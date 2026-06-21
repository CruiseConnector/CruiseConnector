import 'package:cruise_connect/data/services/routing_onboarding_service.dart';
import 'package:cruise_connect/presentation/widgets/cruise/routing_onboarding_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Checkbox-Texte der 5 Wizard-Slides (in Reihenfolge).
  const slideChecks = [
    'Ich entscheide als Fahrer selbst und folge keiner Route blind.',
    'Ich weiß, dass Kartendaten und Routenberechnung abweichen können.',
    'Ich halte mich an die lokalen Verkehrsregeln und Anweisungen.',
    'Ich bediene das Gerät nicht während der Fahrt.',
    'Ich habe die Sicherheits- und Nutzungshinweise verstanden.',
  ];

  Future<void> pumpOnboarding(
    WidgetTester tester, {
    required Size logicalSize,
    double textScale = 1.0,
  }) async {
    SharedPreferences.setMockInitialValues({});
    RoutingOnboardingService.releaseLock();
    await RoutingOnboardingService.reset();

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = logicalSize;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showRoutingOnboardingSheet(context),
                  child: const Text('Onboarding öffnen'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Onboarding öffnen'));
    await tester.pumpAndSettle();
  }

  testWidgets('Sicher-fahren-Wizard rendert auf kleinem iPhone ohne Overflow', (
    tester,
  ) async {
    await pumpOnboarding(tester, logicalSize: const Size(375, 667));
    expect(tester.takeException(), isNull);
    expect(find.text('Sicher fahren'), findsOneWidget);
    expect(find.text('Du entscheidest'), findsOneWidget);
  });

  testWidgets('Sicher-fahren-Wizard rendert auf großem iPhone ohne Overflow', (
    tester,
  ) async {
    await pumpOnboarding(tester, logicalSize: const Size(430, 932));
    expect(tester.takeException(), isNull);
    expect(find.text('Sicher fahren'), findsOneWidget);
  });

  testWidgets(
    'Sicher-fahren-Wizard: kein Overflow bei großer Schrift (textScale 1.3)',
    (tester) async {
      await pumpOnboarding(
        tester,
        logicalSize: const Size(375, 667),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Sicher fahren'), findsOneWidget);
    },
  );

  testWidgets('Wizard bleibt gesperrt bis zum Häkchen und akzeptiert am Ende', (
    tester,
  ) async {
    await pumpOnboarding(tester, logicalSize: const Size(390, 844));

    // Ohne Häkchen: Button gesperrt mit „Häkchen setzen".
    expect(find.text('Häkchen setzen'), findsOneWidget);
    await tester.tap(find.text('Häkchen setzen'));
    await tester.pumpAndSettle();
    expect(await RoutingOnboardingService.hasAccepted(), isFalse);

    // 5 Slides durchklicken: je Häkchen setzen → Weiter/Akzeptieren.
    for (var i = 0; i < slideChecks.length; i++) {
      await tester.tap(find.text(slideChecks[i]));
      await tester.pumpAndSettle();
      final isLast = i == slideChecks.length - 1;
      final label = isLast ? 'Akzeptieren' : 'Weiter';
      expect(find.text(label), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    expect(await RoutingOnboardingService.hasAccepted(), isTrue);
  });
}
