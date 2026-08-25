import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/widgets/mentions.dart';

/// 2026-08-25 — Auftrag Vucko: „schau auch noch das man beim benutzernamen
/// aeoeue verwenden kann das ist bis jetzt nicht gegangen".
///
/// Diese Datei sichert die Erwähnungs-Seite davon ab. Der auffällige Teil ist
/// die Anzeige: hieße jemand „müller", würde aus „@müller" ohne diese
/// Änderung nur „@m" verlinkt und der Rest bliebe toter Text. Der teure Teil
/// ist der stumme: trifft das Muster den Namen nicht, bekommt der Erwähnte
/// KEINE Benachrichtigung — und niemand merkt es, weder der Schreiber noch
/// der Gemeinte.
///
/// Verglichen wird über `SocialService.usernameKey`. Diese Faltung ist
/// zeichengleich mit `public.hashtag_schluessel` aus Migration
/// 20260824102000 — dieselbe Fehlerklasse wie bei der Länder-Klassifikation:
/// zwei Verfahren für dieselbe Frage laufen irgendwann auseinander.
void main() {
  group('Das Muster trifft den ganzen Namen, nicht nur den ASCII-Anfang', () {
    test('deutsche Umlaute und ß gehören zum Namen', () {
      expect(extractMentionUsernames('@müller'), {'müller'});
      expect(extractMentionUsernames('@straße'), {'straße'});
      expect(extractMentionUsernames('@Öltemperatur'), {'öltemperatur'});
      expect(extractMentionUsernames('@Kurvenkönig'), {'kurvenkönig'});
    });

    test('sonst nichts Neues: kein Kyrillisch, kein Akzent, kein Emoji', () {
      // Das kyrillische „а" sieht aus wie das lateinische „a". Wäre es
      // erlaubt, könnte jeder Name exakt nachgebaut werden — und eine
      // Nachricht von „@müller" käme in Wahrheit von einem Doppelgänger.
      expect(extractMentionUsernames('@алекс'), isEmpty);
      expect(extractMentionUsernames('@αλφα'), isEmpty);
      // Ein Akzent ist kein deutscher Umlaut: der Name endet davor.
      expect(extractMentionUsernames('@josé'), {'jos'});
      expect(extractMentionUsernames('@müller😀'), {'müller'});
    });

    test('das Satzzeichen gehört nicht zum Namen', () {
      expect(extractMentionUsernames('Danke @müller.'), {'müller'});
      expect(extractMentionUsernames('Hallo @müller, und @jörg!'), {
        'müller',
        'jörg',
      });
      expect(extractMentionUsernames('Kommst du auch, @straße?'), {'straße'});
      expect(extractMentionUsernames('(@müller)'), {'müller'});
      expect(extractMentionUsernames('@müller\n@jörg'), {'müller', 'jörg'});
    });

    test('der Punkt gehört NICHT mehr zum Token', () {
      // Vorher stand im Service `@([A-Za-z0-9_\.]+)`. „Danke @vucko." ergab
      // damit „vucko." — ein Name, den es in keiner Zeile von `profiles`
      // geben kann, weil `profiles_username_format` nur [A-Za-z0-9_] zulässt.
      // Die Anzeige verlinkte trotzdem „@vucko" (ihr Muster kannte den Punkt
      // nicht). Ergebnis: sichtbarer Link, keine Benachrichtigung.
      final treffer = SocialService.usernameMentionPattern
          .allMatches('Danke @vucko. Und @müller.')
          .map((m) => m.group(1))
          .toList();
      expect(treffer, ['vucko', 'müller']);
    });
  });

  group('Die Faltung ist die aus dem Haus, keine zweite', () {
    test('Umlaut und Ausschreibung fallen zusammen', () {
      expect(SocialService.usernameKey('müller'), 'mueller');
      expect(SocialService.usernameKey('Müller'), 'mueller');
      expect(SocialService.usernameKey('MUELLER'), 'mueller');
      expect(SocialService.usernameKey('mueller'), 'mueller');
      expect(SocialService.usernameKey('Straße'), 'strasse');
      expect(SocialService.usernameKey('STRASSE'), 'strasse');
      expect(SocialService.usernameKey('  Vucko  '), 'vucko');
    });

    test('was nicht zusammengehört, bleibt getrennt', () {
      expect(
        SocialService.usernameKey('kontour') ==
            SocialService.usernameKey('kontur'),
        isFalse,
      );
      expect(
        SocialService.usernameKey('muller') ==
            SocialService.usernameKey('müller'),
        isFalse,
        reason: '„muller" ist ein anderer Name als „müller"/„mueller"',
      );
    });

    test('zeichengleich mit public.hashtag_schluessel — läuft die Migration '
        'weg, wird dieser Test rot', () {
      final sql = File(
        'supabase/migrations/20260824102000_lesestand_und_hashtags.sql',
      ).readAsStringSync();
      final anfang = sql.indexOf(
        'create or replace function public.hashtag_schluessel',
      );
      final ende = sql.indexOf('comment on function public.hashtag_schluessel');
      expect(anfang, greaterThan(0));
      expect(ende, greaterThan(anfang));
      final literale = RegExp("'([^']*)'")
          .allMatches(sql.substring(anfang, ende))
          .map((m) => m.group(1)!)
          .toList();
      expect(literale.length, greaterThanOrEqualTo(18));

      final quelle = File(
        'lib/data/services/social_service.dart',
      ).readAsStringSync();
      // Die acht ausgeschriebenen Ersetzungen, paarweise.
      for (var i = 0; i + 1 < literale.length - 2; i += 2) {
        expect(
          quelle.contains("'${literale[i]}': '${literale[i + 1]}'"),
          isTrue,
          reason:
              'die Migration faltet ${literale[i]} auf ${literale[i + 1]}, '
              'usernameKey nicht',
        );
      }
      // Die beiden Tabellen der translate()-Zeile, zeichengleich.
      final akzente = literale[literale.length - 2];
      final ersatz = literale[literale.length - 1];
      expect(akzente.length, ersatz.length);
      expect(quelle.contains(akzente), isTrue);
      expect(quelle.contains(ersatz), isTrue);
    });
  });

  group('Nachschlagen findet denselben Namen wie die Datenbank', () {
    test('alle Schreibweisen einer Eingabe', () {
      expect(SocialService.usernameSpellings('mueller'), contains('müller'));
      expect(SocialService.usernameSpellings('müller'), contains('mueller'));
      expect(SocialService.usernameSpellings('Straße'), contains('Strasse'));
      expect(SocialService.usernameSpellings('strasse'), contains('straße'));
      // Die eingetippte Schreibweise ist immer dabei.
      expect(SocialService.usernameSpellings('müller'), contains('müller'));
    });

    test('jede Variante hat denselben Schlüssel — deshalb kann nie der '
        'falsche Mensch herauskommen', () {
      for (final name in ['müller', 'Straßenkoenig', 'joerg_ue']) {
        final schluessel = SocialService.usernameKey(name);
        for (final variante in SocialService.usernameSpellings(name)) {
          expect(SocialService.usernameKey(variante), schluessel);
        }
      }
    });

    test('die Liste ist gedeckelt — ein Name mit vielen Umlauten darf keine '
        'Filterbedingung mit hunderten Zweigen erzeugen', () {
      expect(
        SocialService.usernameSpellings('üüüüüüüü').length,
        lessThanOrEqualTo(16),
      );
      expect(SocialService.usernameSpellings('  '), isEmpty);
    });

    test('ein vollständiger Name lässt nur Namenszeichen zu', () {
      expect(SocialService.usernameFullPattern.hasMatch('müller'), isTrue);
      expect(SocialService.usernameFullPattern.hasMatch('müller.'), isFalse);
      expect(SocialService.usernameFullPattern.hasMatch('a,b'), isFalse);
      expect(SocialService.usernameFullPattern.hasMatch(''), isFalse);
    });
  });

  group('Die Vorschläge beim Tippen reissen beim Umlaut nicht ab', () {
    test('der Prefix darf Umlaute enthalten und leer sein', () {
      expect(SocialService.usernamePrefixPattern.hasMatch(''), isTrue);
      expect(SocialService.usernamePrefixPattern.hasMatch('mü'), isTrue);
      expect(SocialService.usernamePrefixPattern.hasMatch('straß'), isTrue);
      expect(SocialService.usernamePrefixPattern.hasMatch('mü ler'), isFalse);
      expect(SocialService.usernamePrefixPattern.hasMatch('алекс'), isFalse);
    });

    test('„mue" getippt findet „müller" — beide Seiten werden gefaltet', () {
      final schluessel = SocialService.usernameKey('müller');
      expect(schluessel.startsWith(SocialService.usernameKey('mue')), isTrue);
      expect(schluessel.startsWith(SocialService.usernameKey('mü')), isTrue);
      expect(schluessel.startsWith(SocialService.usernameKey('m')), isTrue);
      expect(schluessel.startsWith(SocialService.usernameKey('ma')), isFalse);
    });
  });

  group('Angezeigt wird, was getippt wurde', () {
    test('der Handle verstümmelt den Umlaut nicht mehr', () {
      // Vorher machte `[^a-z0-9]` aus „Müller" ein „@m_ller" — überall dort,
      // wo ein Handle steht (Feed, Profil, Glocke, Community-Karte).
      expect(SocialService.publicHandle({'username': 'Müller'}), '@müller');
      expect(SocialService.publicHandle({'username': 'Straße'}), '@straße');
    });

    test('Altbestände ohne gültigen Namen werden weiter geschnitten', () {
      expect(
        SocialService.publicHandle({'username': 'Max Power'}),
        '@max_power',
      );
    });
  });

  group('Es gibt nur EIN Muster', () {
    late String service;
    late String mentions;

    setUpAll(() {
      String ohneKommentare(String quelle) => quelle
          .split('\n')
          .where((zeile) {
            final t = zeile.trimLeft();
            return !t.startsWith('//') && !t.startsWith('///');
          })
          .join('\n');
      service = ohneKommentare(
        File('lib/data/services/social_service.dart').readAsStringSync(),
      );
      mentions = ohneKommentare(
        File('lib/presentation/widgets/mentions.dart').readAsStringSync(),
      );
    });

    test('die Anzeige benutzt das Muster des Service, keine Kopie', () {
      expect(mentions.contains('SocialService.usernameMentionPattern'), isTrue);
      expect(mentions.contains(r"RegExp(r'@("), isFalse);
      expect(mentions.contains(r"RegExp('@("), isFalse);
    });

    test('das Eingabefeld benutzt denselben Zeichensatz', () {
      expect(mentions.contains('SocialService.usernamePrefixPattern'), isTrue);
      expect(mentions.contains(r'^[A-Za-z0-9_]*$'), isFalse);
    });

    test('auch die Personensuche fragt nach allen Schreibweisen — sonst '
        'findet man den Menschen nicht, den man erwähnen will', () {
      final stelle = service.indexOf('searchUsers(');
      expect(stelle, greaterThan(0));
      expect(
        service.substring(stelle, stelle + 900).contains('usernameSpellings('),
        isTrue,
      );
    });

    test('der Zeichensatz steht genau einmal', () {
      expect(
        service.contains(r"usernameCharClass = 'A-Za-z0-9_ÄÖÜäöüß'"),
        isTrue,
      );
      expect(service.contains(r'A-Za-z0-9_\.'), isFalse);
      expect(mentions.contains('A-Za-z0-9_'), isFalse);
    });
  });
}
