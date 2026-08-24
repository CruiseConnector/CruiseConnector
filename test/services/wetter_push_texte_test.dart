import 'dart:io';

import 'package:cruise_connect/data/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-24 (vucko): „die taeglichen Benachrichtigungen fuer eine Strecke
/// sollen immer unterschiedlich sein, ohne Bindestrich und anlockend."
///
/// Gemessen vor der Aenderung: supabase/functions/send-push/index.ts hatte
/// den Titel fest verdrahtet („Bestes Cruise-Wetter"). Jeden Tag derselbe
/// Satz auf dem Sperrbildschirm — und darunter zeigte die App einen ganz
/// anderen Text, weil sie ihren eigenen Variantenpool hatte.
///
/// Dieser Test bewacht drei Dinge:
///   1. Push und App rendern aus DERSELBEN Tabelle (Datei-Abgleich).
///   2. Die Hausregeln am Wortlaut: kein Strich, echte Umlaute, Laenge.
///   3. Die Auswahl wechselt taeglich und wiederholt sich nicht im Monat.
void main() {
  // ── Tabellen aus der Edge Function lesen ─────────────────────────────────
  final tsDatei = File('supabase/functions/send-push/index.ts');
  final tsQuelle = tsDatei.readAsStringSync();

  List<List<String>> tsTabelle(String name) {
    final block = RegExp(
      'const $name: string\\[\\]\\[\\] = \\[(.*?)\\n\\];',
      dotAll: true,
    ).firstMatch(tsQuelle);
    expect(
      block,
      isNotNull,
      reason: 'Tabelle $name fehlt in ${tsDatei.path}',
    );
    final zeilen = RegExp(r"^\s*\['(.*)', '(.*)'\],$", multiLine: true)
        .allMatches(block!.group(1)!);
    return [
      for (final z in zeilen) [z.group(1)!, z.group(2)!],
    ];
  }

  final paare = <String, (List<List<String>>, String)>{
    'mild': (WetterPushTexte.mild, 'WETTER_MILD'),
    'warm': (WetterPushTexte.warm, 'WETTER_WARM'),
    'kuehl': (WetterPushTexte.kuehl, 'WETTER_KUEHL'),
    'ohneWert': (WetterPushTexte.ohneWert, 'WETTER_OHNE_WERT'),
  };

  group('Push und App sagen dasselbe', () {
    test('REGRESSION: send-push hat keinen fest verdrahteten Titel mehr', () {
      expect(
        tsQuelle.contains("title: 'Bestes Cruise-Wetter'"),
        isFalse,
        reason: 'Der feste Titel war genau der Defekt vom 24.08.',
      );
      expect(
        tsQuelle.contains('wetterTexte('),
        isTrue,
        reason: 'send-push muss aus der gemeinsamen Tabelle rendern',
      );
    });

    for (final eintrag in paare.entries) {
      test('Tabelle ${eintrag.key} ist in Dart und TypeScript gleich', () {
        final dart = eintrag.value.$1;
        final ts = tsTabelle(eintrag.value.$2);
        expect(
          ts.length,
          dart.length,
          reason: '${eintrag.value.$2} hat ${ts.length} Eintraege, '
              'WetterPushTexte.${eintrag.key} hat ${dart.length}',
        );
        for (var i = 0; i < dart.length; i++) {
          expect(ts[i][0], dart[i][0], reason: 'Titel $i in ${eintrag.key}');
          expect(ts[i][1], dart[i][1], reason: 'Text $i in ${eintrag.key}');
        }
      });
    }

    test('die Bandgrenzen stehen in beiden Dateien gleich', () {
      expect(tsQuelle.contains('temperaturC >= 27'), isTrue);
      expect(tsQuelle.contains('temperaturC < 13'), isTrue);
      expect(WetterPushTexte.poolFuer(27), same(WetterPushTexte.warm));
      expect(WetterPushTexte.poolFuer(26.9), same(WetterPushTexte.mild));
      expect(WetterPushTexte.poolFuer(13), same(WetterPushTexte.mild));
      expect(WetterPushTexte.poolFuer(12.9), same(WetterPushTexte.kuehl));
      expect(WetterPushTexte.poolFuer(null), same(WetterPushTexte.ohneWert));
    });
  });

  group('Hausregeln am Wortlaut', () {
    // U+002D bis U+2212: Bindestrich, Gedankenstrich und alles dazwischen,
    // was auf dem Bildschirm wie ein Strich aussieht.
    const striche = ['-', '‐', '‑', '‒', '–', '—',
        '―', '−'];

    // Klassische ae/oe/ue-Ersatzschreibung. Vucko will echte Umlaute.
    const ersatzschreibung = [
      'fuer', 'ueber', 'moecht', 'schoen', 'draussen', 'strasse', 'grosse',
      'waehl', 'oeffne', 'kuehl', 'huegel', 'laenge', 'naechst', 'gruen',
      'gefaellig', 'zaehlt',
    ];

    for (final eintrag in paare.entries) {
      final pool = eintrag.value.$1;
      test('${eintrag.key}: kein Strich, kein Apostroph', () {
        for (final p in pool) {
          for (final text in p) {
            for (final strich in striche) {
              expect(
                text.contains(strich),
                isFalse,
                reason: 'Strich in „$text"',
              );
            }
            expect(text.contains("'"), isFalse, reason: 'Apostroph in „$text"');
          }
        }
      });

      test('${eintrag.key}: echte Umlaute statt ae/oe/ue', () {
        for (final p in pool) {
          for (final text in p) {
            final klein = text.toLowerCase();
            for (final wort in ersatzschreibung) {
              expect(
                klein.contains(wort),
                isFalse,
                reason: 'Ersatzschreibung „$wort" in „$text"',
              );
            }
            expect(text.contains('Ã'), isFalse, reason: 'Mojibake in „$text"');
          }
        }
      });

      test('${eintrag.key}: Laengengrenzen fuer den Sperrbildschirm', () {
        // Android schneidet den Titel der eingeklappten Meldung bei rund 30
        // Zeichen ab, das iPhone zeigt zwei Zeilen Text (rund 85 Zeichen).
        for (final p in pool) {
          for (final grad in ['8', '25', 'minus 12']) {
            final titel = p[0].replaceAll('{temp}', grad);
            final text = p[1].replaceAll('{temp}', grad);
            expect(
              titel.length,
              lessThanOrEqualTo(30),
              reason: 'Titel zu lang (${titel.length}): „$titel"',
            );
            expect(
              text.length,
              lessThanOrEqualTo(85),
              reason: 'Text zu lang (${text.length}): „$text"',
            );
          }
        }
      });

      test('${eintrag.key}: der Kern steht vorne', () {
        for (final p in pool) {
          if (eintrag.key == 'ohneWert') {
            // Ohne Temperatur in der Nutzlast darf kein Platzhalter stehen,
            // sonst liest der Nutzer woertlich „{temp}°".
            expect(p.join(' ').contains('{temp}'), isFalse, reason: '$p');
            continue;
          }
          final imTitel = p[0].contains('{temp}');
          final stelle = p[1].indexOf('{temp}');
          expect(
            imTitel || (stelle >= 0 && stelle < 45),
            isTrue,
            reason: 'Temperatur steht zu weit hinten: „${p[1]}"',
          );
        }
      });
    }

    test('jeder Titel kommt nur einmal vor', () {
      final alle = [
        for (final e in paare.values) ...e.$1.map((p) => p[0]),
      ];
      expect(
        alle.toSet().length,
        alle.length,
        reason: 'Doppelte Titel wuerden bei einem Bandwechsel '
            'am Folgetag wie eine Wiederholung wirken',
      );
    });

    test('die Texte benutzen echte Umlaute und echtes ss', () {
      final alle = paare.values
          .expand((e) => e.$1)
          .expand((p) => p)
          .join(' ');
      for (final zeichen in ['ä', 'ö', 'ü', 'ß']) {
        expect(alle.contains(zeichen), isTrue, reason: 'kein $zeichen');
      }
    });
  });

  group('Auswahl', () {
    const nutzer = '7f3c2b10-0000-4000-8000-0000000000aa';
    DateTime tag(int n) => DateTime.utc(2026, 8, 24).add(Duration(days: n));

    test('ein Monat ohne Wiederholung im Normalfall', () {
      expect(
        WetterPushTexte.mild.length,
        greaterThanOrEqualTo(31),
        reason: 'Sonst wiederholt sich der Text innerhalb eines Monats',
      );
      final gesehen = <String>{};
      for (var i = 0; i < 31; i++) {
        final (titel, text) = WetterPushTexte.fuer(
          userId: nutzer,
          erstelltAm: tag(i),
          temperaturC: 21,
        );
        expect(gesehen.add('$titel|$text'), isTrue, reason: 'Tag $i doppelt');
      }
    });

    test('zwei Tage hintereinander nie derselbe Text, in jedem Band', () {
      const temperaturen = <num?>[21, 31, 4, null];
      for (final temp in temperaturen) {
        for (var i = 0; i < 400; i++) {
          final heute = WetterPushTexte.fuer(
            userId: nutzer,
            erstelltAm: tag(i),
            temperaturC: temp,
          );
          final morgen = WetterPushTexte.fuer(
            userId: nutzer,
            erstelltAm: tag(i + 1),
            temperaturC: temp,
          );
          expect(heute, isNot(morgen), reason: 'Tag $i, $temp Grad');
        }
      }
    });

    test('dieselbe Meldung ergibt immer denselben Text', () {
      // Genau darauf beruht, dass Push und App zusammenpassen: die Edge
      // rendert beim Zustellen, die App beim Oeffnen der Liste.
      final beimSenden = WetterPushTexte.fuer(
        userId: nutzer,
        erstelltAm: DateTime.utc(2026, 8, 24, 15, 30),
        temperaturC: 22.4,
      );
      final beimOeffnen = WetterPushTexte.fuer(
        userId: nutzer,
        erstelltAm: DateTime.utc(2026, 8, 24, 15, 30),
        temperaturC: 22.4,
      );
      expect(beimSenden, beimOeffnen);
    });

    test('die Uhrzeit innerhalb des Tages aendert den Text nicht', () {
      final mittag = WetterPushTexte.fuer(
        userId: nutzer,
        erstelltAm: DateTime.utc(2026, 8, 24, 11),
        temperaturC: 22,
      );
      final abend = WetterPushTexte.fuer(
        userId: nutzer,
        erstelltAm: DateTime.utc(2026, 8, 24, 19),
        temperaturC: 22,
      );
      expect(mittag, abend);
    });

    test('zwei Nutzer bekommen am selben Tag nicht zwingend dasselbe', () {
      final texte = <String>{};
      for (var i = 0; i < 20; i++) {
        final (titel, _) = WetterPushTexte.fuer(
          userId: 'nutzer-nummer-$i',
          erstelltAm: tag(0),
          temperaturC: 21,
        );
        texte.add(titel);
      }
      expect(texte.length, greaterThan(1));
    });

    test('Temperatur wird gerundet eingesetzt, Minusgrade ausgeschrieben', () {
      expect(WetterPushTexte.temperaturText(22.4), '22');
      expect(WetterPushTexte.temperaturText(22.6), '23');
      expect(WetterPushTexte.temperaturText(-2.5), 'minus 3');
      expect(WetterPushTexte.temperaturText(-0.4), '0');
      final (titel, text) = WetterPushTexte.fuer(
        userId: nutzer,
        erstelltAm: tag(0),
        temperaturC: -3,
      );
      expect('$titel $text'.contains('{temp}'), isFalse);
      for (final strich in ['-', '−']) {
        expect('$titel $text'.contains(strich), isFalse);
      }
    });
  });
}
