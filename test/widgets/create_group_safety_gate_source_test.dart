import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schützt das Sicherheits-Gate bei der Gruppenerstellung.
///
/// 2026-08-11: Ein Audit hat gezeigt, dass das ECHTE Gate in `_createGroup`
/// steht (`showGroupSafetyNoticeSheet` direkt vor jedem Schreibvorgang) und von
/// KEINEM Test gedeckt war. Der Aufruf in `initState` ist nur ein Info-Popup —
/// `unawaited`, ohne Auswertung. Wer den Aufruf in `_createGroup` entfernt,
/// verschiebt oder hinter die Validierung zieht, bekommt eine gruene Test-Suite
/// UND Gruppen ohne Sicherheitshinweis. Genau das faengt dieser Test ab.
///
/// Bewusst ein QUELLTEXT-Test statt eines Widget-Tests: Das Gate haengt an
/// einem modalen Sheet mit Scroll-Zwang und am abgeschlossenen App-Tutorial —
/// ein Widget-Test muesste so viel nachbauen, dass er am Ende die Nachbildung
/// prueft statt der echten Reihenfolge. Diese Pruefung liest die Reihenfolge
/// direkt dort ab, wo sie zaehlt.
void main() {
  final datei = File('lib/presentation/pages/create_group_page.dart');

  late String createGroupRumpf;

  setUpAll(() {
    expect(datei.existsSync(), isTrue, reason: 'Seite nicht gefunden');
    final quelle = datei.readAsStringSync();

    final start = quelle.indexOf('Future<void> _createGroup() async {');
    expect(
      start,
      greaterThan(-1),
      reason: 'Methode _createGroup wurde umbenannt — dieser Schutz muss mit.',
    );

    // Bis zum ersten echten Schreibvorgang lesen: alles davor ist die
    // Torwaechter-Zone.
    final schreibvorgang = quelle.indexOf('CruiseGroupService.create(', start);
    expect(
      schreibvorgang,
      greaterThan(-1),
      reason: 'Schreibpfad umbenannt — dieser Schutz muss mit.',
    );
    createGroupRumpf = quelle.substring(start, schreibvorgang);
  });

  group('Sicherheits-Gate bei der Gruppenerstellung', () {
    test('der Sicherheitshinweis kommt VOR dem Schreiben in die Datenbank', () {
      expect(
        createGroupRumpf.contains('showGroupSafetyNoticeSheet'),
        isTrue,
        reason:
            'Zwischen dem Start von _createGroup und CruiseGroupService.create '
            'muss der Sicherheitshinweis stehen. Fehlt er, entstehen Gruppen '
            'ohne Hinweis.',
      );
    });

    test('das Ergebnis wird abgewartet und ausgewertet', () {
      // `unawaited(...)` oder ein ignoriertes Ergebnis waere ein stilles Leck:
      // Das Sheet ginge auf, die Gruppe entstuende trotzdem.
      expect(
        createGroupRumpf.contains('await showGroupSafetyNoticeSheet'),
        isTrue,
        reason: 'Der Hinweis muss abgewartet werden (await).',
      );
      // 2026-08-18 (Defekt 3): Der Abbruch war frueher ein nacktes
      // `if (!acceptedSafety) return;` — fail-closed, aber stumm. Genau das
      // war das Problem: Knopf gedrueckt, nichts passiert, keine Meldung.
      // Jetzt steht eine Erklaerung davor. Beide Formen gelten als
      // fail-closed, der Abbruch selbst ist weiterhin Pflicht.
      expect(
        RegExp(
          r'if\s*\(\s*!\s*\w+\s*\)\s*(return|\{[^}]*return\s*;\s*\})',
          multiLine: true,
        ).hasMatch(createGroupRumpf),
        isTrue,
        reason:
            'Auf ein abgelehntes/weggewischtes Sheet muss ein Abbruch folgen '
            '(fail-closed).',
      );
    });

    test('kein Weg schaltet das Gate dauerhaft ab', () {
      // markGroupSafetyAccepted ist ein Einweg-Schalter: einmal gesetzt, fragt
      // die App diesen Nutzer NIE wieder. Er darf ausschliesslich im Sheet
      // selbst gesetzt werden, wenn jemand bewusst zustimmt — niemals aus der
      // Seite heraus (etwa beim Wegdruecken eines Overlays).
      final quelle = datei.readAsStringSync();
      expect(
        quelle.contains('markGroupSafetyAccepted'),
        isFalse,
        reason:
            'Die Seite darf den Einweg-Schalter nicht selbst setzen — sonst ist '
            'der Sicherheitshinweis fuer diesen Nutzer dauerhaft aus.',
      );
    });
  });
}
