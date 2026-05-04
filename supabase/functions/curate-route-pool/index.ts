import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  cellKey,
  CurationCandidate,
  CurationPoolRoute,
  CurationRouteCell,
  deriveCoverageStatus,
  qualityTierFor,
  RatingFeedback,
  shouldDemoteVerifiedRoute,
  shouldPromoteCandidate,
  summarizeRatings,
  weeklyRotationScore,
} from "./curation_logic.ts";

type JsonMap = Record<string, unknown>;

interface CurationOptions {
  runId?: string;
  dryRun?: boolean;
  candidateLimit?: number;
  poolLimit?: number;
  ratingLimit?: number;
}

interface CoverageRow {
  id: string;
  country_code: string;
  admin1_name: string;
  admin2_name?: string | null;
  city_cluster: string;
  route_type: string;
  distance_bucket: number;
  style_key: string;
  avoid_highways: boolean;
  min_verified_count?: number;
  target_pool_size?: number;
  max_pool_size?: number;
  acceptable_reserve_limit_percent?: number;
}

interface CurationStats {
  promoted: number;
  demoted: number;
  candidatesScanned: number;
  verifiedScanned: number;
  ratingsScanned: number;
  coverageUpdated: number;
  skippedCandidates: Record<string, number>;
  skippedDemotions: Record<string, number>;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

let supabaseUrl = "";
let serviceKey = "";
let dryRun = false;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }
  if (!isAuthorized(req)) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  let body: JsonMap = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  try {
    const result = await curateRoutePool({
      runId: stringOption(body.run_id),
      dryRun: boolOption(body.dry_run, false),
      candidateLimit: intOption(body.candidate_limit, 500, 1, 2000),
      poolLimit: intOption(body.pool_limit, 2000, 1, 5000),
      ratingLimit: intOption(body.rating_limit, 5000, 1, 20000),
    });
    return jsonResponse(result, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: "curation_failed", message }, 500);
  }
});

export async function curateRoutePool(options: CurationOptions = {}) {
  supabaseUrl = env("SUPABASE_URL");
  serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
  dryRun = options.dryRun ?? false;
  if (!supabaseUrl || !serviceKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.");
  }

  const run = await startRun(options.runId);
  const runId = String(run.id);
  if (run.status === "completed") {
    return {
      run_id: runId,
      dry_run: dryRun,
      idempotent: true,
      stats: run.stats ?? {},
    };
  }

  const stats = createStats();
  try {
    const [candidateRows, poolRows, coverageRows, ratingRows] = await Promise
      .all([
        loadCandidateRows(options.candidateLimit ?? 500),
        loadPoolRows(options.poolLimit ?? 2000),
        loadCoverageRows(),
        loadRatingRows(options.ratingLimit ?? 5000),
      ]);

    stats.candidatesScanned = candidateRows.length;
    stats.verifiedScanned = poolRows.length;
    stats.ratingsScanned = ratingRows.length;

    const ratingsByFingerprint = groupRatings(ratingRows);
    const activePool = poolRows.map(toPoolRoute);
    const activePoolByCell = groupPoolByCell(activePool);
    const existingPoolFingerprints = new Set(
      activePool.map((route) => route.routeFingerprint),
    );
    const coverageByCell = new Map(
      coverageRows.map((coverage) => [cellKey(toCoverageCell(coverage)), coverage]),
    );
    const touchedCells = new Set<string>();

    for (const row of activePool) {
      const summary = summarizeRatings(
        ratingsByFingerprint.get(row.routeFingerprint) ?? [],
        row,
      );
      const score = weeklyRotationScore(row, summary);
      await patchPoolStats(row, summary, score);

      const sameCellRoutes = activePoolByCell.get(cellKey(row)) ?? [];
      const betterAlternativesAvailable = sameCellRoutes.some((candidate) =>
        candidate.routeFingerprint !== row.routeFingerprint &&
        candidate.qualityScore >= row.qualityScore &&
        candidate.isActive
      );
      const decision = shouldDemoteVerifiedRoute(row, summary, {
        betterAlternativesAvailable,
      });
      if (!decision.accepted) {
        increment(stats.skippedDemotions, decision.reason);
        continue;
      }
      await demotePoolRoute(row, decision.reason, runId, summary, score);
      stats.demoted += 1;
      row.isActive = false;
      row.verified = false;
      row.deprecatedAt = new Date().toISOString();
      touchedCells.add(cellKey(row));
    }

    for (const rawCandidate of candidateRows) {
      const candidate = toCandidate(rawCandidate);
      const key = cellKey(candidate);
      const summary = summarizeRatings(
        ratingsByFingerprint.get(candidate.routeFingerprint) ?? [],
        candidate,
      );
      await patchCandidateStats(candidate, summary);

      const coverage = coverageByCell.get(key);
      const activeVerifiedCount = activePool.filter((route) =>
        route.isActive && route.verified && cellKey(route) === key
      ).length;
      const decision = shouldPromoteCandidate(candidate, summary, {
        activeVerifiedCount,
        maxPoolSize: coverage?.max_pool_size ?? 20,
        existingPoolFingerprints,
      });
      if (!decision.accepted) {
        increment(stats.skippedCandidates, decision.reason);
        continue;
      }

      await promoteCandidate(rawCandidate, summary, runId);
      stats.promoted += 1;
      existingPoolFingerprints.add(candidate.routeFingerprint);
      activePool.push(candidateToPool(candidate, summary));
      await markCandidatePromoted(candidate, summary);
      rawCandidate.is_candidate = false;
      rawCandidate.is_verified_pool = true;
      rawCandidate.promoted_to_pool_at = new Date().toISOString();
      touchedCells.add(key);
    }

    for (const key of touchedCells) {
      const coverage = coverageByCell.get(key);
      if (!coverage) continue;
      await refreshCoverage(coverage, activePool, candidateRows);
      stats.coverageUpdated += 1;
    }

    await finishRun(runId, "completed", stats);
    return { run_id: runId, dry_run: dryRun, stats };
  } catch (error) {
    await failRun(runId, error instanceof Error ? error.message : String(error));
    throw error;
  }
}

async function startRun(runId?: string) {
  if (runId) {
    const rows = await rest("route_pool_curation_runs", {
      query: `id=eq.${encodeURIComponent(runId)}&limit=1`,
    }) as JsonMap[];
    if (rows.length > 0) {
      const row = rows[0];
      if (row.status !== "completed" && !dryRun) {
        await rest("route_pool_curation_runs", {
          method: "PATCH",
          query: `id=eq.${encodeURIComponent(runId)}`,
          body: {
            status: "running",
            updated_at: new Date().toISOString(),
          },
        });
      }
      return row;
    }
  }
  if (dryRun) {
    return { id: "dry-run", status: "running" };
  }
  const inserted = await rest("route_pool_curation_runs", {
    method: "POST",
    query: "select=id,status",
    headers: { Prefer: "return=representation" },
    body: {
      status: "running",
      requested_at: new Date().toISOString(),
      notes: "Trusted route-pool curation run.",
    },
  }) as JsonMap[];
  return inserted[0];
}

async function loadCandidateRows(limit: number): Promise<JsonMap[]> {
  return await rest("route_pool_candidates", {
    query:
      "is_candidate=eq.true&is_verified_pool=eq.false&promoted_to_pool_at=is.null&demoted_at=is.null" +
      `&limit=${limit}`,
  }) as JsonMap[];
}

async function loadPoolRows(limit: number): Promise<JsonMap[]> {
  return await rest("route_pool", {
    query: `verified=eq.true&is_active=eq.true&limit=${limit}`,
  }) as JsonMap[];
}

async function loadCoverageRows(): Promise<CoverageRow[]> {
  return await rest("route_pool_coverage", {
    query:
      "select=id,country_code,admin1_name,admin2_name,city_cluster,route_type,distance_bucket,style_key,avoid_highways,min_verified_count,target_pool_size,max_pool_size,acceptable_reserve_limit_percent",
  }) as CoverageRow[];
}

async function loadRatingRows(limit: number): Promise<RatingFeedback[]> {
  const rows = await rest("route_ratings", {
    query:
      "select=route_fingerprint,rating,tags,completion_percent,created_at" +
      `&order=created_at.desc&limit=${limit}`,
  }) as JsonMap[];
  return rows.map((row) => ({
    routeFingerprint: String(row.route_fingerprint ?? ""),
    rating: typeof row.rating === "number" ? row.rating : null,
    tags: Array.isArray(row.tags) ? row.tags.map(String) : [],
    completionPercent: typeof row.completion_percent === "number"
      ? row.completion_percent
      : null,
  })).filter((row) => row.routeFingerprint.length > 0);
}

async function patchPoolStats(
  route: CurationPoolRoute,
  summary: ReturnType<typeof summarizeRatings>,
  weeklyScore: number,
): Promise<void> {
  if (dryRun) return;
  await rest("route_pool", {
    method: "PATCH",
    query: `route_fingerprint=eq.${encodeURIComponent(route.routeFingerprint)}`,
    body: {
      average_rating: summary.averageRating,
      rating_count: summary.ratingCount,
      completion_rate: summary.completionRate,
      weekly_rotation_score: weeklyScore,
      updated_at: new Date().toISOString(),
    },
  });
}

async function patchCandidateStats(
  candidate: CurationCandidate,
  summary: ReturnType<typeof summarizeRatings>,
): Promise<void> {
  if (dryRun) return;
  await rest("route_pool_candidates", {
    method: "PATCH",
    query: `route_fingerprint=eq.${encodeURIComponent(candidate.routeFingerprint)}`,
    body: {
      average_rating: summary.averageRating,
      rating_count: summary.ratingCount,
      completion_rate: summary.completionRate,
      candidate_score: weeklyRotationScore(candidateToPool(candidate, summary), summary),
      updated_at: new Date().toISOString(),
    },
  });
}

async function promoteCandidate(
  candidate: JsonMap,
  summary: ReturnType<typeof summarizeRatings>,
  runId: string,
): Promise<void> {
  if (dryRun) return;
  const payload = routePayload(candidate);
  const poolRow = {
    route_region_id: candidate.route_region_id ?? null,
    route_fingerprint: candidate.route_fingerprint,
    title: candidate.title ?? null,
    country_code: candidate.country_code,
    admin1_name: candidate.admin1_name,
    admin2_name: candidate.admin2_name ?? null,
    city_cluster: candidate.city_cluster,
    start_lat: candidate.start_lat,
    start_lng: candidate.start_lng,
    end_lat: null,
    end_lng: null,
    distance_km: candidate.distance_km,
    distance_bucket: candidate.distance_bucket,
    route_type: candidate.route_type,
    style_tags: candidate.style_tags ?? [],
    avoids_highway: candidate.avoid_highways === true,
    has_highway: candidate.has_highway === true,
    quality_score: candidate.quality_score ?? 0,
    shape_score: candidate.shape_score ?? 0,
    user_rating: summary.averageRating,
    rating_count: summary.ratingCount,
    average_rating: summary.averageRating,
    completion_rate: summary.completionRate,
    usage_count: candidate.repeated_success_count ?? 0,
    source: "curated_candidate",
    verified: true,
    is_active: true,
    deprecated_at: null,
    weekly_rotation_score: weeklyRotationScore(toPoolRoute(candidate), summary),
    geometry: candidate.geometry,
    route_payload: {
      ...payload,
      promoted_from_candidate_id: candidate.id ?? null,
      curation_run_id: runId,
      curation_promoted_at: new Date().toISOString(),
    },
  };
  await rest("route_pool", {
    method: "POST",
    query: "on_conflict=route_fingerprint",
    headers: { Prefer: "resolution=merge-duplicates" },
    body: poolRow,
  });
}

async function markCandidatePromoted(
  candidate: CurationCandidate,
  summary: ReturnType<typeof summarizeRatings>,
): Promise<void> {
  if (dryRun) return;
  await rest("route_pool_candidates", {
    method: "PATCH",
    query: `route_fingerprint=eq.${encodeURIComponent(candidate.routeFingerprint)}`,
    body: {
      is_candidate: false,
      is_verified_pool: true,
      promoted_to_pool_at: new Date().toISOString(),
      average_rating: summary.averageRating,
      rating_count: summary.ratingCount,
      completion_rate: summary.completionRate,
      updated_at: new Date().toISOString(),
    },
  });
}

async function demotePoolRoute(
  route: CurationPoolRoute,
  reason: string,
  runId: string,
  summary: ReturnType<typeof summarizeRatings>,
  weeklyScore: number,
): Promise<void> {
  if (dryRun) return;
  await rest("route_pool", {
    method: "PATCH",
    query: `route_fingerprint=eq.${encodeURIComponent(route.routeFingerprint)}`,
    body: {
      is_active: false,
      deprecated_at: new Date().toISOString(),
      average_rating: summary.averageRating,
      rating_count: summary.ratingCount,
      completion_rate: summary.completionRate,
      weekly_rotation_score: weeklyScore,
      route_payload: {
        ...(route.routePayload ?? {}),
        demoted_by_curation_run_id: runId,
        demotion_reason: reason,
        demoted_at: new Date().toISOString(),
      },
      updated_at: new Date().toISOString(),
    },
  });
}

async function refreshCoverage(
  coverage: CoverageRow,
  poolRows: CurationPoolRoute[],
  candidateRows: JsonMap[],
): Promise<void> {
  if (dryRun) return;
  const key = cellKey(toCoverageCell(coverage));
  const verified = poolRows.filter((route) =>
    route.isActive && route.verified && cellKey(route) === key
  );
  const candidates = candidateRows.map(toCandidate).filter((candidate) =>
    candidate.isCandidate !== false &&
    !candidate.promotedToPoolAt &&
    !candidate.demotedAt &&
    cellKey(candidate) === key
  );
  const qualityCounts = verified.reduce(
    (counts, route) => {
      counts[qualityTierFor(route)] += 1;
      return counts;
    },
    { ideal: 0, good: 0, acceptable: 0, rejected: 0 },
  );
  const status = deriveCoverageStatus({
    verifiedCount: verified.length,
    candidateCount: candidates.length,
    idealCount: qualityCounts.ideal,
    goodCount: qualityCounts.good,
    acceptableCount: qualityCounts.acceptable,
    distinctFingerprintCount: new Set(
      verified.map((route) => route.routeFingerprint),
    ).size,
    minVerifiedCount: coverage.min_verified_count ?? 3,
    targetPoolSize: coverage.target_pool_size ?? 8,
    maxPoolSize: coverage.max_pool_size ?? 20,
    acceptableReserveLimitPercent:
      coverage.acceptable_reserve_limit_percent ?? 25,
  });
  await rest("route_pool_coverage", {
    method: "PATCH",
    query: `id=eq.${encodeURIComponent(coverage.id)}`,
    body: {
      current_verified_count: verified.length,
      current_candidate_count: candidates.length,
      ideal_count: qualityCounts.ideal,
      good_count: qualityCounts.good,
      acceptable_count: qualityCounts.acceptable,
      rejected_count: qualityCounts.rejected,
      distinct_fingerprint_count: new Set(
        verified.map((route) => route.routeFingerprint),
      ).size,
      coverage_status: status,
      last_counted_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    },
  });
}

async function finishRun(
  runId: string,
  status: "completed",
  stats: CurationStats,
): Promise<void> {
  if (dryRun || runId === "dry-run") return;
  await rest("route_pool_curation_runs", {
    method: "PATCH",
    query: `id=eq.${encodeURIComponent(runId)}`,
    body: {
      status,
      promoted_count: stats.promoted,
      demoted_count: stats.demoted,
      updated_at: new Date().toISOString(),
      notes:
        `Promoted ${stats.promoted}, demoted ${stats.demoted}; no hard deletes. Stats=${JSON.stringify(stats).slice(0, 900)}`,
    },
  });
}

async function failRun(runId: string, message: string): Promise<void> {
  if (dryRun || runId === "dry-run") return;
  await rest("route_pool_curation_runs", {
    method: "PATCH",
    query: `id=eq.${encodeURIComponent(runId)}`,
    body: {
      status: "failed",
      updated_at: new Date().toISOString(),
      notes: `Curation failed: ${message.slice(0, 700)}`,
    },
  });
}

async function rest(
  path: string,
  options: {
    method?: string;
    query?: string;
    body?: unknown;
    headers?: Record<string, string>;
  } = {},
): Promise<unknown> {
  const url = `${supabaseUrl}/rest/v1/${path}${
    options.query ? `?${options.query}` : ""
  }`;
  const response = await fetch(url, {
    method: options.method ?? "GET",
    headers: {
      apikey: serviceKey,
      authorization: `Bearer ${serviceKey}`,
      "content-type": "application/json",
      ...options.headers,
    },
    body: options.body == null ? undefined : JSON.stringify(options.body),
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`${path} ${response.status}: ${text.slice(0, 500)}`);
  }
  if (response.status === 204) return null;
  const text = await response.text();
  return text.trim().length === 0 ? null : JSON.parse(text);
}

function groupRatings(rows: RatingFeedback[]): Map<string, RatingFeedback[]> {
  const grouped = new Map<string, RatingFeedback[]>();
  for (const row of rows) {
    const list = grouped.get(row.routeFingerprint) ?? [];
    list.push(row);
    grouped.set(row.routeFingerprint, list);
  }
  return grouped;
}

function groupPoolByCell(
  rows: CurationPoolRoute[],
): Map<string, CurationPoolRoute[]> {
  const grouped = new Map<string, CurationPoolRoute[]>();
  for (const row of rows) {
    const key = cellKey(row);
    const list = grouped.get(key) ?? [];
    list.push(row);
    grouped.set(key, list);
  }
  return grouped;
}

function toCandidate(row: JsonMap): CurationCandidate {
  return {
    id: stringOption(row.id),
    routeFingerprint: String(row.route_fingerprint ?? ""),
    countryCode: String(row.country_code ?? "").toUpperCase(),
    admin1Name: String(row.admin1_name ?? ""),
    admin2Name: stringOption(row.admin2_name),
    cityCluster: String(row.city_cluster ?? ""),
    routeType: String(row.route_type ?? "ROUND_TRIP"),
    distanceBucket: numberOption(row.distance_bucket, 0),
    styleKey: String(row.style_key ?? "standard"),
    avoidHighways: row.avoid_highways === true,
    hasHighway: row.has_highway === true,
    qualityScore: numberOption(row.quality_score, 0),
    shapeScore: numberOption(row.shape_score, 0),
    averageRating: nullableNumber(row.average_rating),
    ratingCount: numberOption(row.rating_count, 0),
    completionRate: nullableNumber(row.completion_rate),
    repeatedSuccessCount: numberOption(row.repeated_success_count, 0),
    isCandidate: row.is_candidate !== false,
    isVerifiedPool: row.is_verified_pool === true,
    promotedToPoolAt: stringOption(row.promoted_to_pool_at),
    demotedAt: stringOption(row.demoted_at),
    routePayload: routePayload(row),
  };
}

function toPoolRoute(row: JsonMap): CurationPoolRoute {
  const styleTags = Array.isArray(row.style_tags)
    ? row.style_tags.map(String)
    : [];
  return {
    id: stringOption(row.id),
    routeFingerprint: String(row.route_fingerprint ?? ""),
    countryCode: String(row.country_code ?? "").toUpperCase(),
    admin1Name: String(row.admin1_name ?? ""),
    admin2Name: stringOption(row.admin2_name),
    cityCluster: String(row.city_cluster ?? ""),
    routeType: String(row.route_type ?? "ROUND_TRIP"),
    distanceBucket: numberOption(row.distance_bucket, 0),
    styleKey: styleTags[0] ?? "standard",
    avoidHighways: row.avoids_highway === true,
    hasHighway: row.has_highway === true,
    qualityScore: numberOption(row.quality_score, 0),
    averageRating: nullableNumber(row.average_rating),
    ratingCount: numberOption(row.rating_count, 0),
    completionRate: nullableNumber(row.completion_rate),
    isActive: row.is_active !== false,
    verified: row.verified === true,
    deprecatedAt: stringOption(row.deprecated_at),
    routePayload: routePayload(row),
  };
}

function candidateToPool(
  candidate: CurationCandidate,
  summary: ReturnType<typeof summarizeRatings>,
): CurationPoolRoute {
  return {
    ...candidate,
    averageRating: summary.averageRating,
    ratingCount: summary.ratingCount,
    completionRate: summary.completionRate,
    verified: true,
    isActive: true,
    deprecatedAt: null,
  };
}

function toCoverageCell(row: CoverageRow): CurationRouteCell {
  return {
    countryCode: row.country_code,
    admin1Name: row.admin1_name,
    admin2Name: row.admin2_name,
    cityCluster: row.city_cluster,
    routeType: row.route_type,
    distanceBucket: row.distance_bucket,
    styleKey: row.style_key,
    avoidHighways: row.avoid_highways,
  };
}

function routePayload(row: JsonMap): JsonMap {
  return row.route_payload && typeof row.route_payload === "object" &&
      !Array.isArray(row.route_payload)
    ? row.route_payload as JsonMap
    : {};
}

function createStats(): CurationStats {
  return {
    promoted: 0,
    demoted: 0,
    candidatesScanned: 0,
    verifiedScanned: 0,
    ratingsScanned: 0,
    coverageUpdated: 0,
    skippedCandidates: {},
    skippedDemotions: {},
  };
}

function increment(target: Record<string, number>, key: string): void {
  target[key] = (target[key] ?? 0) + 1;
}

function isAuthorized(req: Request): boolean {
  const bearer = bearerToken(req.headers.get("authorization"));
  const cronSecret = Deno.env.get("ROUTE_POOL_CURATION_CRON_SECRET")?.trim();
  if (cronSecret && constantTimeEquals(req.headers.get("x-cron-secret"), cronSecret)) {
    return true;
  }
  if (cronSecret && constantTimeEquals(bearer, cronSecret)) {
    return true;
  }
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ??
    null;
  return Boolean(serviceRoleKey) && constantTimeEquals(bearer, serviceRoleKey);
}

function bearerToken(value: string | null): string {
  const trimmed = value?.trim() ?? "";
  return trimmed.toLowerCase().startsWith("bearer ")
    ? trimmed.slice("bearer ".length).trim()
    : "";
}

function constantTimeEquals(left: string | null, right: string | null): boolean {
  const a = new TextEncoder().encode(left ?? "");
  const b = new TextEncoder().encode(right ?? "");
  const length = Math.max(a.length, b.length);
  let diff = a.length ^ b.length;
  for (let index = 0; index < length; index += 1) {
    diff |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }
  return diff === 0;
}

function env(name: string): string {
  return Deno.env.get(name)?.trim() ?? "";
}

function intOption(value: unknown, fallback: number, min: number, max: number) {
  const parsed = typeof value === "number" ? value : Number(String(value ?? ""));
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, Math.floor(parsed)));
}

function boolOption(value: unknown, fallback: boolean): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function stringOption(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : undefined;
}

function numberOption(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function nullableNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json; charset=utf-8",
    },
  });
}
