import 'package:flutter/material.dart';
import 'package:cruise_connect/presentation/widgets/photo/ride_photo_picker.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/group_leaderboard_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/domain/models/user_drive_session.dart';
import 'package:cruise_connect/presentation/pages/route_share_page.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_maplibre_map.dart';

/// Strava-artige Detailansicht einer abgeschlossenen Fahrt.
///
/// 2026-06-25 (vucko): Aufrufbar aus Analytics-„Letzte Fahrten", gespeicherten
/// Routen und geteilten Routen. Zeigt die GEFAHRENE Strecke akkurat auf einer
/// echten dunklen Karte + alle Eckdaten (Modus, Distanz, Dauer, Ø/Top-Speed,
/// Kurven, XP) ästhetisch, das hinzugefügte Foto (persistiert), und bei
/// Gruppen-Fahrten die interne Rangliste + Teilnehmer. Teilen öffnet den
/// Strava-Share-Composer mit der echten Route.
class RideDetailPage extends StatefulWidget {
  const RideDetailPage({
    super.key,
    required this.session,
    this.allowPhoto = true,
    this.savedRouteId,
  });

  /// Detailansicht für eine GESPEICHERTE Route (statt einer gefahrenen Session).
  /// Baut eine Anzeige-Session aus der Route. Bei EIGENER Route darf ein Foto
  /// hinzugefügt/geändert werden (persistiert an routes.photo_url); zusätzlich
  /// zeigt sie das Foto der zugehörigen gefahrenen Fahrt (per Fingerprint).
  factory RideDetailPage.fromSavedRoute(SavedRoute route) {
    final coords = route.flatCoordinates;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwn = route.userId != null && route.userId == currentUserId;
    return RideDetailPage(
      allowPhoto: isOwn,
      savedRouteId: isOwn ? route.id : null,
      session: UserDriveSession(
        id: route.id,
        userId: route.userId ?? '',
        routeId: route.id,
        distanceKm: route.distanceKm,
        durationSeconds: (route.durationSeconds ?? 0).round(),
        xpAwarded: route.xpAwarded ?? 0,
        completedAtEnd: route.completedAtEnd,
        createdAt: route.createdAt,
        routeStyle: route.displayStyleLabel,
        routeType: route.routeType,
        groupId: route.groupId,
        trackGeometry: coords.length >= 2 ? coords : null,
        // Fingerprint mitführen → die gespeicherte Route kann das Foto der
        // zugehörigen GEFAHRENEN Fahrt nachladen (Single Source of Truth).
        routeFingerprint: route.routeFingerprint,
        // Eigenes Foto der Route (falls direkt gesetzt).
        photoUrl: route.photoUrl,
      ),
    );
  }

  final UserDriveSession session;
  final bool allowPhoto;

  /// Wenn gesetzt: dies ist eine eigene GESPEICHERTE Route — Foto wird an
  /// routes.photo_url persistiert (nicht an einer Drive-Session).
  final String? savedRouteId;

  @override
  State<RideDetailPage> createState() => _RideDetailPageState();
}

class _RideDetailPageState extends State<RideDetailPage> {
  static const _months = [
    'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
    'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
  ];

  String? _photoUrl;
  bool _photoBusy = false;
  List<GroupLeaderboardEntry> _leaderboard = const [];
  bool _leaderboardLoading = false;

  UserDriveSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _photoUrl = _s.photoUrl;
    if (_s.isGroupRide) _loadLeaderboard();
    // Gespeicherte Route ohne eigenes Foto: das Foto der zugehörigen gefahrenen
    // Fahrt (per route_fingerprint) nachladen → erscheint bei „gespeicherte
    // Routen" konsistent, verschwindet nicht mehr.
    if (_photoUrl == null && (_s.routeFingerprint?.trim().isNotEmpty ?? false)) {
      _loadLinkedRidePhoto();
    }
  }

  Future<void> _loadLinkedRidePhoto() async {
    final url = await GamificationService.photoUrlForRouteFingerprint(
      _s.routeFingerprint!,
    );
    if (!mounted || url == null) return;
    setState(() => _photoUrl = url);
  }

  Future<void> _loadLeaderboard() async {
    setState(() => _leaderboardLoading = true);
    final rows = await GroupLeaderboardService.fetch(_s.groupId!);
    if (!mounted) return;
    setState(() {
      _leaderboard = rows;
      _leaderboardLoading = false;
    });
  }

  // ── Formatierung ───────────────────────────────────────────────────────────
  String get _styleLabel => (_s.routeStyle?.trim().isNotEmpty == true)
      ? _s.routeStyle!.trim()
      : 'Cruise';

  String get _modusLabel => switch (_s.routeType) {
    'ROUND_TRIP' => 'Rundkurs',
    'POINT_TO_POINT' => 'A → B',
    _ => _styleLabel,
  };

  String _formatDistance(double km) =>
      km >= 100 ? '${km.toStringAsFixed(0)} km' : '${km.toStringAsFixed(1)} km';

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    final s = seconds % 60;
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  String _formatDate(DateTime dt) {
    final l = dt.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '${l.day}. ${_months[l.month - 1]} ${l.year} · $hh:$mm';
  }

  double? get _avgKmh => _s.durationSeconds > 0
      ? _s.distanceKm / (_s.durationSeconds / 3600.0)
      : null;

  // ── Kurven aus dem Track ────────────────────────────────────────────────────
  // 2026-06-25 (vucko): EINE Quelle der Wahrheit — derselbe akkurate,
  // dichte-unabhängige Zähler wie im Route-Banner (GamificationService).
  // Vorher hatte die Detail-Übersicht ihren eigenen, abweichenden Zähler
  // (Schwelle 32°, Index-Stride) → andere Kurvenzahl als beim Berechnen.
  int? get _curveCount {
    final t = _s.trackGeometry;
    if (t == null || t.length < 3) return null;
    return GamificationService.countCurves(t);
  }

  // ── Foto ───────────────────────────────────────────────────────────────────
  Future<void> _changePhoto() async {
    if (_photoBusy) return;
    try {
      // Foto wählen + Ausschnitt/Zoom festlegen. Festes 4:3 = exakt das
      // Anzeige-Format der Foto-Sektion → was zugeschnitten wird ist genau das,
      // was später gezeigt wird (nichts wird nachträglich weggeschnitten).
      final bytes = await pickAndCropRidePhoto(context, lockedAspect: 4 / 3);
      if (bytes == null) return;
      setState(() => _photoBusy = true);
      final oldUrl = _photoUrl;
      final url = await SocialService.uploadUserAsset(
        bucket: 'ride-photos',
        bytes: bytes,
        fileName: '${_s.id}.jpg',
        contentType: 'image/jpeg',
      );
      if (url != null) {
        // Persistenz: eigene GESPEICHERTE Route → routes.photo_url, sonst die
        // gefahrene Drive-Session. Beide RLS-gehärtet (.select bestätigt Treffer).
        final ok = widget.savedRouteId != null
            ? await SavedRoutesService.updateRoutePhoto(widget.savedRouteId!, url)
            : await GamificationService.updateDriveSessionPhoto(_s.id, url);
        // Altes Foto entfernen, falls es unter einem ANDEREN Pfad lag (z.B. ein
        // Post-Route-Foto ride_<ts>.jpg) → kein verwaister Storage-Müll. Bei
        // gleichem Pfad hat der upsert die Datei bereits überschrieben.
        if (oldUrl != null) {
          final oldPath = SocialService.storagePathFromPublicUrl(
            'ride-photos',
            oldUrl,
          );
          final newPath = SocialService.storagePathFromPublicUrl(
            'ride-photos',
            url,
          );
          if (oldPath != null && oldPath != newPath) {
            await SocialService.deleteUserAsset(
              bucket: 'ride-photos',
              publicUrl: oldUrl,
            );
          }
        }
        if (mounted) {
          setState(() => _photoUrl = url);
          // Explizite Speichern-Bestätigung → der Nutzer sieht eindeutig, dass
          // das Foto wirklich gesichert wurde (oder eben nicht).
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ok ? 'Foto gespeichert ✓' : 'Foto konnte nicht gespeichert werden'),
              backgroundColor: const Color(0xFF1C1F26),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else if (mounted) {
        // Upload selbst ist (nach 3 Versuchen) gescheitert → ehrlich melden,
        // statt still nichts zu tun. So weiß der Nutzer, dass er es erneut
        // versuchen muss (kein „verschwundenes" Foto).
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto konnte nicht hochgeladen werden, bitte erneut versuchen.'),
            backgroundColor: Color(0xFF1C1F26),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto konnte nicht gespeichert werden.'),
            backgroundColor: Color(0xFF1C1F26),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removePhoto() async {
    if (_photoBusy) return;
    setState(() => _photoBusy = true);
    final oldUrl = _photoUrl;
    if (widget.savedRouteId != null) {
      await SavedRoutesService.updateRoutePhoto(widget.savedRouteId!, null);
    } else {
      await GamificationService.updateDriveSessionPhoto(_s.id, null);
    }
    // Auch die Bild-Datei aus dem Storage löschen → kein verwaister Müll.
    if (oldUrl != null) {
      await SocialService.deleteUserAsset(
        bucket: 'ride-photos',
        publicUrl: oldUrl,
      );
    }
    if (mounted) {
      setState(() {
        _photoUrl = null;
        _photoBusy = false;
      });
    }
  }

  // ── Teilen ─────────────────────────────────────────────────────────────────
  void _openShare() {
    final track = _s.trackGeometry;
    final segments = (track != null && track.length >= 2)
        ? <List<Offset>>[
            [for (final p in track) Offset(p[0], p[1])],
          ]
        : const <List<Offset>>[];
    final top = _s.topSpeedKmh;
    final curves = _curveCount;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteSharePage(
          data: RouteShareData(
            title: _styleLabel,
            subtitle: _formatDate(_s.createdAt),
            segments: segments,
            distanceLabel: _formatDistance(_s.distanceKm),
            durationLabel: _formatDuration(_s.durationSeconds),
            topSpeedLabel:
                top != null && top > 0 ? '${top.toStringAsFixed(0)} km/h' : null,
            styleLabel: _modusLabel,
            curvesLabel: curves != null ? '$curves Kurven' : null,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final topSpeed = _s.topSpeedKmh;
    final avg = _avgKmh;
    final track = _s.trackGeometry;
    final hasTrack = track != null && track.length >= 2;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Fahrt',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
            tooltip: 'Teilen',
            onPressed: _openShare,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          if (hasTrack) _buildMapHero(track, accent) else _buildGradientHero(accent),
          if (widget.allowPhoto || _photoUrl != null) ...[
            const SizedBox(height: 16),
            _buildPhotoSection(accent),
          ],
          const SizedBox(height: 16),
          _buildStatGrid(accent, topSpeed, avg),
          if (_s.isGroupRide) ...[
            const SizedBox(height: 20),
            _buildGroupRanking(accent),
          ],
        ],
      ),
    );
  }

  // ── Karten-Hero (echte gefahrene Strecke) ──────────────────────────────────
  /// Siehe onControllerReady in _buildMapHero: die Kamera wird genau einmal
  /// auf die Strecke eingepasst, danach gehoert der Zoom dem Nutzer.
  bool _kartePasst = false;

  Widget _buildMapHero(List<List<double>> track, Color accent) {
    final pts = [for (final p in track) ll.LatLng(p[1], p[0])];
    double sumLat = 0, sumLng = 0;
    for (final p in pts) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    final center = ll.LatLng(sumLat / pts.length, sumLng / pts.length);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 286,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CruiseMapLibreMap(
              initialCenter: center,
              initialZoom: 11,
              rotateGestures: false,
              // 2026-08-25 (vucko, Feld-Meldung „ich will in der Karte zoomen
              // koennen und sehen wie er gefahren ist"): Die Karte ist das
              // erste Kind eines ListView. Ohne eigenen Gesten-Erkenner gewinnt
              // dessen Zieh-Erkenner die Gesten-Arena, und die Karte bekam nur
              // Tipps — deshalb reagierte das Attributionszeichen, aber weder
              // Ziehen noch Zwei-Finger-Zoom. Derselbe Fall war in
              // create_group_page.dart schon einmal so geloest.
              // Folge: ueber der Karte scrollt die Seite nicht mehr per
              // Wischen. Das ist gewollt, gescrollt wird unter der Karte.
              eagerGestures: true,
              lines: [
                CruiseMapLine(points: pts, color: accent, width: 6),
              ],
              onControllerReady: (c) {
                // NUR EINMAL einpassen. onControllerReady haengt am Ende von
                // _onStyleLoaded, und das feuert auf iOS mehrfach. Ohne diese
                // Sperre schnappt die Kamera nach einem Style-Nachladen in die
                // Uebersicht zurueck und wirft den Nutzer aus seinem Zoom.
                // Bisher fiel das nicht auf, weil niemand zoomen konnte.
                if (_kartePasst) return;
                _kartePasst = true;
                c.fitBounds(pts, padding: const EdgeInsets.all(46));
              },
            ),
            // Lese-Schutz oben/unten für Pille + Titel.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.32),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.62),
                    ],
                    stops: const [0.0, 0.22, 0.62, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: _statusPill(),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _shadowed(
                      _styleLabel,
                      size: 22,
                      weight: FontWeight.w900,
                    ),
                    const SizedBox(height: 2),
                    _shadowed(
                      _formatDate(_s.createdAt),
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientHero(Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(accent, Colors.black, 0.12)!,
            Color.lerp(accent, Colors.black, 0.46)!,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusPill(),
          const SizedBox(height: 14),
          Text(
            _styleLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatDate(_s.createdAt),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill() {
    final isGroup = _s.isGroupRide;
    final label = isGroup
        ? 'Gruppenfahrt'
        : (_s.completedAtEnd ? 'Abgeschlossen' : 'Aufgezeichnet');
    final icon = isGroup
        ? Icons.groups_rounded
        : (_s.completedAtEnd ? Icons.flag_rounded : Icons.route_rounded);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _shadowed(
    String text, {
    required double size,
    required FontWeight weight,
    Color color = Colors.white,
  }) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: weight,
        height: 1.1,
        shadows: const [
          Shadow(color: Colors.black, blurRadius: 6),
          Shadow(color: Colors.black54, blurRadius: 2),
        ],
      ),
    );
  }

  // ── Foto ───────────────────────────────────────────────────────────────────
  Widget _buildPhotoSection(Color accent) {
    final url = _photoUrl;
    if (url != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => Container(
                  color: const Color(0xFF1C1F26),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.broken_image_rounded,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
          ),
          // Bearbeiten/Entfernen nur bei einer ECHTEN Drive-Session (allowPhoto).
          // Bei gespeicherten Routen wird das Foto der zugehörigen Fahrt nur
          // angezeigt (read-only) — Bearbeiten geht dort über „zuletzt gefahren".
          if (widget.allowPhoto)
            Positioned(
              right: 8,
              top: 8,
              child: Row(
                children: [
                  _circleBtn(
                    Icons.edit_rounded,
                    _photoBusy ? null : _changePhoto,
                  ),
                  const SizedBox(width: 8),
                  _circleBtn(
                    Icons.delete_outline_rounded,
                    _photoBusy ? null : _removePhoto,
                  ),
                ],
              ),
            ),
          if (_photoBusy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            ),
        ],
      );
    }
    return Material(
      color: const Color(0xFF1C1F26),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _photoBusy ? null : _changePhoto,
        child: Container(
          height: 64,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_photoBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              else
                Icon(Icons.add_a_photo_rounded, color: accent, size: 20),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  'Foto zu dieser Fahrt hinzufügen',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
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

  Widget _circleBtn(IconData icon, VoidCallback? onTap) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  // ── Stat-Grid ──────────────────────────────────────────────────────────────
  Widget _buildStatGrid(Color accent, double? topSpeed, double? avg) {
    final curves = _curveCount;
    final tiles = <Widget>[
      _statTile('Distanz', _formatDistance(_s.distanceKm), Icons.map_rounded, accent),
      _statTile('Dauer', _formatDuration(_s.durationSeconds), Icons.timer_rounded, accent),
      // 2026-08-25 (vucko): Fehlt ein Wert, wird die Kachel WEGGELASSEN statt
      // einen Gedankenstrich zu zeigen. Zwei Gruende: in Nutzertexten kommen
      // keine Striche vor, und eine leere Kachel behauptet, es gaebe hier eine
      // Angabe. Beim Hoechsttempo ist genau das der Fall — es steht in
      // `user_drive_sessions`, die Routentabelle hat gar keine Spalte dafuer,
      // also ist der Wert bei einer geteilten fremden Route immer null.
      if (topSpeed != null && topSpeed > 0)
        _statTile(
          'Höchsttempo',
          '${topSpeed.toStringAsFixed(0)} km/h',
          Icons.speed_rounded,
          accent,
        ),
      if (avg != null && avg > 0)
        _statTile(
          'Ø Tempo',
          '${avg.toStringAsFixed(0)} km/h',
          Icons.trending_up_rounded,
          accent,
        ),
      _statTile('Modus', _modusLabel, Icons.tune_rounded, accent),
      if (curves != null)
        _statTile('Kurven', '$curves', Icons.moving_rounded, accent),
      _statTile('XP', '${_s.xpAwarded}', Icons.bolt_rounded, accent),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        const spacing = 12.0;
        final tileW = (c.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final t in tiles) SizedBox(width: tileW, child: t),
          ],
        );
      },
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color accent) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFA0AEC0),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  // ── Gruppen-Rangliste ──────────────────────────────────────────────────────
  Widget _buildGroupRanking(Color accent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Rangliste der Gruppe',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (_leaderboard.isNotEmpty)
                Text(
                  '${_leaderboard.length} Teilnehmer',
                  style: const TextStyle(
                    color: Color(0xFFA0AEC0),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_leaderboardLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            )
          else if (_leaderboard.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Für diese Gruppe gibt es noch keine Rangliste.',
                style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
              ),
            )
          else
            for (var i = 0; i < _leaderboard.length; i++)
              _rankRow(i + 1, _leaderboard[i], accent),
        ],
      ),
    );
  }

  Widget _rankRow(int rank, GroupLeaderboardEntry e, Color accent) {
    final isSelf = e.userId == _s.userId;
    final medal = switch (rank) {
      1 => const Color(0xFFFFD166),
      2 => const Color(0xFFCBD5E1),
      3 => const Color(0xFFD9A066),
      _ => const Color(0xFF6B7280),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isSelf ? accent.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isSelf
            ? Border.all(color: accent.withValues(alpha: 0.45))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: medal,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 6),
          CircleAvatar(
            radius: 15,
            backgroundColor: const Color(0xFF2A2F3A),
            backgroundImage:
                (e.avatarUrl != null && e.avatarUrl!.isNotEmpty)
                    ? NetworkImage(e.avatarUrl!)
                    : null,
            child: (e.avatarUrl == null || e.avatarUrl!.isEmpty)
                ? const Icon(Icons.person, size: 16, color: Color(0xFF8B95A7))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              e.username?.trim().isNotEmpty == true
                  ? e.username!.trim()
                  : 'Fahrer',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: isSelf ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatDistance(e.totalDistanceKm),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (e.maxTopSpeedKmh > 0)
                Text(
                  '${e.maxTopSpeedKmh.toStringAsFixed(0)} km/h',
                  style: const TextStyle(
                    color: Color(0xFFA0AEC0),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
