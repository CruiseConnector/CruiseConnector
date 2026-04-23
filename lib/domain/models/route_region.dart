class RouteRegion {
  const RouteRegion({
    this.id,
    required this.countryCode,
    required this.admin1Name,
    this.admin2Name,
    required this.cityCluster,
    required this.centerLat,
    required this.centerLng,
    this.fallbackRadiusKm = 30.0,
    this.populationWeight,
    this.isActive = true,
  });

  final String? id;
  final String countryCode;
  final String admin1Name;
  final String? admin2Name;
  final String cityCluster;
  final double centerLat;
  final double centerLng;
  final double fallbackRadiusKm;
  final int? populationWeight;
  final bool isActive;

  factory RouteRegion.fromJson(Map<String, dynamic> json) {
    return RouteRegion(
      id: json['id'] as String?,
      countryCode: ((json['country_code'] as String?) ?? '').toUpperCase(),
      admin1Name: (json['admin1_name'] as String?) ?? '',
      admin2Name: json['admin2_name'] as String?,
      cityCluster: (json['city_cluster'] as String?) ?? '',
      centerLat: (json['center_lat'] as num?)?.toDouble() ?? 0.0,
      centerLng: (json['center_lng'] as num?)?.toDouble() ?? 0.0,
      fallbackRadiusKm:
          (json['fallback_radius_km'] as num?)?.toDouble() ?? 30.0,
      populationWeight: (json['population_weight'] as num?)?.toInt(),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'country_code': countryCode.toUpperCase(),
      'admin1_name': admin1Name,
      'admin2_name': admin2Name,
      'city_cluster': cityCluster,
      'center_lat': centerLat,
      'center_lng': centerLng,
      'fallback_radius_km': fallbackRadiusKm,
      'population_weight': populationWeight,
      'is_active': isActive,
    };
  }
}
