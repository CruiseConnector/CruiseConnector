import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/domain/models/route_pool_candidate.dart';
import 'package:cruise_connect/domain/models/route_pool_coverage.dart';
import 'package:cruise_connect/domain/models/route_pool_entry.dart';
import 'package:cruise_connect/domain/models/route_region.dart';
import 'package:cruise_connect/domain/models/route_seed_job.dart';
import 'package:cruise_connect/data/services/route_style_config.dart';

class RoutePoolQuery {
  const RoutePoolQuery({
    required this.userLat,
    required this.userLng,
    required this.countryCode,
    required this.admin1Name,
    this.admin2Name,
    this.cityCluster,
    required this.distanceBucket,
    required this.style,
    required this.avoidHighways,
    this.routeType = 'ROUND_TRIP',
    this.crossBorderAllowed = false,
  });

  final double userLat;
  final double userLng;
  final String countryCode;
  final String admin1Name;
  final String? admin2Name;
  final String? cityCluster;
  final int distanceBucket;
  final String style;
  final bool avoidHighways;
  final String routeType;
  final bool crossBorderAllowed;

  String get normalizedCountryCode => countryCode.toUpperCase();
}

class RoutePoolMatch {
  const RoutePoolMatch({
    required this.route,
    required this.startDistanceKm,
    required this.allowedRadiusKm,
    required this.radiusScope,
  });

  final RoutePoolEntry route;
  final double startDistanceKm;
  final double allowedRadiusKm;
  final String radiusScope;
}

class RoutePoolRegionAssignment {
  const RoutePoolRegionAssignment({
    required this.region,
    required this.distanceToCenterKm,
    this.newClusterCreated = false,
  });

  final RouteRegion region;
  final double distanceToCenterKm;
  final bool newClusterCreated;
}

class RoutePoolCoverageCheck {
  const RoutePoolCoverageCheck({
    required this.assignment,
    required this.coverage,
    required this.coverageStatus,
    required this.regionDifficulty,
    required this.hardRegionStatus,
    required this.bootstrapEnabled,
    required this.curatedSeedPreferred,
    required this.minVerifiedCount,
    required this.targetPoolSize,
    required this.maxPoolSize,
    required this.candidateBufferLimit,
    required this.acceptableReserveLimitPercent,
    required this.currentVerifiedCount,
    required this.currentCandidateCount,
    required this.idealCount,
    required this.goodCount,
    required this.acceptableCount,
    required this.rejectedCount,
    required this.distinctFingerprintCount,
    required this.seedJobCreated,
    required this.duplicateJobPrevented,
    required this.poolHealthy,
    required this.poolFull,
    required this.bootstrapPending,
    this.seedJobStatus,
    this.seedJobError,
    this.seedJobId,
    this.nextRetryAt,
  });

  final RoutePoolRegionAssignment? assignment;
  final RoutePoolCoverage? coverage;
  final String coverageStatus;
  final String regionDifficulty;
  final String hardRegionStatus;
  final bool bootstrapEnabled;
  final bool curatedSeedPreferred;
  final int minVerifiedCount;
  final int targetPoolSize;
  final int maxPoolSize;
  final int candidateBufferLimit;
  final int acceptableReserveLimitPercent;
  final int currentVerifiedCount;
  final int currentCandidateCount;
  final int idealCount;
  final int goodCount;
  final int acceptableCount;
  final int rejectedCount;
  final int distinctFingerprintCount;
  final bool seedJobCreated;
  final bool duplicateJobPrevented;
  final bool poolHealthy;
  final bool poolFull;
  final bool bootstrapPending;
  final String? seedJobStatus;
  final String? seedJobError;
  final String? seedJobId;
  final DateTime? nextRetryAt;

  bool get shouldSurfaceWarmup =>
      coverageStatus == 'warming_up' ||
      coverageStatus == 'cooldown' ||
      coverageStatus == 'empty' ||
      coverageStatus == 'thin' ||
      coverageStatus == 'quality_thin' ||
      coverageStatus == 'hard_region_thin' ||
      coverageStatus == 'hard_region_curated_needed' ||
      coverageStatus == 'bootstrap_limited';

  String get healingStatus {
    if (coverageStatus == 'hard_region_curated_needed') {
      return 'hard_region_curated_needed';
    }
    final coverageHealingStatus = coverage?.healingStatus;
    if (coverageHealingStatus != null && coverageHealingStatus != 'idle') {
      return coverageHealingStatus;
    }
    if (seedJobStatus == 'running') return 'healing_running';
    if (seedJobStatus == 'queued') return 'healing_queued';
    if (seedJobStatus == 'cooldown') return 'healing_failed_cooldown';
    if (seedJobStatus == 'paused_budget') return 'healing_paused_budget';
    return 'idle';
  }

  int? get estimatedWaitMinutes {
    final retryAt = nextRetryAt;
    if (retryAt == null) return shouldSurfaceWarmup ? 5 : null;
    final minutes = retryAt.difference(DateTime.now().toUtc()).inMinutes;
    return minutes <= 0 ? 1 : minutes;
  }

  Map<String, dynamic> toMeta() {
    return {
      'coverage_status': coverageStatus,
      'healing_status': healingStatus,
      'healing_job_id': seedJobId,
      'next_retry_at': nextRetryAt?.toIso8601String(),
      'estimated_wait_minutes': estimatedWaitMinutes,
      'region_difficulty': regionDifficulty,
      'hard_region_status': hardRegionStatus,
      'bootstrap_enabled': bootstrapEnabled,
      'curated_seed_preferred': curatedSeedPreferred,
      'pool_bootstrap_pending': bootstrapPending,
      'seed_job_created': seedJobCreated,
      'duplicate_job_prevented': duplicateJobPrevented,
      'seed_job_status': seedJobStatus,
      'seed_job_error': seedJobError,
      'chosen_cluster': assignment?.region.cityCluster,
      'country_code': assignment?.region.countryCode,
      'admin1_name': assignment?.region.admin1Name,
      'admin2_name': assignment?.region.admin2Name,
      'coverage_cell_key': coverage == null
          ? null
          : RoutePoolService.coverageCellKey(
              countryCode: coverage!.countryCode,
              admin1Name: coverage!.admin1Name,
              admin2Name: coverage!.admin2Name,
              cityCluster: coverage!.cityCluster,
              routeType: coverage!.routeType,
              distanceBucket: coverage!.distanceBucket,
              styleKey: coverage!.styleKey,
              avoidHighways: coverage!.avoidHighways,
            ),
      'new_cluster_created': assignment?.newClusterCreated ?? false,
      'chosen_cluster_distance_km': assignment == null
          ? null
          : double.parse(assignment!.distanceToCenterKm.toStringAsFixed(2)),
      'min_verified_count': minVerifiedCount,
      'target_pool_size': targetPoolSize,
      'max_pool_size': maxPoolSize,
      'candidate_buffer_limit': candidateBufferLimit,
      'acceptable_reserve_limit_percent': acceptableReserveLimitPercent,
      'current_verified_count': currentVerifiedCount,
      'current_candidate_count': currentCandidateCount,
      'ideal_count': idealCount,
      'good_count': goodCount,
      'acceptable_count': acceptableCount,
      'rejected_count': rejectedCount,
      'distinct_fingerprint_count': distinctFingerprintCount,
      'pool_healthy': poolHealthy,
      'pool_full': poolFull,
      'local_pool_unavailable':
          coverageStatus == 'empty' ||
          coverageStatus == 'thin' ||
          coverageStatus == 'quality_thin' ||
          coverageStatus == 'warming_up' ||
          coverageStatus == 'cooldown' ||
          coverageStatus == 'hard_region_thin' ||
          coverageStatus == 'hard_region_curated_needed' ||
          coverageStatus == 'bootstrap_limited',
      'retry_recommended': shouldSurfaceWarmup,
      'region_warming_up': shouldSurfaceWarmup,
    };
  }
}

class _CoveragePolicy {
  const _CoveragePolicy({
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
}

class RoutePoolRequiredCombination {
  const RoutePoolRequiredCombination({
    required this.distanceBucket,
    required this.styleLabel,
    required this.styleKey,
    required this.avoidHighways,
    required this.requiredVerifiedCount,
  });

  final int distanceBucket;
  final String styleLabel;
  final String styleKey;
  final bool avoidHighways;
  final int requiredVerifiedCount;
}

class _RequiredCoverageStyle {
  const _RequiredCoverageStyle(this.label, this.key);

  final String label;
  final String key;
}

const List<_RequiredCoverageStyle> _requiredCoverageStyles = [
  _RequiredCoverageStyle('Sport Mode', 'sport_mode'),
  _RequiredCoverageStyle('Kurvenjagd', 'kurvenjagd'),
  _RequiredCoverageStyle('Abendrunde', 'abendrunde'),
  _RequiredCoverageStyle('Entdecker', 'entdecker'),
];

class RoutePoolCombinationCoverage {
  const RoutePoolCombinationCoverage({
    required this.requirement,
    required this.coverageStatus,
    required this.currentVerifiedCount,
    required this.currentCandidateCount,
    required this.idealCount,
    required this.goodCount,
    required this.acceptableCount,
    required this.rejectedCount,
    required this.distinctFingerprintCount,
    required this.seedJobQueued,
    required this.duplicateJobPrevented,
    required this.seedJobPriority,
    required this.seedJobStatus,
    required this.missingVerifiedCount,
  });

  final RoutePoolRequiredCombination requirement;
  final String coverageStatus;
  final int currentVerifiedCount;
  final int currentCandidateCount;
  final int idealCount;
  final int goodCount;
  final int acceptableCount;
  final int rejectedCount;
  final int distinctFingerprintCount;
  final bool seedJobQueued;
  final bool duplicateJobPrevented;
  final int? seedJobPriority;
  final String? seedJobStatus;
  final int missingVerifiedCount;

  bool get isFulfilled => missingVerifiedCount <= 0;
  bool get healingJobNeeded => missingVerifiedCount > 0;
  String get label =>
      '${requirement.distanceBucket} ${requirement.styleLabel} '
      '${requirement.avoidHighways ? 'AUS' : 'AN'}';
}

class RoutePoolClusterCoverageReport {
  const RoutePoolClusterCoverageReport({
    required this.region,
    required this.coverageStatus,
    required this.requiredCombinationCount,
    required this.fulfilledCombinationCount,
    required this.totalVerifiedCount,
    required this.totalCandidateCount,
    required this.seedJobsQueuedCount,
    required this.duplicateJobsPreventedCount,
    required this.hardRegion,
    required this.combinations,
  });

  final RouteRegion region;
  final String coverageStatus;
  final int requiredCombinationCount;
  final int fulfilledCombinationCount;
  final int totalVerifiedCount;
  final int totalCandidateCount;
  final int seedJobsQueuedCount;
  final int duplicateJobsPreventedCount;
  final bool hardRegion;
  final List<RoutePoolCombinationCoverage> combinations;

  bool get isHealthyMinimum =>
      coverageStatus == 'healthy_minimum' ||
      coverageStatus == 'healthy_full' ||
      coverageStatus == 'target_met';

  List<RoutePoolCombinationCoverage> get missingCombinations =>
      combinations.where((combo) => !combo.isFulfilled).toList(growable: false);
}

class RoutePoolCandidateSaveResult {
  const RoutePoolCandidateSaveResult({
    required this.saved,
    required this.duplicate,
    required this.poolFull,
    this.assignment,
    this.candidate,
    this.duplicateSource,
    this.coverageRefreshFailed = false,
    this.saveErrorType,
    this.saveErrorCode,
    this.saveErrorReason,
  });

  final bool saved;
  final bool duplicate;
  final bool poolFull;
  final RoutePoolRegionAssignment? assignment;
  final RoutePoolCandidate? candidate;
  final String? duplicateSource;
  final bool coverageRefreshFailed;
  final String? saveErrorType;
  final String? saveErrorCode;
  final String? saveErrorReason;
}

class RoutePoolService {
  RoutePoolService({
    SupabaseClient? client,
    List<RoutePoolEntry>? inMemoryRoutes,
    List<RouteRegion>? inMemoryRegions,
    List<RoutePoolCoverage>? inMemoryCoverage,
    List<RouteSeedJob>? inMemorySeedJobs,
    List<RoutePoolCandidate>? inMemoryCandidates,
  }) : _client = client,
       _inMemoryRoutes = inMemoryRoutes,
       _inMemoryRegions = inMemoryRegions,
       _inMemoryCoverage = inMemoryCoverage,
       _inMemorySeedJobs = inMemorySeedJobs,
       _inMemoryCandidates = inMemoryCandidates;

  static const double localClusterMaxKm = 12.0;
  static const double nearbyClusterMaxKm = 20.0;
  static const double regionalMaxKm = 30.0;
  static const double maxExtendedRegionalKm = 45.0;
  static const double roundTripIdealStartMaxKm = 5.0;
  static const double roundTripHardStartMaxKm = 10.0;
  static const Set<int> validDistanceBuckets = {50, 75, 100};
  static const int defaultMinVerifiedPerCell = 3;
  static const int defaultTargetPoolSize = 8;
  static const int defaultMaxPoolSize = 20;
  static const int defaultCandidateBufferLimit = 30;
  static const int defaultAcceptableReserveLimitPercent = 25;
  static const int defaultMinDistinctFingerprints = 3;
  static const Duration coverageRefreshTtl = Duration(minutes: 15);
  static const Duration defaultSeedJobCooldown = Duration(minutes: 20);
  static final List<RoutePoolRequiredCombination> mvpRequiredCombinations = [
    for (final bucket in validDistanceBuckets)
      for (final style in _requiredCoverageStyles)
        for (final avoidHighways in [true, false])
          RoutePoolRequiredCombination(
            distanceBucket: bucket,
            styleLabel: style.label,
            styleKey: style.key,
            avoidHighways: avoidHighways,
            requiredVerifiedCount: defaultMinVerifiedPerCell,
          ),
  ];

  final SupabaseClient? _client;
  final List<RoutePoolEntry>? _inMemoryRoutes;
  final List<RouteRegion>? _inMemoryRegions;
  final List<RoutePoolCoverage>? _inMemoryCoverage;
  final List<RouteSeedJob>? _inMemorySeedJobs;
  final List<RoutePoolCandidate>? _inMemoryCandidates;

  SupabaseClient get _db => _client ?? Supabase.instance.client;

  static String coverageCellKey({
    required String countryCode,
    required String admin1Name,
    String? admin2Name,
    required String cityCluster,
    required String routeType,
    required int distanceBucket,
    required String styleKey,
    required bool avoidHighways,
  }) {
    return [
      countryCode.trim().toUpperCase(),
      _cellKeyPart(admin1Name),
      _cellKeyPart(admin2Name),
      _cellKeyPart(cityCluster),
      routeType.trim().toUpperCase(),
      distanceBucket.toString(),
      _normalizeStyleKey(styleKey),
      avoidHighways ? 'avoid_highways' : 'allow_highways',
    ].join('|');
  }

  Future<RoutePoolRegionAssignment?> resolveRegionAssignment({
    required double userLat,
    required double userLng,
    bool crossBorderAllowed = false,
    String? preferredCountryCode,
    String? preferredAdmin1Name,
    String? preferredAdmin2Name,
    String? preferredCityCluster,
  }) async {
    final regions = await _loadRegionsForAssignment(
      userLat: userLat,
      userLng: userLng,
      crossBorderAllowed: crossBorderAllowed,
      preferredCountryCode: preferredCountryCode,
      preferredAdmin1Name: preferredAdmin1Name,
      preferredAdmin2Name: preferredAdmin2Name,
      preferredCityCluster: preferredCityCluster,
    );
    if (regions.isEmpty) return null;

    final nearestRegion = _resolveNearestRegion(
      userLat: userLat,
      userLng: userLng,
      regions: regions,
      preferredCountryCode: preferredCountryCode,
      preferredAdmin1Name: preferredAdmin1Name,
      preferredAdmin2Name: preferredAdmin2Name,
      preferredCityCluster: preferredCityCluster,
    );
    if (nearestRegion == null) return null;

    final distanceToCenterKm = haversineDistanceKm(
      userLat,
      userLng,
      nearestRegion.centerLat,
      nearestRegion.centerLng,
    );
    return RoutePoolRegionAssignment(
      region: nearestRegion,
      distanceToCenterKm: distanceToCenterKm,
    );
  }

  Future<RoutePoolCoverageCheck> ensureCoverageForRequest({
    required double userLat,
    required double userLng,
    required int distanceBucket,
    required String style,
    required bool avoidHighways,
    required String routeType,
    required String subscriptionTier,
    bool createSeedJob = false,
    bool crossBorderAllowed = false,
    String? preferredCountryCode,
    String? preferredAdmin1Name,
    String? preferredAdmin2Name,
    String? preferredCityCluster,
  }) async {
    if (!validDistanceBuckets.contains(distanceBucket)) {
      return const RoutePoolCoverageCheck(
        assignment: null,
        coverage: null,
        coverageStatus: 'empty',
        regionDifficulty: 'normal',
        hardRegionStatus: 'normal',
        bootstrapEnabled: false,
        curatedSeedPreferred: false,
        minVerifiedCount: 3,
        targetPoolSize: defaultTargetPoolSize,
        maxPoolSize: defaultMaxPoolSize,
        candidateBufferLimit: defaultCandidateBufferLimit,
        acceptableReserveLimitPercent: defaultAcceptableReserveLimitPercent,
        currentVerifiedCount: 0,
        currentCandidateCount: 0,
        idealCount: 0,
        goodCount: 0,
        acceptableCount: 0,
        rejectedCount: 0,
        distinctFingerprintCount: 0,
        seedJobCreated: false,
        duplicateJobPrevented: false,
        poolHealthy: false,
        poolFull: false,
        bootstrapPending: false,
      );
    }

    final assignment = await resolveRegionAssignment(
      userLat: userLat,
      userLng: userLng,
      crossBorderAllowed: crossBorderAllowed,
      preferredCountryCode: preferredCountryCode,
      preferredAdmin1Name: preferredAdmin1Name,
      preferredAdmin2Name: preferredAdmin2Name,
      preferredCityCluster: preferredCityCluster,
    );

    if (assignment == null) {
      return const RoutePoolCoverageCheck(
        assignment: null,
        coverage: null,
        coverageStatus: 'empty',
        regionDifficulty: 'normal',
        hardRegionStatus: 'normal',
        bootstrapEnabled: false,
        curatedSeedPreferred: false,
        minVerifiedCount: 3,
        targetPoolSize: defaultTargetPoolSize,
        maxPoolSize: defaultMaxPoolSize,
        candidateBufferLimit: defaultCandidateBufferLimit,
        acceptableReserveLimitPercent: defaultAcceptableReserveLimitPercent,
        currentVerifiedCount: 0,
        currentCandidateCount: 0,
        idealCount: 0,
        goodCount: 0,
        acceptableCount: 0,
        rejectedCount: 0,
        distinctFingerprintCount: 0,
        seedJobCreated: false,
        duplicateJobPrevented: false,
        poolHealthy: false,
        poolFull: false,
        bootstrapPending: false,
      );
    }

    final styleKey = _normalizeStyleKey(style);
    final requiredCombination = _requiredCombinationFor(
      distanceBucket: distanceBucket,
      styleKey: styleKey,
      avoidHighways: avoidHighways,
    );
    var coverage = await _loadOrRefreshCoverage(
      assignment: assignment,
      distanceBucket: distanceBucket,
      styleKey: styleKey,
      avoidHighways: avoidHighways,
      routeType: routeType,
    );
    final policy = _coveragePolicyFor(
      region: assignment.region,
      coverage: coverage,
      requiredCombination: requiredCombination,
    );

    var seedJobCreated = false;
    var duplicateJobPrevented = false;
    var seedJob = await _loadSeedJob(
      assignment: assignment,
      distanceBucket: distanceBucket,
      styleKey: styleKey,
      avoidHighways: avoidHighways,
      routeType: routeType,
    );
    if (createSeedJob && seedJob != null && _seedJobBlocksNewJob(seedJob)) {
      duplicateJobPrevented = true;
    }
    final shouldCreateSeedJob =
        createSeedJob &&
        _shouldCreateSeedJob(
          policy: policy,
          coverage: coverage,
          existingSeedJob: seedJob,
        );
    if (shouldCreateSeedJob) {
      final jobResult = await _ensureSeedJob(
        assignment: assignment,
        policy: policy,
        distanceBucket: distanceBucket,
        styleKey: styleKey,
        avoidHighways: avoidHighways,
        routeType: routeType,
        subscriptionTier: subscriptionTier,
        priority: _seedJobPriority(
          subscriptionTier: subscriptionTier,
          requiredCombination: requiredCombination,
          currentVerifiedCount: coverage.currentVerifiedCount,
        ),
      );
      seedJob = jobResult.job;
      seedJobCreated = jobResult.created;
      duplicateJobPrevented = jobResult.duplicatePrevented;
      coverage = await _upsertCoverage(
        coverage.copyWith(
          coverageStatus: _deriveCoverageStatus(
            policy: policy,
            currentVerifiedCount: coverage.currentVerifiedCount,
            idealCount: coverage.idealCount,
            goodCount: coverage.goodCount,
            acceptableCount: coverage.acceptableCount,
            distinctFingerprintCount: coverage.distinctFingerprintCount,
            hasBootstrapPending: true,
            isCooldown: seedJob.isCoolingDown,
          ),
          healingStatus: _healingStatusForSeedJob(seedJob),
          healingPriority: seedJob.priority,
          lastHealingJobId: seedJob.id,
          nextHealingAt: seedJob.nextRetryAt ?? seedJob.cooldownUntil,
          lastBootstrapRequestedAt:
              seedJob.lastRequestedAt ?? DateTime.now().toUtc(),
          bootstrapCooldownUntil: seedJob.cooldownUntil,
          lastError: seedJob.lastError,
        ),
      );
    }

    final hasBootstrapPending =
        seedJob != null && (seedJob.isActive || seedJob.isCoolingDown);
    final coverageStatus = _deriveCoverageStatus(
      policy: policy,
      currentVerifiedCount: coverage.currentVerifiedCount,
      idealCount: coverage.idealCount,
      goodCount: coverage.goodCount,
      acceptableCount: coverage.acceptableCount,
      distinctFingerprintCount: coverage.distinctFingerprintCount,
      hasBootstrapPending: hasBootstrapPending,
      isCooldown: seedJob?.isCoolingDown ?? false,
    );
    final syncedCoverage = coverage.coverageStatus == coverageStatus
        ? coverage
        : await _upsertCoverage(
            coverage.copyWith(
              coverageStatus: coverageStatus,
              healingStatus: seedJob == null
                  ? coverage.healingStatus
                  : _healingStatusForSeedJob(seedJob),
              healingPriority: seedJob?.priority,
              lastHealingJobId: seedJob?.id,
              nextHealingAt: seedJob?.nextRetryAt ?? seedJob?.cooldownUntil,
              bootstrapCooldownUntil: seedJob?.cooldownUntil,
              lastError: seedJob?.lastError,
            ),
          );

    return RoutePoolCoverageCheck(
      assignment: assignment,
      coverage: syncedCoverage,
      coverageStatus: coverageStatus,
      regionDifficulty: policy.difficultyLevel,
      hardRegionStatus: policy.hardRegionStatus,
      bootstrapEnabled: policy.bootstrapEnabled,
      curatedSeedPreferred: policy.curatedSeedPreferred,
      minVerifiedCount: syncedCoverage.minVerifiedCount,
      targetPoolSize: syncedCoverage.targetPoolSize,
      maxPoolSize: syncedCoverage.maxPoolSize,
      candidateBufferLimit: syncedCoverage.candidateBufferLimit,
      acceptableReserveLimitPercent:
          syncedCoverage.acceptableReserveLimitPercent,
      currentVerifiedCount: syncedCoverage.currentVerifiedCount,
      currentCandidateCount: syncedCoverage.currentCandidateCount,
      idealCount: syncedCoverage.idealCount,
      goodCount: syncedCoverage.goodCount,
      acceptableCount: syncedCoverage.acceptableCount,
      rejectedCount: syncedCoverage.rejectedCount,
      distinctFingerprintCount: syncedCoverage.distinctFingerprintCount,
      seedJobCreated: seedJobCreated,
      duplicateJobPrevented: duplicateJobPrevented,
      poolHealthy: _coverageMeetsMinimum(
        policy: policy,
        coverage: syncedCoverage,
      ),
      poolFull:
          syncedCoverage.currentVerifiedCount >= syncedCoverage.maxPoolSize,
      bootstrapPending: hasBootstrapPending,
      seedJobStatus: seedJob?.status,
      seedJobError: seedJob?.lastError,
      seedJobId: seedJob?.id,
      nextRetryAt: seedJob?.nextRetryAt ?? seedJob?.cooldownUntil,
    );
  }

  Future<RoutePoolClusterCoverageReport?> buildClusterCoverageReport({
    required String countryCode,
    required String admin1Name,
    required String cityCluster,
    String? admin2Name,
    String routeType = 'ROUND_TRIP',
    bool createSeedJobs = false,
    String subscriptionTier = 'free',
    List<RoutePoolRequiredCombination>? requiredCombinations,
  }) async {
    final region = await _loadRegionByClusterKey(
      countryCode: countryCode,
      admin1Name: admin1Name,
      admin2Name: admin2Name,
      cityCluster: cityCluster,
    );
    if (region == null) return null;

    final assignment = RoutePoolRegionAssignment(
      region: region,
      distanceToCenterKm: 0,
    );
    final combinations =
        requiredCombinations ?? RoutePoolService.mvpRequiredCombinations;
    final coverageRows = <RoutePoolCombinationCoverage>[];
    var queuedCount = 0;
    var duplicateCount = 0;

    for (final requirement in combinations) {
      var coverage = await _loadOrRefreshCoverage(
        assignment: assignment,
        distanceBucket: requirement.distanceBucket,
        styleKey: requirement.styleKey,
        avoidHighways: requirement.avoidHighways,
        routeType: routeType,
      );
      final policy = _coveragePolicyFor(
        region: region,
        coverage: coverage,
        requiredCombination: requirement,
      );
      var seedJob = await _loadSeedJob(
        assignment: assignment,
        distanceBucket: requirement.distanceBucket,
        styleKey: requirement.styleKey,
        avoidHighways: requirement.avoidHighways,
        routeType: routeType,
      );
      var seedJobQueued = false;
      var duplicatePrevented = false;
      final missingVerifiedCount = _missingMinimumCoverageCount(
        policy: policy,
        coverage: coverage,
      );
      if (createSeedJobs &&
          missingVerifiedCount > 0 &&
          seedJob != null &&
          _seedJobBlocksNewJob(seedJob)) {
        duplicatePrevented = true;
        duplicateCount += 1;
      }
      if (createSeedJobs &&
          missingVerifiedCount > 0 &&
          _shouldCreateSeedJob(
            policy: policy,
            coverage: coverage,
            existingSeedJob: seedJob,
          )) {
        final result = await _ensureSeedJob(
          assignment: assignment,
          policy: policy,
          distanceBucket: requirement.distanceBucket,
          styleKey: requirement.styleKey,
          avoidHighways: requirement.avoidHighways,
          routeType: routeType,
          subscriptionTier: subscriptionTier,
          priority: _seedJobPriority(
            subscriptionTier: subscriptionTier,
            requiredCombination: requirement,
            currentVerifiedCount: coverage.currentVerifiedCount,
          ),
        );
        seedJob = result.job;
        seedJobQueued = result.created;
        duplicatePrevented = result.duplicatePrevented;
        if (seedJobQueued) queuedCount += 1;
        if (duplicatePrevented) duplicateCount += 1;
        coverage = await _upsertCoverage(
          coverage.copyWith(
            coverageStatus: _deriveCoverageStatus(
              policy: policy,
              currentVerifiedCount: coverage.currentVerifiedCount,
              idealCount: coverage.idealCount,
              goodCount: coverage.goodCount,
              acceptableCount: coverage.acceptableCount,
              distinctFingerprintCount: coverage.distinctFingerprintCount,
              hasBootstrapPending: true,
              isCooldown: seedJob.isCoolingDown,
            ),
            healingStatus: _healingStatusForSeedJob(seedJob),
            healingPriority: seedJob.priority,
            lastHealingJobId: seedJob.id,
            nextHealingAt: seedJob.nextRetryAt ?? seedJob.cooldownUntil,
            lastBootstrapRequestedAt:
                seedJob.lastRequestedAt ?? DateTime.now().toUtc(),
            bootstrapCooldownUntil: seedJob.cooldownUntil,
            lastError: seedJob.lastError,
          ),
        );
      }

      final hasBootstrapPending =
          seedJob != null && (seedJob.isActive || seedJob.isCoolingDown);
      final coverageStatus = _deriveCoverageStatus(
        policy: policy,
        currentVerifiedCount: coverage.currentVerifiedCount,
        idealCount: coverage.idealCount,
        goodCount: coverage.goodCount,
        acceptableCount: coverage.acceptableCount,
        distinctFingerprintCount: coverage.distinctFingerprintCount,
        hasBootstrapPending: hasBootstrapPending,
        isCooldown: seedJob?.isCoolingDown ?? false,
      );
      if (coverage.coverageStatus != coverageStatus) {
        coverage = await _upsertCoverage(
          coverage.copyWith(
            coverageStatus: coverageStatus,
            healingStatus: seedJob == null
                ? coverage.healingStatus
                : _healingStatusForSeedJob(seedJob),
            healingPriority: seedJob?.priority,
            lastHealingJobId: seedJob?.id,
            nextHealingAt: seedJob?.nextRetryAt ?? seedJob?.cooldownUntil,
            bootstrapCooldownUntil: seedJob?.cooldownUntil,
            lastError: seedJob?.lastError,
          ),
        );
      }
      coverageRows.add(
        RoutePoolCombinationCoverage(
          requirement: requirement,
          coverageStatus: coverageStatus,
          currentVerifiedCount: coverage.currentVerifiedCount,
          currentCandidateCount: coverage.currentCandidateCount,
          idealCount: coverage.idealCount,
          goodCount: coverage.goodCount,
          acceptableCount: coverage.acceptableCount,
          rejectedCount: coverage.rejectedCount,
          distinctFingerprintCount: coverage.distinctFingerprintCount,
          seedJobQueued: seedJobQueued,
          duplicateJobPrevented: duplicatePrevented,
          seedJobPriority: seedJob?.priority,
          seedJobStatus: seedJob?.status,
          missingVerifiedCount: math.max(
            0,
            _missingMinimumCoverageCount(policy: policy, coverage: coverage),
          ),
        ),
      );
    }

    final totalVerifiedCount = await _countClusterVerifiedRoutes(
      assignment: assignment,
      routeType: routeType,
    );
    final totalCandidateCount = await _countClusterCandidates(
      assignment: assignment,
      routeType: routeType,
    );
    final fulfilledCount = coverageRows
        .where((combo) => combo.isFulfilled)
        .length;
    final status = _deriveClusterCoverageStatus(
      region: region,
      fulfilledCombinationCount: fulfilledCount,
      requiredCombinationCount: coverageRows.length,
      totalVerifiedCount: totalVerifiedCount,
    );

    return RoutePoolClusterCoverageReport(
      region: region,
      coverageStatus: status,
      requiredCombinationCount: coverageRows.length,
      fulfilledCombinationCount: fulfilledCount,
      totalVerifiedCount: totalVerifiedCount,
      totalCandidateCount: totalCandidateCount,
      seedJobsQueuedCount: queuedCount,
      duplicateJobsPreventedCount: duplicateCount,
      hardRegion: region.difficultyLevel == 'hard',
      combinations: coverageRows,
    );
  }

  Future<RoutePoolCandidateSaveResult> recordCandidateRoute({
    required double userLat,
    required double userLng,
    required int distanceBucket,
    required String style,
    required bool avoidHighways,
    required String routeType,
    required String candidateSource,
    required String routeFingerprint,
    required Map<String, dynamic> geometry,
    Map<String, dynamic> routePayload = const {},
    double qualityScore = 0,
    double shapeScore = 0,
    double? distanceKm,
    bool hasHighway = false,
    bool crossBorderAllowed = false,
    String? preferredCountryCode,
    String? preferredAdmin1Name,
    String? preferredAdmin2Name,
    String? preferredCityCluster,
  }) async {
    if (!validDistanceBuckets.contains(distanceBucket)) {
      return const RoutePoolCandidateSaveResult(
        saved: false,
        duplicate: false,
        poolFull: false,
      );
    }

    final assignment = await resolveRegionAssignment(
      userLat: userLat,
      userLng: userLng,
      crossBorderAllowed: crossBorderAllowed,
      preferredCountryCode: preferredCountryCode,
      preferredAdmin1Name: preferredAdmin1Name,
      preferredAdmin2Name: preferredAdmin2Name,
      preferredCityCluster: preferredCityCluster,
    );
    if (assignment == null) {
      return const RoutePoolCandidateSaveResult(
        saved: false,
        duplicate: false,
        poolFull: false,
      );
    }

    final styleKey = _normalizeStyleKey(style);
    final coverage = await _loadOrRefreshCoverage(
      assignment: assignment,
      distanceBucket: distanceBucket,
      styleKey: styleKey,
      avoidHighways: avoidHighways,
      routeType: routeType,
    );
    final policy = _coveragePolicyFor(
      region: assignment.region,
      coverage: coverage,
      requiredCombination: _requiredCombinationFor(
        distanceBucket: distanceBucket,
        styleKey: styleKey,
        avoidHighways: avoidHighways,
      ),
    );
    final poolFull = coverage.currentVerifiedCount >= coverage.maxPoolSize;
    final qualityTier = routePayload['quality_tier']?.toString().toLowerCase();
    final distanceFitsBucket =
        distanceKm == null ||
        (distanceKm >= distanceBucket * 0.65 &&
            distanceKm <= distanceBucket * 1.35);
    if ((avoidHighways && hasHighway) ||
        qualityTier == 'rejected' ||
        qualityScore < 60 ||
        !distanceFitsBucket ||
        coverage.currentCandidateCount >= policy.candidateBufferLimit) {
      return RoutePoolCandidateSaveResult(
        saved: false,
        duplicate: false,
        poolFull: poolFull,
        assignment: assignment,
      );
    }
    final candidate = RoutePoolCandidate(
      routeRegionId: assignment.region.id,
      routeFingerprint: routeFingerprint,
      countryCode: assignment.region.countryCode,
      admin1Name: assignment.region.admin1Name,
      admin2Name: assignment.region.admin2Name,
      cityCluster: assignment.region.cityCluster,
      startLat: userLat,
      startLng: userLng,
      distanceKm: distanceKm,
      routeType: routeType,
      distanceBucket: distanceBucket,
      styleKey: styleKey,
      styleTags: [style],
      avoidHighways: avoidHighways,
      hasHighway: hasHighway,
      qualityScore: qualityScore.clamp(0, 100).toDouble(),
      shapeScore: shapeScore.clamp(0, 100).toDouble(),
      candidateSource: candidateSource,
      difficultyLevel: policy.difficultyLevel,
      hardRegionStatus: policy.hardRegionStatus,
      candidateLocalityScore: _candidateLocalityScore(
        distanceToCenterKm: assignment.distanceToCenterKm,
      ),
      repeatedSuccessCount: 1,
      isCandidate: true,
      isVerifiedPool: false,
      geometry: geometry,
      routePayload: routePayload,
    );
    final saveResult = await _upsertCandidate(candidate);
    if (!saveResult.saved) {
      if (saveResult.duplicate) {
        await _loadOrRefreshCoverage(
          assignment: assignment,
          distanceBucket: distanceBucket,
          styleKey: styleKey,
          avoidHighways: avoidHighways,
          routeType: routeType,
          forceRefresh: true,
        );
      }
      return RoutePoolCandidateSaveResult(
        saved: false,
        duplicate: saveResult.duplicate,
        poolFull: poolFull,
        assignment: assignment,
        candidate: saveResult.candidate,
        duplicateSource: saveResult.duplicateSource,
        saveErrorType: saveResult.saveErrorType,
        saveErrorCode: saveResult.saveErrorCode,
        saveErrorReason: saveResult.saveErrorReason,
      );
    }

    var coverageRefreshFailed = false;
    try {
      await _loadOrRefreshCoverage(
        assignment: assignment,
        distanceBucket: distanceBucket,
        styleKey: styleKey,
        avoidHighways: avoidHighways,
        routeType: routeType,
        forceRefresh: true,
      );
    } catch (_) {
      // Candidate staging succeeded; coverage can be recomputed by the next
      // request or worker run, so do not report the save itself as failed.
      coverageRefreshFailed = true;
    }
    return RoutePoolCandidateSaveResult(
      saved: true,
      duplicate: false,
      poolFull: poolFull,
      assignment: assignment,
      candidate: saveResult.candidate,
      coverageRefreshFailed: coverageRefreshFailed,
    );
  }

  Future<RoutePoolMatch?> findBestRouteNear({
    required double userLat,
    required double userLng,
    required int distanceBucket,
    required String style,
    required bool avoidHighways,
    String routeType = 'ROUND_TRIP',
    bool crossBorderAllowed = false,
    String? preferredCountryCode,
    String? preferredAdmin1Name,
    String? preferredAdmin2Name,
    String? preferredCityCluster,
    int candidateLimit = 120,
  }) async {
    final matches = await findCandidateRoutesNear(
      userLat: userLat,
      userLng: userLng,
      distanceBucket: distanceBucket,
      style: style,
      avoidHighways: avoidHighways,
      routeType: routeType,
      crossBorderAllowed: crossBorderAllowed,
      preferredCountryCode: preferredCountryCode,
      preferredAdmin1Name: preferredAdmin1Name,
      preferredAdmin2Name: preferredAdmin2Name,
      preferredCityCluster: preferredCityCluster,
      candidateLimit: candidateLimit,
    );
    return matches.isEmpty ? null : matches.first;
  }

  Future<List<RoutePoolMatch>> findCandidateRoutesNear({
    required double userLat,
    required double userLng,
    required int distanceBucket,
    required String style,
    required bool avoidHighways,
    String routeType = 'ROUND_TRIP',
    bool crossBorderAllowed = false,
    String? preferredCountryCode,
    String? preferredAdmin1Name,
    String? preferredAdmin2Name,
    String? preferredCityCluster,
    int candidateLimit = 120,
  }) async {
    if (!validDistanceBuckets.contains(distanceBucket)) return const [];
    final effectiveCandidateLimit = _effectiveCandidateLimit(
      routeType,
      candidateLimit,
    );

    final inMemoryRoutes = _inMemoryRoutes;
    final inMemoryRegions = _inMemoryRegions;
    if (inMemoryRoutes != null && inMemoryRegions != null) {
      return _findCandidateRoutesInMemory(
        userLat: userLat,
        userLng: userLng,
        distanceBucket: distanceBucket,
        style: style,
        avoidHighways: avoidHighways,
        routeType: routeType,
        crossBorderAllowed: crossBorderAllowed,
        preferredCountryCode: preferredCountryCode,
        preferredAdmin1Name: preferredAdmin1Name,
        preferredAdmin2Name: preferredAdmin2Name,
        preferredCityCluster: preferredCityCluster,
        routes: inMemoryRoutes,
        regions: inMemoryRegions,
      );
    }

    try {
      final regionSearchBounds = _boundingBoxFor(
        userLat,
        userLng,
        _maxRegionSearchRadiusForRouteType(routeType),
      );
      Future<List<RouteRegion>> loadRegions({
        String? countryCode,
        String? admin1Name,
      }) async {
        var query = _db
            .from('route_regions')
            .select()
            .eq('is_active', true)
            .gte('center_lat', regionSearchBounds.minLat)
            .lte('center_lat', regionSearchBounds.maxLat)
            .gte('center_lng', regionSearchBounds.minLng)
            .lte('center_lng', regionSearchBounds.maxLng);
        if (!crossBorderAllowed &&
            countryCode != null &&
            countryCode.trim().isNotEmpty) {
          query = query.eq('country_code', countryCode.trim().toUpperCase());
        }
        if (!crossBorderAllowed &&
            admin1Name != null &&
            admin1Name.trim().isNotEmpty) {
          query = query.eq('admin1_name', admin1Name.trim());
        }
        final rows = await query;
        return (rows as List)
            .map((row) => RouteRegion.fromJson(row as Map<String, dynamic>))
            .toList(growable: false);
      }

      var regions = await loadRegions(
        countryCode: preferredCountryCode,
        admin1Name: preferredAdmin1Name,
      );
      if (regions.isEmpty &&
          !crossBorderAllowed &&
          preferredCountryCode != null &&
          preferredCountryCode.trim().isNotEmpty) {
        regions = await loadRegions(countryCode: preferredCountryCode);
      }
      final nearestRegion = _resolveNearestRegion(
        userLat: userLat,
        userLng: userLng,
        regions: regions,
        preferredCountryCode: preferredCountryCode,
        preferredAdmin1Name: preferredAdmin1Name,
        preferredAdmin2Name: preferredAdmin2Name,
        preferredCityCluster: preferredCityCluster,
      );
      if (nearestRegion == null) return const [];

      Future<List<RoutePoolMatch>> lookupBucket(
        int bucket, {
        required bool relaxStyle,
      }) async {
        final routeSearchBounds = _boundingBoxFor(
          userLat,
          userLng,
          _maxSearchRadiusForRouteType(routeType),
        );
        var routeQuery = _db
            .from('route_pool')
            .select()
            .eq('verified', true)
            .eq('is_active', true)
            .eq('route_type', routeType)
            .eq('distance_bucket', bucket)
            .gte('start_lat', routeSearchBounds.minLat)
            .lte('start_lat', routeSearchBounds.maxLat)
            .gte('start_lng', routeSearchBounds.minLng)
            .lte('start_lng', routeSearchBounds.maxLng);

        if (!crossBorderAllowed) {
          routeQuery = routeQuery
              .eq('country_code', nearestRegion.countryCode)
              .eq('admin1_name', nearestRegion.admin1Name);
        }
        if (avoidHighways) {
          routeQuery = routeQuery
              .eq('avoids_highway', true)
              .eq('has_highway', false);
        }

        final routeRows = await routeQuery
            .order('quality_score', ascending: false)
            .limit(effectiveCandidateLimit);
        final candidates = (routeRows as List)
            .map((row) => RoutePoolEntry.fromJson(row as Map<String, dynamic>))
            .toList(growable: false);

        return findMatches(
          query: RoutePoolQuery(
            userLat: userLat,
            userLng: userLng,
            countryCode: nearestRegion.countryCode,
            admin1Name: nearestRegion.admin1Name,
            admin2Name: nearestRegion.admin2Name,
            cityCluster: nearestRegion.cityCluster,
            distanceBucket: bucket,
            style: style,
            avoidHighways: avoidHighways,
            routeType: routeType,
            crossBorderAllowed: crossBorderAllowed,
          ),
          candidates: candidates,
          regions: regions,
          relaxStyle: relaxStyle,
        );
      }

      final bucketOrder =
          [
            distanceBucket,
            ...validDistanceBuckets.where((bucket) => bucket != distanceBucket),
          ]..sort((a, b) {
            if (a == distanceBucket) return -1;
            if (b == distanceBucket) return 1;
            return (a - distanceBucket).abs().compareTo(
              (b - distanceBucket).abs(),
            );
          });

      final exactPrimaryMatches = <RoutePoolMatch>[];
      final exactFallbackMatches = <RoutePoolMatch>[];
      final relaxedPrimaryMatches = <RoutePoolMatch>[];
      final relaxedFallbackMatches = <RoutePoolMatch>[];
      final seenExactPrimaryRouteIds = <String>{};
      final seenExactFallbackRouteIds = <String>{};
      final seenRelaxedPrimaryRouteIds = <String>{};
      final seenRelaxedFallbackRouteIds = <String>{};
      final preferSingleBucketRoundTrip = routeType == 'ROUND_TRIP';
      final primaryBucketOrder = preferSingleBucketRoundTrip
          ? <int>[distanceBucket]
          : bucketOrder;
      final fallbackBucketOrder = preferSingleBucketRoundTrip
          ? const Iterable<int>.empty()
          : bucketOrder.skip(1);
      void addMatches(
        List<RoutePoolMatch> target,
        Set<String> seenRouteIds,
        List<RoutePoolMatch> nextMatches,
      ) {
        for (final match in nextMatches) {
          if (seenRouteIds.add(match.route.id)) {
            target.add(match);
          }
        }
      }

      for (final bucket in primaryBucketOrder) {
        addMatches(
          exactPrimaryMatches,
          seenExactPrimaryRouteIds,
          await lookupBucket(bucket, relaxStyle: false),
        );
      }
      if (exactPrimaryMatches.isEmpty) {
        for (final bucket in fallbackBucketOrder) {
          addMatches(
            exactFallbackMatches,
            seenExactFallbackRouteIds,
            await lookupBucket(bucket, relaxStyle: false),
          );
        }
      }
      for (final bucket in primaryBucketOrder) {
        addMatches(
          relaxedPrimaryMatches,
          seenRelaxedPrimaryRouteIds,
          await lookupBucket(bucket, relaxStyle: true),
        );
      }
      if (relaxedPrimaryMatches.isEmpty) {
        for (final bucket in fallbackBucketOrder) {
          addMatches(
            relaxedFallbackMatches,
            seenRelaxedFallbackRouteIds,
            await lookupBucket(bucket, relaxStyle: true),
          );
        }
      }
      _sortCandidateMatches(
        exactPrimaryMatches,
        requestedBucket: distanceBucket,
        requestedStyle: style,
      );
      _sortCandidateMatches(
        exactFallbackMatches,
        requestedBucket: distanceBucket,
        requestedStyle: style,
      );
      _sortCandidateMatches(
        relaxedPrimaryMatches,
        requestedBucket: distanceBucket,
        requestedStyle: style,
      );
      _sortCandidateMatches(
        relaxedFallbackMatches,
        requestedBucket: distanceBucket,
        requestedStyle: style,
      );

      final orderedMatches = preferSingleBucketRoundTrip
          ? <RoutePoolMatch>[...exactPrimaryMatches]
          : <RoutePoolMatch>[
              ...exactPrimaryMatches,
              ...exactFallbackMatches,
              ...relaxedPrimaryMatches,
              ...relaxedFallbackMatches,
            ];
      final seenOrderedIds = <String>{};
      return orderedMatches
          .where((match) => seenOrderedIds.add(match.route.id))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<RoutePoolMatch?> findBestRoute({
    required RoutePoolQuery query,
    int candidateLimit = 120,
  }) async {
    final matches = await findCandidateRoutesNear(
      userLat: query.userLat,
      userLng: query.userLng,
      distanceBucket: query.distanceBucket,
      style: query.style,
      avoidHighways: query.avoidHighways,
      routeType: query.routeType,
      crossBorderAllowed: query.crossBorderAllowed,
      preferredCountryCode: query.normalizedCountryCode,
      preferredAdmin1Name: query.admin1Name,
      preferredAdmin2Name: query.admin2Name,
      preferredCityCluster: query.cityCluster,
      candidateLimit: candidateLimit,
    );
    return matches.isEmpty ? null : matches.first;
  }

  static RoutePoolMatch? findBestMatch({
    required RoutePoolQuery query,
    required Iterable<RoutePoolEntry> candidates,
    required Iterable<RouteRegion> regions,
    bool relaxStyle = false,
  }) {
    final matches = findMatches(
      query: query,
      candidates: candidates,
      regions: regions,
      relaxStyle: relaxStyle,
    );
    return matches.isEmpty ? null : matches.first;
  }

  static List<RoutePoolMatch> _findCandidateRoutesInMemory({
    required double userLat,
    required double userLng,
    required int distanceBucket,
    required String style,
    required bool avoidHighways,
    required String routeType,
    required bool crossBorderAllowed,
    String? preferredCountryCode,
    String? preferredAdmin1Name,
    String? preferredAdmin2Name,
    String? preferredCityCluster,
    required List<RoutePoolEntry> routes,
    required List<RouteRegion> regions,
  }) {
    final nearestRegion = _resolveNearestRegion(
      userLat: userLat,
      userLng: userLng,
      regions: regions,
      preferredCountryCode: preferredCountryCode,
      preferredAdmin1Name: preferredAdmin1Name,
      preferredAdmin2Name: preferredAdmin2Name,
      preferredCityCluster: preferredCityCluster,
    );
    if (nearestRegion == null) return const [];

    final bucketOrder =
        [
          distanceBucket,
          ...validDistanceBuckets.where((bucket) => bucket != distanceBucket),
        ]..sort((a, b) {
          if (a == distanceBucket) return -1;
          if (b == distanceBucket) return 1;
          return (a - distanceBucket).abs().compareTo(
            (b - distanceBucket).abs(),
          );
        });

    final exactPrimaryMatches = <RoutePoolMatch>[];
    final exactFallbackMatches = <RoutePoolMatch>[];
    final relaxedPrimaryMatches = <RoutePoolMatch>[];
    final relaxedFallbackMatches = <RoutePoolMatch>[];
    final seenExactPrimaryRouteIds = <String>{};
    final seenExactFallbackRouteIds = <String>{};
    final seenRelaxedPrimaryRouteIds = <String>{};
    final seenRelaxedFallbackRouteIds = <String>{};
    final preferSingleBucketRoundTrip = routeType == 'ROUND_TRIP';
    final primaryBucketOrder = preferSingleBucketRoundTrip
        ? <int>[distanceBucket]
        : bucketOrder;
    final fallbackBucketOrder = preferSingleBucketRoundTrip
        ? const Iterable<int>.empty()
        : bucketOrder.skip(1);
    void addMatches(
      List<RoutePoolMatch> target,
      Set<String> seenRouteIds,
      List<RoutePoolMatch> nextMatches,
    ) {
      for (final match in nextMatches) {
        if (seenRouteIds.add(match.route.id)) {
          target.add(match);
        }
      }
    }

    for (final bucket in primaryBucketOrder) {
      addMatches(
        exactPrimaryMatches,
        seenExactPrimaryRouteIds,
        findMatches(
          query: RoutePoolQuery(
            userLat: userLat,
            userLng: userLng,
            countryCode: nearestRegion.countryCode,
            admin1Name: nearestRegion.admin1Name,
            admin2Name: nearestRegion.admin2Name,
            cityCluster: nearestRegion.cityCluster,
            distanceBucket: bucket,
            style: style,
            avoidHighways: avoidHighways,
            routeType: routeType,
            crossBorderAllowed: crossBorderAllowed,
          ),
          candidates: routes,
          regions: regions,
          relaxStyle: false,
        ),
      );
    }
    if (exactPrimaryMatches.isEmpty) {
      for (final bucket in fallbackBucketOrder) {
        addMatches(
          exactFallbackMatches,
          seenExactFallbackRouteIds,
          findMatches(
            query: RoutePoolQuery(
              userLat: userLat,
              userLng: userLng,
              countryCode: nearestRegion.countryCode,
              admin1Name: nearestRegion.admin1Name,
              admin2Name: nearestRegion.admin2Name,
              cityCluster: nearestRegion.cityCluster,
              distanceBucket: bucket,
              style: style,
              avoidHighways: avoidHighways,
              routeType: routeType,
              crossBorderAllowed: crossBorderAllowed,
            ),
            candidates: routes,
            regions: regions,
            relaxStyle: false,
          ),
        );
      }
    }
    for (final bucket in primaryBucketOrder) {
      addMatches(
        relaxedPrimaryMatches,
        seenRelaxedPrimaryRouteIds,
        findMatches(
          query: RoutePoolQuery(
            userLat: userLat,
            userLng: userLng,
            countryCode: nearestRegion.countryCode,
            admin1Name: nearestRegion.admin1Name,
            admin2Name: nearestRegion.admin2Name,
            cityCluster: nearestRegion.cityCluster,
            distanceBucket: bucket,
            style: style,
            avoidHighways: avoidHighways,
            routeType: routeType,
            crossBorderAllowed: crossBorderAllowed,
          ),
          candidates: routes,
          regions: regions,
          relaxStyle: true,
        ),
      );
    }
    if (relaxedPrimaryMatches.isEmpty) {
      for (final bucket in fallbackBucketOrder) {
        addMatches(
          relaxedFallbackMatches,
          seenRelaxedFallbackRouteIds,
          findMatches(
            query: RoutePoolQuery(
              userLat: userLat,
              userLng: userLng,
              countryCode: nearestRegion.countryCode,
              admin1Name: nearestRegion.admin1Name,
              admin2Name: nearestRegion.admin2Name,
              cityCluster: nearestRegion.cityCluster,
              distanceBucket: bucket,
              style: style,
              avoidHighways: avoidHighways,
              routeType: routeType,
              crossBorderAllowed: crossBorderAllowed,
            ),
            candidates: routes,
            regions: regions,
            relaxStyle: true,
          ),
        );
      }
    }
    _sortCandidateMatches(
      exactPrimaryMatches,
      requestedBucket: distanceBucket,
      requestedStyle: style,
    );
    _sortCandidateMatches(
      exactFallbackMatches,
      requestedBucket: distanceBucket,
      requestedStyle: style,
    );
    _sortCandidateMatches(
      relaxedPrimaryMatches,
      requestedBucket: distanceBucket,
      requestedStyle: style,
    );
    _sortCandidateMatches(
      relaxedFallbackMatches,
      requestedBucket: distanceBucket,
      requestedStyle: style,
    );
    final orderedMatches = preferSingleBucketRoundTrip
        ? <RoutePoolMatch>[...exactPrimaryMatches]
        : <RoutePoolMatch>[
            ...exactPrimaryMatches,
            ...exactFallbackMatches,
            ...relaxedPrimaryMatches,
            ...relaxedFallbackMatches,
          ];
    final seenOrderedIds = <String>{};
    return orderedMatches
        .where((match) => seenOrderedIds.add(match.route.id))
        .toList(growable: false);
  }

  static List<RoutePoolMatch> findMatches({
    required RoutePoolQuery query,
    required Iterable<RoutePoolEntry> candidates,
    required Iterable<RouteRegion> regions,
    bool relaxStyle = false,
  }) {
    if (!validDistanceBuckets.contains(query.distanceBucket)) return const [];
    final activeRegions = regions.where((region) => region.isActive).toList();
    final matches = <RoutePoolMatch>[];

    for (final candidate in candidates) {
      if (!candidate.verified) continue;
      if (!candidate.isActive) continue;
      if (candidate.routeType != query.routeType) continue;
      if (!validDistanceBuckets.contains(candidate.distanceBucket)) continue;
      if (candidate.distanceBucket != query.distanceBucket) continue;
      final exactStyleMatch = _styleMatches(candidate, query.style);
      if (!relaxStyle && !exactStyleMatch) continue;
      if (relaxStyle &&
          !exactStyleMatch &&
          !_relaxedStyleCompatible(candidate, query.style)) {
        continue;
      }
      if (!_highwayMatches(candidate, query.avoidHighways)) continue;
      if (!_locationScopeMatches(query, candidate)) continue;

      final distanceKm = haversineDistanceKm(
        query.userLat,
        query.userLng,
        candidate.startLat,
        candidate.startLng,
      );
      final radius = _allowedRadiusFor(query, candidate, activeRegions);
      if (radius == null || distanceKm > radius.allowedRadiusKm) continue;
      final radiusScope = query.routeType == 'ROUND_TRIP'
          ? _roundTripRadiusScope(query, candidate, distanceKm)
          : radius.scope;

      matches.add(
        RoutePoolMatch(
          route: candidate,
          startDistanceKm: distanceKm,
          allowedRadiusKm: radius.allowedRadiusKm,
          radiusScope: radiusScope,
        ),
      );
    }

    matches.sort((a, b) {
      final byDistance = a.startDistanceKm.compareTo(b.startDistanceKm);
      if (byDistance != 0) return byDistance;

      final byCity = _boolScore(
        _sameCity(query, a.route),
      ).compareTo(_boolScore(_sameCity(query, b.route)));
      if (byCity != 0) return -byCity;

      final byAdmin2 = _boolScore(
        _sameAdmin2(query, a.route),
      ).compareTo(_boolScore(_sameAdmin2(query, b.route)));
      if (byAdmin2 != 0) return -byAdmin2;

      final byRotation = b.route.weeklyRotationScore.compareTo(
        a.route.weeklyRotationScore,
      );
      if (byRotation != 0) return byRotation;

      return b.route.qualityScore.compareTo(a.route.qualityScore);
    });

    return matches;
  }

  static void _sortCandidateMatches(
    List<RoutePoolMatch> matches, {
    required int requestedBucket,
    required String requestedStyle,
  }) {
    matches.sort((a, b) {
      final byExactStyle = _boolScore(
        _styleMatches(a.route, requestedStyle),
      ).compareTo(_boolScore(_styleMatches(b.route, requestedStyle)));
      if (byExactStyle != 0) return -byExactStyle;

      final byBucketFit = (a.route.distanceBucket - requestedBucket)
          .abs()
          .compareTo((b.route.distanceBucket - requestedBucket).abs());
      if (byBucketFit != 0) return byBucketFit;

      final byActualDistanceFit = (a.route.distanceKm - requestedBucket)
          .abs()
          .compareTo((b.route.distanceKm - requestedBucket).abs());
      if (byActualDistanceFit != 0) return byActualDistanceFit;

      final byStyleFit = _poolStyleFitScore(
        b.route,
        requestedStyle,
      ).compareTo(_poolStyleFitScore(a.route, requestedStyle));
      if (byStyleFit != 0) return byStyleFit;

      final byStartDistance = a.startDistanceKm.compareTo(b.startDistanceKm);
      if (byStartDistance != 0) return byStartDistance;

      final byRotation = b.route.weeklyRotationScore.compareTo(
        a.route.weeklyRotationScore,
      );
      if (byRotation != 0) return byRotation;

      return b.route.qualityScore.compareTo(a.route.qualityScore);
    });
  }

  Future<List<RouteRegion>> _loadRegionsForAssignment({
    required double userLat,
    required double userLng,
    required bool crossBorderAllowed,
    String? preferredCountryCode,
    String? preferredAdmin1Name,
    String? preferredAdmin2Name,
    String? preferredCityCluster,
  }) async {
    final inMemoryRegions = _inMemoryRegions;
    if (inMemoryRegions != null) {
      return inMemoryRegions
          .where((region) {
            if (!region.isActive) return false;
            final distanceKm = haversineDistanceKm(
              userLat,
              userLng,
              region.centerLat,
              region.centerLng,
            );
            final allowedKm = math.min(
              math.max(regionalMaxKm, region.fallbackRadiusKm),
              maxExtendedRegionalKm,
            );
            if (distanceKm > allowedKm) return false;
            if (!crossBorderAllowed &&
                preferredCountryCode != null &&
                preferredCountryCode.trim().isNotEmpty &&
                !_sameText(preferredCountryCode, region.countryCode)) {
              return false;
            }
            if (!crossBorderAllowed &&
                preferredAdmin1Name != null &&
                preferredAdmin1Name.trim().isNotEmpty &&
                !_sameText(preferredAdmin1Name, region.admin1Name)) {
              return false;
            }
            return true;
          })
          .toList(growable: false);
    }

    final bounds = _boundingBoxFor(userLat, userLng, maxExtendedRegionalKm);
    var query = _db
        .from('route_regions')
        .select()
        .eq('is_active', true)
        .gte('center_lat', bounds.minLat)
        .lte('center_lat', bounds.maxLat)
        .gte('center_lng', bounds.minLng)
        .lte('center_lng', bounds.maxLng);
    if (!crossBorderAllowed &&
        preferredCountryCode != null &&
        preferredCountryCode.trim().isNotEmpty) {
      query = query.eq(
        'country_code',
        preferredCountryCode.trim().toUpperCase(),
      );
    }
    if (!crossBorderAllowed &&
        preferredAdmin1Name != null &&
        preferredAdmin1Name.trim().isNotEmpty) {
      query = query.eq('admin1_name', preferredAdmin1Name.trim());
    }
    final rows = await query;
    return (rows as List)
        .map((row) => RouteRegion.fromJson(row as Map<String, dynamic>))
        .where((region) => region.isActive)
        .toList(growable: false);
  }

  Future<RouteRegion?> _loadRegionByClusterKey({
    required String countryCode,
    required String admin1Name,
    String? admin2Name,
    required String cityCluster,
  }) async {
    final inMemoryRegions = _inMemoryRegions;
    if (inMemoryRegions != null) {
      for (final region in inMemoryRegions) {
        if (!region.isActive) continue;
        if (_sameText(region.countryCode, countryCode) &&
            _sameText(region.admin1Name, admin1Name) &&
            _nullableSameText(region.admin2Name, admin2Name) &&
            _sameText(region.cityCluster, cityCluster)) {
          return region;
        }
      }
      return null;
    }

    var query = _db
        .from('route_regions')
        .select()
        .eq('is_active', true)
        .eq('country_code', countryCode.trim().toUpperCase())
        .eq('admin1_name', admin1Name.trim())
        .eq('city_cluster', cityCluster.trim());
    if (admin2Name != null && admin2Name.trim().isNotEmpty) {
      query = query.eq('admin2_name', admin2Name.trim());
    }
    final rows = await query.limit(1);
    if ((rows as List).isEmpty) return null;
    return RouteRegion.fromJson(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<RoutePoolCoverage> _loadOrRefreshCoverage({
    required RoutePoolRegionAssignment assignment,
    required int distanceBucket,
    required String styleKey,
    required bool avoidHighways,
    required String routeType,
    bool forceRefresh = false,
  }) async {
    final coverage = await _loadCoverageRow(
      assignment: assignment,
      distanceBucket: distanceBucket,
      styleKey: styleKey,
      avoidHighways: avoidHighways,
      routeType: routeType,
    );
    final policy = _coveragePolicyFor(
      region: assignment.region,
      coverage: coverage,
      requiredCombination: _requiredCombinationFor(
        distanceBucket: distanceBucket,
        styleKey: styleKey,
        avoidHighways: avoidHighways,
      ),
    );
    final policyAlignedCoverage = coverage == null
        ? null
        : _applyCoveragePolicySnapshot(coverage, policy: policy);
    final policyChanged =
        coverage != null &&
        _coveragePolicyChanged(coverage, policyAlignedCoverage!);
    final shouldRefresh =
        coverage == null ||
        forceRefresh ||
        policyChanged ||
        policyAlignedCoverage!.lastCountedAt == null ||
        DateTime.now().toUtc().difference(
              policyAlignedCoverage.lastCountedAt!,
            ) >
            coverageRefreshTtl;
    if (!shouldRefresh) {
      return policyAlignedCoverage;
    }

    final verifiedSummary = await _summarizeMatchingVerifiedRoutes(
      assignment: assignment,
      distanceBucket: distanceBucket,
      styleKey: styleKey,
      avoidHighways: avoidHighways,
      routeType: routeType,
    );
    final candidateCount = await _countMatchingCandidates(
      assignment: assignment,
      distanceBucket: distanceBucket,
      styleKey: styleKey,
      avoidHighways: avoidHighways,
      routeType: routeType,
    );
    final base =
        policyAlignedCoverage ??
        RoutePoolCoverage(
          routeRegionId: assignment.region.id,
          countryCode: assignment.region.countryCode,
          admin1Name: assignment.region.admin1Name,
          admin2Name: assignment.region.admin2Name,
          cityCluster: assignment.region.cityCluster,
          routeType: routeType,
          distanceBucket: distanceBucket,
          styleKey: styleKey,
          avoidHighways: avoidHighways,
          coverageStatus: 'empty',
          difficultyLevel: policy.difficultyLevel,
          hardRegionStatus: policy.hardRegionStatus,
          bootstrapEnabled: policy.bootstrapEnabled,
          curatedSeedPreferred: policy.curatedSeedPreferred,
          minVerifiedCount: policy.minVerifiedCount,
          targetPoolSize: policy.targetPoolSize,
          maxPoolSize: policy.maxPoolSize,
          candidateBufferLimit: policy.candidateBufferLimit,
          acceptableReserveLimitPercent: policy.acceptableReserveLimitPercent,
          healthyThreshold: policy.healthyThreshold,
          thinThreshold: policy.thinThreshold,
          seedBudgetUnits: policy.seedBudgetUnits,
          seedCooldownMinutes: policy.seedCooldownMinutes,
        );
    final refreshed = base.copyWith(
      currentVerifiedCount: verifiedSummary.verifiedCount,
      currentCandidateCount: candidateCount,
      idealCount: verifiedSummary.idealCount,
      goodCount: verifiedSummary.goodCount,
      acceptableCount: verifiedSummary.acceptableCount,
      rejectedCount: verifiedSummary.rejectedCount,
      distinctFingerprintCount: verifiedSummary.distinctFingerprintCount,
      coverageStatus: _deriveCoverageStatus(
        policy: policy,
        currentVerifiedCount: verifiedSummary.verifiedCount,
        idealCount: verifiedSummary.idealCount,
        goodCount: verifiedSummary.goodCount,
        acceptableCount: verifiedSummary.acceptableCount,
        distinctFingerprintCount: verifiedSummary.distinctFingerprintCount,
        hasBootstrapPending: false,
        isCooldown: false,
      ),
      lastCountedAt: DateTime.now().toUtc(),
    );
    return _upsertCoverage(refreshed);
  }

  Future<RoutePoolCoverage?> _loadCoverageRow({
    required RoutePoolRegionAssignment assignment,
    required int distanceBucket,
    required String styleKey,
    required bool avoidHighways,
    required String routeType,
  }) async {
    final inMemoryCoverage = _inMemoryCoverage;
    if (inMemoryCoverage != null) {
      for (final coverage in inMemoryCoverage) {
        if (_coverageKeyMatches(
          coverage,
          assignment: assignment,
          distanceBucket: distanceBucket,
          styleKey: styleKey,
          avoidHighways: avoidHighways,
          routeType: routeType,
        )) {
          return coverage;
        }
      }
      return null;
    }

    final rows = await _db
        .from('route_pool_coverage')
        .select()
        .eq('country_code', assignment.region.countryCode)
        .eq('admin1_name', assignment.region.admin1Name)
        .eq('city_cluster', assignment.region.cityCluster)
        .eq('route_type', routeType)
        .eq('distance_bucket', distanceBucket)
        .eq('style_key', styleKey)
        .eq('avoid_highways', avoidHighways);
    for (final row in rows as List) {
      final coverage = RoutePoolCoverage.fromJson(row as Map<String, dynamic>);
      if (_nullableSameText(
        coverage.admin2Name,
        assignment.region.admin2Name,
      )) {
        return coverage;
      }
    }
    return null;
  }

  Future<RoutePoolCoverage> _upsertCoverage(RoutePoolCoverage coverage) async {
    final inMemoryCoverage = _inMemoryCoverage;
    if (inMemoryCoverage != null) {
      final index = inMemoryCoverage.indexWhere((item) {
        return _sameText(item.countryCode, coverage.countryCode) &&
            _sameText(item.admin1Name, coverage.admin1Name) &&
            _nullableSameText(item.admin2Name, coverage.admin2Name) &&
            _sameText(item.cityCluster, coverage.cityCluster) &&
            _sameText(item.routeType, coverage.routeType) &&
            item.distanceBucket == coverage.distanceBucket &&
            _sameText(item.styleKey, coverage.styleKey) &&
            item.avoidHighways == coverage.avoidHighways;
      });
      if (index >= 0) {
        inMemoryCoverage[index] = coverage;
      } else {
        inMemoryCoverage.add(coverage);
      }
      return coverage;
    }

    final existing = await _loadCoverageRow(
      assignment: RoutePoolRegionAssignment(
        region: RouteRegion(
          id: coverage.routeRegionId,
          countryCode: coverage.countryCode,
          admin1Name: coverage.admin1Name,
          admin2Name: coverage.admin2Name,
          cityCluster: coverage.cityCluster,
          centerLat: 0,
          centerLng: 0,
        ),
        distanceToCenterKm: 0,
      ),
      distanceBucket: coverage.distanceBucket,
      styleKey: coverage.styleKey,
      avoidHighways: coverage.avoidHighways,
      routeType: coverage.routeType,
    );
    if (existing?.id != null) {
      final payload = _coveragePayloadForDb(coverage)..remove('id');
      final rows = await _db
          .from('route_pool_coverage')
          .update(payload)
          .eq('id', existing!.id!)
          .select()
          .limit(1);
      return RoutePoolCoverage.fromJson(
        Map<String, dynamic>.from((rows as List).first as Map),
      );
    }
    final rows = await _db
        .from('route_pool_coverage')
        .insert(_coveragePayloadForDb(coverage))
        .select()
        .limit(1);
    return RoutePoolCoverage.fromJson(
      Map<String, dynamic>.from((rows as List).first as Map),
    );
  }

  Future<_CoverageQualitySummary> _summarizeMatchingVerifiedRoutes({
    required RoutePoolRegionAssignment assignment,
    required int distanceBucket,
    required String styleKey,
    required bool avoidHighways,
    required String routeType,
  }) async {
    final summary = _CoverageQualitySummary();
    final inMemoryRoutes = _inMemoryRoutes;
    if (inMemoryRoutes != null) {
      for (final route in inMemoryRoutes) {
        if (!route.verified || !route.isActive) continue;
        if (!_sameText(route.countryCode, assignment.region.countryCode)) {
          continue;
        }
        if (!_sameText(route.admin1Name, assignment.region.admin1Name)) {
          continue;
        }
        if (!_nullableSameText(
          route.admin2Name,
          assignment.region.admin2Name,
        )) {
          continue;
        }
        if (!_sameText(route.cityCluster, assignment.region.cityCluster)) {
          continue;
        }
        if (!_sameText(route.routeType, routeType)) continue;
        if (route.distanceBucket != distanceBucket) continue;
        if (_normalizeStyleKeyList(route.styleTags).contains(styleKey) ==
            false) {
          continue;
        }
        if (!_highwayMatches(route, avoidHighways)) {
          continue;
        }
        summary.add(
          qualityTier: _qualityTierForRoute(route),
          fingerprint: _fingerprintForRoute(route),
        );
      }
      return summary;
    }

    final rows = await _db
        .from('route_pool')
        .select(
          'id, style_tags, avoids_highway, has_highway, admin2_name, '
          'quality_score, route_payload',
        )
        .eq('verified', true)
        .eq('is_active', true)
        .eq('country_code', assignment.region.countryCode)
        .eq('admin1_name', assignment.region.admin1Name)
        .eq('city_cluster', assignment.region.cityCluster)
        .eq('route_type', routeType)
        .eq('distance_bucket', distanceBucket);
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      if (!_nullableSameText(
        map['admin2_name'] as String?,
        assignment.region.admin2Name,
      )) {
        continue;
      }
      final tags = _normalizeStyleKeyList(_styleTagsFromRaw(map['style_tags']));
      if (!tags.contains(styleKey)) continue;
      final avoidsHighway = (map['avoids_highway'] as bool?) ?? false;
      final hasHighway = (map['has_highway'] as bool?) ?? false;
      if (avoidHighways && (!avoidsHighway || hasHighway)) {
        continue;
      }
      summary.add(
        qualityTier: _qualityTierForRawRoute(map),
        fingerprint: _fingerprintForRawRoute(map),
      );
    }
    return summary;
  }

  Future<int> _countMatchingCandidates({
    required RoutePoolRegionAssignment assignment,
    required int distanceBucket,
    required String styleKey,
    required bool avoidHighways,
    required String routeType,
  }) async {
    final inMemoryCandidates = _inMemoryCandidates;
    if (inMemoryCandidates != null) {
      return inMemoryCandidates.where((candidate) {
        return candidate.isCandidate &&
            _sameText(candidate.countryCode, assignment.region.countryCode) &&
            _sameText(candidate.admin1Name, assignment.region.admin1Name) &&
            _nullableSameText(
              candidate.admin2Name,
              assignment.region.admin2Name,
            ) &&
            _sameText(candidate.cityCluster, assignment.region.cityCluster) &&
            _sameText(candidate.routeType, routeType) &&
            candidate.distanceBucket == distanceBucket &&
            _sameText(candidate.styleKey, styleKey) &&
            candidate.avoidHighways == avoidHighways;
      }).length;
    }

    final rows = await _db
        .from('route_pool_candidates')
        .select('admin2_name')
        .eq('country_code', assignment.region.countryCode)
        .eq('admin1_name', assignment.region.admin1Name)
        .eq('city_cluster', assignment.region.cityCluster)
        .eq('route_type', routeType)
        .eq('distance_bucket', distanceBucket)
        .eq('style_key', styleKey)
        .eq('avoid_highways', avoidHighways)
        .eq('is_candidate', true);
    var count = 0;
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      if (_nullableSameText(
        map['admin2_name'] as String?,
        assignment.region.admin2Name,
      )) {
        count += 1;
      }
    }
    return count;
  }

  Future<int> _countClusterVerifiedRoutes({
    required RoutePoolRegionAssignment assignment,
    required String routeType,
  }) async {
    final inMemoryRoutes = _inMemoryRoutes;
    if (inMemoryRoutes != null) {
      return inMemoryRoutes.where((route) {
        return route.verified &&
            route.isActive &&
            _sameText(route.countryCode, assignment.region.countryCode) &&
            _sameText(route.admin1Name, assignment.region.admin1Name) &&
            _nullableSameText(route.admin2Name, assignment.region.admin2Name) &&
            _sameText(route.cityCluster, assignment.region.cityCluster) &&
            _sameText(route.routeType, routeType);
      }).length;
    }

    final rows = await _db
        .from('route_pool')
        .select('id, admin2_name')
        .eq('verified', true)
        .eq('is_active', true)
        .eq('country_code', assignment.region.countryCode)
        .eq('admin1_name', assignment.region.admin1Name)
        .eq('city_cluster', assignment.region.cityCluster)
        .eq('route_type', routeType);
    var count = 0;
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      if (_nullableSameText(
        map['admin2_name'] as String?,
        assignment.region.admin2Name,
      )) {
        count += 1;
      }
    }
    return count;
  }

  Future<int> _countClusterCandidates({
    required RoutePoolRegionAssignment assignment,
    required String routeType,
  }) async {
    final inMemoryCandidates = _inMemoryCandidates;
    if (inMemoryCandidates != null) {
      return inMemoryCandidates.where((candidate) {
        return candidate.isCandidate &&
            _sameText(candidate.countryCode, assignment.region.countryCode) &&
            _sameText(candidate.admin1Name, assignment.region.admin1Name) &&
            _nullableSameText(
              candidate.admin2Name,
              assignment.region.admin2Name,
            ) &&
            _sameText(candidate.cityCluster, assignment.region.cityCluster) &&
            _sameText(candidate.routeType, routeType);
      }).length;
    }

    final rows = await _db
        .from('route_pool_candidates')
        .select('id, admin2_name')
        .eq('country_code', assignment.region.countryCode)
        .eq('admin1_name', assignment.region.admin1Name)
        .eq('city_cluster', assignment.region.cityCluster)
        .eq('route_type', routeType)
        .eq('is_candidate', true);
    var count = 0;
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      if (_nullableSameText(
        map['admin2_name'] as String?,
        assignment.region.admin2Name,
      )) {
        count += 1;
      }
    }
    return count;
  }

  Future<_SeedJobUpsertResult> _ensureSeedJob({
    required RoutePoolRegionAssignment assignment,
    required _CoveragePolicy policy,
    required int distanceBucket,
    required String styleKey,
    required bool avoidHighways,
    required String routeType,
    required String subscriptionTier,
    int? priority,
  }) async {
    final now = DateTime.now().toUtc();
    final existing = await _loadSeedJob(
      assignment: assignment,
      distanceBucket: distanceBucket,
      styleKey: styleKey,
      avoidHighways: avoidHighways,
      routeType: routeType,
    );
    if (existing != null) {
      if (existing.isActive || existing.isCoolingDown) {
        return _SeedJobUpsertResult(
          job: existing,
          created: false,
          duplicatePrevented: true,
        );
      }
      final restarted = existing.copyWith(
        status: 'queued',
        difficultyLevel: policy.difficultyLevel,
        hardRegionStatus: policy.hardRegionStatus,
        lastRequestedAt: now,
        seedBudgetUnits: policy.seedBudgetUnits,
        seedCooldownMinutes: policy.seedCooldownMinutes,
        priority: priority ?? existing.priority,
        maxAttempts: policy.isHard ? 1 : existing.maxAttempts,
        triggeredByTier: subscriptionTier,
      );
      return _SeedJobUpsertResult(
        job: await _saveSeedJob(restarted),
        created: true,
        duplicatePrevented: false,
      );
    }

    final job = RouteSeedJob(
      routeRegionId: assignment.region.id,
      countryCode: assignment.region.countryCode,
      admin1Name: assignment.region.admin1Name,
      admin2Name: assignment.region.admin2Name,
      cityCluster: assignment.region.cityCluster,
      routeType: routeType,
      distanceBucket: distanceBucket,
      styleKey: styleKey,
      avoidHighways: avoidHighways,
      status: 'queued',
      difficultyLevel: policy.difficultyLevel,
      hardRegionStatus: policy.hardRegionStatus,
      priority: priority ?? _priorityForTier(subscriptionTier),
      maxAttempts: policy.isHard ? 1 : 3,
      lastRequestedAt: now,
      seedBudgetUnits: policy.seedBudgetUnits,
      seedCooldownMinutes: policy.seedCooldownMinutes,
      triggeredByTier: subscriptionTier,
    );
    return _SeedJobUpsertResult(
      job: await _saveSeedJob(job),
      created: true,
      duplicatePrevented: false,
    );
  }

  Future<RouteSeedJob?> _loadSeedJob({
    required RoutePoolRegionAssignment assignment,
    required int distanceBucket,
    required String styleKey,
    required bool avoidHighways,
    required String routeType,
  }) async {
    final inMemorySeedJobs = _inMemorySeedJobs;
    if (inMemorySeedJobs != null) {
      for (final job in inMemorySeedJobs) {
        if (_seedJobKeyMatches(
          job,
          assignment: assignment,
          distanceBucket: distanceBucket,
          styleKey: styleKey,
          avoidHighways: avoidHighways,
          routeType: routeType,
        )) {
          return job;
        }
      }
      return null;
    }

    final rows = await _db
        .from('route_seed_jobs')
        .select()
        .eq('country_code', assignment.region.countryCode)
        .eq('admin1_name', assignment.region.admin1Name)
        .eq('city_cluster', assignment.region.cityCluster)
        .eq('route_type', routeType)
        .eq('distance_bucket', distanceBucket)
        .eq('style_key', styleKey)
        .eq('avoid_highways', avoidHighways);
    for (final row in rows as List) {
      final job = RouteSeedJob.fromJson(row as Map<String, dynamic>);
      if (_nullableSameText(job.admin2Name, assignment.region.admin2Name)) {
        return job;
      }
    }
    return null;
  }

  Future<RouteSeedJob> _saveSeedJob(RouteSeedJob job) async {
    final inMemorySeedJobs = _inMemorySeedJobs;
    if (inMemorySeedJobs != null) {
      final index = inMemorySeedJobs.indexWhere((item) {
        return _sameText(item.countryCode, job.countryCode) &&
            _sameText(item.admin1Name, job.admin1Name) &&
            _nullableSameText(item.admin2Name, job.admin2Name) &&
            _sameText(item.cityCluster, job.cityCluster) &&
            _sameText(item.routeType, job.routeType) &&
            item.distanceBucket == job.distanceBucket &&
            _sameText(item.styleKey, job.styleKey) &&
            item.avoidHighways == job.avoidHighways;
      });
      if (index >= 0) {
        inMemorySeedJobs[index] = job;
      } else {
        inMemorySeedJobs.add(job);
      }
      return job;
    }

    final assignment = RoutePoolRegionAssignment(
      region: RouteRegion(
        id: job.routeRegionId,
        countryCode: job.countryCode,
        admin1Name: job.admin1Name,
        admin2Name: job.admin2Name,
        cityCluster: job.cityCluster,
        centerLat: 0,
        centerLng: 0,
      ),
      distanceToCenterKm: 0,
    );
    final existing = await _loadSeedJob(
      assignment: assignment,
      distanceBucket: job.distanceBucket,
      styleKey: job.styleKey,
      avoidHighways: job.avoidHighways,
      routeType: job.routeType,
    );
    if (existing?.id != null) {
      final payload = _seedJobPayloadForDb(job)..remove('id');
      final rows = await _db
          .from('route_seed_jobs')
          .update(payload)
          .eq('id', existing!.id!)
          .select()
          .limit(1);
      return RouteSeedJob.fromJson(
        Map<String, dynamic>.from((rows as List).first as Map),
      );
    }
    final rows = await _db
        .from('route_seed_jobs')
        .insert(_seedJobPayloadForDb(job))
        .select()
        .limit(1);
    return RouteSeedJob.fromJson(
      Map<String, dynamic>.from((rows as List).first as Map),
    );
  }

  Future<_CandidateUpsertResult> _upsertCandidate(
    RoutePoolCandidate candidate,
  ) async {
    final inMemoryCandidates = _inMemoryCandidates;
    if (inMemoryCandidates != null) {
      final existingPoolRoute =
          _inMemoryRoutes?.any(
            (route) => _sameText(
              _fingerprintForRoute(route),
              candidate.routeFingerprint,
            ),
          ) ??
          false;
      if (existingPoolRoute) {
        return _CandidateUpsertResult(
          saved: false,
          duplicate: true,
          candidate: candidate,
          duplicateSource: 'pool',
        );
      }
      final existingIndex = inMemoryCandidates.indexWhere(
        (item) => _sameText(item.routeFingerprint, candidate.routeFingerprint),
      );
      if (existingIndex >= 0) {
        return _CandidateUpsertResult(
          saved: false,
          duplicate: true,
          candidate: inMemoryCandidates[existingIndex],
          duplicateSource: 'candidate',
        );
      }
      inMemoryCandidates.add(candidate);
      return _CandidateUpsertResult(
        saved: true,
        duplicate: false,
        candidate: candidate,
      );
    }

    final poolRows = await _db
        .from('route_pool')
        .select('route_fingerprint')
        .eq('route_fingerprint', candidate.routeFingerprint)
        .limit(1);
    if ((poolRows as List).isNotEmpty) {
      return _CandidateUpsertResult(
        saved: false,
        duplicate: true,
        candidate: candidate,
        duplicateSource: 'pool',
      );
    }

    final rows = await _db
        .from('route_pool_candidates')
        .select()
        .eq('route_fingerprint', candidate.routeFingerprint)
        .limit(1);
    if ((rows as List).isNotEmpty) {
      return _CandidateUpsertResult(
        saved: false,
        duplicate: true,
        candidate: RoutePoolCandidate.fromJson(
          Map<String, dynamic>.from(rows.first as Map),
        ),
        duplicateSource: 'candidate',
      );
    }
    try {
      final inserted = await _db
          .from('route_pool_candidates')
          .insert(candidate.toJson())
          .select()
          .limit(1);
      return _CandidateUpsertResult(
        saved: true,
        duplicate: false,
        candidate: RoutePoolCandidate.fromJson(
          Map<String, dynamic>.from((inserted as List).first as Map),
        ),
      );
    } on PostgrestException catch (error) {
      if (_isDuplicateFingerprintError(error)) {
        final existing = await _db
            .from('route_pool_candidates')
            .select()
            .eq('route_fingerprint', candidate.routeFingerprint)
            .limit(1);
        if ((existing as List).isNotEmpty) {
          return _CandidateUpsertResult(
            saved: false,
            duplicate: true,
            candidate: RoutePoolCandidate.fromJson(
              Map<String, dynamic>.from(existing.first as Map),
            ),
            duplicateSource: 'candidate',
          );
        }
        return _CandidateUpsertResult(
          saved: false,
          duplicate: true,
          candidate: candidate,
          duplicateSource: 'unknown',
        );
      }
      return _CandidateUpsertResult(
        saved: false,
        duplicate: false,
        candidate: candidate,
        saveErrorType: error.runtimeType.toString(),
        saveErrorCode: error.code,
        saveErrorReason: error.message,
      );
    }
  }

  static bool _isDuplicateFingerprintError(PostgrestException error) {
    final code = error.code?.toLowerCase();
    if (code == '23505') return true;
    final message = error.message.toLowerCase();
    return message.contains('duplicate') ||
        message.contains('unique') ||
        message.contains('route_fingerprint');
  }

  static bool _coverageKeyMatches(
    RoutePoolCoverage coverage, {
    required RoutePoolRegionAssignment assignment,
    required int distanceBucket,
    required String styleKey,
    required bool avoidHighways,
    required String routeType,
  }) {
    return _sameText(coverage.countryCode, assignment.region.countryCode) &&
        _sameText(coverage.admin1Name, assignment.region.admin1Name) &&
        _nullableSameText(coverage.admin2Name, assignment.region.admin2Name) &&
        _sameText(coverage.cityCluster, assignment.region.cityCluster) &&
        _sameText(coverage.routeType, routeType) &&
        coverage.distanceBucket == distanceBucket &&
        _sameText(coverage.styleKey, styleKey) &&
        coverage.avoidHighways == avoidHighways;
  }

  static bool _seedJobKeyMatches(
    RouteSeedJob job, {
    required RoutePoolRegionAssignment assignment,
    required int distanceBucket,
    required String styleKey,
    required bool avoidHighways,
    required String routeType,
  }) {
    return _sameText(job.countryCode, assignment.region.countryCode) &&
        _sameText(job.admin1Name, assignment.region.admin1Name) &&
        _nullableSameText(job.admin2Name, assignment.region.admin2Name) &&
        _sameText(job.cityCluster, assignment.region.cityCluster) &&
        _sameText(job.routeType, routeType) &&
        job.distanceBucket == distanceBucket &&
        _sameText(job.styleKey, styleKey) &&
        job.avoidHighways == avoidHighways;
  }

  static RoutePoolRequiredCombination? _requiredCombinationFor({
    required int distanceBucket,
    required String styleKey,
    required bool avoidHighways,
  }) {
    for (final combination in mvpRequiredCombinations) {
      if (combination.distanceBucket == distanceBucket &&
          combination.styleKey == styleKey &&
          combination.avoidHighways == avoidHighways) {
        return combination;
      }
    }
    return null;
  }

  static _CoveragePolicy _coveragePolicyFor({
    required RouteRegion region,
    RoutePoolCoverage? coverage,
    RoutePoolRequiredCombination? requiredCombination,
  }) {
    final requiredVerifiedCount = requiredCombination?.requiredVerifiedCount;
    final minVerifiedCount = math.max(
      0,
      math.min(
        defaultMaxPoolSize,
        requiredVerifiedCount ?? defaultMinVerifiedPerCell,
      ),
    );
    final targetPoolSize = math.max(minVerifiedCount, defaultTargetPoolSize);
    final maxPoolSize = math.max(targetPoolSize, defaultMaxPoolSize);
    final candidateBufferLimit = math.max(
      0,
      coverage?.candidateBufferLimit ?? defaultCandidateBufferLimit,
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
    return _CoveragePolicy(
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

  static String _deriveClusterCoverageStatus({
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

  static RoutePoolCoverage _applyCoveragePolicySnapshot(
    RoutePoolCoverage coverage, {
    required _CoveragePolicy policy,
  }) {
    return coverage.copyWith(
      difficultyLevel: policy.difficultyLevel,
      hardRegionStatus: policy.hardRegionStatus,
      bootstrapEnabled: policy.bootstrapEnabled,
      curatedSeedPreferred: policy.curatedSeedPreferred,
      minVerifiedCount: policy.minVerifiedCount,
      targetPoolSize: policy.targetPoolSize,
      maxPoolSize: policy.maxPoolSize,
      candidateBufferLimit: policy.candidateBufferLimit,
      acceptableReserveLimitPercent: policy.acceptableReserveLimitPercent,
      healthyThreshold: policy.healthyThreshold,
      thinThreshold: policy.thinThreshold,
      seedBudgetUnits: policy.seedBudgetUnits,
      seedCooldownMinutes: policy.seedCooldownMinutes,
    );
  }

  static bool _coveragePolicyChanged(
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

  static bool _shouldCreateSeedJob({
    required _CoveragePolicy policy,
    required RoutePoolCoverage coverage,
    required RouteSeedJob? existingSeedJob,
  }) {
    if (_coverageMeetsMinimum(policy: policy, coverage: coverage)) {
      return false;
    }
    if (coverage.currentVerifiedCount >= policy.maxPoolSize) return false;
    if (coverage.currentCandidateCount >= policy.candidateBufferLimit) {
      return false;
    }
    if (!policy.bootstrapEnabled) return false;
    if (policy.isHard && policy.curatedSeedPreferred) return false;
    if (policy.seedBudgetUnits <= 0) return false;
    if (existingSeedJob == null) return true;
    if (_seedJobBlocksNewJob(existingSeedJob)) return false;
    if (existingSeedJob.failureCount >= existingSeedJob.maxAttempts) {
      return false;
    }
    if (existingSeedJob.attemptCount >= existingSeedJob.maxAttempts) {
      return false;
    }
    return true;
  }

  static bool _seedJobBlocksNewJob(RouteSeedJob seedJob) {
    return seedJob.isActive ||
        seedJob.isCoolingDown ||
        seedJob.isBudgetPaused ||
        _seedJobAttemptBudgetExceeded(seedJob);
  }

  static bool _seedJobAttemptBudgetExceeded(RouteSeedJob seedJob) {
    if (seedJob.dailyAttemptBudget <= 0 || seedJob.monthlyAttemptBudget <= 0) {
      return true;
    }
    final now = DateTime.now().toUtc();
    final today = _dateOnlyKey(now);
    final month = _monthOnlyKey(now);
    final dailyCount = _dateOnlyKey(seedJob.budgetWindowDate) == today
        ? seedJob.dailyAttemptCount
        : 0;
    final monthlyCount = _monthOnlyKey(seedJob.budgetWindowMonth) == month
        ? seedJob.monthlyAttemptCount
        : 0;
    return dailyCount >= seedJob.dailyAttemptBudget ||
        monthlyCount >= seedJob.monthlyAttemptBudget;
  }

  static String _healingStatusForSeedJob(RouteSeedJob seedJob) {
    if (seedJob.status == 'running') return 'healing_running';
    if (seedJob.status == 'queued') return 'healing_queued';
    if (seedJob.status == 'cooldown') return 'healing_failed_cooldown';
    if (seedJob.status == 'paused_budget') return 'healing_paused_budget';
    if (seedJob.hardRegionStatus == 'curated_needed') {
      return 'hard_region_curated_needed';
    }
    return 'idle';
  }

  static String? _dateOnlyKey(DateTime? value) {
    if (value == null) return null;
    return value.toUtc().toIso8601String().split('T').first;
  }

  static String? _monthOnlyKey(DateTime? value) {
    final date = _dateOnlyKey(value);
    if (date == null || date.length < 8) return null;
    return '${date.substring(0, 8)}01';
  }

  static Map<String, dynamic> _coveragePayloadForDb(
    RoutePoolCoverage coverage,
  ) {
    final payload = coverage.toJson();
    final now = DateTime.now().toUtc();
    payload['healing_budget_window_date'] ??= _dateOnlyKey(now);
    payload['healing_budget_window_month'] ??= _monthOnlyKey(now);
    return payload;
  }

  static Map<String, dynamic> _seedJobPayloadForDb(RouteSeedJob job) {
    final payload = job.toJson();
    final now = DateTime.now().toUtc();
    payload['budget_window_date'] ??= _dateOnlyKey(now);
    payload['budget_window_month'] ??= _monthOnlyKey(now);
    return payload;
  }

  static String _deriveCoverageStatus({
    required _CoveragePolicy policy,
    required int currentVerifiedCount,
    required int idealCount,
    required int goodCount,
    required int acceptableCount,
    required int distinctFingerprintCount,
    required bool hasBootstrapPending,
    required bool isCooldown,
  }) {
    if (currentVerifiedCount > policy.maxPoolSize) return 'overfull';
    final goodEnoughCount = idealCount + goodCount;
    final acceptableLimit = _acceptableReserveLimit(
      currentVerifiedCount: currentVerifiedCount,
      acceptableReserveLimitPercent: policy.acceptableReserveLimitPercent,
    );
    final acceptableOverLimit =
        currentVerifiedCount > 0 && acceptableCount > acceptableLimit;
    final minimumMet =
        currentVerifiedCount >= policy.minVerifiedCount &&
        distinctFingerprintCount >= policy.minDistinctFingerprints &&
        goodEnoughCount >= policy.minVerifiedCount &&
        !acceptableOverLimit;
    if (minimumMet && currentVerifiedCount >= policy.targetPoolSize) {
      return 'target_met';
    }
    if (minimumMet) return 'healthy';
    if (currentVerifiedCount >= policy.minVerifiedCount &&
        (goodEnoughCount < policy.minVerifiedCount || acceptableOverLimit)) {
      return 'quality_thin';
    }
    if (policy.isHard) {
      if (hasBootstrapPending || isCooldown) return 'bootstrap_limited';
      if (currentVerifiedCount > 0) return 'hard_region_thin';
      if (!policy.bootstrapEnabled ||
          policy.curatedSeedPreferred ||
          policy.hardRegionStatus == 'curated_needed') {
        return 'hard_region_curated_needed';
      }
      return 'empty';
    }
    if (isCooldown) return 'cooldown';
    if (hasBootstrapPending) return 'warming_up';
    if (currentVerifiedCount > 0) return 'thin';
    return 'empty';
  }

  static bool _coverageMeetsMinimum({
    required _CoveragePolicy policy,
    required RoutePoolCoverage coverage,
  }) {
    final goodEnoughCount = coverage.idealCount + coverage.goodCount;
    final acceptableLimit = _acceptableReserveLimit(
      currentVerifiedCount: coverage.currentVerifiedCount,
      acceptableReserveLimitPercent: policy.acceptableReserveLimitPercent,
    );
    return coverage.currentVerifiedCount >= policy.minVerifiedCount &&
        coverage.distinctFingerprintCount >= policy.minDistinctFingerprints &&
        goodEnoughCount >= policy.minVerifiedCount &&
        coverage.acceptableCount <= acceptableLimit;
  }

  static int _missingMinimumCoverageCount({
    required _CoveragePolicy policy,
    required RoutePoolCoverage coverage,
  }) {
    if (_coverageMeetsMinimum(policy: policy, coverage: coverage)) return 0;
    final missingVerified = math.max(
      0,
      policy.minVerifiedCount - coverage.currentVerifiedCount,
    );
    final missingDistinct = math.max(
      0,
      policy.minDistinctFingerprints - coverage.distinctFingerprintCount,
    );
    final missingGoodEnough = math.max(
      0,
      policy.minVerifiedCount - (coverage.idealCount + coverage.goodCount),
    );
    return math.max(
      missingVerified,
      math.max(missingDistinct, missingGoodEnough),
    );
  }

  static int _acceptableReserveLimit({
    required int currentVerifiedCount,
    required int acceptableReserveLimitPercent,
  }) {
    if (currentVerifiedCount <= 0 || acceptableReserveLimitPercent <= 0) {
      return 0;
    }
    return (currentVerifiedCount * (acceptableReserveLimitPercent / 100))
        .floor();
  }

  static double _candidateLocalityScore({required double distanceToCenterKm}) {
    return math.max(0.0, 100.0 - (distanceToCenterKm * 5.0));
  }

  static int _priorityForTier(String subscriptionTier) {
    switch (subscriptionTier.trim().toLowerCase()) {
      case 'premium':
        return 30;
      case 'basic':
        return 20;
      case 'free':
      default:
        return 10;
    }
  }

  static int _seedJobPriority({
    required String subscriptionTier,
    required RoutePoolRequiredCombination? requiredCombination,
    required int currentVerifiedCount,
  }) {
    final tierPriority = _priorityForTier(subscriptionTier);
    if (requiredCombination == null) return tierPriority;

    final missingCount = math.max(
      0,
      requiredCombination.requiredVerifiedCount - currentVerifiedCount,
    );
    final bucketPriority = switch (requiredCombination.distanceBucket) {
      50 => 40,
      75 => 35,
      100 => 25,
      _ => 10,
    };
    final stylePriority = switch (requiredCombination.styleKey) {
      'sport_mode' => 30,
      'kurvenjagd' => 30,
      'entdecker' => 24,
      'abendrunde' => 18,
      _ => 10,
    };
    return tierPriority + bucketPriority + stylePriority + (missingCount * 10);
  }

  static String _normalizeStyleKey(String style) {
    final cleaned = style
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'standard' : cleaned;
  }

  static String _cellKeyPart(String? value) {
    return (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  }

  static List<String> _normalizeStyleKeyList(List<String> styles) {
    return styles.map(_normalizeStyleKey).toList(growable: false);
  }

  static List<String> _styleTagsFromRaw(Object? raw) {
    if (raw is List) {
      return raw.map((item) => item.toString()).toList(growable: false);
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  static String _qualityTierForRoute(RoutePoolEntry route) {
    final payloadTier = route.routePayload['quality_tier']?.toString();
    return _normalizeQualityTier(payloadTier, route.qualityScore);
  }

  static String _qualityTierForRawRoute(Map<String, dynamic> route) {
    final payload = route['route_payload'];
    final payloadTier = payload is Map
        ? payload['quality_tier']?.toString()
        : null;
    final qualityScore = (route['quality_score'] as num?)?.toDouble() ?? 0.0;
    return _normalizeQualityTier(payloadTier, qualityScore);
  }

  static String _normalizeQualityTier(String? rawTier, double qualityScore) {
    final tier = (rawTier ?? '').trim().toLowerCase();
    if (tier == 'ideal' ||
        tier == 'good' ||
        tier == 'acceptable' ||
        tier == 'rejected') {
      return tier;
    }
    if (qualityScore >= 92) return 'ideal';
    if (qualityScore >= 82) return 'good';
    if (qualityScore >= 70) return 'acceptable';
    return 'rejected';
  }

  static String _fingerprintForRoute(RoutePoolEntry route) {
    final payload = route.routePayload;
    return (payload['route_fingerprint'] ??
            payload['fingerprint'] ??
            payload['seed_key'] ??
            route.id)
        .toString();
  }

  static String _fingerprintForRawRoute(Map<String, dynamic> route) {
    final payload = route['route_payload'];
    if (payload is Map) {
      final fingerprint =
          payload['route_fingerprint'] ??
          payload['fingerprint'] ??
          payload['seed_key'];
      if (fingerprint != null) return fingerprint.toString();
    }
    return route['id']?.toString() ?? '';
  }

  static double haversineDistanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static bool _styleMatches(RoutePoolEntry candidate, String style) {
    return candidate.styleTags.any((tag) => _sameText(tag, style));
  }

  static bool _relaxedStyleCompatible(RoutePoolEntry candidate, String style) {
    final requested = _normalizeStyleKey(style);
    final candidateKeys = _normalizeStyleKeyList(candidate.styleTags);
    if (candidateKeys.contains(requested)) return true;

    final allowed = switch (requested) {
      'sport_mode' || 'sport' => const {'entdecker', 'abendrunde'},
      'kurvenjagd' || 'kurvenreich' || 'alpenstrassen' => const {'entdecker'},
      'abendrunde' || 'panorama' => const {'sport_mode', 'sport'},
      'entdecker' ||
      'zufall' => const {'sport_mode', 'sport', 'kurvenjagd', 'abendrunde'},
      _ => const <String>{},
    };
    return candidateKeys.any(allowed.contains);
  }

  static double _poolStyleFitScore(RoutePoolEntry candidate, String style) {
    final coordinates = _coordinatesFromGeometry(candidate.geometry);
    if (coordinates.length < 6) {
      return _styleMatches(candidate, style) ? 62.0 : 38.0;
    }
    final styleConfig = RouteStyleConfig.forMode(style);
    return styleConfig.scoreStyleFit(
      coordinates: coordinates,
      distanceKm: candidate.distanceKm,
      durationSeconds: candidate.durationSeconds,
    );
  }

  static List<List<double>> _coordinatesFromGeometry(
    Map<String, dynamic> geometry,
  ) {
    final rawCoordinates = geometry['coordinates'];
    if (geometry['type'] != 'LineString' || rawCoordinates is! List) {
      return const [];
    }
    final coordinates = <List<double>>[];
    for (final point in rawCoordinates) {
      if (point is List && point.length >= 2) {
        final lng = point[0];
        final lat = point[1];
        if (lng is num && lat is num) {
          coordinates.add([lng.toDouble(), lat.toDouble()]);
        }
      }
    }
    return coordinates;
  }

  static bool _highwayMatches(RoutePoolEntry candidate, bool avoidHighways) {
    if (avoidHighways) return candidate.avoidsHighway && !candidate.hasHighway;
    return true;
  }

  static bool _locationScopeMatches(
    RoutePoolQuery query,
    RoutePoolEntry candidate,
  ) {
    final sameCountry = _sameText(
      query.normalizedCountryCode,
      candidate.countryCode,
    );
    if (!sameCountry && !query.crossBorderAllowed) return false;
    if (!sameCountry) return query.crossBorderAllowed;
    return _sameText(query.admin1Name, candidate.admin1Name);
  }

  static _RadiusDecision? _allowedRadiusFor(
    RoutePoolQuery query,
    RoutePoolEntry candidate,
    List<RouteRegion> regions,
  ) {
    if (query.routeType == 'ROUND_TRIP') {
      if (_sameCity(query, candidate) ||
          _sameAdmin2(query, candidate) ||
          _sameText(query.admin1Name, candidate.admin1Name)) {
        return const _RadiusDecision(
          roundTripHardStartMaxKm,
          'roundtrip_local',
        );
      }
      if (query.crossBorderAllowed) {
        return const _RadiusDecision(
          roundTripHardStartMaxKm,
          'roundtrip_cross_border',
        );
      }
      return null;
    }
    if (_sameCity(query, candidate)) {
      return const _RadiusDecision(localClusterMaxKm, 'local_cluster');
    }
    if (_sameAdmin2(query, candidate)) {
      return const _RadiusDecision(nearbyClusterMaxKm, 'nearby_cluster');
    }
    if (_sameText(query.admin1Name, candidate.admin1Name)) {
      final region = _matchingRegion(candidate, regions);
      final regionalLimit = math.min(
        math.max(regionalMaxKm, region?.fallbackRadiusKm ?? regionalMaxKm),
        maxExtendedRegionalKm,
      );
      return _RadiusDecision(regionalLimit, 'regional');
    }
    if (query.crossBorderAllowed) {
      return const _RadiusDecision(regionalMaxKm, 'cross_border');
    }
    return null;
  }

  static RouteRegion? _matchingRegion(
    RoutePoolEntry candidate,
    List<RouteRegion> regions,
  ) {
    for (final region in regions) {
      if (_sameText(region.countryCode, candidate.countryCode) &&
          _sameText(region.admin1Name, candidate.admin1Name) &&
          _sameText(region.cityCluster, candidate.cityCluster) &&
          _nullableSameText(region.admin2Name, candidate.admin2Name)) {
        return region;
      }
    }
    return null;
  }

  static RouteRegion? _nearestRegionFor(
    double userLat,
    double userLng,
    List<RouteRegion> regions,
  ) {
    RouteRegion? best;
    var bestDistanceKm = double.infinity;
    for (final region in regions) {
      if (!region.isActive) continue;
      final distanceKm = haversineDistanceKm(
        userLat,
        userLng,
        region.centerLat,
        region.centerLng,
      );
      final allowedKm = math.min(
        math.max(regionalMaxKm, region.fallbackRadiusKm),
        maxExtendedRegionalKm,
      );
      if (distanceKm > allowedKm) continue;
      if (distanceKm < bestDistanceKm) {
        bestDistanceKm = distanceKm;
        best = region;
      }
    }
    return best;
  }

  static RouteRegion? _resolveNearestRegion({
    required double userLat,
    required double userLng,
    required List<RouteRegion> regions,
    String? preferredCountryCode,
    String? preferredAdmin1Name,
    String? preferredAdmin2Name,
    String? preferredCityCluster,
  }) {
    final preferredRegions = regions
        .where((region) {
          if (!region.isActive) return false;
          if (preferredCountryCode != null &&
              preferredCountryCode.trim().isNotEmpty &&
              !_sameText(preferredCountryCode, region.countryCode)) {
            return false;
          }
          if (preferredAdmin1Name != null &&
              preferredAdmin1Name.trim().isNotEmpty &&
              !_sameText(preferredAdmin1Name, region.admin1Name)) {
            return false;
          }
          if (preferredAdmin2Name != null &&
              preferredAdmin2Name.trim().isNotEmpty &&
              !_sameText(preferredAdmin2Name, region.admin2Name)) {
            return false;
          }
          if (preferredCityCluster != null &&
              preferredCityCluster.trim().isNotEmpty &&
              !_sameText(preferredCityCluster, region.cityCluster)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    final preferredNearest = preferredRegions.isEmpty
        ? null
        : _nearestRegionFor(userLat, userLng, preferredRegions);
    return preferredNearest ?? _nearestRegionFor(userLat, userLng, regions);
  }

  static bool _sameCity(RoutePoolQuery query, RoutePoolEntry candidate) {
    final cityCluster = query.cityCluster;
    return cityCluster != null && _sameText(cityCluster, candidate.cityCluster);
  }

  static bool _sameAdmin2(RoutePoolQuery query, RoutePoolEntry candidate) {
    final admin2Name = query.admin2Name;
    return admin2Name != null && _sameText(admin2Name, candidate.admin2Name);
  }

  static bool _nullableSameText(String? left, String? right) {
    if (left == null && right == null) return true;
    if (left == null || right == null) return false;
    return _sameText(left, right);
  }

  static bool _sameText(String? left, String? right) {
    return (left ?? '').trim().toLowerCase() ==
        (right ?? '').trim().toLowerCase();
  }

  static int _boolScore(bool value) => value ? 1 : 0;

  static double _toRadians(double degrees) => degrees * (math.pi / 180.0);

  static _Bounds _boundingBoxFor(
    double latitude,
    double longitude,
    double radiusKm,
  ) {
    final latDelta = radiusKm / 111.32;
    final cosLatitude = math.cos(_toRadians(latitude)).abs();
    final safeCosLatitude = cosLatitude < 0.1 ? 0.1 : cosLatitude;
    final lngDelta = radiusKm / (111.32 * safeCosLatitude);
    return _Bounds(
      minLat: latitude - latDelta,
      maxLat: latitude + latDelta,
      minLng: longitude - lngDelta,
      maxLng: longitude + lngDelta,
    );
  }

  static double _maxSearchRadiusForRouteType(String routeType) {
    return routeType == 'ROUND_TRIP'
        ? roundTripHardStartMaxKm
        : maxExtendedRegionalKm;
  }

  static double _maxRegionSearchRadiusForRouteType(String routeType) {
    return routeType == 'ROUND_TRIP'
        ? roundTripHardStartMaxKm
        : maxExtendedRegionalKm;
  }

  static int _effectiveCandidateLimit(String routeType, int candidateLimit) {
    final normalizedLimit = candidateLimit.clamp(1, 200);
    return routeType == 'ROUND_TRIP'
        ? math.min<int>(normalizedLimit, 80)
        : math.min<int>(normalizedLimit, 140);
  }

  static String _roundTripRadiusScope(
    RoutePoolQuery query,
    RoutePoolEntry candidate,
    double distanceKm,
  ) {
    if (distanceKm <= roundTripIdealStartMaxKm && _sameCity(query, candidate)) {
      return 'local_cluster';
    }
    if (distanceKm <= roundTripHardStartMaxKm) {
      if (_sameAdmin2(query, candidate) || _sameCity(query, candidate)) {
        return 'nearby_cluster';
      }
      return 'regional_nearby';
    }
    return 'too_far';
  }
}

class _RadiusDecision {
  const _RadiusDecision(this.allowedRadiusKm, this.scope);

  final double allowedRadiusKm;
  final String scope;
}

class _Bounds {
  const _Bounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
}

class _CoverageQualitySummary {
  int verifiedCount = 0;
  int idealCount = 0;
  int goodCount = 0;
  int acceptableCount = 0;
  int rejectedCount = 0;

  final Set<String> _fingerprints = <String>{};

  int get distinctFingerprintCount => _fingerprints.length;

  void add({required String qualityTier, required String fingerprint}) {
    verifiedCount += 1;
    if (fingerprint.trim().isNotEmpty) {
      _fingerprints.add(fingerprint.trim());
    }
    if (qualityTier == 'ideal') {
      idealCount += 1;
    } else if (qualityTier == 'good') {
      goodCount += 1;
    } else if (qualityTier == 'acceptable') {
      acceptableCount += 1;
    } else {
      rejectedCount += 1;
    }
  }
}

class _SeedJobUpsertResult {
  const _SeedJobUpsertResult({
    required this.job,
    required this.created,
    required this.duplicatePrevented,
  });

  final RouteSeedJob job;
  final bool created;
  final bool duplicatePrevented;
}

class _CandidateUpsertResult {
  const _CandidateUpsertResult({
    required this.saved,
    required this.duplicate,
    required this.candidate,
    this.duplicateSource,
    this.saveErrorType,
    this.saveErrorCode,
    this.saveErrorReason,
  });

  final bool saved;
  final bool duplicate;
  final RoutePoolCandidate candidate;
  final String? duplicateSource;
  final String? saveErrorType;
  final String? saveErrorCode;
  final String? saveErrorReason;
}
