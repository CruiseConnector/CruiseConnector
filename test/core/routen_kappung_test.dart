import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/core/kurven_zaehler.dart';
import 'package:cruise_connect/core/routen_kappung.dart';

/// 2026-08-28 (Fehler 7 und 8, Stalking-Schutz): Verhalten des gemeinsamen
/// Kappungs-Helfers. Anzeige (Skizze) und Fremdfahrt rufen dieselbe Funktion;
/// dieser Test haelt die Zusicherungen fest, auf die sich beide verlassen.
void main() {
  /// Gerade Linie auf Breite 47 Grad, Punktabstand ~100 m in Laengsrichtung.
  List<List<double>> gerade(int punkte) {
    const startLng = 9.70;
    const lat = 47.0;
    // ~100 m in Grad Laenge auf Breite 47.
    const schritt = 0.1 / 75.93;
    return [
      for (var i = 0; i < punkte; i++) [startLng + i * schritt, lat],
    ];
  }

  double laengeMeter(List<List<double>> p) => linienLaengeKm(p) * 1000.0;

  test('5 km Linie: 300 m je Ende fehlen, der Rest bleibt', () {
    final linie = gerade(51); // ~5 km
    final gesamt = laengeMeter(linie);
    final gekappt = kappeEndstuecke(linie, 300, 300);

    expect(gekappt.length, greaterThanOrEqualTo(2));
    expect(laengeMeter(gekappt), closeTo(gesamt - 600, 20));
    // Der neue Anfang liegt ~300 m vom echten Start entfernt.
    expect(
      KurvenZaehler.distanzMeter(linie.first, gekappt.first),
      closeTo(300, 10),
    );
    expect(
      KurvenZaehler.distanzMeter(linie.last, gekappt.last),
      closeTo(300, 10),
    );
  });

  test('unter dem Mindestrest kommt eine leere Liste (2 km Linie)', () {
    // ~2 km minus 600 m Kappung laesst weniger als [mindestRestMeter] uebrig.
    final linie = gerade(21);
    expect(kappeEndstuecke(linie, 300, 300), isEmpty);
  });

  test('sehr kurze Route: leer statt Ausnahme', () {
    expect(kappeEndstuecke(gerade(6), 300, 300), isEmpty);
    expect(kappeEndstuecke(const [], 300, 300), isEmpty);
    expect(
      kappeEndstuecke(const [
        [9.7, 47.0],
      ], 300, 300),
      isEmpty,
    );
  });

  test('Kappung 0/0 laesst eine lange Linie unveraendert', () {
    final linie = gerade(51);
    final ergebnis = kappeEndstuecke(linie, 0, 0);
    expect(ergebnis.length, linie.length);
    expect(ergebnis.first, linie.first);
    expect(ergebnis.last, linie.last);
  });
}
