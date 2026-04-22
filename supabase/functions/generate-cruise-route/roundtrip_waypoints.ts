import type {
  Coordinate,
  DistanceConfig,
  RoundTripCandidatePlan,
  RouteMode,
} from "./routing_types.ts";
import {
  calculateBearing,
  calculateDestination,
  calculateDistance,
  normalizeBearingDegrees,
  seededBaseBearing,
  seededUnit,
} from "./routing_utils.ts";

export function getDistanceConfig(
  targetDistance: number,
  mode?: string,
): DistanceConfig {
  // Erfolgsquote vor Perfektion: idealer Zielkorridor plus breiterer
  // akzeptabler Bereich. 50 / 75 / 100 / 150 km bewusst unterschiedlich
  // staffeln (nicht nur zwei Buckets), damit längere Ziele sichtbar weiter
  // „ausgreifen“ müssen als kurze 50er-Runden.
  let idealTolerance: number;
  let acceptableTolerance: number;
  if (targetDistance <= 55) {
    idealTolerance = 0.12;
    acceptableTolerance = 0.19;
  } else if (targetDistance <= 85) {
    idealTolerance = 0.11;
    acceptableTolerance = 0.175;
  } else if (targetDistance <= 115) {
    idealTolerance = 0.10;
    acceptableTolerance = 0.155;
  } else {
    idealTolerance = 0.09;
    acceptableTolerance = 0.14;
  }
  const minKm = Math.round(targetDistance * (1 - idealTolerance));
  const maxKm = Math.round(targetDistance * (1 + idealTolerance));
  const acceptableMinKm = Math.round(
    targetDistance * (1 - acceptableTolerance),
  );
  const acceptableMaxKm = Math.round(
    targetDistance * (1 + acceptableTolerance),
  );

  // Formel: radius = targetDistance / (2 * PI * road_factor)
  // road_factor variiert stark je nach Stil, weil Landstraßen-Routing
  // deutlich längere Wege erzeugt als Direktverbindungen.
  let roadFactor: number;
  switch (mode) {
    case "Kurvenjagd":
      roadFactor = targetDistance > 110
        ? 1.60
        : targetDistance <= 60
        ? 1.68
        : targetDistance <= 90
        ? 1.73
        : 1.70; // Mehr Raum für saubere Berg-/Loopformen statt gefalteter Äste
      break;
    case "Entdecker":
      roadFactor = targetDistance > 110
        ? 1.50
        : targetDistance <= 60
        ? 1.54
        : targetDistance <= 90
        ? 1.60
        : 1.58; // Etwas weiter greifen, damit Entdecker nicht zu eng faltet
      break;
    case "Abendrunde":
      roadFactor = targetDistance > 110 ? 1.10 : 1.12; // Ruhiger Radius, aber kein Zentrumsknäuel
      break;
    case "Sport Mode":
      roadFactor = targetDistance > 110
        ? 1.22
        : targetDistance <= 60
        ? 1.46
        : targetDistance <= 90
        ? 1.30
        : 1.26; // Gestreckterer Suchraum für flüssige Sport-Loops
      break;
    default:
      roadFactor = 1.25;
  }
  const shortDistanceBoost = targetDistance <= 55
    ? 0.80
    : targetDistance <= 85
    ? 0.87
    : targetDistance <= 115
    ? 0.93
    : 0.98;
  const radiusKm = targetDistance /
    (2 * Math.PI * roadFactor * shortDistanceBoost);
  let waypointRadiusMeters = targetDistance <= 55
    ? 3200
    : targetDistance <= 85
    ? 4000
    : targetDistance <= 115
    ? 4600
    : 5400;
  if (mode === "Kurvenjagd") waypointRadiusMeters += 500;
  if (mode === "Entdecker") waypointRadiusMeters += 700;
  if (mode === "Abendrunde") {
    waypointRadiusMeters = Math.max(2800, waypointRadiusMeters - 200);
  }

  console.log(
    `Distance config: target=${targetDistance}km, radius=${
      radiusKm.toFixed(1)
    }km, ` +
      `idealBand=${minKm}-${maxKm}km, acceptableBand=${acceptableMinKm}-${acceptableMaxKm}km, ` +
      `snapRadius=${waypointRadiusMeters}m, roadFactor=${roadFactor}, mode=${mode}`,
  );
  return {
    radiusKm,
    minKm,
    maxKm,
    acceptableMinKm,
    acceptableMaxKm,
    waypointRadiusMeters,
  };
}

function calculateTriangleWaypoints(
  start: Coordinate,
  searchRadiusKm: number,
  seed?: number,
  preferredBearingDegrees?: number,
): Coordinate[] {
  // Seeded random für reproduzierbare aber variable Routen
  const s = seed ?? Math.floor(Math.random() * 100000);
  const rng = (offset: number) => seededUnit(s + offset);

  const baseBearing = seededBaseBearing(s, preferredBearingDegrees);

  // WP1: Outbound direction, full radius
  const wp1 = calculateDestination(
    start,
    searchRadiusKm * (0.8 + rng(1) * 0.4), // 0.8–1.2× radius
    baseBearing,
  );

  // WP2: 100–140° offset from WP1 direction, slightly shorter
  const returnBearing = (baseBearing + 100 + rng(2) * 40) % 360;
  const wp2 = calculateDestination(
    start,
    searchRadiusKm * (0.65 + rng(3) * 0.2), // 0.65–0.85× radius
    returnBearing,
  );

  return [wp1, wp2];
}

function calculateLoopWaypoints(
  start: Coordinate,
  searchRadiusKm: number,
  numWaypoints: number = 5,
  seed?: number,
  preferredBearingDegrees?: number,
  bearingJitterDegrees: number = 110,
): Coordinate[] {
  // Seeded random für reproduzierbare aber variable Routen
  const s = seed ?? Math.floor(Math.random() * 100000);
  const rng = (offset: number) => seededUnit(s + offset);

  const baseBearing = seededBaseBearing(
    s + 97,
    preferredBearingDegrees,
    bearingJitterDegrees,
  );
  // Sweep < 360° to avoid star/spider plans that repeatedly cut back through center.
  const sweepDegrees = 275 + rng(3) * 45;
  const startOffset = -sweepDegrees / 2 + (rng(4) - 0.5) * 18;
  const angleStep = numWaypoints <= 1 ? 0 : sweepDegrees / (numWaypoints - 1);

  const waypoints: Coordinate[] = [];

  for (let i = 0; i < numWaypoints; i++) {
    // Keep a tighter ring to reduce multi-arm center returns and hooks.
    const distanceVariation = 0.86 + (rng(10 + i * 2) * 0.24);
    const distance = searchRadiusKm * distanceVariation;

    // Mild bearing jitter keeps routes natural without creating sharp spider spokes.
    const bearing = baseBearing + startOffset + (angleStep * i) +
      (rng(11 + i * 2) * 12 - 6);

    const wp = calculateDestination(start, distance, bearing);
    waypoints.push(wp);
  }

  return enforceWaypointRadiusBand(
    start,
    smoothWaypointChain(waypoints, 0.22),
    searchRadiusKm * 0.68,
    searchRadiusKm * 1.22,
  );
}

function calculateCardinalLoopWaypoints(
  start: Coordinate,
  searchRadiusKm: number,
  seed?: number,
  preferredBearingDegrees?: number,
  ellipseFactor: number = 1.0,
  bearingJitterDegrees: number = 110,
): Coordinate[] {
  const s = seed ?? Math.floor(Math.random() * 100000);
  const rng = (offset: number) => seededUnit(s + offset);
  const baseBearing = seededBaseBearing(
    s + 211,
    preferredBearingDegrees,
    bearingJitterDegrees,
  );
  const normalizedEllipse = Math.max(0.75, ellipseFactor);
  const bearings = [20, 102, 198, 286];
  const waypoints = bearings.map((bearingOffset, index) => {
    const axisFactor = index % 2 === 0
      ? normalizedEllipse
      : Math.max(0.65, 1 / normalizedEllipse);
    const distanceVariation = 0.90 + rng(31 + index * 7) * 0.14;
    const bearingJitter = (rng(32 + index * 7) - 0.5) * 10;
    return calculateDestination(
      start,
      searchRadiusKm * axisFactor * distanceVariation,
      baseBearing + bearingOffset + bearingJitter,
    );
  });

  return enforceWaypointRadiusBand(
    start,
    smoothWaypointChain(waypoints, 0.2),
    searchRadiusKm * 0.66,
    searchRadiusKm * 1.24,
  );
}

function calculateZigZagWaypoints(
  start: Coordinate,
  searchRadiusKm: number,
  seed?: number,
  preferredBearingDegrees?: number,
): Coordinate[] {
  const s = seed ?? Math.floor(Math.random() * 100000);
  const rng = (offset: number) => seededUnit(s + offset);
  const baseBearing = seededBaseBearing(s + 377, preferredBearingDegrees);
  // Softer "S" rhythm to avoid aggressive hooks.
  const offsets = [34, -32, 92, -86];

  const waypoints = offsets.map((offset, index) => {
    const distanceFactor = 0.90 + rng(71 + index * 11) * 0.20;
    const drift = (rng(72 + index * 11) - 0.5) * 12;
    return calculateDestination(
      start,
      searchRadiusKm * distanceFactor,
      baseBearing + offset + drift,
    );
  });

  return enforceWaypointRadiusBand(
    start,
    smoothWaypointChain(waypoints, 0.18),
    searchRadiusKm * 0.70,
    searchRadiusKm * 1.20,
  );
}

function calculateReturnPath(
  start: Coordinate,
  outboundWaypoints: Coordinate[],
  seed?: number,
): Coordinate[] {
  if (outboundWaypoints.length < 2) return [];
  const s = seed ?? Math.floor(Math.random() * 100000);
  const rng = (offset: number) => seededUnit(s + offset);

  const firstWp = outboundWaypoints[0];
  const lastWp = outboundWaypoints[outboundWaypoints.length - 1];
  const firstBearing = calculateBearing(start, firstWp);
  const lastBearing = calculateBearing(start, lastWp);
  const blendedBearing = normalizeBearingDegrees(
    (firstBearing + lastBearing) / 2 + 90 + (rng(50) - 0.5) * 28,
  );
  const returnBearing = blendedBearing;
  const outerRadius = Math.max(
    calculateDistance(start, firstWp),
    calculateDistance(start, lastWp),
  );
  const returnDistance = outerRadius * (0.78 + rng(51) * 0.2);

  const returnWp = calculateDestination(start, returnDistance, returnBearing);
  return enforceWaypointRadiusBand(
    start,
    [returnWp],
    Math.max(outerRadius * 0.62, 0.8),
    Math.max(outerRadius * 1.18, 1.6),
  );
}

function calculateLoopWithReturnWaypoints(
  start: Coordinate,
  searchRadiusKm: number,
  outboundWaypointCount: number,
  seed?: number,
  preferredBearingDegrees?: number,
  bearingJitterDegrees: number = 110,
): Coordinate[] {
  const outbound = calculateLoopWaypoints(
    start,
    searchRadiusKm,
    Math.max(2, outboundWaypointCount),
    seed,
    preferredBearingDegrees,
    bearingJitterDegrees,
  );
  const returnWaypoints = calculateReturnPath(
    start,
    outbound,
    (seed ?? 0) + 73,
  );
  return [...outbound, ...returnWaypoints];
}

function calculateAnchoredLoopWaypoints(
  start: Coordinate,
  searchRadiusKm: number,
  bearingOffsets: number[],
  distanceFactors: number[],
  seed?: number,
  preferredBearingDegrees?: number,
  options?: {
    bearingJitterDegrees?: number;
    pointBearingJitterDegrees?: number;
    radialJitter?: number;
    smoothing?: number;
    minRadiusFactor?: number;
    maxRadiusFactor?: number;
  },
): Coordinate[] {
  const s = seed ?? Math.floor(Math.random() * 100000);
  const rng = (offset: number) => seededUnit(s + offset);
  const baseBearing = seededBaseBearing(
    s + 463,
    preferredBearingDegrees,
    options?.bearingJitterDegrees ?? 26,
  );
  const pointBearingJitterDegrees = options?.pointBearingJitterDegrees ?? 8;
  const radialJitter = options?.radialJitter ?? 0.10;

  const waypoints = bearingOffsets.map((bearingOffset, index) => {
    const rawDistanceFactor = distanceFactors[index] ??
      distanceFactors.at(-1) ??
      1.0;
    const distanceVariation = 1 +
      (rng(91 + index * 7) - 0.5) * radialJitter;
    const bearingJitter = (rng(92 + index * 7) - 0.5) *
      pointBearingJitterDegrees;
    return calculateDestination(
      start,
      searchRadiusKm * rawDistanceFactor * distanceVariation,
      baseBearing + bearingOffset + bearingJitter,
    );
  });

  return enforceWaypointRadiusBand(
    start,
    smoothWaypointChain(waypoints, options?.smoothing ?? 0.16),
    searchRadiusKm * (options?.minRadiusFactor ?? 0.68),
    searchRadiusKm * (options?.maxRadiusFactor ?? 1.18),
  );
}

function calculatePairedLoopWaypoints(
  start: Coordinate,
  searchRadiusKm: number,
  corridorBearingDegrees: number,
  seed?: number,
  options?: {
    spreadDegrees?: number;
    distanceFactors?: [number, number, number];
    bearingJitterDegrees?: number;
    radialJitter?: number;
    smoothing?: number;
    minRadiusFactor?: number;
    maxRadiusFactor?: number;
  },
): Coordinate[] {
  const s = seed ?? Math.floor(Math.random() * 100000);
  const rng = (offset: number) => seededUnit(s + offset);
  const spread = options?.spreadDegrees ?? 58;
  const factors = options?.distanceFactors ?? [1.02, 1.16, 1.02];
  const bearingJitterDegrees = options?.bearingJitterDegrees ?? 5;
  const radialJitter = options?.radialJitter ?? 0.045;
  const bearings = [
    corridorBearingDegrees - spread,
    corridorBearingDegrees,
    corridorBearingDegrees + spread,
  ];

  const waypoints = bearings.map((bearing, index) => {
    const distanceFactor = factors[index] ?? factors[1];
    const distanceVariation = 1 +
      (rng(300 + index * 17) - 0.5) * radialJitter;
    const bearingJitter = (rng(301 + index * 17) - 0.5) *
      bearingJitterDegrees;
    return calculateDestination(
      start,
      searchRadiusKm * distanceFactor * distanceVariation,
      bearing + bearingJitter,
    );
  });

  return enforceWaypointRadiusBand(
    start,
    smoothWaypointChain(waypoints, options?.smoothing ?? 0.08),
    searchRadiusKm * (options?.minRadiusFactor ?? 0.88),
    searchRadiusKm * (options?.maxRadiusFactor ?? 1.22),
  );
}

export function enforceWaypointRadiusBand(
  start: Coordinate,
  waypoints: Coordinate[],
  minRadiusKm: number,
  maxRadiusKm: number,
): Coordinate[] {
  const clampedMin = Math.max(0, minRadiusKm);
  const clampedMax = Math.max(clampedMin + 0.05, maxRadiusKm);
  return waypoints.map((wp) => {
    const radius = calculateDistance(start, wp);
    if (radius >= clampedMin && radius <= clampedMax) return wp;
    const bearing = calculateBearing(start, wp);
    const adjustedRadius = Math.min(clampedMax, Math.max(clampedMin, radius));
    return calculateDestination(start, adjustedRadius, bearing);
  });
}

export function smoothWaypointChain(
  waypoints: Coordinate[],
  strength: number = 0.2,
): Coordinate[] {
  if (waypoints.length < 3) return waypoints;
  const clampedStrength = Math.max(0, Math.min(0.45, strength));
  return waypoints.map((wp, i) => {
    if (i === 0 || i === waypoints.length - 1) return wp;
    const prev = waypoints[i - 1];
    const next = waypoints[i + 1];
    const corridorMid = {
      latitude: (prev.latitude + next.latitude) / 2,
      longitude: (prev.longitude + next.longitude) / 2,
    };
    return {
      latitude: wp.latitude * (1 - clampedStrength) +
        corridorMid.latitude * clampedStrength,
      longitude: wp.longitude * (1 - clampedStrength) +
        corridorMid.longitude * clampedStrength,
    };
  });
}

function buildWaypointRadiuses(
  waypoints: Coordinate[],
  intermediateRadiusMeters: number,
): string {
  return waypoints
    .map((_, i) =>
      (i === 0 || i === waypoints.length - 1)
        ? "unlimited"
        : `${intermediateRadiusMeters}`
    )
    .join(";");
}

function dedupeRoundTripPlans(
  plans: RoundTripCandidatePlan[],
): RoundTripCandidatePlan[] {
  const seen = new Set<string>();
  const result: RoundTripCandidatePlan[] = [];

  for (const plan of plans) {
    const signature = plan.waypoints
      .map((wp) => `${wp.latitude.toFixed(4)},${wp.longitude.toFixed(4)}`)
      .join("|");
    if (seen.has(signature)) continue;
    seen.add(signature);
    result.push(plan);
  }

  return result;
}

export function buildRoundTripWaypointCandidates({
  start,
  distanceConfig,
  targetDistanceKm,
  mode,
  randomSeed,
  preferredBearingDegrees,
  waypointShapeFactor,
  radiusMultiplier = 1,
  zigzagWaypoints = false,
  simplifyWaypoints = false,
  maxWaypoints,
  avoidHighways = false,
}: {
  start: Coordinate;
  distanceConfig: DistanceConfig;
  targetDistanceKm: number;
  mode?: RouteMode;
  randomSeed: number;
  preferredBearingDegrees?: number;
  waypointShapeFactor?: number;
  radiusMultiplier?: number;
  zigzagWaypoints?: boolean;
  simplifyWaypoints?: boolean;
  maxWaypoints?: number;
  avoidHighways?: boolean;
}): RoundTripCandidatePlan[] {
  const plans: RoundTripCandidatePlan[] = [];
  const shortTarget = targetDistanceKm <= 60;
  const mediumTarget = targetDistanceKm > 60 && targetDistanceKm <= 110;
  const longTarget = targetDistanceKm > 110;
  const baseRadius = distanceConfig.radiusKm * Math.max(0.7, radiusMultiplier);
  const baseSnapRadius = distanceConfig.waypointRadiusMeters;
  const avoidHighwaysShortSportSearch = avoidHighways &&
    mode === "Sport Mode" &&
    shortTarget;

  const addPlan = (
    label: string,
    waypoints: Coordinate[],
    snapMultiplier: number = 1,
  ) => {
    const fullWaypoints = [start, ...waypoints, start];
    plans.push({
      label,
      waypoints: fullWaypoints,
      radiuses: buildWaypointRadiuses(
        fullWaypoints,
        Math.round(baseSnapRadius * snapMultiplier),
      ),
    });
  };

  if (avoidHighwaysShortSportSearch) {
    const pairedLoop = (
      multiplier: number,
      corridorBearingDegrees: number,
      seedOffset: number,
      spreadDegrees: number,
      distanceFactors: [number, number, number],
    ) =>
      calculatePairedLoopWaypoints(
        start,
        baseRadius * multiplier,
        corridorBearingDegrees,
        randomSeed + seedOffset,
        {
          spreadDegrees,
          distanceFactors,
          bearingJitterDegrees: 4,
          radialJitter: 0.035,
          smoothing: 0.06,
          minRadiusFactor: 0.90,
          maxRadiusFactor: 1.22,
        },
      );

    addPlan(
      "sport-paired-west",
      pairedLoop(1.24, 272, 1901, 60, [1.03, 1.20, 1.05]),
      1.02,
    );
    addPlan(
      "sport-paired-northwest",
      pairedLoop(1.31, 306, 1907, 56, [1.04, 1.22, 1.06]),
      1.02,
    );
    addPlan(
      "sport-paired-southwest",
      pairedLoop(1.24, 238, 1913, 56, [1.02, 1.19, 1.03]),
      1.02,
    );
    addPlan(
      "sport-paired-northwest-wide",
      pairedLoop(1.33, 304, 1919, 62, [1.04, 1.22, 1.06]),
      1.06,
    );
    addPlan(
      "sport-paired-west-wide",
      pairedLoop(1.29, 274, 1927, 64, [1.04, 1.20, 1.05]),
      1.06,
    );
    addPlan(
      "sport-paired-southwest-wide",
      pairedLoop(1.25, 236, 1933, 62, [1.02, 1.18, 1.03]),
      1.06,
    );
    addPlan(
      "sport-paired-northwest-long",
      pairedLoop(1.29, 306, 1939, 60, [1.04, 1.20, 1.05]),
      1.08,
    );
    addPlan(
      "sport-paired-east",
      pairedLoop(1.20, 74, 1957, 56, [1.02, 1.17, 1.03]),
      1.04,
    );
    addPlan(
      "sport-paired-west-long",
      pairedLoop(1.23, 272, 1949, 66, [1.03, 1.18, 1.04]),
      1.08,
    );

    return dedupeRoundTripPlans(plans);
  }

  const triangle = (multiplier: number, seedOffset: number) =>
    calculateTriangleWaypoints(
      start,
      baseRadius * multiplier,
      randomSeed + seedOffset,
      preferredBearingDegrees,
    );
  const cardinal = (
    multiplier: number,
    seedOffset: number,
    ellipseFactor: number = 1.0,
  ) =>
    calculateCardinalLoopWaypoints(
      start,
      baseRadius * multiplier,
      randomSeed + seedOffset,
      preferredBearingDegrees,
      ellipseFactor,
    );
  const loop = (
    multiplier: number,
    waypointCount: number,
    seedOffset: number,
  ) =>
    calculateLoopWaypoints(
      start,
      baseRadius * multiplier,
      waypointCount,
      randomSeed + seedOffset,
      preferredBearingDegrees,
    );
  const loopWithReturn = (
    multiplier: number,
    waypointCount: number,
    seedOffset: number,
    preferredBearingDegrees?: number,
    bearingJitterDegrees: number = 110,
  ) =>
    calculateLoopWithReturnWaypoints(
      start,
      baseRadius * multiplier,
      waypointCount,
      randomSeed + seedOffset,
      preferredBearingDegrees,
      bearingJitterDegrees,
    );
  const directionalLoop = (
    multiplier: number,
    waypointCount: number,
    seedOffset: number,
    preferredBearingDegrees: number,
    bearingJitterDegrees: number = 24,
  ) =>
    calculateLoopWaypoints(
      start,
      baseRadius * multiplier,
      waypointCount,
      randomSeed + seedOffset,
      preferredBearingDegrees,
      bearingJitterDegrees,
    );
  const directionalCardinal = (
    multiplier: number,
    seedOffset: number,
    preferredBearingDegrees: number,
    ellipseFactor: number = 1.0,
    bearingJitterDegrees: number = 24,
  ) =>
    calculateCardinalLoopWaypoints(
      start,
      baseRadius * multiplier,
      randomSeed + seedOffset,
      preferredBearingDegrees,
      ellipseFactor,
      bearingJitterDegrees,
    );
  const anchoredLoop = (
    multiplier: number,
    preferredBearingDegrees: number,
    bearingOffsets: number[],
    distanceFactors: number[],
    seedOffset: number,
    options?: {
      bearingJitterDegrees?: number;
      pointBearingJitterDegrees?: number;
      radialJitter?: number;
      smoothing?: number;
      minRadiusFactor?: number;
      maxRadiusFactor?: number;
    },
  ) =>
    calculateAnchoredLoopWaypoints(
      start,
      baseRadius * multiplier,
      bearingOffsets,
      distanceFactors,
      randomSeed + seedOffset,
      preferredBearingDegrees,
      options,
    );
  const zigzag = (multiplier: number, seedOffset: number) =>
    calculateZigZagWaypoints(
      start,
      baseRadius * multiplier,
      randomSeed + seedOffset,
      preferredBearingDegrees,
    );

  switch (mode) {
    case "Kurvenjagd":
      if (longTarget) {
        addPlan("curve-cardinal-wide", cardinal(1.14, 101, 1.0), 1.12);
        addPlan("curve-cardinal-grand", cardinal(1.24, 1601, 1.0), 1.16);
        addPlan("curve-zigzag-core", zigzag(1.06, 73), 1.16);
        addPlan("curve-triangle-wide", triangle(1.14, 887), 1.10);
        addPlan("curve-loop-wide", loop(1.20, 4, 131), 1.16);
        addPlan("curve-loop-grand", loop(1.34, 4, 1703), 1.20);
        addPlan("curve-orbital-sweep", loopWithReturn(1.10, 4, 73), 1.14);
        addPlan("curve-loop-open", loop(1.28, 4, 541), 1.20);
        addPlan("curve-triangle", triangle(1.00, 397), 1.0);
        addPlan("curve-loop-tight", loop(1.02, 4, 11), 1.05);
        addPlan("curve-loop-scout", loop(0.92, 3, 997), 1.0);
      } else {
        addPlan(
          "curve-cardinal-tight",
          cardinal(1.06, 101, 1.0),
          1.08,
        );
        addPlan("curve-loop-tight", loop(1.02, shortTarget ? 4 : 5, 11), 1.04);
        addPlan("curve-triangle", triangle(0.96, 397), 0.98);
        addPlan("curve-loop-scout", loop(0.92, shortTarget ? 3 : 4, 997), 1.0);
        addPlan("curve-zigzag-core", zigzag(0.96, 73), 1.06);
        addPlan(
          "curve-loop-wide",
          loop(longTarget ? 1.26 : 1.12, mediumTarget ? 4 : 5, 131),
          1.12,
        );
        addPlan(
          "curve-loop-open",
          loop(longTarget ? 1.34 : 1.16, mediumTarget ? 5 : 4, 541),
          1.14,
        );
        addPlan("curve-triangle-wide", triangle(1.10, 887), 1.08);
        addPlan(
          "curve-orbital-core",
          loopWithReturn(shortTarget ? 1.00 : 1.06, shortTarget ? 3 : 4, 73),
          1.10,
        );
      }
      break;
    case "Abendrunde":
      addPlan("evening-cardinal-soft", cardinal(0.84, 91, 0.92), 0.94);
      addPlan("evening-triangle-compact", triangle(0.90, 17), 0.95);
      addPlan("evening-triangle-wide", triangle(1.05, 149), 1.0);
      addPlan("evening-triangle-extended", triangle(1.18, 563), 1.1);
      addPlan("evening-loop-soft", loop(0.98, 3, 281), 1.0);
      addPlan("evening-loop-wide", loop(1.12, 3, 881), 1.12);
      addPlan("evening-orbital-soft", loopWithReturn(0.92, 3, 41), 0.98);
      addPlan("evening-triangle-relaxed", triangle(1.28, 1151), 1.16);
      break;
    case "Entdecker":
      addPlan("explore-cardinal-wide", cardinal(1.12, 67, 1.08), 1.12);
      if (zigzagWaypoints) {
        addPlan("explore-zigzag", zigzag(1.06, 883), 1.12);
      }
      addPlan(
        "explore-loop-wide",
        loop(longTarget ? 1.28 : 1.18, mediumTarget ? 4 : 5, 23),
        1.16,
      );
      addPlan(
        "explore-loop-offset",
        loop(1.08, shortTarget ? 3 : 4, 307),
        1.15,
      );
      addPlan(
        "explore-loop-far",
        loop(longTarget ? 1.36 : 1.24, mediumTarget ? 5 : 4, 587),
        1.24,
      );
      addPlan("explore-triangle", triangle(1.12, 443), 1.0);
      addPlan(
        "explore-orbital-wide",
        loopWithReturn(longTarget ? 1.16 : 1.08, mediumTarget ? 4 : 3, 47),
        1.12,
      );
      addPlan("explore-loop-scout", loop(0.96, shortTarget ? 3 : 4, 953), 1.08);
      break;
    case "Sport Mode":
    default:
      if (avoidHighwaysShortSportSearch) {
        addPlan(
          "sport-rheintal-west",
          anchoredLoop(
            0.96,
            282,
            [-10, 62],
            [0.94, 0.98],
            59,
            {
              bearingJitterDegrees: 12,
              pointBearingJitterDegrees: 5,
              radialJitter: 0.05,
              smoothing: 0.12,
              minRadiusFactor: 0.78,
              maxRadiusFactor: 1.04,
            },
          ),
          0.98,
        );
        addPlan(
          "sport-compact-oval-southwest",
          anchoredLoop(
            0.94,
            244,
            [-12, 58],
            [0.90, 0.96],
            271,
            {
              bearingJitterDegrees: 12,
              pointBearingJitterDegrees: 5,
              radialJitter: 0.05,
              smoothing: 0.12,
              minRadiusFactor: 0.78,
              maxRadiusFactor: 1.04,
            },
          ),
          0.98,
        );
        addPlan(
          "sport-offset-loop-north",
          anchoredLoop(
            0.98,
            326,
            [-18, 56],
            [0.92, 0.98],
            443,
            {
              bearingJitterDegrees: 12,
              pointBearingJitterDegrees: 5,
              radialJitter: 0.05,
              smoothing: 0.12,
              minRadiusFactor: 0.80,
              maxRadiusFactor: 1.06,
            },
          ),
          1.00,
        );
        addPlan(
          "sport-loop-flow-west",
          anchoredLoop(
            1.02,
            292,
            [-14, 60],
            [0.94, 1.00],
            29,
            {
              bearingJitterDegrees: 12,
              pointBearingJitterDegrees: 5,
              radialJitter: 0.05,
              smoothing: 0.12,
              minRadiusFactor: 0.80,
              maxRadiusFactor: 1.06,
            },
          ),
          1.00,
        );
        addPlan(
          "sport-loop-scout-southwest",
          anchoredLoop(
            0.90,
            230,
            [-8, 54],
            [0.88, 0.94],
            1031,
            {
              bearingJitterDegrees: 12,
              pointBearingJitterDegrees: 5,
              radialJitter: 0.05,
              smoothing: 0.12,
              minRadiusFactor: 0.76,
              maxRadiusFactor: 1.02,
            },
          ),
          0.96,
        );
        addPlan(
          "sport-cardinal-northwest",
          directionalCardinal(0.84, 173, 304, 1.06, 14),
          0.98,
        );
        addPlan(
          "sport-valley-safe-west",
          directionalCardinal(0.80, 611, 270, 1.04, 14),
          0.96,
        );
        break;
      }
      addPlan(
        "sport-cardinal-ellipse",
        cardinal(1.04, 59, waypointShapeFactor ?? 2.0),
        1.02,
      );
      addPlan("sport-loop-flow", loop(1.10, shortTarget ? 3 : 4, 29), 1.0);
      addPlan(
        "sport-loop-wide",
        loop(longTarget ? 1.22 : 1.14, mediumTarget ? 4 : 3, 173),
        1.12,
      );
      addPlan(
        "sport-loop-extended",
        loop(longTarget ? 1.30 : 1.18, mediumTarget ? 4 : 3, 611),
        1.18,
      );
      if (longTarget) {
        addPlan(
          "sport-cardinal-long",
          cardinal(1.20, 1717, waypointShapeFactor ?? 2.0),
          1.10,
        );
        addPlan("sport-loop-grand", loop(1.36, 4, 1423), 1.18);
      }
      addPlan("sport-triangle", triangle(1.00, 457), 1.0);
      addPlan(
        "sport-orbital-flow",
        loopWithReturn(shortTarget ? 1.00 : 1.08, shortTarget ? 3 : 4, 37),
        1.04,
      );
      addPlan("sport-loop-scout", loop(0.92, 3, 1031), 1.0);
      addPlan("sport-triangle-wide", triangle(1.16, 1289), 1.08);
      break;
  }

  if (avoidHighwaysShortSportSearch) {
    addPlan(
      "fallback-valley-safe-southwest",
      directionalCardinal(0.80, 1499, 236, 1.06, 14),
      0.98,
    );
    addPlan(
      "fallback-rheintal-west",
      anchoredLoop(
        0.92,
        288,
        [-8, 58],
        [0.90, 0.96],
        1607,
        {
          bearingJitterDegrees: 12,
          pointBearingJitterDegrees: 5,
          radialJitter: 0.05,
          smoothing: 0.12,
          minRadiusFactor: 0.78,
          maxRadiusFactor: 1.04,
        },
      ),
      0.98,
    );
    addPlan(
      "fallback-compact-oval-north",
      anchoredLoop(
        0.94,
        342,
        [-10, 56],
        [0.90, 0.96],
        503,
        {
          bearingJitterDegrees: 12,
          pointBearingJitterDegrees: 5,
          radialJitter: 0.05,
          smoothing: 0.12,
          minRadiusFactor: 0.78,
          maxRadiusFactor: 1.04,
        },
      ),
      0.98,
    );
    addPlan(
      "fallback-cardinal-west",
      directionalCardinal(0.84, 619, 272, 1.04, 14),
      0.98,
    );
    addPlan(
      "fallback-offset-loop-west",
      anchoredLoop(
        0.92,
        252,
        [-10, 54],
        [0.90, 0.96],
        733,
        {
          bearingJitterDegrees: 12,
          pointBearingJitterDegrees: 5,
          radialJitter: 0.05,
          smoothing: 0.12,
          minRadiusFactor: 0.78,
          maxRadiusFactor: 1.04,
        },
      ),
      0.98,
    );
    addPlan(
      "fallback-loop-rheintal",
      anchoredLoop(
        0.96,
        296,
        [-14, 58],
        [0.92, 0.98],
        857,
        {
          bearingJitterDegrees: 12,
          pointBearingJitterDegrees: 5,
          radialJitter: 0.05,
          smoothing: 0.12,
          minRadiusFactor: 0.80,
          maxRadiusFactor: 1.06,
        },
      ),
      1.00,
    );
  } else {
    addPlan(
      "fallback-cardinal",
      cardinal(1.00, 1499, waypointShapeFactor ?? 1.0),
      1.08,
    );
    if (shortTarget && mode === "Kurvenjagd") {
      addPlan(
        "fallback-cardinal-ellipse",
        cardinal(0.96, 1607, 1.18),
        1.06,
      );
    }
    addPlan(
      "fallback-triangle-compact",
      triangle(shortTarget ? 0.88 : 0.84, 503),
      1.0,
    );
    addPlan(
      "fallback-triangle-balanced",
      triangle(shortTarget ? 0.96 : 1.00, 619),
      1.05,
    );
    addPlan(
      "fallback-triangle-wide",
      triangle(shortTarget ? 1.06 : 1.12, 1181),
      1.08,
    );
    if (!shortTarget) {
      addPlan(
        "fallback-triangle-very-wide",
        triangle(mediumTarget ? 1.18 : 1.28, 1571),
        1.14,
      );
    }
    addPlan("fallback-loop-3", loop(shortTarget ? 0.98 : 1.02, 3, 733), 1.08);
    addPlan("fallback-loop-4", loop(shortTarget ? 1.06 : 1.12, 4, 857), 1.12);
    if (!shortTarget) {
      addPlan(
        "fallback-loop-5",
        loop(mediumTarget ? 1.10 : 1.16, 4, 1093),
        1.14,
      );
    }
  }

  const dedupedPlans = dedupeRoundTripPlans(plans);
  if (!simplifyWaypoints) {
    return dedupedPlans;
  }

  const maxIntermediateWaypoints = Math.max(
    1,
    Math.min(4, maxWaypoints ?? 3),
  );
  const stableShortSportLoopLabels = [
    "sport-rheintal-west",
    "sport-compact-oval-southwest",
    "sport-offset-loop-north",
    "sport-loop-flow-west",
    "sport-loop-scout-southwest",
    "sport-cardinal-northwest",
    "sport-valley-safe-west",
    "fallback-rheintal-west",
    "fallback-compact-oval-north",
    "fallback-offset-loop-west",
    "fallback-loop-rheintal",
    "fallback-cardinal-west",
    "fallback-valley-safe-southwest",
  ];
  const simplifiedPreferred = dedupedPlans.filter((plan) => {
    const intermediateCount = Math.max(0, plan.waypoints.length - 2);
    if (intermediateCount > maxIntermediateWaypoints) return false;

    const label = plan.label.toLowerCase();
    if (avoidHighwaysShortSportSearch) {
      return stableShortSportLoopLabels.some((token) => label.includes(token));
    }
    const shortCurvyCompactPlan = mode === "Kurvenjagd" && shortTarget &&
      (
        label.includes("loop-scout") ||
        label.includes("orbital-core") ||
        label.includes("zigzag-core")
      );
    return (
      label.includes("triangle") ||
      label.includes("cardinal") ||
      label.includes("loop-3") ||
      (maxIntermediateWaypoints >= 4 && label.includes("loop-4")) ||
      shortCurvyCompactPlan
    );
  });
  if (simplifiedPreferred.length > 0) {
    return simplifiedPreferred;
  }

  const simplifiedPool = dedupedPlans.filter(
    (plan) =>
      Math.max(0, plan.waypoints.length - 2) <= maxIntermediateWaypoints,
  );
  return simplifiedPool.length > 0 ? simplifiedPool : dedupedPlans;
}
