import 'dart:math' as math;

import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:geolocator/geolocator.dart' as geo;

/// 2026-08-15 (vucko Testfahrt, Video 18:28: Banner klebt 20 s an „In den
/// Kreisverkehr einfahren"): Geladene Routen (Favoriten, gepostete Strecken,
/// aufgezeichnete Tracks, „Fahrt fortsetzen") tragen KEINE Manöver — nur der
/// kurze Anfahrts-Leg hat welche. Danach hing das Banner am letzten
/// Anfahrts-Manöver fest, weil es kein nächstes gab.
///
/// Lösung: Für die geladene Geometrie holen wir uns bei GraphHopper eine
/// Route ENTLANG dieser Geometrie (Start → dichte Via-Punkte → Ende) und
/// übernehmen NUR die Manöver — die Original-Geometrie bleibt unangetastet
/// (P3: geladene Routen bleiben original). Dieses File enthält den puren,
/// testbaren Teil: Via-Wahl und das Übertragen der Manöver auf die
/// Original-Koordinaten.

/// Wählt Zwischenpunkte entlang [coords] (ohne Start/Ende): etwa alle
/// [zielAbstandM] Meter, höchstens [maxVias]. Bei langen Routen wächst der
/// Abstand automatisch, damit die Anfrage klein bleibt.
List<List<double>> waehleViaPunkte(
  List<List<double>> coords, {
  double zielAbstandM = 600,
  int maxVias = 60,
}) {
  final n = coords.length;
  if (n < 3) return const [];
  var gesamt = 0.0;
  for (var i = 1; i < n; i++) {
    gesamt += _dist(coords[i - 1], coords[i]);
  }
  if (gesamt <= zielAbstandM) return const [];
  final anzahl = math.min(maxVias, (gesamt / zielAbstandM).floor());
  if (anzahl <= 0) return const [];
  final abstand = gesamt / (anzahl + 1);
  final vias = <List<double>>[];
  var naechste = abstand;
  var lauf = 0.0;
  for (var i = 1; i < n - 1 && vias.length < anzahl; i++) {
    lauf += _dist(coords[i - 1], coords[i]);
    if (lauf >= naechste) {
      vias.add([coords[i][0], coords[i][1]]);
      naechste += abstand;
    }
  }
  return vias;
}

/// Überträgt [manoever] (Indizes in [abgeleitet]) auf [original].
///
/// Für jedes Manöver wird die Position auf der Original-Geometrie gesucht —
/// aber nur in einem Fenster um die ERWARTETE Streckenposition: Das letzte
/// übernommene Manöver dient als Anker, dazu kommt der Fahrweg auf der
/// abgeleiteten Route seit diesem Anker. So verrutscht nichts, auch wenn
/// die abgeleitete Route insgesamt kürzer/länger ist, und ein Hin-und-zurück
/// auf derselben Straße springt nicht auf den falschen Ast (bei Gleichstand
/// gewinnt die Stelle, die der erwarteten Position näher ist).
///
/// Ein Manöver wird nur übernommen, wenn
///  1. sein Punkt und je ein Kontrollpunkt [kontrollAbstandM] davor und
///     dahinter (interpoliert auf der abgeleiteten Route) höchstens
///     [maxAbstandM] von der Original-POLYLINIE entfernt liegen, und
///  2. die Kursänderung über ±[kontrollAbstandM] auf beiden Geometrien
///     zusammenpasst (Differenz ≤ [maxKursDifferenzDeg]).
/// Weicht die abgeleitete Route dort ab (Mini-Schleife an einem Via, Wende
/// in einer Einfahrt, Abkürzung), wäre die Anweisung auf der Original-
/// Geometrie falsch — sie fliegt.
///
/// Wenden: GraphHopper legt die Wende dorthin, wo SEIN Pfad kehrt — bei
/// einer Stichstraße oft einige Dutzend Meter vor dem echten Wendepunkt (der
/// Via lag nicht ganz am Ende). Darum wird für Wenden im Fenster der Punkt
/// gesucht, an dem die ORIGINAL-Geometrie kehrt (Kursänderung > 150°); nur
/// wenn es ihn gibt (≤ [wendeSucheM] entfernt), wird die Wende dorthin
/// gesetzt, sonst verworfen (Schein-Wende in einer Einfahrt).
///
/// Live-Befund 40-km-Runde (Fixture): 30 GH-Manöver, 26 sauber übernommen,
/// 4 Artefakte (Schleifchen an Vias, Schein-Wende) verworfen.
List<RouteManeuver> uebertrageManoeverAufGeometrie({
  required List<List<double>> original,
  required List<List<double>> abgeleitet,
  required List<RouteManeuver> manoever,
  List<List<double>> vias = const [],
  double maxAbstandM = 30,
  double fensterM = 150,
  double kontrollAbstandM = 40,
  double kurzeSpanneM = 20,
  double maxKursDifferenzDeg = 60,
  double wendeSucheM = 250,
}) {
  if (original.length < 2 || abgeleitet.length < 2 || manoever.isEmpty) {
    return const [];
  }
  final cumO = _kumuliert(original);
  final cumA = _kumuliert(abgeleitet);
  final gesamtO = cumO.last;
  final gesamtA = cumA.last;
  if (gesamtO <= 0 || gesamtA <= 0) return const [];
  final anker = _viaAnker(original, cumO, abgeleitet, cumA, vias);
  final artefakt = _wendeArtefakte(manoever, cumA, abgeleitet.length);

  final ergebnis = <RouteManeuver>[];
  var letzterIndex = -1;
  final genutzteWenden = <int>{};
  for (var mi = 0; mi < manoever.length; mi++) {
    if (artefakt[mi]) continue;
    final m = manoever[mi];
    final j = m.routeIndex.clamp(0, abgeleitet.length - 1);
    final distA = cumA[j];
    final erwartet = _erwarteteOriginalDistanz(anker, distA);
    final istWende = m.icon == Icons.u_turn_left || m.icon == Icons.u_turn_right;

    _Treffer? treffer;
    if (istWende) {
      treffer = _wendepunktImFenster(
        original,
        cumO,
        erwartet,
        wendeSucheM,
        kontrollAbstandM,
        m.longitude,
        m.latitude,
      );
      if (treffer == null || !genutzteWenden.add(treffer.index)) continue;
    } else {
      treffer = _naechsterImFenster(
        original,
        cumO,
        erwartet,
        fensterM,
        m.longitude,
        m.latitude,
      );
      if (treffer == null || treffer.abstand > maxAbstandM) continue;

      // 1. Kontrollpunkte davor/dahinter (interpoliert, exakt ±kontrollAbstand).
      var passt = true;
      for (final d in [distA - kontrollAbstandM, distA + kontrollAbstandM]) {
        if (d < 0 || d > gesamtA) continue; // Routenanfang/-ende
        final p = _punktBei(abgeleitet, cumA, d);
        final t = _naechsterImFenster(
          original,
          cumO,
          treffer.entlang + (d - distA),
          fensterM,
          p[0],
          p[1],
        );
        if (t == null || t.abstand > maxAbstandM) {
          passt = false;
          break;
        }
      }
      if (!passt) continue;

      // 2. Kursänderung muss auf beiden Geometrien zusammenpassen — grob
      //    (±kontrollAbstand) UND fein (±20 m). Die feine Spanne entlarvt
      //    Mini-Ausflüge in Einfahrten (links rein, wenden, links raus), die
      //    über 40 m netto wieder geradeaus aussehen.
      var kursPasst = true;
      for (final spanne in [kontrollAbstandM, kurzeSpanneM]) {
        final kursA = _kursAenderung(abgeleitet, cumA, distA, spanne);
        final kursO = _kursAenderung(original, cumO, treffer.entlang, spanne);
        if (kursA == null || kursO == null) continue;
        var diff = (kursA - kursO).abs();
        if (diff > 180) diff = 360 - diff;
        final grenze = spanne < kontrollAbstandM
            ? maxKursDifferenzDeg + 15
            : maxKursDifferenzDeg;
        if (diff > grenze) {
          kursPasst = false;
          break;
        }
      }
      if (!kursPasst) continue;
    }

    // Monoton halten — ein Manöver darf nicht hinter das vorige rutschen.
    final idx = math.max(treffer.index, letzterIndex + 1);
    if (idx >= original.length) continue;
    letzterIndex = idx;
    ergebnis.add(
      m.copyWith(
        routeIndex: idx,
        latitude: original[idx][1],
        longitude: original[idx][0],
      ),
    );
  }
  return ergebnis;
}

/// Via-Snap-Artefakte: Landet ein Via genau auf einem Knoten einer
/// Seitenstraße, liefert GraphHopper „links rein / wenden / links raus" als
/// drei Instruktionen an EINEM Punkt (0 m Geometrie) — auf der Original-
/// Geometrie gibt es dort nichts. Jede Gruppe direkt aufeinanderfolgender
/// Manöver innerhalb [naheM], die eine Wende enthält, wird komplett verworfen.
List<bool> _wendeArtefakte(
  List<RouteManeuver> manoever,
  List<double> cumA,
  int nA, {
  double naheM = 15,
}) {
  final flags = List<bool>.filled(manoever.length, false);
  var start = 0;
  while (start < manoever.length) {
    var ende = start;
    while (ende + 1 < manoever.length) {
      final a = cumA[manoever[ende].routeIndex.clamp(0, nA - 1)];
      final b = cumA[manoever[ende + 1].routeIndex.clamp(0, nA - 1)];
      if ((b - a).abs() > naheM) break;
      ende++;
    }
    if (ende > start) {
      final hatWende = manoever
          .sublist(start, ende + 1)
          .any((m) => m.icon == Icons.u_turn_left || m.icon == Icons.u_turn_right);
      if (hatWende) {
        for (var i = start; i <= ende; i++) {
          flags[i] = true;
        }
      }
    }
    start = ende + 1;
  }
  return flags;
}

/// Stützstellen abgeleitete-Distanz → Original-Distanz.
///
/// Die Vias sind Original-Stützpunkte, die wir selbst gewählt haben — ihre
/// Original-Streckenposition ist exakt bekannt. Auf der abgeleiteten Route
/// wird jeder Via vorwärts (monoton) als erster Punkt ≤ 40 m gefunden. So
/// wirkt eine Abweichung der abgeleiteten Route (Schleifchen, verkürzte
/// Stichstraße) nur bis zum nächsten Via und verschiebt nicht alles dahinter.
/// Ohne Vias bleibt nur die Proportion (Start↔Start, Ende↔Ende).
List<List<double>> _viaAnker(
  List<List<double>> original,
  List<double> cumO,
  List<List<double>> abgeleitet,
  List<double> cumA,
  List<List<double>> vias,
) {
  final anker = <List<double>>[
    [0.0, 0.0],
  ];
  var suchVon = 1;
  var origVon = 1;
  for (final v in vias) {
    if (v.length < 2) continue;
    // Original-Position: exakter Stützpunkt (vorwärts ab dem letzten Via).
    var oi = -1;
    for (var i = origVon; i < original.length; i++) {
      if (original[i][0] == v[0] && original[i][1] == v[1]) {
        oi = i;
        break;
      }
    }
    if (oi < 0) continue;
    // Abgeleitete Position: erster Punkt vorwärts, der ≤ 40 m am Via liegt;
    // dann noch bis zum lokal nächsten weiterlaufen.
    var ai = -1;
    var bestD = double.infinity;
    for (var i = suchVon; i < abgeleitet.length; i++) {
      final d = geo.Geolocator.distanceBetween(
        v[1],
        v[0],
        abgeleitet[i][1],
        abgeleitet[i][0],
      );
      if (d <= 40.0) {
        if (d < bestD) {
          bestD = d;
          ai = i;
        } else if (ai >= 0) {
          break; // wieder weiter weg → lokales Minimum gefunden
        }
      } else if (ai >= 0) {
        break;
      }
    }
    if (ai < 0) continue;
    if (cumA[ai] <= anker.last[0] || cumO[oi] <= anker.last[1]) continue;
    anker.add([cumA[ai], cumO[oi]]);
    suchVon = ai + 1;
    origVon = oi + 1;
  }
  anker.add([cumA.last, cumO.last]);
  return anker;
}

/// Stückweise lineare Interpolation über die Anker.
double _erwarteteOriginalDistanz(List<List<double>> anker, double distA) {
  if (distA <= anker.first[0]) return anker.first[1];
  for (var k = 1; k < anker.length; k++) {
    final a = anker[k - 1];
    final b = anker[k];
    if (distA <= b[0]) {
      final span = b[0] - a[0];
      final t = span > 0 ? (distA - a[0]) / span : 0.0;
      return a[1] + t * (b[1] - a[1]);
    }
  }
  return anker.last[1];
}

/// Sucht im Fenster [erwartet ± sucheM] den Original-Stützpunkt, an dem die
/// Geometrie kehrt (Kursänderung über ±spanne > 150°) und der der GH-Wende
/// am nächsten liegt.
_Treffer? _wendepunktImFenster(
  List<List<double>> coords,
  List<double> cum,
  double erwartet,
  double sucheM,
  double spanne,
  double lng,
  double lat,
) {
  final von = _indexBeiDistanz(cum, erwartet - sucheM);
  final bis = math.min(_indexBeiDistanz(cum, erwartet + sucheM), coords.length - 1);
  _Treffer? bester;
  for (var i = von; i <= bis; i++) {
    final k = _kursAenderung(coords, cum, cum[i], spanne);
    if (k == null || k.abs() < 150) continue;
    final d = geo.Geolocator.distanceBetween(lat, lng, coords[i][1], coords[i][0]);
    if (d > sucheM) continue;
    if (bester == null || d < bester.abstand) {
      bester = _Treffer(i, d, cum[i]);
    }
  }
  return bester;
}

class _Treffer {
  const _Treffer(this.index, this.abstand, this.entlang);

  /// Original-Index (näherer Endpunkt des besten Segments).
  final int index;

  /// Abstand Punkt → Polylinie in Metern.
  final double abstand;

  /// Streckenposition des Lotfußpunkts auf der Original-Route in Metern.
  final double entlang;
}

/// Kleinster Abstand des Punkts (lng, lat) zu den Segmenten von [coords], die
/// im Streckenfenster [zielDist ± fensterM] liegen.
_Treffer? _naechsterImFenster(
  List<List<double>> coords,
  List<double> cum,
  double zielDist,
  double fensterM,
  double lng,
  double lat,
) {
  final von = _indexBeiDistanz(cum, zielDist - fensterM);
  final bis = math.min(_indexBeiDistanz(cum, zielDist + fensterM), coords.length - 1);
  if (bis <= von) {
    // Fenster ohne Segment (z. B. am Routenende): Punktabstand.
    final i = von.clamp(0, coords.length - 1);
    return _Treffer(
      i,
      geo.Geolocator.distanceBetween(lat, lng, coords[i][1], coords[i][0]),
      cum[i],
    );
  }
  final cosLat = math.cos(lat * math.pi / 180);
  double px(List<double> c) => (c[0] - lng) * cosLat * 111320.0;
  double py(List<double> c) => (c[1] - lat) * 110540.0;
  var bester = double.infinity;
  var besterScore = double.infinity;
  var besterIdx = von;
  var besterEntlang = cum[von];
  for (var i = von; i < bis; i++) {
    final ax = px(coords[i]), ay = py(coords[i]);
    final bx = px(coords[i + 1]), by = py(coords[i + 1]);
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = 0.0;
    if (len2 > 0) t = ((-ax) * dx + (-ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final fx = ax + t * dx, fy = ay + t * dy;
    final d = math.sqrt(fx * fx + fy * fy);
    final entlang = cum[i] + t * (cum[i + 1] - cum[i]);
    // Gleich nahe Stellen (Hin- und Rückweg derselben Straße): die der
    // erwarteten Streckenposition nähere gewinnt.
    final score = d + 0.05 * (entlang - zielDist).abs();
    if (score < besterScore) {
      besterScore = score;
      bester = d;
      besterIdx = t < 0.5 ? i : i + 1;
      besterEntlang = entlang;
    }
  }
  return _Treffer(besterIdx, bester, besterEntlang);
}

/// Kursänderung in Grad (rechts positiv) über die Strecke [dist ± spanne];
/// null, wenn die Spanne über Anfang/Ende hinausragt.
double? _kursAenderung(
  List<List<double>> coords,
  List<double> cum,
  double dist,
  double spanne,
) {
  if (dist - spanne < 0 || dist + spanne > cum.last) return null;
  final a = _punktBei(coords, cum, dist - spanne);
  final b = _punktBei(coords, cum, dist);
  final c = _punktBei(coords, cum, dist + spanne);
  final k1 = geo.Geolocator.bearingBetween(a[1], a[0], b[1], b[0]);
  final k2 = geo.Geolocator.bearingBetween(b[1], b[0], c[1], c[0]);
  var delta = (k2 - k1) % 360.0;
  if (delta > 180.0) delta -= 360.0;
  if (delta < -180.0) delta += 360.0;
  return delta;
}

/// Interpolierter Punkt [lng, lat] bei Streckenposition [dist].
List<double> _punktBei(List<List<double>> coords, List<double> cum, double dist) {
  final n = coords.length;
  if (dist <= 0) return [coords.first[0], coords.first[1]];
  if (dist >= cum.last) return [coords[n - 1][0], coords[n - 1][1]];
  final i = _indexBeiDistanz(cum, dist); // erster Index mit cum >= dist, >= 1
  final i0 = math.max(0, i - 1);
  final seg = cum[i] - cum[i0];
  final t = seg > 0 ? ((dist - cum[i0]) / seg).clamp(0.0, 1.0) : 0.0;
  return [
    coords[i0][0] + t * (coords[i][0] - coords[i0][0]),
    coords[i0][1] + t * (coords[i][1] - coords[i0][1]),
  ];
}

/// Erster Index, dessen kumulierte Distanz >= [dist] ist (geklemmt).
int _indexBeiDistanz(List<double> cum, double dist) {
  if (dist <= 0) return 0;
  final n = cum.length;
  if (dist >= cum.last) return n - 1;
  var lo = 0;
  var hi = n - 1;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (cum[mid] < dist) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

List<double> _kumuliert(List<List<double>> coords) {
  final cum = List<double>.filled(coords.length, 0.0);
  for (var i = 1; i < coords.length; i++) {
    cum[i] = cum[i - 1] + _dist(coords[i - 1], coords[i]);
  }
  return cum;
}

double _dist(List<double> a, List<double> b) {
  if (a.length < 2 || b.length < 2) return 0.0;
  return geo.Geolocator.distanceBetween(a[1], a[0], b[1], b[0]);
}
