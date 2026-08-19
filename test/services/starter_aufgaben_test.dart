import 'dart:convert';
import 'dart:io';

import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-14 (vucko): „Aufgaben, die man erfüllen muss, um das Starter-Paket
/// zu haben, und einen zusätzlichen Bonus von einer Woche, wo man doppelt so
/// viele XP bekommt — und der Timer wirklich nur eine Woche läuft."
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dienst = StarterAufgabenService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dienst.resetForTests();
  });

  // 2026-08-19 (vucko): „auch noch weitere sachen wie der erste post, die
  // erste Gruppenfahrt umfasst wo man abschliessen muss und die erste runde
  // gefahren."
  test('acht Aufgaben, die drei neuen am Ende', () {
    expect(StarterAufgabenService.aufgaben, hasLength(8));
    final ids = StarterAufgabenService.aufgaben.map((a) => a.id).toList();
    expect(ids.take(5).toSet(), {
      'tutorial',
      'route',
      'favorit',
      'speichern',
      'community',
    });
    expect(ids.skip(5).toList(), ['runde', 'post', 'gruppenfahrt']);
  });

  test('markiere ist idempotent und zaehlt sauber', () async {
    await dienst.load();
    await dienst.markiere('route');
    await dienst.markiere('route');
    expect(dienst.erledigtAnzahl, 1);
    expect(dienst.alleErledigt, isFalse);
  });

  test('alle Aufgaben erledigt: Paket einmalig, Timer startet', () async {
    await dienst.load();
    for (final a in StarterAufgabenService.aufgaben) {
      await dienst.markiere(a.id);
    }
    expect(dienst.paketVergeben, isTrue);
    expect(dienst.paketFrischVerdient.value, isTrue);
    expect(dienst.doppelXpAktiv, isTrue);

    // Der Timer endet exakt sieben Tage nach dem Abschluss.
    final rest = dienst.bonusVerbleibend;
    expect(rest.inDays, 6);
    expect(rest.inHours, greaterThanOrEqualTo(167)); // knapp unter 168 h
  });

  test('der Endzeitpunkt wird EINMAL gesetzt und nie verlaengert', () async {
    await dienst.load();
    for (final a in StarterAufgabenService.aufgaben) {
      await dienst.markiere(a.id);
    }
    final ende = dienst.bonusEnde;
    // Erneutes Markieren (z. B. Replay) darf nichts verschieben.
    await dienst.markiere('route');
    expect(dienst.bonusEnde, ende);

    // Und ein Neustart liest denselben Endzeitpunkt von der Platte.
    dienst.resetForTests();
    await dienst.load();
    expect(
      dienst.bonusEnde!.difference(ende!).inSeconds.abs(),
      lessThan(2),
      reason: 'ein App-Neustart verlaengert die Woche nicht',
    );
  });

  // 2026-08-19 (vucko): Die Doppel-XP-Woche steckt jetzt in der BASIS des
  // Streak-Multiplikators (2,0 statt 1,0), nicht mehr in einem Nachschlag auf
  // die fertigen XP. wendeBonusAn reicht deshalb nur noch durch, sonst wuerde
  // die Woche zweimal zaehlen. Die Basis-Regel selbst prueft
  // test/services/streak_multiplikator_test.dart.
  test('abgelaufener Bonus laesst die XP unveraendert', () async {
    SharedPreferences.setMockInitialValues({
      'starter_paket_vergeben_v1': true,
      'starter_bonus_ende_v1': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
      'starter_aufgaben_erledigt_v1':
          '["tutorial","route","favorit","speichern","community"]',
    });
    await dienst.load();
    // Der abgelaufene Bonus schaltet die Basis des Multiplikators zurueck
    // auf 1,0. Eine eigene Verdopplungs-Methode gibt es seit dem 19.08.
    // nicht mehr, deshalb wird hier nur noch der Schalter geprueft.
    expect(dienst.doppelXpAktiv, isFalse);
  });

  test('der aktive Bonus meldet sich, rechnet aber nicht selbst', () async {
    SharedPreferences.setMockInitialValues({
      'starter_paket_vergeben_v1': true,
      'starter_bonus_ende_v1': DateTime.now()
          .add(const Duration(days: 3))
          .toIso8601String(),
      'starter_aufgaben_erledigt_v1':
          '["tutorial","route","favorit","speichern","community"]',
    });
    await dienst.load();
    // Frueher wurde hier 85 zu 170. Die Verdopplung liegt jetzt in der BASIS
    // des Streak-Multiplikators (2,0 statt 1,0); der Dienst sagt nur noch,
    // OB die Woche laeuft. Gerechnet wird ausschliesslich in
    // GamificationService.streakMultiplierForDays.
    expect(dienst.doppelXpAktiv, isTrue);
  });

  // ------------------------------------------------------------------
  // 2026-08-19: Das Startklar-Abzeichen kommt nachtraeglich an.
  // ------------------------------------------------------------------
  //
  // vucko: „das startklar abzeichen hat keiner." GEMESSEN am 19.08.:
  // badge_16 hatte 0 von 152 Profilen — auch die beiden Nutzer nicht, deren
  // Doppel-XP-Woche nachweislich lief. Die Vergabe haing allein am einmaligen
  // Ereignis paketFrischVerdient, und genau da verwarf die Datenbank noch
  // alles ab badge_15. Ein Ereignis kann man nicht nachholen, einen Zustand
  // schon.
  group('Startklar-Abzeichen aus dem Zustand', () {
    test('Bestandsnutzer mit den alten fuenf gilt weiterhin als verdient', () async {
      SharedPreferences.setMockInitialValues({
        'starter_paket_vergeben_v1': true,
        'starter_bonus_ende_v1': DateTime.now()
            .subtract(const Duration(days: 40))
            .toIso8601String(),
        'starter_aufgaben_erledigt_v1':
            '["tutorial","route","favorit","speichern","community"]',
      });
      await dienst.load();
      // Fuenf von acht — nach der Erweiterung NICHT mehr „alles erledigt".
      expect(dienst.erledigtAnzahl, 5);
      expect(dienst.alleErledigt, isFalse);
      // Trotzdem steht ihm das Abzeichen zu: er hatte das Paket bereits.
      expect(dienst.paketVerdient, isTrue);
    });

    test('frisch alle acht erledigt: verdient', () async {
      await dienst.load();
      expect(dienst.paketVerdient, isFalse);
      for (final a in StarterAufgabenService.aufgaben) {
        await dienst.markiere(a.id);
      }
      expect(dienst.paketVerdient, isTrue);
    });

    test('halb fertig: nicht verdient', () async {
      await dienst.load();
      await dienst.markiere('route');
      await dienst.markiere('community');
      expect(dienst.paketVerdient, isFalse);
    });
  });

  // ------------------------------------------------------------------
  // 2026-08-19: Die drei neuen Aufgaben werden aus dem Zustand abgeleitet.
  // ------------------------------------------------------------------
  group('Drei neue Aufgaben aus den Kennzahlen', () {
    test('ohne Post, ohne Fahrt: nichts erledigt', () async {
      await dienst.load();
      await dienst.synchronisiereAusKennzahlen(
        posts: 0,
        abgeschlosseneFahrten: 0,
        abgeschlosseneGruppenfahrten: 0,
      );
      expect(dienst.erledigt('post'), isFalse);
      expect(dienst.erledigt('runde'), isFalse);
      expect(dienst.erledigt('gruppenfahrt'), isFalse);
    });

    test('Post und Fahrt zaehlen, die Gruppenfahrt erst abgeschlossen', () async {
      await dienst.load();
      await dienst.synchronisiereAusKennzahlen(
        posts: 2,
        abgeschlosseneFahrten: 1,
        abgeschlosseneGruppenfahrten: 0,
      );
      expect(dienst.erledigt('post'), isTrue);
      expect(dienst.erledigt('runde'), isTrue);
      // „wo man abschliessen muss": eine bloss erstellte oder abgebrochene
      // Gruppenfahrt zaehlt ausdruecklich nicht.
      expect(dienst.erledigt('gruppenfahrt'), isFalse);

      await dienst.synchronisiereAusKennzahlen(
        posts: 2,
        abgeschlosseneFahrten: 1,
        abgeschlosseneGruppenfahrten: 1,
      );
      expect(dienst.erledigt('gruppenfahrt'), isTrue);
    });

    test('Nachzuegler: wer laengst gefahren ist, bekommt es gutgeschrieben', () async {
      SharedPreferences.setMockInitialValues({
        'starter_aufgaben_erledigt_v1': '["tutorial","route"]',
      });
      await dienst.load();
      await dienst.synchronisiereAusKennzahlen(
        posts: 7,
        abgeschlosseneFahrten: 12,
        abgeschlosseneGruppenfahrten: 3,
      );
      expect(dienst.erledigtAnzahl, 5);
      expect(dienst.erledigt('gruppenfahrt'), isTrue);
    });

    test('der einmal vergebene Bonus bleibt vergeben', () async {
      final ende = DateTime.now().add(const Duration(days: 4));
      SharedPreferences.setMockInitialValues({
        'starter_paket_vergeben_v1': true,
        'starter_bonus_ende_v1': ende.toIso8601String(),
        'starter_aufgaben_erledigt_v1':
            '["tutorial","route","favorit","speichern","community"]',
      });
      await dienst.load();
      expect(dienst.doppelXpAktiv, isTrue);

      // Die drei neuen Aufgaben treffen einen Bestandsnutzer.
      await dienst.synchronisiereAusKennzahlen(
        posts: 1,
        abgeschlosseneFahrten: 1,
        abgeschlosseneGruppenfahrten: 1,
      );
      expect(dienst.alleErledigt, isTrue);
      // Kein zweiter Timer, keine zweite Verleihung.
      expect(dienst.bonusEnde!.difference(ende).inSeconds.abs(), lessThan(2));
      expect(dienst.paketFrischVerdient.value, isFalse);
    });
  });

  group('Verdrahtung', () {
    test('keine nachtraegliche Verdopplung mehr im Code', () {
      // 2026-08-19 (vucko): Der Test stand vorher andersherum und verlangte
      // ZWEI wendeBonusAn-Aufrufe in cruise_mode_page.dart. Seit die
      // Doppel-XP-Woche in der BASIS des Streak-Multiplikators steckt
      // (GamificationService.basisMitDoppelXp = 2,0 statt 1,0), waere jede
      // zusaetzliche Verdopplung eine Doppelrechnung: Streak 3 auf 1000 XP
      // Distanz-Basis ergaebe 1000 * 1,3 * 2 = 2600 statt richtig
      // 1000 * 2,3 = 2300 XP.
      //
      // Die Methode ist deshalb ERSATZLOS entfernt und nicht nur entschaerft:
      // eine Methode, die nur durchreicht, laedt dazu ein, spaeter wieder
      // etwas hineinzuschreiben. Dieser Test schlaegt an, wenn sie
      // zurueckkommt.
      for (final pfad in const [
        'lib/presentation/pages/cruise_mode_page.dart',
        'lib/data/services/unterbrochene_fahrt_verbuchung.dart',
        'lib/data/services/starter_aufgaben_service.dart',
      ]) {
        final quelle = File(pfad).readAsStringSync();
        // Erwaehnungen in Kommentaren sind erlaubt, echte Aufrufe nicht.
        final zeilen = const LineSplitter().convert(quelle).where(
          (z) => z.contains('wendeBonusAn(') && !z.trimLeft().startsWith('//'),
        );
        expect(
          zeilen,
          isEmpty,
          reason:
              'In $pfad steht wieder ein echter wendeBonusAn-Aufruf. Die '
              'Doppel-XP-Woche wuerde damit zweimal zaehlen.',
        );
      }
    });

    test('die fuenf gemeldeten Andockstellen melden weiterhin', () {
      final dateien = {
        'tutorial': 'lib/presentation/widgets/app_tutorial_overlay.dart',
        'route': 'lib/presentation/pages/cruise_mode_page.dart',
        'favorit': 'lib/data/services/gespeicherte_adressen_service.dart',
        'speichern': 'lib/data/services/saved_routes_service.dart',
        'community': 'lib/presentation/pages/home_page.dart',
      };
      dateien.forEach((id, pfad) {
        expect(
          File(pfad).readAsStringSync().contains("markiere('$id')"),
          isTrue,
          reason: 'Andockstelle fuer "$id" fehlt in $pfad',
        );
      });
    });

    test('die Badge-Vergabe leitet badge_16 aus dem Zustand ab', () {
      final gam = File(
        'lib/data/services/gamification_service.dart',
      ).readAsStringSync();
      expect(
        gam.contains('starter.paketVerdient'),
        isTrue,
        reason:
            'ohne diese Ableitung haengt badge_16 wieder am einmaligen '
            'Ereignis und kann nie nachgeholt werden',
      );
      expect(gam.contains('Badge.starterBadgeId'), isTrue);
      expect(
        gam.contains('synchronisiereAusKennzahlen('),
        isTrue,
        reason: 'die drei neuen Aufgaben kommen aus denselben Kennzahlen',
      );
    });

    test('alle acht Aufgaben fuehren hin, keine tote Schaltflaeche', () {
      final karte = File(
        'lib/presentation/widgets/starter_paket_karte.dart',
      ).readAsStringSync();
      for (final a in StarterAufgabenService.aufgaben) {
        expect(
          karte.contains("case '${a.id}':"),
          isTrue,
          reason: 'die Zeile "${a.id}" hat keinen Zweig in _fuehreHin',
        );
      }
    });

    test('die Karte haengt auf dem Startbildschirm', () {
      expect(
        File(
          'lib/presentation/pages/home_content_page.dart',
        ).readAsStringSync().contains('StarterPaketKarte('),
        isTrue,
      );
    });
  });
}
