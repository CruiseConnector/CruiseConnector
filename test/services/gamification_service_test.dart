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

    test('stores an explicit XP award even when distance would differ', () {
      final row = GamificationService.buildDriveSessionInsert(
        userId: 'user-1',
        distanceKm: 23.004,
        durationSeconds: 1800,
        completedAtEnd: false,
        xpAwarded: 200,
      );

      expect(row['distance_km'], 23.004);
      expect(row['xp_awarded'], 200);
    });

    test('route progress XP is gated at 20 percent and proportional', () {
      RouteXpBreakdown breakdown(double progress, {bool completed = false}) {
        return GamificationService.calculateRouteXpBreakdownForProgress(
          plannedDistanceKm: 100,
          progressRatio: progress,
          completed: completed,
          curves: 999,
          style: 'Kurvenjagd',
        );
      }

      expect(breakdown(0).totalXp, 0);
      expect(breakdown(0.199).totalXp, 0);
      expect(breakdown(0.20).totalXp, 200);
      expect(breakdown(0.50).totalXp, 500);
      expect(breakdown(1.0, completed: true).totalXp, 1000);
    });

    test('completed flag below finish threshold does not grant full XP', () {
      final xp = GamificationService.calculateRouteXpBreakdownForProgress(
        plannedDistanceKm: 100,
        progressRatio: 0.50,
        completed: true,
        curves: 0,
        style: 'Sport Mode',
      );

      expect(xp.totalXp, 500);
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

    test(
      'summarizing treats explicit zero XP as zero, not distance fallback',
      () {
        final totals = GamificationService.summarizeDriveSessions([
          UserDriveSession(
            id: 'drive-zero',
            userId: 'user-1',
            distanceKm: 50,
            durationSeconds: 900,
            xpAwarded: 0,
            completedAtEnd: false,
            routeStyle: 'Sport Mode',
            routeType: 'ROUND_TRIP',
            routeFingerprint: 'fp-zero',
            createdAt: DateTime.utc(2026, 1, 2),
          ),
        ]);

        expect(totals.totalRoutes, 1);
        expect(totals.totalDistanceKm, 50);
        expect(totals.totalXp, 0);
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
