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
    // ±15% Toleranz um die Zieldistanz — z.B. 50km → 42.5-57.5km
    const tolerance = 0.15;
    const minKm = Math.round(targetDistance * (1 - tolerance));
    const maxKm = Math.round(targetDistance * (1 + tolerance));

    // Radius muss VIEL kleiner sein als die Zieldistanz, weil:
    // - Straßenrouten sind 1.3-2x länger als Luftlinie
    // - Bei exclude=motorway,toll werden Routen noch länger (Landstraßen-Umwege)
    // - 4-5 Waypoints im Kreis erzeugen eine Route ≈ 2*PI*radius * road_factor
    //
    // Formel: radius = targetDistance / (2 * PI * road_factor)
    // road_factor: 1.4 normal, 1.8 für Kurvenjagd/Entdecker (keine Autobahn)
    let roadFactor = 1.4;
    if (mode === 'Kurvenjagd' || mode === 'Entdecker') {
        roadFactor = 1.8; // Landstraßen sind deutlich länger
    } else if (mode === 'Abendrunde') {
        roadFactor = 1.5; // Stadt-Routing etwas länger
    }
    const radiusKm = targetDistance / (2 * Math.PI * roadFactor);

    console.log(`Distance config: target=${targetDistance}km, radius=${radiusKm.toFixed(1)}km, band=${minKm}-${maxKm}km, roadFactor=${roadFactor}`);
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
        let mapboxProfile = 'mapbox/driving';
        let excludeParams = '';
        let radiusesParams = '';

        if (mode === 'Kurvenjagd') {
                // Bergstraßen & Kurven: Autobahnen + Schnellstraßen ausschließen → nur Landstraßen
                mapboxProfile = 'mapbox/driving';
                excludeParams = 'motorway,toll';
        } else if (mode === 'Sport Mode') {
                // Schnelle, leicht kurvige Strecken: nur Autobahn vermeiden
                mapboxProfile = 'mapbox/driving';
                excludeParams = 'motorway';
        } else if (mode === 'Abendrunde') {
                // Entspannte Stadt-Route: Traffic-Profil bevorzugt beleuchtete Hauptstraßen
                mapboxProfile = 'mapbox/driving-traffic';
                excludeParams = 'motorway,unpaved';
        } else if (mode === 'Entdecker') {
                // Unbefahrene Strecken: keine Einschränkungen, alle Straßentypen erlaubt
                mapboxProfile = 'mapbox/driving';
                excludeParams = 'motorway,toll';
        } else {
                // Default/Standard fallback
                mapboxProfile = 'mapbox/driving';
        }

        // --- 3. Flexible Planung ---
        let finalWaypoints: Coordinate[] = []
        let distanceConfig: DistanceConfig | null = null
        // Default to ROUND_TRIP if not specified, for backward compatibility or default 'Zufall' behavior
        const currentRouteType = body.route_type || 'ROUND_TRIP';

        if (planning_type === 'Zufall') {
                if (currentRouteType === 'POINT_TO_POINT') {
                          if (!body.destination_location) {
                                  throw new Error("For 'POINT_TO_POINT' planning, a destination_location is required.")
                          }
                          // Simple A -> B
                          finalWaypoints = [startLocation, body.destination_location];
                } else {
                        // ROUND_TRIP logic
                        if (!targetDistance) {
                                throw new Error("For 'Zufall' planning, a targetDistance is required.")
                        }

                        // >100 km is capped to 150 km maximum route target
                        const effectiveDistance = Math.min(targetDistance, 150);
                        distanceConfig = getDistanceConfig(effectiveDistance, mode)

                        // Waypoint-Strategie je nach Fahrstil
                        let generatedWPs: Coordinate[];
                        if (mode === 'Kurvenjagd') {
                            // Mehr Waypoints für kurvigere Routen (4-5 Punkte im Kreis)
                            generatedWPs = calculateLoopWaypoints(startLocation, distanceConfig.radiusKm * 1.1, 4);
                        } else if (mode === 'Entdecker') {
                            // Loop mit vielen Waypoints für abwechslungsreiche Strecken
                            generatedWPs = calculateLoopWaypoints(startLocation, distanceConfig.radiusKm * 0.9, 5);
                        } else if (mode === 'Abendrunde') {
                            // Kompakter Dreieck, kürzerer Radius für Stadtnähe
                            generatedWPs = calculateTriangleWaypoints(startLocation, distanceConfig.radiusKm * 0.7);
                        } else {
                            // Sport Mode & Standard: normales Dreieck
                            generatedWPs = calculateTriangleWaypoints(startLocation, distanceConfig.radiusKm);
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
        radiusesParams = finalWaypoints
            .map((_, i) => (i === 0 || i === finalWaypoints.length - 1) ? 'unlimited' : '1000')
            .join(';');

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
