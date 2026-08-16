import 'dart:io';

import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';
import 'package:cruise_connect/data/services/tutorial_ziel_registry.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';
import 'package:cruise_connect/presentation/widgets/starter_paket_karte.dart';
import 'package:cruise_connect/presentation/widgets/ziel_hinweis_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-16 (vucko Testfahrt, Aufgabe 5, Teil 2): „Wenn sie bei der
/// Willkommensaufgabe auf die Aufgaben klicken, sollen sie direkt
/// weitergeleitet werden und es wird ihnen gehighlightet, was sie noch machen
/// muessen — man zeigt ihnen: so geht das. Und bei der Cruise-Mode-Seite soll
/// das Overlay Schritt fuer Schritt erklaeren, welcher Modus was ist."
void main() {
  group('ZielHinweisOverlay', () {
    testWidgets('misst das echte Ziel, zeigt Sprechblase, Weiter/Verstanden', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: 100,
                  left: 40,
                  child: SizedBox(
                    key: TutorialZielRegistry.key(TutorialZielRegistry.cruiseSuchknopf),
                    width: 120,
                    height: 50,
                  ),
                ),
                const ZielHinweisOverlay(
                  messenBis: Duration(milliseconds: 300),
                  schritte: [
                    HinweisSchritt(
                      ziel: TutorialZielRegistry.cruiseSuchknopf,
                      titel: 'Suchen',
                      text: 'Hier tippen.',
                    ),
                    HinweisSchritt(titel: 'Fertig', text: 'Das war es.'),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Suchen'), findsOneWidget);
      expect(find.text('Hier tippen.'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
      // Ziel gemessen: Sprechblase liegt UNTER dem Ziel (Ziel in der oberen
      // Haelfte), also tiefer als y=150.
      final blase = tester.getTopLeft(find.byKey(const ValueKey('hinweis_blase')));
      expect(blase.dy, greaterThan(150));

      await tester.tap(find.byKey(const ValueKey('hinweis_weiter')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Fertig'), findsOneWidget);
      expect(find.text('Verstanden'), findsOneWidget);
    });

    testWidgets('fehlt das Ziel, kommt die Blase mittig nach dem Zeitlimit', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ZielHinweisOverlay(
              messenBis: Duration(milliseconds: 200),
              schritte: [
                HinweisSchritt(ziel: 'gibt_es_nicht', titel: 'T', text: 'X'),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('T'), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('T'), findsOneWidget);
    });
  });

  group('Starter-Karte fuehrt hin', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      StarterAufgabenService.instance.resetForTests();
      CruiseModePage.hinweisWunsch.value = null;
    });

    testWidgets('„Eine Route suchen" antippen → Cruise-Tab + Wunsch „route"', (
      tester,
    ) async {
      var tab = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StarterPaketKarte(onTabChange: (i) => tab = i),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Zeigen'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('starter_aufgabe_route')));
      await tester.pump();
      expect(tab, 2);
      expect(CruiseModePage.hinweisWunsch.value, 'route');
    });

    testWidgets('„Eine Adresse merken" → Cruise-Tab + Wunsch „favorit"', (
      tester,
    ) async {
      var tab = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StarterPaketKarte(onTabChange: (i) => tab = i),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('starter_aufgabe_favorit')));
      await tester.pump();
      expect(tab, 2);
      expect(CruiseModePage.hinweisWunsch.value, 'favorit');
    });

    testWidgets('erledigte Aufgabe ist nicht mehr antippbar', (tester) async {
      await StarterAufgabenService.instance.load();
      await StarterAufgabenService.instance.markiere('route');
      var tab = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StarterPaketKarte(onTabChange: (i) => tab = i),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('starter_aufgabe_route')));
      await tester.pump();
      expect(tab, -1);
      expect(CruiseModePage.hinweisWunsch.value, isNull);
    });
  });

  group('Verdrahtung', () {
    late String cm;
    late String setup;
    setUpAll(() {
      cm = File('lib/presentation/pages/cruise_mode_page.dart').readAsStringSync();
      setup = File('lib/presentation/widgets/cruise/cruise_setup_card.dart').readAsStringSync();
    });

    test('Setup-Karte traegt Keys fuer jeden erklaerten Schritt + Fragezeichen', () {
      for (final z in [
        'cruiseModusRundkurs',
        'cruiseModusAtoB',
        'cruiseLaenge',
        'cruiseUmweg',
        'cruiseAutobahn',
        'cruiseStil',
        'zielsuche',
        'cruiseSetupHilfe',
      ]) {
        expect(setup.contains('TutorialZielRegistry.$z'), isTrue, reason: z);
      }
      expect(setup.contains('onTap: widget.onHilfe'), isTrue);
      expect(cm.contains('TutorialZielRegistry.cruiseSuchknopf'), isTrue);
    });

    test('Cruise-Seite: Starter-Wunsch → Fuehrung; Setup-Fuehrung Schritt fuer Schritt', () {
      expect(cm.contains('CruiseModePage.hinweisWunsch.addListener(_onHinweisWunsch)'), isTrue);
      expect(cm.contains('onHilfe: _zeigeSetupFuehrung'), isTrue);
      final i = cm.indexOf('Future<void> _zeigeSetupFuehrung()');
      final rumpf = cm.substring(i, i + 5000);
      // Reihenfolge der Erklaerung: Rundkurs → Laenge → A nach B → Ziel →
      // Umweg → Autobahn → Stil → Suchen.
      final reihenfolge = [
        "titel: 'Rundkurs'",
        "titel: 'Länge'",
        "titel: 'A nach B'",
        "titel: 'Ziel'",
        "titel: 'Umweg'",
        "titel: 'Autobahn an oder aus'",
        "titel: 'Stil'",
        "titel: 'Suchen'",
      ];
      var pos = 0;
      for (final t in reihenfolge) {
        final p = rumpf.indexOf(t, pos);
        expect(p, greaterThan(0), reason: t);
        pos = p;
      }
      // Erstes Aufklappen nach dem Tutorial: einmal automatisch.
      expect(cm.contains('_setupFuehrungBeimErstenMal()'), isTrue);
      expect(cm.contains("'cruise_setup_fuehrung_v1_gesehen'"), isTrue);
    });

    test('Route speichern zaehlt auch ueber die Empfehlung/den Feed', () {
      final saved = File('lib/data/services/saved_routes_service.dart').readAsStringSync();
      final i = saved.indexOf('static Future<void> saveExistingRoute(');
      expect(saved.substring(i, i + 500).contains("markiere('speichern')"), isTrue);
      final home = File('lib/presentation/pages/home_content_page.dart').readAsStringSync();
      expect(home.contains('TutorialZielRegistry.homeRouteSpeichern'), isTrue);
      expect(home.contains('StarterPaketKarte(onTabChange: widget.onTabChange)'), isTrue);
    });
  });
}
