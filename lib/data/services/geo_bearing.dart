import 'dart:math' as math;

/// Shared bearing / heading-angle helpers.
///
/// 2026-06-26 (vucko): behavior-preserving extraction of the pure angle/bearing
/// math that lived as private statics inside the 16.7k-line cruise_mode_page
/// god-object. Sibling of [GeoDistance]. Formulas are byte-identical to the
/// originals — only the home moved, so the math is now testable in isolation.
class GeoBearing {
  const GeoBearing._();

  /// Zirkuläre Interpolation für Heading (0–360°).
  static double lerpAngleDeg(double from, double to, double t) {
    var diff = (to - from) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return (from + diff * t) % 360;
  }

  /// Kleinster Winkelunterschied (mit Vorzeichen, -180..+180).
  static double angleDiff(double from, double to) {
    var diff = (to - from) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }

  /// Forward-Offset: ~100m nach Norden in Breitengrad-Grad.
  static double forwardOffsetLat(double headingDeg) {
    return math.cos(headingDeg * math.pi / 180) * 0.0009; // ~100m
  }

  /// Forward-Offset: ~100m nach Osten in Längengrad-Grad.
  static double forwardOffsetLng(double headingDeg) {
    return math.sin(headingDeg * math.pi / 180) *
        0.0012; // ~100m (breitenabhängig)
  }

  /// Kompass-Bearing (0–360°) von (lat1,lng1) nach (lat2,lng2).
  static double bearingDegrees(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final phi1 = lat1 * math.pi / 180.0;
    final phi2 = lat2 * math.pi / 180.0;
    final dLng = (lng2 - lng1) * math.pi / 180.0;
    final y = math.sin(dLng) * math.cos(phi2);
    final x =
        math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(dLng);
    return (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
  }

  /// Heading ist nutzbar (endlich, 0–360°).
  static bool isUsableHeading(double? heading) =>
      heading != null && heading.isFinite && heading >= 0 && heading <= 360;
}
