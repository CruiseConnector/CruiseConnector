import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/cruise_ui_rules.dart';
import 'package:flutter/services.dart'
    show HapticFeedback, SystemChrome, DeviceOrientation;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:floating/floating.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/route_bookmark_provider.dart';
import 'package:cruise_connect/application/providers/saved_routes_provider.dart';
import 'package:cruise_connect/data/services/web_position_smoother.dart';
import 'package:cruise_connect/data/services/compass_heading_service.dart';
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
import 'package:cruise_connect/data/services/active_ride_snapshot_service.dart';
import 'package:cruise_connect/data/services/driven_track_recorder.dart';
import 'package:cruise_connect/data/services/geo_bearing.dart';
import 'package:cruise_connect/data/services/geo_distance.dart';
import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:cruise_connect/data/services/navigation_android_notification_service.dart';
import 'package:cruise_connect/data/services/navigation_live_activity_service.dart';
import 'package:cruise_connect/data/services/navigation_reroute_decision.dart';
import 'package:cruise_connect/data/services/navigation_progress_socket_service.dart';
import 'package:cruise_connect/data/services/offline_map_service.dart';
import 'package:cruise_connect/data/services/map_style_service.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;
import 'package:cruise_connect/data/services/cruise_dark_map_style.dart';
import 'package:cruise_connect/data/services/app_tutorial_service.dart';
import 'package:cruise_connect/data/services/frame_timing_utils.dart';
import 'package:cruise_connect/data/services/group_route_data_builder.dart';
import 'package:cruise_connect/data/services/analytics_service.dart';
import 'package:cruise_connect/data/services/location_permission_helper.dart';
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
import 'package:cruise_connect/presentation/controllers/cruise_navigation_controller.dart';
import 'package:cruise_connect/presentation/pages/cruise/route_loading_phases.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_completion_dialog.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_maneuver_indicator.dart';
import 'package:cruise_connect/presentation/widgets/cruise/voice_volume_sheet.dart';
import 'package:cruise_connect/presentation/widgets/cruise/nav_distance_format.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_navigation_info_panel.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_setup_card.dart';
import 'package:cruise_connect/presentation/widgets/cruise/drive_control_panel.dart';
import 'package:cruise_connect/presentation/widgets/cruise/routing_onboarding_sheet.dart';
import 'package:cruise_connect/presentation/widgets/cruise/construction_alert_sheet.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_maplibre_map.dart';
import 'package:cruise_connect/domain/models/construction_report.dart';
import 'package:cruise_connect/domain/models/road_incident.dart';
import 'package:cruise_connect/presentation/widgets/cruise/incident_alert_sheet.dart';
import 'package:cruise_connect/presentation/widgets/cruise/incident_report_sheet.dart';
import 'package:cruise_connect/data/services/construction_geofence.dart';
import 'package:cruise_connect/data/services/construction_report_service.dart';
import 'package:cruise_connect/data/services/navigation_pip_service.dart';
import 'package:cruise_connect/data/services/road_incident_geofence.dart';
import 'package:cruise_connect/data/services/road_incident_service.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/cruise_group_service.dart';
import 'package:cruise_connect/data/services/route_quality_validator.dart';
import 'package:cruise_connect/domain/models/group_member.dart';
import 'package:cruise_connect/presentation/pages/group_lobby_page.dart';

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
  static final ValueNotifier<String?> pendingGroupView = ValueNotifier<String?>(
    null,
  );

  /// 2026-06-25 (vucko): Anforderung „öffne den Cruise-Tab" (z.B. aus der
  /// Wetter-Benachrichtigung). Zähler — Home hört darauf und schaltet auf den
  /// Cruise-Tab (Index 2). So landet man im echten Tab mit Bottom-Nav, nicht
  /// auf einer losen Vollbild-Seite.
  static final ValueNotifier<int> openCruiseTab = ValueNotifier<int>(0);

  /// 2026-06-20 (vucko Gruppen-Rejoin): Geräte-lokales Set von Gruppen, deren
  /// AKTIVE Fahrt der Nutzer bewusst verlassen hat. Die Lobby darf ihn dann
  /// NICHT automatisch zurück in die Navigation ziehen — sonst reisst ihn der
  /// nächste Leader-Reroute (jede Route-Änderung pingt die Lobby) sofort wieder
  /// rein. Rejoin passiert NUR bewusst über den „Zur laufenden Route"-Button.
  /// Wird geleert, sobald die Gruppe inaktiv wird oder bewusst rejoined wird.
  static final Set<String> suppressedAutoEnterGroupIds = <String>{};

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
    // 2026-06-20 (vucko Live-Activity-Sync): Lead-Kompensation NUR im Hintergrund
    // (Sperrbildschirm/Dynamic-Island ohne sichtbare In-App-Zahl). Im Vordergrund
    // exakt senden, damit Dynamic Island und In-App-Banner dieselbe Zahl zeigen.
    _appInForeground = state == AppLifecycleState.resumed;
    // 2026-07-06 (vucko Fahrt-Resume): Beim Backgrounding SOFORT einen
    // Snapshot der laufenden Fahrt sichern — genau jetzt kann iOS die App
    // jederzeit beenden (der Bug: pausierte Fahrt war nach App-Kill komplett
    // weg, nirgends auffindbar, nicht fortsetzbar).
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _persistActiveRideSnapshot(force: true, paused: _isPaused);
      // 2026-07-22 (vucko Free-Cam-Kompass): Magnetometer im Hintergrund
      // nicht weiterlaufen lassen (Akku) — Resume startet ihn bei Bedarf neu.
      _stopCompass();
    }
    if (state != AppLifecycleState.resumed || !mounted || _disposed) return;
    _startCompassIfNeeded();

    // 2026-07-03 (vucko Async-nach-Resume, Geräte-Video 07-03): Der Kamera-/
    // Render-Ticker (AnimationController mit vsync) wird von Flutter GEMUTET,
    // sobald die App nicht sichtbar ist (Sperrbildschirm/Live-Preview). Kamera,
    // Puck-Render und Linien-Trim frieren also am letzten Frame ein, WÄHREND der
    // GPS-Stream im Hintergrund weiterläuft und den Smoother (_lastTimestamp,
    // _lat/_lng) fortschreibt. Beim Resume liefert predict() dann die volle
    // 1,5-s-Dead-Reckoning-Extrapolation ab dem eingefrorenen Render-Stand →
    // Puck/Linie springen und „rennen nach" (genau das beobachtete Asynchrone).
    // Gegenmittel: VOR dem ersten Render-Frame hart re-synchronisieren — in
    // ALLEN Fahrmodi, nicht nur wenn zentriert. rebaseToNow() setzt die
    // Prediction-Baseline auf jetzt (kein Extrapolations-Sprung), _resetPuckBlend
    // killt den alten Interpolationsrest, und Render-Lock + Linie werden auf den
    // aktuellen Standort verankert → sofort synchron.
    _nativeSmoother.rebaseToNow();
    _resetPuckBlend();
    // 2026-07-22 (vucko „GPS veraltet"-Fehlmeldung): Beim Resume wurde bisher
    // alles resynct (Smoother, Kamera, Render-Lock, Gruppen-Realtime) — nur der
    // GPS-Stall-Zustand nicht. Ein im Hintergrund aufgelaufenes Fix-Gap wurde so
    // beim Aufsperren sofort als „GPS-Signal schwach" gewertet, obwohl kein
    // Empfangsproblem vorlag. Stempel frisch setzen + kurze Gnadenfrist + ein
    // evtl. hängendes Flag sofort löschen.
    _lastLocationFixAt = DateTime.now();
    _resumeGpsGraceUntil = DateTime.now().add(const Duration(seconds: 8));
    if (_gpsWeak) {
      _gpsWeak = false;
      _safeSetState(() {});
    }
    final resumeLoc = _userLocation;
    if (resumeLoc != null &&
        _isRouteConfirmed &&
        _fullRouteCoordinates.length >= 2) {
      final resumeDist = _projectDistOnRoute(
        resumeLoc.latitude,
        resumeLoc.longitude,
        DateTime.now(),
      );
      if (resumeDist != null) {
        _reanchorRenderLockToDistance(resumeDist);
        final match = _lastWindowMatch;
        if (match != null) _trimVisibleRouteToProjection(match);
      }
    }

    // 2026-06-24 (vucko Geräte-Video): Nach Hintergrund (Lock/Anruf/App-Switch/
    // Vollbild-Werbung) blieb die Navi-Kamera im Free-Cam hängen — Puck UND
    // Mitfahrer scrollten aus dem Bild („Standort weg / man sieht sich nicht
    // mehr"), die Re-Center-Taste war ausgegraut und rastete nie wieder ein.
    // Beim Zurückkommen die zentrierte Navi-Kamera wieder einrasten (Single +
    // Gruppe), wie Google/Apple Maps.
    if (_isRouteConfirmed && !_isOverviewActive) {
      if (!_isCameraLocked) {
        _safeSetState(() => _isCameraLocked = true);
      }
      unawaited(_recenterMap());
    }

    final groupId = widget.groupId;
    if (groupId == null) return;
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
  final _smartRerouteEngine = const SmartRerouteEngine();
  final _navigationSocketService = NavigationProgressSocketService();
  final _navigationController = CruiseNavigationController();
  final _drivenTrackRecorder = DrivenTrackRecorder();
  // 2026-06-23 (vucko Post-Route Top-Speed): höchstes geglättetes Tempo der
  // aktuellen Fahrt (m/s). Smoother statt Roh-GPS → kein Multipath-Spike; <100
  // m/s-Guard filtert absurde Glitches. Reset bei jeder NEUEN Fahrt.
  double _maxSpeedMps = 0.0;

  // ─────────────────────── Route Setup State ─────────────────────────────────
  bool _isRoundTrip = true;
  String _planningType = 'Zufall';
  String _selectedLength = '50 km';
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
  // 2026-07-06 (vucko Routen-Wiederholung): Umweg-Level („Direkt/Klein/
  // Mittel/Groß") wurde in settingsChanged NICHT verglichen → ein Wechsel
  // von „kleiner Umweg" auf „mittlerer Umweg" wurde als searchAgain statt
  // settingsChanged behandelt und konnte die alte Route wieder zeigen.
  String? _lastGeneratedDetour;
  // 2026-07-06 (vucko Routen-Wiederholung): monotoner Salt pro Suche.
  // Vorher floss forceFreshVariant als BOOL in den p2pDiversitySeed —
  // ab der 2. Generierung war der Seed damit für immer identisch
  // (1. Suche: false, jede weitere: true) → Versuch 3+ lieferte immer
  // wieder die Route aus Versuch 2.
  int _p2pSearchSalt = 0;
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

  /// Marker-Größe: einheitlich der kompakte Apple-Maps-Puck (44px) auf ALLEN
  /// Plattformen. 2026-06-21 (vucko Geräte-Video): der alte 80px-Android-Puck
  /// trug einen großen transluzenten Accuracy-Halo („zwei Ringe") — entfernt.
  double get _puckSize => 44.0;

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
  // 2026-06-25 (vucko Marker-Swim, native): vorgerasterte POI/Baustellen-Icons
  // (Key → PNG-Bytes) für den nativen Symbol-Layer + Guard gegen Mehrfach-Raster.
  final Map<String, Uint8List> _poiIconImages = {};
  bool _poiIconRasterInFlight = false;
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
  // 2026-07-24 (vucko "+-Button"): Crowd-Verkehrsmeldungen (Unfall/Baustelle/
  // Stau) — gleiche Architektur wie das Baustellen-System darüber, plus
  // Realtime-Sync (andere Fahrer sehen Meldungen live) und Stau-Ausdehnungs-
  // Tracking des Melders.
  List<RoadIncident> _routeIncidents = const [];
  final RoadIncidentGeofence _incidentGeofence = RoadIncidentGeofence();
  String? _activeIncidentAlertId;
  RealtimeChannel? _incidentChannel;
  Timer? _incidentRefetchDebounce;
  DateTime? _lastLivePositionPushAt;
  String? _jamTrackingIncidentId;
  DateTime? _jamTrackingStartedAt;
  DateTime? _jamRecoverySince;
  // 2026-05-23 (vucko): Haptic-Tracking damit jede Stufe (300m/150m/50m)
  // nur 1× pro Manöver feuert statt bei jedem GPS-Tick.
  int? _lastHapticManeuverIndex;
  // 2026-06-22 (vucko Autobahn-Ausfahrt): welcher Manöver-Index schon eine
  // (geschwindigkeitsabhängige) Voice-Vorankündigung bekommen hat.
  int? _voicePreAnnouncedManeuverIndex;
  // 2026-07-02 (vucko Geräte-Video Voice-Chaos): Beim Start-Snap kriecht der
  // Routen-Index über mehrere Ticks nach vorn und „überrollt" Manöver — jedes
  // bekam eine Vorankündigung (Ansagen-Stau). Vorankündigung erst, wenn der
  // sichtbare Manöver-Index kurz STABIL blieb. Zusätzlich merken wir den
  // vorangekündigten TEXT: die „Jetzt"-Ansage nutzt denselben Wortlaut, damit
  // nicht zwei Formulierungen/Straßennamen fürs selbe Manöver zu hören sind
  // (GH-/Mapbox-/Kreisel-Promotion-Texte unterscheiden sich).
  int? _voiceStableManeuverIndex;
  DateTime? _voiceManeuverStableSince;
  String? _voicePreAnnouncedText;
  bool _hapticStage300m = false;
  bool _hapticStage150m = false;
  bool _hapticStage50m = false;
  StreamSubscription<geo.Position>? _positionSubscription;
  StreamSubscription<geo.Position>? _socketPositionSubscription;
  StreamSubscription<geo.Position>?
  _idlePositionSubscription; // Standort-Stream für Heading im Idle

  // 2026-06-19 (vucko Kreisverkehr-Sim-Test): Fahrsimulator NUR in Debug-Builds
  // wieder aktiv. Speist synthetische GPS-Positionen entlang der Route in den
  // ECHTEN _onLocationUpdate-Intake — testet damit exakt die Live-Logik (inkl.
  // Kreisverkehr-Symbol/Nummer + GPS-Ausreißer-Gate + Render-Lock), nicht einen
  // Sonderpfad. kDebugMode-gated → kommt nie in TestFlight/Store.
  bool _isSimulationRunning = false;
  Timer? _simTimer;
  int _simIndex = 0;
  double _simDistM = 0.0;
  double _simDistAtIndexM = 0.0;
  static const int _simTickMs = 100; // 10 Hz
  static const double _simSpeedKmh = 30.0;

  bool _isCameraLocked =
      false; // Compass-Toggle: true = Kamera folgt dem Standort
  double? _remainingDistance; // Live verbleibende Distanz in Metern
  double? _remainingDuration; // Live verbleibende Zeit in Sekunden
  bool _isRerouting = false; // Verhindert mehrfaches gleichzeitiges Rerouting
  DateTime? _rerouteStartedAt;
  // 2026-06-22 (vucko Reroute-Hang): Sicherheits-Watchdog. Falls ein await im
  // Reroute-Pfad wider Erwarten nicht zurückkommt (hängendes Plugin/SDK), wird
  // _isRerouting garantiert zurückgesetzt und ein sanfter Fallback gezeigt,
  // statt das Banner endlos auf „Neuberechnung" stehen zu lassen.
  Timer? _rerouteWatchdog;
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

  // 2026-06-18 (vucko Video: Puck springt voraus und wartet): Zähler + Zeitanker
  // für abgelehnte Index-Vorschübe. Früher wurde nach 2 Rejects trotzdem committed;
  // genau das konnte den Render-Lock auf ein Zukunfts-Leg ziehen. Jetzt wächst das
  // erlaubte Meterbudget mit real verstrichener Zeit seit dem letzten akzeptierten
  // Index — echte Fahrt auf sparser Geometrie kommt weiter, Selbstüberlapp-Teleports
  // bleiben blockiert.
  int _advanceCapRejects = 0;
  DateTime? _lastRouteIndexAdvanceAt;
  // 2026-06-23 (vucko 2-Geräte-Video „Banner+Rest-km frieren nach verpasstem
  // Turn ein"): Frozen-Progress-Watchdog. Friert die Distanz-entlang-der-Route
  // (Render-Lock) trotz klarer Fahrt zu lange ein (Map-Matcher klebt am
  // verpassten Manöver, Off-Route feuert noch nicht), wird EIN Reroute erzwungen.
  double? _lastRenderDistForFreeze;
  DateTime? _renderDistChangedAt;
  // 2026-06-23 (vucko 2-Geräte-Video „Nav-Freeze bei GPS-Verlust" + „GPS-Hinweis"):
  // GPS-Stall-Watchdog. Friert der Standort-Stream ein (Tunnel/Wald), clampt der
  // Smoother-Predict nach 1,5s → location-getriebener Nav-Tick + Puck + Banner
  // froren ein. Timer-basiert (unabhängig vom Stream).
  DateTime? _lastLocationFixAt; // wann kam der letzte verarbeitete GPS-Fix
  double _gpsLastFixSpeedMps = 0.0; // Tempo beim LETZTEN Fix (fährt vs. steht)
  DateTime?
  _lastStallGlideAt; // letzter Dead-Reckoning-Glide-Tick während Stall
  Timer? _gpsStallWatchdog;
  bool _gpsWeak = false; // „GPS schwach"-Hinweis sichtbar?
  // 2026-07-22 (vucko): 5s war knapper als Google/Apple-Praxis (15-30s) und
  // feuerte bei alltäglichen, harmlosen 5-8s-Fix-Lücken (Kreuzung unter Brücke,
  // dichte Bäume). 10s zeigt echte Ausfälle (Tunnel) immer noch schnell genug.
  static const Duration _gpsWeakThreshold = Duration(seconds: 10);
  // 2026-07-22 (vucko „GPS veraltet"-Fehlmeldung): Nach App-Resume ist ein
  // Fix-Gap normal (OS drosselt Background-Delivery) — Gnadenfrist statt
  // sofortiger Warnung im Moment des Aufsperrens.
  DateTime? _resumeGpsGraceUntil;
  static const Duration _gpsStallGlideThreshold = Duration(milliseconds: 1800);

  // 2026-06-24 (vucko Y4): dezenter „kein Internet"-Hinweis während der Fahrt
  // (Single + Gruppe). Interface-down (Flugmodus/kein Empfang) → Pille; stört
  // Banner/Buttons nicht (eigene Safe-Zone darunter). Karte ist offline gecacht,
  // die Fahrt läuft weiter — der Hinweis ist nur Info.
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _offline = false;

  // 2026-06-17 (vucko Geräte-Video: Standort-Teleport + grundloses Reroute):
  // GPS-Ausreißer-Gate. Letzter als plausibel akzeptierter ROH-Fix + Zähler der
  // am Stück verworfenen Ausreißer. Ein physikalisch unmöglicher Sprung
  // (Multipath/Stadt-Schlucht: Accuracy ok, Position springt 50–150 m) wird für
  // die GESAMTE Logik verworfen → kein Puck-Teleport, kein grundloses Reroute.
  // Fail-open nach _maxGpsJumpRejects, damit ein ECHTER anhaltender Sprung
  // (Tunnelausfahrt / GPS-Recovery) nicht einfriert.
  geo.Position? _lastPlausibleRawFix;
  int _gpsJumpRejects = 0;
  static const int _maxGpsJumpRejects = 4;

  // 2026-06-17 (vucko Geräte-Video: Manöver-Distanz friert ein / springt HOCH):
  // Monotone Banner-Distanz liegt jetzt im CruiseNavigationController.
  String? _lastLiveActivitySignature;
  DateTime? _lastLiveActivitySentAt;
  String? _lastLiveActivityCoreKey;

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
  // 2026-06-17 (vucko Kaltstart-Reroute): Wurde der Puck in DIESER Sitzung schon
  // EINMAL eingerastet? Nur im allerersten Kaltstart-Fenster (nie eingerastet)
  // gilt die abgesenkte Reroute-Schwelle (1,4× statt 2× Korridor), damit eine
  // echte Start-Fehlroute in ~4s statt ~11s korrigiert wird. Nach Reroutes
  // (_routeLockedOn wieder false, aber everLocked=true) bleibt es bei 2× — kein
  // Re-Reroute-Loop.
  bool _everLockedOn = false;
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
  // 2026-06-12 (vucko): Manöver-Ueberfahren-Tracking für den Sofort-Reroute.
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
  // wieder verlässt (haeufig beim Verfahren), wartete sonst sichtbar lange
  // auf den nächsten Versuch. Fehlschlaege behalten ihren eigenen Cooldown.
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
  // 2026-06-25 (vucko Foto-Persistenz): id der aufgenommenen Drive-Session, um
  // ein erst im Abschluss-Sheet hinzugefügtes Foto nachtragen zu können.
  String? _recordedDriveSessionId;
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
  // Zeitstempel (ms) + Geschwindigkeit [vlng,vlat] deg/s je Peer für
  // Dead-Reckoning-Extrapolation zwischen Updates.
  final Map<String, int> _peerFixTimeMs = {};
  final Map<String, List<double>> _peerVelDegPerSec = {};
  String? _myUserId;
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
  // 2026-06-23 (vucko 2-Geräte-Gruppen-Video, C2): Ein off-route Follower zieht
  // die Leader-Route SOFORT per Backfill (statt nur auf die 5-s-Kadenz zu
  // warten) → frische Rest-km/ETA kommen schneller. Debounce gegen Server-Spam.
  DateTime? _lastFollowerBackfillPullAt;
  static const Duration _followerBackfillMinInterval = Duration(seconds: 2);
  bool _canPublishGroupRoute = false;
  // 2026-06-10 (vucko Gruppen-Reroute-Regel): true, sobald ICH der aktiven
  // (Gruppen-)Route real gefolgt bin (on-route <80m). Nur dann darf mein
  // Reroute die GRUPPEN-Route ersetzen — ein Late-Joiner, der noch nie auf
  // der Route war, loest für die Gruppe KEIN Reroute aus und sieht die
  // KOMPLETTE Route kraeftig, bis er selbst drauf fährt.
  bool _everOnActiveRoute = false;
  bool _applyingGroupRouteUpdate = false;
  int _groupRouteRevision = 0;
  Map<String, dynamic>? _activeGroupRouteData;
  final Map<String, GroupMember> _groupMembers = {};
  static const Duration _groupPositionUploadInterval = Duration(seconds: 1);
  // Peer-Sync „maximal synchron" (2026-06-21): Peer wird wie der eigene Puck
  // per Dead-Reckoning vorausgerechnet + schneller geglättet, Position kommt
  // primär per Broadcast (Fast-Path) und wird auf die Route projiziert.
  static const double _peerEaseFactor =
      0.22; // war 0.08 (schnellere Konvergenz)
  // 2026-06-23 (vucko 2-Geräte-Video „Peer hängt beim Reroute"): Während das
  // andere Gerät reroutet (3-12s), brach dessen Broadcast-Kadenz ein → der
  // Peer-Marker fror nach nur 3s/60m Vorausrechnung ein. Auf 8s/200m angehoben,
  // damit der Marker durch die typische Reroute-Lücke WEITER GLEITET (Tempo +
  // Heading kommen ja mit). Ein echter Halt sendet speed≈0 → kein Overshoot; nur
  // eine echte Bewegungs-Lücke wird länger extrapoliert, der nächste Broadcast
  // snappt per _peerEaseFactor + Route-Snap sofort zurück.
  static const double _peerExtrapMaxSeconds = 8.0;
  static const double _peerExtrapMaxMeters = 200.0;
  static const double _peerRouteSnapMeters =
      25.0; // auf Route snappen wenn ≤25m
  // 2026-06-20 (vucko Gruppen-Reroute-Sync): Backfill 15s→5s und Reconnect 3s→1s.
  // Realtime ist der Primärpfad (sub-Sekunde), aber wenn der Channel nach einem
  // Netz-Blip „silent dead" ist, ist der Backfill das EINZIGE Sicherheitsnetz,
  // damit ein Follower den Reroute des Vorausfahrenden SYNCHRON mitbekommt. 5s
  // statt 15s drittelt die Worst-Case-Latenz; ein kleiner SELECT/Follower/5s ist
  // vernachlässigbar (Member-Backfill läuft eh schon mit 5s).
  static const Duration _groupRouteBackfillInterval = Duration(seconds: 5);
  static const Duration _groupRouteReconnectDelay = Duration(seconds: 1);
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

  // 2026-07-22 (vucko Free-Cam-Kompass, Google-Maps-artig): Im FREIEN Modus
  // dreht die Karte smooth in Blickrichtung mit. Quelle geschwindigkeits-
  // abhängig: im Stand/Schritttempo der Magnetometer-Kompass (GPS-Kurs friert
  // dort ein), ab Fahrtempo das fusionierte Bewegungs-Heading (Magnetometer im
  // Fahrzeug ist durch Metall/Elektronik gestört). Läuft NUR im freien Modus —
  // der Lock-Modus behält seine Routen-Tangente.
  final CompassHeadingService _compassService = CompassHeadingService();
  // Gesten-Sperre: Auto-Rotate pausiert, solange der Nutzer die Karte gerade
  // selbst bewegt hat. Wird bei Gesten-START und (wichtig!) bei Gesten-ENDE
  // gestempelt — sonst liefe die Sperre bei langen Dreh-Gesten ab, während der
  // Finger noch auf dem Screen ist, und die Kamera drehte gegen den Nutzer.
  DateTime? _lastUserCameraGestureAt;
  static const Duration _freeRotateGestureBlock = Duration(seconds: 3);
  // Zuletzt ANGEWANDTES Auto-Rotate-Bearing (Rate-Limit: erst ab 3° Differenz
  // wird ein neuer Kamera-Call abgesetzt — Method-Channel-Schonung wie beim
  // _camMoveInFlight-Muster des Lock-Modus).
  double _lastFreeAutoRotateHeading = 0.0;
  // Eigenes In-Flight-Flag (BEWUSST nicht _camMoveInFlight teilen: sonst würde
  // ein noch laufendes Free-Rotate-animateTo beim Umschalten auf Lock den
  // ersten Locked-moveTo bis zu 400ms blockieren).
  bool _freeRotateInFlight = false;

  // Animierte Kamera-Bewegung zwischen GPS-Updates (alle Plattformen)
  AnimationController? _cameraAnimController;
  double _camToLat = 0.0;
  double _camToLng = 0.0;
  double _camToHeading = 0.0;
  double _lastCameraHeading = 0.0; // Für Bearing-Dead-Zone (< 5° ignorieren)
  // 2026-06-24 (vucko): Ankunftsfenster — ab hier Kamera-Bearing einfrieren, weil
  // die Routen-Tangente an den letzten Stützpunkten degeneriert (End-Spin/Flip).
  static const double _arrivalCameraFreezeMeters = 180.0;
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

  // Lade-Phasen-Texte + Auswahl: extrahiert nach
  // presentation/pages/cruise/route_loading_phases.dart (behavior-preserving).
  String get _routeLoadingStatusText => RouteLoadingPhases.statusText(
        isGroup: widget.groupId != null,
        isPreparingExisting: _isPreparingExistingRoute,
        isWaypoint: _isWaypointPlanning,
        isRoundTrip: _isRoundTrip,
        phaseIndex: _routeLoadingPhaseIndex,
      );

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
    _routeLoadingPhaseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted ||
          _disposed ||
          !_isLoading ||
          _activeRouteGenerationSerial != generationId) {
        return;
      }
      _safeSetState(() {
        _routeSearchProgress = math.min(_routeSearchProgress + 0.024, 0.92);
        final phaseCount = RouteLoadingPhases.phaseCount(
          isGroup: widget.groupId != null,
          isPreparingExisting: _isPreparingExistingRoute,
          isWaypoint: _isWaypointPlanning,
          isRoundTrip: _isRoundTrip,
        );
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
    // 2026-06-25 (vucko Trip-Chronologie-Fix): NUR den NÄCHSTEN erwarteten Stopp
    // abhaken (kleinster noch-nicht-passierter Index), nicht jeden geometrisch
    // nahen. Vorher konnte auf einer kurvigen Strecke ein SPÄTERER Stopp (der
    // zufällig <120 m an der Route lag) VOR einem früheren als „erreicht"
    // markiert werden → beim Speichern/Resume falsche Reihenfolge & Chronologie
    // (genau der gemeldete Bug). So bleibt die abgehakte Sequenz strikt monoton;
    // bewusstes Überspringen läuft weiterhin über _remainingWaypointsForReroute.
    var nextIdx = 0;
    while (nextIdx < _activeIntermediateWaypoints.length &&
        _passedWaypointIndices.contains(nextIdx)) {
      nextIdx++;
    }
    if (nextIdx >= _activeIntermediateWaypoints.length) return;
    final wp = _activeIntermediateWaypoints[nextIdx];
    final d = geo.Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      wp[1],
      wp[0],
    );
    if (d <= 120.0) {
      _passedWaypointIndices.add(nextIdx);
      final tripId = _activeTripId;
      if (tripId != null) {
        unawaited(
          TripService.instance.markStopReached(tripId, nextIdx + 1).catchError((
            Object e,
          ) {
            debugPrint('[CruiseMode] markStopReached fail (silent): $e');
          }),
        );
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
  // 2026-06-11 (vucko Video-Befund vom Gerät): Puck (freier Kalman) und
  // Linien-Schnitt (Fix-Match + Gates) waren ZWEI unabhaengige Systeme — am
  // echten 1Hz-GPS liefen sie sichtbar auseinander (Linie ragte hinter den
  // Puck, Puck "schwamm" neben der Linie). Industrie-Lösung (Google/Mapbox
  // Navigation): während der Fahrt wird der GERENDERTE Puck auf die Route
  // GESNAPPT und gleitet monoton ENTLANG der Geometrie; der Linien-Schnitt
  // nutzt DIESELBE Distanz → Puck und Linie können konstruktiv nicht mehr
  // auseinanderlaufen. Kurze GPS-Ausreisser werden visuell auf dem letzten
  // Lock gehalten; echte Off-route-Fahrten fallen nach kurzer Hysterese auf
  // den freien Puck zurück. Reroute/Off-route-Prüfung nutzt weiter die echte
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
  /// Routen-[index]. Gibt true zurück, wenn wirklich neu geankert wurde
  /// (Versatz > 20 m oder Lock war freigegeben) — sonst false: Mini-Jitter
  /// bleibt auf dem monotonen Glide, damit ein einzelner Seiten-Fix keinen
  /// sichtbaren Schnitt-Ruecksprung erzeugt.
  bool _reanchorRenderLockToDistance(double distanceM) {
    _ensureRouteCumDist();
    final cum = _routeCumDistM;
    if (cum == null || cum.isEmpty) return false;
    final d = distanceM.clamp(0.0, cum.last).toDouble();
    final lockDist = _renderLockDistM;
    if (lockDist >= 0 && (d - lockDist).abs() <= 20.0) return false;
    _routeRenderLock.reanchorToDistance(d);
    return true;
  }

  ({
    int stableIndex,
    double currentDist,
    double matchDist,
    double advanceMeters,
    double elapsedSeconds,
    double speedMps,
    bool plausible,
  })
  _routeProgressDecision(RouteWindowMatch match, geo.Position position) {
    _ensureRouteMetrics();
    final stableIndex = stableRouteIndexForMatch(
      match: match,
      currentIndex: _currentRouteIndex,
    ).clamp(0, _fullRouteCoordinates.length - 1).toInt();
    final currentDist =
        _routeCumDist[_currentRouteIndex
            .clamp(0, _routeCumDist.length - 1)
            .toInt()];
    final matchDist = routeDistanceForMatchMeters(
      cumulativeDistances: _routeCumDist,
      match: match,
    );
    final advanceMeters = math.max(0.0, matchDist - currentDist);
    final lastAdvanceAt = _lastRouteIndexAdvanceAt ??= position.timestamp;
    final elapsedSeconds =
        position.timestamp.difference(lastAdvanceAt).inMilliseconds / 1000.0;
    final speedMps = math.max(
      position.speed.isFinite && position.speed > 0 ? position.speed : 0.0,
      _nativeSmoother.speed.isFinite && _nativeSmoother.speed > 0
          ? _nativeSmoother.speed
          : 0.0,
    );
    final plausible = isPlausibleRouteAdvance(
      advanceMeters: advanceMeters,
      elapsedSeconds: elapsedSeconds,
      speedMps: speedMps,
      accuracyMeters: position.accuracy,
    );
    return (
      stableIndex: stableIndex,
      currentDist: currentDist,
      matchDist: matchDist,
      advanceMeters: advanceMeters,
      elapsedSeconds: elapsedSeconds,
      speedMps: speedMps,
      plausible: plausible,
    );
  }

  void _debugRejectedRouteAdvance(
    String context,
    ({
      int stableIndex,
      double currentDist,
      double matchDist,
      double advanceMeters,
      double elapsedSeconds,
      double speedMps,
      bool plausible,
    })
    decision,
    geo.Position position,
  ) {
    if (!kDebugMode) return;
    final limit = plausibleRouteAdvanceLimitMeters(
      elapsedSeconds: decision.elapsedSeconds,
      speedMps: decision.speedMps,
      accuracyMeters: position.accuracy,
    );
    debugPrint(
      '[$context] Zukunfts-Match verworfen #$_advanceCapRejects: '
      'advance=${decision.advanceMeters.toStringAsFixed(0)}m '
      'limit=${limit.toStringAsFixed(0)}m '
      'dt=${decision.elapsedSeconds.toStringAsFixed(1)}s '
      'idx=$_currentRouteIndex->${decision.stableIndex}',
    );
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
  /// gesprungen, sondern ~600ms weich übergeblendet (smoothstep auf das pro
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

  /// Render-Position für Puck UND Kamera: on-route = auf die Linie gesnappt.
  /// 2026-06-23 (vucko 2-Geräte-Video „Nav-Freeze bei GPS-Verlust"): Während eines
  /// BESTÄTIGTEN GPS-Stalls (Stream liefert >1,8s nichts, Wagen fuhr zuletzt
  /// klar, sicher route-locked) den Render-Lock entlang der Route weiterschieben
  /// (Dead-Reckoning) statt am eingefrorenen Smoother-Predict (1,5s-Clamp) zu
  /// hängen. Gibt die geglittene Route-Position zurück, sonst null. Greift NUR im
  /// Stall — der Normalpfad (GPS fließt) ruft das wegen `gap < threshold` nie auf,
  /// bleibt also unberührt; im Stall wäre der Schirm ohnehin eingefroren.
  LatLng? _gpsStallRouteGlide(DateTime renderAt) {
    if (!_routeLockedOn) return null;
    final last = _lastLocationFixAt;
    if (last == null) return null;
    final gap = renderAt.difference(last);
    if (gap < _gpsStallGlideThreshold) return null; // GPS fließt → normal
    if (gap > const Duration(seconds: 25)) {
      return null; // aufgeben, kein Run-away
    }
    if (_gpsLastFixSpeedMps < 3.0) return null; // Wagen stand → kein Glide
    if (_renderLockDistM < 0) return null;
    final lastGlide = _lastStallGlideAt ?? last;
    final dt = (renderAt.difference(lastGlide).inMilliseconds / 1000.0)
        .clamp(0.0, 0.5)
        .toDouble();
    _lastStallGlideAt = renderAt;
    if (dt > 0) {
      _routeRenderLock.glideRenderForward(
        _renderLockDistM + _gpsLastFixSpeedMps * dt,
      );
    }
    final pt = _pointAtRouteDist(_renderLockDistM);
    if (pt == null) return null;
    final glided = LatLng(pt[1], pt[0]);
    _lastRouteLockedRenderLatLng = glided;
    _lastRouteRenderLockAcceptedAt = renderAt;
    return glided;
  }

  /// 2026-06-23 (vucko GPS-Stall-Watchdog, Timer-getrieben): unabhängig vom
  /// Standort-Stream. Zeigt „GPS schwach" NUR wenn der Wagen zuletzt FUHR (nicht
  /// im Stand/Tankstelle) + hält während des Stalls den Kamera-Ticker am Leben,
  /// damit der per-Frame-Glide (oben) Puck + Linie weitergleiten lässt.
  void _checkGpsStall() {
    // 2026-06-24 (vucko Y3): Pausiert ist KEIN GPS-Problem — der Stream ruht
    // bewusst. Sonst zeigte das eigene Gerät fälschlich „GPS schwach", obwohl der
    // Fahrer nur pausiert hat.
    if (!mounted || _disposed || !_isRouteConfirmed || _isPaused) {
      if (_gpsWeak) {
        _gpsWeak = false;
        _safeSetState(() {});
      }
      return;
    }
    final last = _lastLocationFixAt;
    if (last == null) return;
    // 2026-07-22 (vucko): Resume-Gnadenfrist — direkt nach dem Aufsperren ist
    // ein Gap erwartbar und KEIN Empfangsproblem (siehe _resumeGpsGraceUntil).
    final grace = _resumeGpsGraceUntil;
    if (grace != null && DateTime.now().isBefore(grace)) {
      if (_gpsWeak) {
        _gpsWeak = false;
        _safeSetState(() {});
      }
      return;
    }
    final gap = DateTime.now().difference(last);
    final moving = _gpsLastFixSpeedMps >= 3.0;
    final warn = moving && gap >= _gpsWeakThreshold;
    if (warn != _gpsWeak) {
      _gpsWeak = warn;
      _safeSetState(() {});
    }
    if (moving &&
        _routeLockedOn &&
        gap >= _gpsStallGlideThreshold &&
        gap <= const Duration(seconds: 25)) {
      // Ticker am Leben halten: das Ziel auf die geglittene Position setzen.
      final cur = _routeLockedRenderPosition(DateTime.now());
      if (cur != null) {
        _animateCameraTo(cur.latitude, cur.longitude, _camToHeading);
      }
    }
  }

  /// 2026-06-24 (vucko Y4): „Kein Internet"-Hinweis während der Fahrt. Lauscht
  /// auf Interface-Wechsel (Flugmodus/kein Empfang). Karte ist offline gecacht —
  /// die Fahrt läuft weiter, der Hinweis ist nur Info und verdeckt nichts.
  void _startConnectivityWatch() {
    _connSub?.cancel();
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted || _disposed) return;
      final offline =
          results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      if (offline != _offline) {
        _offline = offline;
        _safeSetState(() {});
      }
    });
    // Initialer Stand (best-effort, nicht blockierend).
    unawaited(
      Connectivity()
          .checkConnectivity()
          .then((results) {
            if (!mounted || _disposed) return;
            final offline =
                results.isEmpty ||
                results.every((r) => r == ConnectivityResult.none);
            if (offline != _offline) {
              _offline = offline;
              _safeSetState(() {});
            }
          })
          .catchError((_) {}),
    );
  }

  void _stopConnectivityWatch() {
    _connSub?.cancel();
    _connSub = null;
    if (_offline) {
      _offline = false;
      _safeSetState(() {});
    }
  }

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
    // 2026-06-23 (vucko Nav-Freeze bei GPS-Verlust): im bestätigten GPS-Stall
    // entlang der Route weitergleiten statt einzufrieren (greift NUR im Stall).
    final stallGlide = _gpsStallRouteGlide(renderAt);
    if (stallGlide != null) return stallGlide;
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

  /// Read-only Render-Position für das Map-Overlay. Wichtig: Das Map-Widget
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
    // der der Puck gerendert wird. Das alte 18m-Fix-Gate entfällt in diesem
    // Pfad (der Lock garantiert on-route); es friert den Schnitt damit auch
    // bei GPS-Jitter nicht mehr ein (Geräte-Video-Befund).
    _ensureRouteCumDist();
    final lockDist = _renderLockDistM;
    if (lockDist >= 0 && _routeCumDistM != null) {
      final cum = _routeCumDistM!;
      // 2026-06-17 (vucko „Linie hinter Puck", Geräte-Video 7×): Den roten Schnitt
      // einen kleinen Vorhalt (= Trim-Gate, 2,5 m) VOR den Puck legen. Vorher
      // schnitt der Lock-Pfad EXAKT am Puck (0 Vorhalt) → zwischen zwei Trim-
      // Pushes (Gate 2,5 m) lag der Puck bis zu 2,5 m vor dem Schnitt und ein
      // rotes Stück ragte HINTER dem Puck heraus. Der Vorhalt garantiert: Schnitt
      // immer ≥ Puck, nie rote Linie dahinter. _lastTrimDistM bleibt am echten
      // Render-Meter (Gate-Kadenz unverändert).
      final cutDist = math.min(lockDist + _routeTrimPushGateM, cum.last);
      final pt = _pointAtRouteDist(cutDist);
      if (pt == null) return false;
      projHead = pt;
      var i = _renderLockSegIdx.clamp(0, coords.length - 2);
      if (cum[i] > cutDist) i = 0;
      while (i < coords.length - 2 && cum[i + 1] < cutDist) {
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
    // 2026-06-12 (vucko Geräte-Screenshots): Schnitt und Puck teilen exakt
    // dieselbe Distanz. Der fruehere 6m-Vorhalt war als Naht-Verdeckung gedacht,
    // erzeugte in echten Fahrbildern aber wieder den Eindruck, dass Route und
    // Standort nicht zusammenkleben. Die Marker-Größe verdeckt die GeoJSON-
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
    // kurz seitlich ausreissen, während der Route-Lock den sichtbaren Puck
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
      // Off-Route-Phase), wäre das 3km-Fenster an der FALSCHEN Stelle und
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
    // 2026-06-17 (vucko Geräte-Video, 90°-Kipper): Die Fahransicht ist
    // portrait-designt (Banner/Karte/Buttons). Dreht das Telefon während der
    // Navigation, kippte die UI in ein kaputtes Querformat (Banner seitlich).
    // Wie jede Navi sperren wir die Cruise-Seite auf Hochkant; beim Verlassen
    // (dispose) wird die App wieder für alle Orientierungen freigegeben.
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _loadVectorTiles();
    // 2026-06-06 (vucko P10): Zuletzt bekannten Standort laden → Karte öffnet
    // (auch beim Kaltstart) sofort dort statt bei „Deutschland-Mitte@z6".
    unawaited(_loadPersistedUserCenter());
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
      var pref = CountryPreferenceLabel.fromStorage(stored);
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

  CountryPreference get _effectiveCountryPreferenceForGeneration {
    if (!_countryFilterAppliesToCurrentRoute) return CountryPreference.any;
    return _countryPreference;
  }

  String? get _effectiveHomeCountryCodeForGeneration =>
      _effectiveCountryPreferenceForGeneration == CountryPreference.any
      ? null
      : _homeCountryCode;

  Future<void> _maybeShowRoutingOnboarding() async {
    if (!mounted || _disposed) return;
    if (_isRouteConfirmed) return;
    if (!await AppTutorialService.hasCompleted()) return;
    if (!mounted || _disposed || _isRouteConfirmed) return;
    await showRoutingOnboardingSheet(context);
  }

  Future<void> _restoreConfirmedOfflineRouteIfAvailable() async {
    if (!mounted || _disposed || _isRouteConfirmed) return;
    if (_fullRouteCoordinates.isNotEmpty) return;
    final cached = await RouteCacheService.instance.loadConfirmedRoute();
    if (cached == null || !mounted || _disposed) return;
    // 2026-06-19 (Gruppenfahrt Sync): Auf der Solo-Cruise-Seite darf keine
    // bestätigte Navigationsroute automatisch wieder erscheinen. Gruppen-
    // Recovery kommt aus der Gruppe/Revision, Solo-Recovery aus Trip-Resume.
    final age = DateTime.now().toUtc().difference(cached.savedAt.toUtc());
    final isStale = age > const Duration(minutes: 15);
    if (isStale || widget.groupId == null || cached.groupId != widget.groupId) {
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
      // bright fällt auf die volle Route zurück (nie unsichtbar), dim wird
      // beim nächsten Tick sofort neu gesetzt (dimHead == null).
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

  /// 2026-06-23 (vucko 2-Geräte-Gruppen-Video, C2): Zieht die kanonische Leader-
  /// Route SOFORT (debounced ≤1×/2s) per Backfill, wenn dieses Gerät ein NICHT-
  /// führender Gruppen-Follower ist. So bekommt ein off-route Follower frische
  /// Rest-km/ETA aus der Leader-Route schneller als über die 5-s-Periodik. Reine
  /// Leseoperation (Fetch + Adopt nur höherer Revision); _reloadGroupRouteFrom
  /// Backfill hat eigenen In-Flight-Guard. Leader/solo lösen nichts aus.
  void _maybePullFollowerGroupRouteBackfill(geo.Position position) {
    final groupId = widget.groupId;
    if (groupId == null) return;
    if (_isCurrentDeviceLeadingGroupRoute(position)) return;
    final now = DateTime.now();
    if (_lastFollowerBackfillPullAt != null &&
        now.difference(_lastFollowerBackfillPullAt!) <
            _followerBackfillMinInterval) {
      return;
    }
    _lastFollowerBackfillPullAt = now;
    final meId = Supabase.instance.client.auth.currentUser?.id;
    unawaited(_reloadGroupRouteFromBackfill(groupId, meId));
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
    final resumeState = _resumeGroupRouteStateForCurrentPosition(result);
    final accessPlan = resumeState == null
        ? await _buildGroupAccessPlanForCurrentPosition(result, routeData)
        : null;
    final activeResult = accessPlan?.activeRoute ?? result;
    final activeSessionRoute = accessPlan?.activeRoute ?? result;
    final accessLegJoinIndex = accessPlan == null
        ? null
        : _accessLegJoinIndexForPlan(accessPlan);
    final accessLegMainRoute = accessPlan?.sessionRoute;
    _applyingGroupRouteUpdate = true;
    try {
      _lastRouteResult = activeResult;
      _sessionRouteResult = activeSessionRoute;
      _activeSpeedLimits = activeResult.speedLimits;
      _activeGroupRouteData = Map<String, dynamic>.from(routeData);
      _groupRouteRevision = math.max(_groupRouteRevision, revision).toInt();
      _recentDestinationDistances = [];
      if (accessPlan == null || !accessPlan.hasAccessLeg) {
        _clearAccessLegState();
      }
      _safeSetState(() {
        _routeGeoJson = activeResult.geoJson;
        _routeDistance = activeResult.distanceMeters;
        _routeDuration = activeResult.durationSeconds;
        _originalRouteDistance = activeResult.distanceMeters;
        _originalRouteDuration = activeResult.durationSeconds;
        _fullRouteCoordinates = activeResult.coordinates;
        _remainingRouteCoordinates =
            resumeState?.remainingCoordinates ?? activeResult.coordinates;
        // 2026-06-10 (3km-Design v2): Fenster-Caches bei neuer Route leeren —
        // bright fällt auf die volle Route zurück (nie unsichtbar), dim wird
        // beim nächsten Tick sofort neu gesetzt (dimHead == null).
        _brightAheadLatLngs = const [];
        _dimRemainingLatLngs = const [];
        _lastDimHead = null;
        _maneuvers = activeResult.maneuvers;
        _currentRouteIndex = resumeState?.routeIndex ?? 0;
        _lastDrawnRouteIndex = _currentRouteIndex;
        _updateActiveManeuver();
        _distanceSinceLastRedraw = 0.0;
        _announcedManeuverIndices.clear();
        _offRouteCount = 0;
        _lastRerouteTime = DateTime.now();
        _remainingDistance =
            resumeState?.remainingDistanceMeters ?? activeResult.distanceMeters;
        _remainingDuration =
            resumeState?.remainingDurationSeconds ??
            activeResult.durationSeconds;
        _distanceToFinalTargetMeters = null;
        _isExistingRouteSession = true;
        _isRouteConfirmed = wasConfirmed;
        _applyGroupRouteMetadata(routeData);
        if (accessPlan != null && accessPlan.hasAccessLeg) {
          _isAccessLegActive = true;
          _accessLegJoinIndex = accessLegJoinIndex;
          _accessLegMainRouteResult = accessLegMainRoute;
          _sessionRouteStartIndexInActiveRoute = 0;
          _totalDistanceDriven = 0.0;
          _drivenTrackRecorder.reset();
        }
      });

      await _drawRoute(activeResult.geometry, animateCamera: !wasConfirmed);
      if (autoConfirm && !wasConfirmed) {
        await _confirmRoute(
          preserveCurrentProgress: resumeState != null || accessPlan != null,
        );
      }
      debugPrint(
        '[CruiseMode] Gruppenroute übernommen: revision=$revision source=$source '
        'access_leg_used=${activeResult.edgeMeta['access_leg_used']} '
        'join_type=${activeResult.edgeMeta['join_point_type']}',
      );
    } finally {
      _applyingGroupRouteUpdate = false;
    }
  }

  Future<RouteAccessPlan?> _buildGroupAccessPlanForCurrentPosition(
    RouteResult result,
    Map<String, dynamic> routeData,
  ) async {
    if (widget.groupId == null || result.coordinates.length < 2) return null;
    if (result.edgeMeta['access_leg_used'] != null ||
        result.edgeMeta['route_rebased_to_user'] == true) {
      return null;
    }
    final isRoundTrip = _routeDataDescribesRoundTrip(routeData, result);
    if (!groupRouteAccessLegAllowed(isRoundTrip: isRoundTrip)) {
      return null;
    }

    final position = await _resolveFreshPositionForGroupRouteAccess();
    if (position == null) return null;

    final match = findNearestInWindow(
      position: position,
      coordinates: result.coordinates,
      currentIndex: 0,
      windowSize: result.coordinates.length,
      maxJumpMeters: double.infinity,
    );
    if (match.distanceMeters.isFinite &&
        match.distanceMeters <=
            RouteAccessPlanner.nearbyPassJoinDistanceMeters) {
      return null;
    }

    final style = routeData['style']?.toString() ?? _selectedStyle;
    final avoidHighways =
        (routeData['avoid_highways'] as bool?) ??
        _effectiveNavigationAvoidHighways;

    try {
      // 2026-06-27 (vucko): KEIN „nahe am Start → Join-Index 0"-Pin mehr. Das
      // zwang die Anfahrt per Luftlinie zum Original-Start (Dornbirn), obwohl die
      // Route am User (Hohenems) vorbeiläuft. chooseJoinPoint wählt jetzt den
      // nächsten sinnvollen Punkt: Rundkurs → bester Loop-Einstieg (Ende bleibt
      // Original-Start), A→B → nächster Vorwärts-Einstieg (joinNearestForward).
      final plan = await _routeService.buildAccessRouteToExistingRoute(
        currentPosition: position,
        existingRoute: result,
        mode: style,
        avoidHighways: avoidHighways,
        preferredJoinIndex: null,
        returnToSessionOrigin: false,
        rebaseClosedLoop: isRoundTrip,
        joinNearestForward: !isRoundTrip,
      );
      _logAccessLegMeta(plan);
      if (plan.hasAccessLeg ||
          plan.joinPoint.index > 0 ||
          plan.routeStartDistanceMeters >
              RouteAccessPlanner.directJoinDistanceMeters) {
        return plan;
      }
    } catch (e) {
      debugPrint(
        '[CruiseMode] Gruppen-Access-Leg konnte nicht vorbereitet werden: $e',
      );
    }
    return null;
  }

  Future<geo.Position?> _resolveFreshPositionForGroupRouteAccess() async {
    final streamFix = _userLocation;
    if (streamFix != null && _isFreshStartFix(streamFix)) return streamFix;
    try {
      final fresh = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.best,
          timeLimit: Duration(seconds: 6),
        ),
      );
      _userLocation = fresh;
      if (_isFreshStartFix(fresh)) return fresh;
    } catch (e) {
      debugPrint('[CruiseMode] Kein frischer Gruppen-Access-Fix: $e');
    }
    return null;
  }

  bool _routeDataDescribesRoundTrip(
    Map<String, dynamic> routeData,
    RouteResult result,
  ) {
    final routeType = routeData['route_type']?.toString();
    if (routeType == 'ROUND_TRIP') return true;
    if (routeType == 'POINT_TO_POINT') return false;
    if (result.coordinates.length < 3) return false;
    final first = result.coordinates.first;
    final last = result.coordinates.last;
    return geo.Geolocator.distanceBetween(
          first[1],
          first[0],
          last[1],
          last[0],
        ) <=
        RouteAccessPlanner.closedLoopEndpointDistanceMeters;
  }

  int _accessLegJoinIndexForPlan(RouteAccessPlan plan) {
    return math
        .max(
          1,
          plan.activeRoute.coordinates.length -
              plan.sessionRoute.coordinates.length,
        )
        .clamp(1, math.max(1, plan.activeRoute.coordinates.length - 1))
        .toInt();
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

  ({
    int routeIndex,
    List<List<double>> remainingCoordinates,
    double remainingDistanceMeters,
    double? remainingDurationSeconds,
  })?
  _resumeGroupRouteStateForCurrentPosition(RouteResult result) {
    final position = _userLocation;
    final coords = result.coordinates;
    if (position == null || coords.length < 2) return null;
    final match = findNearestInWindow(
      position: position,
      coordinates: coords,
      currentIndex: 0,
      windowSize: coords.length,
      maxJumpMeters: double.infinity,
    );
    if (!match.distanceMeters.isFinite || match.distanceMeters > 160.0) {
      return null;
    }
    final routeIndex = stableRouteIndexForMatch(
      match: match,
      currentIndex: 0,
    ).clamp(0, coords.length - 1).toInt();
    final remaining = coords.sublist(routeIndex);
    if (remaining.isNotEmpty) {
      final first = remaining.first;
      final headDistance = geo.Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        first[1],
        first[0],
      );
      if (headDistance <= _headSnapMaxMeters) {
        remaining[0] = [position.longitude, position.latitude];
      }
    }
    final remainingDistance = _calculatePolylineDistanceMeters(remaining);
    final totalDistance =
        result.distanceMeters ?? _calculatePolylineDistanceMeters(coords);
    final remainingDuration =
        result.durationSeconds != null && totalDistance > 0
        ? result.durationSeconds! * (remainingDistance / totalDistance)
        : null;
    return (
      routeIndex: routeIndex,
      remainingCoordinates: remaining,
      remainingDistanceMeters: remainingDistance,
      remainingDurationSeconds: remainingDuration,
    );
  }

  geo.Position _positionFromLatLngForRouteMatch({
    required double latitude,
    required double longitude,
    DateTime? timestamp,
  }) {
    return geo.Position(
      longitude: longitude,
      latitude: latitude,
      timestamp: timestamp ?? DateTime.now(),
      accuracy: 20,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
      floor: null,
      isMocked: false,
    );
  }

  double? _routeProgressMetersForPosition(
    geo.Position position, {
    double maxDistanceMeters = 180.0,
  }) {
    if (_fullRouteCoordinates.length < 2) return null;
    _ensureRouteMetrics();
    final match = findNearestInWindow(
      position: position,
      coordinates: _fullRouteCoordinates,
      currentIndex: 0,
      windowSize: _fullRouteCoordinates.length,
      maxJumpMeters: double.infinity,
    );
    if (!match.distanceMeters.isFinite ||
        match.distanceMeters > maxDistanceMeters) {
      return null;
    }
    return routeDistanceForMatchMeters(
      cumulativeDistances: _routeCumDist,
      match: match,
    );
  }

  double? _currentRouteProgressMetersFallback() {
    if (_fullRouteCoordinates.length < 2) return null;
    _ensureRouteMetrics();
    if (_routeCumDist.isEmpty) return null;
    if (_renderLockDistM.isFinite &&
        _renderLockDistM >= 0 &&
        _renderLockDistM <= _routeTotalLenM + 100.0) {
      return _renderLockDistM;
    }
    final idx = _currentRouteIndex.clamp(0, _routeCumDist.length - 1).toInt();
    return _routeCumDist[idx];
  }

  bool _isCurrentDeviceLeadingGroupRoute(geo.Position position) {
    if (widget.groupId == null) return true;
    final myProgress =
        _routeProgressMetersForPosition(position, maxDistanceMeters: 220.0) ??
        _currentRouteProgressMetersFallback();
    if (myProgress == null) return false;
    final now = DateTime.now();
    final peerProgress = <double>[];
    for (final member in _groupMembers.values) {
      if (!member.hasFreshLocation(
        now: now,
        maxAge: _groupMemberFreshLocationAge,
      )) {
        continue;
      }
      final peerPosition = _positionFromLatLngForRouteMatch(
        latitude: member.currentLat!,
        longitude: member.currentLng!,
        timestamp: member.lastUpdatedAt,
      );
      final progress = _routeProgressMetersForPosition(
        peerPosition,
        maxDistanceMeters: 220.0,
      );
      if (progress != null) peerProgress.add(progress);
    }
    final isLeader = groupReroutePublisherIsLeader(
      myProgressMeters: myProgress,
      peerProgressMeters: peerProgress,
    );
    if (!isLeader && kDebugMode) {
      debugPrint(
        '[CruiseMode] Gruppen-Reroute nicht publiziert: '
        'nicht vorderstes Fahrzeug '
        'my=${myProgress.toStringAsFixed(0)}m peers=$peerProgress',
      );
    }
    return isLeader;
  }

  /// 2026-06-21 (vucko Feldkirch-Gruppen-Reroute-Hang): Soll dieser Follower
  /// seine lokale Off-Route-Reroute aussetzen und der geteilten Leader-Route
  /// folgen? Reine Entscheidung in [groupFollowerShouldDeferLocalReroute];
  /// hier nur die Live-Inputs gesammelt. Sicher per Konstruktion: solo
  /// (groupId null), Leader und Allein-in-Gruppe geben false → unverändert.
  bool _groupFollowerShouldDeferReroute(geo.Position position) {
    if (widget.groupId == null) return false;
    final now = DateTime.now();
    final hasFreshPeer = _groupMembers.values.any(
      (m) => m.hasFreshLocation(now: now, maxAge: _groupMemberFreshLocationAge),
    );
    // 2026-06-22 (vucko Gruppen-Video „Follower strandet"): Wie lange/weit ist
    // der Follower schon off-route? Bei anhaltender/weiter Divergenz hört der
    // Defer auf, damit der Follower nicht ewig auf eine Leader-Route wartet, die
    // nie kommt (Leader fährt korrekt weiter), sondern selbst zurück-rerouted.
    final offRouteFor = _offRouteSince == null
        ? Duration.zero
        : now.difference(_offRouteSince!);
    return groupFollowerShouldDeferLocalReroute(
      inGroup: true,
      hasSharedGroupRoute: _groupRouteRevision > 0,
      hasFreshLeaderPeer: hasFreshPeer,
      isLeadingGroupRoute: _isCurrentDeviceLeadingGroupRoute(position),
      offRouteFor: offRouteFor,
      offRouteGapMeters: _offRouteGapMeters,
    );
  }

  /// 2026-06-23 (vucko 2-Geräte-Gruppen-Video, C1): Ist dieses Gerät ein NICHT-
  /// führender Gruppen-Follower mit frischem Leader voraus und geteilter Route?
  /// Dann zeigt das „Neuberechnung"-Banner ruhig „Folge der Gruppe" — der Fahrer
  /// folgt nur dem Leader, dessen Republish gleich adoptiert wird (kein Flackern).
  /// Wird NUR im Build aufgerufen, wenn das Reroute-Banner ohnehin aktiv ist
  /// (begrenzte Kosten). Fällt der Leader-Peer weg (>12s stale), greift wieder
  /// das normale „Neuberechnung", weil der Follower dann selbst zurück muss.
  bool _groupFollowerWaitingForLeaderRoute() {
    if (widget.groupId == null || _groupRouteRevision <= 0) return false;
    final pos = _userLocation;
    if (pos == null) return false;
    final now = DateTime.now();
    final hasFreshPeer = _groupMembers.values.any(
      (m) => m.hasFreshLocation(now: now, maxAge: _groupMemberFreshLocationAge),
    );
    if (!hasFreshPeer) return false;
    return !_isCurrentDeviceLeadingGroupRoute(pos);
  }

  Future<bool> _publishGroupRouteIfAllowed(
    RouteResult result, {
    required bool wasLeadingBeforeCommit,
  }) async {
    final groupId = widget.groupId;
    if (groupId == null ||
        !wasLeadingBeforeCommit ||
        !_canPublishGroupRoute ||
        // 2026-06-10 (vucko Gruppen-Reroute-Regel): Nur wer der Route real
        // gefolgt ist, darf sie für die GRUPPE ersetzen (Late-Join-Schutz).
        !_everOnActiveRoute ||
        _applyingGroupRouteUpdate ||
        _groupRouteRevision <= 0) {
      return false;
    }

    final expectedRevision = _groupRouteRevision;
    final publisherProgressMeters = _currentRouteProgressMetersFallback();
    if (publisherProgressMeters == null || !publisherProgressMeters.isFinite) {
      debugPrint(
        '[CruiseMode] Gruppenroute nicht geschrieben: kein Fortschritt für Publish-Guard',
      );
      return false;
    }
    final meId = Supabase.instance.client.auth.currentUser?.id;
    final routeData = GroupRouteDataBuilder.replaceRoutePayload(
      route: result,
      previousRouteData: _activeGroupRouteData,
      updateReason: 'navigation_reroute',
      publishMeta: {
        'client_guard': 'leader_progress_v1',
        'is_leading_vehicle': wasLeadingBeforeCommit,
        'publisher_progress_meters': publisherProgressMeters,
        'publisher_user_id': meId,
        'published_at': DateTime.now().toUtc().toIso8601String(),
      },
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
        unawaited(_reloadGroupRouteFromBackfill(groupId, meId));
        return false;
      }
      _groupRouteRevision = update.routeRevision;
      _activeGroupRouteData = routeData;
      debugPrint(
        '[CruiseMode] Gruppenroute geschrieben: revision=${update.routeRevision}',
      );
      return true;
    } catch (e) {
      debugPrint(
        '[CruiseMode] Gruppenroute konnte nicht geschrieben werden: $e',
      );
      unawaited(_reloadGroupRouteFromBackfill(groupId, meId));
      return false;
    }
  }

  void _startGroupMembersRealtime(String groupId, String? meId) {
    _groupMembersCh?.unsubscribe();
    _myUserId = meId;
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
      onBroadcastPosition: (payload) => _onPeerBroadcast(payload, meId),
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
    // 20Hz: Peer wird wie der eigene Puck per Dead-Reckoning auf JETZT
    // vorausgerechnet (Anker + Tempo×Zeit, gedeckelt) und schnell dorthin
    // geglättet — so steht er dort, wo er aktuell real ist, statt ~2s/100m
    // hinter dem letzten Upload.
    _peerAnimTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || _disposed || _peerTargetPos.isEmpty) return;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      var moved = false;
      _peerTargetPos.forEach((uid, anchor) {
        final shown = _peerShownPos[uid];
        if (shown == null) {
          _peerShownPos[uid] = [anchor[0], anchor[1]];
          moved = true;
          return;
        }
        var tgtLng = anchor[0];
        var tgtLat = anchor[1];
        final vel = _peerVelDegPerSec[uid];
        final tFix = _peerFixTimeMs[uid];
        if (vel != null && tFix != null) {
          final dt = ((nowMs - tFix) / 1000.0).clamp(
            0.0,
            _peerExtrapMaxSeconds,
          );
          if (dt > 0) {
            final exLng = anchor[0] + vel[0] * dt;
            final exLat = anchor[1] + vel[1] * dt;
            final exMeters = geo.Geolocator.distanceBetween(
              anchor[1],
              anchor[0],
              exLat,
              exLng,
            );
            if (exMeters <= _peerExtrapMaxMeters || exMeters < 0.01) {
              tgtLng = exLng;
              tgtLat = exLat;
            } else {
              final s = _peerExtrapMaxMeters / exMeters;
              tgtLng = anchor[0] + (exLng - anchor[0]) * s;
              tgtLat = anchor[1] + (exLat - anchor[1]) * s;
            }
          }
        }
        final dLng = tgtLng - shown[0];
        final dLat = tgtLat - shown[1];
        // ~0.05m-Schwelle (grob in Grad) -> konvergiert: nichts tun.
        if (dLng.abs() < 0.0000005 && dLat.abs() < 0.0000005) return;
        shown[0] += dLng * _peerEaseFactor;
        shown[1] += dLat * _peerEaseFactor;
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
      _setPeerFix(
        incoming.userId,
        lng: lng,
        lat: lat,
        tMs:
            merged.lastUpdatedAt?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch,
      );
    }
    return true;
  }

  /// Nimmt einen neuen Peer-Fix auf (aus DB-Realtime ODER Broadcast).
  /// Reihenfolge-Guard (kein Rückwärts-Sprung dedupt Broadcast↔DB), leitet bei
  /// Bedarf die Geschwindigkeit aus zwei aufeinanderfolgenden Fixes ab und
  /// setzt Anker + Zeit + Velocity. Der _peerAnimTimer rechnet daraus pro Frame
  /// die aktuelle Position voraus (Dead-Reckoning wie der eigene Puck).
  void _setPeerFix(
    String uid, {
    required double lng,
    required double lat,
    required int tMs,
    List<double>? velDegPerSec,
  }) {
    final prevT = _peerFixTimeMs[uid];
    if (prevT != null && tMs <= prevT) return; // veraltet/Duplikat
    if (velDegPerSec == null) {
      final prevAnchor = _peerTargetPos[uid];
      if (prevAnchor != null && prevT != null) {
        final dt = (tMs - prevT) / 1000.0;
        if (dt > 0.2 && dt < 6.0) {
          velDegPerSec = [
            (lng - prevAnchor[0]) / dt,
            (lat - prevAnchor[1]) / dt,
          ];
        }
      }
    }
    _peerTargetPos[uid] = [lng, lat];
    _peerFixTimeMs[uid] = tMs;
    if (velDegPerSec != null) _peerVelDegPerSec[uid] = velDegPerSec;
    // Erste Position: direkt setzen (kein Anflug quer über die Karte).
    _peerShownPos.putIfAbsent(uid, () => [lng, lat]);
  }

  /// m/s + Heading → [vlng, vlat] in Grad/Sekunde (für sofortige Extrapolation
  /// aus EINEM Broadcast, ohne auf zwei Fixes warten zu müssen).
  List<double> _peerVelFromSpeedHeading(
    double speedMps,
    double headingDeg,
    double lat,
  ) {
    if (!speedMps.isFinite ||
        speedMps <= 0.3 ||
        !headingDeg.isFinite ||
        headingDeg < 0) {
      return const [0.0, 0.0];
    }
    final rad = headingDeg * math.pi / 180.0;
    const metersPerDegLat = 111320.0;
    final metersPerDegLng = 111320.0 * math.cos(lat * math.pi / 180.0);
    final north = speedMps * math.cos(rad);
    final east = speedMps * math.sin(rad);
    return [
      metersPerDegLng.abs() < 1e-6 ? 0.0 : east / metersPerDegLng,
      north / metersPerDegLat,
    ];
  }

  /// Verarbeitet einen Live-Positions-Broadcast eines Peers (Fast-Path).
  void _onPeerBroadcast(Map<String, dynamic> payload, String? meId) {
    if (!mounted || _disposed) return;
    final inner = payload['payload'];
    final m = inner is Map
        ? Map<String, dynamic>.from(inner)
        : Map<String, dynamic>.from(payload);
    final uid = m['user_id'] as String?;
    if (uid == null || uid == meId) return;
    final lat = (m['lat'] as num?)?.toDouble();
    final lng = (m['lng'] as num?)?.toDouble();
    final tMs = (m['t'] as num?)?.toInt();
    if (lat == null || lng == null || tMs == null) return;
    if (!lat.isFinite || !lng.isFinite) return;
    final member = _groupMembers[uid];
    if (member == null) return; // erst rendern, wenn die DB-Row da ist
    final speed = (m['speed'] as num?)?.toDouble();
    final heading = (m['heading'] as num?)?.toDouble();
    final vel = (speed != null && heading != null)
        ? _peerVelFromSpeedHeading(speed, heading, lat)
        : null;
    _lastGroupRealtimeEventAt = DateTime.now();
    _groupMembers[uid] = member.copyWith(
      currentLat: lat,
      currentLng: lng,
      lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(tMs, isUtc: true),
    );
    // 2026-06-24 (vucko Y3): transienten Status des Peers merken (pausiert /
    // GPS-schwach) für die Marker-Kennzeichnung.
    _peerStatus[uid] = (
      paused: m['paused'] == true,
      gpsWeak: m['gps_weak'] == true,
    );
    _setPeerFix(uid, lng: lng, lat: lat, tMs: tMs, velDegPerSec: vel);
    _safeSetState(() {});
  }

  /// Aktuelle Render-Position eines Peers: geglättet+extrapoliert (_peerShownPos)
  /// und — wenn nah genug — auf die gemeinsame Route projiziert, damit Peer und
  /// eigener Puck auf DERSELBEN Linie liegen.
  LatLng _peerRenderPoint(String uid, GroupMember m) {
    final shown = _peerShownPos[uid];
    final base = shown != null
        ? LatLng(shown[1], shown[0])
        : LatLng(m.currentLat!, m.currentLng!);
    return _projectPeerOntoRoute(base) ?? base;
  }

  /// Projiziert eine Peer-Position auf die aktive Routen-Geometrie, WENN sie
  /// ≤_peerRouteSnapMeters dran ist (sonst null = Rohpunkt). Konservativ: ein
  /// off-route-Peer wird NIE auf die Linie teleportiert.
  LatLng? _projectPeerOntoRoute(LatLng p) {
    if (widget.groupId == null) return null;
    final pts = _routeLatLngs;
    if (pts.length < 2) return null;
    final cosLat = math.cos(p.latitude * math.pi / 180.0);
    final px = p.longitude * cosLat;
    final py = p.latitude;
    var best2 = double.infinity;
    var bestLng = 0.0;
    var bestLat = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      final ax = a.longitude * cosLat;
      final ay = a.latitude;
      final bx = b.longitude * cosLat;
      final by = b.latitude;
      final dx = bx - ax;
      final dy = by - ay;
      final segLen2 = dx * dx + dy * dy;
      var t = segLen2 <= 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / segLen2;
      if (t < 0) t = 0;
      if (t > 1) t = 1;
      final qx = ax + dx * t;
      final qy = ay + dy * t;
      final ddx = px - qx;
      final ddy = py - qy;
      final d2 = ddx * ddx + ddy * ddy;
      if (d2 < best2) {
        best2 = d2;
        bestLng = cosLat.abs() < 1e-9 ? p.longitude : qx / cosLat;
        bestLat = qy;
      }
    }
    if (!best2.isFinite) return null;
    final meters = geo.Geolocator.distanceBetween(
      p.latitude,
      p.longitude,
      bestLat,
      bestLng,
    );
    return meters <= _peerRouteSnapMeters ? LatLng(bestLat, bestLng) : null;
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
    final status = _peerStatus[m.userId];
    final isPaused = isFresh && status?.paused == true;
    final isGpsWeak = isFresh && status?.gpsWeak == true;
    final liveColor = isDriver
        ? AppAccentColors.accent
        : const Color(0xFF4FC3F7);
    final color = isFresh ? liveColor : const Color(0xFF8A8F98);

    // 2026-06-24 (vucko Y3): Status-Badge — klar erkennbar WARUM ein Mitfahrer
    // steht/anders ist. Priorität: keine Verbindung (Standort alt) > pausiert >
    // GPS-schwach. Pausiert bleibt VOLL sichtbar (Heartbeat hält frisch), nur
    // echtes Veralten dimmt + zeigt das WLAN-aus-Symbol.
    IconData? badgeIcon;
    Color badgeColor = const Color(0xFF8A8F98);
    if (!isFresh) {
      badgeIcon = Icons.wifi_off_rounded;
      badgeColor = const Color(0xFFFF6B61);
    } else if (isPaused) {
      badgeIcon = Icons.pause_rounded;
      badgeColor = const Color(0xFFFFB02E);
    } else if (isGpsWeak) {
      badgeIcon = Icons.gps_off_rounded;
      badgeColor = const Color(0xFFFFB02E);
    }

    final avatar = Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        shape: BoxShape.circle,
        // Pausiert → ruhiger orangener Ring statt des Live-Farbrings.
        border: Border.all(
          color: isPaused ? const Color(0xFFFFB02E) : color,
          width: isFresh ? 3 : 2,
        ),
        boxShadow: [
          if (isFresh && !isPaused)
            BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8),
        ],
      ),
      child: CircleAvatar(
        radius: 18,
        backgroundColor: color,
        foregroundImage: UserAvatar.avatarImageProvider(
          context,
          m.avatarUrl,
          radius: 18,
        ),
        child: Icon(
          isDriver ? Icons.directions_car : Icons.person,
          color: Colors.white,
          size: 16,
        ),
      ),
    );

    return Opacity(
      opacity: isFresh ? 1.0 : 0.5,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          avatar,
          if (badgeIcon != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0E14),
                  shape: BoxShape.circle,
                  border: Border.all(color: badgeColor, width: 1.6),
                ),
                child: Icon(badgeIcon, color: badgeColor, size: 11),
              ),
            ),
        ],
      ),
    );
  }

  bool _hasGroupMemberLocation(GroupMember m) => m.hasLocation;

  // 2026-06-24 (vucko Peer-Status, Y3): transienter Zustand der Mitfahrer
  // (pausiert / GPS-schwach), aus den grp_pos-Broadcasts. „Kein Internet" wird
  // aus der Frische des Markers abgeleitet (keine eigene Flag nötig).
  final Map<String, ({bool paused, bool gpsWeak})> _peerStatus = {};

  // Eigener Pausen-Zustand: beim Pausieren broadcasten wir weiter einen
  // „paused"-Heartbeat mit eingefrorener Position, damit die anderen uns als
  // PAUSIERT (nicht als offline) sehen — der Standort bleibt sichtbar stehen.
  bool _isPaused = false;
  Timer? _pauseHeartbeat;
  static const Duration _pauseHeartbeatInterval = Duration(seconds: 3);

  bool _positionUploadInFlight = false;

  Future<void> _uploadMyPosition() async {
    if (widget.groupId == null) return;
    final pos = _userPosition;
    if (pos == null) return;
    // Fast-Path: Broadcast (kein DB-Roundtrip) — sub-Sekunde, auch wenn der
    // DB-Write gerade hängt. Tempo+Heading gehen mit, damit Peers extrapolieren.
    _broadcastMyPosition(pos);
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

  void _broadcastMyPosition(LatLng pos) {
    final ch = _groupMembersCh;
    final uid = _myUserId;
    if (ch == null || uid == null) return;
    // Tempo/Heading vom Smoother bzw. GPS-Heading mitschicken, damit Peers
    // sofort extrapolieren können (sonst leiten sie es aus 2 Fixes ab).
    final speed = _nativeSmoother.speed;
    unawaited(
      CruiseGroupService.broadcastPosition(
        ch,
        userId: uid,
        lat: pos.latitude,
        lng: pos.longitude,
        tMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        speed: speed.isFinite && speed > 0 ? speed : null,
        heading: _userHeading.isFinite ? _userHeading : null,
        // 2026-06-24 (vucko Y3): eigenen Status mitschicken, damit die Mitfahrer
        // sehen WARUM man steht (pausiert vs. GPS-schwach).
        paused: _isPaused,
        gpsWeak: _gpsWeak,
      ),
    );
  }

  /// 2026-06-24 (vucko Y3): Pausen-Zustand setzen + sofort broadcasten. Beim
  /// Pausieren läuft ein leichter Heartbeat weiter (eingefrorene Position +
  /// paused=true), damit die anderen den Marker als PAUSIERT sehen — und nicht
  /// als offline (sonst sähe es aus wie „kein Internet").
  void _setGroupPaused(bool paused) {
    if (widget.groupId == null || _isPaused == paused) {
      _isPaused = paused;
      return;
    }
    _isPaused = paused;
    final pos = _userPosition;
    if (pos != null) _broadcastMyPosition(pos);
    _pauseHeartbeat?.cancel();
    if (paused) {
      _pauseHeartbeat = Timer.periodic(_pauseHeartbeatInterval, (_) {
        if (!mounted || _disposed || !_isPaused) return;
        final p = _userPosition;
        if (p != null) _broadcastMyPosition(p);
      });
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
              'Diese Tour hat keine gültigen Wegpunkte mehr und wird geschlossen.',
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
        message: 'Trip wird fortgesetzt, ${waypoints.length} Stopps geladen',
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
    // 2026-06-17 (vucko 90°-Kipper): Orientierungs-Sperre der Fahransicht wieder
    // aufheben — der Rest der App darf drehen.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 2026-06-15 (vucko M5): Map SOFORT inaktiv — ein in-flight Render-/Kamera-
    // Tick während des Page-Teardowns darf keinen Native-Call mehr absetzen.
    _mlController?.active = false;
    WidgetsBinding.instance.removeObserver(this);
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
    _rerouteWatchdog?.cancel();
    _gpsStallWatchdog?.cancel();
    _stopCompass();
    _cameraAnimController?.removeListener(_onCameraAnimationTick);
    _cameraAnimController?.dispose();
    CruiseModePage.isFullscreen.value = false;
    CruiseModePage.pendingRoute.removeListener(_onPendingRoute);
    CruiseModePage.pendingTripResume.removeListener(_onPendingTripResume);
    _stopSimulation(restartLiveTracking: false);
    // 2026-07-24 (vucko Wakelock): Sicherheitsnetz — dispose() geht NICHT
    // durch _stopNavigationTracking() (reißt Streams direkt ab), z.B. beim
    // Verlassen per OS-Geste mitten in der Navigation. Doppeltes Disable
    // ist ein harmloser No-Op.
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    unawaited(NavigationPipService.instance.disarm());
    unawaited(RoadIncidentService.instance.clearLivePosition());
    _incidentRefetchDebounce?.cancel();
    _incidentChannel?.unsubscribe();
    _positionSubscription?.cancel();
    _socketPositionSubscription?.cancel();
    _positionUploadTimer?.cancel();
    _peerAnimTimer?.cancel();
    _groupRouteBackfillTimer?.cancel();
    _groupRouteReconnectTimer?.cancel();
    _groupMembersBackfillTimer?.cancel();
    _groupMembersReconnectTimer?.cancel();
    _groupMembersFreshnessTimer?.cancel();
    _pauseHeartbeat?.cancel();
    _connSub?.cancel();
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

  // 2026-07-03 (vucko Linien-Versatz-Milderung, Geräte-Video 07-03): Die
  // Routenlinie ist geo-exakt; der sichtbare Versatz zur Straße entsteht, weil
  // die Basiskarten-PMTiles (dach.pmtiles max_zoom 14) beim Fahr-Zoom 16.5 um
  // 2,5 Stufen ÜBERZOOMT werden — dabei ist die Straßengeometrie beim Tile-Build
  // auf das z14-Raster generalisiert (Sehnen statt Kurven), während die rote
  // Linie voll aufgelöst ist → in Kurven liegt die Linie neben der groben
  // Straße. Fahr-Zoom von 16.5 auf 15.0 senken reduziert den Überzoom auf 1,0
  // Stufe → der sichtbare Versatz schrumpft ~2,8×. DAUERHAFTER Fix = den
  // roads-Layer der PMTiles bis z15/16 ohne Maxzoom-Simplify neu bauen
  // (Tile-Pipeline auf dem Tile-Server) — dann kann der Zoom wieder höher.
  static const double _kNavFollowZoom = 15.0;

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
    // 2026-06-13 (vucko Free-Cam-/Off-Route-Ruckeln, Geräte-Videos): Der
    // Puck-Glide + Linien-Schnitt laufen jetzt in JEDEM Kameramodus pro
    // Frame. Vorher stoppte der Ticker beim Verlassen der Zentrierung
    // komplett → die Render-Position wurde nur noch pro GPS-Fix (1Hz)
    // fortgeschrieben und der Puck teleportierte sekuendlich (~19m bei
    // 70 km/h). Kamera-Bewegung bleibt natürlich an _isCameraLocked
    // gebunden; bei stehender Kamera stossen wir die Marker-Projektion
    // selbst an (sonst projiziert nur onCameraMove).
    if (!kIsWeb) {
      // 2026-06-11 (vucko Route-Lock): Kamera folgt derselben route-gesnappten
      // Render-Position wie der Puck (eine Quelle) — vorher zog die freie
      // Kalman-Prediction die Kamera seitlich neben die Linie.
      // 2026-06-25 (vucko Stage 2c, Marker-Swim): Beim FREIEN Pannen im
      // Stillstand KEINEN 150ms-Dead-Reckoning-Vorhalt anwenden. Sonst schiebt
      // der Smoother die Render-Position pro Frame minimal vor → der Puck
      // „kriecht" über den festgehaltenen Boden (zusätzlich zum unvermeidbaren
      // 1-Frame-Overlay-Lag). Bei Bewegung ODER gesperrter Kamera bleibt der
      // volle Vorhalt (flüssiges Gleiten / Kamera-Sync) unverändert.
      final stationaryFreePan =
          !_isCameraLocked &&
          _nativeSmoother.speed < 0.6 &&
          (_userLocation?.speed ?? 0) < 0.8;
      final lockPos = _routeLockedRenderPosition(
        stationaryFreePan
            ? DateTime.now()
            : DateTime.now().add(_nativeRenderPredictionLead),
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
        // 2026-07-22 (vucko Free-Cam-Kompass): Karte smooth in Blick-/Fahrt-
        // richtung nachdrehen (Google-Maps-artig) — mit Gesten-Sperre,
        // 3°-Rate-Limit und eigenem In-Flight-Schutz.
        _applyFreeModeAutoRotate();
        // 2026-06-13 (vucko Free-Cam-Ruckeln, Geräte-Video): Idle-Stop mit
        // HYSTERESE. Vorher stoppte der Ticker bei einem EINZELNEN Frame
        // <0,3 m/s — ein kurzer Smoother-Speed-Dip (nach Reroute, GPS-Glitch)
        // hielt den Puck dann bis zum nächsten 1Hz-Fix an (Mikro-Ruckeln).
        // Jetzt: erst nach ~0,5s anhaltendem Quasi-Stillstand (<0,15 m/s)
        // pausieren; jeder Speed-Pickup setzt den Zähler zurück.
        // 2026-06-15 (vucko M4 „Puck IMMER fluessig"): Auch das ROHE GPS-Tempo
        // prüfen. Bei einem fehlerhaften Reroute kann die Smoother-Geschwindigkeit
        // kurz auf ~0 einfrieren, OBWOHL der Wagen fährt — dann darf der Ticker
        // NICHT pausieren, sonst klebt der Puck bis zum nächsten 1Hz-Fix.
        // 2026-07-22 (vucko Free-Cam-Kompass): Zusätzlich NICHT pausieren,
        // solange die Auto-Rotation noch >=3° nachzudrehen hat — sonst fröre
        // die Drehung im Stand mitten in der Bewegung ein (der Kompass-Hook
        // _onCompassHeadingUpdate weckt den Ticker sonst zwar wieder, aber
        // Stop/Start pro Frame wäre reines Geflacker).
        final movingByGps = (_userLocation?.speed ?? 0) > 0.6;
        if (_nativeSmoother.speed < 0.15 &&
            !movingByGps &&
            !_freeModeAutoRotatePending()) {
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
        // 2026-06-21 (vucko Geräte-Video „Route immer leicht geneigt"): Heading-
        // Ziel PRIMÄR aus der ROUTEN-TANGENTE (Straße zeigt senkrecht nach oben),
        // nicht aus dem verrauschten GPS-Kurs. Auf dem Gerät kippte der GPS-Course
        // die Karte um den Rauschwinkel; on-route ist die Tangente die Wahrheit.
        // Fallback auf das geglättete GPS-Heading nur, wenn keine Tangente da ist
        // (off-route / sehr kurze Restroute). Die Dead-Zone + der Tick-Lerp
        // glätten die Drehung weiterhin (kein Stand-Zappeln, kein Burst-Ruck).
        // 2026-06-24 (vucko Geräte-Video „Kamera dreht/kippt am Ende"): In den
        // letzten ~180 m vor der Ankunft wird die Routen-Tangente an den letzten
        // Stützpunkten degeneriert → Bearing + Zoom oszillierten (Spin/180°-Flip
        // beim Ankommen). Im Ankunftsfenster das Bearing auf den letzten guten
        // Heading-up-Wert EINFRIEREN (Position folgt weiter, nur keine Drehung
        // mehr aus dem kaputten Endsegment).
        final remainingForCam = _remainingDistance;
        final inArrivalWindow =
            remainingForCam != null &&
            remainingForCam.isFinite &&
            remainingForCam <= _arrivalCameraFreezeMeters;
        if (!inArrivalWindow) {
          double? targetHeading = _routeTangentCameraBearing(lockPos);
          // 2026-07-24 (vucko Autobahn-Dreh-Bug, zweite Verteidigungslinie):
          // Bei hohem Tempo ist der GPS-Kurs sehr verlässlich — weicht die
          // Routen-Tangente plötzlich stark davon ab, ist fast sicher der
          // Render-Lock kurz auf ein falsches Segment gerutscht (Parallel-
          // fahrbahn/Rampe am Autobahnkreuz), NICHT die Straße. Dann die
          // Tangente verwerfen → der Fallback unten übernimmt den echten
          // GPS-Kurs (= tatsächliche Fahrtrichtung), bis Tangente und Kurs
          // wieder übereinstimmen. 60° lässt jede echte Kurve durch (engste
          // Autobahnrampe bei >54 km/h bleibt mit 30m-Look-ahead unter ~40°).
          if (targetHeading != null &&
              _nativeSmoother.hasValidHeading &&
              _nativeSmoother.speed > 15.0) {
            final tangentVsCourse = GeoBearing.angleDiff(
              targetHeading,
              _nativeSmoother.heading,
            ).abs();
            if (tangentVsCourse > 60.0) {
              targetHeading = null;
            }
          }
          if (targetHeading == null && _nativeSmoother.hasValidHeading) {
            targetHeading = _nativeSmoother
                .predict(DateTime.now().add(_nativeRenderPredictionLead))
                .heading;
          }
          if (targetHeading != null) {
            final delta = GeoBearing.angleDiff(_camToHeading, targetHeading).abs();
            // Mikro-Jitter (<0,6°) ignorieren — sonst zappelt die Karte im Stand.
            if (delta >= 0.6) {
              _camToHeading = targetHeading;
              _lastCameraHeading = targetHeading;
            }
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
    _camCurHeading = GeoBearing.lerpAngleDeg(_camCurHeading, _camToHeading, f);
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
        GeoBearing.angleDiff(prevHeading, _camCurHeading).abs() < 0.05) {
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
    final offLat = _camCurLat + GeoBearing.forwardOffsetLat(_camCurHeading);
    final offLng = _camCurLng + GeoBearing.forwardOffsetLng(_camCurHeading);
    _camMoveInFlight = true;
    ctrl
        .moveTo(
          lat: offLat,
          lng: offLng,
          zoom: _kNavFollowZoom,
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
    final headingDelta = GeoBearing.angleDiff(_lastCameraHeading, heading).abs();
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
                'Bis zu 5 Stopps, mit Pause/Resume, perfekt für Mehrtages-Touren',
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
                  text: '$title: ',
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
    // 2026-06-20 (vucko Gruppen-Exit-Flow): System-Back (iOS-Swipe / Android-
    // Back) während einer AKTIVEN Gruppen-Fahrt darf NICHT direkt rauspoppen —
    // sonst umgeht es Bestätigung + Post-Route-Screen und der User landet wieder
    // auf der Routensuche. Wir fangen ihn ab und leiten in denselben Flow wie der
    // Zurück-Button (_handleActiveRouteBack → Bestätigen → Abschluss → Lobby).
    // 2026-07-27 (vucko „beim Zurück soll ein Pop-up kommen"): Dasselbe gilt
    // jetzt für laufende SOLO-Fahrten. Vorher poppte die Wischgeste die Seite
    // sofort weg, ohne Rückfrage — ein Fix nur am Zurück-Button hätte den
    // häufigsten Weg (iOS-Kantenwisch, Android-Zurück) offen gelassen.
    final blockSystemBack =
        (widget.groupId != null && _isRouteConfirmed) || _soloRideIsRunning;
    return PopScope(
      canPop: !blockSystemBack,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !blockSystemBack) return;
        _handleActiveRouteBack();
      },
      // 2026-07-25 (vucko „Mini-Bildschirm neben anderen Apps"): Im
      // Android-PiP-Fenster (wenige Zentimeter gross) waere die volle
      // Karte samt Panels/Buttons unlesbar — dort zeigen wir stattdessen
      // eine reduzierte Manoever-Ansicht (Pfeil + Distanz + ETA), wie es
      // Google Maps macht. Ausserhalb von PiP bleibt alles unveraendert;
      // auf iOS/Web liefert PiPSwitcher immer childWhenDisabled.
      child: _pipAware(
        Scaffold(
        backgroundColor: const Color(0xFF0B0E14),
        body: Stack(
          children: [
            // Map IMMER an gleicher Stelle im Widget-Tree (verhindert Neu-Erstellung)
            // RepaintBoundary isoliert Canvas-Repaints vom Rest der UI (Web-Performance).
            Positioned.fill(child: RepaintBoundary(child: _buildMapWidget())),

            // Config-Overlay ODER Navigation-Overlay
            // RepaintBoundary trennt UI-Overlays vom Karten-Repaint (Web-Performance).
            // 2026-06-24 (vucko Gruppen-Verlassen-Video): Route-Setup/Übersicht
            // NUR im Solo-Modus. Im Gruppenmodus gibt es KEIN Routen-Erstellen —
            // ein Mitglied navigiert die geteilte Gruppenroute oder geht zurück
            // in die Lobby. So landet niemand im Gruppenmodus auf der Setup-
            // Ansicht (und kann auch nicht alleine eine Route bauen).
            if (!_isRouteConfirmed && widget.groupId == null)
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
            // Gruppe + (noch) keine bestätigte Route = Lade-/Übergangszustand
            // (Route der Gruppe wird gerade geladen, ODER man verlässt gerade).
            // Niemals Route-Setup — nur ein Lade-Hinweis + garantierter Zurück-
            // zur-Lobby-Button.
            if (!_isRouteConfirmed && widget.groupId != null)
              _buildGroupRouteLoadingOverlay(),
            if (_isRouteConfirmed)
              RepaintBoundary(child: _buildNavigationOverlay()),
            // 2026-05-28 (vucko Task #79): Komplette FAB-Spalte auch ohne
            // Route — verschwindet animiert wenn Setup-Sheet hochgezogen ist.
            // Nur Solo: im Gruppenmodus gibt es kein Route-Setup.
            if (!_isRouteConfirmed && widget.groupId == null)
              _buildFabColumn(hasRoute: false),
            if (_shouldShowRoundTripSearchStatus)
              _buildRoundTripSearchStatusOverlay(),
          ],
        ),
        ),
      ),
    );
  }

  /// 2026-07-25 (vucko „Mini-Bildschirm"): PiPSwitcher NUR auf Android
  /// einhängen. Das floating-Plugin hat keine iOS-Implementierung, und der
  /// Switcher pollt intern im 100ms-Takt den Method-Channel — auf iOS/Web
  /// würde das dauerhaft MissingPluginException werfen. Dort wird der
  /// normale Aufbau unverändert durchgereicht.
  Widget _pipAware(Widget normal) {
    if (kIsWeb || !Platform.isAndroid) return normal;
    return PiPSwitcher(
      childWhenEnabled: _buildPipView(),
      childWhenDisabled: normal,
    );
  }

  /// 2026-07-25 (vucko „Mini-Bildschirm"): Inhalt des Android-PiP-Fensters.
  /// Bewusst extrem reduziert — im ~2cm hohen Systemfenster zaehlt nur:
  /// naechstes Manoever (Pfeil + Text), Distanz dorthin, Rest-ETA. KEINE
  /// Karte (native Platform-View in einem so kleinen Fenster ist teuer und
  /// unleserlich), keine Buttons (in PiP nicht bedienbar).
  Widget _buildPipView() {
    // Nutzt bewusst denselben Snapshot wie Live Activity + Android-
    // Benachrichtigung — dort ist die Lead-Kompensation und der
    // Reroute-Zustand bereits korrekt eingerechnet, kein zweiter Datenpfad.
    final snap = _navigationLiveActivitySnapshot();
    final restKm = snap.remainingDistanceMeters;
    final restSec = snap.remainingDurationSeconds;
    final rest = <String>[
      if (restKm != null && restKm.isFinite)
        '${(restKm / 1000).toStringAsFixed(restKm < 10000 ? 1 : 0)} km',
      if (restSec != null && restSec > 0) '${(restSec / 60).round()} min',
    ].join(' · ');

    return Container(
      color: const Color(0xFF0B0E14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppAccentColors.accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(
              snap.isRerouting
                  ? Icons.autorenew_rounded
                  : Icons.navigation_rounded,
              color: AppAccentColors.accent,
              size: 26,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (snap.distanceToManeuverMeters != null)
                  Text(
                    formatNavDistance(snap.distanceToManeuverMeters),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                Text(
                  snap.instruction,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (rest.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    rest,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
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
          if (leave == true && mounted) {
            if (widget.groupId != null) {
              // 2026-06-24 (vucko Gruppe-verlassen-Video): GARANTIERT zurück in
              // die Lobby. Dieser Button erscheint im Gruppen-Lade-/Übergangs-
              // zustand (keine bestätigte Route) — der Post-Screen wurde, falls
              // es einen gab, schon im aktiven Verlassen-Flow gezeigt. Direkt der
              // robuste Lobby-Pfad, NIE über den (durch _completionSheetShown
              // blockierbaren) Sheet-Pfad → kein Dead-End mehr.
              unawaited(_returnToGroupLobbyFromActiveRoute());
            } else {
              Navigator.of(context).pop();
            }
          }
        },
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  /// 2026-06-24 (vucko Gruppen-Verlassen-Video): Im Gruppenmodus OHNE bestätigte
  /// Route gibt es KEIN Route-Setup. Stattdessen ein dezenter Lade-/Übergangs-
  /// Hinweis (die Gruppenroute lädt gerade ODER man verlässt gerade) plus ein
  /// garantierter Zurück-zur-Lobby-Button — so strandet niemand auf einer
  /// Setup-Ansicht und kann auch keine eigene Route bauen.
  Widget _buildGroupRouteLoadingOverlay() {
    final topInset = MediaQuery.of(context).padding.top;
    return Stack(
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1F26).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(AppAccentColors.accent),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Gruppenroute wird geladen …',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Du fährst die Route der Gruppe',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (Navigator.canPop(context))
          Positioned(top: topInset + 12, left: 12, child: _buildExitButton()),
      ],
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
                        onTap: () => _handleVoiceModeCycle(context),
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
    // 2026-06-24 (vucko): Der schwebende Top-Mode-Header (Standard/Trip-Modus +
    // Stop-Zähler) lag GENAU über dem „Runterwischen zum Schließen"-Greiftab →
    // das Panel ließ sich kaum runterziehen. Wenn der Header sichtbar ist, wird
    // der transparente Oberstreifen höher, damit der Greiftab klar UNTER dem
    // Header sitzt (keine Überdeckung mehr).
    final showExpandedModeHeader =
        _isWaypointPlanning &&
        !_showRouteInfoBanner &&
        _routeSearchNoticeTitle == null;
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
                    // 2026-06-24 (vucko): + Platz für den Top-Mode-Header, damit
                    // der Greiftab darunter (statt darunter VERdeckt) sitzt.
                    height:
                        MediaQuery.of(context).padding.top +
                        (showExpandedModeHeader ? 116 : 64),
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
        // wenn Error-Banner aktiv (sonst Doppel-Header oben). Der Greiftab
        // oben bekommt dafür extra Höhe (showExpandedModeHeader), sodass der
        // Header ihn NICHT mehr überdeckt.
        if (showExpandedModeHeader) _buildWaypointModeHeader(),
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
    // 2026-06-25 (vucko): Wert IMMER einzeilig — egal ob „60", „1285" oder
    // „116.8 km" / „2h 13min". Vorher brach der Wert in der schmalen Spalte um
    // („116.8" / „km") → uneinheitliche Zeilenhöhen + komischer Umbruch. FittedBox
    // skaliert breite Werte minimal herunter statt sie umzubrechen.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppAccentColors.accent, size: 20),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
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

  /// 2026-06-24 (vucko Y4): einheitliche dezente Status-Pille (GPS/Internet).
  Widget _buildStatusPill(IconData icon, String text) {
    const amber = Color(0xFFFFB74D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2028).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: amber.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: amber, size: 17),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
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
        // 2026-06-23 (vucko 2-Geräte-Video „GPS-Hinweis"): dezenter, NICHT-
        // verdeckender Hinweis UNTER dem Manöver-Banner — nur wenn der Wagen
        // zuletzt fuhr + der GPS-Stream eingefroren ist (Tunnel/Wald), nie im
        // Stand. Mittig, klein, animiert ein/aus; liegt weder über dem Banner
        // (oben) noch über den unteren Buttons.
        // 2026-06-24 (vucko Y4): Status-Pillen (GPS-schwach + kein Internet),
        // gestapelt, dezent UNTER dem Banner und ÜBER den unteren Buttons — sie
        // verdecken nichts und sind nur Info. Conditional → kein reservierter
        // Leerraum, AnimatedSize blendet sie sanft ein/aus.
        Positioned(
          top: topInset + 8 + (visibleManeuver != null ? 102 : 60),
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_gpsWeak)
                      _buildStatusPill(
                        Icons.satellite_alt_rounded,
                        'GPS-Signal schwach',
                      ),
                    if (_gpsWeak && _offline) const SizedBox(height: 8),
                    if (_offline)
                      _buildStatusPill(
                        Icons.wifi_off_rounded,
                        'Keine Internetverbindung',
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
                  distanceToManeuverMeters: _displayManeuverDistanceMeters(
                    visibleManeuver,
                  ),
                  leading: _buildManeuverBackChevron(),
                  isRerouting: reroutingActive,
                  reroutingDuration: reroutingDuration,
                  // 2026-06-23 (vucko 2-Geräte-Gruppen-Video, C1): ruhiges
                  // „Folge der Gruppe" statt oszillierendem „Neuberechnung",
                  // wenn dieses Gerät als Follower nur auf die Leader-Route
                  // wartet (nur ausgewertet, wenn das Reroute-Banner aktiv ist).
                  groupFollowerWaiting:
                      reroutingActive && _groupFollowerWaitingForLeaderRoute(),
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
                    _setGroupPaused(false);
                    await _startNavigationFlow();
                  },
                  onPause: () {
                    // 2026-06-24 (vucko Y3): Pause an die Gruppe melden, damit die
                    // anderen den Marker als „pausiert" sehen (Heartbeat hält ihn
                    // sichtbar, statt ihn offline aussehen zu lassen).
                    _setGroupPaused(true);
                    _stopNavigationTracking();
                    // 2026-07-06 (vucko Fahrt-Resume): Pause = wahrscheinlichster
                    // Moment vor einem späteren App-Kill → sofort sichern.
                    _persistActiveRideSnapshot(force: true, paused: true);
                  },
                  onStop: () {
                    _setGroupPaused(false);
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
      label: widget.groupId != null
          ? 'Zurück zur Gruppe'
          : 'Zurück zum Strecken-Setup',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _handleActiveRouteBack,
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
      label: widget.groupId != null
          ? 'Zurück zur Gruppe'
          : 'Zurück zum Strecken-Setup',
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
            onTap: _handleActiveRouteBack,
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
    // 2026-06-10/19 (vucko 3km-Sichtdesign): Während der bestätigten Fahrt
    // zeigt die aktive (voll rote) Quelle für Rundkurs/Umweg/Trip nur das
    // 3km-Fenster ab Puck; die dezente Rest-Preview kommt aus
    // _buildMapLibreLines. Nur direkte A→B-Navigation darf die volle aktive
    // Reststrecke zeigen.
    final canUseLiveRouteWindow =
        _isRouteConfirmed &&
        !_isRerouting &&
        _offRouteSince == null &&
        _brightAheadLatLngs.length >= 2;
    // Fallback bei leerem Live-Fenster: Direkt-A→B zeigt die volle Reststrecke,
    // alle anderen Modi bekommen maximal 3 km aktiv plus dezente Preview.
    // In der Preview (noch nicht bestätigt) bleibt _routeLatLngs, damit die
    // Reveal-Animation (2→voll) sichtbar bleibt.
    // 2026-06-21 (vucko 2-Geräte-Video): Beim Reroute die Route SICHTBAR lassen.
    // Früher (commit 8f61df0) wurde die Linie während „Neuberechnung" komplett
    // ausgeblendet, um eine Luftlinie vom Puck zur alten Geometrie zu vermeiden —
    // das ließ die rote Route aber 15s+ KOMPLETT verschwinden (Video-Befund).
    // Jetzt: volle Routen-Geometrie OHNE Puck-Trim zeigen (keine Luftlinie, weil
    // nicht an den Live-Puck-Kopf gehängt) bis die neue Route committet ist —
    // wie Google/Apple, die die alte Route bis zum Reroute-Commit stehen lassen.
    final hideLineForReroute = _isReroutingBannerActive && !_isOverviewActive;
    final activePts = hideLineForReroute
        ? (_routeLatLngs.length >= 2
              ? _fullRouteBackgroundLatLngs
              : const <LatLng>[])
        : (!_isOverviewActive && _routeLatLngs.length >= 2)
        ? (canUseLiveRouteWindow
              ? _brightAheadLatLngs
              : (_isRouteConfirmed
                    ? _activeRouteFallbackPointsForNavigation()
                    : _routeLatLngs))
        : _fullRouteBackgroundLatLngs;
    // 2026-06-25 (vucko native POIs): fehlende Icon-Bilder rastern (self-healing,
    // intern geguarded → idempotent, kein Build-Overhead wenn alles bereit ist).
    _ensurePoiIcons();
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
      // 2026-06-26 (vucko Route-unsichtbar-Fix): Der 3km-Gradient (transparent
      // hinterm Puck, Rest dezent) darf NUR während der bestätigten Fahrt
      // greifen. In der VORSCHAU (Route berechnet, noch nicht bestätigt) ließ er
      // nach Ablauf der 4s-Übersicht ~die ganze Route blass werden → „ich sehe
      // keine Route". Vorschau + Übersicht => Gradient aus, ganze Route voll.
      routeTotalMeters:
          (_isOverviewActive || !_isRouteConfirmed) ? 0.0 : _routeTotalLenM,
      routeColor: AppAccentColors.accent,
      // 2026-06-10 (vucko Fahr-Ruckeln-Fix): Puck folgt pro Frame der Kalman-
      // Prediction (Dead Reckoning zwischen den ~1Hz-GPS-Fixes) statt der
      // rohen Fix-Position — kein Sekunden-Teleport mehr. Web: aus (dort
      // glättet der WebPositionSmoother den Event-Pfad wie bisher).
      // 2026-06-11 (vucko Route-Lock): Der Puck folgt pro Frame der auf die
      // ROUTE gesnappten Render-Position (eine Quelle mit Linien-Schnitt +
      // Kamera) — Puck fährt sichtbar AUF der Linie, kein Auseinanderlaufen.
      liveSmoothedPosition: kIsWeb ? null : _readRouteLockedRenderPosition,
      // 2026-06-25 (vucko Marker-Swim): POIs/Baustellen als NATIVE Symbole.
      poiFeatures: _buildPoiFeatures(),
      poiImages: _poiIconImages,
      onPoiTapped: _onPoiSymbolTapped,
      onControllerReady: (c) {
        _mlController = c;
        if (!_mapReady) _onMapReady();
      },
      onMapClick: (p) => _handleMapTap(null, p),
      onCameraMoved: () {
        // 2026-07-22 (vucko Free-Cam-Kompass): Gesten-START stempeln — Auto-
        // Rotate pausiert, während der Nutzer die Karte selbst bewegt.
        _lastUserCameraGestureAt = DateTime.now();
        _unlockCameraFollow();
        _scheduleViewportPoiRefresh();
      },
      // Gesten-ENDE erneut stempeln: die 3s-Sperre beginnt erst ab Loslassen
      // (sonst dreht die Kamera bei langen Gesten mitten unterm Finger los).
      onUserGestureEnd: () {
        _lastUserCameraGestureAt = DateTime.now();
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

  bool get _directPointToPointShowsFullActiveRoute =>
      !_isRoundTrip &&
      !_activePointToPointScenic &&
      _activeDetourVariant <= 0 &&
      _activeIntermediateWaypoints.isEmpty;

  List<LatLng> _activeRouteFallbackPointsForNavigation() {
    if (_directPointToPointShowsFullActiveRoute) {
      return _activeRouteAheadFromIndex();
    }
    return _activeRouteWindowFromIndex(maxMeters: 3000.0);
  }

  List<LatLng> _activeRouteWindowFromIndex({required double maxMeters}) {
    final coords = _fullRouteCoordinates;
    if (coords.length < 2) return _routeLatLngs.take(2).toList(growable: false);
    final idx = _currentRouteIndex.clamp(0, coords.length - 1).toInt();
    final head = _lastRouteLockedRenderLatLng;
    final pts = <LatLng>[];
    var prevLat = 0.0;
    var prevLng = 0.0;
    var nextIndex = 0;

    if (head != null) {
      pts.add(head);
      prevLat = head.latitude;
      prevLng = head.longitude;
      nextIndex = (idx + 1).clamp(0, coords.length).toInt();
    } else {
      final c = coords[idx];
      pts.add(LatLng(c[1], c[0]));
      prevLat = c[1];
      prevLng = c[0];
      nextIndex = (idx + 1).clamp(0, coords.length).toInt();
    }

    var acc = 0.0;
    while (nextIndex < coords.length && acc < maxMeters) {
      final c = coords[nextIndex];
      final d = geo.Geolocator.distanceBetween(prevLat, prevLng, c[1], c[0]);
      if (!d.isFinite || d <= 0) {
        nextIndex++;
        continue;
      }
      if (acc + d <= maxMeters) {
        pts.add(LatLng(c[1], c[0]));
        acc += d;
        prevLat = c[1];
        prevLng = c[0];
        nextIndex++;
        continue;
      }
      final remain = maxMeters - acc;
      final f = (remain / d).clamp(0.0, 1.0);
      pts.add(
        LatLng(prevLat + (c[1] - prevLat) * f, prevLng + (c[0] - prevLng) * f),
      );
      break;
    }

    if (pts.length >= 2) return pts;
    return _routeLatLngs.take(2).toList(growable: false);
  }

  List<CruiseMapLine> _buildMapLibreLines() {
    // 2026-06-10 (vucko 3km-Sichtdesign v2): Während der bestätigten Fahrt
    // liegt hier die DEZENTE Reststrecke ab Puck (Opacity 0.30) — sie deutet
    // „es geht weiter" an, während die aktive Quelle nur das volle
    // 3km-Fenster zeigt. 200m-Gate: ihr Anfang liegt unter dem bright-Fenster
    // und ist unsichtbar, darum sind seltene Pushes voellig ausreichend.
    // 2026-06-21 (vucko Reroute-Luftlinie): auch die dezente Vorschau-Linie
    // während aktiver Neuberechnung ausblenden — sonst zeichnet sie denselben
    // Off-Road-Verbinder zur alten Route.
    if (_isRouteConfirmed && !_isOverviewActive && !_isReroutingBannerActive) {
      final previewPts = _dimRemainingLatLngs.length >= 2
          ? _dimRemainingLatLngs
          : _directPointToPointShowsFullActiveRoute
          ? const <LatLng>[]
          : _activeRouteAheadFromIndex();
      if (previewPts.length < 2) return const <CruiseMapLine>[];
      return [
        CruiseMapLine(
          points: previewPts,
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
    // 2026-06-25 (vucko Marker-Swim): POIs + Baustellen sind jetzt NATIVE
    // Symbol-Layer (GPU, kein Overlay mehr → kein Schwimmen beim Pannen). Siehe
    // poiFeatures/poiImages an der CruiseMapLibreMap + _buildPoiFeatures/
    // _ensurePoiIcons/_onPoiSymbolTapped. (Flutter-Overlay nur noch für Puck,
    // Wegpunkte, Start/Ziel, Gruppen-Peers.)
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
        markers.add(
          CruiseMapMarker(
            id: 'grp-${entry.key}',
            position: _peerRenderPoint(entry.key, m),
            width: 48,
            height: 48,
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
    final visibleRouteLatLngs = _isRouteConfirmed
        ? _activeRouteFallbackPointsForNavigation()
        : _routeLatLngs;
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
        if (visibleRouteLatLngs.length >= 2)
          PolylineLayer(
            polylines: [
              if (!kIsWeb)
                // Glow-Effekt (nur native — auf Web zu teuer für CanvasKit)
                Polyline(
                  points: visibleRouteLatLngs,
                  color: AppAccentColors.accent.withValues(alpha: 0.30),
                  strokeWidth: 12,
                ),
              // Haupt-Routenlinie
              Polyline(
                points: visibleRouteLatLngs,
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
        // ── Verkehrsmeldungs-Marker (2026-07-24, "+-Button") ───────────────
        if (_routeIncidents.isNotEmpty)
          MarkerLayer(
            rotate: true,
            markers: [
              for (final incident in _routeIncidents)
                Marker(
                  point: LatLng(incident.latitude, incident.longitude),
                  width: 40,
                  height: 40,
                  child: GestureDetector(
                    onTap: () => IncidentAlertSheet.show(context, incident),
                    child: _buildIncidentMarker(incident),
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
                    point: _peerRenderPoint(m.userId, m),
                    width: 48,
                    height: 48,
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
    // 2026-07-22 (vucko Free-Cam-Kompass): Die Seite startet im freien Modus
    // (_isCameraLocked=false) — Kompass sofort mitlaufen lassen, nicht erst
    // nach der ersten Geste. Lock-Pfade stoppen ihn in _recenterMap().
    _startCompassIfNeeded();
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
            onPressed: _isLoading
                ? _cancelRouteGeneration
                : _onSearchButtonPressed,
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
    // 2026-06-21 (vucko Geräte-Video „Puck wie iOS, keine zwei Ringe"): auf
    // ALLEN Plattformen der saubere Apple-Maps-Punkt. Der frühere Android-Puck
    // (_buildDefaultLocationPuck) legte einen großen transluzenten blauen
    // Accuracy-Halo um den Punkt → wirkte wie zwei Ringe. Weg damit.
    return _buildiOSLocationPuck(headingDegrees);
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

    // 2026-07-03 (vucko „Standort immer / direkt in Einstellungen"): Einheitlich
    // über den Helper — fragt an, stuft (so weit per Dialog möglich) auf „Immer"
    // hoch und leitet sonst DIREKT in die App-Einstellungen. Kein Plattform-Split
    // mehr; iOS versucht jetzt auch erst die Hochstufung statt sofort Settings.
    final permission = await LocationPermissionHelper.requestAlways();
    if (!mounted || _disposed) return false;
    if (permission == geo.LocationPermission.always) return true;

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

  /// 2026-07-23 (vucko Werbung): 30s-Rewarded-Video bei der SUCH-AKTION selbst
  /// (vorher Interstitial) — feuert GENAU beim Nutzer-Tap auf „Rundkurs/
  /// A-nach-B/Wegpunkt suchen" (auch bei der Erstsuche), NICHT bei internen
  /// Re-Läufen (Trip-Resume-Auto-Generate, Validator-/Auto-Retry, POI-Reroute)
  /// — die rufen `_generateRoute` direkt. Fire-and-forget: die Suche selbst
  /// läuft parallel weiter und wird durchs Video nie blockiert.
  void _onSearchButtonPressed() {
    _showRouteSearchRewardedVideoIfDue();
    unawaited(_generateRoute());
  }

  /// Gemeinsamer Ad-Hook für JEDEN manuellen "ich will jetzt eine (neue)
  /// Route" Tap — auch die "Direkte Route nehmen"/"Nochmal suchen"-Buttons
  /// im Warmup-Dialog (_showRouteWarmupDialog) zählen als solcher Tap, nicht
  /// nur der Haupt-Such-Button. Cooldown verhindert Spam bei mehreren Taps
  /// kurz hintereinander.
  void _showRouteSearchRewardedVideoIfDue() {
    // Ohne Werbesystem auf main bewusst ein No-Op — die Aufrufstellen (Haupt-
    // Such-Button, Warmup-Dialog) bleiben erhalten, damit der Hook beim
    // spaeteren Werbe-Merge nur an EINER Stelle wieder scharf geschaltet wird.
  }

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
        // 2026-07-27 (vucko „der Inlandsfilter funktioniert immer noch nicht"):
        // CountryRegion.classify() kennt nur DACH und die direkten Nachbarn.
        // Ausserhalb davon lieferte es null, und DANN prüften weder Client
        // noch Edge Function irgendetwas — der Filter war ein stiller No-Op,
        // ohne dass der Nutzer je erfahren hätte, warum die Route trotzdem
        // ins Ausland führt. Jetzt sagen wir es ihm.
        if (_homeCountryCode == null && mounted) {
          TopToast.show(
            context,
            message:
                'Für diese Gegend kennen wir das Land nicht. „Im Land bleiben" '
                'wirkt hier nicht.',
            icon: Icons.public_off_rounded,
            duration: const Duration(seconds: 4),
          );
        }
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
                      _lastGeneratedAvoidHighways != _avoidHighways ||
                      // 2026-07-06 (vucko Routen-Wiederholung): Umweg-Level
                      // („Direkt/Klein/Mittel/Groß") ist eine echte Settings-
                      // Änderung — vorher wurde sie ignoriert.
                      _lastGeneratedDetour != _selectedDetour)));
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
        // 2026-07-06 (vucko Routen-Wiederholung): Seed pro Suche monoton
        // verschieben. Vorher: forceFreshVariant (bool) + auf GANZE Grad
        // gerundete Zielkoordinaten → ab der 2. Generierung war der Seed
        // für immer identisch und Versuch 3+ zeigte immer wieder Route 2.
        _p2pSearchSalt += 1;
        final p2pDiversitySeed = Object.hash(
          (destLat * 1000).round(),
          (destLng * 1000).round(),
          detourVariant,
          _avoidHighways,
          _p2pSearchSalt,
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
        // 2026-07-10 (vucko Gruppen-Rundkurs-Resume): Auch Gruppen-RUNDFAHRTEN
        // als Trip persistieren — vorher tat das NUR der A→B-Zweig oben, sodass
        // eine Gruppen-Rundfahrt nach App-Kill/Neustart KEIN Resume hatte. Der
        // Trip (mit group_id) ist der Rejoin-Anker: er erscheint als Home-Card
        // und führt per pendingGroupView zurück in die Lobby → „Zur laufenden
        // Route". Best-effort, fail silent.
        if (widget.groupId != null &&
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
    // hat in Feldkirch/Götzis bis zu mehrere Minuten warten müssen).
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
            RouteLoadingPhases.roundTrip.length - 1,
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
    _hideRouteSearchStatusForAcceptedRoute();
    _lastGeneratedWasRoundTrip = _isRoundTrip;
    _lastGeneratedSelectedKm = _isRoundTrip ? distance : null;
    _lastGeneratedSelectedStyle = _selectedStyle;
    _lastGeneratedAvoidHighways = _avoidHighways;
    _lastGeneratedDetour = _selectedDetour;
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
    // 2026-07-22 (vucko Werbung): Die Such-Interstitial feuert jetzt beim
    // KLICK auf den Such-Button (_onSearchButtonPressed), nicht mehr hier nach
    // dem Ergebnis — so kommt die Werbung genau bei der Aktion (auch bei der
    // Erstsuche) und legt sich über die „Suche läuft"-Anzeige.
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
    // 2026-07-24 (vucko "+-Button"): Verkehrsmeldungen ebenso frisch pro Route.
    _routeIncidents = const [];
    _incidentGeofence.clear();
    _activeIncidentAlertId = null;
    unawaited(_checkHazardsInBackground(result.coordinates));
    // 2026-05-24 (vucko Task #49): POIs auto-laden wenn Settings aktiv
    // (Google-Maps-Style: Tankstellen erscheinen automatisch auf der Map).
    //
    // 2026-07-27 (vucko „die POIs verschwinden einfach"): Die Liste wird hier
    // NICHT mehr sofort geleert. Vorher wurden _routePois, _routeConstructions
    // und _routeIncidents im selben Tick auf leer gesetzt — damit griff der
    // Early-Return in _buildPoiFeatures (alle drei leer), und die native Karte
    // bekam per setGeoJsonSource eine LEERE FeatureCollection. Sämtliche
    // Marker verschwanden sichtbar, teils sekundenlang, teils dauerhaft (wenn
    // das Nachladen scheiterte). Jetzt bleiben die alten Marker stehen, bis
    // die neuen da sind; _loadPoisFromSettings ersetzt sie in einem Rutsch und
    // räumt im Fehlerfall selbst auf.
    if (PoiSettingsService.instance.anyEnabled) {
      unawaited(_loadPoisFromSettings(result.coordinates));
    } else {
      _routePois = const [];
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
      // bright fällt auf die volle Route zurück (nie unsichtbar), dim wird
      // beim nächsten Tick sofort neu gesetzt (dimHead == null).
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
        // 2026-06-27 (vucko): A→B nicht mehr hart auf den Routenstart (Index 0)
        // pinnen. Der frühere P9-Pin zwang eine Luftlinie/Anfahrt zum Original-
        // Start, wenn die Route am User vorbeiläuft. Stattdessen schleichend an
        // den nächsten Vorwärts-Punkt anschließen (joinNearestForward); Rundkurse
        // behalten die Loop-Rotation (rebaseClosedLoop, Ende = Original-Start).
        preferredJoinIndex: null,
        joinNearestForward: !isRoundTrip,
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
    // Gerät auf ~80-100m (accuracy*0.8 bis 48 + speedBuffer bis 35) — eine
    // Parallelstrasse 40m daneben galt als "on-route", das Banner fror bei 0m
    // ein und der Reroute kam minutenlang nicht. Gestrafft auf Google-Niveau;
    // Fehl-Reroutes verhindert weiterhin die Zeit-Hysterese + das
    // heading-bedingte Vorwaerts-Veto, nicht ein Riesen-Korridor.
    final speedBuffer = speed > 22 ? 10.0 : (speed > 12 ? 6.0 : 0.0);
    return baseCorridor + accuracy * 0.45 + speedBuffer;
  }

  /// 2026-06-12 (vucko): Stimmt der GPS-Kurs grob mit der Routen-Tangente am
  /// Match überein? Nur aussagekraeftig bei echter Fahrt (>4 m/s) und
  /// gültigem Kurs — sonst konservativ true.
  bool _gpsHeadingAlignedWithRoute(
    geo.Position position,
    RouteWindowMatch match,
  ) {
    if (!position.speed.isFinite || position.speed < 4.0) return true;
    if (!position.heading.isFinite || position.heading < 0) return true;
    final coords = _fullRouteCoordinates;
    final i = match.index.clamp(0, coords.length - 2);
    final tangent = GeoBearing.bearingDegrees(
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
    final tangent = GeoBearing.bearingDegrees(
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
      final b = GeoBearing.bearingDegrees(
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


  /// 2026-06-21 (vucko Geräte-Video „Route immer leicht geneigt"): Kamera-Bearing
  /// aus der ROUTEN-TANGENTE statt aus dem verrauschten GPS-Kurs. Schaut von der
  /// route-gesnappten Render-Position [head] ~[lookAheadMeters] entlang der Route
  /// voraus und liefert die Richtung dorthin → die befahrene Straße zeigt im
  /// Display senkrecht nach oben (wie Apple/Google). Liefert null bei Off-Route
  /// oder zu kurzer Restroute (dann GPS-Heading-Fallback).
  double? _routeTangentCameraBearing(
    LatLng head, {
    double lookAheadMeters = 30.0,
  }) {
    if (_offRouteSince != null) return null;
    final coords = _fullRouteCoordinates;
    if (coords.length < 2) return null;
    final idx = _currentRouteIndex.clamp(0, coords.length - 2).toInt();
    var acc = 0.0;
    var prevLat = head.latitude;
    var prevLng = head.longitude;
    double? aheadLat;
    double? aheadLng;
    for (var i = idx + 1; i < coords.length; i++) {
      final lat = coords[i][1];
      final lng = coords[i][0];
      final d = geo.Geolocator.distanceBetween(prevLat, prevLng, lat, lng);
      if (!d.isFinite || d <= 0) {
        prevLat = lat;
        prevLng = lng;
        continue;
      }
      if (acc + d >= lookAheadMeters) {
        final f = ((lookAheadMeters - acc) / d).clamp(0.0, 1.0);
        aheadLat = prevLat + (lat - prevLat) * f;
        aheadLng = prevLng + (lng - prevLng) * f;
        break;
      }
      acc += d;
      prevLat = lat;
      prevLng = lng;
      aheadLat = lat;
      aheadLng = lng;
    }
    if (aheadLat == null || aheadLng == null) return null;
    final dist = geo.Geolocator.distanceBetween(
      head.latitude,
      head.longitude,
      aheadLat,
      aheadLng,
    );
    // Zu kurzer Vorlauf → unzuverlässige Tangente, lieber GPS-Fallback.
    if (dist < 5.0) return null;
    return GeoBearing.bearingDegrees(head.latitude, head.longitude, aheadLat, aheadLng);
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
    // 2026-07-02 (vucko Monitoring): EINE zentrale Stelle für alle
    // Routen-Fehlschläge (initial + Reroute + Zusatzsuche) — zeigt in Firebase
    // Analytics, wie oft und warum Nutzer beim Kernfeature hängen bleiben.
    unawaited(
      AnalyticsService.instance.logRouteGenerationFailed(
        _isRoundTrip ? 'roundtrip' : 'point_to_point',
        message,
      ),
    );
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
            : 'Keine neue Variante gefunden, deine Route passt.';
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
        // 2026-07-23 (vucko Werbung): echter manueller Tap auf eine neue
        // Suche — zählt wie der Haupt-Such-Button, nicht wie ein interner
        // Auto-Retry.
        _showRouteSearchRewardedVideoIfDue();
        unawaited(Future<void>.delayed(Duration.zero, _generateRoute));
      } else if (action == 'retry') {
        _showRouteSearchRewardedVideoIfDue();
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
    _lastGeneratedDetour = null;
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
      _advanceCapRejects = 0;
      _lastRouteIndexAdvanceAt = null;
      _lastPlausibleRawFix = null;
      _gpsJumpRejects = 0;
      _navigationController.clearManeuverDistanceSmoothing();
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
  }

  void _saveActiveTripForLater() {
    _returnToCruiseSetupFromActiveRoute();
  }

  void _handleActiveRouteBack() {
    if (widget.groupId != null) {
      unawaited(_confirmAndStopGroupRide());
      return;
    }
    if (_soloRideIsRunning) {
      unawaited(_confirmAndLeaveSoloRide());
      return;
    }
    _returnToCruiseSetupFromActiveRoute();
  }

  /// Läuft gerade eine echte Solo-Fahrt (nicht bloß die Routenvorschau)?
  /// Nur dann ist ein Rückfragen sinnvoll — in der Vorschau kostet Zurück
  /// nichts und ein Dialog wäre reine Belästigung.
  bool get _soloRideIsRunning =>
      widget.groupId == null &&
      _isRouteConfirmed &&
      (_positionSubscription != null || _activeTripId != null);

  /// 2026-07-27 (vucko „beim Zurück soll ein Pop-up kommen"): Bestätigung vor
  /// dem Verlassen einer laufenden Solo-Fahrt.
  ///
  /// Zum Text: Vucko wollte sinngemäß „du verlierst alle deine
  /// Erfahrungspunkte". Das wäre falsch und hätte Nutzer unnötig erschreckt —
  /// XP werden ausschließlich im Abschluss-Sheet vergeben
  /// (_recordDriveSessionForCurrentRoute, nur aus onSave/onDiscard des
  /// CruiseCompletionDialog). Wer ohne Beenden zurückgeht, bekommt für DIESE
  /// Fahrt keine Punkte; bereits gutgeschriebene Punkte werden nirgends im
  /// Code wieder abgezogen. Der Dialog sagt deshalb genau das.
  Future<void> _confirmAndLeaveSoloRide() async {
    if (!mounted || _disposed) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text(
          'Fahrt wirklich verlassen?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Für diese Fahrt bekommst du dann keine Erfahrungspunkte. '
          'Deine bisherigen Punkte bleiben dir erhalten.\n\n'
          'Beende die Fahrt stattdessen, dann wird sie gewertet.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: Text(
              'Weiterfahren',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('end'),
            child: const Text(
              'Fahrt beenden',
              style: TextStyle(
                color: Color(0xFF5BD98A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('leave'),
            child: const Text(
              'Verlassen',
              style: TextStyle(
                color: Color(0xFFFF6B61),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted || _disposed) return;
    if (choice == 'end') {
      _stopNavigationTracking();
      _stopSimulation(restartLiveTracking: false);
      _onRouteEarlyStopped();
      return;
    }
    if (choice != 'leave') return;
    _returnToCruiseSetupFromActiveRoute();
  }

  // 2026-06-20 (vucko Gruppen-Exit-Flow): Verlässt ein Gruppen-Mitglied die
  // Fahrt über den Zurück-Button, MUSS es (1) bestätigen, (2) den Post-Route-
  // Screen mit seinen Stats/anteiligem XP sehen und (3) danach zurück in die
  // LOBBY — NIEMALS in eine eigene Routensuche. Wir leiten über den normalen
  // Abschluss-Flow (_onRouteEarlyStopped → Completion-Sheet), der die WIRKLICH
  // gefahrene Strecke (Driven-Track) + daraus berechnetes XP zeigt; die Lobby-
  // Navigation passiert nach dem Sheet-Schliessen (_presentCompletionSheet).
  Future<void> _confirmAndStopGroupRide() async {
    if (!mounted || _disposed) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text(
          'Fahrt verlassen?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Bist du sicher, dass du die Fahrt verlassen willst?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Abbrechen',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Verlassen',
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
    _onRouteEarlyStopped();
  }

  Future<void> _returnToGroupLobbyFromActiveRoute() async {
    if (!mounted || _disposed) return;
    _dismissTransientRouteUi();
    _stopSimulation(restartLiveTracking: false);
    _stopNavigationTracking();
    CruiseModePage.isFullscreen.value = false;
    final groupId = widget.groupId;
    if (groupId == null) {
      await Navigator.of(context).maybePop();
      return;
    }
    // 2026-06-20 (vucko Gruppen-Rejoin): Bewusstes Verlassen → die Lobby darf
    // mich NICHT automatisch in die laufende Fahrt zurückziehen. Rejoin nur
    // über den expliziten „Zur laufenden Route"-Button.
    CruiseModePage.suppressedAutoEnterGroupIds.add(groupId);
    // 2026-06-24 (vucko Gruppen-Verlassen-Video): GARANTIERT in die Lobby —
    // deterministisch und ohne Seiteneffekte. Früher: maybePop(); das poppte am
    // Gerät manchmal NICHT (PopScope-canPop / ungewöhnlicher Stack) → man strandete
    // auf der leeren Route-Setup-Ansicht im Gruppenmodus und kam per Button nicht
    // mehr raus. Jetzt: die Cruise-Page (und eine evtl. darunterliegende Lobby)
    // werden entfernt und durch eine FRISCHE Lobby ersetzt. Kein PopScope-Trigger
    // (kein Geister-„verlassen?"-Dialog), keine Doppel-Lobby, kein Dead-End.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => GroupLobbyPage(groupId: groupId)),
      (route) => route.isFirst,
    );
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
    if (widget.groupId != null) {
      unawaited(_returnToGroupLobbyFromActiveRoute());
      return;
    }
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
          message: 'Tour zwischengespeichert, auf Home fortsetzen',
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
      // 2026-06-20 (vucko Gruppen-Video): Top-Toast statt Bottom-SnackBar, damit
      // die Meldung die Pause/Beenden-Buttons während der Fahrt nicht verdeckt.
      TopToast.show(
        context,
        message: 'Hauptroute erreicht. Navigation läuft normal weiter.',
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

  /// 2026-06-23 (vucko Voice-Lautstärke): Sprach-Modus zyklisch schalten
  /// (off→important→all→off). Beim WIEDER-Einschalten nach komplettem Aus
  /// (off→an) das Lautstärke-Sheet mit Test-Stimme zeigen statt nur des Toasts —
  /// so kann der Nutzer die (bisher fixe, zu leise) Lautstärke einstellen.
  Future<void> _handleVoiceModeCycle(BuildContext buttonContext) async {
    final oldMode = VoiceSettingsService.instance.mode;
    await VoiceSettingsService.instance.cycleMode();
    HapticFeedback.selectionClick();
    final newMode = VoiceSettingsService.instance.mode;
    if (newMode == VoiceMode.off) {
      unawaited(TtsService.instance.stop());
    } else {
      unawaited(TtsService.instance.prepare());
    }
    if (!mounted || !buttonContext.mounted) return;
    if (oldMode == VoiceMode.off && newMode != VoiceMode.off) {
      await showVoiceVolumeSheet(buttonContext);
      return;
    }
    final newLabel = switch (newMode) {
      VoiceMode.off => 'Stumm',
      VoiceMode.important => 'Nur Wichtiges',
      VoiceMode.all => 'Alle Ansagen',
    };
    if (!mounted || !buttonContext.mounted) return;
    TopToast.show(
      buttonContext,
      message: 'Sprache: $newLabel',
      icon: switch (newMode) {
        VoiceMode.off => Icons.volume_off_rounded,
        VoiceMode.important => Icons.volume_down_rounded,
        VoiceMode.all => Icons.volume_up_rounded,
      },
      // 2026-06-23 (vucko Video s19-21): während der Navigation den Toast UNTER
      // das Manöver-Banner schieben statt darüber (verdeckte sonst die Abbiegung).
      topOffset: _isRouteConfirmed ? 96.0 : 0.0,
    );
  }

  Future<void> _startNavigationFlow() async {
    _completionSheetShown = false; // neue Fahrt → genau ein Post-Sheet erlauben
    final hasLocationPermission = await _ensureNavigationLocationPermission();
    if (!hasLocationPermission) return;

    // 2026-07-02 (vucko Geräte-Video): Voice-State der letzten Fahrt darf die
    // neue nicht beeinflussen (Index-Kollision → verschluckte/doppelte Ansage).
    _voicePreAnnouncedManeuverIndex = null;
    _voicePreAnnouncedText = null;
    _voiceStableManeuverIndex = null;
    _voiceManeuverStableSince = null;
    TtsService.instance.resetNavTag();

    await _prepareAccessLegForOffRouteStart();
    await _prepareXpStreakContext();
    if (VoiceSettingsService.instance.mode != VoiceMode.off) {
      await TtsService.instance.prepare();
    }
    _startNavigationTracking();
    _startNavigationLiveActivity();
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
  }

  Future<void> _prepareXpStreakContext() async {
    final streakDays = await GamificationService.getStreakDaysForNextRide(
      rideDate: DateTime.now(),
    );
    if (!mounted || _disposed) return;
    _xpStreakDays = streakDays;
  }

  Future<void> _prepareAccessLegForOffRouteStart() async {
    // 2026-06-17 (vucko Kaltstart-Off-Route, Video 0:16-0:27): Auch für FRISCHE
    // A→B-Suchen re-ankern. Vorher nur für gespeicherte Sessions
    // (_isExistingRouteSession) — bei einer frischen Suche fuhr der Nutzer aber
    // zwischen „Suchen" und „Fahrt starten" oft schon ein Stück; die Route
    // startete dann seitlich vom echten Standort und ein später Reroute musste
    // es reparieren. Die Methode ist defensiv (sie kehrt sofort zurück, wenn der
    // Puck am Start liegt oder keine Quell-Route vorliegt), also kein Risiko für
    // den Normalstart.
    if (_fullRouteCoordinates.length < 2) return;
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
    final movingNavigationStart =
        position.speed.isFinite && position.speed >= 2.5;
    final startIsPinnedEnoughForMoving =
        !movingNavigationStart || distanceToRouteStart <= _headSnapMaxMeters;
    final matchesRouteStartIndex =
        globalMatch.index <= 24 ||
        (_isRoundTrip &&
            globalMatch.index >=
                math.max(0, _fullRouteCoordinates.length - 25));
    if (startIsPinnedEnoughForMoving &&
        distanceToRouteStart <= onStartCorridor &&
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
        final committed = await _commitRerouteResult(
          result: accessPlan.sessionRoute,
          sessionRouteResult: accessPlan.sessionRoute,
          position: position,
          publishToGroup: false,
        );
        if (!committed) return;
        _safeSetState(() {
          _clearAccessLegState();
          _sessionRouteStartIndexInActiveRoute = 0;
          _totalDistanceDriven = 0.0;
          _drivenTrackRecorder.reset();
        });
      }
      return;
    }

    final committed = await _commitRerouteResult(
      result: accessPlan.activeRoute,
      sessionRouteResult: accessPlan.activeRoute,
      position: position,
      publishToGroup: false,
    );
    if (!committed) return;

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
      // 2026-06-20 (vucko Gruppen-Video): Top-Toast statt Bottom-SnackBar — nicht
      // über die Pause/Beenden-Buttons legen.
      TopToast.show(
        context,
        message:
            'Anfahrts-Abschnitt aktiv. Danach geht es auf die gespeicherte Route.',
        icon: Icons.route_rounded,
        // 2026-06-24 (vucko Video): bei aktiver Navigation UNTER das Manöver-
        // Banner, damit es z.B. eine Kreisverkehr-Ansage nicht verdeckt.
        topOffset: _isRouteConfirmed ? 96.0 : 0.0,
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
        remappedManeuvers.add(m.copyWith(routeIndex: bestIdx));
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
  static const double _rerouteMaxStartOffsetMeters = 120.0;

  /// Maximaler Abstand zwischen der Commit-Position und der Route, die sichtbar
  /// übernommen oder in die Gruppe publiziert werden darf. Liegt der Fahrer nach
  /// Edge-/Netz-Latenz schon weiter daneben, bleibt die alte Linie stehen und
  /// der nächste Zyklus startet mit frischer Position statt eine versetzte Route
  /// kurz sichtbar zu machen.
  static const double _rerouteCommitMaxRouteOffsetMeters = 65.0;

  /// 2026-06-22 (vucko Reroute-Hang): Obergrenze, ab der ein laufender Reroute
  /// als „hängend" gilt. Bewusst großzügig über dem realistischen Worst-Case
  /// (zwei Zyklen mit je mehreren sequenziellen ≤10s-HTTP-Calls können legitim
  /// 15-20s dauern) — der Watchdog soll NUR im echten Hänger feuern, nicht eine
  /// noch laufende, normal-langsame Neuberechnung abwürgen. Ein evtl. doch noch
  /// committender Spät-Zyklus wird vom 65m-Stale-Check abgefangen.
  static const Duration _rerouteWatchdogTimeout = Duration(seconds: 22);

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
      return 'Reroute verworfen: Server-Route startete zu weit entfernt. Folge der Linie, der nächste Versuch kommt automatisch.';
    }
    final last = causes.isNotEmpty ? causes.last : '';
    if (last.startsWith('timeout') || last.startsWith('network')) {
      return 'Reroute gerade nicht möglich (Netz/Server). Folge der Linie, der nächste Versuch kommt automatisch.';
    }
    if (last.startsWith('edge_error')) {
      return 'Reroute-Server meldet einen Fehler. Folge der Linie, der nächste Versuch kommt automatisch.';
    }
    if (last.startsWith('no_route') || last == 'no_candidate') {
      return 'Keine Anschlussroute gefunden. Folge der Linie, wende erst bei sicherer Möglichkeit.';
    }
    return 'Keine sichere Reroute. Folge der Linie und wende erst bei sicherer Möglichkeit';
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
    // eine alte aktive Linie stehen lassen. Der Off-Route-Loop nutzt dafür den
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
            'Keine sichere Reroute. Folge der Linie und wende erst bei sicherer Möglichkeit',
        icon: Icons.warning_amber_rounded,
        isError: true,
        duration: const Duration(milliseconds: 4000),
      );
    }
  }

  Future<bool> _hasConnectivityForReroute() async {
    if (kIsWeb) return true;
    try {
      // 2026-06-22 (vucko Reroute-Hang): Der Connectivity-Plugin-Call hat KEIN
      // eigenes Timeout und kann auf manchen Android-Geräten hängen — dann blieb
      // _isRerouting für immer true und das Banner stand endlos auf
      // „Neuberechnung". Hart deckeln; bei Timeout online annehmen (der HTTP-
      // Reroute scheitert ohnehin schnell, wenn wir wirklich offline sind).
      final results = await Connectivity().checkConnectivity().timeout(
        const Duration(seconds: 2),
      );
      return results.any((result) => result != ConnectivityResult.none);
    } catch (error) {
      debugPrint(
        '[CruiseMode] Connectivity-Check für Reroute fehlgeschlagen: $error',
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
        message: 'Offline: Gespeicherte Route bleibt sichtbar',
        icon: Icons.cloud_off_rounded,
        isError: true,
        duration: const Duration(milliseconds: 4000),
      );
    }
  }

  double _calculatePolylineDistanceMeters(List<List<double>> coordinates) {
    return GeoDistance.polylineMetersLngLat(coordinates);
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

  double? _kmMetaToMeters(Map<String, dynamic> meta, String key) {
    final value = meta[key];
    if (value is num && value.isFinite) return value.toDouble() * 1000.0;
    return null;
  }

  double _routeResultDistanceMeters(RouteResult result) {
    final distance = result.distanceMeters;
    if (distance != null && distance.isFinite && distance > 0) {
      return distance;
    }
    return _calculatePolylineDistanceMeters(result.coordinates);
  }

  bool _rejectsProtectedShortReroute(
    RouteResult result, {
    required double? remainingDistanceBeforeMeters,
  }) {
    if (!_isRoundTrip && widget.groupId == null) return false;
    final meta = result.edgeMeta;
    final isReroute =
        meta['reroute_triggered'] == true || meta['reroute_mode'] != null;
    if (!isReroute) return false;
    final before =
        remainingDistanceBeforeMeters ??
        _kmMetaToMeters(meta, 'remaining_distance_before') ??
        _remainingDistance ??
        (_remainingRouteCoordinates.length >= 2
            ? _calculatePolylineDistanceMeters(_remainingRouteCoordinates)
            : null) ??
        _routeDistance;
    final after =
        _kmMetaToMeters(meta, 'remaining_distance_after') ??
        _routeResultDistanceMeters(result);
    final keepsDistance = reroutePreservesPlannedRemainingDistance(
      beforeMeters: before,
      afterMeters: after,
    );
    if (keepsDistance) return false;
    debugPrint(
      '[CruiseMode][RerouteGuard] Kandidat verworfen: Reststrecke würde '
      'zu stark schrumpfen '
      'before=${((before ?? 0) / 1000).toStringAsFixed(1)}km '
      'after=${(after / 1000).toStringAsFixed(1)}km '
      'mode=${meta['reroute_mode']} group=${widget.groupId != null} '
      'roundtrip=$_isRoundTrip',
    );
    return true;
  }

  Future<bool> _commitRerouteResult({
    required RouteResult result,
    required geo.Position position,
    RouteResult? sessionRouteResult,
    bool publishToGroup = true,
    double? remainingDistanceBeforeMeters,
    // 2026-06-23 (vucko 2-Geräte-Video „Reroute findet ab einem Punkt KEINE
    // Route mehr"): Der lokale Re-Anchor-Notnagel beginnt PER KONSTRUKTION exakt
    // an der GPS-Position und ist die letzte Rettung gegen die Endlos-
    // „Neuberechnung". Er darf NICHT an den Shape-/Stale-Gates scheitern (sonst
    // bleibt der Fahrer ohne Route) → diese beiden Gates für ihn überspringen.
    bool allowStaleReanchor = false,
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
    // 2026-06-13 (vucko Reroute-Videos): Beim Commit zählt die JETZT-Position
    // (Smoother-Prediction), nicht die bis zu mehrere Sekunden alte Request-
    // Position — für Wenden-Check, Re-Anchor und den Stale-Check unten.
    final commitPos = _freshRerouteStartPosition(position, lead: Duration.zero);
    if (!allowStaleReanchor &&
        _rejectsProtectedShortReroute(
          result,
          remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
        )) {
      _lastRerouteTime = DateTime.now();
      _lastRerouteFailed = true;
      return false;
    }
    if (result.coordinates.length < 2) {
      _lastRerouteTime = DateTime.now();
      _lastRerouteFailed = true;
      return false;
    }
    // 2026-06-19 (vucko Gruppen-/Reroute-Video): Stale-Commit vor JEDEM
    // sichtbaren State-Update und vor Gruppen-Publish prüfen. Vorher wurde eine
    // Route, die beim Commit schon >80m neben dem Fahrer lag, kurz übernommen
    // und erst danach eine Ketten-Reroute angestoßen. Das erzeugte genau den
    // sichtbaren "Route/Puck versetzt"-Zustand aus den Testfahrten.
    final commitRouteMatch = findNearestInWindow(
      position: commitPos,
      coordinates: result.coordinates,
      currentIndex: 0,
      windowSize: math.min(160, result.coordinates.length),
      maxJumpMeters: double.infinity,
    );
    if (!allowStaleReanchor &&
        (!commitRouteMatch.distanceMeters.isFinite ||
            commitRouteMatch.distanceMeters >
                _rerouteCommitMaxRouteOffsetMeters)) {
      final offsetLabel = commitRouteMatch.distanceMeters.isFinite
          ? commitRouteMatch.distanceMeters.toStringAsFixed(0)
          : commitRouteMatch.distanceMeters.toString();
      _pendingChainedReroute = true;
      _lastRerouteTime = DateTime.now();
      _lastRerouteFailed = true;
      debugPrint(
        '[CruiseMode][Reroute] Stale-Commit verworfen: Fahrer '
        '${offsetLabel}m neben '
        'neuer Route (limit=${_rerouteCommitMaxRouteOffsetMeters.toStringAsFixed(0)}m)',
      );
      return false;
    }
    _pendingChainedReroute = false;
    _chainedRerouteCount = 0;
    final wasLeadingGroupVehicleBeforeCommit =
        publishToGroup && widget.groupId != null
        ? _isCurrentDeviceLeadingGroupRoute(commitPos)
        : true;
    if (publishToGroup &&
        widget.groupId != null &&
        !wasLeadingGroupVehicleBeforeCommit) {
      final groupId = widget.groupId!;
      final meId = Supabase.instance.client.auth.currentUser?.id;
      unawaited(_reloadGroupRouteFromBackfill(groupId, meId));
      _lastRerouteTime = DateTime.now();
      _lastRerouteFailed = true;
      return false;
    }
    if (publishToGroup && widget.groupId != null) {
      final published = await _publishGroupRouteIfAllowed(
        result,
        wasLeadingBeforeCommit: wasLeadingGroupVehicleBeforeCommit,
      );
      if (!published) {
        final groupId = widget.groupId!;
        final meId = Supabase.instance.client.auth.currentUser?.id;
        unawaited(_reloadGroupRouteFromBackfill(groupId, meId));
        _lastRerouteTime = DateTime.now();
        _lastRerouteFailed = true;
        return false;
      }
    }

    _lastRouteResult = result;
    _sessionRouteResult = sessionRouteResult ?? result;
    _activeSpeedLimits = result.speedLimits;
    _recentDestinationDistances = [];

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
    // Route >120 Grad GEGEN die aktuelle Fahrtrichtung, fährt der User von
    // ihr weg — die erste regulaere Instruktion ("rechts abbiegen") wäre
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
      final routeStartBearing = GeoBearing.bearingDegrees(
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
      // bright fällt auf die volle Route zurück (nie unsichtbar), dim wird
      // beim nächsten Tick sofort neu gesetzt (dimHead == null).
      _brightAheadLatLngs = const [];
      _dimRemainingLatLngs = const [];
      _lastDimHead = null;
      _currentRouteIndex = 0;
      _lastDrawnRouteIndex = 0;
      _distanceSinceLastRedraw = 0.0;
      _advanceCapRejects = 0;
      _lastRouteIndexAdvanceAt = null;
      _navigationController.clearManeuverDistanceSmoothing();
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
      // 2026-07-02 (vucko Geräte-Video): Voice-Vorankündigungs-State gehört
      // zur ALTEN Manöverliste — ohne Reset kollidiert der Index mit der neuen
      // Liste (Ansage verschluckt oder doppelt) und der Text-Cache nennt die
      // falsche Straße.
      _voicePreAnnouncedManeuverIndex = null;
      _voicePreAnnouncedText = null;
      _voiceStableManeuverIndex = null;
      _voiceManeuverStableSince = null;
      TtsService.instance.resetNavTag();
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
    final reanchor = commitRouteMatch;
    if (reanchor.distanceMeters <= _rerouteCommitMaxRouteOffsetMeters) {
      _currentRouteIndex = reanchor.index.clamp(
        0,
        math.max(0, result.coordinates.length - 1),
      );
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
      // Der Stale-Commit-Guard oben garantiert bereits, dass diese Geometrie
      // dicht genug am Fahrzeug liegt. Den Restkopf an die Commit-Position
      // heften verhindert, dass die rote Linie im ersten Frame hinter/neben dem
      // Puck startet.
      if (distanceToFirst <= _rerouteCommitMaxRouteOffsetMeters) {
        remaining[0] = [commitPos.longitude, commitPos.latitude];
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
    // Fingerprint bei Rundkurs-Reroute hätte sie sonst stehen lassen).
    // 2026-06-26 (vucko): Aufruf war seit 00cb464 in den Kommentar geschluckt
    // (Dead Code) — wieder als echte Anweisung. Sonst blieb die graue Vorschau-
    // linie nach gleich-langem Rundkurs-Reroute auf alter Geometrie stehen.
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
    // 2026-06-25 (vucko Süd-Offline): außerhalb DACH den Strecken-Korridor als
    // MapLibre-Offline-Region vorab cachen → Trip-/Single-Strecke offline.
    unawaited(
      MapStyleService.instance.downloadRouteOfflineRegion(result.coordinates),
    );
    return true;
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

  Future<void> _confirmRoute({bool preserveCurrentProgress = false}) async {
    if (_isLoading || _fullRouteCoordinates.isEmpty) return;
    setState(() {
      _isRouteConfirmed = true;
      if (!preserveCurrentProgress) {
        _currentRouteIndex = 0;
        _lastDrawnRouteIndex = 0;
        _remainingRouteCoordinates = _fullRouteCoordinates;
      } else {
        _lastDrawnRouteIndex = _currentRouteIndex;
        if (_remainingRouteCoordinates.isEmpty) {
          final startIndex = _currentRouteIndex
              .clamp(0, math.max(0, _fullRouteCoordinates.length - 1))
              .toInt();
          _remainingRouteCoordinates = _fullRouteCoordinates.sublist(
            startIndex,
          );
        }
      }
      _distanceSinceLastRedraw = 0.0;
      _showRouteInfoBanner = false;
      _configCollapsed = false;
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
      // 2026-06-25 (vucko): Trip außerhalb DACH — native MapLibre-Offline-Region
      // für den Strecken-Korridor (eu.pmtiles) laden, damit die Strecke beim
      // Fahren auch ohne Internet sichtbar bleibt. Gilt Single + Gruppe + Trip,
      // greift NUR wenn die Route DACH verlässt (drinnen deckt dach.pmtiles ab).
      unawaited(
        MapStyleService.instance.downloadRouteOfflineRegion(
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
          ? 'Navigation läuft, dein Standort bleibt für die Route aktiv.'
          : 'Navigation läuft, dein Standort wird mit der Gruppe geteilt.';
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
    // 2026-07-24 (vucko "Display ging während Navigation aus"): Bildschirm
    // bleibt an, solange navigiert wird — wie Google Maps. Fire-and-forget,
    // ein Wakelock-Fehler darf den Navigations-Start nie blockieren.
    // Gegenstück: _stopNavigationTracking() + dispose()-Sicherheitsnetz.
    unawaited(WakelockPlus.enable().catchError((Object e) {
      debugPrint('[CruiseMode] Wakelock enable fehlgeschlagen: $e');
    }));
    // 2026-07-25 (vucko „Mini-Bildschirm wenn man die App verlaesst"):
    // Android-PiP scharf stellen — verlaesst der Nutzer waehrend der Fahrt die
    // App, schrumpft die Navigation automatisch in ein kleines Fenster.
    // Auf iOS ein No-Op (dort deckt die Live Activity den Fall ab).
    unawaited(NavigationPipService.instance.arm());
    // 2026-07-24 (vucko "+-Button"): Live-Sync für Verkehrsmeldungen NUR
    // während aktiver Navigation (kein Dauer-Kanal außerhalb der Fahrt).
    // Änderung → debounced Refetch der Route-BBox.
    _incidentChannel ??= RoadIncidentService.instance.subscribeIncidents(() {
      _incidentRefetchDebounce?.cancel();
      _incidentRefetchDebounce = Timer(const Duration(seconds: 1), () {
        if (!mounted || _fullRouteCoordinates.length < 2) return;
        unawaited(_loadRoadIncidents(_fullRouteCoordinates));
      });
    });
    // 2026-06-23 (vucko GPS-Stall-Watchdog): unabhängig vom Standort-Stream.
    _lastLocationFixAt = DateTime.now();
    _gpsStallWatchdog?.cancel();
    _gpsStallWatchdog = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkGpsStall(),
    );
    _startConnectivityWatch();

    // Navigations-Startzeit setzen (nur beim ersten Start, nicht bei Resume)
    final startsNewDriveSession = _navigationStartTime == null;
    if (startsNewDriveSession) {
      _drivenTrackRecorder.reset();
      _totalDistanceDriven = 0.0;
      _maxSpeedMps = 0.0; // 2026-06-23 (vucko Top-Speed): pro Fahrt frisch.
      // 2026-06-15 (vucko N1): Lock-On frisch — bis der Puck eingerastet ist, gilt
      // die Kaltstart-Reroute-Sperre (kein Phantom am Fahrtbeginn).
      _onRouteLockStreak = 0;
      _routeLockedOn = false;
      // 2026-06-17 (vucko Kaltstart-Reroute): neue Sitzung → Kaltstart-Schnell-
      // schiene (1,4× Korridor) wieder scharf, bis zum ersten Einrasten.
      _everLockedOn = false;
      _advanceCapRejects = 0;
      _lastRouteIndexAdvanceAt = null;
      _lastPlausibleRawFix = null;
      _gpsJumpRejects = 0;
      _navigationController.clearManeuverDistanceSmoothing();
    }
    _navigationStartTime ??= DateTime.now();
    // 2026-07-06 (vucko Fahrt-Resume): Fahrtstart sofort persistieren, damit
    // die Strecke einen App-Kill überlebt (vorher lebte sie nur im RAM).
    _persistActiveRideSnapshot(force: true);
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

    // 2026-06-23 (vucko Post-Route Top-Speed): höchstes geglättetes Tempo merken.
    final smSpeed = _nativeSmoother.speed;
    if (smSpeed.isFinite && smSpeed > 0 && smSpeed < 100) {
      if (smSpeed > _maxSpeedMps) _maxSpeedMps = smSpeed;
    }

    _totalDistanceDriven = _drivenTrackRecorder.distanceMeters;
    // 2026-07-06 (vucko Fahrt-Resume): Fortschritt gedrosselt (max. alle 20s)
    // mitschreiben — nach App-Kill kennt der Resume-Snapshot so die bereits
    // gefahrenen Kilometer und die letzte Position.
    _persistActiveRideSnapshot(
      lat: position.latitude,
      lng: position.longitude,
    );
    if (result == DrivenTrackSampleResult.newSegment) {
      debugPrint(
        '[CruiseMode] GPS-Luecke erkannt, Track-Segment getrennt gespeichert.',
      );
    }
    // 2026-05-28 (vucko Task #66): Geofence-Check pro Driven-Track-Sample.
    // Sample-Frequenz ist ~1Hz während aktiver Fahrt — reicht für 200m
    // Trigger bei Geschwindigkeiten bis 200 km/h (= ~55 m/s).
    _processConstructionGeofence(position.latitude, position.longitude);
    // 2026-07-24 (vucko "+-Button"): Verkehrsmeldungs-Geofence + Stau-
    // Ausdehnungs-Tracking — gleiche O(n)-Kostenordnung wie die Baustellen.
    _processIncidentGeofence(position.latitude, position.longitude);
    _tickJamTracking(position);
    _pushLivePositionThrottled(position);
  }

  /// 2026-07-26 (vucko "darf nicht ausgenutzt werden koennen"): Die letzte
  /// bekannte Position ist serverseitig der BELEG dafür, dass eine Meldung
  /// wirklich von vor Ort kommt — ohne sie akzeptiert der Server nur eine
  /// kurzlebige, ungeprüfte Meldung. Bewusst nur während laufender Navigation
  /// und gedrosselt; beim Fahrtende wird sie wieder gelöscht (Vuckos Vorgabe:
  /// keine Standortdaten außerhalb der Fahrt aufbewahren).
  void _pushLivePositionThrottled(geo.Position position) {
    final now = DateTime.now();
    final last = _lastLivePositionPushAt;
    if (last != null && now.difference(last) < const Duration(seconds: 60)) {
      return;
    }
    _lastLivePositionPushAt = now;
    unawaited(
      RoadIncidentService.instance
          .pushLivePosition(position.latitude, position.longitude),
    );
  }

  void _stopNavigationTracking() {
    // Standort-Beleg wieder entfernen — er gilt nur für die laufende Fahrt.
    _lastLivePositionPushAt = null;
    unawaited(RoadIncidentService.instance.clearLivePosition());
    // 2026-07-24 (vucko Wakelock): Display-Sperre wieder freigeben — dieser
    // Funnel deckt ALLE Stop-Pfade ab (Pause, Beenden, Lobby-Rückkehr,
    // Setup-Rückkehr, Ankunft, Simulation, Post-Ride-Cleanup).
    unawaited(WakelockPlus.disable().catchError((Object e) {
      debugPrint('[CruiseMode] Wakelock disable fehlgeschlagen: $e');
    }));
    unawaited(NavigationPipService.instance.disarm());
    // 2026-07-24 (vucko "+-Button"): Incident-Realtime-Kanal schließen.
    _incidentRefetchDebounce?.cancel();
    _incidentRefetchDebounce = null;
    _incidentChannel?.unsubscribe();
    _incidentChannel = null;
    // 2026-07-25 (Review-Fund): Stau-Tracking hier VERWERFEN, nicht
    // abschließen. Wer mitten im Stau die Fahrt beendet, weiß nicht wo der
    // Stau endet — ein Ende zu schreiben wäre gelogen. Ohne diesen Reset
    // hing die ID bis zur NÄCHSTEN Fahrt und deren erste freie Strecke
    // wurde als Stau-Ende der alten Meldung gespeichert.
    _jamTrackingIncidentId = null;
    _jamTrackingStartedAt = null;
    _jamRecoverySince = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _socketPositionSubscription?.cancel();
    _socketPositionSubscription = null;
    _gpsStallWatchdog?.cancel();
    _gpsStallWatchdog = null;
    _gpsWeak = false;
    _stopConnectivityWatch();
    unawaited(_navigationSocketService.close());
    _endNavigationLiveActivity();
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

    // 2026-06-23 (vucko GPS-Stall-Watchdog): frischer Fix → Stempel + Tempo
    // merken (für „fährt vs. steht"). Sobald wieder Fixes fließen, ist die GPS-
    // Lücke vorbei → Hinweis weg + Glide-Tracker zurücksetzen (der nächste
    // reguläre Render-Pfad übernimmt; der Render-Lock-Glide war monoton, springt
    // also nicht zurück).
    _lastLocationFixAt = DateTime.now();
    // 2026-07-22 (vucko „GPS veraltet"-Fehlmeldung): Tempo-Lesung ist nach unten
    // zum Smoother-Update gewandert. Vorher wurde hier (a) eine ECHTE 0.0 vom OS
    // (regulärer Stillstands-Wert, kein Fehler!) als „ungültig" verworfen und
    // (b) stattdessen der noch NICHT mit diesem Fix aktualisierte Smoother
    // gelesen — der zeigte beim Anhalten noch 4-8 m/s Restmoment. Ergebnis:
    // „fährt" im Moment des Ampel-Stopps → kurze GPS-Lücke = falsche Warnung.
    _lastStallGlideAt = null;
    if (_gpsWeak) {
      _gpsWeak = false;
      _safeSetState(() {});
    }

    // 2026-06-17 (vucko Geräte-Video: Standort teleportiert + grundloses Reroute):
    // GPS-AUSREISSER-GATE. Physikalisch unmögliche Sprünge (Stadt/Schlucht-
    // Multipath: Accuracy ok, Position springt 50–150 m weg) trieben bisher 1:1
    // die Routen-Logik UND (über den Smoother) den Puck → sichtbarer Teleport +
    // „Neuberechnung", obwohl der Fahrer exakt auf der Linie fuhr (im 22-Agenten-
    // Video-Audit in JEDEM Navigations-Frame on-route bestätigt; ein Reroute kann
    // nur feuern, wenn die ROHE Position > Korridor von der GANZEN Route liegt =
    // genau so ein Ausreißer). Apple/Google verwerfen solche Fixes. Wir halten den
    // letzten guten Stand — der Puck gleitet per Dead-Reckoning (Smoother-predict)
    // + Kamera weiter. Höchstens _maxGpsJumpRejects Fixes am Stück verwerfen
    // (fail-open), damit ein ECHTER anhaltender Sprung (Tunnelausfahrt) nicht
    // einfriert. Die echte Off-Route-/Reroute-Logik bleibt 1:1 — ein Verfahren ist
    // immer mit realem Tempo erreichbar, wird also NIE gefiltert.
    final lastPlausible = _lastPlausibleRawFix;
    if (lastPlausible != null) {
      final jumpMeters = geo.Geolocator.distanceBetween(
        lastPlausible.latitude,
        lastPlausible.longitude,
        position.latitude,
        position.longitude,
      );
      final dtSeconds =
          position.timestamp
              .difference(lastPlausible.timestamp)
              .inMilliseconds /
          1000.0;
      final plausibleSpeed = math.max(
        math.max(
          position.speed.isFinite && position.speed > 0 ? position.speed : 0.0,
          lastPlausible.speed.isFinite && lastPlausible.speed > 0
              ? lastPlausible.speed
              : 0.0,
        ),
        _nativeSmoother.speed.isFinite ? _nativeSmoother.speed : 0.0,
      );
      final accuracySlack =
          (position.accuracy.isFinite && position.accuracy > 0
              ? position.accuracy
              : 0.0) +
          (lastPlausible.accuracy.isFinite && lastPlausible.accuracy > 0
              ? lastPlausible.accuracy
              : 0.0);
      if (isImplausibleGpsJump(
            jumpMeters: jumpMeters,
            dtSeconds: dtSeconds,
            plausibleSpeedMps: plausibleSpeed,
            accuracySlackMeters: accuracySlack,
          ) &&
          _gpsJumpRejects < _maxGpsJumpRejects) {
        _gpsJumpRejects++;
        if (kDebugMode) {
          debugPrint(
            '[gps-jump] Ausreißer verworfen #$_gpsJumpRejects: '
            'sprung=${jumpMeters.toStringAsFixed(0)}m '
            'dt=${dtSeconds.toStringAsFixed(1)}s '
            'acc=${position.accuracy.toStringAsFixed(0)}m',
          );
        }
        return; // Roh-Ausreißer ignorieren: Puck/Kamera laufen per Dead-Reckoning
      }
    }
    _gpsJumpRejects = 0;
    _lastPlausibleRawFix = position;

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

    // 2026-07-22 (vucko „GPS veraltet"-Fehlmeldung): Tempo für „fährt vs. steht"
    // ERST NACH dem Smoother-Update lesen. position.speed >= 0 akzeptiert die
    // reguläre Stillstands-0.0; nur bei wirklich ungültigen Werten (NaN/negativ)
    // greift der Smoother-Fallback — der jetzt garantiert den AKTUELLEN Fix
    // eingerechnet hat statt des Restmoments vom vorherigen Tick.
    final fixSpeed = position.speed.isFinite && position.speed >= 0
        ? position.speed
        : _nativeSmoother.speed;
    _gpsLastFixSpeedMps = fixSpeed.isFinite && fixSpeed > 0 ? fixSpeed : 0.0;

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

    // 2026-06-13 (vucko Free-Cam-Ruckeln): Render-Ticker läuft in JEDEM
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
    // 2026-06-13 (vucko Geräte-Video „Reroute greift nicht nahe Ziel"):
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
    // der GPS-KURS zur Route passt. Beim überfahrenen Abbiege-Manöver oder
    // auf der Parallelstrasse kriecht der Match-Index naemlich WEITER vorwaerts
    // (die Projektion wandert mit) — das alte Veto blockierte den Reroute
    // damit minutenlang ("0 m"-Banner-Freeze im Geräte-Video).
    var makingForwardProgress =
        match.index > prevRouteIndex &&
        _gpsHeadingAlignedWithRoute(position, match);

    // 2026-06-12 (vucko): Manöver-UEBERFAHREN-Trigger. War der Fahrer schon
    // <35m am aktiven Manöver und entfernt sich wieder >60m davon, ist das
    // Manöver verpasst — Off-Route-Verfahren sofort starten, auch wenn die
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
    // 2026-06-13 (vucko Geräte-Video): Re-Snap läuft jetzt AUCH nahe dem Ziel
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
        final globalDecision = _routeProgressDecision(globalMatch, position);
        final globalIsForwardOrCurrent =
            globalDecision.matchDist + 1.0 >= globalDecision.currentDist;
        final canCommitGlobalProgress =
            globalDecision.plausible &&
            globalIsForwardOrCurrent &&
            globalDecision.stableIndex >= _currentRouteIndex;
        if (canCommitGlobalProgress) {
          _currentRouteIndex = globalDecision.stableIndex;
          _lastRouteIndexAdvanceAt = position.timestamp;
          routeProgressMatch = globalMatch;
        } else {
          routeProgressMatch = RouteWindowMatch(
            index: _currentRouteIndex,
            distanceMeters: globalMatch.distanceMeters,
          );
          _advanceCapRejects++;
          _debugRejectedRouteAdvance(
            'global-re-snap',
            globalDecision,
            position,
          );
        }
        isOutsideCorridor =
            false; // doch auf der Route — nur Fenster nachgehinkt
        // 2026-06-14 (vucko Re-Dock-Trim, Geräte-Screenshot „Strecke vor UND
        // hinter mir"): Beim Wieder-Andocken nach kurzer Abweichung rueckte der
        // Re-Snap zwar _currentRouteIndex vor, aber der Render-Lock (= Quelle
        // des Linien-Schnitts UND des Pucks) ist monoton und blieb hinter der
        // echten Position eingefroren → das 3km-Bright-Fenster startete hinter
        // dem Puck, der abgefahrene Teil blieb rot. Jetzt: Lock explizit auf den
        // re-gesnappten Index ankern + Trim-Push-Caches leeren, damit der
        // Schnitt diesen Tick neu vom echten Puck aus aufgebaut wird. Nur bei
        // echtem Versatz (>20m) — Mini-Jitter bleibt auf dem monotonen Glide.
        if (canCommitGlobalProgress &&
            _reanchorRenderLockToDistance(globalDecision.matchDist)) {
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

    // Manöver-Overshoot zählt wie "klar daneben" — aber NUR im breiten
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
      if (_onRouteLockStreak >= _lockOnStreakNeeded) {
        _routeLockedOn = true;
        _everLockedOn = true;
      }
    } else if (isOutsideCorridor) {
      _onRouteLockStreak = 0;
    }
    // Harte Decke: nach _lockOnGraceCeiling gilt der Puck als eingerastet, selbst
    // wenn das GPS nie sauber ≤35m wurde — sonst bliebe ein echtes Verfahren in
    // dauerhaft mäßiger GPS-Lage ewig gesperrt.
    if (!_routeLockedOn &&
        _navigationStartTime != null &&
        DateTime.now().difference(_navigationStartTime!) >
            _lockOnGraceCeiling &&
        (_postRerouteGraceUntil == null ||
            DateTime.now().isAfter(_postRerouteGraceUntil!))) {
      // 2026-06-16 (vucko O4): Die 90s-Grace-Decke darf NICHT mitten in der
      // Post-Reroute-Grace force-locken — sonst wäre der Lock-Reset oben sofort
      // wieder aufgehoben und die Kaskade bliebe. Während der 6s-Grace gilt die
      // strenge Divergenz-Schwelle (rerouteVoteAllowed, lockedOn=false).
      _routeLockedOn = true;
      _everLockedOn = true;
    }
    // Mapbox-/Apple-Gating (siehe rerouteVoteAllowed): unqualifizierter Fix bzw.
    // Kaltstart-Rauschen vor dem Einrasten darf KEIN Reroute auslösen.
    final rerouteMayVote = rerouteVoteAllowed(
      accuracyMeters: accuracyM,
      routeLockedOn: _routeLockedOn,
      everLockedOn: _everLockedOn,
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

    // 2026-06-23 (vucko 2-Geräte-Gruppen-Video, C2): Sobald ein Gruppen-Gerät
    // off-route ist, sofort (debounced) die Leader-Route per Backfill ziehen —
    // egal ob es gleich deferred (Leader führt zurück) ODER selbst rerouted.
    // Ein nicht-führender Follower bekommt so die frische Rest-km/ETA schneller
    // als über die reine 5-s-Periodik. Leader/solo: No-Op (siehe Helper-Guard).
    if (isOutsideCorridor && widget.groupId != null) {
      _maybePullFollowerGroupRouteBackfill(position);
    }

    if (isOutsideCorridor &&
        !approachingDestination &&
        !nearRouteEnd &&
        !makingForwardProgress &&
        rerouteMayVote &&
        // 2026-06-21 (vucko Feldkirch-Gruppen-Reroute-Hang): Ein NICHT-führender
        // Gruppen-Follower reroutet NICHT selbst — er folgt der geteilten Leader-
        // Route zurück (G4). Sonst fighten lokale Reroutes die Leader-Updates →
        // 38s-„Neuberechnung"-Churn. Sicher per Konstruktion (solo/Leader/allein
        // unverändert). Off-Route wird dann wie „im Korridor" behandelt (else).
        !_groupFollowerShouldDeferReroute(position)) {
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
    _ensureRouteMetrics();
    final advanceDecision = _routeProgressDecision(match, position);
    final stableMatchIndex = advanceDecision.stableIndex;
    if (stableMatchIndex > _currentRouteIndex &&
        stableMatchIndex - _currentRouteIndex <= 60 &&
        match.distanceMeters <= offRouteCorridor) {
      // 2026-06-18 (vucko Standort-Teleport): Den Fortschritt nicht mehr nach N
      // Rejects erzwingen. Das erlaubte Meterbudget wächst mit echter Zeit seit dem
      // letzten akzeptierten Index. Dadurch bleibt sparse Geometrie beweglich, aber
      // ein Zukunfts-Leg kann den Puck nicht 100-300 m vorziehen und dort warten
      // lassen, bis das Auto real aufschließt.
      if (advanceDecision.plausible) {
        _advanceCapRejects = 0;
        final committedAdvanceMeters = math.max(
          0.0,
          _routeCumDist[stableMatchIndex] - advanceDecision.currentDist,
        );
        _distanceSinceLastRedraw += committedAdvanceMeters;
        _currentRouteIndex = stableMatchIndex;
        _lastRouteIndexAdvanceAt = position.timestamp;
        needsRebuild = true;
        _maybeFinalizeAccessLegPhase();
        // 2026-06-09 (vucko Voll-Route-Sichtbar): KEIN 3km-Sliding-Window-Redraw
        // der sichtbaren Linie mehr. Die rote aktive Linie ist die VOLLE Route
        // (statisch, einmal gepusht → kann NIE flackern); _trimVisibleRouteToProjection
        // pflegt den grauen Driven-Trail + _remainingRouteCoordinates.
      } else {
        _advanceCapRejects++;
        _debugRejectedRouteAdvance('route-advance', advanceDecision, position);
      }
    } else {
      // Kein Vorwärts-Match (Puck nicht vor dem Index) → Reject-Zähler nullen,
      // damit sich kein veralteter Stand zu einem späteren Fehl-Force summiert.
      _advanceCapRejects = 0;
      _lastRouteIndexAdvanceAt ??= position.timestamp;
    }

    // 2026-06-23 (vucko 2-Geräte-Video „Banner+Rest-km frieren nach verpasstem
    // Turn ~85s ein"): Frozen-Progress-Watchdog. Die Render-Lock-Distanz gleitet
    // normal mit dem Puck (auch mitten auf langen Segmenten) — friert sie TROTZ
    // klarer Fahrt zu lange ein, klebt der Map-Matcher am verpassten Manöver und
    // der Off-Route-Detektor feuert (noch) nicht (Puck geometrisch nah). Dann EIN
    // Reroute erzwingen (re-ankert Banner+Linie+Rest-km; V1 committet garantiert).
    final renderDistNow = _renderLockDistM;
    if (_lastRenderDistForFreeze == null ||
        (renderDistNow - _lastRenderDistForFreeze!).abs() > 5.0) {
      _lastRenderDistForFreeze = renderDistNow;
      _renderDistChangedAt = position.timestamp;
    }
    final frozenFor = _renderDistChangedAt == null
        ? Duration.zero
        : position.timestamp.difference(_renderDistChangedAt!);
    final watchdogSpeedMps = math.max(
      position.speed.isFinite && position.speed > 0 ? position.speed : 0.0,
      _nativeSmoother.speed.isFinite && _nativeSmoother.speed > 0
          ? _nativeSmoother.speed
          : 0.0,
    );
    if (!_isRerouting &&
        _isRouteConfirmed &&
        shouldForceRerouteOnFrozenProgress(
          sinceProgressChanged: frozenFor,
          speedMps: watchdogSpeedMps,
          approachingDestination: approachingDestination,
          nearRouteEnd: nearRouteEnd,
        ) &&
        (_lastRerouteTime == null ||
            position.timestamp.difference(_lastRerouteTime!) >
                _rerouteFailureCooldown) &&
        !_groupFollowerShouldDeferReroute(position)) {
      debugPrint(
        '[CruiseMode] Frozen-Progress-Watchdog: Fortschritt '
        '${frozenFor.inSeconds}s eingefroren bei '
        '${watchdogSpeedMps.toStringAsFixed(0)}m/s → Reroute erzwungen',
      );
      _renderDistChangedAt = position.timestamp; // Anti-Spam
      _lastRenderDistForFreeze = renderDistNow;
      _lastRerouteTime = position.timestamp;
      _offRouteSince = null;
      unawaited(_rerouteToOriginalRoute(position));
      return;
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

    // Prüfe ob Route zu Ende ist.
    // 2026-06-25 (vucko): Der Auto-Abschluss (Post-Route-Screen) darf NICHT mehr
    // ausschließlich am Map-Matcher-Index hängen. Direkt am Ziel kann der Matcher
    // den Index ein paar Punkte vor dem letzten Routenpunkt „stehen lassen"
    // (kurzes Schluss-Segment / konservativer Match) → die Ankunft (≤Radius)
    // wurde dann NIE als Abschluss erkannt = Sheet kam nicht (gemeldete
    // Regression). Jetzt feuert der Abschluss, sobald man im Ankunftsradius ist
    // UND entweder der Index am Ende ist ODER der Großteil der geplanten Strecke
    // gefahren wurde. `_canCompleteNavigationAtCurrentPosition` (→
    // shouldCompleteNavigation) bleibt der eigentliche Wächter: A→B nur ≤Radius,
    // Rundkurs erst ab ≥95% gefahren → kein verfrühter Abschluss.
    final lastIndex = _fullRouteCoordinates.length - 1;
    final distanceToTarget =
        _updateDistanceToFinalTarget(position) ?? double.infinity;
    final plannedForArrival =
        _completionRouteResult?.distanceMeters ?? _originalRouteDistance;
    final drivenMostOfRoute =
        plannedForArrival != null &&
        plannedForArrival > 0 &&
        _totalDistanceDriven >= plannedForArrival * 0.80;
    final arrivedAtRouteEnd =
        _currentRouteIndex >= lastIndex - 1 || drivenMostOfRoute;
    if (arrivedAtRouteEnd &&
        distanceToTarget <= _arrivalRadiusMeters &&
        _canCompleteNavigationAtCurrentPosition(position)) {
      _stopNavigationTracking();
      _stopSimulation(restartLiveTracking: false);
      _onRouteCompleted();
      return;
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
    final visibleManeuver = _activeVisibleManeuver();
    final distToManeuver = _displayManeuverDistanceMeters(visibleManeuver);
    if (visibleManeuverIndex != null && distToManeuver != null) {
      // Reset state wenn neues Manöver
      if (_lastHapticManeuverIndex != visibleManeuverIndex) {
        _lastHapticManeuverIndex = visibleManeuverIndex;
        _hapticStage300m = false;
        _hapticStage150m = false;
        _hapticStage50m = false;
        // 2026-07-02 (vucko Geräte-Video): eine noch laufende/gequeue-te
        // Ansage des VORHERIGEN Manövers sofort stoppen — sonst spielt sie
        // verspätet ab, während das Banner längst das nächste Manöver zeigt
        // („rechts abbiegen" hörbar, Kreisverkehr sichtbar).
        unawaited(TtsService.instance.stopIfStaleFor(visibleManeuverIndex));
        _voicePreAnnouncedText = null;
      }
      // Stabilitäts-Tracking für die Vorankündigung (siehe Felddeklaration).
      if (_voiceStableManeuverIndex != visibleManeuverIndex) {
        _voiceStableManeuverIndex = visibleManeuverIndex;
        _voiceManeuverStableSince = DateTime.now();
      }
      // 2026-06-11 (vucko 1Hz-GPS-Fix): Stufen KASKADIEREND ohne Band-
      // Untergrenze. Die alten Baender ((150,300], (50,150]) waren unter dem
      // 20-Hz-Sim nicht überspringbar — echtes GPS mit 3-5s-Fix-Luecke
      // (Tunnel/Empfangsloch) sprang bei Landstrassentempo über ein ganzes
      // Band, und die EINZIGE Voice-Vorankuendigung (300m) entfiel. Jetzt
      // feuert immer die hoechste noch offene Stufe <= aktueller Distanz;
      // tiefere Stufen markieren die höheren als verbraucht.
      // 2026-06-22 (vucko Geräte-Video „Autobahn-Ausfahrt zu spät"): Voice-
      // Vorankündigung GESCHWINDIGKEITSABHÄNGIG vorziehen — bei Autobahntempo
      // ~780 m statt fix 300 m (sonst kam „in 200 m raus" erst auf der Rampe).
      // Genau 1× pro Manöver; Distanz im Text macht es ehrlich („In 800 Metern…").
      final preAnnounceDist = maneuverPreAnnounceDistanceMeters(
        _nativeSmoother.speed,
      );
      // 2026-07-02 (vucko Geräte-Video): erst ansagen, wenn der Index ≥1,2 s
      // stabil ist — beim Start-Snap überrollte Manöver bekommen so KEINE
      // eigene Ansage mehr (das war der „5 Ansagen nach Start"-Stau).
      final maneuverStableMs = _voiceManeuverStableSince == null
          ? 0
          : DateTime.now().difference(_voiceManeuverStableSince!).inMilliseconds;
      if (_voicePreAnnouncedManeuverIndex != visibleManeuverIndex &&
          distToManeuver <= preAnnounceDist &&
          distToManeuver > 60 &&
          maneuverStableMs >= 1200) {
        _voicePreAnnouncedManeuverIndex = visibleManeuverIndex;
        _speakManeuverAnnouncement(distToManeuver.round(), important: true);
      }
      // 300m → lightImpact (Haptik bleibt fix; die Voice kommt jetzt früher).
      if (!_hapticStage300m && distToManeuver <= 300 && distToManeuver > 50) {
        HapticFeedback.lightImpact();
        _hapticStage300m = true;
        // Erstkontakt schon <=150m (Fix-Luecke): 150er-Haptik gilt als
        // mitverbraucht — sonst feuern light+medium im selben Tick doppelt.
        if (distToManeuver <= 150) _hapticStage150m = true;
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

    _updateNavigationLiveActivity();
    if (needsRebuild) _safeSetState(() {});
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
      // 2026-07-27: Da _applyRouteResult die alte Liste bewusst stehen lässt,
      // muss der Fehlerfall hier aufräumen — sonst blieben POIs der VORIGEN
      // Route dauerhaft auf der neuen Strecke liegen.
      if (mounted) setState(() => _routePois = const []);
    }
  }

  // ── 2026-06-25 (vucko Marker-Swim): native POI/Baustellen-Symbole ──────────
  // POIs + Baustellen werden als NATIVE MapLibre-Symbol-Layer gerendert (GPU,
  // im selben Frame wie die Karte) statt als Flutter-Overlay → kein „Schwimmen"
  // beim Pannen. Die Icons (farbiger Kreis + Ring + Glyph) werden EINMAL pro
  // Variante in eine PNG gerastert und via addImage registriert.

  static const String _constructionIconKey = 'cons';

  // 2026-07-24 (vucko "+-Button"): eigene Icon-Keys pro Meldungs-Typ, damit
  // jeder Typ seine Farbe/Glyph behält (rot Unfall, orange Baustelle,
  // gelb Stau).
  String _incidentIconKey(RoadIncidentType type) => 'inc_${type.name}';

  String _poiIconKey(RoutePoi poi) {
    final soon = OpeningHoursParser.parse(poi.openingHours).isClosingSoon;
    return 'poi_${poi.type.name}${soon ? '_soon' : ''}';
  }

  Color _poiColorFor(PoiType type) => switch (type) {
    PoiType.fuel => const Color(0xFFEF4444),
    PoiType.restaurant => const Color(0xFFFB923C),
    PoiType.cafe => const Color(0xFFA78BFA),
    PoiType.fastFood => const Color(0xFFFBBF24),
    PoiType.pub => const Color(0xFF22C55E),
    PoiType.motorcycleRepair => const Color(0xFF2DD4BF),
    PoiType.parking => const Color(0xFF60A5FA),
    PoiType.toilets => const Color(0xFF9CA3AF),
  };

  IconData _poiIconDataFor(PoiType type) => switch (type) {
    PoiType.fuel => Icons.local_gas_station_rounded,
    PoiType.restaurant => Icons.restaurant_rounded,
    PoiType.cafe => Icons.local_cafe_rounded,
    PoiType.fastFood => Icons.fastfood_rounded,
    PoiType.pub => Icons.sports_bar_rounded,
    PoiType.motorcycleRepair => Icons.build_rounded,
    PoiType.parking => Icons.local_parking_rounded,
    PoiType.toilets => Icons.wc_rounded,
  };

  Set<String> _neededPoiIconKeys() {
    final keys = <String>{};
    for (final poi in _routePois) {
      keys.add(_poiIconKey(poi));
    }
    if (_routeConstructions.isNotEmpty) keys.add(_constructionIconKey);
    for (final incident in _routeIncidents) {
      keys.add(_incidentIconKey(incident.type));
    }
    return keys;
  }

  /// Rastert fehlende Icon-Varianten (self-healing, intern geguarded). Wird aus
  /// build() angestoßen → deckt ALLE POI-Lade-Pfade ab. setState nur, wenn neue
  /// Bilder fertig sind (kein Build-Loop, da _poiIconImages danach gefüllt ist).
  void _ensurePoiIcons() {
    if (_poiIconRasterInFlight || kIsWeb) return;
    final needed = _neededPoiIconKeys();
    final missing = needed
        .where((k) => !_poiIconImages.containsKey(k))
        .toList();
    if (missing.isEmpty) return;
    _poiIconRasterInFlight = true;
    () async {
      final fresh = <String, Uint8List>{};
      for (final key in missing) {
        try {
          fresh[key] = await _rasterizePoiIcon(key);
        } catch (_) {}
      }
      if (!mounted) {
        _poiIconRasterInFlight = false;
        return;
      }
      _poiIconRasterInFlight = false;
      if (fresh.isNotEmpty) {
        setState(() => _poiIconImages.addAll(fresh));
      }
    }();
  }

  Future<Uint8List> _rasterizePoiIcon(String key) {
    if (key == _constructionIconKey) {
      return _rasterizeCircleIcon(
        fill: Colors.white,
        ring: const Color(0xFFFF9500),
        ringWidth: 2.2,
        icon: Icons.construction_rounded,
        glyphColor: const Color(0xFFFF9500),
        logicalDiameter: 38,
        glyphSize: 18,
      );
    }
    // 2026-07-24 (vucko "+-Button"): Verkehrsmeldungs-Icons — gleiche
    // Kreis-Optik wie die Baustellen, Farbe/Glyph pro Typ.
    if (key.startsWith('inc_')) {
      final type = RoadIncidentType.values.firstWhere(
        (t) => t.name == key.substring('inc_'.length),
        orElse: () => RoadIncidentType.stau,
      );
      return _rasterizeCircleIcon(
        fill: Colors.white,
        ring: type.color,
        ringWidth: 2.2,
        icon: type.icon,
        glyphColor: type.color,
        logicalDiameter: 38,
        glyphSize: 18,
      );
    }
    final soon = key.endsWith('_soon');
    final typeName = key.substring(
      'poi_'.length,
      key.length - (soon ? '_soon'.length : 0),
    );
    final type = PoiType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => PoiType.fuel,
    );
    return _rasterizeCircleIcon(
      fill: _poiColorFor(type),
      ring: soon ? const Color(0xFFFB923C) : Colors.white,
      ringWidth: soon ? 2.8 : 2.2,
      icon: _poiIconDataFor(type),
      glyphColor: Colors.white,
      logicalDiameter: 34,
      glyphSize: 16,
    );
  }

  /// Zeichnet einen farbigen Kreis + Ring + zentriertes Material-Glyph in eine
  /// PNG (3× Auflösung → scharf; der Symbol-Layer skaliert mit iconSize 1/3).
  Future<Uint8List> _rasterizeCircleIcon({
    required Color fill,
    required Color ring,
    required double ringWidth,
    required IconData icon,
    required Color glyphColor,
    required double logicalDiameter,
    required double glyphSize,
  }) async {
    const double scale = 3.0;
    final double px = logicalDiameter * scale;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final Offset center = Offset(px / 2, px / 2);
    final double r = px / 2 - (ringWidth * scale);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = fill
        ..isAntiAlias = true,
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth * scale
        ..color = ring
        ..isAntiAlias = true,
    );
    final tp = TextPainter(
      textDirection: ui.TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: glyphSize * scale,
          color: glyphColor,
          height: 1.0,
        ),
      ),
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    final ui.Image img = await recorder.endRecording().toImage(
      px.round(),
      px.round(),
    );
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return bd!.buffer.asUint8List();
  }

  /// GeoJSON-Point-Features für POIs + Baustellen (top-level `id` = Tap-Matching,
  /// Property `icon` = registriertes Bild). Nur Features mit bereits gerastertem
  /// Icon → nie eine fehlende Bild-Referenz im Layer.
  List<Map<String, dynamic>> _buildPoiFeatures() {
    // 2026-07-25 (Review-Fund): _routeIncidents MUSS hier mit rein — sonst
    // liefert der Early-Return eine leere Liste, sobald eine Route weder POIs
    // noch Baustellen hat, und Verkehrsmeldungen erscheinen auf der NATIVEN
    // Karte nie (der Normalfall bei ausgeschaltetem POI-Filter).
    if (_routePois.isEmpty &&
        _routeConstructions.isEmpty &&
        _routeIncidents.isEmpty) {
      return const [];
    }
    final features = <Map<String, dynamic>>[];
    for (final poi in _routePois) {
      final key = _poiIconKey(poi);
      if (!_poiIconImages.containsKey(key)) continue;
      features.add({
        'type': 'Feature',
        'id': 'poi-${poi.latitude},${poi.longitude}',
        'properties': {'icon': key},
        'geometry': {
          'type': 'Point',
          'coordinates': [poi.longitude, poi.latitude],
        },
      });
    }
    if (_poiIconImages.containsKey(_constructionIconKey)) {
      for (final c in _routeConstructions) {
        features.add({
          'type': 'Feature',
          'id': 'cons-${c.latitude},${c.longitude}',
          'properties': {'icon': _constructionIconKey},
          'geometry': {
            'type': 'Point',
            'coordinates': [c.longitude, c.latitude],
          },
        });
      }
    }
    // 2026-07-24 (vucko "+-Button"): Verkehrsmeldungen im selben nativen
    // Symbol-Layer — nur mit bereits gerastertem Icon (nie eine fehlende
    // Bild-Referenz im Layer, gleiche Regel wie POIs/Baustellen oben).
    for (final incident in _routeIncidents) {
      final key = _incidentIconKey(incident.type);
      if (!_poiIconImages.containsKey(key)) continue;
      features.add({
        'type': 'Feature',
        'id': 'inc-${incident.id}',
        'properties': {'icon': key},
        'geometry': {
          'type': 'Point',
          'coordinates': [incident.longitude, incident.latitude],
        },
      });
    }
    return features;
  }

  /// Tap auf ein natives POI/Baustellen-Symbol → passendes Sheet (id-Matching
  /// wie die früheren Overlay-Marker-IDs).
  void _onPoiSymbolTapped(String id) {
    if (id.startsWith('poi-')) {
      for (final poi in _routePois) {
        if ('poi-${poi.latitude},${poi.longitude}' == id) {
          _showPoiInfoCard(poi);
          return;
        }
      }
    } else if (id.startsWith('cons-')) {
      for (final c in _routeConstructions) {
        if ('cons-${c.latitude},${c.longitude}' == id) {
          ConstructionAlertSheet.show(context, c);
          return;
        }
      }
    } else if (id.startsWith('inc-')) {
      for (final incident in _routeIncidents) {
        if ('inc-${incident.id}' == id) {
          IncidentAlertSheet.show(context, incident);
          return;
        }
      }
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
            '${poi.type.label} liegt ${(minDistMeters / 1000).toStringAsFixed(1)} km abseits, bitte als neuen Stopp planen.',
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
        message: 'Route konnte nicht angepasst werden, versuch es nochmal.',
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
      message: '${poi.type.label} entfernt, Route wird neu berechnet…',
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
          '⛽ Tankstellen erscheinen automatisch auf der Karte, Filter in den Einstellungen',
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
      // 2026-07-24 (vucko "+-Button"): Crowd-Verkehrsmeldungen (Unfall/
      // Baustelle/Stau) für die Route laden — gleiche Kette wie Baustellen.
      unawaited(_loadRoadIncidents(coords));
    } catch (_) {
      // silent fail
    }
  }

  /// 2026-07-24 (vucko "+-Button"): Crowd-Meldungen (road_incidents) für die
  /// Route laden — Muster wie _loadConstructionReports. Wird zusätzlich vom
  /// Realtime-Kanal (debounced) erneut angestoßen, wenn andere Fahrer melden.
  Future<void> _loadRoadIncidents(List<List<double>> coords) async {
    if (coords.length < 2) return;
    try {
      double minLat = coords.first[1], maxLat = coords.first[1];
      double minLng = coords.first[0], maxLng = coords.first[0];
      for (final c in coords) {
        if (c[1] < minLat) minLat = c[1];
        if (c[1] > maxLat) maxLat = c[1];
        if (c[0] < minLng) minLng = c[0];
        if (c[0] > maxLng) maxLng = c[0];
      }
      final incidents = await RoadIncidentService.instance.fetchInBbox(
        southLat: minLat - 0.018,
        westLng: minLng - 0.018,
        northLat: maxLat + 0.018,
        eastLng: maxLng + 0.018,
      );
      if (!mounted) return;
      final onRoute = RoadIncidentService.instance.filterToRoute(
        incidents: incidents,
        routeCoordinates: coords,
        bufferMeters: 200,
      );
      setState(() {
        _routeIncidents = onRoute;
      });
      // Eigene Meldungen NICHT in den Geofence — der Melder steht direkt an
      // der Position und würde sonst sofort sein eigenes "Noch da?" sehen.
      final uid = Supabase.instance.client.auth.currentUser?.id;
      _incidentGeofence.setIncidents(
        onRoute.where((i) => i.reportedBy != uid).toList(),
      );
      debugPrint(
        '[CruiseMode] Verkehrsmeldungen geladen: ${incidents.length} bbox, '
        '${onRoute.length} auf Route.',
      );
    } catch (e) {
      debugPrint('[CruiseMode] Incident-Load fehlgeschlagen: $e');
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

  /// 2026-07-24 (vucko "+-Button"): Marker-Widget für Verkehrsmeldungen
  /// (Web-Fallback; nativ läuft es über den Symbol-Layer).
  Widget _buildIncidentMarker(RoadIncident incident) {
    final accent = incident.type.color;
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
      child: Icon(incident.type.icon, size: 18, color: accent),
    );
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
    // 2026-07-25 (Review-Fund): auch das Verkehrsmeldungs-Sheet blockt hier —
    // sonst konnten sich zwei Bottom-Sheets stapeln (die Gegenrichtung war
    // schon geguarded, diese nicht).
    if (_activeIncidentAlertId != null) return;
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

  /// 2026-07-24 (vucko "+-Button"): Geofence-Tick für Verkehrsmeldungen —
  /// beim Annähern (<200m) EINMAL pro Vorbeifahrt das "Noch da?"-Sheet
  /// zeigen (Hysterese im Geofence; besser als Google Maps, wo der Prompt
  /// bei jeder Vorbeifahrt erneut nervt). Nur ein Sheet gleichzeitig, und
  /// nie parallel zum Baustellen-Sheet.
  void _processIncidentGeofence(double lat, double lng) {
    if (!_isRouteConfirmed) return;
    if (_routeIncidents.isEmpty) return;
    if (_activeIncidentAlertId != null) return;
    if (_activeConstructionAlertId != null) return;
    final entered = _incidentGeofence.processPosition(
      latitude: lat,
      longitude: lng,
    );
    if (entered.isEmpty || !mounted) return;
    final incident = entered.first;
    _activeIncidentAlertId = incident.id;
    unawaited(
      IncidentAlertSheet.show(context, incident).then((_) {
        _activeIncidentAlertId = null;
      }),
    );
  }

  /// 2026-07-24 (vucko "+-Button"): "+"-FAB → Typ wählen → an aktueller
  /// Position melden. Bei Stau startet zusätzlich das Ausdehnungs-Tracking
  /// (läuft bis wieder flüssig gefahren wird, siehe _tickJamTracking).
  Future<void> _openIncidentReportSheet() async {
    final type = await IncidentReportSheet.show(context);
    if (type == null || !mounted) return;
    // _userPosition wird erst im Navigations-Tracking gesetzt — VOR dem
    // Fahrt-Start (Route-Bestätigungs-Screen) liefert der Idle-Stream die
    // Position über _userLocation. Beide Quellen zulassen.
    final lat = _userPosition?.latitude ?? _userLocation?.latitude;
    final lng = _userPosition?.longitude ?? _userLocation?.longitude;
    if (lat == null || lng == null) {
      TopToast.show(
        context,
        message: 'Keine GPS-Position, bitte gleich nochmal versuchen.',
        isError: true,
      );
      return;
    }
    final result = await RoadIncidentService.instance.report(
      type: type,
      latitude: lat,
      longitude: lng,
    );
    if (!mounted) return;
    if (!result.ok) {
      // 2026-07-26: Der Server begründet Ablehnungen jetzt konkret (Tageslimit,
      // zu schnell hintereinander, unplausibel, gesperrt). Das ist ehrlicher
      // als das frühere pauschale „fehlgeschlagen" und sagt dem Nutzer, was er
      // tun kann.
      TopToast.show(
        context,
        message: result.message ?? 'Melden gerade nicht möglich.',
        isError: true,
      );
      return;
    }
    final incident = result.incident!;
    setState(() {
      _routeIncidents = [
        ..._routeIncidents.where((i) => i.id != incident.id),
        incident,
      ];
    });
    TopToast.show(
      context,
      message: result.merged
          ? '${type.label} bestätigt, danke!'
          : '${type.label} gemeldet, danke!',
      icon: type.icon,
    );
    if (type == RoadIncidentType.stau) {
      _jamTrackingIncidentId = incident.id;
      _jamTrackingStartedAt = DateTime.now();
      _jamRecoverySince = null;
    }
  }

  /// Stau-Ausdehnung: nach einem Stau-Report weiterverfolgen, bis wieder
  /// >60 km/h für 20s am Stück gefahren wird (oder 10-min-Deckel), dann das
  /// Stau-Ende in die Meldung schreiben. Nur der Melder trackt.
  void _tickJamTracking(geo.Position position) {
    final id = _jamTrackingIncidentId;
    if (id == null) return;
    final started = _jamTrackingStartedAt;
    if (started == null ||
        DateTime.now().difference(started) > const Duration(minutes: 10)) {
      _finishJamTracking(position);
      return;
    }
    final speedKmh =
        (position.speed.isFinite ? position.speed : 0.0) * 3.6;
    if (speedKmh > 60.0) {
      _jamRecoverySince ??= DateTime.now();
      if (DateTime.now().difference(_jamRecoverySince!) >
          const Duration(seconds: 20)) {
        _finishJamTracking(position);
      }
    } else {
      _jamRecoverySince = null;
    }
  }

  void _finishJamTracking(geo.Position position) {
    final id = _jamTrackingIncidentId;
    _jamTrackingIncidentId = null;
    _jamTrackingStartedAt = null;
    _jamRecoverySince = null;
    if (id == null) return;
    unawaited(
      RoadIncidentService.instance.updateJamExtent(
        incidentId: id,
        endLat: position.latitude,
        endLng: position.longitude,
      ),
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
        if (user == null) {
          // 2026-07-27: Ohne dieses Zurücksetzen bliebe _poisLoading für immer
          // true und der Wächter ganz oben („if (_poisLoading) return") würde
          // JEDEN weiteren POI-Ladeversuch dieser Seite dauerhaft blockieren.
          if (mounted) setState(() => _poisLoading = false);
          return;
        }
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
    // 2026-06-02 (vucko): POI-/Config-Button war zwischenzeitlich AUCH bei
    // ausgeklapptem Setup-Sheet sichtbar (Wunsch: „über die ganze Karte
    // einstellen, nicht erst bei bestätigter Route"). Im Wegpunkte-Modus
    // bleibt die Spalte ausgeblendet, weil dort die rechte Wegpunkt-Rail
    // bereits POI/Voice/Camera zeigt (sonst Doppel-Spalte, Task #80).
    //
    // 2026-07-25 (vucko „wenn ich das hochwische möchte ich die Panels rechts
    // ausgeblendet haben"): Das kehrt die 2026-06-02-Entscheidung bewusst
    // wieder um. Bei ausgeklapptem Sheet überdeckt das Panel die Karte und
    // die FAB-Spalte lag sichtbar DARÜBER (siehe User-Screenshot) — sie fährt
    // jetzt raus, solange das Sheet oben ist, und kommt zurück, sobald der
    // Nutzer es runterwischt (_configCollapsed == true). Die Buttons bleiben
    // damit erreichbar, sobald man die Karte tatsächlich sieht.
    // 2026-07-27 (vucko „Schnellzugriff/POIs sind während der Fahrt weg"):
    // REGRESSION aus der Zeile darüber. `_configCollapsed` beschreibt das
    // Setup-Sheet, das es NUR vor der bestätigten Route gibt (siehe die beiden
    // Aufrufstellen: hasRoute:false vor der Route, hasRoute:true in der
    // Navigation). Während der Fahrt gibt es nichts zum Hochwischen — trotzdem
    // hing die Sichtbarkeit an dem Flag, und das steht beim Betreten der
    // Navigation stellenweise auf false (z.B. Fahrt-Resume, Zeile ~2206) sowie
    // als Startwert. Ergebnis: die komplette rechte Spalte (POI-Filter, Stimme,
    // Kamera-Lock, Melde-Button) war mitten in der Fahrt unsichtbar.
    // Das Ausblenden gilt jetzt ausdrücklich nur im Vor-Routen-Zustand.
    final hidden = cruiseFabColumnHidden(
      hasRoute: hasRoute,
      waypointRailActive: waypointRailActive,
      configCollapsed: _configCollapsed,
    );
    final bottomInset = hasRoute ? 260.0 : 240.0;
    // 2026-07-25 (Review-Fund): Mit dem neuen Melde-FAB sind es bis zu 5
    // Bubbles (Debug: 6) à 60pt = 300-360pt. Bei bottom:260 ragte die Spalte
    // auf kleinen Geräten (iPhone SE, 667pt) ins Manöver-Banner. Die Spalte
    // wird deshalb auf den real verfügbaren Platz gedeckelt und scrollt bei
    // Bedarf — `reverse: true` hält dabei die UNTEREN (wichtigsten, inkl. "+")
    // Buttons immer sichtbar, oben wird abgeschnitten statt zu überlappen.
    final media = MediaQuery.of(context);
    final maxColumnHeight =
        (media.size.height - bottomInset - media.padding.top - 168.0)
            .clamp(120.0, double.infinity);
    return Positioned(
      right: 16,
      bottom: bottomInset,
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
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxColumnHeight),
              child: SingleChildScrollView(
                reverse: true,
                physics: const ClampingScrollPhysics(),
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
                      onPressed: () => _handleVoiceModeCycle(context),
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
                // 2026-06-19 (vucko Kreisverkehr-Sim): Debug-only Play/Stop-FAB
                // für den Fahrsimulator (Live-Navigation ohne echtes GPS testen).
                if (kDebugMode && _isRouteConfirmed)
                  _FabBubble(
                    heroTag: 'sim_drive_fab',
                    icon: _isSimulationRunning
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                    color: _isSimulationRunning
                        ? const Color(0xFFD64545)
                        : const Color(0xFF2BA84A),
                    onPressed: () {
                      if (_isSimulationRunning) {
                        _stopSimulation();
                      } else {
                        unawaited(_startSimulation());
                      }
                    },
                    big: true,
                  ),
                // 2026-07-24 (vucko "+-Button"): Unfall/Baustelle/Stau melden —
                // unterstes Element der Spalte, direkt über dem Info-Panel
                // (per User-Screenshot markierte Stelle). Nur während einer
                // bestätigten Route sichtbar — Melden ergibt nur im
                // Fahr-Kontext Sinn.
                if (hasRoute && _isRouteConfirmed)
                  _FabBubble(
                    heroTag: 'report_incident_fab',
                    icon: Icons.add_rounded,
                    color: const Color(0xFFE53935),
                    onPressed: () => unawaited(_openIncidentReportSheet()),
                    big: true,
                  ),
                  ],
                ),
              ),
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
    // regulaere Instruktion wäre in dem Moment irrefuehrend.
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
    final maneuverIndex = _activeVisibleManeuverIndex();
    // 2026-06-05 (vucko Task #6): NUR die reine instruction (ohne Distanz) als
    // Voice-Quelle. maneuver.announcement enthält bereits eine Distanz → der alte
    // Fallback doppelte sie zu „In 287m In 300m rechts abbiegen". Ist instruction
    // leer, gar nicht ansagen.
    // 2026-07-02 (vucko Geräte-Video): Die „Jetzt"-Ansage nutzt denselben
    // Wortlaut wie die Vorankündigung desselben Manövers — Kreisel-Promotion/
    // Reroute dazwischen wechselte sonst hörbar Straße/Formulierung.
    var raw = maneuver.instruction.trim();
    if (distMeters <= 30 &&
        maneuverIndex != null &&
        maneuverIndex == _voicePreAnnouncedManeuverIndex &&
        _voicePreAnnouncedText != null) {
      raw = _voicePreAnnouncedText!;
    }
    if (raw.isEmpty) return;
    if (distMeters > 30) _voicePreAnnouncedText = raw;
    // Distanz auf SAUBERE Stufen runden statt krummer Live-Werte („In 287m" →
    // „In 300 Metern"). „Metern" ausgeschrieben für klare TTS-Aussprache.
    final String text;
    if (distMeters <= 30) {
      text = 'Jetzt $raw';
    } else {
      final rounded = formatSpokenNavDistanceMeters(distMeters.toDouble());
      text = 'In $rounded Metern $raw';
    }
    if (important) {
      unawaited(
        TtsService.instance.speakImportant(
          text,
          interrupt: interrupt,
          navTag: maneuverIndex,
        ),
      );
    } else {
      unawaited(TtsService.instance.speakOptional(text));
    }
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

  /// 2026-06-23 (vucko 2-Geräte-Video „Reroute findet ab einem Punkt KEINE Route
  /// mehr"): Netz-freier Re-Anchor-Notnagel. Baut aus der bestehenden Planungs-
  /// route + GPS-Position eine garantiert gültige Route und committet sie unter
  /// Umgehung der Shape-/Stale-Gates (`allowStaleReanchor`). Bricht die Endlos-
  /// „Neuberechnung", wenn GraphHopper nichts liefert (429-Rate-Limit oder jeder
  /// Kandidat ge-gated). Gibt true zurück, wenn committed.
  Future<bool> _commitLocalReanchorFallback({
    required geo.Position position,
    required List<List<double>> planningCoordinates,
    required List<RouteManeuver> planningManeuvers,
    required double? remainingDistanceBeforeMeters,
  }) async {
    if (planningCoordinates.length < 2) return false;
    // Nächsten Punkt auf der Planungsroute suchen + EINEN Schritt vorwärts →
    // kurzer gerader Anschluss am Puck (kein 1-2km-Fern-Rejoin-Diagonale).
    final match = findNearestInWindow(
      position: position,
      coordinates: planningCoordinates,
      currentIndex: 0,
      windowSize: planningCoordinates.length,
      maxJumpMeters: double.infinity,
    );
    final rejoin = math
        .min(match.index + 1, planningCoordinates.length - 1)
        .clamp(0, planningCoordinates.length - 1)
        .toInt();
    final reanchor = buildLocalReanchorRoute(
      currentPosition: [position.longitude, position.latitude],
      planningCoordinates: planningCoordinates,
      planningManeuvers: planningManeuvers,
      forwardRejoinIndex: rejoin,
    );
    if (reanchor.coordinates.length < 2) return false;
    final dist = _calculatePolylineDistanceMeters(reanchor.coordinates);
    return _commitRerouteResult(
      result: _buildRouteResultFromCoordinates(
        coordinates: reanchor.coordinates,
        maneuvers: reanchor.maneuvers,
        distanceMeters: dist,
        durationSeconds: _estimateDurationSecondsForDistance(dist),
        speedLimits: const <SpeedLimitSegment>[],
        edgeMeta: const {'reroute_mode': 'local_reanchor'},
      ),
      position: position,
      remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
      allowStaleReanchor: true,
      // Lokaler Notnagel = nur SELBST zurück auf die bestehende Route. Die
      // (degradierte, gerade-Anschluss-)Geometrie NICHT in die Gruppe
      // publizieren — der nächste echte GH-Reroute übernimmt das.
      publishToGroup: false,
    );
  }

  Future<void> _rerouteToOriginalRoute(geo.Position position) async {
    if (_isRerouting) return;
    _isRerouting = true;
    _rerouteStartedAt = DateTime.now();
    _pendingChainedReroute = false;
    // 2026-06-22 (vucko Reroute-Hang): Harter Watchdog. Alle await-Stellen sind
    // einzeln per .timeout() gedeckelt (Connectivity 2s, HTTP ≤10s, GPS 3s) →
    // das finally läuft garantiert. Dieser Timer ist das Sicherheitsnetz für den
    // pathologischen Fall, dass ein Future trotzdem hängt: nach _rerouteWatchdog
    // Timeout wird der „Neuberechnung"-Status zwangsweise beendet. Ein evtl.
    // spät zurückkommender Commit wird vom 80m-Stale-Check in
    // _commitRerouteResult ohnehin verworfen (der Fahrer ist längst weiter).
    _rerouteWatchdog?.cancel();
    _rerouteWatchdog = Timer(_rerouteWatchdogTimeout, () {
      if (!_isRerouting || !mounted || _disposed) return;
      debugPrint(
        '[CruiseMode][Reroute] Watchdog: Reroute >${_rerouteWatchdogTimeout.inSeconds}s '
        'ohne Commit → harter Reset des „Neuberechnung"-Status',
      );
      _isRerouting = false;
      _rerouteStartedAt = null;
      _lastRerouteTime = DateTime.now();
      _lastRerouteFailed = true;
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        TopToast.show(
          context,
          message:
              'Reroute dauert zu lange, bitte weiterfahren, ich versuche es gleich erneut',
          icon: Icons.refresh_rounded,
          isError: true,
          duration: const Duration(milliseconds: 4000),
        );
        _safeSetState(() {});
      }
    });
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
                'Reroute gerade nicht möglich: GPS ist noch nicht präzise genug, bitte weiterfahren',
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
      // 2026-06-22 (vucko Reroute-Hang): Watchdog abräumen — der reguläre Pfad
      // ist fertig, ein verspäteter Zwangs-Reset wäre jetzt nur störend.
      _rerouteWatchdog?.cancel();
      _rerouteWatchdog = null;
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

            final committed = await _commitRerouteResult(
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
              remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
            );
            if (!committed) {
              cycleFailures.add('distance_guard(destination)');
              // 2026-06-23 (vucko 2-Geräte-Gruppen-Video „Reroute oszilliert,
              // ETA hängt auf alter Route"): Auch der ZIEL-Pfad braucht das
              // Local-Reanchor-Netz (wie Redock + no_candidate). Ein NICHT-
              // führender Gruppen-Follower wird in _commitRerouteResult VOR dem
              // lokalen Apply abgewiesen (Nicht-Leader-Zweig, publishToGroup) →
              // ohne dieses Netz bekäme er GAR KEINE Route: er oszillierte
              // zwischen „Neuberechnung" und alter Linie und behielt die alte
              // Rest-km/ETA, bis die Leader-Route adoptiert ist (Realtime/5s-
              // Backfill). Der Reanchor (publishToGroup:false) gibt ihm SOFORT
              // eine eigene Brücken-Linie+Manöver+ETA ab der GPS-Position; die
              // nächste Leader-Adoption (_applyGroupRouteData) überschreibt sie
              // sauber. Solo/Leader: ohnehin committet der reguläre Pfad → der
              // Reanchor greift dort nur bei echtem Stale/Distance-Guard (safe).
              if (mounted && !_disposed) {
                final local = await _commitLocalReanchorFallback(
                  position: position,
                  planningCoordinates: planningCoordinates,
                  planningManeuvers: planningManeuvers,
                  remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
                );
                if (local) return true;
              }
              return false;
            }
            _logRerouteMeta(rerouteMeta);
            _clearAccessLegState();
            _sessionRouteStartIndexInActiveRoute = 0;

            // 2026-06-21 (vucko Geräte-Video „Doppelbanner"): KEIN Reroute-Toast
            // mehr. Der frühere „Gruppen-Route aktualisiert"/„Neue Strecke"-Top-
            // Toast lag über dem Manöver-Banner (beide oben verankert) und kam in
            // Gruppenfahrten bei jedem Leader-Update — Doppelbanner-Kollision.
            // Die neu gezeichnete Linie + das aktualisierte Manöver-Banner sind
            // die Rückmeldung (wie Apple/Google, die Reroutes nicht toasten).
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
            final committed = await _commitRerouteResult(
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
              remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
            );
            if (!committed) {
              cycleFailures.add('distance_guard(redock)');
              // 2026-06-23 (vucko Video): Selbst der „garantierte" Re-Dock wurde
              // ge-gated (Fahrer beim Commit zu weit weg / Stale) → lokaler
              // Re-Anchor (bypasst die Gates, beginnt exakt am Puck).
              if (mounted && !_disposed) {
                final local = await _commitLocalReanchorFallback(
                  position: position,
                  planningCoordinates: planningCoordinates,
                  planningManeuvers: planningManeuvers,
                  remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
                );
                if (local) return true;
              }
              return false;
            }
            if (mounted) {
              TopToast.show(
                context,
                message: 'Route neu berechnet, zurück auf Kurs',
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
        // 2026-06-23 (vucko 2-Geräte-Video „Reroute findet ab einem Punkt KEINE
        // Route mehr"): LETZTER AUSWEG — lokaler Re-Anchor OHNE Netz. Lieferten
        // alle GH-Versuche (Ziel/Rejoin/garantierter Re-Dock) nichts — typisch
        // wenn GH nach vielen Reroutes 429-rate-limitet ODER jeder Kandidat durch
        // die Shape-/Merge-Gates fällt — committen wir die bestehende Planungs-
        // route ab dem nächsten Vorwärtspunkt mit der GPS-Position als Start. So
        // bekommt der Fahrer IMMER eine Linie+Manöver zurück statt >2,5 Min
        // Endlos-„Neuberechnung" (genau die Endlosschleife aus dem Video).
        if (mounted && !_disposed && planningCoordinates.length >= 2) {
          final localCommitted = await _commitLocalReanchorFallback(
            position: position,
            planningCoordinates: planningCoordinates,
            planningManeuvers: planningManeuvers,
            remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
          );
          if (localCommitted) {
            debugPrint(
              '[CruiseMode][Reroute] Lokaler Re-Anchor committed '
              '(Netz-Notnagel) — Endlos-Neuberechnung gebrochen',
            );
            return true;
          }
        }
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

      final committed = await _commitRerouteResult(
        result: finalResult,
        sessionRouteResult: sessionRouteResult,
        position: position,
        publishToGroup: !accessLegMode,
        remainingDistanceBeforeMeters: remainingDistanceBeforeMeters,
      );
      if (!committed) {
        cycleFailures.add('distance_guard');
        return false;
      }
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
    if (GeoBearing.isUsableHeading(smoothedHeading)) {
      return smoothedHeading! % 360;
    }

    final rawHeading = position.heading;
    final rawAccuracy = position.headingAccuracy;
    if (GeoBearing.isUsableHeading(rawHeading) &&
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


  /// Berechnet die Distanz entlang der Route vom aktuellen Index zum nächsten Manöver.
  int? _activeVisibleManeuverIndex() {
    return _navigationController.activeVisibleManeuverIndex(
      maneuvers: _maneuvers,
      currentRouteIndex: _currentRouteIndex,
      activeManeuverIndex: _activeManeuverIndex,
      remainingRouteDistanceMeters: _remainingDistance,
      distanceToFinalTargetMeters: _distanceToFinalTargetMeters,
      arrivalRadiusMeters: _arrivalRadiusMeters,
    );
  }

  RouteManeuver? _activeVisibleManeuver() {
    return _navigationController.activeVisibleManeuver(
      maneuvers: _maneuvers,
      currentRouteIndex: _currentRouteIndex,
      activeManeuverIndex: _activeManeuverIndex,
      remainingRouteDistanceMeters: _remainingDistance,
      distanceToFinalTargetMeters: _distanceToFinalTargetMeters,
      arrivalRadiusMeters: _arrivalRadiusMeters,
    );
  }

  double? _calculateDistanceToManeuver([RouteManeuver? visibleManeuver]) {
    return _navigationController.calculateDistanceToManeuver(
      maneuvers: _maneuvers,
      routeCoordinates: _fullRouteCoordinates,
      currentRouteIndex: _currentRouteIndex,
      activeManeuverIndex: _activeManeuverIndex,
      remainingRouteDistanceMeters: _remainingDistance,
      distanceToFinalTargetMeters: _distanceToFinalTargetMeters,
      arrivalRadiusMeters: _arrivalRadiusMeters,
      offRouteGapMeters: _offRouteGapMeters,
      visibleManeuver: visibleManeuver,
    );
  }

  /// Banner-Distanz: gleiche geglättete Rohdistanz wie Voice/Haptik, danach nur
  /// noch visuelle Monotonie, damit der Text innerhalb desselben Manövers nicht
  /// nach oben springt.
  double? _displayManeuverDistanceMeters([RouteManeuver? visibleManeuver]) {
    return _navigationController.displayManeuverDistanceMeters(
      maneuvers: _maneuvers,
      routeCoordinates: _fullRouteCoordinates,
      currentRouteIndex: _currentRouteIndex,
      activeManeuverIndex: _activeManeuverIndex,
      remainingRouteDistanceMeters: _remainingDistance,
      distanceToFinalTargetMeters: _distanceToFinalTargetMeters,
      arrivalRadiusMeters: _arrivalRadiusMeters,
      offRouteGapMeters: _offRouteGapMeters,
      cumulativeDistancesMeters: _routeCumDistM,
      renderLockDistanceMeters: _renderLockDistM,
      visibleManeuver: visibleManeuver,
    );
  }

  NavigationLiveActivitySnapshot _navigationLiveActivitySnapshot() {
    final maneuver = _activeVisibleManeuver();
    final instruction = _isReroutingBannerActive
        ? 'Route wird neu berechnet'
        : (maneuver?.instruction.trim().isNotEmpty == true
              ? maneuver!.instruction.trim()
              : 'Der Route folgen');
    final kind = maneuver == null
        ? 'continue'
        : maneuver.isArrival
        ? 'arrival'
        : maneuver.maneuverType == ManeuverType.roundabout
        ? 'roundabout:${maneuver.roundaboutExitNumber ?? 0}'
        : _maneuverKindFromInstruction(maneuver.instruction);
    final distanceToManeuver = maneuver == null
        ? null
        : _leadCompensatedLiveDistance(
            _displayManeuverDistanceMeters(maneuver),
          );
    return NavigationLiveActivitySnapshot(
      instruction: instruction,
      maneuverType: kind,
      distanceToManeuverMeters: distanceToManeuver,
      remainingDistanceMeters: _leadCompensatedLiveDistance(
        _remainingDistance ?? _routeDistance,
      ),
      remainingDurationSeconds: (_remainingDuration ?? _routeDuration)?.round(),
      isRerouting: _isReroutingBannerActive,
    );
  }

  // 2026-06-20 (vucko Live-Activity-Sync): Die Sperrbildschirm-Live-Activity
  // rendert erst ~1-2 s nach unserem Push (ActivityKit-Latenz + der Wert bleibt
  // bis zum nächsten Push STATISCH) → bei Tempo hängt die Lock-Screen-Zahl 50-150 m
  // hinter der In-App-Meteranzeige. Gegenmittel: wir senden eine LEAD-kompensierte
  // Distanz — den Wert, den die In-App in ~_liveActivityLeadSeconds ZEIGEN wird.
  // Wenn iOS den Push dann tatsächlich rendert, stimmt er ~mit der In-App-Zahl
  // überein → synchron. Skaliert mit der (geglätteten) Geschwindigkeit: langsam/
  // stehend = exakt; nah am Manöver (≤100 m) ebenfalls exakt, damit kein
  // verfrühtes „Jetzt" entsteht. Gedeckelt, damit es nie weit vorausläuft.
  static const double _liveActivityLeadSeconds = 1.5;
  static const double _liveActivityLeadCapMeters = 80.0;

  bool _appInForeground = true;

  double? _leadCompensatedLiveDistance(double? meters) {
    if (meters == null) return null;
    if (_appInForeground) return meters; // Vordergrund: exakt = wie Banner
    if (meters <= 100) return meters;
    final speed = _nativeSmoother.speed;
    if (!speed.isFinite || speed <= 2.0) return meters;
    final lead = (speed * _liveActivityLeadSeconds).clamp(
      0.0,
      _liveActivityLeadCapMeters,
    );
    return math.max(0.0, meters - lead);
  }

  String _maneuverKindFromInstruction(String instruction) {
    final lower = instruction.toLowerCase();
    if (lower.contains('links')) return 'left';
    if (lower.contains('rechts')) return 'right';
    if (lower.contains('wenden')) return 'uturn';
    if (lower.contains('ziel') || lower.contains('ankunft')) return 'arrival';
    return 'continue';
  }

  void _startNavigationLiveActivity() {
    _lastLiveActivitySignature = null;
    _lastLiveActivitySentAt = null;
    _lastLiveActivityCoreKey = null;
    final snapshot = _navigationLiveActivitySnapshot();
    _lastLiveActivitySignature = snapshot.signature();
    _lastLiveActivitySentAt = DateTime.now();
    _lastLiveActivityCoreKey = _liveActivityCoreKey(snapshot);
    unawaited(NavigationLiveActivityService.instance.start(snapshot));
    // 2026-07-03 (vucko): Android-Live-Preview parallel — laufende
    // Benachrichtigung (Sperrbildschirm/Shade), gleiche Daten, eigenes Gate.
    unawaited(NavigationAndroidNotificationService.instance.start(snapshot));
  }

  // 2026-07-02 (vucko Geräte-Video Live-Activity-Freeze): „Kern" eines
  // Snapshots = das Manöver selbst. Nur bei Kern-Wechsel darf ein Update das
  // 5-s-Distanz-Throttle umgehen.
  String _liveActivityCoreKey(NavigationLiveActivitySnapshot s) {
    return '${s.instruction}|${s.maneuverType}|${s.isRerouting}';
  }

  void _updateNavigationLiveActivity({bool force = false}) {
    final snapshot = _navigationLiveActivitySnapshot();
    final signature = snapshot.signature();
    final now = DateTime.now();
    // 2026-07-02 (vucko Geräte-Video Live-Activity-Freeze): iOS drosselt Live
    // Activities über ein Update-BUDGET. Die alten 10-m-Buckets + 8-s-Keep-alive
    // ergaben bei Fahrtempo ~1 Update/s — nach ~1 Minute stellte iOS das Rendern
    // KOMPLETT ein (Sperrbildschirm fror bei „Churer Straße / Jetzt" ein, obwohl
    // die App weiter sendete). Deshalb hart limitieren: Manöver-/Reroute-Wechsel
    // nach frühestens 1 s, reine Distanz-Fortschritte nach frühestens 5 s,
    // unveränderter Inhalt nur als 45-s-Keep-alive.
    if (!force && _lastLiveActivitySentAt != null) {
      final sinceLast = now.difference(_lastLiveActivitySentAt!);
      final coreChanged =
          _liveActivityCoreKey(snapshot) != _lastLiveActivityCoreKey;
      final Duration minGap;
      if (coreChanged) {
        minGap = const Duration(seconds: 1);
      } else if (signature != _lastLiveActivitySignature) {
        minGap = const Duration(seconds: 5);
      } else {
        minGap = const Duration(seconds: 45);
      }
      if (sinceLast < minGap) return;
    }
    _lastLiveActivitySignature = signature;
    _lastLiveActivitySentAt = now;
    _lastLiveActivityCoreKey = _liveActivityCoreKey(snapshot);
    if (kDebugMode) {
      debugPrint(
        '[LiveActivity] send dist=${snapshot.distanceToManeuverMeters?.toStringAsFixed(0)} '
        '"${snapshot.instruction}"',
      );
    }
    unawaited(NavigationLiveActivityService.instance.update(snapshot));
    unawaited(NavigationAndroidNotificationService.instance.update(snapshot));
  }

  void _endNavigationLiveActivity() {
    _lastLiveActivitySignature = null;
    _lastLiveActivitySentAt = null;
    _lastLiveActivityCoreKey = null;
    unawaited(NavigationLiveActivityService.instance.end());
    unawaited(NavigationAndroidNotificationService.instance.end());
  }

  void _updateActiveManeuver() {
    _activeManeuverIndex = _navigationController.activeManeuverIndexForProgress(
      maneuvers: _maneuvers,
      currentRouteIndex: _currentRouteIndex,
      fallbackIndex: _activeManeuverIndex,
    );
  }

  List<({double lat, double lng})> _roundaboutTopologyProbePoints(
    RouteManeuver maneuver,
  ) {
    final points = <({double lat, double lng})>[];
    void add(double lat, double lng) {
      if (!lat.isFinite || !lng.isFinite) return;
      for (final p in points) {
        final d = geo.Geolocator.distanceBetween(p.lat, p.lng, lat, lng);
        if (d < 14.0) return;
      }
      points.add((lat: lat, lng: lng));
    }

    add(maneuver.latitude, maneuver.longitude);
    if (_fullRouteCoordinates.isEmpty) return points;

    final idx = maneuver.routeIndex
        .clamp(0, _fullRouteCoordinates.length - 1)
        .toInt();
    void addCoord(int i) {
      if (i < 0 || i >= _fullRouteCoordinates.length) return;
      final c = _fullRouteCoordinates[i];
      if (c.length < 2) return;
      add(c[1], c[0]);
    }

    addCoord(idx);

    // 2026-06-18 (Dormagen-Videos): GH/Mapbox-Manöverkoordinaten liegen an
    // Kreiseln teils auf Zufahrt, Ring oder Ausfahrt. Eine einzige 45-m-
    // Overpass-Probe kann dann den Ring knapp verfehlen und cached "kein Ring".
    // Deshalb entlang der gefahrenen Route rund um das Manöver probieren.
    var walked = 0.0;
    for (var i = idx; i < _fullRouteCoordinates.length - 1; i++) {
      final a = _fullRouteCoordinates[i];
      final b = _fullRouteCoordinates[i + 1];
      if (a.length < 2 || b.length < 2) break;
      walked += geo.Geolocator.distanceBetween(a[1], a[0], b[1], b[0]);
      if (walked > 115.0 || points.length >= 8) break;
      addCoord(i + 1);
    }

    walked = 0.0;
    for (var i = idx; i > 0; i--) {
      final a = _fullRouteCoordinates[i];
      final b = _fullRouteCoordinates[i - 1];
      if (a.length < 2 || b.length < 2) break;
      walked += geo.Geolocator.distanceBetween(a[1], a[0], b[1], b[0]);
      if (walked > 70.0 || points.length >= 10) break;
      addCoord(i - 1);
    }
    return points;
  }

  RoundaboutTopology? _cachedRoundaboutTopologyFor(
    Iterable<({double lat, double lng})> probes,
    RoundaboutTopologyService svc,
  ) {
    for (final p in probes) {
      final cached = svc.cached(p.lat, p.lng);
      if (cached != null) return cached;
    }
    return null;
  }

  bool _allRoundaboutTopologyProbesResolved(
    Iterable<({double lat, double lng})> probes,
    RoundaboutTopologyService svc,
  ) {
    var hasProbe = false;
    for (final p in probes) {
      hasProbe = true;
      if (!svc.isResolved(p.lat, p.lng)) return false;
    }
    return hasProbe;
  }

  bool _applyResolvedRoundaboutTopologyIfReady(
    int index,
    RoundaboutTopologyService svc,
  ) {
    if (index < 0 || index >= _maneuvers.length) return false;
    final maneuver = _maneuvers[index];
    final probes = _roundaboutTopologyProbePoints(maneuver);
    final cached = _cachedRoundaboutTopologyFor(probes, svc);
    if (cached != null) {
      _applyRoundaboutTopology(index, cached);
      return true;
    }
    if (_allRoundaboutTopologyProbesResolved(probes, svc)) {
      if (maneuver.maneuverType == ManeuverType.roundabout) {
        _applyRoundaboutTopology(index, null);
        return true;
      }
      return false;
    }
    return false;
  }

  ({double lat, double lng})? _firstUnresolvedRoundaboutProbe(
    Iterable<({double lat, double lng})> probes,
    RoundaboutTopologyService svc,
  ) {
    for (final p in probes) {
      if (!svc.isResolved(p.lat, p.lng)) return p;
    }
    return null;
  }

  // 2026-06-16 (vucko O9): Echte Kreisverkehr-Topologie lazy beim Anfahren
  // holen. Sucht das nächste Kreisverkehr-Manöver ab dem aktiven Index, das
  // noch keine Arm-Winkel hat und <1500m entfernt ist. Liegt das Ergebnis schon
  // im Cache (synchron), wird es sofort angewandt; sonst genau EIN Overpass-Fetch
  // ausgelöst (dedupliziert im Service), dessen Resultat danach ins Manöver
  // gespiegelt wird. Schlägt nur das Netz fehl, bleibt das Manöver offen und der
  // nächste Tick darf erneut versuchen. Nur wenn alle lokalen Proben erfolgreich
  // "kein Ring" liefern, wird der Geometrie-Fallback endgültig markiert.
  void _maybeEnrichRoundaboutTopology() {
    if (_maneuvers.isEmpty) return;
    final start = _activeManeuverIndex.clamp(0, _maneuvers.length - 1);
    final origin = _userLocation;
    for (var i = start; i < _maneuvers.length; i++) {
      final m = _maneuvers[i];
      final isKnownRoundabout = m.maneuverType == ManeuverType.roundabout;
      final isHiddenRoundaboutCandidate =
          !isKnownRoundabout && _maneuverCouldBeHiddenRoundabout(m);
      if (!isKnownRoundabout && !isHiddenRoundaboutCandidate) continue;
      if (isKnownRoundabout && m.roundaboutArmBearings != null) {
        continue; // schon aufgelöst
      }
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
      if (_applyResolvedRoundaboutTopologyIfReady(i, svc)) return;

      final probes = _roundaboutTopologyProbePoints(m);
      if (!isKnownRoundabout &&
          _allRoundaboutTopologyProbesResolved(probes, svc)) {
        continue;
      }
      final probe = _firstUnresolvedRoundaboutProbe(probes, svc);
      if (probe != null) {
        final maneuverLat = m.latitude;
        final maneuverLng = m.longitude;
        final maneuverRouteIndex = m.routeIndex;
        final probeLat = probe.lat;
        final probeLng = probe.lng;
        svc.fetch(probeLat, probeLng).then((topo) {
          if (!mounted) return;
          if (topo == null && !svc.isResolved(probeLat, probeLng)) {
            // Netz-/Endpoint-Fehler: nicht als "aufgelöst" markieren, sonst
            // bleibt genau der Kreisel dieser Fahrt dauerhaft im Fallback.
            return;
          }
          // Index könnte inzwischen anders sein → über ursprüngliches Manöver
          // wiederfinden, nicht über die Probe-Koordinate.
          for (var j = 0; j < _maneuvers.length; j++) {
            final mm = _maneuvers[j];
            final mmKnownRoundabout =
                mm.maneuverType == ManeuverType.roundabout;
            if (!mmKnownRoundabout && !_maneuverCouldBeHiddenRoundabout(mm)) {
              continue;
            }
            if (mmKnownRoundabout && mm.roundaboutArmBearings != null) {
              continue;
            }
            final sameCoordinate =
                (mm.latitude - maneuverLat).abs() < 1e-6 &&
                (mm.longitude - maneuverLng).abs() < 1e-6;
            if (sameCoordinate || mm.routeIndex == maneuverRouteIndex) {
              if (topo != null) {
                _applyRoundaboutTopology(j, topo);
              } else {
                _applyResolvedRoundaboutTopologyIfReady(j, svc);
              }
              break;
            }
          }
        });
      }
      return; // pro Tick nur das nächste Manöver behandeln
    }
  }

  bool _maneuverCouldBeHiddenRoundabout(RouteManeuver maneuver) {
    if (maneuver.maneuverType == ManeuverType.roundabout) return true;
    if (maneuver.isArrival) return false;
    final text = maneuver.instruction.toLowerCase();
    if (text.contains('kreisverkehr') ||
        text.contains('roundabout') ||
        text.contains('traffic circle') ||
        text.contains('rotary')) {
      return true;
    }
    return maneuver.icon == Icons.turn_right ||
        maneuver.icon == Icons.turn_left ||
        maneuver.icon == Icons.turn_slight_right ||
        maneuver.icon == Icons.turn_slight_left ||
        maneuver.icon == Icons.turn_sharp_right ||
        maneuver.icon == Icons.turn_sharp_left;
  }

  void _applyRoundaboutTopology(int index, RoundaboutTopology? topo) {
    if (index < 0 || index >= _maneuvers.length) return;
    if (_maneuvers[index].roundaboutArmBearings != null) return;
    final current = _maneuvers[index];
    if (current.maneuverType != ManeuverType.roundabout && topo == null) {
      return;
    }

    // 2026-06-19 (vucko Kreisverkehr 100% wie Apple): War das Manöver schon von
    // GraphHopper als Kreisel erkannt, ist GHs exit_number die topologie-
    // abgeleitete Wahrheit — wir tasten Nummer/Text/Winkel NICHT an und hängen
    // NUR die echten OSM-Arme + Inselgröße fürs Symbol an. (Früher überschrieb
    // roundaboutExitNumberFromTopologyBearings hier GHs korrekte Nummer und
    // konnte sie verschlechtern — genau die Screenshot-Fehler.)
    if (current.maneuverType == ManeuverType.roundabout) {
      _maneuvers[index] = current.copyWith(
        roundaboutArmBearings: topo?.armBearings ?? const <double>[],
        roundaboutIslandScale: topo?.islandScale,
      );
      _safeSetState(() {});
      return;
    }

    // „Versteckter" Kreisel: GH hat ihn NICHT als Kreisel geliefert (keine
    // Nummer). Erst hier promotet → die Nummer kommt aus OSM-Topologie, sonst
    // aus der Geometrie. Symbol-Pfeil weiter aus dem echten Routen-Drehwinkel.
    final geomTurnRad = roundaboutGeomTurnRad(
      _fullRouteCoordinates,
      current.routeIndex,
      current.routeIndex,
    );
    final entryBearing = RoundaboutTopologyService.armBearingAlong(
      _fullRouteCoordinates,
      current.routeIndex,
      -1,
    );
    final exitBearing = RoundaboutTopologyService.armBearingAlong(
      _fullRouteCoordinates,
      current.routeIndex,
      1,
    );
    final topologyExit = roundaboutExitNumberFromTopologyBearings(
      entryBearing: entryBearing,
      exitBearing: exitBearing,
      armBearings: topo?.armBearings,
    );
    final exitNumber =
        topologyExit ?? roundaboutExitNumberFromGeometryRad(geomTurnRad);
    final instruction = exitNumber != null
        ? roundaboutInstructionForExitNumber(exitNumber)
        : 'Im Kreisverkehr weiterfahren';
    _maneuvers[index] = current.copyWith(
      icon: Icons.roundabout_right,
      maneuverType: ManeuverType.roundabout,
      announcement: instruction,
      instruction: instruction,
      roundaboutExitNumber: exitNumber,
      roundaboutTurnAngleRad: geomTurnRad,
      roundaboutEntryBearing: entryBearing,
      roundaboutExitBearing: exitBearing,
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
    _startCompassIfNeeded();
  }

  // ── 2026-07-22 (vucko Free-Cam-Kompass) ──────────────────────────────────

  void _startCompassIfNeeded() {
    // Simulation hat keinen synthetischen Kompass — der echte Magnetometer-
    // Wert würde beim Schreibtisch-Test nur verwirren.
    if (kIsWeb || _isCameraLocked || _isSimulationRunning || !mounted) return;
    _compassService.onUpdate = _onCompassHeadingUpdate;
    _compassService.start();
  }

  void _stopCompass() => _compassService.stop();

  /// Weckt den pausierten Free-Cam-Ticker auf, wenn sich das Gerät im Stand
  /// nennenswert dreht (Idle-Stop hält ihn sonst an — vor dem Kompass gab es
  /// im Stand schlicht nichts zu animieren). Die eigentliche Rotation macht
  /// weiterhin der Ticker (Glättung, Gesten-Sperre, Rate-Limit).
  void _onCompassHeadingUpdate() {
    if (!mounted || _disposed || _isCameraLocked) return;
    if (_cameraAnimController?.isAnimating ?? false) return;
    final target = _freeModeAutoRotateBearing();
    if (target == null) return;
    if (GeoBearing.angleDiff(_lastFreeAutoRotateHeading, target).abs() < 3.0) {
      return;
    }
    _lastCameraFrameAt = null;
    _cameraAnimController?.repeat();
  }

  /// Ziel-Bearing für die Auto-Rotation im freien Modus — oder null, wenn
  /// gerade keine vertrauenswürdige Quelle existiert.
  double? _freeModeAutoRotateBearing() {
    if (_isSimulationRunning) return null;
    final speedNow = math.max(
      _nativeSmoother.speed,
      _userLocation?.speed ?? 0.0,
    );
    if (speedNow < 2.5) {
      // Stand/Schritttempo: Magnetometer ist hier die EINZIGE lebendige
      // Richtungs-Quelle (GPS-Kurs friert ein, Bewegungs-Heading ruht).
      return _compassService.hasHeading ? _compassService.heading : null;
    }
    // Fahrt: Bewegungs-/GPS-Heading-Fusion ist die bessere Quelle.
    return (_userHeading.isFinite && _userHeading >= 0) ? _userHeading : null;
  }

  /// Ob Auto-Rotate aktuell etwas zu tun hätte (>=3° Abweichung) — hält den
  /// Idle-Stop des Tickers davon ab, mitten in einer Drehung zu pausieren.
  bool _freeModeAutoRotatePending() {
    final target = _freeModeAutoRotateBearing();
    if (target == null) return false;
    return GeoBearing.angleDiff(_lastFreeAutoRotateHeading, target).abs() >=
        3.0;
  }

  /// Google-Maps-artige Kompass-Rotation: pro Tick im freien Modus prüfen, ob
  /// die Kamera smooth Richtung Blick-/Fahrtrichtung nachdrehen soll.
  void _applyFreeModeAutoRotate() {
    if (_freeRotateInFlight) return;
    final target = _freeModeAutoRotateBearing();
    if (target == null) return;
    final gestureAt = _lastUserCameraGestureAt;
    if (gestureAt != null &&
        DateTime.now().difference(gestureAt) < _freeRotateGestureBlock) {
      return;
    }
    if (GeoBearing.angleDiff(_lastFreeAutoRotateHeading, target).abs() < 3.0) {
      return;
    }
    final cur = _mlController?.raw.cameraPosition;
    if (cur == null) return;
    _freeRotateInFlight = true;
    _lastFreeAutoRotateHeading = target;
    _mlController!
        .animateTo(
          lat: cur.target.latitude,
          lng: cur.target.longitude,
          zoom: cur.zoom,
          bearing: target,
          duration: const Duration(milliseconds: 400),
        )
        .whenComplete(() => _freeRotateInFlight = false);
  }

  Future<void> _recenterMap() async {
    final position = _userLocation;
    if (position == null || !_mapReady) return;
    // 2026-07-22 (vucko Free-Cam-Kompass): Zentrieren = gelockter Follow —
    // der Magnetometer wird nicht mehr gebraucht (Lock nutzt Routen-Tangente/
    // Bewegungs-Heading). Jeder Lock-Pfad läuft durch diese Funktion.
    _stopCompass();
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
    // 2026-07-22 (vucko „nach Routen-Start 300-400m verkehrt herum"): Bisher
    // wurde hier HART auf _userHeading gesnappt — das ist der fusionierte
    // Smoother-Zustand, der nach Stand-/Langsamfahrt-Phasen (Ampel, Routen-
    // Start, App-Resume) aus GPS-Jitter bis ~180° falsch geprägt sein konnte
    // und sich danach nur über mehrere reale Fixe hinweg heilte (= 300-400m).
    // Jetzt gilt dieselbe Prioritätsordnung wie im laufenden Navigations-Tick:
    // 1) Routen-Tangente in Fahrtrichtung (on-route die Wahrheit),
    // 2) letztes zuverlässiges rohes GPS-Heading (frisch, streng validiert),
    // 3) _userHeading, 4) letztes Kamera-Heading.
    // Ankunftsfenster (~180m vor Ziel) wie im Tick ausgenommen: dort ist die
    // Tangente an den letzten Stützpunkten degeneriert (Spin/Flip-Fix 06-24).
    // BEWUSST kein _isOverviewActive-Gate: _showRouteOverview() ruft
    // _recenterMap() auf, WÄHREND das Flag noch true ist (finally setzt es
    // erst danach zurück) — die Tangente muss auch dort greifen.
    final remainingForRecenter = _remainingDistance;
    final inArrivalWindow =
        remainingForRecenter != null &&
        remainingForRecenter.isFinite &&
        remainingForRecenter <= _arrivalCameraFreezeMeters;
    double? tangentHeading;
    if (_isRouteConfirmed && !inArrivalWindow) {
      tangentHeading = _routeTangentCameraBearing(anchor);
    }
    final gpsFallback = (!kIsWeb && _nativeSmoother.hasRecentReliableGpsHeading)
        ? _nativeSmoother.lastReliableGpsHeading
        : null;
    final heading =
        tangentHeading ??
        gpsFallback ??
        ((_userHeading.isFinite && _userHeading >= 0)
            ? _userHeading
            : _lastCameraHeading);
    // Smoother-Heading-Zustand HART mitziehen: sonst fiele der Navigations-
    // Tick beim nächsten Tangenten-Aussetzer (Mini-Off-Route-Blip) sofort auf
    // den alten, evtl. korrupten EMA-Zustand zurück und die Kamera drehte
    // wieder weg.
    if (!kIsWeb) _nativeSmoother.snapHeading(heading);
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

  // 2026-06-19 (vucko Kreisverkehr-Sim-Test): Debug-Fahrsimulator. Fährt die
  // bestätigte Route mit konstant 30 km/h ab und speist die Positionen in den
  // ECHTEN _onLocationUpdate-Pfad — so testet er die Live-Navigation (Banner,
  // Kreisel-Symbol/Nummer, Puck, Render-Lock) ohne echtes GPS. NUR in kDebugMode.
  Future<void> _startSimulation() async {
    if (!kDebugMode) return;
    if (_isSimulationRunning) return;
    if (_fullRouteCoordinates.length < 2) return;
    _stopNavigationTracking(); // echtes GPS pausieren
    _simIndex = 0;
    _simDistM = 0.0;
    _simDistAtIndexM = 0.0;
    // GPS-Ausreißer-Gate zurücksetzen, damit die erste Sim-Position (evtl. weit
    // vom letzten echten Fix) nicht als unmöglicher Sprung verworfen wird.
    _lastPlausibleRawFix = null;
    _gpsJumpRejects = 0;
    _isSimulationRunning = true;
    if (!_isCameraLocked) {
      _isCameraLocked = true;
      await _activateNavigationCamera();
    }
    _safeSetState(() {});
    _simStep();
  }

  void _stopSimulation({bool restartLiveTracking = true}) {
    _simTimer?.cancel();
    _simTimer = null;
    if (!_isSimulationRunning) return;
    _isSimulationRunning = false;
    if (restartLiveTracking && _isRouteConfirmed) _startNavigationTracking();
    _safeSetState(() {});
  }

  void _simStep() {
    _simTimer?.cancel();
    if (!_isSimulationRunning || !mounted || _disposed) return;
    final coords = _fullRouteCoordinates;
    if (coords.length < 2) {
      _stopSimulation(restartLiveTracking: false);
      return;
    }
    final lastIndex = coords.length - 1;
    const speedMs = _simSpeedKmh / 3.6;
    _simDistM += speedMs * (_simTickMs / 1000.0);
    // Vertex-Cursor bis zum Segment, das _simDistM enthält (distanz-interpoliert
    // → konstante 30 km/h egal wie dicht die GraphHopper-Stützpunkte liegen).
    while (_simIndex < lastIndex) {
      final a = coords[_simIndex];
      final b = coords[_simIndex + 1];
      final segLen = geo.Geolocator.distanceBetween(a[1], a[0], b[1], b[0]);
      if (segLen <= 0) {
        _simIndex++;
        continue;
      }
      if (_simDistAtIndexM + segLen >= _simDistM) break;
      _simDistAtIndexM += segLen;
      _simIndex++;
    }
    if (_simIndex >= lastIndex) {
      final end = coords[lastIndex];
      final prev = coords[lastIndex - 1];
      _feedSimPosition(
        end[1],
        end[0],
        calculateBearing(prev[1], prev[0], end[1], end[0]),
      );
      _stopSimulation(restartLiveTracking: false);
      return;
    }
    final a = coords[_simIndex];
    final b = coords[_simIndex + 1];
    final segLen = geo.Geolocator.distanceBetween(a[1], a[0], b[1], b[0]);
    final t = segLen <= 0
        ? 0.0
        : ((_simDistM - _simDistAtIndexM) / segLen).clamp(0.0, 1.0);
    final lat = a[1] + (b[1] - a[1]) * t;
    final lng = a[0] + (b[0] - a[0]) * t;
    _feedSimPosition(lat, lng, calculateBearing(a[1], a[0], b[1], b[0]));
    _simTimer = Timer(const Duration(milliseconds: _simTickMs), _simStep);
  }

  void _feedSimPosition(double lat, double lng, double heading) {
    final pos = geo.Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 4.0,
      altitude: 0.0,
      altitudeAccuracy: 1.0,
      heading: heading,
      headingAccuracy: 5.0,
      speed: _simSpeedKmh / 3.6,
      speedAccuracy: 1.0,
    );
    unawaited(_onLocationUpdate(pos));
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

    final durationSeconds = adjustedResult?.durationSeconds ?? 0;
    final avgKmh = durationSeconds > 0
        ? drivenKm / (durationSeconds / 3600.0)
        : 0.0;
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
      topSpeedKmh: _maxSpeedMps * 3.6,
      // Ø nur plausibel zeigen (≤ Top-Speed, kein Glitch durch Mini-Distanz).
      avgSpeedKmh:
          avgKmh.isFinite && avgKmh > 0 && avgKmh <= _maxSpeedMps * 3.6 + 5
          ? avgKmh
          : 0.0,
    );
  }

  // 2026-06-20 (vucko Gruppen-Exit-Flow): Zeigt das Post-Route-Sheet (gefahrene
  // km + anteiliges XP) und kehrt NUR für Gruppen-Mitglieder NACH dem Schliessen
  // zurück in die Lobby — statt auf der Routensuche-Karte zu stranden. Solo-
  // Fahrten bleiben unverändert (Sheet → Reset auf Setup wie bisher).
  // Ein-Schuss-Schutz: pro Fahrt erscheint NUR EIN Post-Route-Sheet. Sonst
  // stapelten Ankunft + Beenden (oder ein doppelter Trigger) zwei Abschluss-
  // Sheets → der „zweite Post-Screen" aus dem 2-Geräte-Video. Reset für die
  // nächste Fahrt in _startNavigationFlow.
  bool _completionSheetShown = false;
  void _presentCompletionSheet(CruiseCompletionDialog dialog) {
    if (_completionSheetShown) return;
    _completionSheetShown = true;
    unawaited(() async {
      await showCruiseCompletionSheet<void>(context: context, child: dialog);
      if (!mounted || _disposed) return;
      if (widget.groupId != null) {
        await _returnToGroupLobbyFromActiveRoute();
      }
    }());
  }

  void _onRouteCompleted() {
    if (!mounted || _disposed) return;
    // 2026-06-25 (vucko): Fahrt am Ziel abgeschlossen → Gruppe „abschließen".
    // Setzt closed_at, ab dann läuft die 24h-Frist bis Gruppe + Chat per
    // pg_cron gelöscht werden. Idempotent (jedes Mitglied darf es auslösen),
    // fehlertolerant (das Post-Sheet darf nie daran scheitern).
    final groupId = widget.groupId;
    if (groupId != null) {
      unawaited(CruiseGroupService.closeGroup(groupId));
    }
    final snapshot = _buildCompletionSnapshot(
      isEarlyStop: false,
      belowMinimum: _completionProgressBelowXpMinimum(completed: true),
      completed: true,
    );
    _freezeMapForCompletion();
    unawaited(
      _recordRouteCompletionCandidate(completed: true, discarded: false),
    );
    final drivenSnap = _drivenTrackRecorder.snapshot();
    _presentCompletionSheet(
      CruiseCompletionDialog(
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
        topSpeedKmh: snapshot.topSpeedKmh,
        avgSpeedKmh: snapshot.avgSpeedKmh,
        routeStyle: _selectedStyle,
        isRoundTrip: _isRoundTrip,
        onSave: (rating, tags, title, photoUrl) async {
          final result = await _saveRouteAndSyncXp(
            rating: rating,
            ratingTags: tags,
            title: title,
            completed: true,
            photoUrl: photoUrl,
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
    _freezeMapForCompletion();

    final drivenSnap = _drivenTrackRecorder.snapshot();
    _presentCompletionSheet(
      CruiseCompletionDialog(
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
        topSpeedKmh: snapshot.topSpeedKmh,
        avgSpeedKmh: snapshot.avgSpeedKmh,
        isEarlyStop: snapshot.isEarlyStop,
        belowMinimum: snapshot.belowMinimum,
        routeStyle: _selectedStyle,
        isRoundTrip: _isRoundTrip,
        onSave: (rating, tags, title, photoUrl) async {
          final result = await _saveRouteAndSyncXp(
            rating: rating,
            ratingTags: tags,
            title: title,
            photoUrl: photoUrl,
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
    String? photoUrl,
  }) async {
    int? previousLevel;
    int? previousTotalXp;
    var xpAwardedForResult = 0;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('level,total_xp')
            .eq('id', userId)
            .maybeSingle();
        previousLevel = (profile?['level'] as num?)?.toInt();
        previousTotalXp = (profile?['total_xp'] as num?)?.toInt();
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
        xpAwardedForResult = xpBreakdown.totalXp;
        debugPrint(
          '[CruiseMode] Saving route: style=$_selectedStyle, roundTrip=$_isRoundTrip, '
          'distKm=${adjustedResult.distanceKm}, durationSec=${adjustedResult.durationSeconds?.round()}, '
          'progress=${(progressFraction * 100).round()}%, '
          'xp=${xpBreakdown.totalXp}',
        );
        await _recordDriveSessionForCurrentRoute(
          completed: completed,
          photoUrl: photoUrl,
        );
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
          // Foto direkt an die gespeicherte Route hängen → es überlebt die
          // Bereinigung der „zuletzt gefahren"-Sessions (Top-5), weil eine
          // GESPEICHERTE Route ihr Foto unabhängig behält.
          photoUrl: photoUrl,
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
      final oldTotalXp =
          previousTotalXp ??
          math.max(0, gamResult.totalXp - xpAwardedForResult);
      return CruiseCompletionActionResult(
        success: true,
        newBadges: gamResult.newBadges,
        levelUp: previousLevel != null && gamResult.level.level > previousLevel,
        newLevel: gamResult.level.level,
        previousTotalXp: oldTotalXp,
        newTotalXp: gamResult.totalXp,
        xpEarned: xpAwardedForResult,
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

  /// 2026-07-06 (vucko Fahrt-Resume): Snapshot der laufenden SOLO-Fahrt
  /// persistieren. Gruppen (Lobby-Rejoin) und Trips (trips-Tabelle) haben
  /// eigene Resume-Mechanismen und werden bewusst übersprungen.
  void _persistActiveRideSnapshot({
    bool force = false,
    bool paused = false,
    double? lat,
    double? lng,
  }) {
    if (widget.groupId != null || _tripModeEnabled) return;
    final startedAt = _navigationStartTime;
    if (!_isRouteConfirmed || startedAt == null) return;
    final route = _sessionRouteResult ?? _lastRouteResult;
    if (route == null || route.coordinates.length < 2) return;
    final distanceKm =
        route.distanceKm ?? ((route.distanceMeters ?? 0) / 1000.0);
    if (distanceKm <= 0) return;
    final snapshot = ActiveRideSnapshot(
      savedAt: DateTime.now(),
      startedAt: startedAt,
      style: _selectedStyle,
      distanceKm: distanceKm,
      geometry: route.geometry,
      isRoundTrip: _isRoundTrip,
      durationSeconds: route.durationSeconds,
      drivenKm: _totalDistanceDriven / 1000.0,
      elapsedSeconds: DateTime.now().difference(startedAt).inSeconds,
      wasPaused: paused,
      lastLat: lat,
      lastLng: lng,
    );
    unawaited(
      force
          ? ActiveRideSnapshotService.save(snapshot)
          : ActiveRideSnapshotService.saveThrottled(snapshot),
    );
  }

  Future<void> _recordDriveSessionForCurrentRoute({
    required bool completed,
    String? photoUrl,
  }) async {
    // 2026-07-06 (vucko Fahrt-Resume): Die Fahrt endet hier durch bewusste
    // User-Aktion (Beenden/Verwerfen/Speichern) — Resume-Snapshot entfernen,
    // sonst bietet der Homescreen eine bereits abgeschlossene Fahrt an.
    unawaited(ActiveRideSnapshotService.clear());
    if (_driveSessionRecordedForCompletion) {
      // Session wurde bereits (über einen anderen Pfad) aufgenommen — ein Foto,
      // das der User erst im Abschluss-Sheet hinzufügt, nachtragen (greift dank
      // der drive-session UPDATE-Policy auf photo_url).
      if (photoUrl != null &&
          photoUrl.isNotEmpty &&
          _recordedDriveSessionId != null) {
        await GamificationService.updateDriveSessionPhoto(
          _recordedDriveSessionId!,
          photoUrl,
        );
      }
      return;
    }
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
    final recordedSession = await GamificationService.recordDriveSession(
      distanceKm: drivenKm,
      durationSeconds: adjustedResult.durationSeconds?.round() ?? 0,
      completedAtEnd: completed,
      routeStyle: _selectedStyle,
      routeType: _isRoundTrip ? 'ROUND_TRIP' : 'POINT_TO_POINT',
      routeFingerprint: adjustedResult.edgeMeta['route_fingerprint']
          ?.toString(),
      xpAwarded: xpBreakdown.totalXp,
      // 2026-06-23 (vucko X3): Gruppen-Fahrt taggen + Top-Speed mitschreiben
      // -> speist die deterministische Gruppen-Rangliste in der Lobby.
      groupId: widget.groupId,
      topSpeedKmh: _maxSpeedMps * 3.6,
      // 2026-06-25 (vucko Routen-Detail-Page): den GEFAHRENEN Track mitspeichern
      // → die Detailseite zeigt die echte gefahrene Strecke akkurat (wie Strava).
      trackGeometry: _drivenTrackRecorder.snapshot().coordinates,
      // 2026-06-25 (vucko Foto-Persistenz): Foto aus dem Abschluss-Sheet direkt
      // beim Insert mitspeichern → erscheint sofort in „zuletzt gefahren",
      // Detailseite, Share (verschwindet nicht mehr).
      photoUrl: photoUrl,
    );
    _recordedDriveSessionId = recordedSession?.id;
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
      // ZWISCHENSPEICHERN: Trip wird pausiert und kann später von der
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
    this.topSpeedKmh = 0,
    this.avgSpeedKmh = 0,
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
  // 2026-06-23 (vucko Post-Route Top-Speed).
  final double topSpeedKmh;
  final double avgSpeedKmh;
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

