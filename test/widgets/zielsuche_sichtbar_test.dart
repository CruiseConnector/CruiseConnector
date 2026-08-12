import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-12 (vucko): „wenn man beim Gruppen- oder Single-Cruise-Mode das Ziel
/// suchen will, muss man immer speziell runter gehen, damit ich die Ergebnisse
/// sehen kann. Ich moechte, dass man beim Draufklicken direkt die perfekte
/// Ansicht hat, dass man zum Bestaetigen der Adresse direkt klicken kann und
/// nicht unterscrollen muss, ohne dass es kaputt geht."
///
/// WARUM DAS SO WEH TAT. Die Vorschlagsbox haengt unter dem Suchfeld. Sitzt das
/// Feld weit unten im Formular, liegt die Box hinter der Tastatur. Und
/// runterscrollen half nicht: Beide Suchfelder haben
/// `onTapOutside: unfocus()`, und TapRegion feuert das schon beim
/// FINGER-AUFSETZEN, nicht erst bei einem sauberen Tipp. Wer scrollen wollte,
/// verlor im selben Moment den Fokus, die Liste schloss sich. Man kam
/// praktisch nie an die Adresse.
///
/// DIE LOESUNG GEHT ANDERSHERUM: Nicht die Liste nach unten quetschen, sondern
/// das FELD nach oben holen, sobald es den Fokus bekommt. Darunter bleiben dann
/// ueber 300 Punkte bis zur Tastatur, die Box passt vollstaendig.
///
/// Beide Seiten benutzen dieselbe Karte (cruise_mode_page und
/// create_group_page), der Eingriff wirkt also an einer Stelle fuer beide.
void main() {
  late String karte;

  setUpAll(() {
    karte = File(
      'lib/presentation/widgets/cruise/cruise_setup_card.dart',
    ).readAsStringSync();
  });

  test('das Suchfeld wird beim Fokus nach oben geholt', () {
    expect(karte.contains('void _richteSuchfeldAus()'), isTrue);
    expect(karte.contains('Scrollable.ensureVisible('), isTrue);
    expect(
      karte.contains('_zielFeldSchluessel'),
      isTrue,
      reason: 'ohne Schluessel gibt es keinen Bezugspunkt zum Scrollen',
    );
  });

  test('die Karte bringt einen eigenen FocusNode mit', () {
    // Die Gruppenseite reicht keinen durch. Ohne eigenen Node wuerde die
    // Verbesserung dort gar nicht greifen - und genau die Gruppe hat der
    // Gruender ausdruecklich mitgenannt.
    expect(karte.contains('_eigenerZielFokus'), isTrue);
    expect(
      karte.contains(
        'FocusNode get _zielFokus => widget.destinationFocusNode ?? _eigenerZielFokus;',
      ),
      isTrue,
    );
  });

  test('nur der EIGENE FocusNode wird freigegeben', () {
    final start = karte.indexOf('void dispose()');
    expect(start, greaterThan(0));
    final rumpf = karte.substring(start, start + 600);
    expect(rumpf.contains('_eigenerZielFokus.dispose()'), isTrue);
    expect(
      rumpf.contains('widget.destinationFocusNode!.dispose()'),
      isFalse,
      reason:
          'der von aussen gereichte Node gehoert der Seite - ihn hier zu '
          'entsorgen wuerde die Cruise-Seite beim naechsten Tippen zerlegen',
    );
  });

  test('ausgerichtet wird erst, wenn die Tastatur steht', () {
    // Waehrend die Tastatur hochfaehrt, aendert sich die Fensterhoehe. Wer zu
    // frueh misst, scrollt an die falsche Stelle und es ruckelt zweimal. Eine
    // feste Wartezeit waere geraten - die Hoehe zu beobachten ist
    // selbstkorrigierend, auch beim Drehen und im geteilten Bildschirm.
    expect(karte.contains('void didChangeMetrics()'), isTrue);
    expect(karte.contains('_letzteTastaturhoehe'), isTrue);
  });

  test('die drei Abbruchbedingungen sind da', () {
    final start = karte.indexOf('void _richteSuchfeldAus()');
    final rumpf = karte.substring(start, start + 1000);

    expect(
      rumpf.contains('currentContext'),
      isTrue,
      reason:
          'das Feld kann zwischenzeitlich aus dem Baum gefallen sein - das '
          'Formular klappt ein oder die Karte wechselt in den '
          'Bestaetigungs-Zweig',
    );
    expect(
      rumpf.contains('isScrollingNotifier.value'),
      isTrue,
      reason:
          'in eine LAUFENDE Wischbewegung hineinzuscrollen fuehlt sich an, als '
          'wuerde einem das Bild aus der Hand gerissen',
    );
    expect(
      rumpf.contains('_zielFokus.hasFocus'),
      isTrue,
      reason: 'ohne Fokus gibt es nichts auszurichten',
    );
  });

  test('die Ausrichtung wird gerechnet, nicht geraten', () {
    final start = karte.indexOf('void _richteSuchfeldAus()');
    final rumpf = karte.substring(start, start + 1000);
    expect(
      rumpf.contains('MediaQuery.paddingOf(ctx).top'),
      isTrue,
      reason:
          'sonst landet das Feld hinter der Statusleiste statt knapp darunter',
    );
    expect(
      rumpf.contains('position.viewportDimension'),
      isTrue,
      reason:
          'die Inhaltshoehe ist auf beiden Seiten verschieden und aendert sich '
          'sogar innerhalb einer Seite - ein fester Pixelwert stimmt in der '
          'Haelfte der Faelle nicht',
    );
  });
}
