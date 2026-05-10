import 'dart:math' as math;

import 'package:geolocator/geolocator.dart' as geo;

import 'package:cruise_connect/domain/models/route_maneuver.dart';

/// Kleinstmöglicher Winkelunterschied zweier Himmelsrichtungen in Grad (0..180).
double headingDeltaDegrees(double headingA, double headingB) {
  final normalizedA = headingA % 360;
  final normalizedB = headingB % 360;
  final raw = (normalizedA - normalizedB).abs();
  return raw > 180 ? 360 - raw : raw;
}

/// Erkennung eines faktischen Wendemanövers anhand der Richtungsänderung.
bool isUTurnHeadingChange(
  double fromHeading,
  double toHeading, {
  double thresholdDegrees = 145.0,
}) {
  return headingDeltaDegrees(fromHeading, toHeading) >= thresholdDegrees;
}

/// Bearing zwischen zwei Punkten in [lng, lat] in Grad.
double bearingFromCoordinates(List<double> from, List<double> to) {
  final lat1 = from[1] * math.pi / 180;
  final lat2 = to[1] * math.pi / 180;
  final dLon = (to[0] - from[0]) * math.pi / 180;

  final y = math.sin(dLon) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Bearing eines Routenabschnitts an einer Stelle [index] (von index -> index+1).
double routeHeadingAt(List<List<double>> coordinates, int index) {
  if (coordinates.length < 2) return 0;
  final safeIndex = index.clamp(0, coordinates.length - 2);
  return bearingFromCoordinates(
    coordinates[safeIndex],
    coordinates[safeIndex + 1],
  );
}

/// Wählt einen Rejoin-Index, der möglichst in Fahrtrichtung liegt.
///
/// Der Algorithmus schaut nur nach vorne und bevorzugt Kandidaten mit geringer
/// Richtungsabweichung zur aktuellen Fahrzeugausrichtung.
int selectForwardRejoinIndex({
  required List<List<double>> coordinates,
  required int nearestIndex,
  required double currentHeadingDegrees,
  int minLookAheadPoints = 90,
  int maxLookAheadPoints = 320,
  double maxAlignmentDeltaDegrees = 100.0,
}) {
  if (coordinates.length < 2) return 0;

  final safeNearest = nearestIndex.clamp(0, coordinates.length - 2);
  final minIndex = math.min(
    safeNearest + minLookAheadPoints,
    coordinates.length - 2,
  );
  final maxIndex = math.min(
    safeNearest + maxLookAheadPoints,
    coordinates.length - 2,
  );

  if (minIndex >= maxIndex) return minIndex;

  int? bestIndex;
  double bestScore = -double.infinity;

  for (var idx = minIndex; idx <= maxIndex; idx++) {
    final candidateHeading = routeHeadingAt(coordinates, idx);
    final delta = headingDeltaDegrees(currentHeadingDegrees, candidateHeading);
    if (delta > maxAlignmentDeltaDegrees) continue;

    // Hohe Ausrichtungstreue und moderaten Look-Ahead bevorzugen.
    final alignmentScore = math.cos(delta * math.pi / 180);
    final proximityPenalty = (idx - minIndex) * 0.001;
    final score = alignmentScore - proximityPenalty;

    if (score > bestScore) {
      bestScore = score;
      bestIndex = idx;
    }
  }

  return bestIndex ?? minIndex;
}

/// Prüft ob der Übergang von Reroute -> Originalroute zu einem U-Turn führt.
bool isUTurnJoin({
  required List<List<double>> rerouteCoordinates,
  required List<List<double>> originalCoordinates,
  required int rejoinIndex,
  double thresholdDegrees = 145.0,
}) {
  if (rerouteCoordinates.length < 2 || originalCoordinates.length < 2) {
    return false;
  }

  final safeRejoin = rejoinIndex.clamp(0, originalCoordinates.length - 2);
  final rerouteHeading = bearingFromCoordinates(
    rerouteCoordinates[rerouteCoordinates.length - 2],
    rerouteCoordinates.last,
  );
  final originalHeading = routeHeadingAt(originalCoordinates, safeRejoin);

  return isUTurnHeadingChange(
    rerouteHeading,
    originalHeading,
    thresholdDegrees: thresholdDegrees,
  );
}

/// Distanz in Metern von einer Position zu einem [lng, lat]-Zielpunkt.
double distanceToCoordinateMeters({
  required geo.Position position,
  required List<double> coordinate,
}) {
  if (coordinate.length < 2) return double.infinity;
  return geo.Geolocator.distanceBetween(
    position.latitude,
    position.longitude,
    coordinate[1],
    coordinate[0],
  );
}

/// Erkennt, ob die letzten Samples eine sinnvolle Annäherung an das Ziel zeigen.
bool isApproachingDestination(
  List<double> recentDistancesMeters, {
  double minImprovementMeters = 12.0,
}) {
  if (recentDistancesMeters.length < 3) return false;

  final oldest = recentDistancesMeters.first;
  final newest = recentDistancesMeters.last;
  final improvement = oldest - newest;
  final dynamicThreshold = math.max(minImprovementMeters, oldest * 0.015);

  return improvement >= dynamicThreshold;
}

bool shouldShowArrivalManeuver({
  required double? remainingRouteDistanceMeters,
  required double? distanceToFinalTargetMeters,
  double arrivalRadiusMeters = 50.0,
}) {
  if (remainingRouteDistanceMeters == null ||
      distanceToFinalTargetMeters == null) {
    return false;
  }
  return remainingRouteDistanceMeters <= arrivalRadiusMeters &&
      distanceToFinalTargetMeters <= arrivalRadiusMeters;
}

bool shouldCompleteNavigation({
  required bool isRoundTrip,
  required double distanceToFinalTargetMeters,
  required double drivenDistanceMeters,
  required double? plannedDistanceMeters,
  double completionRadiusMeters = 50.0,
  double minRoundTripProgress = 0.95,
}) {
  if (distanceToFinalTargetMeters > completionRadiusMeters) return false;
  if (!isRoundTrip) return true;
  if (plannedDistanceMeters == null || plannedDistanceMeters <= 0) return true;
  final progress = (drivenDistanceMeters / plannedDistanceMeters).clamp(
    0.0,
    1.0,
  );
  return progress >= minRoundTripProgress;
}

bool violatesNoHighwayPolicy({
  required bool avoidHighways,
  required Map<String, dynamic> edgeMeta,
}) {
  if (!avoidHighways) return false;

  final motorwayViolation =
      _boolMeta(edgeMeta, 'motorwayViolation') ??
      _boolMeta(edgeMeta, 'motorway_violation') ??
      false;
  if (motorwayViolation) return true;

  final hasHighway =
      _boolMeta(edgeMeta, 'actual_has_highway') ??
      _boolMeta(edgeMeta, 'has_highway') ??
      _boolMeta(edgeMeta, 'motorway_present') ??
      false;
  if (hasHighway) return true;

  final avoidRequested = _boolMeta(edgeMeta, 'avoid_highways_requested');
  if (avoidRequested == false) return true;

  final highwayAllowed = _boolMeta(edgeMeta, 'highway_allowed');
  if (highwayAllowed == true) return true;

  final motorwayPolicy = _stringMeta(edgeMeta, 'motorway_policy');
  if (motorwayPolicy == 'allowed_not_required') return true;

  final effectiveExcludes = _stringMeta(edgeMeta, 'effective_excludes');
  if (effectiveExcludes != null &&
      !_containsExclude(effectiveExcludes, 'motorway')) {
    return true;
  }

  return false;
}

int? selectActiveGuidanceManeuverIndex({
  required List<RouteManeuver> maneuvers,
  required int currentRouteIndex,
  required double? remainingRouteDistanceMeters,
  required double? distanceToFinalTargetMeters,
  int startIndex = 0,
  double arrivalRadiusMeters = 50.0,
}) {
  if (maneuvers.isEmpty) return null;

  final safeStart = startIndex.clamp(0, maneuvers.length - 1).toInt();
  for (var i = safeStart; i < maneuvers.length; i++) {
    final maneuver = maneuvers[i];
    if (maneuver.routeIndex < currentRouteIndex) continue;
    if (maneuver.isArrival) {
      return shouldShowArrivalManeuver(
            remainingRouteDistanceMeters: remainingRouteDistanceMeters,
            distanceToFinalTargetMeters: distanceToFinalTargetMeters,
            arrivalRadiusMeters: arrivalRadiusMeters,
          )
          ? i
          : null;
    }
    return i;
  }

  final lastIndex = maneuvers.length - 1;
  final last = maneuvers[lastIndex];
  if (last.isArrival) {
    return shouldShowArrivalManeuver(
          remainingRouteDistanceMeters: remainingRouteDistanceMeters,
          distanceToFinalTargetMeters: distanceToFinalTargetMeters,
          arrivalRadiusMeters: arrivalRadiusMeters,
        )
        ? lastIndex
        : null;
  }
  return lastIndex;
}

/// Baut kompakte Telemetrie für einen echten Straßen-Reroute.
Map<String, dynamic> buildRerouteTelemetry({
  required String rerouteReason,
  required String rerouteMode,
  required double? remainingDistanceBeforeMeters,
  required double? remainingDistanceAfterMeters,
  required double? etaBeforeSeconds,
  required double? etaAfterSeconds,
  double? rerouteDistanceMeters,
  double? rejoinPointDistanceMeters,
  bool rerouteFailed = false,
}) {
  double? roundKm(double? meters) => meters == null
      ? null
      : double.parse((meters / 1000.0).toStringAsFixed(2));
  double? roundSeconds(double? seconds) =>
      seconds == null ? null : double.parse(seconds.toStringAsFixed(1));

  return {
    'reroute_triggered': true,
    'reroute_reason': rerouteReason,
    'reroute_mode': rerouteMode,
    'reroute_distance_km': roundKm(rerouteDistanceMeters),
    'rejoin_point_distance_km': roundKm(rejoinPointDistanceMeters),
    'remaining_distance_before': roundKm(remainingDistanceBeforeMeters),
    'remaining_distance_after': roundKm(remainingDistanceAfterMeters),
    'eta_before': roundSeconds(etaBeforeSeconds),
    'eta_after': roundSeconds(etaAfterSeconds),
    'reroute_failed': rerouteFailed,
  };
}

bool? _boolMeta(Map<String, dynamic> meta, String key) {
  final value = meta[key];
  return value is bool ? value : null;
}

String? _stringMeta(Map<String, dynamic> meta, String key) {
  final value = meta[key];
  if (value == null) return null;
  final text = value.toString().trim().toLowerCase();
  return text.isEmpty ? null : text;
}

bool _containsExclude(String excludes, String token) {
  return excludes
      .split(',')
      .map((entry) => entry.trim().toLowerCase())
      .contains(token);
}
