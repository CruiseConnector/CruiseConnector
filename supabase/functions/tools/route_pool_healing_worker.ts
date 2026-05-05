import {
  buildRouteFingerprintFromRoute,
  evaluateRouteCleanupGate,
  evaluateRouteQuality,
} from "../generate-cruise-route/route_quality.ts";
import type {
  Coordinate,
  RouteMode,
} from "../generate-cruise-route/routing_types.ts";
import {
  applyAvoidHighwaysExcludes,
  calculateDestination,
  normalizeBearingDegrees,
} from "../generate-cruise-route/routing_utils.ts";

type JsonMap = Record<string, unknown>;

interface SeedJob {
  id: string;
  route_region_id?: string | null;
  country_code: string;
  admin1_name: string;
  admin2_name?: string | null;
  city_cluster: string;
  route_type: "ROUND_TRIP" | "POINT_TO_POINT";
  distance_bucket: 50 | 75 | 100;
  style_key: string;
  avoid_highways: boolean;
  status: string;
  difficulty_level?: string;
  hard_region_status?: string;
  priority?: number;
  max_attempts?: number;
  attempt_count?: number;
  failure_count?: number;
  seed_budget_units?: number;
  seed_cooldown_minutes?: number;
  max_mapbox_calls?: number;
  mapbox_calls_used?: number;
  job_kind?: string | null;
  verified_inserted_count?: number;
  candidate_inserted_count?: number;
  daily_attempt_budget?: number;
  monthly_attempt_budget?: number;
  daily_attempt_count?: number;
  monthly_attempt_count?: number;
  budget_window_date?: string;
  budget_window_month?: string;
  daily_mapbox_budget?: number;
  monthly_mapbox_budget?: number;
  daily_mapbox_count?: number;
  monthly_mapbox_count?: number;
  mapbox_budget_window_date?: string;
  mapbox_budget_window_month?: string;
  cooldown_until?: string | null;
  next_retry_at?: string | null;
  started_at?: string | null;
  last_error?: string | null;
}

interface RouteRegion {
  id?: string;
  country_code: string;
  admin1_name: string;
  admin2_name?: string | null;
  city_cluster: string;
  center_lat: number;
  center_lng: number;
  difficulty_level?: string;
  hard_region_status?: string;
  bootstrap_enabled?: boolean;
  curated_seed_preferred?: boolean;
  default_min_verified_count?: number;
  default_target_pool_size?: number;
  default_max_pool_size?: number;
  healthy_threshold?: number;
  thin_threshold?: number;
  seed_budget_units?: number;
  seed_cooldown_minutes?: number;
}

interface HealingCandidatePlan {
  family: string;
  label: string;
  targetDistanceKm: number;
  waypoints: Coordinate[];
  radiuses: string;
  continueStraight: boolean;
}

interface HealingMapboxFetchResult {
  route: any | null;
  routes?: any[];
  outcome: "ok" | "no_route" | "http_error" | "network_error" | "timeout";
  statusCode?: number;
  details?: string;
}

export interface HealingStats {
  processed: number;
  claimed: number;
  completed: number;
  failed: number;
  pausedBudget: number;
  mapboxCallsUsed: number;
  verifiedInserted: number;
  candidatesInserted: number;
  stoppedForRuntime: boolean;
}

export interface RoutePoolHealingWorkerOptions {
  supabaseUrl?: string;
  serviceKey?: string;
  edgeEndpoint?: string;
  functionKey?: string;
  dryRun?: boolean;
  jobLimit?: number;
  maxGlobalMapboxCalls?: number;
  maxVerifiedPerClusterPerRun?: number;
  targetVerifiedPerJob?: number;
  maxRuntimeSeconds?: number;
}

export interface RoutePoolHealingWorkerResult {
  dryRun: boolean;
  limits: {
    jobLimit: number;
    maxGlobalMapboxCalls: number;
    maxVerifiedPerClusterPerRun: number;
    targetVerifiedPerJob: number;
    maxRuntimeSeconds: number;
  };
  stats: HealingStats;
}

let supabaseUrl = "";
let serviceKey = "";
let edgeEndpoint = "";
let functionKey = "";
let dryRun = false;
let jobLimit = 3;
let maxGlobalMapboxCalls = 18;
let maxVerifiedPerClusterPerRun = 3;
let targetVerifiedPerJob = 2;
let maxJobsToFetch = 9;
let maxRuntimeMs = 90_000;
let runStartedAt = 0;
let stats = createHealingStats();

export async function processRouteSeedJobs(
  options: RoutePoolHealingWorkerOptions = {},
): Promise<RoutePoolHealingWorkerResult> {
  supabaseUrl = options.supabaseUrl ?? env("SUPABASE_URL");
  serviceKey = options.serviceKey ??
    (env("SUPABASE_SERVICE_ROLE_KEY") || env("SUPABASE_ANON_KEY"));
  edgeEndpoint = options.edgeEndpoint ??
    `${supabaseUrl}/functions/v1/generate-cruise-route`;
  functionKey = options.functionKey ?? (env("SUPABASE_FUNCTION_KEY") ||
    serviceKey);
  dryRun = options.dryRun ?? false;
  jobLimit = clampInt(options.jobLimit, 3, 1, 3);
  maxGlobalMapboxCalls = clampInt(options.maxGlobalMapboxCalls, 18, 1, 20);
  maxVerifiedPerClusterPerRun = clampInt(
    options.maxVerifiedPerClusterPerRun,
    3,
    1,
    5,
  );
  targetVerifiedPerJob = clampInt(options.targetVerifiedPerJob, 2, 1, 3);
  const maxRuntimeSeconds = clampInt(options.maxRuntimeSeconds, 90, 30, 120);
  maxRuntimeMs = maxRuntimeSeconds * 1000;
  maxJobsToFetch = Math.max(jobLimit * 3, jobLimit);
  runStartedAt = Date.now();
  stats = createHealingStats();

  if (!supabaseUrl || !serviceKey || !functionKey) {
    throw new Error(
      "Missing SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY/SUPABASE_ANON_KEY.",
    );
  }

  const jobs = await loadClaimableJobs();
  for (const job of jobs) {
    if (stats.processed >= jobLimit) break;
    if (stats.mapboxCallsUsed >= maxGlobalMapboxCalls) break;
    if (runtimeExceeded()) {
      stats.stoppedForRuntime = true;
      break;
    }
    if (!isJobRunnable(job)) continue;

    const claimed = await claimJob(job);
    if (!claimed) continue;
    stats.claimed += 1;
    stats.processed += 1;

    try {
      await processJob(claimed);
    } catch (error) {
      await failJob(claimed, errorMessage(error), true);
    }
  }

  return {
    dryRun,
    limits: {
      jobLimit,
      maxGlobalMapboxCalls,
      maxVerifiedPerClusterPerRun,
      targetVerifiedPerJob,
      maxRuntimeSeconds,
    },
    stats,
  };
}

if (import.meta.main) {
  const result = await processRouteSeedJobs({
    dryRun: Deno.args.includes("--dry-run"),
    jobLimit: intArg("--limit=", 3),
    maxGlobalMapboxCalls: intArg("--max-mapbox-calls=", 18),
    maxVerifiedPerClusterPerRun: intArg("--max-verified-per-cluster=", 3),
    targetVerifiedPerJob: intArg("--target-verified-per-job=", 2),
    maxRuntimeSeconds: intArg("--max-runtime-seconds=", 90),
    edgeEndpoint: arg("--endpoint="),
  });
  console.log(JSON.stringify(result, null, 2));
}

function createHealingStats(): HealingStats {
  return {
    processed: 0,
    claimed: 0,
    completed: 0,
    failed: 0,
    pausedBudget: 0,
    mapboxCallsUsed: 0,
    verifiedInserted: 0,
    candidatesInserted: 0,
    stoppedForRuntime: false,
  };
}

async function processJob(job: SeedJob): Promise<void> {
  if (job.route_type !== "ROUND_TRIP") {
    await failJob(job, "unsupported_route_type_for_region_healing", false);
    return;
  }

  const region = await loadRegionForJob(job);
  if (!region) {
    await failJob(job, "route_region_missing", false);
    return;
  }
  const userDemandLearningJob = job.job_kind === "user_demand_learning";
  if (region.bootstrap_enabled === false && !userDemandLearningJob) {
    await markCuratedNeeded(job, region, "bootstrap_disabled");
    return;
  }
  if (
    region.difficulty_level === "hard" &&
    (region.curated_seed_preferred === true ||
      region.hard_region_status === "curated_needed") &&
    !userDemandLearningJob
  ) {
    await markCuratedNeeded(job, region, "hard_region_curated_needed");
    return;
  }

  const remainingBudget = remainingMapboxBudget(job);
  if (remainingBudget <= 0) {
    await pauseJobForBudget(job, "job_budget_exhausted");
    return;
  }

  const maxCallsForJob = Math.min(
    remainingBudget,
    Math.max(0, job.max_mapbox_calls ?? 8) -
      Math.max(0, job.mapbox_calls_used ?? 0),
    maxGlobalMapboxCalls - stats.mapboxCallsUsed,
  );
  if (maxCallsForJob <= 0) {
    await pauseJobForBudget(job, "global_budget_exhausted");
    return;
  }

  let verifiedInserted = 0;
  let candidatesInserted = 0;
  let callsUsed = 0;
  let lastFailure = "no_candidate_generated";
  let verifiedCapacityRemaining = await verifiedCapacityRemainingForCell(
    job,
    region,
  );
  const start = {
    latitude: region.center_lat,
    longitude: region.center_lng,
  };

  for (let attempt = 0; attempt < maxCallsForJob; attempt += 1) {
    if (verifiedInserted >= targetVerifiedPerJob) break;
    if (stats.verifiedInserted >= maxVerifiedPerClusterPerRun) break;
    if (callsUsed >= maxCallsForJob) break;
    if (runtimeExceeded()) {
      stats.stoppedForRuntime = true;
      break;
    }

    const planAttempt = Math.max(0, job.mapbox_calls_used ?? 0) + attempt;
    const response = await callHealingCandidateGenerator(
      job,
      region,
      start,
      planAttempt,
    );
    if (!response.ok) {
      callsUsed += 1;
      stats.mapboxCallsUsed += 1;
      lastFailure = response.reason;
      continue;
    }
    const callCost = mapboxCallsFromMeta(response.meta);
    callsUsed += callCost;
    stats.mapboxCallsUsed += callCost;

    const route = response.route;
    const decision = evaluateGeneratedRoute(job, route, start);
    if (!decision.acceptable) {
      const family = typeof response.meta.healing_family === "string"
        ? `${response.meta.healing_family}_`
        : "";
      lastFailure = `${family}${decision.reason}`;
      continue;
    }

    const fingerprint = `healing_${shortHash(decision.fingerprint)}`;
    const existingPoolRoute = await routeExists("route_pool", fingerprint);
    const existingCandidate = await routeExists(
      "route_pool_candidates",
      fingerprint,
    );
    if (existingPoolRoute || existingCandidate) {
      lastFailure = "duplicate_fingerprint";
      continue;
    }

    if (decision.verified && verifiedCapacityRemaining > 0) {
      const inserted = await upsertVerifiedRoute({
        job,
        region,
        route,
        fingerprint,
        decision,
      });
      if (inserted) {
        verifiedInserted += 1;
        verifiedCapacityRemaining -= 1;
        stats.verifiedInserted += 1;
      }
    } else {
      if (decision.verified) {
        lastFailure = "max_pool_size_reached_candidate_staged";
      }
      const inserted = await upsertCandidateRoute({
        job,
        region,
        route,
        fingerprint,
        decision,
      });
      if (inserted) {
        candidatesInserted += 1;
        stats.candidatesInserted += 1;
      }
    }
  }

  await refreshCoverage(job, region);
  if (verifiedInserted > 0) {
    await completeJob(job, {
      callsUsed,
      verifiedInserted,
      candidatesInserted,
      reason: "verified_inserted",
    });
    return;
  }
  if (candidatesInserted > 0) {
    await cooldownJobAfterCandidateOnly(job, {
      callsUsed,
      candidatesInserted,
      reason: "candidate_inserted_no_verified",
    });
    return;
  }
  await failJob(job, lastFailure, true, callsUsed);
}

async function callRouteGenerator(
  job: SeedJob,
  region: RouteRegion,
  start: Coordinate,
  attempt: number,
): Promise<
  { ok: true; route: any; meta: JsonMap } | {
    ok: false;
    reason: string;
  }
> {
  const style = styleLabel(job.style_key);
  const randomSeed = stableNumber(`${job.id}|${attempt}|${Date.now()}`);
  const styleProfile = styleProfileFor(job.style_key);
  const body = {
    request_id: `route_pool_healing_${job.id}_${attempt + 1}`,
    route_type: job.route_type,
    planning_type: "Zufall",
    startLocation: start,
    targetDistance: targetDistanceFor(job.distance_bucket, attempt),
    mode: style,
    randomSeed,
    avoid_highways: job.avoid_highways,
    continue_straight: true,
    direction_hint: randomSeed % 360,
    route_variant_hint: `healing-${job.id}-${attempt}`,
    route_fingerprint_hint: `healing-${job.id}-${attempt}-${randomSeed}`,
    max_candidate_attempts: job.distance_bucket === 50 ? 5 : 6,
    style_profile: styleProfile,
    waypoint_shape_factor: job.style_key === "kurvenjagd" ? 0.95 : 1.85,
    zigzag_waypoints: job.style_key === "kurvenjagd",
  };
  const response = await fetch(edgeEndpoint, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json",
      apikey: functionKey,
      authorization: `Bearer ${functionKey}`,
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    let reason = `http_${response.status}`;
    try {
      const error = await response.json();
      reason = String(error?.code ?? error?.error ?? reason);
    } catch {
      // Keep status reason.
    }
    return { ok: false, reason };
  }
  const data = await response.json();
  if (!data?.route?.geometry?.coordinates?.length) {
    return { ok: false, reason: String(data?.code ?? "missing_geometry") };
  }
  return { ok: true, route: data.route, meta: data.meta ?? {} };
}

async function callHealingCandidateGenerator(
  job: SeedJob,
  region: RouteRegion,
  start: Coordinate,
  attempt: number,
): Promise<
  { ok: true; route: any; meta: JsonMap } | {
    ok: false;
    reason: string;
  }
> {
  const accessToken = env("MAPBOX_ACCESS_TOKEN");
  if (!accessToken) {
    return await callRouteGenerator(job, region, start, attempt);
  }

  const plan = healingPlanForAttempt(job, start, attempt);
  const exclude = applyAvoidHighwaysExcludes("", job.avoid_highways);
  const fetchResult = await fetchHealingMapboxRoute(
    plan,
    exclude,
    accessToken,
    { timeoutMs: 3_800 },
  );

  const routeOptions = fetchResult.routes?.length
    ? fetchResult.routes
    : fetchResult.route
    ? [fetchResult.route]
    : [];
  if (routeOptions.length === 0) {
    return {
      ok: false,
      reason: fetchResult.outcome === "http_error"
        ? `mapbox_http_${fetchResult.statusCode ?? "unknown"}`
        : `mapbox_${fetchResult.outcome}`,
    };
  }

  return {
    ok: true,
    route: routeOptions[0],
    meta: {
      mapbox_call_count: 1,
      healing_strategy: "direct_mapbox_loop",
      healing_family: plan.family,
      healing_plan: plan.label,
      healing_target_distance_km: plan.targetDistanceKm,
      healing_route_options: routeOptions.length,
    },
  };
}

async function fetchHealingMapboxRoute(
  plan: HealingCandidatePlan,
  exclude: string,
  accessToken: string,
  options: { timeoutMs: number },
): Promise<HealingMapboxFetchResult> {
  const coordinatesStr = plan.waypoints
    .map((point) => `${point.longitude},${point.latitude}`)
    .join(";");
  const params = new URLSearchParams({
    access_token: accessToken,
    geometries: "geojson",
    overview: "simplified",
    steps: "false",
    language: "de",
    continue_straight: plan.continueStraight ? "true" : "false",
    alternatives: "false",
  });
  if (exclude.trim().length > 0) params.set("exclude", exclude);
  if (plan.radiuses.trim().length > 0) params.set("radiuses", plan.radiuses);

  const url =
    `https://api.mapbox.com/directions/v5/mapbox/driving/${coordinatesStr}?${params}`;
  const controller = new AbortController();
  let timeoutId: number | undefined;
  const timeoutResult = new Promise<HealingMapboxFetchResult>((resolve) => {
    timeoutId = setTimeout(() => {
      controller.abort();
      resolve({
        route: null,
        outcome: "timeout",
        details: "healing_mapbox_timeout",
      });
    }, options.timeoutMs);
  });
  const request = (async (): Promise<HealingMapboxFetchResult> => {
    const response = await fetch(url, { signal: controller.signal });
    if (!response.ok) {
      return {
        route: null,
        outcome: "http_error",
        statusCode: response.status,
        details: (await response.text()).slice(0, 300),
      };
    }
    const data = await response.json();
    const routes = Array.isArray(data?.routes) ? data.routes : [];
    if (routes.length === 0) {
      return {
        route: null,
        outcome: "no_route",
        details: JSON.stringify(data).slice(0, 300),
      };
    }
    const boundedRoutes = routes.map(boundHealingRouteGeometry);
    return { route: boundedRoutes[0], routes: boundedRoutes, outcome: "ok" };
  })();

  try {
    return await Promise.race([request, timeoutResult]);
  } catch (error) {
    const details = error instanceof Error ? error.message : String(error);
    const timeout = details.toLowerCase().includes("abort") ||
      (error instanceof DOMException && error.name === "AbortError");
    return {
      route: null,
      outcome: timeout ? "timeout" : "network_error",
      details,
    };
  } finally {
    if (timeoutId != null) clearTimeout(timeoutId);
  }
}

function boundHealingRouteGeometry(route: any): any {
  const coordinates = route?.geometry?.coordinates;
  if (!Array.isArray(coordinates) || coordinates.length <= 650) return route;

  const bounded: unknown[] = [];
  const lastIndex = coordinates.length - 1;
  for (let index = 0; index < 650; index += 1) {
    const ratio = index / 649;
    bounded.push(coordinates[Math.round(lastIndex * ratio)]);
  }
  return {
    ...route,
    geometry: {
      ...route.geometry,
      coordinates: bounded,
    },
  };
}

function healingPlanForAttempt(
  job: SeedJob,
  start: Coordinate,
  attempt: number,
): HealingCandidatePlan {
  const plans = buildHealingCandidatePlans(job, start);
  return plans[attempt % plans.length];
}

function buildHealingCandidatePlans(
  job: SeedJob,
  start: Coordinate,
): HealingCandidatePlan[] {
  const targetVariants = healingTargetDistances(job.distance_bucket);
  const sectorSeed = stableNumber(
    `${job.country_code}|${job.admin1_name}|${
      job.admin2_name ?? ""
    }|${job.city_cluster}|${job.style_key}|${job.avoid_highways}`,
  );
  const sectorOffset = sectorSeed % 45;
  const hashedSectors = [0, 45, 90, 135, 180, 225, 270, 315].map((bearing) =>
    normalizeBearingDegrees(bearing + sectorOffset)
  );
  const sectors = uniqueBearings([
    ...preferredHealingSectors(job),
    ...hashedSectors,
  ]);
  const plans: HealingCandidatePlan[] = [];
  for (const targetDistanceKm of targetVariants) {
    for (const sector of sectors) {
      plans.push(...healingFamilyPlans(job, start, targetDistanceKm, sector));
    }
  }
  return plans;
}

function preferredHealingSectors(job: SeedJob): number[] {
  const country = job.country_code.trim().toUpperCase();
  const admin1 = job.admin1_name.trim().toLowerCase();
  const city = job.city_cluster.trim().toLowerCase();
  if (country === "AT" && admin1.includes("vorarlberg")) {
    if (city.includes("bregenz")) {
      return [125, 160, 205, 95, 235, 70, 260, 35];
    }
    if (city.includes("dornbirn")) {
      return [120, 170, 220, 90, 260, 45, 315, 0];
    }
    if (city.includes("götzis") || city.includes("goetzis")) {
      return [90, 140, 190, 230, 45, 280, 320, 0];
    }
  }
  return [];
}

function uniqueBearings(values: number[]): number[] {
  const seen = new Set<number>();
  const result: number[] = [];
  for (const value of values) {
    const normalized = Math.round(normalizeBearingDegrees(value));
    if (seen.has(normalized)) continue;
    seen.add(normalized);
    result.push(normalized);
  }
  return result;
}

function healingFamilyPlans(
  job: SeedJob,
  start: Coordinate,
  targetDistanceKm: number,
  sectorBearing: number,
): HealingCandidatePlan[] {
  const curvy = job.style_key === "kurvenjagd";
  const explorer = job.style_key === "entdecker";
  const sport = job.style_key === "sport_mode";
  const compactScale = healingRadiusScale(
    job,
    job.avoid_highways ? 0.19 : 0.21,
  );
  const wideScale = healingRadiusScale(job, job.avoid_highways ? 0.26 : 0.29);
  const curvyScale = healingRadiusScale(job, curvy ? 0.24 : 0.21);
  return [
    makeHealingLoopPlan({
      family: "compact_loop",
      start,
      targetDistanceKm,
      sectorBearing,
      bearings: [0, 105, 215],
      radiusFactors: [compactScale, compactScale * 1.08, compactScale],
      minRadiusKm: healingMinRadiusKm(job),
    }),
    makeHealingLoopPlan({
      family: "wide_loop",
      start,
      targetDistanceKm,
      sectorBearing,
      bearings: [10, 90, 185, 275],
      radiusFactors: [wideScale, wideScale * 0.78, wideScale, wideScale * 0.78],
      minRadiusKm: healingMinRadiusKm(job),
    }),
    makeHealingLoopPlan({
      family: "valley_loop",
      start,
      targetDistanceKm,
      sectorBearing,
      bearings: [-20, 55, 125, 205, 285],
      radiusFactors: healingRadiusScales(job, [0.18, 0.24, 0.20, 0.24, 0.18]),
      minRadiusKm: healingMinRadiusKm(job),
    }),
    makeHealingLoopPlan({
      family: "hill_loop",
      start,
      targetDistanceKm,
      sectorBearing,
      bearings: [30, 120, 210, 300],
      radiusFactors: healingRadiusScales(job, [0.20, 0.28, 0.24, 0.20]),
      minRadiusKm: healingMinRadiusKm(job),
    }),
    makeHealingLoopPlan({
      family: "smooth_sport_loop",
      start,
      targetDistanceKm,
      sectorBearing,
      bearings: sport ? [15, 95, 185, 275] : [20, 110, 200, 290],
      radiusFactors: healingRadiusScales(job, [0.22, 0.24, 0.22, 0.20]),
      minRadiusKm: healingMinRadiusKm(job),
    }),
    makeHealingLoopPlan({
      family: "curvy_distributed_loop",
      start,
      targetDistanceKm,
      sectorBearing,
      bearings: [-25, 45, 115, 190, 265],
      radiusFactors: [
        curvyScale,
        curvyScale * 0.85,
        curvyScale * 1.12,
        curvyScale,
        curvyScale * 0.88,
      ],
      minRadiusKm: healingMinRadiusKm(job),
    }),
    makeHealingLoopPlan({
      family: "explorer_sector_loop",
      start,
      targetDistanceKm,
      sectorBearing,
      bearings: explorer ? [-10, 55, 145, 235] : [0, 65, 150, 240],
      radiusFactors: healingRadiusScales(
        job,
        explorer ? [0.22, 0.30, 0.26, 0.20] : [0.20, 0.27, 0.23, 0.18],
      ),
      minRadiusKm: healingMinRadiusKm(job),
    }),
  ];
}

function healingRadiusScales(job: SeedJob, scales: number[]): number[] {
  return scales.map((scale) => healingRadiusScale(job, scale));
}

function healingRadiusScale(job: SeedJob, scale: number): number {
  if (job.distance_bucket === 50) return scale * 0.24;
  if (job.distance_bucket === 75) return scale * 0.50;
  return scale * 0.70;
}

function healingMinRadiusKm(job: SeedJob): number {
  if (job.distance_bucket === 50) return 1.2;
  if (job.distance_bucket === 75) return 2.5;
  return 5;
}

function makeHealingLoopPlan(args: {
  family: string;
  start: Coordinate;
  targetDistanceKm: number;
  sectorBearing: number;
  bearings: number[];
  radiusFactors: number[];
  minRadiusKm: number;
}): HealingCandidatePlan {
  const innerWaypoints = args.bearings.map((bearingOffset, index) => {
    const radiusFactor = args.radiusFactors[index] ??
      args.radiusFactors[args.radiusFactors.length - 1] ?? 0.22;
    return calculateDestination(
      args.start,
      Math.max(args.minRadiusKm, args.targetDistanceKm * radiusFactor),
      normalizeBearingDegrees(args.sectorBearing + bearingOffset),
    );
  });
  const waypoints = [args.start, ...innerWaypoints, args.start];
  const snapRadiusMeters = Math.round(
    Math.max(2200, Math.min(8500, args.targetDistanceKm * 95)),
  );
  const radiuses = waypoints.map((_, index) =>
    index === 0 || index === waypoints.length - 1
      ? "1200"
      : String(snapRadiusMeters)
  ).join(";");
  return {
    family: args.family,
    label: `${args.family}_${Math.round(args.targetDistanceKm)}_${
      Math.round(args.sectorBearing)
    }`,
    targetDistanceKm: args.targetDistanceKm,
    waypoints,
    radiuses,
    continueStraight: true,
  };
}

function healingTargetDistances(bucket: 50 | 75 | 100): number[] {
  if (bucket === 50) return [48, 52, 55, 45, 58, 50];
  if (bucket === 75) return [68, 74, 80, 86, 64];
  return [90, 98, 106, 114, 118];
}

function evaluateGeneratedRoute(
  job: SeedJob,
  route: any,
  start: Coordinate,
): {
  acceptable: boolean;
  verified: boolean;
  reason: string;
  fingerprint: string;
  qualityTier: string;
  qualityScore: number;
  shapeScore: number;
  distanceKm: number;
} {
  const style = styleLabel(job.style_key);
  const quality = evaluateRouteQuality(route, job.route_type, {
    targetDistanceKm: job.distance_bucket,
    mode: style,
    avoidHighways: job.avoid_highways,
  });
  const cleanup = evaluateRouteCleanupGate(route, job.route_type, {
    targetDistanceKm: job.distance_bucket,
    mode: style,
    avoidHighways: job.avoid_highways,
    startLocation: start,
  });
  if (!quality.passed || quality.tier === "rejected") {
    return rejectDecision(`quality_${quality.reason}`);
  }
  if (!cleanup.passed) {
    return rejectDecision(`cleanup_${cleanup.reason}`);
  }
  const distanceKm = distanceKmFromRoute(route);
  if (!distanceInBucket(distanceKm, job.distance_bucket)) {
    return rejectDecision(`distance_outside_bucket_${distanceKm.toFixed(1)}`);
  }
  if (job.avoid_highways && routeHasMotorway(route)) {
    return rejectDecision("motorway_violation");
  }

  const verified = quality.tier === "ideal" || quality.tier === "good";
  return {
    acceptable: true,
    verified,
    reason: quality.reason,
    fingerprint: buildRouteFingerprintFromRoute(route),
    qualityTier: quality.tier,
    qualityScore: qualityScoreForTier(quality.tier),
    shapeScore: Math.max(0, Math.min(100, 100 - cleanup.removedPointPercent)),
    distanceKm,
  };
}

function rejectDecision(reason: string) {
  return {
    acceptable: false,
    verified: false,
    reason,
    fingerprint: "",
    qualityTier: "rejected",
    qualityScore: 0,
    shapeScore: 0,
    distanceKm: 0,
  };
}

async function upsertVerifiedRoute(args: {
  job: SeedJob;
  region: RouteRegion;
  route: any;
  fingerprint: string;
  decision: ReturnType<typeof evaluateGeneratedRoute>;
}): Promise<boolean> {
  const coords = args.route.geometry.coordinates as number[][];
  const first = coords[0];
  const last = coords[coords.length - 1];
  const hasHighway = routeHasMotorway(args.route);
  const row = {
    route_fingerprint: args.fingerprint,
    title: `${args.region.city_cluster} ${args.job.distance_bucket} ${
      styleLabel(args.job.style_key)
    } Healing`,
    route_region_id: args.region.id ?? args.job.route_region_id,
    country_code: args.region.country_code,
    admin1_name: args.region.admin1_name,
    admin2_name: args.region.admin2_name ?? args.job.admin2_name ?? null,
    city_cluster: args.region.city_cluster,
    start_lat: first[1],
    start_lng: first[0],
    end_lat: last[1],
    end_lng: last[0],
    distance_km: args.decision.distanceKm,
    distance_bucket: args.job.distance_bucket,
    route_type: args.job.route_type,
    style_tags: [styleLabel(args.job.style_key)],
    avoids_highway: args.job.avoid_highways,
    has_highway: hasHighway,
    quality_score: args.decision.qualityScore,
    shape_score: args.decision.shapeScore,
    source: "mapbox_healing",
    verified: true,
    is_active: true,
    geometry: args.route.geometry,
    route_payload: {
      source: "route_pool_healing_worker",
      quality_tier: args.decision.qualityTier,
      seed_job_id: args.job.id,
      generated_at: new Date().toISOString(),
    },
  };
  if (dryRun) return true;
  await rest("route_pool", {
    method: "POST",
    query: "on_conflict=route_fingerprint",
    headers: { Prefer: "resolution=merge-duplicates" },
    body: row,
  });
  return true;
}

async function upsertCandidateRoute(args: {
  job: SeedJob;
  region: RouteRegion;
  route: any;
  fingerprint: string;
  decision: ReturnType<typeof evaluateGeneratedRoute>;
}): Promise<boolean> {
  const coords = args.route.geometry.coordinates as number[][];
  const first = coords[0];
  const hasHighway = routeHasMotorway(args.route);
  const row = {
    route_region_id: args.region.id ?? args.job.route_region_id,
    route_fingerprint: args.fingerprint,
    country_code: args.region.country_code,
    admin1_name: args.region.admin1_name,
    admin2_name: args.region.admin2_name ?? args.job.admin2_name ?? null,
    city_cluster: args.region.city_cluster,
    start_lat: first[1],
    start_lng: first[0],
    distance_km: args.decision.distanceKm,
    route_type: args.job.route_type,
    distance_bucket: args.job.distance_bucket,
    style_key: args.job.style_key,
    style_tags: [styleLabel(args.job.style_key)],
    avoid_highways: args.job.avoid_highways,
    has_highway: hasHighway,
    quality_score: args.decision.qualityScore,
    shape_score: args.decision.shapeScore,
    candidate_source: "bootstrap",
    candidate_region_difficulty: args.region.difficulty_level ?? "normal",
    candidate_locality_score: 100,
    repeated_success_count: 1,
    is_candidate: true,
    is_verified_pool: false,
    candidate_score: args.decision.qualityScore,
    geometry: args.route.geometry,
    route_payload: {
      source: "route_pool_healing_worker",
      quality_tier: args.decision.qualityTier,
      seed_job_id: args.job.id,
      generated_at: new Date().toISOString(),
    },
  };
  if (dryRun) return true;
  await rest("route_pool_candidates", {
    method: "POST",
    query: "on_conflict=route_fingerprint",
    headers: { Prefer: "resolution=merge-duplicates" },
    body: row,
  });
  return true;
}

async function loadClaimableJobs(): Promise<SeedJob[]> {
  const query = new URLSearchParams({
    select: "*",
    order: "priority.desc,updated_at.asc",
    limit: String(maxJobsToFetch),
  });
  query.append("status", "in.(queued,cooldown,paused_budget,running)");
  query.append("route_type", "eq.ROUND_TRIP");
  const rows = await rest<SeedJob[]>("route_seed_jobs", { query });
  return rows.filter(isJobRunnable);
}

async function claimJob(job: SeedJob): Promise<SeedJob | null> {
  const today = new Date().toISOString().slice(0, 10);
  const month = `${today.slice(0, 8)}01`;
  const dailyCount = job.budget_window_date === today
    ? (job.daily_attempt_count ?? 0) + 1
    : 1;
  const monthlyCount = job.budget_window_month === month
    ? (job.monthly_attempt_count ?? 0) + 1
    : 1;
  if (
    dailyCount > (job.daily_attempt_budget ?? 12) ||
    monthlyCount > (job.monthly_attempt_budget ?? 120)
  ) {
    await pauseJobForBudget(job, "request_budget_exhausted");
    return null;
  }

  const payload = {
    status: "running",
    started_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    attempt_count: (job.attempt_count ?? 0) + 1,
    daily_attempt_count: dailyCount,
    monthly_attempt_count: monthlyCount,
    budget_window_date: today,
    budget_window_month: month,
    last_error: null,
  };
  if (dryRun) return { ...job, ...payload } as SeedJob;
  const rows = await rest<SeedJob[]>("route_seed_jobs", {
    method: "PATCH",
    query: `id=eq.${
      encodeURIComponent(job.id)
    }&status=in.(queued,cooldown,paused_budget,running)&select=*`,
    headers: { Prefer: "return=representation" },
    body: payload,
  });
  return rows[0] ?? null;
}

async function completeJob(
  job: SeedJob,
  result: {
    callsUsed: number;
    verifiedInserted: number;
    candidatesInserted: number;
    reason: string;
  },
): Promise<void> {
  stats.completed += 1;
  if (dryRun) return;
  await rest("route_seed_jobs", {
    method: "PATCH",
    query: `id=eq.${encodeURIComponent(job.id)}`,
    body: {
      status: "completed",
      completed_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      mapbox_calls_used: (job.mapbox_calls_used ?? 0) + result.callsUsed,
      verified_inserted_count: (job.verified_inserted_count ?? 0) +
        result.verifiedInserted,
      candidate_inserted_count: (job.candidate_inserted_count ?? 0) +
        result.candidatesInserted,
      ...mapboxBudgetPatch(job, result.callsUsed),
      completed_reason: result.reason,
      last_error: null,
      cooldown_until: null,
      next_retry_at: null,
    },
  });
}

async function cooldownJobAfterCandidateOnly(
  job: SeedJob,
  result: {
    callsUsed: number;
    candidatesInserted: number;
    reason: string;
  },
): Promise<void> {
  const cooldownUntil = new Date(
    Date.now() + Math.max(1, job.seed_cooldown_minutes ?? 20) * 60_000,
  ).toISOString();
  if (dryRun) return;
  await rest("route_seed_jobs", {
    method: "PATCH",
    query: `id=eq.${encodeURIComponent(job.id)}`,
    body: {
      status: "cooldown",
      updated_at: new Date().toISOString(),
      mapbox_calls_used: (job.mapbox_calls_used ?? 0) + result.callsUsed,
      candidate_inserted_count: (job.candidate_inserted_count ?? 0) +
        result.candidatesInserted,
      ...mapboxBudgetPatch(job, result.callsUsed),
      completed_reason: result.reason,
      last_failure_reason: result.reason,
      last_error: result.reason,
      cooldown_until: cooldownUntil,
      next_retry_at: cooldownUntil,
    },
  });
  await updateCoverageHealingStatus(job, {
    healingStatus: "healing_failed_cooldown",
    failureReason: result.reason,
    nextHealingAt: cooldownUntil,
  });
}

async function failJob(
  job: SeedJob,
  reason: string,
  cooldown: boolean,
  callsUsed = 0,
): Promise<void> {
  stats.failed += 1;
  const failureCount = (job.failure_count ?? 0) + 1;
  const maxAttempts = Math.max(1, job.max_attempts ?? 3);
  const shouldCurate = job.difficulty_level === "hard" ||
    failureCount >= maxAttempts;
  const cooldownUntil = new Date(
    Date.now() + Math.max(1, job.seed_cooldown_minutes ?? 20) * 60_000,
  ).toISOString();
  const status = shouldCurate ? "failed" : cooldown ? "cooldown" : "failed";
  if (dryRun) return;
  await rest("route_seed_jobs", {
    method: "PATCH",
    query: `id=eq.${encodeURIComponent(job.id)}`,
    body: {
      status,
      updated_at: new Date().toISOString(),
      completed_at: status === "failed" ? new Date().toISOString() : null,
      failure_count: failureCount,
      last_failure_reason: reason,
      last_error: reason,
      cooldown_until: status === "cooldown" ? cooldownUntil : null,
      next_retry_at: status === "cooldown" ? cooldownUntil : null,
      mapbox_calls_used: (job.mapbox_calls_used ?? 0) + callsUsed,
      ...mapboxBudgetPatch(job, callsUsed),
    },
  });
  await updateCoverageHealingStatus(job, {
    healingStatus: shouldCurate
      ? "hard_region_curated_needed"
      : "healing_failed_cooldown",
    failureReason: reason,
    nextHealingAt: status === "cooldown" ? cooldownUntil : null,
  });
}

async function pauseJobForBudget(job: SeedJob, reason: string): Promise<void> {
  stats.pausedBudget += 1;
  if (dryRun) return;
  await rest("route_seed_jobs", {
    method: "PATCH",
    query: `id=eq.${encodeURIComponent(job.id)}`,
    body: {
      status: "paused_budget",
      updated_at: new Date().toISOString(),
      last_error: reason,
      last_failure_reason: reason,
      next_retry_at: nextUtcMidnight().toISOString(),
    },
  });
  await updateCoverageHealingStatus(job, {
    healingStatus: "healing_paused_budget",
    failureReason: reason,
    nextHealingAt: nextUtcMidnight().toISOString(),
  });
}

async function markCuratedNeeded(
  job: SeedJob,
  region: RouteRegion,
  reason: string,
): Promise<void> {
  if (!dryRun) {
    await rest("route_seed_jobs", {
      method: "PATCH",
      query: `id=eq.${encodeURIComponent(job.id)}`,
      body: {
        status: "failed",
        completed_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        last_error: reason,
        last_failure_reason: reason,
        hard_region_status: region.hard_region_status ?? "curated_needed",
      },
    });
    await updateCoverageHealingStatus(job, {
      healingStatus: "hard_region_curated_needed",
      failureReason: reason,
      nextHealingAt: null,
    });
  }
  stats.failed += 1;
}

async function refreshCoverage(job: SeedJob, region: RouteRegion) {
  if (dryRun) return;
  const verifiedRows = await rest<JsonMap[]>("route_pool", {
    query: new URLSearchParams({
      select:
        "id,route_fingerprint,style_tags,admin2_name,avoids_highway,has_highway,quality_score,route_payload",
      verified: "eq.true",
      is_active: "eq.true",
      country_code: `eq.${region.country_code}`,
      admin1_name: `eq.${region.admin1_name}`,
      city_cluster: `eq.${region.city_cluster}`,
      route_type: `eq.${job.route_type}`,
      distance_bucket: `eq.${job.distance_bucket}`,
    }),
  });
  const verifiedSummary = summarizeVerifiedRows(verifiedRows, job, region);
  const candidateRows = await rest<JsonMap[]>("route_pool_candidates", {
    query: new URLSearchParams({
      select: "id,admin2_name",
      country_code: `eq.${region.country_code}`,
      admin1_name: `eq.${region.admin1_name}`,
      city_cluster: `eq.${region.city_cluster}`,
      route_type: `eq.${job.route_type}`,
      distance_bucket: `eq.${job.distance_bucket}`,
      style_key: `eq.${job.style_key}`,
      avoid_highways: `eq.${job.avoid_highways}`,
      is_candidate: "eq.true",
    }),
  });
  const candidateCount =
    candidateRows.filter((row) =>
      nullableSame(row.admin2_name, region.admin2_name)
    ).length;
  const policy = coveragePolicy(region);
  const coverageStatus = coverageStatusForSummary(
    verifiedSummary,
    policy,
    region,
  );
  const healingStatus = coverageMeetsMinimum(verifiedSummary, policy)
    ? "idle"
    : "healing_queued";
  await upsertCoverage(job, region, {
    verifiedSummary,
    candidateCount,
    coverageStatus,
    healingStatus,
  });
}

async function verifiedCapacityRemainingForCell(
  job: SeedJob,
  region: RouteRegion,
): Promise<number> {
  if (dryRun) return Number.POSITIVE_INFINITY;
  const coverage = await loadCoverage(job, region);
  const maxPoolSize = Math.max(
    0,
    Number(
      coverage?.max_pool_size ?? region.default_max_pool_size ?? 20,
    ),
  );
  const currentVerifiedCount = Math.max(
    0,
    Number(coverage?.current_verified_count ?? 0),
  );
  return Math.max(0, maxPoolSize - currentVerifiedCount);
}

async function upsertCoverage(
  job: SeedJob,
  region: RouteRegion,
  data: {
    verifiedSummary: CoverageQualitySummary;
    candidateCount: number;
    coverageStatus: string;
    healingStatus: string;
  },
) {
  const existing = await loadCoverage(job, region);
  const payload = {
    route_region_id: region.id ?? job.route_region_id ?? null,
    country_code: region.country_code,
    admin1_name: region.admin1_name,
    admin2_name: region.admin2_name ?? job.admin2_name ?? null,
    city_cluster: region.city_cluster,
    route_type: job.route_type,
    distance_bucket: job.distance_bucket,
    style_key: job.style_key,
    avoid_highways: job.avoid_highways,
    min_verified_count: 3,
    target_pool_size: 8,
    max_pool_size: 20,
    candidate_buffer_limit: 30,
    acceptable_reserve_limit_percent: 25,
    coverage_status: data.coverageStatus,
    healing_status: data.healingStatus,
    healing_priority: job.priority ?? 0,
    current_verified_count: data.verifiedSummary.verifiedCount,
    current_candidate_count: data.candidateCount,
    ideal_count: data.verifiedSummary.idealCount,
    good_count: data.verifiedSummary.goodCount,
    acceptable_count: data.verifiedSummary.acceptableCount,
    rejected_count: data.verifiedSummary.rejectedCount,
    distinct_fingerprint_count: data.verifiedSummary.distinctFingerprintCount,
    difficulty_level: region.difficulty_level ?? job.difficulty_level ??
      "normal",
    hard_region_status: region.hard_region_status ??
      job.hard_region_status ?? "normal",
    last_counted_at: new Date().toISOString(),
    last_seed_completed_at: new Date().toISOString(),
    last_healing_job_id: job.id,
    updated_at: new Date().toISOString(),
  };
  if (existing?.id) {
    await rest("route_pool_coverage", {
      method: "PATCH",
      query: `id=eq.${encodeURIComponent(String(existing.id))}`,
      body: payload,
    });
  } else {
    await rest("route_pool_coverage", { method: "POST", body: payload });
  }
}

async function updateCoverageHealingStatus(
  job: SeedJob,
  options: {
    healingStatus: string;
    failureReason: string;
    nextHealingAt: string | null;
  },
) {
  const region = await loadRegionForJob(job);
  if (!region) return;
  const existing = await loadCoverage(job, region);
  if (!existing?.id) return;
  await rest("route_pool_coverage", {
    method: "PATCH",
    query: `id=eq.${encodeURIComponent(String(existing.id))}`,
    body: {
      healing_status: options.healingStatus,
      healing_failure_count: Number(existing.healing_failure_count ?? 0) + 1,
      last_error: options.failureReason,
      next_healing_at: options.nextHealingAt,
      last_healing_job_id: job.id,
      updated_at: new Date().toISOString(),
    },
  });
}

async function loadCoverage(job: SeedJob, region: RouteRegion) {
  const params = new URLSearchParams({
    select: "*",
    country_code: `eq.${region.country_code}`,
    admin1_name: `eq.${region.admin1_name}`,
    city_cluster: `eq.${region.city_cluster}`,
    route_type: `eq.${job.route_type}`,
    distance_bucket: `eq.${job.distance_bucket}`,
    style_key: `eq.${job.style_key}`,
    avoid_highways: `eq.${job.avoid_highways}`,
    limit: "1",
  });
  const rows = await rest<JsonMap[]>("route_pool_coverage", { query: params });
  return rows.find((row) => nullableSame(row.admin2_name, region.admin2_name));
}

async function loadRegionForJob(job: SeedJob): Promise<RouteRegion | null> {
  if (job.route_region_id) {
    const rows = await rest<RouteRegion[]>("route_regions", {
      query: new URLSearchParams({
        select: "*",
        id: `eq.${job.route_region_id}`,
        limit: "1",
      }),
    });
    if (rows[0]) return rows[0];
  }
  const rows = await rest<RouteRegion[]>("route_regions", {
    query: new URLSearchParams({
      select: "*",
      country_code: `eq.${job.country_code}`,
      admin1_name: `eq.${job.admin1_name}`,
      city_cluster: `eq.${job.city_cluster}`,
      limit: "10",
    }),
  });
  return rows.find((region) =>
    nullableSame(region.admin2_name, job.admin2_name)
  ) ??
    rows[0] ?? null;
}

async function routeExists(
  table: "route_pool" | "route_pool_candidates",
  fingerprint: string,
) {
  const rows = await rest<JsonMap[]>(table, {
    query: new URLSearchParams({
      select: table === "route_pool" ? "route_fingerprint" : "id",
      route_fingerprint: `eq.${fingerprint}`,
      limit: "1",
    }),
  });
  return rows.length > 0;
}

async function rest<T = unknown>(
  table: string,
  options: {
    method?: "GET" | "POST" | "PATCH";
    query?: URLSearchParams | string;
    headers?: Record<string, string>;
    body?: unknown;
  } = {},
): Promise<T> {
  const query = options.query
    ? typeof options.query === "string"
      ? options.query
      : options.query.toString()
    : "";
  const url = `${supabaseUrl}/rest/v1/${table}${query ? `?${query}` : ""}`;
  const response = await fetch(url, {
    method: options.method ?? "GET",
    headers: {
      apikey: serviceKey,
      authorization: `Bearer ${serviceKey}`,
      "content-type": "application/json",
      accept: "application/json",
      ...(options.headers ?? {}),
    },
    body: options.body == null ? undefined : JSON.stringify(options.body),
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`rest_${table}_${response.status}:${text.slice(0, 240)}`);
  }
  if (response.status === 204) return undefined as T;
  const text = await response.text();
  return (text.trim().length === 0 ? undefined : JSON.parse(text)) as T;
}

function isJobRunnable(job: SeedJob): boolean {
  if (job.status === "queued") return true;
  if (job.status === "running") {
    const startedAt = Date.parse(job.started_at ?? "");
    return Number.isFinite(startedAt) && Date.now() - startedAt > 5 * 60_000;
  }
  if (job.status !== "cooldown" && job.status !== "paused_budget") {
    return false;
  }
  const retryAt = job.next_retry_at ?? job.cooldown_until;
  return retryAt == null || Date.parse(retryAt) <= Date.now();
}

function remainingMapboxBudget(job: SeedJob): number {
  const today = new Date().toISOString().slice(0, 10);
  const month = `${today.slice(0, 8)}01`;
  const dailyAttemptCount = job.budget_window_date === today
    ? (job.daily_attempt_count ?? 0)
    : 0;
  const monthlyAttemptCount = job.budget_window_month === month
    ? (job.monthly_attempt_count ?? 0)
    : 0;
  const dailyAttemptRemaining = Math.max(
    0,
    (job.daily_attempt_budget ?? 12) - dailyAttemptCount,
  );
  const monthlyAttemptRemaining = Math.max(
    0,
    (job.monthly_attempt_budget ?? 120) - monthlyAttemptCount,
  );
  const dailyMapboxCount = job.mapbox_budget_window_date === today
    ? (job.daily_mapbox_count ?? 0)
    : 0;
  const monthlyMapboxCount = job.mapbox_budget_window_month === month
    ? (job.monthly_mapbox_count ?? 0)
    : 0;
  const dailyMapboxRemaining = Math.max(
    0,
    (job.daily_mapbox_budget ?? 12) - dailyMapboxCount,
  );
  const monthlyMapboxRemaining = Math.max(
    0,
    (job.monthly_mapbox_budget ?? 120) - monthlyMapboxCount,
  );
  return Math.min(
    dailyAttemptRemaining,
    monthlyAttemptRemaining,
    dailyMapboxRemaining,
    monthlyMapboxRemaining,
  );
}

function mapboxBudgetPatch(job: SeedJob, callsUsed: number): JsonMap {
  if (!Number.isFinite(callsUsed) || callsUsed <= 0) return {};
  const today = new Date().toISOString().slice(0, 10);
  const month = `${today.slice(0, 8)}01`;
  const dailyCount = job.mapbox_budget_window_date === today
    ? (job.daily_mapbox_count ?? 0)
    : 0;
  const monthlyCount = job.mapbox_budget_window_month === month
    ? (job.monthly_mapbox_count ?? 0)
    : 0;
  return {
    daily_mapbox_count: dailyCount + callsUsed,
    monthly_mapbox_count: monthlyCount + callsUsed,
    mapbox_budget_window_date: today,
    mapbox_budget_window_month: month,
  };
}

function mapboxCallsFromMeta(meta: JsonMap): number {
  const raw = meta.mapbox_call_count ?? meta.mapboxCallCount ??
    meta.mapbox_calls_used;
  if (typeof raw === "number" && Number.isFinite(raw) && raw > 0) {
    return Math.max(1, Math.ceil(raw));
  }
  return 1;
}

function distanceKmFromRoute(route: any): number {
  const raw = typeof route?.distance === "number" ? route.distance : 0;
  return raw > 1000 ? raw / 1000 : raw;
}

function distanceInBucket(distanceKm: number, bucket: 50 | 75 | 100): boolean {
  if (bucket === 50) return distanceKm >= 45 && distanceKm <= 58;
  if (bucket === 75) return distanceKm >= 62 && distanceKm <= 88;
  return distanceKm >= 85 && distanceKm <= 118;
}

function routeHasMotorway(route: any): boolean {
  const text = JSON.stringify(route?.legs ?? []).toLowerCase();
  return text.includes("motorway") || text.includes("autobahn");
}

function healthyThreshold(region: RouteRegion, job: SeedJob): number {
  if (
    typeof region.healthy_threshold === "number" && region.healthy_threshold > 0
  ) {
    return region.healthy_threshold;
  }
  if (job.distance_bucket === 100) return 2;
  return 3;
}

function targetDistanceFor(bucket: 50 | 75 | 100, attempt: number): number {
  const variants = bucket === 50
    ? [46, 50, 54]
    : bucket === 75
    ? [68, 75, 82, 72]
    : [90, 100, 108, 96];
  return variants[attempt % variants.length] ?? bucket;
}

function styleLabel(styleKey: string): RouteMode {
  switch (styleKey) {
    case "kurvenjagd":
      return "Kurvenjagd";
    case "abendrunde":
      return "Abendrunde";
    case "entdecker":
      return "Entdecker";
    case "sport_mode":
    default:
      return "Sport Mode";
  }
}

function styleProfileFor(styleKey: string): string {
  switch (styleKey) {
    case "kurvenjagd":
      return "kurvenjagd";
    case "abendrunde":
      return "evening";
    case "entdecker":
      return "explorer";
    case "sport_mode":
    default:
      return "sport";
  }
}

function normalizeStyleKey(style: string): string {
  const cleaned = style.trim().toLowerCase()
    .replaceAll(/[^a-z0-9]+/g, "_")
    .replaceAll(/_+/g, "_")
    .replaceAll(/^_|_$/g, "");
  return cleaned || "standard";
}

function styleTags(raw: unknown): string[] {
  if (Array.isArray(raw)) return raw.map(String);
  if (typeof raw === "string" && raw.trim().length > 0) {
    return raw.split(",").map((item) => item.trim()).filter(Boolean);
  }
  return [];
}

interface CoveragePolicy {
  minVerifiedCount: number;
  targetPoolSize: number;
  maxPoolSize: number;
  acceptableReserveLimitPercent: number;
  minDistinctFingerprints: number;
}

interface CoverageQualitySummary {
  verifiedCount: number;
  idealCount: number;
  goodCount: number;
  acceptableCount: number;
  rejectedCount: number;
  distinctFingerprintCount: number;
}

function coveragePolicy(region: RouteRegion): CoveragePolicy {
  return {
    minVerifiedCount: 3,
    targetPoolSize: 8,
    maxPoolSize: Math.max(8, region.default_max_pool_size ?? 20),
    acceptableReserveLimitPercent: 25,
    minDistinctFingerprints: 3,
  };
}

function summarizeVerifiedRows(
  rows: JsonMap[],
  job: SeedJob,
  region: RouteRegion,
): CoverageQualitySummary {
  const fingerprints = new Set<string>();
  const summary = {
    verifiedCount: 0,
    idealCount: 0,
    goodCount: 0,
    acceptableCount: 0,
    rejectedCount: 0,
    distinctFingerprintCount: 0,
  };
  for (const row of rows) {
    if (!nullableSame(row.admin2_name, region.admin2_name)) continue;
    if (
      !styleTags(row.style_tags).map(normalizeStyleKey).includes(job.style_key)
    ) {
      continue;
    }
    if (!highwayMatches(row, job.avoid_highways)) continue;

    summary.verifiedCount += 1;
    const fingerprint = String(
      row.route_fingerprint ?? routePayload(row).route_fingerprint ??
        routePayload(row).fingerprint ?? routePayload(row).seed_key ??
        row.id ?? "",
    );
    if (fingerprint.trim().length > 0) fingerprints.add(fingerprint.trim());
    switch (qualityTierForRow(row)) {
      case "ideal":
        summary.idealCount += 1;
        break;
      case "good":
        summary.goodCount += 1;
        break;
      case "acceptable":
        summary.acceptableCount += 1;
        break;
      default:
        summary.rejectedCount += 1;
        break;
    }
  }
  summary.distinctFingerprintCount = fingerprints.size;
  return summary;
}

function highwayMatches(row: JsonMap, avoidHighways: boolean): boolean {
  if (avoidHighways) {
    return row.avoids_highway === true && row.has_highway !== true;
  }
  return true;
}

function qualityTierForRow(row: JsonMap): string {
  const payloadTier = String(routePayload(row).quality_tier ?? "")
    .trim()
    .toLowerCase();
  if (
    payloadTier === "ideal" ||
    payloadTier === "good" ||
    payloadTier === "acceptable" ||
    payloadTier === "rejected"
  ) {
    return payloadTier;
  }
  const qualityScore = Number(row.quality_score ?? 0);
  if (qualityScore >= 92) return "ideal";
  if (qualityScore >= 82) return "good";
  if (qualityScore >= 70) return "acceptable";
  return "rejected";
}

function routePayload(row: JsonMap): JsonMap {
  return typeof row.route_payload === "object" && row.route_payload !== null
    ? row.route_payload as JsonMap
    : {};
}

function coverageMeetsMinimum(
  summary: CoverageQualitySummary,
  policy: CoveragePolicy,
): boolean {
  const goodEnoughCount = summary.idealCount + summary.goodCount;
  const acceptableLimit = Math.floor(
    summary.verifiedCount * (policy.acceptableReserveLimitPercent / 100),
  );
  return summary.verifiedCount >= policy.minVerifiedCount &&
    summary.distinctFingerprintCount >= policy.minDistinctFingerprints &&
    goodEnoughCount >= policy.minVerifiedCount &&
    summary.acceptableCount <= acceptableLimit;
}

function coverageStatusForSummary(
  summary: CoverageQualitySummary,
  policy: CoveragePolicy,
  region: RouteRegion,
): string {
  if (summary.verifiedCount > policy.maxPoolSize) return "overfull";
  if (coverageMeetsMinimum(summary, policy)) {
    return summary.verifiedCount >= policy.targetPoolSize
      ? "target_met"
      : "healthy";
  }
  if (summary.verifiedCount >= policy.minVerifiedCount) return "quality_thin";
  if (summary.verifiedCount > 0) {
    return region.difficulty_level === "hard" ? "hard_region_thin" : "thin";
  }
  return "warming_up";
}

function nullableSame(left: unknown, right: unknown): boolean {
  return String(left ?? "").trim().toLowerCase() ===
    String(right ?? "").trim().toLowerCase();
}

function qualityScoreForTier(tier: string): number {
  if (tier === "ideal") return 96;
  if (tier === "good") return 88;
  if (tier === "acceptable") return 78;
  return 0;
}

function stableNumber(input: string): number {
  let hash = 2166136261;
  for (let i = 0; i < input.length; i += 1) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return Math.abs(hash >>> 0);
}

function shortHash(input: string): string {
  return stableNumber(input).toString(16).padStart(8, "0").slice(0, 8);
}

function nextUtcMidnight(): Date {
  const now = new Date();
  return new Date(Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate() + 1,
    0,
    0,
    0,
  ));
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function runtimeExceeded(): boolean {
  return runStartedAt > 0 && Date.now() - runStartedAt >= maxRuntimeMs;
}

function clampInt(
  value: number | undefined,
  fallback: number,
  min: number,
  max: number,
): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, Math.floor(parsed)));
}

function intArg(prefix: string, fallback: number): number {
  const raw = arg(prefix);
  const value = raw == null ? NaN : Number(raw);
  return Number.isFinite(value) ? Math.max(0, Math.floor(value)) : fallback;
}

function arg(prefix: string): string | undefined {
  return Deno.args.find((item) => item.startsWith(prefix))?.slice(
    prefix.length,
  );
}

function env(name: string): string {
  return Deno.env.get(name)?.trim() ?? "";
}
