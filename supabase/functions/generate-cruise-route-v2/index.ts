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
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const GRAPHHOPPER_URL = Deno.env.get('GRAPHHOPPER_URL') ?? 'http://graphhopper.local:8989';
// DE-Server (PC1 Port 8991) — kompakter Backup, aktuell mit Mittelost-Daten
// geseedet (TODO: PC1 neu seeden mit germany-latest).
const GRAPHHOPPER_DE_URL = Deno.env.get('GRAPHHOPPER_DE_URL') ?? GRAPHHOPPER_URL.replace(':8989', ':8991');
// 2026-05-24 (vucko PC2-Architektur): PC2 hostet erweitertes Europa-OSM
// (Italien, Frankreich, Spanien, Balkan, Beneluxx, Polen). Wird automatisch
// genutzt für alle Punkte AUSSER DACH, plus als Load-Balancing für DACH
// wenn PC1 stark belastet. Falls ENV nicht gesetzt → wir fallen auf
// PC1-DE-Server zurück (graceful degradation).
const GRAPHHOPPER_EU_URL = Deno.env.get('GRAPHHOPPER_EU_URL') ?? GRAPHHOPPER_DE_URL;
// 2026-06-02 (vucko Routing-Stabilität): Harte Obergrenze pro GraphHopper-Call.
// Ohne Timeout konnte ein hängender Round-Trip-Request die ganze Funktion bis
// zum Plattform-Limit blockieren → Client sah „Keine Verbindung zum Routing-
// Dienst". 9s deckt auch langsame Alpine-Loops ab, kappt aber echte Hänger.
const GH_FETCH_TIMEOUT_MS = 9000;
const ALLOWED_ORIGINS = '*';

/// Region-Klassifikation für intelligente Server-Wahl.
/// 2026-05-24 (vucko): 3 Region-Buckets:
///   - DACH (PC1-DACH-Server 8989) — DE+AT+CH+LI komplett
///   - EU-WEST (PC2 Frankreich, Belgien, Niederlande, Luxemburg)
///   - EU-SOUTH (PC2 Italien, Spanien, Portugal, Süd-Frankreich)
///   - EU-EAST (PC2 Polen, Tschechien, Slowakei, Ungarn, Balkan)
///   - UNKNOWN (außerhalb, z.B. Skandinavien-Nord oder weit außerhalb EU)
enum GeoRegion { dach = 'dach', euWest = 'eu_west', euSouth = 'eu_south', euEast = 'eu_east', unknown = 'unknown' }

const ONLY_HOME_MAX_FOREIGN_FRACTION = 0.10;
const ONLY_HOME_MAX_FOREIGN_SEGMENT_METERS = 500;

function classifyPoint(lat: number, lng: number): GeoRegion {
  // 2026-05-27 (vucko v2): Explicit-First-Order mit Alpen-Trennlinie bei
  // lat 46.5. Süd der Alpen = euSouth/Balkan, nördlich = DACH/AT.
  // Vermeidet dass Graz (47.07) als Italien klassifiziert wird oder
  // Klagenfurt (46.62) als Slowenien.

  // Slowenien (45.42-46.55, 13.38-16.61) — engere lat-Box um Klagenfurt/Villach auszuschließen
  if (lat >= 45.42 && lat <= 46.55 && lng >= 13.38 && lng <= 16.61) {
    return GeoRegion.euEast;
  }
  // Kroatien (42.4-46.55, 13.5-19.45)
  if (lat >= 42.4 && lat <= 46.55 && lng >= 13.5 && lng <= 19.45) {
    return GeoRegion.euEast;
  }
  // Italien (35.5-46.5, 6.6-18.5) — Alpen-Linie bei lat 46.5 trennt von AT/CH
  // Südtirol (Bozen 46.49) ist gerade noch IT, alles ab lat 46.5 ist DACH
  if (lat >= 35.5 && lat <= 46.5 && lng >= 6.6 && lng <= 18.5) {
    return GeoRegion.euSouth;
  }
  // Spanien + Portugal + Süd-Frankreich (Lat <44 = klar süd der DACH-Box)
  if (lat >= 36.0 && lat <= 44.0 && lng >= -10.0 && lng <= 7.5) {
    return GeoRegion.euSouth;
  }
  // DACH (DE + AT + CH + LI) — nach den kleineren Ländern
  if (lat >= 45.8 && lat <= 55.1 && lng >= 5.86 && lng <= 17.2) {
    return GeoRegion.dach;
  }
  // Frankreich-Nord + Benelux + UK-Süd
  if (lat >= 47.0 && lat <= 55.0 && lng >= -5.5 && lng <= 7.5) {
    return GeoRegion.euWest;
  }
  // Polen + Tschechien + Slowakei + Ungarn + Serbien + Bosnien etc.
  if (lat >= 40.0 && lat <= 55.5 && lng >= 12.0 && lng <= 30.0) {
    return GeoRegion.euEast;
  }
  return GeoRegion.unknown;
}

function isInDachCoverage(lat: number, lng: number): boolean {
  return classifyPoint(lat, lng) === GeoRegion.dach;
}

// 2026-08-18 (D1b2, gemessen): Die alte IT-Box `lat < 46.85 && lng 6.6..13.9`
// verschluckte GANZ Osttirol und den Westen Kaerntens, die SI-Box
// `lat 45.4..46.9 && lng 13.4..16.6` den Rest Kaerntens. Gemessen an der
// Produktions-Edge: Villach (46.610/13.856) -> IT, Lienz (46.830/12.769) -> IT,
// Klagenfurt (46.625/14.308) -> SI. Fuer diese Nutzer war „Im Land bleiben"
// unbenutzbar, sobald irgendjemand die Laenderkennung korrekt setzt.
//
// Die Suedgrenze Oesterreichs laeuft nicht auf einer Breite, sondern springt
// entlang des Alpenhauptkamms. Diese Bandtabelle folgt den realen
// Grenzuebergaengen: Reschen 46.84, Brenner 47.00, Innichen/Sillian 46.73,
// Ploeckenpass 46.60, Nassfeld 46.56, Thoerl-Maglern 46.52, Loibl 46.43,
// Seebergsattel 46.47, Radlpass 46.66, Spielfeld 46.70.
// Alles NOERDLICH der Bandgrenze ist Oesterreich und darf nicht mehr in die
// IT- oder SI-Box fallen.
function austriaSouthLimit(lng: number): number {
  if (lng < 11.00) return 46.85; // Reschenpass / Vinschgau
  if (lng < 12.00) return 46.90; // Brenner, Timmelsjoch
  if (lng < 12.35) return 46.78; // Innichen bleibt Italien
  if (lng < 12.60) return 46.68; // Sillian, Kartitsch = Osttirol
  if (lng < 13.50) return 46.55; // Ploeckenpass, Nassfeld
  if (lng < 13.75) return 46.53; // Thoerl-Maglern: Arnoldstein AT / Tarvis IT
  if (lng < 14.20) return 46.45; // Karawankentunnel: Villach AT / Jesenice SI
  if (lng < 14.60) return 46.44; // Loibl: Ferlach AT
  if (lng < 14.90) return 46.47; // Seebergsattel, Koralpe
  if (lng < 15.50) return 46.62; // Drau: Lavamuend AT / Dravograd SI
  if (lng < 15.80) return 46.695; // Mur: Spielfeld/Mureck AT, Sentilj SI
  return 46.683; // Mur: Bad Radkersburg AT, Gornja Radgona SI
}

function classifyCountry(lat: number, lng: number): string | null {
  if (isLiechtensteinApprox(lat, lng)) return 'LI';
  if (lat >= 47.52 && lat <= 47.58 && lng >= 9.63 && lng <= 9.74) return 'DE';
  if (isVorarlbergAustria(lat, lng)) return 'AT';
  if (lat >= 45.80 && lat <= 47.81 && lng >= 5.95 && lng <= 9.66) return 'CH';
  // Oesterreich-Sued VOR IT/SI pruefen — sonst gewinnen die groben Boxen.
  if (lng >= 10.00 && lng <= 17.16 && lat >= austriaSouthLimit(lng) &&
      lat <= austriaNorthLimit(lng)) {
    return 'AT';
  }
  if (lat < 46.85 && lng >= 6.6 && lng <= 13.9) return 'IT';
  if (lat >= 45.4 && lat <= 46.9 && lng >= 13.4 && lng <= 16.6) return 'SI';
  if (lng >= 9.53 && lng <= 17.16 && lat >= 46.37) {
    if (lat <= austriaNorthLimit(lng)) return 'AT';
  }
  if (lat >= 47.27 && lat <= 55.06 && lng >= 5.87 && lng <= 15.04) return 'DE';
  return null;
}

function isLiechtensteinApprox(lat: number, lng: number): boolean {
  if (lat < 47.04 || lat > 47.28 || lng < 9.47 || lng > 9.64) return false;
  return pointInPolygon(lat, lng, [
    [9.485, 47.270],
    [9.545, 47.270],
    [9.585, 47.235],
    [9.626, 47.165],
    [9.615, 47.047],
    [9.490, 47.045],
    [9.485, 47.165],
  ]);
}

function isVorarlbergAustria(lat: number, lng: number): boolean {
  if (lat < 46.82 || lat > 47.56 || lng < 9.52 || lng > 10.30) return false;
  if (isLiechtensteinApprox(lat, lng)) return false;
  return lng >= vorarlbergWestLimit(lat);
}

function vorarlbergWestLimit(lat: number): number {
  if (lat >= 47.50) return 9.70;
  if (lat >= 47.44) return 9.645;
  if (lat >= 47.32) return 9.585;
  if (lat >= 47.22) return 9.565;
  if (lat >= 47.15) return 9.600;
  return 9.650;
}

function pointInPolygon(lat: number, lng: number, polygon: Array<[number, number]>): boolean {
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const [xi, yi] = polygon[i];
    const [xj, yj] = polygon[j];
    const intersects = ((yi > lat) !== (yj > lat)) &&
      (lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi);
    if (intersects) inside = !inside;
  }
  return inside;
}

function austriaNorthLimit(lng: number): number {
  if (lng < 10.9) return 47.55;
  if (lng < 11.6) return 47.42;
  if (lng < 12.6) return 47.60;
  if (lng < 13.4) return 47.82;
  return 48.80;
}

function normalizeCountryPreference(value: unknown): 'any' | 'prefer_home' | 'only_home' {
  const raw = String(value ?? '').trim().toLowerCase().replace(/[-\s]/g, '_');
  if (raw === 'only_home' || raw === 'onlyhome') return 'only_home';
  if (raw === 'prefer_home' || raw === 'preferhome') return 'prefer_home';
  return 'any';
}

function normalizeCountryCode(value: unknown): string | null {
  const raw = String(value ?? '').trim().toUpperCase();
  return raw.length > 0 ? raw : null;
}

type CountryRouteMetrics = {
  foreignPointFraction: number;
  foreignDistanceFraction: number;
  maxForeignSegmentMeters: number;
  foreignDistanceMeters: number;
  totalDistanceMeters: number;
  countriesTouched: string[];
};

function countryRouteMetrics(coords: [number, number][], homeCountryCode: string | null): CountryRouteMetrics {
  const home = homeCountryCode ? homeCountryCode.toUpperCase() : null;
  const seen = new Set<string>();
  let classified = 0;
  let foreignPoints = 0;
  let foreignDistanceMeters = 0;
  let totalDistanceMeters = 0;
  let activeForeignMeters = 0;
  let maxForeignSegmentMeters = 0;
  let previous: [number, number] | null = null;
  let previousCountry: string | null = null;
  for (const [lng, lat] of coords) {
    const country = classifyCountry(lat, lng);
    if (country) {
      seen.add(country);
      if (home) {
        classified++;
        if (country !== home) foreignPoints++;
      }
    }
    if (previous) {
      const [prevLng, prevLat] = previous;
      const segmentMeters = distanceMeters(prevLat, prevLng, lat, lng);
      if (Number.isFinite(segmentMeters) && segmentMeters > 0) {
        totalDistanceMeters += segmentMeters;
        const midCountry = classifyCountry((prevLat + lat) / 2, (prevLng + lng) / 2);
        if (midCountry) seen.add(midCountry);
        const endpointsForeign = Boolean(home && previousCountry && country && previousCountry !== home && country !== home);
        const midpointForeign = Boolean(home && midCountry && midCountry !== home);
        if (endpointsForeign || midpointForeign) {
          foreignDistanceMeters += segmentMeters;
          activeForeignMeters += segmentMeters;
          maxForeignSegmentMeters = Math.max(maxForeignSegmentMeters, activeForeignMeters);
        } else {
          activeForeignMeters = 0;
        }
      }
    }
    previous = [lng, lat];
    previousCountry = country;
  }
  const countriesTouchedList = [...seen].sort((a, b) => {
    if (home && a === home) return -1;
    if (home && b === home) return 1;
    return a.localeCompare(b);
  });
  return {
    foreignPointFraction: classified === 0 ? 0 : foreignPoints / classified,
    foreignDistanceFraction: totalDistanceMeters <= 0 ? 0 : foreignDistanceMeters / totalDistanceMeters,
    maxForeignSegmentMeters,
    foreignDistanceMeters,
    totalDistanceMeters,
    countriesTouched: countriesTouchedList,
  };
}

function countryForeignFraction(coords: [number, number][], homeCountryCode: string | null): number {
  return countryRouteMetrics(coords, homeCountryCode).foreignPointFraction;
}

function countriesTouched(coords: [number, number][], homeCountryCode: string | null): string[] {
  return countryRouteMetrics(coords, homeCountryCode).countriesTouched;
}

function countryPenalty(foreignFraction: number, preference: 'any' | 'prefer_home' | 'only_home'): number {
  if (preference === 'any' || foreignFraction <= 0) return 0;
  const clamped = Math.min(1, Math.max(0, foreignFraction));
  const maxPenalty = preference === 'only_home' ? 300 : 90;
  return maxPenalty * Math.pow(clamped, 1.5);
}

/// 3-Server-Wahl mit intelligentem Routing.
/// 2026-05-24 (vucko):
///   - DACH-Punkt → PC1-DACH primary (PC1-DE fallback, PC2-EU fallback²)
///   - EU-Punkt → PC2-EU primary (PC1-DE fallback, PC1-DACH fallback²)
///   - Cross-DACH-EU Route (z.B. München→Mailand) → beide Server müssen
///     coveren, also EU primary
function chooseGraphhopperUrl(lat: number, lng: number): { primary: string; fallback: string } {
  return chooseGraphhopperUrlForRoute([{ lat, lng }]);
}

function chooseGraphhopperUrlForRoute(points: Array<{ lat: number; lng: number }>): { primary: string; fallback: string } {
  if (points.length === 0) {
    return { primary: GRAPHHOPPER_URL, fallback: GRAPHHOPPER_DE_URL };
  }
  const regions = new Set(points.map(p => classifyPoint(p.lat, p.lng)));
  // Alle Punkte in DACH → DACH-Server primary (PC1 ist schneller, weniger
  // Daten zu durchsuchen)
  if (regions.size === 1 && regions.has(GeoRegion.dach)) {
    // 2026-06-28 (vucko Failover-Fix): Fallback MUSS die ANDERE physische
    // Maschine sein (PC1 = GRAPHHOPPER_DE_URL), nicht GRAPHHOPPER_EU_URL — denn
    // URL (PC2-DACH) UND EU_URL (PC2-EU) liegen auf DEMSELBEN PC2. Lag PC2 aus,
    // fiel das „Failover" auf die tote Maschine -> Serverfehler. Mit DE_URL
    // uebernimmt bei PC2-Ausfall echt der zweite PC (PC1). Voraussetzung:
    // Supabase-Secret GRAPHHOPPER_DE_URL zeigt auf PC1 (siehe INFRA_NEVER_DOWN.md).
    return { primary: GRAPHHOPPER_URL, fallback: GRAPHHOPPER_DE_URL };
  }
  // 2026-05-27 (vucko v3): PC2 hat jetzt MIT dach-italy-balkan.osm.pbf
  // (DE+AT+CH+IT+SI+HR+FR-Süd in einer einzigen dedupzierten PBF aus
  // europe-latest.osm.pbf bbox-extract). Damit kann PC2 BEIDE Regionen
  // routen. Cross-Border und reine EU-Routen → PC2 primary, PC1 als
  // Fallback wenn PC2 offline.
  // 2026-06-28 (vucko Failover-Fix): Fallback = PC1 (GRAPHHOPPER_DE_URL), die
  // andere physische Maschine — NICHT GRAPHHOPPER_URL, das ebenfalls auf PC2
  // liegt. So uebernimmt bei PC2-Ausfall wirklich der zweite PC.
  return { primary: GRAPHHOPPER_EU_URL, fallback: GRAPHHOPPER_DE_URL };
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
  randomSeed?: number;
  random_seed?: number;
  route_variant_hint?: string;
  routeVariantHint?: string;
  detour_factor?: number;
  detourFactor?: number;
  offset_side?: number;
  offsetSide?: number;
  previous_route_fingerprints?: string[];
  client_trigger?: string;
  /// 2026-08-18 (Aufgabe 1.3): Der Client schickt dieses Feld
  /// (route_service.dart:3242 und :3323), die Edge hat es nie gelesen.
  /// Es wird BEWUSST ignoriert, siehe die Begruendung bei `maxAttempts`.
  /// Hier steht es nur, damit es getypt ist und im Meta sichtbar wird.
  max_candidate_attempts?: number;
  // 2026-05-22 (Task #41): A→B Detour-Level (0=direkt, 1=klein, 2=mittel, 3=groß)
  detour_level?: number;
  detourLevel?: number;
  // 2026-05-22 (Task #42): Explicit user-waypoints (zwischen start + end)
  waypoints?: Array<{ latitude: number; longitude: number }>;
  // 2026-07-03 (vucko Wegpunkte-jede-Distanz): Pflicht-Stopps. Der Client sendet
  // sie bisher als ROUND_TRIP mit waypoint_mode='required_stops' — die alte v2
  // las diese Felder GAR NICHT und lieferte eine round_trip-Zufallsschleife, die
  // die Stopps ignorierte (+ eine harte Client-Distanzsperre). Jetzt routen wir
  // sie als echte durchgeroutete Punktkette (car/fastest, jede Distanz).
  required_waypoints?: Array<{ latitude: number; longitude: number }>;
  waypoint_mode?: string;
  close_loop?: boolean;
  // 2026-06-09 (vucko U-Turn-Fix): Reroute während der Fahrt — der Client
  // schickt seine Fahrtrichtung mit. Wird als GraphHopper-`heading` am
  // Startpunkt durchgereicht → die neue Route startet IN Fahrtrichtung,
  // keine Einbiegungen, die sofort einen U-Turn verlangen.
  reroute_request?: boolean;
  moving_start?: boolean;
  current_heading?: number;
  country_preference?: string;
  countryPreference?: string;
  home_country_code?: string;
  homeCountryCode?: string;
  avoid_cross_border?: boolean;
  avoidCrossBorder?: boolean;
  allowed_countries?: string[];
  allowedCountries?: string[];
  /// 2026-08-18 (D1c): Vom Handler aus dem JWT gesetzt — NIE vom Client. Wird
  /// nur gebraucht, um einen Abdeckungswunsch dem richtigen Konto zuzuordnen.
  _subject_id?: string | null;
  /// 2026-08-18 (D5): 'app' | 'test' | 'worker'. Trennt echte Nutzung von
  /// Messlaeufen im Ereignisprotokoll.
  origin?: string;
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
    randomSeed: raw.randomSeed ?? raw.random_seed,
    route_variant_hint: raw.route_variant_hint ?? raw.routeVariantHint,
    detour_factor: raw.detour_factor ?? raw.detourFactor,
    offset_side: raw.offset_side ?? raw.offsetSide,
    detour_level: raw.detour_level ?? raw.detourLevel ?? 0,
    country_preference: normalizeCountryPreference(raw.country_preference ?? raw.countryPreference),
    home_country_code: normalizeCountryCode(raw.home_country_code ?? raw.homeCountryCode) ?? undefined,
    avoid_cross_border: raw.avoid_cross_border ?? raw.avoidCrossBorder ?? false,
    allowed_countries: raw.allowed_countries ?? raw.allowedCountries,
    _subject_id: null, // wird erst im Handler aus dem JWT gefuellt
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
  // 2026-05-28 (vucko Task #82): Path-Details (road_class/road_environment)
  // kommen als [from, to, value]-Segmente, wenn `details=` angefragt wird.
  details?: Record<string, Array<[number, number, string | number]>>;
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
  // 2026-05-28 (vucko Profile-Diff): Profile massiv differenziert.
  // Vorher: Sport+Kurvenjagd hatten beide curvature-Bonus → fast identische
  // Geometrien. User-Beschwerde: „Sport gibt Bergstrecke, Kurvenjagd gibt
  // geradere Strecke — die Modi sind kaum unterschiedlich."
  //
  // Neue Charakterisierung:
  // - SPORT (scenic):  offene Genuss-Kurven auf SECONDARY/PRIMARY,
  //                    geringer curvature-Bonus, längere Stretches (200)
  // - KURVENJAGD:      MAX Kurven auf TERTIARY/UNCLASSIFIED + Bergpässe,
  //                    PRIMARY penalisiert (zu gerade), starker curvature-
  //                    Bonus, kompakte Loops (55)
  // - ABENDRUNDE:      Hauptstraßen, curve-averse, direkter Weg (300)
  // - ENTDECKER:       Variety-Mix, kein curvature-Bonus, mittlere Distanz
  // 2026-08-09 (vucko „die Modi muessen sich unterscheiden"): Jede Regel steht
  // jetzt auf ZWEI Beinen — road_class UND max_speed. Grund: `curvature` gibt es
  // nur auf einem der beiden Mini-PCs (siehe serverCapabilities). Auf dem
  // anderen wurden die curvature-Regeln weggeschnitten, und road_class allein
  // trennt zu schwach: eine Messreihe ueber 45-km-Rundkurse ab Feldkirch ergab
  // 287 / 292 / 296 Kurven pro 50 km fuer Kurvenjagd / Sport / Abendrunde — also
  // praktisch dieselbe Route. max_speed ist auf BEIDEN Servern vorhanden und
  // trennt den Charakter zuverlaessig:
  //   <= 60 km/h  Ortsdurchfahrt, enge Bergstrasse, Serpentine
  //   70-80 km/h  klassische kurvige Landstrasse
  //   >= 90 km/h  gestreckte Hauptstrasse, fliessend
  //
  // Bergpassage ist derzeit NICHT direkt messbar: Der Graph ist ohne Hoehendaten
  // importiert (elevation=false, kein average_slope). Bis zu einem Reimport mit
  // Hoehendaten dient das Paar „kleine Strassenklasse + niedriges Tempolimit"
  // als Naeherung fuer den Bergpass — Kurvenjagd sucht ihn, Abendrunde meidet ihn.
  switch (profile) {
    case 'motorcycle_kurvenjagd':
      // MAX Kurven, kleine technische Strassen, Bergpaesse.
      // PRIMARY bewusst penalisiert — zu gerade, zu wenig Fahr-Spass.
      return {
        priority: [
          { if: 'road_class == TERTIARY', multiply_by: '1.7' },
          { if: 'road_class == UNCLASSIFIED', multiply_by: '1.45' },
          { if: 'road_class == SECONDARY', multiply_by: '1.15' },
          { if: 'road_class == PRIMARY', multiply_by: '0.7' },
          { if: 'road_class == RESIDENTIAL', multiply_by: '0.3' },
          // Bergpass-Naeherung: langsame kleine Strassen sind das Ziel.
          { if: 'max_speed < 75', multiply_by: '1.6' },
          { if: 'max_speed < 55', multiply_by: '1.8' },
          // Gestreckte Schnellstrassen sind das Gegenteil dieses Modus.
          { if: 'max_speed >= 95', multiply_by: '0.35' },
          { if: 'curvature < 0.7', multiply_by: '1.9' },
          { if: 'curvature < 0.5', multiply_by: '2.4' },
        ],
        // 2026-06-10 (vucko): GH-Server erzwingt >=200 (HTTP 400:
        // "CustomModel in query can only use distance_influence bigger or
        // equal to 200.0"). Feintuning gehoert in die Server-Config.
        distance_influence: 200,
      };
    case 'motorcycle_scenic':
      // Sport: offene Genuss-Kurven, breite gut ausgebaute Strassen, wenig Berg.
      // Der Auftrag lautet „mehr Geraden, wenig Bergpassage" — deshalb wird das
      // langsame Bergprofil hier aktiv abgewertet statt nur nicht belohnt.
      return {
        priority: [
          { if: 'road_class == SECONDARY', multiply_by: '1.6' },
          { if: 'road_class == PRIMARY', multiply_by: '1.4' },
          { if: 'road_class == TERTIARY', multiply_by: '0.85' },
          { if: 'road_class == UNCLASSIFIED', multiply_by: '0.6' },
          { if: 'road_class == RESIDENTIAL', multiply_by: '0.4' },
          // Fliessendes Tempo ist der Kern dieses Modus.
          { if: 'max_speed >= 80', multiply_by: '1.5' },
          { if: 'max_speed < 60', multiply_by: '0.45' },
          { if: 'curvature < 0.75', multiply_by: '1.15' },
        ],
        distance_influence: 200,
      };
    case 'motorcycle_abendrunde':
      // Gemuetlich durch Staedte, Doerfer und Nebenstrassen — ausdruecklich
      // OHNE Bergpassage. Ortsdurchfahrten sind hier gewollt (das unterscheidet
      // die Abendrunde von Sport), die enge Serpentine ist es nicht.
      return {
        priority: [
          { if: 'road_class == SECONDARY', multiply_by: '1.6' },
          { if: 'road_class == PRIMARY', multiply_by: '1.4' },
          { if: 'road_class == RESIDENTIAL', multiply_by: '1.15' },
          { if: 'road_class == LIVING_STREET', multiply_by: '1.05' },
          { if: 'road_class == TERTIARY', multiply_by: '0.8' },
          // Bergpass-Naeherung ausschliessen: kleine Strasse + langsam.
          { if: 'road_class == UNCLASSIFIED', multiply_by: '0.35' },
          { if: 'max_speed < 55', multiply_by: '0.5' },
          { if: 'max_speed >= 100', multiply_by: '0.6' },
          { if: 'curvature < 0.5', multiply_by: '0.7' },
        ],
        distance_influence: 300,
      };
    case 'motorcycle_entdecker':
      // Variety: kleinere Strassen + Mix, KEIN curvature-Bonus
      // (Erkundung ueber Strassenvielfalt, nicht ueber Kruemmung).
      return {
        priority: [
          { if: 'road_class == TERTIARY', multiply_by: '1.45' },
          { if: 'road_class == UNCLASSIFIED', multiply_by: '1.25' },
          { if: 'road_class == SECONDARY', multiply_by: '1.15' },
          { if: 'road_class == PRIMARY', multiply_by: '0.95' },
          { if: 'road_class == RESIDENTIAL', multiply_by: '1.05' },
        ],
        distance_influence: 200,
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
  // 2026-06-02 (vucko): GraphHoppers Turn-by-turn-Instructions durchreichen,
  // damit das Handy/CarPlay echte Wegbeschreibung („300m rechts abbiegen")
  // zeigen kann. Wurde bisher verworfen → 0 Manöver.
  instructions?: Array<Record<string, unknown>>;
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

function stableHashInt(text: string | undefined): number {
  let hash = 0;
  const value = text ?? '';
  for (let i = 0; i < value.length; i++) {
    hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0;
  }
  return Math.abs(hash);
}

function finiteNumberOr(value: unknown, fallback: number): number {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeOffsetSide(value: unknown, seed: number): -1 | 1 {
  const parsed = finiteNumberOr(value, 0);
  if (parsed < 0) return -1;
  if (parsed > 0) return 1;
  return seed % 2 === 0 ? 1 : -1;
}

// 2026-06-10 (vucko START-SNAP-FIX): Haversine in Metern für die globale
// Start-Wache (Route muss am echten Standort beginnen).
function distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}


/// 2026-08-18 (Aufgabe 1.3): Welcher Term hat die Umweg-Basisdistanz bestimmt?
export type UmwegBasisTerm = 'absolut' | 'untergrenze' | 'faktor' | 'zieldistanz';

/// 2026-08-18 (Aufgabe 1.3): Basisdistanz des seitlichen Umweg-Wegpunkts.
///
/// GEMESSEN: Bis heute standen hier VIER Terme in einem Math.max, und einer
/// davon war nachweislich tot. Der Kommentar behauptete, `baseFactor`
/// (0,15 / 0,30 / 0,50) trenne die Stufen. Nachgerechnet mit den Werten, die
/// der Client wirklich schickt (route_service.dart: detour_factor 2,00 / 3,00
/// / 4,00):
///     factorKm-Anteil = (detour_factor - 1) * 0,55 = 0,55 / 1,10 / 1,65
///     baseFactor      =                              0,15 / 0,30 / 0,50
/// Der Faktor-Term ist in JEDER Stufe das 3,3- bis 3,7-Fache des baseFactor.
/// Beide werden mit demselben Profil-Multiplikator skaliert, der kuerzt sich
/// also weg. baseFactor konnte den Vergleich nie gewinnen — bei 5 bis 80 km
/// Luftlinie gewann immer `faktor` oder `zieldistanz`.
///
/// ZWEI VARIANTEN durchgerechnet:
///  (a) Als Untergrenze WIRKSAM machen: dafuer muesste baseFactor ueber 0,55 /
///      1,10 / 1,65 steigen, also auf mehr als das Dreifache. Der seitliche
///      Wegpunkt wanderte damit drei Mal so weit hinaus und die Routen wuerden
///      deutlich laenger als die angeforderte Zieldistanz. Genau das war der
///      Befund vom 16.08. („Ueberschuss war das Problem, nicht Mangel",
///      Dornbirn→Bezau: 69 km fuer Ziel 45). Verworfen.
///  (b) STREICHEN als eigener Term und den Wert dorthin legen, wo er wirklich
///      als Untergrenze wirkt: in den Faktor-Term, der bisher eine feste
///      Untergrenze von 0,08 hatte. Das ist rechnerisch identisch
///      (max(0,15 ; 0,08) = 0,15) und laesst nur EINEN Term stehen, der
///      genau das tut, was der Kommentar sagt. Gewaehlt.
///
/// Wirksam wird die Untergrenze damit dort, wo sie gebraucht wird: bei
/// Anfragen OHNE `detour_factor` (alte App-Versionen bleiben installiert und
/// schicken das Feld nicht). Ohne sie fiele der Umweg dort von 0,15/0,30/0,50
/// auf 0,08 der Luftlinie zusammen — Stufe 1, 2 und 3 waeren nicht mehr zu
/// unterscheiden.
export function umwegBasisKm(opts: {
  directKm: number;
  detourLevel: number;
  detourFactor: number;
  requestedTargetKm: number;
  profileMultiplier: number;
}): { km: number; term: UmwegBasisTerm } {
  const untergrenzeAnteil = opts.detourLevel === 1
    ? 0.15
    : opts.detourLevel === 2
    ? 0.30
    : 0.50;
  // Die Untergrenze steckt hier drin: unter 0,15 / 0,30 / 0,50 der Luftlinie
  // faellt der seitliche Wegpunkt nie, egal was der Client schickt.
  const faktorAnteil = Math.max(untergrenzeAnteil, (opts.detourFactor - 1) * 0.55);
  const faktorKm = opts.directKm * faktorAnteil * opts.profileMultiplier;
  const zielKm = Math.max(0, opts.requestedTargetKm - opts.directKm) * 0.48;
  // 2 km absolute Untergrenze: darunter liegt der seitliche Wegpunkt noch im
  // selben Ort und GraphHopper liefert schlicht die direkte Strecke.
  let km = 2;
  let term: UmwegBasisTerm = 'absolut';
  if (faktorKm > km) {
    km = faktorKm;
    // Nur wenn der Faktor-Term GENAU auf der Untergrenze sitzt, hat die
    // Untergrenze entschieden — sonst der vom Client geschickte Faktor.
    term = faktorAnteil <= untergrenzeAnteil ? 'untergrenze' : 'faktor';
  }
  if (zielKm > km) {
    km = zielKm;
    term = 'zieldistanz';
  }
  return { km, term };
}

// ─────────── Selbst-Ueberlappung: hin und dieselbe Strasse zurueck ────────
//
// 2026-08-18 (Aufgabe 1.4, vucko am 16.08.): „Die Strecken muessen sauber sein
// und nicht in eine Richtung und dann die gleiche Strasse wieder zurueckfinden."
//
// GEMESSEN vor dieser Aenderung: Das Wort „overlap" kam in dieser Datei kein
// einziges Mal vor, weder im Repo noch in der deployten Fassung. Serverseitig
// gab es nur `u_turn_count` aus den GraphHopper-Vorzeichen -8/8/-98 und die
// Strafe darauf. Eine Strecke, die OHNE signalisierte Wende hin und zurueck
// ueber dieselbe Strasse laeuft (Schleife durchs Dorf und auf der
// Parallelfahrbahn zurueck), wurde vom Server weder erkannt noch bestraft.
// Sie konnte als bester Kandidat gewinnen und musste dann im Client verworfen
// werden. Das Live-Harness test/route/a2b_umweg_live_probe_test.dart:73-79 hat
// am 16.08. Ueberlappungen bis 21 % gemessen — der Server sah davon nichts.
//
// VERFAHREN, absichtlich gleich parametrisiert wie dieses Harness:
//   * Geometrie auf ein 100-m-Raster abtasten
//   * Naehe: unter 40 m
//   * Mindest-Indexabstand: 60 Rasterpunkte (rund 6 km entlang der Strecke),
//     damit Kurven, Kreisverkehre und Alpen-Kehren nicht mitzaehlen
//
// DREI UNTERSCHIEDE zum Harness, alle drei gemessen begruendet:
//   1. RICHTUNGSBEWUSST: ein Paar zaehlt nur, wenn die beiden Durchfahrten
//      GEGENLAEUFIG sind (Peilungsunterschied ueber 120 Grad, also
//      Skalarprodukt der Fahrtrichtungen unter -0,5). Genau das ist „hin und
//      dieselbe Strasse zurueck". Eine Kreuzung im Rundkurs (rund 90 Grad)
//      zaehlt damit nicht mit. Rechenprobe (c): Rundkurs mit genau einer
//      Kreuzung → 0,000.
//   2. SYMMETRISCH: das Harness sucht den Partner nur vorwaerts (j > i + 60)
//      und kommt bei einer reinen Hin-und-Rueckfahrt deshalb auf rund 0,5.
//      Hier zaehlen BEIDE Durchfahrten, eine komplett doppelt befahrene
//      Strecke ergibt also rund 1,0 = „die ganze Strecke wurde zweimal
//      gefahren". Wer Harness-Zahlen vergleicht: Server rund 2x Harness.
//   3. PUNKT GEGEN SEGMENT statt Punkt gegen Punkt, und echte Abtastung statt
//      Ausduennen. Die erste Fassung verglich Rasterpunkt mit Rasterpunkt und
//      duennte die vorhandenen Stuetzpunkte nur aus. Gemessen in der
//      Rechenprobe: der Fall „zurueck auf der Parallelfahrbahn, 25 m daneben"
//      ergab damit 0,000 statt rund 0,95 — die Rasterpunkte von Hin- und
//      Rueckrichtung lagen um rund 100 m phasenverschoben und liefen
//      aneinander vorbei. Mit interpolierter 100-m-Abtastung und dem Abstand
//      Punkt-zu-Segment ist das Ergebnis unabhaengig davon, wo GraphHopper
//      seine Stuetzpunkte gesetzt hat.
//
// BEKANNTE LUECKE, bewusst in Kauf genommen: Durch den Mindest-Indexabstand
// von 60 Rasterpunkten sind die letzten rund 6 km vor und nach einem
// Wendepunkt unsichtbar. Ein kurzer Stachel (Sackgasse mit Wendekreis, 3 km
// raus und 3 km zurueck) wird von dieser Kennzahl NICHT erfasst — den deckt
// `u_turn_count` ab, weil GraphHopper dort ein Wende-Vorzeichen setzt. Den
// Schwellwert zu senken wuerde Alpen-Serpentinen treffen, also genau die
// Strassen, die „Kurvenjagd" haben will. Messbar in der Rechenprobe: 60 km
// hin und zurueck ergibt 0,950, dieselbe Figur mit nur 10 km ergibt 0,700.
//
// LAUFZEIT: Die Funktion laeuft fuer JEDEN Kandidaten (bis zu 14 parallel).
// Deshalb KEINE naive O(n^2)-Schleife: die Rasterpunkte kommen in ein
// 160-m-Gitter (Hash auf lokale Meter-Koordinaten), gesucht wird nur in den 9
// Nachbarzellen. Damit ist der Aufwand linear in der Punktzahl.
const UEBERLAPP_RASTER_M = 100;
const UEBERLAPP_NAEHE_M = 40;
const UEBERLAPP_MIN_INDEXABSTAND = 60;
const UEBERLAPP_GEGENLAEUFIG_COS = -0.5; // entspricht mehr als 120 Grad
// Zellenkante des Suchgitters. Muss groesser sein als Naehe + Rasterschritt
// (40 + 100 = 140), sonst kann die 3x3-Nachbarschaft ein Segment uebersehen,
// das dem Punkt naeher als 40 m kommt.
const UEBERLAPP_ZELLE_M = 160;
// Schutz gegen entartete Geometrien: mehr als 20.000 Rasterpunkte entspraechen
// ueber 2.000 km Strecke. Danach wird nur noch gruober abgetastet.
const UEBERLAPP_MAX_PUNKTE = 20000;

/// Streckengleiche Abtastung: liefert lokale Meter-Koordinaten im festen
/// Abstand `schrittM`, auch wenn die Eingabe lange Kanten ohne Zwischenpunkte
/// hat (Autobahn-Kanten zwischen Anschlussstellen sind mehrere Kilometer lang).
/// Ohne diese Interpolation haengt das Ergebnis davon ab, wo GraphHopper
/// zufaellig Stuetzpunkte gesetzt hat.
function ueberlappRaster(
  coords: [number, number][],
  schrittM: number,
): { xs: Float64Array; ys: Float64Array; n: number } {
  const lat0 = coords[0][1];
  const lng0 = coords[0][0];
  const mProLng = 111320 * Math.cos((lat0 * Math.PI) / 180);
  const mProLat = 110540;
  const px: number[] = [];
  const py: number[] = [];
  let vx = 0;
  let vy = 0;
  px.push(0);
  py.push(0);
  let rest = schrittM;
  for (let i = 1; i < coords.length; i++) {
    const nx = (coords[i][0] - lng0) * mProLng;
    const ny = (coords[i][1] - lat0) * mProLat;
    let dx = nx - vx;
    let dy = ny - vy;
    let len = Math.sqrt(dx * dx + dy * dy);
    // `len > 0` ist Pflicht: GraphHopper liefert gelegentlich zwei identische
    // Stuetzpunkte hintereinander. Ohne die Bedingung teilt die naechste Zeile
    // durch null und die ganze Kennzahl wird NaN.
    while (len > 0 && len >= rest && px.length < UEBERLAPP_MAX_PUNKTE) {
      vx += (dx / len) * rest;
      vy += (dy / len) * rest;
      px.push(vx);
      py.push(vy);
      dx = nx - vx;
      dy = ny - vy;
      len = Math.sqrt(dx * dx + dy * dy);
      rest = schrittM;
    }
    rest -= len;
    vx = nx;
    vy = ny;
  }
  return { xs: Float64Array.from(px), ys: Float64Array.from(py), n: px.length };
}

/// Anteil der Strecke (0..1), der ein zweites Mal in Gegenrichtung befahren
/// wird. Koordinaten sind wie ueberall [longitude, latitude].
function selbstUeberlappungAnteil(coords: [number, number][]): number {
  if (!coords || coords.length < 2) return 0;
  const { xs, ys, n } = ueberlappRaster(coords, UEBERLAPP_RASTER_M);
  // Kuerzer als der Mindest-Indexabstand → es KANN keine Ueberlappung geben.
  if (n <= UEBERLAPP_MIN_INDEXABSTAND + 1) return 0;
  // Fahrtrichtung je Rasterpunkt als Einheitsvektor (Nachbar davor/danach)
  const rx = new Float64Array(n);
  const ry = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const a = i > 0 ? i - 1 : 0;
    const b = i < n - 1 ? i + 1 : n - 1;
    let dx = xs[b] - xs[a];
    let dy = ys[b] - ys[a];
    const len = Math.sqrt(dx * dx + dy * dy);
    if (len > 0) {
      dx /= len;
      dy /= len;
    }
    rx[i] = dx;
    ry[i] = dy;
  }
  // Suchgitter aufbauen
  const zelle = UEBERLAPP_ZELLE_M;
  const gitter = new Map<number, number[]>();
  const schluessel = (cx: number, cy: number) => cx * 1000003 + cy;
  for (let i = 0; i < n; i++) {
    const k = schluessel(Math.floor(xs[i] / zelle), Math.floor(ys[i] / zelle));
    const eimer = gitter.get(k);
    if (eimer) eimer.push(i);
    else gitter.set(k, [i]);
  }
  const naeheQuadrat = UEBERLAPP_NAEHE_M * UEBERLAPP_NAEHE_M;
  // Abstand Punkt i zum Segment j→j+1, plus Richtungsvergleich.
  const passt = (i: number, j: number): boolean => {
    if (j < 0 || j + 1 >= n) return false;
    // Beide Segmentenden muessen weit genug entfernt liegen, sonst zaehlt eine
    // enge Kehre als Ueberlappung.
    if (Math.abs(j - i) < UEBERLAPP_MIN_INDEXABSTAND) return false;
    if (Math.abs(j + 1 - i) < UEBERLAPP_MIN_INDEXABSTAND) return false;
    const sx = xs[j];
    const sy = ys[j];
    let ex = xs[j + 1] - sx;
    let ey = ys[j + 1] - sy;
    const laengeQuadrat = ex * ex + ey * ey;
    let t = 0;
    if (laengeQuadrat > 0) {
      t = ((xs[i] - sx) * ex + (ys[i] - sy) * ey) / laengeQuadrat;
      if (t < 0) t = 0;
      else if (t > 1) t = 1;
    }
    const ddx = xs[i] - (sx + ex * t);
    const ddy = ys[i] - (sy + ey * t);
    if (ddx * ddx + ddy * ddy >= naeheQuadrat) return false;
    const len = Math.sqrt(laengeQuadrat);
    if (len === 0) return false;
    ex /= len;
    ey /= len;
    return rx[i] * ex + ry[i] * ey <= UEBERLAPP_GEGENLAEUFIG_COS;
  };
  let treffer = 0;
  for (let i = 0; i < n; i++) {
    const cx = Math.floor(xs[i] / zelle);
    const cy = Math.floor(ys[i] / zelle);
    let gefunden = false;
    for (let ox = -1; ox <= 1 && !gefunden; ox++) {
      for (let oy = -1; oy <= 1 && !gefunden; oy++) {
        const eimer = gitter.get(schluessel(cx + ox, cy + oy));
        if (!eimer) continue;
        for (const j of eimer) {
          if (passt(i, j) || passt(i, j - 1)) {
            gefunden = true;
            break;
          }
        }
      }
    }
    if (gefunden) treffer++;
  }
  return Number((treffer / n).toFixed(3));
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

// ───────────────── Server-Faehigkeiten (Encoded Values / Profile) ──────────
//
// 2026-08-09 (vucko „die Modi differenzieren sich nicht"): ROOT CAUSE gefunden.
// Die beiden Mini-PCs waren nicht synchron und BEIDE unvollstaendig:
//   PC2 (:8989)  kennt das Profil 'car',  hat aber KEIN 'curvature'
//   PC1          kennt 'curvature',       hat aber KEIN 'car'-Profil
// Drei der vier Stil-Overlays (Sport, Kurvenjagd, Abendrunde) enthalten
// `curvature`-Regeln. Auf dem Server ohne diesen Encoded Value antwortet
// GraphHopper mit HTTP 400: „Cannot compile expression: … 'curvature' not
// available" — die KOMPLETTE Anfrage stirbt, nicht nur die eine Regel. Ergebnis:
// Der Stil kam nie beim Router an, alle Modi lieferten dieselbe Geometrie.
//
// Der Fix hat drei Stufen, damit ein Server-Zustand nie wieder eine Route
// kosten kann:
//   1. Wir fragen einmal pro Server /info ab und merken uns, was er kann.
//   2. Regeln, die auf einen unbekannten Encoded Value zeigen, fliegen raus —
//      der Rest des Stils wirkt weiterhin.
//   3. Sollte trotzdem ein Compile-Fehler kommen, wird EINMAL ohne Overlay
//      wiederholt. Eine Route ohne Stil ist immer besser als gar keine Route.
interface ServerCaps {
  encodedValues: Set<string>;
  profiles: Set<string>;
  bis: number;
}

const CAPS_TTL_MS = 10 * 60 * 1000;
const capsCache = new Map<string, ServerCaps>();

async function serverCapabilities(baseUrl: string): Promise<ServerCaps | null> {
  const jetzt = Date.now();
  const bekannt = capsCache.get(baseUrl);
  if (bekannt && bekannt.bis > jetzt) return bekannt;
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 4000);
    const res = await fetch(`${baseUrl}/info`, { signal: ctrl.signal });
    clearTimeout(t);
    if (!res.ok) return null;
    // deno-lint-ignore no-explicit-any
    const d: any = await res.json();
    const ev = d?.encoded_values;
    const evNames: string[] = Array.isArray(ev)
      ? ev.map((x: unknown) => (typeof x === 'string' ? x : Object.keys(x as object)[0]))
      : ev && typeof ev === 'object'
      ? Object.keys(ev)
      : [];
    const caps: ServerCaps = {
      encodedValues: new Set(evNames.filter(Boolean)),
      // deno-lint-ignore no-explicit-any
      profiles: new Set((d?.profiles ?? []).map((p: any) => p?.name).filter(Boolean)),
      bis: jetzt + CAPS_TTL_MS,
    };
    capsCache.set(baseUrl, caps);
    return caps;
  } catch (_) {
    // Kein /info erreichbar: lieber nichts filtern als eine Route verlieren.
    // Stufe 3 (Retry ohne Overlay) faengt den Rest ab.
    return null;
  }
}

/// Alle Bezeichner links von einem Vergleich in einer Custom-Model-Bedingung.
/// `road_class == TERTIARY && max_speed < 70` → ['road_class', 'max_speed'].
function bedingungsFelder(ausdruck: string): string[] {
  const felder: string[] = [];
  for (const teil of ausdruck.split(/&&|\|\|/)) {
    const m = teil.trim().match(/^([a-z_][a-z0-9_]*)\s*(==|!=|<=|>=|<|>)/i);
    if (m) felder.push(m[1]);
  }
  return felder;
}

/// Entfernt Regeln, die auf einen dem Server unbekannten Encoded Value zeigen.
function overlayAufServerZuschneiden<T extends { if: string }>(
  regeln: T[],
  caps: ServerCaps | null,
): { behalten: T[]; entfernt: string[] } {
  if (caps == null || caps.encodedValues.size === 0) {
    return { behalten: regeln, entfernt: [] };
  }
  const behalten: T[] = [];
  const entfernt: string[] = [];
  for (const regel of regeln) {
    const felder = bedingungsFelder(regel.if);
    const fehlend = felder.filter((f) => !caps.encodedValues.has(f));
    if (fehlend.length === 0) behalten.push(regel);
    else entfernt.push(`${regel.if} (fehlt: ${fehlend.join(',')})`);
  }
  return { behalten, entfernt };
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
  // 2026-08-16 (T3): Lage des Umweg-Vias entlang der Direktlinie (0..1).
  detourAlong?: number;
  // Custom waypoints (zwischen start + end, in order)
  intermediateWaypoints?: Array<{ lat: number; lng: number }>;
  // 2026-06-09 (vucko U-Turn-Fix): Fahrtrichtung am Startpunkt (Grad, 0=Nord).
  // GraphHopper bevorzugt damit Routen, die IN Fahrtrichtung starten —
  // verhindert Reroutes, die mit einer Wende/U-Turn beginnen. ch.disable ist
  // ohnehin global true (custom_model) → heading wird ehrt.
  headingDeg?: number;
  // Standard-A→B, Trip-Wegpunkte und Navigation-Reroutes sollen sich wie
  // Google/Apple verhalten: Hauptstraßen/Autobahn vor Wohnstraßen-Shortcuts.
  preferMainRoads?: boolean;
  // 2026-06-02 (vucko): externes Abbruch-Signal (Round-Trip-Racer bricht die
  // nicht mehr benötigten Verlierer-Calls ab) + optionaler Per-Call-Timeout.
  signal?: AbortSignal;
  timeoutMs?: number;
  // 2026-06-29 (vucko Config-Drift-Schutz): interner Rekursions-Guard. Wenn ein
  // angefragtes Profil auf dem GraphHopper-Server fehlt (z.B. weil ein Mini-PC
  // out-of-sync ist und das 'car'-Profil nicht kennt), retryt callGraphHopper
  // EINMAL automatisch mit einem garantiert vorhandenen Motorrad-Profil, statt
  // die ganze Route mit HTTP 400 sterben zu lassen. Dieses Feld merkt sich das
  // ursprüngliche Profil, damit der Retry nicht endlos läuft.
  _profileFallbackFrom?: string;
  // 2026-08-09 (vucko): Zweiter Rekursions-Guard. Wenn der Server das
  // Stil-Overlay nicht uebersetzen kann, wird EINMAL ohne Overlay wiederholt —
  // eine Route ohne Stil schlaegt „keine Route".
  _ohneOverlay?: boolean;
}): Promise<RouteResult | { error: string }> {
  // 2026-06-03 (vucko ROOT-CAUSE-FIX): GraphHopper wird jetzt per POST mit
  // JSON-Body angesprochen, NICHT mehr per GET-Query. Live-Test an PC1+PC2
  // bewies eindeutig: `custom_model` als GET-Query-Param wird KOMPLETT IGNORIERT
  // (avoid=true ≡ avoid=false → identischer Fingerprint, Autobahn blieb). Per
  // POST-Body wirkt es sofort (Autobahn weg, Stil-Overlays greifen). DAS war die
  // wahre Ursache, warum „Autobahn aus", Stil-Differenzierung, Track/Service-
  // Penalty und Ferry-Block bei Rundkurs UND A→B alle NIE funktionierten.
  // GraphHopper-points sind im Body [lng, lat] (GeoJSON) — umgekehrt zur
  // GET-Form `point=lat,lng`.
  const points: Array<[number, number]> = [[opts.startLng, opts.startLat]];
  if (!opts.isRoundTrip && opts.endLat != null && opts.endLng != null) {
    // Explicit waypoints zuerst (für Wegpunkte-Mode)
    if (opts.intermediateWaypoints && opts.intermediateWaypoints.length > 0) {
      for (const wp of opts.intermediateWaypoints) {
        points.push([wp.lng, wp.lat]);
      }
    }
    // Auto-detour via senkrecht-Offset (klein/mittel/groß umweg)
    else if (opts.detourPerpendicularKm != null && opts.detourPerpendicularKm > 0
          && opts.detourBearingDeg != null) {
      // 2026-08-16 (vucko Testfahrt T3 „A→B zackt, Stufen unterscheiden sich
      // kaum"): Ein Via senkrecht zur Direktlinie — jetzt nicht mehr nur in
      // der Mitte, sondern je Kandidat bei [detourAlong] (0.38 / 0.5 / 0.62).
      // Live an GraphHopper gemessen: Ein Bogen aus drei Vias brachte NICHT
      // weniger Wenden (die Vias landen in den Bergen auf Sackgassen) und
      // deutlich laengere Routen; asymmetrische Einzel-Vias erzeugen dagegen
      // verschieden geformte Schleifen und mehr 0-Wende-Kandidaten. Die
      // eigentliche Waffe gegen den Stachel ist die Kandidatenwahl (mehr
      // Kandidaten, harte Wende-Strafe) plus pass_through unten.
      const along = opts.detourAlong ?? 0.5;
      const viaLat = opts.startLat + (opts.endLat - opts.startLat) * along;
      const viaLng = opts.startLng + (opts.endLng - opts.startLng) * along;
      const directBearing = bearingDeg(opts.startLat, opts.startLng, opts.endLat, opts.endLng);
      const perpBearing = (directBearing + opts.detourBearingDeg + 360) % 360;
      const offset = offsetCoord(viaLat, viaLng, opts.detourPerpendicularKm, perpBearing);
      points.push([offset.lng, offset.lat]);
    }
    points.push([opts.endLng, opts.endLat]);
  }
  const hatUmwegBogen =
    !opts.isRoundTrip && opts.detourPerpendicularKm != null &&
    opts.detourPerpendicularKm > 0 && opts.detourBearingDeg != null &&
    !(opts.intermediateWaypoints && opts.intermediateWaypoints.length > 0);
  // deno-lint-ignore no-explicit-any
  const ghBody: Record<string, any> = {
    points,
    profile: opts.profile,
    points_encoded: false,
    'ch.disable': true,
    instructions: true,
    // Deutsche Turn-by-turn-Texte („Rechts abbiegen auf …") für Handy + CarPlay.
    locale: 'de',
    // road_class/road_environment Details für echte Autobahn-Erkennung in meta.
    details: ['road_class', 'road_environment'],
    // 2026-08-16 (T3): Am Umweg-Via NICHT wenden, wenn es eine Weiterfahrt
    // gibt — GH faehrt dann in Fahrtrichtung durch (heading_penalty). Live
    // gemessen: macht aus manchem 1-Wende-Kandidaten einen 0-Wende-Kandidaten;
    // auf einer Sackgasse aendert es nichts (dort hilft nur ein anderer Via).
    // Nur fuer Umweg-Vias; Wegpunkte-Modus und Rundkurs bleiben wie bisher.
    ...(hatUmwegBogen ? { pass_through: true } : {}),
  };
  // 2026-06-09 (vucko U-Turn-Fix): EIN heading-Wert = gilt für den Startpunkt.
  // 2026-06-13 (vucko Reroute-Videos): Der POST-Body-Feldname ist `headings`
  // (Plural-Array)! `heading` (Singular) ist nur der GET-Query-Param und wird
  // im JSON-Body von GH STILL ignoriert (live bewiesen: heading → byte-
  // identische Routen bei 20° vs. 200°; headings → ehrliche „Wenden"-
  // Instruktion sign -98). Gleiche Falle wie der custom_model-GET-Bug.
  // heading_penalty 300 (GH-Default): gegen die Fahrtrichtung starten kostet
  // 5 Fahrminuten → nur wenn es WIRKLICH keine Alternative gibt, dreht GH um —
  // und dann sagt es das Wendemanöver explizit an.
  if (!opts.isRoundTrip && opts.headingDeg != null && Number.isFinite(opts.headingDeg)) {
    ghBody.headings = [((Math.round(opts.headingDeg) % 360) + 360) % 360];
    ghBody.heading_penalty = 300;
  }
  if (opts.isRoundTrip) {
    ghBody.algorithm = 'round_trip';
    if (opts.targetDistanceKm) {
      // dotted-key Form ist die einzige, die GH im POST-Body ehrt (nested
      // `round_trip:{distance}` wird ignoriert → 9km-Default; Live-getestet).
      ghBody['round_trip.distance'] = Math.round(opts.targetDistanceKm * 1000);
    }
    if (opts.seed != null) {
      ghBody['round_trip.seed'] = opts.seed;
    }
  }

  // 2026-05-21 (vucko): Stil-Differenzierung als Runtime-Overlay statt
  // Baseline-Profile-Änderung (die wäre ein Graph-Re-Import). Custom-Model
  // wird zusätzlich zum Profile angewandt — verschärft die Charakter-
  // Unterschiede zwischen Sport/Kurvenjagd/Abendrunde/Entdecker.
  const customOverlay = styleOverlayForProfile(opts.profile);
  const overlay: {
    priority: Array<{ if: string; multiply_by: string }>;
    speed?: Array<{ if: string; limit_to: string }>;
    distance_influence?: number;
  } = {
    priority: [...customOverlay.priority],
    // 2026-05-23 (vucko Bug-Fix FH→Romanshorn Fähre):
    // speed.limit_to=0 ist GraphHopper's echter Hard-Block für eine Edge.
    // multiply_by Penalties allein reichen nicht — GH nahm Bodensee-Fähre
    // trotzdem weil Land-Route 50× länger wäre. limit_to=0 macht die
    // Edge komplett unbefahrbar.
    speed: [{ if: 'road_environment == FERRY', limit_to: '0' }],
  };
  if (customOverlay.distance_influence != null) {
    overlay.distance_influence = customOverlay.distance_influence;
  }
  // Autobahn-Vermeidung: HARTER Block, nicht nur Penalty.
  // 2026-06-03 (vucko): multiply_by 0.05 war zu weich — Live-Matrix zeigte
  // 43/96 Routen MIT Autobahn trotz „Autobahn aus" (auf langen Strecken ist die
  // Autobahn ~20× schneller → GH nahm sie trotz Penalty). Lösung: dieselbe
  // bewiesene Hard-Block-Technik wie bei Ferry — speed.limit_to=0 macht die
  // Motorway-Edge KOMPLETT unbefahrbar (priority allein reicht nicht). TRUNK
  // (Schnell-/Bundesstraße) bleibt nur stark bestraft, NICHT 0 — in Alpentälern
  // ist sie oft die einzige Durchfahrt; Hard-Block dort → NO_ROUTE.
  if (opts.avoidHighways) {
    // HARTER Block via priority 0 = „Kante komplett meiden" (GH-Doku). Live-Test
    // 2026-06-03 bewies: speed.limit_to=0 wirkt im round_trip-Algorithmus NICHT
    // (uses_motorway blieb true MITTEN in der Route, start_on_motorway=false).
    // priority dagegen wird angewandt — die Stil-Overlays sind alle priority-
    // basiert und differenzieren klar. Darum Motorway hart auf priority 0.
    overlay.priority.push({ if: 'road_class == MOTORWAY', multiply_by: '0' });
    // Trunk (Bundes-/Schnellstraße): stark bestraft, NICHT 0 — in Alpentälern
    // (Inntal: A12 ‖ B171) oft einzige Durchfahrt; Hard-Block dort → NO_ROUTE.
    overlay.priority.push({ if: 'road_class == TRUNK', multiply_by: '0.05' });
    // speed.limit_to=0 zusätzlich als Gürtel-und-Hosenträger (schadet nicht).
    overlay.speed!.push({ if: 'road_class == MOTORWAY', limit_to: '0' });
  }
  // Doppelter Schutz: Ferry zusätzlich noch hohe priority-Penalty
  overlay.priority.push({ if: 'road_environment == FERRY', multiply_by: '0.001' });
  // 2026-05-27 (vucko Quality-Fix): Track/Service/Path universell ausschließen.
  // Diese Klassen sind in OSM oft Forst-/Wirtschaftswege, Service-Roads zu
  // Parkplätzen, oder unbefahrbare Fußwege. Sie waren bisher NIRGENDS
  // penalisiert → GraphHopper hat sie regelmäßig in Sport/Kurvenjagd-Routen
  // eingebaut wenn sie kurzer oder „kurviger" waren. User-Beschwerde:
  // „komische Nebenstraßen ohne Grund". Multiply_by 0.05 = praktisch
  // ausgeschlossen ohne Hard-Block (falls eine Route wirklich nur darüber
  // funktioniert, GH kann immer noch eskalieren).
  // 2026-06-06 (vucko P5): HARTE Sperre für nicht-PKW-Wege. User-Feedback aus
  // Test-Rundkurs: die Route führte über Traktor-/Feldwege (TRACK) und Wege, die
  // ein PKW NICHT befahren darf. priority 0 = ECHTER Hard-Block (GraphHopper:
  // ConnectionNotFound auf der Kante, NICHT eskalierbar — gleiche Mechanik wie
  // der Motorway-Block oben). Bewusst: lieber NO_ROUTE als eine Route über einen
  // Feldweg. SERVICE bleibt nur mild bestraft (legitime Zufahrten nötig, sonst
  // würden Start/Ziel an Service-Roads unerreichbar). road_class ist derselbe
  // Encoded-Value wie bisher → safe (kein Graph-Re-Import nötig).
  overlay.priority.push({ if: 'road_class == TRACK', multiply_by: '0' });
  overlay.priority.push({ if: 'road_class == PATH', multiply_by: '0' });
  overlay.priority.push({ if: 'road_class == FOOTWAY', multiply_by: '0' });
  overlay.priority.push({ if: 'road_class == PEDESTRIAN', multiply_by: '0' });
  overlay.priority.push({ if: 'road_class == STEPS', multiply_by: '0' });
  overlay.priority.push({ if: 'road_class == BRIDLEWAY', multiply_by: '0' });
  overlay.priority.push({ if: 'road_class == CYCLEWAY', multiply_by: '0' });
  overlay.priority.push({ if: 'road_class == SERVICE', multiply_by: '0.15' });
  if (opts.preferMainRoads) {
    // 2026-06-16 (Codex): Standard-A→B/Trip/Reroute dürfen nicht mehr über
    // Mini-Nebenstraßen gewinnen, wenn Hauptstraßen/Autobahn sinnvoll sind.
    // GraphHopper Custom-Models erlauben serverseitig keine Boosts >1; deshalb
    // lassen wir die gewünschten Klassen bei 1 und werten Nebenstraßen ab.
    if (!opts.avoidHighways) {
      overlay.priority.push({ if: 'road_class == TRUNK', multiply_by: '0.88' });
      overlay.priority.push({ if: 'road_class == PRIMARY', multiply_by: '0.78' });
      overlay.priority.push({ if: 'road_class == SECONDARY', multiply_by: '0.70' });
      overlay.priority.push({ if: 'road_class == TERTIARY', multiply_by: '0.45' });
      overlay.priority.push({ if: 'road_class == UNCLASSIFIED', multiply_by: '0.32' });
      overlay.priority.push({ if: 'road_class == RESIDENTIAL', multiply_by: '0.22' });
    } else {
      overlay.priority.push({ if: 'road_class == SECONDARY', multiply_by: '0.88' });
      overlay.priority.push({ if: 'road_class == TERTIARY', multiply_by: '0.55' });
      overlay.priority.push({ if: 'road_class == UNCLASSIFIED', multiply_by: '0.35' });
      overlay.priority.push({ if: 'road_class == RESIDENTIAL', multiply_by: '0.24' });
    }
  } else {
    // Scenic/Rundkurs bleibt wie bisher: Autobahn mild abwerten, außer sie ist
    // klar schneller. Standard-A→B bekommt diese Abwertung bewusst NICHT.
    overlay.priority.push({ if: 'road_class == MOTORWAY', multiply_by: '0.6' });
  }
  // 2026-06-10 (vucko GH-Default-Konformitaet): Der GH-Server lief bis heute
  // mit gelockerter Config; nach Neustart gelten die GH-Defaults: in
  // Query-CustomModels darf multiply_by NICHT > 1 sein (HTTP 400: "maximum of
  // value '1.45' cannot be larger..."). Dadurch platzten ALLE Requests mit
  // Boost-Werten -> Notfall-Mini-Routen ("katastrophal"-Screenshot).
  // Fix: Prioritaeten normalisieren — alle multiply_by durch den groessten
  // Wert teilen. Die relative Ordnung (= der Stil-Charakter) bleibt erhalten,
  // das Modell ist serverkonform.
  if (overlay.priority.length > 0) {
    let maxMul = 1;
    for (const rule of overlay.priority) {
      const v = Number(rule.multiply_by);
      if (Number.isFinite(v) && v > maxMul) maxMul = v;
    }
    if (maxMul > 1) {
      for (const rule of overlay.priority) {
        const v = Number(rule.multiply_by);
        if (Number.isFinite(v)) {
          rule.multiply_by = String(Math.min(1, Math.round((v / maxMul) * 100) / 100));
        }
      }
    }
  }
  const baseUrl = opts.serverUrl ?? GRAPHHOPPER_URL;

  // 2026-08-09 (vucko): Overlay auf das zuschneiden, was DIESER Server kann.
  // Regeln mit unbekanntem Encoded Value (z. B. `curvature` auf PC2) wuerden
  // sonst die ganze Anfrage mit HTTP 400 killen — genau das war die Ursache
  // dafuer, dass sich die Fahrstile nicht unterschieden haben.
  const caps = await serverCapabilities(baseUrl);
  if (caps != null) {
    const prio = overlayAufServerZuschneiden(overlay.priority, caps);
    const spd = overlayAufServerZuschneiden(overlay.speed ?? [], caps);
    if (prio.entfernt.length > 0 || spd.entfernt.length > 0) {
      console.warn(
        `[OVERLAY-TRIM] ${baseUrl} kennt Teile des Stil-Modells nicht — ` +
        `${[...prio.entfernt, ...spd.entfernt].join(' | ')}`,
      );
    }
    overlay.priority = prio.behalten;
    overlay.speed = spd.behalten;
    // Profil proaktiv ersetzen statt auf den 400 zu warten.
    if (caps.profiles.size > 0 && !caps.profiles.has(ghBody.profile)) {
      const ersatz = ghBody.profile === 'car'
        ? (caps.profiles.has('motorcycle_abendrunde') ? 'motorcycle_abendrunde' : [...caps.profiles][0])
        : (caps.profiles.has('motorcycle_scenic') ? 'motorcycle_scenic' : [...caps.profiles][0]);
      console.warn(
        `[PROFILE-TRIM] ${baseUrl} kennt '${ghBody.profile}' nicht — nutze '${ersatz}'`,
      );
      ghBody.profile = ersatz;
    }
  }
  if (
    !opts._ohneOverlay &&
    (overlay.priority.length > 0 || overlay.distance_influence != null ||
      (overlay.speed?.length ?? 0) > 0)
  ) {
    // Objekt, NICHT JSON.stringify — geht jetzt im POST-Body an GraphHopper.
    ghBody.custom_model = overlay;
  }

  const url = `${baseUrl}/route`;
  // 2026-06-02 (vucko): Per-Call-Timeout + externes Abort-Signal. Ein hängender
  // GraphHopper-Call wird nach GH_FETCH_TIMEOUT_MS hart abgebrochen (statt die
  // Funktion bis zum Plattform-Limit zu blockieren), und der Round-Trip-Racer
  // kann nicht mehr benötigte Calls vorzeitig abbrechen (spart GH-Last).
  const timeoutCtrl = new AbortController();
  const timeoutId = setTimeout(
    () => timeoutCtrl.abort(),
    opts.timeoutMs ?? GH_FETCH_TIMEOUT_MS,
  );
  if (opts.signal) {
    if (opts.signal.aborted) timeoutCtrl.abort();
    else opts.signal.addEventListener('abort', () => timeoutCtrl.abort(), { once: true });
  }
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(ghBody),
      signal: timeoutCtrl.signal,
    });
    if (!res.ok) {
      const bodyText = (await res.text()).slice(0, 300);
      // 2026-06-29 (vucko Config-Drift-Schutz): Wenn der Server das angefragte
      // Profil NICHT kennt (typisch nach einem Mini-PC-Config-Drift, bei dem
      // z.B. 'car' fehlt), liefert GraphHopper HTTP 400 "The requested profile
      // '…' does not exist". Statt die ganze Route sterben zu lassen, retryen
      // wir EINMAL mit einem garantiert vorhandenen Motorrad-Profil. Für 'car'
      // (Direkt-/Schnellste-Intent) ist 'motorcycle_abendrunde' am direktesten
      // (geringster Kurven-Bonus); sonst der Universal-Default 'motorcycle_scenic'.
      if (
        res.status === 400 &&
        /does not exist/i.test(bodyText) &&
        !opts._profileFallbackFrom
      ) {
        clearTimeout(timeoutId);
        const fallbackProfile = opts.profile === 'car'
          ? 'motorcycle_abendrunde'
          : 'motorcycle_scenic';
        console.warn(
          `[PROFILE-FALLBACK] Server kennt Profil '${opts.profile}' nicht — ` +
          `retry mit '${fallbackProfile}' (Server out-of-sync?). Body: ${bodyText.slice(0, 120)}`,
        );
        return await callGraphHopper({
          ...opts,
          profile: fallbackProfile,
          _profileFallbackFrom: opts.profile,
        });
      }
      // 2026-08-09 (vucko): Letzte Stufe. Wenn der Server das Stil-Modell nicht
      // uebersetzen kann (unbekannter Encoded Value, geaenderte Server-Config),
      // wird EINMAL ohne Overlay wiederholt. Eine Route ohne Stil ist immer
      // besser als eine Fehlermeldung — der Auftrag lautet „immer eine Route".
      if (
        res.status === 400 &&
        /Cannot compile expression|not available|custom_model/i.test(bodyText) &&
        !opts._ohneOverlay
      ) {
        clearTimeout(timeoutId);
        console.warn(
          `[OVERLAY-FALLBACK] ${baseUrl} lehnt das Stil-Modell ab — retry ohne ` +
          `Overlay. Body: ${bodyText.slice(0, 140)}`,
        );
        return await callGraphHopper({ ...opts, _ohneOverlay: true });
      }
      return { error: `GraphHopper HTTP ${res.status}: ${bodyText.slice(0, 200)}` };
    }
    const data: GraphHopperResponse = await res.json();
    if (!data.paths || data.paths.length === 0) {
      return { error: data.message ?? 'GraphHopper returned no paths' };
    }
    const p = data.paths[0];
    const coords = p.points.coordinates;
    const distanceKm = p.distance / 1000;
    // 2026-05-23 (vucko Bug-Fix Bodensee-Ferry): GraphHopper Custom-Model
    // mit road_environment==FERRY wird nicht zuverlässig durchgesetzt
    // (bleibt im Routing). Post-Process: wenn die Route Edges mit
    // >1500m zwischen 2 aufeinanderfolgenden Punkten hat UND wir nicht
    // round_trip sind → Ferry-Verdacht → als Error zurückgeben damit
    // upper layer retry mit anderem Snap-Offset macht.
    //
    // 2026-05-24 (vucko Fix für FH→Wien false-positive): Ferry-Detection
    // NUR für motorcycle-Profile mit avoidHighways aktivieren. Bei `car`
    // ohne avoidHighways wollen wir Autobahn-Edges, die ohnehin oft große
    // Knotenabstände haben. Plus 6km-Schwelle statt 1.5km — Bodensee-Fähre
    // ist ~12km, Autobahn-Edges selten >6km.
    const isMotorcycleProfile = opts.profile.startsWith('motorcycle');
    if (!opts.isRoundTrip && isMotorcycleProfile) {
      let suspiciousEdgeCount = 0;
      let longestEdgeMeters = 0;
      for (let i = 1; i < Math.min(coords.length, 200); i++) {
        const c1 = coords[i - 1];
        const c2 = coords[i];
        // Haversine in Meter
        const R = 6371000;
        const lat1 = (c1[1] * Math.PI) / 180;
        const lat2 = (c2[1] * Math.PI) / 180;
        const dLat = ((c2[1] - c1[1]) * Math.PI) / 180;
        const dLng = ((c2[0] - c1[0]) * Math.PI) / 180;
        const a = Math.sin(dLat / 2) ** 2 +
          Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
        const d = 2 * R * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        // Erhöht von 1500m → 4000m: vermeidet false-positives bei Autobahn-Edges
        // ohne dichten Knotenraster (z.B. zwischen Anschlussstellen).
        if (d > 4000) suspiciousEdgeCount++;
        if (d > longestEdgeMeters) longestEdgeMeters = d;
      }
      // Schwelle von 2 → 3 Edges: noch konservativer false-positive-Schutz.
      if (suspiciousEdgeCount >= 3) {
        return {
          error: `Ferry detected: ${suspiciousEdgeCount} edges >4km (longest ${Math.round(longestEdgeMeters)}m)`,
        };
      }
    }
    // 2026-05-28 (vucko Task #82): Echte Autobahn-Nutzung aus den
    // road_class-Details ableiten. road_class-Details kommen als
    // [from, to, value]-Segmente; MOTORWAY/TRUNK = Autobahn-artig.
    const roadClassSegments = p.details?.road_class ?? [];
    const upperSegs = roadClassSegments.map(
      (seg: [number, number, string | number]) => String(seg[2] ?? '').toUpperCase(),
    );
    // 2026-06-03 (vucko): Motorway (Autobahn) und Trunk (Schnellstraße) GETRENNT
    // erfassen. avoid_highways blockt Motorway HART; Trunk darf als Alpen-
    // Notausgang bleiben → Selektion + Scoring behandeln beide getrennt.
    const usesMotorway = upperSegs.includes('MOTORWAY');
    const usesTrunk = upperSegs.includes('TRUNK');
    const hasHighway = usesMotorway || usesTrunk;
    const leadingSegment = upperSegs.length > 0 ? upperSegs[0] : '';
    const startOnMotorway =
      leadingSegment === 'MOTORWAY' || leadingSegment === 'TRUNK';
    const classMeters: Record<string, number> = {};
    let detailMeters = 0;
    for (const seg of roadClassSegments) {
      const from = Math.max(0, Number(seg[0]) || 0);
      const to = Math.min(coords.length - 1, Number(seg[1]) || 0);
      const cls = String(seg[2] ?? 'UNKNOWN').toUpperCase();
      let meters = 0;
      for (let i = from + 1; i <= to && i < coords.length; i++) {
        meters += distanceMeters(coords[i - 1][1], coords[i - 1][0], coords[i][1], coords[i][0]);
      }
      classMeters[cls] = (classMeters[cls] ?? 0) + meters;
      detailMeters += meters;
    }
    const denomMeters = detailMeters > 0 ? detailMeters : Math.max(1, p.distance);
    const fractionFor = (...classes: string[]) =>
      Number((classes.reduce((sum, cls) => sum + (classMeters[cls] ?? 0), 0) / denomMeters).toFixed(3));
    const motorwayFraction = fractionFor('MOTORWAY');
    const majorRoadFraction = fractionFor('MOTORWAY', 'TRUNK', 'PRIMARY', 'SECONDARY');
    const minorRoadFraction = fractionFor('TERTIARY', 'UNCLASSIFIED', 'RESIDENTIAL', 'SERVICE');
    const residentialFraction = fractionFor('RESIDENTIAL');
    const serviceFraction = fractionFor('SERVICE');
    const instructions = p.instructions ?? [];
    // 2026-06-03 (vucko): echte U-Turns aus den GraphHopper-Instructions zählen
    // (sign -8/8 = U-Turn links/rechts, -98 = U-Turn unbekannte Richtung). Das
    // ist der „hässliche U-Turn in einer Einfahrt", über den der User klagt —
    // Selektion + Best-of-N-Scoring bestrafen ihn jetzt.
    const uTurnCount = instructions.filter((i) => {
      const s = (i as Record<string, unknown>).sign;
      return s === -8 || s === 8 || s === -98;
    }).length;
    // 2026-08-18 (Aufgabe 1.4, vucko am 16.08.): „Die Strecken muessen sauber
    // sein und nicht in eine Richtung und dann die gleiche Strasse wieder
    // zurueckfinden." u_turn_count sieht NUR Wenden, die GraphHopper selbst
    // signalisiert. Diese Kennzahl sieht die Faelle ohne Vorzeichen: Schleife
    // durchs Dorf und auf der Parallelfahrbahn zurueck.
    const selbstUeberlappung = selbstUeberlappungAnteil(coords as [number, number][]);
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
        has_highway: hasHighway,
        actual_has_highway: hasHighway,
        uses_motorway: usesMotorway,
        uses_trunk: usesTrunk,
        u_turn_count: uTurnCount,
        self_overlap_fraction: selbstUeberlappung,
        start_on_motorway: startOnMotorway,
        prefer_main_roads: opts.preferMainRoads === true,
        motorway_distance_fraction: motorwayFraction,
        major_road_distance_fraction: majorRoadFraction,
        minor_road_distance_fraction: minorRoadFraction,
        residential_distance_fraction: residentialFraction,
        service_distance_fraction: serviceFraction,
      },
      instructions,
    };
  } catch (e) {
    return { error: `GraphHopper fetch failed: ${(e as Error).message}` };
  } finally {
    clearTimeout(timeoutId);
  }
}

// 2026-06-02 (vucko Routing-Speed): Feuert alle Promises parallel und gibt
// SOFORT [ersterAkzeptabler] zurück, sobald einer die Schwelle erfüllt — die
// restlichen Calls werden vom Aufrufer abgebrochen. Erfüllt KEINER die
// Schwelle, kommen am Ende ALLE gesammelten Ergebnisse zurück, sodass das
// normale Best-of-N-Scoring den besten verfügbaren wählt. So hängt die
// Live-Suche nicht mehr am langsamsten von N parallelen GraphHopper-Calls
// (Promise.all = langsamster gewinnt → 9-11s; hier: erster guter → ~2-4s).
async function raceForFirstAcceptable<T>(
  promises: Array<Promise<T>>,
  isAcceptable: (v: T) => boolean,
): Promise<T[]> {
  if (promises.length === 0) return [];
  return await new Promise<T[]>((resolve) => {
    const collected: T[] = [];
    let done = false;
    let remaining = promises.length;
    for (const p of promises) {
      p.then((v) => {
        collected.push(v);
        if (!done && isAcceptable(v)) {
          done = true;
          resolve([v]);
        }
      }).catch(() => {
        /* Fehler/Abbruch zählt als nicht akzeptabel */
      }).finally(() => {
        remaining--;
        if (remaining === 0 && !done) {
          done = true;
          resolve(collected);
        }
      });
    }
  });
}

// ─────────────────── Route-Generation mit Retries + Compensation ───────────

// ── Abdeckungs-Vorabpruefung (2026-08-18, D1c) ───────────────────────────────
// Gemessen am 18.08.: 165 `coverage_out_of_bounds` in 14 Tagen, davon 113 von
// einem einzigen Nutzer. Bisher merkte die Edge das erst, NACHDEM sie bis zu
// acht GraphHopper-Versuche verbraucht hatte — und meldete es als 502, also
// als „unser Server spinnt gerade, versuch es nochmal". Der Nutzer versuchte
// es nochmal. 113-mal.
//
// Die Wahrheit steht in GraphHopper selbst: `/info` liefert die Bounding-Box
// des importierten Graphen.
//
// Gemessen am 18.08. frueh: lat 32.90..50.57 — die Nordkante lief quer durch
// Deutschland, Frankfurt war die noerdlichste erreichbare Grossstadt. Koeln,
// Duesseldorf, Dortmund, Hannover, Leipzig, Dresden, Berlin und Hamburg
// bekamen nie eine Route, egal wie oft jemand tippte.
//
// Am 18.08. nachmittags behoben: Norddeutschland wurde in den Ausschnitt
// aufgenommen, ohne im Sueden etwas aufzugeben (Griechenland, Tuerkei und
// Rumaenien sind unveraendert drin). Bezahlt wurde das damit, dass PC2
// keine Fuss- und Radwege mehr importiert — 28,5 Millionen Kanten, die kein
// Auto und kein Motorrad je befahren kann.
//
// WICHTIG: Die Quelle ist der Graph, NICHT die Tabelle `route_pool_coverage`.
// Die kennt nur Vorarlberg, Baden-Wuerttemberg und Wien und wuerde Villach,
// Klagenfurt, Innsbruck und Muenchen faelschlich abweisen — die funktionieren
// heute nachweislich.
interface GhBbox { minLng: number; minLat: number; maxLng: number; maxLat: number }
let _bboxCache: { at: number; boxes: GhBbox[] } | null = null;
const BBOX_CACHE_MS = 10 * 60 * 1000;
// Rueckfallwert = die am 18.08. auf PC1 und PC2 gemessene Box. Wird nur
// benutzt, wenn `/info` gerade nicht erreichbar ist; dann lieber grosszuegig
// durchlassen als faelschlich abweisen.
const BBOX_FALLBACK: GhBbox = { minLng: -5.52, minLat: 32.90, maxLng: 41.66, maxLat: 50.57 };

async function graphhopperBboxes(): Promise<GhBbox[]> {
  const now = Date.now();
  if (_bboxCache && now - _bboxCache.at < BBOX_CACHE_MS) return _bboxCache.boxes;
  const urls = [...new Set([GRAPHHOPPER_URL, GRAPHHOPPER_DE_URL, GRAPHHOPPER_EU_URL])];
  const boxes: GhBbox[] = [];
  await Promise.all(urls.map(async (u) => {
    try {
      const ctrl = new AbortController();
      const t = setTimeout(() => ctrl.abort(), 2500);
      const r = await fetch(`${u}/info`, { signal: ctrl.signal });
      clearTimeout(t);
      if (!r.ok) return;
      const j = await r.json() as { bbox?: number[] };
      const b = j?.bbox;
      if (Array.isArray(b) && b.length === 4 && b.every((n) => typeof n === 'number')) {
        boxes.push({ minLng: b[0], minLat: b[1], maxLng: b[2], maxLat: b[3] });
      }
    } catch (_) {
      // Server gerade nicht erreichbar — zaehlt nicht als „ausserhalb".
    }
  }));
  const ergebnis = boxes.length > 0 ? boxes : [BBOX_FALLBACK];
  _bboxCache = { at: now, boxes: ergebnis };
  return ergebnis;
}

// Kleiner Rand, damit ein Punkt exakt auf der Kante nicht abgewiesen wird.
const BBOX_RAND_GRAD = 0.02;

function ausserhalbAllerBoxen(lat: number, lng: number, boxes: GhBbox[]): boolean {
  return !boxes.some((b) =>
    lat >= b.minLat - BBOX_RAND_GRAD && lat <= b.maxLat + BBOX_RAND_GRAD &&
    lng >= b.minLng - BBOX_RAND_GRAD && lng <= b.maxLng + BBOX_RAND_GRAD);
}

/// Traegt einen Punkt ausserhalb der Abdeckung in die Warteliste ein, damit wir
/// zum ersten Mal WISSEN, wo die Nutzer sitzen, die nie eine Route bekommen.
/// Best-effort: ein Fehler hier darf die Antwort nie aufhalten.
function merkeAbdeckungswunsch(
  lat: number, lng: number, userId: string | null, land: string | null,
): void {
  if (!_rlAdmin) return;
  const p: Promise<void> = Promise.resolve(
    _rlAdmin.from('coverage_requests').insert({
      user_id: userId,
      lat: Math.round(lat * 1000) / 1000,
      lng: Math.round(lng * 1000) / 1000,
      country_code: land,
    }),
  ).then(() => {}, () => {});
  const er = (globalThis as { EdgeRuntime?: { waitUntil?: (x: Promise<unknown>) => void } }).EdgeRuntime;
  if (er?.waitUntil) er.waitUntil(p); else void p;
}

async function generateRoute(req: RouteRequest): Promise<Response> {
  // 2026-07-03 (vucko Wegpunkte-jede-Distanz, Geräte-Video 07-03): Pflicht-
  // Wegpunkte als echte durchgeroutete Punktkette behandeln — NICHT als
  // round_trip-Zufallsschleife (die die Stopps komplett ignorierte). Wir
  // schreiben die Anfrage in eine A→B-Anfrage mit Zwischen-Wegpunkten um:
  // Start → WP1 → … → (Start bei close_loop, sonst letzter WP). Damit greift die
  // bereits robuste A→B-Maschinerie inkl. Ultimate-car-Fallback (Zeile ~1836) →
  // bei JEDER Distanz zwischen den Punkten eine Route (schnellster Weg, car-
  // Profil), ohne Distanz-/U-Turn-/±12%-Rundkurs-Rejects. Die frühere Client-
  // Distanzsperre `waypoint_too_far` entfällt separat im route_service.dart.
  {
    const reqWps = req.required_waypoints;
    const startLoc = req.start_location ?? req.startLocation;
    if (
      req.waypoint_mode === 'required_stops' &&
      reqWps &&
      reqWps.length > 0 &&
      startLoc
    ) {
      const closeLoop = req.close_loop !== false;
      // Bei geschlossenem Rundkurs sind ALLE Stopps Zwischenpunkte und das Ziel
      // ist wieder der Start; bei offener Kette wird der letzte Stopp zum Ziel.
      const chain = closeLoop ? reqWps : reqWps.slice(0, -1);
      const target = closeLoop ? startLoc : reqWps[reqWps.length - 1];
      console.log(
        `[WAYPOINT-CHAIN] required_stops=${reqWps.length} close_loop=${closeLoop} → A→B car/fastest chain`,
      );
      req = {
        ...req,
        route_type: 'POINT_TO_POINT',
        waypoints: chain,
        target_location: target,
        targetLocation: target,
        detour_level: 0, // → isDirectFastest → car/fastest, kein Sport-Overlay
        selected_style: '', // leer = kein STYLE_TO_PROFILE-Treffer → car
        mode: '',
      };
    }
  }
  const isRoundTrip = req.route_type === 'ROUND_TRIP';
  // 2026-06-09 (vucko Direkt-Fastest-Fix): Eine DIREKTE A→B-Route (Detour 0, Stil
  // 'Standard'/unbekannt) UND jeder Reroute sollen die SCHNELLSTE Strecke fahren
  // (Google/Apple-Niveau) — NICHT die kurvige Sport-Gewichtung. ROOT CAUSE des
  // User-Reports (Götzis→Hard, +27% Umweg-Schleife): resolveProfile() fiel für
  // 'Standard' auf 'motorcycle_scenic' zurück → Kurven-Bonus + Scenic-Road-Boost +
  // distance_influence 200 → GraphHopper bevorzugte kurvige Umwege statt des
  // direkten Wegs. Das 'car'-Profil trifft den leeren default-Overlay (kein
  // Kurven-/Scenic-Bonus) + nur die Safety-Blocks (Track/Path/Ferry/Autobahn) →
  // kürzeste sinnvolle Strecke. Cruising-Stile (Sport/Kurvenjagd/…) + Umwege
  // (detour_level>0) bleiben unverändert kurvig.
  const _rawStyle = (req.selected_style ?? '').trim().toLowerCase();
  const isDirectFastest =
    !isRoundTrip &&
    (req.detour_level ?? 0) === 0 &&
    !STYLE_TO_PROFILE[_rawStyle];
  const profile = isDirectFastest ? 'car' : resolveProfile(req.selected_style);
  const previousFps = new Set(req.previous_route_fingerprints ?? []);
  const startLocation = req.start_location;
  if (!startLocation) {
    return jsonResponse({
      error: 'missing_start_location',
      user_message: 'Startposition fehlt.',
      debug_message: 'Edge v2: missing start_location',
    }, 400);
  }
  // ── Abdeckung PRUEFEN, bevor GraphHopper acht Mal vergeblich rechnet ──
  const _boxen = await graphhopperBboxes();
  const _zuPruefen: Array<{ lat: number; lng: number; was: string }> = [
    { lat: startLocation.latitude, lng: startLocation.longitude, was: 'Startpunkt' },
  ];
  if (req.target_location) {
    _zuPruefen.push({
      lat: req.target_location.latitude,
      lng: req.target_location.longitude,
      was: 'Ziel',
    });
  }
  for (const wp of req.waypoints ?? []) {
    _zuPruefen.push({ lat: wp.latitude, lng: wp.longitude, was: 'Zwischenstopp' });
  }
  const _draussen = _zuPruefen.find((pt) => ausserhalbAllerBoxen(pt.lat, pt.lng, _boxen));
  if (_draussen) {
    merkeAbdeckungswunsch(
      _draussen.lat,
      _draussen.lng,
      req._subject_id ?? null,
      classifyCountry(_draussen.lat, _draussen.lng),
    );
    return jsonResponse({
      error: 'coverage_out_of_bounds',
      user_message: _draussen.was === 'Startpunkt'
        ? 'Deine Region ist noch nicht freigeschaltet. Wir bauen die Abdeckung ' +
          'Schritt für Schritt aus und haben deine Gegend jetzt vorgemerkt. ' +
          'Routen funktionieren derzeit in ganz Deutschland, Österreich und ' +
          'der Schweiz, dazu Norditalien und der Balkan bis Griechenland.'
        : `Dein ${_draussen.was} liegt außerhalb unseres Liefergebiets. ` +
          'Wir decken derzeit ganz Deutschland, Österreich und die Schweiz ab, ' +
          'dazu Norditalien und den Balkan bis Griechenland.',
      debug_message:
        `coverage_precheck ${_draussen.was} lat=${_draussen.lat.toFixed(4)} lng=${_draussen.lng.toFixed(4)} boxes=${JSON.stringify(_boxen)}`,
      region: classifyCountry(_draussen.lat, _draussen.lng) ?? 'unknown',
      waitlisted: _draussen.was === 'Startpunkt',
    }, 422);
  }

  const countryPreference = normalizeCountryPreference(req.country_preference);
  // 2026-08-18 (D1b2): Das Heimatland wird SELBST aus dem Startpunkt
  // abgeleitet, nicht vom Client uebernommen. Grund: Client und Edge hatten
  // beide dieselbe kaputte Laenderlogik (Villach/Lienz -> IT, Klagenfurt -> SI)
  // und hoben sich dadurch gegenseitig auf. Repariert man nur eine Seite,
  // verlieren genau diese Nutzer ihre Routen — alte App-Versionen bleiben
  // installiert und senden weiter den falschen Wert. Der Startpunkt ist die
  // einzige Quelle, die beide Seiten gleich sehen.
  const _homeAusStart = classifyCountry(startLocation.latitude, startLocation.longitude);
  const homeCountryCode = _homeAusStart ?? normalizeCountryCode(req.home_country_code);
  const strictInland =
    isRoundTrip &&
    (req.avoid_cross_border === true || countryPreference === 'only_home') &&
    homeCountryCode != null;

  // Adaptive Distance Compensation (nur für Round-Trip relevant)
  const region = classifyRegion(startLocation.latitude, startLocation.longitude);
  // 2026-06-03 (vucko): `let` statt `const` — die adaptive Distanz-Korrektur
  // unten justiert round_trip.distance nach, wenn GH in engem Terrain daneben
  // liegt (tryServerWithProfile liest diesen Wert zur Call-Zeit aus dem Closure).
  let effectiveDistanceKm = isRoundTrip && req.target_distance_km
    ? req.target_distance_km * region.factor
    : req.target_distance_km;

  // Seed-Strategie für Round-Trip:
  // - Initial Search: seed aus Hash(startLat, startLng, distance) — deterministisch erste Variante
  // - Search Again (force_fresh): seed aus Timestamp + 137° rotation (Calimoto-Pattern)
  // - Retry bei previous fingerprint match: nächster seed
  const seeds = generateSeeds({
    forceFresh: req.force_fresh_variant ?? false,
    startLat: startLocation.latitude,
    startLng: startLocation.longitude,
    targetKm: req.target_distance_km ?? 50,
    avoidHighways: req.avoid_highways === true,
    styleKey: _rawStyle,
    detourLevel: req.detour_level ?? 0,
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
  const detourSpec: Array<{ bearing: number; distKm: number; side: -1 | 1; family: number; along: number }> = [];
  // 2026-08-18 (Aufgabe 1.3): Welcher Term die Umweg-Basisdistanz bestimmt hat,
  // wandert ins Antwort-Meta. Ohne diese Anzeige ist im Feld nicht zu sehen,
  // dass ein Term im Math.max wirkungslos ist — genau so blieb der falsche
  // Kommentar monatelang unbemerkt.
  let detourBasisTerm: UmwegBasisTerm | undefined;
  if (!isRoundTrip && req.target_location && detourLevel > 0) {
    const directKm = (() => {
      const R = 6371;
      const toRad = (d: number) => (d * Math.PI) / 180;
      const dLat = toRad(req.target_location.latitude - startLocation.latitude);
      const dLng = toRad(req.target_location.longitude - startLocation.longitude);
      const a = Math.sin(dLat/2)**2 + Math.cos(toRad(startLocation.latitude))
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
    const detourFactor = Math.max(1, finiteNumberOr(req.detour_factor, 1));
    const requestedTargetKm = finiteNumberOr(req.target_distance_km, directKm);
    // 2026-08-18 (Aufgabe 1.3): war ein Math.max mit vier Termen, von denen
    // einer (baseFactor 0,15/0,30/0,50) nachweislich nie gewinnen konnte.
    // Herleitung und Zahlen stehen bei umwegBasisKm().
    const umwegBasis = umwegBasisKm({
      directKm,
      detourLevel,
      detourFactor,
      requestedTargetKm,
      profileMultiplier: profileDetourMultiplier,
    });
    const baseKm = umwegBasis.km;
    detourBasisTerm = umwegBasis.term;
    const variantSeed =
      Math.abs(Math.round(finiteNumberOr(req.randomSeed, 0))) +
      stableHashInt(req.route_variant_hint) +
      (req.force_fresh_variant ? Date.now() % 1009 : 0);
    const preferredSide = normalizeOffsetSide(req.offset_side, variantSeed);
    // Bearing-Sets pro Stil unterschiedlich damit Routes sich klar
    // unterscheiden (sonst pickt GH die kürzeste path egal welches profile).
    const absBearingsForStyle = profile === 'motorcycle_kurvenjagd'
      ? [90, 120, 60, 135, 75, 105]  // breit + tief — viele Optionen
      : profile === 'motorcycle_scenic'
      ? [75, 60, 90, 105, 45, 120]   // schmaler Spread — Cruiser-feeling
      : profile === 'motorcycle_abendrunde'
      ? [60, 45, 75, 90, 35]         // wenig Umweg
      : [80, 100, 60, 120, 45, 95];  // entdecker: variability
    const rotation = absBearingsForStyle.length > 0
      ? variantSeed % absBearingsForStyle.length
      : 0;
    const rotatedAbsBearings = [
      ...absBearingsForStyle.slice(rotation),
      ...absBearingsForStyle.slice(0, rotation),
    ];
    const bearingsForStyle = [
      ...rotatedAbsBearings.map((b) => b * preferredSide),
      ...rotatedAbsBearings.map((b) => -b * preferredSide),
    ];
    // 2026-08-16 (vucko Testfahrt T3): mehr Kandidaten je Stufe (4/6/8 →
    // 8/12/14) und das Via zusaetzlich bei 38 % / 62 % der Direktlinie statt
    // nur in der Mitte. Live-Befund: Mit nur einem Mitten-Via hatte fast
    // jede Umweg-Route eine Wende (Stachel: hin und auf demselben Weg
    // zurueck) — es fehlte schlicht an Kandidaten OHNE Wende. Die Kandidaten
    // laufen parallel, die Latenz bleibt bei der laengsten Einzelanfrage.
    // 2026-08-18 (Aufgabe 1.3): Stufe 1 hatte mit 8 die WENIGSTEN Kandidaten
    // (gegen 12 und 14) — bei zwei Distanzen je Peilung sind das nur 4
    // Peilungen, ausgerechnet dort, wo wendefreie Kandidaten am knappsten
    // sind: ein kleiner seitlicher Versatz landet oft in einer Sackgasse oder
    // im Wohngebiet, aus dem GraphHopper nur mit Wenden herauskommt. Stufe 1
    // bekommt jetzt 12, also 6 Peilungen statt 4.
    //
    // KOSTEN: keine zusaetzliche Latenz. Die Kandidaten werden weiter unten in
    // EINEM Promise.all abgefeuert (Suche nach „detourLevel > 0: parallel mit
    // verschiedenen Sub-Waypoint-Positionen"), die Antwortzeit ist also die
    // laengste EINZELNE GraphHopper-Anfrage, nicht ihre Summe. Was steigt, ist
    // die Last auf GraphHopper: 4 zusaetzliche gleichzeitige Anfragen je
    // Stufe-1-Suche. Stufe 3 faehrt mit 14 schon laenger so.
    const limit = detourLevel === 1 ? 12 : detourLevel === 2 ? 12 : 14;
    // 2026-05-22 (vucko Task #11): Pro Bearing zwei distanzen probieren —
    // wenn der primäre Sub-WP im Wasser/Berg landet, fängt der kleinere
    // baseKm-Wert oft trotzdem. Verdoppelt effektiv die Erfolgsrate
    // ohne Latenz zu sprengen (Promise.all parallel).
    const seedJitter = 0.90 + (variantSeed % 17) / 100;
    // 2026-08-16 (T3): Nur noch zwei Distanzen je Peilung (Basis + kleiner).
    // Die 1,22-fache Variante fuer mittel/gross ist raus — Ueberschuss war
    // das Problem, nicht Mangel — dafuer decken die Kandidaten mehr Peilungen
    // ab (verschiedene Taeler/Strassen → mehr wendefreie Kandidaten).
    const distanceVariants = detourLevel >= 2
      ? [baseKm * seedJitter, Math.max(2, baseKm * 0.68)]
      : [baseKm * seedJitter, Math.max(2, baseKm * 0.62)];
    const alongVariants = [0.5, 0.38, 0.62];
    let alongIdx = variantSeed % alongVariants.length;
    for (const b of bearingsForStyle) {
      for (const d of distanceVariants) {
        const side = b < 0 ? -1 : 1;
        const along = alongVariants[alongIdx % alongVariants.length];
        alongIdx++;
        detourSpec.push({ bearing: b, distKm: d, side, family: detourSpec.length, along });
        if (detourSpec.length >= limit) break;
      }
      if (detourSpec.length >= limit) break;
    }
  }
  const hasExplicitWaypoints = !isRoundTrip && (req.waypoints?.length ?? 0) > 0;
  const shouldPreferMainRoads =
    !isRoundTrip &&
    (isDirectFastest || hasExplicitWaypoints || req.reroute_request === true);

  // 2026-05-28 (vucko Speed-Boost): Hard-Regions (Vorarlberg/Tirol/CH-Alpen)
  // bekommen weniger parallele Seeds — GraphHopper-Thread-Pool ist dort
  // auf den schwierigen Bergpässen schneller saturiert. Weniger parallele
  // Calls = max(call_time) sinkt um 20-30% weil kein einzelner Seed mehr auf
  // den überlasteten Pool wartet.
  const regionForHotspot = classifyRegion(
    startLocation.latitude,
    startLocation.longitude,
  );
  const isAlpineHotspot = regionForHotspot.label === 'alpine';
  // 2026-06-03 (vucko): moderater Seed-Bump. Mit strengerer Akzeptanz (kein
  // Motorway, keine U-Turns) braucht die Auswahl mehr saubere Kandidaten zum
  // Vergleichen. generateSeeds liefert 10 — wir nutzen jetzt mehr davon. Der
  // Racer bricht Verlierer ab, sobald ein sauberer da ist → Latenz bleibt < 10s.
  //
  // 2026-08-18 (Aufgabe 1.3): `max_candidate_attempts` aus dem Request wird
  // hier BEWUSST NICHT ausgewertet. Gemessen, was der Client schickt:
  // route_service.dart:3170 sendet fuer A→B den Vorgabewert 3, :3287 den Wert
  // 5, fuer Rundkurse :1697 die Werte 18 bzw. 30. Wuerden wir das als
  // Obergrenze nehmen, faellt A→B von 13 bis 14 Kandidaten auf 3 bis 5 zurueck
  // — das macht exakt den Befund vom 16.08. rueckgaengig (17 von 18
  // Umweg-Routen mit einer Wende, weil es an wendefreien Kandidaten fehlte).
  // Als Untergrenze taugt es ebenso wenig: 30 gleichzeitige Anfragen
  // saturieren den GraphHopper-Thread-Pool und treiben die laengste
  // Einzelanfrage nach oben. Die Zahl gehoert an die Stelle, die weiss, wie
  // viele saubere Kandidaten die Auswahl braucht — und das ist der Server.
  // Der Wert wandert nur zur Nachvollziehbarkeit ins Antwort-Meta.
  const clientCandidateBudget = Number.isFinite(Number(req.max_candidate_attempts))
    ? Number(req.max_candidate_attempts)
    : undefined;
  const maxAttempts = isRoundTrip
    ? (isAlpineHotspot
        ? (needsDiversity ? 8 : 7)
        : (needsDiversity ? 10 : 8))
    : (hasExplicitWaypoints ? 1 : Math.max(13, detourSpec.length || 13));
  const targetKm = req.target_distance_km ?? 50;
  const candidates: Array<{ result: RouteResult; deltaPct: number; seed: number; isDup: boolean }> = [];
  let bestCandidate: RouteResult | null = null;
  let lastError = 'unknown';

  const candidateSeeds = seeds.slice(0, maxAttempts);
  // 2026-05-24 (vucko): Server-Wahl mit ALLEN Routen-Punkten —
  // Multi-Stopp-Tours die bis Frankfurt/Berlin gehen müssen automatisch
  // den DE-Server nutzen, sonst out-of-bounds.
  const allRoutePoints: Array<{ lat: number; lng: number }> = [
    { lat: startLocation.latitude, lng: startLocation.longitude },
  ];
  if (req.target_location) {
    allRoutePoints.push({
      lat: req.target_location.latitude,
      lng: req.target_location.longitude,
    });
  }
  if (req.waypoints) {
    for (const wp of req.waypoints) {
      allRoutePoints.push({ lat: wp.latitude, lng: wp.longitude });
    }
  }
  const serverChoice = chooseGraphhopperUrlForRoute(allRoutePoints);
  // 2026-06-10 (vucko START-SNAP-FIX): merkt sich, welcher GH-Server den
  // aktuellen Kandidaten-Batch geliefert hat — die Start-Wache routet ihren
  // Zubringer dann gegen DENSELBEN Server (Primary kann down/out-of-bounds
  // sein, dann liefe der Zubringer in den 9s-Timeout).
  let lastServerUsed = serverChoice.primary;
  const tryServerWithProfile = async (
    serverUrl: string,
    profileToUse: string,
    latOffset: number = 0,
    lngOffset: number = 0,
  ) => {
    lastServerUsed = serverUrl;
    if (isRoundTrip) {
      // 2026-06-02 (vucko Routing-Speed/Stabilität): NICHT auf alle Seeds warten
      // (Promise.all = langsamster von N gewinnt → 9-11s). Stattdessen den ERSTEN
      // akzeptablen Kandidaten nehmen und die restlichen Calls abbrechen.
      // GraphHopper-Round-Trip-Latenz schwankt 2-9s → so liefert die Live-Suche
      // in ~2-4s statt am langsamsten Outlier zu hängen. Die Akzeptanz-Schwelle
      // spiegelt das spätere Best-of-N-Scoring (nah an Zieldistanz, kein
      // Duplikat, realistische Geschwindigkeit, Stil getroffen).
      const controllers = candidateSeeds.map(() => new AbortController());
      const calls = candidateSeeds.map((seed, i) =>
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
          signal: controllers[i].signal,
        }).then(result => ({ result, seed })),
      );
      const minTurns = minTurnsPerKmForProfile(profileToUse);
      const isAcceptable = (
        entry: { result: RouteResult | { error: string }; seed: number },
      ): boolean => {
        const r = entry.result;
        if ('error' in r) return false;
        // 2026-06-03 (vucko): „Autobahn aus" heißt KEINE Autobahn. Ein Kandidat
        // mit Motorway ist niemals akzeptabel wenn avoid_highways gesetzt ist.
        if ((req.avoid_highways ?? false) && r.meta.uses_motorway === true) return false;
        if (strictInland) {
          const country = countryRouteMetrics(
            r.geometry.coordinates as [number, number][],
            homeCountryCode,
          );
          if (
            country.foreignPointFraction > ONLY_HOME_MAX_FOREIGN_FRACTION ||
            country.foreignDistanceFraction > ONLY_HOME_MAX_FOREIGN_FRACTION ||
            country.maxForeignSegmentMeters > ONLY_HOME_MAX_FOREIGN_SEGMENT_METERS
          ) return false;
        }
        // 2026-06-03 (vucko): Racer schließt NUR auf einer 0-U-Turn-Route kurz
        // (die ideale). Gibt es keine, sammelt er alle und das nicht-lineare
        // Best-of-N-Scoring wählt den Fallback: 0 < 1 (Kosten 14) < 2 (250). So
        // bevorzugen wir 0-U-Turn, fallen auf 1 zurück und liefern NIE eine
        // ≥2-U-Turn-Route (die der Client hart wegwirft → „keine Route").
        if (((r.meta.u_turn_count as number | undefined) ?? 0) > 0) return false;
        if (previousFps.has(r.fingerprint)) return false; // Duplikat → nächster Seed
        const deltaPct = Math.abs(r.distanceKm - targetKm) / targetKm * 100;
        if (deltaPct > 12) return false; // zu weit von Zieldistanz
        const avgSpeedKmh = r.durationSeconds > 0
          ? r.distanceKm / (r.durationSeconds / 3600)
          : 50;
        const minSpeed = r.distanceKm >= 75 ? 35 : 30;
        if (avgSpeedKmh < minSpeed) return false; // unrealistisch langsam
        const turns = countSignificantTurns(
          r.geometry.coordinates as [number, number][],
        );
        const turnsPerKm = r.distanceKm > 0 ? turns / r.distanceKm : 0;
        if (turnsPerKm < minTurns * 0.85) return false; // Stil klar verfehlt
        return true;
      };
      const picked = await raceForFirstAcceptable(calls, isAcceptable);
      // Verlierer-Calls abbrechen → GraphHopper-Last sparen (Cron-Kontention).
      for (const c of controllers) {
        try { c.abort(); } catch { /* ignore */ }
      }
      return picked;
    }
    // A→B mode mit Wegpunkten
    if (hasExplicitWaypoints) {
      // 2026-05-22 (vucko Task #7): Snap-Fallback für weit entfernte Stopps.
      // Erstversuch: alle Waypoints exakt wie geklickt. Wenn fail (kein Match,
      // Snap zu Autobahn etc.), versuche bis zu 4 Varianten mit kleinem Offset
      // pro Waypoint (8 Richtungen × 0.0012° ≈ 130m). Reihenfolge der Versuche:
      //   0: Original
      //   1: alle WP +E (0.0012, 0)
      //   2: alle WP +N (0, 0.0012)
      //   3: gemischt — gerade WP +E, ungerade +N
      //   4: alle WP -W -S
      const baseWPs = req.waypoints!.map(w => ({ lat: w.latitude, lng: w.longitude }));
      // 2026-05-23 (vucko Task #13): Zwei-Stufen-Snap.
      // Stufe 1: kleine Offsets (~130m) — fängt 90% der Fälle wo der
      //   gewählte Punkt knapp neben einer Straße ist.
      // Stufe 2: GROSSE Offsets (~1.1km) in 8 Richtungen pro WP — fängt
      //   Fälle wo der User auf Wasser/Wald/Berg getippt hat. Wir suchen
      //   jeden WP einzeln neu, bis ein Snap klappt; behalten die 7 anderen.
      const smallOffsetVariants: Array<Array<{ lat: number; lng: number }>> = [
        baseWPs,
        baseWPs.map(wp => ({ lat: wp.lat + 0.0014, lng: wp.lng })),
        baseWPs.map(wp => ({ lat: wp.lat, lng: wp.lng + 0.0014 })),
        baseWPs.map((wp, i) => i % 2 === 0
          ? { lat: wp.lat + 0.0014, lng: wp.lng }
          : { lat: wp.lat, lng: wp.lng + 0.0014 }),
        baseWPs.map(wp => ({ lat: wp.lat - 0.0014, lng: wp.lng - 0.0014 })),
      ];
      // ~1.1km Offsets in 8 Richtungen (für See/Wald/Berg-Punkte).
      const bigDeltas: Array<[number, number]> = [
        [ 0.010,  0     ], [ 0.007,  0.007], [ 0,       0.010], [-0.007,  0.007],
        [-0.010,  0     ], [-0.007, -0.007], [ 0,      -0.010], [ 0.007, -0.007],
      ];
      // ~5-6km Offsets (Mega-Stufe) für Punkte mitten im Bodensee/Bergsee.
      // Letzte Eskalationsstufe — User-Intent wird nur grob respektiert,
      // aber besser als "Stopps prüfen"-Fehler.
      const megaDeltas: Array<[number, number]> = [
        [ 0.050,  0     ], [ 0.035,  0.035], [ 0,       0.050], [-0.035,  0.035],
        [-0.050,  0     ], [-0.035, -0.035], [ 0,      -0.050], [ 0.035, -0.035],
      ];
      const buildVariants = (deltas: Array<[number, number]>) =>
        deltas.map(([dLat, dLng]) =>
          baseWPs.map(wp => ({ lat: wp.lat + dLat, lng: wp.lng + dLng })),
        );
      // 2026-05-24 (vucko): Pro-WP individueller Snap.
      // Bug: Bei `baseWPs.map(wp => ...same offset...)` werden ALLE WPs
      // gleichzeitig verschoben. Wenn WP[0]=München gut snappt aber WP[1]=Salzburg
      // nicht → globaler offset kann beide kaputt machen.
      // Lösung: Pro WP einzeln 8 Richtungen + start/target auch einzeln versuchen.
      const buildPerWpVariants = (deltas: Array<[number, number]>): Array<Array<{ lat: number; lng: number }>> => {
        const variants: Array<Array<{ lat: number; lng: number }>> = [];
        for (let wpIdx = 0; wpIdx < baseWPs.length; wpIdx++) {
          for (const [dLat, dLng] of deltas) {
            const v = baseWPs.map((wp, i) =>
              i === wpIdx ? { lat: wp.lat + dLat, lng: wp.lng + dLng } : wp,
            );
            variants.push(v);
          }
        }
        return variants;
      };
      const offsetVariants = [
        ...smallOffsetVariants,
        ...buildPerWpVariants(bigDeltas),         // pro WP einzeln
        ...buildVariants(bigDeltas),               // alle WPs gleich (legacy)
        ...buildPerWpVariants(megaDeltas),        // pro WP einzeln mit Mega
        ...buildVariants(megaDeltas),              // alle WPs gleich (legacy)
      ];
      // 2026-05-24 (vucko): Auch start + target einzeln offsetten —
      // bei "Cannot find point 0/N" liegt es nicht an WPs.
      const startEndOffsets: Array<{ sLat: number; sLng: number; tLat: number; tLng: number }> = [
        { sLat: 0, sLng: 0, tLat: 0, tLng: 0 },           // Original
        { sLat: 0.0014, sLng: 0, tLat: 0, tLng: 0 },
        { sLat: 0, sLng: 0.0014, tLat: 0, tLng: 0 },
        { sLat: 0, sLng: 0, tLat: 0.0014, tLng: 0 },
        { sLat: 0, sLng: 0, tLat: 0, tLng: 0.0014 },
        { sLat: 0.010, sLng: 0, tLat: 0, tLng: 0 },
        { sLat: 0, sLng: 0, tLat: 0.010, tLng: 0 },
        { sLat: 0, sLng: 0, tLat: 0, tLng: 0.010 },
        { sLat: 0, sLng: 0, tLat: -0.010, tLng: 0 },
      ];
      // 2026-06-10 (vucko START-SNAP-FIX): Pässe statt gemischtem Cross-
      // Product. Pass 0 hält Start+Ziel IMMER exakt — bei WP-Fails liegt das
      // Problem fast nie am Start, und ein „zufällig" mitverschobener Start
      // ließ Routen 150m-1.1km neben dem Standort beginnen. Meldet GH dabei
      // „Cannot find point 0" (= der Start SELBST ist nicht snapbar), brechen
      // wir Pass 0 sofort ab — alle weiteren Pass-0-Versuche teilen den
      // exakten Start und scheitern identisch (sonst 21+16N tote Calls →
      // Client-Timeout, Review-Befund 2026-06-10). Pass 1a rettet dann mit
      // Start/Ziel-Offsets bei EXAKTEN WPs (Start-Offsets zuerst), Pass 1b
      // zuletzt mit WP-Offsets × Start/Ziel-Offsets (alles kaputt).
      const wpCallShared = {
        profile: profileToUse,
        isRoundTrip: false as const,
        avoidHighways: req.avoid_highways ?? false,
        serverUrl,
        preferMainRoads: shouldPreferMainRoads,
        // 2026-06-09 (vucko U-Turn-Fix): Reroute startet in Fahrtrichtung.
        headingDeg: req.reroute_request === true ? req.current_heading : undefined,
      };
      for (let attempt = 0; attempt < offsetVariants.length; attempt++) {
        const result = await callGraphHopper({
          ...wpCallShared,
          startLat: req.start_location!.latitude,
          startLng: req.start_location!.longitude,
          endLat: req.target_location!.latitude,
          endLng: req.target_location!.longitude,
          intermediateWaypoints: offsetVariants[attempt],
        });
        if (!('error' in result)) {
          return [{ result, seed: attempt }];
        }
        if (attempt === 0) {
          console.log(`Waypoint snap attempt 0 failed: ${result.error.slice(0, 120)} — retrying with offsets`);
        }
        if (result.error.includes('Cannot find point 0:')) {
          console.log('Waypoint pass 0: start itself un-snappable — escalating to start/end offsets immediately');
          break;
        }
      }
      // Pass 1a: exakte WPs, Start/Ziel-Offsets. Bei Navigation/Reroute ist der
      // Start die Fahrzeugposition und darf niemals verschoben werden; nur Ziel-
      // oder WP-Snap darf eskalieren. Sonst gewinnt eine versetzte Anschlussroute
      // und der Client verwirft sie als Start-Offset.
      const targetOnlyRescue = [
        startEndOffsets[3], startEndOffsets[4], startEndOffsets[6],
        startEndOffsets[7], startEndOffsets[8],
      ];
      const seRescue = req.reroute_request === true
        ? targetOnlyRescue
        : [
            startEndOffsets[1], startEndOffsets[2], startEndOffsets[5],
            ...targetOnlyRescue,
          ];
      for (let i = 0; i < seRescue.length; i++) {
        const seOffset = seRescue[i];
        const result = await callGraphHopper({
          ...wpCallShared,
          startLat: req.start_location!.latitude + seOffset.sLat,
          startLng: req.start_location!.longitude + seOffset.sLng,
          endLat: req.target_location!.latitude + seOffset.tLat,
          endLng: req.target_location!.longitude + seOffset.tLng,
          intermediateWaypoints: baseWPs,
        });
        if (!('error' in result)) {
          return [{ result, seed: offsetVariants.length + i }];
        }
      }
      // Pass 1b: WP-Offsets (groß/mega) × Start/Ziel-Offsets.
      for (let attempt = smallOffsetVariants.length; attempt < offsetVariants.length; attempt++) {
        const seOffset = seRescue[(attempt - smallOffsetVariants.length) % seRescue.length];
        const result = await callGraphHopper({
          ...wpCallShared,
          startLat: req.start_location!.latitude + seOffset.sLat,
          startLng: req.start_location!.longitude + seOffset.sLng,
          endLat: req.target_location!.latitude + seOffset.tLat,
          endLng: req.target_location!.longitude + seOffset.tLng,
          intermediateWaypoints: offsetVariants[attempt],
        });
        if (!('error' in result)) {
          return [{ result, seed: 2 * offsetVariants.length + attempt }];
        }
      }
      // 2026-05-24 (vucko): SEGMENT-STITCH-FALLBACK.
      // Empirie: GraphHopper Multi-Point-Routing (>=3 points) ist STRENGER
      // beim Point-Snap als 2-Point-Routing. Konkret: München-Marienplatz
      // (48.13, 11.58) snappt bei A→B aber NICHT als WP in 3-Point-Setup.
      // Mit motorcycle_scenic gilt das umso mehr (Auswahl-Filter "weniger
      // Straßen erreichbar").
      // Workaround: Wenn Multi-Point fail → route N+1 separate A→B Segmente,
      //   stitch geometries zusammen. Jedes Segment nutzt directVariants
      //   (13 Start/End-Snap-Versuche). Klappt zuverlässig.
      console.log(`All ${offsetVariants.length} WP-snap attempts failed — falling back to segment-stitch`);
      const segments: Array<{ start: { lat: number; lng: number }; end: { lat: number; lng: number } }> = [];
      const allPoints = [
        { lat: req.start_location!.latitude, lng: req.start_location!.longitude },
        ...baseWPs,
        { lat: req.target_location!.latitude, lng: req.target_location!.longitude },
      ];
      for (let i = 0; i < allPoints.length - 1; i++) {
        segments.push({ start: allPoints[i], end: allPoints[i + 1] });
      }
      // Pro Segment: directVariants-ähnlicher Best-of-N Snap.
      const segDirectVariants: Array<{ sLatOff: number; sLngOff: number; eLatOff: number; eLngOff: number }> = [
        { sLatOff: 0, sLngOff: 0, eLatOff: 0, eLngOff: 0 },
        { sLatOff: 0.0014, sLngOff: 0, eLatOff: 0, eLngOff: 0 },
        { sLatOff: 0, sLngOff: 0.0014, eLatOff: 0, eLngOff: 0 },
        { sLatOff: 0, sLngOff: 0, eLatOff: 0.0014, eLngOff: 0 },
        { sLatOff: 0, sLngOff: 0, eLatOff: 0, eLngOff: 0.0014 },
        { sLatOff: 0.010, sLngOff: 0, eLatOff: 0, eLngOff: 0 },
        { sLatOff: 0, sLngOff: 0, eLatOff: 0.010, eLngOff: 0 },
        { sLatOff: 0, sLngOff: 0.010, eLatOff: 0, eLngOff: 0 },
        { sLatOff: 0, sLngOff: 0, eLatOff: 0, eLngOff: 0.010 },
      ];
      const segResults: Array<RouteResult> = [];
      for (let segIdx = 0; segIdx < segments.length; segIdx++) {
        const seg = segments[segIdx];
        const segmentVariants = req.reroute_request === true && segIdx === 0
          ? segDirectVariants.filter(v => v.sLatOff === 0 && v.sLngOff === 0)
          : segDirectVariants;
        const tries = await Promise.all(
          segmentVariants.map(v =>
            callGraphHopper({
              startLat: seg.start.lat + v.sLatOff,
              startLng: seg.start.lng + v.sLngOff,
              endLat: seg.end.lat + v.eLatOff,
              endLng: seg.end.lng + v.eLngOff,
              profile: profileToUse,
              isRoundTrip: false,
              avoidHighways: req.avoid_highways ?? false,
              serverUrl,
              preferMainRoads: shouldPreferMainRoads,
              // Heading nur fürs ERSTE Segment (= Fahrzeugposition); an den
              // Zwischenstopps ist die Ankunftsrichtung unbekannt.
              headingDeg: segIdx === 0 && req.reroute_request === true
                ? req.current_heading
                : undefined,
            }),
          ),
        );
        const ok = tries.find(r => !('error' in r));
        if (!ok) {
          // Segment unrettbar → komplettes Multi-Stop fail
          const lastErr = tries[tries.length - 1];
          const errMsg = 'error' in lastErr ? lastErr.error : 'unknown';
          console.log(`Segment ${segIdx} (${seg.start.lat},${seg.start.lng} → ${seg.end.lat},${seg.end.lng}) all snap variants failed: ${errMsg}`);
          return [{ result: lastErr, seed: 0 }];
        }
        segResults.push(ok as RouteResult);
      }
      // Stitche alle Segmente zusammen.
      const stitchedCoords: [number, number][] = [];
      let totalDistKm = 0;
      let totalDurSec = 0;
      let totalAscent = 0;
      for (let i = 0; i < segResults.length; i++) {
        const sr = segResults[i];
        const coords = sr.geometry.coordinates;
        // Bei nicht-erstem Segment den ersten Punkt überspringen (= Endpunkt von vorherigem).
        const startFrom = i === 0 ? 0 : 1;
        for (let j = startFrom; j < coords.length; j++) {
          stitchedCoords.push(coords[j] as [number, number]);
        }
        totalDistKm += sr.distanceKm;
        totalDurSec += sr.durationSeconds;
        totalAscent += sr.ascent;
      }
      const stitched: RouteResult = {
        geometry: { type: 'LineString', coordinates: stitchedCoords },
        distanceKm: totalDistKm,
        durationSeconds: totalDurSec,
        ascent: totalAscent,
        coordinateCount: stitchedCoords.length,
        fingerprint: buildFingerprint(stitchedCoords, totalDistKm),
        meta: {
          route_source: 'graphhopper-stitched',
          engine: 'graphhopper-8',
          profile: profileToUse,
          bbox: segResults[0].meta.bbox,
          // 2026-08-18 (Aufgabe 1.4): Auch die zusammengenaehte Stopp-Kette
          // bekommt die Kennzahl. Gerade hier entsteht Hin-und-zurueck, weil
          // die Segmente einzeln geroutet werden und keines vom anderen weiss.
          self_overlap_fraction: selbstUeberlappungAnteil(stitchedCoords),
        },
      };
      console.log(`Stitched ${segments.length} segments: ${totalDistKm.toFixed(1)}km`);
      return [{ result: stitched, seed: 0 }];
    }
    if (detourSpec.length === 0) {
      // Direkter A→B (detourLevel 0) — 2026-05-23 (vucko Task #13):
      // Snap-Offset-Varianten gegen „Punkt im Wasser/Hafen"-Fails.
      //
      // 2026-06-09 (vucko A→B-Endpunkt-Fix): GESTUFT statt alle 13 parallel.
      // Vorher konnten Varianten mit ZIEL-Offset bis ±1.1km gewinnen, obwohl
      // das exakte Ziel erreichbar war → die Route endete sichtbar NEBEN/HINTER
      // dem Zielmarker (Bregenz→Götzis-Bug).
      //
      // 2026-06-10 (vucko START-SNAP-FIX): Phase A enthielt neben dem exakten
      // Start auch ±150m/±1.1km-START-Offset-Varianten PARALLEL. Das Best-of-N-
      // Scoring wählt nach Routen-Score (deltaPct gegen targetKm, das bei A→B
      // auf 50km defaultet!) — die Route mit verschobenem Start ist oft länger
      // und gewann dadurch DETERMINISTISCH gegen den exakten Start (Dornbirn
      // live: erster Punkt 756m neben dem Standort → Client lehnt ab → „A→B
      // und jeder Reroute kaputt"). Jetzt: Start IMMER exakt in Phase A-C.
      // Start-Offsets erst als allerletzte Eskalation (Phase D klein, Phase E
      // groß) — sie laufen also NUR, wenn der exakte Start nachweislich nicht
      // snapbar ist (alle Phasen mit exaktem Start gescheitert).
      const heading = req.reroute_request === true ? req.current_heading : undefined;
      const phases: Array<Array<{
        sLatOff: number; sLngOff: number; eLatOff: number; eLngOff: number;
      }>> = [
        [ // Phase A: Start EXAKT + Ziel EXAKT — einzige „normale" Variante
          { sLatOff: 0, sLngOff: 0, eLatOff: 0, eLngOff: 0 },
        ],
        [ // Phase B: Start exakt, kleine Ziel-Offsets (~150m)
          { sLatOff: 0, sLngOff: 0, eLatOff: 0.0014, eLngOff: 0 },
          { sLatOff: 0, sLngOff: 0, eLatOff: 0, eLngOff: 0.0014 },
          { sLatOff: 0, sLngOff: 0, eLatOff: -0.0014, eLngOff: 0 },
          { sLatOff: 0, sLngOff: 0, eLatOff: 0, eLngOff: -0.0014 },
        ],
        [ // Phase C: Start exakt, große Ziel-Offsets (~1.1km) — Insel/Hafen-Rettung
          { sLatOff: 0, sLngOff: 0, eLatOff: 0.010, eLngOff: 0 },
          { sLatOff: 0, sLngOff: 0, eLatOff: -0.010, eLngOff: 0 },
          { sLatOff: 0, sLngOff: 0, eLatOff: 0, eLngOff: 0.010 },
          { sLatOff: 0, sLngOff: 0, eLatOff: 0, eLngOff: -0.010 },
        ],
        [ // Phase D: kleine Start-Offsets (~150m), Ziel exakt — Start-Rettung
          { sLatOff: 0.0014, sLngOff: 0, eLatOff: 0, eLngOff: 0 },
          { sLatOff: 0, sLngOff: 0.0014, eLatOff: 0, eLngOff: 0 },
          { sLatOff: -0.0014, sLngOff: 0, eLatOff: 0, eLngOff: 0 },
          { sLatOff: 0, sLngOff: -0.0014, eLatOff: 0, eLngOff: 0 },
        ],
        [ // Phase E: große Start-Offsets (~1.1km), Ziel exakt — letzte Eskalation
          { sLatOff: 0.010, sLngOff: 0, eLatOff: 0, eLngOff: 0 },
          { sLatOff: -0.010, sLngOff: 0, eLatOff: 0, eLngOff: 0 },
          { sLatOff: 0, sLngOff: 0.010, eLatOff: 0, eLngOff: 0 },
          { sLatOff: 0, sLngOff: -0.010, eLatOff: 0, eLngOff: 0 },
        ],
      ];
      const phaseNames = ['exact', 'end-offset-150m', 'end-offset-1km', 'start-offset-150m', 'start-offset-1km'];
      const runnablePhases = req.reroute_request === true ? phases.slice(0, 3) : phases;
      let lastResults: Array<{ result: RouteResult | { error: string }; seed: number }> = [];
      for (let p = 0; p < runnablePhases.length; p++) {
        const results = await Promise.all(
          runnablePhases[p].map((v, idx) =>
            callGraphHopper({
              startLat: req.start_location!.latitude + v.sLatOff,
              startLng: req.start_location!.longitude + v.sLngOff,
              endLat: req.target_location!.latitude + v.eLatOff,
              endLng: req.target_location!.longitude + v.eLngOff,
              profile: profileToUse,
              isRoundTrip: false,
              avoidHighways: req.avoid_highways ?? false,
              serverUrl,
              preferMainRoads: shouldPreferMainRoads,
              headingDeg: heading,
            }).then(result => ({ result, seed: p * 16 + idx })),
          ),
        );
        if (results.some(r => !('error' in r.result))) {
          if (p > 0) {
            console.log(`Direct A→B: exact phase failed, ${phaseNames[p] ?? `phase-${p}`} succeeded`);
          }
          return results;
        }
        lastResults = results;
      }
      return lastResults;
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
          preferMainRoads: req.reroute_request === true,
          detourBearingDeg: spec.bearing,
          detourPerpendicularKm: spec.distKm,
          detourAlong: spec.along,
          // 2026-06-09 (vucko U-Turn-Fix): Reroute startet in Fahrtrichtung.
          headingDeg: req.reroute_request === true ? req.current_heading : undefined,
        }).then((result) => {
          if (!('error' in result)) {
            result.meta.detour_level = detourLevel;
            result.meta.requested_detour_level = detourLevel;
            result.meta.delivered_detour_level = detourLevel;
            result.meta.detour_offset_side = spec.side;
            result.meta.detour_bearing_deg = spec.bearing;
            result.meta.detour_perpendicular_km = Number(spec.distKm.toFixed(2));
            result.meta.detour_along = spec.along;
            result.meta.detour_family = spec.family;
          }
          return { result, seed: idx };
        }),
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

  // 2026-05-24 (vucko ULTIMATE-FALLBACK):
  // Wenn ALLE motorcycle-Profile Varianten fail → versuche `car` Profil
  // OHNE avoid_highways. Das ist der "Google Maps Fallback": IMMER eine
  // befahrbare Route, auch wenn nicht scenic. Besser als gar nichts.
  // Nutzt Plain-Dijkstra ohne Custom-Model.
  const ultimateAllFailed = parallel.every(p => 'error' in p.result);
  if (ultimateAllFailed && !isRoundTrip && req.target_location != null) {
    const ultimateServers = serverChoice.primary === serverChoice.fallback
      ? [serverChoice.primary]
      : [serverChoice.primary, serverChoice.fallback];
    // 2026-05-28 (vucko Task #82): VOR dem Auto-Fallback noch ein
    // motorcycle_scenic-Versuch MIT avoid_highways. Kurze Trips (z.B.
    // Hohenems→Feldkirch) bekommen so die parallele B-Straße (L190) statt
    // der A14, bevor wir auf das generische Auto-Profil zurückfallen.
    console.log(`[ULTIMATE FALLBACK] All attempts failed, trying motorcycle_scenic avoid-highway first`);
    for (const scenicServer of ultimateServers) {
      try {
        const scenicResult = await callGraphHopper({
          startLat: req.start_location!.latitude,
          startLng: req.start_location!.longitude,
          endLat: req.target_location.latitude,
          endLng: req.target_location.longitude,
          profile: 'motorcycle_scenic',
          isRoundTrip: false,
          avoidHighways: true,
          serverUrl: scenicServer,
          intermediateWaypoints: req.waypoints?.map(w => ({
            lat: w.latitude, lng: w.longitude,
          })),
          preferMainRoads: shouldPreferMainRoads,
        });
        if (!('error' in scenicResult)) {
          console.log(`[ULTIMATE FALLBACK] motorcycle_scenic avoid-highway succeeded on ${scenicServer}`);
          parallel = [{ result: scenicResult, seed: 0 }];
          usedProfileFallback = true;
          lastServerUsed = scenicServer;
          break;
        }
      } catch (e) {
        console.log(`[ULTIMATE FALLBACK] motorcycle_scenic attempt threw: ${e}`);
      }
    }
  }

  const ultimateStillFailed = parallel.every(p => 'error' in p.result);
  if (ultimateStillFailed && !isRoundTrip && req.target_location != null) {
    console.log(`[ULTIMATE FALLBACK] All motorcycle attempts failed, trying car profile direct`);
    // Direkter A→B mit "car" profil, kein Custom-Model.
    const carServers = serverChoice.primary === serverChoice.fallback
      ? [serverChoice.primary]
      : [serverChoice.primary, serverChoice.fallback];
    for (const carServer of carServers) {
      try {
        const carResult = await callGraphHopper({
          startLat: req.start_location!.latitude,
          startLng: req.start_location!.longitude,
          endLat: req.target_location.latitude,
          endLng: req.target_location.longitude,
          profile: 'car',
          isRoundTrip: false,
          // 2026-05-28 (vucko Task #82): respektiere die User-Einstellung
          // statt hart Autobahn zu erlauben.
          avoidHighways: req.avoid_highways ?? false,
          serverUrl: carServer,
          intermediateWaypoints: req.waypoints?.map(w => ({
            lat: w.latitude, lng: w.longitude,
          })),
          preferMainRoads: true,
        });
        if (!('error' in carResult)) {
          console.log(`[ULTIMATE FALLBACK] car profile succeeded on ${carServer}`);
          // 2026-05-28 (vucko Task #82): markiere die Notfall-Auto-Route.
          carResult.meta.ultimate_car_fallback = true;
          parallel = [{ result: carResult, seed: 0 }];
          usedProfileFallback = true;
          lastServerUsed = carServer;
          break;
        }
      } catch (e) {
        console.log(`[ULTIMATE FALLBACK] car attempt threw: ${e}`);
      }
    }
  }

  // 2026-06-03 (vucko): Adaptive Distanz-Korrektur für Round-Trip. GHs
  // round_trip.distance ist in alpinem/eingeengtem Terrain unzuverlässig
  // (Feldkirch live: 50km→40km, 100km→157km bei GLEICHEM comp-Faktor 0.9). Ein
  // einzelner Region-Faktor kann das nicht fixen. Lösung: einmalige Feedback-
  // Korrektur — liegt die beste Route >15% daneben, neu anfragen mit
  // round_trip.distance × (Ziel/Ist). Homt zuverlässig aufs Ziel ohne Region-
  // Tuning; kostet nur bei Bedarf einen Extra-Batch (Latenz bleibt < 10s).
  if (isRoundTrip && req.target_distance_km && effectiveDistanceKm) {
    const okResults = parallel
      .map((p) => p.result)
      .filter((r): r is RouteResult => !('error' in r));
    if (okResults.length > 0) {
      const best = okResults.reduce((a, b) =>
        Math.abs(a.distanceKm - targetKm) < Math.abs(b.distanceKm - targetKm) ? a : b
      );
      const deltaRatio = Math.abs(best.distanceKm - targetKm) / targetKm;
      if (deltaRatio > 0.15 && best.distanceKm > 1) {
        const corrected = Math.max(
          targetKm * 0.5,
          Math.min(targetKm * 2.5, effectiveDistanceKm * (targetKm / best.distanceKm)),
        );
        console.log(
          `[DIST-CORRECT] best=${best.distanceKm.toFixed(1)}km vs target=${targetKm}km → re-request ${corrected.toFixed(1)}km`,
        );
        effectiveDistanceKm = corrected;
        const corrective = await tryServerWithProfile(
          serverChoice.primary,
          usedProfileFallback ? 'motorcycle_entdecker' : profile,
        );
        parallel = parallel.concat(corrective);
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

  // 2026-06-10 (vucko GOOGLE-MAPS-VERLAESSLICHKEIT): Der GH-round_trip-
  // Algorithmus kann serverseitig degradieren (heute live gemessen: ALLE
  // Profile/Styles/Standorte lieferten ueber den Notfall-Pfad Mini-Routen
  // mit 57-80% Zielabweichung und Luftlinien-Gaps bis 402m — beim User als
  // Dreieck quer ueber die Karte sichtbar). A->B-Routing lief dabei
  // einwandfrei. Deshalb: Gibt es fuer einen Rundkurs KEINEN Kandidaten mit
  // <=35% Zielabweichung, bauen wir den Rundkurs SELBST aus drei
  // A->B-Segmenten (Dreieck; GH snappt die Eckpunkte auf Strassen). Erst
  // wenn auch das scheitert, ist "keine Route" die ehrliche Antwort —
  // NIE wieder eine 5km-Mini-"Route" fuer ein 25km-Ziel ausliefern.
  const synthDiagTop: string[] = [];
  if (isRoundTrip) {
    const bestDelta = candidates.length
      ? Math.min(...candidates.map((c) => c.deltaPct))
      : Infinity;
    if (bestDelta > 35) {
      console.log(`[SYNTH-TRIANGLE] best roundtrip delta ${bestDelta === Infinity ? 'none' : bestDelta.toFixed(0) + '%'} — building stitched triangle roundtrip`);
      const sLat = startLocation.latitude;
      const sLng = startLocation.longitude;
      const offsetPoint = (lat: number, lng: number, distKm: number, bearingDeg: number) => {
        const rad = (bearingDeg * Math.PI) / 180;
        return {
          lat: lat + (distKm * Math.cos(rad)) / 111.32,
          lng: lng + (distKm * Math.sin(rad)) / (111.32 * Math.cos((lat * Math.PI) / 180)),
        };
      };
      // Eckpunkte koennen im Gebirge/Wald landen — gestaffelte Offsets bis
      // ~1.3km, damit GH einen Strassen-Snap findet.
      const synthSnapVariants = [
        { latOff: 0, lngOff: 0 },
        { latOff: 0.0014, lngOff: 0 },
        { latOff: -0.0014, lngOff: 0.0014 },
        { latOff: 0.006, lngOff: 0 },
        { latOff: -0.006, lngOff: -0.006 },
        { latOff: 0, lngOff: 0.012 },
        { latOff: -0.012, lngOff: 0 },
        { latOff: 0.012, lngOff: 0.012 },
      ];
      const synthDiag = synthDiagTop;
      const firstRtErr = parallel.find((pp) => 'error' in pp.result);
      synthDiag.push(`rt_err=${firstRtErr ? String((firstRtErr.result as { error: string }).error).slice(0, 160) : 'none(' + parallel.length + ' ok results, all mini)'}`);
      // Strategie: Wendepunkt W aus einer ECHTEN A->B-Geometrie nehmen (liegt
      // garantiert auf einer Strasse — kein "Cannot find point" mehr), dann
      // Hinweg start->W direkt + Rueckweg W->start mit seitlichem Detour
      // (anderer Weg zurueck). Distanz steuert sich ueber die Lage von W.
      let reachKm = targetKm * 0.62; // Fernziel-Distanz fuer die Probe-Route
      outer:
      for (const bearing of [45, 160, 280, 100]) {
        let probeOk: RouteResult | null = null;
        let pr = reachKm;
        for (let shrink = 0; shrink < 3 && !probeOk; shrink++) {
          const far = offsetPoint(sLat, sLng, pr, bearing);
          const probe = await callGraphHopper({
            startLat: sLat,
            startLng: sLng,
            endLat: far.lat,
            endLng: far.lng,
            profile: 'motorcycle_entdecker',
            isRoundTrip: false,
            avoidHighways: req.avoid_highways ?? false,
            serverUrl: lastServerUsed,
            preferMainRoads: shouldPreferMainRoads,
          });
          if (!('error' in probe)) {
            probeOk = probe as RouteResult;
          } else {
            synthDiag.push(`b${bearing} probe@${pr.toFixed(0)}km: ${('error' in probe ? probe.error : '?').toString().slice(0, 60)}`);
            pr *= 0.6; // Snap-Fehler -> naeher ran (Richtung Tal/Stadt)
          }
        }
        if (!probeOk) continue outer;
        // Wendepunkt = Geometrie-Punkt bei ~targetKm*0.45 entlang der Probe.
        const pc = probeOk.geometry.coordinates as [number, number][];
        const wantKm = Math.min(targetKm * 0.45, probeOk.distanceKm * 0.9);
        let acc = 0;
        let wIdx = pc.length - 1;
        for (let i = 1; i < pc.length; i++) {
          const dx = (pc[i][0] - pc[i - 1][0]) * 111.32 * Math.cos((pc[i][1] * Math.PI) / 180);
          const dy = (pc[i][1] - pc[i - 1][1]) * 110.54;
          acc += Math.sqrt(dx * dx + dy * dy);
          if (acc >= wantKm) { wIdx = i; break; }
        }
        const W = { lat: pc[wIdx][1], lng: pc[wIdx][0] };
        // Hinweg: start->W = Probe-Geometrie bis wIdx (echte Strassen).
        const outCoords = pc.slice(0, wIdx + 1) as [number, number][];
        const outKm = Math.min(acc, wantKm + 1);
        // Rueckweg: W->start mit seitlichem Detour (anderer Weg zurueck).
        for (const detSide of [0]) {
          const back = await callGraphHopper({
            startLat: W.lat,
            startLng: W.lng,
            endLat: sLat,
            endLng: sLng,
            profile: 'motorcycle_entdecker',
            isRoundTrip: false,
            avoidHighways: req.avoid_highways ?? false,
            serverUrl: serverChoice.primary,
          });
          if ('error' in back) {
            synthDiag.push(`b${bearing} back det${detSide}: ${(back.error ?? '?').toString().slice(0, 60)}`);
            continue;
          }
          const br = back as RouteResult;
          const coords: [number, number][] = [...outCoords];
          const bc = br.geometry.coordinates as [number, number][];
          for (let j = 1; j < bc.length; j++) coords.push(bc[j] as [number, number]);
          const dist = outKm + br.distanceKm;
          const delta = Math.abs(dist - targetKm) / targetKm * 100;
          if (delta > 35) {
            synthDiag.push(`b${bearing} det${detSide}: dist=${dist.toFixed(1)} delta=${delta.toFixed(0)}`);
            continue;
          }
          let maxGapM = 0;
          for (let i = 1; i < coords.length; i++) {
            const dx = (coords[i][0] - coords[i - 1][0]) * 111320 * Math.cos((coords[i][1] * Math.PI) / 180);
            const dy = (coords[i][1] - coords[i - 1][1]) * 110540;
            const g = Math.sqrt(dx * dx + dy * dy);
            if (g > maxGapM) maxGapM = g;
          }
          // Gerade Tunnel haben keine Zwischenpunkte (Achrain ~850m) — erst
          // ab >1200m ist es eine kaputte Naht/Luftlinie.
          if (maxGapM > 1200) {
            synthDiag.push(`b${bearing} det${detSide}: gap=${maxGapM.toFixed(0)}m`);
            continue;
          }
          const synth: RouteResult = {
            geometry: { type: 'LineString', coordinates: coords },
            distanceKm: dist,
            durationSeconds: Math.round((outKm / Math.max(br.distanceKm, 0.1)) * br.durationSeconds) + br.durationSeconds,
            ascent: br.ascent,
            coordinateCount: coords.length,
            fingerprint: buildFingerprint(coords, dist),
            meta: {
              route_source: 'graphhopper-stitched-outback',
              engine: 'graphhopper-8',
              profile: 'motorcycle_entdecker',
              bbox: br.meta.bbox,
              // 2026-08-18 (Aufgabe 1.4): Diese Notfallroute ist per Bauart
              // hin-und-zurueck. Sie umgeht das Scoring (sie wird als einziger
              // Kandidat gesetzt), die Kennzahl steht hier also nur zum
              // Mitmessen im Monitoring — nicht zur Auswahl.
              self_overlap_fraction: selbstUeberlappungAnteil(coords),
            },
          };
          console.log(`[SYNTH-OUTBACK] success: ${dist.toFixed(1)}km (delta ${delta.toFixed(0)}%, ${coords.length} pts)`);
          candidates.length = 0;
          candidates.push({ result: synth, deltaPct: delta, seed: 0, isDup: previousFps.has(synth.fingerprint) });
          usedProfileFallback = true;
          lastServerUsed = serverChoice.primary; // Outback-Segmente liefen gegen primary
          break outer;
        }
      }
      // Immer noch nichts Brauchbares (>50% daneben)? Ehrlicher Fehler statt
      // Muell — der Client zeigt eine saubere Meldung + Auto-Retry.
      const finalBest = candidates.length
        ? Math.min(...candidates.map((c) => c.deltaPct))
        : Infinity;
      if (finalBest > 50) {
        console.log('[SYNTH-TRIANGLE] no acceptable roundtrip — returning error instead of garbage');
        candidates.length = 0;
        lastError = `roundtrip_quality_unavailable [${synthDiag.slice(0, 6).join(' | ')}]`;
      }
    }
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
    // 2026-06-03 (vucko): Autobahn- + U-Turn-Penalty im Best-of-N. Diese
    // Fallback-Auswahl greift nur, wenn KEIN Kandidat „acceptable" war — dann
    // trotzdem den mit am wenigsten Autobahn/U-Turns nehmen. highwayPenalty 1000
    // = effektiv Hard-Reject (Motorway nur wenn buchstäblich nichts anderes).
    const usesMotorway = c.result.meta.uses_motorway === true;
    const uTurns = (c.result.meta.u_turn_count as number | undefined) ?? 0;
    const highwayPenalty = ((req.avoid_highways ?? false) && usesMotorway) ? 1000 : 0;
    const minorRoadFraction = Number(c.result.meta.minor_road_distance_fraction ?? 0);
    const residentialFraction = Number(c.result.meta.residential_distance_fraction ?? 0);
    const serviceFraction = Number(c.result.meta.service_distance_fraction ?? 0);
    const mainRoadPenalty = shouldPreferMainRoads
      ? Math.min(
          140,
          minorRoadFraction * 70 +
          residentialFraction * 130 +
          serviceFraction * 160,
        )
      : 0;
    // 2026-06-03 (vucko KRITISCH): NICHT-linearer U-Turn-Penalty, an die
    // CLIENT-Akzeptanz angepasst. Der Flutter-Validator (route_quality_validator
    // hardUturnFailure) wirft Rundkurse mit ≥2 U-Turns HART weg → die Edge darf
    // solche Routen nie als beste liefern, sonst „keine Route" (genau der vom
    // User gemeldete Fehlschlag bei Inland/Sport 100km). Darum:
    //   0 U-Turns → 0   (ideal)
    //   1 U-Turn  → 14  (mild; Client akzeptiert, Distanz-Korrektur darf gewinnen)
    //   ≥2 U-Turns → 250+  (quasi Hard-Reject — nur wenn buchstäblich nichts
    //                       anderes existiert, dann lieber als NO_ROUTE)
    // 2026-08-16 (vucko Testfahrt T3): Bei A→B-UMWEGEN ist EINE Wende genau
    // der haessliche Stachel (hin und auf demselben Weg zurueck), den der
    // Nutzer sieht. Dort wiegt sie 60 (statt 14): Ein wendefreier Kandidat
    // darf bis ~60 % neben der Zieldistanz liegen und gewinnt trotzdem gegen
    // den exakt passenden Stachel. Rundkurse und Direkt-A→B unveraendert.
    const einzelWendeStrafe = detourLevel > 0 ? 60 : 14;
    const uTurnPenalty = uTurns === 0
        ? 0
        : uTurns === 1
        ? einzelWendeStrafe
        : 250 + (uTurns - 2) * 120;
    // 2026-08-18 (Aufgabe 1.4, vucko am 16.08.): „Die Strecken muessen sauber
    // sein und nicht in eine Richtung und dann die gleiche Strasse wieder
    // zurueckfinden."
    //
    // Die Ueberlappung wirkt in der AUSWAHL, nicht erst in der Ablehnung —
    // gemessen war der Zustand: der Server kannte die Kennzahl gar nicht, ein
    // hin-und-zurueck-Kandidat konnte gewinnen und wurde erst im Client
    // weggeworfen („keine Route").
    //
    // Gewicht in der Groessenordnung der Wende-Strafe (60): Ein Kandidat, der
    // die HALBE Strecke doppelt faehrt, kostet 0,5 * 60 = 30 Grundstrafe. Bei
    // A→B-Umwegen kommt ab 0,15 ein steiler Teil dazu (300 je voller Einheit),
    // weil dort genau dieser Stachel die Beschwerde war:
    //   Anteil 0,10 →  6     (Rauschen, z.B. eine Ortsdurchfahrt zweimal)
    //   Anteil 0,15 →  9     (Schwelle, ab hier steil)
    //   Anteil 0,30 → 18 + 45 = 63   (rund eine Wende)
    //   Anteil 0,50 → 30 + 105 = 135 (schlaegt jede Distanz-Feinabstimmung)
    // Rundkurse bekommen nur den Grundterm: dort ist ein Stueck doppelt oft
    // topologisch unvermeidbar (Taleingang, einzige Brücke).
    const selbstUeberlappung = Number(c.result.meta.self_overlap_fraction ?? 0);
    const ueberlappStrafe =
      selbstUeberlappung * 60 +
      (detourLevel > 0 ? Math.max(0, selbstUeberlappung - 0.15) * 300 : 0);
    const country = countryRouteMetrics(
      c.result.geometry.coordinates as [number, number][],
      homeCountryCode,
    );
    const foreignFraction = Math.max(country.foreignPointFraction, country.foreignDistanceFraction);
    const countryRejected =
      strictInland &&
      (country.foreignPointFraction > ONLY_HOME_MAX_FOREIGN_FRACTION ||
        country.foreignDistanceFraction > ONLY_HOME_MAX_FOREIGN_FRACTION ||
        country.maxForeignSegmentMeters > ONLY_HOME_MAX_FOREIGN_SEGMENT_METERS);
    const countryScorePenalty = countryPenalty(foreignFraction, countryPreference);
    return {
      ...c, turns, turnsPerKm, stylePenalty, speedPenalty, avgSpeedKmh,
      isUnreasonablySlow, foreignFraction, countryRejected, countryScorePenalty,
      mainRoadPenalty, selbstUeberlappung, ueberlappStrafe,
      foreignPointFraction: country.foreignPointFraction,
      foreignDistanceFraction: country.foreignDistanceFraction,
      maxForeignSegmentMeters: country.maxForeignSegmentMeters,
      // 2026-08-16 (T3): Bei A→B-Umwegen wiegt ein UEBERSCHUSS ueber die
      // Zieldistanz 1,6-fach — sonst kippt „mittel" gern auf die Laenge von
      // „gross" (wendefreie Kandidaten sind bei kleineren Offsets haeufiger,
      // die Stufen sollen unterscheidbar bleiben).
      score:
        (detourLevel > 0 && c.result.distanceKm > targetKm
          // ab +40 % Ueberschuss zusaetzlich steil — sonst faellt „mittel"
          // in die Laenge von „gross" (Live-Befund Dornbirn→Bezau: 69 km
          // fuer Ziel 45).
          ? c.deltaPct * 1.6 + Math.max(0, c.deltaPct - 40) * 3
          : c.deltaPct) +
        stylePenalty + speedPenalty + highwayPenalty +
        uTurnPenalty + ueberlappStrafe + countryScorePenalty + mainRoadPenalty +
        (countryRejected ? 10000 : 0),
    };
  });

  const allCountryRejected =
    strictInland && scored.length > 0 && scored.every(c => c.countryRejected);
  if (allCountryRejected) {
    return jsonResponse({
      error: 'no_inland_route',
      user_message:
        'Hier ist kein Rundkurs möglich, der im Land bleibt. Schalt „Im Land bleiben" aus oder wähl eine kürzere Distanz bzw. einen Start weiter im Landesinneren.',
      debug_message:
        `all_candidates_crossed_border home=${homeCountryCode} max=${ONLY_HOME_MAX_FOREIGN_FRACTION}`,
      meta: {
        response_code: 'no_inland_route',
        country_preference: countryPreference,
        home_country_code: homeCountryCode,
        avoid_cross_border: true,
        candidate_count: scored.length,
        country_rejected_count: scored.filter(c => c.countryRejected).length,
        min_foreign_fraction: Number(Math.min(...scored.map(c => c.foreignFraction)).toFixed(3)),
        min_foreign_distance_fraction: Number(Math.min(...scored.map(c => c.foreignDistanceFraction)).toFixed(3)),
        min_max_foreign_segment_meters: Math.round(Math.min(...scored.map(c => c.maxForeignSegmentMeters))),
      },
    }, 422);
  }

  // Best non-duplicate mit niedrigstem combined Score.
  // Zuerst nur "reasonable speed" Routes betrachten (nicht isUnreasonablySlow).
  // Nur wenn ALLE slow sind, fallback auf besten slow.
  const selectable = scored.filter(c => !c.countryRejected);
  const nonDupReasonable = selectable.filter(c => !c.isDup && !c.isUnreasonablySlow)
    .sort((a, b) => a.score - b.score);
  if (nonDupReasonable.length > 0) {
    bestCandidate = nonDupReasonable[0].result;
  } else {
    const nonDupAny = selectable.filter(c => !c.isDup).sort((a, b) => a.score - b.score);
    if (nonDupAny.length > 0) {
      bestCandidate = nonDupAny[0].result;
    } else if (selectable.length > 0) {
      selectable.sort((a, b) => a.score - b.score);
      bestCandidate = selectable[0].result;
    }
  }

  if (bestCandidate) {
    const selectedCandidate = candidates.find(c => c.result.fingerprint === bestCandidate!.fingerprint);
    const selectedScored = scored.find(c => c.result.fingerprint === bestCandidate!.fingerprint);

    // 2026-06-10 (vucko START-SNAP-FIX, Schicht 2): Globale Start-Wache —
    // die ausgelieferte Route MUSS am echten Standort beginnen. Greift, wenn
    // eine Offset-Eskalation gewonnen hat (A→B Phase D/E, Rundkurs-8-
    // Richtungs-Rettung, WP-Snap-Pass-1) ODER GraphHopper selbst >50m weit
    // gesnappt hat. Korrektur: kurzer Zubringer echter Start → erster
    // Routenpunkt wird vorangestellt (Rundkurs: zusätzlich Rückweg letzter
    // Punkt → echter Start), inkl. Instruction-Intervall-Shift. Scheitert die
    // Korrektur, liefern wir KEINE versetzte Route aus.
    if (req.start_location) {
      const sLatReq = req.start_location.latitude;
      const sLngReq = req.start_location.longitude;
      const mainCoords = bestCandidate.geometry.coordinates as [number, number][];
      if (mainCoords.length > 1) {
        const startOffsetM = distanceMeters(sLatReq, sLngReq, mainCoords[0][1], mainCoords[0][0]);
        if (startOffsetM > 50) {
          console.log(`[START-GUARD] route starts ${startOffsetM.toFixed(0)}m from requested start — building access connector`);
          const connector = await callGraphHopper({
            startLat: sLatReq,
            startLng: sLngReq,
            endLat: mainCoords[0][1],
            endLng: mainCoords[0][0],
            profile: 'car', // robustester Snap für den kurzen Zubringer
            isRoundTrip: false,
            avoidHighways: req.avoid_highways ?? false,
            serverUrl: lastServerUsed,
            preferMainRoads: shouldPreferMainRoads,
            headingDeg: req.reroute_request === true ? req.current_heading : undefined,
          });
          // Zubringer plausibel? (kein 10km-Umweg für 150m Versatz)
          const connectorOk = !('error' in connector) &&
            connector.distanceKm * 1000 <= Math.max(1500, startOffsetM * 6);
          if (connectorOk) {
            const conn = connector as RouteResult;
            // GH-Sign 4/5 = Ankunfts-Instructions des Zubringers — entfernen,
            // die Hauptroute übernimmt; Intervalle ggf. um `by` Punkte schieben.
            const stripArrival = (list: Array<Record<string, unknown>> | undefined) =>
              (list ?? []).filter((ins) => {
                const s = ins.sign as number | undefined;
                return s !== 4 && s !== 5;
              });
            const shiftInstr = (list: Array<Record<string, unknown>>, by: number) =>
              list.map((ins) => {
                const iv = ins.interval as [number, number] | undefined;
                return iv ? { ...ins, interval: [iv[0] + by, iv[1] + by] } : { ...ins };
              });
            const connCoords = conn.geometry.coordinates as [number, number][];
            const prependPts = connCoords.slice(0, -1); // letzter ≈ mainCoords[0]
            const shift = prependPts.length;
            let finalCoords: [number, number][] = [...prependPts, ...mainCoords];
            let mergedInstr = [
              ...stripArrival(conn.instructions),
              ...shiftInstr(bestCandidate.instructions ?? [], shift),
            ];
            let mergedDistKm = bestCandidate.distanceKm + conn.distanceKm;
            let mergedDurS = bestCandidate.durationSeconds + conn.durationSeconds;
            let mergedAscent = bestCandidate.ascent + conn.ascent;
            // Rundkurs: auch das ENDE zum echten Start zurückführen, sonst
            // schließt die Schleife am versetzten Punkt statt am Standort.
            if (isRoundTrip) {
              const lastPt = mainCoords[mainCoords.length - 1];
              const back = await callGraphHopper({
                startLat: lastPt[1],
                startLng: lastPt[0],
                endLat: sLatReq,
                endLng: sLngReq,
                profile: 'car',
                isRoundTrip: false,
                avoidHighways: req.avoid_highways ?? false,
                serverUrl: lastServerUsed,
                preferMainRoads: shouldPreferMainRoads,
              });
              if (!('error' in back) && back.distanceKm * 1000 <= Math.max(1500, startOffsetM * 6)) {
                const br = back as RouteResult;
                const appendShift = finalCoords.length - 1;
                const backCoords = (br.geometry.coordinates as [number, number][]).slice(1);
                finalCoords = [...finalCoords, ...backCoords];
                // „Ziel erreicht" der Hauptroute ans neue Ende verschieben.
                const lastInstr = mergedInstr.length > 0
                  ? mergedInstr[mergedInstr.length - 1] as Record<string, unknown>
                  : undefined;
                const lastSign = lastInstr ? (lastInstr.sign as number | undefined) : undefined;
                const hasArrival = lastInstr != null && (lastSign === 4 || lastSign === 5);
                const bodyInstr = hasArrival ? mergedInstr.slice(0, -1) : mergedInstr;
                mergedInstr = [
                  ...bodyInstr,
                  ...shiftInstr(stripArrival(br.instructions), appendShift),
                  ...(hasArrival
                    ? [{ ...lastInstr, interval: [finalCoords.length - 1, finalCoords.length - 1] }]
                    : []),
                ];
                mergedDistKm += br.distanceKm;
                mergedDurS += br.durationSeconds;
                mergedAscent += br.ascent;
              } else {
                const reason = 'error' in back ? back.error.slice(0, 120) : 'detour too long';
                console.log(`[START-GUARD] roundtrip return connector unavailable (${reason}) — rejecting offset loop`);
                return jsonResponse({
                  error: 'start_offset_uncorrectable',
                  user_message:
                    'Die berechnete Route konnte nicht sauber an deinen Standort angebunden werden. Bitte versuche es erneut.',
                  debug_message:
                    `roundtrip_return_connector_unavailable offset=${Math.round(startOffsetM)}m reason=${reason}`,
                  meta: {
                    response_code: 'start_offset_uncorrectable',
                    start_offset_meters: Math.round(startOffsetM),
                  },
                }, 502);
              }
            }
            bestCandidate = {
              ...bestCandidate,
              geometry: { ...bestCandidate.geometry, coordinates: finalCoords },
              distanceKm: mergedDistKm,
              durationSeconds: mergedDurS,
              ascent: mergedAscent,
              coordinateCount: finalCoords.length,
              fingerprint: buildFingerprint(finalCoords, mergedDistKm),
              instructions: mergedInstr,
              meta: { ...bestCandidate.meta, start_corrected_from_m: Math.round(startOffsetM) },
            };
            console.log(`[START-GUARD] connector ok (+${(conn.distanceKm * 1000).toFixed(0)}m) — route now starts at requested start`);
          } else {
            const reason = 'error' in connector ? connector.error.slice(0, 120) : 'detour too long';
            console.log(`[START-GUARD] connector unavailable (${reason}) — rejecting offset route`);
            return jsonResponse({
              error: 'start_offset_uncorrectable',
              user_message:
                'Die berechnete Route konnte nicht sauber an deinen Standort angebunden werden. Bitte versuche es erneut.',
              debug_message:
                `start_connector_unavailable offset=${Math.round(startOffsetM)}m reason=${reason}`,
              meta: {
                response_code: 'start_offset_uncorrectable',
                start_offset_meters: Math.round(startOffsetM),
              },
            }, 502);
          }
        }
        const finalFirst = (bestCandidate.geometry.coordinates as [number, number][])[0];
        bestCandidate.meta.start_offset_m = Math.round(
          distanceMeters(sLatReq, sLngReq, finalFirst[1], finalFirst[0]),
        );
      }
    }
    const finalCoords = bestCandidate.geometry.coordinates as [number, number][];
    const finalCountry = countryRouteMetrics(finalCoords, homeCountryCode);
    const finalForeignFraction = Math.max(finalCountry.foreignPointFraction, finalCountry.foreignDistanceFraction);
    const finalCountriesTouched = finalCountry.countriesTouched;
    const deliveredDetourLevel = !isRoundTrip
      ? Math.max(
          0,
          Math.min(
            detourLevel,
            Math.round(
              finiteNumberOr(
                bestCandidate.meta.delivered_detour_level ?? bestCandidate.meta.detour_level,
                0,
              ),
            ),
          ),
        )
      : 0;
    const detourRatio = !isRoundTrip && req.start_location && req.target_location
      ? Number((bestCandidate.distanceKm / Math.max(
          0.1,
          distanceMeters(
            req.start_location.latitude,
            req.start_location.longitude,
            req.target_location.latitude,
            req.target_location.longitude,
          ) / 1000,
        )).toFixed(2))
      : undefined;
    const finalCountryRejected =
      strictInland &&
      (finalCountry.foreignPointFraction > ONLY_HOME_MAX_FOREIGN_FRACTION ||
        finalCountry.foreignDistanceFraction > ONLY_HOME_MAX_FOREIGN_FRACTION ||
        finalCountry.maxForeignSegmentMeters > ONLY_HOME_MAX_FOREIGN_SEGMENT_METERS);
    if (finalCountryRejected) {
      return jsonResponse({
        error: 'no_inland_route',
        user_message:
          'Hier ist kein Rundkurs möglich, der im Land bleibt. Schalt „Im Land bleiben" aus oder wähl eine kürzere Distanz bzw. einen Start weiter im Landesinneren.',
        debug_message:
          `selected_candidate_crossed_border foreign=${finalForeignFraction.toFixed(3)} foreign_distance=${finalCountry.foreignDistanceFraction.toFixed(3)} max_segment_m=${Math.round(finalCountry.maxForeignSegmentMeters)} home=${homeCountryCode}`,
        meta: {
          response_code: 'no_inland_route',
          country_preference: countryPreference,
          home_country_code: homeCountryCode,
          avoid_cross_border: true,
          foreign_fraction: Number(finalForeignFraction.toFixed(3)),
          foreign_point_fraction: Number(finalCountry.foreignPointFraction.toFixed(3)),
          foreign_distance_fraction: Number(finalCountry.foreignDistanceFraction.toFixed(3)),
          max_foreign_segment_meters: Math.round(finalCountry.maxForeignSegmentMeters),
          countries_touched: finalCountriesTouched,
        },
      }, 422);
    }

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
        // 2026-06-02 (vucko): GraphHopper Turn-by-turn durchreichen → echte
        // Wegbeschreibung („300m rechts abbiegen") auf Handy + CarPlay.
        // Format: [{text, distance, time, sign, interval:[a,b], street_name}].
        instructions: bestCandidate.instructions ?? [],
      },
      meta: {
        ...bestCandidate.meta,
        route_fingerprint: bestCandidate.fingerprint,
        attempts_used: candidates.length,
        delta_pct: Number((selectedCandidate?.deltaPct ?? 0).toFixed(1)),
        synth_diag: synthDiagTop.length ? synthDiagTop.slice(0, 4) : undefined,
        was_duplicate: selectedCandidate?.isDup ?? false,
        region: region.label,
        compensation_factor: region.factor,
        requested_target_km: req.target_distance_km,
        effective_target_km: Number(effectiveDistanceKm?.toFixed(1)),
        requested_detour_level: !isRoundTrip ? detourLevel : undefined,
        delivered_detour_level: !isRoundTrip ? deliveredDetourLevel : undefined,
        detour_downgraded: !isRoundTrip && deliveredDetourLevel < detourLevel,
        detour_ratio: detourRatio,
        detour_offset_side: bestCandidate.meta.detour_offset_side,
        detour_bearing_deg: bestCandidate.meta.detour_bearing_deg,
        detour_perpendicular_km: bestCandidate.meta.detour_perpendicular_km,
        // 2026-08-18 (Aufgabe 1.3): welcher Term die Umweg-Basisdistanz
        // bestimmt hat, und wie viele Kandidaten wirklich losgeschickt wurden.
        detour_base_term: detourBasisTerm,
        detour_candidate_count: detourSpec.length > 0 ? detourSpec.length : undefined,
        // Vom Client geschickt, vom Server bewusst ignoriert (Begruendung bei
        // maxAttempts). Steht hier, damit „toter Parameter" messbar bleibt.
        client_candidate_budget: clientCandidateBudget,
        client_candidate_budget_ignored: clientCandidateBudget !== undefined,
        // v1-kompatible meta-Felder
        distance_km: Number(bestCandidate.distanceKm.toFixed(2)),
        duration_seconds: Math.round(bestCandidate.durationSeconds),
        // Style-Quality (turn-density Vergleich gegen Profile-Min)
        turn_count: selectedScored?.turns ?? 0,
        turns_per_km: Number((selectedScored?.turnsPerKm ?? 0).toFixed(2)),
        style_penalty: Number((selectedScored?.stylePenalty ?? 0).toFixed(1)),
        avg_speed_kmh: Number((selectedScored?.avgSpeedKmh ?? 0).toFixed(1)),
        speed_penalty: Number((selectedScored?.speedPenalty ?? 0).toFixed(1)),
        main_road_penalty: Number((selectedScored?.mainRoadPenalty ?? 0).toFixed(1)),
        // 2026-08-18 (Aufgabe 1.4): Anteil der Strecke, der ein zweites Mal in
        // Gegenrichtung befahren wird, plus die daraus gezogene Strafe.
        // Rueckfall auf das Kandidaten-Meta: die Notfallrouten (stitched-outback)
        // umgehen das Scoring, `selectedScored` ist dort undefined — ohne den
        // Rueckfall wuerde ausgerechnet die hin-und-zurueck-Route 0 melden.
        self_overlap_fraction: Number(
          (selectedScored?.selbstUeberlappung ??
            Number(bestCandidate.meta.self_overlap_fraction ?? 0)).toFixed(3),
        ),
        self_overlap_penalty: Number((selectedScored?.ueberlappStrafe ?? 0).toFixed(1)),
        profile_fallback_used: usedProfileFallback,
        country_preference: countryPreference,
        home_country_code: homeCountryCode,
        avoid_cross_border: strictInland,
        foreign_fraction: Number(finalForeignFraction.toFixed(3)),
        foreign_point_fraction: Number(finalCountry.foreignPointFraction.toFixed(3)),
        foreign_distance_fraction: Number(finalCountry.foreignDistanceFraction.toFixed(3)),
        max_foreign_segment_meters: Math.round(finalCountry.maxForeignSegmentMeters),
        countries_touched: finalCountriesTouched,
        country_rejected_count: scored.filter(c => c.countryRejected).length,
        country_penalty: Number((selectedScored?.countryScorePenalty ?? 0).toFixed(1)),
      },
    });
  }

  // 2026-05-24 (vucko Task #31): Spezifischere Error-Message bei
  // bekannten Mustern. Out-of-bounds = Coverage-Limit.
  let userMessage = 'Konnte aktuell keine passende Route generieren. Probier andere Distanz oder Stil.';
  let errCode = 'no_route';

  // 2026-05-27 (vucko Cross-Border-Detection): Wenn die Route MISCHUNG aus
  // DACH und EU-Süd ist (z.B. München→Mailand), kann aktuell keiner unserer
  // Server beide Punkte snappen. Klare Fehlermeldung statt cryptic "no_route".
  const allPoints: Array<{ lat: number; lng: number }> = [];
  if (req.start_location) {
    allPoints.push({ lat: req.start_location.latitude, lng: req.start_location.longitude });
  }
  if (req.target_location) {
    allPoints.push({ lat: req.target_location.latitude, lng: req.target_location.longitude });
  }
  if (req.waypoints) {
    for (const wp of req.waypoints) allPoints.push({ lat: wp.latitude, lng: wp.longitude });
  }
  const pointRegions = new Set(allPoints.map(p => classifyPoint(p.lat, p.lng)));
  const isCrossBorder = pointRegions.has(GeoRegion.dach) &&
    [GeoRegion.euSouth, GeoRegion.euWest, GeoRegion.euEast].some(r => pointRegions.has(r));

  // 2026-05-27 (vucko v3): Cross-Border ist jetzt PC2-supported (PC2 hat
  // dach-italy-balkan.osm.pbf). Daher nur noch als Last-Resort-Message wenn
  // PC2 wirklich offline ist UND DACH-PC1 das auch nicht abdecken kann.
  if (isCrossBorder && (lastError.includes('fetch failed') || lastError.includes('error sending request'))) {
    userMessage = 'Cross-Border-Routing-Server vorübergehend nicht erreichbar. Bleibe vorerst entweder im DACH-Raum ODER innerhalb Italien/Slowenien/Kroatien.';
    errCode = 'cross_border_server_offline';
  } else if (lastError.includes('out of bounds')) {
    userMessage = 'Diese Route reicht über unser aktuelles Liefergebiet hinaus. Wir unterstützen DACH (DE, AT, CH) plus Italien, Slowenien, Kroatien und Süd-Frankreich. Setze Stopps näher beieinander.';
    errCode = 'coverage_out_of_bounds';
  } else if (lastError.includes('Cannot find point')) {
    // Parse welcher Punkt — Index sagt uns ob Start/Ziel/Wegpunkt.
    const pointIdxMatch = lastError.match(/Cannot find point (\d+):/);
    const idx = pointIdxMatch ? parseInt(pointIdxMatch[1], 10) : null;
    const hasWaypoints = (req.waypoints?.length ?? 0) > 0;
    if (idx === 0) {
      userMessage = 'Dein Start-Punkt konnte nicht an eine befahrbare Straße angedockt werden. Verschiebe ihn ein paar Meter auf eine sichtbare Straße.';
    } else if (idx != null && hasWaypoints && idx > 0 && idx <= (req.waypoints?.length ?? 0)) {
      userMessage = `Der Wegpunkt #${idx} konnte nicht an eine befahrbare Straße angedockt werden. Verschiebe ihn auf eine ländliche Straße (Stadtkern-Plätze funktionieren oft nicht — probiere einen Vorort).`;
    } else {
      userMessage = 'Dein Ziel konnte nicht an eine befahrbare Straße angedockt werden. Verschiebe es ein paar Meter auf eine sichtbare Straße.';
    }
    errCode = 'point_off_road';
  } else if (lastError.includes('Ferry detected')) {
    userMessage = 'Wir konnten keine Land-Route finden — versuche andere Wegpunkte.';
    errCode = 'no_land_route';
  }


  // 2026-08-18 (D1b): Statuscode nach URSACHE, nicht pauschal 502. Der Client
  // stempelt jeden 5xx als „temporaerer Serverfehler, gleich nochmal
  // versuchen" — bei diesen drei Faellen ist das eine Luege: die Anfrage ist
  // so nicht erfuellbar, egal wie oft man sie wiederholt. 422 sagt das.
  // `cross_border_server_offline` bleibt 5xx (503), denn da IST der Server weg.
  const fachlich = errCode === 'coverage_out_of_bounds' ||
    errCode === 'point_off_road' ||
    errCode === 'no_land_route';
  const status = fachlich ? 422 : (errCode === 'cross_border_server_offline' ? 503 : 502);
  if (errCode === 'coverage_out_of_bounds' && req.start_location) {
    merkeAbdeckungswunsch(
      req.start_location.latitude,
      req.start_location.longitude,
      req._subject_id ?? null,
      classifyCountry(req.start_location.latitude, req.start_location.longitude),
    );
  }
  return jsonResponse({
    error: errCode,
    user_message: userMessage,
    debug_message: lastError,
    region: region.label,
    attempts: Math.min(maxAttempts, seeds.length),
  }, status);
}

// ─────────────────── Seed-Generation ──────────────────────────────────────

function generateSeeds(opts: {
  forceFresh: boolean;
  startLat: number;
  startLng: number;
  targetKm: number;
  // 2026-07-06 (vucko Routen-Wiederholung): Settings in den deterministischen
  // Seed-Hash mischen. Vorher lieferten „Autobahn an" vs. „Autobahn aus" bzw.
  // Stil-Wechsel bei gleichem Start+Distanz IDENTISCHE Seeds → die Sub-
  // Waypoints landeten an denselben Stellen → stark korrelierte Geometrie,
  // gefühlt „immer dieselbe Route trotz geänderter Einstellungen".
  avoidHighways?: boolean;
  styleKey?: string;
  detourLevel?: number;
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
  const settingsSalt =
    (opts.avoidHighways ? 7919 : 0) +
    (opts.detourLevel ?? 0) * 2711 +
    stableHashInt(opts.styleKey ?? '') % 5081;
  const h = Math.abs(
    Math.round(opts.startLat * 1000) * 31 +
    Math.round(opts.startLng * 1000) * 17 +
    Math.round(opts.targetKm) * 7 +
    settingsSalt,
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

// ── Rate-Limiting (fail-open) ───────────────────────────────────────────────
// Schützt DB + GraphHopper gegen Spam/Abuse, OHNE normale Nutzer (oder die
// live-testende Suite) je zu treffen: großzügige Limits + jeder Fehler/Timeout
// => Request darf durch. Kill-Switch via RATE_LIMIT_ENABLED. verify_jwt bleibt
// false — wir lesen den JWT-sub nur zum Keying, prüfen die Signatur NICHT.
const RL_ENABLED = (Deno.env.get('RATE_LIMIT_ENABLED') ?? 'true') === 'true';
const RL_DB_TIMEOUT_MS = 800;
// 2026-06-26 (vucko): authed-Limits bewusst großzügig — ein ungeduldiger Nutzer,
// der „Andere Route" mehrfach tippt, oder dichtes Reroute auf kurviger Strecke
// soll NIE ein 429 sehen. Der per-User-Deckel (100/min) ist für einen Menschen
// unerreichbar, stoppt aber Skript-Abuse pro Account. anon (nur Direkt-API ohne
// Login + Test-Suite) bleibt 600/min/IP gegen anonymes Hämmern auf GraphHopper.
const RL_LIMITS = {
  authed_generate: { max: 100, windowSec: 60 },
  authed_reroute: { max: 200, windowSec: 60 },
  anon_generate: { max: 600, windowSec: 60 },
} as const;

// Service-Role-Client NUR für den check_rate_limit-RPC, einmal modul-global.
// Fehlt eine ENV => null => Limiter komplett aus (fail-open).
const _rlAdmin = (() => {
  try {
    const u = Deno.env.get('SUPABASE_URL');
    const k = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!u || !k) return null;
    return createClient(u, k, { auth: { persistSession: false } });
  } catch (_) {
    return null;
  }
})();

/// Liefert den Rate-Limit-Schluessel UND — getrennt davon — die Identitaet.
///
/// 2026-08-18 (Defekt 5): Vorher gab es nur `key` und `tier`, und die
/// Telemetrie holte sich die Nutzer-ID mit `rl.key.slice(4)` aus dem
/// Rate-Limit-Schluessel zurueck. Das ist eine stille Kopplung: aendert
/// jemand das Praefix `uid:`, schreibt das Ereignisprotokoll ab sofort
/// unbrauchbare IDs, ohne dass ein Test oder ein Fehler das meldet. Ein
/// Rate-Limit-Schluessel ist ein Rate-Limit-Schluessel, keine Identitaet.
function rlExtractKey(
  req: Request,
): { key: string; tier: 'authed' | 'anon'; subjectId: string | null } {
  try {
    const auth = req.headers.get('authorization') ?? '';
    const token = auth.replace(/^Bearer\s+/i, '');
    const parts = token.split('.');
    if (parts.length === 3) {
      const payload = JSON.parse(
        atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')),
      );
      if (
        payload.role === 'authenticated' &&
        typeof payload.sub === 'string' &&
        payload.sub.length > 0
      ) {
        return {
          key: `uid:${payload.sub}`,
          tier: 'authed',
          subjectId: payload.sub,
        };
      }
    }
  } catch (_) {
    // unparsebar/anon => IP-Pfad
  }
  const ip =
    req.headers.get('cf-connecting-ip') ??
    (req.headers.get('x-forwarded-for') ?? '').split(',')[0].trim();
  return {
    key: ip ? `ip:${ip}` : 'anon:shared',
    tier: 'anon',
    subjectId: null,
  };
}

/// Woher kam die Anfrage? Ohne diese Angabe sah es aus, als haetten 47 % der
/// Routenanfragen keinen Nutzer. Tatsaechlich stammen die anonymen Zeilen aus
/// Messlaeufen: am 16.08. 399 Stueck in 16 Minuten (25 pro Minute), am 30.07.
/// 52 in 11 Minuten. An 17 von 21 Tagen war KEINE einzige Zeile ohne Konto.
/// Mit dieser Spalte laesst sich das trennen, statt es zu raten.
function normalizeOrigin(roh: unknown): 'app' | 'test' | 'worker' | 'unknown' {
  const v = typeof roh === 'string' ? roh.trim().toLowerCase() : '';
  if (v === 'app' || v === 'test' || v === 'worker') return v;
  return 'unknown';
}

async function rlAllows(
  key: string,
  action: string,
  max: number,
  windowSec: number,
): Promise<{ allowed: boolean; retryAfter: number }> {
  if (!RL_ENABLED || !_rlAdmin) return { allowed: true, retryAfter: 0 };
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), RL_DB_TIMEOUT_MS);
    const { data, error } = await _rlAdmin
      .rpc('check_rate_limit', {
        p_key: key,
        p_action: action,
        p_max: max,
        p_window_seconds: windowSec,
      })
      .abortSignal(ctrl.signal)
      .maybeSingle();
    clearTimeout(t);
    if (error || !data) return { allowed: true, retryAfter: 0 };
    const row = data as { allowed?: boolean; retry_after?: number };
    return { allowed: row.allowed === true, retryAfter: row.retry_after ?? 0 };
  } catch (_) {
    return { allowed: true, retryAfter: 0 };
  }
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
    // 2026-06-29 (vucko): Prueft ALLE distinct Server parallel, nicht nur den
    // Primaer — sonst zeigt /health rot, obwohl ueber Failover (PC1) sauber
    // geroutet wird. ok=true sobald IRGENDEIN Server antwortet.
    const targets: Array<[string, string]> = [
      ['primary', GRAPHHOPPER_URL],
      ['de', GRAPHHOPPER_DE_URL],
      ['eu', GRAPHHOPPER_EU_URL],
    ];
    const servers: Record<string, string> = {};
    let anyUp = false;
    await Promise.all(targets.map(async ([name, base]) => {
      try {
        const r = await fetch(`${base}/health`, { signal: AbortSignal.timeout(4000) });
        servers[name] = r.ok ? 'up' : 'down';
        if (r.ok) anyUp = true;
      } catch (_) {
        servers[name] = 'unreachable';
      }
    }));
    return jsonResponse(
      { ok: anyUp, graphhopper: anyUp ? 'up' : 'down', servers },
      anyUp ? 200 : 503,
    );
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
  // ── Rate-Limit-Gate (fail-open) ── direkt vor der teuren GraphHopper-Arbeit,
  // nach OPTIONS/health/method/JSON/start_location (die werden nie limitiert).
  const rl = rlExtractKey(req);
  const rlBody = body as { reroute_request?: boolean; moving_start?: boolean };
  const isReroute = rlBody.reroute_request === true || rlBody.moving_start === true;
  const rlAction = rl.tier === 'authed'
    ? (isReroute ? 'route_reroute' : 'route_generate')
    : 'route_generate_anon';
  const rlLimit = rl.tier === 'authed'
    ? (isReroute ? RL_LIMITS.authed_reroute : RL_LIMITS.authed_generate)
    : RL_LIMITS.anon_generate;
  const rlGate = await rlAllows(rl.key, rlAction, rlLimit.max, rlLimit.windowSec);
  if (!rlGate.allowed) {
    return new Response(
      JSON.stringify({
        error: 'rate_limited',
        user_message:
          'Zu viele Routenanfragen in kurzer Zeit. Bitte einen Moment warten und erneut versuchen.',
        retry_after: rlGate.retryAfter,
      }),
      {
        status: 429,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': ALLOWED_ORIGINS,
          'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
          'Retry-After': String(rlGate.retryAfter),
        },
      },
    );
  }
  // ── Generierungs-Telemetrie (2026-07-11): speist route_generation_events
  // fürs Admin-Monitoring (Generierungen 24h/7d, Heute-Seite, Wochenvergleich).
  // Die alte route_search_sessions-Queue ist seit der v2-Edge tot — dieses
  // Logging ist ihr schlanker Ersatz. Best-effort: Telemetrie-Fehler dürfen
  // NIEMALS das Routing beeinträchtigen. Reroutes zählen nicht als Suche.
  const genStartedAt = Date.now();
  // 2026-08-18 (D1c): Identitaet aus dem JWT in den Body reichen, damit ein
  // Abdeckungswunsch dem Konto zugeordnet werden kann. Bewusst NACH
  // normalizeRequest, das den Feldwert des Clients verwirft.
  body._subject_id = rl.subjectId;
  const res = await generateRoute(body);
  if (!isReroute && _rlAdmin) {
    try {
      let success = res.status === 200;
      let genErrCode: string | null = null;
      try {
        const peek = await res.clone().json();
        if (peek && typeof peek === 'object' && (peek as { error?: unknown }).error) {
          success = false;
          genErrCode = String((peek as { error: unknown }).error).slice(0, 60);
        }
      } catch (_) {
        // Antwort ist kein JSON — der HTTP-Status entscheidet.
      }
      const b = body as Record<string, unknown>;
      const logPromise = _rlAdmin
        .from('route_generation_events')
        .insert({
          user_id: rl.subjectId,
          route_type: (b.route_type as string) ?? 'ROUND_TRIP',
          style_key: (b.selected_style ?? b.mode)?.toString().slice(0, 40) ?? null,
          distance_km:
            Math.round(Number(b.target_distance_km ?? b.targetDistance ?? 0)) || null,
          avoid_highways: b.avoid_highways === true,
          source: 'edge_v2',
          origin: normalizeOrigin((body as Record<string, unknown>).origin),
          success,
          error_code: genErrCode,
          duration_ms: Date.now() - genStartedAt,
        })
        .then(() => {}, () => {});
      const er = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } }).EdgeRuntime;
      if (er?.waitUntil) er.waitUntil(logPromise);
      else await logPromise;
    } catch (_) {
      // Telemetrie ist nie ein Fehler fürs Routing.
    }
  }
  return res;
}

serve(handler);
