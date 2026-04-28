export function classifyRoutingError(message: string): {
  status: number;
  code:
    | "INVALID_REQUEST"
    | "too_few_waypoints"
    | "too_many_waypoints"
    | "waypoint_duplicate_or_too_close"
    | "waypoint_too_far"
    | "NO_ROUTE"
    | "UNAUTHORIZED"
    | "RATE_LIMIT"
    | "TIMEOUT"
    | "WORKER_LIMIT"
    | "INTERNAL_ERROR";
  retryable: boolean;
  retryAfterSec?: number;
} {
  const lower = message.toLowerCase();
  if (lower.includes("too_few_waypoints")) {
    return { status: 422, code: "too_few_waypoints", retryable: false };
  }
  if (lower.includes("too_many_waypoints")) {
    return { status: 422, code: "too_many_waypoints", retryable: false };
  }
  if (lower.includes("waypoint_duplicate_or_too_close")) {
    return {
      status: 422,
      code: "waypoint_duplicate_or_too_close",
      retryable: false,
    };
  }
  if (lower.includes("waypoint_too_far")) {
    return { status: 422, code: "waypoint_too_far", retryable: false };
  }
  if (
    lower.includes("waypoint_layout_unstable") ||
    lower.includes("waypoint_route_not_possible")
  ) {
    return { status: 422, code: "INVALID_REQUEST", retryable: false };
  }
  if (lower.includes("waypoint_quality_too_low")) {
    return { status: 404, code: "NO_ROUTE", retryable: false };
  }
  if (
    lower.includes("invalid") ||
    lower.includes("missing") ||
    lower.includes("out of bounds") ||
    lower.includes("required")
  ) {
    return { status: 422, code: "INVALID_REQUEST", retryable: false };
  }
  if (lower.includes("no route found") || lower.includes("keine route")) {
    return { status: 404, code: "NO_ROUTE", retryable: false };
  }
  if (
    lower.includes("unauthorized") || lower.includes("forbidden") ||
    lower.includes("jwt")
  ) {
    return { status: 401, code: "UNAUTHORIZED", retryable: false };
  }
  if (
    lower.includes("worker limit") ||
    lower.includes("cpu time limit") ||
    lower.includes("memory limit") ||
    lower.includes("wall clock") ||
    lower.includes("resource limit")
  ) {
    return {
      status: 503,
      code: "WORKER_LIMIT",
      retryable: true,
      retryAfterSec: 2,
    };
  }
  if (
    lower.includes("rate limit") || lower.includes("too many requests") ||
    lower.includes("mapbox_http_429")
  ) {
    return {
      status: 429,
      code: "RATE_LIMIT",
      retryable: true,
      retryAfterSec: 8,
    };
  }
  if (
    lower.includes("timeout") ||
    lower.includes("timed out") ||
    lower.includes("aborterror") ||
    lower.includes("mapbox_timeout")
  ) {
    return { status: 504, code: "TIMEOUT", retryable: true, retryAfterSec: 5 };
  }
  return { status: 500, code: "INTERNAL_ERROR", retryable: false };
}
