import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cruise_connect/core/constants.dart';

import 'package:cruise_connect/data/services/geocoding_service.dart';
import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:cruise_connect/data/services/navigation_progress_socket_service.dart';
import 'package:cruise_connect/data/services/offline_map_service.dart';
import 'package:cruise_connect/data/services/route_service.dart';
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

class _CruiseModePageState extends State<CruiseModePage> {
  // ─────────────────────── Services ──────────────────────────────────────────
  final _geocodingService = const GeocodingService();
  final _routeService = const RouteService();
  final _navigationSocketService = NavigationProgressSocketService();

  // ─────────────────────── Route Setup State ─────────────────────────────────
  bool _isRoundTrip = true;
  String _planningType = 'Zufall';
  String _selectedLength = '50 Km';
  String _selectedLocation = 'Aktueller Standort';
  String _selectedStyle = 'Sport Mode';
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

  // ─────────────────────── Map State (flutter_map) ───────────────────────────
  bool _isLoading = false;
  final MapController _mapController = MapController();
  bool _mapReady = false;
  // Route als LatLng-Liste für PolylineLayer
  List<LatLng> _routeLatLngs = [];
  // Aktuelle User-Position als Marker
  LatLng? _userPosition;
  // Simulation-Puck-Position als Marker
  LatLng? _simulationPuckPosition;

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

  // ─────────────────────── Simulation State ─────────────────────────────────
  Timer? _simulationTimer;
  bool _isSimulationRunning = false;
  bool _isSimulationStepRunning = false;
  int _simulationIndex = 0;
  final bool _isSimulationEnabled = true; // Simulation für Testing
  double _simulationSpeedKmh = 60; // Aktuelle Simulationsgeschwindigkeit

  bool _isCameraLocked =
      false; // Compass-Toggle: true = Kamera folgt dem Standort
  double? _remainingDistance; // Live verbleibende Distanz in Metern
  double? _remainingDuration; // Live verbleibende Zeit in Sekunden
  bool _isRerouting = false; // Verhindert mehrfaches gleichzeitiges Rerouting
  DateTime? _lastRerouteTime; // Cooldown zwischen Reroutes
  int _offRouteCount = 0; // Zählt aufeinanderfolgende Off-Route-Updates
  static const double _offRouteThresholdMeters =
      150.0; // Ab wann Rerouting ausgelöst wird
  static const int _offRouteCountThreshold =
      5; // Mindestanzahl Off-Route-Updates vor Reroute
  static const int _routeRedrawIndexThreshold =
      5; // Häufigere Teil-Redraws für flüssige Linie
  static const double _routeRedrawDistanceMeters = 30.0;
  double _totalDistanceDriven = 0.0; // Gesamte gefahrene Strecke in Metern
  double?
  _originalRouteDistance; // Ursprüngliche Gesamtdistanz (für Zeitberechnung)
  double?
  _originalRouteDuration; // Ursprüngliche Gesamtdauer (für Zeitberechnung)
  int _lastDrawnRouteIndex =
      0; // Letzter Index bei dem die Route neu gezeichnet wurde
  double _distanceSinceLastRedraw = 0.0;

  bool _disposed = false;

  // ──────────────────────────────────────────────────────────────────────────

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_disposed) setState(fn);
  }

  @override
  void initState() {
    super.initState();
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
    CruiseModePage.isFullscreen.value = false;
    CruiseModePage.pendingRoute.removeListener(_onPendingRoute);
    _stopSimulation(restartLiveTracking: false);
    _positionSubscription?.cancel();
    _socketPositionSubscription?.cancel();
    unawaited(_navigationSocketService.dispose());
    _destinationController.dispose();
    super.dispose();
  }

  // ═══════════════════════ BUILD ════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: Stack(
        children: [
          // Map IMMER an gleicher Stelle im Widget-Tree (verhindert Neu-Erstellung)
          Positioned.fill(child: _buildMapWidget()),

          // Config-Overlay ODER Navigation-Overlay
          if (!_isRouteConfirmed) _buildConfigOverlay(),
          if (_isRouteConfirmed) _buildNavigationOverlay(),
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
                        onRoundTripChanged: (v) =>
                            setState(() => _isRoundTrip = v),
                        onPlanningTypeChanged: (v) =>
                            setState(() => _planningType = v),
                        onLengthChanged: (v) =>
                            setState(() => _selectedLength = v),
                        onLocationChanged: (v) =>
                            setState(() => _selectedLocation = v),
                        onStyleChanged: (v) =>
                            setState(() => _selectedStyle = v),
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
        TileLayer(
          urlTemplate:
              'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/256/{z}/{x}/{y}?access_token={accessToken}',
          additionalOptions: {'accessToken': AppConstants.mapboxPublicToken},
          userAgentPackageName: 'com.cruise_connect.app',
          retinaMode: true,
        ),
        // ── Route (Glow + Hauptlinie + Überlappungen) ────────────────────────
        if (_routeLatLngs.length >= 2)
          PolylineLayer(
            polylines: [
              // Glow-Effekt (breiter, halbtransparent)
              Polyline(
                points: _routeLatLngs,
                color: const Color(0x4DFF5722),
                strokeWidth: 12,
              ),
              // Haupt-Routenlinie
              Polyline(
                points: _routeLatLngs,
                color: const Color(0xFFFF5722),
                strokeWidth: 5,
              ),
            ],
          ),
        // ── Standort-Marker (immer sichtbar wenn Position bekannt) ──────────
        if (_userLocation != null && !_isRouteConfirmed)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(
                  _userLocation!.latitude,
                  _userLocation!.longitude,
                ),
                width: 28,
                height: 28,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        // ── User-Position Marker (Live-Navigation) ───────────────────────────
        if (_userPosition != null && _isRouteConfirmed)
          MarkerLayer(
            markers: [
              Marker(
                point: _userPosition!,
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.navigation,
                  color: Color(0xFF007AFF),
                  size: 36,
                ),
              ),
            ],
          ),
        // ── Simulations-Puck (blauer Kreis mit weißem Ring) ──────────────────
        if (_simulationPuckPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _simulationPuckPosition!,
                width: 28,
                height: 28,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Color(0xFF007AFF),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
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
        _setCameraToPosition(freshPosition);
        _safeSetState(() {}); // Marker-Refresh
      } catch (e) {
        debugPrint('[CruiseMode] Frische GPS-Position nicht verfügbar: $e');
      }
    } catch (e) {
      debugPrint('Konnte Karten-Position nicht setzen: $e');
    }
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

      Map<String, double>? targetLocation;
      if (!_isRoundTrip && _destinationController.text.isNotEmpty) {
        targetLocation = await _geocodingService.getCoordinatesFromAddress(
          _destinationController.text,
        );
        if (targetLocation == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Konnte Zieladresse nicht finden.')),
          );
          setState(() => _isLoading = false);
          return;
        }
      }

      // Eine Route generieren — kein Warmup/Skip mehr (spart Mapbox Tokens)
      RouteResult result;
      if (!_isRoundTrip) {
        double? destLat, destLng;
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
        result = await _routeService.generatePointToPoint(
          startPosition: startPosition,
          destinationLat: destLat,
          destinationLng: destLng,
          mode: _selectedStyle,
          scenic: _selectedStyle != 'Standard',
        );
      } else {
        result = await _routeService.generateRoundTrip(
          startPosition: startPosition,
          targetDistanceKm: distance,
          mode: _selectedStyle,
          planningType: _planningType,
          targetLocation: targetLocation,
        );
      }

      // Qualitätsprüfung: Route muss echte Straßengeometrie haben UND
      // innerhalb des Distanzbandes liegen (±30% als Client-Toleranz)
      final actualKm = result.distanceKm ?? 0;
      final tooFewPoints = result.coordinates.length < 50 && distance >= 20;
      final distanceTooFar =
          actualKm > distance * 1.5 || actualKm < distance * 0.3;

      if ((tooFewPoints || distanceTooFar) && _isRoundTrip) {
        debugPrint(
          '[CruiseMode] Route-Qualität schlecht: ${result.coordinates.length} Punkte, ${actualKm.toStringAsFixed(1)} km (Ziel: $distance km) — bis zu 2 Retries',
        );
        for (var retry = 0; retry < 2; retry++) {
          result = await _routeService.generateRoundTrip(
            startPosition: startPosition,
            targetDistanceKm: distance,
            mode: _selectedStyle,
            planningType: _planningType,
            targetLocation: targetLocation,
          );
          final retryKm = result.distanceKm ?? 0;
          if (result.coordinates.length >= 50 &&
              retryKm <= distance * 1.5 &&
              retryKm >= distance * 0.3) {
            debugPrint(
              '[CruiseMode] Retry ${retry + 1} erfolgreich: ${result.coordinates.length} Punkte, ${retryKm.toStringAsFixed(1)} km',
            );
            break;
          }
          debugPrint(
            '[CruiseMode] Retry ${retry + 1} auch schlecht: ${result.coordinates.length} Punkte, ${retryKm.toStringAsFixed(1)} km',
          );
        }
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
    } catch (e) {
      _showError(e.toString());
    } finally {
      _safeSetState(() => _isLoading = false);
    }
  }

  void _applyRouteResult(RouteResult result) {
    _lastRouteResult = result;
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

    setState(() {
      _routeGeoJson = json.encode(geometry);
      _routeDistance = route.distanceKm * 1000; // km → m
      _routeDuration = route.durationSeconds;
      _isRouteConfirmed = false;
      _fullRouteCoordinates = coordinates;
      _remainingRouteCoordinates = coordinates;
      _maneuvers = const [];
      _activeManeuverIndex = 0;
      _currentRouteIndex = 0;
      _lastDrawnRouteIndex = 0;
      _distanceSinceLastRedraw = 0.0;
      _announcedManeuverIndices.clear();
      _isRoundTrip = route.isRoundTrip;
      _selectedStyle = route.style;
    });

    await _drawRoute(geometry);

    // Automatisch bestätigen und Navigation starten
    await _confirmRoute();
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
    _positionSubscription?.cancel();
    _socketPositionSubscription?.cancel();

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

    // Web unterstützt kein bestForNavigation → fallback auf best
    const locationSettings = kIsWeb
        ? geo.LocationSettings(
            accuracy: geo.LocationAccuracy.best,
            distanceFilter: 3,
          )
        : geo.LocationSettings(
            accuracy: geo.LocationAccuracy.bestForNavigation,
            distanceFilter: 3,
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
  }

  Future<void> _onLocationUpdate(geo.Position position) async {
    if (!mounted || _disposed) return;
    _userLocation = position;

    // User-Position als Marker rendern (MarkerLayer in _buildMapWidget)
    _safeSetState(() {
      _userPosition = LatLng(position.latitude, position.longitude);
      if (_routeLatLngs.isNotEmpty) {
        _routeLatLngs[0] = LatLng(position.latitude, position.longitude);
      }
    });

    // Kamera folgt User-Position wenn Camera-Lock aktiv
    if (_isCameraLocked && _mapReady) {
      try {
        _mapController.move(
          LatLng(position.latitude, position.longitude),
          16.0,
        );
      } catch (e) {
        debugPrint('[CruiseMode] Kamera-Folgen fehlgeschlagen: $e');
      }
    }

    if (!_isRouteConfirmed || _fullRouteCoordinates.length < 2) return;

    final match = findNearestInWindow(
      position: position,
      coordinates: _fullRouteCoordinates,
      currentIndex: _currentRouteIndex,
      windowSize: 40,
    );

    // Rerouting: Wenn zu weit von der Route entfernt → erst zählen, dann neu berechnen
    if (match.distanceMeters > _offRouteThresholdMeters) {
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
    } else {
      _offRouteCount = 0; // Wieder auf der Route → Counter zurücksetzen
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

      // Route häufiger in kleineren Schritten neu zeichnen (flüssigere Orange-Linie)
      // WICHTIG: Immer nur 3km voraus zeigen (Sliding Window)
      final redrawByIndex =
          _currentRouteIndex - _lastDrawnRouteIndex >=
          _routeRedrawIndexThreshold;
      final redrawByDistance =
          _distanceSinceLastRedraw >= _routeRedrawDistanceMeters;
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

      final maxRejoinIndex = math.max(0, _fullRouteCoordinates.length - 2);
      var rejoinIndex = selectForwardRejoinIndex(
        coordinates: _fullRouteCoordinates,
        nearestIndex: globalMatch.index,
        currentHeadingDegrees: heading,
      ).clamp(0, maxRejoinIndex).toInt();

      RouteResult? rerouteResult;
      for (var attempt = 0; attempt < 3; attempt++) {
        final rejoinPoint = _fullRouteCoordinates[rejoinIndex];
        final distToRejoin = geo.Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          rejoinPoint[1],
          rejoinPoint[0],
        );
        if (distToRejoin < 200) return;

        final candidate = await _routeService.generatePointToPoint(
          startPosition: position,
          destinationLat: rejoinPoint[1],
          destinationLng: rejoinPoint[0],
          mode: 'Standard',
        );

        if (candidate.coordinates.length < 2) {
          rejoinIndex = math.min(rejoinIndex + 80, maxRejoinIndex).toInt();
          continue;
        }

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

        rerouteResult = candidate;
        break;
      }

      if (rerouteResult == null || !mounted || _disposed) return;

      // Neue Route mit dem Rest der Originalroute zusammenführen
      final rerouteCoords = rerouteResult.coordinates;
      final remainingOriginal = _fullRouteCoordinates.sublist(rejoinIndex);
      final mergedCoordinates = [...rerouteCoords, ...remainingOriginal];

      // Maneuvers für den neuen Abschnitt + verbleibende originale Maneuvers
      final remainingManeuvers = _maneuvers
          .where((m) => m.routeIndex >= rejoinIndex)
          .map(
            (m) => RouteManeuver(
              latitude: m.latitude,
              longitude: m.longitude,
              routeIndex: m.routeIndex - rejoinIndex + rerouteCoords.length,
              icon: m.icon,
              announcement: m.announcement,
              instruction: m.instruction,
            ),
          )
          .toList();

      final rerouteManeuvers = rerouteResult.maneuvers;
      final allManeuvers = [...rerouteManeuvers, ...remainingManeuvers];

      // Route wird über _drawRoute() automatisch aktualisiert (GeoJSON Source Update)

      _safeSetState(() {
        _fullRouteCoordinates = mergedCoordinates;
        _currentRouteIndex = 0;
        _lastDrawnRouteIndex = 0; // Reset damit Route sofort gezeichnet wird
        _distanceSinceLastRedraw = 0.0;
        _maneuvers = allManeuvers;
        _activeManeuverIndex = 0;
        _announcedManeuverIndices.clear();
        // Speed-History entfernt — Zeit wird über Mapbox-Proportion berechnet
      });

      // Verbleibende Distanz/Zeit neu berechnen (ohne originale Werte zu überschreiben)
      _updateRemainingDistanceAndDuration();

      // Route auf der Karte neu zeichnen — Start bei User-Position
      final windowEnd = _findLookAheadIndex(0, 3000);
      final routeSlice = mergedCoordinates.sublist(0, windowEnd);
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
    } catch (e) {
      debugPrint('Rerouting fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Rerouting fehlgeschlagen: $e'),
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

  /// Zeigt den Simulations-Puck (blauer Kreis mit weißem Ring) als MarkerLayer.
  /// Kein Mapbox AnnotationManager mehr — flutter_map rendert via State.
  Future<void> _updateSimulationPuck(double lng, double lat) async {
    _safeSetState(() {
      _simulationPuckPosition = LatLng(lat, lng); // lng,lat → LatLng(lat,lng)
    });
  }

  /// Entfernt den Simulations-Puck (State auf null setzen).
  Future<void> _removeSimulationPuck() async {
    _safeSetState(() {
      _simulationPuckPosition = null;
    });
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
          await _saveRouteAndSyncXp();
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
        : null;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CruiseCompletionDialog(
        distanceKm: drivenKm,
        totalRouteKm: totalKm,
        isEarlyStop: true,
        onSave: (rating) async {
          Navigator.pop(ctx);
          await _saveRouteAndSyncXp(rating: rating);
          _resetAfterCompletion();
        },
        onDiscard: () async {
          Navigator.pop(ctx);
          await _saveRouteAndSyncXp();
          _resetAfterCompletion();
        },
      ),
    );
  }

  /// Speichert die gefahrene Route und synchronisiert XP/Level/Badges.
  Future<void> _saveRouteAndSyncXp({int? rating}) async {
    try {
      debugPrint(
        '[CruiseMode] _saveRouteAndSyncXp: _lastRouteResult=${_lastRouteResult != null}, rating=$rating',
      );
      if (_lastRouteResult != null) {
        // Route mit tatsächlich gefahrener Distanz speichern
        final drivenDistanceMeters = _totalDistanceDriven > 0
            ? _totalDistanceDriven
            : _routeDistance;
        final adjustedResult = RouteResult(
          geoJson: _lastRouteResult!.geoJson,
          geometry: _lastRouteResult!.geometry,
          coordinates: _lastRouteResult!.coordinates,
          maneuvers: _lastRouteResult!.maneuvers,
          distanceMeters: drivenDistanceMeters,
          durationSeconds: _lastRouteResult!.durationSeconds,
          distanceKm: drivenDistanceMeters != null
              ? drivenDistanceMeters / 1000
              : null,
        );
        debugPrint(
          '[CruiseMode] Saving route: style=$_selectedStyle, roundTrip=$_isRoundTrip, distKm=${adjustedResult.distanceKm}',
        );
        await SavedRoutesService.saveRoute(
          result: adjustedResult,
          style: _selectedStyle,
          isRoundTrip: _isRoundTrip,
          rating: rating,
          drivenKm: _totalDistanceDriven > 0
              ? _totalDistanceDriven / 1000
              : null,
        );
        debugPrint('[CruiseMode] Route saved successfully!');
      }
      // XP/Level/Badges synchronisieren
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
