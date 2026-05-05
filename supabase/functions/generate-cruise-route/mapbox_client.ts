import type { Coordinate, MapboxRouteFetchResult } from "./routing_types.ts";
import { debugError, debugWarn } from "./routing_debug.ts";
import { wait } from "./routing_utils.ts";

const RETRYABLE_MAPBOX_STATUS_CODES = new Set([
  408,
  409,
  425,
  429,
  500,
  502,
  503,
  504,
]);
const MAX_MAPBOX_FETCH_ATTEMPTS = 3;
const MAPBOX_FETCH_TIMEOUT_MS = 15000;
const DEFAULT_MAPBOX_RATE_PER_MINUTE = 250;
const MAPBOX_ROUTE_CACHE_MAX_ENTRIES = 12;

interface MapboxTokenBucket {
  ratePerMinute: number;
  capacity: number;
  tokens: number;
  updatedAtMs: number;
}

const mapboxRouteCache = new Map<string, MapboxRouteFetchResult>();

function getConfiguredMapboxRatePerMinute(): number {
  try {
    const rawValue = Deno.env.get("MAPBOX_RATE_PER_MINUTE");
    const parsed = rawValue ? Number(rawValue) : DEFAULT_MAPBOX_RATE_PER_MINUTE;
    if (!Number.isFinite(parsed) || parsed <= 0) {
      return DEFAULT_MAPBOX_RATE_PER_MINUTE;
    }
    return Math.max(1, Math.floor(parsed));
  } catch {
    return DEFAULT_MAPBOX_RATE_PER_MINUTE;
  }
}

const mapboxTokenBucket: MapboxTokenBucket = (() => {
  const ratePerMinute = getConfiguredMapboxRatePerMinute();
  return {
    ratePerMinute,
    capacity: ratePerMinute,
    tokens: ratePerMinute,
    updatedAtMs: Date.now(),
  };
})();

function syncMapboxTokenBucketRate(): void {
  const ratePerMinute = getConfiguredMapboxRatePerMinute();
  if (ratePerMinute === mapboxTokenBucket.ratePerMinute) return;

  mapboxTokenBucket.ratePerMinute = ratePerMinute;
  mapboxTokenBucket.capacity = ratePerMinute;
  mapboxTokenBucket.tokens = Math.min(mapboxTokenBucket.tokens, ratePerMinute);
  mapboxTokenBucket.updatedAtMs = Date.now();
}

function refillMapboxTokenBucket(nowMs: number): void {
  const elapsedMs = Math.max(0, nowMs - mapboxTokenBucket.updatedAtMs);
  if (elapsedMs <= 0) return;

  const refillRatePerMs = mapboxTokenBucket.ratePerMinute / 60000;
  mapboxTokenBucket.tokens = Math.min(
    mapboxTokenBucket.capacity,
    mapboxTokenBucket.tokens + elapsedMs * refillRatePerMs,
  );
  mapboxTokenBucket.updatedAtMs = nowMs;
}

async function acquireMapboxFetchSlot(): Promise<void> {
  while (true) {
    syncMapboxTokenBucketRate();
    refillMapboxTokenBucket(Date.now());

    if (mapboxTokenBucket.tokens >= 1) {
      mapboxTokenBucket.tokens -= 1;
      return;
    }

    const refillRatePerMs = mapboxTokenBucket.ratePerMinute / 60000;
    const waitMs = Math.ceil((1 - mapboxTokenBucket.tokens) / refillRatePerMs);
    await wait(Math.max(1, waitMs));
  }
}

function getMapboxRouteCacheKey(
  coordinatesStr: string,
  profile: string,
  exclude: string,
  radiuses: string,
  continueStraight: boolean,
  alternatives: boolean,
  bearings: string,
  includeGuidance: boolean,
  overview: "full" | "simplified",
  avoidManeuverRadiusMeters: number | null,
): string {
  return [
    profile,
    coordinatesStr,
    exclude,
    radiuses,
    continueStraight ? "continue" : "allow_reverse",
    alternatives ? "alts" : "single",
    bearings,
    includeGuidance ? "guidance" : "geometry",
    overview,
    avoidManeuverRadiusMeters == null
      ? "avoid_maneuver_radius=none"
      : `avoid_maneuver_radius=${avoidManeuverRadiusMeters.toFixed(0)}`,
  ].join("|");
}

function cloneMapboxRouteFetchResult(
  result: MapboxRouteFetchResult,
): MapboxRouteFetchResult {
  return {
    ...result,
    route: result.route === null ? null : structuredClone(result.route),
    routes: result.routes == null ? undefined : structuredClone(result.routes),
  };
}

function getCachedMapboxRoute(
  cacheKey: string,
): MapboxRouteFetchResult | null {
  const cached = mapboxRouteCache.get(cacheKey);
  if (!cached) return null;

  mapboxRouteCache.delete(cacheKey);
  mapboxRouteCache.set(cacheKey, cached);
  return cloneMapboxRouteFetchResult(cached);
}

function cacheMapboxRoute(
  cacheKey: string,
  result: MapboxRouteFetchResult,
  options?: { alternatives?: boolean },
): void {
  if (result.outcome !== "ok" && result.outcome !== "no_route") return;
  // Alternative responses carry multiple full geometries, steps and
  // instructions. Random roundtrip candidates rarely repeat, so caching those
  // payloads costs memory without materially improving hit rate.
  if (result.outcome === "ok" && options?.alternatives === true) return;

  if (mapboxRouteCache.has(cacheKey)) {
    mapboxRouteCache.delete(cacheKey);
  }
  mapboxRouteCache.set(cacheKey, cloneMapboxRouteFetchResult(result));

  while (mapboxRouteCache.size > MAPBOX_ROUTE_CACHE_MAX_ENTRIES) {
    const oldestKey = mapboxRouteCache.keys().next().value;
    if (oldestKey === undefined) break;
    mapboxRouteCache.delete(oldestKey);
  }
}

export function getRetryKindFromMapboxFailure(
  failure: Pick<MapboxRouteFetchResult, "outcome" | "statusCode" | "details">,
): "rate_limit" | "timeout" | "other" {
  if (failure.outcome === "timeout") return "timeout";
  if (failure.statusCode === 429) return "rate_limit";
  const details = String(failure.details ?? "").toLowerCase();
  if (details.includes("too many requests") || details.includes("rate limit")) {
    return "rate_limit";
  }
  if (
    details.includes("timeout") || details.includes("timed out") ||
    details.includes("abort")
  ) {
    return "timeout";
  }
  return "other";
}

/**
 * Calls Mapbox Directions API.
 */
export async function getMapboxRouteDetailed(
  waypoints: Coordinate[],
  profile: string,
  exclude: string,
  radiuses: string,
  accessToken: string,
  options?: {
    continueStraight?: boolean;
    alternatives?: boolean;
    bearings?: string;
    maxAttempts?: number;
    timeoutMs?: number;
    retryDelayBaseMs?: number;
    includeGuidance?: boolean;
    overview?: "full" | "simplified";
    avoidManeuverRadiusMeters?: number;
  },
): Promise<MapboxRouteFetchResult> {
  // Format coordinates: "lon,lat;lon,lat;..."
  const coordinatesStr = waypoints
    .map((p) => `${p.longitude},${p.latitude}`)
    .join(";");

  // Base URL
  // We use geometries=geojson to get the path geometry
  const continueStraight = options?.continueStraight ?? true;
  const alternatives = options?.alternatives === true;
  const includeGuidance = options?.includeGuidance !== false;
  const bearings = options?.bearings?.trim() ?? "";
  const overview = options?.overview ??
    (includeGuidance ? "full" : "simplified");
  const avoidManeuverRadiusMeters =
    typeof options?.avoidManeuverRadiusMeters === "number" &&
      Number.isFinite(options.avoidManeuverRadiusMeters) &&
      options.avoidManeuverRadiusMeters > 0
      ? Math.round(options.avoidManeuverRadiusMeters)
      : null;
  let url =
    `https://api.mapbox.com/directions/v5/${profile}/${coordinatesStr}?access_token=${accessToken}&geometries=geojson&overview=${overview}&steps=${
      includeGuidance ? "true" : "false"
    }&language=de&continue_straight=${
      continueStraight ? "true" : "false"
    }&alternatives=${alternatives ? "true" : "false"}`;
  if (includeGuidance && overview === "full") {
    url +=
      "&voice_instructions=true&banner_instructions=true&annotations=maxspeed";
  } else if (includeGuidance) {
    url += "&voice_instructions=true&banner_instructions=true";
  }

  // Append optional parameters if they exist
  if (exclude && exclude.trim() !== "") {
    url += `&exclude=${exclude}`;
  }
  if (radiuses && radiuses.trim() !== "") {
    url += `&radiuses=${radiuses}`;
  }
  if (bearings !== "") {
    url += `&bearings=${bearings}`;
  }
  if (avoidManeuverRadiusMeters != null) {
    url += `&avoid_maneuver_radius=${avoidManeuverRadiusMeters}`;
  }

  const cacheKey = getMapboxRouteCacheKey(
    coordinatesStr,
    profile,
    exclude,
    radiuses,
    continueStraight,
    alternatives,
    bearings,
    includeGuidance,
    overview,
    avoidManeuverRadiusMeters,
  );
  const cachedResult = getCachedMapboxRoute(cacheKey);
  if (cachedResult) {
    return cachedResult;
  }

  const maxAttempts = Math.max(
    1,
    Math.min(4, options?.maxAttempts ?? MAX_MAPBOX_FETCH_ATTEMPTS),
  );
  const timeoutMs = Math.max(
    4000,
    Math.min(22000, options?.timeoutMs ?? MAPBOX_FETCH_TIMEOUT_MS),
  );
  const retryDelayBaseMs = Math.max(
    120,
    Math.min(800, options?.retryDelayBaseMs ?? 180),
  );

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    await acquireMapboxFetchSlot();
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetch(url, { signal: controller.signal });
      if (!res.ok) {
        const text = await res.text();
        const failure: MapboxRouteFetchResult = {
          route: null,
          outcome: "http_error",
          statusCode: res.status,
          details: text,
        };
        const retryable = RETRYABLE_MAPBOX_STATUS_CODES.has(res.status);
        if (retryable && attempt < maxAttempts) {
          debugWarn(
            `Mapbox API retryable error (${res.status}), retry ${
              attempt + 1
            }/${maxAttempts}`,
          );
          await wait(retryDelayBaseMs * attempt);
          continue;
        }
        debugError(
          `Mapbox API Error (${res.status}): ${text.slice(0, 240)}`,
        );
        return failure;
      }

      const data = await res.json();
      if (!data.routes || data.routes.length === 0) {
        const noRouteResult: MapboxRouteFetchResult = {
          route: null,
          outcome: "no_route",
          details: JSON.stringify(data).slice(0, 500),
        };
        cacheMapboxRoute(cacheKey, noRouteResult, { alternatives });
        return noRouteResult;
      }

      // Return the best route
      const successResult: MapboxRouteFetchResult = {
        route: data.routes[0],
        routes: data.routes,
        outcome: "ok",
      };
      cacheMapboxRoute(cacheKey, successResult, { alternatives });
      return successResult;
    } catch (error) {
      const details = error instanceof Error ? error.message : String(error);
      const isAbort =
        (error instanceof DOMException && error.name === "AbortError") ||
        String(details).toLowerCase().includes("abort");
      const failure: MapboxRouteFetchResult = {
        route: null,
        outcome: isAbort ? "timeout" : "network_error",
        details,
      };
      if (attempt < maxAttempts) {
        debugWarn(
          `Mapbox ${isAbort ? "timeout" : "network"} retry (${
            attempt + 1
          }/${maxAttempts}): ${details}`,
        );
        await wait(retryDelayBaseMs * attempt);
        continue;
      }
      debugError(`Mapbox fetch failed (${failure.outcome}): ${details}`);
      return failure;
    } finally {
      clearTimeout(timeoutId);
    }
  }

  return {
    route: null,
    outcome: "network_error",
    details: "Mapbox fetch retry budget exhausted",
  };
}

export async function getMapboxRoute(
  waypoints: Coordinate[],
  profile: string,
  exclude: string,
  radiuses: string,
  accessToken: string,
  options?: {
    continueStraight?: boolean;
    alternatives?: boolean;
    bearings?: string;
    maxAttempts?: number;
    timeoutMs?: number;
    retryDelayBaseMs?: number;
    includeGuidance?: boolean;
  },
) {
  const result = await getMapboxRouteDetailed(
    waypoints,
    profile,
    exclude,
    radiuses,
    accessToken,
    options,
  );
  return result.route;
}

export interface MapboxOptimizationWaypoint {
  waypoint_index?: number;
  trips_index?: number;
  name?: string;
  location?: [number, number];
}

export interface MapboxOptimizationFetchResult {
  trip: any | null;
  waypoints?: MapboxOptimizationWaypoint[];
  outcome:
    | "ok"
    | "no_route"
    | "http_error"
    | "network_error"
    | "timeout";
  statusCode?: number;
  details?: string;
}

/**
 * Calls Mapbox Optimization API v1 to get a visit order.
 *
 * We only use this for required-stop waypoint roundtrips. The optimized trip is
 * not shown directly; Directions API still builds the final full route and
 * guidance after the order is known.
 */
export async function getMapboxOptimizationDetailed(
  waypoints: Coordinate[],
  profile: string,
  accessToken: string,
  options?: {
    roundTrip?: boolean;
    source?: "first" | "any";
    radiuses?: string;
    approaches?: string;
    maxAttempts?: number;
    timeoutMs?: number;
    retryDelayBaseMs?: number;
  },
): Promise<MapboxOptimizationFetchResult> {
  const coordinatesStr = waypoints
    .map((p) => `${p.longitude},${p.latitude}`)
    .join(";");

  const roundTrip = options?.roundTrip !== false;
  const source = options?.source ?? "first";
  let url =
    `https://api.mapbox.com/optimized-trips/v1/${profile}/${coordinatesStr}?access_token=${accessToken}&roundtrip=${
      roundTrip ? "true" : "false"
    }&source=${source}&geometries=geojson&overview=simplified&steps=false`;

  if (options?.radiuses?.trim()) {
    url += `&radiuses=${options.radiuses}`;
  }
  if (options?.approaches?.trim()) {
    url += `&approaches=${options.approaches}`;
  }

  const maxAttempts = Math.max(
    1,
    Math.min(3, options?.maxAttempts ?? 2),
  );
  const timeoutMs = Math.max(
    3000,
    Math.min(16000, options?.timeoutMs ?? 9000),
  );
  const retryDelayBaseMs = Math.max(
    120,
    Math.min(800, options?.retryDelayBaseMs ?? 180),
  );

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    await acquireMapboxFetchSlot();
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetch(url, { signal: controller.signal });
      if (!res.ok) {
        const text = await res.text();
        const retryable = RETRYABLE_MAPBOX_STATUS_CODES.has(res.status);
        if (retryable && attempt < maxAttempts) {
          debugWarn(
            `Mapbox Optimization retryable error (${res.status}), retry ${
              attempt + 1
            }/${maxAttempts}`,
          );
          await wait(retryDelayBaseMs * attempt);
          continue;
        }
        debugError(
          `Mapbox Optimization API Error (${res.status}): ${
            text.slice(0, 240)
          }`,
        );
        return {
          trip: null,
          outcome: "http_error",
          statusCode: res.status,
          details: text,
        };
      }

      const data = await res.json();
      if (!data.trips || data.trips.length === 0) {
        return {
          trip: null,
          waypoints: Array.isArray(data.waypoints) ? data.waypoints : undefined,
          outcome: "no_route",
          details: JSON.stringify(data).slice(0, 500),
        };
      }

      return {
        trip: data.trips[0],
        waypoints: Array.isArray(data.waypoints) ? data.waypoints : undefined,
        outcome: "ok",
      };
    } catch (error) {
      const details = error instanceof Error ? error.message : String(error);
      const isAbort =
        (error instanceof DOMException && error.name === "AbortError") ||
        String(details).toLowerCase().includes("abort");
      if (attempt < maxAttempts) {
        debugWarn(
          `Mapbox Optimization ${isAbort ? "timeout" : "network"} retry (${
            attempt + 1
          }/${maxAttempts}): ${details}`,
        );
        await wait(retryDelayBaseMs * attempt);
        continue;
      }
      debugError(
        `Mapbox Optimization fetch failed (${
          isAbort ? "timeout" : "network_error"
        }): ${details}`,
      );
      return {
        trip: null,
        outcome: isAbort ? "timeout" : "network_error",
        details,
      };
    } finally {
      clearTimeout(timeoutId);
    }
  }

  return {
    trip: null,
    outcome: "network_error",
    details: "Mapbox Optimization retry budget exhausted",
  };
}
