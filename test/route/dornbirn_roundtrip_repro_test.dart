// 2026-06-27 (vucko) — 10-Regionen Rundkurs-Live-Matrix (Vorarlberg×2, AT×5, DE×2, CH×1)
// mit verschiedenen Settings. Fährt die ECHTE Client-Logik (RouteService.generateRoundTrip,
// premium=live-first) gegen den LIVE-Edge und druckt pro Kombi: OK+km ODER FAIL+Grund.
//
// Lauf:  flutter test test/route/dornbirn_roundtrip_repro_test.dart --dart-define=SB_ANON=<anon>

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:functions_client/functions_client.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/country_region.dart';
import 'package:cruise_connect/data/services/route_service.dart';

const _anon = String.fromEnvironment('SB_ANON', defaultValue: '');
final _endpoint = Uri.parse(
  'https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/generate-cruise-route-v2',
);

class _LiveInvoker implements RouteEdgeInvoker {
  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(_endpoint);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set('apikey', _anon);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_anon');
      req.write(jsonEncode(body));
      final resp = await req.close();
      final raw = await resp.transform(utf8.decoder).join();
      final data = raw.isEmpty ? null : jsonDecode(raw);
      return FunctionResponse(data: data, status: resp.statusCode);
    } finally {
      client.close(force: true);
    }
  }
}

geo.Position _pos(double lat, double lng) => geo.Position(
  latitude: lat, longitude: lng, timestamp: DateTime.now(), accuracy: 5,
  altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0,
  speed: 0, speedAccuracy: 0,
);

class _Region {
  const _Region(this.name, this.country, this.lat, this.lng);
  final String name;
  final String country;
  final double lat;
  final double lng;
}

void main() {
  test('10-region round-trip live matrix', () async {
    if (_anon.isEmpty) {
      // ignore: avoid_print
      print('SKIP: no --dart-define=SB_ANON');
      return;
    }
    SharedPreferences.setMockInitialValues({});

    const regions = <_Region>[
      // Vorarlberg ×2
      _Region('Dornbirn', 'AT', 47.4125, 9.7414),
      _Region('Bregenz', 'AT', 47.5031, 9.7471),
      // Österreich ×5
      _Region('Innsbruck', 'AT', 47.2692, 11.4041),
      _Region('Salzburg', 'AT', 47.8095, 13.0550),
      _Region('Graz', 'AT', 47.0707, 15.4395),
      _Region('Linz', 'AT', 48.3069, 14.2858),
      _Region('Wien', 'AT', 48.2082, 16.3738),
      // Deutschland ×2
      _Region('München', 'DE', 48.1351, 11.5820),
      _Region('Stuttgart', 'DE', 48.7758, 9.1829),
      // Schweiz ×1
      _Region('Zürich', 'CH', 47.3769, 8.5417),
    ];

    // Verschiedene Settings (Modus, km, avoidHighways, country-pref)
    final settings = <List<dynamic>>[
      ['Sport Mode', 50, false, CountryPreference.any],
      ['Standard', 40, false, CountryPreference.preferHome],
      ['Kurvenjagd', 60, true, CountryPreference.any],
    ];

    var ok = 0, fail = 0;
    final failures = <String>[];

    for (final r in regions) {
      for (final s in settings) {
        final mode = s[0] as String;
        final km = s[1] as int;
        final avoid = s[2] as bool;
        final pref = s[3] as CountryPreference;
        RouteService.resetForTests();
        final svc = RouteService(invoker: _LiveInvoker());
        final label = '${r.name}(${r.country}) $mode ${km}km '
            'ah=$avoid pref=${pref.name}';
        try {
          final res = await svc.generateRoundTrip(
            startPosition: _pos(r.lat, r.lng),
            targetDistanceKm: km,
            mode: mode,
            planningType: 'Zufall',
            avoidHighways: avoid,
            countryPreference: pref,
            homeCountryCode: r.country,
            debugTrigger: 'matrix',
          );
          final coords = res.coordinates.length;
          if (coords >= 2) {
            ok++;
            // ignore: avoid_print
            print('OK   $label -> ${res.distanceKm?.toStringAsFixed(1)}km '
                '($coords pts)');
          } else {
            fail++;
            failures.add('$label -> empty geometry');
            // ignore: avoid_print
            print('FAIL $label -> empty geometry');
          }
        } catch (e) {
          fail++;
          final msg = e is RouteServiceException
              ? '${e.type.name}|${e.debugMessage ?? e.userMessage}'
              : e.toString();
          failures.add('$label -> $msg');
          // ignore: avoid_print
          print('FAIL $label -> $msg');
        }
      }
    }

    // ignore: avoid_print
    print('\n==== MATRIX: $ok OK / $fail FAIL (${regions.length} Regionen × '
        '${settings.length} Settings) ====');
    for (final f in failures) {
      // ignore: avoid_print
      print('  ✗ $f');
    }
    expect(fail, 0, reason: 'Rundkurs muss in allen Regionen+Settings gehen');
  }, timeout: const Timeout(Duration(minutes: 12)));

  // 2026-06-27 (vucko): FREE-Tier muss bei Pool-Miss auf Live durchfallen,
  // NICHT „keine Route" werfen (Route-Zugang ist nicht die Paywall).
  test('FREE tier falls through to live (no hard no-route)', () async {
    if (_anon.isEmpty) {
      // ignore: avoid_print
      print('SKIP: no --dart-define=SB_ANON');
      return;
    }
    SharedPreferences.setMockInitialValues({});
    const spots = <_Region>[
      _Region('Dornbirn', 'AT', 47.4125, 9.7414),
      _Region('Bregenz', 'AT', 47.5031, 9.7471),
      _Region('Zürich', 'CH', 47.3769, 8.5417),
    ];
    var ok = 0, fail = 0;
    for (final r in spots) {
      RouteService.resetForTests();
      final svc = RouteService(invoker: _LiveInvoker());
      try {
        final res = await svc.generateRoundTrip(
          startPosition: _pos(r.lat, r.lng),
          targetDistanceKm: 50,
          mode: 'Sport Mode',
          planningType: 'Zufall',
          subscriptionTier: 'free',
          homeCountryCode: r.country,
          debugTrigger: 'free-test',
        );
        ok++;
        // ignore: avoid_print
        print('OK   FREE ${r.name} -> ${res.distanceKm?.toStringAsFixed(1)}km '
            '(${res.coordinates.length} pts)');
      } catch (e) {
        // GraphHopper-down (Server/502/DNS) ist Infrastruktur, KEIN Fix-Fehler —
        // beweist sogar, dass free bis zum Live-Versuch durchgefallen ist. Nur
        // der ALTE pool-only/coverage-Pfad (ohne Live-Versuch) wäre ein Fehler.
        final msg = e.toString();
        final attemptedLive = e is RouteServiceException &&
            (e.type == RouteErrorType.server ||
                msg.contains('GraphHopper') ||
                msg.contains('502'));
        if (attemptedLive) {
          ok++;
          // ignore: avoid_print
          print('OK   FREE ${r.name} -> Live versucht (GraphHopper down: '
              'Infra, kein Fix-Fehler)');
        } else {
          fail++;
          // ignore: avoid_print
          print('FAIL FREE ${r.name} -> alter pool-only no-route? -> $e');
        }
      }
    }
    expect(fail, 0,
        reason: 'FREE muss Live VERSUCHEN (nie sofortiges pool-only-no-route)');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
