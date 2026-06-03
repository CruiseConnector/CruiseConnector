import 'dart:io';

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

  static const String _localFileName = 'dach.pmtiles';

  /// Mindestgröße, damit eine abgebrochene/teilweise Datei NICHT als „fertig"
  /// gilt (die echte DACH-Datei ist mehrere GB groß).
  static const int _minValidBytes = 200 * 1024 * 1024; // 200 MB

  bool _downloadInProgress = false;
  bool get isDownloading => _downloadInProgress;

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
    final raw = await rootBundle.loadString(asset);
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
