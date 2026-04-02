// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

/// Erzeugt eine valide Supabase-Antwort mit der angegebenen Distanz.
Map<String, dynamic> _buildRouteResponse({
  required double distanceMeters,
  required double durationSeconds,
  int coordinateCount = 100,
  List<Map<String, dynamic>>? legs,
  String mode = 'Sport Mode',
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
      11.592 + math.cos(t) * radius * params.stretch,
      48.140 + math.sin(t) * radius * params.aspect,
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
                    'location': [11.583, 48.136],
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
}) {
  const startLng = 11.5820;
  const startLat = 48.1351;
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

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.last
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
        (_) async =>
            _buildRouteResponse(distanceMeters: 56000, durationSeconds: 3600),
      );

      await service.generatePointToPoint(
        startPosition: _munich(),
        destinationLat: 47.8,
        destinationLng: 12.0,
        mode: 'Alpenstraßen',
        scenic: true,
      );

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.first
              as Map<String, dynamic>;
      expect(captured['mode'], 'Alpenstraßen');
    });

    test(
      'scenic = true → targetDistance und dynamischer randomSeed werden mitgesendet',
      () async {
        when(mockInvoker.invoke(any)).thenAnswer(
          (_) async =>
              _buildRouteResponse(distanceMeters: 82000, durationSeconds: 5200),
        );

        await service.generatePointToPoint(
          startPosition: _munich(),
          destinationLat: 47.8,
          destinationLng: 12.0,
          mode: 'Sport Mode',
          scenic: true,
          routeVariant: 2,
        );

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
          (_) async =>
              _buildRouteResponse(distanceMeters: 98000, durationSeconds: 6200),
        );

        await service.generatePointToPoint(
          startPosition: _munich(),
          destinationLat: 47.8,
          destinationLng: 12.0,
          mode: 'Sport Mode',
          scenic: true,
          routeVariant: 3,
          avoidHighways: true,
        );

        final captured =
            verify(mockInvoker.invoke(captureAny)).captured.first
                as Map<String, dynamic>;
        expect(captured['avoid_highways'], isTrue);
        expect(captured['targetDistance'], isNotNull);
        expect(captured['detour_level'], 3);
        expect(captured['detour_factor'], isNotNull);
      },
    );

    test('Umwegstufen skalieren die targetDistance sichtbar', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 66000, durationSeconds: 4200),
      );

      await service.generatePointToPoint(
        startPosition: _munich(),
        destinationLat: 47.8,
        destinationLng: 12.0,
        mode: 'Sport Mode',
        scenic: true,
        routeVariant: 1,
      );

      final smallDetour =
          verify(mockInvoker.invoke(captureAny)).captured.first
              as Map<String, dynamic>;
      clearInteractions(mockInvoker);

      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 82000, durationSeconds: 5200),
      );

      await service.generatePointToPoint(
        startPosition: _munich(),
        destinationLat: 47.8,
        destinationLng: 12.0,
        mode: 'Sport Mode',
        scenic: true,
        routeVariant: 2,
      );

      final mediumDetour =
          verify(mockInvoker.invoke(captureAny)).captured.first
              as Map<String, dynamic>;
      clearInteractions(mockInvoker);

      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 98000, durationSeconds: 6200),
      );

      await service.generatePointToPoint(
        startPosition: _munich(),
        destinationLat: 47.8,
        destinationLng: 12.0,
        mode: 'Sport Mode',
        scenic: true,
        routeVariant: 3,
      );

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
            distanceMeters: 165000,
            durationSeconds: 9800,
            destinationLat: 47.8095,
            destinationLng: 13.0550,
            coordinateCount: 500,
            bendScale: 0.36,
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

        expect(callCount, 2);
        expect(result.distanceKm, isNotNull);
        expect(result.distanceKm!, lessThan(200));
      },
    );
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

        final captured =
            verify(mockInvoker.invoke(captureAny)).captured.last
                as Map<String, dynamic>;
        expect(captured['mode'], style);
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
