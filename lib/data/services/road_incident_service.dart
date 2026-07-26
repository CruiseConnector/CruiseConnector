import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/domain/models/road_incident.dart';

/// 2026-07-24 (vucko "+-Button: Unfall/Baustelle/Stau melden"): Service für
/// Crowd-Verkehrsmeldungen — Waze-Prinzip, Muster nach
/// [ConstructionReportService] (aber Crowd-only, kein Overpass-Fallback).
///
/// - Melden: 1 Tap, Position = aktuelle GPS-Position, TTL pro Typ.
/// - Live-Sync: Realtime-Kanal auf `road_incidents` — andere Fahrer sehen
///   neue Meldungen ohne Refresh.
/// - Votes: "Noch da?/Weg" beim Vorbeifahren, via SECURITY-DEFINER-RPC
///   (`vote_road_incident`) — kein Doppel-Vote, Counter serverseitig.
///
/// 2026-07-26 (vucko "darf nicht ausgenutzt werden koennen"): Der Client
/// schreibt NICHT mehr direkt in `road_incidents` — die Schreibrechte sind
/// entzogen. Alles laeuft ueber SECURITY-DEFINER-Funktionen, die serverseitig
/// Ort, Menge und Vertrauen pruefen. Konkret kann der Client damit weder
/// `expires_at` noch `active`, `confirmed_count`, `visibility` oder
/// `reported_by` bestimmen — genau die Felder, ueber die sich das System
/// vorher haette aushebeln lassen.
class RoadIncidentReportResult {
  const RoadIncidentReportResult({this.incident, this.message, this.merged = false});

  /// Die (neue oder zusammengefuehrte) Meldung — null bei Ablehnung.
  final RoadIncident? incident;

  /// Server-Begruendung bei Ablehnung, direkt anzeigbar (deutsch).
  final String? message;

  /// true = es gab hier schon dieselbe Meldung, sie wurde nur bestaetigt.
  final bool merged;

  bool get ok => incident != null;
}

class RoadIncidentService {
  RoadIncidentService._();
  static final RoadIncidentService instance = RoadIncidentService._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// Meldet eine neue Verkehrslage. Der Server entscheidet ueber Annahme,
  /// Lebensdauer und Sichtbarkeit; abgelehnt wird mit einer Begruendung, die
  /// direkt angezeigt werden kann (Tageslimit, zu schnell hintereinander,
  /// unplausible Entfernung, Sperre).
  Future<RoadIncidentReportResult> report({
    required RoadIncidentType type,
    required double latitude,
    required double longitude,
  }) async {
    if (_db.auth.currentUser == null) {
      return const RoadIncidentReportResult(message: 'Nicht angemeldet.');
    }
    try {
      final res = await _db.rpc('report_road_incident', params: {
        'p_type': type.name,
        'p_lat': latitude,
        'p_lng': longitude,
      });
      final map = Map<String, dynamic>.from(res as Map);
      final id = map['incident_id'] as String?;
      if (id == null) {
        return const RoadIncidentReportResult(
          message: 'Melden fehlgeschlagen — bitte spaeter erneut versuchen.',
        );
      }
      final row = await _db
          .from('road_incidents')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (row == null) {
        // Kann passieren, wenn die Meldung still gestellt wurde und die
        // Policy sie fuer diesen Nutzer nicht liefert — kein Fehlerfall.
        return RoadIncidentReportResult(merged: map['merged'] == true);
      }
      return RoadIncidentReportResult(
        incident: RoadIncident.fromJson(Map<String, dynamic>.from(row)),
        merged: map['merged'] == true,
      );
    } on PostgrestException catch (e) {
      debugPrint('[RoadIncident] report abgelehnt: ${e.message}');
      return RoadIncidentReportResult(message: _readableError(e.message));
    } catch (e) {
      debugPrint('[RoadIncident] report failed: $e');
      return const RoadIncidentReportResult(
        message: 'Melden fehlgeschlagen — bitte spaeter erneut versuchen.',
      );
    }
  }

  /// Postgres haengt an Exceptions gern Kontext an; fuer den Nutzer bleibt nur
  /// der eigentliche Satz uebrig.
  String _readableError(String raw) {
    final cleaned = raw.split('\n').first.trim();
    return cleaned.isEmpty
        ? 'Melden gerade nicht moeglich.'
        : cleaned;
  }

  /// Eigene Meldung zuruecknehmen — der schnellste saubere Weg, einen Fehler
  /// zu korrigieren, und er kostet den Melder kein Vertrauen.
  Future<bool> retract(String incidentId) async {
    try {
      await _db.rpc('retract_road_incident',
          params: {'p_incident_id': incidentId});
      return true;
    } catch (e) {
      debugPrint('[RoadIncident] retract failed: $e');
      return false;
    }
  }

  /// Letzte bekannte Position — NUR waehrend laufender Navigation setzen.
  /// Sie ist der Beleg dafuer, dass eine Meldung wirklich von vor Ort kommt.
  Future<void> pushLivePosition(double lat, double lng) async {
    try {
      await _db.rpc('set_live_position', params: {'p_lat': lat, 'p_lng': lng});
    } catch (e) {
      debugPrint('[RoadIncident] Position senden fehlgeschlagen: $e');
    }
  }

  /// Beim Fahrtende wieder loeschen (vuckos Vorgabe: keine Standortdaten
  /// ausserhalb aktiver Navigation aufbewahren).
  Future<void> clearLivePosition() async {
    try {
      await _db.rpc('clear_live_position');
    } catch (e) {
      debugPrint('[RoadIncident] Position loeschen fehlgeschlagen: $e');
    }
  }

  /// Aktive, nicht abgelaufene Meldungen in einer BBox. Die RLS-Policy
  /// filtert serverseitig bereits auf active + expires_at — der Client
  /// filtert zur doppelten Sicherheit nochmal.
  Future<List<RoadIncident>> fetchInBbox({
    required double southLat,
    required double westLng,
    required double northLat,
    required double eastLng,
  }) async {
    try {
      final rows = await _db
          .from('road_incidents')
          .select()
          .gte('lat', southLat)
          .lte('lat', northLat)
          .gte('lng', westLng)
          .lte('lng', eastLng)
          .limit(200);
      final out = <RoadIncident>[];
      for (final row in rows) {
        try {
          final incident = RoadIncident.fromJson(
            Map<String, dynamic>.from(row),
          );
          if (incident.active && !incident.isExpired) out.add(incident);
        } catch (e) {
          debugPrint('[RoadIncident] parse failed: $e');
        }
      }
      return out;
    } catch (e) {
      debugPrint('[RoadIncident] fetch failed: $e');
      return const [];
    }
  }

  /// Nur Meldungen nahe der Route (Sampling-Verfahren wie
  /// ConstructionReportService.filterToRoute).
  List<RoadIncident> filterToRoute({
    required List<RoadIncident> incidents,
    required List<List<double>> routeCoordinates,
    double bufferMeters = 200,
  }) {
    if (incidents.isEmpty || routeCoordinates.length < 2) return const [];
    final samples = _sampleRoute(routeCoordinates, targetSamples: 80);
    final filtered = <RoadIncident>[];
    for (final incident in incidents) {
      var minDist = double.infinity;
      for (final c in samples) {
        final d = _haversine(incident.latitude, incident.longitude, c[1], c[0]);
        if (d < minDist) minDist = d;
        if (minDist <= bufferMeters) break;
      }
      if (minDist <= bufferMeters) filtered.add(incident);
    }
    return filtered;
  }

  /// "Noch da" (true) oder "Schon weg" (false) — idempotent via RPC.
  Future<bool> vote({required String incidentId, required bool stillThere}) async {
    if (_db.auth.currentUser == null) return false;
    try {
      await _db.rpc(
        'vote_road_incident',
        params: {
          'p_incident_id': incidentId,
          'p_vote': stillThere ? 'confirm' : 'dismiss',
        },
      );
      return true;
    } catch (e) {
      debugPrint('[RoadIncident] vote failed: $e');
      return false;
    }
  }

  /// Stau-Ausdehnung nachtragen — serverseitig auf die eigene Meldung, den
  /// Typ „stau" und eine plausible Laenge begrenzt.
  Future<void> updateJamExtent({
    required String incidentId,
    required double endLat,
    required double endLng,
  }) async {
    try {
      await _db.rpc('update_jam_extent', params: {
        'p_incident_id': incidentId,
        'p_end_lat': endLat,
        'p_end_lng': endLng,
      });
    } catch (e) {
      debugPrint('[RoadIncident] jam extent update failed: $e');
    }
  }

  /// Realtime-Kanal: feuert [onChange] bei jeder Änderung an
  /// `road_incidents` (Insert/Update). Aufrufer refetcht dann die Route-BBox
  /// (leichtgewichtig, debounced im Aufrufer). Kanal-Muster nach
  /// CommunityChatService.subscribeMessages.
  RealtimeChannel subscribeIncidents(void Function() onChange) {
    final channel = _db.channel('road_incidents_live');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'road_incidents',
      callback: (_) => onChange(),
    );
    channel.subscribe();
    return channel;
  }

  // ───────────────────── Helpers ──────────────────────────────────────
  List<List<double>> _sampleRoute(
    List<List<double>> coords, {
    required int targetSamples,
  }) {
    if (coords.length <= targetSamples) return coords;
    final step = coords.length / targetSamples;
    final out = <List<double>>[];
    for (var i = 0; i < targetSamples; i++) {
      out.add(coords[(i * step).floor()]);
    }
    out.add(coords.last);
    return out;
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
