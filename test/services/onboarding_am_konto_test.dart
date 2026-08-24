import 'package:cruise_connect/data/services/app_tutorial_service.dart';
import 'package:cruise_connect/data/services/nutzer_prefs_schluessel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-24 — Aufgabe 1 und 2 aus Vuckos Auftrag vom selben Tag.
///
/// Aufgabe 1, woertlich: „aber nicht das wenn man die app loescht und sie
/// nochmal holt das man wieder das tutorial spielen kann das tutorial bzw. das
/// onboarding soll einmal pro account absolviert werden".
///
/// Aufgabe 2, woertlich: „lass jeden account mit der neuen version vorerst das
/// tutorial durchspielen ich muss es testen".
///
/// Beides zusammen: EINMAL fuer alle zuruecksetzen, danach haengt der
/// Abschluss am Konto und kommt nie wieder.
///
/// VOR DER AENDERUNG waeren alle Tests hier rot: `hasCompleted` las
/// ausschliesslich die SharedPreferences, es gab weder eine Konto-Abfrage noch
/// eine Ruecksetz-Generation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const nutzerA = 'aaaaaaaa-1111-2222-3333-444444444444';

  /// Wie oft der Server gefragt wurde — fuer den Nachweis, dass die Antwort
  /// gemerkt und nicht bei jedem Aufruf neu geholt wird.
  late int abfragen;
  late List<String> schreibZugriffe;

  void haengeKontoAn({required bool abgeschlossen, Duration? verzoegerung}) {
    AppTutorialService.kontoLeserFuerTests = (id) async {
      abfragen += 1;
      if (verzoegerung != null) await Future<void>.delayed(verzoegerung);
      return abgeschlossen;
    };
    AppTutorialService.kontoSchreiberFuerTests = (id) async {
      schreibZugriffe.add(id);
    };
  }

  setUp(() {
    abfragen = 0;
    schreibZugriffe = <String>[];
    SharedPreferences.setMockInitialValues({});
    NutzerPrefsSchluessel.nutzerIdFuerTests = () => nutzerA;
    AppTutorialService.resetKontoGedaechtnisFuerTests();
    AppTutorialService.kontoLeserFuerTests = null;
    AppTutorialService.kontoSchreiberFuerTests = null;
  });

  tearDown(() {
    NutzerPrefsSchluessel.nutzerIdFuerTests = null;
    AppTutorialService.kontoLeserFuerTests = null;
    AppTutorialService.kontoSchreiberFuerTests = null;
    AppTutorialService.resetKontoGedaechtnisFuerTests();
  });

  group('Aufgabe 1 — der Abschluss haengt am Konto', () {
    test('Neuinstallation: leeres Handy, aber das Konto ist durch', () async {
      // Genau der Fall aus Vuckos Satz: App geloescht, neu geholt. Auf dem
      // Geraet steht nichts mehr, das Konto weiss es trotzdem.
      haengeKontoAn(abgeschlossen: true);

      expect(await AppTutorialService.hasCompleted(), isTrue);
      expect(abfragen, 1);
    });

    test('die Antwort wird ABGEWARTET, das Tutorial springt nicht los',
        () async {
      // Vucko: „Bis die Antwort da ist, darf das Tutorial NICHT losspringen,
      // sonst sieht der Nutzer es kurz und es verschwindet wieder."
      haengeKontoAn(
        abgeschlossen: true,
        verzoegerung: const Duration(milliseconds: 120),
      );

      final begonnen = DateTime.now();
      final ergebnis = await AppTutorialService.hasCompleted();
      final gedauert = DateTime.now().difference(begonnen);

      expect(ergebnis, isTrue);
      expect(
        gedauert.inMilliseconds,
        greaterThanOrEqualTo(100),
        reason: 'hasCompleted hat nicht auf den Server gewartet',
      );
    });

    test('die Antwort wird gemerkt — kein Netzweg bei jedem Aufruf', () async {
      haengeKontoAn(abgeschlossen: true);

      await AppTutorialService.hasCompleted();
      await AppTutorialService.hasCompleted();
      await AppTutorialService.hasCompleted();

      expect(abfragen, 1);
    });

    test('frisches Konto: der Server sagt nein, die Tour laeuft', () async {
      haengeKontoAn(abgeschlossen: false);
      expect(await AppTutorialService.hasCompleted(), isFalse);
    });

    test('markCompleted schreibt den Abschluss ans Konto', () async {
      haengeKontoAn(abgeschlossen: false);

      await AppTutorialService.markCompleted();
      // markCompleted schreibt bewusst unawaited weiter.
      await Future<void>.delayed(Duration.zero);

      expect(schreibZugriffe, [nutzerA]);
      expect(await AppTutorialService.hasCompleted(), isTrue);
    });

    test('ein Netzfehler wird NICHT als „abgeschlossen" gemerkt', () async {
      var versuche = 0;
      AppTutorialService.kontoLeserFuerTests = (id) async {
        versuche += 1;
        if (versuche == 1) throw StateError('kein Netz');
        return true;
      };

      expect(await AppTutorialService.hasCompleted(), isFalse);
      // Der zweite Aufruf fragt WIRKLICH noch einmal.
      expect(await AppTutorialService.hasCompleted(), isTrue);
      expect(versuche, 2);
    });

    test('„Tutorial nochmal ansehen" schlaegt die Konto-Antwort', () async {
      // Sonst waere die Schaltflaeche ab heute tot: der Server sagt zu Recht
      // „abgeschlossen" und das Overlay ginge sofort wieder zu.
      haengeKontoAn(abgeschlossen: true);
      expect(await AppTutorialService.hasCompleted(), isTrue);

      await AppTutorialService.requestReplay();
      expect(await AppTutorialService.hasCompleted(), isFalse);

      // Nach dem zweiten Durchlauf gilt wieder der Abschluss.
      await AppTutorialService.markCompleted();
      expect(await AppTutorialService.hasCompleted(), isTrue);
    });
  });

  group('Aufgabe 2 — einmalig fuer alle zuruecksetzen', () {
    /// Der Zustand eines Bestandsnutzers VOR dem Update: Tutorial auf dem
    /// Geraet als gesehen markiert, Starter-Aufgaben und Bonuswoche laufen.
    Map<String, Object> bestandsnutzer() => <String, Object>{
          AppTutorialService.completedKey: true,
          '${AppTutorialService.completedKey}::$nutzerA': true,
          'starter_aufgaben_erledigt_v1': '["tutorial","route","community"]',
          'starter_paket_vergeben_v1': true,
          'starter_bonus_ende_v1': '2026-08-31T12:00:00.000',
          AppTutorialService.rewardClaimedKey: true,
        };

    test('greift genau EINMAL und danach nie wieder', () async {
      SharedPreferences.setMockInitialValues(bestandsnutzer());
      haengeKontoAn(abgeschlossen: false);

      // Erster Start mit der neuen Version: die Tour kommt noch einmal.
      expect(await AppTutorialService.hasCompleted(), isFalse);

      // Der Nutzer spielt sie durch.
      await AppTutorialService.markCompleted();
      expect(await AppTutorialService.hasCompleted(), isTrue);

      // Und ab jetzt bleibt es dabei — auch nach weiteren Starts.
      expect(await AppTutorialService.hasCompleted(), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(
          NutzerPrefsSchluessel.fuer(AppTutorialService.ruecksetzGenerationKey),
        ),
        AppTutorialService.ruecksetzGeneration,
      );
    });

    test('reisst weder Boost noch die anderen Aufgaben mit', () async {
      // Vucko: „Das Zuruecksetzen darf NICHT den Boost oder die schon
      // erledigten anderen Aufgaben mitreissen. Nur das Tutorial."
      SharedPreferences.setMockInitialValues(bestandsnutzer());
      haengeKontoAn(abgeschlossen: false);

      await AppTutorialService.hasCompleted();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('starter_aufgaben_erledigt_v1'),
        '["tutorial","route","community"]',
      );
      expect(prefs.getBool('starter_paket_vergeben_v1'), isTrue);
      expect(prefs.getString('starter_bonus_ende_v1'), isNotNull);
      // Auch der Merker fuer die 125 XP bleibt: die Belohnung gibt es einmal.
      expect(prefs.getBool(AppTutorialService.rewardClaimedKey), isTrue);
    });

    test('wer die Tour auf einem anderen Geraet schon nachgeholt hat, '
        'bekommt sie nicht noch einmal', () async {
      // Zweites Geraet, Bestandsdaten lokal, aber das Konto ist inzwischen
      // durch. Das Zuruecksetzen raeumt den Geraete-Merker ab — die
      // Konto-Antwort haelt die Tour trotzdem zu.
      SharedPreferences.setMockInitialValues(bestandsnutzer());
      haengeKontoAn(abgeschlossen: true);

      expect(await AppTutorialService.hasCompleted(), isTrue);
    });
  });
}
