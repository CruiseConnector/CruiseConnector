import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/auth_service.dart';

/// 2026-08-31 — Vucko: „dass man sich auch mit seinen Benutzernamen nur mit
/// seinem Passwort anmelden kann."
///
/// Der gefaehrliche Teil dieser Aufgabe ist NICHT die Anmeldung, sondern die
/// Aufloesung Name -> E-Mail. Die @-Namen sind oeffentlich, die Adressen
/// nicht. Wer diese Aufloesung dem Client gibt, macht aus jeder Namensliste
/// eine Adressliste.
///
/// Dieser Test haelt genau das fest: die Aufloesung darf nur serverseitig
/// existieren, sie darf nur `service_role` offenstehen, und aus der Edge
/// Function darf nie eine Adresse zurueckkommen. Er liest dafuer die
/// Migration und die Edge Function als Text — genauso, wie
/// `test/core/benutzername_umlaute_test.dart` die Faltung der Migration mit
/// der in Dart vergleicht.
void main() {
  const edgePfad = 'supabase/functions/username-login/index.ts';
  const configPfad = 'supabase/config.toml';

  group('Aufteilung E-Mail gegen @-Name', () {
    test('das @ entscheidet, und nur das @', () {
      expect(AuthService.istEmailEingabe('vucko@example.at'), isTrue);
      expect(AuthService.istEmailEingabe('  vucko@example.at '), isTrue);
      expect(AuthService.istEmailEingabe('Vucko'), isFalse);
      expect(AuthService.istEmailEingabe('cruiser_99'), isFalse);
      // Umlaute sind seit 25.08. in @-Namen erlaubt und duerfen die
      // Entscheidung nicht durcheinanderbringen.
      expect(AuthService.istEmailEingabe('Jürgen'), isFalse);
    });

    test(
      'ein unmoeglicher @-Name geht gar nicht erst zum Server',
      () async {
        // Ohne initialisiertes Supabase wuerde jeder Netzaufruf werfen. Dass
        // hier eine AuthException mit UNSERER Kennung ankommt, beweist, dass
        // der Aufruf vorher abgefangen wurde.
        await expectLater(
          AuthService.signInWithUsername(username: 'ab', password: 'egal123'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'message',
              AuthService.fehlerAnmeldedatenFalsch,
            ),
          ),
        );
        await expectLater(
          AuthService.signInWithEmailOrUsername(
            identifier: 'nicht erlaubt!',
            password: 'egal123',
          ),
          throwsA(isA<AuthException>()),
        );
      },
    );
  });

  test('jede Fehlerkennung hat eine Uebersetzung auf der Anmeldeseite', () {
    // 2026-08-31: Der teuerste Fehler waere gewesen, eine neue Kennung
    // einzufuehren und sie auf der Seite zu vergessen — dann faellt sie in
    // „Login fehlgeschlagen" und der Nutzer erfaehrt nicht, was los ist.
    // Beim Fall „Edge noch nicht ausgerollt" waere das besonders bitter: er
    // haette sein funktionierendes Passwort fuer falsch gehalten.
    final dienst = File('lib/data/services/auth_service.dart')
        .readAsStringSync();
    final seite = File('lib/presentation/pages/login_page.dart')
        .readAsStringSync();

    final kennungen = RegExp(
      r"static const String (fehler\w+) = '([a-z_]+)';",
    ).allMatches(dienst).map((m) => m.group(1)!).toList();

    expect(
      kennungen.length,
      greaterThanOrEqualTo(4),
      reason: 'Die Kennungen im AuthService muessen gefunden werden.',
    );
    for (final kennung in kennungen) {
      expect(
        seite.contains('AuthService.$kennung'),
        isTrue,
        reason:
            'login_page.dart uebersetzt AuthService.$kennung nicht. Ohne '
            'Zweig sieht der Nutzer nur „Login fehlgeschlagen".',
      );
    }
  });

  group('Die E-Mail bleibt auf dem Server', () {
    // 2026-08-31: Die Migration wird ueber ihren INHALT gesucht, nicht ueber
    // ihren Dateinamen. Der Name traegt einen Zeitstempel, und der muss zu der
    // Version passen, unter der die Migration tatsaechlich eingespielt wurde —
    // beim Nachziehen dieses Zeitstempels ist dieser Test schon einmal
    // gerissen, obwohl an der Sache nichts falsch war.
    final migration = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .where(
          (f) => f.readAsStringSync().contains(
            'function public.anmeldename_zu_benutzer_id',
          ),
        )
        .fold<File?>(null, (a, b) => a == null || b.path.compareTo(a.path) > 0 ? b : a);
    final edge = File(edgePfad);

    test('Migration und Edge Function liegen im Repo', () {
      expect(
        migration,
        isNotNull,
        reason:
            'Keine Migration definiert public.anmeldename_zu_benutzer_id. '
            'Der Test muss aus dem Projektwurzelverzeichnis laufen; wurde die '
            'Funktion umbenannt, diesen Waechter mitziehen.',
      );
      expect(edge.existsSync(), isTrue);
    });

    test('die Aufloesung liefert eine Kennung, keine Adresse', () {
      final sql = migration!.readAsStringSync();
      expect(
        sql.contains('returns uuid'),
        isTrue,
        reason:
            'anmeldename_zu_benutzer_id darf ausschliesslich die Benutzer'
            'kennung zurueckgeben. Sobald hier eine Zeile mit Adresse '
            'herauskommt, ist jede oeffentliche Namensliste eine Adressliste.',
      );
      expect(
        RegExp(r'\bemail\b', caseSensitive: false).hasMatch(_rumpf(sql)),
        isFalse,
        reason:
            'Im Rumpf der Datenbankfunktion darf das Wort E-Mail nicht '
            'vorkommen.',
      );
    });

    test('nur service_role darf die Aufloesung aufrufen', () {
      final sql = migration!.readAsStringSync().toLowerCase();
      expect(sql.contains('security definer'), isTrue);
      expect(
        sql.contains('revoke all on function public.anmeldename_zu_benutzer_id')
            ,
        isTrue,
      );
      for (final rolle in ['public', 'anon', 'authenticated']) {
        expect(
          RegExp('grant execute on function '
                  r'public\.anmeldename_zu_benutzer_id\(text\)\s*to[^;]*'
                  '\\b$rolle\\b')
              .hasMatch(sql),
          isFalse,
          reason: 'Die Rolle $rolle darf die Aufloesung nicht ausfuehren.',
        );
      }
      expect(
        RegExp(r'grant execute on function '
                r'public\.anmeldename_zu_benutzer_id\(text\)\s*to\s*'
                r'service_role')
            .hasMatch(sql),
        isTrue,
      );
    });

    test('keine Antwort der Edge Function traegt eine Adresse', () {
      final ts = edge.readAsStringSync();
      final antworten = RegExp(r'antwort\(\s*\{([^}]*)\}', dotAll: true)
          .allMatches(ts)
          .map((m) => m.group(1) ?? '')
          .toList();
      expect(
        antworten,
        isNotEmpty,
        reason: 'Der Test muss die Antworten der Funktion finden koennen.',
      );
      for (final nutzlast in antworten) {
        // `email_nicht_bestaetigt` ist eine Fehlerkennung, keine Adresse.
        final ohneKennung = nutzlast.replaceAll('email_nicht_bestaetigt', '');
        expect(
          RegExp('email', caseSensitive: false).hasMatch(ohneKennung),
          isFalse,
          reason:
              'Diese Antwort traegt eine Adresse nach draussen: $nutzlast',
        );
      }
    });

    test('die Edge Function ist ohne Sitzung erreichbar', () {
      // Die Funktion IST die Anmeldung. Mit verify_jwt = true wiese das
      // Gateway den oeffentlichen Schluessel als „Invalid JWT" ab und niemand
      // koennte sich mit seinem Namen anmelden — dieselbe Falle, die bei
      // generate-cruise-route-v2 schon einmal zugeschnappt ist.
      final config = File(configPfad).readAsStringSync();
      final block = config.split('[functions.username-login]');
      expect(block.length, 2, reason: 'Eintrag in der config.toml fehlt.');
      final rest = block[1].split('[functions.').first;
      expect(rest.contains('verify_jwt = false'), isTrue);
      expect(rest.contains('enabled = true'), isTrue);
    });
  });
}

/// Der Funktionsrumpf zwischen den Dollar-Klammern. Alles davor und danach
/// sind Kommentare und Rechtevergabe; dort steht das Wort E-Mail zu Recht.
String _rumpf(String sql) {
  final teile = sql.split(r'$fn$');
  return teile.length >= 2 ? teile[1] : '';
}
