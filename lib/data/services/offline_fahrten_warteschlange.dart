import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/gamification_service.dart';

/// 2026-08-26 (Nutzerbericht: „die App nimmt 50 % der Fahrten nicht wahr,
/// obwohl sie ueber 10 km lang waren — es koennte daran liegen, dass ich
/// nicht mit dem Internet verbunden war").
///
/// GEMESSENE URSACHE: Der Abschluss einer Fahrt schrieb die Zeile in
/// `user_drive_sessions` in EINEM Versuch. Schlug der fehl (kein Netz,
/// Funkloch im Tal, Zeitueberschreitung), warf `recordDriveSession` — und
/// `_recordDriveSessionForCurrentRoute` loeschte im `finally` trotzdem den
/// Fahrt-Schnappschuss. Damit war die letzte lokale Spur der Fahrt weg: kein
/// Kilometer, kein XP, kein zweiter Versuch. Genau das beschreibt der Bericht.
///
/// Diese Warteschlange ist das fehlende Netz darunter: Was nicht gebucht
/// werden konnte, liegt als JSON-Datei im Application-Support-Verzeichnis und
/// wird nachgetragen, sobald wieder eine Verbindung besteht.
///
/// KEINE DOPPELBUCHUNGEN. CLAUDE.md: „Eine gefahrene Fahrt = GENAU EINE Zeile"
/// in `user_drive_sessions` — sonst zaehlen Badges wie „Anzahl Fahrten"
/// doppelt. Der heikle Fall ist nicht das saubere Offline (da kommt nichts an),
/// sondern die WACKELIGE Verbindung: Der Insert laeuft serverseitig durch, die
/// Antwort geht auf dem Rueckweg verloren, der Client haelt die Fahrt fuer
/// ungebucht. Deshalb vergibt der Client die `id` der Zeile SELBST und schickt
/// beim Nachtragen dieselbe id noch einmal: Postgres lehnt sie dann mit
/// `23505` (unique_violation) ab, und genau diese Ablehnung ist der Beweis,
/// dass die Fahrt schon steht. Sie zaehlt hier als Erfolg.
///
/// Der Zeitstempel wird beim Anstellen eingefroren (`created_at`). Ohne ihn
/// truege eine Fahrt vom Samstag das Datum des Nachtragens am Montag — und
/// verschoebe Streak, Wochen-Chart und Monats-Rangliste.
class OfflineFahrtenWarteschlange {
  OfflineFahrtenWarteschlange._();

  static const String _dateiName = 'offene_fahrten_v1.json';

  /// Mehr als das hebt niemand mehr sinnvoll auf; die aeltesten fallen raus.
  /// Ein Deckel gehoert hierhin, weil die Datei sonst bei dauerhaft kaputtem
  /// Konto (z. B. abgelaufene Sitzung) unbegrenzt wuechse.
  static const int maxEintraege = 50;

  /// Wie viele Fahrten warten? Die Fahransicht liest das, um beim
  /// Fehlschlag „wird nachgetragen" statt „konnte nicht gespeichert werden"
  /// zu sagen.
  static final ValueNotifier<int> offeneFahrten = ValueNotifier<int>(0);

  static bool _traegtGeradeNach = false;
  static StreamSubscription<List<ConnectivityResult>>? _netzWache;
  static StreamSubscription<AuthState>? _anmeldeWache;

  static SupabaseClient get _db => Supabase.instance.client;

  static Future<File> _datei() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_dateiName');
  }

  /// Die wartenden Fahrten, aelteste zuerst. Eine unlesbare Datei liefert eine
  /// leere Liste — ein kaputter Cache darf den App-Start nicht kosten.
  static Future<List<Map<String, dynamic>>> lade() async {
    try {
      final datei = await _datei();
      if (!await datei.exists()) return const [];
      final roh = jsonDecode(await datei.readAsString());
      if (roh is! List) return const [];
      final eintraege = roh
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      offeneFahrten.value = eintraege.length;
      return eintraege;
    } catch (e) {
      debugPrint('[OfflineFahrten] Warteschlange nicht lesbar: $e');
      return const [];
    }
  }

  static Future<void> _schreibe(List<Map<String, dynamic>> eintraege) async {
    try {
      final datei = await _datei();
      if (eintraege.isEmpty) {
        if (await datei.exists()) await datei.delete();
        offeneFahrten.value = 0;
        return;
      }
      // Atomar wie beim Fahrt-Schnappschuss: erst .tmp, dann umbenennen. Ein
      // Abschuss mitten im Schreiben hinterlaesst sonst eine halbe Datei —
      // und die haette genau die Fahrten verschluckt, die sie retten soll.
      final tmp = File('${datei.path}.tmp');
      await tmp.writeAsString(jsonEncode(eintraege), flush: true);
      await tmp.rename(datei.path);
      offeneFahrten.value = eintraege.length;
    } catch (e) {
      debugPrint('[OfflineFahrten] Warteschlange nicht schreibbar: $e');
    }
  }

  /// Behaelt die JUENGSTEN [maxEintraege]. Wer 60 Fahrten offen hat, ist nicht
  /// kurz im Funkloch gewesen — dann sind die neuesten die interessanten.
  @visibleForTesting
  static List<Map<String, dynamic>> begrenze(
    List<Map<String, dynamic>> eintraege,
  ) {
    if (eintraege.length <= maxEintraege) return eintraege;
    return eintraege.sublist(eintraege.length - maxEintraege);
  }

  /// Stellt eine nicht gebuchte Fahrt an. [zeile] ist genau die Zeile, die an
  /// `user_drive_sessions` gehen sollte — inklusive der vom Client vergebenen
  /// `id`, ohne die das Nachtragen nicht doppelsicher waere.
  static Future<void> stelleAn(Map<String, dynamic> zeile) async {
    if (zeile['user_id'] == null || zeile['id'] == null) {
      debugPrint('[OfflineFahrten] Zeile ohne id/user_id — nicht angestellt.');
      return;
    }
    final gesichert = Map<String, dynamic>.from(zeile);
    // Fahrtdatum festhalten: sonst waere `created_at` der Tag des Nachtragens.
    gesichert['created_at'] ??= DateTime.now().toUtc().toIso8601String();

    final eintraege = List<Map<String, dynamic>>.from(await lade());
    // Dieselbe Fahrt nicht zweimal anstellen (zweiter Abschluss-Versuch).
    if (eintraege.any((e) => e['id'] == gesichert['id'])) return;
    eintraege.add(gesichert);
    await _schreibe(begrenze(eintraege));
    debugPrint('[OfflineFahrten] Fahrt gesichert, wird nachgetragen.');
  }

  /// Ist dieser Fehler der Beweis, dass die Fahrt schon gebucht IST?
  ///
  /// `23505` ist die Postgres-Verletzung eines eindeutigen Schluessels — bei
  /// unserer selbst vergebenen `id` also: die Zeile steht bereits. Alles
  /// andere (Netz, RLS, Server) ist ein echter Fehlschlag und muss liegen
  /// bleiben.
  @visibleForTesting
  static bool istSchonGebucht(Object fehler) =>
      fehler is PostgrestException && fehler.code == '23505';

  /// Traegt alles nach, was der angemeldete Nutzer offen hat.
  ///
  /// Gibt die Zahl der erledigten Fahrten zurueck. Fahrten eines ANDEREN
  /// Kontos bleiben unangetastet liegen (Geraetewechsel, zweiter Nutzer) —
  /// gebucht wird nur, wer selbst gefahren ist.
  static Future<int> trageNach() async {
    if (_traegtGeradeNach) return 0;
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return 0;

    _traegtGeradeNach = true;
    try {
      final eintraege = List<Map<String, dynamic>>.from(await lade());
      if (eintraege.isEmpty) return 0;

      final bleiben = <Map<String, dynamic>>[];
      var gebucht = 0;
      var netzKaputt = false;

      for (final zeile in eintraege) {
        if (zeile['user_id'] != uid || netzKaputt) {
          bleiben.add(zeile);
          continue;
        }
        try {
          await _db.from('user_drive_sessions').insert(zeile);
          gebucht++;
        } catch (e) {
          if (istSchonGebucht(e)) {
            // Der Insert war beim ersten Mal durchgelaufen, nur die Antwort
            // ging verloren. Nichts zu tun — und vor allem NICHT ein zweites
            // Mal buchen.
            debugPrint('[OfflineFahrten] Fahrt stand schon — Eintrag raus.');
            continue;
          }
          debugPrint('[OfflineFahrten] Nachtragen fehlgeschlagen: $e');
          // Der naechste Eintrag wuerde am selben Netz scheitern. Abbrechen
          // statt 50-mal in dieselbe Zeitueberschreitung zu laufen.
          netzKaputt = true;
          bleiben.add(zeile);
        }
      }

      await _schreibe(bleiben);
      if (gebucht > 0) {
        debugPrint('[OfflineFahrten] $gebucht Fahrt(en) nachgetragen.');
        // Ohne das stuenden die Kilometer zwar in `user_drive_sessions`, aber
        // `profiles.total_xp`, Level und Badges blieben bis zur naechsten
        // Fahrt auf dem alten Stand — der Fahrer saehe seine XP nicht.
        try {
          await GamificationService.calculateAndSync();
        } catch (e) {
          debugPrint('[OfflineFahrten] Abgleich nach dem Nachtragen: $e');
        }
      }
      return gebucht;
    } finally {
      _traegtGeradeNach = false;
    }
  }

  /// Startet die Beobachtung: einmal sofort, danach bei jeder neuen
  /// Verbindung und nach jeder Anmeldung.
  ///
  /// Gehoert in `main()` und nicht auf eine Seite: Wer nach der Fahrt die App
  /// schliesst und sie zu Hause im WLAN wieder oeffnet, landet auf der
  /// Startseite — die Fahransicht wird dabei nie gebaut.
  static void starteNetzWache() {
    unawaited(trageNach());

    _netzWache ??= Connectivity().onConnectivityChanged.listen((ergebnisse) {
      final online = ergebnisse.any((r) => r != ConnectivityResult.none);
      if (online) unawaited(trageNach());
    });

    // Nach dem Anmelden: Die Fahrten warten seit dem Funkloch, der Nutzer war
    // beim App-Start aber vielleicht noch gar nicht eingeloggt.
    _anmeldeWache ??= _db.auth.onAuthStateChange.listen((zustand) {
      if (zustand.event == AuthChangeEvent.signedIn ||
          zustand.event == AuthChangeEvent.tokenRefreshed) {
        unawaited(trageNach());
      }
    });
  }

  @visibleForTesting
  static Future<void> stoppeNetzWache() async {
    await _netzWache?.cancel();
    await _anmeldeWache?.cancel();
    _netzWache = null;
    _anmeldeWache = null;
  }
}
