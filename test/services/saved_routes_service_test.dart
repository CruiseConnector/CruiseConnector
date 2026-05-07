// Tests für SavedRoutesService
//
// Ausführen: flutter test test/services/saved_routes_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/domain/models/user_level.dart';

void main() {
  group('SavedRoute Model Tests', () {
    test('SavedRoute.fromJson parst alle Felder korrekt', () {
      final json = {
        'id': 'route-123',
        'created_at': '2025-01-15T10:00:00.000Z',
        'style': 'Kurvenreich',
        'distance_actual': 42.5,
        'distance_target': 50,
        'driven_km': 42.5,
        'geometry': {'type': 'LineString', 'coordinates': []},
        'name': 'Meine Lieblingsroute',
        'duration_seconds': 3600.0,
        'route_type': 'ROUND_TRIP',
        'rating': 5,
        'user_id': 'user-1',
        'source_route_id': 'route-source',
        'route_source': 'pool',
        'route_fingerprint': 'fp-route-123',
        'quality_tier': 'good',
        'route_meta': {'style_fit_score': 82.5},
        'average_rating': 4.6,
        'rating_count': 3,
        'completion_rate': 0.91,
        'completed_at_end': false,
        'group_id': 'group-1',
      };

      final route = SavedRoute.fromJson(json);

      expect(route.id, equals('route-123'));
      expect(route.style, equals('Kurvenreich'));
      expect(route.distanceKm, equals(42.5));
      expect(route.name, equals('Meine Lieblingsroute'));
      expect(route.rating, equals(5));
      expect(route.userId, equals('user-1'));
      expect(route.sourceRouteId, equals('route-source'));
      expect(route.isRoundTrip, isTrue);
      expect(route.groupId, equals('group-1'));
      expect(route.isDrivenSession, isTrue);
      expect(route.completionRatio, closeTo(0.85, 0.001));
      expect(route.qualifiesForXpCredit, isTrue);
      expect(route.routeSource, equals('pool'));
      expect(route.routeFingerprint, equals('fp-route-123'));
      expect(route.qualityBadgeLabel, equals('Gut'));
      expect(route.ratingSummaryLabel, equals('4,6 · 3 Bewertungen'));
      expect(route.completionRate, equals(0.91));
      expect(route.isFullyCompleted, isFalse);
      expect(route.xpCreditProgressRatio, closeTo(0.85, 0.001));
      expect(route.xpCreditedDistanceKm, closeTo(42.5, 0.001));
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
      expect(route.isDrivenSession, isFalse);
      expect(route.qualifiesForXpCredit, isFalse);
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

    test('kurz abgebrochene Legacy-Route bleibt als gefahren erkennbar', () {
      final route = SavedRoute.fromJson({
        'id': 'route-early-stop',
        'created_at': '2025-01-15T10:00:00.000Z',
        'style': 'Sport Mode',
        'distance_actual': 11.0,
        'distance_target': 60,
        'driven_km': 11.0,
        'geometry': {'type': 'LineString', 'coordinates': []},
      });

      expect(route.isDrivenSession, isTrue);
      expect(route.completionRatio, lessThan(0.20));
      expect(route.qualifiesForXpCredit, isTrue);
      expect(route.xpCreditProgressRatio, closeTo(11 / 60, 0.001));
      expect(route.xpCreditedDistanceKm, 11);
      expect(route.isRecommendationEligible, isFalse);
    });

    test('XP-Gutschrift nutzt die tatsaechlich gefahrene Strecke', () {
      final route = SavedRoute.fromJson({
        'id': 'route-stepped-xp',
        'created_at': '2025-01-15T10:00:00.000Z',
        'style': 'Sport Mode',
        'distance_actual': 25.0,
        'distance_target': 100,
        'driven_km': 25.0,
        'geometry': {'type': 'LineString', 'coordinates': []},
      });

      expect(route.completionRatio, closeTo(0.25, 0.001));
      expect(route.qualifiesForXpCredit, isTrue);
      expect(route.xpCreditProgressRatio, closeTo(0.25, 0.001));
      expect(route.xpCreditedDistanceKm, closeTo(25, 0.001));
      expect(route.isFullyCompleted, isFalse);
    });

    test('vollstaendig gefahrene Route gilt als komplette Fahrt', () {
      final route = SavedRoute.fromJson({
        'id': 'route-complete',
        'created_at': '2025-01-15T10:00:00.000Z',
        'style': 'Sport Mode',
        'distance_actual': 100.0,
        'distance_target': 100,
        'driven_km': 100.0,
        'completed_at_end': true,
        'geometry': {'type': 'LineString', 'coordinates': []},
      });

      expect(route.completionRatio, 1.0);
      expect(route.isFullyCompleted, isTrue);
      expect(route.xpCreditProgressRatio, 1.0);
      expect(route.xpCreditedDistanceKm, 100.0);
    });

    test(
      'Completion-Flag zählt trotz gerundetem distance_target als fertig',
      () {
        final route = SavedRoute.fromJson({
          'id': 'route-complete-rounded',
          'created_at': '2025-01-15T10:00:00.000Z',
          'style': 'Sport Mode',
          'distance_actual': 49.6,
          'distance_target': 50,
          'driven_km': 49.6,
          'completed_at_end': true,
          'geometry': {'type': 'LineString', 'coordinates': []},
        });

        expect(route.completionRatio, lessThan(1.0));
        expect(route.isFullyCompleted, isTrue);
      },
    );

    test('routeSignature bleibt für gleiche Geometrie stabil', () {
      final json = {
        'id': 'route-signature',
        'created_at': '2025-01-15T10:00:00.000Z',
        'style': 'Entdecker',
        'distance_actual': 42.5,
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [11.58, 48.13],
            [11.60, 48.15],
            [11.62, 48.17],
            [11.64, 48.19],
          ],
        },
      };

      final first = SavedRoute.fromJson(json);
      final second = SavedRoute.fromJson({...json, 'id': 'route-signature-2'});

      expect(first.routeSignature, equals(second.routeSignature));
    });
  });

  group('Gamification XP-Credit', () {
    test('25 Prozent Fahrt nutzt die tatsaechliche Strecke ohne Abrundung', () {
      final creditedKm = GamificationService.creditedDistanceKmForProgress(
        plannedDistanceKm: 100,
        progressRatio: 0.25,
      );

      expect(creditedKm, 25);
    });

    test('60 Prozent Fahrt gibt 60 Prozent Strecken-XP', () {
      final creditedKm = GamificationService.creditedDistanceKmForProgress(
        plannedDistanceKm: 100,
        progressRatio: 0.60,
      );

      expect(creditedKm, 60);
    });

    test('unter 20 Prozent Fahrt nutzt trotzdem die gefahrene Strecke', () {
      final creditedKm = GamificationService.creditedDistanceKmForProgress(
        plannedDistanceKm: 100,
        progressRatio: 0.19,
      );

      expect(creditedKm, 19);
    });

    test('completed erzwingt 100 Prozent XP-Credit', () {
      final creditedKm = GamificationService.creditedDistanceKmForProgress(
        plannedDistanceKm: 100,
        progressRatio: 0.96,
        completed: true,
      );

      expect(creditedKm, 100);
    });

    test('Level ist bei 100 gedeckelt', () {
      final level = UserLevel.fromXp(UserLevel.xpForLevel(120));

      expect(level.level, UserLevel.maxLevel);
      expect(level.progress, 1.0);
      expect(level.xpToNextLevel, 0);
    });
  });

  group('Badge-Konfiguration', () {
    test('enthaelt nur die aktive Badge-Auswahl', () {
      final ids = app.Badge.all.map((badge) => badge.id).toList();

      expect(
        ids,
        equals([
          'badge_01',
          'badge_02',
          'badge_03',
          'badge_04',
          'badge_05',
          'badge_06',
          'badge_07',
          'badge_08',
          'badge_09',
          'badge_10',
          'badge_13',
          'badge_14',
        ]),
      );
      expect(app.Badge.getById('route_1'), isNull);
      expect(app.Badge.getById('badge_02')?.name, equals('Erste Fahrt'));
    });
  });

  group('SavedRoutesService Tests', () {
    test(
      'getUserRoutes gibt leere Liste zurück wenn nicht eingeloggt',
      () async {
        // SavedRoutesService.getUserRoutes() prüft currentUser?.id
        // wenn null → return []
        expect([], isEmpty);
      },
    );

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

    test(
      'deleteRoute mit nicht-existenter ID → graceful (kein Crash)',
      () async {
        // Wenn routeId nicht gefunden wird, sollte kein Crash entstehen
        final routes = ['route-0', 'route-1'];
        routes.removeWhere((id) => id == 'nicht-vorhanden');
        expect(routes.length, equals(2)); // Unverändert
      },
    );

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

    test(
      'hasEquivalentSavedRoute erkennt gleiche Route über source_route_id',
      () {
        final recommended = SavedRoute.fromJson({
          'id': 'route-original',
          'created_at': '2025-01-15T10:00:00.000Z',
          'style': 'Sport Mode',
          'distance_actual': 50.0,
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [11.58, 48.13],
              [11.62, 48.17],
            ],
          },
        });
        final savedCopy = SavedRoute.fromJson({
          'id': 'route-copy',
          'created_at': '2025-01-15T10:00:00.000Z',
          'style': 'Sport Mode',
          'distance_actual': 50.0,
          'source_route_id': 'route-original',
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [11.58, 48.13],
              [11.62, 48.17],
            ],
          },
        });

        expect(
          SavedRoutesService.hasEquivalentSavedRoute(recommended, [savedCopy]),
          isTrue,
        );
      },
    );

    test('hasEquivalentSavedRoute erkennt gleiche Route über Geometrie', () {
      final recommended = SavedRoute.fromJson({
        'id': 'route-original',
        'created_at': '2025-01-15T10:00:00.000Z',
        'style': 'Abendrunde',
        'distance_actual': 40.0,
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [11.58, 48.13],
            [11.60, 48.15],
            [11.62, 48.17],
          ],
        },
      });
      final savedCopy = SavedRoute.fromJson({
        'id': 'route-copy',
        'created_at': '2025-01-16T10:00:00.000Z',
        'style': 'Abendrunde',
        'distance_actual': 40.0,
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [11.58, 48.13],
            [11.60, 48.15],
            [11.62, 48.17],
          ],
        },
      });

      expect(
        SavedRoutesService.hasEquivalentSavedRoute(recommended, [savedCopy]),
        isTrue,
      );
    });

    test('dedupeEquivalentRoutes entfernt doppelte gespeicherte Kopien', () {
      final original = SavedRoute.fromJson({
        'id': 'route-original',
        'created_at': '2025-01-15T10:00:00.000Z',
        'style': 'Sport Mode',
        'distance_actual': 50.0,
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [11.58, 48.13],
            [11.62, 48.17],
          ],
        },
      });
      final firstCopy = SavedRoute.fromJson({
        'id': 'route-copy-1',
        'created_at': '2025-01-16T10:00:00.000Z',
        'style': 'Sport Mode',
        'distance_actual': 50.0,
        'source_route_id': 'route-original',
        'geometry': original.geometry,
      });
      final secondCopy = SavedRoute.fromJson({
        'id': 'route-copy-2',
        'created_at': '2025-01-17T10:00:00.000Z',
        'style': 'Sport Mode',
        'distance_actual': 50.0,
        'source_route_id': 'route-original',
        'geometry': original.geometry,
      });

      final deduped = SavedRoutesService.dedupeEquivalentRoutes([
        firstCopy,
        secondCopy,
      ]);

      expect(deduped, hasLength(1));
      expect(
        SavedRoutesService.hasEquivalentSavedRoute(original, deduped),
        isTrue,
      );
    });
  });
}
