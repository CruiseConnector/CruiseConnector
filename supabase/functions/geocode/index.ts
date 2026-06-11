import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type JsonMap = Record<string, unknown>;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const GEOCODER_BASE_URL = trimTrailingSlash(
  Deno.env.get("GEOCODER_BASE_URL") ??
    Deno.env.get("PHOTON_URL") ??
    Deno.env.get("NOMINATIM_URL") ??
    "",
);
const GEOCODER_KIND = (
  Deno.env.get("GEOCODER_KIND") ??
    (Deno.env.get("NOMINATIM_URL") ? "nominatim" : "photon")
).toLowerCase();
const GEOCODER_PROVIDER = Deno.env.get("GEOCODER_PROVIDER") ??
  (GEOCODER_BASE_URL.includes("photon.komoot.io")
    ? "photon_komoot"
    : `self_hosted_${GEOCODER_KIND}`);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }
  if (!GEOCODER_BASE_URL) {
    return jsonResponse({ error: "self_hosted_geocoder_not_configured" }, 503);
  }

  let body: JsonMap;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const type = stringValue(body.type) ?? "search";
  try {
    if (type === "reverse") {
      const latitude = numberValue(body.latitude);
      const longitude = numberValue(body.longitude);
      if (latitude == null || longitude == null) {
        return jsonResponse({ error: "missing_reverse_coordinates" }, 400);
      }
      const feature = await reverseGeocode({
        latitude,
        longitude,
        language: stringValue(body.language) ?? "de",
      });
      return jsonResponse({
        provider: GEOCODER_PROVIDER,
        place_name: feature == null ? null : stringValue(feature.place_name),
        center: feature == null ? null : feature.center ?? null,
        context: feature == null ? null : feature.context ?? null,
        features: feature == null ? [] : [feature],
      });
    }

    const query = stringValue(body.query)?.trim() ?? "";
    if (query.length === 0) {
      return jsonResponse({
        provider: GEOCODER_PROVIDER,
        features: [],
      });
    }
    const features = await searchGeocode({
      query,
      language: stringValue(body.language) ?? "de",
      countryCodes: stringValue(body.country_codes) ?? "at,de,ch",
      limit: clampInt(body.limit, 7, 1, 10),
      proximityLatitude: numberValue(body.proximity_latitude),
      proximityLongitude: numberValue(body.proximity_longitude),
    });
    return jsonResponse({ provider: GEOCODER_PROVIDER, features });
  } catch (error) {
    return jsonResponse({
      error: "self_hosted_geocoder_failed",
      message: error instanceof Error ? error.message : String(error),
    }, 502);
  }
});

async function searchGeocode(options: {
  query: string;
  language: string;
  countryCodes: string;
  limit: number;
  proximityLatitude: number | null;
  proximityLongitude: number | null;
}): Promise<JsonMap[]> {
  if (GEOCODER_KIND === "nominatim") {
    return searchNominatim(options);
  }
  return searchPhoton(options);
}

async function reverseGeocode(options: {
  latitude: number;
  longitude: number;
  language: string;
}): Promise<JsonMap | null> {
  if (GEOCODER_KIND === "nominatim") {
    return reverseNominatim(options);
  }
  return reversePhoton(options);
}

async function searchPhoton(options: {
  query: string;
  language: string;
  countryCodes: string;
  limit: number;
  proximityLatitude: number | null;
  proximityLongitude: number | null;
}): Promise<JsonMap[]> {
  const url = new URL(`${GEOCODER_BASE_URL}/api`);
  url.searchParams.set("q", options.query);
  url.searchParams.set("limit", String(options.limit));
  url.searchParams.set("lang", options.language);
  if (options.proximityLatitude != null && options.proximityLongitude != null) {
    url.searchParams.set("lat", String(options.proximityLatitude));
    url.searchParams.set("lon", String(options.proximityLongitude));
  }
  const data = await fetchJson(url);
  const features = Array.isArray(data?.features) ? data.features : [];
  return features.map(normalizePhotonFeature).filter(isJsonMap);
}

async function reversePhoton(options: {
  latitude: number;
  longitude: number;
  language: string;
}): Promise<JsonMap | null> {
  const url = new URL(`${GEOCODER_BASE_URL}/reverse`);
  url.searchParams.set("lat", String(options.latitude));
  url.searchParams.set("lon", String(options.longitude));
  url.searchParams.set("lang", options.language);
  const data = await fetchJson(url);
  const features = Array.isArray(data?.features) ? data.features : [];
  const normalized = normalizePhotonFeature(features[0]);
  return isJsonMap(normalized) ? normalized : null;
}

async function searchNominatim(options: {
  query: string;
  language: string;
  countryCodes: string;
  limit: number;
}): Promise<JsonMap[]> {
  const url = new URL(`${GEOCODER_BASE_URL}/search`);
  url.searchParams.set("q", options.query);
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("addressdetails", "1");
  url.searchParams.set("limit", String(options.limit));
  url.searchParams.set("accept-language", options.language);
  const countries = countryCodes(options.countryCodes);
  if (countries.length > 0) {
    url.searchParams.set("countrycodes", countries.join(","));
  }
  const data = await fetchJson(url);
  const rows = Array.isArray(data) ? data : [];
  return rows.map(normalizeNominatimRow).filter(isJsonMap);
}

async function reverseNominatim(options: {
  latitude: number;
  longitude: number;
  language: string;
}): Promise<JsonMap | null> {
  const url = new URL(`${GEOCODER_BASE_URL}/reverse`);
  url.searchParams.set("lat", String(options.latitude));
  url.searchParams.set("lon", String(options.longitude));
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("addressdetails", "1");
  url.searchParams.set("zoom", "18");
  url.searchParams.set("accept-language", options.language);
  const data = await fetchJson(url);
  const normalized = normalizeNominatimRow(data);
  return isJsonMap(normalized) ? normalized : null;
}

async function fetchJson(url: URL): Promise<any> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 6_000);
  try {
    const response = await fetch(url, {
      headers: {
        accept: "application/json",
        "user-agent": "CruiseConnect-Geocoder/1.0",
      },
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`geocoder_http_${response.status}`);
    }
    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
}

function normalizePhotonFeature(feature: unknown): JsonMap | null {
  if (!isJsonMap(feature)) return null;
  const geometry = feature.geometry;
  const properties = isJsonMap(feature.properties) ? feature.properties : {};
  const coordinates = isJsonMap(geometry) && Array.isArray(geometry.coordinates)
    ? geometry.coordinates
    : null;
  if (!coordinates || coordinates.length < 2) return null;
  const lng = numberValue(coordinates[0]);
  const lat = numberValue(coordinates[1]);
  if (lng == null || lat == null) return null;
  const name = firstString(
    properties.name,
    properties.street,
    properties.city,
    properties.county,
    properties.state,
  );
  const context = compactStrings([
    properties.housenumber,
    properties.street && properties.street !== name ? properties.street : null,
    properties.postcode,
    properties.city,
    properties.county,
    properties.state,
    properties.country,
  ]).join(", ");
  const placeName = compactStrings([name, context]).join(", ");
  return {
    place_name: placeName || context || `${lat.toFixed(5)}, ${lng.toFixed(5)}`,
    center: [lng, lat],
    context: context || null,
  };
}

function normalizeNominatimRow(row: unknown): JsonMap | null {
  if (!isJsonMap(row)) return null;
  const lat = numberValue(row.lat);
  const lng = numberValue(row.lon);
  if (lng == null || lat == null) return null;
  const address = isJsonMap(row.address) ? row.address : {};
  const name = firstString(
    row.name,
    address.amenity,
    address.road,
    address.neighbourhood,
    address.suburb,
    address.city,
    address.town,
    address.village,
  );
  const context = compactStrings([
    address.house_number,
    address.road,
    address.postcode,
    address.city,
    address.town,
    address.village,
    address.state,
    address.country,
  ]).join(", ");
  const displayName = stringValue(row.display_name);
  return {
    place_name: displayName ?? compactStrings([name, context]).join(", "),
    center: [lng, lat],
    context: context || null,
  };
}

function countryCodes(value: string): string[] {
  return value
    .split(",")
    .map((part) => part.trim().toLowerCase())
    .filter((part) => part.length === 2);
}

function compactStrings(values: unknown[]): string[] {
  const result: string[] = [];
  for (const value of values) {
    const text = stringValue(value)?.trim();
    if (!text || result.includes(text)) continue;
    result.push(text);
  }
  return result;
}

function firstString(...values: unknown[]): string {
  return compactStrings(values)[0] ?? "";
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

function numberValue(value: unknown): number | null {
  const parsed = typeof value === "number"
    ? value
    : typeof value === "string"
    ? Number(value)
    : NaN;
  return Number.isFinite(parsed) ? parsed : null;
}

function isJsonMap(value: unknown): value is JsonMap {
  return value != null && typeof value === "object" && !Array.isArray(value);
}

function clampInt(
  value: unknown,
  fallback: number,
  min: number,
  max: number,
): number {
  const parsed = Number(value ?? fallback);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, Math.round(parsed)));
}

function trimTrailingSlash(value: string): string {
  return value.replace(/\/+$/, "");
}

function jsonResponse(body: JsonMap, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
