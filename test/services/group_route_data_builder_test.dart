import 'package:cruise_connect/data/services/group_route_data_builder.dart';
import 'package:cruise_connect/domain/models/place_suggestion.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  RouteResult routeWithMeta(
    Map<String, dynamic> meta, {
    List<List<double>> coordinates = const [
      [9.7, 47.5],
      [9.8, 47.6],
    ],
    List<RouteManeuver> maneuvers = const [],
  }) {
    return RouteResult(
      geoJson: '{"type":"LineString","coordinates":[[9.7,47.5],[9.8,47.6]]}',
      geometry: {'type': 'LineString', 'coordinates': coordinates},
      coordinates: coordinates,
      maneuvers: maneuvers,
      distanceMeters: 52000,
      durationSeconds: 3600,
      edgeMeta: meta,
    );
  }

  test('speichert A-nach-B route_data mit Ziel und Detour', () {
    final routeData = GroupRouteDataBuilder.build(
      route: routeWithMeta({'route_fingerprint': 'fp-a-b'}),
      isRoundTrip: false,
      planningType: 'Zufall',
      style: 'Sport Mode',
      avoidHighways: true,
      destination: const PlaceSuggestion(
        placeName: 'Bregenz',
        coordinates: [9.7471, 47.5031],
      ),
      detourVariant: 2,
      scenic: true,
    );

    expect(routeData['route_type'], 'POINT_TO_POINT');
    expect(routeData['avoid_highways'], isTrue);
    expect(routeData['detour_variant'], 2);
    expect(routeData['scenic'], isTrue);
    expect(routeData['fingerprint'], 'fp-a-b');
    expect(routeData['destination'], isA<Map<String, dynamic>>());
    expect((routeData['destination'] as Map)['place_name'], 'Bregenz');
  });

  test('speichert Wegpunkte-Rundkurs mit required_waypoints und Herkunft', () {
    final routeData = GroupRouteDataBuilder.build(
      route: routeWithMeta({'route_fingerprint': 'fp-waypoints'}),
      isRoundTrip: true,
      planningType: 'Wegpunkte',
      style: 'Kurvenjagd',
      avoidHighways: false,
      targetDistanceKm: 75,
      requiredWaypoints: const [LatLng(47.4, 9.7), LatLng(47.5, 9.8)],
      waypointOrigin: 'auto_seed',
      waypointSeedAttempt: 3,
    );

    expect(routeData['route_type'], 'ROUND_TRIP');
    expect(routeData['planning_type'], 'Wegpunkte');
    expect(routeData['target_distance_km'], 75);
    expect(routeData['required_waypoints'], hasLength(2));
    expect(routeData['waypoint_origin'], 'auto_seed');
    expect(routeData['waypoint_seed_attempt'], 3);
  });

  test('filtert sensible Meta-Keys aus route_data', () {
    final routeData = GroupRouteDataBuilder.build(
      route: routeWithMeta({
        'route_fingerprint': 'fp-safe',
        'authorization': 'Bearer should-not-persist',
        'mapbox_token': 'should-not-persist',
        'worker_secret': 'should-not-persist',
      }),
      isRoundTrip: true,
      planningType: 'Zufall',
      style: 'Sport Mode',
      avoidHighways: false,
      targetDistanceKm: 50,
    );

    final meta = routeData['edgeMeta'] as Map<String, dynamic>;
    expect(meta['route_fingerprint'], 'fp-safe');
    expect(meta.containsKey('authorization'), isFalse);
    expect(meta.containsKey('mapbox_token'), isFalse);
    expect(meta.containsKey('worker_secret'), isFalse);
  });

  test('ersetzt Route fuer Gruppenrevision und behaelt Planungsdaten', () {
    final previous = GroupRouteDataBuilder.build(
      route: routeWithMeta({
        'route_fingerprint': 'old-fp',
        'authorization': 'Bearer should-not-persist',
      }),
      isRoundTrip: true,
      planningType: 'Wegpunkte',
      style: 'Kurvenjagd',
      avoidHighways: true,
      targetDistanceKm: 50,
      requiredWaypoints: const [LatLng(47.4, 9.7)],
    )..['client_secret'] = 'should-not-persist';

    final replacement = GroupRouteDataBuilder.replaceRoutePayload(
      route: routeWithMeta(
        {'route_fingerprint': 'new-fp', 'mapbox_token': 'nope'},
        coordinates: const [
          [9.9, 47.7],
          [10.0, 47.8],
        ],
      ),
      previousRouteData: previous,
      updateReason: 'navigation_reroute',
      publishMeta: {
        'client_guard': 'leader_progress_v1',
        'is_leading_vehicle': true,
        'publisher_progress_meters': 1234.5,
        'service_role_token': 'should-not-persist',
      },
    );

    expect(replacement['planning_type'], 'Wegpunkte');
    expect(replacement['avoid_highways'], isTrue);
    expect(replacement['target_distance_km'], 50);
    expect(replacement['fingerprint'], 'new-fp');
    expect(replacement['update_reason'], 'navigation_reroute');
    expect(replacement.containsKey('client_secret'), isFalse);
    final publish = replacement['route_publish'] as Map<String, dynamic>;
    expect(publish['is_leading_vehicle'], isTrue);
    expect(publish['publisher_progress_meters'], 1234.5);
    expect(publish.containsKey('service_role_token'), isFalse);
    final meta = replacement['edgeMeta'] as Map<String, dynamic>;
    expect(meta.containsKey('mapbox_token'), isFalse);
  });

  test('parst kanonische Gruppenroute inklusive Manöver', () {
    final routeData = GroupRouteDataBuilder.build(
      route: routeWithMeta(
        {'route_fingerprint': 'parse-fp'},
        maneuvers: const [
          RouteManeuver(
            latitude: 47.55,
            longitude: 9.75,
            routeIndex: 8,
            icon: Icons.roundabout_right,
            announcement: 'Im Kreisverkehr die zweite Ausfahrt nehmen.',
            instruction: 'Im Kreisverkehr die zweite Ausfahrt nehmen.',
            maneuverType: ManeuverType.roundabout,
            roundaboutExitNumber: 2,
          ),
          RouteManeuver(
            latitude: 47.6,
            longitude: 9.8,
            routeIndex: 20,
            icon: Icons.flag,
            announcement: 'Ziel erreicht.',
            instruction: 'Ziel erreicht.',
          ),
        ],
      ),
      isRoundTrip: false,
      planningType: 'Zufall',
      style: 'Standard',
      avoidHighways: false,
    );

    final parsed = GroupRouteDataBuilder.parseRouteResult(routeData);

    expect(parsed, isNotNull);
    expect(parsed!.coordinates, hasLength(2));
    expect(parsed.maneuvers, hasLength(2));
    expect(parsed.maneuvers.first.maneuverType, ManeuverType.roundabout);
    expect(parsed.maneuvers.first.roundaboutExitNumber, 2);
    expect(parsed.maneuvers.last.icon, Icons.flag);
  });
}
