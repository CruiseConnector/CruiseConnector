// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/presentation/pages/route_share_page.dart';

/// 2026-07-28 (vucko „Bild-Export: das Layout passt gar nicht"):
///
/// Rendert die Share-Karte in den Formaten, in denen sie kaputt aussah, und
/// legt PNGs zum Anschauen ab. Zusätzlich harte Zusicherungen gegen die
/// beiden konkreten Fehler aus den Screenshots:
///   1. Titel brach MITTEN IM WORT um („Kurvenreic / her Donn…").
///   2. Kennzahlen liefen über oder brachen um.
void main() {
  const accent = Color(0xFFFF4438);

  RouteShareData daten(String titel, {String? dauer}) => RouteShareData(
    title: titel,
    subtitle: 'Kurvenjagd',
    distanceLabel: '26,7 km',
    durationLabel: dauer ?? '35 min',
    curvesLabel: '92 Kurven',
    segments: const [
      [
        Offset(9.74, 47.41),
        Offset(9.70, 47.45),
        Offset(9.65, 47.46),
        Offset(9.62, 47.43),
        Offset(9.68, 47.40),
        Offset(9.74, 47.41),
      ],
    ],
  );

  /// Liest die tatsaechlich gerenderte Schriftgroesse des Titels aus.
  /// Damit ist messbar, ob der Einpasser gearbeitet hat — statt Pixel zu deuten.
  double titelGroesse(WidgetTester tester, String titel) {
    final t = tester.widget<Text>(
      find.descendant(
        of: find.byType(RouteShareCard),
        matching: find.text(titel),
      ),
    );
    return t.style!.fontSize!;
  }

  Future<void> ablegen(WidgetTester tester, String name) async {
    await expectLater(
      find.byType(RouteShareCard),
      matchesGoldenFile('goldens/share_card_$name.png'),
    );
  }

  Widget rahmen(double breite, RouteShareData d) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF10141B),
      body: Center(
        child: SizedBox(
          width: breite,
          child: RouteShareCard(data: d, accent: accent),
        ),
      ),
    ),
  );

  testWidgets('Sticker-Breite: langer Titel bricht nicht im Wort', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Genau der Titel aus Vuckos Screenshot, der „Kurvenreic / her Donn…"
    // ergab — im schmalsten Format (Sticker).
    await tester.pumpWidget(
      rahmen(300, daten('Kurvenreicher Donnerstagabend')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'kein Overflow');

    // Der Titel MUSS vollstaendig im Baum stehen (nicht durch einen anderen
    // Text ersetzt) und die Schrift muss verkleinert worden sein — sonst
    // haette Flutter wieder mitten im Wort getrennt.
    final g = titelGroesse(tester, 'Kurvenreicher Donnerstagabend');
    expect(g, lessThan(22.0),
        reason: 'Bei diesem langen Titel muss der Einpasser verkleinern');
    expect(g, greaterThanOrEqualTo(13.0),
        reason: 'aber nicht unter die Lesbarkeitsgrenze');
    await ablegen(tester, 'sticker_langer_titel');
  });

  testWidgets('breite Karte: normaler Titel', (tester) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(rahmen(420, daten('Kurviger Sonntagabend')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Auf breiter Karte passt ein normaler Titel in voller Groesse — es darf
    // NICHT vorsorglich verkleinert werden.
    expect(titelGroesse(tester, 'Kurviger Sonntagabend'), 22.0);
    await ablegen(tester, 'breit_normal');
  });

  testWidgets('Markenname wird verkleinert, NIE abgeschnitten', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Schmalstes realistisches Format. Vorher stand hier „CRUISE CONN…".
    await tester.pumpWidget(rahmen(260, daten('Kurviger Sonntagabend')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final marke = tester.widget<Text>(
      find.descendant(
        of: find.byType(RouteShareCard),
        matching: find.text('CRUISE CONNECTOR'),
      ),
    );
    expect(
      marke.overflow,
      isNot(TextOverflow.ellipsis),
      reason: 'Der eigene Markenname darf nie mit „…" enden',
    );
    expect(
      find.descendant(
        of: find.byType(RouteShareCard),
        matching: find.byType(FittedBox),
      ),
      findsWidgets,
      reason: 'Statt abzuschneiden muss verkleinert werden',
    );
  });

  testWidgets('extrem langes Einzelwort läuft nicht über', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      rahmen(280, daten('Donaudampfschifffahrtsgesellschaftskapitaensrunde')),
    );
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'Ein Wort, das breiter als jede Zeile ist, darf die Karte nicht '
          'sprengen — es wird gekürzt, nicht überlaufen gelassen',
    );
    // Selbst hier bleibt die Schrift lesbar (Untergrenze), statt beliebig
    // klein zu werden.
    expect(
      titelGroesse(tester, 'Donaudampfschifffahrtsgesellschaftskapitaensrunde'),
      13.0,
    );
    await ablegen(tester, 'extremwort');
  });
}
