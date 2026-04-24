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

export function buildPointToPointScenicWaypoints({
  start,
  destination,
  mode,
  targetDistance,
  detourLevel,
  detourFactor,
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
  offsetSide?: number;
  waypointShapeFactor?: number;
  zigzagWaypoints?: boolean;
  randomSeed?: number;
  simplifyWaypoints?: boolean;
  maxWaypoints?: number;
  robustFallback?: boolean;
}): Coordinate[] {
  const directDistanceKm = calculateDistance(start, destination);
  if (directDistanceKm < 1.5) {
    return [start, destination];
  }

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

  const effectiveFactor = Math.max(
    detourFactor ?? 1.0,
    1.0 + scenicModeBoost + detourBoost * fallbackScale,
  );
  const desiredDistanceKm = Math.max(
    targetDistance ?? 0,
    directDistanceKm * effectiveFactor,
  );
  const minimumExtraDistanceKm = detourLevel === 1
    ? 7.0
    : detourLevel === 2
    ? 13.5
    : detourLevel >= 3
    ? 24.0
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
  const rawFractions = waypointCount === 1
    ? [onePointFraction]
    : waypointCount === 2
    ? twoPointTemplate
    : waypointCount === 3
    ? [0.2, 0.5, 0.8]
    : waypointCount === 4
    ? [0.15, 0.38, 0.62, 0.85]
    : [0.12, 0.3, 0.5, 0.7, 0.88];
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
  const baseSide = requestedOffsetSide ??
    (seededUnit(randomSeed + detourLevel + Math.round(directDistanceKm)) >= 0.5
      ? 1
      : -1);

  // Offset-Limits — drastischer gespreizt zwischen Klein/Mittel/Groß,
  // damit Mapbox tatsächlich verschiedene Korridore zurückliefert.
  let maxOffsetKm = detourLevel === 1
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
  let minOffsetKm = detourLevel === 1
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
      baseBearing + side * (90 + corridorBearingBias + angleDrift),
    );
  });

  const corridorWaypoints = smoothWaypointChain(
    scenicWaypoints,
    simplifyWaypoints ? (robustFallback ? 0.16 : 0.24) : 0.18,
  );
  const minCorridorRadiusKm = Math.max(
    directDistanceKm * (
      simplifyWaypoints ? (robustFallback ? 0.12 : 0.14) : 0.18
    ),
    0.9,
  );
  const maxCorridorRadiusKm = Math.max(
    minCorridorRadiusKm + 0.4,
    directDistanceKm * (
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
      ? directDistanceKm * 1.12
      : detourLevel === 2
      ? directDistanceKm * 1.32
      : detourLevel >= 3
      ? directDistanceKm * 1.60
      : directDistanceKm * 1.04
    : detourLevel === 1
    ? directDistanceKm * 1.15
    : detourLevel === 2
    ? directDistanceKm * 1.40
    : detourLevel >= 3
    ? directDistanceKm * 1.75
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
      ? 1.34
      : detourLevel === 2
      ? 1.44
      : detourLevel >= 3
      ? 1.56
      : 1.24
    : detourLevel === 1
    ? 1.28
    : detourLevel === 2
    ? 1.38
    : detourLevel >= 3
    ? 1.50
    : 1.20;
  const directMultiplier = relaxed
    ? detourLevel === 1
      ? 1.78
      : detourLevel === 2
      ? 2.25
      : detourLevel >= 3
      ? 3.10
      : 1.48
    : detourLevel === 1
    ? 1.65
    : detourLevel === 2
    ? 2.10
    : detourLevel >= 3
    ? 2.95
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

  return Math.max(
    minimumDistanceKm + slackKm,
    Math.max(targetKm * targetMultiplier, directDistanceKm * directMultiplier),
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
