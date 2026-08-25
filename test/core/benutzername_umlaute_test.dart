import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/social_service.dart';

/// 2026-08-25 — Vucko: „schau auch noch das man beim benutzernamen aeoeue
/// verwenden kann das ist bis jetzt nicht gegangen".
///
/// Zwei Dinge muessen zusammen stimmen, sonst aergert sich der Nutzer zweimal:
///
/// 1. Er muss ä ö ü ß TIPPEN koennen. Bisher frassen zwei
///    `FilteringTextInputFormatter` die Zeichen schon bei der Eingabe weg —
///    man drueckt „ü" und es erscheint gar nichts.
/// 2. Die App muss dieselbe Regel benutzen wie die Datenbank. Sagt die App
///    „frei" und der Server lehnt danach ab, ist das schlimmer als vorher.
///
/// Der wichtigste Test hier ist der Vergleich der FALTUNG mit der Migration:
/// „mueller" und „müller" duerfen nicht zwei Konten sein, sonst haelt jeder
/// eine Nachricht von „@müller" fuer eine von „@mueller". Dieselbe
/// Fehlerklasse wie bei der Laender-Klassifikation und bei den Hashtags.
void main() {
  /// Simuliert, was die Tastatur macht: Zeichen fuer Zeichen einfuegen und
  /// jeden Formatter darueberlaufen lassen.
  String tippe(String text) {
    var value = TextEditingValue.empty;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      var next = TextEditingValue(
        text: value.text + char,
        selection: TextSelection.collapsed(offset: value.text.length + 1),
      );
      for (final formatter in AppInputLimits.usernameFormatters) {
        next = formatter.formatEditUpdate(value, next);
      }
      value = next;
    }
    return value.text;
  }

  group('Der Nutzer muss Umlaute tippen koennen', () {
    test('ä ö ü Ä Ö Ü ß ueberleben die Eingabe', () {
      expect(tippe('müller'), 'müller');
      expect(tippe('Jürgen'), 'Jürgen');
      expect(tippe('gruß_öäü'), 'gruß_öäü');
      expect(tippe('ÄÖÜ'), 'ÄÖÜ');
    });

    test('sonst kommt nichts Neues dazu — kyrillisch, griechisch, Emoji und '
        'Leerzeichen bleiben draussen', () {
      // Das kyrillische „а" sieht aus wie das lateinische „a". Wer es tippen
      // darf, kann jeden fremden @-Namen zeichengenau nachbauen.
      expect(tippe('mаx'), 'mx');
      expect(tippe('πάτερ'), '');
      expect(tippe('max🚗'), 'max');
      expect(tippe('max mustermann'), 'maxmustermann');
      expect(tippe('max.muster'), 'maxmuster');
      expect(tippe('café'), 'caf');
    });

    test('die Laengenbegrenzung bleibt', () {
      expect(tippe('ü' * 30).length, AppInputLimits.usernameMaxLength);
    });
  });

  group('Formatregel', () {
    test('Umlaut-Namen sind gueltig', () {
      expect(AppInputLimits.isValidUsername('müller'), isTrue);
      expect(AppInputLimits.isValidUsername('Jürgen'), isTrue);
      expect(AppInputLimits.isValidUsername('gruß'), isTrue);
      expect(AppInputLimits.isValidUsername('öäü'), isTrue);
    });

    test('fremde Alphabete bleiben ungueltig', () {
      expect(AppInputLimits.isValidUsername('mаx'), isFalse); // kyrillisch
      expect(AppInputLimits.isValidUsername('café'), isFalse);
      expect(AppInputLimits.isValidUsername('max muster'), isFalse);
    });

    test('dieselben Zusatzregeln wie is_valid_username_format in der '
        'Datenbank: kein __, nicht mit _ beginnen oder enden', () {
      expect(AppInputLimits.isValidUsername('max__müller'), isFalse);
      expect(AppInputLimits.isValidUsername('_müller'), isFalse);
      expect(AppInputLimits.isValidUsername('müller_'), isFalse);
      expect(AppInputLimits.isValidUsername('max_müller'), isTrue);
    });

    test('Laenge 3 bis 20 gilt weiter', () {
      expect(AppInputLimits.isValidUsername('mü'), isFalse);
      expect(AppInputLimits.isValidUsername('müü'), isTrue);
      expect(AppInputLimits.isValidUsername('ü' * 21), isFalse);
    });
  });

  group(
    'Faltung: „müller" ist nicht mehr frei, wenn „Mueller" vergeben ist',
    () {
      test(
        'Umlaute und Gross-/Kleinschreibung ergeben denselben Schluessel',
        () {
          expect(AppInputLimits.usernameKey('müller'), 'mueller');
          expect(AppInputLimits.usernameKey('Müller'), 'mueller');
          expect(AppInputLimits.usernameKey('MUELLER'), 'mueller');
          expect(AppInputLimits.usernameKey('Mueller'), 'mueller');
          expect(AppInputLimits.usernameKey('gruß'), 'gruss');
          expect(AppInputLimits.usernameKey('Straße'), 'strasse');
          expect(AppInputLimits.usernameKey('Jürgen'), 'juergen');
        },
      );

      test('verschiedene Namen bleiben verschieden', () {
        expect(
          AppInputLimits.usernameKey('kontour') ==
              AppInputLimits.usernameKey('koentour'),
          isFalse,
        );
        expect(AppInputLimits.usernameKey('max_1'), 'max_1');
      });

      test('angezeigt wird immer das Getippte — die Faltung veraendert den '
          'Namen nicht', () {
        const getippt = 'Jürgen';
        expect(AppInputLimits.sanitizeUsername(getippt), getippt);
        expect(AppInputLimits.usernameKey(getippt) == getippt, isFalse);
      });
    },
  );

  group('App-Regel und Datenbank-Regel duerfen nicht auseinanderlaufen', () {
    late String migration;

    setUpAll(() {
      migration = File(
        'supabase/migrations/'
        '20260825100000_benutzername_umlaute_und_verwechslungsschutz.sql',
      ).readAsStringSync();
    });

    /// Der Zeichenvorrat, den die Datenbank erlaubt. Der CHECK und
    /// `is_valid_username_format` loeschen alle erlaubten Zeichen mit
    /// `translate` aus dem Namen — bleibt etwas uebrig, war es verboten.
    String erlaubteZeichenDerDatenbank() {
      final treffer = RegExp(
        r"translate\(\s*\w+,\s*'([^']+)',\s*''\s*\)",
      ).allMatches(migration).map((m) => m.group(1)!).toSet();
      expect(
        treffer.length,
        1,
        reason:
            'Die Migration nennt mehr als einen Zeichenvorrat. Dann pruefen '
            'CHECK und is_valid_username_format nicht mehr dasselbe.',
      );
      return treffer.single;
    }

    test('die App laesst genau die Zeichen zu, die auch die Datenbank '
        'zulaesst', () {
      final ausDerDatenbank = erlaubteZeichenDerDatenbank().split('').toSet();
      final ausDerApp = <String>{
        for (var c = 'A'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++)
          String.fromCharCode(c),
        for (var c = 'a'.codeUnitAt(0); c <= 'z'.codeUnitAt(0); c++)
          String.fromCharCode(c),
        for (var c = '0'.codeUnitAt(0); c <= '9'.codeUnitAt(0); c++)
          String.fromCharCode(c),
        '_',
        'ä',
        'ö',
        'ü',
        'Ä',
        'Ö',
        'Ü',
        'ß',
      };
      // Gegenprobe, dass die Liste oben wirklich die der App ist.
      expect(
        AppInputLimits.usernameAllowedChars,
        r'A-Za-z0-9_äöüÄÖÜß',
        reason: 'Zeichenvorrat der App geaendert — Liste im Test nachziehen.',
      );
      expect(
        ausDerApp.difference(ausDerDatenbank),
        isEmpty,
        reason:
            'Die App laesst Zeichen tippen, die die Datenbank ablehnt. Dann '
            'sagt die App „frei" und der Server lehnt beim Speichern ab.',
      );
      expect(
        ausDerDatenbank.difference(ausDerApp),
        isEmpty,
        reason:
            'Die Datenbank erlaubt mehr als die App. Dann kann ein bereits '
            'vergebener Name in der App nicht mehr eingetippt werden.',
      );
    });

    test('die Datenbank hat dieselben Unterstrich-Regeln wie die App', () {
      for (final regel in [r"p !~ '__'", r"p !~ '^_'", r"p !~ '_$'"]) {
        expect(
          migration.contains(regel),
          isTrue,
          reason:
              'is_valid_username_format prueft $regel nicht mehr. Dann muss '
              'AppInputLimits.isValidUsername mit.',
        );
      }
      expect(migration.contains('char_length(p) >= 3'), isTrue);
      expect(migration.contains('char_length(p) <= 20'), isTrue);
      expect(AppInputLimits.usernameMinLength, 3);
      expect(AppInputLimits.usernameMaxLength, 20);
    });

    test('die Faltung ist dieselbe wie in benutzername_schluessel', () {
      // Aus der Funktion die Paare herausziehen: replace(..., 'ä', 'ae') …
      final funktion = migration.substring(
        migration.indexOf('function public.benutzername_schluessel'),
        migration.indexOf('comment on function public.benutzername_schluessel'),
      );
      final paare = <String, String>{
        for (final m in RegExp(r"'([^']+)', '([^']+)'").allMatches(funktion))
          m.group(1)!: m.group(2)!,
      };
      expect(
        paare,
        AppInputLimits.usernameKeyReplacements,
        reason:
            'benutzername_schluessel faltet andere Zeichen als '
            'AppInputLimits.usernameKey. Dann erklaert die App dem Nutzer '
            'etwas anderes, als die Datenbank tut.',
      );
      expect(
        funktion.contains('lower(p_name)'),
        isTrue,
        reason:
            'Die Datenbank faltet die Gross-/Kleinschreibung nicht mehr — '
            'dann darf usernameKey das auch nicht mehr tun.',
      );
      for (final paar in paare.entries) {
        expect(AppInputLimits.usernameKey('x${paar.key}x'), 'x${paar.value}x');
      }
    });

    test('die Datenbank vergleicht Namen ueber die Faltung — sonst waere die '
        'Erklaerung in der App gelogen', () {
      expect(
        migration.contains('ux_profiles_username_schluessel'),
        isTrue,
        reason: 'Ohne UNIQUE-Index ueber die Faltung ist „müller" doch frei.',
      );
      expect(
        migration.contains(
          'public.benutzername_schluessel(username) = v_schluessel',
        ),
        isTrue,
        reason: 'username_available/set_username vergleichen ungefaltet.',
      );
    });
  });

  /// Am 25.08.2026 direkt gegen die Datenbank gemessen (Supabase-MCP,
  /// Projekt tlcfaxvvqzobmzwvfnvb, nach dem Einspielen der Migration):
  ///   select v, public.is_valid_username_format(v),
  ///             public.benutzername_schluessel(v) from proben(v);
  /// Weicht die App hier ab, sagt sie dem Nutzer etwas anderes als der
  /// Server — genau der Fall, den wir vermeiden wollen.
  group('Gemessen gegen die laufende Datenbank', () {
    const gemessen = <String, (bool, String)>{
      'müller': (true, 'mueller'),
      'Müller': (true, 'mueller'),
      'MUELLER': (true, 'mueller'),
      'Jürgen': (true, 'juergen'),
      'gruß': (true, 'gruss'),
      'mü': (false, 'mue'),
      'max__müller': (false, 'max__mueller'),
      '_müller': (false, '_mueller'),
      'müller_': (false, 'mueller_'),
      'mаx': (false, 'mаx'), // kyrillisches а
      'café': (false, 'café'),
      'max muster': (false, 'max muster'),
      'Jürgen_Müller': (true, 'juergen_mueller'),
      'öäü': (true, 'oeaeue'),
      'Straße': (true, 'strasse'),
      'max_1': (true, 'max_1'),
      'koentour': (true, 'koentour'),
    };

    test(
      'gueltig/ungueltig und Schluessel stimmen mit dem Server ueberein',
      () {
        for (final probe in gemessen.entries) {
          expect(
            AppInputLimits.isValidUsername(probe.key),
            probe.value.$1,
            reason: '„${probe.key}": die Datenbank sagt ${probe.value.$1}.',
          );
          expect(
            AppInputLimits.usernameKey(probe.key),
            probe.value.$2,
            reason:
                '„${probe.key}": die Datenbank faltet zu „${probe.value.$2}".',
          );
        }
      },
    );
  });

  group('Vorschlag beim Anmelden ueber Apple oder Google', () {
    test('„Jürgen Müller" wird nicht mehr zu „J_rgen_M_ller"', () {
      expect(AppInputLimits.sanitizeUsername('Jürgen Müller'), 'Jürgen_Müller');
      expect(AppInputLimits.sanitizeUsername('Jürgen'), 'Jürgen');
    });

    test('der Vorschlag ist danach gueltig — kein __ , kein _ am Rand', () {
      final vorschlaege = [
        'Jürgen Müller',
        '  ..Jörg..  ',
        'Max   Müller',
        'Anna-Sophie Öztürk',
        'Über.Alles.Größer.Als.Zwanzig.Zeichen',
      ];
      for (final roh in vorschlaege) {
        final name = AppInputLimits.sanitizeUsername(roh);
        expect(
          AppInputLimits.isValidUsername(name),
          isTrue,
          reason: '„$roh" ergibt „$name" — das lehnt die Datenbank ab.',
        );
      }
    });

    test('normalizeUsernameFallback behaelt Umlaute und bleibt gueltig', () {
      expect(AppInputLimits.normalizeUsernameFallback('jürgen'), 'jürgen');
      expect(
        AppInputLimits.isValidUsername(
          AppInputLimits.normalizeUsernameFallback('ö'),
        ),
        isTrue,
      );
      expect(AppInputLimits.normalizeUsernameFallback('...'), 'Cruiser');
    });
  });

  group('Eingabefeld und Erwaehnung meinen dieselben Zeichen', () {
    test('AppInputLimits.usernameAllowedChars und '
        'SocialService.usernameCharClass beschreiben dieselbe Menge', () {
      // Zwei Konstanten fuer dieselbe Regel: die eine entscheidet, was man
      // TIPPEN darf, die andere, was in einem Beitrag als @-Erwaehnung
      // erkannt wird. Laufen sie auseinander, kann man sich einen Namen
      // geben, den niemand mehr erwaehnen kann — und der Erwaehnte erfaehrt
      // nichts davon.
      String menge(String klasse) {
        final zeichen = <String>{};
        for (var c = 32; c < 0x180; c++) {
          final s = String.fromCharCode(c);
          if (RegExp('[$klasse]').hasMatch(s)) zeichen.add(s);
        }
        final sortiert = zeichen.toList()..sort();
        return sortiert.join();
      }

      expect(
        menge(AppInputLimits.usernameAllowedChars),
        menge(SocialService.usernameCharClass),
        reason:
            'Eingabefeld und @-Erwaehnung erlauben unterschiedliche Zeichen.',
      );
    });
  });

  group('Die Fehlermeldung sagt, WARUM der Name vergeben ist', () {
    test('bei Umlauten oder Grossbuchstaben steht der andere Name da', () {
      final hinweis = AppInputLimits.usernameFoldingHint('müller');
      expect(hinweis, contains('mueller'));
      expect(hinweis, contains('müller'));
    });

    test('kein Hinweis, wenn es nichts zu erklaeren gibt', () {
      expect(AppInputLimits.usernameFoldingHint('mueller'), isEmpty);
      expect(AppInputLimits.usernameFoldingHint(''), isEmpty);
    });
  });
}
