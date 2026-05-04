import {
  assertEquals,
  assertGreater,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  cellKey,
  CurationCandidate,
  CurationPoolRoute,
  deriveCoverageStatus,
  shouldDemoteVerifiedRoute,
  shouldPromoteCandidate,
  summarizeRatings,
  weeklyRotationScore,
} from "./curation_logic.ts";

const baseCandidate: CurationCandidate = {
  id: "candidate-1",
  routeFingerprint: "candidate-good",
  countryCode: "AT",
  admin1Name: "Vorarlberg",
  admin2Name: "Dornbirn",
  cityCluster: "Dornbirn",
  routeType: "ROUND_TRIP",
  distanceBucket: 50,
  styleKey: "sport",
  avoidHighways: true,
  hasHighway: false,
  qualityScore: 88,
  shapeScore: 8,
  repeatedSuccessCount: 2,
  isCandidate: true,
  isVerifiedPool: false,
  routePayload: { quality_tier: "good" },
};

const basePoolRoute: CurationPoolRoute = {
  id: "pool-1",
  routeFingerprint: "pool-weak",
  countryCode: "AT",
  admin1Name: "Vorarlberg",
  admin2Name: "Dornbirn",
  cityCluster: "Dornbirn",
  routeType: "ROUND_TRIP",
  distanceBucket: 50,
  styleKey: "sport",
  avoidHighways: true,
  hasHighway: false,
  qualityScore: 82,
  verified: true,
  isActive: true,
  routePayload: { quality_tier: "good" },
};

Deno.test("Candidate wird promoted, wenn Feedback und Gates passen", () => {
  const ratings = summarizeRatings([
    { routeFingerprint: "candidate-good", rating: 5, completionPercent: 91 },
    { routeFingerprint: "candidate-good", rating: 4, completionPercent: 84 },
  ]);

  const decision = shouldPromoteCandidate(baseCandidate, ratings, {
    activeVerifiedCount: 2,
    maxPoolSize: 20,
    existingPoolFingerprints: new Set(),
  });

  assertEquals(decision.accepted, true);
  assertEquals(decision.reason, "promote_candidate");
});

Deno.test("Schlechte Route mit negativen Tags wird nicht promoted", () => {
  const ratings = summarizeRatings([
    {
      routeFingerprint: "candidate-good",
      rating: 5,
      completionPercent: 95,
      tags: ["Sackgasse"],
    },
    { routeFingerprint: "candidate-good", rating: 5, completionPercent: 90 },
  ]);

  const decision = shouldPromoteCandidate(baseCandidate, ratings, {
    activeVerifiedCount: 2,
    maxPoolSize: 20,
    existingPoolFingerprints: new Set(),
  });

  assertEquals(decision.accepted, false);
  assertEquals(decision.reason, "negative_tags");
});

Deno.test("Max pool size bleibt pro Zelle erhalten", () => {
  const ratings = summarizeRatings([
    { routeFingerprint: "candidate-good", rating: 5, completionPercent: 91 },
    { routeFingerprint: "candidate-good", rating: 5, completionPercent: 90 },
  ]);

  const decision = shouldPromoteCandidate(baseCandidate, ratings, {
    activeVerifiedCount: 20,
    maxPoolSize: 20,
    existingPoolFingerprints: new Set(),
  });

  assertEquals(decision.accepted, false);
  assertEquals(decision.reason, "cell_max_pool_size_reached");
});

Deno.test("Curation ist idempotent fuer bereits verified Fingerprints", () => {
  const ratings = summarizeRatings([
    { routeFingerprint: "candidate-good", rating: 5, completionPercent: 91 },
    { routeFingerprint: "candidate-good", rating: 5, completionPercent: 90 },
  ]);

  const decision = shouldPromoteCandidate(baseCandidate, ratings, {
    activeVerifiedCount: 2,
    maxPoolSize: 20,
    existingPoolFingerprints: new Set(["candidate-good"]),
  });

  assertEquals(decision.accepted, false);
  assertEquals(decision.reason, "duplicate_verified_fingerprint");
});

Deno.test("Verified wird bei schlechtem Feedback und Alternative demoted", () => {
  const ratings = summarizeRatings([
    {
      routeFingerprint: "pool-weak",
      rating: 2,
      completionPercent: 45,
      tags: ["falscher Start"],
    },
    {
      routeFingerprint: "pool-weak",
      rating: 3,
      completionPercent: 40,
      tags: ["Sackgasse"],
    },
  ]);

  const decision = shouldDemoteVerifiedRoute(basePoolRoute, ratings, {
    betterAlternativesAvailable: true,
  });

  assertEquals(decision.accepted, true);
  assertEquals(decision.reason, "low_average_rating");
});

Deno.test("Verified wird ohne bessere Alternative nicht demoted", () => {
  const ratings = summarizeRatings([
    { routeFingerprint: "pool-weak", rating: 2, completionPercent: 45 },
    { routeFingerprint: "pool-weak", rating: 3, completionPercent: 40 },
  ]);

  const decision = shouldDemoteVerifiedRoute(basePoolRoute, ratings, {
    betterAlternativesAvailable: false,
  });

  assertEquals(decision.accepted, false);
  assertEquals(decision.reason, "no_better_alternatives");
});

Deno.test("Coverage Status nutzt exakte Zelle und Zielwerte", () => {
  assertEquals(
    cellKey(baseCandidate),
    "AT|Vorarlberg|Dornbirn|Dornbirn|ROUND_TRIP|50|sport|no_highway",
  );
  assertEquals(
    deriveCoverageStatus({
      verifiedCount: 3,
      candidateCount: 1,
      idealCount: 1,
      goodCount: 2,
      acceptableCount: 0,
      distinctFingerprintCount: 3,
      minVerifiedCount: 3,
      targetPoolSize: 8,
      maxPoolSize: 20,
    }),
    "healthy",
  );
});

Deno.test("Weekly rotation score steigt mit gutem Feedback", () => {
  const weak = summarizeRatings([
    { routeFingerprint: "pool-weak", rating: 3, completionPercent: 60 },
    { routeFingerprint: "pool-weak", rating: 4, completionPercent: 65 },
  ]);
  const strong = summarizeRatings([
    { routeFingerprint: "pool-weak", rating: 5, completionPercent: 95 },
    { routeFingerprint: "pool-weak", rating: 5, completionPercent: 90 },
  ]);

  assertGreater(
    weeklyRotationScore(basePoolRoute, strong),
    weeklyRotationScore(basePoolRoute, weak),
  );
});
