import 'package:cruise_connect/core/app_changelog.dart';
import 'package:cruise_connect/presentation/widgets/changelog_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-26 (vucko, Aufgabe 3): „Schau, dass das Popup viel angenehmer
/// aussieht — es soll jeden Schritt erklaeren, aber nicht alles in eine
/// riesige Meldung verpacken. Viel weniger Woerter, ganz kurze Erklaerungen.
/// Und oben soll ein Fortschrittsanzeiger stehen, zum Beispiel 1 von 3. Bitte
/// auf dem MacBook bei 110 Prozent testen und auf die 1 von X Anzeige achten."
void main() {
  const eintrag = ChangelogEintrag(
    version: '9.9.9',
    titel: 'Testtitel',
    punkte: <String>['Erster Punkt', 'Zweiter Punkt', 'Dritter Punkt'],
  );

  Future<void> oeffne(WidgetTester tester, {double schriftgroesse = 1.0}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(schriftgroesse)),
            child: Scaffold(
              body: Builder(
                builder: (inner) => TextButton(
                  onPressed: () => showChangelogSheet(inner, eintrag),
                  child: const Text('auf'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
  }

  testWidgets('oben steht 1 von 3, und es zaehlt hoch', (tester) async {
    await oeffne(tester);
    expect(find.text('1 von 3'), findsOneWidget);
    expect(find.text('Erster Punkt'), findsOneWidget);
    // Nur EIN Punkt auf einmal, keine Textwand.
    expect(find.text('Zweiter Punkt'), findsNothing);

    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('2 von 3'), findsOneWidget);
    expect(find.text('Zweiter Punkt'), findsOneWidget);
    expect(find.text('Erster Punkt'), findsNothing);
  });

  testWidgets('der letzte Schritt schliesst mit Alles klar', (tester) async {
    await oeffne(tester);
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('3 von 3'), findsOneWidget);
    expect(find.text('Weiter'), findsNothing);
    expect(find.text('Alles klar'), findsOneWidget);
    // Die Rueckmeldung erst am Ende, damit sie beim Lesen nicht ablenkt.
    expect(find.text('Etwas dazu sagen'), findsOneWidget);

    await tester.tap(find.text('Alles klar'));
    await tester.pumpAndSettle();
    expect(find.text('3 von 3'), findsNothing);
  });

  testWidgets('man kann zurueck', (tester) async {
    await oeffne(tester);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('1 von 3'), findsOneWidget);
  });

  testWidgets('bei 110 Prozent Schrift bleibt alles bedienbar', (tester) async {
    // Genau der Fall, den Vucko pruefen wollte.
    await oeffne(tester, schriftgroesse: 1.1);
    expect(find.text('1 von 3'), findsOneWidget);
    expect(find.text('Weiter'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'kein Ueberlauf');
  });

  testWidgets('auch bei 150 Prozent nichts kaputt', (tester) async {
    await oeffne(tester, schriftgroesse: 1.5);
    expect(find.text('1 von 3'), findsOneWidget);
    expect(find.text('Weiter'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'kein Ueberlauf');
  });

  test('die Texte der aktuellen Version sind kurz', () {
    final eintraege = AppChangelog.eintraege;
    expect(eintraege, isNotEmpty);
    final neuester = eintraege.first;
    for (final p in neuester.punkte) {
      expect(
        p.length,
        lessThanOrEqualTo(140),
        reason: 'zu lang fuer einen Schritt: "$p"',
      );
      expect(p.contains('-'), isFalse, reason: 'Strich in "$p"');
      expect(p.contains('—'), isFalse, reason: 'Gedankenstrich in "$p"');
    }
  });
}
