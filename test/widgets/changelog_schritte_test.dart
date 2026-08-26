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
    anzeigeName: '1.3',
    titel: 'Testtitel',
    schrittTitel: <String>['Titel eins', 'Titel zwei', 'Titel drei'],
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

  testWidgets('das Popup zeigt den Anzeigenamen, nicht die technische Nummer', (
    tester,
  ) async {
    // 2026-08-26 (vucko): „mache auch noch 1.3 bei den Neuigkeiten in der App,
    // nicht 1.5.28." Intern laeuft die technische Nummer weiter, nach aussen
    // zaehlt die Ausgabe.
    await oeffne(tester);
    expect(find.text('Version 1.3'), findsOneWidget);
    expect(find.text('Version 9.9.9'), findsNothing);
  });

  testWidgets('jeder Schritt hat seine eigene Ueberschrift', (tester) async {
    // Vorher stand auf allen Schritten derselbe Versionstitel.
    await oeffne(tester);
    expect(find.text('Titel eins'), findsOneWidget);
    expect(find.text('Testtitel'), findsNothing);

    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('Titel zwei'), findsOneWidget);
    expect(find.text('Titel eins'), findsNothing);
  });

  testWidgets('wegwischen und danebentippen schliessen nicht', (tester) async {
    await oeffne(tester);
    expect(find.text('1 von 3'), findsOneWidget);

    // Tipp auf den abgedunkelten Bereich darueber.
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();
    expect(find.text('1 von 3'), findsOneWidget, reason: 'darf nicht zugehen');

    // Kraeftig nach unten wischen.
    await tester.drag(find.text('Erster Punkt'), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.text('1 von 3'), findsOneWidget, reason: 'darf nicht zugehen');

    // Der Weg hinaus ueber die Knoepfe muss aber immer offen sein.
    expect(find.text('Weiter'), findsOneWidget);
  });

  test('ohne eigene Schritt-Titel bleibt der Versionstitel', () {
    const ohne = ChangelogEintrag(
      version: '1.0.0',
      titel: 'Nur einer',
      punkte: <String>['a', 'b'],
    );
    expect(ohne.titelFuer(0), 'Nur einer');
    expect(ohne.titelFuer(1), 'Nur einer');
    expect(ohne.sichtbareVersion, '1.0.0');
  });

  test('eine unpassend lange Titelliste wird ignoriert', () {
    const schief = ChangelogEintrag(
      version: '1.0.0',
      titel: 'Rueckfall',
      schrittTitel: <String>['nur einer'],
      punkte: <String>['a', 'b'],
    );
    expect(schief.titelFuer(0), 'Rueckfall');
    expect(schief.titelFuer(1), 'Rueckfall');
  });
}
