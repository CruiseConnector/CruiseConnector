import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/route_access_plan.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RouteService.resetForTests();
  });

  group('RouteAccessPlanner', () {
    test('bevorzugt einen fruehen, gut fahrbaren Einstiegspunkt', () {
      final route = _buildLoopRoute();
      const planner = RouteAccessPlanner();

      final joinPoint = planner.chooseJoinPoint(
        currentPosition: _position(latitude: 47.29, longitude: 9.58),
        existingRoute: route,
      );

      expect(joinPoint.progressRatio, lessThanOrEqualTo(0.45));
      expect(joinPoint.index, lessThan(route.coordinates.length ~/ 2));
      expect(joinPoint.remainingDistanceMeters, greaterThan(1500));
    });

    test('nutzt bevorzugten Join-Index exakt fuer Access-Reroutes', () {
      final route = _buildLoopRoute();
      const planner = RouteAccessPlanner();

      final joinPoint = planner.chooseJoinPoint(
        currentPosition: _position(latitude: 47.29, longitude: 9.58),
        existingRoute: route,
        preferredJoinIndex: 14,
      );

      expect(joinPoint.index, 14);
    });
  });

  group('RouteService.buildAccessRouteToExistingRoute', () {
    test(
      'baut Access-Leg und behaelt den logischen Endpunkt der Route',
      () async {
        final invoker = _AccessInvoker();
        final service = RouteService(invoker: invoker);
        final existingRoute = _buildLoopRoute();

        final plan = await service.buildAccessRouteToExistingRoute(
          currentPosition: _position(latitude: 47.312, longitude: 9.611),
          existingRoute: existingRoute,
        );

        expect(plan.hasAccessLeg, isTrue);
        expect(invoker.callCount, 1);
        expect(plan.joinPoint.progressRatio, lessThanOrEqualTo(0.45));
        expect(
          plan.logicalOrigin,
          orderedEquals(existingRoute.coordinates.first),
        );
        expect(plan.logicalEnd, orderedEquals(existingRoute.coordinates.last));
        expect(
          plan.activeRoute.coordinates.last,
          orderedEquals(plan.followOnRoute.coordinates.last),
        );
        expect(
          plan.activeRoute.distanceMeters!,
          greaterThan(plan.followOnRoute.distanceMeters!),
        );
      },
    );

    test(
      'verzichtet auf Access-Leg wenn der Nutzer bereits am Routeneinstieg ist',
      () async {
        final invoker = _AccessInvoker();
        final service = RouteService(invoker: invoker);
        final existingRoute = _buildLoopRoute();
        final start = existingRoute.coordinates.first;

        final plan = await service.buildAccessRouteToExistingRoute(
          currentPosition: _position(latitude: start[1], longitude: start[0]),
          existingRoute: existingRoute,
        );

        expect(plan.hasAccessLeg, isFalse);
        expect(invoker.callCount, 0);
        expect(
          plan.activeRoute.coordinates,
          orderedEquals(plan.followOnRoute.coordinates),
        );
      },
    );
  });
}

class _AccessInvoker implements RouteEdgeInvoker {
  int callCount = 0;

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    callCount += 1;
    final start = Map<String, dynamic>.from(body['startLocation'] as Map);
    final destination = Map<String, dynamic>.from(
      body['destination_location'] as Map,
    );
    final startLat = (start['latitude'] as num).toDouble();
    final startLng = (start['longitude'] as num).toDouble();
    final destLat = (destination['latitude'] as num).toDouble();
    final destLng = (destination['longitude'] as num).toDouble();

    final coordinates = List.generate(14, (index) {
      final t = index / 13;
      return [
        startLng + (destLng - startLng) * t,
        startLat + (destLat - startLat) * t,
      ];
    });
    final distanceMeters = _polylineDistanceMeters(coordinates);

    return {
      'route': {
        'geometry': {'type': 'LineString', 'coordinates': coordinates},
        'distance': distanceMeters,
        'duration': distanceMeters / 13.89,
        'legs': const [
          {'steps': []},
        ],
      },
    };
  }
}

RouteResult _buildLoopRoute() {
  final coordinates = List.generate(90, (index) {
    final t = (2 * math.pi * index) / 89;
    final radius = 0.018 + math.sin(t * 2) * 0.002;
    return [9.74 + math.cos(t) * radius, 47.41 + math.sin(t) * radius * 0.72];
  });
  coordinates[0] = [9.74, 47.41];
  coordinates[coordinates.length - 1] = [...coordinates.first];
  final geometry = {'type': 'LineString', 'coordinates': coordinates};
  final distanceMeters = _polylineDistanceMeters(coordinates);

  return RouteResult(
    geoJson: json.encode(geometry),
    geometry: geometry,
    coordinates: coordinates,
    maneuvers: const [],
    distanceMeters: distanceMeters,
    durationSeconds: distanceMeters / 16.0,
    distanceKm: distanceMeters / 1000.0,
  );
}

double _polylineDistanceMeters(List<List<double>> coordinates) {
  var total = 0.0;
  for (var index = 1; index < coordinates.length; index++) {
    total += geo.Geolocator.distanceBetween(
      coordinates[index - 1][1],
      coordinates[index - 1][0],
      coordinates[index][1],
      coordinates[index][0],
    );
  }
  return total;
}

geo.Position _position({required double latitude, required double longitude}) {
  return geo.Position(
    longitude: longitude,
    latitude: latitude,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 5,
    heading: 0,
    headingAccuracy: 5,
    speed: 0,
    speedAccuracy: 1,
  );
}
