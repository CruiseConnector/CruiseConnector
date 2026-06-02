import 'dart:async';
import 'dart:convert';

import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Maschinenlesbare Manöver-Typen für die Auto-Displays (Android Auto +
/// CarPlay). Die Fahr-Richtung steckt in der App nur im Material-Icon
/// (`RouteManeuver.icon`), nicht im groben `maneuverType` (normal/roundabout).
/// Diese Kinds werden nativ auf `Maneuver.TYPE_*` (Android) bzw. `CPManeuver`-
/// Symbole (iOS) gemappt. String-Werte müssen 1:1 mit der Kotlin/Swift-Seite
/// übereinstimmen.
class CarManeuverKind {
  const CarManeuverKind._();

  static const straight = 'straight';
  static const turnLeft = 'turnLeft';
  static const turnRight = 'turnRight';
  static const slightLeft = 'slightLeft';
  static const slightRight = 'slightRight';
  static const sharpLeft = 'sharpLeft';
  static const sharpRight = 'sharpRight';
  static const uturn = 'uturn';
  static const roundabout = 'roundabout';
  static const rampLeft = 'rampLeft';
  static const rampRight = 'rampRight';
  static const merge = 'merge';
  static const forkLeft = 'forkLeft';
  static const forkRight = 'forkRight';
  static const arrive = 'arrive';
}

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
  // 2026-05-24 (vucko Task #46): wird vom Native-Target (CarPlay/AA)
  // beschrieben sobald es connected wird. Flutter pollt hier nur.
  static const carConnectedKey = 'car_connected_at';
  // 2026-06-02 (vucko): Login-Status für CarPlay/Android-Auto. Ist niemand
  // eingeloggt, zeigt das Auto-Display „Bitte zuerst einloggen" statt der Karte.
  static const loggedInKey = 'cc_logged_in';
  static const _progressThrottle = Duration(seconds: 3);

  SharedPreferences? _preferences;
  DateTime? _lastProgressWrite;

  /// Schreibt den Login-Status, den die CarPlay/Android-Auto-Seite liest.
  Future<void> publishLoginState(bool loggedIn) async {
    final prefs = await _ensurePrefs();
    await prefs.setString(loggedInKey, loggedIn ? '1' : '0');
  }

  /// Liefert true wenn ein CarPlay/AA-Target sich in den letzten 30s
  /// gemeldet hat. Native Target soll `car_connected_at` regelmäßig setzen.
  Future<bool> isCarConnected() async {
    final prefs = await _ensurePrefs();
    final iso = prefs.getString(carConnectedKey);
    if (iso == null) return false;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return false;
    return DateTime.now().difference(dt) < const Duration(seconds: 30);
  }

  Future<SharedPreferences> _ensurePrefs() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

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
    String? nextManeuverKind,
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
        nextManeuverKind: nextManeuverKind,
      ),
    );
  }

  Future<void> publishProgress({
    required double? remainingDistanceMeters,
    required double? remainingDurationSeconds,
    required String? nextManeuverText,
    required double? nextManeuverDistance,
    String? nextManeuverKind,
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
      'nextManeuverKind': nextManeuverKind,
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
    String? nextManeuverKind,
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
      'nextManeuverKind': nextManeuverKind ?? _firstManeuverKind(result),
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
      'kind': maneuverKindFromIcon(maneuver.icon),
      'roundaboutExitNumber': maneuver.roundaboutExitNumber,
    };
  }

  /// Leitet aus dem Manöver-Icon (die einzige Richtungsquelle in der App) einen
  /// maschinenlesbaren Kind-String ab, den Android Auto / CarPlay in ein echtes
  /// Abbiege-Symbol übersetzen. Muss zu den nativen Mappings passen.
  static String maneuverKindFromIcon(IconData icon) {
    if (icon == Icons.turn_left) return CarManeuverKind.turnLeft;
    if (icon == Icons.turn_right) return CarManeuverKind.turnRight;
    if (icon == Icons.turn_slight_left) return CarManeuverKind.slightLeft;
    if (icon == Icons.turn_slight_right) return CarManeuverKind.slightRight;
    if (icon == Icons.turn_sharp_left) return CarManeuverKind.sharpLeft;
    if (icon == Icons.turn_sharp_right) return CarManeuverKind.sharpRight;
    if (icon == Icons.u_turn_left || icon == Icons.u_turn_right) {
      return CarManeuverKind.uturn;
    }
    if (icon == Icons.roundabout_left || icon == Icons.roundabout_right) {
      return CarManeuverKind.roundabout;
    }
    if (icon == Icons.ramp_left) return CarManeuverKind.rampLeft;
    if (icon == Icons.ramp_right) return CarManeuverKind.rampRight;
    if (icon == Icons.merge) return CarManeuverKind.merge;
    if (icon == Icons.fork_left) return CarManeuverKind.forkLeft;
    if (icon == Icons.fork_right) return CarManeuverKind.forkRight;
    if (icon == Icons.flag) return CarManeuverKind.arrive;
    return CarManeuverKind.straight;
  }

  String? _firstManeuverText(RouteResult result) {
    if (result.maneuvers.isEmpty) return null;
    final first = result.maneuvers.first;
    return first.instruction.isNotEmpty
        ? first.instruction
        : first.announcement;
  }

  String? _firstManeuverKind(RouteResult result) {
    if (result.maneuvers.isEmpty) return null;
    return maneuverKindFromIcon(result.maneuvers.first.icon);
  }

  Future<void> _writeSnapshot(Map<String, dynamic> snapshot) async {
    final preferences = await _prefs();
    // updatedAtMs ist die Veraltet-Marke für die CarPlay-Seite (Epoch-ms,
    // trivial vergleichbar — kein ISO-Parsing nötig). Verhindert, dass ein
    // alter Snapshot nach App-Neustart eine Geister-Navigation auslöst.
    snapshot['updatedAtMs'] = DateTime.now().millisecondsSinceEpoch;
    await preferences.setString(snapshotKey, json.encode(snapshot));
  }

  Future<void> _writeProgress(Map<String, dynamic> progress) async {
    final preferences = await _prefs();
    progress['updatedAtMs'] = DateTime.now().millisecondsSinceEpoch;
    await preferences.setString(progressKey, json.encode(progress));
  }

  Future<void> _clearProgress() async {
    final preferences = await _prefs();
    await preferences.remove(progressKey);
    _lastProgressWrite = null;
  }

  /// 2026-06-02 (vucko): Beim App-Start aufrufen. Löscht alle persistierten
  /// Auto-Keys, damit nach einem Neustart KEINE alte Route als „Navigation
  /// läuft" wiederaufersteht und KEIN alter `car_command` erneut ausgeführt
  /// wird (der Listener startet mit requestId 0). CarPlay startet so frisch.
  Future<void> clearCarSession() async {
    final prefs = await _ensurePrefs();
    await prefs.remove(snapshotKey);
    await prefs.remove(progressKey);
    await prefs.remove('car_command');
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
