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
    this.speedLimits = const [],
    this.edgeMeta = const {},
  });

  final String geoJson;
  final Map<String, dynamic> geometry;
  final List<List<double>> coordinates;
  final List<RouteManeuver> maneuvers;
  final double? distanceMeters;
  final double? durationSeconds;
  final double? distanceKm;

  /// Tempolimits pro Routenabschnitt: [{startIndex, endIndex, speedKmh}]
  final List<SpeedLimitSegment> speedLimits;

  /// Zusätzliche Metadaten der Edge Function, z.B. serverseitiges Quality-Tier.
  final Map<String, dynamic> edgeMeta;
}

/// Ein Abschnitt der Route mit einem bestimmten Tempolimit.
class SpeedLimitSegment {
  const SpeedLimitSegment({
    required this.startIndex,
    required this.endIndex,
    required this.speedKmh,
  });
  final int startIndex;
  final int endIndex;
  final int speedKmh;
}
