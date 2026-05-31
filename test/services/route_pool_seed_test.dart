// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:math';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/route_quality_validator.dart';

void main() {
  group('Vorarlberg route-pool seed', () {
    final seedFile = File('supabase/seed/route_pool_vorarlberg.json');
    final seedSql = File(
      'supabase/migrations/20260424_route_pool_vorarlberg_seed.sql',
    );
    final regionsSql = File(
      'supabase/migrations/20260423_route_pool_regions.sql',
    );
    final southRegionsSql = File(
      'supabase/migrations/20260425_route_pool_regions_south_rheintal.sql',
    );
    final southSeedSql = File(
      File(
            'supabase/migrations/20260426_route_pool_vorarlberg_south_rheintal_seed.sql',
          ).existsSync()
          ? 'supabase/migrations/20260426_route_pool_vorarlberg_south_rheintal_seed.sql'
          : 'supabase/migrations/20260425_route_pool_vorarlberg_south_rheintal_seed.sql',
    );

    test('route_regions seed contains the MVP Vorarlberg clusters', () {
      final sql =
          regionsSql.readAsStringSync() +
          '\n' +
          (southRegionsSql.existsSync()
              ? southRegionsSql.readAsStringSync()
              : '');

      expect(sql, contains("('AT', 'Vorarlberg', 'Bregenz'"));
      expect(sql, contains("('AT', 'Vorarlberg', 'Dornbirn'"));
      expect(sql, contains("('AT', 'Vorarlberg', 'Feldkirch'"));
      expect(sql, contains("('AT', 'Vorarlberg', 'Bludenz'"));
      expect(sql, contains("'Rheintal-Sued'"));
    });

    test(
      'seed routes are verified real Mapbox geometries, not placeholders',
      () {
        final routes = _seedRoutes(seedFile);

        expect(routes.length, greaterThanOrEqualTo(10));
        expect(
          routes.any((route) => route['source'] == 'placeholder'),
          isFalse,
        );

        final fingerprints = <String>{};
        final clusters = <String>{};
        final buckets = <int>{};
        final clusterCounts = <String, int>{};
        final bucketCounts = <int, int>{};
        var noHighwayCount = 0;
        final southRheintalRoutes = <Map<String, dynamic>>[];

        for (final route in routes) {
          fingerprints.add(route['route_fingerprint'] as String);
          clusters.add(route['city_cluster'] as String);
          buckets.add(route['distance_bucket'] as int);
          clusterCounts.update(
            route['city_cluster'] as String,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
          bucketCounts.update(
            route['distance_bucket'] as int,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
          if (route['avoids_highway'] == true &&
              route['has_highway'] == false) {
            noHighwayCount += 1;
          }
          if (route['city_cluster'] == 'Rheintal-Sued') {
            southRheintalRoutes.add(route);
          }

          expect(route['verified'], isTrue);
          expect(route['is_active'], isTrue);
          expect(route['source'], 'mapbox_seed');
          expect(route['route_type'], 'ROUND_TRIP');
          expect(route['distance_bucket'], isNot(150));
          expect(route['distance_bucket'], isIn(<int>[50, 75, 100]));
          expect(route['avoids_highway'], isTrue);
          expect(route['has_highway'], isFalse);
          expect(route['quality_score'], greaterThanOrEqualTo(70));

          final geometry = route['geometry'] as Map<String, dynamic>;
          expect(geometry['type'], 'LineString');
          expect(geometry['coordinates'], isA<List>());
          expect((geometry['coordinates'] as List).length, greaterThan(20));

          final payload = route['route_payload'] as Map<String, dynamic>;
          expect(payload['provider'], 'mapbox');
          expect(payload['effective_excludes'], contains('motorway'));
        }

        expect(fingerprints.length, routes.length);
        expect(
          clusters,
          containsAll(<String>[
            'Bregenz',
            'Dornbirn',
            'Feldkirch',
            'Bludenz',
            'Rheintal-Sued',
          ]),
        );
        expect(buckets, containsAll(<int>[50, 75, 100]));
        expect(noHighwayCount, routes.length);
        expect(clusterCounts['Bludenz'] ?? 0, greaterThanOrEqualTo(2));
        expect(clusterCounts['Feldkirch'] ?? 0, greaterThanOrEqualTo(4));
        expect(bucketCounts[100] ?? 0, greaterThanOrEqualTo(4));
        expect(southRheintalRoutes.length, greaterThanOrEqualTo(3));
        expect(
          southRheintalRoutes.where(
            (route) =>
                route['distance_bucket'] == 50 &&
                (route['style_tags'] as List).contains('Sport Mode'),
          ),
          hasLength(greaterThanOrEqualTo(3)),
        );
      },
    );

    test('seed SQL is idempotent and uses route_fingerprint upsert', () {
      final sql =
          seedSql.readAsStringSync() +
          '\n' +
          (southSeedSql.existsSync() ? southSeedSql.readAsStringSync() : '');

      expect(sql, contains('idx_route_pool_fingerprint'));
      expect(sql, contains('idx_route_pool_active_verified_bounds'));
      expect(sql, contains('ON CONFLICT (route_fingerprint) DO UPDATE SET'));
      expect(sql, contains('weekly_rotation_score'));
      expect(sql, contains('deprecated_at'));
    });

    test(
      'seed SQL stays consistent with JSON and has no empty is_active slot',
      () {
        final sql =
            seedSql.readAsStringSync() +
            '\n' +
            (southSeedSql.existsSync() ? southSeedSql.readAsStringSync() : '');
        final routes = _seedRoutes(seedFile);

        expect(sql, isNot(contains(", true, , '")));
        expect(sql, isNot(contains('undefined')));

        for (final route in routes) {
          expect(sql, contains(route['route_fingerprint'] as String));
        }
      },
    );

    test('south Rheintal seeds stay local to their cluster center', () {
      final routes = _seedRoutes(seedFile)
          .where((route) => route['city_cluster'] == 'Rheintal-Sued')
          .toList(growable: false);

      expect(routes.length, greaterThanOrEqualTo(3));
      for (final route in routes) {
        final startLat = route['start_lat'] as num;
        final startLng = route['start_lng'] as num;
        final distanceKm = _haversineKm(
          startLat.toDouble(),
          startLng.toDouble(),
          47.3499,
          9.6584,
        );
        expect(
          distanceKm,
          lessThanOrEqualTo(5.0),
          reason:
              'south Rheintal seed ${route['route_fingerprint']} starts too far from cluster center',
        );
      }
    });

    test('verified seed routes contain no short dead-end spikes', () {
      final routes = _seedRoutes(seedFile);

      for (final route in routes) {
        final geometry = route['geometry'] as Map<String, dynamic>;
        final coordinates = (geometry['coordinates'] as List)
            .map((point) => List<double>.from(point as List))
            .toList(growable: false);
        // 2026-05-31 (vucko): Dieser Test prüft gezielt KURZE Spikes (≤600m) —
        // daher explizit mit den historischen engen Parametern. Die
        // Produktiv-Defaults von detectDeadEndSpikes wurden separat erweitert
        // (bis 1500m), um auch lange Sackgassen-Stiche zu erkennen; das ist
        // hier bewusst NICHT Gegenstand (sonst flaggt es längere, evtl.
        // gewollte Pool-Geometrien).
        final spikes = RouteQualityValidator.detectDeadEndSpikes(
          coordinates,
          maxPathMeters: 600.0,
          maxOutwardRadiusMeters: 320.0,
        );
        expect(
          spikes,
          isEmpty,
          reason:
              'seed route ${route['route_fingerprint']} contains short dead-end spikes',
        );
      }
    });
  });
}

List<Map<String, dynamic>> _seedRoutes(File file) {
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return (json['routes'] as List)
      .cast<Map>()
      .map((route) => Map<String, dynamic>.from(route))
      .toList(growable: false);
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRadians(lat1)) *
          cos(_toRadians(lat2)) *
          sin(dLng / 2) *
          sin(dLng / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadiusKm * c;
}

double _toRadians(double value) => value * pi / 180.0;
