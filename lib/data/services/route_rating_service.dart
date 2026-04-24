import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/route_quality_validator.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

class RouteRatingService {
  RouteRatingService._();

  static SupabaseClient get _db => Supabase.instance.client;

  static Future<bool> saveRating({
    required RouteResult result,
    required int? rating,
    required List<String> tags,
    required double completionPercent,
    required double? distanceKm,
    required double? durationSeconds,
    required String? qualityTier,
  }) async {
    final userId = _db.auth.currentUser?.id;
    final normalizedRating = rating?.clamp(1, 5).toInt();
    final cleanedTags = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (userId == null || (normalizedRating == null && cleanedTags.isEmpty)) {
      return false;
    }

    final fingerprint =
        result.edgeMeta['route_fingerprint']?.toString().trim().isNotEmpty ==
            true
        ? result.edgeMeta['route_fingerprint'].toString()
        : RouteQualityValidator.buildRouteFingerprint(
            _sampleCoordinates(result.coordinates),
            distanceKm: result.distanceKm ?? distanceKm,
            precision: 4,
          );
    final row = <String, dynamic>{
      'user_id': userId,
      'route_id':
          result.edgeMeta['pool_route_id']?.toString() ??
          result.edgeMeta['pool_match_id']?.toString(),
      'route_fingerprint': fingerprint,
      'route_source':
          result.edgeMeta['route_source']?.toString() ??
          result.edgeMeta['source']?.toString() ??
          'unknown',
      'rating': normalizedRating,
      'tags': cleanedTags,
      'completion_percent': completionPercent.clamp(0, 100),
      'distance_km': distanceKm,
      'duration_seconds': durationSeconds?.round(),
      'quality_tier':
          qualityTier ??
          result.edgeMeta['quality_tier']?.toString() ??
          'acceptable',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await _db
          .from('route_ratings')
          .upsert(row, onConflict: 'user_id,route_fingerprint');
      return true;
    } catch (error) {
      debugPrint(
        '[RouteRating] Bewertung konnte nicht gespeichert werden: $error',
      );
      return false;
    }
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
}
