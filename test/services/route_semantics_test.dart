import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/route_semantics.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/data/services/route_style_config.dart';

void main() {
  group('RouteSemantics', () {
    test(
      'normalizes Sport Mode aliases without splitting verified pool styles',
      () {
        expect(RouteSemantics.normalizeStyleKey('Sport Mode'), 'sport_mode');
        expect(RouteSemantics.normalizeStyleKey('sport'), 'sport');
        expect(RouteSemantics.styleKeyAliases('Sport Mode'), {
          'sport_mode',
          'sport',
        });
        expect(
          RouteSemantics.styleKeyMatches(
            'sport',
            RouteSemantics.styleKeyAliases('Sport Mode'),
          ),
          isTrue,
        );
      },
    );

    test('normalizes Kurvenjagd and Alpine aliases consistently', () {
      final aliases = RouteSemantics.styleKeyAliases('Alpenstraßen');

      expect(aliases, contains('kurvenjagd'));
      expect(aliases, contains('alpenstrassen'));
      expect(RouteStyleConfig.forMode('Alpenstraßen').profileKey, 'kurvenjagd');
    });

    test('normalizes route type aliases for pool and route service checks', () {
      expect(RouteSemantics.normalizeRouteType('roundtrip'), 'ROUND_TRIP');
      expect(RouteSemantics.normalizeRouteType('Rundkurs'), 'ROUND_TRIP');
      expect(RouteSemantics.normalizeRouteType('a_b'), 'POINT_TO_POINT');
      expect(
        RouteSemantics.routeTypeMatches('round_trip', 'ROUND_TRIP'),
        isTrue,
      );
      expect(RouteService.requiresDestination('pointtopoint'), isTrue);
      expect(RouteService.requiresDestination('Rundkurs'), isFalse);
    });
  });
}
