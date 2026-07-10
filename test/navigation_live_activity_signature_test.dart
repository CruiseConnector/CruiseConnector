import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/navigation_live_activity_service.dart';

NavigationLiveActivitySnapshot _snap({
  String instruction = 'Rechts abbiegen auf Churer Straße.',
  String maneuverType = 'right',
  double? distanceToManeuver,
  double? remaining,
  int? durationSeconds = 1260,
  bool isRerouting = false,
}) {
  return NavigationLiveActivitySnapshot(
    instruction: instruction,
    maneuverType: maneuverType,
    distanceToManeuverMeters: distanceToManeuver,
    remainingDistanceMeters: remaining,
    remainingDurationSeconds: durationSeconds,
    isRerouting: isRerouting,
  );
}

void main() {
  // 2026-07-02 (vucko Live-Activity-Freeze): Die Signatur steuert, wie oft die
  // Live Activity gepusht wird. Zu feine Buckets (10 m) erzeugten ~1 Update/s →
  // iOS-Update-Budget erschöpft → Sperrbildschirm fror dauerhaft ein. Diese
  // Tests nageln die GROBEN Buckets fest.
  group('NavigationLiveActivitySnapshot.signature Buckets', () {
    test('kleine Distanz-Fortschritte (<50 m Schritt) ändern die Signatur NICHT',
        () {
      final a = _snap(distanceToManeuver: 100, remaining: 16600);
      final b = _snap(distanceToManeuver: 108, remaining: 16600);
      expect(a.signature(), b.signature());
    });

    test('50-m-Bucket-Wechsel unter 1 km ändert die Signatur', () {
      final a = _snap(distanceToManeuver: 100, remaining: 16600);
      final b = _snap(distanceToManeuver: 160, remaining: 16600);
      expect(a.signature(), isNot(b.signature()));
    });

    test('über 1 km gelten 250-m-Buckets', () {
      final a = _snap(distanceToManeuver: 1500, remaining: 16600);
      final b = _snap(distanceToManeuver: 1600, remaining: 16600);
      final c = _snap(distanceToManeuver: 1900, remaining: 16600);
      expect(a.signature(), b.signature());
      expect(a.signature(), isNot(c.signature()));
    });

    test('Reststrecke in 500-m-Buckets', () {
      final a = _snap(distanceToManeuver: 500, remaining: 16600);
      final b = _snap(distanceToManeuver: 500, remaining: 16700);
      final c = _snap(distanceToManeuver: 500, remaining: 17100);
      expect(a.signature(), b.signature());
      expect(a.signature(), isNot(c.signature()));
    });

    test('Manöver-Wechsel ändert die Signatur immer', () {
      final a = _snap(distanceToManeuver: 500, remaining: 16600);
      final b = _snap(
        instruction: 'Im Kreisverkehr Ausfahrt 1 auf Im Buch nehmen.',
        maneuverType: 'roundabout:1',
        distanceToManeuver: 500,
        remaining: 16600,
      );
      expect(a.signature(), isNot(b.signature()));
    });

    test('Reroute-Flag ändert die Signatur', () {
      final a = _snap(distanceToManeuver: 500, remaining: 16600);
      final b = _snap(
        distanceToManeuver: 500,
        remaining: 16600,
        isRerouting: true,
      );
      expect(a.signature(), isNot(b.signature()));
    });
  });
}
