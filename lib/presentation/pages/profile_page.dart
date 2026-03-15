import 'package:cruise_connect/presentation/pages/interactive_post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/pages/welcome_page.dart';
import 'package:cruise_connect/presentation/pages/create_post_page.dart';
import 'package:cruise_connect/presentation/pages/edit_profile_page.dart';
import 'package:cruise_connect/presentation/pages/settings_page.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _loading = true;
  int _followerCount = 0;
  int _followingCount = 0;
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _groups = [];
  List<SavedRoute> _savedRoutes = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final results = await Future.wait([
        SocialService.getFollowerCount(uid),
        SocialService.getFollowingCount(uid),
        SocialService.getUserPosts(uid),
        SocialService.getMyGroups(),
        SavedRoutesService.getUserRoutes(),
      ]);

      if (mounted) {
        setState(() {
          _followerCount = results[0] as int;
          _followingCount = results[1] as int;
          _posts = results[2] as List<Map<String, dynamic>>;
          _groups = results[3] as List<Map<String, dynamic>>;
          _savedRoutes = results[4] as List<SavedRoute>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void signUserOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
        (route) => false,
      );
    }
  }

  String _formatTimeAgo(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes} Min.';
    if (diff.inHours < 24) return '${diff.inHours} Std.';
    if (diff.inDays < 30) return '${diff.inDays} Tage';
    return '${(diff.inDays / 30).floor()} Mon.';
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final String userEmail = user?.email ?? "user@cruiseconnect.com";
    final String userName = (user?.userMetadata?['username'] as String?) ?? userEmail.split('@')[0];
    final String userHandle = "@${userEmail.split('@')[0]}";

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0B0E14),
      endDrawer: _buildBurgerMenu(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFF3B30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePostPage()));
          _loadData();
        },
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              systemOverlayStyle: const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
              ),
              stretch: true,
              expandedHeight: 150,
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              flexibleSpace: FlexibleSpaceBar(
                background: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Colors.transparent],
                      stops: [0.6, 1.0],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF1C1F26), Color(0xFF0B0E14)],
                        stops: [0.3, 1.0],
                      ),
                    ),
                    child: Center(
                      child: Icon(Icons.camera_alt_outlined, size: 80, color: Colors.white.withValues(alpha: 0.05)),
                    ),
                  ),
                ),
              ),
              actions: [
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white),
                    onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  ),
                ),
              ],
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Transform.translate(
                          offset: const Offset(0, -40),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: const BoxDecoration(
                              color: Color(0xFF0B0E14),
                              shape: BoxShape.circle,
                            ),
                            child: CircleAvatar(
                              radius: 40,
                              backgroundColor: const Color(0xFFFF3B30),
                              child: Text(
                                userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfilePage())),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white30),
                              ),
                              child: const Text("Profil bearbeiten", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Transform.translate(
                      offset: const Offset(0, -30),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(userName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(userHandle, style: const TextStyle(color: Colors.grey, fontSize: 15)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _buildFollowStat('$_followingCount', "Folge ich"),
                              const SizedBox(width: 16),
                              _buildFollowStat('$_followerCount', "Follower"),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Tabs (scrollt mit)
            SliverToBoxAdapter(
              child: Container(
                color: const Color(0xFF0B0E14),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: const Color(0xFFFF3B30),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  tabs: const [
                    Tab(text: "Posts"),
                    Tab(text: "Routen"),
                    Tab(text: "Gruppen"),
                  ],
                ),
              ),
            ),
          ];
        },
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30)))
            : TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Posts
                  _posts.isEmpty
                      ? const Center(child: Text('Noch keine Posts', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 10, bottom: 80),
                          itemCount: _posts.length,
                          itemBuilder: (context, index) {
                            final post = _posts[index];
                            final profile = post['profiles'] as Map<String, dynamic>?;
                            return InteractivePostCard(
                              name: profile?['username'] ?? userName,
                              handle: userHandle,
                              time: _formatTimeAgo(post['created_at']),
                              content: post['content'] ?? '',
                              initialLikeCount: '${post['likes_count'] ?? 0}',
                              initialCommentCount: '${post['comments_count'] ?? 0}',
                              initialRepostCount: '${post['reposts_count'] ?? 0}',
                            );
                          },
                        ),

                  // Tab 2: Gespeicherte Routen
                  _savedRoutes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.route, color: Colors.grey[700], size: 48),
                              const SizedBox(height: 12),
                              const Text('Noch keine Routen gespeichert', style: TextStyle(color: Colors.grey)),
                              const SizedBox(height: 4),
                              const Text('Fahre los und bestätige deine erste Route!', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _savedRoutes.length,
                          itemBuilder: (context, index) {
                            final route = _savedRoutes[index];
                            return _buildRouteCard(route);
                          },
                        ),

                  // Tab 3: Gruppen
                  _groups.isEmpty
                      ? const Center(child: Text('Noch keiner Gruppe beigetreten', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _groups.length,
                          itemBuilder: (context, index) {
                            final group = _groups[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _buildGroupCard(
                                group['name'] ?? 'Gruppe',
                                group['route_name'] ?? '',
                                group['stats'] ?? '',
                                (group['group_members'] as List?)?.length ?? 0,
                                group['time_location'] ?? '',
                                true,
                              ),
                            );
                          },
                        ),
                ],
              ),
      ),
    );
  }

  Widget _buildRouteCard(SavedRoute route) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
            child: Center(child: Text(route.styleEmoji, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(route.name ?? route.style, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  '${route.formattedDistance} · ${route.formattedDuration}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          // Play Button
          if (route.geometry != null)
            IconButton(
              icon: const Icon(Icons.play_circle_fill, color: Color(0xFFFF3B30), size: 32),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => CruiseModePage(initialRoute: route)));
              },
            ),
          // Delete
          IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.grey[600], size: 20),
            onPressed: () async {
              await SavedRoutesService.deleteRoute(route.id);
              _loadData();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBurgerMenu() {
    return Drawer(
      backgroundColor: const Color(0xFF1C1F26),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text("Menü", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
            _buildMenuItem(Icons.settings, "Einstellungen",
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))),
            _buildMenuItem(Icons.bookmark, "Gespeicherte Routen", onTap: () {
              _tabController.animateTo(1);
            }),
            _buildMenuItem(Icons.help_outline, "Hilfe & Support"),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: signUserOut,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B30).withValues(alpha: 0.1),
                    foregroundColor: const Color(0xFFFF3B30),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFFFF3B30)),
                    ),
                  ),
                  child: const Text("Ausloggen", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, {VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
      onTap: () {
        Navigator.pop(context);
        onTap?.call();
      },
    );
  }

  Widget _buildFollowStat(String count, String label) {
    return Row(
      children: [
        Text(count, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 15)),
      ],
    );
  }

  Widget _buildGroupCard(String title, String routeName, String stats, int drivers, String timeLoc, bool isJoined) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: isJoined ? Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                if (isJoined)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text("Dabei", style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            if (routeName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.terrain, color: Colors.white70, size: 14),
                const SizedBox(width: 6),
                Text(routeName, style: const TextStyle(color: Colors.white, fontSize: 14)),
              ]),
            ],
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(stats, style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.local_fire_department, color: Colors.orange, size: 14),
              const SizedBox(width: 6),
              Text("$drivers Fahrer", style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ],
        ),
      ),
    );
  }
}
