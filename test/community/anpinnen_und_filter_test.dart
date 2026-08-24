import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/data/services/nutzer_prefs_schluessel.dart';
import 'package:cruise_connect/presentation/widgets/community/community_filter_leiste.dart';

/// 2026-08-24 — Auftrag Vucko, woertlich (zwei Nachrichten):
///
///   „und man soll auch communitys anpinnen koennen und einen filter haben bei
///    oeffentliche communitys wo man einstellen kann auch bei der erstellung
///    obs fuer autofahrer motorradfahrer in welcher region und das man dann
///    beim filter nach region nach auto motorrad oder beides und sonstige
///    sachen die noch sinn machen einstellen kann teste das auch gruendlich"
///
///   „man soll auch community anpinnen koennen"
///
/// Fundament ist die Migration 20260824190000 (Tabellen `community_pins`,
/// `community_regionen`, Spalten `communities.fahrzeugart`/`region_code`,
/// RPC `get_communities_gefiltert` und `community_pin_setzen`). Dieser Test
/// bewacht die CLIENT-Seite.
///
/// OHNE DIE AENDERUNG IST DIE DATEI SCHON BEIM UEBERSETZEN ROT: es gab weder
/// `CommunityFahrzeugart` noch `CommunityFilterEinstellungen` noch
/// `communityFilterLeerText` noch `sortiereMitPinsZuerst`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tabQuelle = File(
    'lib/presentation/pages/community_chats_tab.dart',
  ).readAsStringSync();
  final dienstQuelle = File(
    'lib/data/services/community_chat_service.dart',
  ).readAsStringSync();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'konto-a';
  });

  tearDown(() {
    NutzerPrefsSchluessel.nutzerIdFuerTests = null;
    CommunityChatService.setzeRegionenFuerTests(null);
  });

  // ==========================================================================
  // AUFGABE 1 — ANPINNEN
  // ==========================================================================
  group('Aufgabe 1: Anpinnen', () {
    Map<String, dynamic> zeile(
      String id, {
      int? pin,
      String? aktivitaet,
      String? erstellt,
    }) {
      return <String, dynamic>{
        'id': id,
        'name': id,
        'angepinnt': pin != null,
        'pin_position': pin,
        'letzte_aktivitaet': aktivitaet,
        'created_at': erstellt ?? '2026-08-01T00:00:00Z',
      };
    }

    test('eine Zeile ohne Pin gilt nicht als angepinnt', () {
      final ohne = zeile('a');
      expect(CommunityChatService.istAngepinnt(ohne), isFalse);
      expect(CommunityChatService.pinPosition(ohne), isNull);
    });

    test('Platz 1 wird als angepinnt erkannt', () {
      final mit = zeile('a', pin: 1);
      expect(CommunityChatService.istAngepinnt(mit), isTrue);
      expect(CommunityChatService.pinPosition(mit), 1);
    });

    test(
      'Angepinntes steht oben — auch wenn es die aelteste und stillste ist',
      () {
        // Genau der Fall, der ohne Sortierung schiefgeht: die angepinnte
        // Community ist die mit der aeltesten Aktivitaet. Wuerde nur nach
        // Aktivitaet sortiert, staende sie unten.
        final liste = <Map<String, dynamic>>[
          zeile('frisch', aktivitaet: '2026-08-24T10:00:00Z'),
          zeile('mittel', aktivitaet: '2026-08-20T10:00:00Z'),
          zeile('angepinnt', pin: 1, aktivitaet: '2026-01-01T10:00:00Z'),
        ];

        CommunityChatService.sortiereMitPinsZuerst(liste);

        expect(liste.map((z) => z['id']).toList(), [
          'angepinnt',
          'frisch',
          'mittel',
        ]);
      },
    );

    test('mehrere Pins stehen in der Reihenfolge ihrer Plaetze', () {
      final liste = <Map<String, dynamic>>[
        zeile('platz3', pin: 3, aktivitaet: '2026-08-24T10:00:00Z'),
        zeile('platz1', pin: 1, aktivitaet: '2026-01-01T10:00:00Z'),
        zeile('ohne', aktivitaet: '2026-08-24T12:00:00Z'),
        zeile('platz2', pin: 2, aktivitaet: '2026-02-01T10:00:00Z'),
      ];

      CommunityChatService.sortiereMitPinsZuerst(liste);

      expect(liste.map((z) => z['id']).toList(), [
        'platz1',
        'platz2',
        'platz3',
        'ohne',
      ]);
    });

    test(
      'ohne letzte Nachricht zaehlt das Gruendungsdatum, nicht „ganz unten"',
      () {
        // Gemessen am 24.08.2026: „Legacy" hat 14 Mitglieder und hatte NIE
        // eine Nachricht. Ohne diesen Rueckfall faellt sie auf Zeitwert 0 und
        // steht immer ganz unten, egal wie jung sie ist.
        final liste = <Map<String, dynamic>>[
          zeile('alt', aktivitaet: '2026-08-01T10:00:00Z'),
          zeile('nie_geschrieben', erstellt: '2026-08-23T10:00:00Z'),
        ];

        CommunityChatService.sortiereMitPinsZuerst(liste);

        expect(liste.first['id'], 'nie_geschrieben');
      },
    );

    test('setzePinInZeile schaltet hin und zurueck', () {
      final z = zeile('a');

      CommunityChatService.setzePinInZeile(z, angepinnt: true, position: 2);
      expect(CommunityChatService.istAngepinnt(z), isTrue);
      expect(CommunityChatService.pinPosition(z), 2);

      CommunityChatService.setzePinInZeile(z, angepinnt: false);
      expect(CommunityChatService.istAngepinnt(z), isFalse);
      expect(CommunityChatService.pinPosition(z), isNull);
    });

    test('die 10er-Grenze der Datenbank kommt im Klartext beim Nutzer an', () {
      // `community_pin_setzen` wirft: „Du hast schon 10 Communities
      // angepinnt. Löse zuerst eine davon." Dieser Satz ist bereits fuer
      // Menschen geschrieben und darf NICHT durch ein generisches
      // „Aktion gerade nicht möglich." ersetzt werden — sonst weiss niemand,
      // warum das Anpinnen nicht geht.
      final text = CommunityChatService.pinFehlerText(
        _fehler('Du hast schon 10 Communities angepinnt. Löse zuerst eine davon.'),
      );
      expect(text, contains('10 Communities angepinnt'));
    });

    test('eine alte Datenbank ohne die Funktion sagt das auch so', () {
      final text = CommunityChatService.pinFehlerText(
        _fehler(
          'Could not find the function public.community_pin_setzen in the '
          'schema cache',
          code: 'PGRST202',
        ),
      );
      expect(text, 'Anpinnen gibt es erst nach dem nächsten Update.');
    });

    test('Datenbankrauschen wird nicht durchgereicht', () {
      final text = CommunityChatService.pinFehlerText(
        _fehler('new row violates row-level security policy', code: '42501'),
      );
      expect(text, 'Anpinnen gerade nicht möglich.');
    });

    test('die Bedienung haengt am vorhandenen Drei-Punkte-Menue', () {
      // Vucko hat die Bedienung offengelassen. Entschieden: der Eintrag im
      // Menue, das es schon gibt. Dieser Test haelt die Entscheidung fest —
      // faellt sie weg, faellt der Zugang zum Anpinnen weg.
      expect(
        tabQuelle.contains("value: 'pin'"),
        isTrue,
        reason: 'Der Menueeintrag zum Anpinnen fehlt.',
      );
      expect(tabQuelle.contains('_pinUmschalten('), isTrue);
    });

    test('die Rueckmeldung kommt SOFORT, nicht erst nach dem Server', () {
      // Optimistic-UI-Grundsatz dieses Projekts. Nachgestellt an der Quelle:
      // in `_pinUmschalten` steht das erste `setState` VOR dem `await` auf
      // die Datenbank.
      final start = tabQuelle.indexOf('Future<void> _pinUmschalten(');
      expect(start, greaterThan(-1));
      final ende = tabQuelle.indexOf('int _naechsterPinPlatz()', start);
      expect(ende, greaterThan(start));
      final block = tabQuelle.substring(start, ende);

      final ersterSetState = block.indexOf('setState(');
      final ersterAwait = block.indexOf('await CommunityChatService.pinSetzen');
      expect(ersterSetState, greaterThan(-1));
      expect(ersterAwait, greaterThan(-1));
      expect(
        ersterSetState < ersterAwait,
        isTrue,
        reason:
            'Die Kachel muss die Nadel bekommen, BEVOR der Server geantwortet '
            'hat. Sonst passiert auf den Fingertipp erst einmal nichts.',
      );
      expect(
        block.contains('_showError(e)'),
        isTrue,
        reason: 'Ohne Ruecknahme bei einem Fehler luegt die Anzeige.',
      );
    });
  });

  // ==========================================================================
  // AUFGABE 2 — DER FILTER
  // ==========================================================================
  group('Aufgabe 2: Fahrzeugart', () {
    test('die Werte sind wortgleich mit profile_vehicles.vehicle_type', () {
      expect(CommunityFahrzeugart.auto.wert, 'car');
      expect(CommunityFahrzeugart.motorrad.wert, 'motorcycle');
      expect(CommunityFahrzeugart.alle.wert, 'both');
    });

    test('„Alle" filtert nicht — es geht als null an die Datenbank', () {
      // Wichtig: `both` als FILTER hiesse „nur gemischte Communities". Die
      // Datenbank setzt es zwar selbst auf „egal" um, aber der Client darf
      // sich darauf nicht verlassen.
      expect(CommunityFahrzeugart.alle.filterWert, isNull);
      expect(CommunityFahrzeugart.auto.filterWert, 'car');
      expect(CommunityFahrzeugart.motorrad.filterWert, 'motorcycle');
    });

    test('beim Anlegen wird „Alle" als both geschrieben, nicht als null', () {
      // Die Spalte ist `not null default both`. Ein null wuerde den Insert
      // sprengen.
      expect(CommunityFahrzeugart.alle.spaltenWert, 'both');
    });

    test('ein unbekannter Wert faellt auf „Alle" zurueck', () {
      expect(CommunityFahrzeugart.ausWert(null), CommunityFahrzeugart.alle);
      expect(CommunityFahrzeugart.ausWert(''), CommunityFahrzeugart.alle);
      expect(CommunityFahrzeugart.ausWert('lkw'), CommunityFahrzeugart.alle);
      expect(CommunityFahrzeugart.ausWert('CAR'), CommunityFahrzeugart.auto);
    });

    test('„offen fuer alle" bekommt KEIN Etikett an der Kachel', () {
      // Gemessen: alle sechs Bestands-Communities stehen auf `both`. Ein
      // Etikett daran klebte an jeder einzelnen Kachel und unterschiede
      // nichts.
      expect(CommunityFahrzeugart.alle.kachelText, isNull);
      expect(CommunityFahrzeugart.auto.kachelText, 'Für Autos');
      expect(CommunityFahrzeugart.motorrad.kachelText, 'Für Motorräder');
    });

    test('die Fahrzeugart wird aus einer geladenen Zeile gelesen', () {
      expect(
        CommunityChatService.fahrzeugartVon(<String, dynamic>{
          'fahrzeugart': 'motorcycle',
        }),
        CommunityFahrzeugart.motorrad,
      );
      // Eine alte Datenbank liefert das Feld gar nicht.
      expect(
        CommunityChatService.fahrzeugartVon(<String, dynamic>{}),
        CommunityFahrzeugart.alle,
      );
    });
  });

  group('Aufgabe 2: Sortierung', () {
    test('die Werte sind die der Datenbank', () {
      expect(CommunitySortierung.aktiv.wert, 'aktiv');
      expect(CommunitySortierung.gross.wert, 'gross');
      expect(CommunitySortierung.neu.wert, 'neu');
    });

    test('Vorgabe ist „Aktiv", nicht „Größte"', () {
      // Gemessen am 24.08.2026: „Legacy" hat 14 Mitglieder und hatte NIE eine
      // Nachricht, „Cruise Connector" 19 Mitglieder und seit dem 14.08. keine
      // mehr. „Größte zuerst" empfiehlt also die beiden totesten.
      expect(CommunitySortierung.ausWert(null), CommunitySortierung.aktiv);
      expect(CommunitySortierung.ausWert('quatsch'), CommunitySortierung.aktiv);
      expect(CommunitySortierung.ausWert('neu'), CommunitySortierung.neu);
    });
  });

  group('Aufgabe 2: Region', () {
    test('eine Zeile aus community_regionen wird vollstaendig gelesen', () {
      final region = CommunityRegion.ausZeile(<String, dynamic>{
        'code': 'AT-8',
        'land_code': 'AT',
        'name': 'Vorarlberg',
        'ist_land': false,
        'sortierung': 10,
      });
      expect(region.code, 'AT-8');
      expect(region.landCode, 'AT');
      expect(region.name, 'Vorarlberg');
      expect(region.istLand, isFalse);
      expect(region.sortierung, 10);
    });

    test('„ganzes Land" ist als solches erkennbar', () {
      final region = CommunityRegion.ausZeile(<String, dynamic>{
        'code': 'AT',
        'land_code': 'AT',
        'name': 'Ganz Österreich',
        'ist_land': true,
        'sortierung': 0,
      });
      expect(region.istLand, isTrue);
    });

    test('der Regionsname kommt aus der geladenen Zeile', () {
      expect(
        CommunityChatService.regionName(<String, dynamic>{
          'region_name': 'Vorarlberg',
        }),
        'Vorarlberg',
      );
      // ueberregional / alte Datenbank
      expect(CommunityChatService.regionName(<String, dynamic>{}), isNull);
      expect(
        CommunityChatService.regionName(<String, dynamic>{'region_name': '  '}),
        isNull,
      );
    });
  });

  group('Aufgabe 2: ein leeres Ergebnis wird erklaert', () {
    // Vucko woertlich: „sorg dafuer, dass ein leeres Ergebnis erklaert wird
    // (‚Keine Community passt zu diesem Filter') statt einfach leer zu sein".
    test('Filter gesetzt: der Satz aus dem Auftrag steht da', () {
      expect(
        communityFilterLeerText(filtertEtwasWeg: true, sucheAktiv: false),
        'Keine Community passt zu diesem Filter.',
      );
    });

    test('nur gesucht: dann liegt es an der Suche, nicht am Filter', () {
      expect(
        communityFilterLeerText(filtertEtwasWeg: false, sucheAktiv: true),
        'Keine Community passt zu deiner Suche.',
      );
    });

    test('beides: beides wird genannt', () {
      expect(
        communityFilterLeerText(filtertEtwasWeg: true, sucheAktiv: true),
        'Keine Community passt zu diesem Filter und deiner Suche.',
      );
    });

    test('nichts gesetzt: KEINE Filter-Ausrede', () {
      // Der wichtigste Fall. Stuende hier ein Satz, behauptete die App einen
      // Filter, den niemand gesetzt hat — und der Nutzer suchte den Regler,
      // der ihn wegnimmt.
      expect(
        communityFilterLeerText(filtertEtwasWeg: false, sucheAktiv: false),
        isNull,
      );
    });
  });

  group('Aufgabe 2: die Filterwahl ueberlebt den Neustart', () {
    test('gemerkt wird Fahrzeugart, Region und Sortierung', () async {
      final wahl = CommunityFilterEinstellungen.fuerTests();
      await wahl.laden();

      await wahl.setzeFahrzeugart(CommunityFahrzeugart.motorrad);
      await wahl.setzeRegion('AT-8');
      await wahl.setzeSortierung(CommunitySortierung.gross);

      // Neustart: eine frische Wahl liest denselben Spiegel.
      final nachNeustart = CommunityFilterEinstellungen.fuerTests();
      await nachNeustart.laden();

      expect(nachNeustart.fahrzeugart, CommunityFahrzeugart.motorrad);
      expect(nachNeustart.regionCode, 'AT-8');
      expect(nachNeustart.sortierung, CommunitySortierung.gross);
    });

    test('ein zweites Konto auf demselben Handy erbt den Filter NICHT', () async {
      final wahl = CommunityFilterEinstellungen.fuerTests();
      await wahl.laden();
      await wahl.setzeFahrzeugart(CommunityFahrzeugart.motorrad);
      await wahl.setzeRegion('AT-8');

      NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'konto-b';
      final anderes = CommunityFilterEinstellungen.fuerTests();
      await anderes.laden();

      expect(
        anderes.fahrzeugart,
        CommunityFahrzeugart.alle,
        reason:
            'Ein geerbter Filter sieht aus wie eine leere App — und niemand '
            'sucht einen Regler, den er nie angefasst hat.',
      );
      expect(anderes.regionCode, isNull);
    });

    test('filtertEtwasWeg ignoriert die Sortierung', () async {
      final wahl = CommunityFilterEinstellungen.fuerTests();
      await wahl.laden();
      expect(wahl.filtertEtwasWeg, isFalse);

      // Umsortieren blendet nichts aus — es kann ein leeres Ergebnis also
      // auch nicht erklaeren.
      await wahl.setzeSortierung(CommunitySortierung.neu);
      expect(wahl.filtertEtwasWeg, isFalse);

      await wahl.setzeFahrzeugart(CommunityFahrzeugart.auto);
      expect(wahl.filtertEtwasWeg, isTrue);
    });

    test('zuruecksetzen raeumt die Filter weg und laesst die Sortierung', () async {
      final wahl = CommunityFilterEinstellungen.fuerTests();
      await wahl.laden();
      await wahl.setzeFahrzeugart(CommunityFahrzeugart.auto);
      await wahl.setzeRegion('DE-BY');
      await wahl.setzeSortierung(CommunitySortierung.neu);

      await wahl.zuruecksetzen();

      expect(wahl.fahrzeugart, CommunityFahrzeugart.alle);
      expect(wahl.regionCode, isNull);
      expect(
        wahl.sortierung,
        CommunitySortierung.neu,
        reason:
            'Die Sortierung hat nichts ausgeblendet. Sie mit zurueckzusetzen '
            'waere eine Ueberraschung.',
      );
    });

    test('eine leere Region gilt als „keine Region"', () async {
      final wahl = CommunityFilterEinstellungen.fuerTests();
      await wahl.laden();
      await wahl.setzeRegion('   ');
      expect(wahl.regionCode, isNull);
      expect(wahl.filtertEtwasWeg, isFalse);
    });

    test('jede Aenderung meldet sich sofort (ChangeNotifier)', () async {
      final wahl = CommunityFilterEinstellungen.fuerTests();
      await wahl.laden();
      var meldungen = 0;
      wahl.addListener(() => meldungen++);

      await wahl.setzeFahrzeugart(CommunityFahrzeugart.auto);
      expect(meldungen, 1);

      // Dieselbe Wahl noch einmal: keine Meldung, kein Neuladen.
      await wahl.setzeFahrzeugart(CommunityFahrzeugart.auto);
      expect(meldungen, 1);
    });
  });

  group('Aufgabe 2: der Filter geht an die Datenbank, nicht an den Client', () {
    test('gefiltert wird serverseitig ueber get_communities_gefiltert', () {
      expect(dienstQuelle.contains("'get_communities_gefiltert'"), isTrue);
      expect(dienstQuelle.contains("'p_fahrzeugart'"), isTrue);
      expect(dienstQuelle.contains("'p_region_code'"), isTrue);
      expect(dienstQuelle.contains("'p_suche'"), isTrue);
      expect(dienstQuelle.contains("'p_sortierung'"), isTrue);
    });

    test(
      'Fahrzeugart und Region gelten NUR fuer die oeffentliche Liste',
      () {
        // Der Fehler, den dieser Test verhindert: wer nach „Motorrad"
        // filtert, darf nicht seine EIGENEN Communities verlieren.
        final start = tabQuelle.indexOf('Future<void> _load() async {');
        expect(start, greaterThan(-1));
        final ende = tabQuelle.indexOf('Future<void> _openCommunity(', start);
        expect(ende, greaterThan(start));
        final block = tabQuelle.substring(start, ende);

        final meine = block.indexOf('CommunityListe.meine');
        final entdecken = block.indexOf('CommunityListe.entdecken');
        expect(meine, greaterThan(-1));
        expect(entdecken, greaterThan(meine));

        final meinerAufruf = block.substring(meine, entdecken);
        expect(
          meinerAufruf.contains('fahrzeugart:'),
          isFalse,
          reason:
              'Der Fahrzeugart-Filter darf „Meine Communities" nicht '
              'ausblenden.',
        );
        expect(meinerAufruf.contains('regionCode:'), isFalse);
        expect(
          meinerAufruf.contains('suche:'),
          isTrue,
          reason:
              'Die Suche gilt sehr wohl fuer beide Listen — wer einen Namen '
              'tippt, sucht die Community, nicht die Liste.',
        );
      },
    );

    test('der Rueckfall auf eine alte Datenbank sucht wenigstens im Text', () {
      final zeilen = <Map<String, dynamic>>[
        <String, dynamic>{'name': 'Opel-Crew', 'description': null},
        <String, dynamic>{'name': 'Legacy', 'description': 'BMW und mehr'},
      ];

      // Gross-/Kleinschreibung egal — gemessen am 24.08.2026 hiess die
      // Community „Opel-Crew", eine Suche nach „opel" muss sie finden.
      expect(
        CommunityChatService.filtereOhneServer(
          zeilen,
          suche: 'opel',
        ).map((z) => z['name']).toList(),
        ['Opel-Crew'],
      );
      // Die Beschreibung zaehlt mit.
      expect(
        CommunityChatService.filtereOhneServer(
          zeilen,
          suche: 'bmw',
        ).map((z) => z['name']).toList(),
        ['Legacy'],
      );
      // Ohne Suchtext bleibt alles stehen.
      expect(CommunityChatService.filtereOhneServer(zeilen).length, 2);
      expect(
        CommunityChatService.filtereOhneServer(zeilen, suche: '  ').length,
        2,
      );
    });
  });

  // ==========================================================================
  // AUFGABE 3 — BEI DER ERSTELLUNG
  // ==========================================================================
  group('Aufgabe 3: bei der Erstellung', () {
    test('createCommunity nimmt Fahrzeugart und Region entgegen', () {
      expect(
        dienstQuelle.contains(
          'CommunityFahrzeugart fahrzeugart = CommunityFahrzeugart.alle,',
        ),
        isTrue,
      );
      expect(dienstQuelle.contains("'region_code':"), isTrue);
      expect(dienstQuelle.contains("'fahrzeugart': fahrzeugart.spaltenWert"), isTrue);
    });

    test('das Erstellen-Blatt reicht beides durch', () {
      expect(tabQuelle.contains('fahrzeugart: fahrzeugart,'), isTrue);
      expect(tabQuelle.contains('regionCode: regionCode,'), isTrue);
    });

    test('kein neues Pflichtfeld: die Vorgaben sind „Alle" und „keine"', () {
      // Ein Pflichtfeld mehr ist eine Huerde vor dem eigentlichen Zweck, und
      // eine erzwungene Wahl liefert falsche Angaben, weil jemand irgendetwas
      // antippt, um weiterzukommen.
      expect(
        tabQuelle.contains('var fahrzeugart = CommunityFahrzeugart.alle;'),
        isTrue,
      );
      expect(tabQuelle.contains('String? regionCode;'), isTrue);
      // Der „Erstellen"-Knopf haengt weiterhin NUR am Speichern-Zustand,
      // nicht an einer der beiden neuen Angaben.
      expect(tabQuelle.contains('onPressed: saving ? null : create,'), isTrue);
    });
  });

  // ==========================================================================
  // Die Bedienoberflaeche
  // ==========================================================================
  group('Die Filterleiste', () {
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
        code: 'DE-BY',
        landCode: 'DE',
        name: 'Bayern',
        istLand: false,
      ),
    ];

    Future<CommunityFilterEinstellungen> pumpeLeiste(WidgetTester tester) async {
      final wahl = CommunityFilterEinstellungen.fuerTests();
      await wahl.laden();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: wahl,
              builder: (context, _) => CommunityFilterLeiste(
                einstellungen: wahl,
                regionen: regionen,
                onFahrzeugart: wahl.setzeFahrzeugart,
                onRegion: wahl.setzeRegion,
                onSortierung: wahl.setzeSortierung,
                onZuruecksetzen: wahl.zuruecksetzen,
              ),
            ),
          ),
        ),
      );
      return wahl;
    }

    testWidgets('alle drei Fahrzeugarten sind gleichzeitig sichtbar', (
      tester,
    ) async {
      await pumpeLeiste(tester);
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('Motorrad'), findsOneWidget);
      expect(find.text('Alle'), findsOneWidget);
    });

    testWidgets('ein Tipp auf „Motorrad" setzt die Wahl', (tester) async {
      final wahl = await pumpeLeiste(tester);
      await tester.tap(find.text('Motorrad'));
      await tester.pumpAndSettle();
      expect(wahl.fahrzeugart, CommunityFahrzeugart.motorrad);
    });

    testWidgets('ohne Region steht „Alle Regionen" da', (tester) async {
      await pumpeLeiste(tester);
      expect(find.text('Alle Regionen'), findsOneWidget);
    });

    testWidgets('das Regionsblatt waehlt aus und zeigt den Namen an', (
      tester,
    ) async {
      final wahl = await pumpeLeiste(tester);
      await tester.tap(find.text('Alle Regionen'));
      await tester.pumpAndSettle();

      // Nach Land gruppiert, „ganzes Land" zuerst.
      expect(find.text('Österreich'), findsOneWidget);
      expect(find.text('Ganz Österreich'), findsOneWidget);
      expect(find.text('Deutschland'), findsOneWidget);

      await tester.tap(find.text('Vorarlberg'));
      await tester.pumpAndSettle();

      expect(wahl.regionCode, 'AT-8');
      expect(find.text('Vorarlberg'), findsOneWidget);
    });

    testWidgets('„Alles anzeigen" erscheint erst, wenn etwas wegfiltert', (
      tester,
    ) async {
      final wahl = await pumpeLeiste(tester);
      expect(find.text('Alles anzeigen'), findsNothing);

      await tester.tap(find.text('Auto'));
      await tester.pumpAndSettle();
      expect(find.text('Alles anzeigen'), findsOneWidget);

      await tester.tap(find.text('Alles anzeigen'));
      await tester.pumpAndSettle();
      expect(wahl.fahrzeugart, CommunityFahrzeugart.alle);
      expect(find.text('Alles anzeigen'), findsNothing);
    });

    testWidgets('das Blatt kann abgebrochen werden, ohne etwas zu aendern', (
      tester,
    ) async {
      final wahl = await pumpeLeiste(tester);
      await wahl.setzeRegion('AT-8');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Vorarlberg'));
      await tester.pumpAndSettle();
      // Zurueck ohne Auswahl.
      Navigator.of(tester.element(find.text('Region'))).pop();
      await tester.pumpAndSettle();

      expect(
        wahl.regionCode,
        'AT-8',
        reason:
            'Abbrechen ist etwas anderes als „alle Regionen" — sonst raeumt '
            'ein Wisch nach unten den Filter weg.',
      );
    });

    testWidgets('beim Erstellen heisst der dritte Zustand „Für alle"', (
      tester,
    ) async {
      var gewaehlt = CommunityFahrzeugart.alle;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommunityFahrzeugartChips(
              gewaehlt: gewaehlt,
              alleBeschriftung: 'Für alle',
              onWahl: (w) => gewaehlt = w,
            ),
          ),
        ),
      );
      expect(find.text('Für alle'), findsOneWidget);
      expect(find.text('Alle'), findsNothing);
    });
  });
}

/// Baut einen Fehler, wie ihn PostgREST liefert.
PostgrestException _fehler(String meldung, {String? code}) =>
    PostgrestException(message: meldung, code: code);
