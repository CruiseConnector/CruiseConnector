import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/geo_distance.dart';

void main() {
  group('GeoDistance', () {
    test('haversineKm returns zero for identical coordinates', () {
      final distanceKm = GeoDistance.haversineKm(
        fromLat: 47.2692,
        fromLng: 9.5986,
        toLat: 47.2692,
        toLng: 9.5986,
      );

      expect(distanceKm, closeTo(0, 0.000001));
    });

    test('lngLatDistanceMeters treats coordinates as Mapbox [lng, lat]', () {
      final meters = GeoDistance.lngLatDistanceMeters(
        const [9.5986, 47.2692],
        const [9.7372, 47.3667],
      );

      expect(meters, closeTo(15100, 400));
    });

    test('maxSegmentMetersLngLat returns longest segment only', () {
      final maxMeters = GeoDistance.maxSegmentMetersLngLat(const [
        [9.5986, 47.2692],
        [9.6000, 47.2692],
        [9.7372, 47.3667],
      ]);

      expect(maxMeters, greaterThan(14000));
      expect(maxMeters, lessThan(16000));
    });

    test('polylineMetersLngLat sums Mapbox coordinate segments', () {
      final meters = GeoDistance.polylineMetersLngLat(const [
        [9.5986, 47.2692],
        [9.6000, 47.2692],
        [9.7372, 47.3667],
      ]);

      expect(meters, greaterThan(15000));
      expect(meters, lessThan(15400));
    });
  });
}
