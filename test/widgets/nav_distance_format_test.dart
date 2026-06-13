import 'package:cruise_connect/presentation/widgets/cruise/nav_distance_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-06-13 (vucko J2): Google-Maps-Style Distanz-Stufen. Der User will
/// saubere Zahlen (690, 680, 670) statt „krummer" wie 522 m.
void main() {
  group('formatNavDistance', () {
    test('null → --', () => expect(formatNavDistance(null), '--'));

    test('< 1 km auf 10er-Stufen gerundet', () {
      expect(formatNavDistance(522), '520 m');
      expect(formatNavDistance(694), '690 m');
      expect(formatNavDistance(685), '690 m'); // .5 → auf
      expect(formatNavDistance(683), '680 m');
      expect(formatNavDistance(677), '680 m');
      expect(formatNavDistance(671), '670 m');
    });

    test('NIE krumme Einer-Stelle unter 1 km', () {
      for (var m = 11; m < 1000; m++) {
        final s = formatNavDistance(m.toDouble());
        expect(s.endsWith('0 m'), isTrue, reason: '$m m → "$s"');
      }
    });

    test('1–10 km → ein Dezimal mit Komma', () {
      expect(formatNavDistance(2100), '2,1 km');
      expect(formatNavDistance(1000), '1,0 km');
      expect(formatNavDistance(5000), '5,0 km');
    });

    test('≥ 10 km → ganze km', () {
      expect(formatNavDistance(26000), '26 km');
      expect(formatNavDistance(12340), '12 km');
    });

    test('nowLabelUnderTen: < 10 m → Jetzt', () {
      expect(formatNavDistance(5, nowLabelUnderTen: true), 'Jetzt');
      expect(formatNavDistance(0, nowLabelUnderTen: true), 'Jetzt');
      // Ohne Flag bleibt es eine (10er-gestufte) Meter-Zahl: 5 → 10.
      expect(formatNavDistance(5), '10 m');
    });

    test('negativ → 0-geklemmt', () {
      expect(formatNavDistance(-50), '0 m');
    });
  });
}
