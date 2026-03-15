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

class CruiseModePage extends StatefulWidget {
  const CruiseModePage({super.key, this.initialRoute});

  /// Wenn gesetzt, wird diese Route direkt geladen und bestätigt.
  final SavedRoute? initialRoute;

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
    _stopSimulation(restartLiveTracking: false);
    _positionSubscription?.cancel();
    _mapboxMap = null;
    _destinationController.dispose();
    super.dispose();
  }

  // ═══════════════════════ BUILD ════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isRouteConfirmed) return _buildFullscreenMap();

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                backgroundColor: const Color(0xFF0B0E14),
                elevation: 0,
                automaticallyImplyLeading: false,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    children: [
                      _buildMapWidget(),
                      Container(
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
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
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
      ),
    );
  }

  // ═══════════════════════ FULLSCREEN MAP ═══════════════════════════════════

  Widget _buildFullscreenMap() {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: Stack(
        children: [
          _buildMapWidget(),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(20),
              ),
              child: IconButton(
                onPressed: () => setState(() {
                  _stopSimulation(restartLiveTracking: false);
                  _stopNavigationTracking();
                  _isRouteConfirmed = false;
                  _viewportState = null;
                }),
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Zurück',
              ),
            ),
          ),
          if (_maneuvers.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12, right: 12,
              child: CruiseManeuverIndicator(
                maneuver: _maneuvers[_activeManeuverIndex.clamp(0, _maneuvers.length - 1)],
                userPosition: _userLocation,
              ),
            ),
          Positioned(
            left: 16, right: 16, bottom: 20,
            child: CruiseNavigationInfoPanel(
              durationSeconds: _routeDuration,
              distanceMeters: _routeDistance,
            ),
          ),
          Positioned(
            right: 16, bottom: 112,
            child: FloatingActionButton(
              heroTag: 'recenter_map_fab',
              backgroundColor: const Color(0xFF2D3138),
              foregroundColor: Colors.white,
              onPressed: _recenterMap,
              child: const Icon(Icons.explore),
            ),
          ),
          if (_fullRouteCoordinates.length > 1)
            Positioned(
              right: 16, bottom: 170,
              child: FloatingActionButton(
                heroTag: 'simulation_fab',
                mini: true,
                backgroundColor: const Color(0xFF2D3138),
                foregroundColor: Colors.white,
                onPressed: _toggleSimulation,
                child: Icon(_isSimulationRunning ? Icons.pause : Icons.play_arrow),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════ MAP WIDGET ═══════════════════════════════════════

  Widget _buildMapWidget() {
    return Stack(
      fit: StackFit.expand,
      children: [
        MapWidget(
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
          },
          onMapLoadErrorListener: (event) {
            if (!mounted || _disposed) return;
            _safeSetState(() => _mapLoadError = event.message);
          },
          cameraOptions: CameraOptions(zoom: 13.0, pitch: 0.0, bearing: 0.0),
          viewport: _viewportState,
        ),
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

    try {
      if (_routeGeoJson != null) {
        final geometry = Map<String, dynamic>.from(json.decode(_routeGeoJson!) as Map);
        await _drawRoute(geometry);
        if (_isRouteConfirmed) await _activateNavigationCamera();
      } else {
        await _initializeMapLocation();
      }
      if (_userLocation != null) await _updateVisibleCursor(_userLocation!);
    } catch (e) {
      debugPrint('Map initialization failed: $e');
      _safeSetState(() => _mapLoadError = 'Karte konnte nicht initialisiert werden.');
    }
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
      _isRouteConfirmed = false;
      _viewportState = null;
      _fullRouteCoordinates = result.coordinates;
      _remainingRouteCoordinates = result.coordinates;
      _maneuvers = result.maneuvers;
      _activeManeuverIndex = 0;
      _currentRouteIndex = 0;
      _announcedManeuverIndices.clear();
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
      final windowEnd = _findLookAheadIndex(0, 3000);
      _remainingRouteCoordinates = total >= 2
          ? _fullRouteCoordinates.sublist(0, windowEnd)
          : _fullRouteCoordinates;
    });

    // Route sofort speichern (ohne Bewertung)
    if (_lastRouteResult != null) {
      SavedRoutesService.saveRoute(
        result: _lastRouteResult!,
        style: _selectedStyle,
        isRoundTrip: _isRoundTrip,
      ).then((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Route gespeichert'),
              duration: Duration(seconds: 2),
              backgroundColor: Color(0xFF1A1F26),
            ),
          );
        }
      }).catchError((_) {});
    }

    _startNavigationTracking();
    if (total >= 2) {
      await _drawRoute(
        {'type': 'LineString', 'coordinates': _remainingRouteCoordinates},
        animateCamera: false,
      );
    }
    await _activateNavigationCamera();
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
    await _updateVisibleCursor(position);

    if (_isRouteConfirmed && _mapboxMap != null) {
      await _focusCameraOnPosition(position, animated: false);
    }

    if (!_isRouteConfirmed || _fullRouteCoordinates.length < 2) return;

    final match = findNearestInWindow(
      position: position,
      coordinates: _fullRouteCoordinates,
      currentIndex: _currentRouteIndex,
    );

    var needsRebuild = false;

    if (match.index > _currentRouteIndex && match.distanceMeters <= 45.0) {
      _currentRouteIndex = match.index;
      needsRebuild = true;

      final windowEnd = _findLookAheadIndex(_currentRouteIndex, 3000);
      _remainingRouteCoordinates = _fullRouteCoordinates.sublist(_currentRouteIndex, windowEnd);
      final clipped = {'type': 'LineString', 'coordinates': _remainingRouteCoordinates};
      _routeGeoJson = json.encode(clipped);
      await _drawRoute(clipped, animateCamera: false);
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
    if (_fullRouteCoordinates.length < 2) return;
    _stopNavigationTracking();
    _simulationIndex = 0;
    _currentRouteIndex = 0;
    _announcedManeuverIndices.clear();
    _activeManeuverIndex = 0;
    _isSimulationRunning = true;

    final windowEnd = _findLookAheadIndex(0, 3000);
    _remainingRouteCoordinates = _fullRouteCoordinates.sublist(0, windowEnd);
    final fullGeometry = {'type': 'LineString', 'coordinates': _remainingRouteCoordinates};
    _routeGeoJson = json.encode(fullGeometry);
    await _drawRoute(fullGeometry, animateCamera: false);

    final first = _fullRouteCoordinates.first;
    final second = _fullRouteCoordinates[1];
    await _focusCameraOnPosition(_buildSimulatedPosition(first, second), animated: true);
    _safeSetState(() {});

    _simulationTimer?.cancel();
    _scheduleNextSimulationStep();
  }

  void _stopSimulation({bool restartLiveTracking = true}) {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _isSimulationStepRunning = false;
    _isSimulationRunning = false;
    if (restartLiveTracking && _isRouteConfirmed) _startNavigationTracking();
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
    final delayMs = (distMeters / 41.67 * 1000).round().clamp(30, 5000); // 150 km/h
    _simulationTimer = Timer(Duration(milliseconds: delayMs), _runSimulationStep);
  }

  Future<void> _runSimulationStep() async {
    if (!_isSimulationRunning || _isSimulationStepRunning ||
        _fullRouteCoordinates.length < 2) {
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
      await _onLocationUpdate(_buildSimulatedPosition(current, next));
      if (_simulationIndex >= lastIndex) {
        _stopSimulation(restartLiveTracking: false);
        _onRouteCompleted();
        return;
      }
    } finally {
      _isSimulationStepRunning = false;
    }
    _scheduleNextSimulationStep();
  }

  geo.Position _buildSimulatedPosition(List<double> current, List<double> next) {
    final heading = calculateBearing(current[1], current[0], next[1], next[0]);
    return geo.Position(
      longitude: current[0],
      latitude: current[1],
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      heading: heading,
      speed: 41.67, // 150 km/h
      speedAccuracy: 1,
      altitudeAccuracy: 0,
      headingAccuracy: 5,
    );
  }

  // ═══════════════════════ ROUTE COMPLETION ═════════════════════════════════

  void _onRouteCompleted() {
    if (!mounted || _disposed) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CruiseCompletionDialog(
        distanceKm: _routeDistance != null ? _routeDistance! / 1000 : null,
        onSave: (rating) {
          Navigator.pop(ctx);
          _resetAfterCompletion();
        },
        onDiscard: () {
          Navigator.pop(ctx);
          _resetAfterCompletion();
        },
      ),
    );
  }

  void _resetAfterCompletion() {
    _safeSetState(() {
      _isRouteConfirmed = false;
      _viewportState = null;
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
