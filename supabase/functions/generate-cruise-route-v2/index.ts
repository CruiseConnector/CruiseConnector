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
  if (inAllgaeuBodensee || inSalzburgRegion) {
    return { factor: 1.00, label: 'alpenanrand' };
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
}): Promise<RouteResult | { error: string }> {
  const params = new URLSearchParams();
  params.append('point', `${opts.startLat},${opts.startLng}`);
  if (!opts.isRoundTrip && opts.endLat != null && opts.endLng != null) {
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

  // Custom-Model-Override für Autobahn-vermeidung
  if (opts.avoidHighways) {
    const customModel = {
      priority: [{ if: 'road_class == MOTORWAY || road_class == TRUNK', multiply_by: '0.05' }],
    };
    params.set('custom_model', JSON.stringify(customModel));
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
  const maxAttempts = isRoundTrip ? 5 : 1;
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
  const tryServer = async (serverUrl: string) => {
    return await Promise.all(
      candidateSeeds.map(seed =>
        callGraphHopper({
          startLat: req.start_location!.latitude,
          startLng: req.start_location!.longitude,
          endLat: req.target_location?.latitude,
          endLng: req.target_location?.longitude,
          profile,
          isRoundTrip,
          targetDistanceKm: effectiveDistanceKm,
          seed,
          avoidHighways: req.avoid_highways ?? false,
          serverUrl,
        }).then(result => ({ result, seed })),
      ),
    );
  };
  // Versuche primary, wenn alle fail → fallback server
  let parallel = await tryServer(serverChoice.primary);
  const primaryAllFailed = parallel.every(p => 'error' in p.result);
  if (primaryAllFailed && serverChoice.primary !== serverChoice.fallback) {
    console.log(`Primary server ${serverChoice.primary} all failed, trying fallback ${serverChoice.fallback}`);
    parallel = await tryServer(serverChoice.fallback);
  }

  for (const { result, seed } of parallel) {
    if ('error' in result) {
      lastError = result.error;
      continue;
    }
    const isDup = previousFps.has(result.fingerprint);
    const deltaPct = Math.abs(result.distanceKm - targetKm) / targetKm * 100;
    candidates.push({ result, deltaPct, seed, isDup });
  }

  // Best non-duplicate mit niedrigstem Delta
  const nonDupSorted = candidates.filter(c => !c.isDup).sort((a, b) => a.deltaPct - b.deltaPct);
  if (nonDupSorted.length > 0) {
    bestCandidate = nonDupSorted[0].result;
  } else if (candidates.length > 0) {
    // Fallback: alle waren Duplicates oder nichts non-dup → nimm besten duplicate
    candidates.sort((a, b) => a.deltaPct - b.deltaPct);
    bestCandidate = candidates[0].result;
  }

  if (bestCandidate) {
    const selectedCandidate = candidates.find(c => c.result.fingerprint === bestCandidate!.fingerprint);
    // V1-kompatible Response-Struktur damit Flutter route_service.dart
    // unverändert weiter funktioniert. Felder die der alte Mapbox-Code parst:
    //   route.geometry, route.distance (in METER), route.duration (in MILLISEKUNDEN)
    //   meta.route_source, meta.route_fingerprint, meta.distance_km
    return jsonResponse({
      route: {
        geometry: bestCandidate.geometry,
        distance: Math.round(bestCandidate.distanceKm * 1000), // METER (v1 compat)
        duration: Math.round(bestCandidate.durationSeconds * 1000), // MILLISEKUNDEN (v1 compat)
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
