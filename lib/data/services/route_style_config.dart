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

    return true;
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
