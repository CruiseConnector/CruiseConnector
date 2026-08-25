import 'dart:io';

import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-25, Vucko wörtlich:
///
///   „das abzeichen nach dem onboarding soll startklar heissen und nicht
///    durchgespielt. udn man soll sehen man bekommt ein badge 1000 XP + noch
///    einen 2 fach boost der 7 Tage lang aktiv ist"
///
/// DER GEMESSENE BEFUND (25.08., Produktivdatenbank, 202 Profile):
///
///   profiles.total_xp gegen die Summe der xp_awarded    Differenz 0, überall
///   Profile mit badge_16 „Startklar"                    183 (alle aus der
///                                                       Migration vom 24.08.)
///   Profile mit badge_58 „Durchgespielt"                  1 (Vucko)
///   Profile mit einem starter_bonus_ende                  1
///   Profile mit laufender Bonuswoche                      0
///
/// Die 1000 XP standen auf der Karte und wurden NIE gebucht — die Differenz
/// null über alle 202 Profile ist der Beweis.
///
/// OHNE DIE ÄNDERUNG WÄRE JEDER TEST HIER ROT: [GamificationService
/// .starterPaketBonusXp] und [GamificationService.gesamtXpMitStarterBonus]
/// gab es nicht, und `calculateAndSync` schrieb `totals.totalXp` unverändert
/// nach `profiles.total_xp`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final starter = StarterAufgabenService.instance;

  final dienstQuelle = File(
    'lib/data/services/gamification_service.dart',
  ).readAsStringSync();

  /// Der Dienst OHNE Zeilenkommentare. Nötig, weil die erklärenden
  /// Kommentare die alte Zeile wörtlich zitieren — eine Quellwache über die
  /// rohe Datei wäre daran hängen geblieben.
  final dienstCode = dienstQuelle
      .split('\n')
      .where((z) => !z.trimLeft().startsWith('//') && !z.trimLeft().startsWith('///'))
      .join('\n');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    starter.resetForTests();
  });

  group('Die 1000 XP gibt es überhaupt', () {
    test('die Zahl steht an genau einer Stelle und ist 1000', () {
      expect(GamificationService.starterPaketBonusXp, 1000);
      // Kein zweites Vorkommen als nackte Zahl in der Rechnung — die Karte
      // und die Gutschrift müssen dieselbe Konstante lesen, sonst zeigt die
      // Karte etwas anderes an, als gebucht wird.
      final vorkommen = RegExp(
        r'starterPaketBonusXp\s*=',
      ).allMatches(dienstQuelle).length;
      expect(vorkommen, 1);
    });

    test('ohne verdientes Paket gibt es keinen Bonus', () {
      expect(
        GamificationService.gesamtXpMitStarterBonus(
          fahrtenXp: 2300,
          paketVerdient: false,
        ),
        2300,
      );
    });

    test('mit verdientem Paket kommen genau 1000 dazu', () {
      expect(
        GamificationService.gesamtXpMitStarterBonus(
          fahrtenXp: 2300,
          paketVerdient: true,
        ),
        3300,
      );
      expect(
        GamificationService.gesamtXpMitStarterBonus(
          fahrtenXp: 0,
          paketVerdient: true,
        ),
        1000,
      );
    });
  });

  group('Die gefährlichste Stelle: nichts wird doppelt gerechnet', () {
    /// Am 19.08. hat eine zweite Verdopplungsstelle aus 2300 XP einmal 2600
    /// gemacht. Ein Bonus, der zusätzlich mit dem Multiplikator verrechnet
    /// würde, wäre genau derselbe Fehler mit einer anderen Zahl.
    test('die laufende Doppel-XP-Woche verdoppelt den Bonus NICHT', () async {
      SharedPreferences.setMockInitialValues({
        'starter_paket_vergeben_v1': true,
        'starter_bonus_ende_v1': DateTime.now()
            .add(const Duration(days: 3))
            .toIso8601String(),
        'starter_aufgaben_erledigt_v1':
            '["tutorial","route","favorit","speichern","community",'
            '"garage","runde","post"]',
      });
      await starter.load();
      expect(starter.doppelXpAktiv, isTrue);
      expect(starter.paketVerdient, isTrue);

      // Fahrt-XP: 100 km, Streak 3, laufende Woche → 1000 * 2,3 = 2300.
      final fahrt = GamificationService.calculateRouteXpBreakdown(
        distanceKm: 100,
        curves: 0,
        style: 'Sport Mode',
        streakDays: 3,
      );
      expect(fahrt.totalXp, 2300, reason: 'die Fahrt-Rechnung ist unberührt');

      final gesamt = GamificationService.gesamtXpMitStarterBonus(
        fahrtenXp: fahrt.totalXp,
        paketVerdient: starter.paketVerdient,
      );
      expect(gesamt, 3300);
      expect(gesamt, isNot(4300), reason: 'der Bonus wurde verdoppelt');
      expect(gesamt, isNot(3600), reason: 'die Fahrt wurde ein zweites Mal '
          'verdoppelt — das ist die 2600 vom 19.08.');
    });

    test('zweimal gerechnet kommt zweimal dasselbe heraus', () {
      // profiles.total_xp wird bei JEDEM Sync neu geschrieben. Wäre der Bonus
      // eine Buchung statt eines Zustands, stünden nach zehn Syncs 10.000 XP
      // zu viel im Profil.
      var stand = 0;
      for (var sync = 0; sync < 10; sync++) {
        stand = GamificationService.gesamtXpMitStarterBonus(
          fahrtenXp: 500,
          paketVerdient: true,
        );
      }
      expect(stand, 1500);
    });

    test('die Waechter gegen die Doppelrechnung stehen unverändert', () {
      final starterQuelle = File(
        'lib/data/services/starter_aufgaben_service.dart',
      ).readAsStringSync();
      expect(starterQuelle.contains('int wendeBonusAn('), isFalse);
      expect(starterQuelle.contains('static const int bonusFaktor'), isFalse);
      expect(
        dienstQuelle.contains('static const double basisMitDoppelXp = 2.0;'),
        isTrue,
      );
      expect(
        dienstQuelle.contains('static const double basisOhneBonus = 1.0;'),
        isTrue,
      );
      // Und der neue Bonus rechnet selbst nicht mit dem Multiplikator.
      final rumpfStart = dienstQuelle.indexOf(
        'static int gesamtXpMitStarterBonus(',
      );
      expect(rumpfStart, greaterThan(0));
      final rumpf = dienstQuelle.substring(
        rumpfStart,
        dienstQuelle.indexOf(';', dienstQuelle.indexOf('=>', rumpfStart)),
      );
      expect(rumpf.contains('multiplier'), isFalse);
      expect(rumpf.contains('streakMultiplierForDays'), isFalse);
      expect(rumpf.contains('basisMitDoppelXp'), isFalse);
    });
  });

  group('Der Bonus kommt wirklich im Profil an', () {
    test('calculateAndSync schreibt die Summe MIT Bonus', () {
      // Vorher stand hier `final totalXp = totals.totalXp;` — genau deshalb
      // war die Differenz über alle 202 Profile null.
      expect(
        dienstCode.contains('final totalXp = totals.totalXp;'),
        isFalse,
        reason: 'der Bonus wird wieder überschrieben',
      );
      final bonus = dienstQuelle.indexOf('final totalXp = gesamtXpMitStarterBonus(');
      expect(bonus, greaterThan(0), reason: 'der Bonus wird nie gerechnet');

      // Er hängt an derselben Bedingung wie das Abzeichen.
      final aufruf = dienstQuelle.substring(
        bonus,
        dienstQuelle.indexOf('\n    );', bonus),
      );
      expect(aufruf, contains('paketVerdient: starter.paketVerdient'));
      expect(aufruf, isNot(contains('alleAufgabenErledigt')));

      // Und das Ergebnis geht in die Spalte.
      final schreiben = dienstQuelle.indexOf("'total_xp': totalXp,");
      expect(schreiben, greaterThan(bonus));
    });

    test('das Level wird NACH dem Bonus bestimmt', () {
      // Sonst stünden im Profil ein Level und ein total_xp, die nicht
      // zusammenpassen.
      final bonus =
          dienstQuelle.indexOf('final totalXp = gesamtXpMitStarterBonus(');
      final level =
          dienstQuelle.indexOf('final level = UserLevel.fromXp(totalXp.toDouble());');
      expect(level, greaterThan(bonus));
    });
  });

  group('Eine Belohnung für eine Sache', () {
    test('das Abzeichen der Belohnung heißt Startklar', () {
      final belohnung = app.Badge.getById(app.Badge.starterBadgeId)!;
      expect(belohnung.name, 'Startklar');
      // Und die Vergabe hängt an paketVerdient, derselben Bedingung wie XP
      // und Bonuswoche.
      final vergabe = dienstQuelle.indexOf(
        'currentlyQualifiedBadges.add(Badge.starterBadgeId)',
      );
      expect(vergabe, greaterThan(0));
      final bedingung = dienstQuelle.substring(
        dienstQuelle.lastIndexOf('if (', vergabe),
        vergabe,
      );
      expect(bedingung, contains('starter.paketVerdient'));
    });

    test('badge_58 trägt weder XP noch Bonuswoche', () {
      // Es ist ein reines Sammler-Abzeichen. Nur so sind es nicht zwei fast
      // gleiche Abzeichen für dieselbe Liste.
      final vergabe = dienstQuelle.indexOf(
        'currentlyQualifiedBadges.add(alleAufgabenBadgeId)',
      );
      final bonus =
          dienstQuelle.indexOf('final totalXp = gesamtXpMitStarterBonus(');
      expect(vergabe, greaterThan(0));
      expect(bonus, greaterThan(vergabe));

      final bonusAufruf = dienstQuelle.substring(
        bonus,
        dienstQuelle.indexOf('\n    );', bonus),
      );
      expect(bonusAufruf, isNot(contains('alleAufgabenBadgeId')));
      expect(bonusAufruf, isNot(contains('alleAufgabenErledigt')));
    });

    test('die Kennung heißt nicht mehr „das Onboarding-Abzeichen"', () {
      // Der alte Name behauptete, badge_58 sei das Abzeichen nach dem
      // Onboarding. Genau darüber ist Vucko gestolpert.
      expect(app.Badge.alleAufgabenBadgeId, 'badge_58');
      expect(GamificationService.alleAufgabenBadgeId, 'badge_58');
      // Der alte Name bleibt als Alias, solange die Karte ihn liest.
      expect(app.Badge.onboardingBadgeId, app.Badge.alleAufgabenBadgeId);
    });

    test('die Schwelle der Belohnung bleibt bei acht von zwölf', () {
      // GEMESSEN am 25.08.: 0 von 202 Profilen erfüllen alle acht
      // serverseitig ableitbaren Aufgaben, „ein Hashtag" hat NIEMAND je
      // benutzt. Eine Belohnung bei zwölf wäre heute unerreichbar — genau der
      // Fehler vom 24.08., an dem 0 von 183 den Boost verpasst haben.
      expect(StarterAufgabenService.aufgabenFuerBoost, 8);
      expect(StarterAufgabenService.aufgaben.length, 12);
    });

    test('acht Aufgaben lösen Abzeichen, XP und Woche gemeinsam aus', () async {
      await starter.load();
      expect(starter.paketVerdient, isFalse);
      expect(
        GamificationService.gesamtXpMitStarterBonus(
          fahrtenXp: 100,
          paketVerdient: starter.paketVerdient,
        ),
        100,
      );

      await starter.markiereAlle(
        StarterAufgabenService.aufgaben.map((a) => a.id).take(8),
      );

      expect(starter.paketVerdient, isTrue, reason: 'Abzeichen');
      expect(starter.doppelXpAktiv, isTrue, reason: 'Bonuswoche');
      expect(
        GamificationService.gesamtXpMitStarterBonus(
          fahrtenXp: 100,
          paketVerdient: starter.paketVerdient,
        ),
        1100,
        reason: '1000 XP',
      );
    });
  });
}
