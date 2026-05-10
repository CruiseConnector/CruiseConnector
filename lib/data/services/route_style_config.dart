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

  /// SPORT: Autobahnen werden über den Toggle gesteuert. Stil heißt hier
  /// „flüssig & schnell“: gestreckte Ellipse, moderater Radius, sodass
  /// Mapbox bevorzugt Landstraßen/Highways wählt und keine engen Bergstraßen
  /// zwingend einbauen muss. Den eigentlichen Semantik-Hebel gegen
  /// „Sport über Bergpass“ setzt die Edge Function (exclude=unpaved).
  static const sport = RouteStyleConfig._(
    name: 'Sport Mode',
    profileKey: 'sport',
    waypointShapeFactor: 2.05,
    radiusMultiplier: 1.02,
    minRoundTripKm: 25,
    maxRoundTripKm: 100,
    retryAttempts: 4,
    minStyleFitScore: 49.0,
    preferFlatTerrain: true,
  );

  /// KURVENJAGD: Zick-Zack-Waypoints für maximale Kurvendichte,
  /// breiterer Suchradius damit genug kurvige Straßen gefunden werden.
  /// Post-Validation: mindestens 20 Kurven pro 50km.
  static const kurvenjagd = RouteStyleConfig._(
    name: 'Kurvenjagd',
    profileKey: 'kurvenjagd',
    waypointShapeFactor: 0.95,
    radiusMultiplier: 1.18,
    minRoundTripKm: 20,
    maxRoundTripKm: 100,
    retryAttempts: 5,
    minStyleFitScore: 52.0,
    minCurvesPer50km: 18,
    zigzagWaypoints: true,
  );

  /// ABENDRUNDE: Kleinerer Radius (Faktor 0.7) für mehr Ortsdurchfahrten,
  /// ruhige Straßen mit max. 70 km/h Durchschnittsgeschwindigkeit.
  static const abendrunde = RouteStyleConfig._(
    name: 'Abendrunde',
    profileKey: 'abendrunde',
    waypointShapeFactor: 1.0,
    radiusMultiplier: 0.70,
    minRoundTripKm: 10,
    maxRoundTripKm: 100,
    retryAttempts: 4,
    minStyleFitScore: 51.0,
    maxAvgSpeedKmh: 72.0,
  );

  /// ENTDECKER: Zufällige Richtung die sich von den letzten 3 unterscheidet,
  /// breiterer Suchradius für unbekannte Gebiete.
  static const entdecker = RouteStyleConfig._(
    name: 'Entdecker',
    profileKey: 'entdecker',
    waypointShapeFactor: 1.08,
    radiusMultiplier: 1.24,
    minRoundTripKm: 20,
    maxRoundTripKm: 100,
    retryAttempts: 5,
    minStyleFitScore: 47.0,
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
    final metrics = calculateStyleMetrics(
      coordinates: coordinates,
      distanceKm: distanceKm,
      durationSeconds: durationSeconds,
    );
    if (!metrics.isUsable) {
      return 0.0;
    }

    final smoothnessScore = metrics.smoothnessScore / 100.0;
    final averageSpeedKmh = metrics.averageSpeedKmh;
    final segmentFlowScore = _scoreRamp(
      metrics.averageSegmentLengthMeters,
      softMin: 120.0,
      idealMin: 260.0,
    );

    final normalizedScore = switch (profileKey) {
      'sport' => _weightedAverage([
        _weighted(
          _scoreAround(
            metrics.curveDensityPer50Km,
            center: 8.0,
            tolerance: 9.0,
          ),
          0.08,
        ),
        _weighted(
          _scoreAround(
            metrics.sharpCurveDensityPer50Km,
            center: 2.0,
            tolerance: 4.0,
          ),
          0.08,
        ),
        _weighted(
          _scoreRamp(metrics.spreadRatio, softMin: 0.16, idealMin: 0.30),
          0.16,
        ),
        _weighted(segmentFlowScore, 0.20),
        _weighted(smoothnessScore, 0.36),
        _weighted(
          averageSpeedKmh == null
              ? 0.65
              : _scoreAround(averageSpeedKmh, center: 70.0, tolerance: 24.0),
          0.12,
        ),
      ]),
      'kurvenjagd' => _weightedAverage([
        _weighted(
          _scoreRamp(
            metrics.curveDensityPer50Km,
            softMin: 22.0,
            idealMin: 36.0,
          ),
          0.34,
        ),
        _weighted(
          _scoreRamp(
            metrics.sharpCurveDensityPer50Km,
            softMin: 8.0,
            idealMin: 16.0,
          ),
          0.22,
        ),
        _weighted(
          _scoreRamp(
            metrics.headingChangePerKm,
            softMin: 95.0,
            idealMin: 150.0,
          ),
          0.12,
        ),
        _weighted(
          _scoreAround(metrics.spreadRatio, center: 0.24, tolerance: 0.16),
          0.10,
        ),
        _weighted(
          _scoreRamp(smoothnessScore, softMin: 0.45, idealMin: 0.72),
          0.10,
        ),
        _weighted(
          _scoreAround(metrics.compactnessScore, center: 50.0, tolerance: 30.0),
          0.12,
        ),
      ]),
      'abendrunde' => _weightedAverage([
        _weighted(
          _scoreAround(metrics.compactnessScore, center: 64.0, tolerance: 22.0),
          0.30,
        ),
        _weighted(smoothnessScore, 0.24),
        _weighted(
          averageSpeedKmh == null
              ? 0.65
              : _scoreAround(averageSpeedKmh, center: 44.0, tolerance: 18.0),
          0.24,
        ),
        _weighted(
          _scoreAround(
            metrics.curveDensityPer50Km,
            center: 10.0,
            tolerance: 12.0,
          ),
          0.12,
        ),
        _weighted(
          _scoreAround(metrics.spreadRatio, center: 0.14, tolerance: 0.10),
          0.10,
        ),
      ]),
      'entdecker' => _weightedAverage([
        _weighted(metrics.sectorDiversityScore / 100.0, 0.20),
        _weighted(
          _scoreRamp(metrics.spreadRatio, softMin: 0.16, idealMin: 0.28),
          0.34,
        ),
        _weighted(
          _scoreAround(metrics.compactnessScore, center: 38.0, tolerance: 30.0),
          0.12,
        ),
        _weighted(
          _scoreAround(
            metrics.curveDensityPer50Km,
            center: 16.0,
            tolerance: 20.0,
          ),
          0.10,
        ),
        _weighted(_scoreRamp(distanceKm, softMin: 35.0, idealMin: 70.0), 0.14),
        _weighted(smoothnessScore, 0.10),
      ]),
      _ => _weightedAverage([
        _weighted(
          _scoreAround(
            metrics.curveDensityPer50Km,
            center: 16.0,
            tolerance: 14.0,
          ),
          0.30,
        ),
        _weighted(
          _scoreRamp(metrics.spreadRatio, softMin: 0.16, idealMin: 0.26),
          0.24,
        ),
        _weighted(
          _scoreAround(metrics.compactnessScore, center: 50.0, tolerance: 24.0),
          0.22,
        ),
        _weighted(smoothnessScore, 0.24),
      ]),
    };

    final separatedScore = _applyStyleSeparation(
      profileKey,
      normalizedScore,
      metrics,
      smoothnessScore,
    );
    return (separatedScore * 100.0).clamp(0.0, 100.0);
  }

  static double _applyStyleSeparation(
    String profileKey,
    double score,
    RouteStyleMetrics metrics,
    double smoothnessScore,
  ) {
    if (profileKey == 'sport') {
      final excessiveCurves = _scoreRamp(
        metrics.curveDensityPer50Km,
        softMin: 22.0,
        idealMin: 34.0,
      );
      final excessiveSharp = _scoreRamp(
        metrics.sharpCurveDensityPer50Km,
        softMin: 7.0,
        idealMin: 13.0,
      );
      final excessiveHeading = _scoreRamp(
        metrics.headingChangePerKm,
        softMin: 115.0,
        idealMin: 165.0,
      );
      return (score -
              excessiveCurves * 0.12 -
              excessiveSharp * 0.08 -
              excessiveHeading * 0.06)
          .clamp(0.0, 1.0);
    }
    if (profileKey == 'kurvenjagd') {
      final loopSupport = _weightedAverage([
        _weighted(
          _scoreAround(metrics.compactnessScore, center: 50.0, tolerance: 32.0),
          0.36,
        ),
        _weighted(
          _scoreRamp(metrics.spreadRatio, softMin: 0.18, idealMin: 0.30),
          0.34,
        ),
        _weighted(
          _scoreRamp(smoothnessScore, softMin: 0.46, idealMin: 0.70),
          0.30,
        ),
      ]);
      final loopPenalty = loopSupport < 0.56
          ? (0.56 - loopSupport) * 0.18
          : 0.0;
      return (score - loopPenalty).clamp(0.0, 1.0);
    }
    return score.clamp(0.0, 1.0);
  }

  RouteStyleMetrics calculateStyleMetrics({
    required List<List<double>> coordinates,
    required double distanceKm,
    double? durationSeconds,
  }) {
    if (coordinates.length < 6 || distanceKm <= 0) {
      return RouteStyleMetrics.empty;
    }

    final turnStats = _calculateTurnStats(coordinates);
    final curveDensityPer50Km = (turnStats.curveCount / distanceKm) * 50.0;
    final sharpCurveDensityPer50Km =
        (turnStats.sharpCurveCount / distanceKm) * 50.0;
    final spreadRatio = _estimateSpreadRatio(coordinates, distanceKm);
    final compactnessScore = _estimateCompactnessScore(coordinates);
    final microZigzagPercent = _estimateMicroZigzagPercent(coordinates);
    final smoothnessScore = (100.0 - microZigzagPercent).clamp(0.0, 100.0);
    final headingChangePerKm = turnStats.totalHeadingChange / distanceKm;
    final averageSegmentLengthMeters = _estimateAverageSegmentLengthMeters(
      coordinates,
    );
    final averageSpeedKmh = durationSeconds != null && durationSeconds > 0
        ? distanceKm / (durationSeconds / 3600.0)
        : null;
    final sectorDiversityScore = _estimateSectorDiversityScore(coordinates);

    return RouteStyleMetrics(
      curveDensityPer50Km: curveDensityPer50Km,
      sharpCurveDensityPer50Km: sharpCurveDensityPer50Km,
      averageSegmentLengthMeters: averageSegmentLengthMeters,
      headingChangePerKm: headingChangePerKm,
      smoothnessScore: smoothnessScore,
      microZigzagPercent: microZigzagPercent,
      spreadRatio: spreadRatio,
      compactnessScore: compactnessScore,
      sectorDiversityScore: sectorDiversityScore,
      averageSpeedKmh: averageSpeedKmh,
    );
  }

  List<String> styleFitReasons(RouteStyleMetrics metrics) {
    final reasons = <String>[];
    switch (profileKey) {
      case 'sport':
        if (metrics.smoothnessScore >= 78) reasons.add('smooth_flow');
        if (metrics.averageSegmentLengthMeters >= 180) {
          reasons.add('longer_segments');
        }
        if (metrics.sharpCurveDensityPer50Km >= 10) {
          reasons.add('too_many_sharp_turns');
        }
        if (metrics.microZigzagPercent >= 30) reasons.add('zigzag_penalty');
        break;
      case 'kurvenjagd':
        if (metrics.curveDensityPer50Km >= 28) {
          reasons.add('high_curve_density');
        }
        if (metrics.headingChangePerKm >= 130) reasons.add('continuous_bends');
        if (metrics.microZigzagPercent >= 42) reasons.add('zigzag_penalty');
        break;
      case 'abendrunde':
        if (metrics.averageSpeedKmh != null && metrics.averageSpeedKmh! <= 58) {
          reasons.add('calm_speed');
        }
        if (metrics.compactnessScore >= 52) reasons.add('clean_return');
        if (metrics.sharpCurveDensityPer50Km >= 9) {
          reasons.add('too_aggressive');
        }
        break;
      case 'entdecker':
        if (metrics.sectorDiversityScore >= 55) reasons.add('sector_diverse');
        if (metrics.spreadRatio >= 0.26) reasons.add('regional_spread');
        break;
    }
    return reasons;
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

  // Scenic-Umwege starten clientseitig nur mit Luftlinien-Distanz. Für kurze
  // A→B-Strecken unterschätzt das die tatsächlich "direkte" Fahrdistanz oft
  // deutlich, wodurch Klein/Mittel/Groß zu ähnlich werden. Diese Referenz
  // hebt nur den Scenic-Basispunkt leicht an; direkte A→B-Routen bleiben
  // unverändert.
  double pointToPointScenicReferenceDistanceKm({
    required double directDistanceKm,
    required int detourVariant,
  }) {
    if (detourVariant <= 0) return directDistanceKm;

    final shortHop = directDistanceKm <= 12.0;
    final midHop = directDistanceKm <= 25.0;
    final roadFactor = shortHop
        ? 1.32
        : midHop
        ? 1.24
        : 1.18;
    final roadPaddingKm = switch (detourVariant) {
      1 => shortHop ? 1.8 : (midHop ? 2.2 : 2.8),
      2 => shortHop ? 2.6 : (midHop ? 3.1 : 3.8),
      3 => shortHop ? 3.8 : (midHop ? 4.5 : 5.2),
      _ => shortHop ? 1.5 : (midHop ? 2.0 : 2.5),
    };

    return math.max(
      directDistanceKm,
      math.max(directDistanceKm * roadFactor, directDistanceKm + roadPaddingKm),
    );
  }

  // Detour-Fenster — entkoppelt, damit Klein/Mittel/Groß sich tatsächlich
  // unterschiedlich anfühlen. Vorher überlappten die Bereiche so stark, dass
  // eine Route mit 1.85× direkter Distanz für alle drei Stufen gültig war.
  // Aktuelle Fenster:
  //   Klein:  1.20×–1.45× direkt   (~Faktor 1.32×)
  //   Mittel: 1.50×–1.90× direkt   (~Faktor 1.65×)
  //   Groß:   1.90×–2.80× direkt   (~Faktor 2.10×)
  // Bewusst etwas weiter als zuvor, damit Mapbox bei Bergland (Dornbirn,
  // Bregenzerwald) das Fenster wirklich treffen kann. Eine schmale ~10%
  // Überlappung an den Rändern bleibt absichtlich erhalten, damit der
  // Fallback nicht ständig auf "direkt" zurückfällt und alle drei Stufen
  // wieder identisch wirken. Falls der Mapbox-Kandidat zu kurz ist, sieht
  // _tryPointToPointFallback in route_service.dart die Stufe noch immer.
  double minimumPointToPointDistanceKm({
    required double directDistanceKm,
    required bool scenic,
    required int detourVariant,
  }) {
    if (!scenic && detourVariant <= 0) {
      return directDistanceKm;
    }
    final scenicReferenceKm = scenic
        ? pointToPointScenicReferenceDistanceKm(
            directDistanceKm: directDistanceKm,
            detourVariant: detourVariant,
          )
        : directDistanceKm;
    final minByVariant = switch (detourVariant) {
      1 => scenicReferenceKm * 1.20,
      2 => scenicReferenceKm * 1.50,
      3 => scenicReferenceKm * 1.90,
      _ => scenicReferenceKm * 1.08,
    };
    final paddingKm = switch (detourVariant) {
      1 => 1.0,
      2 => 3.0,
      3 => 6.0,
      _ => 1.0,
    };
    return math.max(minByVariant, scenicReferenceKm + paddingKm);
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
    final scenicReferenceKm = scenic
        ? pointToPointScenicReferenceDistanceKm(
            directDistanceKm: directDistanceKm,
            detourVariant: detourVariant,
          )
        : directDistanceKm;
    final maxByTarget = switch (detourVariant) {
      1 => targetKm * 1.12,
      2 => targetKm * 1.14,
      3 => targetKm * 1.18,
      _ => targetKm * 1.20,
    };
    final maxByDirect = switch (detourVariant) {
      1 => scenicReferenceKm * 1.45,
      2 => scenicReferenceKm * 1.90,
      3 => scenicReferenceKm * 2.80,
      _ => scenicReferenceKm * 1.40,
    };
    final slackKm = switch (detourVariant) {
      1 => 3.0,
      2 => 5.5,
      3 => 10.0,
      _ => 2.5,
    };
    final lowerBound = minimumPointToPointDistanceKm(
      directDistanceKm: directDistanceKm,
      scenic: scenic,
      detourVariant: detourVariant,
    );
    return math.max(lowerBound + slackKm, math.min(maxByDirect, maxByTarget));
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
    // Feinerer Step (3) fängt alpine Switchbacks im 250–500m Fenster zuverlässig.
    // Nur hier sicher: _countBearingChanges wird ausschließlich vom Kurvenjagd-
    // Hard-Gate genutzt (minCurvesPer50km != null). Sport/Abendrunde/Entdecker
    // bleiben über _calculateTurnStats (sampleStep=5) unbeeinflusst.
    const sampleStep = 3;

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

  static _TurnStats _calculateTurnStats(List<List<double>> coordinates) {
    if (coordinates.length < 4) return const _TurnStats();

    var curveCount = 0;
    var sharpCurveCount = 0;
    var totalHeadingChange = 0.0;
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
      totalHeadingChange += delta;
      if (delta > 15) curveCount++;
      if (delta > 32) sharpCurveCount++;
    }

    return _TurnStats(
      curveCount: curveCount,
      sharpCurveCount: sharpCurveCount,
      totalHeadingChange: totalHeadingChange,
    );
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

  static double _estimateAverageSegmentLengthMeters(
    List<List<double>> coordinates,
  ) {
    final projected = _projectToMeters(
      _sampleCoordinates(coordinates, sampleCount: 88),
    );
    if (projected.length < 2) return 0.0;
    var totalMeters = 0.0;
    var segmentCount = 0;
    for (var i = 1; i < projected.length; i++) {
      final distance = projected[i - 1].distanceTo(projected[i]);
      if (distance <= 1) continue;
      totalMeters += distance;
      segmentCount++;
    }
    return segmentCount == 0 ? 0.0 : totalMeters / segmentCount;
  }

  static double _estimateSectorDiversityScore(List<List<double>> coordinates) {
    if (coordinates.length < 8) return 0.0;
    final origin = coordinates.first;
    if (origin.length < 2) return 0.0;
    final sectors = <int>{};
    for (final point in _sampleCoordinates(coordinates, sampleCount: 48)) {
      if (point.length < 2) continue;
      final distanceMeters = _haversineMeters(origin, point);
      if (distanceMeters < 500) continue;
      final bearing = _bearing(origin[1], origin[0], point[1], point[0]);
      sectors.add((bearing / 45.0).floor().clamp(0, 7));
    }
    return ((sectors.length / 6.0) * 100.0).clamp(0.0, 100.0);
  }

  static double _haversineMeters(List<double> a, List<double> b) {
    const earthRadiusMeters = 6371000.0;
    final lat1 = a[1] * math.pi / 180.0;
    final lat2 = b[1] * math.pi / 180.0;
    final dLat = (b[1] - a[1]) * math.pi / 180.0;
    final dLng = (b[0] - a[0]) * math.pi / 180.0;
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
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

class RouteStyleMetrics {
  const RouteStyleMetrics({
    required this.curveDensityPer50Km,
    required this.sharpCurveDensityPer50Km,
    required this.averageSegmentLengthMeters,
    required this.headingChangePerKm,
    required this.smoothnessScore,
    required this.microZigzagPercent,
    required this.spreadRatio,
    required this.compactnessScore,
    required this.sectorDiversityScore,
    required this.averageSpeedKmh,
  });

  static const empty = RouteStyleMetrics(
    curveDensityPer50Km: 0,
    sharpCurveDensityPer50Km: 0,
    averageSegmentLengthMeters: 0,
    headingChangePerKm: 0,
    smoothnessScore: 0,
    microZigzagPercent: 0,
    spreadRatio: 0,
    compactnessScore: 0,
    sectorDiversityScore: 0,
    averageSpeedKmh: null,
  );

  final double curveDensityPer50Km;
  final double sharpCurveDensityPer50Km;
  final double averageSegmentLengthMeters;
  final double headingChangePerKm;
  final double smoothnessScore;
  final double microZigzagPercent;
  final double spreadRatio;
  final double compactnessScore;
  final double sectorDiversityScore;
  final double? averageSpeedKmh;

  bool get isUsable => curveDensityPer50Km.isFinite && smoothnessScore > 0;

  Map<String, dynamic> toJson() {
    return {
      'curve_density_per_50km': double.parse(
        curveDensityPer50Km.toStringAsFixed(2),
      ),
      'curve_density_per_km': double.parse(
        (curveDensityPer50Km / 50.0).toStringAsFixed(3),
      ),
      'sharp_turn_count_per_50km': double.parse(
        sharpCurveDensityPer50Km.toStringAsFixed(2),
      ),
      'average_segment_length_m': double.parse(
        averageSegmentLengthMeters.toStringAsFixed(1),
      ),
      'heading_change_per_km': double.parse(
        headingChangePerKm.toStringAsFixed(1),
      ),
      'smoothness_score': double.parse(smoothnessScore.toStringAsFixed(1)),
      'zigzag_score': double.parse(microZigzagPercent.toStringAsFixed(1)),
      'spread_ratio': double.parse(spreadRatio.toStringAsFixed(3)),
      'compactness_score': double.parse(compactnessScore.toStringAsFixed(1)),
      'sector_diversity_score': double.parse(
        sectorDiversityScore.toStringAsFixed(1),
      ),
      'average_speed_kmh': averageSpeedKmh == null
          ? null
          : double.parse(averageSpeedKmh!.toStringAsFixed(1)),
    };
  }
}

class _TurnStats {
  const _TurnStats({
    this.curveCount = 0,
    this.sharpCurveCount = 0,
    this.totalHeadingChange = 0.0,
  });

  final int curveCount;
  final int sharpCurveCount;
  final double totalHeadingChange;
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
