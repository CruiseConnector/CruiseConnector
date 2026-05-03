import type {
  Coordinate,
  DistanceConfig,
  RouteCleanupEvaluation,
  RouteMode,
  RouteQualityEvaluation,
  RouteQualityTier,
  RouteShapeMetrics,
  RouteStyleMetrics,
} from "./routing_types.ts";
import {
  calculateBearing,
  calculateDistance,
  countCenterReentries,
  countMajorDistancePeaks,
  estimateMiddleCoverageRatio,
  headingDeltaDegrees,
  measureCoordinatePathMeters,
  pointToCoordinate,
  routeHeadingAt,
  smoothDistanceSeries,
  stableStringHash,
} from "./routing_utils.ts";
import { getRouteDistanceKm } from "./point_to_point.ts";
import { debugLog } from "./routing_debug.ts";

export function countUTurnManeuvers(route: any): number {
  const legs = route?.legs;
  if (!Array.isArray(legs)) return 0;

  let count = 0;
  for (const leg of legs) {
    const steps = leg?.steps;
    if (!Array.isArray(steps)) continue;

    for (const step of steps) {
      const maneuver = step?.maneuver ?? {};
      const modifier = String(maneuver?.modifier ?? "").toLowerCase();
      const type = String(maneuver?.type ?? "").toLowerCase();
      const instruction = String(maneuver?.instruction ?? "").toLowerCase();

      if (
        modifier.includes("uturn") ||
        modifier.includes("u-turn") ||
        type === "uturn" ||
        type === "u-turn" ||
        instruction.includes("wenden") ||
        instruction.includes("u-turn")
      ) {
        count += 1;
      }
    }
  }
  return count;
}

/**
 * Prüft ob eine Route explizite Wendemanöver enthält.
 */
export function hasUTurnManeuver(route: any): boolean {
  const legs = route?.legs;
  if (!Array.isArray(legs)) return false;

  for (const leg of legs) {
    const steps = leg?.steps;
    if (!Array.isArray(steps)) continue;

    for (const step of steps) {
      const maneuver = step?.maneuver ?? {};
      const modifier = String(maneuver?.modifier ?? "").toLowerCase();
      const type = String(maneuver?.type ?? "").toLowerCase();
      const instruction = String(maneuver?.instruction ?? "").toLowerCase();

      if (
        modifier.includes("uturn") ||
        modifier.includes("u-turn") ||
        type === "uturn" ||
        type === "u-turn" ||
        instruction.includes("wenden") ||
        instruction.includes("u-turn")
      ) {
        return true;
      }
    }
  }
  return false;
}

function calculateRouteOverlapPercent(route: any): number {
  const coordinates = route?.geometry?.coordinates;
  if (!Array.isArray(coordinates) || coordinates.length < 25) {
    return 0;
  }

  const sampleStep = 4;
  const minIndexGap = 30;
  const overlapDistanceMeters = 45;
  let sampleCount = 0;
  let overlapCount = 0;

  for (let i = 0; i < coordinates.length; i += sampleStep) {
    const current = pointToCoordinate(coordinates[i]);
    if (!current) continue;

    sampleCount += 1;
    const headingI = routeHeadingAt(coordinates, i);
    let foundOverlap = false;

    for (let j = i + minIndexGap; j < coordinates.length; j += sampleStep) {
      const candidate = pointToCoordinate(coordinates[j]);
      if (!candidate) continue;

      const distanceMeters = calculateDistance(current, candidate) * 1000;
      if (distanceMeters >= overlapDistanceMeters) continue;

      const headingJ = routeHeadingAt(coordinates, j);
      const headingDelta = headingDeltaDegrees(headingI, headingJ);
      const sameDirection = headingDelta <= 35;
      const oppositeDirection = headingDelta >= 145;

      if (sameDirection || oppositeDirection) {
        foundOverlap = true;
        break;
      }
    }

    if (foundOverlap) {
      overlapCount += 1;
    }
  }

  if (sampleCount === 0) return 0;
  return (overlapCount / sampleCount) * 100;
}

function extractRouteCoordinates(route: any): Coordinate[] {
  const raw = route?.geometry?.coordinates;
  if (!Array.isArray(raw)) return [];
  const result: Coordinate[] = [];
  for (const point of raw) {
    const parsed = pointToCoordinate(point);
    if (parsed) result.push(parsed);
  }
  return result;
}

function sampleCoordinates(
  coordinates: Coordinate[],
  sampleCount: number,
): Coordinate[] {
  if (coordinates.length === 0) return [];
  const effectiveSamples = Math.max(
    2,
    Math.min(sampleCount, coordinates.length),
  );
  const samples: Coordinate[] = [];
  for (let i = 0; i < effectiveSamples; i += 1) {
    const ratio = effectiveSamples === 1 ? 0 : i / (effectiveSamples - 1);
    const index = Math.round((coordinates.length - 1) * ratio);
    samples.push(coordinates[index]);
  }
  return samples;
}

export function buildRouteFingerprint(
  coordinates: Coordinate[],
  options?: {
    distanceKm?: number;
    sampleCount?: number;
    precision?: number;
  },
): string {
  if (coordinates.length === 0) {
    return "empty";
  }

  const precision = Math.max(0, options?.precision ?? 4);
  const parts: string[] = [
    `n:${coordinates.length}`,
  ];
  if (
    typeof options?.distanceKm === "number" &&
    Number.isFinite(options.distanceKm)
  ) {
    parts.push(`d:${options.distanceKm.toFixed(1)}`);
  }

  for (
    const point of sampleCoordinates(
      coordinates,
      options?.sampleCount ?? 10,
    )
  ) {
    parts.push(
      `${point.longitude.toFixed(precision)},${
        point.latitude.toFixed(precision)
      }`,
    );
  }
  return parts.join("|");
}

export function buildRouteFingerprintFromRoute(route: any): string {
  const coordinates = extractRouteCoordinates(route);
  return buildRouteFingerprint(coordinates, {
    distanceKm: getRouteDistanceKm(route),
  });
}

export function hashCoordinates(
  coordinates: Coordinate[],
  distanceKm?: number,
): string {
  return stableStringHash(
    buildRouteFingerprint(coordinates, { distanceKm }),
  ).toString(16);
}

export interface RouteLoopCleanupResult extends RouteCleanupEvaluation {
  coordinates: Coordinate[];
  startTrimApplied: boolean;
  startTrimRejected: boolean;
  loopRemovalApplied: boolean;
  loopRemovalRejected: boolean;
  loopRemovedPercent: number;
  revertedLoopRemoval: boolean;
}

export function cleanupLoopAndCollapse(
  coordinates: Coordinate[],
  originalDistanceMeters?: number,
  startCoordinate?: Coordinate,
): RouteLoopCleanupResult {
  if (coordinates.length < 2) {
    const cleanedDistanceKm = measureCoordinatePathMeters(coordinates) / 1000;
    return {
      passed: true,
      reason: "cleanup_not_needed",
      coordinates,
      removedPointPercent: 0,
      distanceRetentionRatio: 1,
      removedLoops: 0,
      cleanedDistanceKm,
      cleanedGeometricUTurnCount: countGeometricUTurns(coordinates),
      fingerprint: hashCoordinates(coordinates, cleanedDistanceKm),
      startTrimApplied: false,
      startTrimRejected: false,
      loopRemovalApplied: false,
      loopRemovalRejected: false,
      loopRemovedPercent: 0,
      revertedLoopRemoval: false,
    };
  }

  const baselineDistanceMeters = originalDistanceMeters != null &&
      Number.isFinite(originalDistanceMeters) && originalDistanceMeters > 0
    ? originalDistanceMeters
    : measureCoordinatePathMeters(coordinates);
  let cleaned = coordinates.slice();
  const cleanupStart = startCoordinate ?? cleaned[0];

  const searchEnd = Math.max(
    5,
    Math.min(200, Math.round(cleaned.length * 0.20)),
  );
  let maxStartDistanceMeters = 0;
  let maxDistanceIndex = 0;
  for (let i = 0; i < searchEnd; i += 1) {
    const distanceMeters = calculateDistance(cleanupStart, cleaned[i]) * 1000;
    if (distanceMeters > maxStartDistanceMeters) {
      maxStartDistanceMeters = distanceMeters;
      maxDistanceIndex = i;
    }
  }

  let trimTo = 0;
  if (maxStartDistanceMeters > 100) {
    for (let i = maxDistanceIndex; i < searchEnd; i += 1) {
      const distanceMeters = calculateDistance(cleanupStart, cleaned[i]) * 1000;
      if (distanceMeters < 80) {
        trimTo = i;
      }
    }
  } else {
    for (let i = 1; i < searchEnd; i += 1) {
      const distanceMeters = calculateDistance(cleanupStart, cleaned[i]) * 1000;
      if (distanceMeters < 35) {
        trimTo = i;
      }
    }
  }

  let startTrimApplied = false;
  let startTrimRejected = false;
  if (trimTo > 0) {
    const trimmed = cleaned.slice(trimTo);
    const trimmedDistanceMeters = measureCoordinatePathMeters(trimmed);
    const trimmedRatio = baselineDistanceMeters > 0
      ? trimmedDistanceMeters / baselineDistanceMeters
      : 1;
    const removedPointRatio = trimTo / cleaned.length;
    if (trimmedRatio >= 0.72 || removedPointRatio <= 0.08) {
      cleaned = trimmed;
      startTrimApplied = true;
    } else {
      startTrimRejected = true;
    }
  }

  const beforeLoopCleanup = cleaned.slice();
  const beforeLoopCount = cleaned.length;
  const loopResult = removeClientStyleLocalLoops(cleaned);
  const loopRemovedPercent = beforeLoopCount > 0
    ? Math.max(0, 1 - loopResult.coordinates.length / beforeLoopCount) * 100
    : 0;
  let loopRemovalApplied = false;
  let loopRemovalRejected = false;
  if (loopRemovedPercent <= 30) {
    cleaned = loopResult.coordinates;
    loopRemovalApplied = loopResult.removedLoops > 0;
  } else if (loopResult.removedLoops > 0) {
    loopRemovalRejected = true;
  }

  let cleanedDistanceMeters = measureCoordinatePathMeters(cleaned);
  let revertedLoopRemoval = false;
  if (
    baselineDistanceMeters > 10000 &&
    baselineDistanceMeters > 0 &&
    cleanedDistanceMeters / baselineDistanceMeters < 0.78
  ) {
    cleaned = beforeLoopCleanup;
    cleanedDistanceMeters = measureCoordinatePathMeters(cleaned);
    revertedLoopRemoval = true;
    loopRemovalApplied = false;
  }

  const cleanedDistanceKm = cleanedDistanceMeters / 1000;
  return {
    passed: true,
    reason: "cleanup_ok",
    coordinates: cleaned,
    removedPointPercent: coordinates.length > 0
      ? Math.max(0, 1 - cleaned.length / coordinates.length) * 100
      : 0,
    distanceRetentionRatio: baselineDistanceMeters > 0
      ? cleanedDistanceMeters / baselineDistanceMeters
      : 1,
    removedLoops: loopRemovalApplied ? loopResult.removedLoops : 0,
    cleanedDistanceKm,
    cleanedGeometricUTurnCount: countGeometricUTurns(cleaned),
    fingerprint: hashCoordinates(cleaned, cleanedDistanceKm),
    startTrimApplied,
    startTrimRejected,
    loopRemovalApplied,
    loopRemovalRejected,
    loopRemovedPercent,
    revertedLoopRemoval,
  };
}

export function hasFoldLoop(
  reason: string,
  cleanup?: Pick<
    RouteCleanupEvaluation,
    "removedPointPercent" | "distanceRetentionRatio"
  >,
): boolean {
  return reason.startsWith("shape=") ||
    reason.startsWith("short_sport_shape=") ||
    reason.startsWith("center_return=") ||
    (
      cleanup != null &&
      cleanup.removedPointPercent > 18 &&
      cleanup.distanceRetentionRatio < 0.84
    );
}

function cloneRouteWithCoordinates(
  route: any,
  coordinates: Coordinate[],
  distanceKm: number,
): any {
  const nextGeometry = {
    ...(route?.geometry ?? {}),
    coordinates: coordinates.map((point) => [point.longitude, point.latitude]),
  };
  return {
    ...(route ?? {}),
    distance: distanceKm * 1000,
    geometry: nextGeometry,
  };
}

function countGeometricUTurns(coordinates: Coordinate[]): number {
  if (coordinates.length < 10) return 0;
  let count = 0;
  for (let i = 2; i < coordinates.length - 2; i += 1) {
    const prev = coordinates[i - 2];
    const current = coordinates[i];
    const next = coordinates[i + 2];
    const chordDistanceMeters = calculateDistance(prev, next) * 1000;
    if (chordDistanceMeters > 300) continue;

    const before = calculateBearing(prev, current);
    const after = calculateBearing(current, next);
    const delta = headingDeltaDegrees(before, after);
    if (delta > 140) {
      count += 1;
      i += 10;
    }
  }
  return count;
}

function removeClientStyleLocalLoops(coordinates: Coordinate[]): {
  coordinates: Coordinate[];
  removedLoops: number;
} {
  if (coordinates.length < 10) {
    return { coordinates, removedLoops: 0 };
  }

  const cumulative: number[] = [0];
  for (let i = 1; i < coordinates.length; i += 1) {
    cumulative.push(
      cumulative[cumulative.length - 1] +
        calculateDistance(coordinates[i - 1], coordinates[i]) * 1000,
    );
  }

  const safeEnd = Math.max(
    10,
    Math.min(coordinates.length, Math.round(coordinates.length * 0.85)),
  );
  for (let i = 10; i < safeEnd; i += 1) {
    const lookBack = Math.max(0, i - 300);
    for (let j = lookBack; j < i - 8; j += 1) {
      const directDistanceMeters = calculateDistance(
        coordinates[i],
        coordinates[j],
      ) * 1000;
      if (directDistanceMeters > 60) continue;

      const pathLengthMeters = cumulative[i] - cumulative[j];
      if (pathLengthMeters < directDistanceMeters * 4) continue;
      if (pathLengthMeters > 1200) continue;

      const shortened = coordinates.slice(0, j + 1).concat(
        coordinates.slice(i),
      );
      const next = removeClientStyleLocalLoops(shortened);
      return {
        coordinates: next.coordinates,
        removedLoops: next.removedLoops + 1,
      };
    }
  }

  return { coordinates, removedLoops: 0 };
}

function estimateClientLoopCleanupImpact(coordinates: Coordinate[]): {
  removedPointPercent: number;
  distanceRetentionRatio: number;
  removedLoops: number;
  cleanedDistanceKm: number;
  cleanedGeometricUTurnCount: number;
} {
  if (coordinates.length < 10) {
    return {
      removedPointPercent: 0,
      distanceRetentionRatio: 1,
      removedLoops: 0,
      cleanedDistanceKm: measureCoordinatePathMeters(coordinates) / 1000,
      cleanedGeometricUTurnCount: 0,
    };
  }

  const originalDistanceMeters = measureCoordinatePathMeters(coordinates);
  let cleaned = coordinates.slice();
  const start = cleaned[0];
  const searchEnd = Math.max(
    5,
    Math.min(200, Math.round(cleaned.length * 0.20)),
  );
  let maxStartDistanceMeters = 0;
  let maxDistanceIndex = 0;
  for (let i = 0; i < searchEnd; i += 1) {
    const distanceMeters = calculateDistance(start, cleaned[i]) * 1000;
    if (distanceMeters > maxStartDistanceMeters) {
      maxStartDistanceMeters = distanceMeters;
      maxDistanceIndex = i;
    }
  }

  let trimTo = 0;
  if (maxStartDistanceMeters > 100) {
    for (let i = maxDistanceIndex; i < searchEnd; i += 1) {
      const distanceMeters = calculateDistance(start, cleaned[i]) * 1000;
      if (distanceMeters < 80) {
        trimTo = i;
      }
    }
  } else {
    for (let i = 1; i < searchEnd; i += 1) {
      const distanceMeters = calculateDistance(start, cleaned[i]) * 1000;
      if (distanceMeters < 35) {
        trimTo = i;
      }
    }
  }

  if (trimTo > 0) {
    const trimmed = cleaned.slice(trimTo);
    const trimmedDistanceMeters = measureCoordinatePathMeters(trimmed);
    const trimmedRatio = originalDistanceMeters > 0
      ? trimmedDistanceMeters / originalDistanceMeters
      : 1;
    const removedPointRatio = trimTo / cleaned.length;
    if (trimmedRatio >= 0.72 || removedPointRatio <= 0.08) {
      cleaned = trimmed;
    }
  }

  const beforeLoopCount = cleaned.length;
  const loopResult = removeClientStyleLocalLoops(cleaned);
  const removedLoopPercent = beforeLoopCount > 0
    ? 1 - loopResult.coordinates.length / beforeLoopCount
    : 0;
  if (removedLoopPercent <= 0.30) {
    cleaned = loopResult.coordinates;
  }

  const cleanedDistanceMeters = measureCoordinatePathMeters(cleaned);
  return {
    removedPointPercent: coordinates.length > 0
      ? Math.max(0, 1 - cleaned.length / coordinates.length) * 100
      : 0,
    distanceRetentionRatio: originalDistanceMeters > 0
      ? cleanedDistanceMeters / originalDistanceMeters
      : 1,
    removedLoops: loopResult.removedLoops,
    cleanedDistanceKm: cleanedDistanceMeters / 1000,
    cleanedGeometricUTurnCount: countGeometricUTurns(cleaned),
  };
}

function calculateRouteShapeSignals(route: any): {
  angularRoughness: number;
  sharpTurnRate: number;
  hookCount: number;
  centralReturnPercent: number;
  centerReentryCount: number;
  radialPeakCount: number;
  middleCoverageRatio: number;
  geometricUTurnCount: number;
  oppositeOverlapPercent: number;
  foldedLoopPenalty: number;
  repeatedStartAreaPercent: number;
  spurArmPercent: number;
  loopCleanupRemovedPercent: number;
  loopCleanupDistanceRetentionRatio: number;
  loopCleanupCount: number;
  loopCleanupDistanceKm: number;
  loopCleanupUTurnCount: number;
} {
  const coordinates = extractRouteCoordinates(route);
  if (coordinates.length < 12) {
    return {
      angularRoughness: 0,
      sharpTurnRate: 0,
      hookCount: 0,
      centralReturnPercent: 0,
      centerReentryCount: 0,
      radialPeakCount: 0,
      middleCoverageRatio: 0,
      geometricUTurnCount: 0,
      oppositeOverlapPercent: 0,
      foldedLoopPenalty: 0,
      repeatedStartAreaPercent: 0,
      spurArmPercent: 0,
      loopCleanupRemovedPercent: 0,
      loopCleanupDistanceRetentionRatio: 1,
      loopCleanupCount: 0,
      loopCleanupDistanceKm: 0,
      loopCleanupUTurnCount: 0,
    };
  }

  const sampleStep = 5;
  const start = coordinates[0];
  const centralRadiusMeters = Math.max(
    140,
    Math.min(1300, (getRouteDistanceKm(route) * 1000) * 0.022),
  );
  const centralStartIndex = Math.floor(coordinates.length * 0.14);
  const centralEndIndex = Math.ceil(coordinates.length * 0.84);

  let centralSamples = 0;
  let centralHits = 0;
  let totalTurnSamples = 0;
  let turnDeltaSum = 0;
  let sharpTurnCount = 0;
  let hookCount = 0;

  for (
    let i = sampleStep;
    i < coordinates.length - sampleStep;
    i += sampleStep
  ) {
    const prev = coordinates[i - sampleStep];
    const current = coordinates[i];
    const next = coordinates[i + sampleStep];

    const headingIn = calculateBearing(prev, current);
    const headingOut = calculateBearing(current, next);
    const delta = headingDeltaDegrees(headingIn, headingOut);
    totalTurnSamples += 1;
    turnDeltaSum += delta;
    if (delta >= 78) sharpTurnCount += 1;

    const segmentInKm = calculateDistance(prev, current);
    const segmentOutKm = calculateDistance(current, next);
    if (
      delta >= 132 &&
      segmentInKm <= 0.24 &&
      segmentOutKm <= 0.24
    ) {
      hookCount += 1;
    }

    if (i >= centralStartIndex && i <= centralEndIndex) {
      centralSamples += 1;
      const distanceToStartMeters = calculateDistance(start, current) * 1000;
      if (distanceToStartMeters <= centralRadiusMeters) {
        centralHits += 1;
      }
    }
  }

  const angularRoughness = totalTurnSamples > 0
    ? turnDeltaSum / totalTurnSamples
    : 0;
  const sharpTurnRate = totalTurnSamples > 0
    ? (sharpTurnCount / totalTurnSamples) * 100
    : 0;
  const centralReturnPercent = centralSamples > 0
    ? (centralHits / centralSamples) * 100
    : 0;
  const profileSampleStep = Math.max(
    sampleStep * 4,
    Math.floor(coordinates.length / 24),
  );
  const sampledStartDistances: number[] = [];
  for (let i = 0; i < coordinates.length; i += profileSampleStep) {
    sampledStartDistances.push(calculateDistance(start, coordinates[i]) * 1000);
  }
  if (coordinates.length > 1) {
    sampledStartDistances.push(
      calculateDistance(start, coordinates[coordinates.length - 1]) * 1000,
    );
  }
  const maxStartDistance = sampledStartDistances.reduce(
    (maxValue, value) => Math.max(maxValue, value),
    0,
  );
  const smoothedDistances = smoothDistanceSeries(sampledStartDistances);
  const centerReentryCount = maxStartDistance <= 0 ? 0 : countCenterReentries(
    smoothedDistances,
    Math.max(420, Math.min(1700, maxStartDistance * 0.24)),
  );
  const radialPeakCount = maxStartDistance <= 0 ? 0 : Math.max(
    0,
    countMajorDistancePeaks(
      smoothedDistances,
      maxStartDistance * 0.78,
    ) - 1,
  );
  const middleCoverageRatio = estimateMiddleCoverageRatio(
    smoothedDistances,
    maxStartDistance,
  );
  const repeatedStartAreaPercent = Math.min(
    100,
    Math.max(0, (centerReentryCount / 2.5) * 100),
  );
  const spurArmPercent = Math.min(
    100,
    Math.max(0, (Math.max(0, radialPeakCount - 1) / 3) * 100),
  );
  const geometricUTurnCount = countGeometricUTurns(coordinates);

  const oppositeSampleStep = Math.max(5, Math.floor(coordinates.length / 180));
  const oppositeMinIndexGap = Math.max(
    30,
    Math.floor(coordinates.length * 0.035),
  );
  let oppositeSamples = 0;
  let oppositeHits = 0;
  for (let i = 0; i < coordinates.length - 1; i += oppositeSampleStep) {
    oppositeSamples += 1;
    const current = coordinates[i];
    const headingI = calculateBearing(
      current,
      coordinates[Math.min(i + 1, coordinates.length - 1)],
    );
    let hasOppositeCorridor = false;
    for (
      let j = i + oppositeMinIndexGap;
      j < coordinates.length - 1;
      j += oppositeSampleStep
    ) {
      const candidate = coordinates[j];
      const distanceMeters = calculateDistance(current, candidate) * 1000;
      if (distanceMeters > 65) continue;

      const headingJ = calculateBearing(candidate, coordinates[j + 1]);
      if (headingDeltaDegrees(headingI, headingJ) >= 140) {
        hasOppositeCorridor = true;
        break;
      }
    }
    if (hasOppositeCorridor) {
      oppositeHits += 1;
    }
  }
  const oppositeOverlapPercent = oppositeSamples > 0
    ? (oppositeHits / oppositeSamples) * 100
    : 0;
  const foldedLoopPenalty = Math.min(
    100,
    geometricUTurnCount * 26 +
      oppositeOverlapPercent * 1.45 +
      repeatedStartAreaPercent * 0.28 +
      spurArmPercent * 0.34 +
      Math.max(0, 0.40 - middleCoverageRatio) * 120 +
      Math.max(0, centralReturnPercent - 12) * 0.9 +
      Math.max(0, centerReentryCount - 1) * 10,
  );
  return {
    angularRoughness,
    sharpTurnRate,
    hookCount,
    centralReturnPercent,
    centerReentryCount,
    radialPeakCount,
    middleCoverageRatio,
    geometricUTurnCount,
    oppositeOverlapPercent,
    foldedLoopPenalty,
    repeatedStartAreaPercent,
    spurArmPercent,
    loopCleanupRemovedPercent: 0,
    loopCleanupDistanceRetentionRatio: 1,
    loopCleanupCount: 0,
    loopCleanupDistanceKm: 0,
    loopCleanupUTurnCount: 0,
  };
}

function shapeMetricsFromSignals(
  signals: ReturnType<typeof calculateRouteShapeSignals>,
  overlapPercent: number,
): RouteShapeMetrics {
  const outAndBackScore = clampNumber(
    signals.oppositeOverlapPercent * 2.2 +
      overlapPercent * 0.45 +
      signals.foldedLoopPenalty * 0.22,
    0,
    100,
  );
  const spurScore = clampNumber(
    signals.spurArmPercent +
      signals.repeatedStartAreaPercent * 0.35 +
      signals.loopCleanupRemovedPercent * 0.55,
    0,
    100,
  );
  const deadEndArmScore = clampNumber(
    signals.hookCount * 8 +
      signals.spurArmPercent * 0.85 +
      Math.max(0, signals.radialPeakCount - 1) * 12,
    0,
    100,
  );
  const loopnessScore = clampNumber(
    100 -
      signals.foldedLoopPenalty * 0.62 -
      spurScore * 0.34 -
      outAndBackScore * 0.30 -
      Math.max(0, 0.48 - signals.middleCoverageRatio) * 95 -
      Math.max(0, signals.centerReentryCount - 1) * 8,
    0,
    100,
  );
  return {
    loopnessScore,
    spurScore,
    deadEndArmScore,
    outAndBackScore,
    overlapScore: clampNumber(overlapPercent, 0, 100),
    centralReturnPercent: signals.centralReturnPercent,
    centerReentryCount: signals.centerReentryCount,
    radialPeakCount: signals.radialPeakCount,
    middleCoverageRatio: signals.middleCoverageRatio,
    geometricUTurnCount: signals.geometricUTurnCount,
    oppositeOverlapPercent: signals.oppositeOverlapPercent,
    foldedLoopPenalty: signals.foldedLoopPenalty,
    repeatedStartAreaPercent: signals.repeatedStartAreaPercent,
    spurArmPercent: signals.spurArmPercent,
    cleanupRemovedPercent: signals.loopCleanupRemovedPercent,
    cleanupDistanceRetentionRatio: signals.loopCleanupDistanceRetentionRatio,
    cleanupLoopCount: signals.loopCleanupCount,
    cleanupUTurnCount: signals.loopCleanupUTurnCount,
  };
}

function calculateRouteShapeMetrics(
  route: any,
  overlapPercent?: number,
): RouteShapeMetrics {
  return shapeMetricsFromSignals(
    calculateRouteShapeSignals(route),
    overlapPercent ?? calculateRouteOverlapPercent(route),
  );
}

function clampNumber(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function scoreAround(value: number, center: number, tolerance: number): number {
  if (tolerance <= 0) return value === center ? 1 : 0;
  return 1 - clampNumber(Math.abs(value - center) / tolerance, 0, 1);
}

function scoreRamp(value: number, softMin: number, idealMin: number): number {
  if (idealMin <= softMin) return value >= idealMin ? 1 : 0;
  if (value <= softMin) return 0;
  if (value >= idealMin) return 1;
  return clampNumber((value - softMin) / (idealMin - softMin), 0, 1);
}

function weightedAverage(
  scores: Array<{ value: number; weight: number }>,
): number {
  const totalWeight = scores.reduce((sum, item) => sum + item.weight, 0);
  if (totalWeight <= 0) return 0;
  return clampNumber(
    scores.reduce(
      (sum, item) => sum + clampNumber(item.value, 0, 1) * item.weight,
      0,
    ) / totalWeight,
    0,
    1,
  );
}

function estimateRouteSectorDiversity(coordinates: Coordinate[]): number {
  if (coordinates.length < 8) return 0;
  const origin = coordinates[0];
  const sectors = new Set<number>();
  const sampleStep = Math.max(1, Math.floor(coordinates.length / 48));
  for (let i = 0; i < coordinates.length; i += sampleStep) {
    const point = coordinates[i];
    if (calculateDistance(origin, point) * 1000 < 500) continue;
    const bearing = calculateBearing(origin, point);
    sectors.add(Math.max(0, Math.min(7, Math.floor(bearing / 45))));
  }
  return clampNumber((sectors.size / 6) * 100, 0, 100);
}

export function calculateRouteStyleMetrics(route: any): RouteStyleMetrics {
  const coordinates = extractRouteCoordinates(route);
  const distanceKm = Math.max(0, getRouteDistanceKm(route));
  const shapeSignals = calculateRouteShapeSignals(route);
  if (coordinates.length < 6 || distanceKm <= 0) {
    return {
      curveDensityPerKm: 0,
      curveDensityPer50Km: 0,
      averageSegmentLengthMeters: 0,
      sharpTurnCount: 0,
      sharpTurnRate: 0,
      smoothnessScore: 0,
      headingChangeTotal: 0,
      headingChangePerKm: 0,
      zigzagScore: 0,
      stubPenalty: 0,
      sectorDiversityScore: 0,
      loopnessScore: 0,
      spurScore: 100,
      deadEndArmScore: 100,
      outAndBackScore: 100,
      overlapScore: 100,
    };
  }
  const shapeMetrics = shapeMetricsFromSignals(shapeSignals, 0);

  const sampleStep = 5;
  let curveCount = 0;
  let sharpTurnCount = 0;
  let headingChangeTotal = 0;
  for (
    let i = sampleStep;
    i < coordinates.length - sampleStep;
    i += sampleStep
  ) {
    const previous = coordinates[i - sampleStep];
    const current = coordinates[i];
    const next = coordinates[Math.min(i + sampleStep, coordinates.length - 1)];
    const delta = headingDeltaDegrees(
      calculateBearing(previous, current),
      calculateBearing(current, next),
    );
    headingChangeTotal += delta;
    if (delta >= 15) curveCount += 1;
    if (delta >= 32) sharpTurnCount += 1;
  }

  const averageSegmentLengthMeters = coordinates.length <= 1
    ? 0
    : (measureCoordinatePathMeters(coordinates) / (coordinates.length - 1));
  const curveDensityPerKm = curveCount / distanceKm;
  const curveDensityPer50Km = curveDensityPerKm * 50;
  const headingChangePerKm = headingChangeTotal / distanceKm;
  const zigzagScore = clampNumber(
    shapeSignals.sharpTurnRate * 0.82 +
      shapeSignals.hookCount * 8 +
      shapeSignals.oppositeOverlapPercent * 0.42 +
      shapeSignals.foldedLoopPenalty * 0.24,
    0,
    100,
  );
  const stubPenalty = clampNumber(
    shapeSignals.spurArmPercent * 0.55 +
      shapeSignals.repeatedStartAreaPercent * 0.28 +
      shapeSignals.loopCleanupRemovedPercent * 0.70 +
      shapeSignals.hookCount * 4,
    0,
    100,
  );
  const smoothnessScore = clampNumber(
    100 -
      shapeSignals.angularRoughness * 1.10 -
      shapeSignals.sharpTurnRate * 0.65 -
      shapeSignals.hookCount * 3.2 -
      shapeSignals.oppositeOverlapPercent * 0.38 -
      shapeSignals.foldedLoopPenalty * 0.25 -
      stubPenalty * 0.35,
    0,
    100,
  );

  return {
    curveDensityPerKm,
    curveDensityPer50Km,
    averageSegmentLengthMeters,
    sharpTurnCount,
    sharpTurnRate: shapeSignals.sharpTurnRate,
    smoothnessScore,
    headingChangeTotal,
    headingChangePerKm,
    zigzagScore,
    stubPenalty,
    sectorDiversityScore: estimateRouteSectorDiversity(coordinates),
    loopnessScore: shapeMetrics.loopnessScore,
    spurScore: shapeMetrics.spurScore,
    deadEndArmScore: shapeMetrics.deadEndArmScore,
    outAndBackScore: shapeMetrics.outAndBackScore,
    overlapScore: shapeMetrics.overlapScore,
  };
}

export function scoreRouteStyleFit(
  route: any,
  mode: RouteMode | undefined,
): { score: number; reasons: string[]; metrics: RouteStyleMetrics } {
  const metrics = calculateRouteStyleMetrics(route);
  const normalizedMode = mode ?? "Standard";
  const smoothness = metrics.smoothnessScore / 100;
  const reasons: string[] = [];
  const score = (() => {
    switch (normalizedMode) {
      case "Sport Mode":
        if (metrics.smoothnessScore >= 78) reasons.push("smooth_flow");
        if (metrics.averageSegmentLengthMeters >= 180) {
          reasons.push("longer_segments");
        }
        if (metrics.zigzagScore >= 30) reasons.push("zigzag_penalty");
        if (metrics.sharpTurnRate >= 22) reasons.push("too_many_sharp_turns");
        if (metrics.spurScore >= 24) reasons.push("spur_penalty");
        {
          const rawScore = weightedAverage([
            {
              value: scoreAround(metrics.curveDensityPer50Km, 8, 9),
              weight: 0.07,
            },
            { value: scoreAround(metrics.sharpTurnRate, 6, 8), weight: 0.08 },
            {
              value: scoreRamp(metrics.averageSegmentLengthMeters, 130, 280),
              weight: 0.20,
            },
            { value: smoothness, weight: 0.34 },
            { value: scoreAround(metrics.zigzagScore, 8, 24), weight: 0.08 },
            { value: 1 - metrics.spurScore / 100, weight: 0.09 },
            { value: 1 - metrics.outAndBackScore / 100, weight: 0.08 },
            { value: metrics.loopnessScore / 100, weight: 0.16 },
          ]) * 100;
          const curvePenalty =
            scoreRamp(metrics.curveDensityPer50Km, 22, 34) * 12 +
            scoreRamp(metrics.sharpTurnRate, 14, 24) * 8 +
            scoreRamp(metrics.headingChangePerKm, 115, 165) * 6;
          return rawScore - curvePenalty;
        }
      case "Kurvenjagd":
        if (metrics.curveDensityPer50Km >= 28) {
          reasons.push("high_curve_density");
        }
        if (metrics.headingChangePerKm >= 130) {
          reasons.push("continuous_bends");
        }
        if (metrics.stubPenalty >= 28) reasons.push("stub_penalty");
        if (metrics.loopnessScore >= 72) reasons.push("clean_loop");
        {
          const loopSupport = weightedAverage([
            { value: metrics.loopnessScore / 100, weight: 0.44 },
            { value: 1 - metrics.spurScore / 100, weight: 0.24 },
            { value: 1 - metrics.outAndBackScore / 100, weight: 0.20 },
            { value: smoothness, weight: 0.12 },
          ]);
          const rawScore = weightedAverage([
            {
              value: scoreRamp(metrics.curveDensityPer50Km, 22, 36),
              weight: 0.28,
            },
            { value: scoreRamp(metrics.sharpTurnRate, 8, 18), weight: 0.15 },
            {
              value: scoreRamp(metrics.headingChangePerKm, 95, 150),
              weight: 0.14,
            },
            { value: metrics.loopnessScore / 100, weight: 0.18 },
            { value: 1 - metrics.spurScore / 100, weight: 0.12 },
            { value: 1 - metrics.outAndBackScore / 100, weight: 0.08 },
            { value: scoreRamp(smoothness, 0.45, 0.72), weight: 0.05 },
          ]) * 100;
          const loopPenalty = loopSupport < 0.58
            ? (0.58 - loopSupport) * 22
            : 0;
          return rawScore - loopPenalty;
        }
      case "Abendrunde":
        if (metrics.smoothnessScore >= 72) reasons.push("calm_flow");
        return weightedAverage([
          {
            value: smoothness,
            weight: 0.28,
          },
          {
            value: scoreAround(metrics.curveDensityPer50Km, 10, 12),
            weight: 0.14,
          },
          { value: scoreAround(metrics.zigzagScore, 6, 18), weight: 0.16 },
          { value: 1 - metrics.spurScore / 100, weight: 0.14 },
          { value: 1 - metrics.outAndBackScore / 100, weight: 0.10 },
          { value: metrics.loopnessScore / 100, weight: 0.12 },
          { value: scoreAround(metrics.sharpTurnRate, 6, 8), weight: 0.06 },
        ]) * 100;
      case "Entdecker":
        if (metrics.sectorDiversityScore >= 55) {
          reasons.push("sector_diverse");
        }
        return weightedAverage([
          { value: metrics.sectorDiversityScore / 100, weight: 0.34 },
          {
            value: scoreRamp(metrics.headingChangePerKm, 45, 105),
            weight: 0.16,
          },
          {
            value: scoreRamp(metrics.averageSegmentLengthMeters, 95, 210),
            weight: 0.10,
          },
          {
            value: scoreAround(metrics.curveDensityPer50Km, 16, 20),
            weight: 0.12,
          },
          { value: metrics.loopnessScore / 100, weight: 0.16 },
          { value: 1 - metrics.outAndBackScore / 100, weight: 0.08 },
          { value: smoothness, weight: 0.04 },
        ]) * 100;
      default:
        return weightedAverage([
          { value: smoothness, weight: 0.34 },
          {
            value: scoreAround(metrics.curveDensityPer50Km, 16, 16),
            weight: 0.30,
          },
          { value: scoreAround(metrics.stubPenalty, 8, 28), weight: 0.20 },
          { value: metrics.sectorDiversityScore / 100, weight: 0.16 },
        ]) * 100;
    }
  })();
  return { score: clampNumber(score, 0, 100), reasons, metrics };
}

function applyStyleFitToQuality(
  quality: RouteQualityEvaluation,
  route: any,
  mode?: RouteMode,
): RouteQualityEvaluation {
  const styleFit = scoreRouteStyleFit(route, mode);
  const shapeMetrics = calculateRouteShapeMetrics(
    route,
    quality.overlapPercent,
  );
  const baseScore = quality.score;
  if (quality.tier === "rejected") {
    return {
      ...quality,
      baseScore,
      styleFitScore: styleFit.score,
      styleFitReasons: styleFit.reasons,
      styleMetrics: styleFit.metrics,
      shapeMetrics,
    };
  }
  const stylePenalty = (100 - styleFit.score) * 0.55;
  const styleBonus = styleFit.score * 0.08;
  return {
    ...quality,
    baseScore,
    score: baseScore + stylePenalty - styleBonus,
    styleFitScore: styleFit.score,
    styleFitReasons: styleFit.reasons,
    styleMetrics: styleFit.metrics,
    shapeMetrics,
  };
}

function evaluateRouteQualityCore(
  route: any,
  routeType: "ROUND_TRIP" | "POINT_TO_POINT",
  options?: {
    targetDistanceKm?: number;
    distanceConfig?: DistanceConfig;
    mode?: RouteMode;
    avoidHighways?: boolean;
    requiredStops?: boolean;
  },
): RouteQualityEvaluation {
  const coordinateCount = route?.geometry?.coordinates?.length ?? 0;
  const actualDistanceKm = getRouteDistanceKm(route);
  const targetDistanceKm = options?.targetDistanceKm ?? 0;
  const distanceConfig = options?.distanceConfig;
  const avoidHighways = options?.avoidHighways === true;
  const requiredStops = options?.requiredStops === true;
  const distanceDeltaKm = targetDistanceKm > 0
    ? Math.abs(actualDistanceKm - targetDistanceKm)
    : 0;
  // Anti-Kraken: Kurvenjagd bekommt einen etwas schärferen Overlap-
  // Threshold, damit echte Out-and-Back-/Ast-Formen (Sackgasse hin+zurück)
  // konsequent als rejected markiert werden. Wert kalibriert auf reale
  // Tal-Geometrie (Dornbirn/Bregenzerwald): 16 fängt Kraken, verschenkt aber
  // keine gültigen Kurven-Loops.
  const isCurveChase = options?.mode === "Kurvenjagd";
  const isSportMode = options?.mode === "Sport Mode";
  const isNoHighwayHairpinEligibleRoundTrip = routeType === "ROUND_TRIP" &&
    options?.avoidHighways === true &&
    (options?.targetDistanceKm ?? Number.POSITIVE_INFINITY) <= 115;
  const isShortNoHighwaySportRoundTrip = routeType === "ROUND_TRIP" &&
    isSportMode &&
    options?.avoidHighways === true &&
    (options?.targetDistanceKm ?? Number.POSITIVE_INFINITY) <= 60;
  // Short Sport roundtrips with highways enabled: Mapbox often needs to
  // take a highway exit, drive 1–2 km on local roads, then re-enter the
  // highway. The client flags these exit loops as geometric u-turns even
  // though the rendered GeoJSON is fine. Allow up to 3 u-turns plus a
  // slightly larger overlap/fold band to unblock this scenario.
  const isShortSportWithHighwayRoundTrip = routeType === "ROUND_TRIP" &&
    isSportMode &&
    options?.avoidHighways === false &&
    (options?.targetDistanceKm ?? Number.POSITIVE_INFINITY) <= 60;
  const hardDistanceMin = targetDistanceKm <= 0 ? 0 : targetDistanceKm *
    (targetDistanceKm <= 60
      ? avoidHighways ? 0.64 : 0.70
      : targetDistanceKm <= 100
      ? 0.74
      : 0.76);
  const hardDistanceMax = targetDistanceKm <= 0
    ? Number.POSITIVE_INFINITY
    : targetDistanceKm *
      (targetDistanceKm <= 60
        ? avoidHighways ? isShortNoHighwaySportRoundTrip ? 1.30 : 1.44 : 1.36
        : targetDistanceKm <= 100
        ? 1.34
        : 1.30);
  const severeDistanceMiss = targetDistanceKm > 0 &&
    (actualDistanceKm < hardDistanceMin || actualDistanceKm > hardDistanceMax);
  const shortSportPresentationMinKm = 44.8;
  const shortSportPresentationMaxKm = 55.2;
  const shortSportRawDistanceMiss = isShortNoHighwaySportRoundTrip &&
    (actualDistanceKm < shortSportPresentationMinKm - 1.0 ||
      actualDistanceKm > shortSportPresentationMaxKm + 1.2);
  if (routeType === "ROUND_TRIP" && severeDistanceMiss) {
    return {
      passed: false,
      reason: `distance=${actualDistanceKm.toFixed(1)}km`,
      overlapPercent: 0,
      hasUTurn: false,
      tier: "rejected",
      score: 910 +
        distanceDeltaKm * 7 +
        Math.max(0, Math.abs(actualDistanceKm - targetDistanceKm)) * 2.5,
      coordinateCount,
      actualDistanceKm,
      distanceDeltaKm,
    };
  }
  if (routeType === "ROUND_TRIP" && shortSportRawDistanceMiss) {
    return {
      passed: false,
      reason: `short_sport_distance=${actualDistanceKm.toFixed(1)}km`,
      overlapPercent: 0,
      hasUTurn: false,
      tier: "rejected",
      score: 940 +
        Math.abs(
            actualDistanceKm < shortSportPresentationMinKm
              ? shortSportPresentationMinKm - actualDistanceKm
              : actualDistanceKm - shortSportPresentationMaxKm,
          ) * 18,
      coordinateCount,
      actualDistanceKm,
      distanceDeltaKm,
    };
  }
  const overlapPercent = calculateRouteOverlapPercent(route);
  const shapeSignals = calculateRouteShapeSignals(route);
  const hasManeuverUTurn = hasUTurnManeuver(route);
  const hasGeometricUTurn = routeType === "ROUND_TRIP" &&
    shapeSignals.geometricUTurnCount > 0;
  const hasUTurn = hasManeuverUTurn || hasGeometricUTurn;
  const overlapThreshold = routeType === "ROUND_TRIP"
    ? (isCurveChase ? 15 : 16)
    : (isCurveChase ? 12 : 14);
  // Kurvenjagd strenger bei Haken/Radial-Peaks — das sind die typischen
  // „Äste/Kraken“ (Mapbox stolpert in Sackgasse, kehrt um, nächster Ast).
  // 6 (statt 8) ist genug aggressiv für Anti-Kraken ohne valide Kurven-Loops
  // zu zerschneiden.
  const severeHookCount = routeType === "ROUND_TRIP"
    ? (isCurveChase ? 6 : 8)
    : 4;
  const avoidHighwaysSportEligible = avoidHighways === true && isSportMode &&
    routeType === "ROUND_TRIP";
  const mediumLongNoHighwaySportLooseHooks = avoidHighwaysSportEligible &&
    targetDistanceKm > 60 && targetDistanceKm <= 115;
  const effectiveSevereHookCount = mediumLongNoHighwaySportLooseHooks
    ? Math.max(severeHookCount, 20)
    : severeHookCount;
  // Kurvenjagd: Reentry/RadialPeaks etwas strenger werten, damit offene
  // Stern-/Astformen früher als "severe" markiert werden, aber nicht so
  // streng, dass normale enge Tal-Loops verworfen werden.
  // medium/long no-highway Sport deserves a more lenient severeShape
  // check because Alpine routes naturally produce higher foldedLoop and
  // opposite-overlap readings (switchbacks, valley corridors).
  const mediumLongNoHighwaySportShape = routeType === "ROUND_TRIP" &&
    avoidHighways === true && isSportMode &&
    !isShortNoHighwaySportRoundTrip && targetDistanceKm > 60 &&
    targetDistanceKm <= 115;
  const longNoHighwaySportSpurShape = mediumLongNoHighwaySportShape &&
    targetDistanceKm >= 90 &&
    (
      (
        shapeSignals.spurArmPercent >= 42 &&
        (
          shapeSignals.middleCoverageRatio < 0.34 ||
          shapeSignals.repeatedStartAreaPercent >= 18 ||
          shapeSignals.oppositeOverlapPercent >= 22 ||
          shapeSignals.radialPeakCount >= 3
        )
      ) ||
      (
        shapeSignals.oppositeOverlapPercent > 22 &&
        shapeSignals.middleCoverageRatio < 0.34 &&
        shapeSignals.foldedLoopPenalty > 68
      ) ||
      (
        shapeSignals.loopCleanupRemovedPercent > 24 &&
        shapeSignals.hookCount >= 6
      )
    );
  const severeRoundTripShape = routeType === "ROUND_TRIP" &&
    (
      shapeSignals.centerReentryCount >= 4 ||
      longNoHighwaySportSpurShape ||
      (shapeSignals.radialPeakCount >= (isCurveChase ? 3 : 4) &&
        shapeSignals.middleCoverageRatio < 0.34) ||
      (shapeSignals.middleCoverageRatio < 0.18 &&
        shapeSignals.centralReturnPercent > 18) ||
      (shapeSignals.centralReturnPercent > 28 &&
        shapeSignals.middleCoverageRatio < 0.26) ||
      // Sport: offene Stern-/Vielarm-Formen ohne ausreichende Loop-Fläche
      (isSportMode === true &&
        !mediumLongNoHighwaySportShape &&
        shapeSignals.radialPeakCount >= 4 &&
        shapeSignals.middleCoverageRatio < 0.33) ||
      shapeSignals.repeatedStartAreaPercent > 52 ||
      (
        shapeSignals.spurArmPercent >= 58 &&
        shapeSignals.repeatedStartAreaPercent >= 32
      ) ||
      (
        shapeSignals.radialPeakCount >= 3 &&
        shapeSignals.spurArmPercent >= 52 &&
        (
          shapeSignals.middleCoverageRatio < 0.40 ||
          shapeSignals.repeatedStartAreaPercent >= 18
        )
      ) ||
      (
        shapeSignals.oppositeOverlapPercent >
          (isShortNoHighwaySportRoundTrip
            ? 16
            : (mediumLongNoHighwaySportShape ? 28 : 24)) &&
        shapeSignals.middleCoverageRatio <
          (isShortNoHighwaySportRoundTrip
            ? 0.46
            : (mediumLongNoHighwaySportShape ? 0.25 : 0.36))
      ) ||
      (
        // foldedLoopPenalty is clamped at 100, which naturally hits for
        // alpine serpentines. Disable the gate entirely for medium/long
        // no-highway Sport and rely on oppositeOverlap + coverage above
        // to catch real kraken shapes.
        !mediumLongNoHighwaySportShape &&
        shapeSignals.foldedLoopPenalty >
          (isShortNoHighwaySportRoundTrip ? 56 : 74)
      )
    );
  const severeCentralReturn = routeType === "ROUND_TRIP"
    ? (
      shapeSignals.centralReturnPercent > (isCurveChase ? 30 : 35) ||
      (
        shapeSignals.centralReturnPercent > (isCurveChase ? 22 : 24) &&
        (
          shapeSignals.centerReentryCount >= 2 ||
          shapeSignals.radialPeakCount >= (isCurveChase ? 3 : 4) ||
          shapeSignals.hookCount >= (isCurveChase ? 3 : 4)
        )
      )
    )
    : shapeSignals.centralReturnPercent > 11;

  if (routeType !== "ROUND_TRIP") {
    if (coordinateCount < 30 && actualDistanceKm > 10) {
      return {
        passed: false,
        reason: `coords=${coordinateCount}`,
        overlapPercent,
        hasUTurn,
        tier: "rejected",
        score: 1000 + Math.max(0, 30 - coordinateCount),
        coordinateCount,
        actualDistanceKm,
        distanceDeltaKm,
      };
    }
    if (hasUTurn) {
      return {
        passed: false,
        reason: "u_turn",
        overlapPercent,
        hasUTurn,
        tier: "rejected",
        score: 1200,
        coordinateCount,
        actualDistanceKm,
        distanceDeltaKm,
      };
    }
    if (overlapPercent > overlapThreshold) {
      return {
        passed: false,
        reason: `overlap=${overlapPercent.toFixed(1)}%`,
        overlapPercent,
        hasUTurn,
        tier: "rejected",
        score: 1100 + overlapPercent,
        coordinateCount,
        actualDistanceKm,
        distanceDeltaKm,
      };
    }
    if (shapeSignals.hookCount >= severeHookCount) {
      return {
        passed: false,
        reason: `hooks=${shapeSignals.hookCount}`,
        overlapPercent,
        hasUTurn,
        tier: "rejected",
        score: 1040 + shapeSignals.hookCount * 20,
        coordinateCount,
        actualDistanceKm,
        distanceDeltaKm,
      };
    }

    return {
      passed: true,
      reason: "ok",
      overlapPercent,
      hasUTurn,
      tier: "ideal",
      score: overlapPercent +
        shapeSignals.angularRoughness * 0.22 +
        shapeSignals.sharpTurnRate * 0.65 +
        shapeSignals.hookCount * 7 +
        shapeSignals.centralReturnPercent * 0.45,
      coordinateCount,
      actualDistanceKm,
      distanceDeltaKm,
    };
  }

  const withinIdealDistance = !distanceConfig ||
    targetDistanceKm <= 0 ||
    (actualDistanceKm >= distanceConfig.minKm &&
      actualDistanceKm <= distanceConfig.maxKm);
  const withinAcceptableDistance = !distanceConfig ||
    targetDistanceKm <= 0 ||
    (actualDistanceKm >= distanceConfig.acceptableMinKm &&
      actualDistanceKm <= distanceConfig.acceptableMaxKm);
  const severeOverlap = overlapPercent >
    (isShortNoHighwaySportRoundTrip ? 34 : 52);
  const goodTierOverlapOk = overlapPercent <=
    (isShortNoHighwaySportRoundTrip ? 22 : isCurveChase ? 26 : 28);
  const idealOverlap = overlapPercent <= overlapThreshold;
  const severeCoordinateThreshold = targetDistanceKm <= 60
    ? 17
    : targetDistanceKm <= 100
    ? 19
    : 23;
  const weakGeometryThreshold = targetDistanceKm <= 60
    ? 23
    : targetDistanceKm <= 100
    ? 27
    : 31;
  const severeCoordinateShortage =
    coordinateCount < severeCoordinateThreshold && actualDistanceKm > 8;
  const weakGeometry = coordinateCount < weakGeometryThreshold &&
    actualDistanceKm > 15;
  const shortSportOverlapMiss = isShortNoHighwaySportRoundTrip &&
    overlapPercent > 22;
  const noHighwayLoopCleanup = isNoHighwayHairpinEligibleRoundTrip
    ? estimateClientLoopCleanupImpact(extractRouteCoordinates(route))
    : null;
  if (noHighwayLoopCleanup != null) {
    shapeSignals.loopCleanupRemovedPercent =
      noHighwayLoopCleanup.removedPointPercent;
    shapeSignals.loopCleanupDistanceRetentionRatio =
      noHighwayLoopCleanup.distanceRetentionRatio;
    shapeSignals.loopCleanupCount = noHighwayLoopCleanup.removedLoops;
    shapeSignals.loopCleanupDistanceKm = noHighwayLoopCleanup.cleanedDistanceKm;
    shapeSignals.loopCleanupUTurnCount =
      noHighwayLoopCleanup.cleanedGeometricUTurnCount;
  }
  // Real mountain valleys (Dornbirn/Bregenzerwald) naturally contain
  // hairpin bends on no-highway roads. The short-distance path stays
  // strict, but medium/long no-highway Sport routes need much more
  // tolerance for geometric U-turns, overlap and coverage because Mapbox
  // cannot avoid Pass-style serpentines without the motorway.
  const mediumLongNoHighwaySport = isNoHighwayHairpinEligibleRoundTrip &&
    !isShortNoHighwaySportRoundTrip && isSportMode;
  // Count Mapbox-reported uturn maneuvers. Alpine hairpin bends are often
  // classified as uturn modifiers even though they are natural switchbacks
  // on serpentine mountain roads. For medium/long no-highway Sport rides
  // we tolerate a handful of those as long as the geometric signals stay
  // within the (loosened) hairpin gate thresholds.
  const uTurnManeuverCount = hasManeuverUTurn ? countUTurnManeuvers(route) : 0;
  const tolerantShortSportHairpin = isShortSportWithHighwayRoundTrip;
  const cleanShortSportHairpin = tolerantShortSportHairpin &&
    !hasManeuverUTurn && shapeSignals.geometricUTurnCount <= 3 &&
    (distanceConfig == null ||
      (
        actualDistanceKm >= distanceConfig.acceptableMinKm * 0.9 &&
        actualDistanceKm <= distanceConfig.acceptableMaxKm * 1.12
      )) &&
    overlapPercent <= 26 &&
    shapeSignals.oppositeOverlapPercent <= 20 &&
    shapeSignals.centerReentryCount <= 2 &&
    shapeSignals.repeatedStartAreaPercent <= 26 &&
    shapeSignals.spurArmPercent <= 30 &&
    shapeSignals.centralReturnPercent <= 20 &&
    shapeSignals.hookCount <= 12;
  const cleanNoHighwayHairpin = (isNoHighwayHairpinEligibleRoundTrip &&
    (mediumLongNoHighwaySport
      ? uTurnManeuverCount <= (targetDistanceKm > 85 ? 6 : 5)
      : !hasManeuverUTurn) &&
    shapeSignals.geometricUTurnCount <=
      (mediumLongNoHighwaySport
        ? (targetDistanceKm > 85 ? 6 : 5)
        : (targetDistanceKm > 85 ? 2 : 1)) &&
    (distanceConfig == null ||
      (
        actualDistanceKm >=
          (isShortNoHighwaySportRoundTrip
            ? shortSportPresentationMinKm
            : distanceConfig.acceptableMinKm *
              (mediumLongNoHighwaySport ? 0.94 : 1.0)) &&
        actualDistanceKm <=
          (isShortNoHighwaySportRoundTrip
            ? shortSportPresentationMaxKm + 1.0
            : distanceConfig.acceptableMaxKm *
                (mediumLongNoHighwaySport ? 1.22 : 1.0) + 1.0)
      )) &&
    overlapPercent <=
      (mediumLongNoHighwaySport ? 36 : (isCurveChase ? 10 : 12)) &&
    shapeSignals.oppositeOverlapPercent <=
      (mediumLongNoHighwaySport
        ? (targetDistanceKm > 85 ? 28 : 24)
        : (targetDistanceKm > 85 ? 6 : 5)) &&
    shapeSignals.foldedLoopPenalty <=
      (mediumLongNoHighwaySport ? 100 : (targetDistanceKm > 85 ? 56 : 36)) &&
    shapeSignals.middleCoverageRatio >=
      (mediumLongNoHighwaySport ? 0.40 : 0.68) &&
    shapeSignals.centerReentryCount <=
      (mediumLongNoHighwaySport ? 2 : 0) &&
    shapeSignals.repeatedStartAreaPercent <=
      (mediumLongNoHighwaySport ? 30 : 10) &&
    shapeSignals.spurArmPercent <= (mediumLongNoHighwaySport ? 34 : 14) &&
    shapeSignals.centralReturnPercent <=
      (mediumLongNoHighwaySport ? 22 : 8) &&
    shapeSignals.hookCount <= (mediumLongNoHighwaySport ? 18 : 2) &&
    shapeSignals.loopCleanupRemovedPercent <=
      (mediumLongNoHighwaySport ? 38 : 12) &&
    shapeSignals.loopCleanupDistanceRetentionRatio >=
      (mediumLongNoHighwaySport ? 0.70 : 0.88) &&
    (distanceConfig == null ||
    shapeSignals.loopCleanupDistanceKm >=
      (isShortNoHighwaySportRoundTrip
        ? shortSportPresentationMinKm - 1.0
        : distanceConfig.acceptableMinKm - 1.0))) ||
    cleanShortSportHairpin;
  const cleanRequiredStopHairpin = requiredStops &&
    !hasManeuverUTurn &&
    shapeSignals.geometricUTurnCount <= (isCurveChase ? 5 : 4) &&
    overlapPercent <= (isCurveChase ? 28 : 30) &&
    shapeSignals.oppositeOverlapPercent <= (isCurveChase ? 24 : 26) &&
    shapeSignals.foldedLoopPenalty <= 88 &&
    shapeSignals.middleCoverageRatio >= 0.22 &&
    shapeSignals.centerReentryCount <= 2 &&
    shapeSignals.repeatedStartAreaPercent <= 42 &&
    shapeSignals.spurArmPercent <= 36 &&
    shapeSignals.centralReturnPercent <= 28 &&
    shapeSignals.hookCount <= (isCurveChase ? 14 : 16);

  if (hasUTurn && !cleanNoHighwayHairpin && !cleanRequiredStopHairpin) {
    if (isNoHighwayHairpinEligibleRoundTrip && hasGeometricUTurn) {
      debugLog(
        `[RT-QA] hairpin-reject uTurn=${shapeSignals.geometricUTurnCount}` +
          ` manUT=${hasManeuverUTurn}(${uTurnManeuverCount}) clean=${cleanNoHighwayHairpin}` +
          ` dist=${actualDistanceKm.toFixed(1)} ovl=${
            overlapPercent.toFixed(1)
          }` +
          ` opp=${shapeSignals.oppositeOverlapPercent.toFixed(1)}` +
          ` fld=${shapeSignals.foldedLoopPenalty.toFixed(1)}` +
          ` cov=${shapeSignals.middleCoverageRatio.toFixed(2)}` +
          ` crx=${shapeSignals.centerReentryCount}` +
          ` rep=${shapeSignals.repeatedStartAreaPercent.toFixed(1)}` +
          ` spr=${shapeSignals.spurArmPercent.toFixed(1)}` +
          ` ctr=${shapeSignals.centralReturnPercent.toFixed(1)}` +
          ` hk=${shapeSignals.hookCount}` +
          ` cln=${shapeSignals.loopCleanupRemovedPercent.toFixed(1)}` +
          ` ret=${shapeSignals.loopCleanupDistanceRetentionRatio.toFixed(2)}` +
          ` cln_d=${shapeSignals.loopCleanupDistanceKm.toFixed(1)}` +
          ` mediumLongSport=${mediumLongNoHighwaySport}`,
      );
    }
    return {
      passed: false,
      reason: hasGeometricUTurn
        ? `u_turn_geometry=${shapeSignals.geometricUTurnCount}`
        : "u_turn",
      overlapPercent,
      hasUTurn,
      tier: "rejected",
      score: 1200 + shapeSignals.geometricUTurnCount * 35,
      coordinateCount,
      actualDistanceKm,
      distanceDeltaKm,
    };
  }
  if (severeCoordinateShortage) {
    return {
      passed: false,
      reason: `coords=${coordinateCount}`,
      overlapPercent,
      hasUTurn,
      tier: "rejected",
      score: 900 + Math.max(0, severeCoordinateThreshold - coordinateCount) * 8,
      coordinateCount,
      actualDistanceKm,
      distanceDeltaKm,
    };
  }
  if (severeOverlap) {
    return {
      passed: false,
      reason: `overlap=${overlapPercent.toFixed(1)}%`,
      overlapPercent,
      hasUTurn,
      tier: "rejected",
      score: 900 + overlapPercent * 6,
      coordinateCount,
      actualDistanceKm,
      distanceDeltaKm,
    };
  }
  if (shortSportRawDistanceMiss) {
    return {
      passed: false,
      reason: `short_sport_distance=${actualDistanceKm.toFixed(1)}km`,
      overlapPercent,
      hasUTurn,
      tier: "rejected",
      score: 940 +
        Math.abs(
            actualDistanceKm < shortSportPresentationMinKm
              ? shortSportPresentationMinKm - actualDistanceKm
              : actualDistanceKm - shortSportPresentationMaxKm,
          ) * 18,
      coordinateCount,
      actualDistanceKm,
      distanceDeltaKm,
    };
  }
  if (shortSportOverlapMiss) {
    return {
      passed: false,
      reason: `short_sport_overlap=${overlapPercent.toFixed(1)}%`,
      overlapPercent,
      hasUTurn,
      tier: "rejected",
      score: 940 + overlapPercent * 5,
      coordinateCount,
      actualDistanceKm,
      distanceDeltaKm,
    };
  }

  const branchPenalty = shapeSignals.centerReentryCount * 17 +
    Math.max(0, shapeSignals.radialPeakCount - 1) * 9 +
    Math.max(0, 0.50 - shapeSignals.middleCoverageRatio) * 86 +
    shapeSignals.repeatedStartAreaPercent * 0.9 +
    shapeSignals.spurArmPercent * 0.8 +
    Math.max(0, 1 - shapeSignals.loopCleanupDistanceRetentionRatio) * 140;
  const estimatedClientCleanedDistanceKm = actualDistanceKm *
    shapeSignals.loopCleanupDistanceRetentionRatio;
  const clientCleanupWouldMissDistance = distanceConfig != null &&
    estimatedClientCleanedDistanceKm < distanceConfig.acceptableMinKm;
  const clientCleanupWouldMissPresentationBand =
    isShortNoHighwaySportRoundTrip &&
    (shapeSignals.loopCleanupDistanceKm < shortSportPresentationMinKm ||
      shapeSignals.loopCleanupDistanceKm > shortSportPresentationMaxKm);
  if (
    isShortNoHighwaySportRoundTrip &&
    (
      (
        shapeSignals.loopCleanupUTurnCount > 0 &&
        !cleanNoHighwayHairpin
      ) ||
      (clientCleanupWouldMissDistance && !cleanNoHighwayHairpin) ||
      (clientCleanupWouldMissPresentationBand &&
        !cleanNoHighwayHairpin) ||
      shapeSignals.centerReentryCount >= 3 ||
      shapeSignals.radialPeakCount >= 4 ||
      shapeSignals.repeatedStartAreaPercent > 28 ||
      (
        shapeSignals.spurArmPercent > 28 &&
        (
          shapeSignals.repeatedStartAreaPercent > 18 ||
          shapeSignals.middleCoverageRatio < 0.40
        )
      ) ||
      (
        shapeSignals.middleCoverageRatio < 0.30 &&
        shapeSignals.centralReturnPercent > 16
      ) ||
      (
        overlapPercent > 28 &&
        shapeSignals.middleCoverageRatio < 0.38
      ) ||
      (
        shapeSignals.oppositeOverlapPercent > 12 &&
        shapeSignals.middleCoverageRatio < 0.50
      ) ||
      (
        shapeSignals.foldedLoopPenalty > 44 &&
        shapeSignals.middleCoverageRatio < 0.54
      ) ||
      (
        shapeSignals.loopCleanupRemovedPercent > 18 &&
        (
          shapeSignals.loopCleanupDistanceRetentionRatio < 0.84 ||
          clientCleanupWouldMissDistance
        )
      ) ||
      (
        shapeSignals.loopCleanupRemovedPercent > 30 &&
        shapeSignals.loopCleanupCount >= 12
      )
    )
  ) {
    return {
      passed: false,
      reason:
        `short_sport_shape=branches:${shapeSignals.radialPeakCount}/reentry:${shapeSignals.centerReentryCount}/coverage:${
          shapeSignals.middleCoverageRatio.toFixed(2)
        }/backtrack:${shapeSignals.oppositeOverlapPercent.toFixed(1)}%/fold:${
          shapeSignals.foldedLoopPenalty.toFixed(1)
        }/start:${shapeSignals.repeatedStartAreaPercent.toFixed(1)}%/spur:${
          shapeSignals.spurArmPercent.toFixed(1)
        }%/cleanup:${shapeSignals.loopCleanupRemovedPercent.toFixed(1)}%/${
          shapeSignals.loopCleanupDistanceRetentionRatio.toFixed(2)
        }/cleanDist:${
          shapeSignals.loopCleanupDistanceKm.toFixed(1)
        }km/u:${shapeSignals.loopCleanupUTurnCount}`,
      overlapPercent,
      hasUTurn,
      tier: "rejected",
      score: 930 + branchPenalty + overlapPercent * 4,
      coordinateCount,
      actualDistanceKm,
      distanceDeltaKm,
    };
  }
  if (shapeSignals.hookCount >= effectiveSevereHookCount) {
    return {
      passed: false,
      reason: `hooks=${shapeSignals.hookCount}`,
      overlapPercent,
      hasUTurn,
      tier: "rejected",
      score: 900 + shapeSignals.hookCount * 24,
      coordinateCount,
      actualDistanceKm,
      distanceDeltaKm,
    };
  }
  if (severeCentralReturn) {
    return {
      passed: false,
      reason: `center_return=${shapeSignals.centralReturnPercent.toFixed(1)}%`,
      overlapPercent,
      hasUTurn,
      tier: "rejected",
      score: 920 + shapeSignals.centralReturnPercent * 8,
      coordinateCount,
      actualDistanceKm,
      distanceDeltaKm,
    };
  }
  if (severeRoundTripShape) {
    return {
      passed: false,
      reason:
        `shape=branches:${shapeSignals.radialPeakCount}/reentry:${shapeSignals.centerReentryCount}/coverage:${
          shapeSignals.middleCoverageRatio.toFixed(2)
        }/backtrack:${shapeSignals.oppositeOverlapPercent.toFixed(1)}%/fold:${
          shapeSignals.foldedLoopPenalty.toFixed(1)
        }/start:${shapeSignals.repeatedStartAreaPercent.toFixed(1)}%/spur:${
          shapeSignals.spurArmPercent.toFixed(1)
        }`,
      overlapPercent,
      hasUTurn,
      tier: "rejected",
      score: 910 + branchPenalty,
      coordinateCount,
      actualDistanceKm,
      distanceDeltaKm,
    };
  }
  if (severeDistanceMiss) {
    return {
      passed: false,
      reason: `distance=${actualDistanceKm.toFixed(1)}km`,
      overlapPercent,
      hasUTurn,
      tier: "rejected",
      score: 910 +
        distanceDeltaKm * 7 +
        Math.max(0, Math.abs(actualDistanceKm - targetDistanceKm)) * 2.5,
      coordinateCount,
      actualDistanceKm,
      distanceDeltaKm,
    };
  }

  let tier: RouteQualityTier = "acceptable";
  if (
    withinIdealDistance &&
    idealOverlap &&
    coordinateCount >= 38 &&
    shapeSignals.angularRoughness <= 62 &&
    shapeSignals.sharpTurnRate <= 34 &&
    shapeSignals.centralReturnPercent <= 10 &&
    shapeSignals.hookCount <= 1 &&
    shapeSignals.centerReentryCount <= 1 &&
    shapeSignals.radialPeakCount <= 2 &&
    shapeSignals.repeatedStartAreaPercent <= 18 &&
    shapeSignals.spurArmPercent <= 18 &&
    shapeSignals.foldedLoopPenalty <= 40 &&
    shapeSignals.loopCleanupRemovedPercent <= 8 &&
    shapeSignals.middleCoverageRatio >= 0.48
  ) {
    tier = "ideal";
  } else if (
    withinAcceptableDistance &&
    goodTierOverlapOk &&
    !weakGeometry &&
    shapeSignals.angularRoughness <= 74 &&
    shapeSignals.sharpTurnRate <= 44 &&
    shapeSignals.centralReturnPercent <= 17 &&
    shapeSignals.hookCount <= 3 &&
    shapeSignals.centerReentryCount <= 2 &&
    shapeSignals.radialPeakCount <= 4 &&
    shapeSignals.repeatedStartAreaPercent <= 30 &&
    shapeSignals.spurArmPercent <= 36 &&
    shapeSignals.foldedLoopPenalty <= 60 &&
    shapeSignals.loopCleanupRemovedPercent <= 18 &&
    shapeSignals.middleCoverageRatio >= 0.36
  ) {
    tier = "good";
  }

  const score = distanceDeltaKm * 7 +
    overlapPercent * 3 +
    shapeSignals.angularRoughness * 0.85 +
    shapeSignals.sharpTurnRate * 1.7 +
    shapeSignals.hookCount * 18 +
    shapeSignals.centralReturnPercent * 3.4 +
    shapeSignals.oppositeOverlapPercent * 2.4 +
    shapeSignals.foldedLoopPenalty * 1.2 +
    shapeSignals.repeatedStartAreaPercent * 1.35 +
    shapeSignals.spurArmPercent * 1.45 +
    shapeSignals.loopCleanupRemovedPercent * 1.8 +
    branchPenalty +
    (tier === "ideal" ? 0 : tier === "good" ? 24 : 60) +
    (withinAcceptableDistance ? 0 : 45) +
    Math.max(0, 34 - coordinateCount) * 2;

  return {
    passed: true,
    reason: tier === "ideal"
      ? "ideal"
      : tier === "good"
      ? "good"
      : `acceptable(dist=${actualDistanceKm.toFixed(1)}km, overlap=${
        overlapPercent.toFixed(1)
      }%, rough=${shapeSignals.angularRoughness.toFixed(1)}, center=${
        shapeSignals.centralReturnPercent.toFixed(1)
      }%)`,
    overlapPercent,
    hasUTurn,
    tier,
    score,
    coordinateCount,
    actualDistanceKm,
    distanceDeltaKm,
  };
}

export function evaluateRouteQuality(
  route: any,
  routeType: "ROUND_TRIP" | "POINT_TO_POINT",
  options?: {
    targetDistanceKm?: number;
    distanceConfig?: DistanceConfig;
    mode?: RouteMode;
    avoidHighways?: boolean;
    requiredStops?: boolean;
  },
): RouteQualityEvaluation {
  const quality = evaluateRouteQualityCore(route, routeType, options);
  if (routeType !== "ROUND_TRIP") return quality;
  return applyStyleFitToQuality(quality, route, options?.mode);
}

export function evaluateRouteCleanupGate(
  route: any,
  routeType: "ROUND_TRIP" | "POINT_TO_POINT",
  options?: {
    targetDistanceKm?: number;
    distanceConfig?: DistanceConfig;
    mode?: RouteMode;
    avoidHighways?: boolean;
    startLocation?: Coordinate;
    requiredStops?: boolean;
  },
): RouteCleanupEvaluation {
  if (routeType !== "ROUND_TRIP") {
    const coordinates = extractRouteCoordinates(route);
    const cleanedDistanceKm = getRouteDistanceKm(route);
    return {
      passed: true,
      reason: "cleanup_not_required",
      removedPointPercent: 0,
      distanceRetentionRatio: 1,
      removedLoops: 0,
      cleanedDistanceKm,
      cleanedGeometricUTurnCount: 0,
      fingerprint: hashCoordinates(coordinates, cleanedDistanceKm),
    };
  }

  const coordinates = extractRouteCoordinates(route);
  if (coordinates.length < 2) {
    return {
      passed: false,
      reason: "cleanup_coords=0",
      removedPointPercent: 0,
      distanceRetentionRatio: 0,
      removedLoops: 0,
      cleanedDistanceKm: 0,
      cleanedGeometricUTurnCount: 0,
      fingerprint: "empty",
    };
  }

  const cleanup = cleanupLoopAndCollapse(
    coordinates,
    typeof route?.distance === "number" && Number.isFinite(route.distance)
      ? route.distance
      : measureCoordinatePathMeters(coordinates),
    options?.startLocation,
  );
  const distanceConfig = options?.distanceConfig;
  const targetDistanceKm = options?.targetDistanceKm ?? 0;
  // Medium/long no-highway Sport rides run through alpine serpentines
  // where Mapbox reports uturn modifiers. Tolerate a bounded number
  // of them when the cleaned route is otherwise geometrically healthy.
  const mediumLongNoHighwaySportGate = routeType === "ROUND_TRIP" &&
    options?.avoidHighways === true &&
    options?.mode === "Sport Mode" &&
    targetDistanceKm > 60 && targetDistanceKm <= 115;
  const requiredStopsGate = options?.requiredStops === true;
  const maneuverUTurnAllowance = mediumLongNoHighwaySportGate ? 6 : 0;
  const maneuverUTurnCount = countUTurnManeuvers(route);
  const manualUTurnBreach = maneuverUTurnCount > maneuverUTurnAllowance;
  const geometricUTurnAllowance = requiredStopsGate
    ? 4
    : mediumLongNoHighwaySportGate
    ? 6
    : 0;
  const cleanedGeometricUTurnBreach = cleanup.cleanedGeometricUTurnCount >
    geometricUTurnAllowance;
  const cleanedHasUTurn = manualUTurnBreach || cleanedGeometricUTurnBreach;

  if (cleanedHasUTurn) {
    return {
      ...cleanup,
      passed: false,
      reason: cleanedGeometricUTurnBreach
        ? `cleanup_u_turn_geometry=${cleanup.cleanedGeometricUTurnCount}`
        : "cleanup_u_turn",
    };
  }

  if (
    distanceConfig != null &&
    (
      cleanup.cleanedDistanceKm <
        distanceConfig.acceptableMinKm *
          (mediumLongNoHighwaySportGate ? 0.94 : 1.0) ||
      cleanup.cleanedDistanceKm >
        distanceConfig.acceptableMaxKm *
          (mediumLongNoHighwaySportGate ? 1.22 : 1.0)
    )
  ) {
    return {
      ...cleanup,
      passed: false,
      reason: `cleanup_distance=${cleanup.cleanedDistanceKm.toFixed(1)}km`,
    };
  }

  if (
    !cleanup.startTrimApplied &&
    !cleanup.loopRemovalApplied &&
    cleanup.removedPointPercent <= 0.1 &&
    cleanup.cleanedGeometricUTurnCount === 0
  ) {
    return {
      ...cleanup,
      cleanedCoordinates: cleanup.coordinates,
    };
  }

  const cleanedRoute = cloneRouteWithCoordinates(
    route,
    cleanup.coordinates,
    cleanup.cleanedDistanceKm,
  );
  const cleanedQuality = evaluateRouteQualityCore(
    cleanedRoute,
    routeType,
    options,
  );

  if (
    !mediumLongNoHighwaySportGate && hasFoldLoop(cleanedQuality.reason, cleanup)
  ) {
    return {
      ...cleanup,
      passed: false,
      reason: `cleanup_${cleanedQuality.reason}`,
    };
  }

  if (cleanedQuality.tier === "rejected" && !mediumLongNoHighwaySportGate) {
    return {
      ...cleanup,
      passed: false,
      reason: `cleanup_${cleanedQuality.reason}`,
    };
  }
  // For medium/long no-highway Sport: only reject if the cleaned
  // quality is rejected AND the route also has severe issues that
  // aren't natural alpine serpentines (e.g. massive opposite overlap).
  if (
    mediumLongNoHighwaySportGate &&
    cleanedQuality.tier === "rejected" &&
    cleanedQuality.reason != null &&
    !cleanedQuality.reason.startsWith("u_turn") &&
    !cleanedQuality.reason.startsWith("u_turn_geometry") &&
    !cleanedQuality.reason.startsWith("shape=") &&
    !cleanedQuality.reason.startsWith("hooks=")
  ) {
    return {
      ...cleanup,
      passed: false,
      reason: `cleanup_${cleanedQuality.reason}`,
    };
  }

  return {
    ...cleanup,
    cleanedCoordinates: cleanup.coordinates,
  };
}
