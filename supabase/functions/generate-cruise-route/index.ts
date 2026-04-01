// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"

// Environment variables
const MAPBOX_ACCESS_TOKEN = Deno.env.get('MAPBOX_ACCESS_TOKEN')

// Erlaubte Origins — eigene App, Supabase-Domain und GitHub Pages
const ALLOWED_ORIGINS = [
    'https://tlcfaxvvqzobmzwvfnvb.supabase.co',
    'https://cruiseconnector.github.io',
]

function getCorsHeaders(req?: Request) {
    const origin = req?.headers.get('origin') ?? ''
    const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0]
    return {
        'Access-Control-Allow-Origin': allowedOrigin,
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    }
}

interface Coordinate {
    latitude: number
    longitude: number
}

type RouteMode = 'Kurvenjagd' | 'Sport Mode' | 'Abendrunde' | 'Entdecker' | 'Standard'

interface RequestData {
    planning_type: 'Zufall' | 'Wegpunkte'
    route_type?: 'ROUND_TRIP' | 'POINT_TO_POINT'
    manual_waypoints?: Coordinate[]
    targetDistance?: number // in km
    startLocation: Coordinate
    destination_location?: Coordinate
    mode?: RouteMode
    randomSeed?: number
    detour_level?: number
    detour_factor?: number
    avoid_highways?: boolean
    direction_hint?: number
    offset_side?: number
    style_profile?: string
    waypoint_shape_factor?: number
    radius_multiplier?: number
    prefer_flat_terrain?: boolean
    zigzag_waypoints?: boolean
    continue_straight?: boolean
    route_variant_hint?: string
    variant_hint?: string
    route_fingerprint_hint?: string
    fingerprint_hint?: string
    max_candidate_attempts?: number
    simplify_waypoints?: boolean
    max_waypoints?: number
}

interface DistanceConfig {
    radiusKm: number
    minKm: number
    maxKm: number
    acceptableMinKm: number
    acceptableMaxKm: number
    waypointRadiusMeters: number
}

type RouteQualityTier = 'ideal' | 'acceptable' | 'fallback' | 'reject'

interface RouteQualityEvaluation {
    passed: boolean
    reason: string
    overlapPercent: number
    hasUTurn: boolean
    tier: RouteQualityTier
    score: number
    coordinateCount: number
    actualDistanceKm: number
    distanceDeltaKm: number
}

interface RoundTripCandidatePlan {
    label: string
    waypoints: Coordinate[]
    radiuses: string
}

interface RoundTripSearchResult {
    route: any
    waypoints: Coordinate[]
    radiuses: string
    quality: RouteQualityEvaluation
    candidateAttempts: number
    acceptedCandidates: number
    rejectedCandidates: number
    rejectReasons: Record<string, number>
    searchPhases: string[]
    variantHint?: string
    fingerprintHint?: string
}

interface MapboxRouteFetchResult {
    route: any | null
    outcome: 'ok' | 'no_route' | 'http_error' | 'network_error' | 'timeout'
    statusCode?: number
    details?: string
}

const RETRYABLE_MAPBOX_STATUS_CODES = new Set([408, 409, 425, 429, 500, 502, 503, 504])
const MAX_MAPBOX_FETCH_ATTEMPTS = 3
const MAPBOX_FETCH_TIMEOUT_MS = 15000

function wait(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms))
}

function normalizeBearingDegrees(value: number): number {
    const normalized = value % 360
    return normalized < 0 ? normalized + 360 : normalized
}

function seededBaseBearing(seed: number, preferredBearingDegrees?: number): number {
    if (typeof preferredBearingDegrees === 'number' && Number.isFinite(preferredBearingDegrees)) {
        const jitter = (seededUnit(seed + 601) - 0.5) * 110
        return normalizeBearingDegrees(preferredBearingDegrees + jitter)
    }
    return seededUnit(seed) * 360
}

/**
 * Calculates a new coordinate given a starting point, distance (km), and bearing (degrees).
 */
function calculateDestination(start: Coordinate, distanceKm: number, bearingDegrees: number): Coordinate {
    const R = 6371 // Earth's radius in km
    const bearingRad = (bearingDegrees * Math.PI) / 180
    const lat1 = (start.latitude * Math.PI) / 180
    const lon1 = (start.longitude * Math.PI) / 180

    const lat2 = Math.asin(
        Math.sin(lat1) * Math.cos(distanceKm / R) +
        Math.cos(lat1) * Math.sin(distanceKm / R) * Math.cos(bearingRad)
    )

    const lon2 = lon1 + Math.atan2(
        Math.sin(bearingRad) * Math.sin(distanceKm / R) * Math.cos(lat1),
        Math.cos(distanceKm / R) - Math.sin(lat1) * Math.sin(lat2)
    )

    return {
        latitude: (lat2 * 180) / Math.PI,
        longitude: (lon2 * 180) / Math.PI,
    }
}

function getDistanceConfig(targetDistance: number, mode?: string): DistanceConfig {
    // Erfolgsquote vor Perfektion: idealer Zielkorridor plus breiterer
    // akzeptabler Bereich, damit brauchbare Rundkurse nicht zu früh scheitern.
    const idealTolerance = targetDistance <= 60
        ? 0.16
        : targetDistance <= 100
        ? 0.14
        : 0.12;
    const acceptableTolerance = targetDistance <= 60
        ? 0.32
        : targetDistance <= 100
        ? 0.28
        : 0.24;
    const minKm = Math.round(targetDistance * (1 - idealTolerance));
    const maxKm = Math.round(targetDistance * (1 + idealTolerance));
    const acceptableMinKm = Math.round(targetDistance * (1 - acceptableTolerance));
    const acceptableMaxKm = Math.round(targetDistance * (1 + acceptableTolerance));

    // Formel: radius = targetDistance / (2 * PI * road_factor)
    // road_factor variiert stark je nach Stil, weil Landstraßen-Routing
    // deutlich längere Wege erzeugt als Direktverbindungen.
    let roadFactor: number;
    switch (mode) {
        case 'Kurvenjagd':
            roadFactor = 1.70; // Mehr Suchraum, damit Kurvenmodus nicht verhungert
            break;
        case 'Entdecker':
            roadFactor = 1.60; // Breiterer Suchraum für ungewöhnliche Straßen
            break;
        case 'Abendrunde':
            roadFactor = 1.12; // Ruhiger, aber nicht zu eng um den Start
            break;
        case 'Sport Mode':
            roadFactor = 1.28; // Fließender Radius, bessere Trefferquote
            break;
        default:
            roadFactor = 1.25;
    }
    const shortDistanceBoost = targetDistance <= 60
        ? 0.80
        : targetDistance <= 100
        ? 0.89
        : 0.96;
    const radiusKm = targetDistance / (2 * Math.PI * roadFactor * shortDistanceBoost);
    let waypointRadiusMeters = targetDistance <= 60 ? 3200 : targetDistance <= 100 ? 4200 : 5200;
    if (mode === 'Kurvenjagd') waypointRadiusMeters += 500;
    if (mode === 'Entdecker') waypointRadiusMeters += 700;
    if (mode === 'Abendrunde') waypointRadiusMeters = Math.max(2800, waypointRadiusMeters - 200);

    console.log(
        `Distance config: target=${targetDistance}km, radius=${radiusKm.toFixed(1)}km, ` +
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

/**
 * Generates 2 waypoints forming a true triangle to prevent start-area loops.
 *
 * Triangle approach: WP1 and WP2 are on OPPOSITE SIDES of the start,
 * separated by 100–140°. This creates a natural triangle where Mapbox
 * routes Start→WP1→WP2→Start using three clearly distinct road segments
 * and never needs to pass back through the start area.
 *
 * Route: Start → WP1 → WP2 → Start
 */
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

/**
 * Generates loop waypoints with multiple points for varied routes.
 * Uses 4-6 waypoints arranged in a circle pattern for true loop experience.
 * Avoids returning on the same path by offsetting return route.
 */
function calculateLoopWaypoints(
    start: Coordinate,
    searchRadiusKm: number,
    numWaypoints: number = 5,
    seed?: number,
    preferredBearingDegrees?: number,
): Coordinate[] {
    // Seeded random für reproduzierbare aber variable Routen
    const s = seed ?? Math.floor(Math.random() * 100000);
    const rng = (offset: number) => seededUnit(s + offset);

    const baseBearing = seededBaseBearing(s + 97, preferredBearingDegrees);
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
        const bearing = baseBearing + startOffset + (angleStep * i) + (rng(11 + i * 2) * 12 - 6);

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
): Coordinate[] {
    const s = seed ?? Math.floor(Math.random() * 100000);
    const rng = (offset: number) => seededUnit(s + offset);
    const baseBearing = seededBaseBearing(s + 211, preferredBearingDegrees);
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

/**
 * Generates return path waypoints that avoid the outbound route.
 * Creates a "figure-8" or wide loop pattern instead of backtracking.
 */
function calculateReturnPath(start: Coordinate, outboundWaypoints: Coordinate[], seed?: number): Coordinate[] {
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
): Coordinate[] {
    const outbound = calculateLoopWaypoints(
        start,
        searchRadiusKm,
        Math.max(2, outboundWaypointCount),
        seed,
        preferredBearingDegrees,
    );
    const returnWaypoints = calculateReturnPath(start, outbound, (seed ?? 0) + 73);
    return [...outbound, ...returnWaypoints];
}

function enforceWaypointRadiusBand(
    start: Coordinate,
    waypoints: Coordinate[],
    minRadiusKm: number,
    maxRadiusKm: number,
): Coordinate[] {
    const clampedMin = Math.max(0, minRadiusKm)
    const clampedMax = Math.max(clampedMin + 0.05, maxRadiusKm)
    return waypoints.map((wp) => {
        const radius = calculateDistance(start, wp)
        if (radius >= clampedMin && radius <= clampedMax) return wp
        const bearing = calculateBearing(start, wp)
        const adjustedRadius = Math.min(clampedMax, Math.max(clampedMin, radius))
        return calculateDestination(start, adjustedRadius, bearing)
    })
}

function smoothWaypointChain(waypoints: Coordinate[], strength: number = 0.2): Coordinate[] {
    if (waypoints.length < 3) return waypoints
    const clampedStrength = Math.max(0, Math.min(0.45, strength))
    return waypoints.map((wp, i) => {
        if (i === 0 || i === waypoints.length - 1) return wp
        const prev = waypoints[i - 1]
        const next = waypoints[i + 1]
        const corridorMid = {
            latitude: (prev.latitude + next.latitude) / 2,
            longitude: (prev.longitude + next.longitude) / 2,
        }
        return {
            latitude: wp.latitude * (1 - clampedStrength) + corridorMid.latitude * clampedStrength,
            longitude: wp.longitude * (1 - clampedStrength) + corridorMid.longitude * clampedStrength,
        }
    })
}

function buildWaypointRadiuses(waypoints: Coordinate[], intermediateRadiusMeters: number): string {
    return waypoints
        .map((_, i) => (i === 0 || i === waypoints.length - 1) ? 'unlimited' : `${intermediateRadiusMeters}`)
        .join(';');
}

function dedupeRoundTripPlans(plans: RoundTripCandidatePlan[]): RoundTripCandidatePlan[] {
    const seen = new Set<string>();
    const result: RoundTripCandidatePlan[] = [];

    for (const plan of plans) {
        const signature = plan.waypoints
            .map((wp) => `${wp.latitude.toFixed(4)},${wp.longitude.toFixed(4)}`)
            .join('|');
        if (seen.has(signature)) continue;
        seen.add(signature);
        result.push(plan);
    }

    return result;
}

function buildRoundTripWaypointCandidates({
    start,
    distanceConfig,
    targetDistanceKm,
    mode,
    randomSeed,
    preferredBearingDegrees,
    waypointShapeFactor,
    radiusMultiplier = 1,
    zigzagWaypoints = false,
}: {
    start: Coordinate
    distanceConfig: DistanceConfig
    targetDistanceKm: number
    mode?: RouteMode
    randomSeed: number
    preferredBearingDegrees?: number
    waypointShapeFactor?: number
    radiusMultiplier?: number
    zigzagWaypoints?: boolean
}): RoundTripCandidatePlan[] {
    const plans: RoundTripCandidatePlan[] = [];
    const shortTarget = targetDistanceKm <= 60;
    const mediumTarget = targetDistanceKm > 60 && targetDistanceKm <= 110;
    const longTarget = targetDistanceKm > 110;
    const baseRadius = distanceConfig.radiusKm * Math.max(0.7, radiusMultiplier);
    const baseSnapRadius = distanceConfig.waypointRadiusMeters;

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
    ) => calculateCardinalLoopWaypoints(
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
    ) => calculateLoopWaypoints(
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
    ) => calculateLoopWithReturnWaypoints(
        start,
        baseRadius * multiplier,
        waypointCount,
        randomSeed + seedOffset,
        preferredBearingDegrees,
    );
    const zigzag = (multiplier: number, seedOffset: number) =>
        calculateZigZagWaypoints(
            start,
            baseRadius * multiplier,
            randomSeed + seedOffset,
            preferredBearingDegrees,
        );

    switch (mode) {
        case 'Kurvenjagd':
            if (longTarget) {
                addPlan('curve-zigzag-core', zigzag(1.06, 73), 1.16);
                addPlan('curve-cardinal-wide', cardinal(1.14, 101, 1.0), 1.12);
                addPlan('curve-triangle-wide', triangle(1.14, 887), 1.10);
                addPlan('curve-return-long', loopWithReturn(1.10, 3, 263), 1.14);
                addPlan('curve-loop-wide', loop(1.20, 4, 131), 1.16);
                addPlan('curve-loop-open', loop(1.28, 4, 541), 1.20);
                addPlan('curve-triangle', triangle(1.00, 397), 1.0);
                addPlan('curve-loop-tight', loop(1.02, 4, 11), 1.05);
                addPlan('curve-loop-scout', loop(0.92, 3, 997), 1.0);
            } else {
                addPlan('curve-zigzag-core', zigzag(1.02, 73), 1.12);
                addPlan(
                    'curve-cardinal-tight',
                    cardinal(1.06, 101, 1.0),
                    1.08,
                );
                addPlan('curve-loop-tight', loop(1.08, shortTarget ? 4 : 5, 11), 1.05);
                addPlan('curve-loop-wide', loop(longTarget ? 1.26 : 1.18, mediumTarget ? 4 : 5, 131), 1.16);
                addPlan('curve-loop-open', loop(longTarget ? 1.34 : 1.24, mediumTarget ? 5 : 4, 541), 1.22);
                addPlan('curve-return', loopWithReturn(1.12, 3, 263), 1.18);
                addPlan('curve-triangle', triangle(1.02, 397), 1.0);
                addPlan('curve-triangle-wide', triangle(1.20, 887), 1.14);
                addPlan('curve-loop-scout', loop(0.94, shortTarget ? 3 : 4, 997), 1.0);
            }
            break;
        case 'Abendrunde':
            addPlan('evening-cardinal-soft', cardinal(0.84, 91, 0.92), 0.94);
            addPlan('evening-triangle-compact', triangle(0.90, 17), 0.95);
            addPlan('evening-triangle-wide', triangle(1.05, 149), 1.0);
            addPlan('evening-triangle-extended', triangle(1.18, 563), 1.1);
            addPlan('evening-loop-soft', loop(0.98, 3, 281), 1.0);
            addPlan('evening-return', loopWithReturn(0.94, 2, 419), 1.05);
            addPlan('evening-loop-wide', loop(1.12, 3, 881), 1.12);
            addPlan('evening-triangle-relaxed', triangle(1.28, 1151), 1.16);
            break;
        case 'Entdecker':
            addPlan('explore-cardinal-wide', cardinal(1.12, 67, 1.08), 1.12);
            if (zigzagWaypoints) {
                addPlan('explore-zigzag', zigzag(1.06, 883), 1.12);
            }
            addPlan('explore-loop-wide', loop(longTarget ? 1.28 : 1.18, mediumTarget ? 4 : 5, 23), 1.16);
            addPlan('explore-return', loopWithReturn(1.10, 4, 163), 1.20);
            addPlan('explore-loop-offset', loop(1.08, shortTarget ? 3 : 4, 307), 1.15);
            addPlan('explore-loop-far', loop(longTarget ? 1.36 : 1.24, mediumTarget ? 5 : 4, 587), 1.24);
            addPlan('explore-triangle', triangle(1.12, 443), 1.0);
            addPlan('explore-loop-scout', loop(0.96, shortTarget ? 3 : 4, 953), 1.08);
            addPlan('explore-return-open', loopWithReturn(1.22, 4, 1301), 1.26);
            break;
        case 'Sport Mode':
        default:
            addPlan(
                'sport-cardinal-ellipse',
                cardinal(1.04, 59, waypointShapeFactor ?? 2.0),
                1.02,
            );
            addPlan('sport-loop-flow', loop(1.10, shortTarget ? 3 : 4, 29), 1.0);
            addPlan('sport-loop-wide', loop(longTarget ? 1.22 : 1.14, mediumTarget ? 4 : 3, 173), 1.12);
            addPlan('sport-loop-extended', loop(longTarget ? 1.30 : 1.18, mediumTarget ? 4 : 3, 611), 1.18);
            addPlan('sport-return', loopWithReturn(1.04, 3, 313), 1.10);
            addPlan('sport-triangle', triangle(1.00, 457), 1.0);
            addPlan('sport-loop-scout', loop(0.92, 3, 1031), 1.0);
            addPlan('sport-triangle-wide', triangle(1.16, 1289), 1.08);
            break;
    }

    addPlan('fallback-cardinal', cardinal(1.00, 1499, waypointShapeFactor ?? 1.0), 1.08);
    addPlan('fallback-triangle-compact', triangle(0.84, 503), 1.0);
    addPlan('fallback-triangle-balanced', triangle(1.00, 619), 1.05);
    addPlan('fallback-triangle-wide', triangle(1.16, 1181), 1.10);
    addPlan('fallback-triangle-very-wide', triangle(1.28, 1571), 1.18);
    addPlan('fallback-loop-3', loop(1.02, 3, 733), 1.1);
    addPlan('fallback-loop-4', loop(1.12, 4, 857), 1.14);
    addPlan('fallback-loop-5', loop(1.20, 5, 1093), 1.20);
    addPlan('fallback-loop-6', loop(1.30, 5, 1741), 1.26);
    addPlan('fallback-return', loopWithReturn(1.08, 3, 977), 1.16);
    addPlan('fallback-return-wide', loopWithReturn(1.20, 4, 1901), 1.24);

    return dedupeRoundTripPlans(plans);
}

/**
 * Calculate bearing between two coordinates in degrees.
 */
function calculateBearing(from: Coordinate, to: Coordinate): number {
    const lat1 = (from.latitude * Math.PI) / 180;
    const lat2 = (to.latitude * Math.PI) / 180;
    const dLon = ((to.longitude - from.longitude) * Math.PI) / 180;
    
    const y = Math.sin(dLon) * Math.cos(lat2);
    const x = Math.cos(lat1) * Math.sin(lat2) -
              Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
    
    const bearing = (Math.atan2(y, x) * 180) / Math.PI;
    return (bearing + 360) % 360;
}

/**
 * Calculate distance between two coordinates in km.
 */
function calculateDistance(from: Coordinate, to: Coordinate): number {
    const R = 6371;
    const lat1 = (from.latitude * Math.PI) / 180;
    const lat2 = (to.latitude * Math.PI) / 180;
    const dLat = ((to.latitude - from.latitude) * Math.PI) / 180;
    const dLon = ((to.longitude - from.longitude) * Math.PI) / 180;
    
    const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
              Math.cos(lat1) * Math.cos(lat2) *
              Math.sin(dLon/2) * Math.sin(dLon/2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    
    return R * c;
}

function interpolateCoordinate(from: Coordinate, to: Coordinate, fraction: number): Coordinate {
    const clamped = Math.min(1, Math.max(0, fraction))
    return {
        latitude: from.latitude + (to.latitude - from.latitude) * clamped,
        longitude: from.longitude + (to.longitude - from.longitude) * clamped,
    }
}

function seededUnit(seed: number): number {
    const raw = Math.sin(seed * 12.9898 + 78.233) * 43758.5453123
    return raw - Math.floor(raw)
}

function stableStringHash(input: string): number {
    let hash = 2166136261
    for (let i = 0; i < input.length; i++) {
        hash ^= input.charCodeAt(i)
        hash = Math.imul(hash, 16777619)
    }
    return (hash >>> 0)
}

function normalizeHint(value?: string): string | undefined {
    if (typeof value !== 'string') return undefined
    const trimmed = value.trim()
    return trimmed.length > 0 ? trimmed : undefined
}

function getRetryKindFromMapboxFailure(
    failure: Pick<MapboxRouteFetchResult, 'outcome' | 'statusCode' | 'details'>,
): 'rate_limit' | 'timeout' | 'other' {
    if (failure.outcome === 'timeout') return 'timeout'
    if (failure.statusCode === 429) return 'rate_limit'
    const details = String(failure.details ?? '').toLowerCase()
    if (details.includes('too many requests') || details.includes('rate limit')) {
        return 'rate_limit'
    }
    if (details.includes('timeout') || details.includes('timed out') || details.includes('abort')) {
        return 'timeout'
    }
    return 'other'
}

function prioritizeCandidatePlans(
    plans: RoundTripCandidatePlan[],
    phaseName: string,
    variantHint?: string,
    fingerprintHint?: string,
): RoundTripCandidatePlan[] {
    if (plans.length <= 1) return plans

    const normalizedVariant = normalizeHint(variantHint)?.toLowerCase()
    const preferredTokens = normalizedVariant
        ? normalizedVariant.split(/[^a-z0-9_-]+/i).filter(Boolean)
        : []

    const preferred = preferredTokens.length === 0
        ? []
        : plans.filter((plan) => preferredTokens.some((token) => plan.label.toLowerCase().includes(token)))
    const remaining = preferredTokens.length === 0
        ? [...plans]
        : plans.filter((plan) => !preferred.includes(plan))

    if (remaining.length <= 1) {
        return [...preferred, ...remaining]
    }

    const normalizedFingerprint = normalizeHint(fingerprintHint)
    const rotationSeed = normalizedFingerprint
        ? stableStringHash(`${phaseName}:${normalizedFingerprint}`)
        : 0
    const startIndex = rotationSeed % remaining.length
    const rotated = remaining.slice(startIndex).concat(remaining.slice(0, startIndex))
    return [...preferred, ...rotated]
}

function buildPointToPointScenicWaypoints({
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
}: {
    start: Coordinate
    destination: Coordinate
    mode?: RouteMode
    targetDistance?: number
    detourLevel: number
    detourFactor?: number
    offsetSide?: number
    waypointShapeFactor?: number
    zigzagWaypoints?: boolean
    randomSeed?: number
    simplifyWaypoints?: boolean
    maxWaypoints?: number
}): Coordinate[] {
    const directDistanceKm = calculateDistance(start, destination)
    if (directDistanceKm < 1.5) {
        return [start, destination]
    }

    // Stil-Boost: wie viel Extra-Distanz der Stil zur Route hinzufügt
    // Kurvenjagd braucht mehr Umweg (enge Straßen = längere Wege)
    const scenicModeBoost = mode === 'Kurvenjagd'
        ? 0.30
        : mode === 'Entdecker'
        ? 0.35
        : mode === 'Sport Mode'
        ? 0.18
        : mode === 'Abendrunde'
        ? 0.12
        : 0.0

    // Umweg-Boost: lateral offset 18% / 40% / 70% der Luftlinie
    const detourBoost = detourLevel === 1
        ? 0.26
        : detourLevel === 2
        ? 0.40
        : detourLevel >= 3
        ? 0.70
        : 0.0

    const effectiveFactor = Math.max(
        detourFactor ?? 1.0,
        1.0 + scenicModeBoost + detourBoost,
    )
    const desiredDistanceKm = Math.max(
        targetDistance ?? 0,
        directDistanceKm * effectiveFactor,
    )
    const minimumExtraDistanceKm = detourLevel === 1
        ? 6.5
        : detourLevel === 2
        ? 12.0
        : detourLevel >= 3
        ? 22.0
        : 3.0
    let extraDistanceKm = Math.max(
        minimumExtraDistanceKm,
        desiredDistanceKm - directDistanceKm,
    )
    if (simplifyWaypoints) {
        extraDistanceKm *= detourLevel >= 2 ? 0.82 : 0.9
    }

    // Waypoint-Anzahl: je Umweg-Level + Seed-Variation.
    // Klein kann auf längeren Strecken 1 oder 2 Wegpunkte nutzen.
    let waypointCount: number;
    if (detourLevel >= 3) {
        waypointCount = 3; // Groß: 3 WPs weit aufgefächert
    } else if (detourLevel >= 2) {
        waypointCount = 2; // Mittel: 2 WPs in S-Form
    } else if (detourLevel >= 1) {
        const useTwoWaypoints = directDistanceKm >= 18 &&
            seededUnit(randomSeed + Math.round(directDistanceKm * 10)) > 0.35
        waypointCount = useTwoWaypoints ? 2 : 1;
    } else {
        waypointCount = 0; // Direkt: keine Extra-Waypoints
    }
    if (directDistanceKm < 12) waypointCount = Math.min(waypointCount, 2);
    if (directDistanceKm < 6) waypointCount = Math.min(waypointCount, 1);
    if (simplifyWaypoints) {
        const cappedWaypoints = Math.max(
            1,
            Math.min(3, maxWaypoints ?? (detourLevel >= 3 ? 2 : 1)),
        )
        waypointCount = Math.min(waypointCount, cappedWaypoints)
    }

    // Fractions: wo auf der A→B Linie werden die Waypoints platziert
    const onePointFraction = 0.50 + (seededUnit(randomSeed + 211) - 0.5) * 0.24
    const twoPointTemplate = seededUnit(randomSeed + 307) >= 0.5
        ? [0.28, 0.72]
        : [0.35, 0.67]
    const rawFractions = waypointCount === 1
        ? [onePointFraction]
        : waypointCount === 2
        ? twoPointTemplate
        : waypointCount === 3
        ? [0.2, 0.5, 0.8]
        : waypointCount === 4
        ? [0.15, 0.38, 0.62, 0.85]
        : [0.12, 0.3, 0.5, 0.7, 0.88]
    const fractionJitter = detourLevel === 1 ? 0.08 : detourLevel === 2 ? 0.06 : 0.05
    const fractions = rawFractions
        .map((fraction, index) => {
            const jitter = (seededUnit(randomSeed + 401 + index * 29) - 0.5) * 2 * fractionJitter
            return Math.min(0.9, Math.max(0.1, fraction + jitter))
        })
        .sort((a, b) => a - b)

    const baseBearing = calculateBearing(start, destination)
    // Seite determiniert durch Seed — aber bei Entdecker wechselnd pro WP
    const requestedOffsetSide = offsetSide === -1 ? -1 : offsetSide === 1 ? 1 : null
    const baseSide = requestedOffsetSide ??
        (seededUnit(randomSeed + detourLevel + Math.round(directDistanceKm)) >= 0.5 ? 1 : -1)

    // Offset-Limits je nach Umweg-Level (drastischer gespreizt)
    let maxOffsetKm = detourLevel === 1
        ? Math.max(
            5.5,
            Math.min(directDistanceKm * 0.42, extraDistanceKm * 0.85 + 3.5),
        )
        : detourLevel === 2
        ? Math.max(
            7.0,
            Math.min(directDistanceKm * 0.58, extraDistanceKm * 0.92 + 4.5),
        )
        : Math.max(
            9.0,
            Math.min(directDistanceKm * 0.76, extraDistanceKm * 1.04 + 6.5),
        )
    let minOffsetKm = detourLevel === 1
        ? Math.min(maxOffsetKm, Math.max(4.0, maxOffsetKm * 0.58))
        : detourLevel === 2
        ? Math.min(maxOffsetKm, Math.max(5.5, maxOffsetKm * 0.52))
        : Math.min(maxOffsetKm, Math.max(7.0, maxOffsetKm * 0.48))
    if (simplifyWaypoints) {
        maxOffsetKm *= detourLevel >= 2 ? 0.74 : 0.80
        minOffsetKm *= detourLevel >= 2 ? 0.72 : 0.78
    }

    const scenicWaypoints = fractions.map((fraction, index) => {
        const basePoint = interpolateCoordinate(start, destination, fraction)
        const variationSeed = randomSeed + (index + 1) * 17
        const variation = 0.85 + seededUnit(variationSeed) * 0.35

        // Stilspezifische Offset-Berechnung
        let arcFactor: number;
        let angleDrift: number;
        let side: number;

        switch (mode) {
            case 'Kurvenjagd':
                // Curvy but controlled corridor to avoid hooks/stubs.
                arcFactor = 0.96 + index * 0.16;
                angleDrift = (seededUnit(variationSeed + 7) - 0.5) * 34;
                side = index % 2 === 0 ? baseSide : -baseSide;
                break;
            case 'Entdecker':
                // Keep one dominant side with optional single crossover.
                arcFactor = 0.84 + seededUnit(variationSeed + 3) * 0.46;
                angleDrift = (seededUnit(variationSeed + 7) - 0.5) * 42;
                side = waypointCount >= 3 && index === 1 && seededUnit(variationSeed + 11) >= 0.58
                    ? -baseSide
                    : baseSide;
                break;
            case 'Abendrunde':
                // Sanfter, gleichmäßiger Bogen — alle auf einer Seite, nah dran
                arcFactor = 0.5 + index * 0.1;
                angleDrift = (seededUnit(variationSeed + 7) - 0.5) * 12;
                side = baseSide;
                break;
            default: // Sport Mode
                // Weicher Bogen, mittlerer Offset, leicht wechselnd
                arcFactor = detourLevel === 1
                    ? 0.86 + index * 0.14
                    : 0.72 + index * 0.16;
                angleDrift = (seededUnit(variationSeed + 7) - 0.5) *
                    (detourLevel === 1 ? 30 : 24);
                side = waypointCount <= 1
                    ? baseSide
                    : (index % 2 === 0 ? baseSide : -baseSide);
        }

        if (zigzagWaypoints) {
            side = index % 2 === 0 ? baseSide : -baseSide
            angleDrift += 7
        }
        if (typeof waypointShapeFactor === 'number' && Number.isFinite(waypointShapeFactor)) {
            arcFactor *= Math.max(0.75, Math.min(2.0, waypointShapeFactor))
        }

        const offsetKm = Math.min(
            maxOffsetKm,
            Math.max(minOffsetKm, extraDistanceKm * arcFactor * variation),
        )

        return calculateDestination(
            basePoint,
            offsetKm,
            baseBearing + side * (90 + angleDrift),
        )
    })

    const corridorWaypoints = smoothWaypointChain(
        scenicWaypoints,
        simplifyWaypoints ? 0.24 : 0.18,
    )
    const minCorridorRadiusKm = Math.max(
        directDistanceKm * (simplifyWaypoints ? 0.14 : 0.18),
        0.9,
    )
    const maxCorridorRadiusKm = Math.max(
        minCorridorRadiusKm + 0.4,
        directDistanceKm * (detourLevel >= 2 ? 0.92 : 0.84),
    )

    return [
        start,
        ...enforceWaypointRadiusBand(
            start,
            corridorWaypoints,
            minCorridorRadiusKm,
            maxCorridorRadiusKm,
        ),
        destination,
    ]
}

function getRouteDistanceKm(route: any): number {
    return typeof route?.distance === 'number' ? route.distance / 1000 : 0
}

function getPointToPointMinimumDistanceKm(
    directDistanceKm: number,
    targetDistance: number | undefined,
    detourLevel: number,
    relaxed = false,
): number {
    const detourMultiplier = relaxed
        ? detourLevel === 1
            ? 1.14
            : detourLevel === 2
            ? 1.32
            : detourLevel >= 3
            ? 1.55
            : 1.0
        : detourLevel === 1
        ? 1.25   // Klein: mindestens +25%
        : detourLevel === 2
        ? 1.50   // Mittel: mindestens +50%
        : detourLevel >= 3
        ? 1.90   // Groß: mindestens +90%
        : 1.0
    const targetFactor = relaxed
        ? detourLevel >= 2
            ? 0.88
            : 0.90
        : 0.985

    return Math.max(
        targetDistance ? targetDistance * targetFactor : 0,
        directDistanceKm * detourMultiplier,
    )
}

function getPointToPointMaximumDistanceKm(
    directDistanceKm: number,
    targetDistance: number | undefined,
    detourLevel: number,
    relaxed = false,
): number {
    const targetKm = Math.max(targetDistance ?? directDistanceKm, directDistanceKm)
    const targetMultiplier = relaxed
        ? detourLevel === 1
            ? 1.40
            : detourLevel === 2
            ? 1.50
            : detourLevel >= 3
            ? 1.60
            : 1.22
        : detourLevel === 1
        ? 1.32
        : detourLevel === 2
        ? 1.42
        : detourLevel >= 3
        ? 1.52
        : 1.18
    const directMultiplier = relaxed
        ? detourLevel === 1
            ? 2.20
            : detourLevel === 2
            ? 3.00
            : detourLevel >= 3
            ? 3.60
            : 1.45
        : detourLevel === 1
        ? 2.05
        : detourLevel === 2
        ? 2.85
        : detourLevel >= 3
        ? 3.45
        : 1.35
    const slackKm = relaxed
        ? detourLevel === 1
            ? 5.0
            : detourLevel === 2
            ? 8.0
            : detourLevel >= 3
            ? 12.0
            : 3.0
        : detourLevel === 1
        ? 3.0
        : detourLevel === 2
        ? 6.0
        : detourLevel >= 3
        ? 10.0
        : 2.0
    const minimumDistanceKm = getPointToPointMinimumDistanceKm(
        directDistanceKm,
        targetDistance,
        detourLevel,
        relaxed,
    )

    return Math.max(
        minimumDistanceKm + slackKm,
        Math.max(targetKm * targetMultiplier, directDistanceKm * directMultiplier),
    )
}

function isPointToPointDetourAcceptable(
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
    )
    const maximumDistanceKm = getPointToPointMaximumDistanceKm(
        directDistanceKm,
        targetDistance,
        detourLevel,
        relaxed,
    )
    const distanceKm = getRouteDistanceKm(route)
    return distanceKm >= minimumDistanceKm && distanceKm <= maximumDistanceKm
}

/**
 * Scales a waypoint closer to the start location (center) by a given factor.
 * New = Start + (WP - Start) * factor
 */
function scaleWaypoint(start: Coordinate, wp: Coordinate, factor: number): Coordinate {
    return {
        latitude: start.latitude + (wp.latitude - start.latitude) * factor,
        longitude: start.longitude + (wp.longitude - start.longitude) * factor,
    }
}

/**
 * Calls Mapbox Directions API.
 */
async function getMapboxRouteDetailed(
    waypoints: Coordinate[],
    profile: string,
    exclude: string,
    radiuses: string,
    accessToken: string,
    options?: {
        continueStraight?: boolean
        maxAttempts?: number
        timeoutMs?: number
        retryDelayBaseMs?: number
    },
): Promise<MapboxRouteFetchResult> {
    // Format coordinates: "lon,lat;lon,lat;..."
    const coordinatesStr = waypoints
        .map(p => `${p.longitude},${p.latitude}`)
        .join(';')

    // Base URL
    // We use geometries=geojson to get the path geometry
    const continueStraight = options?.continueStraight ?? true
    let url = `https://api.mapbox.com/directions/v5/${profile}/${coordinatesStr}?access_token=${accessToken}&geometries=geojson&overview=full&steps=true&voice_instructions=true&banner_instructions=true&language=de&continue_straight=${continueStraight ? 'true' : 'false'}&annotations=maxspeed`

    // Append optional parameters if they exist
    if (exclude && exclude.trim() !== '') {
        url += `&exclude=${exclude}`
    }
    if (radiuses && radiuses.trim() !== '') {
        url += `&radiuses=${radiuses}`
    }

    const maxAttempts = Math.max(1, Math.min(4, options?.maxAttempts ?? MAX_MAPBOX_FETCH_ATTEMPTS))
    const timeoutMs = Math.max(4000, Math.min(22000, options?.timeoutMs ?? MAPBOX_FETCH_TIMEOUT_MS))
    const retryDelayBaseMs = Math.max(120, Math.min(800, options?.retryDelayBaseMs ?? 180))

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        const controller = new AbortController()
        const timeoutId = setTimeout(() => controller.abort(), timeoutMs)
        try {
            const res = await fetch(url, { signal: controller.signal })
            if (!res.ok) {
                const text = await res.text()
                const failure: MapboxRouteFetchResult = {
                    route: null,
                    outcome: 'http_error',
                    statusCode: res.status,
                    details: text,
                }
                const retryable = RETRYABLE_MAPBOX_STATUS_CODES.has(res.status)
                if (retryable && attempt < maxAttempts) {
                    console.warn(`Mapbox API retryable error (${res.status}), retry ${attempt + 1}/${maxAttempts}`)
                    await wait(retryDelayBaseMs * attempt)
                    continue
                }
                console.error(`Mapbox API Error (${res.status}): ${text}`)
                return failure
            }

            const data = await res.json()
            if (!data.routes || data.routes.length === 0) {
                return {
                    route: null,
                    outcome: 'no_route',
                    details: JSON.stringify(data).slice(0, 500),
                }
            }

            // Return the best route
            return {
                route: data.routes[0],
                outcome: 'ok',
            }
        } catch (error) {
            const details = error instanceof Error ? error.message : String(error)
            const isAbort =
                (error instanceof DOMException && error.name === 'AbortError') ||
                String(details).toLowerCase().includes('abort')
            const failure: MapboxRouteFetchResult = {
                route: null,
                outcome: isAbort ? 'timeout' : 'network_error',
                details,
            }
            if (attempt < maxAttempts) {
                console.warn(`Mapbox ${isAbort ? 'timeout' : 'network'} retry (${attempt + 1}/${maxAttempts}): ${details}`)
                await wait(retryDelayBaseMs * attempt)
                continue
            }
            console.error(`Mapbox fetch failed (${failure.outcome}): ${details}`)
            return failure
        } finally {
            clearTimeout(timeoutId)
        }
    }

    return {
        route: null,
        outcome: 'network_error',
        details: 'Mapbox fetch retry budget exhausted',
    }
}

async function getMapboxRoute(
    waypoints: Coordinate[],
    profile: string,
    exclude: string,
    radiuses: string,
    accessToken: string,
    options?: {
        continueStraight?: boolean
        maxAttempts?: number
        timeoutMs?: number
        retryDelayBaseMs?: number
    },
) {
    const result = await getMapboxRouteDetailed(
        waypoints,
        profile,
        exclude,
        radiuses,
        accessToken,
        options,
    )
    return result.route
}

/**
 * Prüft ob eine Route explizite Wendemanöver enthält.
 */
function hasUTurnManeuver(route: any): boolean {
    const legs = route?.legs
    if (!Array.isArray(legs)) return false

    for (const leg of legs) {
        const steps = leg?.steps
        if (!Array.isArray(steps)) continue

        for (const step of steps) {
            const maneuver = step?.maneuver ?? {}
            const modifier = String(maneuver?.modifier ?? '').toLowerCase()
            const type = String(maneuver?.type ?? '').toLowerCase()
            const instruction = String(maneuver?.instruction ?? '').toLowerCase()

            if (
                modifier.includes('uturn') ||
                modifier.includes('u-turn') ||
                type === 'uturn' ||
                type === 'u-turn' ||
                instruction.includes('wenden') ||
                instruction.includes('u-turn')
            ) {
                return true
            }
        }
    }
    return false
}

function headingDeltaDegrees(a: number, b: number): number {
    let delta = Math.abs((a - b) % 360)
    if (delta > 180) {
        delta = 360 - delta
    }
    return delta
}

function pointToCoordinate(point: any): Coordinate | null {
    if (!Array.isArray(point) || point.length < 2) return null
    const longitude = Number(point[0])
    const latitude = Number(point[1])
    if (!Number.isFinite(longitude) || !Number.isFinite(latitude)) {
        return null
    }
    return { latitude, longitude }
}

function routeHeadingAt(routeCoordinates: any[], index: number): number {
    if (!Array.isArray(routeCoordinates) || routeCoordinates.length < 2) {
        return 0
    }
    const safeIndex = Math.max(0, Math.min(index, routeCoordinates.length - 2))
    const from = pointToCoordinate(routeCoordinates[safeIndex])
    const to = pointToCoordinate(routeCoordinates[safeIndex + 1])
    if (!from || !to) return 0
    return calculateBearing(from, to)
}

function calculateRouteOverlapPercent(route: any): number {
    const coordinates = route?.geometry?.coordinates
    if (!Array.isArray(coordinates) || coordinates.length < 25) {
        return 0
    }

    const sampleStep = 4
    const minIndexGap = 30
    const overlapDistanceMeters = 45
    let sampleCount = 0
    let overlapCount = 0

    for (let i = 0; i < coordinates.length; i += sampleStep) {
        const current = pointToCoordinate(coordinates[i])
        if (!current) continue

        sampleCount += 1
        const headingI = routeHeadingAt(coordinates, i)
        let foundOverlap = false

        for (let j = i + minIndexGap; j < coordinates.length; j += sampleStep) {
            const candidate = pointToCoordinate(coordinates[j])
            if (!candidate) continue

            const distanceMeters = calculateDistance(current, candidate) * 1000
            if (distanceMeters >= overlapDistanceMeters) continue

            const headingJ = routeHeadingAt(coordinates, j)
            const headingDelta = headingDeltaDegrees(headingI, headingJ)
            const sameDirection = headingDelta <= 35
            const oppositeDirection = headingDelta >= 145

            if (sameDirection || oppositeDirection) {
                foundOverlap = true
                break
            }
        }

        if (foundOverlap) {
            overlapCount += 1
        }
    }

    if (sampleCount === 0) return 0
    return (overlapCount / sampleCount) * 100
}

function extractRouteCoordinates(route: any): Coordinate[] {
    const raw = route?.geometry?.coordinates
    if (!Array.isArray(raw)) return []
    const result: Coordinate[] = []
    for (const point of raw) {
        const parsed = pointToCoordinate(point)
        if (parsed) result.push(parsed)
    }
    return result
}

function calculateRouteShapeSignals(route: any): {
    angularRoughness: number
    sharpTurnRate: number
    hookCount: number
    centralReturnPercent: number
} {
    const coordinates = extractRouteCoordinates(route)
    if (coordinates.length < 12) {
        return {
            angularRoughness: 0,
            sharpTurnRate: 0,
            hookCount: 0,
            centralReturnPercent: 0,
        }
    }

    const sampleStep = 5
    const start = coordinates[0]
    const centralRadiusMeters = Math.max(140, Math.min(1300, (getRouteDistanceKm(route) * 1000) * 0.022))
    const centralStartIndex = Math.floor(coordinates.length * 0.14)
    const centralEndIndex = Math.ceil(coordinates.length * 0.84)

    let centralSamples = 0
    let centralHits = 0
    let totalTurnSamples = 0
    let turnDeltaSum = 0
    let sharpTurnCount = 0
    let hookCount = 0

    for (let i = sampleStep; i < coordinates.length - sampleStep; i += sampleStep) {
        const prev = coordinates[i - sampleStep]
        const current = coordinates[i]
        const next = coordinates[i + sampleStep]

        const headingIn = calculateBearing(prev, current)
        const headingOut = calculateBearing(current, next)
        const delta = headingDeltaDegrees(headingIn, headingOut)
        totalTurnSamples += 1
        turnDeltaSum += delta
        if (delta >= 78) sharpTurnCount += 1

        const segmentInKm = calculateDistance(prev, current)
        const segmentOutKm = calculateDistance(current, next)
        if (
            delta >= 132 &&
            segmentInKm <= 0.24 &&
            segmentOutKm <= 0.24
        ) {
            hookCount += 1
        }

        if (i >= centralStartIndex && i <= centralEndIndex) {
            centralSamples += 1
            const distanceToStartMeters = calculateDistance(start, current) * 1000
            if (distanceToStartMeters <= centralRadiusMeters) {
                centralHits += 1
            }
        }
    }

    const angularRoughness = totalTurnSamples > 0 ? turnDeltaSum / totalTurnSamples : 0
    const sharpTurnRate = totalTurnSamples > 0 ? (sharpTurnCount / totalTurnSamples) * 100 : 0
    const centralReturnPercent = centralSamples > 0 ? (centralHits / centralSamples) * 100 : 0

    return {
        angularRoughness,
        sharpTurnRate,
        hookCount,
        centralReturnPercent,
    }
}

function evaluateRouteQuality(
    route: any,
    routeType: 'ROUND_TRIP' | 'POINT_TO_POINT',
    options?: {
        targetDistanceKm?: number
        distanceConfig?: DistanceConfig
    },
): RouteQualityEvaluation {
    const coordinateCount = route?.geometry?.coordinates?.length ?? 0
    const actualDistanceKm = getRouteDistanceKm(route)
    const hasUTurn = hasUTurnManeuver(route)
    const overlapPercent = calculateRouteOverlapPercent(route)
    const overlapThreshold = routeType === 'ROUND_TRIP' ? 18 : 14
    const targetDistanceKm = options?.targetDistanceKm ?? 0
    const distanceConfig = options?.distanceConfig
    const distanceDeltaKm =
        targetDistanceKm > 0 ? Math.abs(actualDistanceKm - targetDistanceKm) : 0
    const shapeSignals = calculateRouteShapeSignals(route)
    const severeHookCount = routeType === 'ROUND_TRIP' ? 5 : 4
    const severeCentralReturn = routeType === 'ROUND_TRIP'
        ? shapeSignals.centralReturnPercent > 16
        : shapeSignals.centralReturnPercent > 11

    if (routeType !== 'ROUND_TRIP') {
        if (coordinateCount < 30 && actualDistanceKm > 10) {
            return {
                passed: false,
                reason: `coords=${coordinateCount}`,
                overlapPercent,
                hasUTurn,
                tier: 'reject',
                score: 1000 + Math.max(0, 30 - coordinateCount),
                coordinateCount,
                actualDistanceKm,
                distanceDeltaKm,
            }
        }
        if (hasUTurn) {
            return {
                passed: false,
                reason: 'u_turn',
                overlapPercent,
                hasUTurn,
                tier: 'reject',
                score: 1200,
                coordinateCount,
                actualDistanceKm,
                distanceDeltaKm,
            }
        }
        if (overlapPercent > overlapThreshold) {
            return {
                passed: false,
                reason: `overlap=${overlapPercent.toFixed(1)}%`,
                overlapPercent,
                hasUTurn,
                tier: 'reject',
                score: 1100 + overlapPercent,
                coordinateCount,
                actualDistanceKm,
                distanceDeltaKm,
            }
        }
        if (shapeSignals.hookCount >= severeHookCount) {
            return {
                passed: false,
                reason: `hooks=${shapeSignals.hookCount}`,
                overlapPercent,
                hasUTurn,
                tier: 'reject',
                score: 1040 + shapeSignals.hookCount * 20,
                coordinateCount,
                actualDistanceKm,
                distanceDeltaKm,
            }
        }

        return {
            passed: true,
            reason: 'ok',
            overlapPercent,
            hasUTurn,
            tier: 'ideal',
            score:
                overlapPercent +
                shapeSignals.angularRoughness * 0.22 +
                shapeSignals.sharpTurnRate * 0.65 +
                shapeSignals.hookCount * 7 +
                shapeSignals.centralReturnPercent * 0.45,
            coordinateCount,
            actualDistanceKm,
            distanceDeltaKm,
        }
    }

    const withinIdealDistance =
        !distanceConfig ||
        targetDistanceKm <= 0 ||
        (actualDistanceKm >= distanceConfig.minKm &&
            actualDistanceKm <= distanceConfig.maxKm)
    const withinAcceptableDistance =
        !distanceConfig ||
        targetDistanceKm <= 0 ||
        (actualDistanceKm >= distanceConfig.acceptableMinKm &&
            actualDistanceKm <= distanceConfig.acceptableMaxKm)
    const severeOverlap = overlapPercent > 52
    const acceptableOverlap = overlapPercent <= 36
    const idealOverlap = overlapPercent <= overlapThreshold
    const severeCoordinateThreshold =
        targetDistanceKm <= 60 ? 16 : targetDistanceKm <= 100 ? 18 : 22
    const weakGeometryThreshold =
        targetDistanceKm <= 60 ? 22 : targetDistanceKm <= 100 ? 26 : 30
    const severeCoordinateShortage =
        coordinateCount < severeCoordinateThreshold && actualDistanceKm > 8
    const weakGeometry =
        coordinateCount < weakGeometryThreshold && actualDistanceKm > 15

    if (hasUTurn) {
        return {
            passed: false,
            reason: 'u_turn',
            overlapPercent,
            hasUTurn,
            tier: 'reject',
            score: 1200,
            coordinateCount,
            actualDistanceKm,
            distanceDeltaKm,
        }
    }
    if (severeCoordinateShortage) {
        return {
            passed: false,
            reason: `coords=${coordinateCount}`,
            overlapPercent,
            hasUTurn,
            tier: 'reject',
            score: 900 + Math.max(0, severeCoordinateThreshold - coordinateCount) * 8,
            coordinateCount,
            actualDistanceKm,
            distanceDeltaKm,
        }
    }
    if (severeOverlap) {
        return {
            passed: false,
            reason: `overlap=${overlapPercent.toFixed(1)}%`,
            overlapPercent,
            hasUTurn,
            tier: 'reject',
            score: 900 + overlapPercent * 6,
            coordinateCount,
            actualDistanceKm,
            distanceDeltaKm,
        }
    }
    if (shapeSignals.hookCount >= severeHookCount) {
        return {
            passed: false,
            reason: `hooks=${shapeSignals.hookCount}`,
            overlapPercent,
            hasUTurn,
            tier: 'reject',
            score: 900 + shapeSignals.hookCount * 24,
            coordinateCount,
            actualDistanceKm,
            distanceDeltaKm,
        }
    }
    if (severeCentralReturn) {
        return {
            passed: false,
            reason: `center_return=${shapeSignals.centralReturnPercent.toFixed(1)}%`,
            overlapPercent,
            hasUTurn,
            tier: 'reject',
            score: 920 + shapeSignals.centralReturnPercent * 8,
            coordinateCount,
            actualDistanceKm,
            distanceDeltaKm,
        }
    }

    let tier: RouteQualityTier = 'fallback'
    if (
        withinIdealDistance &&
        idealOverlap &&
        coordinateCount >= 38 &&
        shapeSignals.angularRoughness <= 62 &&
        shapeSignals.sharpTurnRate <= 34 &&
        shapeSignals.centralReturnPercent <= 9 &&
        shapeSignals.hookCount <= 1
    ) {
        tier = 'ideal'
    } else if (
        withinAcceptableDistance &&
        acceptableOverlap &&
        !weakGeometry &&
        shapeSignals.angularRoughness <= 74 &&
        shapeSignals.sharpTurnRate <= 44 &&
        shapeSignals.centralReturnPercent <= 13 &&
        shapeSignals.hookCount <= 3
    ) {
        tier = 'acceptable'
    }

    const score =
        distanceDeltaKm * 7 +
        overlapPercent * 3 +
        shapeSignals.angularRoughness * 0.85 +
        shapeSignals.sharpTurnRate * 1.7 +
        shapeSignals.hookCount * 18 +
        shapeSignals.centralReturnPercent * 3.4 +
        (tier === 'ideal' ? 0 : tier === 'acceptable' ? 24 : 60) +
        (withinAcceptableDistance ? 0 : 45) +
        Math.max(0, 34 - coordinateCount) * 2

    return {
        passed: true,
        reason:
            tier === 'ideal'
                ? 'ideal'
                : tier === 'acceptable'
                ? 'acceptable'
                : `fallback(dist=${actualDistanceKm.toFixed(1)}km, overlap=${overlapPercent.toFixed(1)}%, rough=${shapeSignals.angularRoughness.toFixed(1)}, center=${shapeSignals.centralReturnPercent.toFixed(1)}%)`,
        overlapPercent,
        hasUTurn,
        tier,
        score,
        coordinateCount,
        actualDistanceKm,
        distanceDeltaKm,
    }
}

function widenDistanceConfigForRoundTripSearch(
    base: DistanceConfig,
    targetDistanceKm: number,
    phase: 'balanced' | 'fallback',
): DistanceConfig {
    const minFactor = phase === 'fallback' ? 0.70 : 0.76
    const maxFactor = phase === 'fallback' ? 1.34 : 1.24
    const radiusMultiplier = phase === 'fallback' ? 1.20 : 1.10
    const snapMultiplier = phase === 'fallback' ? 1.32 : 1.18

    return {
        radiusKm: base.radiusKm * radiusMultiplier,
        minKm: base.minKm,
        maxKm: base.maxKm,
        acceptableMinKm: Math.min(base.acceptableMinKm, Math.round(targetDistanceKm * minFactor)),
        acceptableMaxKm: Math.max(base.acceptableMaxKm, Math.round(targetDistanceKm * maxFactor)),
        waypointRadiusMeters: Math.round(base.waypointRadiusMeters * snapMultiplier),
    }
}

function normalizeRoundTripRejectReason(reason: string): string {
    if (reason.startsWith('coords=')) return 'coords'
    if (reason.startsWith('overlap=')) return 'overlap'
    if (reason.startsWith('hooks=')) return 'hooks'
    if (reason.startsWith('center_return=')) return 'center_return'
    if (reason.startsWith('mapbox_http_')) return 'mapbox_http'
    if (reason.startsWith('mapbox_')) return reason
    if (reason.includes('u_turn')) return 'u_turn'
    if (reason.includes('fallback')) return 'fallback'
    return reason
}

async function searchBestRoundTripRoute({
    startLocation,
    targetDistanceKm,
    distanceConfig,
    mode,
    randomSeed,
    directionHintDegrees,
    waypointShapeFactor,
    radiusMultiplier,
    zigzagWaypoints,
    mapboxProfile,
    excludeParams,
    accessToken,
    variantHint,
    fingerprintHint,
    maxCandidateAttemptsHint,
}: {
    startLocation: Coordinate
    targetDistanceKm: number
    distanceConfig: DistanceConfig
    mode?: RouteMode
    randomSeed: number
    directionHintDegrees?: number
    waypointShapeFactor?: number
    radiusMultiplier?: number
    zigzagWaypoints?: boolean
    mapboxProfile: string
    excludeParams: string
    accessToken: string
    variantHint?: string
    fingerprintHint?: string
    maxCandidateAttemptsHint?: number
}): Promise<RoundTripSearchResult | null> {
    const highCostCurveSearch = mode === 'Kurvenjagd' && targetDistanceKm >= 130
    const normalizedVariantHint = normalizeHint(variantHint)
    const normalizedFingerprintHint = normalizeHint(fingerprintHint)
    const globalAttemptBudget = Math.max(
        highCostCurveSearch ? 4 : 5,
        Math.min(
            highCostCurveSearch ? 7 : 10,
            Math.round(maxCandidateAttemptsHint ?? (highCostCurveSearch ? 7 : 9)),
        ),
    )
    const searchStartTs = Date.now()
    const roundTripTimeBudgetMs = highCostCurveSearch ? 16000 : 19000

    const searchPhases = [
        {
            name: 'strict',
            distanceConfig,
            seedOffset: 0,
            continueStraight: true,
            exclude: excludeParams,
        },
        {
            name: 'balanced',
            distanceConfig: widenDistanceConfigForRoundTripSearch(
                distanceConfig,
                targetDistanceKm,
                'balanced',
            ),
            seedOffset: 911,
            continueStraight: false,
            exclude: excludeParams,
        },
        {
            name: 'fallback',
            distanceConfig: widenDistanceConfigForRoundTripSearch(
                distanceConfig,
                targetDistanceKm,
                'fallback',
            ),
            seedOffset: 1777,
            continueStraight: false,
            exclude: '',
        },
    ].filter((phase) => !(highCostCurveSearch && phase.name === 'fallback'))

    let candidateAttempts = 0
    let acceptedCandidates = 0
    let rejectedCandidates = 0
    let bestPlan: RoundTripCandidatePlan | null = null
    let bestRoute: any = null
    let bestQuality: RouteQualityEvaluation | null = null
    const rejectReasons = new Map<string, number>()
    let rateLimitHits = 0
    let timeoutHits = 0

    const registerReject = (reason: string) => {
        const normalized = normalizeRoundTripRejectReason(reason)
        rejectReasons.set(normalized, (rejectReasons.get(normalized) ?? 0) + 1)
    }

    for (const phase of searchPhases) {
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
            }),
            phase.name,
            normalizedVariantHint,
            normalizedFingerprintHint,
        )
        const maxPhaseAttempts =
            highCostCurveSearch
                ? phase.name === 'strict'
                    ? 2
                    : 1
                : phase.name === 'strict'
                ? 4
                : phase.name === 'balanced'
                ? 2
                : 1
        const candidatePlans = orderedCandidates.slice(0, Math.min(orderedCandidates.length, maxPhaseAttempts + 1))
        let phaseAttempts = 0
        let phaseAcceptedCandidates = 0

        console.log(
            `[RT] Phase ${phase.name}: candidates=${candidatePlans.length}, radius=${phase.distanceConfig.radiusKm.toFixed(1)}km, ` +
            `snap=${phase.distanceConfig.waypointRadiusMeters}m, exclude=${phase.exclude || 'none'}, continueStraight=${phase.continueStraight}`,
        )

        for (const plan of candidatePlans) {
            if (
                phaseAttempts >= maxPhaseAttempts ||
                candidateAttempts >= globalAttemptBudget ||
                Date.now() - searchStartTs >= roundTripTimeBudgetMs
            ) {
                console.log(
                    `[RT] Phase ${phase.name}: stopping early after ${phaseAttempts} attempts (global=${candidateAttempts})`,
                )
                break
            }

            phaseAttempts += 1
            candidateAttempts += 1
            console.log(
                `[RT] Candidate ${candidateAttempts}: ${phase.name}/${plan.label} (${plan.waypoints.length - 2} WPs)`,
            )

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
            )
            const primaryFailureKind = getRetryKindFromMapboxFailure(fetchResult)
            if (primaryFailureKind === 'rate_limit') rateLimitHits += 1
            if (primaryFailureKind === 'timeout') timeoutHits += 1

            if (rateLimitHits >= 2) {
                throw new Error('Routing provider rate limit reached during round-trip search.')
            }
            if (timeoutHits >= 3) {
                throw new Error('Routing provider timeout during round-trip search.')
            }

            if (
                fetchResult.outcome === 'no_route' &&
                phase.exclude &&
                phase.exclude.trim() !== ''
            ) {
                console.log(`[RT] ${plan.label}: retry without excludes`)
                const relaxedFetch = await getMapboxRouteDetailed(
                    plan.waypoints,
                    mapboxProfile,
                    '',
                    plan.radiuses,
                    accessToken,
                    {
                        continueStraight: phase.continueStraight,
                        maxAttempts: 1,
                        timeoutMs: 10500,
                    },
                )
                const relaxedFailureKind = getRetryKindFromMapboxFailure(relaxedFetch)
                if (relaxedFailureKind === 'rate_limit') rateLimitHits += 1
                if (relaxedFailureKind === 'timeout') timeoutHits += 1
                if (rateLimitHits >= 2) {
                    throw new Error('Routing provider rate limit reached during round-trip search.')
                }
                if (timeoutHits >= 3) {
                    throw new Error('Routing provider timeout during round-trip search.')
                }
                if (relaxedFetch.outcome === 'ok') {
                    fetchResult = relaxedFetch
                }
            }

            if (!fetchResult.route) {
                rejectedCandidates += 1
                const reason = fetchResult.outcome === 'http_error'
                    ? `mapbox_http_${fetchResult.statusCode ?? 'unknown'}`
                    : `mapbox_${fetchResult.outcome}`
                registerReject(reason)
                console.log(
                    `[RT] ${phase.name}/${plan.label}: ${reason}${fetchResult.details ? ` (${fetchResult.details.slice(0, 160)})` : ''}`,
                )
                continue
            }

            let route = fetchResult.route
            let quality = evaluateRouteQuality(route, 'ROUND_TRIP', {
                targetDistanceKm,
                distanceConfig: phase.distanceConfig,
            })

            if (
                quality.tier === 'reject' &&
                phase.exclude &&
                phase.exclude.trim() !== '' &&
                quality.reason.startsWith('overlap=') &&
                rateLimitHits === 0 &&
                timeoutHits < 2
            ) {
                console.log(`[RT] ${plan.label}: rejected with excludes, trying relaxed street filter`)
                const relaxedFetch = await getMapboxRouteDetailed(
                    plan.waypoints,
                    mapboxProfile,
                    '',
                    plan.radiuses,
                    accessToken,
                    {
                        continueStraight: phase.continueStraight,
                        maxAttempts: 1,
                        timeoutMs: 10500,
                    },
                )
                const relaxedFailureKind = getRetryKindFromMapboxFailure(relaxedFetch)
                if (relaxedFailureKind === 'rate_limit') rateLimitHits += 1
                if (relaxedFailureKind === 'timeout') timeoutHits += 1
                if (rateLimitHits >= 2) {
                    throw new Error('Routing provider rate limit reached during round-trip search.')
                }
                if (timeoutHits >= 3) {
                    throw new Error('Routing provider timeout during round-trip search.')
                }
                if (relaxedFetch.route) {
                    const relaxedQuality = evaluateRouteQuality(relaxedFetch.route, 'ROUND_TRIP', {
                        targetDistanceKm,
                        distanceConfig: phase.distanceConfig,
                    })
                    console.log(
                        `[RT] ${plan.label}: relaxed tier=${relaxedQuality.tier}, score=${relaxedQuality.score.toFixed(1)}, ` +
                        `distance=${relaxedQuality.actualDistanceKm.toFixed(1)}km, overlap=${relaxedQuality.overlapPercent.toFixed(1)}%, coords=${relaxedQuality.coordinateCount}`,
                    )
                    if (relaxedQuality.tier !== 'reject' || relaxedQuality.score < quality.score) {
                        route = relaxedFetch.route
                        quality = relaxedQuality
                    }
                }
            }

            console.log(
                `[RT] ${phase.name}/${plan.label}: tier=${quality.tier}, score=${quality.score.toFixed(1)}, ` +
                `distance=${quality.actualDistanceKm.toFixed(1)}km, overlap=${quality.overlapPercent.toFixed(1)}%, coords=${quality.coordinateCount}`,
            )

            if (quality.tier === 'reject') {
                rejectedCandidates += 1
                registerReject(quality.reason)
                continue
            }

            acceptedCandidates += 1
            phaseAcceptedCandidates += 1
            if (!bestQuality || quality.score < bestQuality.score) {
                bestPlan = plan
                bestRoute = route
                bestQuality = quality
            }

            const shouldStopAfterGoodCandidate =
                candidateAttempts >= (highCostCurveSearch ? 3 : 4) &&
                (
                    quality.tier === 'ideal' ||
                    (quality.tier === 'acceptable' && phaseAcceptedCandidates >= 1) ||
                    (phase.name === 'fallback' && phaseAcceptedCandidates >= 1)
                )

            if (shouldStopAfterGoodCandidate) {
                console.log(
                    `[RT] Phase ${phase.name}: good candidate found, stopping early after ${phaseAttempts} attempts`,
                )
                break
            }
        }

        if (
            candidateAttempts >= globalAttemptBudget ||
            Date.now() - searchStartTs >= roundTripTimeBudgetMs
        ) {
            break
        }
        if (bestQuality?.tier === 'ideal') {
            break
        }
        if (
            phaseAcceptedCandidates > 0 &&
            (bestQuality?.tier === 'acceptable' || phase.name === 'fallback')
        ) {
            break
        }
    }

    if (!bestPlan || !bestRoute || !bestQuality) {
        console.log(
            `[RT] Search exhausted: ${candidateAttempts} candidates, none usable. Reject summary=${JSON.stringify(Object.fromEntries(rejectReasons))}`,
        )
        return null
    }

    console.log(
        `[RT] Selected ${bestPlan.label}: tier=${bestQuality.tier}, score=${bestQuality.score.toFixed(1)}, ` +
        `attempts=${candidateAttempts}, accepted=${acceptedCandidates}, rejected=${rejectedCandidates}, rejects=${JSON.stringify(Object.fromEntries(rejectReasons))}`,
    )

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
    }
}

function classifyRoutingError(message: string): {
    status: number
    code: 'INVALID_REQUEST' | 'NO_ROUTE' | 'UNAUTHORIZED' | 'RATE_LIMIT' | 'TIMEOUT' | 'WORKER_LIMIT' | 'INTERNAL_ERROR'
    retryable: boolean
    retryAfterSec?: number
} {
    const lower = message.toLowerCase()
    if (
        lower.includes('invalid') ||
        lower.includes('missing') ||
        lower.includes('out of bounds') ||
        lower.includes('required')
    ) {
        return { status: 422, code: 'INVALID_REQUEST', retryable: false }
    }
    if (lower.includes('no route found') || lower.includes('keine route')) {
        return { status: 404, code: 'NO_ROUTE', retryable: false }
    }
    if (lower.includes('unauthorized') || lower.includes('forbidden') || lower.includes('jwt')) {
        return { status: 401, code: 'UNAUTHORIZED', retryable: false }
    }
    if (
        lower.includes('worker limit') ||
        lower.includes('cpu time limit') ||
        lower.includes('memory limit') ||
        lower.includes('wall clock') ||
        lower.includes('resource limit')
    ) {
        return { status: 503, code: 'WORKER_LIMIT', retryable: true, retryAfterSec: 2 }
    }
    if (lower.includes('rate limit') || lower.includes('too many requests') || lower.includes('mapbox_http_429')) {
        return { status: 429, code: 'RATE_LIMIT', retryable: true, retryAfterSec: 8 }
    }
    if (
        lower.includes('timeout') ||
        lower.includes('timed out') ||
        lower.includes('aborterror') ||
        lower.includes('mapbox_timeout')
    ) {
        return { status: 504, code: 'TIMEOUT', retryable: true, retryAfterSec: 5 }
    }
    return { status: 500, code: 'INTERNAL_ERROR', retryable: false }
}

Deno.serve(async (req) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: getCorsHeaders(req) })
    }

    try {
        // 1. Parse Request
        const body = await req.json() as RequestData
        const { planning_type, startLocation, targetDistance, manual_waypoints, mode } = body
        const directionHint =
            typeof body.direction_hint === 'number' && Number.isFinite(body.direction_hint)
                ? normalizeBearingDegrees(Math.round(body.direction_hint))
                : undefined
        const offsetSide =
            body.offset_side === -1 || body.offset_side === 1 ? body.offset_side : undefined
        const waypointShapeFactor =
            typeof body.waypoint_shape_factor === 'number' && Number.isFinite(body.waypoint_shape_factor)
                ? body.waypoint_shape_factor
                : undefined
        const radiusMultiplier =
            typeof body.radius_multiplier === 'number' && Number.isFinite(body.radius_multiplier)
                ? body.radius_multiplier
                : undefined
        const zigzagWaypoints = body.zigzag_waypoints === true
        const variantHint = normalizeHint(
            body.route_variant_hint ?? body.variant_hint ?? body.style_profile,
        )
        const fingerprintHint = normalizeHint(body.route_fingerprint_hint ?? body.fingerprint_hint)
        const maxCandidateAttemptsHint =
            typeof body.max_candidate_attempts === 'number' && Number.isFinite(body.max_candidate_attempts)
                ? body.max_candidate_attempts
                : undefined
        const hintSeedOffset =
            stableStringHash(`${variantHint ?? ''}|${fingerprintHint ?? ''}`) % 9973
        console.log(
            '[RoutingRequest]',
            JSON.stringify({
                planningType: planning_type,
                routeType: body.route_type ?? 'ROUND_TRIP',
                mode: mode ?? 'Standard',
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
        )

        if (!MAPBOX_ACCESS_TOKEN) {
            throw new Error("Server Error: MAPBOX_ACCESS_TOKEN is not configured.")
        }

        // Basic validation
        if (!startLocation) {
                throw new Error("Missing startLocation")
        }

        // Coordinate validation helper
        const isValidCoord = (c: Coordinate): boolean =>
            c != null &&
            typeof c.latitude === 'number' && typeof c.longitude === 'number' &&
            !isNaN(c.latitude) && !isNaN(c.longitude) &&
            c.latitude >= -90 && c.latitude <= 90 &&
            c.longitude >= -180 && c.longitude <= 180;

        if (!isValidCoord(startLocation)) {
            throw new Error("Invalid startLocation: coordinates out of bounds or not a number")
        }
        if (body.destination_location && !isValidCoord(body.destination_location)) {
            throw new Error("Invalid destination_location: coordinates out of bounds or not a number")
        }
        if (manual_waypoints) {
            for (let i = 0; i < manual_waypoints.length; i++) {
                if (!isValidCoord(manual_waypoints[i])) {
                    throw new Error(`Invalid waypoint at index ${i}: coordinates out of bounds or not a number`)
                }
            }
        }
        if (targetDistance != null && (typeof targetDistance !== 'number' || isNaN(targetDistance) || targetDistance <= 0 || targetDistance > 500)) {
            throw new Error("Invalid targetDistance: must be a number between 1 and 500")
        }
        if (body.direction_hint != null && (typeof body.direction_hint !== 'number' || !Number.isFinite(body.direction_hint))) {
            throw new Error("Invalid direction_hint: must be a finite number")
        }
        if (body.offset_side != null && body.offset_side !== -1 && body.offset_side !== 1) {
            throw new Error("Invalid offset_side: must be -1 or 1")
        }
        if (body.waypoint_shape_factor != null && (typeof body.waypoint_shape_factor !== 'number' || !Number.isFinite(body.waypoint_shape_factor))) {
            throw new Error("Invalid waypoint_shape_factor: must be a finite number")
        }
        if (body.radius_multiplier != null && (typeof body.radius_multiplier !== 'number' || !Number.isFinite(body.radius_multiplier))) {
            throw new Error("Invalid radius_multiplier: must be a finite number")
        }
        if (body.max_candidate_attempts != null && (typeof body.max_candidate_attempts !== 'number' || !Number.isFinite(body.max_candidate_attempts))) {
            throw new Error("Invalid max_candidate_attempts: must be a finite number")
        }

        const avoidHighways = body.avoid_highways === true
        const requestContinueStraight = body.continue_straight !== false
        const randomSeed = (body.randomSeed ?? Math.floor(Math.random() * 100000)) + hintSeedOffset

        // --- 2. Fahrstil-Parameter (Mapbox) ---
        // Jeder Stil nutzt unterschiedliche Mapbox-Profile und Exclude-Parameter.
        // Da Mapbox kein "prefer" unterstützt, erzwingen wir Straßentypen durch
        // Excludes + stilspezifische Waypoint-Platzierung (siehe Subtask 2).
        let mapboxProfile = 'mapbox/driving';
        let excludeParams = '';
        let radiusesParams = '';

        if (mode === 'Kurvenjagd') {
                // Bergstraßen & enge Kurven: Autobahn + Maut + Fähre ausschließen
                // → zwingt Mapbox auf secondary/tertiary Landstraßen
                mapboxProfile = 'mapbox/driving';
                excludeParams = 'motorway,toll,ferry';
        } else if (mode === 'Sport Mode') {
                // Schnelle Landstraßen mit breiten Kurven: nur Autobahn + Fähre vermeiden
                // → Mapbox bevorzugt primary/secondary (schnellste Nicht-Autobahn-Route)
                mapboxProfile = 'mapbox/driving';
                excludeParams = 'motorway,ferry';
        } else if (mode === 'Abendrunde') {
                // Ruhige Nebenstraßen: Autobahn + Schnellstraßen + unbefestigt vermeiden
                // → driving-traffic bevorzugt beleuchtete, befahrene Straßen
                mapboxProfile = 'mapbox/driving-traffic';
                excludeParams = 'motorway,trunk,ferry,unpaved';
        } else if (mode === 'Entdecker') {
                // Abgelegene Strecken: nur Autobahn + Maut vermeiden, alles andere erlaubt
                // → lässt auch unpaved/unclassified zu für echte Entdecker-Routen
                mapboxProfile = 'mapbox/driving';
                excludeParams = 'motorway,toll';
        } else {
                // Standard: minimal eingeschränkt
                mapboxProfile = 'mapbox/driving';
                excludeParams = 'ferry';
        }

        // --- 3. Flexible Planung ---
        let finalWaypoints: Coordinate[] = []
        let distanceConfig: DistanceConfig | null = null
        let effectiveTargetDistanceKm: number | null = null
        let pointToPointIsScenic = false
        let pointToPointDirectDistanceKm = 0
        // Default to ROUND_TRIP if not specified, for backward compatibility or default 'Zufall' behavior
        const currentRouteType = body.route_type || 'ROUND_TRIP';
        const detourLevel = Math.max(0, Math.min(3, body.detour_level ?? 0))

        if (planning_type === 'Zufall' && currentRouteType === 'ROUND_TRIP') {
            if (mode === 'Kurvenjagd') {
                excludeParams = 'motorway,ferry'
            } else if (mode === 'Abendrunde') {
                mapboxProfile = 'mapbox/driving'
                excludeParams = 'motorway,ferry'
            } else if (mode === 'Entdecker') {
                excludeParams = 'motorway'
            }
        }

        if (planning_type === 'Zufall') {
                if (currentRouteType === 'POINT_TO_POINT') {
                          // A→B: direkte Straßenroute, optional ohne Autobahnen.
                          mapboxProfile = 'mapbox/driving';
                          excludeParams = avoidHighways ? 'motorway,motorway_link,trunk' : '';
                          if (!body.destination_location) {
                                  throw new Error("For 'POINT_TO_POINT' planning, a destination_location is required.")
                          }
                          pointToPointDirectDistanceKm = calculateDistance(startLocation, body.destination_location)
                          pointToPointIsScenic =
                              detourLevel > 0 ||
                              (mode != null && mode !== 'Standard') ||
                              (targetDistance != null && targetDistance > pointToPointDirectDistanceKm * 1.05)

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
                              ? Math.min(15000, Math.max(6500, Math.round(pointToPointDirectDistanceKm * 320)))
                              : detourLevel === 2
                              ? Math.min(12000, Math.max(5400, Math.round(pointToPointDirectDistanceKm * 260)))
                              : detourLevel === 1
                              ? Math.min(9000, Math.max(4200, Math.round(pointToPointDirectDistanceKm * 220)))
                              : 6000
                          const scenicRadius = `${scenicRadiusMeters}`
                          radiusesParams = finalWaypoints
                              .map((_, i) => (i === 0 || i === finalWaypoints.length - 1) ? 'unlimited' : scenicRadius)
                              .join(';');
                } else {
                        // ROUND_TRIP logic
                        if (!targetDistance) {
                                throw new Error("For 'Zufall' planning, a targetDistance is required.")
                        }

                        // >100 km is capped to 150 km maximum route target
                        const effectiveDistance = Math.min(targetDistance, 150);
                        distanceConfig = getDistanceConfig(effectiveDistance, mode)
                        effectiveTargetDistanceKm = effectiveDistance
                }

        } else if (planning_type === 'Wegpunkte') {
                if (!manual_waypoints || manual_waypoints.length < 3) {
                          throw new Error("For 'Wegpunkte', provide at least 3 points (including start/end implies a loop or A->B->C).")
                }
                finalWaypoints = manual_waypoints;
        } else {
                throw new Error("Invalid planning_type. Must be 'Zufall' or 'Wegpunkte'.")
        }

        // Radiuses: Start/Ende unlimited (echte GPS-Position), Zwischenpunkte max 1000m
        // Kleiner Radius = Waypoints müssen nahe einer Straße liegen → verhindert "Abkürzungen"
        // durch Gelände wo keine Straße existiert
        if (!radiusesParams && finalWaypoints.length > 0) {
            radiusesParams = finalWaypoints
                .map((_, i) => (i === 0 || i === finalWaypoints.length - 1) ? 'unlimited' : '1000')
                .join(';');
        }

        // --- Execute Route Request (with retries) ---
        let route = null;
        let roundTripSearch: RoundTripSearchResult | null = null
        const useRoundTripSearch =
            planning_type === 'Zufall' &&
            currentRouteType === 'ROUND_TRIP' &&
            distanceConfig != null &&
            targetDistance != null;

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
            });
            if (roundTripSearch) {
                route = roundTripSearch.route;
                finalWaypoints = roundTripSearch.waypoints;
                radiusesParams = roundTripSearch.radiuses;
                console.log(
                    `[RT] Search summary: attempts=${roundTripSearch.candidateAttempts}, accepted=${roundTripSearch.acceptedCandidates}, rejected=${roundTripSearch.rejectedCandidates}, chosen=${roundTripSearch.quality.tier}`,
                );
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
                    timeoutMs: pointToPointIsScenic ? 12000 : 10000,
                    retryDelayBaseMs: 220,
                },
            );

            if (!route && excludeParams && excludeParams.trim() !== '') {
                console.log(`No route with excludes "${excludeParams}", retrying without...`);
                route = await getMapboxRoute(
                    finalWaypoints,
                    mapboxProfile,
                    '',
                    radiusesParams,
                    MAPBOX_ACCESS_TOKEN,
                    {
                        continueStraight: requestContinueStraight,
                        maxAttempts: 1,
                        timeoutMs: 9500,
                    },
                );
            }

            if (route) {
                const initialQuality = evaluateRouteQuality(route, currentRouteType)
                if (!initialQuality.passed) {
                    console.log(`Initial route rejected: ${initialQuality.reason}`);
                    route = null
                }
            }

            if (
                route &&
                planning_type === 'Zufall' &&
                currentRouteType === 'POINT_TO_POINT' &&
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
                const routeDistanceKm = getRouteDistanceKm(route)
                const minimumDistanceKm = getPointToPointMinimumDistanceKm(
                    pointToPointDirectDistanceKm,
                    targetDistance,
                    detourLevel,
                    body.simplify_waypoints === true,
                )
                const maximumDistanceKm = getPointToPointMaximumDistanceKm(
                    pointToPointDirectDistanceKm,
                    targetDistance,
                    detourLevel,
                    body.simplify_waypoints === true,
                )
                console.log(
                    `Initial P2P scenic route rejected: ${routeDistanceKm.toFixed(1)}km outside ${minimumDistanceKm.toFixed(1)}-${maximumDistanceKm.toFixed(1)}km`,
                )
                route = null
            }
        }

        if (!route && planning_type === 'Zufall' && currentRouteType === 'POINT_TO_POINT' && body.destination_location && pointToPointIsScenic) {
            const scenicRetryCount = body.simplify_waypoints === true ? 3 : 2
            for (let retry = 0; retry < scenicRetryCount && !route; retry++) {
                console.log(`P2P scenic retry ${retry + 1}: regenerating waypoints...`);
                const retryDetourLevel = Math.max(
                    retry === 0
                        ? detourLevel
                        : retry === 1
                        ? detourLevel - 1
                        : 1,
                    1,
                )
                const retrySimplifyWaypoints = body.simplify_waypoints === true || retry > 0
                const retryMaxWaypoints = retrySimplifyWaypoints
                    ? Math.max(
                        1,
                        Math.min(
                            3,
                            retry >= 2
                                ? 1
                                : body.max_waypoints ?? (retryDetourLevel >= 3 ? 2 : 1),
                        ),
                    )
                    : undefined
                const retryOffsetSide =
                    offsetSide == null
                        ? undefined
                        : retry % 2 === 0
                        ? offsetSide
                        : -offsetSide
                const softenedTarget = targetDistance != null
                    ? Math.max(
                        pointToPointDirectDistanceKm *
                            (retry >= 2 ? 1.10 : retrySimplifyWaypoints ? 1.14 : 1.22),
                        targetDistance *
                            (retry >= 2 ? 0.82 : retrySimplifyWaypoints ? 0.88 : 0.95),
                    )
                    : undefined
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
                })
                const retryRadiusMeters = retryDetourLevel >= 3
                    ? Math.min(15500, Math.max(7000, Math.round(pointToPointDirectDistanceKm * 330)))
                    : retryDetourLevel === 2
                    ? Math.min(12500, Math.max(5600, Math.round(pointToPointDirectDistanceKm * 270)))
                    : retryDetourLevel === 1
                    ? Math.min(9500, Math.max(4400, Math.round(pointToPointDirectDistanceKm * 230)))
                    : 7000
                const retryRadius = `${retryRadiusMeters}`
                const retryRadiuses = retryWaypoints
                    .map((_, i) => (i === 0 || i === retryWaypoints.length - 1) ? 'unlimited' : retryRadius)
                    .join(';')

                route = await getMapboxRoute(
                    retryWaypoints,
                    mapboxProfile,
                    excludeParams,
                    retryRadiuses,
                    MAPBOX_ACCESS_TOKEN,
                    {
                        continueStraight: requestContinueStraight,
                        maxAttempts: 1,
                        timeoutMs: 10500,
                    },
                );
                if (!route && excludeParams && excludeParams.trim() !== '') {
                    route = await getMapboxRoute(
                        retryWaypoints,
                        mapboxProfile,
                        '',
                        retryRadiuses,
                        MAPBOX_ACCESS_TOKEN,
                        {
                            continueStraight: requestContinueStraight,
                            maxAttempts: 1,
                            timeoutMs: 9500,
                        },
                    );
                }
                if (route) {
                    const retryQuality = evaluateRouteQuality(route, currentRouteType)
                    if (!retryQuality.passed) {
                        console.log(`P2P scenic retry ${retry + 1}: route rejected because of ${retryQuality.reason}`);
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
                        const routeDistanceKm = getRouteDistanceKm(route)
                        const minimumDistanceKm = getPointToPointMinimumDistanceKm(
                            pointToPointDirectDistanceKm,
                            softenedTarget ?? targetDistance,
                            retryDetourLevel,
                            retrySimplifyWaypoints,
                        )
                        const maximumDistanceKm = getPointToPointMaximumDistanceKm(
                            pointToPointDirectDistanceKm,
                            softenedTarget ?? targetDistance,
                            retryDetourLevel,
                            retrySimplifyWaypoints,
                        )
                        console.log(
                            `P2P scenic retry ${retry + 1}: route rejected because ${routeDistanceKm.toFixed(1)}km is outside ${minimumDistanceKm.toFixed(1)}-${maximumDistanceKm.toFixed(1)}km`,
                        )
                        route = null
                        continue
                    }
                    finalWaypoints = retryWaypoints;
                    radiusesParams = retryRadiuses;
                }
            }
        }

        if (
            !route &&
            planning_type === 'Zufall' &&
            currentRouteType === 'POINT_TO_POINT' &&
            body.destination_location &&
            !pointToPointIsScenic
        ) {
            console.log('P2P scenic fallback: using direct A->B route');
            const fallbackWaypoints = [startLocation, body.destination_location];
            const fallbackRadiuses = 'unlimited;unlimited';
            route = await getMapboxRoute(
                fallbackWaypoints,
                mapboxProfile,
                '',
                fallbackRadiuses,
                MAPBOX_ACCESS_TOKEN,
                {
                    continueStraight: requestContinueStraight,
                    maxAttempts: 1,
                    timeoutMs: 9000,
                },
            );
            if (route) {
                finalWaypoints = fallbackWaypoints;
                radiusesParams = fallbackRadiuses;
            }
        }

        if (!route) {
            throw new Error(
                useRoundTripSearch
                    ? "No route found with current constraints after exhausting round-trip search."
                    : "No route found with current constraints.",
            );
        }

        // Mapbox returns distance in meters -> convert to kilometers for app output.
        let actualDistanceKm = (route.distance as number) / 1000;

        // --- 4. Distance Band Retry & Scaling ---
        // Skaliert Waypoints näher/weiter zum Start bis die Route im ±10% Band liegt.
        // Aggressive Korrektur bei großem Fehler, sanfter bei Annäherung.
        if (
            planning_type === 'Zufall' &&
            currentRouteType === 'ROUND_TRIP' &&
            distanceConfig
        ) {
            let attempts = 0
            const maxAttempts = 8 // Mehr Versuche für bessere Konvergenz
            while (
                attempts < maxAttempts &&
                (actualDistanceKm > distanceConfig.maxKm || actualDistanceKm < distanceConfig.minKm)
            ) {
                const ratio = (effectiveTargetDistanceKm ?? targetDistance!) / actualDistanceKm;
                // Aggressiver korrigieren bei großem Fehler, sanfter bei Annäherung
                // > 2x oder < 0.5x → 85% Korrektur (fast direkt)
                // 1.3x-2x → 70% Korrektur
                // < 1.3x → 50% Korrektur (Feintuning, verhindert Oszillation)
                const errorMagnitude = Math.abs(ratio - 1);
                const correctionStrength = errorMagnitude > 1.0 ? 0.85
                                         : errorMagnitude > 0.3 ? 0.70
                                         : 0.50;
                const scaleFactor = 1 + (ratio - 1) * correctionStrength;

                console.log(`Scaling attempt ${attempts + 1}: ${actualDistanceKm.toFixed(1)}km → target ${(effectiveTargetDistanceKm ?? targetDistance)}km, ratio=${ratio.toFixed(2)}, scale=${scaleFactor.toFixed(3)}`);

                // Alle Zwischenpunkte skalieren (nicht Start/Ende)
                const scaledWaypoints = finalWaypoints.map((wp, i) => {
                    if (i === 0 || i === finalWaypoints.length - 1) return wp;
                    return scaleWaypoint(startLocation, wp, scaleFactor);
                });

                const newRadiuses = scaledWaypoints
                    .map((_, i) =>
                        (i === 0 || i === scaledWaypoints.length - 1)
                            ? 'unlimited'
                            : `${Math.round(distanceConfig.waypointRadiusMeters * 0.9)}`,
                    )
                    .join(';');

                let newRoute = await getMapboxRoute(
                    scaledWaypoints,
                    mapboxProfile,
                    excludeParams,
                    newRadiuses,
                    MAPBOX_ACCESS_TOKEN,
                    { continueStraight: currentRouteType !== 'ROUND_TRIP' },
                )

                if (!newRoute && excludeParams && excludeParams.trim() !== '') {
                    newRoute = await getMapboxRoute(
                        scaledWaypoints,
                        mapboxProfile,
                        '',
                        newRadiuses,
                        MAPBOX_ACCESS_TOKEN,
                        { continueStraight: currentRouteType !== 'ROUND_TRIP' },
                    )
                }

                if (!newRoute) {
                    console.log(`Scaling attempt ${attempts + 1}: No route found, stopping`);
                    break
                }

                const scaledQuality = evaluateRouteQuality(newRoute, currentRouteType, {
                    targetDistanceKm: effectiveTargetDistanceKm ?? targetDistance,
                    distanceConfig,
                })
                if (!scaledQuality.passed) {
                    console.log(`Scaling attempt ${attempts + 1}: Route rejected (${scaledQuality.reason})`);
                    break
                }

                route = newRoute
                finalWaypoints = scaledWaypoints
                actualDistanceKm = (newRoute.distance as number) / 1000
                attempts += 1
            }
            console.log(`Distance scaling done after ${attempts} attempts: ${actualDistanceKm.toFixed(1)} km (target: ${(effectiveTargetDistanceKm ?? targetDistance)} km, band: ${distanceConfig.minKm}-${distanceConfig.maxKm} km)`);
        }

        // ── Quality gate: Route muss echte Straßengeometrie haben ──
        const finalQuality = evaluateRouteQuality(route, currentRouteType, {
            targetDistanceKm: currentRouteType === 'ROUND_TRIP' ? (effectiveTargetDistanceKm ?? targetDistance) : undefined,
            distanceConfig: currentRouteType === 'ROUND_TRIP' ? distanceConfig ?? undefined : undefined,
        })
        if (!finalQuality.passed) {
            console.error(`Route quality too low: ${finalQuality.reason}`);
            throw new Error(`Route-Qualität zu niedrig (${finalQuality.reason}). Bitte erneut versuchen.`);
        }

        // Always use the ACTUAL Mapbox distance — never clamp.
        const finalDistanceKm = actualDistanceKm

        // Route wird NICHT in der Edge Function gespeichert.
        // Die App speichert via SavedRoutesService.saveRoute() MIT user_id.
        // (Edge Function hat keinen Auth-Context → konnte vorher kein user_id setzen)

        const routeForFrontend = {
            ...route,
            distance: route.distance, // Mapbox-Originalwert in METERN beibehalten
            legs: route.legs ?? [],
        }

        // Construct response
        return new Response(
            JSON.stringify({
                route: routeForFrontend,
                waypoints: finalWaypoints,
                meta: {
                    distance_km: finalDistanceKm,
                    duration_min: route.duration / 60,
                    profile: mapboxProfile.replace('mapbox/', ''),
                    mode: mode,
                    quality_tier: finalQuality.tier,
                    quality_reason: finalQuality.reason,
                    quality_overlap_percent: finalQuality.overlapPercent,
                    quality_coordinate_count: finalQuality.coordinateCount,
                    requested_target_distance_km:
                        currentRouteType === 'ROUND_TRIP' ? targetDistance ?? null : null,
                    effective_target_distance_km:
                        currentRouteType === 'ROUND_TRIP' ? effectiveTargetDistanceKm ?? targetDistance ?? null : null,
                    ...(roundTripSearch != null
                        ? {
                            search_summary: {
                                candidate_attempts:
                                    roundTripSearch.candidateAttempts,
                                accepted_candidates:
                                    roundTripSearch.acceptedCandidates,
                                rejected_candidates:
                                    roundTripSearch.rejectedCandidates,
                                reject_reasons:
                                    roundTripSearch.rejectReasons,
                                search_phases:
                                    roundTripSearch.searchPhases,
                                variant_hint:
                                    roundTripSearch.variantHint ?? null,
                                fingerprint_hint:
                                    roundTripSearch.fingerprintHint ?? null,
                            },
                          }
                        : {}),
                }
            }),
            { headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' } }
        )

    } catch (error: any) {
        const message = error?.message ?? 'Unbekannter Fehler in generate-cruise-route'
        const classification = classifyRoutingError(message)
        console.error("Error in generate-cruise-route:", message, error?.stack ?? '')
        const responseHeaders: Record<string, string> = {
            ...getCorsHeaders(req),
            'Content-Type': 'application/json',
        }
        if (classification.retryAfterSec != null) {
            responseHeaders['Retry-After'] = String(classification.retryAfterSec)
        }
        return new Response(
            JSON.stringify({
                error: message,
                code: classification.code,
                retryable: classification.retryable,
                retry_after_sec: classification.retryAfterSec ?? null,
            }),
            {
                status: classification.status,
                headers: responseHeaders,
            }
        )
    }
})
