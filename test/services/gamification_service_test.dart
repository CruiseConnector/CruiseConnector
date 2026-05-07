import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/domain/models/user_drive_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Gamification badge persistence', () {
    test(
      'keeps already unlocked badges when current rules no longer qualify',
      () {
        final badges = GamificationService.mergeBadgeIds([
          'badge_05',
          'badge_07',
        ], const []);

        expect(badges, ['badge_05', 'badge_07']);
      },
    );

    test('does not report an already unlocked badge as new again', () {
      final newBadges = GamificationService.newlyQualifiedBadgeIds(
        ['badge_05'],
        ['badge_05'],
      );

      expect(newBadges, isEmpty);
    });

    test('normalizes legacy ids, removes invalid ids, and preserves order', () {
      final badges = GamificationService.mergeBadgeIds(
        ['badge_13', 'route_1', 'unknown_badge', 'badge_05', 'badge_05'],
        ['badge_01'],
      );

      expect(badges, ['badge_01', 'badge_02', 'badge_05', 'badge_13']);
    });
  });

  group('Drive-session XP', () {
    test('awards exactly 10 XP per actually driven kilometer', () {
      expect(GamificationService.calculateDriveXp(1), 10);
      expect(GamificationService.calculateDriveXp(10), 100);
      expect(GamificationService.calculateDriveXp(100), 1000);
      expect(GamificationService.calculateDriveXp(23), 230);
    });

    test('ignores curves, style bonuses, and streak multipliers for XP', () {
      final xp = GamificationService.calculateRouteXp(
        distanceKm: 23,
        curves: 999,
        style: 'Kurvenjagd',
        streakDays: 30,
      );

      expect(xp, 230);
    });

    test('builds an immutable drive-session insert from actual distance', () {
      final row = GamificationService.buildDriveSessionInsert(
        userId: 'user-1',
        distanceKm: 23.004,
        durationSeconds: 1800,
        completedAtEnd: false,
        routeStyle: 'Sport Mode',
        routeType: 'ROUND_TRIP',
        routeFingerprint: 'fp-23',
      );

      expect(row['distance_km'], 23.004);
      expect(row['duration_seconds'], 1800);
      expect(row['xp_awarded'], 230);
      expect(row['completed_at_end'], isFalse);
      expect(row['route_fingerprint'], 'fp-23');
    });

    test(
      'summarizes only drive sessions, so saved-route deletion cannot remove XP',
      () {
        final sessions = [
          UserDriveSession(
            id: 'drive-1',
            userId: 'user-1',
            distanceKm: 23,
            durationSeconds: 1200,
            xpAwarded: 230,
            completedAtEnd: false,
            routeStyle: 'Sport Mode',
            routeType: 'ROUND_TRIP',
            routeFingerprint: 'fp-1',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ];

        final beforeDelete = GamificationService.summarizeDriveSessions(
          sessions,
        );
        final afterSavedRouteDelete =
            GamificationService.summarizeDriveSessions(sessions);

        expect(beforeDelete.totalDistanceKm, 23);
        expect(beforeDelete.totalXp, 230);
        expect(beforeDelete.totalRoutes, 1);
        expect(afterSavedRouteDelete.totalXp, beforeDelete.totalXp);
        expect(
          afterSavedRouteDelete.totalDistanceKm,
          beforeDelete.totalDistanceKm,
        );
      },
    );

    test('old saved routes without drive sessions do not create XP totals', () {
      final totals = GamificationService.summarizeDriveSessions(const []);

      expect(totals.totalDistanceKm, 0);
      expect(totals.totalXp, 0);
      expect(totals.totalRoutes, 0);
    });
  });
}
