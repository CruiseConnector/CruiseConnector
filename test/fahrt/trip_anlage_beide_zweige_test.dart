import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-18 (Defekt 2 aus dem Produktionsbericht):
/// „Zwei Tabellen fuer dieselbe Fahrt." Gemessen: 12 Zeilen in `trips` von
/// 2 Personen, 116 Zeilen in `user_drive_sessions`. Ursache der Luecke: Der
/// A→B-Zweig legte einen Trip an, wenn der Trip-Modus aktiv war ODER eine
/// Gruppe fuhr — der Rundkurs-Zweig nur bei einer Gruppe. Wer den Trip-Modus
/// fuer einen Rundkurs einschaltete, bekam keine Home-Card und kein Resume.
void main() {
  test('Rundkurs und A→B legen einen Trip unter derselben Bedingung an', () {
    final quelle = File(
      'lib/presentation/pages/cruise_mode_page.dart',
    ).readAsStringSync();

    final treffer = RegExp(
      r'if \(\(_tripModeEnabled \|\| widget\.groupId != null\) &&\s*'
      r'result\.distanceMeters != null &&\s*'
      r'result\.distanceMeters! > 0\) \{\s*'
      r'unawaited\(\s*_createTripInDb\(',
      multiLine: true,
    ).allMatches(quelle).length;

    expect(
      treffer,
      2,
      reason:
          'Erwartet: beide Zweige (Rundkurs und A→B) stellen dieselbe Frage. '
          'Gefunden: $treffer. Laufen sie auseinander, verliert einer der '
          'beiden Modi Home-Card und Resume nach App-Kill.',
    );
  });

  test('CLAUDE.md benennt user_drive_sessions als fuehrende Tabelle', () {
    final md = File('CLAUDE.md').readAsStringSync();
    expect(md.contains('`user_drive_sessions` ist FUEHREND'), isTrue);
    expect(md.contains('`trips` ist die Planungs- und Gruppentabelle'), isTrue);
  });
}
