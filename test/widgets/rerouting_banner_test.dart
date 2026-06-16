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
}
