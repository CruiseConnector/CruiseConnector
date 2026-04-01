import 'dart:math' as math;

/// Konfiguration für die 4 Fahrstile — bestimmt Waypoint-Muster,
/// Mapbox-Parameter und Post-Generierungs-Validierung.
///
/// Die eigentlichen Mapbox-API-Parameter (exclude, profile) werden
/// in der Edge Function gesetzt. Diese Klasse steuert die CLIENT-SEITIGE
/// Logik: Waypoint-Form, Radius-Multiplikator und Qualitätsprüfung.
class RouteStyleConfig {
  const RouteStyleConfig._({
    required this.name,
    required this.profileKey,
    required this.waypointShapeFactor,
    required this.radiusMultiplier,
    required this.minRoundTripKm,
    required this.maxRoundTripKm,
    required this.retryAttempts,
    required this.minStyleFitScore,
    this.minCurvesPer50km,
    this.maxAvgSpeedKmh,
    this.preferFlatTerrain = false,
    this.zigzagWaypoints = false,
  });

  final String name;
  final String profileKey;

  /// Ellipsen-Faktor für Waypoint-Verteilung:
  /// 1.0 = gleichmäßiger Kreis, 2.0 = gestreckte Ellipse (2:1 Verhältnis).
  /// Höhere Werte erzeugen mehr Geraden (gut für Sport Mode).
  final double waypointShapeFactor;

  /// Radius-Multiplikator relativ zum Standard (1.0).
  /// Kleinere Werte (0.7) = engere Rundkurse mit mehr Ortsdurchfahrten.
  /// Größere Werte (1.2) = weitläufigere Rundkurse.
  final double radiusMultiplier;
  final int minRoundTripKm;
  final int maxRoundTripKm;
  final int retryAttempts;
  final double minStyleFitScore;

  /// Mindest-Kurven pro 50km (Bearing-Änderungen >15°).
  /// Nur für Kurvenjagd relevant — null = kein Check.
  final int? minCurvesPer50km;

  /// Maximale Durchschnittsgeschwindigkeit (km/h) die die Route implizieren darf.
  /// Berechnet aus Distanz/Dauer. Nur für Abendrunde — null = kein Check.
  final double? maxAvgSpeedKmh;

  /// Ob flaches Terrain bevorzugt werden soll (Δelevation < 100m).
  final bool preferFlatTerrain;

  /// Ob Waypoints im Zick-Zack-Muster statt gleichmäßig auf dem Kreis
  /// verteilt werden (abwechselnd links/rechts der Hauptachse).
  final bool zigzagWaypoints;

  // ── Die 4 Fahrstil-Profile ───────────────────────────────────────────

  /// SPORT: Autobahnen ERLAUBT, gestreckte Ellipse für lange Geraden,
  /// bevorzugt flaches Terrain für hohe Geschwindigkeiten.
  static const sport = RouteStyleConfig._(
    name: 'Sport Mode',
    profileKey: 'sport',
    waypointShapeFactor: 2.0,
    radiusMultiplier: 1.0,
    minRoundTripKm: 25,
    maxRoundTripKm: 280,
    retryAttempts: 4,
    minStyleFitScore: 50.0,
    preferFlatTerrain: true,
  );

  /// KURVENJAGD: Zick-Zack-Waypoints für maximale Kurvendichte,
  /// breiterer Suchradius damit genug kurvige Straßen gefunden werden.
  /// Post-Validation: mindestens 20 Kurven pro 50km.
  static const kurvenjagd = RouteStyleConfig._(
    name: 'Kurvenjagd',
    profileKey: 'kurvenjagd',
    waypointShapeFactor: 1.0,
    radiusMultiplier: 1.15,
    minRoundTripKm: 20,
    maxRoundTripKm: 230,
    retryAttempts: 5,
    minStyleFitScore: 56.0,
    minCurvesPer50km: 20,
    zigzagWaypoints: true,
  );

  /// ABENDRUNDE: Kleinerer Radius (Faktor 0.7) für mehr Ortsdurchfahrten,
  /// ruhige Straßen mit max. 70 km/h Durchschnittsgeschwindigkeit.
  static const abendrunde = RouteStyleConfig._(
    name: 'Abendrunde',
    profileKey: 'abendrunde',
    waypointShapeFactor: 1.0,
    radiusMultiplier: 0.7,
    minRoundTripKm: 10,
    maxRoundTripKm: 130,
    retryAttempts: 3,
    minStyleFitScore: 48.0,
    maxAvgSpeedKmh: 70.0,
  );

  /// ENTDECKER: Zufällige Richtung die sich von den letzten 3 unterscheidet,
  /// breiterer Suchradius für unbekannte Gebiete.
  static const entdecker = RouteStyleConfig._(
    name: 'Entdecker',
    profileKey: 'entdecker',
    waypointShapeFactor: 1.0,
    radiusMultiplier: 1.2,
    minRoundTripKm: 30,
    maxRoundTripKm: 320,
    retryAttempts: 5,
    minStyleFitScore: 46.0,
  );

  /// Gibt die passende Config für einen Stil-Namen zurück.
  static RouteStyleConfig forMode(String mode) {
    final normalized = mode.trim().toLowerCase();
    return switch (normalized) {
      'sport mode' || 'sport' || 'autobahn' => sport,
      'kurvenjagd' || 'kurvenreich' || 'alpenstraßen' => kurvenjagd,
      'abendrunde' || 'panorama' => abendrunde,
      'entdecker' || 'zufall' => entdecker,
      _ => sport,
    };
  }

  /// Prüft ob die generierte Route die stilspezifischen Qualitätskriterien erfüllt.
  /// Gibt true zurück wenn die Route akzeptabel ist.
  bool validateStyleQuality({
    required List<List<double>> coordinates,
    required double distanceKm,
    double? durationSeconds,
  }) {
    // Kurvenjagd: Bearing-Änderungen zählen
    if (minCurvesPer50km != null && coordinates.length >= 20) {
      final curveCount = _countBearingChanges(
        coordinates,
        thresholdDegrees: 15,
      );
      final curvesNormalized = distanceKm > 0
          ? (curveCount / distanceKm) * 50.0
          : 0.0;
      if (curvesNormalized < minCurvesPer50km!) {
        return false;
      }
    }

    // Abendrunde: Durchschnittsgeschwindigkeit prüfen
    if (maxAvgSpeedKmh != null &&
        durationSeconds != null &&
        durationSeconds > 0) {
      final avgSpeed = distanceKm / (durationSeconds / 3600);
      if (avgSpeed > maxAvgSpeedKmh!) {
        return false;
      }
    }

    final styleFitScore = scoreStyleFit(
      coordinates: coordinates,
      distanceKm: distanceKm,
      durationSeconds: durationSeconds,
    );
    return styleFitScore >= minStyleFitScore;
  }

  /// Weicher Stil-Score (0-100) für bereits generierte Routen.
  ///
  /// Der Score ergänzt die harten Style-Checks oben mit Form- und
  /// Fahrdynamik-Heuristiken, ohne weitere API-Aufrufe auszulösen.
  double scoreStyleFit({
    required List<List<double>> coordinates,
    required double distanceKm,
    double? durationSeconds,
  }) {
    if (coordinates.length < 6 || distanceKm <= 0) {
      return 0.0;
    }

    final curveCount = _countBearingChanges(coordinates, thresholdDegrees: 15);
    final sharpCurveCount = _countBearingChanges(
      coordinates,
      thresholdDegrees: 32,
    );
    final curveDensityPer50Km = (curveCount / distanceKm) * 50.0;
    final sharpCurveDensityPer50Km = (sharpCurveCount / distanceKm) * 50.0;
    final spreadRatio = _estimateSpreadRatio(coordinates, distanceKm);
    final compactnessScore = _estimateCompactnessScore(coordinates);
    final microZigzagPercent = _estimateMicroZigzagPercent(coordinates);
    final smoothnessScore = 1.0 - (microZigzagPercent / 100.0);
    final averageSpeedKmh = durationSeconds != null && durationSeconds > 0
        ? distanceKm / (durationSeconds / 3600.0)
        : null;

    final normalizedScore = switch (profileKey) {
      'sport' => _weightedAverage([
        _weighted(
          _scoreAround(curveDensityPer50Km, center: 12.0, tolerance: 16.0),
          0.26,
        ),
        _weighted(
          _scoreAround(sharpCurveDensityPer50Km, center: 5.0, tolerance: 7.0),
          0.14,
        ),
        _weighted(_scoreRamp(spreadRatio, softMin: 0.16, idealMin: 0.28), 0.26),
        _weighted(
          _scoreAround(compactnessScore, center: 46.0, tolerance: 28.0),
          0.12,
        ),
        _weighted(smoothnessScore, 0.22),
      ]),
      'kurvenjagd' => _weightedAverage([
        _weighted(
          _scoreRamp(curveDensityPer50Km, softMin: 18.0, idealMin: 30.0),
          0.34,
        ),
        _weighted(
          _scoreRamp(sharpCurveDensityPer50Km, softMin: 7.0, idealMin: 15.0),
          0.22,
        ),
        _weighted(
          _scoreAround(spreadRatio, center: 0.24, tolerance: 0.16),
          0.12,
        ),
        _weighted(
          _scoreAround(compactnessScore, center: 52.0, tolerance: 26.0),
          0.12,
        ),
        _weighted(
          _scoreRamp(smoothnessScore, softMin: 0.55, idealMin: 0.8),
          0.20,
        ),
      ]),
      'abendrunde' => _weightedAverage([
        _weighted(
          _scoreAround(compactnessScore, center: 62.0, tolerance: 24.0),
          0.28,
        ),
        _weighted(
          _scoreAround(curveDensityPer50Km, center: 15.0, tolerance: 13.0),
          0.18,
        ),
        _weighted(
          _scoreAround(spreadRatio, center: 0.18, tolerance: 0.10),
          0.14,
        ),
        _weighted(smoothnessScore, 0.20),
        _weighted(
          averageSpeedKmh == null
              ? 0.65
              : _scoreAround(averageSpeedKmh, center: 48.0, tolerance: 24.0),
          0.20,
        ),
      ]),
      'entdecker' => _weightedAverage([
        _weighted(_scoreRamp(spreadRatio, softMin: 0.18, idealMin: 0.32), 0.30),
        _weighted(
          _scoreAround(curveDensityPer50Km, center: 18.0, tolerance: 14.0),
          0.20,
        ),
        _weighted(
          _scoreAround(compactnessScore, center: 42.0, tolerance: 24.0),
          0.16,
        ),
        _weighted(smoothnessScore, 0.18),
        _weighted(_scoreRamp(distanceKm, softMin: 35.0, idealMin: 70.0), 0.16),
      ]),
      _ => _weightedAverage([
        _weighted(
          _scoreAround(curveDensityPer50Km, center: 16.0, tolerance: 14.0),
          0.35,
        ),
        _weighted(_scoreRamp(spreadRatio, softMin: 0.16, idealMin: 0.26), 0.25),
        _weighted(
          _scoreAround(compactnessScore, center: 50.0, tolerance: 24.0),
          0.20,
        ),
        _weighted(smoothnessScore, 0.20),
      ]),
    };

    return (normalizedScore * 100.0).clamp(0.0, 100.0);
  }

  int clampRoundTripDistanceKm(int requestedKm) {
    return requestedKm.clamp(minRoundTripKm, maxRoundTripKm);
  }

  double clampPointToPointTargetKm(
    double requestedKm, {
    required double directDistanceKm,
    required bool scenic,
    required int detourVariant,
  }) {
    if (!scenic && detourVariant <= 0) {
      return directDistanceKm;
    }
    final lowerBound = minimumPointToPointDistanceKm(
      directDistanceKm: directDistanceKm,
      scenic: scenic,
      detourVariant: detourVariant,
    );
    final upperBound = maximumPointToPointDistanceKm(
      targetKm: requestedKm,
      directDistanceKm: directDistanceKm,
      scenic: scenic,
      detourVariant: detourVariant,
    );
    return requestedKm.clamp(lowerBound, upperBound);
  }

  double minimumPointToPointDistanceKm({
    required double directDistanceKm,
    required bool scenic,
    required int detourVariant,
  }) {
    if (!scenic && detourVariant <= 0) {
      return directDistanceKm;
    }
    final minByVariant = switch (detourVariant) {
      1 => directDistanceKm * 1.18,
      2 => directDistanceKm * 1.42,
      3 => directDistanceKm * 1.75,
      _ => directDistanceKm * 1.08,
    };
    final paddingKm = switch (detourVariant) {
      1 => 1.0,
      2 => 2.0,
      3 => 4.0,
      _ => 1.0,
    };
    return math.max(minByVariant, directDistanceKm + paddingKm);
  }

  double maximumPointToPointDistanceKm({
    required double targetKm,
    required double directDistanceKm,
    required bool scenic,
    required int detourVariant,
  }) {
    if (!scenic && detourVariant <= 0) {
      return math.max(directDistanceKm + 2.0, directDistanceKm * 1.12);
    }
    final maxByTarget = switch (detourVariant) {
      1 => targetKm * 1.32,
      2 => targetKm * 1.42,
      3 => targetKm * 1.52,
      _ => targetKm * 1.18,
    };
    final maxByDirect = switch (detourVariant) {
      1 => directDistanceKm * 2.05,
      2 => directDistanceKm * 2.85,
      3 => directDistanceKm * 3.45,
      _ => directDistanceKm * 1.35,
    };
    final slackKm = switch (detourVariant) {
      1 => 3.0,
      2 => 6.0,
      3 => 10.0,
      _ => 2.0,
    };
    final lowerBound = minimumPointToPointDistanceKm(
      directDistanceKm: directDistanceKm,
      scenic: scenic,
      detourVariant: detourVariant,
    );
    return math.max(lowerBound + slackKm, math.max(maxByTarget, maxByDirect));
  }

  Map<String, dynamic> toRequestHints() {
    return <String, dynamic>{
      'style_profile': profileKey,
      'waypoint_shape_factor': waypointShapeFactor,
      'radius_multiplier': radiusMultiplier,
      'prefer_flat_terrain': preferFlatTerrain,
      'zigzag_waypoints': zigzagWaypoints,
    };
  }

  /// Zählt Bearing-Änderungen die größer als [thresholdDegrees] sind.
  /// Nutzt Sampling (jeden 5. Punkt) für Performance.
  static int _countBearingChanges(
    List<List<double>> coordinates, {
    required double thresholdDegrees,
  }) {
    if (coordinates.length < 4) return 0;

    var count = 0;
    const sampleStep = 5;

    for (
      var i = sampleStep;
      i < coordinates.length - sampleStep;
      i += sampleStep
    ) {
      final prev = coordinates[i - sampleStep];
      final curr = coordinates[i];
      final next =
          coordinates[math.min(i + sampleStep, coordinates.length - 1)];

      if (prev.length < 2 || curr.length < 2 || next.length < 2) continue;

      final bearing1 = _bearing(prev[1], prev[0], curr[1], curr[0]);
      final bearing2 = _bearing(curr[1], curr[0], next[1], next[0]);
      final delta = _angleDiff(bearing1, bearing2).abs();

      if (delta > thresholdDegrees) count++;
    }

    return count;
  }

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

  static double _angleDiff(double from, double to) {
    var diff = (to - from) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }

  static List<_StyleProjectedPoint> _projectToMeters(
    List<List<double>> coordinates,
  ) {
    if (coordinates.isEmpty) return const [];
    final origin = coordinates.first;
    if (origin.length < 2) return const [];
    final originLng = origin[0];
    final originLat = origin[1];
    final cosLat = math.cos(originLat * math.pi / 180.0);

    return coordinates
        .where((point) => point.length >= 2)
        .map(
          (point) => _StyleProjectedPoint(
            x: (point[0] - originLng) * 111320.0 * cosLat,
            y: (point[1] - originLat) * 110540.0,
          ),
        )
        .toList();
  }

  static double _estimateSpreadRatio(
    List<List<double>> coordinates,
    double distanceKm,
  ) {
    if (coordinates.length < 2 || distanceKm <= 0) return 0.0;
    final projected = _projectToMeters(coordinates);
    if (projected.isEmpty) return 0.0;

    var minX = projected.first.x;
    var maxX = projected.first.x;
    var minY = projected.first.y;
    var maxY = projected.first.y;
    for (final point in projected.skip(1)) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
    }

    final diagonalKm =
        math.sqrt(math.pow(maxX - minX, 2) + math.pow(maxY - minY, 2)) / 1000.0;
    return (diagonalKm / distanceKm).clamp(0.0, 1.0);
  }

  static double _estimateCompactnessScore(List<List<double>> coordinates) {
    if (coordinates.length < 5) return 0.0;
    final projected = _projectToMeters(
      _sampleCoordinates(coordinates, sampleCount: 56),
    );
    if (projected.length < 5) return 0.0;

    final polygonArea = _polygonArea(projected);
    if (polygonArea <= 0) return 0.0;

    var perimeter = 0.0;
    for (var i = 1; i < projected.length; i++) {
      perimeter += projected[i - 1].distanceTo(projected[i]);
    }
    perimeter += projected.last.distanceTo(projected.first);
    if (perimeter <= 0) return 0.0;

    final quotient = (4 * math.pi * polygonArea) / (perimeter * perimeter);
    return ((quotient / 0.24).clamp(0.0, 1.0)) * 100.0;
  }

  static double _estimateMicroZigzagPercent(List<List<double>> coordinates) {
    if (coordinates.length < 10) return 0.0;
    final sampled = _sampleCoordinates(coordinates, sampleCount: 72);
    final projected = _projectToMeters(sampled);
    if (projected.length < 6) return 0.0;

    final headings = <double>[];
    final segmentLengths = <double>[];
    for (var i = 1; i < projected.length; i++) {
      final previous = projected[i - 1];
      final current = projected[i];
      final distance = previous.distanceTo(current);
      if (distance < 6) continue;
      segmentLengths.add(distance);
      headings.add(
        (math.atan2(current.y - previous.y, current.x - previous.x) *
                    180 /
                    math.pi +
                360) %
            360,
      );
    }
    if (headings.length < 4) return 0.0;

    var zigzagCount = 0;
    var windowCount = 0;
    for (var i = 1; i < headings.length - 1; i++) {
      final firstDelta = _angleDiff(headings[i - 1], headings[i]);
      final secondDelta = _angleDiff(headings[i], headings[i + 1]);
      final firstMagnitude = firstDelta.abs();
      final secondMagnitude = secondDelta.abs();
      final recovery = _angleDiff(headings[i - 1], headings[i + 1]).abs();
      final windowDistance =
          segmentLengths[i - 1] + segmentLengths[i] + segmentLengths[i + 1];
      windowCount++;

      final isAlternating =
          (firstDelta > 0 && secondDelta < 0) ||
          (firstDelta < 0 && secondDelta > 0);
      if (isAlternating &&
          firstMagnitude >= 18 &&
          secondMagnitude >= 18 &&
          firstMagnitude <= 95 &&
          secondMagnitude <= 95 &&
          recovery <= 35 &&
          windowDistance <= 170) {
        zigzagCount++;
      }
    }

    if (windowCount == 0) return 0.0;
    return ((zigzagCount / windowCount) * 100.0).clamp(0.0, 100.0);
  }

  static List<List<double>> _sampleCoordinates(
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
      samples.add(point);
    }
    return samples;
  }

  static double _polygonArea(List<_StyleProjectedPoint> points) {
    if (points.length < 3) return 0.0;
    var twiceArea = 0.0;
    for (var i = 0; i < points.length; i++) {
      final current = points[i];
      final next = points[(i + 1) % points.length];
      twiceArea += current.x * next.y - next.x * current.y;
    }
    return twiceArea.abs() / 2.0;
  }

  static _WeightedScore _weighted(double value, double weight) {
    return _WeightedScore(value: value.clamp(0.0, 1.0), weight: weight);
  }

  static double _weightedAverage(List<_WeightedScore> scores) {
    var weightedValue = 0.0;
    var totalWeight = 0.0;
    for (final score in scores) {
      weightedValue += score.value * score.weight;
      totalWeight += score.weight;
    }
    if (totalWeight <= 0) return 0.0;
    return (weightedValue / totalWeight).clamp(0.0, 1.0);
  }

  static double _scoreAround(
    double value, {
    required double center,
    required double tolerance,
  }) {
    if (tolerance <= 0) return value == center ? 1.0 : 0.0;
    final delta = ((value - center).abs() / tolerance).clamp(0.0, 1.0);
    return 1.0 - delta;
  }

  static double _scoreRamp(
    double value, {
    required double softMin,
    required double idealMin,
  }) {
    if (idealMin <= softMin) {
      return value >= idealMin ? 1.0 : 0.0;
    }
    if (value <= softMin) return 0.0;
    if (value >= idealMin) return 1.0;
    return ((value - softMin) / (idealMin - softMin)).clamp(0.0, 1.0);
  }
}

class _StyleProjectedPoint {
  const _StyleProjectedPoint({required this.x, required this.y});

  final double x;
  final double y;

  double distanceTo(_StyleProjectedPoint other) {
    return math.sqrt(math.pow(other.x - x, 2) + math.pow(other.y - y, 2));
  }
}

class _WeightedScore {
  const _WeightedScore({required this.value, required this.weight});

  final double value;
  final double weight;
}

/// Vorbereitung für personalisierte Entdecker-Routen.
// TODO: Supabase-Fahrdaten laden für personalisierte Routen
class ExplorerConfig {
  const ExplorerConfig({
    this.avoidAreaHashes = const [],
    this.preferredBearings = const [],
  });

  /// Hashes von bereits befahrenen Gebieten (für zukünftige Personalisierung)
  final List<String> avoidAreaHashes;

  /// Bevorzugte Richtungen basierend auf Fahrthistorie
  final List<double> preferredBearings;
}
