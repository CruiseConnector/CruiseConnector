import 'dart:math' as math;

import 'package:geolocator/geolocator.dart' as geo;

import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:cruise_connect/data/services/route_quality_validator.dart';

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
    required this.sessionRoute,
    required this.joinPoint,
    required this.logicalOrigin,
    required this.logicalEnd,
    required this.sessionOrigin,
    required this.sessionEnd,
    required this.joinPointType,
    required this.routeStartDistanceMeters,
    required this.routePassesNearUser,
    required this.routeRebasedToUser,
    this.accessLeg,
    this.returnLeg,
  });

  final RouteResult originalRoute;
  final RouteResult activeRoute;
  final RouteResult followOnRoute;
  final RouteResult sessionRoute;
  final RouteJoinPoint joinPoint;
  final RouteResult? accessLeg;
  final RouteResult? returnLeg;
  final List<double> logicalOrigin;
  final List<double> logicalEnd;
  final List<double> sessionOrigin;
  final List<double> sessionEnd;
  final String joinPointType;
  final double routeStartDistanceMeters;
  final bool routePassesNearUser;
  final bool routeRebasedToUser;

  bool get hasAccessLeg => accessLeg != null;
  bool get hasReturnLeg => returnLeg != null;
}

class RouteAccessPlanner {
  const RouteAccessPlanner();

  static const double directJoinDistanceMeters = 60.0;
  static const double nearbyPassJoinDistanceMeters = 160.0;
  static const double closedLoopEndpointDistanceMeters = 80.0;
  static const double _onRouteJoinDistanceMeters = directJoinDistanceMeters;
  static const double _closedLoopEndpointDistanceMeters =
      closedLoopEndpointDistanceMeters;
  static const int _maxSuggestedJoinPoints = 4;

  RouteJoinPoint chooseJoinPoint({
    required geo.Position currentPosition,
    required RouteResult existingRoute,
    int? preferredJoinIndex,
    bool rebaseClosedLoop = false,
  }) {
    return suggestJoinPoints(
      currentPosition: currentPosition,
      existingRoute: existingRoute,
      preferredJoinIndex: preferredJoinIndex,
      maxCandidates: 1,
      rebaseClosedLoop: rebaseClosedLoop,
    ).first;
  }

  List<RouteJoinPoint> suggestJoinPoints({
    required geo.Position currentPosition,
    required RouteResult existingRoute,
    int? preferredJoinIndex,
    int maxCandidates = _maxSuggestedJoinPoints,
    bool rebaseClosedLoop = false,
  }) {
    final coordinates = existingRoute.coordinates;
    if (coordinates.length < 2) {
      throw ArgumentError('Existing route requires at least 2 coordinates.');
    }

    final cumulativeDistances = _buildCumulativeDistances(coordinates);
    final totalDistanceMeters = cumulativeDistances.last;
    final deadEndSpikes = RouteQualityValidator.detectDeadEndSpikes(
      coordinates,
    );
    final closedLoop = _isClosedLoop(coordinates);
    final rebaseClosedLoopMode = rebaseClosedLoop && closedLoop;
    final cappedPreferred = preferredJoinIndex?.clamp(
      0,
      coordinates.length - 1,
    );
    if (cappedPreferred != null) {
      return [
        _buildJoinPoint(
          currentPosition: currentPosition,
          coordinates: coordinates,
          cumulativeDistances: cumulativeDistances,
          totalDistanceMeters: totalDistanceMeters,
          deadEndSpikes: deadEndSpikes,
          closedLoop: closedLoop,
          rebaseClosedLoop: rebaseClosedLoopMode,
          index: cappedPreferred,
        ),
      ];
    }

    final suggestions = <RouteJoinPoint>[];
    void addSuggestion(RouteJoinPoint candidate) {
      final alreadyCovered = suggestions.any(
        (existing) => (existing.index - candidate.index).abs() <= 2,
      );
      if (alreadyCovered) return;
      suggestions.add(candidate);
      suggestions.sort((left, right) => left.score.compareTo(right.score));
      if (suggestions.length > maxCandidates) {
        suggestions.removeRange(maxCandidates, suggestions.length);
      }
    }

    if (closedLoop && !rebaseClosedLoopMode) {
      final startJoinPoint = _buildJoinPoint(
        currentPosition: currentPosition,
        coordinates: coordinates,
        cumulativeDistances: cumulativeDistances,
        totalDistanceMeters: totalDistanceMeters,
        deadEndSpikes: deadEndSpikes,
        closedLoop: closedLoop,
        rebaseClosedLoop: rebaseClosedLoopMode,
        index: 0,
      );
      if (startJoinPoint.distanceFromCurrentMeters <=
          _closedLoopEndpointDistanceMeters) {
        addSuggestion(startJoinPoint);
      }
    }

    final onRouteJoinPoint = _nearestOnRouteJoinPoint(
      currentPosition: currentPosition,
      coordinates: coordinates,
      cumulativeDistances: cumulativeDistances,
      totalDistanceMeters: totalDistanceMeters,
      closedLoop: closedLoop,
      deadEndSpikes: deadEndSpikes,
      rebaseClosedLoop: rebaseClosedLoopMode,
    );
    if (onRouteJoinPoint != null) {
      addSuggestion(onRouteJoinPoint);
    }

    final minRemainingMeters = rebaseClosedLoopMode
        ? math.max(900.0, totalDistanceMeters * 0.22)
        : math.max(900.0, totalDistanceMeters * 0.14);
    final maxJoinIndex = _maxJoinIndexForRemainingDistance(
      cumulativeDistances: cumulativeDistances,
      totalDistanceMeters: totalDistanceMeters,
      minRemainingMeters: minRemainingMeters,
    );
    if (rebaseClosedLoopMode) {
      final step = math.max(1, coordinates.length ~/ 30);
      for (
        var index = 0;
        index < math.max(1, coordinates.length - 1);
        index += step
      ) {
        final candidate = _buildJoinPoint(
          currentPosition: currentPosition,
          coordinates: coordinates,
          cumulativeDistances: cumulativeDistances,
          totalDistanceMeters: totalDistanceMeters,
          deadEndSpikes: deadEndSpikes,
          closedLoop: closedLoop,
          rebaseClosedLoop: rebaseClosedLoopMode,
          index: index,
        );
        addSuggestion(candidate);
      }
      if (suggestions.isEmpty) {
        suggestions.add(
          _buildJoinPoint(
            currentPosition: currentPosition,
            coordinates: coordinates,
            cumulativeDistances: cumulativeDistances,
            totalDistanceMeters: totalDistanceMeters,
            deadEndSpikes: deadEndSpikes,
            closedLoop: closedLoop,
            rebaseClosedLoop: rebaseClosedLoopMode,
            index: 0,
          ),
        );
      }
      return suggestions.take(maxCandidates).toList(growable: false);
    }
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
    final upperBounds = <int>[
      math.min(primaryMaxIndex, maxJoinIndex),
      math.min(expandedMaxIndex, maxJoinIndex),
      maxJoinIndex,
    ];

    for (final upperBound in upperBounds) {
      for (var index = 0; index <= upperBound; index += step) {
        final candidate = _buildJoinPoint(
          currentPosition: currentPosition,
          coordinates: coordinates,
          cumulativeDistances: cumulativeDistances,
          totalDistanceMeters: totalDistanceMeters,
          deadEndSpikes: deadEndSpikes,
          closedLoop: closedLoop,
          rebaseClosedLoop: rebaseClosedLoopMode,
          index: index,
        );
        if (candidate.remainingDistanceMeters < minRemainingMeters) continue;
        addSuggestion(candidate);
      }
      if (suggestions.isNotEmpty) break;
    }

    if (maxJoinIndex != coordinates.length - 1) {
      final boundaryCandidate = _buildJoinPoint(
        currentPosition: currentPosition,
        coordinates: coordinates,
        cumulativeDistances: cumulativeDistances,
        totalDistanceMeters: totalDistanceMeters,
        deadEndSpikes: deadEndSpikes,
        closedLoop: closedLoop,
        rebaseClosedLoop: rebaseClosedLoopMode,
        index: maxJoinIndex,
      );
      addSuggestion(boundaryCandidate);
    }

    if (suggestions.isEmpty) {
      suggestions.add(
        _buildJoinPoint(
          currentPosition: currentPosition,
          coordinates: coordinates,
          cumulativeDistances: cumulativeDistances,
          totalDistanceMeters: totalDistanceMeters,
          deadEndSpikes: deadEndSpikes,
          closedLoop: closedLoop,
          rebaseClosedLoop: rebaseClosedLoopMode,
          index: 0,
        ),
      );
    }

    return suggestions.take(maxCandidates).toList(growable: false);
  }

  RouteJoinPoint _buildJoinPoint({
    required geo.Position currentPosition,
    required List<List<double>> coordinates,
    required List<double> cumulativeDistances,
    required double totalDistanceMeters,
    required List<RouteDeadEndSpike> deadEndSpikes,
    required bool closedLoop,
    required bool rebaseClosedLoop,
    required int index,
  }) {
    final point = coordinates[index];
    final distanceFromCurrentMeters = geo.Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      point[1],
      point[0],
    );
    final routeRemainingDistanceMeters = math.max(
      0.0,
      totalDistanceMeters - cumulativeDistances[index],
    );
    final remainingDistanceMeters = rebaseClosedLoop && closedLoop
        ? totalDistanceMeters
        : routeRemainingDistanceMeters;
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

    final progressPenalty = rebaseClosedLoop && closedLoop
        ? (progressRatio < 0.04
              ? (0.04 - progressRatio) * 3200.0
              : progressRatio > 0.96
              ? (progressRatio - 0.96) * 3200.0
              : 0.0)
        : (progressRatio < 0.06
              ? (0.06 - progressRatio) * 1800.0
              : progressRatio > 0.40
              ? (progressRatio - 0.40) * 4200.0
              : progressRatio > 0.30
              ? (progressRatio - 0.30) * 1200.0
              : 0.0);
    final remainingPenalty = rebaseClosedLoop && closedLoop
        ? 0.0
        : remainingDistanceMeters < 900.0
        ? (900.0 - remainingDistanceMeters) * 1.8
        : 0.0;
    final headingPenalty = headingDeltaDegrees * 4.5;
    final reachabilityPenalty =
        !rebaseClosedLoop &&
            distanceFromCurrentMeters < 140.0 &&
            progressRatio > 0.22
        ? (0.22 - progressRatio).abs() * 200.0
        : 0.0;
    final deadEndPenalty =
        deadEndSpikes.any((spike) => spike.containsIndex(index)) ? 2600.0 : 0.0;
    final score =
        distanceFromCurrentMeters +
        headingPenalty +
        progressPenalty +
        remainingPenalty +
        reachabilityPenalty +
        deadEndPenalty;

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

  RouteJoinPoint? _nearestOnRouteJoinPoint({
    required geo.Position currentPosition,
    required List<List<double>> coordinates,
    required List<double> cumulativeDistances,
    required double totalDistanceMeters,
    required bool closedLoop,
    required List<RouteDeadEndSpike> deadEndSpikes,
    required bool rebaseClosedLoop,
  }) {
    RouteJoinPoint? nearest;
    final joinDistanceThreshold = rebaseClosedLoop
        ? nearbyPassJoinDistanceMeters
        : _onRouteJoinDistanceMeters;
    for (var index = 0; index < coordinates.length; index++) {
      if (closedLoop && index == coordinates.length - 1) continue;
      final candidate = _buildJoinPoint(
        currentPosition: currentPosition,
        coordinates: coordinates,
        cumulativeDistances: cumulativeDistances,
        totalDistanceMeters: totalDistanceMeters,
        deadEndSpikes: deadEndSpikes,
        closedLoop: closedLoop,
        rebaseClosedLoop: rebaseClosedLoop,
        index: index,
      );
      if (candidate.distanceFromCurrentMeters > joinDistanceThreshold) {
        continue;
      }
      if (nearest == null ||
          candidate.distanceFromCurrentMeters <
              nearest.distanceFromCurrentMeters) {
        nearest = candidate;
      }
    }
    return nearest;
  }

  bool _isClosedLoop(List<List<double>> coordinates) {
    if (coordinates.length < 3) return false;
    final first = coordinates.first;
    final last = coordinates.last;
    return geo.Geolocator.distanceBetween(
          first[1],
          first[0],
          last[1],
          last[0],
        ) <=
        _closedLoopEndpointDistanceMeters;
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
