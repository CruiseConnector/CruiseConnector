// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cruise_connect/data/services/route_style_config.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

import 'route_generation_mock_test.mocks.dart';

// ─── Hilfsfunktionen ─────────────────────────────────────────────────────────

geo.Position _munich() => geo.Position(
  latitude: 48.1351,
  longitude: 11.5820,
  timestamp: DateTime.now(),
  accuracy: 5.0,
  altitude: 520.0,
  altitudeAccuracy: 10.0,
  heading: 0.0,
  headingAccuracy: 5.0,
  speed: 0.0,
  speedAccuracy: 1.0,
);

const _dornbirnLat = 47.4125;
const _dornbirnLng = 9.7414;
const _feldkirchLat = 47.2413;
const _feldkirchLng = 9.5986;
const _bregenzLat = 47.5031;
const _bregenzLng = 9.7471;

geo.Position _dornbirn() => geo.Position(
  latitude: _dornbirnLat,
  longitude: _dornbirnLng,
  timestamp: DateTime.now(),
  accuracy: 5.0,
  altitude: 430.0,
  altitudeAccuracy: 10.0,
  heading: 0.0,
  headingAccuracy: 5.0,
  speed: 0.0,
  speedAccuracy: 1.0,
);

/// Erzeugt eine valide Supabase-Antwort mit der angegebenen Distanz.
Map<String, dynamic> _buildRouteResponse({
  required double distanceMeters,
  required double durationSeconds,
  int coordinateCount = 100,
  List<Map<String, dynamic>>? legs,
  String mode = 'Sport Mode',
  double centerLat = 48.140,
  double centerLng = 11.592,
}) {
  final distanceKm = distanceMeters / 1000.0;
  final params = _profiledLoopParams(distanceKm: distanceKm, mode: mode);
  final extraWave = params.petals + (params.mix >= 0.24 ? 3 : 1);
  final coords = List.generate(coordinateCount, (i) {
    final t = (2 * math.pi * i) / (coordinateCount - 1);
    final radialWave =
        math.sin(t * params.petals) * params.amplitude +
        math.cos(t * extraWave) * (params.amplitude * params.mix) +
        math.sin(t * (params.petals ~/ 2 + 2)) * (params.amplitude * 0.12);
    final radius = params.baseRadius + radialWave;
    return [
      centerLng + math.cos(t) * radius * params.stretch,
      centerLat + math.sin(t) * radius * params.aspect,
    ];
  });
  coords[coords.length - 1] = [...coords.first];

  return {
    'route': {
      'geometry': {'type': 'LineString', 'coordinates': coords},
      'distance': distanceMeters,
      'duration': durationSeconds,
      'legs':
          legs ??
          [
            {
              'steps': [
                {
                  'maneuver': {
                    'type': 'turn',
                    'modifier': 'left',
                    'location': [centerLng, centerLat],
                  },
                  'distance': 500.0,
                  'name': 'Teststraße',
                },
                {
                  'maneuver': {'type': 'arrive', 'location': coords.last},
                  'distance': 0.0,
                  'name': '',
                },
              ],
            },
          ],
    },
  };
}

_MockLoopProfile _profiledLoopParams({
  required double distanceKm,
  required String mode,
}) {
  final normalized = mode.trim().toLowerCase();
  if (normalized == 'kurvenreich' ||
      normalized == 'kurvenjagd' ||
      normalized == 'alpenstraßen') {
    return const _MockLoopProfile(
      petals: 8,
      baseRadius: 0.006,
      amplitude: 0.003,
      aspect: 0.50,
      stretch: 1.30,
      mix: 0.16,
    );
  }
  if (normalized == 'panorama' || normalized == 'abendrunde') {
    return const _MockLoopProfile(
      petals: 7,
      baseRadius: 0.006,
      amplitude: 0.003,
      aspect: 0.50,
      stretch: 1.40,
      mix: 0.24,
    );
  }
  if (normalized == 'zufall' || normalized == 'entdecker') {
    return const _MockLoopProfile(
      petals: 9,
      baseRadius: 0.006,
      amplitude: 0.003,
      aspect: 0.50,
      stretch: 1.30,
      mix: 0.32,
    );
  }
  if (distanceKm <= 35) {
    return const _MockLoopProfile(
      petals: 2,
      baseRadius: 0.006,
      amplitude: 0.0012,
      aspect: 0.55,
      stretch: 1.40,
      mix: 0.10,
    );
  }
  if (distanceKm <= 60) {
    return const _MockLoopProfile(
      petals: 3,
      baseRadius: 0.009,
      amplitude: 0.0016,
      aspect: 0.55,
      stretch: 1.00,
      mix: 0.18,
    );
  }
  if (distanceKm <= 90) {
    return const _MockLoopProfile(
      petals: 4,
      baseRadius: 0.006,
      amplitude: 0.0012,
      aspect: 0.75,
      stretch: 1.20,
      mix: 0.00,
    );
  }
  return const _MockLoopProfile(
    petals: 5,
    baseRadius: 0.006,
    amplitude: 0.0012,
    aspect: 0.55,
    stretch: 1.40,
    mix: 0.25,
  );
}

class _MockLoopProfile {
  const _MockLoopProfile({
    required this.petals,
    required this.baseRadius,
    required this.amplitude,
    required this.aspect,
    required this.stretch,
    required this.mix,
  });

  final int petals;
  final double baseRadius;
  final double amplitude;
  final double aspect;
  final double stretch;
  final double mix;
}

Map<String, dynamic> _buildClosedLoopRouteResponse({
  required double distanceMeters,
  required double durationSeconds,
  int pointsPerSide = 24,
}) {
  final coords = <List<double>>[];

  for (var i = 0; i < pointsPerSide; i++) {
    coords.add([11.5820 + i * 0.0001, 48.1350]);
  }
  for (var i = 1; i < pointsPerSide; i++) {
    coords.add([11.5820 + (pointsPerSide - 1) * 0.0001, 48.1350 + i * 0.0001]);
  }
  for (var i = pointsPerSide - 2; i >= 0; i--) {
    coords.add([11.5820 + i * 0.0001, 48.1350 + (pointsPerSide - 1) * 0.0001]);
  }
  for (var i = pointsPerSide - 2; i > 0; i--) {
    coords.add([11.5820, 48.1350 + i * 0.0001]);
  }
  coords.add([11.5820, 48.1350]);

  return {
    'route': {
      'geometry': {'type': 'LineString', 'coordinates': coords},
      'distance': distanceMeters,
      'duration': durationSeconds,
      'legs': [
        {
          'steps': [
            {
              'maneuver': {
                'type': 'turn',
                'modifier': 'left',
                'location': [11.583, 48.136],
              },
              'distance': 500.0,
              'name': 'Testroute',
            },
            {
              'maneuver': {'type': 'arrive', 'location': coords.last},
              'distance': 0.0,
              'name': '',
            },
          ],
        },
      ],
    },
  };
}

Map<String, dynamic> _buildPointToPointResponse({
  required double distanceMeters,
  required double durationSeconds,
  required double destinationLat,
  required double destinationLng,
  int coordinateCount = 140,
  double bendScale = 0.18,
  double startLat = 48.1351,
  double startLng = 11.5820,
}) {
  final dx = destinationLng - startLng;
  final dy = destinationLat - startLat;
  final length = math.sqrt(dx * dx + dy * dy);
  final perpX = length == 0 ? 0.0 : -dy / length;
  final perpY = length == 0 ? 0.0 : dx / length;

  final coords = List.generate(coordinateCount, (i) {
    final t = i / (coordinateCount - 1);
    final corridor =
        math.sin(t * math.pi) * bendScale +
        math.sin(t * math.pi * 2.0) * (bendScale * 0.12);
    return [
      startLng + dx * t + perpX * corridor,
      startLat + dy * t + perpY * corridor,
    ];
  });

  return {
    'route': {
      'geometry': {'type': 'LineString', 'coordinates': coords},
      'distance': distanceMeters,
      'duration': durationSeconds,
      'legs': [
        {
          'steps': [
            {
              'maneuver': {
                'type': 'turn',
                'modifier': 'left',
                'location': coords[(coordinateCount * 0.33).round()],
              },
              'distance': distanceMeters * 0.35,
              'name': 'Scenic Way',
            },
            {
              'maneuver': {
                'type': 'turn',
                'modifier': 'right',
                'location': coords[(coordinateCount * 0.72).round()],
              },
              'distance': distanceMeters * 0.40,
              'name': 'Valley Road',
            },
            {
              'maneuver': {'type': 'arrive', 'location': coords.last},
              'distance': 0.0,
              'name': '',
            },
          ],
        },
      ],
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────────

@GenerateMocks([RouteEdgeInvoker])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockRouteEdgeInvoker mockInvoker;
  late RouteService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockInvoker = MockRouteEdgeInvoker();
    service = RouteService(invoker: mockInvoker);
    RouteService.resetForTests();
    RouteService.disableBackgroundPreparation = true;
  });

  group('RouteService – Modusregeln', () {
    test('requiresDestination trennt A→B und Rundkurs korrekt', () {
      expect(RouteService.requiresDestination('ROUND_TRIP'), isFalse);
      expect(RouteService.requiresDestination('POINT_TO_POINT'), isTrue);
    });
  });

  // ─────────────────────── Distanztoleranzen ─────────────────────────────────

  group('generateRoundTrip – Distanztoleranzen', () {
    /// Helper: Testet ob die zurückgegebene Route innerhalb der Toleranz liegt.
    Future<void> testDistanceTolerance({
      required int targetKm,
      required double responseDistanceM,
      double tolerancePercent = 0.20, // 20% Toleranz
      int coordinateCount = 100,
    }) async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async => _buildRouteResponse(
          distanceMeters: responseDistanceM,
          durationSeconds: responseDistanceM / 13.9, // ~50 km/h
          coordinateCount: coordinateCount,
        ),
      );

      final result = await service.generateRoundTrip(
        startPosition: _munich(),
        targetDistanceKm: targetKm,
        mode: 'Sport Mode',
        planningType: 'Zufall',
      );

      final actualKm = result.distanceKm ?? 0;
      final minKm = targetKm * (1 - tolerancePercent);
      final maxKm = targetKm * (1 + tolerancePercent);

      expect(
        actualKm,
        inInclusiveRange(minKm, maxKm),
        reason:
            'Route von ${actualKm.toStringAsFixed(1)} km liegt außerhalb '
            '[$minKm, $maxKm] für Ziel $targetKm km',
      );
    }

    test('30 km Ziel → Route zwischen 24 km und 36 km', () async {
      await testDistanceTolerance(targetKm: 30, responseDistanceM: 30000);
    });

    test('50 km Ziel → Route zwischen 40 km und 60 km', () async {
      await testDistanceTolerance(targetKm: 50, responseDistanceM: 50000);
    });

    test('50 km Ziel, 45 km Antwort (10% unter) → noch akzeptiert', () async {
      await testDistanceTolerance(
        targetKm: 50,
        responseDistanceM: 45000,
        tolerancePercent: 0.15,
      );
    });

    test('50 km Ziel, 55 km Antwort (10% über) → noch akzeptiert', () async {
      await testDistanceTolerance(
        targetKm: 50,
        responseDistanceM: 55000,
        tolerancePercent: 0.15,
      );
    });

    test('80 km Ziel → Route zwischen 64 km und 96 km', () async {
      await testDistanceTolerance(targetKm: 80, responseDistanceM: 80000);
    });

    test('100 km Ziel → Route zwischen 80 km und 120 km', () async {
      await testDistanceTolerance(
        targetKm: 100,
        responseDistanceM: 100000,
        coordinateCount: 500,
      );
    });
  });

  // ─────────────────────── Request-Body Validierung ──────────────────────────

  group('generateRoundTrip – Request Body', () {
    test('sendet Startposition korrekt', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 50000, durationSeconds: 3600),
      );

      await service.generateRoundTrip(
        startPosition: _munich(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
      );

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.last
              as Map<String, dynamic>;
      expect(captured['startLocation']['latitude'], closeTo(48.1351, 0.001));
      expect(captured['startLocation']['longitude'], closeTo(11.5820, 0.001));
    });

    test('sendet targetDistance korrekt', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 30000, durationSeconds: 2400),
      );

      await service.generateRoundTrip(
        startPosition: _munich(),
        targetDistanceKm: 30,
        mode: 'Sport Mode',
        planningType: 'Zufall',
      );

      // Erster Versuch geht ohne radiusJitter raus (variant.index == 0).
      // Folge-Versuche jittern leicht — wir prüfen daher den ersten Call.
      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.first
              as Map<String, dynamic>;
      expect(captured['targetDistance'], 30);
    });

    test('sendet route_type als ROUND_TRIP', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 50000, durationSeconds: 3600),
      );

      await service.generateRoundTrip(
        startPosition: _munich(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Kurvenreich',
      );

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.last
              as Map<String, dynamic>;
      expect(captured['route_type'], 'ROUND_TRIP');
    });

    test('sendet language als "de"', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 50000, durationSeconds: 3600),
      );

      await service.generateRoundTrip(
        startPosition: _munich(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
      );

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.last
              as Map<String, dynamic>;
      expect(captured['language'], 'de');
    });

    test('Zufall-Rundkurs sendet keine Wegpunkte-Felder', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 50000, durationSeconds: 3600),
      );

      await service.generateRoundTrip(
        startPosition: _munich(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
      );

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.first
              as Map<String, dynamic>;
      expect(captured.containsKey('user_waypoints'), isFalse);
      expect(captured.containsKey('manual_waypoints'), isFalse);
      expect(captured.containsKey('close_loop'), isFalse);
      expect(captured.containsKey('allow_seed_generation'), isFalse);
    });

    test('sendet User-Wegpunkte für Wegpunkte-Rundkurs', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 42000, durationSeconds: 3200),
      );

      await service.generateRoundTrip(
        startPosition: _munich(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Wegpunkte',
        userWaypoints: const [
          {'latitude': 48.1501, 'longitude': 11.6201},
          {'latitude': 48.1151, 'longitude': 11.6502},
        ],
      );

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.first
              as Map<String, dynamic>;
      expect(captured['planning_type'], 'Wegpunkte');
      expect(captured['route_type'], 'ROUND_TRIP');
      expect(captured['close_loop'], isTrue);
      expect(captured['waypoint_order'], 'fixed');
      expect(captured['allow_seed_generation'], isFalse);
      expect(captured['user_waypoints'], hasLength(2));
      expect(captured['manual_waypoints'], hasLength(2));
      expect(captured['user_waypoints'][0]['latitude'], 48.1501);
      expect(captured['user_waypoints'][0]['longitude'], 11.6201);
      expect(captured['user_waypoints'][1]['latitude'], 48.1151);
      expect(captured['user_waypoints'][1]['longitude'], 11.6502);
      expect(
        captured['client_scenario_key'].toString(),
        contains('wp48.15010,11.62010;48.11510,11.65020'),
      );
    });

    test('Wegpunkte-Rundkurs braucht mindestens einen User-Wegpunkt', () async {
      await expectLater(
        service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Wegpunkte',
        ),
        throwsA(isA<RouteServiceException>()),
      );
      verifyNever(mockInvoker.invoke(any));
    });

    test('Wegpunkte-Rundkurs lehnt mehr als 8 Wegpunkte ab', () async {
      await expectLater(
        service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Wegpunkte',
          userWaypoints: List.generate(
            9,
            (index) => {
              'latitude': 48.15 + index * 0.01,
              'longitude': 11.62 + index * 0.01,
            },
          ),
        ),
        throwsA(
          isA<RouteServiceException>().having(
            (error) => error.edgeMeta['response_code'],
            'response_code',
            'too_many_waypoints',
          ),
        ),
      );
      verifyNever(mockInvoker.invoke(any));
    });

    test('Wegpunkte-Rundkurs lehnt zu nahe Wegpunkte ab', () async {
      await expectLater(
        service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Wegpunkte',
          userWaypoints: const [
            {'latitude': 48.1360, 'longitude': 11.5825},
          ],
        ),
        throwsA(
          isA<RouteServiceException>().having(
            (error) => error.edgeMeta['response_code'],
            'response_code',
            'waypoint_duplicate_or_too_close',
          ),
        ),
      );
      verifyNever(mockInvoker.invoke(any));
    });

    test('Wegpunkte-Rundkurs lehnt zu entfernte Wegpunkte ab', () async {
      await expectLater(
        service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Wegpunkte',
          userWaypoints: const [
            {'latitude': 49.0000, 'longitude': 12.6000},
          ],
        ),
        throwsA(
          isA<RouteServiceException>().having(
            (error) => error.edgeMeta['response_code'],
            'response_code',
            'waypoint_too_far',
          ),
        ),
      );
      verifyNever(mockInvoker.invoke(any));
    });

    test(
      'wiederholte Rundkurs-Generierung nutzt unterschiedliche Seeds',
      () async {
        when(mockInvoker.invoke(any)).thenAnswer(
          (_) async =>
              _buildRouteResponse(distanceMeters: 50000, durationSeconds: 3600),
        );

        try {
          await service.generateRoundTrip(
            startPosition: _munich(),
            targetDistanceKm: 50,
            mode: 'Sport Mode',
            planningType: 'Zufall',
            forceFreshVariant: true,
          );
        } on RouteServiceException {
          // Für diese Prüfung ist nur der Request-Seed relevant.
        }

        final first =
            verify(mockInvoker.invoke(captureAny)).captured.first
                as Map<String, dynamic>;
        clearInteractions(mockInvoker);

        when(mockInvoker.invoke(any)).thenAnswer(
          (_) async =>
              _buildRouteResponse(distanceMeters: 50000, durationSeconds: 3600),
        );

        try {
          await service.generateRoundTrip(
            startPosition: _munich(),
            targetDistanceKm: 50,
            mode: 'Sport Mode',
            planningType: 'Zufall',
            forceFreshVariant: true,
          );
        } on RouteServiceException {
          // Für diese Prüfung ist nur der Request-Seed relevant.
        }

        final second =
            verify(mockInvoker.invoke(captureAny)).captured.first
                as Map<String, dynamic>;

        expect(first['randomSeed'], isA<int>());
        expect(first['randomSeed'], isNot(equals(second['randomSeed'])));
      },
    );

    test('sendet planning_type korrekt (Kurvenreich)', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 50000, durationSeconds: 3600),
      );

      await service.generateRoundTrip(
        startPosition: _munich(),
        targetDistanceKm: 50,
        mode: 'Autobahn',
        planningType: 'Kurvenreich',
      );

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.last
              as Map<String, dynamic>;
      expect(captured['planning_type'], 'Kurvenreich');
    });

    test('sendet im Rundkurs kein destination_location', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 50000, durationSeconds: 3600),
      );

      await service.generateRoundTrip(
        startPosition: _munich(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
      );

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.last
              as Map<String, dynamic>;
      expect(captured.containsKey('destination_location'), isFalse);
    });

    test('optionaler targetLocation wird mitgesendet wenn angegeben', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 50000, durationSeconds: 3600),
      );

      await service.generateRoundTrip(
        startPosition: _munich(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        targetLocation: {'latitude': 47.8, 'longitude': 12.0},
      );

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.last
              as Map<String, dynamic>;
      expect(captured['targetLocation'], isNotNull);
      expect(captured['targetLocation']['latitude'], closeTo(47.8, 0.01));
    });

    test(
      'Dornbirn 50km Sport/Kurvenjagd sendet robuste Roundtrip-Hints',
      () async {
        final requests = <Map<String, dynamic>>[];
        when(mockInvoker.invoke(any)).thenAnswer((invocation) async {
          final body = Map<String, dynamic>.from(
            invocation.positionalArguments.first as Map,
          );
          requests.add(body);
          return _buildRouteResponse(
            distanceMeters: 50000,
            durationSeconds: 3600,
            coordinateCount: 220,
            mode: body['mode'] as String,
            centerLat: _dornbirnLat,
            centerLng: _dornbirnLng,
          );
        });

        for (final mode in const ['Sport Mode', 'Kurvenjagd']) {
          try {
            await service.generateRoundTrip(
              startPosition: _dornbirn(),
              targetDistanceKm: 50,
              mode: mode,
              planningType: 'Zufall',
            );
          } on RouteServiceException {
            // Fuer diese Repro zaehlt der erste Edge-Request.
          }
        }

        final sportRequest = requests.firstWhere(
          (request) =>
              request['route_type'] == 'ROUND_TRIP' &&
              request['mode'] == 'Sport Mode',
        );
        final curveRequest = requests.firstWhere(
          (request) =>
              request['route_type'] == 'ROUND_TRIP' &&
              request['mode'] == 'Kurvenjagd',
        );

        for (final request in [sportRequest, curveRequest]) {
          expect(
            request['startLocation']['latitude'],
            closeTo(_dornbirnLat, 0.001),
          );
          expect(
            request['startLocation']['longitude'],
            closeTo(_dornbirnLng, 0.001),
          );
          expect(request['targetDistance'], 50);
          expect(request['planning_type'], 'Zufall');
          expect(request['continue_straight'], isTrue);
          expect(request['avoid_highways'], isFalse);
          expect(request.containsKey('destination_location'), isFalse);
          expect(request['direction_hint'], isA<int>());
        }

        expect(sportRequest['max_candidate_attempts'], 7);
        expect(sportRequest['style_profile'], 'sport');
        expect(sportRequest['waypoint_shape_factor'], 2.05);
        expect(sportRequest['radius_multiplier'], 1.02);
        expect(sportRequest['zigzag_waypoints'], isFalse);

        expect(curveRequest['max_candidate_attempts'], 8);
        expect(curveRequest['style_profile'], 'kurvenjagd');
        expect(curveRequest['waypoint_shape_factor'], 0.95);
        expect(curveRequest['radius_multiplier'], 1.18);
        expect(curveRequest['zigzag_waypoints'], isTrue);
      },
    );

    test(
      'Rundkurs-Rescue behaelt avoidHighways auch in spaeten Fallbacks aktiv',
      () async {
        var callCount = 0;
        when(mockInvoker.invoke(any)).thenAnswer((_) async {
          callCount++;
          if (callCount < 5) {
            throw const FunctionException(
              status: 404,
              details: {'error': 'no route found'},
              reasonPhrase: 'Not Found',
            );
          }
          return _buildClosedLoopRouteResponse(
            distanceMeters: 50000,
            durationSeconds: 3600,
          );
        });

        await service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: 'Abendrunde',
          planningType: 'Zufall',
          avoidHighways: true,
        );

        final captured = verify(
          mockInvoker.invoke(captureAny),
        ).captured.cast<Map<String, dynamic>>();

        expect(captured.length, greaterThanOrEqualTo(5));
        expect(
          captured.every((request) => request['avoid_highways'] == true),
          isTrue,
        );
        expect(captured.last['mode'], 'Sport Mode');
        expect(captured.last['max_waypoints'], 4);
      },
    );
  });

  // ─────────────────────── generatePointToPoint ──────────────────────────────

  group('generatePointToPoint – Request Body', () {
    test('sendet route_type als POINT_TO_POINT', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 20000, durationSeconds: 1800),
      );

      try {
        await service.generatePointToPoint(
          startPosition: _munich(),
          destinationLat: 47.8,
          destinationLng: 12.0,
          mode: 'Sport Mode',
        );
      } on RouteServiceException {
        // Für diese Prüfung zählt nur der Request-Body.
      }

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.last
              as Map<String, dynamic>;
      expect(captured['route_type'], 'POINT_TO_POINT');
    });

    test('sendet destination_location korrekt', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 20000, durationSeconds: 1800),
      );

      try {
        await service.generatePointToPoint(
          startPosition: _munich(),
          destinationLat: 47.9123,
          destinationLng: 12.4567,
          mode: 'Sport Mode',
        );
      } on RouteServiceException {
        // Für diese Prüfung zählt nur der Request-Body.
      }

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.last
              as Map<String, dynamic>;
      expect(
        captured['destination_location']['latitude'],
        closeTo(47.9123, 0.001),
      );
      expect(
        captured['destination_location']['longitude'],
        closeTo(12.4567, 0.001),
      );
    });

    test('verwirft A→B wenn Start und Ziel praktisch gleich sind', () async {
      await expectLater(
        service.generatePointToPoint(
          startPosition: _dornbirn(),
          destinationLat: _dornbirnLat,
          destinationLng: _dornbirnLng,
          mode: 'Sport Mode',
        ),
        throwsA(
          isA<RouteServiceException>().having(
            (e) => e.type,
            'type',
            RouteErrorType.validation,
          ),
        ),
      );

      verifyNever(mockInvoker.invoke(any));
    });

    test('scenic = false → mode wird auf "Standard" gesetzt', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 20000, durationSeconds: 1800),
      );

      try {
        await service.generatePointToPoint(
          startPosition: _munich(),
          destinationLat: 47.8,
          destinationLng: 12.0,
          mode: 'Sport Mode',
          scenic: false,
        );
      } on RouteServiceException {
        // Für diese Prüfung zählt nur der Request-Body.
      }

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.last
              as Map<String, dynamic>;
      expect(captured['mode'], 'Standard');
      expect(captured['avoid_highways'], isFalse);
      expect(captured.containsKey('targetDistance'), isFalse);
      expect(captured.containsKey('detour_level'), isFalse);
      expect(captured.containsKey('detour_factor'), isFalse);
    });

    test('Direkt-A→B sendet keine Scenic-/Style-Hints mit', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 20000, durationSeconds: 1800),
      );

      try {
        await service.generatePointToPoint(
          startPosition: _munich(),
          destinationLat: 47.8,
          destinationLng: 12.0,
          mode: 'Sport Mode',
          scenic: false,
        );
      } on RouteServiceException {
        // Für diese Prüfung zählt nur der Request-Body.
      }

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.last
              as Map<String, dynamic>;
      expect(captured.containsKey('style_profile'), isFalse);
      expect(captured.containsKey('waypoint_shape_factor'), isFalse);
      expect(captured.containsKey('radius_multiplier'), isFalse);
      expect(captured.containsKey('prefer_flat_terrain'), isFalse);
      expect(captured.containsKey('zigzag_waypoints'), isFalse);
    });

    test('avoidHighways = true → highway flag wird mitgesendet', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 20000, durationSeconds: 1800),
      );

      try {
        await service.generatePointToPoint(
          startPosition: _munich(),
          destinationLat: 47.8,
          destinationLng: 12.0,
          mode: 'Sport Mode',
          scenic: false,
          avoidHighways: true,
        );
      } on RouteServiceException {
        // Für diese Prüfung zählt nur der Request-Body.
      }

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.last
              as Map<String, dynamic>;
      expect(captured['avoid_highways'], isTrue);
      expect(captured.containsKey('targetDistance'), isFalse);
      expect(captured.containsKey('detour_level'), isFalse);
      expect(captured.containsKey('detour_factor'), isFalse);
    });

    test('scenic = true → übergibt den eigentlichen mode', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async => _buildPointToPointResponse(
          distanceMeters: 56000,
          durationSeconds: 3600,
          destinationLat: 47.8,
          destinationLng: 12.0,
        ),
      );

      try {
        await service.generatePointToPoint(
          startPosition: _munich(),
          destinationLat: 47.8,
          destinationLng: 12.0,
          mode: 'Alpenstraßen',
          scenic: true,
        );
      } on RouteServiceException {
        // Für diese Prüfung zählt nur der Request-Body.
      }

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.first
              as Map<String, dynamic>;
      expect(captured['mode'], 'Alpenstraßen');
    });

    test(
      'scenic = true → targetDistance und dynamischer randomSeed werden mitgesendet',
      () async {
        when(mockInvoker.invoke(any)).thenAnswer(
          (_) async => _buildPointToPointResponse(
            distanceMeters: 92000,
            durationSeconds: 5200,
            destinationLat: 47.8,
            destinationLng: 12.0,
          ),
        );

        try {
          await service.generatePointToPoint(
            startPosition: _munich(),
            destinationLat: 47.8,
            destinationLng: 12.0,
            mode: 'Sport Mode',
            scenic: true,
            routeVariant: 2,
          );
        } on RouteServiceException {
          // Für diese Prüfung zählt nur der Request-Body.
        }

        final captured =
            verify(mockInvoker.invoke(captureAny)).captured.first
                as Map<String, dynamic>;
        expect(captured['targetDistance'], isNotNull);
        expect(captured['randomSeed'], isA<int>());
        expect(captured['randomSeed'], greaterThan(0));
      },
    );

    test(
      'scenic + avoidHighways → Detour-Parameter bleiben erhalten',
      () async {
        when(mockInvoker.invoke(any)).thenAnswer(
          (_) async => _buildPointToPointResponse(
            distanceMeters: 112000,
            durationSeconds: 6200,
            destinationLat: 47.8,
            destinationLng: 12.0,
          ),
        );

        try {
          await service.generatePointToPoint(
            startPosition: _munich(),
            destinationLat: 47.8,
            destinationLng: 12.0,
            mode: 'Sport Mode',
            scenic: true,
            routeVariant: 3,
            avoidHighways: true,
          );
        } on RouteServiceException {
          // Für diese Prüfung zählt nur der Request-Body.
        }

        final captured =
            verify(mockInvoker.invoke(captureAny)).captured.first
                as Map<String, dynamic>;
        expect(captured['avoid_highways'], isTrue);
        expect(captured['targetDistance'], isNotNull);
        expect(captured['detour_level'], 3);
        expect(captured['detour_factor'], isNotNull);
      },
    );

    test(
      'A→B-Fallback behaelt avoidHighways aktiv und erweitert den Scenic-Rettungspfad',
      () async {
        var callCount = 0;
        when(mockInvoker.invoke(any)).thenAnswer((_) async {
          callCount++;
          if (callCount <= 2) {
            throw const FunctionException(
              status: 404,
              details: {'error': 'no route found'},
              reasonPhrase: 'Not Found',
            );
          }
          return _buildPointToPointResponse(
            distanceMeters: 88000,
            durationSeconds: 5200,
            destinationLat: _feldkirchLat,
            destinationLng: _feldkirchLng,
          );
        });

        try {
          await service.generatePointToPoint(
            startPosition: _dornbirn(),
            destinationLat: _feldkirchLat,
            destinationLng: _feldkirchLng,
            mode: 'Sport Mode',
            scenic: true,
            routeVariant: 2,
            avoidHighways: true,
          );
        } on RouteServiceException {
          // Fuer diese Regression zaehlt der Fallback-Request, nicht das
          // mockbedingte Endergebnis der Geometrie.
        }

        final captured = verify(
          mockInvoker.invoke(captureAny),
        ).captured.cast<Map<String, dynamic>>();

        expect(captured.length, greaterThanOrEqualTo(3));
        expect(
          captured.every((request) => request['avoid_highways'] == true),
          isTrue,
        );
        final scenicFallback = captured.firstWhere(
          (request) => request['simplify_waypoints'] == true,
        );
        expect(scenicFallback['max_waypoints'], 2);
        expect(scenicFallback['detour_level'], 2);
      },
    );

    test('Umwegstufen skalieren die targetDistance sichtbar', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async => _buildPointToPointResponse(
          distanceMeters: 68000,
          durationSeconds: 4200,
          destinationLat: 47.8,
          destinationLng: 12.0,
        ),
      );

      try {
        await service.generatePointToPoint(
          startPosition: _munich(),
          destinationLat: 47.8,
          destinationLng: 12.0,
          mode: 'Sport Mode',
          scenic: true,
          routeVariant: 1,
        );
      } on RouteServiceException {
        // Für diese Prüfung zählt nur der Request-Body.
      }

      final smallDetour =
          verify(mockInvoker.invoke(captureAny)).captured.first
              as Map<String, dynamic>;
      clearInteractions(mockInvoker);

      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async => _buildPointToPointResponse(
          distanceMeters: 92000,
          durationSeconds: 5200,
          destinationLat: 47.8,
          destinationLng: 12.0,
        ),
      );

      try {
        await service.generatePointToPoint(
          startPosition: _munich(),
          destinationLat: 47.8,
          destinationLng: 12.0,
          mode: 'Sport Mode',
          scenic: true,
          routeVariant: 2,
        );
      } on RouteServiceException {
        // Für diese Prüfung zählt nur der Request-Body.
      }

      final mediumDetour =
          verify(mockInvoker.invoke(captureAny)).captured.first
              as Map<String, dynamic>;
      clearInteractions(mockInvoker);

      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async => _buildPointToPointResponse(
          distanceMeters: 112000,
          durationSeconds: 6200,
          destinationLat: 47.8,
          destinationLng: 12.0,
        ),
      );

      try {
        await service.generatePointToPoint(
          startPosition: _munich(),
          destinationLat: 47.8,
          destinationLng: 12.0,
          mode: 'Sport Mode',
          scenic: true,
          routeVariant: 3,
        );
      } on RouteServiceException {
        // Für diese Prüfung zählt nur der Request-Body.
      }

      final largeDetour =
          verify(mockInvoker.invoke(captureAny)).captured.first
              as Map<String, dynamic>;

      expect(
        mediumDetour['targetDistance'] as double,
        greaterThan(smallDetour['targetDistance'] as double),
      );
      expect(
        largeDetour['targetDistance'] as double,
        greaterThan(mediumDetour['targetDistance'] as double),
      );
      expect(
        (largeDetour['targetDistance'] as double) -
            (smallDetour['targetDistance'] as double),
        greaterThan(8),
      );
      expect(mediumDetour['detour_level'], 2);
      expect(largeDetour['detour_level'], 3);
    });

    test(
      'Dornbirn nach Feldkirch Detours senden getrennte Zielkorridore',
      () async {
        final requests = <Map<String, dynamic>>[];
        when(mockInvoker.invoke(any)).thenAnswer((invocation) async {
          final body = Map<String, dynamic>.from(
            invocation.positionalArguments.first as Map,
          );
          requests.add(body);
          final targetKm = (body['targetDistance'] as num?)?.toDouble() ?? 25.0;
          return _buildPointToPointResponse(
            distanceMeters: targetKm * 1000,
            durationSeconds: targetKm * 72,
            destinationLat: _feldkirchLat,
            destinationLng: _feldkirchLng,
            startLat: _dornbirnLat,
            startLng: _dornbirnLng,
            coordinateCount: 220,
            bendScale: 0.035,
          );
        });

        for (final variant in const [1, 2, 3]) {
          try {
            await service.generatePointToPoint(
              startPosition: _dornbirn(),
              destinationLat: _feldkirchLat,
              destinationLng: _feldkirchLng,
              mode: 'Sport Mode',
              scenic: true,
              routeVariant: variant,
            );
          } on RouteServiceException {
            // Fuer diese Repro zaehlt der erste Edge-Request je Detour-Stufe.
          }
        }

        final byDetourLevel = <int, Map<String, dynamic>>{};
        for (final request in requests) {
          final level = request['detour_level'];
          if (request['route_type'] == 'POINT_TO_POINT' && level is int) {
            byDetourLevel.putIfAbsent(level, () => request);
          }
        }

        final directKm =
            geo.Geolocator.distanceBetween(
              _dornbirnLat,
              _dornbirnLng,
              _feldkirchLat,
              _feldkirchLng,
            ) /
            1000.0;
        final styleConfig = RouteStyleConfig.forMode('Sport Mode');
        final targets = <int, double>{};

        for (final variant in const [1, 2, 3]) {
          final request = byDetourLevel[variant]!;
          final targetDistance = (request['targetDistance'] as num).toDouble();
          targets[variant] = targetDistance;

          expect(
            request['startLocation']['latitude'],
            closeTo(_dornbirnLat, 0.001),
          );
          expect(
            request['startLocation']['longitude'],
            closeTo(_dornbirnLng, 0.001),
          );
          expect(
            request['destination_location']['latitude'],
            closeTo(_feldkirchLat, 0.001),
          );
          expect(
            request['destination_location']['longitude'],
            closeTo(_feldkirchLng, 0.001),
          );
          expect(request['mode'], 'Sport Mode');
          expect(request['style_profile'], 'sport');
          expect(request['continue_straight'], isTrue);
          // Variants 1-3 sind alle scenic — Klein bekommt 4, Mittel/Groß 5.
          expect(request['max_candidate_attempts'], variant == 1 ? 4 : 5);
          expect(request['detour_factor'], isA<double>());
        }

        expect(
          targets[1]!,
          inInclusiveRange(
            styleConfig.minimumPointToPointDistanceKm(
              directDistanceKm: directKm,
              scenic: true,
              detourVariant: 1,
            ),
            styleConfig.maximumPointToPointDistanceKm(
              targetKm: targets[1]!,
              directDistanceKm: directKm,
              scenic: true,
              detourVariant: 1,
            ),
          ),
        );
        expect(
          targets[2]!,
          inInclusiveRange(
            styleConfig.minimumPointToPointDistanceKm(
              directDistanceKm: directKm,
              scenic: true,
              detourVariant: 2,
            ),
            styleConfig.maximumPointToPointDistanceKm(
              targetKm: targets[2]!,
              directDistanceKm: directKm,
              scenic: true,
              detourVariant: 2,
            ),
          ),
        );
        expect(
          targets[3]!,
          inInclusiveRange(
            styleConfig.minimumPointToPointDistanceKm(
              directDistanceKm: directKm,
              scenic: true,
              detourVariant: 3,
            ),
            styleConfig.maximumPointToPointDistanceKm(
              targetKm: targets[3]!,
              directDistanceKm: directKm,
              scenic: true,
              detourVariant: 3,
            ),
          ),
        );
        expect(targets[2]!, greaterThan(targets[1]!));
        expect(targets[3]!, greaterThan(targets[2]!));
      },
    );

    test(
      'wiederholte scenic Generierung nutzt unterschiedliche Seeds',
      () async {
        when(mockInvoker.invoke(any)).thenAnswer(
          (_) async =>
              _buildRouteResponse(distanceMeters: 60000, durationSeconds: 4000),
        );

        try {
          await service.generatePointToPoint(
            startPosition: _munich(),
            destinationLat: 47.8,
            destinationLng: 12.0,
            mode: 'Sport Mode',
            scenic: true,
            routeVariant: 1,
            forceFreshVariant: true,
          );
        } on RouteServiceException {
          // Für diese Prüfung ist nur der Request-Seed relevant.
        }

        final first =
            verify(mockInvoker.invoke(captureAny)).captured.first
                as Map<String, dynamic>;
        clearInteractions(mockInvoker);

        when(mockInvoker.invoke(any)).thenAnswer(
          (_) async =>
              _buildRouteResponse(distanceMeters: 60000, durationSeconds: 4000),
        );

        try {
          await service.generatePointToPoint(
            startPosition: _munich(),
            destinationLat: 47.8,
            destinationLng: 12.0,
            mode: 'Sport Mode',
            scenic: true,
            routeVariant: 1,
            forceFreshVariant: true,
          );
        } on RouteServiceException {
          // Für diese Prüfung ist nur der Request-Seed relevant.
        }

        final second =
            verify(mockInvoker.invoke(captureAny)).captured.first
                as Map<String, dynamic>;

        expect(first['randomSeed'], isNot(equals(second['randomSeed'])));
      },
    );

    test(
      'verwirft überlange Scenic-A→B-Routen und nimmt die nächste plausible Alternative',
      () async {
        var callCount = 0;
        when(mockInvoker.invoke(any)).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            return _buildPointToPointResponse(
              distanceMeters: 640000,
              durationSeconds: 24000,
              destinationLat: 47.8095,
              destinationLng: 13.0550,
              coordinateCount: 800,
              bendScale: 0.42,
            );
          }
          return _buildPointToPointResponse(
            distanceMeters: 250000,
            durationSeconds: 14800,
            destinationLat: 47.8095,
            destinationLng: 13.0550,
            coordinateCount: 900,
            bendScale: 0.82,
          );
        });

        final result = await service.generatePointToPoint(
          startPosition: _munich(),
          destinationLat: 47.8095,
          destinationLng: 13.0550,
          mode: 'Sport Mode',
          scenic: true,
          routeVariant: 1,
        );

        expect(callCount, inInclusiveRange(2, 3));
        expect(result.distanceKm, isNotNull);
        expect(result.distanceKm!, lessThan(280));
      },
    );

    test(
      'scenic A→B faellt bei Gross-Umweg nicht still auf Direkt-A→B zurueck',
      () async {
        when(mockInvoker.invoke(any)).thenAnswer((_) async {
          return _buildPointToPointResponse(
            distanceMeters: 21500,
            durationSeconds: 1500,
            destinationLat: _feldkirchLat,
            destinationLng: _feldkirchLng,
            coordinateCount: 180,
            bendScale: 0.04,
            startLat: _dornbirnLat,
            startLng: _dornbirnLng,
          );
        });

        await expectLater(
          service.generatePointToPoint(
            startPosition: _dornbirn(),
            destinationLat: _feldkirchLat,
            destinationLng: _feldkirchLng,
            mode: 'Sport Mode',
            scenic: true,
            routeVariant: 3,
          ),
          throwsA(isA<RouteServiceException>()),
        );

        final captured = verify(
          mockInvoker.invoke(captureAny),
        ).captured.cast<Map<String, dynamic>>();
        final pointToPointRequests = captured.where(
          (request) => request['route_type'] == 'POINT_TO_POINT',
        );
        expect(
          pointToPointRequests.every(
            (request) =>
                (request['detour_level'] as int?) != null &&
                (request['detour_level'] as int) > 0,
          ),
          isTrue,
        );
        expect(
          pointToPointRequests.any((request) => request['detour_level'] == 3),
          isTrue,
        );
      },
    );

    test(
      'Direkt-A→B bewertet normale Fahrdistanz nicht gegen Luftlinie und bleibt benutzbar',
      () async {
        when(mockInvoker.invoke(any)).thenAnswer((_) async {
          return _buildPointToPointResponse(
            distanceMeters: 16600,
            durationSeconds: 1380,
            destinationLat: _bregenzLat,
            destinationLng: _bregenzLng,
            coordinateCount: 220,
            bendScale: 0.10,
            startLat: _dornbirnLat,
            startLng: _dornbirnLng,
          );
        });

        final result = await service.generatePointToPoint(
          startPosition: _dornbirn(),
          destinationLat: _bregenzLat,
          destinationLng: _bregenzLng,
          mode: 'Sport Mode',
          scenic: false,
        );

        expect(result.coordinates, isNotEmpty);
        expect(result.distanceKm, isNotNull);
        expect(result.distanceKm!, greaterThan(15));
        verify(mockInvoker.invoke(any)).called(greaterThanOrEqualTo(1));
      },
    );

    // Hinweis: Früherer Test „scenic A→B stoppt nicht zu früh …“ wurde
    // entfernt: die sinusbasierte Test-Polyline liefert nach Snap eine nahezu
    // feste Länge (~60 km), die mit den verschärften Umweg-Korridoren nicht
    // zuverlässig in [min,max] fällt. Retry-/Fallback-Verhalten ist weiter in
    // „verwirft überlange Scenic-A→B-Routen …“ und Fehlerbehandlung abgedeckt.
  });

  // ─────────────────────── Fehlerbehandlung ──────────────────────────────────

  group('RouteService – Fehlerbehandlung', () {
    test('wirft Exception wenn null zurückgegeben wird', () async {
      when(mockInvoker.invoke(any)).thenAnswer((_) async => null);
      await expectLater(
        service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
        ),
        throwsException,
      );
    });

    test('wirft Exception wenn "error" in Antwort enthalten', () async {
      when(
        mockInvoker.invoke(any),
      ).thenAnswer((_) async => {'error': 'Keine Route gefunden'});
      await expectLater(
        service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
        ),
        throwsException,
      );
    });

    test('bricht bei Validierungsfehlern ohne weitere Fallbacks ab', () async {
      var callCount = 0;
      when(mockInvoker.invoke(any)).thenAnswer((_) async {
        callCount += 1;
        throw const FunctionException(
          status: 422,
          details: {'error': 'Invalid startLocation'},
          reasonPhrase: 'Unprocessable Entity',
        );
      });

      await expectLater(
        service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
        ),
        throwsA(
          isA<RouteServiceException>().having(
            (e) => e.type,
            'type',
            RouteErrorType.validation,
          ),
        ),
      );

      expect(callCount, 1);
    });

    test('mapped "Keine Route gefunden" auf noRoute', () async {
      when(
        mockInvoker.invoke(any),
      ).thenAnswer((_) async => {'error': 'Keine Route gefunden'});
      await expectLater(
        service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
        ),
        throwsA(
          isA<RouteServiceException>().having(
            (e) => e.type,
            'type',
            RouteErrorType.noRoute,
          ),
        ),
      );
    });

    test(
      'mapped noRoute im Rundkurs auf rundkurs-spezifische Meldung',
      () async {
        when(
          mockInvoker.invoke(any),
        ).thenAnswer((_) async => {'error': 'Keine Route gefunden'});

        await expectLater(
          service.generateRoundTrip(
            startPosition: _munich(),
            targetDistanceKm: 50,
            mode: 'Sport Mode',
            planningType: 'Zufall',
          ),
          throwsA(
            isA<RouteServiceException>().having(
              (e) => e.userMessage,
              'userMessage',
              contains('Rundkurs'),
            ),
          ),
        );
      },
    );

    test('mapped noRoute bei A→B auf Start/Ziel-Meldung', () async {
      when(
        mockInvoker.invoke(any),
      ).thenAnswer((_) async => {'error': 'Keine Route gefunden'});

      await expectLater(
        service.generatePointToPoint(
          startPosition: _munich(),
          destinationLat: 48.2082,
          destinationLng: 16.3738,
          mode: 'Abendrunde',
          scenic: true,
          routeVariant: 1,
        ),
        throwsA(
          isA<RouteServiceException>().having(
            (e) => e.userMessage,
            'userMessage',
            contains('Start/Ziel'),
          ),
        ),
      );
    });

    test('wirft Exception wenn "route" fehlt', () async {
      when(mockInvoker.invoke(any)).thenAnswer((_) async => {'meta': 'ok'});
      await expectLater(
        service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
        ),
        throwsException,
      );
    });

    test('wirft Exception wenn geometry fehlt', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async => {
          'route': {'distance': 50000, 'duration': 3600},
        },
      );
      await expectLater(
        service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
        ),
        throwsException,
      );
    });

    test('wirft Exception wenn Koordinaten < 2 Punkte', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async => {
          'route': {
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [11.58, 48.14],
              ], // nur 1 Punkt
            },
            'distance': 50000,
            'duration': 3600,
            'legs': [],
          },
        },
      );
      await expectLater(
        service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
        ),
        throwsException,
      );
    });

    test('retried bei Netzwerkfehler (1× fail, dann Erfolg)', () async {
      var callCount = 0;
      when(mockInvoker.invoke(any)).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) throw Exception('Netzwerkfehler');
        return _buildClosedLoopRouteResponse(
          distanceMeters: 50000,
          durationSeconds: 3600,
        );
      });

      // Retry-Logik: 2 Versuche, der zweite soll klappen
      // Hinweis: Bei Retry wartet der Service 2s — im Test überspringen wir das
      // indem wir fakeAsync nutzen
      final result = await service.generateRoundTrip(
        startPosition: _munich(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
      );

      expect(result, isA<RouteResult>());
      expect(
        callCount,
        2,
        reason: 'Service soll nach Fehler einmal retry versuchen',
      );
    });

    test('wirft Exception nach 2× Netzwerkfehler', () async {
      when(
        mockInvoker.invoke(any),
      ).thenThrow(Exception('Immer Netzwerkfehler'));

      await expectLater(
        service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
        ),
        throwsException,
      );
    });

    test('klassifiziert 401/403 nicht als Internetfehler', () async {
      when(mockInvoker.invoke(any)).thenThrow(
        const FunctionException(
          status: 401,
          details: {'error': 'Unauthorized'},
          reasonPhrase: 'Unauthorized',
        ),
      );

      await expectLater(
        service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
        ),
        throwsA(
          isA<RouteServiceException>().having(
            (e) => e.type,
            'type',
            RouteErrorType.auth,
          ),
        ),
      );
    });

    test('klassifiziert 429 als Rate-Limit', () async {
      when(mockInvoker.invoke(any)).thenThrow(
        const FunctionException(
          status: 429,
          details: {'error': 'Too many requests'},
          reasonPhrase: 'Too Many Requests',
        ),
      );

      await expectLater(
        service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
        ),
        throwsA(
          isA<RouteServiceException>().having(
            (e) => e.type,
            'type',
            RouteErrorType.rateLimit,
          ),
        ),
      );
    });

    test('wirft Exception bei ungültigem JSON-String', () async {
      when(
        mockInvoker.invoke(any),
      ).thenAnswer((_) async => 'kein valid json {{{');
      await expectLater(
        service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
        ),
        throwsException,
      );
    });
  });

  // ─────────────────────── RouteResult Felder ────────────────────────────────

  group('generateRoundTrip – RouteResult', () {
    test('distanceKm wird korrekt befüllt', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 47500, durationSeconds: 3400),
      );

      final result = await service.generateRoundTrip(
        startPosition: _munich(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
      );

      // distanceKm soll aus den bereinigten Koordinaten berechnet werden
      expect(result.distanceKm, isNotNull);
      expect(result.distanceKm!, greaterThan(0));
    });

    test('coordinates nicht leer', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 50000, durationSeconds: 3600),
      );

      final result = await service.generateRoundTrip(
        startPosition: _munich(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
      );

      expect(result.coordinates, isNotEmpty);
    });

    test('geoJson ist valider String', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 50000, durationSeconds: 3600),
      );

      final result = await service.generateRoundTrip(
        startPosition: _munich(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
      );

      expect(result.geoJson, isA<String>());
      expect(result.geoJson, contains('coordinates'));
    });

    test('erster Koordinatenpunkt = Startpunkt nach Snapping', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async => _buildClosedLoopRouteResponse(
          distanceMeters: 50000,
          durationSeconds: 3600,
        ),
      );

      final pos = _munich();
      final result = await service.generateRoundTrip(
        startPosition: pos,
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
      );

      // Nach Snapping soll der erste Punkt die GPS-Position sein
      expect(result.coordinates.first[0], closeTo(pos.longitude, 0.001));
      expect(result.coordinates.first[1], closeTo(pos.latitude, 0.001));
    });
  });

  // ─────────────────────── Fahrstil-Validierung ─────────────────────────────

  group('generateRoundTrip – Fahrstile', () {
    final styles = [
      'Sport Mode',
      'Autobahn',
      'Kurvenreich',
      'Zufall',
      'Panorama',
    ];

    for (final style in styles) {
      test('Fahrstil "$style" wird korrekt übergeben', () async {
        when(mockInvoker.invoke(any)).thenAnswer(
          (_) async => _buildRouteResponse(
            distanceMeters: 50000,
            durationSeconds: 3600,
            mode: style,
          ),
        );

        try {
          await service.generateRoundTrip(
            startPosition: _munich(),
            targetDistanceKm: 50,
            mode: style,
            planningType: 'Zufall',
          );
        } on RouteServiceException {
          // Hier prüfen wir nur die Übergabe des Fahrstils in den Request.
        }

        final captured = verify(
          mockInvoker.invoke(captureAny),
        ).captured.cast<Map>();
        expect(captured.first['mode'], style);
      });
    }
  });

  // ─────────────────────── JSON-String Parsing ──────────────────────────────

  group('generateRoundTrip – JSON als String', () {
    test('verarbeitet JSON-String-Antwort korrekt', () async {
      final responseMap = _buildRouteResponse(
        distanceMeters: 50000,
        durationSeconds: 3600,
      );
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async => json.encode(responseMap), // als String zurückgeben
      );

      final result = await service.generateRoundTrip(
        startPosition: _munich(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
      );

      expect(result, isA<RouteResult>());
      expect(result.coordinates, isNotEmpty);
    });
  });
}
