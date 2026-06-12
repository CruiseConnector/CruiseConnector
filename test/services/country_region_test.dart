import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/country_region.dart';

void main() {
  group('CountryRegion.classify', () {
    test('Götzis / Vorarlberg ist AT', () {
      // Götzis ~47.33, 9.64
      expect(CountryRegion.classify(47.33, 9.64), 'AT');
    });

    test('Wien ist AT', () {
      expect(CountryRegion.classify(48.21, 16.37), 'AT');
    });

    test('Punkt westlich des Rheins (CH) ist CH', () {
      // St. Gallen ~47.42, 9.37
      expect(CountryRegion.classify(47.42, 9.37), 'CH');
    });

    test('München ist DE', () {
      expect(CountryRegion.classify(48.14, 11.58), 'DE');
    });

    test('Bozen/Südtirol ist IT', () {
      expect(CountryRegion.classify(46.49, 11.35), 'IT');
    });
  });

  group('CountryRegion.foreignFraction', () {
    test('reine AT-Route hat 0 Ausland-Anteil', () {
      final coords = [
        [9.64, 47.33],
        [9.70, 47.36],
        [9.75, 47.40],
      ];
      expect(
        CountryRegion.foreignFraction(
          coordinates: coords,
          homeCountryCode: 'AT',
        ),
        0.0,
      );
    });

    test('Route mit CH-Anteil hat >0 Ausland-Anteil', () {
      final coords = [
        [9.64, 47.33], // AT
        [9.37, 47.42], // CH
        [9.35, 47.43], // CH
      ];
      final frac = CountryRegion.foreignFraction(
        coordinates: coords,
        homeCountryCode: 'AT',
      );
      expect(frac, greaterThan(0.0));
      expect(frac, lessThanOrEqualTo(1.0));
    });
  });

  group('CountryRegion.scorePenalty', () {
    test('any-Präferenz → kein Penalty', () {
      expect(
        CountryRegion.scorePenalty(
          foreignFraction: 1.0,
          preference: CountryPreference.any,
        ),
        0.0,
      );
    });

    test('preferHome < onlyHome für gleichen Anteil', () {
      final prefer = CountryRegion.scorePenalty(
        foreignFraction: 0.5,
        preference: CountryPreference.preferHome,
      );
      final only = CountryRegion.scorePenalty(
        foreignFraction: 0.5,
        preference: CountryPreference.onlyHome,
      );
      expect(prefer, lessThan(only));
    });

    test('Penalty bleibt endlich; harter Reject sitzt im RouteService', () {
      final only = CountryRegion.scorePenalty(
        foreignFraction: 1.0,
        preference: CountryPreference.onlyHome,
      );
      expect(only.isFinite, isTrue);
      expect(only, lessThan(500.0)); // weit unter destinationReached-Reject 500
    });

    test(
      'onlyHome-Schwelle ist zentral und toleriert kleines Box-Rauschen',
      () {
        expect(CountryRegion.onlyHomeMaxForeignFraction, 0.10);
      },
    );

    test('kleiner Grenz-Touch → kaum Penalty', () {
      final small = CountryRegion.scorePenalty(
        foreignFraction: 0.05,
        preference: CountryPreference.onlyHome,
      );
      expect(small, lessThan(20.0));
    });
  });
}
