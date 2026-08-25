import 'dart:io';

import 'package:cruise_connect/domain/models/badge.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-18 (Aufgabe 4.2, vucko Sprachnachricht 09 vom 16.08.):
/// „Mehrstufige Badges, das heisst, Kurvenkoenig gibt es drei Stufen, und von
/// den anderen Badges auch. Das auch noch einfuehren."
///
/// DREI Stufen je Familie ist die Vorgabe, nicht fuenf. Bestehende IDs und
/// ihre Schwellwerte wurden dabei NIE geaendert, nur gruppiert; jede neue
/// Stufe ist eine neue, zweistellige ID. Dadurch braucht es keine
/// Datenmigration: `profiles.badges` bleibt zeichengleich gueltig.
void main() {
  /// Muster der Datenbank (Migration 20260818230000). Wer es verletzt, dessen
  /// Badge wird beim Speichern still verworfen.
  final dbMuster = RegExp(r'^badge_[0-9]{2}$');

  group('Aufbau der Familien', () {
    test('jede gestufte Familie hat GENAU drei Stufen', () {
      for (final familie in badgeFamilien) {
        if (!familie.istGestuft) continue;
        expect(
          familie.stufen,
          hasLength(3),
          reason:
              'Familie ${familie.schluessel} hat ${familie.stufen.length} '
              'Stufen. Vuckos Vorgabe sind drei.',
        );
      }
    });

    test('die bewusst stufenlosen Familien sind namentlich bekannt', () {
      final stufenlos = badgeFamilien
          .where((f) => !f.istGestuft)
          .map((f) => f.schluessel)
          .toList();
      // 'stile' = vier von vier Stilen, darueber gibt es nichts.
      expect(stufenlos, ['stile']);
    });

    test('Schwellwerte steigen streng monoton', () {
      for (final familie in badgeFamilien) {
        for (var i = 1; i < familie.stufen.length; i++) {
          expect(
            familie.stufen[i].schwelle,
            greaterThan(familie.stufen[i - 1].schwelle),
            reason:
                'Familie ${familie.schluessel}: Stufe ${i + 1} '
                '(${familie.stufen[i].id}) ist nicht groesser als die davor',
          );
        }
      }
    });

    test('jede Stufen-ID ist zweistellig und existiert im Katalog', () {
      for (final familie in badgeFamilien) {
        for (final stufe in familie.alleStufen) {
          expect(
            dbMuster.hasMatch(stufe.id),
            isTrue,
            reason: '${stufe.id} wuerde die Datenbank still verwerfen',
          );
          expect(
            Badge.getById(stufe.id),
            isNotNull,
            reason: '${stufe.id} steht in der Tabelle, aber nicht in Badge.all',
          );
        }
      }
    });

    test('keine ID doppelt, weder im Katalog noch in der Tabelle', () {
      final katalog = Badge.all.map((b) => b.id).toList();
      expect(katalog.length, katalog.toSet().length);

      final tabelle = <String>[
        for (final familie in badgeFamilien)
          for (final stufe in familie.alleStufen) stufe.id,
      ];
      expect(
        tabelle.length,
        tabelle.toSet().length,
        reason: 'Ein Badge darf nur EINE Bedingung haben',
      );
    });

    test('Familien-Schluessel sind eindeutig', () {
      final schluessel = badgeFamilien.map((f) => f.schluessel).toList();
      expect(schluessel.length, schluessel.toSet().length);
    });
  });

  group('Katalog und Tabelle stimmen ueberein', () {
    test('Badge.familie und Badge.stufe passen zur Tabelle', () {
      for (final familie in badgeFamilien) {
        for (var i = 0; i < familie.stufen.length; i++) {
          final badge = Badge.getById(familie.stufen[i].id)!;
          expect(badge.familie, familie.schluessel, reason: badge.id);
          expect(
            badge.stufe,
            i + 1,
            reason: '${badge.id} muss Stufe ${i + 1} sein',
          );
        }
        for (final stufe in familie.ohneStufe) {
          final badge = Badge.getById(stufe.id)!;
          expect(badge.familie, familie.schluessel, reason: badge.id);
          expect(
            badge.stufe,
            0,
            reason: '${badge.id} ist ein Meilenstein ohne Rangfolge',
          );
        }
      }
    });

    test('jedes Badge mit Familie steht auch in der Tabelle', () {
      for (final badge in Badge.all) {
        if (badge.familie == null) continue;
        expect(
          badgeBedingungFuer(badge.id),
          isNotNull,
          reason: '${badge.id} hat eine Familie, aber keine Schwelle',
        );
      }
    });

    // 2026-08-24 (Aufgabe 10a, vucko): „dass community ein enzelnes badge
    // bekommen [...] aber nur eins". Das Community-Abzeichen ist bewusst der
    // dritte stufenlose: Es gibt kein „zwei Communities" und kein „zehn
    // Communities", also darf es auch in keine Stufenleiter geraten.
    // 2026-08-24 (Auftrag vom 24.08.): badge_58 „Durchgespielt" ist der vierte
    // stufenlose. Es gibt kein „zweites Tutorial", also darf auch dieses
    // Abzeichen in keine Stufenleiter geraten.
    test('ohne Familie sind nur die vier bewussten Einzelstuecke', () {
      final ohne = Badge.all
          .where((b) => b.familie == null)
          .map((b) => b.id)
          .toList();
      expect(ohne, [
        Badge.membershipBadgeId,
        Badge.starterBadgeId,
        Badge.communityGruenderBadgeId,
        Badge.onboardingBadgeId,
      ]);
    });

    test('alle Stufen einer Familie tragen dieselbe Akzent-Kategorie', () {
      // Sonst haetten zwei Stufen desselben Ziels verschiedene Farben.
      for (final familie in badgeFamilien) {
        final kategorien = Badge.familienBadges(
          familie.schluessel,
        ).map((b) => b.category).toSet();
        expect(
          kategorien,
          hasLength(1),
          reason: 'Familie ${familie.schluessel}: $kategorien',
        );
      }
    });

    test('die Akzentfarbe kennt jede benutzte Kategorie', () {
      // 2026-08-18: 'group' und 'groups' waren derselbe Begriff in zwei
      // Schreibweisen; 'group' fiel in den Standardzweig der Farbtabelle.
      final seite = File(
        'lib/presentation/pages/analytics_page.dart',
      ).readAsStringSync();
      final farbtabelle = seite.substring(
        seite.indexOf('Color _badgeAccentColor'),
      );
      for (final kategorie in Badge.all.map((b) => b.category).toSet()) {
        if (kategorie == 'membership') continue; // bewusst Standardfarbe
        expect(
          farbtabelle.contains("'$kategorie' =>"),
          isTrue,
          reason: 'Kategorie $kategorie hat keine eigene Akzentfarbe',
        );
      }
    });

    test('jedes Badge hat ein vorhandenes Emblem', () {
      for (final badge in Badge.all) {
        expect(badge.assetPath, isNotNull, reason: badge.id);
        expect(
          File(badge.assetPath!).existsSync(),
          isTrue,
          reason: '${badge.id}: ${badge.assetPath}',
        );
      }
    });

    test('keine Gedankenstriche in Namen und Beschreibungen', () {
      for (final badge in Badge.all) {
        expect(badge.name.contains('—'), isFalse, reason: badge.id);
        expect(badge.description.contains('—'), isFalse, reason: badge.id);
      }
    });
  });

  group('Hilfsmethoden', () {
    test('familienBadges liefert die Stufen in der richtigen Reihenfolge', () {
      expect(Badge.familienBadges('kurven').map((b) => b.id), [
        'badge_41',
        'badge_27',
        'badge_42',
      ]);
      // Stufenlose Meilensteine haengen hinten dran, nach Schwelle sortiert.
      expect(Badge.familienBadges('distanz').map((b) => b.id), [
        'badge_06',
        'badge_10',
        'badge_13',
        'badge_31',
        'badge_32',
      ]);
    });

    test('hoechste erreichte Stufe zu einer Menge erreichter IDs', () {
      expect(Badge.hoechsteErreichteStufe('kurven', {'badge_41'}), 1);
      expect(
        Badge.hoechsteErreichteStufe('kurven', {'badge_41', 'badge_27'}),
        2,
      );
      expect(Badge.hoechsteErreichteStufe('kurven', const {}), 0);
      // Ein stufenloser Meilenstein hebt die Stufe nicht an.
      expect(Badge.hoechsteErreichteStufe('distanz', {'badge_31'}), 0);
    });

    test('naechsteStufe ueberspringt Erreichtes', () {
      expect(Badge.naechsteStufe('kurven', {'badge_41'})?.id, 'badge_27');
      expect(
        Badge.naechsteStufe('kurven', {
          'badge_41',
          'badge_27',
          'badge_42',
        }),
        isNull,
      );
    });
  });

  group('Fortschritt zielt auf die naechste Stufe', () {
    Map<BadgeMetrik, double> m({
      double km = 0,
      int kurven = 0,
      int gruppen = 0,
    }) => badgeMetriken(
      totalKm: km,
      kurvenjagdFahrten: kurven,
      createdGroups: gruppen,
    );

    test('Kurvenkoenig: 4 Fahrten zeigen den Weg zur zweiten Stufe', () {
      final p = badgeFamilienFortschritt(
        familie: 'kurven',
        erreichteBadgeIds: {'badge_41'},
        metriken: m(kurven: 4),
      )!;
      expect(p.ziel, 10);
      expect(p.zahlen, '4 von 10 Fahrten');
    });

    test('ohne jede Stufe wird gegen die erste gemessen', () {
      final p = badgeFamilienFortschritt(
        familie: 'kurven',
        erreichteBadgeIds: const {},
        metriken: m(kurven: 1),
      )!;
      expect(p.ziel, 3);
    });

    test('Vuckos Beispiel: 274 km zeigen 274 von 500', () {
      final p = badgeFamilienFortschritt(
        familie: 'distanz',
        erreichteBadgeIds: const {},
        metriken: m(km: 274),
      )!;
      expect(p.zahlen, '274 von 500 km');
    });

    test('ist alles erreicht, gibt es nichts mehr anzuzeigen', () {
      final alle = Badge.familienBadges('kurven').map((b) => b.id).toSet();
      expect(
        badgeFamilienFortschritt(
          familie: 'kurven',
          erreichteBadgeIds: alle,
          metriken: m(kurven: 99),
        ),
        isNull,
      );
    });

    test('ein einzelnes Badge misst weiter an SEINER eigenen Schwelle', () {
      final p = badgeFortschrittAus('badge_42', m(kurven: 4))!;
      expect(p.ziel, 25);
    });
  });

  group('Freischaltung liest dieselbe Tabelle', () {
    test('Schwellen schalten genau ihre Stufe frei', () {
      final ids = erfuellteBadgeIds(
        badgeMetriken(kurvenjagdFahrten: 10, totalKm: 600),
      );
      expect(ids, contains('badge_41'));
      expect(ids, contains('badge_27'));
      expect(ids, isNot(contains('badge_42')));
      expect(ids, contains('badge_06'));
      expect(ids, isNot(contains('badge_31')));
    });

    test('nichts gefahren, nichts freigeschaltet', () {
      expect(erfuellteBadgeIds(badgeMetriken()), isEmpty);
    });

    test('der Gruppen-Zaehler deckelt nicht mehr bei zwei', () {
      // Hier stand `.limit(2)`; damit waeren badge_35 (3) und badge_38 (10)
      // nie erreichbar gewesen.
      final quelle = File(
        'lib/data/services/gamification_service.dart',
      ).readAsStringSync();
      expect(quelle.contains('.eq(\'created_by\', userId)\n          .limit(2)'),
          isFalse);
      expect(erfuellteBadgeIds(badgeMetriken(createdGroups: 10)),
          containsAll(['badge_07', 'badge_35', 'badge_38']));
    });
  });
}
