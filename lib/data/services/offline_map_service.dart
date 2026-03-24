import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Cached den Dark-Map-Style für Offline-Nutzung.
///
/// Beim App-Start wird der Style einmalig heruntergeladen,
/// damit die Karte auch bei schlechter Verbindung sofort lädt.
class OfflineMapService {
  OfflineMapService._();
  static final OfflineMapService instance = OfflineMapService._();

  bool _initialized = false;

  /// Lädt den Dark-Style für Offline-Nutzung.
  /// Idempotent — läuft nur einmal, auch bei mehrfachem Aufruf.
  Future<void> ensureStyleCached() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final offlineManager = await OfflineManager.create();

      // Style-Pack für Dark-Modus laden (Zoom 0-16 reicht für Navigation)
      await offlineManager.loadStylePack(
        MapboxStyles.DARK,
        StylePackLoadOptions(
          glyphsRasterizationMode:
              GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
          metadata: {'app': 'CruiseConnect'},
          acceptExpired: true,
        ),
        (progress) {
          debugPrint(
            '[OfflineMap] Style: ${progress.completedResourceCount}/${progress.requiredResourceCount}',
          );
        },
      );

      debugPrint('[OfflineMap] Dark-Style gecached');
    } catch (e) {
      debugPrint('[OfflineMap] Style-Caching fehlgeschlagen: $e');
      // Nicht kritisch — App funktioniert auch online
    }
  }

  /// Cached Kartenkacheln entlang einer Route für Offline-Navigation.
  /// [routeCoordinates] sind die Route-Koordinaten als [lng, lat] Listen.
  Future<void> cacheRouteRegion(
    List<List<double>> routeCoordinates, {
    String regionId = 'active-route',
  }) async {
    if (routeCoordinates.length < 2) return;

    try {
      final tileStore = await TileStore.createDefault();

      // Bounding-Box um die Route berechnen (mit 2km Puffer)
      double minLng = double.infinity, maxLng = -double.infinity;
      double minLat = double.infinity, maxLat = -double.infinity;
      for (final c in routeCoordinates) {
        if (c[0] < minLng) minLng = c[0];
        if (c[0] > maxLng) maxLng = c[0];
        if (c[1] < minLat) minLat = c[1];
        if (c[1] > maxLat) maxLat = c[1];
      }
      // ~2km Puffer in Grad (ca. 0.018°)
      const buffer = 0.018;
      minLng -= buffer;
      maxLng += buffer;
      minLat -= buffer;
      maxLat += buffer;

      // Tile-Region laden (Zoom 10-16 für Navigation)
      await tileStore.loadTileRegion(
        regionId,
        TileRegionLoadOptions(
          geometry: {
            'type': 'Polygon',
            'coordinates': [
              [
                [minLng, minLat],
                [maxLng, minLat],
                [maxLng, maxLat],
                [minLng, maxLat],
                [minLng, minLat],
              ],
            ],
          },
          descriptorsOptions: [
            TilesetDescriptorOptions(
              styleURI: MapboxStyles.DARK,
              minZoom: 10,
              maxZoom: 16,
            ),
          ],
          acceptExpired: true,
          networkRestriction: NetworkRestriction.NONE,
        ),
        (progress) {
          if (progress.completedResourceCount % 50 == 0) {
            debugPrint(
              '[OfflineMap] Tiles: ${progress.completedResourceCount}/${progress.requiredResourceCount}',
            );
          }
        },
      );

      debugPrint('[OfflineMap] Route-Region gecached');
    } catch (e) {
      debugPrint('[OfflineMap] Route-Caching fehlgeschlagen: $e');
    }
  }
}
