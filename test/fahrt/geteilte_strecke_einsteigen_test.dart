// 2026-08-31 — Auftrag 11: „Teste selbst, ob der Fix vom letzten Mal wirkt."
//
// VUCKOS SZENARIO, woertlich aus der Sprachnachricht vom 31.08.:
//   „geteilte Route, 300 bis 400 Meter einsteigen, automatisch uebernehmen,
//    dass man nicht extra zu einem Startpunkt fahren muss."
//
// Was vorher passierte: Eine geteilte (also GELADENE, offene) Strecke dockte
// immer am Original-Start an. Wer sie fahren wollte, wurde erst dorthin
// gefuehrt, wo der Ersteller losgefahren war — oft vor dessen Haustuer, in
// Vuckos Fall mehrere Kilometer weit zu einer Tankstelle.
//
// Dieser Test faehrt die Strecke nicht, aber er prueft genau die
// Entscheidung, an der es haengt: welchen Einstiegspunkt der Planer waehlt.
// Das ist reine Rechnung ohne Netz, also belastbar wiederholbar.
//
// Er prueft BEIDE Richtungen:
//   * Solo steigt dort ein, wo der Fahrer steht.
//   * Die Gruppe erzwingt weiterhin den Original-Start — dort sollen alle
//     dieselbe Strecke fahren, und das darf der Fix nicht mit abgeraeumt
//     haben.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;

import 'package:cruise_connect/data/services/route_access_plan.dart';
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart'
    show andockRegelFuerGeteilteRoute;

/// Meter pro Grad Breite. Fuer eine Nord-Sued-Gerade genau genug, und der
/// Test rechnet damit in Metern statt in Gradbruchteilen.
const double _meterProGradBreite = 111320.0;

/// Eine schnurgerade Strecke nach Norden, Punkt alle [schrittMeter] Meter.
/// Damit ist „der Fahrer steht 350 m nach dem Start" exakt ausdrueckbar.
RouteResult geradeStrecke({
  int punkte = 400,
  double schrittMeter = 50,
  double startLat = 47.41,
  double startLng = 9.74,
}) {
  final coordinates = List.generate(
    punkte,
    (i) => [startLng, startLat + (i * schrittMeter) / _meterProGradBreite],
  );
  final geometry = {'type': 'LineString', 'coordinates': coordinates};
  final meter = schrittMeter * (punkte - 1);
  return RouteResult(
    geoJson: json.encode(geometry),
    geometry: geometry,
    coordinates: coordinates,
    maneuvers: const [],
    distanceMeters: meter,
    durationSeconds: meter / 16.0,
    distanceKm: meter / 1000.0,
  );
}

geo.Position stehtBei({required double lat, required double lng}) {
  return geo.Position(
    longitude: lng,
    latitude: lat,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

/// Die Position [meter] Meter nach dem Start auf der Geraden.
geo.Position aufDerStreckeBei(RouteResult route, double meter) {
  final start = route.coordinates.first;
  return stehtBei(
    lat: start[1] + meter / _meterProGradBreite,
    lng: start[0],
  );
}

void main() {
  const planer = RouteAccessPlanner();

  group('Solo: geteilte Strecke, 300 bis 400 m einsteigen', () {
    // Genau die Werte, die cruise_mode_page beim Solo-Fahrtstart uebergibt:
    // preferredJoinIndex: null, joinNearestForward: true (geladen und offen).
    RouteJoinPoint einstiegSolo(RouteResult route, geo.Position wo) {
      return planer.chooseJoinPoint(
        currentPosition: wo,
        existingRoute: route,
        preferredJoinIndex: null,
        rebaseClosedLoop: false,
        joinNearestForward: true,
      );
    }

    // Wie nah der Einstieg liegen KANN, ist keine freie Wahl: der Planer
    // tastet die Strecke in `Punktzahl ~/ 40` Schritten ab
    // (RouteAccessPlanner, joinNearestForward-Zweig). Bei der Teststrecke —
    // 400 Punkte im Abstand von 50 m, also 20 km — ist das jeder zehnte
    // Punkt, mithin ein Raster von 500 m. Ein Fahrer bei 350 m landet
    // deshalb auf 500 m: 150 m VORAUS.
    //
    // Genau darum geht es: 150 m weiterfahren ist in Ordnung, 350 m zurueck
    // zum Original-Start war die Beschwerde.
    const rasterMeter = 500.0;

    test('bei 350 m steigt der Fahrer vor sich ein, nicht am Start', () {
      final route = geradeStrecke();
      final einstieg = einstiegSolo(route, aufDerStreckeBei(route, 350));

      expect(
        einstieg.index,
        greaterThan(0),
        reason:
            'Index 0 heisst Original-Start. Bei einer Solo-Fahrt darf der '
            'nicht mehr erzwungen werden — das war Vuckos Beschwerde.',
      );
      expect(
        einstieg.index * 50.0,
        greaterThanOrEqualTo(350),
        reason:
            'Der Einstieg muss VOR dem Fahrer liegen. Ein Punkt hinter ihm '
            'hiesse umdrehen.',
      );
      expect(
        einstieg.distanceFromCurrentMeters,
        lessThanOrEqualTo(rasterMeter),
        reason:
            'Der Einstieg liegt weiter als ein Rasterschritt entfernt. Dann '
            'stimmt die Vorwaerts-Suche nicht mehr.',
      );
    });

    test('das gilt ueber das ganze Band 300 bis 400 m', () {
      final route = geradeStrecke();
      for (var meter = 300.0; meter <= 400.0; meter += 25) {
        final einstieg = einstiegSolo(route, aufDerStreckeBei(route, meter));
        expect(
          einstieg.index,
          greaterThan(0),
          reason: 'Bei $meter m wurde der Fahrer zum Original-Start geschickt.',
        );
        expect(
          einstieg.index * 50.0,
          greaterThanOrEqualTo(meter),
          reason: 'Bei $meter m liegt der Einstieg HINTER dem Fahrer.',
        );
        expect(
          einstieg.distanceFromCurrentMeters,
          lessThanOrEqualTo(rasterMeter),
          reason: 'Bei $meter m ist der Einstieg zu weit weg.',
        );
      }
    });

    test('auch weit drin, nicht nur am Anfang', () {
      final route = geradeStrecke();
      // 8 km in eine 20-km-Strecke hinein.
      final einstieg = einstiegSolo(route, aufDerStreckeBei(route, 8000));
      expect(einstieg.distanceFromCurrentMeters, lessThanOrEqualTo(rasterMeter));
      expect(einstieg.index * 50.0, greaterThanOrEqualTo(8000));
      expect(
        einstieg.remainingDistanceMeters,
        greaterThan(10000),
        reason: 'Ab dem Einstieg muessen noch rund 12 km uebrig sein.',
      );
    });

    test(
      'REGRESSION: mit der alten Einstellung wuerde er zum Start geschickt',
      () {
        // Der Gegenbeweis. Waere preferredJoinIndex weiterhin 0 — so stand es
        // bis zum 31.08. im Solo-Pfad — landete der Fahrer wieder am
        // Original-Start. Faellt dieser Test, ist der Test selbst stumpf
        // geworden und prueft nicht mehr, was er soll.
        final route = geradeStrecke();
        final alt = planer.chooseJoinPoint(
          currentPosition: aufDerStreckeBei(route, 350),
          existingRoute: route,
          preferredJoinIndex: 0,
          joinNearestForward: false,
        );
        expect(alt.index, 0);
        expect(
          alt.distanceFromCurrentMeters,
          greaterThan(300),
          reason:
              'Der alte Weg schickte den Fahrer nachweislich zurueck zum '
              'Original-Start.',
        );
      },
    );

    test('der Fahrer steht NEBEN der Strecke, nicht exakt darauf', () {
      // Im echten Leben steht niemand auf dem Meter genau auf der Linie.
      final route = geradeStrecke();
      final aufHoehe = aufDerStreckeBei(route, 350);
      // rund 40 m seitlich versetzt
      final daneben = stehtBei(
        lat: aufHoehe.latitude,
        lng: aufHoehe.longitude + 40 / (_meterProGradBreite * 0.676),
      );
      final einstieg = einstiegSolo(route, daneben);
      expect(einstieg.index, greaterThan(0));
      expect(
        einstieg.distanceFromCurrentMeters,
        lessThanOrEqualTo(rasterMeter + 60),
        reason: 'Ein Raster-Schritt plus der seitliche Versatz.',
      );
    });
  });

  group('Die Gruppe behaelt den Zwang zum Original-Start', () {
    test('geladene offene Route: Index 0, Zubringer, Hinweis', () {
      final regel = andockRegelFuerGeteilteRoute(
        istGeladeneRoute: true,
        endpunkteGeschlossen: false,
        flagIstRundkurs: false,
      );
      expect(
        regel.preferredJoinIndex,
        0,
        reason:
            'In der Gruppe sollen alle dieselbe Strecke fahren. Der Fix fuer '
            'die Solo-Fahrt darf das nicht mit abgeraeumt haben.',
      );
      expect(regel.zubringerErlaubt, isTrue);
      expect(
        regel.hinweisZumOriginalStart,
        isTrue,
        reason:
            'Wer zum Original-Start gefuehrt wird, muss das erfahren — sonst '
            'wirkt es wie der gemeldete komische Sprung.',
      );
      expect(
        regel.joinNearestForward,
        isFalse,
        reason: 'Vorwaerts-Andocken waere bei geladenen Routen die Abkuerzung.',
      );
    });

    test('geschlossene Runde setzt an der Geometrie auf', () {
      final regel = andockRegelFuerGeteilteRoute(
        istGeladeneRoute: true,
        endpunkteGeschlossen: true,
        flagIstRundkurs: false,
      );
      expect(regel.geschlossen, isTrue);
      expect(regel.rebaseClosedLoop, isTrue);
      expect(
        regel.preferredJoinIndex,
        isNull,
        reason: 'Eine Runde rotiert ueber jeden Meter, sie hat keinen Zwang.',
      );
    });
  });

  group('Die Verdrahtung stimmt an allen drei Stellen', () {
    // Direkt am Quelltext, damit niemand eine der Stellen unbemerkt
    // zurueckdreht. Es gibt genau drei Aufrufe von
    // buildAccessRouteToExistingRoute, und sie duerfen NICHT dasselbe tun.
    late List<String> aufrufe;

    setUpAll(() {
      final quelle = File(
        'lib/presentation/pages/cruise_mode_page.dart',
      ).readAsStringSync();
      aufrufe = <String>[];
      var ab = 0;
      while (true) {
        final i = quelle.indexOf('buildAccessRouteToExistingRoute(', ab);
        if (i < 0) break;
        // Bis zur schliessenden Klammer des Aufrufs, grosszuegig geschaetzt.
        aufrufe.add(quelle.substring(i, math.min(i + 2800, quelle.length)));
        ab = i + 1;
      }
    });

    test('es sind genau drei Stellen', () {
      expect(
        aufrufe.length,
        3,
        reason:
            'Erwartet: Gruppen-Pfad, Vorschau und Solo-Fahrtstart. Kommt eine '
            'vierte dazu, muss sie hier mit geprueft werden — sonst faehrt '
            'sie ungeprueft nach eigenen Regeln.',
      );
    });

    test('Gruppe: erzwungener Einstieg bleibt', () {
      expect(
        aufrufe[0].contains('preferredJoinIndex: regel.preferredJoinIndex'),
        isTrue,
        reason:
            'Der Gruppen-Pfad muss ueber das gemeinsame Regelwerk laufen. '
            'Dort ist der Zwang zum Original-Start gewollt: alle sollen '
            'dieselbe Strecke fahren.',
      );
    });

    test('Solo-Fahrtstart: KEIN erzwungener Einstieg', () {
      final solo = aufrufe.last;
      expect(
        solo.contains('preferredJoinIndex: null'),
        isTrue,
        reason:
            'Der Solo-Fahrtstart erzwingt wieder einen Einstiegspunkt. Damit '
            'faehrt der Nutzer erneut erst zur Haustuer des Erstellers — '
            'genau die Beschwerde vom 31.08.',
      );
      expect(
        solo.contains('joinNearestForward: _istWiederaufnahme'),
        isTrue,
        reason:
            'Ohne Vorwaerts-Andocken laeuft die Strecke ab dem naechsten '
            'Punkt nicht weiter.',
      );
    });

    test('Vorschau: ebenfalls kein erzwungener Einstieg', () {
      expect(
        aufrufe[1].contains('preferredJoinIndex: null'),
        isTrue,
        reason:
            'Vorschau und Fahrtstart muessen dasselbe zeigen. Weichen sie ab, '
            'sieht der Nutzer eine Strecke und faehrt eine andere.',
      );
    });
  });
}
