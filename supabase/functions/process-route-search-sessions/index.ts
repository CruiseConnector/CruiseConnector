import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type JsonMap = Record<string, unknown>;
type Bucket = 50 | 75 | 100;

interface SessionRow {
  id: string;
  created_at?: string | null;
  expires_at?: string | null;
  origin_lng: number;
  origin_lat: number;
  distance_bucket: Bucket;
  style_key: string;
  avoid_highways: boolean;
  status: string;
  attempts_count?: number | null;
  mapbox_calls_used?: number | null;
  best_candidate_payload?: JsonMap | null;
  candidate_queue_payload?: unknown[] | null;
  reject_summary?: JsonMap | null;
  locked_until?: string | null;
}

interface RouteRegion {
  id?: string | null;
  country_code: string;
  admin1_name: string;
  admin2_name?: string | null;
  city_cluster: string;
  center_lat: number;
  center_lng: number;
  difficulty_level?: string | null;
}

interface CandidatePayload {
  candidate_id: string;
  route_fingerprint: string;
  previous_route_fingerprints?: string[];
  candidate_family: string;
  planned_coordinates: number[][];
  silent_via_waypoints?: string | null;
  waypoint_indexes?: number[];
  radiuses?: string;
  bearings?: string | null;
  avoid_maneuver_radius_m?: number | null;
  continue_straight?: boolean;
  force_legacy_waypoints?: boolean;
  target_distance_km?: number;
  distance_bucket?: Bucket;
  distance_band_min_km?: number;
  distance_band_max_km?: number;
  predicted_distance_km?: number;
  pre_hydration_quality?: JsonMap;
  shape_score?: number | null;
  style_key?: string;
  requested_style?: string | null;
  delivered_style?: string | null;
  style_downgraded?: boolean;
  avoid_highways?: boolean;
  motorway_policy?: string;
  exclude_params?: string;
  search_stage?: string;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const maxSessionCandidateQueueLength = 10;

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
    const result = await processSessions({
      maxSessions: clampInt(
        body.max_sessions_per_run ?? body.max_sessions,
        2,
        1,
        2,
      ),
      maxHydrations: clampInt(
        body.max_hydrations_per_run ?? body.max_candidates ??
          body.max_mapbox_calls_per_run,
        2,
        1,
        2,
      ),
      searchSessionId: stringValue(body.search_session_id) ??
        stringValue(body.session_id),
    });
    return jsonResponse(result, 200);
  } catch (error) {
    return jsonResponse({
      error: "worker_failed",
      message: error instanceof Error ? error.message : String(error),
    }, 500);
  }
});

async function processSessions(options: {
  maxSessions: number;
  maxHydrations: number;
  searchSessionId: string | null;
}) {
  const sessions = await loadClaimableSessions(
    options.maxSessions,
    options.searchSessionId,
  );
  let processed = 0;
  let found = 0;
  let noRoute = 0;
  let mapboxCallsUsed = 0;
  const results: JsonMap[] = [];

  for (const session of sessions) {
    if (processed >= options.maxSessions) break;
    if (mapboxCallsUsed >= options.maxHydrations) break;
    const claimed = await claimSession(session);
    if (claimed == null) continue;
    const result = await hydrateClaimedSession(claimed);
    processed += 1;
    mapboxCallsUsed += Number(result.mapbox_calls_used ?? 0);
    if (result.found === true) found += 1;
    if (result.finished === true && result.found !== true) noRoute += 1;
    results.push(result);
  }

  return {
    processed_sessions: processed,
    found,
    no_route: noRoute,
    mapbox_calls_used: mapboxCallsUsed,
    results,
  };
}

async function hydrateClaimedSession(session: SessionRow): Promise<JsonMap> {
  const queue = candidateQueue(session);
  const attempt = Math.max(0, session.attempts_count ?? 0);
  const candidate = queue[attempt] ?? null;
  if (candidate == null) {
    await finish(session, "no_route", "candidate_queue_exhausted");
    return {
      search_session_id: session.id,
      found: false,
      finished: true,
      reason: "candidate_queue_exhausted",
    };
  }
  if (!candidateIsValid(candidate)) {
    await rejectOrRetry(
      session,
      "invalid_candidate_payload",
      0,
      candidate,
      queue,
    );
    return {
      search_session_id: session.id,
      found: false,
      finished: false,
      reason: "invalid_candidate_payload",
    };
  }
  if (candidateWasRecentlyShown(candidate)) {
    await rejectOrRetry(
      session,
      "duplicate_previous_fingerprint",
      0,
      candidate,
      queue,
    );
    return {
      search_session_id: session.id,
      found: false,
      finished: false,
      reason: "duplicate_previous_fingerprint",
      mapbox_calls_used: 0,
      candidate_queue_index: attempt,
    };
  }

  const token = env("MAPBOX_ACCESS_TOKEN");
  if (!token) {
    await finish(session, "failed", "mapbox_token_missing");
    return {
      search_session_id: session.id,
      found: false,
      finished: true,
      reason: "mapbox_token_missing",
    };
  }

  const fetchResult = await fetchFullRoute(candidate, session, token);
  const callsUsed = 1;
  if (!fetchResult.route) {
    await rejectOrRetry(
      session,
      fetchResult.reason,
      callsUsed,
      candidate,
      queue,
    );
    return {
      search_session_id: session.id,
      found: false,
      finished: false,
      reason: fetchResult.reason,
      mapbox_calls_used: callsUsed,
      candidate_queue_index: attempt,
    };
  }

  const route = fetchResult.route;
  const display = displayDecision(
    route,
    candidate.distance_bucket ?? session.distance_bucket,
  );
  if (display.reason != null) {
    await rejectOrRetry(session, display.reason, callsUsed, candidate, queue);
    return {
      search_session_id: session.id,
      found: false,
      finished: false,
      reason: display.reason,
      mapbox_calls_used: callsUsed,
      candidate_queue_index: attempt,
    };
  }

  const distanceKm = distanceKmFromRoute(route);
  const band = candidateDistanceBand(candidate, session.distance_bucket);
  if (distanceKm < band.minKm || distanceKm > band.maxKm) {
    const reason = `distance_outside_candidate_band_${distanceKm.toFixed(1)}`;
    await rejectOrRetry(session, reason, callsUsed, candidate, queue);
    return {
      search_session_id: session.id,
      found: false,
      finished: false,
      reason,
      mapbox_calls_used: callsUsed,
      candidate_queue_index: attempt,
    };
  }

  const hasMotorway = routeHasMotorway(route);
  if (session.avoid_highways && hasMotorway) {
    await rejectOrRetry(
      session,
      "motorway_violation",
      callsUsed,
      candidate,
      queue,
    );
    return {
      search_session_id: session.id,
      found: false,
      finished: false,
      reason: "motorway_violation",
      mapbox_calls_used: callsUsed,
      candidate_queue_index: attempt,
    };
  }
  if (rejectVorarlbergRhineBorderIntrusion(session, route)) {
    await rejectOrRetry(
      session,
      "border_intrusion",
      callsUsed,
      candidate,
      queue,
    );
    return {
      search_session_id: session.id,
      found: false,
      finished: false,
      reason: "border_intrusion",
      mapbox_calls_used: callsUsed,
      candidate_queue_index: attempt,
    };
  }

  const totalCalls = (session.mapbox_calls_used ?? 0) + callsUsed;
  const fingerprint = candidate.route_fingerprint ||
    `session_${shortHash(JSON.stringify(route.geometry).slice(0, 12000))}`;
  const qualityTier = qualityTierFromCandidate(candidate);
  const region = await nearestRegionForSession(session);
  const saveResult = await persistFoundRoute({
    session,
    candidate,
    route,
    fingerprint,
    region,
    distanceKm,
    qualityTier,
    shapeScore: shapeScoreFromCandidate(candidate),
    hasMotorway,
  });
  const now = new Date().toISOString();
  const bestRoutePayload = {
    route,
    meta: {
      source: "search_session",
      route_source: "search_session",
      search_session_id: session.id,
      final_geometry_source: "hydrated_worker",
      geometry_source: "mapbox_full",
      final_overview: "full",
      guidance_degraded: true,
      guidance_degraded_reason: "worker_hydrated_persisted_live_candidate",
      final_coordinate_count: display.coordinateCount,
      coordinate_count: display.coordinateCount,
      max_display_segment_m: display.maxSegmentMeters,
      max_segment_m: display.maxSegmentMeters,
      average_segment_m: display.averageSegmentMeters,
      road_snapped_geometry: true,
      quality_tier: qualityTier,
      pre_hydration_quality_tier: String(
        candidate.pre_hydration_quality?.tier ?? qualityTier,
      ),
      route_distance_km: distanceKm,
      target_distance_km: candidate.target_distance_km ??
        session.distance_bucket,
      requested_distance_bucket: session.distance_bucket,
      requested_style_key: canonicalStyleKey(session.style_key),
      requested_style: candidate.requested_style ??
        styleLabel(session.style_key),
      delivered_style: candidate.delivered_style ??
        styleLabel(session.style_key),
      style_downgraded: candidate.style_downgraded === true,
      avoid_highways_requested: session.avoid_highways,
      motorway_policy: session.avoid_highways
        ? "exclude_motorway"
        : "allowed_not_required",
      actual_has_highway: hasMotorway,
      actual_avoids_highway: !hasMotorway,
      mapbox_calls_used: totalCalls,
      mapbox_calls_used_worker: callsUsed,
      candidate_id: candidate.candidate_id,
      candidate_family: candidate.candidate_family,
      candidate_queue_index: attempt,
      worker_invocation_count: attempt + 1,
      predicted_distance_km: candidate.predicted_distance_km ?? null,
      final_distance_km: distanceKm,
      distance_band_min_km: band.minKm,
      distance_band_max_km: band.maxKm,
      silent_via_used: !candidate.force_legacy_waypoints &&
        Boolean(candidate.silent_via_waypoints),
      silent_via_waypoints: candidate.silent_via_waypoints ?? null,
      mapbox_leg_count: Array.isArray(route?.legs) ? route.legs.length : null,
      arrive_maneuver_count: countArriveManeuvers(route),
      candidate_inserted: saveResult.candidateInserted,
      candidate_saved: saveResult.candidateInserted,
      verified_inserted: saveResult.verifiedInserted,
      pool_inserted: saveResult.verifiedInserted,
      route_persisted: saveResult.candidateInserted ||
        saveResult.verifiedInserted,
      candidate_duplicate_fingerprint: saveResult.duplicate,
      candidate_duplicate_source: saveResult.duplicateSource,
      candidate_save_skipped_reason: saveResult.skippedReason,
      candidate_save_failed: saveResult.failed,
      candidate_save_error_reason: saveResult.errorReason,
      route_region_id: region.id ?? null,
      city_cluster: region.city_cluster,
      country_code: region.country_code,
      admin1_name: region.admin1_name,
      admin2_name: region.admin2_name ?? null,
    },
  };

  const rejectSummary: JsonMap = mergeReject(
    session.reject_summary,
    "found",
    candidate,
  );
  rejectSummary.persistence = {
    candidate_inserted: saveResult.candidateInserted,
    verified_inserted: saveResult.verifiedInserted,
    duplicate: saveResult.duplicate,
    duplicate_source: saveResult.duplicateSource,
    skipped_reason: saveResult.skippedReason,
    failed: saveResult.failed,
    error_reason: saveResult.errorReason,
  };
  await patchSession(session.id, {
    status: "found",
    progress_stage: "found",
    attempts_count: attempt + 1,
    mapbox_calls_used: totalCalls,
    best_candidate_payload: candidate,
    best_route_fingerprint: fingerprint,
    best_route_payload: bestRoutePayload,
    reject_summary: rejectSummary,
    last_error: null,
    locked_until: null,
    worker_last_seen_at: now,
    updated_at: now,
  });

  return {
    search_session_id: session.id,
    found: true,
    finished: true,
    route_fingerprint: fingerprint,
    candidate_family: candidate.candidate_family,
    candidate_queue_index: attempt,
    final_distance_km: distanceKm,
    final_coordinate_count: display.coordinateCount,
    max_display_segment_m: display.maxSegmentMeters,
    mapbox_calls_used: callsUsed,
    candidate_inserted: saveResult.candidateInserted,
    verified_inserted: saveResult.verifiedInserted,
    candidate_save_skipped_reason: saveResult.skippedReason,
  };
}

async function persistFoundRoute(args: {
  session: SessionRow;
  candidate: CandidatePayload;
  route: any;
  fingerprint: string;
  region: RouteRegion;
  distanceKm: number;
  qualityTier: string;
  shapeScore: number;
  hasMotorway: boolean;
}): Promise<{
  candidateInserted: boolean;
  verifiedInserted: boolean;
  duplicate: boolean;
  duplicateSource: string | null;
  skippedReason: string | null;
  failed: boolean;
  errorReason: string | null;
}> {
  if (!["ideal", "good", "acceptable"].includes(args.qualityTier)) {
    return skippedSave("quality_tier_not_persistable");
  }
  if (args.session.avoid_highways && args.hasMotorway) {
    return skippedSave("motorway_violation");
  }
  const coordinates = routeCoordinates(args.route);
  if (
    coordinates.length < minDisplayCoordinateCount(args.session.distance_bucket)
  ) {
    return skippedSave("display_geometry_too_sparse");
  }

  const duplicatePool = await routeExists("route_pool", args.fingerprint);
  if (duplicatePool) {
    return {
      candidateInserted: false,
      verifiedInserted: false,
      duplicate: true,
      duplicateSource: "pool",
      skippedReason: "duplicate_fingerprint",
      failed: false,
      errorReason: null,
    };
  }
  const duplicateCandidate = await routeExists(
    "route_pool_candidates",
    args.fingerprint,
  );
  if (duplicateCandidate) {
    return {
      candidateInserted: false,
      verifiedInserted: false,
      duplicate: true,
      duplicateSource: "candidate",
      skippedReason: "duplicate_fingerprint",
      failed: false,
      errorReason: null,
    };
  }

  try {
    if (args.qualityTier === "ideal" || args.qualityTier === "good") {
      await upsertVerifiedRoute(args);
      return {
        candidateInserted: false,
        verifiedInserted: true,
        duplicate: false,
        duplicateSource: null,
        skippedReason: null,
        failed: false,
        errorReason: null,
      };
    }
    await upsertCandidateRoute(args);
    return {
      candidateInserted: true,
      verifiedInserted: false,
      duplicate: false,
      duplicateSource: null,
      skippedReason: null,
      failed: false,
      errorReason: null,
    };
  } catch (error) {
    return {
      candidateInserted: false,
      verifiedInserted: false,
      duplicate: false,
      duplicateSource: null,
      skippedReason: "insert_failed",
      failed: true,
      errorReason: sanitizeError(error),
    };
  }
}

function skippedSave(reason: string) {
  return {
    candidateInserted: false,
    verifiedInserted: false,
    duplicate: false,
    duplicateSource: null,
    skippedReason: reason,
    failed: false,
    errorReason: null,
  };
}

async function upsertVerifiedRoute(args: {
  session: SessionRow;
  candidate: CandidatePayload;
  route: any;
  fingerprint: string;
  region: RouteRegion;
  distanceKm: number;
  qualityTier: string;
  shapeScore: number;
  hasMotorway: boolean;
}): Promise<void> {
  const coordinates = routeCoordinates(args.route);
  const first = coordinates[0];
  const last = coordinates[coordinates.length - 1] ?? first;
  await rest("route_pool", {
    method: "POST",
    query: "on_conflict=route_fingerprint",
    headers: { Prefer: "resolution=merge-duplicates" },
    body: {
      route_fingerprint: args.fingerprint,
      title: `${args.region.city_cluster} ${args.session.distance_bucket} ${
        styleLabel(args.session.style_key)
      } Session`,
      route_region_id: args.region.id ?? null,
      country_code: args.region.country_code,
      admin1_name: args.region.admin1_name,
      admin2_name: args.region.admin2_name ?? null,
      city_cluster: args.region.city_cluster,
      start_lat: first[1],
      start_lng: first[0],
      end_lat: last[1],
      end_lng: last[0],
      distance_km: args.distanceKm,
      distance_bucket: args.session.distance_bucket,
      route_type: "ROUND_TRIP",
      style_tags: [styleLabel(args.session.style_key)],
      avoids_highway: !args.hasMotorway,
      has_highway: args.hasMotorway,
      quality_score: qualityScoreForTier(args.qualityTier),
      shape_score: args.shapeScore,
      source: "mapbox_healing",
      verified: true,
      is_active: true,
      geometry: args.route.geometry,
      route_payload: sessionRoutePayload(args),
    },
  });
}

async function upsertCandidateRoute(args: {
  session: SessionRow;
  candidate: CandidatePayload;
  route: any;
  fingerprint: string;
  region: RouteRegion;
  distanceKm: number;
  qualityTier: string;
  shapeScore: number;
  hasMotorway: boolean;
}): Promise<void> {
  const coordinates = routeCoordinates(args.route);
  const first = coordinates[0];
  await rest("route_pool_candidates", {
    method: "POST",
    query: "on_conflict=route_fingerprint",
    headers: { Prefer: "resolution=merge-duplicates" },
    body: {
      route_region_id: args.region.id ?? null,
      route_fingerprint: args.fingerprint,
      country_code: args.region.country_code,
      admin1_name: args.region.admin1_name,
      admin2_name: args.region.admin2_name ?? null,
      city_cluster: args.region.city_cluster,
      start_lat: first[1],
      start_lng: first[0],
      distance_km: args.distanceKm,
      route_type: "ROUND_TRIP",
      distance_bucket: args.session.distance_bucket,
      style_key: canonicalStyleKey(args.session.style_key),
      style_tags: [styleLabel(args.session.style_key)],
      avoid_highways: !args.hasMotorway,
      has_highway: args.hasMotorway,
      quality_score: qualityScoreForTier(args.qualityTier),
      shape_score: args.shapeScore,
      candidate_source: "bootstrap",
      candidate_region_difficulty: args.region.difficulty_level ?? "normal",
      candidate_locality_score: 100,
      repeated_success_count: 1,
      is_candidate: true,
      is_verified_pool: false,
      candidate_score: qualityScoreForTier(args.qualityTier),
      geometry: args.route.geometry,
      route_payload: sessionRoutePayload(args),
    },
  });
}

function sessionRoutePayload(args: {
  session: SessionRow;
  candidate: CandidatePayload;
  qualityTier: string;
  distanceKm: number;
  route: any;
}) {
  return {
    source: "process_route_search_sessions",
    route_source: "search_session",
    final_geometry_source: "hydrated_worker",
    geometry_source: "mapbox_full",
    quality_tier: args.qualityTier,
    search_session_id: args.session.id,
    candidate_id: args.candidate.candidate_id,
    candidate_family: args.candidate.candidate_family,
    target_distance_km: args.candidate.target_distance_km ??
      args.session.distance_bucket,
    route_distance_km: args.distanceKm,
    generated_at: new Date().toISOString(),
  };
}

async function loadClaimableSessions(
  limit: number,
  sessionId: string | null,
): Promise<SessionRow[]> {
  const query = new URLSearchParams({
    select: "*",
    order: "created_at.asc",
    limit: String(Math.max(1, limit)),
  });
  if (sessionId != null) {
    query.set("id", `eq.${sessionId}`);
  } else {
    query.append("status", "in.(queued,running,hydrating)");
    query.append("route_type", "eq.ROUND_TRIP");
    query.append("expires_at", `gt.${new Date().toISOString()}`);
  }
  const rows = await rest<SessionRow[]>("route_search_sessions", { query });
  const now = Date.now();
  return rows.filter((session) => {
    if (sessionId != null) return true;
    if (session.status !== "hydrating") return true;
    const lockedUntil = session.locked_until == null
      ? 0
      : Date.parse(session.locked_until);
    return !Number.isFinite(lockedUntil) || lockedUntil <= now;
  });
}

async function claimSession(session: SessionRow): Promise<SessionRow | null> {
  const now = new Date().toISOString();
  const rows = await rest<SessionRow[]>("route_search_sessions", {
    method: "PATCH",
    query: `id=eq.${
      encodeURIComponent(session.id)
    }&status=in.(queued,running,hydrating)&select=*`,
    headers: { Prefer: "return=representation" },
    body: {
      status: "hydrating",
      progress_stage: "worker_hydrating",
      worker_last_seen_at: now,
      locked_until: new Date(Date.now() + 2 * 60_000).toISOString(),
      updated_at: now,
    },
  });
  return rows[0] ?? null;
}

function candidateQueue(session: SessionRow): CandidatePayload[] {
  const queue = Array.isArray(session.candidate_queue_payload)
    ? session.candidate_queue_payload
      .map(candidateFromUnknown)
      .filter((candidate): candidate is CandidatePayload => candidate != null)
    : [];
  if (queue.length > 0) return queue.slice(0, maxSessionCandidateQueueLength);
  const best = candidateFromUnknown(session.best_candidate_payload);
  return best == null ? [] : [best];
}

function candidateFromUnknown(value: unknown): CandidatePayload | null {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  const record = value as JsonMap;
  const planned = Array.isArray(record.planned_coordinates)
    ? record.planned_coordinates
      .map((point) =>
        Array.isArray(point) && point.length >= 2
          ? [Number(point[0]), Number(point[1])]
          : null
      )
      .filter((point): point is number[] =>
        Array.isArray(point) &&
        Number.isFinite(point[0]) &&
        Number.isFinite(point[1])
      )
    : [];
  return {
    candidate_id: String(record.candidate_id ?? ""),
    route_fingerprint: String(record.route_fingerprint ?? ""),
    previous_route_fingerprints:
      Array.isArray(record.previous_route_fingerprints)
        ? record.previous_route_fingerprints
          .map((value) => typeof value === "string" ? value.trim() : "")
          .filter((value) => value.length > 0)
          .slice(0, 10)
        : [],
    candidate_family: String(record.candidate_family ?? "unknown"),
    planned_coordinates: planned,
    silent_via_waypoints: typeof record.silent_via_waypoints === "string"
      ? record.silent_via_waypoints
      : null,
    waypoint_indexes: Array.isArray(record.waypoint_indexes)
      ? record.waypoint_indexes.map(Number).filter(Number.isFinite)
      : undefined,
    radiuses: typeof record.radiuses === "string" ? record.radiuses : undefined,
    bearings: typeof record.bearings === "string" ? record.bearings : null,
    avoid_maneuver_radius_m: numberOrUndefined(record.avoid_maneuver_radius_m),
    continue_straight: record.continue_straight !== false,
    force_legacy_waypoints: record.force_legacy_waypoints === true,
    target_distance_km: numberOrUndefined(record.target_distance_km),
    distance_bucket: bucketOrUndefined(record.distance_bucket),
    distance_band_min_km: numberOrUndefined(record.distance_band_min_km),
    distance_band_max_km: numberOrUndefined(record.distance_band_max_km),
    predicted_distance_km: numberOrUndefined(record.predicted_distance_km),
    pre_hydration_quality: isJsonMap(record.pre_hydration_quality)
      ? record.pre_hydration_quality
      : {},
    shape_score: typeof record.shape_score === "number" &&
        Number.isFinite(record.shape_score)
      ? record.shape_score
      : null,
    style_key: typeof record.style_key === "string"
      ? record.style_key
      : undefined,
    requested_style: typeof record.requested_style === "string"
      ? record.requested_style
      : null,
    delivered_style: typeof record.delivered_style === "string"
      ? record.delivered_style
      : null,
    style_downgraded: record.style_downgraded === true,
    avoid_highways: record.avoid_highways === true,
    motorway_policy: typeof record.motorway_policy === "string"
      ? record.motorway_policy
      : undefined,
    exclude_params: typeof record.exclude_params === "string"
      ? record.exclude_params
      : undefined,
    search_stage: typeof record.search_stage === "string"
      ? record.search_stage
      : undefined,
  };
}

function candidateWasRecentlyShown(candidate: CandidatePayload): boolean {
  const fingerprint = candidate.route_fingerprint.trim().toLowerCase();
  if (fingerprint.length === 0) return false;
  return (candidate.previous_route_fingerprints ?? []).some((previous) =>
    previous.trim().toLowerCase() === fingerprint
  );
}

function candidateIsValid(candidate: CandidatePayload): boolean {
  return candidate.planned_coordinates.length >= 2 &&
    candidate.planned_coordinates.every((point) =>
      point.length >= 2 &&
      Number.isFinite(point[0]) &&
      Number.isFinite(point[1]) &&
      Math.abs(point[0]) <= 180 &&
      Math.abs(point[1]) <= 90
    );
}

async function fetchFullRoute(
  candidate: CandidatePayload,
  session: SessionRow,
  token: string,
): Promise<{ route: any | null; reason: string }> {
  const coordinates = candidate.planned_coordinates
    .map((point) => `${point[0]},${point[1]}`)
    .join(";");
  const params = new URLSearchParams({
    access_token: token,
    geometries: "geojson",
    overview: "full",
    steps: "true",
    language: "de",
    continue_straight: String(candidate.continue_straight !== false),
    alternatives: "false",
  });
  const exclude = applyAvoidHighwaysExcludes(
    candidate.exclude_params ?? "",
    session.avoid_highways,
  );
  if (exclude.trim().length > 0) params.set("exclude", exclude.trim());
  params.set("radiuses", validRadiuses(candidate));
  if (
    candidate.bearings != null &&
    candidate.bearings.split(";").length ===
      candidate.planned_coordinates.length
  ) {
    params.set("bearings", candidate.bearings);
  }
  if (
    typeof candidate.avoid_maneuver_radius_m === "number" &&
    Number.isFinite(candidate.avoid_maneuver_radius_m)
  ) {
    params.set(
      "avoid_maneuver_radius",
      String(Math.max(
        1,
        Math.min(1000, Math.round(candidate.avoid_maneuver_radius_m)),
      )),
    );
  }
  if (!candidate.force_legacy_waypoints) {
    const waypointString = candidate.silent_via_waypoints ??
      (candidate.planned_coordinates.length > 2
        ? `0;${candidate.planned_coordinates.length - 1}`
        : null);
    if (waypointString != null && waypointString.trim().length > 0) {
      params.set("waypoints", waypointString);
    }
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetch(
      `https://api.mapbox.com/directions/v5/mapbox/driving/${coordinates}?${params}`,
      { signal: controller.signal },
    );
    if (!response.ok) {
      return { route: null, reason: `mapbox_http_${response.status}` };
    }
    const data = await response.json();
    const route = Array.isArray(data?.routes) ? data.routes[0] : null;
    return route == null
      ? { route: null, reason: "mapbox_no_route" }
      : { route, reason: "ok" };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      route: null,
      reason: message.toLowerCase().includes("abort")
        ? "mapbox_timeout"
        : "mapbox_network_error",
    };
  } finally {
    clearTimeout(timeoutId);
  }
}

function validRadiuses(candidate: CandidatePayload): string {
  if (
    candidate.radiuses != null &&
    candidate.radiuses.split(";").length ===
      candidate.planned_coordinates.length
  ) {
    return candidate.radiuses;
  }
  return candidate.planned_coordinates
    .map((_, index) =>
      index === 0 || index === candidate.planned_coordinates.length - 1
        ? "1200"
        : "4500"
    )
    .join(";");
}

function applyAvoidHighwaysExcludes(
  exclude: string,
  avoidHighways: boolean,
): string {
  const parts = exclude
    .split(",")
    .map((part) => part.trim())
    .filter((part) => part.length > 0);
  if (avoidHighways && !parts.includes("motorway")) {
    parts.push("motorway");
  }
  return Array.from(new Set(parts)).join(",");
}

async function rejectOrRetry(
  session: SessionRow,
  reason: string,
  callsUsed: number,
  candidate: CandidatePayload,
  queue: CandidatePayload[],
): Promise<void> {
  const attempts = Math.max(0, session.attempts_count ?? 0) + 1;
  const exhausted = attempts >= Math.max(1, queue.length);
  await patchSession(session.id, {
    status: exhausted ? "no_route" : "queued",
    progress_stage: exhausted ? "no_route" : "queued_next_candidate",
    attempts_count: attempts,
    mapbox_calls_used: (session.mapbox_calls_used ?? 0) + callsUsed,
    best_candidate_payload: candidate,
    last_error: reason,
    reject_summary: mergeReject(session.reject_summary, reason, candidate),
    locked_until: null,
    worker_last_seen_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  });
}

async function finish(
  session: SessionRow,
  status: "no_route" | "failed",
  reason: string,
): Promise<void> {
  await patchSession(session.id, {
    status,
    progress_stage: status,
    last_error: reason,
    locked_until: null,
    worker_last_seen_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  });
}

function displayDecision(route: any, bucket: Bucket) {
  const stats = geometryStats(route?.geometry?.coordinates);
  if (stats.coordinateCount < minDisplayCoordinateCount(bucket)) {
    return {
      ...stats,
      reason: `display_geometry_coords_${stats.coordinateCount}`,
    };
  }
  if ((stats.maxSegmentMeters ?? 0) > (bucket === 100 ? 2500 : 2000)) {
    return {
      ...stats,
      reason: `display_geometry_max_segment_${stats.maxSegmentMeters}`,
    };
  }
  if ((stats.averageSegmentMeters ?? 0) > 900) {
    return {
      ...stats,
      reason: `display_geometry_avg_segment_${stats.averageSegmentMeters}`,
    };
  }
  return { ...stats, reason: null };
}

function minDisplayCoordinateCount(bucket: Bucket): number {
  if (bucket === 50) return 80;
  if (bucket === 75) return 120;
  return 160;
}

function geometryStats(raw: unknown) {
  const points = Array.isArray(raw)
    ? raw.filter((p): p is [number, number] =>
      Array.isArray(p) &&
      typeof p[0] === "number" &&
      typeof p[1] === "number" &&
      Number.isFinite(p[0]) &&
      Number.isFinite(p[1])
    )
    : [];
  if (points.length < 2) {
    return {
      coordinateCount: points.length,
      maxSegmentMeters: null,
      averageSegmentMeters: null,
    };
  }
  let total = 0;
  let max = 0;
  for (let i = 1; i < points.length; i += 1) {
    const meters = distanceMeters(
      { longitude: points[i - 1][0], latitude: points[i - 1][1] },
      { longitude: points[i][0], latitude: points[i][1] },
    );
    total += meters;
    max = Math.max(max, meters);
  }
  return {
    coordinateCount: points.length,
    maxSegmentMeters: Number(max.toFixed(1)),
    averageSegmentMeters: Number((total / (points.length - 1)).toFixed(1)),
  };
}

function candidateDistanceBand(candidate: CandidatePayload, bucket: Bucket) {
  if (
    typeof candidate.distance_band_min_km === "number" &&
    typeof candidate.distance_band_max_km === "number" &&
    candidate.distance_band_max_km > candidate.distance_band_min_km
  ) {
    return {
      minKm: candidate.distance_band_min_km,
      maxKm: candidate.distance_band_max_km,
    };
  }
  if (bucket === 50) return { minKm: 42, maxKm: 65 };
  if (bucket === 75) return { minKm: 62, maxKm: 90 };
  return { minKm: 85, maxKm: 118 };
}

function distanceKmFromRoute(route: any): number {
  const raw = typeof route?.distance === "number" ? route.distance : 0;
  return raw > 1000 ? Number((raw / 1000).toFixed(1)) : Number(raw.toFixed(1));
}

function routeHasMotorway(route: any): boolean {
  const text = JSON.stringify(route?.legs ?? []).toLowerCase();
  return text.includes("motorway") || text.includes("autobahn");
}

function qualityTierFromCandidate(candidate: CandidatePayload): string {
  const tier = String(candidate.pre_hydration_quality?.tier ?? "acceptable");
  return ["ideal", "good", "acceptable"].includes(tier) ? tier : "acceptable";
}

function countArriveManeuvers(route: any): number | null {
  if (!Array.isArray(route?.legs)) return null;
  let count = 0;
  for (const leg of route.legs) {
    if (!Array.isArray(leg?.steps)) continue;
    for (const step of leg.steps) {
      const maneuverType = String(step?.maneuver?.type ?? "").toLowerCase();
      if (maneuverType === "arrive" || maneuverType === "arrive waypoint") {
        count += 1;
      }
    }
  }
  return count;
}

function distanceMeters(
  a: { latitude: number; longitude: number },
  b: { latitude: number; longitude: number },
): number {
  const radius = 6371000;
  const dLat = (b.latitude - a.latitude) * Math.PI / 180;
  const dLon = (b.longitude - a.longitude) * Math.PI / 180;
  const lat1 = a.latitude * Math.PI / 180;
  const lat2 = b.latitude * Math.PI / 180;
  const sinDLat = Math.sin(dLat / 2);
  const sinDLon = Math.sin(dLon / 2);
  const h = sinDLat * sinDLat +
    Math.cos(lat1) * Math.cos(lat2) * sinDLon * sinDLon;
  return 2 * radius * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function mergeReject(
  current: JsonMap | null | undefined,
  reason: string,
  candidate: CandidatePayload,
) {
  const rejectReasons = current?.reject_reasons != null &&
      typeof current.reject_reasons === "object"
    ? { ...(current.reject_reasons as Record<string, unknown>) }
    : {};
  rejectReasons[reason] = Number(rejectReasons[reason] ?? 0) + 1;
  return {
    ...(current ?? {}),
    reject_reasons: rejectReasons,
    last_candidate_id: candidate.candidate_id,
    last_candidate_family: candidate.candidate_family,
    last_candidate_predicted_distance_km: candidate.predicted_distance_km ??
      null,
    updated_at: new Date().toISOString(),
  };
}

function canonicalStyleKey(styleKey: string): string {
  const normalized = styleKey.trim().toLowerCase().replace(/[^a-z0-9]+/g, "_")
    .replace(/_+/g, "_").replace(/^_|_$/g, "");
  if (normalized === "sport" || normalized === "sport_mode") {
    return "sport_mode";
  }
  if (
    normalized === "kurvenjagd" || normalized === "kurvenreich" ||
    normalized === "curvy" || normalized === "curves" ||
    normalized === "alpenstrassen" || normalized === "alpenstrasse" ||
    normalized === "alpenstra_en"
  ) {
    return "kurvenjagd";
  }
  return normalized || "sport_mode";
}

function styleLabel(styleKey: string): string {
  const canonical = canonicalStyleKey(styleKey);
  if (canonical === "kurvenjagd") return "Kurvenjagd";
  if (canonical === "abendrunde") return "Abendrunde";
  if (canonical === "entdecker") return "Entdecker";
  return "Sport Mode";
}

function routeCoordinates(route: any): number[][] {
  return Array.isArray(route?.geometry?.coordinates)
    ? route.geometry.coordinates.filter((point: unknown): point is number[] =>
      Array.isArray(point) &&
      point.length >= 2 &&
      typeof point[0] === "number" &&
      typeof point[1] === "number" &&
      Number.isFinite(point[0]) &&
      Number.isFinite(point[1])
    )
    : [];
}

function rejectVorarlbergRhineBorderIntrusion(
  session: SessionRow,
  route: any,
): boolean {
  const inVorarlbergRhineValley = session.origin_lat >= 47.18 &&
    session.origin_lat <= 47.46 &&
    session.origin_lng >= 9.55 &&
    session.origin_lng <= 9.80;
  if (!inVorarlbergRhineValley) return false;
  const coordinates = routeCoordinates(route);
  let foreignCorridorPoints = 0;
  for (const [lng, lat] of coordinates) {
    if (
      lat >= 47.05 && lat <= 47.58 &&
      (lng < 9.53 || (lat >= 47.30 && lat <= 47.52 && lng < 9.61))
    ) {
      foreignCorridorPoints += 1;
    }
  }
  return foreignCorridorPoints >= Math.max(4, coordinates.length * 0.03);
}

function shapeScoreFromCandidate(candidate: CandidatePayload): number {
  const direct = Number(candidate.shape_score);
  if (Number.isFinite(direct)) return clampNumber(direct, 0, 100);
  const shapeMetrics = isJsonMap(candidate.pre_hydration_quality?.shape_metrics)
    ? candidate.pre_hydration_quality.shape_metrics
    : {};
  const loopness = Number(shapeMetrics.loopness_score);
  if (Number.isFinite(loopness)) return clampNumber(loopness, 0, 100);
  const score = Number(candidate.pre_hydration_quality?.score);
  if (Number.isFinite(score)) return clampNumber(score, 0, 100);
  return qualityScoreForTier(qualityTierFromCandidate(candidate));
}

function qualityScoreForTier(tier: string): number {
  if (tier === "ideal") return 96;
  if (tier === "good") return 88;
  if (tier === "acceptable") return 78;
  return 0;
}

function clampNumber(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

async function nearestRegionForSession(
  session: SessionRow,
): Promise<RouteRegion> {
  const rows = await rest<RouteRegion[]>("route_regions", {
    query: new URLSearchParams({
      select:
        "id,country_code,admin1_name,admin2_name,city_cluster,center_lat,center_lng,difficulty_level",
      limit: "200",
    }),
  });
  const origin = {
    latitude: session.origin_lat,
    longitude: session.origin_lng,
  };
  const candidates = rows
    .filter((region) =>
      Number.isFinite(region.center_lat) && Number.isFinite(region.center_lng)
    )
    .map((region) => ({
      region,
      distanceKm: distanceMeters(origin, {
        latitude: region.center_lat,
        longitude: region.center_lng,
      }) / 1000,
    }))
    .sort((a, b) => a.distanceKm - b.distanceKm);
  return candidates[0]?.region ?? {
    country_code: "AT",
    admin1_name: "Vorarlberg",
    admin2_name: null,
    city_cluster: "interactive_roundtrip",
    center_lat: session.origin_lat,
    center_lng: session.origin_lng,
    difficulty_level: "normal",
  };
}

async function routeExists(
  table: "route_pool" | "route_pool_candidates",
  fingerprint: string,
): Promise<boolean> {
  if (!fingerprint.trim()) return false;
  const rows = await rest<JsonMap[]>(table, {
    query: new URLSearchParams({
      select: "route_fingerprint",
      route_fingerprint: `eq.${fingerprint}`,
      limit: "1",
    }),
  });
  return rows.length > 0;
}

function sanitizeError(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return message
    .replace(/Bearer\s+[A-Za-z0-9._-]+/g, "Bearer <redacted>")
    .replace(/access_token=[^&\s]+/g, "access_token=<redacted>")
    .slice(0, 220);
}

async function patchSession(id: string, patch: JsonMap) {
  await rest("route_search_sessions", {
    method: "PATCH",
    query: `id=eq.${encodeURIComponent(id)}`,
    body: patch,
  });
}

async function rest<T = unknown>(
  table: string,
  options: {
    method?: "GET" | "POST" | "PATCH";
    query?: URLSearchParams | string;
    body?: unknown;
    headers?: Record<string, string>;
  } = {},
): Promise<T> {
  const query = options.query
    ? typeof options.query === "string"
      ? options.query
      : options.query.toString()
    : "";
  const key = serviceKey();
  const response = await fetch(
    `${env("SUPABASE_URL").replace(/\/$/, "")}/rest/v1/${table}${
      query ? `?${query}` : ""
    }`,
    {
      method: options.method ?? "GET",
      headers: {
        apikey: key,
        authorization: `Bearer ${key}`,
        "content-type": "application/json",
        accept: "application/json",
        ...(options.headers ?? {}),
      },
      body: options.body == null ? undefined : JSON.stringify(options.body),
    },
  );
  if (!response.ok) {
    throw new Error(
      `rest_${table}_${response.status}:${
        (await response.text()).slice(0, 220)
      }`,
    );
  }
  if (response.status === 204) return undefined as T;
  const text = await response.text();
  return (text.trim() ? JSON.parse(text) : undefined) as T;
}

function isAuthorized(req: Request): boolean {
  const bearer = bearerToken(req.headers.get("authorization"));
  const apiKey = req.headers.get("apikey")?.trim() ?? "";
  const searchSecret = env("ROUTE_SEARCH_SESSION_CRON_SECRET");
  if (
    searchSecret &&
    (constantEquals(bearer, searchSecret) ||
      constantEquals(req.headers.get("x-cron-secret"), searchSecret))
  ) {
    return true;
  }
  const healingSecret = env("ROUTE_POOL_HEALING_CRON_SECRET");
  if (
    healingSecret &&
    (constantEquals(bearer, healingSecret) ||
      constantEquals(req.headers.get("x-cron-secret"), healingSecret))
  ) {
    return true;
  }
  const key = serviceKey();
  return key.length > 0 &&
    (constantEquals(bearer, key) || constantEquals(apiKey, key) ||
      secretApiKeys().some((secret) =>
        constantEquals(apiKey, secret) || constantEquals(bearer, secret)
      ));
}

function serviceKey(): string {
  const direct = env("SUPABASE_SERVICE_ROLE_KEY");
  if (direct) return direct;
  const cruiserConnectKey = env("CRUISERCONNECT_SERVICE_ROLE_KEY");
  if (cruiserConnectKey) return cruiserConnectKey;
  return secretApiKeys()[0] ?? "";
}

function secretApiKeys(): string[] {
  return [
    ...parseNamedSecretKeys(Deno.env.get("CRUISERCONNECT_SERVICE_ROLE_KEY")),
    ...parseNamedSecretKeys(Deno.env.get("SUPABASE_SECRET_KEYS")),
    ...parseNamedSecretKeys(Deno.env.get("SUPABASE_SECRET_KEY")),
  ].filter((value, index, all) =>
    value.length > 0 && all.indexOf(value) === index
  );
}

function parseNamedSecretKeys(raw: string | undefined): string[] {
  const trimmed = raw?.trim() ?? "";
  if (trimmed.length === 0) return [];
  if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) return [trimmed];
  try {
    return secretValues(JSON.parse(trimmed));
  } catch {
    return [];
  }
}

function secretValues(value: unknown): string[] {
  if (typeof value === "string") return [value];
  if (Array.isArray(value)) return value.flatMap(secretValues);
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return [
      record.value,
      record.key,
      record.api_key,
      record.apiKey,
      ...Object.values(record).filter((entry) =>
        typeof entry === "string" && entry.startsWith("sb_" + "secret_")
      ),
    ].flatMap(secretValues);
  }
  return [];
}

function bearerToken(value: string | null): string {
  const trimmed = value?.trim() ?? "";
  return trimmed.toLowerCase().startsWith("bearer ")
    ? trimmed.slice("bearer ".length).trim()
    : "";
}

function constantEquals(left: string | null, right: string | null): boolean {
  const a = new TextEncoder().encode(left ?? "");
  const b = new TextEncoder().encode(right ?? "");
  const length = Math.max(a.length, b.length);
  let diff = a.length ^ b.length;
  for (let i = 0; i < length; i += 1) diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return diff === 0;
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

function env(name: string): string {
  return Deno.env.get(name)?.trim() ?? "";
}

function shortHash(value: string): string {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i += 1) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return Math.abs(hash >>> 0).toString(36);
}

function numberOrUndefined(value: unknown): number | undefined {
  const number = Number(value);
  return Number.isFinite(number) ? number : undefined;
}

function bucketOrUndefined(value: unknown): Bucket | undefined {
  const number = Number(value);
  return number === 50 || number === 75 || number === 100 ? number : undefined;
}

function isJsonMap(value: unknown): value is JsonMap {
  return value != null && typeof value === "object" && !Array.isArray(value);
}

function stringValue(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function clampInt(
  value: unknown,
  fallback: number,
  min: number,
  max: number,
): number {
  const parsed = typeof value === "number"
    ? value
    : Number(String(value ?? ""));
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, Math.floor(parsed)));
}
