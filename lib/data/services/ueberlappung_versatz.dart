/// Versetzt Streckenteile, die eine schon befahrene Stelle ein zweites Mal
/// benutzen, seitlich — damit Hin- und Rueckweg als zwei Linien sichtbar sind.
///
/// 2026-09-01 (Vucko: „auch muessen wir schauen wie wir das loesen wenn sich
/// der weg ueberschneidet und der hinweg sich mit dem rueckweg ueberschneidet
/// weil so sieht es wie in der bildschirmaufnahme auch sehr verbuggt aus"):
///
/// Auf seiner Aufnahme fuhr die Route eine Strasse hinauf, machte oben eine
/// Haarnadel und kam auf DERSELBEN Strasse zurueck. Beide Spuren liegen
/// geometrisch uebereinander, also zeichnet die Karte EINE Linie, wo zwei
/// sind. Fuer den Fahrer sieht es aus, als ende die Strecke oben einfach.
///
/// WARUM NUR DIE HINTERGRUNDLINIE VERSETZT WIRD. Die App zeichnet zwei
/// Linien uebereinander: eine schwache ueber die GANZE Route und darauf die
/// kraeftige aktive Linie, auf der der Standortpunkt sitzt. Wuerde die aktive
/// Linie versetzt, saesse der Punkt sichtbar neben ihr — bei Navigationszoom
/// waeren schon vier Meter rund acht Bildpunkte. Der Versatz gehoert deshalb
/// ausschliesslich in die Hintergrundlinie: sie erklaert den Verlauf, die
/// aktive Linie bleibt zentimetergenau dort, wo die Strasse ist.
library;

import 'dart:math' as math;

/// Wie nah zwei Punkte sein muessen, damit sie als dieselbe Stelle gelten.
///
/// Zwoelf Meter decken die Fahrbahnbreite und die Ungenauigkeit der
/// Routengeometrie ab, ohne benachbarte Strassen zusammenzuziehen.
const double ueberlappNaeheMeter = 12.0;

/// Wie weit die zweite Spur zur Seite rueckt.
///
/// Sechs Meter sind bei Navigationszoom deutlich sichtbar und bleiben bei
/// weitem Zoom unauffaellig. Mehr wuerde die Linie sichtbar von der Strasse
/// loesen.
const double ueberlappVersatzMeter = 6.0;

/// Wie viele Punkte mindestens zwischen zwei Vorbeifahrten liegen muessen.
///
/// Ohne diesen Abstand wuerde schon eine enge Kurve als Ueberlappung gelten:
/// dort liegen aufeinanderfolgende Punkte naturgemaess nah beieinander.
const int ueberlappMindestAbstandPunkte = 12;

/// Wie viele Punkte AM STUECK ein zweites Mal befahren sein muessen.
///
/// 2026-09-01: Ohne diese Regel wurde ein Rundkurs versetzt. Bei ihm trifft
/// der letzte Punkt auf den ersten — das ist der Schluss der Runde, keine
/// zweite Vorbeifahrt. Ein einzelner Treffer reicht deshalb nicht; erst eine
/// zusammenhaengende Strecke ist ein Stich, den man sehen soll.
const int ueberlappMindestLaufPunkte = 4;

const double _meterProGradBreite = 111320.0;

/// Liefert die Punkte mit seitlichem Versatz an den Stellen, die ein zweites
/// Mal befahren werden. Koordinaten sind [longitude, latitude].
///
/// Die ERSTE Vorbeifahrt bleibt unveraendert; nur die spaeteren ruecken zur
/// Seite. So bleibt die Hinweg-Spur dort, wo die Strasse ist, und der
/// Rueckweg legt sich sichtbar daneben.
List<List<double>> mitUeberlappungsVersatz(
  List<List<double>> punkte, {
  double naeheMeter = ueberlappNaeheMeter,
  double versatzMeter = ueberlappVersatzMeter,
  int mindestAbstand = ueberlappMindestAbstandPunkte,
}) {
  if (punkte.length < 3) return punkte;

  // Ein grobes Raster macht die Suche linear statt quadratisch. Ohne das
  // waere eine Route mit 11.000 Punkten nicht mehr zeichenbar.
  final zellGrad = naeheMeter * 2 / _meterProGradBreite;
  final raster = <int, List<int>>{};
  int schluessel(double lng, double lat) {
    final x = (lng / zellGrad).floor();
    final y = (lat / zellGrad).floor();
    return x * 1000003 + y;
  }

  // ERSTER DURCHGANG: markieren, welche Punkte eine schon befahrene Stelle
  // ein zweites Mal benutzen.
  final wiederholt = List<bool>.filled(punkte.length, false);
  for (var i = 0; i < punkte.length; i++) {
    final p = punkte[i];
    if (p.length < 2) continue;
    final lng = p[0], lat = p[1];
    final zx = (lng / zellGrad).floor();
    final zy = (lat / zellGrad).floor();
    var gefunden = false;
    for (var ox = -1; ox <= 1 && !gefunden; ox++) {
      for (var oy = -1; oy <= 1 && !gefunden; oy++) {
        final eimer = raster[(zx + ox) * 1000003 + (zy + oy)];
        if (eimer == null) continue;
        for (final j in eimer) {
          if (i - j < mindestAbstand) continue;
          if (_meter(punkte[j], p) <= naeheMeter) {
            gefunden = true;
            break;
          }
        }
      }
    }
    wiederholt[i] = gefunden;
    raster.putIfAbsent(schluessel(lng, lat), () => <int>[]).add(i);
  }

  // ZWEITER DURCHGANG: nur zusammenhaengende Laeufe zaehlen. Ein einzelner
  // Treffer ist der Schluss einer Runde, kein Stich.
  final versetzen = List<bool>.filled(punkte.length, false);
  var laufStart = -1;
  for (var i = 0; i <= punkte.length; i++) {
    final drin = i < punkte.length && wiederholt[i];
    if (drin && laufStart < 0) {
      laufStart = i;
    } else if (!drin && laufStart >= 0) {
      if (i - laufStart >= ueberlappMindestLaufPunkte) {
        for (var k = laufStart; k < i; k++) {
          versetzen[k] = true;
        }
      }
      laufStart = -1;
    }
  }

  if (!versetzen.contains(true)) return punkte;

  // DRITTER DURCHGANG: senkrecht zur oertlichen Fahrtrichtung ausweichen.
  final ergebnis = <List<double>>[];
  for (var i = 0; i < punkte.length; i++) {
    final p = punkte[i];
    if (p.length < 2 || !versetzen[i]) {
      ergebnis.add(p);
      continue;
    }
    final vor = punkte[math.max(0, i - 1)];
    final nach = punkte[math.min(punkte.length - 1, i + 1)];
    ergebnis.add(
      _seitlich(
        lng: p[0],
        lat: p[1],
        vonLng: vor[0],
        vonLat: vor[1],
        bisLng: nach[0],
        bisLat: nach[1],
        meter: versatzMeter,
      ),
    );
  }
  return ergebnis;
}

double _meter(List<double> a, List<double> b) {
  if (a.length < 2 || b.length < 2) return double.infinity;
  final mittlereBreite = (a[1] + b[1]) / 2 * math.pi / 180.0;
  final dx = (b[0] - a[0]) * _meterProGradBreite * math.cos(mittlereBreite);
  final dy = (b[1] - a[1]) * _meterProGradBreite;
  return math.sqrt(dx * dx + dy * dy);
}

List<double> _seitlich({
  required double lng,
  required double lat,
  required double vonLng,
  required double vonLat,
  required double bisLng,
  required double bisLat,
  required double meter,
}) {
  final breitenFaktor = math.cos(lat * math.pi / 180.0).abs().clamp(0.05, 1.0);
  // Richtung des Wegstuecks in Metern.
  final dx = (bisLng - vonLng) * _meterProGradBreite * breitenFaktor;
  final dy = (bisLat - vonLat) * _meterProGradBreite;
  final laenge = math.sqrt(dx * dx + dy * dy);
  if (laenge < 0.001) return [lng, lat];
  // Senkrechte nach rechts bezogen auf die Fahrtrichtung.
  final nx = dy / laenge;
  final ny = -dx / laenge;
  return [
    lng + (nx * meter) / (_meterProGradBreite * breitenFaktor),
    lat + (ny * meter) / _meterProGradBreite,
  ];
}
