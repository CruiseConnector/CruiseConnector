import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/route_bookmark_provider.dart';
import 'package:cruise_connect/application/providers/saved_routes_provider.dart';
import 'package:cruise_connect/data/services/web_position_smoother.dart';
import 'package:cruise_connect/data/services/native_position_smoother.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cruise_connect/data/services/country_region.dart';
import 'package:cruise_connect/data/services/geocoding_service.dart';
import 'package:cruise_connect/data/services/voice_settings_service.dart';
import 'package:cruise_connect/data/services/tts_service.dart';
import 'package:cruise_connect/data/services/trip_service.dart';
import 'package:cruise_connect/data/services/route_poi_service.dart';
import 'package:cruise_connect/data/services/opening_hours_parser.dart';
import 'package:cruise_connect/presentation/widgets/cruise/poi_detail_sheet.dart';
import 'package:cruise_connect/presentation/widgets/cruise/poi_filter_sheet.dart';
import 'package:cruise_connect/data/services/road_hazard_service.dart';
import 'package:cruise_connect/data/services/poi_settings_service.dart';
import 'package:cruise_connect/presentation/widgets/weather_inline.dart';
import 'package:cruise_connect/presentation/widgets/top_toast.dart';
import 'package:cruise_connect/data/services/driven_track_recorder.dart';
import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:cruise_connect/data/services/navigation_reroute_decision.dart';
import 'package:cruise_connect/data/services/navigation_progress_socket_service.dart';
import 'package:cruise_connect/data/services/offline_map_service.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;
import 'package:cruise_connect/data/services/cruise_dark_map_style.dart';
import 'package:cruise_connect/data/services/car_route_bridge_service.dart';
import 'package:cruise_connect/data/services/car_command_listener.dart';
import 'package:cruise_connect/data/services/frame_timing_utils.dart';
import 'package:cruise_connect/data/services/group_route_data_builder.dart';
import 'package:cruise_connect/data/services/route_access_plan.dart';
import 'package:cruise_connect/data/services/roundabout_topology_service.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/data/services/route_cache_service.dart';
import 'package:cruise_connect/data/services/route_completion_candidate_service.dart';
import 'package:cruise_connect/data/services/route_pool_service.dart';
import 'package:cruise_connect/data/services/route_rating_service.dart';
import 'package:cruise_connect/data/services/route_render_lock.dart';
import 'package:cruise_connect/data/services/smart_reroute_engine.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/place_suggestion.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart'
    show RouteManeuver, RouteWindowMatch, ManeuverType;
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_completion_dialog.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_maneuver_indicator.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_navigation_info_panel.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_setup_card.dart';
import 'package:cruise_connect/presentation/widgets/cruise/drive_control_panel.dart';
import 'package:cruise_connect/presentation/widgets/cruise/routing_onboarding_sheet.dart';
import 'package:cruise_connect/presentation/widgets/cruise/construction_alert_sheet.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_maplibre_map.dart';
import 'package:cruise_connect/domain/models/construction_report.dart';
import 'package:cruise_connect/data/services/construction_geofence.dart';
import 'package:cruise_connect/data/services/construction_report_service.dart';
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

  /// 2026-05-24 (vucko Task #53): Trip-Resume-Signal.
  /// Wird gesetzt wenn HomeCarousel auf Trip-Resume-Card geklickt wird.
  /// CruiseModePage hört darauf und lädt TripService.stopsFor(tripId)
  /// + setzt Wegpunkte + öffnet Routing-Sheet im Trip-Mode.
  static final ValueNotifier<String?> pendingTripResume =
      ValueNotifier<String?>(null);

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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // 2026-06-10 (vucko Find-My-Härtung): App kommt aus dem Hintergrund zurück
  // (Lock/Anruf/App-Switch — die typischen Netz-Blip-Momente): Gruppen-
  // Realtime sofort hart neu aufbauen + backfillen, statt auf Timer zu warten.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    final groupId = widget.groupId;
    if (groupId == null || !mounted || _disposed) return;
    final meId = Supabase.instance.client.auth.currentUser?.id;
    _lastGroupRealtimeEventAt = DateTime.now();
    _startGroupMembersRealtime(groupId, meId);
    unawaited(
      _reloadGroupMembersFromBackfill(groupId, meId, forceRebuild: true),
    );
    unawaited(_uploadMyPosition());
  }

  // ─────────────────────── Services ──────────────────────────────────────────
  final _geocodingService = const GeocodingService();
  final _routeService = RouteService();
  final _carRouteBridge = CarRouteBridgeService();
  // 2026-06-02 (vucko Sync): true solange der Abschluss-Screen (Bewertung)
  // offen ist — damit CarPlays „Fertig" das Handy-Sheet gezielt schließen kann.
  bool _completionSheetOpen = false;
  final _smartRerouteEngine = const SmartRerouteEngine();
  final _navigationSocketService = NavigationProgressSocketService();
  final _drivenTrackRecorder = DrivenTrackRecorder();

  // ─────────────────────── Route Setup State ─────────────────────────────────
  bool _isRoundTrip = true;
  String _planningType = 'Zufall';
  String _selectedLength = '50 Km';
  String _selectedLocation = 'Aktueller Standort';
  // 2026-05-28 (vucko): "Standort wählen" — vom User gesetzter Startpunkt
  // (Karten-Tap ODER Adresssuche). Wenn gesetzt + _selectedLocation ==
  // 'Standort wählen', startet die Route von hier statt vom GPS.
  LatLng? _pickedStartLocation;
  String? _pickedStartLabel; // Reverse-geocodeter Ortsname für die Anzeige.
  bool _isPickingStartOnMap = false; // Karten-Tap setzt gerade den Startpunkt.
  final TextEditingController _startLocationController =
      TextEditingController();
  final FocusNode _startLocationFocusNode = FocusNode();
  String _selectedStyle = 'Sport Mode';
  String _selectedDetour = 'Direkt';
  // 2026-05-30 (vucko): Länder-Präferenz (egal / eher im Land / nur im Land).
  // Weiches Scoring — nie ein harter Reject (sonst Vorarlberg-Explosion).
  CountryPreference _countryPreference = CountryPreference.any;
  String? _homeCountryCode; // Auto-erkannt via Reverse-Geocode am Start.
  // 2026-05-28 (vucko Task #83): One-Shot — nächste A→B-Suche erzwingt eine
  // direkte Route ohne Quality-Reject ("Direkte Route nehmen").
  bool _forceAcceptDirectOnce = false;
  bool _avoidHighways = false;
  final TextEditingController _destinationController = TextEditingController();
  // 2026-05-28 (vucko Startup-V Issue 3A): Eigener FocusNode für das A→B-
  // Suchfeld. Hat das Feld Fokus (User tippt eine Adresse), blenden wir die
  // Bottom-Actions (Route berechnen/bestätigen) aus, damit das Autocomplete-
  // Overlay sie nicht überlagert und der User einen Vorschlag auswählen kann.
  final FocusNode _destinationFocusNode = FocusNode();
  bool _destinationHasFocus = false;

  // ─────────────────────── A-to-B Route Selection State ──────────────────────
  PlaceSuggestion? _selectedDestination;

  // ─────────────────────── Route Result State ────────────────────────────────
  bool _isRouteConfirmed = false;
  String? _routeGeoJson;
  double? _routeDistance;
  double? _routeDuration;
  RouteResult? _lastRouteResult;
  RouteResult? _sessionRouteResult;
  bool _configCollapsed = false; // Config-Panel ein-/ausgeklappt
  // 2026-05-28 (vucko Startup-V Issue 1): Scroll-Position des ausgeklappten
  // Setup-Panels. Solange noch Inhalt nach unten kommt, zeigen wir am unteren
  // Rand einen Fade + Chevron als „mehr unten"-Hinweis.
  final ScrollController _configScrollController = ScrollController();
  bool _configCanScrollDown = false;
  bool _showRouteInfoBanner = false; // Route-Info Banner nach Generation
  // 2026-05-31 (vucko): Preview-Banner per Hochwischen weggewischt → statt des
  // vollen Banners erscheint eine kompakte Recall-Pille. Tipp/Runterwischen
  // holt die Route-Info wieder zurück ("lebendiges" Gefühl). Wird bei jeder
  // neuen Route zurückgesetzt.
  bool _routeBannerDismissed = false;
  bool _routeWarmupDialogOpen = false;
  String? _routeSearchNoticeTitle;
  String? _routeSearchNoticeMessage;
  double _routeSearchProgress = 0.08;
  bool _routeSearchStatusLeaving = false;
  bool _routeSearchDismissScheduled = false;
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
  // Defensive Layer gegen den Duplikat-Bug: wenn die Edge-Function trotz
  // forceFreshVariant + previousFingerprints aus Race-Conditions oder
  // Pool-Engpass die GLEICHE Route zurückliefert, fängt das die UI hier ab.
  // Statt einer „keine neue Variante"-Snackbar (verwirrt mehr als sie
  // hilft) triggern wir bis zu 2 automatische Re-Suchen mit
  // forceFreshVariant=true — Calimoto-Pattern: User klickt Search Again,
  // App soll selbst weiter rotieren bis was Neues kommt.
  String? _lastDisplayedRouteFingerprint;
  int _searchAgainAutoRetryCount = 0;
  DateTime? _searchAgainAutoRetryWindowStart;
  static const int _maxSearchAgainAutoRetries = 2;
  // 2026-06-02 (vucko): Länder-Gate-Retry-Felder entfernt — „Im Land bleiben"
  // ist jetzt SOFT (blockiert nie), daher keine UI-Retry-Schleife mehr nötig.
  // Wall-Clock-Cap: Auto-Retry-Counter wird nach 30s zurückgesetzt. Verhindert
  // dass ein gestauter Edge-Server endlose UI-Re-Suchen triggert.
  static const Duration _searchAgainAutoRetryWindow = Duration(seconds: 30);
  List<double> _recentDestinationDistances = [];
  List<SpeedLimitSegment> _activeSpeedLimits = [];

  // ─────────────────────── Map State (flutter_map) ───────────────────────────
  bool _isLoading = false;
  bool _isPreparingExistingRoute = false;
  Timer? _routeLoadingPhaseTimer;
  Timer? _routeSearchExitTimer;
  int _routeLoadingPhaseIndex = 0;
  final MapController _mapController = MapController();
  // 2026-06-03 (vucko): MapLibre GL Native als neue Karten-Engine — Mapbox-Look,
  // GPU-flüssig, rendert PMTiles KORREKT (kein vector_tile_renderer-Stottern/
  // Muster). `_useMapLibre` schaltet zwischen neuer MapLibre-Karte und alter
  // flutter_map-Karte um → sofortiges Sicherheitsnetz, falls auf dem Gerät in
  // der Navigation etwas hakt (der eingeloggte Screen war am Sim nicht testbar).
  static const bool _useMapLibre = true;
  CruiseMapLibreController? _mlController;
  bool _mapReady = false;
  final List<LatLng> _roundTripWaypoints = [];
  int? _selectedRoundTripWaypointIndex;
  int? _replaceRoundTripWaypointIndex;
  int _waypointSeedCounter = 0;
  String _roundTripWaypointOrigin = 'manual';
  int _roundTripWaypointSeedAttempt = 0;
  // 2026-05-22 (vucko): Trip-Modus erweitert max-WPs auf 5 (statt 3 default).
  // User toggled via TripMode-Switch. First-Use Tutorial-Overlay zeigt
  // sich wenn _waypointTutorialShown == false.
  bool _tripModeEnabled = false;
  // 2026-05-24 (vucko Task #53): Trip-DB-ID wenn Trip-Mode aktiv + Route gestartet.
  // null = kein Trip aktiv. Bei Pause/Verlassen → TripService.pauseTrip(this).
  String? _activeTripId;
  // 2026-06-10 (vucko Resume-Crash-Fix): verhindert Doppel-Resume, solange der
  // pendingTripResume-Intent (jetzt erst nach Erfolg konsumiert) noch gesetzt ist.
  bool _tripResumeInFlight = false;
  bool _waypointTutorialShown = false;
  static const int _maxWaypointsNormal = 3;
  static const int _maxWaypointsTripMode = 5;
  int get _currentMaxWaypoints =>
      _tripModeEnabled ? _maxWaypointsTripMode : _maxWaypointsNormal;
  // Route als LatLng-Liste für PolylineLayer
  List<LatLng> _routeLatLngs = [];
  Timer? _routeDrawAnimationTimer;
  int _routeDrawAnimationToken = 0;
  // 2026-05-28 (vucko Task #86 / Startup-V Issue 2): Memoisierte Gesamt-Route
  // als gedimmte Hintergrund-Polyline. Während der Fahrt zeichnen wir nur das
  // 3km-Sliding-Window hell — ohne Hintergrund sah es aus als würde die Route
  // abrupt enden („schaut kaputt aus"). Cache-Key ist die Identität der
  // _fullRouteCoordinates-Liste, damit nicht bei jedem GPS-Tick (200ms)
  // re-konvertiert wird.
  List<LatLng> _fullRouteLatLngsCache = const [];
  List<List<double>>? _fullRouteLatLngsCacheSource;
  List<LatLng> get _fullRouteBackgroundLatLngs {
    if (!identical(_fullRouteLatLngsCacheSource, _fullRouteCoordinates)) {
      _fullRouteLatLngsCacheSource = _fullRouteCoordinates;
      _fullRouteLatLngsCache = _fullRouteCoordinates.length < 2
          ? const []
          : _fullRouteCoordinates
                .map((c) => LatLng(c[1], c[0]))
                .toList(growable: false);
    }
    return _fullRouteLatLngsCache;
  }

  // Aktuelle User-Position als Marker
  LatLng? _userPosition;
  double _userHeading = 0.0; // GPS-Heading in Grad (0=Nord, 90=Ost)

  /// Marker-Größe: iOS-Puck ist kompakter (44px) als Default (80px).
  double get _puckSize => !kIsWeb && Platform.isIOS ? 44.0 : 80.0;

  // ─────────────────────── Navigation State ─────────────────────────────────
  geo.Position? _userLocation;
  // 2026-06-06 (vucko P10): Letzter bekannter Standort, STATISCH über Page-Opens
  // hinweg gecacht. Wird als initialCenter der Karte benutzt → beim Öffnen der
  // Cruise-Page ist man SOFORT auf dem Standort statt erst „Deutschland-Mitte@z6"
  // zu sehen, bis das asynchrone GPS aufgelöst hat.
  static LatLng? _cachedUserCenter;
  // 2026-06-08 (vucko Kamera-Fix): EINMAL fixierte Initial-Kamera (siehe
  // _buildMapLibreMap) — verhindert Map-Widget-Neuerzeugung pro GPS-Tick.
  LatLng? _stableInitialCenter;
  double? _stableInitialZoom;
  List<List<double>> _fullRouteCoordinates = [];
  List<List<double>> _remainingRouteCoordinates = [];
  // 2026-06-10 (vucko 3km-Sichtdesign v2): helles 3km-Fenster ab Puck (bright)
  // + dezente Reststrecke ab Puck (dim, 200m-gegated). Kein Trail mehr.
  List<LatLng> _brightAheadLatLngs = const [];
  List<LatLng> _dimRemainingLatLngs = const [];
  List<double>? _lastDimHead;
  // 2026-06-09 (vucko Voll-Route-Sichtbar): grauer „Driven-Trail" = begrenztes
  // Fenster HINTER dem Puck. Die rote aktive Linie (_routeLatLngs) ist jetzt die
  // VOLLE Route (statisch) → immer sichtbar, kein 3km-Abschnitt mehr; dieser
  // graue Trail frisst den abgefahrenen Teil hinter dem Puck deckend auf.
  List<LatLng> _drivenTrailLatLngs = const [];
  List<double>?
  _lastDrivenHead; // Puck-Projektion des letzten Trail-Pushes (Gate)
  // 2026-06-08 (vucko Leitlinie GPU-Trim): Metriken der aktiven Route für das
  // line-gradient-Trimmen. _activeRouteLatLngs = volle Route (an die Karte, wird
  // dort EINMAL je Wechsel gesetzt). _routeCumDist = kumulierte Distanz je Punkt;
  // _routeProgress 0..1 = Fraktion bis zum Puck (= Trim-Punkt). _routeMetricsSig
  // erkennt Routen-/Reroute-Wechsel → Neuberechnung + Progress-Reset.
  String _routeMetricsSig = '';
  List<double> _routeCumDist = [];
  double _routeTotalLenM = 0.0;
  double _routeProgress = 0.0;
  List<RouteManeuver> _maneuvers = [];
  int _activeManeuverIndex = 0;
  int _currentRouteIndex = 0;
  final Set<int> _announcedManeuverIndices = <int>{};
  // 2026-05-24 (vucko Task #44): POI-Layer (Tankstellen etc.)
  bool _poisVisible = false;
  bool _poisLoading = false;
  List<RoutePoi> _routePois = const [];
  final Set<PoiType> _poiTypes = const {PoiType.fuel};
  // 2026-05-24 (vucko Task #45): Road-Hazard-Detection (OSM construction).
  // Aktuell als Toast-Warnung beim Route-Build genutzt; Liste wird für
  // zukünftige Map-Marker-Overlay-Iteration vorgehalten.
  // ignore: unused_field
  List<RoadHazard> _roadHazards = const [];
  // ignore: unused_field
  bool _hazardCheckDone = false;
  // 2026-05-28 (vucko Task #66): Baustellen-Crowdsourcing (Supabase +
  // OSM Overpass). Liste wird beim Route-Build gefiltert auf die Route,
  // Geofence triggert das Alert-Sheet während der Fahrt.
  List<ConstructionReport> _routeConstructions = const [];
  final ConstructionGeofence _constructionGeofence = ConstructionGeofence();
  String? _activeConstructionAlertId;
  // 2026-05-23 (vucko): Haptic-Tracking damit jede Stufe (300m/150m/50m)
  // nur 1× pro Manöver feuert statt bei jedem GPS-Tick.
  int? _lastHapticManeuverIndex;
  bool _hapticStage300m = false;
  bool _hapticStage150m = false;
  bool _hapticStage50m = false;
  StreamSubscription<geo.Position>? _positionSubscription;
  StreamSubscription<geo.Position>? _socketPositionSubscription;
  StreamSubscription<geo.Position>?
  _idlePositionSubscription; // Standort-Stream für Heading im Idle

  // Fahrsimulator entfernt; bleibt immer false, damit bestehende
  // Navigation-Helfer keinen Simulationspfad aktivieren.
  final bool _isSimulationRunning = false;

  bool _isCameraLocked =
      false; // Compass-Toggle: true = Kamera folgt dem Standort
  double? _remainingDistance; // Live verbleibende Distanz in Metern
  double? _remainingDuration; // Live verbleibende Zeit in Sekunden
  bool _isRerouting = false; // Verhindert mehrfaches gleichzeitiges Rerouting
  DateTime? _rerouteStartedAt;
  // 2026-06-13 (vucko J4): _rerouteBannerShown entfernt — es gibt keinen
  // separaten Reroute-Toast mehr (das obere Banner zeigt „Neuberechnung").
  DateTime? _lastRerouteTime; // Cooldown zwischen Reroutes
  bool _lastRerouteFailed = false;
  int _offRouteCount = 0; // Zählt aufeinanderfolgende Off-Route-Updates
  // 2026-06-15 (vucko N-Runde-2, Geräte-Video: 3 Phantom-Reroutes MITTEN in der
  // Fahrt bei dead-on Puck): Mapbox-/Google-Regel — Zähler aufeinanderfolgender
  // Off-Route-Fixes, den JEDER „auf-Route"-Fix sofort auf 0 setzt. Ein 2-3s-
  // Multipath-Ausreißer (Kurve/Auffahrt/Baumdecke) kann so per Definition nie die
  // nötigen ≥4 Fixes am Stück „off" erreichen. Ersetzt die Zeit-Hysterese
  // (_offRouteSince) als Auslöse-Kriterium. [[navi_n1_n2_phantom_roundabout_2026_06_15]]
  int _consecutiveOffRouteFixes = 0;

  // 2026-06-16 (vucko O4): Post-Reroute-Lock-Grace. Nach einem Reroute wird die
  // Lock-On-Grace neu gestartet (Lock zurückgesetzt) und für dieses Fenster die
  // 90s-Grace-Decke ausgesetzt — sonst rastet der Puck sofort wieder „ein" und
  // ein minimal neben der Fahrbahn liegender frischer Routen-Abschnitt löst eine
  // Reroute-Kaskade aus (User-Video: „rerouted auch wenn ich der Route folge").
  DateTime? _postRerouteGraceUntil;
  // 2026-06-07 (vucko P-reroute): Zeit-basierte Hysterese wie Apple/Google —
  // Off-Route muss ANHALTEND sein (Wall-Clock), nicht nur N Ticks (bei 20Hz-Sim
  // wären 5 Ticks = 0.25s = viel zu zappelig). Gesetzt beim ersten Außerhalb-
  // Tick, geleert sobald wieder im Korridor ODER der Puck weiter vorankommt.
  DateTime? _offRouteSince;
  // 2026-06-13 (vucko Video Banner-Freeze): Luftlinien-Abstand GPS→Route,
  // solange der Fahrer off-route ist (sonst 0). Wird auf die Manöver-Distanz
  // addiert → die Meter-Anzeige WÄCHST ehrlich beim Wegfahren (Google-
  // Verhalten), statt minutenlang auf dem letzten On-Route-Wert einzufrieren.
  double _offRouteGapMeters = 0.0;
  // 2026-06-15 (vucko N1, Geräte-Fahrt 23min): Phantom-Reroutes am Fahrtbeginn.
  // Der SICHTBARE Puck ist route-locked (klebt auf der Linie), die Off-Route-
  // Prüfung nutzt aber das ROHE GPS. Beim Kaltstart (Multipath/Schlucht,
  // schlechte Accuracy, Access-Leg-Versatz) reißt Roh-GPS sekundenlang seitlich
  // aus und löst grundlose „Neuberechnung" aus, die der Nutzer NIE als Abweichung
  // sieht (der gesnappte Puck wirkt dead-on). Genau das, was Apple (Patent
  // US9835469B2 „Start-of-route … suppression of off-route feedback") und Mapbox
  // (`isWithinDepartureStep`/`isQualified`/`RouteSnappingMinimumHorizontalAccuracy`)
  // unterbinden: NIE auf rohem GPS rerouten, erst bei eingerastetem Puck. Erst wenn
  // der Puck nachweislich (≥4 Fixes, ≤25m senkrecht, Accuracy ≤35m) eingerastet
  // ist, gilt normale Off-Route-Logik voll. Vorher nur bei eindeutigem,
  // gut-vermessenem Verfahren (>2× Korridor & gute Accuracy). [[navi_m1_m5_crash_reroute_2026_06_15]]
  int _onRouteLockStreak = 0;
  bool _routeLockedOn = false;
  static const double _lockOnPerpMeters = 25.0;
  static const double _lockOnMaxAccuracyMeters = 35.0;
  static const int _lockOnStreakNeeded = 4;
  // Harte Decke der Kaltstart-Grace: nach 90s ist die Anfangsphase definitiv
  // vorbei (auch bei dauerhaft mäßigem GPS, das nie ≤35m einrastet) → normale
  // Off-Route-Logik, damit ein echtes Verfahren NIE ewig unterdrückt bleibt. Der
  // beobachtete Phantom-Cluster lag ganz innerhalb der ersten ~66s.
  static const Duration _lockOnGraceCeiling = Duration(seconds: 90);
  // Mapbox isQualified: Fix mit Accuracy ≤0 oder >100m ist unbrauchbar und darf
  // NIE off-route voten (er bewegt weiter den Puck, aber nicht das Reroute).
  static const double _maxQualifiedAccuracyMeters = 100.0;
  // 2026-06-13 (vucko Verfahren-„kracht"): Übergangs-Blend der Puck-Quelle
  // (Route-gesnappt ↔ frei) — siehe _blendPuckTransition.
  LatLng? _puckBlendFrom;
  DateTime? _puckBlendStartAt;
  // 2026-06-15 (vucko N-Runde-2, „off-route nicht flüssig"): Zeitstempel des
  // letzten Frei-Puck-Ease-Frames für die framerate-unabhängige Glättung.
  DateTime? _lastFreePuckEaseAt;
  bool _puckSourceWasLocked = false;
  // 2026-06-13 (vucko Google/Apple-Bar-Review F6-2): 600→220ms. 600ms zeigte
  // den Puck bis ~300ms auf einer Zwischenposition (Lag zur echten Position
  // bei Tempo); Google/Apple springen quasi sofort. 220ms ist gerade noch
  // weich, aber unter der Wahrnehmungsschwelle für „Puck hinkt nach".
  static const Duration _puckBlendDuration = Duration(milliseconds: 220);
  // 2026-06-12 (vucko): Manoever-Ueberfahren-Tracking fuer den Sofort-Reroute.
  int? _overshootManeuverIndex;
  double _overshootMinDistM = double.infinity;
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
  // 2026-06-07 (vucko P-reroute): _offRouteCountThreshold (Tick-Count) entfernt —
  // durch zeit-basierte Hysterese (_offRouteSince, ≥3s/≥1.5s) ersetzt.
  // 2026-06-12 (vucko Video): 12s -> 6s. Wer den frischen Reroute sofort
  // wieder verlaesst (haeufig beim Verfahren), wartete sonst sichtbar lange
  // auf den naechsten Versuch. Fehlschlaege behalten ihren eigenen Cooldown.
  // 2026-06-16 (Codex Video-Befund): Reroute muss nach echtem Verfahren
  // innerhalb von ca. 4s sichtbar aktiv sein. Die Hysterese unten erkennt
  // schneller; der Cooldown darf danach nicht wieder 3-4s blockieren.
  static const Duration _rerouteCooldown = Duration(seconds: 2);
  static const Duration _rerouteFailureCooldown = Duration(seconds: 3);
  // Ketten-Reroute: Commit landete nachweislich hinter dem Fahrer (>80m) →
  // sofort mit frischer Position nachrouten, Cooldown überspringen. Max 2×
  // hintereinander (Schutz gegen Loops bei kaputtem GPS).
  bool _pendingChainedReroute = false;
  int _chainedRerouteCount = 0;
  // 2026-06-01 (vucko): Max. Versatz, bis zu dem der sichtbare Routenkopf an
  // die GPS-Position geheftet wird. Darüber bleibt der echte Routenpunkt der
  // Kopf → keine Off-Route-Zacken bei GPS-Drift in Bergtälern.
  static const double _headSnapMaxMeters = 18.0;
  // 2026-06-09 (vucko Voll-Route-Sichtbar): die früheren Redraw-Schwellen
  // (_routeRedrawIndexThreshold / _routeRedrawDistanceMeters) sind entfallen — es
  // gibt keinen 3km-Sliding-Window-Redraw der sichtbaren Linie mehr (rote Linie =
  // statische Voll-Route, grauer Driven-Trail macht den Schnitt).
  double _totalDistanceDriven = 0.0; // Gesamte gefahrene Strecke in Metern
  DateTime? _navigationStartTime; // Zeitpunkt des Navigations-Starts
  // 2026-06-03 (vucko): Getter _isActivelyDriving entfernt — die Karte rendert
  // jetzt IMMER im Raster-Modus (flüssig + einheitlich), nicht mehr abhängig vom
  // Fahr-Status. _navigationStartTime bleibt für _isActivelyDrivingRoute aktiv.
  int _xpStreakDays = 1;
  bool _driveSessionRecordedForCompletion = false;
  double?
  _originalRouteDistance; // Ursprüngliche Gesamtdistanz (für Zeitberechnung)
  double?
  _originalRouteDuration; // Ursprüngliche Gesamtdauer (für Zeitberechnung)
  double? _distanceToFinalTargetMeters;
  // 2026-06-09 (vucko Trip-Skip): Aktive Zwischenstopps der laufenden A→B-/
  // Trip-/Wegpunkte-Route ([lng,lat], geplante Reihenfolge) + welche bereits
  // besucht ODER bewusst übersprungen wurden. Grundlage für Reroutes, die durch
  // die VERBLEIBENDEN Stopps führen (statt stumm direkt zum Endziel), und fürs
  // automatische Überspringen: Lässt der Fahrer einen Stopp aus, wird zum
  // näheren von (nächster verbleibender Stopp | Endziel) gereroutet.
  List<List<double>> _activeIntermediateWaypoints = const [];
  final Set<int> _passedWaypointIndices = <int>{};

  // Schwellenwerte für Completion-Status. XP basiert auf real gefahrenen km.
  static const double _minProgressForXpCredit =
      GamificationService.minRouteProgressForXp;
  static const double _minProgressForFullCredit =
      1.0; // Nur echte Zielankunft zählt als abgeschlossen.
  static const double _minProgressForAutomaticCompletion = 0.95;
  static const double _roundTripFinishArmProgress = 0.80;
  static const double _arrivalRadiusMeters = 50.0;
  int _lastDrawnRouteIndex =
      0; // Letzter Index bei dem die Route neu gezeichnet wurde
  double _distanceSinceLastRedraw = 0.0;

  bool _disposed = false;

  // ─────────────────────── Group / Live Tracking ────────────────────────────
  RealtimeChannel? _groupRouteCh;
  RealtimeChannel? _groupMembersCh;
  Timer? _positionUploadTimer;
  DateTime? _lastGroupRealtimeEventAt;
  // 2026-06-10 (vucko Find-My-Smoothness): Peer-Marker gleiten zur neuesten
  // Zielposition statt alle ~2s hart zu springen (39m-Spruenge bei 70 km/h).
  // shown = angezeigte Position (lng,lat), target = letzte empfangene.
  final Map<String, List<double>> _peerShownPos = {};
  final Map<String, List<double>> _peerTargetPos = {};
  Timer? _peerAnimTimer;
  Timer? _groupRouteBackfillTimer;
  Timer? _groupRouteReconnectTimer;
  Timer? _groupMembersBackfillTimer;
  Timer? _groupMembersReconnectTimer;
  Timer? _groupMembersFreshnessTimer;
  // 2026-06-02 (vucko): Debounce für automatisches Nachladen der Viewport-POIs
  // beim Schwenken/Zoomen (mehr POIs je weiter rausgezoomt).
  Timer? _viewportPoiDebounce;
  bool _groupRouteBackfillInFlight = false;
  bool _groupMembersBackfillInFlight = false;
  bool _canPublishGroupRoute = false;
  // 2026-06-10 (vucko Gruppen-Reroute-Regel): true, sobald ICH der aktiven
  // (Gruppen-)Route real gefolgt bin (on-route <80m). Nur dann darf mein
  // Reroute die GRUPPEN-Route ersetzen — ein Late-Joiner, der noch nie auf
  // der Route war, loest fuer die Gruppe KEIN Reroute aus und sieht die
  // KOMPLETTE Route kraeftig, bis er selbst drauf faehrt.
  bool _everOnActiveRoute = false;
  bool _applyingGroupRouteUpdate = false;
  int _groupRouteRevision = 0;
  Map<String, dynamic>? _activeGroupRouteData;
  final Map<String, GroupMember> _groupMembers = {};
  static const Duration _groupPositionUploadInterval = Duration(seconds: 2);
  static const Duration _groupRouteBackfillInterval = Duration(seconds: 15);
  static const Duration _groupRouteReconnectDelay = Duration(seconds: 3);
  // 2026-06-10 (vucko Find-My-Härtung): Backfill enger (5s) — er ist das
  // Sicherheitsnetz gegen "silent dead" Realtime-Channels nach Netz-Blips.
  static const Duration _groupMembersBackfillInterval = Duration(seconds: 5);
  // Watchdog: kommt >15s weder ein Realtime-Event noch ein erfolgreicher
  // Backfill an, wird der Channel HART neu aufgebaut (Socket-Blip-Recovery).
  static const Duration _groupRealtimeWatchdogAge = Duration(seconds: 15);
  static const Duration _groupMembersReconnectDelay = Duration(seconds: 3);
  static const Duration _groupMembersFreshnessTick = Duration(seconds: 5);
  static const Duration _groupMemberFreshLocationAge = Duration(seconds: 12);

  // Web-only: Letzte setState-Zeit für Throttling (max. 1 Rebuild / 16ms auf Web)
  DateTime? _lastWebRebuildTime;

  // Web-only: GPS-Smoother für flüssige Positionsdarstellung (Kalman-Filter)
  final WebPositionSmoother _webSmoother = WebPositionSmoother();

  // iOS/Android: Native GPS-Smoother mit Heading-Fusion (Kalman-Filter)
  final NativePositionSmoother _nativeSmoother = NativePositionSmoother(
    minMovementMeters: 0.35,
    maxJumpMeters: 500.0,
    minHeadingDistanceMeters: 1.2,
    headingSmoothingFactor:
        0.62, // reaktiver, damit Fahrzeug und Karte nicht nachziehen
    processNoise: 3.2,
    stationaryNoiseMeters: 1.2,
    headingNoiseThresholdDegrees: 6.0,
    lowSpeedThresholdMs: 2.5, // Unter 9 km/h: Bewegungs-Heading priorisieren
    highSpeedThresholdMs: 8.0, // Über 29 km/h: GPS-Heading priorisieren
  );

  // Animierte Kamera-Bewegung zwischen GPS-Updates (alle Plattformen)
  AnimationController? _cameraAnimController;
  double _camToLat = 0.0;
  double _camToLng = 0.0;
  double _camToHeading = 0.0;
  double _lastCameraHeading = 0.0; // Für Bearing-Dead-Zone (< 5° ignorieren)
  // 2026-06-08 (vucko Butterweich): KONTINUIERLICHER Smooth-Follow. _camCur* ist
  // der pro Frame sanft Richtung _camTo* gezogene Kamera-Stand; pro Frame EIN
  // INSTANTES moveCamera (kein engine-Ease → kein Puls-Ruckeln der 5Hz-Animation).
  double _camCurLat = 0.0, _camCurLng = 0.0, _camCurHeading = 0.0;
  bool _camHasState = false;
  bool _camMoveInFlight = false; // Coalescing — kein Method-Channel-Stau
  DateTime? _lastCameraFrameAt;

  // ──────────────────────────────────────────────────────────────────────────

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_disposed) setState(fn);
  }

  static const List<String> _roundTripLoadingPhases = [
    'Wir suchen eine passende Route',
    'Alternativen werden geprüft',
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

  static const List<String> _groupLoadingPhases = [
    'Route abstimmen',
    'Gruppe synchronisieren',
    'Fast fertig',
  ];

  String get _routeLoadingStatusText {
    if (widget.groupId != null) {
      final phaseIndex = _routeLoadingPhaseIndex.clamp(
        0,
        _groupLoadingPhases.length - 1,
      );
      return _groupLoadingPhases[phaseIndex];
    }
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
    _routeSearchExitTimer?.cancel();
    _safeSetState(() {
      _isLoading = true;
      _isPreparingExistingRoute = preparingExistingRoute;
      _activeRouteGenerationSerial = generationId;
      _routeGenerationCancelled = false;
      _showRouteInfoBanner = false;
      _routeLoadingPhaseIndex = 0;
      _routeSearchProgress = 0.08;
      _routeSearchStatusLeaving = false;
      _routeSearchDismissScheduled = false;
      _routeSearchNoticeTitle = null;
      _routeSearchNoticeMessage = null;
      _configCollapsed = true;
    });
    unawaited(
      _carRouteBridge.publishSearching(
        routeType: _carRouteType,
        style: _selectedStyle,
        avoidHighways: _avoidHighways,
      ),
    );
    _routeLoadingPhaseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted ||
          _disposed ||
          !_isLoading ||
          _activeRouteGenerationSerial != generationId) {
        return;
      }
      _safeSetState(() {
        _routeSearchProgress = math.min(_routeSearchProgress + 0.024, 0.92);
        final phaseCount = widget.groupId != null
            ? _groupLoadingPhases.length
            : _isPreparingExistingRoute
            ? _existingRouteLoadingPhases.length
            : _isWaypointPlanning
            ? _waypointLoadingPhases.length
            : !_isRoundTrip
            ? _pointToPointLoadingPhases.length
            : _roundTripLoadingPhases.length;
        _routeLoadingPhaseIndex = math.min(
          (_routeSearchProgress * phaseCount).floor(),
          phaseCount - 1,
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
    if (!_routeSearchStatusLeaving && !_routeSearchDismissScheduled) {
      _routeSearchExitTimer?.cancel();
    }
    _safeSetState(() {
      _isLoading = false;
      _isPreparingExistingRoute = false;
      _routeLoadingPhaseIndex = 0;
      if (!_routeSearchStatusLeaving && !_routeSearchDismissScheduled) {
        _routeSearchProgress = 0.08;
      }
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
    _routeSearchExitTimer?.cancel();
    _safeSetState(() {
      _routeGenerationCancelled = true;
      _activeRouteGenerationSerial = null;
      _isLoading = false;
      _isPreparingExistingRoute = false;
      _routeLoadingPhaseIndex = 0;
      _routeSearchProgress = math.min(_routeSearchProgress, 0.92);
      _routeSearchStatusLeaving = false;
      _routeSearchDismissScheduled = false;
      _routeSearchNoticeTitle = 'Suche abgebrochen';
      _routeSearchNoticeMessage =
          'Wir übernehmen keine Route aus dieser Suche. Du kannst jederzeit neu starten.';
    });
    _scheduleRouteSearchStatusDismiss(hold: const Duration(milliseconds: 1800));
  }

  void _hideRouteSearchStatusForAcceptedRoute() {
    _routeLoadingPhaseTimer?.cancel();
    _routeLoadingPhaseTimer = null;
    _routeSearchExitTimer?.cancel();
    _safeSetState(() {
      _isLoading = false;
      _isPreparingExistingRoute = false;
      _activeRouteGenerationSerial = null;
      _routeGenerationCancelled = false;
      _routeLoadingPhaseIndex = 0;
      _routeSearchProgress = 1.0;
      _routeSearchNoticeTitle = 'Route gefunden';
      _routeSearchNoticeMessage = 'Die Route ist bereit.';
      _routeSearchStatusLeaving = false;
      _routeSearchDismissScheduled = false;
    });
    _scheduleRouteSearchStatusDismiss(hold: const Duration(milliseconds: 2600));
  }

  void _scheduleRouteSearchStatusDismiss({
    Duration hold = const Duration(milliseconds: 2200),
  }) {
    _routeSearchExitTimer?.cancel();
    _routeSearchDismissScheduled = true;
    _routeSearchExitTimer = Timer(hold, () {
      if (!mounted || _disposed) return;
      _safeSetState(() {
        _routeSearchStatusLeaving = true;
      });
      _routeSearchExitTimer = Timer(const Duration(milliseconds: 280), () {
        if (!mounted || _disposed) return;
        _safeSetState(() {
          _routeSearchDismissScheduled = false;
          _routeSearchStatusLeaving = false;
          _routeSearchProgress = 0.08;
          _routeSearchNoticeTitle = null;
          _routeSearchNoticeMessage = null;
        });
      });
    });
  }

  // 2026-05-31 (vucko): Hinweis-Banner manuell wegwischen. Spiegelt das
  // finale Cleanup aus _scheduleRouteSearchStatusDismiss und bricht einen
  // evtl. laufenden Auto-Dismiss-Timer ab, damit nichts doppelt feuert.
  void _dismissRouteSearchNotice() {
    if (!mounted || _disposed) return;
    _routeSearchExitTimer?.cancel();
    _safeSetState(() {
      _routeSearchDismissScheduled = false;
      _routeSearchStatusLeaving = false;
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

  // 2026-06-06 (vucko P3): Setzt den Kopf der sichtbaren (roten) Route JEDEN Tick
  // exakt auf die PROJIZIERTE Position des Pucks auf der Polylinie und schneidet
  // alle bereits passierten Stützpunkte ab. So „schmilzt" die Linie smooth unter
  // dem Puck weg — nie vor, nie hinter dem Standort.
  //
  // Vorher (_pinVisibleRouteStartToPosition) hing der Kopf am nächsten Vertex und
  // wurde nur geheftet, wenn dieser <25m entfernt war. Auf langen Segmenten
  // (GraphHopper-Vertices 50–300m auseinander) blieb der Kopf darum hinter dem
  // Puck stehen → genau das gemeldete „Linie viel zu weit vorne/hinten".
  // 2026-06-08 (vucko Leitlinie GPU-Trim): kumulierte Distanzen + LatLng-Liste der
  // aktiven Route. Nur neu rechnen, wenn sich die Route ändert (Start/Reroute).
  void _ensureRouteMetrics() {
    final coords = _fullRouteCoordinates;
    final sig = coords.length < 2
        ? 'e'
        : '${coords.length}:${coords.first[0].toStringAsFixed(5)},'
              '${coords.first[1].toStringAsFixed(5)}>'
              '${coords.last[0].toStringAsFixed(5)},'
              '${coords.last[1].toStringAsFixed(5)}';
    if (sig == _routeMetricsSig) return;
    _routeMetricsSig = sig;
    final cum = List<double>.filled(coords.length, 0.0);
    var total = 0.0;
    for (var i = 1; i < coords.length; i++) {
      total += geo.Geolocator.distanceBetween(
        coords[i - 1][1],
        coords[i - 1][0],
        coords[i][1],
        coords[i][0],
      );
      cum[i] = total;
    }
    _routeCumDist = cum;
    _routeTotalLenM = total;
    _routeProgress = 0.0; // neue Route → von vorne
  }

  // Fahrt-Fortschritt 0..1 als DISTANZ-Fraktion (line-progress misst Distanz!) aus
  // der Puck-Projektion (Segment-Index + -Fraktion des Matches).
  double _routeProgressFromMatch(RouteWindowMatch match) {
    _ensureRouteMetrics();
    final n = _routeCumDist.length;
    if (_routeTotalLenM <= 0 || n < 2) return _routeProgress;
    final segIdx = match.segmentIndex;
    final frac = match.segmentFraction;
    double along;
    if (segIdx != null && frac != null && segIdx >= 0 && segIdx + 1 < n) {
      final f = frac.clamp(0.0, 1.0);
      along =
          _routeCumDist[segIdx] +
          f * (_routeCumDist[segIdx + 1] - _routeCumDist[segIdx]);
    } else {
      along = _routeCumDist[match.index.clamp(0, n - 1)];
    }
    return (along / _routeTotalLenM).clamp(0.0, 1.0);
  }

  /// 2026-06-09 (vucko Trip-Skip): markiert Zwischenstopps als besucht, sobald
  /// der Fahrer ≤120 m herankommt. Billig (≤8 Stopps, 1 Distanz je Tick).
  /// 2026-06-10 (vucko Trip-Resume): besuchte Stopps zusätzlich in der DB
  /// abhaken (actual_arrival) — beim Resume nach App-Neustart werden nur die
  /// NOCH NICHT befahrenen Stopps + das Endziel geladen. Sequenz in trip_stops:
  /// 0 = Start → Zwischenstopp i hat Sequenz i+1.
  void _markPassedWaypoints(geo.Position position) {
    if (_activeIntermediateWaypoints.isEmpty) return;
    for (var i = 0; i < _activeIntermediateWaypoints.length; i++) {
      if (_passedWaypointIndices.contains(i)) continue;
      final wp = _activeIntermediateWaypoints[i];
      final d = geo.Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        wp[1],
        wp[0],
      );
      if (d <= 120.0) {
        _passedWaypointIndices.add(i);
        final tripId = _activeTripId;
        if (tripId != null) {
          unawaited(
            TripService.instance.markStopReached(tripId, i + 1).catchError((
              Object e,
            ) {
              debugPrint('[CruiseMode] markStopReached fail (silent): $e');
            }),
          );
        }
      }
    }
  }

  /// 2026-06-09 (vucko Trip-Skip): verbleibende Stopps für einen Reroute.
  /// Regel (User-Spec): Lässt der Fahrer einen Stopp aus, wird automatisch zum
  /// NÄHEREN von (nächster verbleibender Stopp | Endziel) geroutet — Stopps vor
  /// dem näheren Ziel gelten als bewusst übersprungen. null = keine Stopps mehr
  /// (Reroute direkt zum Endziel).
  List<Map<String, double>>? _remainingWaypointsForReroute(
    geo.Position position,
    List<double> destination,
  ) {
    if (_activeIntermediateWaypoints.isEmpty) return null;
    final remaining = <MapEntry<int, List<double>>>[];
    for (var i = 0; i < _activeIntermediateWaypoints.length; i++) {
      if (!_passedWaypointIndices.contains(i)) {
        remaining.add(MapEntry(i, _activeIntermediateWaypoints[i]));
      }
    }
    if (remaining.isEmpty) return null;
    double distTo(List<double> c) => geo.Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      c[1],
      c[0],
    );
    final destDist = distTo(destination);
    var nearestIdx = 0;
    var nearestDist = double.infinity;
    for (var i = 0; i < remaining.length; i++) {
      final d = distTo(remaining[i].value);
      if (d < nearestDist) {
        nearestDist = d;
        nearestIdx = i;
      }
    }
    if (destDist < nearestDist) {
      // Endziel ist näher als jeder verbleibende Stopp → alle überspringen.
      for (final e in remaining) {
        _passedWaypointIndices.add(e.key);
      }
      debugPrint(
        '[CruiseMode] Trip-Skip: Endziel näher als alle Rest-Stopps → direkt zum Ziel.',
      );
      return null;
    }
    for (var i = 0; i < nearestIdx; i++) {
      _passedWaypointIndices.add(remaining[i].key);
    }
    if (nearestIdx > 0) {
      debugPrint(
        '[CruiseMode] Trip-Skip: $nearestIdx Stopp(s) übersprungen, '
        '${remaining.length - nearestIdx} verbleibend.',
      );
    }
    return [
      for (var i = nearestIdx; i < remaining.length; i++)
        {'latitude': remaining[i].value[1], 'longitude': remaining[i].value[0]},
    ];
  }

  // ── Route-Lock: EINE Quelle für Puck, Kamera und Linien-Schnitt ──────────
  // 2026-06-11 (vucko Video-Befund vom Geraet): Puck (freier Kalman) und
  // Linien-Schnitt (Fix-Match + Gates) waren ZWEI unabhaengige Systeme — am
  // echten 1Hz-GPS liefen sie sichtbar auseinander (Linie ragte hinter den
  // Puck, Puck "schwamm" neben der Linie). Industrie-Loesung (Google/Mapbox
  // Navigation): waehrend der Fahrt wird der GERENDERTE Puck auf die Route
  // GESNAPPT und gleitet monoton ENTLANG der Geometrie; der Linien-Schnitt
  // nutzt DIESELBE Distanz → Puck und Linie koennen konstruktiv nicht mehr
  // auseinanderlaufen. Kurze GPS-Ausreisser werden visuell auf dem letzten
  // Lock gehalten; echte Off-route-Fahrten fallen nach kurzer Hysterese auf
  // den freien Puck zurueck. Reroute/Off-route-Pruefung nutzt weiter die echte
  // GPS-Position und wird dadurch nicht maskiert.
  RouteWindowMatch? _lastWindowMatch;
  final RouteRenderLock _routeRenderLock = RouteRenderLock();
  double _lastTrimDistM = -1;
  LatLng? _lastRouteLockedRenderLatLng;
  DateTime? _lastRouteRenderLockAcceptedAt;
  // 2026-06-13 (vucko „Linie hinterm Puck"): Gate 4→2,5m + Vorhalt 0→2,5m.
  // Der Schnitt liegt damit IMMER 0..2,5m VOR dem Lock-Meter — die Naht
  // pendelt unsichtbar UNTER dem Puck-Kreis, nie als roter Schweif dahinter.
  // (6m Vorhalt wirkte „abgekoppelt", 0m zeigte bis 4m Schweif — 2,5m ist
  // der verifizierte Mittelweg, vgl. Linienkopf-Vorhalt-Fix 0495f57.)
  static const double _routeTrimPushGateM = 2.5;
  static const double _routeTrimLeadM = 2.5;
  static const Duration _routeOutlierVisualHold = Duration(milliseconds: 1500);
  static const Duration _nativeRenderPredictionLead = Duration(
    milliseconds: 150,
  );
  List<double>? get _routeCumDistM => _routeRenderLock.cumulativeDistances;
  int get _renderLockSegIdx => _routeRenderLock.segmentIndex;
  double get _renderLockDistM => _routeRenderLock.distanceM;

  bool _clearLiveRouteWindowForOffRoute() {
    if (_brightAheadLatLngs.isEmpty &&
        _dimRemainingLatLngs.isEmpty &&
        _drivenTrailLatLngs.isEmpty &&
        _lastDimHead == null &&
        _lastDrivenHead == null &&
        _lastTrimDistM < 0) {
      return false;
    }
    _brightAheadLatLngs = const [];
    _dimRemainingLatLngs = const [];
    _drivenTrailLatLngs = const [];
    _lastDimHead = null;
    _lastDrivenHead = null;
    _lastTrimDistM = -1;
    return true;
  }

  void _ensureRouteCumDist() {
    if (_routeRenderLock.ensureRoute(_fullRouteCoordinates)) {
      _lastTrimDistM = -1;
      _lastRouteLockedRenderLatLng = null;
      _lastRouteRenderLockAcceptedAt = null;
    }
  }

  /// Projiziert (lat,lng) auf die aktive Route. Liefert die monotone Distanz
  /// entlang der Route oder null (off-route / keine Route).
  double? _projectDistOnRoute(double lat, double lng, DateTime timestamp) {
    final coords = _fullRouteCoordinates;
    final projection = _routeRenderLock.project(
      coordinates: coords,
      latitude: lat,
      longitude: lng,
      routeConfirmed: _isRouteConfirmed,
      currentRouteIndex: _currentRouteIndex,
      speedMps: _nativeSmoother.speed,
      timestamp: timestamp,
      // 2026-06-13 (vucko Verfahren-„kracht"): Kurs mitgeben → der Lock
      // erkennt echtes Wegfahren (Heading-Divergenz) und lässt früh los.
      headingDeg: _nativeSmoother.hasValidHeading
          ? _nativeSmoother.heading
          : null,
    );
    return projection?.distanceM;
  }

  /// Punkt (lng,lat) bei Distanz d entlang der aktiven Route.
  List<double>? _pointAtRouteDist(double d) {
    _ensureRouteCumDist();
    return _routeRenderLock.pointAtDistance(d);
  }

  /// 2026-06-14 (vucko Re-Dock-Trim): Ankert den Render-Lock nach einem
  /// Wieder-Andocken (globaler Re-Snap im Korridor) auf den re-gesnappten
  /// Routen-[index]. Gibt true zurueck, wenn wirklich neu geankert wurde
  /// (Versatz > 20 m oder Lock war freigegeben) — sonst false: Mini-Jitter
  /// bleibt auf dem monotonen Glide, damit ein einzelner Seiten-Fix keinen
  /// sichtbaren Schnitt-Ruecksprung erzeugt.
  bool _reanchorRenderLockToIndex(int index) {
    _ensureRouteCumDist();
    final cum = _routeCumDistM;
    if (cum == null || cum.isEmpty) return false;
    final i = index.clamp(0, cum.length - 1);
    final d = cum[i];
    final lockDist = _renderLockDistM;
    if (lockDist >= 0 && (d - lockDist).abs() <= 20.0) return false;
    _routeRenderLock.reanchorToDistance(d);
    return true;
  }

  bool _shouldHoldLastRouteLockedRenderPosition(DateTime now) {
    return shouldHoldRouteRenderLock(
      now: now,
      lastAcceptedAt: _lastRouteRenderLockAcceptedAt,
      offRouteSince: _offRouteSince,
      routeConfirmed: _isRouteConfirmed,
      overviewActive: _isOverviewActive,
      hasLock: _renderLockDistM >= 0,
      holdDuration: _routeOutlierVisualHold,
    );
  }

  /// 2026-06-13 (vucko Verfahren-„kracht"): Wechselt die Puck-Quelle zwischen
  /// „auf der Route gesnappt" und „frei (echtes GPS)", wird NICHT mehr hart
  /// gesprungen, sondern ~600ms weich uebergeblendet (smoothstep auf das pro
  /// Frame weiterwandernde Ziel). Betrifft Lock-Release beim Verfahren,
  /// Hold-Ablauf UND Re-Acquire nach dem Reroute.
  LatLng _blendPuckTransition(
    LatLng target, {
    required bool locked,
    required DateTime at,
  }) {
    final prev = _lastRouteLockedRenderLatLng;
    if (locked != _puckSourceWasLocked) {
      _puckSourceWasLocked = locked;
      if (prev != null) {
        final jumpM = geo.Geolocator.distanceBetween(
          prev.latitude,
          prev.longitude,
          target.latitude,
          target.longitude,
        );
        // Nur echte sichtbare Spruenge blenden; Mini-Differenzen direkt,
        // Riesen-Spruenge (Teleport/Routenwechsel) ebenfalls direkt.
        if (jumpM > 8.0 && jumpM < 500.0) {
          _puckBlendFrom = prev;
          _puckBlendStartAt = at;
        }
      }
    }
    final from = _puckBlendFrom;
    final startAt = _puckBlendStartAt;
    if (from == null || startAt == null) {
      // 2026-06-15 (vucko N-Runde-2): Off-Route fehlt der Route-Lock, der die
      // 1Hz-GPS-Korrektur sonst versteckt → den FREIEN Puck pro Frame weich ans
      // (bereits dead-reckon-extrapolierte) Ziel heranziehen, damit er gleitet
      // statt bei jedem Fix zu springen. Den gesnappten Puck NICHT ziehen (er
      // würde hinter den Linienkopf zurückfallen). Große Sprünge direkt.
      if (!locked) return _easeFreePuck(target, at);
      _lastFreePuckEaseAt = null;
      return target;
    }
    final t =
        at.difference(startAt).inMilliseconds /
        _puckBlendDuration.inMilliseconds;
    if (t >= 1.0) {
      _puckBlendFrom = null;
      _puckBlendStartAt = null;
      return target;
    }
    final e = t * t * (3.0 - 2.0 * t); // smoothstep
    return LatLng(
      from.latitude + (target.latitude - from.latitude) * e,
      from.longitude + (target.longitude - from.longitude) * e,
    );
  }

  void _resetPuckBlend() {
    _puckBlendFrom = null;
    _puckBlendStartAt = null;
    _puckSourceWasLocked = false;
    _lastFreePuckEaseAt = null;
  }

  /// 2026-06-15 (vucko N-Runde-2): Framerate-unabhängige exponentielle Glättung
  /// des freien (off-route) Pucks. Zieht die vorige Render-Position pro Frame ein
  /// Stück Richtung [target] (= bereits extrapolierter Smoother-Punkt), sodass die
  /// per-Fix-Korrektur als sanftes Gleiten statt als Sprung erscheint. Lag ≈
  /// 1/lambda ≈ 0,11s (bei 30 m/s ~3m, unsichtbar). Große Sprünge (Teleport/
  /// Reroute/Quellenwechsel) und Lücken werden direkt durchgereicht.
  LatLng _easeFreePuck(LatLng target, DateTime at) {
    final prev = _lastRouteLockedRenderLatLng;
    final prevAt = _lastFreePuckEaseAt;
    _lastFreePuckEaseAt = at;
    if (prev == null || prevAt == null) return target;
    final dt = at.difference(prevAt).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 0.5) return target; // Lücke/erster Frame → direkt
    final jumpM = geo.Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      target.latitude,
      target.longitude,
    );
    if (jumpM > 60.0 || jumpM < 0.05) {
      return target; // Teleport / Mikro → direkt
    }
    const lambda = 9.0;
    final a = 1.0 - math.exp(-lambda * dt);
    return LatLng(
      prev.latitude + (target.latitude - prev.latitude) * a,
      prev.longitude + (target.longitude - prev.longitude) * a,
    );
  }

  /// Render-Position fuer Puck UND Kamera: on-route = auf die Linie gesnappt.
  LatLng? _routeLockedRenderPosition([DateTime? at]) {
    final renderAt = at ?? DateTime.now();
    final p = _nativeSmoother.predict(renderAt);
    if (p.lat == 0 && p.lng == 0) {
      _lastRouteLockedRenderLatLng = null;
      _lastRouteRenderLockAcceptedAt = null;
      _resetPuckBlend();
      return null;
    }
    if (!_isRouteConfirmed || _isOverviewActive) {
      final free = LatLng(p.lat, p.lng);
      _lastRouteLockedRenderLatLng = free;
      _resetPuckBlend();
      return free;
    }
    final d = _projectDistOnRoute(p.lat, p.lng, renderAt);
    if (d == null) {
      if (_shouldHoldLastRouteLockedRenderPosition(renderAt)) {
        final heldPt = _pointAtRouteDist(_renderLockDistM);
        if (heldPt != null) {
          final held = _blendPuckTransition(
            LatLng(heldPt[1], heldPt[0]),
            locked: true,
            at: renderAt,
          );
          _lastRouteLockedRenderLatLng = held;
          return held;
        }
      }
      // off-route: freier Puck — weich aus dem Lock ausblenden
      final free = _blendPuckTransition(
        LatLng(p.lat, p.lng),
        locked: false,
        at: renderAt,
      );
      _lastRouteLockedRenderLatLng = free;
      return free;
    }
    _lastRouteRenderLockAcceptedAt = renderAt;
    final pt = _pointAtRouteDist(d);
    if (pt == null) {
      final free = _blendPuckTransition(
        LatLng(p.lat, p.lng),
        locked: false,
        at: renderAt,
      );
      _lastRouteLockedRenderLatLng = free;
      return free;
    }
    final locked = _blendPuckTransition(
      LatLng(pt[1], pt[0]),
      locked: true,
      at: renderAt,
    );
    _lastRouteLockedRenderLatLng = locked;
    return locked;
  }

  /// Read-only Render-Position fuer das Map-Overlay. Wichtig: Das Map-Widget
  /// projiziert Marker bei jedem CameraMove; dieser Callback darf den Route-Lock
  /// nicht fortschreiben, sonst kann der Puck einen Frame neuer sein als der
  /// GeoJSON-Linienkopf.
  LatLng? _readRouteLockedRenderPosition() => _lastRouteLockedRenderLatLng;

  bool _trimVisibleRouteToProjection(RouteWindowMatch match) {
    final coords = _fullRouteCoordinates;
    if (coords.length < 2) return false;
    _lastWindowMatch = match;

    List<double> projHead;
    int aheadStart;
    // 2026-06-11 (vucko Route-Lock): Ist der Render-Lock aktiv, ist SEINE
    // monotone Distanz die Quelle des Schnitts — exakt dieselbe Position, an
    // der der Puck gerendert wird. Das alte 18m-Fix-Gate entfaellt in diesem
    // Pfad (der Lock garantiert on-route); es friert den Schnitt damit auch
    // bei GPS-Jitter nicht mehr ein (Geraete-Video-Befund).
    _ensureRouteCumDist();
    final lockDist = _renderLockDistM;
    if (lockDist >= 0 && _routeCumDistM != null) {
      final pt = _pointAtRouteDist(lockDist);
      if (pt == null) return false;
      projHead = pt;
      var i = _renderLockSegIdx.clamp(0, coords.length - 2);
      final cum = _routeCumDistM!;
      if (cum[i] > lockDist) i = 0;
      while (i < coords.length - 2 && cum[i + 1] < lockDist) {
        i++;
      }
      aheadStart = i + 1;
      _lastTrimDistM = lockDist;
    } else {
      // Fallback (kein Lock, z. B. ganz frische Route): bisheriger Fix-Match.
      if (match.distanceMeters > _headSnapMaxMeters) return false;
      final segIdx = match.segmentIndex;
      final frac = match.segmentFraction;
      if (segIdx != null && frac != null && segIdx + 1 < coords.length) {
        final a = coords[segIdx];
        final b = coords[segIdx + 1];
        final f = frac.clamp(0.0, 1.0);
        projHead = [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f];
        aheadStart = segIdx + 1;
      } else {
        final idx = match.index.clamp(0, coords.length - 1);
        projHead = [coords[idx][0], coords[idx][1]];
        aheadStart = idx + 1;
      }
    }
    if (aheadStart > coords.length) aheadStart = coords.length;

    // 2026-06-09 (vucko Voll-Route-Sichtbar): Distanz-Gate auf die Puck-Projektion
    // — nur bei echter Bewegung (≥4m) neu. Der graue Trail liegt HINTER dem Puck,
    // ein 4m-Lag ist optisch unsichtbar (Puck deckt die Naht), hält aber die
    // Push-Rate niedrig → butterweich, kein Tile-Hunger / Schwarz-Karte-Risiko.
    if (_lastDrivenHead != null) {
      final moved = geo.Geolocator.distanceBetween(
        _lastDrivenHead![1],
        _lastDrivenHead![0],
        projHead[1],
        projHead[0],
      );
      if (moved < _routeTrimPushGateM) return false;
    }
    _lastDrivenHead = projHead;

    // GRAUER Driven-Trail = begrenztes (~3km) Fenster HINTER dem Puck; Kopf =
    // Puck-Projektion → scharfer Schnitt EXAKT am Puck. Die rote aktive Linie
    // (_routeLatLngs) ist die VOLLE Route und bleibt statisch → die komplette
    // Reststrecke ist IMMER kräftig rot sichtbar (kein „abgeschnitten wirkendes"
    // 3km-Stück mehr). Begrenztes Fenster = konstant günstiger Push.
    final clampedAhead = aheadStart.clamp(0, coords.length);
    // 2026-06-10 (vucko 3km-Sichtdesign v2): KEIN grauer Trail mehr —
    // Abgefahrenes verschwindet einfach (beide sichtbaren Linien starten am
    // Puck). Sichtbar sind:
    //  • BRIGHT (aktive Quelle): [Puck .. +3 km] in VOLLEM Rot — „die
    //    nächsten 3 km immer clean geladen", scharfer Schnitt exakt am Puck.
    //  • DIM (Basis-Linien-Layer): [Puck .. Ende] dezent (Opacity ~0.30) —
    //    man sieht leicht, dass es weitergeht; die ersten 3 km davon liegen
    //    UNTER bright und sind unsichtbar, darum reicht ein träges 200m-Gate
    //    (seltene Pushes, kein Tile-Hunger).
    _drivenTrailLatLngs = const [];

    // Volle Reststrecke (Puck → Ende) für Restdistanz + Auto-Snapshot pflegen
    // (nur Dart-Listen, KEIN Map-Push).
    _remainingRouteCoordinates = <List<double>>[
      projHead,
      if (clampedAhead < coords.length)
        for (final c in coords.sublist(clampedAhead)) [c[0], c[1]],
    ];

    // BRIGHT: 3km-Fenster ab Puck (kleine Geometrie, 4m-gegated wie oben).
    var headLng = projHead[0];
    var headLat = projHead[1];
    var headIdx = clampedAhead;
    // 2026-06-12 (vucko Geraete-Screenshots): Schnitt und Puck teilen exakt
    // dieselbe Distanz. Der fruehere 6m-Vorhalt war als Naht-Verdeckung gedacht,
    // erzeugte in echten Fahrbildern aber wieder den Eindruck, dass Route und
    // Standort nicht zusammenkleben. Die Marker-Groesse verdeckt die GeoJSON-
    // Push-Kadenz ausreichend; wichtiger ist ein identischer Geo-Anker.
    var lead = _routeTrimLeadM;
    while (lead > 0 && headIdx < coords.length) {
      final c = coords[headIdx];
      final d = geo.Geolocator.distanceBetween(headLat, headLng, c[1], c[0]);
      if (d <= lead || d <= 0) {
        lead -= d;
        headLng = c[0];
        headLat = c[1];
        headIdx++;
      } else {
        final f = lead / d;
        headLng += (c[0] - headLng) * f;
        headLat += (c[1] - headLat) * f;
        lead = 0;
      }
    }
    var acc = 0.0;
    var aheadEnd = headIdx;
    var prevLng = headLng;
    var prevLat = headLat;
    while (aheadEnd < coords.length && acc < 3000.0) {
      final c = coords[aheadEnd];
      acc += geo.Geolocator.distanceBetween(prevLat, prevLng, c[1], c[0]);
      prevLng = c[0];
      prevLat = c[1];
      aheadEnd++;
    }
    // On-route-Erkennung: Abstand GERENDERTER Puck -> Projektion. Roh-GPS kann
    // kurz seitlich ausreissen, waehrend der Route-Lock den sichtbaren Puck
    // korrekt auf der Linie haelt. Dieser Guard darf dann nicht gegen eine
    // andere Quelle entscheiden und die rote Vorwaerts-Linie ausblenden.
    final visualPuck =
        _lastRouteLockedRenderLatLng ??
        (_userLocation == null
            ? null
            : LatLng(_userLocation!.latitude, _userLocation!.longitude));
    if (visualPuck != null) {
      final offM = geo.Geolocator.distanceBetween(
        visualPuck.latitude,
        visualPuck.longitude,
        projHead[1],
        projHead[0],
      );
      if (offM <= 80) _everOnActiveRoute = true;
      if (widget.groupId != null && !_everOnActiveRoute && offM > 80) {
        // Late-Joiner abseits der Route: KEIN 3km-Fenster — volle Route
        // kraeftig zeigen (Fallback in activePts), bis er drauf ist.
        _brightAheadLatLngs = const [];
        return true;
      }
      // 2026-06-10 (vucko Anti-Haenger, Screenshot-Bug): Haengt die
      // Projektion >120m hinter/neben dem Puck (Match-Haenger nach Reroute,
      // Off-Route-Phase), waere das 3km-Fenster an der FALSCHEN Stelle und
      // vor dem Fahrer nur die dezente Linie ("Route wirkt ausgefallen").
      // Dann lieber: Fenster aus -> die VOLLE Route kraeftig (Fallback) —
      // niemals duenn/falsch vor dem Fahrer.
      if (offM > 120) {
        _brightAheadLatLngs = const [];
        return true;
      }
    }
    _brightAheadLatLngs = [
      LatLng(headLat, headLng),
      for (final c in coords.sublist(headIdx, aheadEnd)) LatLng(c[1], c[0]),
    ];

    // DIM: Reststrecke ab Puck — nur alle ~200m neu (Anfang ist von bright
    // überdeckt, das Lag ist unsichtbar).
    final dimHead = _lastDimHead;
    if (dimHead == null ||
        geo.Geolocator.distanceBetween(
              dimHead[1],
              dimHead[0],
              projHead[1],
              projHead[0],
            ) >=
            200.0) {
      _lastDimHead = projHead;
      // 2026-06-10 (vucko Schwanz-Fix): dim beginnt ~200m VORAUS — dieser
      // Anfang liegt unsichtbar UNTER dem 3km-bright-Fenster. So kann das
      // 200m-Push-Gate konstruktiv NIE einen dezenten Schwanz hinter dem
      // Puck stehen lassen (Screenshot-Bug 2).
      var dimSkip = 0;
      var dAcc = 0.0;
      var pLng = projHead[0];
      var pLat = projHead[1];
      while (dimSkip < _remainingRouteCoordinates.length && dAcc < 200.0) {
        final c = _remainingRouteCoordinates[dimSkip];
        dAcc += geo.Geolocator.distanceBetween(pLat, pLng, c[1], c[0]);
        pLng = c[0];
        pLat = c[1];
        dimSkip++;
      }
      _dimRemainingLatLngs = [
        for (final c in _remainingRouteCoordinates.skip(
          dimSkip > 0 ? dimSkip - 1 : 0,
        ))
          LatLng(c[1], c[0]),
      ];
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadVectorTiles();
    // 2026-06-06 (vucko P10): Zuletzt bekannten Standort laden → Karte öffnet
    // (auch beim Kaltstart) sofort dort statt bei „Deutschland-Mitte@z6".
    unawaited(_loadPersistedUserCenter());
    // 2026-06-02 (vucko Sync): Schließt das Auto den Abschluss-Screen mit
    // „Fertig", soll das Handy-Sheet ebenfalls zugehen (beidseitige Sync).
    CarCommandListener.instance.onCompletionDone = () {
      if (!mounted || _disposed) return;
      if (_completionSheetOpen) {
        _completionSheetOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      _resetAfterCompletion();
    };
    // 2026-06-02 (vucko Sync): „Losfahren" auf CarPlay → das HANDY übernimmt die
    // Fahrt (GPS/Voice-Treiber) → beide Geräte 1:1 synchron, und CarPlay bekommt
    // echte Live-Wegbeschreibung/ETA via publishProgress. Abgesichert: nur wenn
    // die Cruise-Page offen ist, nicht gerade lädt und nicht schon navigiert.
    // Ist die Page zu, navigiert CarPlay eigenständig weiter (kein Abbruch).
    CarCommandListener
        .instance
        .onStartNavigation = (route, style, avoidHighways) {
      if (!mounted || _disposed || _isLoading) return;
      if (_navigationStartTime != null) return; // läuft bereits
      // Hat das Handy schon eine Route in der Vorschau (selbst geplant via
      // onPlanRoute)? Dann die fahren. Sonst die vom Auto gelieferte übernehmen.
      final hasCurrentRoute = _fullRouteCoordinates.length >= 2;
      if (!hasCurrentRoute && route != null) {
        setState(() {
          _selectedStyle = style;
          _isRoundTrip = true; // CarPlay plant Rundkurse
        });
        _applyRouteResult(route);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _disposed) return;
        if (_fullRouteCoordinates.length < 2) return; // keine Route da
        await _confirmRoute();
        await _startNavigationFlow();
      });
    };
    // 2026-06-02 (vucko Mirror): „Route planen" auf CarPlay → das HANDY fährt
    // die Suche (Lade-Popup + Vorschau-Animation) und publisht searching/found
    // selbst an CarPlay zurück → beide Geräte suchen gleichzeitig, beide zeichnen
    // die Route. true = Page hat übernommen (sonst rechnet der Listener standalone).
    CarCommandListener.instance.onPlanRoute = (style, km, avoidHighways) {
      if (!mounted || _disposed || _isLoading) return false;
      if (_navigationStartTime != null) return false; // fährt schon
      setState(() {
        _isRoundTrip = true;
        _planningType = 'Zufall';
        _selectedStyle = style;
        _selectedLength = '$km Km';
        _avoidHighways = avoidHighways;
      });
      unawaited(_generateRoute());
      return true;
    };
    // Animierte Kamera-Bewegung zwischen GPS-Updates (alle Plattformen, 60fps)
    // 2026-05-22 (vucko): GPS-Update-Frequenz jetzt 200ms (Android). Camera-
    // Animation muss noch dazu passen damit zwischen Updates ohne Stop weitergeht.
    //   iOS:     250ms (GPS variabel)
    //   Android: 230ms (knapp länger als 200ms GPS-Intervall → seamless overlap)
    //   Web:     280ms (GPS langsamer + smoother prediction)
    final animDuration = (!kIsWeb && Platform.isIOS)
        ? const Duration(milliseconds: 250)
        : Platform.isAndroid
        ? const Duration(milliseconds: 230)
        : const Duration(milliseconds: 280);
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
    if (widget.initialRoute == null && widget.groupId == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _restoreConfirmedOfflineRouteIfAvailable(),
      );
    }
    CruiseModePage.pendingRoute.addListener(_onPendingRoute);
    CruiseModePage.pendingTripResume.addListener(_onPendingTripResume);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumePendingRouteIfAvailable();
      // 2026-06-10 (vucko Resume-Crash-Fix): Intent kann einen Crash/Fehlversuch
      // überleben (wird erst nach Erfolg konsumiert) — beim Page-Aufbau einmal
      // initial prüfen, nicht nur auf Listener-Events warten.
      unawaited(_consumePendingTripResumeIfAvailable());
    });
    _destinationController.addListener(_onDestinationTextChanged);
    _destinationFocusNode.addListener(_onDestinationFocusChanged);
    _startLocationFocusNode.addListener(_onDestinationFocusChanged);
    unawaited(_loadCountryPreference());
    unawaited(_loadWaypointTutorialShown());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowRoutingOnboarding(),
    );
  }

  // 2026-06-01 (vucko): Trip-Modus-Tutorial nur EINMALIG (persistent) und nur
  // beim echten Wechsel zu Trip-Modus — nicht mehr beim Setzen des 2. Wegpunkts
  // im Standard-Modus (das nervte im Test).
  static const String _waypointTutorialKey = 'waypoint_trip_tutorial_shown_v1';
  Future<void> _loadWaypointTutorialShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_waypointTutorialKey) == true) {
        _waypointTutorialShown = true;
      }
    } catch (_) {
      // Best-effort — Default: noch nicht gezeigt.
    }
  }

  Future<void> _persistWaypointTutorialShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_waypointTutorialKey, true);
    } catch (_) {
      // Best-effort.
    }
  }

  // 2026-05-30 (vucko): Länder-Präferenz persistent.
  static const String _countryPrefKey = 'route_country_preference_v1';
  Future<void> _loadCountryPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_countryPrefKey);
      final pref = CountryPreferenceLabel.fromStorage(stored);
      if (mounted && pref != _countryPreference) {
        setState(() => _countryPreference = pref);
      }
    } catch (_) {
      // Best-effort — Default bleibt 'egal'.
    }
  }

  Future<void> _persistCountryPreference(CountryPreference pref) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_countryPrefKey, pref.storageValue);
    } catch (_) {
      // Best-effort.
    }
  }

  bool get _countryFilterAppliesToCurrentRoute =>
      _isRoundTrip && !_isWaypointPlanning;

  CountryPreference get _effectiveCountryPreferenceForGeneration =>
      _countryFilterAppliesToCurrentRoute
      ? _countryPreference
      : CountryPreference.any;

  String? get _effectiveHomeCountryCodeForGeneration =>
      _effectiveCountryPreferenceForGeneration == CountryPreference.any
      ? null
      : _homeCountryCode;

  Future<void> _maybeShowRoutingOnboarding() async {
    if (!mounted || _disposed) return;
    if (_isRouteConfirmed) return;
    await showRoutingOnboardingSheet(context);
  }

  Future<void> _restoreConfirmedOfflineRouteIfAvailable() async {
    if (!mounted || _disposed || _isRouteConfirmed) return;
    if (_fullRouteCoordinates.isNotEmpty) return;
    final cached = await RouteCacheService.instance.loadConfirmedRoute();
    if (cached == null || !mounted || _disposed) return;
    // 2026-05-28 (vucko Task #77): TTL drastisch verkürzt auf 15 Min UND
    // nur restoren wenn der Cache-Eintrag eine groupId hat (= aktive
    // Gruppenfahrt). Solo-Routes verschwinden beim Tab-Wechsel komplett —
    // User-Beschwerde: „beim Cruise-Open kommt alte Route, was nicht
    // passieren darf". Echtes Funkloch-Recovery passiert über Tour-Resume
    // (groupId basiert), nicht über diesen Cache.
    final age = DateTime.now().toUtc().difference(cached.savedAt.toUtc());
    final isStale = age > const Duration(minutes: 15);
    final isSoloRoute = cached.groupId == null;
    if (isStale || isSoloRoute) {
      debugPrint(
        '[CruiseMode] Bestätigte Route nicht wiederhergestellt: '
        'age=${age.inMinutes}min groupId=${cached.groupId} — Cache geleert.',
      );
      unawaited(RouteCacheService.instance.clearConfirmedRoute());
      return;
    }
    await OfflineMapService.instance.ensureStyleCached();
    if (!mounted || _disposed) return;

    final route = cached.route;
    _lastRouteResult = route;
    _sessionRouteResult = route;
    _activeSpeedLimits = route.speedLimits;
    _recentDestinationDistances = [];
    _drivenTrackRecorder.reset();
    _clearAccessLegState();
    _safeSetState(() {
      _routeGeoJson = route.geoJson;
      _routeDistance = route.distanceMeters;
      _routeDuration = route.durationSeconds;
      _originalRouteDistance = route.distanceMeters;
      _originalRouteDuration = route.durationSeconds;
      _fullRouteCoordinates = route.coordinates;
      _remainingRouteCoordinates = route.coordinates;
      // 2026-06-10 (3km-Design v2): Fenster-Caches bei neuer Route leeren —
      // bright faellt auf die volle Route zurueck (nie unsichtbar), dim wird
      // beim naechsten Tick sofort neu gesetzt (dimHead == null).
      _brightAheadLatLngs = const [];
      _dimRemainingLatLngs = const [];
      _lastDimHead = null;
      _maneuvers = route.maneuvers;
      _activeManeuverIndex = 0;
      _currentRouteIndex = 0;
      _lastDrawnRouteIndex = 0;
      _distanceSinceLastRedraw = 0.0;
      _announcedManeuverIndices.clear();
      _remainingDistance = route.distanceMeters;
      _remainingDuration = route.durationSeconds;
      _distanceToFinalTargetMeters = null;
      _isExistingRouteSession = true;
      _isRoundTrip = cached.isRoundTrip;
      _selectedStyle = cached.style;
      _avoidHighways = cached.avoidHighways;
      _activeAvoidHighways = cached.avoidHighways;
      _isRouteConfirmed = true;
      _showRouteInfoBanner = false;
      _configCollapsed = false;
    });
    CruiseModePage.isFullscreen.value = true;
    await _drawRoute(route.geometry, animateCamera: false);
    unawaited(OfflineMapService.instance.cacheRouteRegion(route.coordinates));
    debugPrint('[CruiseMode] Offline bestätigte Route wiederhergestellt.');
  }

  // ═══════════════════════ GROUP / LIVE TRACKING ═══════════════════════════

  Future<void> _bootstrapGroupSession(String groupId) async {
    _positionUploadTimer?.cancel();
    _peerAnimTimer?.cancel();
    _groupRouteBackfillTimer?.cancel();
    _groupRouteReconnectTimer?.cancel();
    _groupMembersBackfillTimer?.cancel();
    _groupMembersReconnectTimer?.cancel();
    _groupMembersFreshnessTimer?.cancel();
    final g = await CruiseGroupService.fetch(groupId);
    if (g == null || !mounted) return;

    // Mitglieder initial einlesen (ohne mich selbst)
    final meId = Supabase.instance.client.auth.currentUser?.id;
    _mergeGroupMembers(g.members, meId: meId);
    _canPublishGroupRoute = meId != null && g.canUpdateRoute(meId);
    _groupRouteRevision = g.routeRevision;
    _safeSetState(() {});

    final activeRouteData = g.activeRouteData;
    if (activeRouteData != null) {
      await _applyGroupRouteData(
        activeRouteData,
        revision: g.routeRevision,
        source: 'bootstrap',
        autoConfirm: true,
      );
    }

    _startGroupRouteSync(groupId, meId);
    _startGroupMembersRealtime(groupId, meId);
    _startGroupMembersRecovery(groupId, meId);

    // Timer: eigene Position regelmäßig hochschieben
    _positionUploadTimer = Timer.periodic(
      _groupPositionUploadInterval,
      (_) => _uploadMyPosition(),
    );
  }

  void _startGroupRouteSync(String groupId, String? meId) {
    _groupRouteCh?.unsubscribe();
    _groupRouteCh = CruiseGroupService.subscribeGroup(
      groupId,
      (row) => unawaited(_applyGroupRouteRow(row, source: 'realtime')),
      onStatus: (status, _) {
        if (!mounted || _disposed) return;
        if (status == RealtimeSubscribeStatus.subscribed) {
          unawaited(_reloadGroupRouteFromBackfill(groupId, meId));
          return;
        }
        if (status == RealtimeSubscribeStatus.closed ||
            status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          _scheduleGroupRouteReconnect(groupId, meId);
        }
      },
    );

    _groupRouteBackfillTimer?.cancel();
    _groupRouteBackfillTimer = Timer.periodic(
      _groupRouteBackfillInterval,
      (_) => _reloadGroupRouteFromBackfill(groupId, meId),
    );
  }

  void _scheduleGroupRouteReconnect(String groupId, String? meId) {
    _groupRouteReconnectTimer?.cancel();
    _groupRouteReconnectTimer = Timer(_groupRouteReconnectDelay, () {
      if (!mounted || _disposed || widget.groupId != groupId) return;
      _startGroupRouteSync(groupId, meId);
      unawaited(_reloadGroupRouteFromBackfill(groupId, meId));
    });
  }

  Future<void> _reloadGroupRouteFromBackfill(
    String groupId,
    String? meId,
  ) async {
    if (_groupRouteBackfillInFlight || !mounted || _disposed) return;
    _groupRouteBackfillInFlight = true;
    try {
      final group = await CruiseGroupService.fetch(groupId);
      if (group == null || !mounted || _disposed || widget.groupId != groupId) {
        return;
      }
      _canPublishGroupRoute = meId != null && group.canUpdateRoute(meId);
      final routeData = group.activeRouteData;
      if (routeData == null || group.routeRevision <= _groupRouteRevision) {
        return;
      }
      await _applyGroupRouteData(
        routeData,
        revision: group.routeRevision,
        source: 'backfill',
        autoConfirm: _isRouteConfirmed,
      );
    } catch (_) {
      // Backfill ist Recovery. Die letzte bekannte Gruppenroute bleibt aktiv.
    } finally {
      _groupRouteBackfillInFlight = false;
    }
  }

  Future<void> _applyGroupRouteRow(
    Map<String, dynamic> row, {
    required String source,
  }) async {
    if (!mounted || _disposed || row.isEmpty) return;
    final revision = (row['route_revision'] as num?)?.toInt() ?? 0;
    if (revision <= _groupRouteRevision) return;
    final routeData = _routeDataFromGroupRow(row);
    if (routeData == null) return;
    await _applyGroupRouteData(
      routeData,
      revision: revision,
      source: source,
      autoConfirm: _isRouteConfirmed,
    );
  }

  Map<String, dynamic>? _routeDataFromGroupRow(Map<String, dynamic> row) {
    final current = row['current_route_data'];
    if (current is Map<String, dynamic>) return current;
    if (current is Map) return Map<String, dynamic>.from(current);
    final legacy = row['route_data'];
    if (legacy is Map<String, dynamic>) return legacy;
    if (legacy is Map) return Map<String, dynamic>.from(legacy);
    return null;
  }

  Future<void> _applyGroupRouteData(
    Map<String, dynamic> routeData, {
    required int revision,
    required String source,
    required bool autoConfirm,
  }) async {
    final result = GroupRouteDataBuilder.parseRouteResult(routeData);
    if (result == null || result.coordinates.length < 2) return;
    if (!mounted || _disposed) return;

    final wasConfirmed = _isRouteConfirmed;
    _applyingGroupRouteUpdate = true;
    try {
      _lastRouteResult = result;
      _sessionRouteResult = result;
      _activeSpeedLimits = result.speedLimits;
      _activeGroupRouteData = Map<String, dynamic>.from(routeData);
      _groupRouteRevision = math.max(_groupRouteRevision, revision).toInt();
      _recentDestinationDistances = [];
      _clearAccessLegState();
      _safeSetState(() {
        _routeGeoJson = result.geoJson;
        _routeDistance = result.distanceMeters;
        _routeDuration = result.durationSeconds;
        _originalRouteDistance = result.distanceMeters;
        _originalRouteDuration = result.durationSeconds;
        _fullRouteCoordinates = result.coordinates;
        _remainingRouteCoordinates = result.coordinates;
        // 2026-06-10 (3km-Design v2): Fenster-Caches bei neuer Route leeren —
        // bright faellt auf die volle Route zurueck (nie unsichtbar), dim wird
        // beim naechsten Tick sofort neu gesetzt (dimHead == null).
        _brightAheadLatLngs = const [];
        _dimRemainingLatLngs = const [];
        _lastDimHead = null;
        _maneuvers = result.maneuvers;
        _activeManeuverIndex = 0;
        _currentRouteIndex = 0;
        _lastDrawnRouteIndex = 0;
        _distanceSinceLastRedraw = 0.0;
        _announcedManeuverIndices.clear();
        _offRouteCount = 0;
        _lastRerouteTime = DateTime.now();
        _remainingDistance = result.distanceMeters;
        _remainingDuration = result.durationSeconds;
        _distanceToFinalTargetMeters = null;
        _isExistingRouteSession = true;
        _isRouteConfirmed = wasConfirmed;
        _applyGroupRouteMetadata(routeData);
      });

      await _drawRoute(result.geometry, animateCamera: !wasConfirmed);
      if (autoConfirm && !wasConfirmed) {
        await _confirmRoute();
      }
      debugPrint(
        '[CruiseMode] Gruppenroute übernommen: revision=$revision source=$source',
      );
    } finally {
      _applyingGroupRouteUpdate = false;
    }
  }

  void _applyGroupRouteMetadata(Map<String, dynamic> routeData) {
    final routeType = routeData['route_type']?.toString();
    if (routeType == 'ROUND_TRIP') {
      _isRoundTrip = true;
      _activeDestinationCoordinate = null;
    } else if (routeType == 'POINT_TO_POINT') {
      _isRoundTrip = false;
      List<double>? dest;
      final destination = routeData['destination'];
      if (destination is Map) {
        final lat = destination['latitude'];
        final lng = destination['longitude'];
        if (lat is num && lng is num) {
          dest = [lng.toDouble(), lat.toDouble()];
        }
      }
      // 2026-06-09 (vucko Audit T1-H): bei fehlenden/defekten Ziel-Metadaten NICHT
      // die ALTE Ziel-Koordinate behalten (zeigte sonst aufs Ziel der Vorgänger-
      // Route → Reroute zielte falsch) — auf den letzten Routenpunkt (= echtes
      // Ende) zurückfallen, sonst null.
      _activeDestinationCoordinate =
          dest ??
          (_fullRouteCoordinates.length >= 2
              ? _fullRouteCoordinates.last
              : null);
    } else {
      // Unbekannter Typ → kein stale Ziel aus einer Vorgänger-Route halten.
      _activeDestinationCoordinate = null;
    }
    _selectedStyle = routeData['style']?.toString() ?? _selectedStyle;
    _avoidHighways = (routeData['avoid_highways'] as bool?) ?? _avoidHighways;
    _activeAvoidHighways = _avoidHighways;
    _activeDetourVariant =
        (routeData['detour_variant'] as num?)?.toInt() ?? _activeDetourVariant;
    _activePointToPointScenic =
        (routeData['scenic'] as bool?) ?? _activePointToPointScenic;
    _activePointToPointMode = _selectedStyle;
  }

  Future<void> _publishGroupRouteIfAllowed(RouteResult result) async {
    final groupId = widget.groupId;
    if (groupId == null ||
        !_canPublishGroupRoute ||
        // 2026-06-10 (vucko Gruppen-Reroute-Regel): Nur wer der Route real
        // gefolgt ist, darf sie fuer die GRUPPE ersetzen (Late-Join-Schutz).
        !_everOnActiveRoute ||
        _applyingGroupRouteUpdate ||
        _groupRouteRevision <= 0) {
      return;
    }

    final expectedRevision = _groupRouteRevision;
    final routeData = GroupRouteDataBuilder.replaceRoutePayload(
      route: result,
      previousRouteData: _activeGroupRouteData,
      updateReason: 'navigation_reroute',
    );
    try {
      final update = await CruiseGroupService.updateCurrentRoute(
        groupId: groupId,
        expectedRevision: expectedRevision,
        routeData: routeData,
      );
      if (update == null) {
        debugPrint(
          '[CruiseMode] Gruppenroute nicht geschrieben: revision_conflict expected=$expectedRevision',
        );
        final meId = Supabase.instance.client.auth.currentUser?.id;
        unawaited(_reloadGroupRouteFromBackfill(groupId, meId));
        return;
      }
      _groupRouteRevision = update.routeRevision;
      _activeGroupRouteData = routeData;
      debugPrint(
        '[CruiseMode] Gruppenroute geschrieben: revision=${update.routeRevision}',
      );
    } catch (e) {
      debugPrint(
        '[CruiseMode] Gruppenroute konnte nicht geschrieben werden: $e',
      );
      final meId = Supabase.instance.client.auth.currentUser?.id;
      unawaited(_reloadGroupRouteFromBackfill(groupId, meId));
    }
  }

  void _startGroupMembersRealtime(String groupId, String? meId) {
    _groupMembersCh?.unsubscribe();
    _groupMembersCh = CruiseGroupService.subscribeMembers(
      groupId,
      (row) {
        if (row.isEmpty) return;
        _lastGroupRealtimeEventAt = DateTime.now();
        final uid = row['user_id'] as String?;
        if (uid == null || uid == meId) return;
        try {
          final changed = _mergeGroupMember(
            GroupMember.fromMap(row),
            meId: meId,
          );
          if (changed) _safeSetState(() {});
        } catch (_) {}
      },
      onDelete: (oldRow) {
        final removed = _removeGroupMemberFromRealtimeDelete(
          oldRow,
          meId: meId,
        );
        if (removed) _safeSetState(() {});
      },
      onStatus: (status, _) {
        if (!mounted || _disposed) return;
        if (status == RealtimeSubscribeStatus.subscribed) {
          unawaited(
            _reloadGroupMembersFromBackfill(groupId, meId, forceRebuild: true),
          );
          return;
        }
        if (status == RealtimeSubscribeStatus.closed ||
            status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          _scheduleGroupMembersReconnect(groupId, meId);
        }
      },
    );
  }

  bool _removeGroupMemberFromRealtimeDelete(
    Map<String, dynamic> oldRow, {
    String? meId,
  }) {
    final userId = oldRow['user_id'] as String?;
    if (userId != null) {
      if (userId == meId) return false;
      return _groupMembers.remove(userId) != null;
    }

    final memberId = oldRow['id'] as String?;
    if (memberId == null) return false;
    for (final entry in _groupMembers.entries.toList(growable: false)) {
      if (entry.value.id == memberId) {
        _groupMembers.remove(entry.key);
        return true;
      }
    }
    return false;
  }

  void _startGroupMembersRecovery(String groupId, String? meId) {
    _groupMembersBackfillTimer?.cancel();
    _groupMembersFreshnessTimer?.cancel();
    _peerAnimTimer?.cancel();
    // 20Hz-Glaettung: exponentielles Nachziehen (~1.2s Konvergenz, passend
    // zum 2s-Upload-Takt) -> butterweiche Peer-Bewegung wie beim eigenen Puck.
    _peerAnimTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || _disposed || _peerTargetPos.isEmpty) return;
      var moved = false;
      _peerTargetPos.forEach((uid, target) {
        final shown = _peerShownPos[uid];
        if (shown == null) {
          _peerShownPos[uid] = [target[0], target[1]];
          moved = true;
          return;
        }
        final dLng = target[0] - shown[0];
        final dLat = target[1] - shown[1];
        // ~0.5m-Schwelle (grob in Grad) -> konvergiert: nichts tun.
        if (dLng.abs() < 0.000005 && dLat.abs() < 0.000005) return;
        shown[0] += dLng * 0.08;
        shown[1] += dLat * 0.08;
        moved = true;
      });
      if (moved) _safeSetState(() {});
    });
    _groupMembersBackfillTimer = Timer.periodic(
      _groupMembersBackfillInterval,
      (_) => _reloadGroupMembersFromBackfill(groupId, meId),
    );
    _groupMembersFreshnessTimer = Timer.periodic(_groupMembersFreshnessTick, (
      _,
    ) {
      if (!mounted || _disposed) return;
      if (_groupMembers.values.any((member) => member.hasLocation)) {
        _safeSetState(() {});
      }
      // 2026-06-10 (vucko Find-My-Härtung): Watchdog gegen "silent dead"
      // Realtime-Channels — nach Netz-Blips kann der Socket neu verbinden,
      // ohne dass der Channel je wieder Events liefert ODER einen
      // Fehlerstatus meldet. Kommt länger als _groupRealtimeWatchdogAge kein
      // Event UND ist mind. ein Mitglied stale, wird der Channel hart neu
      // aufgebaut + sofort backfillt.
      final lastEvent = _lastGroupRealtimeEventAt;
      final anyStale = _groupMembers.values.any(
        (m) =>
            m.hasLocation &&
            !m.hasFreshLocation(maxAge: _groupMemberFreshLocationAge),
      );
      if (anyStale &&
          (lastEvent == null ||
              DateTime.now().difference(lastEvent) >
                  _groupRealtimeWatchdogAge)) {
        _lastGroupRealtimeEventAt = DateTime.now(); // Debounce
        debugPrint('[CruiseMode] Realtime-Watchdog: Channel-Rebuild');
        _startGroupMembersRealtime(groupId, meId);
        unawaited(_reloadGroupMembersFromBackfill(groupId, meId));
      }
    });
  }

  void _scheduleGroupMembersReconnect(String groupId, String? meId) {
    _groupMembersReconnectTimer?.cancel();
    _groupMembersReconnectTimer = Timer(_groupMembersReconnectDelay, () {
      if (!mounted || _disposed || widget.groupId != groupId) return;
      _startGroupMembersRealtime(groupId, meId);
      unawaited(_reloadGroupMembersFromBackfill(groupId, meId));
    });
  }

  Future<void> _reloadGroupMembersFromBackfill(
    String groupId,
    String? meId, {
    bool forceRebuild = false,
  }) async {
    if (_groupMembersBackfillInFlight || !mounted || _disposed) return;
    _groupMembersBackfillInFlight = true;
    try {
      final members = await CruiseGroupService.fetchMembers(
        groupId,
      ).timeout(const Duration(seconds: 4));
      if (!mounted || _disposed || widget.groupId != groupId) return;
      final changed = _mergeGroupMembers(members, meId: meId);
      if (changed || forceRebuild) {
        _safeSetState(() {});
      }
    } catch (_) {
      // Backfill ist ein Recovery-Pfad. Bei kurzem Netzproblem bleibt der
      // letzte bekannte Marker sichtbar und wird nur gedimmt.
    } finally {
      _groupMembersBackfillInFlight = false;
    }
  }

  bool _mergeGroupMembers(List<GroupMember> members, {String? meId}) {
    var changed = false;
    for (final member in members) {
      if (member.userId == meId) continue;
      changed = _mergeGroupMember(member, meId: meId) || changed;
    }
    return changed;
  }

  bool _mergeGroupMember(GroupMember incoming, {String? meId}) {
    if (incoming.userId == meId) return false;
    final existing = _groupMembers[incoming.userId];
    final merged = existing == null
        ? incoming
        : GroupMember(
            id: incoming.id,
            groupId: incoming.groupId,
            userId: incoming.userId,
            role: incoming.role,
            rideRole: incoming.rideRole,
            currentLat: incoming.currentLat,
            currentLng: incoming.currentLng,
            lastUpdatedAt: incoming.lastUpdatedAt,
            createdAt: incoming.createdAt,
            displayName: incoming.displayName ?? existing.displayName,
            avatarUrl: incoming.avatarUrl ?? existing.avatarUrl,
          );
    if (existing != null && _sameGroupMemberState(existing, merged)) {
      return false;
    }
    _groupMembers[incoming.userId] = merged;
    final lat = merged.currentLat;
    final lng = merged.currentLng;
    if (lat != null && lng != null) {
      _peerTargetPos[incoming.userId] = [lng, lat];
      // Erste Position: direkt setzen (kein Anflug quer ueber die Karte).
      _peerShownPos.putIfAbsent(incoming.userId, () => [lng, lat]);
    }
    return true;
  }

  bool _sameGroupMemberState(GroupMember a, GroupMember b) {
    return a.id == b.id &&
        a.groupId == b.groupId &&
        a.userId == b.userId &&
        a.role == b.role &&
        a.rideRole == b.rideRole &&
        a.currentLat == b.currentLat &&
        a.currentLng == b.currentLng &&
        a.lastUpdatedAt == b.lastUpdatedAt &&
        a.displayName == b.displayName &&
        a.avatarUrl == b.avatarUrl;
  }

  Widget _buildGroupMemberMarker(GroupMember m) {
    final isDriver = m.rideRole == RideRole.driver;
    final isFresh = m.hasFreshLocation(maxAge: _groupMemberFreshLocationAge);
    final liveColor = isDriver
        ? AppAccentColors.accent
        : const Color(0xFF4FC3F7);
    final color = isFresh ? liveColor : const Color(0xFF8A8F98);
    return Opacity(
      opacity: isFresh ? 1.0 : 0.48,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0E14),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: isFresh ? 3 : 2),
          boxShadow: [
            if (isFresh)
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
      ),
    );
  }

  bool _hasGroupMemberLocation(GroupMember m) => m.hasLocation;

  bool _positionUploadInFlight = false;

  Future<void> _uploadMyPosition() async {
    if (widget.groupId == null) return;
    final pos = _userPosition;
    if (pos == null) return;
    // 2026-06-10 (vucko Find-My-Härtung): Bei kaputtem Netz hingen die
    // 2s-Uploads ohne Timeout minutenlang und stauten sich — der eigene
    // Standort alterte für ALLE Mitfahrer ("man sieht sich nicht mehr").
    // Jetzt: hartes 3s-Timeout, keine Überlappung, nächster Tick probiert
    // sowieso erneut (Heartbeat-Charakter bleibt erhalten).
    if (_positionUploadInFlight) return;
    _positionUploadInFlight = true;
    try {
      await CruiseGroupService.updateMyPosition(
        groupId: widget.groupId!,
        lat: pos.latitude,
        lng: pos.longitude,
      ).timeout(const Duration(seconds: 3));
    } catch (_) {
      // still — Timer rettet beim nächsten Tick; Marker beim Peer dimmt nur.
    } finally {
      _positionUploadInFlight = false;
    }
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

  // 2026-05-24 (vucko Task #53): Trip-Resume aus Home-Carousel.
  void _onPendingTripResume() {
    _consumePendingTripResumeIfAvailable();
  }

  Future<void> _consumePendingTripResumeIfAvailable() async {
    if (!mounted || _disposed) return;
    final tripId = CruiseModePage.pendingTripResume.value;
    if (tripId == null) return;
    if (_tripResumeInFlight) return;
    _tripResumeInFlight = true;
    // 2026-06-10 (vucko Resume-Crash-Fix): Der Intent wird erst NACH dem
    // erfolgreichen Laden der Stopps konsumiert (siehe unten). Vorher wurde er
    // SOFORT genullt — crashte die Cruise-Page beim allerersten Öffnen
    // (MapLibre-Erstopen-Race), war der Resume-Wunsch weg und der nächste
    // Öffnen-Versuch zeigte nur das leere Setup. Jetzt überlebt der Intent den
    // Crash → der zweite Open lädt die Tour automatisch.
    try {
      final stops = await TripService.instance.stopsFor(tripId);
      if (!mounted || _disposed) return;
      // 2026-05-24 (vucko Fix): wenn Trip kaputt (keine/zu wenige Stops) →
      // sauberer Top-Toast + Trip in DB als completed markieren damit er
      // nicht weiter in der Resume-Card auftaucht.
      if (stops.length < 2) {
        TopToast.show(
          context,
          message:
              'Diese Tour hat keine gültigen Wegpunkte mehr — wird geschlossen.',
          icon: Icons.info_outline_rounded,
          duration: const Duration(milliseconds: 3500),
        );
        unawaited(_safeCompleteTrip(tripId));
        CruiseModePage.pendingTripResume.value = null; // bewusst geschlossen
        return;
      }
      // Resume in DB markieren (status=active, resumed_at=now)
      await TripService.instance.resumeTrip(tripId);
      // Setze UI-State: Trip-Mode an, Wegpunkte = stops (ohne start),
      // _activeTripId = tripId damit Pause/Complete später greift.
      // 2026-06-10 (vucko Trip-Resume): NUR die noch nicht befahrenen Stopps
      // (actual_arrival == null) + IMMER das Endziel laden — bereits
      // abgehakte Stopps (markStopReached während der Fahrt) werden beim
      // Weiterfahren nicht erneut angefahren. Route wird unten von der
      // AKTUELLEN Position aus neu generiert (egal wo man weiterfährt).
      final waypoints = stops
          .where(
            (s) =>
                s.stopType != 'start' &&
                (s.actualArrival == null ||
                    s.stopType == 'destination' ||
                    s.stopType == 'end'),
          )
          .map((s) => LatLng(s.lat, s.lng))
          .toList(growable: false);
      if (!mounted || _disposed) return;
      // 2026-06-10 (vucko Trip-Resume): 1 verbleibender Punkt (= Endziel) ist
      // VALIDE — Route von der aktuellen Position direkt zum Ziel (Audit T1-M:
      // 1-Wegpunkt-Trip erzeugt eine saubere A→B-Route). Nur komplett leer
      // (alle Stopps inkl. Ziel abgefahren) wird geschlossen.
      if (waypoints.isEmpty) {
        TopToast.show(
          context,
          message: 'Alle Stopps dieser Tour sind bereits abgefahren.',
          icon: Icons.info_outline_rounded,
          duration: const Duration(milliseconds: 3500),
        );
        unawaited(_safeCompleteTrip(tripId));
        CruiseModePage.pendingTripResume.value = null; // bewusst geschlossen
        return;
      }
      setState(() {
        _activeTripId = tripId;
        _tripModeEnabled = true;
        _isRoundTrip = true;
        _planningType = 'Wegpunkte';
        _roundTripWaypoints
          ..clear()
          ..addAll(waypoints);
      });
      // ERFOLG → Intent jetzt (und erst jetzt) konsumieren.
      CruiseModePage.pendingTripResume.value = null;
      // Visuelle Bestätigung
      TopToast.show(
        context,
        message: 'Trip wird fortgesetzt — ${waypoints.length} Stopps geladen',
        icon: Icons.route_rounded,
        duration: const Duration(milliseconds: 2800),
      );
      // 2026-05-24 (vucko): Auto-Route-Generation nach Resume.
      // Sonst sieht der User nur leere Karte mit Wegpunkten — verwirrend.
      // Delay damit setState durch ist + UI gemounted.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted || _disposed) return;
      unawaited(_generateRoute());
    } catch (e) {
      debugPrint('[CruiseMode] Trip-Resume failed: $e');
      // Intent NICHT konsumieren → nächster Page-Open versucht es erneut.
      if (mounted && !_disposed) {
        TopToast.show(
          context,
          message: 'Tour konnte nicht geladen werden.',
          icon: Icons.warning_amber_rounded,
          duration: const Duration(milliseconds: 3000),
        );
      }
    } finally {
      _tripResumeInFlight = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // 2026-06-15 (vucko M5): Map SOFORT inaktiv — ein in-flight Render-/Kamera-
    // Tick während des Page-Teardowns darf keinen Native-Call mehr absetzen.
    _mlController?.active = false;
    WidgetsBinding.instance.removeObserver(this);
    // 2026-06-02 (vucko Sync): CarPlay-Hooks lösen (Page-Lebenszyklus).
    if (CarCommandListener.instance.onCompletionDone != null) {
      CarCommandListener.instance.onCompletionDone = null;
    }
    if (CarCommandListener.instance.onStartNavigation != null) {
      CarCommandListener.instance.onStartNavigation = null;
    }
    if (CarCommandListener.instance.onPlanRoute != null) {
      CarCommandListener.instance.onPlanRoute = null;
    }
    // 2026-05-24 (vucko Task #53): aktive Trip pausieren beim Verlassen
    // (z. B. App-Backgrounding, Tab-Wechsel). Best-effort.
    final tripIdToPause = _activeTripId;
    if (tripIdToPause != null) {
      _activeTripId = null;
      unawaited(_safePauseTrip(tripIdToPause));
    }
    _routeDrawAnimationToken++;
    _routeDrawAnimationTimer?.cancel();
    _routeLoadingPhaseTimer?.cancel();
    _routeSearchExitTimer?.cancel();
    _cameraAnimController?.removeListener(_onCameraAnimationTick);
    _cameraAnimController?.dispose();
    CruiseModePage.isFullscreen.value = false;
    CruiseModePage.pendingRoute.removeListener(_onPendingRoute);
    CruiseModePage.pendingTripResume.removeListener(_onPendingTripResume);
    _stopSimulation(restartLiveTracking: false);
    _positionSubscription?.cancel();
    _socketPositionSubscription?.cancel();
    _positionUploadTimer?.cancel();
    _peerAnimTimer?.cancel();
    _groupRouteBackfillTimer?.cancel();
    _groupRouteReconnectTimer?.cancel();
    _groupMembersBackfillTimer?.cancel();
    _groupMembersReconnectTimer?.cancel();
    _groupMembersFreshnessTimer?.cancel();
    _viewportPoiDebounce?.cancel();
    _groupRouteCh?.unsubscribe();
    _groupMembersCh?.unsubscribe();
    _stopIdlePositionStream();
    unawaited(_navigationSocketService.dispose());
    _destinationController.removeListener(_onDestinationTextChanged);
    _destinationController.dispose();
    _destinationFocusNode.removeListener(_onDestinationFocusChanged);
    _destinationFocusNode.dispose();
    _startLocationFocusNode.removeListener(_onDestinationFocusChanged);
    _startLocationFocusNode.dispose();
    _startLocationController.dispose();
    _configScrollController.dispose();
    super.dispose();
  }

  // 2026-05-28 (vucko Startup-V Issue 3A): Fokus-Wechsel des Suchfelds →
  // Bottom-Actions ein-/ausblenden, damit das Autocomplete-Overlay sie nicht
  // verdeckt.
  void _onDestinationFocusChanged() {
    // 2026-05-28 (vucko): Beide Suchfelder (Ziel + Startort) berücksichtigen —
    // sobald eines Fokus hat, Bottom-Actions ausblenden.
    final hasFocus =
        _destinationFocusNode.hasFocus || _startLocationFocusNode.hasFocus;
    if (hasFocus == _destinationHasFocus) return;
    if (!mounted || _disposed) {
      _destinationHasFocus = hasFocus;
      return;
    }
    setState(() => _destinationHasFocus = hasFocus);
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
  // 2026-06-08 (vucko Butterweich): KONTINUIERLICHER Smooth-Follow pro Frame.
  // Statt 5Hz engine-animateCamera (deren Ease-in/out an jeder Unterbrechung die
  // Geschwindigkeit pulsen ließ = Mini-Ruckeln) zieht der Ticker den Kamera-Stand
  // jeden Frame ein Stück linear Richtung Ziel und setzt ihn INSTANT (moveCamera).
  // Lineare Bewegung + 1 Channel-Call pro Frame (coalesced) = butterweich.
  // Kamera-Bewegungs-Diagnostik bleibt für Entwickler im Code, ist für Uploads
  // aber per Default deaktiviert.
  static const bool _perfCamDiag = bool.fromEnvironment('PERF_CAM_DIAG');
  final List<double> _camDiagSteps = [];
  int _camDiagStalls = 0;
  int _camDiagTicks = 0;
  DateTime? _camDiagLastReport;

  void _camDiagRecord(double stepMeters) {
    _camDiagTicks++;
    if (stepMeters < 0.05) {
      _camDiagStalls++;
    } else {
      _camDiagSteps.add(stepMeters);
    }
    final now = DateTime.now();
    _camDiagLastReport ??= now;
    if (now.difference(_camDiagLastReport!) < const Duration(seconds: 10)) {
      return;
    }
    _camDiagLastReport = now;
    final steps = List<double>.from(_camDiagSteps)..sort();
    final ticks = _camDiagTicks;
    final stalls = _camDiagStalls;
    _camDiagSteps.clear();
    _camDiagStalls = 0;
    _camDiagTicks = 0;
    if (steps.isEmpty) {
      debugPrint('[PERF-CAM] ticks=$ticks stall=100% (keine Bewegung)');
      return;
    }
    final avg = steps.reduce((a, b) => a + b) / steps.length;
    final p95 = steps[((steps.length - 1) * 0.95).round()];
    debugPrint(
      '[PERF-CAM] ticks=$ticks | moving=${steps.length} | '
      'stall=${(stalls / ticks * 100).toStringAsFixed(1)}% | '
      'step avg=${avg.toStringAsFixed(2)}m p95=${p95.toStringAsFixed(2)}m '
      'max=${steps.last.toStringAsFixed(2)}m',
    );
  }

  // 2026-06-10 (vucko Fahr-Ruckeln-Fix, MESSBELEGT): Zähler für den
  // Konvergenz-Stop — steht die Kamera ~45 Frames praktisch still (Ampel,
  // Stillstand), wird der 120Hz-Ticker gestoppt statt weiter pro Frame
  // moveCamera zu feuern. Jeder GPS-Fix startet ihn über _animateCameraTo
  // sofort wieder (`if (!controller.isAnimating) controller.repeat()`).
  int _camIdleTicks = 0;
  // 2026-06-13 (vucko Free-Cam-Ruckeln): Hysterese-Zähler für den Free-Cam-
  // Idle-Stop — verhindert Ticker-Pause bei kurzen Speed-Dips.
  int _freeCamIdleTicks = 0;

  void _onCameraAnimationTick() {
    if (!_mapReady || _isOverviewActive) {
      _cameraAnimController?.stop();
      _lastCameraFrameAt = null;
      return;
    }
    // 2026-06-10 (vucko Fahr-Ruckeln-Fix, MESSBELEGT): Das Kamera-ZIEL wurde
    // bisher nur pro GPS-Event gesetzt. Echtes iOS-GPS liefert ~1Hz → das Ziel sprang
    // 1×/Sekunde um ~Sekunden-Fahrstrecke (70 km/h ≈ 19 m), die Dämpfung
    // raste in ~100 ms hinterher und stand dann ~900 ms still = das „Ruckeln"
    // am Gerät (am Simulator unsichtbar, weil die Sim mit 20 Hz füttert).
    // Jetzt wird das Ziel JEDEN Frame aus der Kalman-Prediction des Smoothers
    // weitergeschoben (Dead Reckoning mit 150 ms Vorhalt wie bisher; dt-Clamp
    // 1,5 s im Smoother verhindert Davonlaufen bei GPS-Aussetzern). Gleiche
    // Optik/Framing (Zoom, Offset, Dämpfung, Heading-Dead-Zone unverändert) —
    // nur kontinuierlich statt pulsierend. Web behält den Event-Pfad.
    //
    // 2026-06-13 (vucko Free-Cam-/Off-Route-Ruckeln, Geraete-Videos): Der
    // Puck-Glide + Linien-Schnitt laufen jetzt in JEDEM Kameramodus pro
    // Frame. Vorher stoppte der Ticker beim Verlassen der Zentrierung
    // komplett → die Render-Position wurde nur noch pro GPS-Fix (1Hz)
    // fortgeschrieben und der Puck teleportierte sekuendlich (~19m bei
    // 70 km/h). Kamera-Bewegung bleibt natuerlich an _isCameraLocked
    // gebunden; bei stehender Kamera stossen wir die Marker-Projektion
    // selbst an (sonst projiziert nur onCameraMove).
    if (!kIsWeb) {
      // 2026-06-11 (vucko Route-Lock): Kamera folgt derselben route-gesnappten
      // Render-Position wie der Puck (eine Quelle) — vorher zog die freie
      // Kalman-Prediction die Kamera seitlich neben die Linie.
      final lockPos = _routeLockedRenderPosition(
        DateTime.now().add(_nativeRenderPredictionLead),
      );
      // Linien-Schnitt mitziehen: ist der gerenderte Fortschritt dem letzten
      // Trim voraus, frisch nachtrimmen. Der sichtbare Linienkopf haengt am
      // selben Route-Lock-Meter wie der Puck (+kleiner Vorhalt unterm Puck).
      if (_renderLockDistM >= 0 &&
          _lastTrimDistM >= 0 &&
          _renderLockDistM - _lastTrimDistM > _routeTrimPushGateM &&
          _lastWindowMatch != null) {
        if (_trimVisibleRouteToProjection(_lastWindowMatch!)) {
          _safeSetState(() {});
        }
      }
      if (!_isCameraLocked) {
        // Freie Kamera: Puck-Overlay pro Frame reprojizieren.
        _mlController?.reprojectMarkers();
        // 2026-06-13 (vucko Free-Cam-Ruckeln, Geraete-Video): Idle-Stop mit
        // HYSTERESE. Vorher stoppte der Ticker bei einem EINZELNEN Frame
        // <0,3 m/s — ein kurzer Smoother-Speed-Dip (nach Reroute, GPS-Glitch)
        // hielt den Puck dann bis zum nächsten 1Hz-Fix an (Mikro-Ruckeln).
        // Jetzt: erst nach ~0,5s anhaltendem Quasi-Stillstand (<0,15 m/s)
        // pausieren; jeder Speed-Pickup setzt den Zähler zurück.
        // 2026-06-15 (vucko M4 „Puck IMMER fluessig"): Auch das ROHE GPS-Tempo
        // prüfen. Bei einem fehlerhaften Reroute kann die Smoother-Geschwindigkeit
        // kurz auf ~0 einfrieren, OBWOHL der Wagen faehrt — dann darf der Ticker
        // NICHT pausieren, sonst klebt der Puck bis zum naechsten 1Hz-Fix.
        final movingByGps = (_userLocation?.speed ?? 0) > 0.6;
        if (_nativeSmoother.speed < 0.15 && !movingByGps) {
          _freeCamIdleTicks++;
          if (_freeCamIdleTicks >= 30) {
            _cameraAnimController?.stop();
            _lastCameraFrameAt = null;
            _freeCamIdleTicks = 0;
          }
        } else {
          _freeCamIdleTicks = 0;
        }
        return;
      }
      if (lockPos != null) {
        _camToLat = lockPos.latitude;
        _camToLng = lockPos.longitude;
        // 2026-06-13 (vucko Kamera-Abbiege-Ruckeln, Geraete-Video): Heading-Ziel
        // jetzt AUCH pro Frame aus der Smoother-Prediction nachführen (analog
        // zur Position). Vorher war es event-gesteuert (1×/GPS-Fix) → beim
        // Abbiegen sprang das Ziel 1×/s und die Drehung kam in Bursts (Ruckeln).
        // Der Smoother extrapoliert das Heading mit geglätteter Drehrate, die
        // Dead-Zone (gegen GPS-Jitter im Stand) bleibt erhalten.
        if (_nativeSmoother.hasValidHeading) {
          final predHeading = _nativeSmoother
              .predict(DateTime.now().add(_nativeRenderPredictionLead))
              .heading;
          final delta = _angleDiff(_camToHeading, predHeading).abs();
          // Mikro-Jitter (<0,6°) ignorieren — sonst zappelt die Karte im Stand.
          if (delta >= 0.6) {
            _camToHeading = predHeading;
            _lastCameraHeading = predHeading;
          }
        }
      }
    } else if (!_isCameraLocked) {
      _cameraAnimController?.stop();
      _lastCameraFrameAt = null;
      return;
    }
    if (!_camHasState || _camMoveInFlight) return;
    final frameNow = DateTime.now();
    final previousFrameAt = _lastCameraFrameAt;
    _lastCameraFrameAt = frameNow;
    // Kritisch gedämpftes Annähern (Apple/Google-artig). Auf dem echten Gerät
    // kommt nicht jeder AnimationController-Tick bis zu MapLibre durch
    // (_camMoveInFlight coalesced Method-Channel-Calls). Der alte fixe 0.18-
    // Faktor war pro Tick kalibriert und wurde bei 30/20fps effektiv zu langsam.
    // Zeitnormiert bleibt die Follow-Zeitkonstante stabil, ohne bei langen Pausen
    // zu teleportieren (max 4 Frame-Äquivalente).
    final f = frameNormalizedBlend(
      perFrameBlend: 0.18,
      elapsed: previousFrameAt == null
          ? null
          : frameNow.difference(previousFrameAt),
    );
    final prevLat = _camCurLat;
    final prevLng = _camCurLng;
    final prevHeading = _camCurHeading;
    _camCurLat += (_camToLat - _camCurLat) * f;
    _camCurLng += (_camToLng - _camCurLng) * f;
    _camCurHeading = _lerpAngleDeg(_camCurHeading, _camToHeading, f);
    final stepMeters = geo.Geolocator.distanceBetween(
      prevLat,
      prevLng,
      _camCurLat,
      _camCurLng,
    );
    if (_perfCamDiag) _camDiagRecord(stepMeters);
    // Konvergenz-Stop: praktisch keine Bewegung mehr (<1 cm/Frame, <0.05°)
    // über ~45 Frames → Ticker stoppen, kein moveCamera-Spam im Stillstand.
    if (stepMeters < 0.01 &&
        _angleDiff(prevHeading, _camCurHeading).abs() < 0.05) {
      if (++_camIdleTicks >= 45) {
        _camIdleTicks = 0;
        _cameraAnimController?.stop();
        _lastCameraFrameAt = null;
        return;
      }
    } else {
      _camIdleTicks = 0;
    }
    final ctrl = _mlController;
    if (ctrl == null) return;
    // Forward-Offset: Zentrum ~100m voraus → Puck sitzt im unteren Drittel.
    final offLat = _camCurLat + _forwardOffsetLat(_camCurHeading);
    final offLng = _camCurLng + _forwardOffsetLng(_camCurHeading);
    _camMoveInFlight = true;
    ctrl
        .moveTo(lat: offLat, lng: offLng, zoom: 16.5, bearing: _camCurHeading)
        .whenComplete(() => _camMoveInFlight = false);
  }

  /// Startet eine animierte Kamera-Bewegung von der aktuellen zur neuen Position.
  void _animateCameraTo(double lat, double lng, double heading) {
    final controller = _cameraAnimController;
    if (controller == null || !_mapReady) return;

    // Bearing-Dead-Zone: kleinste Heading-Änderungen ignorieren (GPS-Rauschen).
    final deadZoneDegrees = (!kIsWeb && Platform.isIOS)
        ? 0.8
        : Platform.isAndroid
        ? 1.0
        : 1.5;
    var effectiveHeading = heading;
    final headingDelta = _angleDiff(_lastCameraHeading, heading).abs();
    if (headingDelta < deadZoneDegrees) {
      effectiveHeading = _lastCameraHeading;
    } else {
      _lastCameraHeading = heading;
    }

    // 2026-06-08 (vucko Butterweich): NUR das Ziel setzen — die Bewegung macht der
    // kontinuierliche Ticker (_onCameraAnimationTick) pro Frame. Kein engine-Ease
    // pro Fix → kein Puls-Ruckeln; ein moveCamera/Frame (coalesced) → kein Stau.
    _camToLat = lat;
    _camToLng = lng;
    _camToHeading = effectiveHeading;
    if (!_camHasState) {
      _camCurLat = lat;
      _camCurLng = lng;
      _camCurHeading = effectiveHeading;
      _camHasState = true;
    }
    if (!controller.isAnimating) {
      _lastCameraFrameAt = null;
      controller.repeat();
    }
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

  String get _carRouteType {
    if (_isWaypointPlanning) return CarRouteType.waypoints;
    return _isRoundTrip ? CarRouteType.roundtrip : CarRouteType.pointToPoint;
  }

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

  bool get _isActivelyDrivingRoute =>
      _isRouteConfirmed &&
      (_positionSubscription != null ||
          _socketPositionSubscription != null ||
          _isSimulationRunning);

  LatLng? get _activeRouteEndMarkerPoint {
    if (!_isActivelyDrivingRoute || _fullRouteCoordinates.length < 2) {
      return null;
    }
    final remainingDistance = _remainingDistance;
    if (remainingDistance == null || remainingDistance > 3000) return null;
    final end = _fullRouteCoordinates.last;
    if (end.length < 2) return null;
    return LatLng(end[1], end[0]);
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

  List<LatLng> _deliveredRoundTripWaypointsFromMeta(Map<String, dynamic> meta) {
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

  // ─────────────────── "Standort wählen": Start-Picker ───────────────────────
  // 2026-05-28 (vucko): Setzt den manuell gewählten Startpunkt (Karten-Tap
  // oder Adresssuche), beendet den Karten-Pick-Modus, reverse-geocodet den
  // Ortsnamen für die Anzeige und verwirft eine evtl. alte Route-Preview.
  void _setPickedStartLocation(LatLng point, {String? label}) {
    setState(() {
      _pickedStartLocation = point;
      _pickedStartLabel = label;
      _isPickingStartOnMap = false;
      _selectedLocation = 'Standort wählen';
    });
    HapticFeedback.selectionClick();
    _dismissTransientRouteUi();
    _resetGeneratedRouteUiState();
    if (label == null) {
      unawaited(() async {
        final name = await _geocodingService.reverseGeocode(
          point.latitude,
          point.longitude,
        );
        if (!mounted || _disposed) return;
        if (name != null && _pickedStartLocation == point) {
          setState(() => _pickedStartLabel = name);
        }
      }());
    }
    if (mounted) {
      TopToast.show(
        context,
        message: label == null ? 'Startpunkt gesetzt' : 'Startpunkt: $label',
        icon: Icons.my_location_rounded,
        duration: const Duration(milliseconds: 2200),
      );
    }
  }

  void _beginPickStartOnMap() {
    setState(() {
      _isPickingStartOnMap = true;
      _selectedLocation = 'Standort wählen';
      _configCollapsed = true; // Karte freigeben für den Tap.
    });
    if (mounted) {
      TopToast.show(
        context,
        message: 'Tippe auf die Karte für deinen Startpunkt',
        icon: Icons.touch_app_rounded,
        duration: const Duration(milliseconds: 2600),
      );
    }
  }

  // 2026-05-28 (vucko): Startort aus der Adresssuche übernommen.
  void _onStartLocationSelected(PlaceSuggestion suggestion) {
    _setPickedStartLocation(
      LatLng(suggestion.latitude, suggestion.longitude),
      label: suggestion.placeName,
    );
  }

  void _clearPickedStartLocation() {
    setState(() {
      _pickedStartLocation = null;
      _pickedStartLabel = null;
      _isPickingStartOnMap = false;
      _startLocationController.clear();
    });
    _dismissTransientRouteUi();
    _resetGeneratedRouteUiState();
  }

  void _handleMapTap(TapPosition? tapPosition, LatLng point) {
    if (_isLoading || _isRouteConfirmed) return;
    // 2026-05-28 (vucko): "Standort wählen" — Karten-Tap setzt den Startpunkt.
    if (_isPickingStartOnMap) {
      _setPickedStartLocation(point);
      return;
    }
    if (!_isWaypointPlanning) return;
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
    // 2026-05-22 (vucko): Dynamisches Limit je nach Mode.
    // Normal: 3 Stopps, Trip-Mode: 5. UI lässt User mehr setzen, aber bei
    // Route-Suche → klare Hinweis "max N".
    // Hard-Cap auf 8 für sehr explorative User (mehr ist nicht sinnvoll).
    if (_roundTripWaypoints.length >= 8) {
      _showError(
        'Max 8 Stopps technisch möglich. Aktiviere Trip-Modus für 5, sonst max 3.',
        isCritical: false,
      );
      return;
    }
    // 2026-06-01 (vucko): KEIN Trip-Modus-Tutorial mehr beim Setzen des 2.
    // Wegpunkts im Standard-Modus — das nervte im Test ("Vorschlag Trip-Modus"
    // obwohl man bewusst Standard nutzt). Das Tutorial kommt jetzt nur noch
    // einmalig beim echten Wechsel auf Trip-Modus (siehe _buildWaypointModeHeader).
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

  /// First-Use Tutorial-Overlay zeigt Trip-Modus-Option freundlich.
  /// 2026-05-22 (vucko Task #7): "schau dass ein cooles overlay kommt"
  void _showWaypointTutorialOverlay() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1C1F26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppAccentColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.tips_and_updates_rounded,
                      color: AppAccentColors.accent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tipp: Trip-Modus',
                      style: TextStyle(
                        color: AppAccentColors.accent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Du planst eine Route mit Stopps. Hier dein Cheat-Sheet:',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 14),
              _tutorialBullet(
                '🎯',
                'Standard',
                'Bis zu 3 Stopps für eine schnelle Tour',
              ),
              const SizedBox(height: 10),
              _tutorialBullet(
                '🗺️',
                'Trip-Modus',
                'Bis zu 5 Stopps, mit Pause/Resume — perfekt für Mehrtages-Touren',
              ),
              const SizedBox(height: 10),
              _tutorialBullet(
                '💾',
                'Auto-Save',
                'Trip wird gespeichert, du kannst später im Homescreen weitermachen',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    if (mounted) setState(() => _tripModeEnabled = true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppAccentColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Trip-Modus aktivieren (5 Stopps)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'Bei 3 Stopps bleiben',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWaypointLimitDialog(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1C1F26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.amber,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Zu viele Stopps',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              if (!_tripModeEnabled) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      if (mounted) setState(() => _tripModeEnabled = true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppAccentColors.accent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Trip-Modus aktivieren',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'OK, ich entferne Stopps',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tutorialBullet(String emoji, String title, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13, height: 1.4),
              children: [
                TextSpan(
                  text: '$title — ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: text,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
    // 2026-05-24 (vucko Task #47): Limit erhöht auf 5 (Trip-Modus).
    // Vorher hartes "> 3" hat Trip-Modus mit 4-5 Stopps blockiert.
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
          if (!_isRouteConfirmed)
            RepaintBoundary(
              // 2026-05-28 (vucko): Weicher Übergang beim Auf-/Zuklappen statt
              // hartem setState-Wechsel. Collapsed- und Expanded-Tree haben
              // distinkte Keys (config_collapsed / config_expanded), der
              // AnimatedSwitcher faded+slidet zwischen ihnen. Beide Trees sind
              // bottom-anchored → vertikaler Slide liest sich wie ein
              // hochfahrendes/absinkendes Sheet.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final slide = Tween<Offset>(
                    begin: const Offset(0, 0.06),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  fit: StackFit.expand,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                child: _buildConfigOverlay(),
              ),
            ),
          if (_isRouteConfirmed)
            RepaintBoundary(child: _buildNavigationOverlay()),
          // 2026-05-28 (vucko Task #79): Komplette FAB-Spalte auch ohne
          // Route — verschwindet animiert wenn Setup-Sheet hochgezogen ist.
          if (!_isRouteConfirmed) _buildFabColumn(hasRoute: false),
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
      _isLoading ||
      _routeSearchNoticeTitle != null ||
      _routeSearchStatusLeaving;

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
        : (_routeSearchNoticeTitle ?? 'Route gefunden');
    final status = _isLoading
        ? _routeLoadingStatusText
        : (_routeSearchNoticeMessage ??
              'Gerade keine gute Route gefunden. Wir suchen weiter im Hintergrund.');
    final noticeIsSuccess = _routeSearchNoticeIsSuccess(title);
    final progressValue = isNotice
        ? (noticeIsSuccess ? 1.0 : math.min(_routeSearchProgress, 0.92))
        : _routeSearchProgress;

    final statusCard = _buildCompactRoundTripSearchStatus(
      title: title,
      status: status,
      progress: progressValue,
      isNotice: isNotice,
      isLeaving: _routeSearchStatusLeaving,
      maxWidth: math.min(media.size.width - 32, 430),
    );
    return Positioned(
      top: media.padding.top + 12,
      left: 16,
      right: 16,
      // 2026-05-31 (vucko): Während der Suche bleibt der Status nicht
      // wegwischbar (IgnorePointer ein). Sobald es ein Hinweis ist (z.B.
      // „Route noch nicht verfügbar"/„Route gefunden"), kann man ihn einzeln
      // zur Seite wischen — wie eine Handy-Benachrichtigung.
      child: IgnorePointer(
        ignoring: !isNotice,
        child: Align(
          alignment: Alignment.topCenter,
          child: isNotice
              ? Dismissible(
                  key: const ValueKey('roundtrip-search-notice'),
                  direction: DismissDirection.horizontal,
                  resizeDuration: null,
                  onDismissed: (_) => _dismissRouteSearchNotice(),
                  child: statusCard,
                )
              : statusCard,
        ),
      ),
    );
  }

  bool _routeSearchNoticeIsSuccess(String title) {
    return title.trim().toLowerCase().contains('route gefunden');
  }

  Widget _buildCompactRoundTripSearchStatus({
    required String title,
    required String status,
    required double progress,
    required bool isNotice,
    required bool isLeaving,
    required double maxWidth,
  }) {
    final accent = AppAccentColors.accent;
    final clampedProgress = progress.clamp(0.0, 1.0);
    final noticeIsSuccess = isNotice && _routeSearchNoticeIsSuccess(title);
    final showPercent = !isNotice || noticeIsSuccess;
    final iconColor = isNotice && !noticeIsSuccess
        ? const Color(0xFFFFC861)
        : accent;
    return TweenAnimationBuilder<double>(
      key: const ValueKey('roundtrip-search-compact'),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0.0, end: isLeaving ? 0.0 : 1.0),
      builder: (context, visibility, child) {
        return Opacity(
          opacity: visibility.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -42 * (1 - visibility)),
            child: Transform.scale(
              scale: 0.96 + (0.04 * visibility),
              child: child,
            ),
          ),
        );
      },
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeOutCubic,
        tween: Tween<double>(begin: 0.08, end: clampedProgress),
        builder: (context, animatedProgress, _) {
          return Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
                    decoration: BoxDecoration(
                      color: const Color(0xF0151820),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.52),
                        width: 1.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.24),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.34),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: iconColor.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(17),
                                border: Border.all(
                                  color: iconColor.withValues(alpha: 0.38),
                                ),
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutBack,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: Tween<double>(
                                        begin: 0.82,
                                        end: 1,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  );
                                },
                                child: isNotice
                                    ? Icon(
                                        noticeIsSuccess
                                            ? CupertinoIcons.check_mark_circled
                                            : CupertinoIcons
                                                  .exclamationmark_circle,
                                        key: ValueKey(
                                          noticeIsSuccess
                                              ? 'notice-success'
                                              : 'notice-warning',
                                        ),
                                        color: iconColor,
                                        size: 22,
                                      )
                                    : CupertinoActivityIndicator(
                                        key: const ValueKey('search-loading'),
                                        radius: 9,
                                        color: accent,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
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
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    status,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.82,
                                      ),
                                      fontSize: 14,
                                      height: 1.22,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (showPercent) ...[
                              const SizedBox(width: 12),
                              Text(
                                '${(animatedProgress * 100).clamp(0, 100).round()}%',
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            height: 5,
                            color: Colors.white.withValues(alpha: 0.12),
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: animatedProgress.clamp(0.03, 1.0),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      accent.withValues(alpha: 0.82),
                                      accent,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: [
                                    BoxShadow(
                                      color: accent.withValues(alpha: 0.56),
                                      blurRadius: 12,
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
      ),
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
    // 2026-05-23 (vucko UX-refactor): Mode-Header schlank (~44px),
    // also Map-Controls direkt darunter (~70px Abstand).
    final top =
        media.padding.top + (_shouldShowRoundTripSearchStatus ? 78 : 70);
    final selected = _selectedRoundTripWaypointIndex;
    final replacing = _replaceRoundTripWaypointIndex;
    // 2026-05-22 (vucko): Dynamisches Limit-Display
    final subtitle = replacing != null
        ? 'Neu'
        : _roundTripWaypoints.isEmpty
        ? 'Stopps'
        : '${_roundTripWaypoints.length}/$_currentMaxWaypoints';
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
                  // 2026-05-28 (vucko Task #80): Inline-FABs in der
                  // Wegpunkt-Rail. Statt einer zweiten Spalte rechts unten
                  // landen POI/Voice/Camera hier am Ende der Rail. Optisch
                  // getrennt mit dünnem Divider.
                  const SizedBox(height: 12),
                  Container(
                    width: 36,
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                  const SizedBox(height: 4),
                  AnimatedBuilder(
                    animation: PoiSettingsService.instance,
                    builder: (context, _) {
                      final active = PoiSettingsService.instance.anyEnabled;
                      return _buildWaypointMapAction(
                        icon: Icons.tune_rounded,
                        label: 'POIs',
                        onTap: _isLoading ? null : _openPoiFilter,
                        overrideAccent: active ? AppAccentColors.accent : null,
                      );
                    },
                  ),
                  AnimatedBuilder(
                    animation: VoiceSettingsService.instance,
                    builder: (context, _) {
                      final mode = VoiceSettingsService.instance.mode;
                      final (icon, color) = switch (mode) {
                        VoiceMode.off => (Icons.volume_off_rounded, null),
                        VoiceMode.important => (
                          Icons.volume_down_rounded,
                          const Color(0xFFFBBF24),
                        ),
                        VoiceMode.all => (
                          Icons.volume_up_rounded,
                          AppAccentColors.accent,
                        ),
                      };
                      return _buildWaypointMapAction(
                        icon: icon,
                        label: 'Sprache',
                        overrideAccent: color,
                        onTap: () async {
                          await VoiceSettingsService.instance.cycleMode();
                          HapticFeedback.selectionClick();
                          if (!context.mounted) return;
                          final newMode = VoiceSettingsService.instance.mode;
                          final newLabel = switch (newMode) {
                            VoiceMode.off => 'Stumm',
                            VoiceMode.important => 'Nur Wichtiges',
                            VoiceMode.all => 'Alle Ansagen',
                          };
                          TopToast.show(
                            context,
                            message: 'Sprache: $newLabel',
                            icon: switch (newMode) {
                              VoiceMode.off => Icons.volume_off_rounded,
                              VoiceMode.important => Icons.volume_down_rounded,
                              VoiceMode.all => Icons.volume_up_rounded,
                            },
                          );
                        },
                      );
                    },
                  ),
                  _buildWaypointMapAction(
                    icon: _isCameraLocked ? Icons.explore : Icons.explore_off,
                    label: 'Kamera',
                    overrideAccent: _isCameraLocked
                        ? AppAccentColors.accent
                        : null,
                    onTap: _toggleCameraLock,
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
    Color? overrideAccent,
  }) {
    final enabled = onTap != null;
    final accent = destructive
        ? const Color(0xFFFF6B5F)
        : (overrideAccent ?? AppAccentColors.accent);
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

  // 2026-05-24 (vucko Task #33): Style-Dock entfernt aus Map.
  // Funktion bleibt für Fallback/Future-Use erhalten.
  // ignore: unused_element
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
      // 2026-05-23 (vucko Task #23+33): Wenn Error-Banner ("Stopps prüfen")
      // sichtbar ist, Mode-Header + Style-Dock ausblenden → Screen wird
      // aufgeräumt, User-Fokus bleibt auf Banner + Karte.
      // 2026-05-24 (vucko Task #33): Style-Dock GANZ aus der Map raus —
      // gehört ins Setup-Panel. Map zeigt nur noch Mode-Header + Stop-Controls.
      final hasErrorBanner = _routeSearchNoticeTitle != null;
      final showWaypointChrome =
          _isWaypointPlanning && !_showRouteInfoBanner && !hasErrorBanner;
      return Stack(
        key: const ValueKey('config_collapsed'),
        children: [
          if (_showRouteInfoBanner && _lastRouteResult != null)
            _buildRoutePreviewHeader(),
          if (showWaypointChrome) _buildWaypointModeHeader(),
          if (showWaypointChrome) _buildWaypointMapControls(),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            // 2026-05-28 (vucko): KEIN „Rundkurs suchen"-Button mehr im
            // eingeklappten Zustand. Im Startup-V-Test haben viele sofort auf
            // den Button getippt, OHNE je die Einstellungen (Länge/Stil/
            // Autobahn/Standort) zu sehen. Jetzt gibt es hier nur eine klare
            // „Strecke planen"-CTA, die das Setup-Panel öffnet — der eigentliche
            // Such-Button lebt ausschließlich unten im ausgeklappten Panel,
            // nachdem der User die Optionen gesehen hat.
            child: GestureDetector(
              onTap: () => setState(() => _configCollapsed = false),
              onVerticalDragUpdate: (details) {
                // Hochziehen (negativer dy) öffnet das Panel.
                if (details.primaryDelta != null &&
                    details.primaryDelta! < -6) {
                  setState(() => _configCollapsed = false);
                }
              },
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  MediaQuery.of(context).padding.bottom + 14,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0xCC0B0E14),
                      Color(0xFF0B0E14),
                    ],
                    stops: [0.0, 0.4, 1.0],
                  ),
                ),
                child: Builder(
                  builder: (context) {
                    // 2026-05-30 (vucko): Wenn schon eine Route berechnet ist
                    // (Preview-Banner oben sichtbar), gehört der „Route
                    // bestätigen"-Button auch in den eingeklappten Zustand —
                    // direkt über „Strecke planen", damit man nicht erst wieder
                    // hochziehen muss, um loszufahren.
                    final hasConfirmableRoute =
                        _showRouteInfoBanner &&
                        _lastRouteResult != null &&
                        (_fullRouteCoordinates.length >= 2 ||
                            _routeLatLngs.length >= 2);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag-Handle (Pill)
                        Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (hasConfirmableRoute) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _confirmRoute,
                              icon: const Icon(
                                Icons.navigation_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              label: const Text(
                                'Route bestätigen',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppAccentColors.accent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        // „Strecke planen" (bzw. „Route ändern" wenn schon eine
                        // Route da ist) — öffnet das Setup-Panel.
                        Container(
                          width: double.infinity,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: hasConfirmableRoute
                                ? null
                                : [
                                    BoxShadow(
                                      color: AppAccentColors.accent.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: hasConfirmableRoute
                              ? OutlinedButton.icon(
                                  onPressed: () =>
                                      setState(() => _configCollapsed = false),
                                  icon: Icon(
                                    Icons.tune_rounded,
                                    color: AppAccentColors.accent,
                                    size: 20,
                                  ),
                                  label: const Text(
                                    'Route ändern',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1C1F26),
                                    side: BorderSide(
                                      color: AppAccentColors.accent.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  ),
                                )
                              : ElevatedButton.icon(
                                  onPressed: () =>
                                      setState(() => _configCollapsed = false),
                                  icon: const Icon(
                                    Icons.tune_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                  label: Text(
                                    _isWaypointPlanning
                                        ? 'Wegpunkte planen'
                                        : _isRoundTrip
                                        ? 'Strecke planen'
                                        : 'Route planen',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppAccentColors.accent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                        ),
                        if (hasConfirmableRoute && _activeTripId != null) ...[
                          const SizedBox(height: 8),
                          _buildTripLifecycleActions(height: 46),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Ausgeklappter Zustand: vollständiges Config-Panel
    return Stack(
      key: const ValueKey('config_expanded'),
      children: [
        // Overscroll nach oben (= Swipe-Down am Anfang) → einklappen.
        // 2026-05-28 (vucko Startup-V Issue 1): ScrollNotification zusätzlich
        // abgreifen, um zu wissen ob noch Inhalt nach unten kommt (Fade-Hint).
        // 2026-05-30 (vucko): Schwelle gesenkt (−6 statt −15), damit Runter-
        // wischen am Listenanfang zuverlässig einklappt statt zu „kleben".
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is OverscrollNotification &&
                notification.overscroll < -6) {
              setState(() => _configCollapsed = true);
              return true;
            }
            if (notification is ScrollUpdateNotification ||
                notification is ScrollMetricsNotification) {
              final m = notification.metrics;
              final canScrollDown = m.pixels < m.maxScrollExtent - 12;
              if (canScrollDown != _configCanScrollDown && mounted) {
                setState(() => _configCanScrollDown = canScrollDown);
              }
            }
            return false;
          },
          child: CustomScrollView(
            controller: _configScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Transparenter Bereich oben → Map scheint durch + Einklapp-Pfeil
              SliverToBoxAdapter(
                child: GestureDetector(
                  // 2026-05-30 (vucko): Direkt auf die Wisch-Bewegung reagieren
                  // (onVerticalDragUpdate) statt nur auf die End-Velocity —
                  // dadurch klappt der obere Streifen sofort & zuverlässig ein,
                  // egal wie schnell gewischt wird (Bug: „kam nicht vom Overlay
                  // weg"). Tap auf den Streifen klappt ebenfalls ein.
                  onTap: () => setState(() => _configCollapsed = true),
                  onVerticalDragUpdate: (details) {
                    if (details.primaryDelta != null &&
                        details.primaryDelta! > 4) {
                      setState(() => _configCollapsed = true);
                    }
                  },
                  onVerticalDragEnd: (details) {
                    // 2026-05-31 (vucko): Fling-Schwelle gesenkt (120→60), damit
                    // schon ein leichtes Runterwischen das Panel schließt.
                    if ((details.primaryVelocity ?? 0) > 60) {
                      setState(() => _configCollapsed = true);
                    }
                  },
                  child: Container(
                    // 2026-05-28 (vucko Startup-V Issue 1): Ausgeklappt =
                    // (fast) Vollbild. Nur ein schmaler Streifen Karte oben
                    // bleibt sichtbar + der „Einklappen"-Griff. Das Setup füllt
                    // den Rest, und der Such-Button scrollt am Ende mit (unten)
                    // — so ist sofort klar, dass man scrollen kann.
                    height: MediaQuery.of(context).padding.top + 64,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xFF0B0E14)],
                        stops: [0.0, 1.0],
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        // 2026-05-31 (vucko): Prominenter Pull-Tab statt kleinem
                        // „Einklappen"-Chip — der breite Greif-Balken signalisiert
                        // klar „hier runterwischen zum Schließen". Tippen schließt
                        // ebenfalls (onTap am äußeren GestureDetector).
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 52,
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF1C1F26,
                                ).withValues(alpha: 0.82),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                  SizedBox(width: 5),
                                  Text(
                                    'Runterwischen zum Schließen',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
                      // 2026-05-31 (vucko): Wenn schon eine Route berechnet ist,
                      // sitzt das Stats-Banner als erste Karte IM Scroll-Fluss
                      // — direkt über dem Setup, sauber gestapelt, keine
                      // Überlappung mehr. Antippen klappt das Panel ein, damit
                      // man die Route gleich auf der Karte sieht.
                      if (_showRouteInfoBanner && _lastRouteResult != null) ...[
                        GestureDetector(
                          onTap: () => setState(() => _configCollapsed = true),
                          child: _buildRouteInfoBanner(),
                        ),
                        const SizedBox(height: 18),
                      ],
                      CruiseSetupCard(
                        isRoundTrip: _isRoundTrip,
                        planningType: _planningType,
                        selectedLength: _selectedLength,
                        selectedLocation: _selectedLocation,
                        selectedStyle: _selectedStyle,
                        selectedDestination: _selectedDestination,
                        destinationController: _destinationController,
                        destinationFocusNode: _destinationFocusNode,
                        startLocationController: _startLocationController,
                        startLocationFocusNode: _startLocationFocusNode,
                        pickedStartLabel: _pickedStartLabel,
                        onPickStartOnMap: _beginPickStartOnMap,
                        onStartLocationSelected: _onStartLocationSelected,
                        onStartLocationCleared: _clearPickedStartLocation,
                        countryPreference: _countryPreference,
                        homeCountryCode:
                            _homeCountryCode ??
                            CountryRegion.classify(
                              _userLocation?.latitude ?? 47.24,
                              _userLocation?.longitude ?? 9.6,
                            ),
                        onCountryPreferenceChanged: (pref) {
                          setState(() => _countryPreference = pref);
                          unawaited(_persistCountryPreference(pref));
                        },
                        onRoundTripChanged: _handleRouteModeChanged,
                        onPlanningTypeChanged: _handlePlanningTypeChanged,
                        onLengthChanged: (v) {
                          if (kDebugMode) {
                            debugPrint('[RouteDebug][UIState] selectedKm=$v');
                          }
                          setState(() => _selectedLength = v);
                        },
                        onLocationChanged: (v) =>
                            setState(() => _selectedLocation = v),
                        onStyleChanged: (v) {
                          if (kDebugMode) {
                            debugPrint(
                              '[RouteDebug][UIState] selectedStyle=$v',
                            );
                          }
                          setState(() => _selectedStyle = v);
                        },
                        selectedDetour: _selectedDetour,
                        onDetourChanged: _handleDetourChanged,
                        selectedAvoidHighways: _avoidHighways,
                        proximityLatitude: _userLocation?.latitude,
                        proximityLongitude: _userLocation?.longitude,
                        onAvoidHighwaysChanged: (value) {
                          if (kDebugMode) {
                            debugPrint(
                              '[RouteDebug][UIState] avoidHighways=$value',
                            );
                          }
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
                      // 2026-05-28 (vucko Startup-V Issue 1): Such-/Bestätigen-
                      // Button sitzt am Ende des Scroll-Inhalts (inline, kein
                      // dunkles Loch mehr). Direkt unter dem Setup → man muss
                      // scrollen, um ihn zu erreichen, was die Scrollbarkeit
                      // signalisiert. Safe-Area-Abstand unten.
                      const SizedBox(height: 20),
                      _buildBottomActions(inline: true),
                      SizedBox(
                        height: MediaQuery.of(context).padding.bottom + 20,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // 2026-05-31 (vucko): Route-Info-Banner NICHT mehr schwebend im
        // ausgeklappten Zustand — das überlappte den „Strecken-Setup"-Header
        // (höchst unprofessionell). Stattdessen wird es als erste Karte IN den
        // Scroll-Fluss über den Setup gesetzt (siehe unten in der Column).
        // Schwebend bleibt es nur im eingeklappten Zustand (über der Karte).
        // Top-Mode-Header auch im ausgeklappten Zustand — aber nicht
        // wenn Error-Banner aktiv (sonst Doppel-Header oben)
        if (_isWaypointPlanning &&
            !_showRouteInfoBanner &&
            _routeSearchNoticeTitle == null)
          _buildWaypointModeHeader(),
        // 2026-05-28 (vucko Startup-V Issue 1): „Mehr unten"-Hinweis. Solange
        // noch Inhalt nach unten scrollbar ist, ein weicher Fade + pulsierender
        // Chevron am unteren Rand — wie bei Apple/Google Maps. Verschwindet
        // automatisch, sobald der User ganz unten ist (Button erreicht).
        // IgnorePointer, damit Taps/Scroll durchgehen.
        if (_configCanScrollDown && !_destinationHasFocus)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 56,
            child: IgnorePointer(
              child: Container(
                alignment: Alignment.bottomCenter,
                padding: const EdgeInsets.only(bottom: 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xFF0B0E14)],
                  ),
                ),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppAccentColors.accent.withValues(alpha: 0.9),
                  size: 26,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRoutePreviewHeader() {
    // 2026-05-24 (vucko Task #48): Wetter direkt im Stats-Banner
    // integriert (kein 2. Pop-up mehr). Cleaner Single-Card.
    final top = MediaQuery.of(context).padding.top + 8;
    // 2026-05-31 (vucko): Hochwischen wischt das Banner weg → es schrumpft zu
    // einer kleinen Recall-Pille oben rechts. Tippen oder Runterwischen holt
    // die volle Route-Info wieder zurück. Das macht das Wegräumen/Zurückholen
    // „lebendig" und gibt der Karte Platz, ohne die Route zu verlieren.
    if (_routeBannerDismissed) {
      return Positioned(top: top, right: 12, child: _buildRouteRecallPill());
    }
    return Positioned(
      top: top,
      left: 12,
      right: 12,
      child: Dismissible(
        key: const ValueKey('route_preview_banner'),
        direction: DismissDirection.up,
        resizeDuration: null,
        onDismissed: (_) {
          if (!mounted) return;
          setState(() => _routeBannerDismissed = true);
        },
        child: _buildRouteInfoBanner(),
      ),
    );
  }

  /// 2026-05-31 (vucko): Kompakte Pille, die das weggewischte Route-Banner
  /// repräsentiert. Tippen oder Runterwischen holt es zurück.
  Widget _buildRouteRecallPill() {
    final result = _lastRouteResult;
    final distMeters = result?.distanceMeters;
    final distLabel = distMeters != null
        ? '${(distMeters / 1000.0).toStringAsFixed(0)} km'
        : null;
    return GestureDetector(
      onTap: () {
        if (!mounted) return;
        setState(() => _routeBannerDismissed = false);
      },
      onVerticalDragUpdate: (details) {
        if ((details.primaryDelta ?? 0) > 4) {
          if (!mounted) return;
          setState(() => _routeBannerDismissed = false);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xF0151820),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: AppAccentColors.accent.withValues(alpha: 0.5),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_rounded, color: AppAccentColors.accent, size: 18),
            const SizedBox(width: 7),
            Text(
              distLabel != null ? 'Route · $distLabel' : 'Routeninfo',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 5),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white54,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteInfoBanner() {
    final result = _lastRouteResult!;
    // Immer echte Mapbox-Distanz nutzen (distanceMeters), nicht distanceKm (war geclampt)
    final distKm = result.distanceMeters != null
        ? (result.distanceMeters! / 1000.0).toStringAsFixed(1)
        : '--';
    final actualDistanceKm = result.distanceMeters != null
        ? result.distanceMeters! / 1000.0
        : (result.distanceKm ?? 0.0);
    // 2026-05-23 (vucko): Akkuratere Zeit-Anzeige.
    // GH-Duration kann unrealistisch sein (zu lang in alpine Bergen wenn viele
    // Tempo-30-Zonen drin, zu kurz wenn Autobahn übergewichtet). Hybrid:
    //   1. Wenn GH-Duration vorhanden UND avg-speed plausibel (25-110 km/h) → nehmen
    //   2. Sonst: aus Distanz × style-typischer Avg-Speed schätzen
    // Style-Werte basierend auf echten Motorradtouring-Schnitten (Landstraße):
    //   Sport: 60 km/h (gemischt Land+Stadt)
    //   Kurvenjagd: 48 km/h (kurvenreich = langsamer)
    //   Abendrunde: 55 km/h (entspannt)
    //   Entdecker: 52 km/h (mix mit kleinen Straßen)
    final estimatedAverageKmh = switch (_selectedStyle.toLowerCase()) {
      'kurvenjagd' || 'kurvenreich' => 48.0,
      'abendrunde' || 'panorama' => 55.0,
      'sport' || 'sport mode' || 'sport_mode' => 60.0,
      'entdecker' || 'zufall' => 52.0,
      _ => 55.0,
    };
    int durationMin;
    final realDurationSeconds = result.durationSeconds;
    if (realDurationSeconds != null &&
        realDurationSeconds > 30 &&
        actualDistanceKm > 0) {
      final ghAvgKmh = actualDistanceKm / (realDurationSeconds / 3600);
      if (ghAvgKmh >= 25 && ghAvgKmh <= 110) {
        // GH-Wert plausibel — direkt nutzen
        durationMin = (realDurationSeconds / 60).round();
      } else {
        // GH unrealistisch — Style-Schätzung
        durationMin = (actualDistanceKm / estimatedAverageKmh * 60).round();
      }
    } else if (actualDistanceKm > 0) {
      durationMin = (actualDistanceKm / estimatedAverageKmh * 60).round();
    } else {
      durationMin = 0;
    }
    final hours = durationMin ~/ 60;
    final mins = durationMin % 60;
    final timeStr = hours > 0 ? '${hours}h ${mins}min' : '$mins min';
    final curveCount = _cachedCurveCount;
    // 2026-05-23 (vucko): Source-Badge entfernt — User-Wunsch
    // "live / emergency_fallback / routenpool nicht mehr oben anzeigen".
    // _routeSourceLabel() bleibt in den meta-Daten für Debug, aber nicht im UI.

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
          // 2026-05-24 (vucko): Wetter inline als 5. Metric — passt zum
          // Style der anderen (Distanz/Dauer/Kurven/XP) ohne dicke Extra-Card.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: _buildInfoItem(
                  Icons.straighten,
                  '$distKm km',
                  'Distanz',
                ),
              ),
              Expanded(
                child: _buildInfoItem(Icons.timer_outlined, timeStr, 'Dauer'),
              ),
              Expanded(
                child: _buildInfoItem(
                  Icons.turn_right,
                  '$curveCount',
                  'Kurven',
                ),
              ),
              Expanded(
                child: _buildInfoItem(
                  Icons.star_outline,
                  '${_calculateRouteXp()}',
                  'XP',
                ),
              ),
              if (_routeStartCoord() != null)
                Expanded(
                  child: WeatherInline(
                    latitude: _routeStartCoord()![1],
                    longitude: _routeStartCoord()![0],
                    durationMinutes: durationMin,
                  ),
                ),
            ],
          ),
          // 2026-05-24 (vucko): Optionale dezente Footer-Zeile:
          // - Steigung wenn > 50m (kleines Chip)
          // - Wetter-Warnung (Regen/Trend/Gewitter) nur bei Bedarf
          if (_ascentMeters() > 50 || _routeStartCoord() != null) ...[
            _buildBannerFooterStrip(durationMin: durationMin),
          ],
        ],
      ),
    );
  }

  /// 2026-05-24 (vucko): Route-Start-Coordinate [lng, lat] für Wetter-Position.
  List<double>? _routeStartCoord() {
    final coords = _lastRouteResult?.coordinates;
    if (coords == null || coords.isEmpty) return null;
    final c = coords.first;
    if (c.length < 2) return null;
    return c;
  }

  Widget _buildBannerFooterStrip({required int durationMin}) {
    final start = _routeStartCoord();
    final ascent = _ascentMeters();
    final showAscent = ascent > 50;
    final showWeatherWarning = start != null;
    if (!showAscent && !showWeatherWarning) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showAscent) ...[
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppAccentColors.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppAccentColors.accent.withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.terrain_outlined,
                    size: 13,
                    color: AppAccentColors.accent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '+${ascent}m',
                    style: TextStyle(
                      color: AppAccentColors.accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (showWeatherWarning)
          WeatherWarningStrip(
            latitude: start[1],
            longitude: start[0],
            durationMinutes: durationMin,
          ),
      ],
    );
  }

  int _ascentMeters() {
    final meta = _lastRouteResult?.edgeMeta;
    if (meta == null) return 0;
    final raw = meta['ascent_meters'] ?? meta['ascent'];
    if (raw is num) return raw.round();
    return 0;
  }

  // 2026-05-23: nicht mehr im UI gezeigt (User-Wunsch). Beibehalten für
  // Debug-Logs / zukünftige Verwendung in Settings.
  // ignore: unused_element
  String? _routeSourceLabel(RouteResult result) {
    final meta = result.edgeMeta;
    if (meta.isEmpty) return null;
    final raw = (meta['route_source'] ?? meta['source'] ?? '')
        .toString()
        .toLowerCase();
    if (raw.isEmpty) return null;
    if (raw == 'pool' || raw == 'route_pool') return 'POOL';
    if (raw == 'candidate_reserve') return 'POOL+';
    if (raw == 'cache' || raw == 'session_cache') return 'CACHE';
    if (raw == 'mapbox' || raw == 'live') return 'LIVE';
    return raw.toUpperCase();
  }

  /// Berechnet XP für die aktuelle Route via GamificationService.
  int _calculateRouteXp() {
    final distKm = _lastRouteResult?.distanceKm ?? 0;
    return GamificationService.calculateRouteXp(
      distanceKm: distKm,
      curves: _cachedCurveCount,
      style: _selectedStyle,
      // 2026-06-15 (vucko): Streak-Multiplikator auch in der XP-Vorschau zeigen,
      // damit die Anzeige der echten Gutschrift entspricht.
      streakDays: _xpStreakDays,
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

  /// 2026-06-13 (vucko Google/Apple-Bar-Review G1+F6-3): Das Banner soll den
  /// neutralen „Neuberechnung"-Status zeigen (wie Google „Rerouting…"), sobald
  /// ein Reroute läuft ODER der Fahrer klar+anhaltend off-route ist. Die
  /// 1,2s/30m-Schwelle deckt zugleich das 0,6s-Fenster zwischen Lock-Release
  /// und Reroute-Banner ab (kein „Position bewegt sich, aber keine UI-Reaktion").
  bool get _isReroutingBannerActive {
    if (_isRerouting) return true;
    final since = _offRouteSince;
    if (since == null) return false;
    return _offRouteGapMeters > 30.0 &&
        DateTime.now().difference(since) >= const Duration(milliseconds: 1200);
  }

  Widget _buildNavigationOverlay() {
    final topInset = MediaQuery.of(context).padding.top;
    final visibleManeuver = _activeVisibleManeuver();
    final reroutingActive = _isReroutingBannerActive;
    final reroutingDuration = _rerouteStartedAt == null
        ? null
        : DateTime.now().difference(_rerouteStartedAt!);
    return Stack(
      children: [
        Positioned(
          top: topInset + 8,
          left: 12,
          right: visibleManeuver != null ? 12 : null,
          // 2026-06-08 (vucko): Zurück-Button + Manöver-Banner zu EINER Einheit
          // vereint — der Zurück-Chevron sitzt jetzt INNERHALB der Banner-Karte
          // (per Trennlinie abgesetzt) statt als zweite lose Pille daneben.
          child: visibleManeuver != null
              ? CruiseManeuverIndicator(
                  maneuver: visibleManeuver,
                  distanceToManeuverMeters: _calculateDistanceToManeuver(
                    visibleManeuver,
                  ),
                  leading: _buildManeuverBackChevron(),
                  isRerouting: reroutingActive,
                  reroutingDuration: reroutingDuration,
                )
              : _buildRoutePreviewBackButton(),
        ),
        // 2026-05-28 (vucko Task #79): FAB-Spalte aus _buildFabColumn —
        // gleicher Code für Pre-Route und während Navigation, mit dem
        // Unterschied dass im Navigation-State auch Simulation + Overview
        // gezeigt werden. Verschwindet wenn Setup-Sheet hochgezogen ist.
        _buildFabColumn(hasRoute: true),
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

  // 2026-06-08 (vucko): kompakter Zurück-Chevron, der INNERHALB der Manöver-
  // Karte sitzt (als `leading`) — vereint Zurück + Manöver zu einer Einheit.
  Widget _buildManeuverBackChevron() {
    return Semantics(
      button: true,
      label: 'Zurück zum Strecken-Setup',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _returnToCruiseSetupFromActiveRoute,
          borderRadius: BorderRadius.circular(13),
          child: const SizedBox(
            width: 44,
            height: 56,
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoutePreviewBackButton() {
    return Semantics(
      button: true,
      label: 'Zurück zum Strecken-Setup',
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFF1C2028).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 12,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _returnToCruiseSetupFromActiveRoute,
            borderRadius: BorderRadius.circular(14),
            child: const Center(
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════ MAP WIDGET (flutter_map) ════════════════════════

  Widget _buildMapWidget() {
    if (_useMapLibre) return _buildMapLibreMap();
    return _buildFlutterMap();
  }

  // ───────────────────── MapLibre-Kamera-Adapter ─────────────────────────────
  // Bilden die wenigen MapController-Aufrufe nach und dispatchen je nach Engine,
  // damit die Aufrufstellen identisch bleiben.
  void _camMove(double lat, double lng, double zoom, {bool animate = true}) {
    if (_useMapLibre) {
      if (animate) {
        _mlController?.animateTo(lat: lat, lng: lng, zoom: zoom);
      } else {
        _mlController?.moveTo(lat: lat, lng: lng, zoom: zoom);
      }
    } else {
      try {
        _mapController.move(LatLng(lat, lng), zoom);
      } catch (_) {}
    }
  }

  void _camFitBounds(List<LatLng> points, EdgeInsets padding) {
    if (points.length < 2) return;
    if (_useMapLibre) {
      _mlController?.fitBounds(points, padding: padding);
    } else {
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: padding,
          ),
        );
      } catch (_) {}
    }
  }

  // ───────────────────── MapLibre-Karte (neue Engine) ────────────────────────
  Widget _buildMapLibreMap() {
    // 2026-06-06 (vucko P10): Wenn wir den Standort schon kennen (gecacht oder
    // live), die Karte SOFORT dort öffnen (z13) statt bei Deutschland-Mitte@z6.
    // 2026-06-08 (vucko Kamera-Fix): initialCenter/zoom EINMAL fixieren. Vorher
    // hingen sie an _userPosition (ändert sich pro GPS-Tick) → der Map-Widget bekam
    // ständig neue initial-Props → Plattform-View/Controller wurde neu erzeugt →
    // firstFrameReady ging auf dem von der Page gehaltenen Controller verloren →
    // Kamera eingefroren. „Initial" ist per Definition einmalig.
    _stableInitialCenter ??=
        _userPosition ??
        _cachedUserCenter ??
        const LatLng(51.165691, 10.451526);
    _stableInitialZoom ??= (_userPosition ?? _cachedUserCenter) != null
        ? 13.0
        : 6.0;
    // 2026-06-08 (vucko Leitstrich-Sharp-Cut): die AKTIVE rote Linie = die am Puck
    // GESCHNITTENE Reststrecke (solide Farbe), der abgefahrene Teil = grauer
    // Hintergrund. Der Schnitt entsteht durch die Geometrie-Kante (knackscharf wie
    // Google/Apple) statt durch einen unscharfen line-gradient.
    //  - Preview: _routeLatLngs ist die VOLLE Route — und genau das, was die
    //    Einzeichnen-Animation (_startRouteDrawAnimation) von 2 Punkten auf voll
    //    wachsen lässt. Darum hier _routeLatLngs nutzen (NICHT den statischen
    //    _fullRouteBackgroundLatLngs) → die Reveal-Animation ist wieder sichtbar.
    //  - Navigation: _routeLatLngs ist jetzt die VOLLE Route (statisch) → die
    //    komplette Reststrecke ist IMMER kräftig rot sichtbar; der scharfe Schnitt
    //    macht der graue Driven-Trail (drivenTrailPoints), der sie hinter dem Puck
    //    deckend auffrisst. Kein 3km-Fenster mehr (das wirkte „abgeschnitten").
    // 2026-06-09 (vucko Reveal-Fix): die _isRouteConfirmed-Bedingung fiel weg —
    // sie unterdrückte in der Preview die Animation.
    _ensureRouteMetrics();
    // 2026-06-10 (vucko 3km-Sichtdesign v2): Waehrend der bestaetigten Fahrt
    // zeigt die aktive (voll rote) Quelle NUR das 3km-Fenster ab Puck; die
    // Andeutung der Reststrecke macht der dezente Basis-Layer
    // (_buildMapLibreLines). Vor der Fahrt/in der Uebersicht: volle Route voll
    // rot. Fallback: solange noch kein Fenster berechnet ist (Fahrtbeginn),
    // bleibt die VOLLE Route sichtbar — der Strich darf nie verschwinden.
    final canUseLiveRouteWindow =
        _isRouteConfirmed &&
        !_isRerouting &&
        _offRouteSince == null &&
        _brightAheadLatLngs.length >= 2;
    // 2026-06-13 (vucko J4): Fallback NIE mehr die volle Route (die hinter dem
    // Puck weiterläuft) — sondern die Route AB Puck vorwärts. Während Reroute/
    // Off-Route war das 3km-Fenster leer → vorher lag die alte volle Route rot
    // durch den Puck (Video: „Strecke vor UND hinter mir"). In der Preview
    // (noch nicht bestätigt) bleibt _routeLatLngs, damit die Reveal-Animation
    // (2→voll) sichtbar bleibt.
    final activePts = (!_isOverviewActive && _routeLatLngs.length >= 2)
        ? (canUseLiveRouteWindow
              ? _brightAheadLatLngs
              : (_isRouteConfirmed
                    ? _activeRouteAheadFromIndex()
                    : _routeLatLngs))
        : _fullRouteBackgroundLatLngs;
    return CruiseMapLibreMap(
      initialCenter: _stableInitialCenter!,
      initialZoom: _stableInitialZoom!,
      lines: _buildMapLibreLines(),
      markers: _buildMapLibreMarkers(),
      activeRoutePoints: activePts,
      // Grauer „abgefahren"-Trail nur im Folgemodus; in der Übersicht zeigt die
      // ganze rote Route ohne Grau (sauberer Gesamtüberblick).
      drivenTrailPoints: _isOverviewActive ? const [] : _drivenTrailLatLngs,
      routeProgress: _routeProgress,
      // 2026-06-10 (vucko 3km-Sichtdesign): Gesamtlänge fürs GPU-Gradient
      // (transparent hinterm Puck / 3 km voll / Rest dezent). In der Übersicht
      // 0 → Gradient aus, ganze Route voll sichtbar.
      routeTotalMeters: _isOverviewActive ? 0.0 : _routeTotalLenM,
      routeColor: AppAccentColors.accent,
      // 2026-06-10 (vucko Fahr-Ruckeln-Fix): Puck folgt pro Frame der Kalman-
      // Prediction (Dead Reckoning zwischen den ~1Hz-GPS-Fixes) statt der
      // rohen Fix-Position — kein Sekunden-Teleport mehr. Web: aus (dort
      // glättet der WebPositionSmoother den Event-Pfad wie bisher).
      // 2026-06-11 (vucko Route-Lock): Der Puck folgt pro Frame der auf die
      // ROUTE gesnappten Render-Position (eine Quelle mit Linien-Schnitt +
      // Kamera) — Puck faehrt sichtbar AUF der Linie, kein Auseinanderlaufen.
      liveSmoothedPosition: kIsWeb ? null : _readRouteLockedRenderPosition,
      onControllerReady: (c) {
        _mlController = c;
        if (!_mapReady) _onMapReady();
      },
      onMapClick: (p) => _handleMapTap(null, p),
      onCameraMoved: () {
        _unlockCameraFollow();
        _scheduleViewportPoiRefresh();
      },
    );
  }

  /// Aktive rote Linie als Fallback OHNE Stück hinter dem Puck: die Route ab
  /// dem aktuellen Routen-Index vorwärts. Genutzt wenn das 3km-Fenster
  /// (_brightAheadLatLngs) leer ist (Reroute in-flight, Off-Route-Phase,
  /// Fenster-Lücke). _currentRouteIndex ist immer ein gültiger Index in
  /// _fullRouteCoordinates (Commit/Re-Anchor setzen beide konsistent), darum
  /// ist das billig und korrekt — nie hinter dem Standort.
  List<LatLng> _activeRouteAheadFromIndex() {
    final coords = _fullRouteCoordinates;
    if (coords.length < 2) return _routeLatLngs;
    final idx = _currentRouteIndex.clamp(0, coords.length - 1).toInt();
    // Kopf = der auf die ROUTE gesnappte Puck (immer on-road, nie ein
    // Off-Route-Verbinder). Ist er da, hängen wir die Vertices AB idx+1 an →
    // die Linie startet exakt am Puck. Sonst ab dem ≤Puck-Vertex (idx), damit
    // sie trotzdem am Puck klebt (kein vorlaufender Spalt).
    final head = _lastRouteLockedRenderLatLng;
    final tailStart = head != null
        ? (idx + 1).clamp(0, coords.length).toInt()
        : (idx >= coords.length - 1 ? coords.length - 2 : idx);
    final pts = <LatLng>[
      if (head != null) head,
      for (final c in coords.sublist(tailStart)) LatLng(c[1], c[0]),
    ];
    return pts.length >= 2 ? pts : _routeLatLngs;
  }

  List<CruiseMapLine> _buildMapLibreLines() {
    // 2026-06-10 (vucko 3km-Sichtdesign v2): Waehrend der bestaetigten Fahrt
    // liegt hier die DEZENTE Reststrecke ab Puck (Opacity 0.30) — sie deutet
    // „es geht weiter" an, waehrend die aktive Quelle nur das volle
    // 3km-Fenster zeigt. 200m-Gate: ihr Anfang liegt unter dem bright-Fenster
    // und ist unsichtbar, darum sind seltene Pushes voellig ausreichend.
    if (_isRouteConfirmed &&
        !_isOverviewActive &&
        _dimRemainingLatLngs.length >= 2) {
      return [
        CruiseMapLine(
          points: _dimRemainingLatLngs,
          color: AppAccentColors.accent,
          width: 5,
          opacity: 0.30,
        ),
      ];
    }
    return const <CruiseMapLine>[];
  }

  List<CruiseMapMarker> _buildMapLibreMarkers() {
    final markers = <CruiseMapMarker>[];
    final pointToPointDestination = _pointToPointDestinationMarkerPoint;
    final activeRouteEnd = _activeRouteEndMarkerPoint;

    if (_userLocation != null && !_isRouteConfirmed) {
      markers.add(
        CruiseMapMarker(
          id: 'user-loc',
          position: LatLng(_userLocation!.latitude, _userLocation!.longitude),
          width: _puckSize,
          height: _puckSize,
          child: _buildLocationPuck(_userHeading),
        ),
      );
    }
    if (_pickedStartLocation != null &&
        _selectedLocation == 'Standort wählen' &&
        !_isRouteConfirmed) {
      markers.add(
        CruiseMapMarker(
          id: 'picked-start',
          position: _pickedStartLocation!,
          width: 46,
          height: 56,
          alignment: Alignment.topCenter,
          child: _buildPickedStartMarker(),
        ),
      );
    }
    if (_isWaypointPlanning && _roundTripWaypoints.isNotEmpty) {
      for (var i = 0; i < _roundTripWaypoints.length; i++) {
        markers.add(
          CruiseMapMarker(
            id: 'wp-$i',
            position: _roundTripWaypoints[i],
            width: 44,
            height: 44,
            child: GestureDetector(
              onTap: _isLoading ? null : () => _selectRoundTripWaypoint(i),
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
        );
      }
    }
    if (pointToPointDestination != null) {
      markers.add(
        CruiseMapMarker(
          id: 'p2p-dest',
          position: pointToPointDestination,
          width: 44,
          height: 44,
          child: _buildDestinationMarker(),
        ),
      );
    }
    if (activeRouteEnd != null) {
      markers.add(
        CruiseMapMarker(
          id: 'route-end',
          position: activeRouteEnd,
          width: 46,
          height: 46,
          child: _buildDestinationMarker(),
        ),
      );
    }
    for (final poi in _routePois) {
      markers.add(
        CruiseMapMarker(
          id: 'poi-${poi.latitude},${poi.longitude}',
          position: LatLng(poi.latitude, poi.longitude),
          width: 36,
          height: 36,
          child: GestureDetector(
            onTap: () => _showPoiInfoCard(poi),
            child: _buildPoiMarker(poi),
          ),
        ),
      );
    }
    for (final c in _routeConstructions) {
      markers.add(
        CruiseMapMarker(
          id: 'cons-${c.latitude},${c.longitude}',
          position: LatLng(c.latitude, c.longitude),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => ConstructionAlertSheet.show(context, c),
            child: _buildConstructionMarker(c),
          ),
        ),
      );
    }
    if (_userPosition != null && _isRouteConfirmed) {
      // Bei gesperrter Navi-Kamera dreht die MapLibre-Karte bereits per
      // bearing=heading (Fahrtrichtung oben) → der Screen-Overlay-Puck zeigt
      // gerade nach oben (0). Bei freigegebener Kamera (User hat gepannt) zeigt
      // er die echte Fahrtrichtung relativ zur (north-up) Karte.
      markers.add(
        CruiseMapMarker(
          id: 'user-pos',
          position: _userPosition!,
          width: _puckSize,
          height: _puckSize,
          // Folgt pro Frame der Smoother-Prediction (liveSmoothedPosition) —
          // _userPosition bleibt der Fallback, falls der Smoother leer ist.
          followsLivePosition: true,
          child: _buildLocationPuck(_isCameraLocked ? 0.0 : _userHeading),
        ),
      );
    }
    if (widget.groupId != null && _groupMembers.isNotEmpty) {
      for (final entry in _groupMembers.entries) {
        final m = entry.value;
        if (!_hasGroupMemberLocation(m)) continue;
        final shown = _peerShownPos[entry.key];
        markers.add(
          CruiseMapMarker(
            id: 'grp-${entry.key}',
            position: shown != null
                ? LatLng(shown[1], shown[0])
                : LatLng(m.currentLat!, m.currentLng!),
            width: 40,
            height: 40,
            child: _buildGroupMemberMarker(m),
          ),
        );
      }
    }
    return markers;
  }

  Widget _buildFlutterMap() {
    final pointToPointDestination = _pointToPointDestinationMarkerPoint;
    final activeRouteEnd = _activeRouteEndMarkerPoint;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        // Startpunkt: Mitte Deutschlands (wird bei GPS-Erlaubnis sofort überschrieben)
        initialCenter: const LatLng(51.165691, 10.451526),
        initialZoom: 6.0,
        onMapReady: _onMapReady,
        onTap: _handleMapTap,
        // 2026-05-28 (vucko Task #70): Map-Background bei Tile-Lücken auf
        // Dunkle Kartenfarbe statt System-Weiß. So sind Pan-Lücken kaum
        // sichtbar während die Tiles im Hintergrund nachgeladen werden.
        backgroundColor: OfflineMapService.cruiseDarkBackground,
        // Bei echter Karten-Geste: Kamera-Follow in Vorschau und Navigation lösen.
        onPointerDown: (event, point) {
          _unlockCameraFollow();
        },
        // 2026-06-02 (vucko): Beim Schwenken/Zoomen automatisch die POIs im
        // sichtbaren Bereich nachladen → je weiter rausgezoomt, desto mehr
        // POIs über das ganze Sichtfeld. Debounced + nur beim Planen/Browsen.
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture) {
            _unlockCameraFollow();
            _scheduleViewportPoiRefresh();
          }
        },
      ),
      children: [
        // ── Cruise-Dark-Raster-Tile-Layer ────────────────────────────────────
        // 2026-05-28 (vucko Task #77): retinaMode KOMPLETT DEAKTIVIERT.
        // User-Screenshots zeigen regelmäßige vertikale Streifen — das ist
        // klassisches Symptom für retinaMode-URL-Mismatch (Tiles liefern
        // 256px, retinaMode würde @2x verlangen, aber unsere URL
        // hat „/256/" hardcoded → flutter_map streched die Tiles in einer
        // Weise die auf iPhone 17 Pro Max (3x Display) die Streifen
        // produziert).
        // Plus tileDisplay.instantaneous statt fade-in damit es kein
        // Alpha-Blending zwischen alten und neuen Tiles gibt.
        // 2026-06-02 (vucko): WELT-ÜBERSICHT (z0–6) als unterste Vektor-Ebene.
        // Liegt UNTER dem DACH-Detail-Layer → die ganze Welt ist sichtbar/
        // zoombar, außerhalb DACH bleibt (überzoomt) etwas sichtbar statt
        // schwarz. In DACH deckt der DACH-Layer (gleiches Theme, fast gleiche
        // Hintergrundfarbe) sie nahtlos ab. Nur ~43 MB, Egress via R2 gratis.
        if (_worldPmtilesProvider != null)
          VectorTileLayer(
            // 2026-06-03 (vucko): IMMER Raster-Modus (nicht nur beim Fahren).
            // Live-Vektor-Rendering ruckelte beim Planen/Schwenken auf dem Gerät
            // (CPU-schwer). Rasterisierte Tiles werden gecacht → flüssig überall.
            // Konstanter Key → kein Layer-Rebuild/Flash beim Fahrt-Start.
            key: const ValueKey('vtl-world-raster'),
            tileProviders: TileProviders({'protomaps': _worldPmtilesProvider!}),
            theme: _cruiseMapTheme,
            tileOffset: TileOffset.DEFAULT,
            layerMode: VectorTileLayerMode.raster,
            maximumTileSubstitutionDifference: 3,
            concurrency: 4,
          ),
        // 2026-06-02 (vucko): Self-hosted VEKTOR-Tiles (PMTiles aus R2) im
        // Cruise-Dark-Style, sobald geladen. Schlägt Laden/Rendern fehl, bleibt
        // _pmtilesProvider null → eigener Raster-Layer (else) als Fallback,
        // damit die Karte IMMER funktioniert.
        if (_pmtilesProvider != null)
          VectorTileLayer(
            // 2026-06-03 (vucko): IMMER Raster-Modus + konstanter Key.
            // Vorher hybrid (vector beim Planen, raster beim Fahren) — der
            // Vektor-Modus ruckelte beim Schwenken auf dem Gerät, und der
            // Wechsel verursachte einen Tile-Reload-Flash. Raster überall =
            // flüssig + einheitlich, minimal weniger scharf beim Zwischenzoom
            // (akzeptabler Trade-off fürs Cruisen).
            key: const ValueKey('vtl-raster'),
            tileProviders: TileProviders({'protomaps': _pmtilesProvider!}),
            theme: _cruiseMapTheme,
            tileOffset: TileOffset.DEFAULT,
            layerMode: VectorTileLayerMode.raster,
            maximumTileSubstitutionDifference: 3,
            concurrency: 4,
          )
        else
          TileLayer(
            // 2026-06-02 (vucko): externer Karten-Fallback deaktiviert. Fällt das
            // Vektor-PMTiles-Laden aus (z.B. r2.dev rate-limitet die Range-
            // Requests auf die 5GB-Datei), zeigen wir jetzt UNSERE gerasterten
            // Cruise-Dark-Tiles (z6–12 aus R2 — dieselben wie CarPlay, laden
            // zuverlässig als einzelne PNGs). So sieht der User IMMER unseren
            // eigenen Look.
            urlTemplate: OfflineMapService.cruiseRasterTileUrl,
            tileProvider: NetworkTileProvider(),
            userAgentPackageName: 'com.cruise_connect.app',
            retinaMode: false,
            // Tiles enden bei z12 → darüber skaliert flutter_map hoch (kein Schwarz).
            maxNativeZoom: 12,
            tileDisplay: const TileDisplay.instantaneous(),
            keepBuffer: 5,
            panBuffer: 3,
            evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
          ),
        // ── Gesamt-Route als gedimmter Hintergrund ───────────────────────────
        // 2026-05-28 (vucko Task #86 / Startup-V Issue 2): Während der Fahrt
        // ist _routeLatLngs nur das 3km-Sliding-Window. Ohne diesen Hintergrund
        // wirkte die Route „abgeschnitten / kaputt". Wir zeichnen die komplette
        // Route schwach darunter, damit der Gesamtverlauf immer sichtbar ist —
        // KEIN abruptes Ende mehr. Nur im Navigations-Modus (sonst ist die
        // Preview-Polyline ohnehin die volle Route).
        if (_isRouteConfirmed && _fullRouteBackgroundLatLngs.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _fullRouteBackgroundLatLngs,
                color: AppAccentColors.accent.withValues(alpha: 0.28),
                strokeWidth: 3,
              ),
            ],
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
        // ── Grauer „abgefahren"-Trail (ÜBER der roten Voll-Route) ─────────────
        // 2026-06-09 (vucko Voll-Route-Sichtbar): frisst den abgefahrenen Teil
        // hinter dem Puck grau auf — Pendant zum MapLibre-Driven-Layer.
        if (_isRouteConfirmed && _drivenTrailLatLngs.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _drivenTrailLatLngs,
                color: const Color(0xFF6E7178),
                strokeWidth: kIsWeb ? 4 : 6,
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
        // 2026-05-28 (vucko): Manuell gewählter Startpunkt ("Standort wählen").
        if (_pickedStartLocation != null &&
            _selectedLocation == 'Standort wählen' &&
            !_isRouteConfirmed)
          MarkerLayer(
            rotate: true,
            markers: [
              Marker(
                point: _pickedStartLocation!,
                width: 46,
                height: 56,
                alignment: Alignment.topCenter,
                child: _buildPickedStartMarker(),
              ),
            ],
          ),
        if (_isWaypointPlanning && _roundTripWaypoints.isNotEmpty)
          MarkerLayer(
            rotate: true,
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
            rotate: true,
            markers: [
              Marker(
                point: pointToPointDestination,
                width: 44,
                height: 44,
                child: _buildDestinationMarker(),
              ),
            ],
          ),
        if (activeRouteEnd != null)
          MarkerLayer(
            rotate: true,
            markers: [
              Marker(
                point: activeRouteEnd,
                width: 46,
                height: 46,
                child: _buildDestinationMarker(),
              ),
            ],
          ),
        // ── POI-Marker (Tankstellen, Restaurants etc., Google-Maps-Style) ─
        if (_routePois.isNotEmpty)
          MarkerLayer(
            // 2026-06-02 (vucko): rotate=true → Symbole richten sich gegen die
            // Kartendrehung auf, bleiben für den User IMMER lesbar/aufrecht,
            // auch wenn die Karte während der Fahrt gedreht ist.
            rotate: true,
            markers: [
              for (final poi in _routePois)
                Marker(
                  point: LatLng(poi.latitude, poi.longitude),
                  width: 36,
                  height: 36,
                  child: GestureDetector(
                    onTap: () => _showPoiInfoCard(poi),
                    child: _buildPoiMarker(poi),
                  ),
                ),
            ],
          ),
        // ── Baustellen-Marker (Task #66, orange pulsierend) ────────────────
        if (_routeConstructions.isNotEmpty)
          MarkerLayer(
            rotate: true,
            markers: [
              for (final c in _routeConstructions)
                Marker(
                  point: LatLng(c.latitude, c.longitude),
                  width: 40,
                  height: 40,
                  child: GestureDetector(
                    onTap: () => ConstructionAlertSheet.show(context, c),
                    child: _buildConstructionMarker(c),
                  ),
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
            rotate: true,
            markers: _groupMembers.values
                .where(_hasGroupMemberLocation)
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
  /// PMTiles-Vektorquelle (R2). Sobald geladen, rendert die Karte die
  /// self-hosted Tiles im Dark-Style (siehe _buildMapWidget); bleibt sie null,
  /// nutzt die App weiter den eigenen Raster-Layer (Fallback, nichts bricht).
  PmTilesVectorTileProvider? _pmtilesProvider;
  // 2026-06-02 (vucko): Welt-Übersicht (z0–6) als Unterlage unter DACH-Detail.
  PmTilesVectorTileProvider? _worldPmtilesProvider;

  /// Eigenes Mapbox-Dark-ähnliches Theme für die self-hosted Protomaps-Tiles
  /// (einmal gebaut). Ersetzt das karge Standard-Protomaps-Dark.
  late final vtr.Theme _cruiseMapTheme = vtr.ThemeReader().read(
    cruiseDarkMapStyle,
  );

  Future<void> _loadVectorTiles() async {
    final provider = await OfflineMapService.instance.loadPmtilesProvider();
    if (provider != null && mounted) {
      _safeSetState(() => _pmtilesProvider = provider);
    }
    // Welt-Übersicht parallel laden (klein, ~43 MB) → ganze Welt sichtbar,
    // DACH bleibt im Detail. Schlägt das Laden fehl, bleibt's bei DACH-only.
    final world = await OfflineMapService.instance.loadWorldPmtilesProvider();
    if (world != null && mounted) {
      _safeSetState(() => _worldPmtilesProvider = world);
    }
  }

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
      // 2026-06-06 (vucko P10): Kennen wir den Standort schon (gecacht/persistiert),
      // SOFORT hin zentrieren — bevor das asynchrone GPS in _initializeMapLocation
      // auflöst. Schließt das Kaltstart-Fenster, in dem sonst kurz „Deutschland"
      // zu sehen war, falls die Karte vor dem Prefs-Load nativ erzeugt wurde.
      final cached = _cachedUserCenter;
      if (cached != null && _userLocation == null) {
        _camMove(cached.latitude, cached.longitude, 13.0);
      }
      _initializeMapLocation();
    }
  }

  // ═══════════════════════ BOTTOM ACTIONS ═══════════════════════════════════

  // 2026-05-28 (vucko Startup-V Issue 1+3A): [inline]=true wird im
  // ausgeklappten Scroll-Panel verwendet — dann OHNE fixe 160px-Höhe und ohne
  // Gradient-Box, damit der Button nicht in einem großen dunklen Loch
  // „schwebt", sondern sauber direkt unter dem Setup sitzt. [inline]=false
  // (Default) ist die fixierte Leiste im eingeklappten Zustand über der Karte.
  Widget _buildBottomActions({bool inline = false}) {
    final hasConfirmableRoute =
        _lastRouteResult != null &&
        (_fullRouteCoordinates.length >= 2 ||
            _routeLatLngs.length >= 2 ||
            _routeGeoJson != null);
    final actions = Column(
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
                  side: BorderSide(color: AppAccentColors.accent, width: 1.5),
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
        if (hasConfirmableRoute && _activeTripId != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildTripLifecycleActions(height: 46),
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
    );

    if (inline) {
      // Kein Gradient, keine fixe Höhe — sitzt direkt unter dem Setup-Inhalt.
      return Offstage(
        offstage: _destinationHasFocus,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: actions,
        ),
      );
    }

    return Offstage(
      offstage: _destinationHasFocus,
      child: Container(
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
        child: Center(child: actions),
      ),
    );
  }

  Widget _buildTripLifecycleActions({required double height}) {
    return Row(
      children: [
        Expanded(
          child: _buildTripSaveForLaterButton(height: height, compact: true),
        ),
        const SizedBox(width: 8),
        Expanded(child: _buildTripCancelButton(height: height)),
      ],
    );
  }

  Widget _buildTripSaveForLaterButton({
    required double height,
    bool compact = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton.icon(
        onPressed: _isLoading ? null : _saveActiveTripForLater,
        icon: Icon(
          Icons.archive_outlined,
          color: AppAccentColors.accent,
          size: 18,
        ),
        label: Text(
          compact ? 'Speichern' : 'Tour zwischenspeichern',
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 13 : 15,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xFF1C1F26),
          side: BorderSide(
            color: AppAccentColors.accent.withValues(alpha: 0.42),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      ),
    );
  }

  Widget _buildTripCancelButton({required double height}) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton.icon(
        onPressed: _isLoading ? null : _confirmCancelActiveTripFromMap,
        icon: const Icon(
          Icons.close_rounded,
          color: Color(0xFFFF6B61),
          size: 18,
        ),
        label: const Text(
          'Abbrechen',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xFF1C1F26),
          side: BorderSide(
            color: const Color(0xFFFF6B61).withValues(alpha: 0.42),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      ),
    );
  }

  /// Trip-Mode-Toggle: zeigt aktuelles Limit (3 / 5) + Switch.
  /// Tippt der User auf "?" öffnet sich das Tutorial-Overlay erneut.
  /// Top-Mode-Header für Wegpunkte: zwei große Segment-Cards
  /// (Standard / Trip-Modus) mit Slide+Glow-Animation und ausklappbarer
  /// Erklärung. Erscheint ganz oben auf der Map sobald Wegpunkt-Planung
  /// aktiv ist. Ersetzt den alten Bottom-Switch.
  Widget _buildWaypointModeHeader() {
    final media = MediaQuery.of(context);
    final top = media.padding.top + 8;
    final current = _roundTripWaypoints.length;
    final max = _currentMaxWaypoints;
    return Positioned(
      top: top,
      // 2026-05-23 (vucko UX-refactor): Schlanke zentrierte Pill statt
      // breiter Block. Spart vertical Real-Estate massiv.
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.92, end: 1.0),
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) => Transform.scale(
              scale: scale,
              alignment: Alignment.topCenter,
              child: child,
            ),
            child: _WaypointModeHeader(
              tripEnabled: _tripModeEnabled,
              current: current,
              max: max,
              onSelect: (enabled) {
                if (_tripModeEnabled == enabled) {
                  _showWaypointTutorialOverlay();
                  return;
                }
                HapticFeedback.mediumImpact();
                setState(() => _tripModeEnabled = enabled);
                // 2026-06-01 (vucko): Das Trip-Modus-Tutorial kommt jetzt NUR
                // hier — beim ERSTEN echten Wechsel auf Trip-Modus, und nur
                // einmalig (persistent). Beim Zurückschalten/danach nur ein Toast.
                if (enabled && !_waypointTutorialShown) {
                  _waypointTutorialShown = true;
                  unawaited(_persistWaypointTutorialShown());
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _showWaypointTutorialOverlay();
                  });
                } else {
                  TopToast.show(
                    context,
                    message: enabled
                        ? 'Trip-Modus aktiv · bis 5 Stopps, beliebig weit'
                        : 'Standard · bis 3 Stopps für schnelle Rundkurse',
                    icon: enabled
                        ? Icons.compass_calibration
                        : Icons.flag_circle,
                    duration: const Duration(milliseconds: 2200),
                  );
                }
              },
              onHelpTap: _showWaypointTutorialOverlay,
            ),
          ),
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

  // 2026-05-28 (vucko): Marker für den manuell gewählten Startpunkt
  // ("Standort wählen"). Grüner Pin mit Play/Start-Icon, klar vom blauen
  // Ziel-Marker unterscheidbar.
  Widget _buildPickedStartMarker() {
    const color = Color(0xFF34C759);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF101722),
            border: Border.all(color: color, width: 2.3),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.36),
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
          child: const Icon(Icons.play_arrow_rounded, color: color, size: 22),
        ),
        Transform.translate(
          offset: const Offset(0, -4),
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: const Color(0xFF101722),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: color.withValues(alpha: 0.72)),
              ),
            ),
          ),
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

  /// iOS Puck: reiner blauer Punkt, KEIN Richtungspfeil.
  /// 2026-06-13 (vucko J5): Der Richtungskeil sprang mit dem (bei langsamer
  /// Fahrt unzuverlässigen) GPS-/Geräte-Heading herum und wirkte wie ein
  /// „wohin schaut das Handy"-Pfeil. Komplett entfernt — die Kamera ist eh
  /// fahrtrichtungs-oben, der Punkt braucht keinen eigenen Pfeil.
  Widget _buildiOSLocationPuck(double headingDegrees) {
    return const SizedBox(
      width: 44,
      height: 44,
      child: CustomPaint(size: Size(44, 44), painter: _AppleMapsPuckPainter()),
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
          // 2026-06-13 (vucko J5): Richtungspfeil entfernt — reiner Punkt.
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
    // 2026-06-06 (vucko P10): Standort cachen → nächstes Cruise-Page-Öffnen
    // startet die Karte sofort hier statt bei Deutschland-Mitte.
    _cachedUserCenter = LatLng(position.latitude, position.longitude);
    unawaited(_persistUserCenter(_cachedUserCenter!));
    if (!_mapReady) return;
    try {
      _camMove(position.latitude, position.longitude, 13.0);
    } catch (e) {
      debugPrint('[CruiseMode] setCamera fehlgeschlagen: $e');
    }
  }

  // 2026-06-06 (vucko P10): Letzten Standort persistieren + beim App-Start laden,
  // damit AUCH das allererste Cruise-Öffnen nach einem Kaltstart sofort auf dem
  // (zuletzt bekannten) Standort liegt statt auf „Deutschland-Mitte".
  static const String _prefsLastCenterLat = 'cruise_last_center_lat_v1';
  static const String _prefsLastCenterLng = 'cruise_last_center_lng_v1';

  Future<void> _persistUserCenter(LatLng c) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefsLastCenterLat, c.latitude);
      await prefs.setDouble(_prefsLastCenterLng, c.longitude);
    } catch (_) {}
  }

  Future<void> _loadPersistedUserCenter() async {
    if (_cachedUserCenter != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(_prefsLastCenterLat);
      final lng = prefs.getDouble(_prefsLastCenterLng);
      if (lat != null && lng != null) {
        _cachedUserCenter ??= LatLng(lat, lng);
        // Karte schon offen, aber noch kein Live-Fix → sofort grob hin zentrieren.
        if (mounted && _mapReady && _userLocation == null) {
          _camMove(lat, lng, 13.0);
        } else if (mounted) {
          _safeSetState(
            () {},
          ); // nächster Build nutzt _cachedUserCenter als initialCenter
        }
      }
    } catch (_) {}
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
            'Bitte erlaube Cruise Connector den Standortzugriff in den App-Einstellungen.',
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
          'Damit deine Gruppenfahrt weiterläuft, wenn du z. B. zu Spotify wechselst, braucht Cruise Connector die Freigabe "Immer erlauben".',
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

  // 2026-06-10 (vucko Start-Fix): Frische-/Accuracy-Gate für die Startkoordinate.
  // Auf echten Geräten lieferte getLastKnownPosition() beliebig alte Fixes →
  // die Route begann „irgendwo in der Nähe" statt am aktuellen Standort. Ein
  // Fix gilt als frisch, wenn er jünger als 10 s und genauer als 50 m ist.
  static const Duration _startFixMaxAge = Duration(seconds: 10);
  static const double _startFixMaxAccuracyMeters = 50.0;
  // 2026-06-16 (vucko O4/P0 Start-Koordinaten-Bug, Video Churer Straße 9): Beim
  // FAHREN ist der Versatz in Sekunden allein nicht aussagekräftig — ein 10s-alter
  // Stream-Fix ist bei 60 km/h ~150m, bei 100 km/h ~280m daneben. Folge: der
  // A→B-Startpunkt war nicht die echte Position (Such-Puck ≠ Navi-Start-Puck),
  // die Initial-Route passte nicht → ständige Folge-Reroutes. Wir begrenzen den
  // Versatz daher in METERN (Tempo × Alter); im Stand bleibt der 10s-Rahmen.
  static const double _startFixMaxStalenessMeters = 25.0;

  bool _isFreshStartFix(geo.Position position) {
    final ageMs = DateTime.now()
        .difference(position.timestamp)
        .inMilliseconds
        .abs();
    if (position.accuracy <= 0 ||
        position.accuracy > _startFixMaxAccuracyMeters) {
      return false;
    }
    // Positions-Versatz in Metern (Tempo × Alter) hart deckeln — ein frischer
    // getCurrentPosition-Fix (Alter ~0) passiert immer, ein alter Stream-Fix bei
    // Fahrt wird abgelehnt → es wird ein frischer geholt (Such-Spinner läuft eh).
    final speed = position.speed.isFinite && position.speed > 0
        ? position.speed
        : 0.0;
    final positionalStalenessM = speed * (ageMs / 1000.0);
    if (positionalStalenessM > _startFixMaxStalenessMeters) return false;
    return ageMs <= _startFixMaxAge.inMilliseconds;
  }

  String _describeStartFix(geo.Position position) =>
      'age=${DateTime.now().difference(position.timestamp).inMilliseconds}ms '
      'acc=${position.accuracy.toStringAsFixed(0)}m '
      'lat=${position.latitude.toStringAsFixed(5)} '
      'lng=${position.longitude.toStringAsFixed(5)}';

  /// Liefert einen FRISCHEN GPS-Fix für die Routengenerierung.
  ///
  /// Reihenfolge:
  /// 1. Laufender Idle-/Navigations-Stream, wenn frisch (<10 s) und genau
  ///    (<50 m) — kein zusätzliches Warten.
  /// 2. `getCurrentPosition()` mit 12 s Timeout (der Suche-Spinner läuft
  ///    währenddessen bereits).
  /// 3. Fallback nur, wenn der letzte bekannte Fix ebenfalls frisch/genau ist.
  ///
  /// Vorher wurde getLastKnownPosition() BEVORZUGT — auf echten Geräten konnte
  /// der Fix Minuten/Stunden alt sein und die Route begann am falschen Ort.
  Future<geo.Position> _acquireFreshStartFix({
    bool forceCurrentPosition = false,
  }) async {
    final streamFix = _userLocation;
    if (!forceCurrentPosition &&
        streamFix != null &&
        _isFreshStartFix(streamFix)) {
      debugPrint(
        '[CruiseMode][StartFix] source=stream ${_describeStartFix(streamFix)}',
      );
      return streamFix;
    }
    try {
      final fresh = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.best,
        ),
      ).timeout(const Duration(seconds: 12));
      debugPrint(
        '[CruiseMode][StartFix] source=getCurrentPosition '
        '${_describeStartFix(fresh)}',
      );
      if (_isFreshStartFix(fresh)) {
        return fresh;
      }
      debugPrint(
        '[CruiseMode][StartFix] source=getCurrentPosition rejected '
        '${_describeStartFix(fresh)} '
        'limitAge=${_startFixMaxAge.inSeconds}s '
        'limitAcc=${_startFixMaxAccuracyMeters.toStringAsFixed(0)}m',
      );
    } on TimeoutException {
      debugPrint(
        '[CruiseMode][StartFix] getCurrentPosition-Timeout (12s) — '
        'prüfe letzten bekannten Fix',
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
    geo.Position? fallback;
    if (!kIsWeb) {
      fallback = await geo.Geolocator.getLastKnownPosition();
    }
    fallback ??= _userLocation;
    if (fallback != null) {
      if (_isFreshStartFix(fallback)) {
        debugPrint(
          '[CruiseMode][StartFix] source=freshFallback '
          '${_describeStartFix(fallback)}',
        );
        return fallback;
      }
      debugPrint(
        '[CruiseMode][StartFix] source=staleFallback '
        '${_describeStartFix(fallback)} — ABGELEHNT',
      );
    }
    throw const RouteServiceException(
      type: RouteErrorType.validation,
      userMessage:
          'GPS-Fix ist zu alt oder zu ungenau. Bitte kurz warten und erneut versuchen.',
      debugMessage: 'No fresh start fix available within age/accuracy gate.',
      edgeMeta: {'response_code': 'fresh_start_fix_unavailable'},
    );
  }

  Future<geo.Position> _getStartCoordinates({
    bool forceFreshGps = false,
  }) async {
    // 2026-05-28 (vucko): "Standort wählen" mit gesetztem Punkt → von dort
    // starten (Karten-Tap oder Adresssuche). Dijkstra-Routing braucht nur
    // gültige Start-Koordinaten, egal woher.
    if (_selectedLocation == 'Standort wählen' &&
        _pickedStartLocation != null) {
      final picked = _pickedStartLocation!;
      debugPrint(
        '[CruiseMode][StartFix] source=pickedLocation '
        'lat=${picked.latitude.toStringAsFixed(5)} '
        'lng=${picked.longitude.toStringAsFixed(5)}',
      );
      return geo.Position(
        longitude: picked.longitude,
        latitude: picked.latitude,
        timestamp: DateTime.now(),
        accuracy: 5,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
    }
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

      // 2026-06-10 (vucko Start-Fix): Frische-Gate statt getLastKnownPosition-
      // Shortcut (der lieferte beliebig alte Positionen → falscher Routenstart).
      return _acquireFreshStartFix(forceCurrentPosition: forceFreshGps);
    }
    // Fallback: Eigene Position verwenden wenn vorhanden, sonst Vorarlberg
    if (_userLocation != null) {
      debugPrint(
        '[CruiseMode][StartFix] source=userLocationFallback '
        '${_describeStartFix(_userLocation!)}',
      );
      return _userLocation!;
    }
    debugPrint(
      '[CruiseMode][StartFix] source=vorarlbergDefault — keine Position '
      'verfügbar, nutze Default-Koordinate',
    );
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

  Future<void> _generateRoute({bool startValidatorRetry = false}) async {
    // Doppelklick-Schutz: Wenn bereits generiert wird, ignorieren
    if (_isLoading) return;

    // 2026-05-22 (vucko Task #7): Limit-Check vor Routensuche.
    // Normal-Mode: max 3 WPs, Trip-Mode: max 5. UI lässt mehr setzen damit
    // User experimentieren kann, hier kommt der freundliche Hinweis.
    if (_isWaypointPlanning &&
        _roundTripWaypoints.length > _currentMaxWaypoints) {
      final extra = _roundTripWaypoints.length - _currentMaxWaypoints;
      final hint = _tripModeEnabled
          ? 'Im Trip-Modus max 5 Stopps. Du hast $extra zu viel.'
          : 'Im Standard max 3 Stopps. Aktiviere Trip-Modus für bis zu 5, oder entferne $extra Stopp${extra > 1 ? "s" : ""}.';
      _showWaypointLimitDialog(hint);
      return;
    }

    final generationId = ++_routeGenerationSerial;
    final previousUiState = _captureGeneratedRouteUiState();
    _dismissTransientRouteUi();
    _startRouteLoadingUi(generationId: generationId);

    // Hintergrund-Generierung pausieren während User aktiv generiert
    RouteCacheService.beginUserGeneration();

    var requestedDistance = 50;
    String? requestedWaypointSignature;
    var requestedCountryPreference = CountryPreference.any;
    String? requestedHomeCountryCode;
    try {
      final startPosition = await _getStartCoordinates(
        forceFreshGps: startValidatorRetry,
      );
      if (_isRouteGenerationCancelled(generationId)) return;

      // 2026-05-30/06-12 (vucko): Heimatland automatisch aus dem Startpunkt
      // ableiten (offline-Heuristik, kein extra API-Call). Der Filter gilt nur
      // dort, wo der Toggle sichtbar ist: Rundkurs ohne Wegpunkt-/Trip-Modus.
      if (_effectiveCountryPreferenceForGeneration != CountryPreference.any) {
        _homeCountryCode = CountryRegion.classify(
          startPosition.latitude,
          startPosition.longitude,
        );
      }
      final effectiveCountryPreference =
          _effectiveCountryPreferenceForGeneration;
      final effectiveHomeCountryCode = _effectiveHomeCountryCodeForGeneration;
      requestedCountryPreference = effectiveCountryPreference;
      requestedHomeCountryCode = effectiveHomeCountryCode;

      final digits = _selectedLength.replaceAll(RegExp(r'[^0-9]'), '');
      var distance = digits.isNotEmpty ? int.parse(digits) : 50;
      final waypointSnapshot = List<LatLng>.unmodifiable(_roundTripWaypoints);
      final waypointSignature = _isWaypointPlanning
          ? _roundTripWaypointSignature(waypointSnapshot)
          : null;
      requestedWaypointSignature = waypointSignature;
      // 2026-05-23 (vucko Bug-Fix): Limit muss aus _currentMaxWaypoints
      // kommen, nicht hardcoded 3. Vorher griff im Trip-Modus (5 WPs)
      // dieser Branch und zeigte "Bitte nutze maximal 3 Stopps".
      if (_isWaypointPlanning &&
          (waypointSnapshot.isEmpty ||
              waypointSnapshot.length > _currentMaxWaypoints)) {
        final tooManyMsg = _tripModeEnabled
            ? 'Im Trip-Modus max $_currentMaxWaypoints Stopps. Entferne einen Stopp.'
            : 'Standard erlaubt max $_currentMaxWaypoints Stopps. Aktiviere Trip-Modus oben für bis zu 5.';
        _restoreGeneratedRouteFailureUi(
          previousUiState,
          waypointSnapshot.isEmpty
              ? 'Setze mindestens einen Stopp oder lass Vorschläge erzeugen.'
              : tooManyMsg,
          error: RouteServiceException(
            type: RouteErrorType.validation,
            userMessage: waypointSnapshot.isEmpty
                ? 'Setze mindestens einen Stopp oder lass Vorschläge erzeugen.'
                : tooManyMsg,
            debugMessage:
                'Invalid UI waypoint count=${waypointSnapshot.length} max=$_currentMaxWaypoints trip=$_tripModeEnabled.',
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
      // 2026-05-21 (vucko): Bei settingsChanged (Stil/Distanz/AB-Toggle) muss
      // der Auto-Retry-State resettet werden — sonst meint die Defensive-
      // Logik fälschlich, die neue Route sei eine Wiederholung der alten
      // (anderer Style aber zufällig gleicher Fingerprint), triggert Retry,
      // und der User sieht endlose "Suche..."-Schleife.
      if (settingsChanged || routeDebugTrigger == 'firstSearch') {
        _lastDisplayedRouteFingerprint = null;
        _searchAgainAutoRetryCount = 0;
      }
      if (kDebugMode) {
        debugPrint(
          '[RouteDebug][UI] selectedKm=$distance selectedStyle=$_selectedStyle '
          'avoidHighways=$_avoidHighways forceFreshVariant=$forceFreshVariant '
          'startValidatorRetry=$startValidatorRetry '
          'trigger=$routeDebugTrigger '
          'routeType=${_isRoundTrip ? 'ROUND_TRIP' : 'POINT_TO_POINT'} '
          'planningType=$_planningType selectedLength=$_selectedLength '
          'waypointCount=${waypointSnapshot.length} '
          'waypointSignature=${waypointSignature ?? 'none'} '
          'countryPreference=${effectiveCountryPreference.storageValue} '
          'homeCountry=${effectiveHomeCountryCode ?? '-'} '
          'selectedLocation=$_selectedLocation '
          'useCurrentLocation=${_selectedLocation == 'Aktueller Standort'} '
          'startLat=${startPosition.latitude.toStringAsFixed(5)} '
          'startLng=${startPosition.longitude.toStringAsFixed(5)} '
          'clientRoutingBuildId=${RouteService.clientRoutingBuildId} '
          'clientRoutingBuildTime=${RouteService.clientRoutingBuildTime}',
        );
      }
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
        _activeIntermediateWaypoints = const [];
        _passedWaypointIndices.clear();
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
        debugPrint(
          '[CruiseMode][P2PDiag] stage=generate_request '
          'retry=$startValidatorRetry detour=$detourVariant '
          'scenic=$scenicMode directOverride=$_forceAcceptDirectOnce '
          'start=${_describeStartFix(startPosition)} '
          'destLat=${destLat.toStringAsFixed(5)} '
          'destLng=${destLng.toStringAsFixed(5)} '
          'destDistance=${destinationDistanceMeters.toStringAsFixed(0)}m '
          'avoidHighways=$_avoidHighways',
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
          // 2026-05-28 (vucko Task #83): One-Shot direkte Route ohne Quality-Reject.
          forceAcceptDirect: _forceAcceptDirectOnce,
          // 2026-06-09 (vucko A→B-Dijkstra): „Direkt" = EIN schnellster Dijkstra-/
          // CH-Pfad statt 5–6-Varianten-Suche → deutlich schneller. Budget 1 +
          // knappes Zeitbudget nur im Direkt-Fall; Umweg/Scenic behält die Vielfalt.
          candidateBudgetOverride: scenicMode ? null : 1,
          maxSearchMsOverride: scenicMode ? null : 8000,
          countryPreference: effectiveCountryPreference,
          homeCountryCode: effectiveHomeCountryCode,
        );
      } else if (_isWaypointPlanning && waypointSnapshot.isNotEmpty) {
        // 2026-05-23 (vucko Task #22): Trip-Modus = A→B mit Multi-Stopps.
        // Letzter WP = Endziel, alle dazwischen = intermediates.
        // 2026-05-24 (vucko Task #32): Auch im Trip-Modus die gleichen
        // Umweg-Optionen (Direkt / Klein / Mittel / Groß) wie bei A→B.
        //
        // 2026-05-28 (vucko Task #81): Standard-Wegpunkte-Modus (kein
        // Trip-Modus aber Stops gesetzt) wird hier MIT übernommen und
        // als A→B-Pattern mit `destination = startPosition` (Rundkurs-
        // Schleife) geroutet. Vorher ging der Standard-Pfad über
        // `generateRoundTrip(userWaypoints: …)` mit `required_waypoints` —
        // das produziert oft „Stopps prüfen — keine sichere Strecke"
        // wenn der Algorithmus Mapbox-side zu strikt prüft. Trip-Pattern
        // ist deutlich robuster.
        final bool isStandardWaypointMode =
            !_tripModeEnabled && waypointSnapshot.isNotEmpty;
        final LatLng destinationLatLng = isStandardWaypointMode
            ? LatLng(startPosition.latitude, startPosition.longitude)
            : waypointSnapshot.last;
        final List<LatLng> intermediateLatLngs = isStandardWaypointMode
            ? waypointSnapshot
            : waypointSnapshot.sublist(0, waypointSnapshot.length - 1);
        final intermediates = intermediateLatLngs
            .map(
              (p) => <String, double>{
                'latitude': p.latitude,
                'longitude': p.longitude,
              },
            )
            .toList(growable: false);
        final tripDetourVariant = switch (_selectedDetour) {
          'Kleiner Umweg' => 1,
          'Mittlerer Umweg' => 2,
          'Großer Umweg' => 3,
          _ => 0,
        };
        final tripScenic = _selectedDetour != 'Direkt';
        _activeDestinationCoordinate = [
          destinationLatLng.longitude,
          destinationLatLng.latitude,
        ];
        // 2026-06-09 (vucko Trip-Skip): Stopps für Reroute-durch-Reststopps merken.
        _activeIntermediateWaypoints = [
          for (final p in intermediateLatLngs) [p.longitude, p.latitude],
        ];
        _passedWaypointIndices.clear();
        _activeDetourVariant = tripDetourVariant;
        _activePointToPointScenic = tripScenic;
        _activePointToPointMode = tripScenic ? _selectedStyle : 'Standard';
        _activeAvoidHighways = _avoidHighways;
        final subscriptionTier = RouteService.resolveEffectiveSubscriptionTier(
          isTesterOrBeta: true,
        );
        debugPrint(
          '[CruiseMode][P2PDiag] stage=waypoint_request '
          'retry=$startValidatorRetry detour=$tripDetourVariant '
          'scenic=$tripScenic tripMode=$_tripModeEnabled '
          'start=${_describeStartFix(startPosition)} '
          'destLat=${destinationLatLng.latitude.toStringAsFixed(5)} '
          'destLng=${destinationLatLng.longitude.toStringAsFixed(5)} '
          'intermediates=${intermediates.length} '
          'avoidHighways=$_avoidHighways',
        );
        result = await _routeService.generatePointToPoint(
          startPosition: startPosition,
          destinationLat: destinationLatLng.latitude,
          destinationLng: destinationLatLng.longitude,
          mode: tripScenic ? _selectedStyle : 'Standard',
          scenic: tripScenic,
          routeVariant: tripDetourVariant,
          avoidHighways: _avoidHighways,
          forceFreshVariant: forceFreshVariant,
          subscriptionTier: subscriptionTier,
          intermediateWaypoints: intermediates,
          countryPreference: effectiveCountryPreference,
          homeCountryCode: effectiveHomeCountryCode,
        );
        // 2026-05-24 (vucko Task #53): Trip-Mode → Trip in DB persistieren.
        // 2026-06-10 (vucko Trip-Resume): JETZT AUCH SOLO-Trips (User-Wunsch
        // geändert: „statt Route anhalten soll man zwischenspeichern und von
        // egal wo weiterfahren können"). Die Resume-Card lädt die Stopps aus
        // der DB und generiert die Route von der AKTUELLEN Position neu.
        // Best-effort, fail silent (Trip-Persistierung darf nie das Routing blockieren).
        // 2026-06-10 (vucko Gruppen-Trip): GRUPPEN-Fahrten werden IMMER als
        // Trip persistiert (mehrtaegig weiterfahren, App-Kill/Neustart-fest) —
        // nicht nur bei aktiviertem Trip-Modus.
        if ((_tripModeEnabled || widget.groupId != null) &&
            result.distanceMeters != null &&
            result.distanceMeters! > 0) {
          unawaited(
            _createTripInDb(
              startLat: startPosition.latitude,
              startLng: startPosition.longitude,
              waypoints: waypointSnapshot,
              style: _selectedStyle,
              avoidHighways: _avoidHighways,
              distanceKm: (result.distanceMeters! / 1000),
              durationSeconds: result.durationSeconds?.round() ?? 0,
            ),
          );
        }
      } else {
        _activeDestinationCoordinate = null;
        _activeIntermediateWaypoints = const [];
        _passedWaypointIndices.clear();
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
          waypointOrigin: _isWaypointPlanning ? _roundTripWaypointOrigin : null,
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
          countryPreference: effectiveCountryPreference,
          homeCountryCode: effectiveHomeCountryCode,
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
      // 2026-06-10 (vucko Fehler-Klassifizierung): EIN greppbarer Log pro
      // Fehlschlag mit Typ + Edge-Code + Start-Versatz — vorher war jeder
      // Generierungsfehler nur ein generisches "failed: Exception".
      if (e is RouteServiceException) {
        debugPrint(
          '[CruiseMode][GenFail] mode=${_isRoundTrip ? 'roundtrip' : 'p2p'} '
          'planning=$_planningType type=${e.type.name} '
          'status=${e.statusCode ?? '-'} '
          'code=${e.edgeMeta['response_code'] ?? '-'} '
          'startOffset=${e.edgeMeta['start_offset_meters'] ?? '-'} '
          'debug=${e.debugMessage}',
        );
      } else if (e is TimeoutException) {
        debugPrint(
          '[CruiseMode][GenFail] mode=${_isRoundTrip ? 'roundtrip' : 'p2p'} '
          'planning=$_planningType type=timeout debug=$e',
        );
      } else {
        debugPrint(
          '[CruiseMode][GenFail] mode=${_isRoundTrip ? 'roundtrip' : 'p2p'} '
          'planning=$_planningType type=exception '
          'runtime=${e.runtimeType} debug=$e',
        );
      }
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
      if (!startValidatorRetry && _isStartValidatorReject(e)) {
        final preserveForceAcceptDirectOnce = _forceAcceptDirectOnce;
        debugPrint(
          '[CruiseMode][StartValidatorRetry] start_offset_rejected — '
          'starte genau einen Retry mit frischem getCurrentPosition-Fix',
        );
        Future.microtask(() {
          if (!mounted || _disposed) return;
          if (preserveForceAcceptDirectOnce) {
            _forceAcceptDirectOnce = true;
          }
          _generateRoute(startValidatorRetry: true);
        });
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
              countryPreference: requestedCountryPreference,
              homeCountryCode: requestedHomeCountryCode,
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
            // Last-Chance Pool-Fallback bei `search_session_no_route`: wenn der
            // Pool für (region, bucket, style, avoid_highways) verifizierte
            // Routen kennt, lieber eine bewährte Pool-Route ausspielen als die
            // generische „Wir bereiten Routen vor"-Statusmeldung zu zeigen.
            if (_isRoundTrip &&
                pollError is RouteServiceException &&
                (pollError.edgeMeta['response_code']?.toString() ==
                        'search_session_no_route' ||
                    pollError.edgeMeta['code']?.toString() ==
                        'search_session_no_route')) {
              try {
                final lastChanceStart = await _getStartCoordinates();
                if (_isRouteGenerationCancelled(generationId)) return;
                final lastChance = await _routeService
                    .tryPoolFallbackForFailedRoundTrip(
                      startPosition: lastChanceStart,
                      targetDistanceKm: requestedDistance,
                      mode: _selectedStyle,
                      avoidHighways: _avoidHighways,
                      planningType: _planningType,
                      countryPreference: requestedCountryPreference,
                      homeCountryCode: requestedHomeCountryCode,
                    );
                if (lastChance != null &&
                    !_isRouteGenerationCancelled(generationId)) {
                  _logRoundTripSearchUiDecision(
                    'route_accepted_from_last_chance_pool',
                    sessionId: sessionId,
                    result: lastChance,
                  );
                  await _acceptGeneratedRouteResult(
                    result: lastChance,
                    startPosition: lastChanceStart,
                    distance: requestedDistance,
                    waypointSignature: requestedWaypointSignature,
                  );
                  return;
                }
              } catch (lastChanceError, lastChanceStack) {
                debugPrint(
                  '[CruiseMode] Last-chance pool fallback failed: $lastChanceError',
                );
                debugPrintStack(
                  label: '[CruiseMode] Last-chance pool stacktrace',
                  stackTrace: lastChanceStack,
                );
              }
            }
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
      unawaited(_carRouteBridge.publishFailed(message: errorMessage));
    } finally {
      // Hintergrund-Generierung wieder erlauben
      RouteCacheService.endUserGeneration();
      _stopRouteLoadingUi(generationId: generationId);
      // 2026-05-28 (vucko Task #83): One-Shot-Flag nach jedem Versuch zurücksetzen.
      _forceAcceptDirectOnce = false;
    }
  }

  Future<RouteResult?> _pollRoundTripSearchSession(
    String sessionId, {
    required int generationId,
    CountryPreference countryPreference = CountryPreference.any,
    String? homeCountryCode,
  }) async {
    // 2026-05-25 (vucko): Polling beschleunigt — vorher 30 × 3s = 90s (User
    // hat in Feldkirch/Götzis bis zu mehrere Minuten warten muessen).
    // Neu: progressiv kürzere Polls, max 18 × 2s = 36s. Wenn dann nicht da,
    // fällt RouteService auf Pool-Fallback (`tryPoolFallbackForFailedRoundTrip`).
    const maxPolls = 18;
    DateTime? lastWorkerKickAt;
    for (var poll = 0; poll < maxPolls; poll += 1) {
      if (_isRouteGenerationCancelled(generationId)) return null;
      // Erste 4 Polls sehr schnell (1.5s), danach 2.5s — die meisten Edge-
      // Sessions sind in 3-6s da, längere brauchen Worker-Kick + retry.
      final pollDelay = poll < 4
          ? const Duration(milliseconds: 1500)
          : const Duration(milliseconds: 2500);
      await Future.delayed(pollDelay);
      if (_isRouteGenerationCancelled(generationId)) return null;
      _logRoundTripSearchUiDecision(
        'poll_attempt',
        sessionId: sessionId,
        pollAttempt: poll + 1,
      );
      final result = await _routeService.pollRoundTripSearchSession(
        sessionId,
        countryPreference: countryPreference,
        homeCountryCode: homeCountryCode,
      );
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
              now.difference(lastWorkerKickAt) >= const Duration(seconds: 9))) {
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
    if (kDebugMode) {
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
  }

  bool _shouldKickStaleRoundTripSearchSession(
    Map<String, dynamic>? meta, {
    required int pollIndex,
  }) {
    if (pollIndex < 1 || meta == null) return false;
    final status = meta['search_session_status']?.toString();
    final workerLastSeen = meta['worker_last_seen_at']?.toString().trim();
    final updatedAt = meta['updated_at']?.toString().trim();
    final attemptsRaw = meta['attempts_count'];
    final attempts = attemptsRaw is num
        ? attemptsRaw.toInt()
        : int.tryParse(attemptsRaw?.toString() ?? '') ?? 0;
    final queueRaw = meta['candidate_queue_count'];
    final queueCount = queueRaw is num
        ? queueRaw.toInt()
        : int.tryParse(queueRaw?.toString() ?? '') ?? 0;
    final isWaitingStatus =
        status == 'queued' || status == 'running' || status == 'hydrating';
    if (!isWaitingStatus) return false;
    if (attempts >= math.max(1, queueCount)) return false;
    final lastSeenAt = DateTime.tryParse(
      (workerLastSeen == null || workerLastSeen == 'null')
          ? (updatedAt ?? '')
          : workerLastSeen,
    );
    if (lastSeenAt == null) return true;
    return DateTime.now().difference(lastSeenAt.toLocal()) >=
        const Duration(seconds: 10);
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

  bool _isStartValidatorReject(Object error) {
    if (error is! RouteServiceException) return false;
    final code =
        error.edgeMeta['response_code']?.toString() ??
        error.edgeMeta['code']?.toString();
    return code == 'start_offset_rejected' ||
        code == 'start_offset_uncorrectable';
  }

  Future<void> _acceptGeneratedRouteResult({
    required RouteResult result,
    required geo.Position startPosition,
    required int distance,
    required String? waypointSignature,
  }) async {
    if (!mounted || _disposed) return;
    // 2026-05-31 (vucko): UNIVERSELLER Spike-Cleanup vor der Anzeige — greift
    // für ALLE Quellen (Live, Pool, A→B), nicht nur den Live-Snap-Pfad. So
    // werden Sackgassen-Zacken auch aus Pool-Routen entfernt (User-Report:
    // „manchmal kommt es trotzdem auf"). Off-Road-sicher (40m-Guard im
    // Validator); fällt auf das Original zurück, wenn Cleanup nichts findet.
    final cleanedResult = _cleanRouteForDisplay(result);
    // 2026-06-06 (vucko P9): Die Route MUSS IMMER am User-Standort beginnen —
    // egal ob Live, Pool, A→B oder Wegpunkte. Darum den Access-Leg vom GPS zum
    // Routenstart hier UNBEDINGT erzwingen (vorher nur für Rundkurse → A→B- und
    // Pool-Routen starteten mitten in der Strecke, Puck mittendrin = User-Report).
    // allowDistantAccess nur für POOL/Reserve-Quellen (deren fixer Start kann weit
    // weg liegen); eine LIVE-Route startet ohnehin am User → ist sie „zu weit",
    // soll lieber der bestehende Guard werfen als ein Querfeldein-Connector.
    final routeSource =
        (cleanedResult.edgeMeta['route_source'] ??
                cleanedResult.edgeMeta['source'])
            ?.toString() ??
        '';
    final isPoolSourced =
        routeSource == 'pool' ||
        routeSource == 'route_pool' ||
        routeSource == 'candidate_reserve';
    final prepared = await _prepareRouteForPreviewStart(
      result: cleanedResult,
      startPosition: startPosition,
      isRoundTrip: _isRoundTrip,
      avoidHighways: _avoidHighways,
      forceAccessFromCurrentLocation: true,
      allowDistantAccess: isPoolSourced,
    );

    // 2026-06-12 (vucko): Länder-Gate sitzt im RouteService/Edge-Contract.
    // Die UI zeigt nur noch validierte Ergebnisse; versteckte Filterzustände
    // aus A→B/Wegpunkte werden vor dem Request neutralisiert.

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

    // Defensive Duplikat-Detection: vergleiche das gerade gelieferte Route-
    // Fingerprint mit dem zuletzt gezeigten. Wenn identisch — und der User
    // war auf einem Search-Again-Pfad — triggern wir bis zu 2 automatische
    // Re-Suchen mit forceFreshVariant statt eine "keine neue Variante"-
    // Snackbar zu zeigen. Calimoto-Pattern: die App rotiert selbst weiter.
    final newFingerprint =
        prepared.edgeMeta['route_fingerprint']?.toString() ??
        RouteService.lastRouteDebugFingerprint;
    final isRepeatedRoute =
        newFingerprint != null &&
        newFingerprint.isNotEmpty &&
        _lastDisplayedRouteFingerprint == newFingerprint;
    // Wall-Clock-Window: nach 30s Counter resetten — vermeidet dass ein
    // gestauter Edge-Server endlose Re-Suchen triggert (vucko 2026-05-21).
    final now = DateTime.now();
    if (_searchAgainAutoRetryWindowStart == null ||
        now.difference(_searchAgainAutoRetryWindowStart!) >
            _searchAgainAutoRetryWindow) {
      _searchAgainAutoRetryWindowStart = now;
      _searchAgainAutoRetryCount = 0;
    }
    final canAutoRetry =
        isRepeatedRoute &&
        _lastDisplayedRouteFingerprint != null &&
        _searchAgainAutoRetryCount < _maxSearchAgainAutoRetries;

    if (canAutoRetry && mounted) {
      _searchAgainAutoRetryCount += 1;
      debugPrint(
        '[CruiseMode] Auto-retry $_searchAgainAutoRetryCount/$_maxSearchAgainAutoRetries — same fingerprint, triggering fresh search.',
      );
      // Direkt nochmal `_generateRoute` — die globalen Single-Flight-Locks
      // sorgen dafür, dass das sauber sequenziell läuft. State-Reset macht
      // generateRoute selbst (loading flag etc.).
      Future.microtask(() {
        if (!mounted || _disposed) return;
        _generateRoute();
      });
      return;
    }

    _applyRouteResult(prepared);
    // 2026-05-31 (vucko): Routen-Korridor SOFORT beim Anzeigen vorladen (Zoom
    // 10-17), nicht erst beim Bestätigen. So sind die Straßen-Tiles entlang der
    // Route schon da, wenn der User in der Preview reinzoomt oder offline geht
    // — kein Nachladen mehr im DACH-Raum entlang der geplanten Strecke.
    if (prepared.coordinates.length >= 2) {
      unawaited(
        OfflineMapService.instance.cacheRouteRegion(prepared.coordinates),
      );
    }
    unawaited(
      _carRouteBridge.publishFound(
        result: prepared,
        routeType: _carRouteType,
        style: _selectedStyle,
        avoidHighways: _avoidHighways,
      ),
    );
    _hideRouteSearchStatusForAcceptedRoute();
    _lastGeneratedWasRoundTrip = _isRoundTrip;
    _lastGeneratedSelectedKm = _isRoundTrip ? distance : null;
    _lastGeneratedSelectedStyle = _selectedStyle;
    _lastGeneratedAvoidHighways = _avoidHighways;
    _lastGeneratedWaypointSignature = deliveredWaypoints.isNotEmpty
        ? _roundTripWaypointSignature(deliveredWaypoints)
        : waypointSignature;
    if (newFingerprint != null && newFingerprint.isNotEmpty) {
      _lastDisplayedRouteFingerprint = newFingerprint;
    }
    // Auto-Retry-Counter resetten sobald wir eine echte neue Route zeigen.
    // Nur wenn die aktuelle Route NICHT eine Wiederholung war, sind wir aus
    // dem Retry-Loop raus.
    if (!isRepeatedRoute) {
      _searchAgainAutoRetryCount = 0;
    }

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
        _routeBannerDismissed = false;
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
    if (kDebugMode && result.edgeMeta.isNotEmpty) {
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
    _drivenTrackRecorder.reset();
    _clearAccessLegState();
    // 2026-05-24 (vucko Task #45): Hazard-Check im Hintergrund.
    _hazardCheckDone = false;
    _roadHazards = const [];
    // 2026-05-28 (vucko Task #66): alte Baustellen + Geofence zurücksetzen.
    _routeConstructions = const [];
    _constructionGeofence.clear();
    _activeConstructionAlertId = null;
    unawaited(_checkHazardsInBackground(result.coordinates));
    // 2026-05-24 (vucko Task #49): POIs auto-laden wenn Settings aktiv
    // (Google-Maps-Style: Tankstellen erscheinen automatisch auf der Map).
    _routePois = const [];
    if (PoiSettingsService.instance.anyEnabled) {
      unawaited(_loadPoisFromSettings(result.coordinates));
    }
    // First-Run-Tutorial einmalig zeigen
    if (!PoiSettingsService.instance.tutorialSeen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPoiFirstRunTutorial();
      });
    }
    // Eine neu angezeigte Route ist Preview, keine aktive Navigation. Wenn der
    // User während der Suche Recenter/Follow aktiv hatte, darf die Kamera die
    // Preview nicht weiter festhalten und gegen Pans zurückziehen.
    _cameraAnimController?.stop();
    _lastCameraFrameAt = null;
    setState(() {
      _routeGeoJson = result.geoJson;
      _routeDistance = result.distanceMeters;
      _routeDuration = result.durationSeconds;
      _originalRouteDistance = result.distanceMeters;
      _originalRouteDuration = result.durationSeconds;
      _isRouteConfirmed = false;
      _isCameraLocked = false;
      _fullRouteCoordinates = result.coordinates;
      _remainingRouteCoordinates = result.coordinates;
      // 2026-06-10 (3km-Design v2): Fenster-Caches bei neuer Route leeren —
      // bright faellt auf die volle Route zurueck (nie unsichtbar), dim wird
      // beim naechsten Tick sofort neu gesetzt (dimHead == null).
      _brightAheadLatLngs = const [];
      _dimRemainingLatLngs = const [];
      _lastDimHead = null;
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
      _lastRerouteFailed = false;
      _remainingDistance = null;
      _remainingDuration = null;
      _distanceToFinalTargetMeters = null;
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
      // 2026-05-31 (vucko): KEIN synthetischer GPS→Routenkopf-Strich mehr.
      // Der frühere _pinRouteStartToUser zeichnete eine Luftlinie, die quer
      // durchs Gelände gehen konnte — der User-Wunsch ist aber: die Strecke
      // muss IMMER auf der Straße bleiben. Innerhalb des Korridors (≤70m) ist
      // der optische Versatz minimal; die echte GraphHopper-Geometrie bleibt
      // unverändert. Größere Lücken laufen weiter über die Access-Leg-Logik
      // unten (echter on-road Connector).
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

    final RouteAccessPlan accessPlan;
    try {
      accessPlan = await _routeService.buildAccessRouteToExistingRoute(
        currentPosition: startPosition,
        existingRoute: result,
        mode: _selectedStyle,
        avoidHighways: avoidHighways,
        // 2026-06-06 (vucko P9-Fix): returnToSessionOrigin NUR bei Rundkursen.
        // Seit P9 läuft dieser Block auch für A→B (forceAccessFromCurrentLocation);
        // mit `true` hängte er eine Rück-Leg B→A an → aus A→B wurde ein Loop.
        // Der Navigations-Pfad nutzt ebenfalls returnToSessionOrigin:isRoundTrip.
        returnToSessionOrigin: isRoundTrip,
        rebaseClosedLoop: isRoundTrip,
        // 2026-06-06 (vucko P9): Bei NICHT-Rundkursen (A→B) den Join hart auf den
        // ECHTEN Routenstart (Index 0) pinnen. Sonst wählt chooseJoinPoint den
        // nächstgelegenen On-Route-Punkt → sitzt der User mittig, würde der
        // Routenkopf abgeschnitten und die Strecke begänne mittendrin. Rundkurse
        // behalten die Loop-Rotation (rebaseClosedLoop wählt den besten Einstieg).
        preferredJoinIndex: isRoundTrip ? null : 0,
      );
    } catch (e) {
      // 2026-06-06 (vucko P9-Fix): Schlägt die Access-Leg-Berechnung fehl
      // (z.B. GraphHopper liefert nichts für die Anbindung), die Route TROTZDEM
      // anzeigen (un-rebased) statt sie zu verschlucken — sichtbare Route >
      // gar keine Route. (Die Distanz-Reject-Guard oben wirft weiterhin bewusst.)
      debugPrint(
        '[CruiseMode] Preview-Access-Leg fehlgeschlagen, zeige Route ohne Rebase: $e',
      );
      return result;
    }
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

  void _onDestinationSelected(PlaceSuggestion suggestion) {
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
      return 110;
    }
    if (_activeDetourVariant == 1) {
      return 80;
    }
    return 45;
  }

  /// 2026-06-01 (vucko): Effektiver Off-Route-Korridor — wie Google/Apple werden
  /// GPS-Ungenauigkeit + Tempo eingerechnet. Bei schlechtem GPS (Bergtal/Tunnel,
  /// große accuracy) wird der Korridor erweitert → keine Fehl-Reroutes durch
  /// Drift. Bei höherem Tempo etwas mehr Toleranz (GPS-Lag + Bewegung). Statisch
  /// + pur, damit unit-testbar.
  static double effectiveOffRouteCorridorMeters({
    required double baseCorridor,
    double? accuracyMeters,
    double? speedMps,
  }) {
    final accuracy =
        (accuracyMeters != null &&
            accuracyMeters.isFinite &&
            accuracyMeters > 0)
        ? math.min(accuracyMeters, 30.0)
        : 0.0;
    final speed = (speedMps != null && speedMps.isFinite && speedMps > 0)
        ? speedMps
        : 0.0;
    // 2026-06-12 (vucko Reroute-zu-spaet, Video-Befund): Der Korridor wuchs am
    // Geraet auf ~80-100m (accuracy*0.8 bis 48 + speedBuffer bis 35) — eine
    // Parallelstrasse 40m daneben galt als "on-route", das Banner fror bei 0m
    // ein und der Reroute kam minutenlang nicht. Gestrafft auf Google-Niveau;
    // Fehl-Reroutes verhindert weiterhin die Zeit-Hysterese + das
    // heading-bedingte Vorwaerts-Veto, nicht ein Riesen-Korridor.
    final speedBuffer = speed > 22 ? 10.0 : (speed > 12 ? 6.0 : 0.0);
    return baseCorridor + accuracy * 0.45 + speedBuffer;
  }

  /// 2026-06-12 (vucko): Stimmt der GPS-Kurs grob mit der Routen-Tangente am
  /// Match ueberein? Nur aussagekraeftig bei echter Fahrt (>4 m/s) und
  /// gueltigem Kurs — sonst konservativ true.
  bool _gpsHeadingAlignedWithRoute(
    geo.Position position,
    RouteWindowMatch match,
  ) {
    if (!position.speed.isFinite || position.speed < 4.0) return true;
    if (!position.heading.isFinite || position.heading < 0) return true;
    final coords = _fullRouteCoordinates;
    final i = match.index.clamp(0, coords.length - 2);
    final tangent = _bearingDegrees(
      coords[i][1],
      coords[i][0],
      coords[i + 1][1],
      coords[i + 1][0],
    );
    var delta = (position.heading - tangent).abs() % 360.0;
    if (delta > 180.0) delta = 360.0 - delta;
    return delta <= 55.0;
  }

  /// 2026-06-13 (vucko Google/Apple-Bar-Review F4/G6): KLAR gegenläufiger Kurs
  /// (>72°) — strenger als das 55°-Korridor-Veto, damit ein verpasster Abbieger
  /// schnell erkannt wird, ABER eine enge (Sport-Mode-)Kurve nicht fälschlich
  /// als Verfahren zählt. Wird mit [_routeHasSharpTurnNear] kombiniert.
  bool _gpsHeadingClearlyOpposed(
    geo.Position position,
    RouteWindowMatch match,
  ) {
    if (!position.speed.isFinite || position.speed < 4.0) return false;
    if (!position.heading.isFinite || position.heading < 0) return false;
    final coords = _fullRouteCoordinates;
    if (coords.length < 2) return false;
    final i = match.index.clamp(0, coords.length - 2);
    final tangent = _bearingDegrees(
      coords[i][1],
      coords[i][0],
      coords[i + 1][1],
      coords[i + 1][0],
    );
    var delta = (position.heading - tangent).abs() % 360.0;
    if (delta > 180.0) delta = 360.0 - delta;
    return delta > 72.0;
  }

  /// 2026-06-13 (vucko G6, Alpen-Haarnadel-Schutz): Liegt innerhalb der
  /// nächsten [aheadMeters] auf der Route eine scharfe Richtungsänderung
  /// (kumulierter Bearing-Wechsel > [turnDeg])? Dann ist ein momentan
  /// gegenläufiger GPS-Kurs Kurvenfahrt, kein Verfahren — Schnell-Reroute
  /// unterdrücken (die 3s-Spatial-Hysterese greift weiterhin, falls doch echt).
  bool _routeHasSharpTurnNear(
    int index, {
    double aheadMeters = 35.0,
    double turnDeg = 50.0,
  }) {
    final coords = _fullRouteCoordinates;
    if (coords.length < 3) return false;
    final start = index.clamp(0, coords.length - 2);
    var acc = 0.0;
    double? prevBearing;
    var cumTurn = 0.0;
    for (var i = start; i < coords.length - 1 && acc < aheadMeters; i++) {
      final seg = geo.Geolocator.distanceBetween(
        coords[i][1],
        coords[i][0],
        coords[i + 1][1],
        coords[i + 1][0],
      );
      acc += seg;
      final b = _bearingDegrees(
        coords[i][1],
        coords[i][0],
        coords[i + 1][1],
        coords[i + 1][0],
      );
      if (prevBearing != null) {
        var d = (b - prevBearing).abs() % 360.0;
        if (d > 180.0) d = 360.0 - d;
        cumTurn += d;
        if (cumTurn > turnDeg) return true;
      }
      prevBearing = b;
    }
    return false;
  }

  static double _bearingDegrees(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final phi1 = lat1 * math.pi / 180.0;
    final phi2 = lat2 * math.pi / 180.0;
    final dLng = (lng2 - lng1) * math.pi / 180.0;
    final y = math.sin(dLng) * math.cos(phi2);
    final x =
        math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(dLng);
    return (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
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
      // 2026-06-15 (vucko N1): Eine wiederaufgenommene Fahrt ist per Definition
      // hinter dem Fahrt-Start → sofort als eingerastet behandeln, damit die
      // Kaltstart-Reroute-Sperre nicht erneut greift.
      _routeLockedOn = snapshot.navigationStartTime != null;
      _onRouteLockStreak = _routeLockedOn ? _lockOnStreakNeeded : 0;
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

    // 2026-05-28 (vucko Task #84): Wenn eine zuvor berechnete Route noch
    // sichtbar ist (Preview-Karte „Route berechnet"), war der gescheiterte
    // Versuch nur eine ZUSÄTZLICHE Variantensuche („Nochmal suchen"). Dann
    // NIE mit dem blockierenden „Route noch nicht verfügbar"-Dialog
    // unterbrechen — das war der False-Positive aus dem Startup-V-Test
    // (Popup erschien über gültiger „24.6 km · Perfekt"-Karte). Diese Prüfung
    // MUSS vor den Warmup-/Notice-Checks stehen, sonst greift der
    // Warmup-Dialog (route_quality_too_low etc.) trotz sichtbarer Route.
    if (_snapshotHasVisibleRoute(previousUiState)) {
      debugPrint(
        '[CruiseMode] Route attempt failed but previous route stayed visible: '
        '$message${error == null ? "" : " ($error)"}',
      );
      // Höchstens eine sanfte, selbst-schließende Notice — kein Dialog.
      if (_isWaypointRouteError(error)) {
        _showWaypointRouteStatusNotice(error as RouteServiceException);
      } else if (_isExpectedRoundTripRoutingStatus(error)) {
        // 2026-06-02 (vucko): Eine Route IST sichtbar — der gescheiterte Versuch
        // war nur eine Zusatzsuche. NIE „Keine passende Route gefunden / keine
        // sichere Route" zeigen (das war die Kontradiktion im Screenshot: Banner
        // über gültiger 47,4km-Route). Stattdessen neutrale Kopie.
        _showRoundTripRouteStatusNotice(
          error as RouteServiceException,
          routeAlreadyVisible: true,
        );
      }
      return;
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

  void _showRoundTripRouteStatusNotice(
    RouteServiceException error, {
    bool routeAlreadyVisible = false,
  }) {
    if (!mounted || _disposed) return;
    final code =
        error.edgeMeta['response_code']?.toString() ??
        error.edgeMeta['code']?.toString();
    final healingQueued = _routeSearchHealingQueued(error);
    // 2026-06-02 (vucko): Ist schon eine Route sichtbar, war dies nur eine
    // ZUSATZsuche → niemals als Fehler framen („keine Route"). Neutrale,
    // selbst-schließende Kopie, die NICHT der angezeigten Strecke widerspricht.
    if (routeAlreadyVisible) {
      _routeSearchExitTimer?.cancel();
      _safeSetState(() {
        _routeSearchProgress = 1.0;
        _routeSearchStatusLeaving = false;
        _routeSearchDismissScheduled = false;
        _routeSearchNoticeTitle = 'Aktuelle Strecke bleibt';
        _routeSearchNoticeMessage = healingQueued
            ? 'Wir bereiten im Hintergrund neue Vorschläge vor.'
            : 'Keine neue Variante gefunden — deine Route passt.';
      });
      _scheduleRouteSearchStatusDismiss(
        hold: const Duration(milliseconds: 1800),
      );
      return;
    }
    final title = healingQueued
        ? 'Wir bereiten bessere Routen vor'
        : code == 'search_in_progress'
        ? 'Alternativen werden geprüft'
        : 'Keine passende Route gefunden';
    final message = healingQueued
        ? 'Wir bereiten automatisch neue Vorschläge für diese Einstellung vor.'
        : switch (code) {
            'search_in_progress' =>
              'Wir prüfen weitere Varianten und verfeinern die Strecke.',
            'search_session_timeout' =>
              'Die Suche läuft weiter. Beim nächsten Versuch prüfen wir neue Vorschläge.',
            'search_session_no_route' =>
              'Gerade war keine sichere Route dabei.',
            'route_quality_too_low' =>
              'Die gefundenen Varianten waren noch nicht sauber genug.',
            _ => 'Gerade war keine sichere Route dabei.',
          };
    _routeSearchExitTimer?.cancel();
    _safeSetState(() {
      _routeSearchProgress = math.min(_routeSearchProgress, 0.92);
      _routeSearchStatusLeaving = false;
      _routeSearchDismissScheduled = false;
      _routeSearchNoticeTitle = title;
      _routeSearchNoticeMessage = message;
    });
    _scheduleRouteSearchStatusDismiss(hold: const Duration(milliseconds: 2400));
  }

  bool _routeSearchHealingQueued(RouteServiceException error) {
    final meta = error.edgeMeta;
    final code =
        meta['response_code']?.toString().toLowerCase() ??
        meta['code']?.toString().toLowerCase();
    final healingStatus = meta['healing_status']?.toString().toLowerCase();
    final seedJobStatus = meta['seed_job_status']?.toString().toLowerCase();
    return meta['background_learning_queued'] == true ||
        meta['seed_job_queued'] == true ||
        meta['seed_job_created'] == true ||
        meta['healing_job_created'] == true ||
        code == 'pool_bootstrap_pending' ||
        code == 'search_session_timeout' ||
        healingStatus == 'healing_queued' ||
        healingStatus == 'healing_running' ||
        healingStatus == 'healing_failed_cooldown' ||
        seedJobStatus == 'queued' ||
        seedJobStatus == 'running' ||
        seedJobStatus == 'cooldown';
  }

  void _showWaypointRouteStatusNotice(RouteServiceException error) {
    if (!mounted || _disposed) return;
    final code =
        error.edgeMeta['response_code']?.toString() ??
        error.edgeMeta['code']?.toString();
    // 2026-05-23 (vucko Bug-Fix): too_many_waypoints muss das AKTUELLE
    // Limit kennen (3 Standard, 5 Trip-Modus). Vorher fest "drei" verdrahtet,
    // was im Trip-Modus mit 5 Stopps fälschlich getriggert wurde.
    final tooManyMsg = _tripModeEnabled
        ? 'Im Trip-Modus max $_currentMaxWaypoints Stopps. Entferne einen Stopp und versuche es erneut.'
        : 'Standard erlaubt max $_currentMaxWaypoints Stopps. Tippe oben auf "Trip-Modus" für bis zu 5 Stopps.';
    final message = switch (code) {
      'waypoint_too_far' =>
        'Wir konnten die Stopps noch nicht sauber an Straßen anbinden. Setze einen Stopp näher an eine Straße oder lass neue Stopps vorschlagen.',
      'waypoint_duplicate_or_too_close' =>
        'Zwei Stopps liegen zu nah beieinander. Verschiebe einen Punkt oder entferne ihn.',
      'too_few_waypoints' =>
        'Setze mindestens einen Stopp oder lass passende Stopps vorschlagen.',
      'too_many_waypoints' => tooManyMsg,
      _ =>
        'Diese Stopps ergeben gerade keine sichere Strecke. Bearbeite sie auf der Karte oder lass neue Stopps vorschlagen.',
    };
    _routeSearchExitTimer?.cancel();
    _safeSetState(() {
      _configCollapsed = true;
      _routeSearchProgress = math.min(_routeSearchProgress, 0.92);
      _routeSearchStatusLeaving = false;
      _routeSearchDismissScheduled = false;
      _routeSearchNoticeTitle = 'Stopps prüfen';
      _routeSearchNoticeMessage = message;
    });
    _scheduleRouteSearchStatusDismiss(hold: const Duration(milliseconds: 2600));
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
        // 2026-05-28 (vucko Task #83): "Direkte Route nehmen" erzwingt einmalig
        // eine direkte Route ohne Quality-Reject statt nur dieselbe Suche zu wiederholen.
        _forceAcceptDirectOnce = true;
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
    _driveSessionRecordedForCompletion = false;
    _drivenTrackRecorder.reset();
    _safeSetState(() {
      _isLoading = false;
      _routeLoadingPhaseIndex = 0;
      _routeSearchProgress = 0.08;
      _activeRouteGenerationSerial = null;
      _routeGenerationCancelled = false;
      _routeSearchNoticeTitle = null;
      _routeSearchNoticeMessage = null;
      _lastRerouteFailed = false;
      _routeGeoJson = null;
      _routeDistance = null;
      _routeDuration = null;
      _routeLatLngs = [];
      _fullRouteCoordinates = [];
      _remainingRouteCoordinates = [];
      _drivenTrailLatLngs = const [];
      _lastDrivenHead = null;
      _activeIntermediateWaypoints = const [];
      _passedWaypointIndices.clear();
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
      _distanceToFinalTargetMeters = null;
      _sessionRouteStartIndexInActiveRoute = 0;
      _navigationStartTime = null;
      _offRouteCount = 0;
      _lastRerouteTime = null;
      _lastRerouteFailed = false;
      _isRerouting = false;
      _originalRouteDistance = null;
      _originalRouteDuration = null;
      _totalDistanceDriven = 0.0;
      _drivenTrackRecorder.reset();
      _isCameraLocked = false;
      _configCollapsed = false;
    });
    // 2026-06-02 (vucko Sync): Bewertung am Handy fertig → Auto-Session leeren.
    // CarPlay liest den geleerten Snapshot → schließt seinen Abschluss-Screen
    // automatisch (beidseitige Sync). publishEnded (status=ended) hätte CarPlay
    // dagegen am Abschluss-Screen hängen lassen.
    _completionSheetOpen = false;
    unawaited(_carRouteBridge.clearCarSession());
  }

  void _saveActiveTripForLater() {
    _returnToCruiseSetupFromActiveRoute();
  }

  Future<void> _confirmCancelActiveTripFromMap() async {
    if (!mounted || _disposed || _isLoading) return;
    final tripId = _activeTripId;
    if (tripId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text(
          'Tour abbrechen?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Die Tour wird beendet und aus dem Fortsetzen-Bereich entfernt. Deine gefahrenen Strecken bleiben unverändert.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Zurück',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Abbrechen',
              style: TextStyle(
                color: Color(0xFFFF6B61),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _disposed) return;

    _activeTripId = null;
    try {
      await TripService.instance.cancelTrip(tripId);
      if (!mounted || _disposed) return;
      _returnToCruiseSetupFromActiveRoute();
      TopToast.show(
        context,
        message: 'Tour abgebrochen',
        icon: Icons.close_rounded,
        duration: const Duration(milliseconds: 2600),
      );
    } catch (e) {
      debugPrint('[CruiseMode] Trip cancel fail: $e');
      if (!mounted || _disposed) return;
      _activeTripId = tripId;
      TopToast.show(
        context,
        message: 'Tour konnte nicht abgebrochen werden',
        icon: Icons.error_outline_rounded,
        isError: true,
      );
    }
  }

  void _returnToCruiseSetupFromActiveRoute() {
    if (!mounted || _disposed) return;
    final tripIdToPause = _activeTripId;
    if (tripIdToPause != null) {
      _activeTripId = null;
    }
    _dismissTransientRouteUi();
    _stopSimulation(restartLiveTracking: false);
    _stopNavigationTracking();
    CruiseModePage.isFullscreen.value = false;
    // 2026-05-27 (vucko UX): Cancel = User will diese Route NICHT weiter.
    // Cache leeren damit beim nächsten App-Start die Map sauber kommt.
    unawaited(RouteCacheService.instance.clearConfirmedRoute());
    _resetGeneratedRouteUiState();

    final currentLocation = _userLocation;
    if (currentLocation != null) {
      _setCameraToPosition(currentLocation);
    } else {
      unawaited(_initializeMapLocation());
    }
    if (tripIdToPause != null) {
      unawaited(() async {
        await _safePauseTrip(tripIdToPause);
        if (!mounted || _disposed) return;
        TopToast.show(
          context,
          message: 'Tour zwischengespeichert — auf Home fortsetzen',
          icon: Icons.archive_outlined,
          duration: const Duration(milliseconds: 3000),
        );
      }());
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

    // 2026-06-09 (vucko Voll-Route-Sichtbar): die sichtbare aktive Linie ist ab
    // jetzt die VOLLE Route (statisch) — der graue Driven-Trail frisst sie hinter
    // dem Puck auf. _remainingRouteCoordinates bleibt die volle Reststrecke (für
    // Restdistanz/Auto). Driven-Trail für die frische Fahrt zurücksetzen.
    _lastDrivenHead = null;
    _drivenTrailLatLngs = const [];
    _safeSetState(() {
      _remainingRouteCoordinates = _fullRouteCoordinates.sublist(
        _currentRouteIndex,
        _fullRouteCoordinates.length,
      );
    });
    await _drawRoute({
      'type': 'LineString',
      'coordinates': _fullRouteCoordinates,
    }, animateCamera: false);
    final activeResult = _lastRouteResult;
    if (activeResult != null) {
      unawaited(
        _carRouteBridge.publishNavigationStarted(
          result: activeResult,
          routeType: _carRouteType,
          style: _selectedStyle,
          avoidHighways: _avoidHighways,
          remainingDistanceMeters: _remainingDistance ?? _routeDistance,
          remainingDurationSeconds: _remainingDuration ?? _routeDuration,
          nextManeuverText: _currentCarManeuverText(),
          nextManeuverDistance: _calculateDistanceToManeuver(),
          nextManeuverKind: _currentCarManeuverKind(),
        ),
      );
    }
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
        avoidHighways: _effectiveNavigationAvoidHighways,
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
          publishToGroup: false,
        );
        _safeSetState(() {
          _clearAccessLegState();
          _sessionRouteStartIndexInActiveRoute = 0;
          _totalDistanceDriven = 0.0;
          _drivenTrackRecorder.reset();
        });
      }
      return;
    }

    await _commitRerouteResult(
      result: accessPlan.activeRoute,
      sessionRouteResult: accessPlan.activeRoute,
      position: position,
      publishToGroup: false,
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
      _drivenTrackRecorder.reset();
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

  // 2026-05-31 (vucko): Entfernt Dead-End-Spikes aus der anzuzeigenden Route
  // (alle Quellen). Off-Road-sicher über den 40m-Guard im Validator. Manöver
  // werden auf den nächstgelegenen bereinigten Koordinaten-Index neu gemappt,
  // damit Turn-by-Turn konsistent bleibt; Speed-Limits werden verworfen, wenn
  // sich die Punktzahl ändert (sie werden ohnehin nur grob indexiert genutzt).
  RouteResult _cleanRouteForDisplay(RouteResult result) {
    if (result.coordinates.length < 8) return result;
    final cleaned = RouteQualityValidator.cleanRouteArtifacts(
      result.coordinates,
    );
    if (cleaned.length == result.coordinates.length) return result; // nichts
    final geometry = <String, dynamic>{
      'type': 'LineString',
      'coordinates': cleaned,
    };
    // Manöver auf nächsten bereinigten Index neu mappen.
    final remappedManeuvers = <RouteManeuver>[];
    for (final m in result.maneuvers) {
      var bestIdx = 0;
      var bestDist = double.infinity;
      for (var i = 0; i < cleaned.length; i++) {
        final d = geo.Geolocator.distanceBetween(
          m.latitude,
          m.longitude,
          cleaned[i][1],
          cleaned[i][0],
        );
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        }
      }
      // Manöver, das näher als 25m an einem bereinigten Punkt liegt, behalten
      // (alles andere lag im entfernten Spike → wegfallen lassen).
      if (bestDist <= 25.0) {
        remappedManeuvers.add(
          RouteManeuver(
            latitude: m.latitude,
            longitude: m.longitude,
            routeIndex: bestIdx,
            icon: m.icon,
            announcement: m.announcement,
            instruction: m.instruction,
            maneuverType: m.maneuverType,
            roundaboutExitNumber: m.roundaboutExitNumber,
            roundaboutTurnAngleRad: m.roundaboutTurnAngleRad,
          ),
        );
      }
    }
    final cleanedDistanceMeters = _calculatePolylineDistanceMeters(cleaned);
    return RouteResult(
      geoJson: json.encode(geometry),
      geometry: geometry,
      coordinates: cleaned,
      maneuvers: remappedManeuvers.isEmpty
          ? result.maneuvers
          : remappedManeuvers,
      distanceMeters: cleanedDistanceMeters > 0
          ? cleanedDistanceMeters
          : result.distanceMeters,
      durationSeconds: result.durationSeconds,
      distanceKm: cleanedDistanceMeters > 0
          ? cleanedDistanceMeters / 1000
          : result.distanceKm,
      speedLimits: const [],
      edgeMeta: {...result.edgeMeta, 'spike_cleanup_applied': true},
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

  bool get _effectiveNavigationAvoidHighways {
    return _activeAvoidHighways ||
        _avoidHighways ||
        _routeMetaRequestsNoHighway(_lastRouteResult?.edgeMeta) ||
        _routeMetaRequestsNoHighway(_sessionRouteResult?.edgeMeta);
  }

  bool _routeMetaRequestsNoHighway(Map<String, dynamic>? meta) {
    if (meta == null || meta.isEmpty) return false;
    if (meta['avoid_highways_requested'] == true ||
        meta['avoid_highways'] == true) {
      return true;
    }
    final policy = meta['motorway_policy']?.toString().toLowerCase();
    return policy == 'exclude_motorway';
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

  // ─────────────── Reroute-Fehlerklassifizierung (2026-06-10, vucko) ────────
  // Vorher mündete JEDER Reroute-Fehler in derselben generischen Meldung —
  // unmöglich zu diagnostizieren, ob Edge-Fehler, Timeout, Validator-Reject
  // oder Start-Versatz (Server-Snap-Bug). Jede Fehlstelle im Zyklus meldet
  // jetzt eine Ursache; die letzte Meldung an den User ist ursachen-spezifisch.

  /// Maximal akzeptierter Abstand zwischen aktuellem GPS-Fix und erstem Punkt
  /// eines Reroute-Connectors. Während der Fahrt ist der User AUF einer Straße
  /// — legitimes Snapping liegt unter ~100 m (Edge nutzt start_radius_m=65).
  static const double _rerouteMaxStartOffsetMeters = 250.0;

  String _classifyRerouteError(Object e) {
    if (e is TimeoutException) return 'timeout';
    if (e is RouteServiceException) {
      final code = e.edgeMeta['response_code']?.toString();
      if (code == 'start_offset_rejected' ||
          code == 'start_offset_uncorrectable') {
        final meters = e.edgeMeta['start_offset_meters'];
        return 'start_offset(${meters ?? '?'}m)';
      }
      switch (e.type) {
        case RouteErrorType.network:
          return 'network';
        case RouteErrorType.server:
        case RouteErrorType.rateLimit:
        case RouteErrorType.workerLimit:
        case RouteErrorType.auth:
          return 'edge_error(${e.type.name}/${e.statusCode ?? '-'})';
        case RouteErrorType.quality:
          return 'validator_reject(${e.debugMessage})';
        case RouteErrorType.noRoute:
        case RouteErrorType.emptyResponse:
          return 'no_route(${e.type.name})';
        default:
          return 'edge_error(${e.type.name})';
      }
    }
    return 'exception(${e.runtimeType})';
  }

  String _rerouteFailureUserMessage(List<String> causes) {
    if (causes.any((c) => c.startsWith('start_offset'))) {
      return 'Reroute verworfen: Server-Route startete zu weit entfernt — folge der Linie, nächster Versuch kommt automatisch';
    }
    final last = causes.isNotEmpty ? causes.last : '';
    if (last.startsWith('timeout') || last.startsWith('network')) {
      return 'Reroute gerade nicht möglich (Netz/Server) — folge der Linie, nächster Versuch kommt automatisch';
    }
    if (last.startsWith('edge_error')) {
      return 'Reroute-Server meldet einen Fehler — folge der Linie, nächster Versuch kommt automatisch';
    }
    if (last.startsWith('no_route') || last == 'no_candidate') {
      return 'Keine Anschlussroute gefunden — folge der Linie, wende erst bei sicherer Möglichkeit';
    }
    return 'Keine sichere Reroute — folge der Linie, wende erst bei sicherer Möglichkeit';
  }

  void _publishRerouteFailure({
    required String rerouteReason,
    required String rerouteMode,
    required double? remainingDistanceBeforeMeters,
    required double? etaBeforeSeconds,
    double? rerouteDistanceMeters,
    double? rejoinPointDistanceMeters,
    String? userMessage,
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
    // Fehlgeschlagene Reroutes sollen nicht spammen, aber auch nicht 12s lang
    // eine alte aktive Linie stehen lassen. Der Off-Route-Loop nutzt dafuer den
    // kurzen Failure-Cooldown.
    _lastRerouteTime = DateTime.now();
    _lastRerouteFailed =
        true; // 2026-06-06 (vucko P6): Meldung NUR oben (TopToast), nicht mehr als orange
    // SnackBar unten. P7 deckelt automatisch auf ≤5s + Swipe-to-dismiss.
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      TopToast.show(
        context,
        message:
            userMessage ??
            'Keine sichere Reroute — folge der Linie, wende erst bei sicherer Möglichkeit',
        icon: Icons.warning_amber_rounded,
        isError: true,
        duration: const Duration(milliseconds: 4000),
      );
    }
  }

  Future<bool> _hasConnectivityForReroute() async {
    if (kIsWeb) return true;
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((result) => result != ConnectivityResult.none);
    } catch (error) {
      debugPrint(
        '[CruiseMode] Connectivity-Check fuer Reroute fehlgeschlagen: $error',
      );
      return true;
    }
  }

  void _publishOfflineRerouteFallback({
    required double? remainingDistanceBeforeMeters,
    required double? etaBeforeSeconds,
  }) {
    final meta = buildRerouteTelemetry(
      rerouteReason: 'offline',
      rerouteMode: 'saved_route_rejoin',
      remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
      remainingDistanceAfterMeters: remainingDistanceBeforeMeters,
      etaBeforeSeconds: etaBeforeSeconds,
      etaAfterSeconds: etaBeforeSeconds,
      rerouteFailed: true,
    );
    _markCurrentRouteWithRerouteMeta(meta);
    _logRerouteMeta(meta);
    _lastRerouteTime = DateTime.now();
    _lastRerouteFailed =
        true; // 2026-06-06 (vucko P6): oben statt orange Bottom-SnackBar.
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      TopToast.show(
        context,
        message: 'Offline — gespeicherte Route bleibt sichtbar',
        icon: Icons.cloud_off_rounded,
        isError: true,
        duration: const Duration(milliseconds: 4000),
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
    bool publishToGroup = true,
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

    // 2026-06-13 (vucko Reroute-Videos): Beim Commit zaehlt die JETZT-Position
    // (Smoother-Prediction), nicht die bis zu mehrere Sekunden alte Request-
    // Position — fuer Wenden-Check, Re-Anchor und den Stale-Check unten.
    final commitPos = _freshRerouteStartPosition(position, lead: Duration.zero);

    // 2026-06-13 (vucko Google/Apple-Bar-Review G4): Liefert GraphHopper (dank
    // des headings-Fixes) bereits ein echtes WENDEN-Manöver als erste
    // Instruktion, übernimmt das normale Banner+Voice-Flow die Ansage nativ
    // (U-Turn-Icon + Distanz-Eskalation wie Google). Der synthetische Override
    // ist dann überflüssig und würde nur doppelt sprechen — nur als FALLBACK
    // feuern, wenn GH KEIN führendes Wenden-Manöver hat.
    final firstManeuverIsUTurn =
        result.maneuvers.isNotEmpty &&
        result.maneuvers.first.routeIndex <= 2 &&
        (result.maneuvers.first.icon == Icons.u_turn_left ||
            result.maneuvers.first.icon == Icons.u_turn_right);

    // 2026-06-12 (vucko Video: "sagt rechts, meint wenden"): Startet die neue
    // Route >120 Grad GEGEN die aktuelle Fahrtrichtung, faehrt der User von
    // ihr weg — die erste regulaere Instruktion ("rechts abbiegen") waere
    // irrefuehrend. Dann zuerst EXPLIZIT zum Wenden auffordern.
    // 2026-06-13 (G5/F5-Review): Schwelle 135→120° (Industriestandard, fängt
    // Wenden-Fälle 2-3s früher).
    final c = result.coordinates;
    if (!firstManeuverIsUTurn &&
        c.length >= 2 &&
        commitPos.speed.isFinite &&
        commitPos.speed > 3.0 &&
        commitPos.heading.isFinite &&
        commitPos.heading >= 0) {
      var probeIdx = 1;
      var acc = 0.0;
      while (probeIdx < c.length - 1 && acc < 25.0) {
        acc += geo.Geolocator.distanceBetween(
          c[probeIdx - 1][1],
          c[probeIdx - 1][0],
          c[probeIdx][1],
          c[probeIdx][0],
        );
        probeIdx++;
      }
      final routeStartBearing = _bearingDegrees(
        c[0][1],
        c[0][0],
        c[probeIdx][1],
        c[probeIdx][0],
      );
      var delta = (commitPos.heading - routeStartBearing).abs() % 360.0;
      if (delta > 180.0) delta = 360.0 - delta;
      if (delta > 120.0) {
        _speakManeuverAnnouncement(
          0,
          important: true,
          interrupt: true,
          overrideText: 'Bitte wenden, sobald es möglich ist.',
        );
      }
    }

    _safeSetState(() {
      _routeGeoJson = result.geoJson;
      _routeDistance = result.distanceMeters;
      _routeDuration = result.durationSeconds;
      _originalRouteDistance = result.distanceMeters;
      _originalRouteDuration = result.durationSeconds;
      _fullRouteCoordinates = result.coordinates;
      _remainingRouteCoordinates = result.coordinates;
      // 2026-06-10 (3km-Design v2): Fenster-Caches bei neuer Route leeren —
      // bright faellt auf die volle Route zurueck (nie unsichtbar), dim wird
      // beim naechsten Tick sofort neu gesetzt (dimHead == null).
      _brightAheadLatLngs = const [];
      _dimRemainingLatLngs = const [];
      _lastDimHead = null;
      _currentRouteIndex = 0;
      _lastDrawnRouteIndex = 0;
      _distanceSinceLastRedraw = 0.0;
      _maneuvers = result.maneuvers;
      _activeManeuverIndex = 0;
      _announcedManeuverIndices.clear();
      // 2026-06-05 (vucko Task #6): Haptic-Stage-Flags + letzten Manöver-Index
      // mit zurücksetzen. Sonst hat das 1. Manöver der NEUEN Route denselben
      // Index 0 wie das alte → der Reset im Location-Update greift nicht → Flags
      // bleiben true → die erste Ansage der neuen Route wird verschluckt.
      _hapticStage300m = false;
      _hapticStage150m = false;
      _hapticStage50m = false;
      _lastHapticManeuverIndex = null;
      _offRouteCount = 0;
      _consecutiveOffRouteFixes = 0;
      // 2026-06-16 (vucko O4): Lock-On-Grace nach Reroute neu starten — der Puck
      // muss sich erst wieder sauber auf die NEUE Route einrasten, bevor schnelle
      // Off-Route-Votes wieder greifen. Bricht die Reroute-Kaskade, wenn der
      // frische Routen-Abschnitt minimal neben der Fahrbahn liegt (snap-first).
      _routeLockedOn = false;
      _onRouteLockStreak = 0;
      _postRerouteGraceUntil = DateTime.now().add(const Duration(seconds: 6));
      // 2026-06-08 (vucko Task #47): Access-Leg-State MUSS beim Reroute-Commit
      // zurück. _fullRouteCoordinates wird komplett durch neue (kürzere) Geometrie
      // ersetzt — ein alter _accessLegJoinIndex zeigt dann in den ALTEN Array
      // (out-of-bounds/falsches Segment) und _isAccessLegActive=true bläht den
      // Off-Route-Korridor auf 85m → der globale Re-Snap ankert auf dem FALSCHEN
      // Ast eines sich selbst überlappenden Rundkurses → Selbstüberschneidung.
      // Der legitime Access-Leg-Reroute-Pfad setzt die Flags NACH dem await
      // wieder, daher hier gefahrlos (inline statt _clearAccessLegState(), damit
      // es Teil dieser setState-Transaktion ist).
      _isAccessLegActive = false;
      _accessLegJoinIndex = null;
      _accessLegMainRouteResult = null;
      _lastRerouteTime = DateTime.now();
      _lastRerouteFailed = false;
      _offRouteGapMeters = 0.0;
      // 2026-06-15 (vucko N1, Verify-Hygiene): Overshoot-Tracker auf der frisch
      // gebauten Route zurücksetzen — der alte „min<35 gesehen"-Latch zeigt sonst
      // auf ein Manöver, das es in der neuen Geometrie nicht mehr gibt.
      _overshootManeuverIndex = null;
      _overshootMinDistM = double.infinity;
      _remainingDistance = result.distanceMeters;
      _remainingDuration = result.durationSeconds;
      _distanceToFinalTargetMeters = null;
    });

    GamificationService.countCurvesAsync(result.coordinates).then((count) {
      if (mounted) {
        setState(() => _cachedCurveCount = count);
      }
    });

    // 2026-06-08 (vucko Task #47): Auf der NEUEN Geometrie re-matchen statt blind
    // ab 0 zu slicen. Index 0 ist zwar der Connector-Start (= GPS), aber falls
    // der Puck schon ein paar Punkte weiter ist oder die Naht minimal driftet,
    // darf das Puck-Fenster NICHT über eine Naht hinweg slicen. Kleines Fenster
    // ab 0 (Puck ist frisch am Connector-Start) → ein evtl. Self-Overlap trifft
    // nicht den falschen Ast.
    final reanchor = findNearestInWindow(
      position: commitPos,
      coordinates: result.coordinates,
      currentIndex: 0,
      windowSize: math.min(120, result.coordinates.length),
      maxJumpMeters: double.infinity,
    );
    if (reanchor.distanceMeters <= _headSnapMaxMeters) {
      _currentRouteIndex = reanchor.index.clamp(
        0,
        math.max(0, result.coordinates.length - 1),
      );
    }
    // 2026-06-13 (vucko Reroute-Videos): Stale-Commit-Check. Ist der Fahrer
    // beim Commit schon >80m von der NEUEN Route entfernt (Edge-Latenz bei
    // schneller Fahrt / Fahrer ist abgebogen), waere die Route sofort wieder
    // off-route → Ketten-Reroute mit frischer Position anstossen (Flag wird
    // im finally von _rerouteToOriginalRoute verarbeitet).
    if (reanchor.distanceMeters.isFinite && reanchor.distanceMeters > 80.0) {
      _pendingChainedReroute = true;
      debugPrint(
        '[CruiseMode][Reroute] Stale-Commit: Fahrer '
        '${reanchor.distanceMeters.toStringAsFixed(0)}m neben neuer Route',
      );
    } else {
      _chainedRerouteCount = 0;
    }
    // 2026-06-09 (vucko Voll-Route-Sichtbar): volle Reststrecke (Puck→Ende) für
    // Restdistanz/Auto; SICHTBAR wird die VOLLE neue Route gezeichnet (statisch),
    // der zurückgesetzte graue Driven-Trail frisst sie wieder hinter dem Puck auf.
    final remaining = result.coordinates.sublist(
      _currentRouteIndex.clamp(0, math.max(0, result.coordinates.length - 1)),
      result.coordinates.length,
    );
    if (remaining.isNotEmpty) {
      final first = remaining.first;
      final distanceToFirst = geo.Geolocator.distanceBetween(
        commitPos.latitude,
        commitPos.longitude,
        first[1],
        first[0],
      );
      // 2026-06-01 (vucko): Kopf nur an GPS heften, wenn das Fahrzeug WIRKLICH
      // auf der Linie ist (≤18m). Bei GPS-Drift (Bergtal) sonst Off-Route-Zacken.
      if (distanceToFirst <= _headSnapMaxMeters) {
        remaining[0] = [position.longitude, position.latitude];
      }
    }
    _remainingRouteCoordinates = remaining;
    _routeGeoJson = json.encode({
      'type': 'LineString',
      'coordinates': result.coordinates,
    });
    _lastDrivenHead = null;
    _drivenTrailLatLngs = const [];
    await _drawRoute({
      'type': 'LineString',
      'coordinates': result.coordinates,
    }, animateCamera: false);
    // 2026-06-06 (vucko P2/P4): Reroute-Banner-Flag zurücksetzen (nächster Off-
    // Route-Zyklus darf wieder genau EIN Banner zeigen) + die GRAUE Vorschau-/
    // Hintergrundroute deterministisch neu zeichnen (gleicher Signatur-
    // Fingerprint bei Rundkurs-Reroute hätte sie sonst stehen lassen).    _mlController?.forceResyncLines();
    unawaited(
      RouteCacheService.instance.storeConfirmedRoute(
        route: result,
        isRoundTrip: _isRoundTrip,
        style: _selectedStyle,
        avoidHighways: _effectiveNavigationAvoidHighways,
        groupId: widget.groupId,
      ),
    );
    unawaited(OfflineMapService.instance.cacheRouteRegion(result.coordinates));
    if (publishToGroup) {
      unawaited(_publishGroupRouteIfAllowed(result));
    }
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
        _routeBannerDismissed = false;
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

    final routeForOffline = _activeRouteForOfflineCache();
    if (routeForOffline != null) {
      unawaited(
        RouteCacheService.instance.storeConfirmedRoute(
          route: routeForOffline,
          isRoundTrip: _isRoundTrip,
          style: _selectedStyle,
          avoidHighways: _effectiveNavigationAvoidHighways,
          groupId: widget.groupId,
        ),
      );
      unawaited(
        OfflineMapService.instance.cacheRouteRegion(
          routeForOffline.coordinates,
        ),
      );
    }

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

  RouteResult? _activeRouteForOfflineCache() {
    final result = _lastRouteResult ?? _sessionRouteResult;
    if (result != null && result.coordinates.length >= 2) return result;
    if (_fullRouteCoordinates.length < 2) return null;
    final geometry = <String, dynamic>{
      'type': 'LineString',
      'coordinates': _fullRouteCoordinates,
    };
    return RouteResult(
      geoJson: jsonEncode(geometry),
      geometry: geometry,
      coordinates: _fullRouteCoordinates,
      maneuvers: _maneuvers,
      distanceMeters: _routeDistance,
      durationSeconds: _routeDuration,
      speedLimits: _activeSpeedLimits,
      edgeMeta: const {'route_source': 'confirmed_route_cache'},
    );
  }

  /// 2026-06-09 (vucko Voll-Route-Sichtbar): Index ~targetMeters VOR startIndex
  /// (rückwärts) — Startpunkt des begrenzten grauen Driven-Fensters hinter dem
  /// Puck. Clamped auf ≥ 0. Begrenzt → konstant günstiger Push, kein Wachsen.
  // ignore: unused_element
  int _findLookBehindIndex(int startIndex, double targetMeters) {
    double accumulated = 0.0;
    final clampedStart = startIndex.clamp(0, _fullRouteCoordinates.length);
    for (var i = clampedStart - 1; i > 0; i--) {
      final c1 = _fullRouteCoordinates[i];
      final c2 = _fullRouteCoordinates[i - 1];
      accumulated += geo.Geolocator.distanceBetween(c1[1], c1[0], c2[1], c2[0]);
      if (accumulated >= targetMeters) return i - 1;
    }
    return 0;
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
        _camFitBounds([
          bounds.southWest,
          bounds.northEast,
        ], EdgeInsets.fromLTRB(24, safeTop + 18, 24, bottomPad));
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
        distanceFilter: 0,
        // 2026-05-22 (vucko): 500ms → 200ms für 2.5× häufigere GPS-Updates.
        // User-Wunsch: "jede Minidrehung sehen können, jeden Meter scharf".
        // Android GPS hardware kann ~5Hz (200ms) wenn bestForNavigation.
        intervalDuration: const Duration(milliseconds: 200),
        foregroundNotificationConfig: geo.ForegroundNotificationConfig(
          notificationTitle: 'Cruise Connector Navigation',
          notificationText: notificationText,
          notificationChannelName: 'Cruise Connector Navigation',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }

    if (Platform.isIOS || Platform.isMacOS) {
      return geo.AppleSettings(
        accuracy: geo.LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        activityType: geo.ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }

    return const geo.LocationSettings(
      accuracy: geo.LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
  }

  void _startNavigationTracking() {
    _stopIdlePositionStream(); // Idle-Stream stoppen, Navigation übernimmt
    _positionSubscription?.cancel();
    _socketPositionSubscription?.cancel();

    // Navigations-Startzeit setzen (nur beim ersten Start, nicht bei Resume)
    final startsNewDriveSession = _navigationStartTime == null;
    if (startsNewDriveSession) {
      _drivenTrackRecorder.reset();
      _totalDistanceDriven = 0.0;
      // 2026-06-15 (vucko N1): Lock-On frisch — bis der Puck eingerastet ist, gilt
      // die Kaltstart-Reroute-Sperre (kein Phantom am Fahrtbeginn).
      _onRouteLockStreak = 0;
      _routeLockedOn = false;
    }
    _navigationStartTime ??= DateTime.now();
    _driveSessionRecordedForCompletion = false;
    final currentLocation = _userLocation;
    if (startsNewDriveSession && currentLocation != null) {
      _recordDrivenTrackSample(currentLocation);
    }

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

  void _recordDrivenTrackSample(geo.Position position) {
    final result = _drivenTrackRecorder.addSample(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: position.timestamp,
      accuracyMeters: position.accuracy,
      speedMetersPerSecond: position.speed,
    );
    if (result == DrivenTrackSampleResult.ignored) return;

    _totalDistanceDriven = _drivenTrackRecorder.distanceMeters;
    if (result == DrivenTrackSampleResult.newSegment) {
      debugPrint(
        '[CruiseMode] GPS-Luecke erkannt, Track-Segment getrennt gespeichert.',
      );
    }
    // 2026-05-28 (vucko Task #66): Geofence-Check pro Driven-Track-Sample.
    // Sample-Frequenz ist ~1Hz während aktiver Fahrt — reicht für 200m
    // Trigger bei Geschwindigkeiten bis 200 km/h (= ~55 m/s).
    _processConstructionGeofence(position.latitude, position.longitude);
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

  List<double>? _finalNavigationTargetCoordinate() {
    if (!_isRoundTrip && _activeDestinationCoordinate != null) {
      return _activeDestinationCoordinate;
    }
    if (_fullRouteCoordinates.isEmpty) return null;
    return _fullRouteCoordinates.last;
  }

  double? _updateDistanceToFinalTarget(geo.Position position) {
    final target = _finalNavigationTargetCoordinate();
    if (target == null || target.length < 2) {
      _distanceToFinalTargetMeters = null;
      return null;
    }
    final distance = distanceToCoordinateMeters(
      position: position,
      coordinate: target,
    );
    _distanceToFinalTargetMeters = distance;
    return distance;
  }

  bool _canCompleteNavigationAtCurrentPosition(geo.Position position) {
    final distanceToTarget =
        _updateDistanceToFinalTarget(position) ?? double.infinity;
    final plannedDistanceMeters =
        _completionRouteResult?.distanceMeters ?? _originalRouteDistance;
    final canComplete = shouldCompleteNavigation(
      isRoundTrip: _isRoundTrip,
      distanceToFinalTargetMeters: distanceToTarget,
      drivenDistanceMeters: _totalDistanceDriven,
      plannedDistanceMeters: plannedDistanceMeters,
      completionRadiusMeters: _arrivalRadiusMeters,
      minRoundTripProgress: _minProgressForAutomaticCompletion,
    );
    if (canComplete) return true;

    if (_isRoundTrip && distanceToTarget <= _arrivalRadiusMeters) {
      final progress =
          plannedDistanceMeters == null || plannedDistanceMeters <= 0
          ? 1.0
          : (_totalDistanceDriven / plannedDistanceMeters).clamp(0.0, 1.0);
      debugPrint(
        '[CruiseMode] Ziel erreicht, aber noch nicht genug Route gefahren: '
        '${(progress * 100).round()}%',
      );
    }
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

    final nativePredictionTime = kIsWeb
        ? null
        : DateTime.now().add(_nativeRenderPredictionLead);
    final nativeLockedTarget = nativePredictionTime == null
        ? null
        : _routeLockedRenderPosition(nativePredictionTime);

    // ── Kamera-Bewegung ──────────────────────────────────────────────────────
    // Alle Plattformen: Animierte Interpolation (60fps smooth)
    // 2026-06-06 (vucko P11): Während die Routen-Übersicht (Karten-Button) läuft,
    // den Follow NICHT feuern — sonst zog der nächste GPS-Fix die Kamera sofort
    // wieder auf den Standort und die Übersicht „funktionierte nicht".
    if (_isCameraLocked && _mapReady && !_isOverviewActive) {
      if (kIsWeb) {
        final predicted = _webSmoother.predict(
          DateTime.now().add(const Duration(milliseconds: 180)),
        );
        _animateCameraTo(predicted.lat, predicted.lng, predicted.heading);
      } else {
        // iOS/Android: Vorhersage für noch flüssigere Animation
        final predictionTime =
            nativePredictionTime ??
            DateTime.now().add(_nativeRenderPredictionLead);
        final predicted = _nativeSmoother.predict(predictionTime);
        final lockedTarget =
            nativeLockedTarget ?? _routeLockedRenderPosition(predictionTime);
        _animateCameraTo(
          lockedTarget?.latitude ??
              (predicted.lat != 0 ? predicted.lat : effectivePosition.latitude),
          lockedTarget?.longitude ??
              (predicted.lng != 0
                  ? predicted.lng
                  : effectivePosition.longitude),
          _nativeSmoother.hasValidHeading ? predicted.heading : _userHeading,
        );
      }
    }

    // 2026-06-13 (vucko Free-Cam-Ruckeln): Render-Ticker laeuft in JEDEM
    // Kameramodus, solange Fixes kommen — er treibt Puck-Glide, Linien-
    // Schnitt und (bei stehender Kamera) die Marker-Projektion. Der Idle-
    // Stop im Tick pausiert ihn im Stand; hier wird er wiederbelebt.
    if (!kIsWeb && _mapReady && !_isOverviewActive) {
      final renderTicker = _cameraAnimController;
      if (renderTicker != null && !renderTicker.isAnimating) {
        _lastCameraFrameAt = null;
        renderTicker.repeat();
      }
    }

    // ── UI-Rebuild Throttling ───────────────────────────────────────────────
    // Marker-Position intern aktualisieren, Route-Geometrie aber stabil lassen.
    // setState nur wenn genug Zeit vergangen (Web: 16ms, Native: sofort).
    _userPosition = LatLng(
      effectivePosition.latitude,
      effectivePosition.longitude,
    );
    _cachedUserCenter =
        _userPosition; // 2026-06-06 (vucko P10): Center-Cache frisch halten
    if (_isRouteConfirmed && _navigationStartTime != null) {
      _recordDrivenTrackSample(effectivePosition);
    }
    // Wichtig: Die kanonische Route hier nicht auf die aktuelle GPS-Position
    // ziehen. Bei Off-Route-/Access-Leg-Starts erzeugt das sonst eine
    // sichtbare Luftlinie vom Fahrer zur Route. Route-Slices werden nur nach
    // einem echten Route-Match oder einer berechneten Access-/Reroute gesetzt.

    // 2026-06-06 (vucko P8): Rebuild-Throttle jetzt auf ALLEN Plattformen (vorher
    // nur Web/16ms). Dieser „nackte" Per-Fix-Rebuild aktualisiert nur Puck-Geo +
    // HUD; die FLÜSSIGE Bewegung macht die engine-seitige Kamera-Animation +
    // Marker-Reprojektion in onCameraMove. Max ~11Hz reicht, spart UI-Churn.
    final now = DateTime.now();
    final skipRebuild =
        _lastWebRebuildTime != null &&
        now.difference(_lastWebRebuildTime!).inMilliseconds < 90;
    if (!skipRebuild) {
      _lastWebRebuildTime = now;
      _safeSetState(() {});
    }

    if (!_isRouteConfirmed || _fullRouteCoordinates.length < 2) return;

    // 2026-06-07 (vucko P-reroute): Korridor ZUERST (vor dem Match) berechnen,
    // damit das Index-Advance-Fenster an denselben Korridor gekoppelt ist — sonst
    // entstand ein 45–54m-„Dead-Band", in dem der Index einfror, das Vorwärts-
    // Fenster überlief und auf perfekt befahrener Route ein Fehl-Reroute feuerte.
    final baseCorridor = _isAccessLegActive
        ? 85.0
        : _isRoundTrip
        ? _offRouteThresholdMeters
        : _currentPointToPointCorridorMeters();
    final offRouteCorridor = effectiveOffRouteCorridorMeters(
      baseCorridor: baseCorridor,
      accuracyMeters: position.accuracy,
      speedMps: position.speed,
    );

    final prevRouteIndex = _currentRouteIndex;
    // windowSize 40→80 + maxJumpMeters an den Korridor gekoppelt: der Index folgt
    // dem Puck auch über lange GraphHopper-Segmente, statt einzufrieren.
    final rawMatch = findNearestInWindow(
      position: position,
      coordinates: _fullRouteCoordinates,
      currentIndex: _currentRouteIndex,
      windowSize: 80,
      maxJumpMeters: math.max(offRouteCorridor + 15, 60.0),
    );
    final match = _guardRoundTripFinishMatch(rawMatch);
    var routeProgressMatch = match;
    var offRouteDecisionMatch = match;
    _updateDistanceToFinalTarget(position);
    final previousVisibleManeuverIndex = _activeVisibleManeuverIndex();

    var isOutsideCorridor = match.distanceMeters > offRouteCorridor;
    // 2026-06-13 (vucko Geraete-Video „Reroute greift nicht nahe Ziel"):
    // `approachingDestination` soll NUR die letzten Meter vor der Ankunft das
    // Reroute unterdrücken (GPS-Rauschen am Ziel). Die alte Definition war
    // aber „macht Fortschritt Richtung Ziel" und feuerte schon bei 2,2 km
    // Reststrecke → unterdrückte globalen Re-Snap + Off-Route + Reroute:
    // currentRouteIndex fror ein, „X km verbleibend" fror ein, das 3km-Fenster
    // klebte an der falschen Stelle, und ein echtes Verfahren wurde NIE
    // erkannt. Jetzt zusätzlich harte Restdistanz-Schranke (≤180 m): nur dann
    // ist man wirklich „beim Ankommen".
    final remainingForGate = _remainingDistance ?? _routeDistance;
    final approachingDestination =
        !_isRoundTrip &&
        _activeDestinationCoordinate != null &&
        (remainingForGate != null && remainingForGate <= 180.0) &&
        _isApproachingCurrentDestination(position);
    // 2026-06-13 (vucko J4-Phantom): Nahe dem ENDE eines Rundkurses ist Start≈
    // Ende ein Selbstüberlapp, an dem der Matcher kurz „off-route" meldete und
    // auf den letzten Metern einen Phantom-Reroute auslöste („Neuberechnung"
    // bei 0,5 km Rest im Video). Auf den letzten ~250 m eines Rundkurses NIE
    // rerouten — Index/Distanz werden weiter gepflegt, nur der Trigger ruht.
    final nearRouteEnd =
        _isRoundTrip && remainingForGate != null && remainingForGate <= 250.0;
    // Apple/Google-Regel: ein VORWÄRTS-laufender Puck fährt die Route — auch wenn
    // ein einzelner Fix seitlich zappelt. Dann niemals reroute.
    // 2026-06-12 (vucko Reroute-zu-spaet, Video): Das Veto gilt nur noch, wenn
    // der GPS-KURS zur Route passt. Beim ueberfahrenen Abbiege-Manoever oder
    // auf der Parallelstrasse kriecht der Match-Index naemlich WEITER vorwaerts
    // (die Projektion wandert mit) — das alte Veto blockierte den Reroute
    // damit minutenlang ("0 m"-Banner-Freeze im Geraete-Video).
    var makingForwardProgress =
        match.index > prevRouteIndex &&
        _gpsHeadingAlignedWithRoute(position, match);

    // 2026-06-12 (vucko): Manoever-UEBERFAHREN-Trigger. War der Fahrer schon
    // <35m am aktiven Manoever und entfernt sich wieder >60m davon, ist das
    // Manoever verpasst — Off-Route-Verfahren sofort starten, auch wenn die
    // Position noch im (breiten) Korridor liegt. Exakt der Video-Fall.
    final distToManeuverNow = _calculateDistanceToManeuver();
    final visibleIdxForOvershoot = _activeVisibleManeuverIndex();
    if (visibleIdxForOvershoot != _overshootManeuverIndex) {
      _overshootManeuverIndex = visibleIdxForOvershoot;
      _overshootMinDistM = double.infinity;
    }
    var maneuverOvershoot = false;
    if (distToManeuverNow != null) {
      if (distToManeuverNow < _overshootMinDistM) {
        _overshootMinDistM = distToManeuverNow;
      }
      maneuverOvershoot =
          _overshootMinDistM < 35.0 &&
          distToManeuverNow > math.max(60.0, _overshootMinDistM + 45.0) &&
          (position.speed.isFinite ? position.speed : 0) > 3.0;
    }

    // 2026-06-08 (vucko P-reroute): GLOBALER RE-SNAP (wie Apple/Google). Das
    // gefensterte Matching kann hinter dem Fahrer zurückbleiben (Fenster
    // [idx,idx+80] erreicht die echte Position nicht mehr) → es meldet fälschlich
    // „off-route", obwohl der Puck IN Wahrheit auf der Route ist (= die unnötigen
    // Reroutes nach einem Re-Dock). Meckert das Fenster, durchsuchen wir EINMAL
    // die ganze Route: liegt der nächste Punkt doch im Korridor, war es nur
    // Fenster-Verzug → re-ankern + NICHT off-route. Nur wirklich-daneben (auch
    // global > Korridor) zählt. Läuft nur wenn das Fenster off-route meldet →
    // kein Overhead im Normalbetrieb.
    // 2026-06-13 (vucko Geraete-Video): Re-Snap läuft jetzt AUCH nahe dem Ziel
    // (kein `!approachingDestination`-Gate mehr) — er ist immer sicher (re-
    // ankert nur den Index) und hält currentRouteIndex/Restdistanz/3km-Fenster
    // aktuell, statt sie einzufrieren wenn man sich nahe dem Ziel verfährt.
    if (isOutsideCorridor) {
      // 2026-06-13 (vucko Manöver-26km-Bug): Re-Snap mit INDEX-Nähe-Präferenz
      // statt blindem global-Nächsten — auf selbstüberlappenden Rundkursen
      // (gleiche Straße Hin+Rück) springt der Index sonst auf den fernen
      // Selbstüberlapp und das nächste Manöver schießt 26km ans Routenende.
      final globalMatch = findNearestOnRoutePreferIndex(
        position: position,
        coordinates: _fullRouteCoordinates,
        referenceIndex: _currentRouteIndex,
        corridorMeters: offRouteCorridor,
      );
      if (globalMatch.distanceMeters < offRouteDecisionMatch.distanceMeters) {
        offRouteDecisionMatch = globalMatch;
        makingForwardProgress = globalMatch.index > prevRouteIndex;
      }
      if (globalMatch.distanceMeters <= offRouteCorridor) {
        _currentRouteIndex = globalMatch.index.clamp(
          0,
          _fullRouteCoordinates.length - 1,
        );
        routeProgressMatch = globalMatch;
        isOutsideCorridor =
            false; // doch auf der Route — nur Fenster nachgehinkt
        // 2026-06-14 (vucko Re-Dock-Trim, Geraete-Screenshot „Strecke vor UND
        // hinter mir"): Beim Wieder-Andocken nach kurzer Abweichung rueckte der
        // Re-Snap zwar _currentRouteIndex vor, aber der Render-Lock (= Quelle
        // des Linien-Schnitts UND des Pucks) ist monoton und blieb hinter der
        // echten Position eingefroren → das 3km-Bright-Fenster startete hinter
        // dem Puck, der abgefahrene Teil blieb rot. Jetzt: Lock explizit auf den
        // re-gesnappten Index ankern + Trim-Push-Caches leeren, damit der
        // Schnitt diesen Tick neu vom echten Puck aus aufgebaut wird. Nur bei
        // echtem Versatz (>20m) — Mini-Jitter bleibt auf dem monotonen Glide.
        if (_reanchorRenderLockToIndex(globalMatch.index)) {
          _lastTrimDistM = -1;
          _lastDrivenHead = null;
          _lastDimHead = null;
          _lastWindowMatch = routeProgressMatch;
        }
      }
    }

    // 2026-06-13 (vucko J1-Latenz, DER Kern-Fix): Ist man nach dem globalen
    // Re-Snap IMMER NOCH außerhalb des Korridors (>Korridor von JEDEM
    // Routenpunkt), kann es KEIN echtes „Vorwärts auf der Route" geben — der
    // vorlaufende Match-Index ist dann nur das 80er-Fenster, das über einen
    // Selbstüberlapp/Parallelweg gleitet. Genau dieser falsche Fortschritts-
    // Veto (makingForwardProgress=true trotz off-route) ließ den Reroute auf
    // Rundkursen 20-25 s hängen. Außerhalb Korridor ⇒ niemals Fortschritts-Veto.
    if (isOutsideCorridor) {
      makingForwardProgress = false;
    }

    // Manoever-Overshoot zaehlt wie "klar daneben" — aber NUR im breiten
    // Point-to-Point-Korridor (300-800 m), wo ein verpasster Turn sonst
    // distanz-technisch unentdeckt bliebe. Bei Rundkursen (50 m Korridor) ist
    // ein verpasster Turn ohnehin sofort >Korridor → der Overshoot-Zwang löste
    // dort nur Phantom-Reroutes an Kreisverkehren/Selbstüberlapp aus (Video).
    if (maneuverOvershoot && !_isRoundTrip) {
      isOutsideCorridor = true;
      makingForwardProgress = false;
    }
    // 2026-06-13 (vucko Video Banner-Freeze): Restdistanz/-zeit IMMER pflegen —
    // auch off-route und VOR dem Reroute-Early-Return. Vorher fror „X,X km
    // verbleibend" beim Verfahren minutenlang ein (nur die ETA-Uhr tickte).
    final remainingChanged = _updateRemainingDistanceAndDuration(
      routeMatch: routeProgressMatch,
    );

    // 2026-06-15 (vucko N1): Mapbox-/Apple-Gating gegen Kaltstart-Phantom-Reroutes
    // (Geräte-Fahrt 23min: „Neue Strecke übernommen" feuerte ~alle 10-25s am Anfang,
    // während der gesnappte Puck dead-on wirkte). Der gesnappte Render verdeckt, dass
    // ROHES GPS beim Kaltstart seitlich ausreißt; die Off-Route-Prüfung lief darauf.
    final accuracyM = position.accuracy.isFinite ? position.accuracy : -1.0;
    // Accuracy ≤35m = vertrauenswürdig genug zum Einrasten / für die Schnell-Schiene
    // (≈ Mapbox RouteSnappingMinimumHorizontalAccuracy 20m + GPS-Slack).
    final goodAccuracy = accuracyM > 0 && accuracyM <= _lockOnMaxAccuracyMeters;
    // Lock-On-Streak: senkrecht nah + im Korridor + gute Accuracy = eingerastet.
    final perpToRoute = math.min(
      offRouteDecisionMatch.distanceMeters.isFinite
          ? offRouteDecisionMatch.distanceMeters
          : double.infinity,
      routeProgressMatch.distanceMeters.isFinite
          ? routeProgressMatch.distanceMeters
          : double.infinity,
    );
    if (!isOutsideCorridor &&
        perpToRoute <= _lockOnPerpMeters &&
        goodAccuracy) {
      if (_onRouteLockStreak < _lockOnStreakNeeded) _onRouteLockStreak++;
      if (_onRouteLockStreak >= _lockOnStreakNeeded) _routeLockedOn = true;
    } else if (isOutsideCorridor) {
      _onRouteLockStreak = 0;
    }
    // Harte Decke: nach _lockOnGraceCeiling gilt der Puck als eingerastet, selbst
    // wenn das GPS nie sauber ≤35m wurde — sonst bliebe ein echtes Verfahren in
    // dauerhaft mäßiger GPS-Lage ewig gesperrt.
    if (!_routeLockedOn &&
        _navigationStartTime != null &&
        DateTime.now().difference(_navigationStartTime!) > _lockOnGraceCeiling &&
        (_postRerouteGraceUntil == null ||
            DateTime.now().isAfter(_postRerouteGraceUntil!))) {
      // 2026-06-16 (vucko O4): Die 90s-Grace-Decke darf NICHT mitten in der
      // Post-Reroute-Grace force-locken — sonst wäre der Lock-Reset oben sofort
      // wieder aufgehoben und die Kaskade bliebe. Während der 6s-Grace gilt die
      // strenge Divergenz-Schwelle (rerouteVoteAllowed, lockedOn=false).
      _routeLockedOn = true;
    }
    // Mapbox-/Apple-Gating (siehe rerouteVoteAllowed): unqualifizierter Fix bzw.
    // Kaltstart-Rauschen vor dem Einrasten darf KEIN Reroute auslösen.
    final rerouteMayVote = rerouteVoteAllowed(
      accuracyMeters: accuracyM,
      routeLockedOn: _routeLockedOn,
      offRouteDistanceMeters: offRouteDecisionMatch.distanceMeters,
      corridorMeters: offRouteCorridor,
      maxQualifiedAccuracyMeters: _maxQualifiedAccuracyMeters,
      lockOnMaxAccuracyMeters: _lockOnMaxAccuracyMeters,
    );

    // 2026-06-15 (vucko N-Runde-2): KLAR DEFINIERTE REGEL — Zähler statt Zeit.
    // UNBEDINGT vor dem Gate berechnen (auch bei Fortschritt/Ziel-Annäherung den
    // Zähler zurücksetzen, sonst überlebt ein Reststand einen Korridor-Tick).
    // „Auf Route diesen Fix" = im Korridor, ODER etwas weiter aber Kurs passt
    // (Kurven-/Parallel-Toleranz bis 2× Korridor), ODER klarer Fortschritt/Ziel.
    // Der Kurs-Check ist bei Langsamfahrt/ungültigem Heading konservativ „aligned"
    // (GPS-Kurs dann unbrauchbar). JEDER solche Fix nullt den Zähler.
    final perpOffM = offRouteDecisionMatch.distanceMeters.isFinite
        ? offRouteDecisionMatch.distanceMeters
        : double.infinity;
    final courseAlignedNow = _gpsHeadingAlignedWithRoute(
      position,
      offRouteDecisionMatch,
    );
    final onRouteThisFix = fixIsOnRoute(
      isOutsideCorridor: isOutsideCorridor,
      perpMeters: perpOffM,
      corridorMeters: offRouteCorridor,
      courseAligned: courseAlignedNow,
      makingForwardProgress: makingForwardProgress,
      approachingDestination: approachingDestination,
      nearRouteEnd: nearRouteEnd,
    );
    // Unbrauchbarer Fix (>100m Accuracy) zählt NICHT als off, nullt aber auch
    // nicht (neutral halten) — sonst würde ein einzelner Müll-Fix einen echten
    // Off-Streak löschen.
    final fixUsableForOffRoute =
        accuracyM > 0 && accuracyM <= _maxQualifiedAccuracyMeters;
    // 2026-06-16 (vucko P1 Phantom-Reroute trotz Auf-der-Strecke): Den Off-Route-
    // Zähler NICHT hochzählen, wenn der gematchte Routen-Index gleichzeitig
    // VORWÄRTS läuft UND wir noch nah an der Route sind (≤2,5× Korridor). Genau
    // das ist die Signatur des Selbstüberlapp-/Parallelspur-Phantoms: das
    // gefensterte Matching gleitet kurz auf das ferne/parallele Leg, meldet
    // „outside", obwohl der Fahrer exakt auf der Linie weiterfährt. Ein ECHTES
    // Verfahren unterscheidet sich klar: der Index bleibt stehen/läuft rückwärts
    // (falsch abgebogen) ODER die Distanz wächst über 2,5× Korridor — beides
    // zählt weiter und feuert den Reroute normal. Verzögert echtes Verfahren also
    // nicht, eliminiert aber den Rest-Phantom.
    final advancingButNearRoute =
        offRouteDecisionMatch.index > prevRouteIndex &&
        perpOffM <= offRouteCorridor * 2.5;
    if (onRouteThisFix) {
      _consecutiveOffRouteFixes = 0;
    } else if (fixUsableForOffRoute &&
        !advancingButNearRoute &&
        _consecutiveOffRouteFixes < 1000) {
      _consecutiveOffRouteFixes++;
    }
    // Nötige Off-Fixes accuracy-skaliert (Mapbox: max(4, accuracy/4)). Schlechtes
    // GPS ⇒ MEHR Fixes (träger), aber NIE hart blockiert — ein echtes Verfahren
    // unter mäßigem Himmel (A14-Auffahrt) feuert weiterhin, nur etwas später.
    // Schnell-Schiene (3 Fixes) nur bei EINDEUTIGEM Verfahren: Manöver-Overshoot
    // ODER klar gegenläufiger Kurs (>72°, >25m daneben, keine scharfe Kurve voraus).
    final clearWrongTurn =
        maneuverOvershoot ||
        (_gpsHeadingClearlyOpposed(position, offRouteDecisionMatch) &&
            offRouteDecisionMatch.distanceMeters > 25.0 &&
            !_routeHasSharpTurnNear(offRouteDecisionMatch.index));
    final effRequiredOffFixes = requiredOffRouteFixes(
      accuracyMeters: accuracyM,
      clearWrongTurn: clearWrongTurn,
    );

    if (isOutsideCorridor &&
        !approachingDestination &&
        !nearRouteEnd &&
        !makingForwardProgress &&
        rerouteMayVote) {
      // Ehrliche Banner-Meter: Luftlinie zur Route fließt in die Anzeige ein.
      _offRouteGapMeters = offRouteDecisionMatch.distanceMeters.isFinite
          ? offRouteDecisionMatch.distanceMeters
          : 0.0;
      if (_clearLiveRouteWindowForOffRoute()) {
        _safeSetState(() {});
      }
      // Zähler + Zeit-Hysterese: normale GPS-Ausreißer müssen mehrere
      // Off-Route-Fixes liefern; eindeutiges Verfahren darf schneller feuern.
      final rerouteDecisionAt = DateTime.now();
      _offRouteSince ??= rerouteDecisionAt;
      final rerouteDecision = NavigationRerouteDecisionEngine.evaluate(
        isOutsideCorridor: isOutsideCorridor,
        approachingDestination: approachingDestination,
        nearRouteEnd: nearRouteEnd,
        makingForwardProgress: makingForwardProgress,
        maneuverOvershoot: maneuverOvershoot,
        headingOpposed: clearWrongTurn && !maneuverOvershoot,
        distanceMeters: offRouteDecisionMatch.distanceMeters,
        corridorMeters: offRouteCorridor,
        offRouteSince: _offRouteSince,
        now: rerouteDecisionAt,
        isRerouting: _isRerouting,
        lastRerouteTime: _lastRerouteTime,
        lastRerouteFailed: _lastRerouteFailed,
        speedMps: position.speed,
        normalCooldown: _rerouteCooldown,
        failedCooldown: _rerouteFailureCooldown,
      );
      final offRouteDeclared =
          _consecutiveOffRouteFixes >= effRequiredOffFixes ||
          (rerouteDecision.clearlyOffRoute && rerouteDecision.sustained) ||
          rerouteDecision.maximumWaitExceeded;
      if (offRouteDeclared && rerouteDecision.shouldTrigger) {
        _lastRerouteTime = rerouteDecisionAt;
        _offRouteCount = 0;
        _consecutiveOffRouteFixes = 0;
        _offRouteSince = null;
        _rerouteToOriginalRoute(position);
        return;
      }
    } else {
      // Im Korridor ODER Fortschritt ODER Ziel-Annäherung → Off-Route-Timer aus.
      _offRouteSince = null;
      _offRouteCount = 0;
      _consecutiveOffRouteFixes = 0;
      _offRouteGapMeters = 0.0;
    }

    var needsRebuild = remainingChanged;

    // 2026-06-07 (vucko P-reroute): Advance-Gate an den Korridor gekoppelt (war
    // hart 45m) → kein Dead-Band mehr zwischen 45m und Korridorbreite.
    // + Anti-Overlap-Cap: ein einzelner Tick darf den Index NICHT um >60 Punkte
    // vorspringen. Auf einem sich selbst überlappenden Rundkurs (Hin-/Rückweg
    // dieselbe Straße) könnte das 80er-Fenster sonst auf die RÜCKWEG-Spur
    // springen → Fortschritt korrupt, nötiger Reroute unterdrückt. Echtes Fahren
    // rückt <2 Punkte/Tick vor, der Cap blockt also nur anomale Sprünge.
    if (match.index > _currentRouteIndex &&
        match.index - _currentRouteIndex <= 60 &&
        match.distanceMeters <= offRouteCorridor) {
      // Gefahrene Distanz tracken (Routen-Meter zwischen altem und neuem Index).
      var advanceMeters = 0.0;
      for (var i = _currentRouteIndex; i < match.index; i++) {
        final c1 = _fullRouteCoordinates[i];
        final c2 = _fullRouteCoordinates[i + 1];
        advanceMeters += geo.Geolocator.distanceBetween(
          c1[1],
          c1[0],
          c2[1],
          c2[0],
        );
      }
      // 2026-06-16 (vucko Banner-Freeze + Standort-Sprung, Video-Analyse): Den
      // Index-Vorschub AUCH in METERN kappen, nicht nur in Vertices. 60 Vertices
      // sind auf dünner GraphHopper-Geometrie oft hunderte Meter → ein
      // Selbstüberlapp-/Parallel-Match springt den Index weit voraus; danach
      // friert die Manöver-Distanz ein (Banner hängt 10-25 s, dann Sprung) und
      // der Puck wirkt vorausgesprungen, bis der Wagen real aufgeschlossen hat.
      // Echte Fahrt rückt höchstens ~Tempo × ein paar Sekunden vor; ein
      // implausibler Meter-Sprung wird verworfen (Index bleibt am echten
      // Standort, rückt nächsten Fix plausibel weiter).
      final sp = position.speed.isFinite && position.speed > 0
          ? position.speed.clamp(0.0, 70.0)
          : 0.0;
      final maxAdvanceMeters = sp * 3.0 + 60.0;
      // Plausibler Vorschub → übernehmen. Implausibler Meter-Sprung → diesen Fix
      // verwerfen (Index bleibt am echten Standort, rückt nächsten Fix plausibel
      // weiter). So kein Index-Leap → keine eingefrorene Manöver-Distanz.
      if (advanceMeters <= maxAdvanceMeters) {
        _distanceSinceLastRedraw += advanceMeters;
        _currentRouteIndex = match.index;
        needsRebuild = true;
        _maybeFinalizeAccessLegPhase();
        // 2026-06-09 (vucko Voll-Route-Sichtbar): KEIN 3km-Sliding-Window-Redraw
        // der sichtbaren Linie mehr. Die rote aktive Linie ist die VOLLE Route
        // (statisch, einmal gepusht → kann NIE flackern); _trimVisibleRouteToProjection
        // pflegt den grauen Driven-Trail + _remainingRouteCoordinates.
      }
    }

    // 2026-06-08 (vucko Leitlinie GPU-Trim): Fahrt-Fortschritt 0..1 entlang der
    // Route bestimmt den line-gradient (GPU-seitig) — der trimmt die rote Linie
    // EXAKT an der Puck-Projektion, geo-verankert → bei jedem Tempo nie davor und
    // nie dahinter. Ersetzt das frühere Geometrie-Trimmen (das pro Frame die
    // ganze Route neu pushte → Lag/Schwarz). Nur bei echter Änderung rebuild.
    if (!isOutsideCorridor) {
      // 2026-06-14 (vucko Re-Dock-Trim): routeProgressMatch (re-gesnappt) statt
      // dem veralteten Fenster-`match` — sonst ankert der Fortschritt nach dem
      // Wieder-Andocken hinter dem Puck. Im Korridor sind beide identisch.
      final newProgress = _routeProgressFromMatch(routeProgressMatch);
      if ((newProgress - _routeProgress).abs() > 0.00003) {
        _routeProgress = newProgress;
        needsRebuild = true;
      }
    }
    // 2026-06-09 (vucko Voll-Route-Sichtbar): pflegt den grauen Driven-Trail
    // (sichtbar, hinter dem Puck) + _remainingRouteCoordinates (Restdistanz/Auto).
    // Bei echter Änderung Rebuild anstoßen → _syncDrivenTrail pusht den Trail.
    if (!isOutsideCorridor) {
      // 2026-06-14 (vucko Re-Dock-Trim): re-gesnappter Match → der Fallback-Pfad
      // (Lock freigegeben) schneidet am echten Puck statt am alten Fenster.
      if (_trimVisibleRouteToProjection(routeProgressMatch)) {
        needsRebuild = true;
      }
    }
    // 2026-06-09 (vucko Trip-Skip): besuchte Zwischenstopps abhaken.
    _markPassedWaypoints(position);

    // Prüfe ob Route zu Ende ist
    final lastIndex = _fullRouteCoordinates.length - 1;
    if (_currentRouteIndex >= lastIndex - 1) {
      final distanceToTarget =
          _updateDistanceToFinalTarget(position) ?? double.infinity;
      if (distanceToTarget <= _arrivalRadiusMeters &&
          _canCompleteNavigationAtCurrentPosition(position)) {
        _stopNavigationTracking();
        _stopSimulation(restartLiveTracking: false);
        _onRouteCompleted();
        return;
      }
    }

    final prevManeuver = _activeManeuverIndex;
    _updateActiveManeuver();
    final visibleManeuverIndex = _activeVisibleManeuverIndex();
    if (_activeManeuverIndex != prevManeuver ||
        visibleManeuverIndex != previousVisibleManeuverIndex) {
      needsRebuild = true;
      // Haptic Feedback wenn neues Manöver aktiv wird (Abbiegung erreicht)
      if (visibleManeuverIndex != null &&
          visibleManeuverIndex != previousVisibleManeuverIndex) {
        HapticFeedback.heavyImpact();
      }
    }
    // 2026-06-16 (vucko O9): Echte Kreisverkehr-Topologie lazy holen, sobald
    // ein Kreisel ins Anfahr-Fenster (≤1500m) rückt — pro Tick max. 1 Fetch.
    _maybeEnrichRoundaboutTopology();
    // 2026-05-23 (vucko Task #16): 3-Stufen-Annäherungs-Haptic.
    // Jede Stufe feuert nur 1× pro Manöver — verhindert Spam bei
    // GPS-Updates alle 200-500ms im Annäherungsbereich.
    final distToManeuver = _calculateDistanceToManeuver();
    if (visibleManeuverIndex != null && distToManeuver != null) {
      // Reset state wenn neues Manöver
      if (_lastHapticManeuverIndex != visibleManeuverIndex) {
        _lastHapticManeuverIndex = visibleManeuverIndex;
        _hapticStage300m = false;
        _hapticStage150m = false;
        _hapticStage50m = false;
      }
      // 2026-06-11 (vucko 1Hz-GPS-Fix): Stufen KASKADIEREND ohne Band-
      // Untergrenze. Die alten Baender ((150,300], (50,150]) waren unter dem
      // 20-Hz-Sim nicht ueberspringbar — echtes GPS mit 3-5s-Fix-Luecke
      // (Tunnel/Empfangsloch) sprang bei Landstrassentempo ueber ein ganzes
      // Band, und die EINZIGE Voice-Vorankuendigung (300m) entfiel. Jetzt
      // feuert immer die hoechste noch offene Stufe <= aktueller Distanz;
      // tiefere Stufen markieren die hoeheren als verbraucht.
      // 300m → lightImpact + EINE saubere Vorankündigung.
      if (!_hapticStage300m && distToManeuver <= 300 && distToManeuver > 50) {
        HapticFeedback.lightImpact();
        _hapticStage300m = true;
        // Erstkontakt schon <=150m (Fix-Luecke): 150er-Haptik gilt als
        // mitverbraucht — sonst feuern light+medium im selben Tick doppelt.
        if (distToManeuver <= 150) _hapticStage150m = true;
        _speakManeuverAnnouncement(distToManeuver.round(), important: true);
      }
      // 150m → 2026-06-05 (vucko Task #6): NUR Haptik, KEINE Voice mehr. Die
      // 150m-Ansage würgte sonst per stop() die 300m-Vorankündigung mitten im
      // Satz ab (das hörbare „Abhacken"). 2 Ansagen/Manöver reichen.
      if (!_hapticStage150m && distToManeuver <= 150 && distToManeuver > 50) {
        HapticFeedback.mediumImpact();
        _hapticStage150m = true;
      }
      // 50m → heavyImpact + finale „Jetzt"-Ansage (interrupt: zeitkritisch,
      // darf die Vorankündigung ablösen).
      if (!_hapticStage50m && distToManeuver <= 50) {
        HapticFeedback.heavyImpact();
        _hapticStage50m = true;
        _speakManeuverAnnouncement(0, important: true, interrupt: true);
      }
    }

    if (needsRebuild) _safeSetState(() {});
    unawaited(
      _carRouteBridge.publishProgress(
        remainingDistanceMeters: _remainingDistance,
        remainingDurationSeconds: _remainingDuration,
        nextManeuverText: _currentCarManeuverText(),
        nextManeuverDistance: distToManeuver,
        nextManeuverKind: _currentCarManeuverKind(),
        // 2026-06-14 (vucko K7): Live-Position + Fortschritts-Index ans Auto.
        latitude: position.latitude,
        longitude: position.longitude,
        heading: position.heading,
        routeIndex: _currentRouteIndex,
      ),
    );
  }

  // 2026-05-24 (vucko Task #49): POI-Auto-Fetch + Map-Marker.
  // 2026-05-24 (vucko v2): nur OFFENE POIs anzeigen — geschlossene sind für
  // den User nutzlos. Unbekannte Öffnungszeiten zeigen wir trotzdem an
  // (z.B. kleine Tankstellen ohne OSM-Tag).
  Future<void> _loadPoisFromSettings(List<List<double>> coords) async {
    final types = PoiSettingsService.instance.enabledTypes;
    if (types.isEmpty || coords.length < 2) return;
    try {
      final pois = await RoutePoiService.instance.fetchPoisAlongRoute(
        coordinates: coords,
        types: types,
        bufferMeters: 250,
        maxResults: 80,
      );
      if (!mounted) return;
      final filtered = pois
          .where((p) {
            final info = OpeningHoursParser.parse(p.openingHours);
            // Unbekannte/parseFailed → anzeigen (besser als nichts).
            if (info.parseFailed || info.status == OpenStatus.unknown) {
              return true;
            }
            return info.isOpenNow;
          })
          .take(50)
          .toList();
      setState(() => _routePois = filtered);
    } catch (_) {
      /* silent */
    }
  }

  Widget _buildPoiMarker(RoutePoi poi) {
    final color = switch (poi.type) {
      PoiType.fuel => const Color(0xFFEF4444), // rot — Tankstelle
      PoiType.restaurant => const Color(0xFFFB923C), // orange — Restaurant
      PoiType.cafe => const Color(0xFFA78BFA), // violett — Café
      PoiType.fastFood => const Color(0xFFFBBF24), // gelb — Imbiss
      PoiType.pub => const Color(0xFF22C55E), // grün — Pub
      PoiType.motorcycleRepair => const Color(0xFF2DD4BF), // teal — Werkstatt
      PoiType.parking => const Color(0xFF60A5FA),
      PoiType.toilets => const Color(0xFF9CA3AF),
    };
    // 2026-05-24 (vucko): Material-Icons statt Emoji — Emoji-Font
    // rendert auf manchen iOS-Geräten als "?" (siehe User-Bug).
    final iconData = switch (poi.type) {
      PoiType.fuel => Icons.local_gas_station_rounded,
      PoiType.restaurant => Icons.restaurant_rounded,
      PoiType.cafe => Icons.local_cafe_rounded,
      PoiType.fastFood => Icons.fastfood_rounded,
      PoiType.pub => Icons.sports_bar_rounded,
      PoiType.motorcycleRepair => Icons.build_rounded,
      PoiType.parking => Icons.local_parking_rounded,
      PoiType.toilets => Icons.wc_rounded,
    };
    // 2026-05-24 (vucko): "Schließt bald" → orange Pulsations-Ring
    // damit User auf einen Blick sieht: hier nicht mehr lange offen.
    final info = OpeningHoursParser.parse(poi.openingHours);
    final isClosingSoon = info.isClosingSoon;
    final ringColor = isClosingSoon ? const Color(0xFFFB923C) : Colors.white;
    final ringWidth = isClosingSoon ? 2.6 : 2.2;
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: ringWidth),
        boxShadow: [
          BoxShadow(
            color: (isClosingSoon ? const Color(0xFFFB923C) : color).withValues(
              alpha: 0.55,
            ),
            blurRadius: isClosingSoon ? 12 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(iconData, color: Colors.white, size: 16),
    );
  }

  void _showPoiInfoCard(RoutePoi poi) {
    HapticFeedback.selectionClick();
    // 2026-05-24 (vucko): neues PoiDetailSheet — Status, Wochentag-Tabelle,
    // farbiges Icon-Badge, "Schließt bald"-Warnung.
    // 2026-05-28 (vucko Task #62): „Zur Route hinzufügen" Button — Reroute
    // mit POI als Pflicht-Wegpunkt. Sichtbar nur wenn eine aktive Route da
    // ist und User nicht in einer Group-Session ist (Group hat eigenen Flow).
    final hasActiveRoute =
        _lastRouteResult != null && _fullRouteCoordinates.isNotEmpty;
    final canAddToRoute =
        hasActiveRoute && widget.groupId == null && !_isLoading;
    final isAlready = _poiIsOnRoute(poi);
    PoiDetailSheet.show(
      context,
      poi,
      onAddToRoute: canAddToRoute
          ? () => isAlready
                ? _removePoiFromRoute(poi)
                : _addPoiAsWaypointAndReroute(poi)
          : null,
      isAlreadyOnRoute: isAlready,
    );
  }

  /// Prüft, ob ein POI bereits als Wegpunkt in der aktuellen Route hinterlegt
  /// ist. Match-Toleranz: 50 m radial.
  bool _poiIsOnRoute(RoutePoi poi) {
    // 1. via_poi_id im edgeMeta (Route wurde gepatcht über genau diesen POI)
    final activeMeta = _lastRouteResult?.edgeMeta;
    if (activeMeta != null && activeMeta['via_poi_id'] == poi.id) {
      return true;
    }
    // 2. Klassischer Waypoint im Round-Trip-Wegpunkt-Modus
    if (_isRoundTrip) {
      return _roundTripWaypoints.any((wp) {
        final dist = geo.Geolocator.distanceBetween(
          poi.latitude,
          poi.longitude,
          wp.latitude,
          wp.longitude,
        );
        return dist < 50;
      });
    }
    return false;
  }

  /// 2026-05-28 (vucko Task #62 + #68): Route minimal über POI patchen.
  ///
  /// Der User soll im selben Routenmodus bleiben (Zufall / Sport / ...),
  /// nur die Geometrie wird lokal so verändert dass sie kurz zum POI
  /// abzweigt und an der Route weiterfährt.
  ///
  /// Algorithmus:
  ///   1. Finde den Punkt auf der aktuellen Route der dem POI am nächsten ist
  ///   2. Window-Range entry- und exit-Index (±~15 Punkte ≈ ~300 m)
  ///   3. Edge A→B-Call: entry → POI → exit (kurzer Detour, ~1-2 s)
  ///   4. Splice: original[0..entry] + patch + original[exit..end]
  ///   5. RouteResult lokal updaten, neu zeichnen
  ///
  /// Wenn POI < 30 m an der Route ist → kein Reroute nötig.
  Future<void> _addPoiAsWaypointAndReroute(RoutePoi poi) async {
    if (!mounted || _disposed) return;
    final activeRoute = _lastRouteResult;
    if (activeRoute == null || activeRoute.coordinates.length < 8) {
      TopToast.show(
        context,
        message: 'Erst eine Route berechnen.',
        icon: Icons.info_outline_rounded,
        duration: const Duration(seconds: 3),
      );
      return;
    }
    final coords = activeRoute.coordinates;
    // 1. Find nearest point on route to POI.
    var nearestIdx = 0;
    var minDistMeters = double.infinity;
    for (var i = 0; i < coords.length; i++) {
      final c = coords[i];
      if (c.length < 2) continue;
      final d = geo.Geolocator.distanceBetween(
        poi.latitude,
        poi.longitude,
        c[1],
        c[0],
      );
      if (d < minDistMeters) {
        minDistMeters = d;
        nearestIdx = i;
      }
    }
    // 2. Schon auf der Route → kein Reroute nötig.
    if (minDistMeters < 30) {
      TopToast.show(
        context,
        message: 'Die ${poi.type.label} liegt schon direkt an deiner Route.',
        icon: Icons.check_circle_outline_rounded,
        duration: const Duration(seconds: 3),
      );
      return;
    }
    // 3. Wenn extrem weit weg (> 8 km) → User-Warnung, lieber neue Route bauen.
    if (minDistMeters > 8000) {
      TopToast.show(
        context,
        message:
            '${poi.type.label} liegt ${(minDistMeters / 1000).toStringAsFixed(1)} km abseits — bitte als neuen Stopp planen.',
        icon: Icons.warning_amber_rounded,
        duration: const Duration(seconds: 4),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    TopToast.show(
      context,
      message: 'Route wird minimal über die ${poi.type.label} angepasst…',
      icon: Icons.add_road_rounded,
      duration: const Duration(seconds: 3),
    );
    // 4. Window-Range — kleinerer Window bei kleinerer Route.
    final windowSize = math.max(5, math.min(20, coords.length ~/ 12));
    final entryIdx = math.max(0, nearestIdx - windowSize);
    final exitIdx = math.min(coords.length - 1, nearestIdx + windowSize);
    final entryCoord = coords[entryIdx];
    final exitCoord = coords[exitIdx];
    try {
      // 5. Patch-Call. Wir nutzen direct-A→B (Standard-Profil) damit der
      // Detour kurz bleibt — nicht das Sport-Profil das gerne extra Kurven
      // macht.
      final subscriptionTier = RouteService.resolveEffectiveSubscriptionTier(
        isTesterOrBeta: true,
      );
      final patch = await _routeService.generatePointToPoint(
        startPosition: geo.Position(
          latitude: entryCoord[1],
          longitude: entryCoord[0],
          timestamp: DateTime.now(),
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
        destinationLat: exitCoord[1],
        destinationLng: exitCoord[0],
        mode: 'Standard',
        scenic: false,
        routeVariant: 0,
        avoidHighways: _activeAvoidHighways || _avoidHighways,
        forceFreshVariant: true,
        subscriptionTier: subscriptionTier,
        intermediateWaypoints: [
          {'latitude': poi.latitude, 'longitude': poi.longitude},
        ],
      );
      if (!mounted) return;
      // 6. Splice: erste Hälfte + patch + zweite Hälfte.
      final patchCoords = patch.coordinates;
      if (patchCoords.length < 2) {
        throw StateError('patch empty');
      }
      final newCoords = <List<double>>[
        ...coords.sublist(0, entryIdx).map(List<double>.from),
        ...patchCoords.map(List<double>.from),
        ...coords.sublist(exitIdx + 1).map(List<double>.from),
      ];
      // Approximate-distance: Original-Distance ± patch-delta.
      final originalDistanceM =
          activeRoute.distanceMeters ?? (activeRoute.distanceKm ?? 0) * 1000;
      final removedSegmentM = _approximateSegmentDistanceMeters(
        coords,
        entryIdx,
        exitIdx,
      );
      final patchDistanceM =
          patch.distanceMeters ?? ((patch.distanceKm ?? 0) * 1000);
      final newDistanceM =
          (originalDistanceM - removedSegmentM + patchDistanceM).clamp(
            0.0,
            double.infinity,
          );
      final geometry = <String, dynamic>{
        'type': 'LineString',
        'coordinates': newCoords,
      };
      final newRoute = RouteResult(
        geoJson: json.encode(geometry),
        geometry: geometry,
        coordinates: newCoords,
        maneuvers: activeRoute.maneuvers,
        distanceMeters: newDistanceM,
        durationSeconds: activeRoute.durationSeconds,
        distanceKm: newDistanceM / 1000.0,
        speedLimits: activeRoute.speedLimits,
        edgeMeta: {
          ...activeRoute.edgeMeta,
          'via_poi_id': poi.id,
          'via_poi_label': poi.type.label,
          'patch_applied': true,
        },
      );
      _lastRouteResult = newRoute;
      _sessionRouteResult = newRoute;
      setState(() {
        _fullRouteCoordinates = newCoords;
        _remainingRouteCoordinates = newCoords;
        _routeGeoJson = json.encode(geometry);
        _routeDistance = newDistanceM;
        _remainingDistance = newDistanceM;
      });
      await _drawRoute(geometry, animateRouteDraw: false);
      if (!mounted) return;
      // Map aktuelle POI-Liste merken, der POI ist jetzt „auf der Route".
      // Beim nächsten POI-Tap zeigt das Sheet „Aus Route entfernen".
      TopToast.show(
        context,
        message:
            'Route führt jetzt über die ${poi.type.label} (${minDistMeters.round()} m Detour).',
        icon: Icons.check_circle_outline_rounded,
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      debugPrint('[CruiseMode] POI-Route-Patch fehlgeschlagen: $e');
      if (!mounted) return;
      TopToast.show(
        context,
        message: 'Route konnte nicht angepasst werden — versuch es nochmal.',
        icon: Icons.error_outline_rounded,
        duration: const Duration(seconds: 4),
      );
    }
  }

  /// Hilfsfunktion: Summiert die Distanz zwischen [startIdx] und [endIdx]
  /// in der Coordinates-Liste (kompakter Haversine-Sum).
  double _approximateSegmentDistanceMeters(
    List<List<double>> coords,
    int startIdx,
    int endIdx,
  ) {
    if (startIdx >= endIdx) return 0.0;
    var sum = 0.0;
    for (var i = startIdx; i < endIdx && i + 1 < coords.length; i++) {
      final a = coords[i];
      final b = coords[i + 1];
      if (a.length < 2 || b.length < 2) continue;
      sum += geo.Geolocator.distanceBetween(a[1], a[0], b[1], b[0]);
    }
    return sum;
  }

  /// Entfernt einen POI aus den aktuellen Round-Trip-Wegpunkten und triggert
  /// einen Reroute.
  Future<void> _removePoiFromRoute(RoutePoi poi) async {
    if (!mounted || _disposed) return;
    final removedIndex = _roundTripWaypoints.indexWhere((wp) {
      final dist = geo.Geolocator.distanceBetween(
        poi.latitude,
        poi.longitude,
        wp.latitude,
        wp.longitude,
      );
      return dist < 50;
    });
    if (removedIndex < 0) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _roundTripWaypoints.removeAt(removedIndex);
      if (_roundTripWaypoints.isEmpty) {
        _planningType = 'Zufall';
        _roundTripWaypointOrigin = 'manual';
      }
    });
    TopToast.show(
      context,
      message: '${poi.type.label} entfernt — Route wird neu berechnet…',
      icon: Icons.remove_circle_outline_rounded,
      duration: const Duration(seconds: 3),
    );
    await _generateRoute();
  }

  /// 2026-05-24 (vucko Task #50): First-Run-Tutorial — Google-Maps-Stil
  /// Hinweis dass Tankstellen jetzt auf der Map sichtbar sind, Settings-Link
  /// für Filter.
  Future<void> _showPoiFirstRunTutorial() async {
    if (!mounted || PoiSettingsService.instance.tutorialSeen) return;
    await PoiSettingsService.instance.markTutorialSeen();
    if (!mounted) return;
    TopToast.show(
      context,
      message:
          '⛽ Tankstellen erscheinen automatisch auf der Karte — Filter in Einstellungen',
      icon: Icons.local_gas_station_rounded,
      duration: const Duration(seconds: 5),
    );
  }

  // 2026-05-24 (vucko Task #45): Hazard-Check im Hintergrund nach Route-Build.
  Future<void> _checkHazardsInBackground(List<List<double>> coords) async {
    if (coords.length < 2) return;
    try {
      final hazards = await RoadHazardService.instance.fetchHazardsAlongRoute(
        coordinates: coords,
        bufferMeters: 90,
      );
      if (!mounted) return;
      setState(() {
        _roadHazards = hazards;
        _hazardCheckDone = true;
      });
      // Task #66: Crowd+OSM Baustellen-Layer als Live-Quelle parallel zum
      // Toast laden. Liefert Marker, Geofence-Trigger und Voting.
      unawaited(_loadConstructionReports(coords));
    } catch (_) {
      // silent fail
    }
  }

  /// 2026-05-28 (vucko Task #66): Construction-Reports für die Route laden.
  /// Wird im Hintergrund parallel zum Road-Hazard-Check ausgeführt.
  Future<void> _loadConstructionReports(List<List<double>> coords) async {
    if (coords.length < 2) return;
    try {
      // bbox um die Route mit kleinem Puffer (0.018° ≈ 2 km).
      double minLat = coords.first[1], maxLat = coords.first[1];
      double minLng = coords.first[0], maxLng = coords.first[0];
      for (final c in coords) {
        if (c[1] < minLat) minLat = c[1];
        if (c[1] > maxLat) maxLat = c[1];
        if (c[0] < minLng) minLng = c[0];
        if (c[0] > maxLng) maxLng = c[0];
      }
      final reports = await ConstructionReportService.instance.fetchInBbox(
        southLat: minLat - 0.018,
        westLng: minLng - 0.018,
        northLat: maxLat + 0.018,
        eastLng: maxLng + 0.018,
      );
      if (!mounted) return;
      // 2026-05-28 (vucko Task #74): Buffer 90→200m. Vorarlberger Bauarbeiten
      // sind oft als ein einzelner Way getaggt der nicht exakt auf den
      // Straßenmittel-Punkt liegt → 90m war zu eng und filterte echte
      // Treffer raus (User-Beschwerde Klaus-Götzis).
      final onRoute = ConstructionReportService.instance.filterToRoute(
        reports: reports,
        routeCoordinates: coords,
        bufferMeters: 200,
      );
      setState(() {
        _routeConstructions = onRoute;
      });
      _constructionGeofence.setReports(onRoute);
      debugPrint(
        '[CruiseMode] Baustellen geladen: ${reports.length} bbox, '
        '${onRoute.length} auf Route.',
      );
    } catch (e) {
      debugPrint('[CruiseMode] Construction-Load fehlgeschlagen: $e');
    }
  }

  /// 2026-05-28 (vucko Task #66): Marker-Widget — Orange Pulse-Kreis.
  Widget _buildConstructionMarker(ConstructionReport c) {
    const accent = Color(0xFFFF9500);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: accent, width: 2.2),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.6),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.construction_rounded, size: 18, color: accent),
    );
  }

  /// 2026-05-28 (vucko Task #66): Geofence-Tick pro Position-Update.
  /// Wenn der User in eine Trigger-Zone kommt → Bottom-Sheet zeigen.
  /// Nur eine Baustelle gleichzeitig (verhindert Stack).
  void _processConstructionGeofence(double lat, double lng) {
    if (!_isRouteConfirmed) return;
    if (_routeConstructions.isEmpty) return;
    if (_activeConstructionAlertId != null) return;
    final entered = _constructionGeofence.processPosition(
      latitude: lat,
      longitude: lng,
    );
    if (entered.isEmpty || !mounted) return;
    final report = entered.first;
    _activeConstructionAlertId = report.id;
    unawaited(
      ConstructionAlertSheet.show(context, report).then((_) {
        _activeConstructionAlertId = null;
      }),
    );
  }

  // 2026-05-24 (vucko Task #44): POI-Toggle (Tankstellen entlang Route).
  /// 2026-05-24 (vucko Task #49): POI-Toggle — Marker IN/AUS auf der Map
  /// statt Bottom-Sheet (Google-Maps-Stil). Bottom-Sheet bleibt nur
  /// als Sekundär-Aktion auf langes Drücken.
  /// 2026-05-28 (vucko Task #75): Öffnet das POI-Filter-Bottom-Sheet.
  /// Nach dem Schließen werden die POIs nach den aktuellen Filtern neu
  /// geladen (oder gelöscht falls alle deaktiviert).
  Future<void> _openPoiFilter() async {
    if (!mounted || _disposed) return;
    HapticFeedback.selectionClick();
    await PoiFilterSheet.show(context);
    if (!mounted || _disposed) return;
    final anyEnabled = PoiSettingsService.instance.anyEnabled;
    if (!anyEnabled) {
      setState(() {
        _routePois = const [];
        _poisVisible = false;
      });
      return;
    }
    // 2026-05-28 (vucko Task #78): Wenn Route da → entlang Route laden.
    // Wenn keine Route → viewport-basiert laden (was der User gerade sieht).
    final hasRoute = _fullRouteCoordinates.length >= 2;
    setState(() => _poisVisible = true);
    if (hasRoute) {
      await _loadPoisFromSettings(_fullRouteCoordinates);
    } else {
      await _loadPoisInViewport();
    }
  }

  /// 2026-05-28 (vucko Task #78): POIs für aktuelle Map-Sichtbarkeit laden.
  /// Wird ausgeführt wenn der User vor einer Route bereits Tankstellen etc.
  /// sehen will (z.B. um eine Tankstelle als Start zu wählen).
  ///
  /// bbox = aktuelle Map-Camera-Bounds; Buffer 0 weil wir wirklich nur
  /// das zeigen wollen was der User sieht.
  /// 2026-06-02 (vucko): Debounced Auto-Refresh der Viewport-POIs beim
  /// Schwenken/Zoomen. Nur beim Planen/Browsen (nicht während aktiver
  /// Navigation — da bleiben die Routen-POIs), nur wenn POIs aktiviert sind.
  /// So sieht man beim Rauszoomen mehr POIs über die ganze sichtbare Karte,
  /// ohne Overpass mit Dauer-Queries zu überlasten.
  void _scheduleViewportPoiRefresh() {
    if (_isRouteConfirmed) return;
    if (!PoiSettingsService.instance.anyEnabled) return;
    _viewportPoiDebounce?.cancel();
    _viewportPoiDebounce = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || _disposed) return;
      if (_isRouteConfirmed || _poisLoading) return;
      if (!PoiSettingsService.instance.anyEnabled) return;
      unawaited(_loadPoisInViewport(silent: true));
    });
  }

  Future<void> _loadPoisInViewport({bool silent = false}) async {
    if (!mounted || _disposed) return;
    if (_poisLoading) return;
    setState(() => _poisLoading = true);
    try {
      LatLngBounds? bounds;
      if (_useMapLibre) {
        final b = await _mlController?.visibleBounds();
        if (b != null) bounds = LatLngBounds(b[0], b[1]);
      } else {
        try {
          bounds = _mapController.camera.visibleBounds;
        } catch (_) {}
      }
      if (bounds == null) {
        // Karte nicht ready — Fallback: ~5km Radius um User-Position.
        final user = _userLocation;
        if (user == null) return;
        bounds = LatLngBounds(
          LatLng(user.latitude - 0.04, user.longitude - 0.06),
          LatLng(user.latitude + 0.04, user.longitude + 0.06),
        );
      }
      final samples = <List<double>>[
        [bounds.west, bounds.north],
        [bounds.east, bounds.north],
        [bounds.east, bounds.south],
        [bounds.west, bounds.south],
        [(bounds.west + bounds.east) / 2, (bounds.north + bounds.south) / 2],
      ];
      final pois = await RoutePoiService.instance.fetchPoisAlongRoute(
        coordinates: samples,
        types: PoiSettingsService.instance.enabledTypes,
        // Großer Buffer: wir wollen die ganze sichtbare Fläche, nicht nur
        // entlang einer (fiktiven) Linie.
        bufferMeters: 5000,
        maxResults: 200,
      );
      if (!mounted) return;
      setState(() {
        _routePois = pois;
        _poisLoading = false;
      });
      if (pois.isEmpty && !silent) {
        TopToast.show(
          context,
          message: 'Keine POIs im sichtbaren Bereich.',
          icon: Icons.info_outline_rounded,
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      debugPrint('[CruiseMode] Viewport-POI-Load fehlgeschlagen: $e');
      if (mounted) setState(() => _poisLoading = false);
    }
  }

  /// 2026-05-28 (vucko Task #79): Gemeinsame FAB-Spalte für Pre-Route- UND
  /// Navigation-State. Verschwindet animiert (fade + slide-out-right) wenn
  /// das Strecken-Setup hochgezogen ist (_configCollapsed == false). Während
  /// der Animation und bei voll-versteckt sind die FABs nicht klickbar.
  ///
  /// [hasRoute] true wenn Cruise-Mode in Navigation-State ist; dann werden
  /// zusätzlich Simulation + Route-Übersicht gezeigt.
  Widget _buildFabColumn({required bool hasRoute}) {
    // Bei hochgezogenem Setup-Sheet: FABs ausblenden + nicht klickbar.
    // 2026-05-28 (vucko Task #80): Im Wegpunkte-Modus (Pre-Route) komplett
    // ausblenden, weil die Wegpunkt-Spalte rechts oben jetzt eine
    // integrierte Right-Rail inkl. POI/Voice/Camera-Lock zeigt. Das
    // verhindert Überlappung der beiden Spalten am rechten Bildschirmrand.
    final hasErrorBanner = _routeSearchNoticeTitle != null;
    final waypointRailActive =
        !hasRoute &&
        _isWaypointPlanning &&
        !_showRouteInfoBanner &&
        !hasErrorBanner;
    // 2026-06-02 (vucko): POI-/Config-Button jetzt AUCH vor der Fahrt /
    // während der Routenplanung erreichbar (User-Wunsch: „über die ganze Karte
    // einstellen, nicht erst bei bestätigter Route"). Vorher pre-route nur
    // sichtbar, wenn das Setup-Sheet eingeklappt war (_configCollapsed) — dadurch
    // wirkte der Button, als käme er erst nach der Routenbestätigung. Jetzt nur
    // noch im Wegpunkte-Modus ausgeblendet, weil dort die rechte Wegpunkt-Rail
    // bereits POI/Voice/Camera zeigt (sonst Doppel-Spalte, Task #80).
    final hidden = waypointRailActive;
    return Positioned(
      right: 16,
      bottom: hasRoute ? 260 : 240,
      child: IgnorePointer(
        ignoring: hidden,
        child: AnimatedSlide(
          offset: hidden ? const Offset(1.4, 0) : Offset.zero,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: hidden ? 0 : 1,
            duration: const Duration(milliseconds: 180),
            // 2026-05-28 (vucko Task #79.1): center-alignment damit alle
            // FABs perfekt auf derselben vertikalen Achse stehen — auch
            // wenn intern verschiedene Bubble-Größen verwendet würden.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Route-Übersicht — nur wenn Route da
                if (hasRoute)
                  _FabBubble(
                    heroTag: 'overview_fab',
                    icon: Icons.map_outlined,
                    color: const Color(0xFF2D3138),
                    onPressed: _showRouteOverview,
                  ),
                // POI-Filter — IMMER sichtbar (auch Pre-Route)
                AnimatedBuilder(
                  animation: PoiSettingsService.instance,
                  builder: (context, _) {
                    final active = PoiSettingsService.instance.anyEnabled;
                    return _FabBubble(
                      heroTag: 'pois_fab',
                      icon: Icons.tune_rounded,
                      color: active
                          ? AppAccentColors.accent
                          : const Color(0xFF2D3138),
                      onPressed: _openPoiFilter,
                      loading: _poisLoading,
                    );
                  },
                ),
                // Voice-Mode-Cycle — IMMER sichtbar
                AnimatedBuilder(
                  animation: VoiceSettingsService.instance,
                  builder: (context, _) {
                    final mode = VoiceSettingsService.instance.mode;
                    final (icon, color) = switch (mode) {
                      VoiceMode.off => (
                        Icons.volume_off_rounded,
                        const Color(0xFF2D3138),
                      ),
                      VoiceMode.important => (
                        Icons.volume_down_rounded,
                        const Color(0xFFFBBF24),
                      ),
                      VoiceMode.all => (
                        Icons.volume_up_rounded,
                        AppAccentColors.accent,
                      ),
                    };
                    return _FabBubble(
                      heroTag: 'voice_toggle_fab',
                      icon: icon,
                      color: color,
                      onPressed: () async {
                        await VoiceSettingsService.instance.cycleMode();
                        HapticFeedback.selectionClick();
                        if (!context.mounted) return;
                        final newMode = VoiceSettingsService.instance.mode;
                        final newLabel = switch (newMode) {
                          VoiceMode.off => 'Stumm',
                          VoiceMode.important => 'Nur Wichtiges',
                          VoiceMode.all => 'Alle Ansagen',
                        };
                        TopToast.show(
                          context,
                          message: 'Sprache: $newLabel',
                          icon: switch (newMode) {
                            VoiceMode.off => Icons.volume_off_rounded,
                            VoiceMode.important => Icons.volume_down_rounded,
                            VoiceMode.all => Icons.volume_up_rounded,
                          },
                        );
                      },
                    );
                  },
                ),
                // Camera-Lock / Recenter — IMMER sichtbar
                _FabBubble(
                  heroTag: 'recenter_map_fab',
                  icon: _isCameraLocked ? Icons.explore : Icons.explore_off,
                  color: _isCameraLocked
                      ? AppAccentColors.accent
                      : const Color(0xFF2D3138),
                  onPressed: _toggleCameraLock,
                  big: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 2026-05-28 (vucko Task #75): _togglePois bleibt für Backwards-
  // Compatibility (z.B. wenn anderswo aufgerufen), wird aber durch
  // _openPoiFilter ersetzt. Wird vom Linter als unused erkannt — bewusst
  // behalten falls extern getriggert.
  // ignore: unused_element
  Future<void> _togglePois() async {
    if (_poisLoading) return;
    final newState = !_poisVisible;
    if (!newState) {
      setState(() {
        _poisVisible = false;
        _routePois = const [];
      });
      return;
    }
    if (_fullRouteCoordinates.length < 2) {
      TopToast.show(
        context,
        message: 'Erst eine Route berechnen',
        icon: Icons.info_outline,
      );
      return;
    }
    final types = PoiSettingsService.instance.anyEnabled
        ? PoiSettingsService.instance.enabledTypes
        : _poiTypes;
    setState(() => _poisLoading = true);
    try {
      final pois = await RoutePoiService.instance.fetchPoisAlongRoute(
        coordinates: _fullRouteCoordinates,
        types: types,
        bufferMeters: 250,
        maxResults: 50,
      );
      if (!mounted) return;
      setState(() {
        _routePois = pois;
        _poisVisible = true;
        _poisLoading = false;
      });
      if (pois.isEmpty) {
        TopToast.show(
          context,
          message: 'Keine POIs entlang dieser Route gefunden',
          icon: Icons.search_off,
        );
      } else {
        TopToast.show(
          context,
          message: '${pois.length} POIs auf der Karte sichtbar',
          icon: Icons.place_outlined,
          duration: const Duration(milliseconds: 2200),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _poisLoading = false);
    }
  }

  // 2026-05-24 (vucko): Bottom-Sheet ist nicht mehr standard Workflow.
  // Bleibt als optionaler Helper für Listing-View (z.B. Long-Press FAB).
  // ignore: unused_element
  void _showPoiBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14181F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14, left: 0, right: 0),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Row(
                children: [
                  Icon(
                    Icons.local_gas_station_rounded,
                    color: AppAccentColors.accent,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_routePois.length} POIs entlang der Route',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _routePois.length,
                  separatorBuilder: (ctx, _) => Divider(
                    color: Colors.white.withValues(alpha: 0.06),
                    height: 1,
                  ),
                  itemBuilder: (_, i) {
                    final p = _routePois[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: AppAccentColors.accent.withValues(
                          alpha: 0.20,
                        ),
                        child: Text(
                          p.type.emoji,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      title: Text(
                        p.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        '${p.distanceFromRouteMeters.round()}m abseits'
                        '${p.openingHours != null ? "  ·  ${p.openingHours}" : ""}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 11.5,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 2026-05-24 (vucko Task #39): Manöver-TTS-Ansage.
  // distMeters=0 → "Jetzt links" / "Jetzt rechts"
  // distMeters>0 → "In Xm links abbiegen"
  void _speakManeuverAnnouncement(
    int distMeters, {
    required bool important,
    bool interrupt = false,
    String? overrideText,
  }) {
    // 2026-06-12 (vucko): Fester Ansagetext (z. B. "Bitte wenden") — die
    // regulaere Instruktion waere in dem Moment irrefuehrend.
    if (overrideText != null) {
      if (important) {
        unawaited(
          TtsService.instance.speakImportant(
            overrideText,
            interrupt: interrupt,
          ),
        );
      } else {
        unawaited(TtsService.instance.speakOptional(overrideText));
      }
      return;
    }
    final maneuver = _activeVisibleManeuver();
    if (maneuver == null) return;
    // 2026-06-05 (vucko Task #6): NUR die reine instruction (ohne Distanz) als
    // Voice-Quelle. maneuver.announcement enthält bereits eine Distanz → der alte
    // Fallback doppelte sie zu „In 287m In 300m rechts abbiegen". Ist instruction
    // leer, gar nicht ansagen.
    final raw = maneuver.instruction.trim();
    if (raw.isEmpty) return;
    // Distanz auf SAUBERE Stufen runden statt krummer Live-Werte („In 287m" →
    // „In 300 Metern"). „Metern" ausgeschrieben für klare TTS-Aussprache.
    final String text;
    if (distMeters <= 30) {
      text = 'Jetzt $raw';
    } else {
      final rounded = distMeters < 250
          ? 200
          : distMeters < 400
          ? 300
          : ((distMeters / 100).round() * 100);
      text = 'In $rounded Metern $raw';
    }
    if (important) {
      unawaited(TtsService.instance.speakImportant(text, interrupt: interrupt));
    } else {
      unawaited(TtsService.instance.speakOptional(text));
    }
  }

  String? _currentCarManeuverText() {
    // 2026-06-13 (vucko G1): off-route/Reroute → CarPlay zeigt „Neuberechnung"
    // statt der veralteten Abbiege-Anweisung (wie Google).
    if (_isReroutingBannerActive) return 'Neuberechnung';
    final maneuver = _activeVisibleManeuver();
    if (maneuver == null) return null;
    return maneuver.instruction.isNotEmpty
        ? maneuver.instruction
        : maneuver.announcement;
  }

  /// Maschinenlesbarer Manöver-Typ (links/rechts/Kreisverkehr…) für die
  /// Auto-Displays — abgeleitet aus dem Icon des nächsten Manövers.
  String? _currentCarManeuverKind() {
    if (_isReroutingBannerActive) return null;
    final maneuver = _activeVisibleManeuver();
    if (maneuver == null) return null;
    return CarRouteBridgeService.maneuverKindFromIcon(maneuver.icon);
  }

  bool _updateRemainingDistanceAndDuration({RouteWindowMatch? routeMatch}) {
    final previousDistance = _remainingDistance;
    if (_fullRouteCoordinates.length < 2) {
      _remainingDistance = 0;
      _remainingDuration = 0;
      return previousDistance != _remainingDistance;
    }

    // Verbleibende Distanz ab aktuellem Index bis Ende summieren
    final dist = _calculateRemainingRouteDistance(routeMatch: routeMatch);
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

    if (previousDistance == null) return true;
    return (previousDistance - dist).abs() >= 5.0;
  }

  double _calculateRemainingRouteDistance({RouteWindowMatch? routeMatch}) {
    final segmentIndex = routeMatch?.segmentIndex;
    final segmentFraction = routeMatch?.segmentFraction;
    if (segmentIndex != null &&
        segmentFraction != null &&
        segmentIndex >= 0 &&
        segmentIndex < _fullRouteCoordinates.length - 1) {
      final c1 = _fullRouteCoordinates[segmentIndex];
      final c2 = _fullRouteCoordinates[segmentIndex + 1];
      final segmentMeters = geo.Geolocator.distanceBetween(
        c1[1],
        c1[0],
        c2[1],
        c2[0],
      );
      final fraction = segmentFraction.clamp(0.0, 1.0).toDouble();
      var dist = segmentMeters * (1.0 - fraction);
      for (
        var i = segmentIndex + 1;
        i < _fullRouteCoordinates.length - 1;
        i++
      ) {
        final next1 = _fullRouteCoordinates[i];
        final next2 = _fullRouteCoordinates[i + 1];
        dist += geo.Geolocator.distanceBetween(
          next1[1],
          next1[0],
          next2[1],
          next2[0],
        );
      }
      return dist;
    }

    if (_currentRouteIndex >= _fullRouteCoordinates.length - 1) {
      return 0.0;
    }

    var dist = 0.0;
    for (
      var i = _currentRouteIndex;
      i < _fullRouteCoordinates.length - 1;
      i++
    ) {
      final c1 = _fullRouteCoordinates[i];
      final c2 = _fullRouteCoordinates[i + 1];
      dist += geo.Geolocator.distanceBetween(c1[1], c1[0], c2[1], c2[0]);
    }
    return dist;
  }

  /// Berechnet eine neue Route von der aktuellen Position zurück zur Originalroute.
  /// Nutzt einen Punkt weiter voraus auf der Route als Ziel und berechnet via
  /// Mapbox eine befahrbare Straßenroute (keine Luftlinie).
  ///
  /// 2026-06-10 (vucko Reroute-Retry): Schlägt der komplette Zyklus fehl, gibt
  /// es EINEN automatischen zweiten Zyklus mit FRISCHEM GPS-Fix — der erste
  /// Fehlschlag kann an einer veralteten/ungenauen Position liegen. Erst wenn
  /// auch der Retry scheitert, sieht der User die (ursachen-spezifische)
  /// Fehlermeldung.
  /// Frischeste verfügbare Start-Position für Reroute-Requests/-Commits:
  /// Kalman-Prediction des Smoothers mit kleinem Vorhalt (kompensiert die
  /// Edge-Latenz), synchron ohne GPS-Roundtrip. Fallback: [fallback].
  geo.Position _freshRerouteStartPosition(
    geo.Position fallback, {
    Duration lead = const Duration(milliseconds: 800),
  }) {
    if (kIsWeb) return fallback;
    final base = _nativeSmoother.current;
    if (base == null) return fallback;
    final p = _nativeSmoother.predict(DateTime.now().add(lead));
    if (p.lat == 0 && p.lng == 0) return fallback;
    return geo.Position(
      latitude: p.lat,
      longitude: p.lng,
      timestamp: DateTime.now(),
      accuracy: base.accuracy,
      altitude: base.altitude,
      altitudeAccuracy: base.altitudeAccuracy,
      heading: _nativeSmoother.hasValidHeading ? p.heading : base.heading,
      headingAccuracy: base.headingAccuracy,
      speed: _nativeSmoother.speed,
      speedAccuracy: base.speedAccuracy,
    );
  }

  Future<void> _rerouteToOriginalRoute(geo.Position position) async {
    if (_isRerouting) return;
    _isRerouting = true;
    _rerouteStartedAt = DateTime.now();
    _pendingChainedReroute = false;
    // 2026-06-13 (vucko Reroute-Videos): NIE mit der (bis zu 3s alten)
    // Erkennungs-Position routen. Smoother-Prediction mit 800ms-Vorhalt →
    // die neue Route startet dort, wo der Fahrer beim Commit WIRKLICH ist,
    // nicht 100-300m hinter ihm.
    position = _freshRerouteStartPosition(position);
    final remainingDistanceBeforeMeters = _remainingDistance ?? _routeDistance;
    final etaBeforeSeconds = _remainingDuration ?? _routeDuration;

    try {
      if (!await _hasConnectivityForReroute()) {
        _publishOfflineRerouteFallback(
          remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
          etaBeforeSeconds: etaBeforeSeconds,
        );
        return;
      }

      // 2026-06-13 (vucko J4-Doppelbanner): KEIN separater Reroute-Toast mehr.
      // Das obere Manöver-Banner zeigt während _isRerouting bereits
      // „Neuberechnung — Route wird angepasst". Der zusätzliche TopToast
      // („Route wird neu berechnet — bitte weiterfahren") doppelte exakt diese
      // Meldung → zwei überlappende Banner im Video.
      final firstCycleOk = await _runRerouteCycle(
        position,
        isRetry: false,
        remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
        etaBeforeSeconds: etaBeforeSeconds,
      );
      if (firstCycleOk || !mounted || _disposed) return;

      // EIN Auto-Retry mit frischem GPS-Fix. Kein stiller Fallback auf die
      // alte Position: Wenn der erste Zyklus wegen Start-Snap scheitert, muss
      // der Retry wirklich mit neuer, genauer GPS-Position laufen.
      // 2026-06-13 (vucko Reroute-Videos): Ist der letzte Smoother-Fix <2s
      // alt, ist die Kalman-Prediction der frischeste verfügbare Fix —
      // SYNCHRON statt bis zu 5s getCurrentPosition-Wartezeit.
      geo.Position retryPosition;
      final smootherBase = kIsWeb ? null : _nativeSmoother.current;
      final smootherAgeMs = smootherBase == null
          ? null
          : DateTime.now().difference(smootherBase.timestamp).inMilliseconds;
      if (smootherAgeMs != null && smootherAgeMs < 2000) {
        retryPosition = _freshRerouteStartPosition(position);
        debugPrint(
          '[CruiseMode][RerouteRetry] Smoother-Prediction als Frisch-Fix '
          '(Basis ${smootherAgeMs}ms alt): ${_describeStartFix(retryPosition)}',
        );
      } else {
        try {
          retryPosition = await geo.Geolocator.getCurrentPosition(
            locationSettings: const geo.LocationSettings(
              accuracy: geo.LocationAccuracy.best,
            ),
          ).timeout(const Duration(seconds: 3));
          if (!_isFreshStartFix(retryPosition)) {
            throw TimeoutException(
              'fresh reroute fix stale/inaccurate: ${_describeStartFix(retryPosition)}',
            );
          }
          debugPrint(
            '[CruiseMode][RerouteRetry] Frischer GPS-Fix für Auto-Retry: '
            '${_describeStartFix(retryPosition)}',
          );
        } catch (e) {
          debugPrint(
            '[CruiseMode][RerouteRetry] Frischer Fix fehlgeschlagen '
            '($e) — kein Retry mit alter Position',
          );
          _publishRerouteFailure(
            rerouteReason: 'fresh_fix_unavailable',
            rerouteMode: _isAccessLegActive ? 'rejoin' : 'partial_rebuild',
            remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
            etaBeforeSeconds: etaBeforeSeconds,
            userMessage:
                'Reroute gerade nicht möglich: GPS ist noch nicht präzise genug — bitte weiterfahren',
          );
          return;
        }
      }
      await _runRerouteCycle(
        retryPosition,
        isRetry: true,
        remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
        etaBeforeSeconds: etaBeforeSeconds,
      );
    } finally {
      _isRerouting = false;
      _rerouteStartedAt = null;
      // 2026-06-13 (vucko Reroute-Videos): Der Commit landete nachweislich
      // hinter dem Fahrer (Stale-Check in _commitRerouteResult) → SOFORT mit
      // frischer Position nachrouten statt erst beim nächsten Off-Route-
      // Zyklus (+3s Hysterese +3s Cooldown). Max 2 Ketten.
      if (_pendingChainedReroute && mounted && !_disposed) {
        _pendingChainedReroute = false;
        if (_chainedRerouteCount < 2) {
          _chainedRerouteCount++;
          _lastRerouteTime = null;
          _offRouteSince = null;
          debugPrint(
            '[CruiseMode][Reroute] Commit veraltet → Ketten-Reroute '
            '#$_chainedRerouteCount mit frischer Position',
          );
          unawaited(
            _rerouteToOriginalRoute(_freshRerouteStartPosition(position)),
          );
        } else {
          _chainedRerouteCount = 0;
        }
      }
    }
  }

  /// Ein kompletter Reroute-Zyklus (Ziel-Reroute → Rejoin-Versuche →
  /// garantierter Re-Dock). Gibt `true` zurück, wenn eine Route committed
  /// wurde (oder die UI weg ist), `false` bei Fehlschlag. Die Fehlermeldung an
  /// den User erscheint nur im finalen Versuch (`isRetry == true`) — der erste
  /// Fehlschlag löst stattdessen den Auto-Retry mit frischem Fix aus.
  Future<bool> _runRerouteCycle(
    geo.Position position, {
    required bool isRetry,
    required double? remainingDistanceBeforeMeters,
    required double? etaBeforeSeconds,
  }) async {
    // Ursachen-Protokoll dieses Zyklus — jede Fehlstelle trägt sich ein.
    final cycleFailures = <String>[];
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
      final rerouteAvoidHighways = _effectiveNavigationAvoidHighways;

      // Suche den nächsten Punkt auf der GESAMTEN verbleibenden Route (großes Fenster)
      final globalMatch = findNearestInWindow(
        position: position,
        coordinates: planningCoordinates,
        currentIndex: accessLegMode ? 0 : _currentRouteIndex,
        windowSize: planningCoordinates.length,
        maxJumpMeters: double.infinity,
      );

      final heading = _resolveRerouteHeading(
        position: position,
        planningCoordinates: planningCoordinates,
        nearestIndex: globalMatch.index,
      );
      final rerouteSpeedMps = position.speed.isFinite && position.speed >= 0
          ? position.speed
          : null;
      final rerouteAccuracyMeters =
          position.accuracy.isFinite && position.accuracy > 0
          ? position.accuracy
          : null;

      final smartPlan = _smartRerouteEngine.createPlan(
        currentPosition: position,
        coordinates: planningCoordinates,
        maneuvers: planningManeuvers,
        nearestIndex: globalMatch.index,
        currentHeadingDegrees: heading,
        speedLimits: planningSpeedLimits,
        avoidHighways: rerouteAvoidHighways,
      );

      debugPrint(
        '[CruiseMode] Smart reroute plan: ${smartPlan.debugLabel}, '
        'strategy=${smartPlan.strategy.name}, rejoin=${smartPlan.rejoinIndex}, '
        'heading=${heading.toStringAsFixed(0)}',
      );

      // 2026-06-09 (vucko A→B-Reroute-zum-Ziel): Bei A→B muss das Ziel IMMER bekannt
      // sein, sonst wird der Ziel-Reroute-Zweig übersprungen → der Reroute zielt nur
      // auf die alte Route statt direkt aufs Ziel. Fällt _activeDestinationCoordinate
      // aus (z.B. defekte Gruppen-Metadaten), nimm den letzten Routenpunkt = das
      // geplante Endziel als Fallback.
      final destination =
          _activeDestinationCoordinate ??
          (!_isRoundTrip && _fullRouteCoordinates.length >= 2
              ? _fullRouteCoordinates.last
              : null);
      if (!_isRoundTrip && destination != null && !accessLegMode) {
        // 2026-06-09 (vucko Trip-Skip): Reroute führt durch die VERBLEIBENDEN
        // Zwischenstopps (übersprungene werden automatisch abgehakt) statt
        // stumm direkt zum Endziel.
        final rerouteWaypoints = _remainingWaypointsForReroute(
          position,
          destination,
        );
        final destinationRerouteSeed = Object.hash(
          destination[0].round(),
          destination[1].round(),
          0,
          rerouteAvoidHighways,
          0x44525252,
        );
        RouteResult? destinationResult;
        try {
          destinationResult = await _routeService.generatePointToPoint(
            startPosition: position,
            destinationLat: destination[1],
            destinationLng: destination[0],
            mode: 'Standard',
            scenic: false,
            routeVariant: 0,
            avoidHighways: rerouteAvoidHighways,
            diversitySeed: destinationRerouteSeed,
            forceFreshVariant: true,
            navigationReroute: true,
            candidateBudgetOverride: 1,
            maxSearchMsOverride: 4500,
            currentHeadingDegrees: heading,
            currentSpeedMetersPerSecond: rerouteSpeedMps,
            locationAccuracyMeters: rerouteAccuracyMeters,
            intermediateWaypoints: rerouteWaypoints,
          );
        } catch (e) {
          final cause = _classifyRerouteError(e);
          cycleFailures.add(cause);
          debugPrint(
            '[CruiseMode][RerouteFail] stage=ziel cause=$cause detail=$e',
          );
        }

        // 2026-06-10 (vucko Start-Versatz-Gate): Connector muss am Fahrer
        // beginnen — der Edge-Snap-Bug lieferte Connectors ~758m daneben.
        if (destinationResult != null &&
            destinationResult.coordinates.length >= 2) {
          final destStartOffset = geo.Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            destinationResult.coordinates.first[1],
            destinationResult.coordinates.first[0],
          );
          if (destStartOffset > _rerouteMaxStartOffsetMeters) {
            cycleFailures.add(
              'start_offset(${destStartOffset.toStringAsFixed(0)}m)',
            );
            debugPrint(
              '[CruiseMode][RerouteFail] stage=ziel cause=start_offset '
              'offset=${destStartOffset.toStringAsFixed(0)}m '
              'limit=${_rerouteMaxStartOffsetMeters.toStringAsFixed(0)}m '
              '— Kandidat verworfen',
            );
            destinationResult = null;
          }
        }

        if (destinationResult != null &&
            destinationResult.coordinates.length >= 2) {
          final destinationQuality = validator.validateQuality(
            coordinates: destinationResult.coordinates,
            isRoundTrip: false,
            actualDistanceKm: destinationResult.distanceKm ?? 0,
          );
          final destinationTooFewPoints =
              destinationResult.coordinates.length < 30 &&
              (destinationResult.distanceKm ?? 0) >= 10;
          final highwayViolation = violatesNoHighwayPolicy(
            avoidHighways: rerouteAvoidHighways,
            edgeMeta: destinationResult.edgeMeta,
          );
          // 2026-06-09 (vucko A→B-Reroute-zum-Ziel): Bei A→B ist das ZIEL die
          // Invariante. Wird der saubere Ziel-Kandidat verworfen, NICHT stumm in
          // den Forward-Rejoin durchfallen (der zielt auf die ALTE Route und
          // erreicht das Ziel evtl. nie) — sondern EIN zweiter Versuch mit
          // forceAcceptDirect DIREKT zum Ziel: akzeptiert jede valide Strecke zum
          // Endpunkt (Google/Apple: Reroute zielt immer aufs Ziel). Erst wenn auch
          // das nichts liefert, greift weiter unten der Rejoin/Redock-Fallback.
          RouteResult? acceptedDest;
          if (!destinationQuality.passed ||
              destinationTooFewPoints ||
              highwayViolation) {
            cycleFailures.add(
              'validator_reject(ziel: quality=${!destinationQuality.passed} '
              'fewPoints=$destinationTooFewPoints highway=$highwayViolation)',
            );
            debugPrint(
              '[CruiseMode] Ziel-Reroute QA-verworfen → Force-Accept direkt zum Ziel.',
            );
            try {
              final forced = await _routeService.generatePointToPoint(
                startPosition: position,
                destinationLat: destination[1],
                destinationLng: destination[0],
                mode: 'Standard',
                scenic: false,
                routeVariant: 0,
                avoidHighways: rerouteAvoidHighways,
                forceFreshVariant: true,
                navigationReroute: true,
                forceAcceptDirect: true,
                candidateBudgetOverride: 1,
                maxSearchMsOverride: 6000,
                currentHeadingDegrees: heading,
                currentSpeedMetersPerSecond: rerouteSpeedMps,
                locationAccuracyMeters: rerouteAccuracyMeters,
                intermediateWaypoints: rerouteWaypoints,
              );
              if (forced.coordinates.length >= 2) {
                // Auch der Force-Accept-Connector muss am Fahrer beginnen.
                final forcedStartOffset = geo.Geolocator.distanceBetween(
                  position.latitude,
                  position.longitude,
                  forced.coordinates.first[1],
                  forced.coordinates.first[0],
                );
                if (forcedStartOffset > _rerouteMaxStartOffsetMeters) {
                  cycleFailures.add(
                    'start_offset(${forcedStartOffset.toStringAsFixed(0)}m)',
                  );
                  debugPrint(
                    '[CruiseMode][RerouteFail] stage=ziel_force_accept '
                    'cause=start_offset '
                    'offset=${forcedStartOffset.toStringAsFixed(0)}m '
                    '— Kandidat verworfen',
                  );
                } else {
                  acceptedDest = forced;
                }
              }
            } catch (e) {
              final cause = _classifyRerouteError(e);
              cycleFailures.add(cause);
              debugPrint(
                '[CruiseMode][RerouteFail] stage=ziel_force_accept '
                'cause=$cause detail=$e',
              );
            }
          } else {
            acceptedDest = destinationResult;
          }
          if (acceptedDest != null) {
            final distanceMeters =
                acceptedDest.distanceMeters ??
                _calculatePolylineDistanceMeters(acceptedDest.coordinates);
            final durationSeconds =
                acceptedDest.durationSeconds ??
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
                coordinates: acceptedDest.coordinates,
                maneuvers: acceptedDest.maneuvers,
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                speedLimits: acceptedDest.speedLimits,
                edgeMeta: {...acceptedDest.edgeMeta, ...rerouteMeta},
              ),
              position: position,
              publishToGroup: !accessLegMode,
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
            return true;
          }
        }
      }

      final maxRejoinIndex = math.max(0, planningCoordinates.length - 2);
      final fallbackRejoinIndex = selectForwardRejoinIndex(
        coordinates: planningCoordinates,
        nearestIndex: globalMatch.index,
        currentHeadingDegrees: heading,
        minLookAheadPoints: 55,
        maxLookAheadPoints: 220,
        maxAlignmentDeltaDegrees: 105,
      ).clamp(0, maxRejoinIndex).toInt();

      RouteResult? rerouteResult;
      SmartReroutePlan? acceptedPlan;
      var rejoinIndex = smartPlan.rejoinIndex.clamp(0, maxRejoinIndex).toInt();

      for (var attempt = 0; attempt < 2; attempt++) {
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

        final joinRerouteSeed = Object.hash(
          rejoinPoint[0].round(),
          rejoinPoint[1].round(),
          0,
          rerouteAvoidHighways,
          attempt,
        );
        RouteResult candidate;
        try {
          candidate = await _routeService.generatePointToPoint(
            startPosition: position,
            destinationLat: rejoinPoint[1],
            destinationLng: rejoinPoint[0],
            mode: 'Standard',
            scenic: false,
            routeVariant: 0,
            avoidHighways: rerouteAvoidHighways,
            diversitySeed: joinRerouteSeed,
            forceFreshVariant: true,
            navigationReroute: true,
            candidateBudgetOverride: 1,
            maxSearchMsOverride: 4500,
            currentHeadingDegrees: heading,
            currentSpeedMetersPerSecond: rerouteSpeedMps,
            locationAccuracyMeters: rerouteAccuracyMeters,
          );
        } catch (e) {
          rejoinIndex = math.min(rejoinIndex + 80, maxRejoinIndex).toInt();
          final cause = _classifyRerouteError(e);
          cycleFailures.add(cause);
          debugPrint(
            '[CruiseMode][RerouteFail] stage=rejoin attempt=${attempt + 1} '
            'cause=$cause detail=$e',
          );
          continue;
        }

        if (candidate.coordinates.length < 2) {
          rejoinIndex = math.min(rejoinIndex + 80, maxRejoinIndex).toInt();
          cycleFailures.add('no_route(leere_geometrie)');
          debugPrint(
            '[CruiseMode][RerouteFail] stage=rejoin attempt=${attempt + 1} '
            'cause=no_route(leere_geometrie)',
          );
          continue;
        }

        // 2026-06-10 (vucko Start-Versatz-Gate): Connector muss am Fahrer
        // beginnen (Edge-Snap-Bug lieferte ~758m Versatz).
        final candidateStartOffset = geo.Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          candidate.coordinates.first[1],
          candidate.coordinates.first[0],
        );
        if (candidateStartOffset > _rerouteMaxStartOffsetMeters) {
          rejoinIndex = math.min(rejoinIndex + 80, maxRejoinIndex).toInt();
          cycleFailures.add(
            'start_offset(${candidateStartOffset.toStringAsFixed(0)}m)',
          );
          debugPrint(
            '[CruiseMode][RerouteFail] stage=rejoin attempt=${attempt + 1} '
            'cause=start_offset '
            'offset=${candidateStartOffset.toStringAsFixed(0)}m '
            'limit=${_rerouteMaxStartOffsetMeters.toStringAsFixed(0)}m '
            '— Kandidat verworfen',
          );
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
        final highwayViolation = violatesNoHighwayPolicy(
          avoidHighways: rerouteAvoidHighways,
          edgeMeta: candidate.edgeMeta,
        );
        if (!candidateQuality.passed ||
            candidateTooFewPoints ||
            highwayViolation) {
          rejoinIndex = math.min(rejoinIndex + 80, maxRejoinIndex).toInt();
          cycleFailures.add(
            'validator_reject(rejoin: quality=${!candidateQuality.passed} '
            'fewPoints=$candidateTooFewPoints highway=$highwayViolation)',
          );
          debugPrint(
            '[CruiseMode] Reroute-Attempt ${attempt + 1}: Kandidat verworfen (Qualität/Highway-Policy)',
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
            cycleFailures.add(
              'validator_reject(join_gap ${joinDistance.toStringAsFixed(0)}m)',
            );
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
            cycleFailures.add('validator_reject(join_uturn)');
            debugPrint(
              '[CruiseMode] Reroute-Attempt ${attempt + 1}: Join-U-Turn erkannt, rejoinIndex=$rejoinIndex',
            );
            continue;
          }

          // 2026-06-08 (vucko Task #47): HARTER Naht-Guard gegen die „Bat-Wing".
          // isUTurnJoin prüft nur ein Einzelsegment; rerouteMergeFoldsBack prüft
          // gemitteltes Heading-Reversal UND echte Selbstüberschneidung im Naht-
          // Fenster → fängt auch die Faltung, die der schwache U-Turn-Test durch-
          // lässt. Bei Faltung: weiter vorne andocken (oder verwerfen).
          final foldsBack = rerouteMergeFoldsBack(
            connector: candidate.coordinates,
            tail: planningCoordinates.sublist(
              rejoinIndex,
              math.min(rejoinIndex + 30, planningCoordinates.length),
            ),
          );
          if (foldsBack && rejoinIndex < maxRejoinIndex) {
            rejoinIndex = math.min(rejoinIndex + 80, maxRejoinIndex).toInt();
            cycleFailures.add('validator_reject(merge_folds_back)');
            debugPrint(
              '[CruiseMode] Reroute-Attempt ${attempt + 1}: Merge-Naht faltet zurück, rejoinIndex=$rejoinIndex',
            );
            continue;
          }
          if (foldsBack) {
            // Letzter Rejoin-Index und IMMER NOCH Faltung → diesen Kandidaten
            // NICHT mergen; der garantierte Re-Dock / Fallback übernimmt.
            cycleFailures.add('validator_reject(merge_folds_back_final)');
            debugPrint(
              '[CruiseMode] Reroute-Attempt ${attempt + 1}: Merge-Naht faltet auch am Ende — Kandidat verworfen',
            );
            continue;
          }
        }

        rerouteResult = candidate;
        acceptedPlan = activePlan;
        break;
      }

      // 2026-06-06 (vucko P2-B): GARANTIERTER Re-Dock-Fallback. Lieferten die
      // regulären Connector-Versuche nichts (häufig bei Rundkursen → vorher nur
      // „Keine sichere Reroute" + Spam, ohne dass je etwas passierte), erzwingen
      // wir eine DIREKTE Verbindung vom aktuellen GPS zu einem Vorwärts-Punkt der
      // Originalroute (forceAcceptDirect) und mergen mit dem Original-Rest → der
      // Fahrer dockt smooth wieder an, statt dass das System aufgibt.
      if (rerouteResult == null && mounted && !_disposed) {
        try {
          // 2026-06-06 (vucko P2-Fix): untere Schranke nie > obere — sonst wirft
          // clamp ArgumentError, wenn der Match schon am Routenende sitzt.
          final rejoinUpper = planningCoordinates.length - 1;
          // 2026-06-07 (vucko P-reroute STEP 3): VORWÄRTS-Rejoin verwenden statt
          // blind 400m ab dem rohen Nächsten-Punkt zu laufen. globalMatch.index
          // ist der absolut-nächste Punkt (Voll-Fenster) — auf einem sich selbst
          // überlappenden Rundkurs kann das die RÜCKWEG-Spur sein → der Re-Dock
          // dockte rückwärts an („fährt Nord, zeigt Süd" / verdrehte Linie).
          // fallbackRejoinIndex (oben, mit Heading-/Alignment-Guard berechnet)
          // wählt einen Punkt IN FAHRTRICHTUNG.
          final rejoinIdx = fallbackRejoinIndex
              .clamp(math.min(globalMatch.index + 1, rejoinUpper), rejoinUpper)
              .toInt();
          final rejoinPt = planningCoordinates[rejoinIdx];
          final connector = await _routeService.generatePointToPoint(
            startPosition: position,
            destinationLat: rejoinPt[1],
            destinationLng: rejoinPt[0],
            mode: 'Standard',
            avoidHighways: rerouteAvoidHighways,
            navigationReroute: true,
            forceAcceptDirect: true,
            candidateBudgetOverride: 1,
            maxSearchMsOverride: 4500,
            currentHeadingDegrees: heading,
            currentSpeedMetersPerSecond: rerouteSpeedMps,
            locationAccuracyMeters: rerouteAccuracyMeters,
          );
          final redockTail = planningCoordinates.sublist(rejoinIdx);
          // 2026-06-08 (vucko Task #47): forceAcceptDirect umgeht ALLE Shape-/
          // U-Turn-Gates → der Re-Dock konnte die „Bat-Wing" committen. Auch hier
          // HART gegen Rückfaltung/Selbstüberschneidung der Naht prüfen. Faltet
          // sie zurück → NICHT committen: die alte Route bleibt sichtbar (besser
          // als eine sichtbar kaputte Route), nächster Tick versucht es erneut.
          final redockFolds =
              connector.coordinates.length >= 2 &&
              rerouteMergeFoldsBack(
                connector: connector.coordinates,
                tail: redockTail,
              );
          if (redockFolds) {
            cycleFailures.add('validator_reject(redock_folds_back)');
            debugPrint(
              '[CruiseMode] Garantierter Re-Dock faltet zurück — verworfen, alte Route bleibt',
            );
          }
          // 2026-06-10 (vucko Start-Versatz-Gate): forceAcceptDirect umgeht die
          // Service-Gates NICHT mehr beim Start-Versatz, aber doppelt hält
          // besser — ein Re-Dock-Connector, der nicht am Fahrer beginnt, würde
          // sofort wieder als off-route gelten.
          var redockStartOffsetOk = true;
          if (connector.coordinates.length >= 2) {
            final redockStartOffset = geo.Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              connector.coordinates.first[1],
              connector.coordinates.first[0],
            );
            if (redockStartOffset > _rerouteMaxStartOffsetMeters) {
              redockStartOffsetOk = false;
              cycleFailures.add(
                'start_offset(${redockStartOffset.toStringAsFixed(0)}m)',
              );
              debugPrint(
                '[CruiseMode][RerouteFail] stage=redock cause=start_offset '
                'offset=${redockStartOffset.toStringAsFixed(0)}m '
                'limit=${_rerouteMaxStartOffsetMeters.toStringAsFixed(0)}m '
                '— Re-Dock verworfen, alte Route bleibt',
              );
            }
          }
          if (connector.coordinates.length >= 2 &&
              !redockFolds &&
              redockStartOffsetOk &&
              mounted &&
              !_disposed) {
            final connLen = connector.coordinates.length;
            final tail = redockTail;
            final mergedCoords = <List<double>>[
              ...connector.coordinates,
              ...tail.skip(1),
            ];
            final mergedManeuvers = <RouteManeuver>[
              ...connector.maneuvers,
              for (final m in planningManeuvers)
                if (m.routeIndex >= rejoinIdx)
                  RouteManeuver(
                    latitude: m.latitude,
                    longitude: m.longitude,
                    routeIndex: connLen + (m.routeIndex - rejoinIdx) - 1,
                    icon: m.icon,
                    announcement: m.announcement,
                    instruction: m.instruction,
                    maneuverType: m.maneuverType,
                    roundaboutExitNumber: m.roundaboutExitNumber,
                    roundaboutTurnAngleRad: m.roundaboutTurnAngleRad,
                  ),
            ];
            final dist = _calculatePolylineDistanceMeters(mergedCoords);
            await _commitRerouteResult(
              result: _buildRouteResultFromCoordinates(
                coordinates: mergedCoords,
                maneuvers: mergedManeuvers,
                distanceMeters: dist,
                durationSeconds: _estimateDurationSecondsForDistance(dist),
                speedLimits: connector.speedLimits,
                edgeMeta: {
                  ...connector.edgeMeta,
                  'reroute_mode': 'guaranteed_redock',
                },
              ),
              position: position,
            );
            if (mounted) {
              TopToast.show(
                context,
                message: 'Route neu berechnet — zurück auf Kurs',
                icon: Icons.check_circle,
                duration: const Duration(milliseconds: 2500),
              );
            }
            return true;
          }
        } catch (e) {
          final cause = _classifyRerouteError(e);
          cycleFailures.add(cause);
          debugPrint(
            '[CruiseMode][RerouteFail] stage=redock cause=$cause detail=$e',
          );
        }
      }

      if (!mounted || _disposed) {
        // UI ist weg — kein Retry, keine Meldung.
        return true;
      }
      if (rerouteResult == null || acceptedPlan == null) {
        cycleFailures.add('no_candidate');
        debugPrint(
          '[CruiseMode][RerouteFail] Zyklus gescheitert '
          '(isRetry=$isRetry) causes=${cycleFailures.join(' | ')}',
        );
        if (isRetry) {
          _publishRerouteFailure(
            rerouteReason: 'no_candidate',
            rerouteMode: accessLegMode ? 'rejoin' : 'partial_rebuild',
            remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
            etaBeforeSeconds: etaBeforeSeconds,
            userMessage: _rerouteFailureUserMessage(cycleFailures),
          );
        }
        return false;
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
                roundaboutTurnAngleRad: m.roundaboutTurnAngleRad,
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
                roundaboutTurnAngleRad: m.roundaboutTurnAngleRad,
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
        publishToGroup: !accessLegMode,
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
        });
      } else {
        _clearAccessLegState();
        _sessionRouteStartIndexInActiveRoute = 0;
      }

      if (mounted) {
        // 2026-05-25 (vucko UX): TopToast statt Snackbar — konsistent mit Rest.
        TopToast.show(
          context,
          message: 'Route neu berechnet!',
          icon: Icons.check_circle_rounded,
          duration: const Duration(milliseconds: 2200),
        );
      }
      return true;
    } catch (e, stack) {
      final cause = _classifyRerouteError(e);
      cycleFailures.add(cause);
      debugPrint(
        '[CruiseMode][RerouteFail] Zyklus-Exception (isRetry=$isRetry) '
        'cause=$cause causes=${cycleFailures.join(' | ')} detail=$e',
      );
      debugPrintStack(
        label: '[CruiseMode] Rerouting stacktrace',
        stackTrace: stack,
      );
      if (isRetry) {
        _publishRerouteFailure(
          rerouteReason: 'exception',
          rerouteMode: _isAccessLegActive ? 'rejoin' : 'partial_rebuild',
          remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
          etaBeforeSeconds: etaBeforeSeconds,
          userMessage: _rerouteFailureUserMessage(cycleFailures),
        );
      }
      return false;
    }
  }

  double _resolveRerouteHeading({
    required geo.Position position,
    required List<List<double>> planningCoordinates,
    required int nearestIndex,
  }) {
    double? smoothedHeading;
    if (kIsWeb) {
      if (_webSmoother.hasValidHeading) {
        smoothedHeading = _webSmoother.heading;
      }
    } else if (_nativeSmoother.hasValidHeading) {
      smoothedHeading = _nativeSmoother.heading;
    }
    if (_isUsableHeading(smoothedHeading)) {
      return smoothedHeading! % 360;
    }

    final rawHeading = position.heading;
    final rawAccuracy = position.headingAccuracy;
    if (_isUsableHeading(rawHeading) &&
        (!rawAccuracy.isFinite || rawAccuracy <= 45)) {
      return rawHeading % 360;
    }

    if (planningCoordinates.length >= 2) {
      return routeHeadingAt(
        planningCoordinates,
        nearestIndex.clamp(0, planningCoordinates.length - 1).toInt(),
      );
    }
    return 0.0;
  }

  static bool _isUsableHeading(double? heading) =>
      heading != null && heading.isFinite && heading >= 0 && heading <= 360;

  /// Berechnet die Distanz entlang der Route vom aktuellen Index zum nächsten Manöver.
  int? _activeVisibleManeuverIndex() {
    return selectActiveGuidanceManeuverIndex(
      maneuvers: _maneuvers,
      currentRouteIndex: _currentRouteIndex,
      remainingRouteDistanceMeters: _remainingDistance,
      distanceToFinalTargetMeters: _distanceToFinalTargetMeters,
      startIndex: _activeManeuverIndex,
      arrivalRadiusMeters: _arrivalRadiusMeters,
    );
  }

  RouteManeuver? _activeVisibleManeuver() {
    final index = _activeVisibleManeuverIndex();
    if (index == null) return null;
    return _maneuvers[index.clamp(0, _maneuvers.length - 1).toInt()];
  }

  double? _calculateDistanceToManeuver([RouteManeuver? visibleManeuver]) {
    if (_maneuvers.isEmpty || _fullRouteCoordinates.length < 2) return null;
    final maneuver = visibleManeuver ?? _activeVisibleManeuver();
    if (maneuver == null) return null;
    var targetIndex = maneuver.routeIndex
        .clamp(0, _fullRouteCoordinates.length - 1)
        .toInt();
    // 2026-06-13 (vucko Google/Apple-Bar-Review G2): Ist das sichtbare Manöver
    // bereits hinter dem Puck-Index (überfahren), zeigt Google IMMER das
    // NÄCHSTE noch nicht passierte Manöver — nicht nur die Luftlinie. Das
    // nächste Manöver mit routeIndex > _currentRouteIndex suchen.
    if (targetIndex <= _currentRouteIndex) {
      var nextIdx = -1;
      for (final m in _maneuvers) {
        final mi = m.routeIndex
            .clamp(0, _fullRouteCoordinates.length - 1)
            .toInt();
        if (mi > _currentRouteIndex) {
          nextIdx = mi;
          break;
        }
      }
      // Kein weiteres Manöver (Routenende) → ehrliche Luftlinie zur Route.
      if (nextIdx < 0) {
        return _offRouteGapMeters > 0 ? _offRouteGapMeters : 0;
      }
      targetIndex = nextIdx;
    }

    double dist = 0.0;
    for (var i = _currentRouteIndex; i < targetIndex; i++) {
      final c1 = _fullRouteCoordinates[i];
      final c2 = _fullRouteCoordinates[i + 1];
      dist += geo.Geolocator.distanceBetween(c1[1], c1[0], c2[1], c2[0]);
    }
    // 2026-06-13 (vucko Video Banner-Freeze): off-route kommt die Luftlinie
    // GPS→Route dazu — die Anzeige wächst ehrlich mit, statt einzufrieren.
    return dist + _offRouteGapMeters;
  }

  void _updateActiveManeuver() {
    if (_maneuvers.isEmpty) return;
    // 2026-06-13 (vucko Manöver-26km-Bug): IMMER von 0 das erste Manöver mit
    // routeIndex >= _currentRouteIndex ableiten (statt nur ab dem alten Index
    // vorwärts). Sprang _currentRouteIndex je kurz hoch (Selbstüberlapp-
    // Teleport) und kam zurück, klebte der alte „nur vorwärts"-Index am
    // End-Manöver fest → Banner zeigte „in 26 km abbiegen". Jetzt spiegelt der
    // aktive Index immer den echten Fortschritt wider.
    for (var i = 0; i < _maneuvers.length; i++) {
      if (_maneuvers[i].routeIndex >= _currentRouteIndex) {
        _activeManeuverIndex = i;
        return;
      }
    }
    _activeManeuverIndex = _maneuvers.length - 1;
  }

  // 2026-06-16 (vucko O9): Echte Kreisverkehr-Topologie lazy beim Anfahren
  // holen. Sucht das nächste Kreisverkehr-Manöver ab dem aktiven Index, das
  // noch keine Arm-Winkel hat und <1500m entfernt ist. Liegt das Ergebnis schon
  // im Cache (synchron), wird es sofort angewandt; sonst genau EIN Overpass-Fetch
  // ausgelöst (dedupliziert im Service), dessen Resultat danach ins Manöver
  // gespiegelt wird. Schlägt der Fetch fehl, markieren wir das Manöver mit einer
  // leeren Liste → der Painter fällt sauber auf entry/exit/exit_number zurück und
  // wir versuchen es nicht endlos neu.
  void _maybeEnrichRoundaboutTopology() {
    if (_maneuvers.isEmpty) return;
    final start = _activeManeuverIndex.clamp(0, _maneuvers.length - 1);
    final origin = _userLocation;
    for (var i = start; i < _maneuvers.length; i++) {
      final m = _maneuvers[i];
      if (m.maneuverType != ManeuverType.roundabout) continue;
      if (m.roundaboutArmBearings != null) continue; // schon aufgelöst
      // Nur anfahrende Kreisel (≤1500m) enrichen — spart Calls weit voraus.
      if (origin != null) {
        final d = geo.Geolocator.distanceBetween(
          origin.latitude,
          origin.longitude,
          m.latitude,
          m.longitude,
        );
        if (d > 1500) break; // weitere liegen noch weiter weg → Schluss
      }
      final svc = RoundaboutTopologyService.instance;
      if (svc.isResolved(m.latitude, m.longitude)) {
        _applyRoundaboutTopology(i, svc.cached(m.latitude, m.longitude));
      } else {
        final lat = m.latitude;
        final lng = m.longitude;
        svc.fetch(lat, lng).then((topo) {
          if (!mounted) return;
          // Index könnte inzwischen anders sein → über Koordinate wiederfinden.
          for (var j = 0; j < _maneuvers.length; j++) {
            final mm = _maneuvers[j];
            if (mm.maneuverType == ManeuverType.roundabout &&
                mm.roundaboutArmBearings == null &&
                (mm.latitude - lat).abs() < 1e-6 &&
                (mm.longitude - lng).abs() < 1e-6) {
              _applyRoundaboutTopology(j, topo);
              break;
            }
          }
        });
      }
      return; // pro Tick nur das nächste Manöver behandeln
    }
  }

  void _applyRoundaboutTopology(int index, RoundaboutTopology? topo) {
    if (index < 0 || index >= _maneuvers.length) return;
    if (_maneuvers[index].roundaboutArmBearings != null) return;
    // Auch bei null (kein Kreisel/Netzfehler) eine leere Liste setzen →
    // markiert „aufgelöst", Painter nutzt sauber den Geometrie-Fallback.
    _maneuvers[index] = _maneuvers[index].copyWith(
      roundaboutArmBearings: topo?.armBearings ?? const <double>[],
      roundaboutIslandScale: topo?.islandScale,
    );
    _safeSetState(() {});
  }

  // ═══════════════════════ CAMERA ═══════════════════════════════════════════

  // Kamera-FAB als echter Toggle: aus = Karte frei bewegen, an = Standort folgen.
  // Finger-Pan entriegelt ebenfalls, auch schon in der Routen-Vorschau.
  void _toggleCameraLock() {
    if (_isCameraLocked) {
      _unlockCameraFollow();
      return;
    }
    _safeSetState(() => _isCameraLocked = true);
    _recenterMap();
  }

  void _unlockCameraFollow() {
    if (!_isCameraLocked) return;
    // 2026-06-13 (vucko Free-Cam-Ruckeln): Ticker NICHT mehr stoppen — er
    // treibt im freien Modus weiterhin Puck-Glide + Marker-Projektion
    // (Kamera-Moves unterbindet der _isCameraLocked-Zweig im Tick selbst).
    _lastCameraFrameAt = null;
    _safeSetState(() => _isCameraLocked = false);
  }

  Future<void> _recenterMap() async {
    final position = _userLocation;
    if (position == null || !_mapReady) return;
    // 2026-06-08 (vucko Butterweich): Recenter über den Smooth-Follow-Ticker.
    // Kamera-Stand UND Ziel auf den Standort setzen (Snap), Ticker (re)starten —
    // kein konkurrierendes animateCamera mehr.
    //
    // 2026-06-11 (vucko Route-Lock): Bei aktiver Navigation darf Recenter nicht
    // auf das rohe GPS springen. Puck, Kamera und Linienkopf müssen dieselbe
    // route-gesnappte Render-Position nutzen, sonst sieht das Follow-Umschalten
    // wieder wie ein Standort/Route-Versatz aus.
    final lockedAnchor = (!_isOverviewActive && _isRouteConfirmed)
        ? _routeLockedRenderPosition(
                DateTime.now().add(_nativeRenderPredictionLead),
              ) ??
              _lastRouteLockedRenderLatLng
        : null;
    final anchor =
        lockedAnchor ?? LatLng(position.latitude, position.longitude);
    final heading = (_userHeading.isFinite && _userHeading >= 0)
        ? _userHeading
        : _lastCameraHeading;
    _camCurLat = anchor.latitude;
    _camCurLng = anchor.longitude;
    _camCurHeading = heading;
    _camToLat = anchor.latitude;
    _camToLng = anchor.longitude;
    _camToHeading = heading;
    _lastCameraHeading = heading;
    _camHasState = true;
    _lastCameraFrameAt = null;
    if (!(_cameraAnimController?.isAnimating ?? false)) {
      _cameraAnimController?.repeat();
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
      _camFitBounds(routeLatLngs, const EdgeInsets.fromLTRB(40, 80, 40, 160));

      // 4 Sekunden Übersicht anzeigen, dann zurück
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted || _disposed) return;

      // Zurück zur Navigationsposition
      if (_isCameraLocked) {
        await _recenterMap();
      }
    } catch (e) {
      debugPrint('[CruiseMode] Route-Übersicht fehlgeschlagen: $e');
    } finally {
      // 2026-06-06 (vucko P11-Fix): IMMER zurücksetzen — auch wenn oben bei
      // !mounted/_disposed früh returnt wird. Sonst bliebe _isOverviewActive
      // true hängen → der Follow wäre für diese Page-Instanz dauerhaft tot.
      _isOverviewActive = false;
    }
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
    // 2026-06-08 (vucko Butterweich): Nav-Start initialisiert den Smooth-Follow-
    // Ticker auf den Standort (Snap + Ticker an), zoom 16.5.
    unawaited(_recenterMap());
  }

  // Fahrsimulator entfernt. Navigation nutzt nur echte GPS-Updates.
  void _stopSimulation({bool restartLiveTracking = true}) {}

  // ═══════════════════════ ROUTE COMPLETION ═════════════════════════════════

  RouteResult? get _completionRouteResult =>
      _sessionRouteResult ?? _lastRouteResult;

  RouteResult? _buildAdjustedCompletionResult() {
    final result = _completionRouteResult;
    if (result == null) return null;

    final trackSnapshot = _drivenTrackRecorder.snapshot();
    if (!trackSnapshot.hasDrawableTrack) return null;

    final drivenDistanceMeters = math.max(0.0, trackSnapshot.distanceMeters);
    final progressFraction = _calculateCompletionProgressFraction(
      drivenDistanceMeters,
    );
    final adjustedDuration = _calculateAdjustedCompletionDuration(
      progressFraction,
    );
    return trackSnapshot.toRouteResult(
      source: result,
      durationSeconds: adjustedDuration,
    );
  }

  double _calculateCompletionProgressFraction(double? drivenDistanceMeters) {
    final plannedDistanceMeters =
        _completionRouteResult?.distanceMeters ?? _originalRouteDistance;
    if (drivenDistanceMeters == null || drivenDistanceMeters <= 0) {
      return 0.0;
    }
    if (plannedDistanceMeters == null || plannedDistanceMeters <= 0) {
      return 0.0;
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

  List<List<double>> _buildCompletionCoordinates() {
    return _drivenTrackRecorder.snapshot().coordinates;
  }

  List<List<List<double>>> _buildCompletionSegments() {
    return _drivenTrackRecorder.snapshot().drawableSegments;
  }

  int _estimateCompletionCurves(List<List<double>> coordinates) {
    if (coordinates.length >= 6) {
      final sampled = _sampleCoordinatesForSimilarity(
        coordinates,
        maxSamples: 120,
      );
      final counted = GamificationService.countCurves(sampled);
      if (counted > 0) return counted;
    }
    return 0;
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
    final adjustedResult = _buildAdjustedCompletionResult();
    final drivenKm = adjustedResult?.distanceKm ?? 0;
    final progressFraction = _calculateCompletionProgressFraction(
      adjustedResult?.distanceMeters,
    );
    final creditEligible = progressFraction >= _minProgressForXpCredit;
    final previewCoordinates = adjustedResult?.coordinates ?? <List<double>>[];
    final previewSegments = _buildCompletionSegments();
    final xpCoordinates = _buildCompletionCoordinates();
    final curves = _estimateCompletionCurves(previewCoordinates);
    final xpCurves = _estimateCompletionCurves(xpCoordinates);
    final xpBreakdown = _calculateCompletionXpBreakdown(
      creditedDistanceKm: creditEligible ? drivenKm : 0.0,
      curves: creditEligible ? xpCurves : 0,
    );
    final xpEarned = xpBreakdown.totalXp;

    return _CruiseCompletionSnapshot(
      distanceKm: drivenKm,
      durationText: _formatCompletionDuration(adjustedResult?.durationSeconds),
      curves: curves,
      xpEarned: xpEarned,
      xpBreakdown: xpBreakdown,
      coordinates: previewCoordinates,
      segments: previewSegments,
      isEarlyStop: isEarlyStop,
      belowMinimum: belowMinimum,
    );
  }

  void _onRouteCompleted() {
    if (!mounted || _disposed) return;
    final snapshot = _buildCompletionSnapshot(
      isEarlyStop: false,
      belowMinimum: _completionProgressBelowXpMinimum(completed: true),
      completed: true,
    );
    // 2026-06-02 (vucko Sync): Abschluss-Screen SYNCHRON aufs Auto bringen —
    // SOFORT beim Ankommen (nicht erst nach dem Beantworten am Handy, das war
    // der „CarPlay kam zu spät"-Bug). Distanz mitgeben → kein „-- gefahren".
    _completionSheetOpen = true;
    _freezeMapForCompletion();
    unawaited(
      _carRouteBridge.publishEnded(distanceMeters: snapshot.distanceKm * 1000),
    );
    unawaited(
      _recordRouteCompletionCandidate(completed: true, discarded: false),
    );
    final drivenSnap = _drivenTrackRecorder.snapshot();
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
        routeSegments: snapshot.segments,
        drivenSegments: drivenSnap.segments.isEmpty
            ? null
            : drivenSnap.segments,
        routeStyle: _selectedStyle,
        isRoundTrip: _isRoundTrip,
        onSave: (rating, tags, title) async {
          final result = await _saveRouteAndSyncXp(
            rating: rating,
            ratingTags: tags,
            title: title,
            completed: true,
          );
          _resetAfterCompletion();
          return result;
        },
        onDiscard: () async {
          try {
            await _recordDriveSessionForCurrentRoute(completed: true);
            await _recordRouteCompletionCandidate(
              completed: true,
              discarded: true,
            );
          } finally {
            _resetAfterCompletion();
          }
        },
      ),
    );
  }

  void _onRouteEarlyStopped() {
    if (!mounted || _disposed) return;
    final drivenKm = _drivenTrackRecorder.distanceMeters / 1000;
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

    final snapshot = _buildCompletionSnapshot(
      isEarlyStop: true,
      belowMinimum: _completionProgressBelowXpMinimum(completed: false),
    );
    // 2026-06-02 (vucko Sync): Abschluss-Screen synchron aufs Auto (siehe
    // _onRouteCompleted).
    _completionSheetOpen = true;
    _freezeMapForCompletion();
    unawaited(
      _carRouteBridge.publishEnded(distanceMeters: snapshot.distanceKm * 1000),
    );

    final drivenSnap = _drivenTrackRecorder.snapshot();
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
        routeSegments: snapshot.segments,
        drivenSegments: drivenSnap.segments.isEmpty
            ? null
            : drivenSnap.segments,
        isEarlyStop: snapshot.isEarlyStop,
        belowMinimum: snapshot.belowMinimum,
        routeStyle: _selectedStyle,
        isRoundTrip: _isRoundTrip,
        onSave: (rating, tags, title) async {
          final result = await _saveRouteAndSyncXp(
            rating: rating,
            ratingTags: tags,
            title: title,
          );
          _resetAfterCompletion(tripGoalReached: false);
          return result;
        },
        onDiscard: () async {
          try {
            await _recordDriveSessionForCurrentRoute(completed: false);
            await _recordRouteCompletionCandidate(
              completed: false,
              discarded: true,
            );
          } finally {
            _resetAfterCompletion(tripGoalReached: false);
          }
        },
      ),
    );
  }

  /// Speichert optional die Route und synchronisiert XP/Level/Badges.
  /// XP kommt aus einer immutable Drive-Session, nicht aus der gespeicherten Route.
  Future<CruiseCompletionActionResult> _saveRouteAndSyncXp({
    int? rating,
    List<String> ratingTags = const [],
    String? title,
    bool completed = false,
  }) async {
    int? previousLevel;
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

    try {
      debugPrint(
        '[CruiseMode] _saveRouteAndSyncXp: _lastRouteResult=${_lastRouteResult != null}, rating=$rating',
      );
      final adjustedResult = _buildAdjustedCompletionResult();
      if (adjustedResult != null) {
        final progressFraction = _calculateCompletionProgressFraction(
          adjustedResult.distanceMeters,
        );
        final creditEligible = progressFraction >= _minProgressForXpCredit;
        final drivenKm = adjustedResult.distanceKm ?? 0;
        final xpCoordinates = _buildCompletionCoordinates();
        final xpCurves = _estimateCompletionCurves(xpCoordinates);
        final xpBreakdown = _calculateCompletionXpBreakdown(
          creditedDistanceKm: creditEligible ? drivenKm : 0.0,
          curves: creditEligible ? xpCurves : 0,
        );
        debugPrint(
          '[CruiseMode] Saving route: style=$_selectedStyle, roundTrip=$_isRoundTrip, '
          'distKm=${adjustedResult.distanceKm}, durationSec=${adjustedResult.durationSeconds?.round()}, '
          'progress=${(progressFraction * 100).round()}%, '
          'xp=${xpBreakdown.totalXp}',
        );
        await _recordDriveSessionForCurrentRoute(completed: completed);
        await SavedRoutesService.saveRoute(
          result: adjustedResult,
          style: _selectedStyle,
          isRoundTrip: _isRoundTrip,
          customName: title,
          rating: rating,
          drivenKm: adjustedResult.distanceKm,
          plannedDistanceKm: _completionRouteResult?.distanceMeters != null
              ? _completionRouteResult!.distanceMeters! / 1000
              : adjustedResult.distanceKm,
          xpDistance: xpBreakdown.distanceXp,
          xpCurveBonus: xpBreakdown.curveXp,
          xpStyleBonus: xpBreakdown.styleBonus,
          xpBase: xpBreakdown.baseXp,
          xpMultiplier: xpBreakdown.multiplier,
          xpStreakDays: xpBreakdown.streakDays,
          xpAwarded: xpBreakdown.totalXp,
          completedAtEnd: completed,
          groupId: widget.groupId,
        );
        if (mounted) {
          unawaited(context.read<RouteBookmarkProvider>().loadSavedRoutes());
          unawaited(context.read<SavedRoutesProvider>().loadRoutes());
        }
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
      final gamResult = await GamificationService.calculateAndSync();
      return CruiseCompletionActionResult(
        success: true,
        newBadges: gamResult.newBadges,
        levelUp: previousLevel != null && gamResult.level.level > previousLevel,
        newLevel: gamResult.level.level,
      );
    } catch (e, stack) {
      debugPrint('Route speichern / XP sync fehlgeschlagen: $e');
      if (kDebugMode) {
        debugPrint('Stack: $stack');
      }
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

  Future<void> _recordDriveSessionForCurrentRoute({
    required bool completed,
  }) async {
    if (_driveSessionRecordedForCompletion) return;
    final adjustedResult = _buildAdjustedCompletionResult();
    if (adjustedResult == null) return;
    final drivenKm = adjustedResult.distanceKm ?? 0;
    if (drivenKm <= 0) return;
    final progressFraction = _calculateCompletionProgressFraction(
      adjustedResult.distanceMeters,
    );
    if (progressFraction < _minProgressForXpCredit) return;

    // 2026-06-15 (vucko): Streak-Multiplikator FIX aufs Konto anrechnen — die
    // boosted XP werden hier in user_drive_sessions.xp_awarded geschrieben (Summe
    // → profiles.total_xp via calculateAndSync), nicht nur im Abschluss-Sheet
    // angezeigt. _xpStreakDays = Streak für DIESE Fahrt (inkl. heute, via
    // _prepareXpStreakContext) und ist exakt die Zahl, die das Sheet anzeigt.
    final xpBreakdown = GamificationService.calculateRouteXpBreakdown(
      distanceKm: drivenKm,
      curves: 0,
      style: _selectedStyle,
      streakDays: _xpStreakDays,
    );
    await GamificationService.recordDriveSession(
      distanceKm: drivenKm,
      durationSeconds: adjustedResult.durationSeconds?.round() ?? 0,
      completedAtEnd: completed,
      routeStyle: _selectedStyle,
      routeType: _isRoundTrip ? 'ROUND_TRIP' : 'POINT_TO_POINT',
      routeFingerprint: adjustedResult.edgeMeta['route_fingerprint']
          ?.toString(),
      xpAwarded: xpBreakdown.totalXp,
    );
    _driveSessionRecordedForCompletion = true;
    await GamificationService.calculateAndSync();
  }

  bool _completionProgressBelowXpMinimum({required bool completed}) {
    final adjustedResult = _buildAdjustedCompletionResult();
    final progressFraction = _calculateCompletionProgressFraction(
      adjustedResult?.distanceMeters,
    );
    return progressFraction < _minProgressForXpCredit;
  }

  Future<void> _recordRouteCompletionCandidate({
    required bool completed,
    required bool discarded,
  }) async {
    try {
      final adjustedResult = _buildAdjustedCompletionResult();
      if (adjustedResult == null) return;
      final progressFraction = _calculateCompletionProgressFraction(
        adjustedResult.distanceMeters,
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

  /// 2026-06-15 (vucko M5 „niemals crashen"): Friert die unter dem Abschluss-
  /// Sheet LIEGENDE MapLibre-Map vollständig ein. Das Sheet ist nur ein Dialog
  /// ÜBER der Cruise-Page → die native Karte rendert/projiziert sonst weiter,
  /// während Tracking gestoppt + ein neuer Idle-GPS-Stream läuft. Ein
  /// view-abhängiger Native-Call in diesem Fenster = SIGABRT (von Dart nicht
  /// fangbar, schließt die App zur iOS-Startseite — exakt der Geräte-Crash).
  void _freezeMapForCompletion() {
    _mlController?.active = false;
    _cameraAnimController?.stop();
    _stopIdlePositionStream();
  }

  void _resetAfterCompletion({bool tripGoalReached = true}) {
    // 2026-06-15 (vucko M5): Map wieder aktivieren — die Page bleibt nach dem
    // Sheet am Leben, _setCameraToPosition unten + der (von _stopNavigationTracking
    // neu gestartete) Idle-Stream brauchen eine aktive Karte.
    _mlController?.active = mounted && !_disposed;
    unawaited(RouteCacheService.instance.clearConfirmedRoute());
    _stopSimulation(restartLiveTracking: false);
    _stopNavigationTracking();
    CruiseModePage.isFullscreen.value = false;
    _xpStreakDays = 1;
    _drivenTrackRecorder.reset();
    _resetGeneratedRouteUiState();
    // 2026-05-24 (vucko Task #53): Trip in DB als completed markieren
    // (best-effort, fail silent).
    final tripIdToComplete = _activeTripId;
    if (tripIdToComplete != null) {
      _activeTripId = null;
      // 2026-06-10 (vucko Gruppen-Trip-Regel): Ein Trip endet NUR, wenn das
      // Ziel erreicht wurde. Vorzeitiges Beenden (Early-Stop-Sheet) =
      // ZWISCHENSPEICHERN: Trip wird pausiert und kann spaeter von der
      // aktuellen Position fortgesetzt werden (Resume-Card). Gruppen-Trips
      // enden zusaetzlich erst, wenn alle die Gruppe verlassen haben
      // (leaveGroup-Pfad).
      if (tripGoalReached) {
        unawaited(_safeCompleteTrip(tripIdToComplete));
      } else {
        unawaited(
          TripService.instance.pauseTrip(tripIdToComplete).catchError((_) {}),
        );
      }
    }
    final currentLocation = _userLocation;
    if (currentLocation != null) {
      _setCameraToPosition(currentLocation);
    }
  }

  // 2026-05-24 (vucko Task #53): Trip-Persistierung Helper.
  Future<void> _createTripInDb({
    required double startLat,
    required double startLng,
    required List<LatLng> waypoints,
    required String style,
    required bool avoidHighways,
    required double distanceKm,
    required int durationSeconds,
  }) async {
    try {
      final stops = <({double lat, double lng, String name, String stopType})>[
        (lat: startLat, lng: startLng, name: 'Start', stopType: 'start'),
      ];
      for (var i = 0; i < waypoints.length; i++) {
        final wp = waypoints[i];
        final isLast = i == waypoints.length - 1;
        stops.add((
          lat: wp.latitude,
          lng: wp.longitude,
          name: isLast ? 'Ziel' : 'Stopp ${i + 1}',
          // 2026-06-10 (vucko 0-Stops-Bug): Der DB-CHECK-Constraint
          // trip_stops_stop_type_check erlaubt NUR start|waypoint|overnight|
          // lunch|photo|fuel|destination — 'end' war invalide und ließ den
          // GESAMTEN Batch-Insert platzen (Postgres-Log: "violates check
          // constraint"). Folge: jeder Trip lag OHNE Stops in der DB und der
          // Resume schloss die Tour sofort als kaputt. Ziel = 'destination'.
          stopType: isLast ? 'destination' : 'waypoint',
        ));
      }
      final title = waypoints.length >= 2
          ? '${waypoints.length}-Stop Tour'
          : 'Tour';
      final tripId = await TripService.instance.createTrip(
        title: title,
        stops: stops,
        defaultStyle: style,
        defaultAvoidHighways: avoidHighways,
        groupId: widget.groupId,
        totalDistanceKm: distanceKm,
        totalDurationSeconds: durationSeconds,
      );
      if (tripId != null && mounted && !_disposed) {
        setState(() => _activeTripId = tripId);
        debugPrint(
          '[CruiseMode] Trip #$tripId in DB erstellt mit ${stops.length} Stops',
        );
      }
    } catch (e) {
      debugPrint('[CruiseMode] Trip-Create fehlgeschlagen (silent): $e');
    }
  }

  Future<void> _safePauseTrip(String tripId) async {
    try {
      await TripService.instance.pauseTrip(tripId);
    } catch (e) {
      debugPrint('[CruiseMode] Trip pause fail (silent): $e');
    }
  }

  Future<void> _safeCompleteTrip(String tripId) async {
    try {
      await TripService.instance.completeTrip(tripId);
    } catch (e) {
      debugPrint('[CruiseMode] Trip complete fail (silent): $e');
    }
  }

  // ═══════════════════════ DIALOGS ══════════════════════════════════════════

  void _showError(String message, {bool isCritical = false}) {
    if (!mounted || _disposed) return;
    debugPrint('[CruiseMode] Error: $message (critical=$isCritical)');

    // 2026-05-24 (vucko UX-Fix): TopToast statt fetter Orange-Snackbar.
    // Die alte Snackbar nahm zu viel Platz, überdeckte die Karte und sah
    // nicht zur App-Optik passend aus. TopToast ist konsistent mit dem Rest
    // (Streak, Notifications, Saved-Route, Trip-Resume-Confirm etc.).
    final icon = isCritical
        ? Icons.warning_amber_rounded
        : Icons.wifi_off_rounded;
    TopToast.show(
      context,
      message: message,
      icon: icon,
      duration: Duration(milliseconds: isCritical ? 4500 : 3200),
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
    required this.segments,
    required this.isEarlyStop,
    required this.belowMinimum,
  });

  final double distanceKm;
  final String durationText;
  final int curves;
  final int xpEarned;
  final RouteXpBreakdown xpBreakdown;
  final List<List<double>> coordinates;
  final List<List<List<double>>> segments;
  final bool isEarlyStop;
  final bool belowMinimum;
}

/// iOS Puck: reiner blauer Punkt (weißer Ring + blauer Kern), KEIN Pfeil.
/// 2026-06-13 (vucko J5): Richtungskeil entfernt — der User wollte keinen
/// Pfeil, der mit dem Heading herumspringt.
class _AppleMapsPuckPainter extends CustomPainter {
  const _AppleMapsPuckPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const blue = Color(0xFF007AFF);

    // ── Weißer Ring (Schatten + Rand) ──
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

/// Wegpunkt-Mode-Header (v2 — schlank).
///
/// Eine zentrierte Pill mit zwei Segment-Tabs (Standard | Trip),
/// kleinem Stop-Counter und "?"-Bubble. Höhe ~44px statt ~180px.
/// Animierter "Slide-Pill" hinter dem aktiven Tab (iOS-Style) statt
/// fetter Card-Backgrounds. Keine permanente Erklärung mehr —
/// Erklärung erscheint nur als TopToast beim Mode-Wechsel.
class _WaypointModeHeader extends StatelessWidget {
  const _WaypointModeHeader({
    required this.tripEnabled,
    required this.current,
    required this.max,
    required this.onSelect,
    required this.onHelpTap,
  });

  final bool tripEnabled;
  final int current;
  final int max;
  final ValueChanged<bool> onSelect;
  final VoidCallback onHelpTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final atLimit = current >= max;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: const Color(0xCC0E1117),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.40),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 18),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Segmented Tabs — Stack mit animierter Slide-Pill darunter
              _SegmentedTabs(
                tripEnabled: tripEnabled,
                accent: accent,
                onSelect: onSelect,
              ),
              const SizedBox(width: 6),
              // Counter
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: atLimit
                      ? const Color(0xFFFFB74D).withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  '$current/$max',
                  style: TextStyle(
                    color: atLimit ? const Color(0xFFFFB74D) : Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onHelpTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0x14FFFFFF),
                  ),
                  child: const Icon(
                    CupertinoIcons.info,
                    color: Colors.white70,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({
    required this.tripEnabled,
    required this.accent,
    required this.onSelect,
  });

  final bool tripEnabled;
  final Color accent;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    const tabWidth = 108.0;
    const tabHeight = 34.0;
    return SizedBox(
      width: tabWidth * 2,
      height: tabHeight + 4,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // Animierte Slide-Pill hinter dem aktiven Tab (iOS-Segmented-Style).
          AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: tripEnabled
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Container(
              width: tabWidth,
              height: tabHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: 0.95),
                    accent.withValues(alpha: 0.70),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.45),
                    blurRadius: 14,
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              _SegTab(
                label: 'Standard',
                icon: CupertinoIcons.flag,
                width: tabWidth,
                height: tabHeight + 4,
                active: !tripEnabled,
                onTap: () => onSelect(false),
              ),
              _SegTab(
                label: 'Trip-Modus',
                icon: CupertinoIcons.map_pin_ellipse,
                width: tabWidth,
                height: tabHeight + 4,
                active: tripEnabled,
                onTap: () => onSelect(true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegTab extends StatelessWidget {
  const _SegTab({
    required this.label,
    required this.icon,
    required this.width,
    required this.height,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final double width;
  final double height;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        height: height,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(
                color: active ? Colors.white : Colors.white60,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: active ? 1.0 : 0.92,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      icon,
                      size: 14,
                      color: active ? Colors.white : Colors.white54,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(label),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 2026-05-28 (vucko Task #79): Ästhetischer FAB-Bubble mit Glas-Look,
/// Schatten und Tap-Bounce. Ersetzt die nackten FloatingActionButton.small.
///
/// 2026-05-28 (vucko Task #79.1): Einheitliche Größe (48px) damit alle FABs
/// in der Spalte perfekt vertikal aligned sind. [big]-Flag bleibt für
/// Backwards-Compat aber hat keinen optischen Effekt mehr.
///
/// - Loading-Spinner statt Icon wenn [loading]=true
/// - Schatten mit Color-Tint vom Background damit der FAB „glüht" wenn
///   eine Aktion aktiv ist (z.B. POI-Filter mit Akzentfarbe = leichter
///   Akzent-Glow)
class _FabBubble extends StatelessWidget {
  static const double _size = 48.0;
  static const double _iconSize = 20.0;

  final String heroTag;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final bool loading;
  // ignore: unused_element
  final bool big;
  const _FabBubble({
    required this.heroTag,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.loading = false,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Hero(
        tag: heroTag,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(_size),
            onTap: () {
              HapticFeedback.lightImpact();
              onPressed();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color,
                    Color.lerp(color, Colors.black, 0.18) ?? color,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.36),
                    blurRadius: 12,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.32),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(icon, color: Colors.white, size: _iconSize),
            ),
          ),
        ),
      ),
    );
  }
}
