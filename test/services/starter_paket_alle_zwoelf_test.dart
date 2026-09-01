import 'dart:convert';
import 'dart:io';

import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/presentation/widgets/starter_paket_karte.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-25, Vucko in einer Nachricht:
///
///   „aktiviere einmalig egal ob ich es schon gemacht habe oder nicht fuer
///    jeden nutzer der die app schon hat und der die app erst zukuenftig
///    herunterlaedt, dass man das onboarding machen muss und dafuer kein
///    Badge bekommst und es soll passend sein dafuer weil ich jetzt nur das
///    tutorial bekommen habe und nicht das onboarding und es soll darstehen
///    beim onboarding widget wie weit ich schon bin und als oberstes widget
///    bis ich es abgeschlossen habe also einfach alle funktionen einmal
///    durchgetestet haben die es in der app gibt."
///
/// DER GEMESSENE BEFUND, der diesen Auftrag ausgeloest hat (25.08.,
/// Produktivdatenbank, 199 Profile):
///
///   Profile gesamt                                     199
///   davon mit badge_58                                   1   (Vucko)
///   davon mit einer nicht leeren Aufgabenliste            1   (dasselbe)
///   dessen Stand                                     10/12   (offen:
///                                                     hashtag,
///                                                     gruppenfahrt)
///   dessen starter_bonus_ende                     22.08.     (abgelaufen)
///
/// Also: Er traegt badge_58 fuer die Fuehrung mit den Leuchtkreisen allein,
/// und die Karte mit der Aufgabenliste war fuer ihn unsichtbar, weil
/// „paketVergeben und Bonus vorbei" auf ihn zutraf — mit zwei offenen
/// Aufgaben. Beides ist hier festgenagelt.
void main() {
  final dienst = StarterAufgabenService.instance;

  /// Die zehn Aufgaben, die Vuckos Profil am 25.08. wirklich erledigt hatte.
  const vuckosZehn = <String>[
    'abzeichen',
    'community',
    'favorit',
    'garage',
    'km50',
    'post',
    'route',
    'runde',
    'speichern',
    'tutorial',
  ];

  List<String> alleZwoelf() =>
      StarterAufgabenService.aufgaben.map((a) => a.id).toList();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dienst.resetForTests();
  });

  group('Die zweite Schwelle: alle zwoelf', () {
    test('acht ist der Boost, zwoelf ist „alles durchgetestet"', () async {
      await dienst.load();
      await dienst.markiereAlle(alleZwoelf().take(8));

      expect(dienst.erledigtAnzahl, 8);
      expect(
        dienst.boostErreicht,
        isTrue,
        reason: 'Die Boost-Schwelle bleibt bei acht — sie ist der Preis fuer '
            'die Bonuswoche und muss erreichbar bleiben.',
      );
      expect(
        dienst.alleAufgabenErledigt,
        isFalse,
        reason: 'Mit acht von zwoelf hat man vier Funktionen der App noch nie '
            'benutzt.',
      );

      await dienst.markiereAlle(alleZwoelf());
      expect(dienst.erledigtAnzahl, StarterAufgabenService.aufgaben.length);
      expect(dienst.alleAufgabenErledigt, isTrue);
    });

    test('der Abschluss-Melder feuert genau einmal, bei der zwoelften', () async {
      await dienst.load();
      var meldungen = 0;
      void zaehle() {
        if (dienst.alleAufgabenFrischErledigt.value) {
          meldungen++;
          dienst.alleAufgabenFrischErledigt.value = false;
        }
      }

      dienst.alleAufgabenFrischErledigt.addListener(zaehle);
      addTearDown(() => dienst.alleAufgabenFrischErledigt.removeListener(zaehle));

      await dienst.markiereAlle(alleZwoelf().take(11));
      expect(meldungen, 0, reason: 'elf von zwoelf ist nicht fertig');

      await dienst.markiereAlle(alleZwoelf());
      expect(meldungen, 1);

      // Erneute Meldungen derselben Aufgaben duerfen NICHT nochmal feuern,
      // sonst zeigte die Karte die Verleihung bei jedem Sync erneut.
      await dienst.markiereAlle(alleZwoelf());
      await dienst.markiereAlle(['tutorial']);
      expect(meldungen, 1);
    });

    test('auch der Server-Abgleich kann die zwoelfte bringen (Geraetewechsel)',
        () async {
      SharedPreferences.setMockInitialValues({
        'starter_aufgaben_erledigt_v1': jsonEncode(vuckosZehn),
        // 2026-08-25: Der Zaehler steht auf „schon gelaufen". Ohne ihn wuerde
        // die einmalige Ruecksetzung (vucko: „jeder soll die aufgaben alle
        // nochmal machen") hier zuschlagen und vier Aufgaben entfernen — der
        // Fall misst aber den GERAETEWECHSEL, nicht die Ruecksetzung.
        // Deren eigene Faelle stehen in starter_paket_serverabgleich_test.dart.
        'starter_aufgaben_ruecksetz_generation':
            StarterAufgabenService.ruecksetzGeneration,
      });
      dienst.resetForTests();

      var gemeldet = false;
      void merke() => gemeldet |= dienst.alleAufgabenFrischErledigt.value;
      dienst.alleAufgabenFrischErledigt.addListener(merke);
      addTearDown(() => dienst.alleAufgabenFrischErledigt.removeListener(merke));

      // Das andere Handy hat die zwei fehlenden erledigt.
      dienst.profilLeserFuerTests = () async => {
            StarterAufgabenService.spalteAufgaben: alleZwoelf(),
            StarterAufgabenService.spalteBonusEnde: null,
          };
      dienst.profilSchreiberFuerTests = (_) async {};

      await dienst.synchronisiereMitProfil();

      expect(dienst.alleAufgabenErledigt, isTrue);
      expect(
        gemeldet,
        isTrue,
        reason: 'Sonst kaeme badge_58 auf dem neuen Handy nie an.',
      );
    });
  });

  group('badge_58 haengt an der ganzen Liste, nicht am Tutorial', () {
    test('die Vergabe fragt alleAufgabenErledigt ab', () {
      final quelle =
          File('lib/data/services/gamification_service.dart').readAsStringSync();
      final vergabe =
          quelle.indexOf('currentlyQualifiedBadges.add(alleAufgabenBadgeId)');
      expect(vergabe, greaterThan(0));
      final bedingung =
          quelle.substring(quelle.lastIndexOf('if (', vergabe), vergabe);
      expect(bedingung, contains('starter.alleAufgabenErledigt'));
      expect(bedingung, isNot(contains("erledigt('tutorial')")));
    });

    test('Name und Beschreibung sagen nicht mehr „nur das Tutorial"', () {
      final onboarding = app.Badge.getById(app.Badge.onboardingBadgeId)!;
      expect(
        onboarding.description.toLowerCase(),
        isNot(contains('tutorial')),
        reason: 'Die Beschreibung beschreibt die alte Bedingung. Genau daran '
            'hat Vucko gemerkt, dass das Abzeichen am falschen Ereignis sitzt.',
      );
      expect(onboarding.name, isNot('Eingewiesen'));

      // Und die beiden Abzeichen sagen nicht laenger fast dasselbe:
      // badge_16 darf nicht behaupten, es waeren ALLE Aufgaben.
      final startklar = app.Badge.getById(app.Badge.starterBadgeId)!;
      expect(
        startklar.description,
        isNot(startsWith('Alle Starter-Aufgaben')),
        reason: 'badge_16 haengt an acht von zwoelf, nicht an allen.',
      );
      expect(startklar.name, isNot(onboarding.name));
      expect(startklar.description, isNot(onboarding.description));
    });
  });

  group('Die Karte: Fortschritt und Sichtbarkeit', () {
    /// Baut den Geraetezustand nach: erledigte Aufgaben plus eine
    /// Bonuswoche, die vor [bonusVor] zu Ende ging.
    void geraetestand(List<String> erledigt, {Duration? bonusVor}) {
      SharedPreferences.setMockInitialValues({
        'starter_aufgaben_erledigt_v1': jsonEncode(erledigt),
        if (bonusVor != null) ...{
          'starter_paket_vergeben_v1': true,
          'starter_bonus_ende_v1':
              DateTime.now().subtract(bonusVor).toIso8601String(),
        },
      });
      dienst.resetForTests();
    }

    Future<void> zeige(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: StarterPaketKarte()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
        'VUCKOS FALL: zehn von zwoelf, Bonuswoche abgelaufen — die Karte '
        'steht wieder da', (tester) async {
      geraetestand(vuckosZehn, bonusVor: const Duration(days: 3));
      await zeige(tester);

      // Ohne die Aenderung war hier NICHTS zu sehen: `paketVergeben` war
      // wahr (acht erreicht) und die Woche vorbei.
      expect(find.text('Dein Starter-Paket'), findsOneWidget);
      expect(find.text('10/12'), findsOneWidget);
      // Und genau die zwei offenen Aufgaben sind noch antippbar.
      expect(
        find.byKey(const ValueKey('starter_aufgabe_hashtag')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('starter_aufgabe_gruppenfahrt')),
        findsOneWidget,
      );
      // 2026-08-25 (Gliederung): Hier stand „Boost geschafft" und „2 Schritte"
      // aus dem Erklaerabsatz unter dem Balken. Den Absatz gibt es nicht mehr
      // — er war 112 von 2165 Punkten Kartenhoehe und nannte zwei Schwellen
      // und zwei Abzeichen in einem Satz. Die Restzahl steht jetzt am
      // Belohnungsblock, dort wo auch steht, wofuer man sie sammelt.
      expect(find.textContaining('2 Schritte'), findsOneWidget);
    });

    testWidgets('erst bei zwoelf von zwoelf verschwindet sie', (tester) async {
      geraetestand(alleZwoelf(), bonusVor: const Duration(days: 3));
      await zeige(tester);
      expect(find.text('Dein Starter-Paket'), findsNothing);
      expect(find.text('12/12'), findsNothing);
    });

    testWidgets('laufende Bonuswoche verdeckt die Restliste nicht',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'starter_aufgaben_erledigt_v1': jsonEncode(vuckosZehn),
        'starter_paket_vergeben_v1': true,
        'starter_bonus_ende_v1':
            DateTime.now().add(const Duration(days: 4)).toIso8601String(),
      });
      dienst.resetForTests();
      await zeige(tester);

      expect(find.text('Doppel-XP-Woche läuft'), findsOneWidget);
      expect(
        find.text('Dein Starter-Paket'),
        findsOneWidget,
        reason: 'Wer den Boost hat, muss trotzdem sehen, was ihm noch fehlt.',
      );
    });

    testWidgets('frischer Nutzer: 0/12 und der Weg zur Belohnung',
        (tester) async {
      geraetestand(const []);
      await zeige(tester);
      expect(find.text('0/12'), findsOneWidget);
      // 2026-08-25 (Gliederung): Hier standen „8 Schritte" (die
      // Boost-Schwelle), „Startklar-Abzeichen" (im Fliesstext) und die
      // „Boost"-Marke auf dem Balken. Alle drei sind weg, weil sie ZWEI Ziele
      // nebeneinander zeigten — genau die Verwechslung, aus der der Auftrag
      // entstand. Es gibt jetzt ein Ziel: die ganze Liste. Der Rest steht als
      // Zahl am Belohnungsblock, die Belohnung selbst daneben als Pillen.
      expect(find.textContaining('12 Schritte'), findsOneWidget);
      expect(find.textContaining('Startklar'), findsWidgets);
      expect(find.text('Boost'), findsNothing);
    });
  });

  group('Zwei Abzeichen im selben Durchgang', () {
    /// Wer von sieben erledigten Aufgaben aus einen Sync macht und dabei auf
    /// zwoelf springt, verdient badge_16 (acht) UND badge_58 (zwoelf) in
    /// derselben Sekunde. Beide Melder feuern dann synchron hintereinander.
    /// Ohne die Verleih-Kette in der Karte staenden zwei Dialoge uebereinander.
    test('beide Melder feuern, jeder genau einmal', () async {
      await dienst.load();
      await dienst.markiereAlle(alleZwoelf().take(7));
      expect(dienst.boostErreicht, isFalse);

      var boost = 0;
      var komplett = 0;
      void a() => boost += dienst.paketFrischVerdient.value ? 1 : 0;
      void b() => komplett += dienst.alleAufgabenFrischErledigt.value ? 1 : 0;
      dienst.paketFrischVerdient.addListener(a);
      dienst.alleAufgabenFrischErledigt.addListener(b);
      addTearDown(() {
        dienst.paketFrischVerdient.removeListener(a);
        dienst.alleAufgabenFrischErledigt.removeListener(b);
      });

      await dienst.markiereAlle(alleZwoelf());
      expect(boost, 1);
      expect(komplett, 1);
    });

    test('die Karte reiht die Verleihungen hintereinander', () {
      final karte = File(
        'lib/presentation/widgets/starter_paket_karte.dart',
      ).readAsStringSync();
      expect(karte, contains('Future<void> _verleihKette'));
      // 2026-09-01 (A18): Der Aufruf steht jetzt ueber drei Zeilen, weil ein
      // catchError dazugekommen ist. Deshalb nicht mehr auf den
      // zusammenhaengenden Text pruefen, sondern auf beide Teile.
      expect(karte, contains('_verleihKette = _verleihKette'));
      expect(karte, contains('.then((_) => _verleiheAbzeichen(badgeId))'));
      // Beide Melder gehen ueber die Kette, keiner ruft direkt.
      final direkt = RegExp(r'await _verleiheAbzeichen\(').allMatches(karte);
      expect(direkt, isEmpty);
      // 2026-09-01 (A18, Vucko: "Manchmal haengt es nach der
      // Badge-Animation"): Ohne Faenger stand die Kette nach dem ERSTEN
      // Fehlschlag dauerhaft auf einem abgelehnten Future. Jede weitere
      // Verleihung haengte sich daran und lief nie — lautlos, fuer den Rest
      // der Sitzung.
      expect(
        karte,
        contains('.catchError('),
        reason:
            'Ein einziger Netzhaenger darf nicht alle folgenden Abzeichen '
            'stilllegen.',
      );
    });
  });

  group('Der Platz ganz oben kostet die eigene Anordnung nichts', () {
    late String home;

    setUpAll(() {
      home =
          File('lib/presentation/pages/home_content_page.dart').readAsStringSync();
    });

    test('die Karte steht im Baum vor den Kacheln', () {
      final karte = home.indexOf('_buildStarterPaketMitTutorialAnker(),');
      final kacheln = home.indexOf('_buildDashboard(),');
      expect(karte, greaterThan(0));
      expect(kacheln, greaterThan(0));
      expect(
        karte,
        lessThan(kacheln),
        reason: '„als oberstes widget bis ich es abgeschlossen habe".',
      );
    });

    test('die Karte ist keine Kachel und wird nie mitgespeichert', () {
      // Waere sie eine Kachel, muesste man sie in `_dashboardItems`
      // einsortieren — und genau dabei ginge die eigene Anordnung des
      // Nutzers kaputt oder wuerde ueberschrieben.
      expect(home.contains('_HomeWidgetId.starter'), isFalse);
      expect(home.contains('_HomeWidgetId.starterPaket'), isFalse);

      final i = home.indexOf('Widget _buildStarterPaketMitTutorialAnker() {');
      final rumpf = home.substring(i, home.indexOf('\n  }', i));
      expect(rumpf.contains('_dashboardItems'), isFalse);
      expect(rumpf.contains('setState('), isFalse);
      expect(
        rumpf.contains('_persistDashboardLayout') ||
            rumpf.contains('StartseitenAnordnung.hochladen'),
        isFalse,
        reason: 'Die Karte darf die Anordnung weder lesen noch schreiben.',
      );
    });
  });
}
