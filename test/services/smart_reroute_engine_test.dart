import 'package:cruise_connect/data/services/smart_reroute_engine.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;

void main() {
  const engine = SmartRerouteEngine();

  geo.Position position({
    required double latitude,
    required double longitude,
    double heading = 90,
  }) {
    return geo.Position(
      longitude: longitude,
      latitude: latitude,
      timestamp: DateTime.now(),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: heading,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  List<List<double>> buildStraightRoute({int count = 240}) {
    return List.generate(count, (i) => [11.0 + i * 0.0001, 48.0]);
  }

  group('SmartRerouteEngine', () {
    test('Autobahn-Fall waehlt die naechste Ausfahrt', () {
      final coordinates = buildStraightRoute();
      final maneuvers = <RouteManeuver>[
        RouteManeuver(
          latitude: 48.0020,
          longitude: 11.0040,
          routeIndex: 40,
          icon: Icons.directions_car,
          announcement: 'In 800 Metern die Ausfahrt nehmen',
          instruction: 'Nehmen Sie die Ausfahrt Richtung Zentrum',
        ),
      ];

      final plan = engine.createPlan(
        currentPosition: position(latitude: 48.0, longitude: 11.0),
        coordinates: coordinates,
        maneuvers: maneuvers,
        nearestIndex: 8,
        currentHeadingDegrees: 90,
        speedLimits: const [
          SpeedLimitSegment(startIndex: 0, endIndex: 80, speedKmh: 120),
        ],
      );

      expect(plan.strategy, SmartRerouteStrategy.motorwayExit);
      expect(plan.debugLabel, 'next_motorway_exit');
      expect(plan.rejoinIndex, 40);
      expect(plan.anchorCoordinate, [11.0040, 48.0020]);
    });

    test('Kreisverkehr im Nahbereich waehlt roundabout-Strategie', () {
      final coordinates = buildStraightRoute();
      final maneuvers = <RouteManeuver>[
        RouteManeuver(
          latitude: 48.0014,
          longitude: 11.0014,
          routeIndex: 20,
          icon: Icons.roundabout_left,
          announcement: 'Am Kreisverkehr zweite Ausfahrt nehmen',
          instruction: 'Am Kreisverkehr die zweite Ausfahrt nehmen',
          maneuverType: ManeuverType.roundabout,
          roundaboutExitNumber: 2,
        ),
      ];

      final plan = engine.createPlan(
        currentPosition: position(latitude: 48.0, longitude: 11.0),
        coordinates: coordinates,
        maneuvers: maneuvers,
        nearestIndex: 0,
        currentHeadingDegrees: 90,
        speedLimits: const [
          SpeedLimitSegment(startIndex: 0, endIndex: 80, speedKmh: 50),
        ],
      );

      expect(plan.strategy, SmartRerouteStrategy.roundabout);
      expect(plan.debugLabel, 'nearby_roundabout');
      expect(plan.rejoinIndex, 20);
      expect(plan.anchorCoordinate, [11.0014, 48.0014]);
    });

    test('sonst wird ein sinnvoller Vorwaerts-Join gewaehlt', () {
      final coordinates = buildStraightRoute();
      final maneuvers = <RouteManeuver>[
        RouteManeuver(
          latitude: 48.0008,
          longitude: 11.0032,
          routeIndex: 36,
          icon: Icons.turn_right,
          announcement: 'Rechts abbiegen',
          instruction: 'Rechts abbiegen auf die Hauptstrasse',
        ),
      ];

      final plan = engine.createPlan(
        currentPosition: position(latitude: 48.0, longitude: 11.0),
        coordinates: coordinates,
        maneuvers: maneuvers,
        nearestIndex: 2,
        currentHeadingDegrees: 90,
        speedLimits: const [
          SpeedLimitSegment(startIndex: 0, endIndex: 80, speedKmh: 50),
        ],
      );

      expect(plan.strategy, SmartRerouteStrategy.forwardTurn);
      expect(plan.debugLabel, 'forward_turn_point');
      expect(plan.rejoinIndex, 36);
      expect(plan.anchorCoordinate, [11.0032, 48.0008]);
    });
  });
}
