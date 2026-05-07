import 'package:latlong2/latlong.dart';

import '../../domain/models/mapbox_suggestion.dart';
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
    MapboxSuggestion? destination,
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
              'maneuver_type': maneuver.maneuverType.name,
              if (maneuver.roundaboutExitNumber != null)
                'roundabout_exit_number': maneuver.roundaboutExitNumber,
            },
          )
          .toList(growable: false),
      'edgeMeta': edgeMeta,
      'routeMeta': edgeMeta,
      if (fingerprint != null) 'fingerprint': fingerprint,
    };
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
        map[entry.key.toString()] = _sanitizeJsonValue(entry.value);
      }
      return map;
    }
    if (value is Iterable) {
      return value.map(_sanitizeJsonValue).toList(growable: false);
    }
    return value.toString();
  }
}
