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
    this.pausedSeconds = 0,
    this.rideId,
    this.plannedDistanceKm,
    this.remainingKm,
    this.remainingDurationSeconds,
    this.userId,
    this.verworfen = false,
  });

  /// v2 (2026-08-14, P2): `paused_seconds` kam dazu, damit Vor-Kill-Pausen
  /// beim Fortsetzen nicht als Fahrzeit zaehlen. fromJson liest v1 TOLERANT
  /// (fehlendes Feld = 0) — ein striktes Verwerfen wuerde beim App-Update
  /// genau die Fahrt wegwerfen, die diese Funktion retten soll.
  ///
  /// v3 (2026-08-16, Testfahrt T1/T2): `ride_id`, `planned_distance_km`,
  /// `remaining_km`, `remaining_duration_seconds`, `user_id`, `verworfen`.
  ///  * Die Home-Karte zeigte „4 km Route · 33 km gefahren", weil
  ///    [distanceKm] nach einem Reroute die REST-Route war. Jetzt gibt es die
  ///    geplante Gesamtlaenge und die Reststrecke (km + Sekunden) als eigene
  ///    Felder; [geometry] ist seither die NOCH OFFENE Strecke.
  ///  * [userId]: Nur der Fahrer selbst bekommt die Fahrt angeboten/gebucht —
  ///    nach einem Kontowechsel auf demselben Geraet nicht der andere.
  ///  * [verworfen]: „Verwerfen" gedrueckt (oder abgelaufen), aber die
  ///    Verbuchung des gefahrenen Teils ist noch nicht durch (offline) —
  ///    Karte nicht mehr zeigen, beim naechsten Start nachbuchen und loeschen
  ///    (siehe UnterbrocheneFahrtVerbuchung).
  static const int schemaVersion = 3;

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

  /// Summe aller Pausen vor dem Sichern, in Sekunden.
  final int pausedSeconds;

  /// Eindeutige Kennung dieser Fahrt (bleibt ueber Fortsetzen hinweg gleich).
  final String? rideId;

  /// Geplante Gesamtlaenge der Route beim Fahrtstart (vor Reroutes).
  final double? plannedDistanceKm;

  /// Reststrecke laut Navigation zum Zeitpunkt des Sicherns.
  final double? remainingKm;

  /// Restfahrzeit laut Navigation zum Zeitpunkt des Sicherns.
  final double? remainingDurationSeconds;

  /// Fahrer, dem die Fahrt gehoert (auth.uid). null bei alten Schnappschuessen.
  final String? userId;

  /// Fahrt wurde verworfen/ist abgelaufen — nur noch nachzubuchen, nicht
  /// mehr anzubieten.
  final bool verworfen;

  /// Geplante Laenge fuer die Anzeige — v3-Feld, sonst der alte Wert.
  double get anzeigeGeplantKm => plannedDistanceKm ?? distanceKm;

  /// Reststrecke fuer die Anzeige — v3-Feld, sonst geplant minus gefahren.
  double get anzeigeRestKm =>
      remainingKm ?? (anzeigeGeplantKm - drivenKm).clamp(0.0, anzeigeGeplantKm);

  /// Reine Fahrsekunden (ohne Pausen).
  int get fahrSekunden => (elapsedSeconds - pausedSeconds).clamp(0, elapsedSeconds);

  /// Anteil der geplanten Strecke, der schon gefahren ist (0..1+).
  double get fortschritt =>
      anzeigeGeplantKm > 0 ? drivenKm / anzeigeGeplantKm : 0.0;

  ActiveRideSnapshot copyWith({DateTime? savedAt, bool? verworfen}) {
    return ActiveRideSnapshot(
      savedAt: savedAt ?? this.savedAt,
      startedAt: startedAt,
      style: style,
      distanceKm: distanceKm,
      geometry: geometry,
      isRoundTrip: isRoundTrip,
      durationSeconds: durationSeconds,
      drivenKm: drivenKm,
      elapsedSeconds: elapsedSeconds,
      wasPaused: wasPaused,
      lastLat: lastLat,
      lastLng: lastLng,
      pausedSeconds: pausedSeconds,
      rideId: rideId,
      plannedDistanceKm: plannedDistanceKm,
      remainingKm: remainingKm,
      remainingDurationSeconds: remainingDurationSeconds,
      userId: userId,
      verworfen: verworfen ?? this.verworfen,
    );
  }

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
    'paused_seconds': pausedSeconds,
    if (rideId != null) 'ride_id': rideId,
    if (plannedDistanceKm != null) 'planned_distance_km': plannedDistanceKm,
    if (remainingKm != null) 'remaining_km': remainingKm,
    if (remainingDurationSeconds != null)
      'remaining_duration_seconds': remainingDurationSeconds,
    if (userId != null) 'user_id': userId,
    'verworfen': verworfen,
  };

  static ActiveRideSnapshot? fromJson(Map<String, dynamic> json) {
    // Aeltere Schemata tolerant lesen, nur ZUKUENFTIGE verwerfen.
    final version = (json['version'] as num?)?.toInt() ?? 0;
    if (version < 1 || version > schemaVersion) return null;
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
      pausedSeconds: (json['paused_seconds'] as num?)?.toInt() ?? 0,
      rideId: json['ride_id'] as String?,
      plannedDistanceKm: (json['planned_distance_km'] as num?)?.toDouble(),
      remainingKm: (json['remaining_km'] as num?)?.toDouble(),
      remainingDurationSeconds:
          (json['remaining_duration_seconds'] as num?)?.toDouble(),
      userId: json['user_id'] as String?,
      verworfen: json['verworfen'] == true,
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
    final sperre = _sperre;
    if (sperre != null) await sperre;
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
    final sperre = _sperre;
    if (sperre != null) await sperre;
    final last = _lastWriteAt;
    if (last != null && DateTime.now().difference(last) < _throttle) return;
    await save(snapshot);
  }

  /// Markiert den Schnappschuss als verworfen (Karte weg, Nachbuchung offen).
  static Future<void> markiereVerworfen() async {
    final s = await loadRoh();
    if (s == null || s.verworfen) return;
    await save(s.copyWith(verworfen: true));
  }

  /// Lädt den Snapshot; `null` wenn keiner existiert, er kaputt, verworfen
  /// oder zu alt ist (kaputte Dateien werden dabei aufgeräumt; alte und
  /// verworfene bleiben fuer die Nachbuchung liegen — siehe [loadRoh]).
  static Future<ActiveRideSnapshot?> load() async {
    final snapshot = await loadRoh();
    if (snapshot == null) return null;
    if (snapshot.verworfen || istAbgelaufen(snapshot)) return null;
    return snapshot;
  }

  static bool istAbgelaufen(ActiveRideSnapshot s) =>
      DateTime.now().difference(s.savedAt) > maxAge;

  /// 2026-08-16 (T2): Roh laden — auch verworfene/abgelaufene, damit die
  /// Home-Seite den gefahrenen Teil noch verbuchen kann, bevor sie loescht.
  static Future<ActiveRideSnapshot?> loadRoh() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      final snapshot = decoded is Map<String, dynamic>
          ? ActiveRideSnapshot.fromJson(decoded)
          : null;
      if (snapshot == null) {
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

  /// 2026-08-16 (T2): Bevor eine NEUE Fahrt den Schnappschuss ueberschreibt,
  /// darf ein liegen gebliebener (andere ride_id) noch verbucht werden.
  /// [verbuche] laeuft mit dem alten Schnappschuss; solange es laeuft, warten
  /// alle Schreibvorgaenge ([save]/[saveThrottled]) — sonst wuerde der erste
  /// GPS-Tick der neuen Fahrt den alten Stand wegschreiben, bevor er gelesen
  /// ist.
  static Future<void>? _sperre;

  static Future<void> vorNeuerFahrtSichern(
    String neueRideId,
    Future<void> Function(ActiveRideSnapshot alt) verbuche,
  ) async {
    if (_sperre != null) return;
    final lauf = () async {
      try {
        final alt = await loadRoh();
        if (alt == null || alt.rideId == neueRideId) return;
        await verbuche(alt);
      } catch (e) {
        debugPrint('[ActiveRideSnapshot] Altbuchung fehlgeschlagen: $e');
      }
    }();
    _sperre = lauf;
    try {
      await lauf;
    } finally {
      _sperre = null;
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
