// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import type {
  Coordinate,
  DistanceConfig,
  RequestData,
  RoundTripSearchResult,
} from "./routing_types.ts";
import {
  applyAvoidHighwaysExcludes,
  calculateBearing,
  calculateDestination,
  calculateDistance,
  interpolateCoordinate,
  normalizeBearingDegrees,
  normalizeExcludeParams,
  normalizeHint,
  relaxStreetExcludes,
  scaleWaypoint,
  seededUnit,
  stableStringHash,
} from "./routing_utils.ts";
import { getDistanceConfig } from "./roundtrip_waypoints.ts";
import { getMapboxRoute } from "./mapbox_client.ts";
import {
  buildPointToPointScenicWaypoints,
  getPointToPointMaximumDistanceKm,
  getPointToPointMinimumDistanceKm,
  getRouteDistanceKm,
  isPointToPointDetourAcceptable,
} from "./point_to_point.ts";
import { evaluateRouteQuality } from "./route_quality.ts";
import { searchBestRoundTripRoute } from "./roundtrip_search.ts";
import { classifyRoutingError } from "./routing_request_utils.ts";

// Environment variables
const MAPBOX_ACCESS_TOKEN = Deno.env.get("MAPBOX_ACCESS_TOKEN");

// Erlaubte Origins — eigene App, Supabase-Domain und GitHub Pages
const ALLOWED_ORIGINS = [
  "https://tlcfaxvvqzobmzwvfnvb.supabase.co",
  "https://cruiseconnector.github.io",
];

function getCorsHeaders(req?: Request) {
  const origin = req?.headers.get("origin") ?? "";
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin)
    ? origin
    : ALLOWED_ORIGINS[0];
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
  };
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: getCorsHeaders(req) });
  }

  let requestDebugMeta: Record<string, unknown> | null = null;

  try {
    // 1. Parse Request
    const body = await req.json() as RequestData;
    const debugBody = body as RequestData & {
      request_id?: string;
      client_scenario_key?: string;
      client_force_fresh_variant?: boolean;
      client_trigger?: string;
    };
    const {
      planning_type,
      startLocation,
      targetDistance,
      manual_waypoints,
      mode,
    } = body;
    const directionHint = typeof body.direction_hint === "number" &&
        Number.isFinite(body.direction_hint)
      ? normalizeBearingDegrees(Math.round(body.direction_hint))
      : undefined;
    const offsetSide = body.offset_side === -1 || body.offset_side === 1
      ? body.offset_side
      : undefined;
    const waypointShapeFactor =
      typeof body.waypoint_shape_factor === "number" &&
        Number.isFinite(body.waypoint_shape_factor)
        ? body.waypoint_shape_factor
        : undefined;
    const radiusMultiplier = typeof body.radius_multiplier === "number" &&
        Number.isFinite(body.radius_multiplier)
      ? body.radius_multiplier
      : undefined;
    const zigzagWaypoints = body.zigzag_waypoints === true;
    const variantHint = normalizeHint(
      body.route_variant_hint ?? body.variant_hint ?? body.style_profile,
    );
    const fingerprintHint = normalizeHint(
      body.route_fingerprint_hint ?? body.fingerprint_hint,
    );
    const maxCandidateAttemptsHint =
      typeof body.max_candidate_attempts === "number" &&
        Number.isFinite(body.max_candidate_attempts)
        ? body.max_candidate_attempts
        : undefined;
    const hintSeedOffset =
      stableStringHash(`${variantHint ?? ""}|${fingerprintHint ?? ""}`) % 9973;
    console.log(
      "[RoutingRequest]",
      JSON.stringify({
        requestId: debugBody.request_id ?? null,
        clientScenarioKey: debugBody.client_scenario_key ?? null,
        clientForceFreshVariant: debugBody.client_force_fresh_variant === true,
        clientTrigger: debugBody.client_trigger ?? null,
        planningType: planning_type,
        routeType: body.route_type ?? "ROUND_TRIP",
        mode: mode ?? "Standard",
        hasDestination: body.destination_location != null,
        manualWaypointCount: manual_waypoints?.length ?? 0,
        targetDistance: targetDistance ?? null,
        detourLevel: body.detour_level ?? 0,
        directionHint: directionHint ?? null,
        offsetSide: offsetSide ?? null,
        styleProfile: body.style_profile ?? null,
        waypointShapeFactor: waypointShapeFactor ?? null,
        radiusMultiplier: radiusMultiplier ?? null,
        zigzagWaypoints,
        avoidHighways: body.avoid_highways === true,
        variantHint: variantHint ?? null,
        fingerprintHint: fingerprintHint ?? null,
        maxCandidateAttemptsHint: maxCandidateAttemptsHint ?? null,
      }),
    );

    if (!MAPBOX_ACCESS_TOKEN) {
      throw new Error("Server Error: MAPBOX_ACCESS_TOKEN is not configured.");
    }

    // Basic validation
    if (!startLocation) {
      throw new Error("Missing startLocation");
    }

    // Coordinate validation helper
    const isValidCoord = (c: Coordinate): boolean =>
      c != null &&
      typeof c.latitude === "number" && typeof c.longitude === "number" &&
      !isNaN(c.latitude) && !isNaN(c.longitude) &&
      c.latitude >= -90 && c.latitude <= 90 &&
      c.longitude >= -180 && c.longitude <= 180;

    if (!isValidCoord(startLocation)) {
      throw new Error(
        "Invalid startLocation: coordinates out of bounds or not a number",
      );
    }
    if (body.destination_location && !isValidCoord(body.destination_location)) {
      throw new Error(
        "Invalid destination_location: coordinates out of bounds or not a number",
      );
    }
    if (manual_waypoints) {
      for (let i = 0; i < manual_waypoints.length; i++) {
        if (!isValidCoord(manual_waypoints[i])) {
          throw new Error(
            `Invalid waypoint at index ${i}: coordinates out of bounds or not a number`,
          );
        }
      }
    }
    if (
      targetDistance != null &&
      (typeof targetDistance !== "number" || isNaN(targetDistance) ||
        targetDistance <= 0 || targetDistance > 500)
    ) {
      throw new Error(
        "Invalid targetDistance: must be a number between 1 and 500",
      );
    }
    if (
      body.direction_hint != null &&
      (typeof body.direction_hint !== "number" ||
        !Number.isFinite(body.direction_hint))
    ) {
      throw new Error("Invalid direction_hint: must be a finite number");
    }
    if (
      body.offset_side != null && body.offset_side !== -1 &&
      body.offset_side !== 1
    ) {
      throw new Error("Invalid offset_side: must be -1 or 1");
    }
    if (
      body.waypoint_shape_factor != null &&
      (typeof body.waypoint_shape_factor !== "number" ||
        !Number.isFinite(body.waypoint_shape_factor))
    ) {
      throw new Error("Invalid waypoint_shape_factor: must be a finite number");
    }
    if (
      body.radius_multiplier != null &&
      (typeof body.radius_multiplier !== "number" ||
        !Number.isFinite(body.radius_multiplier))
    ) {
      throw new Error("Invalid radius_multiplier: must be a finite number");
    }
    if (
      body.max_candidate_attempts != null &&
      (typeof body.max_candidate_attempts !== "number" ||
        !Number.isFinite(body.max_candidate_attempts))
    ) {
      throw new Error(
        "Invalid max_candidate_attempts: must be a finite number",
      );
    }

    const avoidHighways = body.avoid_highways === true;
    const requestContinueStraight = body.continue_straight !== false;
    const randomSeed = (body.randomSeed ?? Math.floor(Math.random() * 100000)) +
      hintSeedOffset;
    const requestStartedAt = Date.now();

    // --- 2. Fahrstil-Parameter (Mapbox) ---
    // Jeder Stil nutzt unterschiedliche Mapbox-Profile und Exclude-Parameter.
    // Da Mapbox kein "prefer" unterstützt, erzwingen wir Straßentypen durch
    // Excludes + stilspezifische Waypoint-Platzierung (siehe Subtask 2).
    let mapboxProfile = "mapbox/driving";
    let excludeParams = "";
    let radiusesParams = "";

    if (mode === "Kurvenjagd") {
      // Der Autobahn-Toggle ist die Quelle der Wahrheit. Kurvenjagd schließt
      // ohne Toggle keine Autobahnen hart aus, hält aber Maut/Fähren raus.
      mapboxProfile = "mapbox/driving";
      excludeParams = "toll,ferry";
    } else if (mode === "Sport Mode") {
      // Sport Mode = flüssig & schnell. Unpaved raus, damit Mapbox keine
      // Forst-/Bergstraßen oder Schotter in die Strecke schmuggelt. Autobahn
      // steuert ausschließlich der Toggle.
      mapboxProfile = "mapbox/driving";
      excludeParams = "ferry,unpaved";
    } else if (mode === "Abendrunde") {
      // Abendrunde vermeidet Fähren/Unpaved, Autobahnen nur auf Toggle.
      mapboxProfile = "mapbox/driving-traffic";
      excludeParams = "ferry,unpaved";
    } else if (mode === "Entdecker") {
      // Entdecker hält nur Maut fern, Autobahnen nur auf Toggle.
      mapboxProfile = "mapbox/driving";
      excludeParams = "toll";
    } else {
      // Standard: minimal eingeschränkt
      mapboxProfile = "mapbox/driving";
      excludeParams = "ferry";
    }

    // --- 3. Flexible Planung ---
    let finalWaypoints: Coordinate[] = [];
    let distanceConfig: DistanceConfig | null = null;
    let effectiveTargetDistanceKm: number | null = null;
    let pointToPointIsScenic = false;
    let pointToPointDirectDistanceKm = 0;
    // Default to ROUND_TRIP if not specified, for backward compatibility or default 'Zufall' behavior
    const currentRouteType = body.route_type || "ROUND_TRIP";
    const detourLevel = Math.max(0, Math.min(3, body.detour_level ?? 0));

    if (planning_type === "Zufall" && currentRouteType === "ROUND_TRIP") {
      if (mode === "Kurvenjagd") {
        excludeParams = "ferry";
      } else if (mode === "Sport Mode") {
        // Sport-Rundkurs: Unpaved bleibt draußen, sonst landen wir gerne
        // auf Wald-/Bergwegen (Dornbirn-Bergpässe).
        excludeParams = "ferry,unpaved";
      } else if (mode === "Abendrunde") {
        mapboxProfile = "mapbox/driving";
        excludeParams = "ferry";
      } else if (mode === "Entdecker") {
        excludeParams = "";
      }
      excludeParams = applyAvoidHighwaysExcludes(
        excludeParams,
        avoidHighways,
      );
    }

    if (planning_type === "Zufall") {
      if (currentRouteType === "POINT_TO_POINT") {
        // A→B: direkte Straßenroute, optional ohne Autobahnen.
        // Stil-Excludes wie beim Rundkurs, damit Kurvenjagd/Sport/Entdecker
        // technisch spürbar auseinanderlaufen (nicht nur Waypoint-Form).
        mapboxProfile = mode === "Abendrunde"
          ? "mapbox/driving-traffic"
          : "mapbox/driving";
        const stylePointToPointBase = mode === "Sport Mode"
          ? "ferry,unpaved"
          : mode === "Kurvenjagd"
          ? "ferry"
          : mode === "Entdecker"
          ? "toll"
          : mode === "Abendrunde"
          ? "ferry,unpaved"
          : "ferry";
        excludeParams = applyAvoidHighwaysExcludes(
          stylePointToPointBase,
          avoidHighways,
        );
        if (!body.destination_location) {
          throw new Error(
            "For 'POINT_TO_POINT' planning, a destination_location is required.",
          );
        }
        pointToPointDirectDistanceKm = calculateDistance(
          startLocation,
          body.destination_location,
        );
        pointToPointIsScenic = detourLevel > 0 ||
          (mode != null && mode !== "Standard") ||
          (targetDistance != null &&
            targetDistance > pointToPointDirectDistanceKm * 1.05);

        finalWaypoints = pointToPointIsScenic
          ? buildPointToPointScenicWaypoints({
            start: startLocation,
            destination: body.destination_location,
            mode,
            targetDistance,
            detourLevel,
            detourFactor: body.detour_factor,
            offsetSide,
            waypointShapeFactor,
            zigzagWaypoints,
            randomSeed: body.randomSeed ?? 0,
            simplifyWaypoints: body.simplify_waypoints === true,
            maxWaypoints: body.max_waypoints,
          })
          : [startLocation, body.destination_location];
        const scenicRadiusMeters = detourLevel >= 3
          ? Math.min(
            15000,
            Math.max(6500, Math.round(pointToPointDirectDistanceKm * 320)),
          )
          : detourLevel === 2
          ? Math.min(
            12000,
            Math.max(5400, Math.round(pointToPointDirectDistanceKm * 260)),
          )
          : detourLevel === 1
          ? Math.min(
            9000,
            Math.max(4200, Math.round(pointToPointDirectDistanceKm * 220)),
          )
          : 6000;
        const scenicRadius = `${scenicRadiusMeters}`;
        radiusesParams = finalWaypoints
          .map((_, i) =>
            (i === 0 || i === finalWaypoints.length - 1)
              ? "unlimited"
              : scenicRadius
          )
          .join(";");
      } else {
        // ROUND_TRIP logic
        if (!targetDistance) {
          throw new Error(
            "For 'Zufall' planning, a targetDistance is required.",
          );
        }

        // >100 km is capped to 150 km maximum route target
        const effectiveDistance = Math.min(targetDistance, 150);
        distanceConfig = getDistanceConfig(effectiveDistance, mode);
        effectiveTargetDistanceKm = effectiveDistance;
      }
    } else if (planning_type === "Wegpunkte") {
      if (!manual_waypoints || manual_waypoints.length < 3) {
        throw new Error(
          "For 'Wegpunkte', provide at least 3 points (including start/end implies a loop or A->B->C).",
        );
      }
      finalWaypoints = manual_waypoints;
    } else {
      throw new Error(
        "Invalid planning_type. Must be 'Zufall' or 'Wegpunkte'.",
      );
    }

    requestDebugMeta = {
      request_id: debugBody.request_id ?? null,
      client_scenario_key: debugBody.client_scenario_key ?? null,
      client_force_fresh_variant: debugBody.client_force_fresh_variant === true,
      client_trigger: debugBody.client_trigger ?? null,
      route_type: currentRouteType,
      mode: mode ?? "Standard",
      planning_type,
      targetDistance: targetDistance ?? null,
      requested_target_distance_km: currentRouteType === "ROUND_TRIP"
        ? targetDistance ?? null
        : null,
      effective_target_distance_km: currentRouteType === "ROUND_TRIP"
        ? effectiveTargetDistanceKm ?? targetDistance ?? null
        : null,
      avoid_highways_requested: avoidHighways,
      effective_excludes: excludeParams || "none",
      variant_hint: variantHint ?? null,
      fingerprint_hint: fingerprintHint ?? null,
      max_candidate_attempts: maxCandidateAttemptsHint ?? null,
    };

    console.log(
      "[RoutingResolvedConfig]",
      JSON.stringify({
        requestId: debugBody.request_id ?? null,
        clientScenarioKey: debugBody.client_scenario_key ?? null,
        clientTrigger: debugBody.client_trigger ?? null,
        routeType: currentRouteType,
        mode: mode ?? "Standard",
        planningType: planning_type,
        styleProfile: body.style_profile ?? null,
        avoidHighwaysRequested: avoidHighways,
        mapboxProfile,
        effectiveExcludes: excludeParams || "none",
        simplifyWaypoints: body.simplify_waypoints === true,
        maxWaypoints: body.max_waypoints ?? null,
        targetDistance: targetDistance ?? null,
        effectiveTargetDistanceKm,
      }),
    );

    // Radiuses: Start/Ende unlimited (echte GPS-Position), Zwischenpunkte max 1000m
    // Kleiner Radius = Waypoints müssen nahe einer Straße liegen → verhindert "Abkürzungen"
    // durch Gelände wo keine Straße existiert
    if (!radiusesParams && finalWaypoints.length > 0) {
      radiusesParams = finalWaypoints
        .map((_, i) =>
          (i === 0 || i === finalWaypoints.length - 1) ? "unlimited" : "1000"
        )
        .join(";");
    }

    // --- Execute Route Request (with retries) ---
    let route = null;
    let roundTripSearch: RoundTripSearchResult | null = null;
    const useRoundTripSearch = planning_type === "Zufall" &&
      currentRouteType === "ROUND_TRIP" &&
      distanceConfig != null &&
      targetDistance != null;
    const pointToPointTimeBudgetMs = currentRouteType === "POINT_TO_POINT"
      ? pointToPointIsScenic
        ? (avoidHighways || detourLevel >= 2 ? 15000 : 13000)
        : 10000
      : 0;
    const pointToPointTimeRemainingMs = () =>
      pointToPointTimeBudgetMs <= 0
        ? Number.POSITIVE_INFINITY
        : pointToPointTimeBudgetMs - (Date.now() - requestStartedAt);
    const hasPointToPointBudgetLeft = (reserveMs = 0) =>
      pointToPointTimeBudgetMs <= 0 ||
      pointToPointTimeRemainingMs() > reserveMs;
    const pointToPointTimeoutMs = (
      preferredMs: number,
      minimumMs = 2500,
    ) =>
      pointToPointTimeBudgetMs <= 0 ? preferredMs : Math.max(
        minimumMs,
        Math.min(preferredMs, pointToPointTimeRemainingMs() - 350),
      );

    if (useRoundTripSearch) {
      roundTripSearch = await searchBestRoundTripRoute({
        startLocation,
        targetDistanceKm: effectiveTargetDistanceKm ?? targetDistance!,
        distanceConfig: distanceConfig!,
        mode,
        randomSeed,
        directionHintDegrees: directionHint,
        waypointShapeFactor,
        radiusMultiplier,
        zigzagWaypoints,
        mapboxProfile,
        excludeParams,
        accessToken: MAPBOX_ACCESS_TOKEN,
        variantHint,
        fingerprintHint,
        maxCandidateAttemptsHint,
        simplifyWaypoints: body.simplify_waypoints === true,
        maxWaypoints: body.max_waypoints,
        continueStraight: requestContinueStraight,
        avoidHighways,
      });
      if (roundTripSearch?.route) {
        route = roundTripSearch.route;
        finalWaypoints = roundTripSearch.waypoints;
        radiusesParams = roundTripSearch.radiuses;
        console.log(
          `[RT] Search summary: attempts=${roundTripSearch.candidateAttempts}, accepted=${roundTripSearch.acceptedCandidates}, rejected=${roundTripSearch.rejectedCandidates}, chosen=${roundTripSearch.quality?.tier}`,
        );
        if (roundTripSearch.terminalShortCircuit === true) {
          console.log(
            "[RT] Balanced short-circuit selected terminal seed result; skipping post-search scaling/rescue.",
          );
        }
      }
    } else {
      route = await getMapboxRoute(
        finalWaypoints,
        mapboxProfile,
        excludeParams,
        radiusesParams,
        MAPBOX_ACCESS_TOKEN,
        {
          continueStraight: requestContinueStraight,
          maxAttempts: pointToPointIsScenic ? 2 : 2,
          timeoutMs: pointToPointTimeoutMs(
            pointToPointIsScenic ? 11500 : 9500,
          ),
          retryDelayBaseMs: 220,
        },
      );

      const relaxedPointToPointExcludes = relaxStreetExcludes(
        excludeParams,
        avoidHighways,
      );
      if (!route && relaxedPointToPointExcludes !== excludeParams) {
        console.log(
          `No route with excludes "${excludeParams}", retrying with relaxed excludes "${
            relaxedPointToPointExcludes || "none"
          }"...`,
        );
        route = await getMapboxRoute(
          finalWaypoints,
          mapboxProfile,
          relaxedPointToPointExcludes,
          radiusesParams,
          MAPBOX_ACCESS_TOKEN,
          {
            continueStraight: requestContinueStraight,
            maxAttempts: 1,
            timeoutMs: pointToPointTimeoutMs(8500),
          },
        );
      }

      if (route) {
        const initialQuality = evaluateRouteQuality(route, currentRouteType);
        if (!initialQuality.passed) {
          console.log(`Initial route rejected: ${initialQuality.reason}`);
          route = null;
        }
      }

      if (
        route &&
        planning_type === "Zufall" &&
        currentRouteType === "POINT_TO_POINT" &&
        body.destination_location &&
        pointToPointIsScenic &&
        !isPointToPointDetourAcceptable(
          route,
          pointToPointDirectDistanceKm,
          targetDistance,
          detourLevel,
          body.simplify_waypoints === true,
        )
      ) {
        const routeDistanceKm = getRouteDistanceKm(route);
        const minimumDistanceKm = getPointToPointMinimumDistanceKm(
          pointToPointDirectDistanceKm,
          targetDistance,
          detourLevel,
          body.simplify_waypoints === true,
        );
        const maximumDistanceKm = getPointToPointMaximumDistanceKm(
          pointToPointDirectDistanceKm,
          targetDistance,
          detourLevel,
          body.simplify_waypoints === true,
        );
        console.log(
          `Initial P2P scenic route rejected: ${
            routeDistanceKm.toFixed(1)
          }km outside ${minimumDistanceKm.toFixed(1)}-${
            maximumDistanceKm.toFixed(1)
          }km`,
        );
        route = null;
      }
    }

    if (
      !route && planning_type === "Zufall" &&
      currentRouteType === "POINT_TO_POINT" && body.destination_location &&
      pointToPointIsScenic
    ) {
      const scenicRetryCount = body.simplify_waypoints === true ? 3 : 2;
      const robustNoRouteFallback = avoidHighways && detourLevel >= 2 &&
        body.simplify_waypoints !== true;
      for (
        let retry = 0;
        retry < scenicRetryCount &&
        !route &&
        hasPointToPointBudgetLeft(2200);
        retry++
      ) {
        console.log(`P2P scenic retry ${retry + 1}: regenerating waypoints...`);
        const retryDetourLevel = Math.max(detourLevel, 1);
        const retrySimplifyWaypoints = body.simplify_waypoints === true ||
          retry > 0 ||
          robustNoRouteFallback;
        const retryMaxWaypoints = retrySimplifyWaypoints
          ? robustNoRouteFallback
            ? Math.min(
              body.max_waypoints ?? (retryDetourLevel >= 3 ? 2 : 1),
              retryDetourLevel >= 3 ? 2 : 1,
            )
            : Math.max(
              retryDetourLevel >= 2 ? 2 : 1,
              Math.min(
                3,
                retry >= 2
                  ? (retryDetourLevel >= 2 ? 2 : 1)
                  : body.max_waypoints ?? (retryDetourLevel >= 3 ? 2 : 1),
              ),
            )
          : undefined;
        const retryOffsetSide = offsetSide == null
          ? undefined
          : retry % 2 === 0
          ? offsetSide
          : -offsetSide;
        const emergencyScenicTarget = Math.max(
          retryDetourLevel >= 3
            ? pointToPointDirectDistanceKm *
              (robustNoRouteFallback ? 1.52 : 1.72)
            : retryDetourLevel === 2
            ? pointToPointDirectDistanceKm *
              (robustNoRouteFallback ? 1.26 : 1.40)
            : pointToPointDirectDistanceKm * 1.18,
          retryDetourLevel >= 3
            ? pointToPointDirectDistanceKm +
              (robustNoRouteFallback ? 11.0 : 16.0)
            : retryDetourLevel === 2
            ? pointToPointDirectDistanceKm + (robustNoRouteFallback ? 5.5 : 8.0)
            : pointToPointDirectDistanceKm + 4.0,
        );
        const retryMinimumTarget = Math.max(
          emergencyScenicTarget,
          getPointToPointMinimumDistanceKm(
            pointToPointDirectDistanceKm,
            targetDistance,
            retryDetourLevel,
            true,
          ),
        );
        const softenedTarget = targetDistance != null
          ? retry >= 2 ? retryMinimumTarget : Math.max(
            retryMinimumTarget,
            targetDistance *
              (retrySimplifyWaypoints ? 0.92 : 0.97),
          )
          : retryMinimumTarget;
        const retryWaypoints = buildPointToPointScenicWaypoints({
          start: startLocation,
          destination: body.destination_location,
          mode,
          targetDistance: softenedTarget,
          detourLevel: retryDetourLevel,
          detourFactor: body.detour_factor,
          offsetSide: retryOffsetSide,
          waypointShapeFactor,
          zigzagWaypoints,
          randomSeed: (body.randomSeed ?? 0) + retry + 1,
          simplifyWaypoints: retrySimplifyWaypoints,
          maxWaypoints: retryMaxWaypoints,
          robustFallback: robustNoRouteFallback,
        });
        const retryRadiusMeters = retryDetourLevel >= 3
          ? Math.min(
            robustNoRouteFallback ? 14000 : 15500,
            Math.max(
              robustNoRouteFallback ? 6200 : 7000,
              Math.round(
                pointToPointDirectDistanceKm *
                  (robustNoRouteFallback ? 290 : 330),
              ),
            ),
          )
          : retryDetourLevel === 2
          ? Math.min(
            robustNoRouteFallback ? 10800 : 12500,
            Math.max(
              robustNoRouteFallback ? 4600 : 5600,
              Math.round(
                pointToPointDirectDistanceKm *
                  (robustNoRouteFallback ? 220 : 270),
              ),
            ),
          )
          : retryDetourLevel === 1
          ? Math.min(
            9500,
            Math.max(4400, Math.round(pointToPointDirectDistanceKm * 230)),
          )
          : 7000;
        const retryRadius = `${retryRadiusMeters}`;
        const retryRadiuses = retryWaypoints
          .map((_, i) =>
            (i === 0 || i === retryWaypoints.length - 1)
              ? "unlimited"
              : retryRadius
          )
          .join(";");

        route = await getMapboxRoute(
          retryWaypoints,
          mapboxProfile,
          excludeParams,
          retryRadiuses,
          MAPBOX_ACCESS_TOKEN,
          {
            continueStraight: requestContinueStraight,
            maxAttempts: 1,
            timeoutMs: pointToPointTimeoutMs(9000),
          },
        );
        const relaxedRetryExcludes = relaxStreetExcludes(
          excludeParams,
          avoidHighways,
        );
        if (!route && relaxedRetryExcludes !== excludeParams) {
          route = await getMapboxRoute(
            retryWaypoints,
            mapboxProfile,
            relaxedRetryExcludes,
            retryRadiuses,
            MAPBOX_ACCESS_TOKEN,
            {
              continueStraight: requestContinueStraight,
              maxAttempts: 1,
              timeoutMs: pointToPointTimeoutMs(7800),
            },
          );
        }
        if (route) {
          const retryQuality = evaluateRouteQuality(route, currentRouteType);
          if (!retryQuality.passed) {
            console.log(
              `P2P scenic retry ${
                retry + 1
              }: route rejected because of ${retryQuality.reason}`,
            );
            route = null;
            continue;
          }
        }
        if (route) {
          if (
            !isPointToPointDetourAcceptable(
              route,
              pointToPointDirectDistanceKm,
              softenedTarget ?? targetDistance,
              retryDetourLevel,
              retrySimplifyWaypoints,
            )
          ) {
            const routeDistanceKm = getRouteDistanceKm(route);
            const minimumDistanceKm = getPointToPointMinimumDistanceKm(
              pointToPointDirectDistanceKm,
              softenedTarget ?? targetDistance,
              retryDetourLevel,
              retrySimplifyWaypoints,
            );
            const maximumDistanceKm = getPointToPointMaximumDistanceKm(
              pointToPointDirectDistanceKm,
              softenedTarget ?? targetDistance,
              retryDetourLevel,
              retrySimplifyWaypoints,
            );
            console.log(
              `P2P scenic retry ${retry + 1}: route rejected because ${
                routeDistanceKm.toFixed(1)
              }km is outside ${minimumDistanceKm.toFixed(1)}-${
                maximumDistanceKm.toFixed(1)
              }km`,
            );
            route = null;
            continue;
          }
          finalWaypoints = retryWaypoints;
          radiusesParams = retryRadiuses;
        }
      }
    }

    if (
      !route &&
      planning_type === "Zufall" &&
      currentRouteType === "POINT_TO_POINT" &&
      body.destination_location &&
      pointToPointIsScenic &&
      hasPointToPointBudgetLeft(1600)
    ) {
      console.log("P2P scenic safe fallback: trying single-corridor midpoint");
      const directBearing = calculateBearing(
        startLocation,
        body.destination_location,
      );
      const midpoint = interpolateCoordinate(
        startLocation,
        body.destination_location,
        0.5,
      );
      const fallbackOffsetCapKm = detourLevel >= 3
        ? 11.0
        : detourLevel === 2
        ? 8.0
        : 6.0;
      const fallbackOffsetMinKm = detourLevel >= 3
        ? 5.0
        : detourLevel === 2
        ? 3.5
        : 2.2;
      const fallbackOffsetFactor = detourLevel >= 3
        ? 0.42
        : detourLevel === 2
        ? 0.34
        : 0.28;
      const fallbackOffsetKm = Math.min(
        fallbackOffsetCapKm,
        Math.max(
          fallbackOffsetMinKm,
          pointToPointDirectDistanceKm * fallbackOffsetFactor,
        ),
      );
      const primarySide = offsetSide === -1 || offsetSide === 1
        ? offsetSide
        : 1;
      for (const side of [primarySide, -primarySide]) {
        if (!hasPointToPointBudgetLeft(900)) break;
        const safeWaypoint = calculateDestination(
          midpoint,
          fallbackOffsetKm,
          directBearing + side * 90,
        );
        const safeWaypoints = [
          startLocation,
          safeWaypoint,
          body.destination_location,
        ];
        const safeRadiuses = "unlimited;12000;unlimited";
        route = await getMapboxRoute(
          safeWaypoints,
          mapboxProfile,
          excludeParams,
          safeRadiuses,
          MAPBOX_ACCESS_TOKEN,
          {
            continueStraight: requestContinueStraight,
            maxAttempts: 1,
            timeoutMs: pointToPointTimeoutMs(7000),
          },
        );
        const relaxedSafeFallbackExcludes = relaxStreetExcludes(
          excludeParams,
          avoidHighways,
        );
        if (!route && relaxedSafeFallbackExcludes !== excludeParams) {
          route = await getMapboxRoute(
            safeWaypoints,
            mapboxProfile,
            relaxedSafeFallbackExcludes,
            safeRadiuses,
            MAPBOX_ACCESS_TOKEN,
            {
              continueStraight: requestContinueStraight,
              maxAttempts: 1,
              timeoutMs: pointToPointTimeoutMs(6200),
            },
          );
        }
        if (!route) continue;
        const fallbackQuality = evaluateRouteQuality(route, currentRouteType);
        if (
          fallbackQuality.passed &&
          isPointToPointDetourAcceptable(
            route,
            pointToPointDirectDistanceKm,
            targetDistance,
            detourLevel,
            true,
          )
        ) {
          finalWaypoints = safeWaypoints;
          radiusesParams = safeRadiuses;
          break;
        }
        route = null;
      }
    }

    if (
      !route &&
      planning_type === "Zufall" &&
      currentRouteType === "POINT_TO_POINT" &&
      body.destination_location &&
      !pointToPointIsScenic
    ) {
      console.log(
        pointToPointIsScenic
          ? "P2P scenic fallback exhausted: using direct A->B route"
          : "P2P direct fallback: using direct A->B route",
      );
      const fallbackWaypoints = [startLocation, body.destination_location];
      const fallbackRadiuses = "unlimited;unlimited";
      route = await getMapboxRoute(
        fallbackWaypoints,
        mapboxProfile,
        applyAvoidHighwaysExcludes(excludeParams, avoidHighways),
        fallbackRadiuses,
        MAPBOX_ACCESS_TOKEN,
        {
          continueStraight: requestContinueStraight,
          maxAttempts: 1,
          timeoutMs: pointToPointTimeoutMs(7500),
        },
      );
      if (route) {
        finalWaypoints = fallbackWaypoints;
        radiusesParams = fallbackRadiuses;
      }
    }

    if (!route) {
      const debugRoundTripSearch = body.debug_roundtrip_search === true;
      const noRouteMessage = useRoundTripSearch
        ? "No route found with current constraints after exhausting round-trip search."
        : "No route found with current constraints.";
      if (debugRoundTripSearch) {
        return new Response(
          JSON.stringify({
            error: noRouteMessage,
            code: "NO_ROUTE",
            retryable: false,
            retry_after_sec: null,
            meta: requestDebugMeta,
            debug: roundTripSearch != null
              ? {
                search_summary: {
                  candidate_attempts: roundTripSearch.candidateAttempts,
                  accepted_candidates: roundTripSearch.acceptedCandidates,
                  rejected_candidates: roundTripSearch.rejectedCandidates,
                  reject_reasons: roundTripSearch.rejectReasons,
                  search_phases: roundTripSearch.searchPhases,
                  variant_hint: roundTripSearch.variantHint ?? null,
                  fingerprint_hint: roundTripSearch.fingerprintHint ?? null,
                  exhausted: roundTripSearch.exhausted == true,
                },
              }
              : null,
          }),
          {
            status: 404,
            headers: {
              ...getCorsHeaders(req),
              "Content-Type": "application/json",
            },
          },
        );
      }
      throw new Error(noRouteMessage);
    }

    // Mapbox returns distance in meters -> convert to kilometers for app output.
    let actualDistanceKm = (route.distance as number) / 1000;
    const skipPostSearchScaling = currentRouteType === "ROUND_TRIP" &&
      roundTripSearch?.terminalShortCircuit === true;

    // --- 4. Distance Band Retry & Scaling ---
    // Skaliert Waypoints näher/weiter zum Start bis die Route im ±10% Band liegt.
    // Aggressive Korrektur bei großem Fehler, sanfter bei Annäherung.
    if (
      planning_type === "Zufall" &&
      currentRouteType === "ROUND_TRIP" &&
      distanceConfig &&
      !skipPostSearchScaling
    ) {
      const scalingTargetKm = effectiveTargetDistanceKm ?? targetDistance!;
      const isWithinPreferredScalingBand = (distanceKm: number): boolean => {
        const preferredMinKm = avoidHighways
          ? Math.min(
            distanceConfig.acceptableMinKm,
            Math.round(scalingTargetKm * 0.64),
          )
          : Math.max(0, distanceConfig.acceptableMinKm - 1);
        const preferredMaxKm = avoidHighways
          ? Math.max(
            distanceConfig.acceptableMaxKm,
            Math.round(scalingTargetKm * 1.38),
          )
          : distanceConfig.acceptableMaxKm + 2;
        return distanceKm >= preferredMinKm && distanceKm <= preferredMaxKm;
      };
      let bestScaledRoute = route;
      let bestScaledWaypoints = finalWaypoints;
      let bestScaledDistanceKm = actualDistanceKm;
      let attempts = 0;
      const maxAttempts = avoidHighways ? 5 : 4;
      while (
        attempts < maxAttempts &&
        Date.now() - requestStartedAt < 22000 &&
        (actualDistanceKm > distanceConfig.maxKm ||
          actualDistanceKm < distanceConfig.minKm)
      ) {
        const ratio = (effectiveTargetDistanceKm ?? targetDistance!) /
          actualDistanceKm;
        // Aggressiver korrigieren bei großem Fehler, sanfter bei Annäherung
        // > 2x oder < 0.5x → 85% Korrektur (fast direkt)
        // 1.3x-2x → 70% Korrektur
        // < 1.3x → 50% Korrektur (Feintuning, verhindert Oszillation)
        const errorMagnitude = Math.abs(ratio - 1);
        const correctionStrength = errorMagnitude > 1.0
          ? 0.85
          : errorMagnitude > 0.3
          ? 0.70
          : 0.50;
        const scaleFactor = 1 + (ratio - 1) * correctionStrength;

        console.log(
          `Scaling attempt ${attempts + 1}: ${
            actualDistanceKm.toFixed(1)
          }km → target ${(effectiveTargetDistanceKm ??
            targetDistance)}km, ratio=${ratio.toFixed(2)}, scale=${
            scaleFactor.toFixed(3)
          }`,
        );

        // Alle Zwischenpunkte skalieren (nicht Start/Ende)
        const scaledWaypoints = finalWaypoints.map((wp, i) => {
          if (i === 0 || i === finalWaypoints.length - 1) return wp;
          return scaleWaypoint(startLocation, wp, scaleFactor);
        });

        const newRadiuses = scaledWaypoints
          .map((_, i) =>
            (i === 0 || i === scaledWaypoints.length - 1)
              ? "unlimited"
              : `${Math.round(distanceConfig.waypointRadiusMeters * 0.9)}`
          )
          .join(";");

        let newRoute = await getMapboxRoute(
          scaledWaypoints,
          mapboxProfile,
          excludeParams,
          newRadiuses,
          MAPBOX_ACCESS_TOKEN,
          {
            continueStraight: requestContinueStraight,
            maxAttempts: 1,
            timeoutMs: 6500,
            retryDelayBaseMs: 180,
          },
        );

        const relaxedScalingExcludes = relaxStreetExcludes(
          excludeParams,
          avoidHighways,
        );
        if (!newRoute && relaxedScalingExcludes !== excludeParams) {
          newRoute = await getMapboxRoute(
            scaledWaypoints,
            mapboxProfile,
            relaxedScalingExcludes,
            newRadiuses,
            MAPBOX_ACCESS_TOKEN,
            {
              continueStraight: requestContinueStraight,
              maxAttempts: 1,
              timeoutMs: 5800,
              retryDelayBaseMs: 180,
            },
          );
        }

        if (!newRoute) {
          console.log(
            `Scaling attempt ${attempts + 1}: No route found, stopping`,
          );
          break;
        }

        const scaledQuality = evaluateRouteQuality(newRoute, currentRouteType, {
          targetDistanceKm: effectiveTargetDistanceKm ?? targetDistance,
          distanceConfig,
          mode,
          avoidHighways,
        });
        if (!scaledQuality.passed) {
          console.log(
            `Scaling attempt ${
              attempts + 1
            }: Route rejected (${scaledQuality.reason})`,
          );
          break;
        }

        actualDistanceKm = (newRoute.distance as number) / 1000;
        const bestDeltaKm = Math.abs(bestScaledDistanceKm - scalingTargetKm);
        const candidateDeltaKm = Math.abs(actualDistanceKm - scalingTargetKm);
        const bestInPreferredBand = isWithinPreferredScalingBand(
          bestScaledDistanceKm,
        );
        const candidateInPreferredBand = isWithinPreferredScalingBand(
          actualDistanceKm,
        );
        if (
          (candidateInPreferredBand && !bestInPreferredBand) ||
          candidateDeltaKm + 0.25 < bestDeltaKm
        ) {
          bestScaledRoute = newRoute;
          bestScaledWaypoints = scaledWaypoints;
          bestScaledDistanceKm = actualDistanceKm;
        }

        route = newRoute;
        finalWaypoints = scaledWaypoints;
        attempts += 1;
      }
      route = bestScaledRoute;
      finalWaypoints = bestScaledWaypoints;
      actualDistanceKm = bestScaledDistanceKm;
      console.log(
        `Distance scaling done after ${attempts} attempts: ${
          actualDistanceKm.toFixed(1)
        } km (target: ${(effectiveTargetDistanceKm ??
          targetDistance)} km, band: ${distanceConfig.minKm}-${distanceConfig.maxKm} km)`,
      );
      const finalAcceptableMinKm = avoidHighways
        ? Math.min(
          distanceConfig.acceptableMinKm,
          Math.round((effectiveTargetDistanceKm ?? targetDistance!) * 0.64),
        )
        : Math.max(0, distanceConfig.acceptableMinKm - 1);
      const finalAcceptableMaxKm = avoidHighways
        ? Math.max(
          distanceConfig.acceptableMaxKm,
          Math.round((effectiveTargetDistanceKm ?? targetDistance!) * 1.38),
        )
        : distanceConfig.acceptableMaxKm + 2;
      const successFirstHardMinKm = Math.max(
        0,
        Math.round(
          (effectiveTargetDistanceKm ?? targetDistance!) *
            (avoidHighways ? 0.60 : 0.64),
        ),
      );
      const successFirstHardMaxKm = Math.round(
        (effectiveTargetDistanceKm ?? targetDistance!) *
          (avoidHighways ? 1.44 : 1.40),
      );
      const withinPreferredBand = actualDistanceKm >= finalAcceptableMinKm &&
        actualDistanceKm <= finalAcceptableMaxKm;
      const withinSuccessFirstHardBand =
        actualDistanceKm >= successFirstHardMinKm &&
        actualDistanceKm <= successFirstHardMaxKm;
      if (!withinPreferredBand && !withinSuccessFirstHardBand) {
        throw new Error(
          `No route found with current constraints after exhausting round-trip search. Final distance ${
            actualDistanceKm.toFixed(1)
          }km is outside acceptable band ${finalAcceptableMinKm}-${finalAcceptableMaxKm}km.`,
        );
      }
      if (!withinPreferredBand && withinSuccessFirstHardBand) {
        console.log(
          `[RT] Success-first keep: final distance ${
            actualDistanceKm.toFixed(1)
          }km outside preferred band ` +
            `${finalAcceptableMinKm}-${finalAcceptableMaxKm}km but inside hard band ` +
            `${successFirstHardMinKm}-${successFirstHardMaxKm}km`,
        );
      }
    }

    // ── Quality gate: Route muss echte Straßengeometrie haben ──
    const finalQuality = evaluateRouteQuality(route, currentRouteType, {
      targetDistanceKm: currentRouteType === "ROUND_TRIP"
        ? (effectiveTargetDistanceKm ?? targetDistance)
        : undefined,
      distanceConfig: currentRouteType === "ROUND_TRIP"
        ? distanceConfig ?? undefined
        : undefined,
      mode: currentRouteType === "ROUND_TRIP" ? mode : undefined,
      avoidHighways: currentRouteType === "ROUND_TRIP" ? avoidHighways : false,
    });
    if (!finalQuality.passed) {
      console.error(`Route quality too low: ${finalQuality.reason}`);
      throw new Error(
        `Route-Qualität zu niedrig (${finalQuality.reason}). Bitte erneut versuchen.`,
      );
    }

    // Always use the ACTUAL Mapbox distance — never clamp.
    const finalDistanceKm = actualDistanceKm;

    // Route wird NICHT in der Edge Function gespeichert.
    // Die App speichert via SavedRoutesService.saveRoute() MIT user_id.
    // (Edge Function hat keinen Auth-Context → konnte vorher kein user_id setzen)

    const routeForFrontend = {
      ...route,
      distance: route.distance, // Mapbox-Originalwert in METERN beibehalten
      legs: route.legs ?? [],
    };

    // Construct response
    return new Response(
      JSON.stringify({
        route: routeForFrontend,
        waypoints: finalWaypoints,
        meta: {
          distance_km: finalDistanceKm,
          duration_min: route.duration / 60,
          profile: mapboxProfile.replace("mapbox/", ""),
          mode: mode,
          style_profile: body.style_profile ?? null,
          route_type: currentRouteType,
          detour_level: detourLevel,
          avoid_highways_requested: avoidHighways,
          effective_excludes: excludeParams,
          request_id: debugBody.request_id ?? null,
          client_scenario_key: debugBody.client_scenario_key ?? null,
          client_force_fresh_variant:
            debugBody.client_force_fresh_variant === true,
          client_trigger: debugBody.client_trigger ?? null,
          variant_hint: variantHint ?? null,
          fingerprint_hint: fingerprintHint ?? null,
          max_candidate_attempts: maxCandidateAttemptsHint ?? null,
          waypoint_count: finalWaypoints.length,
          quality_tier: finalQuality.tier,
          quality_reason: finalQuality.reason,
          quality_overlap_percent: finalQuality.overlapPercent,
          quality_coordinate_count: finalQuality.coordinateCount,
          requested_target_distance_km: currentRouteType === "ROUND_TRIP"
            ? targetDistance ?? null
            : null,
          effective_target_distance_km: currentRouteType === "ROUND_TRIP"
            ? effectiveTargetDistanceKm ?? targetDistance ?? null
            : null,
          ...(roundTripSearch?.route != null
            ? {
              search_summary: {
                candidate_attempts: roundTripSearch.candidateAttempts,
                accepted_candidates: roundTripSearch.acceptedCandidates,
                rejected_candidates: roundTripSearch.rejectedCandidates,
                reject_reasons: roundTripSearch.rejectReasons,
                search_phases: roundTripSearch.searchPhases,
                variant_hint: roundTripSearch.variantHint ?? null,
                fingerprint_hint: roundTripSearch.fingerprintHint ?? null,
              },
            }
            : {}),
        },
      }),
      {
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
      },
    );
  } catch (error: any) {
    const message = error?.message ??
      "Unbekannter Fehler in generate-cruise-route";
    const classification = classifyRoutingError(message);
    console.error(
      "Error in generate-cruise-route:",
      message,
      error?.stack ?? "",
    );
    const responseHeaders: Record<string, string> = {
      ...getCorsHeaders(req),
      "Content-Type": "application/json",
    };
    if (classification.retryAfterSec != null) {
      responseHeaders["Retry-After"] = String(classification.retryAfterSec);
    }
    return new Response(
      JSON.stringify({
        error: message,
        code: classification.code,
        retryable: classification.retryable,
        retry_after_sec: classification.retryAfterSec ?? null,
        meta: requestDebugMeta,
      }),
      {
        status: classification.status,
        headers: responseHeaders,
      },
    );
  }
});
