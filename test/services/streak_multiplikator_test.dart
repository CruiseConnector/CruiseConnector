import 'dart:io';

import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';
import 'package:cruise_connect/domain/models/user_drive_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-19 (vucko): „man soll auf den 2 fachen multiplikator der eine woche
/// geht aufbauen bspw nach einem tg 2,1 nach dem zweiten tag 2,2 usw. aber wenn
/// man bei 2,8 oder 3,2x mulitplikator einen tag vergisst, kommt man bei der
/// anfangswoche zurueck auf 2 solang der double xp multiplikator laeuft und
/// wenn die 7 tage vorbei sind und man keine double xp mehr hat, ist die basis
/// 1,00 xp also wenn man es dann vergisst kommt man ganz normal auf 1,00xp nach
/// dem boost."
///
/// Und zum Verfall: „wenn man eine Streak hat und einen Tag vergisst, das man
/// die moeglichkeit hat die streak wieder zu entfachen aber wenn man die app
/// zwei tage nicht verwendet und davor eine streak hatte, kommt man wieder auf
/// die basisstreak ausser in der double xp woche."
///
/// Vor dieser Aenderung waere JEDE Erwartung hier rot: der Multiplikator war
/// hart `1,0 + Tage * 0,1` (nie 2,0 als Basis), die Serie riss beim ERSTEN
/// Fehltag (keine Schonfrist), und die Doppel-XP-Woche wurde nachtraeglich als
/// `xp * 2` obendrauf gelegt (Doppelrechnung).
UserDriveSession _fahrt(DateTime tag, {double km = 20}) => UserDriveSession(
  id: 'f-${tag.toIso8601String()}',
  userId: 'u',
  distanceKm: km,
  durationSeconds: 1800,
  xpAwarded: 0,
  completedAtEnd: true,
  createdAt: tag,
);

DateTime _tag(int jahr, int monat, int tag) => DateTime(jahr, monat, tag, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final starter = StarterAufgabenService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    starter.resetForTests();
  });

  group('Multiplikator = Basis + Tage * 0,1', () {
    // Die Tabelle aus der Regel. Links die Basis, dann die Serie, rechts das
    // Ergebnis. Basis 1,0 = Bonuswoche vorbei, Basis 2,0 = Bonuswoche laeuft.
    const tabelle = <List<double>>[
      // [Basis, Streak-Tage, erwarteter Multiplikator]
      [1.0, 0, 1.0],
      [1.0, 1, 1.1],
      [1.0, 3, 1.3],
      [1.0, 10, 2.0],
      [2.0, 0, 2.0],
      [2.0, 1, 2.1],
      [2.0, 2, 2.2],
      [2.0, 3, 2.3],
      [2.0, 10, 3.0],
    ];

    test('die ganze Tabelle stimmt', () {
      for (final zeile in tabelle) {
        final bonusLaeuft = zeile[0] == 2.0;
        expect(
          GamificationService.streakMultiplierForDays(
            zeile[1].toInt(),
            doppelXpAktiv: bonusLaeuft,
          ),
          closeTo(zeile[2], 1e-9),
          reason:
              'Basis ${zeile[0]} + ${zeile[1].toInt()} Tage muss ${zeile[2]} '
              'ergeben',
        );
      }
    });

    test('kein Deckel nach oben', () {
      expect(
        GamificationService.streakMultiplierForDays(30, doppelXpAktiv: false),
        closeTo(4.0, 1e-9),
      );
      expect(
        GamificationService.streakMultiplierForDays(30, doppelXpAktiv: true),
        closeTo(5.0, 1e-9),
      );
    });

    test('negative Tage koennen die Basis nicht unterschreiten', () {
      expect(
        GamificationService.streakMultiplierForDays(-5, doppelXpAktiv: true),
        closeTo(2.0, 1e-9),
      );
    });
  });

  group('Die Verdopplung wird NICHT mehr doppelt gerechnet', () {
    test('der Dienst meldet die Woche, rechnet aber nicht selbst', () async {
      SharedPreferences.setMockInitialValues({
        'starter_paket_vergeben_v1': true,
        'starter_bonus_ende_v1': DateTime.now()
            .add(const Duration(days: 3))
            .toIso8601String(),
        'starter_aufgaben_erledigt_v1':
            '["tutorial","route","favorit","speichern","community"]',
      });
      await starter.load();
      // Frueher gab es hier wendeBonusAn(85) == 170. Die Methode ist seit
      // dem 19.08. ERSATZLOS entfernt; der Dienst sagt nur noch, OB die
      // Woche laeuft. Gerechnet wird ausschliesslich im Multiplikator.
      expect(starter.doppelXpAktiv, isTrue);
    });

    test('Streak 3, 100 km: alt 2600 XP, neu 2300 XP', () async {
      SharedPreferences.setMockInitialValues({
        'starter_paket_vergeben_v1': true,
        'starter_bonus_ende_v1': DateTime.now()
            .add(const Duration(days: 3))
            .toIso8601String(),
        'starter_aufgaben_erledigt_v1':
            '["tutorial","route","favorit","speichern","community"]',
      });
      await starter.load();

      final b = GamificationService.calculateRouteXpBreakdown(
        distanceKm: 100,
        curves: 0,
        style: 'Sport Mode',
        streakDays: 3,
      );
      expect(b.baseXp, 1000);
      expect(b.multiplier, closeTo(2.3, 1e-9));
      expect(b.totalXp, 2300);
      // Und es gibt keine Stelle mehr, die nachtraeglich verdoppelt: das
      // waere genau die 2600 von frueher.
      expect(b.totalXp, isNot(2600));
    });

    test(
      'die Rechnung holt sich die Basis selbst vom Starter-Dienst',
      () async {
        // Kein Aufrufer muss die Bonuswoche kennen: ohne Bonus 1,3x …
        await starter.load();
        expect(starter.doppelXpAktiv, isFalse);
        expect(
          GamificationService.calculateRouteXp(
            distanceKm: 100,
            curves: 0,
            style: 'Sport Mode',
            streakDays: 3,
          ),
          1300,
        );

        // … und mit laufender Bonuswoche 2,3x, ohne Zutun des Aufrufers.
        starter.resetForTests();
        SharedPreferences.setMockInitialValues({
          'starter_paket_vergeben_v1': true,
          'starter_bonus_ende_v1': DateTime.now()
              .add(const Duration(days: 2))
              .toIso8601String(),
          'starter_aufgaben_erledigt_v1':
              '["tutorial","route","favorit","speichern","community"]',
        });
        await starter.load();
        expect(
          GamificationService.calculateRouteXp(
            distanceKm: 100,
            curves: 0,
            style: 'Sport Mode',
            streakDays: 3,
          ),
          2300,
        );
      },
    );
  });

  group('Streak-Verfall mit Schonfrist', () {
    // Bezugstag ist durchgehend Freitag, der 14.08.2026.
    final heute = _tag(2026, 8, 14);

    test('drei Tage am Stueck: Serie 3', () {
      final serie = GamificationService.calculateDrivingStreakDays([
        _fahrt(_tag(2026, 8, 12)),
        _fahrt(_tag(2026, 8, 13)),
        _fahrt(heute),
      ], now: heute);
      expect(serie, 3);
    });

    test('EIN Tag Luecke: die Serie ueberlebt und zaehlt weiter', () {
      // Mo, Di, Mi gefahren, Do vergessen, Fr wieder gefahren.
      final serie = GamificationService.calculateDrivingStreakDays([
        _fahrt(_tag(2026, 8, 10)),
        _fahrt(_tag(2026, 8, 11)),
        _fahrt(_tag(2026, 8, 12)),
        // 13. fehlt
        _fahrt(heute),
      ], now: heute);
      expect(serie, 4, reason: 'vier Fahrtage, der eine Fehltag zaehlt nicht');
    });

    test('ZWEI Tage Luecke: die Serie faellt auf die Basisserie', () {
      final serie = GamificationService.calculateDrivingStreakDays([
        _fahrt(_tag(2026, 8, 9)),
        _fahrt(_tag(2026, 8, 10)),
        _fahrt(_tag(2026, 8, 11)),
        // 12. und 13. fehlen
        _fahrt(heute),
      ], now: heute);
      expect(serie, 1, reason: 'nur der heutige Fahrtag zaehlt noch');
    });

    test(
      'zweiter Fehltag innerhalb der sieben Tage beendet die Schonfrist',
      () {
        // Rueckwaerts gelesen: 14., 13., 12. gefahren; 11. Fehltag (Schonfrist
        // laeuft ab da); 10. gefahren; 9. ZWEITER Fehltag, nur zwei Tage nach
        // dem ersten — hier reisst die Serie. Was davor liegt (6.-8.) zaehlt
        // nicht mehr mit.
        final serie = GamificationService.calculateDrivingStreakDays([
          _fahrt(_tag(2026, 8, 6)),
          _fahrt(_tag(2026, 8, 7)),
          _fahrt(_tag(2026, 8, 8)),
          _fahrt(_tag(2026, 8, 10)),
          _fahrt(_tag(2026, 8, 12)),
          _fahrt(_tag(2026, 8, 13)),
          _fahrt(heute),
        ], now: heute);
        expect(
          serie,
          4,
          reason: '10., 12., 13., 14. — davor riss der zweite Fehltag',
        );
      },
    );

    test('nach mehr als sieben Tagen ist wieder ein Fehltag frei', () {
      // 1. Fehltag am 2.8., zweiter am 13.8. — elf Tage spaeter, also lange
      // nach dem Ende der Schonfrist. Beide Luecken sind einzeln verzeihlich.
      final serie = GamificationService.calculateDrivingStreakDays([
        _fahrt(_tag(2026, 8, 1)),
        // 2. fehlt
        _fahrt(_tag(2026, 8, 3)),
        _fahrt(_tag(2026, 8, 4)),
        _fahrt(_tag(2026, 8, 5)),
        _fahrt(_tag(2026, 8, 6)),
        _fahrt(_tag(2026, 8, 7)),
        _fahrt(_tag(2026, 8, 8)),
        _fahrt(_tag(2026, 8, 9)),
        _fahrt(_tag(2026, 8, 10)),
        _fahrt(_tag(2026, 8, 11)),
        _fahrt(_tag(2026, 8, 12)),
        // 13. fehlt
        _fahrt(heute),
      ], now: heute);
      expect(serie, 12, reason: 'zwoelf Fahrtage, zwei getrennte Fehltage');
    });

    test('heute noch nicht gefahren ist KEIN Fehltag', () {
      final serie = GamificationService.calculateDrivingStreakDays([
        _fahrt(_tag(2026, 8, 11)),
        _fahrt(_tag(2026, 8, 12)),
        _fahrt(_tag(2026, 8, 13)),
      ], now: heute);
      expect(serie, 3, reason: 'der laufende Tag ist noch nicht vorbei');
    });

    test('gestern vergessen, heute noch offen: die Serie ist zu entfachen', () {
      // Genau der Fall aus dem Auftrag: EIN Fehltag (13.), heute (14.) ist
      // noch nicht vorbei. Die Zahl bleibt stehen, damit man sie heute noch
      // retten kann.
      final serie = GamificationService.calculateDrivingStreakDays([
        _fahrt(_tag(2026, 8, 10)),
        _fahrt(_tag(2026, 8, 11)),
        _fahrt(_tag(2026, 8, 12)),
      ], now: heute);
      expect(serie, 3);
    });

    test('zwei volle Fehltage: Serie ist weg', () {
      // Einen Tag spaeter sind 13. UND 14. vorbei und beide leer.
      final serie = GamificationService.calculateDrivingStreakDays([
        _fahrt(_tag(2026, 8, 10)),
        _fahrt(_tag(2026, 8, 11)),
        _fahrt(_tag(2026, 8, 12)),
      ], now: _tag(2026, 8, 15));
      expect(serie, 0);
    });

    test('0-km-Zeilen halten die Serie NICHT am Leben', () {
      final serie = GamificationService.calculateDrivingStreakDays([
        _fahrt(_tag(2026, 8, 10)),
        _fahrt(_tag(2026, 8, 11), km: 0),
        _fahrt(_tag(2026, 8, 12), km: 0),
        _fahrt(heute),
      ], now: heute);
      expect(serie, 1, reason: 'zwei echte Fehltage trotz zweier 0-km-Zeilen');
    });

    test('ohne jede Fahrt ist die Serie 0', () {
      expect(
        GamificationService.calculateDrivingStreakDays(const [], now: heute),
        0,
      );
    });
  });

  group('Serie fuer die Gutschrift einer Fahrt', () {
    final fahrtTag = _tag(2026, 8, 14);

    test('erste Fahrt ueberhaupt: Serie 1', () {
      expect(
        GamificationService.calculateStreakDaysForRide(
          const [],
          rideDate: fahrtTag,
        ),
        1,
      );
    });

    test('ein Fehltag davor: die Serie laeuft weiter', () {
      expect(
        GamificationService.calculateStreakDaysForRide([
          _fahrt(_tag(2026, 8, 11)),
          _fahrt(_tag(2026, 8, 12)),
          // 13. fehlt
        ], rideDate: fahrtTag),
        3,
      );
    });

    test('zwei Fehltage davor: nur die heutige Fahrt zaehlt', () {
      expect(
        GamificationService.calculateStreakDaysForRide([
          _fahrt(_tag(2026, 8, 10)),
          _fahrt(_tag(2026, 8, 11)),
          // 12. und 13. fehlen
        ], rideDate: fahrtTag),
        1,
      );
    });
  });

  group('Was der Nutzer nach einem Fehltag sieht', () {
    final heute = _tag(2026, 8, 14);

    test('Fehltag IN der Bonuswoche faellt auf 2,00x', () {
      final serie = GamificationService.calculateDrivingStreakDays([
        _fahrt(_tag(2026, 8, 9)),
        _fahrt(_tag(2026, 8, 10)),
        _fahrt(_tag(2026, 8, 11)),
        // 12. und 13. fehlen -> Serie gerissen
      ], now: heute);
      expect(serie, 0);
      expect(
        GamificationService.streakMultiplierForDays(serie, doppelXpAktiv: true),
        closeTo(2.0, 1e-9),
      );
    });

    test('Fehltag NACH der Bonuswoche faellt auf 1,00x', () {
      final serie = GamificationService.calculateDrivingStreakDays([
        _fahrt(_tag(2026, 8, 9)),
        _fahrt(_tag(2026, 8, 10)),
        _fahrt(_tag(2026, 8, 11)),
      ], now: heute);
      expect(serie, 0);
      expect(
        GamificationService.streakMultiplierForDays(
          serie,
          doppelXpAktiv: false,
        ),
        closeTo(1.0, 1e-9),
      );
    });

    test('1,00x ist erreichbar — die alte Anhebung auf 1 ist weg', () {
      // Vorher hob calculateRouteXpBreakdown jeden Wert auf mindestens einen
      // Streak-Tag an: 1,00x war unerreichbar, 1,10x das Minimum.
      final b = GamificationService.calculateRouteXpBreakdown(
        distanceKm: 10,
        curves: 0,
        style: 'Sport Mode',
        streakDays: 0,
        doppelXpAktiv: false,
      );
      expect(b.streakDays, 0);
      expect(b.multiplier, closeTo(1.0, 1e-9));
      expect(b.totalXp, 100);
      expect(b.multiplierLabel, 'x1.00');
    });
  });

  group('Verdrahtung', () {
    test('die Auswertung rechnet die Serie NICHT mehr selbst', () {
      final quelle = File(
        'lib/presentation/pages/analytics_page.dart',
      ).readAsStringSync();
      expect(
        quelle.contains('GamificationService.calculateDrivingStreakDays'),
        isTrue,
        reason: 'die Auswertung muss den Dienst fragen',
      );
      expect(
        quelle.contains('while (driveDays.contains(checkDay))'),
        isFalse,
        reason: 'die abgeschriebene zweite Streak-Schleife muss weg sein',
      );
    });

    test('die Verdopplung steht nur noch an EINER Stelle', () {
      final starterQuelle = File(
        'lib/data/services/starter_aufgaben_service.dart',
      ).readAsStringSync();
      // 2026-08-19: Die Methode ist ganz weg, nicht nur entschaerft. Eine
      // Methode, die nur durchreicht, laedt dazu ein, spaeter wieder etwas
      // hineinzuschreiben, und dann zaehlt die Woche zweimal.
      expect(
        starterQuelle.contains('int wendeBonusAn('),
        isFalse,
        reason: 'wendeBonusAn ist ersatzlos entfernt und darf nicht zurueckkommen',
      );
      expect(
        starterQuelle.contains('static const int bonusFaktor'),
        isFalse,
        reason: 'der alte Faktor ist ersatzlos in die Basis gewandert',
      );
      // Und die Basis lebt genau einmal, im Rechendienst.
      final gam = File(
        'lib/data/services/gamification_service.dart',
      ).readAsStringSync();
      expect(
        gam.contains('static const double basisMitDoppelXp = 2.0;'),
        isTrue,
      );
      expect(gam.contains('static const double basisOhneBonus = 1.0;'), isTrue);
    });
  });
}
