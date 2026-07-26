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
class RoadIncidentService {
  RoadIncidentService._();
  static final RoadIncidentService instance = RoadIncidentService._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// Meldet eine neue Verkehrslage an der aktuellen Position.
  Future<RoadIncident?> report({
    required RoadIncidentType type,
    required double latitude,
    required double longitude,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    try {
      final response = await _db
          .from('road_incidents')
          .insert({
            'type': type.name,
            'lat': latitude,
            'lng': longitude,
            'reported_by': user.id,
            'expires_at': DateTime.now()
                .toUtc()
                .add(type.ttl)
                .toIso8601String(),
          })
          .select()
          .single();
      return RoadIncident.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      debugPrint('[RoadIncident] report failed: $e');
      return null;
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

  /// Stau-Ausdehnung nachtragen (nur eigene Meldung, RLS ri_update_own).
  Future<void> updateJamExtent({
    required String incidentId,
    required double endLat,
    required double endLng,
  }) async {
    try {
      await _db
          .from('road_incidents')
          .update({'jam_end_lat': endLat, 'jam_end_lng': endLng})
          .eq('id', incidentId);
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
