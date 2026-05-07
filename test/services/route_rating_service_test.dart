import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/route_rating_service.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

void main() {
  group('RouteRatingService', () {
    test('Rating speichert vorhandenen Route-Fingerprint', () {
      final row = RouteRatingService.buildRatingRow(
        userId: 'user-1',
        result: const RouteResult(
          geoJson: '{}',
          geometry: {'type': 'LineString', 'coordinates': []},
          coordinates: [
            [9.7471, 47.5162],
            [9.75, 47.52],
            [9.7471, 47.5162],
          ],
          maneuvers: [],
          distanceKm: 50.2,
          edgeMeta: {
            'route_fingerprint': 'fp-explicit',
            'pool_route_id': 'pool-1',
            'route_source': 'pool',
            'quality_tier': 'good',
          },
        ),
        rating: 5,
        tags: const [' schön ', 'schön', 'gute Kurven'],
        completionPercent: 87.5,
        distanceKm: 50.2,
        durationSeconds: 3600,
        qualityTier: null,
      );

      expect(row['user_id'], 'user-1');
      expect(row['route_fingerprint'], 'fp-explicit');
      expect(row['route_id'], 'pool-1');
      expect(row['route_source'], 'pool');
      expect(row['rating'], 5);
      expect(row['tags'], ['schön', 'gute Kurven']);
      expect(row['completion_percent'], 87.5);
      expect(row['quality_tier'], 'good');
    });

    test('Rating baut Fingerprint aus Geometrie, wenn Edge-Meta fehlt', () {
      final row = RouteRatingService.buildRatingRow(
        userId: 'user-2',
        result: const RouteResult(
          geoJson: '{}',
          geometry: {'type': 'LineString', 'coordinates': []},
          coordinates: [
            [9.7471, 47.5162],
            [9.75, 47.52],
            [9.7471, 47.5162],
          ],
          maneuvers: [],
          distanceKm: 50.2,
          edgeMeta: {},
        ),
        rating: 4,
        tags: const [],
        completionPercent: 120,
        distanceKm: 50.2,
        durationSeconds: null,
        qualityTier: 'acceptable',
      );

      expect((row['route_fingerprint'] as String).isNotEmpty, true);
      expect(row['route_source'], 'unknown');
      expect(row['completion_percent'], 100);
      expect(row['quality_tier'], 'acceptable');
    });

    test('Rating normalisiert Runtime-Quellen auf DB-erlaubte Werte', () {
      final row = RouteRatingService.buildRatingRow(
        userId: 'user-3',
        result: const RouteResult(
          geoJson: '{}',
          geometry: {'type': 'LineString', 'coordinates': []},
          coordinates: [
            [9.7471, 47.5162],
            [9.75, 47.52],
          ],
          maneuvers: [],
          distanceKm: 50.2,
          edgeMeta: {
            'route_fingerprint': 'fp-prepared',
            'route_source': 'prepared_buffer',
          },
        ),
        rating: 4,
        tags: const [],
        completionPercent: 75,
        distanceKm: 50.2,
        durationSeconds: null,
        qualityTier: 'good',
      );

      expect(row['route_source'], 'cache');
    });
  });
}
