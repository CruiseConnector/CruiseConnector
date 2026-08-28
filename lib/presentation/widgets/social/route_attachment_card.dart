import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/kurven_zaehler.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';
import 'package:cruise_connect/presentation/pages/ride_detail_page.dart';
import 'package:cruise_connect/presentation/widgets/social/route_verlauf_sketch.dart';

/// Einheitliche Darstellung einer geteilten Route in Posts und Composer.
///
/// 2026-08-28 (vucko Fehler 7 und 8): Statt eines Kartenausschnitts zeigt die
/// Karte den VERLAUF der Strecke als Skizze auf neutralem, dunklem Grund —
/// ohne Basemap, Ortsnamen oder Massstab, und mit gekappten Endstuecken
/// (Stalking-Schutz). Darunter stehen die Eckdaten wie beim Exportieren:
/// Distanz, Dauer, Kurven, Stil und, falls vorhanden, das Hoechsttempo.
class RouteAttachmentCard extends StatefulWidget {
  const RouteAttachmentCard({
    super.key,
    required this.routeId,
    this.compact = false,
    this.showRideButton = true,
    this.fallbackTitle,
    this.fallbackStyle,
    this.fallbackDistanceKm,
    this.fallbackDurationSeconds,
    this.vorgeladeneRoute,
  });

  final String routeId;
  final bool compact;
  final bool showRideButton;
  final String? fallbackTitle;
  final String? fallbackStyle;
  final double? fallbackDistanceKm;
  final double? fallbackDurationSeconds;

  /// Bereits geladene Route — dann fragt die Karte Supabase nicht mehr.
  /// Fuer Vorschauen und Widget-Tests, in denen kein Backend existiert.
  final SavedRoute? vorgeladeneRoute;

  @override
  State<RouteAttachmentCard> createState() => _RouteAttachmentCardState();
}

class _RouteAttachmentCardState extends State<RouteAttachmentCard> {
  SavedRoute? _route;
  bool _loading = true;
  bool _opening = false;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  @override
  void didUpdateWidget(covariant RouteAttachmentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeId != widget.routeId) {
      _route = null;
      _loading = true;
      _opening = false;
      _saving = false;
      _saved = false;
      _loadRoute();
    }
  }

  Future<void> _loadRoute() async {
    final vorgeladen = widget.vorgeladeneRoute;
    if (vorgeladen != null) {
      setState(() {
        _route = vorgeladen;
        _loading = false;
      });
      return;
    }
    try {
      final route = await SavedRoutesService.getRouteById(widget.routeId);
      final saved = route == null
          ? false
          : await SavedRoutesService.isRouteSavedByUser(route.id);
      if (!mounted) return;
      setState(() {
        _route = route;
        _saved = saved;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _startRide() async {
    final route = _route;
    if (_opening || route == null) return;
    setState(() => _opening = true);
    try {
      // 2026-08-28 (vucko Fehler 8, Stalking-Schutz): NIE die rohe fremde
      // Route uebergeben. Fremde Routen werden vorn und hinten um je 1 km
      // gekappt, damit niemand an der Haustuer des Besitzers startet.
      // Waechtertest: test/route/fremdfahrt_kappung_waechter_test.dart.
      final eigeneId = Supabase.instance.client.auth.currentUser?.id;
      final fahrbareRoute = route.fuerFremdfahrt(eigeneId);
      if (fahrbareRoute == null) {
        _showSnack(
          'Diese Route ist zu kurz, um sie geteilt zu fahren.',
          error: true,
        );
        return;
      }
      CruiseModePage.pendingRoute.value = fahrbareRoute;
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _saveRoute() async {
    final route = _route;
    if (_saving || route == null || _saved) return;
    setState(() => _saving = true);
    try {
      await SavedRoutesService.saveExistingRoute(route);
      if (!mounted) return;
      setState(() => _saved = true);
      _showSnack('Route gespeichert.');
    } catch (_) {
      if (!mounted) return;
      _showSnack('Route konnte nicht gespeichert werden.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: error
            ? const Color(0xFF301B20)
            : const Color(0xFF171B24),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1250),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  String _styleEmoji(String? style) {
    switch (style) {
      case 'Kurvenjagd':
        return '🏔️';
      case 'Sport Mode':
        return '🏎️';
      case 'Abendrunde':
        return '🌙';
      case 'Entdecker':
        return '🧭';
      default:
        return '🛣️';
    }
  }

  String _fallbackDistanceLabel() {
    final distance = widget.fallbackDistanceKm;
    if (distance == null || distance <= 0) return '--';
    return '${distance.toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  String _fallbackDurationLabel() {
    final seconds = widget.fallbackDurationSeconds;
    if (seconds == null || seconds <= 0) return '--';
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final isCompact = widget.compact;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 12 : 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1C1F26),
            Color.lerp(const Color(0xFF1C1F26), AppAccentColors.accent, 0.10)!,
          ],
        ),
        borderRadius: BorderRadius.circular(isCompact ? 14 : 16),
        border: Border.all(
          color: AppAccentColors.accent.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: AppAccentColors.accent.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: _loading
          ? _buildLoading(isCompact)
          : route == null
          ? _buildFallback(isCompact)
          : _buildRoute(route, isCompact),
    );
  }

  Widget _buildLoading(bool isCompact) {
    return Row(
      children: [
        _RouteIconBox(compact: isCompact, muted: false),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Route wird geladen...',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: isCompact ? 12 : 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFallback(bool isCompact) {
    final title = widget.fallbackTitle?.trim();
    final style = widget.fallbackStyle?.trim();
    final hasFallback = title != null && title.isNotEmpty;
    return Row(
      children: [
        _RouteIconBox(compact: isCompact, muted: !hasFallback),
        const SizedBox(width: 12),
        Expanded(
          child: hasFallback
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_styleEmoji(style)} $title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isCompact ? 13 : 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_fallbackDistanceLabel()} · ${_fallbackDurationLabel()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: isCompact ? 11 : 12,
                      ),
                    ),
                  ],
                )
              : Text(
                  'Route nicht gefunden',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: isCompact ? 12 : 13,
                  ),
                ),
        ),
      ],
    );
  }

  // 2026-06-25 (vucko Routen-Detail-Page): Tippen auf Titel oder Skizze
  // öffnet die ästhetische Detailseite. Fuer fremde Routen zeigt die dort
  // ebenfalls nur die nachgezeichnete Strecke ohne Karte (Fehler 7).
  void _openDetail() {
    final route = _route;
    if (route == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RideDetailPage.fromSavedRoute(route)),
    );
  }

  Widget _buildRoute(SavedRoute route, bool isCompact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openDetail,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${route.styleEmoji} ${route.name ?? route.style}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isCompact ? 13 : 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _RouteTrustBadges(route: route, compact: isCompact),
                  ],
                ),
              ),
            ),
            if (widget.showRideButton) ...[
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RouteSquareAction(
                    compact: isCompact,
                    loading: _saving,
                    active: _saved,
                    icon: _saved
                        ? Icons.bookmark_added_rounded
                        : Icons.bookmark_add_outlined,
                    onTap: _saved ? null : _saveRoute,
                  ),
                  const SizedBox(height: 6),
                  _RouteDriveAction(
                    compact: isCompact,
                    loading: _opening,
                    onTap: _startRide,
                  ),
                ],
              ),
            ],
          ],
        ),
        SizedBox(height: isCompact ? 8 : 10),
        // 2026-08-28 (vucko Fehler 7, Stalking-Schutz): Nachgezeichnete
        // Strecke statt Kartenausschnitt. Keine Basemap, keine Ortsnamen,
        // kein Massstab — und die Endstuecke sind gekappt, damit niemand
        // die Wohngegend des Besitzers abliest.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openDetail,
          child: SizedBox(
            height: isCompact ? 84 : 128,
            width: double.infinity,
            child: RouteVerlaufSketch(
              punkte: route.flatCoordinates,
              accent: AppAccentColors.accent,
            ),
          ),
        ),
        SizedBox(height: isCompact ? 8 : 10),
        RouteAttachmentStats(route: route, compact: isCompact),
      ],
    );
  }
}

/// Eckdaten „wie beim Exportieren" (route_share_page): Distanz, Dauer,
/// Kurven, Stil und, NUR wenn ein Wert existiert, das Hoechsttempo.
/// Fehlt ein Wert, wird die Kachel weggelassen — nie ein Strich.
class RouteAttachmentStats extends StatelessWidget {
  const RouteAttachmentStats({
    super.key,
    required this.route,
    this.compact = false,
  });

  final SavedRoute route;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    bool ok(String? s) => s != null && s.trim().isNotEmpty && s.trim() != '--';
    final coords = route.flatCoordinates;
    final kurven = coords.length >= 3 ? KurvenZaehler.zaehle(coords) : 0;
    final dauer = route.durationLabelOrEstimate;
    final top = route.topSpeedKmh;
    final chips = <(IconData, String)>[
      if (route.distanceKm > 0) (Icons.map_rounded, route.formattedDistance),
      if (ok(dauer)) (Icons.timer_rounded, dauer),
      if (kurven > 0) (Icons.moving_rounded, '$kurven Kurven'),
      if (ok(route.displayStyleLabel))
        (Icons.tune_rounded, route.displayStyleLabel),
      if (top != null && top > 0)
        (Icons.speed_rounded, '${top.toStringAsFixed(0)} km/h'),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final c in chips) _chip(c.$1, c.$2, accent)],
    );
  }

  Widget _chip(IconData icon, String label, Color accent) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 9,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: compact ? 12 : 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 11.5 : 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteIconBox extends StatelessWidget {
  const _RouteIconBox({required this.compact, required this.muted});

  final bool compact;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 36 : 44,
      height: compact ? 36 : 44,
      decoration: BoxDecoration(
        color: muted
            ? Colors.white.withValues(alpha: 0.05)
            : AppAccentColors.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: muted
            ? null
            : Border.all(color: AppAccentColors.accent.withValues(alpha: 0.28)),
      ),
      child: Icon(
        Icons.route_rounded,
        color: muted ? Colors.white54 : AppAccentColors.accent,
        size: compact ? 18 : 22,
      ),
    );
  }
}

class _RouteSquareAction extends StatelessWidget {
  const _RouteSquareAction({
    required this.compact,
    required this.loading,
    required this.active,
    required this.icon,
    required this.onTap,
  });

  final bool compact;
  final bool loading;
  final bool active;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: compact ? 34 : 38,
        height: compact ? 34 : 38,
        decoration: BoxDecoration(
          color: active
              ? AppAccentColors.accent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: active
                ? AppAccentColors.accent.withValues(alpha: 0.34)
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              )
            : Icon(
                icon,
                color: active ? AppAccentColors.accent : Colors.white70,
                size: compact ? 18 : 20,
              ),
      ),
    );
  }
}

class _RouteDriveAction extends StatelessWidget {
  const _RouteDriveAction({
    required this.compact,
    required this.loading,
    required this.onTap,
  });

  final bool compact;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 16,
          vertical: compact ? 7 : 10,
        ),
        decoration: BoxDecoration(
          color: AppAccentColors.accent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                'Fahren',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 11 : 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}

class _RouteTrustBadges extends StatelessWidget {
  const _RouteTrustBadges({required this.route, required this.compact});

  final SavedRoute route;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[
      _RouteRatingBadge(route: route, compact: compact),
      if (route.qualityBadgeLabel != null)
        _RouteTrustBadge(
          icon: Icons.verified_rounded,
          label: route.qualityBadgeLabel!,
          compact: compact,
          accent: AppAccentColors.accent,
        ),
      // 2026-08-28: Der Stil steht jetzt in den Eckdaten-Chips unter der
      // Skizze (RouteAttachmentStats) — hier nicht mehr doppelt.
    ];

    return Wrap(spacing: 6, runSpacing: 6, children: badges);
  }
}

class _RouteRatingBadge extends StatelessWidget {
  const _RouteRatingBadge({required this.route, required this.compact});

  final SavedRoute route;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final score = route.displayRating;
    final label = route.ratingTrustLabel;
    if (score == null || label == null) {
      return _RouteTrustBadge(
        icon: Icons.star_border_rounded,
        label: 'Noch keine Bewertung',
        compact: compact,
        accent: Colors.white54,
        muted: true,
      );
    }
    final filledStars = (score >= 4.4 ? 5 : score.round()).clamp(1, 5);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 9,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD76A).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFFFD76A).withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...List.generate(5, (index) {
            return Icon(
              index < filledStars
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              color: const Color(0xFFFFD76A),
              size: compact ? 11 : 12,
            );
          }),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteTrustBadge extends StatelessWidget {
  const _RouteTrustBadge({
    required this.icon,
    required this.label,
    required this.compact,
    required this.accent,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final bool compact;
  final Color accent;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 8,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent.withValues(alpha: muted ? 0.16 : 0.24),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: compact ? 12 : 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
