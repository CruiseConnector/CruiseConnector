import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart' as mb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/offline_map_service.dart';

/// Baut den MapLibre-Style und verwaltet die OFFLINE-DACH-PMTiles.
///
/// Idee: Die Karte rendert standardmäßig aus den remote R2-PMTiles (MapLibre
/// cached geladene Kacheln automatisch im Ambient-Cache → besuchte Gebiete sind
/// danach offline verfügbar). Zusätzlich kann der ganze DACH-Raum als eine
/// PMTiles-Datei lokal aufs Gerät geladen werden; dann zeigt der Style auf die
/// LOKALE Datei → komplett offline, alle Zoomstufen, keine Tile-Probleme.
///
/// MapLibre Native (iOS-SDK ≥6.14) liest `pmtiles://<url>` sowohl remote als auch
/// für lokale Dateien (`pmtiles://file://…`).
// 2026-08-28 (Fehler 11, Vucko): "ganz wichtig, dass der Nutzer die Option
// hat gleich am Anfang, wenn er die App installiert, dass nichts ohne seiner
// Zustimmung gedownloadet wird." Deshalb gibt es jetzt drei Stellungen —
// die dritte heisst: gar nicht.
enum MapAutoDownloadPolicy { wifiOnly, wifiAndMobile, aus }

class MapStyleService {
  MapStyleService._();
  static final MapStyleService instance = MapStyleService._();

  static const String _styleAsset = 'assets/map/cruise_dark.json';

  /// Die remote PMTiles-Quelle, wie sie im Asset-Style steht (wird beim
  /// Offline-Modus durch die lokale Datei ersetzt).
  // 2026-06-05 (vucko): Auf den eigenen CDN (tiles.cruiseconnector.at) migriert —
  // konsistent mit OfflineMapService + CarPlay. r2.dev drosselt Range-Requests auf
  // der 5GB-Datei (PMTiles-Header/Tiles laden über Ranges). WICHTIG: remoteDachSource
  // MUSS byte-genau mit der `url` in assets/map/cruise_dark.json übereinstimmen,
  // sonst greift der Offline-Swap (replaceAll) in buildStyleString nicht.
  static const String remoteDachSource =
      'pmtiles://https://tiles.cruiseconnector.at/dach.pmtiles';
  static const String _downloadUrl =
      'https://tiles.cruiseconnector.at/dach.pmtiles';

  /// Optionaler Remote-Style auf Cloudflare (vom User hochgeladen). Wenn
  /// vorhanden, wird er bevorzugt → Karten-Look ohne App-Release änderbar
  /// (wie Mapbox-gehostete Styles). Fehlt er (404/kein Netz), nutzt die App den
  /// gebündelten Style. Upload: `rclone copy assets/map/cruise_dark.json r2:<bucket>/`.
  static const String _remoteStyleUrl =
      'https://tiles.cruiseconnector.at/cruise_dark.json';

  static const String _localFileName = 'dach.pmtiles';
  static const String _autoDownloadPolicyKey =
      'offline_map_auto_download_policy_v1';
  static const String _autoDownloadPromptSeenKey =
      'offline_map_auto_download_prompt_v1_seen';

  /// Mindestgröße, damit eine abgebrochene/teilweise Datei NICHT als „fertig"
  /// gilt (die echte DACH-Datei ist mehrere GB groß).
  static const int _minValidBytes = 200 * 1024 * 1024; // 200 MB

  bool _downloadInProgress = false;
  bool get isDownloading => _downloadInProgress;
  Timer? _autoDownloadTimer;
  bool _autoBootstrapRunning = false;
  MapAutoDownloadPolicy _autoDownloadPolicy = MapAutoDownloadPolicy.wifiOnly;
  bool _settingsLoaded = false;

  MapAutoDownloadPolicy get autoDownloadPolicy => _autoDownloadPolicy;

  Future<void> loadAutoDownloadSettings() async {
    if (_settingsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_autoDownloadPolicyKey);
    _autoDownloadPolicy = MapAutoDownloadPolicy.values.firstWhere(
      (p) => p.name == raw,
      orElse: () => MapAutoDownloadPolicy.wifiOnly,
    );
    _settingsLoaded = true;
  }

  Future<void> setAutoDownloadPolicy(MapAutoDownloadPolicy policy) async {
    _autoDownloadPolicy = policy;
    _settingsLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_autoDownloadPolicyKey, policy.name);
  }

  Future<bool> hasSeenAutoDownloadPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoDownloadPromptSeenKey) ?? false;
  }

  Future<void> markAutoDownloadPromptSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoDownloadPromptSeenKey, true);
  }

  /// Lädt den DACH-Raum automatisch offline (User-Wunsch „automatisch"). NUR
  /// über WLAN (kein Mobilfunk-Volumen). Auf `false` setzen, um den
  /// automatischen ~mehrere-GB-Download zu deaktivieren (manuell via
  /// [downloadDach] bleibt möglich).
  // 2026-06-05 (vucko): DACH automatisch offline laden (expliziter User-Wunsch).
  // SICHER, weil: NUR über WLAN (kein Mobilfunk), EINMALIG (isDachDownloaded-
  // Guard), resumierbar (.part), und scheitert GRACEFUL — bei vollem Speicher/
  // Abbruch wirft der Stream → catch → die unfertige .part wird NIE zu
  // dach.pmtiles umbenannt → die Karte nutzt nie eine halbe Datei (kein Crash,
  // kein korrupter Zustand). Der Crash vorher kam von der Offstage-Karte, NICHT
  // vom Download. Auf false setzen, um den automatischen Download abzuschalten.
  // 2026-06-05 (vucko Task #8): AN — User will den DACH-Raum KOMPLETT offline
  // („nicht unscharfe/fehlende Orte weil es laden muss"). Sobald die lokale
  // dach.pmtiles da ist, rendert MapLibre ganz DACH OHNE Netz (kein Lade-Blur).
  // Sicher: NUR WLAN, EINMALIG (isDachDownloaded-Guard), resumierbar (.part),
  // graceful (Abbruch/Speicher-voll → keine halbe Datei wird genutzt, kein
  // Crash). Auf false, falls der ~mehrere-GB-Download nicht gewünscht ist.
  // 2026-06-05 (vucko Crash-Fix #2): WIEDER AN. Die ECHTE SIGABRT-Ursache war
  // NICHT der Download, sondern addSource/addLineLayer vor dem ersten Frame
  // (Redundant-Layer-Throw aus dem mbgl-Core) — gefixt in cruise_maplibre_map.dart
  // (existenz-geprüft + erst nach erstem Frame) und on-device 18/18 + Bg/Fg
  // verifiziert. Der frühere AUS-Schalter (d12d9d5) basierte auf der falschen
  // Download-Verstärker-Hypothese. Download bleibt sicher: NUR WLAN, EINMALIG
  // (isDachDownloaded-Guard), resumierbar (.part), graceful (Abbruch/Speicher-voll
  // → keine halbe Datei wird genutzt), und läuft erst 10s nach App-Start
  // (home_page Prewarm-Delay) → kollidiert nicht mehr mit dem Karten-Öffnen.
  static const bool autoDownloadEnabled = true;

  /// Garantiert, dass Nutzer ohne lokale DACH-Karte automatisch in den
  /// Hintergrund-Download laufen. Mehrere Einstiegspunkte (App-Start, Home,
  /// erste MapLibre-Karte) dürfen diese Methode aufrufen; sie dedupliziert Timer
  /// und laufende Checks. Ein sofortiger Aufruf darf einen verzögerten App-Start-
  /// Timer vorziehen, damit die Karte nicht auf den Home-Prewarm angewiesen ist.
  void ensureAutoDownloadScheduled({
    Duration delay = Duration.zero,
    String reason = 'startup',
  }) {
    if (!autoDownloadEnabled || kIsWeb) return;
    if (_autoBootstrapRunning || _downloadInProgress) return;
    if (_autoDownloadTimer != null) {
      if (delay == Duration.zero) {
        _autoDownloadTimer?.cancel();
        _autoDownloadTimer = null;
      } else {
        return;
      }
    }

    void start() {
      _autoDownloadTimer = null;
      unawaited(_runAutoDownloadBootstrap(reason));
    }

    if (delay == Duration.zero) {
      start();
    } else {
      _autoDownloadTimer = Timer(delay, start);
    }
  }

  Future<void> _runAutoDownloadBootstrap(String reason) async {
    if (_autoBootstrapRunning || _downloadInProgress) return;
    _autoBootstrapRunning = true;
    try {
      debugPrint('[MapStyle] Auto-DACH-Bootstrap: $reason');
      await verifyLocalDachIntegrityOnce();
      await maybeAutoDownloadDach();
    } catch (e) {
      debugPrint('[MapStyle] Auto-DACH-Bootstrap fehlgeschlagen: $e');
    } finally {
      _autoBootstrapRunning = false;
    }
  }

  /// Startet den DACH-Offline-Download automatisch, wenn sinnvoll: aktiviert,
  /// noch nicht geladen, nicht schon laufend, und auf WLAN. Fire-and-forget —
  /// blockiert nichts. MapLibre cached parallel ohnehin jede geladene Kachel.
  Future<void> maybeAutoDownloadDach() async {
    if (!autoDownloadEnabled || _downloadInProgress) return;
    try {
      await loadAutoDownloadSettings();
      if (await isDachDownloaded()) return;
      // 2026-08-28 (Fehler 11): OHNE beantwortete Zustimmungsfrage laedt der
      // Automatik-Pfad NICHTS — egal, von welchem Einstiegspunkt er kommt
      // (App-Start, Home-Prewarm, erste Karte). Das Blatt kommt beim ersten
      // Oeffnen der Startseite; erst die dort gespeicherte Wahl schaltet
      // frei. Der manuelle Download in den Einstellungen bleibt unberuehrt,
      // ein Fingertipp dort IST die Zustimmung.
      if (!await hasSeenAutoDownloadPrompt()) {
        debugPrint(
          '[MapStyle] Auto-DACH-Download wartet auf die Zustimmungsfrage.',
        );
        return;
      }
      if (_autoDownloadPolicy == MapAutoDownloadPolicy.aus) {
        debugPrint('[MapStyle] Auto-DACH-Download ist abgeschaltet (aus).');
        return;
      }
      final conn = await Connectivity().checkConnectivity();
      final hasWifi = conn.contains(ConnectivityResult.wifi);
      final hasNetwork = conn.any(
        (result) => result != ConnectivityResult.none,
      );
      final canDownload = _autoDownloadPolicy == MapAutoDownloadPolicy.wifiOnly
          ? hasWifi
          : hasNetwork;
      if (!canDownload) {
        debugPrint(
          _autoDownloadPolicy == MapAutoDownloadPolicy.wifiOnly
              ? '[MapStyle] Auto-DACH-Download übersprungen (kein WLAN).'
              : '[MapStyle] Auto-DACH-Download übersprungen (offline).',
        );
        return;
      }
    } catch (_) {
      return;
    }
    debugPrint('[MapStyle] Auto-DACH-Offline-Download startet…');
    unawaited(
      downloadDach(
        onProgress: (received, total) {
          // Grob alle ~100 MB loggen.
          if (received % (100 * 1024 * 1024) < (2 * 1024 * 1024)) {
            final mb = (received / 1024 / 1024).round();
            final totalMb = total > 0 ? (total / 1024 / 1024).round() : -1;
            debugPrint(
              '[MapStyle] DACH offline: $mb${totalMb > 0 ? '/$totalMb' : ''} MB',
            );
          }
        },
      ),
    );
  }

  Future<File> _localFile() async {
    final dir = await getApplicationSupportDirectory();
    final mapDir = Directory('${dir.path}/offline_map');
    if (!await mapDir.exists()) {
      await mapDir.create(recursive: true);
    }
    return File('${mapDir.path}/$_localFileName');
  }

  /// 2026-06-11 (vucko Karten-Selbstheilung): EINMALIGER Integritäts-Check der
  /// lokalen dach.pmtiles. Problem: [isDachDownloaded] prüft nur die GRÖSSE —
  /// eine korrupt heruntergeladene Datei (Resume-Lücke, Server-Wechsel während
  /// des Downloads, defekter Block) gilt als „fertig", die Karte rendert dann
  /// dauerhaft fehlerhaft bzw. fällt auf den alten Mapbox-Raster-Look zurück.
  /// Heilung: (1) PMTiles-Magic-Header prüfen, (2) wenn Netz da: lokale Größe
  /// gegen die Server-Datei (HEAD Content-Length) — kleiner = unvollstaendig.
  /// Bei Defekt wird die Datei gelöscht und der bewaehrte Auto-Download
  /// (NUR WLAN, resumierbar, graceful) laedt sie automatisch EINMALIG neu.
  /// Das Erledigt-Flag wird nur gesetzt, wenn die Prüfung lief — so heilt ein
  /// Offline-Start sich beim nächsten Start mit Netz selbst.
  Future<void> verifyLocalDachIntegrityOnce() async {
    const flagKey = 'dach_pmtiles_integrity_v1_done';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(flagKey) == true) return;
      final f = await _localFile();
      if (!await f.exists()) {
        // Nichts zu heilen — der normale Download-Pfad übernimmt.
        await prefs.setBool(flagKey, true);
        return;
      }
      final localLen = await f.length();
      var healthy = localLen >= _minValidBytes;
      // PMTiles-v3-Dateien beginnen mit dem ASCII-Magic "PMTiles".
      if (healthy) {
        final raf = await f.open();
        try {
          final head = await raf.read(7);
          healthy = head.length == 7 && String.fromCharCodes(head) == 'PMTiles';
        } finally {
          await raf.close();
        }
      }
      var remoteChecked = false;
      if (healthy) {
        try {
          final res = await http
              .head(Uri.parse(_downloadUrl))
              .timeout(const Duration(seconds: 5));
          final remoteLen =
              int.tryParse(res.headers['content-length'] ?? '') ?? 0;
          if (res.statusCode >= 200 && res.statusCode < 300 && remoteLen > 0) {
            remoteChecked = true;
            // Kleiner als der Server = unvollstaendiger Download.
            if (localLen < remoteLen) healthy = false;
          }
        } catch (_) {
          // Kein Netz: Magic-+Größen-Check müssen reichen; Flag bleibt
          // ungesetzt, damit der nächste Start mit Netz voll prüft.
        }
      }
      if (!healthy) {
        await f.delete();
        debugPrint(
          '[MapStyle] Integritaets-Check: defekte/unvollstaendige dach.pmtiles '
          'gelöscht — automatischer Neu-Download startet (WLAN)',
        );
        // Kein eigener Download-Anstoss: der Pre-Warm ruft direkt nach diesem
        // Check maybeAutoDownloadDach() — ein zweiter Aufruf hier erzeugte
        // einen Doppel-Download (Live-Test-Befund).
        await prefs.setBool(flagKey, true);
      } else if (remoteChecked) {
        await prefs.setBool(flagKey, true);
      }
    } catch (e) {
      debugPrint('[MapStyle] Integritaets-Check übersprungen: $e');
    }
  }

  /// Liegt die vollständige DACH-PMTiles lokal vor?
  Future<bool> isDachDownloaded() async {
    try {
      final f = await _localFile();
      return await f.exists() && (await f.length()) >= _minValidBytes;
    } catch (_) {
      return false;
    }
  }

  /// Baut den Style-JSON-String. Quelle = LOKALE PMTiles wenn vorhanden
  /// (offline), sonst remote von R2.
  Future<String> buildStyleString({String asset = _styleAsset}) async {
    final raw = await _loadBaseStyle(asset);
    try {
      if (await isDachDownloaded()) {
        final f = await _localFile();
        final localSource = 'pmtiles://${Uri.file(f.path)}';
        debugPrint('[MapStyle] OFFLINE: lokale PMTiles $localSource');
        return raw.replaceAll(remoteDachSource, localSource);
      }
    } catch (e) {
      debugPrint('[MapStyle] lokale PMTiles-Prüfung fehlgeschlagen: $e');
    }
    return raw;
  }

  /// Basis-Style: bevorzugt den von Cloudflare gespiegelten (remote
  /// aktualisierbaren) Style aus dem lokalen Cache, sonst das App-Bundle. Liest
  /// NUR lokal (kein Netz-Block beim Kartenstart) — der Remote-Style wird per
  /// [refreshRemoteStyle] im Hintergrund aktualisiert.
  Future<String> _loadBaseStyle(String asset) async {
    // 2026-06-05 (vucko): Das BUNDLE ist die Single Source of Truth. Der
    // Remote-Cache-Vorzug (df8a6d1) ist raus — er machte Style-Änderungen
    // unsichtbar (App renderte die gecachte R2-Datei) und war Race-/Crash-
    // anfällig. Bundle ist zudem besser für Offline (immer da, sofort).
    return rootBundle.loadString(asset);
  }

  Future<File> _cachedRemoteStyleFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/offline_map/cruise_dark.remote.json');
  }

  /// Holt den Style von Cloudflare (falls dort hochgeladen) und cached ihn
  /// lokal → wird beim nächsten Kartenstart verwendet. Fehlt die Datei auf R2
  /// (404) oder kein Netz, bleibt es beim Bundle. Hintergrund, blockiert nichts.
  Future<void> refreshRemoteStyle() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(_remoteStyleUrl));
      final resp = await req.close();
      if (resp.statusCode != HttpStatus.ok) return;
      final body = await resp.transform(const Utf8Decoder()).join();
      // Plausibilitätscheck: gültiges Style-JSON?
      if (!body.trimLeft().startsWith('{') || !body.contains('"layers"')) {
        return;
      }
      json.decode(body); // wirft bei kaputtem JSON → Bundle bleibt
      final cached = await _cachedRemoteStyleFile();
      await cached.parent.create(recursive: true);
      // Atomar schreiben (tmp + rename) → ein gleichzeitig lesender Kartenstart
      // sieht NIE eine halbe Datei (sonst MapLibre-Abort, s. _loadBaseStyle).
      final tmp = File('${cached.path}.tmp');
      await tmp.writeAsString(body);
      await tmp.rename(cached.path);
      debugPrint('[MapStyle] Remote-Style von Cloudflare aktualisiert.');
    } catch (_) {
      // Kein Netz / 404 / kaputt → Bundle bleibt.
    } finally {
      client.close();
    }
  }

  /// Lädt die DACH-PMTiles (ganz DACH offline) nach lokal — resumierbar über
  /// eine `.part`-Datei. `onProgress(received, total)` für UI-Fortschritt.
  ///
  /// total ist −1, falls der Server keine Content-Length liefert.
  Future<bool> downloadDach({
    void Function(int received, int total)? onProgress,
  }) async {
    if (_downloadInProgress) return false;
    // 2026-06-11 (vucko): Flag SOFORT setzen — vorher lag ein await zwischen
    // Guard und Set, zwei zeitgleiche Aufrufer (Integritaets-Check + Pre-Warm)
    // konnten BEIDE durchrutschen und parallel in dieselbe .part schreiben.
    _downloadInProgress = true;
    if (await isDachDownloaded()) {
      _downloadInProgress = false;
      return true;
    }
    final target = await _localFile();
    final part = File('${target.path}.part');
    final client = HttpClient();
    try {
      // Resume: bereits geladene Bytes via Range-Request fortsetzen.
      var existing = 0;
      if (await part.exists()) {
        existing = await part.length();
      }
      final req = await client.getUrl(Uri.parse(_downloadUrl));
      if (existing > 0) {
        req.headers.add(HttpHeaders.rangeHeader, 'bytes=$existing-');
      }
      final resp = await req.close();
      if (resp.statusCode != HttpStatus.ok &&
          resp.statusCode != HttpStatus.partialContent) {
        debugPrint('[MapStyle] Download HTTP ${resp.statusCode}');
        return false;
      }
      final total = resp.contentLength < 0
          ? -1
          : resp.contentLength +
                (resp.statusCode == HttpStatus.partialContent ? existing : 0);
      var received = resp.statusCode == HttpStatus.partialContent
          ? existing
          : 0;
      final sink = part.openWrite(
        mode: resp.statusCode == HttpStatus.partialContent
            ? FileMode.append
            : FileMode.write,
      );
      await for (final chunk in resp) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.close();
      await part.rename(target.path);
      debugPrint('[MapStyle] DACH offline geladen: ${target.path}');
      return true;
    } catch (e) {
      debugPrint('[MapStyle] DACH-Download fehlgeschlagen: $e');
      return false;
    } finally {
      client.close();
      _downloadInProgress = false;
    }
  }

  /// Wie viel Platz die Offlinekarte auf dem Geraet belegt, in Bytes.
  ///
  /// 2026-08-28 (Abnahmefund zu Fehler 11): Zaehlt die fertige Datei UND eine
  /// angefangene `.part` mit. Genau die war das Problem: wer bei halb
  /// geladener Karte „Keine Offlinekarte" waehlte, behielt mehrere Gigabyte,
  /// die nie wieder angefasst wurden, und erfuhr nichts davon.
  Future<int> belegterSpeicherBytes() async {
    var summe = 0;
    try {
      final f = await _localFile();
      if (await f.exists()) summe += await f.length();
      final part = File('${f.path}.part');
      if (await part.exists()) summe += await part.length();
    } catch (e) {
      debugPrint('[MapStyle] Belegten Speicher nicht ermittelbar: $e');
    }
    return summe;
  }

  /// Löscht die lokale Offline-Datei (Speicher freigeben).
  Future<void> deleteOffline() async {
    try {
      final f = await _localFile();
      if (await f.exists()) await f.delete();
      final part = File('${f.path}.part');
      if (await part.exists()) await part.delete();
    } catch (_) {}
  }

  // 2026-06-25 (vucko Süd-Offline): Trip-Modus außerhalb DACH soll die Strecke
  // OFFLINE verfügbar haben. DACH ist als ganze dach.pmtiles schon lokal; für
  // den Süden (eu.pmtiles, remote) lädt MapLibre besuchte Kacheln in den
  // Ambient-Cache — zusätzlich pre-cachen wir hier den Routen-KORRIDOR als
  // MapLibre-Offline-Region, damit er auch OHNE Vorab-Fahren offline da ist.
  bool _routeRegionInFlight = false;

  /// Lädt den Strecken-Korridor EINER Route als MapLibre-Offline-Region — NUR
  /// wenn die Route DACH verlässt (drinnen deckt die lokale dach.pmtiles ab).
  /// Best-effort: WLAN-gegated (kein Mobilvolumen), gedeckelter Zoom, eigener
  /// Pfad mit try/catch → kann die Karte NIE kaputtmachen.
  Future<void> downloadRouteOfflineRegion(
    List<List<double>> routeCoordinates, {
    int minZoom = 6,
    int maxZoom = 13,
  }) async {
    if (kIsWeb || routeCoordinates.length < 2 || _routeRegionInFlight) return;
    _routeRegionInFlight = true;
    try {
      await loadAutoDownloadSettings();
      final conn = await Connectivity().checkConnectivity();
      final online = conn.any((r) => r != ConnectivityResult.none);
      if (!online) return;
      final hasWifi = conn.contains(ConnectivityResult.wifi);
      if (_autoDownloadPolicy == MapAutoDownloadPolicy.wifiOnly && !hasWifi) {
        return;
      }

      var minLat = routeCoordinates.first[1], maxLat = routeCoordinates.first[1];
      var minLng = routeCoordinates.first[0], maxLng = routeCoordinates.first[0];
      for (final c in routeCoordinates) {
        if (c.length < 2) continue;
        minLng = math.min(minLng, c[0]);
        maxLng = math.max(maxLng, c[0]);
        minLat = math.min(minLat, c[1]);
        maxLat = math.max(maxLat, c[1]);
      }
      // Nur wenn die Route DACH (teilweise) verlässt — sonst ist alles schon
      // über die lokale dach.pmtiles offline.
      final outsideDach = minLat < OfflineMapService.dachBboxSouthLat ||
          maxLat > OfflineMapService.dachBboxNorthLat ||
          minLng < OfflineMapService.dachBboxWestLng ||
          maxLng > OfflineMapService.dachBboxEastLng;
      if (!outsideDach) return;

      final padLat = (maxLat - minLat) * 0.06 + 0.02;
      final padLng = (maxLng - minLng) * 0.06 + 0.02;
      final bounds = mb.LatLngBounds(
        southwest: mb.LatLng(minLat - padLat, minLng - padLng),
        northeast: mb.LatLng(maxLat + padLat, maxLng + padLng),
      );

      await mb.setOfflineTileCountLimit(250000);
      await mb.downloadOfflineRegion(
        mb.OfflineRegionDefinition(
          bounds: bounds,
          mapStyleUrl: _remoteStyleUrl,
          minZoom: minZoom.toDouble(),
          maxZoom: maxZoom.toDouble(),
        ),
        metadata: const {'type': 'route-corridor'},
      );
      debugPrint('[MapStyle] Offline-Region für Route außerhalb DACH geladen.');
    } catch (e) {
      debugPrint('[MapStyle] Offline-Region-Download fehlgeschlagen (silent): $e');
    } finally {
      _routeRegionInFlight = false;
    }
  }
}
