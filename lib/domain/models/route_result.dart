import 'route_maneuver.dart';

/// Ergebnis einer Routenberechnung vom Edge-Function-Service.
class RouteResult {
  const RouteResult({
    required this.geoJson,
    required this.geometry,
    required this.coordinates,
    required this.maneuvers,
    this.distanceMeters,
    this.durationSeconds,
    this.distanceKm,
  });

  final String geoJson;
  final Map<String, dynamic> geometry;
  final List<List<double>> coordinates;
  final List<RouteManeuver> maneuvers;
  final double? distanceMeters;
  final double? durationSeconds;
  final double? distanceKm;
}
