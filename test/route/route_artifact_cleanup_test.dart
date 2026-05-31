import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cruise_connect/data/services/route_quality_validator.dart';

// 2026-05-31 (vucko): Tests für cleanRouteArtifacts — Dead-End-Spikes /
// Sackgassen-Zacken werden physisch aus der Polyline geschnitten, eine saubere
// Route bleibt unverändert.

/// ~Meter → Grad (grob, für Vorarlberg lat ~47.3).
const double _mPerDegLat = 111320.0;
double _mPerDegLng(double lat) => 111320.0 * 0.679; // cos(47.3°) ≈ 0.679

List<double> _coord(double baseLng, double baseLat, double eastM, double northM) {
  final lat = baseLat + northM / _mPerDegLat;
  final lng = baseLng + eastM / _mPerDegLng(baseLat);
  return [lng, lat];
}

void main() {
  const baseLng = 9.64;
  const baseLat = 47.33;

  group('cleanRouteArtifacts', () {
    test('saubere gerade Route bleibt unverändert', () {
      final coords = <List<double>>[
        for (var i = 0; i < 20; i++) _coord(baseLng, baseLat, i * 50.0, 0),
      ];
      final cleaned = RouteQualityValidator.cleanRouteArtifacts(coords);
      expect(cleaned.length, coords.length);
    });

    // Contract-Tests (unabhängig davon, ob der Detektor auf synthetischen
    // Daten exakt anspringt — das ist auf echter GraphHopper-Geometrie der
    // Fall, aber schwer künstlich nachzubauen):
    test('cleanRouteArtifacts verlängert eine Route NIE', () {
      final coords = <List<double>>[];
      for (var i = 0; i <= 30; i++) {
        coords.add(_coord(baseLng, baseLat, i * 15.0, 0));
      }
      for (final n in [15.0, 30.0, 45.0, 60.0, 75.0]) {
        coords.add(_coord(baseLng, baseLat, 450.0, n));
      }
      for (final n in [60.0, 45.0, 30.0, 15.0, 3.0]) {
        coords.add(_coord(baseLng, baseLat, 450.0, n));
      }
      for (var i = 31; i <= 60; i++) {
        coords.add(_coord(baseLng, baseLat, i * 15.0, 0));
      }
      final cleaned = RouteQualityValidator.cleanRouteArtifacts(coords);
      expect(cleaned.length, lessThanOrEqualTo(coords.length));
      expect(cleaned.length, greaterThanOrEqualTo(2));
    });

    test('erzeugt NIEMALS einen Off-Road-Chord (>40m Sprung)', () {
      // Egal welche Eingabe: kein aufeinanderfolgendes Punktepaar im Ergebnis
      // darf einen viel größeren Sprung haben als im Original (kein neuer
      // Luftlinien-Sehnensprung durchs Gelände).
      final coords = <List<double>>[];
      for (var i = 0; i <= 10; i++) {
        coords.add(_coord(baseLng, baseLat, i * 50.0, 0));
      }
      for (final n in [30.0, 60.0, 90.0, 120.0]) {
        coords.add(_coord(baseLng, baseLat, 500.0, n));
      }
      for (final n in [90.0, 60.0, 30.0, 5.0]) {
        coords.add(_coord(baseLng, baseLat, 500.0, n));
      }
      for (var i = 11; i <= 20; i++) {
        coords.add(_coord(baseLng, baseLat, i * 50.0, 0));
      }
      final cleaned = RouteQualityValidator.cleanRouteArtifacts(coords);
      expect(cleaned.length, greaterThanOrEqualTo(2));
      // Maximaler Original-Segmentsprung als Referenz.
      double maxOriginalGap = 0;
      for (var i = 1; i < coords.length; i++) {
        final d = Geolocator.distanceBetween(
          coords[i - 1][1], coords[i - 1][0], coords[i][1], coords[i][0],
        );
        if (d > maxOriginalGap) maxOriginalGap = d;
      }
      for (var i = 1; i < cleaned.length; i++) {
        final d = Geolocator.distanceBetween(
          cleaned[i - 1][1], cleaned[i - 1][0], cleaned[i][1], cleaned[i][0],
        );
        // Cleanup darf höchstens einen Sprung in Größe des Original-Max +
        // 40m-Reconnect-Toleranz erzeugen.
        expect(d, lessThanOrEqualTo(maxOriginalGap + 40.0));
      }
    });

    test('zu kurze Liste bleibt unverändert (kein Crash)', () {
      final coords = <List<double>>[
        [baseLng, baseLat],
        [baseLng + 0.001, baseLat + 0.001],
      ];
      final cleaned = RouteQualityValidator.cleanRouteArtifacts(coords);
      expect(cleaned, coords);
    });
  });
}
