import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_maneuver_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rendert das Kreisverkehr-Symbol als Golden-PNG, damit man die echte
/// Zirkulationsrichtung + Ausfahrts-Lage MIT DEM AUGE prüfen kann
/// (Rechtsverkehr = gegen Uhrzeigersinn, 1. Ausfahrt leicht rechts).
void main() {
  RouteManeuver roundabout({int exit = 1, double? turnAngle}) {
    return RouteManeuver(
      latitude: 47.4,
      longitude: 9.7,
      routeIndex: 5,
      icon: Icons.roundabout_right,
      announcement: 'Im Kreisverkehr Ausfahrt $exit nehmen.',
      instruction: 'Im Kreisverkehr Ausfahrt $exit nehmen.',
      maneuverType: ManeuverType.roundabout,
      roundaboutExitNumber: exit,
      roundaboutTurnAngleRad: turnAngle,
    );
  }

  // 2026-06-16 (vucko O9): echte OSM-Topologie. entry/exit/arms in Kompass-Grad.
  RouteManeuver topoRoundabout({
    required int exit,
    required double entry,
    required double exitB,
    required List<double> arms,
  }) {
    return RouteManeuver(
      latitude: 47.4,
      longitude: 9.7,
      routeIndex: 5,
      icon: Icons.roundabout_right,
      announcement: 'Im Kreisverkehr Ausfahrt $exit nehmen.',
      instruction: 'Im Kreisverkehr Ausfahrt $exit nehmen.',
      maneuverType: ManeuverType.roundabout,
      roundaboutExitNumber: exit,
      roundaboutEntryBearing: entry,
      roundaboutExitBearing: exitB,
      roundaboutArmBearings: arms,
    );
  }

  Widget harness(RouteManeuver m) => MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0b0e13),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CruiseManeuverIndicator(
                maneuver: m,
                distanceToManeuverMeters: 220,
              ),
            ),
          ),
        ),
      );

  testWidgets('Kreisverkehr Ausfahrt 1 (leicht rechts)', (tester) async {
    await tester.pumpWidget(harness(roundabout(exit: 1)));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CruiseManeuverIndicator),
      matchesGoldenFile('goldens/roundabout_exit1.png'),
    );
  });

  testWidgets('Kreisverkehr Ausfahrt 2 (geradeaus)', (tester) async {
    await tester.pumpWidget(harness(roundabout(exit: 2)));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CruiseManeuverIndicator),
      matchesGoldenFile('goldens/roundabout_exit2.png'),
    );
  });

  testWidgets('Kreisverkehr Ausfahrt 3 (links)', (tester) async {
    await tester.pumpWidget(harness(roundabout(exit: 3)));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CruiseManeuverIndicator),
      matchesGoldenFile('goldens/roundabout_exit3.png'),
    );
  });

  testWidgets('Kreisverkehr echter GH turn_angle (leicht rechts raus)',
      (tester) async {
    await tester.pumpWidget(harness(roundabout(exit: 2, turnAngle: -0.6)));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CruiseManeuverIndicator),
      matchesGoldenFile('goldens/roundabout_turnangle.png'),
    );
  });

  // 2026-06-13 (vucko): Kreisverkehre mit vielen Ausfahrten (5–8) müssen
  // symbolisch abgebildet werden — Ausfahrt-Nummer korrekt, keine Deko-Ausfahrt
  // auf der Einfahrt.
  for (final exit in [5, 6, 7, 8]) {
    testWidgets('Kreisverkehr Ausfahrt $exit (viele Ausfahrten)',
        (tester) async {
      await tester.pumpWidget(harness(roundabout(exit: exit)));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(CruiseManeuverIndicator),
        matchesGoldenFile('goldens/roundabout_exit$exit.png'),
      );
    });
  }

  // ── ECHTE OSM-TOPOLOGIE (vucko O9) ──────────────────────────────────────
  // Einfahrt aus Süden (entry 180°). Rechtsverkehr/CCW: 1. Ausfahrt = Ost (90°,
  // rechts), 2. = Nord (0°, geradeaus), 3. = West (270°, links). Das Symbol muss
  // ALLE realen Arme an ihren echten Winkeln zeigen + die genommene hervorheben.
  testWidgets('Topo 4-armig — 1. Ausfahrt rechts', (tester) async {
    await tester.pumpWidget(harness(topoRoundabout(
      exit: 1,
      entry: 180,
      exitB: 90,
      arms: [0, 90, 180, 270],
    )));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CruiseManeuverIndicator),
      matchesGoldenFile('goldens/roundabout_topo4_exit1.png'),
    );
  });

  testWidgets('Topo 4-armig — 2. Ausfahrt geradeaus', (tester) async {
    await tester.pumpWidget(harness(topoRoundabout(
      exit: 2,
      entry: 180,
      exitB: 0,
      arms: [0, 90, 180, 270],
    )));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CruiseManeuverIndicator),
      matchesGoldenFile('goldens/roundabout_topo4_exit2.png'),
    );
  });

  testWidgets('Topo 4-armig — 3. Ausfahrt links', (tester) async {
    await tester.pumpWidget(harness(topoRoundabout(
      exit: 3,
      entry: 180,
      exitB: 270,
      arms: [0, 90, 180, 270],
    )));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CruiseManeuverIndicator),
      matchesGoldenFile('goldens/roundabout_topo4_exit3.png'),
    );
  });

  // 3-armiger Y-Kreisel (asymmetrisch): Einfahrt Süd, Arme Süd/NO/NW.
  testWidgets('Topo 3-armig Y — Ausfahrt NO', (tester) async {
    await tester.pumpWidget(harness(topoRoundabout(
      exit: 1,
      entry: 180,
      exitB: 55,
      arms: [180, 55, 305],
    )));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CruiseManeuverIndicator),
      matchesGoldenFile('goldens/roundabout_topo3_y.png'),
    );
  });

  // 5-armiger asymmetrischer Kreisel.
  testWidgets('Topo 5-armig asymmetrisch', (tester) async {
    await tester.pumpWidget(harness(topoRoundabout(
      exit: 2,
      entry: 200,
      exitB: 20,
      arms: [200, 20, 80, 140, 300],
    )));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CruiseManeuverIndicator),
      matchesGoldenFile('goldens/roundabout_topo5.png'),
    );
  });
}
