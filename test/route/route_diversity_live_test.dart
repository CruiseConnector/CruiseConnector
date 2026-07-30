// ignore_for_file: avoid_print, depend_on_referenced_packages
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/data/services/country_region.dart';
import 'package:cruise_connect/data/services/route_quality_validator.dart';
import 'package:cruise_connect/data/services/route_service.dart';

/// 2026-07-27 (vucko): „Schau ob der Inlandsfilter wirklich viel besser läuft,
/// dass die Routen diverser sind, und dass zwei Leute die gleichzeitig mit
/// verschiedenen Geräten und verschiedenen Einstellungen suchen NIEMALS das
/// gleiche bekommen können."
///
/// Diese Datei misst das gegen die ECHTE Edge-Function, nicht gegen Mocks —
/// nur so ist die Aussage belastbar. Sie ist deshalb standardmäßig aus und
/// läuft nur mit `--dart-define=RUN_LIVE_DIVERSITY=true`.
///
/// Zwei „Geräte" werden durch zwei unabhängige [RouteService]-Instanzen
/// dargestellt. Das ist die realistische Abbildung: jede Instanz hat ihre
/// eigenen Varianten-Zähler, ihren eigenen Zufallsgenerator und ihre eigene
/// Sektor-Historie — genau wie zwei Handys.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const run = bool.fromEnvironment('RUN_LIVE_DIVERSITY', defaultValue: false);
  const rounds = int.fromEnvironment('DIVERSITY_ROUNDS', defaultValue: 5);
  const outPath = String.fromEnvironment(
    'DIVERSITY_OUTPUT',
    defaultValue: '/tmp/route-diversity.json',
  );

  // Dornbirn: rund 10 km bis Deutschland, 15 km bis zur Schweiz. Ein
  // 100-km-Rundkurs MUSS hier ins Ausland laufen, wenn der Filter nicht greift.
  geo.Position start() => geo.Position(
    latitude: 47.4125,
    longitude: 9.7414,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
    accuracy: 5,
    altitude: 400,
    altitudeAccuracy: 3,
    heading: 0,
    headingAccuracy: 3,
    speed: 0,
    speedAccuracy: 1,
  );

  double similarity(List<List<double>> a, List<List<double>> b) =>
      RouteQualityValidator.calculateRouteSimilarityPercent(
        a,
        b,
        sampleCount: 48,
        proximityMeters: 145.0,
      );

  setUpAll(() async {
    if (!run) return;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
      debug: false,
    );
  });

  test('Live: Ladezeit, Vielfalt, Parallelsuche, Inlandsfilter', skip: !run, () async {
    RouteService.disableBackgroundPreparation = true;
    final protokoll = <Map<String, dynamic>>[];

    // ── 1) Wiederholtes „Nochmal suchen" auf EINEM Gerät ────────────────────
    RouteService.resetForTests();
    final geraetA = RouteService();
    final aRouten = <List<List<double>>>[];
    final aDauern = <int>[];
    for (var i = 0; i < rounds; i++) {
      final t = Stopwatch()..start();
      final r = await geraetA.generateRoundTrip(
        startPosition: start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        forceFreshVariant: i > 0,
        debugTrigger: i == 0 ? 'firstSearch' : 'searchAgain',
      );
      t.stop();
      aDauern.add(t.elapsedMilliseconds);
      aRouten.add(r.coordinates);
      protokoll.add({
        'phase': 'searchAgain',
        'lauf': i,
        'dauerMs': t.elapsedMilliseconds,
        'km': r.distanceKm?.toStringAsFixed(1) ?? '-',
        'fingerprint': RouteService.lastRouteDebugFingerprint,
      });
    }

    // Jede Route muss sich von JEDER vorherigen unterscheiden, nicht nur von
    // der letzten — genau das war Vuckos Beschwerde („nach Neustart kamen
    // Strecken, die schon vorher in der Suche waren").
    for (var i = 0; i < aRouten.length; i++) {
      for (var j = i + 1; j < aRouten.length; j++) {
        final s = similarity(aRouten[i], aRouten[j]);
        expect(
          s,
          lessThan(72.0),
          reason: 'Lauf $i und $j sind zu ähnlich (${s.toStringAsFixed(1)}%)',
        );
      }
    }

    // Ladezeit: eine Routensuche darf sich nicht wie ein Hänger anfühlen.
    aDauern.sort();
    final p95 = aDauern[((aDauern.length - 1) * 0.95).floor()];
    expect(p95, lessThan(15000), reason: 'p95 Ladezeit $p95 ms');

    // ── 2) Zwei Geräte GLEICHZEITIG, verschiedene Einstellungen ─────────────
    RouteService.resetForTests();
    final g1 = RouteService();
    final g2 = RouteService();
    final parallel = await Future.wait([
      g1.generateRoundTrip(
        startPosition: start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        avoidHighways: false,
        forceFreshVariant: true,
        debugTrigger: 'geraet1',
      ),
      g2.generateRoundTrip(
        startPosition: start(),
        targetDistanceKm: 100,
        mode: 'Kurvenjagd',
        planningType: 'Zufall',
        avoidHighways: true,
        forceFreshVariant: true,
        debugTrigger: 'geraet2',
      ),
    ]);
    final sParallel = similarity(
      parallel[0].coordinates,
      parallel[1].coordinates,
    );
    protokoll.add({
      'phase': 'parallelVerschiedeneEinstellungen',
      'aehnlichkeitProzent': sParallel,
      'km1': parallel[0].distanceKm?.toStringAsFixed(1) ?? '-',
      'km2': parallel[1].distanceKm?.toStringAsFixed(1) ?? '-',
    });
    expect(
      sParallel,
      lessThan(50.0),
      reason:
          'Zwei gleichzeitige Suchen mit VERSCHIEDENEN Einstellungen dürfen '
          'sich nicht ähneln (${sParallel.toStringAsFixed(1)}%)',
    );

    // ── 3) Zwei Geräte gleichzeitig, GLEICHE Einstellungen ─────────────────
    // Der härtere Fall: identische Eingaben. Hier zählt, dass die
    // client-seitigen Zufallsquellen (Varianten-Zähler, Jitter, Sektor-
    // Historie) pro Instanz unabhängig sind.
    RouteService.resetForTests();
    final h1 = RouteService();
    final h2 = RouteService();
    final gleich = await Future.wait([
      h1.generateRoundTrip(
        startPosition: start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        forceFreshVariant: true,
        debugTrigger: 'gleichA',
      ),
      h2.generateRoundTrip(
        startPosition: start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        forceFreshVariant: true,
        debugTrigger: 'gleichB',
      ),
    ]);
    final sGleich = similarity(gleich[0].coordinates, gleich[1].coordinates);
    protokoll.add({
      'phase': 'parallelGleicheEinstellungen',
      'aehnlichkeitProzent': sGleich,
      'km1': gleich[0].distanceKm?.toStringAsFixed(1) ?? '-',
      'km2': gleich[1].distanceKm?.toStringAsFixed(1) ?? '-',
    });

    // ── 4) Inlandsfilter: nur Inland gegen egal ─────────────────────────────
    RouteService.resetForTests();
    final inland = RouteService();
    for (final pref in [CountryPreference.any, CountryPreference.onlyHome]) {
      for (var i = 0; i < 3; i++) {
        final r = await inland.generateRoundTrip(
          startPosition: start(),
          targetDistanceKm: 100,
          mode: 'Kurvenjagd',
          planningType: 'Zufall',
          avoidHighways: true,
          forceFreshVariant: true,
          debugTrigger: 'inland',
          countryPreference: pref,
          homeCountryCode: pref == CountryPreference.any ? null : 'AT',
        );
        // Punkte ausserhalb Oesterreichs zaehlen (grobe, aber ausreichende
        // Box: alles westlich von 9.53 ist CH/FL, alles noerdlich von 47.56
        // bei diesen Laengen ist DE).
        var auslandPunkte = 0;
        for (final c in r.coordinates) {
          final lng = c[0];
          final lat = c[1];
          if (lng < 9.53 || lat > 47.58) auslandPunkte++;
        }
        protokoll.add({
          'phase': 'inland',
          'praeferenz': pref.name,
          'lauf': i,
          'km': r.distanceKm?.toStringAsFixed(1) ?? '-',
          'punkte': r.coordinates.length,
          'auslandPunkte': auslandPunkte,
          'auslandAnteilProzent': r.coordinates.isEmpty
              ? 0
              : (auslandPunkte * 100 / r.coordinates.length),
        });
      }
    }

    final nurInland = protokoll.where(
      (p) => p['phase'] == 'inland' && p['praeferenz'] == 'onlyHome',
    );
    for (final p in nurInland) {
      expect(
        p['auslandAnteilProzent'] as num,
        lessThan(2.0),
        reason: 'Mit „nur Inland" darf praktisch kein Auslandsanteil '
            'entstehen: $p',
      );
    }

    await File(outPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(protokoll),
    );
    print('DIVERSITY_REPORT ${jsonEncode(protokoll)}');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
