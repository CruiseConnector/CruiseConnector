import 'dart:math' as math;

import 'package:cruise_connect/data/services/route_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-06-17 (vucko Geräte-Video): Das Banner sagte „Rechts abbiegen auf Churer
/// Straße", die rote Route bog aber klar nach LINKS. Da das sign→Icon/Text-Mapping
/// korrekt ist, kam ein widersprüchlicher `sign` von GraphHopper an. Schutz:
/// Richtung aus der ECHTEN Geometrie ableiten und bei Konflikt der Geometrie
/// vertrauen (der Fahrer navigiert nach der sichtbaren Linie).
void main() {
  // Route: erst 2 Punkte Richtung Norden, dann Abbiegung am Punkt index 2.
  List<List<double>> routeTurning({required bool left}) {
    // [lng, lat]
    final ns = <List<double>>[
      [10.000, 47.000],
      [10.000, 47.001],
      [10.000, 47.002], // index 2 = Manöverpunkt
    ];
    final after = left
        ? <List<double>>[
            [9.999, 47.002],
            [9.998, 47.002],
            [9.997, 47.002], // weiter nach Westen = LINKS
          ]
        : <List<double>>[
            [10.001, 47.002],
            [10.002, 47.002],
            [10.003, 47.002], // weiter nach Osten = RECHTS
          ];
    return [...ns, ...after];
  }

  group('maneuverSignFromGeometryRad', () {
    test('+90° (rechts) → sign 2', () {
      expect(maneuverSignFromGeometryRad(90 * math.pi / 180), 2);
    });
    test('-90° (links) → sign -2', () {
      expect(maneuverSignFromGeometryRad(-90 * math.pi / 180), -2);
    });
    test('+130° (scharf rechts) → sign 3', () {
      expect(maneuverSignFromGeometryRad(130 * math.pi / 180), 3);
    });
    test('-130° (scharf links) → sign -3', () {
      expect(maneuverSignFromGeometryRad(-130 * math.pi / 180), -3);
    });
    test('leichte Kurve (15°) → null (uneindeutig, GH behalten)', () {
      expect(maneuverSignFromGeometryRad(15 * math.pi / 180), isNull);
      expect(maneuverSignFromGeometryRad(-15 * math.pi / 180), isNull);
    });
    test('null → null', () => expect(maneuverSignFromGeometryRad(null), isNull));
  });

  group('turnSignsContradict', () {
    test('GH rechts (2) vs Geometrie links (-2) → Konflikt', () {
      expect(turnSignsContradict(2, -2), isTrue);
    });
    test('GH links (-2) vs Geometrie rechts (2) → Konflikt', () {
      expect(turnSignsContradict(-2, 2), isTrue);
    });
    test('beide rechts → kein Konflikt', () {
      expect(turnSignsContradict(2, 3), isFalse);
    });
    test('beide links → kein Konflikt', () {
      expect(turnSignsContradict(-2, -3), isFalse);
    });
    test('geradeaus/Ziel/Via/Kreisverkehr (0,4,5,6) → nie Konflikt', () {
      for (final s in [0, 4, 5, 6]) {
        expect(turnSignsContradict(s, -2), isFalse, reason: 'gh=$s');
        expect(turnSignsContradict(2, s), isFalse, reason: 'geom=$s');
      }
    });
  });

  group('Geometrie → Sign End-to-End (der Video-Fall)', () {
    test('Route biegt LINKS → Geometrie-sign -2 (nicht rechts)', () {
      final coords = routeTurning(left: true);
      final turn = roundaboutGeomTurnRad(coords, 2, 2);
      expect(turn, isNotNull);
      expect(turn! < 0, isTrue, reason: 'links = negativer Drehwinkel');
      expect(maneuverSignFromGeometryRad(turn), -2);
      // GH sagte fälschlich rechts (2) → Konflikt erkannt → Geometrie gewinnt.
      expect(turnSignsContradict(2, maneuverSignFromGeometryRad(turn)!), isTrue);
    });
    test('Route biegt RECHTS → Geometrie-sign 2', () {
      final coords = routeTurning(left: false);
      final turn = roundaboutGeomTurnRad(coords, 2, 2);
      expect(turn, isNotNull);
      expect(turn! > 0, isTrue, reason: 'rechts = positiver Drehwinkel');
      expect(maneuverSignFromGeometryRad(turn), 2);
    });
  });
}
