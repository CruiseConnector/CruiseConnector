import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:cruise_connect/data/services/route_pool_service.dart';
import 'package:cruise_connect/data/services/route_quality_validator.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

class RouteCompletionCandidateService {
  RouteCompletionCandidateService._();

  static final RoutePoolService _routePoolService = RoutePoolService();

  static Future<RoutePoolCandidateSaveResult?> submitCandidate({
    required RouteResult result,
    required String style,
    required bool isRoundTrip,
    required bool avoidHighways,
    required bool savedByUser,
    required bool discardedByUser,
    required bool completedAtEnd,
    int? rating,
    List<String> ratingTags = const [],
    double? completionPercent,
    String? source,
  }) async {
    final coordinates = result.coordinates;
    if (coordinates.length < 2) return null;

    final routeType = isRoundTrip ? 'ROUND_TRIP' : 'POINT_TO_POINT';
    final distanceKm =
        result.distanceKm ??
        (result.distanceMeters != null ? result.distanceMeters! / 1000 : null);
    final bucket = _distanceBucketForCandidate(distanceKm);
    if (bucket == null) return null;

    final geometrySafety = _validateGeometrySafety(
      result: result,
      distanceBucket: bucket,
      isRoundTrip: isRoundTrip,
    );
    if (!geometrySafety.safe) {
      debugPrint('[RouteCompletionCandidate] skipped=${geometrySafety.reason}');
      return null;
    }

    final qualityTier = _qualityTierFor(result);
    if (qualityTier == 'rejected') return null;

    final first = coordinates.first;
    if (first.length < 2) return null;

    final feedbackTags = ratingTags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final candidateSource =
        source ??
        ((rating != null || feedbackTags.isNotEmpty || discardedByUser)
            ? 'user_route_feedback'
            : 'route_completion_candidate');
    final fingerprint =
        _stringMeta(result.edgeMeta, 'route_fingerprint') ??
        RouteQualityValidator.buildRouteFingerprint(
          _sampleCoordinates(coordinates),
          distanceKm: distanceKm,
          precision: 4,
        );
    final effectiveCompletionPercent =
        completionPercent ??
        (completedAtEnd
            ? 100.0
            : _numMeta(result.edgeMeta, 'completion_percent'));
    final hasHighway =
        _boolMeta(result.edgeMeta, 'has_highway') ??
        _boolMeta(result.edgeMeta, 'actual_has_highway') ??
        _boolMeta(result.edgeMeta, 'motorway_present') ??
        false;
    final motorwayViolation =
        _boolMeta(result.edgeMeta, 'motorwayViolation') ??
        _boolMeta(result.edgeMeta, 'motorway_violation') ??
        (avoidHighways && hasHighway);
    if (motorwayViolation) return null;

    final routePayload = <String, dynamic>{
      ...result.edgeMeta,
      'source': candidateSource,
      'candidate_source': candidateSource,
      'route_source': candidateSource,
      'route_fingerprint': fingerprint,
      'quality_tier': qualityTier,
      'quality_reason':
          _stringMeta(result.edgeMeta, 'quality_reason') ??
          'user_route_completion_candidate',
      'completion_candidate': true,
      'completion_candidate_saved': savedByUser,
      'completion_candidate_discarded': discardedByUser,
      'completion_candidate_completed': completedAtEnd,
      'completion_percent': effectiveCompletionPercent?.clamp(0, 100),
      'rating': rating,
      'rating_tags': feedbackTags,
      'submitted_at': DateTime.now().toUtc().toIso8601String(),
      'coordinate_count': coordinates.length,
      'max_display_segment_m': geometrySafety.maxSegmentMeters,
      'distance_km': distanceKm,
      'distance_bucket': bucket,
      'route_type': routeType,
      'avoid_highways_requested': avoidHighways,
      'motorway_violation': false,
      'is_verified_pool': false,
    };

    try {
      return await _routePoolService.recordCandidateRoute(
        userLat: first[1],
        userLng: first[0],
        distanceBucket: bucket,
        style: style,
        avoidHighways: avoidHighways,
        routeType: routeType,
        candidateSource: candidateSource,
        routeFingerprint: fingerprint,
        geometry: result.geometry.isNotEmpty
            ? result.geometry
            : <String, dynamic>{
                'type': 'LineString',
                'coordinates': coordinates,
              },
        routePayload: routePayload,
        qualityScore: _qualityScoreFor(result, qualityTier),
        shapeScore: _numMeta(result.edgeMeta, 'shape_score') ?? 70.0,
        distanceKm: distanceKm,
        hasHighway: hasHighway,
        preferredCountryCode: _stringMeta(result.edgeMeta, 'country_code'),
        preferredAdmin1Name: _stringMeta(result.edgeMeta, 'admin1_name'),
        preferredAdmin2Name: _stringMeta(result.edgeMeta, 'admin2_name'),
        preferredCityCluster: _stringMeta(result.edgeMeta, 'city_cluster'),
        averageRating: rating?.toDouble(),
        ratingCount: rating == null ? 0 : 1,
        completionRate: effectiveCompletionPercent == null
            ? null
            : (effectiveCompletionPercent / 100).clamp(0, 1).toDouble(),
        timesSelected: savedByUser || completedAtEnd ? 1 : 0,
        lastSelectedAt: DateTime.now().toUtc(),
      );
    } catch (error) {
      debugPrint('[RouteCompletionCandidate] submit failed: $error');
      return null;
    }
  }

  static _GeometrySafety _validateGeometrySafety({
    required RouteResult result,
    required int distanceBucket,
    required bool isRoundTrip,
  }) {
    final coordinates = result.coordinates;
    final minCoordinates = isRoundTrip
        ? (distanceBucket >= 100
              ? 32
              : distanceBucket >= 75
              ? 26
              : 20)
        : 14;
    if (coordinates.length < minCoordinates) {
      return const _GeometrySafety(false, 'coordinate_count_low', 0);
    }
    final source =
        (_stringMeta(result.edgeMeta, 'final_geometry_source') ??
                _stringMeta(result.edgeMeta, 'geometry_source') ??
                '')
            .toLowerCase();
    const unsafeSourceMarkers = [
      'candidate_plan',
      'pre_hydration',
      'sparse',
      'straight_line',
      'fallback_line',
      'synthetic',
    ];
    if (unsafeSourceMarkers.any(source.contains)) {
      return const _GeometrySafety(false, 'unsafe_geometry_source', 0);
    }

    final maxSegmentMeters =
        _numMeta(result.edgeMeta, 'max_display_segment_m') ??
        _maxSegmentMeters(coordinates);
    final maxAllowedSegment = distanceBucket >= 100
        ? 2200.0
        : distanceBucket >= 75
        ? 1800.0
        : 1500.0;
    if (maxSegmentMeters > maxAllowedSegment) {
      return _GeometrySafety(false, 'segment_too_long', maxSegmentMeters);
    }
    return _GeometrySafety(true, null, maxSegmentMeters);
  }

  static int? _distanceBucketForCandidate(double? distanceKm) {
    if (distanceKm == null || !distanceKm.isFinite || distanceKm <= 0) {
      return null;
    }
    if (distanceKm >= 40 && distanceKm < 65) return 50;
    if (distanceKm >= 65 && distanceKm < 92) return 75;
    if (distanceKm >= 92 && distanceKm <= 125) return 100;
    return null;
  }

  static String _qualityTierFor(RouteResult result) {
    final raw = _stringMeta(result.edgeMeta, 'quality_tier')?.toLowerCase();
    if (raw == 'ideal' ||
        raw == 'good' ||
        raw == 'acceptable' ||
        raw == 'rejected') {
      return raw!;
    }
    final score = _numMeta(result.edgeMeta, 'quality_score');
    if (score == null) return 'acceptable';
    if (score >= 92) return 'ideal';
    if (score >= 82) return 'good';
    if (score >= 70) return 'acceptable';
    return 'rejected';
  }

  static double _qualityScoreFor(RouteResult result, String tier) {
    final score = _numMeta(result.edgeMeta, 'quality_score');
    if (score != null) return score.clamp(0, 100).toDouble();
    return switch (tier) {
      'ideal' => 94.0,
      'good' => 84.0,
      'acceptable' => 72.0,
      _ => 40.0,
    };
  }

  static List<List<double>> _sampleCoordinates(List<List<double>> coordinates) {
    if (coordinates.length <= 32) {
      return coordinates.map((point) => [point[0], point[1]]).toList();
    }
    final step = (coordinates.length / 32).ceil();
    final sampled = <List<double>>[];
    for (var i = 0; i < coordinates.length; i += step) {
      sampled.add([coordinates[i][0], coordinates[i][1]]);
    }
    final last = coordinates.last;
    final sampledLast = sampled.last;
    if (sampledLast[0] != last[0] || sampledLast[1] != last[1]) {
      sampled.add([last[0], last[1]]);
    }
    return sampled;
  }

  static double _maxSegmentMeters(List<List<double>> coordinates) {
    var maxSegment = 0.0;
    for (var i = 1; i < coordinates.length; i++) {
      final previous = coordinates[i - 1];
      final current = coordinates[i];
      if (previous.length < 2 || current.length < 2) continue;
      maxSegment = math.max(
        maxSegment,
        _haversineMeters(previous[1], previous[0], current[1], current[0]),
      );
    }
    return maxSegment;
  }

  static double _haversineMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _degToRad(double value) => value * math.pi / 180.0;

  static String? _stringMeta(Map<String, dynamic> meta, String key) {
    final value = meta[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static double? _numMeta(Map<String, dynamic> meta, String key) {
    final value = meta[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static bool? _boolMeta(Map<String, dynamic> meta, String key) {
    final value = meta[key];
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return null;
  }
}

class _GeometrySafety {
  const _GeometrySafety(this.safe, this.reason, this.maxSegmentMeters);

  final bool safe;
  final String? reason;
  final double maxSegmentMeters;
}
