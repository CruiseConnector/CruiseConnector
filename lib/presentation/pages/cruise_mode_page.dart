import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
// TTS deaktiviert:
// import 'package:flutter/services.dart';
// import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'package:cruise_connect/data/services/geocoding_service.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/mapbox_suggestion.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart' show RouteManeuver;
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_maneuver_indicator.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_navigation_info_panel.dart';

class CruiseModePage extends StatefulWidget {
  const CruiseModePage({super.key});

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

  // ─────────────────────── Route Result State ────────────────────────────────
  bool _isRouteConfirmed = false;
  String? _routeGeoJson;
  double? _routeDistance;
  double? _routeDuration;

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

  // TTS deaktiviert - zu viele Audio-Probleme
  // final FlutterTts _flutterTts = FlutterTts();
  // bool _ttsAvailable = false;

  // ──────────────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _stopSimulation(restartLiveTracking: false);
    _positionSubscription?.cancel();
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
              left: 12,
              right: 12,
              child: CruiseManeuverIndicator(
                maneuver: _maneuvers[_activeManeuverIndex.clamp(0, _maneuvers.length - 1)],
                userPosition: _userLocation,
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: CruiseNavigationInfoPanel(
              durationSeconds: _routeDuration,
              distanceMeters: _routeDistance,
            ),
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
          if (_fullRouteCoordinates.length > 1)
            Positioned(
              right: 16,
              bottom: 170,
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
          onStyleLoadedListener: (_) {
            if (!mounted) return;
            setState(() {
              _isMapStyleLoaded = true;
              _mapLoadError = null;
            });
          },
          onMapLoadErrorListener: (event) {
            if (!mounted) return;
            setState(() => _mapLoadError = event.message);
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

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _greyAnnotationManager = null;
    _polylineAnnotationManager = null;
    _cursorAnnotationManager = null;
    if (mounted) setState(() => _isMapStyleLoaded = false);

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
      if (mounted) {
        setState(() => _mapLoadError = 'Karte konnte nicht initialisiert werden.');
      }
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

  // ═══════════════════════ SETUP CARD ═══════════════════════════════════════

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
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          const Text(
            'Routen-Modus',
            style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
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
            crossFadeState: _isRoundTrip ? CrossFadeState.showFirst : CrossFadeState.showSecond,
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
            _buildDistanceInfoBox(),
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

  Widget _buildDistanceInfoBox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Länge',
          style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.grey, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Distanz wird automatisch basierend auf dem Zielort berechnet.',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
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
      debugPrint('Initialisiere Karten-Standort...');
      
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Standortdienste deaktiviert - Karte zeigt Standard-Position');
        return;
      }

      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
        if (permission == geo.LocationPermission.denied) {
          debugPrint('Standortberechtigung verweigert');
          return;
        }
      }
      if (permission == geo.LocationPermission.deniedForever) {
        debugPrint('Standortberechtigung dauerhaft verweigert');
        return;
      }
      
      // Versuche letzte bekannte Position zuerst
      geo.Position? position = await geo.Geolocator.getLastKnownPosition();
      if (position == null) {
        // Dann aktuelle Position mit Timeout
        position = await geo.Geolocator.getCurrentPosition(
          locationSettings: const geo.LocationSettings(accuracy: geo.LocationAccuracy.high),
        ).timeout(const Duration(seconds: 10), onTimeout: () {
          debugPrint('Timeout beim Abrufen der Position');
          throw Exception('Timeout');
        });
      }
      
      _userLocation = position;
      debugPrint('Standort gefunden: ${position.latitude}, ${position.longitude}');

      await _mapboxMap?.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          puckBearingEnabled: true,
          puckBearing: PuckBearing.HEADING,
        ),
      );
      _mapboxMap?.setCamera(
        CameraOptions(
          center: Point(coordinates: Position(position.longitude, position.latitude)),
          zoom: 13.0,
          padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
        ),
      );
      debugPrint('Karte auf aktuellen Standort zentriert');
    } catch (e) {
      debugPrint('Konnte Karten-Position nicht setzen: $e');
    }
  }

  Future<geo.Position> _getStartCoordinates() async {
    if (_selectedLocation == 'Aktueller Standort') {
      // Prüfe GPS-Dienste
      bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Bitte aktiviere GPS/Standort in deinen Geräteeinstellungen und versuche es erneut.');
      }

      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
        if (permission == geo.LocationPermission.denied) {
          throw Exception('Standortberechtigung verweigert. Bitte erlaube den Zugriff in den Einstellungen.');
        }
      }
      if (permission == geo.LocationPermission.deniedForever) {
        throw Exception('Standortberechtigung dauerhaft verweigert. Bitte in den App-Einstellungen aktivieren.');
      }
      
      try {
        // Versuche zuerst die letzte bekannte Position (schneller)
        geo.Position? lastPosition = await geo.Geolocator.getLastKnownPosition();
        if (lastPosition != null) {
          debugPrint('Verwende letzte bekannte Position: ${lastPosition.latitude}, ${lastPosition.longitude}');
          return lastPosition;
        }
        
        // Warte auf aktuelle Position mit Timeout
        debugPrint('Frage aktuelle Position ab...');
        return await geo.Geolocator.getCurrentPosition(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.best,
          ),
        ).timeout(const Duration(seconds: 15), onTimeout: () {
          throw Exception('Standort konnte nicht ermittelt werden. Bitte prüfe deine GPS-Verbindung.');
        });
      } catch (e) {
        debugPrint('Fehler beim Abrufen der Position: $e');
        rethrow;
      }
    }
    // Fallback: Berlin
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
            content: Text(
              'Route berechnet! (${result.distanceKm?.toStringAsFixed(1) ?? '--'} km)',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _calculateRouteToDestination(
    MapboxSuggestion suggestion, {
    required bool scenic,
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
            content: Text(
              '${scenic ? "Coole" : "Direkte"} Route berechnet! (${result.distanceKm?.toStringAsFixed(1) ?? '--'} km)',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyRouteResult(RouteResult result) {
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

  Future<void> _confirmRoute() async {
    setState(() => _isRouteConfirmed = true);
    _startNavigationTracking();
    if (_fullRouteCoordinates.length >= 2) {
      await _drawRoute(
        {'type': 'LineString', 'coordinates': _remainingRouteCoordinates},
        animateCamera: false,
      );
    }
    await _activateNavigationCamera();
  }

  // ═══════════════════════ DRAW ROUTE ═══════════════════════════════════════

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

    // Graue Vollroute (nur bei bestätigter Route)
    if (_isRouteConfirmed && _fullRouteCoordinates.length >= 2) {
      final fullPositions = _fullRouteCoordinates.map((c) => Position(c[0], c[1])).toList();
      try {
        _greyAnnotationManager ??=
            await _mapboxMap!.annotations.createPolylineAnnotationManager();
        await _greyAnnotationManager!.deleteAll();
        await _greyAnnotationManager!.create(PolylineAnnotationOptions(
          geometry: LineString(coordinates: fullPositions),
          lineColor: const Color(0xFF6B7280).toARGB32(),
          lineWidth: 5.0,
        ));
      } catch (_) {
        _greyAnnotationManager =
            await _mapboxMap!.annotations.createPolylineAnnotationManager();
        await _greyAnnotationManager!.create(PolylineAnnotationOptions(
          geometry: LineString(coordinates: fullPositions),
          lineColor: const Color(0xFF6B7280).toARGB32(),
          lineWidth: 5.0,
        ));
      }
    }

    // Rote aktive Route
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
        null,
        null,
      );
      await Future.delayed(const Duration(milliseconds: 100));
      await _mapboxMap!.flyTo(previewCamera, MapAnimationOptions(duration: 2500));
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
    if (!mounted) return;
    _userLocation = position;
    await _updateVisibleCursor(position);

    if (_isRouteConfirmed && _mapboxMap != null) {
      await _focusCameraOnPosition(position, animated: false);
    }

    if (!_isRouteConfirmed || _fullRouteCoordinates.length < 2) {
      setState(() {});
      return;
    }

    final match = findNearestInWindow(
      position: position,
      coordinates: _fullRouteCoordinates,
      currentIndex: _currentRouteIndex,
    );

    if (match.index > _currentRouteIndex && match.distanceMeters <= 45.0) {
      _currentRouteIndex = match.index;
      _remainingRouteCoordinates = _fullRouteCoordinates.sublist(_currentRouteIndex);
      final clipped = {'type': 'LineString', 'coordinates': _remainingRouteCoordinates};
      _routeGeoJson = json.encode(clipped);
      await _drawRoute(clipped, animateCamera: false);
    }

    _updateActiveManeuver();
    // TTS deaktiviert:
    // await _speakUpcomingManeuverIfNeeded(position);

    if (mounted) setState(() {});
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

  // TTS deaktiviert - bei Reaktivierung hier einkommentieren:
  // Future<void> _speakUpcomingManeuverIfNeeded(geo.Position position) async {
  //   if (!_ttsAvailable || _maneuvers.isEmpty) return;
  //   final maneuver = _maneuvers[_activeManeuverIndex];
  //   final distance = geo.Geolocator.distanceBetween(
  //     position.latitude, position.longitude,
  //     maneuver.latitude, maneuver.longitude,
  //   );
  //   if (distance <= 150 && !_announcedManeuverIndices.contains(_activeManeuverIndex)) {
  //     _announcedManeuverIndices.add(_activeManeuverIndex);
  //     await _flutterTts.stop();
  //     await _flutterTts.speak(maneuver.announcement);
  //   }
  // }

  // ═══════════════════════ CAMERA ═══════════════════════════════════════════

  Future<void> _recenterMap() async {
    final map = _mapboxMap;
    final position = _userLocation;
    if (map == null || position == null) return;
    await map.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(position.longitude, position.latitude)),
        zoom: 16.0,
        pitch: 45.0,
        bearing: position.heading.isFinite ? position.heading : 0.0,
      ),
      MapAnimationOptions(duration: 900),
    );
  }

  Future<void> _focusCameraOnPosition(
    geo.Position position, {
    required bool animated,
  }) async {
    if (_mapboxMap == null) return;
    final options = CameraOptions(
      center: Point(coordinates: Position(position.longitude, position.latitude)),
      zoom: 16.0,
      pitch: 45.0,
      bearing: position.heading.isFinite ? position.heading : 0.0,
    );
    if (animated) {
      await _mapboxMap!.flyTo(options, MapAnimationOptions(duration: 700));
    } else {
      await _mapboxMap!.setCamera(options);
    }
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
        center: Point(coordinates: Position(position.longitude, position.latitude)),
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
        lineColor: Colors.white.toARGB32(),
        lineWidth: 4.0,
      ));
      await _cursorAnnotationManager!.create(PolylineAnnotationOptions(
        geometry: LineString(coordinates: horizontalLine),
        lineColor: Colors.white.toARGB32(),
        lineWidth: 4.0,
      ));
      await _cursorAnnotationManager!.create(PolylineAnnotationOptions(
        geometry: LineString(coordinates: headingLine),
        lineColor: const Color(0xFFFF3B30).toARGB32(),
        lineWidth: 4.5,
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
      return;
    }
    await _startSimulation();
  }

  Future<void> _startSimulation() async {
    if (_fullRouteCoordinates.length < 2) return;
    _stopNavigationTracking();
    _simulationIndex = 0;
    _currentRouteIndex = 0;
    _remainingRouteCoordinates = List.from(_fullRouteCoordinates);
    _announcedManeuverIndices.clear();
    _activeManeuverIndex = 0;
    _isSimulationRunning = true;

    final fullGeometry = {'type': 'LineString', 'coordinates': _remainingRouteCoordinates};
    _routeGeoJson = json.encode(fullGeometry);
    await _drawRoute(fullGeometry, animateCamera: false);

    final first = _fullRouteCoordinates.first;
    final second = _fullRouteCoordinates[1];
    await _focusCameraOnPosition(_buildSimulatedPosition(first, second), animated: true);
    if (mounted) setState(() {});

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
    if (restartLiveTracking && _isRouteConfirmed) _startNavigationTracking();
    if (wasRunning && mounted) setState(() {});
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
        _stopSimulation();
        return;
      }
      _simulationIndex = math.min(_simulationIndex + 1, lastIndex);
      final current = _fullRouteCoordinates[_simulationIndex];
      final next = _fullRouteCoordinates[math.min(_simulationIndex + 1, lastIndex)];
      await _onLocationUpdate(_buildSimulatedPosition(current, next));
      if (_simulationIndex >= lastIndex) _stopSimulation();
    } finally {
      _isSimulationStepRunning = false;
    }
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
      speed: 13.5,
      speedAccuracy: 1,
      altitudeAccuracy: 0,
      headingAccuracy: 5,
    );
  }

  // ═══════════════════════ DIALOGS ══════════════════════════════════════════

  void _showRouteTypeDialog(MapboxSuggestion suggestion) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text('Routen-Typ wählen', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ziel: ${suggestion.placeName}',
              style: const TextStyle(color: Colors.grey, fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.arrow_forward, color: Color(0xFFFF3B30)),
              title: const Text('Direkte Route', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Schnellster Weg zum Ziel',
                  style: TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                _calculateRouteToDestination(suggestion, scenic: false);
              },
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.route, color: Colors.orange),
              title: const Text('Coole Route', style: TextStyle(color: Colors.white)),
              subtitle: Text('Mit $_selectedStyle zum Ziel',
                  style: const TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                _calculateRouteToDestination(suggestion, scenic: true);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _openMapForWaypointSelection() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Karten-Auswahl kommt im nächsten Update'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Fehler: $message'), backgroundColor: Colors.red),
    );
  }

  // ═══════════════════════ UI HELPER WIDGETS ════════════════════════════════

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
                    color: const Color(0xFFFF3B30).withValues(alpha: 0.3),
                    blurRadius: 15,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isActive ? const Color(0xFFFF3B30) : Colors.white38, size: 32),
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
          style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
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
              ? const Color(0xFFFF3B30).withValues(alpha: 0.15)
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
          style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0B0E14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: TypeAheadField<MapboxSuggestion>(
            controller: _destinationController,
            suggestionsCallback: (pattern) async {
              if (pattern.isEmpty) return const [];
              return _geocodingService.searchSuggestions(pattern);
            },
            builder: (context, controller, focusNode) => TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.map_outlined, color: Colors.white70),
                  onPressed: _openMapForWaypointSelection,
                  tooltip: 'Auf Karte wählen',
                ),
                hintText: 'Adresse suchen...',
                hintStyle: const TextStyle(color: Colors.white38),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            itemBuilder: (context, suggestion) => ListTile(
              tileColor: const Color(0xFF1C1F26),
              leading: const Icon(Icons.location_on, color: Color(0xFFFF3B30)),
              title: Text(suggestion.placeName,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: suggestion.context != null
                  ? Text(suggestion.context!,
                      style: const TextStyle(color: Colors.grey, fontSize: 12))
                  : null,
            ),
            onSelected: (suggestion) {
              _destinationController.text = suggestion.placeName;
              _showRouteTypeDialog(suggestion);
            },
            emptyBuilder: (context) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Adresse eingeben...', style: TextStyle(color: Colors.grey)),
            ),
            loadingBuilder: (context) => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30))),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionRow(
    String title,
    List<String> options,
    String selectedValue,
    void Function(String) onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
              color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFF3B30) : const Color(0xFF0B0E14),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFF3B30).withValues(alpha: 0.4),
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
