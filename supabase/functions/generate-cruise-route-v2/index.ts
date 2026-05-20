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
const ALLOWED_ORIGINS = '*';

// ─────────────────────────── Types ────────────────────────────────────────

interface RouteRequest {
  route_type: 'ROUND_TRIP' | 'POINT_TO_POINT';
  start_location: { latitude: number; longitude: number };
  target_location?: { latitude: number; longitude: number };
  target_distance_km?: number;
  selected_style?: string;
  avoid_highways?: boolean;
  force_fresh_variant?: boolean;
  previous_route_fingerprints?: string[];
  client_trigger?: string;
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

  const url = `${GRAPHHOPPER_URL}/route?${params.toString()}`;
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

  // Best-of-N Strategie statt Single-Seed:
  // Round-Trip-Distanzen variieren ±25% pro Seed (GH-Algorithmus ist stochastisch).
  // Wir sammeln bis zu 4 Kandidaten, nehmen den nähesten am Target.
  // Bei explicit Search Again (force_fresh): zusätzlich previous-fingerprint-Filter.
  const maxAttempts = isRoundTrip ? 4 : 1;
  let lastError = 'unknown';
  let bestCandidate: RouteResult | null = null;
  let bestDelta = Infinity;
  const targetKm = req.target_distance_km ?? 50;
  const candidates: Array<{ result: RouteResult; deltaPct: number; seed: number; isDup: boolean }> = [];

  for (let attempt = 0; attempt < Math.min(maxAttempts, seeds.length); attempt++) {
    const result = await callGraphHopper({
      startLat: req.start_location.latitude,
      startLng: req.start_location.longitude,
      endLat: req.target_location?.latitude,
      endLng: req.target_location?.longitude,
      profile,
      isRoundTrip,
      targetDistanceKm: effectiveDistanceKm,
      seed: seeds[attempt],
      avoidHighways: req.avoid_highways ?? false,
    });
    if ('error' in result) {
      lastError = result.error;
      continue;
    }
    const isDup = previousFps.has(result.fingerprint);
    const deltaPct = Math.abs(result.distanceKm - targetKm) / targetKm * 100;
    candidates.push({ result, deltaPct, seed: seeds[attempt], isDup });

    // Für Point-to-Point: erster valider Treffer reicht
    if (!isRoundTrip) {
      bestCandidate = result;
      break;
    }
    // Round-Trip: weiter sammeln, am Ende besten wählen
    if (deltaPct < bestDelta && !isDup) {
      bestCandidate = result;
      bestDelta = deltaPct;
    }
    // Early exit wenn schon sehr gut
    if (deltaPct < 10 && !isDup) break;
  }

  // Fallback: wenn alle non-duplicate Routes zu weit daneben, nimm duplicate-Route
  if (!bestCandidate && candidates.length > 0) {
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
  if (opts.forceFresh) {
    // Calimoto-Pattern: Timestamp-basiert + verschiedene Versuche
    const base = Date.now() % 1_000_000;
    return [base, base + 137, base + 274, base + 411, base + 9999, base + 31337];
  }
  // Initial: deterministischer Seed aus Position + Distanz
  const h = Math.abs(
    Math.round(opts.startLat * 1000) * 31 +
    Math.round(opts.startLng * 1000) * 17 +
    Math.round(opts.targetKm) * 7,
  );
  return [h % 100000, (h + 137) % 100000, (h + 274) % 100000, (h + 411) % 100000, (h + 9999) % 100000];
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
  let body: RouteRequest;
  try {
    body = await req.json();
  } catch (_) {
    return jsonResponse({ error: 'invalid_json' }, 400);
  }
  if (!body.start_location?.latitude || !body.start_location?.longitude) {
    return jsonResponse({ error: 'missing_start_location' }, 400);
  }
  return await generateRoute(body);
}

serve(handler);
