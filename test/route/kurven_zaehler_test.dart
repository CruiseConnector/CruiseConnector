import 'dart:math' as math;

import 'package:cruise_connect/core/kurven_zaehler.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/route_style_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Erzeugt eine Polylinie aus [bogen] Halbkreisen mit Radius [radiusM],
/// jeweils durch ein gerades Stueck von [geradeM] getrennt.
/// Koordinaten sind [lng, lat].
List<List<double>> serpentine({
  required int bogen,
  double radiusM = 60,
  double geradeM = 200,
  double startLat = 47.42,
  double startLng = 9.74,
}) {
  const mProGrad = 111320.0;
  final lngFaktor = math.cos(startLat * math.pi / 180);
  final pts = <List<double>>[];
  var lat = startLat;
  var lng = startLng;
  pts.add([lng, lat]);
  for (var b = 0; b < bogen; b++) {
    final richtung = b.isEven ? 1 : -1;
    for (var s = 1; s <= 18; s++) {
      final w = s / 18 * math.pi;
      final dx = radiusM * math.sin(w) * richtung;
      final dy = radiusM * (1 - math.cos(w));
      pts.add([
        lng + dx / (mProGrad * lngFaktor),
        lat + dy / mProGrad,
      ]);
    }
    lat += 2 * radiusM / mProGrad;
    // gerades Verbindungsstueck
    final schritte = math.max(2, (geradeM / 25).round());
    for (var s = 1; s <= schritte; s++) {
      lat += geradeM / schritte / mProGrad;
      pts.add([lng, lat]);
    }
  }
  return pts;
}

List<List<double>> gerade({double laengeM = 20000, double startLat = 47.42}) {
  const mProGrad = 111320.0;
  final pts = <List<double>>[];
  for (var i = 0; i <= 400; i++) {
    pts.add([9.74, startLat + (laengeM * i / 400) / mProGrad]);
  }
  return pts;
}

double laengeKm(List<List<double>> pts) {
  var m = 0.0;
  for (var i = 1; i < pts.length; i++) {
    m += KurvenZaehler.distanzMeter(pts[i - 1], pts[i]);
  }
  return m / 1000;
}

void main() {
  group('KurvenZaehler', () {
    test('eine Gerade hat keine Kurven', () {
      expect(KurvenZaehler.zaehle(gerade()), 0);
    });

    test('mehr Boegen ergeben mehr Kurven — streng monoton', () {
      // Bewusst keine exakte Zahl: Bei einer Serpentine ist auch das
      // Wieder-Einschwenken auf die Gerade ein echter Bogen. Was zaehlt, ist
      // dass der Zaehler mit der Kurvigkeit mitwaechst und nichts verschluckt.
      var vorher = 0;
      for (final n in [1, 3, 6, 10]) {
        final jetzt = KurvenZaehler.zaehle(serpentine(bogen: n));
        expect(
          jetzt,
          greaterThan(vorher),
          reason: '$n Boegen muessen mehr Kurven ergeben als davor',
        );
        expect(jetzt, greaterThanOrEqualTo(n));
        vorher = jetzt;
      }
    });

    test('zu wenige Punkte ergeben 0 statt eines Fehlers', () {
      expect(KurvenZaehler.zaehle(const []), 0);
      expect(
        KurvenZaehler.zaehle(const [
          [9.74, 47.42],
          [9.75, 47.43],
        ]),
        0,
      );
    });

    test('Ergebnis haengt nicht an der Roh-Punktdichte', () {
      // Genau dieselbe Strecke, einmal mit doppelt so vielen Stuetzpunkten:
      // der Zaehler resampelt auf 20 m und muss dasselbe Ergebnis liefern.
      final grob = serpentine(bogen: 5);
      final fein = <List<double>>[];
      for (var i = 0; i < grob.length; i++) {
        fein.add(grob[i]);
        if (i + 1 < grob.length) {
          fein.add([
            (grob[i][0] + grob[i + 1][0]) / 2,
            (grob[i][1] + grob[i + 1][1]) / 2,
          ]);
        }
      }
      expect(KurvenZaehler.zaehle(fein), KurvenZaehler.zaehle(grob));
    });

    // 2026-08-09 (vucko): Anzeige und Routen-Auswahl muessen dieselbe Zahl
    // benutzen. Vorher zeigte die App eine ehrliche Kurvenzahl an und waehlte
    // die Kurvenjagd-Route nach einer voellig anderen.
    test('Gamification und Kurvenzaehler liefern dieselbe Zahl', () {
      final strecke = serpentine(bogen: 7);
      expect(
        GamificationService.countCurves(strecke),
        KurvenZaehler.zaehle(strecke),
      );
    });
  });

  group('Kurvenjagd-Gate', () {
    final kurvig = serpentine(bogen: 40, geradeM: 120);
    final langweilig = gerade(laengeM: 30000);

    test('kurvige Strecke besteht das Gate, eine Gerade nicht', () {
      final kurvigKm = laengeKm(kurvig);
      final geradeKm = laengeKm(langweilig);

      expect(
        KurvenZaehler.proFuenfzigKm(kurvig, kurvigKm),
        greaterThanOrEqualTo(55),
        reason: 'Testfixture muss ueber der Schwelle liegen',
      );

      expect(
        RouteStyleConfig.kurvenjagd.validateStyleQuality(
          coordinates: langweilig,
          distanceKm: geradeKm,
          durationSeconds: geradeKm / 70 * 3600,
        ),
        isFalse,
        reason: 'Eine schnurgerade Strecke ist keine Kurvenjagd',
      );
    });

    test('die Schwelle steht in der Einheit des akkuraten Zaehlers', () {
      // Schutz gegen die alte Falle: 18 war die Schwelle des groben
      // Index-Zaehlers und auf echten Routen (250-350) nie bindend.
      expect(RouteStyleConfig.kurvenjagd.minCurvesPer50km, 55);
      expect(RouteStyleConfig.sport.minCurvesPer50km, isNull);
      expect(RouteStyleConfig.abendrunde.minCurvesPer50km, isNull);
    });
  });
}
