import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_setup_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-07-28 (vucko): „Bei Rundkurs sieht man keine Erklärung, was der Modus
/// macht. Geht man auf A nach B, sieht man sie — und erst wenn man dann wieder
/// zurück auf Rundkurs geht, kommt sie."
///
/// Ursache: `_activeExplainer` startete auf null, also war beim Öffnen gar
/// keine Erklärung sichtbar, obwohl Rundkurs vorausgewählt ist.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget bauen({required bool istRundkurs}) {
    final destination = TextEditingController();
    addTearDown(destination.dispose);
    return ChangeNotifierProvider(
      create: (_) => AppAccentProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CruiseSetupCard(
              isRoundTrip: istRundkurs,
              planningType: 'Zufall',
              selectedLength: '50 km',
              selectedLocation: 'Aktueller Standort',
              selectedStyle: 'Sport Mode',
              selectedDestination: null,
              destinationController: destination,
              selectedDetour: 'Direkt',
              onRoundTripChanged: (_) {},
              onPlanningTypeChanged: (_) {},
              onLengthChanged: (_) {},
              onLocationChanged: (_) {},
              onStyleChanged: (_) {},
              onDestinationSelected: (_) {},
              onDestinationCleared: () {},
              onDetourChanged: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Rundkurs: Erklärung ist sofort beim Öffnen sichtbar', (
    tester,
  ) async {
    await tester.pumpWidget(bauen(istRundkurs: true));
    await tester.pump();

    expect(
      find.textContaining('Du startest und endest am gleichen Punkt'),
      findsOneWidget,
      reason: 'Ohne Antippen muss die Erklärung zum aktiven Modus dastehen',
    );
    expect(
      find.textContaining('Du gibst Start und Ziel an'),
      findsNothing,
      reason: 'Die Erklärung des anderen Modus darf nicht erscheinen',
    );
  });

  testWidgets('A nach B: passende Erklärung ist sofort sichtbar', (
    tester,
  ) async {
    await tester.pumpWidget(bauen(istRundkurs: false));
    await tester.pump();

    expect(
      find.textContaining('Du gibst Start und Ziel an'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Du startest und endest am gleichen Punkt'),
      findsNothing,
    );
  });

  testWidgets('Modus-Wechsel von außen zieht die Erklärung mit', (
    tester,
  ) async {
    await tester.pumpWidget(bauen(istRundkurs: true));
    await tester.pump();
    expect(
      find.textContaining('Du startest und endest am gleichen Punkt'),
      findsOneWidget,
    );

    await tester.pumpWidget(bauen(istRundkurs: false));
    await tester.pump();
    expect(
      find.textContaining('Du gibst Start und Ziel an'),
      findsOneWidget,
      reason: 'Nach dem Wechsel muss die Erklärung zum NEUEN Modus stehen',
    );
  });
}
