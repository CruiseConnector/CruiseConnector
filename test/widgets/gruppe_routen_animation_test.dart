import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-11 (vucko): „man bekommt keine Animation, wie die Strecke verlaeuft
/// auf der Karte."
///
/// Die Route wird jetzt auf der Gruppenkarte gezeichnet — nach demselben
/// Verfahren wie in der Single-Cruise-Seite. Der gefaehrliche Teil daran ist
/// NICHT die Animation selbst, sondern ihr Abbruch: Laeuft ein Timer weiter,
/// waehrend die Route geleert oder die Seite verlassen wird, schreibt der
/// naechste Tick die geloeschte Route zurueck (oder ruft setState auf einem
/// toten Widget). Diese Pruefung liest die Regel direkt in der Quelle nach.
void main() {
  final datei = File('lib/presentation/pages/create_group_page.dart');
  late List<String> zeilen;

  setUpAll(() {
    expect(datei.existsSync(), isTrue);
    zeilen = datei.readAsLinesSync();
  });

  test('vor JEDEM Leeren der Route wird die Zeichnung abgebrochen', () {
    final verstoesse = <int>[];
    for (var i = 0; i < zeilen.length; i++) {
      if (zeilen[i].trim() != '_routeLatLngs = [];') continue;
      // Die Zeile davor muss der Abbruch sein.
      final davor = i > 0 ? zeilen[i - 1].trim() : '';
      if (davor != '_brichRoutenZeichnungAb();') verstoesse.add(i + 1);
    }
    expect(
      verstoesse,
      isEmpty,
      reason:
          'Zeilen ohne vorangehendes _brichRoutenZeichnungAb(): $verstoesse — '
          'ein laufender Tick wuerde die geloeschte Route zurueckschreiben.',
    );
  });

  test('dispose bricht eine laufende Zeichnung ab', () {
    final quelle = zeilen.join('\n');
    final start = quelle.indexOf('void dispose() {');
    expect(start, greaterThan(-1));
    final rumpf = quelle.substring(start, start + 500);
    expect(
      rumpf.contains('_brichRoutenZeichnungAb()'),
      isTrue,
      reason: 'sonst ruft ein Tick setState auf einem abgebauten Widget',
    );
  });

  test('Bedienungshilfen schalten die Animation ab', () {
    final quelle = zeilen.join('\n');
    expect(
      quelle.contains('disableAnimations'),
      isTrue,
      reason: 'wer Animationen abgeschaltet hat, bekommt die Route sofort',
    );
    expect(
      quelle.contains('accessibleNavigation'),
      isTrue,
      reason: 'mit Screenreader darf nichts kriechen',
    );
  });

  test('der Abbruch-Zaehler wird beim Abbrechen erhoeht', () {
    final quelle = zeilen.join('\n');
    final start = quelle.indexOf('void _brichRoutenZeichnungAb() {');
    expect(start, greaterThan(-1));
    final rumpf = quelle.substring(start, quelle.indexOf('}', start));
    expect(
      rumpf.contains('_routeZeichenToken++'),
      isTrue,
      reason:
          'nur der erhoehte Zaehler laesst laufende Ticks erkennen, dass sie '
          'veraltet sind',
    );
    expect(rumpf.contains('_routeZeichenTimer?.cancel()'), isTrue);
  });
}
