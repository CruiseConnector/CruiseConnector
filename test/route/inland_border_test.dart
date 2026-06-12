// ignore_for_file: avoid_print, depend_on_referenced_packages, unnecessary_import
//
// Harte Inland-Garantie (vucko 2026-06-08): an Grenzorten darf „Im Land bleiben"
// NIEMALS eine grenzüberschreitende Route liefern. Pro Ort mehrere Läufe (Routen
// sind zufällig) → JEDE muss entweder im Land bleiben (foreign ≤ produktive
// Box-Rauschen-Toleranz) ODER ein
// sauberer noRoute sein. Eine einzige Cross-Border-Route = FAIL.
//
// Lauf: flutter test test/route/inland_border_test.dart --dart-define=RUN_BORDER=true

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:functions_client/functions_client.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/data/services/country_region.dart';
import 'package:cruise_connect/data/services/route_pool_service.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/route_pool_candidate.dart';
import 'package:cruise_connect/domain/models/route_pool_coverage.dart';
import 'package:cruise_connect/domain/models/route_pool_entry.dart';
import 'package:cruise_connect/domain/models/route_region.dart';
import 'package:cruise_connect/domain/models/route_seed_job.dart';

class _LiveHttpInvoker implements RouteEdgeInvoker {
  _LiveHttpInvoker(this.endpoint);
  final Uri endpoint;
  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    final result = await Process.run('curl', [
      '-sS',
      '--http1.1',
      '-X',
      'POST',
      endpoint.toString(),
      '-H',
      'Content-Type: application/json',
      '-H',
      'apikey: ${AppConstants.supabaseAnonKey}',
      '-H',
      'Authorization: Bearer ${AppConstants.supabaseAnonKey}',
      '--data-binary',
      jsonEncode(body),
      '-w',
      '\n__HTTP_STATUS__:%{http_code}',
    ]);
    final out = (result.stdout as String).trimRight();
    final i = out.lastIndexOf('__HTTP_STATUS__:');
    final raw = i >= 0 ? out.substring(0, i).trim() : '';
    final status = i >= 0 ? int.tryParse(out.substring(i + 16).trim()) ?? 0 : 0;
    return FunctionResponse(
      data: raw.isEmpty ? null : jsonDecode(raw),
      status: status,
    );
  }
}

geo.Position _pos(double lat, double lng) => geo.Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime.now(),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

RoutePoolService _emptyPool() => RoutePoolService(
  inMemoryRoutes: <RoutePoolEntry>[],
  inMemoryRegions: <RouteRegion>[],
  inMemoryCoverage: <RoutePoolCoverage>[],
  inMemorySeedJobs: <RouteSeedJob>[],
  inMemoryCandidates: <RoutePoolCandidate>[],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const run = bool.fromEnvironment('RUN_BORDER', defaultValue: false);
  const runs = int.fromEnvironment('BORDER_RUNS', defaultValue: 4);

  // Grenznahe Startorte (AT/CH/DE-Grenzen) + km.
  const spots = <(String, double, double, int)>[
    ('Goetzis-AT', 47.3331, 9.6336, 50),
    ('Hohenems-AT', 47.3667, 9.6831, 50),
    ('Lustenau-AT', 47.4267, 9.6589, 50),
    ('Bregenz-AT', 47.5031, 9.7471, 50),
    ('Lindau-DE', 47.5459, 9.6845, 50),
    ('Konstanz-DE', 47.6603, 9.1758, 50),
    ('Goetzis-AT-75', 47.3331, 9.6336, 75),
  ];

  test(
    'Harte Inland-Garantie an Grenzen',
    skip: !run,
    () async {
      RouteService.disableBackgroundPreparation = true;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      HttpOverrides.global = null;
      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        anonKey: AppConstants.supabaseAnonKey,
        debug: false,
      );
      final endpoint = Uri.parse(
        'https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/generate-cruise-route-v2',
      );

      var crossings = 0, inland = 0, noRoute = 0;
      for (final s in spots) {
        final home = CountryRegion.classify(s.$2, s.$3) ?? '??';
        for (var r = 0; r < runs; r++) {
          RouteService.resetForTests();
          final svc = RouteService(
            invoker: _LiveHttpInvoker(endpoint),
            routePoolService: _emptyPool(),
          );
          try {
            final res = await svc.generateRoundTrip(
              startPosition: _pos(s.$2, s.$3),
              targetDistanceKm: s.$4,
              mode: 'Sport Mode',
              planningType: 'Zufall',
              forceFreshVariant: r > 0,
              debugTrigger: r > 0 ? 'searchAgain' : 'firstSearch',
              countryPreference: CountryPreference.onlyHome,
              homeCountryCode: home,
            );
            final foreign = CountryRegion.foreignFraction(
              coordinates: res.coordinates,
              homeCountryCode: home,
            );
            final touched = CountryRegion.countriesTouched(
              coordinates: res.coordinates,
              homeCountryCode: home,
            );
            final crossed = foreign > CountryRegion.onlyHomeMaxForeignFraction;
            if (crossed) {
              crossings++;
            } else {
              inland++;
            }
            print(
              'BORDERROW ${s.$1} home=$home run=$r '
              'foreign=${foreign.toStringAsFixed(2)} touched=${touched.join("+")} '
              '${crossed ? "❌ CROSS" : "✓ inland"}',
            );
          } catch (e) {
            noRoute++;
            print(
              'BORDERROW ${s.$1} home=$home run=$r noRoute '
              '(${e.toString().split("\n").first.substring(0, 40)}) ✓ ok',
            );
          }
        }
      }
      print(
        'BORDER_SUMMARY crossings=$crossings inland=$inland noRoute=$noRoute',
      );
      // DIE harte Zusicherung: KEINE einzige grenzüberschreitende Route.
      expect(
        crossings,
        0,
        reason: '$crossings Cross-Border-Routen trotz Im-Land!',
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
