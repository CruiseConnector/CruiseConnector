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
import { debugLog } from "./routing_debug.ts";

export function getDistanceConfig(
  targetDistance: number,
  mode?: string,
): DistanceConfig {
  // Erfolgsquote vor Perfektion: idealer Zielkorridor plus breiterer
  // akzeptabler Bereich. 50 / 75 / 100 km bewusst unterschiedlich
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

  debugLog(
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

/**
 * Generates 4 (or more) waypoints arranged as an orbital ring around the
 * start position. Unlike `calculatePairedLoopWaypoints` which places three
 * waypoints along a single axis (which tends to produce U-turn forced
 * routes when Mapbox has to backtrack), this generator spreads the
 * waypoints across a wide sweep (default 220°) so Mapbox can drive them
 * as a real round ring without reversing direction.
 *
 * The generator is fully deterministic (seeded) and supports asymmetric
 * distance factors per waypoint so the ring can be narrower on one side
 * (typical valley geometry, e.g. Dornbirn where the mountains to the
 * east are inaccessible without highways).
 */
function calculateOrbitalRingWaypoints(
  start: Coordinate,
  searchRadiusKm: number,
  corridorBearingDegrees: number,
  numWaypoints: number = 4,
  sweepDegrees: number = 220,
  seed?: number,
  options?: {
    distanceFactors?: number[];
    bearingJitterDegrees?: number;
    radialJitter?: number;
    smoothing?: number;
    minRadiusFactor?: number;
    maxRadiusFactor?: number;
  },
): Coordinate[] {
  const s = seed ?? Math.floor(Math.random() * 100000);
  const rng = (offset: number) => seededUnit(s + offset);
  const count = Math.max(3, Math.floor(numWaypoints));
  const sweep = Math.max(90, Math.min(300, sweepDegrees));
  const start3rd = sweep / (count - 1);
  const bearingJitterDegrees = options?.bearingJitterDegrees ?? 0;
  const radialJitter = options?.radialJitter ?? 0;
  const factors = options?.distanceFactors;

  const waypoints: Coordinate[] = [];
  for (let index = 0; index < count; index++) {
    const offsetFromCorridor = -sweep / 2 + start3rd * index;
    const bearing = corridorBearingDegrees + offsetFromCorridor +
      (rng(400 + index * 17) - 0.5) * bearingJitterDegrees;
    const factor = factors != null
      ? factors[index] ?? factors[factors.length - 1]
      : 1.0;
    const distanceVariation = 1 +
      (rng(401 + index * 17) - 0.5) * radialJitter;
    waypoints.push(
      calculateDestination(
        start,
        searchRadiusKm * factor * distanceVariation,
        bearing,
      ),
    );
  }

  return enforceWaypointRadiusBand(
    start,
    smoothWaypointChain(waypoints, options?.smoothing ?? 0.06),
    searchRadiusKm * (options?.minRadiusFactor ?? 0.84),
    searchRadiusKm * (options?.maxRadiusFactor ?? 1.24),
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
  zigzagWaypoints?: boolean;
  simplifyWaypoints?: boolean;
  maxWaypoints?: number;
  avoidHighways?: boolean;
}): RoundTripCandidatePlan[] {
  const plans: RoundTripCandidatePlan[] = [];
  const shortTarget = targetDistanceKm <= 60;
  const mediumTarget = targetDistanceKm > 60 && targetDistanceKm <= 110;
  const longTarget = targetDistanceKm > 110;
  const baseRadius = distanceConfig.radiusKm;
  const baseSnapRadius = distanceConfig.waypointRadiusMeters;
  const avoidHighwaysRoundTripSearch = avoidHighways;
  const noHighwayMediumTarget = targetDistanceKm > 60 &&
    targetDistanceKm <= 85;

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
  const zigzag = (multiplier: number, seedOffset: number) =>
    calculateZigZagWaypoints(
      start,
      baseRadius * multiplier,
      randomSeed + seedOffset,
      preferredBearingDegrees,
    );

  const pairedLoop = (
    multiplier: number,
    corridorBearingDegrees: number,
    seedOffset: number,
    spreadDegrees: number,
    distanceFactors: [number, number, number],
    options?: {
      bearingJitterDegrees?: number;
      radialJitter?: number;
      smoothing?: number;
      minRadiusFactor?: number;
      maxRadiusFactor?: number;
    },
  ) =>
    calculatePairedLoopWaypoints(
      start,
      baseRadius * multiplier,
      corridorBearingDegrees,
      randomSeed + seedOffset,
      {
        spreadDegrees,
        distanceFactors,
        bearingJitterDegrees: options?.bearingJitterDegrees ?? 5,
        radialJitter: options?.radialJitter ?? 0.045,
        smoothing: options?.smoothing ?? 0.08,
        minRadiusFactor: options?.minRadiusFactor ?? 0.86,
        maxRadiusFactor: options?.maxRadiusFactor ?? 1.26,
      },
    );

  const fixedBearingLoop = (
    bearings: number[],
    distancesKm: number[],
  ) =>
    bearings.map((bearing, index) =>
      calculateDestination(start, distancesKm[index] ?? distancesKm[0], bearing)
    );
  const orbitalRing = (
    multiplier: number,
    corridorBearingDegrees: number,
    seedOffset: number,
    numWaypoints: number,
    sweepDegrees: number,
    distanceFactors: number[],
    options?: {
      bearingJitterDegrees?: number;
      radialJitter?: number;
      smoothing?: number;
      minRadiusFactor?: number;
      maxRadiusFactor?: number;
    },
  ) =>
    calculateOrbitalRingWaypoints(
      start,
      baseRadius * multiplier,
      corridorBearingDegrees,
      numWaypoints,
      sweepDegrees,
      randomSeed + seedOffset,
      {
        distanceFactors,
        bearingJitterDegrees: options?.bearingJitterDegrees ?? 0,
        radialJitter: options?.radialJitter ?? 0,
        smoothing: options?.smoothing ?? 0.06,
        minRadiusFactor: options?.minRadiusFactor ?? 0.84,
        maxRadiusFactor: options?.maxRadiusFactor ?? 1.24,
      },
    );
  const longNoHighwayCurveRescue = () =>
    pairedLoop(
      targetDistanceKm >= 95 ? 1.74 : 1.58,
      58,
      2447,
      72,
      [1.04, 1.22, 1.06],
      {
        smoothing: 0.06,
        minRadiusFactor: 0.86,
        maxRadiusFactor: 1.32,
      },
    );

  if (avoidHighwaysRoundTripSearch) {
    const styleKey = mode === "Kurvenjagd"
      ? "curvy"
      : mode === "Entdecker"
      ? "explore"
      : mode === "Abendrunde"
      ? "evening"
      : "sport";
    const regionSeed = randomSeed +
      Math.round(start.latitude * 10) * 37 +
      Math.round(start.longitude * 10) * 53;
    const sectorOffsets = [-135, -90, -45, 0, 45, 90, 135, 180];
    const sectorRotation = Math.abs(Math.round(regionSeed)) %
      sectorOffsets.length;
    const baseBearing = seededBaseBearing(
      regionSeed,
      preferredBearingDegrees,
      preferredBearingDegrees === undefined ? 360 : 70,
    );
    const sectorBearings = sectorOffsets.map((_, index) =>
      normalizeBearingDegrees(
        baseBearing +
          sectorOffsets[(index + sectorRotation) % sectorOffsets.length],
      )
    );
    const compactMultiplier = shortTarget
      ? 1.02
      : noHighwayMediumTarget
      ? 1.08
      : 1.18;
    const wideMultiplier = shortTarget
      ? 1.16
      : noHighwayMediumTarget
      ? 1.20
      : 1.34;
    const isCurvy = styleKey === "curvy";
    const isSport = styleKey === "sport";
    sectorBearings.forEach((bearing, index) => {
      const sectorLabel = Math.round(bearing).toString().padStart(3, "0");
      addPlan(
        `nohw-sector-${styleKey}-${index}-${sectorLabel}-paired`,
        pairedLoop(
          compactMultiplier,
          bearing,
          3100 + index * 23,
          isCurvy ? 86 : isSport ? 58 : 72,
          isSport ? [0.98, 1.08, 0.98] : [0.94, 1.12, 0.96],
          {
            bearingJitterDegrees: isCurvy ? 7 : 3,
            radialJitter: isCurvy ? 0.05 : 0.025,
            smoothing: isSport ? 0.08 : 0.05,
            minRadiusFactor: shortTarget ? 0.76 : 0.80,
            maxRadiusFactor: longTarget ? 1.34 : 1.22,
          },
        ),
        isCurvy ? 1.16 : 1.10,
      );
      addPlan(
        `nohw-regional-${styleKey}-${index}-${sectorLabel}-ring`,
        orbitalRing(
          wideMultiplier,
          bearing,
          4100 + index * 29,
          isCurvy ? 5 : 4,
          isCurvy ? 245 : isSport ? 190 : 220,
          isCurvy
            ? [0.90, 1.04, 1.12, 1.02, 0.92]
            : isSport
            ? [0.88, 1.00, 1.02, 0.88]
            : [0.90, 1.04, 1.06, 0.92],
          {
            bearingJitterDegrees: isCurvy ? 10 : 4,
            radialJitter: isCurvy ? 0.06 : 0.03,
            smoothing: isSport ? 0.07 : 0.045,
            minRadiusFactor: shortTarget ? 0.72 : 0.78,
            maxRadiusFactor: longTarget ? 1.36 : 1.24,
          },
        ),
        isCurvy ? 1.18 : 1.12,
      );
    });

    if (shortTarget && mode === "Sport Mode") {
      addPlan(
        "sport-paired-west",
        pairedLoop(1.12, 280, 1901, 58, [1.00, 1.14, 1.00], {
          bearingJitterDegrees: 0,
          radialJitter: 0,
          smoothing: 0,
          minRadiusFactor: 0.88,
          maxRadiusFactor: 1.24,
        }),
        1.08,
      );
      addPlan(
        "sport-paired-northwest",
        pairedLoop(1.32, 304, 1907, 78, [1.00, 1.14, 1.00], {
          bearingJitterDegrees: 0,
          radialJitter: 0,
          smoothing: 0,
          minRadiusFactor: 0.88,
          maxRadiusFactor: 1.25,
        }),
        1.08,
      );
      addPlan(
        "sport-paired-southwest",
        pairedLoop(1.40, 292, 1913, 66, [1.00, 1.14, 1.00], {
          bearingJitterDegrees: 0,
          radialJitter: 0,
          smoothing: 0,
          minRadiusFactor: 0.88,
          maxRadiusFactor: 1.24,
        }),
        1.08,
      );
      addPlan(
        "sport-paired-west-wide",
        pairedLoop(1.12, 304, 1927, 82, [1.00, 1.14, 1.00], {
          bearingJitterDegrees: 0,
          radialJitter: 0,
          smoothing: 0,
          minRadiusFactor: 0.88,
          maxRadiusFactor: 1.26,
        }),
        1.12,
      );
      sectorBearings.slice(0, 4).forEach((bearing, index) => {
        addPlan(
          `sport-flow-regional-${index}`,
          pairedLoop(
            index % 2 === 0 ? 1.04 : 1.08,
            bearing,
            1960 + index * 17,
            52,
            [0.98, 1.06, 0.98],
            {
              bearingJitterDegrees: 2,
              radialJitter: 0.02,
              smoothing: 0.10,
              minRadiusFactor: 0.84,
              maxRadiusFactor: 1.16,
            },
          ),
          1.06,
        );
      });

      return dedupeRoundTripPlans(plans);
    }

    if (shortTarget) {
      addPlan(
        "nohw-short-curve-oval-west",
        pairedLoop(1.00, 280, 2201, 58, [1.00, 1.14, 1.00], {
          bearingJitterDegrees: 0,
          radialJitter: 0,
          smoothing: 0,
          minRadiusFactor: 0.86,
          maxRadiusFactor: 1.20,
        }),
        1.10,
      );
      addPlan(
        "nohw-short-curve-oval-northwest",
        pairedLoop(1.16, 304, 2211, 78, [1.00, 1.14, 1.00], {
          bearingJitterDegrees: 0,
          radialJitter: 0,
          smoothing: 0,
          minRadiusFactor: 0.86,
          maxRadiusFactor: 1.22,
        }),
        1.12,
      );
      addPlan(
        "nohw-short-curve-oval-southwest",
        pairedLoop(1.20, 304, 2221, 78, [1.00, 1.14, 1.00], {
          bearingJitterDegrees: 0,
          radialJitter: 0,
          smoothing: 0,
          minRadiusFactor: 0.86,
          maxRadiusFactor: 1.22,
        }),
        1.10,
      );

      return dedupeRoundTripPlans(plans);
    }

    if (noHighwayMediumTarget) {
      if (mode === "Sport Mode") {
        // 4-WP orbital ring families aimed at the FLAT Rhine valley
        // north of Dornbirn (Bregenz → Höchst → Lustenau → swiss
        // border). These corridors have straight B-roads without the
        // hairpin switchbacks of the Bregenzerwald so Mapbox does not
        // need to insert u-turn maneuvers. Corridor bearings are all
        // in the northern/western semicircle; eastern bearings would
        // drag the route up into the mountains.
        addPlan(
          "nohw-medium-sport-orbital-rheintal-north",
          orbitalRing(
            0.90,
            338,
            2301,
            4,
            215,
            [0.90, 1.02, 1.00, 0.88],
            {
              bearingJitterDegrees: 0,
              radialJitter: 0,
              smoothing: 0.04,
              minRadiusFactor: 0.72,
              maxRadiusFactor: 1.12,
            },
          ),
          1.08,
        );
        addPlan(
          "nohw-medium-sport-orbital-rheintal-northwest",
          orbitalRing(
            0.92,
            322,
            2321,
            4,
            220,
            [0.92, 1.02, 0.98, 0.88],
            {
              bearingJitterDegrees: 0,
              radialJitter: 0,
              smoothing: 0.04,
              minRadiusFactor: 0.72,
              maxRadiusFactor: 1.12,
            },
          ),
          1.08,
        );
        addPlan(
          "nohw-medium-sport-orbital-rheintal-west",
          orbitalRing(
            0.90,
            302,
            2335,
            4,
            228,
            [0.94, 1.00, 0.96, 0.90],
            {
              bearingJitterDegrees: 0,
              radialJitter: 0,
              smoothing: 0.04,
              minRadiusFactor: 0.72,
              maxRadiusFactor: 1.10,
            },
          ),
          1.06,
        );
        addPlan(
          "nohw-medium-sport-orbital-6soft",
          orbitalRing(
            0.84,
            314,
            2338,
            6,
            200,
            [0.94, 0.98, 1.0, 0.98, 0.96, 0.92],
            {
              bearingJitterDegrees: 0,
              radialJitter: 0,
              smoothing: 0.04,
              minRadiusFactor: 0.70,
              maxRadiusFactor: 1.10,
            },
          ),
          1.08,
        );
        addPlan(
          "nohw-medium-sport-orbital-broad-west",
          orbitalRing(
            0.88,
            308,
            2340,
            4,
            235,
            [0.96, 0.99, 0.96, 0.94],
            {
              bearingJitterDegrees: 0,
              radialJitter: 0,
              smoothing: 0.05,
              minRadiusFactor: 0.72,
              maxRadiusFactor: 1.12,
            },
          ),
          1.10,
        );
        addPlan(
          "nohw-medium-sport-orbital-rheintal-loop",
          orbitalRing(
            0.88,
            328,
            2345,
            5,
            215,
            [0.88, 0.98, 1.02, 0.98, 0.86],
            {
              bearingJitterDegrees: 0,
              radialJitter: 0,
              smoothing: 0.04,
              minRadiusFactor: 0.70,
              maxRadiusFactor: 1.14,
            },
          ),
          1.10,
        );
        addPlan(
          "nohw-medium-sport-cardinal-rheintal",
          cardinal(0.94, 2361, 1.08),
          1.08,
        );
        return dedupeRoundTripPlans(plans);
      }
      addPlan(
        "nohw-medium-oval-west",
        pairedLoop(1.30, 260, 2301, 50, [1.00, 1.00, 1.00], {
          bearingJitterDegrees: 0,
          radialJitter: 0,
          smoothing: 0,
          minRadiusFactor: 0.84,
          maxRadiusFactor: 1.26,
        }),
        1.10,
      );
      addPlan(
        "nohw-medium-rhine-south",
        fixedBearingLoop(
          [178, 220, 262],
          [17.2, 17.2, 17.2],
        ),
        1.06,
      );
      addPlan(
        "nohw-medium-oval-northwest",
        pairedLoop(1.30, 260, 2311, 50, [1.00, 1.00, 1.00], {
          bearingJitterDegrees: 0,
          radialJitter: 0,
          smoothing: 0,
          minRadiusFactor: 0.84,
          maxRadiusFactor: 1.26,
        }),
        1.12,
      );
      addPlan(
        "nohw-medium-oval-southwest",
        pairedLoop(1.24, 236, 2321, 56, [1.00, 1.14, 1.00], {
          bearingJitterDegrees: 0,
          radialJitter: 0,
          smoothing: 0,
          minRadiusFactor: 0.84,
          maxRadiusFactor: 1.24,
        }),
        1.12,
      );
      if (mode === "Kurvenjagd" && targetDistanceKm >= 75) {
        addPlan(
          "nohw-curve-rescue-northeast",
          longNoHighwayCurveRescue(),
          1.14,
        );
      }

      return dedupeRoundTripPlans(plans);
    }

    addPlan(
      "nohw-long-oval-west",
      pairedLoop(1.42, 280, 2401, 58, [1.04, 1.18, 1.04], {
        smoothing: 0.06,
        minRadiusFactor: 0.86,
        maxRadiusFactor: 1.28,
      }),
      1.12,
    );
    addPlan(
      "nohw-long-oval-northwest",
      pairedLoop(1.46, 304, 2411, 68, [1.02, 1.20, 1.04], {
        smoothing: 0.06,
        minRadiusFactor: 0.86,
        maxRadiusFactor: 1.30,
      }),
      1.14,
    );
    addPlan(
      "nohw-long-oval-southwest",
      pairedLoop(1.44, 236, 2421, 62, [1.02, 1.18, 1.04], {
        smoothing: 0.06,
        minRadiusFactor: 0.86,
        maxRadiusFactor: 1.28,
      }),
      1.14,
    );
    addPlan(
      "nohw-long-oval-west-wide",
      pairedLoop(1.52, 286, 2431, 72, [1.00, 1.22, 1.04], {
        smoothing: 0.06,
        minRadiusFactor: 0.86,
        maxRadiusFactor: 1.32,
      }),
      1.16,
    );
    if (mode === "Kurvenjagd" && targetDistanceKm >= 75) {
      addPlan(
        "nohw-curve-rescue-northeast",
        longNoHighwayCurveRescue(),
        1.16,
      );
    }

    return dedupeRoundTripPlans(plans);
  }

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
      if (shortTarget) {
        // Highway short Sport: try loop/cardinal before orbitals so strict-phase
        // slices (first N candidates) hit Mapbox-friendly shapes even if sort
        // ties fall back to insertion order.
        addPlan(
          "sport-loop-flow",
          loop(1.10, 3, 29),
          1.0,
        );
        addPlan(
          "sport-loop-wide",
          loop(1.14, 3, 173),
          1.12,
        );
        addPlan(
          "sport-cardinal-ellipse",
          cardinal(1.04, 59, waypointShapeFactor ?? 2.0),
          1.02,
        );
        addPlan(
          "sport-hw-zigzag-rheintal",
          zigzag(1.02, 2517),
          1.06,
        );
        // 4–5 WP orbital rings + last-resort 3-WP corridor.
        addPlan(
          "sport-hw-orbital-rheintal-north",
          orbitalRing(
            0.92,
            340,
            1901,
            4,
            170,
            [0.92, 1.02, 1.00, 0.88],
            {
              bearingJitterDegrees: 0,
              radialJitter: 0,
              smoothing: 0.04,
              minRadiusFactor: 0.74,
              maxRadiusFactor: 1.14,
            },
          ),
          1.10,
        );
        addPlan(
          "sport-hw-orbital-rheintal-northwest",
          orbitalRing(
            0.96,
            320,
            1911,
            4,
            160,
            [0.90, 1.00, 1.02, 0.88],
            {
              bearingJitterDegrees: 0,
              radialJitter: 0,
              smoothing: 0.04,
              minRadiusFactor: 0.74,
              maxRadiusFactor: 1.16,
            },
          ),
          1.10,
        );
        addPlan(
          "sport-hw-orbital-rheintal-west",
          orbitalRing(
            1.02,
            304,
            1921,
            4,
            220,
            [0.96, 1.04, 1.00, 0.92],
            {
              bearingJitterDegrees: 0,
              radialJitter: 0,
              smoothing: 0.04,
              minRadiusFactor: 0.76,
              maxRadiusFactor: 1.16,
            },
          ),
          1.10,
        );
        addPlan(
          "sport-hw-orbital-equal-sweep",
          orbitalRing(
            1.04,
            316,
            1931,
            4,
            235,
            [1.0, 1.0, 1.0, 1.0],
            {
              bearingJitterDegrees: 0,
              radialJitter: 0,
              smoothing: 0.05,
              minRadiusFactor: 0.78,
              maxRadiusFactor: 1.18,
            },
          ),
          1.12,
        );
        addPlan(
          "sport-hw-orbital-soft-5",
          orbitalRing(
            0.96,
            312,
            1941,
            5,
            200,
            [0.92, 0.98, 1.02, 1.0, 0.90],
            {
              bearingJitterDegrees: 0,
              radialJitter: 0,
              smoothing: 0.04,
              minRadiusFactor: 0.74,
              maxRadiusFactor: 1.16,
            },
          ),
          1.12,
        );
        addPlan(
          "sport-hw-cardinal-rheintal",
          cardinal(1.00, 1951, 1.10),
          1.06,
        );
        // Last-resort 3-WP corridor (paired): often rejected, but improves
        // NO_ROUTE rate when orbitals/loops fail a seed batch.
        addPlan(
          "sport-paired-hw-corridor",
          pairedLoop(1.12, 292, 1961, 52, [1.00, 1.08, 1.00], {
            bearingJitterDegrees: 0,
            radialJitter: 0,
            smoothing: 0,
            minRadiusFactor: 0.88,
            maxRadiusFactor: 1.22,
          }),
          1.08,
        );
      }
      if (!shortTarget) {
        addPlan(
          "sport-cardinal-ellipse",
          cardinal(1.04, 59, waypointShapeFactor ?? 2.0),
          1.02,
        );
        addPlan("sport-loop-flow", loop(1.10, 4, 29), 1.0);
        addPlan(
          "sport-loop-wide",
          loop(longTarget ? 1.22 : 1.14, mediumTarget ? 4 : 3, 173),
          1.12,
        );
      }
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

  const dedupedPlans = dedupeRoundTripPlans(plans);
  if (!simplifyWaypoints) {
    return dedupedPlans;
  }

  // Allow up to 5 intermediate waypoints so the new orbital-ring
  // families can survive the simplify filter when the client asks for
  // simplified waypoints (rescue passes in the route service).
  const maxIntermediateWaypoints = Math.max(
    1,
    Math.min(5, maxWaypoints ?? 5),
  );
  const simplifiedPreferred = dedupedPlans.filter((plan) => {
    const intermediateCount = Math.max(0, plan.waypoints.length - 2);
    const label = plan.label.toLowerCase();
    const shortSportPairedPlan = mode === "Sport Mode" && shortTarget &&
      label.includes("sport-paired-");
    const sportOrbitalPlan = mode === "Sport Mode" &&
      (
        label.includes("sport-hw-orbital-") ||
        label.includes("sport-hw-cardinal-") ||
        label.includes("nohw-medium-sport-orbital-") ||
        label.includes("nohw-medium-sport-orbital-rheintal-") ||
        label.includes("nohw-medium-sport-cardinal-")
      );
    // Orbital plans must survive the rescue pass even when the client
    // asks for simplifyWaypoints (maxWaypoints=3). The whole point of
    // the orbital families is to carry 4–5 waypoints — if we drop them
    // here, the rescue falls back to triangles and u-turn rejects.
    const orbitalWaypointsOk = sportOrbitalPlan &&
      intermediateCount <= 5;
    if (!orbitalWaypointsOk && intermediateCount > maxIntermediateWaypoints) {
      return false;
    }
    const shortCurvyCompactPlan = mode === "Kurvenjagd" && shortTarget &&
      (
        label.includes("loop-scout") ||
        label.includes("orbital-core") ||
        label.includes("zigzag-core")
      );
    const shortSportLoopCore = mode === "Sport Mode" && shortTarget &&
      (
        label.includes("sport-loop-flow") ||
        label.includes("sport-loop-wide")
      );
    return (
      label.includes("triangle") ||
      label.includes("cardinal") ||
      label.includes("loop-3") ||
      shortSportPairedPlan ||
      sportOrbitalPlan ||
      shortSportLoopCore ||
      (mode === "Sport Mode" && shortTarget && label.includes("zigzag")) ||
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
