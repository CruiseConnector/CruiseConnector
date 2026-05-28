import 'dart:math' as math;

import 'package:cruise_connect/domain/models/construction_report.dart';

/// 2026-05-28 (vucko Task #66): Geofence-Tracker für Baustellen.
///
/// Pattern: Geolocator-Stream feuert auf jeden Position-Update. Diese
/// Klasse hält die aktuelle Liste an Baustellen für die Route und liefert
/// `enterEvents` wenn der User unter ein Schwellwert kommt. Hysterese
/// verhindert dass dieselbe Baustelle 2× pro Trip getriggert wird:
///   - Trigger bei < enterMeters (default 200m)
///   - Re-Arm bei > rearmMeters (default 600m)
///
/// Im Loop sehr günstig: O(reports) pro Position-Update. Bei <50 reports
/// pro Route bleibt das unter 0.1ms.
class ConstructionGeofence {
  ConstructionGeofence({
    this.enterMeters = 200,
    this.rearmMeters = 600,
  });

  final double enterMeters;
  final double rearmMeters;

  /// Aktive Reports für die laufende Route. Wird über [setReports] gesetzt.
  List<ConstructionReport> _reports = const [];

  /// State pro Report-ID: true = User war drin, noch nicht raus.
  final Map<String, _GeofenceState> _stateById = {};

  void setReports(List<ConstructionReport> reports) {
    _reports = reports;
    // Stale entfernen, neue State-Slots anlegen.
    final activeIds = reports.map((r) => r.id).toSet();
    _stateById.removeWhere((id, _) => !activeIds.contains(id));
    for (final r in reports) {
      _stateById.putIfAbsent(r.id, () => _GeofenceState());
    }
  }

  void clear() {
    _reports = const [];
    _stateById.clear();
  }

  /// Liefert die Reports für die der User gerade INNERHALB der Trigger-
  /// Zone ist UND die Re-Arm-Zone noch nicht durchquert wurden.
  ///
  /// Aufgerufen pro Position-Update; UI ruft dann das Bottom-Sheet auf.
  List<ConstructionReport> processPosition({
    required double latitude,
    required double longitude,
  }) {
    if (_reports.isEmpty) return const [];
    final newlyEntered = <ConstructionReport>[];
    for (final report in _reports) {
      final state = _stateById[report.id]!;
      final dist =
          _haversine(latitude, longitude, report.latitude, report.longitude);

      if (state.inside) {
        // User ist in der Zone — Re-Arm-Check
        if (dist > rearmMeters) {
          state.inside = false;
          state.armed = true;
        }
      } else {
        // User ist draußen — Trigger-Check
        if (dist <= enterMeters && state.armed) {
          state.inside = true;
          state.armed = false;
          state.alertsShown += 1;
          newlyEntered.add(report);
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
  bool armed = true; // Wird false nach Trigger bis Re-Arm
  int alertsShown = 0;
}
