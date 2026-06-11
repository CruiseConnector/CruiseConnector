import 'dart:math' as math;

double frameNormalizedBlend({
  required double perFrameBlend,
  required Duration? elapsed,
  double referenceFrameMs = 1000.0 / 60.0,
  double maxFrameMultiplier = 4.0,
}) {
  final base = perFrameBlend.clamp(0.0, 1.0).toDouble();
  if (elapsed == null || base <= 0.0 || base >= 1.0) return base;

  final elapsedMs = elapsed.inMicroseconds / 1000.0;
  if (!elapsedMs.isFinite || elapsedMs <= 0.0 || referenceFrameMs <= 0.0) {
    return base;
  }

  final frames = (elapsedMs / referenceFrameMs)
      .clamp(0.25, maxFrameMultiplier)
      .toDouble();
  return 1.0 - math.pow(1.0 - base, frames).toDouble();
}
