import 'package:cruise_connect/presentation/pages/home_content_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-24 — „deine Kachel-Anordnung wandert nicht aufs neue Handy".
///
/// GEMESSEN vorher: Die Anordnung lag ausschliesslich in den
/// SharedPreferences unter `home_dashboard_layout_v1`. Neues Handy oder
/// Neuinstallation hiess: alles wieder Standard, die eigene Anordnung
/// ersatzlos weg. Seit Migration 20260824140000 steht sie auf `profiles`
/// (`home_layout`, `home_layout_stand`).
///
/// Ohne die Aenderung ist jeder Test hier rot: [StartseitenAnordnung] gab es
/// nicht.
void main() {
  final jetzt = DateTime(2026, 8, 24, 20, 0);
  final frueher = DateTime(2026, 8, 24, 18, 0);

  /// Ein Konto-Profil im Speicher, das Lesen und Schreiben mitschreibt.
  late Map<String, dynamic> kontoProfil;
  late List<Map<String, dynamic>> schreibZugriffe;

  void haengeKontoAn() {
    StartseitenAnordnung.profilLeserFuerTests = () async =>
        Map<String, dynamic>.from(kontoProfil);
    StartseitenAnordnung.profilSchreiberFuerTests = (werte) async {
      schreibZugriffe.add(werte);
      // Der Trigger trg_guard_home_layout_stand laesst einen aelteren Stand
      // nicht gewinnen — hier nachgebildet, damit der Test dieselbe Regel
      // sieht wie die Datenbank.
      final alterStand = kontoProfil[StartseitenAnordnung.spalteStand];
      final neuerStand = werte[StartseitenAnordnung.spalteStand];
      if (alterStand is String && neuerStand is String) {
        if (DateTime.parse(neuerStand).isBefore(DateTime.parse(alterStand))) {
          return;
        }
      }
      kontoProfil.addAll(werte);
    };
  }

  setUp(() {
    kontoProfil = <String, dynamic>{
      StartseitenAnordnung.spalteKacheln: null,
      StartseitenAnordnung.spalteStand: null,
    };
    schreibZugriffe = [];
    haengeKontoAn();
  });

  tearDown(StartseitenAnordnung.resetForTests);

  List<Map<String, dynamic>> kacheln(List<String> namen) => [
    for (final name in namen)
      {
        'key': name,
        'widgetIds': [name],
        'size': 'large',
      },
  ];

  // -------------------------------------------------------------------
  // 1. Wer gewinnt — die Reihenfolge-Regel
  // -------------------------------------------------------------------
  group('entscheide: wer gewinnt', () {
    test('Konto leer, Geraet hat etwas -> das GERAET gewinnt', () {
      // DER Fall, an dem sonst heute Nacht jemand seine Anordnung verliert:
      // Wer schon verschoben hat, behaelt seinen Stand und laedt ihn hoch.
      expect(
        StartseitenAnordnung.entscheide(
          geraetHatAnordnung: true,
          geraetStand: null,
          kontoHatAnordnung: false,
          kontoStand: null,
        ),
        AnordnungHerkunft.geraet,
      );
    });

    test('Konto hat etwas, Geraet leer -> das KONTO gewinnt', () {
      // Das neue Handy.
      expect(
        StartseitenAnordnung.entscheide(
          geraetHatAnordnung: false,
          geraetStand: null,
          kontoHatAnordnung: true,
          kontoStand: frueher,
        ),
        AnordnungHerkunft.server,
      );
    });

    test('beide haben etwas -> der juengere Stand gewinnt', () {
      expect(
        StartseitenAnordnung.entscheide(
          geraetHatAnordnung: true,
          geraetStand: jetzt,
          kontoHatAnordnung: true,
          kontoStand: frueher,
        ),
        AnordnungHerkunft.geraet,
      );
      expect(
        StartseitenAnordnung.entscheide(
          geraetHatAnordnung: true,
          geraetStand: frueher,
          kontoHatAnordnung: true,
          kontoStand: jetzt,
        ),
        AnordnungHerkunft.server,
      );
    });

    test('gleicher Stand -> das Konto gewinnt, es wird nicht hin- und '
        'hergeschoben', () {
      expect(
        StartseitenAnordnung.entscheide(
          geraetHatAnordnung: true,
          geraetStand: jetzt,
          kontoHatAnordnung: true,
          kontoStand: jetzt,
        ),
        AnordnungHerkunft.server,
      );
    });

    test('Geraet ohne Stand gegen Konto mit Stand -> das KONTO gewinnt', () {
      // Eine Anordnung ohne Stand stammt aus einer App-Fassung, die noch
      // keinen mitgeschrieben hat. Der Konto-Stand ist nachweislich mit
      // dieser Fassung entstanden und damit juenger.
      expect(
        StartseitenAnordnung.entscheide(
          geraetHatAnordnung: true,
          geraetStand: null,
          kontoHatAnordnung: true,
          kontoStand: frueher,
        ),
        AnordnungHerkunft.server,
      );
    });

    test('nirgends etwas -> Standard', () {
      expect(
        StartseitenAnordnung.entscheide(
          geraetHatAnordnung: false,
          geraetStand: null,
          kontoHatAnordnung: false,
          kontoStand: null,
        ),
        AnordnungHerkunft.standard,
      );
    });
  });

  // -------------------------------------------------------------------
  // 2. Der Abgleich am Konto
  // -------------------------------------------------------------------
  group('abgleichen', () {
    test('erster Start mit der neuen Fassung: der Geraetestand wandert hoch, '
        'er wird NICHT ueberschrieben', () async {
      final meine = kacheln(['streak', 'xp', 'rangliste']);

      final ergebnis = await StartseitenAnordnung.abgleichen(
        geraetKacheln: meine,
        geraetStand: null,
        jetzt: jetzt,
      );

      expect(ergebnis.herkunft, AnordnungHerkunft.geraet);
      expect(ergebnis.stand, jetzt, reason: 'bekommt jetzt einen Stand');
      expect(schreibZugriffe, hasLength(1));
      expect(
        schreibZugriffe.single[StartseitenAnordnung.spalteKacheln],
        meine,
        reason: 'genau meine Anordnung, unveraendert',
      );
      expect(
        kontoProfil[StartseitenAnordnung.spalteKacheln],
        meine,
        reason: 'liegt danach am Konto',
      );
    });

    test('neues Handy: das Konto gewinnt und es wird nichts hochgeladen',
        () async {
      final vomKonto = kacheln(['xp', 'streak']);
      kontoProfil[StartseitenAnordnung.spalteKacheln] = vomKonto;
      kontoProfil[StartseitenAnordnung.spalteStand] = frueher
          .toUtc()
          .toIso8601String();

      final ergebnis = await StartseitenAnordnung.abgleichen(
        geraetKacheln: null,
        geraetStand: null,
      );

      expect(ergebnis.herkunft, AnordnungHerkunft.server);
      expect(ergebnis.kacheln, vomKonto);
      expect(ergebnis.stand, isNotNull);
      expect(schreibZugriffe, isEmpty);
    });

    test('kein Netz beim Lesen: unbekannt, und NICHTS wird angefasst',
        () async {
      StartseitenAnordnung.profilLeserFuerTests = () async =>
          throw Exception('kein Netz');

      final ergebnis = await StartseitenAnordnung.abgleichen(
        geraetKacheln: kacheln(['xp']),
        geraetStand: jetzt,
      );

      // Wichtig: NICHT `standard`. Ein fehlgeschlagener Abgleich darf nie
      // aussehen wie „das Konto hat nichts" — sonst faellt die Startseite auf
      // die Standard-Kacheln zurueck.
      expect(ergebnis.herkunft, AnordnungHerkunft.unbekannt);
      expect(schreibZugriffe, isEmpty);
    });

    test('kein Netz beim Hochladen: es fliegt nichts, das Geraet behaelt '
        'seine Anordnung', () async {
      StartseitenAnordnung.profilSchreiberFuerTests = (werte) async =>
          throw Exception('kein Netz');

      final ergebnis = await StartseitenAnordnung.abgleichen(
        geraetKacheln: kacheln(['xp']),
        geraetStand: jetzt,
      );

      expect(ergebnis.herkunft, AnordnungHerkunft.geraet);
      expect(ergebnis.stand, jetzt);
    });

    test('zwei Geraete: das aeltere Geraet ueberschreibt das juengere nicht',
        () async {
      // Handy B hat um 20 Uhr verschoben und hochgeladen.
      final vonB = kacheln(['rangliste', 'xp']);
      kontoProfil[StartseitenAnordnung.spalteKacheln] = vonB;
      kontoProfil[StartseitenAnordnung.spalteStand] = jetzt
          .toUtc()
          .toIso8601String();

      // Handy A hatte um 18 Uhr ohne Netz verschoben und meldet sich jetzt.
      final ergebnis = await StartseitenAnordnung.abgleichen(
        geraetKacheln: kacheln(['xp']),
        geraetStand: frueher,
      );

      expect(ergebnis.herkunft, AnordnungHerkunft.server);
      expect(schreibZugriffe, isEmpty);
      expect(kontoProfil[StartseitenAnordnung.spalteKacheln], vonB);
    });

    test('leere Liste am Konto zaehlt als „nichts"', () async {
      kontoProfil[StartseitenAnordnung.spalteKacheln] = <dynamic>[];

      final ergebnis = await StartseitenAnordnung.abgleichen(
        geraetKacheln: kacheln(['xp']),
        geraetStand: jetzt,
      );

      expect(ergebnis.herkunft, AnordnungHerkunft.geraet);
      expect(schreibZugriffe, hasLength(1));
    });

    test('hochladen schickt beide Spalten in EINEM Schreibvorgang', () async {
      final ok = await StartseitenAnordnung.hochladen(kacheln(['xp']), jetzt);

      expect(ok, isTrue);
      expect(schreibZugriffe, hasLength(1));
      expect(
        schreibZugriffe.single.keys.toSet(),
        {StartseitenAnordnung.spalteKacheln, StartseitenAnordnung.spalteStand},
      );
      expect(
        schreibZugriffe.single[StartseitenAnordnung.spalteStand],
        jetzt.toUtc().toIso8601String(),
        reason: 'immer UTC, sonst verschiebt ein Zeitzonenwechsel den Stand',
      );
    });
  });

  // -------------------------------------------------------------------
  // 3. Eine Kachel, die es nicht mehr gibt
  // -------------------------------------------------------------------
  group('nurBekannteKacheln', () {
    const bekannt = {'xp', 'streak', 'rangliste'};

    test('unbekannte Kachel unter bekannten kostet nur sich selbst', () {
      final uebrig = StartseitenAnordnung.nurBekannteKacheln([
        {
          'key': 'xp',
          'widgetIds': ['xp'],
          'size': 'large',
        },
        {
          'key': 'quantensprung',
          'widgetIds': ['quantensprung'],
          'size': 'small',
        },
        {
          'key': 'streak',
          'widgetIds': ['streak'],
          'size': 'small',
        },
      ], bekannt);

      expect(uebrig, isNotNull);
      expect(uebrig!.map((k) => k['key']), ['xp', 'streak']);
    });

    test('im Ordner faellt nur die unbekannte Kachel weg', () {
      final uebrig = StartseitenAnordnung.nurBekannteKacheln([
        {
          'key': 'ordner',
          'widgetIds': ['xp', 'quantensprung', 'streak'],
          'size': 'large',
          'title': 'Meine Zahlen',
        },
      ], bekannt);

      expect(uebrig, hasLength(1));
      expect(uebrig!.single['widgetIds'], ['xp', 'streak']);
      expect(uebrig.single['title'], 'Meine Zahlen', reason: 'bleibt stehen');
    });

    test('ALLE Kacheln unbekannt -> null, damit die Startseite nicht leer '
        'wird', () {
      // Der gefaehrlichste Fall. Vorher kam hier eine LEERE Liste heraus, und
      // die wurde anstandslos angezeigt: eine Startseite ohne einen einzigen
      // Inhalt. `null` heisst fuer den Aufrufer „Anzeige nicht anfassen" —
      // es bleiben die Standard-Kacheln stehen.
      final uebrig = StartseitenAnordnung.nurBekannteKacheln([
        {
          'key': 'a',
          'widgetIds': ['quantensprung'],
          'size': 'large',
        },
        {
          'key': 'b',
          'widgetIds': ['warpantrieb'],
          'size': 'small',
        },
      ], bekannt);

      expect(uebrig, isNull);
    });

    test('Muell statt Liste, Muell in der Liste -> null bzw. uebersprungen',
        () {
      expect(StartseitenAnordnung.nurBekannteKacheln(null, bekannt), isNull);
      expect(
        StartseitenAnordnung.nurBekannteKacheln('kaputt', bekannt),
        isNull,
      );
      expect(
        StartseitenAnordnung.nurBekannteKacheln([
          'kaputt',
          42,
          {'key': 'ohneIds'},
          {
            'key': 'xp',
            'widgetIds': ['xp'],
          },
        ], bekannt),
        hasLength(1),
      );
    });
  });
}
