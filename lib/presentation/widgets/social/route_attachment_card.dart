import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';

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
      _loadRoute();
    }
  }

  Future<void> _loadRoute() async {
    try {
      final route = await SavedRoutesService.getRouteById(widget.routeId);
      if (!mounted) return;
      setState(() {
        _route = route;
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

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final isCompact = widget.compact;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 12 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(isCompact ? 14 : 16),
        border: Border.all(
          color: AppAccentColors.accent.withValues(alpha: 0.25),
        ),
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
                    color: AppAccentColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.route,
                    color: AppAccentColors.accent,
                    size: isCompact ? 18 : 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
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
                      const SizedBox(height: 8),
                      _RouteTrustBadges(route: route, compact: isCompact),
                    ],
                  ),
                ),
                if (widget.showRideButton) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _startRide,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 12 : 16,
                        vertical: isCompact ? 8 : 10,
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
                                fontSize: isCompact ? 12 : 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
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
      if (route.ratingSummaryLabel != null)
        _RouteTrustBadge(
          icon: Icons.star_rounded,
          label: route.ratingSummaryLabel!,
          compact: compact,
          accent: const Color(0xFFFFD76A),
        ),
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

class _RouteTrustBadge extends StatelessWidget {
  const _RouteTrustBadge({
    required this.icon,
    required this.label,
    required this.compact,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final bool compact;
  final Color accent;

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
        border: Border.all(color: accent.withValues(alpha: 0.24)),
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
