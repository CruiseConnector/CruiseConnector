import 'package:cruise_connect/data/services/gamification_service.dart';
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
}
