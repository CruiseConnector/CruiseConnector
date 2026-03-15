import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/auth_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';
import 'package:cruise_connect/presentation/pages/welcome_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  List<SavedRoute> _routes = const [];
  bool _loadingRoutes = true;
  String? _username;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        SavedRoutesService.getUserRoutes(),
        AuthService.getUsername(),
      ]);
      if (!mounted) return;
      setState(() {
        _routes        = results[0] as List<SavedRoute>;
        _username      = results[1] as String?;
        _loadingRoutes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRoutes = false);
    }
  }

  Future<void> _deleteRoute(String id) async {
    await SavedRoutesService.deleteRoute(id);
    setState(() => _routes.removeWhere((r) => r.id == id));
  }

  Future<void> _signOut() async {
    await AuthService.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomePage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user  = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '–';
    final name  = _username ?? email.split('@').first;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Profilkarte ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F26),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 64, height: 64,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF3B30),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Aktiv', style: TextStyle(color: Color(0xFFFF3B30), fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Statistik ─────────────────────────────────────────────────
            _sectionTitle('Statistiken'),
            const SizedBox(height: 10),
            Row(
              children: [
                _statCard('${_routes.length}', 'Routen', Icons.route),
                const SizedBox(width: 12),
                _statCard(
                  _routes.isEmpty
                      ? '0 km'
                      : '${_routes.fold(0.0, (s, r) => s + r.distanceKm).toStringAsFixed(0)} km',
                  'Gesamt',
                  Icons.speed,
                ),
                const SizedBox(width: 12),
                _statCard(
                  _routes.isEmpty
                      ? '0'
                      : '${_routes.where((r) => r.isRoundTrip).length}',
                  'Rundkurse',
                  Icons.loop,
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── Gespeicherte Routen ───────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _sectionTitle('Gespeicherte Routen'),
                if (_loadingRoutes)
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF3B30)),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            if (!_loadingRoutes && _routes.isEmpty)
              _emptyRoutes()
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _routes.length,
                separatorBuilder: (context, i) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _routeCard(_routes[i]),
              ),

            const SizedBox(height: 28),

            // ── Menü ──────────────────────────────────────────────────────
            _sectionTitle('Konto'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F26),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                children: [
                  _menuItem(Icons.settings_outlined, 'Einstellungen', onTap: () {}),
                  _divider(),
                  _menuItem(Icons.help_outline, 'Hilfe & Support', onTap: () {}),
                  _divider(),
                  _menuItem(Icons.info_outline, 'Über CruiseConnect', onTap: () {}),
                  _divider(),
                  _menuItem(
                    Icons.logout,
                    'Abmelden',
                    color: const Color(0xFFFF3B30),
                    onTap: _signOut,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helper Widgets ─────────────────────────────────────────────────────────

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
  );

  Widget _statCard(String value, String label, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFFFF3B30), size: 22),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 11)),
        ],
      ),
    ),
  );

  Widget _routeCard(SavedRoute route) {
    return Dismissible(
      key: ValueKey(route.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade800,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _deleteRoute(route.id),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F26),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            // Style-Emoji
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF0B0E14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(route.styleEmoji, style: const TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route.name ?? route.style,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.straighten, size: 12, color: Color(0xFFA0AEC0)),
                      const SizedBox(width: 4),
                      Text(route.formattedDistance, style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 12)),
                      const SizedBox(width: 12),
                      const Icon(Icons.timer_outlined, size: 12, color: Color(0xFFA0AEC0)),
                      const SizedBox(width: 4),
                      Text(route.formattedDuration, style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 12)),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          route.isRoundTrip ? 'Rundkurs' : 'A → B',
                          style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Aktionen
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.play_circle_fill, color: Color(0xFFFF3B30), size: 28),
                  tooltip: 'Route starten',
                  onPressed: () => _startRoute(route),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(height: 8),
                IconButton(
                  icon: const Icon(Icons.share_outlined, color: Color(0xFFA0AEC0), size: 20),
                  tooltip: 'Route teilen',
                  onPressed: () => _shareRoute(route),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _startRoute(SavedRoute route) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: CruiseModePage(initialRoute: route),
        ),
      ),
    );
  }

  void _shareRoute(SavedRoute route) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ShareRouteAsPostPage(route: route),
      ),
    );
  }

  Widget _emptyRoutes() => Container(
    padding: const EdgeInsets.symmetric(vertical: 32),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFF1A1F26),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    ),
    child: Column(
      children: const [
        Icon(Icons.route, size: 40, color: Color(0xFF2D3748)),
        SizedBox(height: 12),
        Text('Noch keine Routen gespeichert', style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 14)),
        SizedBox(height: 4),
        Text('Fahre los und bestätige deine erste Route!', style: TextStyle(color: Color(0xFF4A5568), fontSize: 12)),
      ],
    ),
  );

  Widget _menuItem(IconData icon, String label, {required VoidCallback onTap, Color? color}) {
    final c = color ?? Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: c, size: 22),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: TextStyle(color: c, fontSize: 15))),
            Icon(Icons.chevron_right, color: c.withValues(alpha: 0.4), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: Colors.white.withValues(alpha: 0.06), indent: 52);

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }
}

// ═══════════════════════ SHARE ROUTE AS POST ════════════════════════════════

class _ShareRouteAsPostPage extends StatefulWidget {
  const _ShareRouteAsPostPage({required this.route});
  final SavedRoute route;

  @override
  State<_ShareRouteAsPostPage> createState() => _ShareRouteAsPostPageState();
}

class _ShareRouteAsPostPageState extends State<_ShareRouteAsPostPage> {
  final _textController = TextEditingController();
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    final r = widget.route;
    _textController.text =
        'Schaut euch meine Route an! ${r.styleEmoji}\n'
        '${r.formattedDistance} - ${r.formattedDuration}\n'
        '${r.isRoundTrip ? "Rundkurs" : "A \u2192 B"} im Stil "${r.style}"';
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (_textController.text.trim().isEmpty) return;
    setState(() => _posting = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final username = await AuthService.getUsername();

      await Supabase.instance.client.from('posts').insert({
        'user_id': userId,
        'username': username ?? 'Unbekannt',
        'content': _textController.text.trim(),
        'route_id': widget.route.id,
        'route_style': widget.route.style,
        'route_distance_km': widget.route.distanceKm,
        'route_name': widget.route.name ?? widget.route.style,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route geteilt!'), backgroundColor: Color(0xFF1A1F26)),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.route;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Route teilen', style: TextStyle(color: Colors.white)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
            child: ElevatedButton(
              onPressed: _posting ? null : _post,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF3B30),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: _posting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Posten', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Route Info Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F26),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFF3B30).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Text(r.styleEmoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name ?? r.style, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          '${r.formattedDistance} \u00b7 ${r.formattedDuration} \u00b7 ${r.isRoundTrip ? "Rundkurs" : "A \u2192 B"}',
                          style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Text Input
            Expanded(
              child: TextField(
                controller: _textController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                maxLines: null,
                decoration: const InputDecoration(
                  hintText: 'Beschreibe deine Route...',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
