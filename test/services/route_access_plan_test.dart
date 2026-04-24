import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

    test('meidet Join-Punkte auf kurzem Sackgassen-Spike', () {
      final route = _buildLoopRouteWithDeadEndSpike();
      const planner = RouteAccessPlanner();

      final joinPoint = planner.chooseJoinPoint(
        currentPosition: _position(latitude: 47.422, longitude: 9.755),
        existingRoute: route,
      );

      expect(joinPoint.index, isNot(inInclusiveRange(8, 14)));
    });

    test(
      'closed-loop rebase darf spaeten lokalen Einstieg statt fruehem Originalstart waehlen',
      () {
        final route = _buildLoopRoute();
        final latePoint = route.coordinates[62];
        const planner = RouteAccessPlanner();

        final defaultJoin = planner.chooseJoinPoint(
          currentPosition: _position(
            latitude: latePoint[1] + 0.0022,
            longitude: latePoint[0] + 0.0022,
          ),
          existingRoute: route,
        );
        final rebasedJoin = planner
            .suggestJoinPoints(
              currentPosition: _position(
                latitude: latePoint[1] + 0.0022,
                longitude: latePoint[0] + 0.0022,
              ),
              existingRoute: route,
              maxCandidates: 1,
              rebaseClosedLoop: true,
            )
            .first;

        expect(rebasedJoin.progressRatio, greaterThan(0.55));
        expect(
          rebasedJoin.distanceFromCurrentMeters,
          lessThan(defaultJoin.distanceFromCurrentMeters),
        );
      },
    );
  });

  group('RouteService.buildAccessRouteToExistingRoute', () {
    test(
      'baut Access- und Return-Leg ohne Originalroute zu veraendern',
      () async {
        final invoker = _AccessInvoker();
        final service = RouteService(invoker: invoker);
        final existingRoute = _buildLoopRoute();
        final sessionStart = _position(latitude: 47.312, longitude: 9.611);

        final plan = await service.buildAccessRouteToExistingRoute(
          currentPosition: sessionStart,
          existingRoute: existingRoute,
          returnToSessionOrigin: true,
        );

        expect(plan.hasAccessLeg, isTrue);
        expect(plan.hasReturnLeg, isTrue);
        expect(invoker.callCount, 2);
        expect(plan.joinPoint.progressRatio, lessThanOrEqualTo(0.45));
        expect(
          plan.logicalOrigin,
          orderedEquals(existingRoute.coordinates.first),
        );
        expect(plan.logicalEnd, orderedEquals(existingRoute.coordinates.last));
        expect(plan.sessionOrigin, orderedEquals([9.611, 47.312]));
        expect(plan.sessionEnd, orderedEquals([9.611, 47.312]));
        expect(
          plan.activeRoute.coordinates.last,
          orderedEquals(plan.sessionOrigin),
        );
        expect(
          plan.activeRoute.distanceMeters!,
          greaterThan(plan.sessionRoute.distanceMeters!),
        );
        expect(
          plan.sessionRoute.distanceMeters!,
          greaterThan(plan.followOnRoute.distanceMeters!),
        );

        final accessRequest = invoker.bodies.first;
        expect(accessRequest['route_type'], 'POINT_TO_POINT');
        expect(accessRequest['mode'], 'Standard');
        expect(accessRequest['route_variant_hint'], 'access');
        expect(accessRequest['max_candidate_attempts'], 3);
        expect(accessRequest['continue_straight'], isTrue);
        expect(accessRequest['avoid_highways'], isFalse);
        expect(accessRequest.containsKey('targetDistance'), isFalse);
        expect(accessRequest.containsKey('detour_level'), isFalse);
        expect(accessRequest.containsKey('detour_factor'), isFalse);
        expect(
          accessRequest['startLocation']['latitude'],
          closeTo(47.312, 0.001),
        );
        expect(
          accessRequest['startLocation']['longitude'],
          closeTo(9.611, 0.001),
        );
        expect(
          accessRequest['destination_location']['latitude'],
          closeTo(plan.joinPoint.coordinate[1], 0.001),
        );
        expect(
          accessRequest['destination_location']['longitude'],
          closeTo(plan.joinPoint.coordinate[0], 0.001),
        );

        final returnRequest = invoker.bodies.last;
        expect(returnRequest['route_variant_hint'], 'return');
        expect(
          returnRequest['destination_location']['latitude'],
          closeTo(sessionStart.latitude, 0.001),
        );
        expect(
          returnRequest['destination_location']['longitude'],
          closeTo(sessionStart.longitude, 0.001),
        );
      },
    );

    test(
      'uebergibt avoidHighways an Access- und Return-Leg unveraendert',
      () async {
        final invoker = _AccessInvoker();
        final service = RouteService(invoker: invoker);
        final existingRoute = _buildLoopRoute();
        final sessionStart = _position(latitude: 47.312, longitude: 9.611);

        await service.buildAccessRouteToExistingRoute(
          currentPosition: sessionStart,
          existingRoute: existingRoute,
          avoidHighways: true,
          returnToSessionOrigin: true,
        );

        expect(invoker.callCount, 2);
        expect(
          invoker.bodies.every((request) => request['avoid_highways'] == true),
          isTrue,
        );
      },
    );

    test(
      'lockert avoidHighways fuer Access-Legs nicht stillschweigend auf',
      () async {
        final invoker = _StrictAvoidHighwaysInvoker();
        final service = RouteService(invoker: invoker);
        final existingRoute = _buildLoopRoute();

        await expectLater(
          service.buildAccessRouteToExistingRoute(
            currentPosition: _position(latitude: 47.312, longitude: 9.611),
            existingRoute: existingRoute,
            avoidHighways: true,
          ),
          throwsA(isA<RouteServiceException>()),
        );

        expect(invoker.callCount, 1);
        expect(invoker.bodies.single['avoid_highways'], isTrue);
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

    test(
      'rebased geschlossener Rundkurs joint lokal statt unnoetig zum Originalstart zu fahren',
      () async {
        final invoker = _AccessInvoker();
        final service = RouteService(invoker: invoker);
        final existingRoute = _buildLoopRoute();
        final localLatePoint = existingRoute.coordinates[62];
        final sessionStart = _position(
          latitude: localLatePoint[1] + 0.0009,
          longitude: localLatePoint[0] + 0.0009,
        );

        final plan = await service.buildAccessRouteToExistingRoute(
          currentPosition: sessionStart,
          existingRoute: existingRoute,
          returnToSessionOrigin: true,
          rebaseClosedLoop: true,
        );

        expect(plan.joinPoint.index, greaterThan(40));
        expect(plan.joinPoint.progressRatio, greaterThan(0.55));
        expect(plan.hasAccessLeg, isTrue);
        expect(plan.routeRebasedToUser, isTrue);
        expect(plan.routePassesNearUser, isTrue);
        expect(plan.joinPointType, 'nearby_pass');
        expect(
          plan.joinPoint.distanceFromCurrentMeters,
          lessThan(plan.routeStartDistanceMeters),
        );
        expect(plan.activeRoute.edgeMeta['join_point_type'], 'nearby_pass');
        expect(plan.activeRoute.edgeMeta['route_rebased_to_user'], isTrue);
        expect(plan.activeRoute.edgeMeta['route_passes_near_user'], isTrue);
        expect(invoker.callCount, 2);
      },
    );

    test(
      'tritt direkt spaet in den Loop ein wenn der Nutzer bereits am lokalen Durchgangspunkt steht',
      () async {
        final invoker = _AccessInvoker();
        final service = RouteService(invoker: invoker);
        final existingRoute = _buildLoopRoute();
        final localLatePoint = existingRoute.coordinates[58];

        final plan = await service.buildAccessRouteToExistingRoute(
          currentPosition: _position(
            latitude: localLatePoint[1],
            longitude: localLatePoint[0],
          ),
          existingRoute: existingRoute,
          returnToSessionOrigin: true,
          rebaseClosedLoop: true,
        );

        expect(plan.hasAccessLeg, isFalse);
        expect(plan.joinPoint.index, greaterThan(40));
        expect(plan.joinPointType, 'nearby_pass');
        expect(plan.routeRebasedToUser, isTrue);
        expect(plan.activeRoute.edgeMeta['access_leg_used'], isFalse);
        expect(plan.activeRoute.edgeMeta['join_point_type'], 'nearby_pass');
        expect(plan.activeRoute.edgeMeta['route_start_distance_km'], isNotNull);
        expect(invoker.callCount, 0);
      },
    );
  });
}

class _AccessInvoker implements RouteEdgeInvoker {
  int callCount = 0;
  Map<String, dynamic>? lastBody;
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    callCount += 1;
    lastBody = Map<String, dynamic>.from(body);
    bodies.add(lastBody!);
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

class _StrictAvoidHighwaysInvoker implements RouteEdgeInvoker {
  int callCount = 0;
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    callCount += 1;
    final captured = Map<String, dynamic>.from(body);
    bodies.add(captured);

    if (captured['avoid_highways'] == true) {
      throw const FunctionException(
        status: 404,
        details: {'error': 'no route without highways'},
        reasonPhrase: 'Not Found',
      );
    }

    final start = Map<String, dynamic>.from(captured['startLocation'] as Map);
    final destination = Map<String, dynamic>.from(
      captured['destination_location'] as Map,
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

RouteResult _buildLoopRouteWithDeadEndSpike() {
  final base = _buildLoopRoute();
  final coordinates = base.coordinates
      .map((point) => [point[0], point[1]])
      .toList(growable: true);
  final anchor = coordinates[10];
  coordinates.insertAll(11, [
    [anchor[0] + 0.0012, anchor[1] + 0.0004],
    [anchor[0] + 0.0018, anchor[1] + 0.0008],
    [anchor[0] + 0.0012, anchor[1] + 0.0004],
    [anchor[0], anchor[1]],
  ]);
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
