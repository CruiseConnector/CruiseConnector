import 'dart:math' as math;

/// Eine einzige, akkurate Kurvenzaehlung fuer die ganze App.
///
/// 2026-06-25 (vucko): Der Zaehler wurde neu gebaut, weil der alte „jeden 20.
/// Punkt" im INDEX-Raum nahm. GraphHopper liefert aber stark schwankende
/// Punktdichte (viele Punkte in Kurven, wenige auf Geraden) — 20 Punkte waren
/// mal 50 m, mal 2 km. Kurven wurden uebersprungen oder doppelt gezaehlt, und
/// die Zahl hing an der Geometrie-Aufloesung statt an der echten Strasse.
///
/// 2026-08-09 (vucko „Kurvenjagd mit akkurater Kurvenzaehlung"): Hierher
/// verschoben. Vorher lag der gute Zaehler in der Gamification (also dort, wo
/// dem Nutzer die Zahl ANGEZEIGT wird), waehrend die Routen-AUSWAHL fuer
/// Kurvenjagd noch mit einem eigenen, groben Index-Zaehler entschied. Ergebnis:
/// Die App zeigte eine ehrliche Kurvenzahl an, waehlte die Route aber nach einer
/// anderen. Jetzt zaehlen Anzeige und Auswahl dasselbe.
///
/// Verfahren: (1) auf festen ~20-m-Stuetzpunkt-Abstand resampeln → unabhaengig
/// von der Roh-Punktdichte; (2) Kurven ueber kumulierte, vorzeichenbehaftete
/// Richtungsaenderung GRUPPIEREN — ein zusammenhaengender Bogen ist EINE Kurve,
/// ein Richtungswechsel (S-Kurve) oder eine laengere Gerade trennt zwei Kurven.
///
/// Koordinaten sind ueberall [longitude, latitude] (Mapbox-/GeoJSON-Format).
class KurvenZaehler {
  KurvenZaehler._();

  /// Gesamt-Drehung eines Bogens, ab der er als Kurve zaehlt.
  static const double _eintrittGrad = 40.0;

  /// So viel Geradeaus am Stueck beendet einen Bogen.
  static const double _geradeAbbruchMeter = 60.0;

  /// Stuetzpunkt-Abstand nach dem Resampling.
  static const double _stuetzpunktMeter = 20.0;

  static int zaehle(List<List<double>> coords) {
    if (coords.length < 3) return 0;
    final pts = resampleNachDistanz(coords, _stuetzpunktMeter);
    if (pts.length < 3) return 0;

    var kurven = 0;
    var bogenDrehung = 0.0; // kumulierte Drehung des aktuellen Bogens
    var bogenRichtung = 0; // -1 links / +1 rechts
    var gezaehlt = false;
    var geradeMeter = 0.0;

    for (var i = 1; i < pts.length - 1; i++) {
      final d = signierteDrehung(pts[i - 1], pts[i], pts[i + 1]);
      if (d.abs() < 2.0) {
        geradeMeter += _stuetzpunktMeter;
        if (geradeMeter >= _geradeAbbruchMeter) {
          bogenDrehung = 0;
          bogenRichtung = 0;
          gezaehlt = false;
        }
        continue;
      }
      geradeMeter = 0;
      final s = d > 0 ? 1 : -1;
      if (bogenRichtung != 0 && s != bogenRichtung) {
        // Gegenrichtung → neuer Bogen (S-Kurve = zwei Kurven)
        bogenDrehung = 0;
        gezaehlt = false;
      }
      bogenRichtung = s;
      bogenDrehung += d;
      if (!gezaehlt && bogenDrehung.abs() >= _eintrittGrad) {
        kurven++;
        gezaehlt = true;
      }
    }
    return kurven;
  }

  /// Kurven pro 50 km — die Groesse, in der die Fahrstile verglichen werden.
  static double proFuenfzigKm(List<List<double>> coords, double distanzKm) {
    if (distanzKm <= 0) return 0.0;
    return zaehle(coords) / distanzKm * 50.0;
  }

  /// Resampelt eine [lng,lat]-Polylinie auf festen Stuetzpunkt-Abstand (Meter),
  /// per linearer Interpolation. Macht alle nachgelagerten Geometrie-Masse
  /// unabhaengig von der Roh-Punktdichte.
  static List<List<double>> resampleNachDistanz(
    List<List<double>> coords,
    double abstandMeter,
  ) {
    if (coords.length < 2) return List.of(coords);
    final out = <List<double>>[coords.first];
    var acc = 0.0;
    for (var i = 1; i < coords.length; i++) {
      final p0 = coords[i - 1];
      final p1 = coords[i];
      if (p0.length < 2 || p1.length < 2) continue;
      final segLen = distanzMeter(p0, p1);
      if (segLen <= 0) continue;
      var start = 0.0;
      while (acc + (segLen - start) >= abstandMeter) {
        final need = abstandMeter - acc;
        final t = (start + need) / segLen;
        out.add([p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t]);
        start += need;
        acc = 0;
      }
      acc += segLen - start;
    }
    final last = coords.last;
    if (out.length < 2 || out.last[0] != last[0] || out.last[1] != last[1]) {
      out.add(last);
    }
    return out;
  }

  /// Vorzeichenbehaftete Richtungsaenderung bei b (Grad, +rechts/-links),
  /// equirektangular korrigiert (Laengengrade x cos(lat)).
  static double signierteDrehung(
    List<double> a,
    List<double> b,
    List<double> c,
  ) {
    var d = _peilungGrad(b, c) - _peilungGrad(a, b);
    while (d > 180) {
      d -= 360;
    }
    while (d < -180) {
      d += 360;
    }
    return d;
  }

  static double _peilungGrad(List<double> a, List<double> b) {
    final latRad = (a[1] + b[1]) * 0.5 * math.pi / 180.0;
    final dx = (b[0] - a[0]) * math.cos(latRad);
    final dy = b[1] - a[1];
    return math.atan2(dx, dy) * 180.0 / math.pi;
  }

  static double distanzMeter(List<double> a, List<double> b) {
    const erde = 6371000.0;
    final latRad = (a[1] + b[1]) * 0.5 * math.pi / 180.0;
    final dx = (b[0] - a[0]) * math.pi / 180.0 * math.cos(latRad) * erde;
    final dy = (b[1] - a[1]) * math.pi / 180.0 * erde;
    return math.sqrt(dx * dx + dy * dy);
  }
}
