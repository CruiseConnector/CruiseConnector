// 2026-08-31 — Waechter fuer den Vertrag zwischen `username_available` (SQL)
// und dem Onboarding-Assistenten (Dart).
//
// WARUM ES DIESEN TEST GIBT
//
// Am 28.08. wurde `username_available` in einer Migration umgebaut. Dabei ging
// im ERFOLGSFALL der Schluessel `reason` verloren: die Funktion antwortete nur
// noch {"available": true}. Der Assistent liest aber ausschliesslich `reason`
// und schickt alles Unbekannte in seinen default-Zweig — also in die Meldung
// „Konnte gerade nicht pruefen". Damit sah JEDER freie Name wie ein
// Serverfehler aus, und der Weiter-Knopf blieb gesperrt.
//
// Der Fehler war unsichtbar: HTTP 200, keine Ausnahme, kein Eintrag im
// Fehlerprotokoll. Nur der eine fehlende Schluessel. Gemessen an den Konten:
// in den 14 Tagen davor kamen 94 von 104 Personen durch das Onboarding, in den
// Tagen danach 0 von 10.
//
// Der Test kann keine Datenbank starten. Er tut deshalb das, was hier
// tatsaechlich schuetzt: Er liest die juengste Migration, die diese Funktion
// definiert, und besteht nur, wenn JEDER Rueckgabe-Zweig einen `reason`
// mitschickt und die Menge der Gruende zu den Faellen passt, die der Client
// auswertet. Beide Dateien muessen zusammen wandern, sonst schlaegt er fehl.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die juengste Migration, die `username_available` neu definiert.
File _aktuelleMigration() {
  final ordner = Directory('supabase/migrations');
  final treffer =
      ordner
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .where(
            (f) => RegExp(
              r'create\s+or\s+replace\s+function\s+public\.username_available',
              caseSensitive: false,
            ).hasMatch(f.readAsStringSync()),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  expect(
    treffer,
    isNotEmpty,
    reason:
        'Keine Migration definiert public.username_available. Wurde die '
        'Funktion umbenannt? Dann diesen Waechter mitziehen.',
  );
  return treffer.last;
}

/// Der Rumpf der Funktion aus der Migration, ohne Kommentarzeilen — sonst
/// zaehlt der Test die Beispiele in der Begruendung mit.
String _funktionsRumpf(File migration) {
  final text = migration.readAsStringSync();
  final start = text.toLowerCase().indexOf('create or replace function');
  expect(start, greaterThanOrEqualTo(0));
  final rumpf = text.substring(start);
  return rumpf
      .split('\n')
      .where((z) => !z.trimLeft().startsWith('--'))
      .join('\n');
}

void main() {
  group('username_available haelt seinen Vertrag mit dem Client', () {
    late String rumpf;

    setUpAll(() => rumpf = _funktionsRumpf(_aktuelleMigration()));

    test('JEDER Rueckgabe-Zweig schickt einen Grund mit', () {
      final zweige = RegExp(
        r'return\s+jsonb_build_object\s*\(([^;]*?)\)\s*;',
        dotAll: true,
      ).allMatches(rumpf).map((m) => m.group(1)!).toList();

      expect(
        zweige.length,
        greaterThanOrEqualTo(4),
        reason:
            'Erwartet wurden mindestens vier Zweige (ok, invalid_format, '
            'reserved, taken). Gefunden: ${zweige.length}.',
      );

      for (final zweig in zweige) {
        expect(
          zweig,
          contains("'reason'"),
          reason:
              'Dieser Rueckgabe-Zweig schickt keinen `reason` mit:\n'
              '    return jsonb_build_object($zweig);\n'
              'Der Client liest NUR `reason`. Fehlt er, liest er \'unknown\', '
              'faellt in seinen default-Zweig und zeigt dem Nutzer '
              '„Konnte gerade nicht pruefen" — auch wenn alles in Ordnung ist. '
              'Genau so ist am 28.08. die Registrierung fuer alle '
              'ausgefallen.',
        );
      }
    });

    test('Der Erfolgsfall heisst ok und nichts anderes', () {
      final erfolg = RegExp(
        r"return\s+jsonb_build_object\s*\(\s*'available'\s*,\s*true\s*,([^;]*?)\)\s*;",
        dotAll: true,
      ).firstMatch(rumpf);

      expect(
        erfolg,
        isNotNull,
        reason:
            'Kein Zweig gibt available=true zurueck, oder er steht ohne '
            'weitere Schluessel da. Der Erfolgsfall muss lauten: '
            "jsonb_build_object('available', true, 'reason', 'ok')",
      );
      expect(
        erfolg!.group(1),
        contains("'ok'"),
        reason:
            'Der Erfolgsfall traegt einen anderen Grund als \'ok\'. Der '
            'Assistent kennt in seinem switch nur \'ok\' als freien Namen; '
            'jeder andere Wert landet in der Fehlermeldung.',
      );
    });

    test('Die Gruende decken sich mit den Faellen, die der Client auswertet', () {
      final ausSql = RegExp(r"'reason'\s*,\s*'([a-z_]+)'")
          .allMatches(rumpf)
          .map((m) => m.group(1)!)
          .toSet();

      final assistent = File(
        'lib/presentation/pages/onboarding/onboarding_wizard_page.dart',
      ).readAsStringSync();
      final ausDart = RegExp(r"case\s+'([a-z_]+)'\s*:")
          .allMatches(assistent)
          .map((m) => m.group(1)!)
          .toSet();

      final unbehandelt = ausSql.difference(ausDart);
      expect(
        unbehandelt,
        isEmpty,
        reason:
            'Die Datenbank kann $unbehandelt zurueckgeben, aber der Assistent '
            'behandelt das nicht — es landet in seinem default-Zweig und wird '
            'dem Nutzer als Serverfehler gezeigt. Entweder den Fall im '
            'switch ergaenzen oder ihn in der SQL-Funktion nicht senden.',
      );
    });
  });
}
