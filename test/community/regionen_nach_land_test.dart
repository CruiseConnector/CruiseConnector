import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/data/services/nutzer_prefs_schluessel.dart';
import 'package:cruise_connect/presentation/widgets/community/community_filter_leiste.dart';

/// 2026-08-25 — Auftrag Vucko, woertlich:
///
///   „Zudem wollte ich noch zum filter bei gruppenfahrten was ansprechen. es
///    soll automatisch erkannt werden in welchem land man ist und man soll aus
///    dem Land nur die regionen haben also wenn ich in deutschland bin will
///    ich keine regionen von oesterreich haben usw. es solls automatisch am
///    standort erkennen bitte auf das acht geben"
///
/// „bitte auf das acht geben" heisst: die Randfaelle sind der Auftrag, nicht
/// der Normalfall. Dieser Test bewacht deshalb VOR ALLEM die drei Wege, auf
/// denen der Nutzer mit einer LEEREN Auswahl dastehen koennte:
///
///  1. Der Standort ist noch nicht da (Freigabe fehlt, GPS braucht Zeit).
///  2. Der Standort liegt im Ausland (Vorarlberger im Urlaub in Italien).
///  3. Zum erkannten Land gibt es gar keine Regionen in der Datenbank.
///
/// In allen drei Faellen muss die volle Liste stehenbleiben. Eine leere
/// Auswahl waere eine Sackgasse: der Nutzer sieht nichts und hat keinen Griff,
/// um wieder herauszukommen.
///
/// OHNE DIE AENDERUNG IST DIE DATEI SCHON BEIM UEBERSETZEN ROT: es gab weder
/// `CommunityStandortLand` noch `CommunityLandQuelle` noch die Parameter
/// `landCode`/`landQuelle` am Regionsblatt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tabQuelle = File(
    'lib/presentation/pages/community_chats_tab.dart',
  ).readAsStringSync();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'konto-a';
  });

  tearDown(() {
    NutzerPrefsSchluessel.nutzerIdFuerTests = null;
    CommunityStandortLand.standortQuelleFuerTests = null;
    CommunityStandortLand.profilQuelleFuerTests = null;
  });

  final regionen = <CommunityRegion>[
    const CommunityRegion(
      code: 'AT',
      landCode: 'AT',
      name: 'Ganz Österreich',
      istLand: true,
      sortierung: 0,
    ),
    const CommunityRegion(
      code: 'AT-8',
      landCode: 'AT',
      name: 'Vorarlberg',
      istLand: false,
    ),
    const CommunityRegion(
      code: 'DE',
      landCode: 'DE',
      name: 'Ganz Deutschland',
      istLand: true,
      sortierung: 0,
    ),
    const CommunityRegion(
      code: 'DE-BY',
      landCode: 'DE',
      name: 'Bayern',
      istLand: false,
    ),
    const CommunityRegion(
      code: 'CH-SG',
      landCode: 'CH',
      name: 'St. Gallen',
      istLand: false,
    ),
  ];

  // ==========================================================================
  // Das Land aus dem Standort
  // ==========================================================================
  group('Land aus dem Standort', () {
    test('Bregenz ist Österreich, München Deutschland, Zürich die Schweiz', () {
      expect(CommunityStandortLand.landAusPosition(47.5031, 9.7471), 'AT');
      expect(CommunityStandortLand.landAusPosition(48.1372, 11.5756), 'DE');
      expect(CommunityStandortLand.landAusPosition(47.3769, 8.5417), 'CH');
    });

    test('das Ausland liefert kein Land — und beschneidet damit nichts', () {
      // Genau der Fall aus dem Auftrag: der Vorarlberger im Urlaub. Mailand
      // und Rom sind weder AT noch CH noch DE.
      expect(CommunityStandortLand.landAusPosition(45.4642, 9.1900), isNull);
      expect(CommunityStandortLand.landAusPosition(41.9028, 12.4964), isNull);
      // Und ohne Land bleibt die volle Auswahl stehen.
      expect(
        CommunityStandortLand.regionenFuerLand(regionen, null).length,
        regionen.length,
      );
    });
  });

  // ==========================================================================
  // Die Entscheidung: Standort, sonst Profil, sonst das Gemerkte
  // ==========================================================================
  group('Welches Land gilt', () {
    test('der Standort schlägt das Profil', () {
      expect(
        CommunityStandortLand.entscheide(
          standortLand: 'DE',
          profilLand: 'AT',
          gemerktesLand: 'CH',
        ),
        'DE',
      );
    });

    test('ohne Standort gilt das Profil', () {
      expect(
        CommunityStandortLand.entscheide(profilLand: 'AT', gemerktesLand: 'CH'),
        'AT',
      );
    });

    test('ohne beides bleibt das zuletzt erkannte Land', () {
      expect(CommunityStandortLand.entscheide(gemerktesLand: 'CH'), 'CH');
    });

    test('ein Land ohne Regionen zählt nicht als Fund', () {
      // Italien steht in KEINER Zeile von `community_regionen`. Würde es
      // gelten, wäre die Auswahlliste leer — deshalb fällt die Entscheidung
      // hier aufs Profil zurück.
      expect(
        CommunityStandortLand.entscheide(standortLand: 'IT', profilLand: 'AT'),
        'AT',
      );
      expect(CommunityStandortLand.entscheide(standortLand: 'IT'), isNull);
    });

    test('gar nichts heisst „alle Regionen", nicht „keine"', () {
      expect(CommunityStandortLand.entscheide(), isNull);
    });

    test('Kleinschreibung und Leerzeichen aus dem Profil stören nicht', () {
      expect(CommunityStandortLand.entscheide(profilLand: ' de '), 'DE');
    });
  });

  // ==========================================================================
  // Die Auswahlliste
  // ==========================================================================
  group('Die Auswahlliste wird beschnitten', () {
    test('in Deutschland stehen keine österreichischen Regionen mehr', () {
      final gefiltert = CommunityStandortLand.regionenFuerLand(regionen, 'DE');
      expect(gefiltert.map((r) => r.code), <String>['DE', 'DE-BY']);
    });

    test('ohne Land bleibt alles stehen', () {
      expect(
        CommunityStandortLand.regionenFuerLand(regionen, null),
        hasLength(regionen.length),
      );
    });

    test('ein Land ohne Treffer beschneidet nichts', () {
      // Sicherung gegen die leere Auswahl: lieber 54 Zeilen zu viel als keine.
      expect(
        CommunityStandortLand.regionenFuerLand(regionen, 'IT'),
        hasLength(regionen.length),
      );
      expect(
        CommunityStandortLand.regionenFuerLand(const <CommunityRegion>[], 'AT'),
        isEmpty,
      );
    });

    test('eine Region aus einem anderen Land wird erkannt', () {
      expect(
        CommunityStandortLand.istFremdeRegion(
          regionCode: 'AT-8',
          landCode: 'DE',
          regionen: regionen,
        ),
        isTrue,
      );
      expect(
        CommunityStandortLand.istFremdeRegion(
          regionCode: 'DE-BY',
          landCode: 'DE',
          regionen: regionen,
        ),
        isFalse,
      );
      expect(
        CommunityStandortLand.istFremdeRegion(
          regionCode: null,
          landCode: 'DE',
          regionen: regionen,
        ),
        isFalse,
      );
    });
  });

  // ==========================================================================
  // Der Ablauf: erst das Gemerkte, dann Standort/Profil
  // ==========================================================================
  group('Der Ablauf', () {
    test('vor dem ersten Mal ist kein Land gesetzt — also alle Regionen', () async {
      final land = CommunityStandortLand.fuerTests();
      await land.laden();
      expect(land.landCode, isNull);
      expect(land.quelle, CommunityLandQuelle.unbekannt);
    });

    test('der Standort setzt das Land und merkt es sich', () async {
      CommunityStandortLand.standortQuelleFuerTests = () async => 'DE';
      final land = CommunityStandortLand.fuerTests();
      await land.laden();
      await land.aktualisieren();
      expect(land.landCode, 'DE');
      expect(land.quelle, CommunityLandQuelle.standort);

      // Beim nächsten Start steht es sofort da — ohne GPS, ohne Netz.
      CommunityStandortLand.standortQuelleFuerTests = null;
      final naechsterStart = CommunityStandortLand.fuerTests();
      await naechsterStart.laden();
      expect(naechsterStart.landCode, 'DE');
      expect(naechsterStart.quelle, CommunityLandQuelle.gemerkt);
    });

    test('ohne Standortfreigabe übernimmt das Profil', () async {
      CommunityStandortLand.standortQuelleFuerTests = () async => null;
      CommunityStandortLand.profilQuelleFuerTests = () async => 'AT';
      final land = CommunityStandortLand.fuerTests();
      await land.laden();
      await land.aktualisieren();
      expect(land.landCode, 'AT');
      expect(land.quelle, CommunityLandQuelle.profil);
    });

    test('im Ausland ohne Profil-Land bleibt es bei allen Regionen', () async {
      CommunityStandortLand.standortQuelleFuerTests = () async => 'IT';
      CommunityStandortLand.profilQuelleFuerTests = () async => null;
      final land = CommunityStandortLand.fuerTests();
      await land.laden();
      await land.aktualisieren();
      expect(land.landCode, isNull);
      expect(land.quelle, CommunityLandQuelle.unbekannt);
    });

    test('eine Änderung meldet sich bei der Oberfläche', () async {
      CommunityStandortLand.standortQuelleFuerTests = () async => 'CH';
      final land = CommunityStandortLand.fuerTests();
      await land.laden();
      var meldungen = 0;
      land.addListener(() => meldungen++);
      await land.aktualisieren();
      expect(meldungen, 1);
      // Zweiter Durchlauf mit demselben Ergebnis: keine zweite Meldung, sonst
      // baut die Seite ohne Grund neu auf.
      await land.aktualisieren();
      expect(meldungen, 1);
    });
  });

  // ==========================================================================
  // Das Regionsblatt
  // ==========================================================================
  group('Das Regionsblatt', () {
    Future<void> pumpeBlatt(
      WidgetTester tester, {
      required String? landCode,
      String? aktuell,
      CommunityLandQuelle quelle = CommunityLandQuelle.standort,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommunityRegionBlatt(
              regionen: regionen,
              aktuell: aktuell,
              titel: 'Region',
              landCode: landCode,
              landQuelle: quelle,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('in Deutschland stehen keine österreichischen Regionen', (
      tester,
    ) async {
      await pumpeBlatt(tester, landCode: 'DE');
      expect(find.text('Bayern'), findsOneWidget);
      expect(find.text('Vorarlberg'), findsNothing);
      expect(find.text('St. Gallen'), findsNothing);
      // Und der Nutzer sieht, WARUM.
      expect(find.text('Nach deinem Standort: Deutschland'), findsOneWidget);
    });

    testWidgets('„Alle Regionen" bleibt immer wählbar', (tester) async {
      await pumpeBlatt(tester, landCode: 'DE');
      expect(find.text('Alle Regionen'), findsOneWidget);
    });

    testWidgets('der Knopf holt die anderen Länder zurück', (tester) async {
      // Der Grenzbewohner aus Lustenau, der nach St. Gallen schaut.
      await pumpeBlatt(tester, landCode: 'AT');
      expect(find.text('St. Gallen'), findsNothing);
      await tester.tap(find.text('Regionen aus allen Ländern zeigen'));
      await tester.pumpAndSettle();
      expect(find.text('St. Gallen'), findsOneWidget);
      expect(find.text('Bayern'), findsOneWidget);
      // …und wieder zurück.
      expect(find.text('Nur Österreich zeigen'), findsOneWidget);
    });

    testWidgets('eine gewählte Region aus einem anderen Land bleibt sichtbar', (
      tester,
    ) async {
      // Sonst stünde im Filterknopf „Vorarlberg", und im Blatt wäre nichts
      // davon zu sehen — ein Filter ohne Griff.
      await pumpeBlatt(tester, landCode: 'DE', aktuell: 'AT-8');
      expect(find.text('Vorarlberg'), findsOneWidget);
      expect(find.text('Bayern'), findsOneWidget);
    });

    testWidgets('ohne erkanntes Land steht die volle Liste da', (tester) async {
      await pumpeBlatt(
        tester,
        landCode: null,
        quelle: CommunityLandQuelle.unbekannt,
      );
      expect(find.text('Vorarlberg'), findsOneWidget);
      expect(find.text('Bayern'), findsOneWidget);
      expect(find.text('St. Gallen'), findsOneWidget);
      // Kein Umschalter, weil es nichts umzuschalten gibt.
      expect(find.text('Regionen aus allen Ländern zeigen'), findsNothing);
    });
  });

  // ==========================================================================
  // Beide Stellen, an denen es Regionen gibt
  // ==========================================================================
  group('Es wirkt an BEIDEN Stellen', () {
    test('der Filter der öffentlichen Communities bekommt das Land', () {
      expect(tabQuelle.contains('landCode: _standortLand.landCode,'), isTrue);
      expect(tabQuelle.contains('landQuelle: _standortLand.quelle,'), isTrue);
      // Zwei Stellen: die Filterleiste und das Blatt „Community erstellen".
      expect(
        'landCode: _standortLand.landCode,'.allMatches(tabQuelle).length,
        2,
      );
    });

    test('das Land wird neben der Liste geholt, nicht davor', () {
      // Die Liste darf NIE auf eine Standortfreigabe warten.
      expect(tabQuelle.contains('unawaited(_landErmitteln());'), isTrue);
    });

    test('das Land setzt keinen Filter', () {
      // Es beschneidet die Auswahlliste — es blendet keine Community aus.
      expect(tabQuelle.contains('setzeRegion(_standortLand'), isFalse);
    });
  });
}
