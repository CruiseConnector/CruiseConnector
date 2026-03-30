import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/route_quality_validator.dart';

void main() {
  const validator = RouteQualityValidator();

  group('validateOverlap', () {
    test('Keine Überlappung bei gerader Linie', () {
      // Gerade Linie von Süd nach Nord (kein Backtracking)
      final coords = List.generate(
        100,
        (i) => [11.0, 48.0 + i * 0.001], // ~111m pro Schritt
      );
      final overlap = validator.validateOverlap(coords);
      expect(overlap, lessThan(5.0));
    });

    test('Hohe Überlappung bei Hin-und-Zurück', () {
      // Hin und exakt zurück = Backtracking
      // 200 Punkte pro Richtung, 0.0001° Abstand ≈ 11m pro Schritt
      // overlapProximity=40m, also müssen Punkte <40m auseinander sein
      final outbound = List.generate(200, (i) => [11.0, 48.0 + i * 0.0001]);
      final inbound = List.generate(
        200,
        (i) => [11.0, 48.0 + (199 - i) * 0.0001],
      );
      final coords = [...outbound, ...inbound];
      final overlap = validator.validateOverlap(coords);
      expect(overlap, greaterThan(20.0));
    });

    test('Nahe Kreuzung ohne Backtracking bleibt unter dem Grenzwert', () {
      final vertical = List.generate(120, (i) => [11.0, 48.0 + i * 0.0001]);
      final horizontal = List.generate(
        120,
        (i) => [10.994 + i * 0.0001, 48.006],
      );
      final coords = [...vertical, ...horizontal];

      final overlap = validator.validateOverlap(coords);

      expect(overlap, lessThan(12.0));
    });
  });

  group('buildRouteFingerprint', () {
    test('gleiche Route erzeugt denselben Fingerprint', () {
      final coordinates = List.generate(
        40,
        (i) => [11.0 + i * 0.0002, 48.0 + i * 0.0001],
      );

      final first = RouteQualityValidator.buildRouteFingerprint(
        coordinates,
        distanceKm: 24.6,
      );
      final second = RouteQualityValidator.buildRouteFingerprint(
        coordinates,
        distanceKm: 24.6,
      );

      expect(first, equals(second));
    });

    test('deutlich andere Route erzeugt anderen Fingerprint', () {
      final firstRoute = List.generate(
        40,
        (i) => [11.0 + i * 0.0002, 48.0 + i * 0.0001],
      );
      final secondRoute = List.generate(
        40,
        (i) => [11.02 + i * 0.00015, 48.01 - i * 0.00008],
      );

      final first = RouteQualityValidator.buildRouteFingerprint(
        firstRoute,
        distanceKm: 24.6,
      );
      final second = RouteQualityValidator.buildRouteFingerprint(
        secondRoute,
        distanceKm: 31.4,
      );

      expect(first, isNot(equals(second)));
    });
  });

  group('validateNoUturns', () {
    test('Keine U-Turns bei sanfter Kurve', () {
      // Sanfte Kurve: kein abrupter Richtungswechsel
      final coords = List.generate(
        50,
        (i) => [11.0 + i * 0.0005, 48.0 + i * 0.0005],
      );
      final uturns = validator.validateNoUturns(coords);
      expect(uturns, isEmpty);
    });

    test('U-Turn erkannt bei 180° Wende', () {
      // Gerade nach Norden, dann abrupt nach Süden
      final north = List.generate(20, (i) => [11.0, 48.0 + i * 0.0003]);
      final south = List.generate(20, (i) => [11.0, 48.0 + 0.006 - i * 0.0003]);
      final coords = [...north, ...south];
      final uturns = validator.validateNoUturns(coords);
      expect(uturns, isNotEmpty);
    });
  });

  group('validateLoopClosed', () {
    test('Geschlossener Loop erkannt', () {
      // Start und Ende am selben Punkt
      final coords = [
        [11.0, 48.0],
        [11.01, 48.01],
        [11.02, 48.0],
        [11.0, 48.0], // Ende = Start
      ];
      expect(validator.validateLoopClosed(coords), isTrue);
    });

    test('Offener Loop erkannt', () {
      final coords = [
        [11.0, 48.0],
        [11.01, 48.01],
        [12.0, 49.0], // Ende weit vom Start
      ];
      expect(validator.validateLoopClosed(coords), isFalse);
    });
  });

  group('validateDistanceTolerance', () {
    test('Innerhalb ±12% Toleranz', () {
      expect(validator.validateDistanceTolerance(50.0, 48.0), isTrue);
      expect(validator.validateDistanceTolerance(50.0, 55.0), isTrue);
    });

    test('Außerhalb Toleranz', () {
      expect(validator.validateDistanceTolerance(50.0, 40.0), isFalse);
      expect(validator.validateDistanceTolerance(50.0, 60.0), isFalse);
    });
  });

  group('validateQuality – Gesamtbewertung', () {
    test('Gerade Rundkurs-Route besteht', () {
      // Dreieck: Start → Nord → Ost → zurück zum Start
      final coords = <List<double>>[];
      // Leg 1: Start nach Norden
      for (var i = 0; i < 40; i++) {
        coords.add([11.0, 48.0 + i * 0.002]);
      }
      // Leg 2: Nach Osten
      for (var i = 0; i < 40; i++) {
        coords.add([11.0 + i * 0.002, 48.08]);
      }
      // Leg 3: Zurück zum Start
      for (var i = 0; i < 40; i++) {
        final t = i / 39;
        coords.add([11.08 * (1 - t) + 11.0 * t, 48.08 * (1 - t) + 48.0 * t]);
      }

      final result = validator.validateQuality(
        coordinates: coords,
        isRoundTrip: true,
        targetDistanceKm: 50.0,
        actualDistanceKm: 48.0,
      );
      expect(result.overlapPercent, lessThan(15.0));
      expect(result.uturnPositions, isEmpty);
      expect(result.isLoopClosed, isTrue);
      expect(result.distanceInTolerance, isTrue);
    });
  });
}
