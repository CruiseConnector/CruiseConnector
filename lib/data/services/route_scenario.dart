import 'package:flutter/foundation.dart';

@immutable
class RouteScenario {
  const RouteScenario({
    required this.routeType,
    required this.startLatitude,
    required this.startLongitude,
    required this.style,
    required this.planningType,
    this.destinationLatitude,
    this.destinationLongitude,
    this.targetDistanceKm,
    this.detourLevel = 0,
    this.avoidHighways = false,
  });

  final String routeType;
  final double startLatitude;
  final double startLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final String style;
  final double? targetDistanceKm;
  final int detourLevel;
  final bool avoidHighways;
  final String planningType;

  bool get isRoundTrip => routeType == 'ROUND_TRIP';
  bool get isPointToPoint => routeType == 'POINT_TO_POINT';

  String get scenarioKey {
    final startLat = startLatitude.toStringAsFixed(3);
    final startLng = startLongitude.toStringAsFixed(3);
    final destKey =
        destinationLatitude != null && destinationLongitude != null
        ? '${destinationLatitude!.toStringAsFixed(3)},${destinationLongitude!.toStringAsFixed(3)}'
        : 'none';
    final distanceKey = targetDistanceKm != null
        ? targetDistanceKm!.toStringAsFixed(1)
        : '0.0';
    return [
      routeType,
      startLat,
      startLng,
      destKey,
      style,
      planningType,
      distanceKey,
      'd$detourLevel',
      'h${avoidHighways ? 1 : 0}',
    ].join('|');
  }
}
