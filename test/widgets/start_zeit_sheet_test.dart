import 'package:cruise_connect/presentation/widgets/start_zeit_sheet.dart';
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
}
