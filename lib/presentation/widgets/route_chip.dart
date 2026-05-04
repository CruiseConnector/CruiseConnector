import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';

/// Klickbarer Chip für Posts mit `shared_route_id`.
/// Tap lädt die Route via [SavedRoutesService.getRouteById] und stößt den
/// `pendingRoute`-Mechanismus von [CruiseModePage] an — die Home-Page wechselt
/// dann automatisch in den Cruise-Tab und die Route wird zum Nachfahren
/// vorbereitet (Karte zentriert, Manöver geladen).
class RouteChip extends StatefulWidget {
  final String routeId;
  const RouteChip({super.key, required this.routeId});

  @override
  State<RouteChip> createState() => _RouteChipState();
}

class _RouteChipState extends State<RouteChip> {
  bool _loading = false;

  Future<void> _openRoute() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final route = await SavedRoutesService.getRouteById(widget.routeId);
      if (!mounted) return;
      if (route == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Route nicht gefunden'),
            backgroundColor: Color(0xFF1C1F26),
          ),
        );
        return;
      }
      // pendingRoute → home_page wechselt in den Cruise-Tab,
      // CruiseModePage._onPendingRoute() lädt die Route in die Map.
      CruiseModePage.pendingRoute.value = route;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openRoute,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppAccentColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppAccentColors.accent.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppAccentColors.accent,
                ),
              )
            else
              Icon(
                Icons.play_circle_outline,
                color: AppAccentColors.accent,
                size: 16,
              ),
            const SizedBox(width: 6),
            Text(
              'Route fahren',
              style: TextStyle(
                color: AppAccentColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
