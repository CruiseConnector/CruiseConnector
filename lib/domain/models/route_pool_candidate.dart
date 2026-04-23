class RoutePoolCandidate {
  const RoutePoolCandidate({
    this.id,
    this.routeRegionId,
    required this.routeFingerprint,
    required this.countryCode,
    required this.admin1Name,
    this.admin2Name,
    required this.cityCluster,
    required this.startLat,
    required this.startLng,
    this.distanceKm,
    required this.routeType,
    required this.distanceBucket,
    required this.styleKey,
    required this.styleTags,
    required this.avoidHighways,
    required this.hasHighway,
    required this.qualityScore,
    required this.shapeScore,
    required this.candidateSource,
    this.averageRating,
    this.ratingCount = 0,
    this.completionRate,
    this.timesSelected = 0,
    this.lastSelectedAt,
    this.promotedToPoolAt,
    this.demotedAt,
    this.isCandidate = true,
    this.isVerifiedPool = false,
    this.candidateScore,
    required this.geometry,
    this.routePayload = const {},
  });

  final String? id;
  final String? routeRegionId;
  final String routeFingerprint;
  final String countryCode;
  final String admin1Name;
  final String? admin2Name;
  final String cityCluster;
  final double startLat;
  final double startLng;
  final double? distanceKm;
  final String routeType;
  final int distanceBucket;
  final String styleKey;
  final List<String> styleTags;
  final bool avoidHighways;
  final bool hasHighway;
  final double qualityScore;
  final double shapeScore;
  final String candidateSource;
  final double? averageRating;
  final int ratingCount;
  final double? completionRate;
  final int timesSelected;
  final DateTime? lastSelectedAt;
  final DateTime? promotedToPoolAt;
  final DateTime? demotedAt;
  final bool isCandidate;
  final bool isVerifiedPool;
  final double? candidateScore;
  final Map<String, dynamic> geometry;
  final Map<String, dynamic> routePayload;

  factory RoutePoolCandidate.fromJson(Map<String, dynamic> json) {
    return RoutePoolCandidate(
      id: json['id'] as String?,
      routeRegionId: json['route_region_id'] as String?,
      routeFingerprint: (json['route_fingerprint'] as String?) ?? '',
      countryCode: ((json['country_code'] as String?) ?? '').toUpperCase(),
      admin1Name: (json['admin1_name'] as String?) ?? '',
      admin2Name: json['admin2_name'] as String?,
      cityCluster: (json['city_cluster'] as String?) ?? '',
      startLat: (json['start_lat'] as num?)?.toDouble() ?? 0.0,
      startLng: (json['start_lng'] as num?)?.toDouble() ?? 0.0,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      routeType: (json['route_type'] as String?) ?? 'ROUND_TRIP',
      distanceBucket: (json['distance_bucket'] as num?)?.toInt() ?? 0,
      styleKey: (json['style_key'] as String?) ?? 'standard',
      styleTags: _readCandidateStyleTags(json['style_tags']),
      avoidHighways: (json['avoid_highways'] as bool?) ?? false,
      hasHighway: (json['has_highway'] as bool?) ?? false,
      qualityScore: (json['quality_score'] as num?)?.toDouble() ?? 0.0,
      shapeScore: (json['shape_score'] as num?)?.toDouble() ?? 0.0,
      candidateSource: (json['candidate_source'] as String?) ?? 'basic_live',
      averageRating: (json['average_rating'] as num?)?.toDouble(),
      ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
      completionRate: (json['completion_rate'] as num?)?.toDouble(),
      timesSelected: (json['times_selected'] as num?)?.toInt() ?? 0,
      lastSelectedAt: _readCandidateDateTime(json['last_selected_at']),
      promotedToPoolAt: _readCandidateDateTime(json['promoted_to_pool_at']),
      demotedAt: _readCandidateDateTime(json['demoted_at']),
      isCandidate: (json['is_candidate'] as bool?) ?? true,
      isVerifiedPool: (json['is_verified_pool'] as bool?) ?? false,
      candidateScore: (json['candidate_score'] as num?)?.toDouble(),
      geometry: json['geometry'] is Map
          ? Map<String, dynamic>.from(json['geometry'] as Map)
          : const <String, dynamic>{},
      routePayload: json['route_payload'] is Map
          ? Map<String, dynamic>.from(json['route_payload'] as Map)
          : const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'route_region_id': routeRegionId,
      'route_fingerprint': routeFingerprint,
      'country_code': countryCode.toUpperCase(),
      'admin1_name': admin1Name,
      'admin2_name': admin2Name,
      'city_cluster': cityCluster,
      'start_lat': startLat,
      'start_lng': startLng,
      'distance_km': distanceKm,
      'route_type': routeType,
      'distance_bucket': distanceBucket,
      'style_key': styleKey,
      'style_tags': styleTags,
      'avoid_highways': avoidHighways,
      'has_highway': hasHighway,
      'quality_score': qualityScore,
      'shape_score': shapeScore,
      'candidate_source': candidateSource,
      'average_rating': averageRating,
      'rating_count': ratingCount,
      'completion_rate': completionRate,
      'times_selected': timesSelected,
      'last_selected_at': lastSelectedAt?.toIso8601String(),
      'promoted_to_pool_at': promotedToPoolAt?.toIso8601String(),
      'demoted_at': demotedAt?.toIso8601String(),
      'is_candidate': isCandidate,
      'is_verified_pool': isVerifiedPool,
      'candidate_score': candidateScore,
      'geometry': geometry,
      'route_payload': routePayload,
    };
  }
}

List<String> _readCandidateStyleTags(Object? raw) {
  if (raw is List) {
    return raw.map((item) => item.toString()).toList(growable: false);
  }
  if (raw is String && raw.trim().isNotEmpty) {
    return raw
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return const [];
}

DateTime? _readCandidateDateTime(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw)?.toUtc();
  }
  return null;
}
