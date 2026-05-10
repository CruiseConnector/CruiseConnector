import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/route_scenario.dart';

void main() {
  group('RouteScenario novelty keys', () {
    test(
      'roundtrips share broad novelty across nearby starts and different modes',
      () {
        const sportScenario = RouteScenario(
          routeType: 'ROUND_TRIP',
          startLatitude: 47.23861,
          startLongitude: 9.59862,
          style: 'Sport Mode',
          planningType: 'Zufall',
          targetDistanceKm: 50,
          avoidHighways: true,
          closeLoop: true,
        );
        const explorerScenario = RouteScenario(
          routeType: 'ROUND_TRIP',
          startLatitude: 47.24102,
          startLongitude: 9.60121,
          style: 'Entdecker',
          planningType: 'Zufall',
          targetDistanceKm: 75,
          avoidHighways: true,
          closeLoop: true,
        );

        expect(sportScenario.scenarioKey, isNot(explorerScenario.scenarioKey));
        expect(sportScenario.noveltyKey, isNot(explorerScenario.noveltyKey));
        expect(sportScenario.broadNoveltyKey, explorerScenario.broadNoveltyKey);
      },
    );

    test('point-to-point broad novelty stays scenario specific', () {
      const scenario = RouteScenario(
        routeType: 'POINT_TO_POINT',
        startLatitude: 47.23861,
        startLongitude: 9.59862,
        destinationLatitude: 47.4125,
        destinationLongitude: 9.7417,
        style: 'Standard',
        planningType: 'A nach B',
        targetDistanceKm: 0,
      );

      expect(scenario.broadNoveltyKey, scenario.scenarioKey);
    });
  });
}
