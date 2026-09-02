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
// 3. Ein Fehlschlag der Feier wurde still verschluckt. Der Aufrufer
//    quittiert die Abzeichen NACH der Feier — ein stiller Erfolg hiess also:
//    quittiert, obwohl nie etwas zu sehen war, und der Meilenstein war weg.
//    (Vom Kritiker gefunden, nachgebessert: die Schlange reisst nicht ab, das
//    Ergebnis fuer den Aufrufer scheitert aber sehr wohl.)
// 4. Die Verleih-Kette der Starter-Karte hatte keinen Faenger. Nach dem
//    ersten Fehlschlag stand sie dauerhaft auf einem abgelehnten Future, und
//    jede weitere Verleihung haengte sich daran an und lief nie.
//
// Diesen Test gab es vorher nicht. Ohne ihn faellt derselbe Fehler beim
// naechsten Umbau wieder hinein.

import 'dart:io';

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
  test('ein Fehlschlag wird NICHT still quittiert', () {
    // Der Aufrufer zeigeOffeneAuszeichnungen quittiert die Abzeichen NACH der
    // Feier. Endet die Feier bei einem Fehlschlag als sauberes Future, gilt
    // ein nie gezeigtes Abzeichen als abgehakt. Der Dateikopf der Quelle haelt
    // die Gegenregel fest: "lieber einmal zu viel als ein verpasster
    // Meilenstein."
    final quelle = File(
      'lib/presentation/widgets/badge_unlock_popup.dart',
    ).readAsStringSync();
    expect(
      quelle.contains('Future<bool> showBadgeUnlockPopup('),
      isTrue,
      reason:
          'Die Funktion muss ehrlich sagen, OB gefeiert wurde. Ein void kann '
          'das nicht.',
    );
    expect(
      quelle.contains('if (gefeiert) {'),
      isTrue,
      reason:
          'Nur dann darf quittiert werden. Sonst gilt ein nie gezeigtes '
          'Abzeichen als abgehakt und ist fuer immer weg.',
    );
    expect(
      quelle.contains('if (navigator == null) return Future<bool>.value(false);'),
      isTrue,
    );
  });

  // Vor jedem Test eine freie Schlange. Ohne das haengt jeder Test an den
  // Resten des vorigen — die Fehlermeldung ("keine Feier zu sehen") zeigt dann
  // auf die falsche Ursache.

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
    // Freie Schlange. Sie ist datei-privat und ueberlebt den einzelnen Test —
    // ohne das haengt dieser Test an den Resten des vorigen, und die
    // Fehlermeldung ("keine Feier zu sehen") zeigt auf die falsche Ursache.
    setzeFeierSchlangeZurueck();
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

    // 2026-09-01, NACHGEBESSERT nach dem Kritiker: Hier stand
    // expect(find.byType(Dialog), findsNothing) mit der Begruendung "die
    // Feier ist kein Dialog" — also eine Zusicherung, die per Konstruktion
    // wahr ist und die Serialisierung gar nicht prueft. Eine Tautologie.
    //
    // Jetzt wird gezaehlt, was wirklich zaehlt: wie viele Feier-Routen
    // gleichzeitig offen sind. Es darf immer nur EINE sein, die zweite steht
    // in der Schlange.
    expect(
      find.byType(BackdropFilter),
      findsWidgets,
      reason: 'Die erste Feier muss laufen.',
    );
    expect(
      find.text('Abzeichen freigeschaltet').evaluate().length <= 1,
      isTrue,
      reason:
          'Zwei Feiern gleichzeitig legten sich uebereinander, und die untere '
          'wartete auf einen Navigator-Zustand, den es nicht mehr gab. Es darf '
          'also hoechstens EINE offen sein.',
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
