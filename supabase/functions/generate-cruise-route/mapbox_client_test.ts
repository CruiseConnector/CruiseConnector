import { assert, assertEquals } from "jsr:@std/assert@1";
import { buildMapboxDirectionsRequestUrl } from "./mapbox_client.ts";
import type { Coordinate } from "./routing_types.ts";

Deno.test("roundtrip shaping points are encoded as silent via coordinates", () => {
  const waypoints: Coordinate[] = [
    { latitude: 47.25, longitude: 9.60 },
    { latitude: 47.28, longitude: 9.55 },
    { latitude: 47.32, longitude: 9.65 },
    { latitude: 47.30, longitude: 9.72 },
    { latitude: 47.25, longitude: 9.60 },
  ];

  const url = buildMapboxDirectionsRequestUrl(
    waypoints,
    "mapbox/driving",
    "motorway",
    "unlimited;4500;4500;4500;unlimited",
    "test-token",
    {
      continueStraight: true,
      alternatives: true,
      bearings: "120,45;;;;",
      includeGuidance: false,
      steps: true,
      overview: "simplified",
      avoidManeuverRadiusMeters: 80,
      routeLegWaypointIndexes: [0, waypoints.length - 1],
    },
  );
  const parsed = new URL(url);

  assert(
    parsed.pathname.endsWith(
      "/mapbox/driving/9.6,47.25;9.55,47.28;9.65,47.32;9.72,47.3;9.6,47.25",
    ),
  );
  assertEquals(parsed.searchParams.get("waypoints"), "0;4");
  assertEquals(
    parsed.searchParams.get("radiuses"),
    "unlimited;4500;4500;4500;unlimited",
  );
  assertEquals(parsed.searchParams.get("bearings"), "120,45;;;;");
  assertEquals(parsed.searchParams.get("exclude"), "motorway");
  assertEquals(parsed.searchParams.get("steps"), "true");
  assertEquals(parsed.searchParams.get("overview"), "simplified");
  assertEquals(parsed.searchParams.get("alternatives"), "true");
  assertEquals(parsed.searchParams.get("continue_straight"), "true");
  assertEquals(parsed.searchParams.get("avoid_maneuver_radius"), "80");
  assertEquals(parsed.searchParams.get("voice_instructions"), null);
  assertEquals(parsed.searchParams.get("banner_instructions"), null);
});

Deno.test("directions request omits waypoint indexes for normal hard-waypoint calls", () => {
  const url = buildMapboxDirectionsRequestUrl(
    [
      { latitude: 47.25, longitude: 9.60 },
      { latitude: 47.30, longitude: 9.70 },
    ],
    "mapbox/driving",
    "",
    "",
    "test-token",
    { includeGuidance: true, overview: "full" },
  );
  const parsed = new URL(url);

  assertEquals(parsed.searchParams.get("waypoints"), null);
  assertEquals(parsed.searchParams.get("steps"), "true");
  assertEquals(parsed.searchParams.get("voice_instructions"), "true");
  assertEquals(parsed.searchParams.get("banner_instructions"), "true");
});
