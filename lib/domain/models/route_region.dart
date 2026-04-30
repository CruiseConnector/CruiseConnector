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
    this.clusterKind = 'city_cluster',
    this.bootstrapEnabled = true,
    this.difficultyLevel = 'normal',
    this.hardRegionStatus = 'normal',
    this.curatedSeedPreferred = false,
    this.defaultMinVerifiedCount = 3,
    this.defaultTargetPoolSize = 15,
    this.defaultMaxPoolSize = 20,
    this.healthyThreshold = 15,
    this.thinThreshold = 1,
    this.seedBudgetUnits = 1,
    this.seedCooldownMinutes = 20,
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
  final String clusterKind;
  final bool bootstrapEnabled;
  final String difficultyLevel;
  final String hardRegionStatus;
  final bool curatedSeedPreferred;
  final int defaultMinVerifiedCount;
  final int defaultTargetPoolSize;
  final int defaultMaxPoolSize;
  final int healthyThreshold;
  final int thinThreshold;
  final int seedBudgetUnits;
  final int seedCooldownMinutes;
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
      clusterKind: (json['cluster_kind'] as String?) ?? 'city_cluster',
      bootstrapEnabled: (json['bootstrap_enabled'] as bool?) ?? true,
      difficultyLevel: (json['difficulty_level'] as String?) ?? 'normal',
      hardRegionStatus: (json['hard_region_status'] as String?) ?? 'normal',
      curatedSeedPreferred: (json['curated_seed_preferred'] as bool?) ?? false,
      defaultMinVerifiedCount:
          (json['default_min_verified_count'] as num?)?.toInt() ?? 3,
      defaultTargetPoolSize:
          (json['default_target_pool_size'] as num?)?.toInt() ?? 15,
      defaultMaxPoolSize:
          (json['default_max_pool_size'] as num?)?.toInt() ?? 20,
      healthyThreshold: (json['healthy_threshold'] as num?)?.toInt() ?? 15,
      thinThreshold: (json['thin_threshold'] as num?)?.toInt() ?? 1,
      seedBudgetUnits: (json['seed_budget_units'] as num?)?.toInt() ?? 1,
      seedCooldownMinutes:
          (json['seed_cooldown_minutes'] as num?)?.toInt() ?? 20,
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
      'cluster_kind': clusterKind,
      'bootstrap_enabled': bootstrapEnabled,
      'difficulty_level': difficultyLevel,
      'hard_region_status': hardRegionStatus,
      'curated_seed_preferred': curatedSeedPreferred,
      'default_min_verified_count': defaultMinVerifiedCount,
      'default_target_pool_size': defaultTargetPoolSize,
      'default_max_pool_size': defaultMaxPoolSize,
      'healthy_threshold': healthyThreshold,
      'thin_threshold': thinThreshold,
      'seed_budget_units': seedBudgetUnits,
      'seed_cooldown_minutes': seedCooldownMinutes,
      'is_active': isActive,
    };
  }
}
