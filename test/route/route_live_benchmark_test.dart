import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:functions_client/functions_client.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/data/services/route_quality_validator.dart';
import 'package:cruise_connect/data/services/route_service.dart';

class _LiveHttpInvoker implements RouteEdgeInvoker {
  _LiveHttpInvoker(this.endpoint);

  final Uri endpoint;
  int _callCount = 0;
  bool _printedSampleBody = false;

  int takeCallCount() {
    final count = _callCount;
    _callCount = 0;
    return count;
  }

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    _callCount += 1;
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

List<_Scenario> _buildScenarios() {
  final dornbirn = _position(47.4125, 9.7414);
  final feldkirch = _position(47.2413, 9.5986);
  final bregenz = _position(47.5031, 9.7471);

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
    name: 'RT Dornbirn 50 Kurvenjagd',
    start: dornbirn,
    targetDistanceKm: 50,
    mode: 'Kurvenjagd',
    runs: 5,
  );
  addRoundTripScenario(
    name: 'RT Dornbirn 75 Sport',
    start: dornbirn,
    targetDistanceKm: 75,
    mode: 'Sport Mode',
    runs: 5,
  );
  addRoundTripScenario(
    name: 'RT Dornbirn 100 Sport',
    start: dornbirn,
    targetDistanceKm: 100,
    mode: 'Sport Mode',
    runs: 3,
  );
  addRoundTripScenario(
    name: 'RT Dornbirn 150 Sport',
    start: dornbirn,
    targetDistanceKm: 150,
    mode: 'Sport Mode',
    runs: 3,
  );
  addRoundTripScenario(
    name: 'RT Feldkirch 50 Sport',
    start: feldkirch,
    targetDistanceKm: 50,
    mode: 'Sport Mode',
    runs: 5,
  );
  addRoundTripScenario(
    name: 'RT Bregenz 50 Sport',
    start: bregenz,
    targetDistanceKm: 50,
    mode: 'Sport Mode',
    runs: 5,
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

  test(
    'live routing benchmark matrix',
    skip: !runBenchmark,
    () async {
      RouteService.disableBackgroundPreparation = !warm;
      SharedPreferences.setMockInitialValues({});
      RouteService.resetForTests();
      final endpoint = Uri.parse(endpointValue);
      final validator = const RouteQualityValidator();
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
          sharedService = RouteService(invoker: sharedInvoker);
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
        bool? styleEffective;
        bool? geometryDifferent = scenario.routeType == 'ROUND_TRIP'
            ? true
            : false;

        try {
          if (scenario.routeType == 'ROUND_TRIP') {
            final result = await service.generateRoundTrip(
              startPosition: scenario.start,
              targetDistanceKm: scenario.targetDistanceKm!,
              mode: scenario.mode,
              planningType: 'Zufall',
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
            motorwayExcludeActive = scenario.avoidHighways
                ? (excludes?.contains('motorway') ?? false) ||
                      (excludes?.contains('motorway_link') ?? false)
                : !(excludes?.contains('motorway') ?? false) &&
                      !(excludes?.contains('motorway_link') ?? false);
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
            motorwayExcludeActive = scenario.avoidHighways
                ? (excludes?.contains('motorway') ?? false) ||
                      (excludes?.contains('motorway_link') ?? false)
                : !(excludes?.contains('motorway') ?? false) &&
                      !(excludes?.contains('motorway_link') ?? false);
            styleEffective = scenario.detourLevel <= 0
                ? (result.edgeMeta['mode']?.toString() ?? '') == 'Standard'
                : (result.edgeMeta['mode']?.toString() ?? '') == scenario.mode;
          }
        } catch (error) {
          if (error is RouteServiceException) {
            errorCode = error.type.name;
            errorMessage = error.userMessage;
          } else {
            errorCode = error.runtimeType.toString();
            errorMessage = error.toString();
          }
        }

        stopwatch.stop();
        final edgeRequests = invoker.takeCallCount();
        final bucket = _bucketFor(
          tier: success ? tier : 'error',
          routeType: scenario.routeType,
          overlapPercent: overlapPercent,
        );

        final row = <String, dynamic>{
          'index': index + 1,
          'scenario': scenario.name,
          'run': scenario.run,
          'routeType': scenario.routeType,
          'success': success,
          'bucket': bucket,
          'tier': success ? tier : 'error',
          'edgeRequests': edgeRequests,
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
          'styleEffective': styleEffective,
          'geometryDifferent': geometryDifferent,
        };
        results.add(row);

        // ignore: avoid_print
        print(
          '${row['index'].toString().padLeft(3, '0')}/${selectedScenarios.length} | '
          '${row['scenario']} | ${row['bucket']} | tier=${row['tier']} | '
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
