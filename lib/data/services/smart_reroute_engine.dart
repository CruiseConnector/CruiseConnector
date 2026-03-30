import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;

import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

enum SmartRerouteStrategy {
  motorwayExit,
  roundabout,
  forwardTurn,
  forwardRejoin,
}

class SmartReroutePlan {
  const SmartReroutePlan({
    required this.anchorCoordinate,
    required this.rejoinIndex,
    required this.strategy,
    required this.debugLabel,
    this.mergeWithOriginal = true,
  });

  final List<double> anchorCoordinate;
  final int rejoinIndex;
  final SmartRerouteStrategy strategy;
  final String debugLabel;
  final bool mergeWithOriginal;
}

class SmartRerouteEngine {
  const SmartRerouteEngine();

  SmartReroutePlan createPlan({
    required geo.Position currentPosition,
    required List<List<double>> coordinates,
    required List<RouteManeuver> maneuvers,
    required int nearestIndex,
    required double currentHeadingDegrees,
    required List<SpeedLimitSegment> speedLimits,
  }) {
    if (coordinates.length < 2) {
      return const SmartReroutePlan(
        anchorCoordinate: [0, 0],
        rejoinIndex: 0,
        strategy: SmartRerouteStrategy.forwardRejoin,
        debugLabel: 'fallback_empty_route',
      );
    }

    final onMotorway = _isLikelyOnMotorway(
      routeIndex: nearestIndex,
      maneuvers: maneuvers,
      speedLimits: speedLimits,
    );

    if (onMotorway) {
      final exit = _findNextHighwayExit(
        currentPosition: currentPosition,
        maneuvers: maneuvers,
        minimumRouteIndex: nearestIndex + 24,
      );
      if (exit != null) {
        return SmartReroutePlan(
          anchorCoordinate: [exit.longitude, exit.latitude],
          rejoinIndex: exit.routeIndex.clamp(0, coordinates.length - 1),
          strategy: SmartRerouteStrategy.motorwayExit,
          debugLabel: 'next_motorway_exit',
        );
      }
    }

    final roundabout = _findNearbyRoundabout(
      currentPosition: currentPosition,
      maneuvers: maneuvers,
      minimumRouteIndex: nearestIndex + 12,
    );
    if (roundabout != null) {
      return SmartReroutePlan(
        anchorCoordinate: [roundabout.longitude, roundabout.latitude],
        rejoinIndex: roundabout.routeIndex.clamp(0, coordinates.length - 1),
        strategy: SmartRerouteStrategy.roundabout,
        debugLabel: 'nearby_roundabout',
      );
    }

    final forwardTurn = _findForwardTurn(
      currentPosition: currentPosition,
      maneuvers: maneuvers,
      minimumRouteIndex: nearestIndex + 18,
      currentHeadingDegrees: currentHeadingDegrees,
    );
    if (forwardTurn != null) {
      return SmartReroutePlan(
        anchorCoordinate: [forwardTurn.longitude, forwardTurn.latitude],
        rejoinIndex: forwardTurn.routeIndex.clamp(0, coordinates.length - 1),
        strategy: SmartRerouteStrategy.forwardTurn,
        debugLabel: 'forward_turn_point',
      );
    }

    final rejoinIndex = selectForwardRejoinIndex(
      coordinates: coordinates,
      nearestIndex: nearestIndex,
      currentHeadingDegrees: currentHeadingDegrees,
      minLookAheadPoints: onMotorway ? 140 : 90,
      maxLookAheadPoints: onMotorway ? 420 : 320,
      maxAlignmentDeltaDegrees: onMotorway ? 120 : 100,
    ).clamp(0, coordinates.length - 1);

    return SmartReroutePlan(
      anchorCoordinate: coordinates[rejoinIndex],
      rejoinIndex: rejoinIndex,
      strategy: SmartRerouteStrategy.forwardRejoin,
      debugLabel: 'forward_rejoin',
    );
  }

  bool _isLikelyOnMotorway({
    required int routeIndex,
    required List<RouteManeuver> maneuvers,
    required List<SpeedLimitSegment> speedLimits,
  }) {
    final speedLimit = _speedLimitAtIndex(speedLimits, routeIndex);
    if (speedLimit != null && speedLimit >= 90) {
      return true;
    }

    for (final maneuver in maneuvers) {
      if (maneuver.routeIndex < routeIndex) continue;
      if (maneuver.routeIndex > routeIndex + 120) break;
      final text = maneuver.instruction.toLowerCase();
      if (text.contains('autobahn') ||
          text.contains('ausfahrt') ||
          text.contains('abfahrt')) {
        return true;
      }
    }

    return false;
  }

  int? _speedLimitAtIndex(List<SpeedLimitSegment> speedLimits, int routeIndex) {
    for (final segment in speedLimits) {
      if (routeIndex >= segment.startIndex && routeIndex <= segment.endIndex) {
        return segment.speedKmh;
      }
    }
    return null;
  }

  RouteManeuver? _findNextHighwayExit({
    required geo.Position currentPosition,
    required List<RouteManeuver> maneuvers,
    required int minimumRouteIndex,
  }) {
    for (final maneuver in maneuvers) {
      if (maneuver.routeIndex < minimumRouteIndex) continue;
      final text = maneuver.instruction.toLowerCase();
      if (!_isExitInstruction(text)) continue;

      final distance = geo.Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        maneuver.latitude,
        maneuver.longitude,
      );
      if (distance >= 250) {
        return maneuver;
      }
    }
    return null;
  }

  RouteManeuver? _findNearbyRoundabout({
    required geo.Position currentPosition,
    required List<RouteManeuver> maneuvers,
    required int minimumRouteIndex,
  }) {
    for (final maneuver in maneuvers) {
      if (maneuver.routeIndex < minimumRouteIndex) continue;
      final isRoundabout =
          maneuver.maneuverType == ManeuverType.roundabout ||
          maneuver.instruction.toLowerCase().contains('kreisverkehr');
      if (!isRoundabout) continue;

      final distance = geo.Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        maneuver.latitude,
        maneuver.longitude,
      );
      if (distance <= 500) {
        return maneuver;
      }
    }
    return null;
  }

  RouteManeuver? _findForwardTurn({
    required geo.Position currentPosition,
    required List<RouteManeuver> maneuvers,
    required int minimumRouteIndex,
    required double currentHeadingDegrees,
  }) {
    for (final maneuver in maneuvers) {
      if (maneuver.routeIndex < minimumRouteIndex) continue;
      if (!_isUsefulTurnManeuver(maneuver)) continue;

      final distance = geo.Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        maneuver.latitude,
        maneuver.longitude,
      );
      if (distance < 180) continue;

      final bearing = bearingFromCoordinates(
        [currentPosition.longitude, currentPosition.latitude],
        [maneuver.longitude, maneuver.latitude],
      );
      if (headingDeltaDegrees(currentHeadingDegrees, bearing) <= 120) {
        return maneuver;
      }
    }
    return null;
  }

  bool _isExitInstruction(String text) {
    return text.contains('ausfahrt') ||
        text.contains('abfahrt') ||
        text.contains('exit');
  }

  bool _isUsefulTurnManeuver(RouteManeuver maneuver) {
    if (maneuver.icon == Icons.flag || maneuver.icon == Icons.straight) {
      return false;
    }

    if (maneuver.maneuverType == ManeuverType.roundabout) {
      return false;
    }

    final text = maneuver.instruction.toLowerCase();
    if (text.contains('weiterfahren')) {
      return false;
    }

    return true;
  }
}
