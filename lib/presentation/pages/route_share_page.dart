import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/deep_links.dart';
import 'package:cruise_connect/data/services/route_map_share_service.dart';
import 'package:cruise_connect/presentation/widgets/photo/ride_photo_picker.dart';

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

/// Strava-artiger Share-Composer.
///
/// 2026-06-25 (vucko Rework): KEIN Foto/Selfie mehr IN der App dahinterlegen —
/// das macht man in der Ziel-App (Instagram/Snapchat-Story). Vier saubere
/// Formate:
///  • Karte    – echte Karte mit Route als Hintergrund (1 Tap teilen)
///  • Story 9:16 / Quadrat 1:1 – Eckdaten-Karte auf sauberem dunklem Hintergrund
///    → ideal zum direkten Verschicken in WhatsApp & Co. (kein „kaputtes"
///    Transparenz-Schwarz/Weiß).
///  • Sticker  – nur die transparente Karte (PNG mit Alpha) → legt man in der
///    Story-App über sein EIGENES Foto/Selfie.
/// Jeder Teilen-Vorgang hängt einen Deeplink an den Text → der Empfänger landet
/// per Tap in der App ([CruiseDeepLinks.shareUrl]).
class RouteSharePage extends StatefulWidget {
  const RouteSharePage({super.key, required this.data});

  final RouteShareData data;

  @override
  State<RouteSharePage> createState() => _RouteSharePageState();
}

class _RouteSharePageState extends State<RouteSharePage> {
  final GlobalKey _captureKey = GlobalKey();

  _ShareFormat _format = _ShareFormat.story;
  bool _busy = false;
  // 2026-06-25 (vucko Share-Rework): echtes Karten-Bild (Esri-Tiles + Route),
  // async geladen, sobald auf das „Karte"-Format gewechselt wird.
  Uint8List? _mapBytes;
  bool _mapLoading = false;

  // 2026-06-25 (vucko): Overlay-Karte frei positionieren — ziehen (verschieben)
  // + zwei Finger (skalieren). Das landet 1:1 im geteilten Bild, weil die
  // RepaintBoundary die transformierte Karte miterfasst.
  Offset _cardOffset = Offset.zero;
  double _cardScale = 1.0;
  double _scaleStartFactor = 1.0;

  // Eigenes Foto/Selfie als Hintergrund (Story/Quadrat). Optional — Default ist
  // der dunkle Verlauf. Crop/Zoom passiert beim Auswählen (Bestätigen = „Fertig").
  Uint8List? _bgPhoto;
  bool _picking = false;

  double get _aspect => switch (_format) {
        _ShareFormat.story => 9 / 16,
        _ShareFormat.square => 1,
        _ShareFormat.sticker => 9 / 16,
        _ShareFormat.map => 9 / 16,
      };

  bool get _isSticker => _format == _ShareFormat.sticker;
  bool get _isMap => _format == _ShareFormat.map;

  @override
  void initState() {
    super.initState();
    // Karte schon beim Öffnen laden → beim Wechsel auf „Karte" ist sie sofort da
    // (kein störender Lade-Spinner mehr).
    _ensureMapImage();
  }

  void _selectFormat(_ShareFormat f) {
    setState(() {
      _format = f;
      // Position/Größe zurücksetzen — die Formate haben andere Grund-Layouts.
      _cardOffset = Offset.zero;
      _cardScale = 1.0;
    });
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
        aspect: 9 / 16, // Karte-Modus ist 9:16 → kein Crop der Route
      );
      if (mounted) setState(() => _mapBytes = bytes);
    } catch (_) {
      // Tiles nicht erreichbar → Hintergrund bleibt der Gradient (Karte leer).
    } finally {
      if (mounted) setState(() => _mapLoading = false);
    }
  }

  /// Eigenes Foto/Selfie als Hintergrund wählen. Beim Auswählen kann der Nutzer
  /// zuschneiden/zoomen (9:16 passend zum Story-Rahmen) und mit „Fertig"
  /// bestätigen. Danach liegt das Bild als Hintergrund, die Eckdaten-Karte
  /// darüber (frei verschieb-/skalierbar).
  Future<void> _pickBackground(ImageSource source) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final bytes = await pickAndCropRidePhoto(
        context,
        source: source,
        lockedAspect: _format == _ShareFormat.square ? 1 : 9 / 16,
      );
      if (bytes != null && mounted) setState(() => _bgPhoto = bytes);
    } catch (_) {
      // Abbruch / kein Zugriff — still ignorieren.
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Hintergrund-Foto entfernen — MIT Sicherheitsabfrage („Bist du sicher?").
  Future<void> _removeBackgroundWithConfirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161A22),
        title: const Text(
          'Foto entfernen?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Bist du dir sicher, dass du das Hintergrund-Foto entfernen möchtest?',
          style: TextStyle(color: Color(0xFFA0AEC0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Abbrechen',
              style: TextStyle(color: Color(0xFFA0AEC0)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Entfernen',
              style: TextStyle(
                color: Color(0xFFF87171),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => _bgPhoto = null);
  }

  Future<Uint8List?> _capturePng() async {
    final ctx = _captureKey.currentContext;
    if (ctx == null) return null;
    final boundary = ctx.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    final dpr = MediaQuery.of(context).devicePixelRatio.clamp(2.0, 3.0).toDouble();
    // WICHTIG: NICHT boundary.debugNeedsPaint abfragen — der Getter setzt seinen
    // Rückgabewert in einem assert(()=>...)-Block, der im RELEASE entfernt ist →
    // LateInitializationError (genau das ließ „Teilen" im Release fehlschlagen).
    // Die Paint-Bereitschaft sichert das feste Delay in _share().
    final image = await boundary.toImage(pixelRatio: dpr);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF1C1F26)),
    );
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
      // Beim Karten-Format sicherstellen, dass das Karten-Bild geladen ist,
      // bevor wir die Vorschau abfotografieren.
      if (_isMap && _mapBytes == null) await _ensureMapImage();
      // Kurz warten, damit die Vorschau sicher fertig gemalt ist. (Bewusst ein
      // fixes Delay statt WidgetsBinding.endOfFrame — letzteres kann auf einem
      // komplett idle Screen hängen, dann reagiert der Teilen-Button gar nicht.)
      await Future<void>.delayed(const Duration(milliseconds: 160));
      final png = await _capturePng();
      if (png == null || png.isEmpty) {
        debugPrint('[ShareFehler] PNG null/leer (capture)');
        _toast('Bild konnte nicht erstellt werden. Bitte erneut versuchen.');
        return;
      }
      // In eine ECHTE temporäre Datei schreiben (statt nur In-Memory) →
      // maximal kompatibel mit Instagram, WhatsApp, Fotos & Co.
      final tmpDir = await getTemporaryDirectory();
      final baseName = _isSticker ? 'cruise-route-sticker' : 'cruise-route';
      final outFile = File(
        '${tmpDir.path}/${baseName}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await outFile.writeAsBytes(png, flush: true);
      final dist = widget.data.distanceLabel;
      // Deeplink an den Text hängen → tippt der Empfänger ihn an, öffnet sich
      // die App (Android App-Link). Ein Bild kann selbst keinen Link tragen,
      // daher reist er im Begleittext mit (Caption in WhatsApp/Instagram & Co.).
      final headline = dist != null
          ? '${widget.data.title} · $dist, mit Cruise Connector'
          : '${widget.data.title}, mit Cruise Connector';
      final result = await Share.shareXFiles(
        [XFile(outFile.path, mimeType: 'image/png', name: '$baseName.png')],
        text: '$headline\n${CruiseDeepLinks.shareUrl}',
        subject: 'Cruise Connector Route',
        sharePositionOrigin: shareOrigin,
      );
      if (result.status == ShareResultStatus.unavailable) {
        _toast('Teilen ist auf diesem Gerät nicht verfügbar.');
      }
    } catch (e, st) {
      debugPrint('[ShareFehler] $e\n$st');
      // Echte Fehlerursache sichtbar machen (debugPrint loggt im Release nicht).
      final msg = e.toString().replaceAll('\n', ' ');
      _toast('Teilen-Fehler: ${msg.length > 150 ? msg.substring(0, 150) : msg}');
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
        // Hintergrund: echte Karte (Karte-Modus) oder sauberer dunkler Grund
        // (Story/Quadrat). Beim Sticker bleibt es transparent.
        if (!_isSticker) _buildBackground(),
        // Eckdaten-Karte: klar lesbar (Scrim + Schatten). Beim Sticker liegt nur
        // diese Karte auf Transparenz → PNG mit Alpha zum Drüberlegen.
        Align(
          alignment: _isSticker ? Alignment.center : Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.all(_isSticker ? 8 : 18),
            // Frei positionierbar: 1 Finger ziehen = verschieben, 2 Finger =
            // skalieren. Die transformierte Karte wird 1:1 mitfotografiert.
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onScaleStart: (_) => _scaleStartFactor = _cardScale,
              onScaleUpdate: (d) => setState(() {
                _cardScale = (_scaleStartFactor * d.scale).clamp(0.55, 2.4);
                _cardOffset += d.focalPointDelta;
              }),
              child: Transform.translate(
                offset: _cardOffset,
                child: Transform.scale(
                  scale: _cardScale,
                  child: RouteShareCard(
                    data: widget.data,
                    accent: accent,
                    showSketch: !_isMap,
                  ),
                ),
              ),
            ),
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
      // Solange die echte Karte lädt: KEIN Spinner, sondern direkt die Route auf
      // dunklem Grund → es ist immer sofort eine Route da, die echte Karte
      // blendet sich danach drüber.
      return Stack(
        fit: StackFit.expand,
        children: [
          gradient,
          if (widget.data.segments.isNotEmpty)
            CustomPaint(
              painter: _RouteLinePainter(
                segments: widget.data.segments,
                accent: AppAccentColors.accent,
              ),
            ),
        ],
      );
    }
    // Eigenes Foto/Selfie als Hintergrund (Story/Quadrat) — sonst dunkler Grund.
    if (_bgPhoto != null) return Image.memory(_bgPhoto!, fit: BoxFit.cover);
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
          // Foto/Selfie als Hintergrund (nur Story/Quadrat — Karte hat die echte
          // Karte, Sticker bleibt transparent fürs Drüberlegen).
          if (!_isMap && !_isSticker) ...[
            Row(
              children: [
                Expanded(
                  child: _photoButton(
                    _bgPhoto == null ? 'Foto' : 'Foto ändern',
                    Icons.photo_library_rounded,
                    _picking ? null : () => _pickBackground(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _photoButton(
                    'Selfie',
                    Icons.camera_alt_rounded,
                    _picking ? null : () => _pickBackground(ImageSource.camera),
                  ),
                ),
                if (_bgPhoto != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _photoButton(
                      'Entfernen',
                      Icons.delete_outline_rounded,
                      _removeBackgroundWithConfirm,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
          ],
          // Kurzer Hinweis je Modus.
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(
                  _isSticker
                      ? Icons.auto_awesome_mosaic_rounded
                      : Icons.info_outline_rounded,
                  size: 15,
                  color: const Color(0xFF8B97A8),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _isSticker
                        ? 'Transparenter Sticker, leg ihn in der Story-App über dein eigenes Foto.'
                        : _isMap
                            ? 'Echte Karte mit deiner Route, direkt teilen.'
                            : _bgPhoto != null
                                ? 'Dein Foto als Hintergrund, Karte drüber frei ziehen & skalieren.'
                                : 'Foto/Selfie als Hintergrund hinzufügen oder dunkel lassen für Chats.',
                    style: const TextStyle(
                      color: Color(0xFF8B97A8),
                      fontSize: 11.5,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Verschieben/Skalieren-Hinweis + Zurücksetzen (nur wenn verändert).
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.open_with_rounded,
                  size: 15,
                  color: Color(0xFF8B97A8),
                ),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    'Ziehen zum Verschieben · 2 Finger zum Skalieren',
                    style: TextStyle(color: Color(0xFF8B97A8), fontSize: 11.5),
                  ),
                ),
                if (_cardOffset != Offset.zero || _cardScale != 1.0)
                  GestureDetector(
                    onTap: () => setState(() {
                      _cardOffset = Offset.zero;
                      _cardScale = 1.0;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1F26),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Zurücksetzen',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
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

  Widget _photoButton(String label, IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1.0,
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
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
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
  const RouteShareCard({
    super.key,
    required this.data,
    required this.accent,
    this.showSketch = true,
  });

  final RouteShareData data;
  final Color accent;

  /// Im Karte-Modus IST der Hintergrund schon die Karte mit der Route → dann die
  /// kleine Skizze in der Card ausblenden, sonst erscheint die Route doppelt.
  final bool showSketch;

  @override
  Widget build(BuildContext context) {
    bool ok(String? s) => s != null && s.trim().isNotEmpty && s.trim() != '--';
    final stats = <(IconData, String)>[
      if (ok(data.distanceLabel)) (Icons.map_rounded, data.distanceLabel!),
      if (ok(data.durationLabel)) (Icons.timer_rounded, data.durationLabel!),
      if (ok(data.topSpeedLabel)) (Icons.speed_rounded, data.topSpeedLabel!),
      if (ok(data.styleLabel)) (Icons.tune_rounded, data.styleLabel!),
      if (ok(data.curvesLabel)) (Icons.moving_rounded, data.curvesLabel!),
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
          const SizedBox(height: 10),
          // Routen-Skizze (im Karte-Modus aus → sonst doppelte Route). Kompakter
          // gehalten, damit die Karte im Quadrat (1:1) nicht über den Rahmen geht.
          if (showSketch && data.segments.isNotEmpty)
            Container(
              height: 94,
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
          // 2026-07-28 (vucko „das Layout passt gar nicht"): Der Titel stand
          // auf fixen 20 pt. Ein langer Name wie „Kurvenreicher Donnerstag"
          // passte damit in der schmalen Sticker-Breite in keine Zeile, und
          // Flutter bricht ein einzelnes zu langes Wort MITTEN drin um —
          // im geteilten Bild stand dann „Kurvenreic / her Donn…". Jetzt
          // sucht [_FittedTitle] die groesste Schriftgroesse, bei der der
          // Titel wirklich hineinpasst; abgeschnitten wird nur noch im
          // Extremfall.
          _FittedTitle(text: data.title, maxLines: 2),
          if (data.subtitle != null) ...[
            const SizedBox(height: 5),
            _shadowText(
              data.subtitle!.toUpperCase(),
              fontSize: 11.5,
              weight: FontWeight.w700,
              color: accent,
              maxLines: 1,
              letterSpacing: 1.1,
            ),
          ],
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 14),
            // Wrap statt Row → bricht bei schmaler Breite (Sticker/Quadrat,
            // kleines Display, viele Stats) defensiv um statt zu overflowen.
            Wrap(
              spacing: 8,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 13),
          const SizedBox(width: 5),
          // Kennzahlen duerfen NIE umbrechen — „26,7 km" auf zwei Zeilen sieht
          // kaputt aus. Der Wrap oben schiebt den ganzen Chip in die naechste
          // Zeile, statt ihn zu zerlegen.
          _shadowText(label, fontSize: 12.5, weight: FontWeight.w800),
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
    double? letterSpacing,
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
        letterSpacing: letterSpacing,
        shadows: const [
          Shadow(color: Colors.black, blurRadius: 6),
          Shadow(color: Colors.black54, blurRadius: 2),
        ],
      ),
    );
  }
}

/// Titel, der sich in die verfuegbare Breite einpasst.
///
/// 2026-07-28 (vucko „das Layout passt gar nicht"): Ein fester Schriftgrad
/// bricht bei langen Routennamen mitten im Wort um. Flutter trennt ein
/// einzelnes Wort, das breiter als die Zeile ist, hart an beliebiger Stelle —
/// im geteilten Bild stand dann „Kurvenreic / her Donn…".
///
/// Diese Klasse misst den Text mit [TextPainter] und nimmt die groesste
/// Schriftgroesse, bei der er ohne Ueberlauf in [maxLines] passt UND kein
/// einzelnes Wort breiter als die Zeile ist. Erst wenn selbst die kleinste
/// Stufe nicht reicht, wird gekuerzt.
class _FittedTitle extends StatelessWidget {
  const _FittedTitle({required this.text, this.maxLines = 2});

  final String text;
  final int maxLines;

  static const double _maxSize = 22;
  static const double _minSize = 13;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final breite = constraints.maxWidth;
        var groesse = _maxSize;
        if (breite.isFinite && breite > 0) {
          for (var kandidat = _maxSize; kandidat >= _minSize; kandidat -= 0.5) {
            if (_passt(text, kandidat, breite, maxLines)) {
              groesse = kandidat;
              break;
            }
            groesse = _minSize;
          }
        }
        return Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: groesse,
            fontWeight: FontWeight.w900,
            height: 1.12,
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 6),
              Shadow(color: Colors.black54, blurRadius: 2),
            ],
          ),
        );
      },
    );
  }

  static bool _passt(String text, double groesse, double breite, int maxLines) {
    final stil = TextStyle(
      fontSize: groesse,
      fontWeight: FontWeight.w900,
      height: 1.12,
    );
    // 1) Kein EINZELNES Wort darf breiter als die Zeile sein — sonst trennt
    //    Flutter mitten im Wort, egal wie viele Zeilen erlaubt sind.
    for (final wort in text.split(RegExp(r'\s+'))) {
      if (wort.isEmpty) continue;
      final wp = TextPainter(
        text: TextSpan(text: wort, style: stil),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      if (wp.width > breite) return false;
    }
    // 2) Der ganze Text muss in maxLines passen.
    final tp = TextPainter(
      text: TextSpan(text: text, style: stil),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: breite);
    return !tp.didExceedMaxLines;
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
