// CruiseConnect Edge-Function v2 — GraphHopper Adapter
//
// Ersetzt den alten 15.000-Zeilen Mapbox-Hack durch einen schlanken Wrapper
// um die selbst-gehostete GraphHopper-Instanz.
//
// Stil-Mapping CruiseConnect → GraphHopper-Profil:
//   'Sport Mode'  / 'sport_mode'   → motorcycle_scenic
//   'Kurvenjagd'  / 'kurvenjagd'   → motorcycle_kurvenjagd
//   'Abendrunde'  / 'abendrunde'   → motorcycle_abendrunde
//   'Entdecker'   / 'entdecker'    → motorcycle_entdecker
//
// Adaptive Distance-Compensation (gemessen über DACH+BW-Graph, Tunnel-Test 2026-05-20):
//   alpine (Vorarlberg/Tirol)        → 0.90x  (war 0.78x — zu kurz, -17%)
//   alpenanrand (Salzburg/Allgäu/CH-Berg) → 1.00x  (war 0.95x — zu kurz, -15%)
//   flatland (Wien/Zürich/Bern/Linz/BW) → 1.00x  (validiert, ±5%)
//
// Endpoint-Design ist 100% kompatibel zur alten v1-Edge-Function — Flutter
// Route-Service kann v1 oder v2 via Feature-Toggle ansprechen.

import { serve } from 'https://deno.land/std@0.210.0/http/server.ts';

const GRAPHHOPPER_URL = Deno.env.get('GRAPHHOPPER_URL') ?? 'http://graphhopper.local:8989';
// DE-Server (Port 8991 hinter dem Tunnel) hat germany-latest.osm.pbf alleine —
// covers Friedrichshafen, München, Stuttgart, Nürnberg etc. die im DACH-merged
// Graph wegen osmium duplicate-node-ID Crashes nicht drin sind.
const GRAPHHOPPER_DE_URL = Deno.env.get('GRAPHHOPPER_DE_URL') ?? GRAPHHOPPER_URL.replace(':8989', ':8991');
const ALLOWED_ORIGINS = '*';

// Lat-basierte Server-Wahl:
// - AT/CH/LI/BW-Nord-Routing → DACH-Server (8989)
// - DE-südlich-48.3 + Bayern + restliches DE → DE-Server (8991)
// Fallback: wenn ein Server fehlschlägt, anderen probieren.
function chooseGraphhopperUrl(lat: number, lng: number): { primary: string; fallback: string } {
  // DACH-Server kennt: AT (alle), CH (alle), LI, BW lat≥48.3
  const inDachServerArea =
    // Österreich grob 46.4-49.0, 9.5-17.2
    (lat >= 46.4 && lat <= 49.0 && lng >= 9.5 && lng <= 17.2) ||
    // Schweiz grob 45.8-47.8, 5.9-10.5
    (lat >= 45.8 && lat <= 47.8 && lng >= 5.9 && lng <= 10.5) ||
    // BW lat≥48.3 (mein clip), 7.5-10.5
    (lat >= 48.3 && lat <= 49.8 && lng >= 7.5 && lng <= 10.5);
  if (inDachServerArea) {
    return { primary: GRAPHHOPPER_URL, fallback: GRAPHHOPPER_DE_URL };
  }
  // DE-Areas die NICHT im DACH-Server drin: Bayern, BW-Süd (Friedrichshafen),
  // restliches Deutschland (Hessen, Berlin, NRW...)
  return { primary: GRAPHHOPPER_DE_URL, fallback: GRAPHHOPPER_URL };
}

// ─────────────────────────── Types ────────────────────────────────────────

interface RouteRequest {
  route_type?: 'ROUND_TRIP' | 'POINT_TO_POINT';
  // Flutter-Client sendet die Felder in camelCase, alte Mapbox-Edge nutzte
  // snake_case. Wir akzeptieren beide Schreibweisen damit der Adapter direkt
  // gegen den unveränderten Flutter-Code funktioniert.
  start_location?: { latitude: number; longitude: number };
  startLocation?: { latitude: number; longitude: number };
  target_location?: { latitude: number; longitude: number };
  targetLocation?: { latitude: number; longitude: number };
  // Distanz: target_distance_km (v2-Native) ODER targetDistance (Flutter, in km)
  target_distance_km?: number;
  targetDistance?: number;
  // Style: selected_style (v2) ODER mode (Flutter)
  selected_style?: string;
  mode?: string;
  avoid_highways?: boolean;
  force_fresh_variant?: boolean;
  forceFreshVariant?: boolean;
  previous_route_fingerprints?: string[];
  client_trigger?: string;
  // 2026-05-22 (Task #41): A→B Detour-Level (0=direkt, 1=klein, 2=mittel, 3=groß)
  detour_level?: number;
  detourLevel?: number;
  // 2026-05-22 (Task #42): Explicit user-waypoints (zwischen start + end)
  waypoints?: Array<{ latitude: number; longitude: number }>;
}

// Normalisierung: ergänzt fehlende v2-Felder aus den Flutter-Aliassen
function normalizeRequest(raw: RouteRequest): RouteRequest {
  return {
    ...raw,
    route_type: raw.route_type ?? 'ROUND_TRIP',
    start_location: raw.start_location ?? raw.startLocation,
    target_location: raw.target_location ?? raw.targetLocation,
    target_distance_km: raw.target_distance_km ?? raw.targetDistance,
    selected_style: raw.selected_style ?? raw.mode,
    force_fresh_variant: raw.force_fresh_variant ?? raw.forceFreshVariant,
    detour_level: raw.detour_level ?? raw.detourLevel ?? 0,
  };
}

interface GraphHopperPath {
  distance: number; // meters
  time: number; // ms
  ascend?: number;
  descend?: number;
  points: { type: string; coordinates: [number, number][] };
  points_encoded: boolean;
  bbox: [number, number, number, number];
  instructions?: Array<Record<string, unknown>>;
}

interface GraphHopperResponse {
  paths?: GraphHopperPath[];
  message?: string;
  hints?: unknown[];
}

// ─────────────────── Style-Mapping ────────────────────────────────────────

const STYLE_TO_PROFILE: Record<string, string> = {
  'sport mode': 'motorcycle_scenic',
  'sport_mode': 'motorcycle_scenic',
  'sport': 'motorcycle_scenic',
  'kurvenjagd': 'motorcycle_kurvenjagd',
  'kurvenreich': 'motorcycle_kurvenjagd',
  'abendrunde': 'motorcycle_abendrunde',
  'panorama': 'motorcycle_abendrunde',
  'entdecker': 'motorcycle_entdecker',
  'erkundung': 'motorcycle_entdecker',
};

function resolveProfile(style: string | undefined): string {
  if (!style) return 'motorcycle_scenic';
  const key = style.trim().toLowerCase();
  return STYLE_TO_PROFILE[key] ?? 'motorcycle_scenic';
}

// 2026-05-21: Style-Overlay als Runtime-Custom-Model — verschärft die
// Charakter-Unterschiede zwischen den 4 Profilen ohne den Graph-Cache zu
// invalidieren (GH hasht Baseline-Profile in den Cache).
//
// distance_influence:
//   niedrig (60-120)  → bevorzugt Umwege/Kurven (Sport, Kurvenjagd)
//   mittel  (180-220) → balanciert
//   hoch    (260-340) → bevorzugt direkten Weg (Abendrunde)
interface StyleOverlay {
  priority: Array<{ if: string; multiply_by: string }>;
  distance_influence?: number;
}
function styleOverlayForProfile(profile: string): StyleOverlay {
  switch (profile) {
    case 'motorcycle_kurvenjagd':
      // Maximum Kurven, kleine Strassen, Bergstrecken
      return {
        priority: [
          { if: 'road_class == TERTIARY', multiply_by: '1.4' },
          { if: 'road_class == UNCLASSIFIED', multiply_by: '1.3' },
          { if: 'curvature < 0.7', multiply_by: '1.5' },
          { if: 'curvature < 0.5', multiply_by: '1.8' },
          { if: 'road_class == RESIDENTIAL', multiply_by: '0.4' },
        ],
        distance_influence: 80,
      };
    case 'motorcycle_scenic':
      // Sport: schöne offene curvy roads, secondary bevorzugt
      return {
        priority: [
          { if: 'road_class == SECONDARY', multiply_by: '1.35' },
          { if: 'road_class == PRIMARY', multiply_by: '1.15' },
          { if: 'curvature < 0.75', multiply_by: '1.3' },
          { if: 'road_class == RESIDENTIAL', multiply_by: '0.6' },
        ],
        distance_influence: 150,
      };
    case 'motorcycle_abendrunde':
      // Kurze gemütliche Feierabend-Tour, weniger anstrengende Kurven
      return {
        priority: [
          { if: 'road_class == PRIMARY', multiply_by: '1.3' },
          { if: 'road_class == SECONDARY', multiply_by: '1.4' },
          { if: 'road_class == RESIDENTIAL', multiply_by: '1.1' },
          { if: 'curvature < 0.5', multiply_by: '0.8' },
        ],
        distance_influence: 280,
      };
    case 'motorcycle_entdecker':
      // Tertiary + variety, längere distance_influence (eher direkter Weg)
      return {
        priority: [
          { if: 'road_class == TERTIARY', multiply_by: '1.5' },
          { if: 'road_class == UNCLASSIFIED', multiply_by: '1.3' },
          { if: 'road_class == RESIDENTIAL', multiply_by: '1.1' },
        ],
        distance_influence: 180,
      };
    default:
      return { priority: [] };
  }
}

// ─────────────────── Adaptive Distance-Compensation ───────────────────────

interface RegionProfile {
  factor: number;
  label: string;
}

// Klassifiziert User-Standort in "alpine", "alpenanrand", "flatland".
// Basis: Latitude + Longitude (grobe Geofences DACH).
function classifyRegion(lat: number, lng: number): RegionProfile {
  // Alpine: Vorarlberg + Tirol + CH-Alpen + Liechtenstein
  const inVorarlbergTirol = lat >= 46.5 && lat <= 47.55 && lng >= 9.4 && lng <= 12.6;
  const inLiechtenstein = lat >= 47.04 && lat <= 47.27 && lng >= 9.47 && lng <= 9.64;
  const inCHAlpen = lat >= 46.0 && lat <= 47.0 && lng >= 6.8 && lng <= 10.5;
  if (inVorarlbergTirol || inLiechtenstein || inCHAlpen) {
    // 2026-05-21: 0.90 best-balance — höhere Compensation schießt Bregenz
    // über Target, niedrigere lässt es zu kurz. Innsbruck/Feldkirch bleiben
    // Outlier (Reachable Area in Bergtälern zu klein für 50km Round-Trip).
    return { factor: 0.90, label: 'alpine' };
  }

  // Alpenanrand: Allgäu + Bodensee-Süd + Salzburg-Region + CH-Mittelland-Süd
  const inAllgaeuBodensee = lat >= 47.3 && lat <= 47.85 && lng >= 9.5 && lng <= 10.8;
  const inSalzburgRegion = lat >= 47.5 && lat <= 48.2 && lng >= 12.5 && lng <= 13.8;
  // 2026-05-21 (vucko): Obersteiermark (Leoben/Bruck/Mariazell/Liezen) sind
  // bergisch — Regression-Test fand 29-53% over-target wegen falscher
  // flatland-Klassifikation. Alpenanrand 0.92 zieht effective_target enger.
  const inObersteiermark = lat >= 47.3 && lat <= 47.85 && lng >= 14.0 && lng <= 15.7;
  if (inAllgaeuBodensee || inSalzburgRegion || inObersteiermark) {
    return { factor: 0.92, label: 'alpenanrand' };
  }

  // Default: flatland (Wien/Linz/Graz/Zürich/Bern/Stuttgart-Nord/...).
  return { factor: 1.0, label: 'flatland' };
}

// ─────────────────── Route-Fingerprint (für previous-fingerprint-Check) ───

function buildFingerprint(coords: [number, number][], distanceKm: number): string {
  // Format: n:<count>|d:<km>|<lng,lat>×10 sample
  const sampled = sampleCoordinates(coords, 10);
  const parts = sampled.map(c => `${c[0].toFixed(4)},${c[1].toFixed(4)}`).join('|');
  return `n:${coords.length}|d:${distanceKm.toFixed(1)}|${parts}`;
}

function sampleCoordinates(coords: [number, number][], n: number): [number, number][] {
  if (coords.length <= n) return coords;
  const step = (coords.length - 1) / (n - 1);
  return Array.from({ length: n }, (_, i) => coords[Math.round(i * step)]);
}

// ─────────────────── GraphHopper-Call ─────────────────────────────────────

interface RouteResult {
  geometry: GraphHopperPath['points'];
  distanceKm: number;
  durationSeconds: number;
  ascent: number;
  coordinateCount: number;
  fingerprint: string;
  meta: Record<string, unknown>;
}

// ─────────────────── Geo-Helpers (A→B Detour, Task #41) ─────────────────

function bearingDeg(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const toDeg = (r: number) => (r * 180) / Math.PI;
  const φ1 = toRad(lat1), φ2 = toRad(lat2);
  const Δλ = toRad(lng2 - lng1);
  const y = Math.sin(Δλ) * Math.cos(φ2);
  const x = Math.cos(φ1) * Math.sin(φ2) - Math.sin(φ1) * Math.cos(φ2) * Math.cos(Δλ);
  return (toDeg(Math.atan2(y, x)) + 360) % 360;
}

function offsetCoord(lat: number, lng: number, distKm: number, bearingDeg_: number): { lat: number; lng: number } {
  const R = 6371; // km Earth radius
  const toRad = (d: number) => (d * Math.PI) / 180;
  const toDeg = (r: number) => (r * 180) / Math.PI;
  const φ1 = toRad(lat), λ1 = toRad(lng);
  const θ = toRad(bearingDeg_);
  const φ2 = Math.asin(Math.sin(φ1) * Math.cos(distKm / R)
    + Math.cos(φ1) * Math.sin(distKm / R) * Math.cos(θ));
  const λ2 = λ1 + Math.atan2(
    Math.sin(θ) * Math.sin(distKm / R) * Math.cos(φ1),
    Math.cos(distKm / R) - Math.sin(φ1) * Math.sin(φ2),
  );
  return { lat: toDeg(φ2), lng: toDeg(λ2) };
}

// ─────────────────── Style-Quality Metriken ───────────────────────────────
//
// 2026-05-21 (vucko): User-Beschwerde "Sport hat manchmal nur 10 Kurven".
// Wir berechnen die Kurven-Dichte (turns >30°/km) und vergleichen sie mit
// einem Profile-spezifischen Minimum. Routes unter dem Min bekommen Penalty
// im Best-of-N-Ranking, nicht hard-reject (sonst NO_ROUTE in alpine).

function countSignificantTurns(coords: [number, number][]): number {
  if (coords.length < 3) return 0;
  let turns = 0;
  for (let i = 2; i < coords.length; i++) {
    const a = coords[i - 2], b = coords[i - 1], c = coords[i];
    const v1x = b[0] - a[0], v1y = b[1] - a[1];
    const v2x = c[0] - b[0], v2y = c[1] - b[1];
    const dot = v1x * v2x + v1y * v2y;
    const cross = v1x * v2y - v1y * v2x;
    if (dot === 0 && cross === 0) continue;
    const angle = Math.abs(Math.atan2(cross, dot) * 180 / Math.PI);
    if (angle > 30) turns++;
  }
  return turns;
}

function minTurnsPerKmForProfile(profile: string): number {
  switch (profile) {
    case 'motorcycle_kurvenjagd': return 1.4;
    case 'motorcycle_scenic':    return 1.0;  // Sport: ≥50 Kurven für 50km
    case 'motorcycle_entdecker': return 0.6;
    case 'motorcycle_abendrunde':return 0.3;
    default: return 0.5;
  }
}

async function callGraphHopper(opts: {
  startLat: number;
  startLng: number;
  endLat?: number;
  endLng?: number;
  profile: string;
  isRoundTrip: boolean;
  targetDistanceKm?: number;
  seed?: number;
  avoidHighways: boolean;
  serverUrl?: string;
  // 2026-05-22 (vucko Task #41): A→B Detour via Sub-Waypoint
  // detourBearing/detourDistance bestimmen die Lage des Mittelpunkts
  // senkrecht zur direkten Linie. Ohne diese Felder = direkte Route.
  detourBearingDeg?: number;
  detourPerpendicularKm?: number;
  // Custom waypoints (zwischen start + end, in order)
  intermediateWaypoints?: Array<{ lat: number; lng: number }>;
}): Promise<RouteResult | { error: string }> {
  const params = new URLSearchParams();
  params.append('point', `${opts.startLat},${opts.startLng}`);

  // A→B: füge sub-waypoint(s) für detour-Charakter
  if (!opts.isRoundTrip && opts.endLat != null && opts.endLng != null) {
    // Explicit waypoints zuerst (für Wegpunkte-Mode)
    if (opts.intermediateWaypoints && opts.intermediateWaypoints.length > 0) {
      for (const wp of opts.intermediateWaypoints) {
        params.append('point', `${wp.lat},${wp.lng}`);
      }
    }
    // Auto-detour via senkrecht-Offset (klein/mittel/groß umweg)
    else if (opts.detourPerpendicularKm != null && opts.detourPerpendicularKm > 0
          && opts.detourBearingDeg != null) {
      const midLat = (opts.startLat + opts.endLat) / 2;
      const midLng = (opts.startLng + opts.endLng) / 2;
      // Senkrecht zur direkten Linie:
      const directBearing = bearingDeg(opts.startLat, opts.startLng, opts.endLat, opts.endLng);
      const perpBearing = (directBearing + opts.detourBearingDeg + 360) % 360;
      const offset = offsetCoord(midLat, midLng, opts.detourPerpendicularKm, perpBearing);
      params.append('point', `${offset.lat},${offset.lng}`);
    }
    params.append('point', `${opts.endLat},${opts.endLng}`);
  }
  params.set('profile', opts.profile);
  params.set('points_encoded', 'false');
  params.set('ch.disable', 'true');
  params.set('instructions', 'true');

  if (opts.isRoundTrip) {
    params.set('algorithm', 'round_trip');
    if (opts.targetDistanceKm) {
      params.set('round_trip.distance', String(Math.round(opts.targetDistanceKm * 1000)));
    }
    if (opts.seed != null) {
      params.set('round_trip.seed', String(opts.seed));
    }
  }

  // 2026-05-21 (vucko): Stil-Differenzierung als Runtime-Overlay statt
  // Baseline-Profile-Änderung (die wäre ein Graph-Re-Import). Custom-Model
  // wird zusätzlich zum Profile angewandt — verschärft die Charakter-
  // Unterschiede zwischen Sport/Kurvenjagd/Abendrunde/Entdecker.
  const customOverlay = styleOverlayForProfile(opts.profile);
  const overlay: { priority: Array<{ if: string; multiply_by: string }>; distance_influence?: number } = {
    priority: [...customOverlay.priority],
  };
  if (customOverlay.distance_influence != null) {
    overlay.distance_influence = customOverlay.distance_influence;
  }
  // Autobahn-Vermeidung als Top-Up
  if (opts.avoidHighways) {
    overlay.priority.push({ if: 'road_class == MOTORWAY || road_class == TRUNK', multiply_by: '0.05' });
  }
  if (overlay.priority.length > 0 || overlay.distance_influence != null) {
    params.set('custom_model', JSON.stringify(overlay));
  }

  const baseUrl = opts.serverUrl ?? GRAPHHOPPER_URL;
  const url = `${baseUrl}/route?${params.toString()}`;
  try {
    const res = await fetch(url);
    if (!res.ok) {
      return { error: `GraphHopper HTTP ${res.status}: ${await res.text().then(t => t.slice(0, 200))}` };
    }
    const data: GraphHopperResponse = await res.json();
    if (!data.paths || data.paths.length === 0) {
      return { error: data.message ?? 'GraphHopper returned no paths' };
    }
    const p = data.paths[0];
    const coords = p.points.coordinates;
    const distanceKm = p.distance / 1000;
    return {
      geometry: p.points,
      distanceKm,
      durationSeconds: p.time / 1000,
      ascent: p.ascend ?? 0,
      coordinateCount: coords.length,
      fingerprint: buildFingerprint(coords, distanceKm),
      meta: {
        route_source: 'graphhopper',
        engine: 'graphhopper-8',
        profile: opts.profile,
        bbox: p.bbox,
      },
    };
  } catch (e) {
    return { error: `GraphHopper fetch failed: ${(e as Error).message}` };
  }
}

// ─────────────────── Route-Generation mit Retries + Compensation ───────────

async function generateRoute(req: RouteRequest): Promise<Response> {
  const profile = resolveProfile(req.selected_style);
  const isRoundTrip = req.route_type === 'ROUND_TRIP';
  const previousFps = new Set(req.previous_route_fingerprints ?? []);

  // Adaptive Distance Compensation (nur für Round-Trip relevant)
  const region = classifyRegion(req.start_location.latitude, req.start_location.longitude);
  const effectiveDistanceKm = isRoundTrip && req.target_distance_km
    ? req.target_distance_km * region.factor
    : req.target_distance_km;

  // Seed-Strategie für Round-Trip:
  // - Initial Search: seed aus Hash(startLat, startLng, distance) — deterministisch erste Variante
  // - Search Again (force_fresh): seed aus Timestamp + 137° rotation (Calimoto-Pattern)
  // - Retry bei previous fingerprint match: nächster seed
  const seeds = generateSeeds({
    forceFresh: req.force_fresh_variant ?? false,
    startLat: req.start_location.latitude,
    startLng: req.start_location.longitude,
    targetKm: req.target_distance_km ?? 50,
  });

  // PARALLEL Best-of-N statt sequenziell (Latenz-Optimierung 2026-05-21):
  // Vorher: bis zu 4 sequenzielle GraphHopper-Calls × 0.3-0.8s = 1.2-3.2s total.
  // Jetzt: 5 parallele Calls in Promise.all → max(call_time) ≈ 0.3-0.8s total.
  // 5 statt 3 weil Friedrichshafen-Test (Bodensee) zeigte: seed-Failures sind
  // häufiger als gedacht. Mit 5 Versuchen finden wir fast immer 1-2 saubere.
  //
  // 2026-05-21 (vucko): Bei Search-Again oder mit recent-Fingerprints 8 Seeds
  // statt 5 — User-Beschwerde "Routen überschneiden sich". Mehr Seeds = höhere
  // Chance dass mindestens einer in den vorherigen Routen nicht enthalten ist.
  const needsDiversity = (req.force_fresh_variant ?? false) || previousFps.size > 0;

  // 2026-05-22 (Task #41): A→B Detour-Multi-Variant
  // Bei detour_level > 0 generieren wir parallele Routen mit verschiedenen
  // Sub-Waypoint-Positionen (senkrecht zur direkten Linie). Best-of-N wählt
  // dann die mit dem besten Score (style + speed + distance-fit).
  // detour_level 0 = direkt (1 Versuch)
  // detour_level 1 = klein (Sub-WP 3-5 km senkrecht, 3 Versuche)
  // detour_level 2 = mittel (Sub-WP 6-12 km, 4 Versuche)
  // detour_level 3 = groß (Sub-WP 12-25 km, 5 Versuche)
  const detourLevel = isRoundTrip ? 0 : (req.detour_level ?? 0);
  const detourSpec: Array<{ bearing: number; distKm: number }> = [];
  if (!isRoundTrip && req.target_location && detourLevel > 0) {
    const directKm = (() => {
      const R = 6371;
      const toRad = (d: number) => (d * Math.PI) / 180;
      const dLat = toRad(req.target_location.latitude - req.start_location.latitude);
      const dLng = toRad(req.target_location.longitude - req.start_location.longitude);
      const a = Math.sin(dLat/2)**2 + Math.cos(toRad(req.start_location.latitude))
        * Math.cos(toRad(req.target_location.latitude)) * Math.sin(dLng/2)**2;
      return 2 * R * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    })();
    // Sub-WP-Distanz als Anteil der direkten Distanz, MODULIERT vom Profil:
    // Sport/Kurvenjagd: mehr Umweg → curvy roads
    // Abendrunde: weniger Umweg → entspannt
    // Entdecker: medium
    const profileDetourMultiplier = profile === 'motorcycle_kurvenjagd' ? 1.4
      : profile === 'motorcycle_scenic' ? 1.15
      : profile === 'motorcycle_abendrunde' ? 0.7
      : profile === 'motorcycle_entdecker' ? 1.0
      : 1.0;
    const baseFactor = detourLevel === 1 ? 0.15 : detourLevel === 2 ? 0.30 : 0.50;
    const baseKm = Math.max(2, directKm * baseFactor * profileDetourMultiplier);
    // Bearing-Sets pro Stil unterschiedlich damit Routes sich klar
    // unterscheiden (sonst pickt GH die kürzeste path egal welches profile).
    const bearingsForStyle = profile === 'motorcycle_kurvenjagd'
      ? [90, -90, 120, -120]  // breit + tief — viele Optionen
      : profile === 'motorcycle_scenic'
      ? [75, -75, 60, -60]    // schmaler Spread — Cruiser-feeling
      : profile === 'motorcycle_abendrunde'
      ? [60, -60, 45]         // wenig Umweg
      : [80, -80, 100, -100]; // entdecker: variability
    const limit = detourLevel === 1 ? 3 : detourLevel === 2 ? 4 : 5;
    for (const b of bearingsForStyle.slice(0, limit)) {
      detourSpec.push({ bearing: b, distKm: baseKm });
    }
  }
  const hasExplicitWaypoints = !isRoundTrip && (req.waypoints?.length ?? 0) > 0;

  // maxAttempts pro Modus
  const maxAttempts = isRoundTrip
    ? (needsDiversity ? 8 : 5)
    : (hasExplicitWaypoints ? 1 : Math.max(1, detourSpec.length));
  const targetKm = req.target_distance_km ?? 50;
  const candidates: Array<{ result: RouteResult; deltaPct: number; seed: number; isDup: boolean }> = [];
  let bestCandidate: RouteResult | null = null;
  let lastError = 'unknown';

  const candidateSeeds = seeds.slice(0, maxAttempts);
  // Server-Wahl basierend auf User-Position
  const serverChoice = chooseGraphhopperUrl(
    req.start_location.latitude,
    req.start_location.longitude,
  );
  const tryServerWithProfile = async (
    serverUrl: string,
    profileToUse: string,
    latOffset: number = 0,
    lngOffset: number = 0,
  ) => {
    if (isRoundTrip) {
      return await Promise.all(
        candidateSeeds.map(seed =>
          callGraphHopper({
            startLat: req.start_location!.latitude + latOffset,
            startLng: req.start_location!.longitude + lngOffset,
            endLat: req.target_location?.latitude,
            endLng: req.target_location?.longitude,
            profile: profileToUse,
            isRoundTrip,
            targetDistanceKm: effectiveDistanceKm,
            seed,
            avoidHighways: req.avoid_highways ?? false,
            serverUrl,
          }).then(result => ({ result, seed })),
        ),
      );
    }
    // A→B mode
    if (hasExplicitWaypoints) {
      return [await callGraphHopper({
        startLat: req.start_location!.latitude,
        startLng: req.start_location!.longitude,
        endLat: req.target_location!.latitude,
        endLng: req.target_location!.longitude,
        profile: profileToUse,
        isRoundTrip: false,
        avoidHighways: req.avoid_highways ?? false,
        serverUrl,
        intermediateWaypoints: req.waypoints!.map(w => ({ lat: w.latitude, lng: w.longitude })),
      }).then(result => ({ result, seed: 0 }))];
    }
    if (detourSpec.length === 0) {
      // Direkter A→B (detourLevel 0)
      return [await callGraphHopper({
        startLat: req.start_location!.latitude,
        startLng: req.start_location!.longitude,
        endLat: req.target_location!.latitude,
        endLng: req.target_location!.longitude,
        profile: profileToUse,
        isRoundTrip: false,
        avoidHighways: req.avoid_highways ?? false,
        serverUrl,
      }).then(result => ({ result, seed: 0 }))];
    }
    // detourLevel > 0: parallel mit verschiedenen Sub-Waypoint-Positionen
    return await Promise.all(
      detourSpec.map((spec, idx) =>
        callGraphHopper({
          startLat: req.start_location!.latitude,
          startLng: req.start_location!.longitude,
          endLat: req.target_location!.latitude,
          endLng: req.target_location!.longitude,
          profile: profileToUse,
          isRoundTrip: false,
          avoidHighways: req.avoid_highways ?? false,
          serverUrl,
          detourBearingDeg: spec.bearing,
          detourPerpendicularKm: spec.distKm,
        }).then(result => ({ result, seed: idx })),
      ),
    );
  };
  // 2026-05-21 (vucko Task #32): Mehrstufiger Fallback:
  // 1. primary Server, gewünschtes Profil
  // 2. fallback Server, gewünschtes Profil
  // 3. primary mit motorcycle_entdecker (permissive profile)
  // 4. Point-Offset ~100m (Punkt landete evtl auf Autobahn die alle Profile
  //    filtern → "Cannot find valid point", Schladming-Bug)
  let parallel = await tryServerWithProfile(serverChoice.primary, profile);
  let usedProfileFallback = false;
  const primaryAllFailed = parallel.every(p => 'error' in p.result);
  if (primaryAllFailed && serverChoice.primary !== serverChoice.fallback) {
    console.log(`Primary server all failed, trying fallback server`);
    parallel = await tryServerWithProfile(serverChoice.fallback, profile);
  }
  const bothServersFailed = parallel.every(p => 'error' in p.result);
  if (bothServersFailed && profile !== 'motorcycle_entdecker') {
    console.log(`Both servers failed with profile ${profile}, trying motorcycle_entdecker as fallback`);
    parallel = await tryServerWithProfile(serverChoice.primary, 'motorcycle_entdecker');
    const primaryEntdeckerFailed = parallel.every(p => 'error' in p.result);
    if (primaryEntdeckerFailed && serverChoice.primary !== serverChoice.fallback) {
      parallel = await tryServerWithProfile(serverChoice.fallback, 'motorcycle_entdecker');
    }
    usedProfileFallback = !parallel.every(p => 'error' in p.result);
  }
  // Letzte Eskalation: Punkt landete evtl auf Autobahn → 8 offset-Versuche
  // in 45°-Schritten mit motorcycle_entdecker (permissivstes profile).
  // 0.0015° ≈ 100-150m — weit genug um auf Nebenstraße zu landen.
  const stillAllFailed = parallel.every(p => 'error' in p.result);
  if (stillAllFailed) {
    console.log(`All profile fallbacks failed, trying point-offset in 8 directions with entdecker`);
    const offsets: Array<[number, number]> = [
      [ 0.0015,  0     ], [ 0.0011,  0.0011], [ 0,       0.0015], [-0.0011,  0.0011],
      [-0.0015,  0     ], [-0.0011, -0.0011], [ 0,      -0.0015], [ 0.0011, -0.0011],
    ];
    for (const [dLat, dLng] of offsets) {
      parallel = await tryServerWithProfile(serverChoice.primary, 'motorcycle_entdecker', dLat, dLng);
      if (!parallel.every(p => 'error' in p.result)) {
        usedProfileFallback = true; // markiere als degraded
        break;
      }
    }
  }

  // 2026-05-21 (vucko): Style-Quality-Scoring damit Sport nicht zu wenig
  // Kurven hat. Berechnet turn-count und shape-quality. Bei profile-specific
  // Minimum unterschritten → Penalty im Score, nicht hard reject.
  for (const { result, seed } of parallel) {
    if ('error' in result) {
      lastError = result.error;
      continue;
    }
    const isDup = previousFps.has(result.fingerprint);
    const deltaPct = Math.abs(result.distanceKm - targetKm) / targetKm * 100;
    candidates.push({ result, deltaPct, seed, isDup });
  }

  // Style-Quality-Bonus: bevorzuge Routen die zum gewählten Stil passen.
  // Min Turn-Count / km (Sport ≥0.8, Kurvenjagd ≥1.2, Abendrunde ≥0.3, Entdecker ≥0.5)
  const minTurnsPerKm = minTurnsPerKmForProfile(profile);
  const scored = candidates.map(c => {
    const turns = countSignificantTurns(c.result.geometry.coordinates as [number, number][]);
    const turnsPerKm = c.result.distanceKm > 0 ? turns / c.result.distanceKm : 0;
    const turnDeficit = Math.max(0, minTurnsPerKm - turnsPerKm);
    const stylePenalty = Math.min(30, turnDeficit * 25);
    // 2026-05-21 (vucko v2): Speed-Penalty verschärft + isUnreasonablySlow Flag.
    // User-Befund: Friedrichshafen-Bahnhof-Start → erste 2-3km Hafen/City mit
    // Tempo-30 zieht avg_speed bei kurzen Routes massiv runter (12-28 km/h).
    // Diese Routes liefern UX wie "EMERGENCY_FALLBACK".
    //
    // Neuer Schwellwert: <35 km/h für ≥75km Routes, <30 km/h für 25-50km.
    // Solche Routes bekommen +60 Penalty (effectiv hard-reject im Best-of-N,
    // aber als allerletzter Fallback noch nutzbar wenn alle anderen failen).
    const avgSpeedKmh = c.result.durationSeconds > 0
      ? (c.result.distanceKm / (c.result.durationSeconds / 3600))
      : 50;
    const minAcceptableSpeed = c.result.distanceKm >= 75 ? 35 : 30;
    const speedDeficit = Math.max(0, minAcceptableSpeed - avgSpeedKmh);
    const isUnreasonablySlow = avgSpeedKmh > 0 && avgSpeedKmh < minAcceptableSpeed;
    // Penalty: bis +25 für soft (innerhalb Tolerance), +60 für unreasonable
    const speedPenalty = isUnreasonablySlow
      ? 60 + Math.min(20, speedDeficit * 0.8)
      : Math.min(25, speedDeficit * 1.5);
    return {
      ...c, turns, turnsPerKm, stylePenalty, speedPenalty, avgSpeedKmh,
      isUnreasonablySlow,
      score: c.deltaPct + stylePenalty + speedPenalty,
    };
  });

  // Best non-duplicate mit niedrigstem combined Score.
  // Zuerst nur "reasonable speed" Routes betrachten (nicht isUnreasonablySlow).
  // Nur wenn ALLE slow sind, fallback auf besten slow.
  const nonDupReasonable = scored.filter(c => !c.isDup && !c.isUnreasonablySlow)
    .sort((a, b) => a.score - b.score);
  if (nonDupReasonable.length > 0) {
    bestCandidate = nonDupReasonable[0].result;
  } else {
    const nonDupAny = scored.filter(c => !c.isDup).sort((a, b) => a.score - b.score);
    if (nonDupAny.length > 0) {
      bestCandidate = nonDupAny[0].result;
    } else if (scored.length > 0) {
      scored.sort((a, b) => a.score - b.score);
      bestCandidate = scored[0].result;
    }
  }

  if (bestCandidate) {
    const selectedCandidate = candidates.find(c => c.result.fingerprint === bestCandidate!.fingerprint);
    const selectedScored = scored.find(c => c.result.fingerprint === bestCandidate!.fingerprint);
    // V1-kompatible Response-Struktur damit Flutter route_service.dart
    // unverändert weiter funktioniert. Felder die der alte Mapbox-Code parst:
    //   route.geometry, route.distance (in METER), route.duration (in SEKUNDEN)
    //   meta.route_source, meta.route_fingerprint, meta.distance_km
    //
    // 2026-05-21 BUGFIX (vucko): Mapbox Directions API liefert duration in
    // SEKUNDEN (nicht ms wie initial gedacht). Flutter parser nimmt duration
    // direkt als durationSeconds — ms hier hätte 1000× zu lange Anzeige.
    // (Symptom: "1029h 49min" für 51km Route)
    return jsonResponse({
      route: {
        geometry: bestCandidate.geometry,
        distance: Math.round(bestCandidate.distanceKm * 1000), // METER (v1 compat)
        duration: Math.round(bestCandidate.durationSeconds), // SEKUNDEN (Mapbox-Spec)
        // Zusätzliche v2-Felder (optional, nicht-breaking):
        distance_km: Number(bestCandidate.distanceKm.toFixed(2)),
        duration_seconds: Math.round(bestCandidate.durationSeconds),
        ascent_meters: Math.round(bestCandidate.ascent),
        coordinate_count: bestCandidate.coordinateCount,
      },
      meta: {
        ...bestCandidate.meta,
        route_fingerprint: bestCandidate.fingerprint,
        attempts_used: candidates.length,
        delta_pct: Number((selectedCandidate?.deltaPct ?? 0).toFixed(1)),
        was_duplicate: selectedCandidate?.isDup ?? false,
        region: region.label,
        compensation_factor: region.factor,
        requested_target_km: req.target_distance_km,
        effective_target_km: Number(effectiveDistanceKm?.toFixed(1)),
        // v1-kompatible meta-Felder
        distance_km: Number(bestCandidate.distanceKm.toFixed(2)),
        duration_seconds: Math.round(bestCandidate.durationSeconds),
        // Style-Quality (turn-density Vergleich gegen Profile-Min)
        turn_count: selectedScored?.turns ?? 0,
        turns_per_km: Number((selectedScored?.turnsPerKm ?? 0).toFixed(2)),
        style_penalty: Number((selectedScored?.stylePenalty ?? 0).toFixed(1)),
        avg_speed_kmh: Number((selectedScored?.avgSpeedKmh ?? 0).toFixed(1)),
        speed_penalty: Number((selectedScored?.speedPenalty ?? 0).toFixed(1)),
        profile_fallback_used: usedProfileFallback,
      },
    });
  }

  // Alle Seeds liefen ins Leere — entweder kein valid point oder nur Duplikate
  return jsonResponse({
    error: 'no_route',
    user_message: 'Konnte aktuell keine passende Route generieren. Probier andere Distanz oder Stil.',
    debug_message: lastError,
    region: region.label,
    attempts: Math.min(maxAttempts, seeds.length),
  }, 502);
}

// ─────────────────── Seed-Generation ──────────────────────────────────────

function generateSeeds(opts: {
  forceFresh: boolean;
  startLat: number;
  startLng: number;
  targetKm: number;
}): number[] {
  // Erkenntnis 2026-05-21 (Friedrichshafen-Test): Round-Trip Algorithmus von
  // GraphHopper hat seed-spezifische Failures wenn Sub-Waypoints in Wasser /
  // Bergen / unbestraßten Bereichen landen. Lösung: viele, breit gestreute
  // Seeds (statt 5 nah beieinander Werte) damit immer mindestens 2-3 davon
  // saubere Sub-Waypoints treffen.
  if (opts.forceFresh) {
    const base = Date.now() % 1_000_000;
    return [
      base, base + 7, base + 13, base + 137, base + 274,
      base + 411, base + 1337, base + 9999, base + 31337, base + 100003,
    ];
  }
  const h = Math.abs(
    Math.round(opts.startLat * 1000) * 31 +
    Math.round(opts.startLng * 1000) * 17 +
    Math.round(opts.targetKm) * 7,
  );
  // 10 breit gestreute Seeds — Mix von engen und breiten Offsets damit auch
  // alpine Regionen (wo viele Seeds in Berge/Wasser landen) zumindest 1-2
  // Treffer in den top-5 haben. Empirisch beste Anordnung 2026-05-21.
  return [
    (h + 13) % 100000,
    (h + 137) % 100000,
    (h + 1337) % 100000,
    (h + 411) % 100000,
    (h + 9999) % 100000,
    (h + 29) % 100000,
    (h + 4111) % 100000,
    (h + 31337) % 100000,
    (h + 3) % 100000,
    (h + 7) % 100000,
  ];
}

// ─────────────────── HTTP-Handling ────────────────────────────────────────

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': ALLOWED_ORIGINS,
      'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
  });
}

async function handler(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: {
        'Access-Control-Allow-Origin': ALLOWED_ORIGINS,
        'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      },
    });
  }
  const url = new URL(req.url);
  if (url.pathname.endsWith('/health')) {
    // Probe upstream GH health
    try {
      const r = await fetch(`${GRAPHHOPPER_URL}/health`);
      const ok = r.ok;
      return jsonResponse({ ok, graphhopper: ok ? 'up' : 'down' }, ok ? 200 : 503);
    } catch (_) {
      return jsonResponse({ ok: false, graphhopper: 'unreachable' }, 503);
    }
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'method_not_allowed' }, 405);
  }
  let raw: RouteRequest;
  try {
    raw = await req.json();
  } catch (_) {
    return jsonResponse({ error: 'invalid_json' }, 400);
  }
  const body = normalizeRequest(raw);
  if (!body.start_location?.latitude || !body.start_location?.longitude) {
    // Vermeide das Wort "missing/invalid" im error damit der Flutter-Mapper
    // diese nicht als Validation-Fehler "Rundkurs-Parameter sind ungültig"
    // interpretiert sondern den echten user_message zeigt.
    return jsonResponse({
      error: 'start_location_required',
      user_message: 'Standort ist nicht verfügbar — bitte App-Berechtigungen prüfen.',
      debug_message: 'Edge v2: neither start_location nor startLocation in request body',
    }, 400);
  }
  return await generateRoute(body);
}

serve(handler);
