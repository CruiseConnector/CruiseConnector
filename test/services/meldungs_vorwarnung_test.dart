import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/road_incident_geofence.dart';
import 'package:cruise_connect/domain/models/road_incident.dart';

/// 2026-08-20, Vucko: „Die neue Funktion mit Unfaelle melden, Baustellen und
/// auch Stau ist leider noch nicht so funktional." Und zu den Abfragen:
/// „jetzt nicht, wenn es ja ein [unklar] oder so."
///
/// GEMESSENE AUSGANGSLAGE: In `road_incident_votes` steht seit dem 24.07.
/// keine einzige Zeile. Der Geofence hat also nie ausgeloest, weil die
/// Meldungen vorher abliefen. Sobald er ausloest, muss er zwei Dinge richtig
/// machen, die er vorher NICHT konnte:
///
///   1. Bei Autobahntempo frueh genug warnen. Die feste 200-m-Grenze waren bei
///      100 km/h 7,2 Sekunden.
///   2. Je Meldung nur EINMAL je Fahrt ausloesen. Der Re-Arm ueber 600 m hat
///      auf einem Rundkurs oder beim Zurueckfahren derselben Strasse dieselbe
///      Baustelle mehrfach aufgemacht.
///
/// Beide Gruppen unten waeren mit dem Stand vom 24.07. rot.
void main() {
  group('Vorwarnung haengt am Tempo', () {
    test('im Stand bleibt es bei der bisherigen Untergrenze von 200 m', () {
      expect(meldungsVorwarnungMeter(0.0), 200.0);
    });

    test('ohne bekanntes Tempo bleibt es bei 200 m', () {
      expect(meldungsVorwarnungMeter(null), 200.0);
      expect(meldungsVorwarnungMeter(double.nan), 200.0);
      expect(meldungsVorwarnungMeter(-3.0), 200.0);
    });

    test('50 km/h ergeben 250 m, also 18 Sekunden Vorlauf', () {
      // 13,9 m/s * 18 s = 250,2 m
      expect(meldungsVorwarnungMeter(13.9), closeTo(250.2, 0.1));
    });

    test('100 km/h ergeben 500 m statt der alten 200 m', () {
      // Genau der Fall aus dem Auftrag: 200 m waren hier 7,2 Sekunden.
      final meter = meldungsVorwarnungMeter(27.8);
      expect(meter, closeTo(500.4, 0.1));
      expect(meter / 27.8, closeTo(18.0, 0.01));
    });

    test('sehr schnelle Fahrt wird bei 900 m gedeckelt', () {
      // Ohne Deckel waere bei 200 km/h vor etwas gewarnt worden, das noch eine
      // Anschlussstelle weit weg ist.
      expect(meldungsVorwarnungMeter(55.6), 900.0);
    });
  });

  group('Geofence loest bei Autobahntempo frueh genug aus', () {
    test('300 m vor der Baustelle: bei 100 km/h ja, im Stand nein', () {
      final baustelle = _meldung('a');

      final schnell = RoadIncidentGeofence()..setIncidents([baustelle]);
      final trefferSchnell = schnell.processPosition(
        latitude: _latInAbstand(baustelle, 300),
        longitude: baustelle.longitude,
        speedMetersPerSecond: 27.8,
      );
      expect(trefferSchnell, hasLength(1),
          reason: 'bei 100 km/h muss 300 m vorher gewarnt werden');

      final langsam = RoadIncidentGeofence()..setIncidents([baustelle]);
      final trefferLangsam = langsam.processPosition(
        latitude: _latInAbstand(baustelle, 300),
        longitude: baustelle.longitude,
        speedMetersPerSecond: 0.0,
      );
      expect(trefferLangsam, isEmpty,
          reason: 'im Stand bleibt es beim bisherigen 200-m-Ring');
    });

    test('150 m loest auch ohne Tempoangabe aus, wie bisher', () {
      final baustelle = _meldung('b');
      final fence = RoadIncidentGeofence()..setIncidents([baustelle]);
      expect(
        fence.processPosition(
          latitude: _latInAbstand(baustelle, 150),
          longitude: baustelle.longitude,
        ),
        hasLength(1),
      );
    });
  });

  group('je Meldung nur einmal pro Fahrt', () {
    test('zweite Vorbeifahrt auf dem Rundkurs fragt nicht erneut', () {
      final baustelle = _meldung('c');
      final fence = RoadIncidentGeofence()..setIncidents([baustelle]);

      // Erste Vorbeifahrt: annaehern, ausloesen, weit wegfahren.
      expect(
        fence.processPosition(
          latitude: _latInAbstand(baustelle, 150),
          longitude: baustelle.longitude,
        ),
        hasLength(1),
      );
      expect(
        fence.processPosition(
          latitude: _latInAbstand(baustelle, 4000),
          longitude: baustelle.longitude,
        ),
        isEmpty,
      );

      // Zweite Runde ueber dieselbe Stelle. Vorher htte der Re-Arm ueber
      // 600 m die Baustelle erneut aufgemacht.
      expect(
        fence.processPosition(
          latitude: _latInAbstand(baustelle, 150),
          longitude: baustelle.longitude,
        ),
        isEmpty,
        reason: 'dieselbe Meldung darf je Fahrt nur einmal fragen',
      );
    });

    test('ein Nachladen der Meldungen setzt das nicht zurueck', () {
      final baustelle = _meldung('d');
      final fence = RoadIncidentGeofence()..setIncidents([baustelle]);
      fence.processPosition(
        latitude: _latInAbstand(baustelle, 150),
        longitude: baustelle.longitude,
      );

      // Der Auffrisch-Takt laedt alle fuenf Minuten nach und ruft dabei
      // setIncidents mit derselben Meldung erneut auf. Wuerde das den Zustand
      // loeschen, waere die Obergrenze wirkungslos.
      fence.setIncidents([baustelle]);
      expect(
        fence.processPosition(
          latitude: _latInAbstand(baustelle, 4000),
          longitude: baustelle.longitude,
        ),
        isEmpty,
      );
      expect(
        fence.processPosition(
          latitude: _latInAbstand(baustelle, 150),
          longitude: baustelle.longitude,
        ),
        isEmpty,
      );
    });

    test('clear beim Routenwechsel gibt die Meldung wieder frei', () {
      final baustelle = _meldung('e');
      final fence = RoadIncidentGeofence()..setIncidents([baustelle]);
      fence.processPosition(
        latitude: _latInAbstand(baustelle, 150),
        longitude: baustelle.longitude,
      );

      fence.clear();
      fence.setIncidents([baustelle]);
      expect(
        fence.processPosition(
          latitude: _latInAbstand(baustelle, 150),
          longitude: baustelle.longitude,
        ),
        hasLength(1),
        reason: 'eine neue Fahrt ist eine neue Fahrt',
      );
    });
  });
}

RoadIncident _meldung(String id) {
  final jetzt = DateTime.now().toUtc();
  return RoadIncident(
    id: id,
    type: RoadIncidentType.baustelle,
    latitude: 47.5,
    longitude: 9.75,
    createdAt: jetzt,
    expiresAt: jetzt.add(const Duration(days: 14)),
    confirmedCount: 1,
    dismissedCount: 0,
    active: true,
  );
}

/// Breitengrad in [meter] Abstand noerdlich der Meldung. Ein Grad Breite sind
/// 111.320 m, unabhaengig vom Laengengrad.
double _latInAbstand(RoadIncident incident, double meter) {
  return incident.latitude + meter / 111320.0;
}
