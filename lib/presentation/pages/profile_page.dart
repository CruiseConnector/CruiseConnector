import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/pages/welcome_page.dart';
import 'package:cruise_connect/presentation/pages/create_post_page.dart';
import 'package:cruise_connect/presentation/pages/edit_profile_page.dart';
import 'package:cruise_connect/presentation/pages/settings_page.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';
import 'package:cruise_connect/presentation/pages/user_profile_page.dart';

class ProfilePage extends StatefulWidget {
  final int refreshKey;
  const ProfilePage({super.key, this.refreshKey = 0});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with SingleTickerProviderStateMixin {
  @override
  void didUpdateWidget(ProfilePage old) {
    super.didUpdateWidget(old);
    if (widget.refreshKey != old.refreshKey && widget.refreshKey > 0) _loadData();
  }

  late TabController _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _loading = true;
  int _followerCount = 0;
  int _followingCount = 0;
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _reposts = [];
  List<Map<String, dynamic>> _groups = [];
  List<SavedRoute> _savedRoutes = [];
  String? _avatarUrl;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
        SocialService.getUserReposts(uid),
        SocialService.getMyGroups(),
        SavedRoutesService.getUserRoutes(),
        SocialService.getUserProfile(uid),
      ]);

      if (mounted) {
        final profile = results[6] as Map<String, dynamic>?;
        setState(() {
          _followerCount = results[0] as int;
          _followingCount = results[1] as int;
          _posts = results[2] as List<Map<String, dynamic>>;
          _reposts = results[3] as List<Map<String, dynamic>>;
          _groups = results[4] as List<Map<String, dynamic>>;
          _savedRoutes = results[5] as List<SavedRoute>;
          _avatarUrl = profile?['avatar_url'] as String?;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Profile] Daten laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (image == null) return;

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _uploadingAvatar = true);

    try {
      final bytes = await image.readAsBytes();
      final ext = image.path.split('.').last.toLowerCase();
      final path = 'avatars/$uid.$ext';

      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));

      final publicUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(path);

      // URL mit Cache-Buster damit das neue Bild geladen wird
      final urlWithCacheBuster = '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';

      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': publicUrl})
          .eq('id', uid);

      if (mounted) {
        setState(() {
          _avatarUrl = urlWithCacheBuster;
          _uploadingAvatar = false;
        });
      }
    } catch (e) {
      debugPrint('[Profile] Avatar-Upload fehlgeschlagen: $e');
      if (mounted) {
        setState(() => _uploadingAvatar = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload fehlgeschlagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
    final String userEmail = user?.email ?? 'user@cruiseconnect.com';
    final String userName = (user?.userMetadata?['username'] as String?) ?? userEmail.split('@')[0];
    final String userHandle = "@${userEmail.split('@')[0]}";

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0B0E14),
      endDrawer: _buildBurgerMenu(),
      floatingActionButton: FloatingActionButton(
        heroTag: 'profile_fab',
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
                          child: GestureDetector(
                            onTap: _pickAndUploadAvatar,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: Color(0xFF0B0E14),
                                shape: BoxShape.circle,
                              ),
                              child: Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 40,
                                    backgroundColor: const Color(0xFFFF3B30),
                                    backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                                    child: _avatarUrl == null
                                        ? Text(
                                            userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                                            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                                          )
                                        : null,
                                  ),
                                  if (_uploadingAvatar)
                                    const Positioned.fill(
                                      child: CircleAvatar(
                                        radius: 40,
                                        backgroundColor: Colors.black54,
                                        child: SizedBox(
                                          width: 24, height: 24,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF3B30),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: const Color(0xFF0B0E14), width: 2),
                                      ),
                                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                                    ),
                                  ),
                                ],
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
                              child: const Text('Profil bearbeiten', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
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
                              GestureDetector(
                                onTap: () => _showFollowList('following'),
                                child: _buildFollowStat('$_followingCount', 'Folge ich'),
                              ),
                              const SizedBox(width: 16),
                              GestureDetector(
                                onTap: () => _showFollowList('followers'),
                                child: _buildFollowStat('$_followerCount', 'Follower'),
                              ),
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
                    Tab(text: 'Posts'),
                    Tab(text: 'Reposts'),
                    Tab(text: 'Routen'),
                    Tab(text: 'Gruppen'),
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
                  // Tab 1: Posts (mit Lösch-Option)
                  _posts.isEmpty
                      ? const Center(child: Text('Noch keine Posts', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 10, bottom: 80),
                          itemCount: _posts.length,
                          itemBuilder: (context, index) {
                            final post = _posts[index];
                            final profile = post['profiles'] as Map<String, dynamic>?;
                            return _buildOwnPostCard(
                              postId: post['id'],
                              name: profile?['username'] ?? userName,
                              handle: userHandle,
                              time: _formatTimeAgo(post['created_at']),
                              content: post['content'] ?? '',
                              likesCount: post['likes_count'] ?? 0,
                              commentsCount: post['comments_count'] ?? 0,
                              repostsCount: post['reposts_count'] ?? 0,
                            );
                          },
                        ),

                  // Tab 2: Reposts
                  _reposts.isEmpty
                      ? const Center(child: Text('Noch keine Reposts', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 10, bottom: 80),
                          itemCount: _reposts.length,
                          itemBuilder: (context, index) {
                            final repost = _reposts[index];
                            final post = repost['posts'] as Map<String, dynamic>?;
                            if (post == null) return const SizedBox.shrink();
                            final author = post['profiles'] as Map<String, dynamic>?;
                            final authorName = author?['username'] ?? 'User';
                            final originalPostId = post['id'] as String?;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1F26),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.repeat, size: 14, color: Color(0xFF34C759)),
                                      const SizedBox(width: 6),
                                      Text('Repost von @$authorName', style: const TextStyle(color: Color(0xFF34C759), fontSize: 12)),
                                      const Spacer(),
                                      Text(_formatTimeAgo(repost['created_at']), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                      if (originalPostId != null)
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_horiz, color: Colors.grey, size: 18),
                                          color: const Color(0xFF1C1F26),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onSelected: (value) async {
                                            if (value == 'unrepost') {
                                              await SocialService.toggleRepost(originalPostId);
                                              _loadData();
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            const PopupMenuItem(
                                              value: 'unrepost',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.repeat, color: Color(0xFF34C759), size: 18),
                                                  SizedBox(width: 8),
                                                  Text('Repost entfernen', style: TextStyle(color: Colors.white)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(post['content'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3)),
                                ],
                              ),
                            );
                          },
                        ),

                  // Tab 3: Gespeicherte Routen
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

  Widget _buildOwnPostCard({
    required String postId,
    required String name,
    required String handle,
    required String time,
    required String content,
    required int likesCount,
    required int commentsCount,
    required int repostsCount,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFFF3B30),
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    Row(
                      children: [
                        Text(handle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        const SizedBox(width: 5),
                        Text('· $time', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, color: Colors.grey, size: 20),
                color: const Color(0xFF1C1F26),
                onSelected: (value) {
                  if (value == 'delete') _deletePost(postId);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Color(0xFFFF3B30), size: 18),
                        SizedBox(width: 8),
                        Text('Post löschen', style: TextStyle(color: Color(0xFFFF3B30))),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(content, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Row(children: [
                const Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 18),
                if (commentsCount > 0) ...[const SizedBox(width: 4), Text('$commentsCount', style: const TextStyle(color: Colors.grey, fontSize: 12))],
              ]),
              Row(children: [
                const Icon(Icons.repeat, color: Colors.grey, size: 18),
                if (repostsCount > 0) ...[const SizedBox(width: 4), Text('$repostsCount', style: const TextStyle(color: Colors.grey, fontSize: 12))],
              ]),
              Row(children: [
                const Icon(Icons.favorite_border, color: Colors.grey, size: 18),
                if (likesCount > 0) ...[const SizedBox(width: 4), Text('$likesCount', style: const TextStyle(color: Colors.grey, fontSize: 12))],
              ]),
              const Icon(Icons.share_outlined, color: Colors.grey, size: 18),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deletePost(String postId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text('Post löschen?', style: TextStyle(color: Colors.white)),
        content: const Text('Dieser Post wird unwiderruflich gelöscht.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen', style: TextStyle(color: Color(0xFFFF3B30)))),
        ],
      ),
    );
    if (confirmed == true) {
      await SocialService.deletePost(postId);
      _loadData();
    }
  }

  void _showFollowList(String type) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0E14),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return FutureBuilder<List<Map<String, dynamic>>>(
              future: type == 'followers'
                  ? SocialService.getFollowers(uid)
                  : SocialService.getFollowingList(uid),
              builder: (context, snapshot) {
                final title = type == 'followers' ? 'Follower' : 'Folge ich';
                return Column(
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40, height: 4,
                        decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30))))
                    else if (!snapshot.hasData || snapshot.data!.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            type == 'followers' ? 'Noch keine Follower' : 'Du folgst noch niemandem',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: snapshot.data!.length,
                          itemBuilder: (context, index) {
                            final item = snapshot.data![index];
                            final profileKey = type == 'followers' ? 'profiles' : 'profiles';
                            final profile = item[profileKey] as Map<String, dynamic>?;
                            final username = profile?['username'] ?? profile?['email']?.split('@')[0] ?? 'User';
                            final userId = profile?['id'] as String?;

                            return ListTile(
                              onTap: () {
                                Navigator.pop(sheetContext);
                                if (userId != null) {
                                  Future.delayed(const Duration(milliseconds: 150), () {
                                    if (!context.mounted) return;
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfilePage(userId: userId)));
                                  });
                                }
                              },
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFFF3B30),
                                child: Text(username[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                              title: Text(username, style: const TextStyle(color: Colors.white)),
                              subtitle: Text('@${profile?['email']?.split('@')[0] ?? ''}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRouteCard(SavedRoute route) {
    return GestureDetector(
      onTap: () => _showRouteOptions(route),
      child: Container(
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
            const Icon(Icons.chevron_right, color: Colors.grey, size: 24),
          ],
        ),
      ),
    );
  }

  void _showRouteOptions(SavedRoute route) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1F26),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 16),
                Text(route.name ?? route.style, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 4),
                Text('${route.formattedDistance} · ${route.formattedDuration}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 20),
                _buildOptionTile(Icons.play_circle_fill, 'Nochmal fahren', const Color(0xFFFF3B30), () {
                  Navigator.pop(ctx);
                  CruiseModePage.pendingRoute.value = route;
                }),
                _buildOptionTile(Icons.share, 'Als Post teilen', const Color(0xFF00E5FF), () {
                  Navigator.pop(ctx);
                  _shareRouteAsPost(route);
                }),
                _buildOptionTile(Icons.delete_outline, 'Route löschen', Colors.grey, () async {
                  Navigator.pop(ctx);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      backgroundColor: const Color(0xFF1C1F26),
                      title: const Text('Route löschen?', style: TextStyle(color: Colors.white)),
                      content: const Text('Diese Route wird unwiderruflich gelöscht.', style: TextStyle(color: Colors.grey)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen', style: TextStyle(color: Colors.grey))),
                        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Löschen', style: TextStyle(color: Color(0xFFFF3B30)))),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await SavedRoutesService.deleteRoute(route.id);
                    _loadData();
                  }
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionTile(IconData icon, String label, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
      onTap: onTap,
    );
  }

  void _shareRouteAsPost(SavedRoute route) {
    final routeText = '${route.styleEmoji} ${route.name ?? route.style}\n'
        '${route.formattedDistance} · ${route.formattedDuration}\n\n';
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreatePostPage(initialText: routeText, sharedRouteId: route.id)),
    ).then((_) => _loadData());
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
                child: Text('Menü', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
            _buildMenuItem(Icons.settings, 'Einstellungen',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))),
            _buildMenuItem(Icons.bookmark, 'Gespeicherte Routen', onTap: () {
              _tabController.animateTo(2);
            }),
            _buildMenuItem(Icons.help_outline, 'Hilfe & Support'),
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
                  child: const Text('Ausloggen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                    child: const Text('Dabei', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
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
              Text('$drivers Fahrer', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ],
        ),
      ),
    );
  }
}
