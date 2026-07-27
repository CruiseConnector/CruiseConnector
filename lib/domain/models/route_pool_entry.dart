class RoutePoolEntry {
  const RoutePoolEntry({
    required this.id,
    this.title,
    required this.countryCode,
    required this.admin1Name,
    this.admin2Name,
    required this.cityCluster,
    required this.startLat,
    required this.startLng,
    this.endLat,
    this.endLng,
    required this.distanceKm,
    required this.distanceBucket,
    required this.routeType,
    required this.styleTags,
    required this.avoidsHighway,
    required this.hasHighway,
    required this.qualityScore,
    required this.verified,
    this.isActive = true,
    required this.geometry,
    this.durationSeconds,
    this.shapeScore = 0.0,
    this.userRating,
    this.averageRating,
    this.ratingCount = 0,
    this.completionRate,
    this.weeklyRotationScore = 0.0,
    this.lastSuggestedAt,
    this.deprecatedAt,
    this.usageCount = 0,
    this.source = 'curated',
    this.routePayload = const {},
  });

  final String id;
  final String? title;
  final String countryCode;
  final String admin1Name;
  final String? admin2Name;
  final String cityCluster;
  final double startLat;
  final double startLng;
  final double? endLat;
  final double? endLng;
  final double distanceKm;
  final int distanceBucket;
  final String routeType;
  final List<String> styleTags;
  final bool avoidsHighway;
  final bool hasHighway;
  final double qualityScore;
  final bool verified;
  final bool isActive;
  final Map<String, dynamic> geometry;
  final double? durationSeconds;
  final double shapeScore;
  final double? userRating;
  final double? averageRating;
  final int ratingCount;
  final double? completionRate;
  final double weeklyRotationScore;

  /// Wann diese Pool-Route zuletzt jemandem vorgeschlagen wurde.
  ///
  /// 2026-07-27 (vucko „wir haben sehr oft die gleiche Route bekommen"):
  /// Die Spalte gab es in der Datenbank und die Abfrage sortierte auch danach —
  /// sie wurde nur nie ins Modell uebernommen und konnte deshalb bei der
  /// eigentlichen Auswahl im Client gar nicht beruecksichtigt werden.
  final DateTime? lastSuggestedAt;
  final DateTime? deprecatedAt;
  final int usageCount;
  final String source;
  final Map<String, dynamic> routePayload;

  factory RoutePoolEntry.fromJson(Map<String, dynamic> json) {
    final payload = json['route_payload'] is Map
        ? Map<String, dynamic>.from(json['route_payload'] as Map)
        : const <String, dynamic>{};
    final geometry = json['geometry'] is Map
        ? Map<String, dynamic>.from(json['geometry'] as Map)
        : payload['geometry'] is Map
        ? Map<String, dynamic>.from(payload['geometry'] as Map)
        : const <String, dynamic>{};
    return RoutePoolEntry(
      id: json['id'] as String,
      title: json['title'] as String?,
      countryCode: ((json['country_code'] as String?) ?? '').toUpperCase(),
      admin1Name: (json['admin1_name'] as String?) ?? '',
      admin2Name: json['admin2_name'] as String?,
      cityCluster: (json['city_cluster'] as String?) ?? '',
      startLat: (json['start_lat'] as num?)?.toDouble() ?? 0.0,
      startLng: (json['start_lng'] as num?)?.toDouble() ?? 0.0,
      endLat: (json['end_lat'] as num?)?.toDouble(),
      endLng: (json['end_lng'] as num?)?.toDouble(),
      distanceKm:
          (json['distance_km'] as num?)?.toDouble() ??
          (json['distance_actual'] as num?)?.toDouble() ??
          0.0,
      distanceBucket: (json['distance_bucket'] as num?)?.toInt() ?? 0,
      routeType: (json['route_type'] as String?) ?? 'ROUND_TRIP',
      styleTags: _readStyleTags(json['style_tags']),
      avoidsHighway: (json['avoids_highway'] as bool?) ?? false,
      hasHighway: (json['has_highway'] as bool?) ?? false,
      qualityScore: (json['quality_score'] as num?)?.toDouble() ?? 0.0,
      verified: (json['verified'] as bool?) ?? false,
      isActive: (json['is_active'] as bool?) ?? true,
      geometry: geometry,
      durationSeconds:
          (json['duration_seconds'] as num?)?.toDouble() ??
          (payload['duration_seconds'] as num?)?.toDouble(),
      shapeScore: (json['shape_score'] as num?)?.toDouble() ?? 0.0,
      userRating: (json['user_rating'] as num?)?.toDouble(),
      averageRating: (json['average_rating'] as num?)?.toDouble(),
      ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
      completionRate: (json['completion_rate'] as num?)?.toDouble(),
      weeklyRotationScore:
          (json['weekly_rotation_score'] as num?)?.toDouble() ?? 0.0,
      lastSuggestedAt: _readRoutePoolDateTime(json['last_suggested_at']),
      deprecatedAt: _readRoutePoolDateTime(json['deprecated_at']),
      usageCount: (json['usage_count'] as num?)?.toInt() ?? 0,
      source: (json['source'] as String?) ?? 'curated',
      routePayload: payload,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'country_code': countryCode.toUpperCase(),
      'admin1_name': admin1Name,
      'admin2_name': admin2Name,
      'city_cluster': cityCluster,
      'start_lat': startLat,
      'start_lng': startLng,
      'end_lat': endLat,
      'end_lng': endLng,
      'distance_km': distanceKm,
      'distance_bucket': distanceBucket,
      'route_type': routeType,
      'style_tags': styleTags,
      'avoids_highway': avoidsHighway,
      'has_highway': hasHighway,
      'quality_score': qualityScore,
      'verified': verified,
      'is_active': isActive,
      'geometry': geometry,
      'duration_seconds': durationSeconds,
      'shape_score': shapeScore,
      'user_rating': userRating,
      'average_rating': averageRating,
      'rating_count': ratingCount,
      'completion_rate': completionRate,
      'weekly_rotation_score': weeklyRotationScore,
      'deprecated_at': deprecatedAt?.toIso8601String(),
      'usage_count': usageCount,
      'source': source,
      'route_payload': routePayload,
    };
  }
}

List<String> _readStyleTags(Object? raw) {
  if (raw is List) {
    return raw.map((item) => item.toString()).toList(growable: false);
  }
  if (raw is String && raw.trim().isNotEmpty) {
    return raw.split(',').map((item) => item.trim()).toList(growable: false);
  }
  return const [];
}

DateTime? _readRoutePoolDateTime(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw)?.toUtc();
  }
  return null;
}
