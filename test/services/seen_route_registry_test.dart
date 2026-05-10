import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/seen_route_registry.dart';

void main() {
  group('SeenRouteRegistry direction diversity', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SeenRouteRegistry.clearAll();
    });

    tearDown(SeenRouteRegistry.clearAll);

    test('merkt dominante Richtungssektoren fuer Search-Again', () {
      const scenarioKey = 'ROUND_TRIP|AT|Vorarlberg|Feldkirch|50|sport|true';

      SeenRouteRegistry.remember(
        scenarioKey,
        fingerprint: 'north-loop',
        sampledCoordinates: const [
          [9.5986, 47.2386],
          [9.5986, 47.38],
          [9.5986, 47.2386],
        ],
      );

      expect(
        SeenRouteRegistry.hasRecentDominantSectorInAny(
          const [scenarioKey],
          const [
            [9.60, 47.24],
            [9.61, 47.42],
            [9.60, 47.24],
          ],
        ),
        isTrue,
      );
      expect(
        SeenRouteRegistry.hasRecentDominantSectorInAny(
          const [scenarioKey],
          const [
            [9.60, 47.24],
            [9.82, 47.24],
            [9.60, 47.24],
          ],
        ),
        isFalse,
      );
    });

    test('persistiert dominante Richtungssektoren', () async {
      const scenarioKey = 'ROUND_TRIP|persistent-direction';
      const sampledCoordinates = [
        [9.5986, 47.2386],
        [9.86, 47.2386],
        [9.5986, 47.2386],
      ];
      final expectedSector = SeenRouteRegistry.dominantSectorForCoordinates(
        sampledCoordinates,
      );
      await SeenRouteRegistry.ensureLoaded();
      SeenRouteRegistry.remember(
        scenarioKey,
        fingerprint: 'east-loop',
        sampledCoordinates: sampledCoordinates,
      );
      await SeenRouteRegistry.flushForTests();

      SeenRouteRegistry.resetMemoryForTests();
      await SeenRouteRegistry.ensureLoaded();

      expect(
        SeenRouteRegistry.recentDominantSectorsForAny(const [scenarioKey]),
        contains(expectedSector),
      );
    });
  });
}
