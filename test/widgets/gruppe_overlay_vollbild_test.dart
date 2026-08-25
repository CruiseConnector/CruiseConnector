import 'dart:io';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/presentation/pages/create_group_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-11 (vucko): „bei der Gruppenfunktion kann man nicht die
/// Einstellungen oder das ganze wegklicken wie bei der Single-Cruise-Mode-Page
/// ... im Idealfall, dass man das einfach wegdruecken kann und die Karte im
/// Vollscreen hat."
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget seite() => ChangeNotifierProvider(
    create: (_) => AppAccentProvider(),
    child: const MaterialApp(
      home: CreateGroupPage(disableMapTilesForTesting: true),
    ),
  );

  testWidgets('startet mit sichtbaren Einstellungen', (tester) async {
    await tester.pumpWidget(seite());
    await tester.pump();

    // Wichtig fuer den Erststart: Wer eine Gruppe anlegt, soll das Formular
    // sehen, nicht eine leere Karte.
    expect(find.text('Details zur Gruppe'), findsOneWidget);
    expect(find.text('Gruppe einstellen'), findsNothing);
  });

  testWidgets('Karte im Vollbild und wieder zurueck', (tester) async {
    await tester.pumpWidget(seite());
    await tester.pump();

    // Wegdruecken
    await tester.tap(find.byTooltip('Karte im Vollbild'));
    await tester.pumpAndSettle();
    expect(find.text('Gruppe einstellen'), findsOneWidget);
    expect(find.text('Details zur Gruppe'), findsNothing);

    // Zurueckholen
    await tester.tap(find.text('Gruppe einstellen'));
    await tester.pumpAndSettle();
    expect(find.text('Details zur Gruppe'), findsOneWidget);
    expect(find.text('Gruppe einstellen'), findsNothing);
  });

  testWidgets('der Kopf-Schalter holt die Einstellungen auch zurueck', (
    tester,
  ) async {
    await tester.pumpWidget(seite());
    await tester.pump();

    await tester.tap(find.byTooltip('Karte im Vollbild'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Einstellungen zeigen'));
    await tester.pumpAndSettle();

    expect(find.text('Details zur Gruppe'), findsOneWidget);
  });

  testWidgets('der Zurueck-Knopf bleibt in beiden Zustaenden erreichbar', (
    tester,
  ) async {
    await tester.pumpWidget(seite());
    await tester.pump();
    expect(find.byTooltip('Zurueck'), findsOneWidget);

    await tester.tap(find.byTooltip('Karte im Vollbild'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Zurueck'), findsOneWidget);
  });

  // Die wichtigste Regel des ganzen Umbaus. Wandert die Karte beim Umschalten
  // in einen anderen Teilbaum, wird sie neu gebaut — und _mapController zeigt
  // danach auf den alten, toten Controller. Es gibt keinen Absturz, aber
  // frische Routen werden stillschweigend nicht mehr eingerahmt. Genau so ein
  // Fehler faellt beim Testen nie auf, sondern erst beim Fahren.
  test('die Karte steht genau EINMAL im Baum', () {
    final quelle = File(
      'lib/presentation/pages/create_group_page.dart',
    ).readAsStringSync();
    final treffer = RegExp(r'_buildMap\(\)').allMatches(quelle).length;
    expect(
      treffer,
      2,
      reason:
          'erwartet: genau eine Definition und genau eine Verwendung '
          '(Positioned.fill). Mehr Verwendungen bedeuten, dass die Karte in '
          'zwei Teilbaeumen gebaut wird.',
    );
    expect(
      quelle.contains('Positioned.fill(child: RepaintBoundary(child: _buildMap()))'),
      isTrue,
      reason: 'die Karte muss ausserhalb des Umschalters liegen',
    );
  });

  // ── Verhalten nach Vuckos Rueckmeldung vom 2026-08-11 ────────────────────
  // „Es soll nicht transparent sein, es soll wie bei der Single-Cruise-Mode-
  // Page sein." Das Panel ist deshalb SOLIDE und deckt die Karte ab — und
  // Karten-Aktionen klappen es zuerst ein (Cruise-Muster: „Karte freigeben
  // fuer den Tap"). Diese Tests halten beide Regeln fest.

  testWidgets('Wegpunkte-Modus klappt das Panel ein (Karte frei zum Tippen)', (
    tester,
  ) async {
    await tester.pumpWidget(seite());
    await tester.pump();
    expect(find.text('Details zur Gruppe'), findsOneWidget);

    await tester.tap(find.text('Wegpunkte'));
    await tester.pumpAndSettle();

    // Panel weg, Vollbild-Leiste da — genau wie beim Cruisen.
    expect(find.text('Details zur Gruppe'), findsNothing);
    expect(find.text('Gruppe einstellen'), findsOneWidget);

    // Den Hinweis-Toast (2,6 s) auslaufen lassen, sonst meldet das
    // Test-Framework am Ende einen noch offenen Timer.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  test('das Panel ist solide und die Karten-Aktionen klappen ein', () {
    final quelle = File(
      'lib/presentation/pages/create_group_page.dart',
    ).readAsStringSync();

    // 1) Der Einstellungs-Sliver liegt auf einem soliden Grund — nichts
    //    scheint durch. (Vucko: „es soll nicht transparent sein.")
    final blatt = quelle.substring(
      quelle.indexOf('Widget _buildEinstellungsBlatt()'),
      quelle.indexOf('Widget _buildVollbildLeiste()'),
    );
    expect(
      blatt.contains('color: const Color(0xFF0B0E14)'),
      isTrue,
      reason: 'das Panel muss solide sein wie auf der Cruise-Seite',
    );

    // 2) „Standort waehlen" gibt die Karte frei.
    expect(
      RegExp(
        r"if \(value == 'Standort wählen'\) \{\s*_configEingeklappt = true;",
      ).hasMatch(quelle),
      isTrue,
      reason:
          'sonst fordert die App zum Kartentipp auf, waehrend das solide '
          'Panel die Karte verdeckt',
    );
  });

  // 2026-08-12 (vucko: „kann man den Wegpunkte-Modus nicht im Gruppenmodus gut
  // verwenden?"). Stopps SETZEN ging immer. Was fehlte: Ein angetippter Stopp
  // liess sich danach nicht mehr aendern — _replaceSelectedWaypoint und
  // _deleteSelectedWaypoint existierten, waren aber nie mit einem Knopf
  // verbunden. Erreichbar waren nur „Letzten loeschen" und „Alle loeschen".
  test('ein ausgewaehlter Stopp hat auch Aktionen', () {
    final quelle = File(
      'lib/presentation/pages/create_group_page.dart',
    ).readAsStringSync();

    final start = quelle.indexOf('Widget _buildWaypointActionOverlay()');
    expect(start, greaterThan(0));
    final leiste = quelle.substring(start, start + 2600);

    expect(
      leiste.contains('_replaceSelectedWaypoint'),
      isTrue,
      reason: 'sonst ist das Auswaehlen eines Stopps eine Sackgasse',
    );
    expect(leiste.contains('_deleteSelectedWaypoint'), isTrue);
    expect(
      leiste.contains('if (_selectedWaypointIndex != null)'),
      isTrue,
      reason: 'ohne Auswahl soll die Leiste nicht zuwachsen',
    );
  });
}
