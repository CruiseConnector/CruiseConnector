import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cruise_connect/application/providers/route_bookmark_provider.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';

class SavedRouteBookmarksPage extends StatefulWidget {
  const SavedRouteBookmarksPage({super.key});

  @override
  State<SavedRouteBookmarksPage> createState() =>
      _SavedRouteBookmarksPageState();
}

class _SavedRouteBookmarksPageState extends State<SavedRouteBookmarksPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<RouteBookmarkProvider>().loadSavedRoutes();
    });
  }

  Future<void> _refresh() {
    return context.read<RouteBookmarkProvider>().loadSavedRoutes();
  }

  void _startRoute(SavedRoute route) {
    CruiseModePage.pendingRoute.value = route;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouteBookmarkProvider>();
    final routes = provider.savedRoutes;

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
      body: provider.isLoadingList && routes.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF3B30)),
            )
          : RefreshIndicator(
              color: const Color(0xFFFF3B30),
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
                          'Merke dir geteilte Strecken aus der Community fuer spaeter.',
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
                        return _SavedRouteCard(
                          route: route,
                          onStart: () => _startRoute(route),
                          onRemove: () async {
                            await context.read<RouteBookmarkProvider>().toggle(
                              route.id,
                            );
                          },
                        );
                      },
                    ),
            ),
    );
  }
}

class _SavedRouteCard extends StatelessWidget {
  const _SavedRouteCard({
    required this.route,
    required this.onStart,
    required this.onRemove,
  });

  final SavedRoute route;
  final VoidCallback onStart;
  final VoidCallback onRemove;

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
              color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
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
            icon: const Icon(Icons.play_circle_fill, color: Color(0xFFFF3B30)),
          ),
          IconButton(
            tooltip: 'Lesezeichen entfernen',
            onPressed: onRemove,
            icon: const Icon(Icons.bookmark, color: Color(0xFFFFD166)),
          ),
        ],
      ),
    );
  }
}
