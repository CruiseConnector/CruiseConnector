// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/route_service.dart';

void main() {
  late RouteService service;

  setUp(() => service = RouteService());

  group('RouteService.extractCoordinates', () {
    test('extrahiert valide [lng, lat] Paare korrekt', () {
      final geometry = {
        'coordinates': [
          [10.0, 48.0],
          [10.1, 48.1],
          [10.2, 48.2],
        ],
      };
      final result = service.extractCoordinates(geometry);
      expect(result.length, 3);
      expect(result[0], [10.0, 48.0]);
      expect(result[2], [10.2, 48.2]);
    });

    test('filtert Einträge ohne mindestens 2 Werte heraus', () {
      final geometry = {
        'coordinates': [
          [10.0, 48.0],
          [10.1], // nur 1 Wert → wird gefiltert
          [10.2, 48.2],
        ],
      };
      final result = service.extractCoordinates(geometry);
      expect(result.length, 2);
    });

    test('gibt leere Liste zurück wenn coordinates fehlt', () {
      final geometry = <String, dynamic>{};
      final result = service.extractCoordinates(geometry);
      expect(result, isEmpty);
    });

    test('gibt leere Liste zurück wenn coordinates null ist', () {
      final geometry = {'coordinates': null};
      final result = service.extractCoordinates(geometry);
      expect(result, isEmpty);
    });

    test('gibt leere Liste zurück bei leerem coordinates-Array', () {
      final geometry = {'coordinates': <dynamic>[]};
      final result = service.extractCoordinates(geometry);
      expect(result, isEmpty);
    });

    test('konvertiert int-Werte korrekt zu double', () {
      final geometry = {
        'coordinates': [
          [10, 48], // ints statt doubles
        ],
      };
      final result = service.extractCoordinates(geometry);
      expect(result.length, 1);
      expect(result[0][0], isA<double>());
      expect(result[0][1], isA<double>());
    });

    test('verarbeitet München-Koordinaten korrekt', () {
      final geometry = {
        'coordinates': [
          [11.5820, 48.1351],
          [11.5833, 48.1369],
          [11.5847, 48.1382],
        ],
      };
      final result = service.extractCoordinates(geometry);
      expect(result.length, 3);
      expect(result[0][0], closeTo(11.5820, 0.0001));
      expect(result[0][1], closeTo(48.1351, 0.0001));
    });

    test('verarbeitet sehr viele Koordinaten ohne Absturz', () {
      final coords = List.generate(
        5000,
        (i) => [10.0 + i * 0.0001, 48.0 + i * 0.0001],
      );
      final geometry = {'coordinates': coords};
      final result = service.extractCoordinates(geometry);
      expect(result.length, 5000);
    });
  });
}
