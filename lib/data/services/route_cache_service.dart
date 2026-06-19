import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/prepared_route_buffer.dart';
import 'package:cruise_connect/data/services/route_scenario.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

class CachedNavigationRoute {
  const CachedNavigationRoute({
    required this.route,
    required this.savedAt,
    required this.isRoundTrip,
    required this.style,
    required this.avoidHighways,
    this.groupId,
  });

  final RouteResult route;
  final DateTime savedAt;
  final bool isRoundTrip;
  final String style;
  final bool avoidHighways;
  final String? groupId;
}

/// Kleiner Szenario-Puffer für vorbereitete Ersatzrouten.
///
/// Der alte globale Queue-Cache wurde bewusst entfernt, weil er
/// identische oder fachlich falsche Routen in neue User-Intents tragen konnte.
/// Es gibt jetzt maximal eine vorbereitete Route pro Szenario.
class RouteCacheService {
  RouteCacheService._();
  static final RouteCacheService instance = RouteCacheService._();

  static const String _confirmedRouteKey = 'confirmed_navigation_route_v1';

  /// User-initiierte Generierung pausiert optionale Hintergrundarbeit.
  static bool userGenerationActive = false;
  static DateTime? _lastUserGenerationAt;

  static void beginUserGeneration() {
    userGenerationActive = true;
    _lastUserGenerationAt = DateTime.now();
  }

  static void endUserGeneration() {
    userGenerationActive = false;
    _lastUserGenerationAt = DateTime.now();
  }

  static bool get shouldPausePreparation {
    if (userGenerationActive) return true;
    final lastGeneration = _lastUserGenerationAt;
    if (lastGeneration == null) return false;
    return DateTime.now().difference(lastGeneration) <
        const Duration(seconds: 2);
  }

  static void resetForTests() {
    userGenerationActive = false;
    _lastUserGenerationAt = null;
  }

  Future<void> preloadRoutes() async {
    debugPrint(
      '[RouteCache] Globales Vorladen ist deaktiviert. '
      'Vorbereitung passiert nur noch szenariobezogen im PreparedRouteBuffer.',
    );
  }

  RouteResult? getNextRoute() => null;

  int get availableCount => PreparedRouteBuffer.count;

  RouteResult? takePreparedRoute(RouteScenario scenario) {
    return PreparedRouteBuffer.take(scenario.scenarioKey)?.route;
  }

  void storePreparedRoute(RouteScenario scenario, PreparedRouteEntry entry) {
    PreparedRouteBuffer.store(scenario.scenarioKey, entry);
  }

  void clearScenario(RouteScenario scenario) {
    PreparedRouteBuffer.clearScenario(scenario.scenarioKey);
  }

  void clearCache() {
    PreparedRouteBuffer.clearAll();
  }

  Future<void> storeConfirmedRoute({
    required RouteResult route,
    required bool isRoundTrip,
    required String style,
    required bool avoidHighways,
    String? groupId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _confirmedRouteKey,
      jsonEncode({
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'is_round_trip': isRoundTrip,
        'style': style,
        'avoid_highways': avoidHighways,
        'group_id': groupId,
        'route': _routeToJson(route),
      }),
    );
  }

  Future<CachedNavigationRoute?> loadConfirmedRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_confirmedRouteKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final routeRaw = map['route'];
      if (routeRaw is! Map) return null;
      final route = _routeFromJson(Map<String, dynamic>.from(routeRaw));
      if (route == null || route.coordinates.length < 2) return null;
      return CachedNavigationRoute(
        route: route,
        savedAt: DateTime.parse(map['saved_at'] as String),
        isRoundTrip: map['is_round_trip'] == true,
        style: map['style']?.toString() ?? 'Standard',
        avoidHighways: map['avoid_highways'] == true,
        groupId: map['group_id'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clearConfirmedRoute() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_confirmedRouteKey);
  }

  Map<String, dynamic> _routeToJson(RouteResult route) {
    return {
      'geo_json': route.geoJson,
      'geometry': _sanitizeJsonValue(route.geometry),
      'coordinates': route.coordinates
          .map((coord) => coord.take(2).toList(growable: false))
          .toList(growable: false),
      'maneuvers': route.maneuvers
          .map(
            (maneuver) => {
              'latitude': maneuver.latitude,
              'longitude': maneuver.longitude,
              'route_index': maneuver.routeIndex,
              'announcement': maneuver.announcement,
              'instruction': maneuver.instruction,
              'icon_name': _iconName(maneuver.icon),
              'maneuver_type': maneuver.maneuverType.name,
              'roundabout_exit_number': maneuver.roundaboutExitNumber,
              'roundabout_turn_angle': maneuver.roundaboutTurnAngleRad,
              'roundabout_entry_bearing': maneuver.roundaboutEntryBearing,
              'roundabout_exit_bearing': maneuver.roundaboutExitBearing,
              'roundabout_arm_bearings': maneuver.roundaboutArmBearings,
              'roundabout_island_scale': maneuver.roundaboutIslandScale,
              'roundabout_is_arrival': maneuver.roundaboutIsArrival,
            },
          )
          .toList(growable: false),
      'distance_meters': route.distanceMeters,
      'duration_seconds': route.durationSeconds,
      'distance_km': route.distanceKm,
      'speed_limits': route.speedLimits
          .map(
            (segment) => {
              'start_index': segment.startIndex,
              'end_index': segment.endIndex,
              'speed_kmh': segment.speedKmh,
            },
          )
          .toList(growable: false),
      'edge_meta': _sanitizeJsonValue(route.edgeMeta),
    };
  }

  RouteResult? _routeFromJson(Map<String, dynamic> json) {
    final coordinates = _coordinatesFromJson(json['coordinates']);
    if (coordinates.length < 2) return null;
    final geometry = json['geometry'] is Map
        ? Map<String, dynamic>.from(json['geometry'] as Map)
        : <String, dynamic>{'type': 'LineString', 'coordinates': coordinates};
    return RouteResult(
      geoJson:
          json['geo_json']?.toString() ??
          jsonEncode({'type': 'LineString', 'coordinates': coordinates}),
      geometry: geometry,
      coordinates: coordinates,
      maneuvers: _maneuversFromJson(json['maneuvers']),
      distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      speedLimits: _speedLimitsFromJson(json['speed_limits']),
      edgeMeta: json['edge_meta'] is Map
          ? Map<String, dynamic>.from(json['edge_meta'] as Map)
          : const <String, dynamic>{},
    );
  }

  List<List<double>> _coordinatesFromJson(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<List>()
        .where((coord) => coord.length >= 2)
        .map(
          (coord) => [
            (coord[0] as num).toDouble(),
            (coord[1] as num).toDouble(),
          ],
        )
        .toList(growable: false);
  }

  List<RouteManeuver> _maneuversFromJson(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((entry) {
          final map = Map<String, dynamic>.from(entry);
          final maneuverType = ManeuverType.values.firstWhere(
            (type) => type.name == map['maneuver_type'],
            orElse: () => ManeuverType.normal,
          );
          return RouteManeuver(
            latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
            longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
            routeIndex: (map['route_index'] as num?)?.toInt() ?? 0,
            icon: _iconFromJson(map, maneuverType: maneuverType),
            announcement: map['announcement']?.toString() ?? '',
            instruction: map['instruction']?.toString() ?? '',
            maneuverType: maneuverType,
            roundaboutExitNumber: (map['roundabout_exit_number'] as num?)
                ?.toInt(),
            roundaboutTurnAngleRad: (map['roundabout_turn_angle'] as num?)
                ?.toDouble(),
            roundaboutEntryBearing: (map['roundabout_entry_bearing'] as num?)
                ?.toDouble(),
            roundaboutExitBearing: (map['roundabout_exit_bearing'] as num?)
                ?.toDouble(),
            roundaboutArmBearings: _doubleListFromJson(
              map['roundabout_arm_bearings'],
            ),
            roundaboutIslandScale: (map['roundabout_island_scale'] as num?)
                ?.toDouble(),
            roundaboutIsArrival: map['roundabout_is_arrival'] == true,
          );
        })
        .toList(growable: false);
  }

  List<double>? _doubleListFromJson(Object? value) {
    if (value is! List) return null;
    return value
        .whereType<num>()
        .map((number) => number.toDouble())
        .toList(growable: false);
  }

  String _iconName(IconData icon) {
    if (icon == Icons.flag) return 'flag';
    if (icon == Icons.navigation) return 'navigation';
    if (icon == Icons.roundabout_right) return 'roundabout_right';
    if (icon == Icons.turn_left) return 'turn_left';
    if (icon == Icons.turn_right) return 'turn_right';
    if (icon == Icons.turn_slight_left) return 'turn_slight_left';
    if (icon == Icons.turn_slight_right) return 'turn_slight_right';
    if (icon == Icons.turn_sharp_left) return 'turn_sharp_left';
    if (icon == Icons.turn_sharp_right) return 'turn_sharp_right';
    if (icon == Icons.u_turn_left) return 'u_turn_left';
    if (icon == Icons.u_turn_right) return 'u_turn_right';
    if (icon == Icons.ramp_left) return 'ramp_left';
    if (icon == Icons.ramp_right) return 'ramp_right';
    if (icon == Icons.merge) return 'merge';
    if (icon == Icons.fork_left) return 'fork_left';
    if (icon == Icons.fork_right) return 'fork_right';
    return 'straight';
  }

  IconData _iconFromJson(
    Map<String, dynamic> json, {
    required ManeuverType maneuverType,
  }) {
    if (maneuverType == ManeuverType.roundabout) {
      return Icons.roundabout_right;
    }
    final iconName =
        json['icon_name']?.toString() ?? json['maneuver_icon']?.toString();
    final namedIcon = _iconFromName(iconName);
    if (namedIcon != null) return namedIcon;

    final codePoint = (json['icon_code_point'] as num?)?.toInt();
    if (codePoint != null) {
      final legacyIcon = _legacyIconFromCodePoint(codePoint);
      if (legacyIcon != null) return legacyIcon;
    }

    final instruction = json['instruction']?.toString().toLowerCase() ?? '';
    if (instruction.contains('ziel') || instruction.contains('arrive')) {
      return Icons.flag;
    }
    return Icons.straight;
  }

  IconData? _iconFromName(String? name) {
    switch (name) {
      case 'flag':
        return Icons.flag;
      case 'navigation':
        return Icons.navigation;
      case 'roundabout_right':
        return Icons.roundabout_right;
      case 'turn_left':
        return Icons.turn_left;
      case 'turn_right':
        return Icons.turn_right;
      case 'turn_slight_left':
        return Icons.turn_slight_left;
      case 'turn_slight_right':
        return Icons.turn_slight_right;
      case 'turn_sharp_left':
        return Icons.turn_sharp_left;
      case 'turn_sharp_right':
        return Icons.turn_sharp_right;
      case 'u_turn_left':
        return Icons.u_turn_left;
      case 'u_turn_right':
        return Icons.u_turn_right;
      case 'ramp_left':
        return Icons.ramp_left;
      case 'ramp_right':
        return Icons.ramp_right;
      case 'merge':
        return Icons.merge;
      case 'fork_left':
        return Icons.fork_left;
      case 'fork_right':
        return Icons.fork_right;
      case 'straight':
        return Icons.straight;
    }
    return null;
  }

  IconData? _legacyIconFromCodePoint(int codePoint) {
    if (codePoint == Icons.flag.codePoint) return Icons.flag;
    if (codePoint == Icons.navigation.codePoint) return Icons.navigation;
    if (codePoint == Icons.roundabout_right.codePoint) {
      return Icons.roundabout_right;
    }
    if (codePoint == Icons.turn_left.codePoint) return Icons.turn_left;
    if (codePoint == Icons.turn_right.codePoint) return Icons.turn_right;
    if (codePoint == Icons.turn_slight_left.codePoint) {
      return Icons.turn_slight_left;
    }
    if (codePoint == Icons.turn_slight_right.codePoint) {
      return Icons.turn_slight_right;
    }
    if (codePoint == Icons.turn_sharp_left.codePoint) {
      return Icons.turn_sharp_left;
    }
    if (codePoint == Icons.turn_sharp_right.codePoint) {
      return Icons.turn_sharp_right;
    }
    if (codePoint == Icons.u_turn_left.codePoint) return Icons.u_turn_left;
    if (codePoint == Icons.u_turn_right.codePoint) return Icons.u_turn_right;
    if (codePoint == Icons.ramp_left.codePoint) return Icons.ramp_left;
    if (codePoint == Icons.ramp_right.codePoint) return Icons.ramp_right;
    if (codePoint == Icons.merge.codePoint) return Icons.merge;
    if (codePoint == Icons.fork_left.codePoint) return Icons.fork_left;
    if (codePoint == Icons.fork_right.codePoint) return Icons.fork_right;
    if (codePoint == Icons.straight.codePoint) return Icons.straight;
    return null;
  }

  List<SpeedLimitSegment> _speedLimitsFromJson(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((entry) {
          final map = Map<String, dynamic>.from(entry);
          return SpeedLimitSegment(
            startIndex: (map['start_index'] as num?)?.toInt() ?? 0,
            endIndex: (map['end_index'] as num?)?.toInt() ?? 0,
            speedKmh: (map['speed_kmh'] as num?)?.toInt() ?? 0,
          );
        })
        .toList(growable: false);
  }

  dynamic _sanitizeJsonValue(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is Map) {
      final map = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final lower = key.toLowerCase();
        if (lower.contains('token') ||
            lower.contains('secret') ||
            lower.contains('authorization') ||
            lower.contains('password')) {
          continue;
        }
        map[key] = _sanitizeJsonValue(entry.value);
      }
      return map;
    }
    if (value is Iterable) {
      return value.map(_sanitizeJsonValue).toList(growable: false);
    }
    return value.toString();
  }
}
