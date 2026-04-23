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
    this.priority = 0,
    this.maxAttempts = 3,
    this.attemptCount = 0,
    this.lastError,
    this.cooldownUntil,
    this.lastRequestedAt,
    this.startedAt,
    this.completedAt,
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
  final int priority;
  final int maxAttempts;
  final int attemptCount;
  final String? lastError;
  final DateTime? cooldownUntil;
  final DateTime? lastRequestedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? triggeredByTier;

  bool get isQueued => status == 'queued';
  bool get isRunning => status == 'running';
  bool get isActive => isQueued || isRunning;
  bool get isCoolingDown =>
      cooldownUntil != null && cooldownUntil!.isAfter(DateTime.now().toUtc());

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
    int? priority,
    int? maxAttempts,
    int? attemptCount,
    String? lastError,
    DateTime? cooldownUntil,
    DateTime? lastRequestedAt,
    DateTime? startedAt,
    DateTime? completedAt,
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
      priority: priority ?? this.priority,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: lastError ?? this.lastError,
      cooldownUntil: cooldownUntil ?? this.cooldownUntil,
      lastRequestedAt: lastRequestedAt ?? this.lastRequestedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
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
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      maxAttempts: (json['max_attempts'] as num?)?.toInt() ?? 3,
      attemptCount: (json['attempt_count'] as num?)?.toInt() ?? 0,
      lastError: json['last_error'] as String?,
      cooldownUntil: _readSeedJobDateTime(json['cooldown_until']),
      lastRequestedAt: _readSeedJobDateTime(json['last_requested_at']),
      startedAt: _readSeedJobDateTime(json['started_at']),
      completedAt: _readSeedJobDateTime(json['completed_at']),
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
      'priority': priority,
      'max_attempts': maxAttempts,
      'attempt_count': attemptCount,
      'last_error': lastError,
      'cooldown_until': cooldownUntil?.toIso8601String(),
      'last_requested_at': lastRequestedAt?.toIso8601String(),
      'started_at': startedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
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
