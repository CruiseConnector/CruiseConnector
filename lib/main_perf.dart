// PERF-HARNESS-ENTRYPOINT (2026-06-10, Branch fix/fahr-performance).
//
// Startet die App direkt in der CruiseModePage mit einer deterministischen
// Routen-Fixture (echte 108-km-Pool-Route bei Friedrichshafen) und misst die
// Frame-Zeiten (UI-Build + Raster) über SchedulerBinding.addTimingsCallback.
// Alle 10 s wird eine aggregierte Statistik geloggt:
//   [PERF] frames=N | build avg/p90/p99 | raster avg/p90/p99 | jank>16.7ms | >33ms
//
// Benutzung (physisches Gerät, Profile-Build):
//   flutter run --profile -t lib/main_perf.dart \
//     --dart-define=PERF_AUTOPILOT=true \
//     --dart-define=SIM_ENABLED=true \
//     --dart-define=SIM_KMH=70
//
// PERF_AUTOPILOT lässt die CruiseModePage die Fixture-Route automatisch
// bestätigen und die Simulations-Fahrt starten (kein Tippen am Gerät nötig).
// Dieser Entrypoint wird vom normalen App-Build (lib/main.dart) nicht
// referenziert und verändert ihn nicht.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/route_bookmark_provider.dart';
import 'package:cruise_connect/application/providers/saved_routes_provider.dart';
import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/data/services/poi_settings_service.dart';
import 'package:cruise_connect/data/services/voice_settings_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/perf/perf_route_fixture.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';

import 'dart:convert' show json;

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        anonKey: AppConstants.supabaseAnonKey,
      );
      unawaited(VoiceSettingsService.instance.load());
      unawaited(PoiSettingsService.instance.load());

      _PerfFrameStats.instance.start();

      runApp(const _PerfApp());
    },
    (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}

class _PerfApp extends StatelessWidget {
  const _PerfApp();

  @override
  Widget build(BuildContext context) {
    final geometry = Map<String, dynamic>.from(
      json.decode(kPerfRouteGeometryJson) as Map,
    );
    final route = SavedRoute(
      id: 'perf-fixture',
      createdAt: DateTime.now(),
      style: 'Sport Mode',
      distanceKm: 108.48,
      durationSeconds: 6120,
      routeType: 'ROUND_TRIP',
      geometry: geometry,
    );
    // Dieselben Provider, die die Page in Produktion über MyApp sieht —
    // sonst wirft CruiseSetupCard ProviderNotFound und die Messung ist
    // nicht produktionsrepräsentativ.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppAccentProvider()..load()),
        ChangeNotifierProvider(create: (_) => SavedRoutesProvider()),
        ChangeNotifierProvider(create: (_) => RouteBookmarkProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: CruiseModePage(initialRoute: route),
      ),
    );
  }
}

/// Aggregiert FrameTimings und loggt alle 10 s Kennzahlen. Bewusst simpel:
/// Listen sammeln, Perzentile beim Report sortieren, dann leeren.
class _PerfFrameStats {
  _PerfFrameStats._();
  static final _PerfFrameStats instance = _PerfFrameStats._();

  final List<double> _buildMs = [];
  final List<double> _rasterMs = [];
  int _reportNo = 0;

  void start() {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    Timer.periodic(const Duration(seconds: 10), (_) => _report());
    debugPrint('[PERF] FrameStats aktiv — Report alle 10s');
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _buildMs.add(t.buildDuration.inMicroseconds / 1000.0);
      _rasterMs.add(t.rasterDuration.inMicroseconds / 1000.0);
    }
  }

  static double _pct(List<double> sorted, double p) {
    if (sorted.isEmpty) return 0;
    final idx = ((sorted.length - 1) * p).round();
    return sorted[idx];
  }

  void _report() {
    if (_buildMs.isEmpty) {
      debugPrint('[PERF] #${++_reportNo} keine Frames (statisch/idle)');
      return;
    }
    final build = List<double>.from(_buildMs)..sort();
    final raster = List<double>.from(_rasterMs)..sort();
    final n = build.length;
    final totalJank = <double>[
      for (var i = 0; i < n; i++) _buildMs[i] + _rasterMs[i],
    ];
    final jank16 = totalJank.where((t) => t > 16.7).length;
    final jank33 = totalJank.where((t) => t > 33.4).length;
    double avg(List<double> l) =>
        l.reduce((a, b) => a + b) / l.length;
    debugPrint(
      '[PERF] #${++_reportNo} frames=$n | '
      'build avg=${avg(build).toStringAsFixed(1)} '
      'p90=${_pct(build, 0.90).toStringAsFixed(1)} '
      'p99=${_pct(build, 0.99).toStringAsFixed(1)}ms | '
      'raster avg=${avg(raster).toStringAsFixed(1)} '
      'p90=${_pct(raster, 0.90).toStringAsFixed(1)} '
      'p99=${_pct(raster, 0.99).toStringAsFixed(1)}ms | '
      'jank>16.7ms=$jank16 (${(jank16 / n * 100).toStringAsFixed(1)}%) | '
      '>33ms=$jank33 (${(jank33 / n * 100).toStringAsFixed(1)}%)',
    );
    _buildMs.clear();
    _rasterMs.clear();
  }
}
