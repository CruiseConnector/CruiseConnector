import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;

/// Schärfe-Stufe einer Kurve.
enum CurveSeverity { gentle, moderate, sharp, hairpin }

/// Eine erkannte Kurve auf der Route.
class DetectedCurve {
  const DetectedCurve({
    required this.routeIndex,
    required this.angleDegrees,
    required this.severity,
    required this.distanceMeters,
    required this.direction, // 'left' oder 'right'
  });

  final int routeIndex;
  final double angleDegrees;
  final CurveSeverity severity;
  final double distanceMeters; // Distanz vom aktuellen Standort
  final String direction;

  String get label {
    switch (severity) {
      case CurveSeverity.gentle:
        return 'Leichte Kurve';
      case CurveSeverity.moderate:
        return 'Kurve';
      case CurveSeverity.sharp:
        return 'Scharfe Kurve';
      case CurveSeverity.hairpin:
        return 'Haarnadelkurve';
    }
  }

  Color get color {
    switch (severity) {
      case CurveSeverity.gentle:
        return const Color(0xFF34C759); // grün
      case CurveSeverity.moderate:
        return const Color(0xFFFF9500); // orange
      case CurveSeverity.sharp:
        return const Color(0xFFFF5722); // deep orange
      case CurveSeverity.hairpin:
        return const Color(0xFFFF3B30); // rot
    }
  }

  IconData get icon {
    if (direction == 'left') {
      switch (severity) {
        case CurveSeverity.hairpin:
          return Icons.turn_sharp_left;
        case CurveSeverity.sharp:
          return Icons.turn_sharp_left;
        default:
          return Icons.turn_slight_left;
      }
    } else {
      switch (severity) {
        case CurveSeverity.hairpin:
          return Icons.turn_sharp_right;
        case CurveSeverity.sharp:
          return Icons.turn_sharp_right;
        default:
          return Icons.turn_slight_right;
      }
    }
  }
}

/// Kompakte Kurven-Vorwarnung die über dem Info-Panel angezeigt wird.
class CruiseCurveWarning extends StatelessWidget {
  const CruiseCurveWarning({
    super.key,
    required this.curve,
  });

  final DetectedCurve curve;

  @override
  Widget build(BuildContext context) {
    final distText = curve.distanceMeters >= 1000
        ? '${(curve.distanceMeters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km'
        : '${curve.distanceMeters.round()} m';

    // Anzahl der Chevrons basierend auf Schärfe
    final chevronCount = switch (curve.severity) {
      CurveSeverity.gentle => 1,
      CurveSeverity.moderate => 2,
      CurveSeverity.sharp => 3,
      CurveSeverity.hairpin => 4,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2028).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: curve.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Icon-Container mit farbigem Hintergrund
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: curve.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(curve.icon, color: curve.color, size: 22),
          ),
          const SizedBox(width: 12),
          // Label + Chevrons
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  curve.label,
                  style: TextStyle(
                    color: curve.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    chevronCount,
                    (i) => Padding(
                      padding: const EdgeInsets.only(right: 1),
                      child: Icon(
                        curve.direction == 'left'
                            ? Icons.chevron_left_rounded
                            : Icons.chevron_right_rounded,
                        color: curve.color.withValues(alpha: 0.7),
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Distanz rechts
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: curve.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              distText,
              style: TextStyle(
                color: curve.color,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Erkennt Kurven auf der Route voraus ab dem aktuellen Index.
  /// Gibt die nächste relevante Kurve zurück (> 30° Richtungswechsel, < 2km entfernt).
  static DetectedCurve? detectNextCurve({
    required List<List<double>> coordinates,
    required int currentIndex,
    double maxDistanceMeters = 2000,
  }) {
    if (coordinates.length < 10 || currentIndex >= coordinates.length - 10) {
      return null;
    }

    // Voraus-Scan: Suche Richtungswechsel in Segmenten
    // Größerer Segmentabstand (12 Punkte ≈ 80-150m) reduziert Rauschen auf geraden Strecken
    const segmentStep = 12;
    double cumDist = 0;
    final scanEnd = math.min(currentIndex + 400, coordinates.length - segmentStep);

    for (var i = currentIndex + segmentStep; i < scanEnd; i += segmentStep) {
      // Distanz zum Segment berechnen
      for (var d = i - segmentStep; d < i; d++) {
        cumDist += geo.Geolocator.distanceBetween(
          coordinates[d][1], coordinates[d][0],
          coordinates[d + 1][1], coordinates[d + 1][0],
        );
      }

      if (cumDist > maxDistanceMeters) break;

      // Bearing über längere Distanz berechnen (2× segmentStep),
      // damit kleine GPS-Rauscher auf geraden Strecken nicht als Kurve erkannt werden
      final before = math.max(i - segmentStep * 2, currentIndex);
      final after = math.min(i + segmentStep * 2, coordinates.length - 1);

      // Mindestabstand zwischen den Messpunkten prüfen — zu nah = unzuverlässig
      final distBefore = geo.Geolocator.distanceBetween(
        coordinates[before][1], coordinates[before][0],
        coordinates[i][1], coordinates[i][0],
      );
      final distAfter = geo.Geolocator.distanceBetween(
        coordinates[i][1], coordinates[i][0],
        coordinates[after][1], coordinates[after][0],
      );
      // Wenn Messpunkte zu nah beieinander → Bearing unzuverlässig, überspringen
      if (distBefore < 30 || distAfter < 30) continue;

      final bearing1 = _bearing(
        coordinates[before][1], coordinates[before][0],
        coordinates[i][1], coordinates[i][0],
      );
      final bearing2 = _bearing(
        coordinates[i][1], coordinates[i][0],
        coordinates[after][1], coordinates[after][0],
      );

      var angleDiff = (bearing2 - bearing1).abs();
      if (angleDiff > 180) angleDiff = 360 - angleDiff;

      // Nur echte Kurven (> 35°) — vorher 25° was zu viele Fehlalarme erzeugte
      if (angleDiff < 35) continue;

      // Richtung bestimmen (cross-product)
      final cross = math.sin((bearing2 - bearing1) * math.pi / 180);
      final direction = cross > 0 ? 'right' : 'left';

      // Schärfe bestimmen (erhöhte Schwellen um Fehlalarme zu reduzieren)
      final severity = angleDiff >= 130
          ? CurveSeverity.hairpin
          : angleDiff >= 80
              ? CurveSeverity.sharp
              : angleDiff >= 50
                  ? CurveSeverity.moderate
                  : CurveSeverity.gentle;

      return DetectedCurve(
        routeIndex: i,
        angleDegrees: angleDiff,
        severity: severity,
        distanceMeters: cumDist,
        direction: direction,
      );
    }

    return null;
  }

  static double _bearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * math.pi / 180;
    final lat1R = lat1 * math.pi / 180;
    final lat2R = lat2 * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2R);
    final x = math.cos(lat1R) * math.sin(lat2R) -
        math.sin(lat1R) * math.cos(lat2R) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}
