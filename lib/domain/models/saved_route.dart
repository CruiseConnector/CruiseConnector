/// Eine gespeicherte Route aus der Supabase `routes` Tabelle.
class SavedRoute {
  const SavedRoute({
    required this.id,
    required this.createdAt,
    required this.style,
    required this.distanceKm,
    required this.geometry,
    this.userId,
    this.name,
    this.durationSeconds,
    this.routeType,
    this.rating,
    this.distanceTargetKm,
    this.drivenKm,
    this.sourceRouteId,
    this.groupId,
    this.xpDistance,
    this.xpCurveBonus,
    this.xpStyleBonus,
    this.xpBase,
    this.xpMultiplier,
    this.xpStreakDays,
    this.xpAwarded,
    this.routeSource,
    this.routeFingerprint,
    this.qualityTier,
    this.routeMeta = const {},
    this.averageRating,
    this.ratingCount = 0,
    this.completionRate,
    this.completedAtEnd = false,
    this.photoUrl,
  });

  final String id;
  final DateTime createdAt;
  final String style;
  final double distanceKm;
  final Map<String, dynamic> geometry;
  final String? userId;
  final String? name;
  final double? durationSeconds;
  final String? routeType;
  final int? rating;
  final double? distanceTargetKm;
  final double? drivenKm;
  final String? sourceRouteId;
  final String? groupId;
  final int? xpDistance;
  final int? xpCurveBonus;
  final int? xpStyleBonus;
  final int? xpBase;
  final double? xpMultiplier;
  final int? xpStreakDays;
  final int? xpAwarded;
  final String? routeSource;
  final String? routeFingerprint;
  final String? qualityTier;
  final Map<String, dynamic> routeMeta;
  final double? averageRating;
  final int ratingCount;
  final double? completionRate;
  final bool completedAtEnd;
  final String? photoUrl;

  factory SavedRoute.fromJson(Map<String, dynamic> json) {
    return SavedRoute(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      style: (json['style'] as String?) ?? 'Standard',
      distanceKm: (json['distance_actual'] as num?)?.toDouble() ?? 0.0,
      geometry: json['geometry'] is Map
          ? Map<String, dynamic>.from(json['geometry'] as Map)
          : const {},
      name: json['name'] as String?,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
      routeType: (json['route_type'] as String?) ?? 'ROUND_TRIP',
      rating: (json['rating'] as num?)?.toInt(),
      distanceTargetKm: (json['distance_target'] as num?)?.toDouble(),
      drivenKm: (json['driven_km'] as num?)?.toDouble(),
      sourceRouteId: json['source_route_id'] as String?,
      groupId: json['group_id'] as String?,
      xpDistance: (json['xp_distance'] as num?)?.toInt(),
      xpCurveBonus: (json['xp_curve_bonus'] as num?)?.toInt(),
      xpStyleBonus: (json['xp_style_bonus'] as num?)?.toInt(),
      xpBase: (json['xp_base'] as num?)?.toInt(),
      xpMultiplier: (json['xp_multiplier'] as num?)?.toDouble(),
      xpStreakDays: (json['xp_streak_days'] as num?)?.toInt(),
      xpAwarded: (json['xp_awarded'] as num?)?.toInt(),
      routeSource: json['route_source'] as String?,
      routeFingerprint: json['route_fingerprint'] as String?,
      qualityTier: json['quality_tier'] as String?,
      routeMeta: json['route_meta'] is Map
          ? Map<String, dynamic>.from(json['route_meta'] as Map)
          : const {},
      averageRating: (json['average_rating'] as num?)?.toDouble(),
      ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
      completionRate: (json['completion_rate'] as num?)?.toDouble(),
      completedAtEnd: json['completed_at_end'] == true,
      photoUrl: json['photo_url'] as String?,
    );
  }

  bool get isRoundTrip => routeType == 'ROUND_TRIP';

  /// 2026-06-25 (vucko Routen-Detail-Page): flache [lng,lat]-Koordinatenliste
  /// der Route — für die Karten-Darstellung in der Detailseite.
  List<List<double>> get flatCoordinates =>
      flattenGeometryCoordinates(geometry);

  bool get isDrivenSession => (drivenKm ?? 0) > 0;

  double get actualDistanceKm => drivenKm ?? distanceKm;

  double? get completionRatio {
    if (!isDrivenSession) return null;
    final planned = distanceTargetKm;
    if (planned == null || planned <= 0) return null;
    return (actualDistanceKm / planned).clamp(0.0, 1.0);
  }

  bool get qualifiesForXpCredit {
    return isDrivenSession;
  }

  bool get isFullyCompleted {
    if (!isDrivenSession) return false;
    if (completedAtEnd) return true;
    final ratio = completionRatio;
    if (ratio == null) return true;
    return ratio >= 1.0;
  }

  double get xpCreditProgressRatio {
    final ratio = completionRatio;
    if (!isDrivenSession) return 0.0;
    if (ratio == null) return 1.0;
    return ratio.clamp(0.0, 1.0).toDouble();
  }

  double get xpCreditedDistanceKm {
    if (!isDrivenSession) return 0.0;
    return actualDistanceKm;
  }

  bool get isRecommendationEligible {
    if (rating == null || rating! < 3) return false;
    final ratio = completionRatio;
    if (ratio == null) return true;
    return ratio >= 0.85;
  }

  String get routeSignature {
    final coordinates = flattenGeometryCoordinates(geometry);
    if (coordinates.isEmpty) {
      return '$routeType|$style|${distanceKm.toStringAsFixed(1)}';
    }

    final sampleIndexes = <int>{
      0,
      (coordinates.length * 0.25).floor(),
      (coordinates.length * 0.5).floor(),
      (coordinates.length * 0.75).floor(),
      coordinates.length - 1,
    };
    final samples = <String>[];
    for (final index in sampleIndexes.toList()..sort()) {
      final point = coordinates[index];
      final lng = point[0].toStringAsFixed(4);
      final lat = point[1].toStringAsFixed(4);
      samples.add('$lng,$lat');
    }
    return '$routeType|$style|${distanceKm.toStringAsFixed(1)}|${samples.join("|")}';
  }

  /// 2026-08-25 (vucko, Feld-Meldung „Route konnte nicht geladen werden"):
  /// Oeffentlich, weil cruise_mode_page.dart dieselbe Abflachung an drei
  /// Stellen braucht und sie dort haendisch — und falsch — nachgebaut war.
  /// Eine aufgezeichnete Fahrt mit GPS-Luecke wird als MultiLineString
  /// gespeichert; die Nachbauten lasen dann ein ganzes Segment als Punkt.
  static List<List<double>> flattenGeometryCoordinates(
    Map<String, dynamic> geometry,
  ) {
    final raw = geometry['coordinates'];
    if (raw is! List) return const [];
    if (geometry['type'] == 'MultiLineString') {
      return raw
          .whereType<List>()
          .expand(_parseCoordinateSegment)
          .toList(growable: false);
    }
    return _parseCoordinateSegment(raw);
  }

  static List<List<double>> _parseCoordinateSegment(List raw) {
    return raw
        .whereType<List>()
        .where((point) => point.length >= 2)
        .map((point) {
          final lng = point[0];
          final lat = point[1];
          if (lng is! num || lat is! num) return null;
          return [lng.toDouble(), lat.toDouble()];
        })
        .whereType<List<double>>()
        .toList(growable: false);
  }

  /// Serialisiert die Route für den lokalen Cache (shared_preferences).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'created_at': createdAt.toIso8601String(),
      'style': style,
      'distance_actual': distanceKm,
      'geometry': geometry,
      'name': name,
      'duration_seconds': durationSeconds,
      'route_type': routeType,
      'rating': rating,
      'distance_target': distanceTargetKm,
      'driven_km': drivenKm,
      'source_route_id': sourceRouteId,
      'group_id': groupId,
      'xp_distance': xpDistance,
      'xp_curve_bonus': xpCurveBonus,
      'xp_style_bonus': xpStyleBonus,
      'xp_base': xpBase,
      'xp_multiplier': xpMultiplier,
      'xp_streak_days': xpStreakDays,
      'xp_awarded': xpAwarded,
      'route_source': routeSource,
      'route_fingerprint': routeFingerprint,
      'quality_tier': qualityTier,
      'route_meta': routeMeta,
      'average_rating': averageRating,
      'rating_count': ratingCount,
      'completion_rate': completionRate,
      'completed_at_end': completedAtEnd,
      'photo_url': photoUrl,
    };
  }

  /// Formatierte Distanz (z.B. "12,4 km").
  String get formattedDistance =>
      '${distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km';

  /// Formatierte Fahrtzeit (z.B. "1h 23m").
  String get formattedDuration {
    if (durationSeconds == null) return '--';
    final minutes = (durationSeconds! / 60).round();
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  /// 2026-06-25 (vucko): Fahrzeit fürs Teilen — NIE „--". Gibt die echte Dauer
  /// zurück, sonst eine Schätzung aus Distanz ÷ stiltypischem Durchschnittstempo
  /// (Kurvenjagd langsamer, Sport schneller). So steht auf der Share-Karte immer
  /// eine sinnvolle Zeit.
  String get durationLabelOrEstimate {
    // 2026-07-28 (vucko Export-Bild): Auf der geteilten Karte stand „9h 1m"
    // fuer 26,7 km — rechnerisch 3 km/h. Der gespeicherte Wert war schlicht
    // Muell (angehaltene Fahrt, die stundenlang mitlief). Frueher wurde er
    // ungeprueft uebernommen und landete so im Bild, das Nutzer teilen.
    //
    // Jetzt: ein gespeicherter Wert zaehlt nur, wenn er zu einer plausiblen
    // Durchschnittsgeschwindigkeit fuehrt. Sonst greift dieselbe
    // stilbasierte Schaetzung wie bei fehlender Dauer — lieber eine
    // vernuenftige Schaetzung als eine peinliche Zahl.
    if (durationSeconds != null && durationSeconds! > 0) {
      if (distanceKm <= 0) return formattedDuration;
      final kmh = distanceKm / (durationSeconds! / 3600.0);
      if (kmh >= 8.0 && kmh <= 200.0) return formattedDuration;
    }
    if (distanceKm <= 0) return '--';
    final kmh = switch (style.toLowerCase()) {
      'kurvenjagd' => 46.0,
      'sport mode' || 'sport' => 66.0,
      'abendrunde' => 52.0,
      'entdecker' => 56.0,
      _ => 55.0,
    };
    final minutes = (distanceKm / kmh * 60).round();
    if (minutes <= 0) return '--';
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  /// Icon-Name für den Fahrstil.
  String get styleEmoji {
    switch (style) {
      case 'Kurvenjagd':
        return '🏔️';
      case 'Sport Mode':
        return '🏎️';
      case 'Abendrunde':
        return '🌙';
      case 'Entdecker':
        return '🧭';
      default:
        return '🛣️';
    }
  }

  String get displayStyleLabel {
    switch (style) {
      case 'Sport Mode':
        return 'Sport';
      case 'Kurvenjagd':
      case 'Abendrunde':
      case 'Entdecker':
        return style;
      default:
        return style.trim().isEmpty ? 'Route' : style;
    }
  }

  String? get qualityBadgeLabel {
    final tier = (qualityTier ?? routeMeta['quality_tier']?.toString())
        ?.trim()
        .toLowerCase();
    switch (tier) {
      case 'ideal':
        return 'Ideal';
      case 'good':
        return 'Gut';
      case 'acceptable':
        return 'Reserve';
      default:
        return null;
    }
  }

  double? get displayRating {
    if (averageRating != null && averageRating! > 0) return averageRating;
    if (rating != null && rating! > 0) return rating!.toDouble();
    return null;
  }

  String? get ratingSummaryLabel {
    final score = displayRating;
    if (score == null) return null;
    final scoreText = score.toStringAsFixed(1).replaceAll('.', ',');
    if (ratingCount > 0) {
      final suffix = ratingCount == 1 ? 'Bewertung' : 'Bewertungen';
      return '$scoreText · $ratingCount $suffix';
    }
    return '$scoreText Punkte';
  }

  String? get ratingTrustLabel {
    final score = displayRating;
    if (score == null) return null;
    if (score >= 4.4) return 'Sehr gut';
    if (score >= 3.0) return 'Okay';
    return 'Schlecht';
  }

  String? get ratingShareLabel {
    final score = displayRating;
    if (score == null) return null;
    return '${score.toStringAsFixed(1).replaceAll('.', ',')} Sterne';
  }
}
