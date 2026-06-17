import 'package:cruise_connect/presentation/widgets/cruise/nav_distance_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-06-13 (vucko J2): Google-Maps-Style Distanz-Stufen. Der User will
/// saubere Zahlen (690, 680, 670) statt „krummer" wie 522 m.
void main() {
  group('formatNavDistance', () {
    test('null → --', () => expect(formatNavDistance(null), '--'));

    test('< 1 km auf 10er-Stufen gerundet', () {
      expect(formatNavDistance(522), '520 m');
      expect(formatNavDistance(694), '690 m');
      expect(formatNavDistance(685), '690 m'); // .5 → auf
      expect(formatNavDistance(683), '680 m');
      expect(formatNavDistance(677), '680 m');
      expect(formatNavDistance(671), '670 m');
    });

    test('NIE krumme Einer-Stelle unter 1 km', () {
      for (var m = 11; m < 1000; m++) {
        final s = formatNavDistance(m.toDouble());
        expect(s.endsWith('0 m'), isTrue, reason: '$m m → "$s"');
      }
    });

    test('1–10 km → ein Dezimal mit Komma', () {
      expect(formatNavDistance(2100), '2,1 km');
      expect(formatNavDistance(1000), '1,0 km');
      expect(formatNavDistance(5000), '5,0 km');
    });

    test('≥ 10 km → ganze km', () {
      expect(formatNavDistance(26000), '26 km');
      expect(formatNavDistance(12340), '12 km');
    });

    test('nowLabelUnderTen: < 10 m → Jetzt', () {
      expect(formatNavDistance(5, nowLabelUnderTen: true), 'Jetzt');
      expect(formatNavDistance(0, nowLabelUnderTen: true), 'Jetzt');
      // Ohne Flag bleibt es eine (10er-gestufte) Meter-Zahl: 5 → 10.
      expect(formatNavDistance(5), '10 m');
    });

    test('negativ → 0-geklemmt', () {
      expect(formatNavDistance(-50), '0 m');
    });
  });

  // 2026-06-17 (vucko Schnellstraße-Freeze, Geräte-Video): Das Banner blieb auf
  // der Schnellstraße bei „1,0 km" hängen, weil der gleitende Render-Vorlauf bei
  // 80 m abgekappt wurde. Auf weiten Routen-Stützpunkten (Index springt selten)
  // fror die Anzeige damit ein. smoothManeuverDistanceMeters zieht jetzt den
  // GANZEN plausiblen Vorlauf ab → base - ahead == cum[Manöver] - render.
  group('smoothManeuverDistanceMeters', () {
    test('REGRESSION Schnellstraße: 1000 m fror NICHT mehr ein', () {
      // Index steht bei 0 (cum[0]=0); der Puck ist real schon 400 m weiter.
      // Früher (>80 m Kappe) → 1000 (eingefroren). Jetzt → 600.
      expect(
        smoothManeuverDistanceMeters(
          base: 1000, cum: [0, 1500, 3000], render: 400, currentIndex: 0),
        600,
      );
      // weiter gefahren (700 m Vorlauf) → 300, NICHT 1000.
      expect(
        smoothManeuverDistanceMeters(
          base: 1000, cum: [0, 1500, 3000], render: 700, currentIndex: 0),
        300,
      );
    });

    test('Stadt: kleiner Vorlauf (<80 m) wie bisher abgezogen', () {
      expect(
        smoothManeuverDistanceMeters(
          base: 200, cum: [0, 100, 200], render: 50, currentIndex: 0),
        150,
      );
    });

    test('stale (render hinter dem Index) → ehrlicher Index-Wert', () {
      expect(
        smoothManeuverDistanceMeters(
          base: 500, cum: [0, 1000], render: 900, currentIndex: 1),
        500,
      );
    });

    test('render nicht initialisiert (<0) → base', () {
      expect(
        smoothManeuverDistanceMeters(
          base: 500, cum: [0, 1000], render: -1, currentIndex: 0),
        500,
      );
    });

    test('Puck am/über Manöver → 0 (Jetzt), nicht negativ', () {
      expect(
        smoothManeuverDistanceMeters(
          base: 300, cum: [0, 1000], render: 320, currentIndex: 0),
        0,
      );
    });

    test('grober Render-Sprung (weit hinters Manöver) → base (kein Unsinn)', () {
      expect(
        smoothManeuverDistanceMeters(
          base: 300, cum: [0, 1000], render: 900, currentIndex: 0),
        300,
      );
    });

    test('leere cum / Randfälle → base', () {
      expect(
        smoothManeuverDistanceMeters(
            base: 750, cum: const [], render: 100, currentIndex: 0),
        750,
      );
    });
  });
}
