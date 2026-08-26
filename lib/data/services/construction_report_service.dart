import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/domain/models/construction_report.dart';
import 'package:cruise_connect/data/services/road_incident_service.dart';

/// 2026-05-28 (vucko Task #66): Baustellen-Service.
///
/// Quellen:
///   1. Supabase Tabelle `active_construction_reports` (View) — enthält
///      OSM-importierte + Crowd-gemeldete Baustellen.
///   2. Overpass-API — Fallback wenn Supabase noch wenig Daten hat; wird
///      direkt in den lokalen Cache geladen aber NICHT in Supabase
///      gepusht (vermeidet Spam).
///
/// Cache-Strategie: pro bbox 30 min TTL, Memory-only.
class ConstructionReportService {
  ConstructionReportService._();
  static final ConstructionReportService instance =
      ConstructionReportService._();

  static const _overpassUrl = 'https://overpass-api.de/api/interpreter';

  final Map<String, _BboxCacheEntry> _bboxCache = {};

  /// Fetcht alle aktiven Baustellen in einem bbox.
  ///
  /// Strategy:
  ///   1. Supabase-Query (~30-100ms)
  ///   2. Wenn weniger als 3 Treffer im bbox → Overpass-Fallback einmalig
  ///      laden und in Cache speichern (nicht in Supabase pushen).
  Future<List<ConstructionReport>> fetchInBbox({
    required double southLat,
    required double westLng,
    required double northLat,
    required double eastLng,
  }) async {
    final cacheKey = _cacheKey(southLat, westLng, northLat, eastLng);
    final cached = _bboxCache[cacheKey];
    if (cached != null && cached.isFresh) return cached.reports;

    final reports = <ConstructionReport>[];
    try {
      final supaResponse = await Supabase.instance.client
          .from('active_construction_reports')
          .select()
          .gte('lat', southLat)
          .lte('lat', northLat)
          .gte('lng', westLng)
          .lte('lng', eastLng)
          .limit(200);
      for (final row in supaResponse) {
        try {
          reports.add(ConstructionReport.fromJson(row));
        } catch (e) {
          debugPrint('[Construction] parse failed: $e');
        }
      }
    } catch (e) {
      debugPrint('[Construction] Supabase fetch failed: $e');
    }

    // Overpass-Fallback nur wenn Supabase wenig Daten hat — sonst macht's
    // einen API-Call pro Route-Generation der unnötig wäre.
    if (reports.length < 3) {
      try {
        final osmReports = await _fetchFromOverpass(
          southLat: southLat,
          westLng: westLng,
          northLat: northLat,
          eastLng: eastLng,
        );
        // Dedup gegen Supabase-Liste über (lat,lng) gerundet auf 4 Nachkommastellen.
        final knownKeys = reports
            .map((r) =>
                '${r.latitude.toStringAsFixed(4)}|${r.longitude.toStringAsFixed(4)}')
            .toSet();
        for (final osm in osmReports) {
          final key =
              '${osm.latitude.toStringAsFixed(4)}|${osm.longitude.toStringAsFixed(4)}';
          if (!knownKeys.add(key)) continue;
          reports.add(osm);
        }
      } catch (e) {
        debugPrint('[Construction] Overpass fallback failed: $e');
      }
    }

    _bboxCache[cacheKey] = _BboxCacheEntry(reports);
    return reports;
  }

  /// Filter: nur Baustellen, die nahe an der Route liegen (Vorgabe 80 m).
  ///
  /// 2026-08-26 (vucko, Nebenfund zu Aufgabe 1): Hier stand derselbe Fehler
  /// wie bei den gemeldeten Baustellen — die Route wurde auf FESTE 80
  /// Stuetzpunkte ausgeduennt und dann Punkt zu Punkt gemessen statt zur
  /// Linie. An echten Routen gemessen lagen bei 92 km 47 Prozent der Strecke
  /// weiter als 200 m vom naechsten Stuetzpunkt entfernt; bei einem Puffer von
  /// nur 80 m faellt entsprechend mehr durch. Die Baustellen aus den
  /// Kartendaten waren davon genauso betroffen wie die gemeldeten, nur hat es
  /// niemand bemerkt, weil sie seltener sind.
  ///
  /// Jetzt derselbe exakte Weg wie in RoadIncidentService: senkrechter Abstand
  /// zu den Streckenabschnitten.
  List<ConstructionReport> filterToRoute({
    required List<ConstructionReport> reports,
    required List<List<double>> routeCoordinates,
    double bufferMeters = 80,
  }) {
    if (reports.isEmpty || routeCoordinates.length < 2) return [];
    final filtered = <ConstructionReport>[];
    for (final report in reports) {
      if (RoadIncidentService.abstandZurRouteMeter(
            latitude: report.latitude,
            longitude: report.longitude,
            routeCoordinates: routeCoordinates,
          ) <=
          bufferMeters) {
        filtered.add(report);
      }
    }
    return filtered;
  }

  /// User stimmt für „noch da" oder „weg".
  /// Idempotent — bei doppeltem Vote wird der alte überschrieben.
  Future<bool> vote({
    required String reportId,
    required bool stillThere,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('[Construction] vote skipped — no user.');
      return false;
    }
    try {
      // Erst alten Vote löschen (idempotent), dann neuen einfügen.
      await Supabase.instance.client
          .from('construction_votes')
          .delete()
          .eq('report_id', reportId)
          .eq('user_id', user.id);
      await Supabase.instance.client.from('construction_votes').insert({
        'report_id': reportId,
        'user_id': user.id,
        'vote': stillThere ? 'confirm' : 'dismiss',
      });
      // Cache invalidieren damit der nächste Map-Refresh die neue Counter
      // sieht.
      _bboxCache.clear();
      return true;
    } catch (e) {
      debugPrint('[Construction] vote failed: $e');
      return false;
    }
  }

  /// User meldet eine neue Baustelle (Crowd-Source).
  /// Returnt den erstellten Report oder null bei Fehler.
  Future<ConstructionReport?> reportNew({
    required double latitude,
    required double longitude,
    String? roadName,
    String? roadRef,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    try {
      final response = await Supabase.instance.client
          .from('construction_reports')
          .insert({
            'lat': latitude,
            'lng': longitude,
            'road_name': roadName,
            'road_ref': roadRef,
            'source': 'crowd',
            'first_reported_by': user.id,
            // Der Reporter selbst gilt als erste Bestätigung (Trust-Boost).
            'confirm_count': 1,
            'last_confirmed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select()
          .single();
      _bboxCache.clear();
      // Bayesian-Score für den Display passt direkt zur (alpha=1, beta=0)-
      // Beta-Verteilung → 0.667. Kein extra-Roundtrip nötig.
      final json = Map<String, dynamic>.from(response);
      json['score'] = 0.667;
      return ConstructionReport.fromJson(json);
    } catch (e) {
      debugPrint('[Construction] reportNew failed: $e');
      return null;
    }
  }

  // ───────────────────── OSM Overpass-Fallback ────────────────────────
  Future<List<ConstructionReport>> _fetchFromOverpass({
    required double southLat,
    required double westLng,
    required double northLat,
    required double eastLng,
  }) async {
    // 2026-05-28 (vucko Task #74): erweiterte Query — User-Beschwerde
    // „Klaus/Götzis-Baustelle wird nicht angezeigt". Wir checken jetzt
    // alle plausiblen OSM-Tags für aktive/temporäre Bauarbeiten:
    //   - highway=construction (langfristig)
    //   - construction:highway=* (Klassifikation des Endzustands)
    //   - construction=yes (auf bestehender highway-Way)
    //   - roadworks=yes
    //   - temporary=yes (auf highway)
    //   - lanes:disused=* (Spursperrung)
    //   - hazard=construction (Punkt-Markierung)
    //   - barrier=construction
    // Plus: relation für längere Construction-Strecken die als Linie
    // strukturiert sind.
    final bbox = '$southLat,$westLng,$northLat,$eastLng';
    final query = '''
[out:json][timeout:25];
(
  way["highway"="construction"]($bbox);
  way["construction:highway"]($bbox);
  way["highway"]["construction"="yes"]($bbox);
  way["roadworks"="yes"]($bbox);
  way["highway"]["temporary"="yes"]($bbox);
  way["highway"]["lanes:disused"]($bbox);
  way["barrier"="construction"]($bbox);
  node["hazard"="construction"]($bbox);
  node["traffic_calming"="construction"]($bbox);
  relation["construction"]($bbox);
);
out center 150;
''';
    final response = await http
        .post(
          Uri.parse(_overpassUrl),
          headers: const {
            'User-Agent': 'CruiseConnect/1.0 (construction-poi)',
          },
          body: {'data': query},
        )
        .timeout(const Duration(seconds: 18));
    if (response.statusCode != 200) return [];
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final elements = data['elements'] as List? ?? [];
    final out = <ConstructionReport>[];
    for (final el in elements) {
      try {
        double? lat = (el['lat'] as num?)?.toDouble();
        double? lng = (el['lon'] as num?)?.toDouble();
        if (lat == null || lng == null) {
          final center = el['center'] as Map?;
          lat = (center?['lat'] as num?)?.toDouble();
          lng = (center?['lon'] as num?)?.toDouble();
        }
        if (lat == null || lng == null) continue;
        final tags = (el['tags'] as Map?)?.cast<String, dynamic>() ?? {};
        final id = (el['id'] as num).toInt();
        final type = (el['type'] as String?) ?? 'way';
        // OSM-Reports werden nicht in Supabase gepusht hier — würde
        // Spam-Inserts erzeugen wenn jeder User dieselben Routen probiert.
        // Stattdessen virtual: ID = "osm-{type}-{id}", source='osm'.
        out.add(ConstructionReport(
          id: 'osm-$type-$id',
          latitude: lat,
          longitude: lng,
          roadName: tags['name'] as String?,
          roadRef: tags['ref'] as String?,
          source: 'osm',
          osmId: id,
          osmType: type,
          confirmCount: 0,
          dismissCount: 0,
          firstReportedAt: DateTime.now().toUtc(),
          score: 0.5, // Neutral — User-Votes können nicht angewendet werden
                     // weil Report nicht in Supabase ist
        ));
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  // ───────────────────── Helpers ──────────────────────────────────────
  String _cacheKey(double s, double w, double n, double e) =>
      '${s.toStringAsFixed(2)}|${w.toStringAsFixed(2)}|'
      '${n.toStringAsFixed(2)}|${e.toStringAsFixed(2)}';

  // 2026-08-26: `_sampleRoute` und `_haversine` sind entfallen. Sie dienten
  // nur der alten, ungenauen Routenpruefung ueber 80 Stichproben; siehe die
  // Begruendung bei `filterToRoute`.
}

class _BboxCacheEntry {
  _BboxCacheEntry(this.reports) : at = DateTime.now();
  final List<ConstructionReport> reports;
  final DateTime at;
  bool get isFresh =>
      DateTime.now().difference(at) < const Duration(minutes: 30);
}
