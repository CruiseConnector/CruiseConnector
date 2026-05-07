import 'package:cruise_connect/data/services/group_route_data_builder.dart';
import 'package:cruise_connect/domain/models/mapbox_suggestion.dart';
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  RouteResult routeWithMeta(Map<String, dynamic> meta) {
    return RouteResult(
      geoJson: '{"type":"LineString","coordinates":[[9.7,47.5],[9.8,47.6]]}',
      geometry: const {
        'type': 'LineString',
        'coordinates': [
          [9.7, 47.5],
          [9.8, 47.6],
        ],
      },
      coordinates: const [
        [9.7, 47.5],
        [9.8, 47.6],
      ],
      maneuvers: const [],
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
      destination: const MapboxSuggestion(
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
}
