import 'dart:io';
import 'dart:math' as math;

import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-15 (vucko Testfahrt, Aufgabe 4): „Die App berechnet die Route
/// manchmal grundlos neu, und die Kreisverkehr-Symbole sind fuer die
/// Ausfahrten komplett falsch."
///
/// AM VIDEO BELEGT: Banner „Im Kreisverkehr Ausfahrt 1 nehmen" mit S-Bogen
/// statt Kreisel-mit-Ausfahrt; danach sieben Frames „Jetzt · In den
/// Kreisverkehr einfahren" bei 550→240 m Rest.
///
/// URSACHEN + FIXES (jeweils ein Test):
///  1. GraphHoppers `interval[1]` galt als Ring-Austritt — es ist aber der
///     Beginn der NAECHSTEN Instruktion (bis 40 m hinter dem Kreisel). Jetzt
///     wird der echte Austritt aus der Geometrie gelesen.
///  2. Waren alle Manoever hinter dem Puck, blieb das LETZTE aktiv (Banner
///     klebte). Jetzt: kein aktives Manoever.
///  3. Der Frozen-Progress-Watchdog zaehlte Standzeit — 20 s Rot vor dem
///     Kreisel + Anfahren = grundloser Reroute. Jetzt: ≥ 75 m echte Fahrt,
///     Kreisel-Schutz, Reset im Commit.

/// Ein idealisierter Kreisverkehr (Radius 20 m) als [lng, lat]-Polyline:
/// Zufahrt von Sueden, Einfahrt, links herum bis zum Winkel [ausfahrtDeg]
/// (0 = Osten, gegen den Uhrzeigersinn), dann geradeaus die Ausfahrt hinaus.
List<List<double>> _kreisel({required double ausfahrtDeg, int nachher = 6}) {
  const lat0 = 47.4;
  const lng0 = 9.7;
  const r = 20.0;
  const mPerLat = 110540.0;
  final mPerLng = 111320.0 * math.cos(lat0 * math.pi / 180);
  List<double> p(double xM, double yM) => [lng0 + xM / mPerLng, lat0 + yM / mPerLat];
  final pts = <List<double>>[];
  // Zufahrt von Sueden zum Ring (Ring-Einfahrt bei Winkel -90° = Sueden).
  for (var y = -140.0; y < -r; y += 20) {
    pts.add(p(0, y));
  }
  // Ring: von -90° gegen den Uhrzeigersinn (Rechtsverkehr = links herum) bis
  // zum Ausfahrtwinkel.
  const start = -90.0;
  var ende = ausfahrtDeg;
  while (ende <= start) {
    ende += 360;
  }
  for (var a = start; a <= ende; a += 10) {
    final rad = a * math.pi / 180;
    pts.add(p(r * math.cos(rad), r * math.sin(rad)));
  }
  // Ausfahrt: radial nach aussen (geradeaus vom Ring weg).
  final rad = ende * math.pi / 180;
  for (var i = 1; i <= nachher; i++) {
    final d = r + i * 25.0;
    pts.add(p(d * math.cos(rad), d * math.sin(rad)));
  }
  return pts;
}

RouteManeuver _m(int idx, {ManeuverType typ = ManeuverType.normal, String text = 'x'}) =>
    RouteManeuver(
      latitude: 47.4,
      longitude: 9.7,
      routeIndex: idx,
      icon: Icons.turn_right,
      announcement: text,
      instruction: text,
      maneuverType: typ,
    );

void main() {
  group('1. Kreisel-Austritt aus der Geometrie', () {
    test('Ausfahrt 1 (rechts, Osten): Austritt = erster Rechtsknick', () {
      final coords = _kreisel(ausfahrtDeg: 0);
      const entry = 6; // erster Ringpunkt (nach 6 Zufahrtspunkten 0..5)
      final exit = roundaboutRingExitIndex(coords, entry, coords.length - 1);
      expect(exit, isNotNull);
      // Der Austritt liegt am Ende des Ringbogens (Winkel 0°), nicht am
      // Beginn der Ausfahrtsstrasse und schon gar nicht 40 m dahinter.
      const ringEnde = entry + 9; // -90° … 0° in 10°-Schritten
      expect(exit, inInclusiveRange(ringEnde - 1, ringEnde));
    });

    test('Ausfahrt 3 (Westen): Austritt liegt hinter drei Vierteln des Rings', () {
      final coords = _kreisel(ausfahrtDeg: 180);
      const entry = 6;
      final exit = roundaboutRingExitIndex(coords, entry, coords.length - 1)!;
      const ringEnde = entry + 27; // -90° … 180°
      expect(exit, inInclusiveRange(ringEnde - 1, ringEnde));
      // Der Ausfahrts-Kurs vom Austritt aus zeigt nach Westen (270°) …
      final exitBearing = calculateBearing(
        coords[exit][1], coords[exit][0], coords[exit + 2][1], coords[exit + 2][0],
      );
      expect(exitBearing, closeTo(270, 12));
      // … waehrend interval[1]-Logik (Beginn der naechsten Instruktion,
      // hier das Ende der Liste) den Kurs 40 m weiter draussen misst — auf
      // der geraden Ausfahrt zufaellig gleich, in der Praxis (Kurve dahinter)
      // aber ein anderer. Der Drehwinkel Einfahrt→Austritt muss ~-90° (links)
      // sein: von Norden (0°) nach Westen (270°).
      final turn = roundaboutGeomTurnRad(coords, entry, exit)!;
      expect(turn * 180 / math.pi, closeTo(-90, 15));
    });

    test('ohne Rechtsknick (Ring ohne Ausfahrt) kommt null → alte Rueckfaelle', () {
      final coords = _kreisel(ausfahrtDeg: 0, nachher: 0);
      // Ring bis 0° und dann NICHTS mehr: nach dem Ring kein Knick.
      final exit = roundaboutRingExitIndex(coords, 6, coords.length - 1);
      expect(exit, isNull);
    });

    test('Suchgrenze in Metern: fromIdx+3 mindestens, sonst nach Strecke', () {
      final coords = _kreisel(ausfahrtDeg: 0);
      expect(roundaboutSearchLimitIndex(coords, 6, 0), 9);
      final weit = roundaboutSearchLimitIndex(coords, 6, 120);
      expect(weit, greaterThan(9));
      expect(weit, lessThan(coords.length));
      expect(roundaboutSearchLimitIndex(coords, 6, 100000), coords.length - 1);
    });

    test('alle drei Kreisel-Stellen nutzen den Geometrie-Austritt', () {
      final rs = File('lib/data/services/route_service.dart').readAsStringSync();
      final cm = File('lib/presentation/pages/cruise_mode_page.dart').readAsStringSync();
      // GraphHopper-Pfad, Mapbox-Pfad, versteckter Kreisel.
      expect(RegExp(r'roundaboutRingExitIndex\(').allMatches(rs).length, greaterThanOrEqualTo(3));
      expect(cm.contains('roundaboutRingExitIndex('), isTrue);
      // Mapbox-Pfad misst die Ausfahrt nicht mehr am Einfahrtspunkt.
      expect(rs.contains('roundaboutGeomTurnRad(routeCoordinates, routeIndex, routeIndex)'), isFalse);
    });
  });

  group('2. Banner klebt nicht mehr am letzten Manoever', () {
    test('alle Manoever hinter dem Puck → kein aktives (statt lastIndex)', () {
      final maneuvers = [
        _m(10, typ: ManeuverType.roundabout, text: 'In den Kreisverkehr einfahren'),
        _m(30, text: 'Rechts abbiegen'),
      ];
      final idx = selectActiveGuidanceManeuverIndex(
        maneuvers: maneuvers,
        currentRouteIndex: 200,
        startIndex: 1,
        remainingRouteDistanceMeters: 5000,
        distanceToFinalTargetMeters: 5000,
        arrivalRadiusMeters: 30,
      );
      expect(idx, isNull, reason: 'sonst haengt „In den Kreisverkehr einfahren" bis zum Ziel');
    });

    test('… ausser das letzte ist die Ankunft', () {
      final maneuvers = [
        _m(10, text: 'Rechts abbiegen'),
        const RouteManeuver(
          latitude: 47.4,
          longitude: 9.7,
          routeIndex: 30,
          icon: Icons.flag,
          announcement: 'Ziel erreicht.',
          instruction: 'Ziel erreicht.',
        ),
      ];
      final idx = selectActiveGuidanceManeuverIndex(
        maneuvers: maneuvers,
        currentRouteIndex: 200,
        startIndex: 1,
        remainingRouteDistanceMeters: 20,
        distanceToFinalTargetMeters: 20,
        arrivalRadiusMeters: 30,
      );
      expect(idx, 1);
    });
  });

  group('3. Frozen-Progress-Watchdog', () {
    test('Standzeit zaehlt nicht: 20 s Uhr, aber 0 m gefahren → kein Reroute', () {
      expect(
        shouldForceRerouteOnFrozenProgress(
          sinceProgressChanged: const Duration(seconds: 20),
          speedMps: 8,
          approachingDestination: false,
          nearRouteEnd: false,
          drivenSinceProgressChangedM: 0,
        ),
        isFalse,
      );
    });

    test('echter Haenger: 16 s UND 90 m gefahren → Reroute', () {
      expect(
        shouldForceRerouteOnFrozenProgress(
          sinceProgressChanged: const Duration(seconds: 16),
          speedMps: 8,
          approachingDestination: false,
          nearRouteEnd: false,
          drivenSinceProgressChangedM: 90,
        ),
        isTrue,
      );
    });

    test('im Kreisverkehr nie', () {
      expect(
        shouldForceRerouteOnFrozenProgress(
          sinceProgressChanged: const Duration(seconds: 30),
          speedMps: 8,
          approachingDestination: false,
          nearRouteEnd: false,
          drivenSinceProgressChangedM: 200,
          inRoundabout: true,
        ),
        isFalse,
      );
    });

    test('Rueckwaertskompatibel: ohne Fahrweg-Angabe wie bisher', () {
      expect(
        shouldForceRerouteOnFrozenProgress(
          sinceProgressChanged: const Duration(seconds: 16),
          speedMps: 8,
          approachingDestination: false,
          nearRouteEnd: false,
        ),
        isTrue,
      );
    });

    test('Verdrahtung: Stand nullt Uhr+Fahrweg, Commit nullt Watchdog+Off-Route', () {
      final cm = File('lib/presentation/pages/cruise_mode_page.dart').readAsStringSync();
      final wd = cm.indexOf('Frozen-Progress-Watchdog. Die Render-Lock-Distanz');
      expect(wd, greaterThan(0));
      final block = cm.substring(wd, wd + 3500);
      expect(block.contains('if (watchdogSpeedMps < 5.0) {'), isTrue);
      expect(block.contains('drivenSinceProgressChangedM: _watchdogDrivenM'), isTrue);
      expect(block.contains('inRoundabout: _puckNaheKreisverkehr(position)'), isTrue);
      // Reset im Reroute-Commit (setState-Transaktion).
      final commit = cm.indexOf('Future<bool> _commitRerouteResult(');
      final commitBlock = cm.substring(commit, commit + 16000);
      expect(commitBlock.contains('_offRouteSince = null;'), isTrue);
      expect(commitBlock.contains('_renderDistChangedAt = null;'), isTrue);
      expect(commitBlock.contains('_watchdogDrivenM = 0.0;'), isTrue);
    });
  });
}
