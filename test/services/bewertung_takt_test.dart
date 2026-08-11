import 'dart:io';

import 'package:cruise_connect/data/services/ride_rating_prompt_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-11 (vucko): „Nach jeder dritten Runde, die man gefahren ist,
/// alleine oder in der Gruppe, nach diesem Update MUESSEN Popups kommen, dass
/// wir ein kleines Team sind und eine Rezension uns mega weiterbringen wuerde.
/// Dieser Mechanismus muss unbedingt noch drauf sein."
///
/// Zwei Dinge waren vorher anders und haben genau das verhindert:
///
///  1. Der Takt hing an ROUTEN-EREIGNISSEN, nicht an Fahrten. Mitgezaehlt hat
///     auch jede blosse Routensuche. Wer dreimal suchte, ohne zu fahren, bekam
///     das Popup; wer dreimal fuhr, unter Umstaenden nicht. Jetzt zaehlen
///     ausschliesslich abgeschlossene Fahrten — solo wie Gruppe gleich.
///
///  2. Wer einmal „nicht mehr fragen" gewaehlt hatte, war fuer immer stumm —
///     auch nach Updates, die die App spuerbar besser machen. Ein Update ist
///     jetzt ein neuer Anlauf.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const version = '1.5.13';
  const build = '95';
  const stempel = '$version+$build';

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'Cruise Connector',
      packageName: 'com.vucko.cruiserconnect',
      version: version,
      buildNumber: build,
      buildSignature: '',
      installerStore: null,
    );
  });

  /// Der Zustand NACH dem ersten Popup: Zyklus laeuft, Stand ist vermerkt.
  Map<String, Object> imLaufendenZyklus({required int fahrten}) => {
    'ride_rating_reset_version_v1': stempel,
    'ride_rating_completed_rides_v1': fahrten,
    'ride_rating_prompts_shown_v1': 1,
    'ride_rating_events_at_last_prompt_v1': 0,
  };

  group('Der Takt haengt an Fahrten, nicht an Suchvorgaengen', () {
    test('nach zwei Fahrten noch nicht', () async {
      SharedPreferences.setMockInitialValues(imLaufendenZyklus(fahrten: 2));
      expect(await RideRatingPromptService.instance.shouldPrompt(), isFalse);
    });

    test('nach der dritten Fahrt kommt es', () async {
      SharedPreferences.setMockInitialValues(imLaufendenZyklus(fahrten: 3));
      expect(
        await RideRatingPromptService.instance.shouldPrompt(),
        isTrue,
        reason: 'vucko: „nach jeder dritten Runde MUESSEN Popups kommen"',
      );
    });

    test('drei Routensuchen ohne Fahrt loesen nichts aus', () async {
      SharedPreferences.setMockInitialValues({
        ...imLaufendenZyklus(fahrten: 0),
        'ride_rating_route_events_v1': 9,
      });
      expect(
        await RideRatingPromptService.instance.shouldPrompt(),
        isFalse,
        reason: 'gefahren werden muss, nicht gesucht',
      );
    });

    test('nach dem Popup zaehlt der Takt von vorn', () async {
      // Stand 5 Fahrten, letztes Popup bei 3 → erst zwei Fahrten her.
      SharedPreferences.setMockInitialValues({
        'ride_rating_reset_version_v1': stempel,
        'ride_rating_completed_rides_v1': 5,
        'ride_rating_prompts_shown_v1': 1,
        'ride_rating_events_at_last_prompt_v1': 3,
      });
      expect(await RideRatingPromptService.instance.shouldPrompt(), isFalse);

      // Eine Fahrt spaeter sind es drei.
      SharedPreferences.setMockInitialValues({
        'ride_rating_reset_version_v1': stempel,
        'ride_rating_completed_rides_v1': 6,
        'ride_rating_prompts_shown_v1': 1,
        'ride_rating_events_at_last_prompt_v1': 3,
      });
      expect(await RideRatingPromptService.instance.shouldPrompt(), isTrue);
    });

    test('markPromptShown merkt sich den FAHRTEN-Stand', () async {
      SharedPreferences.setMockInitialValues({
        'ride_rating_reset_version_v1': stempel,
        'ride_rating_completed_rides_v1': 7,
        'ride_rating_route_events_v1': 40, // darf keine Rolle spielen
        'ride_rating_prompts_shown_v1': 1,
        'ride_rating_events_at_last_prompt_v1': 4,
      });
      await RideRatingPromptService.instance.markPromptShown();
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt('ride_rating_events_at_last_prompt_v1'),
        7,
        reason:
            'wuerde hier der Ereignis-Stand (40) landen, kaeme das naechste '
            'Popup erst nach 43 Ereignissen statt nach 3 Fahrten',
      );
    });
  });

  // Der teuerste Fehler an diesem Mechanismus war kein Rechenfehler, sondern
  // eine Zaehlstelle zu viel.
  //
  // Am 2026-08-11 wurde ein zweiter registerCompletedRide()-Aufruf ergaenzt,
  // weil eine Suche nach dem falschen Methodennamen die bestehende Stelle
  // nicht fand. Danach zaehlte jede Fahrt doppelt: Das Popup kam nach jeder
  // ZWEITEN Runde statt nach jeder dritten. Kein Unit-Test konnte das sehen —
  // sie rufen den Dienst ja selbst auf und kennen die Aufrufkette in
  // cruise_mode_page.dart nicht.
  //
  // Die erste Fassung dieser Wache pruefte nur, DASS irgendwo gezaehlt wird.
  // Genau daran ist sie vorbeigelaufen. Jetzt zaehlt sie die Aufrufstellen.
  test('eine Fahrt wird an GENAU EINER Stelle gezaehlt', () {
    final quelle = File(
      'lib/presentation/pages/cruise_mode_page.dart',
    ).readAsStringSync();

    final aufrufe = RegExp(
      r'RideRatingPromptService\.instance\.registerCompletedRide\(\)',
    ).allMatches(quelle).length;

    expect(
      aufrufe,
      1,
      reason:
          'Bei 0 bleibt der Fahrten-Zaehler fuer immer auf 0 und das Popup '
          'kommt nie. Bei 2 zaehlt jede Fahrt doppelt und das Popup kommt '
          'nach jeder zweiten statt nach jeder dritten Runde.',
    );

    // Und zwar in _resetAfterCompletion — dem Sammelpunkt, an dem Speichern
    // UND Verwerfen zusammenlaufen und an dem der Abbruchpfad „zu wenig
    // aufgezeichnet" bewusst mit zaehltAlsAbgeschlosseneFahrt: false
    // ausgenommen ist. Wandert der Aufruf woanders hin, zaehlt entweder ein
    // Weg nicht mit oder eine leere Aufzeichnung zaehlt faelschlich mit.
    final start = quelle.indexOf('void _resetAfterCompletion(');
    expect(start, greaterThan(0), reason: '_resetAfterCompletion nicht mehr da');
    final sammelpunkt = quelle.substring(start, start + 600);
    expect(
      sammelpunkt.contains('registerCompletedRide()'),
      isTrue,
      reason: 'die Zaehlung gehoert in _resetAfterCompletion',
    );
  });

  // Die Ueberschrift des Blattes hiess fest „Erste Fahrt geschafft". Solange
  // das Popup nur einmal im Leben kam, stimmte das. Seit es nach jeder dritten
  // Runde wiederkommt, behauptet die App beim vierten, siebten, zehnten Mal
  // etwas sichtbar Falsches.
  group('Die Ueberschrift passt zum Anlass', () {
    test('vor dem ersten Popup ist es die erste Fahrt', () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        await RideRatingPromptService.instance.wurdeSchonGefragt(),
        isFalse,
      );
    });

    test('nach dem ersten Popup nicht mehr', () async {
      SharedPreferences.setMockInitialValues({
        'ride_rating_prompts_shown_v1': 1,
      });
      expect(
        await RideRatingPromptService.instance.wurdeSchonGefragt(),
        isTrue,
      );
    });

    test('das Blatt bietet beide Ueberschriften an', () {
      final quelle = File(
        'lib/presentation/widgets/ride_rating_sheet.dart',
      ).readAsStringSync();
      expect(quelle.contains("'Erste Fahrt geschafft'"), isTrue);
      expect(quelle.contains("'Wieder eine Runde geschafft'"), isTrue);
      // Und der Kern der Botschaft steht in BEIDEN Faellen darunter.
      expect(
        quelle.contains('winzigen Team'),
        isTrue,
        reason: 'vucko: „dass wir ein kleines Team sind"',
      );
      expect(
        quelle.contains('sind Bewertungen'),
        isTrue,
        reason: 'vucko: „eine Rezension uns mega weiterbringen wuerde"',
      );
    });

    test('home_page liest den Stand VOR dem Hochzaehlen', () {
      final quelle = File(
        'lib/presentation/pages/home_page.dart',
      ).readAsStringSync();
      final vorher = quelle.indexOf('wurdeSchonGefragt()');
      final nachher = quelle.indexOf('markPromptShown()');
      expect(vorher, greaterThan(0));
      expect(
        vorher,
        lessThan(nachher),
        reason:
            'umgekehrt waere schon das allererste Popup „nicht das erste" und '
            'die Ueberschrift von Anfang an falsch',
      );
    });
  });

  group('Ein Update ist ein neuer Anlauf', () {
    test('„nicht mehr fragen" von frueher blockiert nicht ewig', () async {
      SharedPreferences.setMockInitialValues({
        'ride_rating_settled_v1': true,
        'ride_rating_reset_version_v1': '1.5.0+70', // alte Version
        'ride_rating_completed_rides_v1': 12,
        'ride_rating_prompts_shown_v1': 4,
      });

      // Der erste Aufruf setzt zurueck. Danach zaehlt der Takt ab jetzt.
      await RideRatingPromptService.instance.shouldPrompt();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('ride_rating_settled_v1'), isFalse);
      expect(prefs.getString('ride_rating_reset_version_v1'), stempel);
      expect(
        prefs.getInt('ride_rating_events_at_last_prompt_v1'),
        12,
        reason:
            'der Takt beginnt beim aktuellen Fahrtenstand — sonst kaeme das '
            'Popup sofort beim ersten Start nach dem Update',
      );
    });

    test('drei Fahrten nach dem Update loesen dann wieder aus', () async {
      SharedPreferences.setMockInitialValues({
        'ride_rating_settled_v1': true,
        'ride_rating_reset_version_v1': '1.5.0+70',
        'ride_rating_completed_rides_v1': 12,
        'ride_rating_prompts_shown_v1': 4,
      });
      // Zuruecksetzen ausloesen.
      await RideRatingPromptService.instance.shouldPrompt();

      // Drei Fahrten weiter.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('ride_rating_completed_rides_v1', 15);
      expect(await RideRatingPromptService.instance.shouldPrompt(), isTrue);
    });

    test(
      'innerhalb derselben Version wird genau EINMAL zurueckgesetzt',
      () async {
        SharedPreferences.setMockInitialValues({
          'ride_rating_settled_v1': true,
          'ride_rating_reset_version_v1': stempel,
          'ride_rating_completed_rides_v1': 3,
          'ride_rating_prompts_shown_v1': 1,
        });
        expect(
          await RideRatingPromptService.instance.shouldPrompt(),
          isFalse,
          reason:
              'wer in DIESER Version bereits bewertet hat, wird nicht erneut '
              'gefragt — sonst nervt das Popup nach jeder dritten Fahrt fuer '
              'immer weiter',
        );
      },
    );
  });
}
