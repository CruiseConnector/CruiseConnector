import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/domain/models/route_pool_candidate.dart';
import 'package:cruise_connect/domain/models/route_pool_coverage.dart';
import 'package:cruise_connect/domain/models/route_pool_entry.dart';
import 'package:cruise_connect/domain/models/route_region.dart';
import 'package:cruise_connect/domain/models/route_seed_job.dart';

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
    required this.targetPoolSize,
    required this.maxPoolSize,
    required this.currentVerifiedCount,
    required this.currentCandidateCount,
    required this.seedJobCreated,
    required this.duplicateJobPrevented,
    required this.poolHealthy,
    required this.poolFull,
    required this.bootstrapPending,
    this.seedJobStatus,
    this.seedJobError,
  });

  final RoutePoolRegionAssignment? assignment;
  final RoutePoolCoverage? coverage;
  final String coverageStatus;
  final int targetPoolSize;
  final int maxPoolSize;
  final int currentVerifiedCount;
  final int currentCandidateCount;
  final bool seedJobCreated;
  final bool duplicateJobPrevented;
  final bool poolHealthy;
  final bool poolFull;
  final bool bootstrapPending;
  final String? seedJobStatus;
  final String? seedJobError;

  bool get shouldSurfaceWarmup =>
      coverageStatus == 'warming_up' ||
      coverageStatus == 'cooldown' ||
      coverageStatus == 'empty';

  Map<String, dynamic> toMeta() {
    return {
      'coverage_status': coverageStatus,
      'pool_bootstrap_pending': bootstrapPending,
      'seed_job_created': seedJobCreated,
      'duplicate_job_prevented': duplicateJobPrevented,
      'seed_job_status': seedJobStatus,
      'seed_job_error': seedJobError,
      'chosen_cluster': assignment?.region.cityCluster,
      'country_code': assignment?.region.countryCode,
      'admin1_name': assignment?.region.admin1Name,
      'admin2_name': assignment?.region.admin2Name,
      'new_cluster_created': assignment?.newClusterCreated ?? false,
      'chosen_cluster_distance_km': assignment == null
          ? null
          : double.parse(assignment!.distanceToCenterKm.toStringAsFixed(2)),
      'target_pool_size': targetPoolSize,
      'max_pool_size': maxPoolSize,
      'current_verified_count': currentVerifiedCount,
      'current_candidate_count': currentCandidateCount,
      'pool_healthy': poolHealthy,
      'pool_full': poolFull,
      'retry_recommended': shouldSurfaceWarmup,
      'region_warming_up': shouldSurfaceWarmup,
    };
  }
}

class RoutePoolCandidateSaveResult {
  const RoutePoolCandidateSaveResult({
    required this.saved,
    required this.duplicate,
    required this.poolFull,
    this.assignment,
    this.candidate,
  });

  final bool saved;
  final bool duplicate;
  final bool poolFull;
  final RoutePoolRegionAssignment? assignment;
  final RoutePoolCandidate? candidate;
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
  static const int defaultTargetPoolSize = 15;
  static const int defaultMaxPoolSize = 20;
  static const Duration coverageRefreshTtl = Duration(minutes: 15);
  static const Duration defaultSeedJobCooldown = Duration(minutes: 20);

  final SupabaseClient? _client;
  final List<RoutePoolEntry>? _inMemoryRoutes;
  final List<RouteRegion>? _inMemoryRegions;
  final List<RoutePoolCoverage>? _inMemoryCoverage;
  final List<RouteSeedJob>? _inMemorySeedJobs;
  final List<RoutePoolCandidate>? _inMemoryCandidates;

  SupabaseClient get _db => _client ?? Supabase.instance.client;

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
        targetPoolSize: defaultTargetPoolSize,
        maxPoolSize: defaultMaxPoolSize,
        currentVerifiedCount: 0,
        currentCandidateCount: 0,
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
        targetPoolSize: defaultTargetPoolSize,
        maxPoolSize: defaultMaxPoolSize,
        currentVerifiedCount: 0,
        currentCandidateCount: 0,
        seedJobCreated: false,
        duplicateJobPrevented: false,
        poolHealthy: false,
        poolFull: false,
        bootstrapPending: false,
      );
    }

    final styleKey = _normalizeStyleKey(style);
    var coverage = await _loadOrRefreshCoverage(
      assignment: assignment,
      distanceBucket: distanceBucket,
      styleKey: styleKey,
      avoidHighways: avoidHighways,
      routeType: routeType,
    );

    var seedJobCreated = false;
    var duplicateJobPrevented = false;
    RouteSeedJob? seedJob;
    if (createSeedJob && coverage.currentVerifiedCount < coverage.targetPoolSize) {
      final jobResult = await _ensureSeedJob(
        assignment: assignment,
        distanceBucket: distanceBucket,
        styleKey: styleKey,
        avoidHighways: avoidHighways,
        routeType: routeType,
        subscriptionTier: subscriptionTier,
      );
      seedJob = jobResult.job;
      seedJobCreated = jobResult.created;
      duplicateJobPrevented = jobResult.duplicatePrevented;
      coverage = await _upsertCoverage(
        coverage.copyWith(
          coverageStatus: _deriveCoverageStatus(
            currentVerifiedCount: coverage.currentVerifiedCount,
            targetPoolSize: coverage.targetPoolSize,
            hasBootstrapPending: true,
            isCooldown: seedJob.isCoolingDown,
          ),
          lastBootstrapRequestedAt:
              seedJob.lastRequestedAt ?? DateTime.now().toUtc(),
          bootstrapCooldownUntil: seedJob.cooldownUntil,
          lastError: seedJob.lastError,
        ),
      );
    } else {
      seedJob = await _loadSeedJob(
        assignment: assignment,
        distanceBucket: distanceBucket,
        styleKey: styleKey,
        avoidHighways: avoidHighways,
        routeType: routeType,
      );
    }

    final hasBootstrapPending =
        seedJob != null && (seedJob.isActive || seedJob.isCoolingDown);
    final coverageStatus = _deriveCoverageStatus(
      currentVerifiedCount: coverage.currentVerifiedCount,
      targetPoolSize: coverage.targetPoolSize,
      hasBootstrapPending: hasBootstrapPending,
      isCooldown: seedJob?.isCoolingDown ?? false,
    );
    final syncedCoverage = coverage.coverageStatus == coverageStatus
        ? coverage
        : await _upsertCoverage(
            coverage.copyWith(
              coverageStatus: coverageStatus,
              bootstrapCooldownUntil: seedJob?.cooldownUntil,
              lastError: seedJob?.lastError,
            ),
          );

    return RoutePoolCoverageCheck(
      assignment: assignment,
      coverage: syncedCoverage,
      coverageStatus: coverageStatus,
      targetPoolSize: syncedCoverage.targetPoolSize,
      maxPoolSize: syncedCoverage.maxPoolSize,
      currentVerifiedCount: syncedCoverage.currentVerifiedCount,
      currentCandidateCount: syncedCoverage.currentCandidateCount,
      seedJobCreated: seedJobCreated,
      duplicateJobPrevented: duplicateJobPrevented,
      poolHealthy: syncedCoverage.currentVerifiedCount >=
          syncedCoverage.targetPoolSize,
      poolFull:
          syncedCoverage.currentVerifiedCount >= syncedCoverage.maxPoolSize,
      bootstrapPending: hasBootstrapPending,
      seedJobStatus: seedJob?.status,
      seedJobError: seedJob?.lastError,
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
    final poolFull = coverage.currentVerifiedCount >= coverage.maxPoolSize;
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
      isCandidate: true,
      isVerifiedPool: false,
      geometry: geometry,
      routePayload: routePayload,
    );
    final saveResult = await _upsertCandidate(candidate);
    if (!saveResult.saved) {
      return RoutePoolCandidateSaveResult(
        saved: false,
        duplicate: saveResult.duplicate,
        poolFull: poolFull,
        assignment: assignment,
        candidate: saveResult.candidate,
      );
    }

    await _loadOrRefreshCoverage(
      assignment: assignment,
      distanceBucket: distanceBucket,
      styleKey: styleKey,
      avoidHighways: avoidHighways,
      routeType: routeType,
      forceRefresh: true,
    );
    return RoutePoolCandidateSaveResult(
      saved: true,
      duplicate: false,
      poolFull: poolFull,
      assignment: assignment,
      candidate: saveResult.candidate,
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
          ? bucketOrder.skip(1)
          : const Iterable<int>.empty();
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
      _sortCandidateMatches(exactPrimaryMatches, requestedBucket: distanceBucket);
      _sortCandidateMatches(
        exactFallbackMatches,
        requestedBucket: distanceBucket,
      );
      _sortCandidateMatches(
        relaxedPrimaryMatches,
        requestedBucket: distanceBucket,
      );
      _sortCandidateMatches(
        relaxedFallbackMatches,
        requestedBucket: distanceBucket,
      );

      final orderedMatches = preferSingleBucketRoundTrip
          ? <RoutePoolMatch>[
              ...exactPrimaryMatches,
              ...relaxedPrimaryMatches,
              ...exactFallbackMatches,
              ...relaxedFallbackMatches,
            ]
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
        ? bucketOrder.skip(1)
        : const Iterable<int>.empty();
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
    _sortCandidateMatches(exactPrimaryMatches, requestedBucket: distanceBucket);
    _sortCandidateMatches(
      exactFallbackMatches,
      requestedBucket: distanceBucket,
    );
    _sortCandidateMatches(
      relaxedPrimaryMatches,
      requestedBucket: distanceBucket,
    );
    _sortCandidateMatches(
      relaxedFallbackMatches,
      requestedBucket: distanceBucket,
    );
    final orderedMatches = preferSingleBucketRoundTrip
        ? <RoutePoolMatch>[
            ...exactPrimaryMatches,
            ...relaxedPrimaryMatches,
            ...exactFallbackMatches,
            ...relaxedFallbackMatches,
          ]
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
      if (!relaxStyle && !_styleMatches(candidate, query.style)) continue;
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

      return b.route.qualityScore.compareTo(a.route.qualityScore);
    });

    return matches;
  }

  static void _sortCandidateMatches(
    List<RoutePoolMatch> matches, {
    required int requestedBucket,
  }) {
    matches.sort((a, b) {
      final byStartDistance = a.startDistanceKm.compareTo(b.startDistanceKm);
      if (byStartDistance != 0) return byStartDistance;

      final byBucketFit = (a.route.distanceBucket - requestedBucket)
          .abs()
          .compareTo((b.route.distanceBucket - requestedBucket).abs());
      if (byBucketFit != 0) return byBucketFit;

      final byActualDistanceFit = (a.route.distanceKm - requestedBucket)
          .abs()
          .compareTo((b.route.distanceKm - requestedBucket).abs());
      if (byActualDistanceFit != 0) return byActualDistanceFit;

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
      return inMemoryRegions.where((region) {
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
      }).toList(growable: false);
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
      query = query.eq('country_code', preferredCountryCode.trim().toUpperCase());
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
    final shouldRefresh = coverage == null ||
        forceRefresh ||
        coverage.lastCountedAt == null ||
        DateTime.now().toUtc().difference(coverage.lastCountedAt!) >
            coverageRefreshTtl;
    if (!shouldRefresh) return coverage;

    final verifiedCount = await _countMatchingVerifiedRoutes(
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
    final base = coverage ??
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
          targetPoolSize: defaultTargetPoolSize,
          maxPoolSize: defaultMaxPoolSize,
        );
    final refreshed = base.copyWith(
      currentVerifiedCount: verifiedCount,
      currentCandidateCount: candidateCount,
      coverageStatus: _deriveCoverageStatus(
        currentVerifiedCount: verifiedCount,
        targetPoolSize: base.targetPoolSize,
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
      if (_nullableSameText(coverage.admin2Name, assignment.region.admin2Name)) {
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
      final payload = coverage.toJson()..remove('id');
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
        .insert(coverage.toJson())
        .select()
        .limit(1);
    return RoutePoolCoverage.fromJson(
      Map<String, dynamic>.from((rows as List).first as Map),
    );
  }

  Future<int> _countMatchingVerifiedRoutes({
    required RoutePoolRegionAssignment assignment,
    required int distanceBucket,
    required String styleKey,
    required bool avoidHighways,
    required String routeType,
  }) async {
    final inMemoryRoutes = _inMemoryRoutes;
    if (inMemoryRoutes != null) {
      return inMemoryRoutes.where((route) {
        if (!route.verified || !route.isActive) return false;
        if (!_sameText(route.countryCode, assignment.region.countryCode)) {
          return false;
        }
        if (!_sameText(route.admin1Name, assignment.region.admin1Name)) {
          return false;
        }
        if (!_nullableSameText(route.admin2Name, assignment.region.admin2Name)) {
          return false;
        }
        if (!_sameText(route.cityCluster, assignment.region.cityCluster)) {
          return false;
        }
        if (!_sameText(route.routeType, routeType)) return false;
        if (route.distanceBucket != distanceBucket) return false;
        if (_normalizeStyleKeyList(route.styleTags).contains(styleKey) == false) {
          return false;
        }
        if (avoidHighways && (!route.avoidsHighway || route.hasHighway)) {
          return false;
        }
        return true;
      }).length;
    }

    final rows = await _db
        .from('route_pool')
        .select('style_tags, avoids_highway, has_highway, admin2_name')
        .eq('verified', true)
        .eq('is_active', true)
        .eq('country_code', assignment.region.countryCode)
        .eq('admin1_name', assignment.region.admin1Name)
        .eq('city_cluster', assignment.region.cityCluster)
        .eq('route_type', routeType)
        .eq('distance_bucket', distanceBucket);
    var count = 0;
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      if (!_nullableSameText(map['admin2_name'] as String?, assignment.region.admin2Name)) {
        continue;
      }
      final tags = _normalizeStyleKeyList(_styleTagsFromRaw(map['style_tags']));
      if (!tags.contains(styleKey)) continue;
      if (avoidHighways &&
          (((map['avoids_highway'] as bool?) ?? false) == false ||
              ((map['has_highway'] as bool?) ?? false) == true)) {
        continue;
      }
      count += 1;
    }
    return count;
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
            _nullableSameText(candidate.admin2Name, assignment.region.admin2Name) &&
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
      if (_nullableSameText(map['admin2_name'] as String?, assignment.region.admin2Name)) {
        count += 1;
      }
    }
    return count;
  }

  Future<_SeedJobUpsertResult> _ensureSeedJob({
    required RoutePoolRegionAssignment assignment,
    required int distanceBucket,
    required String styleKey,
    required bool avoidHighways,
    required String routeType,
    required String subscriptionTier,
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
        lastRequestedAt: now,
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
      priority: _priorityForTier(subscriptionTier),
      lastRequestedAt: now,
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
      final payload = job.toJson()..remove('id');
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
        .insert(job.toJson())
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
      final existingIndex = inMemoryCandidates.indexWhere(
        (item) => _sameText(item.routeFingerprint, candidate.routeFingerprint),
      );
      if (existingIndex >= 0) {
        return _CandidateUpsertResult(
          saved: false,
          duplicate: true,
          candidate: inMemoryCandidates[existingIndex],
        );
      }
      inMemoryCandidates.add(candidate);
      return _CandidateUpsertResult(
        saved: true,
        duplicate: false,
        candidate: candidate,
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
      );
    }
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

  static String _deriveCoverageStatus({
    required int currentVerifiedCount,
    required int targetPoolSize,
    required bool hasBootstrapPending,
    required bool isCooldown,
  }) {
    if (isCooldown) return 'cooldown';
    if (currentVerifiedCount >= targetPoolSize) return 'healthy';
    if (hasBootstrapPending) return 'warming_up';
    if (currentVerifiedCount > 0) return 'thin';
    return 'empty';
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

  static String _normalizeStyleKey(String style) {
    final cleaned = style
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'standard' : cleaned;
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

  static bool _highwayMatches(RoutePoolEntry candidate, bool avoidHighways) {
    if (!avoidHighways) return true;
    return candidate.avoidsHighway && !candidate.hasHighway;
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
  });

  final bool saved;
  final bool duplicate;
  final RoutePoolCandidate candidate;
}
