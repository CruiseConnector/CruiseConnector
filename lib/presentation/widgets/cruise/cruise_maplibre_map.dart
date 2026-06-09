import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart' as mb;
import 'package:visibility_detector/visibility_detector.dart';

import 'package:cruise_connect/data/services/map_style_service.dart';

/// Ein Marker, der als echtes Flutter-Widget über der MapLibre-Karte schwebt.
///
/// Bewusst KEINE Konvertierung zu GL-Symbolen: so bleiben alle bestehenden
/// Marker-Widgets aus cruise_mode_page (Puck, POI, Waypoint-Badge,
/// Gruppen-Avatar …) 1:1 erhalten. Die Bildschirmposition wird via
/// `toScreenLocationBatch` projiziert und bei Kamerabewegung neu berechnet.
class CruiseMapMarker {
  const CruiseMapMarker({
    required this.id,
    required this.position,
    required this.child,
    this.width = 40,
    this.height = 40,
    this.alignment = Alignment.center,
  });

  /// Stabile ID (für effizientes Diffing der Overlay-Children).
  final String id;
  final ll.LatLng position;
  final Widget child;
  final double width;
  final double height;

  /// Ankerpunkt: center = Marker-Mitte auf der Koordinate,
  /// bottomCenter = Spitze unten (z. B. Pin), topCenter = Spitze oben.
  final Alignment alignment;
}

/// Eine Polylinie auf der Karte (GL-gerendert, scharf + flüssig).
class CruiseMapLine {
  const CruiseMapLine({
    required this.points,
    required this.color,
    this.width = 5,
    this.opacity = 1.0,
    this.blur = 0,
  });

  final List<ll.LatLng> points;
  final Color color;
  final double width;
  final double opacity;
  final double blur;
}

/// Steuer-Handle für die Kamera — bildet die wenigen MapController-Aufrufe aus
/// cruise_mode_page nach (move / moveAndRotate / fitCamera).
class CruiseMapLibreController {
  CruiseMapLibreController._(this._map);
  final mb.MapLibreMapController _map;

  /// Sichtbarkeit — vom Widget mit dem VisibilityDetector synchron gehalten.
  /// Ist die Karte offstage (false), werden ALLE Kamera-/View-Calls
  /// übersprungen. Sonst würde MapLibre auf die unsichtbare native View nativ
  /// werfen (SIGABRT, von Dart nicht fangbar → App-Crash).
  bool active = true;

  // 2026-06-05 (vucko Crash-Fix #2): Erst NACH dem ersten gerenderten Frame
  // dürfen view-abhängige native Calls (Kamera/Projektion/getVisibleRegion)
  // laufen. Vorher hat MapLibre auf dem Gerät beim ersten Cruise-Öffnen
  // intermittierend synchron eine C++-Exception in onMethodCall geworfen
  // (uncatchbar → SIGABRT). Kamera-Wünsche, die vor dem ersten Frame kommen
  // (z. B. initiale GPS-Zentrierung aus _onMapReady), werden NICHT verworfen,
  // sondern als „letzter Wunsch" gepuffert und beim ersten Frame angewandt.
  bool firstFrameReady = false;
  Future<void> Function()? _pendingCamera;

  /// Vom Widget aufgerufen, sobald der Renderer den ersten Frame produziert hat.
  void markFirstFrameReady() {
    if (firstFrameReady) return;
    firstFrameReady = true;
    final pending = _pendingCamera;
    _pendingCamera = null;
    if (pending != null) unawaited(pending());
  }

  // 2026-06-06 (vucko P4): Erzwingt ein Neuzeichnen ALLER Linien (rote aktive +
  // graue Vorschau), auch wenn die billige Signatur sich „nicht geändert" hat
  // (z. B. Reroute mit gleicher Punktzahl/gleichen Endpunkten, aber neuer
  // Mitte). Wird vom State gesetzt (forceResyncLines → _lastLinesSig='' +
  // _syncLines()) und von cruise_mode_page beim Reroute-Commit aufgerufen.
  void Function()? onForceResyncLines;
  void forceResyncLines() => onForceResyncLines?.call();

  mb.MapLibreMapController get raw => _map;

  Future<void> animateTo({
    required double lat,
    required double lng,
    double? zoom,
    double? bearing,
    Duration duration = const Duration(milliseconds: 600),
  }) async {
    if (!active) return;
    if (!firstFrameReady) {
      _pendingCamera = () =>
          animateTo(lat: lat, lng: lng, zoom: zoom, bearing: bearing, duration: duration);
      return;
    }
    await _map.animateCamera(
      mb.CameraUpdate.newCameraPosition(
        mb.CameraPosition(
          target: mb.LatLng(lat, lng),
          zoom: zoom ?? _map.cameraPosition?.zoom ?? 14,
          bearing: bearing ?? _map.cameraPosition?.bearing ?? 0,
        ),
      ),
      duration: duration,
    );
  }

  Future<void> moveTo({
    required double lat,
    required double lng,
    double? zoom,
    double? bearing,
  }) async {
    if (!active) return;
    if (!firstFrameReady) {
      _pendingCamera = () => moveTo(lat: lat, lng: lng, zoom: zoom, bearing: bearing);
      return;
    }
    await _map.moveCamera(
      mb.CameraUpdate.newCameraPosition(
        mb.CameraPosition(
          target: mb.LatLng(lat, lng),
          zoom: zoom ?? _map.cameraPosition?.zoom ?? 14,
          bearing: bearing ?? _map.cameraPosition?.bearing ?? 0,
        ),
      ),
    );
  }

  Future<void> fitBounds(
    List<ll.LatLng> points, {
    EdgeInsets padding = const EdgeInsets.all(40),
  }) async {
    if (!active || points.length < 2) return;
    if (!firstFrameReady) {
      _pendingCamera = () => fitBounds(points, padding: padding);
      return;
    }
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    // 2026-06-08 (vucko Overview-Fix): MapLibres CameraUpdate.newLatLngBounds
    // bewegt die Kamera auf iOS unzuverlässig (no-op trotz gültiger Bounds) —
    // der „ganze Route sehen"-Button tat dadurch nichts. Stattdessen Center +
    // passenden Zoom SELBST berechnen und über den BEWIESEN funktionierenden
    // newCameraPosition-Pfad (animateTo) anwenden.
    final centerLat = (minLat + maxLat) / 2.0;
    final centerLng = (minLng + maxLng) / 2.0;
    final latSpan = (maxLat - minLat).abs().clamp(0.0008, 180.0);
    final lngSpan = (maxLng - minLng).abs().clamp(0.0008, 360.0);
    // Mercator-Korrektur für die Breitenspanne, dann den größeren der beiden
    // Spans in einen ~1.1-Tile-breiten Viewport packen (Rand inklusive).
    final latRad = centerLat * math.pi / 180.0;
    final effLatSpan = latSpan / math.max(math.cos(latRad), 0.1);
    final span = math.max(lngSpan, effLatSpan);
    const viewportTiles = 1.1; // ~ (Viewport-Breite − Padding) / 256px
    var zoom = math.log(viewportTiles * 360.0 / span) / math.ln2 - 0.3;
    zoom = zoom.clamp(3.0, 16.0);
    debugPrint(
        '[CruiseMapLibre] fitBounds span=${(maxLat - minLat).toStringAsFixed(4)}x'
        '${(maxLng - minLng).toStringAsFixed(4)} -> zoom=${zoom.toStringAsFixed(2)} pts=${points.length}');
    // bearing:0 → Route Nord-oben in der Übersicht (kein gedrehter Ausschnitt).
    await animateTo(
      lat: centerLat,
      lng: centerLng,
      zoom: zoom,
      bearing: 0,
      duration: const Duration(milliseconds: 600),
    );
  }

  /// Sichtbarer Kartenausschnitt als [southwest, northeast] in latlong2-Koords.
  /// Hält die maplibre-Typen aus den Aufrufern heraus (kein LatLng-Konflikt).
  Future<List<ll.LatLng>?> visibleBounds() async {
    if (!active || !firstFrameReady) return null;
    try {
      final r = await _map.getVisibleRegion();
      return [
        ll.LatLng(r.southwest.latitude, r.southwest.longitude),
        ll.LatLng(r.northeast.latitude, r.northeast.longitude),
      ];
    } catch (_) {
      return null;
    }
  }
}

/// Die self-contained MapLibre-Karte für CruiseConnect.
///
/// Rendert die Mapbox-Dark-Basis (GPU, korrekt — kein vector_tile_renderer),
/// Routen als GL-Linien und Marker als projizierte Flutter-Overlays.
class CruiseMapLibreMap extends StatefulWidget {
  const CruiseMapLibreMap({
    super.key,
    required this.initialCenter,
    this.initialZoom = 6,
    this.lines = const [],
    this.markers = const [],
    this.onMapClick,
    this.onControllerReady,
    this.onCameraMoved,
    this.rotateGestures = true,
    this.styleAsset = 'assets/map/cruise_dark.json',
    this.activeRoutePoints = const [],
    this.drivenTrailPoints = const [],
    this.routeProgress = 0.0,
    this.routeColor = const Color(0xFFFF4438),
  });

  final ll.LatLng initialCenter;
  final double initialZoom;
  final List<CruiseMapLine> lines;
  final List<CruiseMapMarker> markers;
  final void Function(ll.LatLng point)? onMapClick;
  final void Function(CruiseMapLibreController controller)? onControllerReady;
  final VoidCallback? onCameraMoved;
  final bool rotateGestures;
  final String styleAsset;

  // 2026-06-08 (vucko Leitlinie GPU-Trim): die VOLLE aktive Route (wird EINMAL je
  // Routen-/Reroute-Wechsel gesetzt) + der Fahrt-Fortschritt 0..1 entlang dieser
  // Route. Statt die getrimmte Geometrie pro Frame neu zu pushen, bleibt die
  // Geometrie statisch und nur ein line-gradient (GPU) „frisst" sie am Puck auf.
  final List<ll.LatLng> activeRoutePoints;
  // 2026-06-09 (vucko Voll-Route-Sichtbar): der bereits ABGEFAHRENE Teil (ein
  // begrenztes Fenster HINTER dem Puck). Wird als grauer „Driven-Trail" ÜBER der
  // (statischen, vollen) roten Route gezeichnet → „frisst" sie hinter dem Puck
  // grau auf. So bleibt die volle Reststrecke IMMER kräftig rot sichtbar
  // (kein 3km-Abschnitt mehr, der wie „kaputt/abgeschnitten" aussieht), während
  // der scharfe Schnitt am Puck erhalten bleibt (Apple/Google-Look).
  final List<ll.LatLng> drivenTrailPoints;
  final double routeProgress;
  final Color routeColor;

  @override
  State<CruiseMapLibreMap> createState() => _CruiseMapLibreMapState();
}

class _CruiseMapLibreMapState extends State<CruiseMapLibreMap>
    with WidgetsBindingObserver {
  mb.MapLibreMapController? _map;
  CruiseMapLibreController? _ctrl;
  String? _style;
  bool _styleLoaded = false;
  // Sichtbarkeit der Karte (VisibilityDetector). Sicherer Default false: solange
  // die Karte nicht nachweislich sichtbar ist, KEINE view-abhängigen Calls
  // (offstage im IndexedStack → nativer Crash). Wird true, sobald sichtbar.
  bool _visible = false;

  /// Aktuelle Bildschirmpositionen der Marker (id -> Offset in logischen Pixeln).
  final Map<String, Offset> _markerScreen = {};
  // 2026-06-05 (vucko Crash-Fix): Route-Linien laufen NICHT mehr über die
  // Annotation-LineManager. clearLines()+addLine() baute die GeoJSON-Quelle bei
  // JEDEM Sync live ab + neu auf → mbgl warf nativ eine C++-Exception SYNCHRON in
  // onMethodCall (LineBucket/RenderLayer/updateTile) → std::terminate → SIGABRT,
  // nur am Gerät + „manchmal" (exakt flutter-maplibre-gl #509 / maplibre-native
  // #2467). Jetzt: EINE persistente GeoJSON-Quelle + Line-Layer, der NUR via
  // setGeoJsonSource aktualisiert wird (kein remove/re-add der Quelle mehr).
  static const String _lineSourceId = 'cruise-route-lines';
  static const String _lineLayerId = 'cruise-route-lines-layer';
  bool _lineLayerReady = false;
  // 2026-06-08 (vucko CRASH-Fix): In-Flight-Guard gegen Re-Entrancy von
  // _ensureLineLayer. onStyleLoaded feuert auf iOS MEHRFACH (Tiles laden async) →
  // überlappende _ensureLineLayer-Läufe sehen über die await-Lücken BEIDE „Quelle
  // fehlt" → BEIDE addSource/addLineLayer → MLNRedundant…Exception (nativer C++-
  // Throw, von Dart NICHT fangbar) → SIGABRT. _lineLayerReady schützt nicht (erst
  // am Ende gesetzt) → echtes Serialisierungs-Flag, synchron am Start gesetzt.
  bool _ensuringLineLayer = false;
  // Lädt der Style WÄHREND eines _ensureLineLayer-Laufs neu, würde der parallele
  // Re-Establish-Aufruf am In-Flight-Guard abprallen → Layer fehlen im neuen Style
  // (Linie weg + späteres setGeoJsonSource auf fehlende Quelle = erneut SIGABRT).
  // Daher genau EIN Nachzieher gemerkt und nach dem Lauf ausgeführt.
  bool _ensureLinePending = false;
  // 2026-06-08 (vucko Leitlinie GPU-Trim): EIGENE Quelle (lineMetrics:true) für
  // die aktive Route — Geometrie wird nur bei Routen-/Reroute-Wechsel gesetzt;
  // das „Abfahren" macht ein line-gradient (GPU), der pro Tick via
  // setLayerProperties auf den Puck-Progress geschoben wird. Kein Geometrie-
  // Neupush pro Frame → kein Lag, kein Tile-Hunger.
  static const String _activeSrcId = 'cruise-route-active';
  // _activeGlowLayerId = jetzt das CASING (dunkle Kontur UNTER der Füllung),
  // _activeMainLayerId = die rote Füllung darüber. (IDs aus Kompatibilität.)
  static const String _activeGlowLayerId = 'cruise-route-active-glow';
  static const String _activeMainLayerId = 'cruise-route-active-main';
  // 2026-06-09 (vucko Voll-Route-Sichtbar): grauer „Driven-Trail" ÜBER der roten
  // Route — frisst den abgefahrenen Teil hinter dem Puck grau auf. Eigene Quelle +
  // Casing/Füllung (gleiche Breiten wie Rot), damit der abgefahrene Teil exakt wie
  // die rote Linie aussieht, nur grau. Liegt z-mäßig ÜBER _activeMainLayerId.
  static const String _drivenSrcId = 'cruise-route-driven';
  static const String _drivenCasingLayerId = 'cruise-route-driven-casing';
  static const String _drivenFillLayerId = 'cruise-route-driven-fill';
  // Gedämpftes Grau für „schon gefahren" — klar als erledigt lesbar, ohne mit der
  // roten Rest-Route zu konkurrieren.
  static const Color _drivenFillColor = Color(0xFF6E7178);
  // 2026-06-08 (vucko Leitstrich-Premium): dunkle Kontur-Farbe (entsättigtes
  // Rot-Braun) → liest sich als Schatten-Rand, hebt die rote Linie klar vom
  // dunklen Map-Hintergrund ab (Apple/Google-Maps-Look).
  static const Color _routeCasingColor = Color(0xFF230806);
  // Zoom-abhängige Breiten: sichtbar, aber schlank. Casing ~1,5× = dunkler Rand.
  // 2026-06-09 (vucko): nochmal 20% dünner (×0.8) — war „sehr dick".
  static const List<dynamic> _casingWidth = <dynamic>[
    'interpolate', <dynamic>['linear'], <dynamic>['zoom'],
    10, 4.8, 14, 8.8, 16, 11.6, 18, 16.0, 22, 24.0,
  ];
  static const List<dynamic> _fillWidth = <dynamic>[
    'interpolate', <dynamic>['linear'], <dynamic>['zoom'],
    10, 3.2, 14, 5.6, 16, 7.6, 18, 10.4, 22, 15.2,
  ];
  String _lastActiveSig = '';
  String _lastDrivenSig = '';
  // View-/quellen-abhängige Calls (setGeoJsonSource, toScreenLocationBatch) erst
  // NACH dem ersten gerenderten Frame (onCameraIdle) feuern — nicht direkt im
  // onStyleLoaded, solange Renderer/Tiles noch nicht idle sind (sonst Throw).
  bool _firstFrameSynced = false;
  Timer? _initialSyncFallback;
  /// Signatur der zuletzt gezeichneten Linien — _syncLines (teures clearLines+
  /// addLine = voller GeoJSON-Source-Rebuild) läuft NUR bei echter Geometrie-
  /// Änderung, nicht bei jedem Parent-Rebuild/GPS-Tick (Task #4 Lag).
  String _lastLinesSig = '';
  // 2026-06-08 (vucko Marker-Glue): Marker werden jetzt LOKAL in Dart projiziert
  // (synchron, aus map.cameraPosition) statt per async toScreenLocationBatch — das
  // killt den Platform-Channel-Roundtrip, der die Overlay-Marker beim (schnellen)
  // Pannen hinterherhinken ließ. Dafür die Live-Viewport-Größe der Karte (logische
  // Pixel) aus dem LayoutBuilder. Kein _projecting/_projectPending mehr nötig.
  double _mapW = 0;
  double _mapH = 0;
  // 2026-06-05 (vucko Crash-Fix): App-Lifecycle. Im Hintergrund/Inaktiv baut iOS
  // den Metal-Renderer (CAMetalLayer-Drawable) ab — view-/quellen-abhängige Calls
  // (toScreenLocationBatch, setGeoJsonSource, Kamera) würden dann nativ werfen
  // (uncatchbarer C++-Throw → SIGABRT). Solange die App nicht „resumed" ist:
  // ALLE solchen Calls gaten; beim Zurückkommen erst nach dem nächsten Frame.
  bool _appResumed = true;

  // 2026-06-06 (vucko P1): Echte Finger-Geste vs. programmatischer Follow-Move.
  // Programmatische Kamera-Moves (animateTo/moveTo) erzeugen KEINE Pointer-
  // Events — nur eine echte Geste tut das. Beim echten Drag (>18px) wird
  // onCameraMoved EINMAL pro Geste gefeuert (= Lock lösen), sonst nie.
  Offset? _pointerDownPos;
  bool _userPanFired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Sichtbarkeit SOFORT erkennen (kein 500ms-Default) → beim Tab-Wechsel wird
    // die Karte ohne Verzögerung als unsichtbar markiert, bevor ein GPS-Tick
    // einen view-abhängigen Call auf die offstage-View feuern kann.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    // Style via Service bauen: nutzt automatisch die LOKALEN PMTiles, wenn DACH
    // offline geladen wurde — sonst remote von R2.
    MapStyleService.instance.buildStyleString(asset: widget.styleAsset).then((s) {
      if (mounted) setState(() => _style = s);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _initialSyncFallback?.cancel();
    _initialSyncFallback = null;
    _ctrl?.active = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _appResumed) return;
    _appResumed = resumed;
    if (!resumed) {
      // Hintergrund/Inaktiv: keine view-/quellen-abhängigen Calls an die
      // (Metal-)Karte mehr. Controller-Methoden gaten zusätzlich über `active`.
      _ctrl?.active = false;
      return;
    }
    // Zurück im Vordergrund: erst NACH dem nächsten Frame wieder syncen/projizieren
    // (der Metal-Drawable muss sich neu aufbauen) — nicht synchron im selben Frame.
    _ctrl?.active = _visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_appResumed || !_visible) return;
      _syncLines();
      _projectMarkers();
    });
  }

  @override
  void didUpdateWidget(CruiseMapLibreMap old) {
    super.didUpdateWidget(old);
    if (_styleLoaded) {
      // Linien NUR neu zeichnen, wenn sich die Geometrie wirklich geändert hat
      // (cruise_mode_page liefert pro GPS-Tick frische Listen → identical war
      // immer false → voller Rebuild pro Frame = Lag).
      if (_linesSignature() != _lastLinesSig) _syncLines();
      // 2026-06-08 (vucko Sharp-Cut): aktive Route = am Puck geschnittene
      // Reststrecke; bei Geometrie-Wechsel neu pushen (kein Gradient mehr).
      _syncActiveRoute();
      _syncDrivenTrail();
      _projectMarkers();
    }
  }

  /// Billige Signatur der Linien-Geometrie. Ändert sich, wenn sich die Route-
  /// Geometrie ändert.
  /// 2026-06-06 (vucko P4): zusätzlich 3 Mittel-Stützpunkte (¼/½/¾) samplen.
  /// Vorher nur Anzahl+erster+letzter → ein Reroute mit GLEICHER Punktzahl und
  /// gleichem Start/Ziel (typisch bei Rundkursen) änderte die Signatur NICHT →
  /// die graue Vorschau-Route blieb auf der alten Geometrie stehen.
  String _linesSignature() {
    final b = StringBuffer();
    for (final l in widget.lines) {
      final pts = l.points;
      b.write(pts.length);
      if (pts.isNotEmpty) {
        void w(ll.LatLng p) => b.write(
            '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)};');
        b.write('|');
        w(pts.first);
        if (pts.length > 3) {
          w(pts[pts.length ~/ 4]);
          w(pts[pts.length ~/ 2]);
          w(pts[(pts.length * 3) ~/ 4]);
        }
        w(pts.last);
      }
    }
    return b.toString();
  }

  Future<void> _onMapCreated(mb.MapLibreMapController c) async {
    _map = c;
    _ctrl = CruiseMapLibreController._(c);
    // 2026-06-08 (vucko Kamera-Fix): Wird der Controller NACH dem ersten Sync neu
    // erzeugt (z. B. Plattform-View-Rebuild), den Frame-Ready-Zustand übertragen —
    // sonst hält die Page einen Controller mit firstFrameReady=false und ALLE
    // Kamera-Ops werden für immer gepuffert (= Kamera eingefroren).
    if (_firstFrameSynced) _ctrl!.markFirstFrameReady();
    // 2026-06-06 (vucko P4): Reroute kann denselben Signatur-Fingerprint haben →
    // expliziter Resync-Hook, der die Signatur invalidiert und neu zeichnet.
    _ctrl!.onForceResyncLines = () {
      _lastLinesSig = '';
      _syncLines();
    };
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    _ctrl?.active = _visible;
    // 2026-06-05 (vucko Crash-Fix #2): onStyleLoaded kann auf iOS MEHRFACH
    // feuern (z. B. wenn die PMTiles-Vektorquelle asynchron nachlädt). Bei jedem
    // (Re-)Load ist unsere Custom-Linien-Quelle/-Layer im nativen Style weg →
    // als „neu anzulegen" markieren. Ist der erste Frame schon da, etablieren
    // wir sie post-frame erneut (idempotent + existenz-geprüft → kein Redundant-
    // Throw, keine Mutation vor dem ersten Frame).
    final bool wasReload = _firstFrameSynced;
    _lineLayerReady = false;
    if (wasReload) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || !_appResumed || !_visible) return;
        await _ensureLineLayer();
        if (!mounted) return;
        // 2026-06-09 (vucko Voll-Route-Sichtbar): die Quellen wurden beim Reload
        // neu (leer) angelegt → ALLE Signaturen invalidieren, sonst bliebe die
        // statische rote Voll-Route (deren Signatur sich während der Fahrt NIE
        // ändert) nach einem Style-Reload für immer leer.
        _lastLinesSig = '';
        _lastActiveSig = '';
        _lastDrivenSig = '';
        _syncLines();
        _syncActiveRoute();
        _syncDrivenTrail();
      });
    }
    // 2026-06-05 (vucko Crash-Fix #2): KEINE native Style-/Quellen-/Layer-/View-
    // Mutation mehr direkt in onStyleLoaded. onStyleLoaded feuert, sobald das
    // Style-JSON geparst ist — der Metal-Renderer hat aber noch KEINEN Frame
    // produziert und die PMTiles-Quellen laden auf dem Gerät noch asynchron.
    // Eine Quellen-/Layer- oder Kamera-Mutation in genau diesem Fenster warf auf
    // dem Gerät intermittierend synchron eine C++-Exception in onMethodCall
    // (uncatchbar → SIGABRT, bei jedem 5 frischen Crash byte-identischer Stack).
    // Deshalb: ALLES (Linien-Quelle+Layer anlegen, erster Sync, Kamera) erst
    // im ersten onCameraIdle (= erster gerenderter Frame) bzw. im Fallback-Timer.
    _initialSyncFallback?.cancel();
    _initialSyncFallback = Timer(const Duration(milliseconds: 700), () {
      if (mounted) _runFirstSync();
    });
    // Controller wird IMMER übergeben — seine Methoden sind selbst gegatet
    // (firstFrameReady). Kamera-Wünsche vor dem ersten Frame werden gepuffert.
    if (mounted && _ctrl != null) widget.onControllerReady?.call(_ctrl!);
  }

  /// Legt die persistente Route-Linien-Quelle + den Line-Layer einmalig an.
  /// Datengetriebene Paint-Properties (Farbe/Breite/Opazität/Blur kommen als
  /// Feature-Properties) → ein Layer für alle Linien, kein Annotation-Churn.
  Future<void> _ensureLineLayer() async {
    final map = _map;
    // Re-Entrancy-Guard (siehe _ensuringLineLayer-Deklaration): nur EIN Lauf
    // gleichzeitig — verhindert Doppel-add → SIGABRT bei mehrfachem onStyleLoaded.
    if (map == null || _lineLayerReady) return;
    if (_ensuringLineLayer) {
      _ensureLinePending = true; // läuft schon → genau einen Nachzieher merken
      return;
    }
    _ensuringLineLayer = true;
    try {
      // 2026-06-05 (vucko Crash-Fix #2 — ROOT CAUSE): addSource/addLineLayer mit
      // einer ID, die im Style schon existiert, wirft NATIV eine C++-Exception
      // (MLNRedundantSourceException / MLNRedundantLayerException aus dem
      // mbgl-Core) — synchron in onMethodCall, von Dart NICHT fangbar →
      // std::terminate → SIGABRT. Genau das war der intermittierende Geräte-
      // Crash beim ersten Cruise-Öffnen (5 frische Crash-Logs, byte-identischer
      // Stack). Deshalb KEIN remove+add mehr (removeSource auf eine vom Layer
      // genutzte Quelle wirft ebenfalls), sondern strikt existenz-geprüft adden:
      // jede ID entsteht garantiert höchstens einmal, kein Redundant-Throw.
      final sourceIds = await map.getSourceIds();
      if (!mounted) return;
      if (!sourceIds.contains(_lineSourceId)) {
        await map.addSource(
          _lineSourceId,
          const mb.GeojsonSourceProperties(
            data: <String, dynamic>{
              'type': 'FeatureCollection',
              'features': <dynamic>[],
            },
          ),
        );
        if (!mounted) return;
      }
      final layerIds = await map.getLayerIds();
      if (!mounted) return;
      if (!layerIds.contains(_lineLayerId)) {
        await map.addLineLayer(
          _lineSourceId,
          _lineLayerId,
          const mb.LineLayerProperties(
            lineColor: ['get', 'color'],
            lineWidth: ['get', 'width'],
            lineOpacity: ['get', 'opacity'],
            lineBlur: ['get', 'blur'],
            lineJoin: 'round',
            lineCap: 'round',
          ),
        );
      }
      // 2026-06-08 (vucko Leitlinie GPU-Trim): aktive Quelle (lineMetrics!) +
      // Glow/Haupt-Layer mit line-gradient. lineMetrics=true ist Pflicht, sonst
      // ist `line-progress` nicht verfügbar. Existenz-geprüft wie oben (kein
      // Redundant-Throw → kein SIGABRT). Beide Layer ÜBER der Hintergrund-Linie.
      if (!sourceIds.contains(_activeSrcId)) {
        await map.addSource(
          _activeSrcId,
          const mb.GeojsonSourceProperties(
            data: <String, dynamic>{
              'type': 'FeatureCollection',
              'features': <dynamic>[],
            },
            lineMetrics: true,
          ),
        );
        if (!mounted) return;
      }
      // 2026-06-08 (vucko Leitstrich-Sharp-Cut): aktive Quelle = nur noch die
      // RESTSTRECKE (am Puck geschnitten, siehe cruise_mode_page). Casing + Füllung
      // sind SOLIDE Farben (KEIN line-gradient mehr) → der Schnitt entsteht durch
      // die Geometrie-Kante am Puck = knackscharf wie bei Google/Apple Maps (kein
      // langer, schwammiger Gradient-Übergang, der durch die niedrig aufgelöste
      // line-gradient-Textur auf langen Routen entstand). Der abgefahrene Teil ist
      // der graue Hintergrund (Gesamt-Route) aus _buildMapLibreLines.
      if (!layerIds.contains(_activeGlowLayerId)) {
        await map.addLineLayer(
          _activeSrcId,
          _activeGlowLayerId,
          mb.LineLayerProperties(
            lineColor:
                '#${(_routeCasingColor.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
            lineWidth: _casingWidth,
            lineJoin: 'round',
            lineCap: 'round',
          ),
        );
        if (!mounted) return;
      }
      if (!layerIds.contains(_activeMainLayerId)) {
        await map.addLineLayer(
          _activeSrcId,
          _activeMainLayerId,
          mb.LineLayerProperties(
            lineColor:
                '#${(widget.routeColor.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
            lineWidth: _fillWidth,
            lineBlur: 0.5,
            lineJoin: 'round',
            lineCap: 'round',
          ),
        );
        if (!mounted) return;
      }
      // 2026-06-09 (vucko Voll-Route-Sichtbar): grauer Driven-Trail GANZ OBEN.
      // Eigene Quelle (kein lineMetrics nötig). Casing + Füllung in denselben
      // Breiten wie Rot → deckt die rote Linie hinter dem Puck deckend grau ab.
      // Der scharfe Schnitt entsteht an der Geometrie-Kante am Puck (Kopf des
      // Trails = Puck-Projektion). Existenz-geprüft (kein Redundant-Throw).
      if (!sourceIds.contains(_drivenSrcId)) {
        await map.addSource(
          _drivenSrcId,
          const mb.GeojsonSourceProperties(
            data: <String, dynamic>{
              'type': 'FeatureCollection',
              'features': <dynamic>[],
            },
          ),
        );
        if (!mounted) return;
      }
      if (!layerIds.contains(_drivenCasingLayerId)) {
        await map.addLineLayer(
          _drivenSrcId,
          _drivenCasingLayerId,
          mb.LineLayerProperties(
            lineColor:
                '#${(_routeCasingColor.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
            lineWidth: _casingWidth,
            lineJoin: 'round',
            lineCap: 'round',
          ),
        );
        if (!mounted) return;
      }
      if (!layerIds.contains(_drivenFillLayerId)) {
        await map.addLineLayer(
          _drivenSrcId,
          _drivenFillLayerId,
          mb.LineLayerProperties(
            lineColor:
                '#${(_drivenFillColor.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
            lineWidth: _fillWidth,
            lineJoin: 'round',
            lineCap: 'round',
          ),
        );
      }
      _lineLayerReady = true;
    } catch (_) {
      // Defensiv: bei irgendeinem transienten Fehler NICHT erneut blind adden.
      _lineLayerReady = true;
    } finally {
      _ensuringLineLayer = false;
      // Kam während des Laufs ein Re-Establish-Wunsch (Style-Reload) → genau EINMAL
      // nachziehen, falls der Layer dadurch wieder als „nicht bereit" gilt.
      final pending = _ensureLinePending;
      _ensureLinePending = false;
      if (pending && !_lineLayerReady) unawaited(_ensureLineLayer());
    }
  }

  /// Erster Sync nach dem ersten gerenderten Frame — danach laufen Updates
  /// regulär über didUpdateWidget / Sichtbarkeitswechsel.
  ///
  /// Hier passiert ALLES, was native Style-/Quellen-/View-Mutation ist, ZUM
  /// ERSTEN MAL — bewusst erst nachdem der Renderer einen Frame produziert hat
  /// (onCameraIdle) bzw. nach dem 700ms-Fallback. Reihenfolge ist wichtig:
  /// erst die Linien-Quelle+Layer anlegen, DANN die Kamera freigeben + erster
  /// Sync (setGeoJsonSource braucht die Quelle).
  Future<void> _runFirstSync() async {
    if (_firstFrameSynced) return;
    _firstFrameSynced = true;
    _initialSyncFallback?.cancel();
    _initialSyncFallback = null;
    // 2026-06-08 (vucko Kamera-Fix — ROOT CAUSE): Kamera ZUERST freigeben, VOR dem
    // ge-await-eten _ensureLineLayer. Lag markFirstFrameReady danach und wurde
    // `mounted` während des awaits (transienter Rebuild) kurz false, sprang der
    // `if (!mounted) return` davor und markFirstFrameReady lief NIE — der
    // `if (_firstFrameSynced) return`-Guard verhinderte jeden Retry. Folge:
    // firstFrameReady blieb false → ALLE Kamera-Ops (Follow + Recenter) wurden
    // dauerhaft gepuffert und nie angewandt = „Kamera folgt/zentriert nicht,
    // Karte eingefroren". Der erste Frame ist hier bereits gerendert
    // (onCameraIdle bzw. 700ms-Fallback) → die Kamera-Freigabe ist sicher (der
    // SIGABRT kam von Quellen-/Layer-Mutation vor dem Frame, nicht von Kamera).
    _ctrl?.markFirstFrameReady();
    // Persistente Linien-Quelle + Layer EINMAL anlegen (idempotent). Danach wird
    // NUR noch setGeoJsonSource aufgerufen — nie wieder remove/re-add.
    await _ensureLineLayer();
    if (!mounted) return;
    if (_visible) {
      _syncLines();
      _syncActiveRoute();
      _syncDrivenTrail();
      _projectMarkers();
    }
  }

  void _onCameraIdle() {
    // Erstes Idle nach Style-Load = Renderer hat einen Frame → ab jetzt erst
    // Quell-/View-Calls. Vorher würde setGeoJsonSource/convert nativ werfen.
    if (!_firstFrameSynced) {
      _runFirstSync();
      return;
    }
    _projectMarkers();
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final v = info.visibleFraction > 0;
    if (v == _visible) return;
    _visible = v;
    _ctrl?.active = v;
    // Wieder sichtbar geworden → Marker/Linien neu syncen (offstage wurde
    // bewusst nichts an die native View geschickt).
    if (v && _styleLoaded) {
      _syncLines();
      _projectMarkers();
    }
  }

  // 2026-06-07 (vucko P-map-stops): Throttle + Coalesce für _syncLines. Vorher
  // konnte der per-Tick-Aufruf ~11–20Hz eine VOLL-Route via setGeoJsonSource
  // pushen → die native MLNShape(data:)-Reparse hungerte die PMTiles-Vektor-
  // Tile-Pipeline aus (Karte wurde schwarz). Jetzt: max ~5Hz, laufender Sync
  // koalesziert einen Nachzieher, statt zu stapeln.
  bool _syncInFlight = false;
  bool _syncQueued = false;
  DateTime? _lastSyncAt;

  Future<void> _syncLines() async {
    final map = _map;
    // Erst nach dem ersten Frame + wenn Layer bereit. KEIN clearLines/addLine
    // mehr — nur die persistente Quelle in-place aktualisieren (kein nativer
    // Quell-Abriss während der Renderer arbeitet → kein C++-Throw mehr).
    if (!_styleLoaded ||
        !_visible ||
        !_appResumed ||
        !_firstFrameSynced ||
        !_lineLayerReady ||
        map == null) {
      return;
    }
    final now = DateTime.now();
    if (_syncInFlight ||
        (_lastSyncAt != null &&
            now.difference(_lastSyncAt!) < const Duration(milliseconds: 180))) {
      if (!_syncQueued) {
        _syncQueued = true;
        Future<void>.delayed(const Duration(milliseconds: 180), () {
          _syncQueued = false;
          if (mounted) _syncLines();
        });
      }
      return;
    }
    _syncInFlight = true;
    _lastSyncAt = now;
    _lastLinesSig = _linesSignature();
    final features = <Map<String, dynamic>>[];
    for (final l in widget.lines) {
      if (l.points.length < 2) continue;
      features.add({
        'type': 'Feature',
        'properties': {
          'color':
              '#${(l.color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
          'width': l.width,
          'opacity': l.opacity,
          'blur': l.blur,
        },
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final p in l.points) [p.longitude, p.latitude],
          ],
        },
      });
    }
    try {
      await map.setGeoJsonSource(
        _lineSourceId,
        {'type': 'FeatureCollection', 'features': features},
      );
    } catch (_) {
      // Quelle noch nicht bereit / transienter Zustand — nächster Sync zieht nach.
    } finally {
      _syncInFlight = false;
    }
  }

  /// Setzt die aktive Reststrecke (am Puck geschnitten) in die eigene Quelle —
  /// nur bei echtem Geometrie-Wechsel (distanz-gegated im Page), NICHT pro Frame.
  Future<void> _syncActiveRoute() async {
    final map = _map;
    if (!_styleLoaded ||
        !_visible ||
        !_appResumed ||
        !_firstFrameSynced ||
        !_lineLayerReady ||
        map == null) {
      return;
    }
    final pts = widget.activeRoutePoints;
    final sig = pts.length < 2
        ? 'empty'
        : '${pts.length}:${pts.first.latitude.toStringAsFixed(5)},'
            '${pts.first.longitude.toStringAsFixed(5)}>'
            '${pts.last.latitude.toStringAsFixed(5)},'
            '${pts.last.longitude.toStringAsFixed(5)}';
    if (sig == _lastActiveSig) return;
    _lastActiveSig = sig;
    try {
      await map.setGeoJsonSource(_activeSrcId, {
        'type': 'FeatureCollection',
        'features': pts.length < 2
            ? <dynamic>[]
            : [
                {
                  'type': 'Feature',
                  'properties': <String, dynamic>{},
                  'geometry': {
                    'type': 'LineString',
                    'coordinates': [
                      for (final p in pts) [p.longitude, p.latitude],
                    ],
                  },
                },
              ],
      });
    } catch (_) {}
  }

  /// 2026-06-09 (vucko Voll-Route-Sichtbar): grauer Driven-Trail (abgefahrenes
  /// Fenster hinter dem Puck) in die eigene Quelle. Eigene Signatur — pusht nur
  /// bei echtem Geometrie-Wechsel (im Page distanz-gegated), NICHT pro Frame. Die
  /// rote Voll-Route bleibt dabei statisch (separate Quelle) → der „Strich" davor
  /// kann NIE flackern; nur dieser Grau-Trail wandert mit.
  Future<void> _syncDrivenTrail() async {
    final map = _map;
    if (!_styleLoaded ||
        !_visible ||
        !_appResumed ||
        !_firstFrameSynced ||
        !_lineLayerReady ||
        map == null) {
      return;
    }
    final pts = widget.drivenTrailPoints;
    final sig = pts.length < 2
        ? 'empty'
        : '${pts.length}:${pts.first.latitude.toStringAsFixed(5)},'
            '${pts.first.longitude.toStringAsFixed(5)}>'
            '${pts.last.latitude.toStringAsFixed(5)},'
            '${pts.last.longitude.toStringAsFixed(5)}';
    if (sig == _lastDrivenSig) return;
    _lastDrivenSig = sig;
    try {
      await map.setGeoJsonSource(_drivenSrcId, {
        'type': 'FeatureCollection',
        'features': pts.length < 2
            ? <dynamic>[]
            : [
                {
                  'type': 'Feature',
                  'properties': <String, dynamic>{},
                  'geometry': {
                    'type': 'LineString',
                    'coordinates': [
                      for (final p in pts) [p.longitude, p.latitude],
                    ],
                  },
                },
              ],
      });
    } catch (_) {}
  }

  // 2026-06-08 (vucko Marker-Glue): projiziert ALLE Marker SYNCHRON in Dart aus
  // der aktuellen Kamera (map.cameraPosition) — kein async toScreenLocationBatch-
  // Roundtrip mehr, der die Overlay-Marker beim Pannen hinterherhinken ließ. Die
  // Marker bewegen sich jetzt im SELBEN Frame wie die Karte (onCameraMove liefert
  // die frische Kamera) → geo-fixiert, auch bei schnellem Pannen.
  //
  // Pitch ist hier IMMER 0 (tiltGesturesEnabled:false + es wird nirgends ein Tilt
  // gesetzt) → die exakte 2D-Web-Mercator-Projektion reicht (kein Perspektiv-Term).
  // Sollte je ein Tilt>0 gesetzt werden, fällt es sauber auf die native Projektion
  // zurück (siehe unten).
  void _projectMarkers() {
    final map = _map;
    // SIGABRT-Gate UNVERÄNDERT lassen (load-bearing): keine view-/quellen-
    // abhängigen Calls vor dem ersten Frame. cameraPosition ist zwar ein
    // synchroner Getter (kein nativer Throw), aber der Gate schützt auch vor
    // 0-Größe/offstage.
    if (!_styleLoaded ||
        !_visible ||
        !_appResumed ||
        !_firstFrameSynced ||
        map == null ||
        widget.markers.isEmpty) {
      if (_markerScreen.isNotEmpty && mounted) {
        setState(_markerScreen.clear);
      }
      return;
    }
    final cam = map.cameraPosition;
    if (cam == null || _mapW <= 0 || _mapH <= 0) return;

    // Tilt>0 (falls je gesetzt): exakte 2D-Projektion stimmt nicht → native
    // (async) Projektion als Fallback. Heute nie der Fall.
    if (cam.tilt > 0.5) {
      unawaited(_projectMarkersNative());
      return;
    }

    final zoom = cam.zoom;
    final ws = _tileSize * math.pow(2.0, zoom); // fraktionaler Zoom — NICHT runden
    final cx =
        _mercX(cam.target.longitude) * ws;
    final cy =
        _mercY(cam.target.latitude.clamp(-_maxMercLat, _maxMercLat)) * ws;
    final theta = -cam.bearing * math.pi / 180.0; // MapLibre: rotateZ(-bearing)
    final cosT = math.cos(theta), sinT = math.sin(theta);
    final halfW = _mapW / 2, halfH = _mapH / 2;

    final next = <String, Offset>{};
    for (final m in widget.markers) {
      final px = _mercX(m.position.longitude) * ws;
      final py =
          _mercY(m.position.latitude.clamp(-_maxMercLat, _maxMercLat)) * ws;
      final dx = px - cx, dy = py - cy;
      next[m.id] = Offset(
        halfW + (dx * cosT - dy * sinT),
        halfH + (dx * sinT + dy * cosT),
      );
    }
    if (mounted) {
      setState(() {
        _markerScreen
          ..clear()
          ..addAll(next);
      });
    }
  }

  /// Fallback (nur bei Tilt>0 — heute nie): native async Projektion.
  Future<void> _projectMarkersNative() async {
    final map = _map;
    if (map == null) return;
    try {
      // 2026-06-09 (vucko Audit T1-E): die Marker-Liste EINMAL fixieren (vor dem
      // await) und danach NUR diese Referenz indizieren + i<pts.length prüfen.
      // Vorher las die Schleife widget.markers nach dem await neu → schrumpfte das
      // Eltern-Widget die Liste, gab es einen IndexOutOfRange-Crash.
      final markers = widget.markers;
      final pts = await map.toScreenLocationBatch(
        markers
            .map((m) => mb.LatLng(m.position.latitude, m.position.longitude)),
      );
      final next = <String, Offset>{};
      for (var i = 0; i < markers.length && i < pts.length; i++) {
        next[markers[i].id] =
            Offset(pts[i].x.toDouble(), pts[i].y.toDouble());
      }
      if (mounted) {
        setState(() {
          _markerScreen
            ..clear()
            ..addAll(next);
        });
      }
    } catch (_) {}
  }

  void _onCameraMove(mb.CameraPosition _) {
    // Gate: nur sichtbar + resumed + nach Style-Load Controller-Aufrufe (siehe
    // _projectMarkers) — sonst MapLibre-Abort.
    if (!_styleLoaded || !_visible || !_appResumed) return;
    // Während der Bewegung Marker mitführen (throttled über Frame-Coalescing
    // von setState). Linien sind GL-gerendert und brauchen kein Update.
    // 2026-06-06 (vucko P1): onCameraMoved (= Kamera-Lock lösen) wird hier NICHT
    // mehr gefeuert. Sonst löste JEDER programmatische Follow-Move den Lock →
    // die Follow-Schleife starb und der Standort driftete aus der Mitte. Echte
    // Finger-Gesten werden jetzt über den Pointer-Listener in build() erkannt
    // (programmatische Kamera-Moves erzeugen KEINE Pointer-Events → eindeutig).
    _projectMarkers();
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    if (style == null) {
      return const ColoredBox(color: Color(0xFF0b0e13));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // 2026-06-08 (vucko Marker-Glue): Live-Viewport-Größe der Karte (logische
        // Pixel) für die lokale Marker-Projektion festhalten.
        if (constraints.maxWidth != _mapW ||
            constraints.maxHeight != _mapH) {
          _mapW = constraints.maxWidth;
          _mapH = constraints.maxHeight;
        }
        return Stack(
      children: [
        VisibilityDetector(
          key: const ValueKey('cruise-maplibre-visibility'),
          onVisibilityChanged: _onVisibilityChanged,
          // 2026-06-06 (vucko P1): Pointer-Listener erkennt ECHTE Finger-Gesten
          // (translucent → bekommt Events auch, während MapLibre selbst pannt).
          // Nur ein echter Drag löst den Kamera-Lock — programmatische Moves nie.
          child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) {
            _pointerDownPos = e.position;
            _userPanFired = false;
          },
          onPointerMove: (e) {
            if (_userPanFired || _pointerDownPos == null) return;
            if ((e.position - _pointerDownPos!).distance > 18) {
              _userPanFired = true;
              widget.onCameraMoved?.call();
            }
          },
          child: mb.MapLibreMap(
          styleString: style,
          initialCameraPosition: mb.CameraPosition(
            target: mb.LatLng(
              widget.initialCenter.latitude,
              widget.initialCenter.longitude,
            ),
            zoom: widget.initialZoom,
          ),
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: _onStyleLoaded,
          trackCameraPosition: true,
          rotateGesturesEnabled: widget.rotateGestures,
          tiltGesturesEnabled: false,
          compassEnabled: false,
          attributionButtonPosition: mb.AttributionButtonPosition.bottomRight,
          onMapClick: (point, latLng) =>
              widget.onMapClick?.call(ll.LatLng(latLng.latitude, latLng.longitude)),
          onCameraMove: _onCameraMove,
          onCameraIdle: _onCameraIdle,
          ),
          ),
        ),
        // Marker-Overlay
        ..._buildMarkerOverlay(),
      ],
        );
      },
    );
  }

  List<Widget> _buildMarkerOverlay() {
    final out = <Widget>[];
    for (final m in widget.markers) {
      final pos = _markerScreen[m.id];
      if (pos == null) continue;
      // Ankerverschiebung relativ zur Marker-Box.
      final ax = (m.alignment.x + 1) / 2; // 0..1
      final ay = (m.alignment.y + 1) / 2;
      out.add(Positioned(
        left: pos.dx - m.width * ax,
        top: pos.dy - m.height * ay,
        width: m.width,
        height: m.height,
        child: IgnorePointer(
          ignoring: false,
          child: SizedBox(width: m.width, height: m.height, child: m.child),
        ),
      ));
    }
    return out;
  }
}

// ── Lokale Web-Mercator-Projektion (vucko 2026-06-08 Marker-Glue) ─────────────
// Wandelt lng/lat → normierte Mercator-Koordinaten [0..1]. MapLibre nutzt eine
// 512er-Kachel (worldSize = 512 · 2^zoom). KEIN devicePixelRatio (Transform +
// Flutter-Layout sind beide in logischen Pixeln). Latitude vor _mercY clampen.
const double _tileSize = 512.0;
const double _maxMercLat = 85.051129;

double _mercX(double lng) => (180.0 + lng) / 360.0;

double _mercY(double lat) =>
    (180.0 -
        (180.0 / math.pi) *
            math.log(math.tan(math.pi / 4 + lat * math.pi / 360.0))) /
    360.0;
