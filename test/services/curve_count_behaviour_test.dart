import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/gamification_service.dart';

/// 2026-07-28 (vucko): „Analysiere nochmal, wie die Kurven für die Fahrt
/// ermittelt werden. Manchmal stimmt es nicht."
///
/// Diese Datei hält das TATSÄCHLICHE Verhalten von [GamificationService.
/// countCurves] fest — inklusive der bewussten Grenzen. Bisher gab es dafür
/// keinen einzigen Test; `test/route/curve_detection_test.dart` prüft eine
/// ganz andere Klasse (die Live-Kurvenwarnung).
///
/// Der Zähler arbeitet so: Strecke auf feste 20 m resampeln, pro Stützpunkt
/// den vorzeichenbehafteten Abbiegewinkel bilden, unter 2° gilt als geradeaus,
/// 60 m geradeaus beenden einen Bogen, ein Richtungswechsel startet einen
/// neuen, und ab 40° kumulierter Drehung zählt der Bogen als eine Kurve.
void main() {
  /// Baut eine Strecke aus Segmenten mit fester Länge und Richtungsänderung.
  /// [drehungenProSegment] ist die Kursänderung in Grad je Segment.
  List<List<double>> strecke(
    List<double> drehungenProSegment, {
    double segmentM = 20.0,
    double startLat = 47.4,
    double startLng = 9.7,
  }) {
    final punkte = <List<double>>[
      [startLng, startLat],
    ];
    var kurs = 0.0; // Grad, 0 = Norden
    var lat = startLat;
    var lng = startLng;
    for (final d in drehungenProSegment) {
      kurs += d;
      final rad = kurs * math.pi / 180.0;
      final dLat = (segmentM * math.cos(rad)) / 111320.0;
      final dLng =
          (segmentM * math.sin(rad)) /
          (111320.0 * math.cos(lat * math.pi / 180.0));
      lat += dLat;
      lng += dLng;
      punkte.add([lng, lat]);
    }
    return punkte;
  }

  group('Was zuverlaessig erkannt wird', () {
    test('gerade Strecke ergibt null Kurven', () {
      expect(GamificationService.countCurves(strecke(List.filled(60, 0.0))), 0);
    });

    test('klare Kurve (90 Grad auf kurzer Strecke) zaehlt als eine', () {
      final s = strecke([
        ...List.filled(10, 0.0),
        ...List.filled(6, 15.0), // 90 Grad
        ...List.filled(10, 0.0),
      ]);
      expect(GamificationService.countCurves(s), 1);
    });

    test('S-Kurve zaehlt als zwei', () {
      final s = strecke([
        ...List.filled(5, 0.0),
        ...List.filled(6, 15.0), // rechts
        ...List.filled(6, -15.0), // links
        ...List.filled(5, 0.0),
      ]);
      expect(GamificationService.countCurves(s), 2);
    });

    test('zwei getrennte Kurven mit Gerade dazwischen zaehlen als zwei', () {
      final s = strecke([
        ...List.filled(6, 15.0),
        ...List.filled(10, 0.0), // 200 m geradeaus trennt sicher
        ...List.filled(6, 15.0),
      ]);
      expect(GamificationService.countCurves(s), 2);
    });
  });

  group('Bewusste Grenzen des Zaehlers', () {
    test('alternierendes GPS-Rauschen erzeugt KEINE Phantomkurven', () {
      // Plus/minus 3 Grad im Wechsel auf 2 km gerader Strecke.
      final s = strecke([
        for (var i = 0; i < 100; i++) i.isEven ? 3.0 : -3.0,
      ]);
      expect(
        GamificationService.countCurves(s),
        0,
        reason: 'Der Richtungswechsel setzt den Bogen zurueck — genau dafuer '
            'ist die Vorzeichenpruefung da',
      );
    });

    test('sehr sanfter Bogen unter der 2-Grad-Schwelle zaehlt NICHT', () {
      // 1,5 Grad je 20 m ueber 2 km = 150 Grad Gesamtdrehung.
      final s = strecke(List.filled(100, 1.5));
      expect(
        GamificationService.countCurves(s),
        0,
        reason: 'BEWUSSTE Grenze: ein weiter Autobahnbogen ist fuer einen '
            'Fahrer keine Kurve. Wer das aendert, aendert die XP aller '
            'Nutzer — deshalb hier festgehalten statt still gefixt.',
      );
    });

    test('Spitzkehre und Kreisverkehr zaehlen je als EINE Kurve', () {
      final spitzkehre = strecke([
        ...List.filled(5, 0.0),
        ...List.filled(6, 30.0), // 180 Grad
        ...List.filled(5, 0.0),
      ]);
      final kreisverkehr = strecke([
        ...List.filled(5, 0.0),
        ...List.filled(12, 30.0), // 360 Grad
        ...List.filled(5, 0.0),
      ]);
      expect(GamificationService.countCurves(spitzkehre), 1);
      expect(
        GamificationService.countCurves(kreisverkehr),
        1,
        reason: 'Die Schaerfe eines Bogens fliesst nicht ein — eine knappe '
            '40-Grad-Kurve und ein Kreisverkehr zaehlen gleich',
      );
    });
  });

  group('Robustheit', () {
    test('leere und zu kurze Eingaben stuerzen nicht ab', () {
      expect(GamificationService.countCurves(const []), 0);
      expect(
        GamificationService.countCurves(const [
          [9.7, 47.4],
        ]),
        0,
      );
      expect(
        GamificationService.countCurves(const [
          [9.7, 47.4],
          [9.71, 47.41],
        ]),
        0,
      );
    });

    test('doppelte Punktdichte aendert das Ergebnis nicht wesentlich', () {
      // Dieselbe Geometrie, einmal mit 20-m- und einmal mit 10-m-Segmenten.
      final grob = strecke([
        ...List.filled(5, 0.0),
        ...List.filled(6, 15.0),
        ...List.filled(5, 0.0),
      ]);
      final fein = strecke([
        ...List.filled(10, 0.0),
        ...List.filled(12, 7.5),
        ...List.filled(10, 0.0),
      ], segmentM: 10.0);
      final a = GamificationService.countCurves(grob);
      final b = GamificationService.countCurves(fein);
      expect(
        (a - b).abs(),
        lessThanOrEqualTo(1),
        reason: 'Das interne 20-m-Resampling soll die Punktdichte ausgleichen',
      );
    });
  });
}
