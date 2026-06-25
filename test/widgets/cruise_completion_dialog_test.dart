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
    Future<CruiseCompletionActionResult> Function(
      int?,
      List<String>,
      String?,
      String?,
    )?
    onSave,
    Future<void> Function()? onDiscard,
    List<List<List<double>>>? routeSegments,
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
            routeSegments: routeSegments,
            onSave:
                onSave ??
                (rating, tags, title, photoUrl) async {
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
      onSave: (rating, tags, title, photoUrl) async {
        savedRating = rating;
        savedTags = tags;
        return CruiseCompletionActionResult(success: false);
      },
    );

    expect(find.text('Wie war diese Route?'), findsOneWidget);
    expect(find.text('Kurz bewerten. Details sind optional.'), findsOneWidget);

    await tester.tap(find.text('Top'));
    await tester.pump();
    await tester.tap(find.text('Details optional'));
    await tester.pumpAndSettle();
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
      expect(find.text('Details optional'), findsOneWidget);
    },
  );

  testWidgets('Completion-Preview akzeptiert GPS-Track mit Segment-Luecke', (
    tester,
  ) async {
    setSurface(tester, const Size(390, 844));

    await pumpCompletionDialog(
      tester,
      routeSegments: const [
        [
          [9.7471, 47.5162],
          [9.75, 47.52],
        ],
        [
          [9.81, 47.55],
          [9.82, 47.56],
        ],
      ],
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Cruise Connector Route'), findsOneWidget);
  });

  testWidgets('Verwerfen schließt auch wenn Sync im Callback fehlschlägt', (
    tester,
  ) async {
    setSurface(tester, const Size(390, 844));

    await pumpCompletionDialog(
      tester,
      onDiscard: () async => throw Exception('backend offline'),
    );

    expect(find.text('Verwerfen'), findsOneWidget);
    await tester.tap(find.text('Verwerfen'));
    await tester.pumpAndSettle();

    expect(find.text('Verwerfen'), findsNothing);
  });
}
