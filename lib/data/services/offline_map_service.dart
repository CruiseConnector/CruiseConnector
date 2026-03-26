import 'package:flutter/foundation.dart';

/// Stub für den ehemaligen Mapbox-Offline-Map-Service.
///
/// Nach der Migration zu flutter_map werden Karten-Tiles direkt über
/// die Mapbox Raster-Tile-API geladen. Offline-Caching ist aktuell
/// nicht implementiert — der Browser/das OS cached HTTP-Antworten automatisch.
///
/// Die Klasse bleibt als Stub erhalten, damit bestehende Aufrufe in
/// cruise_mode_page.dart und confirmRoute() keine Compilation-Fehler erzeugen.
class OfflineMapService {
  OfflineMapService._();
  static final OfflineMapService instance = OfflineMapService._();

  bool _initialized = false;

  /// No-Op: flutter_map cached Tiles automatisch via HTTP.
  Future<void> ensureStyleCached() async {
    if (_initialized) return;
    _initialized = true;
    debugPrint('[OfflineMap] flutter_map: kein manuelles Style-Caching nötig.');
  }

  /// No-Op: flutter_map cached Tiles automatisch via HTTP.
  Future<void> cacheRouteRegion(
    List<List<double>> routeCoordinates, {
    String regionId = 'active-route',
  }) async {
    debugPrint('[OfflineMap] flutter_map: kein manuelles Tile-Caching nötig.');
  }
}
