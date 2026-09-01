// 2026-09-01 — Vucko, Sprachaufnahme (Aufgabe A18):
//   "Manchmal haengt es nach der Badge-Animation ... ja, dass das mit dem Bug
//    behoben wird."
//
// Das "manchmal" war der entscheidende Hinweis. Es haengt nicht immer, sondern
// nur, wenn sich waehrend der 3,65 Sekunden Feier etwas darueberschiebt.
//
// DREI URSACHEN, alle belegt:
//
// 1. `maybePop()` schliesst die OBERSTE Route im Stapel, nicht die eigene.
//    Liegt inzwischen das Neuerungen-Blatt oder die Sterne-Frage darueber
//    (home_page.dart:390 oeffnet beides beim Antippen des Home-Reiters),
//    schloss die Feier das FREMDE Blatt und blieb selbst stehen.
// 2. Kein Wiedereintritts-Schutz: `zeigeOffeneAuszeichnungen` liest die
//    offenen Abzeichen und quittiert sie erst NACH der Feier. Zwei Aufrufer
//    kurz hintereinander — die Funktion wird an sieben Stellen gerufen —
//    bekamen dieselbe Liste und legten zwei Feiern uebereinander.
// 3. Die Verleih-Kette der Starter-Karte hatte keinen Faenger. Nach dem
//    ersten Fehlschlag stand sie dauerhaft auf einem abgelehnten Future, und
//    jede weitere Verleihung haengte sich daran an und lief nie.
//
// Diesen Test gab es vorher nicht. Ohne ihn faellt derselbe Fehler beim
// naechsten Umbau wieder hinein.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/presentation/widgets/badge_unlock_popup.dart';

Widget _huelle(void Function(BuildContext) beiAufbau) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => beiAufbau(context),
              child: const Text('los'),
            ),
          ),
        );
      },
    ),
  );
}

app.Badge _einAbzeichen() {
  final b = app.Badge.getById('badge_01');
  expect(b, isNotNull, reason: 'badge_01 muss es im Katalog geben.');
  return b!;
}

void main() {
  testWidgets('die Feier schliesst sich selbst, auch wenn etwas darueber liegt',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      _huelle((context) {
        ctx = context;
        showBadgeUnlockPopup(context: context, badges: [_einAbzeichen()]);
      }),
    );

    await tester.tap(find.text('los'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byType(BackdropFilter),
      findsWidgets,
      reason: 'Die Feier muss ueberhaupt erst da sein.',
    );

    // Genau der Fall aus der Beschwerde: waehrend die Feier laeuft, schiebt
    // sich ein Blatt darueber — so wie das Neuerungen-Blatt beim Home-Reiter.
    showDialog<void>(
      context: ctx,
      builder: (_) => const AlertDialog(content: Text('Blatt darueber')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Blatt darueber'), findsOneWidget);

    // Die Feier laeuft 3,65 Sekunden. Danach muss SIE weg sein — und das
    // fremde Blatt muss stehen bleiben.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(
      find.text('Blatt darueber'),
      findsOneWidget,
      reason:
          'Vorher schloss maybePop() genau dieses fremde Blatt statt der '
          'eigenen Feier. Das war der halbe Fehler.',
    );
    expect(
      find.text('Abzeichen freigeschaltet'),
      findsNothing,
      reason:
          'Und die Feier selbst blieb stehen. Das war die andere Haelfte — '
          'aus Sicht des Nutzers: es haengt.',
    );
  });

  testWidgets('zwei Feiern gleichzeitig legen sich nicht uebereinander',
      (tester) async {
    await tester.pumpWidget(
      _huelle((context) {
        // Zwei Aufrufe direkt hintereinander, so wie es passiert, wenn zwei
        // der sieben Aufrufstellen kurz nacheinander feuern.
        showBadgeUnlockPopup(context: context, badges: [_einAbzeichen()]);
        showBadgeUnlockPopup(context: context, badges: [_einAbzeichen()]);
      }),
    );

    await tester.tap(find.text('los'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Es darf immer nur EINE Feier gleichzeitig offen sein. Die zweite steht
    // in der Schlange und kommt danach.
    expect(
      find.byType(Dialog),
      findsNothing,
      reason: 'Die Feier ist kein Dialog, sondern eine eigene Route.',
    );

    // Nach der ersten Feier laeuft die zweite an und ist danach ebenfalls weg.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(
      find.text('Abzeichen freigeschaltet'),
      findsNothing,
      reason: 'Am Ende muss der Bildschirm frei sein, nicht halb verdeckt.',
    );
  });
}
