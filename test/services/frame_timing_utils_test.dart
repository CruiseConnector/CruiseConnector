import 'package:cruise_connect/data/services/frame_timing_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('frameNormalizedBlend', () {
    test('behält den kalibrierten Blend bei 60fps bei', () {
      expect(
        frameNormalizedBlend(
          perFrameBlend: 0.18,
          elapsed: const Duration(microseconds: 16667),
        ),
        closeTo(0.18, 0.0001),
      );
    });

    test('erhöht den Blend bei ausgelassenen Kamera-Frames', () {
      final at60 = frameNormalizedBlend(
        perFrameBlend: 0.18,
        elapsed: const Duration(microseconds: 16667),
      );
      final at30 = frameNormalizedBlend(
        perFrameBlend: 0.18,
        elapsed: const Duration(microseconds: 33333),
      );
      final at20 = frameNormalizedBlend(
        perFrameBlend: 0.18,
        elapsed: const Duration(milliseconds: 50),
      );

      expect(at30, greaterThan(at60));
      expect(at30, closeTo(1 - 0.82 * 0.82, 0.002));
      expect(at20, greaterThan(at30));
    });

    test('deckelt lange Pausen gegen sichtbare Teleports', () {
      final longPause = frameNormalizedBlend(
        perFrameBlend: 0.18,
        elapsed: const Duration(seconds: 1),
      );
      const capped = 1 - 0.82 * 0.82 * 0.82 * 0.82;

      expect(longPause, closeTo(capped, 0.0001));
      expect(longPause, lessThan(0.56));
    });

    test('fällt bei fehlender Zeit auf den Basis-Blend zurück', () {
      expect(
        frameNormalizedBlend(perFrameBlend: 0.18, elapsed: null),
        closeTo(0.18, 0.0001),
      );
    });
  });
}
