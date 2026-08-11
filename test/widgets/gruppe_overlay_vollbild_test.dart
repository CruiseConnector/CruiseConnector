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
    expect(find.text('Gruppen-Details'), findsOneWidget);
    expect(find.text('Gruppe einstellen'), findsNothing);
  });

  testWidgets('Karte im Vollbild und wieder zurueck', (tester) async {
    await tester.pumpWidget(seite());
    await tester.pump();

    // Wegdruecken
    await tester.tap(find.byTooltip('Karte im Vollbild'));
    await tester.pumpAndSettle();
    expect(find.text('Gruppe einstellen'), findsOneWidget);
    expect(find.text('Gruppen-Details'), findsNothing);

    // Zurueckholen
    await tester.tap(find.text('Gruppe einstellen'));
    await tester.pumpAndSettle();
    expect(find.text('Gruppen-Details'), findsOneWidget);
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

    expect(find.text('Gruppen-Details'), findsOneWidget);
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
}
