import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 2026-07-06 (vucko Fahrt-Resume): Lokaler Snapshot der AKTIVEN Solo-Fahrt.
///
/// Root Cause des „Strecke weg nach App-Kill"-Bugs: Die laufende Fahrt lebte
/// NUR im RAM (cruise_mode_page-State). `user_drive_sessions` wird erst beim
/// Fahrt-ENDE geschrieben, `routes` nur beim expliziten Speichern. Wenn iOS
/// die pausierte App im Hintergrund beendet, existiert also NIRGENDS eine
/// Spur der Fahrt — nicht im Archiv, nicht bei den Strecken, und neu
/// generieren geht von unterwegs auch nicht mehr.
///
/// Dieser Service persistiert die laufende Fahrt als JSON-Datei im
/// Application-Support-Verzeichnis:
///  * beim Fahrtstart,
///  * bei jedem Pause-Tap,
///  * beim App-Backgrounding,
///  * gedrosselt (alle [_throttle]) während der Fahrt.
///
/// Beim nächsten App-Start bietet der Homescreen „Fahrt fortsetzen" an —
/// der Snapshot wird als [SavedRoute]-artige Route über den bestehenden
/// `CruiseModePage.pendingRoute`-Pfad geladen. Der existierende
/// joinNearestForward-Mechanismus schließt dabei automatisch am nächsten
/// Routenpunkt an, auch wenn der User inzwischen weitergefahren ist.
///
/// Gruppen-Fahrten (Lobby-Rejoin) und Trips (trips-Tabelle) haben eigene
/// Resume-Mechanismen und werden hier bewusst NICHT gespeichert.
class ActiveRideSnapshot {
  const ActiveRideSnapshot({
    required this.savedAt,
    required this.startedAt,
    required this.style,
    required this.distanceKm,
    required this.geometry,
    required this.isRoundTrip,
    this.durationSeconds,
    this.drivenKm = 0,
    this.elapsedSeconds = 0,
    this.wasPaused = false,
    this.lastLat,
    this.lastLng,
  });

  static const int schemaVersion = 1;

  final DateTime savedAt;
  final DateTime startedAt;
  final String style;
  final double distanceKm;

  /// GeoJSON-LineString (`{type, coordinates}`) — [longitude, latitude].
  final Map<String, dynamic> geometry;
  final bool isRoundTrip;
  final double? durationSeconds;
  final double drivenKm;
  final int elapsedSeconds;
  final bool wasPaused;
  final double? lastLat;
  final double? lastLng;

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'saved_at': savedAt.toIso8601String(),
    'started_at': startedAt.toIso8601String(),
    'style': style,
    'distance_km': distanceKm,
    'geometry': geometry,
    'is_round_trip': isRoundTrip,
    if (durationSeconds != null) 'duration_seconds': durationSeconds,
    'driven_km': drivenKm,
    'elapsed_seconds': elapsedSeconds,
    'was_paused': wasPaused,
    if (lastLat != null) 'last_lat': lastLat,
    if (lastLng != null) 'last_lng': lastLng,
  };

  static ActiveRideSnapshot? fromJson(Map<String, dynamic> json) {
    if ((json['version'] as num?)?.toInt() != schemaVersion) return null;
    final savedAt = DateTime.tryParse(json['saved_at'] as String? ?? '');
    final startedAt = DateTime.tryParse(json['started_at'] as String? ?? '');
    final geometry = json['geometry'];
    final distanceKm = (json['distance_km'] as num?)?.toDouble();
    if (savedAt == null ||
        startedAt == null ||
        geometry is! Map<String, dynamic> ||
        distanceKm == null) {
      return null;
    }
    final coords = geometry['coordinates'];
    if (coords is! List || coords.length < 2) return null;
    return ActiveRideSnapshot(
      savedAt: savedAt,
      startedAt: startedAt,
      style: json['style'] as String? ?? 'Entdecker',
      distanceKm: distanceKm,
      geometry: geometry,
      isRoundTrip: json['is_round_trip'] == true,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
      drivenKm: (json['driven_km'] as num?)?.toDouble() ?? 0,
      elapsedSeconds: (json['elapsed_seconds'] as num?)?.toInt() ?? 0,
      wasPaused: json['was_paused'] == true,
      lastLat: (json['last_lat'] as num?)?.toDouble(),
      lastLng: (json['last_lng'] as num?)?.toDouble(),
    );
  }
}

class ActiveRideSnapshotService {
  ActiveRideSnapshotService._();

  static const String _fileName = 'active_ride_snapshot.json';

  /// Snapshots älter als das gelten als verwaist (User will die Fahrt vom
  /// Vortag i.d.R. nicht mehr fortsetzen) und werden beim Laden verworfen.
  static const Duration maxAge = Duration(hours: 48);

  /// Mindestabstand zwischen zwei gedrosselten Schreibvorgängen.
  static const Duration _throttle = Duration(seconds: 20);

  static DateTime? _lastWriteAt;
  static bool _writing = false;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Persistiert den Snapshot sofort (Pause, Backgrounding, Fahrtstart).
  static Future<void> save(ActiveRideSnapshot snapshot) async {
    if (_writing) return; // laufenden Write nicht stapeln
    _writing = true;
    try {
      final file = await _file();
      // Atomar: erst tmp schreiben, dann umbenennen — ein Kill mitten im
      // Write hinterlässt so nie eine halbe JSON-Datei.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
      await tmp.rename(file.path);
      _lastWriteAt = DateTime.now();
    } catch (e) {
      debugPrint('[ActiveRideSnapshot] save failed: $e');
    } finally {
      _writing = false;
    }
  }

  /// Persistiert höchstens alle [_throttle] — für den Positions-Callback.
  static Future<void> saveThrottled(ActiveRideSnapshot snapshot) async {
    final last = _lastWriteAt;
    if (last != null && DateTime.now().difference(last) < _throttle) return;
    await save(snapshot);
  }

  /// Lädt den Snapshot; `null` wenn keiner existiert, er kaputt oder zu alt
  /// ist (kaputte/alte Dateien werden dabei aufgeräumt).
  static Future<ActiveRideSnapshot?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      final snapshot = decoded is Map<String, dynamic>
          ? ActiveRideSnapshot.fromJson(decoded)
          : null;
      if (snapshot == null ||
          DateTime.now().difference(snapshot.savedAt) > maxAge) {
        await clear();
        return null;
      }
      return snapshot;
    } catch (e) {
      debugPrint('[ActiveRideSnapshot] load failed: $e');
      await clear();
      return null;
    }
  }

  /// Entfernt den Snapshot (reguläres Fahrt-Ende, Verwerfen, Ablauf).
  static Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        await file.delete();
      }
      _lastWriteAt = null;
    } catch (e) {
      debugPrint('[ActiveRideSnapshot] clear failed: $e');
    }
  }
}
