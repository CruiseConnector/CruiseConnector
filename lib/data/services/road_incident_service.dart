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

/// 2026-08-20 (Vucko: „Ich habe es gemeldet … und mir wurde nichts angezeigt
/// von meiner vorherigen Meldung."): Fuehrt [aufruf] mit einem Zeitdeckel aus.
///
/// Der Ortsnachweis geht unmittelbar VOR der Meldung raus. Ohne Deckel wuerde
/// ein haengender Server oder ein Funkloch damit das Melden selbst blockieren,
/// und die Funktion waere schlechter als vorher. Kommt der Nachweis nicht
/// durch, ist das Ergebnis false und der Aufrufer meldet trotzdem — die
/// Meldung lebt dann nur kuerzer.
///
/// Eigene Funktion, damit dieses Zeitverhalten ohne Datenbank pruefbar ist.
Future<bool> ortsnachweisMitDeckel(
  Future<void> Function() aufruf,
  Duration? timeout,
) async {
  try {
    final future = aufruf();
    if (timeout == null) {
      await future;
    } else {
      await future.timeout(timeout);
    }
    return true;
  } catch (e) {
    debugPrint('[RoadIncident] Position senden fehlgeschlagen: $e');
    return false;
  }
}

/// 2026-08-20 (Vucko: „bin ich spaeter wieder diese Strasse gefahren"): Nur
/// die Meldungen, die JETZT noch gelten.
///
/// Diese Pruefung stand bisher nur im Ladeweg. Die geladene Liste wurde
/// waehrend der Fahrt NIE erneut gegen die Uhr gehalten: eine Meldung, die um
/// 14:00 ablief, stand bei einer Fahrt von 13:30 bis 16:00 zweieinhalb Stunden
/// zu lang auf der Karte, und der Geofence haette danach noch nach ihr
/// gefragt. Jetzt benutzen Ladeweg und Auffrisch-Takt dieselbe Funktion.
///
/// [jetzt] ist nur fuer Tests da; im Betrieb gilt die Uhr.
List<RoadIncident> nurGueltigeMeldungen(
  Iterable<RoadIncident> incidents, {
  DateTime? jetzt,
}) {
  final zeitpunkt = (jetzt ?? DateTime.now()).toUtc();
  return [
    for (final i in incidents)
      if (i.active && i.expiresAt.toUtc().isAfter(zeitpunkt)) i,
  ];
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
          message: 'Melden fehlgeschlagen. Bitte spaeter erneut versuchen.',
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
        message: 'Melden fehlgeschlagen. Bitte spaeter erneut versuchen.',
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

  /// Letzte bekannte Position. Sie ist der Beleg dafuer, dass eine Meldung
  /// wirklich von vor Ort kommt, und entscheidet serverseitig ueber die
  /// Lebensdauer: mit Beleg lebt eine Baustelle 14 Tage, ohne Beleg 24 Stunden.
  ///
  /// 2026-08-20 (Vucko: „Ich habe es gemeldet, und dann bin ich spaeter wieder
  /// diese Strasse gefahren, wo eine Baustelle ist, und mir wurde nichts
  /// angezeigt von meiner vorherigen Meldung."): Gemessen wurde diese Position
  /// bisher NUR aus dem Fahrt-Tracking gesendet, hoechstens einmal pro Minute.
  /// Der Melde-Knopf ist aber schon sichtbar, sobald die Route bestaetigt ist,
  /// also vor dem Losfahren. Alle drei ungeprueften Meldungen in der Datenbank
  /// lebten deshalb genau 15 Minuten. Der Aufrufer sendet die Position jetzt
  /// zusaetzlich unmittelbar vor jeder Meldung.
  ///
  /// [timeout] deckelt die Wartezeit: ohne Deckel wuerde ein haengender Server
  /// oder ein Funkloch das Melden blockieren, und dann waere die Funktion
  /// schlechter als vorher. Rueckgabe sagt, ob der Beleg wirklich ankam.
  Future<bool> pushLivePosition(
    double lat,
    double lng, {
    Duration? timeout,
  }) async {
    return ortsnachweisMitDeckel(
      () => _db.rpc('set_live_position', params: {'p_lat': lat, 'p_lng': lng}),
      timeout,
    );
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
          out.add(RoadIncident.fromJson(Map<String, dynamic>.from(row)));
        } catch (e) {
          debugPrint('[RoadIncident] parse failed: $e');
        }
      }
      // Dieselbe Pruefung wie im Auffrisch-Takt der Fahransicht — eine Quelle,
      // damit beide nicht auseinanderlaufen.
      return nurGueltigeMeldungen(out);
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
