import 'dart:math' as math;

import 'package:cruise_connect/data/services/route_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-06-14 (vucko L3): Verifiziert die GEOMETRIE-basierte Kreisverkehr-
/// Richtung (Bodenwahrheit statt GraphHoppers mehrdeutigem `turn_angle`).
/// Beweist die Vorzeichen-Konvention: RECHTS = positiv, LINKS = negativ —
/// genau das, was die Painter-Formel (−pi/2 + angle) und der Exit-1-
/// Plausibilitaets-Guard erwarten. Geraete-Screenshot-Fall: Einfahrt aus
/// Sueden, Ausfahrt nach Nordwest (= klar links) wurde von GH faelschlich als
/// „1. Ausfahrt" gemeldet — die 1. Ausfahrt MUSS in Rechtsverkehr rechts sein.
void main() {
  const baseLat = 47.18;
  const baseLng = 9.65;
  final mPerDegLng = 111320.0 * math.cos(baseLat * math.pi / 180.0);

  // Punkt aus Ost-/Nord-Versatz in Metern → [lng, lat].
  List<double> pt(double eastM, double northM) => [
    baseLng + eastM / mPerDegLng,
    baseLat + northM / 110540.0,
  ];

  // Anfahrt aus Sueden (Kurs Nord, bearing 0) bis zur Einfahrt (Index 3),
  // kurzer Kreis-Bogen, dann das Ausfahrts-Bein in [exitDx,exitDy]-Richtung.
  List<List<double>> roundaboutRoute({
    required double exitEastStep,
    required double exitNorthStep,
  }) {
    return <List<double>>[
      pt(0, -30), // 0
      pt(0, -20), // 1
      pt(0, -10), // 2
      pt(0, 0), //   3 = Einfahrt (entryIdx)
      pt(4, 6), //   4 Bogen
      pt(0, 10), //  5 = Austritt (exitIdx)
      pt(exitEastStep, 10 + exitNorthStep), //       6 Ausfahrt-Bein
      pt(2 * exitEastStep, 10 + 2 * exitNorthStep), // 7
      pt(3 * exitEastStep, 10 + 3 * exitNorthStep), // 8
    ];
  }

  test('exit to the EAST (true 1st exit) → clearly positive (right)', () {
    final route = roundaboutRoute(exitEastStep: 12, exitNorthStep: 1);
    final turn = roundaboutGeomTurnRad(route, 3, 5);
    expect(turn, isNotNull);
    expect(
      turn!,
      greaterThan(0.5),
      reason: 'Rechts-Ausfahrt muss positiven Drehwinkel liefern',
    );
  });

  test('exit to the NORTH-WEST (left) → clearly negative — screenshot case', () {
    // Genau der Geraete-Fall: GH sagte „Ausfahrt 1", die echte Geometrie zeigt
    // aber eine Linkskurve → Exit-1-Guard greift, keine falsche Nummer.
    final route = roundaboutRoute(exitEastStep: -12, exitNorthStep: 12);
    final turn = roundaboutGeomTurnRad(route, 3, 5);
    expect(turn, isNotNull);
    expect(
      turn!,
      lessThan(-0.35),
      reason: 'NW-Ausfahrt ist links → negativ → nicht die 1. Ausfahrt',
    );
  });

  test(
    'arm-bearing geometry keeps left exit negative on sparse support points',
    () {
      final route = <List<double>>[
        pt(0, -80),
        pt(0, -35),
        pt(0, 0), // entry
        pt(-8, 8),
        pt(-35, 14), // exit
        pt(-80, 14),
      ];

      final turn = roundaboutTurnRadFromRouteArmBearings(route, 2, 4);
      expect(turn, isNotNull);
      expect(turn!, lessThan(-0.7));
      expect(roundaboutExitNumberFromGeometryRad(turn), 3);
    },
  );

  test('straight through (2nd exit) → near zero', () {
    final route = roundaboutRoute(exitEastStep: 0, exitNorthStep: 12);
    final turn = roundaboutGeomTurnRad(route, 3, 5);
    expect(turn, isNotNull);
    expect(
      turn!.abs(),
      lessThan(0.3),
      reason: 'Geradeaus durch → Drehwinkel ~0',
    );
  });

  test('too few support points → null (falls back to GH turn_angle)', () {
    final tiny = <List<double>>[pt(0, 0), pt(0, 10)];
    expect(roundaboutGeomTurnRad(tiny, 0, 1), isNull);
    // Gueltige Route, aber entry/exit am Rand ohne Stuetzpunkte davor/danach.
    final route = roundaboutRoute(exitEastStep: 12, exitNorthStep: 1);
    expect(roundaboutGeomTurnRad(route, 0, route.length - 1), isNull);
  });
}
