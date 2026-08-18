import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';

/// 2026-08-18 (vucko, 1.2b): „Erst zurueck auf die Route, bei Fehlschlag
/// mehrfach wiederholen."
///
/// GEMESSENE LUECKE: Die Rejoin-Schleife hatte 2 Durchlaeufe und setzte den
/// Andockindex am Schleifenkopf bedingungslos auf
/// `fallbackRejoinIndex + ((attempt - 1) * 60)` — fuer attempt 1 also auf den
/// Ausgangswert. Alle sieben Vorrueckungen um 80, die vor einem `continue`
/// gesetzt wurden, waren damit wirkungslos: sie wurden nie in eine Anfrage
/// uebersetzt. Zusaetzlich verbrannte der 160-m-Fall den Durchlauf 0 komplett,
/// OHNE einen einzigen Routing-Aufruf.
///
/// `naechsterAndockIndex` ist die eine Stelle, an der der Index weiterrueckt.
/// Dieser Test prueft die Leiter als reine Logik — ohne Routing-Server.
void main() {
  group('naechsterAndockIndex', () {
    test('rueckt um den Schritt vor', () {
      expect(
        naechsterAndockIndex(aktuellerIndex: 10, schritt: 80, maxIndex: 500),
        80 + 10,
      );
    });

    test('geht NIE zurueck', () {
      // Das war der Kern des Fehlers: der Schleifenkopf zog den Index zurueck.
      var index = 12;
      for (var i = 0; i < 5; i++) {
        final naechster = naechsterAndockIndex(
          aktuellerIndex: index,
          schritt: 80,
          maxIndex: 1000,
        );
        expect(
          naechster,
          greaterThan(index),
          reason: 'die Leiter muss streng monoton vorwaerts laufen',
        );
        index = naechster;
      }
      expect(index, 12 + 5 * 80);
    });

    test('vier Durchlaeufe decken echten Weg ab', () {
      // Ohne den Fix landete Durchlauf 2 wieder auf dem Ausgangswert.
      var index = 30;
      for (var i = 0; i < 4; i++) {
        index = naechsterAndockIndex(
          aktuellerIndex: index,
          schritt: 80,
          maxIndex: 5000,
        );
      }
      expect(index, 30 + 320);
    });

    test('klemmt am Routenende statt darueber hinaus zu laufen', () {
      expect(
        naechsterAndockIndex(aktuellerIndex: 90, schritt: 80, maxIndex: 100),
        100,
      );
      expect(
        naechsterAndockIndex(aktuellerIndex: 100, schritt: 80, maxIndex: 100),
        100,
      );
    });

    test('faengt kaputte Eingaben ab', () {
      expect(
        naechsterAndockIndex(aktuellerIndex: -5, schritt: 80, maxIndex: 100),
        80,
      );
      expect(
        naechsterAndockIndex(aktuellerIndex: 999, schritt: 80, maxIndex: 100),
        100,
      );
      expect(
        naechsterAndockIndex(aktuellerIndex: 10, schritt: -80, maxIndex: 100),
        10,
        reason: 'ein negativer Schritt darf den Index nicht zurueckziehen',
      );
      expect(
        naechsterAndockIndex(aktuellerIndex: 10, schritt: 80, maxIndex: 0),
        0,
      );
    });
  });

  group('Rejoin-Leiter im Quelltext', () {
    late String quelle;

    setUpAll(() {
      quelle = File(
        'lib/presentation/pages/cruise_mode_page.dart',
      ).readAsStringSync();
    });

    test('mehr als zwei Durchlaeufe', () {
      expect(
        quelle.contains('static const int _rejoinLeiterVersuche = 4;'),
        isTrue,
        reason: 'zwei Durchlaeufe, davon einer wirkungslos, waren die Ursache',
      );
      expect(
        quelle.contains('for (var attempt = 0; attempt < 2; attempt++)'),
        isFalse,
        reason: 'die alte Zwei-Versuch-Schleife darf nicht zurueckkommen',
      );
    });

    test('der Andockindex wird am Schleifenkopf nicht mehr zurueckgesetzt', () {
      expect(
        quelle.contains('fallbackRejoinIndex + ((attempt - 1) * 60)'),
        isFalse,
        reason:
            'genau diese Zeile machte alle Vorrueckungen um 80 wirkungslos',
      );
      expect(
        quelle.contains('aktuellerIndex: math.max(rejoinIndex, fallbackRejoinIndex)'),
        isTrue,
        reason: 'stattdessen nur noch vorwaerts ziehen',
      );
    });

    test('jede Vorrueckung laeuft ueber die Leiter-Funktion', () {
      expect(
        quelle.contains('math.min(rejoinIndex + 80, maxRejoinIndex)'),
        isFalse,
        reason: 'eine Stelle fuer die Leiter, nicht sieben Kopien',
      );
      expect(
        quelle.contains('math.min(rejoinIndex + 60, maxRejoinIndex)'),
        isFalse,
      );
      // sieben Verwerfungs-Pfade + der 160-m-Fall = acht Aufrufe im Zyklus.
      final aufrufe = 'schritt: 80,'.allMatches(quelle).length;
      expect(aufrufe, 7, reason: 'alle sieben Verwerfungs-Pfade');
      expect('schritt: 60,'.allMatches(quelle).length, 1);
    });

    test('der 160-m-Fall verbrennt keinen Versuch', () {
      final leiter = quelle.indexOf('while (rejoinLohntSich &&');
      expect(leiter, greaterThan(0));
      final rumpf = quelle.substring(leiter, leiter + 4000);
      final nahFall = rumpf.indexOf('if (distToRejoin < 160');
      final zaehler = rumpf.indexOf('final versuchNr = attempt;');
      expect(nahFall, greaterThan(0));
      expect(zaehler, greaterThan(0));
      expect(
        nahFall,
        lessThan(zaehler),
        reason:
            'der 160-m-Fall ruft nichts auf — er muss VOR dem Hochzaehlen '
            'abbiegen, sonst kostet er einen Netz-Versuch',
      );
      expect(
        quelle.contains('leiterAktiv = true;'),
        isTrue,
        reason:
            'nach dem 160-m-Fall muss der Fallback-Plan greifen, dessen Anker '
            'dem vorgerueckten Index folgt — sonst dreht die Schleife auf der '
            'Stelle',
      );
      expect(
        quelle.contains('leiterSchritte < _rejoinLeiterMaxSchritte'),
        isTrue,
        reason: 'harte Obergrenze gegen Endlosdrehen',
      );
    });
  });
}
