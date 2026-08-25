import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/presentation/pages/create_group_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildPage() {
    return ChangeNotifierProvider(
      create: (_) => AppAccentProvider(),
      child: const MaterialApp(
        home: CreateGroupPage(disableMapTilesForTesting: true),
      ),
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
    expect(find.text('Details zur Gruppe'), findsOneWidget);

    final createButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Erstellen'),
    );
    expect(createButton.onPressed, isNull);
  });

  testWidgets(
    'zeigt den „Gespeicherte Route verwenden"-Button und er ist tappbar',
    (tester) async {
      // 2026-07-03 (vucko): Regressionsschutz. Der Button war im (veralteten)
      // Worktree-Build gar nicht vorhanden und lag im Haupt-Checkout in der
      // transparenten Bottom-Bar. Jetzt im scrollbaren Formular-Body → muss
      // sichtbar UND als aktiver ElevatedButton rendern.
      await tester.pumpWidget(buildPage());
      await tester.pump();

      final button = find.widgetWithText(
        ElevatedButton,
        'Gespeicherte Route verwenden',
      );
      expect(button, findsOneWidget);

      // Aktiv (nicht generierend) → onPressed gesetzt, also wirklich tappbar.
      expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
    },
  );

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
