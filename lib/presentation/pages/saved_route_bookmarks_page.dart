import 'package:flutter/material.dart';
import 'package:cruise_connect/presentation/widgets/skeletons/route_card_skeleton.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/route_bookmark_provider.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/pages/create_post_page.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';
import 'package:cruise_connect/presentation/pages/ride_detail_page.dart';
import 'package:cruise_connect/presentation/pages/route_share_page.dart';
import 'package:cruise_connect/presentation/widgets/social/route_teilen_hinweis_sheet.dart';

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
    // 2026-08-28 (vucko Fehler 8, Stalking-Schutz): Gemerkte Routen aus der
    // Community gehoeren fremden Nutzern — vor dem Fahren vorn und hinten
    // je 1 km kappen, eigene Routen bleiben unveraendert.
    final eigeneId = Supabase.instance.client.auth.currentUser?.id;
    final fahrbareRoute = route.fuerFremdfahrt(eigeneId);
    if (fahrbareRoute == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Diese Route ist zu kurz, um sie geteilt zu fahren.'),
          backgroundColor: Color(0xFF301B20),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    CruiseModePage.pendingRoute.value = fahrbareRoute;
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
          ? const RouteCardSkeletonList(count: 3)
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
                          isOwnRoute: isOwnRoute,
                          onOpen: () => _showRouteOptions(route),
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

  void _showRouteOptions(SavedRoute route) {
    final isOwnRoute =
        route.userId == Supabase.instance.client.auth.currentUser?.id;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      route.name ?? route.style,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${route.formattedDistance} · ${route.formattedDuration}',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  _buildOptionTile(
                    Icons.map_outlined,
                    'Übersicht',
                    AppAccentColors.accent,
                    () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RideDetailPage.fromSavedRoute(route),
                        ),
                      );
                    },
                  ),
                  _buildOptionTile(
                    Icons.play_circle_fill,
                    'Nochmal fahren',
                    const Color(0xFF34D399),
                    () {
                      Navigator.pop(ctx);
                      _startRoute(route);
                    },
                  ),
                  if (isOwnRoute)
                    _buildOptionTile(
                      Icons.edit_outlined,
                      'Route umbenennen',
                      const Color(0xFFFFD166),
                      () {
                        Navigator.pop(ctx);
                        _renameRoute(route);
                      },
                    ),
                  _buildOptionTile(
                    Icons.share,
                    'Als Post teilen',
                    const Color(0xFF00E5FF),
                    () {
                      Navigator.pop(ctx);
                      _shareRouteAsPost(route);
                    },
                  ),
                  _buildOptionTile(
                    Icons.ios_share_rounded,
                    'Extern als Bild teilen',
                    const Color(0xFFD7B48A),
                    () {
                      Navigator.pop(ctx);
                      _shareRouteExternally(route);
                    },
                  ),
                  // 2026-08-31 (Vucko, Hinweis vor dem Teilen): „danach nur
                  // noch auf Wunsch". Der Hinweis erscheint von selbst nur
                  // beim ersten Mal — ohne diesen Eintrag koennte ihn danach
                  // niemand mehr nachlesen.
                  _buildOptionTile(
                    Icons.lock_outline,
                    'Schutz beim Teilen',
                    const Color(0xFF9AA7B8),
                    () {
                      Navigator.pop(ctx);
                      zeigeRouteTeilenHinweis(
                        context,
                        ziel: RouteTeilenZiel.beitrag,
                        force: true,
                      );
                    },
                  ),
                  _buildOptionTile(
                    Icons.delete_outline,
                    'Löschen',
                    const Color(0xFFFF5A5F),
                    () {
                      Navigator.pop(ctx);
                      _removeRoute(route);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _removeRoute(SavedRoute route) async {
    final confirmed = await _confirmRemoveRoute(route);
    if (confirmed != true || !mounted) return;

    try {
      await context.read<RouteBookmarkProvider>().removeRouteEverywhere(route);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Route und zugehörige Posts wurden entfernt.'),
          backgroundColor: Color(0xFF1C1F26),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Route konnte nicht entfernt werden.'),
          backgroundColor: Color(0xFF301B20),
        ),
      );
    }
  }

  Future<bool?> _confirmRemoveRoute(SavedRoute route) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1F26),
          title: const Text(
            'Route entfernen?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Wenn du "${route.name ?? route.style}" entfernst, werden auch deine Posts mit dieser Route gelöscht, inklusive der Posts in Communities und in deren Chats.',
            style: const TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'Abbrechen',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                'Entfernen',
                style: TextStyle(color: AppAccentColors.accent),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOptionTile(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      onTap: onTap,
    );
  }

  // 2026-08-31 (Vucko, Hinweis vor dem Teilen): „Kommt bevor jetzt jemand
  // eine Strecke teilt, dass man sich keine Gedanken machen muss, dass die
  // Strecke dann spaeter andockt." Der Hinweis kommt VOR dem Composer, nicht
  // danach — wer abbricht, hat nichts angefangen. Beim zweiten Mal ist er
  // weg (Merker in den SharedPreferences); nachlesen laesst er sich ueber
  // „Schutz beim Teilen" im Optionsblatt.
  Future<void> _shareRouteAsPost(SavedRoute route) async {
    final weiter = await zeigeRouteTeilenHinweis(
      context,
      ziel: RouteTeilenZiel.beitrag,
    );
    if (!weiter || !mounted) return;
    final routeText =
        '${route.styleEmoji} ${route.name ?? route.style}\n'
        '${route.formattedDistance} · ${route.formattedDuration}\n\n';
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CreatePostPage(initialText: routeText, sharedRouteId: route.id),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  // 2026-08-31 (Vucko, Hinweis vor dem Teilen): Auch hier, aber mit EIGENEM
  // Text. Das Bild entsteht auf dem Geraet, und im Composer gibt es das
  // Format „Karte" mit echter Basemap — die Zusicherungen aus dem Beitrag
  // (keine Karte, gekappte Enden) gelten dort NICHT und duerfen deshalb
  // nicht behauptet werden.
  Future<void> _shareRouteExternally(SavedRoute route) async {
    final weiter = await zeigeRouteTeilenHinweis(
      context,
      ziel: RouteTeilenZiel.bild,
    );
    if (!weiter || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteSharePage(
          data: RouteShareData(
            title: route.name?.trim().isNotEmpty == true
                ? route.name!.trim()
                : '${route.displayStyleLabel} Route',
            subtitle: route.displayStyleLabel,
            segments: RouteShareData.segmentsFromGeometry(route.geometry),
            distanceLabel: route.formattedDistance,
            durationLabel: route.formattedDuration,
            styleLabel: route.displayStyleLabel,
          ),
        ),
      ),
    );
  }
}

class _SavedRouteCard extends StatelessWidget {
  const _SavedRouteCard({
    required this.route,
    required this.isOwnRoute,
    required this.onOpen,
  });

  final SavedRoute route;
  final bool isOwnRoute;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      onLongPress: onOpen,
      child: Container(
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isOwnRoute)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD166).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Eigene',
                      style: TextStyle(
                        color: Color(0xFFFFD166),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                const Icon(Icons.chevron_right, color: Colors.grey, size: 24),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
