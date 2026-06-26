import {
  buildRouteFingerprintFromRoute,
  evaluateRouteCleanupGate,
  evaluateRouteQuality,
} from "../generate-cruise-route/route_quality.ts";
import type {
  Coordinate,
  RouteMode,
} from "../generate-cruise-route/routing_types.ts";

type SeedStyle =
  | "Sport Mode"
  | "Kurvenjagd"
  | "Abendrunde"
  | "Entdecker";

type SeedCluster =
  | "Bregenz"
  | "Dornbirn"
  | "Feldkirch"
  | "Bludenz"
  | "Rheintal-Sued";

const allSeedClusters = [
  "Bregenz",
  "Dornbirn",
  "Feldkirch",
  "Bludenz",
  "Rheintal-Sued",
] as const satisfies readonly SeedCluster[];
const allSeedBuckets = [50, 75, 100] as const;
const allSeedStyles = [
  "Sport Mode",
  "Kurvenjagd",
  "Abendrunde",
  "Entdecker",
] as const satisfies readonly SeedStyle[];
const deprecatedSeedFingerprints = new Set<string>([
  "vorarlberg_bregenz-100-kurven-random-8-r2_bf6422f5",
  "vorarlberg_feldkirch-100-sport-rankweil-random-2-r1_284763f0",
]);

interface SeedCandidate {
  key: string;
  title: string;
  cityCluster: SeedCluster;
  admin2Name: string;
  bucket: 50 | 75 | 100;
  targetKm: number;
  styles: SeedStyle[];
  waypoints: Coordinate[];
  avoidHighways: true;
}

interface SeedRouteRow {
  route_fingerprint: string;
  title: string;
  country_code: "AT";
  admin1_name: "Vorarlberg";
  admin2_name: string;
  city_cluster: SeedCluster;
  start_lat: number;
  start_lng: number;
  end_lat: number;
  end_lng: number;
  distance_km: number;
  distance_bucket: 50 | 75 | 100;
  route_type: "ROUND_TRIP";
  style_tags: SeedStyle[];
  avoids_highway: boolean;
  has_highway: boolean;
  quality_score: number;
  shape_score: number;
  source: "mapbox_seed";
  verified: boolean;
  is_active: boolean;
  geometry: {
    type: "LineString";
    coordinates: number[][];
  };
  route_payload: Record<string, unknown>;
}

const outputJson = Deno.args.find((arg) => arg.startsWith("--json="))?.slice(
  "--json=".length,
) ?? "supabase/seed/route_pool_vorarlberg.json";
const outputSql = Deno.args.find((arg) => arg.startsWith("--sql="))?.slice(
  "--sql=".length,
) ?? "supabase/migrations/20260424_route_pool_vorarlberg_seed.sql";
const mergeInputs = Deno.args.find((arg) => arg.startsWith("--merge-json="))
  ?.slice("--merge-json=".length)
  .split(",")
  .map((path) => path.trim())
  .filter((path) => path.length > 0) ?? [];
const includeManualCandidates = !Deno.args.includes("--skip-manual");
const includeRandomCandidates = !Deno.args.includes("--skip-random");
const useLegacyRandomKeys = Deno.args.includes("--legacy-random-keys");
const maxRandomCandidates = Number(
  Deno.args.find((arg) => arg.startsWith("--max-random="))?.slice(
    "--max-random=".length,
  ) ?? "56",
);
const randomOffset = Math.max(
  0,
  Number(
    Deno.args.find((arg) => arg.startsWith("--random-offset="))?.slice(
      "--random-offset=".length,
    ) ?? "0",
  ) || 0,
);
const randomRounds = Math.max(
  1,
  Number(
    Deno.args.find((arg) => arg.startsWith("--random-rounds="))?.slice(
      "--random-rounds=".length,
    ) ?? "1",
  ) || 1,
);
const fetchTimeoutMs = Number(
  Deno.args.find((arg) => arg.startsWith("--timeout-ms="))?.slice(
    "--timeout-ms=".length,
  ) ?? "35000",
);
const concurrency = Math.max(
  1,
  Number(
    Deno.args.find((arg) => arg.startsWith("--concurrency="))?.slice(
      "--concurrency=".length,
    ) ?? "4",
  ) || 4,
);
const targetedRandomMode = Deno.args.some((arg) =>
  arg.startsWith("--random-clusters=") ||
  arg.startsWith("--random-buckets=") ||
  arg.startsWith("--random-styles=") ||
  arg.startsWith("--attempts-per-combo=")
);
const useRandomStartVariants = Deno.args.includes("--random-start-variants");
const randomClusters = parseStringListArg(
  "--random-clusters=",
  allSeedClusters,
) as SeedCluster[];
const randomBuckets = parseNumberListArg("--random-buckets=", allSeedBuckets);
const randomStyles = parseStringListArg(
  "--random-styles=",
  allSeedStyles,
) as SeedStyle[];
const attemptsPerCombination = Math.max(
  1,
  Number(
    Deno.args.find((arg) => arg.startsWith("--attempts-per-combo="))?.slice(
      "--attempts-per-combo=".length,
    ) ?? "8",
  ) || 8,
);
const manualClusters = parseStringListArg(
  "--manual-clusters=",
  allSeedClusters,
) as SeedCluster[];
const manualBuckets = parseNumberListArg("--manual-buckets=", allSeedBuckets);
const manualStyles = parseStringListArg(
  "--manual-styles=",
  allSeedStyles,
) as SeedStyle[];

if (mergeInputs.length > 0) {
  const mergedRoutes = await loadMergedRoutes(mergeInputs);
  await writeSeedOutputs(mergedRoutes, [], {
    source: "mapbox_seed_merged",
    mergeInputs,
  });
  Deno.exit(0);
}

const supabaseAnonKey = loadSupabaseAnonKey();
if (!supabaseAnonKey) {
  throw new Error(
    "SUPABASE_ANON_KEY fehlt. Setze Env oder lib/config/secrets.dart.",
  );
}
const edgeEndpoint = Deno.args.find((arg) => arg.startsWith("--endpoint="))
  ?.slice("--endpoint=".length) ??
  "https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/generate-cruise-route-v2";

const clusters: Record<
  SeedCluster,
  { admin2Name: string; center: Coordinate }
> = {
  Bregenz: {
    admin2Name: "Bregenz",
    center: { latitude: 47.5031, longitude: 9.7471 },
  },
  Dornbirn: {
    admin2Name: "Dornbirn",
    center: { latitude: 47.4125, longitude: 9.7414 },
  },
  Feldkirch: {
    admin2Name: "Feldkirch",
    center: { latitude: 47.2386, longitude: 9.5986 },
  },
  Bludenz: {
    admin2Name: "Bludenz",
    center: { latitude: 47.1548, longitude: 9.822 },
  },
  "Rheintal-Sued": {
    admin2Name: "Rheintal-Sued",
    center: { latitude: 47.3499, longitude: 9.6584 },
  },
};

const p = {
  bregenz: { latitude: 47.5031, longitude: 9.7471 },
  langen: { latitude: 47.5075, longitude: 9.8311 },
  alberschwende: { latitude: 47.4504, longitude: 9.8319 },
  egg: { latitude: 47.431, longitude: 9.895 },
  schwarzenberg: { latitude: 47.414, longitude: 9.852 },
  bezau: { latitude: 47.384, longitude: 9.902 },
  mellau: { latitude: 47.35, longitude: 9.882 },
  au: { latitude: 47.322, longitude: 9.98 },
  damuels: { latitude: 47.28, longitude: 9.884 },
  laterns: { latitude: 47.279, longitude: 9.77 },
  dornbirn: { latitude: 47.4125, longitude: 9.7414 },
  hohenems: { latitude: 47.3667, longitude: 9.6831 },
  goetzis: { latitude: 47.3331, longitude: 9.6336 },
  rankweil: { latitude: 47.2714, longitude: 9.6436 },
  lustenau: { latitude: 47.4264, longitude: 9.6585 },
  feldkirch: { latitude: 47.2386, longitude: 9.5986 },
  frastanz: { latitude: 47.217, longitude: 9.629 },
  nenzing: { latitude: 47.184, longitude: 9.705 },
  bludenz: { latitude: 47.1548, longitude: 9.822 },
  buers: { latitude: 47.149, longitude: 9.803 },
  brand: { latitude: 47.103, longitude: 9.739 },
  schruns: { latitude: 47.0801, longitude: 9.9197 },
  vandans: { latitude: 47.094, longitude: 9.865 },
};

const candidates: SeedCandidate[] = [
  c("bregenz-50-sport-1", "Bregenz Pfänderwald 50", "Bregenz", 50, [
    "Sport Mode",
    "Abendrunde",
  ], [p.bregenz, p.langen, p.alberschwende, p.dornbirn, p.lustenau, p.bregenz]),
  c("bregenz-50-kurven-1", "Bregenz Bregenzerwald 50", "Bregenz", 50, [
    "Kurvenjagd",
    "Entdecker",
  ], [p.bregenz, p.langen, p.alberschwende, p.schwarzenberg, p.bregenz]),
  c("bregenz-75-sport-1", "Bregenz Rheintal 75", "Bregenz", 75, [
    "Sport Mode",
  ], [
    p.bregenz,
    p.lustenau,
    p.hohenems,
    p.goetzis,
    p.alberschwende,
    p.bregenz,
  ]),
  c("bregenz-75-kurven-1", "Bregenz Waldschleife 75", "Bregenz", 75, [
    "Kurvenjagd",
    "Entdecker",
  ], [p.bregenz, p.langen, p.egg, p.schwarzenberg, p.dornbirn, p.bregenz]),
  c("bregenz-100-sport-1", "Bregenz Vorarlberg West 100", "Bregenz", 100, [
    "Sport Mode",
  ], [p.bregenz, p.lustenau, p.feldkirch, p.nenzing, p.dornbirn, p.bregenz]),
  c("bregenz-100-kurven-1", "Bregenz Bregenzerwald 100", "Bregenz", 100, [
    "Kurvenjagd",
    "Entdecker",
  ], [
    p.bregenz,
    p.langen,
    p.egg,
    p.bezau,
    p.mellau,
    p.damuels,
    p.dornbirn,
    p.bregenz,
  ]),

  c("dornbirn-50-sport-1", "Dornbirn Rheintal 50", "Dornbirn", 50, [
    "Sport Mode",
    "Abendrunde",
  ], [p.dornbirn, p.hohenems, p.goetzis, p.rankweil, p.dornbirn]),
  c("dornbirn-50-kurven-1", "Dornbirn Bödele 50", "Dornbirn", 50, [
    "Kurvenjagd",
    "Entdecker",
  ], [p.dornbirn, p.schwarzenberg, p.egg, p.alberschwende, p.dornbirn]),
  c("dornbirn-75-sport-1", "Dornbirn Rheintal Nord 75", "Dornbirn", 75, [
    "Sport Mode",
  ], [p.dornbirn, p.bregenz, p.lustenau, p.goetzis, p.rankweil, p.dornbirn]),
  c("dornbirn-75-kurven-1", "Dornbirn Bregenzerwald 75", "Dornbirn", 75, [
    "Kurvenjagd",
  ], [
    p.dornbirn,
    p.schwarzenberg,
    p.bezau,
    p.mellau,
    p.damuels,
    p.laterns,
    p.dornbirn,
  ]),
  c("dornbirn-100-sport-1", "Dornbirn Vorarlberg Mitte 100", "Dornbirn", 100, [
    "Sport Mode",
  ], [p.dornbirn, p.bregenz, p.lustenau, p.feldkirch, p.nenzing, p.dornbirn]),
  c("dornbirn-100-kurven-1", "Dornbirn Wald und Walgau 100", "Dornbirn", 100, [
    "Kurvenjagd",
    "Entdecker",
  ], [
    p.dornbirn,
    p.alberschwende,
    p.egg,
    p.bezau,
    p.mellau,
    p.damuels,
    p.laterns,
    p.rankweil,
    p.dornbirn,
  ]),

  c("feldkirch-50-sport-1", "Feldkirch Walgau 50", "Feldkirch", 50, [
    "Sport Mode",
    "Abendrunde",
  ], [p.feldkirch, p.rankweil, p.laterns, p.frastanz, p.feldkirch]),
  c("feldkirch-50-kurven-1", "Feldkirch Laterns 50", "Feldkirch", 50, [
    "Kurvenjagd",
  ], [p.feldkirch, p.laterns, p.rankweil, p.nenzing, p.frastanz, p.feldkirch]),
  c("feldkirch-75-sport-1", "Feldkirch Rheintal 75", "Feldkirch", 75, [
    "Sport Mode",
  ], [p.feldkirch, p.rankweil, p.hohenems, p.lustenau, p.goetzis, p.feldkirch]),
  c("feldkirch-75-kurven-1", "Feldkirch Walgau Kurven 75", "Feldkirch", 75, [
    "Kurvenjagd",
    "Entdecker",
  ], [p.feldkirch, p.laterns, p.damuels, p.nenzing, p.frastanz, p.feldkirch]),
  c("feldkirch-100-sport-1", "Feldkirch Vorarlberg 100", "Feldkirch", 100, [
    "Sport Mode",
  ], [p.feldkirch, p.dornbirn, p.bregenz, p.lustenau, p.nenzing, p.feldkirch]),
  c("feldkirch-100-kurven-1", "Feldkirch Alpenrand 100", "Feldkirch", 100, [
    "Kurvenjagd",
  ], [
    p.feldkirch,
    p.laterns,
    p.damuels,
    p.mellau,
    p.bezau,
    p.dornbirn,
    p.rankweil,
    p.feldkirch,
  ]),

  c(
    "rheintal-sued-50-sport-1",
    "Rheintal-Sued Rheinschleife 50",
    "Rheintal-Sued",
    50,
    ["Sport Mode"],
    [p.goetzis, p.hohenems, p.lustenau, p.dornbirn, p.goetzis],
  ),
  c(
    "rheintal-sued-50-sport-2",
    "Rheintal-Sued Laternsrunde 50",
    "Rheintal-Sued",
    50,
    ["Sport Mode"],
    [p.hohenems, p.goetzis, p.rankweil, p.laterns, p.hohenems],
  ),
  c(
    "rheintal-sued-50-sport-3",
    "Rheintal-Sued Walgaukante 50",
    "Rheintal-Sued",
    50,
    ["Sport Mode"],
    [p.goetzis, p.rankweil, p.frastanz, p.laterns, p.hohenems, p.goetzis],
  ),
  c(
    "rheintal-sued-50-kurven-1",
    "Rheintal-Sued Hanglinie 50",
    "Rheintal-Sued",
    50,
    ["Kurvenjagd"],
    [p.hohenems, p.goetzis, p.laterns, p.rankweil, p.hohenems],
  ),

  c("bludenz-50-sport-1", "Bludenz Brandnertal 50", "Bludenz", 50, [
    "Sport Mode",
    "Entdecker",
  ], [p.bludenz, p.buers, p.brand, p.nenzing, p.bludenz]),
  c("bludenz-50-kurven-1", "Bludenz Montafon 50", "Bludenz", 50, [
    "Kurvenjagd",
    "Abendrunde",
  ], [p.bludenz, p.vandans, p.schruns, p.nenzing, p.bludenz]),
  c("bludenz-75-sport-1", "Bludenz Walgau 75", "Bludenz", 75, [
    "Sport Mode",
  ], [p.bludenz, p.nenzing, p.feldkirch, p.rankweil, p.frastanz, p.bludenz]),
  c("bludenz-75-kurven-1", "Bludenz Brandnertal 75", "Bludenz", 75, [
    "Kurvenjagd",
    "Entdecker",
  ], [p.bludenz, p.brand, p.nenzing, p.laterns, p.rankweil, p.bludenz]),
  c("bludenz-100-sport-1", "Bludenz Rheintal 100", "Bludenz", 100, [
    "Sport Mode",
  ], [p.bludenz, p.feldkirch, p.dornbirn, p.lustenau, p.nenzing, p.bludenz]),
  c("bludenz-100-kurven-1", "Bludenz Alpenloop 100", "Bludenz", 100, [
    "Kurvenjagd",
  ], [
    p.bludenz,
    p.brand,
    p.laterns,
    p.damuels,
    p.mellau,
    p.nenzing,
    p.bludenz,
  ]),
];

const accepted: SeedRouteRow[] = [];
const rejected: Array<{ key: string; reason: string; distanceKm?: number }> =
  [];
const seenFingerprints = new Set<string>();

if (includeManualCandidates) {
  await processCandidates(
    filteredManualCandidates(),
    fetchEdgeRoute,
    Math.min(2, concurrency),
  );
}

if (includeRandomCandidates) {
  await processCandidates(
    randomEdgeCandidates(),
    fetchRandomEdgeRoute,
    concurrency,
  );
}

async function processCandidates(
  queue: SeedCandidate[],
  fetcher: (
    candidate: SeedCandidate,
  ) => Promise<{ ok: true; route: any } | { ok: false; reason: string }>,
  workerCount: number,
): Promise<void> {
  let index = 0;
  const total = queue.length;

  async function worker(): Promise<void> {
    while (index < total) {
      const candidate = queue[index];
      index += 1;
      const result = await fetcher(candidate);
      if (!result.ok) {
        rejected.push({ key: candidate.key, reason: result.reason });
      } else {
        acceptRoute(candidate, result.route);
      }

      const done = accepted.length + rejected.length;
      if (done % 10 === 0 || done === total) {
        console.error(
          JSON.stringify({
            progress: `${done}/${total}`,
            accepted: accepted.length,
            rejected: rejected.length,
          }),
        );
      }
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(workerCount, total) }, () => worker()),
  );
}

function acceptRoute(candidate: SeedCandidate, route: any): void {
  const distanceKm = route.distance / 1000;
  if (!distanceInBucket(distanceKm, candidate.bucket)) {
    rejected.push({
      key: candidate.key,
      reason: "distance_outside_bucket",
      distanceKm,
    });
    return;
  }

  const startDistanceKm = haversineKm(
    candidate.waypoints[0],
    clusters[candidate.cityCluster].center,
  );
  if (startDistanceKm > 12) {
    rejected.push({
      key: candidate.key,
      reason: "start_too_far_from_cluster",
      distanceKm,
    });
    return;
  }

  const quality = evaluateRouteQuality(route, "ROUND_TRIP", {
    targetDistanceKm: candidate.targetKm,
    mode: candidate.styles.includes("Kurvenjagd")
      ? "Kurvenjagd"
      : candidate.styles[0] as RouteMode,
    avoidHighways: true,
  });
  const cleanup = evaluateRouteCleanupGate(route, "ROUND_TRIP", {
    targetDistanceKm: candidate.targetKm,
    mode: candidate.styles.includes("Kurvenjagd")
      ? "Kurvenjagd"
      : candidate.styles[0] as RouteMode,
    avoidHighways: true,
    startLocation: candidate.waypoints[0],
  });
  if (
    quality.tier === "rejected" ||
    quality.hasUTurn ||
    !cleanup.passed
  ) {
    rejected.push({
      key: candidate.key,
      reason:
        `quality_${quality.tier}_${quality.reason}_cleanup_${cleanup.reason}`,
      distanceKm,
    });
    return;
  }

  const fingerprint = buildRouteFingerprintFromRoute(route);
  if (seenFingerprints.has(fingerprint)) {
    rejected.push({ key: candidate.key, reason: "duplicate_fingerprint" });
    return;
  }
  seenFingerprints.add(fingerprint);

  const first = route.geometry.coordinates[0] as number[];
  const last = route.geometry
    .coordinates[route.geometry.coordinates.length - 1] as number[];
  accepted.push({
    route_fingerprint: `vorarlberg_${candidate.key}_${hashString(fingerprint)}`,
    title: candidate.title,
    country_code: "AT",
    admin1_name: "Vorarlberg",
    admin2_name: clusters[candidate.cityCluster].admin2Name,
    city_cluster: candidate.cityCluster,
    start_lat: first[1],
    start_lng: first[0],
    end_lat: last[1],
    end_lng: last[0],
    distance_km: round(distanceKm, 2),
    distance_bucket: candidate.bucket,
    route_type: "ROUND_TRIP",
    style_tags: candidate.styles,
    avoids_highway: true,
    has_highway: false,
    quality_score: qualityScore(quality.tier),
    shape_score: Math.max(0, Math.min(100, 100 - quality.score)),
    source: "mapbox_seed",
    verified: true,
    is_active: true,
    geometry: {
      type: "LineString",
      coordinates: route.geometry.coordinates,
    },
    route_payload: {
      provider: "mapbox",
      seed_key: candidate.key,
      target_distance_km: candidate.targetKm,
      quality_tier: quality.tier,
      quality_reason: quality.reason,
      cleanup_reason: cleanup.reason,
      duration_seconds: route.duration,
      effective_excludes: "motorway",
      generated_at: new Date().toISOString(),
    },
  });
}

await writeSeedOutputs(accepted, rejected, { source: "mapbox_seed" });

console.log(
  JSON.stringify(
    {
      accepted: accepted.length,
      rejected: rejected.length,
      byCluster: countBy(accepted, (route) => route.city_cluster),
      byBucket: countBy(accepted, (route) => String(route.distance_bucket)),
      byStyle: countStyles(accepted),
      rejectedReasons: countBy(rejected, (entry) => entry.reason),
      outputJson,
      outputSql,
    },
    null,
    2,
  ),
);

function c(
  key: string,
  title: string,
  cityCluster: SeedCluster,
  bucket: 50 | 75 | 100,
  styles: SeedStyle[],
  waypoints: Coordinate[],
): SeedCandidate {
  return {
    key,
    title,
    cityCluster,
    admin2Name: clusters[cityCluster].admin2Name,
    bucket,
    targetKm: bucket,
    styles,
    waypoints,
    avoidHighways: true,
  };
}

function filteredManualCandidates(): SeedCandidate[] {
  const allowedClusters = new Set<SeedCluster>(manualClusters);
  const allowedBuckets = new Set<number>(manualBuckets);
  const allowedStyles = new Set<SeedStyle>(manualStyles);
  return candidates.filter((candidate) =>
    allowedClusters.has(candidate.cityCluster) &&
    allowedBuckets.has(candidate.bucket) &&
    candidate.styles.some((style) => allowedStyles.has(style))
  );
}

async function loadMergedRoutes(paths: string[]): Promise<SeedRouteRow[]> {
  const byFingerprint = new Map<string, SeedRouteRow>();
  for (const path of paths) {
    const raw = JSON.parse(await Deno.readTextFile(path)) as {
      routes?: SeedRouteRow[];
    };
    for (const route of raw.routes ?? []) {
      if (!route.route_fingerprint) continue;
      if (deprecatedSeedFingerprints.has(route.route_fingerprint)) continue;
      if (route.verified !== true || route.is_active === false) continue;
      const normalizedRoute = {
        ...route,
        verified: true as const,
        is_active: true as const,
      };
      if (!revalidateMergedRoute(normalizedRoute)) continue;
      byFingerprint.set(route.route_fingerprint, normalizedRoute);
    }
  }
  return [...byFingerprint.values()].sort((left, right) =>
    left.route_fingerprint.localeCompare(right.route_fingerprint)
  );
}

async function writeSeedOutputs(
  routes: SeedRouteRow[],
  rejectedRoutes: Array<{ key: string; reason: string; distanceKm?: number }>,
  extra: Record<string, unknown>,
): Promise<void> {
  const filteredRoutes = routes.filter((route) =>
    !deprecatedSeedFingerprints.has(route.route_fingerprint)
  );
  await Deno.writeTextFile(
    outputJson,
    `${
      JSON.stringify(
        {
          generated_at: new Date().toISOString(),
          ...extra,
          routes: filteredRoutes,
          rejected: rejectedRoutes,
        },
        null,
        2,
      )
    }\n`,
  );

  await Deno.writeTextFile(outputSql, buildSeedSql(filteredRoutes));
}

function randomEdgeCandidates(): SeedCandidate[] {
  const result: SeedCandidate[] = [];

  const add = (
    cluster: SeedCluster,
    bucket: 50 | 75 | 100,
    style: SeedStyle,
    attempts: number,
  ) => {
    const starts = targetedRandomMode && useRandomStartVariants
      ? localStartVariants(cluster)
      : [{ suffix: "", coordinate: clusters[cluster].center }];
    const styleKey = style === "Sport Mode"
      ? "sport"
      : style === "Kurvenjagd"
      ? "kurven"
      : style === "Abendrunde"
      ? "abend"
      : "entdecker";
    for (let attempt = 0; attempt < attempts; attempt += 1) {
      for (let roundIndex = 0; roundIndex < randomRounds; roundIndex += 1) {
        for (const start of starts) {
          const startSuffix = start.suffix ? `-${start.suffix}` : "";
          const keySuffix = useLegacyRandomKeys && randomRounds === 1
            ? `${cluster.toLowerCase()}-${bucket}-${styleKey}${startSuffix}-random-${
              attempt + 1
            }`
            : `${cluster.toLowerCase()}-${bucket}-${styleKey}${startSuffix}-random-${
              attempt + 1
            }-r${roundIndex + 1}`;
          result.push({
            key: keySuffix,
            title: `${cluster} ${bucket} ${style} Seed ${attempt + 1}.${
              roundIndex + 1
            }${start.suffix ? ` ${start.suffix}` : ""}`,
            cityCluster: cluster,
            admin2Name: clusters[cluster].admin2Name,
            bucket,
            targetKm: bucket,
            styles: [style],
            waypoints: [start.coordinate],
            avoidHighways: true,
          });
        }
      }
    }
  };

  if (targetedRandomMode) {
    for (const cluster of randomClusters) {
      for (const bucket of randomBuckets) {
        for (const style of randomStyles) {
          add(cluster, bucket, style, attemptsPerCombination);
        }
      }
    }
    if (!Number.isFinite(maxRandomCandidates) || maxRandomCandidates < 0) {
      return result.slice(randomOffset);
    }
    return result.slice(randomOffset, randomOffset + maxRandomCandidates);
  }

  for (const bucket of [50, 75, 100] as const) {
    add("Dornbirn", bucket, "Sport Mode", 5);
    add("Dornbirn", bucket, "Kurvenjagd", 5);
  }
  for (const cluster of ["Bregenz", "Feldkirch", "Bludenz"] as const) {
    add(cluster, 50, "Sport Mode", 3);
    add(cluster, 50, "Kurvenjagd", 3);
  }
  for (const cluster of Object.keys(clusters) as SeedCluster[]) {
    add(cluster, 50, "Abendrunde", 1);
    add(cluster, 50, "Entdecker", 1);
  }
  if (!Number.isFinite(maxRandomCandidates) || maxRandomCandidates < 0) {
    return result.slice(randomOffset);
  }
  return result.slice(randomOffset, randomOffset + maxRandomCandidates);
}

async function fetchEdgeRoute(
  candidate: SeedCandidate,
): Promise<{ ok: true; route: any } | { ok: false; reason: string }> {
  const body = {
    request_id: `route_pool_seed_${candidate.key}`,
    route_type: "ROUND_TRIP",
    planning_type: "Wegpunkte",
    startLocation: candidate.waypoints[0],
    manual_waypoints: candidate.waypoints,
    targetDistance: candidate.targetKm,
    mode: candidate.styles.includes("Kurvenjagd")
      ? "Kurvenjagd"
      : candidate.styles[0],
    avoid_highways: true,
    continue_straight: true,
    style_profile: candidate.styles.includes("Kurvenjagd")
      ? "kurvenjagd"
      : "sport",
  };
  const response = await fetchWithTimeout(edgeEndpoint, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json",
      apikey: supabaseAnonKey,
      authorization: `Bearer ${supabaseAnonKey}`,
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    let code = `http_${response.status}`;
    try {
      const error = await response.json();
      code = error?.code ?? code;
    } catch {
      // Keep HTTP status reason.
    }
    return { ok: false, reason: code };
  }
  const data = await response.json();
  const route = data?.route;
  if (!route?.geometry?.coordinates?.length) {
    return { ok: false, reason: data?.code ?? "no_route" };
  }
  return { ok: true, route };
}

async function fetchRandomEdgeRoute(
  candidate: SeedCandidate,
): Promise<{ ok: true; route: any } | { ok: false; reason: string }> {
  const style = candidate.styles[0];
  const styleProfile = style === "Kurvenjagd"
    ? "kurvenjagd"
    : style === "Sport Mode"
    ? "sport"
    : style === "Abendrunde"
    ? "evening"
    : "explorer";
  const seed = hashString(candidate.key);
  const directionHint = parseInt(seed.slice(0, 4), 16) % 360;
  const distanceJitter = candidate.bucket === 50
    ? [46, 50, 54]
    : candidate.bucket === 75
    ? [68, 75, 82, 72]
    : [90, 100, 108, 96];
  const attemptIndex = Math.max(
    0,
    (parseInt(candidate.key.match(/random-(\d+)/)?.[1] ?? "1", 10) || 1) - 1,
  );
  const targetDistance = distanceJitter[attemptIndex % distanceJitter.length] ??
    candidate.bucket;
  const body = {
    request_id: `route_pool_seed_${candidate.key}`,
    route_type: "ROUND_TRIP",
    planning_type: "Zufall",
    startLocation: candidate.waypoints[0],
    targetDistance,
    mode: style,
    randomSeed: parseInt(seed.slice(0, 8), 16),
    avoid_highways: true,
    continue_straight: true,
    direction_hint: directionHint,
    route_variant_hint: `pool-seed-${candidate.key}`,
    route_fingerprint_hint: `pool-seed-${candidate.key}-${seed}`,
    max_candidate_attempts: candidate.bucket === 50 ? 6 : 8,
    style_profile: styleProfile,
    waypoint_shape_factor: style === "Kurvenjagd" ? 0.95 : 2.05,
    radius_multiplier: style === "Kurvenjagd" ? 1.18 : 1.02,
    zigzag_waypoints: style === "Kurvenjagd" || style === "Entdecker",
  };
  const response = await fetchWithTimeout(edgeEndpoint, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json",
      apikey: supabaseAnonKey,
      authorization: `Bearer ${supabaseAnonKey}`,
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    let code = `http_${response.status}`;
    try {
      const error = await response.json();
      code = error?.code ?? code;
    } catch {
      // Keep HTTP status reason.
    }
    return { ok: false, reason: code };
  }
  const data = await response.json();
  const route = data?.route;
  if (!route?.geometry?.coordinates?.length) {
    return { ok: false, reason: data?.code ?? "no_route" };
  }
  return { ok: true, route };
}

async function fetchWithTimeout(
  input: string,
  init: RequestInit,
): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), fetchTimeoutMs);
  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      return new Response(
        JSON.stringify({ code: "request_timeout" }),
        { status: 504, headers: { "content-type": "application/json" } },
      );
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

function loadSupabaseAnonKey(): string {
  const fromEnv = Deno.env.get("SUPABASE_ANON_KEY");
  if (fromEnv?.trim()) return fromEnv.trim();

  for (const path of [".env"]) {
    try {
      const content = Deno.readTextFileSync(path);
      for (const line of content.split(/\r?\n/)) {
        const match = line.match(/^\s*SUPABASE_ANON_KEY\s*=\s*(.+?)\s*$/);
        if (match) {
          return match[1].replace(/^['"]|['"]$/g, "").trim();
        }
      }
    } catch {
      // Optional local file.
    }
  }

  try {
    const content = Deno.readTextFileSync("lib/config/secrets.dart");
    const match = content.match(
      /supabaseAnonKey\s*=\s*['"]([^'"]+)['"]/,
    );
    if (match?.[1]?.trim()) return match[1].trim();
  } catch {
    // Optional gitignored local file.
  }
  return "";
}

function distanceInBucket(distanceKm: number, bucket: 50 | 75 | 100): boolean {
  if (bucket === 50) return distanceKm >= 40 && distanceKm <= 60;
  if (bucket === 75) return distanceKm >= 60 && distanceKm <= 90;
  return distanceKm >= 80 && distanceKm <= 120;
}

function qualityScore(tier: string): number {
  if (tier === "ideal") return 96;
  if (tier === "good") return 88;
  return 78;
}

function buildSeedSql(routes: SeedRouteRow[]): string {
  const header = `-- Verified Vorarlberg MVP route-pool seed.
-- Generated from Mapbox Directions with exclude=motorway.
-- Idempotent: route_fingerprint is the stable upsert key.

ALTER TABLE public.route_pool
  ADD COLUMN IF NOT EXISTS route_fingerprint text,
  ADD COLUMN IF NOT EXISTS weekly_rotation_score double precision NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_suggested_at timestamptz,
  ADD COLUMN IF NOT EXISTS rating_count integer NOT NULL DEFAULT 0 CHECK (rating_count >= 0),
  ADD COLUMN IF NOT EXISTS average_rating double precision CHECK (average_rating IS NULL OR (average_rating >= 0 AND average_rating <= 5)),
  ADD COLUMN IF NOT EXISTS completion_rate double precision CHECK (completion_rate IS NULL OR (completion_rate >= 0 AND completion_rate <= 1)),
  ADD COLUMN IF NOT EXISTS deprecated_at timestamptz,
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;

DROP INDEX IF EXISTS public.idx_route_pool_fingerprint;
CREATE UNIQUE INDEX IF NOT EXISTS idx_route_pool_fingerprint
  ON public.route_pool (route_fingerprint);

CREATE INDEX IF NOT EXISTS idx_route_pool_active_verified_bounds
  ON public.route_pool (
    route_type,
    distance_bucket,
    country_code,
    admin1_name,
    start_lat,
    start_lng
  )
  WHERE verified = true AND is_active = true;
`;
  if (routes.length === 0) {
    return `${header}
-- No verified routes were generated. Do not treat this seed as pool coverage.
`;
  }

  const values = routes.map((route) =>
    `(${
      [
        sql(route.route_fingerprint),
        sql(route.title),
        sql(route.country_code),
        sql(route.admin1_name),
        sql(route.admin2_name),
        sql(route.city_cluster),
        route.start_lat,
        route.start_lng,
        route.end_lat,
        route.end_lng,
        route.distance_km,
        route.distance_bucket,
        sql(route.route_type),
        `ARRAY[${route.style_tags.map((tag) => sql(tag)).join(", ")}]::text[]`,
        route.avoids_highway,
        route.has_highway,
        route.quality_score,
        route.shape_score,
        sql(route.source),
        route.verified,
        route.is_active,
        sql(JSON.stringify(route.geometry)) + "::jsonb",
        sql(JSON.stringify(route.route_payload)) + "::jsonb",
      ].join(", ")
    })`
  ).join(",\n");

  return `${header}
INSERT INTO public.route_pool (
  route_fingerprint,
  title,
  country_code,
  admin1_name,
  admin2_name,
  city_cluster,
  start_lat,
  start_lng,
  end_lat,
  end_lng,
  distance_km,
  distance_bucket,
  route_type,
  style_tags,
  avoids_highway,
  has_highway,
  quality_score,
  shape_score,
  source,
  verified,
  is_active,
  geometry,
  route_payload
) VALUES
${values}
ON CONFLICT (route_fingerprint) DO UPDATE SET
  title = EXCLUDED.title,
  country_code = EXCLUDED.country_code,
  admin1_name = EXCLUDED.admin1_name,
  admin2_name = EXCLUDED.admin2_name,
  city_cluster = EXCLUDED.city_cluster,
  start_lat = EXCLUDED.start_lat,
  start_lng = EXCLUDED.start_lng,
  end_lat = EXCLUDED.end_lat,
  end_lng = EXCLUDED.end_lng,
  distance_km = EXCLUDED.distance_km,
  distance_bucket = EXCLUDED.distance_bucket,
  route_type = EXCLUDED.route_type,
  style_tags = EXCLUDED.style_tags,
  avoids_highway = EXCLUDED.avoids_highway,
  has_highway = EXCLUDED.has_highway,
  quality_score = EXCLUDED.quality_score,
  shape_score = EXCLUDED.shape_score,
  source = EXCLUDED.source,
  verified = EXCLUDED.verified,
  is_active = EXCLUDED.is_active,
  geometry = EXCLUDED.geometry,
  route_payload = EXCLUDED.route_payload,
  is_active = true,
  deprecated_at = NULL,
  updated_at = now();

${buildDeprecatedSeedSql()}
`;
}

function buildDeprecatedSeedSql(): string {
  if (deprecatedSeedFingerprints.size == 0) return "";
  const values = [...deprecatedSeedFingerprints].map((value) => sql(value))
    .join(
      ",\n  ",
    );
  return `UPDATE public.route_pool
SET
  verified = false,
  is_active = false,
  deprecated_at = COALESCE(deprecated_at, now()),
  updated_at = now()
WHERE route_fingerprint IN (
  ${values}
);`;
}

function revalidateMergedRoute(route: SeedRouteRow): boolean {
  if (!distanceInBucket(route.distance_km, route.distance_bucket)) return false;
  if (
    route.geometry.type !== "LineString" ||
    route.geometry.coordinates.length < 20
  ) {
    return false;
  }
  const style = route.style_tags.includes("Kurvenjagd")
    ? "Kurvenjagd"
    : (route.style_tags[0] ?? "Sport Mode") as RouteMode;
  const targetDistanceKm = Number(route.route_payload?.target_distance_km) ||
    route.distance_bucket;
  const startLocation = {
    latitude: route.start_lat,
    longitude: route.start_lng,
  } satisfies Coordinate;
  const routeLike = {
    geometry: route.geometry,
    distance: route.distance_km * 1000,
    duration: Number(route.route_payload?.duration_seconds) || 0,
  };
  const quality = evaluateRouteQuality(routeLike, "ROUND_TRIP", {
    targetDistanceKm,
    mode: style,
    avoidHighways: route.avoids_highway,
  });
  const cleanup = evaluateRouteCleanupGate(routeLike, "ROUND_TRIP", {
    targetDistanceKm,
    mode: style,
    avoidHighways: route.avoids_highway,
    startLocation,
  });
  return quality.tier !== "rejected" && !quality.hasUTurn && cleanup.passed;
}

function sql(value: string | null): string {
  if (value === null) return "NULL";
  return `'${value.replaceAll("'", "''")}'`;
}

function countBy<T>(
  items: T[],
  key: (item: T) => string,
): Record<string, number> {
  const result: Record<string, number> = {};
  for (const item of items) {
    const value = key(item);
    result[value] = (result[value] ?? 0) + 1;
  }
  return result;
}

function countStyles(routes: SeedRouteRow[]): Record<string, number> {
  const result: Record<string, number> = {};
  for (const route of routes) {
    for (const style of route.style_tags) {
      result[style] = (result[style] ?? 0) + 1;
    }
  }
  return result;
}

function parseStringListArg<T extends string>(
  prefix: string,
  allowedValues: readonly T[],
): T[] {
  const raw = Deno.args.find((arg) => arg.startsWith(prefix))?.slice(
    prefix.length,
  );
  if (!raw?.trim()) return [...allowedValues];
  const allowed = new Set<string>(allowedValues);
  const parsed = raw.split(",")
    .map((value) => value.trim())
    .filter((value): value is T => allowed.has(value));
  return parsed.length > 0 ? parsed : [...allowedValues];
}

function parseNumberListArg<T extends number>(
  prefix: string,
  allowedValues: readonly T[],
): T[] {
  const raw = Deno.args.find((arg) => arg.startsWith(prefix))?.slice(
    prefix.length,
  );
  if (!raw?.trim()) return [...allowedValues];
  const allowed = new Set<number>(allowedValues);
  const parsed = raw.split(",")
    .map((value) => Number(value.trim()))
    .filter((value): value is T => allowed.has(value));
  return parsed.length > 0 ? parsed : [...allowedValues];
}

function localStartVariants(
  cluster: SeedCluster,
): Array<{ suffix: string; coordinate: Coordinate }> {
  if (cluster === "Bludenz") {
    return [
      { suffix: "", coordinate: clusters.Bludenz.center },
      { suffix: "buers", coordinate: p.buers },
      { suffix: "vandans", coordinate: p.vandans },
      { suffix: "nenzing", coordinate: p.nenzing },
      { suffix: "brand", coordinate: p.brand },
      { suffix: "schruns", coordinate: p.schruns },
    ];
  }
  if (cluster === "Feldkirch") {
    return [
      { suffix: "", coordinate: clusters.Feldkirch.center },
      { suffix: "frastanz", coordinate: p.frastanz },
      { suffix: "rankweil", coordinate: p.rankweil },
      { suffix: "goetzis", coordinate: p.goetzis },
    ];
  }
  if (cluster === "Bregenz") {
    return [
      { suffix: "", coordinate: clusters.Bregenz.center },
      { suffix: "langen", coordinate: p.langen },
    ];
  }
  if (cluster === "Rheintal-Sued") {
    return [
      { suffix: "", coordinate: clusters["Rheintal-Sued"].center },
      { suffix: "goetzis", coordinate: p.goetzis },
      { suffix: "hohenems", coordinate: p.hohenems },
    ];
  }
  return [
    { suffix: "", coordinate: clusters.Dornbirn.center },
    { suffix: "hohenems", coordinate: p.hohenems },
    { suffix: "goetzis", coordinate: p.goetzis },
  ];
}

function haversineKm(left: Coordinate, right: Coordinate): number {
  const earthRadiusKm = 6371;
  const dLat = toRad(right.latitude - left.latitude);
  const dLng = toRad(right.longitude - left.longitude);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(left.latitude)) *
      Math.cos(toRad(right.latitude)) *
      Math.sin(dLng / 2) ** 2;
  return earthRadiusKm * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function toRad(value: number): number {
  return value * Math.PI / 180;
}

function hashString(value: string): string {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

function round(value: number, digits: number): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}
