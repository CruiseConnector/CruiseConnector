import 'dart:io';

import 'package:cruise_connect/core/app_changelog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Zwei Release-Fallen, in die dieses Projekt schon getappt ist. Beide kosten
/// nichts zu pruefen und sind teuer zu uebersehen, weil sie erst NACH dem
/// Hochladen in den Store auffallen.
void main() {
  String pubspecVersion() {
    final zeile = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((z) => z.startsWith('version:'));
    // „version: 1.5.13+95" → „1.5.13"
    return zeile.split(':')[1].trim().split('+')[0];
  }

  // Falle 1: Version hochgezaehlt, Changelog-Eintrag vergessen.
  //
  // ChangelogService.faelligerEintrag() findet dann keinen Eintrag, schreibt
  // den Gesehen-Stand still fort und zeigt NICHTS. Genau das ist am
  // 2026-08-11 passiert: Vucko hat das Update installiert und kein Popup
  // gesehen. Der Fehler ist von aussen unsichtbar — es passiert einfach nichts.
  test('zur pubspec-Version gibt es einen Changelog-Eintrag', () {
    final version = pubspecVersion();
    expect(
      AppChangelog.fuerVersion(version),
      isNotNull,
      reason:
          'pubspec steht auf $version, aber app_changelog.dart kennt diese '
          'Version nicht. Ohne Eintrag erscheint nach dem Update kein Hinweis '
          '— und zwar ohne jede Fehlermeldung.',
    );
  });

  test('der neueste Changelog-Eintrag ist der zur laufenden Version', () {
    expect(
      AppChangelog.eintraege.first.version,
      pubspecVersion(),
      reason: 'die Liste ist „neueste zuerst" — sonst stimmt die Reihenfolge',
    );
  });

  // Falle 2: Das Zwangs-Update-Tor haengt nicht mehr im Baum.
  //
  // Der Schalter dafuer liegt in der Datenbank (app_min_version). Waere das
  // Tor aus main.dart verschwunden, wuerde das Hochsetzen dort einfach nichts
  // bewirken — und niemand wuerde es merken, bis eine kaputte Version
  // draussen bleibt.
  test('das Zwangs-Update-Tor haengt in main.dart', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(
      main.contains('ForceUpdateGate('),
      isTrue,
      reason:
          'ohne das Tor hat app_min_version.min_build_number keine Wirkung',
    );
  });

  // Falle 3: Der Auslöser haengt nur am Antippen des Home-Tabs.
  //
  // Bis zum 2026-08-12 war das so — und deshalb erschien weder das
  // Update-Blatt noch die Sterne-Frage jemals beim App-Start: Man steht nach
  // dem Oeffnen bereits auf Home und tippt Home nie an. Man musste erst auf
  // einen anderen Reiter wechseln und zurueckkommen. Genau der Moment, in dem
  // beides erscheinen soll, war der einzige, in dem es ausblieb.
  test('Update-Blatt und Sterne-Frage werden auch beim App-Start geprueft', () {
    final quelle = File('lib/presentation/pages/home_page.dart')
        .readAsStringSync();

    final aufrufe = RegExp(
      r'_pruefeBewertungsPopup\(\)',
    ).allMatches(quelle).length;
    expect(
      aufrufe,
      greaterThanOrEqualTo(3),
      reason:
          'erwartet: die Definition, der Aufruf aus _onNavItemTapped UND der '
          'Aufruf aus dem Post-Frame-Block in initState',
    );

    // Der Start-Aufruf muss in initState stehen, nicht irgendwo.
    final start = quelle.indexOf('void initState()');
    expect(start, greaterThan(0));
    final ende = quelle.indexOf('void _onTutorialReplayRequested');
    expect(ende, greaterThan(start));
    expect(
      quelle.substring(start, ende).contains('_pruefeBewertungsPopup()'),
      isTrue,
      reason: 'ohne den Aufruf beim Start sieht niemand das Update-Blatt',
    );
  });
}
