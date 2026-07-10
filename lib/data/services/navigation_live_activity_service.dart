import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NavigationLiveActivitySnapshot {
  const NavigationLiveActivitySnapshot({
    required this.instruction,
    required this.maneuverType,
    required this.distanceToManeuverMeters,
    required this.remainingDistanceMeters,
    required this.remainingDurationSeconds,
    required this.isRerouting,
  });

  final String instruction;
  final String maneuverType;
  final double? distanceToManeuverMeters;
  final double? remainingDistanceMeters;
  final int? remainingDurationSeconds;
  final bool isRerouting;

  Map<String, Object?> toMap() {
    return {
      'instruction': instruction,
      'maneuverType': maneuverType,
      'distanceToManeuverMeters': distanceToManeuverMeters,
      'remainingDistanceMeters': remainingDistanceMeters,
      'remainingDurationSeconds': remainingDurationSeconds,
      'isRerouting': isRerouting,
    };
  }

  String signature() {
    // 2026-07-02 (vucko Live-Activity-Freeze): Buckets bewusst GROB. Die 10-m-
    // Buckets vom 2026-06-20 erzeugten bei Fahrtempo ~1 Update/s → iOS
    // erschöpfte das ActivityKit-Update-Budget und fror den Sperrbildschirm
    // nach ~1 Minute dauerhaft ein (Geräte-Video: Manöver hing 2+ Minuten auf
    // altem Stand). Lieber eine leicht gröbere, aber LEBENDE Anzeige: 50-m-
    // Stufen nah am Manöver, 250-m-Stufen darüber, 500-m-Reststrecke.
    final maneuverBucket = distanceToManeuverMeters == null
        ? -1
        : distanceToManeuverMeters! <= 1000
        ? (distanceToManeuverMeters! / 50).round()
        : 1000 + (distanceToManeuverMeters! / 250).round();
    final remainingBucket = remainingDistanceMeters == null
        ? -1
        : (remainingDistanceMeters! / 500).round();
    return [
      instruction,
      maneuverType,
      maneuverBucket,
      remainingBucket,
      remainingDurationSeconds == null
          ? -1
          : (remainingDurationSeconds! / 60).round(),
      isRerouting,
    ].join('|');
  }
}

class NavigationLiveActivityService {
  NavigationLiveActivityService._();

  static final NavigationLiveActivityService instance =
      NavigationLiveActivityService._();

  static const MethodChannel _channel = MethodChannel(
    'cruise_connect/navigation_live_activity',
  );

  bool _active = false;
  bool _supportedWarningLogged = false;

  bool get _isSupportedPlatform {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> start(NavigationLiveActivitySnapshot snapshot) async {
    if (!_isSupportedPlatform) return;
    try {
      await _channel.invokeMethod<void>('start', snapshot.toMap());
      _active = true;
    } on PlatformException catch (e) {
      _logUnsupported(e);
    } catch (e) {
      debugPrint('[LiveActivity] start failed: $e');
    }
  }

  Future<void> update(NavigationLiveActivitySnapshot snapshot) async {
    if (!_isSupportedPlatform || !_active) return;
    try {
      await _channel.invokeMethod<void>('update', snapshot.toMap());
    } on PlatformException catch (e) {
      _logUnsupported(e);
    } catch (e) {
      debugPrint('[LiveActivity] update failed: $e');
    }
  }

  Future<void> end() async {
    if (!_isSupportedPlatform || !_active) return;
    _active = false;
    try {
      await _channel.invokeMethod<void>('end');
    } on PlatformException catch (e) {
      _logUnsupported(e);
    } catch (e) {
      debugPrint('[LiveActivity] end failed: $e');
    }
  }

  void _logUnsupported(PlatformException e) {
    if (_supportedWarningLogged) return;
    _supportedWarningLogged = true;
    debugPrint('[LiveActivity] unavailable: ${e.code} ${e.message ?? ''}');
  }
}
