import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/geo_distance.dart';
import 'package:cruise_connect/domain/models/route_pool_entry.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';

class HomeRouteRecommendation {
  const HomeRouteRecommendation({
    required this.poolEntry,
    required this.route,
    required this.displayName,
    required this.qualityScore,
    required this.recommendationScore,
    required this.completionCount,
    required this.averageRating,
    required this.ratingCount,
    required this.completionRate,
  });

  final RoutePoolEntry poolEntry;
  final SavedRoute route;
  final String displayName;
  final double qualityScore;
  final double recommendationScore;
  final int completionCount;
  final double? averageRating;
  final int ratingCount;
  final double? completionRate;

  bool get hasRating => averageRating != null && ratingCount > 0;
  bool get hasCompletions => completionCount > 0;

  /// 2026-05-28 (vucko Task #72): JSON-Serialisierung für persistenten
  /// Cache. Wird in SharedPreferences gespeichert damit die Home-Card beim
  /// 2.+ App-Start sofort gerendert wird, kein leerer "Starte deine erste
  /// Route"-Empty-State mehr.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'pool_entry': poolEntry.toJson(),
    'route': route.toJson(),
    'display_name': displayName,
    'quality_score': qualityScore,
    'recommendation_score': recommendationScore,
    'completion_count': completionCount,
    'average_rating': averageRating,
    'rating_count': ratingCount,
    'completion_rate': completionRate,
  };

  factory HomeRouteRecommendation.fromJson(Map<String, dynamic> json) {
    return HomeRouteRecommendation(
      poolEntry: RoutePoolEntry.fromJson(
        Map<String, dynamic>.from(json['pool_entry'] as Map),
      ),
      route: SavedRoute.fromJson(
        Map<String, dynamic>.from(json['route'] as Map),
      ),
      displayName: json['display_name'] as String,
      qualityScore: (json['quality_score'] as num).toDouble(),
      recommendationScore: (json['recommendation_score'] as num).toDouble(),
      completionCount: (json['completion_count'] as num?)?.toInt() ?? 0,
      averageRating: (json['average_rating'] as num?)?.toDouble(),
      ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
      completionRate: (json['completion_rate'] as num?)?.toDouble(),
    );
  }
}

class HomeRouteRecommendationService {
  HomeRouteRecommendationService._();

  static SupabaseClient get _db => Supabase.instance.client;

  static HomeRouteRecommendation? _cachedRecommendation;
  static DateTime? _cachedAt;
  static String? _cacheKey;
  // 2026-05-24 (vucko Region-aware): Cache-Anker — wenn User sich >25km
  // vom Anker wegbewegt hat, Cache als ungültig markieren auch wenn der
  // Bucket-Key zufällig matched (Bucket = 0.1° = ~11km, kann zu Drift führen).
  static double? _cachedAnchorLat;
  static double? _cachedAnchorLng;

  // 2026-05-24 (vucko): Region-Radius — eine Recommendation ist nur dann
  // relevant wenn der Routen-Startpunkt innerhalb dieses Radius vom User ist.
  // Damit zeigt die Card nie "Bregenz-Loop" wenn der User in Wien ist.
  static const double _regionRadiusKm = 100;
  // Wenn User sich um mehr als das vom letzten Cache-Anker wegbewegt hat,
  // Cache wird invalidiert sofort (statt erst nach 60min).
  static const double _cacheInvalidationDistanceKm = 25;

  static Future<HomeRouteRecommendation?> getTodayRoute({
    double? userLat,
    double? userLng,
  }) async {
    final key = _cacheKeyFor(userLat: userLat, userLng: userLng);
    final cached = _cachedRecommendation;
    final cachedAt = _cachedAt;
    // 2026-05-24 (vucko): Distanz-basierter Cache-Check. Bucket-Key in
    // _cacheKeyFor kann driften (User wandert grob in selber Region). Zusätzlich
    // exakte Distanz prüfen — wenn >25km gewandert → Cache ungültig.
    if (cached != null &&
        cachedAt != null &&
        _cacheKey == key &&
        !_movedTooFarFromCacheAnchor(userLat, userLng) &&
        DateTime.now().difference(cachedAt).inMinutes < 60) {
      return cached;
    }

    try {
      final rows = await _db
          .from('route_pool')
          .select(_routePoolSelect)
          .eq('verified', true)
          .eq('is_active', true)
          .isFilter('deprecated_at', null)
          .gte('quality_score', 70)
          .order('weekly_rotation_score', ascending: false)
          .order('quality_score', ascending: false)
          .limit(120);

      var entries = (rows as List)
          .whereType<Map>()
          .map((row) => RoutePoolEntry.fromJson(Map<String, dynamic>.from(row)))
          .where(_isSafeHomePoolRoute)
          .toList(growable: false);

      // 2026-05-24 (vucko): Region-Filter — nur Routen mit Start innerhalb
      // _regionRadiusKm vom User. Verhindert dass User in Wien eine
      // Bregenz-Route empfohlen bekommt.
      if (userLat != null && userLng != null) {
        entries = entries
            .where((e) {
              final distKm = _haversineKm(
                userLat,
                userLng,
                e.startLat,
                e.startLng,
              );
              return distKm <= _regionRadiusKm;
            })
            .toList(growable: false);
      }

      if (entries.isEmpty) {
        _cacheRecommendation(null, key, userLat, userLng);
        return null;
      }

      final ranked =
          entries
              .map(
                (entry) => _ScoredEntry(
                  entry: entry,
                  score: _recommendationScore(
                    entry,
                    userLat: userLat,
                    userLng: userLng,
                  ),
                ),
              )
              .toList()
            ..sort((a, b) => b.score.compareTo(a.score));

      final topWindow = ranked.take(math.min(8, ranked.length)).toList();
      final seed = _stableDailySeed(topWindow.map((item) => item.entry.id));
      final selected = topWindow[math.Random(seed).nextInt(topWindow.length)];
      final recommendation = _toRecommendation(selected.entry, selected.score);
      _cacheRecommendation(recommendation, key, userLat, userLng);
      return recommendation;
    } catch (error) {
      debugPrint('[HomeRouteRecommendation] route_pool read failed: $error');
      return null;
    }
  }

  /// True wenn User-Position deutlich vom Cache-Anker abweicht.
  /// Trigger für sofortige Cache-Invalidation auch wenn TTL noch nicht
  /// abgelaufen ist (z.B. wenn User per Bahn von Bregenz nach Wien fährt).
  static bool _movedTooFarFromCacheAnchor(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    final aLat = _cachedAnchorLat;
    final aLng = _cachedAnchorLng;
    if (aLat == null || aLng == null) return false;
    return _haversineKm(lat, lng, aLat, aLng) > _cacheInvalidationDistanceKm;
  }

  static void invalidateCache() {
    _cachedRecommendation = null;
    _cachedAt = null;
    _cacheKey = null;
    _cachedAnchorLat = null;
    _cachedAnchorLng = null;
  }

  static const String _routePoolSelect =
      'id,title,country_code,admin1_name,admin2_name,city_cluster,'
      'start_lat,start_lng,end_lat,end_lng,distance_km,distance_bucket,'
      'route_type,style_tags,avoids_highway,has_highway,quality_score,'
      'verified,is_active,geometry,shape_score,user_rating,average_rating,'
      'rating_count,completion_rate,weekly_rotation_score,deprecated_at,'
      'usage_count,source,route_payload';

  static void _cacheRecommendation(
    HomeRouteRecommendation? recommendation,
    String key,
    double? anchorLat,
    double? anchorLng,
  ) {
    _cachedRecommendation = recommendation;
    _cachedAt = DateTime.now();
    _cacheKey = key;
    _cachedAnchorLat = anchorLat;
    _cachedAnchorLng = anchorLng;
  }

  static String _cacheKeyFor({double? userLat, double? userLng}) {
    final now = DateTime.now();
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final latBucket = userLat?.toStringAsFixed(1) ?? 'global';
    final lngBucket = userLng?.toStringAsFixed(1) ?? 'global';
    return '${weekStart.toIso8601String()}|${now.weekday}|$latBucket|$lngBucket';
  }

  static int _stableDailySeed(Iterable<String> routeIds) {
    final now = DateTime.now();
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    var hash = weekStart.millisecondsSinceEpoch ^ (now.weekday * 7919);
    for (final id in routeIds) {
      for (final unit in id.codeUnits.take(12)) {
        hash = 0x1fffffff & (hash * 31 + unit);
      }
    }
    return hash.abs();
  }

  static bool _isSafeHomePoolRoute(RoutePoolEntry entry) {
    if (!entry.verified || !entry.isActive || entry.deprecatedAt != null) {
      return false;
    }
    if (entry.qualityScore < 70 || entry.distanceKm < 5) return false;

    final coords = _coordinatesFromGeometry(entry.geometry);
    if (coords.length < _minCoordinateCount(entry.distanceBucket)) {
      return false;
    }

    final source = _readString(entry.routePayload, const [
      'final_geometry_source',
      'geometry_source',
      'source',
    ]).toLowerCase();
    const unsafeSources = [
      'candidate_plan',
      'pre_hydration',
      'sparse',
      'straight_line',
      'fallback_line',
      'synthetic',
    ];
    if (unsafeSources.any(source.contains)) return false;

    final maxSegment = _maxSegmentMeters(coords);
    if (maxSegment > _maxSegmentThreshold(entry.distanceBucket)) return false;

    if (entry.routePayload['motorway_violation'] == true) return false;
    return true;
  }

  static HomeRouteRecommendation _toRecommendation(
    RoutePoolEntry entry,
    double score,
  ) {
    final name = _displayNameFor(entry);
    final style = _styleLabelFor(entry);
    final qualityTier = _readString(entry.routePayload, const [
      'quality_tier',
      'qualityTier',
    ]);
    final averageRating = entry.averageRating ?? entry.userRating;
    final completionRate = entry.completionRate;
    final completionCount = entry.usageCount;

    final routeMeta = <String, dynamic>{
      ...entry.routePayload,
      'route_source': 'route_pool',
      'source': entry.source,
      'pool_route_id': entry.id,
      'quality_score': entry.qualityScore,
      'average_rating': averageRating,
      'rating_count': entry.ratingCount,
      'completion_rate': completionRate,
      'completion_count': completionCount,
      'weekly_rotation_score': entry.weeklyRotationScore,
      'home_recommendation_score': score,
    };

    final route = SavedRoute(
      id: entry.id,
      createdAt: DateTime.now(),
      style: style,
      distanceKm: entry.distanceKm,
      geometry: entry.geometry,
      name: name,
      durationSeconds: entry.durationSeconds,
      routeType: entry.routeType,
      rating: averageRating?.round(),
      distanceTargetKm: entry.distanceBucket.toDouble(),
      sourceRouteId: entry.id,
      routeSource: 'route_pool',
      routeFingerprint:
          _readString(entry.routePayload, const [
            'route_fingerprint',
            'fingerprint',
          ]).trim().isNotEmpty
          ? _readString(entry.routePayload, const [
              'route_fingerprint',
              'fingerprint',
            ]).trim()
          : entry.id,
      qualityTier: qualityTier.trim().isNotEmpty ? qualityTier : null,
      routeMeta: routeMeta,
      averageRating: averageRating,
      ratingCount: entry.ratingCount,
      completionRate: completionRate,
      completedAtEnd: false,
    );

    return HomeRouteRecommendation(
      poolEntry: entry,
      route: route,
      displayName: name,
      qualityScore: entry.qualityScore,
      recommendationScore: score,
      completionCount: completionCount,
      averageRating: averageRating,
      ratingCount: entry.ratingCount,
      completionRate: completionRate,
    );
  }

  static double _recommendationScore(
    RoutePoolEntry entry, {
    double? userLat,
    double? userLng,
  }) {
    final averageRating = entry.averageRating ?? entry.userRating;
    final ratingScore = averageRating != null && entry.ratingCount > 0
        ? averageRating * 22 + math.min(entry.ratingCount, 20) * 1.4
        : 0.0;
    final rawCompletionRate = entry.completionRate ?? 0;
    final normalizedCompletionRate = rawCompletionRate > 1
        ? rawCompletionRate / 100
        : rawCompletionRate;
    final completionScore = normalizedCompletionRate.clamp(0.0, 1.0) * 14;
    final usageScore = math.min(entry.usageCount, 50) * 0.35;
    final curationScore = entry.weeklyRotationScore + entry.qualityScore * 0.65;
    final proximityScore = userLat != null && userLng != null
        ? math.max(
            0.0,
            18 -
                _haversineKm(userLat, userLng, entry.startLat, entry.startLng) /
                    8,
          )
        : 0.0;
    final socialProofBoost = entry.ratingCount > 0 || entry.usageCount > 0
        ? 18.0
        : 0.0;
    return curationScore +
        ratingScore +
        completionScore +
        usageScore +
        proximityScore +
        socialProofBoost;
  }

  static String _displayNameFor(RoutePoolEntry entry) {
    final rawTitle = entry.title?.trim();
    if (rawTitle != null &&
        rawTitle.isNotEmpty &&
        !_looksTechnicalTitle(rawTitle)) {
      return rawTitle;
    }

    final city = entry.cityCluster.trim();
    final style = _styleLabelFor(entry).toLowerCase();
    if (city.toLowerCase().contains('bregenz')) {
      if (style.contains('kurven')) {
        return _pickName(entry, const [
          'Bodensee Kurvenrunde',
          'Pfänder Kurvenloop',
          'Rheindelta Bogen',
        ]);
      }
      if (style.contains('entdecker')) {
        return _pickName(entry, const [
          'Bodensee Explorer',
          'Hafenrunde Discovery',
          'Rheindelta Explorer',
        ]);
      }
      if (style.contains('abend')) {
        return _pickName(entry, const [
          'Bodensee Abendrunde',
          'Pfänder Sunset Loop',
          'Rheindelta Feierabend',
        ]);
      }
      return _pickName(entry, const [
        'Bodensee Cruise',
        'Lake Flow',
        'Pfänder Sprint',
      ]);
    }
    if (city.toLowerCase().contains('bludenz')) {
      if (style.contains('kurven')) {
        return _pickName(entry, const [
          'Alpine Kurvenrunde',
          'Walgau Serpentinen',
          'Brandnertal Loop',
        ]);
      }
      if (style.contains('sport')) {
        return _pickName(entry, const [
          'Alpine Rush',
          'Walgau Flow',
          'Montafon Sprint',
        ]);
      }
      return _pickName(entry, const [
        'Walgau Loop',
        'Alpine Discovery',
        'Talrunde Bludenz',
      ]);
    }
    if (city.toLowerCase().contains('feldkirch')) {
      if (style.contains('kurven')) {
        return _pickName(entry, const [
          'Walgau Kurvenrunde',
          'Schattenburg Loop',
          'Rheintal Kurvenfluss',
        ]);
      }
      return _pickName(entry, const [
        'Rheintal Flow',
        'Walgau Cruise',
        'Feldkirch Runde',
      ]);
    }
    if (city.toLowerCase().contains('dornbirn')) {
      if (style.contains('kurven')) {
        return _pickName(entry, const [
          'Rheintal Kurvenloop',
          'Bödele Bogen',
          'Dornbirn Kurvenfluss',
        ]);
      }
      if (style.contains('abend')) {
        return _pickName(entry, const [
          'Rheintal Abendrunde',
          'Dornbirn Dämmerloop',
          'Feierabend Flow',
        ]);
      }
      return _pickName(entry, const [
        'Rheintal Loop',
        'Dornbirn Flow',
        'Achauen Cruise',
      ]);
    }
    if (city.isNotEmpty) {
      return _pickName(entry, ['$city Loop', '$city Flow', '$city Cruise']);
    }
    return _pickName(entry, const [
      'Alpine Tour',
      'Cruise Loop',
      'Scenic Flow',
    ]);
  }

  static String _pickName(RoutePoolEntry entry, List<String> names) {
    if (names.isEmpty) return 'Cruise Loop';
    var hash = entry.id.hashCode ^ entry.distanceBucket.hashCode;
    for (final tag in entry.styleTags) {
      hash ^= tag.hashCode;
    }
    return names[hash.abs() % names.length];
  }

  static bool _looksTechnicalTitle(String title) {
    final lower = title.toLowerCase();
    return lower.contains('seed') ||
        lower.contains('bootstrap') ||
        lower.contains('mapbox') ||
        lower.contains('candidate') ||
        lower.contains('route ');
  }

  static String _styleLabelFor(RoutePoolEntry entry) {
    if (entry.styleTags.isEmpty) return 'Rundkurs';
    final first = entry.styleTags.first.trim();
    if (first.isEmpty) return 'Rundkurs';
    if (first == 'sport_mode') return 'Sport Mode';
    if (first == 'curvy') return 'Kurvenjagd';
    if (first == 'evening') return 'Abendrunde';
    if (first == 'explorer') return 'Entdecker';
    return first;
  }

  static String _readString(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value != null) return value.toString();
    }
    return '';
  }

  static List<List<double>> _coordinatesFromGeometry(
    Map<String, dynamic> geometry,
  ) {
    final raw = geometry['coordinates'];
    if (raw is! List) return const [];
    final coords = <List<double>>[];
    for (final point in raw) {
      if (point is List && point.length >= 2) {
        final lng = point[0];
        final lat = point[1];
        if (lng is num && lat is num) {
          coords.add([lng.toDouble(), lat.toDouble()]);
        }
      }
    }
    return coords;
  }

  static int _minCoordinateCount(int bucket) {
    if (bucket >= 100) return 32;
    if (bucket >= 75) return 26;
    return 20;
  }

  static double _maxSegmentThreshold(int bucket) {
    if (bucket >= 100) return 2400;
    if (bucket >= 75) return 2100;
    return 1800;
  }

  static double _maxSegmentMeters(List<List<double>> coords) {
    return GeoDistance.maxSegmentMetersLngLat(coords);
  }

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return GeoDistance.haversineKm(
      fromLat: lat1,
      fromLng: lon1,
      toLat: lat2,
      toLng: lon2,
    );
  }
}

class _ScoredEntry {
  const _ScoredEntry({required this.entry, required this.score});

  final RoutePoolEntry entry;
  final double score;
}
