import 'dart:io';

import 'package:cruise_connect/core/routen_kappung.dart';
import 'package:cruise_connect/presentation/widgets/social/route_teilen_hinweis_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-31 (Vucko): „das ist halt dann ein Pop-up. Kommt bevor jetzt
/// jemand eine Strecke teilt, dass man sich keine Gedanken machen muss, dass
/// die Strecke dann spaeter andockt."
///
/// Diese Datei sichert vier Dinge ab, die beim Nachbauen leicht kaputtgehen:
///
///  1. Der Hinweis erscheint beim ERSTEN Teilen und verschwindet danach.
///     Waere er dauerhaft, waere er eine Nervquelle und wuerde weggetippt.
///  2. Abbrechen speichert NICHTS und teilt NICHTS. Wer sich anders
///     entscheidet, soll den Hinweis beim naechsten Mal wiedersehen.
///  3. Niemand sitzt im Blatt fest. Am 24.08. gab es genau diesen Vorfall
///     (siehe kein_blatt_ohne_ausweg_test.dart): ein Knopf, der an einer
///     ScrollNotification hing, war auf einem breiten iPhone nie bedienbar.
///  4. Die Zahlen im Text kommen aus den Kappungs-Konstanten. Sonst steht im
///     Blatt irgendwann ein Versprechen, das die App nicht mehr haelt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Baut eine Seite, ruft den Hinweis auf und liefert das Ergebnis nach.
  Future<Future<bool>> zeige(
    WidgetTester tester, {
    required RouteTeilenZiel ziel,
    bool force = false,
    Size groesse = const Size(390, 844),
    double textSkala = 1.0,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = groesse;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: groesse,
            textScaler: TextScaler.linear(textSkala),
          ),
          child: Builder(
            builder: (c) {
              ctx = c;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      ),
    );

    final ergebnis = zeigeRouteTeilenHinweis(ctx, ziel: ziel, force: force);
    await tester.pumpAndSettle();
    return ergebnis;
  }

  group('Der Hinweis erscheint einmal und bestaetigt sauber', () {
    testWidgets('Beim ersten Teilen kommt er, „Teilen" gibt gruenes Licht', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final ergebnis = await zeige(tester, ziel: RouteTeilenZiel.beitrag);
      expect(
        find.byType(RouteTeilenHinweisSheet),
        findsOneWidget,
        reason: 'Ohne Blatt teilt jemand, ohne den Schutz zu kennen.',
      );
      expect(find.text('Was beim Teilen geschützt wird'), findsOneWidget);

      await tester.tap(find.text('Teilen'));
      await tester.pumpAndSettle();

      expect(
        await ergebnis,
        isTrue,
        reason: 'Nach „Teilen" muss der Aufrufer weitermachen duerfen.',
      );
      expect(find.byType(RouteTeilenHinweisSheet), findsNothing);
    });

    testWidgets('Beim zweiten Mal kommt er nicht mehr', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final erster = await zeige(tester, ziel: RouteTeilenZiel.beitrag);
      await tester.tap(find.text('Teilen'));
      await tester.pumpAndSettle();
      expect(await erster, isTrue);

      final zweiter = await zeige(tester, ziel: RouteTeilenZiel.beitrag);
      expect(
        find.byType(RouteTeilenHinweisSheet),
        findsNothing,
        reason:
            'Der Hinweis soll beim ersten Mal kommen und danach nur noch auf '
            'Wunsch. Kommt er jedes Mal, wird er zur Nervquelle.',
      );
      expect(
        await zweiter,
        isTrue,
        reason: 'Ohne Blatt muss sofort weitergeteilt werden duerfen.',
      );
    });

    testWidgets('Auf Wunsch (force) kommt er trotz Merker wieder', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final erster = await zeige(tester, ziel: RouteTeilenZiel.beitrag);
      await tester.tap(find.text('Teilen'));
      await tester.pumpAndSettle();
      expect(await erster, isTrue);

      final nochmal = await zeige(
        tester,
        ziel: RouteTeilenZiel.beitrag,
        force: true,
      );
      expect(
        find.byType(RouteTeilenHinweisSheet),
        findsOneWidget,
        reason:
            'Ohne das kann niemand nachlesen, was beim Teilen geschuetzt '
            'wird — der Eintrag „Schutz beim Teilen" waere tot.',
      );
      await tester.tap(find.text('Teilen'));
      await tester.pumpAndSettle();
      expect(await nochmal, isTrue);
    });
  });

  group('Abbrechen teilt nichts und merkt sich nichts', () {
    testWidgets('„Abbrechen" liefert false', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final ergebnis = await zeige(tester, ziel: RouteTeilenZiel.beitrag);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      expect(
        await ergebnis,
        isFalse,
        reason:
            'Der Aufrufer darf nach dem Abbrechen NICHT weitermachen. Sonst '
            'landet der Beitrag trotzdem im Feed.',
      );
    });

    testWidgets('Nach dem Abbrechen kommt der Hinweis wieder', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final erster = await zeige(tester, ziel: RouteTeilenZiel.beitrag);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(await erster, isFalse);

      await zeige(tester, ziel: RouteTeilenZiel.beitrag);
      expect(
        find.byType(RouteTeilenHinweisSheet),
        findsOneWidget,
        reason:
            'Abbrechen ist keine Kenntnisnahme. Wer abbricht, hat den Text '
            'vielleicht gar nicht gelesen.',
      );
    });

    testWidgets('Wegwischen (Hintergrund tippen) liefert false', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final ergebnis = await zeige(tester, ziel: RouteTeilenZiel.beitrag);
      expect(find.byType(RouteTeilenHinweisSheet), findsOneWidget);

      // Ganz oben ist nur der abdunkelnde Hintergrund. Ein Tipp dorthin muss
      // das Blatt schliessen — sonst gibt es auf iOS keinen Ausweg.
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();

      expect(find.byType(RouteTeilenHinweisSheet), findsNothing);
      expect(await ergebnis, isFalse);
    });
  });

  group('Die beiden Ziele haben getrennte Merker', () {
    testWidgets('Beitrag bestaetigt heisst nicht Bild bestaetigt', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final beitrag = await zeige(tester, ziel: RouteTeilenZiel.beitrag);
      await tester.tap(find.text('Teilen'));
      await tester.pumpAndSettle();
      expect(await beitrag, isTrue);

      await zeige(tester, ziel: RouteTeilenZiel.bild);
      expect(
        find.byType(RouteTeilenHinweisSheet),
        findsOneWidget,
        reason:
            'Die beiden Texte sagen Verschiedenes. Wer nur den einen gesehen '
            'hat, kennt den anderen nicht.',
      );
      expect(find.text('Bevor du das Bild weitergibst'), findsOneWidget);
      expect(
        find.text('Weiter'),
        findsOneWidget,
        reason:
            'Beim Bild wird noch nichts geteilt, es oeffnet sich nur der '
            'Composer. „Teilen" waere an dieser Stelle gelogen.',
      );
    });
  });

  group('Niemand sitzt im Blatt fest', () {
    testWidgets(
      'Winzige Schrift auf breitem iPhone: beide Knoepfe sind bedienbar',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});

        // Das Geraet aus dem Vorfall vom 24.08.: 430 Punkte breit, dazu eine
        // Schrift, bei der garantiert nichts zu scrollen bleibt.
        await zeige(
          tester,
          ziel: RouteTeilenZiel.beitrag,
          groesse: const Size(430, 932),
          textSkala: 0.3,
        );

        final bedienbar = tester.allWidgets.where(
          (w) =>
              (w is ButtonStyleButton && w.onPressed != null) ||
              (w is IconButton && w.onPressed != null),
        );
        expect(
          bedienbar.length,
          greaterThanOrEqualTo(2),
          reason:
              'Es muss im ERSTEN Bild sowohl ein Weiter als auch ein Zurueck '
              'geben, ohne dass vorher gescrollt werden muss.',
        );
      },
    );

    testWidgets('Sehr grosse Schrift auf schmalem Handy laeuft nicht ueber', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      await zeige(
        tester,
        ziel: RouteTeilenZiel.beitrag,
        groesse: const Size(320, 568),
        textSkala: 2.0,
      );

      expect(
        tester.takeException(),
        isNull,
        reason:
            'Ein Overflow hier heisst: auf einem alten Handy mit grosser '
            'Systemschrift ist der Knopf nicht erreichbar.',
      );
      expect(find.text('Teilen'), findsOneWidget);
    });
  });

  group('Der Text sagt die Wahrheit', () {
    test('Die Zahlen stammen aus den Kappungs-Konstanten', () {
      expect(anzeigeKappungText(), '${anzeigeKappungMeter.round()} Meter');
      expect(
        fremdfahrtKappungText(),
        '${(fremdfahrtKappungMeter / 1000).round()} km',
      );

      final beitrag = hinweisZeilen(RouteTeilenZiel.beitrag).join(' ');
      expect(
        beitrag.contains(anzeigeKappungText()),
        isTrue,
        reason:
            'Aendert jemand anzeigeKappungMeter, muss der Text mitwandern. '
            'Fest getippte Zahlen werden hier zur Luege.',
      );
      expect(beitrag.contains(fremdfahrtKappungText()), isTrue);
    });

    test('Beide Texte bleiben kurz: drei bis vier Zeilen', () {
      for (final ziel in RouteTeilenZiel.values) {
        final zeilen = hinweisZeilen(ziel);
        expect(
          zeilen.length,
          inInclusiveRange(3, 4),
          reason: 'Vucko: „Kurz halten, drei bis vier Zeilen, kein Roman."',
        );
        for (final zeile in zeilen) {
          expect(
            zeile.length,
            lessThanOrEqualTo(130),
            reason: 'Zu lange Zeile im Hinweis: „$zeile"',
          );
        }
      }
    });

    test('Der Bild-Text verspricht NICHT den Schutz des Beitrags', () {
      // Der Composer kennt das Format „Karte" mit echter Basemap. Wer dort
      // „keine Karte" verspricht, luegt den Nutzer an.
      final bild = hinweisZeilen(RouteTeilenZiel.bild).join(' ');
      expect(
        bild.contains('gekappt'),
        isFalse,
        reason:
            'Beim Bild wird nichts gekappt. route_share_page zeichnet die '
            'uebergebenen Segmente unveraendert.',
      );
      expect(
        bild.contains('Karte'),
        isTrue,
        reason:
            'Das Format Karte muss beim Namen genannt werden, sonst ist der '
            'Hinweis wertlos.',
      );
    });
  });

  group('Alle Teilen-Wege dieser Domaene fragen vorher', () {
    // Quelltext-Waechter: Baut jemand eine der beiden Stellen um und
    // vergisst den Hinweis, faellt das hier auf und nicht erst dem Nutzer.
    const stellen = <String, List<String>>{
      'lib/presentation/pages/saved_route_bookmarks_page.dart': [
        '_shareRouteAsPost',
        '_shareRouteExternally',
      ],
      'lib/presentation/pages/ride_detail_page.dart': ['_openShare'],
    };

    for (final eintrag in stellen.entries) {
      test('${eintrag.key} ruft den Hinweis auf', () {
        final quelle = File(eintrag.key).readAsStringSync();
        expect(
          File(eintrag.key).existsSync(),
          isTrue,
          reason: 'Datei umbenannt? Dann diesen Test mit umziehen.',
        );
        for (final methode in eintrag.value) {
          expect(
            quelle.contains(methode),
            isTrue,
            reason:
                'Die Teilen-Methode $methode gibt es nicht mehr. Wurde sie '
                'umbenannt, gehoert der Hinweis an die neue Stelle.',
          );
        }
        expect(
          'zeigeRouteTeilenHinweis'.allMatches(quelle).length,
          greaterThanOrEqualTo(eintrag.value.length),
          reason:
              'In ${eintrag.key} teilt jemand eine Strecke, ohne vorher '
              'zeigeRouteTeilenHinweis zu rufen. Genau das war der Auftrag.',
        );
      });
    }
  });
}
