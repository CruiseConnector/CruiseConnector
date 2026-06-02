import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/data/services/map_cache_status.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

class OfflineTile {
  const OfflineTile({required this.z, required this.x, required this.y});

  final int z;
  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is OfflineTile && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);
}

class OfflineMapCacheReport {
  const OfflineMapCacheReport({
    required this.requestedTiles,
    required this.downloadedTiles,
    required this.existingTiles,
    required this.failedTiles,
    required this.skipped,
  });

  final int requestedTiles;
  final int downloadedTiles;
  final int existingTiles;
  final int failedTiles;
  final bool skipped;
}

enum _TileCacheOutcome { downloaded, existing, failed }

// MapCacheStatus-Import als Top-level damit der OfflineMapService den
// globalen Status für die Settings-UI aktualisieren kann.

class OfflineMapService {
  OfflineMapService._();
  static final OfflineMapService instance = OfflineMapService._();

  static const String mapboxDarkTileUrlTemplate =
      'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/256/{z}/{x}/{y}?access_token={accessToken}';

  // 2026-06-01 (vucko): Self-hosted Tile-Quelle (Raster-Tiles aus einer
  // PMTiles-Datei auf einem CDN), um die teuren Mapbox-Tile-Requests abzulösen.
  //
  //   null  → AUS. Es wird ausschließlich Mapbox genutzt (kein Verhaltenswechsel).
  //   gesetzt → sobald der Health-Check die URL als erreichbar meldet, liefert
  //             activeTileUrlTemplate die self-hosted URL. Fällt sie aus,
  //             schaltet es AUTOMATISCH auf Mapbox zurück (Fallback).
  //
  // Format wie Mapbox: 'https://<cdn>/{z}/{x}/{y}.png' (256px, dark-Style nahe
  // CARTO Dark / Mapbox-dark). Kein {accessToken} nötig.
  static const String? selfHostedTileUrlTemplate = null;

  // 2026-06-02 (vucko): Self-hosted VEKTOR-Tiles (PMTiles auf Cloudflare R2).
  // Eine Datei, per HTTP-Range gestreamt — löst die teuren Mapbox-Tile-Requests
  // ab. Wird clientseitig im Dark-Style gerendert (vector_map_tiles_pmtiles).
  // Bei Lade-/Render-Fehler nutzt die App weiter den Mapbox-Raster-Layer.
  // Leeren String setzen, um die Vektor-Quelle abzuschalten (→ Mapbox-Raster).
  static const String selfHostedPmtilesUrl =
      'https://pub-0535dd4f86054de1820907b6f06bf17c.r2.dev/dach.pmtiles';

  // 2026-06-02 (vucko): Welt-Übersicht z0–6 (~43 MB) als Unterlage unter den
  // DACH-Detail-Tiles. So kann man die GANZE Welt sehen/zoomen, während nur
  // DACH im Detail (z0–14) heruntergeladen ist. Egress über R2 = gratis.
  static const String selfHostedWorldPmtilesUrl =
      'https://pub-0535dd4f86054de1820907b6f06bf17c.r2.dev/world_z6.pmtiles';

  PmTilesVectorTileProvider? _pmtilesProvider;
  bool _pmtilesLoadAttempted = false;
  PmTilesVectorTileProvider? _worldPmtilesProvider;
  bool _worldPmtilesLoadAttempted = false;

  /// Lädt den PMTiles-Vektor-Provider einmalig (gecacht). `null` = nicht
  /// verfügbar (leere URL, Web oder Fehler) → die App bleibt beim Mapbox-Raster.
  Future<PmTilesVectorTileProvider?> loadPmtilesProvider() async {
    if (_pmtilesProvider != null || _pmtilesLoadAttempted) {
      return _pmtilesProvider;
    }
    _pmtilesLoadAttempted = true;
    if (kIsWeb || selfHostedPmtilesUrl.isEmpty) return null;
    try {
      _pmtilesProvider =
          await PmTilesVectorTileProvider.fromSource(selfHostedPmtilesUrl);
      if (kDebugMode) debugPrint('[OfflineMap] PMTiles-Vektorquelle geladen.');
    } catch (e) {
      _pmtilesProvider = null;
      if (kDebugMode) debugPrint('[OfflineMap] PMTiles laden fehlgeschlagen: $e');
    }
    return _pmtilesProvider;
  }

  /// Lädt die Welt-Übersichts-Vektorquelle (z0–6) einmalig (gecacht). `null` =
  /// nicht verfügbar → die App zeigt außerhalb DACH nur den dunklen Hintergrund.
  Future<PmTilesVectorTileProvider?> loadWorldPmtilesProvider() async {
    if (_worldPmtilesProvider != null || _worldPmtilesLoadAttempted) {
      return _worldPmtilesProvider;
    }
    _worldPmtilesLoadAttempted = true;
    if (kIsWeb || selfHostedWorldPmtilesUrl.isEmpty) return null;
    try {
      _worldPmtilesProvider =
          await PmTilesVectorTileProvider.fromSource(selfHostedWorldPmtilesUrl);
      if (kDebugMode) debugPrint('[OfflineMap] Welt-PMTiles-Quelle geladen.');
    } catch (e) {
      _worldPmtilesProvider = null;
      if (kDebugMode) {
        debugPrint('[OfflineMap] Welt-PMTiles laden fehlgeschlagen: $e');
      }
    }
    return _worldPmtilesProvider;
  }

  bool _selfHostedHealthy = false;
  int _selfHostedErrorStreak = 0;
  bool _healthRecheckScheduled = false;

  /// self-hosted Quelle aktiv = konfiguriert UND zuletzt als erreichbar geprüft.
  bool get isSelfHostedActive =>
      selfHostedTileUrlTemplate != null && _selfHostedHealthy;

  /// Aktive Tile-URL: self-hosted wenn gesund, sonst Mapbox (Auto-Fallback).
  String get activeTileUrlTemplate =>
      isSelfHostedActive ? selfHostedTileUrlTemplate! : mapboxDarkTileUrlTemplate;

  /// Quell-ID → getrennter Cache-Ordner + TileLayer-Key, damit sich die
  /// Styles (Mapbox vs. self-hosted) im Cache nicht mischen.
  String get activeTileSourceId =>
      isSelfHostedActive ? 'self_hosted_dark' : 'mapbox_dark_v11';

  /// Prüft die self-hosted Quelle (ein Test-Tile). Erfolg → self-hosted aktiv,
  /// Fehler/kein-URL → Mapbox. Beim App-Start + periodisch aufrufen.
  Future<void> refreshTileSourceHealth() async {
    const template = selfHostedTileUrlTemplate;
    if (kIsWeb || template == null) {
      _setSelfHostedHealthy(false);
      return;
    }
    // Test-Tile etwa DACH-Mitte bei Zoom 8.
    final testUrl = template
        .replaceAll('{z}', '8')
        .replaceAll('{x}', '136')
        .replaceAll('{y}', '90')
        .replaceAll('{accessToken}', '');
    try {
      final res = await http
          .get(Uri.parse(testUrl))
          .timeout(const Duration(seconds: 4));
      final ok = res.statusCode >= 200 &&
          res.statusCode < 300 &&
          res.bodyBytes.length > 128;
      _setSelfHostedHealthy(ok);
      if (kDebugMode) {
        debugPrint('[OfflineMap] self-hosted Tiles health=$ok (${res.statusCode})');
      }
    } catch (e) {
      _setSelfHostedHealthy(false);
      if (kDebugMode) debugPrint('[OfflineMap] self-hosted health check failed: $e');
    }
  }

  /// Tile-Lade-Fehler melden (TileLayer.errorTileCallback). Häufen sie sich bei
  /// aktiver self-hosted Quelle, wird automatisch auf Mapbox zurückgeschaltet.
  void reportTileLoadError() {
    if (!isSelfHostedActive) return;
    _selfHostedErrorStreak += 1;
    if (_selfHostedErrorStreak >= 6) {
      _setSelfHostedHealthy(false);
      if (!_healthRecheckScheduled) {
        _healthRecheckScheduled = true;
        unawaited(Future<void>.delayed(const Duration(seconds: 45), () {
          _healthRecheckScheduled = false;
          unawaited(refreshTileSourceHealth());
        }));
      }
    }
  }

  void _setSelfHostedHealthy(bool healthy) {
    if (_selfHostedHealthy == healthy) return;
    _selfHostedHealthy = healthy;
    _selfHostedErrorStreak = 0;
    // Quelle gewechselt → Cache-Verzeichnis neu auflösen (getrennt pro Quelle).
    _tileCacheDirectory = null;
    _tileCacheDirectoryFuture = null;
  }

  /// 2026-05-28 (vucko Task #70): Mapbox-Dark-V11-Hintergrundfarbe.
  /// Wird als TileLayer.backgroundColor + tileBuilder-Container verwendet
  /// damit Pan-Lücken nicht weiß sondern in Map-Style erscheinen.
  static const Color mapboxDarkBackground = Color(0xFF0E1216);

  static const int defaultMinZoom = 10;
  // 2026-05-25 (vucko): Route-Cache maxZoom 17 statt 16 für scharfere Live-
  // Navigation. Plus maxTiles 2400 statt 650 für ganze 5km-Korridor um die
  // Route — sodass Offroad-Excursionen + Reroute-Visualisierung offline klappen.
  static const int defaultMaxZoom = 17;
  static const int defaultMaxTiles = 2400;

  // Region-Cache: 2026-05-22 (vucko) aggressiver vorwärmen.
  // 2026-05-25 (vucko v2): User-Wunsch "Karte wirklich gedownloaded und auch
  // bei Off-Route Visualisierung funktionsfähig". Erweitert:
  //   - minZoom 8 → übersichtliche Karte schon bei großer Höhe
  //   - maxZoom 15 statt 14 → schärfere Tiles für Live-Navigation
  //   - maxTiles 8000 statt 4000 → ganze Vorarlberg-Region (~100km × 100km)
  //   - radius 100km statt 50km → User der nach Tirol/Schweiz fährt hat schon Tiles
  static const int defaultRegionMinZoom = 8;
  static const int defaultRegionMaxZoom = 15;
  static const int defaultRegionMaxTiles = 8000;
  static const double defaultRegionRadiusKm = 100.0;

  // 2026-05-28 (vucko Task #70 v3): Zusätzlicher Detail-Cache für die
  // unmittelbare Umgebung (25km), hochauflösend (Zoom 13-16). Komplementär
  // zum großräumigen Region-Cache (100km, Zoom 8-15) damit die Map auch
  // bei höchsten Zoom-Stufen sofort gerendert wird ohne weiße Lücken.
  // ~4500 Tiles, ~55 MB Disk.
  static const int detailRegionMinZoom = 13;
  static const int detailRegionMaxZoom = 16;
  static const int detailRegionMaxTiles = 4500;
  static const double detailRegionRadiusKm = 25.0;

  // Vorarlberg + Bodensee als Default-Heimatregion, falls kein User-Standort
  // verfügbar (erster Launch, Geo-Permission verweigert).
  static const double defaultHomeLat = 47.4500;
  static const double defaultHomeLng = 9.6000;

  // 2026-05-28 (vucko Task #64): DACH-Pre-Cache.
  // bbox umschließt DE + AT + CH + LI mit kleinem Puffer.
  // Zoom 5-10 für Übersicht (App-Open + Karten-Zoom-Out). Höhere Zoom-Levels
  // werden weiter route-spezifisch nachgeladen.
  // Erwartete Größe: ~3500 Tiles, ~30-50 MB Disk.
  static const double dachBboxSouthLat = 45.7;
  static const double dachBboxNorthLat = 55.1;
  static const double dachBboxWestLng = 5.5;
  static const double dachBboxEastLng = 17.2;
  static const int dachOverviewMinZoom = 5;
  static const int dachOverviewMaxZoom = 10;
  static const int dachOverviewMaxTiles = 4500;

  Directory? _tileCacheDirectory;
  Future<Directory?>? _tileCacheDirectoryFuture;

  Future<void> ensureStyleCached() async {
    await _resolveTileCacheDirectory();
  }

  TileProvider tileProvider() => OfflineMapTileProvider(this);

  /// Cached alle Tiles in einem Quadrat um einen Center-Punkt.
  /// Wird beim App-Start für die Heimat-Region aufgerufen, damit beim ersten
  /// Öffnen der Karte sofort gerendert werden kann statt aus dem Netz zu
  /// streamen. Idempotent: bereits vorhandene Tiles werden nicht erneut
  /// heruntergeladen.
  ///
  /// Default-Radius 35 km, Zoom 9-13 → ~1500-2400 Tiles, ~6-12 MB Storage.
  Future<OfflineMapCacheReport> cacheRegionAroundPoint({
    required double latitude,
    required double longitude,
    double radiusKm = defaultRegionRadiusKm,
    int minZoom = defaultRegionMinZoom,
    int maxZoom = defaultRegionMaxZoom,
    int maxTiles = defaultRegionMaxTiles,
    String regionId = 'home',
  }) async {
    if (kIsWeb) {
      return const OfflineMapCacheReport(
        requestedTiles: 0,
        downloadedTiles: 0,
        existingTiles: 0,
        failedTiles: 0,
        skipped: true,
      );
    }
    final directory = await _resolveTileCacheDirectory();
    if (directory == null) {
      return const OfflineMapCacheReport(
        requestedTiles: 0,
        downloadedTiles: 0,
        existingTiles: 0,
        failedTiles: 0,
        skipped: true,
      );
    }

    final tiles = tilesForBoundingBox(
      centerLat: latitude,
      centerLng: longitude,
      radiusKm: radiusKm,
      minZoom: minZoom,
      maxZoom: maxZoom,
      maxTiles: maxTiles,
    );
    if (tiles.isEmpty) {
      return const OfflineMapCacheReport(
        requestedTiles: 0,
        downloadedTiles: 0,
        existingTiles: 0,
        failedTiles: 0,
        skipped: true,
      );
    }

    var downloaded = 0;
    var existing = 0;
    var failed = 0;
    final client = http.Client();
    try {
      const batchSize = 6;
      for (var i = 0; i < tiles.length; i += batchSize) {
        final batch = tiles.skip(i).take(batchSize);
        final outcomes = await Future.wait(
          batch.map((tile) => _cacheTile(client, directory, tile)),
        );
        for (final outcome in outcomes) {
          switch (outcome) {
            case _TileCacheOutcome.downloaded:
              downloaded += 1;
            case _TileCacheOutcome.existing:
              existing += 1;
            case _TileCacheOutcome.failed:
              failed += 1;
          }
        }
      }
    } finally {
      client.close();
    }

    debugPrint(
      '[OfflineMap] Region cache region=$regionId center=($latitude,$longitude) '
      'radius=${radiusKm}km zoom=$minZoom-$maxZoom requested=${tiles.length} '
      'downloaded=$downloaded existing=$existing failed=$failed',
    );
    return OfflineMapCacheReport(
      requestedTiles: tiles.length,
      downloadedTiles: downloaded,
      existingTiles: existing,
      failedTiles: failed,
      skipped: false,
    );
  }

  /// Berechnet alle Tiles innerhalb eines Quadrats um den Center-Punkt für
  /// jeden Zoom-Level. Limitiert auf maxTiles total — höhere Zoom-Levels
  /// werden zuerst eingefroren wenn das Limit erreicht ist (Übersichts-
  /// Zoom hat Priorität, weil dort die meisten App-Starts beginnen).
  @visibleForTesting
  List<OfflineTile> tilesForBoundingBox({
    required double centerLat,
    required double centerLng,
    required double radiusKm,
    required int minZoom,
    required int maxZoom,
    required int maxTiles,
  }) {
    if (minZoom > maxZoom || maxTiles <= 0 || radiusKm <= 0) {
      return const <OfflineTile>[];
    }
    // Grobe Umrechnung km → Grad. Längengrad-Abstand wird mit lat skaliert
    // (cos(lat)), Breitengrad ist konstant 111 km.
    final degLat = radiusKm / 111.0;
    final cosLat = math.cos(centerLat * math.pi / 180.0).abs();
    final degLng = radiusKm / (111.0 * (cosLat < 0.1 ? 0.1 : cosLat));
    final minLat = (centerLat - degLat).clamp(-85.0, 85.0);
    final maxLat = (centerLat + degLat).clamp(-85.0, 85.0);
    final minLng = centerLng - degLng;
    final maxLng = centerLng + degLng;

    final tiles = <OfflineTile>{};
    for (var zoom = minZoom; zoom <= maxZoom; zoom += 1) {
      final topLeft = _tileForCoordinate([minLng, maxLat], zoom);
      final bottomRight = _tileForCoordinate([maxLng, minLat], zoom);
      for (var x = topLeft.x; x <= bottomRight.x; x += 1) {
        for (var y = topLeft.y; y <= bottomRight.y; y += 1) {
          final tile = _normalizeTile(OfflineTile(z: zoom, x: x, y: y));
          if (tile == null) continue;
          tiles.add(tile);
          if (tiles.length >= maxTiles) {
            return tiles.toList(growable: false);
          }
        }
      }
    }
    return tiles.toList(growable: false);
  }

  /// 2026-05-28 (vucko Task #64): DACH-Übersichtskarte einmalig downloaden.
  ///
  /// Wird beim First-Launch (oder via Settings-Button) im Hintergrund
  /// ausgeführt. Cached die komplette DACH-bbox (Zoom 5-10) → User kann
  /// jederzeit aus dem Cruise-Modus rauszoomen und sieht direkt die ganze
  /// Region offline.
  ///
  /// Erwartete Größe: ~3500 Tiles, ~30-50 MB. WLAN-only Empfehlung.
  ///
  /// [onProgress] wird mit (downloaded, total) callback nach jedem Batch
  /// aufgerufen für UI-Progress-Bar.
  Future<OfflineMapCacheReport> cacheDachOverview({
    void Function(int downloaded, int total)? onProgress,
  }) async {
    if (kIsWeb) {
      return const OfflineMapCacheReport(
        requestedTiles: 0,
        downloadedTiles: 0,
        existingTiles: 0,
        failedTiles: 0,
        skipped: true,
      );
    }
    final directory = await _resolveTileCacheDirectory();
    if (directory == null) {
      MapCacheStatus.instance.markFailed(
        error: 'Cache-Verzeichnis nicht verfügbar',
      );
      return const OfflineMapCacheReport(
        requestedTiles: 0,
        downloadedTiles: 0,
        existingTiles: 0,
        failedTiles: 0,
        skipped: true,
      );
    }
    final tiles = _tilesForBbox(
      southLat: dachBboxSouthLat,
      westLng: dachBboxWestLng,
      northLat: dachBboxNorthLat,
      eastLng: dachBboxEastLng,
      minZoom: dachOverviewMinZoom,
      maxZoom: dachOverviewMaxZoom,
      maxTiles: dachOverviewMaxTiles,
    );
    if (tiles.isEmpty) {
      return const OfflineMapCacheReport(
        requestedTiles: 0,
        downloadedTiles: 0,
        existingTiles: 0,
        failedTiles: 0,
        skipped: true,
      );
    }
    MapCacheStatus.instance.markStarted(totalTiles: tiles.length);
    var downloaded = 0;
    var existing = 0;
    var failed = 0;
    final client = http.Client();
    try {
      const batchSize = 8;
      for (var i = 0; i < tiles.length; i += batchSize) {
        final batch = tiles.skip(i).take(batchSize);
        final outcomes = await Future.wait(
          batch.map((tile) => _cacheTile(client, directory, tile)),
        );
        for (final outcome in outcomes) {
          switch (outcome) {
            case _TileCacheOutcome.downloaded:
              downloaded += 1;
            case _TileCacheOutcome.existing:
              existing += 1;
            case _TileCacheOutcome.failed:
              failed += 1;
          }
        }
        final progressed = downloaded + existing;
        MapCacheStatus.instance.updateProgress(downloaded: progressed);
        onProgress?.call(progressed, tiles.length);
      }
    } finally {
      client.close();
    }
    debugPrint(
      '[OfflineMap] DACH overview cache: requested=${tiles.length} '
      'downloaded=$downloaded existing=$existing failed=$failed',
    );
    // Faustregel: Mapbox-Tile ~12 KB im Schnitt (Dark-V11 style). Real
    // measured ~9-14 KB. Wir runden auf 12 KB pro Tile.
    final approxSizeMb = ((downloaded + existing) * 12) ~/ 1024;
    // 2026-05-28 (vucko Task #69): NACH dem ersten Pass automatisch
    // verify+repair laufen lassen — fängt die Connection-Reset-Fehler ab
    // die im ersten Durchlauf einzelne Tiles fehlen lassen.
    if (failed > 0) {
      debugPrint(
        '[OfflineMap] DACH-Pass hatte $failed Fehlversuche — Verify+Repair startet.',
      );
      // Verify+Repair updated den MapCacheStatus selbst.
      await verifyAndRepairDachOverview(onProgress: onProgress);
    } else if (failed == 0) {
      MapCacheStatus.instance.markCompleted(
        totalTiles: tiles.length,
        approxSizeMb: approxSizeMb,
      );
    }
    return OfflineMapCacheReport(
      requestedTiles: tiles.length,
      downloadedTiles: downloaded,
      existingTiles: existing,
      failedTiles: failed,
      skipped: false,
    );
  }

  /// 2026-05-28 (vucko Task #71): Detail-Region-Cache um User-Position.
  /// Komplementär zum großräumigen Region-Cache (100km/Zoom 8-15): hier
  /// 25km Radius bei Zoom 13-16 für hochauflösende Live-Navi ohne weiße
  /// Tile-Lücken. Wird beim Home-Open einmalig getriggert wenn noch nicht
  /// vorhanden.
  Future<OfflineMapCacheReport> cacheDetailRegionAroundPoint({
    required double latitude,
    required double longitude,
  }) async {
    return cacheRegionAroundPoint(
      latitude: latitude,
      longitude: longitude,
      radiusKm: detailRegionRadiusKm,
      minZoom: detailRegionMinZoom,
      maxZoom: detailRegionMaxZoom,
      maxTiles: detailRegionMaxTiles,
      regionId: 'detail_local',
    );
  }

  /// 2026-05-28 (vucko Task #69): Verifiziert dass alle DACH-Overview-Tiles
  /// wirklich auf der Disk liegen — und repariert fehlende automatisch.
  ///
  /// Problem das das löst: Mapbox-Server hat ab und zu Connection-Resets
  /// (sieht man in `http: connection closed before full header was received`),
  /// einzelne Tiles fallen durch obwohl der Download-Pass als „completed"
  /// (>90% success) markiert wurde. Diese Methode:
  ///   1. Berechnet alle expected DACH-Tiles
  ///   2. Prüft pro Tile: file.exists() UND size > 128 Bytes (sonst leeres
  ///      Tile aus früherem fehlerhaftem Download)
  ///   3. Sammelt fehlende
  ///   4. Lädt sie mit höherem Timeout + bis zu 3 Retries pro Tile nach
  ///
  /// Returns: ({total, ok, repairedNow, stillMissing}).
  ///
  /// [onProgress] wird mit (done, total) für Settings-UI gefeuert während
  /// der Repair-Phase läuft.
  Future<({int total, int ok, int repairedNow, int stillMissing})>
      verifyAndRepairDachOverview({
    void Function(int done, int total)? onProgress,
  }) async {
    if (kIsWeb) return (total: 0, ok: 0, repairedNow: 0, stillMissing: 0);
    final directory = await _resolveTileCacheDirectory();
    if (directory == null) return (total: 0, ok: 0, repairedNow: 0, stillMissing: 0);
    final expected = _tilesForBbox(
      southLat: dachBboxSouthLat,
      westLng: dachBboxWestLng,
      northLat: dachBboxNorthLat,
      eastLng: dachBboxEastLng,
      minZoom: dachOverviewMinZoom,
      maxZoom: dachOverviewMaxZoom,
      maxTiles: dachOverviewMaxTiles,
    );
    if (expected.isEmpty) {
      return (total: 0, ok: 0, repairedNow: 0, stillMissing: 0);
    }
    // 1. Verify-Pass: welche Tiles fehlen oder sind defekt (< 128 Bytes)?
    final missing = <OfflineTile>[];
    var okCount = 0;
    for (final tile in expected) {
      final file = _tileFile(directory, tile);
      if (!await file.exists()) {
        missing.add(tile);
        continue;
      }
      final size = await file.length();
      if (size < 128) {
        try {
          await file.delete();
        } catch (_) {}
        missing.add(tile);
        continue;
      }
      okCount += 1;
    }
    debugPrint(
      '[OfflineMap] Verify: ${expected.length} expected, $okCount OK, '
      '${missing.length} fehlen/defekt.',
    );
    if (missing.isEmpty) {
      MapCacheStatus.instance.markCompleted(
        totalTiles: expected.length,
        approxSizeMb: (okCount * 12) ~/ 1024,
      );
      return (total: expected.length, ok: okCount, repairedNow: 0, stillMissing: 0);
    }
    // 2. Repair-Pass: fehlende mit höherem Timeout + 3 Retries nachladen.
    MapCacheStatus.instance.markStarted(totalTiles: expected.length);
    MapCacheStatus.instance.updateProgress(downloaded: okCount);
    var repairedNow = 0;
    final client = http.Client();
    try {
      const batchSize = 4; // kleiner Batch, längeres Timeout — fairer zu Mapbox
      for (var i = 0; i < missing.length; i += batchSize) {
        final batch = missing.skip(i).take(batchSize);
        final outcomes = await Future.wait(
          batch.map((tile) => _cacheTileWithRetry(
                client,
                directory,
                tile,
                maxRetries: 3,
              )),
        );
        for (final outcome in outcomes) {
          if (outcome == _TileCacheOutcome.downloaded ||
              outcome == _TileCacheOutcome.existing) {
            repairedNow += 1;
          }
        }
        final done = okCount + repairedNow;
        MapCacheStatus.instance.updateProgress(downloaded: done);
        onProgress?.call(done, expected.length);
      }
    } finally {
      client.close();
    }
    final stillMissing = missing.length - repairedNow;
    final newOk = okCount + repairedNow;
    final approxSizeMb = (newOk * 12) ~/ 1024;
    debugPrint(
      '[OfflineMap] Repair: $repairedNow von ${missing.length} fehlende '
      'erfolgreich nachgeladen, $stillMissing weiterhin fehlen.',
    );
    if (stillMissing == 0) {
      MapCacheStatus.instance.markCompleted(
        totalTiles: expected.length,
        approxSizeMb: approxSizeMb,
      );
    } else if (stillMissing < expected.length * 0.02) {
      // < 2% Toleranz — wir markieren trotzdem als „completed" weil das
      // visuell kaum auffällt, beim nächsten Tile-Render lädt der Network-
      // Provider den Rest on-demand nach.
      MapCacheStatus.instance.markCompleted(
        totalTiles: expected.length,
        approxSizeMb: approxSizeMb,
      );
    } else {
      MapCacheStatus.instance.markFailed(
        error:
            '$stillMissing von ${expected.length} Tiles konnten auch nach Repair nicht geladen werden',
      );
    }
    return (
      total: expected.length,
      ok: newOk,
      repairedNow: repairedNow,
      stillMissing: stillMissing,
    );
  }

  /// 2026-05-28 (vucko Task #69): Variante von [_cacheTile] mit Retry-Loop
  /// und längerem Timeout — gedacht für Repair-Pass damit transient errors
  /// nicht permanente Lücken hinterlassen.
  Future<_TileCacheOutcome> _cacheTileWithRetry(
    http.Client client,
    Directory directory,
    OfflineTile tile, {
    required int maxRetries,
  }) async {
    final file = _tileFile(directory, tile);
    if (await file.exists() && await file.length() >= 128) {
      return _TileCacheOutcome.existing;
    }
    var attempt = 0;
    while (attempt < maxRetries) {
      attempt += 1;
      try {
        final response = await client
            .get(_tileUri(tile))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            response.bodyBytes.length > 128) {
          await file.parent.create(recursive: true);
          await file.writeAsBytes(response.bodyBytes, flush: true);
          return _TileCacheOutcome.downloaded;
        }
      } catch (_) {
        // Bei Connection-Reset: kurzes Backoff dann Retry.
      }
      if (attempt < maxRetries) {
        await Future<void>.delayed(
          Duration(milliseconds: 200 + attempt * 350),
        );
      }
    }
    return _TileCacheOutcome.failed;
  }

  /// 2026-05-28 (vucko Task #64): DACH-Cache wieder löschen — bei
  /// User-Anfrage aus Settings.
  /// Löscht NUR die DACH-Überblick-Zoomstufen (5-10). Route-Cache-Tiles
  /// (Zoom 11+) und persönliche Cache-Regionen bleiben erhalten.
  Future<int> clearDachOverviewCache() async {
    if (kIsWeb) return 0;
    final directory = await _resolveTileCacheDirectory();
    if (directory == null) return 0;
    var deleted = 0;
    try {
      for (var zoom = dachOverviewMinZoom;
          zoom <= dachOverviewMaxZoom;
          zoom += 1) {
        final zoomDir = Directory('${directory.path}/$zoom');
        if (await zoomDir.exists()) {
          await for (final entity in zoomDir.list(recursive: true)) {
            if (entity is File) {
              try {
                await entity.delete();
                deleted += 1;
              } catch (_) {
                // ignore single-file delete errors
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[OfflineMap] Fehler beim Löschen des DACH-Caches: $e');
    }
    MapCacheStatus.instance.reset();
    debugPrint('[OfflineMap] DACH-Cache gelöscht — $deleted Tiles entfernt.');
    return deleted;
  }

  /// bbox-Tiles (direkter Bounding-Box, ohne Center+Radius-Umrechnung).
  List<OfflineTile> _tilesForBbox({
    required double southLat,
    required double westLng,
    required double northLat,
    required double eastLng,
    required int minZoom,
    required int maxZoom,
    required int maxTiles,
  }) {
    if (minZoom > maxZoom ||
        maxTiles <= 0 ||
        southLat >= northLat ||
        westLng >= eastLng) {
      return const <OfflineTile>[];
    }
    final tiles = <OfflineTile>{};
    for (var zoom = minZoom; zoom <= maxZoom; zoom += 1) {
      final topLeft = _tileForCoordinate([westLng, northLat], zoom);
      final bottomRight = _tileForCoordinate([eastLng, southLat], zoom);
      for (var x = topLeft.x; x <= bottomRight.x; x += 1) {
        for (var y = topLeft.y; y <= bottomRight.y; y += 1) {
          final tile = _normalizeTile(OfflineTile(z: zoom, x: x, y: y));
          if (tile == null) continue;
          tiles.add(tile);
          if (tiles.length >= maxTiles) {
            return tiles.toList(growable: false);
          }
        }
      }
    }
    return tiles.toList(growable: false);
  }

  Future<OfflineMapCacheReport> cacheRouteRegion(
    List<List<double>> routeCoordinates, {
    String regionId = 'active-route',
    int minZoom = defaultMinZoom,
    int maxZoom = defaultMaxZoom,
    int maxTiles = defaultMaxTiles,
  }) async {
    if (kIsWeb || routeCoordinates.length < 2) {
      return const OfflineMapCacheReport(
        requestedTiles: 0,
        downloadedTiles: 0,
        existingTiles: 0,
        failedTiles: 0,
        skipped: true,
      );
    }

    final directory = await _resolveTileCacheDirectory();
    if (directory == null) {
      return const OfflineMapCacheReport(
        requestedTiles: 0,
        downloadedTiles: 0,
        existingTiles: 0,
        failedTiles: 0,
        skipped: true,
      );
    }

    final tiles = tilesForRoute(
      routeCoordinates,
      minZoom: minZoom,
      maxZoom: maxZoom,
      maxTiles: maxTiles,
    );
    var downloaded = 0;
    var existing = 0;
    var failed = 0;

    final client = http.Client();
    try {
      const batchSize = 6;
      for (var i = 0; i < tiles.length; i += batchSize) {
        final batch = tiles.skip(i).take(batchSize);
        final outcomes = await Future.wait(
          batch.map((tile) => _cacheTile(client, directory, tile)),
        );
        for (final outcome in outcomes) {
          switch (outcome) {
            case _TileCacheOutcome.downloaded:
              downloaded += 1;
            case _TileCacheOutcome.existing:
              existing += 1;
            case _TileCacheOutcome.failed:
              failed += 1;
          }
        }
      }
    } finally {
      client.close();
    }

    debugPrint(
      '[OfflineMap] Tiles region=$regionId requested=${tiles.length} '
      'downloaded=$downloaded existing=$existing failed=$failed',
    );
    return OfflineMapCacheReport(
      requestedTiles: tiles.length,
      downloadedTiles: downloaded,
      existingTiles: existing,
      failedTiles: failed,
      skipped: false,
    );
  }

  @visibleForTesting
  List<OfflineTile> tilesForRoute(
    List<List<double>> routeCoordinates, {
    int minZoom = defaultMinZoom,
    int maxZoom = defaultMaxZoom,
    int maxTiles = defaultMaxTiles,
  }) {
    if (routeCoordinates.length < 2 || minZoom > maxZoom || maxTiles <= 0) {
      return const <OfflineTile>[];
    }

    final sampled = _sampleRouteCoordinates(routeCoordinates);
    final tiles = <OfflineTile>{};
    // 2026-05-25 (vucko): Bewusst breiterer Korridor um die Route. So sind
    // beim Off-Route (User fährt 300-500m abseits) die Tiles schon im Cache
    // → Mapbox-Map bleibt sichtbar + Reroute kann visualisiert werden ohne
    // dass leere graue Tiles erscheinen.
    for (var zoom = minZoom; zoom <= maxZoom; zoom += 1) {
      // Korridor-Ring abhängig vom Zoom:
      //   z ≤ 11: ring 0 (eine Tile pro Sample-Punkt, viele km abgedeckt)
      //   z 12-13: ring 1 (3×3 = 9 Tiles pro Punkt)
      //   z 14-15: ring 2 (5×5 = 25 Tiles pro Punkt — ~2km Korridor)
      //   z ≥ 16: ring 3 (7×7 = 49 Tiles — ~500m Korridor bei z=17)
      final ring = zoom <= 11
          ? 0
          : zoom <= 13
              ? 1
              : zoom <= 15
                  ? 2
                  : 3;
      for (final coordinate in sampled) {
        final tile = _tileForCoordinate(coordinate, zoom);
        for (var dx = -ring; dx <= ring; dx += 1) {
          for (var dy = -ring; dy <= ring; dy += 1) {
            final candidate = _normalizeTile(
              OfflineTile(z: zoom, x: tile.x + dx, y: tile.y + dy),
            );
            if (candidate == null) continue;
            tiles.add(candidate);
            if (tiles.length >= maxTiles) return tiles.toList(growable: false);
          }
        }
      }
    }
    return tiles.toList(growable: false);
  }

  File? cachedTileFile(OfflineTile tile) {
    final directory = _tileCacheDirectory;
    if (directory == null || kIsWeb) return null;
    return _tileFile(directory, tile);
  }

  Future<_TileCacheOutcome> _cacheTile(
    http.Client client,
    Directory directory,
    OfflineTile tile,
  ) async {
    final file = _tileFile(directory, tile);
    if (await file.exists()) return _TileCacheOutcome.existing;
    try {
      final response = await client
          .get(_tileUri(tile))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.bodyBytes.length > 128) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(response.bodyBytes, flush: false);
        return _TileCacheOutcome.downloaded;
      }
    } catch (_) {
      // Einzelne Tile-Fehler sind erwartet bei schlechtem Netz.
    }
    return _TileCacheOutcome.failed;
  }

  Future<Directory?> _resolveTileCacheDirectory() {
    if (kIsWeb) return Future<Directory?>.value(null);
    final existing = _tileCacheDirectory;
    if (existing != null) return Future<Directory?>.value(existing);
    return _tileCacheDirectoryFuture ??= _createTileCacheDirectory();
  }

  Future<Directory?> _createTileCacheDirectory() async {
    try {
      final base = await getApplicationSupportDirectory();
      // 2026-06-01 (vucko): Ordner pro Quelle (mapbox_dark_v11 / self_hosted_dark)
      // → kein Style-Mix im Cache beim Umschalten.
      final directory =
          Directory('${base.path}/offline_tiles/$activeTileSourceId');
      await directory.create(recursive: true);
      _tileCacheDirectory = directory;
      return directory;
    } catch (e) {
      debugPrint('[OfflineMap] Tile-Cache-Verzeichnis nicht verfügbar: $e');
      return null;
    } finally {
      _tileCacheDirectoryFuture = null;
    }
  }

  Uri _tileUri(OfflineTile tile) => tileNetworkUri(tile);

  /// 2026-06-01 (vucko): Baut die Tile-URL aus der AKTIVEN Quelle (self-hosted
  /// oder Mapbox-Fallback). Wird sowohl vom Cache-Download als auch vom
  /// [OfflineMapTileProvider] (Live-Tiles) genutzt → eine Source-of-Truth.
  /// {accessToken} wird nur ersetzt, wenn das Template ihn enthält (Mapbox);
  /// bei self-hosted ist es ein No-op.
  Uri tileNetworkUri(OfflineTile tile) {
    final url = activeTileUrlTemplate
        .replaceAll('{z}', tile.z.toString())
        .replaceAll('{x}', tile.x.toString())
        .replaceAll('{y}', tile.y.toString())
        .replaceAll('{accessToken}', AppConstants.mapboxPublicToken);
    return Uri.parse(url);
  }

  /// 2026-05-28 (vucko Task #70): Wird vom [OfflineMapTileProvider] bei
  /// jedem Cache-Miss gefeuert. Lädt das Tile silent im Hintergrund und
  /// speichert es persistent → beim nächsten Pan über dieselbe Region
  /// gibt's keinen weißen Block mehr.
  ///
  /// Dedup pro (z,x,y) damit nicht 5× parallel das gleiche Tile gezogen
  /// wird (flutter_map kann denselben Coord mehrfach abfragen während
  /// Animations).
  final Set<String> _inflightTileFetches = <String>{};

  void persistTileFromNetwork(OfflineTile tile) {
    if (kIsWeb) return;
    final key = '${tile.z}/${tile.x}/${tile.y}';
    if (_inflightTileFetches.contains(key)) return;
    _inflightTileFetches.add(key);
    unawaited(_persistTileFromNetwork(tile).whenComplete(() {
      _inflightTileFetches.remove(key);
    }));
  }

  Future<void> _persistTileFromNetwork(OfflineTile tile) async {
    try {
      final directory = await _resolveTileCacheDirectory();
      if (directory == null) return;
      final file = _tileFile(directory, tile);
      if (await file.exists() && await file.length() >= 128) return;
      final response = await http.get(_tileUri(tile)).timeout(
        const Duration(seconds: 6),
      );
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.bodyBytes.length > 128) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(response.bodyBytes, flush: false);
      }
    } catch (_) {
      // best-effort, silent fail
    }
  }

  File _tileFile(Directory directory, OfflineTile tile) {
    return File('${directory.path}/${tile.z}/${tile.x}/${tile.y}.png');
  }

  List<List<double>> _sampleRouteCoordinates(List<List<double>> coordinates) {
    final sampled = <List<double>>[coordinates.first];
    var distanceSinceLastSample = 0.0;
    for (var i = 1; i < coordinates.length; i += 1) {
      final previous = coordinates[i - 1];
      final current = coordinates[i];
      distanceSinceLastSample += _distanceMeters(previous, current);
      if (distanceSinceLastSample >= 450) {
        sampled.add(current);
        distanceSinceLastSample = 0;
      }
    }
    if (sampled.last != coordinates.last) sampled.add(coordinates.last);
    return sampled;
  }

  OfflineTile _tileForCoordinate(List<double> coordinate, int zoom) {
    final longitude = coordinate[0].clamp(-180.0, 180.0).toDouble();
    final latitude = coordinate[1].clamp(-85.05112878, 85.05112878).toDouble();
    final latRad = latitude * math.pi / 180.0;
    final scale = 1 << zoom;
    final x = (((longitude + 180.0) / 360.0) * scale).floor();
    final y =
        ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
                2.0 *
                scale)
            .floor();
    return _normalizeTile(OfflineTile(z: zoom, x: x, y: y))!;
  }

  OfflineTile? _normalizeTile(OfflineTile tile) {
    final scale = 1 << tile.z;
    if (tile.y < 0 || tile.y >= scale) return null;
    final x = tile.x % scale;
    return OfflineTile(z: tile.z, x: x < 0 ? x + scale : x, y: tile.y);
  }

  double _distanceMeters(List<double> a, List<double> b) {
    const earthRadiusMeters = 6371000.0;
    final lat1 = a[1] * math.pi / 180.0;
    final lat2 = b[1] * math.pi / 180.0;
    final dLat = (b[1] - a[1]) * math.pi / 180.0;
    final dLng = (b[0] - a[0]) * math.pi / 180.0;
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }
}

class OfflineMapTileProvider extends TileProvider {
  OfflineMapTileProvider(this._service, {super.headers});

  final OfflineMapService _service;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final tile = OfflineTile(
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
    );
    final file = _service.cachedTileFile(tile);
    if (file != null && file.existsSync()) {
      return FileImage(file);
    }
    // 2026-05-28 (vucko Task #69 follow-up): Bei Cache-Miss NICHT nur
    // ein Network-Image returnen — auch parallel den Tile in den Cache
    // schreiben. So fängt jedes mal-bewegen die fehlende Tiles ab und
    // beim nächsten Render ist die Datei da → kein weißes Kästchen mehr.
    _service.persistTileFromNetwork(tile);
    // 2026-06-01 (vucko): URL aus der AKTIVEN Quelle bauen (self-hosted ODER
    // Mapbox-Fallback) statt aus dem statischen TileLayer-Template — so greift
    // ein Quellwechsel sofort, ohne Rebuild.
    return NetworkImage(
      _service.tileNetworkUri(tile).toString(),
      headers: headers.isEmpty ? null : headers,
    );
  }
}
