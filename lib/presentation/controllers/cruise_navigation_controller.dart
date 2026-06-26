import 'package:cruise_connect/data/services/geo_distance.dart';
import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/presentation/widgets/cruise/nav_distance_format.dart';

/// Pure navigation-HUD coordinator for CruiseModePage.
///
/// It owns only the small mutable display smoothing state. GPS intake,
/// rerouting, rendering, and persistence remain in the page while this class
/// centralizes active maneuver selection and distance calculation.
class CruiseNavigationController {
  double? _shownManeuverDistM;
  int? _shownManeuverSig;
  DateTime? _shownManeuverAt;

  void clearManeuverDistanceSmoothing() {
    _shownManeuverDistM = null;
    _shownManeuverSig = null;
    _shownManeuverAt = null;
  }

  int? activeVisibleManeuverIndex({
    required List<RouteManeuver> maneuvers,
    required int currentRouteIndex,
    required int activeManeuverIndex,
    required double? remainingRouteDistanceMeters,
    required double? distanceToFinalTargetMeters,
    required double arrivalRadiusMeters,
  }) {
    return selectActiveGuidanceManeuverIndex(
      maneuvers: maneuvers,
      currentRouteIndex: currentRouteIndex,
      remainingRouteDistanceMeters: remainingRouteDistanceMeters,
      distanceToFinalTargetMeters: distanceToFinalTargetMeters,
      startIndex: activeManeuverIndex,
      arrivalRadiusMeters: arrivalRadiusMeters,
    );
  }

  RouteManeuver? activeVisibleManeuver({
    required List<RouteManeuver> maneuvers,
    required int currentRouteIndex,
    required int activeManeuverIndex,
    required double? remainingRouteDistanceMeters,
    required double? distanceToFinalTargetMeters,
    required double arrivalRadiusMeters,
  }) {
    final index = activeVisibleManeuverIndex(
      maneuvers: maneuvers,
      currentRouteIndex: currentRouteIndex,
      activeManeuverIndex: activeManeuverIndex,
      remainingRouteDistanceMeters: remainingRouteDistanceMeters,
      distanceToFinalTargetMeters: distanceToFinalTargetMeters,
      arrivalRadiusMeters: arrivalRadiusMeters,
    );
    if (index == null) return null;
    return maneuvers[index.clamp(0, maneuvers.length - 1).toInt()];
  }

  double? calculateDistanceToManeuver({
    required List<RouteManeuver> maneuvers,
    required List<List<double>> routeCoordinates,
    required int currentRouteIndex,
    required int activeManeuverIndex,
    required double? remainingRouteDistanceMeters,
    required double? distanceToFinalTargetMeters,
    required double arrivalRadiusMeters,
    required double offRouteGapMeters,
    RouteManeuver? visibleManeuver,
  }) {
    if (maneuvers.isEmpty || routeCoordinates.length < 2) return null;
    final maneuver =
        visibleManeuver ??
        activeVisibleManeuver(
          maneuvers: maneuvers,
          currentRouteIndex: currentRouteIndex,
          activeManeuverIndex: activeManeuverIndex,
          remainingRouteDistanceMeters: remainingRouteDistanceMeters,
          distanceToFinalTargetMeters: distanceToFinalTargetMeters,
          arrivalRadiusMeters: arrivalRadiusMeters,
        );
    if (maneuver == null) return null;

    var targetIndex = maneuver.routeIndex
        .clamp(0, routeCoordinates.length - 1)
        .toInt();
    if (targetIndex <= currentRouteIndex) {
      var nextIdx = -1;
      for (final m in maneuvers) {
        final mi = m.routeIndex.clamp(0, routeCoordinates.length - 1).toInt();
        if (mi > currentRouteIndex) {
          nextIdx = mi;
          break;
        }
      }
      if (nextIdx < 0) return offRouteGapMeters > 0 ? offRouteGapMeters : 0;
      targetIndex = nextIdx;
    }

    var distance = 0.0;
    for (var i = currentRouteIndex; i < targetIndex; i++) {
      distance += GeoDistance.lngLatDistanceMeters(
        routeCoordinates[i],
        routeCoordinates[i + 1],
      );
    }
    return distance + offRouteGapMeters;
  }

  double? smoothManeuverDistanceTargetMeters({
    required List<RouteManeuver> maneuvers,
    required List<List<double>> routeCoordinates,
    required int currentRouteIndex,
    required int activeManeuverIndex,
    required double? remainingRouteDistanceMeters,
    required double? distanceToFinalTargetMeters,
    required double arrivalRadiusMeters,
    required double offRouteGapMeters,
    required List<double>? cumulativeDistancesMeters,
    required double renderLockDistanceMeters,
    RouteManeuver? visibleManeuver,
  }) {
    final base = calculateDistanceToManeuver(
      maneuvers: maneuvers,
      routeCoordinates: routeCoordinates,
      currentRouteIndex: currentRouteIndex,
      activeManeuverIndex: activeManeuverIndex,
      remainingRouteDistanceMeters: remainingRouteDistanceMeters,
      distanceToFinalTargetMeters: distanceToFinalTargetMeters,
      arrivalRadiusMeters: arrivalRadiusMeters,
      offRouteGapMeters: offRouteGapMeters,
      visibleManeuver: visibleManeuver,
    );
    if (base == null) return null;
    final cum = cumulativeDistancesMeters;
    return cum == null
        ? base
        : smoothManeuverDistanceMeters(
            base: base,
            cum: cum,
            render: renderLockDistanceMeters,
            currentIndex: currentRouteIndex,
          );
  }

  double? displayManeuverDistanceMeters({
    required List<RouteManeuver> maneuvers,
    required List<List<double>> routeCoordinates,
    required int currentRouteIndex,
    required int activeManeuverIndex,
    required double? remainingRouteDistanceMeters,
    required double? distanceToFinalTargetMeters,
    required double arrivalRadiusMeters,
    required double offRouteGapMeters,
    required List<double>? cumulativeDistancesMeters,
    required double renderLockDistanceMeters,
    RouteManeuver? visibleManeuver,
    DateTime? now,
  }) {
    final raw = smoothManeuverDistanceTargetMeters(
      maneuvers: maneuvers,
      routeCoordinates: routeCoordinates,
      currentRouteIndex: currentRouteIndex,
      activeManeuverIndex: activeManeuverIndex,
      remainingRouteDistanceMeters: remainingRouteDistanceMeters,
      distanceToFinalTargetMeters: distanceToFinalTargetMeters,
      arrivalRadiusMeters: arrivalRadiusMeters,
      offRouteGapMeters: offRouteGapMeters,
      cumulativeDistancesMeters: cumulativeDistancesMeters,
      renderLockDistanceMeters: renderLockDistanceMeters,
      visibleManeuver: visibleManeuver,
    );
    if (raw == null) {
      clearManeuverDistanceSmoothing();
      return null;
    }

    final sig =
        (visibleManeuver ??
                activeVisibleManeuver(
                  maneuvers: maneuvers,
                  currentRouteIndex: currentRouteIndex,
                  activeManeuverIndex: activeManeuverIndex,
                  remainingRouteDistanceMeters: remainingRouteDistanceMeters,
                  distanceToFinalTargetMeters: distanceToFinalTargetMeters,
                  arrivalRadiusMeters: arrivalRadiusMeters,
                ))
            ?.routeIndex ??
        activeManeuverIndex;
    final currentTime = now ?? DateTime.now();
    final sameManeuver = _shownManeuverSig == sig;
    final lastAt = _shownManeuverAt;
    if (sameManeuver &&
        _shownManeuverDistM != null &&
        lastAt != null &&
        currentTime.difference(lastAt).inMilliseconds < 16) {
      return _shownManeuverDistM;
    }

    final shown = monotonicManeuverDistanceMeters(
      prevShown: sameManeuver ? _shownManeuverDistM : null,
      target: raw,
      maneuverChanged: !sameManeuver,
      dtMs: (!sameManeuver || lastAt == null)
          ? 90
          : currentTime.difference(lastAt).inMilliseconds,
    );
    _shownManeuverSig = sig;
    _shownManeuverDistM = shown;
    _shownManeuverAt = currentTime;
    return shown;
  }

  int activeManeuverIndexForProgress({
    required List<RouteManeuver> maneuvers,
    required int currentRouteIndex,
    required int fallbackIndex,
  }) {
    if (maneuvers.isEmpty) return fallbackIndex;
    for (var i = 0; i < maneuvers.length; i++) {
      if (maneuvers[i].routeIndex >= currentRouteIndex) return i;
    }
    return maneuvers.length - 1;
  }
}
