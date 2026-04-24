// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:cruise_connect/data/services/route_service.dart';

// ─── Hilfsfunktionen ─────────────────────────────────────────────────────────

/// Erstellt eine simulierte GPS-Position.
geo.Position _position(double lat, double lng) => geo.Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 5.0,
      altitude: 500.0,
      altitudeAccuracy: 10.0,
      heading: 0.0,
      headingAccuracy: 5.0,
      speed: 0.0,
      speedAccuracy: 1.0,
    );

/// Erzeugt eine gerade Nord-Süd Route (koordinaten: [lng, lat]).
List<List<double>> _straightNorthRoute({
  double startLat = 48.00,
  double startLng = 11.58,
  int points = 100,
  double stepDegrees = 0.001, // ca. 111m pro Schritt
}) =>
    List.generate(points, (i) => [startLng, startLat + i * stepDegrees]);

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('findNearestInWindow – Grundverhalten', () {
    test('leere Koordinatenliste → infinity Distanz, Index 0', () {
      final match = findNearestInWindow(
        position: _position(48.14, 11.58),
        coordinates: [],
        currentIndex: 0,
      );
      expect(match.index, 0);
      expect(match.distanceMeters, double.infinity);
    });

    test('User exakt auf Routenpunkt → Distanz ~0', () {
      final coords = _straightNorthRoute();
      final targetPoint = coords[10]; // [11.58, 48.01]

      final match = findNearestInWindow(
        position: _position(targetPoint[1], targetPoint[0]),
        coordinates: coords,
        currentIndex: 0,
        windowSize: 40,
      );
      expect(match.distanceMeters, lessThan(5.0));
      expect(match.index, 10);
    });

    test('User auf der Route → nächster Punkt korrekt gefunden', () {
      final coords = _straightNorthRoute();

      // Zwischen Punkt 5 und 6 (bei ~48.005)
      final match = findNearestInWindow(
        position: _position(48.0053, 11.58),
        coordinates: coords,
        currentIndex: 0,
        windowSize: 20,
      );
      expect(match.index, inInclusiveRange(4, 7));
      expect(match.distanceMeters, lessThan(50.0));
    });

    test('currentIndex wird als Startpunkt des Fensters genutzt', () {
      final coords = _straightNorthRoute(points: 50);

      // User ist bei Punkt 30, Fenster sucht ab Index 25
      final match = findNearestInWindow(
        position: _position(coords[30][1], coords[30][0]),
        coordinates: coords,
        currentIndex: 25,
        windowSize: 10,
      );
      expect(match.index, inInclusiveRange(28, 32));
    });

    test('User deutlich neben der Route → hohe Distanz (>150m)', () {
      final coords = _straightNorthRoute();

      // User 500m östlich der Route
      final match = findNearestInWindow(
        position: _position(48.05, 11.59), // ~800m östlich
        coordinates: coords,
        currentIndex: 0,
        windowSize: coords.length,
      );
      expect(match.distanceMeters, greaterThan(150.0));
    });

    test('Fenstergrenze wird nicht überschritten', () {
      final coords = _straightNorthRoute(points: 100);

      // User ist bei Punkt 80 aber Fenster geht nur bis Index 10+20=30
      final match = findNearestInWindow(
        position: _position(coords[80][1], coords[80][0]),
        coordinates: coords,
        currentIndex: 10,
        windowSize: 20,
      );
      // Soll nur innerhalb des Fensters suchen
      expect(match.index, lessThanOrEqualTo(30));
    });

    test('currentIndex am Ende der Route → kein Absturz', () {
      final coords = _straightNorthRoute(points: 10);

      final match = findNearestInWindow(
        position: _position(48.009, 11.58),
        coordinates: coords,
        currentIndex: 9, // letzter Index
        windowSize: 20,
      );
      expect(match.index, inInclusiveRange(0, 9));
    });

    test('windowSize größer als verbleibende Koordinaten → kein Absturz', () {
      final coords = _straightNorthRoute(points: 10);

      expect(
        () => findNearestInWindow(
          position: _position(48.005, 11.58),
          coordinates: coords,
          currentIndex: 5,
          windowSize: 1000, // viel größer als Liste
        ),
        returnsNormally,
      );
    });
  });

  group('findNearestInWindow – Off-Route Erkennung (>150m Schwelle)', () {
    test('Position genau auf Route (0m) ist ON-Route', () {
      final coords = _straightNorthRoute();
      final match = findNearestInWindow(
        position: _position(coords[20][1], coords[20][0]),
        coordinates: coords,
        currentIndex: 15,
        windowSize: 40,
      );
      expect(match.distanceMeters, lessThan(150.0));
    });

    test('Position 200m von Route entfernt ist OFF-Route', () {
      final coords = _straightNorthRoute();

      // 200m östlich (1 Grad Lng ≈ 75km, also 0.002 Lng ≈ 150m)
      final match = findNearestInWindow(
        position: _position(48.05, 11.583), // ~200m östlich
        coordinates: coords,
        currentIndex: 40,
        windowSize: 40,
      );
      expect(match.distanceMeters, greaterThan(150.0));
    });

    test('Simulation Off-Route Zähler: 5 aufeinanderfolgende Treffer nötig', () {
      // Test der Logik-Schwelle
      const offRouteThreshold = 150.0;
      const offRouteCountThreshold = 5;

      final coords = _straightNorthRoute();
      var offRouteCount = 0;

      // 5 aufeinanderfolgende off-route updates
      for (var i = 0; i < offRouteCountThreshold; i++) {
        final match = findNearestInWindow(
          position: _position(48.05, 11.595), // weit daneben
          coordinates: coords,
          currentIndex: 0,
          windowSize: coords.length,
        );
        if (match.distanceMeters > offRouteThreshold) offRouteCount++;
      }

      expect(offRouteCount, offRouteCountThreshold,
          reason: 'Alle 5 Updates sollen off-route sein');
    });

    test('Wenn wieder auf Route: Off-Route Zähler reset', () {
      const offRouteThreshold = 150.0;
      final coords = _straightNorthRoute();
      var offRouteCount = 0;

      // 3 off-route
      for (var i = 0; i < 3; i++) {
        final m = findNearestInWindow(
          position: _position(48.05, 11.595),
          coordinates: coords,
          currentIndex: 0,
          windowSize: coords.length,
        );
        if (m.distanceMeters > offRouteThreshold) offRouteCount++;
      }

      // Wieder auf Route → reset
      final onRoute = findNearestInWindow(
        position: _position(coords[20][1], coords[20][0]),
        coordinates: coords,
        currentIndex: 15,
        windowSize: 40,
      );
      if (onRoute.distanceMeters <= offRouteThreshold) offRouteCount = 0;

      expect(offRouteCount, 0, reason: 'Counter soll nach On-Route-Treffer resettet sein');
    });
  });

  group('findNearestInWindow – Routenfortschritt', () {
    test('Index steigt mit User-Bewegung nach vorne', () {
      final coords = _straightNorthRoute(points: 50);

      final match1 = findNearestInWindow(
        position: _position(coords[10][1], coords[10][0]),
        coordinates: coords,
        currentIndex: 0,
        windowSize: 20,
      );

      final match2 = findNearestInWindow(
        position: _position(coords[20][1], coords[20][0]),
        coordinates: coords,
        currentIndex: match1.index,
        windowSize: 20,
      );

      expect(match2.index, greaterThanOrEqualTo(match1.index));
    });

    test('Route-Ende erkannt: letzter Index nahe dem Endpunkt', () {
      final coords = _straightNorthRoute(points: 20);

      final match = findNearestInWindow(
        position: _position(coords.last[1], coords.last[0]),
        coordinates: coords,
        currentIndex: coords.length - 5,
        windowSize: 10,
      );
      expect(match.index, greaterThan(coords.length - 4));
    });
  });
}
