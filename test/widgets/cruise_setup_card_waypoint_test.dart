import 'package:cruise_connect/presentation/widgets/cruise/cruise_setup_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TextEditingController destinationController;

  setUp(() {
    destinationController = TextEditingController();
  });

  tearDown(() {
    destinationController.dispose();
  });

  Widget buildCard({
    int waypointCount = 2,
    int? selectedWaypointIndex,
    int? replacingWaypointIndex,
    VoidCallback? onRemoveLast,
    VoidCallback? onDeleteSelected,
    VoidCallback? onReplaceSelected,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CruiseSetupCard(
            isRoundTrip: true,
            planningType: 'Wegpunkte',
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
            onClearWaypoints: () {},
            onGenerateWaypointSeed: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('zeigt Auswahl-Aktionen nur bei ausgewähltem Bereich', (
    tester,
  ) async {
    var deleted = false;
    var replaced = false;

    await tester.pumpWidget(
      buildCard(
        selectedWaypointIndex: 1,
        onDeleteSelected: () => deleted = true,
        onReplaceSelected: () => replaced = true,
      ),
    );

    expect(
      find.text('Bereich 2 ausgewählt. Du kannst ihn löschen oder neu setzen.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Auswahl löschen'));
    await tester.pump();
    await tester.tap(find.text('Auswahl neu setzen'));
    await tester.pump();

    expect(deleted, isTrue);
    expect(replaced, isTrue);
  });

  testWidgets('zeigt Neu-setzen-Hinweis im Ersetzen-Modus', (tester) async {
    await tester.pumpWidget(
      buildCard(selectedWaypointIndex: 0, replacingWaypointIndex: 0),
    );

    expect(
      find.text('Tippe auf die Karte, um Bereich 1 neu zu setzen.'),
      findsOneWidget,
    );
  });
}
