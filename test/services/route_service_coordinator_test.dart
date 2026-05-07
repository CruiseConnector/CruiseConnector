import 'dart:math' as math;
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/route_pool_service.dart';
import 'package:cruise_connect/data/services/route_quality_validator.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/route_pool_candidate.dart';
import 'package:cruise_connect/domain/models/route_pool_coverage.dart';
import 'package:cruise_connect/domain/models/route_pool_entry.dart';
import 'package:cruise_connect/domain/models/route_region.dart';
import 'package:cruise_connect/domain/models/route_seed_job.dart';

geo.Position _start() => geo.Position(
  latitude: 47.5162,
  longitude: 9.7471,
  timestamp: DateTime.now(),
  accuracy: 5,
  altitude: 410,
  altitudeAccuracy: 8,
  heading: 0,
  headingAccuracy: 5,
  speed: 0,
  speedAccuracy: 1,
);

geo.Position _position(double lat, double lng) => geo.Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime.now(),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

Map<String, dynamic> _closedLoopResponse() {
  return _closedLoopResponseAt(latitude: 47.5162, longitude: 9.7471);
}

Map<String, dynamic> _closedLoopResponseAt({
  required double latitude,
  required double longitude,
}) {
  final coords = List.generate(120, (i) {
    final t = (2 * math.pi * i) / 119;
    final radius =
        0.009 +
        math.sin(t * 3) * 0.0016 +
        math.cos(t * 4) * (0.0016 * 0.18) +
        math.sin(t * 3) * (0.0016 * 0.12);
    return [
      longitude + math.cos(t) * radius,
      latitude + math.sin(t) * radius * 0.55,
    ];
  });
  coords[0] = [longitude, latitude];
  coords[coords.length - 1] = [...coords.first];

  return {
    'route': {
      'geometry': {'type': 'LineString', 'coordinates': coords},
      'distance': 52000.0,
      'duration': 4300.0,
      'legs': [
        {
          'steps': [
            {
              'maneuver': {
                'type': 'turn',
                'modifier': 'left',
                'location': coords[8],
              },
              'distance': 800.0,
              'name': 'Teststraße',
            },
          ],
        },
      ],
    },
  };
}

Map<String, dynamic> _sparseLongRoundTripResponse() {
  final coords = <List<double>>[
    [9.7471, 47.5162],
    [9.95, 47.62],
    [9.72, 47.78],
    [9.52, 47.61],
    [9.7471, 47.5162],
  ];
  return {
    'route': {
      'geometry': {'type': 'LineString', 'coordinates': coords},
      'distance': 100000.0,
      'duration': 7600.0,
      'legs': [
        {
          'steps': [
            {
              'maneuver': {
                'type': 'turn',
                'modifier': 'left',
                'location': coords[1],
              },
              'distance': 25000.0,
              'name': 'Sparse Test',
            },
          ],
        },
      ],
    },
    'meta': {
      'route_type': 'ROUND_TRIP',
      'geometry_source': 'pre_hydration_fallback',
      'final_overview': 'simplified',
    },
  };
}

class _CountingInvoker implements RouteEdgeInvoker {
  _CountingInvoker(this.response);

  final Map<String, dynamic> response;
  int callCount = 0;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    callCount += 1;
    bodies.add(Map<String, dynamic>.from(body));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return response;
  }
}

class _VaryingCountingInvoker implements RouteEdgeInvoker {
  int callCount = 0;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    callCount += 1;
    bodies.add(Map<String, dynamic>.from(body));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final shift = callCount * 0.0032;
    return _closedLoopResponseShifted(shift);
  }
}

class _FlakyCountingInvoker implements RouteEdgeInvoker {
  _FlakyCountingInvoker(this.response, {this.failuresBeforeSuccess = 4});

  final Map<String, dynamic> response;
  final int failuresBeforeSuccess;
  int callCount = 0;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    callCount += 1;
    bodies.add(Map<String, dynamic>.from(body));
    await Future<void>.delayed(const Duration(milliseconds: 25));
    if (callCount <= failuresBeforeSuccess) {
      throw TimeoutException('simulated timeout');
    }
    return response;
  }
}

class _AlwaysFailingInvoker implements RouteEdgeInvoker {
  int callCount = 0;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    callCount += 1;
    bodies.add(Map<String, dynamic>.from(body));
    throw TimeoutException('simulated no route');
  }
}

class _ThrowingCandidateRoutePoolService extends RoutePoolService {
  _ThrowingCandidateRoutePoolService() : super();

  @override
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
    double? averageRating,
    int ratingCount = 0,
    double? completionRate,
    int timesSelected = 0,
    DateTime? lastSelectedAt,
  }) {
    throw StateError('simulated candidate save failure');
  }
}

class _PoolFallbackAccessInvoker implements RouteEdgeInvoker {
  int callCount = 0;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    callCount += 1;
    bodies.add(Map<String, dynamic>.from(body));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    if (body['route_type'] != 'POINT_TO_POINT') {
      throw TimeoutException('simulated no route');
    }

    final start = Map<String, dynamic>.from(body['startLocation'] as Map);
    final destination = Map<String, dynamic>.from(
      body['destination_location'] as Map,
    );
    final startLat = (start['latitude'] as num).toDouble();
    final startLng = (start['longitude'] as num).toDouble();
    final destLat = (destination['latitude'] as num).toDouble();
    final destLng = (destination['longitude'] as num).toDouble();
    final deltaLng = destLng - startLng;
    final deltaLat = destLat - startLat;
    final curveDirection = body['route_variant_hint'] == 'return' ? -1.0 : 1.0;
    final curveLng = -deltaLat * 0.16 * curveDirection;
    final curveLat = deltaLng * 0.16 * curveDirection;

    final coordinates = List.generate(18, (index) {
      final t = index / 17;
      final curve = math.sin(t * math.pi) * 0.35;
      return [
        startLng + deltaLng * t + curveLng * curve,
        startLat + deltaLat * t + curveLat * curve,
      ];
    });
    return {
      'route': {
        'geometry': {'type': 'LineString', 'coordinates': coordinates},
        'distance': _polylineDistanceMeters(coordinates),
        'duration': _polylineDistanceMeters(coordinates) / 13.89,
        'legs': const [
          {'steps': []},
        ],
      },
    };
  }
}

class _SequenceInvoker implements RouteEdgeInvoker {
  _SequenceInvoker(this.responses);

  final List<Map<String, dynamic>> responses;
  int callCount = 0;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    callCount += 1;
    bodies.add(Map<String, dynamic>.from(body));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final index = math.min(callCount - 1, responses.length - 1);
    return responses[index];
  }
}

class _FakeRoutePoolService extends RoutePoolService {
  _FakeRoutePoolService(
    this.match, {
    RoutePoolMatch? reserveMatch,
    List<RoutePoolCoverageCheck>? coverageResponses,
  }) : reserveMatch = reserveMatch,
       _coverageResponses = coverageResponses ?? const [];

  final RoutePoolMatch? match;
  final RoutePoolMatch? reserveMatch;
  final List<RoutePoolCoverageCheck> _coverageResponses;
  final calls = <Map<String, dynamic>>[];
  final reserveCalls = <Map<String, dynamic>>[];
  final coverageCalls = <Map<String, dynamic>>[];
  int ensureCoverageCallCount = 0;

  @override
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
    int candidateLimit = 200,
  }) async {
    calls.add({
      'userLat': userLat,
      'userLng': userLng,
      'distanceBucket': distanceBucket,
      'style': style,
      'avoidHighways': avoidHighways,
      'routeType': routeType,
      'crossBorderAllowed': crossBorderAllowed,
      'preferredCountryCode': preferredCountryCode,
      'preferredAdmin1Name': preferredAdmin1Name,
      'preferredAdmin2Name': preferredAdmin2Name,
      'preferredCityCluster': preferredCityCluster,
      'candidateLimit': candidateLimit,
    });
    return match;
  }

  @override
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
    int candidateLimit = 200,
  }) async {
    calls.add({
      'userLat': userLat,
      'userLng': userLng,
      'distanceBucket': distanceBucket,
      'style': style,
      'avoidHighways': avoidHighways,
      'routeType': routeType,
      'crossBorderAllowed': crossBorderAllowed,
      'preferredCountryCode': preferredCountryCode,
      'preferredAdmin1Name': preferredAdmin1Name,
      'preferredAdmin2Name': preferredAdmin2Name,
      'preferredCityCluster': preferredCityCluster,
      'candidateLimit': candidateLimit,
    });
    return match == null ? const [] : [match!];
  }

  @override
  Future<List<RoutePoolMatch>> findCandidateReserveRoutesNear({
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
    int candidateLimit = 80,
  }) async {
    reserveCalls.add({
      'userLat': userLat,
      'userLng': userLng,
      'distanceBucket': distanceBucket,
      'style': style,
      'avoidHighways': avoidHighways,
      'routeType': routeType,
      'crossBorderAllowed': crossBorderAllowed,
      'preferredCountryCode': preferredCountryCode,
      'preferredAdmin1Name': preferredAdmin1Name,
      'preferredAdmin2Name': preferredAdmin2Name,
      'preferredCityCluster': preferredCityCluster,
      'candidateLimit': candidateLimit,
    });
    return reserveMatch == null ? const [] : [reserveMatch!];
  }

  @override
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
    coverageCalls.add({
      'userLat': userLat,
      'userLng': userLng,
      'distanceBucket': distanceBucket,
      'style': style,
      'avoidHighways': avoidHighways,
      'routeType': routeType,
      'subscriptionTier': subscriptionTier,
      'createSeedJob': createSeedJob,
      'crossBorderAllowed': crossBorderAllowed,
      'preferredCountryCode': preferredCountryCode,
      'preferredAdmin1Name': preferredAdmin1Name,
      'preferredAdmin2Name': preferredAdmin2Name,
      'preferredCityCluster': preferredCityCluster,
    });
    final responseIndex = ensureCoverageCallCount;
    ensureCoverageCallCount += 1;
    if (_coverageResponses.isNotEmpty) {
      return _coverageResponses[math.min(
        responseIndex,
        _coverageResponses.length - 1,
      )];
    }
    return const RoutePoolCoverageCheck(
      assignment: null,
      coverage: null,
      coverageStatus: 'healthy',
      regionDifficulty: 'normal',
      hardRegionStatus: 'normal',
      bootstrapEnabled: true,
      curatedSeedPreferred: false,
      minVerifiedCount: 3,
      targetPoolSize: 8,
      maxPoolSize: 20,
      candidateBufferLimit: 30,
      acceptableReserveLimitPercent: 25,
      currentVerifiedCount: 8,
      currentCandidateCount: 0,
      idealCount: 8,
      goodCount: 0,
      acceptableCount: 0,
      rejectedCount: 0,
      distinctFingerprintCount: 8,
      seedJobCreated: false,
      duplicateJobPrevented: false,
      poolHealthy: true,
      poolFull: false,
      bootstrapPending: false,
    );
  }
}

Map<String, dynamic> _closedLoopResponseShifted(double lngShift) {
  final coords = List.generate(120, (i) {
    final t = (2 * math.pi * i) / 119;
    final radius =
        0.009 +
        math.sin(t * 3) * 0.0016 +
        math.cos(t * 4) * (0.0016 * 0.18) +
        math.sin(t * 3) * (0.0016 * 0.12);
    return [
      9.7471 + lngShift + math.cos(t) * radius,
      47.5162 + math.sin(t) * radius * 0.55,
    ];
  });
  coords[0] = [9.7471 + lngShift, 47.5162];
  coords[coords.length - 1] = [...coords.first];

  return {
    'route': {
      'geometry': {'type': 'LineString', 'coordinates': coords},
      'distance': 52000.0,
      'duration': 4300.0,
      'legs': [
        {
          'steps': [
            {
              'maneuver': {
                'type': 'turn',
                'modifier': 'left',
                'location': coords[8],
              },
              'distance': 800.0,
              'name': 'Teststraße',
            },
          ],
        },
      ],
    },
  };
}

RoutePoolMatch _poolMatch() {
  return _poolMatchWithResponse(
    response: _closedLoopResponse(),
    id: 'pool-dornbirn-50-sport-nohighway',
    cityCluster: 'Dornbirn',
    startDistanceKm: 0.4,
  );
}

RoutePoolCoverageCheck _coverageCheck({
  required String cityCluster,
  String admin1Name = 'Vorarlberg',
  String? admin2Name,
  String coverageStatus = 'warming_up',
  String regionDifficulty = 'normal',
  String hardRegionStatus = 'normal',
  bool bootstrapEnabled = true,
  bool curatedSeedPreferred = false,
  int targetPoolSize = 8,
  int maxPoolSize = 20,
  int healthyThreshold = 3,
  int thinThreshold = 1,
  int currentVerifiedCount = 0,
  int currentCandidateCount = 0,
  bool seedJobCreated = false,
  bool duplicateJobPrevented = false,
  bool poolHealthy = false,
  bool poolFull = false,
  bool bootstrapPending = false,
  String? seedJobStatus,
  String? seedJobError,
  double centerLat = 47.1548,
  double centerLng = 9.8220,
  double fallbackRadiusKm = 35,
}) {
  final region = _benchmarkRegion(
    countryCode: 'AT',
    admin1Name: admin1Name,
    admin2Name: admin2Name ?? cityCluster,
    cityCluster: cityCluster,
    centerLat: centerLat,
    centerLng: centerLng,
    fallbackRadiusKm: fallbackRadiusKm,
    difficultyLevel: regionDifficulty,
    hardRegionStatus: hardRegionStatus,
    bootstrapEnabled: bootstrapEnabled,
    curatedSeedPreferred: curatedSeedPreferred,
    defaultTargetPoolSize: targetPoolSize,
    defaultMaxPoolSize: maxPoolSize,
    healthyThreshold: healthyThreshold,
    thinThreshold: thinThreshold,
  );
  final coverage = RoutePoolCoverage(
    countryCode: region.countryCode,
    admin1Name: region.admin1Name,
    admin2Name: region.admin2Name,
    cityCluster: region.cityCluster,
    routeType: 'ROUND_TRIP',
    distanceBucket: 50,
    styleKey: 'sport_mode',
    avoidHighways: true,
    coverageStatus: coverageStatus,
    difficultyLevel: regionDifficulty,
    hardRegionStatus: hardRegionStatus,
    bootstrapEnabled: bootstrapEnabled,
    curatedSeedPreferred: curatedSeedPreferred,
    minVerifiedCount: 3,
    targetPoolSize: targetPoolSize,
    maxPoolSize: maxPoolSize,
    healthyThreshold: healthyThreshold,
    thinThreshold: thinThreshold,
    currentVerifiedCount: currentVerifiedCount,
    currentCandidateCount: currentCandidateCount,
    idealCount: currentVerifiedCount,
    goodCount: 0,
    acceptableCount: 0,
    rejectedCount: 0,
    distinctFingerprintCount: currentVerifiedCount,
  );
  return RoutePoolCoverageCheck(
    assignment: RoutePoolRegionAssignment(
      region: region,
      distanceToCenterKm: 0.6,
    ),
    coverage: coverage,
    coverageStatus: coverageStatus,
    regionDifficulty: regionDifficulty,
    hardRegionStatus: hardRegionStatus,
    bootstrapEnabled: bootstrapEnabled,
    curatedSeedPreferred: curatedSeedPreferred,
    minVerifiedCount: coverage.minVerifiedCount,
    targetPoolSize: targetPoolSize,
    maxPoolSize: maxPoolSize,
    candidateBufferLimit: coverage.candidateBufferLimit,
    acceptableReserveLimitPercent: coverage.acceptableReserveLimitPercent,
    currentVerifiedCount: currentVerifiedCount,
    currentCandidateCount: currentCandidateCount,
    idealCount: coverage.idealCount,
    goodCount: coverage.goodCount,
    acceptableCount: coverage.acceptableCount,
    rejectedCount: coverage.rejectedCount,
    distinctFingerprintCount: coverage.distinctFingerprintCount,
    seedJobCreated: seedJobCreated,
    duplicateJobPrevented: duplicateJobPrevented,
    poolHealthy: poolHealthy,
    poolFull: poolFull,
    bootstrapPending: bootstrapPending,
    seedJobStatus: seedJobStatus ?? (bootstrapPending ? 'queued' : null),
    seedJobError: seedJobError,
  );
}

RoutePoolMatch _poolMatchWithResponse({
  required Map<String, dynamic> response,
  required String id,
  required String cityCluster,
  required double startDistanceKm,
  double distanceKm = 52,
  int distanceBucket = 50,
  List<String> styleTags = const ['Sport Mode'],
  bool verified = true,
  String source = 'curated',
  Map<String, dynamic> routePayload = const {},
}) {
  final route = response['route'] as Map<String, dynamic>;
  final geometry = Map<String, dynamic>.from(route['geometry'] as Map);
  final first = (geometry['coordinates'] as List).first as List;

  return RoutePoolMatch(
    route: RoutePoolEntry(
      id: id,
      countryCode: 'AT',
      admin1Name: 'Vorarlberg',
      admin2Name: cityCluster,
      cityCluster: cityCluster,
      startLat: (first[1] as num).toDouble(),
      startLng: (first[0] as num).toDouble(),
      distanceKm: distanceKm,
      distanceBucket: distanceBucket,
      routeType: 'ROUND_TRIP',
      styleTags: styleTags,
      avoidsHighway: true,
      hasHighway: false,
      qualityScore: 92,
      verified: verified,
      geometry: geometry,
      durationSeconds: 4300,
      source: source,
      routePayload: routePayload,
    ),
    startDistanceKm: startDistanceKm,
    allowedRadiusKm: 12,
    radiusScope: 'local_cluster',
  );
}

Map<String, dynamic> _spikyClosedLoopResponse() {
  final response = _closedLoopResponse();
  final route = response['route'] as Map<String, dynamic>;
  final geometry = Map<String, dynamic>.from(route['geometry'] as Map);
  final coordinates = (geometry['coordinates'] as List)
      .map((point) => List<double>.from(point as List))
      .toList(growable: true);
  final anchor = coordinates[16];
  coordinates.insertAll(17, [
    [anchor[0] + 0.0012, anchor[1] + 0.0004],
    [anchor[0] + 0.0018, anchor[1] + 0.0007],
    [anchor[0] + 0.0012, anchor[1] + 0.0004],
    [anchor[0], anchor[1]],
  ]);
  geometry['coordinates'] = coordinates;
  route['geometry'] = geometry;
  route['distance'] = _polylineDistanceMeters(coordinates);
  return response;
}

Map<String, dynamic> _outAndBackPoolResponse() {
  final start = [9.7471, 47.5162];
  final outbound = List.generate(28, (index) {
    final t = index / 27.0;
    return [start[0] - 0.18 * t, start[1] + 0.04 * t];
  });
  final coordinates = [...outbound, ...outbound.reversed.skip(1)];
  coordinates[0] = start;
  coordinates[coordinates.length - 1] = [...start];

  return {
    'route': {
      'geometry': {'type': 'LineString', 'coordinates': coordinates},
      'distance': 50000.0,
      'duration': 4100.0,
      'legs': const [
        {'steps': []},
      ],
    },
  };
}

double _polylineDistanceMeters(List<List<double>> coordinates) {
  var total = 0.0;
  for (var index = 1; index < coordinates.length; index++) {
    total += geo.Geolocator.distanceBetween(
      coordinates[index - 1][1],
      coordinates[index - 1][0],
      coordinates[index][1],
      coordinates[index][0],
    );
  }
  return total;
}

RouteRegion _benchmarkRegion({
  required String countryCode,
  required String admin1Name,
  String? admin2Name,
  required String cityCluster,
  required double centerLat,
  required double centerLng,
  double fallbackRadiusKm = 30,
  String difficultyLevel = 'normal',
  String hardRegionStatus = 'normal',
  bool bootstrapEnabled = true,
  bool curatedSeedPreferred = false,
  int defaultTargetPoolSize = 15,
  int defaultMaxPoolSize = 20,
  int healthyThreshold = 15,
  int thinThreshold = 1,
  int seedBudgetUnits = 1,
  int seedCooldownMinutes = 20,
}) {
  return RouteRegion(
    countryCode: countryCode,
    admin1Name: admin1Name,
    admin2Name: admin2Name,
    cityCluster: cityCluster,
    centerLat: centerLat,
    centerLng: centerLng,
    fallbackRadiusKm: fallbackRadiusKm,
    difficultyLevel: difficultyLevel,
    hardRegionStatus: hardRegionStatus,
    bootstrapEnabled: bootstrapEnabled,
    curatedSeedPreferred: curatedSeedPreferred,
    defaultTargetPoolSize: defaultTargetPoolSize,
    defaultMaxPoolSize: defaultMaxPoolSize,
    healthyThreshold: healthyThreshold,
    thinThreshold: thinThreshold,
    seedBudgetUnits: seedBudgetUnits,
    seedCooldownMinutes: seedCooldownMinutes,
  );
}

RoutePoolEntry _inMemoryPoolEntry({
  required String id,
  required String cityCluster,
  required Map<String, dynamic> response,
  String countryCode = 'AT',
  String admin1Name = 'Vorarlberg',
  String? admin2Name,
}) {
  final route = response['route'] as Map<String, dynamic>;
  final geometry = Map<String, dynamic>.from(route['geometry'] as Map);
  final first = (geometry['coordinates'] as List).first as List;
  return RoutePoolEntry(
    id: id,
    countryCode: countryCode,
    admin1Name: admin1Name,
    admin2Name: admin2Name ?? cityCluster,
    cityCluster: cityCluster,
    startLat: (first[1] as num).toDouble(),
    startLng: (first[0] as num).toDouble(),
    distanceKm: 52,
    distanceBucket: 50,
    routeType: 'ROUND_TRIP',
    styleTags: const ['Sport Mode'],
    avoidsHighway: true,
    hasHighway: false,
    qualityScore: 92,
    verified: true,
    geometry: geometry,
    durationSeconds: 4300,
    routePayload: const {
      'provider': 'mapbox',
      'effective_excludes': 'motorway',
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingInvoker invoker;
  late RouteService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RouteService.resetForTests();
    invoker = _CountingInvoker(_closedLoopResponse());
    service = RouteService(invoker: invoker);
  });

  test('single-flight nutzt pro Szenario nur einen aktiven Request', () async {
    final futures = await Future.wait([
      service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
      ),
      service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
      ),
    ]);

    expect(futures, hasLength(2));
    expect(futures.first.distanceKm, closeTo(futures.last.distanceKm!, 0.01));
    // Single-flight dedupliziert die zwei concurrent calls zu einem
    // generateRoundTrip-Lauf. Dieser Lauf macht intern bis zu 2 Edge-Calls
    // (maxAttempts=2 in route_service.dart), wenn der erste Kandidat nicht
    // ideal ist. Ohne Single-Flight wären es 4 Edge-Calls (2 × 2).
    expect(invoker.callCount, lessThanOrEqualTo(2));
  });

  test('ROUND_TRIP verwirft sparse 100-km Anzeige-Geometrie', () async {
    service = RouteService(
      invoker: _CountingInvoker(_sparseLongRoundTripResponse()),
    );

    await expectLater(
      service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 100,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        forceFreshVariant: true,
      ),
      throwsA(
        isA<RouteServiceException>()
            .having(
              (error) => error.edgeMeta['response_code'],
              'response_code',
              'route_display_geometry_invalid',
            )
            .having(
              (error) => error.edgeMeta['display_geometry_reject_reason'],
              'display_geometry_reject_reason',
              isNotNull,
            ),
      ),
    );
  });

  test(
    'Search-Session-Polling behandelt search_in_progress als pollfähig',
    () async {
      service = RouteService(
        invoker: _CountingInvoker({
          'route': null,
          'code': 'search_in_progress',
          'message': 'search_in_progress',
          'meta': {
            'response_code': 'search_in_progress',
            'search_in_progress': true,
            'search_session_id': 'session-queued',
            'search_session_status': 'queued',
            'attempts_count': 0,
            'worker_last_seen_at': null,
            'on_demand_worker_triggered': true,
          },
        }),
      );

      final result = await service.pollRoundTripSearchSession('session-queued');

      expect(result, isNull);
      expect(
        service.lastRoundTripSearchSessionMeta?['search_session_id'],
        'session-queued',
      );
      expect(
        service.lastRoundTripSearchSessionMeta?['search_session_status'],
        'queued',
      );
    },
  );

  test(
    'Search-Session-Polling übernimmt found Route als RouteResult',
    () async {
      final response = _closedLoopResponse();
      response['meta'] = {
        'response_code': 'search_session_found',
        'search_session_id': 'session-found',
        'search_session_status': 'found',
        'route_source': 'search_session',
        'final_geometry_source': 'hydrated_worker',
        'final_coordinate_count': 120,
        'max_display_segment_m': 420,
        'on_demand_worker_triggered': true,
      };
      service = RouteService(invoker: _CountingInvoker(response));

      final result = await service.pollRoundTripSearchSession('session-found');

      expect(result, isNotNull);
      expect(result!.coordinates, hasLength(120));
      expect(result.edgeMeta['search_session_id'], 'session-found');
      expect(result.edgeMeta['route_source'], 'search_session');
      expect(result.edgeMeta['final_geometry_source'], 'hydrated_worker');
    },
  );

  test('Search-Session-Polling verwirft sparse found Geometry', () async {
    final response = _sparseLongRoundTripResponse();
    response['meta'] = {
      'response_code': 'search_session_found',
      'search_session_id': 'session-sparse',
      'search_session_status': 'found',
      'route_source': 'search_session',
      'final_geometry_source': 'hydrated_worker',
      'final_coordinate_count': 5,
      'max_display_segment_m': 30000,
    };
    service = RouteService(invoker: _CountingInvoker(response));

    await expectLater(
      service.pollRoundTripSearchSession('session-sparse'),
      throwsA(
        isA<RouteServiceException>().having(
          (error) => error.edgeMeta['response_code'],
          'response_code',
          'route_display_geometry_invalid',
        ),
      ),
    );
  });

  test(
    'explizites Neu-Suchen startet frisch und löst keine Hintergrundroute aus',
    () async {
      final varyingInvoker = _VaryingCountingInvoker();
      service = RouteService(invoker: varyingInvoker);

      final first = await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        forceFreshVariant: true,
        debugTrigger: 'searchAgain',
      );

      expect(first.coordinates, isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      expect(varyingInvoker.callCount, 1);
      expect(varyingInvoker.bodies.first['client_force_fresh_variant'], true);
      expect(varyingInvoker.bodies.first['client_trigger'], 'searchAgain');
      expect(
        varyingInvoker.bodies.first['client_scenario_key']?.toString(),
        contains('ROUND_TRIP'),
      );

      final second = await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        forceFreshVariant: true,
        debugTrigger: 'searchAgain',
      );

      expect(second.coordinates, isNotEmpty);
      expect(varyingInvoker.callCount, greaterThanOrEqualTo(2));
      expect(
        varyingInvoker.bodies.map((body) => body['route_variant_hint']).toSet(),
        hasLength(greaterThanOrEqualTo(2)),
      );
      expect(
        varyingInvoker.bodies.last['previous_route_fingerprints'],
        isNotEmpty,
      );
    },
  );

  test('Search Again sendet maximal die letzten 10 Fingerprints', () async {
    final varyingInvoker = _VaryingCountingInvoker();
    service = RouteService(invoker: varyingInvoker);

    for (var i = 0; i < 11; i += 1) {
      await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        forceFreshVariant: true,
        debugTrigger: 'searchAgain',
      );
    }

    final lastPrevious =
        varyingInvoker.bodies.last['previous_route_fingerprints'] as List?;
    expect(lastPrevious, isNotNull);
    expect(lastPrevious, hasLength(10));
    expect(RouteService.lastRoutePreviousFingerprints, hasLength(10));
  });

  test('bewegter Rundkurs-Start sendet Snap- und Bearing-Meta', () async {
    final movingStart = geo.Position(
      latitude: 47.5162,
      longitude: 9.7471,
      timestamp: DateTime.now(),
      accuracy: 12,
      altitude: 410,
      altitudeAccuracy: 8,
      heading: 92,
      headingAccuracy: 8,
      speed: 18,
      speedAccuracy: 1,
    );

    final route = await service.generateRoundTrip(
      startPosition: movingStart,
      targetDistanceKm: 50,
      mode: 'Sport Mode',
      planningType: 'Zufall',
      forceFreshVariant: true,
    );

    final body = invoker.bodies.first;
    expect(body['moving_start'], true);
    expect(body['current_heading'], 92);
    expect(body['start_radius_m'], isA<double>());
    expect(body['avoid_maneuver_radius_m'], isA<double>());
    expect(route.edgeMeta['moving_start_detected'], true);
    expect(route.edgeMeta['start_snap_strategy'], 'moving_bearing_radius_snap');
    expect(route.edgeMeta['avoid_maneuver_radius_used'], isA<double>());
  });

  test(
    'sichtbar andere Route darf nach Seen-Historie erneut geliefert werden',
    () async {
      final varyingInvoker = _VaryingCountingInvoker();
      service = RouteService(invoker: varyingInvoker);

      final first = await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        forceFreshVariant: true,
      );

      final second = await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        forceFreshVariant: true,
        debugTrigger: 'searchAgain',
      );

      expect(first.coordinates, isNotEmpty);
      expect(second.coordinates, isNotEmpty);
      expect(second.distanceKm, closeTo(first.distanceKm!, 0.5));
      expect(varyingInvoker.callCount, greaterThanOrEqualTo(2));
      expect(
        RouteQualityValidator.buildRouteFingerprint(
          first.coordinates,
          distanceKm: first.distanceKm,
        ),
        isNot(
          equals(
            RouteQualityValidator.buildRouteFingerprint(
              second.coordinates,
              distanceKm: second.distanceKm,
            ),
          ),
        ),
      );
    },
  );

  test(
    'Rundkurs verwirft gleichen Loop auch nach Toggle-Wechsel und sucht weiter',
    () async {
      final sequenceInvoker = _SequenceInvoker([
        _closedLoopResponse(),
        _closedLoopResponse(),
        _closedLoopResponseShifted(0.0100),
      ]);
      service = RouteService(invoker: sequenceInvoker);

      final first = await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        avoidHighways: false,
        forceFreshVariant: true,
      );

      final second = await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        avoidHighways: true,
        forceFreshVariant: true,
        debugTrigger: 'settingsChanged',
      );

      expect(first.coordinates, isNotEmpty);
      expect(second.coordinates, isNotEmpty);
      expect(sequenceInvoker.callCount, 4);
      expect(
        sequenceInvoker.bodies.first['client_scenario_key']?.toString(),
        contains('|h0'),
      );
      expect(
        sequenceInvoker.bodies
            .skip(1)
            .any(
              (body) =>
                  body['avoid_highways'] == true &&
                  body['client_force_fresh_variant'] == true &&
                  body['client_trigger'] == 'settingsChanged' &&
                  body['client_scenario_key']?.toString().contains('|h1') ==
                      true,
            ),
        true,
      );
      expect(
        RouteQualityValidator.buildRouteFingerprint(
          first.coordinates,
          distanceKm: first.distanceKm,
        ),
        isNot(
          equals(
            RouteQualityValidator.buildRouteFingerprint(
              second.coordinates,
              distanceKm: second.distanceKm,
            ),
          ),
        ),
      );
    },
  );

  test('nach einem Fehler kann direkt erneut frisch gesucht werden', () async {
    final flakyInvoker = _FlakyCountingInvoker(
      _closedLoopResponse(),
      failuresBeforeSuccess: 4,
    );
    service = RouteService(invoker: flakyInvoker);

    await expectLater(
      service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        avoidHighways: true,
        forceFreshVariant: true,
      ),
      throwsA(isA<RouteServiceException>()),
    );

    final recovered = await service.generateRoundTrip(
      startPosition: _start(),
      targetDistanceKm: 50,
      mode: 'Sport Mode',
      planningType: 'Zufall',
      avoidHighways: true,
      forceFreshVariant: true,
    );

    expect(recovered.coordinates, isNotEmpty);
    expect(flakyInvoker.callCount, greaterThanOrEqualTo(5));
  });

  test(
    'Search-Again versucht Live zuerst und nutzt Pool erst nach Live-Fehlschlag',
    () async {
      final failingInvoker = _AlwaysFailingInvoker();
      final poolService = _FakeRoutePoolService(_poolMatch());
      service = RouteService(
        invoker: failingInvoker,
        routePoolService: poolService,
      );

      final route = await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        avoidHighways: true,
        forceFreshVariant: true,
      );

      expect(route.coordinates, isNotEmpty);
      expect(failingInvoker.callCount, 1);
      expect(poolService.calls, hasLength(1));
      expect(poolService.calls.single['distanceBucket'], 50);
      expect(poolService.calls.single['avoidHighways'], true);
      expect(route.edgeMeta['route_source'], 'pool');
      expect(route.edgeMeta['fallbackUsed'], true);
      expect(route.edgeMeta['mapboxCallCount'], 1);
      expect(route.edgeMeta['source_decision'], 'search_again_live_first');
      expect(route.edgeMeta['live_attempted'], true);
      expect(route.edgeMeta['live_attempt_reason'], 'search_again_force_fresh');
      expect(route.edgeMeta['pool_used_reason'], 'network');
      expect(
        route.edgeMeta['pool_match_id'],
        'pool-dornbirn-50-sport-nohighway',
      );
      expect(RouteService.lastRoutePoolFallbackUsed, true);
    },
  );

  test(
    'Search-Again markiert Pool-Duplikat nur als Fallback, wenn keine Alternative bleibt',
    () async {
      final poolService = _FakeRoutePoolService(_poolMatch());
      service = RouteService(
        invoker: _AlwaysFailingInvoker(),
        routePoolService: poolService,
      );

      final first = await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        avoidHighways: true,
      );
      expect(first.coordinates, isNotEmpty);
      expect(first.edgeMeta['route_source'], 'pool');
      expect(first.edgeMeta['duplicateFallbackUsed'], isFalse);

      final second = await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        avoidHighways: true,
        forceFreshVariant: true,
      );

      expect(second.coordinates, isNotEmpty);
      expect(second.edgeMeta['route_source'], 'pool');
      expect(second.edgeMeta['duplicateFallbackUsed'], isTrue);
      expect(second.edgeMeta['duplicate_skipped'], isTrue);
      expect(second.edgeMeta['pool_seen_candidate_count'], 1);
      expect(second.edgeMeta['previous_route_fingerprints'], isNotEmpty);
    },
  );

  test(
    'Hard-Region nutzt Candidate-Reserve nach leerem verified Pool',
    () async {
      final reserveMatch = _poolMatchWithResponse(
        response: _closedLoopResponseAt(latitude: 47.1548, longitude: 9.8220),
        id: 'candidate-reserve-bludenz-50-sport',
        cityCluster: 'Bludenz',
        startDistanceKm: 0.3,
        verified: false,
        source: 'candidate_reserve',
        routePayload: const {
          'candidate_reserve': true,
          'candidate_pool_id': 'candidate-reserve-bludenz-50-sport',
        },
      );
      final poolService = _FakeRoutePoolService(
        null,
        reserveMatch: reserveMatch,
      );
      service = RouteService(
        invoker: _AlwaysFailingInvoker(),
        routePoolService: poolService,
      );

      final route = await service.generateRoundTrip(
        startPosition: _position(47.1548, 9.8220),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        avoidHighways: true,
        forceFreshVariant: true,
        subscriptionTier: 'premium',
      );

      expect(route.coordinates, isNotEmpty);
      expect(poolService.calls, hasLength(1));
      expect(poolService.reserveCalls, hasLength(1));
      expect(poolService.reserveCalls.single['distanceBucket'], 50);
      expect(poolService.reserveCalls.single['avoidHighways'], true);
      expect(route.edgeMeta['route_source'], 'candidate_reserve');
      expect(route.edgeMeta['source'], 'candidate_reserve');
      expect(route.edgeMeta['candidate_reserve_used'], true);
      expect(route.edgeMeta['candidate_pool_id'], reserveMatch.route.id);
      expect(route.edgeMeta['quality_tier'], 'acceptable');
      expect(route.edgeMeta['final_geometry_source'], 'road_snapped_full');
      expect(route.edgeMeta['road_snapped_geometry'], true);
      expect(RouteService.lastRouteGenerationSource, 'candidate_reserve');
      expect(RouteService.lastRouteTemporaryCandidate, true);
    },
  );

  test(
    'Autobahn AN darf gute No-Highway-Poolroute als legitimen Fallback nutzen',
    () async {
      final poolService = _FakeRoutePoolService(_poolMatch());
      service = RouteService(
        invoker: _AlwaysFailingInvoker(),
        routePoolService: poolService,
      );

      final route = await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        avoidHighways: false,
      );

      expect(route.coordinates, isNotEmpty);
      expect(route.edgeMeta['route_source'], 'pool');
      expect(route.edgeMeta['highway_allowed'], isTrue);
      expect(route.edgeMeta['motorway_policy'], 'allowed_not_required');
      expect(route.edgeMeta['actual_has_highway'], isFalse);
      expect(route.edgeMeta['actual_avoids_highway'], isTrue);
      expect(route.edgeMeta['cross_cell_highway_fallback'], isTrue);
    },
  );

  test(
    'ROUND_TRIP-Pool-Fallback verwirft zu weite Pool-Route ueber 10 km',
    () async {
      final failingInvoker = _AlwaysFailingInvoker();
      final farPoolService = _FakeRoutePoolService(
        _poolMatchWithResponse(
          response: _closedLoopResponseShifted(0.25),
          id: 'pool-bregenz-too-far',
          cityCluster: 'Bregenz',
          startDistanceKm: 17.4,
        ),
      );
      service = RouteService(
        invoker: failingInvoker,
        routePoolService: farPoolService,
      );

      await expectLater(
        service.generateRoundTrip(
          startPosition: _start(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
        ),
        throwsA(isA<RouteServiceException>()),
      );

      expect(RouteService.lastRoutePoolFallbackUsed, isFalse);
      expect(RouteService.lastRoutePoolRejectedTooFar, isTrue);
      expect(RouteService.lastRoutePoolDistanceRuleApplied, isTrue);
    },
  );

  test(
    'ROUND_TRIP-Pool-Fallback verwirft lokal kaputte verified Pool-Route',
    () async {
      final poolService = _FakeRoutePoolService(
        _poolMatchWithResponse(
          response: _outAndBackPoolResponse(),
          id: 'pool-bregenz-out-and-back',
          cityCluster: 'Bregenz',
          startDistanceKm: 0.2,
        ),
      );
      service = RouteService(
        invoker: _AlwaysFailingInvoker(),
        routePoolService: poolService,
      );

      await expectLater(
        service.generateRoundTrip(
          startPosition: _start(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
        ),
        throwsA(isA<RouteServiceException>()),
      );

      expect(RouteService.lastRoutePoolFallbackUsed, isFalse);
      expect(RouteService.lastRouteGenerationSource, isNot('pool'));
      expect(poolService.calls, isNotEmpty);
    },
  );

  test('100-km Sport-Pool-Fallback verwirft out-and-back Astroute', () async {
    final poolService = _FakeRoutePoolService(
      _poolMatchWithResponse(
        response: _outAndBackPoolResponse(),
        id: 'pool-dornbirn-100-sport-out-and-back',
        cityCluster: 'Dornbirn',
        startDistanceKm: 0.2,
        distanceKm: 100,
        distanceBucket: 100,
      ),
    );
    service = RouteService(
      invoker: _AlwaysFailingInvoker(),
      routePoolService: poolService,
    );

    await expectLater(
      service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 100,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        avoidHighways: true,
        forceFreshVariant: true,
      ),
      throwsA(isA<RouteServiceException>()),
    );

    expect(RouteService.lastRoutePoolFallbackUsed, isFalse);
    expect(RouteService.lastRouteGenerationSource, isNot('pool'));
  });

  test(
    '100-km Kurvenjagd ohne Route zeigt spezifischen Availability-Status',
    () async {
      final noRouteInvoker = _CountingInvoker({
        'route': null,
        'meta': {
          'requested_style': 'Kurvenjagd',
          'requested_distance_bucket': 100,
        },
      });
      service = RouteService(
        invoker: noRouteInvoker,
        routePoolService: RoutePoolService(
          inMemoryRegions: const <RouteRegion>[],
          inMemoryRoutes: const <RoutePoolEntry>[],
          inMemoryCoverage: const <RoutePoolCoverage>[],
          inMemorySeedJobs: <RouteSeedJob>[],
          inMemoryCandidates: const <RoutePoolCandidate>[],
        ),
      );

      late RouteServiceException error;
      try {
        await service.generateRoundTrip(
          startPosition: _start(),
          targetDistanceKm: 100,
          mode: 'Kurvenjagd',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
        );
      } on RouteServiceException catch (caught) {
        error = caught;
      }

      expect(error.userMessage, contains('Kurvenjagd'));
      expect(error.userMessage, isNot(contains('Bitte ändere Stil')));
      expect(error.edgeMeta['requested_distance_bucket'], 100);
      expect(noRouteInvoker.bodies, isNotEmpty);
      expect(
        noRouteInvoker.bodies.any((body) => body['mode'] == 'Sport Mode'),
        isFalse,
      );
    },
  );

  test(
    'ROUND_TRIP-NoRoute ohne Edge-Meta nutzt Request-Cell für User-Status',
    () async {
      final noRouteInvoker = _CountingInvoker({'route': null});
      service = RouteService(
        invoker: noRouteInvoker,
        routePoolService: RoutePoolService(
          inMemoryRegions: const <RouteRegion>[],
          inMemoryRoutes: const <RoutePoolEntry>[],
          inMemoryCoverage: const <RoutePoolCoverage>[],
          inMemorySeedJobs: <RouteSeedJob>[],
          inMemoryCandidates: const <RoutePoolCandidate>[],
        ),
      );

      late RouteServiceException error;
      try {
        await service.generateRoundTrip(
          startPosition: _start(),
          targetDistanceKm: 100,
          mode: 'Kurvenjagd',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
        );
      } on RouteServiceException catch (caught) {
        error = caught;
      }

      expect(error.userMessage, contains('Kurvenjagd'));
      expect(error.edgeMeta['requested_route_type'], 'ROUND_TRIP');
      expect(error.edgeMeta['requested_style_key'], 'kurvenjagd');
      expect(error.edgeMeta['requested_distance_bucket'], 100);
      expect(error.edgeMeta['avoid_highways'], isTrue);
      expect(error.edgeMeta['exact_cell_required'], isTrue);
    },
  );

  test(
    'paused_budget Seed-Job wird in Testphase nicht als Budget-Popup gemappt',
    () async {
      final noRouteInvoker = _CountingInvoker({'route': null});
      final poolService = _FakeRoutePoolService(
        null,
        coverageResponses: [
          _coverageCheck(
            cityCluster: 'Bludenz',
            coverageStatus: 'empty',
            seedJobStatus: 'paused_budget',
            seedJobError: 'request_budget_exhausted',
            bootstrapPending: true,
          ),
        ],
      );
      service = RouteService(
        invoker: noRouteInvoker,
        routePoolService: poolService,
      );

      late RouteServiceException error;
      try {
        await service.generateRoundTrip(
          startPosition: _position(47.1548, 9.8220),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
          subscriptionTier: 'premium',
        );
      } on RouteServiceException catch (caught) {
        error = caught;
      }

      expect(error.userMessage, isNot(contains('Heute wurden viele')));
      expect(error.edgeMeta['real_budget_limited'], isFalse);
      expect(error.edgeMeta['route_budget_paused'], isFalse);
      expect(error.edgeMeta['next_action'], 'queued_for_healing');
    },
  );

  test(
    'ROUND_TRIP-Pool-Fallback verwirft lokalen Access-Leg wenn der Rebase unbrauchbar ist',
    () async {
      final accessInvoker = _PoolFallbackAccessInvoker();
      final nearbyPoolService = _FakeRoutePoolService(
        _poolMatchWithResponse(
          response: _closedLoopResponseShifted(0.03),
          id: 'pool-nearby-access',
          cityCluster: 'Dornbirn',
          startDistanceKm: 2.4,
        ),
      );
      service = RouteService(
        invoker: accessInvoker,
        routePoolService: nearbyPoolService,
      );

      await expectLater(
        service.generateRoundTrip(
          startPosition: _start(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
        ),
        throwsA(isA<RouteServiceException>()),
      );

      expect(RouteService.lastRoutePoolFallbackUsed, isFalse);
      expect(RouteService.lastRoutePoolRejectedTooFar, isFalse);
      expect(RouteService.lastRouteAccessLegUsed, isFalse);
    },
  );

  test(
    'ROUND_TRIP-Pool-Fallback vertraut nicht blind auf gemeldete Startdistanz',
    () async {
      final failingInvoker = _AlwaysFailingInvoker();
      final lyingPoolService = _FakeRoutePoolService(
        _poolMatchWithResponse(
          response: _closedLoopResponseShifted(0.25),
          id: 'pool-lying-too-far',
          cityCluster: 'Dornbirn',
          startDistanceKm: 0.4,
        ),
      );
      service = RouteService(
        invoker: failingInvoker,
        routePoolService: lyingPoolService,
      );

      await expectLater(
        service.generateRoundTrip(
          startPosition: _start(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
        ),
        throwsA(isA<RouteServiceException>()),
      );

      expect(RouteService.lastRoutePoolFallbackUsed, isFalse);
      expect(RouteService.lastRoutePoolRejectedTooFar, isTrue);
    },
  );

  test(
    'Pool-Route mit kurzem Dead-End-Spur-Stich wird nicht akzeptiert',
    () async {
      final failingInvoker = _AlwaysFailingInvoker();
      final spikyPoolService = _FakeRoutePoolService(
        _poolMatchWithResponse(
          response: _spikyClosedLoopResponse(),
          id: 'pool-spiky',
          cityCluster: 'Dornbirn',
          startDistanceKm: 0.4,
        ),
      );
      service = RouteService(
        invoker: failingInvoker,
        routePoolService: spikyPoolService,
      );

      await expectLater(
        service.generateRoundTrip(
          startPosition: _start(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
        ),
        throwsA(isA<RouteServiceException>()),
      );

      expect(RouteService.lastRoutePoolFallbackUsed, isFalse);
      expect(RouteService.lastRouteDeadEndSpikeDetected, isTrue);
    },
  );

  test(
    'Free-User in healthy Region bekommt Pool-Route ohne Live-Call und ohne Seed-Job',
    () async {
      final jobs = <RouteSeedJob>[];
      final coverages = <RoutePoolCoverage>[];
      final candidates = <RoutePoolCandidate>[];
      service = RouteService(
        invoker: invoker,
        routePoolService: RoutePoolService(
          inMemoryRegions: [
            _benchmarkRegion(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Dornbirn',
              cityCluster: 'Dornbirn',
              centerLat: 47.5162,
              centerLng: 9.7471,
            ),
          ],
          inMemoryRoutes: [
            _inMemoryPoolEntry(
              id: 'healthy-dornbirn-pool',
              cityCluster: 'Dornbirn',
              response: _closedLoopResponse(),
              admin2Name: 'Dornbirn',
            ),
          ],
          inMemoryCoverage: coverages,
          inMemorySeedJobs: jobs,
          inMemoryCandidates: candidates,
        ),
      );

      final route = await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        avoidHighways: true,
        forceFreshVariant: true,
        subscriptionTier: 'free',
      );

      expect(route.edgeMeta['route_source'], 'pool');
      expect(route.edgeMeta['subscriptionTier'], 'free');
      expect(invoker.callCount, 0);
      expect(jobs, isEmpty);
    },
  );

  test(
    'Premium Search-Again versucht Live vor healthy Pool-Fallback',
    () async {
      final jobs = <RouteSeedJob>[];
      final coverage = _coverageCheck(
        cityCluster: 'Dornbirn',
        admin2Name: 'Dornbirn',
        coverageStatus: 'healthy',
        currentVerifiedCount: 15,
        poolHealthy: true,
        centerLat: 47.5162,
        centerLng: 9.7471,
      ).coverage!.copyWith(lastCountedAt: DateTime.now().toUtc());
      service = RouteService(
        invoker: invoker,
        routePoolService: RoutePoolService(
          inMemoryRegions: [
            _benchmarkRegion(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Dornbirn',
              cityCluster: 'Dornbirn',
              centerLat: 47.5162,
              centerLng: 9.7471,
            ),
          ],
          inMemoryRoutes: [
            _inMemoryPoolEntry(
              id: 'premium-dornbirn-pool',
              cityCluster: 'Dornbirn',
              response: _closedLoopResponse(),
              admin2Name: 'Dornbirn',
            ),
          ],
          inMemoryCoverage: [coverage],
          inMemorySeedJobs: jobs,
          inMemoryCandidates: <RoutePoolCandidate>[],
        ),
      );

      final route = await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        avoidHighways: true,
        forceFreshVariant: true,
        subscriptionTier: 'premium',
      );

      expect(route.edgeMeta['route_source'], 'mapbox');
      expect(route.edgeMeta['source_decision'], 'search_again_live_first');
      expect(route.edgeMeta['live_attempted'], true);
      expect(route.edgeMeta['live_attempt_reason'], 'search_again_force_fresh');
      expect(invoker.callCount, 1);
      expect(jobs, isEmpty);
    },
  );

  test(
    'Free-User in leerer Region bekommt warming_up statt generischem Fehler und keinen Job-Duplikatsturm',
    () async {
      final jobs = <RouteSeedJob>[];
      service = RouteService(
        invoker: invoker,
        routePoolService: RoutePoolService(
          inMemoryRegions: [
            _benchmarkRegion(
              countryCode: 'DE',
              admin1Name: 'Baden-Württemberg',
              admin2Name: 'Stuttgart',
              cityCluster: 'Stuttgart',
              centerLat: 48.7758,
              centerLng: 9.1829,
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: jobs,
          inMemoryCandidates: <RoutePoolCandidate>[],
        ),
      );

      late RouteServiceException firstError;
      late RouteServiceException secondError;
      try {
        await service.generateRoundTrip(
          startPosition: _position(48.78, 9.18),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
          subscriptionTier: 'free',
        );
      } on RouteServiceException catch (error) {
        firstError = error;
      }
      try {
        await service.generateRoundTrip(
          startPosition: _position(48.78, 9.18),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
          subscriptionTier: 'free',
        );
      } on RouteServiceException catch (error) {
        secondError = error;
      }

      expect(firstError.userMessage, contains('Neue Vorschläge'));
      expect(firstError.edgeMeta['region_warming_up'], true);
      expect(firstError.edgeMeta['seed_job_created'], true);
      expect(secondError.edgeMeta['duplicate_job_prevented'], true);
      expect(invoker.callCount, 0);
      expect(jobs, hasLength(1));
    },
  );

  test(
    'Premium short no-highway Pool-Luecke nutzt On-Demand-Fill bevor Warmup',
    () async {
      final jobs = <RouteSeedJob>[];
      final failingInvoker = _AlwaysFailingInvoker();
      service = RouteService(
        invoker: failingInvoker,
        routePoolService: RoutePoolService(
          inMemoryRegions: [
            _benchmarkRegion(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              centerLat: 47.2383,
              centerLng: 9.5985,
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: jobs,
          inMemoryCandidates: <RoutePoolCandidate>[],
        ),
      );

      late RouteServiceException firstError;
      late RouteServiceException secondError;
      try {
        await service.generateRoundTrip(
          startPosition: _position(47.2383, 9.5985),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
          subscriptionTier: 'premium',
        );
      } on RouteServiceException catch (error) {
        firstError = error;
      }
      try {
        await service.generateRoundTrip(
          startPosition: _position(47.2383, 9.5985),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
          subscriptionTier: 'premium',
        );
      } on RouteServiceException catch (error) {
        secondError = error;
      }

      expect(failingInvoker.callCount, 6);
      expect(
        failingInvoker.bodies.every(
          (body) => body['max_candidate_attempts'] == 15,
        ),
        true,
      );
      expect(jobs, hasLength(1));
      expect(firstError.edgeMeta['code'], 'pool_bootstrap_pending');
      expect(firstError.edgeMeta['seed_job_created'], true);
      expect(firstError.edgeMeta['live_attempted'], true);
      expect(firstError.edgeMeta['live_fill_attempted'], true);
      expect(firstError.edgeMeta['live_fill_attempt_count'], 3);
      expect(
        firstError.edgeMeta['source_decision'],
        'search_again_on_demand_live_fill',
      );
      expect(firstError.edgeMeta['live_attempt_result'], isNot('success'));
      expect(secondError.edgeMeta['duplicate_job_prevented'], true);
      expect(secondError.edgeMeta['live_attempted'], true);
    },
  );

  test(
    'Premium On-Demand-Fill returned dritte gute Live-Route und staged Candidate',
    () async {
      final jobs = <RouteSeedJob>[];
      final candidates = <RoutePoolCandidate>[];
      final flakyInvoker = _FlakyCountingInvoker(
        _closedLoopResponse(),
        failuresBeforeSuccess: 2,
      );
      service = RouteService(
        invoker: flakyInvoker,
        routePoolService: RoutePoolService(
          inMemoryRegions: [
            _benchmarkRegion(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bregenz',
              cityCluster: 'Bregenz',
              centerLat: 47.5031,
              centerLng: 9.7471,
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: jobs,
          inMemoryCandidates: candidates,
        ),
      );

      final route = await service.generateRoundTrip(
        startPosition: _position(47.5031, 9.7471),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        avoidHighways: true,
        forceFreshVariant: true,
        subscriptionTier: 'premium',
      );

      expect(flakyInvoker.callCount, 3);
      expect(route.edgeMeta['route_source'], 'mapbox');
      expect(route.edgeMeta['live_fill_attempted'], true);
      expect(route.edgeMeta['live_fill_attempt_count'], 3);
      expect(route.edgeMeta['live_fill_success'], true);
      expect(route.edgeMeta['candidate_inserted'], true);
      expect(route.edgeMeta['candidate_saved'], true);
      expect(route.edgeMeta['candidate_save_failed'], false);
      expect(jobs, hasLength(1));
      expect(candidates, hasLength(1));
      expect(candidates.single.candidateSource, 'premium_live');
      expect(
        candidates.single.routeFingerprint,
        route.edgeMeta['route_fingerprint'],
      );
      expect(
        candidates.single.routePayload['candidate_subscription_tier'],
        'premium',
      );
    },
  );

  test('Candidate-Save-Fehler blockiert gute On-Demand-Route nicht', () async {
    service = RouteService(
      invoker: invoker,
      routePoolService: _ThrowingCandidateRoutePoolService(),
    );

    final route = await service.generateRoundTrip(
      startPosition: _position(47.5031, 9.7471),
      targetDistanceKm: 50,
      mode: 'Sport Mode',
      planningType: 'Zufall',
      avoidHighways: false,
      forceFreshVariant: true,
      subscriptionTier: 'premium',
    );

    expect(route.edgeMeta['route_source'], 'mapbox');
    expect(route.edgeMeta['candidate_inserted'], false);
    expect(route.edgeMeta['candidate_saved'], false);
    expect(route.edgeMeta['candidate_save_failed'], true);
    expect(route.edgeMeta['candidate_save_error_type'], 'StateError');
    expect(
      route.edgeMeta['candidate_save_error_reason'],
      contains('simulated candidate save failure'),
    );
    final orchestration = Map<String, dynamic>.from(
      route.edgeMeta['orchestration'] as Map,
    );
    expect(orchestration['candidate_saved'], false);
    expect(orchestration['candidate_save_failed'], true);
    expect(orchestration['candidate_save_error_type'], 'StateError');
  });

  test(
    '75-km Free-Anfrage nutzt keine 50-km Poolroute und queued exakten Seed-Job',
    () async {
      final jobs = <RouteSeedJob>[];
      final wrongBucketRoute = _poolMatchWithResponse(
        response: _closedLoopResponse(),
        id: 'pool-dornbirn-50-sport-nohighway',
        cityCluster: 'Dornbirn',
        startDistanceKm: 0.2,
      ).route;
      service = RouteService(
        invoker: invoker,
        routePoolService: RoutePoolService(
          inMemoryRegions: [
            _benchmarkRegion(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Dornbirn',
              cityCluster: 'Dornbirn',
              centerLat: 47.5162,
              centerLng: 9.7471,
            ),
          ],
          inMemoryRoutes: [wrongBucketRoute],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: jobs,
          inMemoryCandidates: <RoutePoolCandidate>[],
        ),
      );

      late RouteServiceException error;
      try {
        await service.generateRoundTrip(
          startPosition: _start(),
          targetDistanceKm: 75,
          mode: 'Sport Mode',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
          subscriptionTier: 'free',
        );
      } on RouteServiceException catch (caught) {
        error = caught;
      }

      expect(invoker.callCount, 0);
      expect(error.userMessage, contains('Neue Vorschläge'));
      expect(error.edgeMeta['code'], 'pool_bootstrap_pending');
      expect(error.edgeMeta['response_code'], 'pool_bootstrap_pending');
      expect(error.edgeMeta['requested_distance_bucket'], 75);
      expect(error.edgeMeta['pool_exact_bucket_missing'], true);
      expect(error.edgeMeta['seed_job_created'], true);
      expect(jobs, hasLength(1));
      expect(jobs.single.distanceBucket, 75);
      expect(jobs.single.styleKey, 'sport_mode');
    },
  );

  test(
    '100-km Premium-NoRoute nutzt keine 75-km Poolroute und queued exakten Seed-Job',
    () async {
      final jobs = <RouteSeedJob>[];
      final baseWrongBucketRoute = _poolMatchWithResponse(
        response: _closedLoopResponse(),
        id: 'pool-dornbirn-75-kurven-nohighway',
        cityCluster: 'Dornbirn',
        startDistanceKm: 0.2,
      ).route;
      final wrongBucketRoute = RoutePoolEntry(
        id: baseWrongBucketRoute.id,
        countryCode: baseWrongBucketRoute.countryCode,
        admin1Name: baseWrongBucketRoute.admin1Name,
        admin2Name: baseWrongBucketRoute.admin2Name,
        cityCluster: baseWrongBucketRoute.cityCluster,
        startLat: baseWrongBucketRoute.startLat,
        startLng: baseWrongBucketRoute.startLng,
        distanceKm: 75,
        distanceBucket: 75,
        routeType: baseWrongBucketRoute.routeType,
        styleTags: const ['Kurvenjagd'],
        avoidsHighway: baseWrongBucketRoute.avoidsHighway,
        hasHighway: baseWrongBucketRoute.hasHighway,
        qualityScore: baseWrongBucketRoute.qualityScore,
        verified: baseWrongBucketRoute.verified,
        geometry: baseWrongBucketRoute.geometry,
        durationSeconds: baseWrongBucketRoute.durationSeconds,
      );
      service = RouteService(
        invoker: _AlwaysFailingInvoker(),
        routePoolService: RoutePoolService(
          inMemoryRegions: [
            _benchmarkRegion(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Dornbirn',
              cityCluster: 'Dornbirn',
              centerLat: 47.5162,
              centerLng: 9.7471,
            ),
          ],
          inMemoryRoutes: [wrongBucketRoute],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: jobs,
          inMemoryCandidates: <RoutePoolCandidate>[],
        ),
      );

      late RouteServiceException error;
      try {
        await service.generateRoundTrip(
          startPosition: _start(),
          targetDistanceKm: 100,
          mode: 'Kurvenjagd',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
          subscriptionTier: 'premium',
        );
      } on RouteServiceException catch (caught) {
        error = caught;
      }

      expect(error.edgeMeta['code'], 'pool_bootstrap_pending');
      expect(error.edgeMeta['requested_distance_bucket'], 100);
      expect(error.edgeMeta['pool_exact_bucket_missing'], true);
      expect(error.edgeMeta['seed_job_created'], true);
      expect(RouteService.lastRoutePoolFallbackUsed, false);
      expect(jobs, hasLength(1));
      expect(jobs.single.distanceBucket, 100);
      expect(jobs.single.styleKey, 'kurvenjagd');
    },
  );

  test(
    'Free-User in harter Region bekommt keine versteckte Live-Route und ehrliches curated-needed Meta',
    () async {
      final jobs = <RouteSeedJob>[];
      service = RouteService(
        invoker: invoker,
        routePoolService: RoutePoolService(
          inMemoryRegions: [
            _benchmarkRegion(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bludenz',
              cityCluster: 'Bludenz',
              centerLat: 47.1548,
              centerLng: 9.8220,
              fallbackRadiusKm: 35,
              difficultyLevel: 'hard',
              hardRegionStatus: 'curated_needed',
              bootstrapEnabled: false,
              curatedSeedPreferred: true,
              defaultTargetPoolSize: 8,
              defaultMaxPoolSize: 10,
              healthyThreshold: 4,
              thinThreshold: 1,
              seedBudgetUnits: 0,
              seedCooldownMinutes: 180,
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: jobs,
          inMemoryCandidates: <RoutePoolCandidate>[],
        ),
      );

      late RouteServiceException error;
      try {
        await service.generateRoundTrip(
          startPosition: _position(47.1548, 9.8220),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
          subscriptionTier: 'free',
        );
      } on RouteServiceException catch (caught) {
        error = caught;
      }

      expect(invoker.callCount, 0);
      expect(jobs, isEmpty);
      expect(error.userMessage, contains('Bludenz'));
      expect(error.edgeMeta['route_source'], 'pool');
      expect(error.edgeMeta['coverage_status'], 'hard_region_curated_needed');
      expect(error.edgeMeta['region_difficulty'], 'hard');
      expect(error.edgeMeta['hard_region_status'], 'curated_needed');
      expect(error.edgeMeta['seed_job_created'], false);
      expect(error.edgeMeta['duplicate_job_prevented'], false);
      expect(error.edgeMeta['pool_bootstrap_pending'], false);
      expect(error.edgeMeta['chosen_cluster'], 'Bludenz');
      expect(error.edgeMeta['target_pool_size'], isA<int>());
    },
  );

  test(
    'Premium-Hard-Region versucht Live vor Warmup und behält Coverage-Meta',
    () async {
      final failingInvoker = _AlwaysFailingInvoker();
      final poolService = _FakeRoutePoolService(
        null,
        coverageResponses: [
          _coverageCheck(
            cityCluster: 'Bludenz',
            coverageStatus: 'hard_region_curated_needed',
            regionDifficulty: 'hard',
            hardRegionStatus: 'curated_needed',
            bootstrapEnabled: false,
            curatedSeedPreferred: true,
            targetPoolSize: 8,
            maxPoolSize: 10,
            seedJobCreated: false,
            duplicateJobPrevented: false,
            bootstrapPending: false,
          ),
          _coverageCheck(
            cityCluster: 'Bludenz',
            coverageStatus: 'hard_region_curated_needed',
            regionDifficulty: 'hard',
            hardRegionStatus: 'curated_needed',
            bootstrapEnabled: false,
            curatedSeedPreferred: true,
            targetPoolSize: 8,
            maxPoolSize: 10,
            seedJobCreated: false,
            duplicateJobPrevented: false,
            bootstrapPending: false,
          ),
        ],
      );
      service = RouteService(
        invoker: failingInvoker,
        routePoolService: poolService,
      );

      late RouteServiceException error;
      try {
        await service.generateRoundTrip(
          startPosition: _position(47.1548, 9.8220),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
          subscriptionTier: 'premium',
        );
      } on RouteServiceException catch (caught) {
        error = caught;
      }

      expect(error.edgeMeta['coverage_status'], 'hard_region_curated_needed');
      expect(error.edgeMeta['region_difficulty'], 'hard');
      expect(error.edgeMeta['seed_job_created'], false);
      expect(error.edgeMeta['duplicate_job_prevented'], false);
      expect(failingInvoker.callCount, greaterThan(0));
      expect(error.edgeMeta['live_attempted'], true);
      expect(error.edgeMeta['live_attempt_count'], failingInvoker.callCount);
      expect(error.edgeMeta['pool_checked'], true);
      expect(poolService.ensureCoverageCallCount, 1);
    },
  );

  test(
    'Basic-User in leerer Region legt Bootstrap-Job an, darf aber Live-Route erhalten und staged Kandidat',
    () async {
      final jobs = <RouteSeedJob>[];
      final candidates = <RoutePoolCandidate>[];
      service = RouteService(
        invoker: invoker,
        routePoolService: RoutePoolService(
          inMemoryRegions: [
            _benchmarkRegion(
              countryCode: 'DE',
              admin1Name: 'Baden-Württemberg',
              admin2Name: 'Stuttgart',
              cityCluster: 'Stuttgart',
              centerLat: 48.7758,
              centerLng: 9.1829,
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: jobs,
          inMemoryCandidates: candidates,
        ),
      );

      final route = await service.generateRoundTrip(
        startPosition: _position(48.78, 9.18),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        avoidHighways: true,
        forceFreshVariant: true,
        subscriptionTier: 'basic',
      );

      expect(invoker.callCount, greaterThan(0));
      expect(route.edgeMeta['subscriptionTier'], 'basic');
      expect(RouteService.lastRouteSeedJobCreated, true);
      expect(jobs, hasLength(1));
      expect(candidates, hasLength(1));
      expect(candidates.single.candidateSource, 'basic_live');
      expect(candidates.single.isVerifiedPool, isFalse);
    },
  );

  test(
    'Basic-User in Hard-Region darf kontrolliert live explorieren und Candidate stagen',
    () async {
      final jobs = <RouteSeedJob>[];
      final candidates = <RoutePoolCandidate>[];
      final hardInvoker = _CountingInvoker(_closedLoopResponse());
      service = RouteService(
        invoker: hardInvoker,
        routePoolService: RoutePoolService(
          inMemoryRegions: [
            _benchmarkRegion(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bludenz',
              cityCluster: 'Bludenz',
              centerLat: 47.1548,
              centerLng: 9.8220,
              fallbackRadiusKm: 35,
              difficultyLevel: 'hard',
              hardRegionStatus: 'curated_needed',
              bootstrapEnabled: false,
              curatedSeedPreferred: true,
              defaultTargetPoolSize: 8,
              defaultMaxPoolSize: 10,
              healthyThreshold: 4,
              thinThreshold: 1,
              seedBudgetUnits: 0,
              seedCooldownMinutes: 180,
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: jobs,
          inMemoryCandidates: candidates,
        ),
      );

      final route = await service.generateRoundTrip(
        startPosition: _position(47.1548, 9.8220),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        avoidHighways: true,
        forceFreshVariant: true,
        subscriptionTier: 'basic',
      );

      expect(hardInvoker.callCount, greaterThan(0));
      expect(jobs, hasLength(1));
      expect(jobs.single.jobKind, 'manual_seed');
      expect(jobs.single.maxAttempts, 1);
      expect(
        jobs.single.maxMapboxCalls,
        lessThanOrEqualTo(RoutePoolService.userDemandSeedMaxMapboxCalls),
      );
      expect(jobs.single.seedBudgetUnits, greaterThanOrEqualTo(1));
      expect(candidates, hasLength(1));
      expect(candidates.single.candidateSource, 'basic_live');
      expect(route.edgeMeta['hard_region_exploration_used'], true);
      expect(route.edgeMeta['seed_job_created'], true);
      expect(
        route.edgeMeta['source_decision']?.toString(),
        contains('hard_region_live_exploration'),
      );
      expect(route.edgeMeta['candidate_saved'], true);
    },
  );
}
