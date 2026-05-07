import { evaluateRouteQuality, scoreRouteStyleFit } from "./route_quality.ts";
import { calculateDistance } from "./routing_utils.ts";
import type { Coordinate, RouteMode } from "./routing_types.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

const origin: Coordinate = { latitude: 47.5, longitude: 9.7 };

function toCoordinate(xKm: number, yKm: number): Coordinate {
  return {
    latitude: origin.latitude + yKm / 111,
    longitude: origin.longitude +
      xKm / (111 * Math.cos(origin.latitude * Math.PI / 180)),
  };
}

function buildRoute(
  points: Array<[number, number]>,
  options: { stepKm?: number; maneuverUTurn?: boolean } = {},
): any {
  const stepKm = options.stepKm ?? 0.03;
  const coordinates: Coordinate[] = [];
  for (let i = 0; i < points.length - 1; i += 1) {
    const [x1, y1] = points[i];
    const [x2, y2] = points[i + 1];
    const steps = Math.max(1, Math.ceil(Math.hypot(x2 - x1, y2 - y1) / stepKm));
    for (let s = 0; s < steps; s += 1) {
      const t = s / steps;
      coordinates.push(toCoordinate(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t));
    }
  }
  const [lastX, lastY] = points[points.length - 1];
  coordinates.push(toCoordinate(lastX, lastY));

  let distanceKm = 0;
  for (let i = 1; i < coordinates.length; i += 1) {
    distanceKm += calculateDistance(coordinates[i - 1], coordinates[i]);
  }

  return {
    distance: distanceKm * 1000,
    geometry: {
      coordinates: coordinates.map((
        point,
      ) => [point.longitude, point.latitude]),
    },
    legs: options.maneuverUTurn
      ? [{
        steps: [{
          maneuver: {
            type: "turn",
            modifier: "uturn",
            instruction: "U-turn",
          },
        }],
      }]
      : [],
  };
}

function evaluateRoundTrip(route: any, mode: RouteMode) {
  return evaluateRouteQuality(route, "ROUND_TRIP", {
    targetDistanceKm: route.distance / 1000,
    mode,
    avoidHighways: true,
  });
}

Deno.test("geometry-only local hairpins in a clean loop are not rejected as invalid u-turns", () => {
  const route = buildRoute([
    [0, 0],
    [1, 0],
    [2, 0],
    [3, 0],
    [4, 0],
    [4, 0.7],
    [4.35, 0.78],
    [3.95, 0.88],
    [4.35, 0.98],
    [3.95, 1.08],
    [4.35, 1.18],
    [4, 1.35],
    [4, 2.2],
    [4, 3.2],
    [3, 4],
    [2, 4],
    [1, 4],
    [0, 4],
    [0, 3],
    [0, 2],
    [0, 1],
    [0, 0],
  ]);

  const quality = evaluateRoundTrip(route, "Kurvenjagd");

  assert(
    (quality.shapeMetrics?.geometricUTurnCount ?? 0) > 0,
    "fixture must exercise geometric u-turn detection",
  );
  assert(
    quality.passed,
    `expected local hairpin loop to pass, got ${quality.reason}`,
  );
  assert(
    quality.tier !== "rejected",
    "local hairpin loop must not be rejected",
  );
  assert(
    !quality.reason.startsWith("u_turn"),
    `local hairpin loop should not be reported as invalid u-turn: ${quality.reason}`,
  );
});

Deno.test("true out-and-back arm remains rejected", () => {
  const route = buildRoute([
    [0, 0],
    [5, 0],
    [0, 0],
    [0, 3],
    [4, 3],
    [0, 0],
  ], { stepKm: 0.05 });

  const quality = evaluateRoundTrip(route, "Kurvenjagd");

  assert(!quality.passed, "true out-and-back route must be rejected");
  assert(
    quality.tier === "rejected",
    "true out-and-back tier must be rejected",
  );
  assert(
    quality.reason === "u_turn_true_out_and_back" ||
      quality.reason.startsWith("shape=") ||
      quality.reason.startsWith("overlap="),
    `unexpected out-and-back reject reason: ${quality.reason}`,
  );
});

Deno.test("explicit Mapbox maneuver u-turn remains rejected", () => {
  const route = buildRoute([
    [0, 0],
    [1, 0],
    [1, 1],
    [0, 1],
    [0, 0],
  ], { maneuverUTurn: true });

  const quality = evaluateRoundTrip(route, "Kurvenjagd");

  assert(!quality.passed, "explicit maneuver u-turn must be rejected");
  assert(
    quality.reason === "u_turn",
    `unexpected maneuver reason: ${quality.reason}`,
  );
});

Deno.test("hairpin-heavy route fits Kurvenjagd better than Sport", () => {
  const route = buildRoute([
    [0, 0],
    [1, 0],
    [2, 0],
    [3, 0],
    [4, 0],
    [4, 0.7],
    [4.35, 0.78],
    [3.95, 0.88],
    [4.35, 0.98],
    [3.95, 1.08],
    [4.35, 1.18],
    [4, 1.35],
    [4, 2.2],
    [4, 3.2],
    [3, 4],
    [2, 4],
    [1, 4],
    [0, 4],
    [0, 3],
    [0, 2],
    [0, 1],
    [0, 0],
  ]);

  const curvyScore = scoreRouteStyleFit(route, "Kurvenjagd").score;
  const sportScore = scoreRouteStyleFit(route, "Sport Mode").score;

  assert(
    curvyScore > sportScore,
    `expected Kurvenjagd score ${curvyScore} to exceed Sport score ${sportScore}`,
  );
});

Deno.test("dense guidance geometry does not create extra invalid u-turn rejects", () => {
  const points: Array<[number, number]> = [
    [0, 0],
    [1.2, 0],
    [2.6, 0.4],
    [3.8, 1.1],
    [4.1, 2.0],
    [3.6, 2.45],
    [4.05, 2.9],
    [3.55, 3.35],
    [3.9, 3.85],
    [2.7, 4.4],
    [1.4, 4.3],
    [0.2, 3.5],
    [-0.2, 2.1],
    [0, 0],
  ];
  const simplified = buildRoute(points, { stepKm: 0.12 });
  const denseGuidance = buildRoute(points, { stepKm: 0.008 });

  const simplifiedQuality = evaluateRoundTrip(simplified, "Kurvenjagd");
  const denseQuality = evaluateRoundTrip(denseGuidance, "Kurvenjagd");

  assert(
    simplifiedQuality.passed,
    `fixture simplified route must pass, got ${simplifiedQuality.reason}`,
  );
  assert(
    denseQuality.passed,
    `dense guidance route should not be rejected only because of point density, got ${denseQuality.reason}`,
  );
  assert(
    !denseQuality.reason.startsWith("u_turn"),
    `dense guidance route should not become invalid u-turn: ${denseQuality.reason}`,
  );
});
