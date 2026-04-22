import type { Coordinate } from "./routing_types.ts";

export function wait(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function normalizeBearingDegrees(value: number): number {
  const normalized = value % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}

export function normalizeExcludeParams(exclude: string): string {
  return [
    ...new Set(
      exclude.split(",").map((value) => value.trim()).filter((value) =>
        value.length > 0
      ),
    ),
  ].join(",");
}

export function addExcludeParam(exclude: string, value: string): string {
  return normalizeExcludeParams(`${exclude},${value}`);
}

export function removeExcludeParam(exclude: string, value: string): string {
  return normalizeExcludeParams(
    exclude.split(",").map((entry) => entry.trim()).filter((entry) =>
      entry.length > 0 && entry !== value
    ).join(","),
  );
}

export function applyAvoidHighwaysExcludes(
  exclude: string,
  avoidHighways: boolean,
): string {
  let next = exclude;
  // Mapbox Directions akzeptiert hier nur den Highway-Exclude "motorway".
  // Road classes wie "motorway_link" tauchen in Responses auf, sind aber
  // keine gueltigen exclude-Tokens und fuehren sonst zu InvalidInput/422.
  for (const value of ["motorway"]) {
    next = avoidHighways
      ? addExcludeParam(next, value)
      : removeExcludeParam(next, value);
  }
  return normalizeExcludeParams(next);
}

export function isStreetClassExclude(value: string): boolean {
  return value === "motorway";
}

export function relaxStreetExcludes(
  exclude: string,
  avoidHighways: boolean,
): string {
  const normalized = normalizeExcludeParams(exclude);
  if (normalized === "") return "";
  const preserved = normalized.split(",").filter((entry) =>
    entry.length > 0 &&
    (
      !isStreetClassExclude(entry) ||
      (avoidHighways && isStreetClassExclude(entry))
    )
  );
  return normalizeExcludeParams(preserved.join(","));
}

export function seededBaseBearing(
  seed: number,
  preferredBearingDegrees?: number,
  jitterDegrees: number = 110,
): number {
  if (
    typeof preferredBearingDegrees === "number" &&
    Number.isFinite(preferredBearingDegrees)
  ) {
    const jitter = (seededUnit(seed + 601) - 0.5) *
      Math.max(0, jitterDegrees);
    return normalizeBearingDegrees(preferredBearingDegrees + jitter);
  }
  return seededUnit(seed) * 360;
}

export function calculateDestination(
  start: Coordinate,
  distanceKm: number,
  bearingDegrees: number,
): Coordinate {
  const R = 6371; // Earth's radius in km
  const bearingRad = (bearingDegrees * Math.PI) / 180;
  const lat1 = (start.latitude * Math.PI) / 180;
  const lon1 = (start.longitude * Math.PI) / 180;

  const lat2 = Math.asin(
    Math.sin(lat1) * Math.cos(distanceKm / R) +
      Math.cos(lat1) * Math.sin(distanceKm / R) * Math.cos(bearingRad),
  );

  const lon2 = lon1 + Math.atan2(
    Math.sin(bearingRad) * Math.sin(distanceKm / R) * Math.cos(lat1),
    Math.cos(distanceKm / R) - Math.sin(lat1) * Math.sin(lat2),
  );

  return {
    latitude: (lat2 * 180) / Math.PI,
    longitude: (lon2 * 180) / Math.PI,
  };
}

export function calculateBearing(from: Coordinate, to: Coordinate): number {
  const lat1 = (from.latitude * Math.PI) / 180;
  const lat2 = (to.latitude * Math.PI) / 180;
  const dLon = ((to.longitude - from.longitude) * Math.PI) / 180;

  const y = Math.sin(dLon) * Math.cos(lat2);
  const x = Math.cos(lat1) * Math.sin(lat2) -
    Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);

  const bearing = (Math.atan2(y, x) * 180) / Math.PI;
  return (bearing + 360) % 360;
}

export function calculateDistance(from: Coordinate, to: Coordinate): number {
  const R = 6371;
  const lat1 = (from.latitude * Math.PI) / 180;
  const lat2 = (to.latitude * Math.PI) / 180;
  const dLat = ((to.latitude - from.latitude) * Math.PI) / 180;
  const dLon = ((to.longitude - from.longitude) * Math.PI) / 180;

  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1) * Math.cos(lat2) *
      Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c;
}

export function interpolateCoordinate(
  from: Coordinate,
  to: Coordinate,
  fraction: number,
): Coordinate {
  const clamped = Math.min(1, Math.max(0, fraction));
  return {
    latitude: from.latitude + (to.latitude - from.latitude) * clamped,
    longitude: from.longitude + (to.longitude - from.longitude) * clamped,
  };
}

export function seededUnit(seed: number): number {
  const raw = Math.sin(seed * 12.9898 + 78.233) * 43758.5453123;
  return raw - Math.floor(raw);
}

export function stableStringHash(input: string): number {
  let hash = 2166136261;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0);
}

export function normalizeHint(value?: string): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

export function smoothDistanceSeries(values: number[]): number[] {
  if (values.length < 3) return values;
  return values.map((value, index) => {
    const start = Math.max(0, index - 1);
    const end = Math.min(values.length - 1, index + 1);
    let sum = 0;
    let count = 0;
    for (let i = start; i <= end; i++) {
      sum += values[i];
      count += 1;
    }
    return count === 0 ? value : sum / count;
  });
}

export function countCenterReentries(
  distances: number[],
  radiusMeters: number,
): number {
  if (distances.length < 6) return 0;
  let hasLeftStart = false;
  let previousInside = true;
  let reentries = 0;

  for (let i = 1; i < distances.length - 1; i++) {
    const inside = distances[i] <= radiusMeters;
    if (!hasLeftStart && !inside) {
      hasLeftStart = true;
    } else if (
      hasLeftStart && inside && !previousInside && i < distances.length - 3
    ) {
      reentries += 1;
    }
    previousInside = inside;
  }

  return reentries;
}

export function countMajorDistancePeaks(
  distances: number[],
  minimumHeight: number,
): number {
  if (distances.length < 5) return 0;
  let peaks = 0;
  for (let i = 2; i < distances.length - 2; i++) {
    const current = distances[i];
    if (current < minimumHeight) continue;
    if (
      current >= distances[i - 1] &&
      current >= distances[i + 1] &&
      current > distances[i - 2] &&
      current > distances[i + 2]
    ) {
      peaks += 1;
    }
  }
  return peaks;
}

export function estimateMiddleCoverageRatio(
  distances: number[],
  maxDistance: number,
): number {
  if (distances.length < 4 || maxDistance <= 0) return 0;
  const startIndex = Math.floor(distances.length * 0.22);
  const endIndex = Math.ceil(distances.length * 0.78);
  let sum = 0;
  let count = 0;
  for (let i = startIndex; i < endIndex && i < distances.length; i++) {
    sum += distances[i];
    count += 1;
  }
  if (count === 0) return 0;
  return (sum / count) / maxDistance;
}

export function scaleWaypoint(
  start: Coordinate,
  wp: Coordinate,
  factor: number,
): Coordinate {
  return {
    latitude: start.latitude + (wp.latitude - start.latitude) * factor,
    longitude: start.longitude + (wp.longitude - start.longitude) * factor,
  };
}

export function headingDeltaDegrees(a: number, b: number): number {
  let delta = Math.abs((a - b) % 360);
  if (delta > 180) {
    delta = 360 - delta;
  }
  return delta;
}

export function pointToCoordinate(point: any): Coordinate | null {
  if (!Array.isArray(point) || point.length < 2) return null;
  const longitude = Number(point[0]);
  const latitude = Number(point[1]);
  if (!Number.isFinite(longitude) || !Number.isFinite(latitude)) {
    return null;
  }
  return { latitude, longitude };
}

export function routeHeadingAt(routeCoordinates: any[], index: number): number {
  if (!Array.isArray(routeCoordinates) || routeCoordinates.length < 2) {
    return 0;
  }
  const safeIndex = Math.max(0, Math.min(index, routeCoordinates.length - 2));
  const from = pointToCoordinate(routeCoordinates[safeIndex]);
  const to = pointToCoordinate(routeCoordinates[safeIndex + 1]);
  if (!from || !to) return 0;
  return calculateBearing(from, to);
}

export function measureCoordinatePathMeters(coordinates: Coordinate[]): number {
  let distanceMeters = 0;
  for (let i = 0; i < coordinates.length - 1; i += 1) {
    distanceMeters += calculateDistance(coordinates[i], coordinates[i + 1]) *
      1000;
  }
  return distanceMeters;
}
