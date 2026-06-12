import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

import '../../domain/models/place_suggestion.dart';
import '../../domain/models/route_maneuver.dart';
import '../../domain/models/route_result.dart';

class GroupRouteDataBuilder {
  const GroupRouteDataBuilder._();

  static Map<String, dynamic> build({
    required RouteResult route,
    required bool isRoundTrip,
    required String planningType,
    required String style,
    required bool avoidHighways,
    int? targetDistanceKm,
    PlaceSuggestion? destination,
    List<LatLng> requiredWaypoints = const [],
    String? waypointOrigin,
    int? waypointSeedAttempt,
    int detourVariant = 0,
    bool scenic = false,
  }) {
    final routeType = isRoundTrip ? 'ROUND_TRIP' : 'POINT_TO_POINT';
    final edgeMeta = _sanitizeJsonMap(route.edgeMeta);
    final fingerprint =
        edgeMeta['route_fingerprint'] ??
        edgeMeta['routeFingerprint'] ??
        edgeMeta['fingerprint'];

    return <String, dynamic>{
      'geoJson': route.geoJson,
      'geometry': _sanitizeJsonValue(route.geometry),
      'coordinates': route.coordinates
          .map((coord) => coord.take(2).toList(growable: false))
          .toList(growable: false),
      'distance_meters': route.distanceMeters,
      'duration_seconds': route.durationSeconds,
      'distance_km': route.distanceKm ?? ((route.distanceMeters ?? 0) / 1000.0),
      'style': style,
      'route_type': routeType,
      'planning_type': planningType,
      'avoid_highways': avoidHighways,
      'target_distance_km': targetDistanceKm,
      'length_km_target': targetDistanceKm,
      'destination': destination == null
          ? null
          : <String, dynamic>{
              'latitude': destination.latitude,
              'longitude': destination.longitude,
              'place_name': destination.placeName,
              if (destination.context != null) 'context': destination.context,
            },
      'required_waypoints': requiredWaypoints
          .map(
            (point) => <String, dynamic>{
              'latitude': point.latitude,
              'longitude': point.longitude,
            },
          )
          .toList(growable: false),
      'waypoint_origin': waypointOrigin,
      'waypoint_seed_attempt': waypointSeedAttempt,
      'detour_variant': detourVariant,
      'scenic': scenic,
      'maneuvers': route.maneuvers
          .map(
            (maneuver) => <String, dynamic>{
              'latitude': maneuver.latitude,
              'longitude': maneuver.longitude,
              'route_index': maneuver.routeIndex,
              'announcement': maneuver.announcement,
              'instruction': maneuver.instruction,
              'maneuver_icon': _iconName(maneuver.icon),
              'maneuver_type': maneuver.maneuverType.name,
              if (maneuver.roundaboutExitNumber != null)
                'roundabout_exit_number': maneuver.roundaboutExitNumber,
              if (maneuver.roundaboutTurnAngleRad != null)
                'roundabout_turn_angle': maneuver.roundaboutTurnAngleRad,
            },
          )
          .toList(growable: false),
      'edgeMeta': edgeMeta,
      'routeMeta': edgeMeta,
      if (fingerprint != null) 'fingerprint': fingerprint,
    };
  }

  static Map<String, dynamic> replaceRoutePayload({
    required RouteResult route,
    required Map<String, dynamic>? previousRouteData,
    required String updateReason,
  }) {
    final next = _sanitizeJsonMap(previousRouteData ?? const {});
    final edgeMeta = _sanitizeJsonMap(route.edgeMeta);
    final fingerprint =
        edgeMeta['route_fingerprint'] ??
        edgeMeta['routeFingerprint'] ??
        edgeMeta['fingerprint'] ??
        next['fingerprint'];

    next
      ..['geoJson'] = route.geoJson
      ..['geometry'] = _sanitizeJsonValue(route.geometry)
      ..['coordinates'] = route.coordinates
          .map((coord) => coord.take(2).toList(growable: false))
          .toList(growable: false)
      ..['distance_meters'] = route.distanceMeters
      ..['duration_seconds'] = route.durationSeconds
      ..['distance_km'] =
          route.distanceKm ?? ((route.distanceMeters ?? 0) / 1000.0)
      ..['maneuvers'] = route.maneuvers
          .map(
            (maneuver) => <String, dynamic>{
              'latitude': maneuver.latitude,
              'longitude': maneuver.longitude,
              'route_index': maneuver.routeIndex,
              'announcement': maneuver.announcement,
              'instruction': maneuver.instruction,
              'maneuver_icon': _iconName(maneuver.icon),
              'maneuver_type': maneuver.maneuverType.name,
              if (maneuver.roundaboutExitNumber != null)
                'roundabout_exit_number': maneuver.roundaboutExitNumber,
              if (maneuver.roundaboutTurnAngleRad != null)
                'roundabout_turn_angle': maneuver.roundaboutTurnAngleRad,
            },
          )
          .toList(growable: false)
      ..['edgeMeta'] = edgeMeta
      ..['routeMeta'] = edgeMeta
      ..['update_reason'] = updateReason;

    if (fingerprint != null) next['fingerprint'] = fingerprint;
    return next;
  }

  static RouteResult? parseRouteResult(Map<String, dynamic>? routeData) {
    if (routeData == null || routeData.isEmpty) return null;

    final geometry = _geometryFromRouteData(routeData);
    final coordinates = _coordinatesFromRouteData(routeData, geometry);
    if (coordinates.length < 2) return null;

    final normalizedGeometry = <String, dynamic>{
      'type': 'LineString',
      'coordinates': coordinates,
    };
    final geoJson = routeData['geoJson'] is String
        ? routeData['geoJson'] as String
        : const JsonEncoder().convert(geometry ?? normalizedGeometry);

    final edgeMetaRaw = routeData['edgeMeta'] ?? routeData['routeMeta'];
    final edgeMeta = edgeMetaRaw is Map
        ? _sanitizeJsonMap(Map<String, dynamic>.from(edgeMetaRaw))
        : const <String, dynamic>{};

    return RouteResult(
      geoJson: geoJson.startsWith('{') ? geoJson : _jsonLineString(coordinates),
      geometry: geometry ?? normalizedGeometry,
      coordinates: coordinates,
      maneuvers: _maneuversFromRouteData(routeData),
      distanceMeters: (routeData['distance_meters'] as num?)?.toDouble(),
      durationSeconds: (routeData['duration_seconds'] as num?)?.toDouble(),
      distanceKm: (routeData['distance_km'] as num?)?.toDouble(),
      edgeMeta: edgeMeta,
    );
  }

  static Map<String, dynamic>? _geometryFromRouteData(
    Map<String, dynamic> routeData,
  ) {
    final geometry = routeData['geometry'];
    if (geometry is Map) {
      return Map<String, dynamic>.from(geometry);
    }

    final geoJson = routeData['geoJson'];
    if (geoJson is String && geoJson.trim().isNotEmpty) {
      final parsed = _jsonDecodeMap(geoJson);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static List<List<double>> _coordinatesFromRouteData(
    Map<String, dynamic> routeData,
    Map<String, dynamic>? geometry,
  ) {
    final coordinatesRaw = routeData['coordinates'] ?? geometry?['coordinates'];
    if (coordinatesRaw is! List) return const [];
    return coordinatesRaw
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

  static List<RouteManeuver> _maneuversFromRouteData(
    Map<String, dynamic> routeData,
  ) {
    final raw = routeData['maneuvers'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((entry) {
          final map = Map<String, dynamic>.from(entry);
          final maneuverType = _maneuverTypeFromName(
            map['maneuver_type']?.toString(),
          );
          return RouteManeuver(
            latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
            longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
            routeIndex: (map['route_index'] as num?)?.toInt() ?? 0,
            icon: _iconFromName(
              map['maneuver_icon']?.toString(),
              maneuverType: maneuverType,
              instruction: map['instruction']?.toString(),
            ),
            announcement: map['announcement']?.toString() ?? '',
            instruction: map['instruction']?.toString() ?? '',
            maneuverType: maneuverType,
            roundaboutExitNumber: (map['roundabout_exit_number'] as num?)
                ?.toInt(),
            roundaboutTurnAngleRad: (map['roundabout_turn_angle'] as num?)
                ?.toDouble(),
          );
        })
        .toList(growable: false);
  }

  static ManeuverType _maneuverTypeFromName(String? name) {
    return ManeuverType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => ManeuverType.normal,
    );
  }

  static String _iconName(IconData icon) {
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

  static IconData _iconFromName(
    String? name, {
    required ManeuverType maneuverType,
    String? instruction,
  }) {
    if (maneuverType == ManeuverType.roundabout) return Icons.roundabout_right;
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
    final lowerInstruction = instruction?.toLowerCase() ?? '';
    if (lowerInstruction.contains('ziel') ||
        lowerInstruction.contains('arrive')) {
      return Icons.flag;
    }
    return Icons.straight;
  }

  static Map<String, dynamic>? _jsonDecodeMap(String source) {
    try {
      final decoded = const JsonDecoder().convert(source);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  static String _jsonLineString(List<List<double>> coordinates) {
    return const JsonEncoder().convert({
      'type': 'LineString',
      'coordinates': coordinates,
    });
  }

  static Map<String, dynamic> _sanitizeJsonMap(Map<String, dynamic> source) {
    final sanitized = <String, dynamic>{};
    for (final entry in source.entries) {
      final key = entry.key;
      final lower = key.toLowerCase();
      if (lower.contains('token') ||
          lower.contains('secret') ||
          lower.contains('authorization') ||
          lower.contains('password')) {
        continue;
      }
      sanitized[key] = _sanitizeJsonValue(entry.value);
    }
    return sanitized;
  }

  static dynamic _sanitizeJsonValue(dynamic value) {
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
