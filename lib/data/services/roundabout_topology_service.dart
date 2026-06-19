import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 2026-06-16 (vucko O9): Echte Kreisverkehr-Topologie aus OpenStreetMap
/// (Overpass) — Anzahl + Winkel ALLER Arme. So zeichnet das Navi-Symbol den
/// Kreisverkehr so, wie er WIRKLICH aussieht (3-/4-/5-/6-armig, asymmetrisch),
/// nicht generisch. Live an echten Vorarlberger Kreiseln (Köblern/Lustenau)
/// verifiziert.
///
/// Architektur (rate-limit-/offline-sicher):
/// - Pro Kreisel EINE kleine Query, Ergebnis im RAM gecacht (Geometrie ändert
///   sich praktisch nie). Wird beim ANFAHREN lazy geholt (nicht alle vorab).
/// - Kurzer Netz-Timeout + Endpoint-Failover; bei Fehler → null ohne Cache, damit
///   der nächste Navigations-Tick erneut versuchen kann. Bei erfolgreicher
///   Antwort ohne Ring wird null gecacht ("kein Kreisel hier").
class RoundaboutTopology {
  const RoundaboutTopology({
    required this.centerLat,
    required this.centerLng,
    required this.armBearings,
    required this.radiusMeters,
  });

  final double centerLat;
  final double centerLng;

  /// Kompass-Winkel (0..360°, im Uhrzeigersinn ab Nord) jedes Arms — die
  /// Richtung, in die die Straße vom Kreisel WEGführt. Bereits dedupliziert
  /// (Einbahn-Paare derselben Straße zu einem Arm gemerged).
  final List<double> armBearings;

  /// Radius des Kreisel-Rings (Meter, Median Zentrum→Ring-Knoten). Daraus leitet
  /// das Symbol die Insel-Größe ab (Mini vs. großer/Autobahn-Kreisel).
  final double radiusMeters;

  int get armCount => armBearings.length;

  /// Insel-Größe relativ fürs Symbol (1.0 = Standard). Mini-Kreisel < 1, große
  /// Kreisel > 1 — exakt die `islandScale`-Achse aus dem Figma-Design.
  double get islandScale {
    final r = radiusMeters;
    if (r <= 0) return 1.0;
    if (r < 11) return 0.5; // Mini-Kreisel
    if (r < 26) return 1.0; // Standard
    if (r < 42) return 1.25; // groß
    return 1.45; // sehr groß / Autobahnkreisel
  }
}

class RoundaboutTopologyService {
  RoundaboutTopologyService._();
  static final RoundaboutTopologyService instance =
      RoundaboutTopologyService._();

  static const List<String> _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  // Cache: gerundete Koordinate → Topologie (oder null = „kein Kreisel hier").
  // Temporäre Netzfehler werden bewusst NICHT gecacht.
  final Map<String, RoundaboutTopology?> _cache = {};
  // Läuft gerade eine Abfrage für diese Koordinate? (kein Doppel-Fetch)
  final Set<String> _inFlight = {};

  String _key(double lat, double lng) =>
      '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';

  /// Bereits gecachtes Ergebnis (synchron, ohne Netz) — für den Painter.
  RoundaboutTopology? cached(double lat, double lng) => _cache[_key(lat, lng)];

  bool isResolved(double lat, double lng) => _cache.containsKey(_key(lat, lng));

  /// Holt die Topologie (aus Cache oder Overpass). Liefert null, wenn kein
  /// Kreisel gefunden / Netz-Fehler. Nur erfolgreiche "kein Kreisel"-Antworten
  /// werden als null gecacht; temporäre Netzfehler bleiben retry-fähig.
  Future<RoundaboutTopology?> fetch(double lat, double lng) async {
    final key = _key(lat, lng);
    if (_cache.containsKey(key)) return _cache[key];
    if (_inFlight.contains(key)) return null;
    _inFlight.add(key);
    try {
      final result = await _query(lat, lng);
      _cache[key] = result; // auch null cachen (kein erneuter Versuch)
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[Roundabout] fetch failed: $e');
      return null;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<RoundaboutTopology?> _query(double lat, double lng) async {
    // Ring (junction=roundabout|circular) ODER OSM-Mini-Kreisverkehr
    // (node[highway=mini_roundabout]) im 45m-Umkreis + alle Arme, die seine
    // Knoten berühren. `out geom` liefert geordnete Geometrie + Knoten-IDs.
    final ql =
        '[out:json][timeout:20];'
        'way(around:45,$lat,$lng)["junction"~"roundabout|circular"]->.ring;'
        'node(around:45,$lat,$lng)["highway"="mini_roundabout"]->.mini;'
        'node(w.ring)->.rn;'
        'way(bn.rn)->.arms;'
        'way(bn.mini)->.miniarms;'
        '(.ring;.arms;.mini;.miniarms;);'
        'out geom;';
    var gotSuccessfulResponse = false;
    for (final endpoint in _endpoints) {
      try {
        final resp = await http
            .post(Uri.parse(endpoint), body: {'data': ql})
            .timeout(const Duration(seconds: 7));
        if (resp.statusCode != 200) continue;
        gotSuccessfulResponse = true;
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final elements =
            (data['elements'] as List?)?.cast<dynamic>() ?? const [];
        final parsed = _parse(elements);
        return parsed; // kann null sein (kein Ring) → als „kein Kreisel" cachen
      } catch (_) {
        // Timeout/Socket/Parse → nächster Endpoint, dann aufgeben.
      }
    }
    if (!gotSuccessfulResponse) {
      throw StateError('overpass_unavailable');
    }
    return null;
  }

  RoundaboutTopology? _parse(List<dynamic> elements) {
    Map<String, dynamic>? ring;
    for (final e in elements) {
      if (e is! Map<String, dynamic>) continue;
      final tags = e['tags'];
      final j = tags is Map ? tags['junction'] : null;
      if (j == 'roundabout' || j == 'circular') {
        ring = e;
        break;
      }
    }
    if (ring == null) return _parseMiniRoundabout(elements);

    final ringIds = (ring['nodes'] as List?)
        ?.cast<num>()
        .map((n) => n.toInt())
        .toList();
    final ringGeom = (ring['geometry'] as List?)?.cast<dynamic>();
    if (ringIds == null || ringGeom == null || ringIds.length < 3) return null;
    final ringNodeSet = ringIds.toSet();

    // Zentrum = Schwerpunkt der eindeutigen Ring-Knoten.
    final seen = <int>{};
    double sumLat = 0, sumLng = 0;
    var n = 0;
    for (var i = 0; i < ringIds.length && i < ringGeom.length; i++) {
      if (!seen.add(ringIds[i])) continue;
      final g = ringGeom[i];
      if (g is! Map) continue;
      sumLat += (g['lat'] as num).toDouble();
      sumLng += (g['lon'] as num).toDouble();
      n++;
    }
    if (n == 0) return null;
    final cLat = sumLat / n;
    final cLng = sumLng / n;

    // Ring-Radius = Median der Distanzen Zentrum→Ring-Knoten (robust gegen
    // ovale/asymmetrische Kreisel). Für die Insel-Größe im Symbol.
    final radii = <double>[];
    final seenR = <int>{};
    for (var i = 0; i < ringIds.length && i < ringGeom.length; i++) {
      if (!seenR.add(ringIds[i])) continue;
      final g = ringGeom[i];
      if (g is! Map) continue;
      radii.add(
        _metersBetween(
          cLat,
          cLng,
          (g['lat'] as num).toDouble(),
          (g['lon'] as num).toDouble(),
        ),
      );
    }
    radii.sort();
    final radiusMeters = radii.isEmpty ? 0.0 : radii[radii.length ~/ 2];

    // Pro Arm: Winkel vom Zentrum zu einem Punkt ~30m draußen (robust gegen
    // tangentiale Stummel am Knoten).
    final raw = <double>[];
    for (final e in elements) {
      if (identical(e, ring) || e is! Map<String, dynamic>) continue;
      final ids = (e['nodes'] as List?)
          ?.cast<num>()
          .map((x) => x.toInt())
          .toList();
      final geom = (e['geometry'] as List?)?.cast<dynamic>();
      if (ids == null || geom == null || ids.length < 2) continue;
      // Tag junction überspringen (das ist nochmal der Ring/ein Kreisel-Segment).
      final tags = e['tags'];
      final j = tags is Map ? tags['junction'] : null;
      if (j == 'roundabout' || j == 'circular') continue;

      var jIdx = -1;
      for (var i = 0; i < ids.length; i++) {
        if (ringNodeSet.contains(ids[i])) {
          jIdx = i;
          break;
        }
      }
      if (jIdx < 0) continue;
      final outward = jIdx == 0 ? 1 : -1;
      final jg = geom[jIdx];
      if (jg is! Map) continue;
      var tLat = (jg['lat'] as num).toDouble();
      var tLng = (jg['lon'] as num).toDouble();
      var acc = 0.0;
      for (var i = jIdx + outward; i >= 0 && i < geom.length; i += outward) {
        final g = geom[i];
        if (g is! Map) break;
        final la = (g['lat'] as num).toDouble();
        final lo = (g['lon'] as num).toDouble();
        acc += _metersBetween(tLat, tLng, la, lo);
        tLat = la;
        tLng = lo;
        if (acc >= 30) break;
      }
      raw.add(_bearing(cLat, cLng, tLat, tLng));
    }
    if (raw.isEmpty) return null;

    // Dedup: Arme innerhalb ~20° zusammenfassen (Einbahn-Paare derselben Straße).
    raw.sort();
    final arms = <double>[];
    for (final b in raw) {
      final dup = arms.any((a) {
        final d = (a - b).abs();
        return math.min(d, 360 - d) < 20;
      });
      if (!dup) arms.add(b);
    }
    return RoundaboutTopology(
      centerLat: cLat,
      centerLng: cLng,
      armBearings: arms,
      radiusMeters: radiusMeters,
    );
  }

  RoundaboutTopology? _parseMiniRoundabout(List<dynamic> elements) {
    Map<String, dynamic>? node;
    for (final e in elements) {
      if (e is! Map<String, dynamic>) continue;
      if (e['type'] != 'node') continue;
      final tags = e['tags'];
      final highway = tags is Map ? tags['highway'] : null;
      if (highway == 'mini_roundabout') {
        node = e;
        break;
      }
    }
    if (node == null) return null;
    final nodeId = (node['id'] as num?)?.toInt();
    final cLat = (node['lat'] as num?)?.toDouble();
    final cLng = (node['lon'] as num?)?.toDouble();
    if (nodeId == null || cLat == null || cLng == null) return null;

    final raw = <double>[];
    for (final e in elements) {
      if (e is! Map<String, dynamic> || e['type'] != 'way') continue;
      final ids = (e['nodes'] as List?)
          ?.cast<num>()
          .map((x) => x.toInt())
          .toList();
      final geom = (e['geometry'] as List?)?.cast<dynamic>();
      if (ids == null || geom == null || ids.length < 2) continue;
      final jIdx = ids.indexOf(nodeId);
      if (jIdx < 0) continue;
      final outward = jIdx == 0 ? 1 : -1;
      var tLat = cLat;
      var tLng = cLng;
      var acc = 0.0;
      for (var i = jIdx + outward; i >= 0 && i < geom.length; i += outward) {
        final g = geom[i];
        if (g is! Map) break;
        final la = (g['lat'] as num).toDouble();
        final lo = (g['lon'] as num).toDouble();
        acc += _metersBetween(tLat, tLng, la, lo);
        tLat = la;
        tLng = lo;
        if (acc >= 30) break;
      }
      if (tLat != cLat || tLng != cLng) {
        raw.add(_bearing(cLat, cLng, tLat, tLng));
      }
    }
    if (raw.isEmpty) return null;

    raw.sort();
    final arms = <double>[];
    for (final b in raw) {
      final dup = arms.any((a) {
        final d = (a - b).abs();
        return math.min(d, 360 - d) < 20;
      });
      if (!dup) arms.add(b);
    }
    return RoundaboutTopology(
      centerLat: cLat,
      centerLng: cLng,
      armBearings: arms,
      radiusMeters: 5.0,
    );
  }

  /// Kompass-Winkel (0..360°) des Arms, der am Routenpunkt [idx] in Richtung
  /// [step] vom Kreisverkehr wegführt — über ~25 m gemittelt (robust gegen
  /// kurze tangentiale Stummel). step −1 = zurück zur Herkunft (Einfahrt-Arm),
  /// +1 = die genommene Ausfahrt. coords sind [lng, lat] (Mapbox-Format).
  static double? armBearingAlong(List<List<double>> coords, int idx, int step) {
    if (coords.isEmpty || idx < 0 || idx >= coords.length) return null;
    final from = coords[idx];
    if (from.length < 2) return null;
    // 2026-06-19 (vucko Kreisverkehr 100% wie Apple): Früher die Sehne vom
    // Manöverpunkt (liegt AUF dem Ring) zu einem 25-m-Punkt — die bei großen
    // Kreiseln noch IM Ring landet und tangential statt radial zeigt → Pfeil-
    // winkel verbogen. Jetzt messen wir den Kurs des ARM-STRAẞENSTÜCKS:
    // vom Punkt ~14 m außerhalb (klar jenseits des Rings) zum Punkt ~42 m
    // außerhalb. Das ist die echte Heading des Ein-/Ausfahrtsarms. Fällt bei
    // sehr kurzen Routenstücken (Mini-Kreisel) sauber auf die alte Sehne zurück.
    var tLat = from[1], tLng = from[0];
    double? nearLat, nearLng, farLat, farLng;
    var acc = 0.0;
    for (var i = idx + step; i >= 0 && i < coords.length; i += step) {
      final c = coords[i];
      if (c.length < 2) break;
      acc += _metersBetween(tLat, tLng, c[1], c[0]);
      tLat = c[1];
      tLng = c[0];
      if (nearLat == null && acc >= 14) {
        nearLat = tLat;
        nearLng = tLng;
      }
      if (acc >= 42) {
        farLat = tLat;
        farLng = tLng;
        break;
      }
    }
    if (tLat == from[1] && tLng == from[0]) return null;
    if (nearLat != null &&
        nearLng != null &&
        farLat != null &&
        farLng != null &&
        (nearLat != farLat || nearLng != farLng)) {
      return _bearing(nearLat, nearLng, farLat, farLng);
    }
    // Zu kurz für 42 m (kleiner Kreisel / nächstes Manöver nah): wenigstens vom
    // 14-m-Punkt (außerhalb des Rings) zum letzten erreichten Punkt messen —
    // besser als die tangentiale Sehne vom Ringpunkt. Erst wenn auch der
    // 14-m-Punkt fehlt, die alte Sehne vom Manöverpunkt.
    if (nearLat != null &&
        nearLng != null &&
        (nearLat != tLat || nearLng != tLng)) {
      return _bearing(nearLat, nearLng, tLat, tLng);
    }
    return _bearing(from[1], from[0], tLat, tLng);
  }

  static double _bearing(double lat1, double lon1, double lat2, double lon2) {
    final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
    final dl = (lon2 - lon1) * math.pi / 180;
    final y = math.sin(dl) * math.cos(p2);
    final x =
        math.cos(p1) * math.sin(p2) -
        math.sin(p1) * math.cos(p2) * math.cos(dl);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  static double _metersBetween(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
    final dp = (lat2 - lat1) * math.pi / 180,
        dl = (lon2 - lon1) * math.pi / 180;
    final a =
        math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
