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
    // ±12% Toleranz (enger als vorher ±15% für bessere Qualität)
    const tolerance = 0.12;
    const minKm = Math.round(targetDistance * (1 - tolerance));
    const maxKm = Math.round(targetDistance * (1 + tolerance));

    // Formel: radius = targetDistance / (2 * PI * road_factor)
    // road_factor variiert stark je nach Stil, weil Landstraßen-Routing
    // deutlich längere Wege erzeugt als Direktverbindungen.
    let roadFactor: number;
    switch (mode) {
        case 'Kurvenjagd':
            roadFactor = 2.0; // Enge Bergstraßen = sehr lange Umwege
            break;
        case 'Entdecker':
            roadFactor = 1.9; // Abgelegene Straßen = lange Umwege
            break;
        case 'Abendrunde':
            roadFactor = 1.4; // Stadtnah, kurze Wege → größerer Radius nötig
            break;
        case 'Sport Mode':
            roadFactor = 1.6; // Mix aus Landstraße und breiten Straßen
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
function calculateTriangleWaypoints(start: Coordinate, searchRadiusKm: number): Coordinate[] {
    const baseBearing = Math.random() * 360;

    // WP1: Outbound direction, full radius
    const wp1 = calculateDestination(
        start,
        searchRadiusKm * (0.8 + Math.random() * 0.4), // 0.8–1.2× radius
        baseBearing,
    );

    // WP2: 100–140° offset from WP1 direction, slightly shorter
    // Wide enough angle that the return path doesn't clip the start area
    const returnBearing = (baseBearing + 100 + Math.random() * 40) % 360;
    const wp2 = calculateDestination(
        start,
        searchRadiusKm * (0.65 + Math.random() * 0.2), // 0.65–0.85× radius
        returnBearing,
    );

    return [wp1, wp2];
}

/**
 * Generates loop waypoints with multiple points for varied routes.
 * Uses 4-6 waypoints arranged in a circle pattern for true loop experience.
 * Avoids returning on the same path by offsetting return route.
 */
function calculateLoopWaypoints(start: Coordinate, searchRadiusKm: number, numWaypoints: number = 5): Coordinate[] {
    // Random start bearing
    const baseBearing = Math.random() * 360;
    const angleStep = 360 / (numWaypoints + 1);
    
    const waypoints: Coordinate[] = [];
    
    for (let i = 0; i < numWaypoints; i++) {
        // Vary the distance slightly (0.7 to 1.3 of radius)
        const distanceVariation = 0.7 + (Math.random() * 0.6);
        const distance = searchRadiusKm * distanceVariation;
        
        // Calculate bearing with some randomness
        const bearing = baseBearing + (angleStep * i) + (Math.random() * 30 - 15);
        
        const wp = calculateDestination(start, distance, bearing);
        waypoints.push(wp);
    }
    
    return waypoints;
}

/**
 * Generates return path waypoints that avoid the outbound route.
 * Creates a "figure-8" or wide loop pattern instead of backtracking.
 */
function calculateReturnPath(start: Coordinate, outboundWaypoints: Coordinate[]): Coordinate[] {
    // If we have enough outbound waypoints, create a wider return arc
    if (outboundWaypoints.length < 2) return [];
    
    const lastWp = outboundWaypoints[outboundWaypoints.length - 1];
    const midWp = outboundWaypoints[Math.floor(outboundWaypoints.length / 2)];
    
    // Calculate bearing from start to midpoint
    const midBearing = calculateBearing(start, midWp);
    
    // Create return waypoint on opposite side (offset by 120-180 degrees)
    const returnBearing = (midBearing + 120 + Math.random() * 60) % 360;
    const returnDistance = calculateDistance(start, lastWp) * (0.6 + Math.random() * 0.3);
    
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

    // Umweg-Boost: drastischer gespreizt für sichtbaren Unterschied
    const detourBoost = detourLevel === 1
        ? 0.25
        : detourLevel === 2
        ? 0.55
        : detourLevel >= 3
        ? 0.85
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
        ? 5.0
        : detourLevel === 2
        ? 12.0
        : detourLevel >= 3
        ? 22.0
        : 3.0
    const extraDistanceKm = Math.max(
        minimumExtraDistanceKm,
        desiredDistanceKm - directDistanceKm,
    )

    // Waypoint-Anzahl: Stil + Umweg-Level bestimmen die Komplexität
    let waypointCount: number;
    if (detourLevel >= 3) {
        waypointCount = mode === 'Entdecker' ? 5 : 4;
    } else if (detourLevel >= 2) {
        waypointCount = mode === 'Kurvenjagd' ? 4 : 3;
    } else if (detourLevel >= 1) {
        waypointCount = mode === 'Entdecker' || mode === 'Kurvenjagd' ? 2 : 1;
    } else {
        waypointCount = 2;
    }
    if (directDistanceKm < 12) waypointCount = Math.min(waypointCount, 3);
    if (directDistanceKm < 6) waypointCount = Math.min(waypointCount, 2);

    // Fractions: wo auf der A→B Linie werden die Waypoints platziert
    const fractions = waypointCount === 1
        ? [0.5]
        : waypointCount === 2
        ? [0.3, 0.7]
        : waypointCount === 3
        ? [0.2, 0.5, 0.8]
        : waypointCount === 4
        ? [0.15, 0.38, 0.62, 0.85]
        : [0.12, 0.3, 0.5, 0.7, 0.88]

    const baseBearing = calculateBearing(start, destination)
    // Seite determiniert durch Seed — aber bei Entdecker wechselnd pro WP
    const baseSide = seededUnit(randomSeed + detourLevel + Math.round(directDistanceKm)) >= 0.5 ? 1 : -1

    // Offset-Limits je nach Umweg-Level (drastischer gespreizt)
    const maxOffsetKm = Math.max(10, directDistanceKm * 0.8)
    const minOffsetKm = Math.min(
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
                // Engere, stärkere Ausschläge → mehr Zickzack = mehr Kurven
                arcFactor = 0.9 + index * 0.15;
                angleDrift = (seededUnit(variationSeed + 7) - 0.5) * 40;
                side = index % 2 === 0 ? baseSide : -baseSide; // Wechselnde Seiten!
                break;
            case 'Entdecker':
                // Maximale Variation, alle WPs auf verschiedenen Seiten
                arcFactor = 0.7 + seededUnit(variationSeed + 3) * 0.6;
                angleDrift = (seededUnit(variationSeed + 7) - 0.5) * 55;
                side = seededUnit(variationSeed + 11) >= 0.5 ? 1 : -1; // Zufällig
                break;
            case 'Abendrunde':
                // Sanfter, gleichmäßiger Bogen — alle auf einer Seite
                arcFactor = 0.6 + index * 0.12;
                angleDrift = (seededUnit(variationSeed + 7) - 0.5) * 15;
                side = baseSide;
                break;
            default: // Sport Mode
                // Weicher Bogen, mittlerer Offset
                arcFactor = 0.75 + index * 0.2;
                angleDrift = (seededUnit(variationSeed + 7) - 0.5) * 25;
                side = baseSide;
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
        ? 1.26
        : detourLevel === 2
        ? 1.5
        : detourLevel >= 3
        ? 1.8
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
                              ? '10000'
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
                            // KURVENJAGD: 5 eng gesetzte Loop-WPs, großer Radius
                            // → Route wird durch viele Richtungswechsel gezwungen = mehr Kurven
                            // Enger Winkel-Step (60°) + wenig Variation → kompakte Schleife
                            generatedWPs = calculateLoopWaypoints(startLocation, distanceConfig.radiusKm * 1.15, 5);
                        } else if (mode === 'Entdecker') {
                            // ENTDECKER: 6 weit gestreute WPs, wechselnde Distanzen
                            // → maximale Variation, Route geht in unerwartete Richtungen
                            generatedWPs = calculateLoopWaypoints(startLocation, distanceConfig.radiusKm * 1.0, 6);
                        } else if (mode === 'Abendrunde') {
                            // ABENDRUNDE: Einfaches Dreieck, kompakter Radius
                            // → bleibt nah am Startpunkt, ruhige Strecke
                            generatedWPs = calculateTriangleWaypoints(startLocation, distanceConfig.radiusKm * 0.85);
                        } else {
                            // SPORT MODE: 3 Loop-WPs, mittlerer Radius, breite Spreizung
                            // → fließende Bögen auf breiten Landstraßen
                            generatedWPs = calculateLoopWaypoints(startLocation, distanceConfig.radiusKm * 1.05, 3);
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

        if (route && hasUTurnManeuver(route)) {
            console.log('Initial route rejected: contains U-turn maneuver');
            route = null;
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
                const retryWPs = retry % 2 === 0
                    ? calculateTriangleWaypoints(startLocation, retryRadius)
                    : calculateLoopWaypoints(startLocation, retryRadius, 3);
                const retryAll = [startLocation, ...retryWPs, startLocation];
                const retryRadiuses = retryAll.map((_, i) => (i === 0 || i === retryAll.length - 1) ? 'unlimited' : '2000').join(';');

                route = await getMapboxRoute(retryAll, mapboxProfile, '', retryRadiuses, MAPBOX_ACCESS_TOKEN);
                if (route) {
                    // Qualitätsprüfung auch bei Retries
                    const retryCoords = route.geometry?.coordinates?.length ?? 0;
                    const hasUTurn = hasUTurnManeuver(route);
                    if (retryCoords < 30 || hasUTurn) {
                        console.log(`Retry ${retry + 1}: Route rejected (coords=${retryCoords}, uturn=${hasUTurn})`);
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
                        pointToPointDirectDistanceKm * 1.18,
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
                    ? '11000'
                    : '7000'
                const retryRadiuses = retryWaypoints
                    .map((_, i) => (i === 0 || i === retryWaypoints.length - 1) ? 'unlimited' : retryRadius)
                    .join(';')

                route = await getMapboxRoute(retryWaypoints, mapboxProfile, excludeParams, retryRadiuses, MAPBOX_ACCESS_TOKEN);
                if (!route && excludeParams && excludeParams.trim() !== '') {
                    route = await getMapboxRoute(retryWaypoints, mapboxProfile, '', retryRadiuses, MAPBOX_ACCESS_TOKEN);
                }
                if (route && hasUTurnManeuver(route)) {
                    console.log(`P2P scenic retry ${retry + 1}: route rejected because of U-turn`);
                    route = null;
                    continue;
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

                // Qualitätsprüfung: Route muss echte Straßengeometrie haben
                const coordCount = newRoute.geometry?.coordinates?.length ?? 0;
                const hasUTurn = hasUTurnManeuver(newRoute);
                if (coordCount < 30 || hasUTurn) {
                    console.log(`Scaling attempt ${attempts + 1}: Route rejected (coords=${coordCount}, uturn=${hasUTurn})`);
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
        const coordCount = route.geometry?.coordinates?.length ?? 0;
        if (coordCount < 30 && actualDistanceKm > 10) {
            console.error(`Route quality too low: ${coordCount} coordinates for ${actualDistanceKm.toFixed(1)} km — likely straight lines, not roads`);
            throw new Error(`Route-Qualität zu niedrig (${coordCount} Koordinaten). Bitte erneut versuchen.`);
        }
        if (hasUTurnManeuver(route)) {
            console.error('Route quality too low: route contains U-turn maneuver');
            throw new Error('Route enthält einen Wendepunkt. Bitte erneut versuchen.');
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
        console.error("Error in generate-cruise-route:", error.message);
        return new Response(
            JSON.stringify({ error: error.message }),
            {
                status: 400,
                headers: { ...getCorsHeaders(req), 'Content-Type': 'application/json' }
            }
        )
    }
})
