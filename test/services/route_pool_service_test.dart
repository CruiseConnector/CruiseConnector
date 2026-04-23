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
      'ROUND_TRIP: gleiches Distanz-Bucket mit relaxed style kommt vor exact fallback bucket',
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

        expect(matches, hasLength(2));
        expect(matches.first.route.id, 'feldkirch-50-abend');
        expect(matches.last.route.id, 'feldkirch-100-sport');
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
}) {
  return RouteRegion(
    countryCode: countryCode,
    admin1Name: admin1Name,
    admin2Name: admin2Name,
    cityCluster: cityCluster,
    centerLat: centerLat,
    centerLng: centerLng,
    fallbackRadiusKm: fallbackRadiusKm,
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
