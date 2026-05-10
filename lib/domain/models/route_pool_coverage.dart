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
    this.minVerifiedCount = 3,
    this.targetPoolSize = 12,
    this.maxPoolSize = 32,
    this.candidateBufferLimit = 72,
    this.acceptableReserveLimitPercent = 25,
    this.healthyThreshold = 3,
    this.thinThreshold = 1,
    this.currentVerifiedCount = 0,
    this.currentCandidateCount = 0,
    this.idealCount = 0,
    this.goodCount = 0,
    this.acceptableCount = 0,
    this.rejectedCount = 0,
    this.distinctFingerprintCount = 0,
    this.seedBudgetUnits = 1,
    this.seedCooldownMinutes = 20,
    this.healingStatus = 'idle',
    this.healingPriority = 0,
    this.healingAttemptCount = 0,
    this.healingFailureCount = 0,
    this.dailyAttemptBudget = 12,
    this.monthlyAttemptBudget = 120,
    this.healingCallsToday = 0,
    this.healingCallsMonth = 0,
    this.healingBudgetWindowDate,
    this.healingBudgetWindowMonth,
    this.nextHealingAt,
    this.lastHealingJobId,
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
  final int minVerifiedCount;
  final int targetPoolSize;
  final int maxPoolSize;
  final int candidateBufferLimit;
  final int acceptableReserveLimitPercent;
  final int healthyThreshold;
  final int thinThreshold;
  final int currentVerifiedCount;
  final int currentCandidateCount;
  final int idealCount;
  final int goodCount;
  final int acceptableCount;
  final int rejectedCount;
  final int distinctFingerprintCount;
  final int seedBudgetUnits;
  final int seedCooldownMinutes;
  final String healingStatus;
  final int healingPriority;
  final int healingAttemptCount;
  final int healingFailureCount;
  final int dailyAttemptBudget;
  final int monthlyAttemptBudget;
  final int healingCallsToday;
  final int healingCallsMonth;
  final DateTime? healingBudgetWindowDate;
  final DateTime? healingBudgetWindowMonth;
  final DateTime? nextHealingAt;
  final String? lastHealingJobId;
  final DateTime? lastCountedAt;
  final DateTime? lastBootstrapRequestedAt;
  final DateTime? lastSeedCompletedAt;
  final DateTime? bootstrapCooldownUntil;
  final String? lastError;

  bool get isHealthy =>
      coverageStatus == 'healthy' || coverageStatus == 'target_met';
  bool get isTargetMet => coverageStatus == 'target_met';
  bool get isOverfull => coverageStatus == 'overfull';
  bool get isQualityThin => coverageStatus == 'quality_thin';
  bool get isThin => coverageStatus == 'thin';
  bool get isEmpty => coverageStatus == 'empty';
  bool get isWarmingUp => coverageStatus == 'warming_up';
  bool get isCooldown => coverageStatus == 'cooldown';
  bool get isHardRegionThin => coverageStatus == 'hard_region_thin';
  bool get isHardRegionCuratedNeeded =>
      coverageStatus == 'hard_region_curated_needed';
  bool get isBootstrapLimited => coverageStatus == 'bootstrap_limited';
  bool get isPoolFull => currentVerifiedCount >= maxPoolSize;
  bool get healingQueued => healingStatus == 'healing_queued';
  bool get healingRunning => healingStatus == 'healing_running';
  bool get healingPausedBudget => healingStatus == 'healing_paused_budget';

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
    int? minVerifiedCount,
    int? targetPoolSize,
    int? maxPoolSize,
    int? candidateBufferLimit,
    int? acceptableReserveLimitPercent,
    int? healthyThreshold,
    int? thinThreshold,
    int? currentVerifiedCount,
    int? currentCandidateCount,
    int? idealCount,
    int? goodCount,
    int? acceptableCount,
    int? rejectedCount,
    int? distinctFingerprintCount,
    int? seedBudgetUnits,
    int? seedCooldownMinutes,
    String? healingStatus,
    int? healingPriority,
    int? healingAttemptCount,
    int? healingFailureCount,
    int? dailyAttemptBudget,
    int? monthlyAttemptBudget,
    int? healingCallsToday,
    int? healingCallsMonth,
    DateTime? healingBudgetWindowDate,
    DateTime? healingBudgetWindowMonth,
    DateTime? nextHealingAt,
    String? lastHealingJobId,
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
      curatedSeedPreferred: curatedSeedPreferred ?? this.curatedSeedPreferred,
      minVerifiedCount: minVerifiedCount ?? this.minVerifiedCount,
      targetPoolSize: targetPoolSize ?? this.targetPoolSize,
      maxPoolSize: maxPoolSize ?? this.maxPoolSize,
      candidateBufferLimit: candidateBufferLimit ?? this.candidateBufferLimit,
      acceptableReserveLimitPercent:
          acceptableReserveLimitPercent ?? this.acceptableReserveLimitPercent,
      healthyThreshold: healthyThreshold ?? this.healthyThreshold,
      thinThreshold: thinThreshold ?? this.thinThreshold,
      currentVerifiedCount: currentVerifiedCount ?? this.currentVerifiedCount,
      currentCandidateCount:
          currentCandidateCount ?? this.currentCandidateCount,
      idealCount: idealCount ?? this.idealCount,
      goodCount: goodCount ?? this.goodCount,
      acceptableCount: acceptableCount ?? this.acceptableCount,
      rejectedCount: rejectedCount ?? this.rejectedCount,
      distinctFingerprintCount:
          distinctFingerprintCount ?? this.distinctFingerprintCount,
      seedBudgetUnits: seedBudgetUnits ?? this.seedBudgetUnits,
      seedCooldownMinutes: seedCooldownMinutes ?? this.seedCooldownMinutes,
      healingStatus: healingStatus ?? this.healingStatus,
      healingPriority: healingPriority ?? this.healingPriority,
      healingAttemptCount: healingAttemptCount ?? this.healingAttemptCount,
      healingFailureCount: healingFailureCount ?? this.healingFailureCount,
      dailyAttemptBudget: dailyAttemptBudget ?? this.dailyAttemptBudget,
      monthlyAttemptBudget: monthlyAttemptBudget ?? this.monthlyAttemptBudget,
      healingCallsToday: healingCallsToday ?? this.healingCallsToday,
      healingCallsMonth: healingCallsMonth ?? this.healingCallsMonth,
      healingBudgetWindowDate:
          healingBudgetWindowDate ?? this.healingBudgetWindowDate,
      healingBudgetWindowMonth:
          healingBudgetWindowMonth ?? this.healingBudgetWindowMonth,
      nextHealingAt: nextHealingAt ?? this.nextHealingAt,
      lastHealingJobId: lastHealingJobId ?? this.lastHealingJobId,
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
      curatedSeedPreferred: (json['curated_seed_preferred'] as bool?) ?? false,
      minVerifiedCount: (json['min_verified_count'] as num?)?.toInt() ?? 3,
      targetPoolSize: (json['target_pool_size'] as num?)?.toInt() ?? 12,
      maxPoolSize: (json['max_pool_size'] as num?)?.toInt() ?? 32,
      candidateBufferLimit:
          (json['candidate_buffer_limit'] as num?)?.toInt() ?? 72,
      acceptableReserveLimitPercent:
          (json['acceptable_reserve_limit_percent'] as num?)?.toInt() ?? 25,
      healthyThreshold: (json['healthy_threshold'] as num?)?.toInt() ?? 3,
      thinThreshold: (json['thin_threshold'] as num?)?.toInt() ?? 1,
      currentVerifiedCount:
          (json['current_verified_count'] as num?)?.toInt() ?? 0,
      currentCandidateCount:
          (json['current_candidate_count'] as num?)?.toInt() ?? 0,
      idealCount: (json['ideal_count'] as num?)?.toInt() ?? 0,
      goodCount: (json['good_count'] as num?)?.toInt() ?? 0,
      acceptableCount: (json['acceptable_count'] as num?)?.toInt() ?? 0,
      rejectedCount: (json['rejected_count'] as num?)?.toInt() ?? 0,
      distinctFingerprintCount:
          (json['distinct_fingerprint_count'] as num?)?.toInt() ?? 0,
      seedBudgetUnits: (json['seed_budget_units'] as num?)?.toInt() ?? 1,
      seedCooldownMinutes:
          (json['seed_cooldown_minutes'] as num?)?.toInt() ?? 20,
      healingStatus: (json['healing_status'] as String?) ?? 'idle',
      healingPriority: (json['healing_priority'] as num?)?.toInt() ?? 0,
      healingAttemptCount:
          (json['healing_attempt_count'] as num?)?.toInt() ?? 0,
      healingFailureCount:
          (json['healing_failure_count'] as num?)?.toInt() ?? 0,
      dailyAttemptBudget:
          (json['daily_attempt_budget'] as num?)?.toInt() ?? 120,
      monthlyAttemptBudget:
          (json['monthly_attempt_budget'] as num?)?.toInt() ?? 2000,
      healingCallsToday: (json['healing_calls_today'] as num?)?.toInt() ?? 0,
      healingCallsMonth: (json['healing_calls_month'] as num?)?.toInt() ?? 0,
      healingBudgetWindowDate: _readDateTime(
        json['healing_budget_window_date'],
      ),
      healingBudgetWindowMonth: _readDateTime(
        json['healing_budget_window_month'],
      ),
      nextHealingAt: _readDateTime(json['next_healing_at']),
      lastHealingJobId: json['last_healing_job_id'] as String?,
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
      'min_verified_count': minVerifiedCount,
      'target_pool_size': targetPoolSize,
      'max_pool_size': maxPoolSize,
      'candidate_buffer_limit': candidateBufferLimit,
      'acceptable_reserve_limit_percent': acceptableReserveLimitPercent,
      'healthy_threshold': healthyThreshold,
      'thin_threshold': thinThreshold,
      'current_verified_count': currentVerifiedCount,
      'current_candidate_count': currentCandidateCount,
      'ideal_count': idealCount,
      'good_count': goodCount,
      'acceptable_count': acceptableCount,
      'rejected_count': rejectedCount,
      'distinct_fingerprint_count': distinctFingerprintCount,
      'seed_budget_units': seedBudgetUnits,
      'seed_cooldown_minutes': seedCooldownMinutes,
      'healing_status': healingStatus,
      'healing_priority': healingPriority,
      'healing_attempt_count': healingAttemptCount,
      'healing_failure_count': healingFailureCount,
      'daily_attempt_budget': dailyAttemptBudget,
      'monthly_attempt_budget': monthlyAttemptBudget,
      'healing_calls_today': healingCallsToday,
      'healing_calls_month': healingCallsMonth,
      'healing_budget_window_date': _dateOnlyString(healingBudgetWindowDate),
      'healing_budget_window_month': _dateOnlyString(healingBudgetWindowMonth),
      'next_healing_at': nextHealingAt?.toIso8601String(),
      'last_healing_job_id': lastHealingJobId,
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

String? _dateOnlyString(DateTime? value) {
  if (value == null) return null;
  return value.toUtc().toIso8601String().split('T').first;
}
