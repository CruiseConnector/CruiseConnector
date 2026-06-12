// ignore_for_file: avoid_print

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_maneuver_indicator.dart';

void main() {
  late RouteService service;

  setUp(() => service = RouteService());

  group('iconForManeuver – Kreisverkehr', () {
    test('roundabout → roundabout_right', () {
      expect(
        service.iconForManeuver('roundabout', 'right'),
        Icons.roundabout_right,
      );
    });
    test('rotary → roundabout_right', () {
      expect(service.iconForManeuver('rotary', ''), Icons.roundabout_right);
    });
    test('roundabout turn → roundabout_right', () {
      expect(
        service.iconForManeuver('roundabout turn', ''),
        Icons.roundabout_right,
      );
    });

    test('Rechtsverkehr-Winkel: Exit 1 rechts, Exit 2 geradeaus', () {
      expect(roundaboutExitAngleForRightHandTraffic(1), closeTo(0.0, 0.001));
      expect(
        roundaboutExitAngleForRightHandTraffic(2),
        closeTo(-math.pi / 2, 0.001),
      );
      expect(
        roundaboutExitAngleForRightHandTraffic(3),
        closeTo(-math.pi, 0.001),
      );
    });

    test('GH turn_angle → Screen-Winkel: 0=oben, +π/2=rechts, -π/2=links', () {
      // 0 = geradeaus durch den Kreisverkehr → Austritt oben (-π/2 y-down).
      expect(
        roundaboutExitAngleFromTurnAngle(0),
        closeTo(-math.pi / 2, 0.001),
      );
      // +π/2 = rechts raus → Screen-Osten (0 rad).
      expect(roundaboutExitAngleFromTurnAngle(math.pi / 2), closeTo(0, 0.001));
      // -π/2 = links raus → Screen-Westen (±π).
      expect(
        roundaboutExitAngleFromTurnAngle(-math.pi / 2).abs(),
        closeTo(math.pi, 0.001),
      );
    });

    test('GraphHopper-Instruction: turn_angle landet im Manöver', () {
      final coords = [
        [9.480, 47.660],
        [9.481, 47.661],
        [9.482, 47.662],
        [9.483, 47.663],
      ];
      final response = {
        'route': {
          'instructions': [
            {
              'sign': 6,
              'exit_number': 2,
              'turn_angle': -1.57,
              'text': 'Im Kreisverkehr die zweite Ausfahrt nehmen',
              'interval': [1, 2],
            },
            {
              'sign': 4,
              'text': 'Ziel erreicht',
              'interval': [3, 3],
            },
          ],
        },
      };
      final maneuvers = service.extractManeuvers(response, coords);
      expect(maneuvers, hasLength(2));
      final roundabout = maneuvers.first;
      expect(roundabout.maneuverType, ManeuverType.roundabout);
      expect(roundabout.roundaboutExitNumber, 2);
      expect(roundabout.roundaboutTurnAngleRad, isNotNull);
      expect(roundabout.roundaboutTurnAngleRad!, closeTo(-1.57, 0.001));
      // Ziel-Manöver (kein Kreisverkehr) → kein turn_angle.
      expect(maneuvers.last.roundaboutTurnAngleRad, isNull);
    });

    test('GraphHopper-Instruction ohne turn_angle → null (Fallback)', () {
      final coords = [
        [9.480, 47.660],
        [9.481, 47.661],
        [9.482, 47.662],
      ];
      final response = {
        'route': {
          'instructions': [
            {
              'sign': 6,
              'exit_number': 3,
              'text': 'Im Kreisverkehr die dritte Ausfahrt nehmen',
              'interval': [1, 2],
            },
          ],
        },
      };
      final maneuvers = service.extractManeuvers(response, coords);
      expect(maneuvers, hasLength(1));
      expect(maneuvers.first.roundaboutExitNumber, 3);
      expect(maneuvers.first.roundaboutTurnAngleRad, isNull);
    });
  });

  group('iconForManeuver – Ziel & Start', () {
    test('arrive → flag', () {
      expect(service.iconForManeuver('arrive', ''), Icons.flag);
    });
    test('depart → navigation', () {
      expect(service.iconForManeuver('depart', ''), Icons.navigation);
    });
  });

  group('iconForManeuver – Rampen', () {
    test('on ramp links → ramp_left', () {
      expect(service.iconForManeuver('on ramp', 'left'), Icons.ramp_left);
    });
    test('on ramp rechts → ramp_right', () {
      expect(service.iconForManeuver('on ramp', 'right'), Icons.ramp_right);
    });
    test('off ramp links → ramp_left', () {
      expect(service.iconForManeuver('off ramp', 'left'), Icons.ramp_left);
    });
    test('off ramp rechts → ramp_right', () {
      expect(service.iconForManeuver('off ramp', 'right'), Icons.ramp_right);
    });
    test('on ramp ohne Modifier → ramp_right (Standard)', () {
      expect(service.iconForManeuver('on ramp', ''), Icons.ramp_right);
    });
  });

  group('iconForManeuver – Fork', () {
    test('fork links → fork_left', () {
      expect(service.iconForManeuver('fork', 'left'), Icons.fork_left);
    });
    test('fork rechts → fork_right', () {
      expect(service.iconForManeuver('fork', 'right'), Icons.fork_right);
    });
    test('fork ohne Modifier → fork_right (Standard)', () {
      expect(service.iconForManeuver('fork', ''), Icons.fork_right);
    });
  });

  group('iconForManeuver – Merge', () {
    test('merge → merge', () {
      expect(service.iconForManeuver('merge', ''), Icons.merge);
    });
    test('merge links → merge', () {
      expect(service.iconForManeuver('merge', 'left'), Icons.merge);
    });
    test('merge rechts → merge', () {
      expect(service.iconForManeuver('merge', 'right'), Icons.merge);
    });
  });

  group('iconForManeuver – Straßenende', () {
    test('end of road links → turn_left', () {
      expect(service.iconForManeuver('end of road', 'left'), Icons.turn_left);
    });
    test('end of road rechts → turn_right', () {
      expect(service.iconForManeuver('end of road', 'right'), Icons.turn_right);
    });
    test('end of road ohne Modifier → turn_left (Standard)', () {
      expect(service.iconForManeuver('end of road', ''), Icons.turn_left);
    });
  });

  group('iconForManeuver – Richtungsmodifier (turn)', () {
    test('left → turn_left', () {
      expect(service.iconForManeuver('turn', 'left'), Icons.turn_left);
    });
    test('right → turn_right', () {
      expect(service.iconForManeuver('turn', 'right'), Icons.turn_right);
    });
    test('sharp left → turn_sharp_left', () {
      expect(
        service.iconForManeuver('turn', 'sharp left'),
        Icons.turn_sharp_left,
      );
    });
    test('sharp right → turn_sharp_right', () {
      expect(
        service.iconForManeuver('turn', 'sharp right'),
        Icons.turn_sharp_right,
      );
    });
    test('slight left → turn_slight_left', () {
      expect(
        service.iconForManeuver('turn', 'slight left'),
        Icons.turn_slight_left,
      );
    });
    test('slight right → turn_slight_right', () {
      expect(
        service.iconForManeuver('turn', 'slight right'),
        Icons.turn_slight_right,
      );
    });
    test('uturn → u_turn_left', () {
      expect(service.iconForManeuver('turn', 'uturn'), Icons.u_turn_left);
    });
    test('uturn left → u_turn_left', () {
      expect(service.iconForManeuver('turn', 'uturn left'), Icons.u_turn_left);
    });
    test('uturn right → u_turn_right', () {
      expect(
        service.iconForManeuver('turn', 'uturn right'),
        Icons.u_turn_right,
      );
    });
    test('straight → straight', () {
      expect(service.iconForManeuver('turn', 'straight'), Icons.straight);
    });
    test('unbekannter Modifier → straight (Fallback)', () {
      expect(service.iconForManeuver('turn', 'xyz'), Icons.straight);
    });
  });

  group('iconForManeuver – new name / continue', () {
    test('new name mit sharp left → turn_sharp_left', () {
      expect(
        service.iconForManeuver('new name', 'sharp left'),
        Icons.turn_sharp_left,
      );
    });
    test('new name mit right → turn_right', () {
      expect(service.iconForManeuver('new name', 'right'), Icons.turn_right);
    });
    test('continue geradeaus → straight', () {
      expect(service.iconForManeuver('continue', 'straight'), Icons.straight);
    });
    test('continue ohne Modifier → straight', () {
      expect(service.iconForManeuver('continue', ''), Icons.straight);
    });
  });

  group('directionText – Deutsche Richtungstexte', () {
    test('left → Links', () {
      expect(service.directionText('left'), 'Links');
    });
    test('right → Rechts', () {
      expect(service.directionText('right'), 'Rechts');
    });
    test('slight left → Leicht links', () {
      expect(service.directionText('slight left'), 'Leicht links');
    });
    test('slight right → Leicht rechts', () {
      expect(service.directionText('slight right'), 'Leicht rechts');
    });
    test('sharp left → Scharf links', () {
      expect(service.directionText('sharp left'), 'Scharf links');
    });
    test('sharp right → Scharf rechts', () {
      expect(service.directionText('sharp right'), 'Scharf rechts');
    });
    test('Unbekannter Modifier → Weiter (Fallback)', () {
      expect(service.directionText('xyz'), 'Weiter');
    });
    test('case-insensitive: LEFT → Links', () {
      expect(service.directionText('LEFT'), 'Links');
    });
    test('Mit Leerzeichen: " right " → Rechts', () {
      expect(service.directionText(' right '), 'Rechts');
    });
  });

  group('formatDistance – Distanzformatierung', () {
    test('999 m → "In 999 m"', () {
      expect(service.formatDistance(999), 'In 999 m');
    });
    test('1000 m → "In 1,0 km"', () {
      expect(service.formatDistance(1000), 'In 1,0 km');
    });
    test('6385 m → "In 6,4 km"', () {
      expect(service.formatDistance(6385), 'In 6,4 km');
    });
    test('500 m → "In 500 m"', () {
      expect(service.formatDistance(500), 'In 500 m');
    });
    test('0 m → "In 0 m"', () {
      expect(service.formatDistance(0), 'In 0 m');
    });
    test('2000 m → "In 2,0 km"', () {
      expect(service.formatDistance(2000), 'In 2,0 km');
    });
    test('Dezimaltrennzeichen ist Komma (deutsch)', () {
      // Deutsches Format: 1,5 km statt 1.5 km
      expect(service.formatDistance(1500), contains(','));
    });
  });
}
