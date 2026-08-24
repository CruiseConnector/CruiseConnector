import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/widgets/mentions.dart';

/// 2026-08-24 — Aufgabe 1.3 aus dem Auftrag vom 23.08.
///
/// Vucko, Aufnahme 3: „wenn man was einbauen könnte, wäre, wenn man Hashtags
/// hätte […] dass man unter Hashtags Sachen suchen kann" und „für zukünftige
/// Gewinnspiele wäre das auch ganz cool, dass man da Sachen auslosen kann".
///
/// DER WICHTIGSTE TEST IN DIESER DATEI ist der Vergleich zwischen dem Muster
/// im Client und dem Muster im Trigger der Datenbank. Läuft beides
/// auseinander, macht die App etwas anklickbar, das die Suche nie findet —
/// und eine Verlosung verliert Teilnehmer, ohne dass es jemand merkt. Genau
/// diese Fehlerklasse hat uns schon die Länder-Klassifikation gekostet.
void main() {
  group('1.3 — Client-Muster und Datenbank-Muster müssen dasselbe treffen', () {
    late String migration;

    setUpAll(() {
      migration = File(
        'supabase/migrations/20260824102000_lesestand_und_hashtags.sql',
      ).readAsStringSync();
    });

    test('die Migration benutzt genau das erwartete Muster — ändert es sich '
        'dort, wird dieser Test rot', () {
      expect(
        migration.contains(r"'#([[:alpha:]_][[:alnum:]_]{1,49})'"),
        isTrue,
        reason:
            'Das Muster im Trigger post_hashtags_pflegen hat sich '
            'geändert. Dann muss hashtagPattern in mentions.dart mit.',
      );
    });

    test('erstes Zeichen Buchstabe oder Unterstrich, 2 bis 50 Zeichen', () {
      expect(extractHashtags('#ab'), {'ab'});
      expect(extractHashtags('#_privat'), {'_privat'});
      // Eine Ziffer vorn ist KEIN Hashtag. Das haelt Preise und Hausnummern
      // draussen: „#1" darf keine Verlosung ausloesen.
      expect(extractHashtags('#2026'), isEmpty);
      expect(extractHashtags('#1'), isEmpty);
      // Ein einzelnes Zeichen ist zu kurz.
      expect(extractHashtags('#a'), isEmpty);
      // Ziffern hinten sind erlaubt.
      expect(extractHashtags('#cruise2026'), {'cruise2026'});
    });

    test('50 Zeichen gehen, 51 werden abgeschnitten wie in der Datenbank', () {
      final fuenfzig = 'a' * 50;
      expect(extractHashtags('#$fuenfzig'), {fuenfzig});
      final einundfuenfzig = 'a' * 51;
      // Beide Seiten nehmen die ersten 50 Zeichen. Wichtig ist, dass sie
      // DASSELBE tun, nicht dass sie den Rest behalten.
      expect(extractHashtags('#$einundfuenfzig'), {fuenfzig});
    });

    test('Umlaute sind ein echter Fall: #kurvenkönig muss anklickbar sein', () {
      expect(extractHashtags('#kurvenkönig'), {'kurvenkönig'});
      expect(extractHashtags('#straße'), {'straße'});
      expect(extractHashtags('#Öltemperatur'), {'öltemperatur'});
    });

    test('Groß- und Kleinschreibung fällt zusammen', () {
      expect(extractHashtags('#Tourenfahrt #tourenfahrt'), {'tourenfahrt'});
    });

    test('mehrere Hashtags in einem Satz', () {
      expect(extractHashtags('Heute #kurven gefahren, danach #kaffee. Top!'), {
        'kurven',
        'kaffee',
      });
    });

    test('kein Hashtag ohne Raute', () {
      expect(extractHashtags('einfach nur Text'), isEmpty);
    });

    test('Erwähnungen und Hashtags stören sich nicht — beide Muster laufen in '
        'derselben Schleife', () {
      expect(extractMentionUsernames('@vucko schrieb #kurven'), {'vucko'});
      expect(extractHashtags('@vucko schrieb #kurven'), {'kurven'});
    });
  });

  group('1.3 — die Eingabe wird sauber gemacht, nicht gefaltet', () {
    test('führende Rauten und Leerzeichen fallen weg', () {
      expect(SocialService.normalisiereHashtagEingabe('  #kurven '), 'kurven');
      expect(SocialService.normalisiereHashtagEingabe('##kurven'), 'kurven');
      expect(SocialService.normalisiereHashtagEingabe('kurven'), 'kurven');
      expect(SocialService.normalisiereHashtagEingabe('#'), '');
      expect(SocialService.normalisiereHashtagEingabe('   '), '');
    });

    test('gefaltet wird hier NICHT — das macht die Datenbank, sonst laufen '
        'Client und Server auseinander', () {
      // Die Schreibweise bleibt, wie sie war. Erst hashtag_schluessel in
      // der Datenbank macht daraus die Vergleichsform.
      expect(
        SocialService.normalisiereHashtagEingabe('#Kurvenkönig'),
        'Kurvenkönig',
      );
    });
  });

  group('1.3 — was im Code stehen muss', () {
    late String mentions;
    late String service;
    late String page;
    late String seite;

    String ohneKommentare(String quelle) => quelle
        .split('\n')
        .where((zeile) {
          final t = zeile.trimLeft();
          return !t.startsWith('//') && !t.startsWith('///');
        })
        .join('\n');

    setUpAll(() {
      mentions = ohneKommentare(
        File('lib/presentation/widgets/mentions.dart').readAsStringSync(),
      );
      service = ohneKommentare(
        File('lib/data/services/social_service.dart').readAsStringSync(),
      );
      page = ohneKommentare(
        File('lib/presentation/pages/community_page.dart').readAsStringSync(),
      );
      seite = ohneKommentare(
        File(
          'lib/presentation/pages/hashtag_beitraege_page.dart',
        ).readAsStringSync(),
      );
    });

    test(
      'der Client SCHREIBT keine Hashtags — das macht ausschliesslich der '
      'Trigger, sonst trägt sich jemand per Aufruf in ein Gewinnspiel ein',
      () {
        expect(service.contains("from('post_hashtags')"), isFalse);
        expect(
          service.contains("insert(") && service.contains('post_hashtags'),
          isFalse,
        );
        expect(mentions.contains('post_hashtags'), isFalse);
      },
    );

    test('die Liste kommt aus der RPC, nicht aus einer Textsuche', () {
      expect(service.contains("'hashtag_beitraege'"), isTrue);
      expect(service.contains("'hashtag_vorschlaege'"), isTrue);
      // Kein ilike auf content fuer Hashtags: das faende auch „kontour".
      final stelle = service.indexOf('hashtagBeitraege(');
      expect(stelle, greaterThan(0));
      expect(
        service.substring(stelle, stelle + 900).contains('ilike'),
        isFalse,
      );
    });

    test('die Auslosungsliste ist nicht künstlich kurz — die RPC lässt bis 500 '
        'zu, die Seite holt 200', () {
      expect(seite.contains('limit: 200'), isTrue);
    });

    test('ein Hashtag im Text ist anklickbar (Akzeptanzkriterium 3)', () {
      expect(mentions.contains('HashtagBeitraegePage.oeffnen'), isTrue);
      expect(mentions.contains('hashtagPattern.allMatches(text)'), isTrue);
    });

    test('die Suche in der Community kennt Hashtags', () {
      expect(page.contains('SocialService.hashtagVorschlaege('), isTrue);
      expect(page.contains('_buildHashtagTreffer'), isTrue);
      expect(page.contains('#Hashtag'), isTrue);
    });

    test('der Gruppen-Code liegt nach dem Umbau an Index 2 — ein übersehener '
        'Index hätte die Code-Suche stumm kaputtgemacht', () {
      expect(page.contains('results[2] as Map<String, dynamic>?'), isTrue);
    });

    test('echte Umlaute in den Nutzertexten der neuen Seite', () {
      // Bezeichner bleiben englisch/ASCII (HashtagBeitraegePage), NUTZERTEXTE
      // bekommen echte Umlaute. Geprüft wird deshalb der sichtbare Text.
      //
      // 2026-08-24 (Auftrag vom 24.08., Personenzahl): Die Beitragszahl wird
      // seitdem nicht mehr in dieser Datei zusammengesetzt, sondern von
      // `hashtagBeitraegeText` in `hashtag_personen_page.dart` — sonst
      // stuende dieselbe Einzahl-/Mehrzahl-Regel an zwei Stellen. Geprüft
      // wird deshalb dort. Siehe test/community/hashtag_leute_test.dart.
      expect(seite.contains('hashtagBeitraegeText('), isTrue);
      expect(seite.contains('Beitraege\''), isFalse);
      expect(seite.contains('öffentlicher Beitrag'), isTrue);
    });
  });
}
