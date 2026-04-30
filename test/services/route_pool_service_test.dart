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
      'ROUND_TRIP: relaxed style bleibt im exakten Distanz-Bucket',
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

        expect(matches.map((match) => match.route.id), ['feldkirch-50-abend']);
      },
    );

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
            maxPoolSize: 20,
            currentVerifiedCount: 20,
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
            20,
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

    test(
      'Cluster mit vielen falschen Routen ist ohne Pflicht-Kombis nicht healthy_minimum',
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
              styleTags: const ['Abendrunde'],
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
        expect(report.missingCombinations, hasLength(6));
      },
    );

    test(
      'Dornbirn 75 Kurvenjagd AUS fehlend erzeugt priorisierten Seed-Job',
      () async {
        final routes = <RoutePoolEntry>[];
        var id = 0;
        for (final requirement in RoutePoolService.mvpRequiredCombinations) {
          if (requirement.distanceBucket == 75 &&
              requirement.styleKey == 'kurvenjagd') {
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
        expect(report.fulfilledCombinationCount, 5);
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
        expect(coverages, hasLength(18));
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
  int defaultMaxPoolSize = 20,
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
    targetPoolSize: 15,
    maxPoolSize: 20,
    currentVerifiedCount: 0,
    currentCandidateCount: 0,
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
    verified: true,
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
