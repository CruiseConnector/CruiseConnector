// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';

// ─── Hilfsfunktionen ─────────────────────────────────────────────────────────

RouteManeuver _maneuver(IconData icon, {int routeIndex = 0, String instruction = 'Test'}) {
  return RouteManeuver(
    latitude: 48.14,
    longitude: 11.58,
    routeIndex: routeIndex,
    icon: icon,
    announcement: 'Test-Ansage',
    instruction: instruction,
  );
}

RouteManeuver _uTurnLeft({int routeIndex = 5}) =>
    _maneuver(Icons.u_turn_left, routeIndex: routeIndex, instruction: 'Wenden');

RouteManeuver _uTurnRight({int routeIndex = 5}) =>
    _maneuver(Icons.u_turn_right, routeIndex: routeIndex, instruction: 'Wenden');

RouteManeuver _arrive({int routeIndex = 50}) =>
    _maneuver(Icons.flag, routeIndex: routeIndex, instruction: 'Ziel erreicht');

RouteManeuver _turnLeft({int routeIndex = 10}) =>
    _maneuver(Icons.turn_left, routeIndex: routeIndex, instruction: 'Links abbiegen');

RouteManeuver _straight({int routeIndex = 10, String instruction = 'Weiterfahren auf Musterstraße'}) =>
    _maneuver(Icons.straight, routeIndex: routeIndex, instruction: instruction);

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late RouteService service;

  setUp(() => service = RouteService());

  group('filterManeuvers – U-Turns', () {
    test('U-Turn links wird gefiltert', () {
      final result = service.filterManeuvers([
        _turnLeft(),
        _uTurnLeft(routeIndex: 20),
        _arrive(routeIndex: 40),
      ]);
      expect(result.any((m) => m.icon == Icons.u_turn_left), isFalse);
    });

    test('U-Turn rechts wird gefiltert', () {
      final result = service.filterManeuvers([
        _turnLeft(),
        _uTurnRight(routeIndex: 20),
        _arrive(routeIndex: 40),
      ]);
      expect(result.any((m) => m.icon == Icons.u_turn_right), isFalse);
    });

    test('Beide U-Turn-Richtungen gleichzeitig werden gefiltert', () {
      final result = service.filterManeuvers([
        _uTurnLeft(routeIndex: 10),
        _uTurnRight(routeIndex: 20),
        _arrive(routeIndex: 40),
      ]);
      expect(result.any((m) => m.icon == Icons.u_turn_left), isFalse);
      expect(result.any((m) => m.icon == Icons.u_turn_right), isFalse);
    });

    test('Normale Manöver werden nicht durch U-Turn-Filter entfernt', () {
      final result = service.filterManeuvers([
        _turnLeft(routeIndex: 10),
        _uTurnLeft(routeIndex: 20),
        _arrive(routeIndex: 40),
      ]);
      expect(result.any((m) => m.icon == Icons.turn_left), isTrue);
    });
  });

  group('filterManeuvers – Mehrere Arrives (Zwischenziele)', () {
    test('Nur letztes Arrive wird behalten', () {
      final result = service.filterManeuvers([
        _turnLeft(routeIndex: 10),
        _arrive(routeIndex: 20), // Zwischenziel → raus
        _turnLeft(routeIndex: 30),
        _arrive(routeIndex: 50), // Echtes Ziel → bleibt
      ]);
      final arrives = result.where((m) => m.icon == Icons.flag).toList();
      expect(arrives.length, 1);
      expect(arrives.first.routeIndex, 50);
    });

    test('Drei Arrives → nur letztes bleibt', () {
      final result = service.filterManeuvers([
        _arrive(routeIndex: 10),
        _arrive(routeIndex: 30),
        _arrive(routeIndex: 60),
      ]);
      final arrives = result.where((m) => m.icon == Icons.flag).toList();
      expect(arrives.length, 1);
      expect(arrives.first.routeIndex, 60);
    });

    test('Ein einzelnes Arrive bleibt erhalten', () {
      final result = service.filterManeuvers([
        _turnLeft(routeIndex: 10),
        _arrive(routeIndex: 30),
      ]);
      final arrives = result.where((m) => m.icon == Icons.flag).toList();
      expect(arrives.length, 1);
    });

    test('Kein Arrive in der Liste → kein Arrive im Ergebnis', () {
      final result = service.filterManeuvers([
        _turnLeft(routeIndex: 10),
        _turnLeft(routeIndex: 20),
      ]);
      expect(result.any((m) => m.icon == Icons.flag), isFalse);
    });
  });

  group('filterManeuvers – Geradeaus-Manöver', () {
    test('straight mit "Weiterfahren" in Instruction wird gefiltert', () {
      final result = service.filterManeuvers([
        _turnLeft(routeIndex: 10),
        _straight(routeIndex: 20, instruction: 'Weiterfahren auf A99'),
        _arrive(routeIndex: 40),
      ]);
      expect(result.any((m) => m.icon == Icons.straight), isFalse);
    });

    test('straight OHNE "Weiterfahren" bleibt erhalten', () {
      final result = service.filterManeuvers([
        _straight(routeIndex: 10, instruction: 'Geradeaus fahren'),
        _arrive(routeIndex: 40),
      ]);
      expect(result.any((m) => m.icon == Icons.straight), isTrue);
    });
  });

  group('filterManeuvers – Leere Eingaben', () {
    test('leere Liste → leere Liste zurück', () {
      expect(service.filterManeuvers([]), isEmpty);
    });

    test('Liste mit nur U-Turns → leere Liste', () {
      final result = service.filterManeuvers([
        _uTurnLeft(routeIndex: 10),
        _uTurnRight(routeIndex: 20),
      ]);
      expect(result, isEmpty);
    });

    test('Liste bleibt stabil wenn nichts gefiltert wird', () {
      final input = [
        _turnLeft(routeIndex: 10),
        _arrive(routeIndex: 40),
      ];
      final result = service.filterManeuvers(input);
      expect(result.length, 2);
    });
  });

  group('filterManeuvers – Kombinationen', () {
    test('U-Turn + Zwischenziel + geradeaus Weiterfahren werden alle gefiltert', () {
      final result = service.filterManeuvers([
        _turnLeft(routeIndex: 5),
        _uTurnLeft(routeIndex: 10),
        _arrive(routeIndex: 15),         // Zwischenziel
        _straight(routeIndex: 20, instruction: 'Weiterfahren auf B12'),
        _turnLeft(routeIndex: 25),
        _arrive(routeIndex: 50),         // Echtes Ziel
      ]);

      expect(result.any((m) => m.icon == Icons.u_turn_left), isFalse,
          reason: 'U-Turn soll gefiltert sein');
      expect(result.where((m) => m.icon == Icons.flag).length, 1,
          reason: 'Nur ein Arrive soll übrig bleiben');
      expect(result.any((m) => m.icon == Icons.straight), isFalse,
          reason: 'Weiterfahren-Straight soll gefiltert sein');
      expect(result.where((m) => m.icon == Icons.turn_left).length, 2,
          reason: 'Beide turn_left bleiben');
    });
  });
}
