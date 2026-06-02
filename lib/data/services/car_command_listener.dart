import 'dart:async';
import 'dart:convert';

import 'package:cruise_connect/data/services/car_route_bridge_service.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-06-02 (vucko, Task #115): Bidirektionale CarPlay/Android-Auto-Bridge.
///
/// Die Auto-Seite (CarPlay `CarPlayRouteCoordinator`) schreibt Befehle in
/// SharedPreferences (`flutter.car_command`); dieser Listener pollt sie und
/// führt sie aus — **unabhängig von der Cruise-Page**, damit das Konfigurieren
/// im Auto auch funktioniert, wenn die App nicht auf der Karten-Seite ist.
///
/// Flow „Im Auto konfigurieren":
///   Auto: Stil + km + Autobahn wählen → `planRoute`-Befehl
///   → hier: GPS holen, RouteService.generateRoundTrip, Ergebnis als
///     `found`-Snapshot zurück → Auto zeigt Vorschau („Losfahren" / „Neu
///     konfigurieren").
///   Auto: „Losfahren" → `startNavigation`-Befehl → hier: `navigating`-Snapshot
///     + optionaler Hook, damit die Cruise-Page (falls offen) die echte Fahrt
///     mit GPS-Tracking/Voice übernimmt.
///
/// Die Route-Berechnung nutzt bewusst den eigenständigen [RouteService] (keine
/// UI-Abhängigkeit). Siehe auch [CarRouteBridgeService] (Gegenrichtung).
class CarCommandListener {
  CarCommandListener._();
  static final CarCommandListener instance = CarCommandListener._();

  /// Key (ohne `flutter.`-Präfix — das setzt shared_preferences selbst). Die
  /// Swift-Seite liest/schreibt `flutter.car_command` via UserDefaults.
  static const commandKey = 'car_command';

  final CarRouteBridgeService _bridge = CarRouteBridgeService();
  final RouteService _routeService = RouteService();

  Timer? _pollTimer;
  int _lastHandledRequestId = 0;
  bool _busy = false;

  RouteResult? _lastRoute;
  String _lastStyle = 'Sport Mode';
  String _lastRouteType = CarRouteType.roundtrip;
  bool _lastAvoidHighways = false;

  /// Wird mit der berechneten Route aufgerufen, sobald das Auto „Losfahren"
  /// drückt. Die Cruise-Page registriert sich hier, um die echte Fahrt
  /// (GPS-Tracking, Voice, Progress) zu starten. Ist niemand registriert,
  /// fährt das Auto mit der reinen Snapshot-Navigation (eigener Standort-Follow).
  /// Wird mit der berechneten Route aufgerufen, sobald das Auto „Losfahren"
  /// drückt. `route` ist null, wenn die Cruise-Page die Route selbst geplant
  /// hat (onPlanRoute) — dann fährt die Page ihre aktuelle Route.
  void Function(RouteResult? route, String style, bool avoidHighways)?
  onStartNavigation;

  /// 2026-06-02 (vucko Mirror): Wird aufgerufen, wenn das Auto „Route planen"
  /// abschließt. Ist die Cruise-Page offen, übernimmt SIE die Suche (zeigt das
  /// Lade-Popup + die Vorschau-Animation + publisht searching/found an CarPlay
  /// zurück) → echtes 1:1-Mirroring, beide Geräte suchen gleichzeitig. Gibt true
  /// zurück, wenn die Page übernommen hat (dann rechnet der Listener NICHT
  /// standalone). Ist die Page zu → false → Listener rechnet selbst.
  bool Function(String style, int distanceKm, bool avoidHighways)? onPlanRoute;

  /// Wird aufgerufen, wenn das Auto den Abschluss-Screen mit „Fertig" schließt
  /// (completionDone). Die Cruise-Page registriert sich hier, um ihren eigenen
  /// Abschluss-Screen ebenfalls zu schließen → beidseitige Sync.
  void Function()? onCompletionDone;

  bool get isRunning => _pollTimer != null;

  void start() {
    _pollTimer?.cancel();
    // 1,5s-Poll: liest nur einen kleinen Pref-String — vernachlässigbar.
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      unawaited(_poll());
    });
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _poll() async {
    if (_busy) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // KRITISCH: shared_preferences cached Dart-seitig. Die Swift-Seite
      // (CarPlay) schreibt `flutter.car_command` direkt in UserDefaults —
      // ohne reload() würde Dart nur den veralteten Cache lesen und den Befehl
      // nie sehen. reload() holt die frischen Native-Werte.
      await prefs.reload();
      final raw = prefs.getString(commandKey);
      if (raw == null || raw.isEmpty) return;

      final Map<String, dynamic> cmd;
      try {
        cmd = json.decode(raw) as Map<String, dynamic>;
      } catch (_) {
        return;
      }

      final requestId = (cmd['requestId'] as num?)?.toInt() ?? 0;
      if (requestId <= _lastHandledRequestId) return;
      _lastHandledRequestId = requestId;

      final action = cmd['action']?.toString() ?? '';
      _busy = true;
      try {
        switch (action) {
          case 'planRoute':
            await _handlePlanRoute(cmd);
            break;
          case 'startNavigation':
            await _handleStartNavigation();
            break;
          case 'cancel':
            _lastRoute = null;
            await _bridge.publishEnded();
            break;
          case 'completionDone':
            // Auto hat den Abschluss-Screen mit „Fertig" geschlossen → Handy
            // soll seinen Abschluss-Screen ebenfalls schließen + Auto-Session
            // leeren (beidseitige Sync).
            onCompletionDone?.call();
            await _bridge.clearCarSession();
            break;
          default:
            break;
        }
      } finally {
        _busy = false;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CarCommandListener] poll error: $e');
      }
    }
  }

  Future<void> _handlePlanRoute(Map<String, dynamic> cmd) async {
    final style = cmd['style']?.toString() ?? 'Sport Mode';
    final distanceKm = (cmd['distanceKm'] as num?)?.toInt() ?? 60;
    final avoidHighways = cmd['avoidHighways'] == true;
    _lastStyle = style;
    _lastAvoidHighways = avoidHighways;
    _lastRouteType = CarRouteType.roundtrip;

    // 2026-06-02 (vucko Mirror): Ist die Cruise-Page offen, lassen wir SIE die
    // Route suchen → Handy zeigt Lade-Popup + Vorschau-Animation und publisht
    // searching/found selbst an CarPlay (1:1-Spiegelung). Nur wenn die Page zu
    // ist, rechnen wir hier standalone weiter.
    if (onPlanRoute != null && onPlanRoute!(style, distanceKm, avoidHighways)) {
      _lastRoute = null; // Page besitzt die Route
      return;
    }

    await _bridge.publishSearching(
      routeType: CarRouteType.roundtrip,
      style: style,
      avoidHighways: avoidHighways,
    );

    final start = await _resolveStartPosition();
    if (start == null) {
      await _bridge.publishFailed(
        message: 'Kein GPS-Standort verfügbar. Bitte Standort freigeben.',
      );
      return;
    }

    try {
      final result = await _routeService.generateRoundTrip(
        startPosition: start,
        targetDistanceKm: distanceKm,
        mode: style,
        planningType: 'Standard',
        avoidHighways: avoidHighways,
        debugTrigger: 'carplay_config',
        subscriptionTier: RouteService.resolveEffectiveSubscriptionTier(
          requestedTier: 'premium',
          isTesterOrBeta: true,
        ),
      );
      _lastRoute = result;
      await _bridge.publishFound(
        result: result,
        routeType: CarRouteType.roundtrip,
        style: style,
        avoidHighways: avoidHighways,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CarCommandListener] generateRoundTrip failed: $e');
      }
      await _bridge.publishFailed(
        message: 'Route konnte nicht berechnet werden. Bitte erneut versuchen.',
      );
    }
  }

  Future<void> _handleStartNavigation() async {
    final route = _lastRoute;
    // Hat der Listener die Route selbst berechnet (Page war zu), publishen wir
    // direkt navigating. Hat die Page geplant (route == null), startet die Page
    // ihre eigene Route + publisht selbst.
    if (route != null) {
      await _bridge.publishNavigationStarted(
        result: route,
        routeType: _lastRouteType,
        style: _lastStyle,
        avoidHighways: _lastAvoidHighways,
      );
    }
    onStartNavigation?.call(route, _lastStyle, _lastAvoidHighways);
  }

  Future<geo.Position?> _resolveStartPosition() async {
    try {
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.deniedForever) {
        return null;
      }
      final last = await geo.Geolocator.getLastKnownPosition();
      if (last != null) return last;
      return await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
