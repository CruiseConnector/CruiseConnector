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

  test('fuenf Aufgaben, alle ohne Fahrt erfuellbar', () {
    expect(StarterAufgabenService.aufgaben, hasLength(5));
    final ids = StarterAufgabenService.aufgaben.map((a) => a.id).toSet();
    expect(ids, {'tutorial', 'route', 'favorit', 'speichern', 'community'});
  });

  test('markiere ist idempotent und zaehlt sauber', () async {
    await dienst.load();
    await dienst.markiere('route');
    await dienst.markiere('route');
    expect(dienst.erledigtAnzahl, 1);
    expect(dienst.alleErledigt, isFalse);
  });

  test('alle fuenf erledigt: Paket einmalig, Timer startet', () async {
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

  test('abgelaufener Bonus verdoppelt nichts mehr', () async {
    SharedPreferences.setMockInitialValues({
      'starter_paket_vergeben_v1': true,
      'starter_bonus_ende_v1': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
      'starter_aufgaben_erledigt_v1':
          '["tutorial","route","favorit","speichern","community"]',
    });
    await dienst.load();
    expect(dienst.doppelXpAktiv, isFalse);
    expect(dienst.wendeBonusAn(100), 100);
  });

  test('aktiver Bonus verdoppelt exakt', () async {
    SharedPreferences.setMockInitialValues({
      'starter_paket_vergeben_v1': true,
      'starter_bonus_ende_v1': DateTime.now()
          .add(const Duration(days: 3))
          .toIso8601String(),
      'starter_aufgaben_erledigt_v1':
          '["tutorial","route","favorit","speichern","community"]',
    });
    await dienst.load();
    expect(dienst.wendeBonusAn(85), 170);
  });

  group('Verdrahtung', () {
    test('die XP-Vergabe laeuft durch den Bonus', () {
      final cruise = File(
        'lib/presentation/pages/cruise_mode_page.dart',
      ).readAsStringSync();
      final treffer = RegExp(
        r'wendeBonusAn\(',
      ).allMatches(cruise).length;
      expect(
        treffer,
        2,
        reason:
            'beide Vergabestellen (Fahrtende und Aufzeichnung) muessen durch '
            'die eine Regelstelle laufen',
      );
    });

    test('alle fuenf Andockstellen melden', () {
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
