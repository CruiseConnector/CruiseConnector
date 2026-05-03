import type {
  Coordinate,
  DistanceConfig,
  PreferenceArea,
  PreferenceMatchSummary,
  RoundTripCandidatePlan,
  RoundTripSearchResult,
  RouteMode,
  RouteQualityEvaluation,
} from "./routing_types.ts";
import {
  calculateDistance,
  normalizeExcludeParams,
  normalizeHint,
  relaxStreetExcludes,
  stableStringHash,
} from "./routing_utils.ts";
import { buildRoundTripWaypointCandidates } from "./roundtrip_waypoints.ts";
import {
  getMapboxRouteDetailed,
  getRetryKindFromMapboxFailure,
} from "./mapbox_client.ts";
import {
  buildRouteFingerprintFromRoute,
  evaluateRouteCleanupGate,
  evaluateRouteQuality,
} from "./route_quality.ts";
import { debugLog, debugWarn } from "./routing_debug.ts";

function prioritizeCandidatePlans(
  plans: RoundTripCandidatePlan[],
  phaseName: string,
  variantHint?: string,
  fingerprintHint?: string,
  options?: {
    shortCurvyRoundTripFallback?: boolean;
    mode?: string;
    avoidHighways?: boolean;
    targetDistanceKm?: number;
  },
): RoundTripCandidatePlan[] {
  if (plans.length <= 1) return plans;

  const normalizedVariant = normalizeHint(variantHint)?.toLowerCase();
  const genericVariantTokens = new Set([
    "rt",
    "ab",
    "sport",
    "mode",
    "kurvenjagd",
    "abendrunde",
    "entdecker",
    "curve",
    "evening",
    "explore",
    "h0",
    "h1",
  ]);
  const preferredTokens = normalizedVariant
    ? normalizedVariant.split(/[^a-z0-9]+/i).filter((token) =>
      token.length >= 3 &&
      !genericVariantTokens.has(token) &&
      !/^k\d+$/.test(token) &&
      !/^\d+$/.test(token)
    )
    : [];

  const preferred = preferredTokens.length === 0
    ? []
    : plans.filter((plan) =>
      preferredTokens.some((token) => plan.label.toLowerCase().includes(token))
    );
  const remaining = preferredTokens.length === 0
    ? [...plans]
    : plans.filter((plan) => !preferred.includes(plan));

  if (remaining.length <= 1) {
    return [...preferred, ...remaining];
  }

  const normalizedMode = options?.mode?.trim().toLowerCase();
  const preferNoHighwayRoundTrip = options?.avoidHighways === true;
  const preferWideSportAvoidHighways = options?.avoidHighways === true &&
    (normalizedMode === "sport mode" || normalizedMode === "sport") &&
    (options?.targetDistanceKm ?? Number.POSITIVE_INFINITY) <= 80;
  const preferStableShortSportAvoidHighways = preferWideSportAvoidHighways &&
    (options?.targetDistanceKm ?? Number.POSITIVE_INFINITY) <= 60;
  const preferShortSportRoundTrip = options?.avoidHighways !== true &&
    (normalizedMode === "sport mode" || normalizedMode === "sport") &&
    (options?.targetDistanceKm ?? Number.POSITIVE_INFINITY) <= 60;
  const noHighwayTargetKm = options?.targetDistanceKm ??
    Number.POSITIVE_INFINITY;
  const noHighwayOrderTokens = noHighwayTargetKm <= 60
    ? normalizedMode === "kurvenjagd"
      ? [
        "nohw-sector-curvy",
        "nohw-short-curve-oval-west",
        "nohw-short-curve-oval-northwest",
        "nohw-short-curve-oval-southwest",
      ]
      : normalizedMode === "entdecker"
      ? [
        "nohw-sector-explore",
        "sport-paired-west",
        "sport-paired-northwest",
        "sport-paired-southwest",
      ]
      : normalizedMode === "abendrunde"
      ? [
        "nohw-sector-evening",
        "sport-paired-west",
        "sport-paired-northwest",
        "sport-paired-southwest",
      ]
      : [
        "sport-paired-west",
        "sport-paired-northwest",
        "sport-paired-southwest",
        "sport-paired-west-wide",
        "sport-flow-regional",
        "nohw-sector-sport",
      ]
    : noHighwayTargetKm <= 85
    ? normalizedMode === "sport mode" || normalizedMode === "sport"
      ? [
        "nohw-sector-sport",
        "nohw-medium-sport-cardinal-rheintal",
        "nohw-medium-sport-orbital-rheintal-north",
        "nohw-medium-sport-orbital-rheintal-northwest",
        "nohw-medium-sport-orbital-rheintal-west",
        "nohw-medium-sport-orbital-6soft",
        "nohw-medium-sport-orbital-rheintal-loop",
        "nohw-medium-sport-orbital-broad-west",
      ]
      : [
        normalizedMode === "kurvenjagd"
          ? "nohw-sector-curvy"
          : normalizedMode === "entdecker"
          ? "nohw-sector-explore"
          : "nohw-sector-evening",
        "nohw-medium-oval-west",
        "nohw-medium-rhine-south",
        "nohw-medium-oval-northwest",
        "nohw-medium-oval-southwest",
      ]
    : normalizedMode === "kurvenjagd"
    ? [
      "nohw-sector-curvy",
      "nohw-curve-rescue-northeast",
      "nohw-long-oval-northwest",
      "nohw-long-oval-west",
      "nohw-long-oval-southwest",
      "nohw-long-oval-west-wide",
    ]
    : normalizedMode === "entdecker"
    ? [
      "nohw-sector-explore",
      "nohw-long-oval-west",
      "nohw-long-oval-northwest",
      "nohw-long-oval-southwest",
      "nohw-long-oval-west-wide",
    ]
    : normalizedMode === "abendrunde"
    ? [
      "nohw-sector-evening",
      "nohw-long-oval-west",
      "nohw-long-oval-northwest",
      "nohw-long-oval-southwest",
      "nohw-long-oval-west-wide",
    ]
    : [
      "nohw-sector-sport",
      "nohw-long-oval-west",
      "nohw-long-oval-northwest",
      "nohw-long-oval-southwest",
      "nohw-long-oval-west-wide",
    ];
  const styleOrderTokens = preferNoHighwayRoundTrip
    ? noHighwayOrderTokens
    : normalizedMode === "kurvenjagd"
    ? [
      "curve-loop-scout",
      "curve-orbital-core",
      "curve-loop-tight",
      "curve-loop-wide",
      "curve-triangle",
      "curve-zigzag-core",
    ]
    : preferWideSportAvoidHighways
    ? (preferStableShortSportAvoidHighways
      ? phaseName === "fallback"
        ? [
          "sport-paired-northwest-wide",
          "sport-paired-northwest",
          "sport-paired-northwest-long",
          "sport-paired-west-wide",
          "sport-paired-west",
          "sport-paired-west-long",
          "sport-paired-southwest",
          "sport-paired-southwest-wide",
        ]
        : [
          "sport-paired-northwest-wide",
          "sport-paired-northwest",
          "sport-paired-northwest-long",
          "sport-paired-west-wide",
          "sport-paired-west",
          "sport-paired-west-long",
          "sport-paired-southwest",
          "sport-paired-southwest-wide",
        ]
      : [
        "sport-loop-wide",
        "sport-loop-extended",
        "sport-loop-scout",
        "sport-cardinal-ellipse",
        "fallback-loop-4",
        "fallback-loop-3",
        "fallback-cardinal",
        "sport-orbital-flow",
        "sport-loop-flow",
      ])
    : normalizedMode === "sport mode" || normalizedMode === "sport"
    ? [
      // Loops/cardinal first: orbitals alone saturated u_turn rejects when
      // they monopolized the first max_candidate_attempts slots.
      "sport-loop-flow",
      "sport-loop-wide",
      "sport-cardinal-ellipse",
      "sport-hw-zigzag-rheintal",
      "sport-hw-orbital-rheintal-north",
      "sport-hw-orbital-rheintal-northwest",
      "sport-hw-orbital-rheintal-west",
      "sport-hw-orbital-equal-sweep",
      "sport-hw-orbital-soft-5",
      "sport-hw-cardinal-rheintal",
      "sport-paired-hw-corridor",
      "sport-orbital-flow",
      "sport-loop-extended",
      "sport-loop-scout",
    ]
    : normalizedMode === "abendrunde"
    ? [
      "evening-cardinal-soft",
      "evening-triangle-compact",
      "evening-orbital-soft",
      "evening-loop-soft",
    ]
    : normalizedMode === "entdecker"
    ? [
      "explore-cardinal-wide",
      "explore-loop-scout",
      "explore-loop-offset",
      "explore-triangle",
      "explore-orbital-wide",
      "explore-loop-wide",
      "explore-loop-far",
    ]
    : [];
  const styleRank = (label: string): number => {
    const lower = label.toLowerCase();
    let bestIndex = -1;
    let bestLen = -1;
    for (let i = 0; i < styleOrderTokens.length; i++) {
      const token = styleOrderTokens[i];
      if (lower.includes(token) && token.length > bestLen) {
        bestLen = token.length;
        bestIndex = i;
      }
    }
    return bestIndex >= 0 ? bestIndex : styleOrderTokens.length;
  };
  if (styleOrderTokens.length > 0) {
    remaining.sort((a, b) => styleRank(a.label) - styleRank(b.label));
  }

  if (
    (preferWideSportAvoidHighways || preferNoHighwayRoundTrip ||
      preferShortSportRoundTrip) &&
    remaining.length > 1
  ) {
    const prioritized = remaining.filter((plan) =>
      styleRank(plan.label) < styleOrderTokens.length
    );
    const deferred = remaining.filter((plan) => !prioritized.includes(plan));
    if (prioritized.length > 1) {
      const normalizedFingerprint = normalizeHint(fingerprintHint);
      const rotationSeed = normalizedFingerprint
        ? stableStringHash(`${phaseName}:${normalizedFingerprint}`)
        : 0;
      const phaseShift = preferNoHighwayRoundTrip
        ? phaseName === "balanced" ? 4 : phaseName === "fallback" ? 8 : 0
        : 0;
      const noHighwayMediumVariantIndex = normalizedVariant?.match(
        /-k\d{2,3}-(\d+)-/i,
      )?.[1];
      const noHighwayRotationLimit = preferNoHighwayRoundTrip
        ? Math.max(1, Math.min(12, prioritized.length))
        : 1;
      const rotationLimit = preferNoHighwayRoundTrip
        ? noHighwayRotationLimit
        : preferShortSportRoundTrip
        // Highway short Sport: rotation pushed 3-WP rescue / orbitals ahead of
        // loop-flow and starved the first strict slice — keep canonical order.
        ? 1
        : preferStableShortSportAvoidHighways
        ? Math.max(1, Math.min(3, prioritized.length))
        : Math.max(1, Math.min(4, prioritized.length));
      const startIndex = preferNoHighwayRoundTrip &&
          noHighwayMediumVariantIndex != null &&
          noHighwayRotationLimit > 1
        ? (Number.parseInt(noHighwayMediumVariantIndex, 10) + phaseShift) %
          rotationLimit
        : (rotationSeed + phaseShift) % rotationLimit;
      const rotatedPriority = prioritized.slice(startIndex).concat(
        prioritized.slice(0, startIndex),
      );
      return [...preferred, ...rotatedPriority, ...deferred];
    }
    return [...preferred, ...prioritized, ...deferred];
  }

  const safer = remaining.filter((plan) => {
    const label = plan.label.toLowerCase();
    return !label.includes("return") && !label.includes("open");
  });
  const riskier = remaining.filter((plan) => !safer.includes(plan));

  const normalizedFingerprint = normalizeHint(fingerprintHint);
  const rotationSeed = normalizedFingerprint
    ? stableStringHash(`${phaseName}:${normalizedFingerprint}`)
    : 0;
  const orderedPool = safer.length > 0 ? [...safer, ...riskier] : remaining;
  // Ohne echten Fingerprint starteten strict/balanced/fallback bisher alle
  // bei denselben ersten Plänen. Dadurch wurden z.B. Sport-Loops immer mit
  // denselben zwei Grundformen versucht und gute Fallback-Formen nie erreicht.
  //
  // Kurze Kurvenjagd-Roundtrips: Der 65%-Offset in "fallback" hat die Rotation
  // oft genau auf fallback-cardinal / fallback-triangle-* gesetzt, obwohl die
  // brauchbareren curve-*-Pläne (loop-scout, orbital-core, zigzag-core) schon
  // früh in der Liste stehen. Dort bleibt offset 0 — Variation kommt weiter
  // über rotationSeed (Fingerprint).
  const phaseOffset = phaseName === "balanced"
    ? Math.min(2, Math.max(0, orderedPool.length - 1))
    : phaseName === "fallback"
    ? (options?.shortCurvyRoundTripFallback
      ? 0
      : Math.max(0, Math.floor(orderedPool.length * 0.65)))
    : 0;
  const startIndex = (rotationSeed + phaseOffset) % orderedPool.length;
  const rotated = orderedPool.slice(startIndex).concat(
    orderedPool.slice(0, startIndex),
  );
  return [...preferred, ...rotated];
}

function widenDistanceConfigForRoundTripSearch(
  base: DistanceConfig,
  targetDistanceKm: number,
  phase: "balanced" | "fallback",
): DistanceConfig {
  const minFactor = phase === "fallback" ? 0.80 : 0.84;
  const maxFactor = phase === "fallback" ? 1.22 : 1.16;
  const radiusScale = phase === "fallback" ? 1.12 : 1.06;
  const snapMultiplier = phase === "fallback" ? 1.16 : 1.10;

  return {
    radiusKm: base.radiusKm * radiusScale,
    minKm: base.minKm,
    maxKm: base.maxKm,
    acceptableMinKm: Math.min(
      base.acceptableMinKm,
      Math.round(targetDistanceKm * minFactor),
    ),
    acceptableMaxKm: Math.max(
      base.acceptableMaxKm,
      Math.round(targetDistanceKm * maxFactor),
    ),
    waypointRadiusMeters: Math.round(
      base.waypointRadiusMeters * snapMultiplier,
    ),
  };
}

function normalizeRoundTripRejectReason(reason: string): string {
  if (reason.startsWith("coords=")) return "coords";
  if (reason.startsWith("overlap=")) return "overlap";
  if (reason.startsWith("hooks=")) return "hooks";
  if (reason.startsWith("center_return=")) return "center_return";
  if (reason.startsWith("mapbox_http_")) return "mapbox_http";
  if (reason.startsWith("mapbox_")) return reason;
  if (reason.includes("u_turn")) return "u_turn";
  if (reason.includes("fallback")) return "fallback";
  return reason;
}

export async function searchBestRoundTripRoute({
  startLocation,
  targetDistanceKm,
  distanceConfig,
  mode,
  randomSeed,
  directionHintDegrees,
  waypointShapeFactor,
  zigzagWaypoints,
  simplifyWaypoints,
  maxWaypoints,
  mapboxProfile,
  excludeParams,
  accessToken,
  variantHint,
  fingerprintHint,
  maxCandidateAttemptsHint,
  avoidHighways,
  continueStraight,
  preferenceAreas,
}: {
  startLocation: Coordinate;
  targetDistanceKm: number;
  distanceConfig: DistanceConfig;
  mode?: RouteMode;
  randomSeed: number;
  directionHintDegrees?: number;
  waypointShapeFactor?: number;
  zigzagWaypoints?: boolean;
  simplifyWaypoints?: boolean;
  maxWaypoints?: number;
  mapboxProfile: string;
  excludeParams: string;
  accessToken: string;
  variantHint?: string;
  fingerprintHint?: string;
  maxCandidateAttemptsHint?: number;
  avoidHighways: boolean;
  continueStraight: boolean;
  preferenceAreas?: PreferenceArea[];
}): Promise<RoundTripSearchResult | null> {
  const highCostCurveSearch = mode === "Kurvenjagd" && targetDistanceKm >= 130;
  const extendedRoundTripSearch = targetDistanceKm >= 100 ||
    mode === "Entdecker";
  const shortCurvySearch = mode === "Kurvenjagd" && targetDistanceKm <= 60;
  const avoidHighwaysRoundTripSearch = avoidHighways;
  const avoidHighwaysTightRoundTripSearch = avoidHighways &&
    targetDistanceKm <= 80;
  const normalizedExcludeParams = normalizeExcludeParams(excludeParams);
  const relaxedSearchExcludes = relaxStreetExcludes(
    normalizedExcludeParams,
    avoidHighways,
  );
  const constrainedRoundTripSearch = normalizedExcludeParams.trim() !== "";
  const normalizedVariantHint = normalizeHint(variantHint);
  const normalizedFingerprintHint = normalizeHint(fingerprintHint);
  const longNoHighwayCurveRescueLabel = "nohw-curve-rescue-northeast";
  const longNoHighwayCurveRescueSearch = avoidHighways &&
    mode === "Kurvenjagd" &&
    targetDistanceKm > 70;
  const useMapboxAlternatives = true;
  const maxEvaluatedAlternatives = avoidHighways ? 2 : 3;
  const noHighwayAttemptBudget = targetDistanceKm <= 60
    ? mode === "Kurvenjagd" ? 14 : 12
    : targetDistanceKm <= 85
    ? mode === "Kurvenjagd" ? 14 : 12
    : mode === "Kurvenjagd"
    ? 16
    : 14;
  const shortSportHighwayRoundTrip = !avoidHighwaysRoundTripSearch &&
    mode === "Sport Mode" &&
    targetDistanceKm <= 60;
  // No-highway roundtrips still stay bounded, but they must attempt enough
  // live sectors before surfacing warmup. Pool thinness is support metadata,
  // not a reason to skip Mapbox entirely.
  const requestedAttemptBudget = Math.round(
    maxCandidateAttemptsHint ??
      (avoidHighwaysRoundTripSearch
        ? noHighwayAttemptBudget
        : shortSportHighwayRoundTrip
        ? 14
        : highCostCurveSearch
        ? 6
        : extendedRoundTripSearch
        ? 7
        : (constrainedRoundTripSearch || shortCurvySearch)
        ? 8
        : 7),
  );
  const explicitAttemptCap = typeof maxCandidateAttemptsHint === "number" &&
      Number.isFinite(maxCandidateAttemptsHint)
    ? Math.max(
      1,
      Math.min(
        avoidHighwaysRoundTripSearch ? noHighwayAttemptBudget : 10,
        Math.round(maxCandidateAttemptsHint),
      ),
    )
    : null;
  const uncappedGlobalAttemptBudget = avoidHighwaysRoundTripSearch
    ? noHighwayAttemptBudget
    : Math.max(
      shortSportHighwayRoundTrip ? 14 : 7,
      Math.min(
        highCostCurveSearch
          ? 7
          : extendedRoundTripSearch
          ? 8
          : (constrainedRoundTripSearch || shortCurvySearch)
          ? 9
          : shortSportHighwayRoundTrip
          ? 15
          : 8,
        requestedAttemptBudget,
      ),
    );
  const globalAttemptBudget = explicitAttemptCap == null
    ? uncappedGlobalAttemptBudget
    : Math.max(1, Math.min(uncappedGlobalAttemptBudget, explicitAttemptCap));
  const searchStartTs = Date.now();
  // Time Budget: jeder Mapbox-Call kostet ~1.5–3 s; mit 7–9 Plänen + relax
  // brauchen wir ≥18 s, sonst killt das Time-Budget den Fallback bevor er
  // läuft. Client-_invoke-Timeout muss DARÜBER liegen (siehe route_service).
  const roundTripTimeBudgetMs = highCostCurveSearch
    ? 16000
    : avoidHighwaysRoundTripSearch
    ? 25000
    : shortSportHighwayRoundTrip
    ? 28000
    : (constrainedRoundTripSearch || shortCurvySearch)
    ? 22000
    : 19000;
  const mapboxCandidateMaxAttempts = avoidHighwaysRoundTripSearch ? 1 : 2;
  const mapboxCandidateTimeoutMs = avoidHighwaysRoundTripSearch ? 5200 : 12000;
  const mapboxRelaxedTimeoutMs = avoidHighwaysRoundTripSearch ? 4500 : 10500;
  const remainingSearchMs = (reserveMs = 0): number =>
    roundTripTimeBudgetMs - (Date.now() - searchStartTs) - reserveMs;
  const boundedMapboxTimeoutMs = (
    preferredMs: number,
    minimumMs = 2500,
  ): number =>
    Math.max(
      minimumMs,
      Math.min(preferredMs, remainingSearchMs(900)),
    );
  const hasMapboxCallBudget = (minimumMs = 3000): boolean =>
    remainingSearchMs(900) >= minimumMs;
  const activePreferenceAreas = (preferenceAreas ?? []).filter((area) =>
    Number.isFinite(area.latitude) &&
    Number.isFinite(area.longitude) &&
    area.latitude >= -90 &&
    area.latitude <= 90 &&
    area.longitude >= -180 &&
    area.longitude <= 180
  ).slice(0, 3);
  const hasPreferenceAreas = activePreferenceAreas.length > 0;
  const preferenceRadiusMeters = (area: PreferenceArea): number =>
    Math.max(500, Math.min(4000, area.radius_m ?? 2200));
  const routeCoordinates = (route: any): Coordinate[] => {
    const coordinates = route?.geometry?.coordinates;
    if (!Array.isArray(coordinates)) return [];
    return coordinates
      .map((point: unknown) => {
        if (!Array.isArray(point) || point.length < 2) return null;
        const longitude = Number(point[0]);
        const latitude = Number(point[1]);
        if (
          !Number.isFinite(latitude) ||
          !Number.isFinite(longitude) ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180
        ) {
          return null;
        }
        return { latitude, longitude };
      })
      .filter((point): point is Coordinate => point != null);
  };
  const closestDistanceMeters = (
    coordinates: Coordinate[],
    area: PreferenceArea,
  ): number => {
    if (coordinates.length === 0) return Number.POSITIVE_INFINITY;
    let closest = Number.POSITIVE_INFINITY;
    for (const coordinate of coordinates) {
      closest = Math.min(closest, calculateDistance(coordinate, area) * 1000);
    }
    return closest;
  };
  const evaluatePreferenceMatch = (
    route: any,
  ): PreferenceMatchSummary | null => {
    if (!hasPreferenceAreas) return null;
    const coordinates = routeCoordinates(route);
    const distances = activePreferenceAreas.map((area) =>
      Math.round(closestDistanceMeters(coordinates, area))
    );
    const matchScores = distances.map((distance, index) => {
      const radius = preferenceRadiusMeters(activePreferenceAreas[index]);
      return Math.max(0, Math.min(1, 1 - distance / (radius * 2.5)));
    });
    const matchedPreferenceCount =
      distances.filter((distance, index) =>
        distance <= preferenceRadiusMeters(activePreferenceAreas[index])
      ).length;
    const averageScore = matchScores.length === 0
      ? 0
      : matchScores.reduce((sum, score) => sum + score, 0) /
        matchScores.length;
    const preferenceMatchScore = Math.round(averageScore * 100);
    const preferenceIgnoredReason = matchedPreferenceCount === 0 &&
        preferenceMatchScore < 25
      ? "all_preference_areas_far"
      : matchedPreferenceCount < activePreferenceAreas.length
      ? "partial_preference_match"
      : null;
    return {
      matchedPreferenceCount,
      preferenceMatchScore,
      preferenceAreaDistancesMeters: distances,
      preferenceIgnoredReason,
    };
  };
  const preferenceGoodEnough = (
    quality: RouteQualityEvaluation | null,
  ): boolean => {
    if (!hasPreferenceAreas || quality == null) return true;
    return (quality.matchedPreferenceCount ?? 0) > 0 ||
      (quality.preferenceMatchScore ?? 0) >= 35;
  };
  const rankCandidatePlansByPreference = (
    plans: RoundTripCandidatePlan[],
  ): RoundTripCandidatePlan[] => {
    if (!hasPreferenceAreas || plans.length <= 1) return plans;
    const scorePlan = (plan: RoundTripCandidatePlan): number => {
      const interiorWaypoints = plan.waypoints.slice(1, -1);
      if (interiorWaypoints.length === 0) return Number.POSITIVE_INFINITY;
      const distancePenalty = activePreferenceAreas.reduce((sum, area) => {
        const closest = interiorWaypoints.reduce(
          (best, waypoint) =>
            Math.min(best, calculateDistance(waypoint, area) * 1000),
          Number.POSITIVE_INFINITY,
        );
        return sum + closest;
      }, 0);
      const matched =
        activePreferenceAreas.filter((area) =>
          interiorWaypoints.some((waypoint) =>
            calculateDistance(waypoint, area) * 1000 <=
              preferenceRadiusMeters(area) * 2.2
          )
        ).length;
      return distancePenalty - matched * 2500;
    };
    return [...plans].sort((a, b) => scorePlan(a) - scorePlan(b));
  };

  const tuneDistanceConfigForAvoidHighways = (
    config: DistanceConfig,
  ): DistanceConfig => {
    if (!avoidHighwaysRoundTripSearch) {
      return config;
    }
    const shortNoHighwaySportRoundTrip = avoidHighways &&
      mode === "Sport Mode" &&
      targetDistanceKm <= 60;
    const snapCap = shortNoHighwaySportRoundTrip
      ? 5000
      : targetDistanceKm <= 60
      ? mode === "Kurvenjagd" ? 7600 : 7000
      : targetDistanceKm <= 85
      ? 8500
      : 9800;
    const snapBoost = shortNoHighwaySportRoundTrip
      ? 1.20
      : targetDistanceKm <= 60
      ? 1.55
      : targetDistanceKm <= 85
      ? 1.48
      : 1.38;
    const radiusTightening = shortNoHighwaySportRoundTrip
      ? 0.88
      : targetDistanceKm <= 60
      ? 1.00
      : targetDistanceKm <= 85
      ? 1.02
      : 1.08;
    return {
      ...config,
      radiusKm: config.radiusKm * radiusTightening,
      waypointRadiusMeters: Math.min(
        snapCap,
        Math.round(config.waypointRadiusMeters * snapBoost + 700),
      ),
    };
  };

  const searchPhases = [
    {
      name: "strict",
      distanceConfig: tuneDistanceConfigForAvoidHighways(distanceConfig),
      seedOffset: 0,
      continueStraight,
      exclude: normalizedExcludeParams,
    },
    {
      name: "balanced",
      distanceConfig: tuneDistanceConfigForAvoidHighways(
        widenDistanceConfigForRoundTripSearch(
          distanceConfig,
          targetDistanceKm,
          "balanced",
        ),
      ),
      seedOffset: 911,
      continueStraight,
      exclude: normalizedExcludeParams,
    },
    {
      name: "fallback",
      distanceConfig: tuneDistanceConfigForAvoidHighways(
        widenDistanceConfigForRoundTripSearch(
          distanceConfig,
          targetDistanceKm,
          "fallback",
        ),
      ),
      seedOffset: 1777,
      continueStraight,
      exclude: relaxedSearchExcludes,
    },
  ];

  let candidateAttempts = 0;
  let acceptedCandidates = 0;
  let rejectedCandidates = 0;
  let bestPlan: RoundTripCandidatePlan | null = null;
  let bestRoute: any = null;
  let bestQuality: RouteQualityEvaluation | null = null;
  let bestContext: {
    exclude: string;
    continueStraight: boolean;
    distanceConfig: DistanceConfig;
  } | null = null;
  const acceptedRouteCandidates: Array<{
    plan: RoundTripCandidatePlan;
    route: any;
    quality: RouteQualityEvaluation;
    context: {
      exclude: string;
      continueStraight: boolean;
      distanceConfig: DistanceConfig;
    };
  }> = [];
  let balancedHasPresentableCandidate = false;
  let balancedTerminalShortCircuit = false;
  const rejectReasons = new Map<string, number>();
  const lastPlanLabels: string[] = [];
  const seenRouteFingerprints = new Set<string>(
    normalizedFingerprintHint ? [normalizedFingerprintHint] : [],
  );
  let duplicateSkips = 0;
  let bestEmergencyDuplicate: {
    plan: RoundTripCandidatePlan;
    route: any;
    quality: RouteQualityEvaluation;
    fingerprint: string;
    context: {
      exclude: string;
      continueStraight: boolean;
      distanceConfig: DistanceConfig;
    };
  } | null = null;
  let rateLimitHits = 0;
  let timeoutHits = 0;
  let stopSearchWithBestCandidate = false;

  const registerReject = (reason: string) => {
    const normalized = normalizeRoundTripRejectReason(reason);
    rejectReasons.set(normalized, (rejectReasons.get(normalized) ?? 0) + 1);
  };

  const shouldAbortForProviderPressure = (): boolean => {
    if (rateLimitHits >= 2) {
      if (bestQuality && bestRoute && bestPlan) {
        debugWarn(
          `[RT] Provider rate limit after usable candidate (${bestQuality.tier}); returning current best instead of failing search.`,
        );
        stopSearchWithBestCandidate = true;
        return true;
      }
      throw new Error(
        "Routing provider rate limit reached during round-trip search.",
      );
    }
    if (timeoutHits >= 3) {
      if (bestQuality && bestRoute && bestPlan) {
        debugWarn(
          `[RT] Provider timeout pressure after usable candidate (${bestQuality.tier}); returning current best instead of failing search.`,
        );
        stopSearchWithBestCandidate = true;
        return true;
      }
      throw new Error("Routing provider timeout during round-trip search.");
    }
    return false;
  };
  const minBalancedPresentableCoords = targetDistanceKm <= 60
    ? 22
    : targetDistanceKm <= 100
    ? 26
    : 30;
  const isBalancedPresentableCandidate = (
    quality: RouteQualityEvaluation,
  ): boolean =>
    !quality.hasUTurn &&
    quality.coordinateCount >= minBalancedPresentableCoords &&
    (
      quality.tier === "good" ||
      (
        quality.tier === "acceptable" &&
        quality.overlapPercent <= 24 &&
        quality.distanceDeltaKm <= targetDistanceKm * 0.22
      )
    );
  const styleFitThresholdForEarlyStop = (() => {
    if (mode === "Kurvenjagd") return 58;
    if (mode === "Sport Mode") return 54;
    if (mode === "Entdecker") return 52;
    if (mode === "Abendrunde") return 52;
    return 0;
  })();
  const styleGoodEnoughForEarlyStop = (
    quality: RouteQualityEvaluation,
  ): boolean => {
    if (styleFitThresholdForEarlyStop <= 0) return true;
    const styleFit = quality.styleFitScore ?? 0;
    if (styleFit >= styleFitThresholdForEarlyStop) return true;
    // Keep searching for style-specific routes, but do not turn a valid route
    // into a reject solely because style fit is weak.
    return candidateAttempts >= Math.max(3, globalAttemptBudget - 1);
  };
  const applyCleanupGate = (
    route: any,
    quality: RouteQualityEvaluation,
    qualityDistanceConfig: DistanceConfig,
  ): RouteQualityEvaluation => {
    if (quality.tier === "rejected") {
      return quality;
    }
    const cleanup = evaluateRouteCleanupGate(route, "ROUND_TRIP", {
      targetDistanceKm,
      distanceConfig: qualityDistanceConfig,
      mode,
      avoidHighways,
      startLocation,
    });
    if (cleanup.passed) {
      return quality;
    }
    const cleanedDistanceKm = cleanup.cleanedDistanceKm > 0
      ? cleanup.cleanedDistanceKm
      : quality.actualDistanceKm;
    return {
      passed: false,
      reason: cleanup.reason,
      overlapPercent: quality.overlapPercent,
      hasUTurn: quality.hasUTurn || cleanup.cleanedGeometricUTurnCount > 0,
      tier: "rejected",
      score: Math.max(quality.score, 1180) +
        Math.max(0, cleanup.removedPointPercent * 0.6),
      coordinateCount: quality.coordinateCount,
      actualDistanceKm: cleanedDistanceKm,
      distanceDeltaKm: targetDistanceKm > 0
        ? Math.abs(cleanedDistanceKm - targetDistanceKm)
        : quality.distanceDeltaKm,
    };
  };
  const applyPreferenceScoring = (
    route: any,
    quality: RouteQualityEvaluation,
  ): RouteQualityEvaluation => {
    const match = evaluatePreferenceMatch(route);
    if (match == null) return quality;
    const preferenceMeta = {
      preferenceMatchScore: match.preferenceMatchScore,
      matchedPreferenceCount: match.matchedPreferenceCount,
      preferenceAreaDistancesMeters: match.preferenceAreaDistancesMeters,
      preferenceIgnoredReason: match.preferenceIgnoredReason,
    };
    if (quality.tier === "rejected") {
      return { ...quality, ...preferenceMeta };
    }
    const missingPreferenceCount = Math.max(
      0,
      activePreferenceAreas.length - match.matchedPreferenceCount,
    );
    const ignorePenalty = missingPreferenceCount * 28 +
      Math.max(0, 45 - match.preferenceMatchScore) * 0.65;
    const preferenceReward = match.preferenceMatchScore * 0.55 +
      match.matchedPreferenceCount * 18;
    return {
      ...quality,
      ...preferenceMeta,
      baseScore: quality.baseScore ?? quality.score,
      score: Math.max(0, quality.score + ignorePenalty - preferenceReward),
    };
  };
  const evaluateRouteAlternative = (
    route: any,
    qualityDistanceConfig: DistanceConfig,
  ): RouteQualityEvaluation =>
    applyPreferenceScoring(
      route,
      applyCleanupGate(
        route,
        evaluateRouteQuality(route, "ROUND_TRIP", {
          targetDistanceKm,
          distanceConfig: qualityDistanceConfig,
          mode,
          avoidHighways,
        }),
        qualityDistanceConfig,
      ),
    );
  const chooseBestRouteAlternative = (
    routes: any[],
    qualityDistanceConfig: DistanceConfig,
  ): { route: any; quality: RouteQualityEvaluation } | null => {
    let selectedRoute: any = null;
    let selectedQuality: RouteQualityEvaluation | null = null;
    for (const routeOption of routes) {
      const optionQuality = evaluateRouteAlternative(
        routeOption,
        qualityDistanceConfig,
      );
      if (
        selectedQuality == null ||
        (optionQuality.tier !== "rejected" &&
          selectedQuality.tier === "rejected") ||
        (
          optionQuality.tier === selectedQuality.tier &&
          optionQuality.score < selectedQuality.score
        ) ||
        (
          optionQuality.tier !== "rejected" &&
          selectedQuality.tier !== "rejected" &&
          optionQuality.score < selectedQuality.score
        )
      ) {
        selectedRoute = routeOption;
        selectedQuality = optionQuality;
      }
    }
    return selectedRoute != null && selectedQuality != null
      ? { route: selectedRoute, quality: selectedQuality }
      : null;
  };
  const hydrateGuidanceRoute = async (
    plan: RoundTripCandidatePlan,
    context: {
      exclude: string;
      continueStraight: boolean;
      distanceConfig: DistanceConfig;
    },
  ): Promise<{ route: any; quality: RouteQualityEvaluation } | null> => {
    const fetchResult = await getMapboxRouteDetailed(
      plan.waypoints,
      mapboxProfile,
      context.exclude,
      plan.radiuses,
      accessToken,
      {
        continueStraight: context.continueStraight,
        alternatives: false,
        maxAttempts: 1,
        timeoutMs: boundedMapboxTimeoutMs(mapboxCandidateTimeoutMs, 3000),
        retryDelayBaseMs: 220,
        includeGuidance: true,
      },
    );
    if (!fetchResult.route) {
      registerReject(
        fetchResult.outcome === "http_error"
          ? `guidance_mapbox_http_${fetchResult.statusCode ?? "unknown"}`
          : `guidance_mapbox_${fetchResult.outcome}`,
      );
      return null;
    }
    const selection = chooseBestRouteAlternative(
      [fetchResult.route],
      context.distanceConfig,
    );
    if (selection == null || selection.quality.tier === "rejected") {
      registerReject(
        selection?.quality.reason != null
          ? `guidance_${selection.quality.reason}`
          : "guidance_quality_rejected",
      );
      return null;
    }
    return selection;
  };

  for (const phase of searchPhases) {
    if (stopSearchWithBestCandidate) break;
    const orderedCandidates = rankCandidatePlansByPreference(
      prioritizeCandidatePlans(
        buildRoundTripWaypointCandidates({
          start: startLocation,
          distanceConfig: phase.distanceConfig,
          targetDistanceKm,
          mode,
          randomSeed: randomSeed + phase.seedOffset,
          preferredBearingDegrees: directionHintDegrees,
          waypointShapeFactor,
          zigzagWaypoints,
          simplifyWaypoints,
          maxWaypoints,
          avoidHighways,
        }),
        phase.name,
        normalizedVariantHint,
        normalizedFingerprintHint,
        {
          mode,
          avoidHighways,
          targetDistanceKm,
          shortCurvyRoundTripFallback: phase.name === "fallback" &&
            shortCurvySearch,
        },
      ),
    );
    // Pro Phase 2-3 Versuche. WICHTIG: Fair-Share-Guard reserviert für
    // jede spätere Phase MINDESTENS 2 Versuche (vorher: 1), damit der
    // Fallback in Bergtälern wirklich Plan A+B testen kann. Strict darf
    // 3 ausschöpfen, falls die Geometrie es zulässt; balanced/fallback
    // bekommen je 2-3.
    const declaredMaxPerPhase = phase.name === "strict"
      ? avoidHighwaysRoundTripSearch
        ? targetDistanceKm <= 60 ? 5 : 5
        : shortSportHighwayRoundTrip
        ? 4
        : 2
      : phase.name === "balanced"
      ? avoidHighwaysRoundTripSearch
        ? targetDistanceKm <= 60 ? 5 : 5
        : shortSportHighwayRoundTrip
        ? 4
        : 2
      : avoidHighwaysRoundTripSearch
      ? targetDistanceKm <= 60 ? 5 : targetDistanceKm <= 85 ? 5 : 6
      : shortSportHighwayRoundTrip
      ? 4
      : shortCurvySearch
      ? 4
      : constrainedRoundTripSearch
      ? 3
      : 2;
    const phasesRemainingAfterThis = searchPhases.length - 1 -
      searchPhases.indexOf(phase);
    // Reserviere mindestens 2 Versuche pro nachfolgender Phase.
    const reservedForLaterPhases = phasesRemainingAfterThis * 2;
    const fairShareCeiling = Math.max(
      1,
      globalAttemptBudget - candidateAttempts - reservedForLaterPhases,
    );
    const maxPhaseAttempts = Math.min(declaredMaxPerPhase, fairShareCeiling);
    const phaseIndex = searchPhases.indexOf(phase);
    const highwayPhaseStride = shortSportHighwayRoundTrip ? 4 : 0;
    const maxSliceStart = Math.max(
      0,
      orderedCandidates.length - maxPhaseAttempts,
    );
    const sliceStart = shortSportHighwayRoundTrip
      ? Math.min(phaseIndex * highwayPhaseStride, maxSliceStart)
      : 0;
    let candidatePlans = orderedCandidates.slice(
      sliceStart,
      sliceStart +
        Math.min(orderedCandidates.length - sliceStart, maxPhaseAttempts),
    );
    if (longNoHighwayCurveRescueSearch && phase.name === "fallback") {
      const rescuePlan = orderedCandidates.find((plan) =>
        plan.label === longNoHighwayCurveRescueLabel
      );
      if (rescuePlan) {
        const withoutRescue = candidatePlans.filter((plan) =>
          plan.label !== longNoHighwayCurveRescueLabel
        );
        candidatePlans = [
          ...withoutRescue.slice(0, Math.max(0, maxPhaseAttempts - 1)),
          rescuePlan,
        ].slice(0, maxPhaseAttempts);
      }
    }
    let phaseAttempts = 0;
    let phaseAcceptedCandidates = 0;

    debugLog(
      `[RT] Phase ${phase.name}: candidates=${candidatePlans.length}, radius=${
        phase.distanceConfig.radiusKm.toFixed(1)
      }km, ` +
        `snap=${phase.distanceConfig.waypointRadiusMeters}m, exclude=${
          phase.exclude || "none"
        }, continueStraight=${phase.continueStraight}`,
    );

    for (const plan of candidatePlans) {
      if (
        phaseAttempts >= maxPhaseAttempts ||
        candidateAttempts >= globalAttemptBudget ||
        !hasMapboxCallBudget()
      ) {
        debugLog(
          `[RT] Phase ${phase.name}: stopping early after ${phaseAttempts} attempts (global=${candidateAttempts})`,
        );
        break;
      }

      phaseAttempts += 1;
      candidateAttempts += 1;
      lastPlanLabels.push(`${phase.name}/${plan.label}`);
      debugLog(
        `[RT] Candidate ${candidateAttempts}: ${phase.name}/${plan.label} (${
          plan.waypoints.length - 2
        } WPs)`,
      );

      let fetchResult = await getMapboxRouteDetailed(
        plan.waypoints,
        mapboxProfile,
        phase.exclude,
        plan.radiuses,
        accessToken,
        {
          continueStraight: phase.continueStraight,
          alternatives: useMapboxAlternatives,
          maxAttempts: candidateAttempts >= 2 || !hasMapboxCallBudget(8000)
            ? 1
            : mapboxCandidateMaxAttempts,
          timeoutMs: boundedMapboxTimeoutMs(mapboxCandidateTimeoutMs),
          retryDelayBaseMs: 220,
          includeGuidance: false,
        },
      );
      const primaryFailureKind = getRetryKindFromMapboxFailure(fetchResult);
      if (primaryFailureKind === "rate_limit") rateLimitHits += 1;
      if (primaryFailureKind === "timeout") timeoutHits += 1;
      if (shouldAbortForProviderPressure()) break;

      const relaxedPhaseExclude = relaxStreetExcludes(
        phase.exclude,
        avoidHighways,
      );

      if (
        fetchResult.outcome === "no_route" &&
        relaxedPhaseExclude !== phase.exclude &&
        hasMapboxCallBudget(3500)
      ) {
        debugLog(
          `[RT] ${plan.label}: retry with relaxed excludes "${
            relaxedPhaseExclude || "none"
          }"`,
        );
        const relaxedFetch = await getMapboxRouteDetailed(
          plan.waypoints,
          mapboxProfile,
          relaxedPhaseExclude,
          plan.radiuses,
          accessToken,
          {
            continueStraight: phase.continueStraight,
            alternatives: useMapboxAlternatives,
            maxAttempts: 1,
            timeoutMs: boundedMapboxTimeoutMs(mapboxRelaxedTimeoutMs),
            includeGuidance: false,
          },
        );
        const relaxedFailureKind = getRetryKindFromMapboxFailure(relaxedFetch);
        if (relaxedFailureKind === "rate_limit") rateLimitHits += 1;
        if (relaxedFailureKind === "timeout") timeoutHits += 1;
        if (shouldAbortForProviderPressure()) break;
        if (relaxedFetch.outcome === "ok") {
          fetchResult = relaxedFetch;
        }
      }

      if (stopSearchWithBestCandidate) {
        break;
      }

      if (!fetchResult.route) {
        rejectedCandidates += 1;
        const reason = fetchResult.outcome === "http_error"
          ? `mapbox_http_${fetchResult.statusCode ?? "unknown"}`
          : `mapbox_${fetchResult.outcome}`;
        registerReject(reason);
        debugLog(
          `[RT] ${phase.name}/${plan.label}: ${reason}${
            fetchResult.details ? ` (${fetchResult.details.slice(0, 160)})` : ""
          }`,
        );
        continue;
      }

      const primaryRoutes = fetchResult.routes?.length
        ? fetchResult.routes.slice(0, maxEvaluatedAlternatives)
        : fetchResult.route
        ? [fetchResult.route]
        : [];
      const primarySelection = chooseBestRouteAlternative(
        primaryRoutes,
        phase.distanceConfig,
      );
      if (primarySelection == null) {
        rejectedCandidates += 1;
        registerReject("mapbox_empty_route");
        continue;
      }
      let route = primarySelection.route;
      let quality = primarySelection.quality;
      let selectedExclude = phase.exclude;
      let selectedContinueStraight = phase.continueStraight;
      let selectedDistanceConfig = phase.distanceConfig;

      if (
        quality.tier === "rejected" &&
        relaxedPhaseExclude !== phase.exclude &&
        quality.reason.startsWith("overlap=") &&
        rateLimitHits === 0 &&
        timeoutHits < 2 &&
        hasMapboxCallBudget(3500)
      ) {
        debugLog(
          `[RT] ${plan.label}: rejected with strict excludes, trying relaxed street filter`,
        );
        const relaxedFetch = await getMapboxRouteDetailed(
          plan.waypoints,
          mapboxProfile,
          relaxedPhaseExclude,
          plan.radiuses,
          accessToken,
          {
            continueStraight: phase.continueStraight,
            alternatives: useMapboxAlternatives,
            maxAttempts: 1,
            timeoutMs: boundedMapboxTimeoutMs(mapboxRelaxedTimeoutMs),
            includeGuidance: false,
          },
        );
        const relaxedFailureKind = getRetryKindFromMapboxFailure(relaxedFetch);
        if (relaxedFailureKind === "rate_limit") rateLimitHits += 1;
        if (relaxedFailureKind === "timeout") timeoutHits += 1;
        if (shouldAbortForProviderPressure()) break;
        const relaxedRoutes = relaxedFetch.routes?.length
          ? relaxedFetch.routes.slice(0, maxEvaluatedAlternatives)
          : relaxedFetch.route
          ? [relaxedFetch.route]
          : [];
        const relaxedSelection = chooseBestRouteAlternative(
          relaxedRoutes,
          phase.distanceConfig,
        );
        if (relaxedSelection != null) {
          const relaxedQuality = relaxedSelection.quality;
          debugLog(
            `[RT] ${plan.label}: relaxed tier=${relaxedQuality.tier}, score=${
              relaxedQuality.score.toFixed(1)
            }, ` +
              `distance=${
                relaxedQuality.actualDistanceKm.toFixed(1)
              }km, overlap=${
                relaxedQuality.overlapPercent.toFixed(1)
              }%, coords=${relaxedQuality.coordinateCount}`,
          );
          if (
            relaxedQuality.tier !== "rejected" ||
            relaxedQuality.score < quality.score
          ) {
            route = relaxedSelection.route;
            quality = relaxedQuality;
            selectedExclude = relaxedPhaseExclude;
            selectedDistanceConfig = phase.distanceConfig;
          }
        }
      }

      if (stopSearchWithBestCandidate) {
        break;
      }

      debugLog(
        `[RT] ${phase.name}/${plan.label}: tier=${quality.tier}, score=${
          quality.score.toFixed(1)
        }, ` +
          `base=${(quality.baseScore ?? quality.score).toFixed(1)}, style=${
            (quality.styleFitScore ?? 0).toFixed(1)
          }, ` +
          `distance=${quality.actualDistanceKm.toFixed(1)}km, overlap=${
            quality.overlapPercent.toFixed(1)
          }%, curve=${
            (quality.styleMetrics?.curveDensityPer50Km ?? 0).toFixed(1)
          }/50km, smooth=${
            (quality.styleMetrics?.smoothnessScore ?? 0).toFixed(1)
          }, zigzag=${
            (quality.styleMetrics?.zigzagScore ?? 0).toFixed(1)
          }, sharp=${
            (quality.styleMetrics?.sharpTurnRate ?? 0).toFixed(1)
          }, reasons=${
            (quality.styleFitReasons ?? []).join("|") || "none"
          }, coords=${quality.coordinateCount}`,
      );

      if (quality.tier === "rejected") {
        rejectedCandidates += 1;
        registerReject(quality.reason);
        continue;
      }

      const routeFingerprint = buildRouteFingerprintFromRoute(route);
      if (seenRouteFingerprints.has(routeFingerprint)) {
        duplicateSkips += 1;
        registerReject("duplicate_skip");
        debugLog(
          `[RT] ${phase.name}/${plan.label}: duplicate_skip fingerprint=${
            routeFingerprint.slice(0, 24)
          }`,
        );
        if (
          bestEmergencyDuplicate == null ||
          quality.score < bestEmergencyDuplicate.quality.score
        ) {
          bestEmergencyDuplicate = {
            plan,
            route,
            quality,
            fingerprint: routeFingerprint,
            context: {
              exclude: selectedExclude,
              continueStraight: selectedContinueStraight,
              distanceConfig: selectedDistanceConfig,
            },
          };
        }
        continue;
      }
      seenRouteFingerprints.add(routeFingerprint);

      acceptedCandidates += 1;
      phaseAcceptedCandidates += 1;
      const acceptedContext = {
        exclude: selectedExclude,
        continueStraight: selectedContinueStraight,
        distanceConfig: selectedDistanceConfig,
      };
      acceptedRouteCandidates.push({
        plan,
        route,
        quality,
        context: acceptedContext,
      });
      if (!bestQuality || quality.score < bestQuality.score) {
        bestPlan = plan;
        bestRoute = route;
        bestQuality = quality;
        bestContext = acceptedContext;
      }
      if (
        phase.name === "balanced" &&
        isBalancedPresentableCandidate(quality) &&
        preferenceGoodEnough(quality)
      ) {
        balancedHasPresentableCandidate = true;
      }

      const noHighwayMediumLongShapeClean =
        (quality.shapeMetrics?.loopnessScore ?? 0) >=
          (targetDistanceKm >= 90 ? 62 : 54) &&
        (quality.shapeMetrics?.spurScore ?? 100) <=
          (targetDistanceKm >= 90 ? 28 : 34) &&
        (quality.shapeMetrics?.outAndBackScore ?? 100) <=
          (targetDistanceKm >= 90 ? 28 : 34) &&
        (quality.shapeMetrics?.deadEndArmScore ?? 100) <=
          (targetDistanceKm >= 90 ? 24 : 30);
      const noHighwayMediumLongGoodEnough = avoidHighwaysRoundTripSearch &&
        targetDistanceKm > 60 &&
        (quality.tier === "ideal" || quality.tier === "good") &&
        quality.distanceDeltaKm <= targetDistanceKm * 0.15 &&
        quality.overlapPercent <= (mode === "Kurvenjagd" ? 18 : 22) &&
        noHighwayMediumLongShapeClean;
      // Stop aggressively for medium no-highway Sport acceptable hits:
      // alpine geometry means retrying will not improve quality, and
      // running all 6 Mapbox candidates costs >26s (client timeout).
      const noHighwayMediumSportAcceptableEarly =
        avoidHighwaysRoundTripSearch &&
        targetDistanceKm > 60 && targetDistanceKm <= 115 &&
        mode === "Sport Mode" &&
        quality.tier === "acceptable" &&
        quality.distanceDeltaKm <= targetDistanceKm * 0.30 &&
        (plan.label.startsWith("nohw-medium-sport-orbital-") ||
          plan.label.startsWith("nohw-medium-sport-orbital-rheintal-") ||
          plan.label.startsWith("nohw-medium-sport-cardinal-"));
      const noHighwayMediumSportShapeCleanForEarlyStop =
        !noHighwayMediumSportAcceptableEarly ||
        (
          (quality.shapeMetrics?.loopnessScore ?? 0) >=
            (targetDistanceKm >= 90 ? 58 : 52) &&
          (quality.shapeMetrics?.spurScore ?? 100) <=
            (targetDistanceKm >= 90 ? 32 : 38) &&
          (quality.shapeMetrics?.outAndBackScore ?? 100) <=
            (targetDistanceKm >= 90 ? 30 : 36) &&
          (quality.shapeMetrics?.deadEndArmScore ?? 100) <=
            (targetDistanceKm >= 90 ? 28 : 34)
        );
      const noHighwayMediumRescueCandidate = avoidHighwaysRoundTripSearch &&
        targetDistanceKm > 60 &&
        targetDistanceKm <= 85 &&
        (plan.label === "nohw-medium-rhine-south" ||
          (noHighwayMediumSportAcceptableEarly &&
            noHighwayMediumSportShapeCleanForEarlyStop));
      const shouldStopAfterGoodCandidate = quality.tier === "ideal" ||
        noHighwayMediumLongGoodEnough ||
        noHighwayMediumRescueCandidate ||
        (
          quality.tier === "good" &&
          !avoidHighwaysTightRoundTripSearch &&
          candidateAttempts >=
            (highCostCurveSearch || constrainedRoundTripSearch ||
                shortCurvySearch
              ? 3
              : 2)
        ) ||
        (
          candidateAttempts >= (highCostCurveSearch ? 3 : 4) &&
          phase.name === "fallback" &&
          phaseAcceptedCandidates >= 2 &&
          quality.distanceDeltaKm <= targetDistanceKm * 0.15
        );
      const shouldStopAfterAcceptableCandidate =
        quality.tier === "acceptable" &&
        !avoidHighwaysTightRoundTripSearch &&
        noHighwayMediumSportShapeCleanForEarlyStop &&
        (
          phase.name === "fallback" ||
          phaseAcceptedCandidates >= 2 ||
          candidateAttempts >= (constrainedRoundTripSearch ? 3 : 2)
        );

      if (
        (shouldStopAfterGoodCandidate || shouldStopAfterAcceptableCandidate) &&
        styleGoodEnoughForEarlyStop(quality) &&
        preferenceGoodEnough(quality)
      ) {
        debugLog(
          `[RT] Phase ${phase.name}: usable candidate found, stopping early after ${phaseAttempts} attempts`,
        );
        if (noHighwayMediumLongGoodEnough) {
          stopSearchWithBestCandidate = true;
        }
        if (noHighwayMediumRescueCandidate) {
          balancedTerminalShortCircuit = true;
          stopSearchWithBestCandidate = true;
        }
        break;
      }
    }

    if (stopSearchWithBestCandidate) {
      break;
    }
    if (
      candidateAttempts >= globalAttemptBudget ||
      Date.now() - searchStartTs >= roundTripTimeBudgetMs
    ) {
      break;
    }
    if (
      bestQuality?.tier === "ideal" &&
      styleGoodEnoughForEarlyStop(bestQuality) &&
      preferenceGoodEnough(bestQuality)
    ) {
      break;
    }
    if (
      phaseAcceptedCandidates > 0 &&
      bestQuality?.tier === "good" &&
      !avoidHighwaysTightRoundTripSearch &&
      styleGoodEnoughForEarlyStop(bestQuality) &&
      preferenceGoodEnough(bestQuality)
    ) {
      break;
    }
    if (
      phase.name === "balanced" &&
      balancedHasPresentableCandidate &&
      !avoidHighwaysTightRoundTripSearch
    ) {
      debugLog(
        `[RT] Phase balanced: presentable candidate found, skipping fallback/rescue for this seed`,
      );
      balancedTerminalShortCircuit = true;
      stopSearchWithBestCandidate = true;
      break;
    }
    if (
      phaseAcceptedCandidates > 0 &&
      bestQuality?.tier === "acceptable" &&
      !avoidHighwaysTightRoundTripSearch &&
      styleGoodEnoughForEarlyStop(bestQuality) &&
      preferenceGoodEnough(bestQuality) &&
      (
        phase.name === "fallback" ||
        candidateAttempts >= (constrainedRoundTripSearch ? 3 : 2)
      )
    ) {
      break;
    }
  }

  if (!bestPlan || !bestRoute || !bestQuality) {
    if (bestEmergencyDuplicate != null) {
      const hydratedDuplicate = await hydrateGuidanceRoute(
        bestEmergencyDuplicate.plan,
        bestEmergencyDuplicate.context,
      );
      if (hydratedDuplicate == null) {
        registerReject("guidance_fetch_failed");
        bestEmergencyDuplicate = null;
      } else {
        bestEmergencyDuplicate.route = hydratedDuplicate.route;
        bestEmergencyDuplicate.quality = hydratedDuplicate.quality;
      }
    }
    if (bestEmergencyDuplicate != null) {
      debugWarn(
        `[RT] Emergency duplicate fallback: ${bestEmergencyDuplicate.plan.label} (${
          bestEmergencyDuplicate.fingerprint.slice(0, 24)
        })`,
      );
      return {
        route: bestEmergencyDuplicate.route,
        waypoints: bestEmergencyDuplicate.plan.waypoints,
        radiuses: bestEmergencyDuplicate.plan.radiuses,
        quality: bestEmergencyDuplicate.quality,
        candidateAttempts,
        acceptedCandidates,
        rejectedCandidates,
        rejectReasons: Object.fromEntries(rejectReasons),
        searchPhases: searchPhases.map((phase) => phase.name),
        lastPlanLabels,
        variantHint: normalizedVariantHint,
        fingerprintHint: normalizedFingerprintHint,
        duplicateSkips,
        emergencyDuplicateUsed: true,
        preferenceMatch: bestEmergencyDuplicate.quality == null ? null : {
          matchedPreferenceCount:
            bestEmergencyDuplicate.quality.matchedPreferenceCount ?? 0,
          preferenceMatchScore:
            bestEmergencyDuplicate.quality.preferenceMatchScore ?? 0,
          preferenceAreaDistancesMeters:
            bestEmergencyDuplicate.quality.preferenceAreaDistancesMeters ?? [],
          preferenceIgnoredReason:
            bestEmergencyDuplicate.quality.preferenceIgnoredReason ?? null,
        },
      };
    }
    debugLog(
      `[RT] Search exhausted: ${candidateAttempts} candidates, duplicateSkips=${duplicateSkips}, none usable. Reject summary=${
        JSON.stringify(Object.fromEntries(rejectReasons))
      }`,
    );
    return {
      route: null,
      waypoints: [],
      radiuses: "",
      quality: null,
      candidateAttempts,
      acceptedCandidates,
      rejectedCandidates,
      rejectReasons: Object.fromEntries(rejectReasons),
      searchPhases: searchPhases.map((phase) => phase.name),
      lastPlanLabels,
      variantHint: normalizedVariantHint,
      fingerprintHint: normalizedFingerprintHint,
      duplicateSkips,
      exhausted: true,
    };
  }

  if (bestContext != null) {
    let hydratedSelection: {
      plan: RoundTripCandidatePlan;
      route: any;
      quality: RouteQualityEvaluation;
    } | null = null;
    const hydrationQueue = acceptedRouteCandidates
      .slice()
      .sort((a, b) => a.quality.score - b.quality.score);
    for (const candidate of hydrationQueue) {
      const hydratedCandidate = await hydrateGuidanceRoute(
        candidate.plan,
        candidate.context,
      );
      if (hydratedCandidate == null) continue;
      hydratedSelection = {
        plan: candidate.plan,
        route: hydratedCandidate.route,
        quality: hydratedCandidate.quality,
      };
      break;
    }
    if (hydratedSelection == null) {
      registerReject("guidance_fetch_failed");
      debugLog(
        `[RT] Search exhausted after accepted candidates because guidance hydration failed. Reject summary=${
          JSON.stringify(Object.fromEntries(rejectReasons))
        }`,
      );
      return {
        route: null,
        waypoints: [],
        radiuses: "",
        quality: null,
        candidateAttempts,
        acceptedCandidates,
        rejectedCandidates,
        rejectReasons: Object.fromEntries(rejectReasons),
        searchPhases: searchPhases.map((phase) => phase.name),
        lastPlanLabels,
        variantHint: normalizedVariantHint,
        fingerprintHint: normalizedFingerprintHint,
        duplicateSkips,
        exhausted: true,
      };
    }
    bestPlan = hydratedSelection.plan;
    bestRoute = hydratedSelection.route;
    bestQuality = hydratedSelection.quality;
  }

  debugLog(
    `[RT] Selected ${bestPlan.label}: tier=${bestQuality.tier}, score=${
      bestQuality.score.toFixed(1)
    }, base=${(bestQuality.baseScore ?? bestQuality.score).toFixed(1)}, style=${
      (bestQuality.styleFitScore ?? 0).toFixed(1)
    }, ` +
      `curve=${
        (bestQuality.styleMetrics?.curveDensityPer50Km ?? 0).toFixed(1)
      }/50km, smooth=${
        (bestQuality.styleMetrics?.smoothnessScore ?? 0).toFixed(1)
      }, zigzag=${(bestQuality.styleMetrics?.zigzagScore ?? 0).toFixed(1)}, ` +
      `attempts=${candidateAttempts}, accepted=${acceptedCandidates}, rejected=${rejectedCandidates}, duplicateSkips=${duplicateSkips}, rejects=${
        JSON.stringify(Object.fromEntries(rejectReasons))
      }`,
  );

  return {
    route: bestRoute,
    waypoints: bestPlan.waypoints,
    radiuses: bestPlan.radiuses,
    quality: bestQuality,
    candidateAttempts,
    acceptedCandidates,
    rejectedCandidates,
    rejectReasons: Object.fromEntries(rejectReasons),
    searchPhases: searchPhases.map((phase) => phase.name),
    lastPlanLabels,
    variantHint: normalizedVariantHint,
    fingerprintHint: normalizedFingerprintHint,
    duplicateSkips,
    emergencyDuplicateUsed: false,
    terminalShortCircuit: balancedTerminalShortCircuit,
    preferenceMatch: hasPreferenceAreas
      ? {
        matchedPreferenceCount: bestQuality.matchedPreferenceCount ?? 0,
        preferenceMatchScore: bestQuality.preferenceMatchScore ?? 0,
        preferenceAreaDistancesMeters:
          bestQuality.preferenceAreaDistancesMeters ?? [],
        preferenceIgnoredReason: bestQuality.preferenceIgnoredReason ?? null,
      }
      : null,
  };
}
