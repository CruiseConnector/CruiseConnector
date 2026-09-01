// 2026-09-01 — Vucko, Sprachaufnahme:
//   "Vor allem ist es so, wenn ich Umwege suche, also kleine, mittlere oder
//    grosse Umwege, dann dauert es wirklich lange, bis ich eine Route gefunden
//    habe und meistens findet es gar keine Route. Das heisst, irgendwas hast
//    du kaputt gemacht."
//
// WAS GEMESSEN WURDE (01.09., gegen die Live-Edge):
//
// Die Edge ist NICHT schuld. 27 Live-Antworten, 0,9 bis 5,4 Sekunden, keine
// einzige fehlgeschlagen. Die Zeit und das "keine Route" entstehen im Client.
// An drei echten Vorarlberger Paaren mit je sechs Seeds nachgerechnet:
// in FUENF von neun Kombinationen aus Paar und Stufe scheitern BEIDE
// Live-Versuche an den Toren. Haerteste Ursache ist die Kehrtwenden-Pruefung —
// eine einzige Wende verwirft den Kandidaten hart, ohne Notausgang.
//
// Was danach passierte: eine Rueckfall-Kaskade mit drei bis fuenf weiteren
// Serveraufrufen, nacheinander, und am Ende bekam der Nutzer die DIREKTE
// Strecke — also ausdruecklich nicht den Umweg, den er wollte — oder die
// Meldung "keine stabile Variante".
//
// DIE REGEL DAHINTER ist die, die Vucko am selben Tag selbst formuliert hat:
//   "nur wenn es andere wege gibt dann soll er sie auch nehmen aber wenn es
//    keine gibt passt es auch die gleiche route zurueck zu nehmen."
//
// Also: die Tore bleiben in voller Schaerfe und entscheiden weiterhin, WELCHER
// Kandidat gewinnt. Nur wenn am Ende gar nichts uebrig ist, wird der beste
// verworfene ausgeliefert statt einer Fehlermeldung.
//
// Dieser Test stellt genau den Fall nach: die Edge liefert eine Umweg-Route,
// die alle Tore reisst. Vorher: RouteServiceException. Jetzt: die Route.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mockito/mockito.dart';

import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

import 'route_generation_mock_test.mocks.dart';

const _feldkirchLat = 47.2413;
const _feldkirchLng = 9.5986;
const _bregenzLat = 47.5031;
const _bregenzLng = 9.7471;

geo.Position _feldkirch() => geo.Position(
  latitude: _feldkirchLat,
  longitude: _feldkirchLng,
  timestamp: DateTime.now(),
  accuracy: 5.0,
  altitude: 460.0,
  altitudeAccuracy: 10.0,
  heading: 0.0,
  headingAccuracy: 5.0,
  speed: 0.0,
  speedAccuracy: 1.0,
);

/// Eine A-nach-B-Geometrie MIT einem Stich, an dessen Spitze gewendet wird.
///
/// Aufbau: Start, gerade Richtung Ziel, dann ein Abstecher zur Seite und auf
/// demselben Weg zurueck, dann weiter zum Ziel. Genau die Form, die der
/// Kehrtwenden-Filter hart ablehnt.
List<List<double>> _strekeMitWende() {
  final punkte = <List<double>>[];
  const schritte = 140;
  // Hinweg: Feldkirch Richtung Bregenz.
  for (var i = 0; i <= schritte; i++) {
    final t = i / schritte;
    punkte.add([
      _feldkirchLng + (_bregenzLng - _feldkirchLng) * t * 0.55,
      _feldkirchLat + (_bregenzLat - _feldkirchLat) * t * 0.55,
    ]);
  }
  // Der Stich: seitlich weg und auf demselben Weg zurueck.
  final ab = punkte.last;
  final stich = <List<double>>[];
  for (var i = 1; i <= 40; i++) {
    stich.add([ab[0] + 0.0009 * i, ab[1] + 0.00035 * i]);
  }
  punkte.addAll(stich);
  punkte.addAll(stich.reversed.skip(1));
  // Weiter zum Ziel.
  for (var i = 1; i <= schritte; i++) {
    final t = i / schritte;
    punkte.add([
      ab[0] + (_bregenzLng - ab[0]) * t,
      ab[1] + (_bregenzLat - ab[1]) * t,
    ]);
  }
  return punkte;
}

Map<String, dynamic> _antwortMitWende({required double distanzMeter}) {
  final coords = _strekeMitWende();
  return {
    'meta': <String, dynamic>{
      'engine': 'graphhopper-8',
      'detour_level': 2,
      'distance_km': distanzMeter / 1000.0,
    },
    'route': {
      'geometry': {'type': 'LineString', 'coordinates': coords},
      'distance': distanzMeter,
      'duration': distanzMeter / 1000.0 * 60.0,
      'legs': [
        {
          'steps': [
            {
              'maneuver': {
                'type': 'turn',
                'modifier': 'left',
                'location': coords[10],
              },
              'distance': 500.0,
              'name': 'Teststrasse',
            },
            {
              'maneuver': {'type': 'arrive', 'location': coords.last},
              'distance': 0.0,
              'name': '',
            },
          ],
        },
      ],
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockRouteEdgeInvoker mockInvoker;
  late RouteService service;

  setUp(() {
    mockInvoker = MockRouteEdgeInvoker();
    service = RouteService(invoker: mockInvoker);
  });

  group('A nach B mit Umweg liefert IMMER etwas', () {
    test('eine Strecke mit Wende endet NICHT in einer Fehlermeldung', () async {
      // Die Edge liefert durchgehend eine Route mit einem Stich darin. Alle
      // Tore lehnen ab. Vorher konnte hier "Keine passende Route gefunden"
      // herauskommen — genau Vuckos Beschwerde.
      when(mockInvoker.invoke(any)).thenAnswer(
        (_) async => _antwortMitWende(distanzMeter: 62000),
      );

      final ergebnis = await _versuche(service);
      expect(
        ergebnis.route,
        isNotNull,
        reason:
            'Der Nutzer hat einen mittleren Umweg angefordert und die Edge hat '
            'geliefert. Eine Fehlermeldung ist der schlechteste aller '
            'Ausgaenge. Stattdessen kam: ${ergebnis.fehler?.userMessage}',
      );
      expect(ergebnis.route!.coordinates.length, greaterThan(2));
    });

    test('auch wenn die Herabstufung SELBST scheitert, kommt eine Route',
        () async {
      // Der haerteste Fall: die Umwegs-Anfragen liefern eine Route, die alle
      // Tore reisst, UND die Herabstufung auf "direkt" liefert gar nichts.
      // Vorher endete das zwingend in einer Fehlermeldung. Hier muss der
      // Notausgang greifen.
      when(mockInvoker.invoke(any)).thenAnswer((aufruf) async {
        final koerper = aufruf.positionalArguments.first as Map<String, dynamic>;
        final stufe = koerper['detour_level'];
        if (stufe == null || stufe == 0) {
          throw const RouteServiceException(
            type: RouteErrorType.noRoute,
            userMessage: 'Testfall: die Direktroute ist nicht verfuegbar.',
            debugMessage: 'test_direct_unavailable',
          );
        }
        return _antwortMitWende(distanzMeter: 62000);
      });

      final ergebnis = await _versuche(service);
      expect(
        ergebnis.route,
        isNotNull,
        reason:
            'Wenn selbst die Herabstufung nichts liefert, ist der beste '
            'verworfene Kandidat immer noch besser als eine Fehlermeldung. '
            'Stattdessen kam: ${ergebnis.fehler?.userMessage}',
      );
      expect(
        ergebnis.route!.edgeMeta['client_letzter_ausweg'],
        isTrue,
        reason:
            'Der Notausgang muss sich ausweisen. Ohne die Markierung sieht '
            'spaeter niemand, dass hier die Tore uebergangen wurden.',
      );
    });

    test('der Notausgang gilt NUR fuer Umwege, nicht als Generalschluessel',
        () {
      final quelle = _quelltext();
      // Die Bedingungen stehen im Code und muessen eng bleiben. Wer sie
      // aufweicht, macht aus dem Notausgang eine offene Tuer und alle
      // Qualitaetstore wirkungslos.
      for (final bedingung in <String>[
        'scenario.isPointToPoint',
        '!notausgang.startOffsetRejected',
        '!notausgang.countryRejected',
        'notausgang.route.coordinates.length >= 2',
      ]) {
        expect(
          quelle.contains(bedingung),
          isTrue,
          reason:
              'Die Bedingung "$bedingung" fehlt im Notausgang. Ohne sie '
              'wuerde er auch dort greifen, wo eine Ablehnung richtig ist.',
        );
      }
    });

    test('der Notausgang steht NACH allen Rueckfaellen, nicht davor', () {
      final quelle = _quelltext();
      // Das ist der Unterschied zwischen "Notausgang" und "offene Tuer".
      // Stand er vor der Herabstufungs-Kaskade, uebersprang er sie — und die
      // beiden Waechter vom 18.08. schlugen sofort an: eine Route, die sich
      // selbst als direkt meldet, wurde wieder als Umweg verkauft.
      final notausgangAb = quelle.indexOf('client_letzter_ausweg');
      final kaskadeAb = quelle.indexOf('allowDirectFallback: true');
      expect(notausgangAb, greaterThan(0));
      expect(kaskadeAb, greaterThan(0));
      expect(
        kaskadeAb < notausgangAb,
        isTrue,
        reason:
            'Die Herabstufungs-Kaskade MUSS vorher laufen. Sie liefert die '
            'ehrliche Markierung detour_downgraded, auf die zwei Waechter '
            'bestehen.',
      );
    });

    test('die Tore selbst wurden NICHT gelockert', () {
      final quelle = _quelltext();
      // Der Auftrag sagt ausdruecklich: die Routenqualitaet muss top bleiben.
      // Der Notausgang ist die EINZIGE Aenderung; die Pruefungen davor
      // entscheiden weiterhin, welcher Kandidat gewinnt.
      expect(
        quelle.contains('hardUturnFailure') ||
            quelle.contains('uturnPositions'),
        isTrue,
        reason:
            'Die Kehrtwenden-Pruefung muss stehen bleiben. Sie entscheidet '
            'weiterhin, WELCHER Kandidat gewinnt — nur nicht mehr, ob der '
            'Nutzer ueberhaupt etwas bekommt.',
      );
    });
  });
}

Future<RouteResultOderFehler> _versuche(RouteService service) async {
  try {
    final route = await service.generatePointToPoint(
      startPosition: _feldkirch(),
      destinationLat: _bregenzLat,
      destinationLng: _bregenzLng,
      mode: 'Kurvenjagd',
      scenic: true,
      routeVariant: 2,
    );
    return RouteResultOderFehler.erfolg(route);
  } on RouteServiceException catch (e) {
    return RouteResultOderFehler.fehler(e);
  }
}

String _quelltext() =>
    File('lib/data/services/route_service.dart').readAsStringSync();

class RouteResultOderFehler {
  RouteResultOderFehler.erfolg(this.route) : fehler = null;
  RouteResultOderFehler.fehler(this.fehler) : route = null;

  final RouteResult? route;
  final RouteServiceException? fehler;
}
