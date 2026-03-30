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

enum RouteQualityTier { ideal, acceptable, poor }

class RouteQualityClassification {
  const RouteQualityClassification({required this.tier, required this.score});

  final RouteQualityTier tier;
  final double score;

  bool get isIdeal => tier == RouteQualityTier.ideal;
  bool get isAcceptable => tier != RouteQualityTier.poor;
}

/// Prüft die Qualität einer generierten Route.
///
/// Erkennt Backtracking, Wendemanöver, nicht geschlossene Schleifen
/// und Distanz-Abweichungen. Debug-Output im Console-Log.
class RouteQualityValidator {
  const RouteQualityValidator();

  /// Maximaler Overlap-Prozentsatz bevor die Route als schlecht gilt.
  static const double maxOverlapPercent = 15.0;
  static const double roundTripMaxOverlapPercent = 20.0;

  /// Minimaler Bearing-Winkel der als U-Turn gilt (Grad).
  static const double uturnBearingThreshold = 140.0;

  /// Maximale Distanz in der ein U-Turn erkannt wird (Meter).
  static const double uturnDistanceThreshold = 300.0;

  /// Maximale Distanz zwischen Start und Ende für geschlossene Schleife (Meter).
  static const double loopCloseThreshold = 100.0;

  /// Distanz-Toleranz (±10%).
  static const double distanceTolerance = 0.10;

  /// Minimale Distanz zwischen zwei Segmenten um als Overlap zu gelten (Meter).
  static const double overlapProximity = 50.0;

  /// Minimaler Index-Abstand damit ein Punkt als Overlap zählt
  /// (verhindert False-Positives bei benachbarten Segmenten).
  static const int overlapMinIndexGap = 30;

  // ════════════════════════════════════════════════════════════════════════

  /// Berechnet den Overlap-Score: wie viel Prozent der Route sich
  /// mit sich selbst überlappt (Backtracking-Erkennung).
  ///
  /// Algorithmus: Samplet jeden 5. Punkt und prüft ob ein anderes
  /// Segment (>30 Indizes entfernt) <50m nahe kommt und die lokale
  /// Fahrtrichtung ähnlich oder gegensinnig ist. So werden Kreuzungen
  /// weniger hart bestraft, echtes Hin-und-Zurück aber sicher erkannt.
  double validateOverlap(List<List<double>> coordinates) {
    if (coordinates.length < 20) return 0.0;

    // Sampling: jeden 5. Punkt prüfen (Performance)
    const sampleStep = 4;
    var overlapCount = 0;
    var sampleCount = 0;

    for (var i = 0; i < coordinates.length; i += sampleStep) {
      sampleCount++;
      final ci = coordinates[i];
      if (ci.length < 2) continue;
      final headingI = _localHeading(coordinates, i);

      var foundOverlap = false;
      // Prüfe gegen alle Punkte die >minIndexGap entfernt sind
      for (
        var j = i + overlapMinIndexGap;
        j < coordinates.length;
        j += sampleStep
      ) {
        final cj = coordinates[j];
        if (cj.length < 2) continue;

        final dist = geo.Geolocator.distanceBetween(ci[1], ci[0], cj[1], cj[0]);
        if (dist >= overlapProximity) continue;

        final headingJ = _localHeading(coordinates, j);
        final headingDelta = _angleDiff(headingI, headingJ).abs();
        final alignedDirection = headingDelta <= 35.0;
        final oppositeDirection = headingDelta >= 145.0;

        if (alignedDirection || oppositeDirection) {
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
        prev[1],
        prev[0],
        next[1],
        next[0],
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
      start[1],
      start[0],
      end[1],
      end[0],
    );
    return dist <= loopCloseThreshold;
  }

  /// Prüft ob die tatsächliche Distanz innerhalb ±12% der Zieldistanz liegt.
  bool validateDistanceTolerance(
    double targetKm,
    double actualKm, {
    double tolerancePercent = distanceTolerance,
  }) {
    if (targetKm <= 0) return true;
    final ratio = actualKm / targetKm;
    return ratio >= (1.0 - tolerancePercent) &&
        ratio <= (1.0 + tolerancePercent);
  }

  double roundTripDistanceTolerance(double targetKm) {
    if (targetKm <= 0) return distanceTolerance;
    if (targetKm <= 60) return 0.18;
    if (targetKm <= 100) return 0.16;
    return 0.14;
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
    final effectiveDistanceTolerance = isRoundTrip
        ? roundTripDistanceTolerance(targetDistanceKm)
        : distanceTolerance;
    final distOk = targetDistanceKm > 0
        ? validateDistanceTolerance(
            targetDistanceKm,
            actualDistanceKm,
            tolerancePercent: effectiveDistanceTolerance,
          )
        : true;
    final overlapThreshold = isRoundTrip
        ? roundTripMaxOverlapPercent
        : maxOverlapPercent;

    final passed =
        overlap <= overlapThreshold && uturns.isEmpty && loopClosed && distOk;

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

  RouteQualityClassification classifyGeneratedRoute({
    required RouteQualityResult quality,
    required bool isRoundTrip,
    required int coordinateCount,
    required double actualDistanceKm,
    double targetDistanceKm = 0,
  }) {
    final effectiveTarget = targetDistanceKm > 0
        ? targetDistanceKm
        : (actualDistanceKm > 0 ? actualDistanceKm : 1.0);
    final distanceDeltaPercent = effectiveTarget > 0
        ? ((actualDistanceKm - effectiveTarget).abs() / effectiveTarget)
        : 0.0;

    final idealMinCoordinates = isRoundTrip
        ? (effectiveTarget >= 100
              ? 42
              : effectiveTarget >= 70
              ? 34
              : 26)
        : (actualDistanceKm >= 30 ? 28 : 20);
    final acceptableMinCoordinates = isRoundTrip
        ? (effectiveTarget >= 100
              ? 28
              : effectiveTarget >= 70
              ? 24
              : 18)
        : (actualDistanceKm >= 30 ? 20 : 14);

    final idealDistanceOk = targetDistanceKm <= 0
        ? true
        : distanceDeltaPercent <= roundTripDistanceTolerance(targetDistanceKm);
    final acceptableDistanceOk = targetDistanceKm <= 0
        ? true
        : distanceDeltaPercent <=
              (roundTripDistanceTolerance(targetDistanceKm) + 0.08);

    final idealOverlap = isRoundTrip
        ? roundTripMaxOverlapPercent
        : maxOverlapPercent;
    final acceptableOverlap = isRoundTrip ? 28.0 : 20.0;

    final pointPenalty = coordinateCount < acceptableMinCoordinates
        ? (acceptableMinCoordinates - coordinateCount) * 2.0
        : coordinateCount < idealMinCoordinates
        ? (idealMinCoordinates - coordinateCount) * 0.8
        : 0.0;
    final score =
        quality.overlapPercent +
        quality.uturnPositions.length * 18 +
        distanceDeltaPercent * 100 * 1.6 +
        pointPenalty +
        (!quality.isLoopClosed ? 80 : 0);

    if (!quality.isLoopClosed || quality.uturnPositions.isNotEmpty) {
      return RouteQualityClassification(
        tier: RouteQualityTier.poor,
        score: score + 90,
      );
    }

    if (coordinateCount < acceptableMinCoordinates ||
        quality.overlapPercent > acceptableOverlap ||
        !acceptableDistanceOk) {
      return RouteQualityClassification(
        tier: RouteQualityTier.poor,
        score: score + 24,
      );
    }

    if (coordinateCount >= idealMinCoordinates &&
        quality.overlapPercent <= idealOverlap &&
        idealDistanceOk) {
      return RouteQualityClassification(
        tier: RouteQualityTier.ideal,
        score: score,
      );
    }

    return RouteQualityClassification(
      tier: RouteQualityTier.acceptable,
      score: score + 6,
    );
  }

  /// Baut einen kompakten Fingerprint aus Distanz, Punktzahl und
  /// gleichmäßig verteilten Sample-Punkten.
  ///
  /// Das dient dazu, nahezu identische Routen bei wiederholter Generierung
  /// derselben Konfiguration zu erkennen und erneut generieren zu lassen.
  static String buildRouteFingerprint(
    List<List<double>> coordinates, {
    double? distanceKm,
    int sampleCount = 10,
    int precision = 4,
  }) {
    if (coordinates.isEmpty) {
      return 'empty';
    }

    final effectiveSamples = math.max(
      2,
      math.min(sampleCount, coordinates.length),
    );
    final parts = <String>[
      'n:${coordinates.length}',
      if (distanceKm != null) 'd:${distanceKm.toStringAsFixed(1)}',
    ];

    for (var i = 0; i < effectiveSamples; i++) {
      final ratio = effectiveSamples == 1 ? 0.0 : i / (effectiveSamples - 1);
      final index = ((coordinates.length - 1) * ratio).round();
      final point = coordinates[index];
      if (point.length < 2) continue;
      parts.add(
        '${point[0].toStringAsFixed(precision)},${point[1].toStringAsFixed(precision)}',
      );
    }

    return parts.join('|');
  }

  /// Schätzt die geometrische Ähnlichkeit zweier Routen (0-100%).
  ///
  /// Beide Routen werden auf eine feste Anzahl Punkte gesampelt. Für jeden
  /// Sample-Punkt wird geprüft, ob auf der jeweils anderen Route ein naher
  /// Punkt liegt. Das Ergebnis ist der Mittelwert beider Richtungen.
  static double calculateRouteSimilarityPercent(
    List<List<double>> first,
    List<List<double>> second, {
    int sampleCount = 40,
    double proximityMeters = 120.0,
  }) {
    if (first.length < 2 || second.length < 2) return 0.0;

    final firstSamples = _sampleRoute(first, sampleCount: sampleCount);
    final secondSamples = _sampleRoute(second, sampleCount: sampleCount);
    if (firstSamples.isEmpty || secondSamples.isEmpty) return 0.0;

    final forward = _percentPointsNearOtherRoute(
      source: firstSamples,
      target: secondSamples,
      proximityMeters: proximityMeters,
    );
    final backward = _percentPointsNearOtherRoute(
      source: secondSamples,
      target: firstSamples,
      proximityMeters: proximityMeters,
    );
    return (forward + backward) / 2.0;
  }

  /// Prüft, ob die neue Route einer der vorherigen Routen zu ähnlich ist.
  static bool isRouteTooSimilarToPrevious(
    List<List<double>> candidate,
    Iterable<List<List<double>>> previousRoutes, {
    double thresholdPercent = 78.0,
    int sampleCount = 40,
    double proximityMeters = 120.0,
  }) {
    for (final previous in previousRoutes) {
      final similarity = calculateRouteSimilarityPercent(
        candidate,
        previous,
        sampleCount: sampleCount,
        proximityMeters: proximityMeters,
      );
      if (similarity >= thresholdPercent) {
        return true;
      }
    }
    return false;
  }

  static List<List<double>> _sampleRoute(
    List<List<double>> coordinates, {
    required int sampleCount,
  }) {
    if (coordinates.isEmpty) return const [];
    final effectiveSamples = math.max(
      2,
      math.min(sampleCount, coordinates.length),
    );
    final samples = <List<double>>[];
    for (var i = 0; i < effectiveSamples; i++) {
      final ratio = effectiveSamples == 1 ? 0.0 : i / (effectiveSamples - 1);
      final index = ((coordinates.length - 1) * ratio).round();
      final point = coordinates[index];
      if (point.length < 2) continue;
      samples.add([point[0], point[1]]);
    }
    return samples;
  }

  static double _percentPointsNearOtherRoute({
    required List<List<double>> source,
    required List<List<double>> target,
    required double proximityMeters,
  }) {
    if (source.isEmpty || target.isEmpty) return 0.0;
    var nearCount = 0;
    for (final sourcePoint in source) {
      if (sourcePoint.length < 2) continue;
      var minDistance = double.infinity;
      for (final targetPoint in target) {
        if (targetPoint.length < 2) continue;
        final distance = geo.Geolocator.distanceBetween(
          sourcePoint[1],
          sourcePoint[0],
          targetPoint[1],
          targetPoint[0],
        );
        if (distance < minDistance) {
          minDistance = distance;
        }
        if (minDistance <= proximityMeters) {
          break;
        }
      }
      if (minDistance <= proximityMeters) {
        nearCount++;
      }
    }
    return (nearCount / source.length) * 100.0;
  }

  // ── Helper ─────────────────────────────────────────────────────────────

  /// Bearing von Punkt A nach Punkt B in Grad (0–360).
  static double _bearing(double lat1, double lng1, double lat2, double lng2) {
    final lat1R = lat1 * math.pi / 180;
    final lat2R = lat2 * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2R);
    final x =
        math.cos(lat1R) * math.sin(lat2R) -
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

  static double _localHeading(List<List<double>> coordinates, int index) {
    if (coordinates.length < 2) return 0.0;
    final startIndex = math.max(0, math.min(index, coordinates.length - 2));
    final endIndex = math.min(coordinates.length - 1, startIndex + 1);
    final from = coordinates[startIndex];
    final to = coordinates[endIndex];
    if (from.length < 2 || to.length < 2) return 0.0;
    return _bearing(from[1], from[0], to[1], to[0]);
  }
}
