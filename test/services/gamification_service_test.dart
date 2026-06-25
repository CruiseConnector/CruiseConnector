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

    test('ignores curves and style bonuses; distance is the only base', () {
      final breakdown = GamificationService.calculateRouteXpBreakdown(
        distanceKm: 23,
        curves: 999,
        style: 'Kurvenjagd',
        streakDays: 1,
      );
      expect(breakdown.baseXp, 230);
    });

    test('applies the streak multiplier (1.0 + days*0.1, uncapped) to XP', () {
      // 2026-06-15 (vucko): pro aktivem Tag +0,1, KEIN Cap. Wird auch echt aufs
      // Konto angerechnet (xp_awarded), nicht nur angezeigt.
      expect(GamificationService.streakMultiplierForDays(0), 1.0);
      expect(GamificationService.streakMultiplierForDays(1), closeTo(1.1, 1e-9));
      expect(GamificationService.streakMultiplierForDays(2), closeTo(1.2, 1e-9));
      expect(GamificationService.streakMultiplierForDays(4), closeTo(1.4, 1e-9));
      expect(
        GamificationService.streakMultiplierForDays(10),
        closeTo(2.0, 1e-9),
      );
      expect(
        GamificationService.streakMultiplierForDays(20),
        closeTo(3.0, 1e-9),
      );

      // 10 km Basis = 100 XP; 4-Tage-Streak (×1,4) → 140 XP.
      expect(
        GamificationService.calculateRouteXp(
          distanceKm: 10,
          curves: 0,
          style: 'Sport Mode',
          streakDays: 4,
        ),
        140,
      );
      // 23 km Basis = 230 XP; 2-Tage-Streak (×1,2) → 276 XP.
      expect(
        GamificationService.calculateRouteXp(
          distanceKm: 23,
          curves: 0,
          style: 'Sport Mode',
          streakDays: 2,
        ),
        276,
      );
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

    // X3 Gruppen-Rangliste: group_id + top_speed_kmh fließen NUR in den Insert,
    // wenn sie gesetzt/plausibel sind — Single-Mode (kein Group, kein Tempo)
    // bleibt byte-genau wie vorher (Regressionsschutz „nichts kaputt machen").
    test('single-mode insert omits group_id and top_speed_kmh', () {
      final row = GamificationService.buildDriveSessionInsert(
        userId: 'user-1',
        distanceKm: 10,
        durationSeconds: 600,
        completedAtEnd: true,
      );
      expect(row.containsKey('group_id'), isFalse);
      expect(row.containsKey('top_speed_kmh'), isFalse);
    });

    test('group-mode insert tags group_id and rounds top_speed_kmh', () {
      final row = GamificationService.buildDriveSessionInsert(
        userId: 'user-1',
        distanceKm: 10,
        durationSeconds: 600,
        completedAtEnd: true,
        groupId: 'grp-7',
        topSpeedKmh: 123.456,
      );
      expect(row['group_id'], 'grp-7');
      expect(row['top_speed_kmh'], 123.5);
    });

    test('non-positive top speed is not written', () {
      final row = GamificationService.buildDriveSessionInsert(
        userId: 'user-1',
        distanceKm: 10,
        durationSeconds: 600,
        completedAtEnd: true,
        topSpeedKmh: 0,
      );
      expect(row.containsKey('top_speed_kmh'), isFalse);
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

      // baseXp = Distanz-XP VOR dem Streak-Multiplikator → testet das
      // Fortschritts-Gating sauber (der Multiplikator wird separat getestet).
      expect(breakdown(0).baseXp, 0);
      expect(breakdown(0.199).baseXp, 0);
      expect(breakdown(0.20).baseXp, 200);
      expect(breakdown(0.50).baseXp, 500);
      expect(breakdown(1.0, completed: true).baseXp, 1000);
    });

    test('completed flag below finish threshold does not grant full XP', () {
      final xp = GamificationService.calculateRouteXpBreakdownForProgress(
        plannedDistanceKm: 100,
        progressRatio: 0.50,
        completed: true,
        curves: 0,
        style: 'Sport Mode',
      );

      expect(xp.baseXp, 500);
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

  group('countCurves (distanz-basiert, dichte-unabhängig)', () {
    // ~47°N: Meter → Grad ([lng, lat]).
    const mLat = 111000.0;
    const mLng = 111000.0 * 0.6820; // × cos(47°)
    List<double> at(double eastM, double northM) =>
        [eastM / mLng, 47.0 + northM / mLat];

    List<List<double>> straight(int n) =>
        [for (var i = 0; i <= n; i++) at(600.0 * i / n, 0)];

    // L-Form: 400 m Ost, dann 400 m Nord → genau EINE 90°-Kurve.
    List<List<double>> lBend(int perLeg) => [
          for (var i = 0; i <= perLeg; i++) at(400.0 * i / perLeg, 0),
          for (var i = 1; i <= perLeg; i++) at(400.0, 400.0 * i / perLeg),
        ];

    // Z-/S-Form: Ost, Nord (links), Ost (rechts) → ZWEI Kurven.
    List<List<double>> zBend(int perLeg) => [
          for (var i = 0; i <= perLeg; i++) at(300.0 * i / perLeg, 0),
          for (var i = 1; i <= perLeg; i++) at(300.0, 300.0 * i / perLeg),
          for (var i = 1; i <= perLeg; i++)
            at(300.0 + 300.0 * i / perLeg, 300.0),
        ];

    test('Gerade Strecke hat 0 Kurven', () {
      expect(GamificationService.countCurves(straight(30)), 0);
    });

    test('Eine 90°-Biegung = 1 Kurve', () {
      expect(GamificationService.countCurves(lBend(20)), 1);
    });

    test('S-/Z-Form (links + rechts) = 2 Kurven', () {
      expect(GamificationService.countCurves(zBend(20)), 2);
    });

    test('Kurvenzahl ist UNABHÄNGIG von der Punktdichte', () {
      // Identische Form, einmal grob, einmal fein abgetastet. GENAU das war der
      // alte Bug (Index-Stride 20 → Ergebnis hing an der GraphHopper-Dichte).
      expect(
        GamificationService.countCurves(lBend(3)),
        GamificationService.countCurves(lBend(60)),
      );
      expect(
        GamificationService.countCurves(zBend(4)),
        GamificationService.countCurves(zBend(80)),
      );
    });

    test('Zu wenige Punkte → 0 (kein Crash)', () {
      expect(GamificationService.countCurves(const []), 0);
      expect(GamificationService.countCurves([at(0, 0)]), 0);
    });
  });
}
