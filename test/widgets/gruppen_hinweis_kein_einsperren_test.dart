import 'dart:async';

import 'package:cruise_connect/data/services/safety_notice_service.dart';
import 'package:cruise_connect/presentation/widgets/group_safety_notice_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// REGRESSION 24.08.2026 — dieselbe Bauart wie beim eingesperrten Nutzer
/// (iPhone 15 Pro Max, TikTok-Meldung), nur im Gruppenfahrt-Hinweis.
///
/// Der Hinweis hatte beim AUTOMATISCHEN Aufruf keinen einzigen Ausgang:
/// `isDismissible: force`, `enableDrag: force`, das X nur bei `force`. Der
/// einzige Weg nach vorne war der Knopf „Verstanden", und der hing an
/// `_readToBottom`.
///
/// Seit dem 03.07. gab es dafuer eine Notbremse — nur lief die EIN EINZIGES
/// MAL, im `addPostFrameCallback` aus `initState`. Aendert sich die Groesse
/// spaeter (Drehen, Systemschrift, Splitscreen, Tastatur), lief sie nie
/// wieder: wer vorher nicht gescrollt hatte, sass fest.
///
/// Diese Datei haelt drei Zusagen fest:
///  1. Es gibt IMMER einen Ausgang — X, Hintergrund-Tippen, Wischen,
///     Android-Zurueck —, auf jedem Geraet und in jeder Schriftgroesse.
///  2. Das Lese-Tor gibt frei, sobald alles sichtbar ist — auch wenn das
///     erst nach einer Groessenaenderung passiert.
///  3. Ein hakelnder oder fehlender Speicher sperrt niemanden ein.
void main() {
  final geraete = <_Geraet>[
    const _Geraet('iPhone SE (klein)', Size(320, 568), EdgeInsets.zero),
    const _Geraet('iPhone 8', Size(375, 667), EdgeInsets.zero),
    const _Geraet(
      'iPhone 15 Pro Max',
      Size(430, 932),
      EdgeInsets.only(top: 59, bottom: 34),
    ),
    const _Geraet(
      'Galaxy S24 Ultra',
      Size(480, 1060),
      EdgeInsets.only(top: 40, bottom: 24),
    ),
    const _Geraet('iPad', Size(834, 1194), EdgeInsets.zero),
    const _Geraet('iPad Pro', Size(1024, 1366), EdgeInsets.zero),
    const _Geraet(
      'iPhone 15 Pro Max quer',
      Size(932, 430),
      EdgeInsets.only(left: 59, right: 59, bottom: 21),
    ),
    const _Geraet('Tablet quer', Size(1366, 1024), EdgeInsets.zero),
  ];

  const schriftgroessen = <double>[0.8, 1.0, 2.0];

  /// Oeffnet den Hinweis so, wie ihn die App oeffnet: ueber die Funktion,
  /// nicht ueber das Widget. Nur so werden `isDismissible` und `enableDrag`
  /// mitgeprueft — genau die zwei Schalter, die den Nutzer eingesperrt haben.
  Future<_Lauf> oeffnen(
    WidgetTester tester, {
    required _Geraet geraet,
    required double schrift,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = geraet.size;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(schrift),
            padding: geraet.padding,
            viewPadding: geraet.padding,
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );

    final lauf = _Lauf(showGroupSafetyNoticeSheet(ctx));
    await tester.pumpAndSettle();
    return lauf;
  }

  bool knopfOffen(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

  /// Laesst sich der Haken JETZT setzen? Bewusst genau die Haken-Zeile, nicht
  /// „irgendein Bedienelement" — das X ist immer da und wuerde die Pruefung
  /// wertlos machen.
  bool haekchenOffen(WidgetTester tester) {
    final leer = find.byIcon(CupertinoIcons.square);
    final ziel = tester.any(leer)
        ? leer
        : find.byIcon(CupertinoIcons.checkmark_square_fill);
    return tester
        .widgetList<InkWell>(
          find.ancestor(of: ziel, matching: find.byType(InkWell)),
        )
        .any((w) => w.onTap != null);
  }

  double scrollWeg(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(GroupSafetyNoticeSheet),
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .maxScrollExtent;

  Future<void> bisUntenScrollen(WidgetTester tester) async {
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -6000),
    );
    await tester.pumpAndSettle();
  }

  group('Notausgang', () {
    testWidgets(
      'REPRO 24.08.: Der Schliessen-Knopf ist auch beim automatischen '
      'Aufruf da',
      (tester) async {
        final lauf = await oeffnen(tester, geraet: geraete[2], schrift: 1.0);

        expect(
          find.byIcon(CupertinoIcons.xmark),
          findsOneWidget,
          reason:
              'Ohne X gibt es beim automatischen Aufruf keinen Ausgang — '
              'genau die Bauart, die den Nutzer eingesperrt hat.',
        );

        await tester.tap(find.byIcon(CupertinoIcons.xmark));
        await tester.pumpAndSettle();

        expect(find.byType(GroupSafetyNoticeSheet), findsNothing);
        // Schliessen ist KEINE Zustimmung.
        expect(await lauf.ergebnis, isFalse);
        expect(await SafetyNoticeService.hasAcceptedGroupSafety(), isFalse);
      },
    );

    testWidgets('REPRO 24.08.: Tippen auf den Hintergrund kommt heraus', (
      tester,
    ) async {
      final lauf = await oeffnen(tester, geraet: geraete[2], schrift: 1.0);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      expect(
        find.byType(GroupSafetyNoticeSheet),
        findsNothing,
        reason: 'isDismissible war an `force` gekoppelt und damit aus.',
      );
      expect(await lauf.ergebnis, isFalse);
    });

    testWidgets('REPRO 24.08.: Wegwischen kommt heraus', (tester) async {
      final lauf = await oeffnen(tester, geraet: geraete[2], schrift: 1.0);
      await tester.fling(
        find.byIcon(CupertinoIcons.person_3_fill),
        const Offset(0, 900),
        1200,
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(GroupSafetyNoticeSheet),
        findsNothing,
        reason: 'enableDrag war an `force` gekoppelt und damit aus.',
      );
      expect(await lauf.ergebnis, isFalse);
    });

    testWidgets(
      'Android-Zurueck kommt heraus, gilt aber nicht als Zustimmung',
      (tester) async {
        final lauf = await oeffnen(tester, geraet: geraete[3], schrift: 1.0);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(GroupSafetyNoticeSheet), findsNothing);
        expect(await lauf.ergebnis, isFalse);
        expect(await SafetyNoticeService.hasAcceptedGroupSafety(), isFalse);
      },
    );
  });

  group('Groessenwechsel im laufenden Betrieb', () {
    testWidgets(
      'REPRO 24.08.: Wird das Fenster groesser, ohne dass vorher gescrollt '
      'wurde, sperrt es nicht ein',
      (tester) async {
        // Splitscreen, Slide-Over, aufgeklapptes Foldable, geschlossene
        // Tastatur: das Fenster waechst im laufenden Betrieb. Start: es gibt
        // Scrollweg, das Tor ist zu — und der Nutzer scrollt NICHT.
        final lauf = await oeffnen(
          tester,
          geraet: const _Geraet(
            'Halber Bildschirm',
            Size(420, 700),
            EdgeInsets.zero,
          ),
          schrift: 0.5,
        );
        expect(scrollWeg(tester), greaterThan(24.0));
        expect(knopfOffen(tester), isFalse);
        expect(haekchenOffen(tester), isFalse);

        // Jetzt bekommt die App den ganzen Bildschirm: alles passt hinein.
        tester.view.physicalSize = const Size(420, 900);
        await tester.pumpAndSettle();

        expect(scrollWeg(tester), lessThanOrEqualTo(24.0));
        expect(
          haekchenOffen(tester),
          isTrue,
          reason:
              'Die 03.07.-Notbremse lief nur im ersten Bild. Jetzt gibt es '
              'nichts mehr zu scrollen — es feuert also NIE eine '
              'ScrollNotification und das Tor bliebe fuer immer zu.',
        );

        await tester.tap(find.byIcon(CupertinoIcons.square));
        await tester.pumpAndSettle();
        expect(knopfOffen(tester), isTrue);
        await tester.tap(find.text('Verstanden'));
        await tester.pumpAndSettle();
        expect(await lauf.ergebnis, isTrue);
      },
    );

    testWidgets(
      'REPRO 24.08.: Kleinere Systemschrift im laufenden Betrieb sperrt '
      'nicht ein',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = const Size(430, 932);
        addTearDown(() {
          tester.view
            ..resetPhysicalSize()
            ..resetDevicePixelRatio();
        });

        var schrift = 1.0;
        late StateSetter setzeSchrift;
        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => StatefulBuilder(
              builder: (context, setState) {
                setzeSchrift = setState;
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(schrift)),
                  child: child!,
                );
              },
            ),
            home: Builder(
              builder: (context) {
                ctx = context;
                return const Scaffold(body: SizedBox.expand());
              },
            ),
          ),
        );
        unawaited(showGroupSafetyNoticeSheet(ctx));
        await tester.pumpAndSettle();
        expect(scrollWeg(tester), greaterThan(24.0));
        expect(haekchenOffen(tester), isFalse);

        // Der Nutzer stellt die Systemschrift kleiner — jetzt passt alles.
        setzeSchrift(() => schrift = 0.3);
        await tester.pumpAndSettle();

        expect(scrollWeg(tester), lessThanOrEqualTo(24.0));
        expect(
          haekchenOffen(tester),
          isTrue,
          reason: 'Alles sichtbar heisst alles gelesen — auch nachtraeglich.',
        );
      },
    );

    testWidgets('Einmal gelesen bleibt gelesen, auch wenn es wieder laenger '
        'wird', (tester) async {
      await oeffnen(tester, geraet: geraete[5], schrift: 0.8);
      if (scrollWeg(tester) > 24.0) await bisUntenScrollen(tester);
      expect(haekchenOffen(tester), isTrue);

      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpAndSettle();
      expect(
        haekchenOffen(tester),
        isTrue,
        reason: 'Eine Drehung darf niemanden zurueck ins Tor schicken.',
      );
    });
  });

  group('Bildschirm-Matrix: nirgends festsitzen', () {
    for (final geraet in geraete) {
      for (final schrift in schriftgroessen) {
        testWidgets('${geraet.name} @ Schrift $schrift', (tester) async {
          final lauf = await oeffnen(tester, geraet: geraet, schrift: schrift);
          expect(tester.takeException(), isNull);
          expect(find.byType(GroupSafetyNoticeSheet), findsOneWidget);

          final weg = scrollWeg(tester);
          debugPrint(
            'MATRIX ${geraet.name} ${geraet.size} @ $schrift '
            '-> Scrollweg ${weg.toStringAsFixed(1)}',
          );

          // 1. Ausgang existiert immer.
          expect(
            find.byIcon(CupertinoIcons.xmark),
            findsOneWidget,
            reason: 'Ohne X gibt es keinen Ausgang',
          );

          // 2. Der Knopf liegt im Bild.
          final knopf = tester.getRect(find.byType(FilledButton));
          expect(
            knopf.bottom,
            lessThanOrEqualTo(geraet.size.height + 0.5),
            reason: 'Knopf darf nicht unter dem Bildschirmrand liegen',
          );
          expect(knopf.top, greaterThanOrEqualTo(-0.5));

          // 3. Das Tor ist erfuellbar.
          if (weg > 24.0) {
            expect(haekchenOffen(tester), isFalse);
            await bisUntenScrollen(tester);
          }
          expect(
            haekchenOffen(tester),
            isTrue,
            reason: 'Nach dem Lesen muss das Haekchen setzbar sein',
          );

          // 4. Zustimmen funktioniert und schliesst.
          await tester.tap(find.byIcon(CupertinoIcons.square));
          await tester.pumpAndSettle();
          expect(knopfOffen(tester), isTrue);
          await tester.tap(find.text('Verstanden'));
          await tester.pumpAndSettle();

          expect(find.byType(GroupSafetyNoticeSheet), findsNothing);
          expect(await lauf.ergebnis, isTrue);
          expect(await SafetyNoticeService.hasAcceptedGroupSafety(), isTrue);
        });
      }
    }
  });

  group('Doppelaufruf', () {
    // Bewusst KEINE Sperre in der Show-Funktion: eine haengengebliebene
    // Sperre wuerde „nicht zugestimmt" liefern und das Gruppen-Erstellen
    // dauerhaft blockieren — also genau die Sackgasse, die wir ausraeumen.
    // Statt dessen die Zusage, die zaehlt: aus JEDEM Blatt kommt man heraus,
    // und beide Aufrufe kommen mit einer Antwort zurueck.
    testWidgets('Zwei gleichzeitige Aufrufe sperren niemanden ein', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(430, 932);
      addTearDown(() {
        tester.view
          ..resetPhysicalSize()
          ..resetDevicePixelRatio();
      });

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      );

      final ersteres = showGroupSafetyNoticeSheet(ctx);
      final zweiteres = showGroupSafetyNoticeSheet(ctx);
      await tester.pumpAndSettle();

      // Jedes offene Blatt hat sein eigenes X.
      final offen = tester
          .widgetList(find.byType(GroupSafetyNoticeSheet))
          .length;
      expect(offen, greaterThanOrEqualTo(1));
      for (var i = 0; i < offen; i++) {
        expect(
          find.byIcon(CupertinoIcons.xmark),
          findsWidgets,
          reason: 'Jedes Blatt braucht seinen eigenen Ausgang',
        );
        await tester.tap(find.byIcon(CupertinoIcons.xmark).last);
        await tester.pumpAndSettle();
      }

      expect(find.byType(GroupSafetyNoticeSheet), findsNothing);
      expect(await ersteres, isFalse);
      expect(await zweiteres, isFalse);
    });
  });
}

/// Haelt das noch laufende Ergebnis des Blattes fest. Ein `async`-Helfer
/// koennte es nicht zurueckgeben: Dart faltet verschachtelte Futures.
class _Lauf {
  _Lauf(this.ergebnis);

  final Future<bool> ergebnis;
}

class _Geraet {
  const _Geraet(this.name, this.size, this.padding);

  final String name;
  final Size size;
  final EdgeInsets padding;
}
