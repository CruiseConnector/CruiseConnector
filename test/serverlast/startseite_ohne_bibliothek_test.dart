// 2026-08-31 — Waechter: Die Startseite laedt nicht mehr die ganze
// Streckenbibliothek.
//
// WARUM ES DIESEN TEST GIBT
//
// _loadStats() holte die VOLLSTAENDIGE Bibliothek des Nutzers — gemessen an
// der Produktionsdatenbank im Schnitt 1315 kB, im 90. Perzentil 4139 kB, im
// schlimmsten Fall 7060 kB bei 162 Strecken. Gelesen wurden daraus genau zwei
// Dinge: eine Anzahl und ein Wahrheitswert fuer den Speichern-Haken.
//
// Beides geht ohne die Bibliothek:
//   * Die Anzahl liefert GamificationResult.savedRoutes mit. Sie stammt aus
//     einer Abfrage, die nur `id, source_route_id` holt, und sie laeuft
//     ohnehin bei jedem calculateAndSync. Nebenbei behebt das eine
//     Unstimmigkeit: Fortschrittsbalken und Freischaltung von badge_09
//     stammten vorher aus zwei verschiedenen Zaehlungen.
//   * Den Haken beantwortet SavedRoutesService.
//     liegtGleichwertigeStreckeInDerSammlung mit hoechstens zwei winzigen
//     Abfragen.
//
// Der Rueckschritt waere lautlos: Wer getSavedRouteLibrary() hier wieder
// aufruft, sieht keinen Fehler — die App laedt nur wieder Megabyte bei jedem
// Aufbau der Startseite.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Startseite kommt ohne die Streckenbibliothek aus', () {
    late String startseite;

    setUpAll(() {
      startseite = File(
        'lib/presentation/pages/home_content_page.dart',
      ).readAsStringSync();
    });

    test('getSavedRouteLibrary wird nicht mehr aufgerufen', () {
      expect(
        startseite.contains('getSavedRouteLibrary'),
        isFalse,
        reason:
            'Die Startseite laedt wieder die ganze Streckenbibliothek. '
            'Gemessen sind das im Schnitt 1315 kB und im schlimmsten Fall '
            '7060 kB, fuer eine Anzahl und einen Wahrheitswert. Die Anzahl '
            'steht in result.savedRoutes, den Wahrheitswert liefert '
            'SavedRoutesService.liegtGleichwertigeStreckeInDerSammlung.',
      );
    });

    test('der Speichern-Haken wird gezielt erfragt', () {
      expect(
        startseite.contains('liegtGleichwertigeStreckeInDerSammlung'),
        isTrue,
        reason:
            'Ohne die gezielte Abfrage kann der Haken nur noch aus einer '
            'geladenen Liste kommen — und die soll es hier nicht mehr geben.',
      );
      expect(
        startseite.contains('hasEquivalentSavedRoute'),
        isFalse,
        reason:
            'hasEquivalentSavedRoute vergleicht gegen eine LISTE. Wer es hier '
            'benutzt, muss die Liste vorher laden.',
      );
    });

    test('die Anzahl kommt aus der Auswertung, nicht aus einer Liste', () {
      expect(
        startseite.contains('_savedRouteCount = result.savedRoutes'),
        isTrue,
        reason:
            'Die Anzahl muss aus GamificationResult kommen. Nur dann zeigt '
            'der Fortschrittsbalken von badge_09 dieselbe Zahl, aus der die '
            'Freischaltung gerechnet wird.',
      );
    });
  });

  group('Die gezielte Pruefung fragt sicher', () {
    late String dienst;

    setUpAll(() {
      dienst = File(
        'lib/data/services/saved_routes_service.dart',
      ).readAsStringSync();
    });

    /// Der Rumpf von liegtGleichwertigeStreckeInDerSammlung.
    String rumpf() {
      final start = dienst.indexOf(
        'static Future<bool> liegtGleichwertigeStreckeInDerSammlung(',
      );
      expect(
        start,
        greaterThanOrEqualTo(0),
        reason: 'Die Methode gibt es nicht mehr. Waechter mitziehen.',
      );
      final ende = dienst.indexOf('\n  static ', start + 10);
      return dienst.substring(start, ende > 0 ? ende : dienst.length);
    }

    test('sie filtert IMMER auf den angemeldeten Nutzer', () {
      final koerper = rumpf();
      final abfragen = "from('routes')".allMatches(koerper).length;
      final filter = "eq('user_id', userId)".allMatches(koerper).length;
      expect(abfragen, greaterThan(0));
      expect(
        filter,
        abfragen,
        reason:
            'Jede Abfrage auf routes MUSS auf user_id filtern. Belegt an den '
            'Echtdaten: derselbe Fingerprint kommt bei mehreren Nutzern vor, '
            'weil zwei Leute dieselbe Strecke speichern koennen. Ohne den '
            'Filter meldet die App „schon gespeichert", weil es JEMAND '
            'ANDERES gespeichert hat.',
      );
    });

    test('sie prueft die Kennung, bevor sie danach fragt', () {
      expect(
        rumpf().contains('_siehtWieKennungAus'),
        isTrue,
        reason:
            'Eine oertlich erzeugte Strecke traegt keine Kennung im '
            'uuid-Format. Ein Vergleich damit bricht serverseitig mit einem '
            'Typfehler ab, statt schlicht „nein" zu sagen.',
      );
    });

    test('sie laedt selbst keine Geometrie', () {
      expect(
        RegExp(r"select\('id'\)").allMatches(rumpf()).length,
        greaterThan(0),
        reason:
            'Die Abfragen duerfen nur die Kennung holen. Ein select() ohne '
            'Spaltenliste zoege die Geometrie mit und machte den ganzen '
            'Umbau zunichte.',
      );
      expect(
        RegExp(r"\.select\(\)").hasMatch(rumpf()),
        isFalse,
        reason: 'Ein select() ohne Spaltenliste holt alle Spalten.',
      );
    });

    test('saveExistingRoute prueft weiterhin vollstaendig', () {
      // Bewusst NICHT umgestellt: Hier entscheidet sich, ob eine doppelte
      // Zeile entsteht. Die gezielte Abfrage kann bei einer der 162 Altzeilen
      // ohne Fingerprint „nein" sagen; ein leerer Haken ist folgenlos, eine
      // doppelte Zeile waere es nicht.
      final start = dienst.indexOf(
        'static Future<void> saveExistingRoute(',
      );
      expect(start, greaterThanOrEqualTo(0));
      final koerper = dienst.substring(start, start + 1200);
      expect(
        koerper.contains('hasEquivalentSavedRoute'),
        isTrue,
        reason:
            'saveExistingRoute muss weiterhin gegen die ganze Bibliothek '
            'pruefen. 162 Zeilen tragen keinen Fingerprint (alle aelter als '
            '90 Tage); fuer die ist der Vergleich ueber die Geometrie der '
            'einzige Weg. Hier waere ein falsches „nein" eine doppelte Zeile '
            'in der Sammlung des Nutzers.',
      );
    });
  });
}
