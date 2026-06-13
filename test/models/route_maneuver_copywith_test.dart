import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-06-13 (vucko J3): Beweist, dass der Start-Snap (der copyWith nutzt) die
/// Kreisverkehr-Felder NICHT mehr verliert. Genau dieses Strippen ließ das
/// Banner das alte Material-Icon statt des _RoundaboutPainter zeigen.
void main() {
  test('copyWith erhält alle Kreisverkehr-Felder, ändert nur routeIndex', () {
    const m = RouteManeuver(
      latitude: 47.4,
      longitude: 9.7,
      routeIndex: 5,
      icon: Icons.roundabout_right,
      announcement: 'Im Kreisverkehr Ausfahrt 2 nehmen.',
      instruction: 'Im Kreisverkehr Ausfahrt 2 nehmen.',
      maneuverType: ManeuverType.roundabout,
      roundaboutExitNumber: 2,
      roundaboutTurnAngleRad: 0.6,
    );

    final snapped = m.copyWith(routeIndex: 42);

    expect(snapped.routeIndex, 42, reason: 'routeIndex wird neu gesetzt');
    expect(snapped.maneuverType, ManeuverType.roundabout);
    expect(snapped.roundaboutExitNumber, 2);
    expect(snapped.roundaboutTurnAngleRad, 0.6);
    expect(snapped.icon, Icons.roundabout_right);
    expect(snapped.latitude, 47.4);
    expect(snapped.longitude, 9.7);
    expect(snapped.instruction, 'Im Kreisverkehr Ausfahrt 2 nehmen.');
  });

  test('copyWith ohne Args ist identische Kopie', () {
    const m = RouteManeuver(
      latitude: 1,
      longitude: 2,
      routeIndex: 3,
      icon: Icons.turn_right,
      announcement: 'a',
      instruction: 'i',
    );
    final c = m.copyWith();
    expect(c.maneuverType, ManeuverType.normal);
    expect(c.roundaboutExitNumber, isNull);
    expect(c.roundaboutTurnAngleRad, isNull);
    expect(c.routeIndex, 3);
  });
}
