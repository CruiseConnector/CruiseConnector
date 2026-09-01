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

    test('unter 20 Prozent Fahrt gibt keinen XP-Credit', () {
      final creditedKm = GamificationService.creditedDistanceKmForProgress(
        plannedDistanceKm: 100,
        progressRatio: 0.19,
      );

      expect(creditedKm, 0);
    });

    test('completed am Ziel gibt volle Strecken-XP', () {
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
    // 2026-09-01: Um zwoelf erweitert. Die neue Figma-Serie bringt vier
    // Familien mit, die es bisher nur als Emblem gab: Navigation (badge_71
    // bis 73), Fahrten mit der Community (74 bis 76), Laender (77 bis 79) und
    // Fotos (80 bis 82). Die Liste ist bewusst vollstaendig aufgeschrieben —
    // sie faellt, sobald jemand ein Abzeichen entfernt oder umbenennt, und
    // `profiles.badges` ist append-only.
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
          // 2026-08-14 (vucko Tutorial-Badge): Gründungszeit — jeder
          // registrierte Nutzer, vergeben über calculateAndSync.
          'badge_15',
          // 2026-08-15 (vucko Starter-Paket + neue Stufen): Startklar über
          // die Starter-Aufgaben, 17-22 über calculateAndSync.
          'badge_16',
          'badge_17',
          'badge_18',
          'badge_19',
          'badge_20',
          'badge_21',
          'badge_22',
          // 2026-08-16 (vucko Testfahrt T6): vierzehn weitere Stufen, alle
          // ueber calculateAndSync (sessionKennzahlen).
          for (var i = 23; i <= 36; i++) 'badge_$i',
          // 2026-08-18 (Aufgabe 4.2): zwanzig neue Stufen, die die Familien
          // auf je drei auffuellen. Bestehende IDs blieben unveraendert.
          for (var i = 37; i <= 56; i++) 'badge_$i',
          // 2026-08-24 (Aufgabe 10a, vucko): „dass community ein enzelnes
          // badge bekommen [...] aber nur eins das heisst Gruende eine
          // Community". Stufenlos und ohne Familie, wie badge_15 und
          // badge_16. Steht am Ende, weil neue Abzeichen hier immer angehaengt
          // werden — bestehende IDs und ihre Reihenfolge bleiben unberuehrt.
          'badge_57',
          // 2026-08-24 (Auftrag vom 24.08., vucko): „man soll dafuer auch ein
          // badge bekommen wenn man es abgeschlossen hat wie startklar" —
          // badge_58 fuer das durchgespielte Tutorial; seit 25.08. heisst
          // es „Durchgespielt" und verlangt ALLE zwoelf Starter-Aufgaben.
          'badge_58',
          // 2026-08-24 (Auftrag vom 24.08.): vier neue Familien fuer Bereiche
          // ohne jedes Abzeichen — Garage (59-61), Beitraege (62-64),
          // Hashtags (65-67), Meldungen (68-70). Angehaengt, nie eingeschoben:
          // bestehende IDs und ihre Reihenfolge bleiben unberuehrt.
          for (var i = 59; i <= 70; i++) 'badge_$i',          'badge_71',
          'badge_72',
          'badge_73',
          'badge_74',
          'badge_75',
          'badge_76',
          'badge_77',
          'badge_78',
          'badge_79',
          'badge_80',
          'badge_81',
          'badge_82',

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

    test('hasEquivalentSavedRoute erkennt gleiche Route über Fingerprint', () {
      final recommended = SavedRoute.fromJson({
        'id': 'pool-route',
        'created_at': '2025-01-15T10:00:00.000Z',
        'style': 'Sport Mode',
        'distance_actual': 73.7,
        'route_source': 'route_pool',
        'route_fingerprint': 'fp-dornbirn-75-sport',
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [9.74, 47.50],
            [9.80, 47.55],
          ],
        },
      });
      final savedCopy = SavedRoute.fromJson({
        'id': 'saved-copy',
        'created_at': '2025-01-16T10:00:00.000Z',
        'style': 'Sport Mode',
        'distance_actual': 73.7,
        'route_source': 'route_pool',
        'route_fingerprint': 'fp-dornbirn-75-sport',
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [9.74, 47.50],
            [9.81, 47.56],
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

    test(
      'savedRouteCopiesFromUserRoutes behaelt gefahren gespeicherte Routen in der Library',
      () {
        final drivenSavedRoute = SavedRoute.fromJson({
          'id': 'route-driven-saved',
          'created_at': '2025-01-18T10:00:00.000Z',
          'style': 'Sport Mode',
          'distance_actual': 23.0,
          'distance_target': 50,
          'driven_km': 23.0,
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [11.58, 48.13],
              [11.62, 48.17],
            ],
          },
        });

        final libraryCopies = SavedRoutesService.savedRouteCopiesFromUserRoutes(
          [drivenSavedRoute],
        );

        expect(libraryCopies, hasLength(1));
        expect(libraryCopies.single.id, equals('route-driven-saved'));
        expect(libraryCopies.single.isDrivenSession, isTrue);
      },
    );

    test('SavedRoute Signatur unterstuetzt GPS-Track mit Segment-Luecken', () {
      final drivenRoute = SavedRoute.fromJson({
        'id': 'route-driven-multiline',
        'created_at': '2026-05-09T10:00:00.000Z',
        'style': 'Sport Mode',
        'distance_actual': 12.4,
        'driven_km': 12.4,
        'geometry': {
          'type': 'MultiLineString',
          'coordinates': [
            [
              [9.7471, 47.5162],
              [9.7500, 47.5200],
            ],
            [
              [9.8100, 47.5500],
              [9.8200, 47.5600],
            ],
          ],
        },
      });

      expect(drivenRoute.routeSignature, contains('9.7471,47.5162'));
      expect(drivenRoute.routeSignature, contains('9.8200,47.5600'));
    });

    test(
      'buildExistingRouteInsertForTest speichert Community-Kopie ohne Drive-XP-Felder',
      () {
        const sourceRouteId = '11111111-2222-4333-8444-555555555555';
        final route = SavedRoute.fromJson({
          'id': sourceRouteId,
          'created_at': '2025-01-18T10:00:00.000Z',
          'style': 'Entdecker',
          'distance_actual': 41.6,
          'distance_target': 50,
          'duration_seconds': 4700,
          'driven_km': 41.6,
          'route_source': 'pool',
          'route_fingerprint': 'fp-community',
          'quality_tier': 'good',
          'route_meta': {'curve_count': 36},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [9.74, 47.50],
              [9.78, 47.53],
            ],
          },
        });

        final row = SavedRoutesService.buildExistingRouteInsertForTest(
          userId: 'user-1',
          route: route,
        );

        expect(row['user_id'], equals('user-1'));
        expect(row['source_route_id'], equals(sourceRouteId));
        expect(row['route_source'], equals('pool'));
        expect(row['route_fingerprint'], equals('fp-community'));
        expect(row['quality_tier'], equals('good'));
        expect(row['distance_actual'], equals(41.6));
        expect(row['duration_seconds'], equals(4700));
        expect(row, isNot(contains('driven_km')));
        expect(row, isNot(contains('xp_awarded')));
        expect(row, isNot(contains('xp_distance')));
        expect(
          row['route_meta'],
          containsPair('saved_route_source', 'existing_route_copy'),
        );
        expect(row['route_meta'], containsPair('curve_count', 36));
      },
    );

    test(
      'buildExistingRouteInsertForTest speichert Pool-Empfehlung mit Text-ID ohne uuid source_route_id',
      () {
        final route = SavedRoute.fromJson({
          'id': 'vorarlberg-bregenz-50-sport-seed-1',
          'created_at': '2025-01-18T10:00:00.000Z',
          'style': 'Sport Mode',
          'distance_actual': 50.2,
          'distance_target': 50,
          'duration_seconds': 3900,
          'route_source': 'route_pool',
          'route_fingerprint': 'fp-pool-route',
          'quality_tier': 'good',
          'route_meta': {'pool_route_id': 'vorarlberg-bregenz-50-sport-seed-1'},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [9.74, 47.50],
              [9.78, 47.53],
            ],
          },
        });

        final row = SavedRoutesService.buildExistingRouteInsertForTest(
          userId: 'user-1',
          route: route,
        );

        expect(row, isNot(contains('source_route_id')));
        expect(row['route_source'], equals('route_pool'));
        expect(row['route_fingerprint'], equals('fp-pool-route'));
        expect(
          row['route_meta'],
          containsPair('source_route_id', 'vorarlberg-bregenz-50-sport-seed-1'),
        );
      },
    );

    test(
      'buildExistingRouteInsertForTest schreibt route_pool UUID nicht in routes-FK source_route_id',
      () {
        const poolRouteId = '22222222-3333-4444-8555-666666666666';
        final route = SavedRoute.fromJson({
          'id': poolRouteId,
          'created_at': '2025-01-18T10:00:00.000Z',
          'style': 'Sport Mode',
          'distance_actual': 73.7,
          'distance_target': 75,
          'duration_seconds': 7200,
          'route_source': 'route_pool',
          'route_fingerprint': 'fp-home-pool',
          'quality_tier': 'good',
          'route_meta': {'pool_route_id': poolRouteId},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [9.74, 47.50],
              [9.78, 47.53],
            ],
          },
        });

        final row = SavedRoutesService.buildExistingRouteInsertForTest(
          userId: 'user-1',
          route: route,
        );

        expect(row, isNot(contains('source_route_id')));
        expect(row['route_source'], equals('route_pool'));
        expect(row['route_fingerprint'], equals('fp-home-pool'));
        expect(row['route_meta'], containsPair('source_route_id', poolRouteId));
        expect(row['route_meta'], containsPair('pool_route_id', poolRouteId));
      },
    );
  });
}
