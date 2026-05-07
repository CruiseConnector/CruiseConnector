import 'package:cruise_connect/presentation/widgets/cruise/cruise_completion_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Completion-Rating sendet Qualitätsstufe und Tags', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    int? savedRating;
    List<String>? savedTags;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CruiseCompletionDialog(
            distanceKm: 42.5,
            durationText: '55 min',
            curves: 18,
            xpEarned: 120,
            routeCoordinates: const [
              [9.7471, 47.5162],
              [9.75, 47.52],
              [9.7471, 47.5162],
            ],
            onSave: (rating, tags) async {
              savedRating = rating;
              savedTags = tags;
              return CruiseCompletionActionResult(success: false);
            },
            onDiscard: () async {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Wie war diese Route?'), findsOneWidget);
    expect(
      find.text('Dein Feedback verbessert zukünftige Vorschläge.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Top'));
    await tester.pump();
    await tester.tap(find.text('schöne Kurven'));
    await tester.pump();
    await tester.tap(find.text('Autobahn trotz AUS'));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pump();

    expect(savedRating, 5);
    expect(savedTags, containsAll(['schöne Kurven', 'Autobahn trotz AUS']));
  });
}
