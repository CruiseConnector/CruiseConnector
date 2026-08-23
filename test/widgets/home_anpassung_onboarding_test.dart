import 'dart:io';

import 'package:cruise_connect/data/services/app_tutorial_service.dart';
import 'package:cruise_connect/data/services/nutzer_prefs_schluessel.dart';
import 'package:cruise_connect/data/services/tutorial_ziel_registry.dart';
import 'package:cruise_connect/presentation/pages/home_content_page.dart';
import 'package:cruise_connect/presentation/widgets/ziel_hinweis_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-24 — Aufgabe 4.6 (Home-Bildschirm).
///
/// Vucko: „bei dem Home-Bildschirm ist uns aufgefallen, dass wenn man halt
/// mehr Routen speichern moechte, dass - wenn man die Homepage veraendert
/// hat - dass es dann irgendwie ein bisschen verbuggt ist." Und: „moechte ich
/// wirklich, dass beim Onboarding kurz die Ansicht so wie das alte Homescreen
/// ist, und dann, nachdem die Aufgabe abgeschlossen ist, es wieder zum
/// vorherigen wird - also wie es der Nutzer selber eingestellt hat."
Widget _huelle(Widget kind) => MaterialApp(home: Scaffold(body: kind));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------
  // 1. Das Fehlerbild, nachgestellt
  // ---------------------------------------------------------------------
  group('Fehlerbild: Spotlight ohne Ziel', () {
    testWidgets('MIT Anker: Blase klebt am Speichern-Knopf', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _huelle(
          Stack(
            children: [
              Positioned(
                top: 80,
                left: 20,
                child: Container(
                  key: TutorialZielRegistry.key(
                    TutorialZielRegistry.homeRouteSpeichern,
                  ),
                  width: 48,
                  height: 44,
                  color: Colors.red,
                ),
              ),
              const ZielHinweisOverlay(
                messenBis: Duration(milliseconds: 300),
                schritte: [
                  HinweisSchritt(
                    ziel: TutorialZielRegistry.homeRouteSpeichern,
                    titel: 'Route speichern',
                    text: 'Tippe hier auf der Empfehlungs-Karte.',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      final blase = tester.getCenter(
        find.byKey(const ValueKey('hinweis_blase')),
      );
      expect(blase.dy, lessThan(400), reason: 'Blase klebt am Ziel');
    });

    testWidgets('OHNE Anker (Kachel entfernt): kein Ring, Blase mittig', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _huelle(
          const Stack(
            children: [
              ZielHinweisOverlay(
                messenBis: Duration(milliseconds: 300),
                schritte: [
                  HinweisSchritt(
                    ziel: TutorialZielRegistry.homeRouteSpeichern,
                    titel: 'Route speichern',
                    text: 'Tippe hier auf der Empfehlungs-Karte.',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // GEMESSEN: kein Absturz, kein Haenger. Nach der Suche liegt die
      // Sprechblase mittig auf dem abgedunkelten Bildschirm und verweist auf
      // eine Karte, die es nicht mehr gibt.
      expect(tester.takeException(), isNull);
      expect(find.text('Route speichern'), findsOneWidget);
      final blase = tester.getCenter(
        find.byKey(const ValueKey('hinweis_blase')),
      );
      expect(blase.dy, greaterThan(380));
      expect(blase.dy, lessThan(420));
    });
  });

  // ---------------------------------------------------------------------
  // 2. Der Ersatzblock: die Kachel bleibt entfernbar, der Weg bleibt da
  // ---------------------------------------------------------------------
  group('HomeStartseiteRegeln.ersatzNoetig', () {
    test('Kachel da: nie ein Ersatz (kein doppelter Speichern-Knopf)', () {
      expect(
        HomeStartseiteRegeln.ersatzNoetig(
          heuteKachelSichtbar: true,
          unterbrocheneFahrt: true,
          aktiverTrip: true,
          speichernAufgabeOffen: true,
          empfehlungVorhanden: true,
        ),
        isFalse,
      );
    });

    test('Kachel entfernt + Aufgabe offen + Empfehlung: Ersatz', () {
      expect(
        HomeStartseiteRegeln.ersatzNoetig(
          heuteKachelSichtbar: false,
          unterbrocheneFahrt: false,
          aktiverTrip: false,
          speichernAufgabeOffen: true,
          empfehlungVorhanden: true,
        ),
        isTrue,
      );
    });

    test('Kachel entfernt, Aufgabe erledigt: kein Ersatz', () {
      expect(
        HomeStartseiteRegeln.ersatzNoetig(
          heuteKachelSichtbar: false,
          unterbrocheneFahrt: false,
          aktiverTrip: false,
          speichernAufgabeOffen: false,
          empfehlungVorhanden: true,
        ),
        isFalse,
      );
    });

    test('Unterbrochene Fahrt und Trip kommen IMMER durch', () {
      // Das ist der schwerere Teil des Befunds: mit der Kachel verschwanden
      // auch „Fahrt fortsetzen" und die Trip-Karte.
      expect(
        HomeStartseiteRegeln.ersatzNoetig(
          heuteKachelSichtbar: false,
          unterbrocheneFahrt: true,
          aktiverTrip: false,
          speichernAufgabeOffen: false,
          empfehlungVorhanden: false,
        ),
        isTrue,
      );
      expect(
        HomeStartseiteRegeln.ersatzNoetig(
          heuteKachelSichtbar: false,
          unterbrocheneFahrt: false,
          aktiverTrip: true,
          speichernAufgabeOffen: false,
          empfehlungVorhanden: false,
        ),
        isTrue,
      );
    });

    test('Aufgabe offen, aber keine Empfehlung: nichts zu speichern', () {
      expect(
        HomeStartseiteRegeln.ersatzNoetig(
          heuteKachelSichtbar: false,
          unterbrocheneFahrt: false,
          aktiverTrip: false,
          speichernAufgabeOffen: true,
          empfehlungVorhanden: false,
        ),
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------
  // 3. Onboarding zeigt Standard, danach wieder die eigene Anordnung
  // ---------------------------------------------------------------------
  group('OnboardingAnsichtSchalter', () {
    List<String> standard() => const ['xp', 'todayRoute', 'streak'];
    const eigene = ['streak', 'weekly'];

    test('Onboarding an: Standard sichtbar, Speichern gesperrt', () {
      final s = OnboardingAnsichtSchalter<List<String>>();
      expect(s.darfSpeichern, isTrue);
      final gezeigt = s.anwenden(
        onboardingLaeuft: true,
        aktuell: eigene,
        standard: standard,
      );
      expect(gezeigt, standard());
      expect(s.standardAktiv, isTrue);
      expect(
        s.darfSpeichern,
        isFalse,
        reason: 'die Standard-Anordnung darf nie in die Preferences',
      );
    });

    test('Onboarding aus: exakt die eigene Anordnung kommt zurueck', () {
      final s = OnboardingAnsichtSchalter<List<String>>();
      s.anwenden(
        onboardingLaeuft: true,
        aktuell: eigene,
        standard: standard,
      );
      final zurueck = s.anwenden(
        onboardingLaeuft: false,
        aktuell: standard(),
        standard: standard,
      );
      expect(zurueck, same(eigene));
      expect(s.standardAktiv, isFalse);
      expect(s.darfSpeichern, isTrue);
    });

    test('Mehrfaches Umschalten frisst die eigene Anordnung nicht', () {
      final s = OnboardingAnsichtSchalter<List<String>>();
      var gezeigt = eigene;
      for (var i = 0; i < 3; i++) {
        gezeigt = s.anwenden(
          onboardingLaeuft: true,
          aktuell: gezeigt,
          standard: standard,
        );
      }
      expect(gezeigt, standard());
      final zurueck = s.anwenden(
        onboardingLaeuft: false,
        aktuell: gezeigt,
        standard: standard,
      );
      expect(zurueck, same(eigene));
    });

    test('Layout, das WAEHREND des Onboardings geladen wird, geht nicht '
        'auf den Bildschirm, aber auch nicht verloren', () {
      final s = OnboardingAnsichtSchalter<List<String>>();
      s.anwenden(
        onboardingLaeuft: true,
        aktuell: standard(),
        standard: standard,
      );
      const vomGeraet = ['rangliste', 'xp'];
      expect(s.geladenesLayout(vomGeraet), isNull);
      final zurueck = s.anwenden(
        onboardingLaeuft: false,
        aktuell: standard(),
        standard: standard,
      );
      expect(zurueck, same(vomGeraet));
    });

    test('Ohne Onboarding wird ein geladenes Layout direkt angezeigt', () {
      final s = OnboardingAnsichtSchalter<List<String>>();
      const vomGeraet = ['rangliste'];
      expect(s.geladenesLayout(vomGeraet), same(vomGeraet));
    });
  });

  // ---------------------------------------------------------------------
  // 4. Nebenfund 1: Nutzerkennung im Preferences-Schluessel
  // ---------------------------------------------------------------------
  group('NutzerPrefsSchluessel', () {
    tearDown(() => NutzerPrefsSchluessel.nutzerIdFuerTests = null);

    test('ohne Konto bleibt der alte Schluessel', () {
      NutzerPrefsSchluessel.nutzerIdFuerTests = () => null;
      expect(NutzerPrefsSchluessel.fuer('home_dashboard_layout_v1'),
          'home_dashboard_layout_v1');
    });

    test('mit Konto haengt die Kennung dran', () {
      NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'user-a';
      expect(NutzerPrefsSchluessel.fuer('home_dashboard_layout_v1'),
          'home_dashboard_layout_v1::user-a');
    });

    test('Uebernahme: der erste Nutzer behaelt seine Anordnung', () async {
      SharedPreferences.setMockInitialValues({
        'home_dashboard_layout_v1': '[{"key":"streak"}]',
      });
      NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'user-a';
      final prefs = await SharedPreferences.getInstance();
      final key = await NutzerPrefsSchluessel.vorbereitet(
        prefs,
        'home_dashboard_layout_v1',
      );
      expect(key, 'home_dashboard_layout_v1::user-a');
      expect(prefs.getString(key), '[{"key":"streak"}]');
    });

    test('das ZWEITE Konto erbt die Anordnung des ersten NICHT', () async {
      SharedPreferences.setMockInitialValues({
        'home_dashboard_layout_v1': '[{"key":"streak"}]',
      });
      final prefs = await SharedPreferences.getInstance();

      NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'user-a';
      final keyA = await NutzerPrefsSchluessel.vorbereitet(
        prefs,
        'home_dashboard_layout_v1',
      );
      NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'user-b';
      final keyB = await NutzerPrefsSchluessel.vorbereitet(
        prefs,
        'home_dashboard_layout_v1',
      );

      expect(prefs.getString(keyA), '[{"key":"streak"}]');
      expect(prefs.getString(keyB), isNull,
          reason: 'user-b startet mit der Standard-Anordnung');
    });

    test('ein eigener Wert wird nie vom alten ueberschrieben', () async {
      SharedPreferences.setMockInitialValues({
        'home_dashboard_layout_v1': 'ALT',
        'home_dashboard_layout_v1::user-a': 'MEINS',
      });
      NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'user-a';
      final prefs = await SharedPreferences.getInstance();
      final key = await NutzerPrefsSchluessel.vorbereitet(
        prefs,
        'home_dashboard_layout_v1',
      );
      expect(prefs.getString(key), 'MEINS');
    });

    test('bool wird genauso uebernommen (Tutorial-Status)', () async {
      SharedPreferences.setMockInitialValues({
        'app_tutorial_v2_completed': true,
      });
      NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'user-a';
      final prefs = await SharedPreferences.getInstance();
      final key = await NutzerPrefsSchluessel.vorbereitet(
        prefs,
        'app_tutorial_v2_completed',
      );
      expect(prefs.getBool(key), isTrue);
    });
  });

  // ---------------------------------------------------------------------
  // 5. Der Schalter am Tutorial
  // ---------------------------------------------------------------------
  group('AppTutorialService: Onboarding-Ansicht', () {
    tearDown(() {
      NutzerPrefsSchluessel.nutzerIdFuerTests = null;
      AppTutorialService.onboardingAnsichtAktiv.value = false;
    });

    test('Tutorial offen: Standard-Ansicht an; abgeschlossen: wieder aus',
        () async {
      SharedPreferences.setMockInitialValues({});
      NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'user-a';

      await AppTutorialService.pruefeOnboardingAnsicht();
      expect(AppTutorialService.onboardingAnsichtAktiv.value, isTrue);

      await AppTutorialService.markCompleted();
      expect(AppTutorialService.onboardingAnsichtAktiv.value, isFalse);

      await AppTutorialService.pruefeOnboardingAnsicht();
      expect(AppTutorialService.onboardingAnsichtAktiv.value, isFalse);
    });

    test('zweites Konto auf demselben Handy bekommt sein eigenes Onboarding',
        () async {
      SharedPreferences.setMockInitialValues({});
      NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'user-a';
      await AppTutorialService.markCompleted();
      expect(await AppTutorialService.hasCompleted(), isTrue);

      NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'user-b';
      expect(await AppTutorialService.hasCompleted(), isFalse);
      await AppTutorialService.pruefeOnboardingAnsicht();
      expect(AppTutorialService.onboardingAnsichtAktiv.value, isTrue);
    });

    test('Wiederholung schaltet die Standard-Ansicht wieder an', () async {
      SharedPreferences.setMockInitialValues({});
      NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'user-a';
      await AppTutorialService.markCompleted();
      await AppTutorialService.requestReplay();
      expect(AppTutorialService.onboardingAnsichtAktiv.value, isTrue);
      expect(await AppTutorialService.hasCompleted(), isFalse,
          reason: 'der alte kontolose Wert darf nicht zurueckwandern');
    });
  });

  // ---------------------------------------------------------------------
  // 6. Verdrahtung in der Startseite
  // ---------------------------------------------------------------------
  group('Verdrahtung', () {
    final home = File(
      'lib/presentation/pages/home_content_page.dart',
    ).readAsStringSync();

    test('waehrend der Onboarding-Ansicht wird NICHTS gespeichert', () {
      final i = home.indexOf('Future<void> _persistDashboardLayout() async {');
      expect(i, greaterThan(0));
      final rumpf = home.substring(i, i + 900);
      expect(rumpf.contains('if (!_onboardingAnsicht.darfSpeichern) return;'),
          isTrue);
      // ... und der Rueckweg beim Abschluss haengt am Tutorial-Schalter.
      expect(
        home.contains(
          'AppTutorialService.onboardingAnsichtAktiv.addListener(',
        ),
        isTrue,
      );
      expect(home.contains('AppTutorialService.pruefeOnboardingAnsicht()'),
          isTrue);
    });

    test('kein Schluessel ohne Nutzerkennung mehr', () {
      for (final basis in const [
        '_dashboardPrefsKey',
        '_badgeHuntPrefsKey',
        '_homeSnapshotPrefsKey',
      ]) {
        expect(
          home.contains('NutzerPrefsSchluessel.vorbereitet(prefs, $basis)') ||
              home.contains(
                'NutzerPrefsSchluessel.vorbereitet(\n        prefs,\n        $basis,\n      )',
              ) ||
              home.contains('vorbereitet(prefs, $basis)'),
          isTrue,
          reason: '$basis laeuft nicht ueber NutzerPrefsSchluessel',
        );
      }
      expect(home.contains("prefs.getString('home_snapshot_v1')"), isFalse);
    });

    test('der Speichern-Anker wird genau einmal vergeben', () {
      expect(
        RegExp('TutorialZielRegistry.homeRouteSpeichern')
            .allMatches(home)
            .length,
        1,
        reason: 'ein GlobalKey darf nur an einer Stelle im Baum haengen',
      );
      expect(home.contains('tutorialAnker: _heuteKachelTraegtAnker'), isTrue);
      expect(home.contains('_buildErsatzFuerHeuteKachel()'), isTrue);
    });

    test('Tutorial-Anker der Starter-Karte: Bedingung deckt sich mit der '
        'Karte selbst', () {
      final karte = File(
        'lib/presentation/widgets/starter_paket_karte.dart',
      ).readAsStringSync();
      // Quelle der Wahrheit in der Karte ...
      expect(karte.contains('if (!dienst.isLoaded) return const SizedBox.shrink();'),
          isTrue);
      expect(karte.contains('dienst.paketVergeben && !dienst.doppelXpAktiv'),
          isTrue);
      // ... gespiegelt auf der Startseite.
      expect(
        home.contains(
          'dienst.isLoaded && !(dienst.paketVergeben && !dienst.doppelXpAktiv)',
        ),
        isTrue,
      );
      expect(
        home.contains('TutorialZielRegistry.key(TutorialZielRegistry.starterKarte)'),
        isTrue,
      );
    });

    test('„Home anpassen" ist waehrend der Onboarding-Ansicht zu', () {
      final i = home.indexOf('void _openDashboardEditor() {');
      final rumpf = home.substring(i, i + 700);
      expect(rumpf.contains('if (_onboardingAnsicht.standardAktiv) {'), isTrue);
      expect(
        RegExp(r'maxSimultaneousDrags: _onboardingAnsicht\.standardAktiv \? 0 : null')
            .allMatches(home)
            .length,
        2,
        reason: 'beide Zieh-Wege in den Bearbeiten-Modus sind gesperrt',
      );
    });
  });
}
