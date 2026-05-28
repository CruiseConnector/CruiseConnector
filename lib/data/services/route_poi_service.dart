import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Sucht POIs (Tankstellen, Restaurants, Cafés, Werkstätten) entlang
/// einer Route via Overpass-API (kostenlos, kein Key).
///
/// Strategie:
///   1. Route-Polyline in N Sample-Punkte herunterrechnen
///   2. Bounding-Box um Polyline + 2km Buffer berechnen
///   3. Overpass-Query mit `amenity` Filter
///   4. Treffer filtern auf Distanz <bufferMeters von der Route
///
/// Cache: per-Route-Fingerprint, 30min Memory-TTL.
class RoutePoiService {
  RoutePoiService._();
  static final RoutePoiService instance = RoutePoiService._();

  static const _overpassUrl = 'https://overpass-api.de/api/interpreter';
  final Map<String, _PoiCacheEntry> _cache = {};

  /// Fetch POIs entlang einer Route.
  ///
  /// [coordinates] = Liste [lng, lat] Punkte
  /// [types] = amenity-Tags ('fuel', 'restaurant', 'cafe', etc.)
  /// [bufferMeters] = wie nah POI an Route sein muss (default 350m)
  ///
  /// 2026-05-28 (vucko POI-Coverage): Erweitert um alle Wege Tankstellen
  /// zu finden:
  ///   - node["amenity"=fuel] — Standard
  ///   - way["amenity"=fuel]  — Tankstellen mit Hofzufahrt (häufig in DE/AT)
  ///   - node["shop"=fuel]    — Tankstellen primär als Shop getaggt
  /// Plus größerer Buffer (200→350m) und höheres Limit (200→500).
  Future<List<RoutePoi>> fetchPoisAlongRoute({
    required List<List<double>> coordinates,
    Set<PoiType> types = const {PoiType.fuel},
    double bufferMeters = 350,
    int maxResults = 120,
  }) async {
    if (coordinates.length < 2) return [];
    final cacheKey = _cacheKey(coordinates, types);
    final cached = _cache[cacheKey];
    if (cached != null && cached.isFresh) return cached.pois;

    try {
      final sampledRoute = _sampleRoute(coordinates, targetSamples: 100);
      final bbox = _boundingBox(sampledRoute, paddingDegrees: 0.022);
      final amenityFilter = types.map((t) => t.osmTag).join('|');
      final wantsFuel = types.contains(PoiType.fuel);
      final bboxStr =
          '${bbox.south},${bbox.west},${bbox.north},${bbox.east}';
      // Erweiterte Query: nodes UND ways. Bei ways nimmt Overpass mit `center`
      // den Mittelpunkt des Polygons → wir können das wie eine Node behandeln.
      // Zusätzlich shop=fuel für Tankstellen ohne amenity-Tag.
      final shopFuelClause = wantsFuel
          ? '''
  node["shop"="fuel"]($bboxStr);
  way["shop"="fuel"]($bboxStr);'''
          : '';
      final query = '''
[out:json][timeout:22];
(
  node["amenity"~"^($amenityFilter)\$"]($bboxStr);
  way["amenity"~"^($amenityFilter)\$"]($bboxStr);$shopFuelClause
);
out center 500;
''';
      final response = await http
          .post(
            Uri.parse(_overpassUrl),
            headers: const {
              'User-Agent': 'CruiseConnect/1.0 (route-poi)',
            },
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 22));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List? ?? [];
      final all = <RoutePoi>[];
      final seenIds = <int>{};
      for (final el in elements) {
        try {
          // Bei nodes: lat/lon direkt. Bei ways: center.lat / center.lon.
          double? lat = (el['lat'] as num?)?.toDouble();
          double? lng = (el['lon'] as num?)?.toDouble();
          if (lat == null || lng == null) {
            final center = el['center'] as Map?;
            lat = (center?['lat'] as num?)?.toDouble();
            lng = (center?['lon'] as num?)?.toDouble();
          }
          if (lat == null || lng == null) continue;
          final id = (el['id'] as num).toInt();
          // Ways und nodes haben dieselbe ID-Range, plus shop=fuel kann doppelt
          // mit amenity=fuel kommen. Dedup über (typ+id+rundete-coord).
          final dedupKey =
              id * 10 + (el['type'] == 'way' ? 1 : 0);
          if (seenIds.contains(dedupKey)) continue;
          final tags = (el['tags'] as Map?)?.cast<String, dynamic>() ?? {};
          final amenity = (tags['amenity'] as String?) ??
              (tags['shop'] == 'fuel' ? 'fuel' : '');
          final type = PoiType.values.firstWhere(
            (t) => t.osmTag == amenity,
            orElse: () => PoiType.fuel,
          );
          // Distanz zur Route prüfen
          final dist = _minDistanceToRoute(lat, lng, sampledRoute);
          if (dist > bufferMeters) continue;
          seenIds.add(dedupKey);
          all.add(RoutePoi(
            id: dedupKey,
            type: type,
            latitude: lat,
            longitude: lng,
            name: tags['name'] as String?,
            brand: tags['brand'] as String?,
            openingHours: tags['opening_hours'] as String?,
            distanceFromRouteMeters: dist,
          ));
        } catch (_) {
          continue;
        }
      }
      // Zweiter Dedup-Pass: POIs an quasi-identischer Position (z.B. amenity
      // + shop für dieselbe Tankstelle) zusammenfassen — wir behalten den
      // ersten und werfen Duplikate <30m raus.
      final deduped = <RoutePoi>[];
      for (final poi in all) {
        final isDup = deduped.any((other) =>
            other.type == poi.type &&
            _haversine(poi.latitude, poi.longitude, other.latitude,
                    other.longitude) <
                30);
        if (!isDup) deduped.add(poi);
      }
      deduped.sort((a, b) => a.distanceFromRouteMeters
          .compareTo(b.distanceFromRouteMeters));
      final limited = deduped.take(maxResults).toList();
      _cache[cacheKey] = _PoiCacheEntry(limited);
      return limited;
    } catch (e) {
      debugPrint('[RoutePoiService] fetch failed: $e');
      return [];
    }
  }

  /// Sample Route auf N Punkte gleichmäßig verteilt.
  List<List<double>> _sampleRoute(List<List<double>> coords,
      {required int targetSamples}) {
    if (coords.length <= targetSamples) return coords;
    final step = coords.length / targetSamples;
    final sampled = <List<double>>[];
    for (var i = 0; i < targetSamples; i++) {
      sampled.add(coords[(i * step).floor()]);
    }
    sampled.add(coords.last);
    return sampled;
  }

  _Bbox _boundingBox(List<List<double>> coords,
      {required double paddingDegrees}) {
    var minLat = coords.first[1];
    var maxLat = coords.first[1];
    var minLng = coords.first[0];
    var maxLng = coords.first[0];
    for (final c in coords) {
      if (c[1] < minLat) minLat = c[1];
      if (c[1] > maxLat) maxLat = c[1];
      if (c[0] < minLng) minLng = c[0];
      if (c[0] > maxLng) maxLng = c[0];
    }
    return _Bbox(
      south: minLat - paddingDegrees,
      west: minLng - paddingDegrees,
      north: maxLat + paddingDegrees,
      east: maxLng + paddingDegrees,
    );
  }

  double _minDistanceToRoute(double lat, double lng,
      List<List<double>> routeCoords) {
    double minDist = double.infinity;
    for (final c in routeCoords) {
      final d = _haversine(lat, lng, c[1], c[0]);
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  String _cacheKey(List<List<double>> coords, Set<PoiType> types) {
    final first = coords.first;
    final last = coords.last;
    final typesStr = (types.map((t) => t.osmTag).toList()..sort()).join(',');
    return '${first[0].toStringAsFixed(3)}|${first[1].toStringAsFixed(3)}|'
        '${last[0].toStringAsFixed(3)}|${last[1].toStringAsFixed(3)}|'
        '${coords.length}|$typesStr';
  }
}

class _PoiCacheEntry {
  _PoiCacheEntry(this.pois) : at = DateTime.now();
  final List<RoutePoi> pois;
  final DateTime at;
  bool get isFresh => DateTime.now().difference(at) < const Duration(minutes: 30);
}

class _Bbox {
  _Bbox({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });
  final double south, west, north, east;
}

enum PoiType {
  fuel('fuel', '⛽', 'Tankstelle'),
  restaurant('restaurant', '🍴', 'Restaurant'),
  cafe('cafe', '☕', 'Café'),
  fastFood('fast_food', '🍔', 'Imbiss'),
  pub('pub', '🍺', 'Pub'),
  motorcycleRepair('motorcycle_repair', '🔧', 'Werkstatt'),
  parking('parking', '🅿️', 'Parkplatz'),
  toilets('toilets', '🚻', 'WC');

  const PoiType(this.osmTag, this.emoji, this.label);
  final String osmTag;
  final String emoji;
  final String label;
}

class RoutePoi {
  final int id;
  final PoiType type;
  final double latitude;
  final double longitude;
  final String? name;
  final String? brand;
  final String? openingHours;
  final double distanceFromRouteMeters;

  RoutePoi({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.distanceFromRouteMeters,
    this.name,
    this.brand,
    this.openingHours,
  });

  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    if (brand != null && brand!.isNotEmpty) return brand!;
    return type.label;
  }
}
