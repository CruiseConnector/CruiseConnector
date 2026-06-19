import 'dart:convert';

import 'package:cruise_connect/data/services/route_cache_service.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RouteCacheService confirmed navigation route', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('speichert und liest bestaetigte Route offlinefaehig', () async {
      const coordinates = [
        [9.7471, 47.5031],
        [9.7550, 47.5080],
        [9.7620, 47.5120],
      ];
      final geometry = {'type': 'LineString', 'coordinates': coordinates};
      final route = RouteResult(
        geoJson:
            '{"type":"LineString","coordinates":[[9.7471,47.5031],[9.755,47.508],[9.762,47.512]]}',
        geometry: geometry,
        coordinates: coordinates,
        maneuvers: const [
          RouteManeuver(
            latitude: 47.5080,
            longitude: 9.7550,
            routeIndex: 1,
            icon: Icons.turn_right,
            announcement: 'Rechts abbiegen.',
            instruction: 'Rechts abbiegen.',
          ),
          RouteManeuver(
            latitude: 47.5120,
            longitude: 9.7620,
            routeIndex: 2,
            icon: Icons.flag,
            announcement: 'Ziel erreicht.',
            instruction: 'Ziel erreicht.',
          ),
        ],
        distanceMeters: 1800,
        durationSeconds: 240,
        distanceKm: 1.8,
        speedLimits: const [
          SpeedLimitSegment(startIndex: 0, endIndex: 1, speedKmh: 50),
          SpeedLimitSegment(startIndex: 1, endIndex: 2, speedKmh: 80),
        ],
        edgeMeta: const {
          'route_fingerprint': 'offline-route',
          'mapbox_token': 'must-not-persist',
          'nested': {'authorization': 'must-not-persist', 'safe': true},
        },
      );

      await RouteCacheService.instance.storeConfirmedRoute(
        route: route,
        isRoundTrip: false,
        style: 'Standard',
        avoidHighways: true,
        groupId: 'group-a',
      );

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('confirmed_navigation_route_v1')!;
      expect(raw, contains('"icon_name":"turn_right"'));
      expect(raw, isNot(contains('icon_code_point')));

      final cached = await RouteCacheService.instance.loadConfirmedRoute();

      expect(cached, isNotNull);
      expect(cached!.isRoundTrip, isFalse);
      expect(cached.style, 'Standard');
      expect(cached.avoidHighways, isTrue);
      expect(cached.groupId, 'group-a');
      expect(cached.route.coordinates, coordinates);
      expect(cached.route.maneuvers, hasLength(2));
      expect(cached.route.maneuvers.first.icon, Icons.turn_right);
      expect(cached.route.maneuvers.last.isArrival, isTrue);
      expect(cached.route.speedLimits, hasLength(2));
      expect(cached.route.speedLimits.last.speedKmh, 80);
      expect(cached.route.edgeMeta['route_fingerprint'], 'offline-route');
      expect(cached.route.edgeMeta.containsKey('mapbox_token'), isFalse);
      final nested = cached.route.edgeMeta['nested'] as Map<String, dynamic>;
      expect(nested.containsKey('authorization'), isFalse);
      expect(nested['safe'], isTrue);
    });

    test(
      'clearConfirmedRoute entfernt gespeicherte Navigationsroute',
      () async {
        const route = RouteResult(
          geoJson: '{"type":"LineString","coordinates":[[9,47],[9.1,47.1]]}',
          geometry: {
            'type': 'LineString',
            'coordinates': [
              [9.0, 47.0],
              [9.1, 47.1],
            ],
          },
          coordinates: [
            [9.0, 47.0],
            [9.1, 47.1],
          ],
          maneuvers: [],
        );

        await RouteCacheService.instance.storeConfirmedRoute(
          route: route,
          isRoundTrip: true,
          style: 'Kurvenjagd',
          avoidHighways: false,
        );
        await RouteCacheService.instance.clearConfirmedRoute();

        expect(await RouteCacheService.instance.loadConfirmedRoute(), isNull);
      },
    );

    test('liest Legacy-Icon-Codepoints ohne dynamische IconData', () async {
      SharedPreferences.setMockInitialValues({
        'confirmed_navigation_route_v1': jsonEncode({
          'saved_at': DateTime.now().toUtc().toIso8601String(),
          'is_round_trip': true,
          'style': 'Sport Mode',
          'avoid_highways': false,
          'route': {
            'geo_json':
                '{"type":"LineString","coordinates":[[9,47],[9.1,47.1]]}',
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [9.0, 47.0],
                [9.1, 47.1],
              ],
            },
            'coordinates': [
              [9.0, 47.0],
              [9.1, 47.1],
            ],
            'maneuvers': [
              {
                'latitude': 47.1,
                'longitude': 9.1,
                'route_index': 1,
                'announcement': 'Links abbiegen.',
                'instruction': 'Links abbiegen.',
                'icon_code_point': Icons.turn_left.codePoint,
                'icon_font_family': Icons.turn_left.fontFamily,
                'maneuver_type': ManeuverType.normal.name,
              },
            ],
          },
        }),
      });

      final cached = await RouteCacheService.instance.loadConfirmedRoute();

      expect(cached, isNotNull);
      expect(cached!.route.maneuvers.single.icon, Icons.turn_left);
    });

    test('erhaelt Kreisverkehr-Topologie-Felder beim Speichern', () async {
      const route = RouteResult(
        geoJson: '{"type":"LineString","coordinates":[[9,47],[9.1,47.1]]}',
        geometry: {
          'type': 'LineString',
          'coordinates': [
            [9.0, 47.0],
            [9.1, 47.1],
          ],
        },
        coordinates: [
          [9.0, 47.0],
          [9.1, 47.1],
        ],
        maneuvers: [
          RouteManeuver(
            latitude: 47.1,
            longitude: 9.1,
            routeIndex: 1,
            icon: Icons.roundabout_right,
            announcement: 'Im Kreisverkehr 2. Ausfahrt nehmen',
            instruction: 'Im Kreisverkehr 2. Ausfahrt nehmen',
            maneuverType: ManeuverType.roundabout,
            roundaboutExitNumber: 2,
            roundaboutTurnAngleRad: -0.7,
            roundaboutEntryBearing: 180,
            roundaboutExitBearing: 0,
            roundaboutArmBearings: [180, 90, 0, 270],
            roundaboutIslandScale: 1.25,
            roundaboutIsArrival: true,
          ),
        ],
      );

      await RouteCacheService.instance.storeConfirmedRoute(
        route: route,
        isRoundTrip: true,
        style: 'Sport Mode',
        avoidHighways: false,
      );

      final cached = await RouteCacheService.instance.loadConfirmedRoute();
      final maneuver = cached!.route.maneuvers.single;

      expect(maneuver.maneuverType, ManeuverType.roundabout);
      expect(maneuver.roundaboutExitNumber, 2);
      expect(maneuver.roundaboutTurnAngleRad, -0.7);
      expect(maneuver.roundaboutEntryBearing, 180);
      expect(maneuver.roundaboutExitBearing, 0);
      expect(maneuver.roundaboutArmBearings, [180, 90, 0, 270]);
      expect(maneuver.roundaboutIslandScale, 1.25);
      expect(maneuver.roundaboutIsArrival, isTrue);
    });
  });
}
