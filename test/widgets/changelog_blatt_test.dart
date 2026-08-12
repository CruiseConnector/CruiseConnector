import 'dart:io';

import 'package:cruise_connect/core/app_changelog.dart';
import 'package:cruise_connect/presentation/widgets/changelog_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-11 (vucko): „Bei jedem Update, das erste Mal nachdem ich es
/// installiert habe, soll ein Popup kommen mit allen neuen Sachen in einem
/// schoenen Layout — das fehlt auch komplett."
///
/// Es hat DREI unabhaengige Gruende gebraucht, bis das Blatt wirklich erschien.
/// Alle drei waren von aussen unsichtbar: Es passierte einfach nichts, ohne
/// Fehlermeldung, ohne Absturz.
///
///  1. Bei frischer Installation wurde der Hinweis unterdrueckt — womit auch
///     das erste Update, das die Funktion mitbrachte, wie eine Erstinstallation
///     aussah. (behoben am 2026-08-11, siehe changelog_service_test.dart)
///
///  2. Der Ausloeser hing ausschliesslich am ANTIPPEN des Home-Reiters. Beim
///     App-Start steht man aber schon auf Home und tippt ihn nie an.
///     (behoben am 2026-08-12, siehe release_hygiene_test.dart)
///
///  3. Der Hinweis wurde als gesehen vermerkt, BEVOR er angezeigt wurde. Kam
///     dazwischen irgendetwas — das Tutorial setzte den Reiter, das Widget war
///     im Umbau —, war er unwiderruflich verloren: vermerkt, nie gezeigt, bis
///     zur naechsten Version nicht mehr zu holen. Auf dem Samsung genau so
///     passiert und im Log nachgewiesen („laeuft=1.5.13 gesehen=1.5.13").
///
/// Diese Datei haelt Punkt 3 fest und prueft ausserdem, dass das Blatt
/// ueberhaupt rendert — was bis dahin nie jemand gesehen hatte.
void main() {
  final eintrag = AppChangelog.eintraege.first;

  testWidgets('das Blatt zeigt Titel und alle Punkte', (tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showChangelogSheet(context, eintrag),
              child: const Text('auf'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();

    expect(find.text(eintrag.titel), findsOneWidget);

    // Das Blatt scrollt, und was ausserhalb liegt, wird gar nicht erst
    // gebaut. Also zu jedem Punkt hinscrollen — das prueft nebenbei, dass
    // wirklich ALLE erreichbar sind und nicht der letzte unter dem Rand
    // verschwindet.
    final liste = find.byType(Scrollable).first;
    for (final punkt in eintrag.punkte) {
      await tester.scrollUntilVisible(
        find.text(punkt),
        120,
        scrollable: liste,
      );
      expect(
        find.text(punkt),
        findsOneWidget,
        reason: 'dieser Punkt ist im Blatt nicht erreichbar: $punkt',
      );
    }
  });

  test('gemerkt wird erst NACH dem Anzeigen', () {
    final quelle = File(
      'lib/presentation/pages/home_page.dart',
    ).readAsStringSync();

    final start = quelle.indexOf('Future<bool> _pruefeNeuerungen()');
    expect(start, greaterThan(0));
    final rumpf = quelle.substring(start, start + 2200);

    final zeigen = rumpf.indexOf('showChangelogSheet(');
    final merken = rumpf.indexOf('markiereGesehen(');
    expect(zeigen, greaterThan(0));
    expect(merken, greaterThan(0));
    expect(
      zeigen,
      lessThan(merken),
      reason:
          'Umgekehrt geht der Hinweis unwiderruflich verloren, sobald zwischen '
          'Merken und Anzeigen etwas dazwischenkommt — genau so ist er am '
          '2026-08-12 auf dem Samsung verschwunden. Gegen die Wiederkehr im '
          'selben Lauf schuetzt _neuerungenOffen, und wer wegwischt, hat es '
          'trotzdem gesehen: showChangelogSheet kehrt auch dann zurueck.',
    );
  });
}
