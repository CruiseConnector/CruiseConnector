import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/domain/models/saved_route.dart';

/// 2026-07-28 (vucko Export-Bild): Auf der geteilten Karte stand
/// „26,7 km · 9h 1m" — rechnerisch 3 km/h. Der gespeicherte Wert war Müll
/// (eine angehaltene Fahrt, die stundenlang mitlief) und wanderte ungeprüft
/// in ein Bild, das Nutzer öffentlich teilen.
///
/// Regel jetzt: Ein gespeicherter Wert zählt nur, wenn er zu einer plausiblen
/// Durchschnittsgeschwindigkeit führt (8–200 km/h). Sonst greift die
/// stilbasierte Schätzung.
void main() {
  SavedRoute route({
    required double km,
    double? sekunden,
    String stil = 'Kurvenjagd',
  }) => SavedRoute(
    id: 'test',
    createdAt: DateTime(2026, 7, 28),
    style: stil,
    distanceKm: km,
    geometry: const {},
    durationSeconds: sekunden,
  );

  test('genau der Fall aus dem Screenshot wird korrigiert', () {
    // 26,7 km in 9h 1m = 32460 s -> 2,96 km/h. Unmoeglich.
    final r = route(km: 26.7, sekunden: 32460.0);
    expect(r.durationLabelOrEstimate, isNot(contains('9h')));
    // Kurvenjagd rechnet mit 46 km/h -> rund 35 min.
    expect(r.durationLabelOrEstimate, '35 min');
  });

  test('plausible gespeicherte Dauer bleibt unangetastet', () {
    // 48,9 km in 1h 10m = 4200 s -> 41,9 km/h. Passt zu Kurvenjagd.
    final r = route(km: 48.9, sekunden: 4200.0);
    expect(r.durationLabelOrEstimate, '1h 10m');
  });

  test('absurd schnelle Dauer wird ebenfalls verworfen', () {
    // 100 km in 120 s = 3000 km/h.
    final r = route(km: 100, sekunden: 120.0);
    expect(r.durationLabelOrEstimate, isNot('2 min'));
  });

  test('fehlende Dauer schaetzt nach Stil', () {
    expect(route(km: 46, stil: 'Kurvenjagd').durationLabelOrEstimate, '1h');
    expect(route(km: 66, stil: 'Sport Mode').durationLabelOrEstimate, '1h');
  });

  test('ohne Distanz keine Erfindung', () {
    expect(route(km: 0).durationLabelOrEstimate, '--');
  });

  test('Grenzfaelle der Plausibilitaet', () {
    // Genau 8 km/h (unterste erlaubte Grenze) zaehlt noch.
    final langsam = route(km: 8, sekunden: 3600.0);
    expect(langsam.durationLabelOrEstimate, '1h');
    // Knapp darunter nicht mehr.
    final zuLangsam = route(km: 7, sekunden: 3600.0);
    expect(zuLangsam.durationLabelOrEstimate, isNot('1h'));
  });
}
