import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-06-15 (vucko N-Runde-2, Geräte-Video: 3 Phantom-Reroutes MITTEN in der
/// Fahrt bei dead-on Puck): die klar definierte Mapbox-Regel — Zähler
/// aufeinanderfolgender Off-Route-Fixes, den JEDER „auf-Route"-Fix auf 0 setzt.
void main() {
  const corridor = 300.0; // A→B Korridor

  group('fixIsOnRoute — die On-Route-Regel', () {
    bool onRoute({
      required bool outside,
      required double perp,
      required bool aligned,
      bool fwd = false,
      bool approach = false,
      bool nearEnd = false,
    }) =>
        fixIsOnRoute(
          isOutsideCorridor: outside,
          perpMeters: perp,
          corridorMeters: corridor,
          courseAligned: aligned,
          makingForwardProgress: fwd,
          approachingDestination: approach,
          nearRouteEnd: nearEnd,
        );

    test('im Korridor → auf Route', () {
      expect(onRoute(outside: false, perp: 5, aligned: false), isTrue);
    });
    test('etwas weiter aber Kurs passt (≤2× Korridor) → auf Route', () {
      expect(onRoute(outside: true, perp: 450, aligned: true), isTrue);
    });
    test('weiter + Kurs misaligned → off', () {
      expect(onRoute(outside: true, perp: 450, aligned: false), isFalse);
    });
    test('SEHR weit (>2× Korridor) auch bei passendem Kurs → off (Parallelstraße)',
        () {
      expect(onRoute(outside: true, perp: 700, aligned: true), isFalse);
    });
    test('Fortschritt / Ziel-Annäherung / Routen-Ende → auf Route', () {
      expect(onRoute(outside: true, perp: 700, aligned: false, fwd: true), isTrue);
      expect(onRoute(outside: true, perp: 700, aligned: false, approach: true),
          isTrue);
      expect(onRoute(outside: true, perp: 700, aligned: false, nearEnd: true),
          isTrue);
    });
  });

  group('requiredOffRouteFixes — accuracy-skaliert, nie hart blockiert', () {
    test('gutes GPS (10m) → 4 Fixes', () {
      expect(
          requiredOffRouteFixes(accuracyMeters: 10, clearWrongTurn: false), 4);
    });
    test('gutes GPS + eindeutiges Verfahren → 3 Fixes (Schnell-Schiene)', () {
      expect(requiredOffRouteFixes(accuracyMeters: 10, clearWrongTurn: true), 3);
    });
    test('mäßiges GPS (60m) → 15 Fixes (träger, aber nicht blockiert)', () {
      expect(
          requiredOffRouteFixes(accuracyMeters: 60, clearWrongTurn: false), 15);
    });
    test('mäßiges GPS + eindeutiges Verfahren → trotzdem 3 (min)', () {
      expect(requiredOffRouteFixes(accuracyMeters: 60, clearWrongTurn: true), 3);
    });
    test('ungültige Accuracy → 4 (16/4 Default)', () {
      expect(
          requiredOffRouteFixes(accuracyMeters: -1, clearWrongTurn: false), 4);
    });
  });

  // ── Zähler-Simulation: genau das Verhalten aus dem GPS-Handler nachgebildet ──
  // (on → reset 0; off & usable → +1; deklariert bei counter >= required)
  ({int counter, bool declared}) runFixes(
    List<({double perp, bool aligned, double acc, bool clearTurn})> fixes,
  ) {
    var counter = 0;
    var declared = false;
    for (final f in fixes) {
      final outside = f.perp > corridor;
      final on = fixIsOnRoute(
        isOutsideCorridor: outside,
        perpMeters: f.perp,
        corridorMeters: corridor,
        courseAligned: f.aligned,
        makingForwardProgress: false,
        approachingDestination: false,
        nearRouteEnd: false,
      );
      final usable = f.acc > 0 && f.acc <= 100;
      if (on) {
        counter = 0;
      } else if (usable) {
        counter++;
      }
      final req =
          requiredOffRouteFixes(accuracyMeters: f.acc, clearWrongTurn: f.clearTurn);
      if (counter >= req) declared = true;
    }
    return (counter: counter, declared: declared);
  }

  group('Zähler-Regel: Phantom unmöglich, echtes Verfahren feuert', () {
    test('PHANTOM: 3-Fix-Multipath-Burst (dann on-route) feuert NIE', () {
      // genau der Geräte-Fall: kurzer seitlicher Ausreißer an Kurve/Auffahrt
      final r = runFixes([
        (perp: 5, aligned: true, acc: 12, clearTurn: false), // on
        (perp: 400, aligned: false, acc: 12, clearTurn: false), // off 1
        (perp: 420, aligned: false, acc: 12, clearTurn: false), // off 2
        (perp: 410, aligned: false, acc: 12, clearTurn: false), // off 3
        (perp: 8, aligned: true, acc: 12, clearTurn: false), // on → reset!
      ]);
      expect(r.declared, isFalse, reason: 'Burst <4 + Reset → kein Reroute');
      expect(r.counter, 0);
    });

    test('PHANTOM: EIN in-Korridor-Blip mitten im langen Burst nullt alles', () {
      final fixes = <({double perp, bool aligned, double acc, bool clearTurn})>[];
      // 3 off, dann 1 on (Blip), dann wieder 3 off — nie 4 am Stück
      for (var i = 0; i < 3; i++) {
        fixes.add((perp: 450, aligned: false, acc: 12, clearTurn: false));
      }
      fixes.add((perp: 10, aligned: true, acc: 12, clearTurn: false)); // Blip on
      for (var i = 0; i < 3; i++) {
        fixes.add((perp: 450, aligned: false, acc: 12, clearTurn: false));
      }
      final r = runFixes(fixes);
      expect(r.declared, isFalse,
          reason: 'der On-Blip setzt den Zähler zurück → nie ≥4 am Stück');
    });

    test('ECHTES VERFAHREN: 4 durchgehende off-Fixes (gutes GPS) → feuert', () {
      final r = runFixes([
        for (var i = 0; i < 4; i++)
          (perp: 500, aligned: false, acc: 12, clearTurn: false),
      ]);
      expect(r.declared, isTrue, reason: '4 Fixes ≈ 4s = echtes Verfahren');
    });

    test('ECHTES VERFAHREN eindeutig (Overshoot): 3 Fixes reichen (~3s)', () {
      final r = runFixes([
        for (var i = 0; i < 3; i++)
          (perp: 500, aligned: false, acc: 12, clearTurn: true),
      ]);
      expect(r.declared, isTrue, reason: 'Schnell-Schiene 3 Fixes');
    });

    test('PARALLELSTRASSE: weit weg aber Kurs passt → feuert ab >2× Korridor',
        () {
      final r = runFixes([
        for (var i = 0; i < 4; i++)
          (perp: 700, aligned: true, acc: 12, clearTurn: false), // aligned!
      ]);
      expect(r.declared, isTrue,
          reason: '>2× Korridor zählt als off trotz passendem Kurs');
    });
  });
}
