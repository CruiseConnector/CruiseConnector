import 'package:cruise_connect/presentation/widgets/cruise/nav_distance_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-06-13 (vucko J2): Google-Maps-Style Distanz-Stufen. Der User will
/// saubere Zahlen (690, 680, 670) statt „krummer" wie 522 m.
void main() {
  group('formatNavDistance', () {
    test('null → --', () => expect(formatNavDistance(null), '--'));

    test('< 1 km auf Google-ähnliche Stufen gerundet', () {
      // Aktueller Takt: 500-999 m in 50er-Stufen, 201-500 m in 20er-Stufen,
      // darunter 10er-Stufen.
      expect(formatNavDistance(522), '500 m');
      expect(formatNavDistance(694), '700 m');
      expect(formatNavDistance(685), '700 m');
      expect(formatNavDistance(483), '480 m');
      expect(formatNavDistance(177), '180 m');
      expect(formatNavDistance(171), '170 m');
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

  group('formatSpokenNavDistanceMeters', () {
    test('kurze Ansagedistanzen werden nicht auf 200 m hochgezogen', () {
      expect(formatSpokenNavDistanceMeters(70), 70);
      expect(formatSpokenNavDistanceMeters(177), 180);
      expect(formatSpokenNavDistanceMeters(240), 240);
    });

    test('nutzt dieselbe saubere Stufung wie der Banner', () {
      expect(formatSpokenNavDistanceMeters(287), 280);
      expect(formatSpokenNavDistanceMeters(522), 500);
      expect(formatSpokenNavDistanceMeters(-20), 0);
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
          base: 1000,
          cum: [0, 1500, 3000],
          render: 400,
          currentIndex: 0,
        ),
        600,
      );
      // weiter gefahren (700 m Vorlauf) → 300, NICHT 1000.
      expect(
        smoothManeuverDistanceMeters(
          base: 1000,
          cum: [0, 1500, 3000],
          render: 700,
          currentIndex: 0,
        ),
        300,
      );
    });

    test('Stadt: kleiner Vorlauf (<80 m) wie bisher abgezogen', () {
      expect(
        smoothManeuverDistanceMeters(
          base: 200,
          cum: [0, 100, 200],
          render: 50,
          currentIndex: 0,
        ),
        150,
      );
    });

    test('stale (render hinter dem Index) → ehrlicher Index-Wert', () {
      expect(
        smoothManeuverDistanceMeters(
          base: 500,
          cum: [0, 1000],
          render: 900,
          currentIndex: 1,
        ),
        500,
      );
    });

    test('render nicht initialisiert (<0) → base', () {
      expect(
        smoothManeuverDistanceMeters(
          base: 500,
          cum: [0, 1000],
          render: -1,
          currentIndex: 0,
        ),
        500,
      );
    });

    test('Puck am/über Manöver → 0 (Jetzt), nicht negativ', () {
      expect(
        smoothManeuverDistanceMeters(
          base: 300,
          cum: [0, 1000],
          render: 320,
          currentIndex: 0,
        ),
        0,
      );
    });

    test(
      'grober Render-Sprung (weit hinters Manöver) → base (kein Unsinn)',
      () {
        expect(
          smoothManeuverDistanceMeters(
            base: 300,
            cum: [0, 1000],
            render: 900,
            currentIndex: 0,
          ),
          300,
        );
      },
    );

    test('leere cum / Randfälle → base', () {
      expect(
        smoothManeuverDistanceMeters(
          base: 750,
          cum: const [],
          render: 100,
          currentIndex: 0,
        ),
        750,
      );
    });
  });

  // 2026-06-17 (vucko Geräte-Video): Manöver-Distanz fror an Kreisverkehren ein
  // und sprang am Routenende/Reroute nach OBEN („10 m → 40 m"). monoton +
  // sprung-frei anzeigen.
  group('monotonicManeuverDistanceMeters', () {
    test('erster Wert (prevShown null) → Ziel', () {
      expect(
        monotonicManeuverDistanceMeters(
          prevShown: null,
          target: 120,
          maneuverChanged: false,
        ),
        120,
      );
    });

    test('neues Manöver → snap auf neuen (größeren) Wert', () {
      expect(
        monotonicManeuverDistanceMeters(
          prevShown: 50,
          target: 110,
          maneuverChanged: true,
        ),
        110,
      );
    });

    test('SPRUNG NACH OBEN im selben Manöver → halten (der Video-Bug)', () {
      // „10 m → 40 m" am Routenende, gleiches Manöver: NICHT hochspringen.
      expect(
        monotonicManeuverDistanceMeters(
          prevShown: 10,
          target: 40,
          maneuverChanged: false,
        ),
        10,
      );
      // „50 m → 110 m" Walserstraße, gleiches Manöver: halten.
      expect(
        monotonicManeuverDistanceMeters(
          prevShown: 50,
          target: 110,
          maneuverChanged: false,
        ),
        50,
      );
    });

    test('grobe Stufe nach unten → weich gleiten (1 Schritt)', () {
      // 800 → 700, dtMs 90, ease 0.35 → 765 (Zwischenwert, nicht hart 700).
      expect(
        monotonicManeuverDistanceMeters(
          prevShown: 800,
          target: 700,
          maneuverChanged: false,
          dtMs: 90,
        ),
        closeTo(765, 0.5),
      );
    });

    test('mehrere Schritte konvergieren zum Ziel', () {
      var shown = 800.0;
      for (var i = 0; i < 30; i++) {
        shown = monotonicManeuverDistanceMeters(
          prevShown: shown,
          target: 700,
          maneuverChanged: false,
          dtMs: 90,
        );
      }
      expect(shown, closeTo(700, 1.0));
    });

    test('praktisch erreicht (≤ Epsilon) → snap aufs Ziel', () {
      expect(
        monotonicManeuverDistanceMeters(
          prevShown: 700,
          target: 699,
          maneuverChanged: false,
        ),
        699,
      );
    });

    test('gleitet nie UNTER das Ziel', () {
      final v = monotonicManeuverDistanceMeters(
        prevShown: 100,
        target: 90,
        maneuverChanged: false,
        dtMs: 5000,
      );
      expect(v >= 90, isTrue);
    });

    test('negatives/ungültiges Ziel → 0', () {
      expect(
        monotonicManeuverDistanceMeters(
          prevShown: null,
          target: -5,
          maneuverChanged: false,
        ),
        0,
      );
    });
  });
}
