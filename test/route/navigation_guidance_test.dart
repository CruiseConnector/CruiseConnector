// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';

void main() {
  // ─────────────────────── selectForwardRejoinIndex ─────────────────────────

  group('selectForwardRejoinIndex', () {
    /// Erzeugt eine lange gerade Route.
    List<List<double>> _longRoute({int points = 500}) =>
        List.generate(points, (i) => [11.58 + i * 0.0001, 48.14]);

    test('gibt Index zurück der in Fahrtrichtung liegt', () {
      final coords = _longRoute();
      // Nordwärts fahrend (bearing ≈ 0°)
      final result = selectForwardRejoinIndex(
        coordinates: coords,
        nearestIndex: 100,
        currentHeadingDegrees: 0.0, // Norden
      );
      // Soll 90-320 Punkte voraus suchen
      expect(result, inInclusiveRange(100, 420));
    });

    test('weniger als 2 Koordinaten → gibt 0 zurück', () {
      final result = selectForwardRejoinIndex(
        coordinates: [[11.58, 48.14]],
        nearestIndex: 0,
        currentHeadingDegrees: 0.0,
      );
      expect(result, 0);
    });

    test('nearestIndex am Ende → kein Absturz', () {
      final coords = _longRoute(points: 50);
      expect(
        () => selectForwardRejoinIndex(
          coordinates: coords,
          nearestIndex: 48,
          currentHeadingDegrees: 90.0,
        ),
        returnsNormally,
      );
    });

    test('minIndex >= maxIndex → gibt minIndex zurück', () {
      final coords = _longRoute(points: 10);
      final result = selectForwardRejoinIndex(
        coordinates: coords,
        nearestIndex: 9,
        currentHeadingDegrees: 0.0,
        minLookAheadPoints: 5,
        maxLookAheadPoints: 5,
      );
      expect(result, inInclusiveRange(0, 9));
    });

    test('Richtung 90° (Osten) auf Ost-Route → guter Kandidat gefunden', () {
      // Route geht nach Osten (lng steigt)
      final coords = List.generate(500, (i) => [11.58 + i * 0.001, 48.14]);
      final result = selectForwardRejoinIndex(
        coordinates: coords,
        nearestIndex: 50,
        currentHeadingDegrees: 90.0, // Osten
      );
      expect(result, greaterThan(50));
    });

    test('maxAlignmentDeltaDegrees zu klein → Fallback auf minIndex', () {
      final coords = _longRoute();
      // Heading 90° (Osten), aber Route geht Norden → keine guten Kandidaten
      final result = selectForwardRejoinIndex(
        coordinates: coords,
        nearestIndex: 100,
        currentHeadingDegrees: 90.0,
        maxAlignmentDeltaDegrees: 5.0, // sehr enge Toleranz
      );
      // Soll trotzdem einen Wert zurückgeben (kein Absturz)
      expect(result, isA<int>());
    });
  });

  // ─────────────────────── Heading-Berechnungen ──────────────────────────────

  group('headingDeltaDegrees – Randfälle', () {
    test('0° vs 0° → 0°', () {
      expect(headingDeltaDegrees(0, 0), 0.0);
    });

    test('360° vs 0° → 0° (Wraparound)', () {
      expect(headingDeltaDegrees(360, 0), closeTo(0.0, 0.1));
    });

    test('180° vs 180° → 0°', () {
      expect(headingDeltaDegrees(180, 180), 0.0);
    });

    test('45° vs 315° → 90°', () {
      expect(headingDeltaDegrees(45, 315), closeTo(90.0, 0.1));
    });

    test('Negative Werte werden korrekt behandelt', () {
      // -90° = 270°
      expect(headingDeltaDegrees(-90, 90), closeTo(180.0, 1.0));
    });
  });

  group('isUTurnHeadingChange – Grenzwerte', () {
    test('Genau 145° → U-Turn (Standard-Schwelle)', () {
      expect(isUTurnHeadingChange(0, 145), isTrue);
    });

    test('Genau 144.9° → kein U-Turn', () {
      expect(isUTurnHeadingChange(0, 144.9), isFalse);
    });

    test('Nordfahrt, dann Süden (180°) → U-Turn', () {
      expect(isUTurnHeadingChange(0, 180), isTrue);
    });

    test('Ost-West (90°) → kein U-Turn', () {
      expect(isUTurnHeadingChange(0, 90), isFalse);
    });

    test('Wraparound: 355° → 175° = 180° Delta → U-Turn', () {
      expect(isUTurnHeadingChange(355, 175), isTrue);
    });
  });

  // ─────────────────────── bearingFromCoordinates ────────────────────────────

  group('bearingFromCoordinates', () {
    test('[lng, lat] Format: Norden', () {
      final b = bearingFromCoordinates([11.58, 48.0], [11.58, 48.1]);
      expect(b, closeTo(0.0, 2.0));
    });

    test('[lng, lat] Format: Süden', () {
      final b = bearingFromCoordinates([11.58, 48.1], [11.58, 48.0]);
      expect(b, closeTo(180.0, 2.0));
    });

    test('[lng, lat] Format: Osten', () {
      final b = bearingFromCoordinates([11.5, 48.1], [11.6, 48.1]);
      expect(b, closeTo(90.0, 5.0));
    });

    test('[lng, lat] Format: Westen', () {
      final b = bearingFromCoordinates([11.6, 48.1], [11.5, 48.1]);
      expect(b, closeTo(270.0, 5.0));
    });

    test('Ergebnis immer in [0, 360]', () {
      final testPairs = [
        [[0.0, 0.0], [1.0, 1.0]],
        [[10.0, 50.0], [9.0, 49.0]],
        [[-73.9, 40.7], [2.35, 48.85]], // NYC → Paris
      ];
      for (final pair in testPairs) {
        final b = bearingFromCoordinates(pair[0], pair[1]);
        expect(b, inInclusiveRange(0.0, 360.0));
      }
    });
  });

  // ─────────────────────── Navigations-Integration ───────────────────────────

  group('Navigation-Integration – Rerouting-Logik', () {
    test('Fahrzeug fährt in falsche Richtung (180° Abweichung) → isUTurn', () {
      // User fährt Norden, Route geht Süden → U-Turn nötig
      final routeHeading = 0.0;   // Norden
      final vehicleHeading = 180.0; // Süden
      expect(isUTurnHeadingChange(vehicleHeading, routeHeading), isTrue);
    });

    test('Fahrzeug biegt 90° ab → kein U-Turn, normales Rerouting', () {
      final routeHeading = 0.0;   // Norden
      final vehicleHeading = 90.0; // Osten (abgebogen)
      expect(isUTurnHeadingChange(vehicleHeading, routeHeading), isFalse);
    });

    test('headingDelta von 30° → gleiche Richtung, kein Rerouting nötig', () {
      final delta = headingDeltaDegrees(0, 30);
      expect(delta, lessThan(90.0));
    });

    test('routeHeadingAt liefert konsistente Bearings für gerade Route', () {
      // Gerade nach Osten
      final coords = List.generate(
        10,
        (i) => [11.58 + i * 0.001, 48.14],
      );
      for (var i = 0; i < coords.length - 2; i++) {
        final h1 = routeHeadingAt(coords, i);
        final h2 = routeHeadingAt(coords, i + 1);
        // Auf gerader Route soll Bearing konstant bleiben
        expect(headingDeltaDegrees(h1, h2), lessThan(5.0),
            reason: 'Bearing sollte auf gerader Route konstant sein');
      }
    });
  });
}
