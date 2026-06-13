import 'package:cruise_connect/data/services/route_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;

/// 2026-06-13 (vucko Manöver-26km-Bug): Auf einem selbstüberlappenden Rundkurs
/// (gleiche Straße Hin- und Rückweg) darf der globale Re-Snap den Fortschritts-
/// Index NICHT auf den geografisch nahen, aber routen-fernen Selbstüberlapp
/// teleportieren — sonst schießt das nächste Manöver ans Routenende.
void main() {
  geo.Position pos(double lat, double lng) => geo.Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime(2026, 6, 13),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 10,
        speedAccuracy: 0,
      );

  // Out-and-back auf DERSELBEN Linie: idx 0..100 nach Osten, idx 100..200
  // zurück nach Westen. idx k und idx (200-k) liegen ~am selben Ort.
  List<List<double>> outAndBackRoute() {
    final coords = <List<double>>[];
    const lat = 47.4;
    for (var i = 0; i <= 100; i++) {
      coords.add([9.70 + i * 0.0001, lat]); // Osten
    }
    for (var i = 99; i >= 0; i--) {
      coords.add([9.70 + i * 0.0001, lat]); // zurück nach Westen
    }
    return coords; // 201 Punkte, idx 100 = Wendepunkt (östlichster)
  }

  test('Re-Snap bleibt am NAHEN Index bei Selbstüberlappung (kein Teleport)',
      () {
    final route = outAndBackRoute();
    // Puck am Ort von idx 50 (Hinweg). Der Zwilling idx 150 (Rückweg) liegt am
    // selben Ort. referenceIndex=48 → der NAHE Index (≈50) muss gewinnen.
    final p = pos(route[50][1], route[50][0]);
    final match = findNearestOnRoutePreferIndex(
      position: p,
      coordinates: route,
      referenceIndex: 48,
      corridorMeters: 50,
    );
    expect(
      match.index,
      lessThan(105),
      reason: 'Index darf nicht auf den fernen Rückweg-Zwilling (~150) springen',
    );
    expect((match.index - 50).abs(), lessThan(6));
  });

  test('Re-Snap holt vorgelaufenen Puck heran (Fenster-Verzug)', () {
    final route = outAndBackRoute();
    // Puck am Ort von idx 70, referenceIndex hängt bei 40 (Fenster nachgehinkt).
    final p = pos(route[70][1], route[70][0]);
    final match = findNearestOnRoutePreferIndex(
      position: p,
      coordinates: route,
      referenceIndex: 40,
      corridorMeters: 50,
    );
    // Erwartet: Hinweg-Cluster um ~70 (NICHT der ferne Zwilling ~130).
    expect(match.index, greaterThan(55));
    expect(match.index, lessThan(105));
  });

  test('Echtes Off-Route gibt global-nächsten zurück (für Distanz)', () {
    final route = outAndBackRoute();
    // Puck weit weg von der Route (~600m nördlich).
    final p = pos(47.4054, route[50][0]);
    final match = findNearestOnRoutePreferIndex(
      position: p,
      coordinates: route,
      referenceIndex: 48,
      corridorMeters: 50,
    );
    expect(match.distanceMeters, greaterThan(50));
  });
}
