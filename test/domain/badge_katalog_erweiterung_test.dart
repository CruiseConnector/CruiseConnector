import 'package:cruise_connect/domain/models/badge.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-24 (Auftrag vom 24.08., vucko woertlich):
/// „erstelle fuer die genannten kategorien selber noch badges [...] und man
/// soll dafuer auch ein badge bekommen wenn man es abgeschlossen hat wie
/// startklar [...] man muss die sachen wie ersten post oder benutze einen
/// hashtag [...] auch wirklich absolvieren."
///
/// Dieser Test haelt DREI Dinge fest:
///  1. Das Onboarding-Abzeichen badge_58 gibt es, und es ist ausdruecklich
///     NICHT dasselbe wie badge_16 „Startklar".
///  2. Die vier neuen Familien (Garage, Beitraege, Hashtags, Meldungen) mit
///     genau den Schwellen, die aus den gemessenen Zahlen abgeleitet wurden.
///  3. Kein Abzeichen traegt dasselbe Symbol wie ein anderes.
void main() {
  group('badge_58 Onboarding', () {
    test('existiert, ist stufenlos und haengt in keiner Familie', () {
      final badge = Badge.getById(Badge.onboardingBadgeId);
      expect(badge, isNotNull);
      expect(Badge.onboardingBadgeId, 'badge_58');
      expect(badge!.familie, isNull);
      expect(badge.stufe, 0);
      expect(badge.category, 'membership');
    });

    test('ist ein anderes Abzeichen als Startklar', () {
      // badge_16 haengt an ACHT von ELF Starter-Aufgaben, badge_58 allein am
      // Tutorial. Wer die beiden zusammenlegt, verliert die Belohnung genau
      // in der Minute, in der die Tour zu Ende ist.
      expect(Badge.onboardingBadgeId, isNot(Badge.starterBadgeId));
      final onboarding = Badge.getById(Badge.onboardingBadgeId)!;
      final startklar = Badge.getById(Badge.starterBadgeId)!;
      expect(onboarding.name, isNot(startklar.name));
      expect(onboarding.emoji, isNot(startklar.emoji));
      expect(onboarding.assetPath, isNot(startklar.assetPath));
    });

    test('hat keine Schwelle, also auch keinen Fortschrittsbalken', () {
      // Stufenlose Abzeichen werden serverseitig vergeben, nicht gerechnet.
      expect(badgeBedingungFuer(Badge.onboardingBadgeId), isNull);
      expect(
        erfuellteBadgeIds(badgeMetriken(totalKm: 99999, level: 100)),
        isNot(contains(Badge.onboardingBadgeId)),
      );
    });
  });

  group('Neue Familien fuer bisher abzeichenlose Bereiche', () {
    void pruefeFamilie(String schluessel, List<double> schwellen) {
      final familie = badgeFamilieVon(schluessel);
      expect(familie, isNotNull, reason: 'Familie $schluessel fehlt');
      expect(familie!.stufen.map((s) => s.schwelle).toList(), schwellen);
      for (var i = 0; i < familie.stufen.length; i++) {
        final badge = Badge.getById(familie.stufen[i].id);
        expect(badge, isNotNull, reason: familie.stufen[i].id);
        expect(badge!.stufe, i + 1);
        expect(badge.familie, schluessel);
      }
    }

    // GEMESSEN am 24.08.: 86 Fahrzeuge bei 62 Nutzern, Maximum fuenf pro
    // Person. Die hoechste Stufe liegt genau auf diesem Maximum.
    test('Garage: 1 / 3 / 5 Fahrzeuge', () {
      pruefeFamilie('garage', [1, 3, 5]);
    });

    // GEMESSEN: 10 Beitraege von 7 Nutzern, Maximum zwei pro Person.
    test('Beitraege: 1 / 5 / 20', () {
      pruefeFamilie('beitraege', [1, 5, 20]);
    });

    // GEMESSEN: post_hashtags hat 0 Zeilen. Die erste Stufe ist ein einziger
    // Hashtag, genau Vuckos „benutze einen hashtag".
    test('Hashtags: 1 / 5 / 20', () {
      pruefeFamilie('hashtags', [1, 5, 20]);
    });

    // GEMESSEN: 8 Meldungen von 2 Nutzern, eine Person allein hat sieben.
    test('Meldungen: 1 / 5 / 20', () {
      pruefeFamilie('meldungen', [1, 5, 20]);
    });

    test('die neuen Kennzahlen schalten genau ihre Stufen frei', () {
      final ids = erfuellteBadgeIds(
        badgeMetriken(
          fahrzeuge: 3,
          beitraege: 5,
          hashtagBeitraege: 1,
          meldungen: 20,
        ),
      );
      expect(ids, containsAll(['badge_59', 'badge_60']));
      expect(ids, isNot(contains('badge_61')));
      expect(ids, containsAll(['badge_62', 'badge_63']));
      expect(ids, isNot(contains('badge_64')));
      expect(ids, contains('badge_65'));
      expect(ids, isNot(contains('badge_66')));
      expect(ids, containsAll(['badge_68', 'badge_69', 'badge_70']));
    });

    test('ohne Daten bleibt alles gesperrt', () {
      final ids = erfuellteBadgeIds(badgeMetriken());
      for (final id in [
        for (var i = 59; i <= 70; i++) 'badge_$i',
      ]) {
        expect(ids, isNot(contains(id)), reason: id);
      }
    });

    test('der Fortschritt zeigt die naechste offene Stufe', () {
      final p = badgeFamilienFortschritt(
        familie: 'garage',
        erreichteBadgeIds: const {'badge_59'},
        metriken: badgeMetriken(fahrzeuge: 2),
      )!;
      expect(p.zahlen, '2 von 3 Fahrzeuge');

      final einzeln = badgeFortschrittFuer(
        badgeId: 'badge_70',
        level: 0,
        totalKm: 0,
        totalHours: 0,
        completedRides: 0,
        completedGroupRides: 0,
        routePosts: 0,
        createdGroups: 0,
        savedRoutes: 0,
        longestRideKm: 0,
        meldungen: 7,
      )!;
      expect(einzeln.zahlen, '7 von 20 Meldungen');
    });
  });

  group('Symbole', () {
    test('kein Abzeichen traegt dasselbe Symbol wie ein anderes', () {
      // Zwei gleiche Zeichen sind in der Uebersicht nicht auseinanderzuhalten.
      final proEmoji = <String, List<String>>{};
      for (final badge in Badge.all) {
        proEmoji.putIfAbsent(badge.emoji, () => []).add(badge.id);
      }
      final doppelte = proEmoji.entries.where((e) => e.value.length > 1);
      expect(
        doppelte.map((e) => '${e.key}: ${e.value.join(", ")}').toList(),
        isEmpty,
      );
    });

    test('jedes Abzeichen hat ueberhaupt ein Symbol', () {
      for (final badge in Badge.all) {
        expect(badge.emoji.trim(), isNotEmpty, reason: badge.id);
      }
    });
  });
}
