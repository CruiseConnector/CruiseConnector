import 'dart:math' as math;

import 'package:geolocator/geolocator.dart' as geo;

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
