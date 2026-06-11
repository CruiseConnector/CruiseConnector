import 'dart:math' as math;

import 'package:geolocator/geolocator.dart' as geo;

bool shouldHoldRouteRenderLock({
  required DateTime now,
  required DateTime? lastAcceptedAt,
  required DateTime? offRouteSince,
  required bool routeConfirmed,
  required bool overviewActive,
  required bool hasLock,
  Duration holdDuration = const Duration(milliseconds: 1500),
}) {
  if (!routeConfirmed || overviewActive || !hasLock) return false;
  if (lastAcceptedAt == null) return false;
  if (now.difference(lastAcceptedAt) > holdDuration) return false;

  if (offRouteSince != null && now.difference(offRouteSince) > holdDuration) {
    return false;
  }
  return true;
}

/// Projected on-route render position for the navigation puck/camera/route trim.
class RouteRenderLockProjection {
  const RouteRenderLockProjection({
    required this.distanceM,
    required this.segmentIndex,
    required this.lateralMeters,
    required this.point,
  });

  /// Monotonic distance along the route in meters.
  final double distanceM;

  /// Segment containing [point].
  final int segmentIndex;

  /// Perpendicular distance from input GPS/smoother point to the route.
  final double lateralMeters;

  /// Projected route point as [longitude, latitude].
  final List<double> point;
}

class _RouteSearchWindow {
  const _RouteSearchWindow(this.from, this.to);

  final int from;
  final int to;
}

class _ProjectionSearchResult {
  const _ProjectionSearchResult({
    required this.segment,
    required this.distanceM,
    required this.lateralMeters,
  });

  final int segment;
  final double distanceM;
  final double lateralMeters;
}

/// Stateful on-route projector used while navigation is active.
///
/// The lock intentionally advances monotonically and searches by route meters,
/// not by segment count. GraphHopper point density varies a lot between dense
/// turns and long rural segments; a segment-count window can visibly freeze the
/// puck/line sync on real 1 Hz GPS.
class RouteRenderLock {
  RouteRenderLock({
    this.lateralMaxMeters = 30.0,
    this.behindWindowMeters = 90.0,
    this.minAheadWindowMeters = 220.0,
    this.maxAheadWindowMeters = 520.0,
  });

  final double lateralMaxMeters;
  final double behindWindowMeters;
  final double minAheadWindowMeters;
  final double maxAheadWindowMeters;

  List<List<double>>? _coordinates;
  List<double>? _cumulativeDistances;
  String _routeSignature = '';
  int _segmentIndex = 0;
  double _distanceM = -1.0;
  DateTime? _lastProjectionAt;

  List<double>? get cumulativeDistances => _cumulativeDistances;
  int get segmentIndex => _segmentIndex;
  double get distanceM => _distanceM;

  bool ensureRoute(List<List<double>> coordinates) {
    final signature = _routeSignatureFor(coordinates);
    if (identical(_coordinates, coordinates) && _routeSignature == signature) {
      return false;
    }
    _coordinates = coordinates;
    _routeSignature = signature;
    resetLock();
    if (coordinates.length < 2) {
      _cumulativeDistances = null;
      return true;
    }

    final cumulative = List<double>.filled(coordinates.length, 0.0);
    for (var i = 1; i < coordinates.length; i++) {
      cumulative[i] =
          cumulative[i - 1] +
          geo.Geolocator.distanceBetween(
            coordinates[i - 1][1],
            coordinates[i - 1][0],
            coordinates[i][1],
            coordinates[i][0],
          );
    }
    _cumulativeDistances = cumulative;
    return true;
  }

  String _routeSignatureFor(List<List<double>> coordinates) {
    final length = coordinates.length;
    if (length == 0) return '0';
    if (length == 1) return '1:${_pointSignature(coordinates.first)}';

    final sampleIndexes = <int>{
      0,
      length ~/ 4,
      length ~/ 2,
      (length * 3) ~/ 4,
      length - 1,
    };
    return [
      length,
      for (final index in sampleIndexes) _pointSignature(coordinates[index]),
    ].join('|');
  }

  String _pointSignature(List<double> point) {
    if (point.length < 2) return 'invalid';
    return '${point[0].toStringAsFixed(7)},${point[1].toStringAsFixed(7)}';
  }

  void resetLock() {
    _segmentIndex = 0;
    _distanceM = -1.0;
    _lastProjectionAt = null;
  }

  RouteRenderLockProjection? project({
    required List<List<double>> coordinates,
    required double latitude,
    required double longitude,
    required bool routeConfirmed,
    required int currentRouteIndex,
    required double speedMps,
    DateTime? timestamp,
  }) {
    if (coordinates.length < 2 || !routeConfirmed) return null;
    ensureRoute(coordinates);
    final cumulative = _cumulativeDistances;
    if (cumulative == null) return null;

    final cosLat = math.cos(latitude * math.pi / 180.0);
    final hasLock = _distanceM >= 0.0;
    final previousDistanceM = _distanceM;
    final previousSegmentIndex = _segmentIndex;
    var searchDistanceM = _distanceM;
    var searchSegmentIndex = _segmentIndex;
    if (hasLock && currentRouteIndex > _segmentIndex) {
      final idx = currentRouteIndex.clamp(0, cumulative.length - 1).toInt();
      final idxDist = cumulative[idx];
      if (idxDist > searchDistanceM + maxAheadWindowMeters) {
        searchSegmentIndex = math.min(idx, coordinates.length - 2);
        searchDistanceM = idxDist;
      }
    }

    final primaryWindow = _windowFor(
      coordinates: coordinates,
      cumulative: cumulative,
      centerDistanceM: searchDistanceM,
      centerSegmentIndex: searchSegmentIndex,
      speedMps: speedMps,
    );
    var best = _searchBestProjection(
      coordinates: coordinates,
      cumulative: cumulative,
      latitude: latitude,
      longitude: longitude,
      cosLat: cosLat,
      from: primaryWindow.from,
      to: primaryWindow.to,
    );
    final usedReanchorWindow =
        hasLock && searchSegmentIndex != previousSegmentIndex;
    if ((best.segment < 0 || best.lateralMeters > lateralMaxMeters) &&
        usedReanchorWindow) {
      final fallbackWindow = _windowFor(
        coordinates: coordinates,
        cumulative: cumulative,
        centerDistanceM: previousDistanceM,
        centerSegmentIndex: previousSegmentIndex,
        speedMps: speedMps,
      );
      best = _searchBestProjection(
        coordinates: coordinates,
        cumulative: cumulative,
        latitude: latitude,
        longitude: longitude,
        cosLat: cosLat,
        from: fallbackWindow.from,
        to: fallbackWindow.to,
      );
    }

    var bestDistanceM = best.distanceM;
    var bestSegment = best.segment;
    final lateralMeters = best.lateralMeters;
    if (bestSegment < 0 || lateralMeters > lateralMaxMeters) {
      return null;
    }

    if (hasLock && bestDistanceM < previousDistanceM) {
      bestDistanceM = previousDistanceM;
      bestSegment = previousSegmentIndex;
    }
    if (hasLock && timestamp != null && _lastProjectionAt != null) {
      final dtSeconds = math
          .max(
            0.0,
            timestamp.difference(_lastProjectionAt!).inMilliseconds / 1000.0,
          )
          .clamp(0.0, 2.0)
          .toDouble();
      final speed = speedMps.isFinite ? speedMps.clamp(0.0, 60.0) : 0.0;
      // Prevent visual teleports onto nearby future route legs. Real movement is
      // still followed continuously because this method is called per camera
      // frame. A real GPS pause gets up to two seconds of speed-scaled catch-up;
      // a normal 16ms frame is limited to a few meters, not a route-index jump.
      final maxForwardDistance =
          previousDistanceM + 2.0 + speed * dtSeconds * 2.2;
      if (bestDistanceM > maxForwardDistance) {
        bestDistanceM = maxForwardDistance;
        bestSegment = _segmentIndexForDistance(bestDistanceM);
      }
    }

    _segmentIndex = bestSegment;
    _distanceM = bestDistanceM;
    if (timestamp != null &&
        (_lastProjectionAt == null ||
            !timestamp.isBefore(_lastProjectionAt!))) {
      _lastProjectionAt = timestamp;
    }
    final point = pointAtDistance(bestDistanceM);
    if (point == null) return null;

    return RouteRenderLockProjection(
      distanceM: bestDistanceM,
      segmentIndex: bestSegment,
      lateralMeters: lateralMeters,
      point: point,
    );
  }

  _RouteSearchWindow _windowFor({
    required List<List<double>> coordinates,
    required List<double> cumulative,
    required double centerDistanceM,
    required int centerSegmentIndex,
    required double speedMps,
  }) {
    if (centerDistanceM < 0.0) {
      return _RouteSearchWindow(0, coordinates.length - 1);
    }

    final speed = speedMps.isFinite ? speedMps.clamp(0.0, 45.0) : 0.0;
    final aheadWindow = (80.0 + speed * 8.0)
        .clamp(minAheadWindowMeters, maxAheadWindowMeters)
        .toDouble();
    final behindDist = centerDistanceM - behindWindowMeters;
    final aheadDist = centerDistanceM + aheadWindow;

    var from = centerSegmentIndex.clamp(0, coordinates.length - 2).toInt();
    while (from > 0 && cumulative[from] > behindDist) {
      from--;
    }

    var to = centerSegmentIndex.clamp(0, coordinates.length - 2).toInt();
    while (to < coordinates.length - 1 && cumulative[to] < aheadDist) {
      to++;
    }
    to = math.max(from + 1, math.min(to, coordinates.length - 1));
    return _RouteSearchWindow(from, to);
  }

  _ProjectionSearchResult _searchBestProjection({
    required List<List<double>> coordinates,
    required List<double> cumulative,
    required double latitude,
    required double longitude,
    required double cosLat,
    required int from,
    required int to,
  }) {
    var bestLateral2 = double.infinity;
    var bestDistanceM = -1.0;
    var bestSegment = -1;
    for (var i = from; i < to; i++) {
      final ax = (coordinates[i][0] - longitude) * 111320.0 * cosLat;
      final ay = (coordinates[i][1] - latitude) * 110540.0;
      final bx = (coordinates[i + 1][0] - longitude) * 111320.0 * cosLat;
      final by = (coordinates[i + 1][1] - latitude) * 110540.0;
      final dx = bx - ax;
      final dy = by - ay;
      final len2 = dx * dx + dy * dy;
      var t = 0.0;
      if (len2 > 1e-9) {
        t = (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
      }
      final px = ax + dx * t;
      final py = ay + dy * t;
      final lateral2 = px * px + py * py;
      if (lateral2 < bestLateral2) {
        bestLateral2 = lateral2;
        bestSegment = i;
        bestDistanceM = cumulative[i] + math.sqrt(len2) * t;
      }
    }

    return _ProjectionSearchResult(
      segment: bestSegment,
      distanceM: bestDistanceM,
      lateralMeters: math.sqrt(bestLateral2),
    );
  }

  int _segmentIndexForDistance(double distanceM) {
    final cumulative = _cumulativeDistances;
    final coordinates = _coordinates;
    if (cumulative == null || coordinates == null || coordinates.length < 2) {
      return _segmentIndex;
    }
    if (distanceM <= 0.0) return 0;
    if (distanceM >= cumulative.last) return coordinates.length - 2;

    var i = _segmentIndex.clamp(0, coordinates.length - 2);
    if (cumulative[i] > distanceM) i = 0;
    while (i < coordinates.length - 2 && cumulative[i + 1] < distanceM) {
      i++;
    }
    return i;
  }

  List<double>? pointAtDistance(double distanceM) {
    final coordinates = _coordinates;
    final cumulative = _cumulativeDistances;
    if (coordinates == null ||
        coordinates.length < 2 ||
        cumulative == null ||
        cumulative.length != coordinates.length) {
      return null;
    }
    if (distanceM <= 0.0) {
      return [coordinates.first[0], coordinates.first[1]];
    }
    if (distanceM >= cumulative.last) {
      return [coordinates.last[0], coordinates.last[1]];
    }

    var i = _segmentIndex.clamp(0, coordinates.length - 2);
    if (cumulative[i] > distanceM) i = 0;
    while (i < coordinates.length - 2 && cumulative[i + 1] < distanceM) {
      i++;
    }

    final segmentLen = cumulative[i + 1] - cumulative[i];
    final f = segmentLen > 0.0
        ? ((distanceM - cumulative[i]) / segmentLen).clamp(0.0, 1.0)
        : 0.0;
    return [
      coordinates[i][0] + (coordinates[i + 1][0] - coordinates[i][0]) * f,
      coordinates[i][1] + (coordinates[i + 1][1] - coordinates[i][1]) * f,
    ];
  }
}
