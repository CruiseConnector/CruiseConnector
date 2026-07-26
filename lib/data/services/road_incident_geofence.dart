import 'dart:math' as math;

import 'package:cruise_connect/domain/models/road_incident.dart';

/// 2026-07-24 (vucko "+-Button"): Geofence für Verkehrsmeldungen — exakt das
/// bewährte [ConstructionGeofence]-Muster (Trigger <200m, Re-Arm >600m).
/// Die Hysterese ist gleichzeitig unsere Verbesserung gegenüber Google Maps:
/// dort nervt das "Noch da?"-Popup bei JEDER Vorbeifahrt — hier feuert es
/// pro Meldung nur einmal, bis man wirklich wieder weit weg war.
class RoadIncidentGeofence {
  RoadIncidentGeofence({this.enterMeters = 200, this.rearmMeters = 600});

  final double enterMeters;
  final double rearmMeters;

  List<RoadIncident> _incidents = const [];
  final Map<String, _GeofenceState> _stateById = {};

  void setIncidents(List<RoadIncident> incidents) {
    _incidents = incidents;
    final activeIds = incidents.map((i) => i.id).toSet();
    _stateById.removeWhere((id, _) => !activeIds.contains(id));
    for (final i in incidents) {
      _stateById.putIfAbsent(i.id, () => _GeofenceState());
    }
  }

  void clear() {
    _incidents = const [];
    _stateById.clear();
  }

  List<RoadIncident> processPosition({
    required double latitude,
    required double longitude,
  }) {
    if (_incidents.isEmpty) return const [];
    final newlyEntered = <RoadIncident>[];
    for (final incident in _incidents) {
      final state = _stateById[incident.id]!;
      final dist = _haversine(
        latitude,
        longitude,
        incident.latitude,
        incident.longitude,
      );

      if (state.inside) {
        if (dist > rearmMeters) {
          state.inside = false;
          state.armed = true;
        }
      } else {
        if (dist <= enterMeters && state.armed) {
          state.inside = true;
          state.armed = false;
          newlyEntered.add(incident);
        }
      }
    }
    return newlyEntered;
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
}

class _GeofenceState {
  bool inside = false;
  bool armed = true;
}
