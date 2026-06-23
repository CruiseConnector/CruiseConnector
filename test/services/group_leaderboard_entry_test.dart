import 'package:cruise_connect/data/services/group_leaderboard_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GroupLeaderboardEntry.fromMap (X3 RPC parsing)', () {
    test('parses the RPC row shape (double precision + bigint)', () {
      // So liefert get_group_leaderboard eine Zeile zurück.
      final e = GroupLeaderboardEntry.fromMap({
        'user_id': 'u-1',
        'username': 'test37',
        'avatar_url': 'https://x/y.png',
        'total_distance_km': 55.0,
        'max_top_speed_kmh': 120.0,
        'total_duration_seconds': 3300,
        'session_count': 2,
      });
      expect(e.userId, 'u-1');
      expect(e.username, 'test37');
      expect(e.totalDistanceKm, 55.0);
      expect(e.maxTopSpeedKmh, 120.0);
      expect(e.totalDurationSeconds, 3300);
      expect(e.sessionCount, 2);
    });

    test('integer-typed numerics are coerced to double safely', () {
      final e = GroupLeaderboardEntry.fromMap({
        'user_id': 'u-2',
        'username': 'Bravo',
        'avatar_url': null,
        'total_distance_km': 80, // int, nicht double
        'max_top_speed_kmh': 100,
        'total_duration_seconds': 3600,
        'session_count': 1,
      });
      expect(e.totalDistanceKm, 80.0);
      expect(e.maxTopSpeedKmh, 100.0);
      expect(e.avatarUrl, isNull);
    });

    test('null top speed (alte Fahrten ohne Tempo) wird zu 0', () {
      final e = GroupLeaderboardEntry.fromMap({
        'user_id': 'u-3',
        'username': null,
        'avatar_url': null,
        'total_distance_km': 12.5,
        'max_top_speed_kmh': null,
        'total_duration_seconds': null,
        'session_count': 1,
      });
      expect(e.maxTopSpeedKmh, 0.0);
      expect(e.totalDurationSeconds, 0);
      expect(e.username, isNull);
    });
  });
}
