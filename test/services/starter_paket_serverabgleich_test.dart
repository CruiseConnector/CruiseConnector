import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-19 (gemessen): `starter_aufgaben_erledigt_v1`,
/// `starter_bonus_ende_v1` und `starter_paket_vergeben_v1` lagen
/// ausschliesslich in den SharedPreferences. Folge: Ein Geraetewechsel
/// loeschte die laufende Bonuswoche, und derselbe Account konnte auf einem
/// zweiten Geraet eine ZWEITE Bonuswoche bekommen, weil serverseitig nichts
/// blockte.
///
/// Seit Migration 20260819120000 stehen beide Werte auf `profiles`
/// (`starter_aufgaben`, `starter_bonus_ende`); der Trigger
/// `trg_guard_starter_bonus_ende` macht das Ende schreib-einmalig. Diese
/// Tests pruefen die Client-Seite der Zusammenfuehrung.
///
/// Vor der Aenderung waere jeder Test hier rot: `synchronisiereMitProfil`
/// gab es nicht.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dienst = StarterAufgabenService.instance;

  /// Ein Server-Profil im Speicher, das Lesen und Schreiben mitschreibt.
  late Map<String, dynamic> serverProfil;
  late List<Map<String, dynamic>> schreibZugriffe;

  void haengeServerAn() {
    dienst.profilLeserFuerTests = () async =>
        Map<String, dynamic>.from(serverProfil);
    dienst.profilSchreiberFuerTests = (werte) async {
      schreibZugriffe.add(werte);
      // Der Trigger auf `profiles` laesst ein einmal gesetztes Ende nicht
      // mehr aendern — hier nachgebildet, damit der Test dieselbe Regel
      // sieht wie die Datenbank.
      for (final eintrag in werte.entries) {
        if (eintrag.key == StarterAufgabenService.spalteBonusEnde &&
            serverProfil[StarterAufgabenService.spalteBonusEnde] != null) {
          continue;
        }
        serverProfil[eintrag.key] = eintrag.value;
      }
    };
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dienst.resetForTests();
    serverProfil = <String, dynamic>{
      StarterAufgabenService.spalteAufgaben: <String>[],
      StarterAufgabenService.spalteBonusEnde: null,
    };
    schreibZugriffe = [];
    haengeServerAn();
  });

  test('erledigte Aufgaben werden vereinigt, nichts geht verloren', () async {
    serverProfil[StarterAufgabenService.spalteAufgaben] = <String>[
      'tutorial',
      'community',
    ];
    SharedPreferences.setMockInitialValues({
      'starter_aufgaben_erledigt_v1': '["route","favorit"]',
    });
    await dienst.load();
    await dienst.synchronisiereMitProfil();

    expect(dienst.erledigtAnzahl, 4);
    for (final id in ['tutorial', 'community', 'route', 'favorit']) {
      expect(dienst.erledigt(id), isTrue, reason: '$id fehlt nach dem Abgleich');
    }
    // Und der Server kennt jetzt alle vier.
    expect(
      (serverProfil[StarterAufgabenService.spalteAufgaben] as List).toSet(),
      {'tutorial', 'community', 'route', 'favorit'},
    );
  });

  test('Geraetewechsel: die laufende Woche wird uebernommen', () async {
    final ende = DateTime.now().add(const Duration(days: 3));
    serverProfil[StarterAufgabenService.spalteBonusEnde] = ende
        .toUtc()
        .toIso8601String();
    serverProfil[StarterAufgabenService.spalteAufgaben] =
        StarterAufgabenService.aufgaben.map((a) => a.id).toList();

    // Frisches Geraet: leerer Geraetespeicher.
    await dienst.load();
    expect(dienst.doppelXpAktiv, isFalse);

    await dienst.synchronisiereMitProfil();

    expect(dienst.doppelXpAktiv, isTrue);
    expect(dienst.paketVergeben, isTrue);
    expect(dienst.bonusEnde!.difference(ende).inSeconds.abs(), lessThan(2));
  });

  test('zweites Geraet bekommt KEINE zweite Bonuswoche', () async {
    final altesEnde = DateTime.now().add(const Duration(days: 1));
    serverProfil[StarterAufgabenService.spalteBonusEnde] = altesEnde
        .toUtc()
        .toIso8601String();
    serverProfil[StarterAufgabenService.spalteAufgaben] =
        StarterAufgabenService.aufgaben.map((a) => a.id).toList();

    await dienst.load();
    await dienst.synchronisiereMitProfil();

    // Der Client hat das Ende NICHT neu gesetzt und auch nichts hochgeladen.
    expect(dienst.bonusEnde!.difference(altesEnde).inSeconds.abs(), lessThan(2));
    for (final zugriff in schreibZugriffe) {
      expect(
        zugriff.containsKey(StarterAufgabenService.spalteBonusEnde),
        isFalse,
        reason: 'ein zweites Geraet darf das Bonus-Ende nicht anfassen',
      );
    }
    // Kein neuer Countdown von sieben Tagen.
    expect(dienst.bonusVerbleibend.inDays, lessThan(2));
    expect(dienst.paketFrischVerdient.value, isFalse);
  });

  test('alles erledigt, Server kennt noch nichts: Woche startet und wandert '
      'hoch', () async {
    SharedPreferences.setMockInitialValues({
      'starter_aufgaben_erledigt_v1':
          '["tutorial","route","favorit","speichern","community","runde",'
          '"post","gruppenfahrt"]',
    });
    await dienst.load();
    expect(dienst.alleErledigt, isTrue);
    expect(dienst.bonusEnde, isNull);

    await dienst.synchronisiereMitProfil();

    expect(dienst.doppelXpAktiv, isTrue);
    expect(dienst.paketFrischVerdient.value, isTrue);
    expect(
      serverProfil[StarterAufgabenService.spalteBonusEnde],
      isNotNull,
      reason: 'ohne das Hochschreiben waere die Woche beim Geraetewechsel weg',
    );
  });

  test('ohne Anmeldung faellt der Abgleich still aus', () async {
    dienst.profilLeserFuerTests = () async => null;
    await dienst.load();
    await dienst.markiere('route');
    await dienst.synchronisiereMitProfil();
    expect(dienst.erledigtAnzahl, 1);
    expect(schreibZugriffe, isEmpty);
  });

  test('ein Serverfehler beim Lesen laesst den Geraetestand unberuehrt', () async {
    dienst.profilLeserFuerTests = () async => throw StateError('kein Netz');
    SharedPreferences.setMockInitialValues({
      'starter_aufgaben_erledigt_v1': '["route","favorit"]',
    });
    await dienst.load();
    await dienst.synchronisiereMitProfil();
    expect(dienst.erledigtAnzahl, 2);
  });
}
