import 'dart:async';
import 'dart:io';

import 'package:cruise_connect/presentation/pages/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// REGRESSION 24.08.2026 — „Gruppe verlassen" war dieselbe Sackgasse.
///
/// Der Dialog lief mit `barrierDismissible: false`, und BEIDE Knoepfe waren
/// mit `_busy ? null` gesperrt — auch „Abbrechen". Dahinter lief
/// `SocialService.deleteGroup` bzw. `leaveGroup` OHNE Zeitgrenze. Antwortet
/// Supabase nicht (Funkloch, Tunnel, DNS haengt), bleibt `_busy` fuer immer
/// auf true: kein Abbrechen, kein Bestaetigen, auf iOS auch keine
/// Zurueck-Geste. Die Profilseite war tot.
///
/// Die Regeln, die diese Datei festhaelt:
///  1. „Abbrechen" ist NIE gesperrt. Es braucht kein Netz und nichts vom
///     System.
///  2. Jeder Netz-Aufruf hat eine Zeitgrenze mit ehrlicher Meldung.
///  3. Der Nutzer erfaehrt, dass eine abgebrochene Anfrage trotzdem
///     angekommen sein kann — und die Liste wird danach neu geladen.
void main() {
  /// Oeffnet den Dialog wie die Profilseite und haelt fest, womit er endet.
  Future<_Ergebnis> dialogOeffnen(
    WidgetTester tester, {
    required Future<void> Function() onConfirm,
    bool willDelete = false,
    bool iAmOwner = false,
  }) async {
    final ergebnis = _Ergebnis();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  ergebnis.wert = await showDialog<LeaveGroupErgebnis>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => LeaveGroupDialog(
                      willDelete: willDelete,
                      iAmOwner: iAmOwner,
                      onConfirm: onConfirm,
                    ),
                  );
                  ergebnis.fertig = true;
                },
                child: const Text('Dialog öffnen'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Dialog öffnen'));
    await tester.pumpAndSettle();
    return ergebnis;
  }

  bool knopfBedienbar(WidgetTester tester, String text) {
    final knopf = find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(knopf, findsOneWidget, reason: 'Knopf „$text" fehlt');
    return tester.widget<ButtonStyleButton>(knopf).onPressed != null;
  }

  /// Laesst eine noch laufende Zeitgrenze auslaufen. Der Test-Rahmen meckert
  /// sonst ueber einen offenen Timer — und ganz nebenbei beweist das, dass
  /// nach dem Schliessen nichts mehr schiefgeht.
  Future<void> zeitgrenzeAuslaufenLassen(WidgetTester tester) async {
    await tester.pump(
      LeaveGroupDialog.netzZeitgrenze + const Duration(seconds: 1),
    );
    expect(tester.takeException(), isNull);
  }

  group('Abbrechen ist nie gesperrt', () {
    testWidgets(
      'REPRO 24.08.: Waehrend der Anfrage bleibt „Abbrechen" bedienbar',
      (tester) async {
        // Der Aufruf antwortet nie — Funkloch mitten im Verlassen.
        await dialogOeffnen(tester, onConfirm: () => Completer<void>().future);

        expect(knopfBedienbar(tester, 'Abbrechen'), isTrue);
        await tester.tap(find.text('Verlassen'));
        await tester.pump();

        expect(
          knopfBedienbar(tester, 'Abbrechen'),
          isTrue,
          reason:
              'Frueher war „Abbrechen" mit `_busy ? null` gesperrt. Antwortet '
              'das Backend nicht, gab es auf iOS keinen Ausweg mehr.',
        );
        await zeitgrenzeAuslaufenLassen(tester);
      },
    );

    testWidgets('Abbrechen waehrend der Anfrage schliesst den Dialog', (
      tester,
    ) async {
      await dialogOeffnen(tester, onConfirm: () => Completer<void>().future);
      await tester.tap(find.text('Verlassen'));
      await tester.pump();

      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      expect(find.byType(LeaveGroupDialog), findsNothing);
      await zeitgrenzeAuslaufenLassen(tester);
    });

    testWidgets(
      'Auch die Loesch-Variante (letzter Admin) laesst „Abbrechen" offen',
      (tester) async {
        await dialogOeffnen(
          tester,
          willDelete: true,
          iAmOwner: true,
          onConfirm: () => Completer<void>().future,
        );
        expect(find.text('Gruppe löschen?'), findsOneWidget);

        await tester.tap(find.text('Gruppe löschen'));
        await tester.pump();

        expect(knopfBedienbar(tester, 'Abbrechen'), isTrue);
        await zeitgrenzeAuslaufenLassen(tester);
      },
    );
  });

  group('Zeitgrenze auf dem Netz-Aufruf', () {
    testWidgets('REPRO 24.08.: Ein haengender Aufruf endet mit einer '
        'ehrlichen Meldung', (tester) async {
      await dialogOeffnen(tester, onConfirm: () => Completer<void>().future);
      await tester.tap(find.text('Verlassen'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Zeitgrenze abwarten.
      await tester.pump(LeaveGroupDialog.netzZeitgrenze);
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'Ohne Zeitgrenze dreht sich der Kringel bis zum App-Neustart.',
      );
      expect(
        find.textContaining('zu lange'),
        findsOneWidget,
        reason: 'Der Nutzer muss erfahren, warum nichts weitergeht.',
      );
      // Der Nutzer muss wissen, ob er raus ist oder nicht.
      expect(
        find.textContaining('trotzdem angekommen'),
        findsOneWidget,
        reason:
            'Eine abgebrochene Anfrage kann durchgelaufen sein. Das darf man '
            'dem Nutzer nicht verschweigen.',
      );
      // Und er kann es erneut versuchen.
      expect(knopfBedienbar(tester, 'Verlassen'), isTrue);
      expect(knopfBedienbar(tester, 'Abbrechen'), isTrue);
    });

    testWidgets('Ein Fehler nennt den Grund und laesst den Dialog bedienbar', (
      tester,
    ) async {
      await dialogOeffnen(
        tester,
        onConfirm: () async => throw StateError('kaputt'),
      );
      await tester.tap(find.text('Verlassen'));
      await tester.pumpAndSettle();

      expect(find.textContaining('fehlgeschlagen'), findsOneWidget);
      expect(knopfBedienbar(tester, 'Verlassen'), isTrue);
      expect(knopfBedienbar(tester, 'Abbrechen'), isTrue);
    });
  });

  group('Was der Aufrufer erfaehrt', () {
    testWidgets('Erfolg meldet „erledigt"', (tester) async {
      final ergebnis = await dialogOeffnen(tester, onConfirm: () async {});
      await tester.tap(find.text('Verlassen'));
      await tester.pumpAndSettle();

      expect(ergebnis.fertig, isTrue);
      expect(ergebnis.wert, LeaveGroupErgebnis.erledigt);
    });

    testWidgets(
      'Abbrechen OHNE laufende Anfrage meldet „abgebrochen" — kein Neuladen',
      (tester) async {
        final ergebnis = await dialogOeffnen(tester, onConfirm: () async {});
        await tester.tap(find.text('Abbrechen'));
        await tester.pumpAndSettle();

        expect(ergebnis.wert, LeaveGroupErgebnis.abgebrochen);
      },
    );

    testWidgets(
      'Abbrechen WAEHREND einer Anfrage meldet „unklar" — die Liste muss neu',
      (tester) async {
        final ergebnis = await dialogOeffnen(
          tester,
          onConfirm: () => Completer<void>().future,
        );
        await tester.tap(find.text('Verlassen'));
        await tester.pump();
        await tester.tap(find.text('Abbrechen'));
        await tester.pumpAndSettle();

        expect(
          ergebnis.wert,
          LeaveGroupErgebnis.unklar,
          reason:
              'Die Anfrage lief noch. Ob sie angekommen ist, weiss niemand — '
              'also muss die Profilseite die Gruppenliste neu laden.',
        );
        await zeitgrenzeAuslaufenLassen(tester);
      },
    );

    testWidgets('Nach der Zeitgrenze und danach Abbrechen: „unklar"', (
      tester,
    ) async {
      final ergebnis = await dialogOeffnen(
        tester,
        onConfirm: () => Completer<void>().future,
      );
      await tester.tap(find.text('Verlassen'));
      await tester.pump();
      await tester.pump(LeaveGroupDialog.netzZeitgrenze);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      expect(ergebnis.wert, LeaveGroupErgebnis.unklar);
    });
  });

  group('Quelltext-Waechter', () {
    test('Kein Bedienelement des Dialogs haengt an `_busy`, ausser dem '
        'Bestaetigen-Knopf', () {
      // Absicht: `_busy ? null` darf nie wieder an „Abbrechen" landen.
      // Der Verhaltenstest oben prueft das Ergebnis; dieser hier faengt die
      // Bauart ab, bevor sie sich in andere Dialoge kopiert.
      final quelle = _dialogQuelle();
      final stelle = quelle.indexOf("const Text('Abbrechen'");
      expect(stelle, greaterThan(-1), reason: 'Abbrechen-Knopf umbenannt?');
      final davor = quelle.substring((stelle - 300).clamp(0, stelle), stelle);
      expect(
        RegExp(r'_busy\s*\?').hasMatch(davor),
        isFalse,
        reason:
            '„Abbrechen" braucht kein Netz. Es darf nie gesperrt sein — sonst '
            'gibt es bei einer haengenden Anfrage keinen Ausweg.\n'
            'Gefunden:\n$davor',
      );
    });
  });
}

/// Haelt fest, womit der Dialog geendet ist.
class _Ergebnis {
  LeaveGroupErgebnis? wert;
  bool fertig = false;
}

String _dialogQuelle() {
  final quelle = File(
    'lib/presentation/pages/profile_page.dart',
  ).readAsStringSync();
  final start = quelle.indexOf('class LeaveGroupDialog extends StatefulWidget');
  expect(start, greaterThan(-1), reason: 'Dialog umbenannt?');
  final ende = quelle.indexOf('class _ProfileSkeleton', start);
  return quelle.substring(start, ende);
}
