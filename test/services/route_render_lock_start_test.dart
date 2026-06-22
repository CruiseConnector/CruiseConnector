import 'package:cruise_connect/data/services/route_render_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RouteRenderLock Erst-Akquise (Start-Lasso-Fix 2026-06-23)', () {
    // Selbstüberlappender Rundkurs: Start-Leg (Segment 0) geht senkrecht nach
    // Norden; der Rückweg-Leg (Segment 3) läuft entlang lat 47.0 dicht am Start
    // vorbei. Genau die Konstellation aus dem Geräte-Video.
    final route = <List<double>>[
      [9.0, 47.0], // 0 Start
      [9.0, 47.01], // 1 Norden (Start-Leg, ~1113 m)
      [9.002, 47.01], // 2 Osten
      [9.002, 47.0], // 3 Süden
      [9.0003, 47.0], // 4 Westen zurück, endet ~7 m östlich vom Start
    ];

    test('Puck nah am Rückweg-Leg rastet trotzdem am START-Leg ein (kein Spike)',
        () {
      final lock = RouteRenderLock();
      // Puck minimal östlich vom Start: ~7,6 m vom fernen Rückweg-Leg (Segment 3),
      // ~15 m vom senkrechten Start-Leg (Segment 0). OHNE Fix gewinnt die Voll-
      // Suche das nähere FERNE Segment 3 → 3-km-Fenster startet dort → Lasso-Spike.
      final proj = lock.project(
        coordinates: route,
        latitude: 47.0,
        longitude: 9.0002,
        routeConfirmed: true,
        currentRouteIndex: 0,
        speedMps: 0.0,
      );
      expect(proj, isNotNull);
      // MIT Fix: Erst-Akquise um currentRouteIndex (0) gebounded → Start-Leg.
      expect(proj!.segmentIndex, 0);
    });

    test('Erst-Akquise folgt dem currentRouteIndex-Hinweis (z.B. nach Re-Anchor)',
        () {
      final lock = RouteRenderLock();
      // Puck auf dem Rückweg-Leg; currentRouteIndex zeigt korrekt dorthin (3).
      final proj = lock.project(
        coordinates: route,
        latitude: 47.0,
        longitude: 9.001,
        routeConfirmed: true,
        currentRouteIndex: 3,
        speedMps: 0.0,
      );
      expect(proj, isNotNull);
      expect(proj!.segmentIndex, 3);
    });
  });
}
