import 'dart:convert';
import 'dart:io';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/tutorial_ziel_registry.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_setup_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-18 (vucko, Sprachnachricht 07 vom 16.08.): „Wenn man eine Gruppe
/// erstellen will, verschwinden die Routentypen — also entweder Rundkurs oder
/// A nach B verschwindet auf einmal."
///
/// Ursache war eine GlobalKey-Kollision. `CruiseSetupCard` steht in ZWEI
/// Seiten (cruise_mode_page.dart:6847 und create_group_page.dart:1336), und
/// beide leben gleichzeitig im Widget-Baum: home_page.dart baut die Tabs als
/// IndexedStack, der einmal besuchte Cruise-Tab bleibt für immer gemountet.
/// `TutorialZielRegistry.key()` vergibt aber prozessweit genau EINEN
/// GlobalKey je Ziel-Id. Zwei lebende Widgets mit demselben GlobalKey heißt
/// im Debug ein Assert, im RELEASE-Build ein stiller Element-Diebstahl —
/// deshalb sah Vucko die Knöpfe verschwinden, ohne jede Fehlermeldung.
///
/// Ausgerechnet die beiden Modus-Knöpfe traf es immer, weil sie als einzige
/// Registry-Ziele in beiden Seiten unbedingt gebaut werden.
///
/// WICHTIG für künftige Änderungen: Ein Test, der die Gruppenkarte ALLEIN
/// pumpt, ist immer grün. Der Fehler entsteht nur, wenn beide Karten
/// gleichzeitig im Baum stehen — genau das macht dieser Test.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget karte({required bool tutorialZiele}) {
    final ziel = TextEditingController();
    addTearDown(ziel.dispose);
    return CruiseSetupCard(
      tutorialZieleRegistrieren: tutorialZiele,
      isRoundTrip: true,
      planningType: 'Zufall',
      selectedLength: '50 km',
      selectedLocation: 'Aktueller Standort',
      selectedStyle: 'Sport Mode',
      selectedDestination: null,
      destinationController: ziel,
      selectedDetour: 'Direkt',
      onRoundTripChanged: (_) {},
      onPlanningTypeChanged: (_) {},
      onLengthChanged: (_) {},
      onLocationChanged: (_) {},
      onStyleChanged: (_) {},
      onDestinationSelected: (_) {},
      onDestinationCleared: () {},
      onDetourChanged: (_) {},
    );
  }

  /// Baut beide Seiten gleichzeitig, so wie die App es tut: die Cruise-Seite
  /// bleibt im IndexedStack am Leben, die Gruppenseite liegt darüber.
  Widget beideSeiten() => ChangeNotifierProvider(
    create: (_) => AppAccentProvider(),
    child: MaterialApp(
      home: Scaffold(
        body: IndexedStack(
          index: 1,
          children: [
            // Tab „Cruise" — gemountet, aber nicht sichtbar. Diese Seite darf
            // die Tutorial-Keys tragen.
            SingleChildScrollView(child: karte(tutorialZiele: true)),
            // Gruppe erstellen — sichtbar. Diese Seite verzichtet.
            SingleChildScrollView(child: karte(tutorialZiele: false)),
          ],
        ),
      ),
    ),
  );

  testWidgets(
    'Routentypen bleiben, wenn Cruise-Seite und Gruppenseite gleichzeitig leben',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(beideSeiten());
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'Keine GlobalKey-Kollision beim gleichzeitigen Aufbau',
      );
      // Zweimal, weil beide Karten gebaut sind. Entscheidend ist, dass die
      // Zahl stimmt: bei der Kollision verlor eine Seite ihre Knöpfe.
      // skipOffstage: false ist Pflicht — der nicht sichtbare Tab des
      // IndexedStack ist offstage, wird aber sehr wohl gebaut. Genau daher
      // kommt die Kollision.
      expect(find.text('Rundkurs', skipOffstage: false), findsNWidgets(2));
      expect(find.text('A nach B', skipOffstage: false), findsNWidgets(2));

      // Ein Neuaufbau darf daran nichts ändern — bei der Kollision wanderte
      // das Element genau hier von einer Seite zur anderen.
      await tester.pumpWidget(beideSeiten());
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Rundkurs', skipOffstage: false), findsNWidgets(2));
      expect(find.text('A nach B', skipOffstage: false), findsNWidgets(2));
    },
  );

  testWidgets('Das Tutorial findet die Modus-Knöpfe weiterhin', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppAccentProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: karte(tutorialZiele: true)),
          ),
        ),
      ),
    );
    await tester.pump();

    // Ohne diese beiden Rechtecke steht der Tutorial-Spotlight an der
    // falschen Stelle — das war Aufgabe 5 der Testfahrt vom 15.08.
    expect(
      TutorialZielRegistry.rect(TutorialZielRegistry.cruiseModusRundkurs),
      isNotNull,
      reason: 'Die Cruise-Seite muss messbar bleiben',
    );
    expect(
      TutorialZielRegistry.rect(TutorialZielRegistry.cruiseModusAtoB),
      isNotNull,
    );
  });

  test('Nur die Cruise-Seite beansprucht die Tutorial-Ziele', () {
    // Quelltext-Wächter: Wer die Gruppenseite später umbaut, soll hier
    // stolpern und nicht erst im Release-Build eines Nutzers.
    final gruppe = const LineSplitter()
        .convert(
          File('lib/presentation/pages/create_group_page.dart')
              .readAsStringSync(),
        )
        .join('\n');
    expect(
      gruppe.contains('tutorialZieleRegistrieren: false'),
      isTrue,
      reason:
          'create_group_page.dart darf die prozessweit eindeutigen '
          'Tutorial-GlobalKeys nicht beanspruchen',
    );
    final cruise = File(
      'lib/presentation/pages/cruise_mode_page.dart',
    ).readAsStringSync();
    expect(
      cruise.contains('tutorialZieleRegistrieren: false'),
      isFalse,
      reason: 'Die Cruise-Seite MUSS die Ziele behalten, sonst stirbt das Tutorial',
    );
  });
}
