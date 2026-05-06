// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import type {
  Coordinate,
  DistanceConfig,
  RequestData,
  RoundTripSessionCandidatePayload,
  RoundTripSearchResult,
} from "./routing_types.ts";
import {
  applyAvoidHighwaysExcludes,
  calculateBearing,
  calculateDestination,
  calculateDistance,
  interpolateCoordinate,
  normalizeBearingDegrees,
  normalizeHint,
  relaxStreetExcludes,
  scaleWaypoint,
  seededUnit,
  stableStringHash,
} from "./routing_utils.ts";
import { getDistanceConfig } from "./roundtrip_waypoints.ts";
import { getMapboxRoute, getMapboxRouteDetailed } from "./mapbox_client.ts";
import type { PointToPointCorridorFamily } from "./point_to_point.ts";
import {
  buildPointToPointScenicWaypoints,
  getPointToPointMaximumDistanceKm,
  getPointToPointMinimumDistanceKm,
  getRouteDistanceKm,
  isPointToPointDetourAcceptable,
  selectPointToPointCorridorFamilies,
} from "./point_to_point.ts";
import {
  evaluateRouteCleanupGate,
  evaluateRouteQuality,
} from "./route_quality.ts";
import { searchBestRoundTripRoute } from "./roundtrip_search.ts";
import { routeRequiredWaypointRoundTrip } from "./waypoint_roundtrip.ts";
import { classifyRoutingError } from "./routing_request_utils.ts";
import { debugError, debugLog } from "./routing_debug.ts";

// Environment variables
const MAPBOX_ACCESS_TOKEN = Deno.env.get("MAPBOX_ACCESS_TOKEN");
const ROUTING_BUILD_ID = Deno.env.get("ROUTING_BUILD_ID") ??
  "local-debug-meta";
const ROUTING_BUILD_TIME = Deno.env.get("ROUTING_BUILD_TIME") ??
  "local-debug-meta";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")?.replace(/\/$/, "") ?? "";

type JsonMap = Record<string, unknown>;

interface RouteSearchSessionRow {
  id: string;
  status: string;
  progress_stage?: string | null;
  distance_bucket: number;
  style_key: string;
  avoid_highways: boolean;
  attempts_count?: number | null;
  mapbox_calls_used?: number | null;
  best_candidate_payload?: JsonMap | null;
  candidate_queue_payload?: unknown[] | null;
  best_route_payload?: JsonMap | null;
  best_route_fingerprint?: string | null;
  reject_summary?: JsonMap | null;
  seed_job_id?: string | null;
  worker_last_seen_at?: string | null;
  last_error?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  expires_at?: string | null;
}

function serviceKey(): string {
  const direct = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (direct) return direct;
  const modernKeys = [
    ...parseNamedSecretKeys(Deno.env.get("SUPABASE_SECRET_KEYS")),
    ...parseNamedSecretKeys(Deno.env.get("SUPABASE_SECRET_KEY")),
  ];
  return modernKeys[0] ?? "";
}

function parseNamedSecretKeys(raw: string | undefined): string[] {
  const trimmed = raw?.trim() ?? "";
  if (!trimmed) return [];
  if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) return [trimmed];
  try {
    const parsed = JSON.parse(trimmed);
    return secretValuesFromJson(parsed).filter((value, index, all) =>
      value.length > 0 && all.indexOf(value) === index
    );
  } catch {
    return [];
  }
}

function secretValuesFromJson(value: unknown): string[] {
  if (typeof value === "string") return [value];
  if (Array.isArray(value)) return value.flatMap(secretValuesFromJson);
  if (value != null && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return [
      record.value,
      record.key,
      record.api_key,
      record.apiKey,
      ...Object.values(record).filter((entry) =>
        typeof entry === "string" && entry.startsWith("sb_" + "secret_")
      ),
    ].flatMap(secretValuesFromJson);
  }
  return [];
}

async function supabaseRest<T = unknown>(
  table: string,
  options: {
    method?: "GET" | "POST" | "PATCH";
    query?: URLSearchParams | string;
    body?: unknown;
    headers?: Record<string, string>;
  } = {},
): Promise<T> {
  const key = serviceKey();
  if (!SUPABASE_URL || !key) {
    throw new Error("search_session_supabase_not_configured");
  }
  const query = options.query
    ? typeof options.query === "string"
      ? options.query
      : options.query.toString()
    : "";
  const response = await fetch(
    `${SUPABASE_URL}/rest/v1/${table}${query ? `?${query}` : ""}`,
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
    const text = await response.text();
    throw new Error(`rest_${table}_${response.status}:${text.slice(0, 220)}`);
  }
  if (response.status === 204) return undefined as T;
  const text = await response.text();
  return (text.trim().length === 0 ? undefined : JSON.parse(text)) as T;
}

function jsonResponse(
  req: Request,
  body: unknown,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
  });
}

function distanceBucketForTarget(targetDistance?: number): 50 | 75 | 100 {
  const value = Number(targetDistance ?? 50);
  if (value >= 88) return 100;
  if (value >= 63) return 75;
  return 50;
}

function styleKeyForMode(mode?: string): string {
  const normalized = (mode ?? "Sport Mode").trim().toLowerCase();
  if (normalized.includes("kurven")) return "kurvenjagd";
  if (normalized.includes("abend")) return "abendrunde";
  if (normalized.includes("entdeck")) return "entdecker";
  if (normalized.includes("sport")) return "sport";
  return "sport";
}

function candidatePayloadDistanceFits(value: unknown): boolean {
  if (value == null || typeof value !== "object") return false;
  const record = value as JsonMap;
  const predicted = Number(record.predicted_distance_km);
  const minKm = Number(record.distance_band_min_km);
  const maxKm = Number(record.distance_band_max_km);
  if (!Number.isFinite(predicted) || !Number.isFinite(minKm) || !Number.isFinite(maxKm)) {
    return String(record.distance_fit_tier ?? "") !== "outside_bucket";
  }
  return predicted >= minKm && predicted <= maxKm;
}

function roundTripSessionCandidateQueue(
  search: RoundTripSearchResult | null | undefined,
): RoundTripSessionCandidatePayload[] {
  const seen = new Set<string>();
  const queue: RoundTripSessionCandidatePayload[] = [];
  const addCandidate = (candidate: RoundTripSessionCandidatePayload | null | undefined) => {
    if (candidate == null || !candidatePayloadDistanceFits(candidate)) return;
    const key = candidate.route_fingerprint || candidate.candidate_id;
    if (key && seen.has(key)) return;
    if (key) seen.add(key);
    queue.push(candidate);
  };
  addCandidate(search?.bestCandidatePayload ?? null);
  for (const candidate of search?.candidateQueuePayload ?? []) {
    addCandidate(candidate);
  }
  return queue;
}

function mergeRoundTripRejectReasons(
  first: Record<string, number> | undefined,
  second: Record<string, number> | undefined,
): Record<string, number> {
  const merged: Record<string, number> = { ...(first ?? {}) };
  for (const [reason, count] of Object.entries(second ?? {})) {
    merged[reason] = (merged[reason] ?? 0) + count;
  }
  return merged;
}

function mergeRoundTripBatchResults(
  first: RoundTripSearchResult,
  second: RoundTripSearchResult,
): RoundTripSearchResult {
  const queue = [
    ...roundTripSessionCandidateQueue(first),
    ...roundTripSessionCandidateQueue(second),
  ];
  const dedupedQueue: RoundTripSessionCandidatePayload[] = [];
  const seen = new Set<string>();
  for (const candidate of queue) {
    const key = candidate.route_fingerprint || candidate.candidate_id;
    if (key && seen.has(key)) continue;
    if (key) seen.add(key);
    dedupedQueue.push(candidate);
    if (dedupedQueue.length >= 3) break;
  }
  return {
    ...first,
    route: first.route ?? second.route,
    waypoints: first.waypoints.length > 0 ? first.waypoints : second.waypoints,
    radiuses: first.radiuses || second.radiuses,
    quality: first.quality ?? second.quality,
    candidateAttempts:
      (first.candidateAttempts ?? 0) + (second.candidateAttempts ?? 0),
    acceptedCandidates:
      (first.acceptedCandidates ?? 0) + (second.acceptedCandidates ?? 0),
    rejectedCandidates:
      (first.rejectedCandidates ?? 0) + (second.rejectedCandidates ?? 0),
    mapboxCallCount:
      (first.mapboxCallCount ?? 0) + (second.mapboxCallCount ?? 0),
    evaluatedRouteCount:
      (first.evaluatedRouteCount ?? 0) + (second.evaluatedRouteCount ?? 0),
    guidanceHydrationCount:
      (first.guidanceHydrationCount ?? 0) + (second.guidanceHydrationCount ?? 0),
    batchExhausted: first.batchExhausted === true || second.batchExhausted === true,
    searchPhases: [...(first.searchPhases ?? []), ...(second.searchPhases ?? [])],
    lastPlanLabels: [...(first.lastPlanLabels ?? []), ...(second.lastPlanLabels ?? [])],
    rejectReasons: mergeRoundTripRejectReasons(first.rejectReasons, second.rejectReasons),
    bestCandidatePayload: dedupedQueue[0] ?? first.bestCandidatePayload ??
      second.bestCandidatePayload ?? null,
    candidateQueuePayload: dedupedQueue,
  };
}

function searchSessionMeta(row: RouteSearchSessionRow): JsonMap {
  return {
    response_code: row.status === "found"
      ? "search_session_found"
      : row.status === "no_route" || row.status === "failed"
      ? "search_session_no_route"
      : "search_in_progress",
    search_in_progress: !["found", "no_route", "failed", "expired"].includes(
      row.status,
    ),
    search_session_id: row.id,
    search_session_status: row.status,
    progress_stage: row.progress_stage ?? row.status,
    requested_distance_bucket: row.distance_bucket,
    requested_style_key: row.style_key,
    avoid_highways_requested: row.avoid_highways,
    motorway_policy: row.avoid_highways
      ? "exclude_motorway"
      : "allowed_not_required",
    mapbox_calls_used: row.mapbox_calls_used ?? 0,
    attempts_count: row.attempts_count ?? 0,
    seed_job_id: row.seed_job_id ?? null,
    worker_last_seen_at: row.worker_last_seen_at ?? null,
    routeFingerprint: row.best_route_fingerprint ?? null,
    reject_summary: row.reject_summary ?? {},
    last_error: row.last_error ?? null,
    best_candidate_present: row.best_candidate_payload != null,
    candidate_queue_count: Array.isArray(row.candidate_queue_payload)
      ? row.candidate_queue_payload.length
      : 0,
    updated_at: row.updated_at ?? null,
    expires_at: row.expires_at ?? null,
    estimated_wait_seconds: row.distance_bucket >= 75
      ? row.status === "queued" ? 60 : 30
      : row.status === "queued" ? 45 : 20,
  };
}

async function routeSearchSessionStatusResponse(
  req: Request,
  sessionId: string | undefined,
): Promise<Response> {
  const cleanId = sessionId?.trim();
  if (!cleanId) {
    return jsonResponse(req, {
      error: "missing_search_session_id",
      code: "validation_error",
    }, 400);
  }
  const rows = await supabaseRest<RouteSearchSessionRow[]>(
    "route_search_sessions",
    {
      query: new URLSearchParams({
        select: "*",
        id: `eq.${cleanId}`,
        limit: "1",
      }),
    },
  );
  const row = rows[0];
  if (!row) {
    return jsonResponse(req, {
      error: "search_session_not_found",
      code: "search_session_not_found",
      meta: { search_session_id: cleanId },
    }, 404);
  }

  const payload = row.best_route_payload;
  if (row.status === "found" && payload != null) {
    const route = (payload.route ?? payload) as unknown;
    const payloadMeta = payload.meta != null && typeof payload.meta === "object"
      ? payload.meta as JsonMap
      : {};
    return jsonResponse(req, {
      route,
      meta: {
        ...payloadMeta,
        ...searchSessionMeta(row),
        source: payloadMeta.source ?? "search_session",
        route_source: payloadMeta.route_source ?? "search_session",
      },
    });
  }

  if (row.status === "no_route" || row.status === "failed" || row.status === "expired") {
    return jsonResponse(req, {
      route: null,
      code: "no_route",
      message: "search_session_no_route",
      meta: searchSessionMeta(row),
    }, 200);
  }

  return jsonResponse(req, {
    route: null,
    code: "search_in_progress",
    message: "search_in_progress",
    meta: searchSessionMeta(row),
  }, 202);
}

async function createRoundTripSearchSession(
  body: RequestData,
  roundTripSearch: RoundTripSearchResult | null,
  meta: JsonMap | null,
): Promise<RouteSearchSessionRow | null> {
  if (body.planning_type !== "Zufall") return null;
  if ((body.route_type ?? "ROUND_TRIP") !== "ROUND_TRIP") return null;
  const bucket = distanceBucketForTarget(body.targetDistance);
  if (body.startLocation == null) return null;
  const candidateQueue = Array.isArray(roundTripSearch?.candidateQueuePayload)
    ? roundTripSearch.candidateQueuePayload
      .filter(candidatePayloadDistanceFits)
      .slice(0, 3)
    : [];
  const searchBestCandidate = candidatePayloadDistanceFits(
    roundTripSearch?.bestCandidatePayload,
  )
    ? roundTripSearch?.bestCandidatePayload
    : null;
  const bestCandidate = searchBestCandidate ?? candidateQueue[0] ?? null;
  if (roundTripSearch?.batchExhausted !== true && bestCandidate == null) {
    return null;
  }

  const row = {
    route_type: "ROUND_TRIP",
    origin_lng: body.startLocation.longitude,
    origin_lat: body.startLocation.latitude,
    distance_bucket: bucket,
    style_key: styleKeyForMode(body.mode),
    avoid_highways: body.avoid_highways === true,
    status: "queued",
    progress_stage: bestCandidate == null
      ? "queued_without_candidate_payload"
      : "queued_worker_hydration",
    attempts_count: 0,
    mapbox_calls_used: roundTripSearch?.mapboxCallCount ?? 0,
    request_payload: {
      ...body,
      request_id: undefined,
      search_meta: meta ?? {},
      queued_at: new Date().toISOString(),
    },
    best_candidate_payload: bestCandidate,
    candidate_queue_payload: candidateQueue,
    reject_summary: {
      reject_reasons: roundTripSearch?.rejectReasons ?? {},
      batch_index: roundTripSearch?.batchIndex ?? null,
      batch_count: roundTripSearch?.batchCount ?? null,
      candidate_attempts: roundTripSearch?.candidateAttempts ?? 0,
      evaluated_routes: roundTripSearch?.evaluatedRouteCount ?? 0,
      candidate_queue_count: candidateQueue.length,
      best_candidate_family: bestCandidate?.candidate_family ?? null,
    },
    expires_at: new Date(Date.now() + 45 * 60_000).toISOString(),
  };

  const rows = await supabaseRest<RouteSearchSessionRow[]>(
    "route_search_sessions",
    {
      method: "POST",
      query: "select=*",
      headers: { Prefer: "return=representation" },
      body: row,
    },
  );
  return rows[0] ?? null;
}

function parseRoundTripTargetHintKm(value?: string): number | null {
  if (!value) return null;
  const match = value.match(/(?:^|[-_|])k(\d{2,3})(?:[-_|]|$)/i);
  if (!match) return null;
  const parsed = Number.parseInt(match[1], 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function finiteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function clampNumber(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function integerOption(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return Math.round(value);
}

function routeDisplayGeometryStats(
  rawCoordinates: unknown,
): {
  coordinateCount: number;
  maxSegmentMeters: number | null;
  averageSegmentMeters: number | null;
} {
  const coordinates = Array.isArray(rawCoordinates)
    ? rawCoordinates
      .filter((point): point is [number, number] =>
        Array.isArray(point) &&
        point.length >= 2 &&
        typeof point[0] === "number" &&
        typeof point[1] === "number" &&
        Number.isFinite(point[0]) &&
        Number.isFinite(point[1])
      )
      .map((point) => ({
        longitude: point[0],
        latitude: point[1],
      }))
    : [];
  if (coordinates.length < 2) {
    return {
      coordinateCount: coordinates.length,
      maxSegmentMeters: null,
      averageSegmentMeters: null,
    };
  }
  let totalMeters = 0;
  let maxSegmentMeters = 0;
  for (let index = 1; index < coordinates.length; index += 1) {
    const segmentMeters = calculateDistance(
      coordinates[index - 1],
      coordinates[index],
    ) * 1000;
    if (!Number.isFinite(segmentMeters)) continue;
    totalMeters += segmentMeters;
    maxSegmentMeters = Math.max(maxSegmentMeters, segmentMeters);
  }
  return {
    coordinateCount: coordinates.length,
    maxSegmentMeters: Number(maxSegmentMeters.toFixed(1)),
    averageSegmentMeters: Number(
      (totalMeters / Math.max(1, coordinates.length - 1)).toFixed(1),
    ),
  };
}

function minDisplayCoordinateCount(distanceKm: number): number {
  if (distanceKm <= 60) return 70;
  if (distanceKm <= 85) return 105;
  if (distanceKm <= 115) return 145;
  return 180;
}

function roundTripDisplayGeometryRejectReason(
  stats: ReturnType<typeof routeDisplayGeometryStats>,
  distanceKm: number,
  overview: unknown,
): string | null {
  if (overview !== "full") {
    return `display_geometry_overview=${String(overview ?? "unknown")}`;
  }
  if (stats.coordinateCount < minDisplayCoordinateCount(distanceKm)) {
    return `display_geometry_coords=${stats.coordinateCount}`;
  }
  if ((stats.averageSegmentMeters ?? 0) > 900) {
    return `display_geometry_avg_segment=${stats.averageSegmentMeters}`;
  }
  const maxSegmentLimitMeters = distanceKm >= 90 ? 2500 : 2000;
  if ((stats.maxSegmentMeters ?? 0) > maxSegmentLimitMeters) {
    return `display_geometry_max_segment=${stats.maxSegmentMeters}`;
  }
  return null;
}

function buildNoRouteSearchMeta(
  roundTripSearch: RoundTripSearchResult | null,
  extraRejectReason?: string,
  options: {
    avoidHighways?: boolean;
    excludeParams?: string;
    movingStartMeta?: Record<string, unknown> | null;
  } = {},
): Record<string, unknown> | null {
  if (roundTripSearch == null && extraRejectReason == null) {
    return null;
  }

  const rejectReasons = { ...(roundTripSearch?.rejectReasons ?? {}) };
  if (extraRejectReason != null) {
    rejectReasons[extraRejectReason] = (rejectReasons[extraRejectReason] ?? 0) +
      1;
  }
  const topRejectReasons = Object.fromEntries(
    Object.entries(rejectReasons)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5),
  );

  return {
    avoid_highways_requested: options.avoidHighways === true,
    effective_excludes: options.excludeParams ?? null,
    highway_allowed: options.avoidHighways !== true,
    motorway_policy: options.avoidHighways === true
      ? "exclude_motorway"
      : "allowed_not_required",
    ...(options.movingStartMeta ?? {}),
    live_fill_attempted: (roundTripSearch?.candidateAttempts ?? 0) > 0,
    live_fill_attempt_count: roundTripSearch?.candidateAttempts ?? 0,
    live_fill_success: roundTripSearch?.route != null,
    live_fill_accepted_candidates: roundTripSearch?.acceptedCandidates ?? 0,
    live_fill_rejected_candidates: roundTripSearch?.rejectedCandidates ?? 0,
    live_fill_mapbox_calls: roundTripSearch?.mapboxCallCount ?? 0,
    live_fill_evaluated_routes: roundTripSearch?.evaluatedRouteCount ?? 0,
    live_fill_guidance_hydrations: roundTripSearch?.guidanceHydrationCount ??
      0,
    search_session_id: roundTripSearch?.batchCount != null &&
        roundTripSearch.batchCount > 1
      ? `roundtrip_batch:${roundTripSearch.batchIndex ?? 0}/${
        roundTripSearch.batchCount
      }`
      : null,
    roundtrip_batch_index: roundTripSearch?.batchIndex ?? null,
    roundtrip_batch_count: roundTripSearch?.batchCount ?? null,
    roundtrip_batch_exhausted: roundTripSearch?.batchExhausted === true,
    progress_stage: roundTripSearch?.route != null
      ? "found"
      : roundTripSearch?.batchExhausted === true
      ? "batch_exhausted"
      : null,
    background_learning_queued: roundTripSearch?.batchExhausted === true,
    silent_via_used: roundTripSearch?.silentViaUsed === true,
    silent_via_waypoints: roundTripSearch?.silentViaWaypoints ?? null,
    shaping_point_count: roundTripSearch?.shapingPointCount ?? 0,
    mapbox_leg_count: roundTripSearch?.mapboxLegCount ?? null,
    arrive_maneuver_count: roundTripSearch?.arriveManeuverCount ?? null,
    silent_via_fallback_used: roundTripSearch?.silentViaFallbackUsed === true,
    guidance_degraded: roundTripSearch?.guidanceDegraded === true,
    hydration_fallback_used: roundTripSearch?.hydrationFallbackUsed === true,
    final_geometry_source: roundTripSearch?.finalGeometrySource ?? null,
    geometry_source: roundTripSearch?.geometrySource ?? null,
    final_overview: roundTripSearch?.finalOverview ?? null,
    coordinate_count: roundTripSearch?.finalCoordinateCount ?? null,
    max_segment_m: roundTripSearch?.finalMaxSegmentMeters ?? null,
    average_segment_m: roundTripSearch?.finalAverageSegmentMeters ?? null,
    display_geometry_reject_reason:
      roundTripSearch?.finalDisplayGeometryRejectReason ?? null,
    post_hydration_reject_reason:
      roundTripSearch?.postHydrationRejectReason ?? null,
    pre_hydration_quality_tier:
      roundTripSearch?.preHydrationQualityTier ?? null,
    hydration_diagnostics: roundTripSearch?.hydrationDiagnostics ?? [],
    live_fill_search_stage_success: roundTripSearch?.searchStageSuccess ??
      null,
    live_fill_candidate_family: roundTripSearch?.selectedCandidateFamily ??
      null,
    live_fill_distance_fit_tier: roundTripSearch?.distanceFitTier ?? null,
    live_fill_duplicate_skips: roundTripSearch?.duplicateSkips ?? 0,
    live_fill_exhausted: roundTripSearch?.exhausted == true,
    live_fill_emergency_duplicate_used:
      roundTripSearch?.emergencyDuplicateUsed === true,
    safe_fallback_used: roundTripSearch?.safeFallbackUsed === true,
    safe_fallback_reason: roundTripSearch?.safeFallbackReason ?? null,
    requested_style: roundTripSearch?.requestedStyle ?? null,
    delivered_style: roundTripSearch?.deliveredStyle ?? null,
    style_downgraded: roundTripSearch?.styleDowngraded === true,
    live_fill_reject_reasons: topRejectReasons,
    live_fill_reject_samples: roundTripSearch?.rejectSamples ?? [],
    live_fill_search_phases: roundTripSearch?.searchPhases ?? [],
    live_fill_last_plan_labels: (roundTripSearch?.lastPlanLabels ?? []).slice(
      0,
      12,
    ),
    search_summary: {
      candidate_attempts: roundTripSearch?.candidateAttempts ?? 0,
      accepted_candidates: roundTripSearch?.acceptedCandidates ?? 0,
      rejected_candidates: roundTripSearch?.rejectedCandidates ?? 0,
      mapbox_calls: roundTripSearch?.mapboxCallCount ?? 0,
      evaluated_routes: roundTripSearch?.evaluatedRouteCount ?? 0,
      guidance_hydrations: roundTripSearch?.guidanceHydrationCount ?? 0,
      batch_index: roundTripSearch?.batchIndex ?? null,
      batch_count: roundTripSearch?.batchCount ?? null,
      batch_exhausted: roundTripSearch?.batchExhausted === true,
      silent_via_used: roundTripSearch?.silentViaUsed === true,
      silent_via_waypoints: roundTripSearch?.silentViaWaypoints ?? null,
      shaping_point_count: roundTripSearch?.shapingPointCount ?? 0,
      mapbox_leg_count: roundTripSearch?.mapboxLegCount ?? null,
      arrive_maneuver_count: roundTripSearch?.arriveManeuverCount ?? null,
      silent_via_fallback_used: roundTripSearch?.silentViaFallbackUsed === true,
      guidance_degraded: roundTripSearch?.guidanceDegraded === true,
      hydration_fallback_used: roundTripSearch?.hydrationFallbackUsed === true,
      final_geometry_source: roundTripSearch?.finalGeometrySource ?? null,
      geometry_source: roundTripSearch?.geometrySource ?? null,
      final_overview: roundTripSearch?.finalOverview ?? null,
      coordinate_count: roundTripSearch?.finalCoordinateCount ?? null,
      max_segment_m: roundTripSearch?.finalMaxSegmentMeters ?? null,
      average_segment_m: roundTripSearch?.finalAverageSegmentMeters ?? null,
      display_geometry_reject_reason:
        roundTripSearch?.finalDisplayGeometryRejectReason ?? null,
      post_hydration_reject_reason:
        roundTripSearch?.postHydrationRejectReason ?? null,
      pre_hydration_quality_tier:
        roundTripSearch?.preHydrationQualityTier ?? null,
      hydration_diagnostics: roundTripSearch?.hydrationDiagnostics ?? [],
      search_stage_success: roundTripSearch?.searchStageSuccess ?? null,
      candidate_family: roundTripSearch?.selectedCandidateFamily ?? null,
      distance_fit_tier: roundTripSearch?.distanceFitTier ?? null,
      duplicate_skips: roundTripSearch?.duplicateSkips ?? 0,
      emergency_duplicate_used:
        roundTripSearch?.emergencyDuplicateUsed === true,
      reject_reasons: topRejectReasons,
      reject_samples: roundTripSearch?.rejectSamples ?? [],
      search_phases: roundTripSearch?.searchPhases ?? [],
      last_plan_labels: (roundTripSearch?.lastPlanLabels ?? []).slice(0, 12),
      exhausted: roundTripSearch?.exhausted == true,
    },
  };
}

const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",")
  .map((origin) => origin.trim())
  .filter((origin) => origin.length > 0);

function getCorsHeaders(req?: Request) {
  const origin = req?.headers.get("origin") ?? "";
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin)
    ? origin
    : ALLOWED_ORIGINS[0] ?? "null";
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
  };
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: getCorsHeaders(req) });
  }

  let requestDebugMeta: Record<string, unknown> | null = null;

  try {
    // 1. Parse Request
    const body = await req.json() as RequestData;
    const debugBody = body as RequestData & {
      request_id?: string;
      client_scenario_key?: string;
      client_force_fresh_variant?: boolean;
      client_trigger?: string;
    };
    if (body.action === "get_search_session") {
      return await routeSearchSessionStatusResponse(
        req,
        body.search_session_id,
      );
    }
    const {
      planning_type,
      startLocation,
      targetDistance,
      required_waypoints,
      user_waypoints,
      manual_waypoints,
      mode,
    } = body;
    const requiredWaypointArray = Array.isArray(required_waypoints)
      ? required_waypoints
      : undefined;
    const userWaypointArray = Array.isArray(user_waypoints)
      ? user_waypoints
      : undefined;
    const manualWaypointArray = Array.isArray(manual_waypoints)
      ? manual_waypoints
      : undefined;
    const suppliedUserWaypoints =
      requiredWaypointArray != null && requiredWaypointArray.length > 0
        ? requiredWaypointArray
        : userWaypointArray != null && userWaypointArray.length > 0
        ? userWaypointArray
        : manualWaypointArray;
    const preferenceAreas = Array.isArray(body.preference_areas)
      ? body.preference_areas
      : undefined;
    const isWaypointPreferenceRequest =
      body.generation_mode === "random_with_preferences" ||
      body.original_planning_type === "waypoints" ||
      body.original_planning_type === "Wegpunkte" ||
      (preferenceAreas != null && preferenceAreas.length > 0);
    const preferenceAreaCount = preferenceAreas?.length ??
      body.preference_area_count ?? 0;
    const waypointSource =
      requiredWaypointArray != null && requiredWaypointArray.length > 0
        ? "required_waypoints"
        : userWaypointArray != null && userWaypointArray.length > 0
        ? "user_waypoints"
        : manualWaypointArray != null
        ? "manual_waypoints"
        : "none";
    const waypointMode = body.waypoint_mode ??
      (planning_type === "Wegpunkte" ? "required_stops" : undefined);
    const waypointOrder = body.waypoint_order ??
      (waypointMode === "required_stops" ? "auto_optimize" : "fixed");
    const directionHint = typeof body.direction_hint === "number" &&
        Number.isFinite(body.direction_hint)
      ? normalizeBearingDegrees(Math.round(body.direction_hint))
      : undefined;
    const offsetSide = body.offset_side === -1 || body.offset_side === 1
      ? body.offset_side
      : undefined;
    const waypointShapeFactor =
      typeof body.waypoint_shape_factor === "number" &&
        Number.isFinite(body.waypoint_shape_factor)
        ? body.waypoint_shape_factor
        : undefined;
    const zigzagWaypoints = body.zigzag_waypoints === true;
    const variantHint = normalizeHint(
      body.route_variant_hint ?? body.variant_hint ?? body.style_profile,
    );
    const fingerprintHint = normalizeHint(
      body.route_fingerprint_hint ?? body.fingerprint_hint,
    );
    const previousRouteFingerprints = Array.isArray(
        body.previous_route_fingerprints,
      )
      ? body.previous_route_fingerprints
        .map((value: unknown) =>
          typeof value === "string" ? normalizeHint(value) : undefined
        )
        .filter((value: string | undefined): value is string => value != null)
        .slice(0, 12)
      : [];
    const maxCandidateAttemptsHint =
      typeof body.max_candidate_attempts === "number" &&
        Number.isFinite(body.max_candidate_attempts)
        ? body.max_candidate_attempts
        : undefined;
    const requestedRoundTripBatchCount = integerOption(
      body.roundtrip_batch_count,
    );
    const requestedRoundTripBatchIndex = integerOption(
      body.roundtrip_batch_index,
    );
    const hintSeedOffset =
      stableStringHash(`${variantHint ?? ""}|${fingerprintHint ?? ""}`) % 9973;
    debugLog(
      "[RoutingRequest]",
      JSON.stringify({
        requestId: debugBody.request_id ?? null,
        routingBuildId: ROUTING_BUILD_ID,
        routingBuildTime: ROUTING_BUILD_TIME,
        clientScenarioKey: debugBody.client_scenario_key ?? null,
        clientForceFreshVariant: debugBody.client_force_fresh_variant === true,
        clientTrigger: debugBody.client_trigger ?? null,
        planningType: planning_type,
        routeType: body.route_type ?? "ROUND_TRIP",
        mode: mode ?? "Standard",
        hasDestination: body.destination_location != null,
        originalPlanningType: body.original_planning_type ?? null,
        effectivePlanningType: body.effective_planning_type ?? null,
        generationMode: body.generation_mode ?? null,
        preferenceAreaCount,
        preferenceApplied: body.preference_applied === true,
        requiredWaypointCount: required_waypoints?.length ?? 0,
        manualWaypointCount: manual_waypoints?.length ?? 0,
        userWaypointCount: user_waypoints?.length ?? 0,
        waypointSource,
        waypointMode: waypointMode ?? null,
        waypointOrder,
        targetDistance: targetDistance ?? null,
        detourLevel: body.detour_level ?? 0,
        directionHint: directionHint ?? null,
        offsetSide: offsetSide ?? null,
        styleProfile: body.style_profile ?? null,
        waypointShapeFactor: waypointShapeFactor ?? null,
        zigzagWaypoints,
        avoidHighways: body.avoid_highways === true,
        variantHint: variantHint ?? null,
        fingerprintHint: fingerprintHint ?? null,
        previousRouteFingerprintCount: previousRouteFingerprints.length,
        maxCandidateAttemptsHint: maxCandidateAttemptsHint ?? null,
        roundtripBatchIndex: requestedRoundTripBatchIndex,
        roundtripBatchCount: requestedRoundTripBatchCount,
      }),
    );

    if (!MAPBOX_ACCESS_TOKEN) {
      throw new Error("Server Error: MAPBOX_ACCESS_TOKEN is not configured.");
    }

    // Basic validation
    if (!startLocation) {
      throw new Error("Missing startLocation");
    }

    // Coordinate validation helper
    const isValidCoord = (c: Coordinate): boolean =>
      c != null &&
      typeof c.latitude === "number" && typeof c.longitude === "number" &&
      !isNaN(c.latitude) && !isNaN(c.longitude) &&
      c.latitude >= -90 && c.latitude <= 90 &&
      c.longitude >= -180 && c.longitude <= 180;

    if (!isValidCoord(startLocation)) {
      throw new Error(
        "Invalid startLocation: coordinates out of bounds or not a number",
      );
    }
    if (body.destination_location && !isValidCoord(body.destination_location)) {
      throw new Error(
        "Invalid destination_location: coordinates out of bounds or not a number",
      );
    }
    if (suppliedUserWaypoints) {
      for (let i = 0; i < suppliedUserWaypoints.length; i++) {
        if (!isValidCoord(suppliedUserWaypoints[i])) {
          throw new Error(
            `Invalid waypoint at index ${i}: coordinates out of bounds or not a number`,
          );
        }
      }
    }
    if (
      targetDistance != null &&
      (typeof targetDistance !== "number" || isNaN(targetDistance) ||
        targetDistance <= 0 || targetDistance > 500)
    ) {
      throw new Error(
        "Invalid targetDistance: must be a number between 1 and 500",
      );
    }
    if (
      body.direction_hint != null &&
      (typeof body.direction_hint !== "number" ||
        !Number.isFinite(body.direction_hint))
    ) {
      throw new Error("Invalid direction_hint: must be a finite number");
    }
    if (
      body.offset_side != null && body.offset_side !== -1 &&
      body.offset_side !== 1
    ) {
      throw new Error("Invalid offset_side: must be -1 or 1");
    }
    if (
      body.waypoint_shape_factor != null &&
      (typeof body.waypoint_shape_factor !== "number" ||
        !Number.isFinite(body.waypoint_shape_factor))
    ) {
      throw new Error("Invalid waypoint_shape_factor: must be a finite number");
    }
    if (
      body.max_candidate_attempts != null &&
      (typeof body.max_candidate_attempts !== "number" ||
        !Number.isFinite(body.max_candidate_attempts))
    ) {
      throw new Error(
        "Invalid max_candidate_attempts: must be a finite number",
      );
    }
    if (
      body.roundtrip_batch_count != null &&
      (typeof body.roundtrip_batch_count !== "number" ||
        !Number.isFinite(body.roundtrip_batch_count))
    ) {
      throw new Error("Invalid roundtrip_batch_count: must be a finite number");
    }
    if (
      body.roundtrip_batch_index != null &&
      (typeof body.roundtrip_batch_index !== "number" ||
        !Number.isFinite(body.roundtrip_batch_index))
    ) {
      throw new Error("Invalid roundtrip_batch_index: must be a finite number");
    }
    if (
      body.waypoint_order != null && waypointOrder !== "fixed" &&
      waypointOrder !== "auto_optimize"
    ) {
      throw new Error(
        "Invalid waypoint_order: must be fixed or auto_optimize.",
      );
    }

    const normalizeRoundTripUserWaypoints = (
      waypoints: Coordinate[],
    ): Coordinate[] => {
      const normalized = [...waypoints];
      if (
        normalized.length > 0 &&
        calculateDistance(normalized[0], startLocation) <= 0.15
      ) {
        normalized.shift();
      }
      if (
        normalized.length > 0 &&
        calculateDistance(normalized[normalized.length - 1], startLocation) <=
          0.15
      ) {
        normalized.pop();
      }
      return normalized;
    };

    const bearingSpreadDegrees = (bearings: number[]): number => {
      if (bearings.length === 0) return 0;
      const normalized = bearings
        .map((bearing) => ((bearing % 360) + 360) % 360)
        .sort((a, b) => a - b);
      let largestGap = 0;
      for (let i = 0; i < normalized.length; i++) {
        const current = normalized[i];
        const next = normalized[(i + 1) % normalized.length] +
          (i === normalized.length - 1 ? 360 : 0);
        largestGap = Math.max(largestGap, next - current);
      }
      return 360 - largestGap;
    };

    const waypointRadiusesForPlan = (
      waypoints: Coordinate[],
      requiredStops: Coordinate[],
    ): string =>
      waypoints
        .map((point, i) => {
          if (i === 0 || i === waypoints.length - 1) return "unlimited";
          const required = requiredStops.some((stop) =>
            Math.abs(stop.latitude - point.latitude) < 1e-9 &&
            Math.abs(stop.longitude - point.longitude) < 1e-9
          );
          return required ? "150" : "4500";
        })
        .join(";");

    const waypointReachDistancesMeters = (
      coordinates: unknown,
      waypoints: Coordinate[],
    ): number[] => {
      if (!Array.isArray(coordinates)) {
        return waypoints.map(() => Number.POSITIVE_INFINITY);
      }
      return waypoints.map((waypoint) => {
        let bestMeters = Number.POSITIVE_INFINITY;
        for (const raw of coordinates) {
          if (!Array.isArray(raw) || raw.length < 2) continue;
          const lng = Number(raw[0]);
          const lat = Number(raw[1]);
          if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
          const meters = calculateDistance(
            { latitude: lat, longitude: lng },
            waypoint,
          ) * 1000;
          if (meters < bestMeters) bestMeters = meters;
        }
        return Math.round(bestMeters);
      });
    };

    const avoidHighways = body.avoid_highways === true;
    const requestContinueStraight = body.continue_straight !== false;
    const randomSeed = (body.randomSeed ?? Math.floor(Math.random() * 100000)) +
      hintSeedOffset;
    const requestStartedAt = Date.now();

    // --- 2. Fahrstil-Parameter (Mapbox) ---
    // Jeder Stil nutzt unterschiedliche Mapbox-Profile und Exclude-Parameter.
    // Da Mapbox kein "prefer" unterstützt, erzwingen wir Straßentypen durch
    // Excludes + stilspezifische Waypoint-Platzierung (siehe Subtask 2).
    let mapboxProfile = "mapbox/driving";
    let excludeParams = "";
    let radiusesParams = "";

    if (mode === "Kurvenjagd") {
      // Der Autobahn-Toggle ist die Quelle der Wahrheit. Kurvenjagd schließt
      // ohne Toggle keine Autobahnen hart aus, hält aber Maut/Fähren raus.
      mapboxProfile = "mapbox/driving";
      excludeParams = "toll,ferry";
    } else if (mode === "Sport Mode") {
      // Sport Mode = flüssig & schnell. Unpaved raus, damit Mapbox keine
      // Forst-/Bergstraßen oder Schotter in die Strecke schmuggelt. Autobahn
      // steuert ausschließlich der Toggle.
      mapboxProfile = "mapbox/driving";
      excludeParams = "ferry,unpaved";
    } else if (mode === "Abendrunde") {
      // Abendrunde vermeidet Fähren/Unpaved, Autobahnen nur auf Toggle.
      mapboxProfile = "mapbox/driving-traffic";
      excludeParams = "ferry,unpaved";
    } else if (mode === "Entdecker") {
      // Entdecker hält nur Maut fern, Autobahnen nur auf Toggle.
      mapboxProfile = "mapbox/driving";
      excludeParams = "toll";
    } else {
      // Standard: minimal eingeschränkt
      mapboxProfile = "mapbox/driving";
      excludeParams = "ferry";
    }

    // --- 3. Flexible Planung ---
    let finalWaypoints: Coordinate[] = [];
    let distanceConfig: DistanceConfig | null = null;
    let effectiveTargetDistanceKm: number | null = null;
    let route = null;
    let pointToPointIsScenic = false;
    let pointToPointDirectDistanceKm = 0;
    let pointToPointDirectDurationMin: number | null = null;
    let pointToPointEffectiveTargetDistanceKm: number | undefined;
    let pointToPointDestinationDistanceMeters: number | null = null;
    // Default to ROUND_TRIP if not specified, for backward compatibility or default 'Zufall' behavior
    const currentRouteType = body.route_type || "ROUND_TRIP";
    const detourLevel = Math.max(0, Math.min(3, body.detour_level ?? 0));
    let pointToPointDeliveredDetourLevel = detourLevel;
    let pointToPointDetourDowngraded = false;
    let pointToPointDetourFallbackStage: string | null = null;
    let pointToPointDeliveredTargetDistanceKm: number | undefined;
    let pointToPointCorridorFamilies: PointToPointCorridorFamily[] = [];
    let pointToPointSelectedCorridorFamily: PointToPointCorridorFamily | null =
      null;
    let pointToPointRejectedCorridorFamilies: string[] = [];
    let pointToPointVariantAttemptIndex = 0;
    let pointToPointDuplicateSkipped = 0;
    let normalizedUserWaypointsForMeta: Coordinate[] = [];
    let waypointLayoutScore: number | null = null;
    let waypointOrderDelivered: number[] | null = null;
    let waypointAutoOptimizeAttemptCount = 0;
    let waypointAutoOptimizeSelectedIndex: number | null = null;
    let waypointRoutingMeta: Record<string, unknown> | null = null;
    let waypointReachMeta: {
      userWaypointCount: number;
      reachedCount: number;
      allReached: boolean;
      reachDistancesMeters: number[];
      thresholdMeters: number;
    } | null = null;

    if (isWaypointPreferenceRequest) {
      if (currentRouteType !== "ROUND_TRIP") {
        throw new Error(
          "Invalid preference_areas: waypoint preferences are only supported for round trips.",
        );
      }
      if (!preferenceAreas || preferenceAreas.length === 0) {
        throw new Error(
          "too_few_waypoints: Set at least one preference area.",
        );
      }
      if (preferenceAreas.length > 3) {
        throw new Error(
          "too_many_waypoints: Waypoint preference mode supports at most 3 areas.",
        );
      }

      const maxPreferenceDistanceKm = Math.max(
        12,
        Math.min(80, (targetDistance ?? 50) * 0.75),
      );
      for (let i = 0; i < preferenceAreas.length; i++) {
        const area = preferenceAreas[i];
        if (!isValidCoord(area)) {
          throw new Error(
            `Invalid preference_area at index ${i}: coordinates out of bounds or not a number`,
          );
        }
        const distanceFromStartKm = calculateDistance(startLocation, area);
        if (distanceFromStartKm <= 0.2) {
          throw new Error(
            `waypoint_duplicate_or_too_close: preference area ${i} is too close to start.`,
          );
        }
        if (distanceFromStartKm > maxPreferenceDistanceKm) {
          throw new Error(
            `waypoint_too_far: preference area ${i} is ${
              distanceFromStartKm.toFixed(1)
            }km from start.`,
          );
        }
        for (let j = 0; j < i; j++) {
          if (calculateDistance(preferenceAreas[j], area) <= 0.2) {
            throw new Error(
              `waypoint_duplicate_or_too_close: preference areas ${j} and ${i} are too close.`,
            );
          }
        }
      }
    }
    const buildPreferenceNotMatchableMeta = (
      baseMeta: Record<string, unknown> | null,
      reason: string,
    ): Record<string, unknown> => ({
      ...(baseMeta ?? {}),
      response_code: "preference_areas_not_matchable",
      original_planning_type: body.original_planning_type ?? null,
      effective_planning_type: body.effective_planning_type ?? null,
      generation_mode: body.generation_mode ?? null,
      preference_area_count: preferenceAreaCount,
      preference_applied: body.preference_applied === true,
      preference_ignored_reason: reason,
    });

    if (planning_type === "Zufall" && currentRouteType === "ROUND_TRIP") {
      if (mode === "Kurvenjagd") {
        excludeParams = "ferry";
      } else if (mode === "Sport Mode") {
        // Sport-Rundkurs: Unpaved bleibt draußen, sonst landen wir gerne
        // auf Wald-/Bergwegen (Dornbirn-Bergpässe).
        excludeParams = "ferry,unpaved";
      } else if (mode === "Abendrunde") {
        mapboxProfile = "mapbox/driving";
        excludeParams = "ferry";
      } else if (mode === "Entdecker") {
        excludeParams = "";
      }
      excludeParams = applyAvoidHighwaysExcludes(
        excludeParams,
        avoidHighways,
      );
    }

    if (planning_type === "Zufall") {
      if (currentRouteType === "POINT_TO_POINT") {
        // A→B: direkte Straßenroute, optional ohne Autobahnen.
        // Stil-Excludes wie beim Rundkurs, damit Kurvenjagd/Sport/Entdecker
        // technisch spürbar auseinanderlaufen (nicht nur Waypoint-Form).
        mapboxProfile = mode === "Abendrunde"
          ? "mapbox/driving-traffic"
          : "mapbox/driving";
        const stylePointToPointBase = mode === "Sport Mode"
          ? "ferry,unpaved"
          : mode === "Kurvenjagd"
          ? "ferry"
          : mode === "Entdecker"
          ? "toll"
          : mode === "Abendrunde"
          ? "ferry,unpaved"
          : "ferry";
        excludeParams = applyAvoidHighwaysExcludes(
          stylePointToPointBase,
          avoidHighways,
        );
        if (!body.destination_location) {
          throw new Error(
            "For 'POINT_TO_POINT' planning, a destination_location is required.",
          );
        }
        const straightLineDistanceKm = calculateDistance(
          startLocation,
          body.destination_location,
        );
        if (straightLineDistanceKm < 0.25) {
          throw new Error(
            "Start and destination are too close for POINT_TO_POINT planning.",
          );
        }
        pointToPointDirectDistanceKm = straightLineDistanceKm;
        const requestedPointToPointScenic = detourLevel > 0 ||
          (mode != null && mode !== "Standard");
        const directWaypoints = [startLocation, body.destination_location];
        const directRadiuses = "unlimited;unlimited";
        let directRoute = await getMapboxRoute(
          directWaypoints,
          mapboxProfile,
          excludeParams,
          directRadiuses,
          MAPBOX_ACCESS_TOKEN,
          {
            continueStraight: requestContinueStraight,
            maxAttempts: 1,
            timeoutMs: 6500,
          },
        );
        const relaxedDirectExcludes = relaxStreetExcludes(
          excludeParams,
          avoidHighways,
        );
        if (!directRoute && relaxedDirectExcludes !== excludeParams) {
          directRoute = await getMapboxRoute(
            directWaypoints,
            mapboxProfile,
            relaxedDirectExcludes,
            directRadiuses,
            MAPBOX_ACCESS_TOKEN,
            {
              continueStraight: requestContinueStraight,
              maxAttempts: 1,
              timeoutMs: 6000,
            },
          );
        }
        if (!directRoute) {
          throw new Error(
            "Direct A->B route not found with current constraints.",
          );
        }
        const directRouteDistanceKm = getRouteDistanceKm(directRoute);
        if (directRouteDistanceKm > 0) {
          pointToPointDirectDistanceKm = directRouteDistanceKm;
        }
        pointToPointDirectDurationMin = typeof directRoute.duration === "number"
          ? directRoute.duration / 60
          : null;
        pointToPointIsScenic = requestedPointToPointScenic;
        const detourTargetMultiplier = detourLevel === 1
          ? 1.32
          : detourLevel === 2
          ? 1.65
          : detourLevel >= 3
          ? 2.10
          : 1.0;
        pointToPointEffectiveTargetDistanceKm = pointToPointIsScenic
          ? Math.max(
            targetDistance ?? 0,
            pointToPointDirectDistanceKm * detourTargetMultiplier,
          )
          : pointToPointDirectDistanceKm;
        pointToPointDeliveredTargetDistanceKm =
          pointToPointEffectiveTargetDistanceKm;
        pointToPointCorridorFamilies = pointToPointIsScenic
          ? selectPointToPointCorridorFamilies({
            mode,
            detourLevel,
            randomSeed,
            variantHint,
            maxCandidateAttempts: maxCandidateAttemptsHint,
          })
          : [];
        const initialCorridorFamily = pointToPointCorridorFamilies[0];

        finalWaypoints = pointToPointIsScenic
          ? buildPointToPointScenicWaypoints({
            start: startLocation,
            destination: body.destination_location,
            mode,
            targetDistance: pointToPointEffectiveTargetDistanceKm,
            detourLevel,
            detourFactor: body.detour_factor,
            directReferenceDistanceKm: pointToPointDirectDistanceKm,
            corridorFamily: initialCorridorFamily,
            offsetSide,
            waypointShapeFactor,
            zigzagWaypoints,
            randomSeed,
            simplifyWaypoints: body.simplify_waypoints === true,
            maxWaypoints: body.max_waypoints,
          })
          : directWaypoints;
        if (!pointToPointIsScenic) {
          route = directRoute;
          radiusesParams = directRadiuses;
        }
        const scenicRadiusMeters = detourLevel >= 3
          ? Math.min(
            11500,
            Math.max(4700, Math.round(pointToPointDirectDistanceKm * 240)),
          )
          : detourLevel === 2
          ? Math.min(
            9000,
            Math.max(3800, Math.round(pointToPointDirectDistanceKm * 205)),
          )
          : detourLevel === 1
          ? Math.min(
            6800,
            Math.max(2800, Math.round(pointToPointDirectDistanceKm * 165)),
          )
          : 6000;
        const scenicRadius = `${scenicRadiusMeters}`;
        radiusesParams = finalWaypoints
          .map((_, i) =>
            (i === 0 || i === finalWaypoints.length - 1)
              ? "unlimited"
              : scenicRadius
          )
          .join(";");
      } else {
        // ROUND_TRIP logic
        if (!targetDistance) {
          throw new Error(
            "For 'Zufall' planning, a targetDistance is required.",
          );
        }

        const hintedTargetDistance = avoidHighways && targetDistance > 60
          ? parseRoundTripTargetHintKm(variantHint)
          : null;
        const stableNoHighwayTarget = hintedTargetDistance != null &&
            hintedTargetDistance >= 60 &&
            hintedTargetDistance <= 115 &&
            Math.abs(hintedTargetDistance - targetDistance) <=
              Math.max(8, hintedTargetDistance * 0.18)
          ? hintedTargetDistance
          : targetDistance;
        // Product distances are capped at 100 km. No-highway
        // medium/long force-fresh variants may intentionally send a shifted
        // target (e.g. k75 -> 69/82) for diversity; server-side geometry
        // gates must still evaluate against the selected distance bucket.
        const effectiveDistance = Math.min(stableNoHighwayTarget, 100);
        distanceConfig = getDistanceConfig(effectiveDistance, mode);
        effectiveTargetDistanceKm = effectiveDistance;
      }
    } else if (planning_type === "Wegpunkte") {
      if (currentRouteType !== "ROUND_TRIP") {
        throw new Error(
          "waypoint_route_not_possible: Wegpunkte planning currently supports ROUND_TRIP only.",
        );
      }
      if (body.close_loop === false) {
        throw new Error(
          "waypoint_route_not_possible: close_loop must be true for waypoint roundtrip planning.",
        );
      }
      const normalizedUserWaypoints = normalizeRoundTripUserWaypoints(
        suppliedUserWaypoints ?? [],
      );
      normalizedUserWaypointsForMeta = normalizedUserWaypoints;
      if (normalizedUserWaypoints.length < 1) {
        throw new Error(
          "too_few_waypoints: Set at least one waypoint for waypoint roundtrip planning.",
        );
      }
      if (normalizedUserWaypoints.length > 3) {
        throw new Error(
          "too_many_waypoints: Waypoint roundtrip planning supports at most 3 required waypoints.",
        );
      }
      const maxWaypointDistanceKm = targetDistance != null
        ? Math.max(12, Math.min(80, targetDistance * 0.75))
        : 50;
      const maxLegDistanceKm = targetDistance != null
        ? Math.max(20, targetDistance * 0.85)
        : 45;
      const bearingsFromStart: number[] = [];
      let previousWaypoint = startLocation;
      for (let i = 0; i < normalizedUserWaypoints.length; i++) {
        const waypoint = normalizedUserWaypoints[i];
        const distanceFromStartKm = calculateDistance(startLocation, waypoint);
        if (distanceFromStartKm < 0.20) {
          throw new Error(
            `waypoint_duplicate_or_too_close: waypoint ${i} is too close to start.`,
          );
        }
        if (distanceFromStartKm > maxWaypointDistanceKm) {
          throw new Error(
            `waypoint_too_far: waypoint ${i} is ${
              distanceFromStartKm.toFixed(1)
            }km from start and exceeds local limit ${
              maxWaypointDistanceKm.toFixed(1)
            }km.`,
          );
        }
        const legDistanceKm = calculateDistance(previousWaypoint, waypoint);
        if (legDistanceKm > maxLegDistanceKm) {
          throw new Error(
            `waypoint_layout_unstable: waypoint leg ${i} is ${
              legDistanceKm.toFixed(1)
            }km and too long for this roundtrip.`,
          );
        }
        for (let j = 0; j < i; j++) {
          const pairDistanceKm = calculateDistance(
            normalizedUserWaypoints[j],
            waypoint,
          );
          if (pairDistanceKm < 0.20) {
            throw new Error(
              `waypoint_duplicate_or_too_close: waypoints ${j} and ${i} are too close.`,
            );
          }
        }
        bearingsFromStart.push(calculateBearing(startLocation, waypoint));
        previousWaypoint = waypoint;
      }
      const closingLegDistanceKm = calculateDistance(
        previousWaypoint,
        startLocation,
      );
      if (closingLegDistanceKm > maxLegDistanceKm) {
        throw new Error(
          `waypoint_layout_unstable: closing leg is ${
            closingLegDistanceKm.toFixed(1)
          }km and too long for this roundtrip.`,
        );
      }
      const bearingSpread = bearingSpreadDegrees(bearingsFromStart);
      waypointLayoutScore = Math.min(1, Math.max(0, bearingSpread / 180));
      excludeParams = applyAvoidHighwaysExcludes(excludeParams, avoidHighways);
      finalWaypoints = [
        startLocation,
        ...normalizedUserWaypoints,
        startLocation,
      ];
      radiusesParams = waypointRadiusesForPlan(
        finalWaypoints,
        normalizedUserWaypoints,
      );
    } else {
      throw new Error(
        "Invalid planning_type. Must be 'Zufall' or 'Wegpunkte'.",
      );
    }

    debugLog(
      "[RoutingResolvedConfig]",
      JSON.stringify({
        requestId: debugBody.request_id ?? null,
        routingBuildId: ROUTING_BUILD_ID,
        routingBuildTime: ROUTING_BUILD_TIME,
        clientScenarioKey: debugBody.client_scenario_key ?? null,
        clientTrigger: debugBody.client_trigger ?? null,
        routeType: currentRouteType,
        mode: mode ?? "Standard",
        planningType: planning_type,
        originalPlanningType: body.original_planning_type ?? null,
        effectivePlanningType: body.effective_planning_type ?? null,
        generationMode: body.generation_mode ?? null,
        preferenceAreaCount,
        preferenceApplied: body.preference_applied === true,
        styleProfile: body.style_profile ?? null,
        avoidHighwaysRequested: avoidHighways,
        mapboxProfile,
        effectiveExcludes: excludeParams || "none",
        simplifyWaypoints: body.simplify_waypoints === true,
        maxWaypoints: body.max_waypoints ?? null,
        targetDistance: targetDistance ?? null,
        effectiveTargetDistanceKm,
        waypointMode: waypointMode ?? null,
        waypointOrder,
        requiredWaypointCount: normalizedUserWaypointsForMeta.length,
      }),
    );

    // Radiuses: Start/Ende unlimited (echte GPS-Position), Zwischenpunkte max 1000m
    // Kleiner Radius = Waypoints müssen nahe einer Straße liegen → verhindert "Abkürzungen"
    // durch Gelände wo keine Straße existiert
    if (!radiusesParams && finalWaypoints.length > 0) {
      radiusesParams = finalWaypoints
        .map((_, i) =>
          (i === 0 || i === finalWaypoints.length - 1) ? "unlimited" : "1000"
        )
        .join(";");
    }

    // --- Execute Route Request (with retries) ---
    let roundTripSearch: RoundTripSearchResult | null = null;
    let highwayAllowedNoHighwayFallbackUsed = false;
    const useRoundTripSearch = planning_type === "Zufall" &&
      currentRouteType === "ROUND_TRIP" &&
      distanceConfig != null &&
      targetDistance != null;
    const movingStartDetected = useRoundTripSearch &&
      body.moving_start === true &&
      (finiteNumber(body.current_speed_mps) ?? 0) >= 2.5;
    const currentHeading = finiteNumber(body.current_heading);
    const startRadiusMeters = finiteNumber(body.start_radius_m);
    const startBearingToleranceDegrees = finiteNumber(
      body.start_bearing_tolerance_deg,
    );
    const avoidManeuverRadiusMeters = finiteNumber(
      body.avoid_maneuver_radius_m,
    );
    const movingStartMeta = useRoundTripSearch
      ? {
        moving_start_detected: movingStartDetected,
        start_snap_strategy: movingStartDetected
          ? currentHeading == null
            ? "moving_radius_snap"
            : "moving_bearing_radius_snap"
          : "default_roundtrip_snap",
        start_on_motorway: typeof body.start_on_motorway === "boolean"
          ? body.start_on_motorway
          : null,
        current_heading_used: movingStartDetected && currentHeading != null
          ? Math.round(clampNumber(currentHeading, 0, 359))
          : null,
        start_radius_m_used: movingStartDetected && startRadiusMeters != null
          ? Math.round(clampNumber(startRadiusMeters, 5, 300))
          : null,
        start_bearing_tolerance_deg_used:
          movingStartDetected && startBearingToleranceDegrees != null
            ? Math.round(clampNumber(startBearingToleranceDegrees, 15, 90))
            : null,
        avoid_maneuver_radius_used:
          movingStartDetected && avoidManeuverRadiusMeters != null
            ? Math.round(clampNumber(avoidManeuverRadiusMeters, 1, 1000))
            : null,
      }
      : null;
    const roundTripTargetForBatching = effectiveTargetDistanceKm ??
      targetDistance ?? 0;
    const forceRoundTripSearchSession =
      body.force_roundtrip_search_session === true ||
      body.interactive_roundtrip_search === true;
    const shortNoHighwayRoundTripNeedsSession =
      useRoundTripSearch &&
      planning_type === "Zufall" &&
      avoidHighways &&
      roundTripTargetForBatching >= 45;
    const inferredRoundTripBatchCount = useRoundTripSearch &&
        planning_type === "Zufall" &&
        (
          forceRoundTripSearchSession ||
          shortNoHighwayRoundTripNeedsSession ||
          roundTripTargetForBatching >= 70 ||
          (avoidHighways && roundTripTargetForBatching >= 60) ||
          roundTripTargetForBatching >= 90 ||
          mode === "Entdecker"
        )
      ? 3
      : 1;
    const effectiveRoundTripBatchCount = useRoundTripSearch
      ? Math.max(
        1,
        Math.min(4, requestedRoundTripBatchCount ?? inferredRoundTripBatchCount),
      )
      : 1;
    const effectiveRoundTripBatchIndex = effectiveRoundTripBatchCount <= 1
      ? 0
      : Math.max(
        0,
        Math.min(
          effectiveRoundTripBatchCount - 1,
          requestedRoundTripBatchIndex ?? 0,
        ),
      );
    const pointToPointTimeBudgetMs = currentRouteType === "POINT_TO_POINT"
      ? Math.max(
        pointToPointIsScenic
          ? avoidHighways || detourLevel >= 2 ? 24000 : 19000
          : 12000,
        Math.min(26000, Math.max(0, body.max_search_ms ?? 0)),
      )
      : 0;
    const waypointTimeBudgetMs =
      planning_type === "Wegpunkte" && currentRouteType === "ROUND_TRIP"
        ? Math.max(12000, Math.min(35000, body.max_search_ms ?? 33000))
        : 0;
    const pointToPointTimeRemainingMs = () =>
      pointToPointTimeBudgetMs <= 0
        ? Number.POSITIVE_INFINITY
        : pointToPointTimeBudgetMs - (Date.now() - requestStartedAt);
    const hasPointToPointBudgetLeft = (reserveMs = 0) =>
      pointToPointTimeBudgetMs <= 0 ||
      pointToPointTimeRemainingMs() > reserveMs;
    const pointToPointTimeoutMs = (
      preferredMs: number,
      minimumMs = 2500,
    ) =>
      pointToPointTimeBudgetMs <= 0 ? preferredMs : Math.max(
        minimumMs,
        Math.min(preferredMs, pointToPointTimeRemainingMs() - 350),
      );
    const fetchPointToPointScenicRoute = async ({
      waypoints,
      radiuses,
      exclude,
      detourLevelForBand,
      targetDistanceForBand,
      corridorFamily,
      fallbackStage,
      timeoutMs,
      continueStraight,
      relaxedBand = false,
    }: {
      waypoints: Coordinate[];
      radiuses: string;
      exclude: string;
      detourLevelForBand: number;
      targetDistanceForBand?: number;
      corridorFamily?: PointToPointCorridorFamily;
      fallbackStage: string;
      timeoutMs: number;
      continueStraight: boolean;
      relaxedBand?: boolean;
    }) => {
      const detailed = await getMapboxRouteDetailed(
        waypoints,
        mapboxProfile,
        exclude,
        radiuses,
        MAPBOX_ACCESS_TOKEN,
        {
          continueStraight,
          alternatives: true,
          maxAttempts: 1,
          timeoutMs: pointToPointTimeoutMs(timeoutMs),
          retryDelayBaseMs: 220,
        },
      );
      const candidateRoutes = detailed.routes ??
        (detailed.route ? [detailed.route] : []);
      let bestRoute: any | null = null;
      let bestScore = Number.POSITIVE_INFINITY;
      for (let i = 0; i < candidateRoutes.length; i++) {
        const candidate = candidateRoutes[i];
        const quality = evaluateRouteQuality(candidate, currentRouteType, {
          mode,
          avoidHighways,
        });
        if (!quality.passed) {
          continue;
        }
        if (
          !isPointToPointDetourAcceptable(
            candidate,
            pointToPointDirectDistanceKm,
            targetDistanceForBand,
            detourLevelForBand,
            relaxedBand,
          )
        ) {
          continue;
        }
        const candidateDistanceKm = getRouteDistanceKm(candidate);
        const targetDeltaKm = targetDistanceForBand != null
          ? Math.abs(candidateDistanceKm - targetDistanceForBand)
          : 0;
        const downgradePenalty = detourLevelForBand < detourLevel ? 35 : 0;
        const score = quality.score + targetDeltaKm * 1.4 + i * 4 +
          downgradePenalty;
        if (score < bestScore) {
          bestScore = score;
          bestRoute = candidate;
        }
      }
      if (bestRoute) {
        pointToPointSelectedCorridorFamily = corridorFamily ?? null;
        pointToPointDetourFallbackStage = fallbackStage;
        return bestRoute;
      }
      if (corridorFamily) {
        pointToPointRejectedCorridorFamilies.push(corridorFamily);
      }
      return null;
    };
    if (useRoundTripSearch) {
      roundTripSearch = await searchBestRoundTripRoute({
        startLocation,
        targetDistanceKm: effectiveTargetDistanceKm ?? targetDistance!,
        distanceConfig: distanceConfig!,
        mode,
        randomSeed,
        directionHintDegrees: directionHint,
        waypointShapeFactor,
        zigzagWaypoints,
        mapboxProfile,
        excludeParams,
        accessToken: MAPBOX_ACCESS_TOKEN,
        variantHint,
        fingerprintHint,
        previousRouteFingerprints: previousRouteFingerprints.slice(0, 5),
        maxCandidateAttemptsHint,
        batchIndex: effectiveRoundTripBatchIndex,
        batchCount: effectiveRoundTripBatchCount,
        simplifyWaypoints: body.simplify_waypoints === true,
        maxWaypoints: body.max_waypoints,
        continueStraight: requestContinueStraight,
        avoidHighways,
        preferenceAreas,
        movingStartOptions: movingStartMeta == null ? undefined : {
          movingStartDetected,
          currentHeading: currentHeading == null
            ? undefined
            : clampNumber(currentHeading, 0, 359),
          startRadiusMeters: startRadiusMeters == null
            ? undefined
            : clampNumber(startRadiusMeters, 5, 300),
          startBearingToleranceDegrees: startBearingToleranceDegrees == null
            ? undefined
            : clampNumber(startBearingToleranceDegrees, 15, 90),
          avoidManeuverRadiusMeters: avoidManeuverRadiusMeters == null
            ? undefined
            : clampNumber(avoidManeuverRadiusMeters, 1, 1000),
          startSnapStrategy: String(movingStartMeta.start_snap_strategy),
          startOnMotorway: typeof body.start_on_motorway === "boolean"
            ? body.start_on_motorway
            : null,
        },
        debugRejectCandidates: body.debug_reject_candidates === true,
        maxDebugRejectCandidates:
          finiteNumber(body.max_debug_reject_candidates) ??
            undefined,
      });
      if (
        !roundTripSearch?.route &&
        effectiveRoundTripBatchCount > 1 &&
        roundTripSessionCandidateQueue(roundTripSearch).length < 3
      ) {
        const attemptedBatchIndexes = new Set<number>([
          effectiveRoundTripBatchIndex,
        ]);
        for (
          let nextBatchIndex = 0;
          nextBatchIndex < effectiveRoundTripBatchCount &&
          roundTripSessionCandidateQueue(roundTripSearch).length < 3;
          nextBatchIndex += 1
        ) {
          if (attemptedBatchIndexes.has(nextBatchIndex)) continue;
          attemptedBatchIndexes.add(nextBatchIndex);
          const supplementalSearch = await searchBestRoundTripRoute({
            startLocation,
            targetDistanceKm: effectiveTargetDistanceKm ?? targetDistance!,
            distanceConfig: distanceConfig!,
            mode,
            randomSeed: randomSeed + (nextBatchIndex + 1) * 104_729,
            directionHintDegrees: directionHint,
            waypointShapeFactor,
            zigzagWaypoints,
            mapboxProfile,
            excludeParams,
            accessToken: MAPBOX_ACCESS_TOKEN,
            variantHint: variantHint == null
              ? `session-batch-${nextBatchIndex}`
              : `${variantHint}-session-batch-${nextBatchIndex}`,
            fingerprintHint,
            previousRouteFingerprints: previousRouteFingerprints.slice(0, 5),
            maxCandidateAttemptsHint,
            batchIndex: nextBatchIndex,
            batchCount: effectiveRoundTripBatchCount,
            simplifyWaypoints: body.simplify_waypoints === true,
            maxWaypoints: body.max_waypoints,
            continueStraight: requestContinueStraight,
            avoidHighways,
            preferenceAreas,
            movingStartOptions: movingStartMeta == null ? undefined : {
              movingStartDetected,
              currentHeading: currentHeading == null
                ? undefined
                : clampNumber(currentHeading, 0, 359),
              startRadiusMeters: startRadiusMeters == null
                ? undefined
                : clampNumber(startRadiusMeters, 5, 300),
              startBearingToleranceDegrees: startBearingToleranceDegrees == null
                ? undefined
                : clampNumber(startBearingToleranceDegrees, 15, 90),
              avoidManeuverRadiusMeters: avoidManeuverRadiusMeters == null
                ? undefined
                : clampNumber(avoidManeuverRadiusMeters, 1, 1000),
              startSnapStrategy: String(movingStartMeta.start_snap_strategy),
              startOnMotorway: typeof body.start_on_motorway === "boolean"
                ? body.start_on_motorway
                : null,
            },
            debugRejectCandidates: body.debug_reject_candidates === true,
            maxDebugRejectCandidates:
              finiteNumber(body.max_debug_reject_candidates) ??
                undefined,
          });
          if (supplementalSearch != null) {
            roundTripSearch = roundTripSearch == null
              ? supplementalSearch
              : mergeRoundTripBatchResults(roundTripSearch, supplementalSearch);
          }
        }
      }
      if (
        !roundTripSearch?.route && !avoidHighways &&
        effectiveRoundTripBatchCount <= 1
      ) {
        const noHighwayExcludeParams = applyAvoidHighwaysExcludes(
          excludeParams,
          true,
        );
        const noHighwayFallbackSearch = await searchBestRoundTripRoute({
          startLocation,
          targetDistanceKm: effectiveTargetDistanceKm ?? targetDistance!,
          distanceConfig: distanceConfig!,
          mode,
          randomSeed: randomSeed + 7919,
          directionHintDegrees: directionHint,
          waypointShapeFactor,
          zigzagWaypoints,
          mapboxProfile,
          excludeParams: noHighwayExcludeParams,
          accessToken: MAPBOX_ACCESS_TOKEN,
          variantHint: variantHint == null
            ? "highway-allowed-nohighway-fallback"
            : `${variantHint}-highway-allowed-nohighway-fallback`,
          fingerprintHint,
          previousRouteFingerprints: previousRouteFingerprints.slice(0, 5),
          maxCandidateAttemptsHint,
          batchIndex: 0,
          batchCount: 1,
          simplifyWaypoints: body.simplify_waypoints === true,
          maxWaypoints: body.max_waypoints,
          continueStraight: requestContinueStraight,
          avoidHighways: true,
          preferenceAreas,
          movingStartOptions: movingStartMeta == null ? undefined : {
            movingStartDetected,
            currentHeading: currentHeading == null
              ? undefined
              : clampNumber(currentHeading, 0, 359),
            startRadiusMeters: startRadiusMeters == null
              ? undefined
              : clampNumber(startRadiusMeters, 5, 300),
            startBearingToleranceDegrees: startBearingToleranceDegrees == null
              ? undefined
              : clampNumber(startBearingToleranceDegrees, 15, 90),
            avoidManeuverRadiusMeters: avoidManeuverRadiusMeters == null
              ? undefined
              : clampNumber(avoidManeuverRadiusMeters, 1, 1000),
            startSnapStrategy: String(movingStartMeta.start_snap_strategy),
            startOnMotorway: typeof body.start_on_motorway === "boolean"
              ? body.start_on_motorway
              : null,
          },
          debugRejectCandidates: body.debug_reject_candidates === true,
          maxDebugRejectCandidates:
            finiteNumber(body.max_debug_reject_candidates) ??
              undefined,
        });
        if (noHighwayFallbackSearch?.route) {
          roundTripSearch = noHighwayFallbackSearch;
          highwayAllowedNoHighwayFallbackUsed = true;
        }
      }
      if (roundTripSearch?.route) {
        route = roundTripSearch.route;
        finalWaypoints = roundTripSearch.waypoints;
        radiusesParams = roundTripSearch.radiuses;
        debugLog(
          `[RT] Search summary: attempts=${roundTripSearch.candidateAttempts}, accepted=${roundTripSearch.acceptedCandidates}, rejected=${roundTripSearch.rejectedCandidates}, chosen=${roundTripSearch.quality?.tier}`,
        );
        if (roundTripSearch.terminalShortCircuit === true) {
          debugLog(
            "[RT] Balanced short-circuit selected terminal seed result; skipping post-search scaling/rescue.",
          );
        }
      }
    } else if (!route) {
      if (planning_type === "Wegpunkte") {
        const waypointSearch = await routeRequiredWaypointRoundTrip({
          startLocation,
          requiredWaypoints: normalizedUserWaypointsForMeta,
          waypointOrder: waypointOrder === "fixed" ? "fixed" : "auto_optimize",
          targetDistanceKm: targetDistance ?? undefined,
          mode,
          avoidHighways,
          mapboxProfile,
          excludeParams,
          accessToken: MAPBOX_ACCESS_TOKEN,
          randomSeed,
          variantHint,
          fingerprintHint,
          maxSearchMs: waypointTimeBudgetMs || 30000,
        });
        waypointRoutingMeta = waypointSearch.meta;
        waypointAutoOptimizeAttemptCount = Number(
          waypointSearch.meta.waypoint_candidate_plan_count ?? 0,
        );
        if (waypointSearch.route && waypointSearch.waypoints.length > 0) {
          route = waypointSearch.route;
          finalWaypoints = waypointSearch.waypoints;
          radiusesParams = waypointSearch.radiuses;
          waypointOrderDelivered = waypointSearch.deliveredOrder;
        } else {
          const rejectReason = waypointSearch.rejectReason;
          const responseCode = rejectReason === "waypoint_not_reached"
            ? "waypoint_not_reached"
            : rejectReason == null ||
                rejectReason === "no_route" ||
                rejectReason === "timeout" ||
                rejectReason === "http_error" ||
                rejectReason === "network_error"
            ? "waypoint_route_not_possible"
            : "waypoint_quality_too_low";
          requestDebugMeta = {
            response_code: responseCode,
            route_quality_too_low: responseCode === "waypoint_quality_too_low",
            waypoint_source: waypointSource,
            waypoint_mode: waypointMode ?? null,
            waypoint_order_requested: waypointOrder,
            requested_close_loop: body.close_loop !== false,
            normalized_user_waypoint_count:
              normalizedUserWaypointsForMeta.length,
            auto_optimize_attempt_count: waypointAutoOptimizeAttemptCount,
            reject_reason: rejectReason,
            ...(waypointRoutingMeta ?? {}),
          };
          throw new Error(
            responseCode === "waypoint_route_not_possible"
              ? "waypoint_route_not_possible: Mapbox could not connect all required stops."
              : responseCode === "waypoint_not_reached"
              ? "waypoint_not_reached: Directions route did not reach every required waypoint."
              : `waypoint_quality_too_low: ${rejectReason}`,
          );
        }
      } else {
        if (
          currentRouteType === "POINT_TO_POINT" && pointToPointIsScenic &&
          body.destination_location
        ) {
          route = await fetchPointToPointScenicRoute({
            waypoints: finalWaypoints,
            radiuses: radiusesParams,
            exclude: excludeParams,
            detourLevelForBand: detourLevel,
            targetDistanceForBand: pointToPointEffectiveTargetDistanceKm,
            corridorFamily: pointToPointCorridorFamilies[0],
            fallbackStage: "initial_corridor",
            timeoutMs: 11500,
            continueStraight: requestContinueStraight,
          });
          const relaxedPointToPointExcludes = relaxStreetExcludes(
            excludeParams,
            avoidHighways,
          );
          if (!route && relaxedPointToPointExcludes !== excludeParams) {
            route = await fetchPointToPointScenicRoute({
              waypoints: finalWaypoints,
              radiuses: radiusesParams,
              exclude: relaxedPointToPointExcludes,
              detourLevelForBand: detourLevel,
              targetDistanceForBand: pointToPointEffectiveTargetDistanceKm,
              corridorFamily: pointToPointCorridorFamilies[0],
              fallbackStage: "initial_relaxed_corridor",
              timeoutMs: 8500,
              continueStraight: requestContinueStraight,
            });
          }
        } else {
          route = await getMapboxRoute(
            finalWaypoints,
            mapboxProfile,
            excludeParams,
            radiusesParams,
            MAPBOX_ACCESS_TOKEN,
            {
              continueStraight: requestContinueStraight,
              maxAttempts: 2,
              timeoutMs: pointToPointTimeoutMs(9500),
              retryDelayBaseMs: 220,
            },
          );
          const relaxedPointToPointExcludes = relaxStreetExcludes(
            excludeParams,
            avoidHighways,
          );
          if (!route && relaxedPointToPointExcludes !== excludeParams) {
            route = await getMapboxRoute(
              finalWaypoints,
              mapboxProfile,
              relaxedPointToPointExcludes,
              radiusesParams,
              MAPBOX_ACCESS_TOKEN,
              {
                continueStraight: requestContinueStraight,
                maxAttempts: 1,
                timeoutMs: pointToPointTimeoutMs(8500),
              },
            );
          }
        }
      }

      if (route && planning_type !== "Wegpunkte") {
        const initialQuality = evaluateRouteQuality(route, currentRouteType);
        if (!initialQuality.passed) {
          debugLog(`Initial route rejected: ${initialQuality.reason}`);
          route = null;
        }
      }

      if (
        route &&
        planning_type === "Zufall" &&
        currentRouteType === "POINT_TO_POINT" &&
        body.destination_location &&
        pointToPointIsScenic &&
        !isPointToPointDetourAcceptable(
          route,
          pointToPointDirectDistanceKm,
          targetDistance,
          detourLevel,
          body.simplify_waypoints === true,
        )
      ) {
        const routeDistanceKm = getRouteDistanceKm(route);
        const minimumDistanceKm = getPointToPointMinimumDistanceKm(
          pointToPointDirectDistanceKm,
          targetDistance,
          detourLevel,
          body.simplify_waypoints === true,
        );
        const maximumDistanceKm = getPointToPointMaximumDistanceKm(
          pointToPointDirectDistanceKm,
          targetDistance,
          detourLevel,
          body.simplify_waypoints === true,
        );
        debugLog(
          `Initial P2P scenic route rejected: ${
            routeDistanceKm.toFixed(1)
          }km outside ${minimumDistanceKm.toFixed(1)}-${
            maximumDistanceKm.toFixed(1)
          }km`,
        );
        route = null;
      }
    }

    if (
      !route && planning_type === "Zufall" &&
      currentRouteType === "POINT_TO_POINT" && body.destination_location &&
      pointToPointIsScenic
    ) {
      const requestedCandidateAttempts = Math.max(
        3,
        Math.min(9, maxCandidateAttemptsHint ?? 5),
      );
      const scenicRetryCount = body.simplify_waypoints === true
        ? Math.min(4, requestedCandidateAttempts)
        : Math.max(2, requestedCandidateAttempts - 1);
      const robustNoRouteFallback = avoidHighways && detourLevel >= 2 &&
        body.simplify_waypoints !== true;
      for (
        let retry = 0;
        retry < scenicRetryCount &&
        !route &&
        hasPointToPointBudgetLeft(2200);
        retry++
      ) {
        debugLog(`P2P scenic retry ${retry + 1}: regenerating waypoints...`);
        const retryDetourLevel = detourLevel >= 3
          ? retry < scenicRetryCount - 1 ? 3 : 2
          : detourLevel === 2
          ? retry < scenicRetryCount - 1 ? 2 : 1
          : Math.max(detourLevel, 1);
        const retryDowngraded = retryDetourLevel < detourLevel;
        const retrySimplifyWaypoints = body.simplify_waypoints === true ||
          retry >= Math.max(2, scenicRetryCount - 2) ||
          robustNoRouteFallback;
        const retryMaxWaypoints = retrySimplifyWaypoints
          ? robustNoRouteFallback
            ? Math.min(
              body.max_waypoints ?? (retryDetourLevel >= 3 ? 2 : 1),
              retryDetourLevel >= 3 ? 2 : 1,
            )
            : Math.max(
              retryDetourLevel >= 2 ? 2 : 1,
              Math.min(
                3,
                retry >= 2
                  ? (retryDetourLevel >= 2 ? 2 : 1)
                  : body.max_waypoints ?? (retryDetourLevel >= 3 ? 2 : 1),
              ),
            )
          : undefined;
        const retryOffsetSide = offsetSide == null
          ? undefined
          : retry % 2 === 0
          ? offsetSide
          : -offsetSide;
        const retryCorridorFamily = pointToPointCorridorFamilies[
          (retry + 1) % Math.max(1, pointToPointCorridorFamilies.length)
        ];
        const emergencyScenicTarget = Math.max(
          retryDetourLevel >= 3
            ? pointToPointDirectDistanceKm *
              (robustNoRouteFallback ? 1.72 : 2.02)
            : retryDetourLevel === 2
            ? pointToPointDirectDistanceKm *
              (robustNoRouteFallback ? 1.42 : 1.58)
            : pointToPointDirectDistanceKm * 1.24,
          retryDetourLevel >= 3
            ? pointToPointDirectDistanceKm +
              (robustNoRouteFallback ? 16.0 : 22.0)
            : retryDetourLevel === 2
            ? pointToPointDirectDistanceKm +
              (robustNoRouteFallback ? 8.0 : 11.0)
            : pointToPointDirectDistanceKm +
              (pointToPointDirectDistanceKm < 18 ? 3.6 : 5.0),
        );
        const retryMinimumTarget = Math.max(
          emergencyScenicTarget,
          getPointToPointMinimumDistanceKm(
            pointToPointDirectDistanceKm,
            targetDistance,
            retryDetourLevel,
            true,
          ),
        );
        const sameLevelTarget = !retryDowngraded && targetDistance != null
          ? targetDistance
          : null;
        const softenedTarget = sameLevelTarget != null
          ? retry >= 2 ? retryMinimumTarget : Math.max(
            retryMinimumTarget,
            sameLevelTarget *
              (retrySimplifyWaypoints ? 0.92 : 0.97),
          )
          : retryMinimumTarget;
        const retryWaypoints = buildPointToPointScenicWaypoints({
          start: startLocation,
          destination: body.destination_location,
          mode,
          targetDistance: softenedTarget,
          detourLevel: retryDetourLevel,
          detourFactor: body.detour_factor,
          directReferenceDistanceKm: pointToPointDirectDistanceKm,
          corridorFamily: retryCorridorFamily,
          offsetSide: retryOffsetSide,
          waypointShapeFactor,
          zigzagWaypoints,
          randomSeed: randomSeed + retry + 1,
          simplifyWaypoints: retrySimplifyWaypoints,
          maxWaypoints: retryMaxWaypoints,
          robustFallback: robustNoRouteFallback,
        });
        const retryRadiusMeters = retryDetourLevel >= 3
          ? Math.min(
            robustNoRouteFallback ? 10500 : 11800,
            Math.max(
              robustNoRouteFallback ? 4300 : 5000,
              Math.round(
                pointToPointDirectDistanceKm *
                  (robustNoRouteFallback ? 220 : 250),
              ),
            ),
          )
          : retryDetourLevel === 2
          ? Math.min(
            robustNoRouteFallback ? 8400 : 9400,
            Math.max(
              robustNoRouteFallback ? 3400 : 3900,
              Math.round(
                pointToPointDirectDistanceKm *
                  (robustNoRouteFallback ? 185 : 210),
              ),
            ),
          )
          : retryDetourLevel === 1
          ? Math.min(
            7000,
            Math.max(2800, Math.round(pointToPointDirectDistanceKm * 170)),
          )
          : 7000;
        const retryRadius = `${retryRadiusMeters}`;
        const retryRadiuses = retryWaypoints
          .map((_, i) =>
            (i === 0 || i === retryWaypoints.length - 1)
              ? "unlimited"
              : retryRadius
          )
          .join(";");

        route = await fetchPointToPointScenicRoute({
          waypoints: retryWaypoints,
          radiuses: retryRadiuses,
          exclude: excludeParams,
          detourLevelForBand: retryDetourLevel,
          targetDistanceForBand: softenedTarget,
          corridorFamily: retryCorridorFamily,
          fallbackStage: retryDowngraded
            ? `downgraded_to_${retryDetourLevel}`
            : `retry_${retry + 1}_${retryCorridorFamily}`,
          timeoutMs: 9000,
          continueStraight: requestContinueStraight,
          relaxedBand: retrySimplifyWaypoints,
        });
        const relaxedRetryExcludes = relaxStreetExcludes(
          excludeParams,
          avoidHighways,
        );
        if (!route && relaxedRetryExcludes !== excludeParams) {
          route = await fetchPointToPointScenicRoute({
            waypoints: retryWaypoints,
            radiuses: retryRadiuses,
            exclude: relaxedRetryExcludes,
            detourLevelForBand: retryDetourLevel,
            targetDistanceForBand: softenedTarget,
            corridorFamily: retryCorridorFamily,
            fallbackStage: retryDowngraded
              ? `relaxed_downgraded_to_${retryDetourLevel}`
              : `relaxed_retry_${retry + 1}_${retryCorridorFamily}`,
            timeoutMs: 7800,
            continueStraight: requestContinueStraight,
            relaxedBand: retrySimplifyWaypoints,
          });
        }
        if (route) {
          finalWaypoints = retryWaypoints;
          radiusesParams = retryRadiuses;
          pointToPointDeliveredDetourLevel = retryDetourLevel;
          pointToPointDetourDowngraded = retryDowngraded;
          pointToPointDetourFallbackStage = retryDowngraded
            ? `downgraded_to_${retryDetourLevel}`
            : `retry_${retry + 1}_${retryCorridorFamily}`;
          pointToPointDeliveredTargetDistanceKm = softenedTarget;
          pointToPointVariantAttemptIndex = retry + 1;
        }
      }
    }

    if (
      !route &&
      planning_type === "Zufall" &&
      currentRouteType === "POINT_TO_POINT" &&
      body.destination_location &&
      pointToPointIsScenic &&
      hasPointToPointBudgetLeft(1600)
    ) {
      debugLog("P2P scenic safe fallback: trying single-corridor midpoint");
      const safeDetourLevel = detourLevel >= 3
        ? 2
        : detourLevel === 2
        ? 2
        : Math.max(detourLevel, 1);
      const safeTargetDistanceKm = Math.max(
        getPointToPointMinimumDistanceKm(
          pointToPointDirectDistanceKm,
          undefined,
          safeDetourLevel,
          true,
        ),
        pointToPointDirectDistanceKm * (safeDetourLevel >= 2 ? 1.34 : 1.14),
      );
      const directBearing = calculateBearing(
        startLocation,
        body.destination_location,
      );
      const fallbackFraction = 0.42 + seededUnit(randomSeed + 913) * 0.16;
      const midpoint = interpolateCoordinate(
        startLocation,
        body.destination_location,
        fallbackFraction,
      );
      const shortCorridor = pointToPointDirectDistanceKm < 18;
      const fallbackOffsetCapKm = safeDetourLevel >= 2
        ? shortCorridor ? 7.0 : 10.0
        : shortCorridor
        ? 4.0
        : 6.0;
      const fallbackOffsetMinKm = safeDetourLevel >= 2
        ? shortCorridor ? 3.0 : 4.5
        : shortCorridor
        ? 1.6
        : 2.2;
      const fallbackOffsetFactor = safeDetourLevel >= 2
        ? shortCorridor ? 0.32 : 0.40
        : shortCorridor
        ? 0.20
        : 0.28;
      const fallbackOffsetJitter = 0.86 + seededUnit(randomSeed + 947) * 0.28;
      const fallbackOffsetKm = Math.min(
        fallbackOffsetCapKm,
        Math.max(
          fallbackOffsetMinKm,
          pointToPointDirectDistanceKm * fallbackOffsetFactor *
            fallbackOffsetJitter,
        ),
      );
      const primarySide = offsetSide === -1 || offsetSide === 1
        ? offsetSide
        : seededUnit(randomSeed + 971) >= 0.5
        ? 1
        : -1;
      for (const side of [primarySide, -primarySide]) {
        if (!hasPointToPointBudgetLeft(900)) break;
        const safeWaypoint = calculateDestination(
          midpoint,
          fallbackOffsetKm,
          directBearing + side * 90,
        );
        const safeWaypoints = [
          startLocation,
          safeWaypoint,
          body.destination_location,
        ];
        const safeRadiuses = "unlimited;12000;unlimited";
        route = await getMapboxRoute(
          safeWaypoints,
          mapboxProfile,
          excludeParams,
          safeRadiuses,
          MAPBOX_ACCESS_TOKEN,
          {
            continueStraight: requestContinueStraight,
            maxAttempts: 1,
            timeoutMs: pointToPointTimeoutMs(7000),
          },
        );
        const relaxedSafeFallbackExcludes = relaxStreetExcludes(
          excludeParams,
          avoidHighways,
        );
        if (!route && relaxedSafeFallbackExcludes !== excludeParams) {
          route = await getMapboxRoute(
            safeWaypoints,
            mapboxProfile,
            relaxedSafeFallbackExcludes,
            safeRadiuses,
            MAPBOX_ACCESS_TOKEN,
            {
              continueStraight: requestContinueStraight,
              maxAttempts: 1,
              timeoutMs: pointToPointTimeoutMs(6200),
            },
          );
        }
        if (!route) continue;
        const fallbackQuality = evaluateRouteQuality(route, currentRouteType);
        if (
          fallbackQuality.passed &&
          isPointToPointDetourAcceptable(
            route,
            pointToPointDirectDistanceKm,
            safeTargetDistanceKm,
            safeDetourLevel,
            true,
          )
        ) {
          finalWaypoints = safeWaypoints;
          radiusesParams = safeRadiuses;
          pointToPointDeliveredDetourLevel = safeDetourLevel;
          pointToPointDetourDowngraded = safeDetourLevel < detourLevel;
          pointToPointDetourFallbackStage = pointToPointDetourDowngraded
            ? `safe_downgraded_to_${safeDetourLevel}`
            : "safe_corridor";
          pointToPointDeliveredTargetDistanceKm = safeTargetDistanceKm;
          break;
        }
        route = null;
      }
    }

    if (
      !route &&
      planning_type === "Zufall" &&
      currentRouteType === "POINT_TO_POINT" &&
      body.destination_location &&
      !pointToPointIsScenic
    ) {
      debugLog(
        pointToPointIsScenic
          ? "P2P scenic fallback exhausted: using direct A->B route"
          : "P2P direct fallback: using direct A->B route",
      );
      const fallbackWaypoints = [startLocation, body.destination_location];
      const fallbackRadiuses = "unlimited;unlimited";
      route = await getMapboxRoute(
        fallbackWaypoints,
        mapboxProfile,
        applyAvoidHighwaysExcludes(excludeParams, avoidHighways),
        fallbackRadiuses,
        MAPBOX_ACCESS_TOKEN,
        {
          continueStraight: requestContinueStraight,
          maxAttempts: 1,
          timeoutMs: pointToPointTimeoutMs(7500),
        },
      );
      if (route) {
        finalWaypoints = fallbackWaypoints;
        radiusesParams = fallbackRadiuses;
      }
    }

    if (!route) {
      const noRouteMessage = useRoundTripSearch
        ? "No route found with current constraints after exhausting round-trip search."
        : "No route found with current constraints.";
      requestDebugMeta = buildNoRouteSearchMeta(roundTripSearch, undefined, {
        avoidHighways,
        excludeParams,
        movingStartMeta,
      });
      if (
        useRoundTripSearch &&
        currentRouteType === "ROUND_TRIP" &&
        planning_type === "Zufall" &&
        roundTripSearch?.batchExhausted === true
      ) {
        const session = await createRoundTripSearchSession(
          body,
          roundTripSearch,
          requestDebugMeta,
        );
        if (session != null) {
          return jsonResponse(req, {
            route: null,
            code: "search_in_progress",
            message: "search_in_progress",
            meta: {
              ...(requestDebugMeta ?? {}),
              ...searchSessionMeta(session),
              background_learning_queued: true,
              progress_stage: "queued_worker_hydration",
            },
          }, 202);
        }
      }
      if (isWaypointPreferenceRequest && planning_type !== "Wegpunkte") {
        requestDebugMeta = buildPreferenceNotMatchableMeta(
          requestDebugMeta,
          "no_usable_route_for_preferences",
        );
        throw new Error(
          `${noRouteMessage} preference_areas_not_matchable.`,
        );
      }
      if (planning_type === "Wegpunkte") {
        requestDebugMeta = {
          response_code: "waypoint_route_not_possible",
          waypoint_source: waypointSource,
          requested_close_loop: body.close_loop !== false,
          normalized_user_waypoint_count: normalizedUserWaypointsForMeta.length,
          waypoint_layout_score: waypointLayoutScore,
        };
        throw new Error(
          "waypoint_route_not_possible: Mapbox could not route the supplied waypoint loop.",
        );
      }
      throw new Error(noRouteMessage);
    }

    if (
      useRoundTripSearch &&
      currentRouteType === "ROUND_TRIP" &&
      planning_type === "Zufall" &&
      (effectiveTargetDistanceKm ?? targetDistance ?? 0) >= 70 &&
      roundTripSearch != null &&
      (
        roundTripSearch.bestCandidatePayload != null ||
        (roundTripSearch.candidateQueuePayload?.length ?? 0) > 0
      )
    ) {
      requestDebugMeta = buildNoRouteSearchMeta(roundTripSearch, undefined, {
        avoidHighways,
        excludeParams,
        movingStartMeta,
      });
      const session = await createRoundTripSearchSession(
        body,
        { ...roundTripSearch, batchExhausted: true },
        requestDebugMeta,
      );
      if (session != null) {
        return jsonResponse(req, {
          route: null,
          code: "search_in_progress",
          message: "search_in_progress",
          meta: {
            ...(requestDebugMeta ?? {}),
            ...searchSessionMeta(session),
            background_learning_queued: true,
            progress_stage: "queued_worker_hydration",
            long_roundtrip_hydration_deferred: true,
          },
        }, 202);
      }
    }

    // Mapbox returns distance in meters -> convert to kilometers for app output.
    let actualDistanceKm = (route.distance as number) / 1000;
    const skipPostSearchScaling = currentRouteType === "ROUND_TRIP" &&
      roundTripSearch?.terminalShortCircuit === true;

    // --- 4. Distance Band Retry & Scaling ---
    // Accept clean roundtrips within ±15%; only scale clear distance misses.
    if (
      planning_type === "Zufall" &&
      currentRouteType === "ROUND_TRIP" &&
      distanceConfig &&
      !skipPostSearchScaling &&
      !avoidHighways
    ) {
      const scalingTargetKm = effectiveTargetDistanceKm ?? targetDistance!;
      const distanceBandMinKm = scalingTargetKm * 0.85;
      const distanceBandMaxKm = scalingTargetKm * 1.15;
      let bestScaledRoute = route;
      let bestScaledWaypoints = finalWaypoints;
      let bestScaledDistanceKm = actualDistanceKm;
      let attempts = 0;
      const maxAttempts = avoidHighways ? 2 : 3;
      while (
        attempts < maxAttempts &&
        Date.now() - requestStartedAt < 22000 &&
        (actualDistanceKm > distanceBandMaxKm ||
          actualDistanceKm < distanceBandMinKm)
      ) {
        const ratio = (effectiveTargetDistanceKm ?? targetDistance!) /
          actualDistanceKm;
        // Aggressiver korrigieren bei großem Fehler, sanfter bei Annäherung
        // > 2x oder < 0.5x → 85% Korrektur (fast direkt)
        // 1.3x-2x → 70% Korrektur
        // < 1.3x → 50% Korrektur (Feintuning, verhindert Oszillation)
        const errorMagnitude = Math.abs(ratio - 1);
        const correctionStrength = errorMagnitude > 1.0
          ? 0.85
          : errorMagnitude > 0.3
          ? 0.70
          : 0.50;
        const scaleFactor = 1 + (ratio - 1) * correctionStrength;

        debugLog(
          `Scaling attempt ${attempts + 1}: ${
            actualDistanceKm.toFixed(1)
          }km → target ${(effectiveTargetDistanceKm ??
            targetDistance)}km, ratio=${ratio.toFixed(2)}, scale=${
            scaleFactor.toFixed(3)
          }`,
        );

        // Alle Zwischenpunkte skalieren (nicht Start/Ende)
        const scaledWaypoints = finalWaypoints.map((wp, i) => {
          if (i === 0 || i === finalWaypoints.length - 1) return wp;
          return scaleWaypoint(startLocation, wp, scaleFactor);
        });

        const newRadiuses = scaledWaypoints
          .map((_, i) =>
            (i === 0 || i === scaledWaypoints.length - 1)
              ? "unlimited"
              : `${Math.round(distanceConfig.waypointRadiusMeters * 0.9)}`
          )
          .join(";");

        let newRoute = await getMapboxRoute(
          scaledWaypoints,
          mapboxProfile,
          excludeParams,
          newRadiuses,
          MAPBOX_ACCESS_TOKEN,
          {
            continueStraight: requestContinueStraight,
            maxAttempts: 1,
            timeoutMs: 6500,
            retryDelayBaseMs: 180,
          },
        );

        const relaxedScalingExcludes = relaxStreetExcludes(
          excludeParams,
          avoidHighways,
        );
        if (!newRoute && relaxedScalingExcludes !== excludeParams) {
          newRoute = await getMapboxRoute(
            scaledWaypoints,
            mapboxProfile,
            relaxedScalingExcludes,
            newRadiuses,
            MAPBOX_ACCESS_TOKEN,
            {
              continueStraight: requestContinueStraight,
              maxAttempts: 1,
              timeoutMs: 5800,
              retryDelayBaseMs: 180,
            },
          );
        }

        if (!newRoute) {
          debugLog(
            `Scaling attempt ${attempts + 1}: No route found, stopping`,
          );
          break;
        }

        const scaledQuality = evaluateRouteQuality(newRoute, currentRouteType, {
          targetDistanceKm: effectiveTargetDistanceKm ?? targetDistance,
          distanceConfig,
          mode,
          avoidHighways,
        });
        const scaledCleanup = currentRouteType === "ROUND_TRIP"
          ? evaluateRouteCleanupGate(newRoute, currentRouteType, {
            targetDistanceKm: effectiveTargetDistanceKm ?? targetDistance,
            distanceConfig,
            mode,
            avoidHighways,
            startLocation,
          })
          : null;
        if (!scaledQuality.passed || scaledCleanup?.passed === false) {
          debugLog(
            `Scaling attempt ${attempts + 1}: Route rejected (${
              scaledCleanup?.passed === false
                ? scaledCleanup.reason
                : scaledQuality.reason
            })`,
          );
          break;
        }

        actualDistanceKm = (newRoute.distance as number) / 1000;
        const bestDeltaKm = Math.abs(bestScaledDistanceKm - scalingTargetKm);
        const candidateDeltaKm = Math.abs(actualDistanceKm - scalingTargetKm);
        const bestInPreferredBand = bestScaledDistanceKm >= distanceBandMinKm &&
          bestScaledDistanceKm <= distanceBandMaxKm;
        const candidateInPreferredBand =
          actualDistanceKm >= distanceBandMinKm &&
          actualDistanceKm <= distanceBandMaxKm;
        if (
          (candidateInPreferredBand && !bestInPreferredBand) ||
          candidateDeltaKm + 0.25 < bestDeltaKm
        ) {
          bestScaledRoute = newRoute;
          bestScaledWaypoints = scaledWaypoints;
          bestScaledDistanceKm = actualDistanceKm;
        }

        route = newRoute;
        finalWaypoints = scaledWaypoints;
        attempts += 1;
      }
      route = bestScaledRoute;
      finalWaypoints = bestScaledWaypoints;
      actualDistanceKm = bestScaledDistanceKm;
      debugLog(
        `Distance scaling done after ${attempts} attempts: ${
          actualDistanceKm.toFixed(1)
        } km (target: ${(effectiveTargetDistanceKm ??
          targetDistance)} km, band: ${distanceBandMinKm.toFixed(1)}-${
          distanceBandMaxKm.toFixed(1)
        } km)`,
      );
      const withinPreferredBand = actualDistanceKm >= distanceBandMinKm &&
        actualDistanceKm <= distanceBandMaxKm;
      const roundTripFallbackDistanceBounds = (() => {
        if (
          currentRouteType !== "ROUND_TRIP" ||
          roundTripSearch == null ||
          (
            roundTripSearch.safeFallbackUsed !== true &&
            roundTripSearch.hydrationFallbackUsed !== true
          )
        ) {
          return null;
        }
        const requestedKm = effectiveTargetDistanceKm ?? targetDistance ?? 0;
        if (requestedKm <= 60) return { minKm: 40, maxKm: 65 };
        if (requestedKm <= 85) return { minKm: 62, maxKm: 90 };
        if (requestedKm <= 115) return { minKm: 85, maxKm: 118 };
        return null;
      })();
      const withinSafeFallbackBand = roundTripFallbackDistanceBounds != null &&
        actualDistanceKm >= roundTripFallbackDistanceBounds.minKm &&
        actualDistanceKm <= roundTripFallbackDistanceBounds.maxKm;
      if (!withinPreferredBand && !withinSafeFallbackBand) {
        requestDebugMeta = buildNoRouteSearchMeta(
          roundTripSearch,
          `distance=${actualDistanceKm.toFixed(1)}km`,
          { avoidHighways, excludeParams, movingStartMeta },
        );
        if (isWaypointPreferenceRequest) {
          requestDebugMeta = buildPreferenceNotMatchableMeta(
            requestDebugMeta,
            "route_outside_distance_band",
          );
        }
        throw new Error(
          `No route found with current constraints after exhausting round-trip search. Final distance ${
            actualDistanceKm.toFixed(1)
          }km is outside acceptable band ${distanceBandMinKm.toFixed(1)}-${
            distanceBandMaxKm.toFixed(1)
          }km.`,
        );
      }
    }

    // ── Quality gate: Route muss echte Straßengeometrie haben ──
    const roundTripSafeFallbackUsed = currentRouteType === "ROUND_TRIP" &&
      planning_type !== "Wegpunkte" &&
      roundTripSearch?.safeFallbackUsed === true &&
      roundTripSearch.quality?.safeFallbackUsed === true;
    const roundTripPreHydrationFallbackUsed = currentRouteType ===
        "ROUND_TRIP" &&
      planning_type !== "Wegpunkte" &&
      roundTripSearch?.hydrationFallbackUsed === true &&
      roundTripSearch.finalGeometrySource === "pre_hydration_fallback" &&
      roundTripSearch.quality != null &&
      roundTripSearch.quality.tier !== "rejected";
    const isSafeFallbackFinalReject = (reason: string): boolean => {
      const normalized = reason.toLowerCase();
      const shape = roundTripSearch?.quality?.shapeMetrics;
      const cleanPreHydrationHairpin =
        roundTripPreHydrationFallbackUsed &&
        shape != null &&
        shape.geometricUTurnCount <= (mode === "Sport Mode" ? 6 : 4) &&
        shape.cleanupUTurnCount <= (mode === "Sport Mode" ? 6 : 4) &&
        shape.loopnessScore >= (mode === "Sport Mode" ? 58 : 52) &&
        shape.spurScore <= (mode === "Sport Mode" ? 24 : 28) &&
        shape.outAndBackScore <= (mode === "Sport Mode" ? 22 : 26) &&
        shape.deadEndArmScore <= (mode === "Sport Mode" ? 22 : 26) &&
        shape.centerReentryCount <= 2 &&
        shape.repeatedStartAreaPercent <= 24 &&
        shape.centralReturnPercent <= 20 &&
        shape.cleanupDistanceRetentionRatio >= 0.82 &&
        (roundTripSearch?.quality?.overlapPercent ?? 0) <= 30;
      const safeLocalHairpin =
        roundTripSearch?.quality?.safeFallbackUsed === true &&
        shape != null &&
        shape.geometricUTurnCount <= 3 &&
        shape.cleanupUTurnCount <= 3 &&
        shape.loopnessScore >= 58 &&
        shape.spurScore <= 12 &&
        shape.outAndBackScore <= 16 &&
        shape.deadEndArmScore <= 12 &&
        shape.centerReentryCount <= 1 &&
        shape.cleanupDistanceRetentionRatio >= 0.92 &&
        (roundTripSearch.quality.overlapPercent ?? 0) <= 22;
      if (normalized === "cleanup_u_turn" && safeLocalHairpin) {
        return true;
      }
      if (
        (normalized === "u_turn" ||
          normalized.startsWith("u_turn_geometry=") ||
          normalized === "cleanup_u_turn") &&
        cleanPreHydrationHairpin
      ) {
        return true;
      }
      if (normalized.startsWith("cleanup_u_turn_geometry=")) {
        const cleanupUTurnCount = Number(
          normalized.replace("cleanup_u_turn_geometry=", ""),
        );
        const boundedCleanupHairpin =
          (safeLocalHairpin || cleanPreHydrationHairpin) &&
          Number.isFinite(cleanupUTurnCount) &&
          cleanupUTurnCount <= (cleanPreHydrationHairpin ? 6 : 3);
        if (boundedCleanupHairpin) return true;
      }
      if (
        normalized.includes("u_turn") ||
        normalized.includes("dead_end") ||
        normalized.includes("route_stub") ||
        normalized.includes("out_and_back") ||
        normalized.startsWith("hooks=") ||
        normalized.startsWith("center_return=")
      ) {
        return false;
      }
      return normalized.startsWith("short_sport_distance=") ||
        normalized.startsWith("short_sport_shape=") ||
        normalized.startsWith("short_sport_overlap=") ||
        normalized.startsWith("distance=") ||
        normalized.startsWith("cleanup_distance=") ||
        normalized.startsWith("cleanup_short_sport_distance=") ||
        normalized.startsWith("cleanup_short_sport_shape=") ||
        normalized.startsWith("cleanup_short_sport_overlap=");
    };
    const roundTripCompatibleNoHighwayResult = currentRouteType ===
        "ROUND_TRIP" &&
      planning_type !== "Wegpunkte" &&
      (roundTripSearch?.searchStageSuccess ?? "").startsWith(
        "compatible_no_highway",
      );
    const finalQualityAvoidHighways = avoidHighways ||
      roundTripCompatibleNoHighwayResult ||
      highwayAllowedNoHighwayFallbackUsed;
    let finalQuality = evaluateRouteQuality(route, currentRouteType, {
      targetDistanceKm: currentRouteType === "ROUND_TRIP"
        ? planning_type === "Wegpunkte"
          ? undefined
          : (effectiveTargetDistanceKm ?? targetDistance)
        : currentRouteType === "POINT_TO_POINT"
        ? pointToPointDeliveredTargetDistanceKm ??
          pointToPointEffectiveTargetDistanceKm
        : undefined,
      distanceConfig: currentRouteType === "ROUND_TRIP"
        ? planning_type === "Wegpunkte"
          ? undefined
          : distanceConfig ?? undefined
        : undefined,
      mode,
      avoidHighways: finalQualityAvoidHighways,
      requiredStops: planning_type === "Wegpunkte",
      requiredStopCoordinates: planning_type === "Wegpunkte"
        ? normalizedUserWaypointsForMeta
        : undefined,
    });
    if (
      roundTripSafeFallbackUsed &&
      !roundTripPreHydrationFallbackUsed &&
      !finalQuality.passed &&
      isSafeFallbackFinalReject(finalQuality.reason) &&
      roundTripSearch?.quality != null
    ) {
      finalQuality = roundTripSearch.quality;
    }
    if (
      roundTripPreHydrationFallbackUsed &&
      !finalQuality.passed &&
      isSafeFallbackFinalReject(finalQuality.reason) &&
      roundTripSearch?.quality != null
    ) {
      finalQuality = roundTripSearch.quality;
    }
    const finalCleanup = currentRouteType === "ROUND_TRIP" &&
        planning_type !== "Wegpunkte"
      ? evaluateRouteCleanupGate(route, currentRouteType, {
        targetDistanceKm: effectiveTargetDistanceKm ?? targetDistance,
        distanceConfig: distanceConfig ?? undefined,
        mode,
        avoidHighways: finalQualityAvoidHighways,
        startLocation,
      })
      : null;
    if (currentRouteType === "POINT_TO_POINT" && body.destination_location) {
      const rawCoordinates = route?.geometry?.coordinates;
      const lastCoordinate = Array.isArray(rawCoordinates) &&
          rawCoordinates.length > 0
        ? rawCoordinates[rawCoordinates.length - 1]
        : null;
      if (Array.isArray(lastCoordinate) && lastCoordinate.length >= 2) {
        pointToPointDestinationDistanceMeters = calculateDistance(
          { longitude: lastCoordinate[0], latitude: lastCoordinate[1] },
          body.destination_location,
        ) * 1000;
      }
      if (
        pointToPointDestinationDistanceMeters == null ||
        pointToPointDestinationDistanceMeters > 750
      ) {
        requestDebugMeta = {
          point_to_point: {
            destination_snap_distance_m: pointToPointDestinationDistanceMeters,
            destination_reached: false,
            direct_distance_km: pointToPointDirectDistanceKm,
            detour_level: detourLevel,
          },
        };
        throw new Error(
          `POINT_TO_POINT destination not reached (snap ${
            pointToPointDestinationDistanceMeters?.toFixed(0) ?? "unknown"
          }m).`,
        );
      }
    }
    if (!finalQuality.passed) {
      requestDebugMeta = buildNoRouteSearchMeta(
        roundTripSearch,
        finalQuality.reason,
        { avoidHighways, excludeParams, movingStartMeta },
      );
      if (isWaypointPreferenceRequest && planning_type !== "Wegpunkte") {
        requestDebugMeta = buildPreferenceNotMatchableMeta(
          requestDebugMeta,
          finalQuality.reason,
        );
      }
      if (planning_type === "Wegpunkte") {
        requestDebugMeta = {
          ...(requestDebugMeta ?? {}),
          response_code: "waypoint_quality_too_low",
          route_quality_too_low: true,
          waypoint_source: waypointSource,
          waypoint_mode: waypointMode ?? null,
          waypoint_route_mode: "required_stops",
          waypoint_order_requested: waypointOrder,
          waypoint_order_used: waypointOrderDelivered,
          normalized_user_waypoint_count: normalizedUserWaypointsForMeta.length,
          required_waypoint_count: normalizedUserWaypointsForMeta.length,
          waypoint_layout_score: waypointLayoutScore,
          waypoint_route_quality: finalQuality.tier,
        };
      }
      debugError(`Route quality too low: ${finalQuality.reason}`);
      throw new Error(
        planning_type === "Wegpunkte"
          ? `waypoint_quality_too_low: ${finalQuality.reason}`
          : `Route-Qualität zu niedrig (${finalQuality.reason}). Bitte erneut versuchen.`,
      );
    }
    if (
      finalCleanup?.passed === false &&
      !(
        (
          roundTripSafeFallbackUsed &&
          !roundTripPreHydrationFallbackUsed &&
          isSafeFallbackFinalReject(finalCleanup.reason)
        ) ||
        (
          roundTripPreHydrationFallbackUsed &&
          isSafeFallbackFinalReject(finalCleanup.reason)
        )
      )
    ) {
      requestDebugMeta = buildNoRouteSearchMeta(
        roundTripSearch,
        finalCleanup.reason,
        { avoidHighways, excludeParams, movingStartMeta },
      );
      if (planning_type === "Wegpunkte") {
        requestDebugMeta = {
          ...(requestDebugMeta ?? {}),
          response_code: "waypoint_quality_too_low",
          route_quality_too_low: true,
          waypoint_source: waypointSource,
          waypoint_mode: waypointMode ?? null,
          waypoint_route_mode: "required_stops",
          waypoint_order_requested: waypointOrder,
          waypoint_order_used: waypointOrderDelivered,
          normalized_user_waypoint_count: normalizedUserWaypointsForMeta.length,
          required_waypoint_count: normalizedUserWaypointsForMeta.length,
          waypoint_layout_score: waypointLayoutScore,
          waypoint_route_quality: finalQuality.tier,
        };
      }
      debugError(`Route cleanup too low: ${finalCleanup.reason}`);
      throw new Error(
        planning_type === "Wegpunkte"
          ? `waypoint_quality_too_low: ${finalCleanup.reason}`
          : `Route-Qualität zu niedrig (${finalCleanup.reason}). Bitte erneut versuchen.`,
      );
    }

    // Always use the ACTUAL Mapbox distance — never clamp.
    const finalDistanceKm = actualDistanceKm;

    // Route wird NICHT in der Edge Function gespeichert.
    // Die App speichert via SavedRoutesService.saveRoute() MIT user_id.
    // (Edge Function hat keinen Auth-Context → konnte vorher kein user_id setzen)

    // If the cleanup gate trimmed hooks/loops from the route, rebuild
    // the GeoJSON geometry with the cleaned coordinates so the client
    // sees the same cleaned polyline we evaluated. Without this the
    // client's own U-turn detector fires on raw Mapbox switchbacks
    // (alpine serpentines) and rejects the route even though the edge
    // already accepted it.
    const cleanedCoords = finalCleanup?.cleanedCoordinates;
    const applyCleanupToRoute = currentRouteType === "ROUND_TRIP" &&
      Array.isArray(cleanedCoords) && cleanedCoords.length >= 2 &&
      (finalCleanup?.removedPointPercent ?? 0) > 0.01;
    const cleanedGeometryCoords = applyCleanupToRoute
      ? cleanedCoords!.map((c) => [c.longitude, c.latitude])
      : null;
    const routeForFrontend = applyCleanupToRoute
      ? {
        ...route,
        distance: (finalCleanup?.cleanedDistanceKm ?? finalDistanceKm) * 1000,
        geometry: cleanedGeometryCoords
          ? {
            type: "LineString",
            coordinates: cleanedGeometryCoords,
          }
          : route.geometry,
        legs: route.legs ?? [],
      }
      : {
        ...route,
        distance: route.distance, // Mapbox-Originalwert in METERN beibehalten
        legs: route.legs ?? [],
      };
    const responseDistanceKm = applyCleanupToRoute
      ? (finalCleanup?.cleanedDistanceKm ?? finalDistanceKm)
      : finalDistanceKm;
    const displayGeometryStats = routeDisplayGeometryStats(
      routeForFrontend?.geometry?.coordinates,
    );
    const displayGeometryRejectReason =
      currentRouteType === "ROUND_TRIP" && planning_type !== "Wegpunkte"
        ? roundTripDisplayGeometryRejectReason(
          displayGeometryStats,
          responseDistanceKm,
          roundTripSearch?.finalOverview,
        )
        : null;
    if (displayGeometryRejectReason != null) {
      requestDebugMeta = buildNoRouteSearchMeta(
        roundTripSearch,
        displayGeometryRejectReason,
        { avoidHighways, excludeParams, movingStartMeta },
      );
      requestDebugMeta = {
        ...(requestDebugMeta ?? {}),
        response_code: "route_display_geometry_invalid",
        route_quality_too_low: true,
        geometry_source: roundTripSearch?.geometrySource ?? null,
        final_geometry_source: roundTripSearch?.finalGeometrySource ?? null,
        final_overview: roundTripSearch?.finalOverview ?? null,
        coordinate_count: displayGeometryStats.coordinateCount,
        max_segment_m: displayGeometryStats.maxSegmentMeters,
        average_segment_m: displayGeometryStats.averageSegmentMeters,
        display_geometry_reject_reason: displayGeometryRejectReason,
      };
      debugError(
        `Route display geometry invalid: ${displayGeometryRejectReason}`,
      );
      throw new Error(
        `Route-Qualität zu niedrig (${displayGeometryRejectReason}). Bitte erneut versuchen.`,
      );
    }
    const pointToPointActualDetourRatio =
      currentRouteType === "POINT_TO_POINT" && pointToPointDirectDistanceKm > 0
        ? responseDistanceKm / pointToPointDirectDistanceKm
        : null;
    let pointToPointMetaDeliveredDetourLevel = pointToPointDeliveredDetourLevel;
    let pointToPointMetaDowngraded = pointToPointDetourDowngraded;
    let pointToPointMetaFallbackStage = pointToPointDetourFallbackStage;
    if (
      currentRouteType === "POINT_TO_POINT" &&
      pointToPointIsScenic &&
      pointToPointActualDetourRatio != null
    ) {
      const ratioDeliveredLevel = pointToPointActualDetourRatio >= 1.88
        ? 3
        : pointToPointActualDetourRatio >= 1.48
        ? 2
        : pointToPointActualDetourRatio >= 1.18
        ? 1
        : 0;
      pointToPointMetaDeliveredDetourLevel = Math.min(
        pointToPointDeliveredDetourLevel,
        ratioDeliveredLevel,
      );
      if (pointToPointMetaDeliveredDetourLevel < detourLevel) {
        pointToPointMetaDowngraded = true;
        pointToPointMetaFallbackStage = pointToPointMetaFallbackStage == null
          ? `distance_band_downgraded_to_${pointToPointMetaDeliveredDetourLevel}`
          : `${pointToPointMetaFallbackStage}|distance_band_downgraded_to_${pointToPointMetaDeliveredDetourLevel}`;
      }
    }
    if (planning_type === "Wegpunkte" && currentRouteType === "ROUND_TRIP") {
      const reachThresholdMeters = 150;
      const routeCoordinates = routeForFrontend?.geometry?.coordinates;
      const reachDistances = waypointReachDistancesMeters(
        routeCoordinates,
        normalizedUserWaypointsForMeta,
      );
      const reachedCount = reachDistances.filter((distance) =>
        distance <= reachThresholdMeters
      ).length;
      waypointReachMeta = {
        userWaypointCount: normalizedUserWaypointsForMeta.length,
        reachedCount,
        allReached: reachedCount === normalizedUserWaypointsForMeta.length,
        reachDistancesMeters: reachDistances,
        thresholdMeters: reachThresholdMeters,
      };
      if (!waypointReachMeta.allReached) {
        requestDebugMeta = {
          response_code: "waypoint_not_reached",
          waypoint_source: waypointSource,
          waypoint_mode: waypointMode ?? null,
          waypoint_route_mode: "required_stops",
          waypoint_order_requested: waypointOrder,
          waypoint_order_used: waypointOrderDelivered,
          requested_close_loop: body.close_loop !== false,
          normalized_user_waypoint_count: normalizedUserWaypointsForMeta.length,
          required_waypoint_count: normalizedUserWaypointsForMeta.length,
          required_waypoints_reached: reachedCount,
          failed_waypoint_indices: reachDistances
            .map((distance, index) =>
              distance > reachThresholdMeters ? index : null
            )
            .filter((index) => index != null),
          waypoint_layout_score: waypointLayoutScore,
          waypoint_route: waypointReachMeta,
        };
        throw new Error(
          `waypoint_not_reached: reached ${reachedCount}/${normalizedUserWaypointsForMeta.length} required waypoints.`,
        );
      }
    }

    // Construct response
    return new Response(
      JSON.stringify({
        route: routeForFrontend,
        waypoints: finalWaypoints,
        meta: {
          distance_km: responseDistanceKm,
          duration_min: route.duration / 60,
          profile: mapboxProfile.replace("mapbox/", ""),
          mode: mode ?? null,
          style_profile: body.style_profile ?? null,
          route_type: currentRouteType,
          detour_level: currentRouteType === "POINT_TO_POINT"
            ? detourLevel
            : null,
          requested_detour_level: currentRouteType === "POINT_TO_POINT"
            ? detourLevel
            : null,
          delivered_detour_level: currentRouteType === "POINT_TO_POINT"
            ? pointToPointMetaDeliveredDetourLevel
            : null,
          detour_downgraded: currentRouteType === "POINT_TO_POINT"
            ? pointToPointMetaDowngraded
            : null,
          detour_fallback_stage: currentRouteType === "POINT_TO_POINT"
            ? pointToPointMetaFallbackStage
            : null,
          detour_ratio: currentRouteType === "POINT_TO_POINT" &&
              pointToPointDirectDistanceKm > 0
            ? pointToPointActualDetourRatio
            : null,
          direct_distance_km: currentRouteType === "POINT_TO_POINT"
            ? pointToPointDirectDistanceKm
            : null,
          direct_duration_min: currentRouteType === "POINT_TO_POINT"
            ? pointToPointDirectDurationMin
            : null,
          detour_target_distance_km: currentRouteType === "POINT_TO_POINT"
            ? pointToPointDeliveredTargetDistanceKm ??
              pointToPointEffectiveTargetDistanceKm ?? null
            : null,
          detour_min_distance_km:
            currentRouteType === "POINT_TO_POINT" && pointToPointIsScenic
              ? getPointToPointMinimumDistanceKm(
                pointToPointDirectDistanceKm,
                pointToPointDeliveredTargetDistanceKm ??
                  pointToPointEffectiveTargetDistanceKm,
                pointToPointMetaDeliveredDetourLevel,
                body.simplify_waypoints === true,
              )
              : null,
          detour_max_distance_km:
            currentRouteType === "POINT_TO_POINT" && pointToPointIsScenic
              ? getPointToPointMaximumDistanceKm(
                pointToPointDirectDistanceKm,
                pointToPointDeliveredTargetDistanceKm ??
                  pointToPointEffectiveTargetDistanceKm,
                pointToPointMetaDeliveredDetourLevel,
                body.simplify_waypoints === true,
              )
              : null,
          target_detour_ratio_min:
            currentRouteType === "POINT_TO_POINT" && pointToPointIsScenic
              ? pointToPointMetaDeliveredDetourLevel >= 3
                ? 1.90
                : pointToPointMetaDeliveredDetourLevel === 2
                ? 1.50
                : pointToPointMetaDeliveredDetourLevel === 1
                ? 1.20
                : 1.00
              : null,
          target_detour_ratio_max:
            currentRouteType === "POINT_TO_POINT" && pointToPointIsScenic
              ? pointToPointMetaDeliveredDetourLevel >= 3
                ? 2.80
                : pointToPointMetaDeliveredDetourLevel === 2
                ? 1.90
                : pointToPointMetaDeliveredDetourLevel === 1
                ? 1.45
                : 1.12
              : null,
          actual_detour_ratio: currentRouteType === "POINT_TO_POINT"
            ? pointToPointActualDetourRatio
            : null,
          selected_corridor_family: currentRouteType === "POINT_TO_POINT"
            ? pointToPointSelectedCorridorFamily
            : null,
          rejected_corridor_families: currentRouteType === "POINT_TO_POINT"
            ? pointToPointRejectedCorridorFamilies
            : null,
          variant_attempt_index: currentRouteType === "POINT_TO_POINT"
            ? pointToPointVariantAttemptIndex
            : null,
          duplicateSkipped: currentRouteType === "POINT_TO_POINT"
            ? pointToPointDuplicateSkipped
            : null,
          excluded_fingerprint_count: currentRouteType === "POINT_TO_POINT" ||
              currentRouteType === "ROUND_TRIP"
            ? previousRouteFingerprints.length +
              (body.route_fingerprint_hint != null ? 1 : 0)
            : null,
          destination_snap_distance_m: currentRouteType === "POINT_TO_POINT"
            ? pointToPointDestinationDistanceMeters
            : null,
          destination_reached: currentRouteType === "POINT_TO_POINT"
            ? pointToPointDestinationDistanceMeters != null &&
              pointToPointDestinationDistanceMeters <= 750
            : null,
          waypoint_count: finalWaypoints.length,
          planning_type,
          waypoint_mode: waypointMode ?? null,
          waypoint_route_mode: planning_type === "Wegpunkte"
            ? "required_stops"
            : null,
          waypoint_order_requested: planning_type === "Wegpunkte"
            ? waypointOrder
            : null,
          waypoint_order_used: planning_type === "Wegpunkte"
            ? waypointOrderDelivered
            : null,
          auto_optimize_attempt_count: planning_type === "Wegpunkte"
            ? waypointAutoOptimizeAttemptCount
            : null,
          auto_optimize_selected_index: planning_type === "Wegpunkte"
            ? waypointAutoOptimizeSelectedIndex
            : null,
          user_waypoint_count: waypointReachMeta?.userWaypointCount ?? 0,
          waypoints_reached: waypointReachMeta?.allReached ?? null,
          waypoints_reached_count: waypointReachMeta?.reachedCount ?? null,
          waypoint_reach_distances_m: waypointReachMeta?.reachDistancesMeters ??
            null,
          waypoint_reach_threshold_m: waypointReachMeta?.thresholdMeters ??
            null,
          required_waypoint_count: planning_type === "Wegpunkte"
            ? normalizedUserWaypointsForMeta.length
            : null,
          required_waypoints_reached: waypointReachMeta?.reachedCount ?? null,
          required_stop_reach_distances_m:
            waypointReachMeta?.reachDistancesMeters ?? null,
          failed_waypoint_indices: waypointReachMeta == null
            ? null
            : waypointReachMeta.reachDistancesMeters
              .map((distance, index) =>
                distance > waypointReachMeta!.thresholdMeters ? index : null
              )
              .filter((index) => index != null),
          waypoint_source: waypointSource,
          requested_close_loop: body.close_loop !== false,
          close_loop: planning_type === "Wegpunkte" &&
            currentRouteType === "ROUND_TRIP",
          normalized_user_waypoint_count: normalizedUserWaypointsForMeta.length,
          waypoint_layout_score: waypointLayoutScore,
          waypoint_route_quality: planning_type === "Wegpunkte"
            ? finalQuality.tier
            : null,
          ...(planning_type === "Wegpunkte" && waypointRoutingMeta != null
            ? waypointRoutingMeta
            : {}),
          target_distance_km: targetDistance ?? null,
          route_distance_km: responseDistanceKm,
          original_planning_type: body.original_planning_type ?? null,
          effective_planning_type: body.effective_planning_type ?? null,
          generation_mode: body.generation_mode ?? null,
          preference_area_count: preferenceAreaCount,
          preference_applied: body.preference_applied === true,
          matched_preference_count:
            roundTripSearch?.preferenceMatch?.matchedPreferenceCount ?? null,
          preference_match_score:
            roundTripSearch?.preferenceMatch?.preferenceMatchScore ?? null,
          preference_area_distances_m:
            roundTripSearch?.preferenceMatch?.preferenceAreaDistancesMeters ??
              null,
          preference_ignored_reason:
            roundTripSearch?.preferenceMatch?.preferenceIgnoredReason ?? null,
          avoid_highways_requested: avoidHighways,
          effective_excludes: excludeParams,
          highway_allowed: !avoidHighways,
          motorway_policy: avoidHighways
            ? "exclude_motorway"
            : "allowed_not_required",
          highway_allowed_fallback_used: highwayAllowedNoHighwayFallbackUsed,
          selected_no_highway_compatible:
            roundTripCompatibleNoHighwayResult ||
            highwayAllowedNoHighwayFallbackUsed,
          ...(movingStartMeta ?? {}),
          safe_fallback_used: roundTripSearch?.safeFallbackUsed === true,
          safe_fallback_reason: roundTripSearch?.safeFallbackReason ?? null,
          temporary_candidate: roundTripSearch?.safeFallbackUsed === true,
          silent_via_used: roundTripSearch?.silentViaUsed === true,
          silent_via_waypoints: roundTripSearch?.silentViaWaypoints ?? null,
          shaping_point_count: roundTripSearch?.shapingPointCount ?? null,
          mapbox_leg_count: roundTripSearch?.mapboxLegCount ?? null,
          arrive_maneuver_count: roundTripSearch?.arriveManeuverCount ?? null,
          silent_via_fallback_used:
            roundTripSearch?.silentViaFallbackUsed === true,
          guidance_degraded: roundTripSearch?.guidanceDegraded === true,
          hydration_fallback_used:
            roundTripSearch?.hydrationFallbackUsed === true,
          final_geometry_source: roundTripSearch?.finalGeometrySource ?? null,
          geometry_source: roundTripSearch?.geometrySource ?? null,
          final_overview: roundTripSearch?.finalOverview ?? null,
          coordinate_count: displayGeometryStats.coordinateCount,
          max_segment_m: displayGeometryStats.maxSegmentMeters,
          average_segment_m: displayGeometryStats.averageSegmentMeters,
          display_geometry_reject_reason: displayGeometryRejectReason,
          post_hydration_reject_reason:
            roundTripSearch?.postHydrationRejectReason ?? null,
          pre_hydration_quality_tier:
            roundTripSearch?.preHydrationQualityTier ?? null,
          hydration_diagnostics: roundTripSearch?.hydrationDiagnostics ?? [],
          requested_style: roundTripSearch?.requestedStyle ?? mode ?? null,
          delivered_style: roundTripSearch?.deliveredStyle ?? mode ?? null,
          style_downgraded: roundTripSearch?.styleDowngraded === true,
          quality_tier: finalQuality.tier,
          quality_reason: finalQuality.reason,
          selected_style: mode ?? null,
          style_fit_score: finalQuality.styleFitScore ?? null,
          style_fit_reasons: finalQuality.styleFitReasons ?? [],
          style_metrics: finalQuality.styleMetrics ?? null,
          shape_metrics: finalQuality.shapeMetrics ?? null,
          curve_density_per_km: finalQuality.styleMetrics?.curveDensityPerKm ??
            null,
          curve_density_per_50km:
            finalQuality.styleMetrics?.curveDensityPer50Km ?? null,
          smoothness_score: finalQuality.styleMetrics?.smoothnessScore ?? null,
          zigzag_score: finalQuality.styleMetrics?.zigzagScore ?? null,
          sharp_turn_count: finalQuality.styleMetrics?.sharpTurnCount ?? null,
          loopness_score: finalQuality.shapeMetrics?.loopnessScore ?? null,
          spur_score: finalQuality.shapeMetrics?.spurScore ?? null,
          dead_end_arm_score: finalQuality.shapeMetrics?.deadEndArmScore ??
            null,
          out_and_back_score: finalQuality.shapeMetrics?.outAndBackScore ??
            null,
          overlap_score: finalQuality.shapeMetrics?.overlapScore ?? null,
          geometric_uturn_count:
            finalQuality.shapeMetrics?.geometricUTurnCount ?? null,
          ...(roundTripSearch != null
            ? buildNoRouteSearchMeta(roundTripSearch, undefined, {
              avoidHighways,
              excludeParams,
              movingStartMeta,
            })
            : {}),
        },
      }),
      {
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
      },
    );
  } catch (error: any) {
    const message = error?.message ??
      "Unbekannter Fehler in generate-cruise-route";
    const classification = classifyRoutingError(message);
    debugError(
      "Error in generate-cruise-route:",
      message,
      error?.stack ?? "",
    );
    const responseHeaders: Record<string, string> = {
      ...getCorsHeaders(req),
      "Content-Type": "application/json",
    };
    if (classification.retryAfterSec != null) {
      responseHeaders["Retry-After"] = String(classification.retryAfterSec);
    }
    return new Response(
      JSON.stringify({
        error: message,
        code: classification.code,
        retryable: classification.retryable,
        retry_after_sec: classification.retryAfterSec ?? null,
        meta: requestDebugMeta,
      }),
      {
        status: classification.status,
        headers: responseHeaders,
      },
    );
  }
});
