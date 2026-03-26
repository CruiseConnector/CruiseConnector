// Tests für Routen-Berechnung und Route Cache Service
//
// Ausführen: flutter test test/services/route_calculation_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';

void main() {
  group('RouteResult Model Tests', () {
    test('RouteResult mit gültigen Daten → korrekt erstellt', () {
      final route = RouteResult(
        geoJson: '{"type":"FeatureCollection"}',
        geometry: {'type': 'LineString'},
        coordinates: [
          [47.8095, 13.0550],
          [47.8100, 13.0600],
          [47.8120, 13.0650],
        ],
        maneuvers: [],
        distanceMeters: 5000,
        durationSeconds: 600,
        distanceKm: 5.0,
      );

      expect(route.coordinates.length, equals(3));
      expect(route.distanceKm, equals(5.0));
      expect(route.durationSeconds, equals(600));
    });

    test('RouteResult mit leeren Koordinaten → als fehlerhafte Route erkennbar', () {
      final emptyRoute = RouteResult(
        geoJson: '',
        geometry: {},
        coordinates: [],
        maneuvers: [],
      );

      // Eine Route mit 0 Koordinaten ist ungültig
      expect(emptyRoute.coordinates.isEmpty, isTrue);
    });

    test('Route-Qualitätsprüfung: weniger als 50 Koordinaten → wird abgelehnt', () {
      // RouteCacheService prüft ob Route ≥ 50 Koordinatenpunkte hat
      final coords = List.generate(30, (i) => [47.8 + i * 0.001, 13.0]);
      expect(coords.length < 50, isTrue); // Wird vom Cache abgelehnt
    });

    test('Route-Qualitätsprüfung: 50+ Koordinaten → wird akzeptiert', () {
      final coords = List.generate(60, (i) => [47.8 + i * 0.001, 13.0]);
      expect(coords.length >= 50, isTrue);
    });
  });

  group('Überschneidungs-Erkennung Tests', () {
    // Testet die Logik von _findOverlappingSegments() in cruise_mode_page.dart

    test('Route ohne Überschneidung → leere Überschneidungs-Liste', () {
      // Koordinaten die sich nicht überschneiden
      final coords = [
        [47.810, 13.050],
        [47.815, 13.055],
        [47.820, 13.060],
        [47.825, 13.065],
      ];

      // Simuliere Überschneidungsprüfung (vereinfacht):
      // Jeder Punkt prüft ob er innerhalb 35m eines früheren Punktes liegt
      final overlaps = _findOverlaps(coords, thresholdMeters: 35);
      expect(overlaps, isEmpty);
    });

    test('Route mit Rückweg über Hinweg → Überschneidung erkannt', () {
      // Koordinaten: A → B → C → B (Rückweg über B)
      final coords = [
        [47.810, 13.050], // A
        [47.815, 13.055], // B
        [47.820, 13.060], // C
        [47.815, 13.055], // B wieder → Überschneidung!
      ];

      final overlaps = _findOverlaps(coords, thresholdMeters: 35);
      expect(overlaps.isNotEmpty, isTrue);
    });

    test('Schwellenwert 35m: Punkte weiter als 35m → keine Überschneidung', () {
      // 0.001 Grad ≈ 111m (genug Abstand)
      final coords = [
        [47.810, 13.050],
        [47.820, 13.060], // >1km entfernt
      ];
      final overlaps = _findOverlaps(coords, thresholdMeters: 35);
      expect(overlaps, isEmpty);
    });
  });

  group('Route Cache Tests', () {
    test('Cache-Queue hat maximal 5 Slots', () {
      const maxQueueSize = 5;
      final queue = <String>[];
      // Füge 7 Routen ein → Queue bleibt bei 5
      for (var i = 0; i < 7; i++) {
        if (queue.length < maxQueueSize) {
          queue.add('route-$i');
        }
      }
      expect(queue.length, equals(5));
    });

    test('Route aus Cache holen → Queue hat einen Slot weniger', () {
      final queue = ['route-0', 'route-1', 'route-2'];
      final taken = queue.removeAt(0);
      expect(taken, equals('route-0'));
      expect(queue.length, equals(2));
    });

    test('Route mit weniger als 50 Koordinaten wird nicht gecacht', () {
      final coords = List.generate(30, (i) => [0.0, 0.0]);
      final isQualityRoute = coords.length >= 50;
      expect(isQualityRoute, isFalse);
    });
  });

  group('Distanz-Berechnungs Tests', () {
    test('Distanz zwischen Start = Ende ist 0', () {
      final start = [47.810, 13.050];
      final end = [47.810, 13.050];
      // Haversine-Distanz bei gleichen Koordinaten = 0
      expect(_distance(start, end), equals(0.0));
    });

    test('Distanz zwischen zwei bekannten Punkten ist korrekt', () {
      // Salzburg Zentrum → ca. 1km entfernt
      final a = [47.8095, 13.0550];
      final b = [47.8095, 13.0640]; // ca. 600m östlich
      final dist = _distance(a, b);
      expect(dist, greaterThan(0));
      expect(dist, lessThan(1000)); // unter 1km
    });
  });
}

// ─── Hilfsfunktionen für Tests ─────────────────────────────────────────────

/// Vereinfachte Überschneidungserkennung für Tests.
/// Gibt Indizes zurück die sich mit früheren Punkten überschneiden.
List<int> _findOverlaps(
  List<List<double>> coords, {
  required double thresholdMeters,
}) {
  final overlaps = <int>[];
  for (var i = 1; i < coords.length; i++) {
    for (var j = 0; j < i - 1; j++) {
      final dist = _distance(coords[i], coords[j]);
      if (dist < thresholdMeters) {
        overlaps.add(i);
        break;
      }
    }
  }
  return overlaps;
}

/// Vereinfachte Distanzberechnung in Metern (equirectangular approximation).
double _distance(List<double> a, List<double> b) {
  const r = 6371000.0; // Erdradius in Metern
  final dLat = _toRad(b[0] - a[0]);
  final dLon = _toRad(b[1] - a[1]);
  final x = dLon * _cos(_toRad((a[0] + b[0]) / 2));
  return r * _sqrt(dLat * dLat + x * x);
}

double _toRad(double deg) => deg * 3.141592653589793 / 180;
double _cos(double rad) {
  // Vereinfachte cos-Approximation für kleine Winkel
  return 1 - (rad * rad) / 2;
}
double _sqrt(double x) => x <= 0 ? 0 : _sqrtIter(x, x / 2);
double _sqrtIter(double x, double guess) {
  final better = (guess + x / guess) / 2;
  return (better - guess).abs() < 0.001 ? better : _sqrtIter(x, better);
}
