import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/route_pool_coverage_policy.dart';
import 'package:cruise_connect/domain/models/route_pool_coverage.dart';
import 'package:cruise_connect/domain/models/route_region.dart';

void main() {
  group('RoutePoolCoveragePolicy', () {
    test('marks a cell healthy only when minimum quality counts are met', () {
      final policy = RoutePoolCoveragePolicy.forRegion(
        region: _region(),
        defaultMinVerifiedPerCell: 3,
        defaultTargetPoolSize: 12,
        defaultMaxPoolSize: 32,
        defaultCandidateBufferLimit: 72,
        defaultAcceptableReserveLimitPercent: 25,
        defaultMinDistinctFingerprints: 3,
      );

      expect(
        policy.deriveCoverageStatus(
          currentVerifiedCount: 3,
          idealCount: 1,
          goodCount: 2,
          acceptableCount: 0,
          distinctFingerprintCount: 3,
          hasBootstrapPending: false,
          isCooldown: false,
        ),
        'healthy',
      );

      expect(
        policy.deriveCoverageStatus(
          currentVerifiedCount: 3,
          idealCount: 0,
          goodCount: 1,
          acceptableCount: 2,
          distinctFingerprintCount: 3,
          hasBootstrapPending: false,
          isCooldown: false,
        ),
        'quality_thin',
      );
    });

    test('keeps hard curated regions out of normal bootstrap loops', () {
      final policy = RoutePoolCoveragePolicy.forRegion(
        region: _region(
          difficultyLevel: 'hard',
          curatedSeedPreferred: true,
          bootstrapEnabled: false,
        ),
        defaultMinVerifiedPerCell: 3,
        defaultTargetPoolSize: 12,
        defaultMaxPoolSize: 32,
        defaultCandidateBufferLimit: 72,
        defaultAcceptableReserveLimitPercent: 25,
        defaultMinDistinctFingerprints: 3,
      );

      expect(policy.isHard, isTrue);
      expect(
        policy.deriveCoverageStatus(
          currentVerifiedCount: 0,
          idealCount: 0,
          goodCount: 0,
          acceptableCount: 0,
          distinctFingerprintCount: 0,
          hasBootstrapPending: false,
          isCooldown: false,
        ),
        'hard_region_curated_needed',
      );
    });

    test('applies policy values to persisted coverage snapshots', () {
      final policy = RoutePoolCoveragePolicy.forRegion(
        region: _region(defaultTargetPoolSize: 18, defaultMaxPoolSize: 40),
        defaultMinVerifiedPerCell: 3,
        defaultTargetPoolSize: 12,
        defaultMaxPoolSize: 32,
        defaultCandidateBufferLimit: 72,
        defaultAcceptableReserveLimitPercent: 25,
        defaultMinDistinctFingerprints: 3,
      );

      final current = _coverage();
      final next = policy.applySnapshot(current);

      expect(next.targetPoolSize, 18);
      expect(next.maxPoolSize, 40);
      expect(next.candidateBufferLimit, 72);
      expect(
        RoutePoolCoveragePolicy.coverageSnapshotChanged(current, next),
        isTrue,
      );
    });
  });
}

RouteRegion _region({
  String difficultyLevel = 'normal',
  bool bootstrapEnabled = true,
  bool curatedSeedPreferred = false,
  int defaultTargetPoolSize = 12,
  int defaultMaxPoolSize = 32,
}) {
  return RouteRegion(
    id: 'region-1',
    countryCode: 'AT',
    admin1Name: 'Vorarlberg',
    admin2Name: 'Feldkirch',
    cityCluster: 'Feldkirch',
    centerLat: 47.24,
    centerLng: 9.60,
    difficultyLevel: difficultyLevel,
    bootstrapEnabled: bootstrapEnabled,
    curatedSeedPreferred: curatedSeedPreferred,
    defaultTargetPoolSize: defaultTargetPoolSize,
    defaultMaxPoolSize: defaultMaxPoolSize,
  );
}

RoutePoolCoverage _coverage() {
  return const RoutePoolCoverage(
    routeRegionId: 'region-1',
    countryCode: 'AT',
    admin1Name: 'Vorarlberg',
    admin2Name: 'Feldkirch',
    cityCluster: 'Feldkirch',
    routeType: 'ROUND_TRIP',
    distanceBucket: 50,
    styleKey: 'sport_mode',
    avoidHighways: true,
    coverageStatus: 'empty',
  );
}
