import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cruise_connect/core/constants.dart';

import 'package:cruise_connect/data/services/web_position_smoother.dart';
import 'package:cruise_connect/data/services/geocoding_service.dart';
import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:cruise_connect/data/services/navigation_progress_socket_service.dart';
import 'package:cruise_connect/data/services/offline_map_service.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/data/services/smart_reroute_engine.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/mapbox_suggestion.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart'
    show RouteManeuver;
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_completion_dialog.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_maneuver_indicator.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_navigation_info_panel.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_setup_card.dart';
import 'package:cruise_connect/presentation/widgets/cruise/drive_control_panel.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/route_quality_validator.dart';

class CruiseModePage extends StatefulWidget {
  const CruiseModePage({super.key, this.initialRoute});

  /// Wenn gesetzt, wird diese Route direkt geladen und bestätigt.
  final SavedRoute? initialRoute;

  /// Signalisiert dem Parent (HomePage), dass die Navigation im Fullscreen-Modus ist.
  /// Wenn true, soll die BottomNavigationBar ausgeblendet werden.
  static final ValueNotifier<bool> isFullscreen = ValueNotifier<bool>(false);

  /// Wird gesetzt, wenn eine gespeicherte Route erneut gefahren werden soll.
  /// HomePage hört darauf und wechselt zum Cruise-Tab.
  static final ValueNotifier<SavedRoute?> pendingRoute =
      ValueNotifier<SavedRoute?>(null);

  @override
  State<CruiseModePage> createState() => _CruiseModePageState();
}

class _CruiseModePageState extends State<CruiseModePage>
    with TickerProviderStateMixin {
  // ─────────────────────── Services ──────────────────────────────────────────
  final _geocodingService = const GeocodingService();
  final _routeService = RouteService();
  final _smartRerouteEngine = const SmartRerouteEngine();
  final _navigationSocketService = NavigationProgressSocketService();

  // ─────────────────────── Route Setup State ─────────────────────────────────
  bool _isRoundTrip = true;
  String _planningType = 'Zufall';
  String _selectedLength = '50 Km';
  String _selectedLocation = 'Aktueller Standort';
  String _selectedStyle = 'Sport Mode';
  String _selectedDetour = 'Direkt';
  bool _avoidHighways = false;
  final TextEditingController _destinationController = TextEditingController();

  // ─────────────────────── A-to-B Route Selection State ──────────────────────
  MapboxSuggestion? _selectedDestination;

  // ─────────────────────── Route Result State ────────────────────────────────
  bool _isRouteConfirmed = false;
  String? _routeGeoJson;
  double? _routeDistance;
  double? _routeDuration;
  RouteResult? _lastRouteResult;
  bool _configCollapsed = false; // Config-Panel ein-/ausgeklappt
  bool _showRouteInfoBanner = false; // Route-Info Banner nach Generation
  int _cachedCurveCount = 0; // Vorab im Isolate berechnet
  List<double>? _activeDestinationCoordinate;
  String _activePointToPointMode = 'Standard';
  int _activeDetourVariant = 0;
  bool _activePointToPointScenic = false;
  bool _activeAvoidHighways = false;
  List<double> _recentDestinationDistances = [];
  List<SpeedLimitSegment> _activeSpeedLimits = const [];
  final Map<String, List<_RecentRouteSignature>> _recentRoutesByConfig = {};

  // ─────────────────────── Map State (flutter_map) ───────────────────────────
  bool _isLoading = false;
  final MapController _mapController = MapController();
  bool _mapReady = false;
  // Route als LatLng-Liste für PolylineLayer
  List<LatLng> _routeLatLngs = [];
  // Aktuelle User-Position als Marker
  LatLng? _userPosition;
  double _userHeading = 0.0; // GPS-Heading in Grad (0=Nord, 90=Ost)

  // ─────────────────────── Navigation State ─────────────────────────────────
  geo.Position? _userLocation;
  List<List<double>> _fullRouteCoordinates = [];
  List<List<double>> _remainingRouteCoordinates = [];
  List<RouteManeuver> _maneuvers = const [];
  int _activeManeuverIndex = 0;
  int _currentRouteIndex = 0;
  final Set<int> _announcedManeuverIndices = <int>{};
  StreamSubscription<geo.Position>? _positionSubscription;
  StreamSubscription<geo.Position>? _socketPositionSubscription;
  StreamSubscription<geo.Position>?
  _idlePositionSubscription; // Standort-Stream für Heading im Idle

  // ─────────────────────── Simulation State ─────────────────────────────────
  Timer? _simulationTimer;
  bool _isSimulationRunning = false;
  bool _isSimulationStepRunning = false;
  int _simulationIndex = 0;
  final bool _isSimulationEnabled = false; // Simulation deaktiviert
  double _simulationSpeedKmh = 60; // Aktuelle Simulationsgeschwindigkeit

  bool _isCameraLocked =
      false; // Compass-Toggle: true = Kamera folgt dem Standort
  double? _remainingDistance; // Live verbleibende Distanz in Metern
  double? _remainingDuration; // Live verbleibende Zeit in Sekunden
  bool _isRerouting = false; // Verhindert mehrfaches gleichzeitiges Rerouting
  DateTime? _lastRerouteTime; // Cooldown zwischen Reroutes
  int _offRouteCount = 0; // Zählt aufeinanderfolgende Off-Route-Updates
  static const double _offRouteThresholdMeters =
      50.0; // Ab wann Off-Route erkannt wird (wie Apple/Google Maps)
  static const int _offRouteCountThreshold =
      8; // Mindestanzahl Off-Route-Updates vor Reroute (verhindert Flackern)
  static const int _routeRedrawIndexThreshold =
      5; // Häufigere Teil-Redraws für flüssige Linie
  static const double _routeRedrawDistanceMeters = 30.0;
  double _totalDistanceDriven = 0.0; // Gesamte gefahrene Strecke in Metern
  DateTime? _navigationStartTime; // Zeitpunkt des Navigations-Starts
  double?
  _originalRouteDistance; // Ursprüngliche Gesamtdistanz (für Zeitberechnung)
  double?
  _originalRouteDuration; // Ursprüngliche Gesamtdauer (für Zeitberechnung)

  // Schwellenwerte für anteilige Gutschrift
  static const double _minProgressForCredit = 0.10; // 10% Minimum
  static const double _minProgressForFullCredit =
      0.95; // 95% = volle Gutschrift
  int _lastDrawnRouteIndex =
      0; // Letzter Index bei dem die Route neu gezeichnet wurde
  double _distanceSinceLastRedraw = 0.0;

  bool _disposed = false;

  // Web-only: Letzte setState-Zeit für Throttling (max. 1 Rebuild / 200ms auf Web)
  DateTime? _lastWebRebuildTime;

  // Web-only: GPS-Smoother für flüssige Positionsdarstellung (Kalman-Filter)
  final WebPositionSmoother _webSmoother = WebPositionSmoother();

  // Animierte Kamera-Bewegung zwischen GPS-Updates (alle Plattformen)
  AnimationController? _cameraAnimController;
  double _camFromLat = 0.0;
  double _camFromLng = 0.0;
  double _camToLat = 0.0;
  double _camToLng = 0.0;
  double _camFromHeading = 0.0;
  double _camToHeading = 0.0;
  double _lastCameraHeading = 0.0; // Für Bearing-Dead-Zone (< 5° ignorieren)

  // ──────────────────────────────────────────────────────────────────────────

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_disposed) setState(fn);
  }

  @override
  void initState() {
    super.initState();
    // Animierte Kamera-Bewegung zwischen GPS-Updates (alle Plattformen, 60fps)
    _cameraAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(_onCameraAnimationTick);
    if (widget.initialRoute != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadSavedRoute(widget.initialRoute!),
      );
    }
    CruiseModePage.pendingRoute.addListener(_onPendingRoute);
  }

  void _onPendingRoute() {
    final route = CruiseModePage.pendingRoute.value;
    if (route != null) {
      CruiseModePage.pendingRoute.value = null;
      _loadSavedRoute(route);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cameraAnimController?.removeListener(_onCameraAnimationTick);
    _cameraAnimController?.dispose();
    CruiseModePage.isFullscreen.value = false;
    CruiseModePage.pendingRoute.removeListener(_onPendingRoute);
    _stopSimulation(restartLiveTracking: false);
    _positionSubscription?.cancel();
    _socketPositionSubscription?.cancel();
    _stopIdlePositionStream();
    unawaited(_navigationSocketService.dispose());
    _destinationController.dispose();
    super.dispose();
  }

  // ── Smooth Kamera-Animation (60fps zwischen GPS-Updates) ───────────────
  void _onCameraAnimationTick() {
    final controller = _cameraAnimController;
    if (controller == null || !_isCameraLocked || !_mapReady) return;

    final t = Curves.easeOutCubic.transform(controller.value);
    var lat = _camFromLat + (_camToLat - _camFromLat) * t;
    var lng = _camFromLng + (_camToLng - _camFromLng) * t;
    var heading = _lerpAngleDeg(_camFromHeading, _camToHeading, t);

    if (kIsWeb && _webSmoother.current != null) {
      final prediction = _webSmoother.predict(DateTime.now());
      lat = lat + (prediction.lat - lat) * 0.35;
      lng = lng + (prediction.lng - lng) * 0.35;
      heading = _lerpAngleDeg(heading, prediction.heading, 0.35);
    }

    // Forward-Offset: Kartenzentrum ~100m in Fahrtrichtung verschieben,
    // damit der Fahrer mehr Straße vor sich sieht (Marker im unteren Drittel).
    final offsetLat = lat + _forwardOffsetLat(heading);
    final offsetLng = lng + _forwardOffsetLng(heading);

    try {
      _mapController.moveAndRotate(
        LatLng(offsetLat, offsetLng),
        16.5,
        -heading,
      );
    } catch (_) {}
  }

  /// Startet eine animierte Kamera-Bewegung von der aktuellen zur neuen Position.
  void _animateCameraTo(double lat, double lng, double heading) {
    final controller = _cameraAnimController;
    if (controller == null) return;

    // Bearing-Dead-Zone: Heading-Änderungen unter 2° ignorieren (GPS-Rauschen)
    var effectiveHeading = heading;
    final headingDelta = _angleDiff(_lastCameraHeading, heading).abs();
    if (headingDelta < 2.0) {
      effectiveHeading = _lastCameraHeading;
    } else {
      _lastCameraHeading = heading;
    }

    // Fließender Übergang: aktuelle interpolierte Position als neuen Startpunkt nehmen
    // (statt vom letzten Ziel zu starten → verhindert Ruckeln bei schnellen Updates)
    if (controller.isAnimating) {
      final t = Curves.easeOutCubic.transform(controller.value);
      _camFromLat = _camFromLat + (_camToLat - _camFromLat) * t;
      _camFromLng = _camFromLng + (_camToLng - _camFromLng) * t;
      _camFromHeading = _lerpAngleDeg(_camFromHeading, _camToHeading, t);
    } else {
      _camFromLat = _camToLat;
      _camFromLng = _camToLng;
      _camFromHeading = _camToHeading;
    }
    _camToLat = lat;
    _camToLng = lng;
    _camToHeading = effectiveHeading;

    // Wenn erste Animation: From = To (kein Sprung)
    if (_camFromLat == 0.0 && _camFromLng == 0.0) {
      _camFromLat = lat;
      _camFromLng = lng;
      _camFromHeading = effectiveHeading;
    }

    controller.forward(from: 0.0);
  }

  /// Zirkuläre Interpolation für Heading (0–360°).
  static double _lerpAngleDeg(double from, double to, double t) {
    var diff = (to - from) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return (from + diff * t) % 360;
  }

  /// Kleinster Winkelunterschied (mit Vorzeichen, -180..+180).
  static double _angleDiff(double from, double to) {
    var diff = (to - from) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }

  /// Forward-Offset: ~100m nach Norden in Breitengrad-Grad.
  static double _forwardOffsetLat(double headingDeg) {
    return math.cos(headingDeg * math.pi / 180) * 0.0009; // ~100m
  }

  /// Forward-Offset: ~100m nach Osten in Längengrad-Grad.
  static double _forwardOffsetLng(double headingDeg) {
    return math.sin(headingDeg * math.pi / 180) *
        0.0012; // ~100m (breitenabhängig)
  }

  void _handleRouteModeChanged(bool isRoundTrip) {
    const roundTripStyles = {
      'Kurvenjagd',
      'Sport Mode',
      'Abendrunde',
      'Entdecker',
    };
    const pointToPointStyles = {
      'Kurvenjagd',
      'Sport Mode',
      'Abendrunde',
      'Entdecker',
    };

    setState(() {
      _isRoundTrip = isRoundTrip;
      _selectedStyle = isRoundTrip
          ? (roundTripStyles.contains(_selectedStyle)
                ? _selectedStyle
                : 'Sport Mode')
          : (pointToPointStyles.contains(_selectedStyle)
                ? _selectedStyle
                : 'Abendrunde');
      if (isRoundTrip) {
        _selectedDetour = 'Direkt';
        _avoidHighways = false;
        _selectedDestination = null;
        _destinationController.clear();
      } else if (!pointToPointStyles.contains(_selectedStyle)) {
        _selectedStyle = 'Abendrunde';
      }
    });
  }

  bool _requiresDestination(bool isRoundTrip) => !isRoundTrip;

  // ═══════════════════════ BUILD ════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: Stack(
        children: [
          // Map IMMER an gleicher Stelle im Widget-Tree (verhindert Neu-Erstellung)
          // RepaintBoundary isoliert Canvas-Repaints vom Rest der UI (Web-Performance).
          Positioned.fill(child: RepaintBoundary(child: _buildMapWidget())),

          // Config-Overlay ODER Navigation-Overlay
          // RepaintBoundary trennt UI-Overlays vom Karten-Repaint (Web-Performance).
          if (!_isRouteConfirmed) RepaintBoundary(child: _buildConfigOverlay()),
          if (_isRouteConfirmed)
            RepaintBoundary(child: _buildNavigationOverlay()),
        ],
      ),
    );
  }

  // ═══════════════════════ CONFIG OVERLAY ═════════════════════════════════

  Widget _buildConfigOverlay() {
    // Eingeklappter Zustand: nur Buttons am unteren Rand + Expand-Handle + Info-Banner
    if (_configCollapsed) {
      return Stack(
        children: [
          // Route-Info Banner oben (bleibt bis zur Bestätigung)
          if (_showRouteInfoBanner && _lastRouteResult != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 12,
              child: _buildRouteInfoBanner(),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle zum Hochziehen
                GestureDetector(
                  onTap: () => setState(() => _configCollapsed = false),
                  onVerticalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) < -100) {
                      setState(() => _configCollapsed = false);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          const Color(0xFF0B0E14).withValues(alpha: 0.95),
                        ],
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[600],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Icon(
                          Icons.keyboard_arrow_up,
                          color: Colors.grey,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  color: const Color(0xFF0B0E14),
                  child: _buildBottomActions(),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Ausgeklappter Zustand: vollständiges Config-Panel
    return Stack(
      children: [
        // Overscroll nach oben (= Swipe-Down am Anfang) → einklappen
        NotificationListener<OverscrollNotification>(
          onNotification: (notification) {
            // Overscroll am oberen Rand = User swipt nach unten
            if (notification.overscroll < -15) {
              setState(() => _configCollapsed = true);
              return true;
            }
            return false;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Transparenter Bereich oben → Map scheint durch + Einklapp-Pfeil
              SliverToBoxAdapter(
                child: GestureDetector(
                  onVerticalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) > 150) {
                      setState(() => _configCollapsed = true);
                    }
                  },
                  child: Container(
                    height: MediaQuery.of(context).size.height * 0.38,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          const Color(0xFF0B0E14).withValues(alpha: 0.8),
                          const Color(0xFF0B0E14),
                        ],
                        stops: const [0.6, 0.9, 1.0],
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _configCollapsed = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF1C1F26,
                              ).withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Colors.grey,
                                  size: 18,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Einklappen',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  color: const Color(0xFF0B0E14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: Column(
                    children: [
                      CruiseSetupCard(
                        isRoundTrip: _isRoundTrip,
                        planningType: _planningType,
                        selectedLength: _selectedLength,
                        selectedLocation: _selectedLocation,
                        selectedStyle: _selectedStyle,
                        selectedDestination: _selectedDestination,
                        destinationController: _destinationController,
                        onRoundTripChanged: _handleRouteModeChanged,
                        onPlanningTypeChanged: (v) =>
                            setState(() => _planningType = v),
                        onLengthChanged: (v) =>
                            setState(() => _selectedLength = v),
                        onLocationChanged: (v) =>
                            setState(() => _selectedLocation = v),
                        onStyleChanged: (v) =>
                            setState(() => _selectedStyle = v),
                        selectedDetour: _selectedDetour,
                        onDetourChanged: _handleDetourChanged,
                        selectedAvoidHighways: _avoidHighways,
                        onAvoidHighwaysChanged: (value) =>
                            setState(() => _avoidHighways = value),
                        onDestinationSelected: _onDestinationSelected,
                        onDestinationCleared: () => setState(() {
                          _selectedDestination = null;
                          _destinationController.clear();
                        }),
                      ),
                      const SizedBox(height: 140),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Route-Info Banner (bleibt bis zur Bestätigung)
        if (_showRouteInfoBanner && _lastRouteResult != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: _buildRouteInfoBanner(),
          ),
        Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomActions()),
      ],
    );
  }

  Widget _buildRouteInfoBanner() {
    final result = _lastRouteResult!;
    // Immer echte Mapbox-Distanz nutzen (distanceMeters), nicht distanceKm (war geclampt)
    final distKm = result.distanceMeters != null
        ? (result.distanceMeters! / 1000.0).toStringAsFixed(1)
        : '--';
    final durationMin = result.durationSeconds != null
        ? (result.durationSeconds! / 60).round()
        : 0;
    final hours = durationMin ~/ 60;
    final mins = durationMin % 60;
    final timeStr = hours > 0 ? '${hours}h ${mins}min' : '$mins min';
    final curveCount = _cachedCurveCount;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF5722).withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Route berechnet',
            style: TextStyle(
              color: Color(0xFFFF3B30),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildInfoItem(Icons.straighten, '$distKm km', 'Distanz'),
              _buildInfoItem(Icons.timer_outlined, timeStr, 'Dauer'),
              _buildInfoItem(Icons.turn_right, '$curveCount', 'Kurven'),
              _buildInfoItem(
                Icons.star_outline,
                '${_calculateRouteXp()}',
                'XP',
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Berechnet XP für die aktuelle Route via GamificationService.
  int _calculateRouteXp() {
    final distKm = _lastRouteResult?.distanceKm ?? 0;
    return GamificationService.calculateRouteXp(
      distanceKm: distKm,
      curves: _cachedCurveCount,
      style: _selectedStyle,
    );
  }

  Widget _buildInfoItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFFFF3B30), size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════ NAVIGATION OVERLAY ═════════════════════════════

  Widget _buildNavigationOverlay() {
    return Stack(
      children: [
        if (_maneuvers.isNotEmpty)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: CruiseManeuverIndicator(
              maneuver:
                  _maneuvers[_activeManeuverIndex.clamp(
                    0,
                    _maneuvers.length - 1,
                  )],
              distanceToManeuverMeters: _calculateDistanceToManeuver(),
            ),
          ),
        // FAB-Spalte rechts: Simulation + Zentrieren
        Positioned(
          right: 16,
          bottom: 260,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Simulation Start/Stop Button
              if (_isSimulationEnabled && _fullRouteCoordinates.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FloatingActionButton(
                    heroTag: 'simulation_fab',
                    backgroundColor: _isSimulationRunning
                        ? const Color(0xFFFF9500)
                        : const Color(0xFF34C759),
                    foregroundColor: Colors.white,
                    onPressed: _toggleSimulation,
                    child: Icon(
                      _isSimulationRunning
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      size: 28,
                    ),
                  ),
                ),
              // Route-Übersicht Button
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FloatingActionButton.small(
                  heroTag: 'overview_fab',
                  backgroundColor: const Color(0xFF2D3138),
                  foregroundColor: Colors.white,
                  onPressed: _showRouteOverview,
                  child: const Icon(Icons.map_outlined, size: 20),
                ),
              ),
              // Zentrierungs-Button
              FloatingActionButton(
                heroTag: 'recenter_map_fab',
                backgroundColor: _isCameraLocked
                    ? const Color(0xFFFF5722)
                    : const Color(0xFF2D3138),
                foregroundColor: Colors.white,
                onPressed: _toggleCameraLock,
                child: Icon(
                  _isCameraLocked ? Icons.explore : Icons.explore_off,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: CruiseNavigationInfoPanel(
                    durationSeconds: _remainingDuration ?? _routeDuration,
                    distanceMeters: _remainingDistance ?? _routeDistance,
                  ),
                ),
                const SizedBox(height: 4),
                DriveControlPanel(
                  onStart: () async {
                    _startNavigationTracking();
                    _isCameraLocked = true;
                    _activateNavigationCamera();

                    final windowEnd = _findLookAheadIndex(
                      _currentRouteIndex,
                      3000,
                    );
                    setState(() {
                      _remainingRouteCoordinates = _fullRouteCoordinates
                          .sublist(_currentRouteIndex, windowEnd);
                    });
                    await _drawRoute({
                      'type': 'LineString',
                      'coordinates': _remainingRouteCoordinates,
                    }, animateCamera: false);
                  },
                  onPause: () {
                    _stopNavigationTracking();
                  },
                  onStop: () {
                    _stopNavigationTracking();
                    _stopSimulation(restartLiveTracking: false);
                    _onRouteEarlyStopped();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════ MAP WIDGET (flutter_map) ════════════════════════

  Widget _buildMapWidget() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        // Startpunkt: Mitte Deutschlands (wird bei GPS-Erlaubnis sofort überschrieben)
        initialCenter: const LatLng(51.165691, 10.451526),
        initialZoom: 6.0,
        onMapReady: _onMapReady,
        // Bei Berührung der Karte: Kamera-Lock deaktivieren (war Listener-Widget)
        onPointerDown: (event, point) {
          if (_isCameraLocked && _isRouteConfirmed) {
            _safeSetState(() => _isCameraLocked = false);
          }
        },
      ),
      children: [
        // ── Mapbox Dark-Style als Raster-Tile-Layer ──────────────────────────
        // Web: Retina deaktiviert — halbiert Tile-Downloads, weniger Speicher/GPU-Last.
        TileLayer(
          urlTemplate:
              'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/256/{z}/{x}/{y}?access_token={accessToken}',
          additionalOptions: {'accessToken': AppConstants.mapboxPublicToken},
          userAgentPackageName: 'com.cruise_connect.app',
          retinaMode: !kIsWeb,
        ),
        // ── Route (Glow + Hauptlinie) ────────────────────────────────────────
        // Web: Glow-Effekt entfernt — spart eine komplette Polyline-Layer-Berechnung.
        if (_routeLatLngs.length >= 2)
          PolylineLayer(
            polylines: [
              if (!kIsWeb)
                // Glow-Effekt (nur native — auf Web zu teuer für CanvasKit)
                Polyline(
                  points: _routeLatLngs,
                  color: const Color(0x4DFF5722),
                  strokeWidth: 12,
                ),
              // Haupt-Routenlinie
              Polyline(
                points: _routeLatLngs,
                color: const Color(0xFFFF5722),
                strokeWidth: kIsWeb ? 4 : 5,
              ),
            ],
          ),
        // ── Standort-Marker (Apple-Style, immer sichtbar) ──────────────────
        if (_userLocation != null && !_isRouteConfirmed)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(
                  _userLocation!.latitude,
                  _userLocation!.longitude,
                ),
                width: 80,
                height: 80,
                child: _buildAppleLocationDot(_userHeading),
              ),
            ],
          ),
        // ── User-Position Marker (Live-Navigation) ─────────────────────────
        if (_userPosition != null && _isRouteConfirmed)
          MarkerLayer(
            markers: [
              Marker(
                point: _userPosition!,
                width: 80,
                height: 80,
                child: _buildAppleLocationDot(_userHeading),
              ),
            ],
          ),
      ],
    );
  }

  // ═══════════════════════ MAP LIFECYCLE ═════════════════════════════════════

  /// Wird von flutter_map aufgerufen wenn die Karte bereit ist.
  void _onMapReady() {
    _mapReady = true;
    // Route zeichnen falls schon vorhanden, sonst GPS-Position holen
    if (_routeGeoJson != null) {
      final geometry = Map<String, dynamic>.from(
        json.decode(_routeGeoJson!) as Map,
      );
      _drawRoute(geometry);
      if (_isRouteConfirmed) _activateNavigationCamera();
    } else {
      _initializeMapLocation();
    }
  }

  // ═══════════════════════ BOTTOM ACTIONS ═══════════════════════════════════

  Widget _buildBottomActions() {
    return Container(
      height: 160,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xFF0B0E14)],
          stops: [0.0, 0.6],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_routeGeoJson != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _confirmRoute,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: Color(0xFFFF3B30),
                        width: 1.5,
                      ),
                      backgroundColor: const Color(0xFF1C1F26),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    child: const Text(
                      'Route bestätigen',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            Container(
              height: 60,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF3B30).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _generateRoute,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3B30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _isRoundTrip ? 'Rundkurs suchen' : 'Route berechnen',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Apple-Maps-Style Navigations-Marker:
  /// Blauer Richtungspfeil + Genauigkeits-Pulse + weißer Ring + blauer Kern.
  Widget _buildAppleLocationDot(double headingDegrees) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Äußerer Genauigkeits-Pulse (halbtransparenter Ring)
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF007AFF).withValues(alpha: 0.12),
              border: Border.all(
                color: const Color(0xFF007AFF).withValues(alpha: 0.25),
                width: 1.5,
              ),
            ),
          ),
          // Richtungspfeil (dreht sich smooth mit Heading)
          AnimatedRotation(
            turns: headingDegrees / 360.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: CustomPaint(
              size: const Size(80, 80),
              painter: _NavigationArrowPainter(),
            ),
          ),
          // Weißer Ring mit Schatten
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x50000000),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          // Blauer Kern
          Container(
            width: 15,
            height: 15,
            decoration: const BoxDecoration(
              color: Color(0xFF007AFF),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════ LOCATION ═════════════════════════════════════════

  Future<void> _initializeMapLocation() async {
    try {
      // Auf Web: checkPermission/requestPermission nicht unterstützt →
      // Browser zeigt automatisch einen eigenen Permission-Dialog beim ersten
      // getCurrentPosition()-Aufruf. Wir überspringen den nativen Check.
      if (!kIsWeb) {
        final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) return;

        var permission = await geo.Geolocator.checkPermission();
        if (permission == geo.LocationPermission.denied) {
          permission = await geo.Geolocator.requestPermission();
          if (permission == geo.LocationPermission.denied) return;
        }
        if (permission == geo.LocationPermission.deniedForever) return;
      }

      // Erst instant den letzten bekannten Standort verwenden (nicht auf Web verfügbar)
      if (!kIsWeb) {
        geo.Position? position = await geo.Geolocator.getLastKnownPosition();
        if (position != null) {
          _userLocation = position;
          _setCameraToPosition(position);
        }
      }

      // Dann genauere Position holen (auf Web ist das der erste Aufruf)
      try {
        final freshPosition = await geo.Geolocator.getCurrentPosition(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.medium,
            timeLimit: Duration(seconds: 10),
          ),
        );
        _userLocation = freshPosition;
        if (freshPosition.heading.isFinite &&
            freshPosition.heading >= 0 &&
            freshPosition.heading <= 360) {
          _userHeading = freshPosition.heading;
        }
        _setCameraToPosition(freshPosition);
        _safeSetState(() {}); // Marker-Refresh
      } catch (e) {
        debugPrint('[CruiseMode] Frische GPS-Position nicht verfügbar: $e');
      }

      // Idle-Positions-Stream starten für Heading-Updates (stoppt wenn Navigation startet)
      _startIdlePositionStream();
    } catch (e) {
      debugPrint('Konnte Karten-Position nicht setzen: $e');
    }
  }

  void _startIdlePositionStream() {
    _idlePositionSubscription?.cancel();
    // distanceFilter=0 auf allen Plattformen: auch reine Heading-Änderungen
    // (Kompass-Drehung ohne Bewegung) sollen durchkommen.
    const settings = kIsWeb
        ? geo.LocationSettings(
            accuracy: geo.LocationAccuracy.best,
            distanceFilter: 0,
          )
        : geo.LocationSettings(
            accuracy: geo.LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
          );
    _idlePositionSubscription =
        geo.Geolocator.getPositionStream(locationSettings: settings).listen(
          (position) {
            if (!mounted || _disposed) return;
            // Web: Smoother anwenden für flüssige Darstellung
            if (kIsWeb) {
              final smoothed = _webSmoother.update(position);
              // Heading trotzdem immer aktualisieren (auch ohne Positions-Rebuild)
              _userHeading = _webSmoother.heading;
              if (smoothed != null) {
                _userLocation = smoothed;
              }
            } else {
              _userLocation = position;
              if (position.heading.isFinite &&
                  position.heading >= 0 &&
                  position.heading <= 360) {
                _userHeading = position.heading;
              }
            }
            // Idle-Rebuilds auf 100ms throttlen: flüssige Kompass-Rotation
            final now = DateTime.now();
            if (_lastWebRebuildTime != null &&
                now.difference(_lastWebRebuildTime!).inMilliseconds < 100) {
              return;
            }
            _lastWebRebuildTime = now;
            _safeSetState(() {});
          },
          onError: (Object e) {
            debugPrint('[CruiseMode] Idle-Positionsstream Fehler: $e');
          },
        );
  }

  void _stopIdlePositionStream() {
    _idlePositionSubscription?.cancel();
    _idlePositionSubscription = null;
  }

  void _setCameraToPosition(geo.Position position) {
    if (!_mapReady) return;
    try {
      _mapController.move(LatLng(position.latitude, position.longitude), 13.0);
    } catch (e) {
      debugPrint('[CruiseMode] setCamera fehlgeschlagen: $e');
    }
  }

  Future<geo.Position> _getStartCoordinates() async {
    if (_selectedLocation == 'Aktueller Standort') {
      if (!kIsWeb) {
        bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          throw Exception(
            'Bitte aktiviere GPS/Standort in deinen Geräteeinstellungen.',
          );
        }

        var permission = await geo.Geolocator.checkPermission();
        if (permission == geo.LocationPermission.denied) {
          permission = await geo.Geolocator.requestPermission();
          if (permission == geo.LocationPermission.denied) {
            throw Exception('Standortberechtigung verweigert.');
          }
        }
        if (permission == geo.LocationPermission.deniedForever) {
          throw Exception('Standortberechtigung dauerhaft verweigert.');
        }
      }

      if (!kIsWeb) {
        geo.Position? lastPosition =
            await geo.Geolocator.getLastKnownPosition();
        if (lastPosition != null) return lastPosition;
      }

      try {
        return await geo.Geolocator.getCurrentPosition(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.best,
          ),
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw Exception(
              'Standort konnte nicht ermittelt werden. Bitte versuche es erneut.',
            );
          },
        );
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('denied') || msg.contains('permission')) {
          throw Exception(
            'Bitte erlaube den Standortzugriff in deinen Browser-/Geräteeinstellungen und lade die Seite neu.',
          );
        }
        rethrow;
      }
    }
    // Fallback: Eigene Position verwenden wenn vorhanden, sonst Vorarlberg
    if (_userLocation != null) return _userLocation!;
    return geo.Position(
      longitude: 9.7415,
      latitude: 47.2607,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
  }

  // ═══════════════════════ ROUTE GENERATION ════════════════════════════════

  Future<void> _generateRoute() async {
    // Doppelklick-Schutz: Wenn bereits generiert wird, ignorieren
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final startPosition = await _getStartCoordinates();

      final digits = _selectedLength.replaceAll(RegExp(r'[^0-9]'), '');
      final distance = digits.isNotEmpty ? int.parse(digits) : 50;
      double? destLat;
      double? destLng;
      var detourVariant = 0;
      var scenicMode = false;

      Map<String, double>? targetLocation;
      if (_requiresDestination(_isRoundTrip) &&
          _destinationController.text.isNotEmpty) {
        try {
          targetLocation = await _geocodingService.getCoordinatesFromAddress(
            _destinationController.text,
          );
        } on GeocodingException catch (e) {
          debugPrint('[CruiseMode] Geocoding failed: ${e.debugMessage}');
          _showError(e.userMessage);
          return;
        }
        if (targetLocation == null && mounted) {
          _showError('Konnte Zieladresse nicht finden.');
          return;
        }
      }

      // Eine Route generieren — kein Warmup/Skip mehr (spart Mapbox Tokens)
      RouteResult result;
      if (_requiresDestination(_isRoundTrip)) {
        if (_selectedDestination != null) {
          destLat = _selectedDestination!.latitude;
          destLng = _selectedDestination!.longitude;
        } else if (targetLocation != null) {
          destLat = targetLocation['latitude'];
          destLng = targetLocation['longitude'];
        }
        if (destLat == null || destLng == null) {
          throw Exception('Bitte wähle ein Ziel aus.');
        }
        // Umweg-Variante bestimmen (0 = direkt, 1-3 = Umwege)
        detourVariant = switch (_selectedDetour) {
          'Kleiner Umweg' => 1,
          'Mittlerer Umweg' => 2,
          'Großer Umweg' => 3,
          _ => 0,
        };
        scenicMode = _selectedDetour != 'Direkt';
        _activeDestinationCoordinate = [destLng, destLat];
        _activeDetourVariant = detourVariant;
        _activePointToPointScenic = scenicMode;
        _activePointToPointMode = scenicMode ? _selectedStyle : 'Standard';
        _activeAvoidHighways = _avoidHighways;
        _recentDestinationDistances = [];
        result = await _routeService.generatePointToPoint(
          startPosition: startPosition,
          destinationLat: destLat,
          destinationLng: destLng,
          mode: scenicMode ? _selectedStyle : 'Standard',
          scenic: scenicMode,
          routeVariant: detourVariant,
          avoidHighways: _avoidHighways,
        );
      } else {
        _activeDestinationCoordinate = null;
        _activeDetourVariant = 0;
        _activePointToPointScenic = false;
        _activePointToPointMode = 'Standard';
        _activeAvoidHighways = false;
        _recentDestinationDistances = [];
        result = await _routeService.generateRoundTrip(
          startPosition: startPosition,
          targetDistanceKm: distance,
          mode: _selectedStyle,
          planningType: _planningType,
        );
      }

      // ── Qualitätsprüfung mit RouteQualityValidator ─────────────────────
      const validator = RouteQualityValidator();
      final actualKm = result.distanceKm ?? 0;
      final targetKm = _isRoundTrip ? distance.toDouble() : 0.0;

      var quality = validator.validateQuality(
        coordinates: result.coordinates,
        isRoundTrip: _isRoundTrip,
        targetDistanceKm: targetKm,
        actualDistanceKm: actualKm,
      );
      var routeClassification = validator.classifyGeneratedRoute(
        quality: quality,
        isRoundTrip: _isRoundTrip,
        coordinateCount: result.coordinates.length,
        actualDistanceKm: actualKm,
        targetDistanceKm: targetKm,
      );
      final routeConfigKey = _buildRouteConfigKey(
        startPosition: startPosition,
        isRoundTrip: _isRoundTrip,
        targetDistanceKm: distance,
        planningType: _planningType,
        style: _selectedStyle,
        detour: _selectedDetour,
        avoidHighways: _avoidHighways,
        destinationLat: destLat,
        destinationLng: destLng,
      );

      // Basis-Check: zu wenige Punkte oder komplett falsche Distanz
      final minimumPointCount = _minimumRoutePointCount(
        isRoundTrip: _isRoundTrip,
        targetDistanceKm: targetKm,
        actualDistanceKm: actualKm,
      );
      var tooFewPoints = result.coordinates.length < minimumPointCount;

      // Qualitätsprüfung mit paralleler Generierung statt sequentieller Retries
      // → 5 Routen gleichzeitig generieren und die beste auswählen
      if ((!routeClassification.isAcceptable || tooFewPoints) && _isRoundTrip) {
        debugPrint(
          '[CruiseMode] Rundkurs-Qualität noch nicht ausreichend: '
          '${routeClassification.tier} / score=${routeClassification.score.toStringAsFixed(1)} '
          '— generiere 5 Alternativen parallel',
        );
        var bestResult = result;
        var bestQuality = quality;
        var bestClassification = routeClassification;

        // Parallele Generierung: 5 Routen gleichzeitig statt sequentiell
        final candidates = await _routeService.generateMultipleRoundTrips(
          startPosition: startPosition,
          targetDistanceKm: distance,
          mode: _selectedStyle,
          planningType: _planningType,
          count: 5,
        );

        for (var i = 0; i < candidates.length; i++) {
          final candidate = candidates[i];
          final retryKm = candidate.distanceKm ?? 0;
          quality = validator.validateQuality(
            coordinates: candidate.coordinates,
            isRoundTrip: true,
            targetDistanceKm: targetKm,
            actualDistanceKm: retryKm,
          );
          final retryClassification = validator.classifyGeneratedRoute(
            quality: quality,
            isRoundTrip: true,
            coordinateCount: candidate.coordinates.length,
            actualDistanceKm: retryKm,
            targetDistanceKm: targetKm,
          );
          debugPrint(
            '[CruiseMode] Kandidat ${i + 1}: Overlap=${quality.overlapPercent.toStringAsFixed(1)}%, '
            'Wenden=${quality.uturnPositions.length}, tier=${retryClassification.tier}, '
            'score=${retryClassification.score.toStringAsFixed(1)}',
          );

          if (retryClassification.score < bestClassification.score) {
            bestResult = candidate;
            bestQuality = quality;
            bestClassification = retryClassification;
          }

          if (retryClassification.isIdeal) {
            debugPrint(
              '[CruiseMode] Kandidat ${i + 1} ist ideal — übernommen',
            );
            break;
          }
        }

        result = bestResult;
        quality = bestQuality;
        routeClassification = bestClassification;
        debugPrint(
          '[CruiseMode] Beste Route gewählt: '
          'tier=${routeClassification.tier}, score=${routeClassification.score.toStringAsFixed(1)}',
        );
      } else if ((!quality.passed || tooFewPoints) &&
          !_isRoundTrip &&
          destLat != null &&
          destLng != null) {
        debugPrint(
          '[CruiseMode] A→B-Qualität schlecht: $quality — generiere 4 Alternativen parallel',
        );
        var bestResult = result;
        var bestOverlap = quality.overlapPercent;
        var bestUturns = quality.uturnPositions.length;
        var bestPointScore = result.coordinates.length;

        // Parallele Generierung: 4 A→B-Routen gleichzeitig
        final candidates = await _routeService.generateMultiplePointToPoints(
          startPosition: startPosition,
          destinationLat: destLat,
          destinationLng: destLng,
          mode: scenicMode ? _selectedStyle : 'Standard',
          scenic: scenicMode,
          routeVariant: detourVariant,
          avoidHighways: _avoidHighways,
          count: 4,
        );

        for (var i = 0; i < candidates.length; i++) {
          final candidate = candidates[i];
          final retryKm = candidate.distanceKm ?? 0;
          quality = validator.validateQuality(
            coordinates: candidate.coordinates,
            isRoundTrip: false,
            actualDistanceKm: retryKm,
          );
          final retryTooFewPoints =
              candidate.coordinates.length < 30 && retryKm >= 10;
          debugPrint(
            '[CruiseMode] A→B Kandidat ${i + 1}: Overlap=${quality.overlapPercent.toStringAsFixed(1)}%, '
            'Wenden=${quality.uturnPositions.length}, Punkte=${candidate.coordinates.length} '
            '→ ${(quality.passed && !retryTooFewPoints) ? "OK" : "verworfen"}',
          );

          final score =
              quality.overlapPercent +
              quality.uturnPositions.length * 10 +
              (retryTooFewPoints ? 30 : 0);
          final bestScore =
              bestOverlap + bestUturns * 10 + (bestPointScore < 30 ? 30 : 0);
          if (score < bestScore) {
            bestResult = candidate;
            bestOverlap = quality.overlapPercent;
            bestUturns = quality.uturnPositions.length;
            bestPointScore = candidate.coordinates.length;
          }

          if (quality.passed && !retryTooFewPoints) {
            debugPrint('[CruiseMode] A→B Kandidat ${i + 1} OK — übernommen');
            break;
          }
        }

        result = bestResult;
        debugPrint(
          '[CruiseMode] Beste A→B-Route: Overlap=${bestOverlap.toStringAsFixed(1)}%, '
          'Wenden=$bestUturns, Punkte=$bestPointScore',
        );
      }

      quality = validator.validateQuality(
        coordinates: result.coordinates,
        isRoundTrip: _isRoundTrip,
        targetDistanceKm: targetKm,
        actualDistanceKm: result.distanceKm ?? 0,
      );
      routeClassification = validator.classifyGeneratedRoute(
        quality: quality,
        isRoundTrip: _isRoundTrip,
        coordinateCount: result.coordinates.length,
        actualDistanceKm: result.distanceKm ?? 0,
        targetDistanceKm: targetKm,
      );
      tooFewPoints = _isRoundTrip
          ? result.coordinates.length <
                _minimumRoutePointCount(
                  isRoundTrip: true,
                  targetDistanceKm: targetKm,
                  actualDistanceKm: result.distanceKm ?? 0,
                )
          : result.coordinates.length <
                _minimumRoutePointCount(
                  isRoundTrip: false,
                  targetDistanceKm: targetKm,
                  actualDistanceKm: result.distanceKm ?? 0,
                );

      final shouldAvoidDuplicateRoutes = _isRoundTrip || scenicMode;
      final similarityThresholdPercent = _routeSimilarityThresholdPercent(
        isRoundTrip: _isRoundTrip,
        scenicMode: scenicMode,
        detourVariant: detourVariant,
      );
      if (shouldAvoidDuplicateRoutes &&
          _isRouteTooSimilarToPrevious(
            routeConfigKey,
            result,
            thresholdPercent: similarityThresholdPercent,
          )) {
        final duplicateRetryLimit = (!_isRoundTrip && detourVariant == 1)
            ? 5
            : 3;
        for (
          var duplicateRetry = 0;
          duplicateRetry < duplicateRetryLimit;
          duplicateRetry++
        ) {
          debugPrint(
            '[CruiseMode] Ähnliche Route erkannt — generiere Alternative '
            '(${duplicateRetry + 1}/$duplicateRetryLimit)',
          );
          final candidate = _isRoundTrip
              ? await _routeService.generateRoundTrip(
                  startPosition: startPosition,
                  targetDistanceKm: distance,
                  mode: _selectedStyle,
                  planningType: _planningType,
                )
              : await _routeService.generatePointToPoint(
                  startPosition: startPosition,
                  destinationLat: destLat!,
                  destinationLng: destLng!,
                  mode: scenicMode ? _selectedStyle : 'Standard',
                  scenic: scenicMode,
                  routeVariant: detourVariant,
                  avoidHighways: _avoidHighways,
                );
          final candidateDistanceKm = candidate.distanceKm ?? 0;
          final candidateQuality = validator.validateQuality(
            coordinates: candidate.coordinates,
            isRoundTrip: _isRoundTrip,
            targetDistanceKm: targetKm,
            actualDistanceKm: candidateDistanceKm,
          );
          final candidateClassification = validator.classifyGeneratedRoute(
            quality: candidateQuality,
            isRoundTrip: _isRoundTrip,
            coordinateCount: candidate.coordinates.length,
            actualDistanceKm: candidateDistanceKm,
            targetDistanceKm: targetKm,
          );
          final candidateTooFewPoints = _isRoundTrip
              ? candidate.coordinates.length <
                    _minimumRoutePointCount(
                      isRoundTrip: true,
                      targetDistanceKm: targetKm,
                      actualDistanceKm: candidateDistanceKm,
                    )
              : candidate.coordinates.length <
                    _minimumRoutePointCount(
                      isRoundTrip: false,
                      targetDistanceKm: targetKm,
                      actualDistanceKm: candidateDistanceKm,
                    );

          if (candidateTooFewPoints ||
              (!_isRoundTrip && !candidateQuality.passed)) {
            debugPrint(
              '[CruiseMode] Alternative verworfen: Qualität nicht ausreichend.',
            );
            continue;
          }

          result = candidate;
          quality = candidateQuality;
          routeClassification = candidateClassification;
          if (!_isRouteTooSimilarToPrevious(
            routeConfigKey,
            result,
            thresholdPercent: similarityThresholdPercent,
          )) {
            break;
          }
        }
      }

      if (shouldAvoidDuplicateRoutes) {
        _rememberRouteSnapshot(routeConfigKey, result);
      }

      _applyRouteResult(result);
      await _drawRoute(result.geometry);

      // Config einklappen + Info-Banner anzeigen damit man die Route sieht
      if (mounted) {
        setState(() {
          _configCollapsed = true;
          _showRouteInfoBanner = true;
        });
      }
    } catch (e, stack) {
      debugPrint('[CruiseMode] Route generation failed: $e');
      debugPrintStack(
        label: '[CruiseMode] Route generation stacktrace',
        stackTrace: stack,
      );
      final userMessage = e is RouteServiceException
          ? e.userMessage
          : _sanitizeErrorMessage(e.toString());
      _showError(userMessage);
    } finally {
      _safeSetState(() => _isLoading = false);
    }
  }

  String _sanitizeErrorMessage(String raw) {
    final withoutPrefix = raw.replaceFirst('Exception: ', '').trim();
    if (withoutPrefix.isEmpty) {
      return 'Routenberechnung fehlgeschlagen. Bitte erneut versuchen.';
    }
    return withoutPrefix;
  }

  void _applyRouteResult(RouteResult result) {
    _lastRouteResult = result;
    _activeSpeedLimits = result.speedLimits;
    _recentDestinationDistances = [];
    setState(() {
      _routeGeoJson = result.geoJson;
      _routeDistance = result.distanceMeters;
      _routeDuration = result.durationSeconds;
      _originalRouteDistance = result.distanceMeters;
      _originalRouteDuration = result.durationSeconds;
      _isRouteConfirmed = false;
      _fullRouteCoordinates = result.coordinates;
      _remainingRouteCoordinates = result.coordinates;
      _maneuvers = result.maneuvers;
      _activeManeuverIndex = 0;
      _currentRouteIndex = 0;
      _lastDrawnRouteIndex = 0;
      _distanceSinceLastRedraw = 0.0;
      _announcedManeuverIndices.clear();
      _totalDistanceDriven = 0.0;
      _navigationStartTime = null;
      _offRouteCount = 0;
      _lastRerouteTime = null;
      _remainingDistance = null;
      _remainingDuration = null;
      _cachedCurveCount = 0;
    });
    // Kurven async im Isolate berechnen (blockiert UI nicht)
    GamificationService.countCurvesAsync(result.coordinates).then((count) {
      if (mounted) setState(() => _cachedCurveCount = count);
    });
  }

  void _onDestinationSelected(MapboxSuggestion suggestion) {
    setState(() {
      _selectedDestination = suggestion;
      _destinationController.text = suggestion.placeName;
    });
  }

  void _handleDetourChanged(String detour) {
    setState(() {
      _selectedDetour = detour;
      if (detour == 'Direkt') {
        return;
      }
      const allowedStyles = {
        'Kurvenjagd',
        'Sport Mode',
        'Abendrunde',
        'Entdecker',
      };
      if (!allowedStyles.contains(_selectedStyle) ||
          _selectedStyle == 'Direkt') {
        _selectedStyle = 'Abendrunde';
      }
    });
  }

  double _currentPointToPointCorridorMeters() {
    if (_activeDetourVariant >= 2) {
      return 800;
    }
    if (_activeDetourVariant == 1) {
      return 500;
    }
    return 300;
  }

  bool _isApproachingCurrentDestination(geo.Position position) {
    final destination = _activeDestinationCoordinate;
    if (destination == null) return false;

    final distance = distanceToCoordinateMeters(
      position: position,
      coordinate: destination,
    );
    _recentDestinationDistances = [..._recentDestinationDistances, distance];
    if (_recentDestinationDistances.length > 5) {
      _recentDestinationDistances = _recentDestinationDistances.sublist(
        _recentDestinationDistances.length - 5,
      );
    }

    return isApproachingDestination(_recentDestinationDistances);
  }

  String _buildRouteConfigKey({
    required geo.Position startPosition,
    required bool isRoundTrip,
    required int targetDistanceKm,
    required String planningType,
    required String style,
    required String detour,
    required bool avoidHighways,
    double? destinationLat,
    double? destinationLng,
  }) {
    final startBucket =
        '${startPosition.latitude.toStringAsFixed(3)},${startPosition.longitude.toStringAsFixed(3)}';
    if (isRoundTrip) {
      return 'rt|$startBucket|$targetDistanceKm|$planningType|$style';
    }

    final destinationBucket = destinationLat != null && destinationLng != null
        ? '${destinationLat.toStringAsFixed(3)},${destinationLng.toStringAsFixed(3)}'
        : 'none';
    final effectiveStyle = detour == 'Direkt' ? 'Standard' : style;
    return 'ab|$startBucket|$destinationBucket|$detour|$effectiveStyle|$avoidHighways';
  }

  double _routeSimilarityThresholdPercent({
    required bool isRoundTrip,
    required bool scenicMode,
    required int detourVariant,
  }) {
    if (isRoundTrip) return 80.0;
    if (!scenicMode) return 88.0;
    if (detourVariant <= 1) return 76.0;
    if (detourVariant == 2) return 74.0;
    return 72.0;
  }

  int _minimumRoutePointCount({
    required bool isRoundTrip,
    required double targetDistanceKm,
    required double actualDistanceKm,
  }) {
    if (!isRoundTrip) {
      return actualDistanceKm >= 10 ? 30 : 0;
    }
    if (targetDistanceKm >= 120) return 28;
    if (targetDistanceKm >= 75) return 24;
    if (targetDistanceKm >= 35) return 20;
    return actualDistanceKm >= 15 ? 18 : 14;
  }

  bool _isRouteTooSimilarToPrevious(
    String routeConfigKey,
    RouteResult result, {
    required double thresholdPercent,
  }) {
    final history = _recentRoutesByConfig[routeConfigKey];
    if (history == null || history.isEmpty) return false;

    final candidateCoordinates = _sampleCoordinatesForSimilarity(
      result.coordinates,
    );
    final candidateFingerprint = RouteQualityValidator.buildRouteFingerprint(
      candidateCoordinates,
      distanceKm: result.distanceKm,
      precision: 4,
    );

    if (history.any((item) => item.fingerprint == candidateFingerprint)) {
      return true;
    }

    final tooSimilar = RouteQualityValidator.isRouteTooSimilarToPrevious(
      candidateCoordinates,
      history.map((item) => item.coordinates),
      thresholdPercent: thresholdPercent,
      sampleCount: 40,
      proximityMeters: _isRoundTrip ? 130.0 : 160.0,
    );
    if (tooSimilar) {
      debugPrint(
        '[CruiseMode] Route verworfen: zu ähnlich zur letzten Route '
        '(threshold=${thresholdPercent.toStringAsFixed(1)}%)',
      );
    }
    return tooSimilar;
  }

  void _rememberRouteSnapshot(String routeConfigKey, RouteResult result) {
    final sampledCoordinates = _sampleCoordinatesForSimilarity(
      result.coordinates,
    );
    final fingerprint = RouteQualityValidator.buildRouteFingerprint(
      sampledCoordinates,
      distanceKm: result.distanceKm,
      precision: 4,
    );
    final updated = [...?_recentRoutesByConfig[routeConfigKey]];
    if (!updated.any((item) => item.fingerprint == fingerprint)) {
      updated.add(
        _RecentRouteSignature(
          fingerprint: fingerprint,
          coordinates: sampledCoordinates,
        ),
      );
    }
    if (updated.length > 4) {
      updated.removeRange(0, updated.length - 4);
    }
    _recentRoutesByConfig[routeConfigKey] = updated;
  }

  List<List<double>> _sampleCoordinatesForSimilarity(
    List<List<double>> coordinates, {
    int maxSamples = 80,
  }) {
    if (coordinates.length <= maxSamples) {
      return coordinates
          .where((point) => point.length >= 2)
          .map((point) => [point[0], point[1]])
          .toList();
    }
    final sampled = <List<double>>[];
    for (var i = 0; i < maxSamples; i++) {
      final ratio = maxSamples == 1 ? 0.0 : i / (maxSamples - 1);
      final index = ((coordinates.length - 1) * ratio).round();
      final point = coordinates[index];
      if (point.length < 2) continue;
      sampled.add([point[0], point[1]]);
    }
    return sampled;
  }

  String _rerouteMode({required bool mergeWithOriginal}) {
    if (!_activePointToPointScenic || mergeWithOriginal) {
      return 'Standard';
    }
    return _activePointToPointMode;
  }

  int _rerouteVariant({required bool mergeWithOriginal}) {
    if (!_activePointToPointScenic || mergeWithOriginal) {
      return 0;
    }
    return _activeDetourVariant;
  }

  List<SpeedLimitSegment> _mergeSpeedLimits(
    List<SpeedLimitSegment> rerouteSpeedLimits,
    int rejoinIndex,
    int rerouteCoordinateCount, {
    int skippedOriginalCoordinates = 0,
  }) {
    final remaining = _activeSpeedLimits
        .where(
          (segment) =>
              segment.endIndex >= rejoinIndex + skippedOriginalCoordinates,
        )
        .map((segment) {
          final startIndex =
              math.max(
                0,
                segment.startIndex - rejoinIndex - skippedOriginalCoordinates,
              ) +
              rerouteCoordinateCount;
          final endIndex =
              math.max(
                0,
                segment.endIndex - rejoinIndex - skippedOriginalCoordinates,
              ) +
              rerouteCoordinateCount;
          return SpeedLimitSegment(
            startIndex: startIndex,
            endIndex: endIndex,
            speedKmh: segment.speedKmh,
          );
        })
        .toList();

    return [...rerouteSpeedLimits, ...remaining];
  }

  RouteResult _buildRouteResultFromCoordinates({
    required List<List<double>> coordinates,
    required List<RouteManeuver> maneuvers,
    required double? distanceMeters,
    required double? durationSeconds,
    required List<SpeedLimitSegment> speedLimits,
  }) {
    final geometry = <String, dynamic>{
      'type': 'LineString',
      'coordinates': coordinates,
    };
    return RouteResult(
      geoJson: json.encode(geometry),
      geometry: geometry,
      coordinates: coordinates,
      maneuvers: maneuvers,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      distanceKm: distanceMeters != null ? distanceMeters / 1000 : null,
      speedLimits: speedLimits,
    );
  }

  double _calculatePolylineDistanceMeters(List<List<double>> coordinates) {
    if (coordinates.length < 2) return 0;

    var distance = 0.0;
    for (var i = 0; i < coordinates.length - 1; i++) {
      final from = coordinates[i];
      final to = coordinates[i + 1];
      distance += geo.Geolocator.distanceBetween(
        from[1],
        from[0],
        to[1],
        to[0],
      );
    }
    return distance;
  }

  double _estimateDurationSecondsForDistance(double distanceMeters) {
    final referenceDuration = _originalRouteDuration ?? _routeDuration;
    final referenceDistance = _originalRouteDistance ?? _routeDistance;
    if (referenceDuration != null &&
        referenceDistance != null &&
        referenceDuration > 0 &&
        referenceDistance > 0) {
      return referenceDuration * (distanceMeters / referenceDistance);
    }
    return distanceMeters / 13.89;
  }

  Future<void> _commitRerouteResult({
    required RouteResult result,
    required geo.Position position,
  }) async {
    _lastRouteResult = result;
    _activeSpeedLimits = result.speedLimits;
    _recentDestinationDistances = [];

    _safeSetState(() {
      _routeGeoJson = result.geoJson;
      _routeDistance = result.distanceMeters;
      _routeDuration = result.durationSeconds;
      _originalRouteDistance = result.distanceMeters;
      _originalRouteDuration = result.durationSeconds;
      _fullRouteCoordinates = result.coordinates;
      _remainingRouteCoordinates = result.coordinates;
      _currentRouteIndex = 0;
      _lastDrawnRouteIndex = 0;
      _distanceSinceLastRedraw = 0.0;
      _maneuvers = result.maneuvers;
      _activeManeuverIndex = 0;
      _announcedManeuverIndices.clear();
      _offRouteCount = 0;
      _lastRerouteTime = DateTime.now();
      _remainingDistance = result.distanceMeters;
      _remainingDuration = result.durationSeconds;
    });

    GamificationService.countCurvesAsync(result.coordinates).then((count) {
      if (mounted) {
        setState(() => _cachedCurveCount = count);
      }
    });

    final windowEnd = _findLookAheadIndex(0, 3000);
    final routeSlice = result.coordinates.sublist(
      0,
      math.min(windowEnd, result.coordinates.length),
    );
    if (routeSlice.isNotEmpty) {
      routeSlice[0] = [position.longitude, position.latitude];
    }

    _remainingRouteCoordinates = routeSlice;
    final clipped = {
      'type': 'LineString',
      'coordinates': _remainingRouteCoordinates,
    };
    _routeGeoJson = json.encode(clipped);
    await _drawRoute(clipped, animateCamera: false);
  }

  // ═══════════════════════ LOAD SAVED ROUTE ══════════════════════════════════

  Future<void> _loadSavedRoute(SavedRoute route) async {
    final geometry = route.geometry;
    final coordsRaw = (geometry['coordinates'] as List?) ?? const [];
    final coordinates = coordsRaw
        .whereType<List>()
        .where((c) => c.length >= 2)
        .map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
        .toList();

    if (coordinates.length < 2) {
      _showError('Route hat nicht genug Koordinaten.');
      return;
    }

    final previewResult = RouteResult(
      geoJson: json.encode(geometry),
      geometry: geometry,
      coordinates: coordinates,
      maneuvers: const [],
      distanceMeters: route.distanceKm * 1000,
      durationSeconds: route.durationSeconds,
      distanceKm: route.distanceKm,
    );

    _applyRouteResult(previewResult);
    final lastCoordinate = coordinates.last;
    setState(() {
      _isRoundTrip = route.isRoundTrip;
      _selectedStyle = route.style;
      _selectedDetour = 'Direkt';
      _avoidHighways = false;
      _selectedDestination = null;
      _destinationController.clear();
      _isCameraLocked = false;
      _configCollapsed = true;
      _showRouteInfoBanner = true;
      _activeDestinationCoordinate = route.isRoundTrip ? null : lastCoordinate;
      _activeDetourVariant = 0;
      _activePointToPointScenic =
          !route.isRoundTrip && route.style != 'Standard';
      _activePointToPointMode = route.style;
      _activeAvoidHighways = false;
      _recentDestinationDistances = [];
    });
    CruiseModePage.isFullscreen.value = false;

    await _drawRoute(geometry);
  }

  // ═══════════════════════ ROUTE CONFIRM ═════════════════════════════════════

  Future<void> _confirmRoute() async {
    setState(() {
      _isRouteConfirmed = true;
      _currentRouteIndex = 0;
      _lastDrawnRouteIndex = 0;
      _distanceSinceLastRedraw = 0.0;
      _showRouteInfoBanner = false;
      _configCollapsed = false;
      _remainingRouteCoordinates = _fullRouteCoordinates;
      // Kein _viewportState mehr (flutter_map nutzt MapController)
    });
    _recentDestinationDistances = [];
    CruiseModePage.isFullscreen.value = true;

    // Kartenkacheln entlang der Route im Hintergrund cachen
    OfflineMapService.instance.cacheRouteRegion(_fullRouteCoordinates);

    // Route wird erst nach Fahrtende gespeichert (mit Bewertung + XP-Sync)

    // _startNavigationTracking(); // Tracking startet erst bei Klick auf "Fahrt starten"
    // if (total >= 2) {
    //   await _drawRoute(
    //     {'type': 'LineString', 'coordinates': _remainingRouteCoordinates},
    //     animateCamera: false,
    //   );
    // }
    // await _activateNavigationCamera(); // 3D Kamera startet erst bei "Fahrt starten"
  }

  // ═══════════════════════ LOOK-AHEAD HELPER ════════════════════════════════

  int _findLookAheadIndex(int startIndex, double targetMeters) {
    double accumulated = 0.0;
    final total = _fullRouteCoordinates.length;
    for (var i = startIndex; i < total - 1; i++) {
      final c1 = _fullRouteCoordinates[i];
      final c2 = _fullRouteCoordinates[i + 1];
      accumulated += geo.Geolocator.distanceBetween(c1[1], c1[0], c2[1], c2[0]);
      if (accumulated >= targetMeters) return math.min(i + 2, total);
    }
    return total;
  }

  // ═══════════════════════ ROUTE DRAWING (flutter_map) ══════════════════════
  //
  // Statt Mapbox GeoJSON Sources/Layers zu verwalten, setzen wir einfach State.
  // flutter_map rendert PolylineLayer und MarkerLayer automatisch neu.

  Future<void> _drawRoute(
    Map<String, dynamic> geometry, {
    bool animateCamera = true,
  }) async {
    final coordinatesRaw = (geometry['coordinates'] as List?) ?? const [];
    final activeCoordinates = coordinatesRaw
        .whereType<List>()
        .where((c) => c.length >= 2)
        .map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
        .toList();
    if (activeCoordinates.length < 2) return;

    // KRITISCH: Mapbox liefert [longitude, latitude], flutter_map braucht LatLng(lat, lng)
    final routeLatLngs = activeCoordinates
        .map((c) => LatLng(c[1], c[0])) // [lng, lat] → LatLng(lat, lng)
        .toList();

    _safeSetState(() {
      _routeLatLngs = routeLatLngs;
    });

    if (animateCamera && _mapReady && routeLatLngs.isNotEmpty && mounted) {
      // Kurze Verzögerung damit setState durchgelaufen ist
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted || _disposed) return;
      try {
        final bounds = LatLngBounds.fromPoints(routeLatLngs);
        final safeTop = MediaQuery.of(context).padding.top;
        final safeBottom = MediaQuery.of(context).padding.bottom;
        final bottomPad =
            (_isRouteConfirmed ? safeBottom + 130 : safeBottom + 48).clamp(
              48.0,
              220.0,
            );
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: EdgeInsets.fromLTRB(24, safeTop + 18, 24, bottomPad),
          ),
        );
      } catch (e) {
        debugPrint('[CruiseMode] Camera fit fehlgeschlagen: $e');
      }
    }
  }

  // ═══════════════════════ OVERLAP DETECTION ════════════════════════════════

  // ═══════════════════════ NAVIGATION TRACKING ══════════════════════════════

  void _startNavigationTracking() {
    _stopIdlePositionStream(); // Idle-Stream stoppen, Navigation übernimmt
    _positionSubscription?.cancel();
    _socketPositionSubscription?.cancel();

    // Navigations-Startzeit setzen (nur beim ersten Start, nicht bei Resume)
    _navigationStartTime ??= DateTime.now();

    // Web: Smoother resetten für frischen Start
    if (kIsWeb) _webSmoother.reset();

    _distanceSinceLastRedraw = 0.0;
    _lastDrawnRouteIndex = _currentRouteIndex;

    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _socketPositionSubscription = _navigationSocketService.positionStream
        .listen(
          _onLocationUpdate,
          onError: (Object error) {
            debugPrint('[CruiseMode] Socket-Positionsstream Fehler: $error');
          },
        );
    unawaited(
      _navigationSocketService.openSession(sessionId).catchError((
        Object error,
      ) {
        debugPrint(
          '[CruiseMode] Socket-Session konnte nicht gestartet werden: $error',
        );
      }),
    );

    // Web: distanceFilter=0 (Browser-API unterstützt kein natives Distanz-Filtern).
    // iOS/Android: 1m Filter für hochfrequente Updates (Apple-Maps-Feeling).
    const locationSettings = kIsWeb
        ? geo.LocationSettings(
            accuracy: geo.LocationAccuracy.best,
            distanceFilter: 0,
          )
        : geo.LocationSettings(
            accuracy: geo.LocationAccuracy.bestForNavigation,
            distanceFilter: 1,
          );
    _positionSubscription =
        geo.Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen(
          (position) =>
              unawaited(_navigationSocketService.publishPosition(position)),
          onError: (Object error) {
            debugPrint('[CruiseMode] GPS-Positionsstream Fehler: $error');
          },
        );
  }

  void _stopNavigationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _socketPositionSubscription?.cancel();
    _socketPositionSubscription = null;
    unawaited(_navigationSocketService.close());
    _startIdlePositionStream(); // Idle-Stream wieder starten
  }

  Future<void> _onLocationUpdate(geo.Position position) async {
    if (!mounted || _disposed) return;

    // Web: GPS-Smoother anwenden — berechnet Heading aus Positionsverlauf
    // (Browser liefert kein zuverlässiges heading, oft 0 oder NaN)
    geo.Position effectivePosition;
    if (kIsWeb) {
      final smoothed = _webSmoother.update(position);
      // Smoother gibt null zurück wenn Bewegung < 2m → trotzdem intern tracken
      effectivePosition = smoothed ?? _webSmoother.current ?? position;
      _userLocation = effectivePosition;
      _userHeading = _webSmoother.heading;
    } else {
      effectivePosition = position;
      _userLocation = position;
      if (position.heading.isFinite &&
          position.heading >= 0 &&
          position.heading <= 360) {
        _userHeading = position.heading;
      }
    }

    // ── Kamera-Bewegung ──────────────────────────────────────────────────────
    // Web: Animierte Interpolation (60fps smooth), Native: direkter Move
    if (_isCameraLocked && _mapReady) {
      if (kIsWeb) {
        final predicted = _webSmoother.predict(
          DateTime.now().add(const Duration(milliseconds: 180)),
        );
        _animateCameraTo(predicted.lat, predicted.lng, predicted.heading);
      } else {
        _animateCameraTo(
          effectivePosition.latitude,
          effectivePosition.longitude,
          _userHeading,
        );
      }
    }

    // ── UI-Rebuild Throttling ───────────────────────────────────────────────
    // Marker-Position + Route-Start immer intern aktualisieren.
    // setState nur wenn genug Zeit vergangen (Web: 300ms, Native: sofort).
    _userPosition = LatLng(
      effectivePosition.latitude,
      effectivePosition.longitude,
    );
    if (_routeLatLngs.isNotEmpty) {
      _routeLatLngs[0] = LatLng(
        effectivePosition.latitude,
        effectivePosition.longitude,
      );
    }

    final now = DateTime.now();
    final skipRebuild =
        kIsWeb &&
        _lastWebRebuildTime != null &&
        now.difference(_lastWebRebuildTime!).inMilliseconds < 150;
    if (!skipRebuild) {
      _lastWebRebuildTime = now;
      _safeSetState(() {});
    }

    if (!_isRouteConfirmed || _fullRouteCoordinates.length < 2) return;

    // Für Route-Matching die rohe Position verwenden (genauer für Snap-to-Route)
    final match = findNearestInWindow(
      position: position,
      coordinates: _fullRouteCoordinates,
      currentIndex: _currentRouteIndex,
      windowSize: 40,
    );

    final offRouteCorridor = _isRoundTrip
        ? _offRouteThresholdMeters
        : _currentPointToPointCorridorMeters();
    final isOutsideCorridor = match.distanceMeters > offRouteCorridor;
    final approachingDestination =
        !_isRoundTrip &&
        _activeDestinationCoordinate != null &&
        _isApproachingCurrentDestination(position);

    if (isOutsideCorridor) {
      if (approachingDestination) {
        _offRouteCount = 0;
        debugPrint(
          '[CruiseMode] Alternative Route akzeptiert: ${match.distanceMeters.toStringAsFixed(0)}m neben Original, Zielentfernung sinkt weiter.',
        );
      } else {
        _offRouteCount++;
        if (_offRouteCount >= _offRouteCountThreshold && !_isRerouting) {
          final now = DateTime.now();
          final cooldownOk =
              _lastRerouteTime == null ||
              now.difference(_lastRerouteTime!).inSeconds >= 30;
          if (cooldownOk) {
            _lastRerouteTime = now;
            _offRouteCount = 0;
            _rerouteToOriginalRoute(position);
            return;
          }
        }
      }
    } else {
      _offRouteCount = 0;
    }

    var needsRebuild = false;

    if (match.index > _currentRouteIndex && match.distanceMeters <= 45.0) {
      // Gefahrene Distanz tracken
      for (var i = _currentRouteIndex; i < match.index; i++) {
        final c1 = _fullRouteCoordinates[i];
        final c2 = _fullRouteCoordinates[i + 1];
        final segmentMeters = geo.Geolocator.distanceBetween(
          c1[1],
          c1[0],
          c2[1],
          c2[0],
        );
        _totalDistanceDriven += segmentMeters;
        _distanceSinceLastRedraw += segmentMeters;
      }
      _currentRouteIndex = match.index;
      needsRebuild = true;

      // Verbleibende Distanz und Zeit live berechnen
      _updateRemainingDistanceAndDuration();

      // Route in Schritten neu zeichnen (Sliding Window, 3km voraus)
      // Web: größere Schwellen um teure CanvasKit-Repaints zu reduzieren
      const indexThreshold = kIsWeb
          ? _routeRedrawIndexThreshold * 2
          : _routeRedrawIndexThreshold;
      const distThreshold = kIsWeb
          ? _routeRedrawDistanceMeters * 2
          : _routeRedrawDistanceMeters;
      final redrawByIndex =
          _currentRouteIndex - _lastDrawnRouteIndex >= indexThreshold;
      final redrawByDistance = _distanceSinceLastRedraw >= distThreshold;
      if (redrawByIndex || redrawByDistance) {
        _lastDrawnRouteIndex = _currentRouteIndex;
        _distanceSinceLastRedraw = 0.0;
        final windowEnd = _findLookAheadIndex(_currentRouteIndex, 3000);
        final routeSlice = _fullRouteCoordinates
            .sublist(_currentRouteIndex, windowEnd)
            .map((c) => [c[0], c[1]])
            .toList();
        if (routeSlice.isNotEmpty) {
          routeSlice[0] = [position.longitude, position.latitude];
        }
        _remainingRouteCoordinates = routeSlice;
        final clipped = {
          'type': 'LineString',
          'coordinates': _remainingRouteCoordinates,
        };
        _routeGeoJson = json.encode(clipped);
        await _drawRoute(clipped, animateCamera: false);
      }
    }

    // Prüfe ob Route zu Ende ist
    final lastIndex = _fullRouteCoordinates.length - 1;
    if (_currentRouteIndex >= lastIndex - 1) {
      final end = _fullRouteCoordinates.last;
      final distToEnd = geo.Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        end[1],
        end[0],
      );
      if (distToEnd <= 50.0) {
        _stopNavigationTracking();
        _stopSimulation(restartLiveTracking: false);
        _onRouteCompleted();
        return;
      }
    }

    final prevManeuver = _activeManeuverIndex;
    _updateActiveManeuver();
    if (_activeManeuverIndex != prevManeuver) {
      needsRebuild = true;
      // Haptic Feedback wenn neues Manöver aktiv wird
      HapticFeedback.mediumImpact();
    }
    // Leichtes Feedback kurz vor einem Manöver (< 150m)
    final distToManeuver = _calculateDistanceToManeuver();
    if (distToManeuver != null &&
        distToManeuver < 150 &&
        distToManeuver > 100) {
      HapticFeedback.lightImpact();
    }

    if (needsRebuild) _safeSetState(() {});
  }

  void _updateRemainingDistanceAndDuration() {
    if (_fullRouteCoordinates.length < 2 ||
        _currentRouteIndex >= _fullRouteCoordinates.length - 1) {
      _remainingDistance = 0;
      _remainingDuration = 0;
      return;
    }
    // Verbleibende Distanz ab aktuellem Index bis Ende summieren
    double dist = 0.0;
    for (
      var i = _currentRouteIndex;
      i < _fullRouteCoordinates.length - 1;
      i++
    ) {
      final c1 = _fullRouteCoordinates[i];
      final c2 = _fullRouteCoordinates[i + 1];
      dist += geo.Geolocator.distanceBetween(c1[1], c1[0], c2[1], c2[0]);
    }
    _remainingDistance = dist;

    // Zeitberechnung basiert auf DISTANZ-Anteil (nicht Index-Anteil),
    // weil Mapbox-Koordinaten ungleichmäßig verteilt sind (mehr Punkte in Kurven).
    final origDur = _originalRouteDuration ?? _routeDuration;
    final origDist = _originalRouteDistance;
    if (origDur != null && origDur > 0 && origDist != null && origDist > 0) {
      // Verbleibende Distanz / Gesamtdistanz = korrekter Zeitanteil
      final remainingFraction = (dist / origDist).clamp(0.0, 1.0);
      final newDuration = origDur * remainingFraction;

      // Sanft interpolieren damit es nicht springt
      if (_remainingDuration != null) {
        _remainingDuration =
            _remainingDuration! + (newDuration - _remainingDuration!) * 0.3;
      } else {
        _remainingDuration = newDuration;
      }
    } else {
      _remainingDuration = dist / 13.89; // Fallback 50 km/h
    }
  }

  /// Berechnet eine neue Route von der aktuellen Position zurück zur Originalroute.
  /// Nutzt einen Punkt weiter voraus auf der Route als Ziel und berechnet via
  /// Mapbox eine befahrbare Straßenroute (keine Luftlinie).
  Future<void> _rerouteToOriginalRoute(geo.Position position) async {
    if (_isRerouting) return;
    _isRerouting = true;

    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Route wird neu berechnet...'),
            backgroundColor: Color(0xFFFF9500),
            duration: Duration(seconds: 2),
          ),
        );
    }

    try {
      const validator = RouteQualityValidator();
      // Suche den nächsten Punkt auf der GESAMTEN verbleibenden Route (großes Fenster)
      final globalMatch = findNearestInWindow(
        position: position,
        coordinates: _fullRouteCoordinates,
        currentIndex: _currentRouteIndex,
        windowSize: _fullRouteCoordinates.length - _currentRouteIndex,
        maxJumpMeters: double.infinity,
      );

      var heading = position.heading;
      if (!heading.isFinite || heading < 0 || heading > 360) {
        heading = routeHeadingAt(_fullRouteCoordinates, _currentRouteIndex);
      }

      final smartPlan = _smartRerouteEngine.createPlan(
        currentPosition: position,
        coordinates: _fullRouteCoordinates,
        maneuvers: _maneuvers,
        nearestIndex: globalMatch.index,
        currentHeadingDegrees: heading,
        speedLimits: _activeSpeedLimits,
      );

      debugPrint(
        '[CruiseMode] Smart reroute plan: ${smartPlan.debugLabel}, strategy=${smartPlan.strategy.name}, rejoin=${smartPlan.rejoinIndex}',
      );

      final destination = _activeDestinationCoordinate;
      if (!_isRoundTrip && destination != null) {
        final destinationResult = await _routeService.generatePointToPoint(
          startPosition: position,
          destinationLat: destination[1],
          destinationLng: destination[0],
          mode: _activePointToPointScenic
              ? _activePointToPointMode
              : 'Standard',
          scenic: _activePointToPointScenic,
          routeVariant: _activeDetourVariant,
          avoidHighways: _activeAvoidHighways,
        );

        if (destinationResult.coordinates.length >= 2) {
          final destinationQuality = validator.validateQuality(
            coordinates: destinationResult.coordinates,
            isRoundTrip: false,
            actualDistanceKm: destinationResult.distanceKm ?? 0,
          );
          final destinationTooFewPoints =
              destinationResult.coordinates.length < 30 &&
              (destinationResult.distanceKm ?? 0) >= 10;
          if (!destinationQuality.passed || destinationTooFewPoints) {
            debugPrint(
              '[CruiseMode] Direkter Ziel-Reroute verworfen: Qualität unzureichend.',
            );
          } else {
            final distanceMeters =
                destinationResult.distanceMeters ??
                _calculatePolylineDistanceMeters(destinationResult.coordinates);
            final durationSeconds =
                destinationResult.durationSeconds ??
                _estimateDurationSecondsForDistance(distanceMeters);

            await _commitRerouteResult(
              result: _buildRouteResultFromCoordinates(
                coordinates: destinationResult.coordinates,
                maneuvers: destinationResult.maneuvers,
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                speedLimits: destinationResult.speedLimits,
              ),
              position: position,
            );

            if (mounted) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('Neue Strecke zum Ziel wurde übernommen.'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
            }
            return;
          }
        }
      }

      final maxRejoinIndex = math.max(0, _fullRouteCoordinates.length - 2);
      final fallbackRejoinIndex = selectForwardRejoinIndex(
        coordinates: _fullRouteCoordinates,
        nearestIndex: globalMatch.index,
        currentHeadingDegrees: heading,
      ).clamp(0, maxRejoinIndex).toInt();

      RouteResult? rerouteResult;
      SmartReroutePlan? acceptedPlan;
      var rejoinIndex = smartPlan.rejoinIndex.clamp(0, maxRejoinIndex).toInt();

      for (var attempt = 0; attempt < 4; attempt++) {
        final useFallbackPlan = attempt > 0;
        rejoinIndex = useFallbackPlan
            ? math
                  .min(
                    fallbackRejoinIndex + ((attempt - 1) * 60),
                    maxRejoinIndex,
                  )
                  .toInt()
            : rejoinIndex;
        final activePlan = useFallbackPlan
            ? SmartReroutePlan(
                anchorCoordinate: _fullRouteCoordinates[rejoinIndex],
                rejoinIndex: rejoinIndex,
                strategy: SmartRerouteStrategy.forwardRejoin,
                debugLabel: 'fallback_forward_rejoin_$attempt',
              )
            : smartPlan;
        final rejoinPoint = activePlan.anchorCoordinate;
        final distToRejoin = geo.Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          rejoinPoint[1],
          rejoinPoint[0],
        );
        if (distToRejoin < 160 && rejoinIndex < maxRejoinIndex) {
          rejoinIndex = math.min(rejoinIndex + 60, maxRejoinIndex).toInt();
          continue;
        }

        final mergeWithOriginal =
            activePlan.mergeWithOriginal && rejoinIndex < maxRejoinIndex;
        final scenicReroute = !mergeWithOriginal && _activePointToPointScenic;

        final candidate = await _routeService.generatePointToPoint(
          startPosition: position,
          destinationLat: rejoinPoint[1],
          destinationLng: rejoinPoint[0],
          mode: _rerouteMode(mergeWithOriginal: mergeWithOriginal),
          scenic: scenicReroute,
          routeVariant: _rerouteVariant(mergeWithOriginal: mergeWithOriginal),
          avoidHighways: _activeAvoidHighways,
        );

        if (candidate.coordinates.length < 2) {
          rejoinIndex = math.min(rejoinIndex + 80, maxRejoinIndex).toInt();
          continue;
        }

        final candidateQuality = validator.validateQuality(
          coordinates: candidate.coordinates,
          isRoundTrip: false,
          actualDistanceKm: candidate.distanceKm ?? 0,
        );
        final candidateTooFewPoints =
            candidate.coordinates.length < 30 &&
            (candidate.distanceKm ?? 0) >= 10;
        if (!candidateQuality.passed || candidateTooFewPoints) {
          rejoinIndex = math.min(rejoinIndex + 80, maxRejoinIndex).toInt();
          debugPrint(
            '[CruiseMode] Reroute-Attempt ${attempt + 1}: Kandidat verworfen (Qualität)',
          );
          continue;
        }

        if (mergeWithOriginal) {
          final producesUTurn = isUTurnJoin(
            rerouteCoordinates: candidate.coordinates,
            originalCoordinates: _fullRouteCoordinates,
            rejoinIndex: rejoinIndex,
          );
          if (producesUTurn && rejoinIndex < maxRejoinIndex) {
            rejoinIndex = math.min(rejoinIndex + 80, maxRejoinIndex).toInt();
            debugPrint(
              '[CruiseMode] Reroute-Attempt ${attempt + 1}: Join-U-Turn erkannt, rejoinIndex=$rejoinIndex',
            );
            continue;
          }
        }

        rerouteResult = candidate;
        acceptedPlan = activePlan;
        break;
      }

      if (rerouteResult == null ||
          acceptedPlan == null ||
          !mounted ||
          _disposed) {
        return;
      }

      final resolvedRerouteResult = rerouteResult;
      final resolvedPlan = acceptedPlan;
      final mergeWithOriginal =
          resolvedPlan.mergeWithOriginal &&
          resolvedPlan.rejoinIndex < _fullRouteCoordinates.length - 1;
      late final RouteResult finalResult;

      if (mergeWithOriginal) {
        final remainingOriginal = _fullRouteCoordinates.sublist(
          resolvedPlan.rejoinIndex,
        );
        var skippedOriginalCoordinates = 0;
        if (resolvedRerouteResult.coordinates.isNotEmpty &&
            remainingOriginal.isNotEmpty) {
          final rerouteEnd = resolvedRerouteResult.coordinates.last;
          final originalStart = remainingOriginal.first;
          final joinDistance = geo.Geolocator.distanceBetween(
            rerouteEnd[1],
            rerouteEnd[0],
            originalStart[1],
            originalStart[0],
          );
          if (joinDistance <= 20) {
            skippedOriginalCoordinates = 1;
          }
        }

        final originalTail = skippedOriginalCoordinates == 1
            ? remainingOriginal.skip(1).toList()
            : remainingOriginal;
        final mergedCoordinates = [
          ...rerouteResult.coordinates,
          ...originalTail,
        ];

        final remainingManeuvers = _maneuvers
            .where(
              (m) =>
                  m.routeIndex >=
                  resolvedPlan.rejoinIndex + skippedOriginalCoordinates,
            )
            .map(
              (m) => RouteManeuver(
                latitude: m.latitude,
                longitude: m.longitude,
                routeIndex:
                    m.routeIndex -
                    resolvedPlan.rejoinIndex -
                    skippedOriginalCoordinates +
                    resolvedRerouteResult.coordinates.length,
                icon: m.icon,
                announcement: m.announcement,
                instruction: m.instruction,
                maneuverType: m.maneuverType,
                roundaboutExitNumber: m.roundaboutExitNumber,
              ),
            )
            .toList();

        final mergedSpeedLimits = _mergeSpeedLimits(
          resolvedRerouteResult.speedLimits,
          resolvedPlan.rejoinIndex,
          resolvedRerouteResult.coordinates.length,
          skippedOriginalCoordinates: skippedOriginalCoordinates,
        );
        final rerouteDistanceMeters =
            resolvedRerouteResult.distanceMeters ??
            _calculatePolylineDistanceMeters(resolvedRerouteResult.coordinates);
        final remainingDistanceMeters = _calculatePolylineDistanceMeters(
          originalTail,
        );
        final rerouteDurationSeconds =
            resolvedRerouteResult.durationSeconds ??
            _estimateDurationSecondsForDistance(rerouteDistanceMeters);
        final remainingDurationSeconds = _estimateDurationSecondsForDistance(
          remainingDistanceMeters,
        );

        finalResult = _buildRouteResultFromCoordinates(
          coordinates: mergedCoordinates,
          maneuvers: [
            ...resolvedRerouteResult.maneuvers,
            ...remainingManeuvers,
          ],
          distanceMeters: rerouteDistanceMeters + remainingDistanceMeters,
          durationSeconds: rerouteDurationSeconds + remainingDurationSeconds,
          speedLimits: mergedSpeedLimits,
        );
      } else {
        final distanceMeters =
            resolvedRerouteResult.distanceMeters ??
            _calculatePolylineDistanceMeters(resolvedRerouteResult.coordinates);
        finalResult = _buildRouteResultFromCoordinates(
          coordinates: resolvedRerouteResult.coordinates,
          maneuvers: resolvedRerouteResult.maneuvers,
          distanceMeters: distanceMeters,
          durationSeconds:
              resolvedRerouteResult.durationSeconds ??
              _estimateDurationSecondsForDistance(distanceMeters),
          speedLimits: resolvedRerouteResult.speedLimits,
        );
      }

      await _commitRerouteResult(result: finalResult, position: position);

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Route neu berechnet!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
      }
    } catch (e, stack) {
      debugPrint('Rerouting fehlgeschlagen: $e');
      debugPrintStack(
        label: '[CruiseMode] Rerouting stacktrace',
        stackTrace: stack,
      );
      final userMessage = e is RouteServiceException
          ? e.userMessage
          : _sanitizeErrorMessage(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Rerouting fehlgeschlagen: $userMessage'),
              backgroundColor: Colors.red,
            ),
          );
      }
    } finally {
      _isRerouting = false;
    }
  }

  /// Berechnet die Distanz entlang der Route vom aktuellen Index zum nächsten Manöver.
  double? _calculateDistanceToManeuver() {
    if (_maneuvers.isEmpty || _fullRouteCoordinates.length < 2) return null;
    final maneuver =
        _maneuvers[_activeManeuverIndex.clamp(0, _maneuvers.length - 1)];
    final targetIndex = maneuver.routeIndex.clamp(
      0,
      _fullRouteCoordinates.length - 1,
    );
    if (targetIndex <= _currentRouteIndex) return 0;

    double dist = 0.0;
    for (var i = _currentRouteIndex; i < targetIndex; i++) {
      final c1 = _fullRouteCoordinates[i];
      final c2 = _fullRouteCoordinates[i + 1];
      dist += geo.Geolocator.distanceBetween(c1[1], c1[0], c2[1], c2[0]);
    }
    return dist;
  }

  void _updateActiveManeuver() {
    if (_maneuvers.isEmpty) return;
    for (var i = _activeManeuverIndex; i < _maneuvers.length; i++) {
      if (_maneuvers[i].routeIndex >= _currentRouteIndex) {
        _activeManeuverIndex = i;
        return;
      }
    }
    _activeManeuverIndex = _maneuvers.length - 1;
  }

  // ═══════════════════════ CAMERA ═══════════════════════════════════════════

  void _toggleCameraLock() {
    _safeSetState(() => _isCameraLocked = !_isCameraLocked);
    if (_isCameraLocked) {
      // Sofort zur aktuellen Position fliegen (flutter_map: direkt move())
      _recenterMap();
    }
    // Wenn deaktiviert: freie Kartenbewegung — nichts extra nötig
  }

  Future<void> _recenterMap() async {
    final position = _userLocation;
    if (position == null || !_mapReady) return;
    try {
      _mapController.move(LatLng(position.latitude, position.longitude), 16.0);
    } catch (e) {
      debugPrint('[CruiseMode] Recenter fehlgeschlagen: $e');
    }
  }

  bool _isOverviewActive = false;

  Future<void> _showRouteOverview() async {
    if (!_mapReady || _fullRouteCoordinates.length < 2) return;
    if (_isOverviewActive) return;
    _isOverviewActive = true;

    try {
      // Gesamte Route als Bounds berechnen
      final routeLatLngs = _fullRouteCoordinates
          .map((c) => LatLng(c[1], c[0]))
          .toList();
      final bounds = LatLngBounds.fromPoints(routeLatLngs);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(40, 80, 40, 160),
        ),
      );

      // 4 Sekunden Übersicht anzeigen, dann zurück
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted || _disposed) return;

      // Zurück zur Navigationsposition
      if (_isCameraLocked) {
        await _recenterMap();
      }
    } catch (e) {
      debugPrint('[CruiseMode] Route-Übersicht fehlgeschlagen: $e');
    }

    _isOverviewActive = false;
  }

  Future<void> _activateNavigationCamera() async {
    if (!_mapReady) return;
    geo.Position position;
    try {
      position = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint(
        '[CruiseMode] getCurrentPosition fehlgeschlagen, verwende Fallback: $e',
      );
      position = await _getStartCoordinates();
    }
    _userLocation = position;
    _safeSetState(() {
      _userPosition = LatLng(position.latitude, position.longitude);
      _isCameraLocked = true;
    });
    try {
      // Kamera zur User-Position zoomen
      _mapController.move(LatLng(position.latitude, position.longitude), 16.0);
    } catch (e) {
      debugPrint('[CruiseMode] Navigations-Kamera setzen fehlgeschlagen: $e');
    }
  }

  // ═══════════════════════ SIMULATION ═══════════════════════════════════════

  Future<void> _toggleSimulation() async {
    if (_isSimulationRunning) {
      _stopSimulation();
      _safeSetState(() {});
      return;
    }
    await _startSimulation();
  }

  Future<void> _startSimulation() async {
    if (!_isSimulationEnabled) return;
    if (_fullRouteCoordinates.length < 2) return;
    _stopNavigationTracking();
    _simulationIndex = 0;
    _currentRouteIndex = 0;
    _lastDrawnRouteIndex = 0;
    _distanceSinceLastRedraw = 0.0;
    _totalDistanceDriven = 0;
    _navigationStartTime = DateTime.now();
    _announcedManeuverIndices.clear();
    _activeManeuverIndex = 0;
    // Speed-History entfernt
    _isSimulationRunning = true;
    _simulationSpeedKmh = 60;

    // Initiale Route zeichnen
    final windowEnd = _findLookAheadIndex(0, 3000);
    _remainingRouteCoordinates = _fullRouteCoordinates.sublist(0, windowEnd);
    final fullGeometry = {
      'type': 'LineString',
      'coordinates': _remainingRouteCoordinates,
    };
    _routeGeoJson = json.encode(fullGeometry);
    await _drawRoute(fullGeometry, animateCamera: false);

    // Simulations-Puck am Startpunkt anzeigen
    final startCoord = _fullRouteCoordinates.first;
    await _updateSimulationPuck(startCoord[0], startCoord[1]);

    // Kamera aktivieren
    _isCameraLocked = true;
    await _activateNavigationCamera();

    // Initiale Distanz/Zeit setzen
    _updateRemainingDistanceAndDuration();
    _safeSetState(() {});

    _simulationTimer?.cancel();
    _scheduleNextSimulationStep();
  }

  void _stopSimulation({bool restartLiveTracking = true}) {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _isSimulationStepRunning = false;
    _isSimulationRunning = false;
    _removeSimulationPuck();
    if (restartLiveTracking && _isRouteConfirmed) _startNavigationTracking();
  }

  void _scheduleNextSimulationStep() {
    _simulationTimer?.cancel();
    if (!_isSimulationRunning || _fullRouteCoordinates.length < 2) return;
    final lastIndex = _fullRouteCoordinates.length - 1;
    if (_simulationIndex >= lastIndex) return;

    // Fester 50ms Intervall (20 FPS) — smooth für alle Geschwindigkeiten
    // Die Anzahl übersprungener Punkte wird in _runSimulationStep berechnet
    _simulationTimer = Timer(
      const Duration(milliseconds: 50),
      _runSimulationStep,
    );
  }

  Future<void> _runSimulationStep() async {
    if (!_isSimulationRunning ||
        _isSimulationStepRunning ||
        _fullRouteCoordinates.length < 2 ||
        !mounted ||
        _disposed) {
      return;
    }
    _isSimulationStepRunning = true;
    try {
      final lastIndex = _fullRouteCoordinates.length - 1;
      if (_simulationIndex >= lastIndex) {
        _stopSimulation(restartLiveTracking: false);
        _onRouteCompleted();
        return;
      }

      // Berechne wie viele Punkte bei aktueller Geschwindigkeit in 50ms übersprungen werden
      final speedMs = _simulationSpeedKmh / 3.6;
      final targetDistPerStep = speedMs * 0.05; // Meter in 50ms
      double accumulated = 0.0;
      int newIndex = _simulationIndex;
      while (newIndex < lastIndex && accumulated < targetDistPerStep) {
        final c1 = _fullRouteCoordinates[newIndex];
        final c2 = _fullRouteCoordinates[newIndex + 1];
        accumulated += geo.Geolocator.distanceBetween(
          c1[1],
          c1[0],
          c2[1],
          c2[0],
        );
        newIndex++;
      }
      // Mindestens 1 Punkt vorwärts
      _simulationIndex = math
          .max(newIndex, _simulationIndex + 1)
          .clamp(0, lastIndex);

      final current = _fullRouteCoordinates[_simulationIndex];
      final next =
          _fullRouteCoordinates[math.min(_simulationIndex + 1, lastIndex)];

      // Simulations-Puck auf der Karte bewegen
      try {
        await _updateSimulationPuck(current[0], current[1]);
      } catch (e) {
        debugPrint('[Sim] Puck-Update: $e');
      }

      // Location Update
      try {
        await _onLocationUpdate(
          _buildSimulatedPosition(current, next, speedMs),
        );
      } catch (e) {
        debugPrint('[Sim] Location-Update: $e');
      }

      if (_simulationIndex >= lastIndex) {
        _stopSimulation(restartLiveTracking: false);
        _onRouteCompleted();
        return;
      }
    } catch (e) {
      debugPrint('[Sim] Simulationsschritt fehlgeschlagen: $e');
    } finally {
      _isSimulationStepRunning = false;
    }
    if (_isSimulationRunning) _scheduleNextSimulationStep();
  }

  Future<void> _updateSimulationPuck(double lng, double lat) async {
    // Simulation deaktiviert — Puck nicht mehr anzeigen
  }

  Future<void> _removeSimulationPuck() async {
    // Simulation deaktiviert
  }

  geo.Position _buildSimulatedPosition(
    List<double> current,
    List<double> next,
    double speedMs,
  ) {
    final heading = calculateBearing(current[1], current[0], next[1], next[0]);
    return geo.Position(
      longitude: current[0],
      latitude: current[1],
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      heading: heading,
      speed: speedMs,
      speedAccuracy: 1,
      altitudeAccuracy: 0,
      headingAccuracy: 5,
    );
  }

  // ═══════════════════════ ROUTE COMPLETION ═════════════════════════════════

  void _onRouteCompleted() {
    if (!mounted || _disposed) return;
    final drivenKm = _totalDistanceDriven > 0
        ? _totalDistanceDriven / 1000
        : (_routeDistance != null ? _routeDistance! / 1000 : null);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CruiseCompletionDialog(
        distanceKm: drivenKm,
        onSave: (rating) async {
          Navigator.pop(ctx);
          await _saveRouteAndSyncXp(rating: rating);
          _resetAfterCompletion();
        },
        onDiscard: () async {
          Navigator.pop(ctx);
          _resetAfterCompletion();
        },
      ),
    );
  }

  void _onRouteEarlyStopped() {
    if (!mounted || _disposed) return;
    final drivenKm = _totalDistanceDriven / 1000;
    final totalKm = _originalRouteDistance != null
        ? _originalRouteDistance! / 1000
        : 0.0;
    final progressFraction = totalKm > 0
        ? (drivenKm / totalKm).clamp(0.0, 1.0)
        : 0.0;

    // Fast fertig → als volle Completion behandeln
    if (progressFraction >= _minProgressForFullCredit) {
      _onRouteCompleted();
      return;
    }

    final belowMinimum = progressFraction < _minProgressForCredit;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CruiseCompletionDialog(
        distanceKm: drivenKm,
        totalRouteKm: totalKm > 0 ? totalKm : null,
        isEarlyStop: true,
        belowMinimum: belowMinimum,
        onSave: (rating) async {
          Navigator.pop(ctx);
          await _saveRouteAndSyncXp(rating: rating, skipXpSync: belowMinimum);
          _resetAfterCompletion();
        },
        onDiscard: () async {
          Navigator.pop(ctx);
          // Discard mit anteiliger Gutschrift wenn über Minimum
          if (!belowMinimum && _totalDistanceDriven > 0) {
            await _saveRouteAndSyncXp(skipXpSync: false);
          }
          _resetAfterCompletion();
        },
      ),
    );
  }

  /// Speichert die gefahrene Route und synchronisiert XP/Level/Badges.
  /// [skipXpSync] = true → Route wird gespeichert, aber keine XP vergeben (< 10% gefahren).
  Future<void> _saveRouteAndSyncXp({
    int? rating,
    bool skipXpSync = false,
  }) async {
    try {
      debugPrint(
        '[CruiseMode] _saveRouteAndSyncXp: _lastRouteResult=${_lastRouteResult != null}, rating=$rating, skipXp=$skipXpSync',
      );
      if (_lastRouteResult != null) {
        // Route mit tatsächlich gefahrener Distanz speichern
        final drivenDistanceMeters = _totalDistanceDriven > 0
            ? _totalDistanceDriven
            : _routeDistance;

        // Proportionale Dauer berechnen
        final double progressFraction =
            (drivenDistanceMeters != null &&
                _originalRouteDistance != null &&
                _originalRouteDistance! > 0)
            ? (drivenDistanceMeters / _originalRouteDistance!).clamp(0.0, 1.0)
            : 1.0;
        final double? proportionalDuration =
            _lastRouteResult!.durationSeconds != null
            ? _lastRouteResult!.durationSeconds! * progressFraction
            : null;

        // Tatsächlich verstrichene Zeit als Obergrenze (verhindert Gaming)
        final double? elapsedSeconds = _navigationStartTime != null
            ? DateTime.now()
                  .difference(_navigationStartTime!)
                  .inSeconds
                  .toDouble()
            : null;

        // Minimum aus proportionaler und tatsächlicher Zeit verwenden
        final double? adjustedDuration;
        if (proportionalDuration != null && elapsedSeconds != null) {
          adjustedDuration = proportionalDuration < elapsedSeconds
              ? proportionalDuration
              : elapsedSeconds;
        } else {
          adjustedDuration = proportionalDuration ?? elapsedSeconds;
        }

        final adjustedResult = RouteResult(
          geoJson: _lastRouteResult!.geoJson,
          geometry: _lastRouteResult!.geometry,
          coordinates: _lastRouteResult!.coordinates,
          maneuvers: _lastRouteResult!.maneuvers,
          distanceMeters: drivenDistanceMeters,
          durationSeconds: adjustedDuration,
          distanceKm: drivenDistanceMeters != null
              ? drivenDistanceMeters / 1000
              : null,
        );
        debugPrint(
          '[CruiseMode] Saving route: style=$_selectedStyle, roundTrip=$_isRoundTrip, '
          'distKm=${adjustedResult.distanceKm}, durationSec=${adjustedDuration?.round()}, '
          'progress=${(progressFraction * 100).round()}%',
        );
        await SavedRoutesService.saveRoute(
          result: adjustedResult,
          style: _selectedStyle,
          isRoundTrip: _isRoundTrip,
          rating: rating,
          drivenKm: adjustedResult.distanceKm,
          plannedDistanceKm: _originalRouteDistance != null
              ? _originalRouteDistance! / 1000
              : adjustedResult.distanceKm,
        );
        debugPrint('[CruiseMode] Route saved successfully!');
      }
      // XP/Level/Badges synchronisieren (nur wenn über Minimum-Schwelle)
      if (!skipXpSync) {
        final gamResult = await GamificationService.calculateAndSync();
        if (mounted && gamResult.newBadgeIds.isNotEmpty) {
          final badgeNames = gamResult.newBadges.map((b) => b.emoji).join(' ');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Neues Badge: $badgeNames'),
              backgroundColor: const Color(0xFFFFD700),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        debugPrint(
          '[CruiseMode] XP-Sync übersprungen (unter Minimum-Schwelle)',
        );
      }
    } catch (e, stack) {
      debugPrint('Route speichern / XP sync fehlgeschlagen: $e');
      debugPrint('Stack: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Speichern: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _resetAfterCompletion() {
    CruiseModePage.isFullscreen.value = false;
    _safeSetState(() {
      _isRouteConfirmed = false;
      _isCameraLocked = false;
      _totalDistanceDriven = 0.0;
      _navigationStartTime = null;
    });
  }

  // ═══════════════════════ DIALOGS ══════════════════════════════════════════

  void _showError(String message) {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Fehler: $message'), backgroundColor: Colors.red),
    );
  }
}

class _RecentRouteSignature {
  const _RecentRouteSignature({
    required this.fingerprint,
    required this.coordinates,
  });

  final String fingerprint;
  final List<List<double>> coordinates;
}

/// Apple-Maps-Style Navigations-Pfeil: Blauer Tropfen/Pfeil zeigt Fahrtrichtung.
class _NavigationArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Pfeil-Spitze (zeigt nach oben = Fahrtrichtung)
    final arrowPaint = Paint()
      ..color = const Color(0xFF007AFF)
      ..style = PaintingStyle.fill;

    final arrow = ui.Path()
      ..moveTo(cx, cy - 32) // Spitze oben
      ..lineTo(cx - 10, cy - 12) // Links unten
      ..quadraticBezierTo(cx, cy - 16, cx + 10, cy - 12) // Kurve unten
      ..close();

    // Schatten für den Pfeil
    canvas.drawShadow(arrow, const Color(0x60000000), 3.0, false);
    canvas.drawPath(arrow, arrowPaint);

    // Weißer Rand um den Pfeil für bessere Sichtbarkeit
    final borderPaint = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(arrow, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
