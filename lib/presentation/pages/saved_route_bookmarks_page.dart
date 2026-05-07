import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/route_bookmark_provider.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';

class SavedRouteBookmarksPage extends StatefulWidget {
  const SavedRouteBookmarksPage({super.key});

  @override
  State<SavedRouteBookmarksPage> createState() =>
      _SavedRouteBookmarksPageState();
}

class _SavedRouteBookmarksPageState extends State<SavedRouteBookmarksPage> {
  bool _loadingRoutes = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadRoutes();
    });
  }

  Future<void> _loadRoutes() async {
    setState(() => _loadingRoutes = true);
    await context.read<RouteBookmarkProvider>().loadSavedRoutes();
    if (!mounted) return;
    setState(() => _loadingRoutes = false);
  }

  Future<void> _refresh() {
    return _loadRoutes();
  }

  void _startRoute(SavedRoute route) {
    CruiseModePage.pendingRoute.value = route;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouteBookmarkProvider>();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final routes = provider.savedRoutes;
    final isLoading =
        (provider.isLoadingList || _loadingRoutes) && routes.isEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          'Gespeicherte Routen',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: isLoading
          ? Center(
              child: CircularProgressIndicator(color: AppAccentColors.accent),
            )
          : RefreshIndicator(
              color: AppAccentColors.accent,
              backgroundColor: const Color(0xFF1C1F26),
              onRefresh: _refresh,
              child: routes.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(32),
                      children: [
                        const SizedBox(height: 120),
                        Icon(
                          Icons.bookmark_border,
                          color: Colors.grey[700],
                          size: 56,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Noch keine Routen gespeichert',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Merke dir geteilte Strecken aus der Community für später.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: routes.length,
                      itemBuilder: (context, index) {
                        final route = routes[index];
                        final isOwnRoute = route.userId == userId;
                        return _SavedRouteCard(
                          route: route,
                          onStart: () => _startRoute(route),
                          isOwnRoute: isOwnRoute,
                          onRename: () => _renameRoute(route),
                          onRemove: () async {
                            await SavedRoutesService.unsaveRouteEverywhere(
                              route,
                            );
                            await _refresh();
                          },
                        );
                      },
                    ),
            ),
    );
  }

  Future<void> _renameRoute(SavedRoute route) async {
    final controller = TextEditingController(text: route.name ?? route.style);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1F26),
          title: const Text(
            'Route umbenennen',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: AppInputLimits.routeNameMaxLength,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              counterStyle: const TextStyle(color: Colors.grey),
              hintText: 'Name der Route',
              hintStyle: TextStyle(color: Colors.grey[600]),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppAccentColors.accent),
              ),
            ),
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Abbrechen',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: Text(
                'Speichern',
                style: TextStyle(color: AppAccentColors.accent),
              ),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (newName == null || newName.trim().isEmpty) return;

    await SavedRoutesService.renameRoute(route.id, newName);
    await _refresh();
  }
}

class _SavedRouteCard extends StatelessWidget {
  const _SavedRouteCard({
    required this.route,
    required this.onStart,
    required this.onRemove,
    required this.onRename,
    required this.isOwnRoute,
  });

  final SavedRoute route;
  final VoidCallback onStart;
  final VoidCallback onRemove;
  final VoidCallback onRename;
  final bool isOwnRoute;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppAccentColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                route.styleEmoji,
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  route.name ?? route.style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${route.formattedDistance} · ${route.formattedDuration}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Route fahren',
            onPressed: onStart,
            icon: Icon(Icons.play_circle_fill, color: AppAccentColors.accent),
          ),
          if (isOwnRoute)
            IconButton(
              tooltip: 'Route umbenennen',
              onPressed: onRename,
              icon: const Icon(Icons.edit_outlined, color: Color(0xFFFFD166)),
            ),
          IconButton(
            tooltip: 'Gespeicherte Route entfernen',
            onPressed: onRemove,
            icon: const Icon(
              Icons.bookmark_remove_outlined,
              color: Color(0xFFFFD166),
            ),
          ),
        ],
      ),
    );
  }
}
