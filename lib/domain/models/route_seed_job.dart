class RouteSeedJob {
  const RouteSeedJob({
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
    required this.status,
    this.difficultyLevel = 'normal',
    this.hardRegionStatus = 'normal',
    this.priority = 0,
    this.maxAttempts = 3,
    this.attemptCount = 0,
    this.failureCount = 0,
    this.seedBudgetUnits = 1,
    this.seedCooldownMinutes = 20,
    this.jobKind = 'seed_healing',
    this.maxMapboxCalls = 8,
    this.mapboxCallsUsed = 0,
    this.verifiedInsertedCount = 0,
    this.candidateInsertedCount = 0,
    this.dailyAttemptBudget = 12,
    this.monthlyAttemptBudget = 120,
    this.dailyAttemptCount = 0,
    this.monthlyAttemptCount = 0,
    this.budgetWindowDate,
    this.budgetWindowMonth,
    this.lastError,
    this.lastFailureReason,
    this.cooldownUntil,
    this.nextRetryAt,
    this.lastRequestedAt,
    this.startedAt,
    this.completedAt,
    this.completedReason,
    this.triggeredByTier,
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
  final String status;
  final String difficultyLevel;
  final String hardRegionStatus;
  final int priority;
  final int maxAttempts;
  final int attemptCount;
  final int failureCount;
  final int seedBudgetUnits;
  final int seedCooldownMinutes;
  final String jobKind;
  final int maxMapboxCalls;
  final int mapboxCallsUsed;
  final int verifiedInsertedCount;
  final int candidateInsertedCount;
  final int dailyAttemptBudget;
  final int monthlyAttemptBudget;
  final int dailyAttemptCount;
  final int monthlyAttemptCount;
  final DateTime? budgetWindowDate;
  final DateTime? budgetWindowMonth;
  final String? lastError;
  final String? lastFailureReason;
  final DateTime? cooldownUntil;
  final DateTime? nextRetryAt;
  final DateTime? lastRequestedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? completedReason;
  final String? triggeredByTier;

  bool get isQueued => status == 'queued';
  bool get isRunning => status == 'running';
  bool get isActive => isQueued || isRunning;
  bool get isBudgetPaused => status == 'paused_budget';
  bool get isCoolingDown =>
      (cooldownUntil != null &&
          cooldownUntil!.isAfter(DateTime.now().toUtc())) ||
      (nextRetryAt != null && nextRetryAt!.isAfter(DateTime.now().toUtc()));

  RouteSeedJob copyWith({
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
    String? status,
    String? difficultyLevel,
    String? hardRegionStatus,
    int? priority,
    int? maxAttempts,
    int? attemptCount,
    int? failureCount,
    int? seedBudgetUnits,
    int? seedCooldownMinutes,
    String? jobKind,
    int? maxMapboxCalls,
    int? mapboxCallsUsed,
    int? verifiedInsertedCount,
    int? candidateInsertedCount,
    int? dailyAttemptBudget,
    int? monthlyAttemptBudget,
    int? dailyAttemptCount,
    int? monthlyAttemptCount,
    DateTime? budgetWindowDate,
    DateTime? budgetWindowMonth,
    String? lastError,
    String? lastFailureReason,
    DateTime? cooldownUntil,
    DateTime? nextRetryAt,
    DateTime? lastRequestedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    String? completedReason,
    String? triggeredByTier,
  }) {
    return RouteSeedJob(
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
      status: status ?? this.status,
      difficultyLevel: difficultyLevel ?? this.difficultyLevel,
      hardRegionStatus: hardRegionStatus ?? this.hardRegionStatus,
      priority: priority ?? this.priority,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      attemptCount: attemptCount ?? this.attemptCount,
      failureCount: failureCount ?? this.failureCount,
      seedBudgetUnits: seedBudgetUnits ?? this.seedBudgetUnits,
      seedCooldownMinutes: seedCooldownMinutes ?? this.seedCooldownMinutes,
      jobKind: jobKind ?? this.jobKind,
      maxMapboxCalls: maxMapboxCalls ?? this.maxMapboxCalls,
      mapboxCallsUsed: mapboxCallsUsed ?? this.mapboxCallsUsed,
      verifiedInsertedCount:
          verifiedInsertedCount ?? this.verifiedInsertedCount,
      candidateInsertedCount:
          candidateInsertedCount ?? this.candidateInsertedCount,
      dailyAttemptBudget: dailyAttemptBudget ?? this.dailyAttemptBudget,
      monthlyAttemptBudget: monthlyAttemptBudget ?? this.monthlyAttemptBudget,
      dailyAttemptCount: dailyAttemptCount ?? this.dailyAttemptCount,
      monthlyAttemptCount: monthlyAttemptCount ?? this.monthlyAttemptCount,
      budgetWindowDate: budgetWindowDate ?? this.budgetWindowDate,
      budgetWindowMonth: budgetWindowMonth ?? this.budgetWindowMonth,
      lastError: lastError ?? this.lastError,
      lastFailureReason: lastFailureReason ?? this.lastFailureReason,
      cooldownUntil: cooldownUntil ?? this.cooldownUntil,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      lastRequestedAt: lastRequestedAt ?? this.lastRequestedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      completedReason: completedReason ?? this.completedReason,
      triggeredByTier: triggeredByTier ?? this.triggeredByTier,
    );
  }

  factory RouteSeedJob.fromJson(Map<String, dynamic> json) {
    return RouteSeedJob(
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
      status: (json['status'] as String?) ?? 'queued',
      difficultyLevel: (json['difficulty_level'] as String?) ?? 'normal',
      hardRegionStatus: (json['hard_region_status'] as String?) ?? 'normal',
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      maxAttempts: (json['max_attempts'] as num?)?.toInt() ?? 3,
      attemptCount: (json['attempt_count'] as num?)?.toInt() ?? 0,
      failureCount: (json['failure_count'] as num?)?.toInt() ?? 0,
      seedBudgetUnits: (json['seed_budget_units'] as num?)?.toInt() ?? 1,
      seedCooldownMinutes:
          (json['seed_cooldown_minutes'] as num?)?.toInt() ?? 20,
      jobKind: (json['job_kind'] as String?) ?? 'seed_healing',
      maxMapboxCalls: (json['max_mapbox_calls'] as num?)?.toInt() ?? 8,
      mapboxCallsUsed: (json['mapbox_calls_used'] as num?)?.toInt() ?? 0,
      verifiedInsertedCount:
          (json['verified_inserted_count'] as num?)?.toInt() ?? 0,
      candidateInsertedCount:
          (json['candidate_inserted_count'] as num?)?.toInt() ?? 0,
      dailyAttemptBudget: (json['daily_attempt_budget'] as num?)?.toInt() ?? 12,
      monthlyAttemptBudget:
          (json['monthly_attempt_budget'] as num?)?.toInt() ?? 120,
      dailyAttemptCount: (json['daily_attempt_count'] as num?)?.toInt() ?? 0,
      monthlyAttemptCount:
          (json['monthly_attempt_count'] as num?)?.toInt() ?? 0,
      budgetWindowDate: _readSeedJobDateTime(json['budget_window_date']),
      budgetWindowMonth: _readSeedJobDateTime(json['budget_window_month']),
      lastError: json['last_error'] as String?,
      lastFailureReason: json['last_failure_reason'] as String?,
      cooldownUntil: _readSeedJobDateTime(json['cooldown_until']),
      nextRetryAt: _readSeedJobDateTime(json['next_retry_at']),
      lastRequestedAt: _readSeedJobDateTime(json['last_requested_at']),
      startedAt: _readSeedJobDateTime(json['started_at']),
      completedAt: _readSeedJobDateTime(json['completed_at']),
      completedReason: json['completed_reason'] as String?,
      triggeredByTier: json['triggered_by_tier'] as String?,
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
      'status': status,
      'difficulty_level': difficultyLevel,
      'hard_region_status': hardRegionStatus,
      'priority': priority,
      'max_attempts': maxAttempts,
      'attempt_count': attemptCount,
      'failure_count': failureCount,
      'seed_budget_units': seedBudgetUnits,
      'seed_cooldown_minutes': seedCooldownMinutes,
      'job_kind': jobKind,
      'max_mapbox_calls': maxMapboxCalls,
      'mapbox_calls_used': mapboxCallsUsed,
      'verified_inserted_count': verifiedInsertedCount,
      'candidate_inserted_count': candidateInsertedCount,
      'daily_attempt_budget': dailyAttemptBudget,
      'monthly_attempt_budget': monthlyAttemptBudget,
      'daily_attempt_count': dailyAttemptCount,
      'monthly_attempt_count': monthlyAttemptCount,
      'budget_window_date': _dateOnlyString(budgetWindowDate),
      'budget_window_month': _dateOnlyString(budgetWindowMonth),
      'last_error': lastError,
      'last_failure_reason': lastFailureReason,
      'cooldown_until': cooldownUntil?.toIso8601String(),
      'next_retry_at': nextRetryAt?.toIso8601String(),
      'last_requested_at': lastRequestedAt?.toIso8601String(),
      'started_at': startedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'completed_reason': completedReason,
      'triggered_by_tier': triggeredByTier,
    };
  }
}

DateTime? _readSeedJobDateTime(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw)?.toUtc();
  }
  return null;
}

String? _dateOnlyString(DateTime? value) {
  if (value == null) return null;
  return value.toUtc().toIso8601String().split('T').first;
}
