import 'package:flutter/foundation.dart';

import 'package:cruise_connect/data/services/prepared_route_buffer.dart';
import 'package:cruise_connect/data/services/route_scenario.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

/// Kleiner Szenario-Puffer für vorbereitete Ersatzrouten.
///
/// Der alte globale Queue-Cache wurde bewusst entfernt, weil er
/// identische oder fachlich falsche Routen in neue User-Intents tragen konnte.
/// Es gibt jetzt maximal eine vorbereitete Route pro Szenario.
class RouteCacheService {
  RouteCacheService._();
  static final RouteCacheService instance = RouteCacheService._();

  /// User-initiierte Generierung pausiert optionale Hintergrundarbeit.
  static bool userGenerationActive = false;

  Future<void> preloadRoutes() async {
    debugPrint(
      '[RouteCache] Globales Vorladen ist deaktiviert. '
      'Vorbereitung passiert nur noch szenariobezogen im PreparedRouteBuffer.',
    );
  }

  RouteResult? getNextRoute() => null;

  int get availableCount => PreparedRouteBuffer.count;

  RouteResult? takePreparedRoute(RouteScenario scenario) {
    return PreparedRouteBuffer.take(scenario.scenarioKey)?.route;
  }

  void storePreparedRoute(
    RouteScenario scenario,
    PreparedRouteEntry entry,
  ) {
    PreparedRouteBuffer.store(scenario.scenarioKey, entry);
  }

  void clearScenario(RouteScenario scenario) {
    PreparedRouteBuffer.clearScenario(scenario.scenarioKey);
  }

  void clearCache() {
    PreparedRouteBuffer.clearAll();
  }
}
