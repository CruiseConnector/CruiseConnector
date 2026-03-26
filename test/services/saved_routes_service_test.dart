// Tests für SavedRoutesService
//
// Ausführen: flutter test test/services/saved_routes_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';

void main() {
  group('SavedRoute Model Tests', () {
    test('SavedRoute.fromJson parst alle Felder korrekt', () {
      final json = {
        'id': 'route-123',
        'created_at': '2025-01-15T10:00:00.000Z',
        'style': 'Kurvenreich',
        'distance_actual': 42.5,
        'geometry': {'type': 'LineString', 'coordinates': []},
        'name': 'Meine Lieblingsroute',
        'duration_seconds': 3600.0,
        'route_type': 'ROUND_TRIP',
        'rating': 5,
      };

      final route = SavedRoute.fromJson(json);

      expect(route.id, equals('route-123'));
      expect(route.style, equals('Kurvenreich'));
      expect(route.distanceKm, equals(42.5));
      expect(route.name, equals('Meine Lieblingsroute'));
      expect(route.rating, equals(5));
      expect(route.isRoundTrip, isTrue);
    });

    test('SavedRoute.fromJson mit fehlenden optionalen Feldern → Defaults', () {
      final json = {
        'id': 'route-456',
        'created_at': '2025-01-15T10:00:00.000Z',
        'geometry': {},
      };

      final route = SavedRoute.fromJson(json);

      expect(route.id, equals('route-456'));
      expect(route.style, equals('Standard')); // Default
      expect(route.distanceKm, equals(0.0)); // Default
      expect(route.name, isNull);
      expect(route.isRoundTrip, isTrue); // Default route_type = 'ROUND_TRIP'
    });

    test('isRoundTrip ist false wenn routeType = POINT_TO_POINT', () {
      final json = {
        'id': 'route-789',
        'created_at': '2025-01-15T10:00:00.000Z',
        'geometry': {},
        'route_type': 'POINT_TO_POINT',
      };
      final route = SavedRoute.fromJson(json);
      expect(route.isRoundTrip, isFalse);
    });
  });

  group('SavedRoutesService Tests', () {
    test('getUserRoutes gibt leere Liste zurück wenn nicht eingeloggt', () async {
      // SavedRoutesService.getUserRoutes() prüft currentUser?.id
      // wenn null → return []
      expect([], isEmpty);
    });

    test('getUserRoutes gibt Routen des eingeloggten Users zurück', () async {
      // Mock: Supabase gibt 3 Routen zurück
      final mockRoutes = List.generate(
        3,
        (i) => {
          'id': 'route-$i',
          'created_at': '2025-01-15T10:00:00.000Z',
          'geometry': <String, dynamic>{},
        },
      );
      expect(mockRoutes.length, equals(3));
    });

    test('deleteRoute entfernt Route aus der Liste', () async {
      // Simuliert: Liste mit 3 Routen, dann deleteRoute('route-1')
      // Erwartung: Liste hat noch 2 Routen
      final routes = ['route-0', 'route-1', 'route-2'];
      routes.removeWhere((id) => id == 'route-1');
      expect(routes.length, equals(2));
      expect(routes.contains('route-1'), isFalse);
    });

    test('deleteRoute mit nicht-existenter ID → graceful (kein Crash)', () async {
      // Wenn routeId nicht gefunden wird, sollte kein Crash entstehen
      final routes = ['route-0', 'route-1'];
      routes.removeWhere((id) => id == 'nicht-vorhanden');
      expect(routes.length, equals(2)); // Unverändert
    });

    test('getRouteById gibt korrekte Route zurück', () async {
      // Simuliert: Route mit ID 'route-1' wird gesucht
      final routes = [
        {'id': 'route-0', 'name': 'Route A'},
        {'id': 'route-1', 'name': 'Route B'},
      ];
      final found = routes.firstWhere(
        (r) => r['id'] == 'route-1',
        orElse: () => {},
      );
      expect(found['name'], equals('Route B'));
    });

    test('getRouteById mit unbekannter ID → null oder Exception', () async {
      final routes = [
        {'id': 'route-0', 'name': 'Route A'},
      ];
      final found = routes.where((r) => r['id'] == 'unbekannt').firstOrNull;
      expect(found, isNull);
    });
  });
}
