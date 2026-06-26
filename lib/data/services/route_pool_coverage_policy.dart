import 'dart:math' as math;

import 'package:cruise_connect/domain/models/route_pool_coverage.dart';
import 'package:cruise_connect/domain/models/route_region.dart';

/// Pure policy layer for route-pool coverage thresholds and statuses.
///
/// This class deliberately has no Supabase/client dependencies. RoutePoolService
/// owns persistence and worker orchestration; this object only answers whether a
/// coverage cell is healthy, thin, blocked, or needs more candidates.
class RoutePoolCoveragePolicy {
  const RoutePoolCoveragePolicy({
    required this.requiredVerifiedCount,
    required this.difficultyLevel,
    required this.hardRegionStatus,
    required this.bootstrapEnabled,
    required this.curatedSeedPreferred,
    required this.minVerifiedCount,
    required this.targetPoolSize,
    required this.maxPoolSize,
    required this.candidateBufferLimit,
    required this.acceptableReserveLimitPercent,
    required this.minDistinctFingerprints,
    required this.healthyThreshold,
    required this.thinThreshold,
    required this.seedBudgetUnits,
    required this.seedCooldownMinutes,
  });

  factory RoutePoolCoveragePolicy.forRegion({
    required RouteRegion region,
    RoutePoolCoverage? coverage,
    int? requiredVerifiedCount,
    required int defaultMinVerifiedPerCell,
    required int defaultTargetPoolSize,
    required int defaultMaxPoolSize,
    required int defaultCandidateBufferLimit,
    required int defaultAcceptableReserveLimitPercent,
    required int defaultMinDistinctFingerprints,
  }) {
    final minVerifiedCount = math.max(
      0,
      math.min(
        defaultMaxPoolSize,
        requiredVerifiedCount ?? defaultMinVerifiedPerCell,
      ),
    );
    final hardCuratedRegion =
        region.difficultyLevel.trim().toLowerCase() == 'hard' &&
        region.curatedSeedPreferred;
    final targetFloor = hardCuratedRegion
        ? region.defaultTargetPoolSize
        : defaultTargetPoolSize;
    final maxFloor = hardCuratedRegion
        ? region.defaultMaxPoolSize
        : defaultMaxPoolSize;
    final configuredTargetPoolSize = math.max(
      coverage?.targetPoolSize ?? 0,
      region.defaultTargetPoolSize,
    );
    final targetPoolSize = math.max(
      minVerifiedCount,
      math.max(targetFloor, configuredTargetPoolSize),
    );
    final configuredMaxPoolSize = math.max(
      coverage?.maxPoolSize ?? 0,
      region.defaultMaxPoolSize,
    );
    final maxPoolSize = math.max(
      targetPoolSize,
      math.max(maxFloor, configuredMaxPoolSize),
    );
    final candidateBufferLimit = math.max(
      0,
      math.max(
        coverage?.candidateBufferLimit ?? 0,
        math.max(defaultCandidateBufferLimit, targetPoolSize * 4),
      ),
    );
    final acceptableReserveLimitPercent = math.max(
      0,
      math.min(
        100,
        coverage?.acceptableReserveLimitPercent ??
            defaultAcceptableReserveLimitPercent,
      ),
    );
    final healthyThreshold = math.max(
      1,
      math.min(maxPoolSize, minVerifiedCount),
    );
    final thinThreshold = math.max(
      0,
      math.min(
        healthyThreshold - 1,
        region.thinThreshold >= 0
            ? region.thinThreshold
            : (coverage?.thinThreshold ?? 1),
      ),
    );

    return RoutePoolCoveragePolicy(
      requiredVerifiedCount: requiredVerifiedCount,
      difficultyLevel: region.difficultyLevel,
      hardRegionStatus: region.hardRegionStatus,
      bootstrapEnabled: region.bootstrapEnabled,
      curatedSeedPreferred: region.curatedSeedPreferred,
      minVerifiedCount: minVerifiedCount,
      targetPoolSize: targetPoolSize,
      maxPoolSize: maxPoolSize,
      candidateBufferLimit: candidateBufferLimit,
      acceptableReserveLimitPercent: acceptableReserveLimitPercent,
      minDistinctFingerprints: defaultMinDistinctFingerprints,
      healthyThreshold: healthyThreshold,
      thinThreshold: thinThreshold,
      seedBudgetUnits: math.max(
        0,
        region.seedBudgetUnits >= 0
            ? region.seedBudgetUnits
            : (coverage?.seedBudgetUnits ?? 1),
      ),
      seedCooldownMinutes: math.max(
        1,
        region.seedCooldownMinutes > 0
            ? region.seedCooldownMinutes
            : (coverage?.seedCooldownMinutes ?? 20),
      ),
    );
  }

  final int? requiredVerifiedCount;
  final String difficultyLevel;
  final String hardRegionStatus;
  final bool bootstrapEnabled;
  final bool curatedSeedPreferred;
  final int minVerifiedCount;
  final int targetPoolSize;
  final int maxPoolSize;
  final int candidateBufferLimit;
  final int acceptableReserveLimitPercent;
  final int minDistinctFingerprints;
  final int healthyThreshold;
  final int thinThreshold;
  final int seedBudgetUnits;
  final int seedCooldownMinutes;

  bool get isHard => difficultyLevel == 'hard';

  static String deriveClusterCoverageStatus({
    required RouteRegion region,
    required int fulfilledCombinationCount,
    required int requiredCombinationCount,
    required int totalVerifiedCount,
  }) {
    if (requiredCombinationCount > 0 &&
        fulfilledCombinationCount >= requiredCombinationCount) {
      return totalVerifiedCount >= region.defaultTargetPoolSize
          ? 'healthy_full'
          : 'healthy_minimum';
    }
    if (region.difficultyLevel == 'hard') {
      if (region.curatedSeedPreferred ||
          region.hardRegionStatus == 'curated_needed' ||
          !region.bootstrapEnabled) {
        return 'hard_region_curated_needed';
      }
      return totalVerifiedCount > 0 ? 'hard_region_thin' : 'empty';
    }
    return totalVerifiedCount > 0 ? 'thin' : 'empty';
  }

  RoutePoolCoverage applySnapshot(RoutePoolCoverage coverage) {
    return coverage.copyWith(
      difficultyLevel: difficultyLevel,
      hardRegionStatus: hardRegionStatus,
      bootstrapEnabled: bootstrapEnabled,
      curatedSeedPreferred: curatedSeedPreferred,
      minVerifiedCount: minVerifiedCount,
      targetPoolSize: targetPoolSize,
      maxPoolSize: maxPoolSize,
      candidateBufferLimit: candidateBufferLimit,
      acceptableReserveLimitPercent: acceptableReserveLimitPercent,
      healthyThreshold: healthyThreshold,
      thinThreshold: thinThreshold,
      seedBudgetUnits: seedBudgetUnits,
      seedCooldownMinutes: seedCooldownMinutes,
    );
  }

  bool snapshotChanged(RoutePoolCoverage current, RoutePoolCoverage next) {
    return coverageSnapshotChanged(current, next);
  }

  static bool coverageSnapshotChanged(
    RoutePoolCoverage current,
    RoutePoolCoverage next,
  ) {
    return current.difficultyLevel != next.difficultyLevel ||
        current.hardRegionStatus != next.hardRegionStatus ||
        current.bootstrapEnabled != next.bootstrapEnabled ||
        current.curatedSeedPreferred != next.curatedSeedPreferred ||
        current.minVerifiedCount != next.minVerifiedCount ||
        current.targetPoolSize != next.targetPoolSize ||
        current.maxPoolSize != next.maxPoolSize ||
        current.candidateBufferLimit != next.candidateBufferLimit ||
        current.acceptableReserveLimitPercent !=
            next.acceptableReserveLimitPercent ||
        current.healthyThreshold != next.healthyThreshold ||
        current.thinThreshold != next.thinThreshold ||
        current.seedBudgetUnits != next.seedBudgetUnits ||
        current.seedCooldownMinutes != next.seedCooldownMinutes;
  }

  String deriveCoverageStatus({
    required int currentVerifiedCount,
    required int idealCount,
    required int goodCount,
    required int acceptableCount,
    required int distinctFingerprintCount,
    required bool hasBootstrapPending,
    required bool isCooldown,
  }) {
    if (currentVerifiedCount > maxPoolSize) return 'overfull';
    final goodEnoughCount = idealCount + goodCount;
    final acceptableLimit = acceptableReserveLimit(
      currentVerifiedCount: currentVerifiedCount,
      acceptableReserveLimitPercent: acceptableReserveLimitPercent,
    );
    final acceptableOverLimit =
        currentVerifiedCount > 0 && acceptableCount > acceptableLimit;
    final minimumMet =
        currentVerifiedCount >= minVerifiedCount &&
        distinctFingerprintCount >= minDistinctFingerprints &&
        goodEnoughCount >= minVerifiedCount &&
        !acceptableOverLimit;
    if (minimumMet && currentVerifiedCount >= targetPoolSize) {
      return 'target_met';
    }
    if (minimumMet) return 'healthy';
    if (currentVerifiedCount >= minVerifiedCount &&
        (goodEnoughCount < minVerifiedCount || acceptableOverLimit)) {
      return 'quality_thin';
    }
    if (isHard) {
      if (hasBootstrapPending || isCooldown) return 'bootstrap_limited';
      if (currentVerifiedCount > 0) return 'hard_region_thin';
      if (!bootstrapEnabled ||
          curatedSeedPreferred ||
          hardRegionStatus == 'curated_needed') {
        return 'hard_region_curated_needed';
      }
      return 'empty';
    }
    if (isCooldown) return 'cooldown';
    if (hasBootstrapPending) return 'warming_up';
    if (currentVerifiedCount > 0) return 'thin';
    return 'empty';
  }

  bool meetsMinimum(RoutePoolCoverage coverage) {
    final goodEnoughCount = coverage.idealCount + coverage.goodCount;
    final acceptableLimit = acceptableReserveLimit(
      currentVerifiedCount: coverage.currentVerifiedCount,
      acceptableReserveLimitPercent: acceptableReserveLimitPercent,
    );
    return coverage.currentVerifiedCount >= minVerifiedCount &&
        coverage.distinctFingerprintCount >= minDistinctFingerprints &&
        goodEnoughCount >= minVerifiedCount &&
        coverage.acceptableCount <= acceptableLimit;
  }

  bool meetsTarget(RoutePoolCoverage coverage) {
    return meetsMinimum(coverage) &&
        coverage.currentVerifiedCount >= targetPoolSize;
  }

  int missingMinimumCoverageCount(RoutePoolCoverage coverage) {
    if (meetsMinimum(coverage)) return 0;
    final missingVerified = math.max(
      0,
      minVerifiedCount - coverage.currentVerifiedCount,
    );
    final missingDistinct = math.max(
      0,
      minDistinctFingerprints - coverage.distinctFingerprintCount,
    );
    final missingGoodEnough = math.max(
      0,
      minVerifiedCount - (coverage.idealCount + coverage.goodCount),
    );
    return math.max(
      missingVerified,
      math.max(missingDistinct, missingGoodEnough),
    );
  }

  static int acceptableReserveLimit({
    required int currentVerifiedCount,
    required int acceptableReserveLimitPercent,
  }) {
    if (currentVerifiedCount <= 0 || acceptableReserveLimitPercent <= 0) {
      return 0;
    }
    return (currentVerifiedCount * (acceptableReserveLimitPercent / 100))
        .floor();
  }
}
