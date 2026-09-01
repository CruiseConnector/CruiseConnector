// 2026-09-01 — Kritiker-Befund an meiner eigenen Aenderung:
//
//   "profiles.badges bleibt append-only — aber nur wegen eines Ausloesers,
//    nicht wegen des Client-Codes. previousBadges wird mit [] initialisiert,
//    die Leseabfrage steht in einem try/catch, das den Fehler nur in
//    debugPrint schreibt, und danach schreibt das UPDATE unlockedBadges als
//    VOLLSTAENDIGE Liste."
//
// Die Zusage stand also nur im Kommentar. Dieser Test nagelt beide Haelften
// fest: den Ausloeser in der Datenbank UND den Rueckfall im Client.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Abzeichen koennen nicht still verschwinden', () {
    test('der Client schreibt die Spalte nur mit gelesenem Stand', () {
      final quelle = File(
        'lib/data/services/gamification_service.dart',
      ).readAsStringSync();

      expect(
        quelle.contains("if (standGelesen) 'badges': unlockedBadges,"),
        isTrue,
        reason:
            'Scheitert die Leseabfrage, darf die Abzeichen-Spalte gar nicht '
            'mitgeschrieben werden — eine leere Vorgeschichte plus ein '
            'Netzfehler bei den Kennzahlen ergaebe sonst eine KUERZERE Liste.',
      );
      expect(
        quelle.contains('standGelesen = true;'),
        isTrue,
        reason: 'Der Merker muss im Erfolgsfall auch wirklich gesetzt werden.',
      );
    });

    test('der Ausloeser in der Datenbank ist als Migration hinterlegt', () {
      final migrationen = Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .map((f) => f.readAsStringSync())
          .join('\n');

      expect(
        migrationen.contains('merge_profile_badges'),
        isTrue,
        reason:
            'Die zweite Haelfte der Zusage ist der Ausloeser, der alt und neu '
            'vereinigt. Steht er in keiner Migration, kann er beim naechsten '
            'Neuaufbau der Datenbank fehlen, ohne dass es jemand merkt.',
      );
      expect(
        migrationen.contains('preserve_profile_badges'),
        isTrue,
        reason: 'Auch die Ausloeser-Funktion selbst gehoert in eine Migration.',
      );
    });
  });
}
