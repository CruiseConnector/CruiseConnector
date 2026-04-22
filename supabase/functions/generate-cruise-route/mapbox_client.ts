import type { Coordinate, MapboxRouteFetchResult } from "./routing_types.ts";
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
    maxAttempts?: number;
    timeoutMs?: number;
    retryDelayBaseMs?: number;
  },
): Promise<MapboxRouteFetchResult> {
  // Format coordinates: "lon,lat;lon,lat;..."
  const coordinatesStr = waypoints
    .map((p) => `${p.longitude},${p.latitude}`)
    .join(";");

  // Base URL
  // We use geometries=geojson to get the path geometry
  const continueStraight = options?.continueStraight ?? true;
  let url =
    `https://api.mapbox.com/directions/v5/${profile}/${coordinatesStr}?access_token=${accessToken}&geometries=geojson&overview=full&steps=true&voice_instructions=true&banner_instructions=true&language=de&continue_straight=${
      continueStraight ? "true" : "false"
    }&annotations=maxspeed`;

  // Append optional parameters if they exist
  if (exclude && exclude.trim() !== "") {
    url += `&exclude=${exclude}`;
  }
  if (radiuses && radiuses.trim() !== "") {
    url += `&radiuses=${radiuses}`;
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
          console.warn(
            `Mapbox API retryable error (${res.status}), retry ${
              attempt + 1
            }/${maxAttempts}`,
          );
          await wait(retryDelayBaseMs * attempt);
          continue;
        }
        console.error(`Mapbox API Error (${res.status}): ${text}`);
        return failure;
      }

      const data = await res.json();
      if (!data.routes || data.routes.length === 0) {
        return {
          route: null,
          outcome: "no_route",
          details: JSON.stringify(data).slice(0, 500),
        };
      }

      // Return the best route
      return {
        route: data.routes[0],
        outcome: "ok",
      };
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
        console.warn(
          `Mapbox ${isAbort ? "timeout" : "network"} retry (${
            attempt + 1
          }/${maxAttempts}): ${details}`,
        );
        await wait(retryDelayBaseMs * attempt);
        continue;
      }
      console.error(`Mapbox fetch failed (${failure.outcome}): ${details}`);
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
    maxAttempts?: number;
    timeoutMs?: number;
    retryDelayBaseMs?: number;
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
