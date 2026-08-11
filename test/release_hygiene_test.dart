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
}
