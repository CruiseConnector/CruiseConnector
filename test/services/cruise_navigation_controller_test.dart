import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/geo_distance.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/presentation/controllers/cruise_navigation_controller.dart';

RouteManeuver _maneuver(int routeIndex, String instruction) {
  return RouteManeuver(
    latitude: 47.0,
    longitude: 9.0,
    routeIndex: routeIndex,
    icon: Icons.turn_right,
    announcement: instruction,
    instruction: instruction,
  );
}

void main() {
  group('CruiseNavigationController', () {
    const route = <List<double>>[
      [9.000, 47.000],
      [9.001, 47.000],
      [9.002, 47.000],
      [9.003, 47.000],
    ];

    test('selects the first maneuver at or ahead of current progress', () {
      final controller = CruiseNavigationController();
      final maneuvers = [_maneuver(1, 'rechts'), _maneuver(3, 'links')];

      expect(
        controller.activeManeuverIndexForProgress(
          maneuvers: maneuvers,
          currentRouteIndex: 2,
          fallbackIndex: 0,
        ),
        1,
      );
    });

    test(
      'calculates maneuver distance along Mapbox lng/lat route geometry',
      () {
        final controller = CruiseNavigationController();
        final maneuvers = [_maneuver(2, 'rechts')];
        final expected =
            GeoDistance.lngLatDistanceMeters(route[0], route[1]) +
            GeoDistance.lngLatDistanceMeters(route[1], route[2]);

        final distance = controller.calculateDistanceToManeuver(
          maneuvers: maneuvers,
          routeCoordinates: route,
          currentRouteIndex: 0,
          activeManeuverIndex: 0,
          remainingRouteDistanceMeters: 300,
          distanceToFinalTargetMeters: 300,
          arrivalRadiusMeters: 50,
          offRouteGapMeters: 0,
        );

        expect(distance, closeTo(expected, 0.1));
      },
    );

    test('keeps displayed distance monotonic within the same maneuver', () {
      final controller = CruiseNavigationController();
      final maneuvers = [_maneuver(2, 'rechts')];
      final firstAt = DateTime(2026, 1, 1, 12);

      final first = controller.displayManeuverDistanceMeters(
        maneuvers: maneuvers,
        routeCoordinates: route,
        currentRouteIndex: 1,
        activeManeuverIndex: 0,
        remainingRouteDistanceMeters: 200,
        distanceToFinalTargetMeters: 200,
        arrivalRadiusMeters: 50,
        offRouteGapMeters: 0,
        cumulativeDistancesMeters: null,
        renderLockDistanceMeters: -1,
        now: firstAt,
      );

      final wouldJumpUp = controller.displayManeuverDistanceMeters(
        maneuvers: maneuvers,
        routeCoordinates: route,
        currentRouteIndex: 0,
        activeManeuverIndex: 0,
        remainingRouteDistanceMeters: 300,
        distanceToFinalTargetMeters: 300,
        arrivalRadiusMeters: 50,
        offRouteGapMeters: 0,
        cumulativeDistancesMeters: null,
        renderLockDistanceMeters: -1,
        now: firstAt.add(const Duration(milliseconds: 120)),
      );

      expect(wouldJumpUp, first);
    });
  });
}
