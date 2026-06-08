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
import 'package:cruise_connect/data/services/navigation_progress_socket_service.dart';
import 'package:cruise_connect/data/services/offline_map_service.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;
import 'package:cruise_connect/data/services/cruise_dark_map_style.dart';
import 'package:cruise_connect/data/services/car_route_bridge_service.dart';
import 'package:cruise_connect/data/services/car_command_listener.dart';
import 'package:cruise_connect/data/services/group_route_data_builder.dart';
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
    with TickerProviderStateMixin {
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
  MapboxSuggestion? _selectedDestination;

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

  // ─────────────────────── Simulation State ─────────────────────────────────
  Timer? _simulationTimer;
  bool _isSimulationRunning = false;
  bool _isSimulationStepRunning = false;
  int _simulationIndex = 0;
  // 2026-06-08 (vucko Sim-Speed-Fix): Distanz-basierte Interpolation. _simulation
  // DistanceM = zurückgelegte Strecke entlang der Route; _simulationDistAtIndexM =
  // kumulierte Strecke bis zum Segment-Start _simulationIndex. So fährt der Sim
  // EXAKT _simulationConstantKmh, egal wie dicht/dünn die Vertices liegen.
  double _simulationDistanceM = 0.0;
  double _simulationDistAtIndexM = 0.0;
  // 2026-06-08 (vucko DACH-Test): ON-ROAD Reroute-Test-Hook. NUR mit
  // --dart-define=SIM_DEVIATE=true. Nach _simDeviateAfterMeters holt der Sim eine
  // ECHTE GraphHopper-Route quer zur Fahrtrichtung (bleibt auf Straßen!) und
  // fährt sie ab statt der Nav-Route → realistisches Off-Route, das Reroute
  // testet OHNE ins Gelände zu fahren. Endet nach erstem Reroute (devOnce).
  static const bool _simDeviateEnabled = bool.fromEnvironment('SIM_DEVIATE');
  static const double _simDeviateAfterMeters = 1500.0;
  bool _simDeviateRequested = false;
  bool _simDeviatedOnce = false;
  List<List<double>>? _simDeviationRoute;
  double _simDeviationDistM = 0.0;
  double _simDeviationDistAtIndexM = 0.0;
  int _simDeviationIndex = 0;
  // 2026-05-30 (vucko): Fahrten-Simulator — grüner Play-FAB in der Navigation,
  // um die Routenabfahrt zu prüfen.
  // 2026-06-06 (vucko): Sim wieder AN für die Smoothness-/Kamera-/Linien-Tests
  // (konstant 30 km/h statt 100 → man sieht Ruckler/Kamera-Verhalten viel besser).
  // Vor dem finalen Release wieder auf false setzen (Testuser sollen ihn nicht sehen).
  final bool _isSimulationEnabled = true;
  // Konstante Sim-Speed. Default 30 km/h (man sieht Ruckler gut); für schnelle
  // Test-Durchläufe via --dart-define=SIM_KMH=70 hochsetzen.
  static const double _simulationConstantKmh =
      int.fromEnvironment('SIM_KMH', defaultValue: 30) * 1.0;
  double _simulationSpeedKmh = _simulationConstantKmh;

  bool _isCameraLocked =
      false; // Compass-Toggle: true = Kamera folgt dem Standort
  double? _remainingDistance; // Live verbleibende Distanz in Metern
  double? _remainingDuration; // Live verbleibende Zeit in Sekunden
  bool _isRerouting = false; // Verhindert mehrfaches gleichzeitiges Rerouting
  // 2026-06-06 (vucko P2): „Route wird neu berechnet"-Banner NUR einmal pro
  // Reroute-Zyklus zeigen (vorher pro Versuch → Spam). Wird beim Erfolg/Fehler
  // zurückgesetzt.
  bool _rerouteBannerShown = false;
  DateTime? _lastRerouteTime; // Cooldown zwischen Reroutes
  int _offRouteCount = 0; // Zählt aufeinanderfolgende Off-Route-Updates
  // 2026-06-07 (vucko P-reroute): Zeit-basierte Hysterese wie Apple/Google —
  // Off-Route muss ANHALTEND sein (Wall-Clock), nicht nur N Ticks (bei 20Hz-Sim
  // wären 5 Ticks = 0.25s = viel zu zappelig). Gesetzt beim ersten Außerhalb-
  // Tick, geleert sobald wieder im Korridor ODER der Puck weiter vorankommt.
  DateTime? _offRouteSince;
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
  static const Duration _rerouteCooldown = Duration(seconds: 12);
  // 2026-06-01 (vucko): Max. Versatz, bis zu dem der sichtbare Routenkopf an
  // die GPS-Position geheftet wird. Darüber bleibt der echte Routenpunkt der
  // Kopf → keine Off-Route-Zacken bei GPS-Drift in Bergtälern.
  static const double _headSnapMaxMeters = 18.0;
  // 2026-06-05 (vucko Task #4): Redraw-Kadenz entschärft (vorher 1 / 5m). Jeder
  // Redraw erzeugt eine neue Window-Geometrie → die GL-Linie wird neu gezeichnet
  // (clearLines+addLine = teuer). Bei 5m lief das ~6×/Sek (Lag). 25m / index 3 =
  // ~1×/Sek → butterweich. Der Head-Snap + die volle Hintergrund-Route halten die
  // Linie trotzdem optisch am Puck (kein sichtbares Nachhängen).
  static const int _routeRedrawIndexThreshold = 3;
  static const double _routeRedrawDistanceMeters = 25.0;
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
  bool _applyingGroupRouteUpdate = false;
  int _groupRouteRevision = 0;
  Map<String, dynamic>? _activeGroupRouteData;
  final Map<String, GroupMember> _groupMembers = {};
  static const Duration _groupPositionUploadInterval = Duration(seconds: 2);
  static const Duration _groupRouteBackfillInterval = Duration(seconds: 15);
  static const Duration _groupRouteReconnectDelay = Duration(seconds: 3);
  static const Duration _groupMembersBackfillInterval = Duration(seconds: 10);
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
  bool _trimVisibleRouteToProjection(RouteWindowMatch match) {
    final coords = _fullRouteCoordinates;
    if (coords.length < 2) return false;
    // Nur heften, wenn der Fahrer wirklich auf der Route ist (lateral ≤ 18m) —
    // sonst (echter Off-Route/Drift) den Kopf NICHT zwangsweise ziehen.
    if (match.distanceMeters > _headSnapMaxMeters) return false;

    final segIdx = match.segmentIndex;
    final frac = match.segmentFraction;
    List<double> projHead;
    int aheadStart;
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
    if (aheadStart > coords.length) aheadStart = coords.length;

    final windowEnd = _findLookAheadIndex(aheadStart, 3000);
    final newRemaining = <List<double>>[
      projHead,
      if (aheadStart < windowEnd)
        for (final c in coords.sublist(aheadStart, windowEnd)) [c[0], c[1]],
    ];
    if (newRemaining.length < 2) return false;

    // 2026-06-07 (vucko P-map-stops): Guard von 0.4m hoch — der 0.4m-Guard feuerte
    // bei 30km/h JEDEN Tick → ~20Hz Voll-Route-Rewrite, der die PMTiles-Tile-
    // Pipeline aushungerte (Karte schwarz). 2026-06-08 (Butterweich): 3m → 1.5m
    // halbiert die Lücke zwischen Linienkopf und Puck (smoother), OHNE die Push-
    // Frequenz zu erhöhen — die ist ohnehin durch den _syncLines-Throttle (≤5Hz)
    // gedeckelt, also kein zusätzliches Schwarz-Risiko.
    if (_remainingRouteCoordinates.isNotEmpty &&
        _remainingRouteCoordinates.length == newRemaining.length) {
      final cur = _remainingRouteCoordinates.first;
      final moved = geo.Geolocator.distanceBetween(
          cur[1], cur[0], projHead[1], projHead[0]);
      if (moved < 1.5) return false;
    }

    _remainingRouteCoordinates = newRemaining;
    _routeGeoJson = json.encode({
      'type': 'LineString',
      'coordinates': newRemaining,
    });
    _routeLatLngs = [for (final c in newRemaining) LatLng(c[1], c[0])];
    return true;
  }

  @override
  void initState() {
    super.initState();
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
    CarCommandListener.instance.onStartNavigation = (route, style, avoidHighways) {
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
      final destination = routeData['destination'];
      if (destination is Map) {
        final lat = destination['latitude'];
        final lng = destination['longitude'];
        if (lat is num && lng is num) {
          _activeDestinationCoordinate = [lng.toDouble(), lat.toDouble()];
        }
      }
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
      final members = await CruiseGroupService.fetchMembers(groupId);
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

  // 2026-05-24 (vucko Task #53): Trip-Resume aus Home-Carousel.
  void _onPendingTripResume() {
    _consumePendingTripResumeIfAvailable();
  }

  Future<void> _consumePendingTripResumeIfAvailable() async {
    if (!mounted || _disposed) return;
    final tripId = CruiseModePage.pendingTripResume.value;
    if (tripId == null) return;
    CruiseModePage.pendingTripResume.value = null;
    try {
      final stops = await TripService.instance.stopsFor(tripId);
      if (!mounted || _disposed) return;
      // 2026-05-24 (vucko Fix): wenn Trip kaputt (keine/zu wenige Stops) →
      // sauberer Top-Toast + Trip in DB als completed markieren damit er
      // nicht weiter in der Resume-Card auftaucht.
      if (stops.length < 2) {
        TopToast.show(
          context,
          message: 'Diese Tour hat keine gültigen Wegpunkte mehr — wird geschlossen.',
          icon: Icons.info_outline_rounded,
          duration: const Duration(milliseconds: 3500),
        );
        unawaited(_safeCompleteTrip(tripId));
        return;
      }
      // Resume in DB markieren (status=active, resumed_at=now)
      await TripService.instance.resumeTrip(tripId);
      // Setze UI-State: Trip-Mode an, Wegpunkte = stops (ohne start),
      // _activeTripId = tripId damit Pause/Complete später greift.
      final waypoints = stops
          .where((s) => s.stopType != 'start')
          .map((s) => LatLng(s.lat, s.lng))
          .toList(growable: false);
      if (!mounted || _disposed) return;
      if (waypoints.length < 2) {
        TopToast.show(
          context,
          message: 'Tour hat nicht genug Wegpunkte zum Fortsetzen.',
          icon: Icons.info_outline_rounded,
          duration: const Duration(milliseconds: 3500),
        );
        unawaited(_safeCompleteTrip(tripId));
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
      if (mounted && !_disposed) {
        TopToast.show(
          context,
          message: 'Tour konnte nicht geladen werden.',
          icon: Icons.warning_amber_rounded,
          duration: const Duration(milliseconds: 3000),
        );
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
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
  void _onCameraAnimationTick() {
    if (!_isCameraLocked || !_mapReady || _isOverviewActive) {
      _cameraAnimController?.stop();
      return;
    }
    if (!_camHasState || _camMoveInFlight) return;
    // Kritisch gedämpftes Annähern (Apple/Google-artig). Faktor pro Frame.
    const f = 0.18;
    _camCurLat += (_camToLat - _camCurLat) * f;
    _camCurLng += (_camToLng - _camCurLng) * f;
    _camCurHeading = _lerpAngleDeg(_camCurHeading, _camToHeading, f);
    final ctrl = _mlController;
    if (ctrl == null) return;
    // Forward-Offset: Zentrum ~100m voraus → Puck sitzt im unteren Drittel.
    final offLat = _camCurLat + _forwardOffsetLat(_camCurHeading);
    final offLng = _camCurLng + _forwardOffsetLng(_camCurHeading);
    _camMoveInFlight = true;
    ctrl
        .moveTo(
          lat: offLat,
          lng: offLng,
          zoom: 16.5,
          bearing: _camCurHeading,
        )
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
    if (!controller.isAnimating) controller.repeat();
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
        message: label == null
            ? 'Startpunkt gesetzt'
            : 'Startpunkt: $label',
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
  void _onStartLocationSelected(MapboxSuggestion suggestion) {
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
                    child: Icon(Icons.tips_and_updates_rounded,
                        color: AppAccentColors.accent, size: 24),
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
              _tutorialBullet('🎯', 'Standard',
                  'Bis zu 3 Stopps für eine schnelle Tour'),
              const SizedBox(height: 10),
              _tutorialBullet('🗺️', 'Trip-Modus',
                  'Bis zu 5 Stopps, mit Pause/Resume — perfekt für Mehrtages-Touren'),
              const SizedBox(height: 10),
              _tutorialBullet('💾', 'Auto-Save',
                  'Trip wird gespeichert, du kannst später im Homescreen weitermachen'),
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
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
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
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
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
                      final active =
                          PoiSettingsService.instance.anyEnabled;
                      return _buildWaypointMapAction(
                        icon: Icons.tune_rounded,
                        label: 'POIs',
                        onTap: _isLoading ? null : _openPoiFilter,
                        overrideAccent: active
                            ? AppAccentColors.accent
                            : null,
                      );
                    },
                  ),
                  AnimatedBuilder(
                    animation: VoiceSettingsService.instance,
                    builder: (context, _) {
                      final mode = VoiceSettingsService.instance.mode;
                      final (icon, color) = switch (mode) {
                        VoiceMode.off => (
                            Icons.volume_off_rounded,
                            null,
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
                      return _buildWaypointMapAction(
                        icon: icon,
                        label: 'Sprache',
                        overrideAccent: color,
                        onTap: () async {
                          await VoiceSettingsService.instance.cycleMode();
                          HapticFeedback.selectionClick();
                          if (!context.mounted) return;
                          final newMode =
                              VoiceSettingsService.instance.mode;
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
                              VoiceMode.important =>
                                  Icons.volume_down_rounded,
                              VoiceMode.all => Icons.volume_up_rounded,
                            },
                          );
                        },
                      );
                    },
                  ),
                  _buildWaypointMapAction(
                    icon: _isCameraLocked
                        ? Icons.explore
                        : Icons.explore_off,
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
                    final hasConfirmableRoute = _showRouteInfoBanner &&
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
                                      color: AppAccentColors.accent
                                          .withValues(alpha: 0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: hasConfirmableRoute
                              ? OutlinedButton.icon(
                                  onPressed: () => setState(
                                      () => _configCollapsed = false),
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
                                      color: AppAccentColors.accent
                                          .withValues(alpha: 0.5),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  ),
                                )
                              : ElevatedButton.icon(
                                  onPressed: () => setState(
                                      () => _configCollapsed = false),
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
                        colors: [
                          Colors.transparent,
                          Color(0xFF0B0E14),
                        ],
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
                          onTap: () =>
                              setState(() => _configCollapsed = true),
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
                        homeCountryCode: _homeCountryCode ??
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
      return Positioned(
        top: top,
        right: 12,
        child: _buildRouteRecallPill(),
      );
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
    if (realDurationSeconds != null && realDurationSeconds > 30 && actualDistanceKm > 0) {
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
              Expanded(child: _buildInfoItem(Icons.straighten, '$distKm km', 'Distanz')),
              Expanded(child: _buildInfoItem(Icons.timer_outlined, timeStr, 'Dauer')),
              Expanded(child: _buildInfoItem(Icons.turn_right, '$curveCount', 'Kurven')),
              Expanded(child: _buildInfoItem(
                Icons.star_outline,
                '${_calculateRouteXp()}',
                'XP',
              )),
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
                  Icon(Icons.terrain_outlined,
                      size: 13, color: AppAccentColors.accent),
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
    final raw =
        (meta['route_source'] ?? meta['source'] ?? '').toString().toLowerCase();
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
    final visibleManeuver = _activeVisibleManeuver();
    return Stack(
      children: [
        Positioned(
          top: topInset + 8,
          left: 12,
          right: visibleManeuver != null ? 12 : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRoutePreviewBackButton(),
              if (visibleManeuver != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: CruiseManeuverIndicator(
                    maneuver: visibleManeuver,
                    distanceToManeuverMeters: _calculateDistanceToManeuver(
                      visibleManeuver,
                    ),
                  ),
                ),
              ],
            ],
          ),
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
    _stableInitialCenter ??= _userPosition ??
        _cachedUserCenter ??
        const LatLng(51.165691, 10.451526);
    _stableInitialZoom ??=
        (_userPosition ?? _cachedUserCenter) != null ? 13.0 : 6.0;
    return CruiseMapLibreMap(
      initialCenter: _stableInitialCenter!,
      initialZoom: _stableInitialZoom!,
      lines: _buildMapLibreLines(),
      markers: _buildMapLibreMarkers(),
      onControllerReady: (c) {
        _mlController = c;
        if (!_mapReady) _onMapReady();
      },
      onMapClick: (p) => _handleMapTap(null, p),
      onCameraMoved: () {
        if (_isCameraLocked && _isRouteConfirmed) {
          _safeSetState(() => _isCameraLocked = false);
        }
        _scheduleViewportPoiRefresh();
      },
    );
  }

  List<CruiseMapLine> _buildMapLibreLines() {
    final accent = AppAccentColors.accent;
    final lines = <CruiseMapLine>[];
    // Gesamt-Route als gedimmter Hintergrund (während Navigation).
    if (_isRouteConfirmed && _fullRouteBackgroundLatLngs.length >= 2) {
      lines.add(CruiseMapLine(
        points: List<LatLng>.from(_fullRouteBackgroundLatLngs),
        color: accent,
        opacity: 0.28,
        width: 3,
      ));
    }
    // Aktive Route: Glow + Hauptlinie.
    if (_routeLatLngs.length >= 2) {
      lines.add(CruiseMapLine(
        points: List<LatLng>.from(_routeLatLngs),
        color: accent,
        opacity: 0.30,
        width: 12,
        blur: 2,
      ));
      lines.add(CruiseMapLine(
        points: List<LatLng>.from(_routeLatLngs),
        color: accent,
        width: 5,
      ));
    }
    return lines;
  }

  List<CruiseMapMarker> _buildMapLibreMarkers() {
    final markers = <CruiseMapMarker>[];
    final pointToPointDestination = _pointToPointDestinationMarkerPoint;
    final activeRouteEnd = _activeRouteEndMarkerPoint;

    if (_userLocation != null && !_isRouteConfirmed) {
      markers.add(CruiseMapMarker(
        id: 'user-loc',
        position: LatLng(_userLocation!.latitude, _userLocation!.longitude),
        width: _puckSize,
        height: _puckSize,
        child: _buildLocationPuck(_userHeading),
      ));
    }
    if (_pickedStartLocation != null &&
        _selectedLocation == 'Standort wählen' &&
        !_isRouteConfirmed) {
      markers.add(CruiseMapMarker(
        id: 'picked-start',
        position: _pickedStartLocation!,
        width: 46,
        height: 56,
        alignment: Alignment.topCenter,
        child: _buildPickedStartMarker(),
      ));
    }
    if (_isWaypointPlanning && _roundTripWaypoints.isNotEmpty) {
      for (var i = 0; i < _roundTripWaypoints.length; i++) {
        markers.add(CruiseMapMarker(
          id: 'wp-$i',
          position: _roundTripWaypoints[i],
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: _isLoading ? null : () => _selectRoundTripWaypoint(i),
            onLongPress: _isLoading ? null : () => _deleteRoundTripWaypoint(i),
            child: _buildWaypointMarker(
              i + 1,
              selected: _selectedRoundTripWaypointIndex == i,
              replacing: _replaceRoundTripWaypointIndex == i,
            ),
          ),
        ));
      }
    }
    if (pointToPointDestination != null) {
      markers.add(CruiseMapMarker(
        id: 'p2p-dest',
        position: pointToPointDestination,
        width: 44,
        height: 44,
        child: _buildDestinationMarker(),
      ));
    }
    if (activeRouteEnd != null) {
      markers.add(CruiseMapMarker(
        id: 'route-end',
        position: activeRouteEnd,
        width: 46,
        height: 46,
        child: _buildDestinationMarker(),
      ));
    }
    for (final poi in _routePois) {
      markers.add(CruiseMapMarker(
        id: 'poi-${poi.latitude},${poi.longitude}',
        position: LatLng(poi.latitude, poi.longitude),
        width: 36,
        height: 36,
        child: GestureDetector(
          onTap: () => _showPoiInfoCard(poi),
          child: _buildPoiMarker(poi),
        ),
      ));
    }
    for (final c in _routeConstructions) {
      markers.add(CruiseMapMarker(
        id: 'cons-${c.latitude},${c.longitude}',
        position: LatLng(c.latitude, c.longitude),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => ConstructionAlertSheet.show(context, c),
          child: _buildConstructionMarker(c),
        ),
      ));
    }
    if (_userPosition != null && _isRouteConfirmed) {
      // Bei gesperrter Navi-Kamera dreht die MapLibre-Karte bereits per
      // bearing=heading (Fahrtrichtung oben) → der Screen-Overlay-Puck zeigt
      // gerade nach oben (0). Bei freigegebener Kamera (User hat gepannt) zeigt
      // er die echte Fahrtrichtung relativ zur (north-up) Karte.
      markers.add(CruiseMapMarker(
        id: 'user-pos',
        position: _userPosition!,
        width: _puckSize,
        height: _puckSize,
        child: _buildLocationPuck(_isCameraLocked ? 0.0 : _userHeading),
      ));
    }
    if (widget.groupId != null && _groupMembers.isNotEmpty) {
      for (final entry in _groupMembers.entries) {
        final m = entry.value;
        if (!_hasGroupMemberLocation(m)) continue;
        markers.add(CruiseMapMarker(
          id: 'grp-${entry.key}',
          position: LatLng(m.currentLat!, m.currentLng!),
          width: 40,
          height: 40,
          child: _buildGroupMemberMarker(m),
        ));
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
        // Mapbox-Dark-Farbe statt System-Weiß. So sind Pan-Lücken kaum
        // sichtbar während die Tiles im Hintergrund nachgeladen werden.
        backgroundColor: OfflineMapService.mapboxDarkBackground,
        // Bei Berührung der Karte: Kamera-Lock deaktivieren (war Listener-Widget)
        onPointerDown: (event, point) {
          if (_isCameraLocked && _isRouteConfirmed) {
            _safeSetState(() => _isCameraLocked = false);
          }
        },
        // 2026-06-02 (vucko): Beim Schwenken/Zoomen automatisch die POIs im
        // sichtbaren Bereich nachladen → je weiter rausgezoomt, desto mehr
        // POIs über das ganze Sichtfeld. Debounced + nur beim Planen/Browsen.
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture) _scheduleViewportPoiRefresh();
        },
      ),
      children: [
        // ── Mapbox Dark-Style als Raster-Tile-Layer ──────────────────────────
        // 2026-05-28 (vucko Task #77): retinaMode KOMPLETT DEAKTIVIERT.
        // User-Screenshots zeigen regelmäßige vertikale Streifen — das ist
        // klassischer Symptom für retinaMode-URL-Mismatch (Mapbox liefert
        // 256px Tiles, retinaMode würde @2x verlangen, aber unsere URL
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
        // _pmtilesProvider null → Mapbox-Raster-Layer (else) als Fallback,
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
          // 2026-06-02 (vucko): MAPBOX DEAKTIVIERT (User-Wunsch). Fällt das
          // Vektor-PMTiles-Laden aus (z.B. r2.dev rate-limitet die Range-
          // Requests auf die 5GB-Datei), zeigen wir jetzt UNSERE gerasterten
          // Cruise-Dark-Tiles (z6–12 aus R2 — dieselben wie CarPlay, laden
          // zuverlässig als einzelne PNGs) statt der grauen Mapbox-Karte. So
          // sieht der User IMMER unseren eigenen Look, nie Mapbox.
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
  /// nutzt die App weiter den Mapbox-Raster-Layer (Fallback, nichts bricht).
  PmTilesVectorTileProvider? _pmtilesProvider;
  // 2026-06-02 (vucko): Welt-Übersicht (z0–6) als Unterlage unter DACH-Detail.
  PmTilesVectorTileProvider? _worldPmtilesProvider;

  /// Eigenes Mapbox-Dark-ähnliches Theme für die self-hosted Protomaps-Tiles
  /// (einmal gebaut). Ersetzt das karge Standard-Protomaps-Dark.
  late final vtr.Theme _cruiseMapTheme =
      vtr.ThemeReader().read(cruiseDarkMapStyle);

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
          child: const Icon(
            Icons.play_arrow_rounded,
            color: color,
            size: 22,
          ),
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
          _safeSetState(() {}); // nächster Build nutzt _cachedUserCenter als initialCenter
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

  Future<geo.Position> _getStartCoordinates() async {
    // 2026-05-28 (vucko): "Standort wählen" mit gesetztem Punkt → von dort
    // starten (Karten-Tap oder Adresssuche). Dijkstra-Routing braucht nur
    // gültige Start-Koordinaten, egal woher.
    if (_selectedLocation == 'Standort wählen' &&
        _pickedStartLocation != null) {
      final picked = _pickedStartLocation!;
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

    // 2026-05-22 (vucko Task #7): Limit-Check vor Routensuche.
    // Normal-Mode: max 3 WPs, Trip-Mode: max 5. UI lässt mehr setzen damit
    // User experimentieren kann, hier kommt der freundliche Hinweis.
    if (_isWaypointPlanning && _roundTripWaypoints.length > _currentMaxWaypoints) {
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
    try {
      final startPosition = await _getStartCoordinates();
      if (_isRouteGenerationCancelled(generationId)) return;

      // 2026-05-30 (vucko): Heimatland automatisch aus dem Startpunkt ableiten
      // (offline-Heuristik, kein extra API-Call). Nur relevant wenn eine
      // Länder-Präferenz aktiv ist.
      if (_countryPreference != CountryPreference.any) {
        _homeCountryCode = CountryRegion.classify(
          startPosition.latitude,
          startPosition.longitude,
        );
      }

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
          // 2026-05-28 (vucko Task #83): One-Shot direkte Route ohne Quality-Reject.
          forceAcceptDirect: _forceAcceptDirectOnce,
          countryPreference: _countryPreference,
          homeCountryCode: _homeCountryCode,
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
            .map((p) => <String, double>{
                  'latitude': p.latitude,
                  'longitude': p.longitude,
                })
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
        _activeDetourVariant = tripDetourVariant;
        _activePointToPointScenic = tripScenic;
        _activePointToPointMode =
            tripScenic ? _selectedStyle : 'Standard';
        _activeAvoidHighways = _avoidHighways;
        final subscriptionTier = RouteService.resolveEffectiveSubscriptionTier(
          isTesterOrBeta: true,
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
          countryPreference: _countryPreference,
          homeCountryCode: _homeCountryCode,
        );
        // 2026-05-24 (vucko Task #53): Trip-Mode → Trip in DB persistieren
        // NUR wenn der User in einer Gruppen-Session ist. Solo-Touren werden
        // nicht als Resume-Card angezeigt (User-Wunsch), darum auch nicht
        // in der trips-Tabelle landen — vermeidet DB-Pollution.
        // Best-effort, fail silent (Trip-Persistierung darf nie das Routing blockieren).
        if (widget.groupId != null &&
            result.distanceMeters != null &&
            result.distanceMeters! > 0) {
          unawaited(_createTripInDb(
            startLat: startPosition.latitude,
            startLng: startPosition.longitude,
            waypoints: waypointSnapshot,
            style: _selectedStyle,
            avoidHighways: _avoidHighways,
            distanceKm: (result.distanceMeters! / 1000),
            durationSeconds: result.durationSeconds?.round() ?? 0,
          ));
        }
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
          countryPreference: _countryPreference,
          homeCountryCode: _homeCountryCode,
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
        (cleanedResult.edgeMeta['route_source'] ?? cleanedResult.edgeMeta['source'])
            ?.toString() ??
        '';
    final isPoolSourced = routeSource == 'pool' ||
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

    // 2026-06-02 (vucko KRITISCHER FIX): Der Länder-Gate war ein HARTER Block
    // (Route NICHT angezeigt + „keine reine Inlandsroute"-Sackgasse). In
    // Grenzregionen (Vorarlberg liegt minutennah an CH/LI/IT) gibt es fast nie
    // eine reine Inlandsroute → der User blieb stecken, SOGAR nach dem
    // Ausschalten von „Im Land bleiben". Das darf nie passieren. „Im Land
    // bleiben" ist jetzt wieder SOFT: es bevorzugt Inland NUR über den
    // Routen-Score (in der Generierung), blockiert die Anzeige aber NIEMALS —
    // die beste verfügbare Route wird immer gezeigt.

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
    final isRepeatedRoute = newFingerprint != null &&
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
    final canAutoRetry = isRepeatedRoute &&
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
          '[CruiseMode] Preview-Access-Leg fehlgeschlagen, zeige Route ohne Rebase: $e');
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
        (accuracyMeters != null && accuracyMeters.isFinite && accuracyMeters > 0)
        ? math.min(accuracyMeters, 60.0)
        : 0.0;
    final speed = (speedMps != null && speedMps.isFinite && speedMps > 0)
        ? speedMps
        : 0.0;
    final speedBuffer = speed > 22 ? 35.0 : (speed > 12 ? 18.0 : 0.0);
    return baseCorridor + accuracy * 0.8 + speedBuffer;
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
      _scheduleRouteSearchStatusDismiss(hold: const Duration(milliseconds: 1800));
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
      _distanceToFinalTargetMeters = null;
      _sessionRouteStartIndexInActiveRoute = 0;
      _navigationStartTime = null;
      _offRouteCount = 0;
      _lastRerouteTime = null;
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

  void _returnToCruiseSetupFromActiveRoute() {
    if (!mounted || _disposed) return;
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
        remappedManeuvers.add(RouteManeuver(
          latitude: m.latitude,
          longitude: m.longitude,
          routeIndex: bestIdx,
          icon: m.icon,
          announcement: m.announcement,
          instruction: m.instruction,
          maneuverType: m.maneuverType,
          roundaboutExitNumber: m.roundaboutExitNumber,
        ));
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
    // 2026-06-06 (vucko P2): Auch ein FEHLGESCHLAGENER Reroute verhängt den vollen
    // Cooldown → kein erneutes Antriggern alle ~12s (das war der Meldungs-Spam).
    _lastRerouteTime = DateTime.now();
    _rerouteBannerShown = false;
    // 2026-06-06 (vucko P6): Meldung NUR oben (TopToast), nicht mehr als orange
    // SnackBar unten. P7 deckelt automatisch auf ≤5s + Swipe-to-dismiss.
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      TopToast.show(
        context,
        message:
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
    _rerouteBannerShown = false;
    // 2026-06-06 (vucko P6): oben statt orange Bottom-SnackBar.
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

    _safeSetState(() {
      _routeGeoJson = result.geoJson;
      _routeDistance = result.distanceMeters;
      _routeDuration = result.durationSeconds;
      _originalRouteDistance = result.distanceMeters;
      _originalRouteDuration = result.durationSeconds;
      _fullRouteCoordinates = result.coordinates;
      _remainingRouteCoordinates = result.coordinates;
      _currentRouteIndex = 0;
      // 2026-06-07 (vucko P-reroute): Beim Reroute wird _fullRouteCoordinates
      // KOMPLETT ersetzt (neuer, oft kürzerer Array; Index 0 = aktueller GPS-
      // Standort, da der Connector via generatePointToPoint(startPosition) gebaut
      // wird). Lief der Fahrsimulator, behielt _simulationIndex seinen alten,
      // großen Wert → er indexierte den neuen Array am Ende (clamp auf lastIndex)
      // → Puck teleportierte ans Routenende, Bearing kollabierte → „fährt nach
      // Norden, zeigt Süden". Cursor auf 0 zurücksetzen = Sim fährt vom Standort
      // vorwärts weiter.
      if (_isSimulationRunning) {
        _simulationIndex = 0;
        _simulationDistanceM = 0.0;
        _simulationDistAtIndexM = 0.0;
        // 2026-06-08 (vucko DACH-Test): Reroute committet → Abweichung beenden,
        // der Sim folgt ab jetzt der NEUEN (re-gedockten) Route.
        _simDeviationRoute = null;
        _simDeviatedOnce = true;
      }
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
      _lastRerouteTime = DateTime.now();
      _remainingDistance = result.distanceMeters;
      _remainingDuration = result.durationSeconds;
      _distanceToFinalTargetMeters = null;
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
      // 2026-06-01 (vucko): Kopf nur an GPS heften, wenn das Fahrzeug WIRKLICH
      // auf der Linie ist (≤18m). Bei GPS-Drift (Bergtal) sonst Off-Route-Zacken.
      if (distanceToFirst <= _headSnapMaxMeters) {
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
    // 2026-06-06 (vucko P2/P4): Reroute-Banner-Flag zurücksetzen (nächster Off-
    // Route-Zyklus darf wieder genau EIN Banner zeigen) + die GRAUE Vorschau-/
    // Hintergrundroute deterministisch neu zeichnen (gleicher Signatur-
    // Fingerprint bei Rundkurs-Reroute hätte sie sonst stehen lassen).
    _rerouteBannerShown = false;
    _mlController?.forceResyncLines();
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
        _camFitBounds(
          [bounds.southWest, bounds.northEast],
          EdgeInsets.fromLTRB(24, safeTop + 18, 24, bottomPad),
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
    _cachedUserCenter = _userPosition; // 2026-06-06 (vucko P10): Center-Cache frisch halten
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
    _updateDistanceToFinalTarget(position);
    final previousVisibleManeuverIndex = _activeVisibleManeuverIndex();

    var isOutsideCorridor = match.distanceMeters > offRouteCorridor;
    final approachingDestination =
        !_isRoundTrip &&
        _activeDestinationCoordinate != null &&
        _isApproachingCurrentDestination(position);
    // Apple/Google-Regel: ein VORWÄRTS-laufender Puck fährt die Route — auch wenn
    // ein einzelner Fix seitlich zappelt. Dann niemals reroute.
    final makingForwardProgress = match.index > prevRouteIndex;

    // 2026-06-08 (vucko P-reroute): GLOBALER RE-SNAP (wie Apple/Google). Das
    // gefensterte Matching kann hinter dem Fahrer zurückbleiben (Fenster
    // [idx,idx+80] erreicht die echte Position nicht mehr) → es meldet fälschlich
    // „off-route", obwohl der Puck IN Wahrheit auf der Route ist (= die unnötigen
    // Reroutes nach einem Re-Dock). Meckert das Fenster, durchsuchen wir EINMAL
    // die ganze Route: liegt der nächste Punkt doch im Korridor, war es nur
    // Fenster-Verzug → re-ankern + NICHT off-route. Nur wirklich-daneben (auch
    // global > Korridor) zählt. Läuft nur wenn das Fenster off-route meldet →
    // kein Overhead im Normalbetrieb.
    if (isOutsideCorridor && !approachingDestination) {
      final globalMatch = findNearestInWindow(
        position: position,
        coordinates: _fullRouteCoordinates,
        currentIndex: 0,
        windowSize: _fullRouteCoordinates.length,
        maxJumpMeters: double.infinity,
      );
      if (globalMatch.distanceMeters <= offRouteCorridor) {
        _currentRouteIndex =
            globalMatch.index.clamp(0, _fullRouteCoordinates.length - 1);
        isOutsideCorridor = false; // doch auf der Route — nur Fenster nachgehinkt
      }
    }

    if (isOutsideCorridor && !approachingDestination && !makingForwardProgress) {
      // Zeit-basierte Hysterese: anhaltend ≥3.0s daneben ODER klar daneben
      // (≥2.5× Korridor, echtes Abbiegen) ≥1.5s. Kein Zappeln über Tick-Count.
      _offRouteSince ??= DateTime.now();
      final offFor = DateTime.now().difference(_offRouteSince!);
      final clearlyOffRoute = match.distanceMeters > offRouteCorridor * 2.5;
      final sustained = offFor >= const Duration(milliseconds: 3000) ||
          (clearlyOffRoute && offFor >= const Duration(milliseconds: 1500));
      if (sustained && !_isRerouting) {
        final now = DateTime.now();
        final cooldownOk = _lastRerouteTime == null ||
            now.difference(_lastRerouteTime!) >= _rerouteCooldown;
        if (cooldownOk) {
          _lastRerouteTime = now;
          _offRouteCount = 0;
          _offRouteSince = null;
          _rerouteToOriginalRoute(position);
          return;
        }
      }
    } else {
      // Im Korridor ODER Fortschritt ODER Ziel-Annäherung → Off-Route-Timer aus.
      _offRouteSince = null;
      _offRouteCount = 0;
    }

    var needsRebuild = false;
    if (!isOutsideCorridor &&
        _updateRemainingDistanceAndDuration(routeMatch: match)) {
      needsRebuild = true;
    }

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
        _distanceSinceLastRedraw += segmentMeters;
      }
      _currentRouteIndex = match.index;
      needsRebuild = true;
      _maybeFinalizeAccessLegPhase();

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
        // 2026-06-01 (vucko): Kopf nur an die GPS-Position heften, wenn das
        // Fahrzeug wirklich auf der Linie ist (≤18m). Vorher BEDINGUNGSLOS →
        // bei GPS-Drift in Bergtälern entstand ein Off-Route-Zacken vom realen
        // Routenpunkt zur seitlich versetzten Position. Bei größerem Versatz
        // bleibt der echte Routenpunkt der Kopf → Linie bleibt sauber auf der
        // Straße (kleine Lücke zum Punkt ist unkritisch, ein Zacken nicht).
        if (routeSlice.isNotEmpty) {
          final head = routeSlice[0];
          final distToHead = geo.Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            head[1],
            head[0],
          );
          if (distToHead <= _headSnapMaxMeters) {
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
    }

    // 2026-06-06 (vucko P3): JEDEN Tick den Kopf der roten Linie exakt auf die
    // projizierte Puck-Position setzen (entkoppelt vom groben 25m-Redraw oben,
    // der nur teure GeoJSON-/flutter_map-Updates throttelt). So folgt der
    // Linienkopf dem Standort lückenlos — nie davor, nie dahinter.
    if (!isOutsideCorridor && _trimVisibleRouteToProjection(match)) {
      needsRebuild = true;
    }

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
      // 300m → lightImpact + EINE saubere Vorankündigung.
      if (!_hapticStage300m && distToManeuver <= 300 && distToManeuver > 150) {
        HapticFeedback.lightImpact();
        _hapticStage300m = true;
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
      final filtered = pois.where((p) {
        final info = OpeningHoursParser.parse(p.openingHours);
        // Unbekannte/parseFailed → anzeigen (besser als nichts).
        if (info.parseFailed || info.status == OpenStatus.unknown) return true;
        return info.isOpenNow;
      }).take(50).toList();
      setState(() => _routePois = filtered);
    } catch (_) {/* silent */}
  }

  Widget _buildPoiMarker(RoutePoi poi) {
    final color = switch (poi.type) {
      PoiType.fuel => const Color(0xFFEF4444),         // rot — Tankstelle
      PoiType.restaurant => const Color(0xFFFB923C),   // orange — Restaurant
      PoiType.cafe => const Color(0xFFA78BFA),         // violett — Café
      PoiType.fastFood => const Color(0xFFFBBF24),     // gelb — Imbiss
      PoiType.pub => const Color(0xFF22C55E),          // grün — Pub
      PoiType.motorcycleRepair => const Color(0xFF2DD4BF),  // teal — Werkstatt
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
    final ringColor =
        isClosingSoon ? const Color(0xFFFB923C) : Colors.white;
    final ringWidth = isClosingSoon ? 2.6 : 2.2;
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: ringWidth),
        boxShadow: [
          BoxShadow(
            color: (isClosingSoon ? const Color(0xFFFB923C) : color)
                .withValues(alpha: 0.55),
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
    final hasActiveRoute = _lastRouteResult != null &&
        _fullRouteCoordinates.isNotEmpty;
    final canAddToRoute = hasActiveRoute &&
        widget.groupId == null &&
        !_isLoading;
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
          poi.latitude, poi.longitude, wp.latitude, wp.longitude,
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
    final exitIdx =
        math.min(coords.length - 1, nearestIdx + windowSize);
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
      final originalDistanceM = activeRoute.distanceMeters ??
          (activeRoute.distanceKm ?? 0) * 1000;
      final removedSegmentM = _approximateSegmentDistanceMeters(
        coords,
        entryIdx,
        exitIdx,
      );
      final patchDistanceM = patch.distanceMeters ??
          ((patch.distanceKm ?? 0) * 1000);
      final newDistanceM =
          (originalDistanceM - removedSegmentM + patchDistanceM)
              .clamp(0.0, double.infinity);
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
        // 2026-06-07 (vucko P-reroute): wie beim Reroute-Commit — wird die Route
        // mitten in der Sim-Fahrt durch einen POI-Umweg ersetzt, muss der Sim-
        // Cursor mit zurück auf 0, sonst indexiert er den neuen Array am Ende.
        if (_isSimulationRunning) {
          _simulationIndex = 0;
          _simulationDistanceM = 0.0;
          _simulationDistAtIndexM = 0.0;
        }
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
        poi.latitude, poi.longitude, wp.latitude, wp.longitude,
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
      child: const Icon(
        Icons.construction_rounded,
        size: 18,
        color: accent,
      ),
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
    final waypointRailActive = !hasRoute &&
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
                // Simulation Start/Stop — nur wenn Route da + sim enabled
                if (hasRoute &&
                    _isSimulationEnabled &&
                    _fullRouteCoordinates.length > 1)
                  _FabBubble(
                    heroTag: 'simulation_fab',
                    icon: _isSimulationRunning
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                    color: _isSimulationRunning
                        ? const Color(0xFFFF9500)
                        : const Color(0xFF34C759),
                    onPressed: _toggleSimulation,
                    big: true,
                  ),
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
                            VoiceMode.important =>
                                Icons.volume_down_rounded,
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
                  icon: _isCameraLocked
                      ? Icons.explore
                      : Icons.explore_off,
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
                  Icon(Icons.local_gas_station_rounded,
                      color: AppAccentColors.accent, size: 22),
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
                        backgroundColor:
                            AppAccentColors.accent.withValues(alpha: 0.20),
                        child: Text(p.type.emoji,
                            style: const TextStyle(fontSize: 16)),
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
  }) {
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
    final maneuver = _activeVisibleManeuver();
    if (maneuver == null) return null;
    return maneuver.instruction.isNotEmpty
        ? maneuver.instruction
        : maneuver.announcement;
  }

  /// Maschinenlesbarer Manöver-Typ (links/rechts/Kreisverkehr…) für die
  /// Auto-Displays — abgeleitet aus dem Icon des nächsten Manövers.
  String? _currentCarManeuverKind() {
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
  Future<void> _rerouteToOriginalRoute(geo.Position position) async {
    if (_isRerouting) return;
    _isRerouting = true;
    final remainingDistanceBeforeMeters = _remainingDistance ?? _routeDistance;
    final etaBeforeSeconds = _remainingDuration ?? _routeDuration;

    if (!await _hasConnectivityForReroute()) {
      _publishOfflineRerouteFallback(
        remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
        etaBeforeSeconds: etaBeforeSeconds,
      );
      _isRerouting = false;
      return;
    }

    if (mounted && !_rerouteBannerShown) {
      // 2026-06-06 (vucko P2): NUR EINMAL pro Reroute-Zyklus (vorher pro Versuch
      // → der Spam aus dem Test). P7 deckelt die Anzeige auf ≤5s.
      _rerouteBannerShown = true;
      TopToast.show(
        context,
        message: 'Route wird neu berechnet — bitte weiterfahren',
        icon: Icons.refresh_rounded,
        duration: const Duration(seconds: 5),
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
      final rerouteAvoidHighways = _effectiveNavigationAvoidHighways;

      // Suche den nächsten Punkt auf der GESAMTEN verbleibenden Route (großes Fenster)
      final globalMatch = findNearestInWindow(
        position: position,
        coordinates: planningCoordinates,
        currentIndex: accessLegMode ? 0 : _currentRouteIndex,
        windowSize: planningCoordinates.length,
        maxJumpMeters: double.infinity,
      );

      var heading = _userHeading;
      if (!heading.isFinite || heading < 0 || heading > 360) {
        heading = position.heading;
      }
      if (!heading.isFinite || heading < 0 || heading > 360) {
        heading = routeHeadingAt(
          planningCoordinates,
          globalMatch.index.clamp(0, planningCoordinates.length - 1),
        );
      }
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
        '[CruiseMode] Smart reroute plan: ${smartPlan.debugLabel}, strategy=${smartPlan.strategy.name}, rejoin=${smartPlan.rejoinIndex}',
      );

      final destination = _activeDestinationCoordinate;
      if (!_isRoundTrip && destination != null && !accessLegMode) {
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
            maxSearchMsOverride: 7500,
            currentHeadingDegrees: heading,
            currentSpeedMetersPerSecond: rerouteSpeedMps,
            locationAccuracyMeters: rerouteAccuracyMeters,
          );
        } catch (e) {
          debugPrint('[CruiseMode] Direkter Ziel-Reroute fehlgeschlagen: $e');
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
          if (!destinationQuality.passed ||
              destinationTooFewPoints ||
              highwayViolation) {
            debugPrint(
              '[CruiseMode] Direkter Ziel-Reroute verworfen: Qualität/Highway-Policy unzureichend.',
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
            return;
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
            maxSearchMsOverride: 7500,
            currentHeadingDegrees: heading,
            currentSpeedMetersPerSecond: rerouteSpeedMps,
            locationAccuracyMeters: rerouteAccuracyMeters,
          );
        } catch (e) {
          rejoinIndex = math.min(rejoinIndex + 80, maxRejoinIndex).toInt();
          debugPrint(
            '[CruiseMode] Reroute-Attempt ${attempt + 1}: keine Route (${e.runtimeType})',
          );
          continue;
        }

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
        final highwayViolation = violatesNoHighwayPolicy(
          avoidHighways: rerouteAvoidHighways,
          edgeMeta: candidate.edgeMeta,
        );
        if (!candidateQuality.passed ||
            candidateTooFewPoints ||
            highwayViolation) {
          rejoinIndex = math.min(rejoinIndex + 80, maxRejoinIndex).toInt();
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
            currentHeadingDegrees: heading,
            currentSpeedMetersPerSecond: rerouteSpeedMps,
            locationAccuracyMeters: rerouteAccuracyMeters,
          );
          if (connector.coordinates.length >= 2 && mounted && !_disposed) {
            final connLen = connector.coordinates.length;
            final tail = planningCoordinates.sublist(rejoinIdx);
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
            return;
          }
        } catch (e) {
          debugPrint(
              '[CruiseMode] Garantierter Re-Dock-Fallback fehlgeschlagen: $e');
        }
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
      // 2026-05-25 (vucko UX): klarer Fail-Toast wenn Reroute nicht klappt.
      // Vorher: Snackbar verschwand still → User wusste nicht ob das System
      // versucht hat oder noch wartet.
      if (mounted && !_disposed) {
        TopToast.show(
          context,
          message: 'Route konnte nicht neu berechnet werden — folge der alten Linie',
          icon: Icons.warning_amber_rounded,
          duration: const Duration(milliseconds: 3500),
        );
      }
    } finally {
      _isRerouting = false;
    }
  }

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
    final targetIndex = maneuver.routeIndex
        .clamp(0, _fullRouteCoordinates.length - 1)
        .toInt();
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

  // 2026-06-07 (vucko P-centering): Der Kamera-FAB ist jetzt ein EXPLIZITER
  // RECENTER, KEIN Toggle mehr. Vorher: beim Start ist _isCameraLocked bereits
  // true (Sim/Nav) → der erste Tap flippte auf false und ZENTRIERTE NICHT
  // („Button tut nichts / Kamera driftet weg"). Jetzt: Tap = immer auf den
  // Standort zentrieren + Follow an. Entriegelt wird NUR per Finger-Pan (P1).
  void _toggleCameraLock() {
    _safeSetState(() => _isCameraLocked = true);
    _recenterMap();
  }

  Future<void> _recenterMap() async {
    final position = _userLocation;
    if (position == null || !_mapReady) return;
    // 2026-06-08 (vucko Butterweich): Recenter über den Smooth-Follow-Ticker.
    // Kamera-Stand UND Ziel auf den Standort setzen (Snap), Ticker (re)starten —
    // kein konkurrierendes animateCamera mehr.
    final heading = (_userHeading.isFinite && _userHeading >= 0)
        ? _userHeading
        : _lastCameraHeading;
    _camCurLat = position.latitude;
    _camCurLng = position.longitude;
    _camCurHeading = heading;
    _camToLat = position.latitude;
    _camToLng = position.longitude;
    _camToHeading = heading;
    _lastCameraHeading = heading;
    _camHasState = true;
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
      _camFitBounds(
        routeLatLngs,
        const EdgeInsets.fromLTRB(40, 80, 40, 160),
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
    _simulationDistanceM = 0.0;
    _simulationDistAtIndexM = 0.0;
    _currentRouteIndex = 0;
    _lastDrawnRouteIndex = 0;
    _distanceSinceLastRedraw = 0.0;
    _totalDistanceDriven = 0;
    _drivenTrackRecorder.reset();
    _navigationStartTime = DateTime.now();
    _announcedManeuverIndices.clear();
    _activeManeuverIndex = 0;
    // Speed-History entfernt
    _isSimulationRunning = true;
    // 2026-06-08 (vucko): Konstant 30 km/h (Sim-Speed, distanz-interpoliert).
    _simulationSpeedKmh = _simulationConstantKmh;

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

      // 2026-06-08 (vucko Sim-Speed-Fix): DISTANZ-basierte Interpolation entlang
      // der Polyline statt „mind. 1 Vertex pro Tick". GraphHopper-Vertices liegen
      // 10–100m auseinander → der alte „1 Punkt/50ms" lief mit tausenden km/h.
      // Jetzt: pro Tick exakt speedMs*0.05m weiter; Position WIRD im Segment
      // interpoliert → echte konstante 30 km/h + butterweich.
      final speedMs = _simulationSpeedKmh / 3.6;
      _simulationDistanceM += speedMs * 0.05; // Meter in 50ms

      // Vertex-Cursor vorrücken, bis das aktuelle Segment die Ziel-Distanz enthält.
      while (_simulationIndex < lastIndex) {
        final a = _fullRouteCoordinates[_simulationIndex];
        final b = _fullRouteCoordinates[_simulationIndex + 1];
        final segLen = geo.Geolocator.distanceBetween(a[1], a[0], b[1], b[0]);
        if (segLen <= 0) {
          _simulationIndex++;
          continue;
        }
        if (_simulationDistAtIndexM + segLen >= _simulationDistanceM) break;
        _simulationDistAtIndexM += segLen;
        _simulationIndex++;
      }

      if (_simulationIndex >= lastIndex) {
        _simulationIndex = lastIndex;
        _stopSimulation(restartLiveTracking: false);
        _onRouteCompleted();
        return;
      }

      final segA = _fullRouteCoordinates[_simulationIndex];
      final segB = _fullRouteCoordinates[_simulationIndex + 1];
      final segLen =
          geo.Geolocator.distanceBetween(segA[1], segA[0], segB[1], segB[0]);
      final segFrac = segLen > 0
          ? ((_simulationDistanceM - _simulationDistAtIndexM) / segLen)
              .clamp(0.0, 1.0)
          : 0.0;
      // Interpolierte Position INNERHALB des Segments (smooth, exakte Speed).
      var current = <double>[
        segA[0] + (segB[0] - segA[0]) * segFrac,
        segA[1] + (segB[1] - segA[1]) * segFrac,
      ];
      var next = segB;

      // 2026-06-08 (vucko DACH-Test): ON-ROAD-Abweichung für den Reroute-Test.
      // Nach _simDeviateAfterMeters einmalig eine echte GraphHopper-Route quer
      // zur Fahrtrichtung holen und abfahren (bleibt auf Straßen) → realistisches
      // Off-Route. Endet, wenn der Abweichungs-Pfad zu Ende ist oder ein Reroute
      // committet (dort wird _simDeviationRoute genullt).
      if (_simDeviateEnabled &&
          !_simDeviatedOnce &&
          _simDeviationRoute == null &&
          !_simDeviateRequested &&
          _simulationDistanceM > _simDeviateAfterMeters) {
        _simDeviateRequested = true;
        unawaited(_fetchOnRoadDeviation(current, _userHeading));
      }
      final dev = _simDeviationRoute;
      if (dev != null && dev.length >= 2) {
        final devLast = dev.length - 1;
        _simDeviationDistM += speedMs * 0.05;
        while (_simDeviationIndex < devLast) {
          final a = dev[_simDeviationIndex];
          final b = dev[_simDeviationIndex + 1];
          final sl = geo.Geolocator.distanceBetween(a[1], a[0], b[1], b[0]);
          if (sl <= 0) {
            _simDeviationIndex++;
            continue;
          }
          if (_simDeviationDistAtIndexM + sl >= _simDeviationDistM) break;
          _simDeviationDistAtIndexM += sl;
          _simDeviationIndex++;
        }
        if (_simDeviationIndex >= devLast || _simDeviationDistM > 1200.0) {
          // Abweichung endet (Pfad zu Ende ODER ~1.2km gefahren = kurzer,
          // realistischer Falsch-Abzweig) → Sim folgt der (neuen) Route.
          _simDeviatedOnce = true;
          _simDeviationRoute = null;
        } else {
          final da = dev[_simDeviationIndex];
          final db = dev[_simDeviationIndex + 1];
          final dl =
              geo.Geolocator.distanceBetween(da[1], da[0], db[1], db[0]);
          final df = dl > 0
              ? ((_simDeviationDistM - _simDeviationDistAtIndexM) / dl)
                  .clamp(0.0, 1.0)
              : 0.0;
          current = <double>[
            da[0] + (db[0] - da[0]) * df,
            da[1] + (db[1] - da[1]) * df,
          ];
          next = db;
        }
      }

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
    } catch (e) {
      debugPrint('[Sim] Simulationsschritt fehlgeschlagen: $e');
    } finally {
      _isSimulationStepRunning = false;
    }
    if (_isSimulationRunning) _scheduleNextSimulationStep();
  }

  // 2026-06-08 (vucko DACH-Test): holt eine ECHTE GraphHopper-Route quer zur
  // Fahrtrichtung als On-Road-Abweichungs-Pfad (nur SIM_DEVIATE). So bleibt der
  // Test-Puck auf Straßen statt geradeaus ins Gelände zu fahren.
  Future<void> _fetchOnRoadDeviation(List<double> from, double headingDeg) async {
    try {
      // 2026-06-08 (vucko): Abweichungs-Ziel NACH AUSSEN (weg vom Routen-
      // Schwerpunkt), nicht senkrecht — sonst kürzt die Abweichung bei dünnen
      // Schleifen zur Gegenseite ab und der Reroute rejoint 60km voraus. Außen =
      // der Puck verlässt die Schleife → Reroute rejoint nahe der Abzweigung.
      double cLat = 0, cLng = 0;
      final n = _fullRouteCoordinates.length;
      for (final c in _fullRouteCoordinates) {
        cLng += c[0];
        cLat += c[1];
      }
      cLat /= n;
      cLng /= n;
      var mLat = (from[1] - cLat) * 111000.0;
      var mLng = (from[0] - cLng) * 75000.0;
      final mag = math.sqrt(mLat * mLat + mLng * mLng);
      if (mag < 1.0) {
        // Puck ~im Zentrum → Fallback senkrecht.
        final perpRad = (headingDeg + 90.0) * math.pi / 180.0;
        mLat = math.cos(perpRad);
        mLng = math.sin(perpRad);
      } else {
        mLat /= mag;
        mLng /= mag;
      }
      const outM = 900.0; // ~0.9 km nach außen
      final destLat = from[1] + (mLat * outM) / 111000.0;
      final destLng = from[0] + (mLng * outM) / 75000.0;
      final res = await _routeService.generatePointToPoint(
        startPosition: geo.Position(
          latitude: from[1],
          longitude: from[0],
          timestamp: DateTime.now(),
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
        destinationLat: destLat,
        destinationLng: destLng,
        mode: 'Standard',
        scenic: false,
        routeVariant: 0,
        avoidHighways: true,
        forceAcceptDirect: true,
        subscriptionTier: 'premium',
      );
      if (!_disposed && res.coordinates.length >= 2) {
        _simDeviationRoute = res.coordinates;
        _simDeviationIndex = 0;
        _simDeviationDistM = 0.0;
        _simDeviationDistAtIndexM = 0.0;
        debugPrint('[SIMDEV] ON-ROAD Abweichung gesetzt: '
            '${res.coordinates.length} Punkte, '
            '${res.distanceKm?.toStringAsFixed(1)} km');
      } else {
        _simDeviatedOnce = true;
      }
    } catch (e) {
      debugPrint('[SIMDEV] Abweichung-Fetch fehlgeschlagen: $e');
      _simDeviatedOnce = true;
    }
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
          _resetAfterCompletion();
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
            _resetAfterCompletion();
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

    await GamificationService.recordDriveSession(
      distanceKm: drivenKm,
      durationSeconds: adjustedResult.durationSeconds?.round() ?? 0,
      completedAtEnd: completed,
      routeStyle: _selectedStyle,
      routeType: _isRoundTrip ? 'ROUND_TRIP' : 'POINT_TO_POINT',
      routeFingerprint: adjustedResult.edgeMeta['route_fingerprint']
          ?.toString(),
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

  void _resetAfterCompletion() {
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
      unawaited(_safeCompleteTrip(tripIdToComplete));
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
          stopType: isLast ? 'end' : 'waypoint',
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
        debugPrint('[CruiseMode] Trip #$tripId in DB erstellt mit ${stops.length} Stops');
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
              BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 18,
              ),
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
                    color:
                        atLimit ? const Color(0xFFFFB74D) : Colors.white,
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
            alignment:
                tripEnabled ? Alignment.centerRight : Alignment.centerLeft,
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
