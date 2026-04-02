import 'dart:math' as math;

import 'package:geolocator/geolocator.dart' as geo;

import 'package:cruise_connect/domain/models/route_result.dart';

class RouteJoinPoint {
  const RouteJoinPoint({
    required this.index,
    required this.coordinate,
    required this.distanceFromCurrentMeters,
    required this.remainingDistanceMeters,
    required this.progressRatio,
    required this.headingDeltaDegrees,
    required this.score,
  });

  final int index;
  final List<double> coordinate;
  final double distanceFromCurrentMeters;
  final double remainingDistanceMeters;
  final double progressRatio;
  final double headingDeltaDegrees;
  final double score;
}

class RouteAccessPlan {
  const RouteAccessPlan({
    required this.originalRoute,
    required this.activeRoute,
    required this.followOnRoute,
    required this.joinPoint,
    required this.logicalOrigin,
    required this.logicalEnd,
    this.accessLeg,
  });

  final RouteResult originalRoute;
  final RouteResult activeRoute;
  final RouteResult followOnRoute;
  final RouteJoinPoint joinPoint;
  final RouteResult? accessLeg;
  final List<double> logicalOrigin;
  final List<double> logicalEnd;

  bool get hasAccessLeg => accessLeg != null;
}

class RouteAccessPlanner {
  const RouteAccessPlanner();

  RouteJoinPoint chooseJoinPoint({
    required geo.Position currentPosition,
    required RouteResult existingRoute,
    int? preferredJoinIndex,
  }) {
    final coordinates = existingRoute.coordinates;
    if (coordinates.length < 2) {
      throw ArgumentError('Existing route requires at least 2 coordinates.');
    }

    final cumulativeDistances = _buildCumulativeDistances(coordinates);
    final totalDistanceMeters = cumulativeDistances.last;
    final cappedPreferred = preferredJoinIndex?.clamp(
      0,
      coordinates.length - 1,
    );
    if (cappedPreferred != null) {
      return _buildJoinPoint(
        currentPosition: currentPosition,
        coordinates: coordinates,
        cumulativeDistances: cumulativeDistances,
        totalDistanceMeters: totalDistanceMeters,
        index: cappedPreferred,
      );
    }

    final minRemainingMeters = math.max(900.0, totalDistanceMeters * 0.14);
    final maxJoinIndex = _maxJoinIndexForRemainingDistance(
      cumulativeDistances: cumulativeDistances,
      totalDistanceMeters: totalDistanceMeters,
      minRemainingMeters: minRemainingMeters,
    );
    final primaryMaxIndex = _maxJoinIndexForProgress(
      cumulativeDistances: cumulativeDistances,
      totalDistanceMeters: totalDistanceMeters,
      maxProgressRatio: 0.35,
    );
    final expandedMaxIndex = _maxJoinIndexForProgress(
      cumulativeDistances: cumulativeDistances,
      totalDistanceMeters: totalDistanceMeters,
      maxProgressRatio: 0.45,
    );
    final step = math.max(1, coordinates.length ~/ 26);
    RouteJoinPoint? best;

    for (final upperBound in <int>[
      math.min(primaryMaxIndex, maxJoinIndex),
      math.min(expandedMaxIndex, maxJoinIndex),
      maxJoinIndex,
    ]) {
      if (best != null) break;
      for (var index = 0; index <= upperBound; index += step) {
        final candidate = _buildJoinPoint(
          currentPosition: currentPosition,
          coordinates: coordinates,
          cumulativeDistances: cumulativeDistances,
          totalDistanceMeters: totalDistanceMeters,
          index: index,
        );
        if (candidate.remainingDistanceMeters < minRemainingMeters) continue;
        if (best == null || candidate.score < best.score) {
          best = candidate;
        }
      }
    }

    if (maxJoinIndex != coordinates.length - 1) {
      final boundaryCandidate = _buildJoinPoint(
        currentPosition: currentPosition,
        coordinates: coordinates,
        cumulativeDistances: cumulativeDistances,
        totalDistanceMeters: totalDistanceMeters,
        index: maxJoinIndex,
      );
      if (best == null || boundaryCandidate.score < best.score) {
        best = boundaryCandidate;
      }
    }

    return best ??
        _buildJoinPoint(
          currentPosition: currentPosition,
          coordinates: coordinates,
          cumulativeDistances: cumulativeDistances,
          totalDistanceMeters: totalDistanceMeters,
          index: 0,
        );
  }

  RouteJoinPoint _buildJoinPoint({
    required geo.Position currentPosition,
    required List<List<double>> coordinates,
    required List<double> cumulativeDistances,
    required double totalDistanceMeters,
    required int index,
  }) {
    final point = coordinates[index];
    final distanceFromCurrentMeters = geo.Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      point[1],
      point[0],
    );
    final remainingDistanceMeters = math.max(
      0.0,
      totalDistanceMeters - cumulativeDistances[index],
    );
    final progressRatio = totalDistanceMeters <= 0
        ? 0.0
        : (cumulativeDistances[index] / totalDistanceMeters).clamp(0.0, 1.0);
    final localHeading = _localHeading(coordinates, index);
    final approachHeading = _bearing(
      currentPosition.latitude,
      currentPosition.longitude,
      point[1],
      point[0],
    );
    final headingDeltaDegrees = _angleDiff(approachHeading, localHeading).abs();

    const idealLowerBound = 0.06;
    const idealUpperBound = 0.30;
    const softUpperBound = 0.40;
    final progressPenalty = progressRatio < idealLowerBound
        ? (idealLowerBound - progressRatio) * 1800.0
        : progressRatio > softUpperBound
        ? (progressRatio - softUpperBound) * 4200.0
        : progressRatio > idealUpperBound
        ? (progressRatio - idealUpperBound) * 1200.0
        : 0.0;
    final remainingPenalty = remainingDistanceMeters < 900.0
        ? (900.0 - remainingDistanceMeters) * 1.8
        : 0.0;
    final headingPenalty = headingDeltaDegrees * 4.5;
    final reachabilityPenalty =
        distanceFromCurrentMeters < 140.0 && progressRatio > 0.22
        ? (0.22 - progressRatio).abs() * 200.0
        : 0.0;
    final score =
        distanceFromCurrentMeters +
        headingPenalty +
        progressPenalty +
        remainingPenalty +
        reachabilityPenalty;

    return RouteJoinPoint(
      index: index,
      coordinate: [point[0], point[1]],
      distanceFromCurrentMeters: distanceFromCurrentMeters,
      remainingDistanceMeters: remainingDistanceMeters,
      progressRatio: progressRatio,
      headingDeltaDegrees: headingDeltaDegrees,
      score: score,
    );
  }

  int _maxJoinIndexForRemainingDistance({
    required List<double> cumulativeDistances,
    required double totalDistanceMeters,
    required double minRemainingMeters,
  }) {
    for (var index = cumulativeDistances.length - 1; index >= 0; index--) {
      final remaining = totalDistanceMeters - cumulativeDistances[index];
      if (remaining >= minRemainingMeters) {
        return index;
      }
    }
    return math.max(0, cumulativeDistances.length - 2);
  }

  int _maxJoinIndexForProgress({
    required List<double> cumulativeDistances,
    required double totalDistanceMeters,
    required double maxProgressRatio,
  }) {
    if (totalDistanceMeters <= 0) {
      return math.max(0, cumulativeDistances.length - 2);
    }
    for (var index = cumulativeDistances.length - 1; index >= 0; index--) {
      final progress = cumulativeDistances[index] / totalDistanceMeters;
      if (progress <= maxProgressRatio) {
        return index;
      }
    }
    return math.max(0, cumulativeDistances.length - 2);
  }

  List<double> _buildCumulativeDistances(List<List<double>> coordinates) {
    final cumulative = List<double>.filled(coordinates.length, 0.0);
    for (var index = 1; index < coordinates.length; index++) {
      cumulative[index] =
          cumulative[index - 1] +
          geo.Geolocator.distanceBetween(
            coordinates[index - 1][1],
            coordinates[index - 1][0],
            coordinates[index][1],
            coordinates[index][0],
          );
    }
    return cumulative;
  }

  double _localHeading(List<List<double>> coordinates, int index) {
    final fromIndex = index <= 0 ? 0 : index - 1;
    final toIndex = index >= coordinates.length - 1 ? index : index + 1;
    if (fromIndex == toIndex) return 0.0;
    final from = coordinates[fromIndex];
    final to = coordinates[toIndex];
    return _bearing(from[1], from[0], to[1], to[0]);
  }

  double _bearing(double lat1, double lng1, double lat2, double lng2) {
    final lat1R = lat1 * math.pi / 180;
    final lat2R = lat2 * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2R);
    final x =
        math.cos(lat1R) * math.sin(lat2R) -
        math.sin(lat1R) * math.cos(lat2R) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  double _angleDiff(double from, double to) {
    var diff = (to - from) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }
}
