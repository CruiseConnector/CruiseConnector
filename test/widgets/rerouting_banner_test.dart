import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_maneuver_indicator.dart';

void main() {
  RouteManeuver maneuver() => const RouteManeuver(
    latitude: 47.4125,
    longitude: 9.7414,
    routeIndex: 10,
    icon: Icons.turn_right,
    announcement: 'Rechts abbiegen.',
    instruction: 'Rechts abbiegen.',
  );

  Widget harness(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('Reroute-Banner zeigt nach Wartezeit sicheren Fallback-Hinweis', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        CruiseManeuverIndicator(
          maneuver: maneuver(),
          isRerouting: true,
          reroutingDuration: const Duration(seconds: 7),
        ),
      ),
    );

    expect(find.text('Neuberechnung'), findsOneWidget);
    expect(
      find.text('Suche läuft weiter — Route bleibt sichtbar'),
      findsOneWidget,
    );
    expect(find.text('Rechts abbiegen.'), findsNothing);
  });

  // 2026-06-23 (vucko 2-Geräte-Gruppen-Video, C1): Ein nicht-führender Follower,
  // der nur auf die Leader-Route wartet, sieht das ruhige „Folge der Gruppe"
  // statt des alarmierenden, oszillierenden „Neuberechnung".
  testWidgets('Follower-Banner zeigt „Folge der Gruppe" statt „Neuberechnung"', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        CruiseManeuverIndicator(
          maneuver: maneuver(),
          isRerouting: true,
          reroutingDuration: const Duration(seconds: 2),
          groupFollowerWaiting: true,
        ),
      ),
    );

    expect(find.text('Folge der Gruppe'), findsOneWidget);
    expect(find.text('Neue Route der Gruppe kommt gleich'), findsOneWidget);
    expect(find.text('Neuberechnung'), findsNothing);
    expect(find.text('Rechts abbiegen.'), findsNothing);
  });

  // Gegenprobe: ohne Follower-Flag bleibt der Standard-„Neuberechnung"-Status
  // byte-gleich (kein Regress am Solo-/Leader-Pfad).
  testWidgets('Standard-Reroute-Banner bleibt „Neuberechnung" ohne Follower-Flag', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        CruiseManeuverIndicator(
          maneuver: maneuver(),
          isRerouting: true,
          reroutingDuration: const Duration(seconds: 2),
        ),
      ),
    );

    expect(find.text('Neuberechnung'), findsOneWidget);
    expect(
      find.text('Route wird angepasst — bitte weiterfahren'),
      findsOneWidget,
    );
    expect(find.text('Folge der Gruppe'), findsNothing);
  });
}
