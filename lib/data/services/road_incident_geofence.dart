import 'dart:math' as math;

import 'package:cruise_connect/domain/models/road_incident.dart';

/// 2026-08-20 (Vucko: „Die neue Funktion mit Unfaelle melden, Baustellen und
/// auch Stau ist leider noch nicht so funktional."): Wie weit VOR einer
/// Meldung gewarnt werden muss.
///
/// GEMESSENE AUSGANGSLAGE: Die Vorwarnung lag fest bei 200 m. Bei 100 km/h
/// sind das 7,2 Sekunden — zu wenig, um vom Gas zu gehen, und viel zu wenig,
/// um nebenbei „Noch da?" zu beantworten. Bei 130 km/h sind es 5,5 Sekunden.
///
/// Statt einer festen Strecke gilt jetzt eine feste VORLAUFZEIT von 18
/// Sekunden. Das ist die Spanne, in der ein Fahrer eine Information aufnimmt,
/// den Fuss vom Gas nimmt und noch einen Knopf treffen kann, ohne sich zu
/// hetzen. Die Untergrenze von 200 m haelt die Warnung im Stadtverkehr genau
/// dort, wo sie vorher schon richtig war; die Obergrenze von 900 m verhindert,
/// dass auf der Autobahn vor etwas gewarnt wird, das noch eine
/// Anschlussstelle weit weg ist.
///
///   50 km/h  (13,9 m/s) →  250 m
///  100 km/h  (27,8 m/s) →  500 m
///  130 km/h  (36,1 m/s) →  650 m
double meldungsVorwarnungMeter(
  double? tempoMetersPerSecond, {
  double vorlaufSekunden = 18.0,
  double minMeter = 200.0,
  double maxMeter = 900.0,
}) {
  final tempo = tempoMetersPerSecond;
  if (tempo == null || !tempo.isFinite || tempo <= 0) return minMeter;
  return (tempo * vorlaufSekunden).clamp(minMeter, maxMeter).toDouble();
}

/// 2026-07-24 (vucko "+-Button"): Geofence für Verkehrsmeldungen — exakt das
/// bewährte [ConstructionGeofence]-Muster (Trigger <200m, Re-Arm >600m).
/// Die Hysterese ist gleichzeitig unsere Verbesserung gegenüber Google Maps:
/// dort nervt das "Noch da?"-Popup bei JEDER Vorbeifahrt — hier feuert es
/// pro Meldung nur einmal, bis man wirklich wieder weit weg war.
///
/// 2026-08-20 (Vucko: „ist leider noch nicht so funktional", und zu den
/// Abfragen: „jetzt nicht, wenn es ja ein [unklar] oder so"): Zwei
/// Aenderungen.
///
///  1. Der Ausloeseradius haengt jetzt am Tempo (siehe
///     [meldungsVorwarnungMeter]). Der feste 200-m-Ring war bei
///     Autobahntempo eine Warnung von sieben Sekunden.
///  2. Je Meldung wird nur noch EINMAL PRO FAHRT ausgeloest, nicht mehr
///     einmal pro Vorbeifahrt. Der Re-Arm ueber 600 m hat auf einem Rundkurs
///     dieselbe Baustelle zweimal aufgemacht, und beim Hin- und Zurueckfahren
///     derselben Strasse ebenfalls. Zurueckgesetzt wird das erst mit
///     [clear], also beim Routenwechsel und beim Fahrtende.
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

  /// Der Ausloeseradius, mit dem dieser Fix bewertet wird. Oeffentlich, weil
  /// die Fahransicht damit entscheidet, ob eine Meldung ueberhaupt noch weit
  /// genug weg ist, um sie anzusagen.
  double ausloeseRadiusMeter(double? tempoMetersPerSecond) {
    return math.max(
      enterMeters,
      meldungsVorwarnungMeter(tempoMetersPerSecond, minMeter: enterMeters),
    );
  }

  List<RoadIncident> processPosition({
    required double latitude,
    required double longitude,
    double? speedMetersPerSecond,
  }) {
    if (_incidents.isEmpty) return const [];
    final ausloeseRadius = ausloeseRadiusMeter(speedMetersPerSecond);
    // Der Re-Arm muss mit dem Ausloeseradius mitwachsen, sonst laege er bei
    // Autobahntempo INNERHALB des Rings und die Hysterese waere aufgehoben.
    final rearm = math.max(rearmMeters, ausloeseRadius * 2.5);
    final newlyEntered = <RoadIncident>[];
    for (final incident in _incidents) {
      final state = _stateById[incident.id]!;
      // Einmal je Fahrt reicht. Siehe Klassenkommentar.
      if (state.schonAusgeloest) continue;
      final dist = _haversine(
        latitude,
        longitude,
        incident.latitude,
        incident.longitude,
      );

      if (state.inside) {
        if (dist > rearm) {
          state.inside = false;
          state.armed = true;
        }
      } else {
        if (dist <= ausloeseRadius && state.armed) {
          state.inside = true;
          state.armed = false;
          state.schonAusgeloest = true;
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

  /// 2026-08-20: Diese Meldung hatte in dieser Fahrt schon ihren Auftritt.
  bool schonAusgeloest = false;
}
