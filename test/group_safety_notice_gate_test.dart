import 'package:cruise_connect/presentation/widgets/group_safety_notice_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 2026-07-03 (vucko): Regressionsschutz fuer den „Erst bis unten scrollen"-Gate
// im Gruppen-Sicherheits-Hinweis. Der Hinweis hat echten Scroll-Overflow
// (~570 px); der Nutzer muss bis zum Ende scrollen, dann darf er das Haekchen
// setzen und die Gruppe erstellen. Dieser Test stellt sicher, dass genau dieser
// Weg funktioniert — sonst waere die Gruppenerstellung blockiert.
void main() {
  Future<void> pumpSheet(WidgetTester tester, Size logicalSize) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = logicalSize;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GroupSafetyNoticeSheet()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Vor dem Scrollen bleibt der Gate gesperrt', (tester) async {
    await pumpSheet(tester, const Size(430, 932));
    expect(find.text('Erst bis unten scrollen'), findsOneWidget);
    expect(find.text('Häkchen setzen'), findsNothing);
  });

  testWidgets(
    'Scrollen bis unten gibt den Gate frei (Haekchen wird moeglich)',
    (tester) async {
      await pumpSheet(tester, const Size(430, 932));
      // Nutzer wischt den Hinweis bis zum Ende.
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();

      // Gate ist frei; jetzt fehlt nur noch das Haekchen.
      expect(find.text('Erst bis unten scrollen'), findsNothing);
      expect(find.text('Häkchen setzen'), findsOneWidget);
    },
  );
}
