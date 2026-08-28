import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/core/kurven_zaehler.dart';
import 'package:cruise_connect/core/routen_kappung.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';

/// 2026-08-28 (vucko Fehler 8, Stalking-Schutz): Faehrt ein FREMDER Nutzer
/// eine geteilte Route, fehlen vorn und hinten je 1 km — sonst startet und
/// endet er an der Haustuer des Besitzers. Der Besitzer selbst faehrt sein
/// Original unveraendert. Zu kurze Routen (unter 2 km) starten gar nicht.
///
/// Nachgerechnet an einer synthetischen 10 km Linie (Punkte alle 100 m
/// exakt nach Norden), Toleranz 50 m laut Auftrag.
void main() {
  // 1 Grad Breite = pi * 6371000 / 180 Meter (derselbe Erdradius wie in
  // KurvenZaehler.distanzMeter, damit die Rechnung deckungsgleich ist).
  const meterProGradBreite = 111194.92664455873;
  const startLng = 9.7;
  const startLat = 47.4;

  List<List<double>> nordLinie({required double laengeMeter, double schrittMeter = 100}) {
    final punkte = <List<double>>[];
    for (var m = 0.0; m <= laengeMeter + 0.001; m += schrittMeter) {
      punkte.add([startLng, startLat + m / meterProGradBreite]);
    }
    return punkte;
  }

  double laengeMeter(List<List<double>> coords) {
    var meter = 0.0;
    for (var i = 1; i < coords.length; i++) {
      meter += KurvenZaehler.distanzMeter(coords[i - 1], coords[i]);
    }
    return meter;
  }

  SavedRoute routeMit({
    required Map<String, dynamic> geometry,
    required double distanceKm,
    String? userId = 'besitzer-1',
    double? durationSeconds = 600,
  }) {
    return SavedRoute(
      id: 'route-1',
      createdAt: DateTime(2026, 8, 28),
      style: 'Kurvenjagd',
      distanceKm: distanceKm,
      geometry: geometry,
      userId: userId,
      name: 'Hausrunde',
      durationSeconds: durationSeconds,
      routeType: 'ROUND_TRIP',
    );
  }

  group('kappeEndstuecke', () {
    test('10 km Linie verliert vorn und hinten je 1 km (Toleranz 50 m)', () {
      final coords = nordLinie(laengeMeter: 10000);
      expect(laengeMeter(coords), closeTo(10000, 5));

      final gekappt = kappeEndstuecke(coords, 1000, 1000);
      expect(gekappt, isNotEmpty);

      // Restlaenge 8 km.
      expect(laengeMeter(gekappt), closeTo(8000, 50));
      // Neuer Start liegt 1 km vom Original-Start entfernt.
      expect(
        KurvenZaehler.distanzMeter(coords.first, gekappt.first),
        closeTo(1000, 50),
      );
      // Neues Ende liegt 1 km vor dem Original-Ende.
      expect(
        KurvenZaehler.distanzMeter(coords.last, gekappt.last),
        closeTo(1000, 50),
      );
    });

    test('Route unter 2 km ergibt eine leere Liste', () {
      final coords = nordLinie(laengeMeter: 1500);
      expect(kappeEndstuecke(coords, 1000, 1000), isEmpty);
    });

    test('weniger als zwei Punkte ergeben eine leere Liste', () {
      expect(kappeEndstuecke(const [], 1000, 1000), isEmpty);
      expect(
        kappeEndstuecke(const [
          [9.7, 47.4],
        ], 1000, 1000),
        isEmpty,
      );
    });
  });

  group('SavedRoute.fuerFremdfahrt', () {
    test('Besitzer faehrt die eigene Route unveraendert', () {
      final route = routeMit(
        geometry: {
          'type': 'LineString',
          'coordinates': nordLinie(laengeMeter: 10000),
        },
        distanceKm: 10.0,
      );
      final ergebnis = route.fuerFremdfahrt('besitzer-1');
      expect(identical(ergebnis, route), isTrue);
    });

    test('Route ohne Besitzer (Pool, lokale Wiederaufnahme) bleibt unveraendert', () {
      final route = routeMit(
        geometry: {
          'type': 'LineString',
          'coordinates': nordLinie(laengeMeter: 10000),
        },
        distanceKm: 10.0,
        userId: null,
      );
      final ergebnis = route.fuerFremdfahrt('irgendwer');
      expect(identical(ergebnis, route), isTrue);
    });

    test('Fremder bekommt vorn und hinten 1 km weniger, Name und Stil bleiben', () {
      final coords = nordLinie(laengeMeter: 10000);
      final route = routeMit(
        geometry: {'type': 'LineString', 'coordinates': coords},
        distanceKm: 10.0,
      );

      final ergebnis = route.fuerFremdfahrt('fremder-1');
      expect(ergebnis, isNotNull);
      expect(identical(ergebnis, route), isFalse);

      // Distanz neu aus der Punktliste gerechnet: 8 km (Toleranz 50 m).
      expect(ergebnis!.distanceKm, closeTo(8.0, 0.05));

      final gekappt = SavedRoute.flattenGeometryCoordinates(ergebnis.geometry);
      expect(
        KurvenZaehler.distanzMeter(coords.first, gekappt.first),
        closeTo(1000, 50),
      );
      expect(
        KurvenZaehler.distanzMeter(coords.last, gekappt.last),
        closeTo(1000, 50),
      );

      // Name und Stil bleiben, die Kennung auch.
      expect(ergebnis.name, 'Hausrunde');
      expect(ergebnis.style, 'Kurvenjagd');
      expect(ergebnis.id, 'route-1');
      // Der offene Bogen laedt als A nach B (Muster der Wiederaufnahme).
      expect(ergebnis.routeType, 'POINT_TO_POINT');
      // Dauer proportional mitgekuerzt: 600 s auf 10 km werden ~480 s auf 8 km.
      expect(ergebnis.durationSeconds, isNotNull);
      expect(ergebnis.durationSeconds!, closeTo(480, 5));
    });

    test('MultiLineString (aufgezeichnete Fahrt mit GPS Luecke) wird gekappt', () {
      final coords = nordLinie(laengeMeter: 10000);
      final route = routeMit(
        geometry: {
          'type': 'MultiLineString',
          'coordinates': [
            coords.sublist(0, 50),
            coords.sublist(50),
          ],
        },
        distanceKm: 10.0,
      );
      final ergebnis = route.fuerFremdfahrt('fremder-1');
      expect(ergebnis, isNotNull);
      expect(ergebnis!.distanceKm, closeTo(8.0, 0.05));
    });

    test('zu kurze Route (unter 2 km) startet nicht: null', () {
      final route = routeMit(
        geometry: {
          'type': 'LineString',
          'coordinates': nordLinie(laengeMeter: 1500),
        },
        distanceKm: 1.5,
      );
      expect(route.fuerFremdfahrt('fremder-1'), isNull);
    });
  });
}
