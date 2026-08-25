import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/presentation/pages/analytics_page.dart';
import 'package:cruise_connect/presentation/widgets/badge_uebersicht_panel.dart';

/// 2026-08-24 (vucko woertlich): „die stufen badges sollen noch besser
/// angezeigt werden man scrollt da endlos".
///
/// Der lange Teil der Seite war nicht das Uebersichts-Panel, sondern der
/// Katalog darunter: achtzehn Familien-Bloecke mit ALLEN Kacheln
/// untereinander. Dieser Test haelt fest, was der Umbau leisten muss:
///   - Die Hoehe haengt nicht mehr an der Groesse des Katalogs.
///   - Es geht nichts verloren: jedes Abzeichen bleibt erreichbar.
///   - Es wird nicht leer: eine Schublade steht immer offen.
///   - Es doppelt sich nicht mit der Uebersicht darueber.
void main() {
  /// Ein uebliches Telefon (iPhone 13/14 sind 390 Punkte breit). Der Katalog
  /// bekommt hier die Breite, die er auf der Seite auch hat.
  const breite = 390.0;

  /// Kacheln in Originalgroesse, aber ohne Bilder — der Test misst die Hoehe,
  /// nicht die Grafik. Breite und Hoehe kommen seit dem 25.08. von aussen
  /// ([BadgeKachelMasse]), damit Rechnung und Zeichnung nicht auseinander
  /// laufen koennen.
  Widget kachel(app.Badge badge, BadgeKachelMasse masse) => Center(
    child: Text(badge.id, maxLines: 1, overflow: TextOverflow.ellipsis),
  );

  Future<double> baueUndMiss(
    WidgetTester tester, {
    required Set<String> erreichteIds,
    Map<app.BadgeMetrik, double>? metriken,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0B0E14),
          body: SingleChildScrollView(
            child: SizedBox(
              width: breite,
              child: BadgeKatalogListe(
                erreichteIds: erreichteIds,
                metriken: metriken,
                kachelBauer: kachel,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getSize(find.byType(BadgeKatalogListe)).height;
  }

  group('Der Katalog scrollt nicht mehr endlos', () {
    testWidgets('zugeklappt ist er ein Bruchteil von komplett offen', (
      tester,
    ) async {
      final zugeklappt = await baueUndMiss(tester, erreichteIds: const {});

      // „Alle aufklappen" stellt genau den Zustand her, den die Seite vorher
      // IMMER hatte: jeder Block mit allen Kacheln. Das ist die Messlatte.
      await tester.tap(find.text('Alle aufklappen'));
      await tester.pumpAndSettle();
      final offen = tester.getSize(find.byType(BadgeKatalogListe)).height;

      // ignore: avoid_print
      print(
        'Katalog bei $breite Punkten Breite: '
        '${app.Badge.all.length} Kacheln in '
        '${BadgeKatalogListe.schubladen().length} Schubladen — '
        'komplett offen ${offen.round()} Punkte, '
        'im Auslieferungszustand ${zugeklappt.round()} Punkte.',
      );

      // Ein Telefon zeigt rund 700 Punkte auf einmal. Vorher waren es
      // mehrere volle Bildschirme allein unterhalb der Uebersicht.
      expect(
        offen,
        greaterThan(4000),
        reason:
            'Messlatte stimmt nicht mehr: der volle Katalog war die Ursache '
            'des endlosen Scrollens',
      );
      expect(
        zugeklappt,
        lessThan(offen / 3),
        reason: 'Der Auslieferungszustand ist kaum kuerzer als vorher',
      );
      // Die Schranke waechst mit der Zahl der FAMILIEN, nicht mit der Zahl
      // der Abzeichen: eine Kopfzeile je Familie (rund 60 Punkte) plus die
      // eine Schublade, die offen steht (grosszuegig 800). Landen wieder
      // Kacheln in zugeklappten Schubladen, faellt der Test — auch dann noch,
      // wenn der Katalog inzwischen doppelt so gross ist.
      final schranke = BadgeKatalogListe.schubladen().length * 60 + 800;
      expect(
        zugeklappt,
        lessThan(schranke),
        reason:
            'Der Auslieferungszustand haengt wieder an der Zahl der Kacheln',
      );
    });

    testWidgets('die Hoehe haengt am Fortschritt, nicht am Katalog', (
      tester,
    ) async {
      // Wer noch nichts hat, und wer schon einiges hat, sehen ungefaehr
      // gleich viel: offen ist immer genau eine Schublade.
      final leer = await baueUndMiss(tester, erreichteIds: const {});
      final voll = await baueUndMiss(
        tester,
        erreichteIds: app.Badge.all.map((b) => b.id).toSet(),
      );
      expect((leer - voll).abs(), lessThan(200));
    });
  });

  group('Auch auf dem kleinsten Telefon', () {
    testWidgets('bei 320 Punkten laeuft keine Kopfzeile ueber', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: BadgeKatalogListe(
                  erreichteIds: const {},
                  metriken: const {app.BadgeMetrik.gesamtKm: 400},
                  kachelBauer: kachel,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Ein Ueberlauf wuerde den Test mit einer Ausnahme abbrechen; hier
      // bleibt nur zu pruefen, dass wirklich alles gebaut wurde.
      expect(tester.takeException(), isNull);
      expect(find.byType(BadgeKatalogListe), findsOneWidget);
    });
  });

  group('Es verschwindet nichts', () {
    test('die Schubladen ergeben zusammen den vollen Katalog', () {
      final verteilt = <String>[
        for (final s in BadgeKatalogListe.schubladen())
          ...BadgeKatalogListe.badgesVon(s).map((b) => b.id),
      ];
      expect(
        verteilt.toSet(),
        app.Badge.all.map((b) => b.id).toSet(),
        reason: 'Ein Abzeichen ist beim Einsortieren verschwunden',
      );
      expect(
        verteilt.length,
        app.Badge.all.length,
        reason: 'Ein Abzeichen steckt in zwei Schubladen',
      );
    });

    testWidgets('mit einem Tipp ist wieder jedes Abzeichen zu sehen', (
      tester,
    ) async {
      await baueUndMiss(tester, erreichteIds: const {});
      await tester.tap(find.text('Alle aufklappen'));
      await tester.pumpAndSettle();

      for (final badge in app.Badge.all) {
        expect(
          find.text(badge.id, skipOffstage: false),
          findsOneWidget,
          reason: 'Abzeichen ${badge.id} ist nicht mehr erreichbar',
        );
      }
      // Und der Schalter fuehrt auch wieder zurueck.
      expect(find.text('Alle zuklappen'), findsOneWidget);
    });

    testWidgets('jede Familie bleibt mit ihrer Kopfzeile sichtbar', (
      tester,
    ) async {
      await baueUndMiss(tester, erreichteIds: const {});
      for (final familie in app.badgeFamilien) {
        expect(
          find.text(familie.titel, skipOffstage: false),
          findsOneWidget,
          reason: 'Familie ${familie.schluessel} ist ganz verschwunden',
        );
      }
    });
  });

  group('Es wird auch nicht leer', () {
    testWidgets('ohne Zutun steht genau eine Schublade offen', (tester) async {
      await baueUndMiss(tester, erreichteIds: const {});
      // Offen heisst: Kacheln sind da. Genau eine Familie zeigt welche.
      final sichtbar = app.Badge.all
          .where(
            (b) => find.text(b.id, skipOffstage: false).evaluate().isNotEmpty,
          )
          .toList();
      expect(sichtbar, isNotEmpty, reason: 'Der Katalog wirkt leer');

      final familien = sichtbar.map((b) => b.familie).toSet();
      expect(
        familien,
        hasLength(1),
        reason: 'Es soll genau eine Schublade offen stehen',
      );
    });

    testWidgets('offen steht die Familie, der man am naechsten ist', (
      tester,
    ) async {
      // 400 von 500 km — „Kilometer" ist damit am weitesten.
      const metriken = <app.BadgeMetrik, double>{app.BadgeMetrik.gesamtKm: 400};
      final erwartet = BadgeKatalogListe.vorgabeOffen(
        erreichteIds: const {},
        metriken: metriken,
      );
      expect(erwartet, 'distanz');

      await baueUndMiss(tester, erreichteIds: const {}, metriken: metriken);
      final sichtbar = app.Badge.all
          .where(
            (b) => find.text(b.id, skipOffstage: false).evaluate().isNotEmpty,
          )
          .toList();
      expect(sichtbar.map((b) => b.familie).toSet(), {'distanz'});
    });

    test('auch wer alles hat, sieht eine offene Schublade', () {
      final alles = app.Badge.all.map((b) => b.id).toSet();
      expect(
        BadgeKatalogListe.vorgabeOffen(erreichteIds: alles),
        app.badgeFamilien.first.schluessel,
      );
    });
  });

  group('Die Kacheln bleiben bedienbar', () {
    testWidgets('ein Tipp auf die Kachel meldet genau dieses Abzeichen', (
      tester,
    ) async {
      app.Badge? getippt;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: breite,
                child: BadgeKatalogListe(
                  erreichteIds: const {},
                  metriken: const {app.BadgeMetrik.gesamtKm: 400},
                  kachelBauer: kachel,
                  onBadgeTippen: (b) => getippt = b,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final erwartet = app.Badge.familienBadges('distanz').first;
      await tester.scrollUntilVisible(find.text(erwartet.id), 120);
      await tester.tap(find.text(erwartet.id));
      await tester.pumpAndSettle();
      expect(getippt?.id, erwartet.id);
    });
  });

  group('Keine Dopplung mit der Uebersicht darueber', () {
    testWidgets('der Katalog wiederholt die Zustands-Schubladen nicht', (
      tester,
    ) async {
      await baueUndMiss(tester, erreichteIds: const {});
      for (final titel in const [
        'In Arbeit',
        'Geschafft',
        'Noch nicht begonnen',
        'Als Nächstes',
      ]) {
        expect(
          find.text(titel, skipOffstage: false),
          findsNothing,
          reason: '„$titel" steht schon oben im Uebersichts-Panel',
        );
      }
    });

    testWidgets('die Fortschrittszahlen stehen nur in der offenen Schublade', (
      tester,
    ) async {
      const metriken = <app.BadgeMetrik, double>{app.BadgeMetrik.gesamtKm: 400};
      await baueUndMiss(tester, erreichteIds: const {}, metriken: metriken);
      expect(
        find.byType(LinearProgressIndicator, skipOffstage: false),
        findsOneWidget,
        reason:
            'Zugeklappte Schubladen sollen keinen Balken tragen — die Zahlen '
            'zum naechsten Ziel stehen oben im Panel',
      );
    });
  });
}
