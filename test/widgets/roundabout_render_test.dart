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
    await tester.pumpWidget(harness(roundabout(exit: 2, turnAngle: 0.6)));
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
}
