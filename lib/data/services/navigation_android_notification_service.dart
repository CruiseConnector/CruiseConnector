import 'dart:async';
import 'dart:ui' show Color;

import 'package:cruise_connect/data/services/navigation_live_activity_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 2026-07-03 (vucko): Android-Gegenstück zur iOS-Live-Activity. Zeigt während
/// der Navigation eine LAUFENDE (ongoing) Benachrichtigung auf dem
/// Sperrbildschirm und im Benachrichtigungs-Shade mit dem nächsten Manöver,
/// der Distanz dorthin, der Reststrecke und der ETA — wie bei Apple, aber ganz
/// ohne Zertifikate/Entitlements (reines flutter_local_notifications).
///
/// Wird aus [cruise_mode_page] parallel zur iOS-Live-Activity gerufen; die
/// Plattform-Gates sorgen dafür, dass jeweils nur die passende Seite feuert.
class NavigationAndroidNotificationService {
  NavigationAndroidNotificationService._();

  static final NavigationAndroidNotificationService instance =
      NavigationAndroidNotificationService._();

  static const int _notificationId = 9200;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'cruise_navigation',
    'Navigation aktiv',
    description:
        'Zeigt deine Strecke laufend mit Manöver, Distanz und Ankunftszeit.',
    // Bewusst LOW: sichtbar auf Sperrbildschirm/Shade, aber kein Ton/Vibration
    // bei jedem Meter-Update (sonst nervt es bei jeder Aktualisierung).
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
    showBadge: false,
  );

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _active = false;

  bool get _isSupportedPlatform {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    // initialize() ist idempotent und teilt sich nativ mit dem
    // PushNotificationService — hier nur die Android-Seite nötig.
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    _initialized = true;
  }

  Future<void> start(NavigationLiveActivitySnapshot snapshot) async {
    if (!_isSupportedPlatform) return;
    try {
      await _ensureInitialized();
      await _show(snapshot);
      _active = true;
    } catch (e) {
      debugPrint('[NavAndroidNotif] start failed: $e');
    }
  }

  Future<void> update(NavigationLiveActivitySnapshot snapshot) async {
    if (!_isSupportedPlatform || !_active) return;
    try {
      await _show(snapshot);
    } catch (e) {
      debugPrint('[NavAndroidNotif] update failed: $e');
    }
  }

  Future<void> end() async {
    if (!_isSupportedPlatform || !_active) return;
    _active = false;
    try {
      await _local.cancel(id: _notificationId);
    } catch (e) {
      debugPrint('[NavAndroidNotif] end failed: $e');
    }
  }

  Future<void> _show(NavigationLiveActivitySnapshot snapshot) async {
    final title = _title(snapshot);
    final body = _body(snapshot);
    final details = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.low,
      priority: Priority.low,
      // Laufend + nicht wegwischbar + kein Re-Alert bei Updates.
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      showWhen: false,
      category: AndroidNotificationCategory.navigation,
      // Detaillierte, ausklappbare Vorschau der Strecke.
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'Cruise Connector · Navigation',
      ),
      // Manöver-farbige Akzentleiste (rot = Reroute/aktiv wie iOS).
      color: snapshot.isRerouting
          ? const Color(0xFFFF9500)
          : const Color(0xFFFF3B30),
      colorized: false,
    );

    await _local.show(
      id: _notificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: details),
    );
  }

  String _title(NavigationLiveActivitySnapshot s) {
    if (s.isRerouting) return '🔄 Route wird neu berechnet';
    final prefix = _maneuverGlyph(s.maneuverType);
    final text = s.instruction.trim().isNotEmpty
        ? s.instruction.trim()
        : 'Der Route folgen';
    return prefix.isEmpty ? text : '$prefix $text';
  }

  String _body(NavigationLiveActivitySnapshot s) {
    final parts = <String>[];
    final dist = _formatManeuverDistance(s.distanceToManeuverMeters);
    if (dist != null) parts.add(dist);
    final remaining = _formatRemaining(s.remainingDistanceMeters);
    if (remaining != null) parts.add('noch $remaining');
    final eta = _formatEta(s.remainingDurationSeconds);
    if (eta != null) parts.add(eta);
    if (parts.isEmpty) return 'Navigation läuft';
    return parts.join('  ·  ');
  }

  /// Kleines Glyph als Blick-Anker, gespiegelt vom iOS-Manöver-Badge.
  String _maneuverGlyph(String maneuverType) {
    final t = maneuverType.toLowerCase();
    if (t.startsWith('roundabout') || t.contains('kreis')) return '🔄';
    if (t.contains('arrival') || t.contains('ankunft')) return '🏁';
    if (t.contains('uturn') || t.contains('wenden')) return '↩️';
    if (t.contains('left')) return '↰';
    if (t.contains('right')) return '↱';
    if (t.contains('straight') || t.contains('continue')) return '↑';
    return '';
  }

  String? _formatManeuverDistance(double? meters) {
    if (meters == null) return null;
    if (meters < 10) return 'Jetzt';
    if (meters < 1000) {
      // Nah dran feine 10er-Stufen, sonst 50er — wie die App-Kadenz.
      final step = meters <= 200 ? 10.0 : 50.0;
      final rounded = (meters / step).round() * step;
      return 'in ${rounded.toInt()} m';
    }
    final km = meters / 1000;
    return 'in ${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  String? _formatRemaining(double? meters) {
    if (meters == null) return null;
    if (meters < 1000) {
      final rounded = (meters / 50).round() * 50;
      return '${rounded.toInt()} m';
    }
    final km = meters / 1000;
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  String? _formatEta(int? seconds) {
    if (seconds == null || seconds <= 0) return null;
    final totalMin = (seconds / 60).round();
    if (totalMin < 60) return '$totalMin min';
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }
}
