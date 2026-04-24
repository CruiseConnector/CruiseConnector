/// Eine gespeicherte Route aus der Supabase `routes` Tabelle.
class SavedRoute {
  const SavedRoute({
    required this.id,
    required this.createdAt,
    required this.style,
    required this.distanceKm,
    required this.geometry,
    this.name,
    this.durationSeconds,
    this.routeType,
    this.rating,
    this.distanceTargetKm,
    this.drivenKm,
    this.sourceRouteId,
  });

  final String id;
  final DateTime createdAt;
  final String style;
  final double distanceKm;
  final Map<String, dynamic> geometry;
  final String? name;
  final double? durationSeconds;
  final String? routeType;
  final int? rating;
  final double? distanceTargetKm;
  final double? drivenKm;
  final String? sourceRouteId;

  factory SavedRoute.fromJson(Map<String, dynamic> json) {
    return SavedRoute(
      id: json['id'] as String,
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
    );
  }

  bool get isRoundTrip => routeType == 'ROUND_TRIP';

  bool get isDrivenSession => (drivenKm ?? 0) > 0;

  double get actualDistanceKm => drivenKm ?? distanceKm;

  double? get completionRatio {
    if (!isDrivenSession) return null;
    final planned = distanceTargetKm;
    if (planned == null || planned <= 0) return null;
    return (actualDistanceKm / planned).clamp(0.0, 1.0);
  }

  bool get qualifiesForXpCredit {
    final ratio = completionRatio;
    if (!isDrivenSession) return false;
    if (ratio == null) return true;
    return ratio >= 0.10;
  }

  bool get isRecommendationEligible {
    if (rating == null || rating! < 3) return false;
    final ratio = completionRatio;
    if (ratio == null) return true;
    return ratio >= 0.85;
  }

  String get routeSignature {
    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.isEmpty) {
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
      if (point is List && point.length >= 2) {
        final lng = (point[0] as num).toDouble().toStringAsFixed(4);
        final lat = (point[1] as num).toDouble().toStringAsFixed(4);
        samples.add('$lng,$lat');
      }
    }
    return '$routeType|$style|${distanceKm.toStringAsFixed(1)}|${samples.join("|")}';
  }

  /// Serialisiert die Route für den lokalen Cache (shared_preferences).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
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
}
