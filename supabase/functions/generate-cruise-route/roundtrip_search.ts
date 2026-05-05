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
        "nohw-short-explore-compact",
        "nohw-short-explore",
        "nohw-sector-explore",
        "sport-paired-west",
        "sport-paired-northwest",
        "sport-paired-southwest",
      ]
      : normalizedMode === "abendrunde"
      ? [
        "nohw-short-evening-compact",
        "nohw-short-evening",
        "nohw-sector-evening",
        "nohw-regional-evening",
        "sport-paired-west",
        "sport-paired-northwest",
        "sport-paired-southwest",
      ]
      : [
        "nohw-short-sport-compact",
        "nohw-short-sport-valley-clean",
        "sport-flow-regional",
        "nohw-sector-sport",
        "nohw-regional-sport",
        "fallback-triangle-balanced",
        "fallback-loop-3",
        "fallback-loop-4",
        "sport-paired-west",
        "sport-paired-northwest",
        "sport-paired-southwest",
        "sport-paired-west-wide",
      ]
    : noHighwayTargetKm <= 85
    ? normalizedMode === "sport mode" || normalizedMode === "sport"
      ? [
        "nohw-medium-sport-compact",
        "nohw-medium-sport-asymmetric",
        "nohw-medium-sport-cardinal-compact",
        "nohw-sector-sport",
        "nohw-regional-sport",
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
          ? "nohw-medium-curvy-distributed"
          : normalizedMode === "entdecker"
          ? "nohw-medium-explore"
          : "nohw-medium-evening",
        normalizedMode === "entdecker"
          ? "nohw-sector-explore"
          : "nohw-sector-evening",
        normalizedMode === "kurvenjagd"
          ? "nohw-medium-curvy-hillside"
          : "nohw-sector-curvy",
        normalizedMode === "kurvenjagd"
          ? "nohw-medium-curvy-two-lobe"
          : "nohw-regional-curvy",
        "nohw-sector-curvy",
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
      "nohw-long-explore",
      "nohw-sector-explore",
      "nohw-long-oval-west",
      "nohw-long-oval-northwest",
      "nohw-long-oval-southwest",
      "nohw-long-oval-west-wide",
    ]
    : normalizedMode === "abendrunde"
    ? [
      "nohw-long-evening",
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
  previousRouteFingerprints,
  maxCandidateAttemptsHint,
  avoidHighways,
  continueStraight,
  preferenceAreas,
  movingStartOptions,
  debugRejectCandidates,
  maxDebugRejectCandidates,
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
  previousRouteFingerprints?: string[];
  maxCandidateAttemptsHint?: number;
  avoidHighways: boolean;
  continueStraight: boolean;
  preferenceAreas?: PreferenceArea[];
  movingStartOptions?: {
    movingStartDetected: boolean;
    currentHeading?: number;
    startRadiusMeters?: number;
    startBearingToleranceDegrees?: number;
    avoidManeuverRadiusMeters?: number;
    startSnapStrategy?: string;
    startOnMotorway?: boolean | null;
  };
  debugRejectCandidates?: boolean;
  maxDebugRejectCandidates?: number;
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
  const noHighwayCompatibleExcludes = (() => {
    const parts = new Set(
      normalizeExcludeParams(normalizedExcludeParams)
        .split(",")
        .map((part) => part.trim())
        .filter((part) => part.length > 0),
    );
    parts.add("motorway");
    return [...parts].join(",");
  })();
  const constrainedRoundTripSearch = normalizedExcludeParams.trim() !== "";
  const normalizedVariantHint = normalizeHint(variantHint);
  const normalizedFingerprintHint = normalizeHint(fingerprintHint);
  const normalizedPreviousRouteFingerprints = (previousRouteFingerprints ?? [])
    .map((value) => normalizeHint(value))
    .filter((value): value is string => value != null)
    .slice(0, 5);
  const movingStartDetected = movingStartOptions?.movingStartDetected === true;
  const effectivePlanRadiuses = (plan: RoundTripCandidatePlan): string => {
    if (
      !movingStartDetected ||
      typeof movingStartOptions?.startRadiusMeters !== "number" ||
      !Number.isFinite(movingStartOptions.startRadiusMeters)
    ) {
      return plan.radiuses;
    }
    const parts = plan.radiuses.split(";");
    if (parts.length === 0) return plan.radiuses;
    parts[0] = String(
      Math.max(
        5,
        Math.min(300, Math.round(movingStartOptions.startRadiusMeters)),
      ),
    );
    return parts.join(";");
  };
  const effectivePlanBearings = (plan: RoundTripCandidatePlan): string => {
    if (
      !movingStartDetected ||
      typeof movingStartOptions?.currentHeading !== "number" ||
      !Number.isFinite(movingStartOptions.currentHeading)
    ) {
      return "";
    }
    const tolerance = typeof movingStartOptions.startBearingToleranceDegrees ===
          "number" &&
        Number.isFinite(movingStartOptions.startBearingToleranceDegrees)
      ? Math.max(
        15,
        Math.min(
          90,
          Math.round(movingStartOptions.startBearingToleranceDegrees),
        ),
      )
      : 45;
    const heading =
      ((Math.round(movingStartOptions.currentHeading) % 360) + 360) %
      360;
    return plan.waypoints
      .map((_, index) => index === 0 ? `${heading},${tolerance}` : "")
      .join(";");
  };
  const effectiveAvoidManeuverRadius = movingStartDetected &&
      typeof movingStartOptions?.avoidManeuverRadiusMeters === "number" &&
      Number.isFinite(movingStartOptions.avoidManeuverRadiusMeters)
    ? Math.max(
      1,
      Math.min(1000, Math.round(movingStartOptions.avoidManeuverRadiusMeters)),
    )
    : undefined;
  const longNoHighwayCurveRescueLabel = "nohw-curve-rescue-northeast";
  const longNoHighwayCurveRescueSearch = avoidHighways &&
    mode === "Kurvenjagd" &&
    targetDistanceKm > 70;
  const useSearchAlternatives = !avoidHighwaysRoundTripSearch;
  const useSelectiveNoHighwayAlternatives = avoidHighwaysRoundTripSearch &&
    targetDistanceKm <= 115;
  const noHighwayAttemptBudget = targetDistanceKm <= 60
    ? mode === "Kurvenjagd" ? 14 : mode === "Sport Mode" ? 15 : 12
    : targetDistanceKm <= 85
    ? mode === "Kurvenjagd" ? 12 : 10
    : mode === "Kurvenjagd"
    ? 10
    : 8;
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
  const minimumLiveAttemptBudget = !avoidHighwaysRoundTripSearch &&
      mode === "Sport Mode" && targetDistanceKm >= 75
    ? targetDistanceKm >= 95 ? 8 : 7
    : 1;
  const effectiveRequestedAttemptBudget = Math.max(
    minimumLiveAttemptBudget,
    requestedAttemptBudget,
  );
  const explicitAttemptCap = typeof maxCandidateAttemptsHint === "number" &&
      Number.isFinite(maxCandidateAttemptsHint)
    ? Math.max(
      minimumLiveAttemptBudget,
      Math.min(
        avoidHighwaysRoundTripSearch ? noHighwayAttemptBudget : 16,
        Math.round(maxCandidateAttemptsHint),
      ),
    )
    : null;
  const uncappedGlobalAttemptBudget = avoidHighwaysRoundTripSearch
    ? noHighwayAttemptBudget
    : mode === "Sport Mode" && targetDistanceKm >= 75
    ? targetDistanceKm >= 95 ? 16 : 15
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
        effectiveRequestedAttemptBudget,
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
  const maxSearchRouteCoordinates = avoidHighwaysRoundTripSearch
    ? targetDistanceKm <= 60 ? 1600 : targetDistanceKm <= 85 ? 1400 : 1600
    : 1800;
  const maxHydratedRouteCoordinates = avoidHighwaysRoundTripSearch
    ? targetDistanceKm <= 85 ? 2200 : 2600
    : 3200;
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
  const rejectSampleLimit = debugRejectCandidates === true
    ? Math.max(
      1,
      Math.min(
        80,
        Math.round(
          typeof maxDebugRejectCandidates === "number" &&
            Number.isFinite(maxDebugRejectCandidates)
            ? maxDebugRejectCandidates
            : 40,
        ),
      ),
    )
    : 0;
  const rejectSamples: Record<string, unknown>[] = [];
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
  const sampledDebugGeometry = (coordinates: Coordinate[]): number[][] => {
    if (coordinates.length === 0) return [];
    const sampleCount = Math.min(18, coordinates.length);
    const samples: number[][] = [];
    for (let i = 0; i < sampleCount; i += 1) {
      const ratio = sampleCount === 1 ? 0 : i / (sampleCount - 1);
      const index = Math.round((coordinates.length - 1) * ratio);
      const point = coordinates[index];
      samples.push([
        Number(point.longitude.toFixed(5)),
        Number(point.latitude.toFixed(5)),
      ]);
    }
    return samples;
  };
  const recordRejectSample = (
    args: {
      phaseName: string;
      plan: RoundTripCandidatePlan;
      reason: string;
      route?: any;
      quality?: RouteQualityEvaluation | null;
      routeRequestMeta?: RoundTripRouteRequestMeta | null;
      exclude?: string;
    },
  ): void => {
    if (rejectSampleLimit <= 0 || rejectSamples.length >= rejectSampleLimit) {
      return;
    }
    const route = args.route;
    const coordinates = route == null ? [] : routeCoordinates(route);
    const first = coordinates[0];
    const last = coordinates[coordinates.length - 1];
    const firstLastDistanceMeters = first != null && last != null
      ? Math.round(calculateDistance(first, last) * 1000)
      : null;
    const quality = args.quality ?? null;
    const shape = quality?.shapeMetrics;
    const styleMetrics = quality?.styleMetrics;
    const cleanedDistanceKm = shape != null && quality != null
      ? Number(
        (
          quality.actualDistanceKm *
          Math.max(0, Math.min(1, shape.cleanupDistanceRetentionRatio))
        ).toFixed(1),
      )
      : null;
    const localHairpinCandidate = shape != null &&
      shape.geometricUTurnCount > 0 &&
      shape.spurScore <= 10 &&
      shape.outAndBackScore <= 10 &&
      shape.deadEndArmScore <= 14 &&
      shape.centerReentryCount === 0;
    rejectSamples.push({
      phase: args.phaseName,
      candidate_family: args.plan.label,
      target_distance_km: targetDistanceKm,
      route_distance_km: quality == null
        ? null
        : Number(quality.actualDistanceKm.toFixed(1)),
      reject_reason: args.reason,
      quality_score: quality == null ? null : Number(quality.score.toFixed(1)),
      quality_tier: quality?.tier ?? null,
      curve_density: styleMetrics == null
        ? null
        : Number(styleMetrics.curveDensityPer50Km.toFixed(1)),
      loopness_score: shape == null
        ? null
        : Number(shape.loopnessScore.toFixed(1)),
      spur_score: shape == null ? null : Number(shape.spurScore.toFixed(1)),
      out_and_back_score: shape == null
        ? null
        : Number(shape.outAndBackScore.toFixed(1)),
      dead_end_arm_score: shape == null
        ? null
        : Number(shape.deadEndArmScore.toFixed(1)),
      u_turn_count: shape?.geometricUTurnCount ?? null,
      cleanup_u_turn_count: shape?.cleanupUTurnCount ?? null,
      local_hairpin_candidate: localHairpinCandidate,
      cleanup_distance_km: cleanedDistanceKm,
      cleanup_distance_retention_ratio: shape == null
        ? null
        : Number(shape.cleanupDistanceRetentionRatio.toFixed(2)),
      raw_coordinate_count: coordinates.length,
      silent_via_used: args.routeRequestMeta?.silentViaUsed ?? null,
      silent_via_fallback_used: args.routeRequestMeta?.silentViaFallbackUsed ??
        null,
      mapbox_leg_count: args.routeRequestMeta?.mapboxLegCount ?? null,
      arrive_maneuver_count: args.routeRequestMeta?.arriveManeuverCount ?? null,
      first_last_distance_m: firstLastDistanceMeters,
      effective_excludes: args.exclude ?? null,
      fingerprint: route == null ? null : buildRouteFingerprintFromRoute(route),
      geometry_sample: sampledDebugGeometry(coordinates),
    });
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
    forceNoHighway = false,
  ): DistanceConfig => {
    if (!avoidHighwaysRoundTripSearch && !forceNoHighway) {
      return config;
    }
    const shortNoHighwaySportRoundTrip = (avoidHighways || forceNoHighway) &&
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
      ? 0.96
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

  type SearchPhase = {
    name: string;
    distanceConfig: DistanceConfig;
    seedOffset: number;
    continueStraight: boolean;
    exclude: string;
    planAvoidHighways?: boolean;
  };

  const highwayAllowedNoHighwayPhases: SearchPhase[] =
    !avoidHighwaysRoundTripSearch
      ? [
        {
          name: "compatible_no_highway",
          distanceConfig: tuneDistanceConfigForAvoidHighways(
            distanceConfig,
            true,
          ),
          seedOffset: 0,
          continueStraight,
          exclude: noHighwayCompatibleExcludes,
          planAvoidHighways: true,
        },
        {
          name: "compatible_no_highway_balanced",
          distanceConfig: tuneDistanceConfigForAvoidHighways(
            widenDistanceConfigForRoundTripSearch(
              distanceConfig,
              targetDistanceKm,
              "balanced",
            ),
            true,
          ),
          seedOffset: 911,
          continueStraight,
          exclude: noHighwayCompatibleExcludes,
          planAvoidHighways: true,
        },
        {
          name: "compatible_no_highway_fallback",
          distanceConfig: tuneDistanceConfigForAvoidHighways(
            widenDistanceConfigForRoundTripSearch(
              distanceConfig,
              targetDistanceKm,
              "fallback",
            ),
            true,
          ),
          seedOffset: 1777,
          continueStraight,
          exclude: noHighwayCompatibleExcludes,
          planAvoidHighways: true,
        },
      ]
      : [];

  const searchPhases: SearchPhase[] = [
    ...highwayAllowedNoHighwayPhases,
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
    forceLegacyWaypoints?: boolean;
  } | null = null;
  const acceptedRouteCandidates: Array<{
    plan: RoundTripCandidatePlan;
    phaseName: string;
    distanceFitTier: string;
    route: any;
    fingerprint: string;
    quality: RouteQualityEvaluation;
    context: {
      exclude: string;
      continueStraight: boolean;
      distanceConfig: DistanceConfig;
      forceLegacyWaypoints?: boolean;
    };
    routeRequestMeta: RoundTripRouteRequestMeta;
  }> = [];
  type RoundTripRouteRequestMeta = {
    silentViaUsed: boolean;
    silentViaWaypoints: string | null;
    shapingPointCount: number;
    mapboxLegCount: number | null;
    arriveManeuverCount: number | null;
    silentViaFallbackUsed: boolean;
  };
  type RoundTripFetchAttempt = {
    fetchResult: Awaited<ReturnType<typeof getMapboxRouteDetailed>>;
    callsUsed: number;
    failureResults: Awaited<ReturnType<typeof getMapboxRouteDetailed>>[];
    silentViaRequested: boolean;
    silentViaFallbackUsed: boolean;
  };
  let balancedHasPresentableCandidate = false;
  let balancedTerminalShortCircuit = false;
  const rejectReasons = new Map<string, number>();
  const lastPlanLabels: string[] = [];
  const seenRouteFingerprints = new Set<string>([
    ...normalizedPreviousRouteFingerprints,
    ...(normalizedFingerprintHint ? [normalizedFingerprintHint] : []),
  ]);
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
      forceLegacyWaypoints?: boolean;
    };
    routeRequestMeta: RoundTripRouteRequestMeta;
  } | null = null;
  let rateLimitHits = 0;
  let timeoutHits = 0;
  let stopSearchWithBestCandidate = false;
  let mapboxCallCount = 0;
  let evaluatedRouteCount = 0;
  let guidanceHydrationCount = 0;
  let bestPhaseName: string | null = null;
  let bestCandidateFamily: string | null = null;
  let bestDistanceFitTier: string | null = null;
  let bestRouteRequestMeta: RoundTripRouteRequestMeta | null = null;
  let silentViaAttempted = false;
  let silentViaFallbackUsed = false;
  let lastSilentViaWaypoints: string | null = null;
  let lastSilentViaShapingPointCount = 0;
  let lastSilentViaMapboxLegCount: number | null = null;
  let lastSilentViaArriveManeuverCount: number | null = null;
  let guidanceDegraded = false;
  let hydrationFallbackUsed = false;
  let finalGeometrySource:
    | "hydrated"
    | "pre_hydration_fallback"
    | "duplicate_fallback" = "hydrated";
  let postHydrationRejectReason: string | null = null;
  let preHydrationQualityTier: string | null = null;
  const hydrationDiagnostics: Record<string, unknown>[] = [];

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
  const silentViaWaypointIndexes = (plan: RoundTripCandidatePlan): number[] =>
    plan.waypoints.length > 2 ? [0, plan.waypoints.length - 1] : [];
  const silentViaWaypointString = (
    plan: RoundTripCandidatePlan,
  ): string | null =>
    plan.waypoints.length > 2 ? `0;${plan.waypoints.length - 1}` : null;
  const countRouteLegs = (route: any): number | null =>
    Array.isArray(route?.legs) ? route.legs.length : null;
  const countArriveManeuvers = (route: any): number | null => {
    if (!Array.isArray(route?.legs)) return null;
    let count = 0;
    for (const leg of route.legs) {
      if (!Array.isArray(leg?.steps)) continue;
      for (const step of leg.steps) {
        const maneuverType = String(step?.maneuver?.type ?? "").toLowerCase();
        if (maneuverType === "arrive" || maneuverType === "arrive waypoint") {
          count += 1;
        }
      }
    }
    return count;
  };
  const routeRequestMeta = (
    plan: RoundTripCandidatePlan,
    route: any,
    options: { silentViaUsed: boolean; silentViaFallbackUsed: boolean },
  ): RoundTripRouteRequestMeta => ({
    silentViaUsed: options.silentViaUsed,
    silentViaWaypoints: options.silentViaUsed
      ? silentViaWaypointString(plan)
      : null,
    shapingPointCount: Math.max(0, plan.waypoints.length - 2),
    mapboxLegCount: countRouteLegs(route),
    arriveManeuverCount: countArriveManeuvers(route),
    silentViaFallbackUsed: options.silentViaFallbackUsed,
  });
  const routeDistanceKmFromRoute = (route: any): number | null => {
    const distanceMeters = typeof route?.distance === "number"
      ? route.distance
      : null;
    return distanceMeters == null
      ? null
      : Number((distanceMeters / 1000).toFixed(1));
  };
  const routeGeometryChangedRatio = (
    beforeRoute: any,
    afterRoute: any,
  ): number | null => {
    const beforeCoordinates = routeCoordinates(beforeRoute);
    const afterCoordinates = routeCoordinates(afterRoute);
    if (beforeCoordinates.length === 0 || afterCoordinates.length === 0) {
      return null;
    }
    const sampleCount = Math.min(
      12,
      beforeCoordinates.length,
      afterCoordinates.length,
    );
    if (sampleCount <= 1) return 0;
    let totalDeltaKm = 0;
    for (let index = 0; index < sampleCount; index += 1) {
      const ratio = index / (sampleCount - 1);
      const beforeIndex = Math.round((beforeCoordinates.length - 1) * ratio);
      const afterIndex = Math.round((afterCoordinates.length - 1) * ratio);
      totalDeltaKm += calculateDistance(
        beforeCoordinates[beforeIndex],
        afterCoordinates[afterIndex],
      );
    }
    return Number(
      Math.min(1, totalDeltaKm / sampleCount / Math.max(1, targetDistanceKm))
        .toFixed(3),
    );
  };
  const recordHydrationDiagnostic = (
    args: {
      candidate: {
        plan: RoundTripCandidatePlan;
        phaseName: string;
        distanceFitTier: string;
        route: any;
        fingerprint: string;
        quality: RouteQualityEvaluation;
        routeRequestMeta: RoundTripRouteRequestMeta;
      };
      hydrationAttempted: boolean;
      hydrationOutcome: string;
      hydratedRoute?: any | null;
      hydratedQuality?: RouteQualityEvaluation | null;
      hydratedMeta?: RoundTripRouteRequestMeta | null;
      rejectReason?: string | null;
    },
  ): void => {
    if (hydrationDiagnostics.length >= 12) return;
    const preShape = args.candidate.quality.shapeMetrics;
    const postShape = args.hydratedQuality?.shapeMetrics;
    hydrationDiagnostics.push({
      candidate_family: args.candidate.plan.label,
      phase: args.candidate.phaseName,
      pre_hydration_status: args.candidate.quality.tier,
      pre_hydration_quality_passed:
        args.candidate.quality.tier !== "rejected",
      pre_hydration_distance_km: Number(
        args.candidate.quality.actualDistanceKm.toFixed(1),
      ),
      pre_hydration_fingerprint: args.candidate.fingerprint,
      pre_hydration_shape_score: preShape == null
        ? null
        : Number(preShape.loopnessScore.toFixed(1)),
      pre_hydration_reject_reason:
        args.candidate.quality.tier === "rejected"
          ? args.candidate.quality.reason
          : null,
      hydration_attempted: args.hydrationAttempted,
      hydration_outcome: args.hydrationOutcome,
      hydration_distance_km: args.hydratedQuality == null
        ? routeDistanceKmFromRoute(args.hydratedRoute)
        : Number(args.hydratedQuality.actualDistanceKm.toFixed(1)),
      hydration_leg_count: args.hydratedMeta?.mapboxLegCount ??
        countRouteLegs(args.hydratedRoute),
      hydration_arrive_count: args.hydratedMeta?.arriveManeuverCount ??
        countArriveManeuvers(args.hydratedRoute),
      hydration_maneuver_count: Array.isArray(args.hydratedRoute?.legs)
        ? args.hydratedRoute.legs.reduce((sum: number, leg: any) => {
          if (!Array.isArray(leg?.steps)) return sum;
          return sum + leg.steps.length;
        }, 0)
        : null,
      hydration_geometry_changed_ratio: args.hydratedRoute == null
        ? null
        : routeGeometryChangedRatio(
          args.candidate.route,
          args.hydratedRoute,
        ),
      hydration_fingerprint: args.hydratedRoute == null
        ? null
        : buildRouteFingerprintFromRoute(args.hydratedRoute),
      post_hydration_quality_passed:
        args.hydratedQuality == null
          ? false
          : args.hydratedQuality.tier !== "rejected",
      post_hydration_reject_reason: args.rejectReason ?? null,
      post_loopness_score: postShape == null
        ? null
        : Number(postShape.loopnessScore.toFixed(1)),
      post_spur_score: postShape == null
        ? null
        : Number(postShape.spurScore.toFixed(1)),
      post_out_and_back_score: postShape == null
        ? null
        : Number(postShape.outAndBackScore.toFixed(1)),
      silent_via_used: args.candidate.routeRequestMeta.silentViaUsed,
      mapbox_leg_count: args.candidate.routeRequestMeta.mapboxLegCount,
      arrive_maneuver_count:
        args.candidate.routeRequestMeta.arriveManeuverCount,
    });
  };
  const recordProviderFailures = (
    failures: RoundTripFetchAttempt["failureResults"],
  ): void => {
    for (const failure of failures) {
      const failureKind = getRetryKindFromMapboxFailure(failure);
      if (failureKind === "rate_limit") rateLimitHits += 1;
      if (failureKind === "timeout") timeoutHits += 1;
    }
  };
  const shouldFallbackFromSilentViaFailure = (
    fetchResult: Awaited<ReturnType<typeof getMapboxRouteDetailed>>,
  ): boolean =>
    fetchResult.route == null &&
    (
      fetchResult.outcome === "http_error" ||
      fetchResult.outcome === "network_error" ||
      fetchResult.outcome === "timeout"
    );
  const fetchRoundTripPlanRoute = async (
    plan: RoundTripCandidatePlan,
    request: {
      exclude: string;
      radiuses: string;
      continueStraight: boolean;
      alternatives: boolean;
      bearings: string;
      avoidManeuverRadiusMeters?: number;
      maxAttempts: number;
      timeoutMs: number;
      retryDelayBaseMs?: number;
      includeGuidance: boolean;
      overview?: "full" | "simplified";
      forceLegacyWaypoints?: boolean;
    },
  ): Promise<RoundTripFetchAttempt> => {
    const routeLegWaypointIndexes = silentViaWaypointIndexes(plan);
    if (routeLegWaypointIndexes.length < 2 || request.forceLegacyWaypoints) {
      const legacyFetch = await getMapboxRouteDetailed(
        plan.waypoints,
        mapboxProfile,
        request.exclude,
        request.radiuses,
        accessToken,
        {
          continueStraight: request.continueStraight,
          alternatives: request.alternatives,
          bearings: request.bearings,
          avoidManeuverRadiusMeters: request.avoidManeuverRadiusMeters,
          maxAttempts: request.maxAttempts,
          timeoutMs: request.timeoutMs,
          retryDelayBaseMs: request.retryDelayBaseMs,
          includeGuidance: request.includeGuidance,
          overview: request.overview,
        },
      );
      return {
        fetchResult: legacyFetch,
        callsUsed: 1,
        failureResults: legacyFetch.route == null ? [legacyFetch] : [],
        silentViaRequested: false,
        silentViaFallbackUsed: request.forceLegacyWaypoints === true,
      };
    }

    silentViaAttempted = true;
    lastSilentViaWaypoints = silentViaWaypointString(plan);
    lastSilentViaShapingPointCount = Math.max(0, plan.waypoints.length - 2);
    const silentFetch = await getMapboxRouteDetailed(
      plan.waypoints,
      mapboxProfile,
      request.exclude,
      request.radiuses,
      accessToken,
      {
        continueStraight: request.continueStraight,
        alternatives: request.alternatives,
        bearings: request.bearings,
        avoidManeuverRadiusMeters: request.avoidManeuverRadiusMeters,
        maxAttempts: request.maxAttempts,
        timeoutMs: request.timeoutMs,
        retryDelayBaseMs: request.retryDelayBaseMs,
        includeGuidance: request.includeGuidance,
        // Mapbox requires steps when the `waypoints` index list is supplied.
        // For search calls we request steps without voice/banner guidance.
        steps: true,
        overview: request.overview,
        routeLegWaypointIndexes,
      },
    );
    if (!shouldFallbackFromSilentViaFailure(silentFetch)) {
      if (silentFetch.route != null) {
        lastSilentViaMapboxLegCount = countRouteLegs(silentFetch.route);
        lastSilentViaArriveManeuverCount = countArriveManeuvers(
          silentFetch.route,
        );
      }
      return {
        fetchResult: silentFetch,
        callsUsed: 1,
        failureResults: silentFetch.route == null ? [silentFetch] : [],
        silentViaRequested: true,
        silentViaFallbackUsed: false,
      };
    }

    silentViaFallbackUsed = true;
    registerReject("silent_via_technical_fallback");
    debugWarn(
      `[RT] ${plan.label}: silent-via technical failure (${silentFetch.outcome}), retrying legacy hard-waypoint request`,
    );
    const legacyFetch = await getMapboxRouteDetailed(
      plan.waypoints,
      mapboxProfile,
      request.exclude,
      request.radiuses,
      accessToken,
      {
        continueStraight: request.continueStraight,
        alternatives: request.alternatives,
        bearings: request.bearings,
        avoidManeuverRadiusMeters: request.avoidManeuverRadiusMeters,
        maxAttempts: 1,
        timeoutMs: request.timeoutMs,
        retryDelayBaseMs: request.retryDelayBaseMs,
        includeGuidance: request.includeGuidance,
        overview: request.overview,
      },
    );
    return {
      fetchResult: legacyFetch,
      callsUsed: 2,
      failureResults: [
        silentFetch,
        ...(legacyFetch.route == null ? [legacyFetch] : []),
      ],
      silentViaRequested: true,
      silentViaFallbackUsed: true,
    };
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
  const distanceFitTierForQuality = (
    quality: RouteQualityEvaluation,
    qualityDistanceConfig: DistanceConfig,
  ): string => {
    const distanceKm = quality.actualDistanceKm;
    if (
      distanceKm >= qualityDistanceConfig.minKm &&
      distanceKm <= qualityDistanceConfig.maxKm
    ) {
      return "ideal";
    }
    if (
      distanceKm >= qualityDistanceConfig.acceptableMinKm &&
      distanceKm <= qualityDistanceConfig.acceptableMaxKm
    ) {
      return "acceptable";
    }
    return "outside_bucket";
  };
  const shouldRequestSearchAlternatives = (
    phaseName: string,
    planLabel: string,
    phaseAttemptIndex: number,
  ): boolean => {
    if (useSearchAlternatives) return phaseName !== "strict";
    if (!useSelectiveNoHighwayAlternatives) return false;
    if (phaseName === "strict") return false;
    if (phaseAttemptIndex > 2) return false;

    const label = planLabel.toLowerCase();
    return label.includes("compact") ||
      label.includes("asymmetric") ||
      label.includes("cardinal") ||
      label.includes("distributed") ||
      label.includes("hillside") ||
      label.includes("two-lobe") ||
      label.includes("regional") ||
      label.includes("sector") ||
      label.includes("long-oval");
  };
  const applyCleanupGate = (
    route: any,
    quality: RouteQualityEvaluation,
    qualityDistanceConfig: DistanceConfig,
    cleanupAvoidHighways: boolean,
  ): RouteQualityEvaluation => {
    if (quality.tier === "rejected") {
      return quality;
    }
    const cleanup = evaluateRouteCleanupGate(route, "ROUND_TRIP", {
      targetDistanceKm,
      distanceConfig: qualityDistanceConfig,
      mode,
      avoidHighways: cleanupAvoidHighways,
      startLocation,
    });
    if (cleanup.passed) {
      return quality;
    }
    const cleanedDistanceKm = cleanup.cleanedDistanceKm > 0
      ? cleanup.cleanedDistanceKm
      : quality.actualDistanceKm;
    return {
      ...quality,
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
  const requestedStyleLabel = mode ?? "Standard";
  const deliveredStyleForSafeFallback = (
    quality: RouteQualityEvaluation,
  ): string => {
    if (mode !== "Kurvenjagd") return requestedStyleLabel;
    const curveDensity = quality.styleMetrics?.curveDensityPer50Km ?? 0;
    return curveDensity >= 80 ? "relaxed_curvy" : "sport_like";
  };
  const safeFallbackBounds = (): { minKm: number; maxKm: number } | null => {
    if (targetDistanceKm <= 60) return { minKm: 42, maxKm: 65 };
    if (targetDistanceKm <= 85) return { minKm: 62, maxKm: 90 };
    if (targetDistanceKm <= 115) return { minKm: 85, maxKm: 118 };
    return null;
  };
  const isHardRejectReason = (reason: string): boolean => {
    const normalized = reason.toLowerCase();
    return normalized.includes("u_turn") ||
      normalized.includes("dead_end") ||
      normalized.includes("route_stub") ||
      normalized.includes("out_and_back") ||
      normalized.startsWith("hooks=") ||
      normalized.startsWith("center_return=") ||
      normalized.startsWith("cleanup_u_turn");
  };
  const isSoftFallbackReason = (reason: string): boolean => {
    const normalized = reason.toLowerCase();
    return normalized.startsWith("short_sport_distance=") ||
      normalized.startsWith("short_sport_shape=") ||
      normalized.startsWith("short_sport_overlap=") ||
      normalized.startsWith("distance=") ||
      normalized.startsWith("cleanup_short_sport_shape=") ||
      normalized.startsWith("cleanup_short_sport_distance=") ||
      normalized.startsWith("cleanup_distance=");
  };
  const applySafeFallbackTier = (
    quality: RouteQualityEvaluation,
    selectedExclude: string,
  ): RouteQualityEvaluation => {
    if (quality.tier !== "rejected") return quality;
    const bounds = safeFallbackBounds();
    if (bounds == null) return quality;
    if (
      avoidHighways &&
      !normalizeExcludeParams(selectedExclude).includes("motorway")
    ) {
      return quality;
    }
    if (!isSoftFallbackReason(quality.reason)) return quality;
    const shape = quality.shapeMetrics;
    if (shape == null) return quality;
    if (
      quality.actualDistanceKm < bounds.minKm ||
      quality.actualDistanceKm > bounds.maxKm
    ) {
      return quality;
    }
    const loopnessMin = mode === "Kurvenjagd" ? 52 : 56;
    const spurMax = mode === "Kurvenjagd" ? 30 : 26;
    const outAndBackMax = mode === "Kurvenjagd" ? 28 : 24;
    const deadEndMax = mode === "Kurvenjagd" ? 28 : 24;
    const strictShortSportLocalHairpinOk = mode === "Sport Mode" &&
      targetDistanceKm <= 60 &&
      shape.geometricUTurnCount <= 1 &&
      shape.cleanupUTurnCount <= 1 &&
      shape.loopnessScore >= 78 &&
      shape.spurScore <= 14 &&
      shape.outAndBackScore <= 14 &&
      shape.deadEndArmScore <= 18 &&
      shape.middleCoverageRatio >= 0.58 &&
      shape.foldedLoopPenalty <= 36 &&
      shape.oppositeOverlapPercent <= 10 &&
      shape.centerReentryCount === 0 &&
      shape.repeatedStartAreaPercent <= 10 &&
      shape.centralReturnPercent <= 8 &&
      shape.cleanupRemovedPercent <= 12 &&
      shape.cleanupDistanceRetentionRatio >= 0.88 &&
      quality.overlapPercent <= 22;
    const cleanShortSportValleyHairpinOk = mode === "Sport Mode" &&
      targetDistanceKm <= 60 &&
      shape.geometricUTurnCount <= 2 &&
      shape.cleanupUTurnCount <= 2 &&
      shape.loopnessScore >= 78 &&
      shape.spurScore <= 8 &&
      shape.outAndBackScore <= 8 &&
      shape.deadEndArmScore <= 12 &&
      shape.middleCoverageRatio >= 0.64 &&
      shape.foldedLoopPenalty <= 55 &&
      shape.oppositeOverlapPercent <= 6 &&
      shape.centerReentryCount === 0 &&
      shape.repeatedStartAreaPercent <= 8 &&
      shape.centralReturnPercent <= 5 &&
      shape.cleanupRemovedPercent <= 8 &&
      shape.cleanupDistanceRetentionRatio >= 0.94 &&
      quality.overlapPercent <= 16;
    const pragmaticShortSportValleyHairpinOk = mode === "Sport Mode" &&
      targetDistanceKm <= 60 &&
      shape.geometricUTurnCount <= 2 &&
      shape.cleanupUTurnCount <= 1 &&
      shape.loopnessScore >= 62 &&
      shape.spurScore <= 8 &&
      shape.outAndBackScore <= 12 &&
      shape.deadEndArmScore <= 12 &&
      shape.middleCoverageRatio >= 0.60 &&
      shape.foldedLoopPenalty <= 56 &&
      shape.oppositeOverlapPercent <= 7 &&
      shape.centerReentryCount === 0 &&
      shape.repeatedStartAreaPercent <= 8 &&
      shape.centralReturnPercent <= 6 &&
      shape.cleanupRemovedPercent <= 8 &&
      shape.cleanupDistanceRetentionRatio >= 0.96 &&
      quality.overlapPercent <= 18;
    const relaxedShortSportValleyFallbackOk = mode === "Sport Mode" &&
      targetDistanceKm <= 60 &&
      shape.geometricUTurnCount <= 3 &&
      shape.cleanupUTurnCount <= 2 &&
      shape.loopnessScore >= 46 &&
      shape.spurScore <= 4 &&
      shape.outAndBackScore <= 18 &&
      shape.deadEndArmScore <= 8 &&
      shape.centerReentryCount <= 1 &&
      shape.repeatedStartAreaPercent <= 12 &&
      shape.centralReturnPercent <= 10 &&
      shape.oppositeOverlapPercent <= 10 &&
      shape.cleanupRemovedPercent <= 8 &&
      shape.cleanupDistanceRetentionRatio >= 0.94 &&
      quality.overlapPercent <= 22;
    const cleanLocalStyleHairpinOk = mode !== "Sport Mode" &&
      targetDistanceKm <= 85 &&
      shape.geometricUTurnCount <= (mode === "Kurvenjagd" ? 3 : 2) &&
      shape.cleanupUTurnCount <= 2 &&
      shape.loopnessScore >= (mode === "Kurvenjagd" ? 70 : 76) &&
      shape.spurScore <= 10 &&
      shape.outAndBackScore <= 12 &&
      shape.deadEndArmScore <= 12 &&
      shape.centerReentryCount <= 1 &&
      shape.repeatedStartAreaPercent <= 10 &&
      shape.centralReturnPercent <= 8 &&
      shape.oppositeOverlapPercent <= 8 &&
      shape.cleanupRemovedPercent <= 8 &&
      shape.cleanupDistanceRetentionRatio >= 0.96 &&
      quality.overlapPercent <= 18;
    const localHairpinSafeOk = strictShortSportLocalHairpinOk ||
      cleanShortSportValleyHairpinOk ||
      pragmaticShortSportValleyHairpinOk ||
      relaxedShortSportValleyFallbackOk ||
      cleanLocalStyleHairpinOk;
    if (
      (quality.hasUTurn || isHardRejectReason(quality.reason)) &&
      !localHairpinSafeOk
    ) {
      return quality;
    }
    const effectiveLoopnessMin = relaxedShortSportValleyFallbackOk
      ? 46
      : loopnessMin;
    const cleanEnough = shape.loopnessScore >= effectiveLoopnessMin &&
      shape.spurScore <= spurMax &&
      shape.outAndBackScore <= outAndBackMax &&
      shape.deadEndArmScore <= deadEndMax &&
      (
        localHairpinSafeOk ||
        (shape.geometricUTurnCount <= 0 && shape.cleanupUTurnCount <= 0)
      ) &&
      shape.centerReentryCount <= 1 &&
      shape.oppositeOverlapPercent <= 12 &&
      shape.cleanupRemovedPercent <= 18 &&
      shape.cleanupDistanceRetentionRatio >= 0.84 &&
      quality.overlapPercent <= 28;
    if (!cleanEnough) return quality;
    const deliveredStyle = deliveredStyleForSafeFallback(quality);
    return {
      ...quality,
      passed: true,
      reason: `safe_fallback:${quality.reason}`,
      tier: "acceptable",
      score: Math.min(quality.score, 390),
      safeFallbackUsed: true,
      safeFallbackReason: quality.reason,
      requestedStyle: requestedStyleLabel,
      deliveredStyle,
      styleDowngraded: deliveredStyle !== requestedStyleLabel,
    };
  };
  const evaluateRouteAlternative = (
    route: any,
    qualityDistanceConfig: DistanceConfig,
    selectedExclude: string,
  ): RouteQualityEvaluation => {
    const evaluationAvoidHighways = avoidHighways ||
      normalizeExcludeParams(selectedExclude).includes("motorway");
    const quality = applyPreferenceScoring(
      route,
      applyCleanupGate(
        route,
        evaluateRouteQuality(route, "ROUND_TRIP", {
          targetDistanceKm,
          distanceConfig: qualityDistanceConfig,
          mode,
          avoidHighways: evaluationAvoidHighways,
        }),
        qualityDistanceConfig,
        evaluationAvoidHighways,
      ),
    );
    const safeQuality = applySafeFallbackTier(quality, selectedExclude);
    if (safeQuality.safeFallbackUsed === true || quality.shapeMetrics != null) {
      return safeQuality;
    }
    const needsDiagnosticShape = quality.reason.startsWith(
      "short_sport_distance=",
    ) ||
      quality.reason.startsWith("cleanup_distance=") ||
      quality.reason.startsWith("cleanup_short_sport_shape=") ||
      quality.reason.startsWith("cleanup_short_sport_distance=");
    if (!needsDiagnosticShape) {
      return safeQuality;
    }

    // Some short-Sport rejects are emitted by the cleanup gate after the
    // original quality object has been replaced by cleanup diagnostics. Re-run
    // the original route quality to recover shape metrics, then only rescue if
    // the strict safe-fallback shape gate passes. This does not make
    // U-turn/stub/out-and-back routes acceptable.
    const diagnosticQuality = applyPreferenceScoring(
      route,
      evaluateRouteQuality(route, "ROUND_TRIP", {
        targetDistanceKm,
        distanceConfig: qualityDistanceConfig,
        mode,
        avoidHighways: avoidHighways ||
          selectedExclude.split(",").map((part) => part.trim()).includes(
            "motorway",
          ),
      }),
    );
    return applySafeFallbackTier({
      ...diagnosticQuality,
      passed: false,
      reason: quality.reason,
      tier: "rejected",
      score: quality.score,
      actualDistanceKm: quality.actualDistanceKm,
      distanceDeltaKm: quality.distanceDeltaKm,
    }, selectedExclude);
  };
  const chooseBestRouteAlternative = (
    routes: any[],
    qualityDistanceConfig: DistanceConfig,
    selectedExclude: string,
    options?: {
      maxCoordinateCount?: number;
      geometryRejectReason?: string;
    },
  ): { route: any; quality: RouteQualityEvaluation } | null => {
    let selectedRoute: any = null;
    let selectedQuality: RouteQualityEvaluation | null = null;
    const maxCoordinateCount = options?.maxCoordinateCount ??
      maxSearchRouteCoordinates;
    const geometryRejectReason = options?.geometryRejectReason ??
      "geometry_too_large";
    for (const routeOption of routes) {
      const routeCoordinateCount = Array.isArray(
          routeOption?.geometry?.coordinates,
        )
        ? routeOption.geometry.coordinates.length
        : 0;
      if (routeCoordinateCount > maxCoordinateCount) {
        registerReject(geometryRejectReason);
        continue;
      }
      evaluatedRouteCount += 1;
      const optionQuality = evaluateRouteAlternative(
        routeOption,
        qualityDistanceConfig,
        selectedExclude,
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
  const shouldTryShortSportLegacyReverse = (
    plan: RoundTripCandidatePlan,
  ): boolean =>
    avoidHighwaysRoundTripSearch &&
    mode === "Sport Mode" &&
    targetDistanceKm <= 60 &&
    plan.waypoints.length > 3;
  const shouldUseLegacyWaypointsFirst = (
    plan: RoundTripCandidatePlan,
  ): boolean =>
    mode === "Sport Mode" &&
    targetDistanceKm <= 60 &&
    plan.label.startsWith("nohw-short-sport-valley-clean");
  let lastHydrationRejectReason: string | null = null;
  let lastHydrationRoute: any | null = null;
  let lastHydrationQuality: RouteQualityEvaluation | null = null;
  let lastHydrationMeta: RoundTripRouteRequestMeta | null = null;
  const hydrateGuidanceRoute = async (
    plan: RoundTripCandidatePlan,
    context: {
      exclude: string;
      continueStraight: boolean;
      distanceConfig: DistanceConfig;
      forceLegacyWaypoints?: boolean;
    },
  ): Promise<
    {
      route: any;
      quality: RouteQualityEvaluation;
      routeRequestMeta: RoundTripRouteRequestMeta;
    } | null
  > => {
    lastHydrationRejectReason = null;
    lastHydrationRoute = null;
    lastHydrationQuality = null;
    lastHydrationMeta = null;
    let attempt = await fetchRoundTripPlanRoute(plan, {
      exclude: context.exclude,
      radiuses: effectivePlanRadiuses(plan),
      continueStraight: context.continueStraight,
      alternatives: false,
      bearings: effectivePlanBearings(plan),
      avoidManeuverRadiusMeters: effectiveAvoidManeuverRadius,
      maxAttempts: 1,
      timeoutMs: boundedMapboxTimeoutMs(mapboxCandidateTimeoutMs, 3000),
      retryDelayBaseMs: 220,
      includeGuidance: true,
      overview: avoidHighwaysRoundTripSearch ? "simplified" : "full",
      forceLegacyWaypoints: context.forceLegacyWaypoints === true,
    });
    mapboxCallCount += attempt.callsUsed;
    guidanceHydrationCount += attempt.callsUsed;
    recordProviderFailures(attempt.failureResults);
    if (shouldAbortForProviderPressure()) return null;
    if (!attempt.fetchResult.route) {
      lastHydrationRejectReason = attempt.fetchResult.outcome === "http_error"
        ? `guidance_mapbox_http_${attempt.fetchResult.statusCode ?? "unknown"}`
        : `guidance_mapbox_${attempt.fetchResult.outcome}`;
      registerReject(lastHydrationRejectReason);
      return null;
    }
    let selection = chooseBestRouteAlternative(
      [attempt.fetchResult.route],
      context.distanceConfig,
      context.exclude,
      {
        maxCoordinateCount: maxHydratedRouteCoordinates,
        geometryRejectReason: "guidance_geometry_too_large",
      },
    );
    if (
      (selection == null || selection.quality.tier === "rejected") &&
      context.forceLegacyWaypoints !== true &&
      attempt.silentViaRequested &&
      hasMapboxCallBudget(2500)
    ) {
      const legacyAttempt = await fetchRoundTripPlanRoute(plan, {
        exclude: context.exclude,
        radiuses: effectivePlanRadiuses(plan),
        continueStraight: context.continueStraight,
        alternatives: false,
        bearings: effectivePlanBearings(plan),
        avoidManeuverRadiusMeters: effectiveAvoidManeuverRadius,
        maxAttempts: 1,
        timeoutMs: boundedMapboxTimeoutMs(mapboxCandidateTimeoutMs, 3000),
        retryDelayBaseMs: 220,
        includeGuidance: true,
        overview: avoidHighwaysRoundTripSearch ? "simplified" : "full",
        forceLegacyWaypoints: true,
      });
      mapboxCallCount += legacyAttempt.callsUsed;
      guidanceHydrationCount += legacyAttempt.callsUsed;
      recordProviderFailures(legacyAttempt.failureResults);
      if (legacyAttempt.fetchResult.route != null) {
        const legacySelection = chooseBestRouteAlternative(
          [legacyAttempt.fetchResult.route],
          context.distanceConfig,
          context.exclude,
          {
            maxCoordinateCount: maxHydratedRouteCoordinates,
            geometryRejectReason: "guidance_geometry_too_large",
          },
        );
        if (
          legacySelection != null &&
          (
            selection == null ||
            legacySelection.quality.tier !== "rejected" ||
            legacySelection.quality.score < selection.quality.score
          )
        ) {
          selection = legacySelection;
          attempt = legacyAttempt;
        }
      }
    }
    if (
      shouldTryShortSportLegacyReverse(plan) &&
      context.continueStraight !== false &&
      hasMapboxCallBudget(2500)
    ) {
      const reverseLegacyAttempt = await fetchRoundTripPlanRoute(plan, {
        exclude: context.exclude,
        radiuses: effectivePlanRadiuses(plan),
        continueStraight: false,
        alternatives: false,
        bearings: effectivePlanBearings(plan),
        avoidManeuverRadiusMeters: effectiveAvoidManeuverRadius,
        maxAttempts: 1,
        timeoutMs: boundedMapboxTimeoutMs(mapboxCandidateTimeoutMs, 3000),
        retryDelayBaseMs: 220,
        includeGuidance: true,
        overview: avoidHighwaysRoundTripSearch ? "simplified" : "full",
        forceLegacyWaypoints: true,
      });
      mapboxCallCount += reverseLegacyAttempt.callsUsed;
      guidanceHydrationCount += reverseLegacyAttempt.callsUsed;
      recordProviderFailures(reverseLegacyAttempt.failureResults);
      if (reverseLegacyAttempt.fetchResult.route != null) {
        const reverseLegacySelection = chooseBestRouteAlternative(
          [reverseLegacyAttempt.fetchResult.route],
          context.distanceConfig,
          context.exclude,
          {
            maxCoordinateCount: maxHydratedRouteCoordinates,
            geometryRejectReason: "guidance_geometry_too_large",
          },
        );
        if (
          reverseLegacySelection != null &&
          (
            selection == null ||
            reverseLegacySelection.quality.tier !== "rejected" ||
            reverseLegacySelection.quality.score < selection.quality.score
          )
        ) {
          selection = reverseLegacySelection;
          attempt = reverseLegacyAttempt;
        }
      }
    }
    if (selection == null || selection.quality.tier === "rejected") {
      lastHydrationRejectReason = selection?.quality.reason != null
        ? `guidance_${selection.quality.reason}`
        : "guidance_quality_rejected";
      lastHydrationRoute = selection?.route ?? attempt.fetchResult.route;
      lastHydrationQuality = selection?.quality ?? null;
      lastHydrationMeta = routeRequestMeta(
        plan,
        lastHydrationRoute,
        {
          silentViaUsed: attempt.silentViaRequested &&
            !attempt.silentViaFallbackUsed,
          silentViaFallbackUsed: attempt.silentViaFallbackUsed,
        },
      );
      registerReject(lastHydrationRejectReason);
      return null;
    }
    lastHydrationRoute = selection.route;
    lastHydrationQuality = selection.quality;
    lastHydrationMeta = routeRequestMeta(plan, selection.route, {
      silentViaUsed: attempt.silentViaRequested &&
        !attempt.silentViaFallbackUsed,
      silentViaFallbackUsed: attempt.silentViaFallbackUsed,
    });
    return {
      ...selection,
      routeRequestMeta: lastHydrationMeta,
    };
  };

  for (const phase of searchPhases) {
    if (stopSearchWithBestCandidate) break;
    const phasePlanAvoidHighways = phase.planAvoidHighways ?? avoidHighways;
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
          avoidHighways: phasePlanAvoidHighways,
        }),
        phase.name,
        normalizedVariantHint,
        normalizedFingerprintHint,
        {
          mode,
          avoidHighways: phasePlanAvoidHighways,
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
    const phaseIsNoHighwaySearch = phasePlanAvoidHighways === true;
    const declaredMaxPerPhase = phase.name === "strict"
      ? phaseIsNoHighwaySearch
        ? targetDistanceKm <= 60 ? 5 : 5
        : shortSportHighwayRoundTrip
        ? 4
        : mode === "Sport Mode" && targetDistanceKm >= 75
        ? 3
        : 2
      : phase.name === "balanced"
      ? phaseIsNoHighwaySearch
        ? targetDistanceKm <= 60 ? 5 : 5
        : shortSportHighwayRoundTrip
        ? 4
        : mode === "Sport Mode" && targetDistanceKm >= 75
        ? 3
        : 2
      : phaseIsNoHighwaySearch
      ? targetDistanceKm <= 60 ? 5 : targetDistanceKm <= 85 ? 5 : 6
      : shortSportHighwayRoundTrip
      ? 4
      : shortCurvySearch
      ? 4
      : constrainedRoundTripSearch
      ? 3
      : mode === "Sport Mode" && targetDistanceKm >= 75
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
    const useHighwaySliceOffset = shortSportHighwayRoundTrip &&
      phasePlanAvoidHighways !== true;
    const highwayPhaseStride = useHighwaySliceOffset ? 4 : 0;
    const maxSliceStart = Math.max(
      0,
      orderedCandidates.length - maxPhaseAttempts,
    );
    const sliceStart = useHighwaySliceOffset
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
      if (lastPlanLabels.length < 12) {
        lastPlanLabels.push(`${phase.name}/${plan.label}`);
      }
      debugLog(
        `[RT] Candidate ${candidateAttempts}: ${phase.name}/${plan.label} (${
          plan.waypoints.length - 2
        } WPs)`,
      );
      const requestAlternatives = shouldRequestSearchAlternatives(
        phase.name,
        plan.label,
        phaseAttempts,
      );
      const maxEvaluatedAlternatives = requestAlternatives
        ? (avoidHighwaysRoundTripSearch ? 2 : 3)
        : 1;

      let fetchAttempt = await fetchRoundTripPlanRoute(plan, {
        exclude: phase.exclude,
        radiuses: effectivePlanRadiuses(plan),
        continueStraight: phase.continueStraight,
        alternatives: requestAlternatives,
        bearings: effectivePlanBearings(plan),
        avoidManeuverRadiusMeters: effectiveAvoidManeuverRadius,
        maxAttempts: candidateAttempts >= 2 || !hasMapboxCallBudget(8000)
          ? 1
          : mapboxCandidateMaxAttempts,
        timeoutMs: boundedMapboxTimeoutMs(mapboxCandidateTimeoutMs),
        retryDelayBaseMs: 220,
        includeGuidance: false,
        forceLegacyWaypoints: shouldUseLegacyWaypointsFirst(plan),
      });
      mapboxCallCount += fetchAttempt.callsUsed;
      recordProviderFailures(fetchAttempt.failureResults);
      let fetchResult = fetchAttempt.fetchResult;
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
        const relaxedAttempt = await fetchRoundTripPlanRoute(plan, {
          exclude: relaxedPhaseExclude,
          radiuses: effectivePlanRadiuses(plan),
          continueStraight: phase.continueStraight,
          alternatives: false,
          bearings: effectivePlanBearings(plan),
          avoidManeuverRadiusMeters: effectiveAvoidManeuverRadius,
          maxAttempts: 1,
          timeoutMs: boundedMapboxTimeoutMs(mapboxRelaxedTimeoutMs),
          includeGuidance: false,
        });
        mapboxCallCount += relaxedAttempt.callsUsed;
        recordProviderFailures(relaxedAttempt.failureResults);
        if (shouldAbortForProviderPressure()) break;
        if (relaxedAttempt.fetchResult.outcome === "ok") {
          fetchAttempt = relaxedAttempt;
          fetchResult = relaxedAttempt.fetchResult;
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
        recordRejectSample({
          phaseName: phase.name,
          plan,
          reason,
          exclude: phase.exclude,
        });
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
        phase.exclude,
      );
      if (primarySelection == null) {
        rejectedCandidates += 1;
        registerReject("mapbox_empty_route");
        recordRejectSample({
          phaseName: phase.name,
          plan,
          reason: "mapbox_empty_route",
          route: primaryRoutes[0],
          routeRequestMeta: routeRequestMeta(plan, primaryRoutes[0], {
            silentViaUsed: fetchAttempt.silentViaRequested &&
              !fetchAttempt.silentViaFallbackUsed,
            silentViaFallbackUsed: fetchAttempt.silentViaFallbackUsed,
          }),
          exclude: phase.exclude,
        });
        continue;
      }
      let route = primarySelection.route;
      let quality = primarySelection.quality;
      let selectedExclude = phase.exclude;
      let selectedContinueStraight = phase.continueStraight;
      let selectedDistanceConfig = phase.distanceConfig;
      let selectedForceLegacyWaypoints = false;
      let selectedRouteRequestMeta = routeRequestMeta(plan, route, {
        silentViaUsed: fetchAttempt.silentViaRequested &&
          !fetchAttempt.silentViaFallbackUsed,
        silentViaFallbackUsed: fetchAttempt.silentViaFallbackUsed,
      });

      const shouldTryLegacyQualityFallback = fetchAttempt.silentViaRequested &&
        !fetchAttempt.silentViaFallbackUsed &&
        plan.waypoints.length > 3 &&
        rateLimitHits === 0 &&
        timeoutHits < 2 &&
        hasMapboxCallBudget(3200) &&
        (
          quality.reason.startsWith("u_turn") ||
          quality.reason.startsWith("short_sport_shape=") ||
          quality.reason.startsWith("short_sport_distance=") ||
          quality.reason.startsWith("cleanup_short_sport_shape=") ||
          quality.reason.startsWith("cleanup_short_sport_distance=")
        );
      if (quality.tier === "rejected" && shouldTryLegacyQualityFallback) {
        debugLog(
          `[RT] ${plan.label}: silent-via rejected (${quality.reason}), trying legacy waypoint quality fallback`,
        );
        const legacyContinueStraight = shouldTryShortSportLegacyReverse(plan)
          ? false
          : phase.continueStraight;
        const legacyAttempt = await fetchRoundTripPlanRoute(plan, {
          exclude: phase.exclude,
          radiuses: effectivePlanRadiuses(plan),
          continueStraight: legacyContinueStraight,
          alternatives: requestAlternatives,
          bearings: effectivePlanBearings(plan),
          avoidManeuverRadiusMeters: effectiveAvoidManeuverRadius,
          maxAttempts: 1,
          timeoutMs: boundedMapboxTimeoutMs(mapboxCandidateTimeoutMs),
          includeGuidance: false,
          forceLegacyWaypoints: true,
        });
        mapboxCallCount += legacyAttempt.callsUsed;
        recordProviderFailures(legacyAttempt.failureResults);
        if (shouldAbortForProviderPressure()) break;
        const legacyRoutes = legacyAttempt.fetchResult.routes?.length
          ? legacyAttempt.fetchResult.routes.slice(0, maxEvaluatedAlternatives)
          : legacyAttempt.fetchResult.route
          ? [legacyAttempt.fetchResult.route]
          : [];
        const legacySelection = chooseBestRouteAlternative(
          legacyRoutes,
          phase.distanceConfig,
          phase.exclude,
        );
        if (legacySelection != null) {
          const legacyQuality = legacySelection.quality;
          debugLog(
            `[RT] ${plan.label}: legacy fallback tier=${legacyQuality.tier}, score=${
              legacyQuality.score.toFixed(1)
            }, distance=${legacyQuality.actualDistanceKm.toFixed(1)}km`,
          );
          if (
            legacyQuality.tier !== "rejected" ||
            legacyQuality.score < quality.score
          ) {
            route = legacySelection.route;
            quality = legacyQuality;
            selectedExclude = phase.exclude;
            selectedContinueStraight = legacyContinueStraight;
            selectedDistanceConfig = phase.distanceConfig;
            selectedForceLegacyWaypoints = true;
            selectedRouteRequestMeta = routeRequestMeta(plan, route, {
              silentViaUsed: false,
              silentViaFallbackUsed: true,
            });
          }
        }
      }

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
        const relaxedAttempt = await fetchRoundTripPlanRoute(plan, {
          exclude: relaxedPhaseExclude,
          radiuses: effectivePlanRadiuses(plan),
          continueStraight: phase.continueStraight,
          alternatives: false,
          bearings: effectivePlanBearings(plan),
          avoidManeuverRadiusMeters: effectiveAvoidManeuverRadius,
          maxAttempts: 1,
          timeoutMs: boundedMapboxTimeoutMs(mapboxRelaxedTimeoutMs),
          includeGuidance: false,
        });
        mapboxCallCount += relaxedAttempt.callsUsed;
        recordProviderFailures(relaxedAttempt.failureResults);
        if (shouldAbortForProviderPressure()) break;
        const relaxedRoutes = relaxedAttempt.fetchResult.routes?.length
          ? relaxedAttempt.fetchResult.routes.slice(0, maxEvaluatedAlternatives)
          : relaxedAttempt.fetchResult.route
          ? [relaxedAttempt.fetchResult.route]
          : [];
        const relaxedSelection = chooseBestRouteAlternative(
          relaxedRoutes,
          phase.distanceConfig,
          relaxedPhaseExclude,
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
            selectedForceLegacyWaypoints = relaxedAttempt
              .silentViaFallbackUsed;
            selectedRouteRequestMeta = routeRequestMeta(plan, route, {
              silentViaUsed: relaxedAttempt.silentViaRequested &&
                !relaxedAttempt.silentViaFallbackUsed,
              silentViaFallbackUsed: relaxedAttempt.silentViaFallbackUsed,
            });
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
        recordRejectSample({
          phaseName: phase.name,
          plan,
          reason: quality.reason,
          route,
          quality,
          routeRequestMeta: selectedRouteRequestMeta,
          exclude: selectedExclude,
        });
        continue;
      }

      const routeFingerprint = buildRouteFingerprintFromRoute(route);
      if (seenRouteFingerprints.has(routeFingerprint)) {
        duplicateSkips += 1;
        registerReject("duplicate_skip");
        recordRejectSample({
          phaseName: phase.name,
          plan,
          reason: "duplicate_skip",
          route,
          quality,
          routeRequestMeta: selectedRouteRequestMeta,
          exclude: selectedExclude,
        });
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
            routeRequestMeta: selectedRouteRequestMeta,
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
      const distanceFitTier = distanceFitTierForQuality(
        quality,
        selectedDistanceConfig,
      );
      const acceptedContext = {
        exclude: selectedExclude,
        continueStraight: selectedContinueStraight,
        distanceConfig: selectedDistanceConfig,
        forceLegacyWaypoints: selectedForceLegacyWaypoints,
      };
      acceptedRouteCandidates.push({
        plan,
        phaseName: phase.name,
        distanceFitTier,
        route,
        fingerprint: routeFingerprint,
        quality,
        context: acceptedContext,
        routeRequestMeta: selectedRouteRequestMeta,
      });
      if (!bestQuality || quality.score < bestQuality.score) {
        bestPlan = plan;
        bestRoute = route;
        bestQuality = quality;
        bestContext = acceptedContext;
        bestPhaseName = phase.name;
        bestCandidateFamily = plan.label;
        bestDistanceFitTier = distanceFitTier;
        bestRouteRequestMeta = selectedRouteRequestMeta;
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
        quality.actualDistanceKm >=
          Math.max(
            selectedDistanceConfig.acceptableMinKm,
            targetDistanceKm * 0.88,
          ) &&
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
      !avoidHighwaysRoundTripSearch
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
        bestEmergencyDuplicate.routeRequestMeta =
          hydratedDuplicate.routeRequestMeta;
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
        radiuses: effectivePlanRadiuses(bestEmergencyDuplicate.plan),
        quality: bestEmergencyDuplicate.quality,
        candidateAttempts,
        acceptedCandidates,
        rejectedCandidates,
        mapboxCallCount,
        evaluatedRouteCount,
        guidanceHydrationCount,
        searchStageSuccess: "duplicate_fallback",
        selectedCandidateFamily: bestEmergencyDuplicate.plan.label,
        distanceFitTier: distanceFitTierForQuality(
          bestEmergencyDuplicate.quality,
          bestEmergencyDuplicate.context.distanceConfig,
        ),
        rejectReasons: Object.fromEntries(rejectReasons),
        searchPhases: searchPhases.map((phase) => phase.name),
        lastPlanLabels,
        variantHint: normalizedVariantHint,
        fingerprintHint: normalizedFingerprintHint,
        duplicateSkips,
        emergencyDuplicateUsed: true,
        safeFallbackUsed:
          bestEmergencyDuplicate.quality.safeFallbackUsed === true,
        safeFallbackReason: bestEmergencyDuplicate.quality.safeFallbackReason ??
          null,
        requestedStyle: bestEmergencyDuplicate.quality.requestedStyle ?? null,
        deliveredStyle: bestEmergencyDuplicate.quality.deliveredStyle ?? null,
        styleDowngraded:
          bestEmergencyDuplicate.quality.styleDowngraded === true,
        silentViaUsed: bestEmergencyDuplicate.routeRequestMeta.silentViaUsed,
        silentViaWaypoints:
          bestEmergencyDuplicate.routeRequestMeta.silentViaWaypoints,
        shapingPointCount:
          bestEmergencyDuplicate.routeRequestMeta.shapingPointCount,
        mapboxLegCount: bestEmergencyDuplicate.routeRequestMeta.mapboxLegCount,
        arriveManeuverCount:
          bestEmergencyDuplicate.routeRequestMeta.arriveManeuverCount,
        silentViaFallbackUsed:
          bestEmergencyDuplicate.routeRequestMeta.silentViaFallbackUsed ||
          silentViaFallbackUsed,
        guidanceDegraded: false,
        hydrationFallbackUsed: false,
        finalGeometrySource: "duplicate_fallback",
        postHydrationRejectReason: null,
        preHydrationQualityTier: bestEmergencyDuplicate.quality.tier,
        hydrationDiagnostics,
        rejectSamples,
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
      mapboxCallCount,
      evaluatedRouteCount,
      guidanceHydrationCount,
      searchStageSuccess: null,
      selectedCandidateFamily: null,
      distanceFitTier: null,
      rejectReasons: Object.fromEntries(rejectReasons),
      searchPhases: searchPhases.map((phase) => phase.name),
      lastPlanLabels,
      variantHint: normalizedVariantHint,
      fingerprintHint: normalizedFingerprintHint,
      duplicateSkips,
      exhausted: true,
      silentViaUsed: silentViaAttempted,
      silentViaWaypoints: lastSilentViaWaypoints,
      shapingPointCount: lastSilentViaShapingPointCount,
      mapboxLegCount: lastSilentViaMapboxLegCount,
      arriveManeuverCount: lastSilentViaArriveManeuverCount,
      silentViaFallbackUsed,
      hydrationDiagnostics,
      rejectSamples,
    };
  }

  if (bestContext != null) {
    let hydratedSelection: {
      plan: RoundTripCandidatePlan;
      phaseName: string;
      distanceFitTier: string;
      route: any;
      quality: RouteQualityEvaluation;
      routeRequestMeta: RoundTripRouteRequestMeta;
    } | null = null;
    const isPreHydrationFallbackAllowed = (
      candidate: typeof acceptedRouteCandidates[number],
    ): boolean => {
      if (candidate.quality.tier === "rejected") return false;
      if (candidate.distanceFitTier === "outside_bucket") {
        const bounds = safeFallbackBounds();
        if (
          bounds == null ||
          candidate.quality.actualDistanceKm < bounds.minKm ||
          candidate.quality.actualDistanceKm > bounds.maxKm ||
          (
            candidate.quality.safeFallbackUsed !== true &&
            candidate.quality.tier !== "ideal" &&
            candidate.quality.tier !== "good"
          )
        ) {
          return false;
        }
      }
      if (
        avoidHighways &&
        !normalizeExcludeParams(candidate.context.exclude).includes("motorway")
      ) {
        return false;
      }
      const shape = candidate.quality.shapeMetrics;
      if (shape == null) return false;
      const candidateNoHighwayCompatible = normalizeExcludeParams(
        candidate.context.exclude,
      ).includes("motorway");
      const fallbackLoopnessMinimum = candidate.quality.safeFallbackUsed === true
        ? mode === "Sport Mode"
          ? 58
          : 52
        : 52;
      if (shape.loopnessScore < fallbackLoopnessMinimum) return false;
      const isLocalHairpinFallback =
        candidate.quality.safeFallbackUsed === true &&
        shape.geometricUTurnCount <= (mode === "Kurvenjagd" ? 3 : 2) &&
        shape.cleanupUTurnCount <= 2 &&
        shape.centerReentryCount <= 1 &&
        shape.cleanupDistanceRetentionRatio >= 0.92;
      const isCleanAcceptedNoHighwaySportHairpin =
        candidate.quality.safeFallbackUsed !== true &&
        mode === "Sport Mode" &&
        candidateNoHighwayCompatible &&
        targetDistanceKm > 60 &&
        targetDistanceKm <= 115 &&
        shape.geometricUTurnCount <= (targetDistanceKm > 85 ? 6 : 5) &&
        shape.cleanupUTurnCount <= (targetDistanceKm > 85 ? 6 : 5) &&
        shape.loopnessScore >= 60 &&
        shape.spurScore <= 24 &&
        shape.outAndBackScore <= 20 &&
        shape.deadEndArmScore <= 20 &&
        shape.centerReentryCount <= 2 &&
        shape.repeatedStartAreaPercent <= 22 &&
        shape.centralReturnPercent <= 18 &&
        shape.oppositeOverlapPercent <= 24 &&
        shape.cleanupRemovedPercent <= 22 &&
        shape.cleanupDistanceRetentionRatio >= 0.82 &&
        candidate.quality.overlapPercent <= 30;
      const isCleanAcceptedNoHighwayStyleHairpin =
        candidate.quality.safeFallbackUsed !== true &&
        mode !== "Sport Mode" &&
        candidateNoHighwayCompatible &&
        targetDistanceKm > 60 &&
        targetDistanceKm <= 115 &&
        shape.geometricUTurnCount <= (mode === "Kurvenjagd" ? 5 : 4) &&
        shape.cleanupUTurnCount <= (mode === "Kurvenjagd" ? 5 : 4) &&
        shape.loopnessScore >= 56 &&
        shape.spurScore <= 28 &&
        shape.outAndBackScore <= 24 &&
        shape.deadEndArmScore <= 24 &&
        shape.centerReentryCount <= 2 &&
        shape.repeatedStartAreaPercent <= 24 &&
        shape.centralReturnPercent <= 20 &&
        shape.oppositeOverlapPercent <= 24 &&
        shape.cleanupRemovedPercent <= 22 &&
        shape.cleanupDistanceRetentionRatio >= 0.82 &&
        candidate.quality.overlapPercent <= 30;
      const hardUTurnPresent =
        candidate.quality.hasUTurn === true &&
        !isLocalHairpinFallback &&
        !isCleanAcceptedNoHighwaySportHairpin &&
        !isCleanAcceptedNoHighwayStyleHairpin;
      if (hardUTurnPresent) return false;
      const loopnessMin = fallbackLoopnessMinimum;
      const spurMax = candidate.quality.safeFallbackUsed === true ? 18 : 30;
      const outAndBackMax = candidate.quality.safeFallbackUsed === true
        ? 18
        : 30;
      const deadEndMax = candidate.quality.safeFallbackUsed === true ? 18 : 30;
      return shape.loopnessScore >= loopnessMin &&
        shape.spurScore <= spurMax &&
        shape.outAndBackScore <= outAndBackMax &&
        shape.deadEndArmScore <= deadEndMax &&
        shape.centerReentryCount <=
          (isCleanAcceptedNoHighwaySportHairpin ||
              isCleanAcceptedNoHighwayStyleHairpin
            ? 2
            : 1) &&
        shape.repeatedStartAreaPercent <=
          (isCleanAcceptedNoHighwaySportHairpin ||
              isCleanAcceptedNoHighwayStyleHairpin
            ? 24
            : 14) &&
        shape.centralReturnPercent <=
          (isCleanAcceptedNoHighwaySportHairpin ||
              isCleanAcceptedNoHighwayStyleHairpin
            ? 20
            : 12) &&
        shape.cleanupRemovedPercent <=
          (isCleanAcceptedNoHighwaySportHairpin ||
              isCleanAcceptedNoHighwayStyleHairpin
            ? 22
            : 14) &&
        candidate.quality.overlapPercent <=
          (isCleanAcceptedNoHighwaySportHairpin ||
              isCleanAcceptedNoHighwayStyleHairpin
            ? 30
            : candidate.quality.safeFallbackUsed === true
            ? 28
            : 24);
    };
    const hydrationFallbackRank = (
      candidate: typeof acceptedRouteCandidates[number],
    ): number => {
      const shape = candidate.quality.shapeMetrics;
      const distancePenalty = candidate.distanceFitTier === "outside_bucket"
        ? 40
        : candidate.distanceFitTier === "acceptable"
        ? 12
        : 0;
      const shapePenalty = shape == null
        ? 200
        : Math.max(0, 72 - shape.loopnessScore) * 6 +
          shape.spurScore * 5 +
          shape.outAndBackScore * 3 +
          shape.deadEndArmScore * 4 +
          shape.centerReentryCount * 25 +
          shape.geometricUTurnCount * 8 +
          shape.cleanupUTurnCount * 10;
      return candidate.quality.score + distancePenalty + shapePenalty;
    };
    const hydrationQueue = acceptedRouteCandidates
      .slice()
      .sort((a, b) => a.quality.score - b.quality.score)
      .slice(0, avoidHighwaysRoundTripSearch ? 4 : 2);
    for (const candidate of hydrationQueue) {
      const hydratedCandidate = await hydrateGuidanceRoute(
        candidate.plan,
        candidate.context,
      );
      recordHydrationDiagnostic({
        candidate,
        hydrationAttempted: true,
        hydrationOutcome: hydratedCandidate == null ? "rejected" : "accepted",
        hydratedRoute: lastHydrationRoute,
        hydratedQuality: lastHydrationQuality,
        hydratedMeta: lastHydrationMeta,
        rejectReason: hydratedCandidate == null
          ? lastHydrationRejectReason
          : null,
      });
      if (hydratedCandidate == null) {
        postHydrationRejectReason = lastHydrationRejectReason ??
          "guidance_hydration_failed";
        continue;
      }
      hydratedSelection = {
        plan: candidate.plan,
        phaseName: candidate.phaseName,
        distanceFitTier: distanceFitTierForQuality(
          hydratedCandidate.quality,
          candidate.context.distanceConfig,
        ),
        route: hydratedCandidate.route,
        quality: hydratedCandidate.quality,
        routeRequestMeta: hydratedCandidate.routeRequestMeta,
      };
      finalGeometrySource = "hydrated";
      preHydrationQualityTier = candidate.quality.tier;
      break;
    }
    if (hydratedSelection == null) {
      const fallbackCandidate = hydrationQueue
        .slice()
        .sort((a, b) => hydrationFallbackRank(a) - hydrationFallbackRank(b))
        .find(isPreHydrationFallbackAllowed) ??
        acceptedRouteCandidates
          .slice()
          .sort((a, b) => hydrationFallbackRank(a) - hydrationFallbackRank(b))
          .find(isPreHydrationFallbackAllowed);
      if (fallbackCandidate == null) {
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
          mapboxCallCount,
          evaluatedRouteCount,
          guidanceHydrationCount,
          searchStageSuccess: null,
          selectedCandidateFamily: null,
          distanceFitTier: null,
          rejectReasons: Object.fromEntries(rejectReasons),
          searchPhases: searchPhases.map((phase) => phase.name),
          lastPlanLabels,
          variantHint: normalizedVariantHint,
          fingerprintHint: normalizedFingerprintHint,
          duplicateSkips,
          exhausted: true,
          silentViaUsed: silentViaAttempted,
          silentViaWaypoints: lastSilentViaWaypoints,
          shapingPointCount: lastSilentViaShapingPointCount,
          mapboxLegCount: lastSilentViaMapboxLegCount,
          arriveManeuverCount: lastSilentViaArriveManeuverCount,
          silentViaFallbackUsed,
          guidanceDegraded,
          hydrationFallbackUsed,
          finalGeometrySource,
          postHydrationRejectReason,
          preHydrationQualityTier,
          hydrationDiagnostics,
        };
      }
      guidanceDegraded = true;
      hydrationFallbackUsed = true;
      finalGeometrySource = "pre_hydration_fallback";
      postHydrationRejectReason = postHydrationRejectReason ??
        "guidance_hydration_failed";
      preHydrationQualityTier = fallbackCandidate.quality.tier;
      hydratedSelection = {
        plan: fallbackCandidate.plan,
        phaseName: fallbackCandidate.phaseName,
        distanceFitTier: fallbackCandidate.distanceFitTier,
        route: fallbackCandidate.route,
        quality: fallbackCandidate.quality,
        routeRequestMeta: fallbackCandidate.routeRequestMeta,
      };
      debugWarn(
        `[RT] Guidance hydration failed for accepted candidates; using pre-hydration safe fallback ${
          fallbackCandidate.plan.label
        } (${fallbackCandidate.quality.tier}, reason=${
          fallbackCandidate.quality.reason
        })`,
      );
    }
    bestPlan = hydratedSelection.plan;
    bestRoute = hydratedSelection.route;
    bestQuality = hydratedSelection.quality;
    bestPhaseName = hydratedSelection.phaseName;
    bestCandidateFamily = hydratedSelection.plan.label;
    bestDistanceFitTier = hydratedSelection.distanceFitTier;
    bestRouteRequestMeta = hydratedSelection.routeRequestMeta;
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

  const selectedFamilyLower = (bestCandidateFamily ?? bestPlan.label)
    .toLowerCase();
  const requestedStyle = bestQuality.requestedStyle ?? mode ?? null;
  let deliveredStyle = bestQuality.deliveredStyle ?? requestedStyle;
  let styleDowngraded = bestQuality.styleDowngraded === true;
  if (requestedStyle === "Abendrunde" || requestedStyle === "Entdecker") {
    const requestedToken = requestedStyle === "Abendrunde"
      ? "evening"
      : "explore";
    const familyMatchesRequested = selectedFamilyLower.includes(
      requestedToken,
    );
    const familyIsSportLike = selectedFamilyLower.includes("sport") ||
      selectedFamilyLower.includes("flow");
    const familyIsCurvyLike = selectedFamilyLower.includes("curv") ||
      selectedFamilyLower.includes("curve");
    if (!familyMatchesRequested) {
      styleDowngraded = true;
      deliveredStyle = familyIsSportLike
        ? "sport_like"
        : familyIsCurvyLike
        ? "curvy_like"
        : "generic_roundtrip";
    }
  }

  return {
    route: bestRoute,
    waypoints: bestPlan.waypoints,
    radiuses: effectivePlanRadiuses(bestPlan),
    quality: bestQuality,
    candidateAttempts,
    acceptedCandidates,
    rejectedCandidates,
    mapboxCallCount,
    evaluatedRouteCount,
    guidanceHydrationCount,
    searchStageSuccess: bestPhaseName,
    selectedCandidateFamily: bestCandidateFamily,
    distanceFitTier: bestDistanceFitTier,
    rejectReasons: Object.fromEntries(rejectReasons),
    searchPhases: searchPhases.map((phase) => phase.name),
    lastPlanLabels,
    variantHint: normalizedVariantHint,
    fingerprintHint: normalizedFingerprintHint,
    duplicateSkips,
    emergencyDuplicateUsed: false,
    safeFallbackUsed: bestQuality.safeFallbackUsed === true,
    safeFallbackReason: bestQuality.safeFallbackReason ?? null,
    requestedStyle,
    deliveredStyle,
    styleDowngraded,
    silentViaUsed: bestRouteRequestMeta?.silentViaUsed ?? silentViaAttempted,
    silentViaWaypoints: bestRouteRequestMeta?.silentViaWaypoints ??
      lastSilentViaWaypoints,
    shapingPointCount: bestRouteRequestMeta?.shapingPointCount ??
      Math.max(0, bestPlan.waypoints.length - 2),
    mapboxLegCount: bestRouteRequestMeta?.mapboxLegCount ??
      countRouteLegs(bestRoute),
    arriveManeuverCount: bestRouteRequestMeta?.arriveManeuverCount ??
      countArriveManeuvers(bestRoute),
    silentViaFallbackUsed:
      (bestRouteRequestMeta?.silentViaFallbackUsed === true) ||
      silentViaFallbackUsed,
    guidanceDegraded,
    hydrationFallbackUsed,
    finalGeometrySource,
    postHydrationRejectReason,
    preHydrationQualityTier,
    hydrationDiagnostics,
    terminalShortCircuit: balancedTerminalShortCircuit,
    rejectSamples,
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
