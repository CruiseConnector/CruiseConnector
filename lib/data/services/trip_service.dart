import 'package:supabase_flutter/supabase_flutter.dart';

/// Trip-Service — Multi-Stop Touren mit Pause/Resume.
///
/// DB-Schema: `trips`, `trip_stops`, `trip_segments`
/// (siehe `supabase/migrations/20260523010000_trips_schema.sql`).
///
/// 2026-05-22 (vucko Task #2): Foundation für Trip-UI.
/// Dieses Service liefert die Trip-Lifecycle-Operations (CRUD + Resume).
/// UI (Trip-Wizard, Resume-Card im Home) folgt in separate PRs.
class TripService {
  TripService._();
  static final TripService instance = TripService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Erstellt eine neue Trip in DB inkl. trip_stops für jeden Wegpunkt.
  /// Returnt die Trip-ID oder null bei Fehler.
  ///
  /// 2026-05-24 (vucko Task #53): UI-Integration für Trip-Save+Resume.
  Future<String?> createTrip({
    required String title,
    required List<({double lat, double lng, String name, String stopType})> stops,
    required String defaultStyle,
    required bool defaultAvoidHighways,
    String? groupId,
    double totalDistanceKm = 0,
    int totalDurationSeconds = 0,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      // 1. Trip erzeugen (aktiv direkt nach Erstellung)
      // 2026-05-24 (vucko Fix): `.toUtc()` damit der ISO-String mit Z suffix
      // versendet wird. Sonst interpretiert Postgres die naive Time als UTC,
      // was bei Gerät in UTC+2 zu "in der Zukunft"-Eintrag führt → negative
      // "läuft seit X Min" im UI.
      final tripRow = await _client.from('trips').insert({
        'owner_id': userId,
        'title': title,
        'status': 'active',
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'stop_count': stops.length,
        'total_distance_km': totalDistanceKm,
        'total_duration_seconds': totalDurationSeconds,
        'default_style': defaultStyle,
        'default_avoid_highways': defaultAvoidHighways,
        if (groupId != null) 'group_id': groupId,
      }).select('id').single();
      final tripId = tripRow['id'] as String;
      // 2. Stops mit sequence (0=start, N-1=end)
      final stopRows = <Map<String, dynamic>>[];
      for (var i = 0; i < stops.length; i++) {
        final s = stops[i];
        stopRows.add({
          'trip_id': tripId,
          'sequence': i,
          'name': s.name,
          'lat': s.lat,
          'lng': s.lng,
          'stop_type': s.stopType,
          'planned_duration_minutes': 0,
        });
      }
      if (stopRows.isNotEmpty) {
        await _client.from('trip_stops').insert(stopRows);
      }
      return tripId;
    } catch (e) {
      // Logge im Debug
      return null;
    }
  }

  /// Markiert einen Stop als erreicht (actual_arrival = now).
  Future<void> markStopReached(String tripId, int sequence) async {
    await _client.from('trip_stops').update({
      'actual_arrival': DateTime.now().toUtc().toIso8601String(),
    }).eq('trip_id', tripId).eq('sequence', sequence);
  }

  /// Liefert die aktive ODER pausierte Trip des aktuellen Users, falls vorhanden.
  /// Genau ein Trip pro User kann "active" oder "paused" sein.
  /// Verwendung: Home-Screen Resume-Card.
  ///
  /// 2026-05-24 (vucko User-Wunsch): Resume-Card nur bei GROUP-Trips zeigen.
  /// Solo-Tours sind im Home-Screen nicht relevant — der User will den
  /// Resume-Hero-Slot nur sehen wenn er in einer aktiven Gruppen-Tour ist.
  Future<TripSummary?> activeOrPausedTripForCurrentUser({
    bool groupOnly = true,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      var query = _client
          .from('trips')
          .select(
            'id, title, status, paused_at, started_at, total_distance_km, '
            'total_duration_seconds, stop_count, default_style, group_id',
          )
          .eq('owner_id', userId)
          .inFilter('status', ['active', 'paused']);
      if (groupOnly) {
        query = query.not('group_id', 'is', null);
      }
      final result = await query
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (result == null) return null;
      return TripSummary.fromMap(result);
    } catch (_) {
      return null;
    }
  }

  /// Trip pausieren (z.B. Übernachtung).
  Future<void> pauseTrip(String tripId) async {
    await _client.from('trips').update({
      'status': 'paused',
      'paused_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', tripId);
  }

  /// Trip nach Pause weiterführen.
  Future<void> resumeTrip(String tripId) async {
    await _client.from('trips').update({
      'status': 'active',
      'resumed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', tripId);
  }

  /// Trip als abgeschlossen markieren.
  Future<void> completeTrip(String tripId) async {
    await _client.from('trips').update({
      'status': 'completed',
      'finished_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', tripId);
  }

  /// Lädt die Stops eines Trips in Reihenfolge.
  Future<List<TripStop>> stopsFor(String tripId) async {
    final rows = await _client
        .from('trip_stops')
        .select()
        .eq('trip_id', tripId)
        .order('sequence');
    return rows.map<TripStop>(TripStop.fromMap).toList();
  }

  /// Welcher Stop ist der nächste (noch nicht erreicht)?
  Future<TripStop?> nextStopFor(String tripId) async {
    final rows = await _client
        .from('trip_stops')
        .select()
        .eq('trip_id', tripId)
        .filter('actual_arrival', 'is', null)
        .order('sequence')
        .limit(1);
    if (rows.isEmpty) return null;
    return TripStop.fromMap(rows.first);
  }
}

class TripSummary {
  final String id;
  final String title;
  final String status; // 'active' | 'paused'
  final DateTime? pausedAt;
  final DateTime? startedAt;
  final double totalDistanceKm;
  final int totalDurationSeconds;
  final int stopCount;
  final String defaultStyle;

  TripSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.pausedAt,
    required this.startedAt,
    required this.totalDistanceKm,
    required this.totalDurationSeconds,
    required this.stopCount,
    required this.defaultStyle,
  });

  factory TripSummary.fromMap(Map<String, dynamic> m) => TripSummary(
    id: m['id'] as String,
    title: (m['title'] ?? '') as String,
    status: (m['status'] ?? 'paused') as String,
    pausedAt: m['paused_at'] == null
        ? null
        : DateTime.tryParse(m['paused_at'] as String),
    startedAt: m['started_at'] == null
        ? null
        : DateTime.tryParse(m['started_at'] as String),
    totalDistanceKm: ((m['total_distance_km'] ?? 0) as num).toDouble(),
    totalDurationSeconds: ((m['total_duration_seconds'] ?? 0) as num).toInt(),
    stopCount: ((m['stop_count'] ?? 0) as num).toInt(),
    defaultStyle: (m['default_style'] ?? 'Sport Mode') as String,
  );

  bool get isPaused => status == 'paused';
  bool get isActive => status == 'active';
}

class TripStop {
  final String id;
  final int sequence;
  final String name;
  final double lat;
  final double lng;
  final String stopType;
  final DateTime? plannedArrival;
  final DateTime? actualArrival;
  final int plannedDurationMinutes;
  final String? notes;

  TripStop({
    required this.id,
    required this.sequence,
    required this.name,
    required this.lat,
    required this.lng,
    required this.stopType,
    required this.plannedArrival,
    required this.actualArrival,
    required this.plannedDurationMinutes,
    required this.notes,
  });

  factory TripStop.fromMap(Map<String, dynamic> m) => TripStop(
    id: m['id'] as String,
    sequence: (m['sequence'] as num).toInt(),
    name: (m['name'] ?? '') as String,
    lat: (m['lat'] as num).toDouble(),
    lng: (m['lng'] as num).toDouble(),
    stopType: (m['stop_type'] ?? 'waypoint') as String,
    plannedArrival: m['planned_arrival'] == null
        ? null
        : DateTime.tryParse(m['planned_arrival'] as String),
    actualArrival: m['actual_arrival'] == null
        ? null
        : DateTime.tryParse(m['actual_arrival'] as String),
    plannedDurationMinutes: ((m['planned_duration_minutes'] ?? 0) as num).toInt(),
    notes: m['notes'] as String?,
  );
}
