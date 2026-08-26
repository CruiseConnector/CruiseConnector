import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-26 (vucko, Aufgabe 6): „Ich habe auf Route fahren geklickt, die
/// Route hat nicht funktioniert. Ich hab nochmal draufgeklickt, dann hat es
/// funktioniert."
///
/// An `CruiseModePage.pendingRoute` haengen ZWEI Zuhoerer:
///  * `home_page.dart` schaltet auf den Fahr-Reiter, aber NUR wenn
///    `pendingRoute.value != null` ist,
///  * `cruise_mode_page.dart` uebernimmt die Route und LEERT den Wert dabei.
///
/// Kommt die Fahransicht zuerst dran, sieht die Startseite null und schaltet
/// nicht um: die Route laedt im unsichtbaren Reiter, fuer den Fahrer passiert
/// scheinbar nichts. Welcher zuerst drankommt, haengt an der Reihenfolge der
/// Anmeldung und damit daran, ob der Fahr-Reiter schon offen war — daher das
/// Muster „einmal nichts, beim zweiten Mal geht es".
void main() {
  String lies(String pfad) => File(pfad).readAsStringSync();

  test('die Fahransicht fordert den Reiterwechsel selbst an', () {
    final quelle = lies('lib/presentation/pages/cruise_mode_page.dart');
    final start = quelle.indexOf('void _consumePendingRouteIfAvailable()');
    expect(start, greaterThan(-1), reason: 'Verbrauchsmethode nicht gefunden');
    final block = quelle.substring(start, start + 2200);

    // Beides muss im selben Block stehen: leeren UND den Wechsel anfordern.
    expect(
      block.contains('CruiseModePage.pendingRoute.value = null'),
      isTrue,
      reason: 'die Route wird hier verbraucht',
    );
    expect(
      block.contains('CruiseModePage.openCruiseTab.value'),
      isTrue,
      reason:
          'Der Reiterwechsel darf NICHT davon abhaengen, wer schneller war. '
          'Wer die Route verbraucht, fordert den Wechsel selbst an.',
    );
  });

  test('die Startseite hoert weiterhin auf beide Wege', () {
    final quelle = lies('lib/presentation/pages/home_page.dart');
    expect(
      quelle.contains('CruiseModePage.openCruiseTab.addListener'),
      isTrue,
      reason: 'ohne diesen Zuhoerer kommt der Wechsel nicht an',
    );
    expect(
      quelle.contains('CruiseModePage.pendingRoute.addListener'),
      isTrue,
      reason: 'der alte Weg bleibt fuer den Fall, dass die Fahransicht '
          'noch gar nicht gebaut wurde',
    );
  });

  test('der Wechsel-Zuhoerer der Startseite prueft keinen Wert mehr', () {
    // _onOpenCruiseTab muss bedingungslos umschalten, sonst waere die
    // Absicherung wirkungslos.
    final quelle = lies('lib/presentation/pages/home_page.dart');
    final start = quelle.indexOf('void _onOpenCruiseTab()');
    expect(start, greaterThan(-1));
    final block = quelle.substring(start, start + 320);
    expect(block.contains('_selectedIndex = 2'), isTrue);
    expect(
      block.contains('pendingRoute.value != null'),
      isFalse,
      reason: 'dieser Weg darf nicht wieder an den Wert gekoppelt werden',
    );
  });
}
