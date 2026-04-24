// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';

void main() {
  group('calculateBearing – Himmelsrichtungen', () {
    // München als Startpunkt, Bewegung in alle Richtungen

    test('Norden: Bearing ≈ 0°', () {
      final b = calculateBearing(48.0, 11.58, 48.1, 11.58);
      expect(b, closeTo(0.0, 2.0));
    });

    test('Süden: Bearing ≈ 180°', () {
      final b = calculateBearing(48.1, 11.58, 48.0, 11.58);
      expect(b, closeTo(180.0, 2.0));
    });

    test('Osten: Bearing ≈ 90°', () {
      final b = calculateBearing(48.1, 11.58, 48.1, 11.68);
      expect(b, closeTo(90.0, 5.0)); // etwas mehr Toleranz wegen sphärischer Geometrie
    });

    test('Westen: Bearing ≈ 270°', () {
      final b = calculateBearing(48.1, 11.68, 48.1, 11.58);
      expect(b, closeTo(270.0, 5.0));
    });

    test('Nordosten: Bearing zwischen 0° und 90°', () {
      final b = calculateBearing(48.0, 11.58, 48.1, 11.68);
      expect(b, inInclusiveRange(30.0, 60.0));
    });

    test('Südwesten: Bearing zwischen 180° und 270°', () {
      final b = calculateBearing(48.1, 11.68, 48.0, 11.58);
      expect(b, inInclusiveRange(210.0, 250.0));
    });

    test('Selber Punkt → Bearing ist ein definierter Wert (kein Absturz)', () {
      expect(() => calculateBearing(48.1, 11.58, 48.1, 11.58), returnsNormally);
    });

    test('Bearing ist immer zwischen 0 und 360', () {
      final testCases = [
        [48.0, 11.0, 49.0, 12.0],
        [50.0, 10.0, 48.0, 9.0],
        [-33.8, 151.2, 51.5, -0.12], // Sydney → London
        [0.0, 0.0, 0.0, 0.0],
      ];
      for (final c in testCases) {
        final b = calculateBearing(c[0], c[1], c[2], c[3]);
        expect(b, inInclusiveRange(0.0, 360.0),
            reason: 'Bearing außerhalb [0,360] für $c');
      }
    });
  });

  group('headingDeltaDegrees – Winkelunterschied', () {
    test('Gleiche Richtung: Delta = 0°', () {
      expect(headingDeltaDegrees(90, 90), closeTo(0.0, 0.1));
    });

    test('Entgegengesetzte Richtung: Delta = 180°', () {
      expect(headingDeltaDegrees(0, 180), closeTo(180.0, 0.1));
    });

    test('90° Unterschied', () {
      expect(headingDeltaDegrees(0, 90), closeTo(90.0, 0.1));
    });

    test('Wraparound: 350° und 10° → Delta = 20°', () {
      expect(headingDeltaDegrees(350, 10), closeTo(20.0, 0.1));
    });

    test('Wraparound: 10° und 350° → Delta = 20°', () {
      expect(headingDeltaDegrees(10, 350), closeTo(20.0, 0.1));
    });

    test('270° und 90° → Delta = 180°', () {
      expect(headingDeltaDegrees(270, 90), closeTo(180.0, 0.1));
    });

    test('Ergebnis ist immer zwischen 0 und 180', () {
      for (var a = 0; a < 360; a += 15) {
        for (var b = 0; b < 360; b += 15) {
          final delta = headingDeltaDegrees(a.toDouble(), b.toDouble());
          expect(delta, inInclusiveRange(0.0, 180.0),
              reason: 'Delta außerhalb [0,180] für a=$a, b=$b');
        }
      }
    });
  });

  group('isUTurnHeadingChange – Wendeerkennung', () {
    test('Richtungsänderung von 180° = U-Turn', () {
      expect(isUTurnHeadingChange(0, 180), isTrue);
    });

    test('Richtungsänderung von 145° = U-Turn (Schwelle)', () {
      expect(isUTurnHeadingChange(0, 145), isTrue);
    });

    test('Richtungsänderung von 144° = KEIN U-Turn', () {
      expect(isUTurnHeadingChange(0, 144), isFalse);
    });

    test('Geradeaus (0°) = kein U-Turn', () {
      expect(isUTurnHeadingChange(90, 90), isFalse);
    });

    test('90° Kurve = kein U-Turn', () {
      expect(isUTurnHeadingChange(0, 90), isFalse);
    });

    test('Wraparound: 10° → 190° = U-Turn (180°)', () {
      expect(isUTurnHeadingChange(10, 190), isTrue);
    });

    test('Custom Schwelle: 120° bei 130° Änderung = U-Turn', () {
      expect(
        isUTurnHeadingChange(0, 130, thresholdDegrees: 120),
        isTrue,
      );
    });

    test('Custom Schwelle: 120° bei 119° Änderung = kein U-Turn', () {
      expect(
        isUTurnHeadingChange(0, 119, thresholdDegrees: 120),
        isFalse,
      );
    });
  });

  group('bearingFromCoordinates – [lng, lat] Format', () {
    test('Norden: Bearing ≈ 0°', () {
      final b = bearingFromCoordinates([11.58, 48.0], [11.58, 48.1]);
      expect(b, closeTo(0.0, 2.0));
    });

    test('Osten: Bearing ≈ 90°', () {
      final b = bearingFromCoordinates([11.58, 48.1], [11.68, 48.1]);
      expect(b, closeTo(90.0, 5.0));
    });

    test('Leere Liste → kein Absturz', () {
      expect(() => bearingFromCoordinates([0.0, 0.0], [0.0, 0.0]), returnsNormally);
    });
  });

  group('routeHeadingAt – Routenabschnitt-Bearing', () {
    test('Gibt Bearing des Abschnitts index→index+1 zurück', () {
      final coords = [
        [11.58, 48.0],
        [11.58, 48.1], // Norden
        [11.68, 48.1], // Osten
      ];
      expect(routeHeadingAt(coords, 0), closeTo(0.0, 2.0));  // Norden
      expect(routeHeadingAt(coords, 1), closeTo(90.0, 5.0)); // Osten
    });

    test('Index am Ende: kein Absturz, gibt Wert zurück', () {
      final coords = [[11.58, 48.0], [11.58, 48.1]];
      expect(() => routeHeadingAt(coords, 10), returnsNormally);
    });

    test('Weniger als 2 Punkte → gibt 0 zurück', () {
      expect(routeHeadingAt([[11.58, 48.0]], 0), 0.0);
    });
  });
}
