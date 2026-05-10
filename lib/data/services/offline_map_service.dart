import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cruise_connect/core/constants.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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

class OfflineMapService {
  OfflineMapService._();
  static final OfflineMapService instance = OfflineMapService._();

  static const String mapboxDarkTileUrlTemplate =
      'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/256/{z}/{x}/{y}?access_token={accessToken}';

  static const int defaultMinZoom = 10;
  static const int defaultMaxZoom = 16;
  static const int defaultMaxTiles = 650;

  Directory? _tileCacheDirectory;
  Future<Directory?>? _tileCacheDirectoryFuture;

  Future<void> ensureStyleCached() async {
    await _resolveTileCacheDirectory();
  }

  TileProvider tileProvider() => OfflineMapTileProvider(this);

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
    for (var zoom = minZoom; zoom <= maxZoom; zoom += 1) {
      final ring = zoom >= 15 ? 1 : 0;
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
      final directory = Directory('${base.path}/offline_tiles/mapbox_dark_v11');
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

  Uri _tileUri(OfflineTile tile) {
    final url = mapboxDarkTileUrlTemplate
        .replaceAll('{z}', tile.z.toString())
        .replaceAll('{x}', tile.x.toString())
        .replaceAll('{y}', tile.y.toString())
        .replaceAll('{accessToken}', AppConstants.mapboxPublicToken);
    return Uri.parse(url);
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
    return NetworkImage(
      getTileUrl(coordinates, options),
      headers: headers.isEmpty ? null : headers,
    );
  }
}
