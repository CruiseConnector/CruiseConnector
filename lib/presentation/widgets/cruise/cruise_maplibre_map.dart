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

  mb.MapLibreMapController get raw => _map;

  Future<void> animateTo({
    required double lat,
    required double lng,
    double? zoom,
    double? bearing,
    Duration duration = const Duration(milliseconds: 600),
  }) async {
    if (!active) return;
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
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    await _map.animateCamera(
      mb.CameraUpdate.newLatLngBounds(
        mb.LatLngBounds(
          southwest: mb.LatLng(minLat, minLng),
          northeast: mb.LatLng(maxLat, maxLng),
        ),
        left: padding.left,
        top: padding.top,
        right: padding.right,
        bottom: padding.bottom,
      ),
    );
  }

  /// Sichtbarer Kartenausschnitt als [southwest, northeast] in latlong2-Koords.
  /// Hält die maplibre-Typen aus den Aufrufern heraus (kein LatLng-Konflikt).
  Future<List<ll.LatLng>?> visibleBounds() async {
    if (!active) return null;
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

class _CruiseMapLibreMapState extends State<CruiseMapLibreMap> {
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
  final List<mb.Line> _glLines = [];
  /// Signatur der zuletzt gezeichneten Linien — _syncLines (teures clearLines+
  /// addLine = voller GeoJSON-Source-Rebuild) läuft NUR bei echter Geometrie-
  /// Änderung, nicht bei jedem Parent-Rebuild/GPS-Tick (Task #4 Lag).
  String _lastLinesSig = '';
  /// Coalescing der Marker-Projektion: nur EINE toScreenLocationBatch-Anfrage
  /// gleichzeitig in flight (sonst Platform-Channel-Pile-up → Marker-Trailing).
  bool _projecting = false;
  bool _projectPending = false;

  @override
  void initState() {
    super.initState();
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

  /// Billige Signatur der Linien-Geometrie (Anzahl + erster/letzter Punkt je
  /// Linie). Ändert sich nur, wenn die Route-Geometrie sich tatsächlich ändert.
  String _linesSignature() {
    final b = StringBuffer();
    for (final l in widget.lines) {
      b.write(l.points.length);
      if (l.points.isNotEmpty) {
        final f = l.points.first;
        final t = l.points.last;
        b.write(
            '|${f.latitude.toStringAsFixed(5)},${f.longitude.toStringAsFixed(5)}'
            '-${t.latitude.toStringAsFixed(5)},${t.longitude.toStringAsFixed(5)};');
      }
    }
    return b.toString();
  }

  Future<void> _onMapCreated(mb.MapLibreMapController c) async {
    _map = c;
    _ctrl = CruiseMapLibreController._(c);
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    _ctrl?.active = _visible;
    if (_visible) {
      await _syncLines();
      await _projectMarkers();
    }
    // Controller wird IMMER übergeben — seine Methoden sind selbst gegatet.
    if (mounted && _ctrl != null) widget.onControllerReady?.call(_ctrl!);
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

  Future<void> _syncLines() async {
    final map = _map;
    if (!_styleLoaded || !_visible || map == null) return;
    _lastLinesSig = _linesSignature();
    // Bestehende Linien entfernen, dann neu zeichnen. Läuft dank Signatur-Gate
    // (didUpdateWidget) nur bei echter Geometrie-Änderung, nicht pro Frame.
    try {
      await map.clearLines();
    } catch (_) {}
    _glLines.clear();
    for (final l in widget.lines) {
      if (l.points.length < 2) continue;
      final line = await map.addLine(
        mb.LineOptions(
          geometry: l.points
              .map((p) => mb.LatLng(p.latitude, p.longitude))
              .toList(),
          lineColor:
              '#${(l.color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
          lineWidth: l.width,
          lineOpacity: l.opacity,
          lineJoin: 'round',
          lineBlur: l.blur,
        ),
      );
      _glLines.add(line);
    }
  }

  Future<void> _projectMarkers() async {
    final map = _map;
    // KRITISCH: keine Controller-Methode (toScreenLocationBatch) aufrufen, bevor
    // der Style geladen ist. MapLibre wirft sonst nativ eine C++-Exception
    // (SIGABRT) — von Dart NICHT fangbar → App-Crash. onCameraMove kann während
    // des Karten-Setups schon feuern, daher dieser Gate.
    if (!_styleLoaded || !_visible || map == null || widget.markers.isEmpty) {
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
    // Gate: nur sichtbar + nach Style-Load Controller-Aufrufe (siehe
    // _projectMarkers) — sonst MapLibre-Abort.
    if (!_styleLoaded || !_visible) return;
    // Während der Bewegung Marker mitführen (throttled über Frame-Coalescing
    // von setState). Linien sind GL-gerendert und brauchen kein Update.
    _projectMarkers();
    widget.onCameraMoved?.call();
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
          onCameraIdle: _projectMarkers,
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
