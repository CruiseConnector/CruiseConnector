import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_setup_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late TextEditingController destinationController;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    destinationController = TextEditingController();
  });

  tearDown(() {
    destinationController.dispose();
  });

  Widget buildCard({
    bool isRoundTrip = true,
    String planningType = 'Wegpunkte',
    int waypointCount = 2,
    int? selectedWaypointIndex,
    int? replacingWaypointIndex,
    VoidCallback? onRemoveLast,
    VoidCallback? onDeleteSelected,
    VoidCallback? onReplaceSelected,
    bool zeigeAuswahlAktionen = false,
  }) {
    return ChangeNotifierProvider(
      create: (_) => AppAccentProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CruiseSetupCard(
            isRoundTrip: isRoundTrip,
            planningType: planningType,
            selectedLength: '50 km',
            selectedLocation: 'Aktueller Standort',
            selectedStyle: 'Sport Mode',
            selectedDestination: null,
            destinationController: destinationController,
            onRoundTripChanged: (_) {},
            onPlanningTypeChanged: (_) {},
            onLengthChanged: (_) {},
            onLocationChanged: (_) {},
            onStyleChanged: (_) {},
            onDestinationSelected: (_) {},
            onDestinationCleared: () {},
            selectedDetour: 'Direkt',
            onDetourChanged: (_) {},
            roundTripWaypointCount: waypointCount,
            selectedWaypointIndex: selectedWaypointIndex,
            replacingWaypointIndex: replacingWaypointIndex,
            onRemoveLastWaypoint: onRemoveLast,
            onDeleteSelectedWaypoint: onDeleteSelected,
            onReplaceSelectedWaypoint: onReplaceSelected,
            zeigeAuswahlAktionen: zeigeAuswahlAktionen,
            onClearWaypoints: () {},
            onGenerateWaypointSeed: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('zeigt Wegpunkt-Hinweis ohne Setup-Aktionschips', (tester) async {
    await tester.pumpWidget(buildCard(selectedWaypointIndex: 1));

    // 2026-08-11: Hier stand „Stopp 2 ausgewählt. Nutze die Karten-Aktionen
    // rechts." Der Satz versprach etwas, das es nicht gibt: Die Rückrufe
    // onReplaceSelectedWaypoint/onDeleteSelectedWaypoint werden von beiden
    // Seiten übergeben, aber in dieser Karte nie aufgerufen — und die
    // Karten-Aktionsleiste kennt nur „Letzten löschen" und „Alle löschen",
    // nichts für den AUSGEWÄHLTEN Stopp. Die Erwartungen weiter unten
    // („Auswahl löschen" findsNothing) belegen genau das.
    // Ohne zeigeAuswahlAktionen (Vorgabe, so nutzt es die Gruppenseite)
    // liegen die Aktionen in deren eigener Karten-Leiste — der Text verweist
    // dorthin und verspricht nichts, was es nicht gibt.
    expect(
      find.text('Stopp 2 ausgewählt. Die Aktionen dafür liegen rechts auf der Karte.'),
      findsOneWidget,
    );
    expect(find.text('Verschieben'), findsNothing);
    expect(find.text('Löschen'), findsNothing);
    expect(
      find.text(
        'Die Strecke ergibt sich aus deinen Stopps. Stil und Aktionen steuerst du direkt auf der Karte.',
      ),
      findsOneWidget,
    );

    expect(find.text('Auswahl löschen'), findsNothing);
    expect(find.text('Auswahl neu setzen'), findsNothing);
    expect(find.text('Letzten löschen'), findsNothing);
    expect(find.text('Stopps vorschlagen'), findsNothing);
    expect(find.text('Route'), findsNothing);
    expect(find.text('Direkt'), findsNothing);
    expect(find.text('Kleiner Umweg'), findsNothing);
    expect(find.text('Stil'), findsNothing);
    expect(find.text('Sport Mode'), findsNothing);
  });

  testWidgets('zeigt Umweg-Auswahl nur im A-nach-B-Modus', (tester) async {
    await tester.pumpWidget(
      buildCard(isRoundTrip: false, planningType: 'Zufall'),
    );

    expect(find.text('Route'), findsOneWidget);
    expect(find.text('Direkt'), findsOneWidget);
    expect(find.text('Kleiner Umweg'), findsOneWidget);
  });

  testWidgets('zeigt Neu-setzen-Hinweis im Ersetzen-Modus', (tester) async {
    await tester.pumpWidget(
      buildCard(selectedWaypointIndex: 0, replacingWaypointIndex: 0),
    );

    expect(
      find.text('Tippe auf die Karte, um Stopp 1 neu zu setzen.'),
      findsOneWidget,
    );
  });

  // 2026-08-12: Im Einzel-Cruise gibt es keine eigene Karten-Leiste. Die
  // Rueckrufe onReplaceSelectedWaypoint/onDeleteSelectedWaypoint wurden dort
  // seit jeher uebergeben, aber nie aufgerufen — ein angetippter Stopp war
  // eine Sackgasse. Mit zeigeAuswahlAktionen liegen die Aktionen hier.
  testWidgets('mit zeigeAuswahlAktionen sind die Aktionen erreichbar', (
    tester,
  ) async {
    var verschoben = false;
    var geloescht = false;

    await tester.pumpWidget(
      buildCard(
        selectedWaypointIndex: 1,
        zeigeAuswahlAktionen: true,
        onReplaceSelected: () => verschoben = true,
        onDeleteSelected: () => geloescht = true,
      ),
    );

    expect(find.text('Stopp 2 ausgewählt.'), findsOneWidget);
    expect(find.text('Verschieben'), findsOneWidget);
    expect(find.text('Löschen'), findsOneWidget);

    await tester.tap(find.text('Verschieben'));
    await tester.pump();
    expect(verschoben, isTrue, reason: 'der Rueckruf muss wirklich feuern');

    await tester.tap(find.text('Löschen'));
    await tester.pump();
    expect(geloescht, isTrue);
  });

  testWidgets('ohne ausgewaehlten Stopp erscheinen sie nicht', (tester) async {
    await tester.pumpWidget(buildCard(zeigeAuswahlAktionen: true));
    expect(find.text('Verschieben'), findsNothing);
    expect(find.text('Löschen'), findsNothing);
  });
}
