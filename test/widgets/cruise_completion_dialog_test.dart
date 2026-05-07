import 'package:cruise_connect/presentation/widgets/cruise/cruise_completion_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void setSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Future<void> pumpCompletionDialog(
    WidgetTester tester, {
    Future<CruiseCompletionActionResult> Function(int?, List<String>)? onSave,
    Future<void> Function()? onDiscard,
  }) async {
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
            onSave:
                onSave ??
                (rating, tags) async {
                  return CruiseCompletionActionResult(success: false);
                },
            onDiscard: onDiscard ?? () async {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  testWidgets('Completion-Rating sendet Qualitätsstufe und Tags', (
    tester,
  ) async {
    setSurface(tester, const Size(430, 1200));

    int? savedRating;
    List<String>? savedTags;

    await pumpCompletionDialog(
      tester,
      onSave: (rating, tags) async {
        savedRating = rating;
        savedTags = tags;
        return CruiseCompletionActionResult(success: false);
      },
    );

    expect(find.text('Wie war diese Route?'), findsOneWidget);
    expect(find.text('Kurz bewerten. Details sind optional.'), findsOneWidget);

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

  testWidgets('Completion-Rating bleibt auf kleinem iPhone kompakt', (
    tester,
  ) async {
    setSurface(tester, const Size(320, 640));

    await pumpCompletionDialog(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Wie war diese Route?'), findsOneWidget);
    expect(find.text('Speichern'), findsOneWidget);
    expect(find.text('Teilen'), findsOneWidget);
    expect(find.text('Verwerfen'), findsOneWidget);
  });

  testWidgets(
    'Completion-Rating nutzt großen iPhone-Screen ohne Fullscreen-Zwang',
    (tester) async {
      setSurface(tester, const Size(430, 932));

      await pumpCompletionDialog(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Top'), findsOneWidget);
      expect(find.text('Okay'), findsOneWidget);
      expect(find.text('Schlecht'), findsOneWidget);
      expect(find.text('schöne Kurven'), findsOneWidget);
    },
  );
}
