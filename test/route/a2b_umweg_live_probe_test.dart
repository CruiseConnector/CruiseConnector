// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _LiveHttpInvoker implements RouteEdgeInvoker {
  final Uri endpoint = Uri.parse(
    '${AppConstants.supabaseUrl}/functions/v1/${const String.fromEnvironment('PROBE_FN', defaultValue: 'generate-cruise-route-v2')}',
  );
  Map<String, dynamic>? lastBody;
  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    // 2026-08-18 (Defekt 5): Messläufe kennzeichnen sich selbst. Genau dieses
    // Harness hat am 16.08. um 03:05 in 16 Minuten 399 Ereignisse ohne
    // Nutzer-ID erzeugt und den Eindruck entstehen lassen, die Hälfte der
    // Nutzer sei unbekannt.
    body = {...body, 'origin': 'test'};
    lastBody = Map<String, dynamic>.from(body);
    final result = await Process.run('curl', [
      '-sS', '--http1.1', '-X', 'POST', endpoint.toString(),
      '-H', 'Content-Type: application/json',
      '-H', 'apikey: ${AppConstants.supabaseAnonKey}',
      '-H', 'Authorization: Bearer ${AppConstants.supabaseAnonKey}',
      '--data-binary', jsonEncode(body),
      '-w', '\n__HTTP_STATUS__:%{http_code}',
    ]);
    final stdout = (result.stdout as String).trimRight();
    final i = stdout.lastIndexOf('__HTTP_STATUS__:');
    final raw = i >= 0 ? stdout.substring(0, i).trim() : '';
    final status = int.tryParse(stdout.substring(i + 16).trim()) ?? 0;
    return FunctionResponse(data: raw.isEmpty ? null : jsonDecode(raw), status: status);
  }
}

geo.Position _p(double lat, double lng) => geo.Position(
  latitude: lat, longitude: lng, timestamp: DateTime.now(), accuracy: 5,
  altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
);

double _dist(List<double> a, List<double> b) =>
    geo.Geolocator.distanceBetween(a[1], a[0], b[1], b[0]);

/// Kennzahlen: Richtungswechsel > 30° je km (Zackigkeit), Anteil der Punkte,
/// die einem NICHT benachbarten Abschnitt naeher als 25 m sind (Hin-und-zurueck),
/// und der Anteil ueber 400 m Distanz sortierter Punkte.
Map<String, double> _kennzahlen(List<List<double>> c) {
  var km = 0.0;
  for (var i = 1; i < c.length; i++) {
    km += _dist(c[i - 1], c[i]);
  }
  km /= 1000;
  // Richtungswechsel auf ~100-m-Raster
  final grob = <List<double>>[c.first];
  var acc = 0.0;
  for (var i = 1; i < c.length; i++) {
    acc += _dist(c[i - 1], c[i]);
    if (acc >= 100) { grob.add(c[i]); acc = 0; }
  }
  var wechsel = 0;
  double bearing(List<double> a, List<double> b) =>
      geo.Geolocator.bearingBetween(a[1], a[0], b[1], b[0]);
  for (var i = 2; i < grob.length; i++) {
    var d = (bearing(grob[i - 1], grob[i]) - bearing(grob[i - 2], grob[i - 1])).abs() % 360;
    if (d > 180) d = 360 - d;
    if (d > 30) wechsel++;
  }
  // Ueberlappung: Punkt nah an einem Punkt, der > 60 Rasterpunkte entfernt ist
  var ueberlapp = 0;
  for (var i = 0; i < grob.length; i++) {
    for (var j = i + 60; j < grob.length; j++) {
      if (_dist(grob[i], grob[j]) < 40) { ueberlapp++; break; }
    }
  }
  return {
    'km': km,
    'wechselProKm': km > 0 ? wechsel / km : 0,
    'ueberlappAnteil': grob.isNotEmpty ? ueberlapp / grob.length : 0,
  };
}

/// 2026-08-16 (vucko Testfahrt T3): Live-Messharness fuer die A→B-Umwegstufen.
/// Opt-in: `flutter test --dart-define=LIVE_A2B=true test/route/a2b_umweg_live_probe_test.dart`
/// (optional `--dart-define=PROBE_FN=<edge-funktion>` gegen eine Probe-Instanz).
/// Misst je Paar/Stil/Stufe: km, Verhaeltnis zur Luftlinie, geliefert/downgraded,
/// Strassenklassen, Wenden, Zackigkeit, Hin-und-zurueck-Ueberlappung, Latenz.
///
/// Befund vor dem Fix (16.08., Produktion): 17 von 18 Umweg-Routen mit einer
/// Wende (Stachel: hin und auf demselben Weg zurueck), Ueberlappung bis 21 %.
/// Nach dem Fix (Via bei 38/50/62 %, 8/12/14 Kandidaten, pass_through, Wende-
/// Strafe 60, Ueberschuss-Gewicht): 9 von 36 mit Wende, keine Downgrades,
/// Stufen in 12/12 Dreiergruppen geordnet, Median 2,25x / 4,2x / 6,0x Luftlinie.
void main() {
  const live = bool.fromEnvironment('LIVE_A2B', defaultValue: false);
  test('A→B Umweg-Matrix live', skip: !live, () async {
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = null;
    await Supabase.initialize(url: AppConstants.supabaseUrl, anonKey: AppConstants.supabaseAnonKey, debug: false);
    RouteService.disableBackgroundPreparation = true;
    final inv = _LiveHttpInvoker();
    final service = RouteService(invoker: inv);
    final paare = <String, (geo.Position, geo.Position)>{
      'Lustenau→Hohenems': (_p(47.4285, 9.6600), _p(47.3667, 9.6831)),
      'Dornbirn→Bregenz': (_p(47.4125, 9.7414), _p(47.5031, 9.7471)),
      'Dornbirn→Bezau': (_p(47.4125, 9.7414), _p(47.3850, 9.9020)),
    };
    final out = <Map<String, dynamic>>[];
    for (final e in paare.entries) {
      final (a, b) = e.value;
      final direct = geo.Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude) / 1000;
      for (final mode in ['Kurvenjagd', 'Entdecker']) {
        for (final level in [1, 2, 3, 1, 2, 3]) {
          final t0 = DateTime.now();
          try {
            RouteService.resetForTests();
            final r = await service.generatePointToPoint(
              startPosition: a,
              destinationLat: b.latitude,
              destinationLng: b.longitude,
              mode: level > 0 ? mode : 'Standard',
              scenic: level > 0,
              routeVariant: level,
              forceFreshVariant: true,
            );
            final k = _kennzahlen(r.coordinates);
            final m = r.edgeMeta;
            final row = {
              'paar': e.key, 'mode': mode, 'level': level,
              'direktKm': direct, 'km': r.distanceKm, 'min': (r.durationSeconds ?? 0) / 60,
              'ratio': (r.distanceKm ?? 0) / direct,
              'req_target': inv.lastBody?['targetDistance'], 'req_factor': inv.lastBody?['detour_factor'],
              'delivered_level': m['delivered_detour_level'], 'downgraded': m['detour_downgraded'],
              'residential': m['residential_distance_fraction'], 'minor': m['minor_road_distance_fraction'],
              'major': m['major_road_distance_fraction'], 'uturns': m['u_turn_count'],
              'wechselProKm': k['wechselProKm'], 'ueberlapp': k['ueberlappAnteil'],
              'sek': DateTime.now().difference(t0).inMilliseconds / 1000,
              'coords': r.coordinates,
            };
            out.add(row);
            print('PROBE ${e.key} $mode L$level: ${r.distanceKm?.toStringAsFixed(1)} km '
                '(${(row['ratio'] as double).toStringAsFixed(2)}x direkt ${direct.toStringAsFixed(1)}), '
                'req target=${row['req_target']} factor=${row['req_factor']}, '
                'delivered=${row['delivered_level']} downgraded=${row['downgraded']}, '
                'resid=${row['residential']} minor=${row['minor']} major=${row['major']} '
                'uturn=${row['uturns']} wechsel/km=${(k['wechselProKm']!).toStringAsFixed(1)} '
                'ueberlapp=${(k['ueberlappAnteil']!).toStringAsFixed(2)} ${row['sek']}s');
          } catch (err) {
            print('PROBE ${e.key} $mode L$level: FEHLER $err');
            out.add({'paar': e.key, 'mode': mode, 'level': level, 'error': err.toString()});
          }
        }
      }
    }
    File('/private/tmp/claude-501/-Users-vucko-Development-CruiserConnect/8093fe19-b272-4c19-9cc1-6fc634ade357/scratchpad/a2b_probe_${const String.fromEnvironment('PROBE_FN', defaultValue: 'prod')}.json')
        .writeAsStringSync(jsonEncode(out));
  }, timeout: const Timeout(Duration(minutes: 30)));
}
