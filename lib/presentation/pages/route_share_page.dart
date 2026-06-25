import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cruise_connect/presentation/widgets/photo/ride_photo_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/route_map_share_service.dart';

/// Entkoppelte Daten für die Share-Karte — funktioniert von überall
/// (gespeicherte Route, Fahrt-Detail, Post-Route). Segmente = Liste von
/// Linienzügen aus [lng, lat]-Punkten (Mapbox-Format).
class RouteShareData {
  const RouteShareData({
    required this.title,
    required this.segments,
    this.distanceLabel,
    this.durationLabel,
    this.topSpeedLabel,
    this.styleLabel,
    this.curvesLabel,
    this.subtitle,
  });

  final String title;
  final List<List<Offset>> segments;
  final String? distanceLabel;
  final String? durationLabel;
  final String? topSpeedLabel;
  final String? styleLabel;
  final String? curvesLabel;
  final String? subtitle;

  /// Extrahiert die Linienzüge aus einer GeoJSON-Geometrie (LineString oder
  /// MultiLineString) als [lng,lat]-Offsets — für die Routen-Skizze.
  static List<List<Offset>> segmentsFromGeometry(
    Map<String, dynamic>? geometry,
  ) {
    if (geometry == null) return const [];
    final raw = geometry['coordinates'];
    if (raw is! List) return const [];
    List<Offset> parse(List seg) {
      final pts = <Offset>[];
      for (final item in seg) {
        if (item is List && item.length >= 2) {
          final lng = item[0];
          final lat = item[1];
          if (lng is num && lat is num) {
            pts.add(Offset(lng.toDouble(), lat.toDouble()));
          }
        }
      }
      return pts;
    }

    if (geometry['type'] == 'MultiLineString') {
      return raw
          .whereType<List>()
          .map(parse)
          .where((s) => s.length >= 2)
          .toList(growable: false);
    }
    final single = parse(raw);
    return single.length >= 2 ? [single] : const [];
  }
}

enum _ShareFormat { map, story, square, sticker }

/// 2026-06-25 (vucko): Strava-artiger Share-Composer. Man wählt ein Foto/Selfie
/// als Hintergrund, die Eckdaten-Karte liegt als halbtransparente „Glass"-Karte
/// darüber (man sieht das Gesicht durch + die Daten klar lesbar dank Scrim +
/// Schatten — Lesbarkeit für den WORST-CASE-Hintergrund gebaut). Drei Formate:
/// Story 9:16, Quadrat 1:1, und „Sticker" = nur die transparente Karte (PNG mit
/// Alpha) zum Drüberlegen in der eigenen Story.
class RouteSharePage extends StatefulWidget {
  const RouteSharePage({super.key, required this.data});

  final RouteShareData data;

  @override
  State<RouteSharePage> createState() => _RouteSharePageState();
}

class _RouteSharePageState extends State<RouteSharePage> {
  final GlobalKey _captureKey = GlobalKey();

  Uint8List? _photo;
  _ShareFormat _format = _ShareFormat.story;
  bool _busy = false;
  // 2026-06-25 (vucko Share-Rework): echtes Karten-Bild (Esri-Tiles + Route),
  // async geladen, sobald auf das „Karte"-Format gewechselt wird.
  Uint8List? _mapBytes;
  bool _mapLoading = false;

  double get _aspect => switch (_format) {
        _ShareFormat.story => 9 / 16,
        _ShareFormat.square => 1,
        _ShareFormat.sticker => 9 / 16,
        _ShareFormat.map => 9 / 16,
      };

  bool get _isSticker => _format == _ShareFormat.sticker;
  bool get _isMap => _format == _ShareFormat.map;

  void _selectFormat(_ShareFormat f) {
    setState(() => _format = f);
    if (f == _ShareFormat.map) _ensureMapImage();
  }

  Future<void> _ensureMapImage() async {
    if (_mapBytes != null || _mapLoading) return;
    final route = <List<double>>[
      for (final s in widget.data.segments)
        for (final p in s) [p.dx, p.dy],
    ];
    if (route.length < 2) return;
    setState(() => _mapLoading = true);
    try {
      final bytes = await RouteMapShareService.buildRouteMapPng(
        route: route,
        accent: AppAccentColors.accent,
      );
      if (mounted) setState(() => _mapBytes = bytes);
    } catch (_) {
      // Tiles nicht erreichbar → Hintergrund bleibt der Gradient (Karte leer).
    } finally {
      if (mounted) setState(() => _mapLoading = false);
    }
  }

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Foto wählen + Ausschnitt/Zoom frei festlegen → der User steuert, was im
      // geteilten Bild zu sehen ist (und in welchem Ausmaß).
      final bytes = await pickAndCropRidePhoto(context, source: source);
      if (bytes != null && mounted) setState(() => _photo = bytes);
    } catch (_) {
      // Galerie/Kamera abgebrochen oder kein Zugriff — still ignorieren.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List?> _capturePng() async {
    final ctx = _captureKey.currentContext;
    if (ctx == null) return null;
    final boundary = ctx.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    final image = await boundary.toImage(pixelRatio: 3.0);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    // iPad: Share-Sheet ist ein Popover und braucht einen Anker — VOR den awaits
    // erfassen, sonst erscheint das Sheet leer/falsch positioniert.
    final shareBox = context.findRenderObject() as RenderBox?;
    final shareOrigin = shareBox != null
        ? shareBox.localToGlobal(Offset.zero) & shareBox.size
        : null;
    try {
      // Einen Frame warten, damit das Capture-Widget sicher gelayoutet ist.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final png = await _capturePng();
      if (png == null) return;
      final file = XFile.fromData(
        png,
        mimeType: 'image/png',
        name: _isSticker
            ? 'cruise-route-sticker.png'
            : 'cruise-route.png',
      );
      final dist = widget.data.distanceLabel;
      await Share.shareXFiles(
        [file],
        text: dist != null
            ? '${widget.data.title} · $dist — mit Cruise Connector'
            : '${widget.data.title} — mit Cruise Connector',
        subject: 'Cruise Connector Route',
        sharePositionOrigin: shareOrigin,
      );
    } catch (_) {
      // Teilen abgebrochen — kein Fehler-Toast nötig.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Route teilen',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AspectRatio(
                    aspectRatio: _aspect,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(_isSticker ? 0 : 22),
                      child: RepaintBoundary(
                        key: _captureKey,
                        child: _buildPreview(accent),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _buildControls(accent),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(Color accent) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Hintergrund: Karte / Foto (cover) — beim Sticker transparent lassen.
        if (!_isSticker) _buildBackground(),
        // Eckdaten-Glass-Karte: halbtransparent → Gesicht scheint durch, Text
        // klar lesbar (Scrim + Schatten). Beim Sticker liegt nur diese Karte auf
        // Transparenz → PNG mit Alpha zum Drüberlegen.
        Align(
          alignment: _isSticker ? Alignment.center : Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.all(_isSticker ? 8 : 18),
            child: RouteShareCard(data: widget.data, accent: accent),
          ),
        ),
      ],
    );
  }

  Widget _buildBackground() {
    const gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A2030), Color(0xFF0B0E14)],
        ),
      ),
    );
    if (_isMap) {
      if (_mapBytes != null) {
        return Image.memory(_mapBytes!, fit: BoxFit.cover);
      }
      return const Stack(
        fit: StackFit.expand,
        children: [
          gradient,
          Center(
            child: SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        ],
      );
    }
    if (_photo != null) return Image.memory(_photo!, fit: BoxFit.cover);
    return gradient;
  }

  Widget _buildControls(Color accent) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(color: Color(0xFF11151D)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Format-Wahl.
          Row(
            children: [
              _formatChip('Karte', _ShareFormat.map, accent),
              const SizedBox(width: 7),
              _formatChip('Story', _ShareFormat.story, accent),
              const SizedBox(width: 7),
              _formatChip('Quadrat', _ShareFormat.square, accent),
              const SizedBox(width: 7),
              _formatChip('Sticker', _ShareFormat.sticker, accent),
            ],
          ),
          const SizedBox(height: 10),
          // Foto-Aktionen — beim Sticker (transparent) UND bei der Karte (die
          // echte Karte IST der Hintergrund) ausgeblendet.
          if (!_isSticker && !_isMap)
            Row(
              children: [
                Expanded(
                  child: _photoButton(
                    'Selfie',
                    Icons.camera_alt_rounded,
                    () => _pick(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _photoButton(
                    'Foto',
                    Icons.photo_library_rounded,
                    () => _pick(ImageSource.gallery),
                  ),
                ),
                if (_photo != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _photoButton(
                      'Entfernen',
                      Icons.delete_outline_rounded,
                      () => setState(() => _photo = null),
                    ),
                  ),
                ],
              ],
            ),
          if (!_isSticker) const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _share,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded, color: Colors.white),
              label: const Text(
                'Teilen',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          if (_isSticker)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Sticker = transparente Karte zum Drüberlegen auf dein eigenes Story-Foto.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 11.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _formatChip(String label, _ShareFormat format, Color accent) {
    final selected = _format == format;
    return Expanded(
      child: GestureDetector(
        onTap: () => _selectFormat(format),
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accent : const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFFA0AEC0),
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: _busy ? null : onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Öffentliche, wiederverwendbare Eckdaten-„Glass"-Karte: Scrim 0.42 +
/// doppelter Text-Schatten → lesbar über JEDEM Foto (Worst-Case-Hintergrund),
/// während das Foto durchscheint. Isoliert testbar (Sim-Vorschau hell/dunkel)
/// und wiederverwendbar (Share-Composer, evtl. Post-Route).
class RouteShareCard extends StatelessWidget {
  const RouteShareCard({super.key, required this.data, required this.accent});

  final RouteShareData data;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final stats = <(IconData, String)>[
      if (data.distanceLabel != null) (Icons.map_rounded, data.distanceLabel!),
      if (data.durationLabel != null) (Icons.timer_rounded, data.durationLabel!),
      if (data.topSpeedLabel != null) (Icons.speed_rounded, data.topSpeedLabel!),
      if (data.styleLabel != null) (Icons.tune_rounded, data.styleLabel!),
      if (data.curvesLabel != null) (Icons.moving_rounded, data.curvesLabel!),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.directions_car_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              const Flexible(
                child: Text(
                  'CRUISE CONNECTOR',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Routen-Skizze.
          if (data.segments.isNotEmpty)
            Container(
              height: 116,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(16),
              ),
              child: CustomPaint(
                painter: _RouteLinePainter(
                  segments: data.segments,
                  accent: accent,
                ),
              ),
            ),
          const SizedBox(height: 12),
          _shadowText(
            data.title,
            fontSize: 21,
            weight: FontWeight.w900,
            maxLines: 2,
          ),
          if (data.subtitle != null) ...[
            const SizedBox(height: 3),
            _shadowText(
              data.subtitle!,
              fontSize: 12.5,
              weight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.85),
              maxLines: 1,
            ),
          ],
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Wrap statt Row → bricht bei schmaler Breite (Sticker/Quadrat,
            // kleines Display, viele Stats) defensiv um statt zu overflowen.
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final s in stats) _statChip(s.$1, s.$2, accent),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String label, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          _shadowText(label, fontSize: 13, weight: FontWeight.w900),
        ],
      ),
    );
  }

  Widget _shadowText(
    String text, {
    required double fontSize,
    required FontWeight weight,
    Color color = Colors.white,
    int maxLines = 1,
  }) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: weight,
        height: 1.1,
        shadows: const [
          Shadow(color: Colors.black, blurRadius: 6),
          Shadow(color: Colors.black54, blurRadius: 2),
        ],
      ),
    );
  }
}

/// Zeichnet die Routen-Linie (Segmente aus [lng,lat]) in die Kachel — Halo +
/// Glow + Akzent-Linie + Start/Ziel-Punkte.
class _RouteLinePainter extends CustomPainter {
  _RouteLinePainter({required this.segments, required this.accent});

  final List<List<Offset>> segments;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final coords = segments.expand((s) => s).toList();
    if (coords.length < 2) return;
    var minLng = coords.first.dx, maxLng = coords.first.dx;
    var minLat = coords.first.dy, maxLat = coords.first.dy;
    for (final p in coords) {
      minLng = math.min(minLng, p.dx);
      maxLng = math.max(maxLng, p.dx);
      minLat = math.min(minLat, p.dy);
      maxLat = math.max(maxLat, p.dy);
    }
    const pad = 14.0;
    final lngSpan = math.max(maxLng - minLng, 0.0001);
    final latSpan = math.max(maxLat - minLat, 0.0001);
    final scale = math.min(
      (size.width - 2 * pad) / lngSpan,
      (size.height - 2 * pad) / latSpan,
    );
    final w = lngSpan * scale, h = latSpan * scale;
    final ox = (size.width - w) / 2, oy = (size.height - h) / 2;
    Offset project(Offset p) => Offset(
          ox + (p.dx - minLng) * scale,
          oy + (maxLat - p.dy) * scale,
        );

    final halo = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final line = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final seg in segments) {
      if (seg.length < 2) continue;
      final path = Path()..moveTo(project(seg.first).dx, project(seg.first).dy);
      for (final p in seg.skip(1)) {
        final pr = project(p);
        path.lineTo(pr.dx, pr.dy);
      }
      canvas.drawPath(path, halo);
      canvas.drawPath(path, line);
    }

    final start = project(segments.first.first);
    final end = project(segments.last.last);
    canvas.drawCircle(start, 6, Paint()..color = Colors.white);
    canvas.drawCircle(start, 3.5, Paint()..color = accent);
    canvas.drawCircle(end, 6, Paint()..color = Colors.white);
    canvas.drawCircle(end, 3.5, Paint()..color = const Color(0xFFFFD166));
  }

  @override
  bool shouldRepaint(_RouteLinePainter old) =>
      old.segments != segments || old.accent != accent;
}
