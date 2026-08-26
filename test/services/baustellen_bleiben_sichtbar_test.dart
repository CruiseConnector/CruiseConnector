import 'dart:io';
import 'dart:math' as math;

import 'package:cruise_connect/data/services/road_incident_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-26 (vucko, Sprachnachricht 06:02): „Bei der ersten Fahrt habe ich
/// eine Baustelle gemeldet, bei der zweiten bin ich dieselbe Strecke
/// zurueckgefahren, aber die Meldung war auf einmal weg."
///
/// An der Produktionsdatenbank gemessen: die Meldung war NIE weg. Alle drei
/// Meldungen vom 25./26.08. stehen mit Frist bis 08./09.09. aktiv in der
/// Tabelle. Es war ein reiner Anzeigefehler, und der lag hier: Die Pruefung
/// „liegt die Meldung auf meiner Route" duennte die Route auf FESTE 80
/// Stuetzpunkte aus und mass dann Punkt zu Punkt statt zur Linie.
///
/// Gemessen an echten Routen: bei 92 km lagen 47 Prozent der Strecke weiter als
/// 200 m von der naechsten Stichprobe entfernt, bei 107 km 55 Prozent.
void main() {
  // Eine schnurgerade Strecke von 10 km, wie sie GraphHopper auf einer
  // Schnellstrasse liefert: wenige Stuetzpunkte, weit auseinander.
  List<List<double>> gerade({required int punkte, double laengeKm = 10}) {
    const lat = 47.30;
    const lng0 = 9.60;
    final mProGradLng = 111320.0 * math.cos(lat * math.pi / 180);
    final schritt = (laengeKm * 1000) / (punkte - 1) / mProGradLng;
    return [for (var i = 0; i < punkte; i++) [lng0 + i * schritt, lat]];
  }

  double abstand(List<List<double>> route, double lat, double lng) =>
      RoadIncidentService.abstandZurRouteMeter(
        latitude: lat,
        longitude: lng,
        routeCoordinates: route,
      );

  group('Eine Meldung auf der eigenen Route wird gefunden', () {
    test('mitten auf einem langen Abschnitt: Abstand ist null, nicht kilometerweit', () {
      // Zwei Stuetzpunkte, 10 km auseinander. Die Baustelle liegt genau in der
      // Mitte, also EXAKT auf der Strasse.
      final route = gerade(punkte: 2);
      final mitteLng = (route.first[0] + route.last[0]) / 2;
      final d = abstand(route, 47.30, mitteLng);
      expect(d, lessThan(1.0),
          reason: 'die Meldung liegt auf der Linie, Abstand muss null sein');
      // Zur Gegenprobe: der Abstand zum naechsten STUETZPUNKT waere 5 km —
      // genau daran ist die alte Pruefung gescheitert.
      final zumEckpunkt = 5000.0;
      expect(zumEckpunkt, greaterThan(200.0),
          reason: 'so weit war der naechste Stuetzpunkt entfernt');
    });

    test('der Filter nimmt sie jetzt mit, egal wie grob die Route abgetastet ist', () {
      final grob = gerade(punkte: 2);
      final fein = gerade(punkte: 400);
      final mitteLng = (grob.first[0] + grob.last[0]) / 2;
      // Dieselbe Baustelle, zwei verschiedene Punktlisten derselben Strasse —
      // genau die Situation Hinweg gegen Rueckweg.
      expect(abstand(grob, 47.30, mitteLng), lessThan(1.0));
      expect(abstand(fein, 47.30, mitteLng), lessThan(1.0));
    });

    test('quer daneben wird weiterhin richtig gemessen', () {
      final route = gerade(punkte: 2);
      final mitteLng = (route.first[0] + route.last[0]) / 2;
      // 300 m noerdlich der Strasse: rund 0,0027 Grad Breite.
      final d = abstand(route, 47.30 + 300 / 111320.0, mitteLng);
      expect(d, closeTo(300, 15));
    });

    test('eine Meldung zwei Strassen weiter faellt heraus', () {
      final route = gerade(punkte: 2);
      final mitteLng = (route.first[0] + route.last[0]) / 2;
      final d = abstand(route, 47.30 + 600 / 111320.0, mitteLng);
      expect(d, greaterThan(200.0), reason: '600 m daneben ist nicht auf der Route');
    });

    test('vor dem Anfang und hinter dem Ende zaehlt der Endpunkt', () {
      final route = gerade(punkte: 2);
      // 1 km vor dem Start auf derselben Linie.
      final mProGradLng = 111320.0 * math.cos(47.30 * math.pi / 180);
      final davor = route.first[0] - 1000 / mProGradLng;
      expect(abstand(route, 47.30, davor), closeTo(1000, 30));
    });

    test('unbrauchbare Route ergibt unendlich statt eines Absturzes', () {
      expect(abstand(const [], 47.3, 9.6), double.infinity);
      expect(abstand(const [[9.6, 47.3]], 47.3, 9.6), double.infinity);
    });
  });

  test('Quelltext-Waechter: keine Stichproben-Pruefung mehr', () {
    // Kehrt das Ausduennen auf feste Stichproben zurueck, kehrt der Fehler
    // zurueck. Deshalb hier festgenagelt.
    final quelle = File(
      'lib/data/services/road_incident_service.dart',
    ).readAsStringSync();
    expect(quelle.contains('targetSamples'), isFalse,
        reason: 'Abstand IMMER gegen die Streckenabschnitte messen, '
            'nie gegen ausgeduennte Stuetzpunkte');
  });
}
