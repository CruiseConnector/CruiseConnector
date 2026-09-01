// 2026-09-01 — Vucko, Sprachaufnahme (Aufgabe A1):
//   "das problem war dass ich sehr lange gebraucht habe bis ich eine Route von
//    A nach B gefunden habe ... es muss umgehend die Zeit nochmal gemindert
//    werden. Das dauert viel zu lange."
//   "Ich moechte, dass die Routenqualitaet top ist, aber auch die Zeit niedrig
//    ist. Deswegen habe ich auch die Sachen ja zu Hause gehostet."
//
// WO DIE ZEIT HINGING (gemessen am 01.09., nicht vermutet)
//
// Die Edge antwortet in 0,9 bis 5,4 Sekunden, 27 von 27 Aufrufen erfolgreich.
// Die Wartezeit entstand ausschliesslich im Client, aus drei Quellen:
//
//   1. Bis zu SIEBEN Serveraufrufe nacheinander je Tipp — zwei Live-Versuche,
//      ein aggressiver Rettungskorridor, drei Herabstufungen, ein
//      Direktrueckfall. Dazwischen vier bis sechs Datenbankrunden. Nirgends
//      eine Restzeitpruefung: kein Future.wait, keine Deadline, kein Abbruch.
//   2. Ein Feld `max_search_ms: 25000`, das die Edge NIE liest (null Treffer
//      im ganzen index.ts), das aber das Client-Timeout von 26 auf 31 Sekunden
//      hob — je Versuch, bei zwei Versuchen je Aufruf.
//   3. Die Oberflaeche wiederholte die ganze Kaskade bis zu dreimal, weil der
//      Direkt-Rueckfall deterministisch dieselbe Route liefert (Dornbirn nach
//      Bludenz: 3 von 3 Mal exakt 45,21 km, also derselbe Fingerabdruck).
//      Aus 7 Aufrufen wurden 21, aus 10 bis 25 Sekunden wurden 30 bis 75.
//
// Dieser Test nagelt alle drei Gegenmassnahmen fest. Er prueft die QUELLE,
// weil sich eine Frist in einem Unit-Test nicht ehrlich nachstellen laesst,
// ohne echte Wartezeit zu erzeugen.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/route_service.dart';

void main() {
  late String routeService;
  late String cruisePage;
  late String edge;

  setUpAll(() {
    routeService = File(
      'lib/data/services/route_service.dart',
    ).readAsStringSync();
    cruisePage = File(
      'lib/presentation/pages/cruise_mode_page.dart',
    ).readAsStringSync();
    edge = File(
      'supabase/functions/generate-cruise-route-v2/index.ts',
    ).readAsStringSync();
  });

  group('Die Suche hat eine Frist', () {
    test('es gibt ueberhaupt eine', () {
      expect(
        routeService.contains('final gesamtfrist = Duration('),
        isTrue,
        reason:
            'Ohne Gesamtbudget kann ein einziger Tipp rechnerisch 434 '
            'Sekunden dauern (7 Aufrufe x 2 Versuche x 31 s).',
      );
      expect(routeService.contains('bool fristAbgelaufen()'), isTrue);
    });

    test('sie bremst den zweiten Live-Versuch', () {
      expect(
        routeService.contains('if (attempt > 0 && fristAbgelaufen())'),
        isTrue,
        reason:
            'Der ERSTE Versuch laeuft immer. Erst ab dem zweiten darf die '
            'Frist greifen, sonst kaeme bei kaltem Start gar nichts.',
      );
    });

    test('sie bremst die Rueckfall-Kaskade', () {
      expect(
        routeService.contains('if (!navigationReroute && !fristAbgelaufen())'),
        isTrue,
        reason:
            'Hier lagen drei bis fuenf weitere Serveraufrufe. Genau die '
            'liefen bisher auch dann noch, wenn der Nutzer schon eine halbe '
            'Minute wartet.',
      );
    });

    test('sie bremst den aggressiven Rettungskorridor', () {
      expect(
        routeService.contains('if (!fristAbgelaufen() &&'),
        isTrue,
        reason:
            'Liegt schon eine brauchbare Route vor, ist eine SCHOENERE nach '
            '20 Sekunden nichts mehr wert.',
      );
    });

    test('sie wirft nicht, sie ueberspringt nur', () {
      // Das ist der Unterschied zwischen "schneller" und "kaputt". Nach der
      // Frist muss der Notausgang am Ende noch greifen koennen.
      final fristStelle = routeService.indexOf('final gesamtfrist');
      final notausgangStelle = routeService.indexOf('client_letzter_ausweg');
      expect(fristStelle, greaterThan(0));
      expect(notausgangStelle, greaterThan(fristStelle));
      expect(
        routeService.contains('throw') &&
            !routeService.contains('if (fristAbgelaufen()) throw'),
        isTrue,
        reason: 'Die Frist darf niemals selbst eine Fehlermeldung ausloesen.',
      );
    });

    test('beim Neuberechnen waehrend der Fahrt gilt die kuerzere Frist', () {
      expect(
        routeService.contains('navigationReroute ? 10 : 20'),
        isTrue,
        reason:
            'Waehrend der Fahrt wartet niemand 20 Sekunden auf eine neue '
            'Route — dort zaehlt jede Sekunde doppelt.',
      );
    });
  });

  group('Das tote Feld ist weg', () {
    test('die Edge liest max_search_ms wirklich nicht', () {
      expect(
        edge.contains('max_search_ms'),
        isFalse,
        reason:
            'Falls die Edge das Feld eines Tages doch auswertet, muss der '
            'Client es wieder schicken — dann schlaegt dieser Test an.',
      );
    });

    test('der Client schickt keine erfundene Suchdauer mehr', () {
      expect(
        routeService.contains("'max_search_ms': 25000"),
        isFalse,
        reason:
            'Diese 25 Sekunden waren frei erfunden und hoben nur das eigene '
            'Timeout von 26 auf 31 Sekunden.',
      );
    });

    test('eine gesetzte Vorgabe wirkt weiterhin', () {
      // Die Fahransicht setzt bewusst 8 Sekunden fuer "Direkt" und 10 beim
      // Neuberechnen. Die duerfen nicht mit weggeraeumt worden sein.
      expect(
        routeService.contains(
          "if (maxSearchMsOverride != null) 'max_search_ms': maxSearchMsOverride",
        ),
        isTrue,
      );
      expect(
        RouteService.requestTimeoutSecondsFor(
          requestedMaxSearchMs: null,
          navigationRerouteRequest: false,
        ),
        26,
        reason: 'Ohne Angabe gilt wieder die vorgesehene Geduld von 26 s.',
      );
      expect(
        RouteService.requestTimeoutSecondsFor(
          requestedMaxSearchMs: 25000,
          navigationRerouteRequest: false,
        ),
        31,
        reason:
            'Die Rechnung selbst bleibt unveraendert — nur schickt niemand '
            'mehr grundlos 25000.',
      );
    });
  });

  group('Keine sinnlose Wiederholung', () {
    test('ein erzwungenes Ergebnis loest keinen Auto-Retry aus', () {
      expect(
        cruisePage.contains('ergebnisWarErzwungen'),
        isTrue,
        reason:
            'Der Direkt-Rueckfall ist deterministisch. Dieselbe Suche liefert '
            'garantiert denselben Fingerabdruck, die Wiederholung feuerte also '
            'sicher und verdreifachte die Kaskade.',
      );
      expect(
        cruisePage.contains('!ergebnisWarErzwungen &&'),
        isTrue,
        reason: 'Die Bedingung muss auch wirklich in canAutoRetry haengen.',
      );
    });

    test('die Wiederholung bei einer ECHTEN Suche bleibt erhalten', () {
      // Der Gedanke dahinter ist richtig und war Vuckos eigener Wunsch:
      // zweimal dieselbe Strecke soll die App von sich aus neu suchen lassen.
      expect(cruisePage.contains('isRepeatedRoute &&'), isTrue);
      expect(
        cruisePage.contains('_searchAgainAutoRetryCount < '
            '_maxSearchAgainAutoRetries'),
        isTrue,
      );
    });
  });
}
