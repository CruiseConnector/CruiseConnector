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
    this.returnPathPercent = 0.0,
    this.actualDistanceKm,
    this.targetDistanceKm,
    this.centerReentryCount = 0,
    this.radialPeakCount = 0,
    this.corridorSwitchCount = 0,
    this.progressReversalCount = 0,
    this.microZigzagCount = 0,
    this.middleCoverageRatio = 0.0,
    this.shapePenalty = 0.0,
    this.scenicLoopScore = 0.0,
    this.centerRecrossPercent = 0.0,
    this.spurArmCount = 0,
    this.spurArmPercent = 0.0,
    this.compactnessScore = 0.0,
    this.foldedAreaPenalty = 0.0,
    this.repeatedStartAreaPercent = 0.0,
    this.microZigzagPercent = 0.0,
    this.dominantLoopScore = 0.0,
    this.styleFitScore = 0.0,
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
  final double returnPathPercent;

  final double? actualDistanceKm;
  final double? targetDistanceKm;
  final int centerReentryCount;
  final int radialPeakCount;
  final int corridorSwitchCount;
  final int progressReversalCount;
  final int microZigzagCount;
  final double middleCoverageRatio;
  final double shapePenalty;
  final double scenicLoopScore;
  final double centerRecrossPercent;
  final int spurArmCount;
  final double spurArmPercent;
  final double compactnessScore;
  final double foldedAreaPenalty;
  final double repeatedStartAreaPercent;
  final double microZigzagPercent;
  final double dominantLoopScore;
  final double styleFitScore;

  @override
  String toString() {
    return 'RouteQuality(overlap=${overlapPercent.toStringAsFixed(1)}%, '
        'uturns=${uturnPositions.length}, '
        'loopClosed=$isLoopClosed, '
        'returnPath=${returnPathPercent.toStringAsFixed(1)}%, '
        'shapePenalty=${shapePenalty.toStringAsFixed(1)}, '
        'center=${centerRecrossPercent.toStringAsFixed(0)}%, '
        'spurs=$spurArmCount/${spurArmPercent.toStringAsFixed(0)}%, '
        'folded=${foldedAreaPenalty.toStringAsFixed(0)}%, '
        'start=${repeatedStartAreaPercent.toStringAsFixed(0)}%, '
        'zigzag=${microZigzagPercent.toStringAsFixed(0)}%, '
        'loop=${dominantLoopScore.toStringAsFixed(0)}, '
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

  /// Maximal erlaubter Anteil der Route, der einem Rückweg entlang derselben
  /// Straße entspricht (für Rundkurse).
  static const double maxReturnPathPercent = 36.0;

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

  /// Schätzt, wie stark sich zweite und erste Routenhälfte in entgegengesetzter
  /// Richtung überdecken (klassisches Hin-und-zurück-Muster).
  double estimateReturnPathPercent(
    List<List<double>> coordinates, {
    double proximityMeters = 85.0,
    int sampleCount = 22,
  }) {
    if (coordinates.length < 24) return 0.0;

    final half = coordinates.length ~/ 2;
    if (half < 12) return 0.0;
    final firstHalf = coordinates.sublist(0, half);
    final secondHalfReversed = coordinates.sublist(half).reversed.toList();
    final sampledA = _sampleRoute(firstHalf, sampleCount: sampleCount);
    final sampledB = _sampleRoute(secondHalfReversed, sampleCount: sampleCount);
    if (sampledA.isEmpty || sampledB.isEmpty) return 0.0;

    final pairedCount = math.min(sampledA.length, sampledB.length);
    var nearPairs = 0;
    for (var i = 0; i < pairedCount; i++) {
      final a = sampledA[i];
      final b = sampledB[i];
      if (a.length < 2 || b.length < 2) continue;
      final dist = geo.Geolocator.distanceBetween(a[1], a[0], b[1], b[0]);
      if (dist <= proximityMeters) nearPairs++;
    }
    if (pairedCount == 0) return 0.0;
    return (nearPairs / pairedCount) * 100.0;
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
    final shape = _analyzeRouteShape(
      coordinates: coordinates,
      isRoundTrip: isRoundTrip,
    );
    final overlap = validateOverlap(coordinates);
    final uturns = validateNoUturns(coordinates);
    final loopClosed = isRoundTrip ? validateLoopClosed(coordinates) : true;
    final returnPathPercent = isRoundTrip
        ? estimateReturnPathPercent(coordinates)
        : 0.0;
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
        overlap <= overlapThreshold &&
        uturns.isEmpty &&
        loopClosed &&
        distOk &&
        (!isRoundTrip || returnPathPercent <= maxReturnPathPercent) &&
        shape.shapePenalty < (isRoundTrip ? 90.0 : 72.0);

    final result = RouteQualityResult(
      overlapPercent: overlap,
      uturnPositions: uturns,
      isLoopClosed: loopClosed,
      distanceInTolerance: distOk,
      passed: passed,
      returnPathPercent: returnPathPercent,
      actualDistanceKm: actualDistanceKm > 0 ? actualDistanceKm : null,
      targetDistanceKm: targetDistanceKm > 0 ? targetDistanceKm : null,
      centerReentryCount: shape.centerReentryCount,
      radialPeakCount: shape.radialPeakCount,
      corridorSwitchCount: shape.corridorSwitchCount,
      progressReversalCount: shape.progressReversalCount,
      microZigzagCount: shape.microZigzagCount,
      middleCoverageRatio: shape.middleCoverageRatio,
      shapePenalty: shape.shapePenalty,
      scenicLoopScore: shape.scenicLoopScore,
      centerRecrossPercent: shape.centerRecrossPercent,
      spurArmCount: shape.spurArmCount,
      spurArmPercent: shape.spurArmPercent,
      compactnessScore: shape.compactnessScore,
      foldedAreaPenalty: shape.foldedAreaPenalty,
      repeatedStartAreaPercent: shape.repeatedStartAreaPercent,
      microZigzagPercent: shape.microZigzagPercent,
      dominantLoopScore: shape.dominantLoopScore,
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
    String? styleProfileKey,
    double styleFitScore = 0.0,
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
    final idealReturnPath = isRoundTrip ? 18.0 : double.infinity;
    final acceptableReturnPath = isRoundTrip
        ? maxReturnPathPercent
        : double.infinity;

    final pointPenalty = coordinateCount < acceptableMinCoordinates
        ? (acceptableMinCoordinates - coordinateCount) * 2.0
        : coordinateCount < idealMinCoordinates
        ? (idealMinCoordinates - coordinateCount) * 0.8
        : 0.0;
    final score =
        quality.overlapPercent +
        quality.uturnPositions.length * 18 +
        distanceDeltaPercent * 100 * 1.6 +
        (isRoundTrip ? quality.returnPathPercent * 1.4 : 0.0) +
        quality.shapePenalty +
        quality.centerRecrossPercent * (isRoundTrip ? 0.22 : 0.08) +
        quality.spurArmPercent * (isRoundTrip ? 0.28 : 0.10) +
        quality.foldedAreaPenalty * (isRoundTrip ? 0.32 : 0.12) +
        quality.repeatedStartAreaPercent * (isRoundTrip ? 0.24 : 0.06) +
        quality.microZigzagPercent * 0.20 +
        pointPenalty +
        _styleSpecificShapePenalty(
          quality: quality,
          isRoundTrip: isRoundTrip,
          styleProfileKey: styleProfileKey,
        ) -
        styleFitScore * 0.22 -
        quality.dominantLoopScore * (isRoundTrip ? 0.26 : 0.08) -
        quality.scenicLoopScore * (isRoundTrip ? 0.18 : 0.14) +
        (!quality.isLoopClosed ? 80 : 0);

    final severeRoundTripShape =
        isRoundTrip &&
        (quality.centerReentryCount >= 2 ||
            quality.radialPeakCount >= 4 ||
            quality.middleCoverageRatio < 0.42);
    final severePointShape =
        !isRoundTrip &&
        (quality.corridorSwitchCount >= 4 ||
            quality.progressReversalCount >= 2);

    if (!quality.isLoopClosed ||
        quality.uturnPositions.isNotEmpty ||
        (isRoundTrip && quality.returnPathPercent > acceptableReturnPath) ||
        severeRoundTripShape ||
        severePointShape) {
      return RouteQualityClassification(
        tier: RouteQualityTier.poor,
        score: score + 90,
      );
    }

    if (coordinateCount < acceptableMinCoordinates ||
        quality.overlapPercent > acceptableOverlap ||
        !acceptableDistanceOk ||
        quality.foldedAreaPenalty > (isRoundTrip ? 78.0 : 88.0) ||
        quality.repeatedStartAreaPercent > (isRoundTrip ? 62.0 : 72.0) ||
        quality.microZigzagPercent > (isRoundTrip ? 48.0 : 54.0) ||
        quality.shapePenalty > (isRoundTrip ? 52.0 : 42.0)) {
      return RouteQualityClassification(
        tier: RouteQualityTier.poor,
        score: score + 24,
      );
    }

    if (coordinateCount >= idealMinCoordinates &&
        quality.overlapPercent <= idealOverlap &&
        idealDistanceOk &&
        (!isRoundTrip || quality.returnPathPercent <= idealReturnPath) &&
        quality.shapePenalty <= (isRoundTrip ? 18.0 : 14.0) &&
        quality.foldedAreaPenalty <= (isRoundTrip ? 36.0 : 50.0) &&
        quality.repeatedStartAreaPercent <= (isRoundTrip ? 20.0 : 28.0) &&
        quality.microZigzagPercent <= 24.0 &&
        quality.dominantLoopScore >= (isRoundTrip ? 62.0 : 48.0) &&
        (isRoundTrip
            ? quality.centerReentryCount == 0 &&
                  quality.centerRecrossPercent <= 16.0 &&
                  quality.spurArmPercent <= 22.0 &&
                  quality.middleCoverageRatio >= 0.58
            : quality.corridorSwitchCount <= 1 &&
                  quality.progressReversalCount == 0)) {
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

  static _RouteShapeMetrics _analyzeRouteShape({
    required List<List<double>> coordinates,
    required bool isRoundTrip,
  }) {
    final sampled = _sampleRoute(
      coordinates,
      sampleCount: isRoundTrip ? 28 : 26,
    );
    if (sampled.length < 6) {
      return const _RouteShapeMetrics();
    }

    final projected = _projectToMeters(sampled);
    final diagonalMeters = _boundingDiagonal(projected);
    final startProjected = projected.isNotEmpty ? projected.first : null;
    final centerProjected = projected.isNotEmpty
        ? _centroid(projected)
        : const _ProjectedPoint(x: 0.0, y: 0.0);

    final microZigzags = _countMicroZigzags(sampled);
    final microZigzagPercent = sampled.length > 3
        ? ((microZigzags / (sampled.length - 3)) * 100.0).clamp(0.0, 100.0)
        : 0.0;
    final compactnessScore = _estimateCompactnessScore(projected);
    final foldedAreaPenalty = _estimateFoldedAreaPenalty(
      projected,
      compactnessScore: compactnessScore,
    );
    if (isRoundTrip) {
      final start = sampled.first;
      final distances = sampled
          .map(
            (point) => geo.Geolocator.distanceBetween(
              start[1],
              start[0],
              point[1],
              point[0],
            ),
          )
          .toList();
      final maxDistance = distances.fold<double>(
        0.0,
        (maxValue, value) => math.max(maxValue, value),
      );
      if (maxDistance <= 0) {
        return const _RouteShapeMetrics();
      }

      final startRadiusMeters = (maxDistance * 0.24).clamp(450.0, 1700.0);
      final smoothed = _smoothSeries(distances);
      final repeatedStartClusters = _countCenterReentries(
        smoothed,
        radiusMeters: startRadiusMeters,
      );
      final radialPeakCount = _countMajorPeaks(
        smoothed,
        minimumHeight: maxDistance * 0.62,
      );
      final centerRecrossClusters = projected.length >= 8
          ? _countProjectedVisitClusters(
              projected,
              target: centerProjected,
              radiusMeters: (diagonalMeters * 0.12).clamp(160.0, 520.0),
              skipLeadingFraction: 0.12,
              skipTrailingFraction: 0.12,
            )
          : 0;
      final repeatedStartAreaPercent = ((repeatedStartClusters / 2.5) * 100.0)
          .clamp(0.0, 100.0);
      final centerRecrossPercent = ((centerRecrossClusters / 3.0) * 100.0)
          .clamp(0.0, 100.0);
      final spurArmCount = math.max(0, radialPeakCount - 1);
      final spurArmPercent = ((spurArmCount / 3.0) * 100.0).clamp(0.0, 100.0);
      final middleCoverageRatio = _middleCoverageRatio(
        smoothed,
        maxDistance: maxDistance,
      );
      final shapePenalty =
          centerRecrossPercent * 0.28 +
          repeatedStartAreaPercent * 0.20 +
          spurArmPercent * 0.34 +
          foldedAreaPenalty * 0.26 +
          math.max(0.0, 0.60 - middleCoverageRatio) * 80.0 +
          microZigzagPercent * 0.30;
      final scenicLoopScore =
          middleCoverageRatio * 38.0 +
          compactnessScore * 0.18 +
          (100.0 - foldedAreaPenalty) * 0.20 +
          (100.0 - repeatedStartAreaPercent) * 0.10 +
          (100.0 - centerRecrossPercent) * 0.10 -
          spurArmPercent * 0.10 -
          microZigzagPercent * 0.10;
      final dominantLoopScore =
          middleCoverageRatio * 32.0 +
          compactnessScore * 0.22 +
          (100.0 - foldedAreaPenalty) * 0.22 +
          (100.0 - repeatedStartAreaPercent) * 0.12 +
          (100.0 - centerRecrossPercent) * 0.12;

      return _RouteShapeMetrics(
        centerReentryCount: centerRecrossClusters,
        radialPeakCount: radialPeakCount,
        spurArmCount: spurArmCount,
        microZigzagCount: microZigzags,
        middleCoverageRatio: middleCoverageRatio,
        shapePenalty: shapePenalty,
        scenicLoopScore: scenicLoopScore,
        centerRecrossPercent: centerRecrossPercent,
        spurArmPercent: spurArmPercent,
        compactnessScore: compactnessScore,
        foldedAreaPenalty: foldedAreaPenalty,
        repeatedStartAreaPercent: repeatedStartAreaPercent,
        microZigzagPercent: microZigzagPercent,
        dominantLoopScore: dominantLoopScore.clamp(0.0, 100.0),
      );
    }

    final start = sampled.first;
    final end = sampled.last;
    final corridorSwitches = _countCorridorSideSwitches(
      sampled,
      start: start,
      end: end,
    );
    final progressReversals = _countProgressReversals(
      sampled,
      start: start,
      end: end,
    );
    final directDistanceMeters = geo.Geolocator.distanceBetween(
      start[1],
      start[0],
      end[1],
      end[0],
    );
    final averageCorridorOffset = _averageCorridorOffsetRatio(
      sampled,
      start: start,
      end: end,
      directDistanceMeters: directDistanceMeters,
    );
    final repeatedStartClusters = startProjected == null
        ? 0
        : _countProjectedVisitClusters(
            projected,
            target: startProjected,
            radiusMeters: (diagonalMeters * 0.10).clamp(140.0, 320.0),
            skipLeadingFraction: 0.12,
            skipTrailingFraction: 0.06,
          );
    final repeatedStartAreaPercent = ((repeatedStartClusters / 2.0) * 100.0)
        .clamp(0.0, 100.0);
    final centerRecrossClusters = projected.length >= 8
        ? _countProjectedVisitClusters(
            projected,
            target: centerProjected,
            radiusMeters: (diagonalMeters * 0.10).clamp(140.0, 320.0),
            skipLeadingFraction: 0.18,
            skipTrailingFraction: 0.12,
          )
        : 0;
    final centerRecrossPercent = ((centerRecrossClusters / 3.0) * 100.0).clamp(
      0.0,
      100.0,
    );
    final shapePenalty =
        corridorSwitches * 14.0 +
        progressReversals * 18.0 +
        repeatedStartAreaPercent * 0.20 +
        centerRecrossPercent * 0.10 +
        foldedAreaPenalty * 0.08 +
        microZigzagPercent * 0.24 +
        math.max(0.0, 0.08 - averageCorridorOffset) * 45.0;
    final scenicLoopScore =
        averageCorridorOffset * 60.0 +
        compactnessScore * 0.08 +
        (100.0 - foldedAreaPenalty) * 0.08 -
        corridorSwitches * 10.0 -
        progressReversals * 14.0 -
        microZigzagPercent * 0.10;
    final dominantLoopScore =
        averageCorridorOffset * 60.0 +
        compactnessScore * 0.10 +
        (100.0 - repeatedStartAreaPercent) * 0.10 +
        (100.0 - microZigzagPercent) * 0.10;

    return _RouteShapeMetrics(
      corridorSwitchCount: corridorSwitches,
      progressReversalCount: progressReversals,
      microZigzagCount: microZigzags,
      middleCoverageRatio: averageCorridorOffset,
      shapePenalty: shapePenalty,
      scenicLoopScore: scenicLoopScore,
      centerRecrossPercent: centerRecrossPercent,
      compactnessScore: compactnessScore,
      foldedAreaPenalty: foldedAreaPenalty,
      repeatedStartAreaPercent: repeatedStartAreaPercent,
      microZigzagPercent: microZigzagPercent,
      dominantLoopScore: dominantLoopScore.clamp(0.0, 100.0),
    );
  }

  static List<double> _smoothSeries(List<double> values) {
    if (values.length < 3) return values;
    return List<double>.generate(values.length, (index) {
      final start = math.max(0, index - 1);
      final end = math.min(values.length - 1, index + 1);
      var sum = 0.0;
      var count = 0;
      for (var i = start; i <= end; i++) {
        sum += values[i];
        count++;
      }
      return count == 0 ? values[index] : sum / count;
    });
  }

  static int _countCenterReentries(
    List<double> distances, {
    required double radiusMeters,
  }) {
    if (distances.length < 6) return 0;
    var hasLeftStart = false;
    var previousInside = true;
    var reentries = 0;
    for (var i = 1; i < distances.length - 1; i++) {
      final inside = distances[i] <= radiusMeters;
      if (!hasLeftStart && !inside) {
        hasLeftStart = true;
      } else if (hasLeftStart &&
          inside &&
          !previousInside &&
          i < distances.length - 3) {
        reentries++;
      }
      previousInside = inside;
    }
    return reentries;
  }

  static int _countMajorPeaks(
    List<double> values, {
    required double minimumHeight,
  }) {
    if (values.length < 5) return 0;
    var peaks = 0;
    for (var i = 2; i < values.length - 2; i++) {
      final current = values[i];
      if (current < minimumHeight) continue;
      if (current >= values[i - 1] &&
          current >= values[i + 1] &&
          current > values[i - 2] &&
          current > values[i + 2]) {
        peaks++;
      }
    }
    return peaks;
  }

  static double _middleCoverageRatio(
    List<double> distances, {
    required double maxDistance,
  }) {
    if (distances.length < 4 || maxDistance <= 0) return 0.0;
    final start = (distances.length * 0.22).floor();
    final end = (distances.length * 0.78).ceil();
    var sum = 0.0;
    var count = 0;
    for (var i = start; i < end && i < distances.length; i++) {
      sum += distances[i];
      count++;
    }
    if (count == 0) return 0.0;
    return (sum / count) / maxDistance;
  }

  static int _countMicroZigzags(List<List<double>> sampled) {
    if (sampled.length < 6) return 0;
    final headings = <double>[];
    for (var i = 0; i < sampled.length - 1; i++) {
      headings.add(
        _bearing(
          sampled[i][1],
          sampled[i][0],
          sampled[i + 1][1],
          sampled[i + 1][0],
        ),
      );
    }
    var count = 0;
    for (var i = 1; i < headings.length - 1; i++) {
      final first = _angleDiff(headings[i - 1], headings[i]);
      final second = _angleDiff(headings[i], headings[i + 1]);
      if (first.abs() >= 32 &&
          second.abs() >= 32 &&
          first.sign != second.sign &&
          (first.abs() + second.abs()) >= 85) {
        count++;
      }
    }
    return count;
  }

  static int _countCorridorSideSwitches(
    List<List<double>> sampled, {
    required List<double> start,
    required List<double> end,
  }) {
    final projected = sampled
        .map((point) => _crossTrackOffsetMeters(point, start: start, end: end))
        .where((value) => value.abs() >= 220.0)
        .toList();
    if (projected.length < 2) return 0;
    var switches = 0;
    var previousSign = projected.first.sign.toInt();
    for (final value in projected.skip(1)) {
      final sign = value.sign.toInt();
      if (sign != 0 && previousSign != 0 && sign != previousSign) {
        switches++;
      }
      previousSign = sign == 0 ? previousSign : sign;
    }
    return switches;
  }

  static int _countProgressReversals(
    List<List<double>> sampled, {
    required List<double> start,
    required List<double> end,
  }) {
    if (sampled.length < 3) return 0;
    var reversals = 0;
    var previousProgress = -1.0;
    for (final point in sampled) {
      final progress = _alongTrackFraction(point, start: start, end: end);
      if (previousProgress >= 0 && progress + 0.06 < previousProgress) {
        reversals++;
      }
      previousProgress = math.max(previousProgress, progress);
    }
    return reversals;
  }

  static double _averageCorridorOffsetRatio(
    List<List<double>> sampled, {
    required List<double> start,
    required List<double> end,
    required double directDistanceMeters,
  }) {
    if (sampled.isEmpty || directDistanceMeters <= 0) return 0.0;
    var sum = 0.0;
    var count = 0;
    for (final point in sampled.skip(1).take(math.max(1, sampled.length - 2))) {
      sum += _crossTrackOffsetMeters(point, start: start, end: end).abs();
      count++;
    }
    if (count == 0) return 0.0;
    return (sum / count) / directDistanceMeters;
  }

  static double _crossTrackOffsetMeters(
    List<double> point, {
    required List<double> start,
    required List<double> end,
  }) {
    final startMeters = _projectMeters(
      latitude: start[1],
      longitude: start[0],
      originLatitude: start[1],
      originLongitude: start[0],
    );
    final endMeters = _projectMeters(
      latitude: end[1],
      longitude: end[0],
      originLatitude: start[1],
      originLongitude: start[0],
    );
    final pointMeters = _projectMeters(
      latitude: point[1],
      longitude: point[0],
      originLatitude: start[1],
      originLongitude: start[0],
    );
    final dx = endMeters.$1 - startMeters.$1;
    final dy = endMeters.$2 - startMeters.$2;
    final px = pointMeters.$1 - startMeters.$1;
    final py = pointMeters.$2 - startMeters.$2;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return 0.0;
    return (px * dy - py * dx) / length;
  }

  static double _alongTrackFraction(
    List<double> point, {
    required List<double> start,
    required List<double> end,
  }) {
    final startMeters = _projectMeters(
      latitude: start[1],
      longitude: start[0],
      originLatitude: start[1],
      originLongitude: start[0],
    );
    final endMeters = _projectMeters(
      latitude: end[1],
      longitude: end[0],
      originLatitude: start[1],
      originLongitude: start[0],
    );
    final pointMeters = _projectMeters(
      latitude: point[1],
      longitude: point[0],
      originLatitude: start[1],
      originLongitude: start[0],
    );
    final dx = endMeters.$1 - startMeters.$1;
    final dy = endMeters.$2 - startMeters.$2;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) return 0.0;
    final px = pointMeters.$1 - startMeters.$1;
    final py = pointMeters.$2 - startMeters.$2;
    return ((px * dx + py * dy) / lengthSquared).clamp(0.0, 1.0);
  }

  static (double, double) _projectMeters({
    required double latitude,
    required double longitude,
    required double originLatitude,
    required double originLongitude,
  }) {
    const latFactor = 111320.0;
    final lngFactor = 111320.0 * math.cos(originLatitude * math.pi / 180.0);
    final x = (longitude - originLongitude) * lngFactor;
    final y = (latitude - originLatitude) * latFactor;
    return (x, y);
  }

  static List<_ProjectedPoint> _projectToMeters(List<List<double>> sampled) {
    if (sampled.isEmpty) return const [];
    final origin = sampled.first;
    return sampled.map((point) {
      final meters = _projectMeters(
        latitude: point[1],
        longitude: point[0],
        originLatitude: origin[1],
        originLongitude: origin[0],
      );
      return _ProjectedPoint(x: meters.$1, y: meters.$2);
    }).toList();
  }

  static _ProjectedPoint _centroid(List<_ProjectedPoint> points) {
    if (points.isEmpty) {
      return const _ProjectedPoint(x: 0.0, y: 0.0);
    }
    var sumX = 0.0;
    var sumY = 0.0;
    for (final point in points) {
      sumX += point.x;
      sumY += point.y;
    }
    return _ProjectedPoint(x: sumX / points.length, y: sumY / points.length);
  }

  static double _boundingDiagonal(List<_ProjectedPoint> points) {
    if (points.length < 2) return 0.0;
    var minX = points.first.x;
    var maxX = points.first.x;
    var minY = points.first.y;
    var maxY = points.first.y;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
    }
    return math.sqrt(math.pow(maxX - minX, 2) + math.pow(maxY - minY, 2));
  }

  static int _countProjectedVisitClusters(
    List<_ProjectedPoint> points, {
    required _ProjectedPoint target,
    required double radiusMeters,
    required double skipLeadingFraction,
    required double skipTrailingFraction,
  }) {
    if (points.length < 4) return 0;
    final startIndex = (points.length * skipLeadingFraction).floor().clamp(
      0,
      points.length - 1,
    );
    final endIndex = (points.length * (1.0 - skipTrailingFraction))
        .ceil()
        .clamp(startIndex + 1, points.length);
    var clusters = 0;
    var previousInside = false;
    for (var i = startIndex; i < endIndex; i++) {
      final inside = points[i].distanceTo(target) <= radiusMeters;
      if (inside && !previousInside) {
        clusters++;
      }
      previousInside = inside;
    }
    return clusters;
  }

  static double _estimateCompactnessScore(List<_ProjectedPoint> points) {
    if (points.length < 5) return 0.0;
    final area = _polygonArea(points);
    if (area <= 0) return 0.0;
    var perimeter = 0.0;
    for (var i = 1; i < points.length; i++) {
      perimeter += points[i - 1].distanceTo(points[i]);
    }
    perimeter += points.last.distanceTo(points.first);
    if (perimeter <= 0) return 0.0;
    final quotient = (4 * math.pi * area) / (perimeter * perimeter);
    return ((quotient / 0.24).clamp(0.0, 1.0) * 100.0).clamp(0.0, 100.0);
  }

  static double _estimateFoldedAreaPenalty(
    List<_ProjectedPoint> points, {
    required double compactnessScore,
  }) {
    if (points.length < 5) return 0.0;
    final area = _polygonArea(points);
    final hullArea = _polygonArea(_convexHull(points));
    if (area <= 0 || hullArea <= 0) {
      return 100.0;
    }
    final areaFillRatio = (area / hullArea).clamp(0.0, 1.0);
    final fillScore = areaFillRatio * 100.0;
    return (100.0 - (fillScore * 0.62 + compactnessScore * 0.38)).clamp(
      0.0,
      100.0,
    );
  }

  static double _polygonArea(List<_ProjectedPoint> points) {
    if (points.length < 3) return 0.0;
    var twiceArea = 0.0;
    for (var i = 0; i < points.length; i++) {
      final current = points[i];
      final next = points[(i + 1) % points.length];
      twiceArea += current.x * next.y - next.x * current.y;
    }
    return twiceArea.abs() / 2.0;
  }

  static List<_ProjectedPoint> _convexHull(List<_ProjectedPoint> points) {
    if (points.length <= 3) return points;
    final sorted = [...points]
      ..sort((a, b) => a.x == b.x ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    final lower = <_ProjectedPoint>[];
    for (final point in sorted) {
      while (lower.length >= 2 &&
          _cross(lower[lower.length - 2], lower.last, point) <= 0) {
        lower.removeLast();
      }
      lower.add(point);
    }
    final upper = <_ProjectedPoint>[];
    for (final point in sorted.reversed) {
      while (upper.length >= 2 &&
          _cross(upper[upper.length - 2], upper.last, point) <= 0) {
        upper.removeLast();
      }
      upper.add(point);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  static double _cross(
    _ProjectedPoint a,
    _ProjectedPoint b,
    _ProjectedPoint c,
  ) {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  }

  static double _styleSpecificShapePenalty({
    required RouteQualityResult quality,
    required bool isRoundTrip,
    String? styleProfileKey,
  }) {
    switch (styleProfileKey) {
      case 'sport':
        return quality.microZigzagPercent * 0.14 +
            quality.corridorSwitchCount * 4.0 +
            quality.foldedAreaPenalty * 0.08;
      case 'abendrunde':
        return quality.microZigzagPercent * 0.12 +
            quality.repeatedStartAreaPercent * 0.14 +
            quality.centerReentryCount * 2.0;
      case 'kurvenjagd':
        return quality.centerRecrossPercent * 0.12 +
            math.max(0, quality.spurArmCount - 2) * 4.0;
      case 'entdecker':
        return quality.progressReversalCount * 3.0 +
            quality.repeatedStartAreaPercent * 0.08;
      default:
        return isRoundTrip
            ? quality.centerRecrossPercent * 0.08
            : quality.corridorSwitchCount * 2.0;
    }
  }
}

class _RouteShapeMetrics {
  const _RouteShapeMetrics({
    this.centerReentryCount = 0,
    this.radialPeakCount = 0,
    this.corridorSwitchCount = 0,
    this.progressReversalCount = 0,
    this.microZigzagCount = 0,
    this.middleCoverageRatio = 0.0,
    this.shapePenalty = 0.0,
    this.scenicLoopScore = 0.0,
    this.centerRecrossPercent = 0.0,
    this.spurArmCount = 0,
    this.spurArmPercent = 0.0,
    this.compactnessScore = 0.0,
    this.foldedAreaPenalty = 0.0,
    this.repeatedStartAreaPercent = 0.0,
    this.microZigzagPercent = 0.0,
    this.dominantLoopScore = 0.0,
  });

  final int centerReentryCount;
  final int radialPeakCount;
  final int corridorSwitchCount;
  final int progressReversalCount;
  final int microZigzagCount;
  final double middleCoverageRatio;
  final double shapePenalty;
  final double scenicLoopScore;
  final double centerRecrossPercent;
  final int spurArmCount;
  final double spurArmPercent;
  final double compactnessScore;
  final double foldedAreaPenalty;
  final double repeatedStartAreaPercent;
  final double microZigzagPercent;
  final double dominantLoopScore;
}

class _ProjectedPoint {
  const _ProjectedPoint({required this.x, required this.y});

  final double x;
  final double y;

  double distanceTo(_ProjectedPoint other) {
    return math.sqrt(math.pow(other.x - x, 2) + math.pow(other.y - y, 2));
  }
}
