import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:functions_client/functions_client.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/data/services/route_quality_validator.dart';
import 'package:cruise_connect/data/services/route_pool_service.dart';
import 'package:cruise_connect/data/services/route_scenario.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/route_pool_entry.dart';
import 'package:cruise_connect/domain/models/route_region.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

class _LiveHttpInvoker implements RouteEdgeInvoker {
  _LiveHttpInvoker(this.endpoint);

  final Uri endpoint;
  int _callCount = 0;
  bool _printedSampleBody = false;
  final List<Map<String, dynamic>> _requestBodies = [];

  int takeCallCount() {
    final count = _callCount;
    _callCount = 0;
    return count;
  }

  List<Map<String, dynamic>> takeRequestBodies() {
    final bodies = List<Map<String, dynamic>>.from(_requestBodies);
    _requestBodies.clear();
    return bodies;
  }

  String get debugEndpoint => endpoint.toString();

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    _callCount += 1;
    _requestBodies.add(Map<String, dynamic>.from(body));
    if (!_printedSampleBody) {
      _printedSampleBody = true;
      // ignore: avoid_print
      print('LIVE_REQUEST_SAMPLE ${jsonEncode(body)}');
    }
    final payload = jsonEncode(body);
    final result = await Process.run('curl', [
      '-sS',
      '--http1.1',
      '-X',
      'POST',
      endpoint.toString(),
      '-H',
      'Content-Type: application/json',
      '-H',
      'Accept: application/json',
      '-H',
      'apikey: ${AppConstants.supabaseAnonKey}',
      '-H',
      'Authorization: Bearer ${AppConstants.supabaseAnonKey}',
      '--data-binary',
      payload,
      '-w',
      '\n__HTTP_STATUS__:%{http_code}',
    ]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'curl',
        const [],
        (result.stderr as String?)?.trim().isNotEmpty == true
            ? (result.stderr as String).trim()
            : 'curl exited with ${result.exitCode}',
        result.exitCode,
      );
    }
    final stdout = (result.stdout as String).trimRight();
    final markerIndex = stdout.lastIndexOf('__HTTP_STATUS__:');
    final raw = markerIndex >= 0 ? stdout.substring(0, markerIndex).trim() : '';
    final statusText = markerIndex >= 0
        ? stdout.substring(markerIndex + '__HTTP_STATUS__:'.length).trim()
        : '0';
    final statusCode = int.tryParse(statusText) ?? 0;
    final data = raw.isEmpty ? null : jsonDecode(raw);
    if (statusCode >= 400) {
      // ignore: avoid_print
      print(
        'LIVE_REQUEST_ERROR HttpError $statusCode: '
        '${raw.isEmpty ? '<empty>' : raw}',
      );
    }
    return FunctionResponse(data: data, status: statusCode);
  }
}

class _Scenario {
  const _Scenario({
    required this.name,
    required this.routeType,
    required this.run,
    required this.start,
    this.targetDistanceKm,
    this.destination,
    this.mode = 'Sport Mode',
    this.detourLevel = 0,
    this.avoidHighways = false,
    this.variantGroup,
  });

  final String name;
  final String routeType;
  final int run;
  final geo.Position start;
  final int? targetDistanceKm;
  final geo.Position? destination;
  final String mode;
  final int detourLevel;
  final bool avoidHighways;
  final String? variantGroup;
}

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

RoutePoolService _seededRoutePoolServiceForBenchmark() {
  final seedFile = File('supabase/seed/route_pool_vorarlberg.json');
  if (!seedFile.existsSync()) return RoutePoolService();

  final seed = jsonDecode(seedFile.readAsStringSync()) as Map<String, dynamic>;
  final routes = (seed['routes'] as List? ?? const [])
      .cast<Map>()
      .map((route) {
        final json = Map<String, dynamic>.from(route);
        json['id'] ??= json['route_fingerprint'];
        return RoutePoolEntry.fromJson(json);
      })
      .toList(growable: false);
  if (routes.isEmpty) return RoutePoolService();

  return RoutePoolService(
    inMemoryRoutes: routes,
    inMemoryRegions: const [
      RouteRegion(
        countryCode: 'AT',
        admin1Name: 'Vorarlberg',
        admin2Name: 'Bregenz',
        cityCluster: 'Bregenz',
        centerLat: 47.5031,
        centerLng: 9.7471,
        fallbackRadiusKm: 30,
      ),
      RouteRegion(
        countryCode: 'AT',
        admin1Name: 'Vorarlberg',
        admin2Name: 'Dornbirn',
        cityCluster: 'Dornbirn',
        centerLat: 47.4125,
        centerLng: 9.7414,
        fallbackRadiusKm: 30,
      ),
      RouteRegion(
        countryCode: 'AT',
        admin1Name: 'Vorarlberg',
        admin2Name: 'Feldkirch',
        cityCluster: 'Feldkirch',
        centerLat: 47.2386,
        centerLng: 9.5986,
        fallbackRadiusKm: 30,
      ),
      RouteRegion(
        countryCode: 'AT',
        admin1Name: 'Vorarlberg',
        admin2Name: 'Bludenz',
        cityCluster: 'Bludenz',
        centerLat: 47.1548,
        centerLng: 9.8220,
        fallbackRadiusKm: 35,
      ),
      RouteRegion(
        countryCode: 'AT',
        admin1Name: 'Vorarlberg',
        admin2Name: 'Rheintal-Sued',
        cityCluster: 'Rheintal-Sued',
        centerLat: 47.3499,
        centerLng: 9.6584,
        fallbackRadiusKm: 12,
      ),
    ],
  );
}

List<_Scenario> _buildScenarios() {
  final dornbirn = _position(47.4125, 9.7414);
  final goetzis = _position(47.3331, 9.6336);
  final hohenems = _position(47.3667, 9.6831);
  final feldkirch = _position(47.2413, 9.5986);
  final bregenz = _position(47.5031, 9.7471);
  final bludenz = _position(47.1548, 9.8220);

  final scenarios = <_Scenario>[];
  void addRoundTripScenario({
    required String name,
    required geo.Position start,
    required int targetDistanceKm,
    required String mode,
    required int runs,
    bool avoidHighways = false,
  }) {
    for (var i = 0; i < runs; i++) {
      scenarios.add(
        _Scenario(
          name: name,
          routeType: 'ROUND_TRIP',
          run: i + 1,
          start: start,
          targetDistanceKm: targetDistanceKm,
          mode: mode,
          avoidHighways: avoidHighways,
        ),
      );
    }
  }

  addRoundTripScenario(
    name: 'RT Goetzis 50 Kurvenjagd ohne Autobahn',
    start: goetzis,
    targetDistanceKm: 50,
    mode: 'Kurvenjagd',
    runs: 5,
    avoidHighways: true,
  );
  addRoundTripScenario(
    name: 'RT Goetzis 50 Sport ohne Autobahn',
    start: goetzis,
    targetDistanceKm: 50,
    mode: 'Sport Mode',
    runs: 5,
    avoidHighways: true,
  );
  addRoundTripScenario(
    name: 'RT Hohenems 50 Sport ohne Autobahn',
    start: hohenems,
    targetDistanceKm: 50,
    mode: 'Sport Mode',
    runs: 5,
    avoidHighways: true,
  );
  addRoundTripScenario(
    name: 'RT Dornbirn 50 Sport mit Autobahn',
    start: dornbirn,
    targetDistanceKm: 50,
    mode: 'Sport Mode',
    runs: 5,
    avoidHighways: false,
  );
  addRoundTripScenario(
    name: 'RT Dornbirn 50 Sport ohne Autobahn',
    start: dornbirn,
    targetDistanceKm: 50,
    mode: 'Sport Mode',
    runs: 5,
    avoidHighways: true,
  );
  addRoundTripScenario(
    name: 'RT Dornbirn 50 Kurvenjagd ohne Autobahn',
    start: dornbirn,
    targetDistanceKm: 50,
    mode: 'Kurvenjagd',
    runs: 5,
    avoidHighways: true,
  );
  addRoundTripScenario(
    name: 'RT Dornbirn 75 Sport ohne Autobahn',
    start: dornbirn,
    targetDistanceKm: 75,
    mode: 'Sport Mode',
    runs: 5,
    avoidHighways: true,
  );
  addRoundTripScenario(
    name: 'RT Dornbirn 75 Kurvenjagd ohne Autobahn',
    start: dornbirn,
    targetDistanceKm: 75,
    mode: 'Kurvenjagd',
    runs: 5,
    avoidHighways: true,
  );
  addRoundTripScenario(
    name: 'RT Dornbirn 100 Sport ohne Autobahn',
    start: dornbirn,
    targetDistanceKm: 100,
    mode: 'Sport Mode',
    runs: 5,
    avoidHighways: true,
  );
  addRoundTripScenario(
    name: 'RT Dornbirn 100 Kurvenjagd ohne Autobahn',
    start: dornbirn,
    targetDistanceKm: 100,
    mode: 'Kurvenjagd',
    runs: 5,
    avoidHighways: true,
  );
  addRoundTripScenario(
    name: 'RT Bregenz 50 Sport ohne Autobahn',
    start: bregenz,
    targetDistanceKm: 50,
    mode: 'Sport Mode',
    runs: 3,
    avoidHighways: true,
  );
  addRoundTripScenario(
    name: 'RT Bregenz 75 Kurvenjagd ohne Autobahn',
    start: bregenz,
    targetDistanceKm: 75,
    mode: 'Kurvenjagd',
    runs: 5,
    avoidHighways: true,
  );
  addRoundTripScenario(
    name: 'RT Feldkirch 50 Sport ohne Autobahn',
    start: feldkirch,
    targetDistanceKm: 50,
    mode: 'Sport Mode',
    runs: 3,
    avoidHighways: true,
  );
  addRoundTripScenario(
    name: 'RT Feldkirch 75 Sport ohne Autobahn',
    start: feldkirch,
    targetDistanceKm: 75,
    mode: 'Sport Mode',
    runs: 5,
    avoidHighways: true,
  );
  addRoundTripScenario(
    name: 'RT Bludenz 50 Sport ohne Autobahn',
    start: bludenz,
    targetDistanceKm: 50,
    mode: 'Sport Mode',
    runs: 5,
    avoidHighways: true,
  );
  addRoundTripScenario(
    name: 'RT Bludenz 75 Sport ohne Autobahn',
    start: bludenz,
    targetDistanceKm: 75,
    mode: 'Sport Mode',
    runs: 5,
    avoidHighways: true,
  );
  addRoundTripScenario(
    name: 'RT Bludenz 100 Sport ohne Autobahn',
    start: bludenz,
    targetDistanceKm: 100,
    mode: 'Sport Mode',
    runs: 3,
    avoidHighways: true,
  );

  final pairs = [
    ('AB Dornbirn->Feldkirch', dornbirn, feldkirch),
    ('AB Dornbirn->Bregenz', dornbirn, bregenz),
  ];
  final detours = [
    ('Direkt', 0, 'Standard'),
    ('Kleiner Umweg', 1, 'Sport Mode'),
    ('Mittlerer Umweg', 2, 'Sport Mode'),
    ('Großer Umweg', 3, 'Sport Mode'),
  ];

  for (final pair in pairs) {
    for (final detour in detours) {
      for (final avoidHighways in [false, true]) {
        for (var repeat = 0; repeat < 2; repeat++) {
          scenarios.add(
            _Scenario(
              name:
                  '${pair.$1} ${detour.$1} ${avoidHighways ? 'ohne Autobahn' : 'mit Autobahn'}',
              routeType: 'POINT_TO_POINT',
              run: repeat + 1,
              start: pair.$2,
              destination: pair.$3,
              mode: detour.$3,
              detourLevel: detour.$2,
              avoidHighways: avoidHighways,
              variantGroup:
                  '${pair.$1}|run=${repeat + 1}|h=${avoidHighways ? 1 : 0}',
            ),
          );
        }
      }
    }
  }

  return scenarios;
}

String _bucketFor({
  required String tier,
  required String routeType,
  required double? overlapPercent,
}) {
  if (tier == 'error') return 'error';
  if (tier == 'ideal' || tier == 'good') return 'good';
  final overlapLimit = routeType == 'ROUND_TRIP' ? 42.0 : 24.0;
  if (overlapPercent != null && overlapPercent > overlapLimit) {
    return 'weak';
  }
  return 'acceptable';
}

Map<String, dynamic> _scenarioSummary(Iterable<Map<String, dynamic>> rows) {
  final entries = rows.toList();
  final durations = entries.map((entry) => entry['durationMs'] as int).toList()
    ..sort();
  return <String, dynamic>{
    'runs': entries.length,
    'usableRoutes': entries.where((entry) {
      final bucket = entry['bucket'];
      return bucket == 'good' || bucket == 'acceptable';
    }).length,
    'goodRoutes': entries.where((entry) => entry['bucket'] == 'good').length,
    'acceptableRoutes': entries
        .where((entry) => entry['bucket'] == 'acceptable')
        .length,
    'weakRoutes': entries.where((entry) => entry['bucket'] == 'weak').length,
    'realErrors': entries.where((entry) => entry['bucket'] == 'error').length,
    'averageDurationMs':
        entries
            .map((entry) => entry['durationMs'] as int)
            .fold<int>(0, (sum, value) => sum + value) /
        entries.length,
    'p95DurationMs': durations.isEmpty
        ? 0
        : durations[(durations.length * 0.95).floor().clamp(
            0,
            durations.length - 1,
          )],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const runBenchmark = bool.fromEnvironment(
    'RUN_ROUTE_BENCHMARK',
    defaultValue: false,
  );
  const warm = bool.fromEnvironment('BENCHMARK_WARM', defaultValue: true);
  const smoke = bool.fromEnvironment('BENCHMARK_SMOKE', defaultValue: false);
  const benchmarkLimit = int.fromEnvironment(
    'BENCHMARK_LIMIT',
    defaultValue: 0,
  );
  const benchmarkScenario = String.fromEnvironment(
    'BENCHMARK_SCENARIO',
    defaultValue: '',
  );
  const benchmarkRunsPerScenario = int.fromEnvironment(
    'BENCHMARK_RUNS_PER_SCENARIO',
    defaultValue: 0,
  );
  const endpointValue = String.fromEnvironment(
    'BENCHMARK_ENDPOINT',
    defaultValue:
        'https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/generate-cruise-route',
  );
  const outputPath = String.fromEnvironment(
    'BENCHMARK_OUTPUT',
    defaultValue: '/tmp/route-benchmark-live.json',
  );

  /// Nur A→B-Szenarien (Check-Matrix Dornbirn→Feldkirch/Bregenz), ohne Rundkurs.
  const benchmarkP2pOnly = bool.fromEnvironment(
    'BENCHMARK_P2P_ONLY',
    defaultValue: false,
  );
  const benchmarkUiSequence = bool.fromEnvironment(
    'BENCHMARK_UI_SEQUENCE',
    defaultValue: false,
  );

  test(
    'live routing benchmark matrix',
    skip: !runBenchmark,
    () async {
      RouteService.disableBackgroundPreparation = !warm;
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        anonKey: AppConstants.supabaseAnonKey,
        debug: false,
      );
      RouteService.resetForTests();
      final endpoint = Uri.parse(endpointValue);
      const validator = RouteQualityValidator();
      if (benchmarkUiSequence) {
        final dornbirn = _position(47.4125, 9.7414);
        final invoker = _LiveHttpInvoker(endpoint);
        final service = RouteService(
          invoker: invoker,
          routePoolService: _seededRoutePoolServiceForBenchmark(),
        );
        const sequence = <({String label, int km, String mode, bool avoid})>[
          (
            label: '1 50 Sport Autobahn AN',
            km: 50,
            mode: 'Sport Mode',
            avoid: false,
          ),
          (label: '2 nochmal suchen', km: 50, mode: 'Sport Mode', avoid: false),
          (label: '3 Autobahn AUS', km: 50, mode: 'Sport Mode', avoid: true),
          (label: '4 Kurvenjagd AUS', km: 50, mode: 'Kurvenjagd', avoid: true),
          (label: '5 Abendrunde AUS', km: 50, mode: 'Abendrunde', avoid: true),
          (
            label: '6 100 Kurvenjagd AUS',
            km: 100,
            mode: 'Kurvenjagd',
            avoid: true,
          ),
        ];
        final rows = <Map<String, dynamic>>[];
        RouteResult? previous;
        String? previousScenarioKey;
        String? previousVariantHint;
        String? previousFingerprintHint;
        int? previousKm;
        String? previousStyle;
        bool? previousAvoidHighways;

        for (var index = 0; index < sequence.length; index++) {
          final step = sequence[index];
          final forceFreshVariant = previous != null;
          final settingsChanged =
              previous != null &&
              (previousKm != step.km ||
                  previousStyle != step.mode ||
                  previousAvoidHighways != step.avoid);
          final trigger = previous == null
              ? 'firstSearch'
              : settingsChanged
              ? 'settingsChanged'
              : 'searchAgain';
          final scenario = RouteScenario(
            routeType: 'ROUND_TRIP',
            startLatitude: dornbirn.latitude,
            startLongitude: dornbirn.longitude,
            style: step.mode,
            planningType: 'Zufall',
            targetDistanceKm: step.km.toDouble(),
            avoidHighways: step.avoid,
          );
          final stopwatch = Stopwatch()..start();
          var success = false;
          String? errorCode;
          String? errorMessage;
          double? distanceKm;
          double? similarityToPreviousPercent;
          String? fingerprint;
          String? effectiveExcludes;
          String? edgeRoutingBuildId;
          bool? avoidHighwaysRequested;
          String? variantHint;
          String? fingerprintHint;
          String routeSource = 'error';
          bool poolFallbackUsed = false;
          String? poolMatchId;
          String? poolMatchTier;
          double? poolStartDistanceKm;

          try {
            final result = await service.generateRoundTrip(
              startPosition: dornbirn,
              targetDistanceKm: step.km,
              mode: step.mode,
              planningType: 'Zufall',
              avoidHighways: step.avoid,
              forceFreshVariant: forceFreshVariant,
              debugTrigger: trigger,
            );
            success = true;
            distanceKm = result.distanceKm;
            fingerprint =
                RouteService.lastRouteDebugFingerprint ??
                RouteQualityValidator.buildRouteFingerprint(
                  result.coordinates,
                  distanceKm: result.distanceKm,
                );
            if (previous != null) {
              similarityToPreviousPercent =
                  RouteQualityValidator.calculateRouteSimilarityPercent(
                    result.coordinates,
                    previous.coordinates,
                    sampleCount: 48,
                    proximityMeters: 145.0,
                  );
            }
            effectiveExcludes = result.edgeMeta['effective_excludes']
                ?.toString();
            edgeRoutingBuildId = result.edgeMeta['routing_build_id']
                ?.toString();
            avoidHighwaysRequested =
                result.edgeMeta['avoid_highways_requested'] == true;
            routeSource =
                result.edgeMeta['route_source']?.toString() ??
                result.edgeMeta['source']?.toString() ??
                'mapbox';
            poolFallbackUsed =
                RouteService.lastRoutePoolFallbackUsed || routeSource == 'pool';
            poolMatchId = result.edgeMeta['pool_match_id']?.toString();
            poolMatchTier = result.edgeMeta['pool_match_tier']?.toString();
            poolStartDistanceKm =
                (result.edgeMeta['pool_start_distance_km'] as num?)?.toDouble();
            final searchSummary = result.edgeMeta['search_summary'];
            if (searchSummary is Map<String, dynamic>) {
              variantHint = searchSummary['variant_hint']?.toString();
              fingerprintHint = searchSummary['fingerprint_hint']?.toString();
            }
            previous = result;
            previousKm = step.km;
            previousStyle = step.mode;
            previousAvoidHighways = step.avoid;
          } catch (error) {
            if (error is RouteServiceException) {
              errorCode = error.type.name;
              errorMessage = error.userMessage;
              effectiveExcludes = error.edgeMeta['effective_excludes']
                  ?.toString();
              edgeRoutingBuildId = error.edgeMeta['routing_build_id']
                  ?.toString();
              avoidHighwaysRequested =
                  error.edgeMeta['avoid_highways_requested'] == true;
              variantHint = error.edgeMeta['variant_hint']?.toString();
              fingerprintHint = error.edgeMeta['fingerprint_hint']?.toString();
            } else {
              errorCode = error.runtimeType.toString();
              errorMessage = error.toString();
            }
          }

          stopwatch.stop();
          final edgeRequests = invoker.takeCallCount();
          final requestBodies = invoker.takeRequestBodies();
          final requestVariantHints = requestBodies
              .map((body) => body['route_variant_hint']?.toString())
              .whereType<String>()
              .toList();
          final requestFingerprintHints = requestBodies
              .map((body) => body['route_fingerprint_hint']?.toString())
              .whereType<String>()
              .toList();
          final requestAvoidHighwaysValues = requestBodies
              .map((body) => body['avoid_highways'] == true)
              .toSet()
              .toList();
          final scenarioKeyChanged =
              previousScenarioKey == null ||
              previousScenarioKey != scenario.scenarioKey;
          final variantPathChanged =
              previousVariantHint == null ||
              previousVariantHint != variantHint ||
              previousFingerprintHint != fingerprintHint;
          final row = <String, dynamic>{
            'step': step.label,
            'endpoint': endpoint.toString(),
            'success': success,
            'source': routeSource,
            'routeSource': routeSource,
            'durationMs': stopwatch.elapsedMilliseconds,
            'edgeRequests': edgeRequests,
            'selectedKm': step.km,
            'selectedStyle': step.mode,
            'avoidHighways': step.avoid,
            'forceFreshVariant': forceFreshVariant,
            'trigger': trigger,
            'scenarioKey': scenario.scenarioKey,
            'scenarioKeyChanged': scenarioKeyChanged,
            'variantPathChanged': variantPathChanged,
            'routeVariantHint': variantHint,
            'fingerprintHint': fingerprintHint,
            'requestAvoidHighwaysValues': requestAvoidHighwaysValues,
            'requestVariantHints': requestVariantHints,
            'requestFingerprintHints': requestFingerprintHints,
            'requestBodies': requestBodies,
            'cacheHit': RouteService.lastRouteSessionCacheHit,
            'poolFallbackUsed': poolFallbackUsed,
            'poolRouteId': poolMatchId,
            'poolMatchTier': poolMatchTier,
            'poolStartDistanceKm': poolStartDistanceKm,
            'apiCallCount': RouteService.lastRouteApiCallCount,
            'preparedBufferHit': RouteService.lastRoutePreparedBufferHit,
            'preparedBufferUsed': RouteService.lastRoutePreparedBufferUsed,
            'recentFallbackUsed': RouteService.lastRouteRecentFallbackUsed,
            'cachedFallbackUsed':
                RouteService.lastRoutePersistentCacheFallbackUsed,
            'persistentCacheFallbackUsed':
                RouteService.lastRoutePersistentCacheFallbackUsed,
            'duplicateFallbackUsed':
                RouteService.lastRouteDuplicateFallbackUsed,
            'emergencyFallbackUsed':
                RouteService.lastRouteEmergencyFallbackUsed,
            'edgeAvoidHighwaysRequested': avoidHighwaysRequested,
            'edgeEffectiveExcludes': effectiveExcludes,
            'edgeRoutingBuildId': edgeRoutingBuildId,
            'routeFingerprint': fingerprint,
            'similarityToLastRoute': similarityToPreviousPercent,
            'visibleDifferent':
                similarityToPreviousPercent == null ||
                similarityToPreviousPercent < 72.0,
            'motorwayExcludeOk': step.avoid
                ? (effectiveExcludes?.contains('motorway') ?? false)
                : !(effectiveExcludes?.contains('motorway') ?? false),
            'oldRouteFallbackUsed':
                RouteService.lastRouteSessionCacheHit ||
                RouteService.lastRouteRecentFallbackUsed ||
                RouteService.lastRoutePersistentCacheFallbackUsed,
            'fallbackUsed':
                RouteService.lastRouteRecentFallbackUsed ||
                RouteService.lastRoutePersistentCacheFallbackUsed ||
                RouteService.lastRouteDuplicateFallbackUsed ||
                poolFallbackUsed,
            'errorBannerWouldBeVisible': !success && previous == null,
            'errorCode': errorCode,
            'errorMessage': errorMessage,
            'distanceKm': distanceKm,
          };
          rows.add(row);
          // ignore: avoid_print
          print('UI_SEQUENCE ${jsonEncode(row)}');

          previousScenarioKey = scenario.scenarioKey;
          previousVariantHint = variantHint;
          previousFingerprintHint = fingerprintHint;
        }

        await File(
          outputPath,
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(rows));

        expect(rows, hasLength(sequence.length));
        for (final row in rows) {
          expect(row['edgeRequests'], greaterThan(0), reason: row.toString());
          expect(row['cacheHit'], false, reason: row.toString());
        }
        for (final row in rows.skip(2)) {
          expect(row['motorwayExcludeOk'], true, reason: row.toString());
          expect(row['oldRouteFallbackUsed'], false, reason: row.toString());
        }
        expect(rows[1]['variantPathChanged'], true, reason: rows[1].toString());
        expect(rows[1]['trigger'], 'searchAgain', reason: rows[1].toString());
        for (final row in rows.skip(2)) {
          expect(row['trigger'], 'settingsChanged', reason: row.toString());
        }
        expect(
          (rows[1]['similarityToLastRoute'] as double?) == null ||
              (rows[1]['similarityToLastRoute'] as double) < 72.0 ||
              rows[1]['duplicateFallbackUsed'] == true,
          true,
          reason: rows[1].toString(),
        );
        return;
      }
      final scenarios = _buildScenarios();
      var selectedScenarios = scenarios.toList();
      if (benchmarkP2pOnly) {
        selectedScenarios = selectedScenarios
            .where((s) => s.routeType == 'POINT_TO_POINT')
            .toList();
      }
      if (smoke) {
        selectedScenarios = selectedScenarios.take(8).toList();
      }
      if (benchmarkScenario.isNotEmpty) {
        selectedScenarios = selectedScenarios
            .where((scenario) => scenario.name == benchmarkScenario)
            .toList();
      }
      if (benchmarkRunsPerScenario > 0) {
        final runsByScenario = <String, int>{};
        selectedScenarios = selectedScenarios.where((scenario) {
          final nextCount = (runsByScenario[scenario.name] ?? 0) + 1;
          runsByScenario[scenario.name] = nextCount;
          return nextCount <= benchmarkRunsPerScenario;
        }).toList();
      }
      if (benchmarkLimit > 0) {
        selectedScenarios = selectedScenarios.take(benchmarkLimit).toList();
      }
      final results = <Map<String, dynamic>>[];
      final previousSuccessfulRoundTripByScenario =
          <String, List<List<double>>>{};

      var activeScenarioName = '';
      _LiveHttpInvoker? sharedInvoker;
      RouteService? sharedService;

      for (var index = 0; index < selectedScenarios.length; index++) {
        final scenario = selectedScenarios[index];
        final reuseWarmState = warm && activeScenarioName == scenario.name;
        if (!reuseWarmState) {
          RouteService.resetForTests();
          sharedInvoker = _LiveHttpInvoker(endpoint);
          sharedService = RouteService(
            invoker: sharedInvoker,
            routePoolService: _seededRoutePoolServiceForBenchmark(),
          );
          activeScenarioName = scenario.name;
        }
        final invoker = sharedInvoker!;
        final service = sharedService!;
        final stopwatch = Stopwatch()..start();

        var success = false;
        var tier = 'error';
        double? overlapPercent;
        double? distanceKm;
        int candidateAttempts = 0;
        String? qualityReason;
        String? errorCode;
        String? errorMessage;
        String? fingerprint;
        double? similarityToPreviousPercent;
        bool? distanceOkay;
        bool? motorwayExcludeActive;
        String? edgeRoutingBuildId;
        bool? styleEffective;
        String routeSource = 'error';
        bool poolFallbackUsed = false;
        String? poolMatchId;
        String? poolMatchTier;
        double? poolStartDistanceKm;
        bool? poolDistanceRuleApplied;
        bool? poolRejectedTooFar;
        bool? accessLegUsed;
        double? accessLegDistanceKm;
        bool? deadEndSpikeDetected;
        bool? geometryDifferent = scenario.routeType == 'ROUND_TRIP'
            ? true
            : false;

        try {
          if (scenario.routeType == 'ROUND_TRIP') {
            final forceFreshVariant =
                previousSuccessfulRoundTripByScenario[scenario.name] != null;
            final result = await service.generateRoundTrip(
              startPosition: scenario.start,
              targetDistanceKm: scenario.targetDistanceKm!,
              mode: scenario.mode,
              planningType: 'Zufall',
              avoidHighways: scenario.avoidHighways,
              forceFreshVariant: forceFreshVariant,
              debugTrigger: forceFreshVariant ? 'searchAgain' : 'firstSearch',
            );
            success = true;
            distanceKm = result.distanceKm;
            fingerprint = RouteQualityValidator.buildRouteFingerprint(
              result.coordinates,
              distanceKm: result.distanceKm,
            );
            final quality = validator.validateQuality(
              coordinates: result.coordinates,
              isRoundTrip: true,
              targetDistanceKm: scenario.targetDistanceKm!.toDouble(),
              actualDistanceKm: result.distanceKm ?? 0.0,
            );
            overlapPercent = quality.overlapPercent;
            distanceOkay = quality.distanceInTolerance;
            final classification = validator.classifyGeneratedRoute(
              quality: quality,
              isRoundTrip: true,
              coordinateCount: result.coordinates.length,
              actualDistanceKm: result.distanceKm ?? 0.0,
              targetDistanceKm: scenario.targetDistanceKm!.toDouble(),
              styleProfileKey: result.edgeMeta['style_profile']
                  ?.toString()
                  .toLowerCase(),
            );
            tier =
                result.edgeMeta['quality_tier']?.toString() ??
                classification.tier.name;
            qualityReason = result.edgeMeta['quality_reason']?.toString();
            final searchSummary = result.edgeMeta['search_summary'];
            if (searchSummary is Map<String, dynamic>) {
              candidateAttempts =
                  (searchSummary['candidate_attempts'] as num?)?.toInt() ?? 0;
            }
            final previousCoordinates =
                previousSuccessfulRoundTripByScenario[scenario.name];
            if (previousCoordinates != null) {
              similarityToPreviousPercent =
                  RouteQualityValidator.calculateRouteSimilarityPercent(
                    result.coordinates,
                    previousCoordinates,
                    sampleCount: 48,
                    proximityMeters: 145.0,
                  );
              geometryDifferent = similarityToPreviousPercent < 72.0;
            }
            previousSuccessfulRoundTripByScenario[scenario.name] = result
                .coordinates
                .map((point) => [point[0], point[1]])
                .toList();
            final excludes = result.edgeMeta['effective_excludes']?.toString();
            edgeRoutingBuildId = result.edgeMeta['routing_build_id']
                ?.toString();
            routeSource =
                result.edgeMeta['route_source']?.toString() ??
                result.edgeMeta['source']?.toString() ??
                'mapbox';
            poolFallbackUsed =
                RouteService.lastRoutePoolFallbackUsed || routeSource == 'pool';
            poolMatchId = result.edgeMeta['pool_match_id']?.toString();
            poolMatchTier = result.edgeMeta['pool_match_tier']?.toString();
            poolStartDistanceKm =
                (result.edgeMeta['pool_start_distance_km'] as num?)?.toDouble();
            poolDistanceRuleApplied =
                result.edgeMeta['pool_distance_rule_applied'] == true;
            poolRejectedTooFar =
                result.edgeMeta['pool_rejected_too_far'] == true;
            accessLegUsed = result.edgeMeta['access_leg_used'] == true;
            accessLegDistanceKm =
                (result.edgeMeta['access_leg_distance_km'] as num?)?.toDouble();
            deadEndSpikeDetected =
                result.edgeMeta['dead_end_spike_detected'] == true;
            if (routeSource == 'pool') {
              final hasHighway = result.edgeMeta['has_highway'] == true;
              final avoidsHighway = result.edgeMeta['avoids_highway'] == true;
              motorwayExcludeActive = scenario.avoidHighways
                  ? avoidsHighway && !hasHighway
                  : true;
            } else {
              motorwayExcludeActive = scenario.avoidHighways
                  ? (excludes?.contains('motorway') ?? false)
                  : !(excludes?.contains('motorway') ?? false);
            }
            styleEffective =
                (result.edgeMeta['mode']?.toString() ?? '') == scenario.mode;
          } else {
            final result = await service.generatePointToPoint(
              startPosition: scenario.start,
              destinationLat: scenario.destination!.latitude,
              destinationLng: scenario.destination!.longitude,
              mode: scenario.detourLevel > 0 ? scenario.mode : 'Standard',
              scenic: scenario.detourLevel > 0,
              routeVariant: scenario.detourLevel,
              avoidHighways: scenario.avoidHighways,
            );
            success = true;
            distanceKm = result.distanceKm;
            fingerprint = RouteQualityValidator.buildRouteFingerprint(
              result.coordinates,
              distanceKm: result.distanceKm,
            );
            final quality = validator.validateQuality(
              coordinates: result.coordinates,
              isRoundTrip: false,
              actualDistanceKm: result.distanceKm ?? 0.0,
            );
            overlapPercent = quality.overlapPercent;
            distanceOkay = quality.distanceInTolerance;
            final classification = validator.classifyGeneratedRoute(
              quality: quality,
              isRoundTrip: false,
              coordinateCount: result.coordinates.length,
              actualDistanceKm: result.distanceKm ?? 0.0,
            );
            tier =
                result.edgeMeta['quality_tier']?.toString() ??
                classification.tier.name;
            qualityReason = result.edgeMeta['quality_reason']?.toString();
            final searchSummary = result.edgeMeta['search_summary'];
            if (searchSummary is Map<String, dynamic>) {
              candidateAttempts =
                  (searchSummary['candidate_attempts'] as num?)?.toInt() ?? 0;
            }
            final excludes = result.edgeMeta['effective_excludes']?.toString();
            edgeRoutingBuildId = result.edgeMeta['routing_build_id']
                ?.toString();
            routeSource =
                result.edgeMeta['route_source']?.toString() ??
                result.edgeMeta['source']?.toString() ??
                'mapbox';
            poolFallbackUsed =
                RouteService.lastRoutePoolFallbackUsed || routeSource == 'pool';
            poolMatchId = result.edgeMeta['pool_match_id']?.toString();
            poolMatchTier = result.edgeMeta['pool_match_tier']?.toString();
            poolStartDistanceKm =
                (result.edgeMeta['pool_start_distance_km'] as num?)?.toDouble();
            poolDistanceRuleApplied =
                result.edgeMeta['pool_distance_rule_applied'] == true;
            poolRejectedTooFar =
                result.edgeMeta['pool_rejected_too_far'] == true;
            accessLegUsed = result.edgeMeta['access_leg_used'] == true;
            accessLegDistanceKm =
                (result.edgeMeta['access_leg_distance_km'] as num?)?.toDouble();
            deadEndSpikeDetected =
                result.edgeMeta['dead_end_spike_detected'] == true;
            if (routeSource == 'pool') {
              final hasHighway = result.edgeMeta['has_highway'] == true;
              final avoidsHighway = result.edgeMeta['avoids_highway'] == true;
              motorwayExcludeActive = scenario.avoidHighways
                  ? avoidsHighway && !hasHighway
                  : true;
            } else {
              motorwayExcludeActive = scenario.avoidHighways
                  ? (excludes?.contains('motorway') ?? false)
                  : !(excludes?.contains('motorway') ?? false);
            }
            styleEffective = scenario.detourLevel <= 0
                ? (result.edgeMeta['mode']?.toString() ?? '') == 'Standard'
                : (result.edgeMeta['mode']?.toString() ?? '') == scenario.mode;
          }
        } catch (error) {
          if (error is RouteServiceException) {
            errorCode = error.type.name;
            errorMessage = error.userMessage;
            edgeRoutingBuildId = error.edgeMeta['routing_build_id']?.toString();
          } else {
            errorCode = error.runtimeType.toString();
            errorMessage = error.toString();
          }
        }

        stopwatch.stop();
        final edgeRequests = invoker.takeCallCount();
        final requestBodies = invoker.takeRequestBodies();
        final requestVariantHints = requestBodies
            .map((body) => body['route_variant_hint']?.toString())
            .whereType<String>()
            .toList();
        final bucket = _bucketFor(
          tier: success ? tier : 'error',
          routeType: scenario.routeType,
          overlapPercent: overlapPercent,
        );

        final row = <String, dynamic>{
          'index': index + 1,
          'scenario': scenario.name,
          'endpoint': endpoint.toString(),
          'run': scenario.run,
          'routeType': scenario.routeType,
          'success': success,
          'source': routeSource,
          'routeSource': routeSource,
          'bucket': bucket,
          'tier': success ? tier : 'error',
          'edgeRequests': edgeRequests,
          'apiCallCount': RouteService.lastRouteApiCallCount,
          'requestVariantHints': requestVariantHints,
          'requestBodies': requestBodies,
          'candidateAttempts': candidateAttempts,
          'durationMs': stopwatch.elapsedMilliseconds,
          'distanceKm': distanceKm,
          'overlapPercent': overlapPercent,
          'formOkay': success && bucket != 'weak',
          'errorBanner': !success,
          'qualityReason': qualityReason,
          'errorCode': errorCode,
          'errorMessage': errorMessage,
          'avoidHighways': scenario.avoidHighways,
          'mode': scenario.mode,
          'detourLevel': scenario.detourLevel,
          'fingerprint': fingerprint,
          'similarityToPreviousPercent': similarityToPreviousPercent,
          'variantGroup': scenario.variantGroup,
          'distanceOkay': distanceOkay,
          'motorwayExcludeActive': motorwayExcludeActive,
          'edgeRoutingBuildId': edgeRoutingBuildId,
          'styleEffective': styleEffective,
          'geometryDifferent': geometryDifferent,
          'preparedBufferHit': RouteService.lastRoutePreparedBufferHit,
          'preparedBufferUsed': RouteService.lastRoutePreparedBufferUsed,
          'cacheHit': RouteService.lastRouteSessionCacheHit,
          'poolFallbackUsed': poolFallbackUsed,
          'poolRouteId': poolMatchId,
          'poolMatchTier': poolMatchTier,
          'poolStartDistanceKm': poolStartDistanceKm,
          'poolDistanceRuleApplied': poolDistanceRuleApplied,
          'poolRejectedTooFar': poolRejectedTooFar,
          'accessLegUsed': accessLegUsed,
          'accessLegDistanceKm': accessLegDistanceKm,
          'deadEndSpikeDetected': deadEndSpikeDetected,
          'recentFallbackUsed': RouteService.lastRouteRecentFallbackUsed,
          'cachedFallbackUsed':
              RouteService.lastRoutePersistentCacheFallbackUsed,
          'duplicateFallbackUsed': RouteService.lastRouteDuplicateFallbackUsed,
          'emergencyFallbackUsed': RouteService.lastRouteEmergencyFallbackUsed,
          'fallbackUsed':
              RouteService.lastRouteRecentFallbackUsed ||
              RouteService.lastRoutePersistentCacheFallbackUsed ||
              RouteService.lastRouteDuplicateFallbackUsed ||
              poolFallbackUsed,
        };
        results.add(row);

        // ignore: avoid_print
        print(
          '${row['index'].toString().padLeft(3, '0')}/${selectedScenarios.length} | '
          '${row['scenario']} | ${row['bucket']} | tier=${row['tier']} | '
          'source=${row['source']} | '
          'edgeReq=${row['edgeRequests']} | dur=${row['durationMs']}ms | '
          'dist=${row['distanceKm'] == null ? 'n/a' : (row['distanceKm'] as double).toStringAsFixed(1)}km | '
          'motorway=${row['motorwayExcludeActive']} | style=${row['styleEffective']}',
        );
      }

      final pointGroups = <String, List<Map<String, dynamic>>>{};
      for (final row in results.where(
        (row) => row['routeType'] == 'POINT_TO_POINT',
      )) {
        final key = row['variantGroup']?.toString();
        if (key == null) continue;
        pointGroups.putIfAbsent(key, () => []).add(row);
      }
      for (final rows in pointGroups.values) {
        final successRows = rows
            .where(
              (row) => row['success'] == true && row['fingerprint'] != null,
            )
            .toList();
        for (final row in rows) {
          final ownFingerprint = row['fingerprint']?.toString();
          row['geometryDifferent'] =
              ownFingerprint != null &&
              successRows.any(
                (other) =>
                    other != row &&
                    other['fingerprint']?.toString() != ownFingerprint,
              );
        }
      }

      final durations =
          results.map((entry) => entry['durationMs'] as int).toList()..sort();
      final summary = <String, dynamic>{
        'totalRuns': results.length,
        'usableRoutes': results.where((entry) {
          final bucket = entry['bucket'];
          return bucket == 'good' || bucket == 'acceptable';
        }).length,
        'weakRoutes': results
            .where((entry) => entry['bucket'] == 'weak')
            .length,
        'realErrors': results
            .where((entry) => entry['bucket'] == 'error')
            .length,
        'goodRoutes': results
            .where((entry) => entry['bucket'] == 'good')
            .length,
        'acceptableRoutes': results
            .where((entry) => entry['bucket'] == 'acceptable')
            .length,
        'averageDurationMs':
            results
                .map((entry) => entry['durationMs'] as int)
                .fold<int>(0, (sum, value) => sum + value) /
            results.length,
        'p95DurationMs':
            durations[(durations.length * 0.95).floor().clamp(
              0,
              durations.length - 1,
            )],
        'pointToPointDistinctRuns': results
            .where((entry) => entry['routeType'] == 'POINT_TO_POINT')
            .where((entry) => entry['geometryDifferent'] == true)
            .length,
        'mapboxRoutes': results
            .where((entry) => entry['source'] == 'mapbox')
            .length,
        'poolFallbackRoutes': results
            .where((entry) => entry['source'] == 'pool')
            .length,
        'cacheRoutes': results
            .where((entry) => entry['source'] == 'cache')
            .length,
      };
      final motorwayToggleCandidates = results
          .where((entry) => entry['motorwayExcludeActive'] != null)
          .toList();
      summary['motorwayToggleHonored'] = motorwayToggleCandidates.isEmpty
          ? null
          : motorwayToggleCandidates.every(
              (entry) => entry['motorwayExcludeActive'] == true,
            );
      final byScenario = <String, dynamic>{};
      for (final name
          in results.map((row) => row['scenario'] as String).toSet()) {
        byScenario[name] = _scenarioSummary(
          results.where((row) => row['scenario'] == name),
        );
      }

      final output = <String, dynamic>{
        'endpoint': endpoint.toString(),
        'summary': summary,
        'byScenario': byScenario,
        'results': results,
      };
      await File(
        outputPath,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(output));

      // ignore: avoid_print
      print(const JsonEncoder.withIndent('  ').convert(summary));
      expect(results, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
