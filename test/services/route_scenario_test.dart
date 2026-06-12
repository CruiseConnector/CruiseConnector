import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/country_region.dart';
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

    test('country preference separates scenario and novelty keys', () {
      const anyCountry = RouteScenario(
        routeType: 'ROUND_TRIP',
        startLatitude: 47.3331,
        startLongitude: 9.6336,
        style: 'Sport Mode',
        planningType: 'Zufall',
        targetDistanceKm: 50,
      );
      const onlyHome = RouteScenario(
        routeType: 'ROUND_TRIP',
        startLatitude: 47.3331,
        startLongitude: 9.6336,
        style: 'Sport Mode',
        planningType: 'Zufall',
        targetDistanceKm: 50,
        countryPreference: CountryPreference.onlyHome,
        homeCountryCode: 'AT',
      );

      expect(anyCountry.scenarioKey, isNot(onlyHome.scenarioKey));
      expect(anyCountry.noveltyKey, isNot(onlyHome.noveltyKey));
      expect(anyCountry.broadNoveltyKey, isNot(onlyHome.broadNoveltyKey));
      expect(onlyHome.scenarioKey, contains('cponly_home'));
      expect(onlyHome.scenarioKey, contains('hcAT'));
    });

    test('any country preference ignores stale home country code in keys', () {
      const cleanAny = RouteScenario(
        routeType: 'ROUND_TRIP',
        startLatitude: 47.3331,
        startLongitude: 9.6336,
        style: 'Sport Mode',
        planningType: 'Zufall',
        targetDistanceKm: 50,
        countryPreference: CountryPreference.any,
      );
      const staleHomeAny = RouteScenario(
        routeType: 'ROUND_TRIP',
        startLatitude: 47.3331,
        startLongitude: 9.6336,
        style: 'Sport Mode',
        planningType: 'Zufall',
        targetDistanceKm: 50,
        countryPreference: CountryPreference.any,
        homeCountryCode: 'AT',
      );

      expect(staleHomeAny.scenarioKey, cleanAny.scenarioKey);
      expect(staleHomeAny.noveltyKey, cleanAny.noveltyKey);
      expect(staleHomeAny.broadNoveltyKey, cleanAny.broadNoveltyKey);
    });
  });
}
