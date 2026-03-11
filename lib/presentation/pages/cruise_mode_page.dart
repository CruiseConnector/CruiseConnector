import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// TTS deaktiviert - import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

class _RouteManeuver {
  const _RouteManeuver({
    required this.latitude,
    required this.longitude,
    required this.routeIndex,
    required this.icon,
    required this.announcement,
    required this.instruction,
  });

  final double latitude;
  final double longitude;
  final int routeIndex;
  final IconData icon;
  final String announcement;
  final String instruction;
}

class _RouteWindowMatch {
  const _RouteWindowMatch({required this.index, required this.distanceMeters});

  final int index;
  final double distanceMeters;
}

class CruiseModePage extends StatefulWidget {
  const CruiseModePage({super.key});

  @override
  State<CruiseModePage> createState() => _CruiseModePageState();
}

class _CruiseModePageState extends State<CruiseModePage> {
  bool _isRoundTrip = true;
  bool _isRouteConfirmed = false;
  String? _routeGeoJson;
  double? _routeDistance;
  double? _routeDuration;
  String _planningType = 'Zufall';

  String _selectedLength = '50 Km';
  String _selectedLocation = 'Aktueller Standort';
  String _selectedStyle = 'Sport Mode';

  final TextEditingController _destinationController = TextEditingController();

  bool _isLoading = false;
  MapboxMap? _mapboxMap;
  PolylineAnnotationManager? _greyAnnotationManager;
  PolylineAnnotationManager? _polylineAnnotationManager;
  PolylineAnnotationManager? _cursorAnnotationManager;
  ViewportState? _viewportState;
  // TTS deaktiviert - zu viele Audio-Probleme
  // final FlutterTts _flutterTts = FlutterTts();
  StreamSubscription<geo.Position>? _positionSubscription;
  bool _ttsAvailable = false; // false = komplett deaktiviert

  geo.Position? _userLocation;
  List<List<double>> _fullRouteCoordinates = [];
  List<List<double>> _remainingRouteCoordinates = [];
  List<_RouteManeuver> _maneuvers = const [];
  int _activeManeuverIndex = 0;
  int _currentRouteIndex = 0;
  static const int _routeSearchWindowSize = 20;
  static const double _maxRouteIndexJumpDistanceMeters = 45.0;
  final Set<int> _announcedManeuverIndices = <int>{};
  Timer? _simulationTimer;
  bool _isSimulationRunning = false;
  bool _isSimulationStepRunning = false;
  int _simulationIndex = 0;
  bool _isMapStyleLoaded = false;
  String? _mapLoadError;
  int _mapWidgetVersion = 0;

  @override
  void initState() {
    super.initState();
    _configureTts();
  }

  @override
  void dispose() {
    _stopSimulation(restartLiveTracking: false);
    _positionSubscription?.cancel();
    // TTS deaktiviert
    // if (_ttsAvailable) {
    //   _flutterTts.stop();
    // }
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isRouteConfirmed) {
      return _buildFullscreenMap();
    }

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
                              const Color(0xFF0B0E14).withOpacity(0.8),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: Column(
                    children: [_buildSetupCard(), const SizedBox(height: 140)],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomActions(),
          ),
        ],
      ),
    );
  }

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
                color: Colors.black.withOpacity(0.45),
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
          if (_isRouteConfirmed && _maneuvers.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 12,
              child: _buildManeuverIndicator(),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: _buildNavigationInfoPanel(),
          ),
          Positioned(
            right: 16,
            bottom: 112,
            child: FloatingActionButton(
              heroTag: 'recenter_map_fab',
              backgroundColor: const Color(0xFF2D3138),
              foregroundColor: Colors.white,
              onPressed: _recenterMap,
              child: const Icon(Icons.explore),
            ),
          ),
          if (_isRouteConfirmed && _fullRouteCoordinates.length > 1)
            Positioned(
              right: 16,
              bottom: 170,
              child: FloatingActionButton(
                heroTag: 'simulation_fab',
                mini: true,
                backgroundColor: const Color(0xFF2D3138),
                foregroundColor: Colors.white,
                onPressed: _toggleSimulation,
                child: Icon(
                  _isSimulationRunning ? Icons.pause : Icons.play_arrow,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapWidget() {
    return Stack(
      fit: StackFit.expand,
      children: [
        MapWidget(
          key: ValueKey('map_widget_$_mapWidgetVersion'),
          textureView: true,
          styleUri: MapboxStyles.DARK,
          onMapCreated: (MapboxMap mapboxMap) async {
            _mapboxMap = mapboxMap;
            _greyAnnotationManager = null;
            _polylineAnnotationManager = null;
            _cursorAnnotationManager = null;

            if (mounted) {
              setState(() {
                _isMapStyleLoaded = false;
                _mapLoadError = null;
              });
            }

            try {
              if (_routeGeoJson != null) {
                final decoded = json.decode(_routeGeoJson!);
                final geometry = Map<String, dynamic>.from(decoded as Map);
                await _drawRoute(geometry);
                if (_isRouteConfirmed) {
                  await _activateNavigationCamera();
                }
              } else {
                await _initializeMapLocation();
              }

              if (_userLocation != null) {
                await _updateVisibleCursor(_userLocation!);
              }
            } catch (error) {
              debugPrint('Map initialization failed: $error');
              if (mounted) {
                setState(() {
                  _mapLoadError = 'Karte konnte nicht initialisiert werden.';
                });
              }
            }
          },
          onStyleLoadedListener: (_) {
            if (!mounted) return;
            setState(() {
              _isMapStyleLoaded = true;
              _mapLoadError = null;
            });
          },
          onMapLoadErrorListener: (event) {
            debugPrint('Map load error (${event.type}): ${event.message}');
            if (!mounted) return;
            setState(() {
              _mapLoadError = event.message;
            });
          },
          cameraOptions: CameraOptions(zoom: 13.0, pitch: 0.0, bearing: 0.0),
          viewport: _viewportState,
        ),
        if (!_isMapStyleLoaded && _mapLoadError == null)
          const ColoredBox(
            color: Color(0x880B0E14),
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        if (_mapLoadError != null)
          Container(
            color: const Color(0xCC0B0E14),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.map_outlined,
                    color: Colors.white70,
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Mapbox konnte nicht geladen werden.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _mapLoadError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _retryMapLoad,
                    child: const Text('Erneut versuchen'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
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

  Widget _buildSetupCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Strecken-Setup',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Routen-Modus',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildLargeModeButton(
                  label: 'Rundkurs',
                  icon: Icons.loop,
                  isActive: _isRoundTrip,
                  onTap: () => setState(() => _isRoundTrip = true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildLargeModeButton(
                  label: 'A nach B',
                  icon: Icons.alt_route,
                  isActive: !_isRoundTrip,
                  onTap: () => setState(() => _isRoundTrip = false),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 32),
          AnimatedCrossFade(
            firstChild: _buildRoundTripOptions(),
            secondChild: _buildAtoBOptions(),
            crossFadeState: _isRoundTrip
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 300),
          ),
          const Divider(color: Colors.white10, height: 32),
          if (_isRoundTrip)
            _buildSelectionRow(
              'Länge',
              ['20 Km', '50 Km', '100 Km', '+100 Km'],
              _selectedLength,
              (val) => setState(() => _selectedLength = val),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Länge',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Distanz wird automatisch basierend auf dem Zielort berechnet.',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const Divider(color: Colors.white10, height: 32),
          _buildSelectionRow(
            'Standort',
            ['Aktueller Standort', 'Standort wählen'],
            _selectedLocation,
            (val) => setState(() => _selectedLocation = val),
          ),
          const Divider(color: Colors.white10, height: 32),
          _buildSelectionRow(
            'Stil',
            ['Kurvenjagd', 'Sport Mode', 'Abendrunde', 'Entdecker'],
            _selectedStyle,
            (val) => setState(() => _selectedStyle = val),
          ),
        ],
      ),
    );
  }

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
                    color: const Color(0xFFFF3B30).withOpacity(0.3),
                    blurRadius: 12,
                    spreadRadius: 0,
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

  Widget _buildNavigationInfoPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF151922).withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Verbleibende Zeit',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDuration(_routeDuration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 36, color: Colors.white12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Strecke',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDistanceKm(_routeDistance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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

      final position = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
        ),
      );

      _userLocation = position;

      await _mapboxMap?.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          puckBearingEnabled: true,
          puckBearing: PuckBearing.HEADING,
        ),
      );

      _mapboxMap?.setCamera(
        CameraOptions(
          center: Point(
            coordinates: Position(position.longitude, position.latitude),
          ),
          zoom: 13.0,
          padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
        ),
      );
    } catch (e) {
      debugPrint('Konnte Karten-Position nicht setzen: $e');
    }
  }

  Future<void> _drawRoute(
    Map<String, dynamic> geometry, {
    bool animateCamera = true,
  }) async {
    if (_mapboxMap == null) return;

    final coordinatesRaw = (geometry['coordinates'] as List?) ?? const [];

    // Parse the active/remaining route from the geometry passed in.
    final activeCoordinates = coordinatesRaw
        .whereType<List>()
        .where((c) => c.length >= 2)
        .map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
        .toList();

    if (activeCoordinates.length < 2) return;

    // ── Grey background layer: full planned route ────────────────────────
    // Visible once the route is confirmed so overlapping segments on a
    // round trip are clearly distinguishable: grey = still planned but not
    // the immediate segment, red = what to drive right now.
    if (_isRouteConfirmed && _fullRouteCoordinates.length >= 2) {
      try {
        _greyAnnotationManager ??= await _mapboxMap!.annotations
            .createPolylineAnnotationManager();
        final fullPositions = _fullRouteCoordinates
            .map((c) => Position(c[0], c[1]))
            .toList();
        await _greyAnnotationManager!.deleteAll();
        await _greyAnnotationManager!.create(
          PolylineAnnotationOptions(
            geometry: LineString(coordinates: fullPositions),
            lineColor: const Color(0xFF6B7280).toARGB32(), // grey-500
            lineWidth: 5.0,
          ),
        );
      } catch (_) {
        // Channel stale – recreate manager and retry once.
        _greyAnnotationManager = await _mapboxMap!.annotations
            .createPolylineAnnotationManager();
        final fullPositions = _fullRouteCoordinates
            .map((c) => Position(c[0], c[1]))
            .toList();
        await _greyAnnotationManager!.create(
          PolylineAnnotationOptions(
            geometry: LineString(coordinates: fullPositions),
            lineColor: const Color(0xFF6B7280).toARGB32(),
            lineWidth: 5.0,
          ),
        );
      }
    }

    // ── Red active layer: remaining / next-to-drive segment ──────────────
    final routePositions = activeCoordinates
        .map((c) => Position(c[0], c[1]))
        .toList();

    try {
      _polylineAnnotationManager ??= await _mapboxMap!.annotations
          .createPolylineAnnotationManager();
      await _polylineAnnotationManager!.deleteAll();
      await _polylineAnnotationManager!.create(
        PolylineAnnotationOptions(
          geometry: LineString(coordinates: routePositions),
          lineColor: Colors.red.toARGB32(),
          lineWidth: 5.0,
        ),
      );
    } catch (_) {
      // Channel stale – recreate manager and retry once.
      _polylineAnnotationManager = await _mapboxMap!.annotations
          .createPolylineAnnotationManager();
      await _polylineAnnotationManager!.create(
        PolylineAnnotationOptions(
          geometry: LineString(coordinates: routePositions),
          lineColor: Colors.red.toARGB32(),
          lineWidth: 5.0,
        ),
      );
    }

    // ── Camera fit ───────────────────────────────────────────────────────
    if (animateCamera) {
      final routePoints = routePositions
          .map((p) => Point(coordinates: p))
          .toList();

      final mediaQuery = MediaQuery.of(context);
      final safeTop = mediaQuery.padding.top;
      final safeBottom = mediaQuery.padding.bottom;

      final topInset = (safeTop + 18).clamp(16.0, 120.0).toDouble();
      final bottomInset =
          (_isRouteConfirmed ? safeBottom + 130 : safeBottom + 48)
              .clamp(48.0, 220.0)
              .toDouble();

      final previewCamera = await _mapboxMap!.cameraForCoordinates(
        routePoints,
        MbxEdgeInsets(top: topInset, left: 24, bottom: bottomInset, right: 24),
        0,
        0,
      );

      await Future.delayed(const Duration(milliseconds: 100));
      await _mapboxMap!.flyTo(
        previewCamera,
        MapAnimationOptions(duration: 2500),
      );
    }
  }

  Future<void> _confirmRoute() async {
    setState(() => _isRouteConfirmed = true);
    _startNavigationTracking();
    // Immediately redraw with two layers: grey full route + red remaining.
    if (_fullRouteCoordinates.length >= 2) {
      await _drawRoute({
        'type': 'LineString',
        'coordinates': _remainingRouteCoordinates,
      }, animateCamera: false);
    }
    await _activateNavigationCamera();
  }

  Future<void> _configureTts() async {
    // TTS komplett deaktiviert - zu viele Audio-Probleme/Knirschen
    _ttsAvailable = false;
    debugPrint('TTS deaktiviert');
    return;
    
    /* Ursprünglicher TTS-Code:
    try {
      await _flutterTts.setLanguage('de-DE');
      await _flutterTts.setSpeechRate(0.48);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _ttsAvailable = true;
    } on MissingPluginException {
      _ttsAvailable = false;
      debugPrint(
        'flutter_tts Plugin nicht registriert. Bitte App komplett neu starten (kein Hot Reload).',
      );
    } on PlatformException catch (error) {
      _ttsAvailable = false;
      debugPrint('TTS konnte nicht initialisiert werden: ${error.message}');
    }
    */
  }

  Future<void> _recenterMap() async {
    final map = _mapboxMap;
    final position = _userLocation;

    if (map == null || position == null) {
      return;
    }

    await map.flyTo(
      CameraOptions(
        center: Point(
          coordinates: Position(position.longitude, position.latitude),
        ),
        zoom: 16.0,
        pitch: 45.0,
        bearing: position.heading.isFinite ? position.heading : 0.0,
      ),
      MapAnimationOptions(duration: 900),
    );
  }

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

  Future<void> _toggleSimulation() async {
    if (_isSimulationRunning) {
      _stopSimulation();
      return;
    }
    await _startSimulation();
  }

  Future<void> _startSimulation() async {
    if (_fullRouteCoordinates.length < 2) {
      return;
    }

    _stopNavigationTracking();

    _simulationIndex = 0;
    _currentRouteIndex = 0;
    _remainingRouteCoordinates = List<List<double>>.from(_fullRouteCoordinates);
    _announcedManeuverIndices.clear();
    _activeManeuverIndex = 0;
    _isSimulationRunning = true;

    final fullGeometry = {
      'type': 'LineString',
      'coordinates': _remainingRouteCoordinates,
    };
    _routeGeoJson = json.encode(fullGeometry);
    await _drawRoute(fullGeometry, animateCamera: false);

    final firstPoint = _fullRouteCoordinates.first;
    final secondPoint = _fullRouteCoordinates[1];
    final initialPosition = _buildSimulatedPosition(firstPoint, secondPoint);
    await _focusCameraOnPosition(initialPosition, animated: true);

    if (mounted) {
      setState(() {});
    }

    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 850), (_) {
      _runSimulationStep();
    });
  }

  void _stopSimulation({bool restartLiveTracking = true}) {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _isSimulationStepRunning = false;

    final wasRunning = _isSimulationRunning;
    _isSimulationRunning = false;

    if (restartLiveTracking && _isRouteConfirmed) {
      _startNavigationTracking();
    }

    if (wasRunning && mounted) {
      setState(() {});
    }
  }

  Future<void> _runSimulationStep() async {
    if (!_isSimulationRunning ||
        _isSimulationStepRunning ||
        _fullRouteCoordinates.length < 2) {
      return;
    }

    _isSimulationStepRunning = true;

    try {
      final lastIndex = _fullRouteCoordinates.length - 1;
      if (_simulationIndex >= lastIndex) {
        _stopSimulation();
        return;
      }

      _simulationIndex = math.min(_simulationIndex + 1, lastIndex);

      final currentPoint = _fullRouteCoordinates[_simulationIndex];
      final nextPoint =
          _fullRouteCoordinates[math.min(_simulationIndex + 1, lastIndex)];

      final simulatedPosition = _buildSimulatedPosition(
        currentPoint,
        nextPoint,
      );
      await _onLocationUpdate(simulatedPosition);

      if (_simulationIndex >= lastIndex) {
        _stopSimulation();
      }
    } finally {
      _isSimulationStepRunning = false;
    }
  }

  geo.Position _buildSimulatedPosition(
    List<double> currentPoint,
    List<double> nextPoint,
  ) {
    final longitude = currentPoint[0];
    final latitude = currentPoint[1];
    final nextLongitude = nextPoint[0];
    final nextLatitude = nextPoint[1];

    final heading = _calculateBearingDegrees(
      latitude,
      longitude,
      nextLatitude,
      nextLongitude,
    );

    return geo.Position(
      longitude: longitude,
      latitude: latitude,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      heading: heading,
      speed: 13.5,
      speedAccuracy: 1,
      altitudeAccuracy: 0,
      headingAccuracy: 5,
    );
  }

  double _calculateBearingDegrees(
    double startLat,
    double startLon,
    double endLat,
    double endLon,
  ) {
    final startLatRad = startLat * math.pi / 180;
    final endLatRad = endLat * math.pi / 180;
    final dLonRad = (endLon - startLon) * math.pi / 180;

    final y = math.sin(dLonRad) * math.cos(endLatRad);
    final x =
        math.cos(startLatRad) * math.sin(endLatRad) -
        math.sin(startLatRad) * math.cos(endLatRad) * math.cos(dLonRad);

    final bearingRad = math.atan2(y, x);
    final bearingDeg = bearingRad * 180 / math.pi;
    return (bearingDeg + 360) % 360;
  }

  Future<void> _onLocationUpdate(geo.Position position) async {
    if (!mounted) {
      return;
    }

    _userLocation = position;
    await _updateVisibleCursor(position);

    if (_isRouteConfirmed && _mapboxMap != null) {
      await _focusCameraOnPosition(position, animated: false);
    }

    if (!_isRouteConfirmed || _fullRouteCoordinates.length < 2) {
      setState(() {});
      return;
    }

    final nearestMatch = _findNearestRoutePointInWindow(
      position,
      _fullRouteCoordinates,
    );

    if (nearestMatch.index > _currentRouteIndex &&
        nearestMatch.distanceMeters <= _maxRouteIndexJumpDistanceMeters) {
      _currentRouteIndex = nearestMatch.index;
      _remainingRouteCoordinates = _fullRouteCoordinates.sublist(
        _currentRouteIndex,
      );
      final clippedGeometry = {
        'type': 'LineString',
        'coordinates': _remainingRouteCoordinates,
      };

      _routeGeoJson = json.encode(clippedGeometry);
      await _drawRoute(clippedGeometry, animateCamera: false);
    }

    _updateActiveManeuver();
    await _speakUpcomingManeuverIfNeeded(position);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _updateVisibleCursor(geo.Position position) async {
    if (_mapboxMap == null) {
      return;
    }

    _cursorAnnotationManager ??= await _mapboxMap!.annotations
        .createPolylineAnnotationManager();

    final centerLng = position.longitude;
    final centerLat = position.latitude;

    final halfSize = 0.00007;
    final verticalLine = [
      Position(centerLng, centerLat - halfSize),
      Position(centerLng, centerLat + halfSize),
    ];
    final horizontalScale = math.cos(centerLat * math.pi / 180).abs();
    final lonSize = horizontalScale < 0.2
        ? halfSize
        : halfSize / horizontalScale;
    final horizontalLine = [
      Position(centerLng - lonSize, centerLat),
      Position(centerLng + lonSize, centerLat),
    ];

    final heading = position.heading.isFinite ? position.heading : 0.0;
    final headingRad = heading * math.pi / 180;
    final headingLength = halfSize * 2.5;
    final tipLat = centerLat + math.cos(headingRad) * headingLength;
    final tipLng =
        centerLng +
        math.sin(headingRad) *
            (headingLength / horizontalScale.clamp(0.2, 1.0));
    final headingLine = [
      Position(centerLng, centerLat),
      Position(tipLng, tipLat),
    ];

    Future<void> drawCursor() async {
      await _cursorAnnotationManager!.deleteAll();
      await _cursorAnnotationManager!.create(
        PolylineAnnotationOptions(
          geometry: LineString(coordinates: verticalLine),
          lineColor: Colors.white.toARGB32(),
          lineWidth: 4.0,
        ),
      );
      await _cursorAnnotationManager!.create(
        PolylineAnnotationOptions(
          geometry: LineString(coordinates: horizontalLine),
          lineColor: Colors.white.toARGB32(),
          lineWidth: 4.0,
        ),
      );
      await _cursorAnnotationManager!.create(
        PolylineAnnotationOptions(
          geometry: LineString(coordinates: headingLine),
          lineColor: const Color(0xFFFF3B30).toARGB32(),
          lineWidth: 4.5,
        ),
      );
    }

    try {
      await drawCursor();
    } catch (_) {
      // Channel stale – recreate manager and retry once.
      _cursorAnnotationManager = await _mapboxMap!.annotations
          .createPolylineAnnotationManager();
      await drawCursor();
    }
  }

  Future<void> _focusCameraOnPosition(
    geo.Position position, {
    required bool animated,
  }) async {
    if (_mapboxMap == null) {
      return;
    }

    final cameraOptions = CameraOptions(
      center: Point(
        coordinates: Position(position.longitude, position.latitude),
      ),
      zoom: 16.0,
      pitch: 45.0,
      bearing: position.heading.isFinite ? position.heading : 0.0,
    );

    if (animated) {
      await _mapboxMap!.flyTo(
        cameraOptions,
        MapAnimationOptions(duration: 700),
      );
      return;
    }

    await _mapboxMap!.setCamera(cameraOptions);
  }

  _RouteWindowMatch _findNearestRoutePointInWindow(
    geo.Position position,
    List<List<double>> coordinates,
  ) {
    if (coordinates.isEmpty) {
      return const _RouteWindowMatch(index: 0, distanceMeters: double.infinity);
    }

    final startIndex = _currentRouteIndex.clamp(0, coordinates.length - 1);
    final endIndex = math.min(
      startIndex + _routeSearchWindowSize,
      coordinates.length - 1,
    );

    var nearestIndex = startIndex;
    var nearestDistance = double.infinity;

    for (var index = startIndex; index <= endIndex; index++) {
      final coordinate = coordinates[index];
      if (coordinate.length < 2) {
        continue;
      }

      final distance = geo.Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        coordinate[1],
        coordinate[0],
      );

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }

    return _RouteWindowMatch(
      index: nearestIndex,
      distanceMeters: nearestDistance,
    );
  }

  void _updateActiveManeuver() {
    if (_maneuvers.isEmpty) {
      return;
    }

    for (var index = _activeManeuverIndex; index < _maneuvers.length; index++) {
      if (_maneuvers[index].routeIndex >= _currentRouteIndex) {
        _activeManeuverIndex = index;
        return;
      }
    }

    _activeManeuverIndex = _maneuvers.length - 1;
  }

  Future<void> _speakUpcomingManeuverIfNeeded(geo.Position position) async {
    // TTS deaktiviert - keine Audio-Ausgabe
    return;
    
    /* Ursprünglicher Code:
    if (!_ttsAvailable ||
        _maneuvers.isEmpty ||
        _activeManeuverIndex >= _maneuvers.length) {
      return;
    }

    final maneuver = _maneuvers[_activeManeuverIndex];
    final distance = geo.Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      maneuver.latitude,
      maneuver.longitude,
    );

    if (distance <= 150 &&
        !_announcedManeuverIndices.contains(_activeManeuverIndex)) {
      try {
        _announcedManeuverIndices.add(_activeManeuverIndex);
        await _flutterTts.stop();
        await _flutterTts.speak(maneuver.announcement);
      } on MissingPluginException {
        _ttsAvailable = false;
      } on PlatformException {
        _ttsAvailable = false;
      }
    }
  }

  Widget _buildManeuverIndicator() {
    final maneuver = _activeManeuverIndex < _maneuvers.length
        ? _maneuvers[_activeManeuverIndex]
        : null;

    if (maneuver == null) {
      return const SizedBox.shrink();
    }

    final position = _userLocation;
    final distanceMeters = position == null
        ? null
        : geo.Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            maneuver.latitude,
            maneuver.longitude,
          );

    final distanceText = distanceMeters == null
        ? '--'
        : distanceMeters >= 1000.0
        ? '${(distanceMeters / 1000.0).toStringAsFixed(1).replaceAll('.', ',')} km'
        : '${distanceMeters.clamp(0, 999).round()} m';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF2D3138).withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(maneuver.icon, color: Colors.white, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  distanceText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  maneuver.instruction,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

    await _mapboxMap!.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        puckBearingEnabled: true,
        puckBearing: PuckBearing.HEADING,
      ),
    );

    await _mapboxMap!.setCamera(
      CameraOptions(
        center: Point(
          coordinates: Position(position.longitude, position.latitude),
        ),
        zoom: 16.0,
        pitch: 45.0,
        bearing: position.heading.isFinite ? position.heading : 0.0,
      ),
    );

    if (mounted) {
      setState(() {
        _viewportState = const FollowPuckViewportState(
          zoom: 16.0,
          pitch: 45.0,
          bearing: FollowPuckViewportStateBearingHeading(),
        );
      });
    }
  }

  String _formatDuration(double? durationSeconds) {
    if (durationSeconds == null || durationSeconds <= 0) {
      return '--';
    }

    final totalMinutes = (durationSeconds / 60).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (hours <= 0) {
      return '$minutes Min.';
    }

    return '$hours Std. ${minutes.toString().padLeft(2, '0')} Min.';
  }

  String _formatDistanceKm(double? rawDistance) {
    if (rawDistance == null || rawDistance <= 0) {
      return '-- km';
    }

    final km = rawDistance > 1000 ? rawDistance / 1000 : rawDistance;
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  // === MAPBOX GEOCODING & AUTOCOMPLETE ===
  
  static const String _mapboxToken =
      'pk.eyJ1IjoibHVjd3F6IiwiYSI6ImNtbHdnMXFpdjBjZTAzZXF3NDgyYmZ3c2oifQ.upeLKXUnY5z6Pe0JiuznEQ';

  /// Autocomplete-Adresssuche - gibt Vorschläge zurück
  Future<List<MapboxSuggestion>> _searchAddressSuggestions(String query) async {
    if (query.length < 3) return [];
    
    final url =
        'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json?'
        'access_token=$_mapboxToken&autocomplete=true&limit=5&language=de&country=de,at,ch';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List? ?? [];
        
        return features.map((f) => MapboxSuggestion(
          placeName: f['place_name'] as String,
          coordinates: [
            (f['center'][0] as num).toDouble(),
            (f['center'][1] as num).toDouble(),
          ],
          context: f['context']?['text'] as String?,
        )).toList();
      }
    } catch (e) {
      debugPrint('Autocomplete Fehler: $e');
    }
    return [];
  }

  Future<Map<String, double>?> _getCoordinatesFromAddress(
    String address,
  ) async {
    final url =
        'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(address)}.json?access_token=$_mapboxToken&limit=1';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          final coords = data['features'][0]['center'];
          return {
            'longitude': (coords[0] as num).toDouble(),
            'latitude': (coords[1] as num).toDouble(),
          };
        }
      }
    } catch (e) {
      debugPrint('Geocoding Fehler: $e');
    }
    return null;
  }

  Future<void> _generateRoute() async {
    setState(() => _isLoading = true);

    try {
      final startCoords = await _getStartCoordinates();
      final routeType = _isRoundTrip ? 'ROUND_TRIP' : 'POINT_TO_POINT';

      int distance = 50;
      if (_selectedLength.contains('+')) {
        distance = 150;
      } else {
        final digits = _selectedLength.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.isNotEmpty) {
          distance = int.parse(digits);
        }
      }

      Map<String, double>? targetLocationMap;
      if (!_isRoundTrip && _destinationController.text.isNotEmpty) {
        targetLocationMap = await _getCoordinatesFromAddress(
          _destinationController.text,
        );
        if (targetLocationMap == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Konnte Zieladresse nicht finden. Bitte prüfen.'),
            ),
          );
          setState(() => _isLoading = false);
          return;
        }
      }

      final body = {
        'startLocation': {
          'latitude': startCoords.latitude,
          'longitude': startCoords.longitude,
        },
        'targetDistance': distance,
        'mode': _selectedStyle,
        'route_type': routeType,
        'planning_type': _planningType,
        if (targetLocationMap != null) 'targetLocation': targetLocationMap,
      };

      final response = await Supabase.instance.client.functions.invoke(
        'generate-cruise-route',
        body: body,
      );

      final data = response.data;
      if (data == null || data['error'] != null) {
        throw Exception(
          data?['error'] ?? 'Unbekannter Fehler bei der Berechnung.',
        );
      }

      final geometry = Map<String, dynamic>.from(data['route']['geometry']);
      final parsedCoordinates = _extractCoordinatesFromGeometry(geometry);
      final allManeuvers = _extractManeuvers(data, parsedCoordinates);

      // Filter U-turn and arrive maneuvers – round trips end back at start,
      // so no explicit destination announcement is needed.
      final activeManeuvers = allManeuvers
          .where((m) => m.icon != Icons.u_turn_left)
          .toList();

      setState(() {
        _routeGeoJson = json.encode(geometry);
        _routeDistance = (data['route']['distance'] as num?)?.toDouble();
        _routeDuration = (data['route']['duration'] as num?)?.toDouble();
        _isRouteConfirmed = false;
        _viewportState = null;
        _fullRouteCoordinates = parsedCoordinates;
        _remainingRouteCoordinates = parsedCoordinates;
        _maneuvers = activeManeuvers;
        _activeManeuverIndex = 0;
        _currentRouteIndex = 0;
        _announcedManeuverIndices.clear();
      });

      await _drawRoute(geometry);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Route berechnet! (${data['meta']['distance_km']} km)',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<geo.Position> _getStartCoordinates() async {
    if (_selectedLocation == 'Aktueller Standort') {
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Standortdienste sind deaktiviert.');
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

      return await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
    }

    return geo.Position(
      longitude: 13.404954,
      latitude: 52.520008,
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

  List<List<double>> _extractCoordinatesFromGeometry(
    Map<String, dynamic> geometry,
  ) {
    final coordinatesRaw = (geometry['coordinates'] as List?) ?? const [];
    return coordinatesRaw
        .whereType<List>()
        .where((coordinate) => coordinate.length >= 2)
        .map(
          (coordinate) => [
            (coordinate[0] as num).toDouble(),
            (coordinate[1] as num).toDouble(),
          ],
        )
        .toList();
  }

  List<_RouteManeuver> _extractManeuvers(
    dynamic responseData,
    List<List<double>> routeCoordinates,
  ) {
    final route = responseData is Map ? responseData['route'] : null;
    final legs = route is Map ? route['legs'] as List? : null;
    if (legs == null || legs.isEmpty || routeCoordinates.length < 2) {
      return const [];
    }

    final maneuvers = <_RouteManeuver>[];

    for (final leg in legs) {
      if (leg is! Map) continue;
      final steps = leg['steps'] as List?;
      if (steps == null) continue;

      for (final step in steps) {
        if (step is! Map) continue;

        final maneuver = step['maneuver'];
        if (maneuver is! Map) continue;

        // Skip arrive steps – they produce "Your destination is on the right"
        // which is wrong for round trips that return to the start.
        final maneuverType = (maneuver['type'] as String?) ?? '';
        if (maneuverType == 'arrive') continue;

        final location = maneuver['location'];
        if (location is! List || location.length < 2) continue;

        final longitude = (location[0] as num).toDouble();
        final latitude = (location[1] as num).toDouble();
        final modifier = (maneuver['modifier'] as String?) ?? '';
        final rawInstruction =
            (maneuver['instruction'] as String?) ??
            (step['name'] as String?) ??
            _announcementForModifier(modifier);

        final routeIndex = _findNearestRoutePointIndexByLatLng(
          latitude,
          longitude,
          routeCoordinates,
        );

        maneuvers.add(
          _RouteManeuver(
            latitude: latitude,
            longitude: longitude,
            routeIndex: routeIndex,
            icon: _iconForModifier(modifier),
            announcement: _announcementFromInstruction(
              rawInstruction,
              modifier,
            ),
            instruction: _normalizeInstruction(rawInstruction, modifier),
          ),
        );
      }
    }

    maneuvers.sort((a, b) => a.routeIndex.compareTo(b.routeIndex));
    return maneuvers;
  }

  int _findNearestRoutePointIndexByLatLng(
    double latitude,
    double longitude,
    List<List<double>> coordinates,
  ) {
    var nearestIndex = 0;
    var nearestDistance = double.infinity;

    for (var index = 0; index < coordinates.length; index++) {
      final coordinate = coordinates[index];
      if (coordinate.length < 2) {
        continue;
      }

      final distance = geo.Geolocator.distanceBetween(
        latitude,
        longitude,
        coordinate[1],
        coordinate[0],
      );

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }

    return nearestIndex;
  }

  IconData _iconForModifier(String modifier) {
    switch (modifier.toLowerCase()) {
      case 'left':
      case 'slight left':
      case 'sharp left':
        return Icons.turn_left;
      case 'right':
      case 'slight right':
      case 'sharp right':
        return Icons.turn_right;
      case 'uturn':
      case 'uturn left':
      case 'uturn right':
        return Icons.u_turn_left;
      case 'straight':
      default:
        return Icons.straight;
    }
  }

  String _announcementForModifier(String modifier) {
    switch (modifier.toLowerCase()) {
      case 'left':
      case 'slight left':
      case 'sharp left':
        return 'In 100 Metern links abbiegen';
      case 'right':
      case 'slight right':
      case 'sharp right':
        return 'In 100 Metern rechts abbiegen';
      case 'uturn':
      case 'uturn left':
      case 'uturn right':
        return 'In 100 Metern bitte wenden';
      case 'straight':
      default:
        return 'In 100 Metern geradeaus weiterfahren';
    }
  }

  String _normalizeInstruction(String instruction, String modifier) {
    final trimmedInstruction = instruction.trim();
    if (trimmedInstruction.isEmpty) {
      return _announcementForModifier(modifier);
    }
    return trimmedInstruction;
  }

  String _announcementFromInstruction(String instruction, String modifier) {
    final normalized = _normalizeInstruction(instruction, modifier);
    return 'In 150 Metern $normalized';
  }

  Widget _buildLargeModeButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 100,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1C1F26) : const Color(0xFF0B0E14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? const Color(0xFFFF3B30) : Colors.white12,
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF3B30).withOpacity(0.3),
                    blurRadius: 15,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive ? const Color(0xFFFF3B30) : Colors.white38,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white54,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoundTripOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          'Planungs-Typ',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildChoiceButton(
                label: 'Zufall',
                isSelected: _planningType == 'Zufall',
                onTap: () => setState(() => _planningType = 'Zufall'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildChoiceButton(
                label: 'Wegpunkte',
                isSelected: _planningType == 'Wegpunkte',
                onTap: () => setState(() => _planningType = 'Wegpunkte'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChoiceButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF3B30).withOpacity(0.15)
              : const Color(0xFF0B0E14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF3B30) : Colors.transparent,
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFF3B30) : Colors.white60,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildAtoBOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Zielort',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0B0E14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: Colors.white38),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _destinationController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Adresse suchen...',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.map_outlined, color: Colors.white70),
                onPressed: () {},
                tooltip: 'Auf Karte wählen',
              ),
            ],
          ),
        ),
      ],
    );
  }

  
  // === Wegpunkt-Typ für Haltestop vs normaler Wegpunkt ===
  void _showWaypointTypeDialog(List<double> coordinates, Function(WaypointType) onSelect) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text('Wegpunkt-Typ', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.location_on, color: Color(0xFFFF3B30)),
              title: const Text('Wegpunkt', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Einfache Durchfahrt', style: TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                onSelect(WaypointType.normal);
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_parking, color: Colors.orange),
              title: const Text('Haltestop', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Route pausiert hier', style: TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                onSelect(WaypointType.stop);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionRow(
    String title,
    List<String> options,
    String selectedValue,
    Function(String) onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: options.map((option) {
            final isSelected = option == selectedValue;
            return GestureDetector(
              onTap: () => onSelect(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFFF3B30)
                      : const Color(0xFF0B0E14),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFF3B30).withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Text(
                  option,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[400],
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
