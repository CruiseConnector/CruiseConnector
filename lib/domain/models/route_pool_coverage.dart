class RoutePoolCoverage {
  const RoutePoolCoverage({
    this.id,
    this.routeRegionId,
    required this.countryCode,
    required this.admin1Name,
    this.admin2Name,
    required this.cityCluster,
    required this.routeType,
    required this.distanceBucket,
    required this.styleKey,
    required this.avoidHighways,
    required this.coverageStatus,
    this.difficultyLevel = 'normal',
    this.hardRegionStatus = 'normal',
    this.bootstrapEnabled = true,
    this.curatedSeedPreferred = false,
    this.targetPoolSize = 15,
    this.maxPoolSize = 20,
    this.healthyThreshold = 15,
    this.thinThreshold = 1,
    this.currentVerifiedCount = 0,
    this.currentCandidateCount = 0,
    this.seedBudgetUnits = 1,
    this.seedCooldownMinutes = 20,
    this.lastCountedAt,
    this.lastBootstrapRequestedAt,
    this.lastSeedCompletedAt,
    this.bootstrapCooldownUntil,
    this.lastError,
  });

  final String? id;
  final String? routeRegionId;
  final String countryCode;
  final String admin1Name;
  final String? admin2Name;
  final String cityCluster;
  final String routeType;
  final int distanceBucket;
  final String styleKey;
  final bool avoidHighways;
  final String coverageStatus;
  final String difficultyLevel;
  final String hardRegionStatus;
  final bool bootstrapEnabled;
  final bool curatedSeedPreferred;
  final int targetPoolSize;
  final int maxPoolSize;
  final int healthyThreshold;
  final int thinThreshold;
  final int currentVerifiedCount;
  final int currentCandidateCount;
  final int seedBudgetUnits;
  final int seedCooldownMinutes;
  final DateTime? lastCountedAt;
  final DateTime? lastBootstrapRequestedAt;
  final DateTime? lastSeedCompletedAt;
  final DateTime? bootstrapCooldownUntil;
  final String? lastError;

  bool get isHealthy => coverageStatus == 'healthy';
  bool get isThin => coverageStatus == 'thin';
  bool get isEmpty => coverageStatus == 'empty';
  bool get isWarmingUp => coverageStatus == 'warming_up';
  bool get isCooldown => coverageStatus == 'cooldown';
  bool get isHardRegionThin => coverageStatus == 'hard_region_thin';
  bool get isHardRegionCuratedNeeded =>
      coverageStatus == 'hard_region_curated_needed';
  bool get isBootstrapLimited => coverageStatus == 'bootstrap_limited';
  bool get isPoolFull => currentVerifiedCount >= maxPoolSize;

  RoutePoolCoverage copyWith({
    String? id,
    String? routeRegionId,
    String? countryCode,
    String? admin1Name,
    String? admin2Name,
    String? cityCluster,
    String? routeType,
    int? distanceBucket,
    String? styleKey,
    bool? avoidHighways,
    String? coverageStatus,
    String? difficultyLevel,
    String? hardRegionStatus,
    bool? bootstrapEnabled,
    bool? curatedSeedPreferred,
    int? targetPoolSize,
    int? maxPoolSize,
    int? healthyThreshold,
    int? thinThreshold,
    int? currentVerifiedCount,
    int? currentCandidateCount,
    int? seedBudgetUnits,
    int? seedCooldownMinutes,
    DateTime? lastCountedAt,
    DateTime? lastBootstrapRequestedAt,
    DateTime? lastSeedCompletedAt,
    DateTime? bootstrapCooldownUntil,
    String? lastError,
  }) {
    return RoutePoolCoverage(
      id: id ?? this.id,
      routeRegionId: routeRegionId ?? this.routeRegionId,
      countryCode: countryCode ?? this.countryCode,
      admin1Name: admin1Name ?? this.admin1Name,
      admin2Name: admin2Name ?? this.admin2Name,
      cityCluster: cityCluster ?? this.cityCluster,
      routeType: routeType ?? this.routeType,
      distanceBucket: distanceBucket ?? this.distanceBucket,
      styleKey: styleKey ?? this.styleKey,
      avoidHighways: avoidHighways ?? this.avoidHighways,
      coverageStatus: coverageStatus ?? this.coverageStatus,
      difficultyLevel: difficultyLevel ?? this.difficultyLevel,
      hardRegionStatus: hardRegionStatus ?? this.hardRegionStatus,
      bootstrapEnabled: bootstrapEnabled ?? this.bootstrapEnabled,
      curatedSeedPreferred:
          curatedSeedPreferred ?? this.curatedSeedPreferred,
      targetPoolSize: targetPoolSize ?? this.targetPoolSize,
      maxPoolSize: maxPoolSize ?? this.maxPoolSize,
      healthyThreshold: healthyThreshold ?? this.healthyThreshold,
      thinThreshold: thinThreshold ?? this.thinThreshold,
      currentVerifiedCount: currentVerifiedCount ?? this.currentVerifiedCount,
      currentCandidateCount:
          currentCandidateCount ?? this.currentCandidateCount,
      seedBudgetUnits: seedBudgetUnits ?? this.seedBudgetUnits,
      seedCooldownMinutes: seedCooldownMinutes ?? this.seedCooldownMinutes,
      lastCountedAt: lastCountedAt ?? this.lastCountedAt,
      lastBootstrapRequestedAt:
          lastBootstrapRequestedAt ?? this.lastBootstrapRequestedAt,
      lastSeedCompletedAt: lastSeedCompletedAt ?? this.lastSeedCompletedAt,
      bootstrapCooldownUntil:
          bootstrapCooldownUntil ?? this.bootstrapCooldownUntil,
      lastError: lastError ?? this.lastError,
    );
  }

  factory RoutePoolCoverage.fromJson(Map<String, dynamic> json) {
    return RoutePoolCoverage(
      id: json['id'] as String?,
      routeRegionId: json['route_region_id'] as String?,
      countryCode: ((json['country_code'] as String?) ?? '').toUpperCase(),
      admin1Name: (json['admin1_name'] as String?) ?? '',
      admin2Name: json['admin2_name'] as String?,
      cityCluster: (json['city_cluster'] as String?) ?? '',
      routeType: (json['route_type'] as String?) ?? 'ROUND_TRIP',
      distanceBucket: (json['distance_bucket'] as num?)?.toInt() ?? 0,
      styleKey: (json['style_key'] as String?) ?? 'standard',
      avoidHighways: (json['avoid_highways'] as bool?) ?? false,
      coverageStatus: (json['coverage_status'] as String?) ?? 'empty',
      difficultyLevel: (json['difficulty_level'] as String?) ?? 'normal',
      hardRegionStatus: (json['hard_region_status'] as String?) ?? 'normal',
      bootstrapEnabled: (json['bootstrap_enabled'] as bool?) ?? true,
      curatedSeedPreferred:
          (json['curated_seed_preferred'] as bool?) ?? false,
      targetPoolSize: (json['target_pool_size'] as num?)?.toInt() ?? 15,
      maxPoolSize: (json['max_pool_size'] as num?)?.toInt() ?? 20,
      healthyThreshold: (json['healthy_threshold'] as num?)?.toInt() ?? 15,
      thinThreshold: (json['thin_threshold'] as num?)?.toInt() ?? 1,
      currentVerifiedCount:
          (json['current_verified_count'] as num?)?.toInt() ?? 0,
      currentCandidateCount:
          (json['current_candidate_count'] as num?)?.toInt() ?? 0,
      seedBudgetUnits: (json['seed_budget_units'] as num?)?.toInt() ?? 1,
      seedCooldownMinutes:
          (json['seed_cooldown_minutes'] as num?)?.toInt() ?? 20,
      lastCountedAt: _readDateTime(json['last_counted_at']),
      lastBootstrapRequestedAt: _readDateTime(
        json['last_bootstrap_requested_at'],
      ),
      lastSeedCompletedAt: _readDateTime(json['last_seed_completed_at']),
      bootstrapCooldownUntil: _readDateTime(json['bootstrap_cooldown_until']),
      lastError: json['last_error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'route_region_id': routeRegionId,
      'country_code': countryCode.toUpperCase(),
      'admin1_name': admin1Name,
      'admin2_name': admin2Name,
      'city_cluster': cityCluster,
      'route_type': routeType,
      'distance_bucket': distanceBucket,
      'style_key': styleKey,
      'avoid_highways': avoidHighways,
      'coverage_status': coverageStatus,
      'difficulty_level': difficultyLevel,
      'hard_region_status': hardRegionStatus,
      'bootstrap_enabled': bootstrapEnabled,
      'curated_seed_preferred': curatedSeedPreferred,
      'target_pool_size': targetPoolSize,
      'max_pool_size': maxPoolSize,
      'healthy_threshold': healthyThreshold,
      'thin_threshold': thinThreshold,
      'current_verified_count': currentVerifiedCount,
      'current_candidate_count': currentCandidateCount,
      'seed_budget_units': seedBudgetUnits,
      'seed_cooldown_minutes': seedCooldownMinutes,
      'last_counted_at': lastCountedAt?.toIso8601String(),
      'last_bootstrap_requested_at': lastBootstrapRequestedAt
          ?.toIso8601String(),
      'last_seed_completed_at': lastSeedCompletedAt?.toIso8601String(),
      'bootstrap_cooldown_until': bootstrapCooldownUntil?.toIso8601String(),
      'last_error': lastError,
    };
  }
}

DateTime? _readDateTime(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw)?.toUtc();
  }
  return null;
}
