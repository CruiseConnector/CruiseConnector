import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/route_pool_service.dart';
import 'package:cruise_connect/domain/models/route_pool_candidate.dart';
import 'package:cruise_connect/domain/models/route_pool_coverage.dart';
import 'package:cruise_connect/domain/models/route_pool_entry.dart';
import 'package:cruise_connect/domain/models/route_region.dart';
import 'package:cruise_connect/domain/models/route_seed_job.dart';

void main() {
  group('RoutePoolService DACH matching', () {
    test('DE/Bayern: Muenchen bekommt keine Nuernberg-Route ueber 30 km', () {
      final match = RoutePoolService.findBestMatch(
        query: const RoutePoolQuery(
          userLat: 48.1372,
          userLng: 11.5755,
          countryCode: 'DE',
          admin1Name: 'Bayern',
          cityCluster: 'München',
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
        ),
        regions: [
          _region(
            countryCode: 'DE',
            admin1Name: 'Bayern',
            cityCluster: 'Nürnberg',
            centerLat: 49.4521,
            centerLng: 11.0767,
          ),
        ],
        candidates: [
          _route(
            id: 'nuernberg-far',
            countryCode: 'DE',
            admin1Name: 'Bayern',
            cityCluster: 'Nürnberg',
            startLat: 49.4521,
            startLng: 11.0767,
          ),
        ],
      );

      expect(match, isNull);
    });

    test(
      'DE/Baden-Wuerttemberg: Konstanz gewinnt vor Stuttgart, wenn lokal vorhanden',
      () {
        final match = RoutePoolService.findBestMatch(
          query: const RoutePoolQuery(
            userLat: 47.6779,
            userLng: 9.1732,
            countryCode: 'DE',
            admin1Name: 'Baden-Württemberg',
            cityCluster: 'Konstanz',
            distanceBucket: 50,
            style: 'Kurvenjagd',
            avoidHighways: true,
          ),
          regions: [
            _region(
              countryCode: 'DE',
              admin1Name: 'Baden-Württemberg',
              cityCluster: 'Konstanz',
              centerLat: 47.6779,
              centerLng: 9.1732,
            ),
            _region(
              countryCode: 'DE',
              admin1Name: 'Baden-Württemberg',
              cityCluster: 'Stuttgart',
              centerLat: 48.7758,
              centerLng: 9.1829,
            ),
          ],
          candidates: [
            _route(
              id: 'stuttgart-high-score',
              countryCode: 'DE',
              admin1Name: 'Baden-Württemberg',
              cityCluster: 'Stuttgart',
              startLat: 48.7758,
              startLng: 9.1829,
              styleTags: const ['Kurvenjagd'],
              qualityScore: 100,
            ),
            _route(
              id: 'konstanz-local',
              countryCode: 'DE',
              admin1Name: 'Baden-Württemberg',
              cityCluster: 'Konstanz',
              startLat: 47.6790,
              startLng: 9.1750,
              styleTags: const ['Kurvenjagd'],
              qualityScore: 70,
            ),
          ],
        );

        expect(match?.route.id, 'konstanz-local');
        expect(match?.radiusScope, 'local_cluster');
      },
    );

    test('CH/Zuerich: Zuerich-Route gewinnt vor St. Gallen-Route', () {
      final match = RoutePoolService.findBestMatch(
        query: const RoutePoolQuery(
          userLat: 47.3769,
          userLng: 8.5417,
          countryCode: 'CH',
          admin1Name: 'Zürich',
          cityCluster: 'Zürich',
          distanceBucket: 75,
          style: 'Entdecker',
          avoidHighways: false,
        ),
        regions: [
          _region(
            countryCode: 'CH',
            admin1Name: 'Zürich',
            cityCluster: 'Zürich',
            centerLat: 47.3769,
            centerLng: 8.5417,
          ),
          _region(
            countryCode: 'CH',
            admin1Name: 'St. Gallen',
            cityCluster: 'St. Gallen',
            centerLat: 47.4245,
            centerLng: 9.3767,
          ),
        ],
        candidates: [
          _route(
            id: 'st-gallen',
            countryCode: 'CH',
            admin1Name: 'St. Gallen',
            cityCluster: 'St. Gallen',
            startLat: 47.4245,
            startLng: 9.3767,
            distanceBucket: 75,
            styleTags: const ['Entdecker'],
            avoidsHighway: false,
            hasHighway: true,
            qualityScore: 100,
          ),
          _route(
            id: 'zuerich-local',
            countryCode: 'CH',
            admin1Name: 'Zürich',
            cityCluster: 'Zürich',
            startLat: 47.3770,
            startLng: 8.5420,
            distanceBucket: 75,
            styleTags: const ['Entdecker'],
            avoidsHighway: false,
            hasHighway: false,
            qualityScore: 70,
          ),
        ],
      );

      expect(match?.route.id, 'zuerich-local');
    });

    test(
      'CH/St. Gallen: Sargans bekommt keine Zuerich-Route, wenn nahe Route existiert',
      () {
        final match = RoutePoolService.findBestMatch(
          query: const RoutePoolQuery(
            userLat: 47.0483,
            userLng: 9.4410,
            countryCode: 'CH',
            admin1Name: 'St. Gallen',
            cityCluster: 'Sargans',
            admin2Name: 'Sarganserland',
            distanceBucket: 50,
            style: 'Abendrunde',
            avoidHighways: true,
          ),
          regions: [
            _region(
              countryCode: 'CH',
              admin1Name: 'St. Gallen',
              admin2Name: 'Sarganserland',
              cityCluster: 'Sargans',
              centerLat: 47.0483,
              centerLng: 9.4410,
            ),
            _region(
              countryCode: 'CH',
              admin1Name: 'Zürich',
              cityCluster: 'Zürich',
              centerLat: 47.3769,
              centerLng: 8.5417,
            ),
          ],
          candidates: [
            _route(
              id: 'zuerich-far',
              countryCode: 'CH',
              admin1Name: 'Zürich',
              cityCluster: 'Zürich',
              startLat: 47.3769,
              startLng: 8.5417,
              styleTags: const ['Abendrunde'],
              qualityScore: 100,
            ),
            _route(
              id: 'sargans-local',
              countryCode: 'CH',
              admin1Name: 'St. Gallen',
              admin2Name: 'Sarganserland',
              cityCluster: 'Sargans',
              startLat: 47.0500,
              startLng: 9.4450,
              styleTags: const ['Abendrunde'],
              qualityScore: 75,
            ),
          ],
        );

        expect(match?.route.id, 'sargans-local');
      },
    );

    test('AT/Tirol: Innsbruck bekommt lokale Route vor Kufstein', () {
      final match = RoutePoolService.findBestMatch(
        query: const RoutePoolQuery(
          userLat: 47.2692,
          userLng: 11.4041,
          countryCode: 'AT',
          admin1Name: 'Tirol',
          cityCluster: 'Innsbruck',
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: false,
        ),
        regions: [
          _region(
            countryCode: 'AT',
            admin1Name: 'Tirol',
            cityCluster: 'Innsbruck',
            centerLat: 47.2692,
            centerLng: 11.4041,
          ),
          _region(
            countryCode: 'AT',
            admin1Name: 'Tirol',
            cityCluster: 'Kufstein',
            centerLat: 47.5837,
            centerLng: 12.1691,
          ),
        ],
        candidates: [
          _route(
            id: 'kufstein-high-score',
            countryCode: 'AT',
            admin1Name: 'Tirol',
            cityCluster: 'Kufstein',
            startLat: 47.5837,
            startLng: 12.1691,
            avoidsHighway: false,
            hasHighway: true,
            qualityScore: 100,
          ),
          _route(
            id: 'innsbruck-local',
            countryCode: 'AT',
            admin1Name: 'Tirol',
            cityCluster: 'Innsbruck',
            startLat: 47.2700,
            startLng: 11.4050,
            avoidsHighway: false,
            hasHighway: false,
            qualityScore: 70,
          ),
        ],
      );

      expect(match?.route.id, 'innsbruck-local');
    });

    test('Grenznah: Bregenz bekommt ohne Cross-Border keine CH/DE Route', () {
      final match = RoutePoolService.findBestMatch(
        query: const RoutePoolQuery(
          userLat: 47.5031,
          userLng: 9.7471,
          countryCode: 'AT',
          admin1Name: 'Vorarlberg',
          cityCluster: 'Bregenz',
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
        ),
        regions: [
          _region(
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            cityCluster: 'Bregenz',
            centerLat: 47.5031,
            centerLng: 9.7471,
          ),
        ],
        candidates: [
          _route(
            id: 'lindau-de',
            countryCode: 'DE',
            admin1Name: 'Bayern',
            cityCluster: 'Lindau',
            startLat: 47.5460,
            startLng: 9.6840,
          ),
          _route(
            id: 'st-gallen-ch',
            countryCode: 'CH',
            admin1Name: 'St. Gallen',
            cityCluster: 'St. Gallen',
            startLat: 47.4245,
            startLng: 9.3767,
          ),
        ],
      );

      expect(match, isNull);
    });

    test('Duenne Regionen duerfen regional bis maximal 45 km erweitern', () {
      final match = RoutePoolService.findBestMatch(
        query: const RoutePoolQuery(
          userLat: 47.2692,
          userLng: 11.4041,
          countryCode: 'AT',
          admin1Name: 'Tirol',
          cityCluster: 'Innsbruck',
          distanceBucket: 100,
          style: 'Entdecker',
          avoidHighways: true,
          routeType: 'POINT_TO_POINT',
        ),
        regions: [
          _region(
            countryCode: 'AT',
            admin1Name: 'Tirol',
            cityCluster: 'Landeck',
            centerLat: 47.1399,
            centerLng: 10.5659,
            fallbackRadiusKm: 45,
          ),
        ],
        candidates: [
          _route(
            id: 'regional-extended',
            countryCode: 'AT',
            admin1Name: 'Tirol',
            cityCluster: 'Landeck',
            startLat: 47.2100,
            startLng: 10.9000,
            distanceBucket: 100,
            routeType: 'POINT_TO_POINT',
            styleTags: const ['Entdecker'],
          ),
        ],
      );

      expect(match?.route.id, 'regional-extended');
      expect(match?.allowedRadiusKm, 45);
    });

    test('Autobahn AUS verwirft Pool-Routen mit Autobahnanteil', () {
      final match = RoutePoolService.findBestMatch(
        query: const RoutePoolQuery(
          userLat: 48.1372,
          userLng: 11.5755,
          countryCode: 'DE',
          admin1Name: 'Bayern',
          cityCluster: 'München',
          distanceBucket: 75,
          style: 'Sport Mode',
          avoidHighways: true,
        ),
        regions: [
          _region(
            countryCode: 'DE',
            admin1Name: 'Bayern',
            cityCluster: 'München',
            centerLat: 48.1372,
            centerLng: 11.5755,
          ),
        ],
        candidates: [
          _route(
            id: 'motorway-route',
            countryCode: 'DE',
            admin1Name: 'Bayern',
            cityCluster: 'München',
            startLat: 48.1375,
            startLng: 11.5760,
            distanceBucket: 75,
            avoidsHighway: false,
            hasHighway: true,
            qualityScore: 100,
          ),
        ],
      );

      expect(match, isNull);
    });

    test('Distance-Bucket muss exakt zum Suchbucket passen', () {
      final match = RoutePoolService.findBestMatch(
        query: const RoutePoolQuery(
          userLat: 48.1372,
          userLng: 11.5755,
          countryCode: 'DE',
          admin1Name: 'Bayern',
          cityCluster: 'München',
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
        ),
        regions: [
          _region(
            countryCode: 'DE',
            admin1Name: 'Bayern',
            cityCluster: 'München',
            centerLat: 48.1372,
            centerLng: 11.5755,
          ),
        ],
        candidates: [
          _route(
            id: 'wrong-75-bucket',
            countryCode: 'DE',
            admin1Name: 'Bayern',
            cityCluster: 'München',
            startLat: 48.1372,
            startLng: 11.5755,
            distanceBucket: 75,
          ),
        ],
      );

      expect(match, isNull);
    });

    test('150 km ist kein gueltiger Distance-Bucket mehr', () {
      final match = RoutePoolService.findBestMatch(
        query: const RoutePoolQuery(
          userLat: 47.4125,
          userLng: 9.7414,
          countryCode: 'AT',
          admin1Name: 'Vorarlberg',
          cityCluster: 'Dornbirn',
          distanceBucket: 150,
          style: 'Sport Mode',
          avoidHighways: true,
        ),
        regions: [
          _region(
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            cityCluster: 'Dornbirn',
            centerLat: 47.4125,
            centerLng: 9.7414,
          ),
        ],
        candidates: [
          _route(
            id: 'legacy-150',
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            cityCluster: 'Dornbirn',
            startLat: 47.4125,
            startLng: 9.7414,
            distanceBucket: 150,
          ),
        ],
      );

      expect(match, isNull);
    });

    test(
      'ROUND_TRIP: Goetzis bekommt keine Bregenz-Route ueber 10 km Startdistanz',
      () {
        final match = RoutePoolService.findBestMatch(
          query: const RoutePoolQuery(
            userLat: 47.3331,
            userLng: 9.6336,
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            cityCluster: 'Götzis',
            distanceBucket: 50,
            style: 'Kurvenjagd',
            avoidHighways: true,
            routeType: 'ROUND_TRIP',
          ),
          regions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Götzis',
              centerLat: 47.3331,
              centerLng: 9.6336,
            ),
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Bregenz',
              centerLat: 47.5031,
              centerLng: 9.7471,
            ),
          ],
          candidates: [
            _route(
              id: 'bregenz-too-far',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Bregenz',
              startLat: 47.5031,
              startLng: 9.7471,
              styleTags: const ['Kurvenjagd'],
            ),
          ],
        );

        expect(match, isNull);
      },
    );

    test(
      'ROUND_TRIP: Bregenz bekommt keine Bludenz-Route ueber 10 km Startdistanz',
      () {
        final match = RoutePoolService.findBestMatch(
          query: const RoutePoolQuery(
            userLat: 47.5031,
            userLng: 9.7471,
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            cityCluster: 'Bregenz',
            distanceBucket: 50,
            style: 'Sport Mode',
            avoidHighways: true,
            routeType: 'ROUND_TRIP',
          ),
          regions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Bregenz',
              centerLat: 47.5031,
              centerLng: 9.7471,
            ),
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Bludenz',
              centerLat: 47.1548,
              centerLng: 9.8220,
            ),
          ],
          candidates: [
            _route(
              id: 'bludenz-too-far',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Bludenz',
              startLat: 47.1548,
              startLng: 9.8220,
            ),
          ],
        );

        expect(match, isNull);
      },
    );

    test(
      'ROUND_TRIP: lokale Pool-Route innerhalb 5-10 km bleibt als nearby erlaubt',
      () {
        final match = RoutePoolService.findBestMatch(
          query: const RoutePoolQuery(
            userLat: 47.3331,
            userLng: 9.6336,
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            cityCluster: 'Götzis',
            distanceBucket: 50,
            style: 'Sport Mode',
            avoidHighways: true,
            routeType: 'ROUND_TRIP',
          ),
          regions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Götzis',
              centerLat: 47.3331,
              centerLng: 9.6336,
            ),
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Dornbirn',
              centerLat: 47.4125,
              centerLng: 9.7414,
            ),
          ],
          candidates: [
            _route(
              id: 'dornbirn-nearby',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Dornbirn',
              startLat: 47.3890,
              startLng: 9.6760,
            ),
          ],
        );

        expect(match?.route.id, 'dornbirn-nearby');
        expect(match?.startDistanceKm, lessThanOrEqualTo(10.0));
        expect(match?.radiusScope, isNot('too_far'));
      },
    );

    test(
      'ROUND_TRIP: falscher Style wird nicht als passende Zellroute verkauft',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Götzis',
              centerLat: 47.3331,
              centerLng: 9.6336,
            ),
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Feldkirch',
              centerLat: 47.2386,
              centerLng: 9.5986,
            ),
          ],
          inMemoryRoutes: [
            _route(
              id: 'feldkirch-100-sport',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Feldkirch',
              startLat: 47.3304,
              startLng: 9.6012,
              distanceBucket: 100,
              styleTags: const ['Sport Mode'],
            ),
            _route(
              id: 'feldkirch-50-abend',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Feldkirch',
              startLat: 47.3305,
              startLng: 9.6011,
              distanceBucket: 50,
              styleTags: const ['Abendrunde'],
            ),
          ],
        );

        final matches = await service.findCandidateRoutesNear(
          userLat: 47.3331,
          userLng: 9.6336,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
        );

        expect(matches, isEmpty);
      },
    );

    test(
      'ROUND_TRIP: legacy sport Style-Tag matcht Sport Mode exakt',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              centerLat: 47.2386,
              centerLng: 9.5986,
            ),
          ],
          inMemoryRoutes: [
            _route(
              id: 'feldkirch-50-legacy-sport',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              startLat: 47.2386,
              startLng: 9.5986,
              distanceBucket: 50,
              styleTags: const ['sport'],
            ),
          ],
        );

        final matches = await service.findCandidateRoutesNear(
          userLat: 47.2386,
          userLng: 9.5986,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
        );

        expect(matches.map((match) => match.route.id), [
          'feldkirch-50-legacy-sport',
        ]);
      },
    );

    test('ROUND_TRIP: Route-Type-Matching ist case-insensitive', () async {
      final service = RoutePoolService(
        inMemoryRegions: [
          _region(
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            admin2Name: 'Feldkirch',
            cityCluster: 'Feldkirch',
            centerLat: 47.2386,
            centerLng: 9.5986,
          ),
        ],
        inMemoryRoutes: [
          _route(
            id: 'feldkirch-50-sport-uppercase-type',
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            admin2Name: 'Feldkirch',
            cityCluster: 'Feldkirch',
            startLat: 47.2386,
            startLng: 9.5986,
            distanceBucket: 50,
            routeType: 'ROUND_TRIP',
            styleTags: const ['sport'],
          ),
        ],
      );

      final matches = await service.findCandidateRoutesNear(
        userLat: 47.2386,
        userLng: 9.5986,
        distanceBucket: 50,
        style: 'Sport Mode',
        avoidHighways: true,
        routeType: 'round_trip',
      );

      expect(matches.map((match) => match.route.id), [
        'feldkirch-50-sport-uppercase-type',
      ]);
    });

    test(
      'ROUND_TRIP: roundtrip/round_trip/Rundkurs matchen identisch',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              centerLat: 47.2386,
              centerLng: 9.5986,
            ),
          ],
          inMemoryRoutes: [
            _route(
              id: 'feldkirch-50-sport-roundtrip-alias',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              startLat: 47.2386,
              startLng: 9.5986,
              distanceBucket: 50,
              routeType: 'roundtrip',
              styleTags: const ['Sport Mode'],
            ),
          ],
        );

        final matches = await service.findCandidateRoutesNear(
          userLat: 47.2386,
          userLng: 9.5986,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'Rundkurs',
        );

        expect(matches.map((match) => match.route.id), [
          'feldkirch-50-sport-roundtrip-alias',
        ]);
      },
    );

    test('Goetzis Sport 50 Autobahn AN akzeptiert no-highway Route', () async {
      final service = RoutePoolService(
        inMemoryRegions: [
          _region(
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            admin2Name: 'Rheintal-Sued',
            cityCluster: 'Rheintal-Sued',
            centerLat: 47.3331,
            centerLng: 9.6336,
          ),
        ],
        inMemoryRoutes: [
          _route(
            id: 'goetzis-50-sport-no-highway',
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            admin2Name: 'Rheintal-Sued',
            cityCluster: 'Rheintal-Sued',
            startLat: 47.356,
            startLng: 9.65,
            distanceBucket: 50,
            styleTags: const ['Sport Mode'],
            avoidsHighway: true,
            hasHighway: false,
            qualityScore: 88,
          ),
        ],
      );

      final matches = await service.findCandidateRoutesNear(
        userLat: 47.3331,
        userLng: 9.6336,
        distanceBucket: 50,
        style: 'Sport Mode',
        avoidHighways: false,
        routeType: 'ROUND_TRIP',
      );

      expect(matches.map((match) => match.route.id), [
        'goetzis-50-sport-no-highway',
      ]);
    });

    test(
      'Goetzis Sport 50 Autobahn AUS gibt niemals has_highway true zurueck',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Rheintal-Sued',
              cityCluster: 'Rheintal-Sued',
              centerLat: 47.3331,
              centerLng: 9.6336,
            ),
          ],
          inMemoryRoutes: [
            _route(
              id: 'goetzis-50-sport-highway',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Rheintal-Sued',
              cityCluster: 'Rheintal-Sued',
              startLat: 47.3333,
              startLng: 9.6338,
              distanceBucket: 50,
              styleTags: const ['Sport Mode'],
              avoidsHighway: false,
              hasHighway: true,
              qualityScore: 99,
            ),
            _route(
              id: 'goetzis-50-sport-safe',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Rheintal-Sued',
              cityCluster: 'Rheintal-Sued',
              startLat: 47.334,
              startLng: 9.634,
              distanceBucket: 50,
              styleTags: const ['Sport Mode'],
              avoidsHighway: true,
              hasHighway: false,
              qualityScore: 88,
            ),
          ],
        );

        final matches = await service.findCandidateRoutesNear(
          userLat: 47.3331,
          userLng: 9.6336,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
        );

        expect(matches.map((match) => match.route.id), [
          'goetzis-50-sport-safe',
        ]);
      },
    );

    test(
      'Hohenems Kurvenjagd 75 nutzt nahe regionale Route bei leerem Stadtcluster',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Rheintal-Sued',
              cityCluster: 'Hohenems',
              centerLat: 47.3667,
              centerLng: 9.6831,
            ),
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Dornbirn',
              cityCluster: 'Dornbirn',
              centerLat: 47.4125,
              centerLng: 9.743,
            ),
          ],
          inMemoryRoutes: [
            _route(
              id: 'dornbirn-75-kurven-near-hohenems',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Dornbirn',
              cityCluster: 'Dornbirn',
              startLat: 47.4125,
              startLng: 9.743,
              distanceBucket: 75,
              styleTags: const ['Kurvenjagd'],
              avoidsHighway: true,
              hasHighway: false,
              qualityScore: 91,
            ),
          ],
        );

        final matches = await service.findCandidateRoutesNear(
          userLat: 47.3667,
          userLng: 9.6831,
          distanceBucket: 75,
          style: 'Kurvenjagd',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
          preferredCountryCode: 'AT',
          preferredAdmin1Name: 'Vorarlberg',
          preferredCityCluster: 'Hohenems',
        );

        expect(matches.map((match) => match.route.id), [
          'dornbirn-75-kurven-near-hohenems',
        ]);
        expect(matches.single.radiusScope, 'regional_nearby');
      },
    );

    test(
      'Coverage-Zellen trennen Style und Distanz, Autobahn AN akzeptiert No-Highway-Routen',
      () async {
        final routes = <RoutePoolEntry>[
          for (var i = 0; i < 12; i += 1)
            _route(
              id: 'bregenz-50-sport-$i',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bregenz',
              cityCluster: 'Bregenz',
              startLat: 47.5031 + (i * 0.0001),
              startLng: 9.7471 + (i * 0.0001),
              distanceBucket: 50,
              styleTags: const ['Sport Mode'],
              qualityScore: 88,
            ),
        ];
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bregenz',
              cityCluster: 'Bregenz',
              centerLat: 47.5031,
              centerLng: 9.7471,
            ),
          ],
          inMemoryRoutes: routes,
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: <RouteSeedJob>[],
          inMemoryCandidates: <RoutePoolCandidate>[],
        );

        final report = await service.buildClusterCoverageReport(
          countryCode: 'AT',
          admin1Name: 'Vorarlberg',
          admin2Name: 'Bregenz',
          cityCluster: 'Bregenz',
        );

        expect(report, isNotNull);
        final sport50 = report!.combinations.singleWhere(
          (combo) =>
              combo.requirement.distanceBucket == 50 &&
              combo.requirement.styleKey == 'sport_mode' &&
              combo.requirement.avoidHighways,
        );
        final curvy50 = report.combinations.singleWhere(
          (combo) =>
              combo.requirement.distanceBucket == 50 &&
              combo.requirement.styleKey == 'kurvenjagd' &&
              combo.requirement.avoidHighways,
        );
        final sport75 = report.combinations.singleWhere(
          (combo) =>
              combo.requirement.distanceBucket == 75 &&
              combo.requirement.styleKey == 'sport_mode' &&
              combo.requirement.avoidHighways,
        );
        final sport50HighwayAllowed = report.combinations.singleWhere(
          (combo) =>
              combo.requirement.distanceBucket == 50 &&
              combo.requirement.styleKey == 'sport_mode' &&
              !combo.requirement.avoidHighways,
        );

        expect(sport50.coverageStatus, 'healthy');
        expect(sport50.distinctFingerprintCount, 12);
        expect(curvy50.currentVerifiedCount, 0);
        expect(curvy50.coverageStatus, 'empty');
        expect(sport75.currentVerifiedCount, 0);
        expect(sport75.coverageStatus, 'empty');
        expect(sport50HighwayAllowed.currentVerifiedCount, 12);
        expect(sport50HighwayAllowed.coverageStatus, 'healthy');
      },
    );

    test(
      'Coverage Autobahn AUS zaehlt echte no-highway Routen aus Allow-Zellen',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bregenz',
              cityCluster: 'Bregenz',
              centerLat: 47.5031,
              centerLng: 9.7471,
            ),
          ],
          inMemoryRoutes: [
            for (var i = 0; i < 3; i += 1)
              _route(
                id: 'bregenz-allow-no-highway-coverage-$i',
                countryCode: 'AT',
                admin1Name: 'Vorarlberg',
                admin2Name: 'Bregenz',
                cityCluster: 'Bregenz',
                startLat: 47.5031 + (i * 0.0001),
                startLng: 9.7471 + (i * 0.0001),
                styleTags: const ['Sport Mode'],
                avoidsHighway: false,
                hasHighway: false,
                qualityScore: 88,
              ),
            _route(
              id: 'bregenz-actual-highway-coverage',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bregenz',
              cityCluster: 'Bregenz',
              startLat: 47.5041,
              startLng: 9.7481,
              styleTags: const ['Sport Mode'],
              avoidsHighway: false,
              hasHighway: true,
              qualityScore: 99,
            ),
          ],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: <RouteSeedJob>[],
          inMemoryCandidates: <RoutePoolCandidate>[],
        );

        final check = await service.ensureCoverageForRequest(
          userLat: 47.5031,
          userLng: 9.7471,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
          subscriptionTier: 'free',
        );

        expect(check.currentVerifiedCount, 3);
        expect(check.coverageStatus, 'healthy');
        expect(check.poolHealthy, isTrue);
      },
    );

    test(
      'Bregenz Coverage Report markiert fehlende Stil Distanz Zellen',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bregenz',
              cityCluster: 'Bregenz',
              centerLat: 47.5031,
              centerLng: 9.7471,
            ),
          ],
          inMemoryRoutes: [
            for (var i = 0; i < 3; i += 1)
              _route(
                id: 'bregenz-50-sport-$i',
                countryCode: 'AT',
                admin1Name: 'Vorarlberg',
                admin2Name: 'Bregenz',
                cityCluster: 'Bregenz',
                startLat: 47.5031 + (i * 0.0001),
                startLng: 9.7471 + (i * 0.0001),
                distanceBucket: 50,
                styleTags: const ['Sport Mode'],
                qualityScore: 88,
              ),
            for (var i = 0; i < 3; i += 1)
              _route(
                id: 'bregenz-100-entdecker-$i',
                countryCode: 'AT',
                admin1Name: 'Vorarlberg',
                admin2Name: 'Bregenz',
                cityCluster: 'Bregenz',
                startLat: 47.5041 + (i * 0.0001),
                startLng: 9.7481 + (i * 0.0001),
                distanceBucket: 100,
                styleTags: const ['Entdecker'],
                qualityScore: 88,
              ),
          ],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: <RouteSeedJob>[],
          inMemoryCandidates: <RoutePoolCandidate>[],
        );

        final report = await service.buildClusterCoverageReport(
          countryCode: 'AT',
          admin1Name: 'Vorarlberg',
          admin2Name: 'Bregenz',
          cityCluster: 'Bregenz',
        );

        expect(report, isNotNull);
        Map<String, RoutePoolCombinationCoverage> combosByKey() => {
          for (final combo in report!.combinations)
            '${combo.requirement.distanceBucket}|${combo.requirement.styleKey}|${combo.requirement.avoidHighways}':
                combo,
        };
        final combos = combosByKey();

        expect(combos['50|sport_mode|true']?.coverageStatus, 'healthy');
        expect(combos['50|kurvenjagd|true']?.healingJobNeeded, isTrue);
        expect(combos['50|entdecker|true']?.healingJobNeeded, isTrue);
        expect(combos['75|sport_mode|true']?.healingJobNeeded, isTrue);
        expect(combos['75|kurvenjagd|true']?.healingJobNeeded, isTrue);
        expect(combos['100|sport_mode|true']?.healingJobNeeded, isTrue);
        expect(combos['100|kurvenjagd|true']?.healingJobNeeded, isTrue);
        expect(combos['100|entdecker|true']?.coverageStatus, 'healthy');
        expect(report!.isHealthyMinimum, isFalse);
      },
    );

    test('ROUND_TRIP Pool-Ranking bevorzugt nur die exakte Zelle', () async {
      final service = RoutePoolService(
        inMemoryRegions: [
          _region(
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            admin2Name: 'Bregenz',
            cityCluster: 'Bregenz',
            centerLat: 47.5031,
            centerLng: 9.7471,
          ),
        ],
        inMemoryRoutes: [
          _route(
            id: 'bregenz-sport-closer',
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            admin2Name: 'Bregenz',
            cityCluster: 'Bregenz',
            startLat: 47.5031,
            startLng: 9.7471,
            distanceBucket: 50,
            styleTags: const ['Sport Mode'],
            qualityScore: 100,
          ),
          _route(
            id: 'bregenz-curvy-exact',
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            admin2Name: 'Bregenz',
            cityCluster: 'Bregenz',
            startLat: 47.5033,
            startLng: 9.7473,
            distanceBucket: 50,
            styleTags: const ['Kurvenjagd'],
            qualityScore: 88,
          ),
        ],
      );

      final matches = await service.findCandidateRoutesNear(
        userLat: 47.5031,
        userLng: 9.7471,
        distanceBucket: 50,
        style: 'Kurvenjagd',
        avoidHighways: true,
        routeType: 'ROUND_TRIP',
      );

      expect(matches.map((match) => match.route.id), ['bregenz-curvy-exact']);
    });

    test('avoidHighways false akzeptiert no-highway Zellroute', () async {
      final service = RoutePoolService(
        inMemoryRegions: [
          _region(
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            cityCluster: 'Bregenz',
            centerLat: 47.5031,
            centerLng: 9.7471,
          ),
        ],
        inMemoryRoutes: [
          _route(
            id: 'bregenz-no-highway',
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            cityCluster: 'Bregenz',
            startLat: 47.5031,
            startLng: 9.7471,
            avoidsHighway: true,
            hasHighway: false,
            qualityScore: 88,
          ),
        ],
      );

      final matches = await service.findCandidateRoutesNear(
        userLat: 47.5031,
        userLng: 9.7471,
        distanceBucket: 50,
        style: 'Sport Mode',
        avoidHighways: false,
        routeType: 'ROUND_TRIP',
      );

      expect(matches.map((match) => match.route.id), ['bregenz-no-highway']);
    });

    test(
      'avoidHighways true akzeptiert echte no-highway Routen aus Allow-Zellen',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Bregenz',
              centerLat: 47.5031,
              centerLng: 9.7471,
            ),
          ],
          inMemoryRoutes: [
            _route(
              id: 'bregenz-allow-no-highway',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Bregenz',
              startLat: 47.5031,
              startLng: 9.7471,
              avoidsHighway: false,
              hasHighway: false,
              qualityScore: 88,
            ),
            _route(
              id: 'bregenz-actual-highway',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Bregenz',
              startLat: 47.5032,
              startLng: 9.7472,
              avoidsHighway: false,
              hasHighway: true,
              qualityScore: 99,
            ),
          ],
        );

        final matches = await service.findCandidateRoutesNear(
          userLat: 47.5031,
          userLng: 9.7471,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
        );

        expect(matches.map((match) => match.route.id), [
          'bregenz-allow-no-highway',
        ]);
      },
    );

    test('Acceptable-Reserve macht eine Zelle quality_thin', () async {
      final jobs = <RouteSeedJob>[];
      final service = RoutePoolService(
        inMemoryRegions: [
          _region(
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            admin2Name: 'Bregenz',
            cityCluster: 'Bregenz',
            centerLat: 47.5031,
            centerLng: 9.7471,
          ),
        ],
        inMemoryRoutes: [
          for (var i = 0; i < 3; i += 1)
            _route(
              id: 'bregenz-acceptable-$i',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bregenz',
              cityCluster: 'Bregenz',
              startLat: 47.5031 + (i * 0.0001),
              startLng: 9.7471 + (i * 0.0001),
              distanceBucket: 50,
              styleTags: const ['Kurvenjagd'],
              qualityScore: 78,
              routePayload: const {'quality_tier': 'acceptable'},
            ),
        ],
        inMemoryCoverage: <RoutePoolCoverage>[],
        inMemorySeedJobs: jobs,
        inMemoryCandidates: <RoutePoolCandidate>[],
      );

      final check = await service.ensureCoverageForRequest(
        userLat: 47.5031,
        userLng: 9.7471,
        distanceBucket: 50,
        style: 'Kurvenjagd',
        avoidHighways: true,
        routeType: 'ROUND_TRIP',
        subscriptionTier: 'premium',
        createSeedJob: true,
        preferredCountryCode: 'AT',
        preferredAdmin1Name: 'Vorarlberg',
        preferredAdmin2Name: 'Bregenz',
        preferredCityCluster: 'Bregenz',
      );

      expect(check.coverageStatus, 'quality_thin');
      expect(check.currentVerifiedCount, 3);
      expect(check.acceptableCount, 3);
      expect(check.goodCount + check.idealCount, 0);
      expect(check.seedJobCreated, isTrue);
      expect(jobs, hasLength(1));
      expect(jobs.single.styleKey, 'kurvenjagd');
    });

    test(
      'ROUND_TRIP: 75-km Anfrage nutzt keine 50/100-km Poolroute als normalen Erfolg',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Dornbirn',
              centerLat: 47.4125,
              centerLng: 9.7414,
            ),
          ],
          inMemoryRoutes: [
            _route(
              id: 'dornbirn-50-sport',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Dornbirn',
              startLat: 47.4125,
              startLng: 9.7414,
              distanceBucket: 50,
              styleTags: const ['Sport Mode'],
            ),
            _route(
              id: 'dornbirn-100-sport',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Dornbirn',
              startLat: 47.4126,
              startLng: 9.7415,
              distanceBucket: 100,
              styleTags: const ['Sport Mode'],
            ),
          ],
        );

        final matches = await service.findCandidateRoutesNear(
          userLat: 47.4125,
          userLng: 9.7414,
          distanceBucket: 75,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
        );

        expect(matches, isEmpty);
      },
    );

    test(
      'ROUND_TRIP: 100-km Anfrage nutzt keine 75-km Poolroute als normalen Erfolg',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Dornbirn',
              centerLat: 47.4125,
              centerLng: 9.7414,
            ),
          ],
          inMemoryRoutes: [
            _route(
              id: 'dornbirn-75-kurven',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Dornbirn',
              startLat: 47.4125,
              startLng: 9.7414,
              distanceBucket: 75,
              styleTags: const ['Kurvenjagd'],
            ),
          ],
        );

        final matches = await service.findCandidateRoutesNear(
          userLat: 47.4125,
          userLng: 9.7414,
          distanceBucket: 100,
          style: 'Kurvenjagd',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
        );

        expect(matches, isEmpty);
      },
    );

    test(
      'ROUND_TRIP: inkompatible Style-Route wird nicht durch fremdes Bucket ersetzt',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Götzis',
              centerLat: 47.3331,
              centerLng: 9.6336,
            ),
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Feldkirch',
              centerLat: 47.2386,
              centerLng: 9.5986,
            ),
          ],
          inMemoryRoutes: [
            _route(
              id: 'feldkirch-100-sport',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Feldkirch',
              startLat: 47.3304,
              startLng: 9.6012,
              distanceBucket: 100,
              styleTags: const ['Sport Mode'],
            ),
            _route(
              id: 'feldkirch-50-kurvenjagd',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Feldkirch',
              startLat: 47.3305,
              startLng: 9.6011,
              distanceBucket: 50,
              styleTags: const ['Kurvenjagd'],
            ),
          ],
        );

        final matches = await service.findCandidateRoutesNear(
          userLat: 47.3331,
          userLng: 9.6336,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
        );

        expect(matches, isEmpty);
      },
    );

    test(
      'ROUND_TRIP: Rheintal-Sued gewinnt lokal vor Feldkirch, wenn Goetzis nah startet',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Rheintal-Sued',
              cityCluster: 'Rheintal-Sued',
              centerLat: 47.3499,
              centerLng: 9.6584,
              fallbackRadiusKm: 12,
            ),
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              centerLat: 47.2386,
              centerLng: 9.5986,
            ),
          ],
          inMemoryRoutes: [
            _route(
              id: 'feldkirch-local',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              startLat: 47.2714,
              startLng: 9.6436,
              distanceBucket: 50,
              styleTags: const ['Sport Mode'],
            ),
            _route(
              id: 'rheintal-sued-local',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Rheintal-Sued',
              cityCluster: 'Rheintal-Sued',
              startLat: 47.3367,
              startLng: 9.6461,
              distanceBucket: 50,
              styleTags: const ['Sport Mode'],
            ),
          ],
        );

        final matches = await service.findCandidateRoutesNear(
          userLat: 47.3331,
          userLng: 9.6336,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
        );

        expect(matches, isNotEmpty);
        expect(matches.first.route.id, 'rheintal-sued-local');
        expect(matches.first.radiusScope, 'local_cluster');
        expect(matches.first.startDistanceKm, lessThan(5.0));
      },
    );

    test('Quality-Score entscheidet nur als letzter Tiebreaker', () {
      final match = RoutePoolService.findBestMatch(
        query: const RoutePoolQuery(
          userLat: 47.4125,
          userLng: 9.7414,
          countryCode: 'AT',
          admin1Name: 'Vorarlberg',
          cityCluster: 'Dornbirn',
          distanceBucket: 50,
          style: 'Kurvenjagd',
          avoidHighways: true,
        ),
        regions: [
          _region(
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            cityCluster: 'Dornbirn',
            centerLat: 47.4125,
            centerLng: 9.7414,
          ),
        ],
        candidates: [
          _route(
            id: 'same-distance-low-quality',
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            cityCluster: 'Dornbirn',
            startLat: 47.4125,
            startLng: 9.7414,
            styleTags: const ['Kurvenjagd'],
            qualityScore: 65,
          ),
          _route(
            id: 'same-distance-high-quality',
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            cityCluster: 'Dornbirn',
            startLat: 47.4125,
            startLng: 9.7414,
            styleTags: const ['Kurvenjagd'],
            qualityScore: 95,
          ),
        ],
      );

      expect(match?.route.id, 'same-distance-high-quality');
    });

    test('Weekly-Rotation-Score beeinflusst Pool-Tiebreaker', () {
      final match = RoutePoolService.findBestMatch(
        query: const RoutePoolQuery(
          userLat: 47.4125,
          userLng: 9.7414,
          countryCode: 'AT',
          admin1Name: 'Vorarlberg',
          cityCluster: 'Dornbirn',
          distanceBucket: 50,
          style: 'Kurvenjagd',
          avoidHighways: true,
        ),
        regions: [
          _region(
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            cityCluster: 'Dornbirn',
            centerLat: 47.4125,
            centerLng: 9.7414,
          ),
        ],
        candidates: [
          _route(
            id: 'same-distance-low-rotation',
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            cityCluster: 'Dornbirn',
            startLat: 47.4125,
            startLng: 9.7414,
            styleTags: const ['Kurvenjagd'],
            qualityScore: 95,
            weeklyRotationScore: 20,
          ),
          _route(
            id: 'same-distance-high-rotation',
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            cityCluster: 'Dornbirn',
            startLat: 47.4125,
            startLng: 9.7414,
            styleTags: const ['Kurvenjagd'],
            qualityScore: 80,
            weeklyRotationScore: 85,
          ),
        ],
      );

      expect(match?.route.id, 'same-distance-high-rotation');
    });

    test('RoutePoolEntry liest Curation-Felder aus Supabase-Zeile', () {
      final entry = RoutePoolEntry.fromJson({
        'id': 'pool-curated',
        'country_code': 'AT',
        'admin1_name': 'Vorarlberg',
        'admin2_name': 'Dornbirn',
        'city_cluster': 'Dornbirn',
        'start_lat': 47.4125,
        'start_lng': 9.7414,
        'distance_km': 50.2,
        'distance_bucket': 50,
        'route_type': 'ROUND_TRIP',
        'style_tags': ['Kurvenjagd'],
        'avoids_highway': true,
        'has_highway': false,
        'quality_score': 88,
        'verified': true,
        'geometry': {'type': 'LineString', 'coordinates': []},
        'average_rating': 4.6,
        'rating_count': 3,
        'completion_rate': 0.82,
        'weekly_rotation_score': 91.4,
        'deprecated_at': '2026-05-04T10:00:00Z',
      });

      expect(entry.averageRating, 4.6);
      expect(entry.ratingCount, 3);
      expect(entry.completionRate, 0.82);
      expect(entry.weeklyRotationScore, 91.4);
      expect(entry.deprecatedAt, isNotNull);
    });

    test(
      'User zwischen zwei Clustern wird bestehendem Cluster zugeordnet ohne neuen Orts-Pool',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Feldkirch',
              centerLat: 47.2386,
              centerLng: 9.5986,
            ),
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              cityCluster: 'Bludenz',
              centerLat: 47.1548,
              centerLng: 9.8220,
            ),
          ],
        );

        final assignment = await service.resolveRegionAssignment(
          userLat: 47.2050,
          userLng: 9.6750,
          preferredCountryCode: 'AT',
          preferredAdmin1Name: 'Vorarlberg',
        );

        expect(assignment, isNotNull);
        expect(assignment!.region.cityCluster, 'Feldkirch');
        expect(assignment.newClusterCreated, isFalse);
      },
    );

    test(
      'Hard-Region Bludenz meldet curated_needed und startet keinen endlosen Bootstrap',
      () async {
        final coverages = <RoutePoolCoverage>[];
        final jobs = <RouteSeedJob>[];
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bludenz',
              cityCluster: 'Bludenz',
              centerLat: 47.1548,
              centerLng: 9.8220,
              fallbackRadiusKm: 35,
              difficultyLevel: 'hard',
              hardRegionStatus: 'curated_needed',
              bootstrapEnabled: false,
              curatedSeedPreferred: true,
              defaultTargetPoolSize: 8,
              defaultMaxPoolSize: 10,
              healthyThreshold: 4,
              thinThreshold: 1,
              seedBudgetUnits: 0,
              seedCooldownMinutes: 180,
            ),
          ],
          inMemoryCoverage: coverages,
          inMemorySeedJobs: jobs,
          inMemoryCandidates: <RoutePoolCandidate>[],
          inMemoryRoutes: const [],
        );

        final first = await service.ensureCoverageForRequest(
          userLat: 47.1548,
          userLng: 9.8220,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
          subscriptionTier: 'free',
          createSeedJob: true,
          preferredCountryCode: 'AT',
          preferredAdmin1Name: 'Vorarlberg',
          preferredAdmin2Name: 'Bludenz',
          preferredCityCluster: 'Bludenz',
        );
        final second = await service.ensureCoverageForRequest(
          userLat: 47.1548,
          userLng: 9.8220,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
          subscriptionTier: 'free',
          createSeedJob: true,
          preferredCountryCode: 'AT',
          preferredAdmin1Name: 'Vorarlberg',
          preferredAdmin2Name: 'Bludenz',
          preferredCityCluster: 'Bludenz',
        );

        expect(first.assignment, isNotNull);
        expect(first.assignment!.region.cityCluster, 'Bludenz');
        expect(first.assignment!.newClusterCreated, isFalse);
        expect(first.coverageStatus, 'hard_region_curated_needed');
        expect(first.coverage?.coverageStatus, 'hard_region_curated_needed');
        expect(first.regionDifficulty, 'hard');
        expect(first.hardRegionStatus, 'curated_needed');
        expect(first.toMeta()['chosen_cluster'], 'Bludenz');
        expect(first.toMeta()['region_warming_up'], true);
        expect(first.toMeta()['local_pool_unavailable'], true);
        expect(first.seedJobCreated, isFalse);
        expect(first.duplicateJobPrevented, isFalse);
        expect(first.bootstrapPending, isFalse);
        expect(second.coverageStatus, 'hard_region_curated_needed');
        expect(second.seedJobCreated, isFalse);
        expect(second.duplicateJobPrevented, isFalse);
        expect(second.bootstrapPending, isFalse);
        expect(jobs, isEmpty);
      },
    );

    test(
      'Hard-Region Bludenz erlaubt bezahlten User-Demand-Learning-Job',
      () async {
        final coverages = <RoutePoolCoverage>[];
        final jobs = <RouteSeedJob>[];
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bludenz',
              cityCluster: 'Bludenz',
              centerLat: 47.1548,
              centerLng: 9.8220,
              fallbackRadiusKm: 35,
              difficultyLevel: 'hard',
              hardRegionStatus: 'curated_needed',
              bootstrapEnabled: false,
              curatedSeedPreferred: true,
              defaultTargetPoolSize: 8,
              defaultMaxPoolSize: 10,
              healthyThreshold: 4,
              thinThreshold: 1,
              seedBudgetUnits: 0,
              seedCooldownMinutes: 180,
            ),
          ],
          inMemoryCoverage: coverages,
          inMemorySeedJobs: jobs,
          inMemoryCandidates: <RoutePoolCandidate>[],
          inMemoryRoutes: const [],
        );

        final first = await service.ensureCoverageForRequest(
          userLat: 47.1548,
          userLng: 9.8220,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
          subscriptionTier: 'basic',
          createSeedJob: true,
          preferredCountryCode: 'AT',
          preferredAdmin1Name: 'Vorarlberg',
          preferredAdmin2Name: 'Bludenz',
          preferredCityCluster: 'Bludenz',
        );
        final second = await service.ensureCoverageForRequest(
          userLat: 47.1548,
          userLng: 9.8220,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
          subscriptionTier: 'basic',
          createSeedJob: true,
          preferredCountryCode: 'AT',
          preferredAdmin1Name: 'Vorarlberg',
          preferredAdmin2Name: 'Bludenz',
          preferredCityCluster: 'Bludenz',
        );

        expect(first.seedJobCreated, isTrue);
        expect(first.bootstrapPending, isTrue);
        expect(first.seedJobStatus, 'queued');
        expect(jobs, hasLength(1));
        expect(jobs.single.jobKind, 'manual_seed');
        expect(jobs.single.maxAttempts, 1);
        expect(
          jobs.single.maxMapboxCalls,
          lessThanOrEqualTo(RoutePoolService.userDemandSeedMaxMapboxCalls),
        );
        expect(jobs.single.seedBudgetUnits, greaterThanOrEqualTo(1));
        expect(second.seedJobCreated, isFalse);
        expect(second.duplicateJobPrevented, isTrue);
        expect(jobs, hasLength(1));
      },
    );

    test(
      'Hard-Region Bludenz mit wenig Bestand bleibt hard_region_thin statt healthy',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bludenz',
              cityCluster: 'Bludenz',
              centerLat: 47.1548,
              centerLng: 9.8220,
              fallbackRadiusKm: 35,
              difficultyLevel: 'hard',
              hardRegionStatus: 'curated_needed',
              bootstrapEnabled: false,
              curatedSeedPreferred: true,
              defaultTargetPoolSize: 8,
              defaultMaxPoolSize: 10,
              healthyThreshold: 4,
              thinThreshold: 1,
              seedBudgetUnits: 0,
              seedCooldownMinutes: 180,
            ),
          ],
          inMemoryRoutes: [
            _route(
              id: 'bludenz-single-route',
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bludenz',
              cityCluster: 'Bludenz',
              startLat: 47.1549,
              startLng: 9.8223,
              distanceBucket: 50,
              styleTags: const ['Sport Mode'],
            ),
          ],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: <RouteSeedJob>[],
          inMemoryCandidates: <RoutePoolCandidate>[],
        );

        final check = await service.ensureCoverageForRequest(
          userLat: 47.1548,
          userLng: 9.8220,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
          subscriptionTier: 'premium',
          createSeedJob: false,
          preferredCountryCode: 'AT',
          preferredAdmin1Name: 'Vorarlberg',
          preferredAdmin2Name: 'Bludenz',
          preferredCityCluster: 'Bludenz',
        );

        expect(check.coverageStatus, 'hard_region_thin');
        expect(check.coverage?.coverageStatus, 'hard_region_thin');
        expect(check.regionDifficulty, 'hard');
        expect(check.currentVerifiedCount, 1);
        expect(check.poolHealthy, isFalse);
        expect(check.bootstrapPending, isFalse);
        expect(check.shouldSurfaceWarmup, isTrue);
        expect(check.toMeta()['region_warming_up'], true);
        expect(check.toMeta()['retry_recommended'], true);
      },
    );

    test(
      'Zwischen Nueziders und Bludenz entsteht kein Mikro-Cluster ausserhalb des bestehenden Hard-Region-Pools',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bludenz',
              cityCluster: 'Bludenz',
              centerLat: 47.1548,
              centerLng: 9.8220,
              fallbackRadiusKm: 35,
            ),
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              centerLat: 47.2386,
              centerLng: 9.5986,
            ),
          ],
        );

        final assignment = await service.resolveRegionAssignment(
          userLat: 47.1712,
          userLng: 9.8028,
          preferredCountryCode: 'AT',
          preferredAdmin1Name: 'Vorarlberg',
        );

        expect(assignment, isNotNull);
        expect(assignment!.region.cityCluster, 'Bludenz');
        expect(assignment.newClusterCreated, isFalse);
      },
    );

    test(
      'Free-User in leerer Region erzeugt genau einen Bootstrap-Job und warming_up',
      () async {
        final coverages = <RoutePoolCoverage>[];
        final jobs = <RouteSeedJob>[];
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'DE',
              admin1Name: 'Baden-Württemberg',
              admin2Name: 'Stuttgart',
              cityCluster: 'Stuttgart',
              centerLat: 48.7758,
              centerLng: 9.1829,
            ),
          ],
          inMemoryCoverage: coverages,
          inMemorySeedJobs: jobs,
          inMemoryCandidates: <RoutePoolCandidate>[],
          inMemoryRoutes: const [],
        );

        final first = await service.ensureCoverageForRequest(
          userLat: 48.7800,
          userLng: 9.1800,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
          subscriptionTier: 'free',
          createSeedJob: true,
          preferredCountryCode: 'DE',
          preferredAdmin1Name: 'Baden-Württemberg',
        );
        final second = await service.ensureCoverageForRequest(
          userLat: 48.7800,
          userLng: 9.1800,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
          subscriptionTier: 'free',
          createSeedJob: true,
          preferredCountryCode: 'DE',
          preferredAdmin1Name: 'Baden-Württemberg',
        );

        expect(first.coverageStatus, 'warming_up');
        expect(first.seedJobCreated, isTrue);
        expect(first.duplicateJobPrevented, isFalse);
        expect(second.coverageStatus, 'warming_up');
        expect(second.seedJobCreated, isFalse);
        expect(second.duplicateJobPrevented, isTrue);
        expect(jobs, hasLength(1));
        expect(jobs.single.status, 'queued');
        expect(coverages, hasLength(1));
      },
    );

    test(
      'Legacy sport Seed-Job verhindert doppelten sport_mode Seed-Job',
      () async {
        final jobs = <RouteSeedJob>[
          const RouteSeedJob(
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            admin2Name: 'Feldkirch',
            cityCluster: 'Feldkirch',
            routeType: 'ROUND_TRIP',
            distanceBucket: 50,
            styleKey: 'sport',
            avoidHighways: true,
            status: 'queued',
          ),
        ];
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              centerLat: 47.2386,
              centerLng: 9.5986,
            ),
          ],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: jobs,
          inMemoryCandidates: <RoutePoolCandidate>[],
          inMemoryRoutes: const [],
        );

        final result = await service.ensureCoverageForRequest(
          userLat: 47.2386,
          userLng: 9.5986,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
          subscriptionTier: 'free',
          createSeedJob: true,
          preferredCountryCode: 'AT',
          preferredAdmin1Name: 'Vorarlberg',
          preferredAdmin2Name: 'Feldkirch',
          preferredCityCluster: 'Feldkirch',
        );

        expect(result.seedJobCreated, isFalse);
        expect(result.duplicateJobPrevented, isTrue);
        expect(result.seedJobStatus, 'queued');
        expect(jobs, hasLength(1));
        expect(jobs.single.styleKey, 'sport');
      },
    );

    test(
      'Healthy-Minimum unter Target erzeugt weiteren Seed-Job statt Pool frueh voll zu melden',
      () async {
        final now = DateTime.now().toUtc();
        final coverages = <RoutePoolCoverage>[
          RoutePoolCoverage(
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            admin2Name: 'Feldkirch',
            cityCluster: 'Feldkirch',
            routeType: 'ROUND_TRIP',
            distanceBucket: 50,
            styleKey: 'sport_mode',
            avoidHighways: true,
            coverageStatus: 'healthy',
            targetPoolSize: 12,
            maxPoolSize: 32,
            candidateBufferLimit: 72,
            currentVerifiedCount: 3,
            idealCount: 3,
            distinctFingerprintCount: 3,
            lastCountedAt: now,
          ),
        ];
        final jobs = <RouteSeedJob>[];
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              centerLat: 47.2386,
              centerLng: 9.5986,
              defaultTargetPoolSize: 12,
              defaultMaxPoolSize: 32,
              healthyThreshold: 12,
            ),
          ],
          inMemoryCoverage: coverages,
          inMemorySeedJobs: jobs,
          inMemoryCandidates: <RoutePoolCandidate>[],
          inMemoryRoutes: const [],
        );

        final result = await service.ensureCoverageForRequest(
          userLat: 47.2386,
          userLng: 9.5986,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
          subscriptionTier: 'free',
          createSeedJob: true,
          preferredCountryCode: 'AT',
          preferredAdmin1Name: 'Vorarlberg',
          preferredAdmin2Name: 'Feldkirch',
          preferredCityCluster: 'Feldkirch',
        );

        expect(result.coverageStatus, 'healthy');
        expect(result.poolHealthy, isTrue);
        expect(result.poolFull, isFalse);
        expect(result.seedJobCreated, isTrue);
        expect(result.targetPoolSize, 12);
        expect(result.maxPoolSize, 32);
        expect(result.candidateBufferLimit, 72);
        expect(jobs, hasLength(1));
        expect(jobs.single.status, 'queued');
      },
    );

    test(
      'Max-Pool-Groesse leitet neue gute Route in Candidate-Staging statt Verified-Overflow',
      () async {
        final coverages = <RoutePoolCoverage>[
          const RoutePoolCoverage(
            countryCode: 'DE',
            admin1Name: 'Bayern',
            admin2Name: 'München',
            cityCluster: 'München',
            routeType: 'ROUND_TRIP',
            distanceBucket: 50,
            styleKey: 'sport_mode',
            avoidHighways: true,
            coverageStatus: 'healthy',
            targetPoolSize: 15,
            maxPoolSize: 32,
            currentVerifiedCount: 32,
            currentCandidateCount: 0,
          ),
        ];
        final candidates = <RoutePoolCandidate>[];
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'DE',
              admin1Name: 'Bayern',
              admin2Name: 'München',
              cityCluster: 'München',
              centerLat: 48.1372,
              centerLng: 11.5755,
            ),
          ],
          inMemoryRoutes: List.generate(
            32,
            (index) => _route(
              id: 'munich-verified-$index',
              countryCode: 'DE',
              admin1Name: 'Bayern',
              admin2Name: 'München',
              cityCluster: 'München',
              startLat: 48.1372 + (index * 0.0001),
              startLng: 11.5755 + (index * 0.0001),
              distanceBucket: 50,
              styleTags: const ['Sport Mode'],
            ),
          ),
          inMemoryCoverage: coverages,
          inMemorySeedJobs: <RouteSeedJob>[],
          inMemoryCandidates: candidates,
        );

        final result = await service.recordCandidateRoute(
          userLat: 48.1372,
          userLng: 11.5755,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
          candidateSource: 'basic_live',
          routeFingerprint: 'candidate-muc-50-sport-1',
          geometry: const {
            'type': 'LineString',
            'coordinates': [
              [11.5755, 48.1372],
              [11.62, 48.18],
              [11.5755, 48.1372],
            ],
          },
          distanceKm: 52,
          qualityScore: 88,
        );

        expect(result.saved, isTrue);
        expect(result.poolFull, isTrue);
        expect(candidates, hasLength(1));
        expect(candidates.single.isCandidate, isTrue);
        expect(candidates.single.isVerifiedPool, isFalse);
      },
    );

    test('Candidate-Payload enthaelt nur route_pool_candidates-Spalten', () {
      final payload = const RoutePoolCandidate(
        routeFingerprint: 'payload-schema-check',
        countryCode: 'DE',
        admin1Name: 'Bayern',
        cityCluster: 'München',
        startLat: 48.1372,
        startLng: 11.5755,
        distanceKm: 52,
        routeType: 'ROUND_TRIP',
        distanceBucket: 50,
        styleKey: 'sport_mode',
        styleTags: ['Sport Mode'],
        avoidHighways: true,
        hasHighway: false,
        qualityScore: 88,
        shapeScore: 12,
        candidateSource: 'basic_live',
        difficultyLevel: 'hard',
        hardRegionStatus: 'curated_needed',
        geometry: {'type': 'LineString', 'coordinates': []},
      ).toJson();

      const allowed = {
        'id',
        'route_region_id',
        'route_fingerprint',
        'country_code',
        'admin1_name',
        'admin2_name',
        'city_cluster',
        'start_lat',
        'start_lng',
        'distance_km',
        'route_type',
        'distance_bucket',
        'style_key',
        'style_tags',
        'avoid_highways',
        'has_highway',
        'quality_score',
        'shape_score',
        'candidate_source',
        'average_rating',
        'rating_count',
        'completion_rate',
        'times_selected',
        'last_selected_at',
        'promoted_to_pool_at',
        'demoted_at',
        'is_candidate',
        'is_verified_pool',
        'candidate_score',
        'candidate_region_difficulty',
        'candidate_locality_score',
        'repeated_success_count',
        'geometry',
        'route_payload',
      };

      expect(payload.keys.where((key) => !allowed.contains(key)), isEmpty);
      expect(payload, isNot(contains('difficulty_level')));
      expect(payload, isNot(contains('hard_region_status')));
      expect(payload['candidate_region_difficulty'], 'hard');
      expect(
        (payload['route_payload'] as Map)['hard_region_status'],
        'curated_needed',
      );
    });

    test(
      'Duplicate-Fingerprint wird nicht doppelt als Candidate gespeichert',
      () async {
        final candidates = <RoutePoolCandidate>[];
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'DE',
              admin1Name: 'Bayern',
              admin2Name: 'München',
              cityCluster: 'München',
              centerLat: 48.1372,
              centerLng: 11.5755,
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: <RouteSeedJob>[],
          inMemoryCandidates: candidates,
        );

        Future<RoutePoolCandidateSaveResult> save() =>
            service.recordCandidateRoute(
              userLat: 48.1372,
              userLng: 11.5755,
              distanceBucket: 50,
              style: 'Sport Mode',
              avoidHighways: true,
              routeType: 'ROUND_TRIP',
              candidateSource: 'basic_live',
              routeFingerprint: 'candidate-muc-duplicate',
              geometry: const {
                'type': 'LineString',
                'coordinates': [
                  [11.5755, 48.1372],
                  [11.62, 48.18],
                  [11.5755, 48.1372],
                ],
              },
              distanceKm: 52,
              qualityScore: 88,
            );

        final first = await save();
        final second = await save();

        expect(first.saved, isTrue);
        expect(first.duplicate, isFalse);
        expect(second.saved, isFalse);
        expect(second.duplicate, isTrue);
        expect(second.duplicateSource, 'candidate');
        expect(candidates, hasLength(1));
      },
    );

    test('Verified-Pool-Fingerprint blockiert Candidate-Duplikat', () async {
      final candidates = <RoutePoolCandidate>[];
      final service = RoutePoolService(
        inMemoryRegions: [
          _region(
            countryCode: 'DE',
            admin1Name: 'Bayern',
            admin2Name: 'München',
            cityCluster: 'München',
            centerLat: 48.1372,
            centerLng: 11.5755,
          ),
        ],
        inMemoryRoutes: [
          _route(
            id: 'verified-muc-fingerprint',
            countryCode: 'DE',
            admin1Name: 'Bayern',
            admin2Name: 'München',
            cityCluster: 'München',
            startLat: 48.1372,
            startLng: 11.5755,
            routePayload: const {'route_fingerprint': 'already-verified'},
          ),
        ],
        inMemoryCoverage: <RoutePoolCoverage>[],
        inMemorySeedJobs: <RouteSeedJob>[],
        inMemoryCandidates: candidates,
      );

      final result = await service.recordCandidateRoute(
        userLat: 48.1372,
        userLng: 11.5755,
        distanceBucket: 50,
        style: 'Sport Mode',
        avoidHighways: true,
        routeType: 'ROUND_TRIP',
        candidateSource: 'premium_live',
        routeFingerprint: 'already-verified',
        geometry: const {
          'type': 'LineString',
          'coordinates': [
            [11.5755, 48.1372],
            [11.62, 48.18],
            [11.5755, 48.1372],
          ],
        },
        distanceKm: 52,
        qualityScore: 88,
      );

      expect(result.saved, isFalse);
      expect(result.duplicate, isTrue);
      expect(result.duplicateSource, 'pool');
      expect(candidates, isEmpty);
    });

    test('schlechte Live-Candidates werden nicht gespeichert', () async {
      final candidates = <RoutePoolCandidate>[];
      final service = RoutePoolService(
        inMemoryRegions: [
          _region(
            countryCode: 'DE',
            admin1Name: 'Bayern',
            admin2Name: 'München',
            cityCluster: 'München',
            centerLat: 48.1372,
            centerLng: 11.5755,
          ),
        ],
        inMemoryRoutes: const [],
        inMemoryCoverage: <RoutePoolCoverage>[],
        inMemorySeedJobs: <RouteSeedJob>[],
        inMemoryCandidates: candidates,
      );

      final rejected = await service.recordCandidateRoute(
        userLat: 48.1372,
        userLng: 11.5755,
        distanceBucket: 50,
        style: 'Sport Mode',
        avoidHighways: true,
        routeType: 'ROUND_TRIP',
        candidateSource: 'premium_live',
        routeFingerprint: 'rejected-muc-50-sport',
        geometry: const {
          'type': 'LineString',
          'coordinates': [
            [11.5755, 48.1372],
            [11.62, 48.18],
            [11.5755, 48.1372],
          ],
        },
        routePayload: const {'quality_tier': 'rejected'},
        distanceKm: 52,
        qualityScore: 90,
      );
      final highway = await service.recordCandidateRoute(
        userLat: 48.1372,
        userLng: 11.5755,
        distanceBucket: 50,
        style: 'Sport Mode',
        avoidHighways: true,
        routeType: 'ROUND_TRIP',
        candidateSource: 'premium_live',
        routeFingerprint: 'highway-muc-50-sport',
        geometry: const {
          'type': 'LineString',
          'coordinates': [
            [11.5755, 48.1372],
            [11.62, 48.18],
            [11.5755, 48.1372],
          ],
        },
        distanceKm: 52,
        qualityScore: 90,
        hasHighway: true,
      );
      final lowScore = await service.recordCandidateRoute(
        userLat: 48.1372,
        userLng: 11.5755,
        distanceBucket: 50,
        style: 'Sport Mode',
        avoidHighways: true,
        routeType: 'ROUND_TRIP',
        candidateSource: 'premium_live',
        routeFingerprint: 'low-score-muc-50-sport',
        geometry: const {
          'type': 'LineString',
          'coordinates': [
            [11.5755, 48.1372],
            [11.62, 48.18],
            [11.5755, 48.1372],
          ],
        },
        distanceKm: 52,
        qualityScore: 59,
      );
      final distanceMismatch = await service.recordCandidateRoute(
        userLat: 48.1372,
        userLng: 11.5755,
        distanceBucket: 50,
        style: 'Sport Mode',
        avoidHighways: true,
        routeType: 'ROUND_TRIP',
        candidateSource: 'premium_live',
        routeFingerprint: 'distance-mismatch-muc-50-sport',
        geometry: const {
          'type': 'LineString',
          'coordinates': [
            [11.5755, 48.1372],
            [11.62, 48.18],
            [11.5755, 48.1372],
          ],
        },
        distanceKm: 120,
        qualityScore: 90,
      );

      expect(rejected.saved, isFalse);
      expect(rejected.skippedReason, 'quality_rejected');
      expect(highway.saved, isFalse);
      expect(highway.skippedReason, 'motorway_violation');
      expect(lowScore.saved, isFalse);
      expect(lowScore.skippedReason, 'quality_score_low');
      expect(distanceMismatch.saved, isFalse);
      expect(distanceMismatch.skippedReason, 'distance_mismatch');
      expect(candidates, isEmpty);
    });

    test(
      'Candidate-Reserve nutzt nur sichere Candidates in Hard-Region',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bludenz',
              cityCluster: 'Bludenz',
              centerLat: 47.1548,
              centerLng: 9.8220,
              difficultyLevel: 'hard',
              hardRegionStatus: 'curated_needed',
              curatedSeedPreferred: true,
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: <RouteSeedJob>[],
          inMemoryCandidates: [
            _candidate(
              id: 'bludenz-safe-reserve',
              distanceKm: 58,
              coordinateCount: 120,
            ),
            _candidate(
              id: 'bludenz-highway-reserve',
              distanceKm: 55,
              coordinateCount: 120,
              hasHighway: true,
              avoidHighways: false,
            ),
            _candidate(
              id: 'bludenz-sparse-reserve',
              distanceKm: 55,
              coordinateCount: 12,
            ),
            _candidate(
              id: 'bludenz-demoted-reserve',
              distanceKm: 55,
              coordinateCount: 120,
              demotedAt: DateTime.utc(2026),
              isCandidate: true,
            ),
          ],
        );

        final matches = await service.findCandidateReserveRoutesNear(
          userLat: 47.1548,
          userLng: 9.8220,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
        );

        expect(matches, hasLength(1));
        expect(matches.single.route.id, 'bludenz-safe-reserve');
        expect(matches.single.route.source, 'candidate_reserve');
        expect(matches.single.route.verified, isFalse);
        expect(matches.single.route.routePayload['candidate_reserve'], true);
        expect(
          matches.single.route.routePayload['route_source'],
          'candidate_reserve',
        );
      },
    );

    test('Candidate-Reserve blockiert 100-km Short-Fallbacks', () async {
      final service = RoutePoolService(
        inMemoryRegions: [
          _region(
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            admin2Name: 'Bludenz',
            cityCluster: 'Bludenz',
            centerLat: 47.1548,
            centerLng: 9.8220,
            difficultyLevel: 'hard',
            hardRegionStatus: 'curated_needed',
            curatedSeedPreferred: true,
          ),
        ],
        inMemoryRoutes: const [],
        inMemoryCoverage: <RoutePoolCoverage>[],
        inMemorySeedJobs: <RouteSeedJob>[],
        inMemoryCandidates: [
          _candidate(
            id: 'bludenz-short-100-reserve',
            distanceBucket: 100,
            distanceKm: 89,
            coordinateCount: 180,
          ),
          _candidate(
            id: 'bludenz-safe-100-reserve',
            distanceBucket: 100,
            distanceKm: 98,
            coordinateCount: 180,
          ),
        ],
      );

      final matches = await service.findCandidateReserveRoutesNear(
        userLat: 47.1548,
        userLng: 9.8220,
        distanceBucket: 100,
        style: 'Sport Mode',
        avoidHighways: true,
      );

      expect(matches, hasLength(1));
      expect(matches.single.route.id, 'bludenz-safe-100-reserve');
    });

    test(
      'Candidate-Reserve darf normale thin Coverage-Zellen stuetzen',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bregenz',
              cityCluster: 'Bregenz',
              centerLat: 47.5031,
              centerLng: 9.7471,
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: const [
            RoutePoolCoverage(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bregenz',
              cityCluster: 'Bregenz',
              routeType: 'ROUND_TRIP',
              distanceBucket: 50,
              styleKey: 'sport_mode',
              avoidHighways: false,
              coverageStatus: 'thin',
              currentVerifiedCount: 0,
              currentCandidateCount: 3,
            ),
          ],
          inMemorySeedJobs: <RouteSeedJob>[],
          inMemoryCandidates: [
            _candidate(
              id: 'bregenz-thin-reserve',
              admin2Name: 'Bregenz',
              cityCluster: 'Bregenz',
              startLat: 47.5031,
              startLng: 9.7471,
              distanceKm: 42,
              coordinateCount: 120,
              avoidHighways: true,
            ),
          ],
        );

        final matches = await service.findCandidateReserveRoutesNear(
          userLat: 47.5031,
          userLng: 9.7471,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: false,
        );

        expect(matches, hasLength(1));
        expect(matches.single.route.id, 'bregenz-thin-reserve');
        expect(matches.single.route.routePayload['candidate_reserve'], true);
      },
    );

    test(
      'Candidate-Reserve Autobahn AUS nutzt nur echte no-highway Kandidaten',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bregenz',
              cityCluster: 'Bregenz',
              centerLat: 47.5031,
              centerLng: 9.7471,
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: const [
            RoutePoolCoverage(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bregenz',
              cityCluster: 'Bregenz',
              routeType: 'ROUND_TRIP',
              distanceBucket: 50,
              styleKey: 'sport_mode',
              avoidHighways: true,
              coverageStatus: 'thin',
              currentVerifiedCount: 0,
              currentCandidateCount: 2,
            ),
          ],
          inMemorySeedJobs: <RouteSeedJob>[],
          inMemoryCandidates: [
            _candidate(
              id: 'bregenz-allow-no-highway-reserve',
              admin2Name: 'Bregenz',
              cityCluster: 'Bregenz',
              startLat: 47.5031,
              startLng: 9.7471,
              distanceKm: 52,
              coordinateCount: 120,
              avoidHighways: false,
              hasHighway: false,
            ),
            _candidate(
              id: 'bregenz-actual-highway-reserve',
              admin2Name: 'Bregenz',
              cityCluster: 'Bregenz',
              startLat: 47.5032,
              startLng: 9.7472,
              distanceKm: 52,
              coordinateCount: 120,
              avoidHighways: false,
              hasHighway: true,
            ),
          ],
        );

        final matches = await service.findCandidateReserveRoutesNear(
          userLat: 47.5031,
          userLng: 9.7471,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
        );

        expect(matches.map((match) => match.route.id), [
          'bregenz-allow-no-highway-reserve',
        ]);
      },
    );

    test(
      'Candidate-Reserve stuetzt healthy Zellen mit zu wenig verifizierten Routen',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              centerLat: 47.2386,
              centerLng: 9.5986,
              defaultTargetPoolSize: 12,
              defaultMaxPoolSize: 32,
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: const [
            RoutePoolCoverage(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              routeType: 'ROUND_TRIP',
              distanceBucket: 50,
              styleKey: 'sport_mode',
              avoidHighways: true,
              coverageStatus: 'healthy',
              minVerifiedCount: 3,
              targetPoolSize: 12,
              currentVerifiedCount: 1,
              currentCandidateCount: 4,
              distinctFingerprintCount: 1,
            ),
          ],
          inMemorySeedJobs: <RouteSeedJob>[],
          inMemoryCandidates: [
            _candidate(
              id: 'feldkirch-healthy-thin-reserve',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              startLat: 47.2386,
              startLng: 9.5986,
              styleKey: 'sport',
              distanceKm: 52,
              coordinateCount: 140,
            ),
          ],
        );

        final matches = await service.findCandidateReserveRoutesNear(
          userLat: 47.2386,
          userLng: 9.5986,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
        );

        expect(matches, hasLength(1));
        expect(matches.single.route.id, 'feldkirch-healthy-thin-reserve');
        expect(matches.single.route.source, 'candidate_reserve');
      },
    );

    test(
      'Coverage zaehlt legacy sport Candidates fuer Sport-Mode-Zellen',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              centerLat: 47.2386,
              centerLng: 9.5986,
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: <RouteSeedJob>[],
          inMemoryCandidates: [
            _candidate(
              id: 'feldkirch-legacy-sport-reserve',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              startLat: 47.2386,
              startLng: 9.5986,
              styleKey: 'sport',
              distanceKm: 52,
              coordinateCount: 120,
            ),
            _candidate(
              id: 'feldkirch-canonical-sport-reserve',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              startLat: 47.2387,
              startLng: 9.5987,
              styleKey: 'sport_mode',
              distanceKm: 54,
              coordinateCount: 120,
            ),
          ],
        );

        final check = await service.ensureCoverageForRequest(
          userLat: 47.2386,
          userLng: 9.5986,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
          subscriptionTier: 'premium',
          createSeedJob: false,
          preferredCountryCode: 'AT',
          preferredAdmin1Name: 'Vorarlberg',
          preferredAdmin2Name: 'Feldkirch',
          preferredCityCluster: 'Feldkirch',
        );

        expect(check.coverage?.styleKey, 'sport_mode');
        expect(check.currentVerifiedCount, 0);
        expect(check.currentCandidateCount, 2);
        expect(check.coverage?.currentCandidateCount, 2);
      },
    );

    test(
      'Candidate-Reserve findet sport und sport_mode Candidates fuer Sport Mode',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              centerLat: 47.2386,
              centerLng: 9.5986,
              difficultyLevel: 'normal',
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: const [
            RoutePoolCoverage(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              routeType: 'ROUND_TRIP',
              distanceBucket: 50,
              styleKey: 'sport_mode',
              avoidHighways: true,
              coverageStatus: 'warming_up',
              currentVerifiedCount: 1,
              currentCandidateCount: 2,
            ),
          ],
          inMemorySeedJobs: <RouteSeedJob>[],
          inMemoryCandidates: [
            _candidate(
              id: 'feldkirch-legacy-sport-reserve',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              startLat: 47.2386,
              startLng: 9.5986,
              styleKey: 'sport',
              distanceKm: 52,
              coordinateCount: 120,
            ),
            _candidate(
              id: 'feldkirch-canonical-sport-reserve',
              admin2Name: 'Feldkirch',
              cityCluster: 'Feldkirch',
              startLat: 47.2388,
              startLng: 9.5988,
              styleKey: 'sport_mode',
              distanceKm: 54,
              coordinateCount: 120,
            ),
          ],
        );

        final matches = await service.findCandidateReserveRoutesNear(
          userLat: 47.2386,
          userLng: 9.5986,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
        );

        expect(
          matches.map((match) => match.route.id),
          containsAll([
            'feldkirch-legacy-sport-reserve',
            'feldkirch-canonical-sport-reserve',
          ]),
        );
      },
    );

    test('Candidate-Reserve ist in normalen Regionen deaktiviert', () async {
      final service = RoutePoolService(
        inMemoryRegions: [
          _region(
            countryCode: 'AT',
            admin1Name: 'Vorarlberg',
            admin2Name: 'Dornbirn',
            cityCluster: 'Dornbirn',
            centerLat: 47.4125,
            centerLng: 9.7417,
          ),
        ],
        inMemoryRoutes: const [],
        inMemoryCoverage: <RoutePoolCoverage>[],
        inMemorySeedJobs: <RouteSeedJob>[],
        inMemoryCandidates: [
          _candidate(
            id: 'dornbirn-safe-reserve',
            cityCluster: 'Dornbirn',
            startLat: 47.4125,
            startLng: 9.7417,
            distanceKm: 55,
            coordinateCount: 120,
          ),
        ],
      );

      final matches = await service.findCandidateReserveRoutesNear(
        userLat: 47.4125,
        userLng: 9.7417,
        distanceBucket: 50,
        style: 'Sport Mode',
        avoidHighways: true,
      );

      expect(matches, isEmpty);
    });

    test(
      'Candidate-Reserve kann nach Live-NoRoute in normaler Region erzwungen werden',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Rheintal-Sued',
              cityCluster: 'Rheintal-Sued',
              centerLat: 47.3331,
              centerLng: 9.6336,
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: <RouteSeedJob>[],
          inMemoryCandidates: [
            _candidate(
              id: 'goetzis-safe-forced-reserve',
              admin2Name: 'Rheintal-Sued',
              cityCluster: 'Rheintal-Sued',
              startLat: 47.356,
              startLng: 9.65,
              styleKey: 'sport_mode',
              distanceKm: 52,
              coordinateCount: 120,
            ),
          ],
        );

        final matches = await service.findCandidateReserveRoutesNear(
          userLat: 47.3331,
          userLng: 9.6336,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          forceAllow: true,
        );

        expect(matches.map((match) => match.route.id), [
          'goetzis-safe-forced-reserve',
        ]);
      },
    );

    test(
      'Cluster mit vielen falschen Routen ist ohne passende Zellen nicht healthy_minimum',
      () async {
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'DE',
              admin1Name: 'Bayern',
              admin2Name: 'München',
              cityCluster: 'München',
              centerLat: 48.1372,
              centerLng: 11.5755,
            ),
          ],
          inMemoryRoutes: List.generate(
            20,
            (index) => _route(
              id: 'munich-evening-$index',
              countryCode: 'DE',
              admin1Name: 'Bayern',
              admin2Name: 'München',
              cityCluster: 'München',
              startLat: 48.1372 + (index * 0.0001),
              startLng: 11.5755 + (index * 0.0001),
              distanceBucket: 50,
              styleTags: const ['Custom'],
              qualityScore: 88,
            ),
          ),
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: <RouteSeedJob>[],
          inMemoryCandidates: <RoutePoolCandidate>[],
        );

        final report = await service.buildClusterCoverageReport(
          countryCode: 'DE',
          admin1Name: 'Bayern',
          admin2Name: 'München',
          cityCluster: 'München',
        );

        expect(report, isNotNull);
        expect(report!.totalVerifiedCount, 20);
        expect(report.fulfilledCombinationCount, 0);
        expect(report.coverageStatus, 'thin');
        expect(report.isHealthyMinimum, isFalse);
        expect(report.missingCombinations, hasLength(24));
      },
    );

    test(
      'Dornbirn 75 Kurvenjagd AUS fehlend erzeugt priorisierten Seed-Job',
      () async {
        final routes = <RoutePoolEntry>[];
        var id = 0;
        for (final requirement in RoutePoolService.mvpRequiredCombinations) {
          if (requirement.distanceBucket == 75 &&
              requirement.styleKey == 'kurvenjagd' &&
              requirement.avoidHighways) {
            continue;
          }
          for (var i = 0; i < requirement.requiredVerifiedCount; i += 1) {
            routes.add(
              _route(
                id: 'dornbirn-covered-${id++}',
                countryCode: 'AT',
                admin1Name: 'Vorarlberg',
                admin2Name: 'Dornbirn',
                cityCluster: 'Dornbirn',
                startLat: 47.4125 + (id * 0.0001),
                startLng: 9.7414 + (id * 0.0001),
                distanceBucket: requirement.distanceBucket,
                styleTags: [requirement.styleLabel],
                avoidsHighway: requirement.avoidHighways,
                hasHighway: !requirement.avoidHighways,
                qualityScore: 88,
              ),
            );
          }
        }
        final jobs = <RouteSeedJob>[];
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Dornbirn',
              cityCluster: 'Dornbirn',
              centerLat: 47.4125,
              centerLng: 9.7414,
              difficultyLevel: 'easy',
              defaultTargetPoolSize: 18,
              defaultMaxPoolSize: 20,
              healthyThreshold: 12,
              thinThreshold: 4,
              seedBudgetUnits: 2,
            ),
          ],
          inMemoryRoutes: routes,
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: jobs,
          inMemoryCandidates: <RoutePoolCandidate>[],
        );

        final report = await service.buildClusterCoverageReport(
          countryCode: 'AT',
          admin1Name: 'Vorarlberg',
          admin2Name: 'Dornbirn',
          cityCluster: 'Dornbirn',
          createSeedJobs: true,
          subscriptionTier: 'premium',
        );

        expect(report, isNotNull);
        expect(report!.coverageStatus, 'thin');
        expect(report.fulfilledCombinationCount, 23);
        expect(report.seedJobsQueuedCount, 1);
        expect(jobs, hasLength(1));
        expect(jobs.single.distanceBucket, 75);
        expect(jobs.single.styleKey, 'kurvenjagd');
        expect(jobs.single.priority, greaterThanOrEqualTo(90));
      },
    );

    test(
      'Bludenz hard region bekommt curated_needed statt endloser Seed-Jobs',
      () async {
        final jobs = <RouteSeedJob>[];
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'AT',
              admin1Name: 'Vorarlberg',
              admin2Name: 'Bludenz',
              cityCluster: 'Bludenz',
              centerLat: 47.1548,
              centerLng: 9.8220,
              difficultyLevel: 'hard',
              hardRegionStatus: 'curated_needed',
              bootstrapEnabled: false,
              curatedSeedPreferred: true,
              seedBudgetUnits: 0,
              seedCooldownMinutes: 180,
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: jobs,
          inMemoryCandidates: <RoutePoolCandidate>[],
        );

        final report = await service.buildClusterCoverageReport(
          countryCode: 'AT',
          admin1Name: 'Vorarlberg',
          admin2Name: 'Bludenz',
          cityCluster: 'Bludenz',
          createSeedJobs: true,
          subscriptionTier: 'premium',
        );

        expect(report, isNotNull);
        expect(report!.coverageStatus, 'hard_region_curated_needed');
        expect(report.hardRegion, isTrue);
        expect(report.seedJobsQueuedCount, 0);
        expect(jobs, isEmpty);
      },
    );

    test(
      'Stuttgart Muenchen und Zuerich erhalten Coverage-Zellen ohne Massenseeding',
      () async {
        final coverages = <RoutePoolCoverage>[];
        final jobs = <RouteSeedJob>[];
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'DE',
              admin1Name: 'Baden-Württemberg',
              admin2Name: 'Stuttgart',
              cityCluster: 'Stuttgart',
              centerLat: 48.7758,
              centerLng: 9.1829,
            ),
            _region(
              countryCode: 'DE',
              admin1Name: 'Bayern',
              admin2Name: 'München',
              cityCluster: 'München',
              centerLat: 48.1372,
              centerLng: 11.5755,
            ),
            _region(
              countryCode: 'CH',
              admin1Name: 'Zürich',
              admin2Name: 'Zürich',
              cityCluster: 'Zürich',
              centerLat: 47.3769,
              centerLng: 8.5417,
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: coverages,
          inMemorySeedJobs: jobs,
          inMemoryCandidates: <RoutePoolCandidate>[],
        );

        final stuttgart = await service.buildClusterCoverageReport(
          countryCode: 'DE',
          admin1Name: 'Baden-Württemberg',
          admin2Name: 'Stuttgart',
          cityCluster: 'Stuttgart',
        );
        final munich = await service.buildClusterCoverageReport(
          countryCode: 'DE',
          admin1Name: 'Bayern',
          admin2Name: 'München',
          cityCluster: 'München',
        );
        final zurich = await service.buildClusterCoverageReport(
          countryCode: 'CH',
          admin1Name: 'Zürich',
          admin2Name: 'Zürich',
          cityCluster: 'Zürich',
        );

        expect(stuttgart?.coverageStatus, 'empty');
        expect(munich?.coverageStatus, 'empty');
        expect(zurich?.coverageStatus, 'empty');
        expect(coverages, hasLength(72));
        expect(jobs, isEmpty);
      },
    );

    test('Coverage-Meta mappt Seed-Job-Status auf Healing-Status', () {
      final queued = _coverageCheck(seedJobStatus: 'queued');
      final running = _coverageCheck(seedJobStatus: 'running');
      final cooldown = _coverageCheck(seedJobStatus: 'cooldown');
      final budget = _coverageCheck(seedJobStatus: 'paused_budget');
      final curated = _coverageCheck(
        coverageStatus: 'hard_region_curated_needed',
      );

      expect(queued.toMeta()['healing_status'], 'healing_queued');
      expect(running.toMeta()['healing_status'], 'healing_running');
      expect(cooldown.toMeta()['healing_status'], 'healing_failed_cooldown');
      expect(budget.toMeta()['healing_status'], 'healing_paused_budget');
      expect(curated.toMeta()['healing_status'], 'hard_region_curated_needed');
    });

    test('Budget-pausierter Healing-Job wird nicht dupliziert', () async {
      final now = DateTime.utc(2026, 4, 27);
      final jobs = <RouteSeedJob>[
        RouteSeedJob(
          id: 'existing-budget-paused',
          countryCode: 'DE',
          admin1Name: 'Baden-Württemberg',
          admin2Name: 'Stuttgart',
          cityCluster: 'Stuttgart',
          routeType: 'ROUND_TRIP',
          distanceBucket: 50,
          styleKey: 'sport_mode',
          avoidHighways: true,
          status: 'paused_budget',
          dailyAttemptBudget: 1,
          monthlyAttemptBudget: 1,
          dailyAttemptCount: 1,
          monthlyAttemptCount: 1,
          budgetWindowDate: now,
          budgetWindowMonth: DateTime.utc(2026, 4),
          lastError: 'request_budget_exhausted',
          nextRetryAt: DateTime.utc(2026, 4, 28),
        ),
      ];
      final service = RoutePoolService(
        inMemoryRegions: [
          _region(
            countryCode: 'DE',
            admin1Name: 'Baden-Württemberg',
            admin2Name: 'Stuttgart',
            cityCluster: 'Stuttgart',
            centerLat: 48.7758,
            centerLng: 9.1829,
          ),
        ],
        inMemoryRoutes: const [],
        inMemoryCoverage: <RoutePoolCoverage>[],
        inMemorySeedJobs: jobs,
        inMemoryCandidates: <RoutePoolCandidate>[],
      );

      final check = await service.ensureCoverageForRequest(
        userLat: 48.7758,
        userLng: 9.1829,
        distanceBucket: 50,
        style: 'Sport Mode',
        avoidHighways: true,
        routeType: 'ROUND_TRIP',
        subscriptionTier: 'free',
        createSeedJob: true,
        preferredCountryCode: 'DE',
        preferredAdmin1Name: 'Baden-Württemberg',
        preferredAdmin2Name: 'Stuttgart',
        preferredCityCluster: 'Stuttgart',
      );

      expect(check.seedJobCreated, isFalse);
      expect(check.duplicateJobPrevented, isTrue);
      expect(check.seedJobStatus, 'paused_budget');
      expect(check.toMeta()['healing_status'], 'healing_paused_budget');
      expect(check.toMeta()['healing_job_id'], 'existing-budget-paused');
      expect(jobs, hasLength(1));
    });

    test(
      'Ein fehlgeschlagener Healing-Versuch blockiert Retry nicht dauerhaft',
      () async {
        final jobs = <RouteSeedJob>[
          const RouteSeedJob(
            id: 'failed-once',
            countryCode: 'DE',
            admin1Name: 'Baden-Württemberg',
            admin2Name: 'Stuttgart',
            cityCluster: 'Stuttgart',
            routeType: 'ROUND_TRIP',
            distanceBucket: 50,
            styleKey: 'sport_mode',
            avoidHighways: true,
            status: 'failed',
            attemptCount: 1,
            failureCount: 1,
            maxAttempts: 3,
            seedBudgetUnits: 1,
            lastError: 'no_candidate_generated',
          ),
        ];
        final service = RoutePoolService(
          inMemoryRegions: [
            _region(
              countryCode: 'DE',
              admin1Name: 'Baden-Württemberg',
              admin2Name: 'Stuttgart',
              cityCluster: 'Stuttgart',
              centerLat: 48.7758,
              centerLng: 9.1829,
            ),
          ],
          inMemoryRoutes: const [],
          inMemoryCoverage: <RoutePoolCoverage>[],
          inMemorySeedJobs: jobs,
          inMemoryCandidates: <RoutePoolCandidate>[],
        );

        final check = await service.ensureCoverageForRequest(
          userLat: 48.7758,
          userLng: 9.1829,
          distanceBucket: 50,
          style: 'Sport Mode',
          avoidHighways: true,
          routeType: 'ROUND_TRIP',
          subscriptionTier: 'premium',
          createSeedJob: true,
          preferredCountryCode: 'DE',
          preferredAdmin1Name: 'Baden-Württemberg',
          preferredAdmin2Name: 'Stuttgart',
          preferredCityCluster: 'Stuttgart',
        );

        expect(check.seedJobCreated, isTrue);
        expect(check.duplicateJobPrevented, isFalse);
        expect(jobs.single.status, 'queued');
        expect(jobs.single.failureCount, 1);
      },
    );

    test('Budget 0 verhindert auch den ersten Healing-Job', () async {
      final jobs = <RouteSeedJob>[];
      final service = RoutePoolService(
        inMemoryRegions: [
          _region(
            countryCode: 'DE',
            admin1Name: 'Baden-Württemberg',
            admin2Name: 'Stuttgart',
            cityCluster: 'Stuttgart',
            centerLat: 48.7758,
            centerLng: 9.1829,
            seedBudgetUnits: 0,
          ),
        ],
        inMemoryRoutes: const [],
        inMemoryCoverage: <RoutePoolCoverage>[],
        inMemorySeedJobs: jobs,
        inMemoryCandidates: <RoutePoolCandidate>[],
      );

      final check = await service.ensureCoverageForRequest(
        userLat: 48.7758,
        userLng: 9.1829,
        distanceBucket: 50,
        style: 'Sport Mode',
        avoidHighways: true,
        routeType: 'ROUND_TRIP',
        subscriptionTier: 'premium',
        createSeedJob: true,
        preferredCountryCode: 'DE',
        preferredAdmin1Name: 'Baden-Württemberg',
        preferredAdmin2Name: 'Stuttgart',
        preferredCityCluster: 'Stuttgart',
      );

      expect(check.seedJobCreated, isFalse);
      expect(check.duplicateJobPrevented, isFalse);
      expect(jobs, isEmpty);
    });
  });
}

RouteRegion _region({
  required String countryCode,
  required String admin1Name,
  String? admin2Name,
  required String cityCluster,
  required double centerLat,
  required double centerLng,
  double fallbackRadiusKm = 30,
  String difficultyLevel = 'normal',
  String hardRegionStatus = 'normal',
  bool bootstrapEnabled = true,
  bool curatedSeedPreferred = false,
  int defaultTargetPoolSize = 15,
  int defaultMaxPoolSize = 32,
  int healthyThreshold = 15,
  int thinThreshold = 1,
  int seedBudgetUnits = 1,
  int seedCooldownMinutes = 20,
}) {
  return RouteRegion(
    countryCode: countryCode,
    admin1Name: admin1Name,
    admin2Name: admin2Name,
    cityCluster: cityCluster,
    centerLat: centerLat,
    centerLng: centerLng,
    fallbackRadiusKm: fallbackRadiusKm,
    difficultyLevel: difficultyLevel,
    hardRegionStatus: hardRegionStatus,
    bootstrapEnabled: bootstrapEnabled,
    curatedSeedPreferred: curatedSeedPreferred,
    defaultTargetPoolSize: defaultTargetPoolSize,
    defaultMaxPoolSize: defaultMaxPoolSize,
    healthyThreshold: healthyThreshold,
    thinThreshold: thinThreshold,
    seedBudgetUnits: seedBudgetUnits,
    seedCooldownMinutes: seedCooldownMinutes,
  );
}

RoutePoolCoverageCheck _coverageCheck({
  String coverageStatus = 'warming_up',
  String? seedJobStatus,
}) {
  return RoutePoolCoverageCheck(
    assignment: RoutePoolRegionAssignment(
      region: _region(
        countryCode: 'AT',
        admin1Name: 'Vorarlberg',
        cityCluster: 'Feldkirch',
        centerLat: 47.2386,
        centerLng: 9.5986,
      ),
      distanceToCenterKm: 0,
    ),
    coverage: null,
    coverageStatus: coverageStatus,
    regionDifficulty: coverageStatus == 'hard_region_curated_needed'
        ? 'hard'
        : 'normal',
    hardRegionStatus: coverageStatus == 'hard_region_curated_needed'
        ? 'curated_needed'
        : 'normal',
    bootstrapEnabled: coverageStatus != 'hard_region_curated_needed',
    curatedSeedPreferred: coverageStatus == 'hard_region_curated_needed',
    minVerifiedCount: 3,
    targetPoolSize: 12,
    maxPoolSize: 32,
    candidateBufferLimit: 72,
    acceptableReserveLimitPercent: 25,
    currentVerifiedCount: 0,
    currentCandidateCount: 0,
    idealCount: 0,
    goodCount: 0,
    acceptableCount: 0,
    rejectedCount: 0,
    distinctFingerprintCount: 0,
    seedJobCreated: seedJobStatus == 'queued',
    duplicateJobPrevented: false,
    poolHealthy: false,
    poolFull: false,
    bootstrapPending: seedJobStatus == 'queued' || seedJobStatus == 'running',
    seedJobStatus: seedJobStatus,
  );
}

RoutePoolEntry _route({
  required String id,
  required String countryCode,
  required String admin1Name,
  String? admin2Name,
  required String cityCluster,
  required double startLat,
  required double startLng,
  int distanceBucket = 50,
  String routeType = 'ROUND_TRIP',
  List<String> styleTags = const ['Sport Mode'],
  bool avoidsHighway = true,
  bool hasHighway = false,
  double qualityScore = 80,
  double weeklyRotationScore = 0,
  Map<String, dynamic> routePayload = const {},
}) {
  return RoutePoolEntry(
    id: id,
    countryCode: countryCode,
    admin1Name: admin1Name,
    admin2Name: admin2Name,
    cityCluster: cityCluster,
    startLat: startLat,
    startLng: startLng,
    distanceKm: distanceBucket.toDouble(),
    distanceBucket: distanceBucket,
    routeType: routeType,
    styleTags: styleTags,
    avoidsHighway: avoidsHighway,
    hasHighway: hasHighway,
    qualityScore: qualityScore,
    weeklyRotationScore: weeklyRotationScore,
    verified: true,
    routePayload: routePayload,
    geometry: {
      'type': 'LineString',
      'coordinates': [
        [startLng, startLat],
        [startLng + 0.01, startLat + 0.01],
        [startLng, startLat],
      ],
    },
  );
}

RoutePoolCandidate _candidate({
  required String id,
  String countryCode = 'AT',
  String admin1Name = 'Vorarlberg',
  String? admin2Name = 'Bludenz',
  String cityCluster = 'Bludenz',
  double startLat = 47.1548,
  double startLng = 9.8220,
  int distanceBucket = 50,
  double distanceKm = 55,
  String styleKey = 'sport',
  List<String> styleTags = const ['Sport Mode'],
  bool avoidHighways = true,
  bool hasHighway = false,
  double qualityScore = 78,
  int coordinateCount = 120,
  DateTime? promotedToPoolAt,
  DateTime? demotedAt,
  bool isCandidate = true,
  bool isVerifiedPool = false,
}) {
  return RoutePoolCandidate(
    id: id,
    routeFingerprint: 'fingerprint-$id',
    countryCode: countryCode,
    admin1Name: admin1Name,
    admin2Name: admin2Name,
    cityCluster: cityCluster,
    startLat: startLat,
    startLng: startLng,
    distanceKm: distanceKm,
    routeType: 'ROUND_TRIP',
    distanceBucket: distanceBucket,
    styleKey: styleKey,
    styleTags: styleTags,
    avoidHighways: avoidHighways,
    hasHighway: hasHighway,
    qualityScore: qualityScore,
    shapeScore: 78,
    candidateSource: 'bootstrap',
    promotedToPoolAt: promotedToPoolAt,
    demotedAt: demotedAt,
    isCandidate: isCandidate,
    isVerifiedPool: isVerifiedPool,
    geometry: _candidateReserveGeometry(
      startLat: startLat,
      startLng: startLng,
      coordinateCount: coordinateCount,
    ),
    routePayload: {
      'quality_tier': 'acceptable',
      'final_geometry_source': 'hydrated_worker',
      'route_distance_km': distanceKm,
    },
  );
}

Map<String, dynamic> _candidateReserveGeometry({
  required double startLat,
  required double startLng,
  required int coordinateCount,
}) {
  final safeCount = coordinateCount.clamp(2, 240).toInt();
  final coordinates = List<List<double>>.generate(safeCount, (index) {
    final phase = index % 4;
    final lap = index / (safeCount - 1);
    final offset = 0.006 + (lap * 0.002);
    return switch (phase) {
      0 => [startLng, startLat],
      1 => [startLng + offset, startLat + 0.002],
      2 => [startLng + offset, startLat + offset],
      _ => [startLng - 0.002, startLat + offset],
    };
  });
  coordinates[0] = [startLng, startLat];
  coordinates[coordinates.length - 1] = [startLng, startLat];
  return {'type': 'LineString', 'coordinates': coordinates};
}
