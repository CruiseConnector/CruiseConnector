import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/hashtag_beitraege_page.dart';
import 'package:cruise_connect/presentation/pages/hashtag_personen_page.dart';

/// 2026-08-24 — Auftrag Vucko vom 24.08.
///
/// Vucko: „Aber da moechte ich das auch noch mit den Hashtags so haben, dass
/// wenn man einen #Bmw, #BayerischeMotorenWerke oder sonstige, dass man
/// sieht, wer alles so einen # benutzt hat. Also wenn ihn schon 17 Leute
/// benutzt haben, dann soll das moeglichst da noch drunter stehen […] man
/// soll drauf klicken koennen wie bei Instagram oder TikTok."
///
/// In der Datenbank stehen am 24.08. ZEHN Beitraege und NULL davon mit einer
/// Raute. Diese Datei prueft die Oberflaeche deshalb mit erfundenen Daten,
/// die durch die austauschbaren Lader hereingegeben werden. Ohne diese Naht
/// waere die Personenzahl erst dann pruefbar, wenn Vucko sie zum ersten Mal
/// braucht — und dort faellt so etwas erfahrungsgemaess auf.
Map<String, dynamic> _beitrag(String userId, String name) => {
  'post_id': 'p-$userId-${DateTime.now().microsecondsSinceEpoch}',
  'user_id': userId,
  'username': name,
  'avatar_url': null,
  'content': 'Heute #bmw gefahren',
  'created_at': '2026-08-24T10:00:00Z',
  'tag': 'bmw',
};

Map<String, dynamic> _person(String userId, String name, int anzahl) => {
  'user_id': userId,
  'username': name,
  'avatar_url': null,
  'anzahl': anzahl,
};

Widget _huelle(Widget kind) => MaterialApp(home: kind);

/// Pumpt ohne `pumpAndSettle`: die Ladeskelette schimmern endlos, ein
/// `pumpAndSettle` liefe darauf in einen Zeitfehler.
Future<void> _pumpen(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  group('Nutzertexte: Einzahl und Mehrzahl', () {
    test('„von 1 Leuten" darf es nicht geben', () {
      expect(hashtagVonLeutenText(1), 'von 1 Person');
      expect(hashtagVonLeutenText(1), isNot(contains('Leuten')));
      expect(hashtagVonLeutenText(17), 'von 17 Leuten');
    });

    test(
      'die Ueberschrift der Personenliste stimmt in Einzahl und Mehrzahl',
      () {
        expect(hashtagLeuteSatz(1, 'bmw'), '1 Person hat #bmw benutzt');
        expect(hashtagLeuteSatz(17, 'bmw'), '17 Leute haben #bmw benutzt');
        // Solange nachgeladen werden kann, wird keine Endzahl behauptet.
        expect(
          hashtagLeuteSatz(12, 'bmw', mindestens: true),
          'Mindestens 12 Leute haben #bmw benutzt',
        );
      },
    );

    test('„1 Beiträge" darf es auch nicht geben', () {
      expect(hashtagBeitraegeText(1), '1 Beitrag');
      expect(hashtagBeitraegeText(4), '4 Beiträge');
      expect(hashtagBeitraegeText(0), 'Keine Beiträge');
    });

    test('echte Umlaute, keine ae-Schreibweise', () {
      expect(hashtagBeitraegeText(4), contains('ä'));
      expect(hashtagBeitraegeText(4), isNot(contains('Beitraege')));
    });
  });

  group('Personen aus Beitraegen rechnen (Notbehelf ohne die Abfrage)', () {
    test('drei Beitraege von zwei Leuten sind ZWEI Leute, nicht drei', () {
      final personen = SocialService.personenAusBeitraegen([
        _beitrag('u1', 'anna'),
        _beitrag('u1', 'anna'),
        _beitrag('u2', 'bert'),
      ]);
      expect(personen.length, 2);
      expect(personen.first['user_id'], 'u1');
      expect(personen.first['anzahl'], 2);
      expect(personen.last['anzahl'], 1);
    });

    test('bei Gleichstand entscheidet der Name, damit die Reihenfolge '
        'zwischen zwei Ladevorgaengen gleich bleibt', () {
      final personen = SocialService.personenAusBeitraegen([
        _beitrag('u2', 'Bert'),
        _beitrag('u1', 'anna'),
      ]);
      expect(personen.map((p) => p['username']), ['anna', 'Bert']);
    });

    test('Zeilen ohne user_id fallen raus, statt eine Geisterperson zu '
        'erzeugen', () {
      final personen = SocialService.personenAusBeitraegen([
        {'post_id': 'x'},
        _beitrag('u1', 'anna'),
      ]);
      expect(personen.length, 1);
    });

    test('leere Liste ergibt keine Person', () {
      expect(SocialService.personenAusBeitraegen(const []), isEmpty);
    });
  });

  group('Antwortzeilen lesen, auch bei anderer Spaltenbenennung', () {
    test('die Haeufigkeit heisst anzahl, beitraege oder anzahl_beitraege', () {
      expect(SocialService.hashtagPersonZeile({'anzahl': 3})['anzahl'], 3);
      expect(SocialService.hashtagPersonZeile({'beitraege': 4})['anzahl'], 4);
      expect(
        SocialService.hashtagPersonZeile({'anzahl_beitraege': 5})['anzahl'],
        5,
      );
      // Fehlt sie ganz, ist es 0 und nicht null — sonst kracht die Anzeige.
      expect(SocialService.hashtagPersonZeile({'user_id': 'u1'})['anzahl'], 0);
    });

    test('Kopfzahlen lesen beide Benennungen', () {
      final a = SocialService.hashtagKennzahlenAusZeile({
        'beitraege': 17,
        'personen': 5,
      });
      expect(a.beitraege, 17);
      expect(a.personen, 5);

      final b = SocialService.hashtagKennzahlenAusZeile({
        'anzahl_beitraege': 17,
        'anzahl_personen': 5,
      });
      expect(b.beitraege, 17);
      expect(b.personen, 5);
    });
  });

  group('Hashtag-Seite: die Personenzahl steht da und ist antippbar', () {
    Future<void> aufbauen(
      WidgetTester tester, {
      required List<Map<String, dynamic>>? beitraege,
      HashtagKennzahlen? kopfzahlen,
      List<Map<String, dynamic>>? personen,
    }) async {
      await tester.pumpWidget(
        _huelle(
          HashtagBeitraegePage(
            tag: 'bmw',
            beitraegeLader: (tag, {int limit = 50, int offset = 0}) async =>
                beitraege,
            kennzahlenLader: (tag) async => kopfzahlen,
            personenLader: (tag, {int limit = 50, int offset = 0}) async =>
                personen,
          ),
        ),
      );
      await _pumpen(tester);
    }

    testWidgets('vier Beitraege von zwei Leuten: beide Zahlen stehen da', (
      tester,
    ) async {
      await aufbauen(
        tester,
        beitraege: [
          _beitrag('u1', 'anna'),
          _beitrag('u1', 'anna'),
          _beitrag('u1', 'anna'),
          _beitrag('u2', 'bert'),
        ],
        kopfzahlen: const HashtagKennzahlen(beitraege: 4, personen: 2),
      );
      expect(find.text('4 Beiträge'), findsOneWidget);
      expect(find.text('von 2 Leuten'), findsOneWidget);
    });

    testWidgets('eine einzige Person heisst „von 1 Person", nicht '
        '„von 1 Leuten"', (tester) async {
      await aufbauen(
        tester,
        beitraege: [_beitrag('u1', 'anna')],
        kopfzahlen: const HashtagKennzahlen(beitraege: 1, personen: 1),
      );
      expect(find.text('1 Beitrag'), findsOneWidget);
      expect(find.text('von 1 Person'), findsOneWidget);
      expect(find.text('von 1 Leuten'), findsNothing);
    });

    testWidgets('ohne die Kopfzahl-Abfrage wird aus der Liste gerechnet — '
        'die Seite bleibt brauchbar, bis die Migration da ist', (tester) async {
      await aufbauen(
        tester,
        beitraege: [
          _beitrag('u1', 'anna'),
          _beitrag('u2', 'bert'),
          _beitrag('u2', 'bert'),
        ],
        kopfzahlen: null,
      );
      expect(find.text('3 Beiträge'), findsOneWidget);
      expect(find.text('von 2 Leuten'), findsOneWidget);
    });

    testWidgets('eine Kopfzahl, die kleiner ist als das Sichtbare, wird nicht '
        'geglaubt — sonst stuende „Keine Beiträge" ueber drei Karten', (
      tester,
    ) async {
      await aufbauen(
        tester,
        beitraege: [
          _beitrag('u1', 'anna'),
          _beitrag('u2', 'bert'),
          _beitrag('u3', 'cem'),
        ],
        // So sieht es aus, wenn die Abfrage ihre Spalten anders nennt.
        kopfzahlen: const HashtagKennzahlen(beitraege: 0, personen: 0),
      );
      expect(find.text('3 Beiträge'), findsOneWidget);
      expect(find.text('von 3 Leuten'), findsOneWidget);
    });

    testWidgets('kein Netz sagt „konnten nicht geladen werden" und behauptet '
        'NICHT, es gebe keine Beitraege', (tester) async {
      await aufbauen(tester, beitraege: null);
      expect(
        find.text('Die Beiträge konnten nicht geladen werden.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Noch kein öffentlicher Beitrag'),
        findsNothing,
      );
      expect(find.text('Erneut versuchen'), findsOneWidget);
    });

    testWidgets('einen Hashtag, den es nicht gibt, sagt die Seite ehrlich', (
      tester,
    ) async {
      await aufbauen(tester, beitraege: const []);
      expect(
        find.textContaining('Noch kein öffentlicher Beitrag'),
        findsOneWidget,
      );
      // Ohne Personen kein antippbarer Hinweis ins Leere.
      expect(find.textContaining('von '), findsNothing);
    });

    testWidgets('Antippen der Personenzahl oeffnet die Liste der Leute', (
      tester,
    ) async {
      await aufbauen(
        tester,
        beitraege: [_beitrag('u1', 'anna'), _beitrag('u2', 'bert')],
        kopfzahlen: const HashtagKennzahlen(beitraege: 2, personen: 2),
        personen: [_person('u1', 'anna', 1), _person('u2', 'bert', 1)],
      );
      await tester.tap(find.text('von 2 Leuten'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _pumpen(tester);

      // Die alte Seite bleibt hinter der neuen im Baum stehen, deshalb wird
      // hier ausdruecklich nur im neuen Blatt gesucht.
      Finder imBlatt(String text) => find.descendant(
        of: find.byType(HashtagPersonenPage),
        matching: find.text(text),
      );
      expect(imBlatt('2 Leute haben #bmw benutzt'), findsOneWidget);
      expect(imBlatt('anna'), findsOneWidget);
      expect(imBlatt('bert'), findsOneWidget);
      expect(imBlatt('1 Beitrag'), findsNWidgets(2));
    });

    testWidgets('faellt die Personen-Abfrage aus, rechnet das Blatt sie aus '
        'den Beitraegen — statt eine Fehlermeldung zu zeigen', (tester) async {
      await aufbauen(
        tester,
        beitraege: [
          _beitrag('u1', 'anna'),
          _beitrag('u1', 'anna'),
          _beitrag('u2', 'bert'),
        ],
        kopfzahlen: null,
        personen: null,
      );
      await tester.tap(find.text('von 2 Leuten'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _pumpen(tester);

      Finder imBlatt(String text) => find.descendant(
        of: find.byType(HashtagPersonenPage),
        matching: find.text(text),
      );
      expect(imBlatt('2 Leute haben #bmw benutzt'), findsOneWidget);
      expect(imBlatt('anna'), findsOneWidget);
      expect(imBlatt('2 Beiträge'), findsOneWidget);
      expect(imBlatt('bert'), findsOneWidget);
    });
  });

  group('Personen-Blatt', () {
    Future<void> aufbauen(
      WidgetTester tester,
      Future<List<Map<String, dynamic>>?> Function(
        String tag, {
        int limit,
        int offset,
      })
      lader, {
      int seitenGroesse = 50,
    }) async {
      await tester.pumpWidget(
        _huelle(
          HashtagPersonenPage(
            tag: 'bmw',
            lader: lader,
            seitenGroesse: seitenGroesse,
          ),
        ),
      );
      await _pumpen(tester);
    }

    testWidgets('eine Person: Ueberschrift in der Einzahl', (tester) async {
      await aufbauen(
        tester,
        (tag, {int limit = 50, int offset = 0}) async => [
          _person('u1', 'anna', 3),
        ],
      );
      expect(find.text('1 Person hat #bmw benutzt'), findsOneWidget);
      expect(find.text('3 Beiträge'), findsOneWidget);
    });

    testWidgets('niemand: ehrlicher Text statt leerer Flaeche', (tester) async {
      await aufbauen(tester, (tag, {int limit = 50, int offset = 0}) async {
        return const [];
      });
      expect(find.text('Noch niemand hat #bmw benutzt.'), findsOneWidget);
    });

    testWidgets('kein Netz: anderer Text als „niemand"', (tester) async {
      await aufbauen(tester, (tag, {int limit = 50, int offset = 0}) async {
        return null;
      });
      expect(
        find.text('Die Liste konnte nicht geladen werden.'),
        findsOneWidget,
      );
      expect(find.text('Noch niemand hat #bmw benutzt.'), findsNothing);
      expect(find.text('Erneut versuchen'), findsOneWidget);
    });

    testWidgets('viele Leute: es wird nachgeladen und die Ueberschrift '
        'behauptet vorher keine Endzahl', (tester) async {
      final angefragteVersaetze = <int>[];
      List<Map<String, dynamic>> seite(int von, int bis) => [
        for (var i = von; i < bis; i++) _person('u$i', 'person$i', 1),
      ];

      await aufbauen(tester, (tag, {int limit = 50, int offset = 0}) async {
        angefragteVersaetze.add(offset);
        if (offset == 0) return seite(0, 12);
        return seite(12, 15);
      }, seitenGroesse: 12);

      expect(
        find.text('Mindestens 12 Leute haben #bmw benutzt'),
        findsOneWidget,
      );
      expect(angefragteVersaetze, [0]);

      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await _pumpen(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(angefragteVersaetze, [0, 12]);

      // Zurueck nach oben: eine ListView baut nur, was sichtbar ist, sonst
      // ist die Ueberschrift gar nicht im Baum.
      await tester.drag(find.byType(ListView), const Offset(0, 1200));
      await _pumpen(tester);
      expect(find.text('15 Leute haben #bmw benutzt'), findsOneWidget);
      expect(find.text('Mindestens 12 Leute haben #bmw benutzt'), findsNothing);
    });
  });

  group('Client und Migration muessen dieselben Namen benutzen', () {
    // Dieselbe Fehlerklasse wie bei der Laender-Klassifikation: laeuft ein
    // Name auseinander, ist die Personenzahl still weg. Die Seite zeigt dann
    // klaglos die aus der Liste gerechnete Ersatzzahl, und niemand merkt,
    // dass die Abfrage nie antwortet.
    late String migration;

    setUpAll(() {
      migration = File(
        'supabase/migrations/'
        '20260824120000_hashtag_personen_und_kennzahlen.sql',
      ).readAsStringSync();
    });

    test('die Abfragen heissen so, wie der Dienst sie ruft', () {
      expect(
        migration.contains(
          'create or replace function public.hashtag_personen(',
        ),
        isTrue,
      );
      expect(
        migration.contains(
          'create or replace function public.hashtag_kennzahlen(',
        ),
        isTrue,
      );
    });

    test('die Spalten heissen so, wie der Dienst sie liest', () {
      // hashtag_personen liefert die Haeufigkeit als `beitraege`.
      expect(migration.contains('beitraege  bigint'), isTrue);
      // hashtag_kennzahlen liefert die beiden Kopfzahlen.
      expect(migration.contains('beitraege_anzahl  bigint'), isTrue);
      expect(migration.contains('personen_anzahl   bigint'), isTrue);
    });

    test('die Parameter heissen p_tag, p_limit, p_offset', () {
      expect(migration.contains('p_tag    text'), isTrue);
      expect(migration.contains('p_limit  int'), isTrue);
      expect(migration.contains('p_offset int'), isTrue);
    });
  });

  group('was im Code stehen muss', () {
    late String seite;
    late String blatt;
    late String service;

    String ohneKommentare(String quelle) => quelle
        .split('\n')
        .where((zeile) {
          final t = zeile.trimLeft();
          return !t.startsWith('//') && !t.startsWith('///');
        })
        .join('\n');

    setUpAll(() {
      seite = ohneKommentare(
        File(
          'lib/presentation/pages/hashtag_beitraege_page.dart',
        ).readAsStringSync(),
      );
      blatt = ohneKommentare(
        File(
          'lib/presentation/pages/hashtag_personen_page.dart',
        ).readAsStringSync(),
      );
      service = ohneKommentare(
        File('lib/data/services/social_service.dart').readAsStringSync(),
      );
    });

    test('die Personenzahl kommt NICHT aus hashtag_vorschlaege — die Spalte '
        'anzahl zaehlt dort Beitraege, nicht Leute', () {
      expect(blatt.contains('hashtag_vorschlaege'), isFalse);
      expect(seite.contains('hashtagVorschlaege'), isFalse);
    });

    test('der Name der Abfrage steht an genau einer Stelle', () {
      expect(
        service.contains("rpcHashtagPersonen = 'hashtag_personen'"),
        isTrue,
      );
      expect(
        service.contains("rpcHashtagKennzahlen = 'hashtag_kennzahlen'"),
        isTrue,
      );
      // Nirgends sonst ausgeschrieben: sonst muesste man beim Umbenennen
      // suchen statt zu aendern.
      expect(blatt.contains("'hashtag_personen'"), isFalse);
      expect(seite.contains("'hashtag_personen'"), isFalse);
    });

    test('ein Fehler in der Abfrage kommt als null zurueck und NICHT als '
        'leere Liste — sonst behauptet die Seite bei abgeschaltetem Netz, es '
        'gebe keine Beitraege', () {
      final start = service.indexOf('hashtagBeitraegeErgebnis(');
      expect(start, greaterThan(0));
      final ende = service.indexOf('hashtagBeitraege(', start);
      expect(ende, greaterThan(start));
      final rumpf = service.substring(start, ende);
      expect(rumpf.contains('} catch (e) {'), isTrue);
      expect(
        rumpf
            .substring(rumpf.indexOf('} catch (e) {'))
            .contains('return null;'),
        isTrue,
      );
    });

    test('echte Umlaute in den Nutzertexten des neuen Blattes', () {
      expect(blatt.contains('Beiträge'), isTrue);
      expect(blatt.contains('Beitraege\''), isFalse);
      expect(blatt.contains('öffentlichen Beitrag'), isTrue);
    });

    test('keine Gedankenstriche in den Nutzertexten', () {
      // In Kommentaren sind sie erlaubt, in dem, was der Nutzer liest, nicht.
      // `blatt` ist bereits ohne Kommentarzeilen.
      for (final zeile in blatt.split('\n')) {
        expect(
          zeile.contains('—') || zeile.contains('–'),
          isFalse,
          reason: 'Gedankenstrich in einem Nutzertext: $zeile',
        );
      }
    });
  });
}
