import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;

void main() {
  group('Navigation Guidance Utils', () {
    test('headingDeltaDegrees liefert minimale Winkeldifferenz', () {
      expect(headingDeltaDegrees(10, 350), closeTo(20, 0.001));
      expect(headingDeltaDegrees(45, 225), closeTo(180, 0.001));
    });

    test('isUTurnHeadingChange erkennt starke Gegenrichtung', () {
      expect(isUTurnHeadingChange(5, 185), isTrue);
      expect(isUTurnHeadingChange(15, 95), isFalse);
    });

    test(
      'selectForwardRejoinIndex bevorzugt vorwaerts ausgerichteten Abschnitt',
      () {
        final route = <List<double>>[];

        // Segment A: nach Norden
        for (var i = 0; i <= 120; i++) {
          route.add([13.0, 47.0 + i * 0.0001]);
        }
        // Segment B: nach Sueden (Gegenrichtung)
        for (var i = 1; i <= 100; i++) {
          route.add([13.0, 47.012 - i * 0.0001]);
        }
        // Segment C: wieder nach Norden
        for (var i = 1; i <= 100; i++) {
          route.add([13.0, 47.002 + i * 0.0001]);
        }

        final idx = selectForwardRejoinIndex(
          coordinates: route,
          nearestIndex: 130,
          currentHeadingDegrees: 0, // Norden
          minLookAheadPoints: 20,
          maxLookAheadPoints: 220,
          maxAlignmentDeltaDegrees: 60,
        );

        // Sollte nicht im gegengerichteten Segment B landen.
        expect(idx, greaterThanOrEqualTo(220));
      },
    );

    test('isUTurnJoin erkennt gegensinnigen Join', () {
      final reroute = [
        [13.0000, 47.0000],
        [13.0010, 47.0000], // Osten
      ];
      final originalOpposite = [
        [13.0020, 47.0000],
        [13.0010, 47.0000], // Westen
        [13.0000, 47.0000],
      ];
      final originalAligned = [
        [13.0020, 47.0000],
        [13.0030, 47.0000], // Osten
        [13.0040, 47.0000],
      ];

      expect(
        isUTurnJoin(
          rerouteCoordinates: reroute,
          originalCoordinates: originalOpposite,
          rejoinIndex: 0,
        ),
        isTrue,
      );
      expect(
        isUTurnJoin(
          rerouteCoordinates: reroute,
          originalCoordinates: originalAligned,
          rejoinIndex: 0,
        ),
        isFalse,
      );
    });
  });

  group('findNearestInWindow', () {
    final coords = List.generate(30, (i) => [13.0 + i * 0.0001, 47.0]);

    test('behaelt aktuellen Index wenn Match ausserhalb maxJump liegt', () {
      final match = findNearestInWindow(
        position: _position(latitude: 48.0, longitude: 14.0),
        coordinates: coords,
        currentIndex: 5,
        windowSize: 20,
        maxJumpMeters: 50,
      );

      expect(match.index, equals(5));
      expect(match.distanceMeters, greaterThan(50));
    });

    test('springt vorwaerts wenn Match innerhalb maxJump liegt', () {
      final target = coords[12];
      final match = findNearestInWindow(
        position: _position(latitude: target[1], longitude: target[0]),
        coordinates: coords,
        currentIndex: 5,
        windowSize: 20,
        maxJumpMeters: 50,
      );

      expect(match.index, equals(12));
      expect(match.distanceMeters, lessThan(1));
    });
  });

  group('distanceToCoordinateMeters', () {
    test('liefert fuer identische Koordinaten nahezu 0 Meter', () {
      final position = _position(latitude: 48.137, longitude: 11.575);

      final distance = distanceToCoordinateMeters(
        position: position,
        coordinate: [11.575, 48.137],
      );

      expect(distance, closeTo(0, 0.001));
    });

    test('liefert fuer einen Punkt noerdlich davon etwa 1 km', () {
      final position = _position(latitude: 48.137, longitude: 11.575);

      final distance = distanceToCoordinateMeters(
        position: position,
        coordinate: [11.575, 48.14599],
      );

      expect(distance, closeTo(1000, 30));
    });
  });

  group('isApproachingDestination', () {
    test('erkennt eine klare Zielannaeherung', () {
      expect(isApproachingDestination([1200, 1040, 930, 810, 700]), isTrue);
    });

    test(
      'erkennt keine stabile Zielannaeherung ohne genuegende Verbesserung',
      () {
        expect(
          isApproachingDestination([1200, 1198, 1194, 1191, 1189]),
          isFalse,
        );
      },
    );

    test('braucht mindestens drei Samples', () {
      expect(isApproachingDestination([1200, 1100]), isFalse);
    });
  });
}

geo.Position _position({required double latitude, required double longitude}) {
  return geo.Position(
    longitude: longitude,
    latitude: latitude,
    timestamp: DateTime.now(),
    accuracy: 1,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}
