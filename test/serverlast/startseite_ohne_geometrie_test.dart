// 2026-08-31 — Waechter: Die Startseite darf keine Geometrien mehr laden.
//
// WARUM ES DIESEN TEST GIBT
//
// Der Empfehlungsdienst holte 120 Pool-Strecken MIT den Spalten `geometry` und
// `route_payload`, filterte und bewertete sie und waehlte am Ende GENAU EINE
// aus. 119 Geometrien wurden geladen und weggeworfen — bei jedem Kaltstart.
//
// Gemessen an der Produktionsdatenbank am 31.08.:
//   * 120 Zeilen mit Geometrie:  680 ms, 3040 kB
//   * 120 Zeilen nur Kopfdaten:    3 ms,   35 kB
//   plus einmal rund 25 kB fuer die eine ausgewaehlte Strecke.
//   Das ist Faktor 227 in der Zeit und 98 Prozent weniger Bytes.
//
// Nicht der Abfrageplan war das Problem, sondern die Nutzlast: mit Filter und
// Sortierung laeuft dieselbe Abfrage ohne die beiden Spalten in 2 ms ueber
// alle 2778 Zeilen. Ein Index waere deshalb nutzlos gewesen.
//
// Der Rueckschritt waere lautlos: Wer `geometry` wieder in die Spaltenliste
// schreibt, merkt nichts — die App funktioniert weiter, nur eben wieder mit
// drei Megabyte pro Start. Genau davor schuetzt dieser Test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/home_route_recommendation_service.dart';
import 'package:cruise_connect/domain/models/route_pool_entry.dart';

/// Eine Strecke mit frei waehlbaren Kennzahlen. Alles Uebrige ist so gesetzt,
/// dass der Filter allein an den geprueften Werten haengt.
RoutePoolEntry strecke({
  int? punktAnzahl,
  double? maxSegmentMeter,
  String? geometrieQuelle,
  bool? autobahnVerstoss,
  // Standard: gemessen und sauber. Sonst haengt jeder Test dieser Datei an
  // dem Wende-Tor statt an dem, was er eigentlich prueft.
  int? kehrtwendenMitte = 0,
  Map<String, dynamic> geometry = const {},
  Map<String, dynamic> routePayload = const {},
  int distanceBucket = 50,
  double distanceKm = 50,
  double qualityScore = 90,
}) {
  return RoutePoolEntry(
    id: 'test',
    countryCode: 'AT',
    admin1Name: 'Vorarlberg',
    cityCluster: 'bregenz',
    startLat: 47.5,
    startLng: 9.7,
    distanceKm: distanceKm,
    distanceBucket: distanceBucket,
    routeType: 'ROUND_TRIP',
    styleTags: const [],
    avoidsHighway: false,
    hasHighway: false,
    qualityScore: qualityScore,
    verified: true,
    geometry: geometry,
    routePayload: routePayload,
    kehrtwendenMitte: kehrtwendenMitte,
    punktAnzahl: punktAnzahl,
    maxSegmentMeter: maxSegmentMeter,
    geometrieQuelle: geometrieQuelle,
    autobahnVerstoss: autobahnVerstoss,
  );
}

/// Eine echte Geometrie mit [n] Punkten, je [meterProSchritt] auseinander.
Map<String, dynamic> geometrieMit(int n, {double meterProSchritt = 100}) {
  const meterProGrad = 111320.0;
  return {
    'coordinates': List.generate(
      n,
      (i) => [9.7, 47.5 + i * (meterProSchritt / meterProGrad)],
    ),
  };
}

void main() {
  group('Die Abfrage der Startseite laedt keine Geometrie', () {
    late String quelle;

    setUpAll(() {
      quelle = File(
        'lib/data/services/home_route_recommendation_service.dart',
      ).readAsStringSync();
    });

    /// Die Spaltennamen aus _routePoolSelect, einzeln.
    ///
    /// Die Konstante ist in Dart aus mehreren Teilzeichenketten
    /// zusammengesetzt. Erst die Anfuehrungszeichen entfernen, dann an den
    /// Kommas trennen — sonst uebersieht der Test eine Spalte, die mitten in
    /// einem Teilstueck steht. Genau daran ist die erste Fassung dieses
    /// Waechters gescheitert: sie suchte nach "'geometry" mit fuehrendem
    /// Anfuehrungszeichen und liess `...,is_active,geometry,shape_score,...`
    /// glatt durch.
    Set<String> listenSpalten() {
      final treffer = RegExp(
        r"static const String _routePoolSelect\s*=\s*([\s\S]*?);",
      ).firstMatch(quelle);
      expect(
        treffer,
        isNotNull,
        reason:
            'Die Konstante _routePoolSelect gibt es nicht mehr. Wurde sie '
            'umbenannt? Dann diesen Waechter mitziehen.',
      );
      final roh = treffer!
          .group(1)!
          .replaceAll(RegExp(r"'"), '')
          .replaceAll(RegExp(r'\s+'), '');
      return roh
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
    }

    test('weder geometry noch route_payload stehen in der Liste', () {
      final spalten = listenSpalten();
      for (final verboten in ['geometry', 'route_payload']) {
        expect(
          spalten.contains(verboten),
          isFalse,
          reason:
              'Die Spalte "$verboten" steht wieder in _routePoolSelect. Damit '
              'laedt die Startseite bei jedem Kaltstart erneut rund 3040 kB '
              'statt 35 kB, nur um EINE Empfehlung anzuzeigen. Die '
              'ausgewaehlte Strecke wird ueber _ladeGeometrieNach einzeln '
              'geholt; die Liste braucht beides nicht.',
        );
      }
    });

    test('die vier Kennzahlen stehen drin, sonst filtert nichts mehr', () {
      final spalten = listenSpalten();
      for (final noetig in [
        'punkt_anzahl',
        'max_segment_meter',
        'geometrie_quelle',
        'autobahn_verstoss',
      ]) {
        expect(
          spalten.contains(noetig),
          isTrue,
          reason:
              'Die Spalte "$noetig" fehlt in _routePoolSelect. Ohne sie kann '
              'der Sicherheitsfilter ohne Geometrie nicht mehr pruefen und '
              'laesst unsichere Strecken durch.',
        );
      }
    });

    test('die ausgewaehlte Strecke wird einzeln nachgeholt', () {
      expect(
        quelle,
        contains('_ladeGeometrieNach'),
        reason:
            'Ohne das Nachladen bekaeme die Empfehlungskachel eine leere '
            'Karte und „Losfahren" liefe ins Leere.',
      );
      expect(
        RegExp(r"_routePoolGeometrieSelect\s*=\s*'geometry,route_payload'")
            .hasMatch(quelle),
        isTrue,
        reason: 'Das Nachladen muss genau die beiden grossen Spalten holen.',
      );
    });
  });

  group('Der Filter urteilt mit Kennzahlen wie frueher mit der Geometrie', () {
    test('zu wenige Punkte werden verworfen, genug Punkte nicht', () {
      // Schwelle bei distanceBucket 50 ist 20 Punkte.
      expect(
        HomeRouteRecommendationService.istSichereStartseitenStrecke(
          strecke(punktAnzahl: 19, maxSegmentMeter: 100),
        ),
        isFalse,
      );
      expect(
        HomeRouteRecommendationService.istSichereStartseitenStrecke(
          strecke(punktAnzahl: 20, maxSegmentMeter: 100),
        ),
        isTrue,
      );
    });

    test('ein zu grosser Sprung wird verworfen', () {
      // Schwelle bei distanceBucket 50 ist 1800 m.
      expect(
        HomeRouteRecommendationService.istSichereStartseitenStrecke(
          strecke(punktAnzahl: 500, maxSegmentMeter: 1801),
        ),
        isFalse,
      );
      expect(
        HomeRouteRecommendationService.istSichereStartseitenStrecke(
          strecke(punktAnzahl: 500, maxSegmentMeter: 1799),
        ),
        isTrue,
      );
    });

    test('eine unsichere Herkunft wird verworfen', () {
      for (final quelle in [
        'candidate_plan',
        'pre_hydration',
        'sparse',
        'straight_line',
        'fallback_line',
        'synthetic',
      ]) {
        expect(
          HomeRouteRecommendationService.istSichereStartseitenStrecke(
            strecke(
              punktAnzahl: 500,
              maxSegmentMeter: 100,
              geometrieQuelle: quelle,
            ),
          ),
          isFalse,
          reason: 'Herkunft "$quelle" haette verworfen werden muessen.',
        );
      }
    });

    test('die Autobahn-Markierung wird verworfen', () {
      expect(
        HomeRouteRecommendationService.istSichereStartseitenStrecke(
          strecke(
            punktAnzahl: 500,
            maxSegmentMeter: 100,
            autobahnVerstoss: true,
          ),
        ),
        isFalse,
      );
    });

    test(
      'REGRESSION: Kennzahl und Live-Berechnung faellen dasselbe Urteil',
      () {
        // Dieselbe Strecke einmal mit vorberechneten Werten, einmal nur mit
        // Geometrie. Beide Wege muessen gleich entscheiden — sonst haette der
        // Umbau die Auswahl still veraendert.
        for (final fall in [
          (punkte: 19, meter: 100.0, erwartet: false), // zu wenige Punkte
          (punkte: 40, meter: 100.0, erwartet: true), // in Ordnung
          (punkte: 40, meter: 2000.0, erwartet: false), // Sprung zu gross
        ]) {
          final ausKennzahl =
              HomeRouteRecommendationService.istSichereStartseitenStrecke(
                strecke(
                  punktAnzahl: fall.punkte,
                  maxSegmentMeter: fall.meter,
                ),
              );
          final ausGeometrie =
              HomeRouteRecommendationService.istSichereStartseitenStrecke(
                strecke(
                  geometry: geometrieMit(
                    fall.punkte,
                    meterProSchritt: fall.meter,
                  ),
                ),
              );
          expect(
            ausKennzahl,
            fall.erwartet,
            reason: 'Kennzahl-Weg bei $fall',
          );
          expect(
            ausGeometrie,
            fall.erwartet,
            reason:
                'Rueckfall auf die Geometrie bei $fall — beide Wege muessen '
                'gleich entscheiden.',
          );
        }
      },
    );

    test(
      'ohne Kennzahl UND ohne Geometrie wird AUSGESCHLOSSEN',
      () {
        // 2026-09-01 umgedreht. Hier stand das Gegenteil, mit der Begruendung
        // "eine fehlende Messung ist kein Beweis fuer eine schlechte Strecke,
        // eine leere Startseite waere der gefaehrlichere Fehler". Beides war
        // falsch gedacht:
        //
        // Seit die Abfrage die Geometrie bewusst nicht mehr mitholt, ist die
        // Kennzahl die EINZIGE Quelle. Faellt sie aus, laufen alle vier
        // Sicherheitspruefungen ins Leere und eine voellig ungepruefte Strecke
        // landet auf der Startseite — ein Sicherheitsfilter, der bei
        // fehlender Messung durchlaesst, ist keiner. Und leer wird die
        // Startseite davon nicht: es liegen 2778 Pool-Zeilen bereit, die
        // naechste rueckt nach.
        expect(
          HomeRouteRecommendationService.istSichereStartseitenStrecke(
            strecke(),
          ),
          isFalse,
          reason: 'Eine unpruefbare Strecke gehoert nicht auf die Startseite.',
        );
      },
    );

    test('mit Kennzahlen urteilt der Filter wie bisher', () {
      expect(
        HomeRouteRecommendationService.istSichereStartseitenStrecke(
          strecke(punktAnzahl: 500, maxSegmentMeter: 100),
        ),
        isTrue,
        reason: 'Eine gemessene, unauffaellige Strecke bleibt zulaessig.',
      );
    });

    test('die harten Ausschluesse gelten unveraendert weiter', () {
      expect(
        HomeRouteRecommendationService.istSichereStartseitenStrecke(
          strecke(punktAnzahl: 500, maxSegmentMeter: 100, qualityScore: 69),
        ),
        isFalse,
        reason: 'Qualitaet unter 70 bleibt ausgeschlossen.',
      );
      expect(
        HomeRouteRecommendationService.istSichereStartseitenStrecke(
          strecke(punktAnzahl: 500, maxSegmentMeter: 100, distanceKm: 4.9),
        ),
        isFalse,
        reason: 'Unter 5 km bleibt ausgeschlossen.',
      );
    });
  });
}
