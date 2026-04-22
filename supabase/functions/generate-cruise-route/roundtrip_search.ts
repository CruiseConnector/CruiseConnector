import type {
  Coordinate,
  DistanceConfig,
  RoundTripCandidatePlan,
  RoundTripSearchResult,
  RouteMode,
  RouteQualityEvaluation,
} from "./routing_types.ts";
import {
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
import { evaluateRouteQuality } from "./route_quality.ts";

export function prioritizeCandidatePlans(
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
  const preferWideSportAvoidHighways = options?.avoidHighways === true &&
    (normalizedMode === "sport mode" || normalizedMode === "sport") &&
    (options?.targetDistanceKm ?? Number.POSITIVE_INFINITY) <= 80;
  const preferStableShortSportAvoidHighways = preferWideSportAvoidHighways &&
    (options?.targetDistanceKm ?? Number.POSITIVE_INFINITY) <= 60;
  const styleOrderTokens = normalizedMode === "kurvenjagd"
    ? [
      "curve-zigzag-core",
      "curve-loop-scout",
      "curve-orbital-core",
      "curve-loop-tight",
      "curve-loop-wide",
      "curve-triangle",
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
      "sport-cardinal-ellipse",
      "sport-loop-flow",
      "sport-orbital-flow",
      "sport-loop-wide",
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
      "explore-loop-scout",
      "explore-orbital-wide",
      "explore-loop-wide",
      "explore-loop-far",
    ]
    : [];
  const styleRank = (label: string): number => {
    const lower = label.toLowerCase();
    const index = styleOrderTokens.findIndex((token) => lower.includes(token));
    return index >= 0 ? index : styleOrderTokens.length;
  };
  if (styleOrderTokens.length > 0) {
    remaining.sort((a, b) => styleRank(a.label) - styleRank(b.label));
  }

  if (preferWideSportAvoidHighways && remaining.length > 1) {
    const prioritized = remaining.filter((plan) =>
      styleRank(plan.label) < styleOrderTokens.length
    );
    const deferred = remaining.filter((plan) => !prioritized.includes(plan));
    if (prioritized.length > 1) {
      const normalizedFingerprint = normalizeHint(fingerprintHint);
      const rotationSeed = normalizedFingerprint
        ? stableStringHash(`${phaseName}:${normalizedFingerprint}`)
        : 0;
      const rotationLimit = preferStableShortSportAvoidHighways
        ? 1
        : Math.max(1, Math.min(4, prioritized.length));
      const startIndex = rotationSeed % rotationLimit;
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

export function widenDistanceConfigForRoundTripSearch(
  base: DistanceConfig,
  targetDistanceKm: number,
  phase: "balanced" | "fallback",
): DistanceConfig {
  const minFactor = phase === "fallback" ? 0.80 : 0.84;
  const maxFactor = phase === "fallback" ? 1.22 : 1.16;
  const radiusMultiplier = phase === "fallback" ? 1.12 : 1.06;
  const snapMultiplier = phase === "fallback" ? 1.16 : 1.10;

  return {
    radiusKm: base.radiusKm * radiusMultiplier,
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

export function normalizeRoundTripRejectReason(reason: string): string {
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
  radiusMultiplier,
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
}: {
  startLocation: Coordinate;
  targetDistanceKm: number;
  distanceConfig: DistanceConfig;
  mode?: RouteMode;
  randomSeed: number;
  directionHintDegrees?: number;
  waypointShapeFactor?: number;
  radiusMultiplier?: number;
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
}): Promise<RoundTripSearchResult | null> {
  const highCostCurveSearch = mode === "Kurvenjagd" && targetDistanceKm >= 130;
  const extendedRoundTripSearch = targetDistanceKm >= 100 ||
    mode === "Entdecker";
  const shortCurvySearch = mode === "Kurvenjagd" && targetDistanceKm <= 60;
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
  // Budget so kalibriert, dass alle 3 Phasen (strict / balanced / fallback)
  // garantiert MEHRERE Pläne bekommen. Floor 7 schützt schwierige Geometrien
  // (Bergtäler, Inseln) — wir hatten nach Floor 4 noch 3/3 Failures in
  // Dornbirn, weil fairShareCeiling den Fallback auf 1 Plan reduzierte.
  // Constrained Suchen (Autobahn vermeiden) bekommen +1, weil sie pro
  // Versuch ggf. einen relax-retry brauchen (siehe `relaxedFetch` unten).
  const globalAttemptBudget = Math.max(
    avoidHighwaysTightRoundTripSearch ? 8 : 7,
    Math.min(
      avoidHighwaysTightRoundTripSearch
        ? 10
        : highCostCurveSearch
        ? 7
        : extendedRoundTripSearch
        ? 8
        : (constrainedRoundTripSearch || shortCurvySearch)
        ? 9
        : 8,
      Math.round(
        maxCandidateAttemptsHint ??
          (avoidHighwaysTightRoundTripSearch
            ? 10
            : highCostCurveSearch
            ? 6
            : extendedRoundTripSearch
            ? 7
            : (constrainedRoundTripSearch || shortCurvySearch)
            ? 8
            : 7),
      ),
    ),
  );
  const searchStartTs = Date.now();
  // Time Budget: jeder Mapbox-Call kostet ~1.5–3 s; mit 7–9 Plänen + relax
  // brauchen wir ≥18 s, sonst killt das Time-Budget den Fallback bevor er
  // läuft. Client-_invoke-Timeout muss DARÜBER liegen (siehe route_service).
  const roundTripTimeBudgetMs = highCostCurveSearch
    ? 16000
    : avoidHighwaysTightRoundTripSearch
    ? 24000
    : (constrainedRoundTripSearch || shortCurvySearch)
    ? 22000
    : 19000;

  const tuneDistanceConfigForAvoidHighways = (
    config: DistanceConfig,
  ): DistanceConfig => {
    if (!avoidHighwaysTightRoundTripSearch) {
      return config;
    }
    const shortNoHighwaySportRoundTrip = avoidHighways &&
      mode === "Sport Mode" &&
      targetDistanceKm <= 60;
    const snapCap = shortNoHighwaySportRoundTrip
      ? 4400
      : mode === "Kurvenjagd"
      ? 7600
      : 6800;
    const snapBoost = shortNoHighwaySportRoundTrip
      ? 1.08
      : targetDistanceKm <= 60
      ? 1.55
      : 1.40;
    const radiusTightening = shortNoHighwaySportRoundTrip
      ? 0.80
      : targetDistanceKm <= 60
      ? 0.92
      : 0.95;
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
  let balancedHasPresentableCandidate = false;
  let balancedTerminalShortCircuit = false;
  const rejectReasons = new Map<string, number>();
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
        console.warn(
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
        console.warn(
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

  for (const phase of searchPhases) {
    if (stopSearchWithBestCandidate) break;
    const orderedCandidates = prioritizeCandidatePlans(
      buildRoundTripWaypointCandidates({
        start: startLocation,
        distanceConfig: phase.distanceConfig,
        targetDistanceKm,
        mode,
        randomSeed: randomSeed + phase.seedOffset,
        preferredBearingDegrees: directionHintDegrees,
        waypointShapeFactor,
        radiusMultiplier,
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
    );
    // Pro Phase 2-3 Versuche. WICHTIG: Fair-Share-Guard reserviert für
    // jede spätere Phase MINDESTENS 2 Versuche (vorher: 1), damit der
    // Fallback in Bergtälern wirklich Plan A+B testen kann. Strict darf
    // 3 ausschöpfen, falls die Geometrie es zulässt; balanced/fallback
    // bekommen je 2-3.
    const declaredMaxPerPhase = phase.name === "strict"
      ? avoidHighwaysTightRoundTripSearch ? 3 : 2
      : phase.name === "balanced"
      ? avoidHighwaysTightRoundTripSearch ? 3 : 2
      : avoidHighwaysTightRoundTripSearch
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
    const candidatePlans = orderedCandidates.slice(
      0,
      Math.min(orderedCandidates.length, maxPhaseAttempts),
    );
    let phaseAttempts = 0;
    let phaseAcceptedCandidates = 0;

    console.log(
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
        Date.now() - searchStartTs >= roundTripTimeBudgetMs
      ) {
        console.log(
          `[RT] Phase ${phase.name}: stopping early after ${phaseAttempts} attempts (global=${candidateAttempts})`,
        );
        break;
      }

      phaseAttempts += 1;
      candidateAttempts += 1;
      console.log(
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
          maxAttempts: 2,
          timeoutMs: 12000,
          retryDelayBaseMs: 220,
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
        relaxedPhaseExclude !== phase.exclude
      ) {
        console.log(
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
            maxAttempts: 1,
            timeoutMs: 10500,
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
        console.log(
          `[RT] ${phase.name}/${plan.label}: ${reason}${
            fetchResult.details ? ` (${fetchResult.details.slice(0, 160)})` : ""
          }`,
        );
        continue;
      }

      let route = fetchResult.route;
      let quality = evaluateRouteQuality(route, "ROUND_TRIP", {
        targetDistanceKm,
        distanceConfig: phase.distanceConfig,
        mode,
        avoidHighways,
      });

      if (
        quality.tier === "rejected" &&
        relaxedPhaseExclude !== phase.exclude &&
        quality.reason.startsWith("overlap=") &&
        rateLimitHits === 0 &&
        timeoutHits < 2
      ) {
        console.log(
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
            maxAttempts: 1,
            timeoutMs: 10500,
          },
        );
        const relaxedFailureKind = getRetryKindFromMapboxFailure(relaxedFetch);
        if (relaxedFailureKind === "rate_limit") rateLimitHits += 1;
        if (relaxedFailureKind === "timeout") timeoutHits += 1;
        if (shouldAbortForProviderPressure()) break;
        if (relaxedFetch.route) {
          const relaxedQuality = evaluateRouteQuality(
            relaxedFetch.route,
            "ROUND_TRIP",
            {
              targetDistanceKm,
              distanceConfig: phase.distanceConfig,
              mode,
              avoidHighways,
            },
          );
          console.log(
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
            route = relaxedFetch.route;
            quality = relaxedQuality;
          }
        }
      }

      if (stopSearchWithBestCandidate) {
        break;
      }

      console.log(
        `[RT] ${phase.name}/${plan.label}: tier=${quality.tier}, score=${
          quality.score.toFixed(1)
        }, ` +
          `distance=${quality.actualDistanceKm.toFixed(1)}km, overlap=${
            quality.overlapPercent.toFixed(1)
          }%, coords=${quality.coordinateCount}`,
      );

      if (quality.tier === "rejected") {
        rejectedCandidates += 1;
        registerReject(quality.reason);
        continue;
      }

      acceptedCandidates += 1;
      phaseAcceptedCandidates += 1;
      if (!bestQuality || quality.score < bestQuality.score) {
        bestPlan = plan;
        bestRoute = route;
        bestQuality = quality;
      }
      if (
        phase.name === "balanced" &&
        isBalancedPresentableCandidate(quality)
      ) {
        balancedHasPresentableCandidate = true;
      }

      const shouldStopAfterGoodCandidate = quality.tier === "ideal" ||
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
          quality.distanceDeltaKm <= targetDistanceKm * 0.18
        );
      const shouldStopAfterAcceptableCandidate =
        quality.tier === "acceptable" &&
        !avoidHighwaysTightRoundTripSearch &&
        (
          phase.name === "fallback" ||
          phaseAcceptedCandidates >= 2 ||
          candidateAttempts >= (constrainedRoundTripSearch ? 3 : 2)
        );

      if (shouldStopAfterGoodCandidate || shouldStopAfterAcceptableCandidate) {
        console.log(
          `[RT] Phase ${phase.name}: usable candidate found, stopping early after ${phaseAttempts} attempts`,
        );
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
    if (bestQuality?.tier === "ideal") {
      break;
    }
    if (
      phaseAcceptedCandidates > 0 &&
      bestQuality?.tier === "good" &&
      !avoidHighwaysTightRoundTripSearch
    ) {
      break;
    }
    if (
      phase.name === "balanced" &&
      balancedHasPresentableCandidate &&
      !avoidHighwaysTightRoundTripSearch
    ) {
      console.log(
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
      (
        phase.name === "fallback" ||
        candidateAttempts >= (constrainedRoundTripSearch ? 3 : 2)
      )
    ) {
      break;
    }
  }

  if (!bestPlan || !bestRoute || !bestQuality) {
    console.log(
      `[RT] Search exhausted: ${candidateAttempts} candidates, none usable. Reject summary=${
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
      variantHint: normalizedVariantHint,
      fingerprintHint: normalizedFingerprintHint,
      exhausted: true,
    };
  }

  console.log(
    `[RT] Selected ${bestPlan.label}: tier=${bestQuality.tier}, score=${
      bestQuality.score.toFixed(1)
    }, ` +
      `attempts=${candidateAttempts}, accepted=${acceptedCandidates}, rejected=${rejectedCandidates}, rejects=${
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
    variantHint: normalizedVariantHint,
    fingerprintHint: normalizedFingerprintHint,
    terminalShortCircuit: balancedTerminalShortCircuit,
  };
}
