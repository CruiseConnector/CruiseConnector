import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:latlong2/latlong.dart';

import '../../core/input_limits.dart';
import '../../data/services/cruise_group_service.dart';
import '../../data/services/gamification_service.dart';
import '../../data/services/geocoding_service.dart';
import '../../data/services/group_route_data_builder.dart';
import '../../data/services/route_service.dart';
import '../../data/services/saved_routes_service.dart';
import '../../domain/models/place_suggestion.dart';
import '../../domain/models/route_result.dart';
import '../../domain/models/saved_route.dart';
import '../widgets/start_zeit_sheet.dart';
import '../widgets/top_toast.dart';
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
  String _selectedLength = '50 km';
  String _selectedLocation = 'Aktueller Standort';
  String _selectedStyle = 'Sport Mode';
  String _planningType = 'Zufall';
  String _selectedDetour = 'Direkt';
  String _selectedVisibility = 'Öffentlich (Für jeden)';
  DateTime? _selectedDateTime;
  // 2026-08-09 (vucko): Karte aufziehbar + Rücksprung zur Karte nach dem
  // Generieren. Vorher war sie fest 280 px hoch und beim Einstellen weg.
  final ScrollController _scrollCtrl = ScrollController();
  /// Sind die Einstellungen weggedrueckt (Karte im Vollbild)?
  ///
  /// 2026-08-11 (vucko): „im Idealfall, dass es wie bei der Single-Cruise-
  /// Mode-Page ist und man das einfach wegdruecken kann und die Karte im
  /// Vollscreen hat." Nach einer erfolgreichen Generierung klappt die Seite
  /// von selbst ein, damit man die frisch gezeichnete Route ganz sieht.
  bool _configEingeklappt = false;

  bool _isRoundTrip = true;
  bool _avoidHighways = false;
  PlaceSuggestion? _selectedDestination;

  // Map-State
  LatLng? _startPoint;
  final List<LatLng> _roundTripWaypoints = [];
  List<LatLng> _routeLatLngs = [];

  /// Zeichen-Animation der frisch generierten Route.
  ///
  /// 2026-08-11 (vucko „man bekommt keine Animation, wie die Strecke verlaeuft
  /// auf der Karte"): Uebernommen aus der Single-Cruise-Seite
  /// (_startRouteDrawAnimation) — dasselbe bewaehrte Verfahren, damit sich
  /// beide Seiten gleich anfuehlen. Der Zaehler ist der Abbruch-Schalter: Jede
  /// neue Route (oder das Verlassen der Seite) erhoeht ihn, laufende Ticks
  /// erkennen daran, dass sie veraltet sind, und legen sich hin. Ohne das
  /// wuerde ein alter Timer eine geloeschte Route zurueckschreiben.
  Timer? _routeZeichenTimer;
  int _routeZeichenToken = 0;
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
    // Zuerst: laufende Zeichnung stoppen. Ein Tick nach dem Abbau wuerde
    // setState auf einem toten Widget rufen.
    _brichRoutenZeichnungAb();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    _destinationCtrl.dispose();
    _scrollCtrl.dispose();
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
      throw Exception('Die Berechtigung für den Standort fehlt.');
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
              : 'Im Trip sind höchstens 5 Stopps möglich.',
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
    // Die Karte rahmt die VOLLE Route ein, bevor die Animation laeuft — sonst
    // wandert der Ausschnitt waehrend des Zeichnens.
    _fitRouteBounds(coords);
    // Nach dem Generieren zurueck zur Karte: Wer unten im Formular steht, sieht
    // die frische Route sonst gar nicht. Genau das war Vuckos Beschwerde,
    // er konnte "nicht nachschauen, wo das Problem ist".
    _scrollToMap();
    // Einstellungen wegdruecken, damit die frisch gezeichnete Route im
    // Vollbild zu sehen ist — genau das war Vuckos Wunsch: „im Idealfall,
    // dass man das einfach wegdruecken kann und die Karte im Vollscreen hat".
    // Kurz verzoegert, damit das Einklappen nicht mit dem Einrahmen der Karte
    // um denselben Frame kaempft.
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() => _configEingeklappt = true);
    });
    _starteRoutenZeichnung(coords);
  }

  /// Soll die Route gezeichnet werden statt einfach zu erscheinen?
  ///
  /// Kurze Routen wirken beim Zeichnen zappelig, deshalb erst ab 12 Punkten.
  /// Und wer in den Systemeinstellungen Animationen abgeschaltet oder einen
  /// Screenreader an hat, bekommt die Route sofort — Bedienungshilfen gehen
  /// vor Effekt.
  bool _sollRouteZeichnen(List<LatLng> punkte) {
    if (punkte.length < 12) return false;
    final media = MediaQuery.maybeOf(context);
    if (media == null) return true;
    return !media.disableAnimations && !media.accessibleNavigation;
  }

  /// Zeichnet die Route in ~2,4 s von vorne nach hinten auf die Karte.
  void _starteRoutenZeichnung(List<LatLng> ziel) {
    _brichRoutenZeichnungAb();
    if (!mounted || !_sollRouteZeichnen(ziel)) return;

    _routeZeichenToken++;
    final token = _routeZeichenToken;
    final start = DateTime.now();
    const dauer = Duration(milliseconds: 2400);

    setState(() => _routeLatLngs = ziel.take(2).toList(growable: false));

    _routeZeichenTimer = Timer.periodic(const Duration(milliseconds: 33), (
      timer,
    ) {
      if (!mounted || token != _routeZeichenToken) {
        timer.cancel();
        return;
      }
      final vergangen = DateTime.now().difference(start).inMilliseconds;
      final roh = (vergangen / dauer.inMilliseconds).clamp(0.0, 1.0);
      final weich = Curves.easeInOutCubic.transform(roh);
      final sichtbar = math
          .max(2, (ziel.length * weich).ceil())
          .clamp(2, ziel.length)
          .toInt();
      setState(
        () => _routeLatLngs = ziel.take(sichtbar).toList(growable: false),
      );
      if (roh >= 1.0) {
        timer.cancel();
        // Zum Schluss die volle Liste setzen, damit am Ende garantiert die
        // echte Route steht und nicht eine um Rundungsfehler gekuerzte.
        setState(() => _routeLatLngs = List<LatLng>.from(ziel));
      }
    });
  }

  /// Bricht eine laufende Zeichnung ab. MUSS vor jedem Leeren der Route und
  /// beim Verlassen der Seite gerufen werden — sonst schreibt ein alter Tick
  /// die geloeschte Route zurueck.
  void _brichRoutenZeichnungAb() {
    _routeZeichenToken++;
    _routeZeichenTimer?.cancel();
    _routeZeichenTimer = null;
  }

  /// Scrollt den Kopf mit der Karte wieder ins Bild.
  void _scrollToMap() {
    if (!mounted || !_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  // 2026-07-03 (vucko Gruppe-mit-gespeicherter-Route, Geräte-Video 07-03): Statt
  // jedes Mal neu zu generieren, kann der Ersteller eine bereits GESPEICHERTE
  // eigene Route als Gruppen-Route übernehmen. Die SavedRoute wird 1:1 in ein
  // RouteResult konvertiert (identische Geometrie) und über denselben Pfad wie
  // eine frisch generierte Route akzeptiert → landet unverändert im
  // GroupRouteDataBuilder, kein Eingriff in den Gruppen-Erstell-Pfad nötig.
  Future<void> _useSavedRoute() async {
    if (_isGenerating) return;
    List<SavedRoute> library;
    try {
      library = await SavedRoutesService.getSavedRouteLibrary();
    } catch (_) {
      _showError('Gespeicherte Routen konnten nicht geladen werden.');
      return;
    }
    if (!mounted) return;
    if (library.isEmpty) {
      _showError('Du hast noch keine gespeicherte Route.');
      return;
    }
    final picked = await showModalBottomSheet<SavedRoute>(
      context: context,
      backgroundColor: const Color(0xFF15181F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _SavedRoutePickerSheet(routes: library),
    );
    if (picked == null || !mounted) return;

    final result = _savedRouteToResult(picked);
    if (result == null) {
      _showError('Diese Route hat zu wenige Punkte.');
      return;
    }
    setState(() {
      _isRoundTrip = picked.isRoundTrip;
      _selectedStyle = picked.style;
    });
    try {
      await _acceptGeneratedRoute(
        result,
        targetKm: picked.distanceKm.round(),
        waypointSignature: null,
      );
      if (mounted) {
        setState(() => _routeStatusText = 'Gespeicherte Route übernommen');
      }
    } catch (e) {
      _showError(
        e is RouteServiceException
            ? e.userMessage
            : 'Route konnte nicht übernommen werden.',
      );
    }
  }

  RouteResult? _savedRouteToResult(SavedRoute route) {
    final geometry = route.geometry;
    final coordsRaw = (geometry['coordinates'] as List?) ?? const [];
    final coordinates = coordsRaw
        .whereType<List>()
        .where((c) => c.length >= 2)
        .map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
        .toList();
    if (coordinates.length < 2) return null;
    return RouteResult(
      geoJson: json.encode(geometry),
      geometry: geometry,
      coordinates: coordinates,
      maneuvers: const [],
      distanceMeters: route.distanceKm * 1000,
      durationSeconds: route.durationSeconds,
      distanceKm: route.distanceKm,
      edgeMeta: {
        'route_source': 'saved',
        'source': 'saved',
        'saved_route_id': route.id,
        'explicit_route_handoff': true,
      },
    );
  }

  Widget _buildUseSavedRouteButton() {
    // 2026-07-03 (vucko): Solide, klar sichtbare Karte statt fast transparentem
    // OutlinedButton. Der Button sitzt im scrollbaren Formular-Body (nicht in der
    // transparenten Bottom-Bar) → garantiert gelayoutet + sichtbar auf jedem
    // Gerät. Nutzer kann statt „neu generieren" eine gespeicherte Route übernehmen.
    final accent = AppAccentColors.accent;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isGenerating ? null : _useSavedRoute,
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: const Color(0xFF1C1F26),
          disabledBackgroundColor: const Color(0xFF14161C),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: accent.withValues(alpha: 0.55)),
          ),
        ),
        icon: Icon(Icons.bookmark_rounded, size: 20, color: accent),
        label: const Text(
          'Gespeicherte Route verwenden',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }

  Future<RouteResult?> _pollRoundTripSearchSession(
    String sessionId, {
    required int generationId,
  }) async {
    DateTime? lastKickAt;
    for (var poll = 0; poll < 30; poll += 1) {
      if (!_isCurrentGeneration(generationId)) return null;
      if (mounted) {
        setState(() => _routeStatusText = 'Wir prüfen mehrere Varianten');
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
    // 2026-08-18 (Defekt 3): Hier stand ein stummes `return`. Wenn das Sheet
    // false lieferte — und das tat es seit dem 14.08. für jeden
    // Bestandsnutzer —, passierte auf Knopfdruck gar nichts: keine Meldung,
    // kein Sheet, kein Fehler. Jeder Ausstieg sagt jetzt, warum.
    final acceptedSafety = await showGroupSafetyNoticeSheet(context);
    if (!acceptedSafety) {
      _showError(
        'Ohne Bestätigung der Hinweise zur Gruppenfahrt können wir keine Gruppe '
        'anlegen. Du findest sie jederzeit unter Einstellungen.',
      );
      return;
    }
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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GroupLobbyPage(groupId: groupId)),
      );
      unawaited(GamificationService.calculateAndSync());
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
      _brichRoutenZeichnungAb();
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
      _brichRoutenZeichnungAb();
      _routeLatLngs = [];
      if (planningType == 'Zufall') {
        _roundTripWaypoints.clear();
        _selectedWaypointIndex = null;
        _replaceWaypointIndex = null;
        _waypointOrigin = 'manual';
        _waypointSeedAttempt = 0;
      }
      // Wegpunkte setzt man AUF der Karte — Panel einklappen und Karte
      // freigeben, wie es die Cruise-Seite bei Karten-Aktionen macht.
      if (planningType == 'Wegpunkte') {
        _configEingeklappt = true;
      }
    });
    if (planningType == 'Wegpunkte' && mounted) {
      TopToast.show(
        context,
        message: 'Tippe auf die Karte, um deine Stopps zu setzen',
        icon: Icons.touch_app_rounded,
        duration: const Duration(milliseconds: 2600),
      );
    }
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
        _brichRoutenZeichnungAb();
        _routeLatLngs = [];
      });
    }
  }

  void _setWaypointFromMap(LatLng point) {
    final replaceIndex = _replaceWaypointIndex;
    var hitWaypointLimit = false;
    setState(() {
      _lastRoute = null;
      _brichRoutenZeichnungAb();
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
      _brichRoutenZeichnungAb();
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
      _brichRoutenZeichnungAb();
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
      _brichRoutenZeichnungAb();
      _routeLatLngs = [];
    });
  }

  void _replaceSelectedWaypoint() {
    final index = _selectedWaypointIndex;
    if (index == null || index < 0 || index >= _roundTripWaypoints.length) {
      return;
    }
    setState(() {
      _replaceWaypointIndex = index;
      // Karte freigeben, BEVOR wir zum Tippen auffordern — sonst verdeckt das
      // solide Panel genau die Flaeche, auf die getippt werden soll. Dieselbe
      // Regel gilt fuer den Wegpunkte-Modus und „Standort waehlen".
      _configEingeklappt = true;
    });
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
        _brichRoutenZeichnungAb();
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
          // Die Karte steht GENAU EINMAL im Baum und wandert nie in einen
          // anderen Teilbaum. Wuerde sie beim Umschalten neu gebaut, zeigte
          // _mapController auf den alten, toten Controller — die Karte wuerde
          // frische Routen dann stillschweigend nicht mehr einrahmen.
          Positioned.fill(child: RepaintBoundary(child: _buildMap())),

          // Einstellungen: da oder weggedrueckt. Dasselbe Zwei-Zustands-Muster
          // wie in der Single-Cruise-Seite.
          RepaintBoundary(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.06),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              // Ohne eigenen layoutBuilder legt AnimatedSwitcher die beiden
              // Zustaende zentriert uebereinander — der Inhalt wuerde beim
              // Wechseln springen.
              layoutBuilder: (aktuell, vorige) => Stack(
                fit: StackFit.expand,
                children: [...vorige, if (aktuell != null) aktuell],
              ),
              child: _configEingeklappt
                  ? _buildVollbildLeiste()
                  : _buildEinstellungsBlatt(),
            ),
          ),

          if (_isGenerating) _buildRouteGenerationStatus(),
          _buildKopfKnoepfe(),
        ],
      ),
    );
  }

  /// Die Einstellungen — 1:1 das Muster der Single-Cruise-Seite.
  ///
  /// 2026-08-11 (vucko): „es soll nicht transparent sein, es soll wie bei der
  /// Single-Cruise-Mode-Page sein ... einfach von der Cruise-Mode-Page
  /// uebernommen werden, nur halt dass es die Einstellungen vom Gruppenfeature
  /// auch hat." Uebernommen ist deshalb exakt deren Aufbau (dort
  /// _buildConfigOverlay, Zustand config_expanded): oben ein schmaler
  /// Kartenstreifen mit Griff — Tipp oder Runterwischen klappt ein —, darunter
  /// das SOLIDE Panel (0xFF0B0E14) mit allen Einstellungen. Karten-Aktionen
  /// („Auf Karte tippen", Wegpunkte) klappen das Panel zuerst ein, genau wie
  /// _beginPickStartOnMap auf der Cruise-Seite: Karte freigeben fuer den Tap.
  Widget _buildEinstellungsBlatt() {
    final safeTop = MediaQuery.of(context).padding.top;
    return Stack(
      key: const ValueKey('einstellungen_offen'),
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            // Overscroll am Listenanfang = Runterwischen -> einklappen.
            if (n is OverscrollNotification && n.overscroll < -6) {
              _versteckeEinstellungen();
              return true;
            }
            return false;
          },
          child: CustomScrollView(
            controller: _scrollCtrl,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Schmaler Kartenstreifen mit Griff, wie auf der Cruise-Seite.
              SliverToBoxAdapter(
                child: GestureDetector(
                  onTap: _versteckeEinstellungen,
                  onVerticalDragUpdate: (d) {
                    if ((d.primaryDelta ?? 0) > 4) _versteckeEinstellungen();
                  },
                  onVerticalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) > 60) {
                      _versteckeEinstellungen();
                    }
                  },
                  child: Container(
                    height: safeTop + 64,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xFF0B0E14)],
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Das solide Panel mit allen Einstellungen — nichts scheint durch.
              SliverToBoxAdapter(
                child: Container(
                  color: const Color(0xFF0B0E14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_lastRoute != null) _buildRouteStats(),

                      CruiseSetupCard(
                        // 2026-08-18 (vucko, Aufnahme 07): "Wenn man eine
                        // Gruppe erstellen will, verschwinden die Routentypen
                        // - also entweder Rundkurs oder A nach B verschwindet
                        // auf einmal."
                        //
                        // Diese Seite darf die prozessweit eindeutigen
                        // Tutorial-GlobalKeys NICHT beanspruchen: Die
                        // Cruise-Seite bleibt gleichzeitig im Baum
                        // (home_page.dart baut die Tabs als IndexedStack), und
                        // zwei lebende Widgets mit demselben GlobalKey
                        // loeschen sich im Release-Build still gegenseitig aus
                        // dem Baum. Das Tutorial fuehrt ohnehin nur durch den
                        // Cruise-Tab; hier gibt es keinen einzigen Schritt.
                        tutorialZieleRegistrieren: false,
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
                            _brichRoutenZeichnungAb();
                            _routeLatLngs = [];
                          });
                        },
                        onLocationChanged: (value) async {
                          setState(() {
                            _selectedLocation = value;
                            // Startpunkt setzt man AUF der Karte — Panel
                            // einklappen (Cruise-Muster: „Karte freigeben
                            // fuer den Tap").
                            if (value == 'Standort wählen') {
                              _configEingeklappt = true;
                            }
                          });
                          if (value == 'Standort wählen' && mounted) {
                            TopToast.show(
                              context,
                              message:
                                  'Tippe auf die Karte für deinen Startpunkt',
                              icon: Icons.touch_app_rounded,
                              duration: const Duration(milliseconds: 2600),
                            );
                          }
                          if (value == 'Aktueller Standort') {
                            await _tryLocateUser();
                          }
                        },
                        onStyleChanged: (value) {
                          setState(() {
                            _selectedStyle = value;
                            _lastRoute = null;
                            _brichRoutenZeichnungAb();
                            _routeLatLngs = [];
                          });
                        },
                        onDestinationSelected: (suggestion) {
                          setState(() {
                            _selectedDestination = suggestion;
                            _destinationCtrl.text = suggestion.placeName;
                            _lastRoute = null;
                            _brichRoutenZeichnungAb();
                            _routeLatLngs = [];
                          });
                        },
                        onDestinationCleared: () {
                          setState(() {
                            _selectedDestination = null;
                            _destinationCtrl.clear();
                            _lastRoute = null;
                            _brichRoutenZeichnungAb();
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
                            _brichRoutenZeichnungAb();
                            _routeLatLngs = [];
                          });
                        },
                        selectedAvoidHighways: _avoidHighways,
                        onAvoidHighwaysChanged: (value) {
                          setState(() {
                            _avoidHighways = value;
                            _lastRoute = null;
                            _brichRoutenZeichnungAb();
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
                      _buildUseSavedRouteButton(),
                      const SizedBox(height: 16),
                      _buildStartAddressHelper(),
                      if (_selectedLocation == 'Adresse') ...[
                        const SizedBox(height: 12),
                        _buildAddressField(),
                      ],
                      const SizedBox(height: 40),
                      const Text(
                        'Details zur Gruppe',
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
                      const SizedBox(height: 28),
                      // Die Aktionsknoepfe stehen IM Formular, nicht darueber.
                      // Als schwebende Leiste deckten sie auf kleinen
                      // Bildschirmen die Modus-Chips zu (gemessen: Chips bei
                      // y=549, Leiste ab y=521 bei 800x600).
                      _buildBottomBar(schwebend: false),
                      SizedBox(
                        height: MediaQuery.of(context).padding.bottom + 16,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            ),
          ),
      ],
    );
  }

  /// Karte im Vollbild — unten nur eine schmale Leiste zum Zurueckholen.
  Widget _buildVollbildLeiste() {
    final accent = AppAccentColors.accent;
    return Stack(
      key: const ValueKey('einstellungen_weg'),
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xFF0B0E14), Colors.transparent],
                stops: [0.45, 1.0],
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              28,
              20,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Griff: macht ohne Worte klar, dass hier etwas hochgezogen
                // werden kann.
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                const SizedBox(height: 16),
                if (_lastRoute != null) ...[
                  _buildRouteStats(),
                  const SizedBox(height: 14),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(27),
                      ),
                    ),
                    onPressed: _zeigeEinstellungen,
                    icon: const Icon(Icons.tune_rounded, size: 20),
                    label: const Text(
                      'Gruppe einstellen',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Auch nach oben wischen holt die Einstellungen zurueck.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 120,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragUpdate: (d) {
              if ((d.primaryDelta ?? 0) < -6) _zeigeEinstellungen();
            },
          ),
        ),
      ],
    );
  }

  /// Zurueck-Knopf und der Schalter zum Wegdruecken.
  Widget _buildKopfKnoepfe() {
    final oben = MediaQuery.of(context).padding.top + 8;
    return Positioned(
      top: oben,
      left: 8,
      right: 8,
      child: Row(
        children: [
          _rundKnopf(
            icon: Icons.arrow_back,
            tooltip: 'Zurueck',
            onTap: () => Navigator.pop(context),
          ),
          const Spacer(),
          _rundKnopf(
            icon: _configEingeklappt
                ? Icons.tune_rounded
                : Icons.map_outlined,
            tooltip: _configEingeklappt
                ? 'Einstellungen zeigen'
                : 'Karte im Vollbild',
            onTap: _configEingeklappt
                ? _zeigeEinstellungen
                : _versteckeEinstellungen,
          ),
        ],
      ),
    );
  }

  Widget _rundKnopf({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onTap,
      ),
    );
  }

  void _versteckeEinstellungen() {
    if (_configEingeklappt) return;
    HapticFeedback.selectionClick();
    setState(() => _configEingeklappt = true);
  }

  void _zeigeEinstellungen() {
    if (!_configEingeklappt) return;
    HapticFeedback.selectionClick();
    setState(() => _configEingeklappt = false);
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
          // 2026-08-09 (vucko, „man kann oben in der Karte nicht bewegen"):
          // Diese Karte sitzt im Kopf eines CustomScrollView. Ohne eigene
          // Gesten-Erkenner bekommt sie nur, was der Scroll-View übrig lässt —
          // und der beansprucht jedes vertikale Ziehen. Ergebnis: Die Seite
          // scrollt, die Karte steht still. Mit `eagerGestures` gewinnt die
          // Karte die Geste sofort und lässt sich verschieben und zoomen.
          // Gescrollt wird stattdessen über den Bereich UNTER der Karte.
          eagerGestures: true,
        ),
        if (_isWaypointPlanning) _buildWaypointActionOverlay(),
      ],
    );
  }

  void _handleMapReady(CruiseMapLibreController controller) {
    _mapController = controller;
    // 2026-08-11, Fund der Gegenpruefung: Hier stand frueher _routeLatLngs —
    // also das, was GERADE gezeichnet ist. onStyleLoaded kann auf iOS
    // mehrfach feuern (siehe cruise_maplibre_map.dart), etwa wenn nach dem
    // Kameraschwenk neue Kacheln laden. Faellt das in die 2,4 s der
    // Zeichenanimation, enthaelt _routeLatLngs erst ein Anfangsstueck — die
    // Karte haette auf ein Routen-Fragment gezoomt. _lastRoute ist immer
    // vollstaendig.
    final volleRoute = _lastRoute?.coordinates
        .map((c) => LatLng(c[1], c[0]))
        .toList(growable: false);
    final zumEinrahmen = (volleRoute != null && volleRoute.length >= 2)
        ? volleRoute
        : _routeLatLngs;
    if (zumEinrahmen.length >= 2) {
      _fitRouteBounds(zumEinrahmen);
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

  /// Die Karten-Aktionen fuer Stopps.
  ///
  /// 2026-08-11, Korrektur nach der Gegenpruefung: Frueher lag die Karte in
  /// einem 280 px hohen Kopf, „mittig" hiess also mittig im Kartenkopf. Seit
  /// die Karte den ganzen Bildschirm fuellt, landete dieselbe Ausrichtung in
  /// der BILDSCHIRMmitte — bei offenen Einstellungen also hinter dem
  /// undurchsichtigen Formular. Die Setup-Karte verweist woertlich auf „die
  /// Karten-Aktionen rechts", die dort gar nicht mehr zu sehen waren.
  /// Jetzt haengen sie oben im sichtbaren Kartenstreifen.
  Widget _buildWaypointActionOverlay() {
    final oben = _configEingeklappt
        ? MediaQuery.of(context).padding.top + 64
        : MediaQuery.of(context).padding.top + 56;
    return Positioned(
      top: oben,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 2026-08-12 (vucko: „kann man den Wegpunkte-Modus nicht im
            // Gruppenmodus gut verwenden?"). Bis hierher konnte man einen
            // Stopp zwar antippen und auswaehlen — danach gab es aber keine
            // einzige Aktion dafuer. _replaceSelectedWaypoint und
            // _deleteSelectedWaypoint existierten, waren aber nie mit einem
            // Knopf verbunden. Nur „Letzten loeschen" und „Alle loeschen"
            // waren erreichbar; einen BESTIMMTEN Stopp zu aendern ging nicht.
            //
            // Die beiden Knoepfe erscheinen nur bei ausgewaehltem Stopp,
            // damit die Leiste sonst nicht zuwaechst.
            if (_selectedWaypointIndex != null) ...[
              _buildMapActionButton(
                icon: Icons.edit_location_alt_outlined,
                label: 'Stopp ${_selectedWaypointIndex! + 1} verschieben',
                onTap: _replaceSelectedWaypoint,
              ),
              const SizedBox(height: 10),
              _buildMapActionButton(
                icon: Icons.wrong_location_outlined,
                label: 'Stopp ${_selectedWaypointIndex! + 1} löschen',
                onTap: _deleteSelectedWaypoint,
              ),
              const SizedBox(height: 10),
            ],
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
                    'Startzeit',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'optional',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
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
                          : 'Spontan',
                      style: TextStyle(
                        color: _selectedDateTime != null
                            ? Colors.white
                            : Colors.white54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // Zuruecksetzen: Ohne diesen Weg waere eine einmal gesetzte
                  // Zeit fuer immer fest — das Feld ist ja optional.
                  if (_selectedDateTime != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Colors.white38,
                        ),
                        tooltip: 'Startzeit entfernen',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedDateTime = null);
                        },
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

  /// Die Aktionsknoepfe.
  ///
  /// 2026-08-11, Korrektur nach der Gegenpruefung: Frueher schwebte diese
  /// Leiste als Positioned ueber dem Formular. Auf kleinen Bildschirmen (im
  /// Test 800x600) deckte sie die Modus-Chips zu — gemessen: Chips bei y=549,
  /// Leiste ab y=521. Ein Tipp auf „A nach B" landete auf der Leiste. Jetzt
  /// steht sie am Ende des Formulars und kann nichts mehr verdecken.
  Widget _buildBottomBar({bool schwebend = true}) {
    final canCreate = _canCreateGroup;
    // 2026-08-12 (vucko): „Der Generier-Knopf ist bei der Gruppenseite nicht
    // zentriert und unten sieht es komisch aus."
    //
    // Die Leiste war urspruenglich eine SCHWEBENDE Leiste ueber der Karte und
    // hat das nach dem Umbau ins Formular mitgeschleppt: einen schwarzen
    // Verlauf (der ueber der Karte Sinn ergibt, im soliden Panel aber wie ein
    // Schmutzrand aussieht), noch einmal 20 Punkte Seitenrand OBWOHL das Panel
    // schon 20 hat — dadurch standen die Knoepfe schmaler und nach innen
    // versetzt als alles darueber — und 40 Punkte Leerraum unten, die im
    // Formular als Loch erschienen.
    //
    // Schwebend bleibt alles wie gehabt, eingebettet fallen Verlauf und
    // doppelter Rand weg.
    final inhalt = Container(
        decoration: schwebend
            ? BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.9),
                    Colors.transparent,
                  ],
                  stops: const [0.6, 1.0],
                ),
              )
            : null,
        padding: schwebend
            ? const EdgeInsets.fromLTRB(20, 20, 20, 40)
            : EdgeInsets.zero,
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
    );
    if (!schwebend) return inhalt;
    return Positioned(bottom: 0, left: 0, right: 0, child: inhalt);
  }

  bool get _canCreateGroup {
    return _lastRoute != null &&
        _nameCtrl.text.trim().isNotEmpty &&
        _nameCtrl.text.trim().length <= AppInputLimits.groupNameMaxLength &&
        _descCtrl.text.trim().length <=
            AppInputLimits.groupDescriptionMaxLength &&
        // 2026-08-11 (vucko „ich moechte, dass man nicht zwingend eine Uhrzeit
        // bzw. ein Datum einstellen muss. Das soll zusaetzlich sein."):
        // Startzeit ist bewusst KEINE Bedingung mehr. Ohne Zeit gilt die
        // Gruppe als spontan. Die Spalte groups.start_time ist nullable und
        // CruiseGroupService.create nimmt sie bereits als DateTime? entgegen.
        _maxPeople.round() >= 2;
  }

  /// Ein Blatt statt zweier System-Dialoge.
  ///
  /// 2026-08-11 (vucko „die Datum-/Uhrzeiteinstellung soll wesentlich
  /// aesthetischer aussehen und nicht so verklemmt"): Vorher poppte erst ein
  /// Kalenderblatt auf, danach eine Zifferblatt-Uhr — beide im Material-
  /// Standard, beide ohne Bezug zum App-Design. Jetzt ein Blatt mit Tagesleiste,
  /// Schnellwahl und Drehrad; „ohne feste Zeit" ist dort ein eigener Weg.
  Future<void> _selectTime() async {
    final wahl = await zeigeStartZeitSheet(context, aktuell: _selectedDateTime);
    // null = abgebrochen: dann bleibt alles, wie es war.
    if (wahl == null || !mounted) return;
    setState(() => _selectedDateTime = wahl.zeitpunkt);
  }

  String _formatDateTime(DateTime dt) {
    final jetzt = DateTime.now();
    final heute = DateTime(jetzt.year, jetzt.month, jetzt.day);
    final tag = DateTime(dt.year, dt.month, dt.day);
    final abstand = tag.difference(heute).inDays;
    final t =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    // „Heute 18:00" liest sich schneller als „11.08. 18:00".
    if (abstand == 0) return 'Heute $t';
    if (abstand == 1) return 'Morgen $t';
    final d =
        '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.';
    return '$d $t';
  }
}

/// 2026-07-03 (vucko Gruppe-mit-gespeicherter-Route): Auswahl-Sheet für die
/// gespeicherten Routen des Users. Tap → gibt die SavedRoute zurück.
class _SavedRoutePickerSheet extends StatelessWidget {
  const _SavedRoutePickerSheet({required this.routes});

  final List<SavedRoute> routes;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Gespeicherte Route wählen',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: routes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final r = routes[i];
                  final title = (r.name != null && r.name!.trim().isNotEmpty)
                      ? r.name!.trim()
                      : (r.isRoundTrip ? 'Rundkurs' : 'A → B');
                  final subtitle =
                      '${r.distanceKm.toStringAsFixed(1)} km · ${r.isRoundTrip ? 'Rundkurs' : 'A → B'} · ${r.style}';
                  return Material(
                    color: const Color(0xFF1C2028),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).pop(r),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
                                Icons.route_rounded,
                                color: accent,
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
