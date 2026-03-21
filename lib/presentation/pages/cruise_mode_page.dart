import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'package:cruise_connect/data/services/geocoding_service.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/mapbox_suggestion.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart' show RouteManeuver;
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_completion_dialog.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_maneuver_indicator.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_navigation_info_panel.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_route_type_dialog.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_setup_card.dart';
import 'package:cruise_connect/data/services/drive_control_panel.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';

class CruiseModePage extends StatefulWidget {
  const CruiseModePage({super.key, this.initialRoute});

  /// Wenn gesetzt, wird diese Route direkt geladen und bestätigt.
  final SavedRoute? initialRoute;

  /// Signalisiert dem Parent (HomePage), dass die Navigation im Fullscreen-Modus ist.
  /// Wenn true, soll die BottomNavigationBar ausgeblendet werden.
  static final ValueNotifier<bool> isFullscreen = ValueNotifier<bool>(false);

  @override
  State<CruiseModePage> createState() => _CruiseModePageState();
}

class _CruiseModePageState extends State<CruiseModePage> {
  // ─────────────────────── Services ──────────────────────────────────────────
  final _geocodingService = const GeocodingService();
  final _routeService = const RouteService();

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

  // ─────────────────────── Map State ─────────────────────────────────────────
  bool _isLoading = false;
  MapboxMap? _mapboxMap;
  PolylineAnnotationManager? _greyAnnotationManager;
  PolylineAnnotationManager? _polylineAnnotationManager;
  PolylineAnnotationManager? _cursorAnnotationManager;
  CircleAnnotationManager? _simPuckManager;
  ViewportState? _viewportState;
  bool _isMapStyleLoaded = false;
  String? _mapLoadError;
  int _mapWidgetVersion = 0;

  // ─────────────────────── Navigation State ─────────────────────────────────
  geo.Position? _userLocation;
  List<List<double>> _fullRouteCoordinates = [];
  List<List<double>> _remainingRouteCoordinates = [];
  List<RouteManeuver> _maneuvers = const [];
  int _activeManeuverIndex = 0;
  int _currentRouteIndex = 0;
  final Set<int> _announcedManeuverIndices = <int>{};
  StreamSubscription<geo.Position>? _positionSubscription;

  // ─────────────────────── Simulation State ─────────────────────────────────
  Timer? _simulationTimer;
  bool _isSimulationRunning = false;
  bool _isSimulationStepRunning = false;
  int _simulationIndex = 0;
  bool _isSimulationEnabled = true; // Simulation für Testing
  double _simulationSpeedKmh = 60; // Aktuelle Simulationsgeschwindigkeit

  bool _isCameraLocked = false; // Compass-Toggle: true = Kamera folgt dem Standort
  double? _remainingDistance; // Live verbleibende Distanz in Metern
  double? _remainingDuration; // Live verbleibende Zeit in Sekunden
  bool _isRerouting = false; // Verhindert mehrfaches gleichzeitiges Rerouting
  DateTime? _lastRerouteTime; // Cooldown zwischen Reroutes
  int _offRouteCount = 0; // Zählt aufeinanderfolgende Off-Route-Updates
  static const double _offRouteThresholdMeters = 150.0; // Ab wann Rerouting ausgelöst wird
  static const int _offRouteCountThreshold = 5; // Mindestanzahl Off-Route-Updates vor Reroute
  double _totalDistanceDriven = 0.0; // Gesamte gefahrene Strecke in Metern
  double? _originalRouteDistance; // Ursprüngliche Gesamtdistanz (für Zeitberechnung)
  double? _originalRouteDuration; // Ursprüngliche Gesamtdauer (für Zeitberechnung)
  int _lastDrawnRouteIndex = 0; // Letzter Index bei dem die Route neu gezeichnet wurde

  bool _disposed = false;

  // ──────────────────────────────────────────────────────────────────────────

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_disposed) setState(fn);
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialRoute != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSavedRoute(widget.initialRoute!));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    CruiseModePage.isFullscreen.value = false;
    _stopSimulation(restartLiveTracking: false);
    _positionSubscription?.cancel();
    _mapboxMap = null;
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
    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            // Transparenter Bereich oben → Map scheint durch
            SliverToBoxAdapter(
              child: Container(
                height: 300,
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
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                color: const Color(0xFF0B0E14),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                      onRoundTripChanged: (v) => setState(() => _isRoundTrip = v),
                      onPlanningTypeChanged: (v) => setState(() => _planningType = v),
                      onLengthChanged: (v) => setState(() => _selectedLength = v),
                      onLocationChanged: (v) => setState(() => _selectedLocation = v),
                      onStyleChanged: (v) => setState(() => _selectedStyle = v),
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
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: _buildBottomActions(),
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
            left: 12, right: 12,
            child: CruiseManeuverIndicator(
              maneuver: _maneuvers[_activeManeuverIndex.clamp(0, _maneuvers.length - 1)],
              distanceToManeuverMeters: _calculateDistanceToManeuver(),
            ),
          ),
        // FAB-Spalte rechts: Simulation + Zentrieren
        Positioned(
          right: 16, bottom: 260,
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
                      _isSimulationRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      size: 28,
                    ),
                  ),
                ),
              // Zentrierungs-Button
              FloatingActionButton(
                heroTag: 'recenter_map_fab',
                backgroundColor: _isCameraLocked
                    ? const Color(0xFFFF3B30)
                    : const Color(0xFF2D3138),
                foregroundColor: Colors.white,
                onPressed: _toggleCameraLock,
                child: Icon(_isCameraLocked ? Icons.explore : Icons.explore_off),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 0, left: 0, right: 0,
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

                      final windowEnd = _findLookAheadIndex(_currentRouteIndex, 3000);
                      setState(() {
                        _remainingRouteCoordinates = _fullRouteCoordinates.sublist(_currentRouteIndex, windowEnd);
                      });
                      await _drawRoute(
                        {'type': 'LineString', 'coordinates': _remainingRouteCoordinates},
                        animateCamera: false,
                      );
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

  // ═══════════════════════ MAP WIDGET ═══════════════════════════════════════

  Widget _buildMapWidget() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          onPointerDown: (_) {
            // Bei Berührung der Karte: Kamera-Lock automatisch deaktivieren
            if (_isCameraLocked && _isRouteConfirmed) {
              _safeSetState(() {
                _isCameraLocked = false;
                _viewportState = null;
              });
            }
          },
          child: MapWidget(
          key: ValueKey('map_widget_$_mapWidgetVersion'),
          textureView: true,
          styleUri: MapboxStyles.DARK,
          onMapCreated: _onMapCreated,
          onStyleLoadedListener: (_) async {
            if (!mounted || _disposed) return;
            _safeSetState(() {
              _isMapStyleLoaded = true;
              _mapLoadError = null;
            });
            try {
              await _mapboxMap?.location.updateSettings(
                LocationComponentSettings(
                  enabled: true,
                  puckBearingEnabled: true,
                  puckBearing: PuckBearing.HEADING,
                ),
              );
            } catch (_) {}
            // Route zeichnen oder Karte initialisieren (erst hier, weil Annotations den Style brauchen)
            try {
              if (_routeGeoJson != null) {
                final geometry = Map<String, dynamic>.from(json.decode(_routeGeoJson!) as Map);
                await _drawRoute(geometry);
                if (_isRouteConfirmed) await _activateNavigationCamera();
              } else {
                await _initializeMapLocation();
              }
            } catch (e) {
              debugPrint('Map post-style init failed: $e');
            }
          },
          onMapLoadErrorListener: (event) {
            if (!mounted || _disposed) return;
            _safeSetState(() => _mapLoadError = event.message);
          },
          cameraOptions: CameraOptions(zoom: 13.0, pitch: 0.0, bearing: 0.0),
          viewport: _viewportState,
        )),
        if (!_isMapStyleLoaded && _mapLoadError == null)
          const ColoredBox(
            color: Color(0x880B0E14),
            child: Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
        if (_mapLoadError != null)
          Container(
            color: const Color(0xCC0B0E14),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.map_outlined, color: Colors.white70, size: 32),
                  const SizedBox(height: 12),
                  const Text(
                    'Mapbox konnte nicht geladen werden.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _mapLoadError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _retryMapLoad, child: const Text('Erneut versuchen')),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ═══════════════════════ MAP LIFECYCLE ═════════════════════════════════════

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _greyAnnotationManager = null;
    _polylineAnnotationManager = null;
    _cursorAnnotationManager = null;
    _safeSetState(() => _isMapStyleLoaded = false);
    // Route-Zeichnung wird in onStyleLoadedListener gemacht,
    // da Annotation Manager erst nach Style-Load funktionieren.
  }

  void _retryMapLoad() {
    _stopSimulation(restartLiveTracking: false);
    _stopNavigationTracking();
    setState(() {
      _mapboxMap = null;
      _greyAnnotationManager = null;
      _polylineAnnotationManager = null;
      _cursorAnnotationManager = null;
      _viewportState = null;
      _isMapStyleLoaded = false;
      _mapLoadError = null;
      _mapWidgetVersion++;
    });
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
                  width: double.infinity, height: 50,
                  child: OutlinedButton(
                    onPressed: _confirmRoute,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFF3B30), width: 1.5),
                      backgroundColor: const Color(0xFF1C1F26),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    child: const Text(
                      'Route bestätigen',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            Container(
              height: 60, width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF3B30).withValues(alpha: 0.3),
                    blurRadius: 12, offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _generateRoute,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3B30),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        _isRoundTrip ? 'Rundkurs suchen' : 'Route berechnen',
                        style: const TextStyle(
                          color: Colors.white, fontSize: 18,
                          fontWeight: FontWeight.bold, letterSpacing: 1.2,
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
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
        if (permission == geo.LocationPermission.denied) return;
      }
      if (permission == geo.LocationPermission.deniedForever) return;

      geo.Position? position = await geo.Geolocator.getLastKnownPosition();
      position ??= await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(accuracy: geo.LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10), onTimeout: () {
        throw Exception('Timeout');
      });

      _userLocation = position;
      try {
        _mapboxMap?.setCamera(
          CameraOptions(
            center: Point(coordinates: Position(position.longitude, position.latitude)),
            zoom: 13.0,
            padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
          ),
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('Konnte Karten-Position nicht setzen: $e');
    }
  }

  Future<geo.Position> _getStartCoordinates() async {
    if (_selectedLocation == 'Aktueller Standort') {
      bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Bitte aktiviere GPS/Standort in deinen Geräteeinstellungen.');
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

      geo.Position? lastPosition = await geo.Geolocator.getLastKnownPosition();
      if (lastPosition != null) return lastPosition;

      return await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(accuracy: geo.LocationAccuracy.best),
      ).timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception('Standort konnte nicht ermittelt werden.');
      });
    }
    // Fallback: Berlin
    return geo.Position(
      longitude: 13.404954, latitude: 52.520008,
      timestamp: DateTime.now(), accuracy: 0, altitude: 0,
      heading: 0, speed: 0, speedAccuracy: 0,
      altitudeAccuracy: 0, headingAccuracy: 0,
    );
  }

  // ═══════════════════════ ROUTE GENERATION ════════════════════════════════

  Future<void> _generateRoute() async {
    setState(() => _isLoading = true);
    try {
      final startPosition = await _getStartCoordinates();

      int distance = 50;
      if (_selectedLength.contains('+')) {
        distance = 150;
      } else {
        final digits = _selectedLength.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.isNotEmpty) distance = int.parse(digits);
      }

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

      final result = await _routeService.generateRoundTrip(
        startPosition: startPosition,
        targetDistanceKm: distance,
        mode: _selectedStyle,
        planningType: _planningType,
        targetLocation: targetLocation,
      );

      _applyRouteResult(result);
      await _drawRoute(result.geometry);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Route berechnet! (${result.distanceKm?.toStringAsFixed(1) ?? '--'} km)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _safeSetState(() => _isLoading = false);
    }
  }

  Future<void> _calculateRouteToDestination(
    MapboxSuggestion suggestion, {
    required bool scenic,
    int routeVariant = 0,
  }) async {
    setState(() => _isLoading = true);
    try {
      final startPosition = await _getStartCoordinates();
      final result = await _routeService.generatePointToPoint(
        startPosition: startPosition,
        destinationLat: suggestion.latitude,
        destinationLng: suggestion.longitude,
        mode: _selectedStyle,
        scenic: scenic,
      );
      _applyRouteResult(result);
      await _drawRoute(result.geometry);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${scenic ? "Coole" : "Direkte"} Route berechnet! (${result.distanceKm?.toStringAsFixed(1) ?? '--'} km)'),
            backgroundColor: Colors.green,
          ),
        );
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
      _viewportState = null;
      _fullRouteCoordinates = result.coordinates;
      _remainingRouteCoordinates = result.coordinates;
      _maneuvers = result.maneuvers;
      _activeManeuverIndex = 0;
      _currentRouteIndex = 0;
      _announcedManeuverIndices.clear();
      _totalDistanceDriven = 0.0;
      _offRouteCount = 0;
      _lastRerouteTime = null;
      _remainingDistance = null;
      _remainingDuration = null;
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
      _viewportState = null;
      _fullRouteCoordinates = coordinates;
      _remainingRouteCoordinates = coordinates;
      _maneuvers = const [];
      _activeManeuverIndex = 0;
      _currentRouteIndex = 0;
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
    final total = _fullRouteCoordinates.length;
    setState(() {
      _isRouteConfirmed = true;
      _currentRouteIndex = 0;
      // Task 1: Full Route Preview - Hier wird die komplette Route gezeichnet, noch kein 3km Cut!
      _remainingRouteCoordinates = _fullRouteCoordinates;
    });
    CruiseModePage.isFullscreen.value = true;

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

  // ═══════════════════════ ROUTE DRAWING ═════════════════════════════════════

  Future<void> _drawRoute(
    Map<String, dynamic> geometry, {
    bool animateCamera = true,
  }) async {
    if (_mapboxMap == null) return;

    final coordinatesRaw = (geometry['coordinates'] as List?) ?? const [];
    final activeCoordinates = coordinatesRaw
        .whereType<List>()
        .where((c) => c.length >= 2)
        .map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
        .toList();
    if (activeCoordinates.length < 2) return;

    try { await _greyAnnotationManager?.deleteAll(); } catch (_) {}

    final routePositions = activeCoordinates.map((c) => Position(c[0], c[1])).toList();
    try {
      _polylineAnnotationManager ??=
          await _mapboxMap!.annotations.createPolylineAnnotationManager();
      await _polylineAnnotationManager!.deleteAll();
      await _polylineAnnotationManager!.create(PolylineAnnotationOptions(
        geometry: LineString(coordinates: routePositions),
        lineColor: Colors.red.toARGB32(),
        lineWidth: 5.0,
      ));
    } catch (_) {
      _polylineAnnotationManager =
          await _mapboxMap!.annotations.createPolylineAnnotationManager();
      await _polylineAnnotationManager!.create(PolylineAnnotationOptions(
        geometry: LineString(coordinates: routePositions),
        lineColor: Colors.red.toARGB32(),
        lineWidth: 5.0,
      ));
    }

    if (animateCamera && mounted) {
      final routePoints = routePositions.map((p) => Point(coordinates: p)).toList();
      final safeTop = MediaQuery.of(context).padding.top;
      final safeBottom = MediaQuery.of(context).padding.bottom;
      final topInset = (safeTop + 18).clamp(16.0, 120.0).toDouble();
      final bottomInset =
          (_isRouteConfirmed ? safeBottom + 130 : safeBottom + 48).clamp(48.0, 220.0).toDouble();

      final previewCamera = await _mapboxMap!.cameraForCoordinatesPadding(
        routePoints,
        CameraOptions(),
        MbxEdgeInsets(top: topInset, left: 24, bottom: bottomInset, right: 24),
        null, null,
      );
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        await _mapboxMap!.flyTo(previewCamera, MapAnimationOptions(duration: 2500));
      } catch (_) {}
    }
  }

  // ═══════════════════════ NAVIGATION TRACKING ══════════════════════════════

  void _startNavigationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.bestForNavigation,
        distanceFilter: 8,
      ),
    ).listen(_onLocationUpdate);
  }

  void _stopNavigationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  Future<void> _onLocationUpdate(geo.Position position) async {
    if (!mounted || _disposed) return;
    _userLocation = position;
    // Cursor deaktiviert – nur der blaue Mapbox-Puck wird angezeigt
    // await _updateVisibleCursor(position);

    // Kamera folgt über FollowPuckViewportState (smooth) – kein manuelles setCamera nötig

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
        final cooldownOk = _lastRerouteTime == null ||
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
        _totalDistanceDriven += geo.Geolocator.distanceBetween(c1[1], c1[0], c2[1], c2[0]);
      }
      _currentRouteIndex = match.index;
      needsRebuild = true;

      // Verbleibende Distanz und Zeit live berechnen
      _updateRemainingDistanceAndDuration();

      // Route bei jedem Index-Schritt neu zeichnen, mit User-Position
      // als Startpunkt interpoliert (kein Gap, kein Trail hinter dem Punkt)
      if (_currentRouteIndex - _lastDrawnRouteIndex >= 1) {
        _lastDrawnRouteIndex = _currentRouteIndex;
        final windowEnd = _findLookAheadIndex(_currentRouteIndex, 3000);
        final routeSlice = _fullRouteCoordinates.sublist(_currentRouteIndex, windowEnd);

        // Route startet exakt an der User-Position (kein Gap/Trail)
        if (_userLocation != null && routeSlice.isNotEmpty) {
          routeSlice[0] = [_userLocation!.longitude, _userLocation!.latitude];
        }

        _remainingRouteCoordinates = routeSlice;
        final clipped = {'type': 'LineString', 'coordinates': _remainingRouteCoordinates};
        _routeGeoJson = json.encode(clipped);
        await _drawRoute(clipped, animateCamera: false);
      }
    }

    // Prüfe ob Route zu Ende ist
    final lastIndex = _fullRouteCoordinates.length - 1;
    if (_currentRouteIndex >= lastIndex - 1) {
      final end = _fullRouteCoordinates.last;
      final distToEnd = geo.Geolocator.distanceBetween(
        position.latitude, position.longitude, end[1], end[0],
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
    if (_activeManeuverIndex != prevManeuver) needsRebuild = true;

    if (needsRebuild) _safeSetState(() {});
  }

  void _updateRemainingDistanceAndDuration() {
    if (_fullRouteCoordinates.length < 2 || _currentRouteIndex >= _fullRouteCoordinates.length - 1) {
      _remainingDistance = 0;
      _remainingDuration = 0;
      return;
    }
    // Verbleibende Distanz ab aktuellem Index bis Ende summieren
    double dist = 0.0;
    for (var i = _currentRouteIndex; i < _fullRouteCoordinates.length - 1; i++) {
      final c1 = _fullRouteCoordinates[i];
      final c2 = _fullRouteCoordinates[i + 1];
      dist += geo.Geolocator.distanceBetween(c1[1], c1[0], c2[1], c2[0]);
    }
    _remainingDistance = dist;

    // Stabile Zeitberechnung: Mapbox-Originalzeit × verbleibender Anteil.
    // Wie echte Navigation — die Zeit basiert auf der Routenplanung,
    // nicht auf der aktuellen GPS-Geschwindigkeit.
    final origDur = _originalRouteDuration ?? _routeDuration;
    if (origDur != null && origDur > 0 && _fullRouteCoordinates.length > 1) {
      final remainingFraction = (_fullRouteCoordinates.length - 1 - _currentRouteIndex) /
          (_fullRouteCoordinates.length - 1);
      final newDuration = origDur * remainingFraction;

      // Sanft interpolieren damit es nicht springt
      if (_remainingDuration != null) {
        _remainingDuration = _remainingDuration! + (newDuration - _remainingDuration!) * 0.2;
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
        ..showSnackBar(const SnackBar(
          content: Text('Route wird neu berechnet...'),
          backgroundColor: Color(0xFFFF9500),
          duration: Duration(seconds: 2),
        ));
    }

    try {
      // Suche den nächsten Punkt auf der GESAMTEN verbleibenden Route (großes Fenster)
      final globalMatch = findNearestInWindow(
        position: position,
        coordinates: _fullRouteCoordinates,
        currentIndex: _currentRouteIndex,
        windowSize: _fullRouteCoordinates.length - _currentRouteIndex,
      );

      // Zielpunkt: mindestens 100 Punkte voraus (genug Abstand um sinnvolle Route zu berechnen)
      final rejoinIndex = math.min(
        globalMatch.index + 100,
        _fullRouteCoordinates.length - 1,
      );
      final rejoinPoint = _fullRouteCoordinates[rejoinIndex];

      // Wenn Zielpunkt zu nah (< 200m) → kein Rerouting nötig, einfach weiterfahren
      final distToRejoin = geo.Geolocator.distanceBetween(
        position.latitude, position.longitude, rejoinPoint[1], rejoinPoint[0],
      );
      if (distToRejoin < 200) return;

      // Neue Route via Edge Function (= Mapbox Directions API = befahrbare Straßen)
      final rerouteResult = await _routeService.generatePointToPoint(
        startPosition: position,
        destinationLat: rejoinPoint[1],
        destinationLng: rejoinPoint[0],
        mode: 'Standard',
      );

      if (!mounted || _disposed) return;

      // Neue Route mit dem Rest der Originalroute zusammenführen
      final rerouteCoords = rerouteResult.coordinates;
      if (rerouteCoords.length < 2) {
        // Reroute hat keine brauchbare Route ergeben → ignorieren
        return;
      }

      final remainingOriginal = _fullRouteCoordinates.sublist(rejoinIndex);
      final mergedCoordinates = [...rerouteCoords, ...remainingOriginal];

      // Maneuvers für den neuen Abschnitt + verbleibende originale Maneuvers
      final remainingManeuvers = _maneuvers
          .where((m) => m.routeIndex >= rejoinIndex)
          .map((m) => RouteManeuver(
                latitude: m.latitude,
                longitude: m.longitude,
                routeIndex: m.routeIndex - rejoinIndex + rerouteCoords.length,
                icon: m.icon,
                announcement: m.announcement,
                instruction: m.instruction,
              ))
          .toList();

      final rerouteManeuvers = rerouteResult.maneuvers;
      final allManeuvers = [...rerouteManeuvers, ...remainingManeuvers];

      // WICHTIG: Alte Route komplett löschen bevor neue gezeichnet wird
      // Verhindert das Stern/Fan-Muster aus alten Linien
      try {
        await _polylineAnnotationManager?.deleteAll();
      } catch (_) {}

      _safeSetState(() {
        _fullRouteCoordinates = mergedCoordinates;
        _currentRouteIndex = 0;
        _lastDrawnRouteIndex = 0; // Reset damit Route sofort gezeichnet wird
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
      final clipped = {'type': 'LineString', 'coordinates': _remainingRouteCoordinates};
      _routeGeoJson = json.encode(clipped);
      await _drawRoute(clipped, animateCamera: false);

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('Route neu berechnet!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ));
      }
    } catch (e) {
      debugPrint('Rerouting fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('Rerouting fehlgeschlagen: $e'),
            backgroundColor: Colors.red,
          ));
      }
    } finally {
      _isRerouting = false;
    }
  }

  /// Berechnet die Distanz entlang der Route vom aktuellen Index zum nächsten Manöver.
  double? _calculateDistanceToManeuver() {
    if (_maneuvers.isEmpty || _fullRouteCoordinates.length < 2) return null;
    final maneuver = _maneuvers[_activeManeuverIndex.clamp(0, _maneuvers.length - 1)];
    final targetIndex = maneuver.routeIndex.clamp(0, _fullRouteCoordinates.length - 1);
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
      // Sofort zur aktuellen Position fliegen und FollowPuck aktivieren
      _recenterMap();
      _safeSetState(() {
        _viewportState = const FollowPuckViewportState(
          zoom: 16.0,
          pitch: 45.0,
          bearing: FollowPuckViewportStateBearingHeading(),
        );
      });
    } else {
      // FollowPuck deaktivieren → freie Kartenbewegung
      _safeSetState(() => _viewportState = null);
    }
  }

  Future<void> _recenterMap() async {
    final map = _mapboxMap;
    final position = _userLocation;
    if (map == null || position == null || !_isMapStyleLoaded) return;
    try {
      await map.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(position.longitude, position.latitude)),
          zoom: 16.0, pitch: 45.0,
          bearing: position.heading.isFinite ? position.heading : 0.0,
        ),
        MapAnimationOptions(duration: 900),
      );
    } catch (_) {}
  }

  Future<void> _focusCameraOnPosition(
    geo.Position position, {
    required bool animated,
  }) async {
    if (_mapboxMap == null || !_isMapStyleLoaded) return;
    try {
      final options = CameraOptions(
        center: Point(coordinates: Position(position.longitude, position.latitude)),
        zoom: 16.0, pitch: 45.0,
        bearing: position.heading.isFinite ? position.heading : 0.0,
      );
      if (animated) {
        await _mapboxMap!.flyTo(options, MapAnimationOptions(duration: 700));
      } else {
        await _mapboxMap!.setCamera(options);
      }
    } catch (_) {}
  }

  Future<void> _activateNavigationCamera() async {
    if (_mapboxMap == null) return;
    geo.Position position;
    try {
      position = await geo.Geolocator.getCurrentPosition();
    } catch (_) {
      position = await _getStartCoordinates();
    }
    _userLocation = position;
    if (_isMapStyleLoaded) {
      try {
        await _mapboxMap?.location.updateSettings(
          LocationComponentSettings(
            enabled: true,
            puckBearingEnabled: true,
            puckBearing: PuckBearing.HEADING,
          ),
        );
      } catch (_) {}
    }
    try {
      await _mapboxMap!.setCamera(
        CameraOptions(
          center: Point(coordinates: Position(position.longitude, position.latitude)),
          zoom: 16.0, pitch: 45.0,
          bearing: position.heading.isFinite ? position.heading : 0.0,
        ),
      );
    } catch (_) {}
    _safeSetState(() {
      _viewportState = const FollowPuckViewportState(
        zoom: 16.0,
        pitch: 45.0,
        bearing: FollowPuckViewportStateBearingHeading(),
      );
    });
  }

  // ═══════════════════════ CURSOR ═══════════════════════════════════════════

  Future<void> _updateVisibleCursor(geo.Position position) async {
    if (_mapboxMap == null) return;
    _cursorAnnotationManager ??=
        await _mapboxMap!.annotations.createPolylineAnnotationManager();

    final lng = position.longitude;
    final lat = position.latitude;
    const halfSize = 0.00007;
    final verticalLine = [Position(lng, lat - halfSize), Position(lng, lat + halfSize)];
    final hScale = math.cos(lat * math.pi / 180).abs();
    final lonSize = hScale < 0.2 ? halfSize : halfSize / hScale;
    final horizontalLine = [Position(lng - lonSize, lat), Position(lng + lonSize, lat)];
    final heading = position.heading.isFinite ? position.heading : 0.0;
    final headRad = heading * math.pi / 180;
    const headLen = halfSize * 2.5;
    final tipLat = lat + math.cos(headRad) * headLen;
    final tipLng = lng + math.sin(headRad) * (headLen / hScale.clamp(0.2, 1.0));
    final headingLine = [Position(lng, lat), Position(tipLng, tipLat)];

    Future<void> draw() async {
      await _cursorAnnotationManager!.deleteAll();
      await _cursorAnnotationManager!.create(PolylineAnnotationOptions(
        geometry: LineString(coordinates: verticalLine),
        lineColor: Colors.white.toARGB32(), lineWidth: 4.0,
      ));
      await _cursorAnnotationManager!.create(PolylineAnnotationOptions(
        geometry: LineString(coordinates: horizontalLine),
        lineColor: Colors.white.toARGB32(), lineWidth: 4.0,
      ));
      await _cursorAnnotationManager!.create(PolylineAnnotationOptions(
        geometry: LineString(coordinates: headingLine),
        lineColor: const Color(0xFFFF3B30).toARGB32(), lineWidth: 4.5,
      ));
    }

    try {
      await draw();
    } catch (_) {
      _cursorAnnotationManager =
          await _mapboxMap!.annotations.createPolylineAnnotationManager();
      await draw();
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
    _totalDistanceDriven = 0;
    _announcedManeuverIndices.clear();
    _activeManeuverIndex = 0;
    // Speed-History entfernt
    _isSimulationRunning = true;
    _simulationSpeedKmh = 60;

    // Initiale Route zeichnen
    final windowEnd = _findLookAheadIndex(0, 3000);
    _remainingRouteCoordinates = _fullRouteCoordinates.sublist(0, windowEnd);
    final fullGeometry = {'type': 'LineString', 'coordinates': _remainingRouteCoordinates};
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

  /// Berechnet realistische Geschwindigkeit basierend auf Kurven voraus.
  /// Bremst vor Kurven ab und beschleunigt auf Geraden.
  double _calculateSimulationSpeed() {
    final lastIndex = _fullRouteCoordinates.length - 1;
    if (_simulationIndex >= lastIndex - 2) return _simulationSpeedKmh;

    // Schaue 5-10 Punkte voraus für Kurven
    double maxAngleChange = 0;
    final lookAhead = math.min(10, lastIndex - _simulationIndex);
    for (var i = 0; i < lookAhead - 1; i++) {
      final idx = _simulationIndex + i;
      if (idx + 2 > lastIndex) break;
      final p1 = _fullRouteCoordinates[idx];
      final p2 = _fullRouteCoordinates[idx + 1];
      final p3 = _fullRouteCoordinates[idx + 2];
      final bearing1 = calculateBearing(p1[1], p1[0], p2[1], p2[0]);
      final bearing2 = calculateBearing(p2[1], p2[0], p3[1], p3[0]);
      var diff = (bearing2 - bearing1).abs();
      if (diff > 180) diff = 360 - diff;
      if (diff > maxAngleChange) maxAngleChange = diff;
    }

    // Zielgeschwindigkeit basierend auf Kurvenwinkel
    double targetKmh;
    if (maxAngleChange > 60) {
      targetKmh = 25; // Scharfe Kurve / Kreisverkehr
    } else if (maxAngleChange > 30) {
      targetKmh = 40; // Normale Kurve
    } else if (maxAngleChange > 15) {
      targetKmh = 55; // Leichte Kurve
    } else {
      targetKmh = 70; // Gerade
    }

    // Sanft zur Zielgeschwindigkeit interpolieren (kein abruptes Bremsen)
    _simulationSpeedKmh += (targetKmh - _simulationSpeedKmh) * 0.15;
    return _simulationSpeedKmh.clamp(15.0, 80.0);
  }

  void _scheduleNextSimulationStep() {
    _simulationTimer?.cancel();
    if (!_isSimulationRunning || _fullRouteCoordinates.length < 2) return;
    final lastIndex = _fullRouteCoordinates.length - 1;
    if (_simulationIndex >= lastIndex) return;

    final current = _fullRouteCoordinates[_simulationIndex];
    final next = _fullRouteCoordinates[math.min(_simulationIndex + 1, lastIndex)];
    final distMeters = geo.Geolocator.distanceBetween(
      current[1], current[0], next[1], next[0],
    );

    final speedKmh = _calculateSimulationSpeed();
    final speedMs = speedKmh / 3.6;
    final delayMs = distMeters > 0
        ? (distMeters / speedMs * 1000).round().clamp(16, 3000)
        : 50;

    _simulationTimer = Timer(Duration(milliseconds: delayMs), _runSimulationStep);
  }

  Future<void> _runSimulationStep() async {
    if (!_isSimulationRunning || _isSimulationStepRunning ||
        _fullRouteCoordinates.length < 2 || !mounted || _disposed) {
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
      _simulationIndex = math.min(_simulationIndex + 1, lastIndex);
      final current = _fullRouteCoordinates[_simulationIndex];
      final next = _fullRouteCoordinates[math.min(_simulationIndex + 1, lastIndex)];
      final speedMs = _simulationSpeedKmh / 3.6;

      // Simulations-Puck auf der Karte bewegen (Fehler ignorieren)
      try { await _updateSimulationPuck(current[0], current[1]); } catch (_) {}

      // Location Update (Fehler ignorieren, Simulation weiterlaufen lassen)
      try { await _onLocationUpdate(_buildSimulatedPosition(current, next, speedMs)); } catch (_) {}

      if (_simulationIndex >= lastIndex) {
        _stopSimulation(restartLiveTracking: false);
        _onRouteCompleted();
        return;
      }
    } catch (_) {
      // Simulation darf nie durch einen Fehler stoppen
    } finally {
      _isSimulationStepRunning = false;
    }
    if (_isSimulationRunning) _scheduleNextSimulationStep();
  }

  /// Zeigt einen blauen Punkt + weißen Ring als simuliertes Auto auf der Karte.
  Future<void> _updateSimulationPuck(double lng, double lat) async {
    if (_mapboxMap == null) return;
    try {
      _simPuckManager ??= await _mapboxMap!.annotations.createCircleAnnotationManager();
      await _simPuckManager!.deleteAll();
      // Weißer äußerer Ring
      await _simPuckManager!.create(CircleAnnotationOptions(
        geometry: Point(coordinates: Position(lng, lat)),
        circleRadius: 12,
        circleColor: Colors.white.toARGB32(),
        circleOpacity: 0.9,
      ));
      // Blauer innerer Punkt
      await _simPuckManager!.create(CircleAnnotationOptions(
        geometry: Point(coordinates: Position(lng, lat)),
        circleRadius: 8,
        circleColor: const Color(0xFF007AFF).toARGB32(),
        circleOpacity: 1.0,
      ));
    } catch (_) {}
  }

  /// Entfernt den Simulations-Puck von der Karte.
  Future<void> _removeSimulationPuck() async {
    try {
      await _simPuckManager?.deleteAll();
    } catch (_) {}
  }

  geo.Position _buildSimulatedPosition(List<double> current, List<double> next, double speedMs) {
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
    final totalKm = _originalRouteDistance != null ? _originalRouteDistance! / 1000 : null;
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
      debugPrint('[CruiseMode] _saveRouteAndSyncXp: _lastRouteResult=${_lastRouteResult != null}, rating=$rating');
      if (_lastRouteResult != null) {
        // Route mit tatsächlich gefahrener Distanz speichern
        final drivenDistanceMeters = _totalDistanceDriven > 0 ? _totalDistanceDriven : _routeDistance;
        final adjustedResult = RouteResult(
          geoJson: _lastRouteResult!.geoJson,
          geometry: _lastRouteResult!.geometry,
          coordinates: _lastRouteResult!.coordinates,
          maneuvers: _lastRouteResult!.maneuvers,
          distanceMeters: drivenDistanceMeters,
          durationSeconds: _lastRouteResult!.durationSeconds,
          distanceKm: drivenDistanceMeters != null ? drivenDistanceMeters / 1000 : null,
        );
        debugPrint('[CruiseMode] Saving route: style=$_selectedStyle, roundTrip=$_isRoundTrip, distKm=${adjustedResult.distanceKm}');
        await SavedRoutesService.saveRoute(
          result: adjustedResult,
          style: _selectedStyle,
          isRoundTrip: _isRoundTrip,
          rating: rating,
          drivenKm: _totalDistanceDriven > 0 ? _totalDistanceDriven / 1000 : null,
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
          SnackBar(content: Text('Fehler beim Speichern: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _resetAfterCompletion() {
    CruiseModePage.isFullscreen.value = false;
    _safeSetState(() {
      _isRouteConfirmed = false;
      _viewportState = null;
      _isCameraLocked = false;
      _totalDistanceDriven = 0.0;
    });
  }

  // ═══════════════════════ DIALOGS ══════════════════════════════════════════

  void _showRouteTypeDialog(MapboxSuggestion suggestion) {
    showRouteTypeDialog(
      context: context,
      suggestion: suggestion,
      selectedStyle: _selectedStyle,
      onRouteSelected: (s, {required bool scenic, int routeVariant = 0}) {
        _calculateRouteToDestination(s, scenic: scenic, routeVariant: routeVariant);
      },
    );
  }

  void _showError(String message) {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Fehler: $message'), backgroundColor: Colors.red),
    );
  }
}
