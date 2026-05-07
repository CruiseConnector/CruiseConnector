import 'package:cruise_connect/data/services/routing_onboarding_service.dart';
import 'package:cruise_connect/presentation/widgets/cruise/routing_onboarding_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpOnboarding(
    WidgetTester tester, {
    required Size logicalSize,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = logicalSize;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
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

  testWidgets('Routing-Onboarding bleibt gesperrt bis zum Scroll-Ende', (
    tester,
  ) async {
    await pumpOnboarding(tester, logicalSize: const Size(390, 844));

    expect(find.text('Erst vollständig lesen'), findsOneWidget);
    await tester.tap(find.text('Erst vollständig lesen'));
    await tester.pumpAndSettle();
    expect(await RoutingOnboardingService.hasAccepted(), isFalse);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -5000),
    );
    await tester.pumpAndSettle();

    expect(find.text('Verstanden'), findsOneWidget);
    await tester.tap(find.text('Verstanden'));
    await tester.pumpAndSettle();

    expect(await RoutingOnboardingService.hasAccepted(), isTrue);
    expect(find.text('Routing verstehen'), findsNothing);
  });

  testWidgets('Routing-Onboarding rendert auf kleinem iPhone ohne Overflow', (
    tester,
  ) async {
    await pumpOnboarding(tester, logicalSize: const Size(375, 667));
    expect(tester.takeException(), isNull);
    expect(find.text('Routing verstehen'), findsOneWidget);
  });

  testWidgets('Routing-Onboarding rendert auf großem iPhone ohne Overflow', (
    tester,
  ) async {
    await pumpOnboarding(tester, logicalSize: const Size(430, 932));
    expect(tester.takeException(), isNull);
    expect(find.text('Routing verstehen'), findsOneWidget);
  });
}
