// 2026-09-01 — Vucko, Sprachaufnahme (Aufgaben A15 und A16):
//   "was ich auch moechte ist, dass das Zielpunkt dann nicht, also gleich ist
//    wie der neue Anfangspunkt, wo der Nutzer an die Route andockt, das ist
//    ganz wichtig, weil sonst ist der Endpunkt auch ein Haus und dann geht es
//    wieder um die Sicherheit und so weiter"
//
// WAS DAS PROBLEM WAR
//
// Der Andockpunkt ist da, wo der Fahrer gerade steht — meistens vor der
// eigenen Haustuer. Endete die Runde exakt wieder dort, stand die Adresse
// ZWEIMAL in der Geometrie: als Anfang und als Ende. Belegt in
// route_service.dart: `sessionEnd: _copyCoordinate(sessionRoute.coordinates
// .last)`, und der Rueckweg zielte in `_buildReturnLegIfNeeded` exakt auf
// `sessionOrigin`. Wird die Fahrt danach geteilt oder gespeichert, faellt
// beides mit.
//
// DIE SPERRE (A17)
//
// Vucko woertlich: "die Andock-Punkte, wenn man eine Fahrt startet, sind
// anders, das gefaellt mir." Das ist funktionierender Code, mit dem er
// zufrieden ist. Angefasst wird deshalb AUSSCHLIESSLICH das Ziel — die
// Andock-Logik bleibt Zeile fuer Zeile unveraendert. Der letzte Test unten
// haelt das fest.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/core/routen_kappung.dart';

void main() {
  late String quelle;

  setUpAll(() {
    quelle = File('lib/data/services/route_service.dart').readAsStringSync();
  });

  group('Das Ziel liegt nicht mehr auf dem Andockpunkt', () {
    test('es gibt einen Versatz, und er ist begruendet', () {
      expect(
        quelle.contains('_zielVomAndockpunktWegruecken('),
        isTrue,
        reason:
            'Ohne diesen Schritt endet eine fortgesetzte Runde exakt dort, wo '
            'der Fahrer eingestiegen ist — also an seiner Haustuer.',
      );
      expect(zielVersatzMeter, 300.0);
      expect(
        zielVersatzMeter,
        anzeigeKappungMeter,
        reason:
            'Dieselbe Weite wie die Anzeige-Kappung. Zwei verschiedene Zahlen '
            'fuer dieselbe Sache laufen frueher oder spaeter auseinander.',
      );
    });

    test('er greift NUR, wenn das Ziel wirklich am Andockpunkt liegt', () {
      // Ein Ziel, das ohnehin woanders liegt, darf nicht beschnitten werden.
      // Sonst waere aus dem Datenschutz-Fix ein genereller Beschnitt jeder
      // Fahrt geworden.
      expect(quelle.contains('if (abstand > zielGleichAndockMeter) return route;'),
          isTrue);
      expect(zielGleichAndockMeter, 120.0);
    });

    test('eine zu kurze Strecke wird NICHT zerstoert', () {
      // kappeEndstuecke gibt bei zu wenig Rest eine leere Liste zurueck. Die
      // darf nie als Route durchgehen — lieber ein Ziel an der Haustuer als
      // gar keine Fahrt.
      expect(quelle.contains('if (gekappt.length < 2)'), isTrue);
      expect(
        quelle.contains('Lieber ein Ziel an der Haustuer als keine Fahrt.'),
        isTrue,
        reason: 'Die Begruendung gehoert an die Stelle, nicht nur in den Test.',
      );
    });

    test('er greift NUR, wenn WIR das Ende gesetzt haben', () {
      // Faehrt jemand eine FREMDE Runde unveraendert ab, ist ihr Ende die
      // Entscheidung des Erstellers, nicht unsere. Beim ersten Anlauf habe ich
      // zu breit gegriffen, worauf die Zusage "ohne Zubringer ist die aktive
      // Route die Folgeroute" gebrochen ist (route_access_plan_test).
      expect(
        quelle.contains(
          'final wirHabenDasEndeGesetzt = returnLeg != null || '
          'routeRebasedToUser;',
        ),
        isTrue,
        reason:
            'Ohne diese Eingrenzung schneidet der Versatz auch an Strecken '
            'herum, die wir gar nicht veraendert haben.',
      );
    });

    test('Laenge und Fahrzeit werden mitgezogen', () {
      // Sonst zeigt die Fahransicht eine Restdistanz, die es nicht mehr gibt.
      expect(quelle.contains('distanceMeters: laengeMeter'), isTrue);
      expect(quelle.contains('route.durationSeconds! * anteil'), isTrue);
    });

    test('der Eingriff ist im Ergebnis nachvollziehbar', () {
      expect(quelle.contains("'ziel_vom_andockpunkt_versetzt': true"), isTrue,
          reason:
              'Ohne Markierung sieht spaeter niemand, warum die Strecke 300 m '
              'kuerzer ist als die geplante.');
    });
  });

  group('A17: die Andock-Logik bleibt unangetastet', () {
    test('der Versatz fasst nur das ZIEL an, nie den Andockpunkt', () {
      final i = quelle.indexOf('RouteResult _zielVomAndockpunktWegruecken(');
      expect(i, greaterThan(0));
      final block = quelle.substring(i, i + 2200);

      // Der Andockpunkt kommt nur LESEND vor, als Vergleichswert.
      expect(block.contains('andockpunkt'), isTrue);
      for (final verboten in <String>[
        'joinPoint =',
        'joinIndex =',
        '_findJoinPoint',
        'preferredJoinIndex =',
      ]) {
        expect(
          block.contains(verboten),
          isFalse,
          reason:
              'Der Versatz darf "$verboten" nicht anfassen. Vucko: "die '
              'Andock-Punkte, wenn man eine Fahrt startet, sind anders, das '
              'gefaellt mir."',
        );
      }
    });

    test('die Suche nach dem Andockpunkt selbst ist unveraendert', () {
      // Diese beiden Bausteine sind der Kern der Andock-Logik. Sie muessen da
      // sein und duerfen nicht durch den Versatz ersetzt worden sein.
      expect(quelle.contains('joinPointType'), isTrue);
      expect(quelle.contains('rebaseClosedLoop'), isTrue);
    });
  });
}
