import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-12 (vucko): „schau, dass die Quicklinks zuverlaessiger auf der Home
/// Page sind, die sind noch nicht gut genug. Dass es leichter ist, wenn man
/// draufdrueckt, weitergeleitet wird und es viel besser funktioniert und man
/// mehr Flaeche zum Druecken hat — aber nicht zu viel, dass man ausversehen
/// draufdruecken kann."
///
/// DIE URSACHE war kein Fehler in der Weiterleitung, sondern die Groesse des
/// Ziels: Der Sprung in die Community hing an einem NACKTEN Pfeilsymbol mit
/// 14 Punkten Kantenlaenge. Das ist weniger als ein Drittel der empfohlenen
/// 48 Punkte. Man musste zielen, und daneben passierte einfach nichts — was
/// sich anfuehlt, als waere die Weiterleitung kaputt.
///
/// Die Weiterleitung selbst war in Ordnung: pendingTabFocus wird VOR dem
/// Tab-Wechsel gesetzt, CommunityPage hoert per Listener UND per
/// PostFrameCallback, und der Wert wird nach dem Verarbeiten auf null
/// zurueckgesetzt, damit auch zweimal derselbe Reiter hintereinander feuert.
void main() {
  late String karte;
  late String home;

  setUpAll(() {
    karte = File(
      'lib/presentation/widgets/community_carousel_card.dart',
    ).readAsStringSync();
    home = File(
      'lib/presentation/pages/home_content_page.dart',
    ).readAsStringSync();
  });

  test('die ganze Kopfzeile ist der Trefferbereich, mit 44 Punkten Hoehe', () {
    final start = karte.indexOf('if (widget.showHeader)');
    expect(start, greaterThan(0));
    final kopf = karte.substring(start, start + 2600);

    expect(
      kopf.contains('BoxConstraints(minHeight: 44)'),
      isTrue,
      reason:
          '14 Punkte waren das Problem. Unter 44 trifft man nur mit Zielen.',
    );
    expect(kopf.contains('onTap: widget.onOpenCommunity'), isTrue);
    expect(
      kopf.contains('HitTestBehavior.opaque'),
      isTrue,
      reason: 'sonst zaehlen nur die bemalten Punkte, nicht die Luecken',
    );
  });

  test('der Pfeil ist nur noch Hinweis, nicht mehr das Ziel', () {
    final start = karte.indexOf('if (widget.showHeader)');
    final kopf = karte.substring(start, start + 2600);
    // Der GestureDetector muss den GANZEN Zeileninhalt umschliessen, nicht nur
    // das Symbol. Pruefbar an der Reihenfolge: Antippen kommt vor dem Titel.
    final tap = kopf.indexOf('onTap: widget.onOpenCommunity');
    final titel = kopf.indexOf('_title,');
    final pfeil = kopf.indexOf('Icons.arrow_forward_ios');
    expect(tap, greaterThan(0));
    expect(
      tap,
      lessThan(titel),
      reason: 'der Titel muss INNERHALB des Trefferbereichs liegen',
    );
    expect(tap, lessThan(pfeil));
  });

  test('NICHT die ganze Kachel ist antippbar', () {
    // Darunter liegen Profilbilder, Folgen-Knoepfe und das Wegklicken. Waere
    // alles ein Bereich, wuerde jeder Fehlgriff die Community oeffnen — genau
    // das „ausversehen draufdruecken", das vucko ausschliesst.
    final start = karte.indexOf('Widget build(');
    final rumpf = karte.substring(start);
    final treffer = RegExp(
      r'onTap: widget\.onOpenCommunity',
    ).allMatches(rumpf).length;
    expect(
      treffer,
      1,
      reason:
          'genau EIN Trefferbereich je Kachel: die Kopfzeile. Mehr bedeutet, '
          'dass auch Inhalte darunter weiterleiten.',
    );
  });

  test('jeder Quicklink zeigt auf seinen eigenen Reiter', () {
    expect(
      home.contains('_oeffneCommunity(CommunityPage.tabEntdecken)'),
      isTrue,
      reason: 'vucko: „wenn ich auf Kontakte klicke, moechte ich auf das '
          'Community-Entdecken-Feld kommen"',
    );
    expect(home.contains('_oeffneCommunity(CommunityPage.tabGruppen)'), isTrue);
  });

  test('der Reiter wird VOR dem Wechsel gesetzt', () {
    final start = home.indexOf('void _oeffneCommunity(');
    expect(start, greaterThan(0));
    final rumpf = home.substring(start, start + 700);
    final setzen = rumpf.indexOf('pendingTabFocus.value');
    final wechsel = rumpf.indexOf('onTabChange');
    expect(setzen, greaterThan(0));
    expect(
      setzen,
      lessThan(wechsel),
      reason:
          'umgekehrt waere die Community schon gebaut, bevor sie weiss, wohin',
    );
  });
}
