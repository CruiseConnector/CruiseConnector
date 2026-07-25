import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/subscription_provider.dart';
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
  }) {
    // 2026-07-25: Seit dem Free-Tier-Gating (Lock-Symbole an Länge/Stil/
    // Inlandsfilter) liest das Setup den SubscriptionProvider live aus — ohne
    // ihn wirft der Build eine ProviderNotFoundException. Default = Free,
    // damit die Tests genau den restriktivsten Fall abdecken.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppAccentProvider()),
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
      ],
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

    expect(
      find.text('Stopp 2 ausgewählt. Nutze die Karten-Aktionen rechts.'),
      findsOneWidget,
    );
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
}
