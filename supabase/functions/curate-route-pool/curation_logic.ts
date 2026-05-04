export type QualityTier = "ideal" | "good" | "acceptable" | "rejected";

export interface RatingFeedback {
  routeFingerprint: string;
  rating?: number | null;
  tags?: string[] | null;
  completionPercent?: number | null;
}

export interface RatingSummary {
  ratingCount: number;
  averageRating: number | null;
  completionRate: number | null;
  negativeTagCount: number;
  tags: string[];
}

export interface CurationRouteCell {
  countryCode: string;
  admin1Name: string;
  admin2Name?: string | null;
  cityCluster: string;
  routeType: string;
  distanceBucket: number;
  styleKey: string;
  avoidHighways: boolean;
}

export interface CurationCandidate extends CurationRouteCell {
  id?: string | null;
  routeFingerprint: string;
  hasHighway: boolean;
  qualityScore: number;
  shapeScore?: number | null;
  averageRating?: number | null;
  ratingCount?: number | null;
  completionRate?: number | null;
  repeatedSuccessCount?: number | null;
  isCandidate?: boolean | null;
  isVerifiedPool?: boolean | null;
  promotedToPoolAt?: string | null;
  demotedAt?: string | null;
  routePayload?: Record<string, unknown> | null;
}

export interface CurationPoolRoute extends CurationRouteCell {
  id?: string | null;
  routeFingerprint: string;
  hasHighway: boolean;
  isActive: boolean;
  verified: boolean;
  qualityScore: number;
  averageRating?: number | null;
  ratingCount?: number | null;
  completionRate?: number | null;
  deprecatedAt?: string | null;
  routePayload?: Record<string, unknown> | null;
}

export interface PromotionContext {
  activeVerifiedCount: number;
  maxPoolSize: number;
  existingPoolFingerprints: Set<string>;
}

export interface DemotionContext {
  betterAlternativesAvailable: boolean;
}

export interface CurationDecision {
  accepted: boolean;
  reason: string;
}

const negativeTagMarkers = [
  "sackgasse",
  "falscher start",
  "falsche start",
  "autobahn trotz aus",
  "autobahn",
  "motorway",
  "stich",
  "hin und zurück",
  "hin-und-zurück",
  "out and back",
  "out-and-back",
];

const hardWarningMarkers = [
  "u_turn",
  "dead_end",
  "dead-end",
  "sackgasse",
  "spur",
  "stich",
  "out_and_back",
  "out-and-back",
  "route_stub",
  "motorway_violation",
  "autobahn",
  "distance_mismatch",
  "wrong_bucket",
];

export function summarizeRatings(
  ratings: RatingFeedback[],
  fallback: {
    averageRating?: number | null;
    ratingCount?: number | null;
    completionRate?: number | null;
  } = {},
): RatingSummary {
  const ratingValues = ratings
    .map((row) => typeof row.rating === "number" ? row.rating : null)
    .filter((value): value is number => value !== null);
  const completionValues = ratings
    .map((row) =>
      typeof row.completionPercent === "number"
        ? normalizeCompletion(row.completionPercent)
        : null
    )
    .filter((value): value is number => value !== null);
  const tags = ratings.flatMap((row) => row.tags ?? []);
  const ratingCount = ratingValues.length || fallback.ratingCount || 0;
  const averageRating = ratingValues.length > 0
    ? average(ratingValues)
    : nullableNumber(fallback.averageRating);
  const completionRate = completionValues.length > 0
    ? average(completionValues)
    : nullableNumber(fallback.completionRate);

  return {
    ratingCount,
    averageRating,
    completionRate,
    negativeTagCount: countNegativeTags(tags),
    tags,
  };
}

export function shouldPromoteCandidate(
  candidate: CurationCandidate,
  ratings: RatingSummary,
  context: PromotionContext,
): CurationDecision {
  if (candidate.promotedToPoolAt) {
    return reject("already_promoted");
  }
  if (candidate.demotedAt) {
    return reject("candidate_demoted");
  }
  if (candidate.isCandidate === false || candidate.isVerifiedPool === true) {
    return reject("not_active_candidate");
  }
  if (context.existingPoolFingerprints.has(candidate.routeFingerprint)) {
    return reject("duplicate_verified_fingerprint");
  }
  if (context.activeVerifiedCount >= context.maxPoolSize) {
    return reject("cell_max_pool_size_reached");
  }
  if (candidate.avoidHighways && candidate.hasHighway) {
    return reject("motorway_violation");
  }
  if (ratings.negativeTagCount > 0) {
    return reject("negative_tags");
  }
  if (hasHardRouteWarning(candidate.routePayload)) {
    return reject("hard_route_warning");
  }

  const tier = qualityTierFor(candidate);
  const highRatedAcceptable = tier === "acceptable" &&
    (ratings.averageRating ?? 0) >= 4.6 &&
    ratings.ratingCount >= 2;
  if (tier !== "ideal" && tier !== "good" && !highRatedAcceptable) {
    return reject("quality_tier_not_promotable");
  }

  const repeatedSuccessCount = candidate.repeatedSuccessCount ?? 0;
  if (ratings.ratingCount < 2 && repeatedSuccessCount < 2) {
    return reject("insufficient_feedback");
  }
  if ((ratings.averageRating ?? 0) < 4.2) {
    return reject("average_rating_too_low");
  }
  if ((ratings.completionRate ?? 0) < 0.75) {
    return reject("completion_rate_too_low");
  }

  return { accepted: true, reason: "promote_candidate" };
}

export function shouldDemoteVerifiedRoute(
  route: CurationPoolRoute,
  ratings: RatingSummary,
  context: DemotionContext,
): CurationDecision {
  if (!route.verified || !route.isActive || route.deprecatedAt) {
    return reject("not_active_verified_route");
  }
  if (!context.betterAlternativesAvailable) {
    return reject("no_better_alternatives");
  }
  if (ratings.ratingCount >= 2 && (ratings.averageRating ?? 5) < 3.3) {
    return { accepted: true, reason: "low_average_rating" };
  }
  if (ratings.ratingCount >= 2 && (ratings.completionRate ?? 1) < 0.5) {
    return { accepted: true, reason: "low_completion_rate" };
  }
  if (ratings.negativeTagCount >= 2) {
    return { accepted: true, reason: "negative_tags" };
  }
  return reject("healthy_feedback");
}

export function weeklyRotationScore(
  route: Pick<CurationPoolRoute, "qualityScore">,
  ratings: RatingSummary,
): number {
  const quality = clamp(route.qualityScore, 0, 100);
  const averageRating = ratings.averageRating == null
    ? 70
    : clamp(ratings.averageRating * 20, 0, 100);
  const completion = ratings.completionRate == null
    ? 70
    : clamp(ratings.completionRate * 100, 0, 100);
  const feedbackConfidence = clamp(ratings.ratingCount * 8, 0, 20);
  const negativePenalty = Math.min(ratings.negativeTagCount * 18, 50);
  return round1(
    quality * 0.38 +
      averageRating * 0.30 +
      completion * 0.22 +
      feedbackConfidence -
      negativePenalty,
  );
}

export function cellKey(cell: CurationRouteCell): string {
  return [
    cell.countryCode.toUpperCase(),
    cell.admin1Name.trim(),
    cell.admin2Name?.trim() ?? "",
    cell.cityCluster.trim(),
    cell.routeType.trim().toUpperCase(),
    cell.distanceBucket,
    normalizeStyleKey(cell.styleKey),
    cell.avoidHighways ? "no_highway" : "highway_allowed",
  ].join("|");
}

export function deriveCoverageStatus(args: {
  verifiedCount: number;
  candidateCount: number;
  idealCount: number;
  goodCount: number;
  acceptableCount: number;
  distinctFingerprintCount: number;
  minVerifiedCount: number;
  targetPoolSize: number;
  maxPoolSize: number;
  minDistinctFingerprints?: number;
  acceptableReserveLimitPercent?: number;
}): string {
  if (args.verifiedCount <= 0) return "empty";
  if (args.verifiedCount > args.maxPoolSize) return "overfull";

  const minDistinct = args.minDistinctFingerprints ?? 3;
  if (
    args.verifiedCount < args.minVerifiedCount ||
    args.distinctFingerprintCount < minDistinct
  ) {
    return "thin";
  }

  const goodEnough = args.idealCount + args.goodCount;
  const acceptableLimit = Math.max(
    1,
    Math.floor(
      args.verifiedCount *
        ((args.acceptableReserveLimitPercent ?? 25) / 100),
    ),
  );
  if (goodEnough < args.minVerifiedCount || args.acceptableCount > acceptableLimit) {
    return "quality_thin";
  }

  if (args.verifiedCount >= args.targetPoolSize) return "target_met";
  return "healthy";
}

export function qualityTierFor(
  route: Pick<CurationCandidate, "qualityScore" | "routePayload">,
): QualityTier {
  const raw = typeof route.routePayload?.quality_tier === "string"
    ? route.routePayload.quality_tier.toLowerCase()
    : "";
  if (
    raw === "ideal" || raw === "good" || raw === "acceptable" ||
    raw === "rejected"
  ) {
    return raw;
  }
  if (route.qualityScore >= 92) return "ideal";
  if (route.qualityScore >= 82) return "good";
  if (route.qualityScore >= 70) return "acceptable";
  return "rejected";
}

export function countNegativeTags(tags: string[]): number {
  return tags.filter((tag) => {
    const normalized = normalizeText(tag);
    return negativeTagMarkers.some((marker) => normalized.includes(marker));
  }).length;
}

export function hasHardRouteWarning(
  payload: Record<string, unknown> | null | undefined,
): boolean {
  if (!payload) return false;
  if (payload.motorwayViolation === true || payload.motorway_violation === true) {
    return true;
  }
  const warnings = Array.isArray(payload.hard_warnings)
    ? payload.hard_warnings.map(String)
    : [];
  const reasonParts = [
    ...warnings,
    payload.reject_reason,
    payload.quality_reason,
    payload.cleanup_reason,
    payload.shape_quality_reason,
  ]
    .filter((value): value is string => typeof value === "string")
    .map(normalizeText);
  return reasonParts.some((part) =>
    hardWarningMarkers.some((marker) => part.includes(marker))
  );
}

export function normalizeStyleKey(style: string): string {
  return normalizeText(style)
    .replaceAll(" ", "_")
    .replaceAll("-", "_")
    .replaceAll("kurvenjagd", "curvy")
    .replaceAll("sport_mode", "sport")
    .replaceAll("abendrunde", "evening")
    .replaceAll("entdecker", "explorer");
}

function normalizeCompletion(value: number): number {
  return value > 1 ? clamp(value / 100, 0, 1) : clamp(value, 0, 1);
}

function average(values: number[]): number {
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function nullableNumber(value: number | null | undefined): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function normalizeText(value: string): string {
  return value.toLowerCase().trim();
}

function reject(reason: string): CurationDecision {
  return { accepted: false, reason };
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function round1(value: number): number {
  return Math.round(value * 10) / 10;
}
