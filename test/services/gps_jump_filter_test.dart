import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-06-17 (vucko Geräte-Video): Das Banner feuerte grundlose „Neuberechnung"
/// und der Puck teleportierte, obwohl der Fahrer exakt auf der Linie fuhr. Wurzel:
/// physikalisch unmögliche GPS-Sprünge (Multipath) trieben Routen-Logik + Puck.
/// isImplausibleGpsJump filtert NUR das Unmögliche; echtes Verfahren (reales
/// Tempo) darf NIE gefiltert werden.
void main() {
  group('isImplausibleGpsJump', () {
    test('Stillstand-Jitter (25 m, dt 1 s) → KEIN Ausreißer', () {
      expect(
        isImplausibleGpsJump(
          jumpMeters: 25,
          dtSeconds: 1.0,
          plausibleSpeedMps: 0,
          accuracySlackMeters: 20,
        ),
        isFalse,
      );
    });

    test('Stillstand großer Sprung (70 m, dt 1 s) → Ausreißer', () {
      expect(
        isImplausibleGpsJump(
          jumpMeters: 70,
          dtSeconds: 1.0,
          plausibleSpeedMps: 0,
          accuracySlackMeters: 20,
        ),
        isTrue,
      );
    });

    test('Stadt 40 km/h, normaler Fix (26 m) → KEIN Ausreißer', () {
      expect(
        isImplausibleGpsJump(
          jumpMeters: 26,
          dtSeconds: 1.0,
          plausibleSpeedMps: 11,
          accuracySlackMeters: 20,
        ),
        isFalse,
      );
    });

    test('Stadt 40 km/h, Multipath-Sprung (90 m) → Ausreißer', () {
      expect(
        isImplausibleGpsJump(
          jumpMeters: 90,
          dtSeconds: 1.0,
          plausibleSpeedMps: 11,
          accuracySlackMeters: 20,
        ),
        isTrue,
      );
    });

    test('Autobahn 130 km/h, normaler Fix (36 m) → KEIN Ausreißer', () {
      expect(
        isImplausibleGpsJump(
          jumpMeters: 36,
          dtSeconds: 1.0,
          plausibleSpeedMps: 36,
          accuracySlackMeters: 10,
        ),
        isFalse,
      );
    });

    test('Autobahn 130 km/h, Teleport (200 m) → Ausreißer', () {
      expect(
        isImplausibleGpsJump(
          jumpMeters: 200,
          dtSeconds: 1.0,
          plausibleSpeedMps: 36,
          accuracySlackMeters: 10,
        ),
        isTrue,
      );
    });

    test('großer Teleport unabhängig vom Tempo (500 m) → Ausreißer', () {
      expect(
        isImplausibleGpsJump(
          jumpMeters: 500,
          dtSeconds: 1.0,
          plausibleSpeedMps: 11,
          accuracySlackMeters: 20,
        ),
        isTrue,
      );
    });

    test('lange GPS-Lücke (Tunnel, dt 6 s, 300 m) → akzeptieren', () {
      expect(
        isImplausibleGpsJump(
          jumpMeters: 300,
          dtSeconds: 6.0,
          plausibleSpeedMps: 11,
          accuracySlackMeters: 20,
        ),
        isFalse,
      );
    });

    test('erster/ungültiger Fix (dt <= 0) → akzeptieren', () {
      expect(
        isImplausibleGpsJump(
          jumpMeters: 200,
          dtSeconds: 0,
          plausibleSpeedMps: 11,
          accuracySlackMeters: 20,
        ),
        isFalse,
      );
    });

    test('hohe Accuracy-Unschärfe erklärt mittleren Sprung → kein Ausreißer', () {
      // 60 m Sprung bei großem accuracySlack (60 m) ist durch GPS-Unschärfe
      // erklärbar → nicht filtern (sonst Fehl-Filter bei schlechtem Himmel).
      expect(
        isImplausibleGpsJump(
          jumpMeters: 60,
          dtSeconds: 1.0,
          plausibleSpeedMps: 8,
          accuracySlackMeters: 60,
        ),
        isFalse,
      );
    });
  });
}
