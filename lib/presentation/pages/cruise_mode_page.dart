import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cruise_connect/core/constants.dart';

import 'package:cruise_connect/data/services/web_position_smoother.dart';
import 'package:cruise_connect/data/services/native_position_smoother.dart';
import 'package:cruise_connect/data/services/geocoding_service.dart';
import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:cruise_connect/data/services/navigation_progress_socket_service.dart';
import 'package:cruise_connect/data/services/offline_map_service.dart';
import 'package:cruise_connect/data/services/route_access_plan.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/data/services/route_cache_service.dart';
import 'package:cruise_connect/data/services/route_completion_candidate_service.dart';
import 'package:cruise_connect/data/services/route_pool_service.dart';
import 'package:cruise_connect/data/services/route_rating_service.dart';
import 'package:cruise_connect/data/services/smart_reroute_engine.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/mapbox_suggestion.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart'
    show RouteManeuver, RouteWindowMatch;
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_completion_dialog.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_maneuver_indicator.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_navigation_info_panel.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_setup_card.dart';
import 'package:cruise_connect/presentation/widgets/cruise/drive_control_panel.dart';
import 'package:cruise_connect/presentation/widgets/cruise/routing_onboarding_sheet.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/cruise_group_service.dart';
import 'package:cruise_connect/data/services/route_quality_validator.dart';
import 'package:cruise_connect/domain/models/group_member.dart';

class CruiseModePage extends StatefulWidget {
  const CruiseModePage({super.key, this.initialRoute, this.groupId});

  /// Wenn gesetzt, wird diese Route direkt geladen und bestätigt.
  final SavedRoute? initialRoute;

  /// Wenn gesetzt, läuft die Navigation als Teil einer Cruise-Gruppe:
  /// lädt Route aus Supabase, sendet eigene Position regelmäßig,
  /// hört auf Positionen der anderen Mitglieder.
  final String? groupId;

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

class _GeneratedRouteUiStateSnapshot {
  _GeneratedRouteUiStateSnapshot({
    required this.lastRouteResult,
    required this.sessionRouteResult,
    required this.accessLegMainRouteResult,
    required this.activeSpeedLimits,
    required this.activeDestinationCoordinate,
    required this.activeDetourVariant,
    required this.activePointToPointScenic,
    required this.activePointToPointMode,
    required this.activeAvoidHighways,
    required this.recentDestinationDistances,
    required this.isAccessLegActive,
    required this.accessLegJoinIndex,
    required this.routeGeoJson,
    required this.routeDistance,
    required this.routeDuration,
    required this.routeLatLngs,
    required this.fullRouteCoordinates,
    required this.remainingRouteCoordinates,
    required this.maneuvers,
    required this.activeManeuverIndex,
    required this.currentRouteIndex,
    required this.lastDrawnRouteIndex,
    required this.distanceSinceLastRedraw,
    required this.showRouteInfoBanner,
    required this.isRouteConfirmed,
    required this.isExistingRouteSession,
    required this.cachedCurveCount,
    required this.remainingDistance,
    required this.remainingDuration,
    required this.sessionRouteStartIndexInActiveRoute,
    required this.navigationStartTime,
    required this.offRouteCount,
    required this.lastRerouteTime,
    required this.isRerouting,
    required this.originalRouteDistance,
    required this.originalRouteDuration,
    required this.totalDistanceDriven,
    required this.isCameraLocked,
    required this.configCollapsed,
    required this.announcedManeuverIndices,
  });

  final RouteResult? lastRouteResult;
  final RouteResult? sessionRouteResult;
  final RouteResult? accessLegMainRouteResult;
  final List<SpeedLimitSegment> activeSpeedLimits;
  final List<double>? activeDestinationCoordinate;
  final int activeDetourVariant;
  final bool activePointToPointScenic;
  final String activePointToPointMode;
  final bool activeAvoidHighways;
  final List<double> recentDestinationDistances;
  final bool isAccessLegActive;
  final int? accessLegJoinIndex;
  final String? routeGeoJson;
  final double? routeDistance;
  final double? routeDuration;
  final List<LatLng> routeLatLngs;
  final List<List<double>> fullRouteCoordinates;
  final List<List<double>> remainingRouteCoordinates;
  final List<RouteManeuver> maneuvers;
  final int activeManeuverIndex;
  final int currentRouteIndex;
  final int lastDrawnRouteIndex;
  final double distanceSinceLastRedraw;
  final bool showRouteInfoBanner;
  final bool isRouteConfirmed;
  final bool isExistingRouteSession;
  final int cachedCurveCount;
  final double? remainingDistance;
  final double? remainingDuration;
  final int sessionRouteStartIndexInActiveRoute;
  final DateTime? navigationStartTime;
  final int offRouteCount;
  final DateTime? lastRerouteTime;
  final bool isRerouting;
  final double? originalRouteDistance;
  final double? originalRouteDuration;
  final double totalDistanceDriven;
  final bool isCameraLocked;
  final bool configCollapsed;
  final Set<int> announcedManeuverIndices;
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
  RouteResult? _sessionRouteResult;
  bool _configCollapsed = false; // Config-Panel ein-/ausgeklappt
  bool _showRouteInfoBanner = false; // Route-Info Banner nach Generation
  bool _routeWarmupDialogOpen = false;
  String? _routeSearchNoticeTitle;
  String? _routeSearchNoticeMessage;
  double _routeSearchProgress = 0.08;
  int _routeGenerationSerial = 0;
  int? _activeRouteGenerationSerial;
  bool _routeGenerationCancelled = false;
  int _cachedCurveCount = 0; // Vorab im Isolate berechnet
  List<double>? _activeDestinationCoordinate;
  String _activePointToPointMode = 'Standard';
  int _activeDetourVariant = 0;
  bool _activePointToPointScenic = false;
  bool _activeAvoidHighways = false;
  bool? _lastGeneratedWasRoundTrip;
  int? _lastGeneratedSelectedKm;
  String? _lastGeneratedSelectedStyle;
  bool? _lastGeneratedAvoidHighways;
  String? _lastGeneratedWaypointSignature;
  List<double> _recentDestinationDistances = [];
  List<SpeedLimitSegment> _activeSpeedLimits = [];

  // ─────────────────────── Map State (flutter_map) ───────────────────────────
  bool _isLoading = false;
  bool _isPreparingExistingRoute = false;
  Timer? _routeLoadingPhaseTimer;
  int _routeLoadingPhaseIndex = 0;
  final MapController _mapController = MapController();
  bool _mapReady = false;
  final List<LatLng> _roundTripWaypoints = [];
  int? _selectedRoundTripWaypointIndex;
  int? _replaceRoundTripWaypointIndex;
  int _waypointSeedCounter = 0;
  String _roundTripWaypointOrigin = 'manual';
  int _roundTripWaypointSeedAttempt = 0;
  // Route als LatLng-Liste für PolylineLayer
  List<LatLng> _routeLatLngs = [];
  Timer? _routeDrawAnimationTimer;
  int _routeDrawAnimationToken = 0;
  // Aktuelle User-Position als Marker
  LatLng? _userPosition;
  double _userHeading = 0.0; // GPS-Heading in Grad (0=Nord, 90=Ost)

  /// Marker-Größe: iOS-Puck ist kompakter (44px) als Default (80px).
  double get _puckSize => !kIsWeb && Platform.isIOS ? 44.0 : 80.0;

  // ─────────────────────── Navigation State ─────────────────────────────────
  geo.Position? _userLocation;
  List<List<double>> _fullRouteCoordinates = [];
  List<List<double>> _remainingRouteCoordinates = [];
  List<RouteManeuver> _maneuvers = [];
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
  bool _isExistingRouteSession =
      false; // Route aus gespeicherter Vorlage gestartet
  bool _isAccessLegActive = false; // Nutzer fährt aktuell Zufahrts-Abschnitt
  int?
  _accessLegJoinIndex; // Index in _fullRouteCoordinates, ab dem Main-Route aktiv ist
  int _sessionRouteStartIndexInActiveRoute =
      0; // Index ab dem die logische Hauptroute im aktiven Track beginnt
  RouteResult? _accessLegMainRouteResult;
  static const double _offRouteThresholdMeters =
      50.0; // Ab wann Off-Route erkannt wird (wie Apple/Google Maps)
  static const int _offRouteCountThreshold =
      8; // Mindestanzahl Off-Route-Updates vor Reroute (verhindert Flackern)
  static const int _routeRedrawIndexThreshold =
      5; // Häufigere Teil-Redraws für flüssige Linie
  static const double _routeRedrawDistanceMeters = 30.0;
  double _totalDistanceDriven = 0.0; // Gesamte gefahrene Strecke in Metern
  DateTime? _navigationStartTime; // Zeitpunkt des Navigations-Starts
  int _xpStreakDays = 1;
  double?
  _originalRouteDistance; // Ursprüngliche Gesamtdistanz (für Zeitberechnung)
  double?
  _originalRouteDuration; // Ursprüngliche Gesamtdauer (für Zeitberechnung)

  // Schwellenwerte für anteilige Gutschrift
  static const double _minProgressForCredit = 0.20; // 20% Minimum
  static const double _minProgressForFullCredit =
      1.0; // Nur echte Zielankunft bekommt volle Gutschrift
  static const double _minProgressForAutomaticCompletion = 0.95;
  static const double _roundTripFinishArmProgress = 0.80;
  int _lastDrawnRouteIndex =
      0; // Letzter Index bei dem die Route neu gezeichnet wurde
  double _distanceSinceLastRedraw = 0.0;

  bool _disposed = false;

  // ─────────────────────── Group / Live Tracking ────────────────────────────
  RealtimeChannel? _groupMembersCh;
  Timer? _positionUploadTimer;
  final Map<String, GroupMember> _groupMembers = {};

  // Web-only: Letzte setState-Zeit für Throttling (max. 1 Rebuild / 16ms auf Web)
  DateTime? _lastWebRebuildTime;

  // Web-only: GPS-Smoother für flüssige Positionsdarstellung (Kalman-Filter)
  final WebPositionSmoother _webSmoother = WebPositionSmoother();

  // iOS/Android: Native GPS-Smoother mit Heading-Fusion (Kalman-Filter)
  final NativePositionSmoother _nativeSmoother = NativePositionSmoother(
    minMovementMeters: 1.5,
    maxJumpMeters: 500.0,
    minHeadingDistanceMeters: 3.0,
    headingSmoothingFactor: 0.45, // iOS-optimiert: reaktiv aber nicht nervös
    processNoise: 1.8,
    stationaryNoiseMeters: 4.0,
    headingNoiseThresholdDegrees: 12.0,
    lowSpeedThresholdMs: 2.5, // Unter 9 km/h: Bewegungs-Heading priorisieren
    highSpeedThresholdMs: 8.0, // Über 29 km/h: GPS-Heading priorisieren
  );

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

  static const List<String> _roundTripLoadingPhases = [
    'Live-Routen prüfen',
    'Alternativen vergleichen',
    'Route verfeinern',
    'Strecke final prüfen',
    'Fast fertig',
  ];

  static const List<String> _waypointLoadingPhases = [
    'Stopps verbinden',
    'Nächste Straßen finden',
    'Stil anwenden',
    'Route final prüfen',
    'Fast fertig',
  ];

  static const List<String> _pointToPointLoadingPhases = [
    'Ziel prüfen',
    'Straßen finden',
    'Stil anwenden',
    'Route final prüfen',
    'Fast fertig',
  ];

  static const List<String> _existingRouteLoadingPhases = [
    'Andockpunkt finden',
    'Anfahrt berechnen',
    'Route verbinden',
    'Rückweg vorbereiten',
    'Fast fertig',
  ];

  String get _routeLoadingStatusText {
    if (_isPreparingExistingRoute) {
      final phaseIndex = _routeLoadingPhaseIndex.clamp(
        0,
        _existingRouteLoadingPhases.length - 1,
      );
      return _existingRouteLoadingPhases[phaseIndex];
    }
    if (_isWaypointPlanning) {
      final phaseIndex = _routeLoadingPhaseIndex.clamp(
        0,
        _waypointLoadingPhases.length - 1,
      );
      return _waypointLoadingPhases[phaseIndex];
    }
    if (!_isRoundTrip) {
      final phaseIndex = _routeLoadingPhaseIndex.clamp(
        0,
        _pointToPointLoadingPhases.length - 1,
      );
      return _pointToPointLoadingPhases[phaseIndex];
    }
    final phaseIndex = _routeLoadingPhaseIndex.clamp(
      0,
      _roundTripLoadingPhases.length - 1,
    );
    return _roundTripLoadingPhases[phaseIndex];
  }

  void _startRouteLoadingUi({
    required int generationId,
    bool preparingExistingRoute = false,
  }) {
    _routeLoadingPhaseTimer?.cancel();
    _safeSetState(() {
      _isLoading = true;
      _isPreparingExistingRoute = preparingExistingRoute;
      _activeRouteGenerationSerial = generationId;
      _routeGenerationCancelled = false;
      _showRouteInfoBanner = false;
      _routeLoadingPhaseIndex = 0;
      _routeSearchProgress = 0.08;
      _routeSearchNoticeTitle = null;
      _routeSearchNoticeMessage = null;
      _configCollapsed = true;
    });
    _routeLoadingPhaseTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted ||
          _disposed ||
          !_isLoading ||
          _activeRouteGenerationSerial != generationId) {
        return;
      }
      _safeSetState(() {
        _routeSearchProgress = math.min(_routeSearchProgress + 0.045, 0.92);
        _routeLoadingPhaseIndex = math.min(
          (_routeSearchProgress * _roundTripLoadingPhases.length).floor(),
          _roundTripLoadingPhases.length - 1,
        );
      });
    });
  }

  void _stopRouteLoadingUi({int? generationId}) {
    if (generationId != null && _activeRouteGenerationSerial != generationId) {
      return;
    }
    _routeLoadingPhaseTimer?.cancel();
    _routeLoadingPhaseTimer = null;
    _safeSetState(() {
      _isLoading = false;
      _isPreparingExistingRoute = false;
      _routeLoadingPhaseIndex = 0;
      _routeSearchProgress = 0.08;
      if (generationId == null ||
          _activeRouteGenerationSerial == generationId) {
        _activeRouteGenerationSerial = null;
      }
    });
  }

  bool _isRouteGenerationCancelled(int generationId) {
    return _routeGenerationCancelled ||
        _activeRouteGenerationSerial != generationId ||
        !mounted ||
        _disposed;
  }

  void _cancelRouteGeneration() {
    if (!_isLoading && _routeSearchNoticeTitle == null) return;
    _routeLoadingPhaseTimer?.cancel();
    _routeLoadingPhaseTimer = null;
    _safeSetState(() {
      _routeGenerationCancelled = true;
      _activeRouteGenerationSerial = null;
      _isLoading = false;
      _isPreparingExistingRoute = false;
      _routeLoadingPhaseIndex = 0;
      _routeSearchProgress = 1.0;
      _routeSearchNoticeTitle = 'Suche abgebrochen';
      _routeSearchNoticeMessage =
          'Wir übernehmen keine Route aus dieser Suche. Du kannst jederzeit neu starten.';
    });
  }

  void _hideRouteSearchStatusForAcceptedRoute() {
    _routeLoadingPhaseTimer?.cancel();
    _routeLoadingPhaseTimer = null;
    _safeSetState(() {
      _isLoading = false;
      _isPreparingExistingRoute = false;
      _activeRouteGenerationSerial = null;
      _routeGenerationCancelled = false;
      _routeLoadingPhaseIndex = 0;
      _routeSearchProgress = 0.08;
      _routeSearchNoticeTitle = null;
      _routeSearchNoticeMessage = null;
    });
  }

  void _dismissTransientRouteUi() {
    if (!mounted || _disposed) return;
    FocusManager.instance.primaryFocus?.unfocus();
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
  }

  bool _hasMeaningfulRouteChange(List<LatLng> previous, List<LatLng> next) {
    if (previous.length != next.length) return true;
    if (previous.isEmpty) return false;

    final sampleCount = math.min(16, previous.length);
    final lastIndex = previous.length - 1;
    for (var i = 0; i < sampleCount; i++) {
      final ratio = sampleCount == 1 ? 0.0 : i / (sampleCount - 1);
      final index = (lastIndex * ratio).round();
      final prevPoint = previous[index];
      final nextPoint = next[index];
      final distance = geo.Geolocator.distanceBetween(
        prevPoint.latitude,
        prevPoint.longitude,
        nextPoint.latitude,
        nextPoint.longitude,
      );
      if (distance > 1.0) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    // Animierte Kamera-Bewegung zwischen GPS-Updates (alle Plattformen, 60fps)
    // iOS: Kürzere Animation (200ms) für reaktiveres Apple-Maps-artiges Gefühl
    // Web: Längere Animation (250ms) für smoothere Darstellung trotz unzuverlässiger GPS-Updates
    final animDuration = (!kIsWeb && Platform.isIOS)
        ? const Duration(milliseconds: 200)
        : const Duration(milliseconds: 250);
    _cameraAnimController = AnimationController(
      vsync: this,
      duration: animDuration,
    )..addListener(_onCameraAnimationTick);
    if (widget.initialRoute != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadSavedRoute(widget.initialRoute!),
      );
    }
    if (widget.groupId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _bootstrapGroupSession(widget.groupId!),
      );
    }
    CruiseModePage.pendingRoute.addListener(_onPendingRoute);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumePendingRouteIfAvailable();
    });
    _destinationController.addListener(_onDestinationTextChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowRoutingOnboarding(),
    );
  }

  Future<void> _maybeShowRoutingOnboarding() async {
    if (!mounted || _disposed) return;
    await showRoutingOnboardingSheet(context);
  }

  // ═══════════════════════ GROUP / LIVE TRACKING ═══════════════════════════

  Future<void> _bootstrapGroupSession(String groupId) async {
    final g = await CruiseGroupService.fetch(groupId);
    if (g == null || !mounted) return;

    // Mitglieder initial einlesen (ohne mich selbst)
    final meId = Supabase.instance.client.auth.currentUser?.id;
    for (final m in g.members) {
      if (m.userId != meId) _groupMembers[m.userId] = m;
    }
    _safeSetState(() {});

    // Route aus routeData laden und bestätigen
    final rd = g.routeData;
    if (rd != null && rd['geoJson'] is String) {
      final geometry =
          jsonDecode(rd['geoJson'] as String) as Map<String, dynamic>;
      final coordsRaw = (geometry['coordinates'] as List?) ?? [];
      final coordinates = coordsRaw
          .whereType<List>()
          .where((c) => c.length >= 2)
          .map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
          .toList();
      if (coordinates.length >= 2) {
        setState(() {
          _routeGeoJson = rd['geoJson'] as String;
          _routeDistance = (rd['distance_meters'] as num?)?.toDouble();
          _routeDuration = (rd['duration_seconds'] as num?)?.toDouble();
          _isRouteConfirmed = false;
          _fullRouteCoordinates = coordinates;
          _remainingRouteCoordinates = coordinates;
          _maneuvers = [];
        });
        await _drawRoute(geometry);
        await _confirmRoute();
      }
    }

    // Realtime: andere Mitglieder
    _groupMembersCh = CruiseGroupService.subscribeMembers(groupId, (row) {
      if (row.isEmpty) return;
      final uid = row['user_id'] as String?;
      if (uid == null || uid == meId) return;
      try {
        final incoming = GroupMember.fromMap(row);
        final existing = _groupMembers[uid];
        _groupMembers[uid] = GroupMember(
          id: incoming.id,
          groupId: incoming.groupId,
          userId: incoming.userId,
          role: incoming.role,
          rideRole: incoming.rideRole,
          currentLat: incoming.currentLat,
          currentLng: incoming.currentLng,
          lastUpdatedAt: incoming.lastUpdatedAt,
          createdAt: incoming.createdAt,
          displayName: incoming.displayName ?? existing?.displayName,
          avatarUrl: incoming.avatarUrl ?? existing?.avatarUrl,
        );
        _safeSetState(() {});
      } catch (_) {}
    });

    // Timer: eigene Position regelmäßig hochschieben
    _positionUploadTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _uploadMyPosition(),
    );
  }

  Widget _buildGroupMemberMarker(GroupMember m) {
    final isDriver = m.rideRole == RideRole.driver;
    final color = isDriver ? AppAccentColors.accent : const Color(0xFF4FC3F7);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 3),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8),
        ],
      ),
      child: CircleAvatar(
        backgroundColor: color,
        foregroundImage: UserAvatar.avatarImageProvider(
          context,
          m.avatarUrl,
          radius: 20,
        ),
        child: Icon(
          isDriver ? Icons.directions_car : Icons.person,
          color: Colors.white,
          size: 17,
        ),
      ),
    );
  }

  bool _hasFreshGroupMemberLocation(GroupMember m) {
    if (m.currentLat == null || m.currentLng == null) return false;
    final updatedAt = m.lastUpdatedAt;
    if (updatedAt == null) return false;
    return DateTime.now().toUtc().difference(updatedAt.toUtc()) <=
        const Duration(seconds: 30);
  }

  Future<void> _uploadMyPosition() async {
    if (widget.groupId == null) return;
    final pos = _userPosition;
    if (pos == null) return;
    try {
      await CruiseGroupService.updateMyPosition(
        groupId: widget.groupId!,
        lat: pos.latitude,
        lng: pos.longitude,
      );
    } catch (_) {}
  }

  void _onPendingRoute() {
    _consumePendingRouteIfAvailable();
  }

  void _consumePendingRouteIfAvailable() {
    if (!mounted || _disposed) return;
    final route = CruiseModePage.pendingRoute.value;
    if (route != null) {
      CruiseModePage.pendingRoute.value = null;
      unawaited(_loadSavedRoute(route));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _routeDrawAnimationToken++;
    _routeDrawAnimationTimer?.cancel();
    _routeLoadingPhaseTimer?.cancel();
    _cameraAnimController?.removeListener(_onCameraAnimationTick);
    _cameraAnimController?.dispose();
    CruiseModePage.isFullscreen.value = false;
    CruiseModePage.pendingRoute.removeListener(_onPendingRoute);
    _stopSimulation(restartLiveTracking: false);
    _positionSubscription?.cancel();
    _socketPositionSubscription?.cancel();
    _positionUploadTimer?.cancel();
    _groupMembersCh?.unsubscribe();
    _stopIdlePositionStream();
    unawaited(_navigationSocketService.dispose());
    _destinationController.removeListener(_onDestinationTextChanged);
    _destinationController.dispose();
    super.dispose();
  }

  void _onDestinationTextChanged() {
    final selected = _selectedDestination;
    if (selected == null) return;
    final currentText = _destinationController.text.trim();
    if (currentText == selected.placeName.trim()) return;
    if (!mounted || _disposed) {
      _selectedDestination = null;
      return;
    }
    setState(() => _selectedDestination = null);
  }

  // ── Smooth Kamera-Animation (60fps zwischen GPS-Updates) ───────────────
  void _onCameraAnimationTick() {
    final controller = _cameraAnimController;
    if (controller == null || !_isCameraLocked || !_mapReady) return;

    final t = Curves.easeOutCubic.transform(controller.value);
    var lat = _camFromLat + (_camToLat - _camFromLat) * t;
    var lng = _camFromLng + (_camToLng - _camFromLng) * t;
    var heading = _lerpAngleDeg(_camFromHeading, _camToHeading, t);

    // Plattformspezifische Vorhersage für flüssigere Animation
    if (kIsWeb && _webSmoother.current != null) {
      final prediction = _webSmoother.predict(DateTime.now());
      lat = lat + (prediction.lat - lat) * 0.35;
      lng = lng + (prediction.lng - lng) * 0.35;
      heading = _lerpAngleDeg(heading, prediction.heading, 0.35);
    } else if (!kIsWeb && _nativeSmoother.hasValidHeading) {
      // iOS/Android: Native Smoother für Heading-Prediction
      final prediction = _nativeSmoother.predict(DateTime.now());
      // Position sanft mischen (Kalman-geglättet)
      lat = lat + (prediction.lat - lat) * 0.30;
      lng = lng + (prediction.lng - lng) * 0.30;
      // Heading stärker gewichten für reaktive Drehung (Apple-Maps-artig)
      heading = _lerpAngleDeg(heading, prediction.heading, 0.45);
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

    // iOS: Kleinere Dead-Zone (1.5°) für reaktiveres Heading
    // Andere Plattformen: 2° Standard
    final deadZoneDegrees = (!kIsWeb && Platform.isIOS) ? 1.5 : 2.0;

    // Bearing-Dead-Zone: Sehr kleine Heading-Änderungen ignorieren (GPS-Rauschen)
    var effectiveHeading = heading;
    final headingDelta = _angleDiff(_lastCameraHeading, heading).abs();
    if (headingDelta < deadZoneDegrees) {
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
    final roundTripStyles = {
      'Kurvenjagd',
      'Sport Mode',
      'Abendrunde',
      'Entdecker',
    };
    final pointToPointStyles = {
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
      if (!isRoundTrip) {
        _planningType = 'Zufall';
        _roundTripWaypoints.clear();
        _roundTripWaypointOrigin = 'manual';
        _roundTripWaypointSeedAttempt = 0;
        _selectedRoundTripWaypointIndex = null;
        _replaceRoundTripWaypointIndex = null;
      }
    });
    _dismissTransientRouteUi();
    _resetGeneratedRouteUiState();
  }

  bool _requiresDestination(bool isRoundTrip) => !isRoundTrip;

  bool get _isWaypointPlanning => _isRoundTrip && _planningType == 'Wegpunkte';

  LatLng? get _pointToPointDestinationMarkerPoint {
    if (_isRoundTrip || _isRouteConfirmed) return null;
    final active = _activeDestinationCoordinate;
    if (active != null && active.length >= 2) {
      return LatLng(active[1], active[0]);
    }
    final selected = _selectedDestination;
    if (selected == null) return null;
    return LatLng(selected.latitude, selected.longitude);
  }

  void _handlePlanningTypeChanged(String planningType) {
    if (_isLoading) return;
    setState(() {
      _planningType = planningType;
      if (planningType == 'Zufall') {
        _roundTripWaypoints.clear();
        _roundTripWaypointOrigin = 'manual';
        _roundTripWaypointSeedAttempt = 0;
        _selectedRoundTripWaypointIndex = null;
        _replaceRoundTripWaypointIndex = null;
      }
    });
    _dismissTransientRouteUi();
    _resetGeneratedRouteUiState();
  }

  String _roundTripWaypointSignature([List<LatLng>? waypoints]) {
    final points = waypoints ?? _roundTripWaypoints;
    if (points.isEmpty) return 'none';
    return points
        .map(
          (point) =>
              '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}',
        )
        .join(';');
  }

  List<LatLng> _deliveredRoundTripWaypointsFromMeta(
    Map<String, dynamic> meta,
  ) {
    final raw =
        meta['delivered_waypoints'] ??
        meta['delivered_required_waypoints'] ??
        meta['required_waypoints_delivered'];
    if (raw is! List) return const [];
    final delivered = <LatLng>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final latRaw = entry['latitude'] ?? entry['lat'];
      final lngRaw = entry['longitude'] ?? entry['lng'] ?? entry['lon'];
      final lat = latRaw is num ? latRaw.toDouble() : null;
      final lng = lngRaw is num ? lngRaw.toDouble() : null;
      if (lat == null || lng == null) continue;
      if (!lat.isFinite || !lng.isFinite) continue;
      if (lat.abs() > 90 || lng.abs() > 180) continue;
      delivered.add(LatLng(lat, lng));
    }
    return delivered.length <= 3 ? delivered : delivered.take(3).toList();
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

    // Wegpunkt-Routen haben keine fixe km-Vorgabe. Der Faktor gibt Mapbox genug
    // Raum für road-snapped Anfahrt statt die versteckte 50-km-Auswahl zu erzwingen.
    final estimatedRoadKm = (straightLineMeters / 1000.0) * 1.28;
    return math.max(fallbackKm, estimatedRoadKm.ceil()).clamp(25, 260).toInt();
  }

  void _invalidateWaypointPreview() {
    final shouldKeepMapFocused = _isWaypointPlanning || _configCollapsed;
    _dismissTransientRouteUi();
    _resetGeneratedRouteUiState();
    if (shouldKeepMapFocused && mounted && !_disposed) {
      setState(() => _configCollapsed = true);
    }
  }

  void _handleMapTap(TapPosition tapPosition, LatLng point) {
    if (!_isWaypointPlanning || _isLoading || _isRouteConfirmed) return;
    final replaceIndex = _replaceRoundTripWaypointIndex;
    if (replaceIndex != null &&
        replaceIndex >= 0 &&
        replaceIndex < _roundTripWaypoints.length) {
      setState(() {
        _roundTripWaypoints[replaceIndex] = point;
        _roundTripWaypointOrigin = 'manual';
        _roundTripWaypointSeedAttempt = 0;
        _selectedRoundTripWaypointIndex = replaceIndex;
        _replaceRoundTripWaypointIndex = null;
      });
      _invalidateWaypointPreview();
      HapticFeedback.selectionClick();
      return;
    }
    if (_roundTripWaypoints.length >= 3) {
      _showError('Maximal 3 Stopps möglich.', isCritical: false);
      return;
    }
    setState(() {
      _roundTripWaypoints.add(point);
      _roundTripWaypointOrigin = 'manual';
      _roundTripWaypointSeedAttempt = 0;
      _selectedRoundTripWaypointIndex = _roundTripWaypoints.length - 1;
      _replaceRoundTripWaypointIndex = null;
    });
    _invalidateWaypointPreview();
    HapticFeedback.selectionClick();
  }

  void _removeLastRoundTripWaypoint() {
    if (_isLoading || _roundTripWaypoints.isEmpty) return;
    setState(() {
      _roundTripWaypoints.removeLast();
      _roundTripWaypointOrigin = 'manual';
      _roundTripWaypointSeedAttempt = 0;
      if (_roundTripWaypoints.isEmpty) {
        _selectedRoundTripWaypointIndex = null;
        _replaceRoundTripWaypointIndex = null;
      } else {
        final selected = _selectedRoundTripWaypointIndex;
        if (selected == null || selected >= _roundTripWaypoints.length) {
          _selectedRoundTripWaypointIndex = _roundTripWaypoints.length - 1;
        }
        final replacing = _replaceRoundTripWaypointIndex;
        if (replacing != null && replacing >= _roundTripWaypoints.length) {
          _replaceRoundTripWaypointIndex = null;
        }
      }
    });
    _invalidateWaypointPreview();
  }

  void _clearRoundTripWaypoints() {
    if (_isLoading || _roundTripWaypoints.isEmpty) return;
    setState(() {
      _roundTripWaypoints.clear();
      _roundTripWaypointOrigin = 'manual';
      _roundTripWaypointSeedAttempt = 0;
      _selectedRoundTripWaypointIndex = null;
      _replaceRoundTripWaypointIndex = null;
    });
    _invalidateWaypointPreview();
  }

  void _selectRoundTripWaypoint(int index) {
    if (_isLoading || index < 0 || index >= _roundTripWaypoints.length) return;
    setState(() {
      _selectedRoundTripWaypointIndex = index;
      _replaceRoundTripWaypointIndex = null;
    });
    HapticFeedback.selectionClick();
  }

  void _deleteRoundTripWaypoint(int index) {
    if (_isLoading || index < 0 || index >= _roundTripWaypoints.length) return;
    setState(() {
      _roundTripWaypoints.removeAt(index);
      _roundTripWaypointOrigin = 'manual';
      _roundTripWaypointSeedAttempt = 0;
      final selected = _selectedRoundTripWaypointIndex;
      if (_roundTripWaypoints.isEmpty) {
        _selectedRoundTripWaypointIndex = null;
      } else if (selected == null) {
        _selectedRoundTripWaypointIndex = null;
      } else if (selected == index) {
        _selectedRoundTripWaypointIndex = math.min(
          index,
          _roundTripWaypoints.length - 1,
        );
      } else if (selected > index) {
        _selectedRoundTripWaypointIndex = selected - 1;
      }
      final replacing = _replaceRoundTripWaypointIndex;
      if (replacing == null || replacing == index) {
        _replaceRoundTripWaypointIndex = null;
      } else if (replacing > index) {
        _replaceRoundTripWaypointIndex = replacing - 1;
      }
    });
    _invalidateWaypointPreview();
    HapticFeedback.selectionClick();
  }

  void _removeSelectedRoundTripWaypoint() {
    final selected = _selectedRoundTripWaypointIndex;
    if (selected == null) return;
    _deleteRoundTripWaypoint(selected);
  }

  void _replaceSelectedRoundTripWaypoint() {
    final selected = _selectedRoundTripWaypointIndex;
    if (_isLoading || selected == null) return;
    if (selected < 0 || selected >= _roundTripWaypoints.length) return;
    setState(() => _replaceRoundTripWaypointIndex = selected);
    _showError(
      'Tippe auf die Karte, um Stopp ${selected + 1} neu zu setzen.',
      isCritical: false,
    );
    HapticFeedback.selectionClick();
  }

  void _generateRoundTripWaypointSeed() {
    if (_isLoading) return;
    unawaited(_generateRoundTripWaypointSeedAsync());
  }

  Future<void> _generateRoundTripWaypointSeedAsync() async {
    geo.Position startPosition;
    try {
      startPosition = await _getStartCoordinates();
    } catch (_) {
      _showError('Aktueller Standort noch nicht verfügbar.', isCritical: true);
      return;
    }
    final center = LatLng(startPosition.latitude, startPosition.longitude);
    final digits = _selectedLength.replaceAll(RegExp(r'[^0-9]'), '');
    final targetKm = digits.isNotEmpty ? int.parse(digits) : 50;
    final nextSeed = _waypointSeedCounter + 1;
    var points = <LatLng>[];
    for (var attempt = 0; attempt < 4; attempt += 1) {
      points = _buildRoundTripWaypointSeed(
        center: center,
        targetKm: targetKm,
        style: _selectedStyle,
        variant: nextSeed + attempt,
      );
      if (_waypointLayoutLooksStable(center, points, targetKm)) break;
    }
    setState(() {
      _waypointSeedCounter = nextSeed;
      _planningType = 'Wegpunkte';
      _roundTripWaypoints
        ..clear()
        ..addAll(points);
      _roundTripWaypointOrigin = 'auto_seed';
      _roundTripWaypointSeedAttempt = nextSeed;
      _selectedRoundTripWaypointIndex = points.isEmpty ? null : 0;
      _replaceRoundTripWaypointIndex = null;
    });
    _invalidateWaypointPreview();
  }

  List<LatLng> _buildRoundTripWaypointSeed({
    required LatLng center,
    required int targetKm,
    required String style,
    required int variant,
  }) {
    final count = style == 'Abendrunde' ? 2 : 3;
    final baseRadiusKm = math.min(
      18.0,
      math.max(4.0, targetKm / (style == 'Abendrunde' ? 8.5 : 6.0)),
    );
    final styleBaseBearing = switch (style) {
      'Kurvenjagd' => 120.0,
      'Entdecker' => 35.0,
      'Abendrunde' => 250.0,
      _ => 75.0,
    };
    final baseBearing = (styleBaseBearing + variant * 47.0) % 360.0;
    final offsets = switch (style) {
      'Kurvenjagd' => const [-82.0, 4.0, 112.0],
      'Entdecker' => const [-82.0, -8.0, 76.0],
      'Abendrunde' => const [-48.0, 62.0],
      _ => const [-54.0, 12.0, 84.0],
    };
    final factors = switch (style) {
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
    if (points.isEmpty || points.length > 3) return false;
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
          if (_shouldShowRoundTripSearchStatus)
            _buildRoundTripSearchStatusOverlay(),

          // Exit-Button wenn wir als Gruppen-Session gestartet wurden
          // (sonst ist man in der Fullscreen-Navigation gefangen).
          if (widget.groupId != null &&
              !_isRouteConfirmed &&
              Navigator.canPop(context))
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 12,
              child: _buildExitButton(),
            ),
        ],
      ),
    );
  }

  bool get _shouldShowRoundTripSearchStatus =>
      _isLoading || _routeSearchNoticeTitle != null;

  Widget _buildRoundTripSearchStatusOverlay() {
    final media = MediaQuery.of(context);
    final isNotice = !_isLoading && _routeSearchNoticeTitle != null;
    final title = _isLoading
        ? (_isPreparingExistingRoute
              ? 'Route wird vorbereitet'
              : _isWaypointPlanning
              ? 'Wegpunkte werden verbunden'
              : !_isRoundTrip
              ? 'Route wird berechnet'
              : 'Rundkurs wird berechnet')
        : _routeSearchNoticeTitle!;
    final status = _isLoading
        ? _routeLoadingStatusText
        : (_routeSearchNoticeMessage ??
              'Gerade keine gute Route gefunden. Wir suchen weiter im Hintergrund.');
    final progressValue = isNotice ? 1.0 : _routeSearchProgress;

    return Positioned(
      top: media.padding.top + 10,
      left: 14,
      right: 14,
      child: IgnorePointer(
        ignoring: true,
        child: Align(
          alignment: Alignment.topCenter,
          child: _buildCompactRoundTripSearchStatus(
            title: title,
            status: status,
            progress: progressValue,
            isNotice: isNotice,
            maxWidth: math.min(media.size.width - 28, 370),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactRoundTripSearchStatus({
    required String title,
    required String status,
    required double progress,
    required bool isNotice,
    required double maxWidth,
  }) {
    final accent = AppAccentColors.accent;
    final clampedProgress = progress.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      key: const ValueKey('roundtrip-search-compact'),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(end: clampedProgress),
      builder: (context, animatedProgress, _) {
        return Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xE8151820),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.46),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.22),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.34),
                              ),
                            ),
                            child: isNotice
                                ? Icon(
                                    CupertinoIcons.check_mark_circled,
                                    color: accent,
                                    size: 18,
                                  )
                                : CupertinoActivityIndicator(
                                    radius: 8,
                                    color: accent,
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  status,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    fontSize: 12,
                                    height: 1.15,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.05,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${(animatedProgress * 100).clamp(0, 100).round()}%',
                            style: TextStyle(
                              color: accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          height: 4,
                          color: Colors.white.withValues(alpha: 0.10),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: animatedProgress.clamp(0.03, 1.0),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.48),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExitButton() {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () async {
          final leave = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1C1F26),
              title: const Text(
                'Gruppenfahrt verlassen?',
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                'Du verlässt die Navigation. Die Gruppe läuft für andere weiter.',
                style: TextStyle(color: Colors.grey),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Abbrechen'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    'Verlassen',
                    style: TextStyle(color: AppAccentColors.accent),
                  ),
                ),
              ],
            ),
          );
          if (leave == true && mounted) Navigator.of(context).pop();
        },
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildWaypointMapControls() {
    final media = MediaQuery.of(context);
    final top =
        media.padding.top + (_shouldShowRoundTripSearchStatus ? 96 : 88);
    final selected = _selectedRoundTripWaypointIndex;
    final replacing = _replaceRoundTripWaypointIndex;
    final subtitle = replacing != null
        ? 'Neu'
        : _roundTripWaypoints.isEmpty
        ? 'Stopps'
        : '${_roundTripWaypoints.length}/3';
    return Positioned(
      top: top,
      right: 14,
      child: SafeArea(
        top: false,
        bottom: false,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: 72,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xE0141720),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppAccentColors.accent.withValues(alpha: 0.34),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: AppAccentColors.accent.withValues(alpha: 0.14),
                    blurRadius: 22,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppAccentColors.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: AppAccentColors.accent.withValues(alpha: 0.36),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${_roundTripWaypoints.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildWaypointMapAction(
                    icon: CupertinoIcons.sparkles,
                    label: 'Vorschlagen',
                    onTap: _isLoading ? null : _generateRoundTripWaypointSeed,
                  ),
                  _buildWaypointMapAction(
                    icon: CupertinoIcons.arrow_uturn_left,
                    label: 'Zurück',
                    onTap: !_isLoading && _roundTripWaypoints.isNotEmpty
                        ? _removeLastRoundTripWaypoint
                        : null,
                  ),
                  _buildWaypointMapAction(
                    icon: CupertinoIcons.location_solid,
                    label: 'Neu setzen',
                    onTap: !_isLoading && selected != null
                        ? _replaceSelectedRoundTripWaypoint
                        : null,
                  ),
                  _buildWaypointMapAction(
                    icon: CupertinoIcons.trash,
                    label: 'Löschen',
                    onTap: !_isLoading && selected != null
                        ? _removeSelectedRoundTripWaypoint
                        : null,
                    destructive: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaypointMapAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool destructive = false,
  }) {
    final enabled = onTap != null;
    final accent = destructive
        ? const Color(0xFFFF6B5F)
        : AppAccentColors.accent;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(17),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: enabled
                    ? accent.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: enabled
                      ? accent.withValues(alpha: 0.35)
                      : Colors.white10,
                ),
              ),
              child: Icon(
                icon,
                size: 18,
                color: enabled ? Colors.white : Colors.white30,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaypointStyleDock() {
    final media = MediaQuery.of(context);
    const styles = ['Sport Mode', 'Kurvenjagd', 'Abendrunde', 'Entdecker'];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        0,
        18,
        math.max(6, media.padding.bottom * 0.10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xE0141720),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  for (final style in styles) ...[
                    _buildWaypointStyleChip(style),
                    if (style != styles.last) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaypointStyleChip(String style) {
    final selected = _selectedStyle == style;
    final accent = AppAccentColors.accent;
    final icon = switch (style) {
      'Kurvenjagd' => CupertinoIcons.waveform_path,
      'Abendrunde' => CupertinoIcons.moon_stars,
      'Entdecker' => CupertinoIcons.compass,
      _ => CupertinoIcons.speedometer,
    };
    return GestureDetector(
      onTap: _isLoading
          ? null
          : () {
              HapticFeedback.selectionClick();
              setState(() => _selectedStyle = style);
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.60) : Colors.white10,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: selected ? accent : Colors.white54),
            const SizedBox(width: 7),
            Text(
              style,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.05,
              ),
            ),
          ],
        ),
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
            _buildRoutePreviewHeader(),
          if (_isWaypointPlanning && !_showRouteInfoBanner)
            _buildWaypointMapControls(),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isWaypointPlanning && !_showRouteInfoBanner)
                  _buildWaypointStyleDock(),
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
                        onPlanningTypeChanged: _handlePlanningTypeChanged,
                        onLengthChanged: (v) {
                          debugPrint('[RouteDebug][UIState] selectedKm=$v');
                          setState(() => _selectedLength = v);
                        },
                        onLocationChanged: (v) =>
                            setState(() => _selectedLocation = v),
                        onStyleChanged: (v) {
                          debugPrint('[RouteDebug][UIState] selectedStyle=$v');
                          setState(() => _selectedStyle = v);
                        },
                        selectedDetour: _selectedDetour,
                        onDetourChanged: _handleDetourChanged,
                        selectedAvoidHighways: _avoidHighways,
                        proximityLatitude: _userLocation?.latitude,
                        proximityLongitude: _userLocation?.longitude,
                        onAvoidHighwaysChanged: (value) {
                          debugPrint(
                            '[RouteDebug][UIState] avoidHighways=$value',
                          );
                          setState(() => _avoidHighways = value);
                        },
                        onDestinationSelected: _onDestinationSelected,
                        onDestinationInputChanged:
                            _handleDestinationInputChanged,
                        roundTripWaypointCount: _roundTripWaypoints.length,
                        selectedWaypointIndex: _selectedRoundTripWaypointIndex,
                        replacingWaypointIndex: _replaceRoundTripWaypointIndex,
                        waypointActionsEnabled: !_isLoading,
                        onGenerateWaypointSeed: _generateRoundTripWaypointSeed,
                        onRemoveLastWaypoint: _removeLastRoundTripWaypoint,
                        onDeleteSelectedWaypoint:
                            _selectedRoundTripWaypointIndex == null
                            ? null
                            : _removeSelectedRoundTripWaypoint,
                        onReplaceSelectedWaypoint:
                            _selectedRoundTripWaypointIndex == null
                            ? null
                            : _replaceSelectedRoundTripWaypoint,
                        onClearWaypoints: _clearRoundTripWaypoints,
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
          _buildRoutePreviewHeader(),
        Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomActions()),
      ],
    );
  }

  Widget _buildRoutePreviewHeader() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRoutePreviewBackButton(),
          const SizedBox(width: 10),
          Expanded(child: _buildRouteInfoBanner()),
        ],
      ),
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
          color: AppAccentColors.accent.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Route berechnet',
            style: TextStyle(
              color: AppAccentColors.accent,
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
        Icon(icon, color: AppAccentColors.accent, size: 20),
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
    final topInset = MediaQuery.of(context).padding.top;
    return Stack(
      children: [
        if (_maneuvers.isNotEmpty)
          Positioned(
            top: topInset + 8,
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
                    ? AppAccentColors.accent
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
                    await _startNavigationFlow();
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

  Widget _buildRoutePreviewBackButton() {
    final accent = AppAccentColors.accent;
    return Semantics(
      button: true,
      label: 'Zurück zum Strecken-Setup',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: const Color(0xE8151820),
            child: InkWell(
              onTap: _returnToCruiseSetupFromActiveRoute,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.48),
                    width: 1.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(
                  CupertinoIcons.chevron_left,
                  color: Colors.white.withValues(alpha: 0.96),
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════ MAP WIDGET (flutter_map) ════════════════════════

  Widget _buildMapWidget() {
    final pointToPointDestination = _pointToPointDestinationMarkerPoint;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        // Startpunkt: Mitte Deutschlands (wird bei GPS-Erlaubnis sofort überschrieben)
        initialCenter: const LatLng(51.165691, 10.451526),
        initialZoom: 6.0,
        onMapReady: _onMapReady,
        onTap: _handleMapTap,
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
                  color: AppAccentColors.accent.withValues(alpha: 0.30),
                  strokeWidth: 12,
                ),
              // Haupt-Routenlinie
              Polyline(
                points: _routeLatLngs,
                color: AppAccentColors.accent,
                strokeWidth: kIsWeb ? 4 : 5,
              ),
            ],
          ),
        // ── Standort-Marker ──────────────────────────────────────────────
        if (_userLocation != null && !_isRouteConfirmed)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(
                  _userLocation!.latitude,
                  _userLocation!.longitude,
                ),
                width: _puckSize,
                height: _puckSize,
                child: _buildLocationPuck(_userHeading),
              ),
            ],
          ),
        if (_isWaypointPlanning && _roundTripWaypoints.isNotEmpty)
          MarkerLayer(
            markers: [
              for (var i = 0; i < _roundTripWaypoints.length; i++)
                Marker(
                  point: _roundTripWaypoints[i],
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: _isLoading
                        ? null
                        : () => _selectRoundTripWaypoint(i),
                    onLongPress: _isLoading
                        ? null
                        : () => _deleteRoundTripWaypoint(i),
                    child: _buildWaypointMarker(
                      i + 1,
                      selected: _selectedRoundTripWaypointIndex == i,
                      replacing: _replaceRoundTripWaypointIndex == i,
                    ),
                  ),
              ),
            ],
          ),
        if (pointToPointDestination != null)
          MarkerLayer(
            markers: [
              Marker(
                point: pointToPointDestination,
                width: 44,
                height: 44,
                child: _buildDestinationMarker(),
              ),
            ],
          ),
        // ── User-Position Marker (Live-Navigation) ─────────────────────────
        if (_userPosition != null && _isRouteConfirmed)
          MarkerLayer(
            markers: [
              Marker(
                point: _userPosition!,
                width: _puckSize,
                height: _puckSize,
                child: _buildLocationPuck(_userHeading),
              ),
            ],
          ),
        // ── Gruppen-Mitglieder (Live-Positionen) ────────────────────────────
        if (widget.groupId != null && _groupMembers.isNotEmpty)
          MarkerLayer(
            markers: _groupMembers.values
                .where(_hasFreshGroupMemberLocation)
                .map(
                  (m) => Marker(
                    point: LatLng(m.currentLat!, m.currentLng!),
                    width: 40,
                    height: 40,
                    child: _buildGroupMemberMarker(m),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  // ═══════════════════════ MAP LIFECYCLE ═════════════════════════════════════

  /// Wird von flutter_map aufgerufen wenn die Karte bereit ist.
  void _onMapReady() {
    debugPrint(
      '[CruiseMode] _onMapReady called, routeGeoJson=${_routeGeoJson != null}, routeLatLngs=${_routeLatLngs.length}',
    );
    _mapReady = true;
    // Route zeichnen falls schon vorhanden, sonst GPS-Position holen
    if (_routeGeoJson != null) {
      final geometry = Map<String, dynamic>.from(
        json.decode(_routeGeoJson!) as Map,
      );
      debugPrint('[CruiseMode] _onMapReady: Zeichne vorhandene Route');
      _drawRoute(geometry);
      if (_isRouteConfirmed) _activateNavigationCamera();
    } else if (_routeLatLngs.isNotEmpty) {
      // Fallback: Route-LatLngs sind bereits gesetzt aber routeGeoJson fehlt
      debugPrint(
        '[CruiseMode] _onMapReady: routeLatLngs bereits vorhanden (${_routeLatLngs.length} Punkte)',
      );
      // Kein _drawRoute nötig da _routeLatLngs bereits im State ist
      if (_isRouteConfirmed) _activateNavigationCamera();
    } else {
      _initializeMapLocation();
    }
  }

  // ═══════════════════════ BOTTOM ACTIONS ═══════════════════════════════════

  Widget _buildBottomActions() {
    final hasConfirmableRoute =
        _lastRouteResult != null &&
        (_fullRouteCoordinates.length >= 2 ||
            _routeLatLngs.length >= 2 ||
            _routeGeoJson != null);
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
            if (hasConfirmableRoute)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _confirmRoute,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppAccentColors.accent,
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
                    color:
                        (_isLoading
                                ? const Color(0xFFFF453A)
                                : AppAccentColors.accent)
                            .withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? _cancelRouteGeneration : _generateRoute,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isLoading
                      ? const Color(0xFFB9443A)
                      : AppAccentColors.accent,
                  disabledBackgroundColor: AppAccentColors.accent.withValues(
                    alpha: 0.42,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const Text(
                        'Suche abbrechen',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : Text(
                        _isWaypointPlanning
                            ? 'Wegpunkt-Route suchen'
                            : _isRoundTrip
                            ? 'Rundkurs suchen'
                            : 'Route berechnen',
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

  Widget _buildWaypointMarker(
    int index, {
    bool selected = false,
    bool replacing = false,
  }) {
    final color = replacing
        ? const Color(0xFFFFC107)
        : selected
        ? Colors.white
        : AppAccentColors.accent;
    final coreColor = replacing
        ? const Color(0xFFFFC107)
        : selected
        ? AppAccentColors.accent
        : const Color(0xFF121823);
    return AnimatedScale(
      duration: const Duration(milliseconds: 160),
      scale: selected || replacing ? 1.12 : 1.0,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            bottom: 1,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  color: coreColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: color.withValues(alpha: 0.80)),
                ),
              ),
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: coreColor,
              border: Border.all(
                color: color,
                width: selected || replacing ? 2.8 : 2.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: selected ? 0.50 : 0.34),
                  blurRadius: selected || replacing ? 18 : 13,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.32),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationMarker() {
    final color = AppAccentColors.accent;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Positioned(
          bottom: 1,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: const Color(0xFF101722),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withValues(alpha: 0.72)),
              ),
            ),
          ),
        ),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF101722),
            border: Border.all(color: color, width: 2.3),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.34),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.34),
                blurRadius: 9,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(Icons.flag_rounded, color: color, size: 19),
        ),
      ],
    );
  }

  Widget _buildLocationPuck(double headingDegrees) {
    if (!kIsWeb && Platform.isIOS) {
      return _buildiOSLocationPuck(headingDegrees);
    }
    return _buildDefaultLocationPuck(headingDegrees);
  }

  /// iOS Apple-Maps-Style Puck: Kompakter blauer Punkt mit kleinem
  /// Richtungskeil — exakt wie in Apple Karten (Foto 2+3).
  Widget _buildiOSLocationPuck(double headingDegrees) {
    return SizedBox(
      width: 44,
      height: 44,
      child: AnimatedRotation(
        turns: headingDegrees / 360.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        child: CustomPaint(
          size: const Size(44, 44),
          painter: _AppleMapsPuckPainter(),
        ),
      ),
    );
  }

  /// Standard-Puck für Web / Android / macOS (bisheriges Design).
  Widget _buildDefaultLocationPuck(double headingDegrees) {
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
            // Plattformspezifisches Smoothing
            if (kIsWeb) {
              // Web: Smoother anwenden für flüssige Darstellung
              final smoothed = _webSmoother.update(position);
              // Heading trotzdem immer aktualisieren (auch ohne Positions-Rebuild)
              _userHeading = _webSmoother.heading;
              if (smoothed != null) {
                _userLocation = smoothed;
              }
            } else {
              // iOS/Android: Native Smoother mit Heading-Fusion
              final smoothed = _nativeSmoother.update(position);
              // Geglättetes Heading verwenden (fusioniert GPS + Bewegung)
              if (_nativeSmoother.hasValidHeading) {
                _userHeading = _nativeSmoother.heading;
              }
              // Position aktualisieren
              if (smoothed != null) {
                _userLocation = smoothed;
              } else {
                // Auch bei Stillstand: Heading-Updates zulassen
                _userLocation = position;
              }
            }
            // Idle-Rebuilds auf 16ms throttlen: max. ein Rebuild pro Frame.
            final now = DateTime.now();
            if (_lastWebRebuildTime != null &&
                now.difference(_lastWebRebuildTime!).inMilliseconds < 16) {
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

  bool _hasUsableLocationPermission(geo.LocationPermission permission) {
    return permission == geo.LocationPermission.whileInUse ||
        permission == geo.LocationPermission.always;
  }

  void _showNavigationPermissionSnack(String message, Color backgroundColor) {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<bool> _showLocationPermissionDialog({
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'Abbrechen',
  }) async {
    if (!mounted || _disposed) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _ensureNavigationLocationPermission() async {
    if (kIsWeb) return true;

    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!mounted || _disposed) return false;
    if (!serviceEnabled) {
      final openSettings = await _showLocationPermissionDialog(
        title: 'Standort aktivieren',
        message: 'Für die Navigation muss GPS auf deinem Gerät aktiviert sein.',
        confirmLabel: 'Standort öffnen',
      );
      if (openSettings) {
        unawaited(geo.Geolocator.openLocationSettings());
      }
      return false;
    }

    var permission = await geo.Geolocator.checkPermission();
    if (!mounted || _disposed) return false;
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      if (!mounted || _disposed) return false;
    }

    if (permission == geo.LocationPermission.deniedForever) {
      final openSettings = await _showLocationPermissionDialog(
        title: 'Standort blockiert',
        message:
            'Bitte erlaube CruiseConnect den Standortzugriff in den App-Einstellungen.',
        confirmLabel: 'Einstellungen öffnen',
      );
      if (openSettings) {
        unawaited(geo.Geolocator.openAppSettings());
      }
      return false;
    }

    if (!_hasUsableLocationPermission(permission)) {
      _showNavigationPermissionSnack(
        'Standortberechtigung wurde nicht erteilt.',
        AppAccentColors.accent,
      );
      return false;
    }

    if (widget.groupId == null) return true;
    return _ensureBackgroundLocationPermission(permission);
  }

  Future<bool> _ensureBackgroundLocationPermission(
    geo.LocationPermission currentPermission,
  ) async {
    if (currentPermission == geo.LocationPermission.always) return true;

    final shouldAskForBackground = await _showLocationPermissionDialog(
      title: 'Standort im Hintergrund?',
      message:
          'Damit deine Gruppenfahrt weiterläuft, wenn du z. B. zu Spotify wechselst, braucht CruiseConnect die Freigabe "Immer erlauben".',
      confirmLabel: Platform.isIOS || Platform.isMacOS
          ? 'Einstellungen öffnen'
          : 'Jetzt erlauben',
      cancelLabel: 'Nur in App',
    );
    if (!mounted || _disposed) return false;

    if (!shouldAskForBackground) {
      _showNavigationPermissionSnack(
        'Gruppenfahrt startet. Im Hintergrund läuft Tracking erst mit "Immer erlauben".',
        const Color(0xFFFF9500),
      );
      return true;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      unawaited(geo.Geolocator.openAppSettings());
      return false;
    }

    var permission = await geo.Geolocator.requestPermission();
    if (!mounted || _disposed) return false;
    if (permission == geo.LocationPermission.always) return true;

    final openSettings = await _showLocationPermissionDialog(
      title: '"Immer erlauben" fehlt noch',
      message:
          'Falls Android keinen passenden Dialog gezeigt hat, setze den Standortzugriff in den App-Einstellungen auf "Immer erlauben".',
      confirmLabel: 'Einstellungen öffnen',
      cancelLabel: 'Nur in App',
    );
    if (!mounted || _disposed) return false;

    if (openSettings) {
      unawaited(geo.Geolocator.openAppSettings());
      return false;
    }

    _showNavigationPermissionSnack(
      'Gruppenfahrt startet. Im Hintergrund läuft Tracking erst mit "Immer erlauben".',
      const Color(0xFFFF9500),
    );
    return true;
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
    final generationId = ++_routeGenerationSerial;
    final previousUiState = _captureGeneratedRouteUiState();
    _dismissTransientRouteUi();
    _startRouteLoadingUi(generationId: generationId);

    // Hintergrund-Generierung pausieren während User aktiv generiert
    RouteCacheService.beginUserGeneration();

    var requestedDistance = 50;
    String? requestedWaypointSignature;
    try {
      final startPosition = await _getStartCoordinates();
      if (_isRouteGenerationCancelled(generationId)) return;

      final digits = _selectedLength.replaceAll(RegExp(r'[^0-9]'), '');
      var distance = digits.isNotEmpty ? int.parse(digits) : 50;
      final waypointSnapshot = List<LatLng>.unmodifiable(_roundTripWaypoints);
      final waypointSignature = _isWaypointPlanning
          ? _roundTripWaypointSignature(waypointSnapshot)
          : null;
      requestedWaypointSignature = waypointSignature;
      if (_isWaypointPlanning &&
          (waypointSnapshot.isEmpty || waypointSnapshot.length > 3)) {
        _restoreGeneratedRouteFailureUi(
          previousUiState,
          waypointSnapshot.isEmpty
              ? 'Setze mindestens einen Stopp oder lass Vorschläge erzeugen.'
              : 'Bitte nutze maximal 3 Stopps.',
          error: RouteServiceException(
            type: RouteErrorType.validation,
            userMessage: waypointSnapshot.isEmpty
                ? 'Setze mindestens einen Stopp oder lass Vorschläge erzeugen.'
                : 'Bitte nutze maximal 3 Stopps.',
            debugMessage:
                'Invalid UI waypoint count=${waypointSnapshot.length}.',
            edgeMeta: {
              'response_code': waypointSnapshot.isEmpty
                  ? 'too_few_waypoints'
                  : 'too_many_waypoints',
            },
          ),
        );
        return;
      }
      if (_isWaypointPlanning) {
        distance = _estimateWaypointRouteTargetKm(
          startPosition: startPosition,
          waypoints: waypointSnapshot,
          fallbackKm: distance,
        );
      }
      requestedDistance = distance;
      final forceFreshVariant = previousUiState.lastRouteResult != null;
      final settingsChanged =
          previousUiState.lastRouteResult != null &&
          (_lastGeneratedWasRoundTrip != _isRoundTrip ||
              (_isRoundTrip &&
                  (_lastGeneratedSelectedKm != distance ||
                      _lastGeneratedSelectedStyle != _selectedStyle ||
                      _lastGeneratedAvoidHighways != _avoidHighways ||
                      _lastGeneratedWaypointSignature != waypointSignature)) ||
              (!_isRoundTrip &&
                  (_lastGeneratedSelectedStyle != _selectedStyle ||
                      _lastGeneratedAvoidHighways != _avoidHighways)));
      final routeDebugTrigger = previousUiState.lastRouteResult == null
          ? 'firstSearch'
          : settingsChanged
          ? 'settingsChanged'
          : 'searchAgain';
      debugPrint(
        '[RouteDebug][UI] selectedKm=$distance selectedStyle=$_selectedStyle '
        'avoidHighways=$_avoidHighways forceFreshVariant=$forceFreshVariant '
        'trigger=$routeDebugTrigger '
        'routeType=${_isRoundTrip ? 'ROUND_TRIP' : 'POINT_TO_POINT'} '
        'planningType=$_planningType selectedLength=$_selectedLength '
        'waypointCount=${waypointSnapshot.length} '
        'waypointSignature=${waypointSignature ?? 'none'} '
        'selectedLocation=$_selectedLocation '
        'useCurrentLocation=${_selectedLocation == 'Aktueller Standort'} '
        'startLat=${startPosition.latitude.toStringAsFixed(5)} '
        'startLng=${startPosition.longitude.toStringAsFixed(5)} '
        'clientRoutingBuildId=${RouteService.clientRoutingBuildId} '
        'clientRoutingBuildTime=${RouteService.clientRoutingBuildTime}',
      );
      double? destLat;
      double? destLng;
      var detourVariant = 0;
      var scenicMode = false;

      Map<String, double>? targetLocation;
      if (_requiresDestination(_isRoundTrip) &&
          _selectedDestination == null &&
          _destinationController.text.isNotEmpty) {
        try {
          targetLocation = await _geocodingService.getCoordinatesFromAddress(
            _destinationController.text,
            proximityLatitude: startPosition.latitude,
            proximityLongitude: startPosition.longitude,
            requireUnambiguous: true,
          );
          if (_isRouteGenerationCancelled(generationId)) return;
        } on GeocodingException catch (e) {
          debugPrint('[CruiseMode] Geocoding failed: ${e.debugMessage}');
          if (_isRouteGenerationCancelled(generationId)) return;
          _restoreGeneratedRouteFailureUi(
            previousUiState,
            e.userMessage,
            error: e,
          );
          return;
        }
        if (targetLocation == null && mounted) {
          _restoreGeneratedRouteFailureUi(
            previousUiState,
            'Konnte Zieladresse nicht finden.',
          );
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
          _restoreGeneratedRouteFailureUi(
            previousUiState,
            'Bitte wähle ein Ziel aus der Vorschlagsliste aus.',
          );
          return;
        }
        final destinationDistanceMeters = geo.Geolocator.distanceBetween(
          startPosition.latitude,
          startPosition.longitude,
          destLat,
          destLng,
        );
        if (destinationDistanceMeters < 250) {
          _restoreGeneratedRouteFailureUi(
            previousUiState,
            'Start und Ziel liegen zu nah beieinander.',
          );
          return;
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
        final p2pDiversitySeed = Object.hash(
          destLat.round(),
          destLng.round(),
          detourVariant,
          _avoidHighways,
          forceFreshVariant,
        );
        final subscriptionTier = RouteService.resolveEffectiveSubscriptionTier(
          isTesterOrBeta: true,
        );
        result = await _routeService.generatePointToPoint(
          startPosition: startPosition,
          destinationLat: destLat,
          destinationLng: destLng,
          mode: scenicMode ? _selectedStyle : 'Standard',
          scenic: scenicMode,
          routeVariant: detourVariant,
          avoidHighways: _avoidHighways,
          diversitySeed: p2pDiversitySeed,
          forceFreshVariant: forceFreshVariant,
          subscriptionTier: subscriptionTier,
        );
      } else {
        _activeDestinationCoordinate = null;
        _activeDetourVariant = 0;
        _activePointToPointScenic = false;
        _activePointToPointMode = 'Standard';
        _activeAvoidHighways = _avoidHighways;
        _recentDestinationDistances = [];
        final subscriptionTier = RouteService.resolveEffectiveSubscriptionTier(
          isTesterOrBeta: true,
        );
        result = await _routeService.generateRoundTrip(
          startPosition: startPosition,
          targetDistanceKm: distance,
          mode: _selectedStyle,
          planningType: _planningType,
          waypointOrigin: _isWaypointPlanning
              ? _roundTripWaypointOrigin
              : null,
          waypointSeedAttempt: _isWaypointPlanning
              ? _roundTripWaypointSeedAttempt
              : null,
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
          debugTrigger: routeDebugTrigger,
          subscriptionTier: subscriptionTier,
        );
      }

      if (_isRouteGenerationCancelled(generationId)) {
        debugPrint(
          '[CruiseMode] Route generation result ignored after user cancel.',
        );
        return;
      }
      await _acceptGeneratedRouteResult(
        result: result,
        startPosition: startPosition,
        distance: distance,
        waypointSignature: waypointSignature,
      );
    } catch (e, stack) {
      debugPrint('[CruiseMode] Route generation failed: $e');
      debugPrintStack(
        label: '[CruiseMode] Route generation stacktrace',
        stackTrace: stack,
      );
      if (_isRouteGenerationCancelled(generationId)) {
        debugPrint(
          '[CruiseMode] Route generation error ignored after user cancel.',
        );
        return;
      }
      Object errorForUi = e;
      if (e is RouteServiceException && _isSearchInProgressError(e)) {
        final sessionId = e.edgeMeta['search_session_id']?.toString();
        if (sessionId != null && sessionId.isNotEmpty) {
          _logRoundTripSearchUiDecision(
            'poll_start',
            error: e,
            sessionId: sessionId,
          );
          try {
            final polled = await _pollRoundTripSearchSession(
              sessionId,
              generationId: generationId,
            );
            if (_isRouteGenerationCancelled(generationId)) return;
            if (polled != null) {
              _logRoundTripSearchUiDecision(
                'route_accepted_from_poll',
                sessionId: sessionId,
                result: polled,
              );
              await _acceptGeneratedRouteResult(
                result: polled,
                startPosition: await _getStartCoordinates(),
                distance: requestedDistance,
                waypointSignature: requestedWaypointSignature,
              );
              return;
            }
            _logRoundTripSearchUiDecision(
              'poll_timeout_notice',
              error: e,
              sessionId: sessionId,
            );
            errorForUi = RouteServiceException(
              type: RouteErrorType.noRoute,
              userMessage:
                  'Wir prüfen weitere Routenvorschläge im Hintergrund. Bitte versuche es gleich erneut.',
              debugMessage:
                  'Persistent search session polling timed out: $sessionId.',
              edgeMeta: {
                ...e.edgeMeta,
                'response_code': 'search_session_timeout',
                'search_in_progress': false,
                'background_learning_queued': true,
              },
            );
          } catch (pollError, pollStack) {
            debugPrint(
              '[CruiseMode] Search session polling failed: $pollError',
            );
            debugPrintStack(
              label: '[CruiseMode] Search session polling stacktrace',
              stackTrace: pollStack,
            );
            errorForUi = pollError;
          }
        }
      }
      final errorMessage = errorForUi is RouteServiceException
          ? errorForUi.userMessage
          : 'Route konnte nicht generiert werden. Bitte versuche es erneut.';
      _restoreGeneratedRouteFailureUi(
        previousUiState,
        errorMessage,
        error: errorForUi,
      );
    } finally {
      // Hintergrund-Generierung wieder erlauben
      RouteCacheService.endUserGeneration();
      _stopRouteLoadingUi(generationId: generationId);
    }
  }

  Future<RouteResult?> _pollRoundTripSearchSession(
    String sessionId, {
    required int generationId,
  }) async {
    const maxPolls = 45;
    DateTime? lastWorkerKickAt;
    for (var poll = 0; poll < maxPolls; poll += 1) {
      if (_isRouteGenerationCancelled(generationId)) return null;
      await Future.delayed(const Duration(seconds: 4));
      if (_isRouteGenerationCancelled(generationId)) return null;
      _logRoundTripSearchUiDecision(
        'poll_attempt',
        sessionId: sessionId,
        pollAttempt: poll + 1,
      );
      final result = await _routeService.pollRoundTripSearchSession(sessionId);
      if (_isRouteGenerationCancelled(generationId)) return null;
      if (result != null) {
        _logRoundTripSearchUiDecision(
          'poll_found',
          sessionId: sessionId,
          pollAttempt: poll + 1,
          result: result,
        );
        return result;
      }
      final pollMeta = _routeService.lastRoundTripSearchSessionMeta;
      _logRoundTripSearchUiDecision(
        'poll_pending',
        sessionId: sessionId,
        pollAttempt: poll + 1,
      );
      final shouldKick = _shouldKickStaleRoundTripSearchSession(
        pollMeta,
        pollIndex: poll,
      );
      final now = DateTime.now();
      if (shouldKick &&
          (lastWorkerKickAt == null ||
              now.difference(lastWorkerKickAt) >=
                  const Duration(seconds: 12))) {
        lastWorkerKickAt = now;
        _logRoundTripSearchUiDecision(
          'worker_kick_scheduled',
          sessionId: sessionId,
          pollAttempt: poll + 1,
        );
        unawaited(
          _routeService.kickRoundTripSearchSession(
            sessionId,
            reason: 'client_poll_stale',
          ),
        );
      }
      if (mounted && !_disposed) {
        setState(() {
          final pollProgress = 0.34 + ((poll + 1) / maxPolls) * 0.56;
          _routeSearchProgress = math.max(
            _routeSearchProgress,
            math.min(pollProgress, 0.94),
          );
          _routeLoadingPhaseIndex = math.min(
            math.max(_routeLoadingPhaseIndex, 2) + (poll % 4 == 0 ? 1 : 0),
            _roundTripLoadingPhases.length - 1,
          );
        });
      }
    }
    _logRoundTripSearchUiDecision('poll_exhausted', sessionId: sessionId);
    return null;
  }

  void _logRoundTripSearchUiDecision(
    String decision, {
    RouteServiceException? error,
    String? sessionId,
    int? pollAttempt,
    RouteResult? result,
  }) {
    final meta =
        result?.edgeMeta ??
        error?.edgeMeta ??
        _routeService.lastRoundTripSearchSessionMeta ??
        const <String, dynamic>{};
    debugPrint(
      '[RouteDebug][UIHandoff] decision=$decision '
      'clientRoutingBuildId=${RouteService.clientRoutingBuildId} '
      'session_id=${sessionId ?? meta['search_session_id']} '
      'poll_attempt=${pollAttempt ?? '-'} '
      'response_code=${meta['response_code'] ?? meta['code']} '
      'search_session_status=${meta['search_session_status']} '
      'on_demand_worker_triggered=${meta['on_demand_worker_triggered']} '
      'worker_last_seen_at=${meta['worker_last_seen_at']} '
      'attempts=${meta['attempts_count']} '
      'source=${meta['route_source'] ?? meta['source']} '
      'final_geometry_source=${meta['final_geometry_source'] ?? meta['geometry_source']} '
      'coordinate_count=${result?.coordinates.length ?? meta['final_coordinate_count'] ?? meta['coordinate_count']} '
      'ui_loading=$_isLoading',
    );
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
    final isWaitingStatus =
        status == 'queued' || status == 'running' || status == 'hydrating';
    return isWaitingStatus &&
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

  Future<void> _acceptGeneratedRouteResult({
    required RouteResult result,
    required geo.Position startPosition,
    required int distance,
    required String? waypointSignature,
  }) async {
    if (!mounted || _disposed) return;
    final prepared = await _prepareRouteForPreviewStart(
      result: result,
      startPosition: startPosition,
      isRoundTrip: _isRoundTrip,
      avoidHighways: _avoidHighways,
    );

    const validator = RouteQualityValidator();
    final actualKm = prepared.distanceKm ?? 0.0;
    final targetKm = _isWaypointPlanning
        ? actualKm
        : _isRoundTrip
        ? distance.toDouble()
        : 0.0;
    final quality = validator.validateQuality(
      coordinates: prepared.coordinates,
      isRoundTrip: _isRoundTrip,
      targetDistanceKm: targetKm,
      actualDistanceKm: actualKm,
    );
    final routeClassification = validator.classifyGeneratedRoute(
      quality: quality,
      isRoundTrip: _isRoundTrip,
      coordinateCount: prepared.coordinates.length,
      actualDistanceKm: actualKm,
      targetDistanceKm: targetKm,
    );
    debugPrint(
      '[CruiseMode] Route erhalten: '
      'tier=${routeClassification.tier}, '
      'score=${routeClassification.score.toStringAsFixed(1)}, '
      'distance=${actualKm.toStringAsFixed(1)}km, '
      'overlap=${quality.overlapPercent.toStringAsFixed(1)}%, '
      'uturns=${quality.uturnPositions.length}',
    );

    debugPrint(
      '[CruiseMode] Applying route result: ${prepared.coordinates.length} coords',
    );
    final deliveredWaypoints =
        _isWaypointPlanning && _roundTripWaypointOrigin == 'auto_seed'
        ? _deliveredRoundTripWaypointsFromMeta(prepared.edgeMeta)
        : const <LatLng>[];
    _applyRouteResult(prepared);
    _hideRouteSearchStatusForAcceptedRoute();
    _lastGeneratedWasRoundTrip = _isRoundTrip;
    _lastGeneratedSelectedKm = _isRoundTrip ? distance : null;
    _lastGeneratedSelectedStyle = _selectedStyle;
    _lastGeneratedAvoidHighways = _avoidHighways;
    _lastGeneratedWaypointSignature = deliveredWaypoints.isNotEmpty
        ? _roundTripWaypointSignature(deliveredWaypoints)
        : waypointSignature;

    if (mounted) {
      debugPrint('[CruiseMode] Route preview ready, showing confirm state');
      setState(() {
        if (deliveredWaypoints.isNotEmpty) {
          _roundTripWaypoints
            ..clear()
            ..addAll(deliveredWaypoints);
          _selectedRoundTripWaypointIndex = 0;
          _replaceRoundTripWaypointIndex = null;
        }
        _configCollapsed = true;
        _showRouteInfoBanner = true;
      });
    }

    debugPrint('[CruiseMode] Drawing route...');
    try {
      await _drawRoute(prepared.geometry, animateRouteDraw: true);
    } catch (drawError, drawStack) {
      debugPrint('[CruiseMode] Route drawing failed after accept: $drawError');
      debugPrintStack(
        label: '[CruiseMode] Route drawing stacktrace',
        stackTrace: drawStack,
      );
    }
    debugPrint('[CruiseMode] Route generation SUCCESS');
  }

  void _applyRouteResult(RouteResult result) {
    if (result.edgeMeta.isNotEmpty) {
      debugPrint(
        '[RouteDebug][ResultMeta] route_source=${result.edgeMeta['route_source'] ?? result.edgeMeta['source']} '
        'quality_tier=${result.edgeMeta['quality_tier']} '
        'generation_duration_ms=${result.edgeMeta['generation_duration_ms']} '
        'mapbox_call_count=${result.edgeMeta['mapbox_call_count'] ?? result.edgeMeta['mapboxCallCount']} '
        'pool_route_id=${result.edgeMeta['pool_route_id'] ?? result.edgeMeta['pool_match_id']} '
        'pool_match_tier=${result.edgeMeta['pool_match_tier']} '
        'access_leg_used=${result.edgeMeta['access_leg_used']} '
        'route_rebased_to_user=${result.edgeMeta['route_rebased_to_user']} '
        'route_start_distance_km=${result.edgeMeta['route_start_distance_km']}',
      );
    }
    _lastRouteResult = result;
    _sessionRouteResult = result;
    _activeSpeedLimits = result.speedLimits;
    _recentDestinationDistances = [];
    _clearAccessLegState();
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
      _sessionRouteStartIndexInActiveRoute = 0;
      _navigationStartTime = null;
      _offRouteCount = 0;
      _lastRerouteTime = null;
      _remainingDistance = null;
      _remainingDuration = null;
      _cachedCurveCount = 0;
      _isExistingRouteSession = false;
    });
    // Kurven async im Isolate berechnen (blockiert UI nicht)
    GamificationService.countCurvesAsync(result.coordinates).then((count) {
      if (mounted) setState(() => _cachedCurveCount = count);
    });
  }

  Future<RouteResult> _prepareRouteForPreviewStart({
    required RouteResult result,
    required geo.Position startPosition,
    required bool isRoundTrip,
    required bool avoidHighways,
    bool forceAccessFromCurrentLocation = false,
    bool allowDistantAccess = false,
  }) async {
    if ((!isRoundTrip && !forceAccessFromCurrentLocation) ||
        result.coordinates.length < 2) {
      return result;
    }
    if (result.edgeMeta['route_rebased_to_user'] == true &&
        result.edgeMeta['access_leg_used'] != null) {
      return result;
    }

    final first = result.coordinates.first;
    final distanceToRouteStartMeters = geo.Geolocator.distanceBetween(
      startPosition.latitude,
      startPosition.longitude,
      first[1],
      first[0],
    );
    final globalMatch = findNearestInWindow(
      position: startPosition,
      coordinates: result.coordinates,
      currentIndex: 0,
      windowSize: result.coordinates.length,
      maxJumpMeters: double.infinity,
    );
    const onStartCorridor = _offRouteThresholdMeters + 20;
    final matchesRouteStartIndex =
        globalMatch.index <= 24 ||
        globalMatch.index >= math.max(0, result.coordinates.length - 25);
    if (!forceAccessFromCurrentLocation &&
        distanceToRouteStartMeters <= onStartCorridor &&
        matchesRouteStartIndex &&
        globalMatch.distanceMeters <= onStartCorridor) {
      return _withMergedRouteMeta(result, {
        'route_start_distance_km': double.parse(
          (distanceToRouteStartMeters / 1000).toStringAsFixed(2),
        ),
        'route_passes_near_user': true,
        'route_rebased_to_user': false,
        'access_leg_used': false,
      });
    }

    final nearestDistanceKm = globalMatch.distanceMeters / 1000.0;
    final routeStartDistanceKm = distanceToRouteStartMeters / 1000.0;
    if (!allowDistantAccess &&
        routeStartDistanceKm > RoutePoolService.roundTripHardStartMaxKm &&
        nearestDistanceKm > RoutePoolService.roundTripHardStartMaxKm) {
      throw RouteServiceException(
        type: RouteErrorType.noRoute,
        userMessage:
            'Diese Route startet zu weit entfernt. Bitte wähle eine lokale Route.',
        debugMessage:
            'Preview route rejected before display: routeStart=${routeStartDistanceKm.toStringAsFixed(1)}km nearest=${nearestDistanceKm.toStringAsFixed(1)}km.',
      );
    }

    final accessPlan = await _routeService.buildAccessRouteToExistingRoute(
      currentPosition: startPosition,
      existingRoute: result,
      mode: _selectedStyle,
      avoidHighways: avoidHighways,
      returnToSessionOrigin: true,
      rebaseClosedLoop: isRoundTrip,
    );
    _logAccessLegMeta(accessPlan);
    final prepared = _withMergedRouteMeta(accessPlan.activeRoute, {
      'route_source':
          result.edgeMeta['route_source'] ?? result.edgeMeta['source'],
      'source': result.edgeMeta['source'] ?? result.edgeMeta['route_source'],
      'preview_access_prepared': true,
      'route_rebased_to_user': accessPlan.routeRebasedToUser,
      'route_passes_near_user': accessPlan.routePassesNearUser,
      'route_start_distance_km': double.parse(
        (accessPlan.routeStartDistanceMeters / 1000).toStringAsFixed(2),
      ),
    });
    debugPrint(
      '[CruiseMode] Preview-Rebase fertig: '
      'access_leg_used=${prepared.edgeMeta['access_leg_used']} '
      'route_rebased_to_user=${prepared.edgeMeta['route_rebased_to_user']} '
      'route_start_distance_km=${prepared.edgeMeta['route_start_distance_km']}',
    );
    return prepared;
  }

  void _onDestinationSelected(MapboxSuggestion suggestion) {
    setState(() {
      _selectedDestination = suggestion;
      _destinationController.text = suggestion.placeName;
    });
  }

  void _handleDestinationInputChanged(String value) {
    final selected = _selectedDestination;
    if (selected == null) return;
    if (value.trim() == selected.placeName.trim()) return;
    setState(() {
      _selectedDestination = null;
    });
  }

  void _handleDetourChanged(String detour) {
    setState(() {
      _selectedDetour = detour;
      if (detour == 'Direkt') {
        return;
      }
      final allowedStyles = {
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

  void _clearAccessLegState() {
    _isAccessLegActive = false;
    _accessLegJoinIndex = null;
    _accessLegMainRouteResult = null;
  }

  _GeneratedRouteUiStateSnapshot _captureGeneratedRouteUiState() {
    return _GeneratedRouteUiStateSnapshot(
      lastRouteResult: _lastRouteResult,
      sessionRouteResult: _sessionRouteResult,
      accessLegMainRouteResult: _accessLegMainRouteResult,
      activeSpeedLimits: List<SpeedLimitSegment>.from(_activeSpeedLimits),
      activeDestinationCoordinate: _activeDestinationCoordinate == null
          ? null
          : List<double>.from(_activeDestinationCoordinate!),
      activeDetourVariant: _activeDetourVariant,
      activePointToPointScenic: _activePointToPointScenic,
      activePointToPointMode: _activePointToPointMode,
      activeAvoidHighways: _activeAvoidHighways,
      recentDestinationDistances: List<double>.from(
        _recentDestinationDistances,
      ),
      isAccessLegActive: _isAccessLegActive,
      accessLegJoinIndex: _accessLegJoinIndex,
      routeGeoJson: _routeGeoJson,
      routeDistance: _routeDistance,
      routeDuration: _routeDuration,
      routeLatLngs: List<LatLng>.from(_routeLatLngs),
      fullRouteCoordinates: _fullRouteCoordinates
          .map((point) => List<double>.from(point))
          .toList(growable: false),
      remainingRouteCoordinates: _remainingRouteCoordinates
          .map((point) => List<double>.from(point))
          .toList(growable: false),
      maneuvers: List<RouteManeuver>.from(_maneuvers),
      activeManeuverIndex: _activeManeuverIndex,
      currentRouteIndex: _currentRouteIndex,
      lastDrawnRouteIndex: _lastDrawnRouteIndex,
      distanceSinceLastRedraw: _distanceSinceLastRedraw,
      showRouteInfoBanner: _showRouteInfoBanner,
      isRouteConfirmed: _isRouteConfirmed,
      isExistingRouteSession: _isExistingRouteSession,
      cachedCurveCount: _cachedCurveCount,
      remainingDistance: _remainingDistance,
      remainingDuration: _remainingDuration,
      sessionRouteStartIndexInActiveRoute: _sessionRouteStartIndexInActiveRoute,
      navigationStartTime: _navigationStartTime,
      offRouteCount: _offRouteCount,
      lastRerouteTime: _lastRerouteTime,
      isRerouting: _isRerouting,
      originalRouteDistance: _originalRouteDistance,
      originalRouteDuration: _originalRouteDuration,
      totalDistanceDriven: _totalDistanceDriven,
      isCameraLocked: _isCameraLocked,
      configCollapsed: _configCollapsed,
      announcedManeuverIndices: Set<int>.from(_announcedManeuverIndices),
    );
  }

  void _restoreGeneratedRouteUiState(_GeneratedRouteUiStateSnapshot snapshot) {
    _lastRouteResult = snapshot.lastRouteResult;
    _sessionRouteResult = snapshot.sessionRouteResult;
    _accessLegMainRouteResult = snapshot.accessLegMainRouteResult;
    _activeSpeedLimits = List<SpeedLimitSegment>.from(
      snapshot.activeSpeedLimits,
    );
    _activeDestinationCoordinate = snapshot.activeDestinationCoordinate == null
        ? null
        : List<double>.from(snapshot.activeDestinationCoordinate!);
    _activeDetourVariant = snapshot.activeDetourVariant;
    _activePointToPointScenic = snapshot.activePointToPointScenic;
    _activePointToPointMode = snapshot.activePointToPointMode;
    _activeAvoidHighways = snapshot.activeAvoidHighways;
    _recentDestinationDistances = List<double>.from(
      snapshot.recentDestinationDistances,
    );
    _isAccessLegActive = snapshot.isAccessLegActive;
    _accessLegJoinIndex = snapshot.accessLegJoinIndex;
    _announcedManeuverIndices
      ..clear()
      ..addAll(snapshot.announcedManeuverIndices);
    _safeSetState(() {
      _routeGeoJson = snapshot.routeGeoJson;
      _routeDistance = snapshot.routeDistance;
      _routeDuration = snapshot.routeDuration;
      _routeLatLngs = List<LatLng>.from(snapshot.routeLatLngs);
      _fullRouteCoordinates = snapshot.fullRouteCoordinates
          .map((point) => List<double>.from(point))
          .toList(growable: false);
      _remainingRouteCoordinates = snapshot.remainingRouteCoordinates
          .map((point) => List<double>.from(point))
          .toList(growable: false);
      _maneuvers = List<RouteManeuver>.from(snapshot.maneuvers);
      _activeManeuverIndex = snapshot.activeManeuverIndex;
      _currentRouteIndex = snapshot.currentRouteIndex;
      _lastDrawnRouteIndex = snapshot.lastDrawnRouteIndex;
      _distanceSinceLastRedraw = snapshot.distanceSinceLastRedraw;
      _showRouteInfoBanner = snapshot.showRouteInfoBanner;
      _isRouteConfirmed = snapshot.isRouteConfirmed;
      _isExistingRouteSession = snapshot.isExistingRouteSession;
      _cachedCurveCount = snapshot.cachedCurveCount;
      _remainingDistance = snapshot.remainingDistance;
      _remainingDuration = snapshot.remainingDuration;
      _sessionRouteStartIndexInActiveRoute =
          snapshot.sessionRouteStartIndexInActiveRoute;
      _navigationStartTime = snapshot.navigationStartTime;
      _offRouteCount = snapshot.offRouteCount;
      _lastRerouteTime = snapshot.lastRerouteTime;
      _isRerouting = snapshot.isRerouting;
      _originalRouteDistance = snapshot.originalRouteDistance;
      _originalRouteDuration = snapshot.originalRouteDuration;
      _totalDistanceDriven = snapshot.totalDistanceDriven;
      _isCameraLocked = snapshot.isCameraLocked;
      _configCollapsed = snapshot.configCollapsed;
    });
  }

  bool _snapshotHasVisibleRoute(_GeneratedRouteUiStateSnapshot snapshot) {
    return snapshot.lastRouteResult != null ||
        snapshot.routeLatLngs.length >= 2;
  }

  void _restoreGeneratedRouteFailureUi(
    _GeneratedRouteUiStateSnapshot previousUiState,
    String message, {
    Object? error,
  }) {
    _restoreGeneratedRouteUiState(previousUiState);
    if (!_snapshotHasVisibleRoute(previousUiState) && mounted && !_disposed) {
      setState(() {
        _configCollapsed = false;
      });
    }

    if (_isWaypointRouteError(error)) {
      _showWaypointRouteStatusNotice(error as RouteServiceException);
      return;
    }

    if (_isExpectedRoundTripRoutingStatus(error)) {
      _showRoundTripRouteStatusNotice(error as RouteServiceException);
      return;
    }

    if (_isRouteWarmupError(error)) {
      unawaited(_showRouteWarmupDialog(error as RouteServiceException));
      return;
    }

    if (_snapshotHasVisibleRoute(previousUiState)) {
      debugPrint(
        '[CruiseMode] Route attempt failed but previous route stayed visible: '
        '$message${error == null ? "" : " ($error)"}',
      );
      return;
    }

    _showError(message, isCritical: true);
  }

  bool _isExpectedRoundTripRoutingStatus(Object? error) {
    if (!_isRoundTrip || _isWaypointPlanning) return false;
    if (error is! RouteServiceException) return false;
    if (_isRealRouteLimit(error)) return false;
    final code =
        error.edgeMeta['response_code']?.toString() ??
        error.edgeMeta['code']?.toString();
    return error.type == RouteErrorType.noRoute ||
        error.type == RouteErrorType.quality ||
        code == 'search_in_progress' ||
        code == 'search_session_no_route' ||
        code == 'search_session_timeout' ||
        error.edgeMeta['search_in_progress'] == true ||
        _isRouteWarmupError(error);
  }

  bool _isRealRouteLimit(RouteServiceException error) {
    final meta = error.edgeMeta;
    final code =
        meta['response_code']?.toString().toLowerCase() ??
        meta['code']?.toString().toLowerCase();
    return error.type == RouteErrorType.rateLimit ||
        error.type == RouteErrorType.workerLimit ||
        error.statusCode == 429 ||
        meta['real_budget_limited'] == true ||
        meta['budget_limited_global'] == true ||
        meta['mapbox_429'] == true ||
        meta['provider_429'] == true ||
        meta['WORKER_RESOURCE_LIMIT'] == true ||
        meta['worker_resource_limit'] == true ||
        code == 'rate_limit' ||
        code == 'worker_resource_limit';
  }

  void _showRoundTripRouteStatusNotice(RouteServiceException error) {
    if (!mounted || _disposed) return;
    final code =
        error.edgeMeta['response_code']?.toString() ??
        error.edgeMeta['code']?.toString();
    final title = code == 'search_session_timeout'
        ? 'Wir suchen weiter'
        : code == 'search_session_no_route'
        ? 'Gerade keine gute Route gefunden'
        : 'Wir suchen eine bessere Route';
    final message = switch (code) {
      'search_in_progress' =>
        'Wir prüfen Live-Varianten und verfeinern die Strecke.',
      'search_session_timeout' =>
        'Die Suche läuft im Hintergrund weiter. Beim nächsten Versuch prüfen wir neue Vorschläge.',
      'search_session_no_route' =>
        'Gerade war keine sichere Route dabei. Wir sammeln weiter passende Varianten.',
      'route_quality_too_low' =>
        'Die gefundenen Varianten waren noch nicht sauber genug. Wir prüfen weiter.',
      _ =>
        'Gerade keine gute Route gefunden. Wir suchen weiter und prüfen beim nächsten Versuch erneut.',
    };
    _safeSetState(() {
      _routeSearchNoticeTitle = title;
      _routeSearchNoticeMessage = message;
    });
  }

  void _showWaypointRouteStatusNotice(RouteServiceException error) {
    if (!mounted || _disposed) return;
    final code =
        error.edgeMeta['response_code']?.toString() ??
        error.edgeMeta['code']?.toString();
    final message = switch (code) {
      'waypoint_too_far' =>
        'Wir konnten die Stopps noch nicht sauber an Straßen anbinden. Setze einen Stopp näher an eine Straße oder lass neue Stopps vorschlagen.',
      'waypoint_duplicate_or_too_close' =>
        'Zwei Stopps liegen zu nah beieinander. Verschiebe einen Punkt oder entferne ihn.',
      'too_few_waypoints' =>
        'Setze mindestens einen Stopp oder lass passende Stopps vorschlagen.',
      'too_many_waypoints' => 'Nutze maximal drei Stopps für diese Rundroute.',
      _ =>
        'Diese Stopps ergeben gerade keine sichere Strecke. Bearbeite sie auf der Karte oder lass neue Stopps vorschlagen.',
    };
    _safeSetState(() {
      _configCollapsed = true;
      _routeSearchNoticeTitle = 'Stopps prüfen';
      _routeSearchNoticeMessage = message;
    });
  }

  bool _isRouteWarmupError(Object? error) {
    if (error is! RouteServiceException) return false;
    final code =
        error.edgeMeta['response_code']?.toString() ??
        error.edgeMeta['code']?.toString();
    final coverageStatus = error.edgeMeta['coverage_status']?.toString();
    final healingStatus = error.edgeMeta['healing_status']?.toString();
    return code == 'pool_bootstrap_pending' ||
        code == 'region_warming_up' ||
        code == 'route_generation_limited' ||
        code == 'route_quality_too_low' ||
        code == 'search_session_timeout' ||
        code == 'detour_not_available' ||
        coverageStatus == 'empty' ||
        coverageStatus == 'thin' ||
        coverageStatus == 'quality_thin' ||
        coverageStatus == 'warming_up' ||
        coverageStatus == 'cooldown' ||
        coverageStatus == 'hard_region_thin' ||
        coverageStatus == 'hard_region_curated_needed' ||
        coverageStatus == 'bootstrap_limited' ||
        healingStatus == 'healing_queued' ||
        healingStatus == 'healing_running' ||
        healingStatus == 'healing_failed_cooldown' ||
        healingStatus == 'healing_paused_budget' ||
        healingStatus == 'hard_region_curated_needed' ||
        error.edgeMeta['pool_bootstrap_pending'] == true ||
        error.edgeMeta['seed_job_created'] == true ||
        error.edgeMeta['retry_search_started'] == true;
  }

  bool _isWaypointRouteError(Object? error) {
    if (error is! RouteServiceException) return false;
    final code =
        error.edgeMeta['response_code']?.toString() ??
        error.edgeMeta['code']?.toString();
    return code == 'waypoint_quality_too_low' ||
        code == 'waypoint_route_not_possible' ||
        code == 'waypoint_not_reached' ||
        code == 'waypoint_layout_unstable' ||
        code == 'waypoint_duplicate_or_too_close' ||
        code == 'waypoint_too_far' ||
        code == 'too_few_waypoints' ||
        code == 'too_many_waypoints';
  }

  Future<void> _showRouteWarmupDialog(RouteServiceException error) async {
    if (!mounted || _disposed || _routeWarmupDialogOpen) return;
    _routeWarmupDialogOpen = true;
    try {
      final action = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Route noch nicht verfügbar'),
            content: Text(error.userMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop('settings'),
                child: const Text('Einstellungen ändern'),
              ),
              if (!_isRoundTrip)
                TextButton(
                  onPressed: () => Navigator.of(context).pop('direct'),
                  child: const Text('Direkte Route nehmen'),
                ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop('retry'),
                child: const Text('Nochmal suchen'),
              ),
            ],
          );
        },
      );
      if (!mounted || _disposed) return;
      debugPrint(
        '[CruiseMode] Warmup dialog action=$action '
        'code=${error.edgeMeta['response_code'] ?? error.edgeMeta['code']} '
        'retry_reason=${error.edgeMeta['retry_reason']}',
      );
      if (action == 'direct') {
        setState(() => _selectedDetour = 'Direkt');
        unawaited(Future<void>.delayed(Duration.zero, _generateRoute));
      } else if (action == 'retry') {
        unawaited(Future<void>.delayed(Duration.zero, _generateRoute));
      }
    } finally {
      _routeWarmupDialogOpen = false;
    }
  }

  void _resetGeneratedRouteUiState() {
    _routeDrawAnimationToken++;
    _routeDrawAnimationTimer?.cancel();
    _routeLoadingPhaseTimer?.cancel();
    _routeLoadingPhaseTimer = null;
    _clearAccessLegState();
    _lastRouteResult = null;
    _sessionRouteResult = null;
    _activeDestinationCoordinate = null;
    _activeDetourVariant = 0;
    _activePointToPointScenic = false;
    _activePointToPointMode = 'Standard';
    _activeAvoidHighways = false;
    _lastGeneratedWasRoundTrip = null;
    _lastGeneratedSelectedKm = null;
    _lastGeneratedSelectedStyle = null;
    _lastGeneratedAvoidHighways = null;
    _lastGeneratedWaypointSignature = null;
    _recentDestinationDistances = [];
    _activeSpeedLimits = [];
    _announcedManeuverIndices.clear();
    _safeSetState(() {
      _isLoading = false;
      _routeLoadingPhaseIndex = 0;
      _routeSearchProgress = 0.08;
      _activeRouteGenerationSerial = null;
      _routeGenerationCancelled = false;
      _routeSearchNoticeTitle = null;
      _routeSearchNoticeMessage = null;
      _routeGeoJson = null;
      _routeDistance = null;
      _routeDuration = null;
      _routeLatLngs = [];
      _fullRouteCoordinates = [];
      _remainingRouteCoordinates = [];
      _maneuvers = [];
      _activeManeuverIndex = 0;
      _currentRouteIndex = 0;
      _lastDrawnRouteIndex = 0;
      _distanceSinceLastRedraw = 0.0;
      _showRouteInfoBanner = false;
      _isRouteConfirmed = false;
      _isExistingRouteSession = false;
      _cachedCurveCount = 0;
      _remainingDistance = null;
      _remainingDuration = null;
      _sessionRouteStartIndexInActiveRoute = 0;
      _navigationStartTime = null;
      _offRouteCount = 0;
      _lastRerouteTime = null;
      _isRerouting = false;
      _originalRouteDistance = null;
      _originalRouteDuration = null;
      _totalDistanceDriven = 0.0;
      _isCameraLocked = false;
      _configCollapsed = false;
    });
  }

  void _returnToCruiseSetupFromActiveRoute() {
    if (!mounted || _disposed) return;
    _dismissTransientRouteUi();
    _stopSimulation(restartLiveTracking: false);
    _stopNavigationTracking();
    CruiseModePage.isFullscreen.value = false;
    _resetGeneratedRouteUiState();

    final currentLocation = _userLocation;
    if (currentLocation != null) {
      _setCameraToPosition(currentLocation);
    } else {
      unawaited(_initializeMapLocation());
    }
  }

  void _maybeFinalizeAccessLegPhase() {
    if (!_isAccessLegActive) return;
    final joinIndex = _accessLegJoinIndex;
    if (joinIndex == null) return;
    if (_currentRouteIndex < joinIndex) return;

    _safeSetState(() {
      _clearAccessLegState();
    });
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Hauptroute erreicht. Navigation läuft normal weiter.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
    }
  }

  Future<geo.Position?> _resolveCurrentPositionForNavigationStart() async {
    final fallback = _userLocation;
    try {
      final current = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.best,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _userLocation = current;
      return current;
    } catch (_) {
      if (fallback != null) return fallback;
      try {
        final resolved = await _getStartCoordinates();
        _userLocation = resolved;
        return resolved;
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _startNavigationFlow() async {
    final hasLocationPermission = await _ensureNavigationLocationPermission();
    if (!hasLocationPermission) return;

    await _prepareAccessLegForOffRouteStart();
    await _prepareXpStreakContext();
    _startNavigationTracking();
    _isCameraLocked = true;
    await _activateNavigationCamera();

    final windowEnd = _findLookAheadIndex(_currentRouteIndex, 3000);
    _safeSetState(() {
      _remainingRouteCoordinates = _fullRouteCoordinates.sublist(
        _currentRouteIndex,
        windowEnd,
      );
    });
    await _drawRoute({
      'type': 'LineString',
      'coordinates': _remainingRouteCoordinates,
    }, animateCamera: false);
  }

  Future<void> _prepareXpStreakContext() async {
    final streakDays = await GamificationService.getStreakDaysForNextRide(
      rideDate: DateTime.now(),
    );
    if (!mounted || _disposed) return;
    _xpStreakDays = streakDays;
  }

  Future<void> _prepareAccessLegForOffRouteStart() async {
    if (!_isExistingRouteSession || _fullRouteCoordinates.length < 2) return;
    if (_isAccessLegActive) return;

    final position = await _resolveCurrentPositionForNavigationStart();
    if (position == null) return;
    final sourceRoute = _sessionRouteResult ?? _lastRouteResult;
    if (sourceRoute == null || sourceRoute.coordinates.length < 2) return;

    final startCoordinate = _fullRouteCoordinates.first;
    final distanceToRouteStart = geo.Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      startCoordinate[1],
      startCoordinate[0],
    );
    final globalMatch = findNearestInWindow(
      position: position,
      coordinates: _fullRouteCoordinates,
      currentIndex: 0,
      windowSize: _fullRouteCoordinates.length,
      maxJumpMeters: double.infinity,
    );
    final onStartCorridor = _isRoundTrip
        ? _offRouteThresholdMeters + 20
        : _currentPointToPointCorridorMeters() + 40;
    final matchesRouteStartIndex =
        globalMatch.index <= 24 ||
        (_isRoundTrip &&
            globalMatch.index >=
                math.max(0, _fullRouteCoordinates.length - 25));
    if (distanceToRouteStart <= onStartCorridor &&
        matchesRouteStartIndex &&
        globalMatch.distanceMeters <= onStartCorridor) {
      return;
    }

    RouteAccessPlan accessPlan;
    try {
      accessPlan = await _routeService.buildAccessRouteToExistingRoute(
        currentPosition: position,
        existingRoute: sourceRoute,
        mode: 'Standard',
        avoidHighways: _activeAvoidHighways,
        returnToSessionOrigin: _isRoundTrip,
        rebaseClosedLoop: _isRoundTrip,
      );
      _logAccessLegMeta(accessPlan);
    } catch (e) {
      // Access-Leg konnte nicht geroutet werden — KEIN Luftlinien-Fallback.
      // Lieber dem User klar sagen, dass er erst zum Routenstart muss, als
      // eine sichtbar kaputte Route mit Luftlinien-Sprung anzuzeigen.
      debugPrint('[CruiseMode] Access-Leg konnte nicht generiert werden: $e');
      // Die gespeicherte Route bleibt sichtbar; kein harter Fehler-Banner.
      return;
    }

    if (!accessPlan.hasAccessLeg) {
      if (accessPlan.joinPoint.index > 0) {
        await _commitRerouteResult(
          result: accessPlan.sessionRoute,
          sessionRouteResult: accessPlan.sessionRoute,
          position: position,
        );
        _safeSetState(() {
          _clearAccessLegState();
          _sessionRouteStartIndexInActiveRoute = 0;
          _totalDistanceDriven = 0.0;
        });
      }
      return;
    }

    await _commitRerouteResult(
      result: accessPlan.activeRoute,
      sessionRouteResult: accessPlan.activeRoute,
      position: position,
    );

    final joinIndexInMergedRoute = math
        .max(
          1,
          accessPlan.activeRoute.coordinates.length -
              accessPlan.sessionRoute.coordinates.length,
        )
        .clamp(1, math.max(1, accessPlan.activeRoute.coordinates.length - 1))
        .toInt();
    _safeSetState(() {
      _isAccessLegActive = true;
      _accessLegJoinIndex = joinIndexInMergedRoute;
      _sessionRouteStartIndexInActiveRoute = 0;
      _accessLegMainRouteResult = accessPlan.sessionRoute;
      _totalDistanceDriven = 0.0;
    });

    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Anfahrts-Abschnitt aktiv. Danach geht es auf die gespeicherte Route.',
            ),
            backgroundColor: Color(0xFF0A84FF),
            duration: Duration(seconds: 2),
          ),
        );
    }
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
    List<SpeedLimitSegment>? originalSpeedLimits,
  }) {
    final baseSpeedLimits = originalSpeedLimits ?? _activeSpeedLimits;
    final remaining = baseSpeedLimits
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

  List<SpeedLimitSegment> _sliceSpeedLimits(
    List<SpeedLimitSegment> baseSpeedLimits,
    int startIndex, {
    int skippedOriginalCoordinates = 0,
  }) {
    return baseSpeedLimits
        .where(
          (segment) =>
              segment.endIndex >= startIndex + skippedOriginalCoordinates,
        )
        .map((segment) {
          final shiftedStart = math.max(
            0,
            segment.startIndex - startIndex - skippedOriginalCoordinates,
          );
          final shiftedEnd = math.max(
            shiftedStart,
            segment.endIndex - startIndex - skippedOriginalCoordinates,
          );
          return SpeedLimitSegment(
            startIndex: shiftedStart,
            endIndex: shiftedEnd,
            speedKmh: segment.speedKmh,
          );
        })
        .toList();
  }

  RouteResult _buildRouteResultFromCoordinates({
    required List<List<double>> coordinates,
    required List<RouteManeuver> maneuvers,
    required double? distanceMeters,
    required double? durationSeconds,
    required List<SpeedLimitSegment> speedLimits,
    Map<String, dynamic> edgeMeta = const {},
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
      edgeMeta: edgeMeta,
    );
  }

  RouteResult _withMergedRouteMeta(
    RouteResult result,
    Map<String, dynamic> edgeMeta,
  ) {
    return RouteResult(
      geoJson: result.geoJson,
      geometry: result.geometry,
      coordinates: result.coordinates,
      maneuvers: result.maneuvers,
      distanceMeters: result.distanceMeters,
      durationSeconds: result.durationSeconds,
      distanceKm: result.distanceKm,
      speedLimits: result.speedLimits,
      edgeMeta: {...result.edgeMeta, ...edgeMeta},
    );
  }

  void _logAccessLegMeta(RouteAccessPlan plan) {
    final meta = plan.activeRoute.edgeMeta;
    debugPrint(
      '[CruiseMode] Access-Leg meta: '
      'access_leg_used=${meta['access_leg_used']} '
      'access_leg_distance_km=${meta['access_leg_distance_km']} '
      'join_point_type=${meta['join_point_type']} '
      'route_start_distance_km=${meta['route_start_distance_km']} '
      'route_passes_near_user=${meta['route_passes_near_user']} '
      'route_rebased_to_user=${meta['route_rebased_to_user']}',
    );
  }

  void _logRerouteMeta(Map<String, dynamic> meta) {
    debugPrint(
      '[CruiseMode] Reroute meta: '
      'triggered=${meta['reroute_triggered']} '
      'failed=${meta['reroute_failed']} '
      'reason=${meta['reroute_reason']} '
      'mode=${meta['reroute_mode']} '
      'reroute_distance_km=${meta['reroute_distance_km']} '
      'rejoin_point_distance_km=${meta['rejoin_point_distance_km']} '
      'remaining_distance_before=${meta['remaining_distance_before']} '
      'remaining_distance_after=${meta['remaining_distance_after']} '
      'eta_before=${meta['eta_before']} '
      'eta_after=${meta['eta_after']}',
    );
  }

  void _markCurrentRouteWithRerouteMeta(Map<String, dynamic> meta) {
    final last = _lastRouteResult;
    if (last != null) {
      _lastRouteResult = _withMergedRouteMeta(last, meta);
    }
    final session = _sessionRouteResult;
    if (session != null) {
      _sessionRouteResult = _withMergedRouteMeta(session, meta);
    }
  }

  void _publishRerouteFailure({
    required String rerouteReason,
    required String rerouteMode,
    required double? remainingDistanceBeforeMeters,
    required double? etaBeforeSeconds,
    double? rerouteDistanceMeters,
    double? rejoinPointDistanceMeters,
  }) {
    final meta = buildRerouteTelemetry(
      rerouteReason: rerouteReason,
      rerouteMode: rerouteMode,
      remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
      remainingDistanceAfterMeters: remainingDistanceBeforeMeters,
      etaBeforeSeconds: etaBeforeSeconds,
      etaAfterSeconds: etaBeforeSeconds,
      rerouteDistanceMeters: rerouteDistanceMeters,
      rejoinPointDistanceMeters: rejoinPointDistanceMeters,
      rerouteFailed: true,
    );
    _markCurrentRouteWithRerouteMeta(meta);
    _logRerouteMeta(meta);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Straßen-Reroute nicht möglich. Bitte zur Route zurückfahren.',
            ),
            backgroundColor: Color(0xFFFF9500),
            duration: Duration(seconds: 2),
          ),
        );
    }
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
    RouteResult? sessionRouteResult,
  }) async {
    if (result.edgeMeta.isNotEmpty) {
      debugPrint(
        '[CruiseMode] Commit route meta: '
        'access_leg_used=${result.edgeMeta['access_leg_used']} '
        'join_point_type=${result.edgeMeta['join_point_type']} '
        'reroute_mode=${result.edgeMeta['reroute_mode']} '
        'reroute_failed=${result.edgeMeta['reroute_failed']}',
      );
    }
    _lastRouteResult = result;
    _sessionRouteResult = sessionRouteResult ?? result;
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
      final first = routeSlice.first;
      final distanceToFirst = geo.Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        first[1],
        first[0],
      );
      if (distanceToFirst <= 35.0) {
        routeSlice[0] = [position.longitude, position.latitude];
      }
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
    final previousUiState = _captureGeneratedRouteUiState();
    final geometry = route.geometry;
    final generationId = ++_routeGenerationSerial;

    _safeSetState(() {
      _isRoundTrip = route.isRoundTrip;
      _selectedStyle = route.style;
    });
    _startRouteLoadingUi(
      generationId: generationId,
      preparingExistingRoute: true,
    );

    try {
      final coordsRaw = (geometry['coordinates'] as List?) ?? [];
      final coordinates = coordsRaw
          .whereType<List>()
          .where((c) => c.length >= 2)
          .map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
          .toList();

      if (coordinates.length < 2) {
        _stopRouteLoadingUi(generationId: generationId);
        _restoreGeneratedRouteFailureUi(
          previousUiState,
          'Route hat nicht genug Koordinaten.',
        );
        return;
      }

      final previewResult = RouteResult(
        geoJson: json.encode(geometry),
        geometry: geometry,
        coordinates: coordinates,
        maneuvers: [],
        distanceMeters: route.distanceKm * 1000,
        durationSeconds: route.durationSeconds,
        distanceKm: route.distanceKm,
        edgeMeta: {
          'route_source': 'saved',
          'source': 'saved',
          'saved_route_id': route.id,
          'explicit_route_handoff': true,
          'quality_tier': route.rating != null && route.rating! >= 4
              ? 'good'
              : 'acceptable',
        },
      );

      final startPosition =
          await _resolveCurrentPositionForNavigationStart() ??
          await _getStartCoordinates();
      if (_isRouteGenerationCancelled(generationId)) return;
      final preparedPreviewResult = await _prepareRouteForPreviewStart(
        result: previewResult,
        startPosition: startPosition,
        isRoundTrip: route.isRoundTrip,
        avoidHighways: false,
        forceAccessFromCurrentLocation: true,
        allowDistantAccess: true,
      );
      if (_isRouteGenerationCancelled(generationId)) return;

      _applyRouteResult(preparedPreviewResult);
      _hideRouteSearchStatusForAcceptedRoute();
      final preparedCoordinates = preparedPreviewResult.coordinates;
      final lastCoordinate = preparedCoordinates.last;
      setState(() {
        _isExistingRouteSession = true;
        _isRoundTrip = route.isRoundTrip;
        _selectedStyle = route.style;
        _selectedDetour = 'Direkt';
        _avoidHighways = false;
        _selectedDestination = null;
        _destinationController.clear();
        _isCameraLocked = false;
        _configCollapsed = true;
        _showRouteInfoBanner = true;
        _activeDestinationCoordinate = route.isRoundTrip
            ? null
            : lastCoordinate;
        _activeDetourVariant = 0;
        _activePointToPointScenic =
            !route.isRoundTrip && route.style != 'Standard';
        _activePointToPointMode = route.style;
        _activeAvoidHighways = false;
        _recentDestinationDistances = [];
      });
      CruiseModePage.isFullscreen.value = false;

      await _drawRoute(preparedPreviewResult.geometry, animateRouteDraw: true);
    } catch (e) {
      if (!_isRouteGenerationCancelled(generationId)) {
        _stopRouteLoadingUi(generationId: generationId);
        _restoreGeneratedRouteFailureUi(
          previousUiState,
          'Route konnte nicht geladen werden.',
          error: e,
        );
      }
    }
  }

  // ═══════════════════════ ROUTE CONFIRM ═════════════════════════════════════

  Future<void> _confirmRoute() async {
    if (_isLoading || _fullRouteCoordinates.isEmpty) return;
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
    bool animateRouteDraw = false,
  }) async {
    final coordinatesRaw = (geometry['coordinates'] as List?) ?? [];
    final activeCoordinates = coordinatesRaw
        .whereType<List>()
        .where((c) => c.length >= 2)
        .map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
        .toList();

    debugPrint(
      '[CruiseMode] _drawRoute: ${activeCoordinates.length} Koordinaten, '
      'mapReady=$_mapReady, animateCamera=$animateCamera animateRouteDraw=$animateRouteDraw',
    );

    if (activeCoordinates.length < 2) {
      debugPrint(
        '[CruiseMode] _drawRoute: Unzureichende Koordinaten, Route wird nicht gezeichnet',
      );
      return;
    }

    // KRITISCH: Mapbox liefert [longitude, latitude], flutter_map braucht LatLng(lat, lng)
    final routeLatLngs = activeCoordinates
        .map((c) => LatLng(c[1], c[0])) // [lng, lat] → LatLng(lat, lng)
        .toList();

    // Immer setState aufrufen wenn neue Route, nicht nur bei "meaningful change"
    // (verhindert Race Condition auf Web wo initiales Rendern fehlen könnte)
    final hasChange = _hasMeaningfulRouteChange(_routeLatLngs, routeLatLngs);
    final isInitialRoute = _routeLatLngs.isEmpty && routeLatLngs.isNotEmpty;

    if (hasChange || isInitialRoute) {
      debugPrint(
        '[CruiseMode] _drawRoute: setState für ${routeLatLngs.length} Punkte (initial=$isInitialRoute)',
      );
      if (animateRouteDraw && _shouldAnimateRouteDraw(routeLatLngs)) {
        _startRouteDrawAnimation(routeLatLngs);
      } else {
        _routeDrawAnimationToken++;
        _routeDrawAnimationTimer?.cancel();
        _safeSetState(() {
          _routeLatLngs = routeLatLngs;
        });
      }
    }

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
        debugPrint(
          '[CruiseMode] _drawRoute: Kamera auf Route-Bounds angepasst',
        );
      } catch (e) {
        debugPrint('[CruiseMode] Camera fit fehlgeschlagen: $e');
      }
    } else if (!_mapReady) {
      // Web-spezifisch: Map noch nicht ready, Route wird später gezeichnet via _onMapReady
      debugPrint(
        '[CruiseMode] _drawRoute: Map nicht ready, Route wird bei onMapReady gezeichnet',
      );
    }
  }

  bool _shouldAnimateRouteDraw(List<LatLng> routeLatLngs) {
    if (_isRouteConfirmed || routeLatLngs.length < 12) return false;
    final media = MediaQuery.maybeOf(context);
    if (media == null) return true;
    return !media.disableAnimations && !media.accessibleNavigation;
  }

  void _startRouteDrawAnimation(List<LatLng> targetLatLngs) {
    _routeDrawAnimationToken++;
    _routeDrawAnimationTimer?.cancel();
    final token = _routeDrawAnimationToken;
    final start = DateTime.now();
    const duration = Duration(milliseconds: 3600);
    _safeSetState(() {
      _routeLatLngs = targetLatLngs.take(2).toList(growable: false);
    });
    _routeDrawAnimationTimer = Timer.periodic(
      const Duration(milliseconds: 33),
      (timer) {
        if (!mounted || _disposed || token != _routeDrawAnimationToken) {
          timer.cancel();
          return;
        }
        final elapsed = DateTime.now().difference(start).inMilliseconds;
        final rawT = (elapsed / duration.inMilliseconds).clamp(0.0, 1.0);
        final easedT = Curves.easeInOutCubic.transform(rawT);
        final visibleCount = math
            .max(2, (targetLatLngs.length * easedT).ceil())
            .clamp(2, targetLatLngs.length)
            .toInt();
        _safeSetState(() {
          _routeLatLngs = targetLatLngs
              .take(visibleCount)
              .toList(growable: false);
        });
        if (rawT >= 1.0) {
          timer.cancel();
          _safeSetState(() {
            _routeLatLngs = List<LatLng>.from(targetLatLngs);
          });
        }
      },
    );
  }

  // ═══════════════════════ OVERLAP DETECTION ════════════════════════════════

  // ═══════════════════════ NAVIGATION TRACKING ══════════════════════════════

  geo.LocationSettings _navigationLocationSettings() {
    if (kIsWeb) {
      return const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.best,
        distanceFilter: 0,
      );
    }

    if (Platform.isAndroid) {
      final notificationText = widget.groupId == null
          ? 'Navigation läuft - dein Standort bleibt für die Route aktiv.'
          : 'Navigation läuft - dein Standort wird mit der Gruppe geteilt.';
      return geo.AndroidSettings(
        accuracy: geo.LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: geo.ForegroundNotificationConfig(
          notificationTitle: 'CruiseConnect Navigation',
          notificationText: notificationText,
          notificationChannelName: 'CruiseConnect Navigation',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }

    if (Platform.isIOS || Platform.isMacOS) {
      return geo.AppleSettings(
        accuracy: geo.LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
        activityType: geo.ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }

    return const geo.LocationSettings(
      accuracy: geo.LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );
  }

  void _startNavigationTracking() {
    _stopIdlePositionStream(); // Idle-Stream stoppen, Navigation übernimmt
    _positionSubscription?.cancel();
    _socketPositionSubscription?.cancel();

    // Navigations-Startzeit setzen (nur beim ersten Start, nicht bei Resume)
    _navigationStartTime ??= DateTime.now();

    // Smoother resetten für frischen Start
    if (kIsWeb) {
      _webSmoother.reset();
    } else {
      _nativeSmoother.reset();
    }

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
    final locationSettings = _navigationLocationSettings();
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

  RouteWindowMatch _guardRoundTripFinishMatch(RouteWindowMatch match) {
    if (!_isRoundTrip || _fullRouteCoordinates.length < 2) return match;

    final lastIndex = _fullRouteCoordinates.length - 1;
    final isFinishMatch = match.index >= lastIndex - 1;
    if (!isFinishMatch) return match;

    final currentProgress = _routeIndexProgress(
      _currentRouteIndex,
      _fullRouteCoordinates.length,
    );
    if (currentProgress >= _roundTripFinishArmProgress) return match;

    debugPrint(
      '[CruiseMode] Rundkurs-Zielmatch ignoriert: '
      'currentProgress=${(currentProgress * 100).round()}%, '
      'matchIndex=${match.index}/$lastIndex',
    );
    return RouteWindowMatch(
      index: _currentRouteIndex,
      distanceMeters: match.distanceMeters,
    );
  }

  double _routeIndexProgress(int index, int coordinateLength) {
    if (coordinateLength <= 1) return 1.0;
    return (index / (coordinateLength - 1)).clamp(0.0, 1.0);
  }

  bool _hasDrivenEnoughForAutomaticCompletion() {
    final plannedDistanceMeters =
        _completionRouteResult?.distanceMeters ?? _originalRouteDistance;
    if (plannedDistanceMeters == null || plannedDistanceMeters <= 0) {
      return true;
    }
    final progress = (_totalDistanceDriven / plannedDistanceMeters).clamp(
      0.0,
      1.0,
    );
    if (progress >= _minProgressForAutomaticCompletion) return true;

    debugPrint(
      '[CruiseMode] Ziel erreicht, aber noch nicht genug Route gefahren: '
      '${(progress * 100).round()}%',
    );
    return false;
  }

  Future<void> _onLocationUpdate(geo.Position position) async {
    if (!mounted || _disposed) return;

    // Plattformspezifisches GPS-Smoothing und Heading-Fusion
    geo.Position effectivePosition;
    if (kIsWeb) {
      // Web: Smoother berechnet Heading aus Positionsverlauf
      // (Browser liefert kein zuverlässiges heading, oft 0 oder NaN)
      final smoothed = _webSmoother.update(position);
      effectivePosition = smoothed ?? _webSmoother.current ?? position;
      _userLocation = effectivePosition;
      _userHeading = _webSmoother.heading;
    } else {
      // iOS/Android: Native Smoother mit Kalman-Filter und Heading-Fusion
      // Kombiniert GPS-Heading mit Bewegungsrichtung für flüssige Rotation
      final smoothed = _nativeSmoother.update(position);
      effectivePosition = smoothed ?? _nativeSmoother.current ?? position;
      _userLocation = effectivePosition;
      // Geglättetes Heading verwenden (Apple-Maps-artiges Verhalten)
      if (_nativeSmoother.hasValidHeading) {
        _userHeading = _nativeSmoother.heading;
      }
    }

    // ── Kamera-Bewegung ──────────────────────────────────────────────────────
    // Alle Plattformen: Animierte Interpolation (60fps smooth)
    if (_isCameraLocked && _mapReady) {
      if (kIsWeb) {
        final predicted = _webSmoother.predict(
          DateTime.now().add(const Duration(milliseconds: 180)),
        );
        _animateCameraTo(predicted.lat, predicted.lng, predicted.heading);
      } else {
        // iOS/Android: Vorhersage für noch flüssigere Animation
        final predicted = _nativeSmoother.predict(
          DateTime.now().add(const Duration(milliseconds: 150)),
        );
        _animateCameraTo(
          predicted.lat != 0 ? predicted.lat : effectivePosition.latitude,
          predicted.lng != 0 ? predicted.lng : effectivePosition.longitude,
          _nativeSmoother.hasValidHeading ? predicted.heading : _userHeading,
        );
      }
    }

    // ── UI-Rebuild Throttling ───────────────────────────────────────────────
    // Marker-Position intern aktualisieren, Route-Geometrie aber stabil lassen.
    // setState nur wenn genug Zeit vergangen (Web: 16ms, Native: sofort).
    _userPosition = LatLng(
      effectivePosition.latitude,
      effectivePosition.longitude,
    );
    // Wichtig: Die kanonische Route hier nicht auf die aktuelle GPS-Position
    // ziehen. Bei Off-Route-/Access-Leg-Starts erzeugt das sonst eine
    // sichtbare Luftlinie vom Fahrer zur Route. Route-Slices werden nur nach
    // einem echten Route-Match oder einer berechneten Access-/Reroute gesetzt.

    final now = DateTime.now();
    final skipRebuild =
        kIsWeb &&
        _lastWebRebuildTime != null &&
        now.difference(_lastWebRebuildTime!).inMilliseconds < 16;
    if (!skipRebuild) {
      _lastWebRebuildTime = now;
      _safeSetState(() {});
    }

    if (!_isRouteConfirmed || _fullRouteCoordinates.length < 2) return;

    // Für Route-Matching die rohe Position verwenden (genauer für Snap-to-Route)
    final rawMatch = findNearestInWindow(
      position: position,
      coordinates: _fullRouteCoordinates,
      currentIndex: _currentRouteIndex,
      windowSize: 40,
    );
    final match = _guardRoundTripFinishMatch(rawMatch);

    final offRouteCorridor = _isAccessLegActive
        ? 85.0
        : _isRoundTrip
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
        if (i >= _sessionRouteStartIndexInActiveRoute) {
          _totalDistanceDriven += segmentMeters;
        }
        _distanceSinceLastRedraw += segmentMeters;
      }
      _currentRouteIndex = match.index;
      needsRebuild = true;
      _maybeFinalizeAccessLegPhase();

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
      if (distToEnd <= 50.0 && _hasDrivenEnoughForAutomaticCompletion()) {
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
    final remainingDistanceBeforeMeters = _remainingDistance ?? _routeDistance;
    final etaBeforeSeconds = _remainingDuration ?? _routeDuration;

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
      final accessLegMode =
          _isAccessLegActive &&
          _accessLegMainRouteResult != null &&
          _accessLegMainRouteResult!.coordinates.length >= 2;
      final planningCoordinates = accessLegMode
          ? _accessLegMainRouteResult!.coordinates
          : _fullRouteCoordinates;
      final planningManeuvers = accessLegMode
          ? _accessLegMainRouteResult!.maneuvers
          : _maneuvers;
      final planningSpeedLimits = accessLegMode
          ? _accessLegMainRouteResult!.speedLimits
          : _activeSpeedLimits;

      // Suche den nächsten Punkt auf der GESAMTEN verbleibenden Route (großes Fenster)
      final globalMatch = findNearestInWindow(
        position: position,
        coordinates: planningCoordinates,
        currentIndex: accessLegMode ? 0 : _currentRouteIndex,
        windowSize: planningCoordinates.length,
        maxJumpMeters: double.infinity,
      );

      var heading = position.heading;
      if (!heading.isFinite || heading < 0 || heading > 360) {
        heading = routeHeadingAt(
          planningCoordinates,
          globalMatch.index.clamp(0, planningCoordinates.length - 1),
        );
      }

      final smartPlan = _smartRerouteEngine.createPlan(
        currentPosition: position,
        coordinates: planningCoordinates,
        maneuvers: planningManeuvers,
        nearestIndex: globalMatch.index,
        currentHeadingDegrees: heading,
        speedLimits: planningSpeedLimits,
      );

      debugPrint(
        '[CruiseMode] Smart reroute plan: ${smartPlan.debugLabel}, strategy=${smartPlan.strategy.name}, rejoin=${smartPlan.rejoinIndex}',
      );

      final destination = _activeDestinationCoordinate;
      if (!_isRoundTrip && destination != null && !accessLegMode) {
        final destinationRerouteSeed = Object.hash(
          destination[0].round(),
          destination[1].round(),
          _activeDetourVariant,
          _activeAvoidHighways,
          0x44525252,
        );
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
          diversitySeed: destinationRerouteSeed,
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
            final rerouteMeta = buildRerouteTelemetry(
              rerouteReason: accessLegMode
                  ? 'access_leg_destination_reconnect'
                  : 'destination_reconnect',
              rerouteMode: 'full_rebuild',
              remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
              remainingDistanceAfterMeters: distanceMeters,
              etaBeforeSeconds: etaBeforeSeconds,
              etaAfterSeconds: durationSeconds,
              rerouteDistanceMeters: distanceMeters,
              rejoinPointDistanceMeters: geo.Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                destination[1],
                destination[0],
              ),
            );

            await _commitRerouteResult(
              result: _buildRouteResultFromCoordinates(
                coordinates: destinationResult.coordinates,
                maneuvers: destinationResult.maneuvers,
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                speedLimits: destinationResult.speedLimits,
                edgeMeta: {...destinationResult.edgeMeta, ...rerouteMeta},
              ),
              position: position,
            );
            _logRerouteMeta(rerouteMeta);
            _clearAccessLegState();
            _sessionRouteStartIndexInActiveRoute = 0;

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

      final maxRejoinIndex = math.max(0, planningCoordinates.length - 2);
      final fallbackRejoinIndex = selectForwardRejoinIndex(
        coordinates: planningCoordinates,
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
                anchorCoordinate: planningCoordinates[rejoinIndex],
                rejoinIndex: rejoinIndex,
                strategy: SmartRerouteStrategy.forwardRejoin,
                debugLabel: 'fallback_forward_rejoin_$attempt',
              )
            : smartPlan;
        final mergeWithOriginal =
            (accessLegMode || activePlan.mergeWithOriginal) &&
            rejoinIndex < maxRejoinIndex;
        final rejoinPoint = mergeWithOriginal
            ? planningCoordinates[rejoinIndex]
            : activePlan.anchorCoordinate;
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

        final scenicReroute = !mergeWithOriginal && _activePointToPointScenic;

        final joinRerouteSeed = Object.hash(
          rejoinPoint[0].round(),
          rejoinPoint[1].round(),
          _activeDetourVariant,
          _activeAvoidHighways,
          attempt,
        );
        final candidate = await _routeService.generatePointToPoint(
          startPosition: position,
          destinationLat: rejoinPoint[1],
          destinationLng: rejoinPoint[0],
          mode: _rerouteMode(mergeWithOriginal: mergeWithOriginal),
          scenic: scenicReroute,
          routeVariant: _rerouteVariant(mergeWithOriginal: mergeWithOriginal),
          avoidHighways: _activeAvoidHighways,
          diversitySeed: joinRerouteSeed,
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
          final candidateEnd = candidate.coordinates.last;
          final originalJoinPoint = planningCoordinates[rejoinIndex];
          final joinDistance = geo.Geolocator.distanceBetween(
            candidateEnd[1],
            candidateEnd[0],
            originalJoinPoint[1],
            originalJoinPoint[0],
          );
          if (joinDistance > 45.0 && rejoinIndex < maxRejoinIndex) {
            rejoinIndex = math.min(rejoinIndex + 80, maxRejoinIndex).toInt();
            debugPrint(
              '[CruiseMode] Reroute-Attempt ${attempt + 1}: Join-Gap ${joinDistance.toStringAsFixed(0)}m, rejoinIndex=$rejoinIndex',
            );
            continue;
          }

          final producesUTurn = isUTurnJoin(
            rerouteCoordinates: candidate.coordinates,
            originalCoordinates: planningCoordinates,
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
        _publishRerouteFailure(
          rerouteReason: rerouteResult == null
              ? 'no_candidate'
              : 'ui_unmounted',
          rerouteMode: accessLegMode ? 'rejoin' : 'partial_rebuild',
          remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
          etaBeforeSeconds: etaBeforeSeconds,
        );
        return;
      }

      final resolvedRerouteResult = rerouteResult;
      final resolvedPlan = acceptedPlan;
      final mergeBaseCoordinates = planningCoordinates;
      final mergeBaseManeuvers = planningManeuvers;
      final mergeBaseSpeedLimits = planningSpeedLimits;
      final mergeWithOriginal =
          (accessLegMode || resolvedPlan.mergeWithOriginal) &&
          resolvedPlan.rejoinIndex < mergeBaseCoordinates.length - 1;
      late final RouteResult finalResult;
      RouteResult? sessionRouteResult;
      late final Map<String, dynamic> rerouteMeta;
      final rejoinPointDistanceMeters = geo.Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        mergeWithOriginal
            ? mergeBaseCoordinates[resolvedPlan.rejoinIndex][1]
            : resolvedPlan.anchorCoordinate[1],
        mergeWithOriginal
            ? mergeBaseCoordinates[resolvedPlan.rejoinIndex][0]
            : resolvedPlan.anchorCoordinate[0],
      );

      if (mergeWithOriginal) {
        final remainingOriginal = mergeBaseCoordinates.sublist(
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

        final remainingManeuvers = mergeBaseManeuvers
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
          originalSpeedLimits: mergeBaseSpeedLimits,
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
        final sessionManeuvers = mergeBaseManeuvers
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
                    skippedOriginalCoordinates,
                icon: m.icon,
                announcement: m.announcement,
                instruction: m.instruction,
                maneuverType: m.maneuverType,
                roundaboutExitNumber: m.roundaboutExitNumber,
              ),
            )
            .toList();
        final sessionSpeedLimits = _sliceSpeedLimits(
          mergeBaseSpeedLimits,
          resolvedPlan.rejoinIndex,
          skippedOriginalCoordinates: skippedOriginalCoordinates,
        );
        sessionRouteResult = _buildRouteResultFromCoordinates(
          coordinates: originalTail,
          maneuvers: sessionManeuvers,
          distanceMeters: remainingDistanceMeters,
          durationSeconds: remainingDurationSeconds,
          speedLimits: sessionSpeedLimits,
        );
        rerouteMeta = buildRerouteTelemetry(
          rerouteReason: accessLegMode ? 'access_leg_off_route' : 'off_route',
          rerouteMode: 'rejoin',
          remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
          remainingDistanceAfterMeters:
              rerouteDistanceMeters + remainingDistanceMeters,
          etaBeforeSeconds: etaBeforeSeconds,
          etaAfterSeconds: rerouteDurationSeconds + remainingDurationSeconds,
          rerouteDistanceMeters: rerouteDistanceMeters,
          rejoinPointDistanceMeters: rejoinPointDistanceMeters,
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
          edgeMeta: {...resolvedRerouteResult.edgeMeta, ...rerouteMeta},
        );
        sessionRouteResult = _withMergedRouteMeta(
          sessionRouteResult,
          rerouteMeta,
        );
      } else {
        final distanceMeters =
            resolvedRerouteResult.distanceMeters ??
            _calculatePolylineDistanceMeters(resolvedRerouteResult.coordinates);
        rerouteMeta = buildRerouteTelemetry(
          rerouteReason: accessLegMode ? 'access_leg_rebuild' : 'off_route',
          rerouteMode: 'full_rebuild',
          remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
          remainingDistanceAfterMeters: distanceMeters,
          etaBeforeSeconds: etaBeforeSeconds,
          etaAfterSeconds:
              resolvedRerouteResult.durationSeconds ??
              _estimateDurationSecondsForDistance(distanceMeters),
          rerouteDistanceMeters: distanceMeters,
          rejoinPointDistanceMeters: rejoinPointDistanceMeters,
        );
        finalResult = _buildRouteResultFromCoordinates(
          coordinates: resolvedRerouteResult.coordinates,
          maneuvers: resolvedRerouteResult.maneuvers,
          distanceMeters: distanceMeters,
          durationSeconds:
              resolvedRerouteResult.durationSeconds ??
              _estimateDurationSecondsForDistance(distanceMeters),
          speedLimits: resolvedRerouteResult.speedLimits,
          edgeMeta: {...resolvedRerouteResult.edgeMeta, ...rerouteMeta},
        );
        sessionRouteResult = finalResult;
      }

      await _commitRerouteResult(
        result: finalResult,
        sessionRouteResult: sessionRouteResult,
        position: position,
      );
      _logRerouteMeta(rerouteMeta);
      if (accessLegMode) {
        final joinIndexInMergedRoute = resolvedRerouteResult.coordinates.length
            .clamp(1, math.max(1, finalResult.coordinates.length - 1))
            .toInt();
        _safeSetState(() {
          _isAccessLegActive = true;
          _accessLegJoinIndex = joinIndexInMergedRoute;
          _sessionRouteStartIndexInActiveRoute = 0;
          _sessionRouteResult = finalResult;
          _accessLegMainRouteResult = sessionRouteResult;
          _totalDistanceDriven = 0.0;
        });
      } else {
        _clearAccessLegState();
        _sessionRouteStartIndexInActiveRoute = 0;
      }

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
      _publishRerouteFailure(
        rerouteReason: 'exception',
        rerouteMode: _isAccessLegActive ? 'rejoin' : 'partial_rebuild',
        remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
        etaBeforeSeconds: etaBeforeSeconds,
      );
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

  RouteResult? get _completionRouteResult =>
      _sessionRouteResult ?? _lastRouteResult;

  int _logicalCurrentRouteIndex(int coordinateLength) {
    if (coordinateLength <= 0) return 0;
    final adjustedIndex =
        _currentRouteIndex - _sessionRouteStartIndexInActiveRoute;
    return adjustedIndex.clamp(0, coordinateLength - 1).toInt();
  }

  RouteResult? _buildAdjustedCompletionResult({bool completed = false}) {
    final result = _completionRouteResult;
    if (result == null) return null;

    final plannedDistanceMeters =
        _completionRouteResult?.distanceMeters ?? _originalRouteDistance;
    final rawDrivenDistanceMeters = _totalDistanceDriven > 0
        ? _totalDistanceDriven
        : (result.distanceMeters ?? _routeDistance);
    final drivenDistanceMeters =
        completed && plannedDistanceMeters != null && plannedDistanceMeters > 0
        ? plannedDistanceMeters
        : rawDrivenDistanceMeters;
    final progressFraction = _calculateCompletionProgressFraction(
      drivenDistanceMeters,
      completed: completed,
    );
    final adjustedDuration = _calculateAdjustedCompletionDuration(
      progressFraction,
    );
    final completionCoordinates = _buildCompletionCoordinates(progressFraction);
    final geometry = <String, dynamic>{
      'type': 'LineString',
      'coordinates': completionCoordinates,
    };

    return RouteResult(
      geoJson: json.encode(geometry),
      geometry: geometry,
      coordinates: completionCoordinates,
      maneuvers: result.maneuvers,
      distanceMeters: drivenDistanceMeters,
      durationSeconds: adjustedDuration,
      distanceKm: drivenDistanceMeters != null
          ? drivenDistanceMeters / 1000
          : null,
      speedLimits: result.speedLimits,
      edgeMeta: result.edgeMeta,
    );
  }

  double _calculateCompletionProgressFraction(
    double? drivenDistanceMeters, {
    bool completed = false,
  }) {
    if (completed) return 1.0;
    final plannedDistanceMeters =
        _completionRouteResult?.distanceMeters ?? _originalRouteDistance;
    if (drivenDistanceMeters == null ||
        plannedDistanceMeters == null ||
        plannedDistanceMeters <= 0) {
      return 1.0;
    }
    return (drivenDistanceMeters / plannedDistanceMeters).clamp(0.0, 1.0);
  }

  double? _calculateAdjustedCompletionDuration(double progressFraction) {
    final proportionalDuration = _completionRouteResult?.durationSeconds != null
        ? _completionRouteResult!.durationSeconds! * progressFraction
        : null;
    final elapsedSeconds = _navigationStartTime != null
        ? DateTime.now().difference(_navigationStartTime!).inSeconds.toDouble()
        : null;

    if (elapsedSeconds != null && elapsedSeconds > 0) {
      return elapsedSeconds;
    }
    return proportionalDuration ?? elapsedSeconds;
  }

  List<List<double>> _buildCompletionCoordinates(double progressFraction) {
    final sourceCoordinates =
        _completionRouteResult?.coordinates ?? <List<double>>[];
    if (sourceCoordinates.length < 2) return sourceCoordinates;

    final logicalRouteIndex = _logicalCurrentRouteIndex(
      sourceCoordinates.length,
    );
    final routeIndexLength = logicalRouteIndex > 1
        ? math.min(logicalRouteIndex + 1, sourceCoordinates.length)
        : 0;
    final sampledLength = math.max(
      2,
      (sourceCoordinates.length * progressFraction).round(),
    );
    final targetLength = math.max(routeIndexLength, sampledLength);
    return List<List<double>>.from(
      sourceCoordinates.take(math.min(targetLength, sourceCoordinates.length)),
    );
  }

  int _estimateCompletionCurves(
    List<List<double>> coordinates,
    double progressFraction,
  ) {
    if (coordinates.length >= 6) {
      final sampled = _sampleCoordinatesForSimilarity(
        coordinates,
        maxSamples: 120,
      );
      final counted = GamificationService.countCurves(sampled);
      if (counted > 0) return counted;
    }
    return math.max(0, (_cachedCurveCount * progressFraction).round());
  }

  RouteXpBreakdown _calculateCompletionXpBreakdown({
    required double creditedDistanceKm,
    required int curves,
  }) {
    return GamificationService.calculateRouteXpBreakdown(
      distanceKm: creditedDistanceKm,
      curves: curves,
      style: _selectedStyle,
      streakDays: _xpStreakDays,
    );
  }

  String _formatCompletionDuration(double? durationSeconds) {
    if (durationSeconds == null || durationSeconds <= 0) return '--';
    final minutes = math.max(1, (durationSeconds / 60).ceil());
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final restMinutes = minutes % 60;
    if (restMinutes == 0) return '${hours}h';
    return '${hours}h ${restMinutes}min';
  }

  _CruiseCompletionSnapshot _buildCompletionSnapshot({
    required bool isEarlyStop,
    required bool belowMinimum,
    bool completed = false,
  }) {
    final adjustedResult = _buildAdjustedCompletionResult(completed: completed);
    final drivenKm = adjustedResult?.distanceKm ?? 0;
    final progressFraction = _calculateCompletionProgressFraction(
      adjustedResult?.distanceMeters,
      completed: completed,
    );
    final plannedDistanceKm = _completionRouteResult?.distanceMeters != null
        ? _completionRouteResult!.distanceMeters! / 1000
        : drivenKm;
    final creditProgressFraction =
        GamificationService.completionCreditProgressStep(
          progressFraction,
          completed: completed,
        );
    final creditedDistanceKm =
        GamificationService.creditedDistanceKmForProgress(
          plannedDistanceKm: plannedDistanceKm,
          progressRatio: progressFraction,
          completed: completed,
        );
    final previewCoordinates = adjustedResult?.coordinates ?? <List<double>>[];
    final xpCoordinates = _buildCompletionCoordinates(creditProgressFraction);
    final curves = _estimateCompletionCurves(
      previewCoordinates,
      progressFraction,
    );
    final xpCurves = _estimateCompletionCurves(
      xpCoordinates,
      creditProgressFraction,
    );
    final xpBreakdown = _calculateCompletionXpBreakdown(
      creditedDistanceKm: creditedDistanceKm,
      curves: xpCurves,
    );
    final xpEarned = belowMinimum ? 0 : xpBreakdown.totalXp;

    return _CruiseCompletionSnapshot(
      distanceKm: drivenKm,
      durationText: _formatCompletionDuration(adjustedResult?.durationSeconds),
      curves: curves,
      xpEarned: xpEarned,
      xpBreakdown: xpBreakdown,
      coordinates: previewCoordinates,
      isEarlyStop: isEarlyStop,
      belowMinimum: belowMinimum,
    );
  }

  void _onRouteCompleted() {
    if (!mounted || _disposed) return;
    final snapshot = _buildCompletionSnapshot(
      isEarlyStop: false,
      belowMinimum: false,
      completed: true,
    );
    unawaited(
      _recordRouteCompletionCandidate(completed: true, discarded: false),
    );
    showCruiseCompletionSheet(
      context: context,
      child: CruiseCompletionDialog(
        distanceKm: snapshot.distanceKm,
        durationText: snapshot.durationText,
        curves: snapshot.curves,
        xpEarned: snapshot.xpEarned,
        baseXp: snapshot.xpBreakdown.baseXp,
        streakDays: snapshot.xpBreakdown.streakDays,
        xpMultiplier: snapshot.xpBreakdown.multiplier,
        routeCoordinates: snapshot.coordinates,
        onSave: (rating, tags) async {
          final result = await _saveRouteAndSyncXp(
            rating: rating,
            ratingTags: tags,
            completed: true,
          );
          _resetAfterCompletion();
          return result;
        },
        onDiscard: () async {
          await _recordRouteCompletionCandidate(
            completed: true,
            discarded: true,
          );
          _resetAfterCompletion();
        },
      ),
    );
  }

  void _onRouteEarlyStopped() {
    if (!mounted || _disposed) return;
    final drivenKm = _totalDistanceDriven / 1000;
    final totalKm = _completionRouteResult?.distanceMeters != null
        ? _completionRouteResult!.distanceMeters! / 1000
        : 0.0;
    final progressFraction = totalKm > 0
        ? (drivenKm / totalKm).clamp(0.0, 1.0)
        : 0.0;

    // Nur echte Zielankunft zählt als volle Completion.
    if (progressFraction >= _minProgressForFullCredit) {
      _onRouteCompleted();
      return;
    }

    final belowMinimum = progressFraction < _minProgressForCredit;

    final snapshot = _buildCompletionSnapshot(
      isEarlyStop: true,
      belowMinimum: belowMinimum,
    );

    showCruiseCompletionSheet(
      context: context,
      child: CruiseCompletionDialog(
        distanceKm: snapshot.distanceKm,
        durationText: snapshot.durationText,
        curves: snapshot.curves,
        xpEarned: snapshot.xpEarned,
        baseXp: snapshot.xpBreakdown.baseXp,
        streakDays: snapshot.xpBreakdown.streakDays,
        xpMultiplier: snapshot.xpBreakdown.multiplier,
        routeCoordinates: snapshot.coordinates,
        isEarlyStop: snapshot.isEarlyStop,
        belowMinimum: snapshot.belowMinimum,
        onSave: (rating, tags) async {
          final result = await _saveRouteAndSyncXp(
            rating: rating,
            ratingTags: tags,
            skipXpSync: belowMinimum,
          );
          _resetAfterCompletion();
          return result;
        },
        onDiscard: () async {
          await _recordRouteCompletionCandidate(
            completed: false,
            discarded: true,
          );
          _resetAfterCompletion();
        },
      ),
    );
  }

  /// Speichert die gefahrene Route und synchronisiert XP/Level/Badges.
  /// [skipXpSync] = true → Route wird gespeichert, aber keine XP vergeben (< 20% gefahren).
  Future<CruiseCompletionActionResult> _saveRouteAndSyncXp({
    int? rating,
    List<String> ratingTags = const [],
    bool skipXpSync = false,
    bool completed = false,
  }) async {
    int? previousLevel;
    if (!skipXpSync) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        try {
          final profile = await Supabase.instance.client
              .from('profiles')
              .select('level')
              .eq('id', userId)
              .maybeSingle();
          previousLevel = (profile?['level'] as num?)?.toInt();
        } catch (e) {
          debugPrint('[CruiseMode] Vorheriges Level nicht lesbar: $e');
        }
      }
    }

    try {
      debugPrint(
        '[CruiseMode] _saveRouteAndSyncXp: _lastRouteResult=${_lastRouteResult != null}, rating=$rating, skipXp=$skipXpSync',
      );
      final adjustedResult = _buildAdjustedCompletionResult(
        completed: completed,
      );
      if (adjustedResult != null) {
        final progressFraction = _calculateCompletionProgressFraction(
          adjustedResult.distanceMeters,
          completed: completed,
        );
        final plannedDistanceKm = _completionRouteResult?.distanceMeters != null
            ? _completionRouteResult!.distanceMeters! / 1000
            : adjustedResult.distanceKm ?? 0;
        final creditProgressFraction =
            GamificationService.completionCreditProgressStep(
              progressFraction,
              completed: completed,
            );
        final xpCoordinates = _buildCompletionCoordinates(
          creditProgressFraction,
        );
        final xpCurves = _estimateCompletionCurves(
          xpCoordinates,
          creditProgressFraction,
        );
        final creditedDistanceKm =
            GamificationService.creditedDistanceKmForProgress(
              plannedDistanceKm: plannedDistanceKm,
              progressRatio: progressFraction,
              completed: completed,
            );
        final xpBreakdown = skipXpSync
            ? null
            : _calculateCompletionXpBreakdown(
                creditedDistanceKm: creditedDistanceKm,
                curves: xpCurves,
              );
        debugPrint(
          '[CruiseMode] Saving route: style=$_selectedStyle, roundTrip=$_isRoundTrip, '
          'distKm=${adjustedResult.distanceKm}, durationSec=${adjustedResult.durationSeconds?.round()}, '
          'progress=${(progressFraction * 100).round()}%, '
          'xpStep=${(creditProgressFraction * 100).round()}%, xp=${xpBreakdown?.totalXp}',
        );
        await SavedRoutesService.saveRoute(
          result: adjustedResult,
          style: _selectedStyle,
          isRoundTrip: _isRoundTrip,
          rating: rating,
          drivenKm: adjustedResult.distanceKm,
          plannedDistanceKm: _completionRouteResult?.distanceMeters != null
              ? _completionRouteResult!.distanceMeters! / 1000
              : adjustedResult.distanceKm,
          xpDistance: xpBreakdown?.distanceXp,
          xpCurveBonus: xpBreakdown?.curveXp,
          xpStyleBonus: xpBreakdown?.styleBonus,
          xpBase: xpBreakdown?.baseXp,
          xpMultiplier: xpBreakdown?.multiplier,
          xpStreakDays: xpBreakdown?.streakDays,
          xpAwarded: xpBreakdown?.totalXp,
          completedAtEnd: completed,
          groupId: widget.groupId,
        );
        await RouteRatingService.saveRating(
          result: adjustedResult,
          rating: rating,
          tags: ratingTags,
          completionPercent: progressFraction * 100,
          distanceKm: adjustedResult.distanceKm,
          durationSeconds: adjustedResult.durationSeconds,
          qualityTier: adjustedResult.edgeMeta['quality_tier']?.toString(),
        );
        await RouteCompletionCandidateService.submitCandidate(
          result: adjustedResult,
          style: _selectedStyle,
          isRoundTrip: _isRoundTrip,
          avoidHighways: _activeAvoidHighways || _avoidHighways,
          savedByUser: true,
          discardedByUser: false,
          completedAtEnd: completed,
          rating: rating,
          ratingTags: ratingTags,
          completionPercent: progressFraction * 100,
        );
        debugPrint('[CruiseMode] Route saved successfully!');
      }
      // XP/Level/Badges synchronisieren (nur wenn über Minimum-Schwelle)
      if (!skipXpSync) {
        final gamResult = await GamificationService.calculateAndSync();
        return CruiseCompletionActionResult(
          success: true,
          newBadges: gamResult.newBadges,
          levelUp:
              previousLevel != null && gamResult.level.level > previousLevel,
          newLevel: gamResult.level.level,
        );
      } else {
        debugPrint(
          '[CruiseMode] XP-Sync übersprungen (unter Minimum-Schwelle)',
        );
      }
      return CruiseCompletionActionResult(success: true);
    } catch (e, stack) {
      debugPrint('Route speichern / XP sync fehlgeschlagen: $e');
      debugPrint('Stack: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Speichern. Bitte erneut versuchen.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return CruiseCompletionActionResult(success: false);
    }
  }

  Future<void> _recordRouteCompletionCandidate({
    required bool completed,
    required bool discarded,
  }) async {
    try {
      final adjustedResult = _buildAdjustedCompletionResult(
        completed: completed,
      );
      if (adjustedResult == null) return;
      final progressFraction = _calculateCompletionProgressFraction(
        adjustedResult.distanceMeters,
        completed: completed,
      );
      if (discarded) {
        await RouteRatingService.saveRating(
          result: adjustedResult,
          rating: null,
          tags: const ['route_discarded'],
          completionPercent: progressFraction * 100,
          distanceKm: adjustedResult.distanceKm,
          durationSeconds: adjustedResult.durationSeconds,
          qualityTier: adjustedResult.edgeMeta['quality_tier']?.toString(),
        );
      }
      await RouteCompletionCandidateService.submitCandidate(
        result: adjustedResult,
        style: _selectedStyle,
        isRoundTrip: _isRoundTrip,
        avoidHighways: _activeAvoidHighways || _avoidHighways,
        savedByUser: false,
        discardedByUser: discarded,
        completedAtEnd: completed,
        ratingTags: discarded ? const ['route_discarded'] : const [],
        completionPercent: progressFraction * 100,
      );
    } catch (error) {
      debugPrint('[CruiseMode] Completion candidate skipped: $error');
    }
  }

  void _resetAfterCompletion() {
    _stopSimulation(restartLiveTracking: false);
    _stopNavigationTracking();
    CruiseModePage.isFullscreen.value = false;
    _xpStreakDays = 1;
    _resetGeneratedRouteUiState();
    final currentLocation = _userLocation;
    if (currentLocation != null) {
      _setCameraToPosition(currentLocation);
    }
  }

  // ═══════════════════════ DIALOGS ══════════════════════════════════════════

  void _showError(String message, {bool isCritical = false}) {
    if (!mounted || _disposed) return;
    debugPrint('[CruiseMode] Error: $message (critical=$isCritical)');

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: isCritical
            ? AppAccentColors.accent
            : const Color(0xFF2A2F3A),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isCritical ? 4 : 3),
        action: isCritical
            ? SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () {},
              )
            : null,
      ),
    );
  }
}

class _CruiseCompletionSnapshot {
  _CruiseCompletionSnapshot({
    required this.distanceKm,
    required this.durationText,
    required this.curves,
    required this.xpEarned,
    required this.xpBreakdown,
    required this.coordinates,
    required this.isEarlyStop,
    required this.belowMinimum,
  });

  final double distanceKm;
  final String durationText;
  final int curves;
  final int xpEarned;
  final RouteXpBreakdown xpBreakdown;
  final List<List<double>> coordinates;
  final bool isEarlyStop;
  final bool belowMinimum;
}

/// iOS Apple-Maps Puck: Kompakter blauer Punkt + dezenter Richtungskeil.
/// Exakt wie Apple Karten — der Pfeil ist ein kleines spitzes Dreieck
/// unterhalb des Punkts, alles auf 44×44 Canvas zentriert.
class _AppleMapsPuckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const blue = Color(0xFF007AFF);

    // ── 1. Richtungskeil (kleines Dreieck, zeigt nach oben = Fahrtrichtung) ──
    final conePaint = Paint()
      ..color = blue.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    final cone = ui.Path()
      ..moveTo(cx, cy - 18) // Spitze
      ..lineTo(cx - 5.5, cy - 7) // Links
      ..lineTo(cx + 5.5, cy - 7) // Rechts
      ..close();
    canvas.drawPath(cone, conePaint);

    // ── 2. Weißer Ring (Schatten + Rand) ──
    final shadowPaint = Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawCircle(Offset(cx, cy), 10.5, shadowPaint);

    final whitePaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 10.5, whitePaint);

    // ── 3. Blauer Kern ──
    final corePaint = Paint()
      ..color = blue
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 7.5, corePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Standard Navigations-Pfeil für Web/Android/macOS (bisheriges Design).
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
