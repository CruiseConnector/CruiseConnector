// ignore_for_file: depend_on_referenced_packages, invalid_use_of_visible_for_testing_member, prefer_const_declarations

import 'dart:convert';
import 'dart:io';

import 'package:functions_client/functions_client.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/route_quality_validator.dart';
import 'package:cruise_connect/data/services/route_service.dart';

class _LocalHttpInvoker implements RouteEdgeInvoker {
  _LocalHttpInvoker(this.endpoint);

  final Uri endpoint;
  int _callCount = 0;

  int takeCallCount() {
    final count = _callCount;
    _callCount = 0;
    return count;
  }

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    _callCount += 1;
    final client = HttpClient();
    try {
      final request = await client.postUrl(endpoint);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      // 2026-06-27 (vucko Rundkurs-Diagnose): Anon-Key für Live-Edge-Gateway.
      const anon = String.fromEnvironment('SB_ANON', defaultValue: '');
      if (anon.isNotEmpty) {
        request.headers.set('apikey', anon);
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $anon');
      }
      request.write(jsonEncode(body));
      final response = await request.close();
      final raw = await response.transform(utf8.decoder).join();
      final data = raw.isEmpty ? null : jsonDecode(raw);
      return FunctionResponse(data: data, status: response.statusCode);
    } finally {
      client.close(force: true);
    }
  }
}

class _Scenario {
  const _Scenario({
    required this.name,
    required this.routeType,
    required this.run,
    required this.targetDistanceKm,
    required this.start,
    this.destination,
    this.mode = 'Sport Mode',
    this.detourLevel = 0,
    this.avoidHighways = false,
  });

  final String name;
  final String routeType;
  final int run;
  final int targetDistanceKm;
  final geo.Position start;
  final geo.Position? destination;
  final String mode;
  final int detourLevel;
  final bool avoidHighways;
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

String? _argValue(List<String> args, String prefix) {
  for (final arg in args) {
    if (arg.startsWith(prefix)) {
      return arg.substring(prefix.length);
    }
  }
  return null;
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

List<_Scenario> _buildScenarios() {
  final dornbirn = _position(47.4125, 9.7414);
  final feldkirch = _position(47.2413, 9.5986);
  final bregenz = _position(47.5031, 9.7471);

  final scenarios = <_Scenario>[];
  for (var i = 0; i < 20; i++) {
    scenarios.add(
      _Scenario(
        name: 'RT Dornbirn 50 Sport',
        routeType: 'ROUND_TRIP',
        run: i + 1,
        targetDistanceKm: 50,
        start: dornbirn,
        mode: 'Sport Mode',
      ),
    );
  }
  for (var i = 0; i < 20; i++) {
    scenarios.add(
      _Scenario(
        name: 'RT Dornbirn 50 Kurvenjagd',
        routeType: 'ROUND_TRIP',
        run: i + 1,
        targetDistanceKm: 50,
        start: dornbirn,
        mode: 'Kurvenjagd',
      ),
    );
  }
  for (var i = 0; i < 15; i++) {
    scenarios.add(
      _Scenario(
        name: 'RT Feldkirch 50 Sport',
        routeType: 'ROUND_TRIP',
        run: i + 1,
        targetDistanceKm: 50,
        start: feldkirch,
        mode: 'Sport Mode',
      ),
    );
  }
  for (var i = 0; i < 15; i++) {
    scenarios.add(
      _Scenario(
        name: 'RT Bregenz 50 Sport',
        routeType: 'ROUND_TRIP',
        run: i + 1,
        targetDistanceKm: 50,
        start: bregenz,
        mode: 'Sport Mode',
      ),
    );
  }

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
              targetDistanceKm: 0,
              start: pair.$2,
              destination: pair.$3,
              mode: detour.$3,
              detourLevel: detour.$2,
              avoidHighways: avoidHighways,
            ),
          );
        }
      }
    }
  }

  return scenarios;
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

Future<void> main(List<String> args) async {
  final endpoint = Uri.parse(
    _argValue(args, '--endpoint=') ?? 'http://127.0.0.1:8000/',
  );
  final outputPath =
      _argValue(args, '--output=') ??
      '/tmp/route-service-benchmark-results.json';
  final smoke = args.contains('--smoke');
  final warm = args.contains('--warm');

  RouteService.disableBackgroundPreparation = !warm;
  final validator = const RouteQualityValidator();
  final scenarios = _buildScenarios();
  final selectedScenarios = smoke ? scenarios.take(8).toList() : scenarios;
  final results = <Map<String, dynamic>>[];
  SharedPreferences.setMockInitialValues({});
  RouteService.resetForTests();

  var activeScenarioName = '';
  _LocalHttpInvoker? sharedInvoker;
  RouteService? sharedService;

  for (var index = 0; index < selectedScenarios.length; index++) {
    final scenario = selectedScenarios[index];
    final reuseWarmState = warm && activeScenarioName == scenario.name;
    if (!reuseWarmState) {
      RouteService.resetForTests();
      sharedInvoker = _LocalHttpInvoker(endpoint);
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

    try {
      if (scenario.routeType == 'ROUND_TRIP') {
        final result = await service.generateRoundTrip(
          startPosition: scenario.start,
          targetDistanceKm: scenario.targetDistanceKm,
          mode: scenario.mode,
          planningType: 'Zufall',
          avoidHighways: scenario.avoidHighways,
        );
        success = true;
        distanceKm = result.distanceKm;
        final quality = validator.validateQuality(
          coordinates: result.coordinates,
          isRoundTrip: true,
          targetDistanceKm: scenario.targetDistanceKm.toDouble(),
          actualDistanceKm: result.distanceKm ?? 0,
        );
        overlapPercent = quality.overlapPercent;
        final classification = validator.classifyGeneratedRoute(
          quality: quality,
          isRoundTrip: true,
          coordinateCount: result.coordinates.length,
          actualDistanceKm: result.distanceKm ?? 0,
          targetDistanceKm: scenario.targetDistanceKm.toDouble(),
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
        final quality = validator.validateQuality(
          coordinates: result.coordinates,
          isRoundTrip: false,
          actualDistanceKm: result.distanceKm ?? 0,
        );
        overlapPercent = quality.overlapPercent;
        final classification = validator.classifyGeneratedRoute(
          quality: quality,
          isRoundTrip: false,
          coordinateCount: result.coordinates.length,
          actualDistanceKm: result.distanceKm ?? 0,
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
    };
    results.add(row);

    stdout.writeln(
      '${row['index'].toString().padLeft(3, '0')}/${selectedScenarios.length} | '
      '${row['scenario']} | ${row['bucket']} | tier=${row['tier']} | '
      'edgeReq=${row['edgeRequests']} | cand=${row['candidateAttempts']} | '
      '${row['durationMs']}ms | '
      'dist=${row['distanceKm'] == null ? 'n/a' : (row['distanceKm'] as double).toStringAsFixed(1)}km | '
      'overlap=${row['overlapPercent'] == null ? 'n/a' : (row['overlapPercent'] as double).toStringAsFixed(1)} | '
      'banner=${row['errorBanner'] ? 'yes' : 'no'}',
    );
  }

  final durations = results.map((entry) => entry['durationMs'] as int).toList()
    ..sort();
  final edgeRequestCounts =
      results.map((entry) => entry['edgeRequests'] as int).toList()..sort();
  final summary = <String, dynamic>{
    'totalRuns': results.length,
    'usableRoutes': results.where((entry) {
      final bucket = entry['bucket'];
      return bucket == 'good' || bucket == 'acceptable';
    }).length,
    'weakRoutes': results.where((entry) => entry['bucket'] == 'weak').length,
    'realErrors': results.where((entry) => entry['bucket'] == 'error').length,
    'goodRoutes': results.where((entry) => entry['bucket'] == 'good').length,
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
    'averageEdgeRequests':
        results
            .map((entry) => entry['edgeRequests'] as int)
            .fold<int>(0, (sum, value) => sum + value) /
        results.length,
    'p95EdgeRequests':
        edgeRequestCounts[(edgeRequestCounts.length * 0.95).floor().clamp(
          0,
          edgeRequestCounts.length - 1,
        )],
    'benchmarkMode': warm
        ? 'warm_prepared_route_flow'
        : 'cold_no_background_preparation',
  };

  final byScenario = <String, dynamic>{};
  final scenarioNames =
      results.map((entry) => entry['scenario'] as String).toSet()
        ..toList().sort();
  for (final scenarioName in scenarioNames) {
    byScenario[scenarioName] = _scenarioSummary(
      results.where((entry) => entry['scenario'] == scenarioName),
    );
  }

  final payload = <String, dynamic>{
    'generatedAt': DateTime.now().toIso8601String(),
    'endpoint': endpoint.toString(),
    'smoke': smoke,
    'warm': warm,
    'summary': summary,
    'byScenario': byScenario,
    'results': results,
  };

  File(
    outputPath,
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
  stdout.writeln('SUMMARY ${jsonEncode(summary)}');
  stdout.writeln('RESULT_FILE $outputPath');
}
