import 'dart:typed_data';

import 'package:cruise_connect/presentation/widgets/cruise/cruise_completion_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-11 (vucko): „vorallem moechte ich, dass die Leute eher sehen, dass
/// es auch das Gruppenfeature oder das Community-Feature gibt."
///
/// Nach der Fahrt erscheinen zwei leise Vorschlaege. Diese Tests halten fest,
/// dass sie (a) nur bei Solo-Fahrten auftauchen, (b) die richtigen Wege
/// ausloesen und (c) den bestehenden Ablauf nicht stoeren.
void main() {
  void setSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Future<void> pump(
    WidgetTester tester, {
    required bool folgeVorschlaege,
    void Function(int?, List<String>, String?, Uint8List?, bool)? onSave,
    VoidCallback? onGruppeErstellen,
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
            folgeVorschlaege: folgeVorschlaege,
            onGruppeErstellen: onGruppeErstellen,
            onSave: onSave ?? (r, t, ti, p, pub) {},
            onDiscard: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Solo-Fahrt: beide Vorschlaege sind da', (tester) async {
    setSurface(tester, const Size(430, 1200));
    await pump(tester, folgeVorschlaege: true);

    expect(find.text('Nächstes Mal zu zweit'), findsOneWidget);
    expect(find.text('In die Community'), findsOneWidget);
  });

  // Der wichtigste Test: In der Gruppe geht es nach der Fahrt zurueck in die
  // Lobby. Ein Weiterleiten wuerde diesen Ablauf zerreissen.
  testWidgets('Gruppenfahrt: keine Vorschlaege', (tester) async {
    setSurface(tester, const Size(430, 1200));
    await pump(tester, folgeVorschlaege: false);

    expect(find.text('Nächstes Mal zu zweit'), findsNothing);
    expect(find.text('In die Community'), findsNothing);
  });

  testWidgets('„In die Community" speichert MIT Veroeffentlichen-Wunsch', (
    tester,
  ) async {
    setSurface(tester, const Size(430, 1200));
    bool? veroeffentlichen;
    await pump(
      tester,
      folgeVorschlaege: true,
      onSave: (r, t, ti, p, pub) => veroeffentlichen = pub,
    );

    await tester.tap(find.text('In die Community'));
    await tester.pump();

    expect(
      veroeffentlichen,
      isTrue,
      reason: 'sonst landet die Fahrt nie im Post-Editor',
    );
  });

  testWidgets('„Naechstes Mal zu zweit" speichert UND fuehrt weiter', (
    tester,
  ) async {
    setSurface(tester, const Size(430, 1200));
    var gespeichert = false;
    bool? veroeffentlichen;
    var weitergeleitet = false;

    await pump(
      tester,
      folgeVorschlaege: true,
      onSave: (r, t, ti, p, pub) {
        gespeichert = true;
        veroeffentlichen = pub;
      },
      onGruppeErstellen: () => weitergeleitet = true,
    );

    await tester.tap(find.text('Nächstes Mal zu zweit'));
    await tester.pump();

    expect(gespeichert, isTrue, reason: 'die Fahrt darf nicht verloren gehen');
    expect(
      veroeffentlichen,
      isFalse,
      reason: 'wer eine Gruppe will, will nicht gleichzeitig veroeffentlichen',
    );
    expect(weitergeleitet, isTrue);
  });

  testWidgets('ein zweiter Tap loest nichts erneut aus', (tester) async {
    setSurface(tester, const Size(430, 1200));
    var speicherAufrufe = 0;
    await pump(
      tester,
      folgeVorschlaege: true,
      onSave: (r, t, ti, p, pub) => speicherAufrufe++,
    );

    await tester.tap(find.text('In die Community'));
    await tester.pump();
    // Nach dem ersten Tap ist der Dialog abgeschickt; ein zweiter Druck darf
    // die Fahrt nicht doppelt speichern.
    final nochDa = find.text('In die Community');
    if (nochDa.evaluate().isNotEmpty) {
      await tester.tap(nochDa);
      await tester.pump();
    }
    expect(speicherAufrufe, 1);
  });
}
