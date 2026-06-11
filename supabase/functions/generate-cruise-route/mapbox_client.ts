import type { Coordinate, MapboxRouteFetchResult } from "./routing_types.ts";

export interface MapboxOptimizationWaypoint {
  waypoint_index?: number;
  trips_index?: number;
  name?: string;
  location?: [number, number];
}

export interface MapboxOptimizationFetchResult {
  trip: any | null;
  waypoints?: MapboxOptimizationWaypoint[];
  outcome: "ok" | "no_route" | "http_error" | "network_error" | "timeout";
  statusCode?: number;
  details?: string;
}

const removedProviderReason =
  "external_routing_provider_removed_use_graphhopper_v2";

export function buildMapboxDirectionsRequestUrl(
  waypoints: Coordinate[],
  profile: string,
  exclude: string,
  radiuses: string,
  accessToken: string,
  options?: {
    alternatives?: boolean;
    steps?: boolean;
    overview?: "full" | "simplified";
    approaches?: string;
    bearings?: string;
    continueStraight?: boolean;
    avoidManeuverRadiusMeters?: number;
    routeLegWaypointIndexes?: number[];
  },
): string {
  void waypoints;
  void profile;
  void exclude;
  void radiuses;
  void accessToken;
  void options;
  return "";
}

export function getRetryKindFromMapboxFailure(
  failure: Pick<MapboxRouteFetchResult, "outcome" | "statusCode" | "details">,
): "retryable" | "terminal" {
  void failure;
  return "terminal";
}

export async function getMapboxRouteDetailed(
  waypoints: Coordinate[],
  profile: string,
  exclude: string,
  radiuses: string,
  accessToken: string,
  options?: {
    alternatives?: boolean;
    bearings?: string;
    approaches?: string;
    continueStraight?: boolean;
    maxAttempts?: number;
    timeoutMs?: number;
    retryDelayBaseMs?: number;
    includeGuidance?: boolean;
    steps?: boolean;
    overview?: "full" | "simplified";
    avoidManeuverRadiusMeters?: number;
    routeLegWaypointIndexes?: number[];
  },
): Promise<MapboxRouteFetchResult> {
  void waypoints;
  void profile;
  void exclude;
  void radiuses;
  void accessToken;
  void options;
  return {
    route: null,
    outcome: "no_route",
    details: removedProviderReason,
  };
}

export async function getMapboxRoute(
  waypoints: Coordinate[],
  profile: string,
  exclude: string,
  radiuses: string,
  accessToken: string,
  options?: {
    alternatives?: boolean;
    bearings?: string;
    approaches?: string;
    continueStraight?: boolean;
    maxAttempts?: number;
    timeoutMs?: number;
    retryDelayBaseMs?: number;
    includeGuidance?: boolean;
    steps?: boolean;
    overview?: "full" | "simplified";
    avoidManeuverRadiusMeters?: number;
    routeLegWaypointIndexes?: number[];
  },
): Promise<any | null> {
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
  void waypoints;
  void profile;
  void accessToken;
  void options;
  return {
    trip: null,
    waypoints: [],
    outcome: "no_route",
    details: removedProviderReason,
  };
}
