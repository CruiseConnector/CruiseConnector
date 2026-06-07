import 'dart:async';

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
    // 2026-06-07 (vucko P-overview): Padding HART deckeln. Eine hohe DACH-Route
    // + großzügiges Padding (top+bottom) konnte den lösbaren Bereich übersteigen
    // → MapLibre no-opte still (Button „tat nichts"). Plus EXPLIZITE Dauer (sonst
    // Plugin-Default = teils gar keine sichtbare Animation).
    final top = padding.top.clamp(0.0, 180.0);
    final bottom = padding.bottom.clamp(0.0, 200.0);
    final left = padding.left.clamp(0.0, 80.0);
    final right = padding.right.clamp(0.0, 80.0);
    debugPrint(
        '[CruiseMapLibre] fitBounds span=${(maxLat - minLat).toStringAsFixed(4)}x'
        '${(maxLng - minLng).toStringAsFixed(4)} pad=L$left/T$top/R$right/B$bottom pts=${points.length}');
    try {
      await _map.animateCamera(
        mb.CameraUpdate.newLatLngBounds(
          mb.LatLngBounds(
            southwest: mb.LatLng(minLat, minLng),
            northeast: mb.LatLng(maxLat, maxLng),
          ),
          left: left,
          top: top,
          right: right,
          bottom: bottom,
        ),
        duration: const Duration(milliseconds: 600),
      );
    } catch (e) {
      debugPrint('[CruiseMapLibre] fitBounds fehlgeschlagen: $e');
    }
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
  // View-/quellen-abhängige Calls (setGeoJsonSource, toScreenLocationBatch) erst
  // NACH dem ersten gerenderten Frame (onCameraIdle) feuern — nicht direkt im
  // onStyleLoaded, solange Renderer/Tiles noch nicht idle sind (sonst Throw).
  bool _firstFrameSynced = false;
  Timer? _initialSyncFallback;
  /// Signatur der zuletzt gezeichneten Linien — _syncLines (teures clearLines+
  /// addLine = voller GeoJSON-Source-Rebuild) läuft NUR bei echter Geometrie-
  /// Änderung, nicht bei jedem Parent-Rebuild/GPS-Tick (Task #4 Lag).
  String _lastLinesSig = '';
  /// Coalescing der Marker-Projektion: nur EINE toScreenLocationBatch-Anfrage
  /// gleichzeitig in flight (sonst Platform-Channel-Pile-up → Marker-Trailing).
  bool _projecting = false;
  bool _projectPending = false;
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
        if (mounted) _syncLines();
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
    if (_lineLayerReady || map == null) return;
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
      _lineLayerReady = true;
    } catch (_) {
      // Defensiv: bei irgendeinem transienten Fehler NICHT erneut blind adden.
      _lineLayerReady = true;
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
    // Persistente Linien-Quelle + Layer EINMAL anlegen (idempotent). Danach wird
    // NUR noch setGeoJsonSource aufgerufen — nie wieder remove/re-add.
    await _ensureLineLayer();
    if (!mounted) return;
    // Aufgestaute Kamera-Wünsche (initiale GPS-Zentrierung) jetzt anwenden.
    _ctrl?.markFirstFrameReady();
    if (_visible) {
      _syncLines();
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

  Future<void> _projectMarkers() async {
    final map = _map;
    // KRITISCH: keine Controller-Methode (toScreenLocationBatch) aufrufen, bevor
    // der Style geladen ist. MapLibre wirft sonst nativ eine C++-Exception
    // (SIGABRT) — von Dart NICHT fangbar → App-Crash. onCameraMove kann während
    // des Karten-Setups schon feuern, daher dieser Gate.
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
    // Coalescing: läuft schon eine Projektion, nur „pending" merken und raus —
    // verhindert das Platform-Channel-Pile-up (jede toScreenLocationBatch ist ein
    // awaited Roundtrip; bei 5Hz GPS + 60fps Kamera stauen sie sich → Marker-Lag).
    if (_projecting) {
      _projectPending = true;
      return;
    }
    _projecting = true;
    try {
      final pts = await map.toScreenLocationBatch(
        widget.markers.map((m) => mb.LatLng(m.position.latitude, m.position.longitude)),
      );
      final next = <String, Offset>{};
      for (var i = 0; i < widget.markers.length; i++) {
        final p = pts[i];
        // maplibre_gl liefert auf iOS bereits LOGISCHE Pixel (Flutter-Koords) —
        // NICHT durch devicePixelRatio teilen (sonst rutschen Marker nach
        // oben-links). (Android müsste ggf. /dpr — bei Bedarf plattform-spezifisch.)
        next[widget.markers[i].id] = Offset(p.x.toDouble(), p.y.toDouble());
      }
      if (mounted) {
        setState(() {
          _markerScreen
            ..clear()
            ..addAll(next);
        });
      }
    } catch (_) {
      // Projektion vor Style-Load o. Ä. — ignorieren, nächster Frame korrigiert.
    } finally {
      _projecting = false;
      // Wurde während der laufenden Projektion eine weitere angefragt → genau
      // EINMAL nachziehen (mit den dann aktuellen Marker-Positionen).
      if (_projectPending) {
        _projectPending = false;
        _projectMarkers();
      }
    }
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
