// 2026-09-01 — Vucko:
//   "die routen die jetzt im routenpool gespeichert sind und genehmigt werden
//    von der app keine wendepunkte mitten auf den strassen erlauben"
//
// Vorgeschichte: Auf seiner Testfahrt hat ihn die App mitten auf der Strasse
// umdrehen lassen. Vorher schon: "ich moechte das die routenqualitaet besser
// ist und den nutzer niemals in keiner situation dazu auffordert irgendwo auf
// einer strasse umzudrehen oder in eine gasse zum fahren nur um gleich wieder
// umzudrehen".
//
// WAS GEMESSEN WURDE (01.09., Produktionsdatenbank, alle 2778 Pool-Zeilen):
//   2047 Zeilen (73,7 Prozent) enthalten eine Wende MITTENDRIN.
//   731 sind sauber, und alle 731 sind startseitentauglich.
//   51 der 53 Gebiete behalten saubere Strecken. Leer wuerden nur Mariazell
//   und Bludenz — zwei Alpentaeler, in denen hin und zurueck oft die einzige
//   Strasse ist.
//
// DAS TOR SITZT AN ZWEI STELLEN, UND ZWAR UNTERSCHIEDLICH:
//
//   Startseite  -> HARTER AUSSCHLUSS. Dort liegen 120 Kandidaten im Umkreis
//                  von 100 km, es rueckt praktisch immer eine nach. Eine leere
//                  Kachel waere ohnehin der harmlosere Fehler.
//   Pool-Suche  -> NUR SORTIERUNG. Dieser Weg ist selbst schon der Rueckfall,
//                  wenn die Live-Erzeugung nichts geliefert hat. Ein harter
//                  Ausschluss haette dort aus "Route mit Wende" ein "keine
//                  Route" gemacht, und das ist der schlechtere Ausgang.
//
// Beides einzeln festgenagelt, damit niemand die eine Regel fuer die andere
// haelt und sie angleicht.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/home_route_recommendation_service.dart';
import 'package:cruise_connect/data/services/route_pool_service.dart';
import 'package:cruise_connect/domain/models/route_pool_entry.dart';
import 'package:cruise_connect/domain/models/route_region.dart';

RoutePoolEntry poolStrecke({
  required String id,
  int? kehrtwendenMitte = 0,
  double startLat = 47.5,
  double startLng = 9.7,
  double qualityScore = 90,
  double weeklyRotationScore = 50,
}) {
  return RoutePoolEntry(
    id: id,
    countryCode: 'AT',
    admin1Name: 'Vorarlberg',
    cityCluster: 'bregenz',
    startLat: startLat,
    startLng: startLng,
    distanceKm: 50,
    distanceBucket: 50,
    routeType: 'ROUND_TRIP',
    styleTags: const ['Standard'],
    avoidsHighway: false,
    hasHighway: false,
    qualityScore: qualityScore,
    verified: true,
    geometry: const {},
    routePayload: const {},
    punktAnzahl: 500,
    maxSegmentMeter: 100,
    geometrieQuelle: 'graphhopper',
    autobahnVerstoss: false,
    kehrtwendenMitte: kehrtwendenMitte,
    weeklyRotationScore: weeklyRotationScore,
  );
}

RoutePoolEntry startseitenStrecke({int? kehrtwendenMitte = 0}) =>
    poolStrecke(id: 'x', kehrtwendenMitte: kehrtwendenMitte);

void main() {
  group('Die Startseite schlaegt keine Wende-Strecke vor', () {
    test('eine Strecke MIT Wende mittendrin wird abgelehnt', () {
      expect(
        HomeRouteRecommendationService.istSichereStartseitenStrecke(
          startseitenStrecke(kehrtwendenMitte: 1),
        ),
        isFalse,
        reason:
            'Genau das hat Vucko gefahren: mitten auf der Strasse umdrehen. '
            'Auf der Startseite gibt es 120 Kandidaten, es rueckt eine nach.',
      );
      expect(
        HomeRouteRecommendationService.istSichereStartseitenStrecke(
          startseitenStrecke(kehrtwendenMitte: 4),
        ),
        isFalse,
      );
    });

    test('eine NICHT gemessene Strecke wird ebenfalls abgelehnt', () {
      // null heisst "weiss ich nicht", und eine unpruefbare Strecke gehoert
      // nicht auf die Startseite. Dieselbe Regel gilt dort schon fuer die
      // vier aelteren Kennzahlen.
      expect(
        HomeRouteRecommendationService.istSichereStartseitenStrecke(
          startseitenStrecke(kehrtwendenMitte: null),
        ),
        isFalse,
      );
    });

    test('eine saubere Strecke bleibt zulaessig', () {
      expect(
        HomeRouteRecommendationService.istSichereStartseitenStrecke(
          startseitenStrecke(kehrtwendenMitte: 0),
        ),
        isTrue,
        reason:
            'Sonst waere das Tor kein Tor, sondern eine Mauer — dann zeigte '
            'die Startseite gar nichts mehr.',
      );
    });

    test('die Kennzahl wird auch wirklich mitgeladen', () {
      // Ein Filter ueber eine Spalte, die die Abfrage nicht holt, urteilt
      // immer ueber null — und wuerde damit ALLES ablehnen.
      final quelle = File(
        'lib/data/services/home_route_recommendation_service.dart',
      ).readAsStringSync();
      expect(
        quelle.contains('kehrtwenden_mitte'),
        isTrue,
        reason:
            'Ohne die Spalte in _routePoolSelect bekaeme der Filter immer '
            'null und die Startseite bliebe dauerhaft leer.',
      );
    });
  });

  group('Der Startseiten-Cache verliert die Kennzahlen nicht', () {
    test('toJson und fromJson erhalten alle fuenf Messwerte', () {
      // Der Filter urteilt AUSSCHLIESSLICH ueber Kennzahlen, seit die
      // Geometrie bewusst nicht mehr mitgeladen wird. Fielen sie beim
      // Zwischenspeichern heraus, kaeme aus dem Cache eine Strecke zurueck,
      // die kein Tor mehr passieren kann.
      final vorher = poolStrecke(id: 'cache', kehrtwendenMitte: 0);
      final nachher = RoutePoolEntry.fromJson(vorher.toJson());

      expect(nachher.kehrtwendenMitte, 0);
      expect(nachher.punktAnzahl, 500);
      expect(nachher.maxSegmentMeter, 100);
      expect(nachher.geometrieQuelle, 'graphhopper');
      expect(nachher.autobahnVerstoss, false);
      expect(
        HomeRouteRecommendationService.istSichereStartseitenStrecke(nachher),
        isTrue,
        reason: 'Nach dem Umweg ueber den Cache muss dasselbe Urteil stehen.',
      );
    });

    test('eine Wende-Strecke bleibt auch nach dem Cache abgelehnt', () {
      final nachher = RoutePoolEntry.fromJson(
        poolStrecke(id: 'cache2', kehrtwendenMitte: 2).toJson(),
      );
      expect(nachher.kehrtwendenMitte, 2);
      expect(
        HomeRouteRecommendationService.istSichereStartseitenStrecke(nachher),
        isFalse,
      );
    });
  });

  group('Die Pool-Suche stellt saubere Strecken nach vorn', () {
    final regionen = <RouteRegion>[];

    RoutePoolQuery frage() => const RoutePoolQuery(
      userLat: 47.5,
      userLng: 9.7,
      countryCode: 'AT',
      admin1Name: 'Vorarlberg',
      cityCluster: 'bregenz',
      distanceBucket: 50,
      routeType: 'ROUND_TRIP',
      style: 'Standard',
      avoidHighways: false,
    );

    test('die saubere Strecke gewinnt gegen die mit Wende', () {
      final treffer = RoutePoolService.findMatches(
        query: frage(),
        candidates: [
          poolStrecke(id: 'mit-wende', kehrtwendenMitte: 3),
          poolStrecke(id: 'sauber', kehrtwendenMitte: 0),
        ],
        regions: regionen,
        relaxStyle: true,
      );
      expect(treffer, isNotEmpty);
      expect(
        treffer.first.route.id,
        'sauber',
        reason: 'Wer nicht umdrehen muss, kommt zuerst.',
      );
    });

    test('die Wende-Strecke wird NICHT verworfen', () {
      // Wichtig: Dieser Weg ist selbst schon der Rueckfall. Ein harter
      // Ausschluss haette hier "keine Route" erzeugt, und das ist schlimmer
      // als eine Route mit Wende.
      final treffer = RoutePoolService.findMatches(
        query: frage(),
        candidates: [poolStrecke(id: 'nur-diese', kehrtwendenMitte: 2)],
        regions: regionen,
        relaxStyle: true,
      );
      expect(
        treffer.map((t) => t.route.id),
        contains('nur-diese'),
        reason:
            'Gibt es nichts Besseres, faehrt der Nutzer lieber mit einer '
            'Wende als gar nicht.',
      );
    });

    test('die Wende schlaegt sogar die Rotation', () {
      // Die Rotation sorgt dafuer, dass nicht immer dieselbe Strecke kommt.
      // Sie darf aber keine Wende-Strecke nach vorn holen: lieber zweimal
      // dieselbe saubere Runde als einmal eine, die zum Umdrehen zwingt.
      final treffer = RoutePoolService.findMatches(
        query: frage(),
        candidates: [
          poolStrecke(
            id: 'mit-wende-hohe-rotation',
            kehrtwendenMitte: 1,
            weeklyRotationScore: 100,
          ),
          poolStrecke(
            id: 'sauber-niedrige-rotation',
            kehrtwendenMitte: 0,
            weeklyRotationScore: 1,
          ),
        ],
        regions: regionen,
        relaxStyle: true,
      );
      expect(treffer.first.route.id, 'sauber-niedrige-rotation');
    });

    test('eine ungemessene Strecke wird hier NICHT bestraft', () {
      // Die Reserve aus route_pool_candidates fuehrt die Kennzahl gar nicht.
      // Sie hinten anzustellen wuerde sie entwerten, ohne etwas ueber ihre
      // Qualitaet zu wissen.
      final treffer = RoutePoolService.findMatches(
        query: frage(),
        candidates: [
          poolStrecke(id: 'mit-wende', kehrtwendenMitte: 1),
          poolStrecke(id: 'ungemessen', kehrtwendenMitte: null),
        ],
        regions: regionen,
        relaxStyle: true,
      );
      expect(treffer.first.route.id, 'ungemessen');
    });
  });
}
