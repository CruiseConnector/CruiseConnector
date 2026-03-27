// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:geolocator/geolocator.dart' as geo;
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
}) {
  // Koordinaten als gerade Nord-Route generieren
  final coords = List.generate(
    coordinateCount,
    (i) => [11.582 + i * 0.0001, 48.135 + i * 0.0001],
  );

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

// ─────────────────────────────────────────────────────────────────────────────

@GenerateMocks([RouteEdgeInvoker])
void main() {
  late MockRouteEdgeInvoker mockInvoker;
  late RouteService service;

  setUp(() {
    mockInvoker = MockRouteEdgeInvoker();
    service = RouteService(invoker: mockInvoker);
  });

  // ─────────────────────── Distanztoleranzen ─────────────────────────────────

  group('generateRoundTrip – Distanztoleranzen', () {
    /// Helper: Testet ob die zurückgegebene Route innerhalb der Toleranz liegt.
    Future<void> _testDistanceTolerance({
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
      await _testDistanceTolerance(targetKm: 30, responseDistanceM: 30000);
    });

    test('50 km Ziel → Route zwischen 40 km und 60 km', () async {
      await _testDistanceTolerance(targetKm: 50, responseDistanceM: 50000);
    });

    test('50 km Ziel, 45 km Antwort (10% unter) → noch akzeptiert', () async {
      await _testDistanceTolerance(
        targetKm: 50,
        responseDistanceM: 45000,
        tolerancePercent: 0.15,
      );
    });

    test('50 km Ziel, 55 km Antwort (10% über) → noch akzeptiert', () async {
      await _testDistanceTolerance(
        targetKm: 50,
        responseDistanceM: 55000,
        tolerancePercent: 0.15,
      );
    });

    test('80 km Ziel → Route zwischen 64 km und 96 km', () async {
      await _testDistanceTolerance(targetKm: 80, responseDistanceM: 80000);
    });

    test('100 km Ziel → Route zwischen 80 km und 120 km', () async {
      await _testDistanceTolerance(
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
          verify(mockInvoker.invoke(captureAny)).captured.single
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
          verify(mockInvoker.invoke(captureAny)).captured.single
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
          verify(mockInvoker.invoke(captureAny)).captured.single
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
          verify(mockInvoker.invoke(captureAny)).captured.single
              as Map<String, dynamic>;
      expect(captured['language'], 'de');
    });

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
          verify(mockInvoker.invoke(captureAny)).captured.single
              as Map<String, dynamic>;
      expect(captured['planning_type'], 'Kurvenreich');
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
          verify(mockInvoker.invoke(captureAny)).captured.single
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

      await service.generatePointToPoint(
        startPosition: _munich(),
        destinationLat: 47.8,
        destinationLng: 12.0,
        mode: 'Sport Mode',
      );

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.single
              as Map<String, dynamic>;
      expect(captured['route_type'], 'POINT_TO_POINT');
    });

    test('sendet destination_location korrekt', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 20000, durationSeconds: 1800),
      );

      await service.generatePointToPoint(
        startPosition: _munich(),
        destinationLat: 47.9123,
        destinationLng: 12.4567,
        mode: 'Sport Mode',
      );

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.single
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

      await service.generatePointToPoint(
        startPosition: _munich(),
        destinationLat: 47.8,
        destinationLng: 12.0,
        mode: 'Sport Mode',
        scenic: false,
      );

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.single
              as Map<String, dynamic>;
      expect(captured['mode'], 'Standard');
    });

    test('scenic = true → übergibt den eigentlichen mode', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 20000, durationSeconds: 1800),
      );

      await service.generatePointToPoint(
        startPosition: _munich(),
        destinationLat: 47.8,
        destinationLng: 12.0,
        mode: 'Alpenstraßen',
        scenic: true,
      );

      final captured =
          verify(mockInvoker.invoke(captureAny)).captured.single
              as Map<String, dynamic>;
      expect(captured['mode'], 'Alpenstraßen');
    });

    test(
      'scenic = true → targetDistance und randomSeed werden mitgesendet',
      () async {
        when(mockInvoker.invoke(any)).thenAnswer(
          (_) async =>
              _buildRouteResponse(distanceMeters: 60000, durationSeconds: 4000),
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
            verify(mockInvoker.invoke(captureAny)).captured.single
                as Map<String, dynamic>;
        expect(captured['targetDistance'], isNotNull);
        expect(captured['randomSeed'], 2);
      },
    );

    test('groesserer Umweg erzeugt groessere targetDistance', () async {
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 60000, durationSeconds: 4000),
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
          verify(mockInvoker.invoke(captureAny)).captured.single
              as Map<String, dynamic>;
      clearInteractions(mockInvoker);

      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async =>
            _buildRouteResponse(distanceMeters: 60000, durationSeconds: 4000),
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
          verify(mockInvoker.invoke(captureAny)).captured.single
              as Map<String, dynamic>;

      expect(
        largeDetour['targetDistance'] as double,
        greaterThan(smallDetour['targetDistance'] as double),
      );
      expect(largeDetour['detour_level'], 3);
    });
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
        return _buildRouteResponse(
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
        (_) async =>
            _buildRouteResponse(distanceMeters: 50000, durationSeconds: 3600),
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
          (_) async =>
              _buildRouteResponse(distanceMeters: 50000, durationSeconds: 3600),
        );

        await service.generateRoundTrip(
          startPosition: _munich(),
          targetDistanceKm: 50,
          mode: style,
          planningType: 'Zufall',
        );

        final captured =
            verify(mockInvoker.invoke(captureAny)).captured.single
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
