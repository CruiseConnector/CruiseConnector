import 'package:cruise_connect/presentation/widgets/start_zeit_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-11 (vucko): „die Datum-/Uhrzeiteinstellung soll wesentlich
/// aesthetischer aussehen und nicht so verklemmt" — und die Zeit soll optional
/// bleiben.
///
/// Der wichtigste Teil dieser Tests ist die Unterscheidung zwischen
/// „abgebrochen" (null) und „ausdruecklich ohne Zeit" (StartZeitWahl.spontan).
/// Ein einzelnes DateTime? koennte das nicht ausdruecken — dann wuerde ein
/// Abbruch versehentlich die gesetzte Zeit loeschen.
void main() {
  Future<StartZeitWahl?> oeffne(
    WidgetTester tester, {
    DateTime? aktuell,
  }) async {
    StartZeitWahl? ergebnis;
    var fertig = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                ergebnis = await zeigeStartZeitSheet(context, aktuell: aktuell);
                fertig = true;
              },
              child: const Text('auf'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
    addTearDown(() => fertig);
    return ergebnis;
  }

  testWidgets('zeigt Titel, Schnellwahl und Tagesleiste', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await oeffne(tester);

    expect(find.text('Wann geht es los?'), findsOneWidget);
    expect(find.text('Heute Abend'), findsOneWidget);
    expect(find.text('Morgen früh'), findsOneWidget);
    expect(find.text('Samstag'), findsOneWidget);
    expect(find.text('Übernehmen'), findsOneWidget);
    expect(find.text('Ohne feste Zeit losfahren'), findsOneWidget);
    // Die Tagesleiste beginnt bei heute.
    expect(find.text('Heute'), findsWidgets);
  });

  testWidgets('„Ohne feste Zeit" liefert spontan (nicht null)', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    StartZeitWahl? ergebnis;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                ergebnis = await zeigeStartZeitSheet(
                  context,
                  aktuell: DateTime.now().add(const Duration(days: 2)),
                );
              },
              child: const Text('auf'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ohne feste Zeit losfahren'));
    await tester.pumpAndSettle();

    expect(ergebnis, isNotNull, reason: 'kein Abbruch, sondern eine Wahl');
    expect(
      ergebnis!.zeitpunkt,
      isNull,
      reason: 'ausdruecklich ohne feste Zeit',
    );
  });

  testWidgets('Übernehmen liefert einen Zeitpunkt', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    StartZeitWahl? ergebnis;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                ergebnis = await zeigeStartZeitSheet(context);
              },
              child: const Text('auf'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Heute Abend'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();

    expect(ergebnis?.zeitpunkt, isNotNull);
    expect(ergebnis!.zeitpunkt!.hour, 18, reason: '„Heute Abend" = 18 Uhr');
  });

  test('spontan und Zeitpunkt sind unterscheidbar', () {
    const spontan = StartZeitWahl.spontan();
    final mitZeit = StartZeitWahl(DateTime(2026, 8, 15, 10));
    expect(spontan.zeitpunkt, isNull);
    expect(mitZeit.zeitpunkt, isNotNull);
  });

  // ── Funde aus der adversarischen Gegenpruefung (2026-08-11) ──────────────
  // Alle vier lagen in genau diesem Blatt und waren echt.

  testWidgets('Schnellwahl bewegt auch das Uhrzeit-Rad mit', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => zeigeStartZeitSheet(context),
              child: const Text('auf'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();

    final vorher = tester
        .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
        .key;
    await tester.tap(find.text('Heute Abend'));
    await tester.pumpAndSettle();
    final nachher = tester
        .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
        .key;

    // CupertinoDatePicker liest initialDateTime nur beim ERSTEN Bauen. Ohne
    // wechselnden Schluessel bliebe das Rad auf der alten Zeit stehen — und
    // die erste Radberuehrung wuerde die Schnellwahl ueberschreiben.
    expect(
      nachher,
      isNot(equals(vorher)),
      reason: 'das Rad muss neu gebaut werden, sonst zeigt es die alte Zeit',
    );
  });

  testWidgets('Schnellwahl liegt nie in der Vergangenheit', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final chip in ['Heute Abend', 'Morgen früh', 'Samstag']) {
      StartZeitWahl? ergebnis;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  ergebnis = await zeigeStartZeitSheet(context);
                },
                child: const Text('auf'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('auf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(chip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();

      expect(
        ergebnis?.zeitpunkt?.isAfter(DateTime.now()),
        isTrue,
        reason: '„$chip" darf keine vergangene Startzeit liefern',
      );
    }
  });

  testWidgets('die Vorgabe-Uhrzeit liegt immer in der Zukunft', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    StartZeitWahl? ergebnis;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                ergebnis = await zeigeStartZeitSheet(context);
              },
              child: const Text('auf'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();

    // Um 23:30 haette die alte Modulo-Rechnung 00:00 am HEUTIGEN Tag ergeben —
    // fast einen ganzen Tag in der Vergangenheit.
    expect(ergebnis?.zeitpunkt?.isAfter(DateTime.now()), isTrue);
  });
}
