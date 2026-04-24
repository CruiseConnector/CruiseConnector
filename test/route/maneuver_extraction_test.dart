// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';

// ─── Hilfsfunktionen für Test-Daten ──────────────────────────────────────────

/// Erzeugt eine minimale gültige Route-Response mit einem Manöver.
Map<String, dynamic> _buildResponse({
  required String type,
  String modifier = '',
  double distance = 100,
  String instruction = '',
  String stepName = '',
  int? roundaboutExit,
  List<Map<String, dynamic>> extraSteps = const [],
}) {
  final maneuverData = <String, dynamic>{
    'type': type,
    'modifier': modifier,
    'location': [11.58, 48.14], // [lng, lat]
    if (instruction.isNotEmpty) 'instruction': instruction,
    if (roundaboutExit != null) 'exit': roundaboutExit,
  };

  return {
    'route': {
      'legs': [
        {
          'steps': [
            {
              'maneuver': {'type': 'depart', 'location': [11.57, 48.13]},
              'distance': 50.0,
              'name': 'Startstraße',
            },
            {
              'maneuver': maneuverData,
              'distance': distance,
              'name': stepName,
            },
            ...extraSteps,
            {
              'maneuver': {'type': 'arrive', 'location': [11.60, 48.15]},
              'distance': 0.0,
              'name': '',
            },
          ],
        },
      ],
    },
  };
}

/// Route-Koordinaten für München-Bereich (30 Punkte).
List<List<double>> _munichCoords() => List.generate(
      30,
      (i) => [11.58 + i * 0.001, 48.14 + i * 0.0005],
    );

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late RouteService service;
  late List<List<double>> coords;

  setUp(() {
    service = RouteService();
    coords = _munichCoords();
  });

  // ─────────────────────── Grundverhalten ────────────────────────────────────

  group('extractManeuvers – Grundverhalten', () {
    test('gibt leere Liste zurück wenn keine Legs vorhanden', () {
      final data = {'route': <String, dynamic>{}};
      expect(service.extractManeuvers(data, coords), isEmpty);
    });

    test('gibt leere Liste zurück bei weniger als 2 Koordinaten', () {
      final data = _buildResponse(type: 'turn', modifier: 'left');
      expect(service.extractManeuvers(data, [[11.58, 48.14]]), isEmpty);
    });

    test('depart-Manöver wird übersprungen', () {
      final data = _buildResponse(type: 'turn', modifier: 'left');
      final maneuvers = service.extractManeuvers(data, coords);
      // Nur turn + arrive sollen vorhanden sein (depart wird gefiltert)
      expect(maneuvers.any((m) => m.icon == Icons.navigation), isFalse);
    });

    test('Schritte kürzer als 15 m werden übersprungen (außer arrive)', () {
      final data = _buildResponse(
        type: 'turn',
        modifier: 'left',
        distance: 10, // unter 15 m → soll raus
      );
      final maneuvers = service.extractManeuvers(data, coords);
      // Nur arrive soll übrig bleiben
      expect(maneuvers.length, 1);
      expect(maneuvers.first.icon, Icons.flag);
    });

    test('Manöver werden nach routeIndex sortiert', () {
      final data = _buildResponse(type: 'turn', modifier: 'right');
      final maneuvers = service.extractManeuvers(data, coords);
      for (var i = 0; i < maneuvers.length - 1; i++) {
        expect(
          maneuvers[i].routeIndex <= maneuvers[i + 1].routeIndex,
          isTrue,
          reason: 'Manöver nicht nach routeIndex sortiert',
        );
      }
    });

    test('mehrere Legs werden zusammengeführt', () {
      final data = {
        'route': {
          'legs': [
            {
              'steps': [
                {
                  'maneuver': {'type': 'turn', 'modifier': 'left', 'location': [11.58, 48.14]},
                  'distance': 200.0,
                  'name': 'Leg 1 Straße',
                },
                {
                  'maneuver': {'type': 'arrive', 'location': [11.59, 48.145]},
                  'distance': 0.0,
                  'name': '',
                },
              ],
            },
            {
              'steps': [
                {
                  'maneuver': {'type': 'turn', 'modifier': 'right', 'location': [11.59, 48.145]},
                  'distance': 300.0,
                  'name': 'Leg 2 Straße',
                },
                {
                  'maneuver': {'type': 'arrive', 'location': [11.60, 48.15]},
                  'distance': 0.0,
                  'name': '',
                },
              ],
            },
          ],
        },
      };
      final maneuvers = service.extractManeuvers(data, coords);
      // 2 turns + 2 arrives
      expect(maneuvers.length, 4);
    });
  });

  // ─────────────────────── Manöver-Typen ─────────────────────────────────────

  group('extractManeuvers – Abbiegemanöver', () {
    test('Links abbiegen → turn_left Icon', () {
      final data = _buildResponse(type: 'turn', modifier: 'left');
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.turn_left, orElse: () => throw StateError('kein turn_left'));
      expect(m.icon, Icons.turn_left);
    });

    test('Rechts abbiegen → turn_right Icon', () {
      final data = _buildResponse(type: 'turn', modifier: 'right');
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.turn_right, orElse: () => throw StateError('kein turn_right'));
      expect(m.icon, Icons.turn_right);
    });

    test('Scharf links → turn_sharp_left Icon', () {
      final data = _buildResponse(type: 'turn', modifier: 'sharp left');
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.turn_sharp_left, orElse: () => throw StateError('kein sharp_left'));
      expect(m.icon, Icons.turn_sharp_left);
    });

    test('Scharf rechts → turn_sharp_right Icon', () {
      final data = _buildResponse(type: 'turn', modifier: 'sharp right');
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.turn_sharp_right, orElse: () => throw StateError('kein sharp_right'));
      expect(m.icon, Icons.turn_sharp_right);
    });

    test('Leicht links → turn_slight_left Icon', () {
      final data = _buildResponse(type: 'turn', modifier: 'slight left');
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.turn_slight_left, orElse: () => throw StateError('kein slight_left'));
      expect(m.icon, Icons.turn_slight_left);
    });

    test('Leicht rechts → turn_slight_right Icon', () {
      final data = _buildResponse(type: 'turn', modifier: 'slight right');
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.turn_slight_right, orElse: () => throw StateError('kein slight_right'));
      expect(m.icon, Icons.turn_slight_right);
    });

    test('U-Turn links → u_turn_left Icon', () {
      final data = _buildResponse(type: 'turn', modifier: 'uturn left', distance: 50);
      final all = service.extractManeuvers(data, coords);
      // U-Turns werden nach Extraktion durch filterManeuvers entfernt,
      // aber extractManeuvers selbst erzeugt sie noch
      expect(all.any((m) => m.icon == Icons.u_turn_left || m.icon == Icons.u_turn_right), isTrue);
    });
  });

  // ─────────────────────── Spezialmanöver ───────────────────────────────────

  group('extractManeuvers – Spezialmanöver', () {
    test('Kreisverkehr → roundabout Icon + ManeuverType.roundabout', () {
      final data = _buildResponse(
        type: 'roundabout',
        modifier: 'right',
        roundaboutExit: 2,
      );
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.maneuverType == ManeuverType.roundabout, orElse: () => throw StateError('kein roundabout'));
      expect(m.icon, Icons.roundabout_right);
      expect(m.roundaboutExitNumber, 2);
      expect(m.instruction, contains('2.'));
    });

    test('Kreisverkehr Exit 1 → "1. Ausfahrt"', () {
      final data = _buildResponse(type: 'roundabout', modifier: 'right', roundaboutExit: 1);
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.maneuverType == ManeuverType.roundabout);
      expect(m.instruction, contains('1.'));
      expect(m.instruction.toLowerCase(), contains('ausfahrt'));
    });

    test('Kreisverkehr Exit 4 → "4. Ausfahrt"', () {
      final data = _buildResponse(type: 'roundabout', modifier: 'left', roundaboutExit: 4);
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.maneuverType == ManeuverType.roundabout);
      expect(m.instruction, contains('4.'));
    });

    test('Arrive → flag Icon + "Ziel erreicht"', () {
      final data = _buildResponse(type: 'turn', modifier: 'left');
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.flag);
      expect(m.instruction, contains('Ziel'));
    });

    test('Straßenende links → turn_left Icon', () {
      final data = _buildResponse(type: 'end of road', modifier: 'left');
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.turn_left, orElse: () => throw StateError('kein turn_left'));
      expect(m.icon, Icons.turn_left);
      expect(m.instruction.toLowerCase(), contains('links'));
    });

    test('Straßenende mit Straßenname → enthält Straßenname in Instruction', () {
      final data = _buildResponse(
        type: 'end of road',
        modifier: 'right',
        stepName: 'Bahnhofstraße',
      );
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.turn_right);
      expect(m.instruction, contains('Bahnhofstraße'));
    });

    test('Autobahnauffahrt links → ramp_left Icon', () {
      final data = _buildResponse(type: 'on ramp', modifier: 'left');
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.ramp_left, orElse: () => throw StateError('kein ramp_left'));
      expect(m.icon, Icons.ramp_left);
    });

    test('Autobahnausfahrt rechts → ramp_right Icon', () {
      final data = _buildResponse(type: 'off ramp', modifier: 'right');
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.ramp_right, orElse: () => throw StateError('kein ramp_right'));
      expect(m.icon, Icons.ramp_right);
    });

    test('Fork links → fork_left Icon', () {
      final data = _buildResponse(type: 'fork', modifier: 'left');
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.fork_left, orElse: () => throw StateError('kein fork_left'));
      expect(m.icon, Icons.fork_left);
    });

    test('Merge → merge Icon', () {
      final data = _buildResponse(type: 'merge', modifier: '');
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.merge, orElse: () => throw StateError('kein merge'));
      expect(m.icon, Icons.merge);
    });

    test('new name mit echter Richtungsänderung (left) → turn_left Icon', () {
      final data = _buildResponse(type: 'new name', modifier: 'left');
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.turn_left, orElse: () => throw StateError('kein turn_left'));
      expect(m.icon, Icons.turn_left);
    });

    test('continue geradeaus → straight Icon (ohne Richtungsänderung)', () {
      final data = _buildResponse(type: 'continue', modifier: 'straight');
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.straight, orElse: () => throw StateError('kein straight'));
      expect(m.icon, Icons.straight);
    });
  });

  // ─────────────────────── Ansagen ──────────────────────────────────────────

  group('extractManeuvers – Ansagen', () {
    test('Ansage enthält Distanz in Metern für kurze Distanzen', () {
      final data = _buildResponse(type: 'turn', modifier: 'left', distance: 200);
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.turn_left);
      expect(m.announcement, contains('200'));
    });

    test('Ansage enthält km-Format für lange Distanzen', () {
      final data = _buildResponse(type: 'turn', modifier: 'left', distance: 2500);
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.turn_left);
      expect(m.announcement, contains('2,5 km'));
    });

    test('Arrive-Ansage → "Ziel erreicht"', () {
      final data = _buildResponse(type: 'turn', modifier: 'right');
      final m = service.extractManeuvers(data, coords)
          .firstWhere((x) => x.icon == Icons.flag);
      expect(m.announcement, contains('Ziel'));
    });
  });
}
