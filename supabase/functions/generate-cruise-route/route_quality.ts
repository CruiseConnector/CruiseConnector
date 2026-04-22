import type {
  Coordinate,
  DistanceConfig,
  RouteMode,
  RouteQualityEvaluation,
  RouteQualityTier,
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
} from "./routing_utils.ts";
import { getRouteDistanceKm } from "./point_to_point.ts";

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

export function calculateRouteOverlapPercent(route: any): number {
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

export function extractRouteCoordinates(route: any): Coordinate[] {
  const raw = route?.geometry?.coordinates;
  if (!Array.isArray(raw)) return [];
  const result: Coordinate[] = [];
  for (const point of raw) {
    const parsed = pointToCoordinate(point);
    if (parsed) result.push(parsed);
  }
  return result;
}

export function countGeometricUTurns(coordinates: Coordinate[]): number {
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

export function removeClientStyleLocalLoops(coordinates: Coordinate[]): {
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

export function estimateClientLoopCleanupImpact(coordinates: Coordinate[]): {
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

export function calculateRouteShapeSignals(route: any): {
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

export function evaluateRouteQuality(
  route: any,
  routeType: "ROUND_TRIP" | "POINT_TO_POINT",
  options?: {
    targetDistanceKm?: number;
    distanceConfig?: DistanceConfig;
    mode?: RouteMode;
    avoidHighways?: boolean;
  },
): RouteQualityEvaluation {
  const coordinateCount = route?.geometry?.coordinates?.length ?? 0;
  const actualDistanceKm = getRouteDistanceKm(route);
  const overlapPercent = calculateRouteOverlapPercent(route);
  const shapeSignals = calculateRouteShapeSignals(route);
  const hasManeuverUTurn = hasUTurnManeuver(route);
  const hasGeometricUTurn = routeType === "ROUND_TRIP" &&
    shapeSignals.geometricUTurnCount > 0;
  const hasUTurn = hasManeuverUTurn || hasGeometricUTurn;
  // Anti-Kraken: Kurvenjagd bekommt einen etwas schärferen Overlap-
  // Threshold, damit echte Out-and-Back-/Ast-Formen (Sackgasse hin+zurück)
  // konsequent als rejected markiert werden. Wert kalibriert auf reale
  // Tal-Geometrie (Dornbirn/Bregenzerwald): 16 fängt Kraken, verschenkt aber
  // keine gültigen Kurven-Loops.
  const isCurveChase = options?.mode === "Kurvenjagd";
  const isSportMode = options?.mode === "Sport Mode";
  const isShortNoHighwaySportRoundTrip = routeType === "ROUND_TRIP" &&
    isSportMode &&
    options?.avoidHighways === true &&
    (options?.targetDistanceKm ?? Number.POSITIVE_INFINITY) <= 60;
  const overlapThreshold = routeType === "ROUND_TRIP"
    ? (isCurveChase ? 15 : 16)
    : (isCurveChase ? 12 : 14);
  const targetDistanceKm = options?.targetDistanceKm ?? 0;
  const distanceConfig = options?.distanceConfig;
  const avoidHighways = options?.avoidHighways === true;
  const distanceDeltaKm = targetDistanceKm > 0
    ? Math.abs(actualDistanceKm - targetDistanceKm)
    : 0;
  // Kurvenjagd strenger bei Haken/Radial-Peaks — das sind die typischen
  // „Äste/Kraken“ (Mapbox stolpert in Sackgasse, kehrt um, nächster Ast).
  // 6 (statt 8) ist genug aggressiv für Anti-Kraken ohne valide Kurven-Loops
  // zu zerschneiden.
  const severeHookCount = routeType === "ROUND_TRIP"
    ? (isCurveChase ? 6 : 8)
    : 4;
  // Kurvenjagd: Reentry/RadialPeaks etwas strenger werten, damit offene
  // Stern-/Astformen früher als "severe" markiert werden, aber nicht so
  // streng, dass normale enge Tal-Loops verworfen werden.
  const severeRoundTripShape = routeType === "ROUND_TRIP" &&
    (
      shapeSignals.centerReentryCount >= 4 ||
      (shapeSignals.radialPeakCount >= (isCurveChase ? 3 : 4) &&
        shapeSignals.middleCoverageRatio < 0.34) ||
      (shapeSignals.middleCoverageRatio < 0.18 &&
        shapeSignals.centralReturnPercent > 18) ||
      (shapeSignals.centralReturnPercent > 28 &&
        shapeSignals.middleCoverageRatio < 0.26) ||
      // Sport: offene Stern-/Vielarm-Formen ohne ausreichende Loop-Fläche
      (isSportMode === true &&
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
          (isShortNoHighwaySportRoundTrip ? 16 : 24) &&
        shapeSignals.middleCoverageRatio <
          (isShortNoHighwaySportRoundTrip ? 0.46 : 0.36)
      ) ||
      shapeSignals.foldedLoopPenalty >
        (isShortNoHighwaySportRoundTrip ? 56 : 74)
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
  const shortSportOverlapMiss = isShortNoHighwaySportRoundTrip &&
    overlapPercent > 22;

  if (hasUTurn) {
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

  if (isShortNoHighwaySportRoundTrip) {
    const loopCleanup = estimateClientLoopCleanupImpact(
      extractRouteCoordinates(route),
    );
    shapeSignals.loopCleanupRemovedPercent = loopCleanup.removedPointPercent;
    shapeSignals.loopCleanupDistanceRetentionRatio =
      loopCleanup.distanceRetentionRatio;
    shapeSignals.loopCleanupCount = loopCleanup.removedLoops;
    shapeSignals.loopCleanupDistanceKm = loopCleanup.cleanedDistanceKm;
    shapeSignals.loopCleanupUTurnCount = loopCleanup.cleanedGeometricUTurnCount;
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
      shapeSignals.loopCleanupUTurnCount > 0 ||
      clientCleanupWouldMissDistance ||
      clientCleanupWouldMissPresentationBand ||
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
  if (shapeSignals.hookCount >= severeHookCount) {
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
