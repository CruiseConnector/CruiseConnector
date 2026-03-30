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
}

interface DistanceConfig {
    radiusKm: number
    minKm: number
    maxKm: number
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
    // ±10% Toleranz für präzise Distanz-Einhaltung
    const tolerance = 0.10;
    const minKm = Math.round(targetDistance * (1 - tolerance));
    const maxKm = Math.round(targetDistance * (1 + tolerance));

    // Formel: radius = targetDistance / (2 * PI * road_factor)
    // road_factor variiert stark je nach Stil, weil Landstraßen-Routing
    // deutlich längere Wege erzeugt als Direktverbindungen.
    let roadFactor: number;
    switch (mode) {
        case 'Kurvenjagd':
            roadFactor = 2.2; // Enge Bergstraßen = sehr lange Umwege
            break;
        case 'Entdecker':
            roadFactor = 2.0; // Abgelegene Straßen = lange Umwege
            break;
        case 'Abendrunde':
            roadFactor = 1.3; // Stadtnah, kurze Wege → größerer Radius nötig
            break;
        case 'Sport Mode':
            roadFactor = 1.5; // Breite Straßen, weniger Umwege als Kurven
            break;
        default:
            roadFactor = 1.5;
    }
    const radiusKm = targetDistance / (2 * Math.PI * roadFactor);

    console.log(`Distance config: target=${targetDistance}km, radius=${radiusKm.toFixed(1)}km, band=${minKm}-${maxKm}km, roadFactor=${roadFactor}, mode=${mode}`);
    return { radiusKm, minKm, maxKm };
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
function calculateTriangleWaypoints(start: Coordinate, searchRadiusKm: number, seed?: number): Coordinate[] {
    // Seeded random für reproduzierbare aber variable Routen
    const s = seed ?? Math.floor(Math.random() * 100000);
    const rng = (offset: number) => seededUnit(s + offset);

    const baseBearing = rng(0) * 360;

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
function calculateLoopWaypoints(start: Coordinate, searchRadiusKm: number, numWaypoints: number = 5, seed?: number): Coordinate[] {
    // Seeded random für reproduzierbare aber variable Routen
    const s = seed ?? Math.floor(Math.random() * 100000);
    const rng = (offset: number) => seededUnit(s + offset);

    const baseBearing = rng(0) * 360;
    const angleStep = 360 / (numWaypoints + 1);

    const waypoints: Coordinate[] = [];

    for (let i = 0; i < numWaypoints; i++) {
        // Vary the distance slightly (0.7 to 1.3 of radius)
        const distanceVariation = 0.7 + (rng(10 + i * 2) * 0.6);
        const distance = searchRadiusKm * distanceVariation;

        // Calculate bearing with some randomness
        const bearing = baseBearing + (angleStep * i) + (rng(11 + i * 2) * 30 - 15);

        const wp = calculateDestination(start, distance, bearing);
        waypoints.push(wp);
    }

    return waypoints;
}

/**
 * Generates return path waypoints that avoid the outbound route.
 * Creates a "figure-8" or wide loop pattern instead of backtracking.
 */
function calculateReturnPath(start: Coordinate, outboundWaypoints: Coordinate[], seed?: number): Coordinate[] {
    if (outboundWaypoints.length < 2) return [];
    const s = seed ?? Math.floor(Math.random() * 100000);
    const rng = (offset: number) => seededUnit(s + offset);

    const lastWp = outboundWaypoints[outboundWaypoints.length - 1];
    const midWp = outboundWaypoints[Math.floor(outboundWaypoints.length / 2)];

    const midBearing = calculateBearing(start, midWp);
    const returnBearing = (midBearing + 120 + rng(50) * 60) % 360;
    const returnDistance = calculateDistance(start, lastWp) * (0.6 + rng(51) * 0.3);

    const returnWp = calculateDestination(start, returnDistance, returnBearing);
    return [returnWp];
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

function buildPointToPointScenicWaypoints({
    start,
    destination,
    mode,
    targetDistance,
    detourLevel,
    detourFactor,
    randomSeed = 0,
}: {
    start: Coordinate
    destination: Coordinate
    mode?: RouteMode
    targetDistance?: number
    detourLevel: number
    detourFactor?: number
    randomSeed?: number
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
    const extraDistanceKm = Math.max(
        minimumExtraDistanceKm,
        desiredDistanceKm - directDistanceKm,
    )

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
    const baseSide = seededUnit(randomSeed + detourLevel + Math.round(directDistanceKm)) >= 0.5 ? 1 : -1

    // Offset-Limits je nach Umweg-Level (drastischer gespreizt)
    const maxOffsetKm = detourLevel === 1
        ? Math.max(12, directDistanceKm * 0.95)
        : Math.max(10, directDistanceKm * 0.8)
    const minOffsetKm = detourLevel === 1
        ? Math.min(
            maxOffsetKm,
            Math.max(5.5, extraDistanceKm / Math.max(1.8, waypointCount)),
        )
        : Math.min(
            maxOffsetKm,
            Math.max(4.0, extraDistanceKm / Math.max(2, waypointCount)),
        )

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
                // Starke Ausschläge, wechselnde Seiten → Zickzack = viele Kurven
                arcFactor = 1.0 + index * 0.2;
                angleDrift = (seededUnit(variationSeed + 7) - 0.5) * 50;
                side = index % 2 === 0 ? baseSide : -baseSide;
                break;
            case 'Entdecker':
                // Maximale Variation, zufällige Seiten → unbekannte Wege
                arcFactor = 0.8 + seededUnit(variationSeed + 3) * 0.7;
                angleDrift = (seededUnit(variationSeed + 7) - 0.5) * 65;
                side = seededUnit(variationSeed + 11) >= 0.5 ? 1 : -1;
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
                    ? 0.9 + index * 0.16
                    : 0.75 + index * 0.18;
                angleDrift = (seededUnit(variationSeed + 7) - 0.5) *
                    (detourLevel === 1 ? 38 : 30);
                side = waypointCount <= 1
                    ? baseSide
                    : (index % 2 === 0 ? baseSide : -baseSide);
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

    return [start, ...scenicWaypoints, destination]
}

function getRouteDistanceKm(route: any): number {
    return typeof route?.distance === 'number' ? route.distance / 1000 : 0
}

function getPointToPointMinimumDistanceKm(
    directDistanceKm: number,
    targetDistance: number | undefined,
    detourLevel: number,
): number {
    const detourMultiplier = detourLevel === 1
        ? 1.25   // Klein: mindestens +25%
        : detourLevel === 2
        ? 1.50   // Mittel: mindestens +50%
        : detourLevel >= 3
        ? 1.90   // Groß: mindestens +90%
        : 1.0

    return Math.max(
        targetDistance ? targetDistance * 0.985 : 0,
        directDistanceKm * detourMultiplier,
    )
}

function isPointToPointDetourAcceptable(
    route: any,
    directDistanceKm: number,
    targetDistance: number | undefined,
    detourLevel: number,
): boolean {
    const minimumDistanceKm = getPointToPointMinimumDistanceKm(
        directDistanceKm,
        targetDistance,
        detourLevel,
    )
    return getRouteDistanceKm(route) >= minimumDistanceKm
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
async function getMapboxRoute(
    waypoints: Coordinate[],
    profile: string,
    exclude: string,
    radiuses: string,
    accessToken: string
) {
    // Format coordinates: "lon,lat;lon,lat;..."
    const coordinatesStr = waypoints
        .map(p => `${p.longitude},${p.latitude}`)
        .join(';')

    // Base URL
    // We use geometries=geojson to get the path geometry
    let url = `https://api.mapbox.com/directions/v5/${profile}/${coordinatesStr}?access_token=${accessToken}&geometries=geojson&overview=full&steps=true&voice_instructions=true&banner_instructions=true&language=de&continue_straight=true&annotations=maxspeed`

    // Append optional parameters if they exist
    if (exclude && exclude.trim() !== '') {
        url += `&exclude=${exclude}`
    }
    if (radiuses && radiuses.trim() !== '') {
        url += `&radiuses=${radiuses}`
    }

    const res = await fetch(url)
    if (!res.ok) {
        const text = await res.text()
        console.error(`Mapbox API Error (${res.status}): ${text}`)
        return null
    }

    const data = await res.json()
    if (!data.routes || data.routes.length === 0) {
        return null
    }

    // Return the best route
    return data.routes[0]
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

function evaluateRouteQuality(route: any, routeType: 'ROUND_TRIP' | 'POINT_TO_POINT') {
    const coordinateCount = route?.geometry?.coordinates?.length ?? 0
    const actualDistanceKm = getRouteDistanceKm(route)
    const hasUTurn = hasUTurnManeuver(route)
    const overlapPercent = calculateRouteOverlapPercent(route)
    const overlapThreshold = routeType === 'ROUND_TRIP' ? 18 : 14

    if (coordinateCount < 30 && actualDistanceKm > 10) {
        return {
            passed: false,
            reason: `coords=${coordinateCount}`,
            overlapPercent,
            hasUTurn,
        }
    }
    if (hasUTurn) {
        return {
            passed: false,
            reason: 'u_turn',
            overlapPercent,
            hasUTurn,
        }
    }
    if (overlapPercent > overlapThreshold) {
        return {
            passed: false,
            reason: `overlap=${overlapPercent.toFixed(1)}%`,
            overlapPercent,
            hasUTurn,
        }
    }

    return {
        passed: true,
        reason: 'ok',
        overlapPercent,
        hasUTurn,
    }
}

function classifyHttpStatusFromRoutingError(message: string): number {
    const lower = message.toLowerCase()
    if (
        lower.includes('invalid') ||
        lower.includes('missing') ||
        lower.includes('out of bounds') ||
        lower.includes('required')
    ) {
        return 422
    }
    if (lower.includes('no route found') || lower.includes('keine route')) {
        return 404
    }
    if (lower.includes('unauthorized') || lower.includes('forbidden') || lower.includes('jwt')) {
        return 401
    }
    if (lower.includes('rate limit') || lower.includes('too many requests')) {
        return 429
    }
    return 500
}

Deno.serve(async (req) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: getCorsHeaders(req) })
    }

    try {
        // 1. Parse Request
        const body = await req.json() as RequestData
        console.log("Anfrage erhalten!", body);
        const { planning_type, startLocation, targetDistance, manual_waypoints, mode } = body

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

        const avoidHighways = body.avoid_highways === true
        const randomSeed = body.randomSeed ?? Math.floor(Math.random() * 100000)

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
        let pointToPointIsScenic = false
        let pointToPointDirectDistanceKm = 0
        // Default to ROUND_TRIP if not specified, for backward compatibility or default 'Zufall' behavior
        const currentRouteType = body.route_type || 'ROUND_TRIP';
        const detourLevel = Math.max(0, Math.min(3, body.detour_level ?? 0))

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
                                    randomSeed: body.randomSeed ?? 0,
                                })
                              : [startLocation, body.destination_location];
                          const scenicRadius = detourLevel >= 3
                              ? '18000'
                              : detourLevel === 2
                              ? '14000'
                              : detourLevel === 1
                              ? '13000'
                              : '6000'
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

                        // Waypoint-Strategie je nach Fahrstil — jeder Stil erzeugt
                        // eine grundlegend andere Route-Geometrie
                        let generatedWPs: Coordinate[];
                        if (mode === 'Kurvenjagd') {
                            // 6 eng gesetzte WPs, großer Radius → viele Richtungswechsel = mehr Kurven
                            generatedWPs = calculateLoopWaypoints(startLocation, distanceConfig.radiusKm * 1.25, 6, randomSeed);
                        } else if (mode === 'Entdecker') {
                            // 7 weit gestreute WPs → maximale Variation, unerwartete Richtungen
                            generatedWPs = calculateLoopWaypoints(startLocation, distanceConfig.radiusKm * 1.1, 7, randomSeed);
                        } else if (mode === 'Abendrunde') {
                            // Einfaches Dreieck, kompakter Radius → bleibt nah, ruhige Strecke
                            generatedWPs = calculateTriangleWaypoints(startLocation, distanceConfig.radiusKm * 0.75, randomSeed);
                        } else {
                            // SPORT MODE: 3 WPs, breiter Radius → fließende Bögen auf breiten Straßen
                            generatedWPs = calculateLoopWaypoints(startLocation, distanceConfig.radiusKm * 1.15, 3, randomSeed);
                        }

                        // Route: Start -> WPs -> Start
                        finalWaypoints = [startLocation, ...generatedWPs, startLocation];
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
        if (!radiusesParams) {
            radiusesParams = finalWaypoints
                .map((_, i) => (i === 0 || i === finalWaypoints.length - 1) ? 'unlimited' : '1000')
                .join(';');
        }

        // --- Execute Route Request (with retries) ---
        let route = await getMapboxRoute(finalWaypoints, mapboxProfile, excludeParams, radiusesParams, MAPBOX_ACCESS_TOKEN);

        if (!route && excludeParams && excludeParams.trim() !== '') {
            console.log(`No route with excludes "${excludeParams}", retrying without...`);
            route = await getMapboxRoute(finalWaypoints, mapboxProfile, '', radiusesParams, MAPBOX_ACCESS_TOKEN);
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
            )
        ) {
            console.log(
                `Initial P2P scenic route rejected: ${getRouteDistanceKm(route).toFixed(1)}km < required ${getPointToPointMinimumDistanceKm(pointToPointDirectDistanceKm, targetDistance, detourLevel).toFixed(1)}km`,
            )
            route = null
        }

        // Retry with different waypoint directions (up to 5 more attempts)
        // Alterniert zwischen Triangle und Loop-Strategien für maximale Chance
        if (!route && planning_type === 'Zufall' && currentRouteType === 'ROUND_TRIP' && distanceConfig) {
            for (let retry = 0; retry < 5 && !route; retry++) {
                console.log(`Retry ${retry + 1}: generating new waypoints...`);
                // Gerade Versuche: Triangle, ungerade: Loop mit 3 Punkten
                const retryRadius = distanceConfig.radiusKm * (0.7 + retry * 0.15);
                const retrySeed = randomSeed + (retry + 1) * 1000;
                const retryWPs = retry % 2 === 0
                    ? calculateTriangleWaypoints(startLocation, retryRadius, retrySeed)
                    : calculateLoopWaypoints(startLocation, retryRadius, 3, retrySeed);
                const retryAll = [startLocation, ...retryWPs, startLocation];
                const retryRadiuses = retryAll.map((_, i) => (i === 0 || i === retryAll.length - 1) ? 'unlimited' : '2000').join(';');

                route = await getMapboxRoute(retryAll, mapboxProfile, '', retryRadiuses, MAPBOX_ACCESS_TOKEN);
                if (route) {
                    const retryQuality = evaluateRouteQuality(route, currentRouteType)
                    if (!retryQuality.passed) {
                        console.log(`Retry ${retry + 1}: Route rejected (${retryQuality.reason})`);
                        route = null;
                        continue;
                    }
                    finalWaypoints = retryAll;
                    radiusesParams = retryRadiuses;
                }
            }
        }

        if (!route && planning_type === 'Zufall' && currentRouteType === 'POINT_TO_POINT' && body.destination_location && pointToPointIsScenic) {
            for (let retry = 0; retry < 4 && !route; retry++) {
                console.log(`P2P scenic retry ${retry + 1}: regenerating waypoints...`);
                const retryDetourLevel = Math.max(
                    detourLevel - (retry >= 3 ? 1 : 0),
                    0,
                )
                const softenedTarget = targetDistance != null
                    ? Math.max(
                        pointToPointDirectDistanceKm * 1.22,
                        targetDistance * (0.99 - retry * 0.04),
                    )
                    : undefined
                const retryWaypoints = buildPointToPointScenicWaypoints({
                    start: startLocation,
                    destination: body.destination_location,
                    mode,
                    targetDistance: softenedTarget,
                    detourLevel: retryDetourLevel,
                    detourFactor: body.detour_factor,
                    randomSeed: (body.randomSeed ?? 0) + retry + 1,
                })
                const retryRadius = retryDetourLevel >= 3
                    ? '19000'
                    : retryDetourLevel === 2
                    ? '15000'
                    : retryDetourLevel === 1
                    ? '13500'
                    : '7000'
                const retryRadiuses = retryWaypoints
                    .map((_, i) => (i === 0 || i === retryWaypoints.length - 1) ? 'unlimited' : retryRadius)
                    .join(';')

                route = await getMapboxRoute(retryWaypoints, mapboxProfile, excludeParams, retryRadiuses, MAPBOX_ACCESS_TOKEN);
                if (!route && excludeParams && excludeParams.trim() !== '') {
                    route = await getMapboxRoute(retryWaypoints, mapboxProfile, '', retryRadiuses, MAPBOX_ACCESS_TOKEN);
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
                        )
                    ) {
                        console.log(
                            `P2P scenic retry ${retry + 1}: route rejected because it is too short (${getRouteDistanceKm(route).toFixed(1)}km < required ${getPointToPointMinimumDistanceKm(pointToPointDirectDistanceKm, softenedTarget ?? targetDistance, retryDetourLevel).toFixed(1)}km)`,
                        )
                        route = null
                        continue
                    }
                    finalWaypoints = retryWaypoints;
                    radiusesParams = retryRadiuses;
                }
            }
        }

        if (!route && planning_type === 'Zufall' && currentRouteType === 'POINT_TO_POINT' && body.destination_location) {
            console.log('P2P scenic fallback: using direct A->B route');
            const fallbackWaypoints = [startLocation, body.destination_location];
            const fallbackRadiuses = 'unlimited;unlimited';
            route = await getMapboxRoute(fallbackWaypoints, mapboxProfile, '', fallbackRadiuses, MAPBOX_ACCESS_TOKEN);
            if (route) {
                finalWaypoints = fallbackWaypoints;
                radiusesParams = fallbackRadiuses;
            }
        }

        if (!route) {
            throw new Error("No route found with current constraints.");
        }

        // Mapbox returns distance in meters -> convert to kilometers for app output.
        let actualDistanceKm = (route.distance as number) / 1000;

        // --- 4. Distance Band Retry & Scaling ---
        // Skaliert Waypoints näher/weiter zum Start bis die Route im ±10% Band liegt.
        // Aggressive Korrektur bei großem Fehler, sanfter bei Annäherung.
        if (planning_type === 'Zufall' && currentRouteType === 'ROUND_TRIP' && distanceConfig) {
            let attempts = 0
            const maxAttempts = 8 // Mehr Versuche für bessere Konvergenz
            while (
                attempts < maxAttempts &&
                (actualDistanceKm > distanceConfig.maxKm || actualDistanceKm < distanceConfig.minKm)
            ) {
                const ratio = targetDistance! / actualDistanceKm;
                // Aggressiver korrigieren bei großem Fehler, sanfter bei Annäherung
                // > 2x oder < 0.5x → 85% Korrektur (fast direkt)
                // 1.3x-2x → 70% Korrektur
                // < 1.3x → 50% Korrektur (Feintuning, verhindert Oszillation)
                const errorMagnitude = Math.abs(ratio - 1);
                const correctionStrength = errorMagnitude > 1.0 ? 0.85
                                         : errorMagnitude > 0.3 ? 0.70
                                         : 0.50;
                const scaleFactor = 1 + (ratio - 1) * correctionStrength;

                console.log(`Scaling attempt ${attempts + 1}: ${actualDistanceKm.toFixed(1)}km → target ${targetDistance}km, ratio=${ratio.toFixed(2)}, scale=${scaleFactor.toFixed(3)}`);

                // Alle Zwischenpunkte skalieren (nicht Start/Ende)
                const scaledWaypoints = finalWaypoints.map((wp, i) => {
                    if (i === 0 || i === finalWaypoints.length - 1) return wp;
                    return scaleWaypoint(startLocation, wp, scaleFactor);
                });

                const newRadiuses = scaledWaypoints
                    .map((_, i) => (i === 0 || i === scaledWaypoints.length - 1) ? 'unlimited' : '2000')
                    .join(';');

                let newRoute = await getMapboxRoute(
                    scaledWaypoints,
                    mapboxProfile,
                    excludeParams,
                    newRadiuses,
                    MAPBOX_ACCESS_TOKEN,
                )

                if (!newRoute && excludeParams && excludeParams.trim() !== '') {
                    newRoute = await getMapboxRoute(scaledWaypoints, mapboxProfile, '', newRadiuses, MAPBOX_ACCESS_TOKEN)
                }

                if (!newRoute) {
                    console.log(`Scaling attempt ${attempts + 1}: No route found, stopping`);
                    break
                }

                const scaledQuality = evaluateRouteQuality(newRoute, currentRouteType)
                if (!scaledQuality.passed) {
                    console.log(`Scaling attempt ${attempts + 1}: Route rejected (${scaledQuality.reason})`);
                    break
                }

                route = newRoute
                finalWaypoints = scaledWaypoints
                actualDistanceKm = (newRoute.distance as number) / 1000
                attempts += 1
            }
            console.log(`Distance scaling done after ${attempts} attempts: ${actualDistanceKm.toFixed(1)} km (target: ${targetDistance} km, band: ${distanceConfig.minKm}-${distanceConfig.maxKm} km)`);
        }

        // ── Quality gate: Route muss echte Straßengeometrie haben ──
        const finalQuality = evaluateRouteQuality(route, currentRouteType)
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
                        mode: mode
                }
            }),
            { headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' } }
        )

    } catch (error: any) {
        const message = error?.message ?? 'Unbekannter Fehler in generate-cruise-route'
        const status = classifyHttpStatusFromRoutingError(message)
        console.error("Error in generate-cruise-route:", message, error?.stack ?? '')
        return new Response(
            JSON.stringify({ error: message }),
            {
                status,
                headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' }
            }
        )
    }
})
