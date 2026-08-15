import 'dart:convert';
import 'dart:io';

import 'package:cruise_connect/data/services/geladene_route_manoever.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;

/// 2026-08-15 (vucko Testfahrt, Video 18:28): Geladene Routen (Favorit,
/// Post, Aufzeichnung, „Fahrt fortsetzen") trugen KEINE Manöver, nur der
/// Anfahrts-Leg. Das Banner klebte 20 s an „In den Kreisverkehr einfahren".
///
/// Jetzt holt die App fuer die geladene Geometrie eine GraphHopper-Route
/// entlang dichter Via-Punkte und uebernimmt NUR die Manöver auf die
/// Original-Koordinaten. Die Fixtures sind ECHT: die 40-km-Entdecker-Runde
/// `635bf1a1` aus der Datenbank und die live abgeholte Edge-Antwort dazu
/// (1,35 s, 39,76 km statt 40,15 km, 149 Instruktionen inkl. 60 Vias).
List<List<double>> _fixtureCoords() {
  final raw = File(
    'test/fixtures/route_635bf1a1_entdecker_40km.txt',
  ).readAsStringSync().trim();
  return raw
      .split(';')
      .map((p) => p.split(',').map(double.parse).toList())
      .toList();
}

double _abstandZurGeometrie(
  List<List<double>> coords,
  double lng,
  double lat,
) {
  var best = double.infinity;
  for (final c in coords) {
    final d = geo.Geolocator.distanceBetween(lat, lng, c[1], c[0]);
    if (d < best) best = d;
  }
  return best;
}

void main() {
  group('waehleViaPunkte', () {
    test('40-km-Runde bekommt 60 Vias, gleichmaessig verteilt', () {
      final coords = _fixtureCoords();
      final vias = waehleViaPunkte(coords);
      expect(vias.length, 60);
      // Jeder Via ist ein Original-Punkt (keine Interpolation).
      for (final v in vias) {
        expect(
          coords.any((c) => c[0] == v[0] && c[1] == v[1]),
          isTrue,
        );
      }
      // Erster Via nicht der Start, letzter nicht das Ende.
      expect(vias.first, isNot(equals(coords.first)));
      expect(vias.last, isNot(equals(coords.last)));
    });

    test('kurze Strecken bekommen keine Vias', () {
      expect(
        waehleViaPunkte([
          [9.7, 47.4],
          [9.701, 47.4],
          [9.702, 47.4],
        ]),
        isEmpty,
      );
    });
  });

  group('uebertrageManoeverAufGeometrie', () {
    late List<List<double>> original;
    late RouteResultLike gh;
    late RouteService service;

    setUp(() {
      original = _fixtureCoords();
      service = RouteService();
      final json = jsonDecode(
        File(
          'test/fixtures/route_635bf1a1_gh_via_response.json',
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      final route = json['route'] as Map<String, dynamic>;
      final coords = service.extractCoordinates(
        Map<String, dynamic>.from(route['geometry'] as Map),
      );
      final maneuvers = service.extractManeuvers(json, coords);
      gh = RouteResultLike(coords: coords, maneuvers: maneuvers);
    });

    List<RouteManeuver> uebertrage() => uebertrageManoeverAufGeometrie(
          original: original,
          abgeleitet: gh.coords,
          manoever: gh.maneuvers,
          vias: waehleViaPunkte(original),
        );

    test('echte GH-Antwort: 24 von 30 kommen an, alle Kreisel dabei', () {
      // Vias (sign 5) und Geradeaus (sign 0) filtert der Extractor bereits.
      expect(gh.maneuvers.length, 30);
      final uebertragen = uebertrage();
      // 6 Artefakte fliegen: Schleifchen an einem Via (3x „Scharf links"
      // auf der Schwarzacher Strasse) und ein 0-m-Ausflug in eine Einfahrt
      // („links auf Rohrbach / wenden / links auf Hoechsterstrasse").
      expect(uebertragen.length, 24);
      final kreisel = uebertragen
          .where((m) => m.maneuverType == ManeuverType.roundabout)
          .toList();
      expect(kreisel.length, 3);
      expect(kreisel.map((k) => k.roundaboutExitNumber), [1, 2, 3]);
      expect(uebertragen.last.instruction, 'Ziel erreicht.');
      expect(uebertragen.last.routeIndex, original.length - 1);
      // Die Artefakte sind draussen.
      expect(
        uebertragen.any((m) => m.instruction.contains('Rohrbach')),
        isFalse,
      );
      expect(
        uebertragen.any((m) => m.instruction.contains('Schwarzacher Straße')),
        isFalse,
      );
    });

    test('jedes uebertragene Manoever sitzt AUF der Original-Geometrie', () {
      final uebertragen = uebertrage();
      for (final m in uebertragen) {
        expect(m.routeIndex, inInclusiveRange(0, original.length - 1));
        expect(original[m.routeIndex][0], m.longitude);
        expect(original[m.routeIndex][1], m.latitude);
        // ...und ein GH-Manöver mit GLEICHER Anweisung liegt in der Naehe
        // (Zuordnung nicht verrutscht; Wenden duerfen bis 250 m wandern,
        // weil GH bei Stichstrassen vor dem echten Wendepunkt kehrt).
        final istWende = m.instruction.startsWith('Wenden');
        final passend = gh.maneuvers.where(
          (g) =>
              g.instruction == m.instruction &&
              geo.Geolocator.distanceBetween(
                    g.latitude,
                    g.longitude,
                    m.latitude,
                    m.longitude,
                  ) <=
                  (istWende ? 250 : 30),
        );
        expect(
          passend,
          isNotEmpty,
          reason: '${m.instruction} bei ${m.latitude},${m.longitude}',
        );
      }
    });

    test('Indizes sind streng monoton (Hin-und-zurueck-Stiche verwechseln '
        'die Aeste nicht)', () {
      final uebertragen = uebertrage();
      for (var i = 1; i < uebertragen.length; i++) {
        expect(uebertragen[i].routeIndex, greaterThan(uebertragen[i - 1].routeIndex));
      }
      // Der Altweg-Stich wird hin UND zurueck gefahren: „Rechts auf Altweg"
      // (hin), Wende, „Links auf Weidachstrasse" (zurueck) — drei
      // verschiedene Indizes in dieser Reihenfolge.
      final altweg = uebertragen.indexWhere((m) => m.instruction == 'Rechts abbiegen auf Altweg.');
      final wende = uebertragen.indexWhere((m) => m.instruction == 'Wenden auf Altweg.');
      // „Links auf Weidachstrasse" gibt es hin UND zurueck — die zweite ist
      // die nach der Wende.
      final zurueck = uebertragen.lastIndexWhere(
        (m) => m.instruction == 'Links abbiegen auf Weidachstraße.',
      );
      expect(altweg, greaterThanOrEqualTo(0));
      expect(wende, altweg + 1);
      expect(zurueck, wende + 1);
    });

    test('Wenden sitzen am ECHTEN Wendepunkt der Original-Geometrie', () {
      final uebertragen = uebertrage();
      final wenden = uebertragen
          .where((m) => m.instruction.startsWith('Wenden'))
          .toList();
      expect(wenden.length, 2);
      for (final w in wenden) {
        // Kurs 40 m davor vs. 40 m danach auf der Original-Geometrie: kehrt.
        final i = w.routeIndex;
        final vor = original[(i - 3).clamp(0, original.length - 1)];
        final nach = original[(i + 3).clamp(0, original.length - 1)];
        final k1 = geo.Geolocator.bearingBetween(vor[1], vor[0], w.latitude, w.longitude);
        final k2 = geo.Geolocator.bearingBetween(w.latitude, w.longitude, nach[1], nach[0]);
        var d = (k2 - k1).abs() % 360;
        if (d > 180) d = 360 - d;
        expect(d, greaterThan(150), reason: 'Wende ${w.instruction} kehrt nicht');
      }
    });

    test('ohne Vias (nur Proportion) bleibt das Ergebnis brauchbar', () {
      final ohne = uebertrageManoeverAufGeometrie(
        original: original,
        abgeleitet: gh.coords,
        manoever: gh.maneuvers,
      );
      expect(ohne.length, greaterThanOrEqualTo(15));
      for (var i = 1; i < ohne.length; i++) {
        expect(ohne[i].routeIndex, greaterThan(ohne[i - 1].routeIndex));
      }
    });

    test('weicht die abgeleitete Route ab, fliegt das Manoever', () {
      // Kuenstlich: die abgeleitete Route zweigt nach 30 % ab (Parallel-
      // versatz 300 m) — dort liegende Manöver duerfen nicht uebernommen
      // werden, davor schon.
      final n = gh.coords.length;
      final abgeleitet = <List<double>>[];
      for (var i = 0; i < n; i++) {
        final c = gh.coords[i];
        abgeleitet.add(i > n * 0.3 ? [c[0] + 0.004, c[1]] : [c[0], c[1]]);
      }
      final uebertragen = uebertrageManoeverAufGeometrie(
        original: original,
        abgeleitet: abgeleitet,
        manoever: gh.maneuvers,
        vias: waehleViaPunkte(original),
      );
      final voll = uebertrage();
      expect(uebertragen.length, lessThan(voll.length));
      for (final m in uebertragen) {
        expect(
          _abstandZurGeometrie(original, m.longitude, m.latitude),
          lessThanOrEqualTo(30),
        );
      }
    });

    test('leere Eingaben liefern leer', () {
      expect(
        uebertrageManoeverAufGeometrie(
          original: original,
          abgeleitet: const [],
          manoever: gh.maneuvers,
        ),
        isEmpty,
      );
      expect(
        uebertrageManoeverAufGeometrie(
          original: original,
          abgeleitet: gh.coords,
          manoever: const [],
        ),
        isEmpty,
      );
    });
  });

  group('Aufgezeichneter GPS-Track (Vuckos Fahrt vom 07.08., 36 km)', () {
    // Zweites ECHTES Paar: GPS-Aufzeichnung (jeder 4. Punkt) + live geholte
    // Edge-Antwort (1,1 s, 36,17 km statt 36,35 km Track, 132 Instruktionen).
    // Der Track enthaelt eine echte Wende auf einem „Platz" (rein, kehren,
    // raus) und eine Haarnadel in Egg — GPS-Rauschen inklusive.
    late List<List<double>> original;
    late RouteResultLike gh;

    setUp(() {
      final raw = File(
        'test/fixtures/track_6585cc2b_aufzeichnung_36km_jeder4.txt',
      ).readAsStringSync().trim();
      original = raw
          .split(';')
          .map((p) => p.split(',').map(double.parse).toList())
          .toList();
      final service = RouteService();
      final json = jsonDecode(
        File(
          'test/fixtures/track_6585cc2b_gh_via_response.json',
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      final route = json['route'] as Map<String, dynamic>;
      final coords = service.extractCoordinates(
        Map<String, dynamic>.from(route['geometry'] as Map),
      );
      gh = RouteResultLike(
        coords: coords,
        maneuvers: service.extractManeuvers(json, coords),
      );
    });

    test('9 von 10 Manoevern landen auf dem Track, Wende am Kehrpunkt', () {
      expect(gh.maneuvers.length, 10);
      final u = uebertrageManoeverAufGeometrie(
        original: original,
        abgeleitet: gh.coords,
        manoever: gh.maneuvers,
        vias: waehleViaPunkte(original),
      );
      expect(u.length, 9);
      for (var i = 1; i < u.length; i++) {
        expect(u[i].routeIndex, greaterThan(u[i - 1].routeIndex));
      }
      final wende = u.singleWhere((m) => m.instruction == 'Wenden auf Platz.');
      final i = wende.routeIndex;
      final vor = original[i - 3];
      final nach = original[i + 3];
      final k1 = geo.Geolocator.bearingBetween(vor[1], vor[0], wende.latitude, wende.longitude);
      final k2 = geo.Geolocator.bearingBetween(wende.latitude, wende.longitude, nach[1], nach[0]);
      var d = (k2 - k1).abs() % 360;
      if (d > 180) d = 360 - d;
      expect(d, greaterThan(150));
      // Reihenfolge der Platz-Schleife: rein, scharf links, Wende, raus.
      final namen = u.map((m) => m.instruction).toList();
      expect(
        namen.indexOf('Rechts abbiegen auf Platz.'),
        lessThan(namen.indexOf('Wenden auf Platz.')),
      );
      expect(
        namen.indexOf('Wenden auf Platz.'),
        lessThan(namen.indexOf('Links abbiegen auf L5.')),
      );
      expect(u.last.instruction, 'Ziel erreicht.');
      expect(u.last.routeIndex, original.length - 1);
    });
  });

  group('Verdrahtung', () {
    test('_loadSavedRoute laedt Manoever nach und haengt sie an die Route', () {
      final page = File(
        'lib/presentation/pages/cruise_mode_page.dart',
      ).readAsStringSync();
      final start = page.indexOf('Future<void> _loadSavedRoute(');
      final rumpf = page.substring(start, start + 4000);
      expect(rumpf.contains('manoeverFuerGeladeneRoute('), isTrue);
      expect(rumpf.contains('maneuvers: nachgeladeneManoever'), isTrue);
      expect(rumpf.contains('maneuvers: [],'), isFalse,
          reason: 'die leere Manoeverliste war der Hänger-Grund');
    });
  });
}

class RouteResultLike {
  RouteResultLike({required this.coords, required this.maneuvers});
  final List<List<double>> coords;
  final List<RouteManeuver> maneuvers;
}

// Damit `Icons` importiert bleibt, falls Extractor Icons braucht.
// ignore: unused_element
const _unused = Icons.turn_right;
