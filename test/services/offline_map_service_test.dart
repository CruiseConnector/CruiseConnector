import 'package:cruise_connect/data/services/offline_map_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OfflineMapService tilesForRoute', () {
    test('waehlt Tiles entlang der Route ueber mehrere Zoomstufen', () {
      final route = [
        [8.5417, 47.3769],
        [8.5600, 47.3900],
        [8.5800, 47.4050],
      ];

      final tiles = OfflineMapService.instance.tilesForRoute(
        route,
        minZoom: 10,
        maxZoom: 12,
        maxTiles: 100,
      );

      expect(tiles, isNotEmpty);
      expect(tiles.map((tile) => tile.z).toSet(), containsAll([10, 11, 12]));
      expect(tiles.length, lessThanOrEqualTo(100));
      expect(tiles.toSet(), hasLength(tiles.length));
    });

    test('respektiert das Tile-Limit deterministisch', () {
      final route = List.generate(
        120,
        (index) => [8.50 + index * 0.002, 47.30 + index * 0.001],
      );

      final tiles = OfflineMapService.instance.tilesForRoute(
        route,
        minZoom: 10,
        maxZoom: 16,
        maxTiles: 5,
      );

      expect(tiles, hasLength(5));
      expect(
        tiles,
        equals(
          OfflineMapService.instance.tilesForRoute(
            route,
            minZoom: 10,
            maxZoom: 16,
            maxTiles: 5,
          ),
        ),
      );
    });

    test('liefert keine Tiles fuer zu kurze oder ungueltige Eingaben', () {
      expect(OfflineMapService.instance.tilesForRoute(const []), isEmpty);
      expect(
        OfflineMapService.instance.tilesForRoute(
          const [
            [8.5, 47.3],
            [8.6, 47.4],
          ],
          minZoom: 13,
          maxZoom: 12,
        ),
        isEmpty,
      );
      expect(
        OfflineMapService.instance.tilesForRoute(const [
          [8.5, 47.3],
          [8.6, 47.4],
        ], maxTiles: 0),
        isEmpty,
      );
    });
  });
}
