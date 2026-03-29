import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;

/// Ergebnis der Routen-Qualitätsprüfung.
class RouteQualityResult {
  const RouteQualityResult({
    required this.overlapPercent,
    required this.uturnPositions,
    required this.isLoopClosed,
    required this.distanceInTolerance,
    required this.passed,
    this.actualDistanceKm,
    this.targetDistanceKm,
  });

  /// Prozent der Route die sich mit sich selbst überlappt (0-100).
  final double overlapPercent;

  /// Liste der Indizes wo Wendemanöver erkannt wurden (Bearing >150° in <200m).
  final List<int> uturnPositions;

  /// Ob Start und Ende <100m auseinander liegen (nur relevant für Rundkurse).
  final bool isLoopClosed;

  /// Ob die Distanz innerhalb ±12% der Zieldistanz liegt.
  final bool distanceInTolerance;

  /// Gesamtbewertung: true wenn alle Checks bestanden.
  final bool passed;

  final double? actualDistanceKm;
  final double? targetDistanceKm;

  @override
  String toString() {
    return 'RouteQuality(overlap=${overlapPercent.toStringAsFixed(1)}%, '
        'uturns=${uturnPositions.length}, '
        'loopClosed=$isLoopClosed, '
        'distOk=$distanceInTolerance, '
        'passed=$passed'
        '${actualDistanceKm != null ? ', ${actualDistanceKm!.toStringAsFixed(1)}km' : ''}'
        '${targetDistanceKm != null ? '/${targetDistanceKm!.toStringAsFixed(0)}km' : ''})';
  }
}

/// Prüft die Qualität einer generierten Route.
///
/// Erkennt Backtracking, Wendemanöver, nicht geschlossene Schleifen
/// und Distanz-Abweichungen. Debug-Output im Console-Log.
class RouteQualityValidator {
  const RouteQualityValidator();

  /// Maximaler Overlap-Prozentsatz bevor die Route als schlecht gilt.
  static const double maxOverlapPercent = 15.0;

  /// Minimaler Bearing-Winkel der als U-Turn gilt (Grad).
  static const double uturnBearingThreshold = 150.0;

  /// Maximale Distanz in der ein U-Turn erkannt wird (Meter).
  static const double uturnDistanceThreshold = 200.0;

  /// Maximale Distanz zwischen Start und Ende für geschlossene Schleife (Meter).
  static const double loopCloseThreshold = 100.0;

  /// Distanz-Toleranz (±12%).
  static const double distanceTolerance = 0.12;

  /// Minimale Distanz zwischen zwei Segmenten um als Overlap zu gelten (Meter).
  static const double overlapProximity = 40.0;

  /// Minimaler Index-Abstand damit ein Punkt als Overlap zählt
  /// (verhindert False-Positives bei benachbarten Segmenten).
  static const int overlapMinIndexGap = 30;

  // ════════════════════════════════════════════════════════════════════════

  /// Berechnet den Overlap-Score: wie viel Prozent der Route sich
  /// mit sich selbst überlappt (Backtracking-Erkennung).
  ///
  /// Algorithmus: Samplet jeden 5. Punkt und prüft ob ein anderes
  /// Segment (>30 Indizes entfernt) <40m nahe kommt.
  double validateOverlap(List<List<double>> coordinates) {
    if (coordinates.length < 20) return 0.0;

    // Sampling: jeden 5. Punkt prüfen (Performance)
    const sampleStep = 5;
    var overlapCount = 0;
    var sampleCount = 0;

    for (var i = 0; i < coordinates.length; i += sampleStep) {
      sampleCount++;
      final ci = coordinates[i];
      if (ci.length < 2) continue;

      var foundOverlap = false;
      // Prüfe gegen alle Punkte die >minIndexGap entfernt sind
      for (var j = i + overlapMinIndexGap;
          j < coordinates.length;
          j += sampleStep) {
        final cj = coordinates[j];
        if (cj.length < 2) continue;

        final dist = geo.Geolocator.distanceBetween(
          ci[1], ci[0], cj[1], cj[0],
        );
        if (dist < overlapProximity) {
          foundOverlap = true;
          break;
        }
      }
      if (foundOverlap) overlapCount++;
    }

    if (sampleCount == 0) return 0.0;
    return (overlapCount / sampleCount) * 100.0;
  }

  /// Erkennt Wendemanöver: Bearing-Änderung >150° innerhalb <200m.
  /// Gibt die Indizes der erkannten U-Turns zurück.
  List<int> validateNoUturns(List<List<double>> coordinates) {
    if (coordinates.length < 10) return const [];

    final uturns = <int>[];

    // Bearing in Segmenten berechnen, Wendepunkte finden
    for (var i = 2; i < coordinates.length - 2; i++) {
      final prev = coordinates[i - 2];
      final curr = coordinates[i];
      final next = coordinates[i + 2];
      if (prev.length < 2 || curr.length < 2 || next.length < 2) continue;

      // Distanz zwischen prev und next muss <200m sein
      final segDist = geo.Geolocator.distanceBetween(
        prev[1], prev[0], next[1], next[0],
      );
      if (segDist > uturnDistanceThreshold) continue;

      // Bearing vor und nach dem Punkt
      final bearingBefore = _bearing(prev[1], prev[0], curr[1], curr[0]);
      final bearingAfter = _bearing(curr[1], curr[0], next[1], next[0]);
      final delta = _angleDiff(bearingBefore, bearingAfter).abs();

      if (delta > uturnBearingThreshold) {
        uturns.add(i);
        // Skip 10 Punkte nach einem U-Turn (selber Bereich)
        i += 10;
      }
    }

    return uturns;
  }

  /// Prüft ob Start und Endpunkt <100m auseinander liegen (Rundkurs).
  bool validateLoopClosed(List<List<double>> coordinates) {
    if (coordinates.length < 2) return false;

    final start = coordinates.first;
    final end = coordinates.last;
    if (start.length < 2 || end.length < 2) return false;

    final dist = geo.Geolocator.distanceBetween(
      start[1], start[0], end[1], end[0],
    );
    return dist <= loopCloseThreshold;
  }

  /// Prüft ob die tatsächliche Distanz innerhalb ±12% der Zieldistanz liegt.
  bool validateDistanceTolerance(double targetKm, double actualKm) {
    if (targetKm <= 0) return true;
    final ratio = actualKm / targetKm;
    return ratio >= (1.0 - distanceTolerance) &&
        ratio <= (1.0 + distanceTolerance);
  }

  /// Gesamtbewertung: führt alle Checks durch und gibt ein Ergebnis zurück.
  ///
  /// [isRoundTrip]: Wenn true, wird auch der Loop-Check durchgeführt.
  /// [targetDistanceKm]: Zieldistanz für Distanz-Check (0 = skip).
  RouteQualityResult validateQuality({
    required List<List<double>> coordinates,
    required bool isRoundTrip,
    double targetDistanceKm = 0,
    double actualDistanceKm = 0,
  }) {
    final overlap = validateOverlap(coordinates);
    final uturns = validateNoUturns(coordinates);
    final loopClosed = isRoundTrip ? validateLoopClosed(coordinates) : true;
    final distOk = targetDistanceKm > 0
        ? validateDistanceTolerance(targetDistanceKm, actualDistanceKm)
        : true;

    final passed = overlap <= maxOverlapPercent &&
        uturns.isEmpty &&
        loopClosed &&
        distOk;

    final result = RouteQualityResult(
      overlapPercent: overlap,
      uturnPositions: uturns,
      isLoopClosed: loopClosed,
      distanceInTolerance: distOk,
      passed: passed,
      actualDistanceKm: actualDistanceKm > 0 ? actualDistanceKm : null,
      targetDistanceKm: targetDistanceKm > 0 ? targetDistanceKm : null,
    );

    // Debug-Output im Console-Log
    debugPrint('[RouteQuality] $result');

    return result;
  }

  // ── Helper ─────────────────────────────────────────────────────────────

  /// Bearing von Punkt A nach Punkt B in Grad (0–360).
  static double _bearing(double lat1, double lng1, double lat2, double lng2) {
    final lat1R = lat1 * math.pi / 180;
    final lat2R = lat2 * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2R);
    final x = math.cos(lat1R) * math.sin(lat2R) -
        math.sin(lat1R) * math.cos(lat2R) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// Kleinster Winkelunterschied zwischen zwei Bearings (-180..+180).
  static double _angleDiff(double from, double to) {
    var diff = (to - from) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }
}
