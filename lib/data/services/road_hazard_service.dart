import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Sucht Baustellen / gesperrte Straßen entlang einer Route.
///
/// Quelle: OSM via Overpass-API mit Tag-Filter:
///   - highway=construction
///   - construction=*
///   - access=no auf konstruierten Wegen
///
/// Limitierung (ehrlich):
///   - OSM-Daten werden community-getrieben gepflegt → nicht alle echten
///     temporären Baustellen sind getaggt
///   - Für ECHTE Live-Verkehr (Stau, Unfall) braucht es TomTom/HERE API
///     mit Subscription. Das ist NICHT eingebaut.
///
/// Sinnvoll als "early warning" — wenn ein OSM-Construction-Tag entlang
/// der geplanten Route gefunden wird, warnen wir den User noch vor Fahrt.
///
/// Cache: 60min pro Route-Fingerprint.
class RoadHazardService {
  RoadHazardService._();
  static final RoadHazardService instance = RoadHazardService._();

  static const _overpassUrl = 'https://overpass-api.de/api/interpreter';
  final Map<String, _HazardCacheEntry> _cache = {};

  Future<List<RoadHazard>> fetchHazardsAlongRoute({
    required List<List<double>> coordinates,
    double bufferMeters = 100,
  }) async {
    if (coordinates.length < 2) return [];
    final cacheKey = _cacheKey(coordinates);
    final cached = _cache[cacheKey];
    if (cached != null && cached.isFresh) return cached.hazards;

    try {
      final sampledRoute = _sampleRoute(coordinates, targetSamples: 80);
      final bbox = _boundingBox(sampledRoute, paddingDegrees: 0.012);

      // Suche nach gesperrten/construction Straßen
      final query = '''
[out:json][timeout:18];
(
  way["highway"="construction"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
  way["construction"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
  way["highway"]["access"="no"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
);
out center 100;
''';
      final response = await http
          .post(
            Uri.parse(_overpassUrl),
            headers: const {
              'User-Agent': 'CruiseConnect/1.0 (road-hazards)',
            },
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 18));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List? ?? [];
      final hazards = <RoadHazard>[];
      for (final el in elements) {
        try {
          final center = (el['center'] as Map?)?.cast<String, dynamic>();
          final lat = (center?['lat'] as num?)?.toDouble();
          final lng = (center?['lon'] as num?)?.toDouble();
          if (lat == null || lng == null) continue;
          final tags = (el['tags'] as Map?)?.cast<String, dynamic>() ?? {};
          // Distance to route
          final dist = _minDistanceToRoute(lat, lng, sampledRoute);
          if (dist > bufferMeters) continue;
          final type = tags['construction'] != null
              ? RoadHazardType.construction
              : tags['access'] == 'no'
                  ? RoadHazardType.closed
                  : RoadHazardType.construction;
          hazards.add(RoadHazard(
            id: (el['id'] as num).toInt(),
            type: type,
            latitude: lat,
            longitude: lng,
            roadName: tags['name'] as String?,
            constructionType: tags['construction'] as String?,
            note: tags['note'] as String?,
            distanceFromRouteMeters: dist,
          ));
        } catch (_) {
          continue;
        }
      }
      hazards.sort((a, b) => a.distanceFromRouteMeters
          .compareTo(b.distanceFromRouteMeters));
      _cache[cacheKey] = _HazardCacheEntry(hazards);
      return hazards;
    } catch (e) {
      debugPrint('[RoadHazardService] fetch failed: $e');
      return [];
    }
  }

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
    var minLat = coords.first[1], maxLat = coords.first[1];
    var minLng = coords.first[0], maxLng = coords.first[0];
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
      List<List<double>> route) {
    double minDist = double.infinity;
    for (final c in route) {
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

  String _cacheKey(List<List<double>> coords) {
    final first = coords.first;
    final last = coords.last;
    return '${first[0].toStringAsFixed(2)}|${first[1].toStringAsFixed(2)}|'
        '${last[0].toStringAsFixed(2)}|${last[1].toStringAsFixed(2)}|'
        '${coords.length}';
  }
}

class _HazardCacheEntry {
  _HazardCacheEntry(this.hazards) : at = DateTime.now();
  final List<RoadHazard> hazards;
  final DateTime at;
  bool get isFresh =>
      DateTime.now().difference(at) < const Duration(minutes: 60);
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

enum RoadHazardType {
  construction('Baustelle', '🚧'),
  closed('Gesperrt', '⛔'),
  trafficJam('Stau', '🚗');

  const RoadHazardType(this.label, this.emoji);
  final String label;
  final String emoji;
}

class RoadHazard {
  final int id;
  final RoadHazardType type;
  final double latitude;
  final double longitude;
  final String? roadName;
  final String? constructionType;
  final String? note;
  final double distanceFromRouteMeters;

  RoadHazard({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.distanceFromRouteMeters,
    this.roadName,
    this.constructionType,
    this.note,
  });

  String get displayName {
    if (roadName != null && roadName!.isNotEmpty) return roadName!;
    if (constructionType != null && constructionType!.isNotEmpty) {
      return 'Baustelle ($constructionType)';
    }
    return type.label;
  }
}
