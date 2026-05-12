import { assertEquals } from "https://deno.land/std@0.210.0/assert/mod.ts";
import { rejectVorarlbergRhineBorderIntrusion } from "./index.ts";

// Origin Feldkirch (47.238, 9.598). Trigger inVorarlbergRhineValley = true.
const feldkirchSession = {
  origin_lat: 47.238,
  origin_lng: 9.598,
  // deno-lint-ignore no-explicit-any
} as unknown as any;

function makeRoute(coordinates: number[][]): unknown {
  return { geometry: { coordinates } };
}

Deno.test(
  "Feldkirch roundtrip with ~5% points in the 9.55-9.60 stripe is NOT rejected",
  () => {
    const coordinates: number[][] = [];
    // 95 Punkte im normalen Rheintal-Korridor (lng 9.60-9.70, lat 47.20-47.40).
    for (let i = 0; i < 95; i += 1) {
      const lng = 9.60 + (i / 95) * 0.10;
      const lat = 47.20 + (i / 95) * 0.20;
      coordinates.push([lng, lat]);
    }
    // 5 Punkte leicht westlich (lng 9.55-9.59), exakt der Streifen den
    // der alte Filter fälschlich als border_intrusion markiert hat.
    for (let i = 0; i < 5; i += 1) {
      const lng = 9.55 + (i / 5) * 0.04;
      const lat = 47.38;
      coordinates.push([lng, lat]);
    }
    const result = rejectVorarlbergRhineBorderIntrusion(
      feldkirchSession,
      makeRoute(coordinates),
    );
    assertEquals(
      result,
      false,
      "Light western touches (lng 9.55-9.60) must not be flagged as foreign.",
    );
  },
);

Deno.test(
  "Feldkirch roundtrip with substantial CH/FL detour IS still rejected",
  () => {
    const coordinates: number[][] = [];
    // 50 Punkte im Standard-Rheintal.
    for (let i = 0; i < 50; i += 1) {
      coordinates.push([
        9.60 + (i / 50) * 0.10,
        47.20 + (i / 50) * 0.20,
      ]);
    }
    // 20 Punkte deutlich westlich (lng 9.40-9.48 = hartes Foreign), zusammen-
    // hängend in lat 47.25 → ergibt > 4 km Foreign-Strecke und überschreitet
    // den Punkt-Schwellenwert.
    for (let i = 0; i < 20; i += 1) {
      const lng = 9.40 + (i / 20) * 0.08;
      const lat = 47.25;
      coordinates.push([lng, lat]);
    }
    const result = rejectVorarlbergRhineBorderIntrusion(
      feldkirchSession,
      makeRoute(coordinates),
    );
    assertEquals(
      result,
      true,
      "Routes spending > 4 km west of the border must still be rejected.",
    );
  },
);

Deno.test(
  "Origin outside Vorarlberg-Rheintal trigger is short-circuited (returns false)",
  () => {
    const munichSession = {
      origin_lat: 48.137,
      origin_lng: 11.575,
      // deno-lint-ignore no-explicit-any
    } as unknown as any;
    const coordinates: number[][] = [];
    // Mit Punkten die wären-foreign — Trigger schaltet trotzdem hart auf false.
    for (let i = 0; i < 20; i += 1) {
      coordinates.push([9.40, 47.25]);
    }
    const result = rejectVorarlbergRhineBorderIntrusion(
      munichSession,
      makeRoute(coordinates),
    );
    assertEquals(result, false);
  },
);
