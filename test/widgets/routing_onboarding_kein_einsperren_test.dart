import 'dart:async';

import 'package:cruise_connect/data/services/routing_onboarding_service.dart';
import 'package:cruise_connect/presentation/widgets/cruise/routing_onboarding_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// REGRESSION 24.08.2026 — Der eingesperrte Nutzer (TikTok, iPhone 15 Pro Max)
///
/// Das Blatt „Routing verstehen" gab den Knopf nur frei, wenn eine
/// ScrollNotification meldete, dass der Nutzer unten angekommen ist. Passt der
/// Inhalt ohne Scrollen in das Blatt, ist `maxScrollExtent == 0`; Flutter
/// schaltet dann per `ScrollPhysics.shouldAcceptUserOffset` die Zieh-Geste ganz
/// ab. Es feuert also NIE eine ScrollNotification, der Knopf bleibt fuer immer
/// auf „Erst vollstaendig lesen" — und weil beim automatischen Aufruf
/// `isDismissible`, `enableDrag` und der Schliessen-Knopf alle aus waren, gab es
/// keinen anderen Ausgang. Die App war eingefroren.
///
/// Diese Tests decken die Bildschirm-Matrix ab. Sie duerfen NIE wieder
/// zulassen, dass ein Zustand ohne Ausgang entsteht.
void main() {
  /// Ein Geraet aus der Matrix.
  final geraete = <_Geraet>[
    // Schmales altes Geraet.
    const _Geraet('iPhone SE (klein)', Size(320, 568), EdgeInsets.zero),
    const _Geraet('iPhone 8', Size(375, 667), EdgeInsets.zero),
    // Das Geraet des Betroffenen.
    const _Geraet(
      'iPhone 15 Pro Max',
      Size(430, 932),
      EdgeInsets.only(top: 59, bottom: 34),
    ),
    // Grosses Android.
    const _Geraet(
      'Galaxy S24 Ultra',
      Size(480, 1060),
      EdgeInsets.only(top: 40, bottom: 24),
    ),
    // Tablets — hier passt der Inhalt am ehesten ohne Scrollen hinein.
    const _Geraet('iPad', Size(834, 1194), EdgeInsets.zero),
    const _Geraet('iPad Pro', Size(1024, 1366), EdgeInsets.zero),
    // Querformat.
    const _Geraet(
      'iPhone 15 Pro Max quer',
      Size(932, 430),
      EdgeInsets.only(left: 59, right: 59, bottom: 21),
    ),
    const _Geraet('Tablet quer', Size(1366, 1024), EdgeInsets.zero),
  ];

  // Kleinste und groesste Systemschrift plus Normalfall.
  const schriftgroessen = <double>[0.8, 1.0, 2.0];

  Future<void> oeffnen(
    WidgetTester tester, {
    required _Geraet geraet,
    required double schrift,
  }) async {
    SharedPreferences.setMockInitialValues({});
    await RoutingOnboardingService.reset();

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = geraet.size;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

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
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showRoutingOnboardingSheet(context),
                child: const Text('Onboarding öffnen'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Onboarding öffnen'));
    await tester.pumpAndSettle();
  }

  bool knopfOffen(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

  double scrollWeg(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(RoutingOnboardingSheet),
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .maxScrollExtent;

  group('Der Inhalt passt ohne Scrollen', () {
    // ACHTUNG beim Nachrechnen: der Test laeuft mit der Flutter-Testschrift.
    // Die laeuft deutlich breiter als SF Pro (iOS) und Roboto (Android), der
    // Inhalt braucht hier also mehr Zeilen als auf einem echten Geraet. Auf
    // dem Geraet kippt es deshalb frueher — beim Betroffenen auf einem
    // iPhone 15 Pro Max (430 Punkte breit, das breiteste iPhone). Die
    // Schriftgroessen unten sind so gewaehlt, dass der Testaufbau denselben
    // Zustand erreicht: Scrollweg 0.
    testWidgets(
      'REPRO 24.08.: kein Scrollweg => Knopf muss trotzdem sofort frei sein',
      (tester) async {
        await oeffnen(
          tester,
          geraet: const _Geraet('iPad', Size(834, 1194), EdgeInsets.zero),
          schrift: 0.75,
        );

        expect(
          scrollWeg(tester),
          0.0,
          reason: 'Vorbedingung des Fehlers: es gibt nichts zu scrollen',
        );

        // Genau hier hing die App: kein Scrollweg => keine ScrollNotification
        // => der Knopf blieb fuer immer gesperrt.
        expect(
          knopfOffen(tester),
          isTrue,
          reason:
              'Was vollstaendig sichtbar ist, ist vollstaendig gelesen — der '
              'Knopf muss ohne Scrollen freigegeben sein',
        );
        expect(find.text('Verstanden'), findsOneWidget);

        await tester.tap(find.text('Verstanden'));
        await tester.pumpAndSettle();
        expect(find.text('Routing verstehen'), findsNothing);
        expect(await RoutingOnboardingService.hasAccepted(), isTrue);
      },
    );

    testWidgets('REPRO 24.08.: dasselbe auf dem Geraet des Betroffenen '
        '(iPhone 15 Pro Max)', (tester) async {
      await oeffnen(
        tester,
        geraet: const _Geraet(
          'iPhone 15 Pro Max',
          Size(430, 932),
          EdgeInsets.only(top: 59, bottom: 34),
        ),
        schrift: 0.6,
      );

      expect(scrollWeg(tester), 0.0);
      expect(
        knopfOffen(tester),
        isTrue,
        reason: 'Genau dieser Zustand hat den Nutzer eingesperrt',
      );
    });

    testWidgets('ohne Scrollweg ist auch die Zieh-Geste tot (Beweis)', (
      tester,
    ) async {
      await oeffnen(
        tester,
        geraet: const _Geraet('iPad', Size(834, 1194), EdgeInsets.zero),
        schrift: 0.75,
      );
      expect(scrollWeg(tester), 0.0);

      // Ziehen aendert nichts — Flutter nimmt bei maxScrollExtent == 0 gar
      // keine Zieh-Geste mehr an. Der alte Code konnte hier nie freigeben.
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      expect(scrollWeg(tester), 0.0);
    });
  });

  group('Notausgang', () {
    testWidgets(
      'Schliessen-Knopf ist IMMER da — auch beim automatischen Aufruf',
      (tester) async {
        await oeffnen(tester, geraet: geraete[2], schrift: 1.0);
        expect(find.byIcon(CupertinoIcons.xmark), findsOneWidget);

        await tester.tap(find.byIcon(CupertinoIcons.xmark));
        await tester.pumpAndSettle();

        expect(find.text('Routing verstehen'), findsNothing);
        // Schliessen ist KEINE Zustimmung: der Hinweis kommt wieder.
        expect(await RoutingOnboardingService.hasAccepted(), isFalse);
      },
    );

    testWidgets('Tippen auf den Hintergrund schliesst das Blatt', (
      tester,
    ) async {
      await oeffnen(tester, geraet: geraete[2], schrift: 1.0);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('Routing verstehen'), findsNothing);
      expect(await RoutingOnboardingService.hasAccepted(), isFalse);
    });

    testWidgets('Android-Zurueck kommt heraus, gilt aber NICHT als gelesen', (
      tester,
    ) async {
      await oeffnen(tester, geraet: geraete[3], schrift: 1.0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Routing verstehen'), findsNothing);
      expect(await RoutingOnboardingService.hasAccepted(), isFalse);
    });
  });

  group('Bildschirm-Matrix: nirgends festsitzen', () {
    for (final geraet in geraete) {
      for (final schrift in schriftgroessen) {
        testWidgets('${geraet.name} @ Schrift $schrift', (tester) async {
          await oeffnen(tester, geraet: geraet, schrift: schrift);
          expect(tester.takeException(), isNull);
          expect(find.text('Routing verstehen'), findsOneWidget);

          final weg = scrollWeg(tester);
          debugPrint(
            'MATRIX ${geraet.name} ${geraet.size} @ $schrift '
            '-> Scrollweg ${weg.toStringAsFixed(1)}',
          );

          // 1. Notausgang existiert immer.
          expect(
            find.byIcon(CupertinoIcons.xmark),
            findsOneWidget,
            reason: 'Ohne Schliessen-Knopf gibt es keinen Ausgang',
          );

          // 2. Der Knopf ist erreichbar (nicht ausserhalb des Bildschirms).
          final knopf = tester.getRect(find.byType(FilledButton));
          expect(
            knopf.bottom,
            lessThanOrEqualTo(geraet.size.height + 0.5),
            reason: 'Knopf darf nicht unter dem Bildschirmrand liegen',
          );
          expect(knopf.top, greaterThanOrEqualTo(-0.5));

          // 3. Freigabe: passt alles hinein, sofort; sonst nach dem Scrollen.
          if (weg <= 24.0) {
            expect(
              knopfOffen(tester),
              isTrue,
              reason: 'Alles sichtbar => sofort frei',
            );
          } else {
            expect(knopfOffen(tester), isFalse);
            await tester.drag(
              find.byType(SingleChildScrollView),
              const Offset(0, -6000),
            );
            await tester.pumpAndSettle();
            expect(
              knopfOffen(tester),
              isTrue,
              reason: 'Nach dem Scrollen bis unten muss frei sein',
            );
          }

          // 4. Bestaetigen funktioniert und schliesst.
          await tester.tap(find.text('Verstanden'));
          await tester.pumpAndSettle();
          expect(find.text('Routing verstehen'), findsNothing);
          expect(await RoutingOnboardingService.hasAccepted(), isTrue);
        });
      }
    }
  });

  group('Groessenwechsel im laufenden Betrieb', () {
    testWidgets(
      'Drehen vom Hochformat ins Querformat sperrt nicht wieder ein',
      (tester) async {
        await oeffnen(tester, geraet: geraete[4], schrift: 0.8);
        expect(knopfOffen(tester), isTrue);

        tester.view.physicalSize = const Size(1194, 834);
        await tester.pumpAndSettle();
        expect(
          knopfOffen(tester),
          isTrue,
          reason: 'Einmal gelesen bleibt gelesen',
        );
      },
    );

    testWidgets(
      'Wird der Inhalt erst nach dem Drehen vollstaendig sichtbar, gibt der '
      'Knopf nachtraeglich frei',
      (tester) async {
        // Start: Querformat, viel Scrollweg.
        await oeffnen(
          tester,
          geraet: const _Geraet(
            'Tablet quer',
            Size(1024, 700),
            EdgeInsets.zero,
          ),
          schrift: 0.8,
        );
        final vorher = scrollWeg(tester);
        expect(vorher, greaterThan(24.0));
        expect(knopfOffen(tester), isFalse);

        // Drehen ins Hochformat: jetzt passt alles hinein.
        tester.view.physicalSize = const Size(1024, 1366);
        await tester.pumpAndSettle();
        expect(scrollWeg(tester), lessThanOrEqualTo(24.0));
        expect(
          knopfOffen(tester),
          isTrue,
          reason:
              'Nach dem Drehen ist alles sichtbar — ohne erneute '
              'ScrollNotification muss der Knopf trotzdem freigeben',
        );
      },
    );
  });

  group('App-Wechsel', () {
    testWidgets(
      'Blatt bleibt nach App-Wechsel bedienbar und stapelt sich nicht',
      (tester) async {
        await oeffnen(tester, geraet: geraete[2], schrift: 1.0);
        expect(find.text('Routing verstehen'), findsOneWidget);

        // Der Nutzer wechselt in eine andere App und kommt zurueck.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        // Genau EIN Blatt, weiterhin mit Ausgang und bedienbar.
        expect(find.text('Routing verstehen'), findsOneWidget);
        expect(find.byIcon(CupertinoIcons.xmark), findsOneWidget);

        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -6000),
        );
        await tester.pumpAndSettle();
        expect(knopfOffen(tester), isTrue);
        await tester.tap(find.text('Verstanden'));
        await tester.pumpAndSettle();
        expect(find.text('Routing verstehen'), findsNothing);
      },
    );
  });

  group('Doppelaufruf', () {
    testWidgets('zwei gleichzeitige Aufrufe oeffnen nur EIN Blatt', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await RoutingOnboardingService.reset();
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

      // Gleichzeitig, ohne dazwischen zu pumpen — genau der Fall aus dem
      // Doppel-Frame/App-Wechsel.
      unawaited(showRoutingOnboardingSheet(ctx));
      unawaited(showRoutingOnboardingSheet(ctx));
      await tester.pumpAndSettle();

      expect(find.text('Routing verstehen'), findsOneWidget);

      // Und nach dem Schliessen ist die Sperre wieder frei.
      await tester.tap(find.byIcon(CupertinoIcons.xmark));
      await tester.pumpAndSettle();
      expect(RoutingOnboardingService.isOpen, isFalse);
    });
  });
}

class _Geraet {
  const _Geraet(this.name, this.size, this.padding);

  final String name;
  final Size size;
  final EdgeInsets padding;
}
