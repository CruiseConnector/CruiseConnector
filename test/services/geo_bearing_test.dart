import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/geo_bearing.dart';

/// Pinnt die behavior-preserving Extraktion der Bearing/Winkel-Mathe aus
/// cruise_mode_page. Werte von Hand gerechnet — Formeln byte-identisch zum
/// Original, daher sind diese Erwartungen zugleich Regressionsschutz.
void main() {
  group('GeoBearing.bearingDegrees', () {
    test('due east is 90°', () {
      expect(GeoBearing.bearingDegrees(0, 0, 0, 1), closeTo(90, 0.01));
    });
    test('due north is 0°', () {
      expect(GeoBearing.bearingDegrees(0, 0, 1, 0), closeTo(0, 0.01));
    });
    test('due west is 270°', () {
      expect(GeoBearing.bearingDegrees(0, 0, 0, -1), closeTo(270, 0.01));
    });
    test('result is always within [0,360)', () {
      final b = GeoBearing.bearingDegrees(48.78, 9.18, 47.15, 9.82);
      expect(b, greaterThanOrEqualTo(0));
      expect(b, lessThan(360));
    });
  });

  group('GeoBearing.angleDiff', () {
    test('wraps to the short way (signed)', () {
      expect(GeoBearing.angleDiff(10, 350), closeTo(-20, 0.001));
      expect(GeoBearing.angleDiff(350, 10), closeTo(20, 0.001));
      expect(GeoBearing.angleDiff(0, 90), closeTo(90, 0.001));
    });
  });

  group('GeoBearing.lerpAngleDeg', () {
    test('interpolates the short way across the 360/0 seam', () {
      expect(GeoBearing.lerpAngleDeg(0, 90, 0.5), closeTo(45, 0.001));
      expect(GeoBearing.lerpAngleDeg(350, 10, 0.5) % 360, closeTo(0, 0.001));
    });
  });

  group('GeoBearing forward offsets', () {
    test('lat offset peaks heading north', () {
      expect(GeoBearing.forwardOffsetLat(0), closeTo(0.0009, 1e-9));
    });
    test('lng offset peaks heading east', () {
      expect(GeoBearing.forwardOffsetLng(90), closeTo(0.0012, 1e-9));
    });
  });

  group('GeoBearing.isUsableHeading', () {
    test('accepts finite 0..360, rejects null/out-of-range/NaN', () {
      expect(GeoBearing.isUsableHeading(90), isTrue);
      expect(GeoBearing.isUsableHeading(0), isTrue);
      expect(GeoBearing.isUsableHeading(360), isTrue);
      expect(GeoBearing.isUsableHeading(null), isFalse);
      expect(GeoBearing.isUsableHeading(-1), isFalse);
      expect(GeoBearing.isUsableHeading(400), isFalse);
      expect(GeoBearing.isUsableHeading(double.nan), isFalse);
    });
  });
}
