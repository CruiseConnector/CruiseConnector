import type { Coordinate, RouteMode } from "./routing_types.ts";
import {
  calculateBearing,
  calculateDestination,
  calculateDistance,
  interpolateCoordinate,
  seededUnit,
} from "./routing_utils.ts";
import {
  enforceWaypointRadiusBand,
  smoothWaypointChain,
} from "./roundtrip_waypoints.ts";

export type PointToPointCorridorFamily =
  | "direct_valley"
  | "west_flat"
  | "east_valley"
  | "mountain_curvy"
  | "wide_scenic"
  | "smooth_sport"
  | "explorer_alternate_sector";

function stableStringHash(value: string): number {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function uniqueCorridorFamilies(
  families: PointToPointCorridorFamily[],
): PointToPointCorridorFamily[] {
  return [...new Set(families)];
}

export function selectPointToPointCorridorFamilies({
  mode,
  detourLevel,
  randomSeed = 0,
  variantHint,
  maxCandidateAttempts = 6,
}: {
  mode?: RouteMode;
  detourLevel: number;
  randomSeed?: number;
  variantHint?: string;
  maxCandidateAttempts?: number;
}): PointToPointCorridorFamily[] {
  const baseOrder: PointToPointCorridorFamily[] = mode === "Kurvenjagd"
    ? [
      "mountain_curvy",
      "east_valley",
      "west_flat",
      "wide_scenic",
      "explorer_alternate_sector",
      "smooth_sport",
      "direct_valley",
    ]
    : mode === "Entdecker"
    ? [
      "explorer_alternate_sector",
      "wide_scenic",
      "west_flat",
      "east_valley",
      "mountain_curvy",
      "smooth_sport",
      "direct_valley",
    ]
    : mode === "Abendrunde"
    ? [
      "direct_valley",
      "smooth_sport",
      "east_valley",
      "west_flat",
      "explorer_alternate_sector",
      "wide_scenic",
      "mountain_curvy",
    ]
    : [
      "smooth_sport",
      "east_valley",
      "west_flat",
      "direct_valley",
      "wide_scenic",
      "explorer_alternate_sector",
      "mountain_curvy",
    ];
  const largeOrder = detourLevel >= 3
    ? uniqueCorridorFamilies([
      "wide_scenic",
      "mountain_curvy",
      ...baseOrder,
      "explorer_alternate_sector",
    ])
    : baseOrder;
  const hash = stableStringHash(`${variantHint ?? ""}|${randomSeed}`);
  const offset = largeOrder.length === 0 ? 0 : hash % largeOrder.length;
  const rotated = [
    ...largeOrder.slice(offset),
    ...largeOrder.slice(0, offset),
  ];
  const limit = Math.max(
    1,
    Math.min(rotated.length, Math.max(3, maxCandidateAttempts)),
  );
  return rotated.slice(0, limit);
}

export function buildPointToPointScenicWaypoints({
  start,
  destination,
  mode,
  targetDistance,
  detourLevel,
  detourFactor,
  directReferenceDistanceKm,
  corridorFamily,
  offsetSide,
  waypointShapeFactor,
  zigzagWaypoints = false,
  randomSeed = 0,
  simplifyWaypoints = false,
  maxWaypoints,
  robustFallback = false,
}: {
  start: Coordinate;
  destination: Coordinate;
  mode?: RouteMode;
  targetDistance?: number;
  detourLevel: number;
  detourFactor?: number;
  directReferenceDistanceKm?: number;
  corridorFamily?: PointToPointCorridorFamily;
  offsetSide?: number;
  waypointShapeFactor?: number;
  zigzagWaypoints?: boolean;
  randomSeed?: number;
  simplifyWaypoints?: boolean;
  maxWaypoints?: number;
  robustFallback?: boolean;
}): Coordinate[] {
  const directLineDistanceKm = calculateDistance(start, destination);
  const directDistanceKm = Math.max(
    directLineDistanceKm,
    directReferenceDistanceKm ?? 0,
  );
  if (directLineDistanceKm < 1.5 || detourLevel <= 0) {
    return [start, destination];
  }
  const family = corridorFamily ??
    (mode === "Kurvenjagd"
      ? "mountain_curvy"
      : mode === "Entdecker"
      ? "explorer_alternate_sector"
      : mode === "Abendrunde"
      ? "direct_valley"
      : "smooth_sport");

  // Stil-Boost: wie viel Extra-Distanz der Stil zur Route hinzufügt
  // Kurvenjagd braucht mehr Umweg (enge Straßen = längere Wege)
  const scenicModeBoost = mode === "Kurvenjagd"
    ? 0.30
    : mode === "Entdecker"
    ? 0.35
    : mode === "Sport Mode"
    ? 0.18
    : mode === "Abendrunde"
    ? 0.12
    : 0.0;

  // Umweg-Boost an die neuen Flutter-Fenster gekoppelt:
  // Klein zielt auf 1.32× direkt, Mittel auf 1.65×, Groß auf 2.10×.
  // (Vorher 1.26 / 1.40 / 1.70 → Groß war zu nah an Mittel.)
  const detourBoost = detourLevel === 1
    ? 0.36
    : detourLevel === 2
    ? 0.62
    : detourLevel >= 3
    ? 1.08
    : 0.0;
  const fallbackScale = robustFallback
    ? detourLevel >= 3 ? 0.82 : detourLevel === 2 ? 0.86 : 0.92
    : 1.0;
  const isVeryShortCorridor = directDistanceKm < 12;
  const isShortCorridor = directDistanceKm < 18;

  const effectiveFactor = Math.max(
    detourFactor ?? 1.0,
    1.0 + scenicModeBoost + detourBoost * fallbackScale,
  );
  const desiredDistanceKm = Math.max(
    targetDistance ?? 0,
    directDistanceKm * effectiveFactor,
  );
  const minimumExtraDistanceKm = detourLevel === 1
    ? isShortCorridor ? 3.8 : 7.0
    : detourLevel === 2
    ? isVeryShortCorridor ? 7.0 : isShortCorridor ? 9.0 : 13.5
    : detourLevel >= 3
    ? isVeryShortCorridor ? 12.0 : isShortCorridor ? 16.0 : 24.0
    : 3.0;
  let extraDistanceKm = Math.max(
    minimumExtraDistanceKm,
    desiredDistanceKm - directDistanceKm,
  );
  if (simplifyWaypoints) {
    extraDistanceKm *= detourLevel >= 2 ? 0.82 : 0.9;
  }

  // Waypoint-Anzahl: je Umweg-Level + Seed-Variation.
  // Klein kann auf längeren Strecken 1 oder 2 Wegpunkte nutzen.
  let waypointCount: number;
  if (detourLevel >= 3) {
    waypointCount = robustFallback ? 2 : directDistanceKm >= 26 ? 3 : 2;
  } else if (detourLevel >= 2) {
    waypointCount = robustFallback
      ? directDistanceKm >= 22 ? 2 : 1
      : directDistanceKm >= 32
      ? 3
      : 2;
  } else if (detourLevel >= 1) {
    const useTwoWaypoints = directDistanceKm >= 18 &&
      (mode === "Kurvenjagd" || mode === "Entdecker" ||
        directDistanceKm >= 26) &&
      seededUnit(randomSeed + Math.round(directDistanceKm * 10)) > 0.22;
    waypointCount = useTwoWaypoints ? 2 : 1;
  } else {
    waypointCount = 0; // Direkt: keine Extra-Waypoints
  }
  if (directDistanceKm < 12) waypointCount = Math.min(waypointCount, 2);
  if (directDistanceKm < 6) waypointCount = Math.min(waypointCount, 1);
  if (isShortCorridor && detourLevel === 2 && robustFallback) {
    waypointCount = Math.min(waypointCount, 1);
  }
  if (simplifyWaypoints) {
    const minimumWaypoints = detourLevel >= 2 ? 2 : 1;
    const cappedWaypoints = Math.max(
      minimumWaypoints,
      Math.min(3, maxWaypoints ?? (detourLevel >= 3 ? 2 : 1)),
    );
    waypointCount = Math.min(waypointCount, cappedWaypoints);
  }

  // Fractions: wo auf der A→B Linie werden die Waypoints platziert
  const onePointFraction = 0.50 + (seededUnit(randomSeed + 211) - 0.5) * 0.24;
  const twoPointTemplate = seededUnit(randomSeed + 307) >= 0.5
    ? [0.28, 0.72]
    : [0.35, 0.67];
  const familyFractions = family === "direct_valley" && waypointCount >= 2
    ? [0.34, 0.66]
    : family === "mountain_curvy" && waypointCount >= 3
    ? [0.24, 0.52, 0.78]
    : family === "wide_scenic" && waypointCount >= 3
    ? [0.18, 0.50, 0.82]
    : family === "explorer_alternate_sector" && waypointCount >= 2
    ? waypointCount >= 3 ? [0.22, 0.52, 0.80] : [0.30, 0.72]
    : null;
  const rawFractions = familyFractions ??
    (waypointCount === 1
      ? [onePointFraction]
      : waypointCount === 2
      ? twoPointTemplate
      : waypointCount === 3
      ? [0.2, 0.5, 0.8]
      : waypointCount === 4
      ? [0.15, 0.38, 0.62, 0.85]
      : [0.12, 0.3, 0.5, 0.7, 0.88]);
  const fractionJitter = detourLevel === 1
    ? 0.08
    : detourLevel === 2
    ? 0.06
    : 0.05;
  const fractions = rawFractions
    .map((fraction, index) => {
      const jitter = (seededUnit(randomSeed + 401 + index * 29) - 0.5) * 2 *
        fractionJitter;
      return Math.min(0.9, Math.max(0.1, fraction + jitter));
    })
    .sort((a, b) => a - b);

  const baseBearing = calculateBearing(start, destination);
  const familyBearingBoost = family === "wide_scenic"
    ? 10
    : family === "mountain_curvy"
    ? 14
    : family === "explorer_alternate_sector"
    ? 8
    : family === "direct_valley"
    ? -8
    : 0;
  const corridorBearingBias = detourLevel >= 3
    ? robustFallback ? 18 : 32
    : detourLevel === 2
    ? robustFallback ? 14 : 22
    : detourLevel === 1
    ? 14
    : 0;
  // Seite determiniert durch Seed — aber bei Entdecker wechselnd pro WP
  const requestedOffsetSide = offsetSide === -1
    ? -1
    : offsetSide === 1
    ? 1
    : null;
  const familySideOverride = family === "west_flat"
    ? -1
    : family === "east_valley"
    ? 1
    : null;
  const baseSide = requestedOffsetSide ??
    familySideOverride ??
    (seededUnit(randomSeed + detourLevel + Math.round(directDistanceKm)) >= 0.5
      ? 1
      : -1);

  // Offset-Limits — drastischer gespreizt zwischen Klein/Mittel/Groß,
  // damit Mapbox tatsächlich verschiedene Korridore zurückliefert.
  let maxOffsetKm = isShortCorridor
    ? detourLevel === 1
      ? Math.max(
        2.6,
        Math.min(directDistanceKm * 0.34, extraDistanceKm * 0.58 + 1.2),
      )
      : detourLevel === 2
      ? Math.max(
        4.2,
        Math.min(directDistanceKm * 0.52, extraDistanceKm * 0.68 + 1.8),
      )
      : Math.max(
        6.2,
        Math.min(directDistanceKm * 0.72, extraDistanceKm * 0.78 + 2.4),
      )
    : detourLevel === 1
    ? Math.max(
      4.5,
      Math.min(directDistanceKm * 0.36, extraDistanceKm * 0.85 + 3.0),
    )
    : detourLevel === 2
    ? Math.max(
      7.5,
      Math.min(directDistanceKm * 0.62, extraDistanceKm * 0.95 + 5.0),
    )
    : Math.max(
      12.0,
      Math.min(directDistanceKm * 0.88, extraDistanceKm * 1.10 + 8.0),
    );
  let minOffsetKm = isShortCorridor
    ? detourLevel === 1
      ? Math.min(maxOffsetKm, Math.max(1.5, maxOffsetKm * 0.42))
      : detourLevel === 2
      ? Math.min(maxOffsetKm, Math.max(2.4, maxOffsetKm * 0.45))
      : Math.min(maxOffsetKm, Math.max(3.6, maxOffsetKm * 0.48))
    : detourLevel === 1
    ? Math.min(maxOffsetKm, Math.max(3.0, maxOffsetKm * 0.55))
    : detourLevel === 2
    ? Math.min(maxOffsetKm, Math.max(5.5, maxOffsetKm * 0.55))
    : Math.min(maxOffsetKm, Math.max(8.5, maxOffsetKm * 0.55));
  if (simplifyWaypoints) {
    maxOffsetKm *= robustFallback
      ? detourLevel >= 2 ? 0.62 : 0.72
      : detourLevel >= 2
      ? 0.74
      : 0.80;
    minOffsetKm *= robustFallback
      ? detourLevel >= 2 ? 0.60 : 0.70
      : detourLevel >= 2
      ? 0.72
      : 0.78;
  }
  const familyOffsetScale = family === "direct_valley"
    ? 0.58
    : family === "smooth_sport"
    ? 0.78
    : family === "mountain_curvy"
    ? 1.16
    : family === "wide_scenic"
    ? 1.28
    : family === "explorer_alternate_sector"
    ? 1.08
    : 0.96;
  maxOffsetKm *= familyOffsetScale;
  minOffsetKm *= Math.max(0.52, Math.min(1.15, familyOffsetScale * 0.84));

  const scenicWaypoints = fractions.map((fraction, index) => {
    const basePoint = interpolateCoordinate(start, destination, fraction);
    const variationSeed = randomSeed + (index + 1) * 17;
    const variation = 0.85 + seededUnit(variationSeed) * 0.35;

    // Stilspezifische Offset-Berechnung
    let arcFactor: number;
    let angleDrift: number;
    let side: number;

    switch (mode) {
      case "Kurvenjagd":
        // Curvy but controlled corridor to avoid hooks/stubs.
        arcFactor = 0.90 + index * 0.16;
        angleDrift = (seededUnit(variationSeed + 7) - 0.5) * 26;
        side = waypointCount >= 3 && index == waypointCount - 1
          ? -baseSide
          : baseSide;
        break;
      case "Entdecker":
        // Keep one dominant side with optional single crossover.
        arcFactor = 0.84 + seededUnit(variationSeed + 3) * 0.46;
        angleDrift = (seededUnit(variationSeed + 7) - 0.5) * 34;
        side = waypointCount >= 3 && index === 1 &&
            seededUnit(variationSeed + 11) >= 0.58
          ? -baseSide
          : baseSide;
        break;
      case "Abendrunde":
        // Sanfter, gleichmäßiger Bogen — alle auf einer Seite, nah dran
        arcFactor = 0.5 + index * 0.1;
        angleDrift = (seededUnit(variationSeed + 7) - 0.5) * 12;
        side = baseSide;
        break;
      default: // Sport Mode
        // Weicher, konsistenter Bogen statt Haken/S-Knicke.
        arcFactor = detourLevel === 1
          ? 0.86 + index * 0.14
          : 0.72 + index * 0.16;
        angleDrift = (seededUnit(variationSeed + 7) - 0.5) *
          (detourLevel === 1 ? 22 : 18);
        side = baseSide;
    }

    if (family === "direct_valley") {
      arcFactor *= 0.64;
      angleDrift *= 0.45;
      side = baseSide;
    } else if (family === "smooth_sport") {
      arcFactor *= 0.82;
      angleDrift *= 0.62;
      side = baseSide;
    } else if (family === "mountain_curvy") {
      arcFactor *= 1.18;
      angleDrift += (index % 2 === 0 ? 1 : -1) * 8;
      side = waypointCount >= 3 && index === waypointCount - 1
        ? -baseSide
        : baseSide;
    } else if (family === "wide_scenic") {
      arcFactor *= 1.28;
      angleDrift += index % 2 === 0 ? 6 : -6;
      side = baseSide;
    } else if (family === "explorer_alternate_sector") {
      arcFactor *= 1.08;
      side = index % 2 === 1 ? -baseSide : baseSide;
    }

    if (zigzagWaypoints) {
      side = waypointCount >= 3 && index == waypointCount - 1
        ? -baseSide
        : baseSide;
      angleDrift += 5;
    }
    if (
      typeof waypointShapeFactor === "number" &&
      Number.isFinite(waypointShapeFactor)
    ) {
      arcFactor *= Math.max(
        robustFallback ? 0.7 : 0.75,
        Math.min(2.0, waypointShapeFactor),
      );
    }

    const offsetKm = Math.min(
      maxOffsetKm,
      Math.max(minOffsetKm, extraDistanceKm * arcFactor * variation),
    );

    return calculateDestination(
      basePoint,
      offsetKm,
      baseBearing +
        side * (90 + corridorBearingBias + familyBearingBoost + angleDrift),
    );
  });

  const corridorWaypoints = smoothWaypointChain(
    scenicWaypoints,
    simplifyWaypoints ? (robustFallback ? 0.16 : 0.24) : 0.18,
  );
  const minCorridorRadiusKm = Math.max(
    directLineDistanceKm * (
      simplifyWaypoints ? (robustFallback ? 0.12 : 0.14) : 0.18
    ),
    0.9,
  );
  const maxCorridorRadiusKm = Math.max(
    minCorridorRadiusKm + 0.4,
    directLineDistanceKm * (
      detourLevel >= 2 ? (robustFallback ? 0.86 : 0.92) : 0.84
    ),
  );

  return [
    start,
    ...enforceWaypointRadiusBand(
      start,
      corridorWaypoints,
      minCorridorRadiusKm,
      maxCorridorRadiusKm,
    ),
    destination,
  ];
}

export function getRouteDistanceKm(route: any): number {
  return typeof route?.distance === "number" ? route.distance / 1000 : 0;
}

export function getPointToPointMinimumDistanceKm(
  directDistanceKm: number,
  _targetDistance: number | undefined,
  detourLevel: number,
  relaxed = false,
): number {
  const minByVariant = relaxed
    ? detourLevel === 1
      ? directDistanceKm * 1.16
      : detourLevel === 2
      ? directDistanceKm * 1.42
      : detourLevel >= 3
      ? directDistanceKm * 1.72
      : directDistanceKm * 1.04
    : detourLevel === 1
    ? directDistanceKm * 1.20
    : detourLevel === 2
    ? directDistanceKm * 1.50
    : detourLevel >= 3
    ? directDistanceKm * 1.90
    : directDistanceKm * 1.08;
  const paddingKm = relaxed
    ? detourLevel === 1
      ? 0.5
      : detourLevel === 2
      ? 2.0
      : detourLevel >= 3
      ? 4.5
      : 0.5
    : detourLevel === 1
    ? 1.0
    : detourLevel === 2
    ? 3.0
    : detourLevel >= 3
    ? 6.0
    : 1.0;

  return Math.max(minByVariant, directDistanceKm + paddingKm);
}

export function getPointToPointMaximumDistanceKm(
  directDistanceKm: number,
  targetDistance: number | undefined,
  detourLevel: number,
  relaxed = false,
): number {
  const targetKm = Math.max(
    targetDistance ?? directDistanceKm,
    directDistanceKm,
  );
  const targetMultiplier = relaxed
    ? detourLevel === 1
      ? 1.16
      : detourLevel === 2
      ? 1.18
      : detourLevel >= 3
      ? 1.20
      : 1.24
    : detourLevel === 1
    ? 1.12
    : detourLevel === 2
    ? 1.14
    : detourLevel >= 3
    ? 1.18
    : 1.20;
  const directMultiplier = relaxed
    ? detourLevel === 1
      ? 1.56
      : detourLevel === 2
      ? 2.04
      : detourLevel >= 3
      ? 3.00
      : 1.48
    : detourLevel === 1
    ? 1.48
    : detourLevel === 2
    ? 1.95
    : detourLevel >= 3
    ? 2.85
    : 1.40;
  const slackKm = relaxed
    ? detourLevel === 1
      ? 4.0
      : detourLevel === 2
      ? 6.5
      : detourLevel >= 3
      ? 11.0
      : 3.0
    : detourLevel === 1
    ? 3.0
    : detourLevel === 2
    ? 5.5
    : detourLevel >= 3
    ? 10.0
    : 2.5;
  const minimumDistanceKm = getPointToPointMinimumDistanceKm(
    directDistanceKm,
    targetDistance,
    detourLevel,
    relaxed,
  );

  const targetBound = targetKm * targetMultiplier;
  const directBound = directDistanceKm * directMultiplier + slackKm;
  return Math.max(
    minimumDistanceKm + slackKm,
    Math.min(directBound, Math.max(targetBound, directDistanceKm)),
  );
}

export function isPointToPointDetourAcceptable(
  route: any,
  directDistanceKm: number,
  targetDistance: number | undefined,
  detourLevel: number,
  relaxed = false,
): boolean {
  const minimumDistanceKm = getPointToPointMinimumDistanceKm(
    directDistanceKm,
    targetDistance,
    detourLevel,
    relaxed,
  );
  const maximumDistanceKm = getPointToPointMaximumDistanceKm(
    directDistanceKm,
    targetDistance,
    detourLevel,
    relaxed,
  );
  const distanceKm = getRouteDistanceKm(route);
  return distanceKm >= minimumDistanceKm && distanceKm <= maximumDistanceKm;
}
