import 'dart:async';
import 'dart:convert';

import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CarRouteStatus {
  const CarRouteStatus._();

  static const idle = 'idle';
  static const searching = 'searching';
  static const found = 'found';
  static const navigating = 'navigating';
  static const ended = 'ended';
  static const failed = 'failed';
}

class CarRouteType {
  const CarRouteType._();

  static const roundtrip = 'roundtrip';
  static const pointToPoint = 'point_to_point';
  static const waypoints = 'waypoints';
}

class CarRouteBridgeService {
  static const snapshotKey = 'car_route_snapshot';
  static const progressKey = 'car_route_progress_snapshot';
  static const _progressThrottle = Duration(seconds: 3);

  SharedPreferences? _preferences;
  DateTime? _lastProgressWrite;

  Future<void> publishSearching({
    required String routeType,
    required String style,
    required bool avoidHighways,
  }) async {
    await _writeSnapshot({
      'status': CarRouteStatus.searching,
      'routeType': routeType,
      'style': style,
      'avoidHighways': avoidHighways,
      'searchMessage': 'Route wird berechnet',
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> publishFound({
    required RouteResult result,
    required String routeType,
    required String style,
    required bool avoidHighways,
  }) async {
    await _writeSnapshot(
      _snapshotFromRoute(
        result: result,
        routeType: routeType,
        status: CarRouteStatus.found,
        style: style,
        avoidHighways: avoidHighways,
      ),
    );
    await _clearProgress();
  }

  Future<void> publishNavigationStarted({
    required RouteResult result,
    required String routeType,
    required String style,
    required bool avoidHighways,
    double? remainingDistanceMeters,
    double? remainingDurationSeconds,
    String? nextManeuverText,
    double? nextManeuverDistance,
  }) async {
    await _writeSnapshot(
      _snapshotFromRoute(
        result: result,
        routeType: routeType,
        status: CarRouteStatus.navigating,
        style: style,
        avoidHighways: avoidHighways,
        remainingDistanceMeters: remainingDistanceMeters,
        remainingDurationSeconds: remainingDurationSeconds,
        nextManeuverText: nextManeuverText,
        nextManeuverDistance: nextManeuverDistance,
      ),
    );
  }

  Future<void> publishProgress({
    required double? remainingDistanceMeters,
    required double? remainingDurationSeconds,
    required String? nextManeuverText,
    required double? nextManeuverDistance,
    bool force = false,
  }) async {
    final now = DateTime.now();
    if (!force &&
        _lastProgressWrite != null &&
        now.difference(_lastProgressWrite!) < _progressThrottle) {
      return;
    }
    _lastProgressWrite = now;
    await _writeProgress({
      'status': CarRouteStatus.navigating,
      'remainingDistanceMeters': remainingDistanceMeters,
      'remainingDurationSeconds': remainingDurationSeconds,
      'nextManeuverText': nextManeuverText,
      'nextManeuverDistance': nextManeuverDistance,
      'updatedAt': now.toIso8601String(),
    });
  }

  Future<void> publishEnded() async {
    await _writeSnapshot({
      'status': CarRouteStatus.ended,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await _clearProgress();
  }

  Future<void> publishFailed({String? message}) async {
    await _writeSnapshot({
      'status': CarRouteStatus.failed,
      'errorMessage': message,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await _clearProgress();
  }

  Map<String, dynamic> _snapshotFromRoute({
    required RouteResult result,
    required String routeType,
    required String status,
    required String style,
    required bool avoidHighways,
    double? remainingDistanceMeters,
    double? remainingDurationSeconds,
    String? nextManeuverText,
    double? nextManeuverDistance,
  }) {
    final edgeMeta = result.edgeMeta;
    final fingerprint =
        edgeMeta['routeFingerprint'] ??
        edgeMeta['route_fingerprint'] ??
        edgeMeta['fingerprint'];
    final routeId =
        edgeMeta['route_id'] ??
        edgeMeta['pool_route_id'] ??
        edgeMeta['pool_match_id'] ??
        fingerprint;

    return {
      'routeId': routeId?.toString(),
      'fingerprint': fingerprint?.toString(),
      'routeType': routeType,
      'status': status,
      'coordinates': result.coordinates,
      'maneuvers': result.maneuvers.map(_maneuverToJson).toList(),
      'distanceMeters': result.distanceMeters,
      'durationSeconds': result.durationSeconds,
      'remainingDistanceMeters':
          remainingDistanceMeters ?? result.distanceMeters,
      'remainingDurationSeconds':
          remainingDurationSeconds ?? result.durationSeconds,
      'nextManeuverText': nextManeuverText ?? _firstManeuverText(result),
      'nextManeuverDistance': nextManeuverDistance,
      'style': style,
      'avoidHighways': avoidHighways,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _maneuverToJson(RouteManeuver maneuver) {
    return {
      'latitude': maneuver.latitude,
      'longitude': maneuver.longitude,
      'routeIndex': maneuver.routeIndex,
      'announcement': maneuver.announcement,
      'instruction': maneuver.instruction,
      'maneuverType': maneuver.maneuverType.name,
      'roundaboutExitNumber': maneuver.roundaboutExitNumber,
    };
  }

  String? _firstManeuverText(RouteResult result) {
    if (result.maneuvers.isEmpty) return null;
    final first = result.maneuvers.first;
    return first.instruction.isNotEmpty
        ? first.instruction
        : first.announcement;
  }

  Future<void> _writeSnapshot(Map<String, dynamic> snapshot) async {
    final preferences = await _prefs();
    await preferences.setString(snapshotKey, json.encode(snapshot));
  }

  Future<void> _writeProgress(Map<String, dynamic> progress) async {
    final preferences = await _prefs();
    await preferences.setString(progressKey, json.encode(progress));
  }

  Future<void> _clearProgress() async {
    final preferences = await _prefs();
    await preferences.remove(progressKey);
    _lastProgressWrite = null;
  }

  Future<SharedPreferences> _prefs() async {
    final existing = _preferences;
    if (existing != null) return existing;
    final created = await SharedPreferences.getInstance();
    _preferences = created;
    return created;
  }
}
