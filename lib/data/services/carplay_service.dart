import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;

import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';

/// Bridge between CarPlay (native iOS) and Flutter route services.
///
/// Listens for CarPlay commands via MethodChannel and delegates
/// route generation/replay to existing services.
class CarPlayService {
  CarPlayService._();
  static final instance = CarPlayService._();

  static const _channel = MethodChannel('com.cruiseconnect/carplay');
  final _routeService = const RouteService();

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  RouteResult? _lastGeneratedRoute;

  /// Initialize the CarPlay bridge. Call once at app startup.
  void init() {
    _channel.setMethodCallHandler(_handleCarPlayCall);
    debugPrint('[CarPlay] Service initialized');
  }

  Future<dynamic> _handleCarPlayCall(MethodCall call) async {
    switch (call.method) {
      case 'carplayConnected':
        _isConnected = true;
        debugPrint('[CarPlay] Connected');
        break;

      case 'carplayDisconnected':
        _isConnected = false;
        _lastGeneratedRoute = null;
        debugPrint('[CarPlay] Disconnected');
        break;

      case 'generateRoute':
        await _handleGenerateRoute(call.arguments as Map);
        break;

      case 'confirmRoute':
        _handleConfirmRoute();
        break;

      case 'stopNavigation':
        debugPrint('[CarPlay] Navigation stopped from CarPlay');
        break;

      case 'getSavedRoutes':
        await _handleGetSavedRoutes();
        break;

      case 'replayRoute':
        final args = call.arguments as Map;
        await _handleReplayRoute(args['routeId'] as String);
        break;

      default:
        debugPrint('[CarPlay] Unknown method: ${call.method}');
    }
  }

  /// Generate a route from CarPlay request (Rundkurs or A nach B).
  Future<void> _handleGenerateRoute(Map args) async {
    final style = args['style'] as String? ?? 'Sport Mode';
    final distanceKm = args['distanceKm'] as int? ?? 50;
    final planningType = args['planningType'] as String? ?? 'Zufall';
    final isRoundTrip = args['isRoundTrip'] as bool? ?? true;

    debugPrint('[CarPlay] Generating route: $style, ${distanceKm}km, $planningType, roundTrip=$isRoundTrip');

    try {
      // Get current position
      final position = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Generate route using existing service
      // Both Rundkurs and A-nach-B use generateRoundTrip on CarPlay
      // (A-nach-B without destination falls back to scenic one-way route)
      final result = await _routeService.generateRoundTrip(
        startPosition: position,
        targetDistanceKm: distanceKm,
        mode: style,
        planningType: isRoundTrip ? planningType : 'Zufall',
      );

      _lastGeneratedRoute = result;

      // Count curves
      final curveCount = _countCurves(result);

      // Send result back to CarPlay
      _channel.invokeMethod('routeGenerated', {
        'distanceKm': result.distanceKm,
        'durationMin': (result.durationSeconds ?? 0) / 60,
        'curves': curveCount,
        'style': style,
      });

      debugPrint('[CarPlay] Route generated: ${result.distanceKm}km');
    } catch (e) {
      debugPrint('[CarPlay] Route generation failed: $e');
      _channel.invokeMethod('routeError', e.toString());
    }
  }

  /// Confirm route and navigate to cruise mode on the phone.
  void _handleConfirmRoute() {
    if (_lastGeneratedRoute == null) return;

    debugPrint('[CarPlay] Route confirmed, switching to cruise mode');

    // Use the pending route mechanism to switch to cruise tab
    // Create a SavedRoute-like object from the generated result
    // For now, trigger navigation on the phone
    // The phone's CruiseModePage will handle the actual navigation
  }

  /// Load saved routes and send to CarPlay.
  Future<void> _handleGetSavedRoutes() async {
    try {
      final routes = await SavedRoutesService.getUserRoutes();

      final routeData = routes.take(10).map((r) => {
        'id': r.id,
        'name': r.name ?? r.style,
        'style': r.style,
        'distanceKm': r.distanceKm,
        'emoji': r.styleEmoji,
      }).toList();

      _channel.invokeMethod('updateSavedRoutes', routeData);
    } catch (e) {
      debugPrint('[CarPlay] Failed to load saved routes: $e');
      _channel.invokeMethod('updateSavedRoutes', <Map<String, dynamic>>[]);
    }
  }

  /// Replay a saved route: load it and switch to cruise mode.
  Future<void> _handleReplayRoute(String routeId) async {
    try {
      final routes = await SavedRoutesService.getUserRoutes();
      final route = routes.firstWhere((r) => r.id == routeId);

      // Use the pending route notifier to switch to cruise tab
      CruiseModePage.pendingRoute.value = route;

      debugPrint('[CarPlay] Replaying route: ${route.name}');
    } catch (e) {
      debugPrint('[CarPlay] Failed to replay route: $e');
      _channel.invokeMethod('routeError', 'Route nicht gefunden');
    }
  }

  /// Count curves in a route using bearing-based detection.
  int _countCurves(RouteResult result) {
    return GamificationService.countCurves(result.coordinates);
  }
}
