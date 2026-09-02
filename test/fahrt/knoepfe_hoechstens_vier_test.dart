// 2026-09-02 — Vucko, Sprachnachricht:
//   "ich [moechte] die buttons rechts waehrend der fahrt minimieren ... die
//    lautstaerke passt das man es einstellen kann wenns geht noch etwas
//    praeziser, das melden von buttons auch und das zentrieren auch aber die
//    meldung bzw das man baustellen ein oder ausschalten soll kann weg oder in
//    die poi liste rein und das mit dem ganze karte sehen kann auch weg es
//    sollen maximal 4 buttons da sein im moment ist das zu viel"
//
// WAS VORHER WAR
//
// Die rechte Spalte war fest verdrahtet und zeigte waehrend einer bestaetigten
// Fahrt bis zu SECHS Knoepfe. Der Quelltext gab das Problem selbst zu: "Bei
// bottom:260 ragte die Spalte auf kleinen Geraeten ins Manoever-Banner", und
// der Notbehelf war ein Scrollbereich, der oben abschnitt. Knoepfe, an die man
// waehrend der Fahrt erst heranscrollen muss, sind keine Bedienung.
//
// Diese Tests halten die vier Zusagen fest, die sich daraus ergeben.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/fahrt_knoepfe_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FahrtKnoepfeService.instance.zuruecksetzenFuerTest();
  });

  group('Hoechstens vier', () {
    test('die Obergrenze ist vier und steht an EINER Stelle', () {
      expect(FahrtKnoepfeService.hoechstens, 4);
      expect(FahrtKnoepfeService.voreinstellung.length, 4);
    });

    test('der fuenfte Knopf wird abgelehnt, nicht still eingetauscht', () async {
      final d = FahrtKnoepfeService.instance;
      await d.laden();
      expect(d.auswahl.length, 4);

      final vorher = d.auswahl.toList();
      final ging = await d.umschalten(FahrKnopf.uebersicht);

      expect(
        ging,
        isFalse,
        reason: 'Der Aufrufer muss erfahren, dass es nicht ging.',
      );
      expect(
        d.auswahl,
        orderedEquals(vorher),
        reason:
            'Still den aeltesten hinauszuwerfen waere eine Ueberraschung. '
            'Der Nutzer soll erst einen wegnehmen.',
      );
    });

    test('nach dem Wegnehmen passt ein anderer hinein', () async {
      final d = FahrtKnoepfeService.instance;
      await d.laden();
      await d.umschalten(FahrKnopf.melden);
      expect(d.auswahl.length, 3);

      final ging = await d.umschalten(FahrKnopf.uebersicht);
      expect(ging, isTrue);
      expect(d.auswahl.length, 4);
      expect(d.auswahl.last, FahrKnopf.uebersicht);
    });

    test('gar keinen zu waehlen ist erlaubt', () async {
      // Eine leere Spalte ist eine gueltige Entscheidung. Waehrend der Fahrt
      // bleibt dann nur der Griff zum Ausklappen stehen.
      final d = FahrtKnoepfeService.instance;
      await d.laden();
      for (final k in d.auswahl.toList()) {
        await d.umschalten(k);
      }
      expect(d.auswahl, isEmpty);
    });
  });

  group('Die Voreinstellung ist genau das, was Vucko behalten wollte', () {
    test('POI, Stimme, Zentrieren und Melden', () {
      expect(
        FahrtKnoepfeService.voreinstellung,
        orderedEquals(const [
          FahrKnopf.poi,
          FahrKnopf.stimme,
          FahrKnopf.zentrieren,
          FahrKnopf.melden,
        ]),
      );
    });

    test('die beiden gestrichenen sind nicht mehr voreingestellt', () {
      // "die meldung bzw das man baustellen ein oder ausschalten soll kann weg
      // oder in die poi liste rein und das mit dem ganze karte sehen kann auch
      // weg". Waehlbar bleiben sie, voreingestellt nicht.
      expect(
        FahrtKnoepfeService.voreinstellung,
        isNot(contains(FahrKnopf.meldungen)),
      );
      expect(
        FahrtKnoepfeService.voreinstellung,
        isNot(contains(FahrKnopf.uebersicht)),
      );
      expect(FahrtKnoepfeService.alle.length, FahrKnopf.values.length,
          reason: 'Jeder Knopf braucht einen Eintrag fuer die Einstellungen.');
    });
  });

  group('Die Auswahl ueberlebt einen Neustart', () {
    test('gespeichert wird die Kennung, nicht der Aufzaehlungsname', () async {
      // Sonst zerstoert eine Umbenennung im Code die Auswahl aller Nutzer.
      final quelle = File(
        'lib/data/services/fahrt_knoepfe_service.dart',
      ).readAsStringSync();
      expect(quelle.contains('e.kennung'), isTrue);
      expect(
        quelle.contains('.map((e) => e.name)'),
        isFalse,
        reason: 'name ist der Bezeichner aus dem Code und darf nicht in die '
            'gespeicherten Einstellungen wandern.',
      );
    });

    test('eine unbekannte Kennung wird uebersprungen, nicht geworfen', () async {
      SharedPreferences.setMockInitialValues({
        'fahrt_knoepfe_auswahl_v1': ['poi', 'gibtesnichtmehr', 'stimme'],
      });
      FahrtKnoepfeService.instance.zuruecksetzenFuerTest();
      final d = FahrtKnoepfeService.instance;
      await d.laden();
      expect(
        d.auswahl,
        orderedEquals(const [FahrKnopf.poi, FahrKnopf.stimme]),
        reason:
            'Wer eine aeltere Fassung benutzt hat, darf beim Update nicht in '
            'einer leeren oder kaputten Leiste landen.',
      );
    });

    test('mehr als vier gespeicherte Werte werden beschnitten', () async {
      SharedPreferences.setMockInitialValues({
        'fahrt_knoepfe_auswahl_v1': [
          'poi', 'stimme', 'zentrieren', 'melden', 'uebersicht', 'meldungen',
        ],
      });
      FahrtKnoepfeService.instance.zuruecksetzenFuerTest();
      await FahrtKnoepfeService.instance.laden();
      expect(FahrtKnoepfeService.instance.auswahl.length, 4);
    });

    test('doppelte Werte kommen nur einmal an', () async {
      SharedPreferences.setMockInitialValues({
        'fahrt_knoepfe_auswahl_v1': ['poi', 'poi', 'stimme'],
      });
      FahrtKnoepfeService.instance.zuruecksetzenFuerTest();
      await FahrtKnoepfeService.instance.laden();
      expect(
        FahrtKnoepfeService.instance.auswahl,
        orderedEquals(const [FahrKnopf.poi, FahrKnopf.stimme]),
      );
    });

    test('der eingeklappte Zustand bleibt erhalten', () async {
      final d = FahrtKnoepfeService.instance;
      await d.laden();
      expect(d.eingeklappt, isFalse);
      await d.setzeEingeklappt(true);

      d.zuruecksetzenFuerTest();
      await d.laden();
      expect(
        d.eingeklappt,
        isTrue,
        reason: 'Wer die Leiste einmal weggeklappt hat, will sie beim '
            'naechsten Start nicht wieder vor der Karte haben.',
      );
    });
  });

  group('Die Fahransicht baut aus dem Dienst, nicht aus einer festen Liste',
      () {
    late String quelle;

    setUpAll(() {
      quelle = File(
        'lib/presentation/pages/cruise_mode_page.dart',
      ).readAsStringSync();
    });

    test('der Scrollbereich mit reverse ist weg', () {
      // Er war der Notbehelf gegen die zu hohe Spalte. Mit vier Knoepfen
      // braucht es ihn nicht mehr, und er verdeckte, dass oben abgeschnitten
      // wurde.
      final i = quelle.indexOf('Widget _buildFabColumn(');
      expect(i, greaterThan(0));
      final block = quelle.substring(i, i + 2600);
      expect(
        block.contains('reverse: true'),
        isFalse,
        reason: 'Knoepfe, an die man erst heranscrollen muss, sind waehrend '
            'der Fahrt unbrauchbar.',
      );
    });

    test('die Spalte fragt den Dienst', () {
      expect(quelle.contains('FahrtKnoepfeService.instance'), isTrue);
      expect(quelle.contains('for (final k in sichtbar) _buildFahrKnopf(k)'),
          isTrue);
    });

    test('der Griff zum Einklappen ist da', () {
      expect(quelle.contains('_buildEinklappGriff('), isTrue);
      expect(quelle.contains('einklappenUmschalten()'), isTrue);
    });

    test('der Simulator belegt keinen der vier Plaetze', () {
      // Er ist nur in der Entwicklerfassung da und darf dem Fahrer keinen
      // Platz wegnehmen.
      final i = quelle.indexOf('_buildFabColumnInhalt(');
      expect(i, greaterThan(0));
      final block = quelle.substring(i, i + 2200);
      expect(block.contains('kDebugMode'), isTrue);
      expect(
        block.contains("heroTag: 'sim_drive_fab'"),
        isTrue,
        reason: 'Der Simulator steht ausserhalb der gewaehlten vier.',
      );
    });

    test('ein Knopf ohne Route wird nicht als toter Knopf gezeigt', () {
      expect(quelle.contains('if (!info.brauchtRoute) return true;'), isTrue);
      expect(
        quelle.contains(
          'if (k == FahrKnopf.melden) return hasRoute && _isRouteConfirmed;',
        ),
        isTrue,
        reason: 'Melden ohne bestaetigte Fahrt haette nichts zu melden.',
      );
    });
  });

  group('Der Meldungs-Schalter liegt in der POI-Liste', () {
    test('das Blatt nimmt ihn entgegen', () {
      final quelle = File(
        'lib/presentation/widgets/cruise/poi_filter_sheet.dart',
      ).readAsStringSync();
      expect(quelle.contains('final bool? meldungenAn;'), isTrue);
      expect(quelle.contains('final VoidCallback? onMeldungenUmschalten;'),
          isTrue);
      expect(
        quelle.contains('class _MeldungenZeile'),
        isTrue,
        reason: 'Vucko: "kann weg oder in die poi liste rein".',
      );
    });

    test('die Fahransicht reicht ihn durch', () {
      final quelle = File(
        'lib/presentation/pages/cruise_mode_page.dart',
      ).readAsStringSync();
      expect(quelle.contains('meldungenAn: _meldungenAnzeigen'), isTrue);
      expect(
        quelle.contains('onMeldungenUmschalten: _meldungenSchalterUmschalten'),
        isTrue,
      );
    });
  });

  group('Die Lautstaerke laesst sich feiner einstellen', () {
    test('ein Prozentpunkt je Raste statt sechs', () {
      // Der Regler laeuft von 65 auf 100 Prozent. Mit 6 Stufen waren das
      // Spruenge von rund sechs Prozentpunkten und nur sieben erreichbare
      // Werte. Vucko: "wenns geht noch etwas praeziser".
      final quelle = File(
        'lib/presentation/widgets/cruise/voice_volume_sheet.dart',
      ).readAsStringSync();
      expect(quelle.contains('divisions: 35'), isTrue);
      expect(quelle.contains('divisions: 6,'), isFalse);
    });
  });
}
