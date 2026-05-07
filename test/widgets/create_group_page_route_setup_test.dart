import 'package:cruise_connect/presentation/pages/create_group_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildPage() {
    return const MaterialApp(
      home: CreateGroupPage(disableMapTilesForTesting: true),
    );
  }

  testWidgets('zeigt CruiseMode-Setup in der Gruppenerstellung', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();

    expect(find.text('Rundkurs'), findsOneWidget);
    expect(find.text('A nach B'), findsOneWidget);
    expect(find.text('Zufall'), findsOneWidget);
    expect(find.text('Wegpunkte'), findsOneWidget);
    expect(find.text('Gruppen-Details'), findsOneWidget);

    final createButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Erstellen'),
    );
    expect(createButton.onPressed, isNull);
  });

  testWidgets('zeigt Umweg-Auswahl erst im A-nach-B-Modus', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();

    expect(find.text('Kleiner Umweg'), findsNothing);

    await tester.tap(find.text('A nach B'));
    await tester.pumpAndSettle();

    expect(find.text('Kleiner Umweg'), findsOneWidget);
    expect(find.text('Großer Umweg'), findsOneWidget);
  });
}
