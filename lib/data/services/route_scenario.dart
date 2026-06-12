import 'package:flutter/foundation.dart';

import 'package:cruise_connect/data/services/country_region.dart';

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
    this.waypointSignature,
    this.closeLoop = false,
    // 2026-05-30/06-12 (vucko): Länder-Präferenz. `onlyHome` ist ein harter
    // Inlandsfilter; darum muss sie Teil aller Scenario-/Novelty-Keys sein.
    this.countryPreference = CountryPreference.any,
    this.homeCountryCode,
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
  final String? waypointSignature;
  final bool closeLoop;
  final CountryPreference countryPreference;
  final String? homeCountryCode;

  String get normalizedRouteType => routeType.trim().toUpperCase();

  bool get isRoundTrip => normalizedRouteType == 'ROUND_TRIP';
  bool get isPointToPoint => normalizedRouteType == 'POINT_TO_POINT';

  String get _countryKey {
    if (countryPreference == CountryPreference.any) {
      return 'cp${CountryPreference.any.storageValue}';
    }
    final home = homeCountryCode?.trim().toUpperCase();
    return [
      'cp${countryPreference.storageValue}',
      if (home != null && home.isNotEmpty) 'hc$home',
    ].join('|');
  }

  String get noveltyKey {
    if (!isRoundTrip) return scenarioKey;
    final startLat = startLatitude.toStringAsFixed(3);
    final startLng = startLongitude.toStringAsFixed(3);
    return [
      normalizedRouteType,
      startLat,
      startLng,
      'novelty',
      _countryKey,
      if (waypointSignature != null && waypointSignature!.isNotEmpty)
        'wp$waypointSignature',
      if (closeLoop) 'loop1',
    ].join('|');
  }

  String get broadNoveltyKey {
    if (!isRoundTrip) return scenarioKey;
    final startLat = startLatitude.toStringAsFixed(2);
    final startLng = startLongitude.toStringAsFixed(2);
    return [
      normalizedRouteType,
      startLat,
      startLng,
      'novelty_broad',
      _countryKey,
      if (waypointSignature != null && waypointSignature!.isNotEmpty)
        'wp$waypointSignature',
      if (closeLoop) 'loop1',
    ].join('|');
  }

  String get scenarioKey {
    final startLat = startLatitude.toStringAsFixed(3);
    final startLng = startLongitude.toStringAsFixed(3);
    final destKey = destinationLatitude != null && destinationLongitude != null
        ? '${destinationLatitude!.toStringAsFixed(3)},${destinationLongitude!.toStringAsFixed(3)}'
        : 'none';
    final distanceKey = targetDistanceKm != null
        ? targetDistanceKm!.toStringAsFixed(1)
        : '0.0';
    return [
      normalizedRouteType,
      startLat,
      startLng,
      destKey,
      style,
      planningType,
      distanceKey,
      'd$detourLevel',
      'h${avoidHighways ? 1 : 0}',
      _countryKey,
      if (waypointSignature != null && waypointSignature!.isNotEmpty)
        'wp$waypointSignature',
      if (closeLoop) 'loop1',
    ].join('|');
  }
}
