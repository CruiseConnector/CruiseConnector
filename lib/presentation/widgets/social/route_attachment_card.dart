import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';
import 'package:cruise_connect/presentation/pages/ride_detail_page.dart';

/// Einheitliche Darstellung einer geteilten Route in Posts und Composer.
class RouteAttachmentCard extends StatefulWidget {
  const RouteAttachmentCard({
    super.key,
    required this.routeId,
    this.compact = false,
    this.showRideButton = true,
  });

  final String routeId;
  final bool compact;
  final bool showRideButton;

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
    if (_opening || _route == null) return;
    setState(() => _opening = true);
    try {
      CruiseModePage.pendingRoute.value = _route;
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
          ? Row(
              children: [
                Container(
                  width: isCompact ? 36 : 44,
                  height: isCompact ? 36 : 44,
                  decoration: BoxDecoration(
                    color: AppAccentColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.route,
                    color: AppAccentColors.accent,
                    size: 20,
                  ),
                ),
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
            )
          : route == null
          ? Row(
              children: [
                Container(
                  width: isCompact ? 36 : 44,
                  height: isCompact ? 36 : 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.route,
                    color: Colors.white54,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Route nicht gefunden',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: isCompact ? 12 : 13,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  width: isCompact ? 36 : 44,
                  height: isCompact ? 36 : 44,
                  decoration: BoxDecoration(
                    color: AppAccentColors.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppAccentColors.accent.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Icon(
                    Icons.route_rounded,
                    color: AppAccentColors.accent,
                    size: isCompact ? 18 : 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  // 2026-06-25 (vucko Routen-Detail-Page): Tippen auf die Info
                  // öffnet die ästhetische Detailseite (Karte + Eckdaten).
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RideDetailPage.fromSavedRoute(route),
                      ),
                    ),
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
                      const SizedBox(height: 3),
                      Text(
                        '${route.formattedDistance} · ${route.formattedDuration}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: isCompact ? 11 : 12,
                        ),
                      ),
                      const SizedBox(height: 7),
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
                      GestureDetector(
                        onTap: _saveRoute,
                        child: Container(
                          width: isCompact ? 34 : 38,
                          height: isCompact ? 34 : 38,
                          decoration: BoxDecoration(
                            color: _saved
                                ? AppAccentColors.accent.withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: _saved
                                  ? AppAccentColors.accent.withValues(
                                      alpha: 0.34,
                                    )
                                  : Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: _saving
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
                                  _saved
                                      ? Icons.bookmark_added_rounded
                                      : Icons.bookmark_add_outlined,
                                  color: _saved
                                      ? AppAccentColors.accent
                                      : Colors.white70,
                                  size: isCompact ? 18 : 20,
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: _startRide,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 10 : 16,
                            vertical: isCompact ? 7 : 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppAccentColors.accent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _opening
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
                                    fontSize: isCompact ? 11 : 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
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
      _RouteTrustBadge(
        icon: Icons.tune_rounded,
        label: route.displayStyleLabel,
        compact: compact,
        accent: const Color(0xFF7DD3FC),
      ),
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
