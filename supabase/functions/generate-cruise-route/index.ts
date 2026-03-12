// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

// Environment variables
const MAPBOX_ACCESS_TOKEN = Deno.env.get('MAPBOX_ACCESS_TOKEN')

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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

function getDistanceConfig(targetDistance: number): DistanceConfig {
    if (targetDistance <= 20) {
        return { radiusKm: 2.5, minKm: 10, maxKm: 20 }
    }
    if (targetDistance <= 50) {
        return { radiusKm: 7.5, minKm: 40, maxKm: 50 }
    }
    if (targetDistance <= 100) {
        return { radiusKm: 15, minKm: 60, maxKm: 100 }
    }

    return { radiusKm: 22.5, minKm: 100, maxKm: 150 }
}

/**
 * Calculates triangle-like waypoints from a fixed search radius in km.
 * @deprecated Use calculateLoopWaypoints instead for better variety
 */
function calculateTriangleWaypoints(start: Coordinate, searchRadiusKm: number): Coordinate[] {
    return calculateLoopWaypoints(start, searchRadiusKm, 3);
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
    let url = `https://api.mapbox.com/directions/v5/${profile}/${coordinatesStr}?access_token=${accessToken}&geometries=geojson&overview=full&steps=true&voice_instructions=true&banner_instructions=true`

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

Deno.serve(async (req) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
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

        // --- 2. Fahrstil-Parameter (Mapbox) ---
        let mapboxProfile = 'mapbox/driving';
        let excludeParams = '';
        let radiusesParams = '';

        if (mode === 'Kurvenjagd') {
                mapboxProfile = 'mapbox/driving';
                excludeParams = 'motorway,trunk,primary';
        } else if (mode === 'Sport Mode') {
                mapboxProfile = 'mapbox/driving';
                excludeParams = 'motorway';
                // Radiuses need to be set for EACH coordinate. We will calculate this after we determine the waypoints list.
        } else if (mode === 'Abendrunde') {
                mapboxProfile = 'mapbox/driving-traffic';
                // 'beleuchtete Hauptstra뿯½en' -> traffic profile favors main roads. No specific exclude.
                excludeParams = '';
        } else if (mode === 'Entdecker') {
                mapboxProfile = 'mapbox/driving';
                excludeParams = ''; // Standard profile, minimal filters
        } else {
                // Default fallback
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
                        distanceConfig = getDistanceConfig(effectiveDistance)

                        // Generate WP1 and WP2
                        const generatedWPs = calculateTriangleWaypoints(startLocation, distanceConfig.radiusKm);

                        // Route: Start -> WP1 -> WP2 -> Start
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

        // Prepare dynamic radiuses if needed (Sport Mode wants "1000;1000;...")
        if (mode === 'Sport Mode') {
                radiusesParams = finalWaypoints.map(() => '1000').join(';');
        } else {
                radiusesParams = '';
        }

        // --- Execute Route Request ---
        let route = await getMapboxRoute(finalWaypoints, mapboxProfile, excludeParams, radiusesParams, MAPBOX_ACCESS_TOKEN);

        if (!route) {
            // Fallback: retry without exclude constraints (e.g. Kurvenjagd excludes too much in this region)
            if (excludeParams && excludeParams.trim() !== '') {
                console.log(`No route found with excludes "${excludeParams}", retrying without constraints...`);
                route = await getMapboxRoute(finalWaypoints, mapboxProfile, '', radiusesParams, MAPBOX_ACCESS_TOKEN);
            }

            if (!route) {
                throw new Error("No route found with current constraints.");
            }
        }

        // Mapbox returns distance in meters -> convert to kilometers for app output.
        let actualDistanceKm = (route.distance as number) / 1000;

        // --- 4. Distance Band Retry & Clamp ---
        // Applies to generated random round trips only.
        if (planning_type === 'Zufall' && currentRouteType === 'ROUND_TRIP' && distanceConfig) {
            let attempts = 0
            while (
                attempts < 3 &&
                (actualDistanceKm > distanceConfig.maxKm || actualDistanceKm < distanceConfig.minKm)
            ) {
                const wp1 = finalWaypoints[1]
                const wp2 = finalWaypoints[2]

                const isTooLong = actualDistanceKm > distanceConfig.maxKm
                const scaleFactor = isTooLong ? 0.75 : 1.2

                const newWp1 = scaleWaypoint(startLocation, wp1, scaleFactor)
                const newWp2 = scaleWaypoint(startLocation, wp2, scaleFactor)
                const scaledWaypoints = [startLocation, newWp1, newWp2, startLocation]

                const newRadiuses = mode === 'Sport Mode'
                    ? scaledWaypoints.map(() => '1000').join(';')
                    : ''

                let newRoute = await getMapboxRoute(
                    scaledWaypoints,
                    mapboxProfile,
                    excludeParams,
                    newRadiuses,
                    MAPBOX_ACCESS_TOKEN,
                )

                // Fallback for retry attempts as well
                if (!newRoute && excludeParams && excludeParams.trim() !== '') {
                    newRoute = await getMapboxRoute(scaledWaypoints, mapboxProfile, '', newRadiuses, MAPBOX_ACCESS_TOKEN)
                }

                if (!newRoute) {
                    break
                }

                route = newRoute
                finalWaypoints = scaledWaypoints
                actualDistanceKm = (newRoute.distance as number) / 1000
                attempts += 1
            }
        }

        // Final clamp before returning to frontend, keeping distance inside target band.
        const clampedDistanceKm = distanceConfig
            ? Math.min(Math.max(actualDistanceKm, distanceConfig.minKm), distanceConfig.maxKm)
            : actualDistanceKm

        // --- 5. Database Integration ---
        // Save successful route to DB
        const supabase = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // We assume the table 'routes' exists with strict columns per request
        const { error: dbError } = await supabase
            .from('routes')
            .insert({
                style: mode,
                distance_target: targetDistance || clampedDistanceKm, // Fallback if no target set
                distance_actual: clampedDistanceKm,
                geometry: route.geometry, // GeoJSON geometry from Mapbox
                // Optional: user_id if authentication was available in context, or other metadata
            })

        if (dbError) {
                console.error("Failed to save route to database:", dbError)
                // We choose not to fail the request if DB save fails, just log it.
        }

        const routeForFrontend = {
            ...route,
            distance: clampedDistanceKm,
            legs: route.legs ?? [],
        }

        // Construct response
        return new Response(
            JSON.stringify({
                route: routeForFrontend,
                waypoints: finalWaypoints,
                meta: {
                    distance_km: clampedDistanceKm,
                        duration_min: route.duration / 60,
                        profile: mapboxProfile.replace('mapbox/', ''),
                        mode: mode
                }
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error: any) {
        console.error("Error in generate-cruise-route:", error.message);
        return new Response(
            JSON.stringify({ error: error.message }),
            {
                status: 400,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            }
        )
    }
})
