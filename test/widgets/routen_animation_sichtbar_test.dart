import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-12 (vucko): „Bei der Single-Cruise-Mode-Page kommt nach dem Suchen
/// einer Route keine Animation. Bei der Gruppenseite passt es schon."
///
/// DER FEHLER WAR NICHT DIE ANIMATION. Sie lief die ganze Zeit — nur auf einer
/// Linie, die in diesem Moment gar nicht gezeigt wurde.
///
/// Nach der Suche schaltet die Fahransicht in die UEBERSICHT. In diesem Zweig
/// griff die Linienwahl auf `_fullRouteBackgroundLatLngs` zurueck: die VOLLE,
/// statische Route. Die wachsende Linie (`_routeLatLngs`) war damit unsichtbar,
/// und man sah die fertige Strecke sofort — genau der gemeldete Eindruck
/// „keine Animation".
///
/// Auf der Gruppenseite gibt es diesen Uebersichts-Zweig nicht, dort wird immer
/// `_routeLatLngs` gezeichnet. Deshalb war es dort von Anfang an richtig.
void main() {
  late String cruise;
  late String gruppe;

  setUpAll(() {
    cruise = File(
      'lib/presentation/pages/cruise_mode_page.dart',
    ).readAsStringSync();
    gruppe = File(
      'lib/presentation/pages/create_group_page.dart',
    ).readAsStringSync();
  });

  group('Fahransicht: die wachsende Linie gewinnt waehrend des Zeichnens', () {
    test('es gibt einen Vorrang fuer die laufende Animation', () {
      expect(
        cruise.contains('final zeichnetGerade ='),
        isTrue,
        reason:
            'ohne diesen Vorrang zeigt die Uebersicht weiter die volle Route '
            'und die Animation bleibt unsichtbar',
      );
      expect(
        cruise.contains('_routeDrawAnimationTimer?.isActive == true'),
        isTrue,
      );
    });

    test('der Vorrang gilt NUR in der Vorschau', () {
      final start = cruise.indexOf('final zeichnetGerade =');
      final rumpf = cruise.substring(start, start + 200);
      expect(
        rumpf.contains('!_isRouteConfirmed'),
        isTrue,
        reason:
            'waehrend der Navigation muss die Linienwahl unveraendert bleiben: '
            'dort haengt sie am Puck-Fenster und am Trimmen',
      );
    });

    test('der Vorrang steht VOR dem Uebersichts-Zweig', () {
      final start = cruise.indexOf('final activePts = hideLineForReroute');
      expect(start, greaterThan(0));
      final rumpf = cruise.substring(start, start + 700);
      final vorrang = rumpf.indexOf('zeichnetGerade');
      final uebersicht = rumpf.indexOf('!_isOverviewActive');
      expect(vorrang, greaterThan(0));
      expect(
        vorrang,
        lessThan(uebersicht),
        reason: 'sonst greift wieder der alte Zweig zuerst',
      );
    });

    test('das Reroute-Verhalten bleibt unangetastet', () {
      // Beim Reroute soll bewusst die alte volle Route stehen bleiben, wie bei
      // Google und Apple. Das darf der neue Zweig nicht ueberholen.
      final start = cruise.indexOf('final activePts = hideLineForReroute');
      final rumpf = cruise.substring(start, start + 700);
      expect(
        rumpf.indexOf('hideLineForReroute'),
        lessThan(rumpf.indexOf('zeichnetGerade')),
        reason: 'der Reroute-Zweig muss der erste bleiben',
      );
    });
  });

  test('die Gruppenseite hatte den Fehler nie', () {
    // Dort wird immer die wachsende Liste gezeichnet, ohne Uebersichts-Zweig.
    expect(gruppe.contains('_starteRoutenZeichnung('), isTrue);
    expect(gruppe.contains('_brichRoutenZeichnungAb()'), isTrue);
  });

  group('Gruppenseite: die Knopfleiste im Formular', () {
    test('kein Verlauf und kein doppelter Rand, wenn eingebettet', () {
      final start = gruppe.indexOf('Widget _buildBottomBar(');
      expect(start, greaterThan(0));
      final rumpf = gruppe.substring(start, start + 1800);

      // Der schwarze Verlauf ergibt ueber der Karte Sinn, im soliden Panel
      // sah er wie ein Schmutzrand aus.
      expect(rumpf.contains('decoration: schwebend'), isTrue);
      // Das Panel hat bereits 20 Punkte Seitenrand. Noch einmal 20 liess die
      // Knoepfe schmaler und nach innen versetzt wirken als alles darueber -
      // genau Vuckos „nicht zentriert".
      expect(
        rumpf.contains('padding: schwebend'),
        isTrue,
        reason: 'eingebettet darf kein zweiter Rand dazukommen',
      );
      expect(rumpf.contains('EdgeInsets.zero'), isTrue);
    });

    test('die ueberfluessige Verschachtelung ist weg', () {
      final start = gruppe.indexOf('Widget _buildBottomBar(');
      final rumpf = gruppe.substring(start, start + 1800);
      // Vorher: Column(mainAxisSize.min, children: [Row(...)]) - eine Spalte
      // mit genau einem Kind, die nur Platz kostete.
      expect(
        rumpf.contains('child: Row('),
        isTrue,
        reason: 'die Zeile haengt jetzt direkt am Container',
      );
    });
  });
}
