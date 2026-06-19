import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:latlong2/latlong.dart';

import '../../core/input_limits.dart';
import '../../data/services/cruise_group_service.dart';
import '../../data/services/gamification_service.dart';
import '../../data/services/geocoding_service.dart';
import '../../data/services/group_route_data_builder.dart';
import '../../data/services/route_service.dart';
import '../../domain/models/place_suggestion.dart';
import '../../domain/models/route_result.dart';
import '../widgets/badge_unlock_popup.dart';
import '../widgets/cruise/cruise_maplibre_map.dart';
import '../widgets/cruise/cruise_setup_card.dart';
import '../widgets/group_safety_notice_sheet.dart';
import 'group_lobby_page.dart';

/// Gruppenerstellung mit Live-Map: Startpunkt wählen (GPS / Karte / Adresse),
/// Route generieren, dann als Gruppe in Supabase speichern.
class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key, this.disableMapTilesForTesting = false});

  final bool disableMapTilesForTesting;

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  // ignore: prefer_const_constructors
  final _routeService = RouteService();
  final _geocodingService = const GeocodingService();
  CruiseMapLibreController? _mapController;

  // Form
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _destinationCtrl = TextEditingController();

  double _maxPeople = 10;
  String _selectedLength = '50 Km';
  String _selectedLocation = 'Aktueller Standort';
  String _selectedStyle = 'Sport Mode';
  String _planningType = 'Zufall';
  String _selectedDetour = 'Direkt';
  String _selectedVisibility = 'Öffentlich (Für jeden)';
  DateTime? _selectedDateTime;
  bool _isRoundTrip = true;
  bool _avoidHighways = false;
  PlaceSuggestion? _selectedDestination;

  // Map-State
  LatLng? _startPoint;
  final List<LatLng> _roundTripWaypoints = [];
  List<LatLng> _routeLatLngs = [];
  RouteResult? _lastRoute;
  int? _selectedWaypointIndex;
  int? _replaceWaypointIndex;
  String _waypointOrigin = 'manual';
  int _waypointSeedAttempt = 0;
  int _waypointSeedCounter = 0;
  int _routeGenerationSerial = 0;
  bool _lastGeneratedWasRoundTrip = true;
  String? _lastGeneratedPlanningType;
  String? _lastGeneratedStyle;
  int? _lastGeneratedTargetKm;
  bool? _lastGeneratedAvoidHighways;
  String? _lastGeneratedWaypointSignature;
  String? _lastGeneratedDestinationSignature;
  String _routeStatusText = 'Bereit';

  bool _isGenerating = false;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _tryLocateUser();
    if (widget.disableMapTilesForTesting) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(showGroupSafetyNoticeSheet(context));
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    _destinationCtrl.dispose();
    super.dispose();
  }

  // ── Location helpers ──────────────────────────────────────────────────────

  Future<void> _tryLocateUser() async {
    try {
      final pos = await _getCurrentPosition();
      if (!mounted) return;
      setState(() => _startPoint = LatLng(pos.latitude, pos.longitude));
      _moveMapTo(_startPoint!, zoom: 12);
    } catch (_) {
      // Permission verweigert — User kann per Karte wählen.
    }
  }

  Future<geo.Position> _getCurrentPosition() async {
    final enabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!enabled) throw Exception('Standort ist deaktiviert.');
    var perm = await geo.Geolocator.checkPermission();
    if (perm == geo.LocationPermission.denied) {
      perm = await geo.Geolocator.requestPermission();
    }
    if (perm == geo.LocationPermission.denied ||
        perm == geo.LocationPermission.deniedForever) {
      throw Exception('Standort-Berechtigung fehlt.');
    }
    return geo.Geolocator.getCurrentPosition(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _geocodeAddress() async {
    if (_addressCtrl.text.trim().isEmpty) return;
    final res = await _geocodingService.getCoordinatesFromAddress(
      _addressCtrl.text.trim(),
    );
    if (res == null) {
      _showError('Adresse nicht gefunden.');
      return;
    }
    setState(() {
      _startPoint = LatLng(res['latitude']!, res['longitude']!);
    });
    _moveMapTo(_startPoint!, zoom: 12);
  }

  Future<void> _generateRoute() async {
    if (_isGenerating) return;
    final generationId = ++_routeGenerationSerial;
    setState(() {
      _isGenerating = true;
      _routeStatusText = 'Route wird berechnet';
    });
    try {
      final startPosition = await _getStartCoordinates();
      if (!_isCurrentGeneration(generationId)) return;
      final targetKm = _targetDistanceKm();
      final waypointSnapshot = List<LatLng>.unmodifiable(_roundTripWaypoints);
      final waypointSignature = _isWaypointPlanning
          ? _waypointSignature(waypointSnapshot)
          : null;
      if (_isWaypointPlanning &&
          (waypointSnapshot.isEmpty || waypointSnapshot.length > 5)) {
        _showError(
          waypointSnapshot.isEmpty
              ? 'Setze mindestens einen Stopp oder lass Stopps vorschlagen.'
              : 'Bitte nutze maximal 5 Stopps (Trip-Modus).',
        );
        return;
      }

      final forceFreshVariant = _shouldForceFreshRoute(
        targetKm: targetKm,
        waypointSignature: waypointSignature,
      );

      final result = _isRoundTrip
          ? await _generateRoundTripRoute(
              startPosition: startPosition,
              targetKm: targetKm,
              waypointSnapshot: waypointSnapshot,
              forceFreshVariant: forceFreshVariant,
            )
          : await _generatePointToPointRoute(
              startPosition: startPosition,
              forceFreshVariant: forceFreshVariant,
            );
      if (!_isCurrentGeneration(generationId)) return;
      await _acceptGeneratedRoute(
        result,
        targetKm: targetKm,
        waypointSignature: waypointSignature,
      );
    } catch (e) {
      if (!_isCurrentGeneration(generationId)) return;
      if (e is RouteServiceException && _isSearchInProgressError(e)) {
        final sessionId = e.edgeMeta['search_session_id']?.toString();
        if (sessionId != null && sessionId.isNotEmpty) {
          final polled = await _pollRoundTripSearchSession(
            sessionId,
            generationId: generationId,
          );
          if (!_isCurrentGeneration(generationId)) return;
          if (polled != null) {
            await _acceptGeneratedRoute(
              polled,
              targetKm: _targetDistanceKm(),
              waypointSignature: _isWaypointPlanning
                  ? _waypointSignature(_roundTripWaypoints)
                  : null,
            );
            return;
          }
          _showError(
            'Wir prüfen weitere Routenvorschläge im Hintergrund. Bitte versuche es gleich erneut.',
          );
          return;
        }
      }
      final message = e is RouteServiceException
          ? e.userMessage
          : 'Route konnte nicht generiert werden. Bitte versuche es erneut.';
      _showError(message);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<RouteResult> _generateRoundTripRoute({
    required geo.Position startPosition,
    required int targetKm,
    required List<LatLng> waypointSnapshot,
    required bool forceFreshVariant,
  }) {
    final effectiveTargetKm = _isWaypointPlanning
        ? _estimateWaypointRouteTargetKm(
            startPosition: startPosition,
            waypoints: waypointSnapshot,
            fallbackKm: targetKm,
          )
        : targetKm;
    return _routeService.generateRoundTrip(
      startPosition: startPosition,
      targetDistanceKm: effectiveTargetKm,
      mode: _selectedStyle,
      planningType: _planningType,
      waypointOrigin: _isWaypointPlanning ? _waypointOrigin : null,
      waypointSeedAttempt: _isWaypointPlanning ? _waypointSeedAttempt : null,
      userWaypoints: waypointSnapshot
          .map(
            (point) => <String, double>{
              'latitude': point.latitude,
              'longitude': point.longitude,
            },
          )
          .toList(growable: false),
      avoidHighways: _avoidHighways,
      forceFreshVariant: forceFreshVariant,
      debugTrigger: forceFreshVariant ? 'groupSearchAgain' : 'groupFirstSearch',
      subscriptionTier: RouteService.resolveEffectiveSubscriptionTier(
        isTesterOrBeta: true,
      ),
    );
  }

  Future<RouteResult> _generatePointToPointRoute({
    required geo.Position startPosition,
    required bool forceFreshVariant,
  }) async {
    final destination = await _resolveDestination(startPosition);
    if (destination == null) {
      throw const RouteServiceException(
        type: RouteErrorType.validation,
        userMessage: 'Bitte wähle ein Ziel aus.',
        debugMessage: 'Group route generation missing destination.',
      );
    }
    final detourVariant = _detourVariant;
    final scenicMode = detourVariant > 0;
    return _routeService.generatePointToPoint(
      startPosition: startPosition,
      destinationLat: destination.latitude,
      destinationLng: destination.longitude,
      mode: scenicMode ? _selectedStyle : 'Standard',
      scenic: scenicMode,
      routeVariant: detourVariant,
      avoidHighways: _avoidHighways,
      diversitySeed: Object.hash(
        destination.latitude.round(),
        destination.longitude.round(),
        detourVariant,
        _avoidHighways,
        forceFreshVariant,
      ),
      forceFreshVariant: forceFreshVariant,
      subscriptionTier: RouteService.resolveEffectiveSubscriptionTier(
        isTesterOrBeta: true,
      ),
    );
  }

  Future<geo.Position> _getStartCoordinates() async {
    if (_selectedLocation == 'Aktueller Standort' || _startPoint == null) {
      final pos = await _getCurrentPosition();
      if (mounted) {
        setState(() => _startPoint = LatLng(pos.latitude, pos.longitude));
      }
      return pos;
    }
    return _positionFromLatLng(_startPoint!);
  }

  geo.Position _positionFromLatLng(LatLng point) {
    return geo.Position(
      latitude: point.latitude,
      longitude: point.longitude,
      timestamp: DateTime.now(),
      accuracy: 1,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
  }

  Future<PlaceSuggestion?> _resolveDestination(geo.Position start) async {
    final selected = _selectedDestination;
    if (selected != null) return selected;
    final query = _destinationCtrl.text.trim();
    if (query.isEmpty) return null;
    final coordinates = await _geocodingService.getCoordinatesFromAddress(
      query,
      proximityLatitude: start.latitude,
      proximityLongitude: start.longitude,
      requireUnambiguous: true,
    );
    if (coordinates == null) return null;
    final suggestion = PlaceSuggestion(
      placeName: query,
      coordinates: [coordinates['longitude']!, coordinates['latitude']!],
    );
    if (mounted) setState(() => _selectedDestination = suggestion);
    return suggestion;
  }

  Future<void> _acceptGeneratedRoute(
    RouteResult result, {
    required int targetKm,
    required String? waypointSignature,
  }) async {
    final coords = result.coordinates
        .where((c) => c.length >= 2)
        .map((c) => LatLng(c[1], c[0]))
        .toList(growable: false);
    if (coords.length < 2) {
      throw const RouteServiceException(
        type: RouteErrorType.emptyResponse,
        userMessage: 'Die Route enthält zu wenige Punkte.',
        debugMessage: 'Group route result has fewer than 2 coordinates.',
      );
    }
    final deliveredWaypoints =
        _isWaypointPlanning && _waypointOrigin == 'auto_seed'
        ? _deliveredWaypointsFromMeta(result.edgeMeta)
        : const <LatLng>[];
    if (mounted) {
      setState(() {
        _lastRoute = result;
        _routeLatLngs = coords;
        if (deliveredWaypoints.isNotEmpty) {
          _roundTripWaypoints
            ..clear()
            ..addAll(deliveredWaypoints);
          _selectedWaypointIndex = 0;
          _replaceWaypointIndex = null;
        }
        _lastGeneratedWasRoundTrip = _isRoundTrip;
        _lastGeneratedPlanningType = _planningType;
        _lastGeneratedStyle = _selectedStyle;
        _lastGeneratedTargetKm = targetKm;
        _lastGeneratedAvoidHighways = _avoidHighways;
        _lastGeneratedWaypointSignature = deliveredWaypoints.isNotEmpty
            ? _waypointSignature(deliveredWaypoints)
            : waypointSignature;
        _lastGeneratedDestinationSignature = _destinationSignature();
        _routeStatusText = 'Route bereit';
      });
    }
    _fitRouteBounds(coords);
  }

  Future<RouteResult?> _pollRoundTripSearchSession(
    String sessionId, {
    required int generationId,
  }) async {
    DateTime? lastKickAt;
    for (var poll = 0; poll < 30; poll += 1) {
      if (!_isCurrentGeneration(generationId)) return null;
      if (mounted) {
        setState(() => _routeStatusText = 'Wir prüfen Live-Varianten');
      }
      await Future.delayed(const Duration(seconds: 4));
      if (!_isCurrentGeneration(generationId)) return null;
      final result = await _routeService.pollRoundTripSearchSession(sessionId);
      if (result != null) return result;
      final meta = _routeService.lastRoundTripSearchSessionMeta;
      final shouldKick = _shouldKickStaleRoundTripSearchSession(
        meta,
        pollIndex: poll,
      );
      final now = DateTime.now();
      if (shouldKick &&
          (lastKickAt == null ||
              now.difference(lastKickAt) >= const Duration(seconds: 12))) {
        lastKickAt = now;
        unawaited(
          _routeService.kickRoundTripSearchSession(
            sessionId,
            reason: 'group_client_poll_stale',
          ),
        );
      }
    }
    return null;
  }

  bool _shouldKickStaleRoundTripSearchSession(
    Map<String, dynamic>? meta, {
    required int pollIndex,
  }) {
    if (pollIndex < 2 || meta == null) return false;
    final status = meta['search_session_status']?.toString();
    final workerLastSeen = meta['worker_last_seen_at']?.toString().trim();
    final attemptsRaw = meta['attempts_count'];
    final attempts = attemptsRaw is num
        ? attemptsRaw.toInt()
        : int.tryParse(attemptsRaw?.toString() ?? '') ?? 0;
    final waiting =
        status == 'queued' || status == 'running' || status == 'hydrating';
    return waiting &&
        attempts <= 0 &&
        (workerLastSeen == null ||
            workerLastSeen.isEmpty ||
            workerLastSeen == 'null');
  }

  bool _isSearchInProgressError(RouteServiceException error) {
    final code =
        error.edgeMeta['response_code']?.toString() ??
        error.edgeMeta['code']?.toString();
    final status = error.edgeMeta['search_session_status']?.toString();
    return code == 'search_in_progress' ||
        error.edgeMeta['search_in_progress'] == true ||
        status == 'queued' ||
        status == 'running' ||
        status == 'hydrating';
  }

  bool _isCurrentGeneration(int generationId) {
    return mounted && generationId == _routeGenerationSerial;
  }

  void _fitRouteBounds(List<LatLng> coords) {
    if (coords.isEmpty) return;
    unawaited(
      _mapController?.fitBounds(coords, padding: const EdgeInsets.all(40)),
    );
  }

  void _moveMapTo(LatLng point, {required double zoom}) {
    unawaited(
      _mapController?.moveTo(
        lat: point.latitude,
        lng: point.longitude,
        zoom: zoom,
      ),
    );
  }

  int get _detourVariant => switch (_selectedDetour) {
    'Kleiner Umweg' => 1,
    'Mittlerer Umweg' => 2,
    'Großer Umweg' => 3,
    _ => 0,
  };

  bool get _isWaypointPlanning => _isRoundTrip && _planningType == 'Wegpunkte';

  int _targetDistanceKm() {
    final digits = _selectedLength.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isNotEmpty ? int.parse(digits) : 50;
  }

  bool _shouldForceFreshRoute({
    required int targetKm,
    required String? waypointSignature,
  }) {
    if (_lastRoute == null) return false;
    return _lastGeneratedWasRoundTrip != _isRoundTrip ||
        _lastGeneratedPlanningType != _planningType ||
        _lastGeneratedStyle != _selectedStyle ||
        _lastGeneratedTargetKm != targetKm ||
        _lastGeneratedAvoidHighways != _avoidHighways ||
        _lastGeneratedWaypointSignature != waypointSignature ||
        _lastGeneratedDestinationSignature != _destinationSignature();
  }

  String? _destinationSignature() {
    final selected = _selectedDestination;
    if (selected == null) return null;
    return '${selected.latitude.toStringAsFixed(5)},${selected.longitude.toStringAsFixed(5)}';
  }

  String _waypointSignature([List<LatLng>? points]) {
    final source = points ?? _roundTripWaypoints;
    if (source.isEmpty) return 'none';
    return source
        .map(
          (point) =>
              '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}',
        )
        .join(';');
  }

  int _estimateWaypointRouteTargetKm({
    required geo.Position startPosition,
    required List<LatLng> waypoints,
    required int fallbackKm,
  }) {
    if (waypoints.isEmpty) return fallbackKm;
    var straightLineMeters = 0.0;
    var previousLat = startPosition.latitude;
    var previousLng = startPosition.longitude;
    for (final waypoint in waypoints) {
      straightLineMeters += geo.Geolocator.distanceBetween(
        previousLat,
        previousLng,
        waypoint.latitude,
        waypoint.longitude,
      );
      previousLat = waypoint.latitude;
      previousLng = waypoint.longitude;
    }
    straightLineMeters += geo.Geolocator.distanceBetween(
      previousLat,
      previousLng,
      startPosition.latitude,
      startPosition.longitude,
    );
    final estimatedRoadKm = (straightLineMeters / 1000.0) * 1.28;
    return math.max(fallbackKm, estimatedRoadKm.ceil()).clamp(25, 260).toInt();
  }

  List<LatLng> _deliveredWaypointsFromMeta(Map<String, dynamic> meta) {
    final raw =
        meta['delivered_waypoints'] ??
        meta['delivered_required_waypoints'] ??
        meta['required_waypoints'];
    if (raw is! List) return const <LatLng>[];
    return raw
        .whereType<Map>()
        .map((item) {
          final lat = item['latitude'] ?? item['lat'];
          final lng = item['longitude'] ?? item['lng'];
          if (lat is! num || lng is! num) return null;
          return LatLng(lat.toDouble(), lng.toDouble());
        })
        .whereType<LatLng>()
        .take(3)
        .toList(growable: false);
  }

  Future<void> _createGroup() async {
    if (_isCreating) return;
    final acceptedSafety = await showGroupSafetyNoticeSheet(context);
    if (!acceptedSafety) return;
    if (_lastRoute == null || _startPoint == null) {
      _showError('Bitte zuerst eine Route generieren.');
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      _showError('Bitte Gruppennamen eingeben.');
      return;
    }
    if (_nameCtrl.text.trim().length > AppInputLimits.groupNameMaxLength) {
      _showError('Gruppenname ist zu lang.');
      return;
    }
    if (_descCtrl.text.trim().length >
        AppInputLimits.groupDescriptionMaxLength) {
      _showError('Beschreibung ist zu lang.');
      return;
    }
    if (_selectedDateTime == null) {
      _showError('Bitte Datum & Uhrzeit wählen.');
      return;
    }

    setState(() => _isCreating = true);
    try {
      final startDt = _selectedDateTime;

      final routeData = GroupRouteDataBuilder.build(
        route: _lastRoute!,
        isRoundTrip: _isRoundTrip,
        planningType: _planningType,
        style: _selectedStyle,
        avoidHighways: _avoidHighways,
        targetDistanceKm: _isRoundTrip ? _targetDistanceKm() : null,
        destination: _selectedDestination,
        requiredWaypoints: List<LatLng>.unmodifiable(_roundTripWaypoints),
        waypointOrigin: _isWaypointPlanning ? _waypointOrigin : null,
        waypointSeedAttempt: _isWaypointPlanning ? _waypointSeedAttempt : null,
        detourVariant: _detourVariant,
        scenic: !_isRoundTrip && _detourVariant > 0,
      );

      final groupId = await CruiseGroupService.create(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        isPublic: _selectedVisibility == 'Öffentlich (Für jeden)',
        maxPeople: _maxPeople.round(),
        startTime: startDt,
        routeData: routeData,
        startLocation: {
          'lat': _startPoint!.latitude,
          'lng': _startPoint!.longitude,
        },
      );

      if (!mounted) return;
      final gamResult = await GamificationService.calculateAndSync();
      if (!mounted) return;
      if (gamResult.newBadges.isNotEmpty) {
        await showBadgeUnlockPopup(
          context: context,
          badges: gamResult.newBadges,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GroupLobbyPage(groupId: groupId)),
      );
    } catch (e) {
      _showError('Gruppe konnte nicht erstellt werden: $e');
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _handleRouteModeChanged(bool isRoundTrip) {
    setState(() {
      _isRoundTrip = isRoundTrip;
      _lastRoute = null;
      _routeLatLngs = [];
      if (isRoundTrip) {
        _selectedDetour = 'Direkt';
        _selectedDestination = null;
        _destinationCtrl.clear();
      } else {
        _planningType = 'Zufall';
        _roundTripWaypoints.clear();
        _selectedWaypointIndex = null;
        _replaceWaypointIndex = null;
        _waypointOrigin = 'manual';
      }
    });
  }

  void _handlePlanningTypeChanged(String planningType) {
    setState(() {
      _planningType = planningType;
      _lastRoute = null;
      _routeLatLngs = [];
      if (planningType == 'Zufall') {
        _roundTripWaypoints.clear();
        _selectedWaypointIndex = null;
        _replaceWaypointIndex = null;
        _waypointOrigin = 'manual';
        _waypointSeedAttempt = 0;
      }
    });
  }

  void _handleMapTap(LatLng point) {
    if (_isGenerating) return;
    if (_isWaypointPlanning) {
      _setWaypointFromMap(point);
      return;
    }
    if (_selectedLocation == 'Standort wählen') {
      setState(() {
        _startPoint = point;
        _lastRoute = null;
        _routeLatLngs = [];
      });
    }
  }

  void _setWaypointFromMap(LatLng point) {
    final replaceIndex = _replaceWaypointIndex;
    var hitWaypointLimit = false;
    setState(() {
      _lastRoute = null;
      _routeLatLngs = [];
      _waypointOrigin = 'manual';
      _waypointSeedAttempt = 0;
      if (replaceIndex != null &&
          replaceIndex >= 0 &&
          replaceIndex < _roundTripWaypoints.length) {
        _roundTripWaypoints[replaceIndex] = point;
        _selectedWaypointIndex = replaceIndex;
        _replaceWaypointIndex = null;
        return;
      }
      if (_roundTripWaypoints.length >= 3) {
        hitWaypointLimit = true;
        return;
      }
      _roundTripWaypoints.add(point);
      _selectedWaypointIndex = _roundTripWaypoints.length - 1;
    });
    if (hitWaypointLimit) {
      _showError('Maximal 3 Stopps möglich.');
    }
  }

  void _removeLastWaypoint() {
    if (_isGenerating || _roundTripWaypoints.isEmpty) return;
    setState(() {
      _roundTripWaypoints.removeLast();
      _selectedWaypointIndex = _roundTripWaypoints.isEmpty
          ? null
          : math.min(
              _selectedWaypointIndex ?? _roundTripWaypoints.length - 1,
              _roundTripWaypoints.length - 1,
            );
      _replaceWaypointIndex = null;
      _waypointOrigin = 'manual';
      _waypointSeedAttempt = 0;
      _lastRoute = null;
      _routeLatLngs = [];
    });
  }

  void _clearWaypoints() {
    if (_isGenerating || _roundTripWaypoints.isEmpty) return;
    setState(() {
      _roundTripWaypoints.clear();
      _selectedWaypointIndex = null;
      _replaceWaypointIndex = null;
      _waypointOrigin = 'manual';
      _waypointSeedAttempt = 0;
      _lastRoute = null;
      _routeLatLngs = [];
    });
  }

  void _deleteSelectedWaypoint() {
    final index = _selectedWaypointIndex;
    if (index == null || index < 0 || index >= _roundTripWaypoints.length) {
      return;
    }
    setState(() {
      _roundTripWaypoints.removeAt(index);
      _selectedWaypointIndex = _roundTripWaypoints.isEmpty
          ? null
          : math.min(index, _roundTripWaypoints.length - 1);
      _replaceWaypointIndex = null;
      _waypointOrigin = 'manual';
      _waypointSeedAttempt = 0;
      _lastRoute = null;
      _routeLatLngs = [];
    });
  }

  void _replaceSelectedWaypoint() {
    final index = _selectedWaypointIndex;
    if (index == null || index < 0 || index >= _roundTripWaypoints.length) {
      return;
    }
    setState(() => _replaceWaypointIndex = index);
    _showError('Tippe auf die Karte, um Stopp ${index + 1} neu zu setzen.');
  }

  Future<void> _generateWaypointSeed() async {
    try {
      final startPosition = await _getStartCoordinates();
      final center = LatLng(startPosition.latitude, startPosition.longitude);
      final targetKm = _targetDistanceKm();
      final nextSeed = _waypointSeedCounter + 1;
      var points = <LatLng>[];
      for (var attempt = 0; attempt < 4; attempt += 1) {
        points = _buildWaypointSeed(
          center: center,
          targetKm: targetKm,
          variant: nextSeed + attempt,
        );
        if (_waypointLayoutLooksStable(center, points, targetKm)) break;
      }
      if (!mounted) return;
      setState(() {
        _waypointSeedCounter = nextSeed;
        _planningType = 'Wegpunkte';
        _roundTripWaypoints
          ..clear()
          ..addAll(points);
        _selectedWaypointIndex = points.isEmpty ? null : 0;
        _replaceWaypointIndex = null;
        _waypointOrigin = 'auto_seed';
        _waypointSeedAttempt = nextSeed;
        _lastRoute = null;
        _routeLatLngs = [];
      });
    } catch (_) {
      _showError('Aktueller Standort noch nicht verfügbar.');
    }
  }

  List<LatLng> _buildWaypointSeed({
    required LatLng center,
    required int targetKm,
    required int variant,
  }) {
    final count = _selectedStyle == 'Abendrunde' ? 2 : 3;
    final baseRadiusKm = math.min(
      18.0,
      math.max(4.0, targetKm / (_selectedStyle == 'Abendrunde' ? 8.5 : 6.0)),
    );
    final styleBaseBearing = switch (_selectedStyle) {
      'Kurvenjagd' => 120.0,
      'Entdecker' => 35.0,
      'Abendrunde' => 250.0,
      _ => 75.0,
    };
    final baseBearing = (styleBaseBearing + variant * 47.0) % 360.0;
    final offsets = switch (_selectedStyle) {
      'Kurvenjagd' => const [-82.0, 4.0, 112.0],
      'Entdecker' => const [-82.0, -8.0, 76.0],
      'Abendrunde' => const [-48.0, 62.0],
      _ => const [-54.0, 12.0, 84.0],
    };
    final factors = switch (_selectedStyle) {
      'Kurvenjagd' => const [0.90, 1.16, 0.98],
      'Entdecker' => const [0.90, 1.06, 0.96],
      'Abendrunde' => const [0.78, 0.90],
      _ => const [0.94, 1.08, 0.92],
    };
    final highwayScale = _avoidHighways ? 0.95 : 1.0;
    return List.generate(count, (index) {
      final bearing = (baseBearing + offsets[index]) % 360.0;
      final distanceKm = baseRadiusKm * factors[index] * highwayScale;
      return _offsetLatLng(center, distanceKm, bearing);
    }, growable: false);
  }

  bool _waypointLayoutLooksStable(
    LatLng center,
    List<LatLng> points,
    int targetKm,
  ) {
    // 2026-05-24 (vucko Task #47): Limit erhöht auf 5 (Trip-Modus)
    if (points.isEmpty || points.length > 5) return false;
    final maxDistanceKm = math.max(12.0, math.min(80.0, targetKm * 0.75));
    final bearings = <double>[];
    for (var i = 0; i < points.length; i += 1) {
      final point = points[i];
      final fromStartKm =
          geo.Geolocator.distanceBetween(
            center.latitude,
            center.longitude,
            point.latitude,
            point.longitude,
          ) /
          1000.0;
      if (fromStartKm < 0.35 || fromStartKm > maxDistanceKm) return false;
      for (var j = 0; j < i; j += 1) {
        final pairKm =
            geo.Geolocator.distanceBetween(
              point.latitude,
              point.longitude,
              points[j].latitude,
              points[j].longitude,
            ) /
            1000.0;
        if (pairKm < 0.35) return false;
      }
      bearings.add(
        calculateBearing(
          center.latitude,
          center.longitude,
          point.latitude,
          point.longitude,
        ),
      );
    }
    return _bearingSpreadDegrees(bearings) >= 22.0;
  }

  double _bearingSpreadDegrees(List<double> bearings) {
    if (bearings.isEmpty) return 0.0;
    final normalized =
        bearings
            .map((bearing) => bearing % 360)
            .map((bearing) => bearing < 0 ? bearing + 360 : bearing)
            .toList()
          ..sort();
    var largestGap = 0.0;
    for (var i = 0; i < normalized.length; i += 1) {
      final current = normalized[i];
      final next =
          normalized[(i + 1) % normalized.length] +
          (i == normalized.length - 1 ? 360.0 : 0.0);
      largestGap = math.max(largestGap, next - current);
    }
    return 360.0 - largestGap;
  }

  LatLng _offsetLatLng(LatLng origin, double distanceKm, double bearingDeg) {
    const earthRadiusKm = 6371.0;
    final angularDistance = distanceKm / earthRadiusKm;
    final bearing = bearingDeg * math.pi / 180.0;
    final lat1 = origin.latitude * math.pi / 180.0;
    final lng1 = origin.longitude * math.pi / 180.0;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angularDistance) +
          math.cos(lat1) * math.sin(angularDistance) * math.cos(bearing),
    );
    final lng2 =
        lng1 +
        math.atan2(
          math.sin(bearing) * math.sin(angularDistance) * math.cos(lat1),
          math.cos(angularDistance) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(lat2 * 180.0 / math.pi, lng2 * 180.0 / math.pi);
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                backgroundColor: const Color(0xFF0B0E14),
                elevation: 0,
                leading: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(background: _buildMap()),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_lastRoute != null) _buildRouteStats(),

                      CruiseSetupCard(
                        isRoundTrip: _isRoundTrip,
                        planningType: _planningType,
                        selectedLength: _selectedLength,
                        selectedLocation: _selectedLocation,
                        selectedStyle: _selectedStyle,
                        selectedDestination: _selectedDestination,
                        destinationController: _destinationCtrl,
                        onRoundTripChanged: _handleRouteModeChanged,
                        onPlanningTypeChanged: _handlePlanningTypeChanged,
                        onLengthChanged: (value) {
                          setState(() {
                            _selectedLength = value;
                            _lastRoute = null;
                            _routeLatLngs = [];
                          });
                        },
                        onLocationChanged: (value) async {
                          setState(() => _selectedLocation = value);
                          if (value == 'Aktueller Standort') {
                            await _tryLocateUser();
                          }
                        },
                        onStyleChanged: (value) {
                          setState(() {
                            _selectedStyle = value;
                            _lastRoute = null;
                            _routeLatLngs = [];
                          });
                        },
                        onDestinationSelected: (suggestion) {
                          setState(() {
                            _selectedDestination = suggestion;
                            _destinationCtrl.text = suggestion.placeName;
                            _lastRoute = null;
                            _routeLatLngs = [];
                          });
                        },
                        onDestinationCleared: () {
                          setState(() {
                            _selectedDestination = null;
                            _destinationCtrl.clear();
                            _lastRoute = null;
                            _routeLatLngs = [];
                          });
                        },
                        onDestinationInputChanged: (_) {
                          if (_selectedDestination != null) {
                            setState(() => _selectedDestination = null);
                          }
                        },
                        selectedDetour: _selectedDetour,
                        onDetourChanged: (value) {
                          setState(() {
                            _selectedDetour = value;
                            _lastRoute = null;
                            _routeLatLngs = [];
                          });
                        },
                        selectedAvoidHighways: _avoidHighways,
                        onAvoidHighwaysChanged: (value) {
                          setState(() {
                            _avoidHighways = value;
                            _lastRoute = null;
                            _routeLatLngs = [];
                          });
                        },
                        proximityLatitude: _startPoint?.latitude,
                        proximityLongitude: _startPoint?.longitude,
                        roundTripWaypointCount: _roundTripWaypoints.length,
                        selectedWaypointIndex: _selectedWaypointIndex,
                        replacingWaypointIndex: _replaceWaypointIndex,
                        waypointActionsEnabled: !_isGenerating,
                        onGenerateWaypointSeed: () =>
                            unawaited(_generateWaypointSeed()),
                        onRemoveLastWaypoint: _removeLastWaypoint,
                        onDeleteSelectedWaypoint: _deleteSelectedWaypoint,
                        onReplaceSelectedWaypoint: _replaceSelectedWaypoint,
                        onClearWaypoints: _clearWaypoints,
                      ),
                      const SizedBox(height: 16),
                      _buildStartAddressHelper(),
                      if (_selectedLocation == 'Adresse') ...[
                        const SizedBox(height: 12),
                        _buildAddressField(),
                      ],
                      const SizedBox(height: 40),
                      const Text(
                        'Gruppen-Details',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildGroupDetailsCard(),
                      const SizedBox(height: 24),
                      _buildNameField(),
                      const SizedBox(height: 20),
                      const Text(
                        'Beschreibung',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDescriptionField(),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_isGenerating) _buildRouteGenerationStatus(),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildRouteGenerationStatus() {
    final top = MediaQuery.of(context).padding.top + 12;
    return Positioned(
      top: top,
      left: 82,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF161B24).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppAccentColors.accent.withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: AppAccentColors.accent.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: AppAccentColors.accent,
                strokeWidth: 2.4,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _routeStatusText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    if (widget.disableMapTilesForTesting) {
      return const ColoredBox(color: Color(0xFF0B0E14));
    }

    final initialCenter = _startPoint ?? const LatLng(48.1351, 11.5820);
    return Stack(
      children: [
        CruiseMapLibreMap(
          initialCenter: initialCenter,
          initialZoom: _startPoint == null ? 10 : 12,
          activeRoutePoints: _routeLatLngs,
          routeColor: AppAccentColors.accent,
          markers: _buildMapLibreMarkers(),
          onMapClick: _handleMapTap,
          onControllerReady: _handleMapReady,
        ),
        if (_isWaypointPlanning) _buildWaypointActionOverlay(),
      ],
    );
  }

  void _handleMapReady(CruiseMapLibreController controller) {
    _mapController = controller;
    if (_routeLatLngs.length >= 2) {
      _fitRouteBounds(_routeLatLngs);
      return;
    }
    final start = _startPoint;
    if (start != null) _moveMapTo(start, zoom: 12);
  }

  List<CruiseMapMarker> _buildMapLibreMarkers() {
    final markers = <CruiseMapMarker>[];
    final start = _startPoint;
    if (start != null) {
      markers.add(
        CruiseMapMarker(
          id: 'group-start',
          position: start,
          width: 36,
          height: 36,
          child: _buildMapMarker(Icons.my_location),
        ),
      );
    }
    final destination = _selectedDestination;
    if (!_isRoundTrip && destination != null) {
      markers.add(
        CruiseMapMarker(
          id: 'group-destination',
          position: LatLng(destination.latitude, destination.longitude),
          width: 42,
          height: 42,
          child: _buildMapMarker(Icons.flag_rounded),
        ),
      );
    }
    for (var i = 0; i < _roundTripWaypoints.length; i++) {
      markers.add(
        CruiseMapMarker(
          id: 'group-waypoint-$i',
          position: _roundTripWaypoints[i],
          width: 42,
          height: 42,
          child: GestureDetector(
            onTap: () => setState(() => _selectedWaypointIndex = i),
            child: _buildWaypointMarker(i),
          ),
        ),
      );
    }
    return markers;
  }

  Widget _buildMapMarker(IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111823).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppAccentColors.accent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppAccentColors.accent.withValues(alpha: 0.35),
            blurRadius: 12,
          ),
        ],
      ),
      child: Center(child: Icon(icon, color: AppAccentColors.accent, size: 20)),
    );
  }

  Widget _buildWaypointMarker(int index) {
    final selected = _selectedWaypointIndex == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected
            ? AppAccentColors.accent
            : const Color(0xFF111823).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? Colors.white : AppAccentColors.accent,
          width: selected ? 2 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppAccentColors.accent.withValues(alpha: 0.35),
            blurRadius: 12,
          ),
        ],
      ),
      child: Center(
        child: Text(
          '${index + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildWaypointActionOverlay() {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMapActionButton(
              icon: Icons.auto_awesome,
              label: 'Stopps vorschlagen',
              onTap: _isGenerating
                  ? null
                  : () => unawaited(_generateWaypointSeed()),
            ),
            const SizedBox(height: 10),
            _buildMapActionButton(
              icon: Icons.undo,
              label: 'Letzten löschen',
              onTap: _roundTripWaypoints.isEmpty ? null : _removeLastWaypoint,
            ),
            const SizedBox(height: 10),
            _buildMapActionButton(
              icon: Icons.clear_all,
              label: 'Alle löschen',
              onTap: _roundTripWaypoints.isEmpty ? null : _clearWaypoints,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.45,
          duration: const Duration(milliseconds: 160),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1F26).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildRouteStats() {
    final km = ((_lastRoute!.distanceMeters ?? 0) / 1000).toStringAsFixed(1);
    final dur = _lastRoute!.durationSeconds ?? 0;
    final h = (dur / 3600).floor();
    final m = ((dur % 3600) / 60).round();
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppAccentColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppAccentColors.accent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildRouteStat(Icons.straighten, '$km km'),
          _buildRouteStat(Icons.timer, '${h}h ${m}m'),
          _buildRouteStat(
            Icons.route,
            '${_lastRoute!.coordinates.length} Punkte',
          ),
        ],
      ),
    );
  }

  Widget _buildRouteStat(IconData icon, String text) => Row(
    children: [
      Icon(icon, color: AppAccentColors.accent, size: 16),
      const SizedBox(width: 6),
      Text(
        text,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );

  Widget _buildStartAddressHelper() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          const Text(
            'Start per Adresse:',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          _buildTinyChoice(
            label: _selectedLocation == 'Adresse'
                ? 'Adresse aktiv'
                : 'Adresse wählen',
            selected: _selectedLocation == 'Adresse',
            onTap: () => setState(() => _selectedLocation = 'Adresse'),
          ),
          if (_selectedLocation == 'Standort wählen')
            const Text(
              'Tippe auf die Karte, um den Startpunkt zu setzen.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildTinyChoice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppAccentColors.accent : const Color(0xFF0B0E14),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppAccentColors.accent
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildAddressField() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _addressCtrl,
              maxLength: AppInputLimits.addressMaxLength,
              inputFormatters: AppInputLimits.lengthFormatters(
                AppInputLimits.addressMaxLength,
              ),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Adresse oder Ort',
                hintStyle: TextStyle(color: Colors.grey[600]),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _geocodeAddress(),
            ),
          ),
          IconButton(
            icon: Icon(Icons.search, color: AppAccentColors.accent),
            onPressed: _geocodeAddress,
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _nameCtrl,
        onChanged: (_) => setState(() {}),
        maxLength: AppInputLimits.groupNameMaxLength,
        inputFormatters: AppInputLimits.lengthFormatters(
          AppInputLimits.groupNameMaxLength,
        ),
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          counterText: '',
          hintText: 'Gruppenname',
          hintStyle: TextStyle(color: Colors.grey[600]),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildDescriptionField() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: TextField(
        controller: _descCtrl,
        onChanged: (_) => setState(() {}),
        maxLength: AppInputLimits.groupDescriptionMaxLength,
        inputFormatters: AppInputLimits.lengthFormatters(
          AppInputLimits.groupDescriptionMaxLength,
        ),
        style: const TextStyle(color: Colors.white),
        maxLines: 5,
        decoration: InputDecoration(
          counterText: '',
          hintText: 'Beschreibe deine Gruppe...',
          hintStyle: TextStyle(color: Colors.grey[600]),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildGroupDetailsCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          InkWell(
            onTap: _selectTime,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  const Icon(Icons.access_time, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  const Text(
                    'Startuhrzeit *',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B0E14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _selectedDateTime != null
                          ? _formatDateTime(_selectedDateTime!)
                          : 'Wählen',
                      style: TextStyle(
                        color: _selectedDateTime != null
                            ? Colors.white
                            : AppAccentColors.accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(
            color: Colors.white10,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Max. Personen',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                Text(
                  '${_maxPeople.round()}',
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppAccentColors.accent,
              inactiveTrackColor: Colors.grey[800],
              thumbColor: Colors.white,
              overlayColor: AppAccentColors.accent.withValues(alpha: 0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: _maxPeople,
              min: 2,
              max: 50,
              divisions: 48,
              onChanged: (v) => setState(() => _maxPeople = v),
            ),
          ),
          const Divider(
            color: Colors.white10,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Zugänglichkeit',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: ['Nur Kontakte', 'Öffentlich (Für jeden)'].map((
                    option,
                  ) {
                    final isSelected = option == _selectedVisibility;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedVisibility = option),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppAccentColors.accent
                              : const Color(0xFF1A1D24),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          option,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey[400],
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final canCreate = _canCreateGroup;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.9), Colors.transparent],
            stops: const [0.6, 1.0],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isGenerating ? null : _generateRoute,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1C1F26),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.refresh,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _lastRoute == null ? 'Generieren' : 'Neue Route',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: (_isCreating || !canCreate) ? null : _createGroup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppAccentColors.accent,
                    disabledBackgroundColor: AppAccentColors.accent.withValues(
                      alpha: 0.3,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 8,
                  ),
                  child: _isCreating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Erstellen',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canCreateGroup {
    return _lastRoute != null &&
        _nameCtrl.text.trim().isNotEmpty &&
        _nameCtrl.text.trim().length <= AppInputLimits.groupNameMaxLength &&
        _descCtrl.text.trim().length <=
            AppInputLimits.groupDescriptionMaxLength &&
        _selectedDateTime != null &&
        _maxPeople.round() >= 2;
  }

  Future<void> _selectTime() async {
    final now = DateTime.now();
    Widget theme(BuildContext ctx, Widget? child) => Theme(
      data: Theme.of(ctx).copyWith(
        colorScheme: ColorScheme.dark(
          primary: AppAccentColors.accent,
          surface: const Color(0xFF1C1F26),
          onSurface: Colors.white,
        ),
        dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1C1F26)),
      ),
      child: child!,
    );

    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      builder: theme,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _selectedDateTime != null
          ? TimeOfDay.fromDateTime(_selectedDateTime!)
          : TimeOfDay.now(),
      builder: theme,
    );
    if (time == null) return;

    setState(() {
      _selectedDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  String _formatDateTime(DateTime dt) {
    final d =
        '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.';
    final t =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d $t';
  }
}
