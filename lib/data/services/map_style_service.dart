import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

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
class MapStyleService {
  MapStyleService._();
  static final MapStyleService instance = MapStyleService._();

  static const String _styleAsset = 'assets/map/cruise_dark.json';

  /// Die remote PMTiles-Quelle, wie sie im Asset-Style steht (wird beim
  /// Offline-Modus durch die lokale Datei ersetzt).
  static const String remoteDachSource =
      'pmtiles://https://pub-0535dd4f86054de1820907b6f06bf17c.r2.dev/dach.pmtiles';
  static const String _downloadUrl =
      'https://pub-0535dd4f86054de1820907b6f06bf17c.r2.dev/dach.pmtiles';

  /// Optionaler Remote-Style auf Cloudflare (vom User hochgeladen). Wenn
  /// vorhanden, wird er bevorzugt → Karten-Look ohne App-Release änderbar
  /// (wie Mapbox-gehostete Styles). Fehlt er (404/kein Netz), nutzt die App den
  /// gebündelten Style. Upload: `rclone copy assets/map/cruise_dark.json r2:<bucket>/`.
  static const String _remoteStyleUrl =
      'https://tiles.cruiseconnector.at/cruise_dark.json';

  static const String _localFileName = 'dach.pmtiles';

  /// Mindestgröße, damit eine abgebrochene/teilweise Datei NICHT als „fertig"
  /// gilt (die echte DACH-Datei ist mehrere GB groß).
  static const int _minValidBytes = 200 * 1024 * 1024; // 200 MB

  bool _downloadInProgress = false;
  bool get isDownloading => _downloadInProgress;

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
  static const bool autoDownloadEnabled = true;

  /// Startet den DACH-Offline-Download automatisch, wenn sinnvoll: aktiviert,
  /// noch nicht geladen, nicht schon laufend, und auf WLAN. Fire-and-forget —
  /// blockiert nichts. MapLibre cached parallel ohnehin jede geladene Kachel.
  Future<void> maybeAutoDownloadDach() async {
    if (!autoDownloadEnabled || _downloadInProgress) return;
    try {
      if (await isDachDownloaded()) return;
      final conn = await Connectivity().checkConnectivity();
      if (!conn.contains(ConnectivityResult.wifi)) {
        debugPrint('[MapStyle] Auto-DACH-Download übersprungen (kein WLAN).');
        return;
      }
    } catch (_) {
      return;
    }
    debugPrint('[MapStyle] Auto-DACH-Offline-Download startet (WLAN)…');
    unawaited(downloadDach(onProgress: (received, total) {
      // Grob alle ~100 MB loggen.
      if (received % (100 * 1024 * 1024) < (2 * 1024 * 1024)) {
        final mb = (received / 1024 / 1024).round();
        final totalMb = total > 0 ? (total / 1024 / 1024).round() : -1;
        debugPrint('[MapStyle] DACH offline: $mb${totalMb > 0 ? '/$totalMb' : ''} MB');
      }
    }));
  }

  Future<File> _localFile() async {
    final dir = await getApplicationSupportDirectory();
    final mapDir = Directory('${dir.path}/offline_map');
    if (!await mapDir.exists()) {
      await mapDir.create(recursive: true);
    }
    return File('${mapDir.path}/$_localFileName');
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
    if (await isDachDownloaded()) return true;
    _downloadInProgress = true;
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
          : resp.contentLength + (resp.statusCode == HttpStatus.partialContent
              ? existing
              : 0);
      var received =
          resp.statusCode == HttpStatus.partialContent ? existing : 0;
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

  /// Löscht die lokale Offline-Datei (Speicher freigeben).
  Future<void> deleteOffline() async {
    try {
      final f = await _localFile();
      if (await f.exists()) await f.delete();
      final part = File('${f.path}.part');
      if (await part.exists()) await part.delete();
    } catch (_) {}
  }
}
