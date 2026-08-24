import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/presentation/widgets/badge_uebersicht_panel.dart';

/// 2026-08-24 (vucko woertlich): „die stufen badges sollen noch besser
/// angezeigt werden man scrollt da endlos".
///
/// Der Katalog waechst (17 Familien und mehr). Dieser Test haelt fest, was die
/// Uebersicht dabei leisten muss:
///   - Die Hoehe des Abschnitts haengt an dem, was ANGEFANGEN ist, nicht an
///     der Groesse des Katalogs.
///   - Es geht nichts verloren: jede Familie liegt in genau einer Schublade
///     und ist mit einem Tipp erreichbar.
///   - Das Naechstliegende steht oben.
void main() {
  /// Eine Familie, die es sicher gibt — ohne den Katalog festzunageln, der
  /// gerade waechst.
  app.BadgeFamilie familieMit(bool Function(app.BadgeFamilie) pruefung) =>
      app.badgeFamilien.firstWhere(pruefung);

  group('Der Katalog liegt in Schubladen, nicht in einer Endlosliste', () {
    test('jede Familie liegt in genau einer Schublade', () {
      // Absichtlich mit einem gemischten Stand, damit alle drei Schubladen
      // besetzt sind.
      final erste = app.badgeFamilien.first;
      final zweite = app.badgeFamilien[1];
      final erreicht = <String>{
        ...erste.alleStufen.map((s) => s.id),
        zweite.alleStufen.first.id,
      };

      final gruppen = badgeFamilienGruppen(erreichteIds: erreicht);
      final verteilt = [for (final g in gruppen) ...g.familien];

      expect(
        verteilt.map((f) => f.schluessel).toSet(),
        app.badgeFamilien.map((f) => f.schluessel).toSet(),
        reason: 'Eine Familie ist beim Gruppieren verschwunden',
      );
      expect(
        verteilt.length,
        app.badgeFamilien.length,
        reason: 'Eine Familie steckt in zwei Schubladen',
      );
    });

    test('leere Schubladen fallen weg', () {
      final gruppen = badgeFamilienGruppen(erreichteIds: const {});
      expect(gruppen, hasLength(1));
      expect(gruppen.single.titel, badgeGruppeOffen);
      expect(gruppen.single.familien, hasLength(app.badgeFamilien.length));
    });

    test('angefangen, fertig und unberuehrt landen je woanders', () {
      final gestuft = familieMit(
        (f) => f.istGestuft && f.alleStufen.length > 1,
      );
      final andere = familieMit((f) => f.schluessel != gestuft.schluessel);

      final teilweise = badgeFamilienGruppen(
        erreichteIds: {gestuft.alleStufen.first.id},
      );
      expect(
        teilweise
            .firstWhere((g) => g.titel == badgeGruppeInArbeit)
            .familien
            .map((f) => f.schluessel),
        contains(gestuft.schluessel),
      );

      final ganz = badgeFamilienGruppen(
        erreichteIds: gestuft.alleStufen.map((s) => s.id).toSet(),
      );
      expect(
        ganz
            .firstWhere((g) => g.titel == badgeGruppeGeschafft)
            .familien
            .map((f) => f.schluessel),
        contains(gestuft.schluessel),
      );
      expect(
        ganz
            .firstWhere((g) => g.titel == badgeGruppeOffen)
            .familien
            .map((f) => f.schluessel),
        contains(andere.schluessel),
      );
    });

    test('eine fertige Stufe III mit offenem Meilenstein bleibt in Arbeit', () {
      // Sonst stuende die Familie unter „Geschafft" und tauchte unten bei
      // „Als Naechstes" trotzdem als Ziel auf.
      final distanz = familieMit((f) => f.schluessel == 'distanz');
      final ohneLetzten = distanz.alleStufen
          .map((s) => s.id)
          .toList()
          .sublist(0, distanz.alleStufen.length - 1)
          .toSet();

      final gruppen = badgeFamilienGruppen(erreichteIds: ohneLetzten);
      expect(
        gruppen
            .firstWhere((g) => g.titel == badgeGruppeInArbeit)
            .familien
            .map((f) => f.schluessel),
        contains('distanz'),
      );
      expect(
        badgeFamilieFertig(distanz, ohneLetzten),
        isFalse,
        reason: 'Es ist noch ein Abzeichen offen',
      );
    });

    test('in Arbeit steht das Naechstliegende oben', () {
      // 400 von 500 km schlaegt 2 von 3 Kurvenfahrten — dieselbe Rechnung wie
      // im Abschnitt „Als Naechstes", damit beide dasselbe sagen.
      final metriken = app.badgeMetriken(totalKm: 400, kurvenjagdFahrten: 2);
      final distanz = familieMit((f) => f.schluessel == 'distanz');
      final kurven = familieMit((f) => f.schluessel == 'kurven');
      final erreicht = <String>{
        distanz.alleStufen.first.id,
        kurven.alleStufen.first.id,
      };

      final inArbeit = badgeFamilienGruppen(
        erreichteIds: erreicht,
        metriken: metriken,
      ).firstWhere((g) => g.titel == badgeGruppeInArbeit).familien;

      final platzDistanz = inArbeit.indexWhere(
        (f) => f.schluessel == 'distanz',
      );
      final platzKurven = inArbeit.indexWhere((f) => f.schluessel == 'kurven');
      expect(platzDistanz, greaterThanOrEqualTo(0));
      expect(platzKurven, greaterThan(platzDistanz));
    });
  });

  group('Die Uebersicht scrollt nicht mehr endlos', () {
    /// Die Kacheln im Raster tragen die (gekuerzten) Familiennamen. Ihre Zahl
    /// ist das Mass fuer die Hoehe des Abschnitts.
    int sichtbareFamilien(WidgetTester tester) {
      final namen = app.badgeFamilien
          .map((f) => badgeKurzTitel(f.titel))
          .toSet();
      return tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => namen.contains(t.data))
          .length;
    }

    Future<void> zeige(
      WidgetTester tester, {
      required Set<String> erreicht,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xFF0B0E14),
            body: SingleChildScrollView(
              child: SizedBox(
                width: 380,
                child: BadgeUebersichtPanel(
                  erreichteIds: erreicht,
                  metriken: app.badgeMetriken(totalKm: 400),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('ohne Fortschritt bleibt der Katalog zugeklappt', (
      tester,
    ) async {
      await zeige(tester, erreicht: const {});
      expect(
        sichtbareFamilien(tester),
        0,
        reason:
            'Siebzehn Kacheln am Stueck sind genau das, was Vucko gestoert hat',
      );
      // Zu sehen ist die Schublade selbst — mit ihrer Anzahl.
      expect(find.text(badgeGruppeOffen), findsOneWidget);
      expect(find.text('${app.badgeFamilien.length}'), findsOneWidget);
    });

    testWidgets('ein Tipp holt alles wieder hervor', (tester) async {
      await zeige(tester, erreicht: const {});
      await tester.tap(find.text(badgeGruppeOffen));
      await tester.pumpAndSettle();
      expect(
        sichtbareFamilien(tester),
        app.badgeFamilien.length,
        reason: 'Wer alles sehen will, muss alles erreichen koennen',
      );
    });

    testWidgets('offen ist, was angefangen ist — nicht der ganze Katalog', (
      tester,
    ) async {
      final distanz = app.badgeFamilien.firstWhere(
        (f) => f.schluessel == 'distanz',
      );
      await zeige(tester, erreicht: {distanz.alleStufen.first.id});

      expect(find.text(badgeGruppeInArbeit), findsOneWidget);
      expect(find.text(badgeGruppeOffen), findsOneWidget);
      final sichtbar = sichtbareFamilien(tester);
      expect(sichtbar, greaterThan(0));
      expect(
        sichtbar,
        lessThan(app.badgeFamilien.length),
        reason: 'Die zugeklappten Schubladen duerfen nicht mitrendern',
      );
    });
  });
}
