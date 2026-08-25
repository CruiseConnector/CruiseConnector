import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/presentation/pages/analytics_page.dart';
import 'package:cruise_connect/presentation/widgets/badge_uebersicht_panel.dart';

/// 2026-08-25 (vucko woertlich): „das man die badges besser darstellen kann
/// nicht untereinander sondern schon nebeneinander und das es noch besser
/// aussieht das mit dem aufklappen passt aber das es noch etwas schoener
/// aussieht".
///
/// GEMESSEN, warum sie untereinander standen: Der Katalog rechnete seine
/// Kachelbreite aus der AUSSENbreite der Liste — bei 390 Punkten zwei Kacheln
/// zu je 191. Gezeichnet wurden sie aber INNERHALB der Schublade, die nach
/// Rand und Innenabstand nur noch 370 Punkte breit ist. 191 + 8 + 191 = 390
/// passt nicht in 370, also brach das `Wrap` nach JEDER Kachel um. Auf dem
/// Telefon stand damit genau eine Kachel je Reihe.
///
/// Dieser Test haelt drei Dinge fest:
///   1. Es stehen mehrere Kacheln nebeneinander.
///   2. Eine Reihe fuellt die Schublade von Kante zu Kante — kein Rest, in
///      den noch eine weitere Kachel gepasst haette.
///   3. Beide Raster der Seite (Uebersicht oben, Katalog unten) rechnen mit
///      derselben Regel, damit sie dieselbe Kante haben.
void main() {
  /// Ein uebliches Telefon (iPhone 13/14) und das schmalste, das noch
  /// bedient wird.
  const breiten = <double>[320, 390, 430];

  /// Die Kachel in Originalgroesse, aber ohne Bilder — gemessen wird die
  /// Geometrie, nicht die Grafik. Die Masse kommen wie in der Seite von
  /// aussen.
  Widget kachel(app.Badge badge, BadgeKachelMasse masse) => Container(
    alignment: Alignment.center,
    child: Text(badge.id, maxLines: 1, overflow: TextOverflow.ellipsis),
  );

  Future<void> baue(
    WidgetTester tester,
    double breite, {
    Set<String> erreichteIds = const {},
    Map<app.BadgeMetrik, double>? metriken,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0B0E14),
          body: SingleChildScrollView(
            child: SizedBox(
              width: breite,
              child: BadgeKatalogListe(
                erreichteIds: erreichteIds,
                metriken: metriken,
                kachelBauer: kachel,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Die sichtbaren Kacheln, nach Reihen gebuendelt.
  List<List<Rect>> reihen(WidgetTester tester) {
    final rechtecke = <Rect>[];
    for (final badge in app.Badge.all) {
      final text = find.text(badge.id, skipOffstage: false);
      if (text.evaluate().isEmpty) continue;
      final kachel = find.ancestor(
        of: text,
        matching: find.byType(GestureDetector, skipOffstage: false),
      );
      rechtecke.add(tester.getRect(kachel.first));
    }
    rechtecke.sort((a, b) {
      final v = a.top.compareTo(b.top);
      return v != 0 ? v : a.left.compareTo(b.left);
    });
    final gebuendelt = <List<Rect>>[];
    for (final r in rechtecke) {
      if (gebuendelt.isEmpty ||
          (r.top - gebuendelt.last.first.top).abs() > 1.0) {
        gebuendelt.add([r]);
      } else {
        gebuendelt.last.add(r);
      }
    }
    return gebuendelt;
  }

  group('Die Abzeichen stehen nebeneinander', () {
    for (final breite in breiten) {
      testWidgets('bei $breite Punkten sind es mindestens drei je Reihe', (
        tester,
      ) async {
        await baue(tester, breite);
        final gebuendelt = reihen(tester);
        expect(gebuendelt, isNotEmpty, reason: 'Keine Kachel sichtbar');

        final proReihe = gebuendelt.map((r) => r.length).toList();
        // ignore: avoid_print
        print(
          'Katalog bei $breite Punkten: Kacheln je Reihe $proReihe, '
          'Kachel ${gebuendelt.first.first.width.toStringAsFixed(1)} x '
          '${gebuendelt.first.first.height.toStringAsFixed(1)}',
        );

        // Die letzte Reihe darf angebrochen sein, jede andere nicht.
        final volleReihen = gebuendelt.length == 1
            ? proReihe
            : proReihe.sublist(0, gebuendelt.length - 1);
        for (final anzahl in volleReihen) {
          expect(
            anzahl,
            greaterThanOrEqualTo(3),
            reason:
                'Bei $breite Punkten steht wieder fast alles untereinander — '
                'genau das war Vuckos Beschwerde',
          );
        }
      });

      testWidgets('bei $breite Punkten fuellt eine Reihe die Schublade', (
        tester,
      ) async {
        await baue(tester, breite);
        final gebuendelt = reihen(tester);
        final liste = tester.getRect(find.byType(BadgeKatalogListe));

        // Der Innenabstand der Schublade ist links und rechts gleich, also
        // laesst sich die nutzbare Breite aus der ersten Kachel ableiten.
        final innenLinks = gebuendelt.first.first.left;
        final nutzbar = liste.width - 2 * (innenLinks - liste.left);

        final volleReihe = gebuendelt.firstWhere(
          (r) => r.length == gebuendelt.map((x) => x.length).reduce(
            (a, b) => a > b ? a : b,
          ),
        );
        final belegt =
            volleReihe.length * volleReihe.first.width +
            (volleReihe.length - 1) * badgeRasterLuecke;
        expect(
          belegt,
          closeTo(nutzbar, 1.0),
          reason:
              'Die Reihe laesst rechts Platz, in den noch eine Kachel passt — '
              'die Kachelbreite ist wieder aus der falschen Breite gerechnet',
        );
      });
    }

    testWidgets('alle Kacheln der Seite haben dieselbe Groesse', (
      tester,
    ) async {
      await baue(tester, 390);
      await tester.tap(find.text('Alle aufklappen'));
      await tester.pumpAndSettle();
      final alle = reihen(tester).expand((r) => r).toList();
      expect(alle, hasLength(app.Badge.all.length));
      for (final r in alle) {
        expect(r.width, closeTo(alle.first.width, 0.01));
        expect(r.height, closeTo(alle.first.height, 0.01));
      }
    });
  });

  group('Die Seite wird dadurch kuerzer, nicht laenger', () {
    testWidgets('zugeklappt und aufgeklappt bleiben unter dem alten Stand', (
      tester,
    ) async {
      await baue(tester, 390);
      final zugeklappt = tester
          .getSize(find.byType(BadgeKatalogListe))
          .height;
      await tester.tap(find.text('Alle aufklappen'));
      await tester.pumpAndSettle();
      final offen = tester.getSize(find.byType(BadgeKatalogListe)).height;

      // ignore: avoid_print
      print(
        'Katalog bei 390 Punkten: zugeklappt ${zugeklappt.round()} Punkte '
        '(vorher 1792), aufgeklappt ${offen.round()} Punkte (vorher 11532).',
      );

      // Die gemessenen Werte VOR dem Umbau. Beide muessen sinken, weil aus
      // einer Kachel je Reihe drei geworden sind.
      expect(zugeklappt, lessThan(1792));
      expect(offen, lessThan(11532 / 2));
    });
  });

  group('Beide Raster der Seite folgen derselben Regel', () {
    test('die Spaltenzahl haengt nur an der nutzbaren Breite', () {
      expect(badgeRasterSpalten(250), 2);
      expect(badgeRasterSpalten(276), 3, reason: 'Panel auf 320er Geraet');
      expect(badgeRasterSpalten(300), 3, reason: 'Katalog auf 320er Geraet');
      expect(badgeRasterSpalten(370), 3, reason: 'Katalog auf 390er Geraet');
      expect(badgeRasterSpalten(440), 4);
      expect(badgeRasterSpalten(600), 5);
    });

    testWidgets('Uebersicht und Katalog haben dieselbe Kachelzahl je Reihe', (
      tester,
    ) async {
      // Die Uebersicht steht in einem Kasten mit 13 Punkten Innenabstand,
      // ihre Schubladen in einem mit 8 — der Katalog in einem mit 9. Bei
      // 390 Punkten Geraetebreite kommen beide auf drei Spalten.
      const geraet = 390.0;
      expect(badgeRasterSpalten(geraet - 2 * 13 - 2 * 1 - 2 * 8), 3);
      expect(
        badgeRasterSpalten(geraet - BadgeKatalogListe.schubladeChrom),
        3,
      );

      await baue(tester, geraet);
      final proReihe = reihen(tester).map((r) => r.length).toList();
      expect(proReihe.first, 3);
    });
  });

  group('Auch auf dem schmalsten Telefon bleibt alles lesbar', () {
    testWidgets('bei 320 Punkten laeuft nichts ueber', (tester) async {
      await baue(
        tester,
        320,
        metriken: const {app.BadgeMetrik.gesamtKm: 400},
      );
      expect(tester.takeException(), isNull);
      final erste = reihen(tester).first.first;
      // Unter rund 85 Punkten bleibt von einem zweizeiligen Namen nichts
      // Lesbares uebrig — siehe [badgeRasterSpalten].
      expect(erste.width, greaterThanOrEqualTo(85));
    });

    test('die Kachelmasse folgen der Breite', () {
      final schmal = badgeKachelMasse(95);
      final breit = badgeKachelMasse(131);
      expect(schmal.emblem, lessThan(breit.emblem));
      expect(schmal.namenGroesse, lessThanOrEqualTo(breit.namenGroesse));
      expect(schmal.hoehe, lessThan(breit.hoehe));
      // Die Hoehe muss den Rand des Kastens mittragen, sonst meldet Flutter
      // einen Ueberlauf von genau zwei Punkten.
      expect(
        breit.hoehe,
        closeTo(
          breit.emblem + breit.namenHoehe + 2 * badgeKachelRand + 61,
          0.01,
        ),
      );
    });
  });
}
