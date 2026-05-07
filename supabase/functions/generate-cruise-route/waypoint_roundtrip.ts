import type { Coordinate, RouteMode } from "./routing_types.ts";
import {
  calculateBearing,
  calculateDestination,
  calculateDistance,
  stableStringHash,
} from "./routing_utils.ts";
import {
  getMapboxOptimizationDetailed,
  getMapboxRouteDetailed,
} from "./mapbox_client.ts";
import { getRouteDistanceKm } from "./point_to_point.ts";
import { evaluateRouteQuality } from "./route_quality.ts";
import { debugLog } from "./routing_debug.ts";

export interface RequiredWaypointRoundTripResult {
  route: any | null;
  waypoints: Coordinate[];
  radiuses: string;
  requiredOrder: Coordinate[];
  deliveredOrder: number[] | null;
  rejectReason: string | null;
  meta: Record<string, unknown>;
}

export interface RequiredWaypointRoundTripOptions {
  startLocation: Coordinate;
  requiredWaypoints: Coordinate[];
  waypointOrder: "fixed" | "auto_optimize";
  targetDistanceKm?: number;
  mode?: RouteMode;
  avoidHighways: boolean;
  mapboxProfile: string;
  excludeParams: string;
  accessToken: string;
  randomSeed: number;
  variantHint?: string;
  fingerprintHint?: string;
  waypointOrigin?: "manual" | "auto_seed";
  waypointSeedAttempt?: number | null;
  maxSearchMs: number;
}

interface RequiredWaypointPlan {
  label: string;
  strategy: string;
  requiredOrder: Coordinate[];
  waypoints: Coordinate[];
  radiuses: string;
  continueStraight: boolean;
  alternatives: boolean;
  silentVia: boolean;
}

const REQUIRED_STOP_RADIUS_METERS = 1200;
const SHAPE_POINT_RADIUS_METERS = 5500;
const REACH_THRESHOLD_METERS = 1200;

function sameCoordinate(a: Coordinate, b: Coordinate): boolean {
  return (
    Math.abs(a.latitude - b.latitude) < 1e-9 &&
    Math.abs(a.longitude - b.longitude) < 1e-9
  );
}

function waypointOrderIndices(
  ordered: Coordinate[],
  original: Coordinate[],
): number[] {
  return ordered.map((point) => {
    const index = original.findIndex((candidate) =>
      sameCoordinate(candidate, point)
    );
    return index < 0 ? -1 : index;
  });
}

function dedupeOrders(orders: Coordinate[][]): Coordinate[][] {
  const seen = new Set<string>();
  const result: Coordinate[][] = [];
  for (const order of orders) {
    const key = order
      .map((point) =>
        `${point.latitude.toFixed(6)},${point.longitude.toFixed(6)}`
      )
      .join("|");
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(order);
  }
  return result;
}

function permuteWaypoints(waypoints: Coordinate[]): Coordinate[][] {
  if (waypoints.length <= 1) return [waypoints];
  const result: Coordinate[][] = [];
  const used = new Array<boolean>(waypoints.length).fill(false);
  const current: Coordinate[] = [];
  const walk = () => {
    if (current.length === waypoints.length) {
      result.push([...current]);
      return;
    }
    for (let i = 0; i < waypoints.length; i++) {
      if (used[i]) continue;
      used[i] = true;
      current.push(waypoints[i]);
      walk();
      current.pop();
      used[i] = false;
    }
  };
  walk();
  return result.slice(0, 6);
}

function radiusesForPlan(
  waypoints: Coordinate[],
  requiredStops: Coordinate[],
): string {
  return waypoints
    .map((point, index) => {
      if (index === 0 || index === waypoints.length - 1) return "unlimited";
      const isRequired = requiredStops.some((stop) =>
        sameCoordinate(stop, point)
      );
      return isRequired
        ? String(REQUIRED_STOP_RADIUS_METERS)
        : String(SHAPE_POINT_RADIUS_METERS);
    })
    .join(";");
}

function waypointReachDistancesMeters(
  coordinates: unknown,
  waypoints: Coordinate[],
): number[] {
  if (!Array.isArray(coordinates)) {
    return waypoints.map(() => Number.POSITIVE_INFINITY);
  }

  const routePoints = coordinates
    .map((raw) => {
      if (!Array.isArray(raw) || raw.length < 2) return null;
      const longitude = Number(raw[0]);
      const latitude = Number(raw[1]);
      if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
        return null;
      }
      return { latitude, longitude };
    })
    .filter((point): point is Coordinate => point != null);

  if (routePoints.length === 0) {
    return waypoints.map(() => Number.POSITIVE_INFINITY);
  }

  return waypoints.map((waypoint) => {
    let bestMeters = Number.POSITIVE_INFINITY;
    for (const point of routePoints) {
      const meters = calculateDistance(point, waypoint) * 1000;
      if (meters < bestMeters) bestMeters = meters;
    }
    for (let i = 0; i < routePoints.length - 1; i++) {
      const meters = distancePointToSegmentMeters(
        waypoint,
        routePoints[i],
        routePoints[i + 1],
      );
      if (meters < bestMeters) bestMeters = meters;
    }
    return Math.round(bestMeters);
  });
}

function distancePointToSegmentMeters(
  point: Coordinate,
  start: Coordinate,
  end: Coordinate,
): number {
  const latScale = Math.cos((point.latitude * Math.PI) / 180);
  const metersPerDegreeLat = 111_320;
  const metersPerDegreeLng = 111_320 * Math.max(0.01, latScale);
  const sx = (start.longitude - point.longitude) * metersPerDegreeLng;
  const sy = (start.latitude - point.latitude) * metersPerDegreeLat;
  const ex = (end.longitude - point.longitude) * metersPerDegreeLng;
  const ey = (end.latitude - point.latitude) * metersPerDegreeLat;
  const dx = ex - sx;
  const dy = ey - sy;
  const lengthSq = dx * dx + dy * dy;
  if (lengthSq <= 1e-6) {
    return Math.sqrt(sx * sx + sy * sy);
  }
  const t = Math.max(0, Math.min(1, -(sx * dx + sy * dy) / lengthSq));
  const closestX = sx + dx * t;
  const closestY = sy + dy * t;
  return Math.sqrt(closestX * closestX + closestY * closestY);
}

function optimizationOrderFromWaypoints(
  optimizationWaypoints: unknown,
  requiredWaypoints: Coordinate[],
): Coordinate[] | null {
  if (!Array.isArray(optimizationWaypoints)) return null;

  const entries = optimizationWaypoints
    .map((waypoint, inputIndex) => {
      if (inputIndex === 0) return null;
      const rawWaypoint = waypoint as { waypoint_index?: unknown };
      const orderIndex = Number(rawWaypoint.waypoint_index);
      if (!Number.isFinite(orderIndex)) return null;
      const requiredIndex = inputIndex - 1;
      const point = requiredWaypoints[requiredIndex];
      if (!point) return null;
      return { orderIndex, requiredIndex, point };
    })
    .filter((entry): entry is {
      orderIndex: number;
      requiredIndex: number;
      point: Coordinate;
    } => entry != null)
    .sort((a, b) => a.orderIndex - b.orderIndex);

  if (entries.length !== requiredWaypoints.length) return null;
  return entries.map((entry) => entry.point);
}

async function buildOptimizedOrder(
  options: RequiredWaypointRoundTripOptions,
): Promise<{
  order: Coordinate[] | null;
  status: string;
  details?: string;
}> {
  if (options.waypointOrder !== "auto_optimize") {
    return { order: null, status: "skipped_fixed_order" };
  }

  const optimizationRadiuses = radiusesForPlan(
    [options.startLocation, ...options.requiredWaypoints],
    options.requiredWaypoints,
  );
  const optimization = await getMapboxOptimizationDetailed(
    [options.startLocation, ...options.requiredWaypoints],
    options.mapboxProfile,
    options.accessToken,
    {
      roundTrip: true,
      source: "first",
      radiuses: optimizationRadiuses,
      maxAttempts: 1,
      timeoutMs: Math.min(9000, Math.max(4500, options.maxSearchMs - 12000)),
    },
  );

  if (optimization.outcome !== "ok") {
    return {
      order: null,
      status: optimization.outcome,
      details: optimization.details,
    };
  }

  return {
    order: optimizationOrderFromWaypoints(
      optimization.waypoints,
      options.requiredWaypoints,
    ),
    status: "ok",
  };
}

function buildShapePoints(
  start: Coordinate,
  order: Coordinate[],
  targetDistanceKm: number,
  seed: number,
): Coordinate[][] {
  if (order.length === 0) return [];

  const first = order[0];
  const last = order[order.length - 1];
  const outboundBearing = calculateBearing(start, first);
  const inboundBearing = calculateBearing(last, start);
  const stopSpreadKm = Math.max(
    calculateDistance(start, first),
    calculateDistance(last, start),
  );
  const radiusKm = Math.max(
    2.8,
    Math.min(13.5, Math.max(stopSpreadKm * 0.72, targetDistanceKm * 0.13)),
  );
  const side = seed % 2 === 0 ? 1 : -1;
  const result: Coordinate[][] = [];

  for (const direction of [side, -side]) {
    const outboundShape = calculateDestination(
      start,
      radiusKm,
      outboundBearing + direction * 62,
    );
    const inboundShape = calculateDestination(
      last,
      radiusKm * 0.82,
      inboundBearing + direction * 58,
    );
    result.push([outboundShape, ...order, inboundShape]);

    if (order.length === 1) {
      const farShape = calculateDestination(
        first,
        radiusKm * 0.9,
        outboundBearing + 180 + direction * 70,
      );
      result.push([outboundShape, first, farShape]);
    }
  }

  return result;
}

function buildRequiredWaypointPlans(
  options: RequiredWaypointRoundTripOptions,
  orders: Coordinate[][],
): RequiredWaypointPlan[] {
  const plans: RequiredWaypointPlan[] = [];
  const addPlan = (
    label: string,
    strategy: string,
    requiredOrder: Coordinate[],
    interiorWaypoints: Coordinate[],
    continueStraight: boolean,
    alternatives = true,
    silentVia = false,
  ) => {
    const waypoints = [
      options.startLocation,
      ...interiorWaypoints,
      options.startLocation,
    ];
    plans.push({
      label,
      strategy,
      requiredOrder,
      waypoints,
      radiuses: radiusesForPlan(waypoints, requiredOrder),
      continueStraight,
      alternatives,
      silentVia,
    });
  };

  const targetKm = options.targetDistanceKm ?? 50;
  const isAutoSeed = options.waypointOrigin === "auto_seed";
  const seedOffset = stableStringHash(
    `${options.variantHint ?? ""}|${options.fingerprintHint ?? ""}`,
  );

  orders.forEach((order, orderIndex) => {
    addPlan(
      `order_${orderIndex}_direct_allow_reverse`,
      "directions_direct",
      order,
      order,
      false,
    );
    addPlan(
      `order_${orderIndex}_direct_continue`,
      "directions_direct_continue",
      order,
      order,
      true,
    );

    const shapedChains = buildShapePoints(
      options.startLocation,
      order,
      targetKm,
      options.randomSeed + seedOffset + orderIndex,
    );
    shapedChains.forEach((chain, shapeIndex) => {
      addPlan(
        `order_${orderIndex}_shape_${shapeIndex}_allow_reverse`,
        "directions_shape",
        order,
        chain,
        false,
      );
      if (shapeIndex === 0) {
        addPlan(
          `order_${orderIndex}_shape_${shapeIndex}_continue`,
          "directions_shape_continue",
          order,
          chain,
          true,
        );
      }
      if (isAutoSeed) {
        addPlan(
          `order_${orderIndex}_shape_${shapeIndex}_silent_via`,
          "directions_shape_silent_via",
          order,
          chain,
          false,
          false,
          true,
        );
      }
    });
  });

  return plans.slice(0, isAutoSeed ? 32 : 18);
}

export async function routeRequiredWaypointRoundTrip(
  options: RequiredWaypointRoundTripOptions,
): Promise<RequiredWaypointRoundTripResult> {
  const startedAt = Date.now();
  const fixedOrder = options.requiredWaypoints;
  const optimization = await buildOptimizedOrder(options);

  const orders = dedupeOrders([
    ...(optimization.order ? [optimization.order] : []),
    fixedOrder,
    ...(options.waypointOrder === "auto_optimize"
      ? permuteWaypoints(options.requiredWaypoints)
      : []),
  ]);
  const plans = buildRequiredWaypointPlans(options, orders);

  let bestRoute: any | null = null;
  let bestPlan: RequiredWaypointPlan | null = null;
  let bestScore = Number.POSITIVE_INFINITY;
  let rejectReason: string | null = null;
  let directionsAttemptCount = 0;
  let reachedRejectCount = 0;
  let qualityRejectCount = 0;
  const reachRejectDistances: number[][] = [];

  for (const plan of plans) {
    if (Date.now() - startedAt > options.maxSearchMs - 1200) break;
    directionsAttemptCount += 1;
    const fetchResult = await getMapboxRouteDetailed(
      plan.waypoints,
      options.mapboxProfile,
      options.excludeParams,
      plan.radiuses,
      options.accessToken,
      {
        continueStraight: plan.continueStraight,
        alternatives: plan.alternatives,
        maxAttempts: 1,
        routeLegWaypointIndexes: plan.silentVia
          ? [0, plan.waypoints.length - 1]
          : undefined,
        timeoutMs: Math.max(
          2800,
          Math.min(6200, options.maxSearchMs - (Date.now() - startedAt) - 900),
        ),
        retryDelayBaseMs: 180,
      },
    );

    const candidateRoutes = fetchResult.routes?.length
      ? fetchResult.routes
      : fetchResult.route
      ? [fetchResult.route]
      : [];
    if (candidateRoutes.length === 0) {
      rejectReason ??= fetchResult.outcome;
      continue;
    }

    for (
      let alternativeIndex = 0;
      alternativeIndex < candidateRoutes.length;
      alternativeIndex++
    ) {
      const candidateRoute = candidateRoutes[alternativeIndex];
      const reachDistances = waypointReachDistancesMeters(
        candidateRoute?.geometry?.coordinates,
        options.requiredWaypoints,
      );
      const reachedCount = reachDistances.filter((distance) =>
        distance <= REACH_THRESHOLD_METERS
      ).length;
      if (reachedCount < options.requiredWaypoints.length) {
        reachedRejectCount += 1;
        reachRejectDistances.push(reachDistances);
        rejectReason = "waypoint_not_reached";
        debugLog(
          `[WaypointOpt] ${plan.label} alt ${alternativeIndex} missed ${reachedCount}/${options.requiredWaypoints.length} stops`,
        );
        continue;
      }

      const quality = evaluateRouteQuality(candidateRoute, "ROUND_TRIP", {
        mode: options.mode,
        avoidHighways: options.avoidHighways,
        requiredStops: true,
        requiredStopCoordinates: options.requiredWaypoints,
      });
      if (!quality.passed) {
        qualityRejectCount += 1;
        rejectReason = quality.reason;
        debugLog(
          `[WaypointOpt] ${plan.label} alt ${alternativeIndex} rejected: ${quality.reason}`,
        );
        continue;
      }

      const distanceKm = getRouteDistanceKm(candidateRoute);
      const durationMin = typeof candidateRoute.duration === "number"
        ? candidateRoute.duration / 60
        : distanceKm * 1.7;
      const targetDistanceKm = options.targetDistanceKm ?? 0;
      const distanceFitPenalty = targetDistanceKm > 0
        ? Math.abs(distanceKm - targetDistanceKm) * 1.65 +
          Math.max(0, targetDistanceKm * 0.55 - distanceKm) * 3.5 +
          Math.max(0, distanceKm - targetDistanceKm * 1.45) * 1.2
        : 0;
      const score = durationMin + distanceKm * 0.30 + quality.score * 0.36 +
        distanceFitPenalty + alternativeIndex * 3 +
        (plan.continueStraight ? 3 : 0);
      const silentViaPenalty = plan.silentVia ? -2 : 0;
      const originPenalty = options.waypointOrigin === "auto_seed" &&
          plan.silentVia
        ? -3
        : 0;
      const finalScore = score + silentViaPenalty + originPenalty;

      if (finalScore < bestScore) {
        bestScore = finalScore;
        bestRoute = candidateRoute;
        bestPlan = plan;
      }
    }
  }

  const bestReachDistances = bestRoute
    ? waypointReachDistancesMeters(
      bestRoute?.geometry?.coordinates,
      options.requiredWaypoints,
    )
    : null;

  return {
    route: bestRoute,
    waypoints: bestPlan?.waypoints ?? [],
    radiuses: bestPlan?.radiuses ?? "",
    requiredOrder: bestPlan?.requiredOrder ?? fixedOrder,
    deliveredOrder: bestPlan == null
      ? null
      : waypointOrderIndices(bestPlan.requiredOrder, options.requiredWaypoints),
    rejectReason: bestRoute == null ? rejectReason : null,
    meta: {
      waypoint_strategy: bestPlan?.strategy ?? null,
      waypoint_candidate_plan_count: plans.length,
      waypoint_directions_attempt_count: directionsAttemptCount,
      optimization_used: optimization.order != null,
      optimization_status: optimization.status,
      optimization_order: optimization.order == null
        ? null
        : waypointOrderIndices(optimization.order, options.requiredWaypoints),
      directions_variant: bestPlan?.label ?? null,
      continue_straight_used: bestPlan?.continueStraight ?? null,
      silent_via_used: bestPlan?.silentVia ?? false,
      waypoint_origin: options.waypointOrigin ?? "manual",
      waypoint_seed_attempt: options.waypointSeedAttempt ?? null,
      reached_reject_count: reachedRejectCount,
      quality_reject_count: qualityRejectCount,
      waypoint_reach_distances_m: bestReachDistances,
      last_reach_reject_distances_m: reachRejectDistances.at(-1) ?? null,
      waypoint_quality_reject_reason: bestRoute == null ? rejectReason : null,
      last_waypoint_candidate_reject_reason: rejectReason,
    },
  };
}
