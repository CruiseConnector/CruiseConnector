import 'dart:math' as math;

/// Shared geographic distance helpers.
///
/// Coordinates in this project are often Mapbox-style `[longitude, latitude]`.
/// Keep both APIs explicit so call sites do not silently swap lat/lng.
class GeoDistance {
  const GeoDistance._();

  static double haversineKm({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    const radiusKm = 6371.0;
    final dLat = _toRadians(toLat - fromLat);
    final dLng = _toRadians(toLng - fromLng);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(fromLat)) *
            math.cos(_toRadians(toLat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return radiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double haversineMeters({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    return haversineKm(
          fromLat: fromLat,
          fromLng: fromLng,
          toLat: toLat,
          toLng: toLng,
        ) *
        1000.0;
  }

  static double lngLatDistanceMeters(List<double> from, List<double> to) {
    if (from.length < 2 || to.length < 2) return double.infinity;
    return haversineMeters(
      fromLat: from[1],
      fromLng: from[0],
      toLat: to[1],
      toLng: to[0],
    );
  }

  static double maxSegmentMetersLngLat(List<List<double>> coordinates) {
    var maxMeters = 0.0;
    for (var i = 1; i < coordinates.length; i++) {
      final meters = lngLatDistanceMeters(coordinates[i - 1], coordinates[i]);
      if (meters.isFinite && meters > maxMeters) maxMeters = meters;
    }
    return maxMeters;
  }

  static double polylineMetersLngLat(List<List<double>> coordinates) {
    if (coordinates.length < 2) return 0.0;
    var meters = 0.0;
    for (var i = 1; i < coordinates.length; i++) {
      final segment = lngLatDistanceMeters(coordinates[i - 1], coordinates[i]);
      if (segment.isFinite) meters += segment;
    }
    return meters;
  }

  static double _toRadians(double degrees) => degrees * (math.pi / 180.0);
}
