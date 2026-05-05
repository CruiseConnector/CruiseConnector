import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/pages/welcome_page.dart';
import 'package:cruise_connect/presentation/pages/create_post_page.dart';
import 'package:cruise_connect/presentation/pages/edit_profile_page.dart';
import 'package:cruise_connect/presentation/pages/settings_page.dart';
import 'package:cruise_connect/presentation/pages/follow_requests_page.dart';
import 'package:cruise_connect/presentation/pages/blocked_users_page.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';
import 'package:cruise_connect/presentation/pages/liked_posts_page.dart';
import 'package:cruise_connect/presentation/pages/post_detail_page.dart';
import 'package:cruise_connect/presentation/pages/saved_route_bookmarks_page.dart';
import 'package:cruise_connect/presentation/pages/user_profile_page.dart';
import 'package:cruise_connect/presentation/widgets/mentions.dart';
import 'package:cruise_connect/presentation/widgets/accent_color_picker.dart';
import 'package:cruise_connect/presentation/widgets/route_chip.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';
import 'package:cruise_connect/presentation/widgets/vehicle_garage_carousel.dart';
import 'package:cruise_connect/presentation/pages/group_lobby_page.dart';

class ProfilePage extends StatefulWidget {
  final int refreshKey;
  const ProfilePage({super.key, this.refreshKey = 0});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  @override
  void didUpdateWidget(ProfilePage old) {
    super.didUpdateWidget(old);
    if (widget.refreshKey != old.refreshKey && widget.refreshKey > 0) {
      _loadData();
    }
  }

  late TabController _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _loading = true;
  int _followerCount = 0;
  int _followingCount = 0;
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _reposts = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _vehicles = [];
  List<SavedRoute> _savedRoutes = [];
  String? _avatarUrl;
  String? _bannerUrl;

  /// Komplettes Profil-Map — wird an `CarCard` durchgereicht.
  Map<String, dynamic> _profile = {};
  bool _uploadingAvatar = false;
  final Set<String> _expandedGroupNames = {};

  /// UI-State: Bio + CarCard sind standardmäßig kompakt; lange Bio wird
  /// erst bei "mehr" voll ausgeklappt, CarCard erst bei Tap.
  bool _bioExpanded = false;
  bool _carCardExpanded = false;
  static const int _bioCollapseAt = 20;

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
        SocialService.getMyAllGroups(),
        SavedRoutesService.getUserRoutes(),
        SocialService.getUserProfile(uid),
        SocialService.getUserVehicles(uid),
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
          _profile = profile ?? <String, dynamic>{};
          _vehicles = results[7] as List<Map<String, dynamic>>;
          _avatarUrl = profile?['avatar_url'] as String?;
          _bannerUrl = profile?['banner_url'] as String?;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Profile] Daten laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Fragt den User in einem BottomSheet, ob er Kamera oder Galerie nutzen
  /// will. Gibt null zurück, wenn der Sheet abgebrochen wurde.
  Future<ImageSource?> _chooseImageSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1C1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Profilbild ändern',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.photo_camera,
                  color: AppAccentColors.accent,
                ),
                title: const Text(
                  'Kamera',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(
                  Icons.photo_library,
                  color: AppAccentColors.accent,
                ),
                title: const Text(
                  'Galerie',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadAvatar() async {
    final source = await _chooseImageSource();
    if (source == null) return;

    final picker = ImagePicker();
    final XFile? image;
    try {
      image = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
    } catch (e) {
      // Häufigster Fall: User hat Kamera-/Galerie-Berechtigung verweigert.
      debugPrint('[Profile] Bild-Auswahl fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              source == ImageSource.camera
                  ? 'Kein Kamera-Zugriff. Berechtigung in den Einstellungen erlauben.'
                  : 'Kein Galerie-Zugriff. Berechtigung in den Einstellungen erlauben.',
            ),
            backgroundColor: const Color(0xFF1C1F26),
          ),
        );
      }
      return;
    }
    if (image == null) return;

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _uploadingAvatar = true);

    try {
      final bytes = await image.readAsBytes();
      final rawExt = image.path.split('.').last.toLowerCase();
      final ext = RegExp(r'^[a-z0-9]{2,5}$').hasMatch(rawExt) ? rawExt : 'jpg';
      final contentType = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
      final urlWithCacheBuster = await SocialService.uploadUserAsset(
        bucket: 'avatars',
        bytes: bytes,
        fileName: 'avatar.$ext',
        contentType: contentType,
      );
      if (urlWithCacheBuster == null) {
        throw Exception('Upload fehlgeschlagen');
      }

      await SocialService.updateProfileImageUrl(
        column: 'avatar_url',
        publicUrl: urlWithCacheBuster,
      );

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

  Future<void> _openExternalLink(String rawLink) async {
    final normalized = rawLink.startsWith(RegExp(r'https?://'))
        ? rawLink
        : 'https://$rawLink';
    final uri = Uri.tryParse(normalized);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<AppAccentProvider>().color;
    final user = Supabase.instance.client.auth.currentUser;
    // Username & Bio kommen jetzt aus dem `profiles`-Table — Edits aus
    // EditProfilePage werden so direkt sichtbar. user.userMetadata ist
    // unzuverlässig, weil sie nicht synchron zum profiles-Update ist.
    final dbUsername = (_profile['username'] as String?)?.trim();
    final String userName = (dbUsername != null && dbUsername.isNotEmpty)
        ? dbUsername
        : 'Cruiser';
    final String userHandle = SocialService.publicHandle(
      _profile,
      fallbackUserId: user?.id,
    );
    final String? userBio = (_profile['bio'] as String?)?.trim();
    final String? userBioTitle = (_profile['bio_title'] as String?)?.trim();
    final String? userLink = (_profile['link'] as String?)?.trim();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0B0E14),
      endDrawer: _buildBurgerMenu(),
      floatingActionButton: FloatingActionButton(
        heroTag: 'profile_fab',
        backgroundColor: accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreatePostPage()),
          );
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
              expandedHeight: 190,
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
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF1C1F26), Color(0xFF0B0E14)],
                        stops: [0.3, 1.0],
                      ),
                      image: _bannerUrl != null && _bannerUrl!.isNotEmpty
                          ? DecorationImage(
                              image: UserAvatar.resizedNetworkImageProvider(
                                context,
                                _bannerUrl,
                                width: MediaQuery.sizeOf(context).width,
                                height: 220,
                                maxCacheSize: 1600,
                              )!,
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _bannerUrl != null && _bannerUrl!.isNotEmpty
                        ? null
                        : Center(
                            child: Icon(
                              Icons.camera_alt_outlined,
                              size: 80,
                              color: Colors.white.withValues(alpha: 0.05),
                            ),
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
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          GestureDetector(
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
                                    backgroundColor: accent,
                                    foregroundImage:
                                        UserAvatar.avatarImageProvider(
                                          context,
                                          _avatarUrl,
                                          radius: 40,
                                        ),
                                    child: Text(
                                      userName.isNotEmpty
                                          ? userName[0].toUpperCase()
                                          : 'U',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (_uploadingAvatar)
                                    const Positioned.fill(
                                      child: CircleAvatar(
                                        radius: 40,
                                        backgroundColor: Colors.black54,
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
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
                                        color: accent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFF0B0E14),
                                          width: 2,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: GestureDetector(
                              onTap: () async {
                                final changed = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const EditProfilePage(),
                                  ),
                                );
                                // EditProfilePage liefert `true` zurück, wenn
                                // Speichern erfolgreich war — dann frische Daten
                                // ziehen, damit Banner/Avatar/Auto-Karte aktuell sind.
                                if (changed == true) _loadData();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white30),
                                ),
                                child: const Text(
                                  'Profil bearbeiten',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          userHandle,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 15,
                          ),
                        ),
                        if (userBio != null && userBio.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          if (userBioTitle != null &&
                              userBioTitle.isNotEmpty) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                userBioTitle,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          _buildBio(userBio),
                        ],
                        if (userLink != null && userLink.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () => _openExternalLink(userLink),
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.link, size: 14, color: accent),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    userLink,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: accent,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => _showFollowList('following'),
                              child: _buildFollowStat(
                                '$_followingCount',
                                'Folge ich',
                              ),
                            ),
                            const SizedBox(width: 16),
                            GestureDetector(
                              onTap: () => _showFollowList('followers'),
                              child: _buildFollowStat(
                                '$_followerCount',
                                'Follower',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Garage — mehrere Autos/Motorräder, horizontal swipebar.
            if (_vehicles.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: _buildCarSection(),
                ),
              ),

            // Tabs (scrollt mit)
            SliverToBoxAdapter(
              child: Container(
                color: const Color(0xFF0B0E14),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: false,
                  labelPadding: EdgeInsets.zero,
                  indicator: UnderlineTabIndicator(
                    borderSide: BorderSide(color: accent, width: 2.5),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: const Color(0xFF3A3A45),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
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
            ? Center(child: CircularProgressIndicator(color: accent))
            : TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Posts (mit Lösch-Option)
                  _posts.isEmpty
                      ? const Center(
                          child: Text(
                            'Noch keine Posts',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 10, bottom: 80),
                          itemCount: _posts.length,
                          itemBuilder: (context, index) {
                            final post = _posts[index];
                            final profile =
                                post['profiles'] as Map<String, dynamic>?;
                            return _buildOwnPostCard(
                              postId: post['id'],
                              name: profile?['username'] ?? userName,
                              handle: userHandle,
                              time: _formatTimeAgo(post['created_at']),
                              content: post['content'] ?? '',
                              likesCount: post['likes_count'] ?? 0,
                              commentsCount: post['comments_count'] ?? 0,
                              repostsCount: post['reposts_count'] ?? 0,
                              sharedRouteId: post['shared_route_id'] as String?,
                            );
                          },
                        ),

                  // Tab 2: Reposts
                  _reposts.isEmpty
                      ? const Center(
                          child: Text(
                            'Noch keine Reposts',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 10, bottom: 80),
                          itemCount: _reposts.length,
                          itemBuilder: (context, index) {
                            final repost = _reposts[index];
                            final post =
                                repost['posts'] as Map<String, dynamic>?;
                            if (post == null) return const SizedBox.shrink();
                            final author =
                                post['profiles'] as Map<String, dynamic>?;
                            final authorName = SocialService.publicDisplayName(
                              author,
                              fallbackUserId: post['user_id'] as String?,
                            );
                            final authorId = author?['id'] as String?;
                            final originalPostId = post['id'] as String?;
                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: originalPostId == null
                                  ? null
                                  : () => _openPostDetail(post),
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
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
                                        const Icon(
                                          Icons.repeat,
                                          size: 14,
                                          color: Color(0xFF34C759),
                                        ),
                                        const SizedBox(width: 6),
                                        GestureDetector(
                                          onTap: authorId == null
                                              ? null
                                              : () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        UserProfilePage(
                                                          userId: authorId,
                                                          initialUsername:
                                                              authorName,
                                                        ),
                                                  ),
                                                ),
                                          child: Text(
                                            'Repost von @$authorName',
                                            style: const TextStyle(
                                              color: Color(0xFF34C759),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          _formatTimeAgo(repost['created_at']),
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 11,
                                          ),
                                        ),
                                        if (originalPostId != null)
                                          PopupMenuButton<String>(
                                            icon: const Icon(
                                              Icons.more_horiz,
                                              color: Colors.grey,
                                              size: 18,
                                            ),
                                            color: const Color(0xFF1C1F26),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onSelected: (value) async {
                                              if (value == 'unrepost') {
                                                await SocialService.toggleRepost(
                                                  originalPostId,
                                                );
                                                _loadData();
                                              }
                                            },
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(
                                                value: 'unrepost',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.repeat,
                                                      color: Color(0xFF34C759),
                                                      size: 18,
                                                    ),
                                                    SizedBox(width: 8),
                                                    Text(
                                                      'Repost entfernen',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text.rich(
                                      TextSpan(
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          height: 1.3,
                                        ),
                                        children: buildMentionSpans(
                                          context: context,
                                          text: (post['content'] ?? '')
                                              .toString(),
                                          baseStyle: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (post['shared_route_id'] != null) ...[
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: RouteChip(
                                          routeId:
                                              post['shared_route_id'] as String,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
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
                              Icon(
                                Icons.route,
                                color: Colors.grey[700],
                                size: 48,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Noch keine Routen gespeichert',
                                style: TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Fahre los und bestätige deine erste Route!',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
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
                      ? const Center(
                          child: Text(
                            'Noch keiner Gruppe beigetreten',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _groups.length,
                          itemBuilder: (context, index) {
                            final group = _groups[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _buildProfileGroupCard(group),
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
    String? sharedRouteId,
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
              UserAvatar(name: name, avatarUrl: _avatarUrl, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          handle,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '· $time',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_horiz,
                  color: Colors.grey,
                  size: 20,
                ),
                color: const Color(0xFF1C1F26),
                onSelected: (value) {
                  if (value == 'delete') _deletePost(postId);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          color: AppAccentColors.accent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Post löschen',
                          style: TextStyle(color: AppAccentColors.accent),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (ctx) {
              const baseStyle = TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.4,
              );
              return Text.rich(
                TextSpan(
                  style: baseStyle,
                  children: buildMentionSpans(
                    context: ctx,
                    text: content,
                    baseStyle: baseStyle,
                  ),
                ),
              );
            },
          ),
          if (sharedRouteId != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: RouteChip(routeId: sharedRouteId),
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _openPostDetailByValues(
                postId: postId,
                name: name,
                handle: handle,
                content: content,
                time: time,
                sharedRouteId: sharedRouteId,
                avatarUrl: _avatarUrl,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline,
                      color: Colors.grey,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      commentsCount > 0
                          ? '$commentsCount Kommentare'
                          : 'Kommentieren',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
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
        title: const Text(
          'Post löschen?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Dieser Post wird unwiderruflich gelöscht.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Abbrechen',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Löschen',
              style: TextStyle(color: AppAccentColors.accent),
            ),
          ),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[600],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      Expanded(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppAccentColors.accent,
                          ),
                        ),
                      )
                    else if (!snapshot.hasData || snapshot.data!.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            type == 'followers'
                                ? 'Noch keine Follower'
                                : 'Du folgst noch niemandem',
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
                            final profileKey = type == 'followers'
                                ? 'profiles'
                                : 'profiles';
                            final profile =
                                item[profileKey] as Map<String, dynamic>?;
                            final username = SocialService.publicDisplayName(
                              profile,
                              fallbackUserId: profile?['id'] as String?,
                            );
                            final handle = SocialService.publicHandle(
                              profile,
                              fallbackUserId: profile?['id'] as String?,
                            );
                            final userId = profile?['id'] as String?;

                            return ListTile(
                              onTap: () {
                                Navigator.pop(sheetContext);
                                if (userId != null) {
                                  Future.delayed(
                                    const Duration(milliseconds: 150),
                                    () {
                                      if (!context.mounted) return;
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              UserProfilePage(userId: userId),
                                        ),
                                      );
                                    },
                                  );
                                }
                              },
                              leading: UserAvatar.fromProfile(
                                profile,
                                fallbackName: username,
                                radius: 20,
                              ),
                              title: Text(
                                username,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                handle,
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                              trailing: type == 'followers' && userId != null
                                  ? PopupMenuButton<String>(
                                      icon: const Icon(
                                        Icons.more_vert,
                                        color: Colors.grey,
                                      ),
                                      color: const Color(0xFF1C1F26),
                                      onSelected: (value) async {
                                        final provider = this.context
                                            .read<CommunityProvider>();
                                        Navigator.pop(sheetContext);
                                        if (value == 'remove') {
                                          await SocialService.removeFollower(
                                            userId,
                                          );
                                          if (mounted) _loadData();
                                          return;
                                        }
                                        if (value == 'block') {
                                          await provider.blockUser(userId);
                                          if (mounted) _loadData();
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'remove',
                                          child: Text(
                                            'Follower entfernen',
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'block',
                                          child: Text(
                                            'Blockieren',
                                            style: TextStyle(
                                              color: AppAccentColors.accent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : null,
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

  void _openPostDetail(Map<String, dynamic> post) {
    final profile = post['profiles'] as Map<String, dynamic>?;
    _openPostDetailByValues(
      postId: post['id'] as String,
      name: SocialService.publicDisplayName(
        profile,
        fallbackUserId: post['user_id'] as String?,
      ),
      handle: SocialService.publicHandle(
        profile,
        fallbackUserId: post['user_id'] as String?,
      ),
      content: (post['content'] ?? '').toString(),
      time: _formatTimeAgo(post['created_at']),
      sharedRouteId: post['shared_route_id'] as String?,
      avatarUrl: profile?['avatar_url'] as String?,
    );
  }

  void _openPostDetailByValues({
    required String postId,
    required String name,
    required String handle,
    required String content,
    required String time,
    String? sharedRouteId,
    String? avatarUrl,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailPage(
          postId: postId,
          name: name,
          handle: handle,
          content: content,
          time: time,
          sharedRouteId: sharedRouteId,
          avatarUrl: avatarUrl,
        ),
      ),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
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
                Text(
                  route.name ?? route.style,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${route.formattedDistance} · ${route.formattedDuration}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 20),
                _buildOptionTile(
                  Icons.play_circle_fill,
                  'Nochmal fahren',
                  AppAccentColors.accent,
                  () {
                    Navigator.pop(ctx);
                    CruiseModePage.pendingRoute.value = route;
                  },
                ),
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
                  Icons.delete_outline,
                  'Route löschen',
                  Colors.grey,
                  () async {
                    Navigator.pop(ctx);
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        backgroundColor: const Color(0xFF1C1F26),
                        title: const Text(
                          'Route löschen?',
                          style: TextStyle(color: Colors.white),
                        ),
                        content: const Text(
                          'Diese Route wird unwiderruflich gelöscht.',
                          style: TextStyle(color: Colors.grey),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text(
                              'Abbrechen',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: Text(
                              'Löschen',
                              style: TextStyle(color: AppAccentColors.accent),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await SavedRoutesService.deleteRoute(route.id);
                      _loadData();
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
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
            maxLength: 60,
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
    await _loadData();
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

  void _shareRouteAsPost(SavedRoute route) {
    final routeText =
        '${route.styleEmoji} ${route.name ?? route.style}\n'
        '${route.formattedDistance} · ${route.formattedDuration}\n\n';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CreatePostPage(initialText: routeText, sharedRouteId: route.id),
      ),
    ).then((_) => _loadData());
  }

  Widget _buildBurgerMenu() {
    final accent = context.watch<AppAccentProvider>().color;

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
                child: Text(
                  'Menü',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildMenuItem(
              Icons.settings,
              'Einstellungen',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
            ),
            _buildMenuItem(
              Icons.palette_outlined,
              'Akzentfarbe',
              onTap: () {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) showAccentColorPicker(context);
                });
              },
            ),
            _buildMenuItem(
              Icons.person_add_alt_1,
              'Freundschaftsanfragen',
              onTap: () {
                // Drawer explizit über den ScaffoldKey schließen — sonst
                // kann Navigator.pop versehentlich die Profile-Page poppen,
                // und der Back-Button auf der nächsten Page findet keinen
                // gültigen Stack mehr.
                _scaffoldKey.currentState?.closeEndDrawer();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FollowRequestsPage()),
                );
              },
            ),
            _buildMenuItem(
              Icons.block,
              'Blockierte Nutzer',
              onTap: () {
                _scaffoldKey.currentState?.closeEndDrawer();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BlockedUsersPage()),
                );
              },
            ),
            _buildMenuItem(
              Icons.bookmark,
              'Gespeicherte Routen',
              onTap: () {
                _scaffoldKey.currentState?.closeEndDrawer();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SavedRouteBookmarksPage(),
                  ),
                );
              },
            ),
            _buildMenuItem(
              Icons.favorite_border,
              'Gefällt mir',
              onTap: () {
                _scaffoldKey.currentState?.closeEndDrawer();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LikedPostsPage()),
                ).then((_) => _loadData());
              },
            ),
            _buildMenuItem(Icons.help_outline, 'Hilfe & Support'),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: signUserOut,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent.withValues(alpha: 0.1),
                    foregroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: accent),
                    ),
                  ),
                  child: const Text(
                    'Ausloggen',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
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
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      onTap: () {
        Navigator.pop(context);
        onTap?.call();
      },
    );
  }

  Widget _buildFollowStat(String count, String label) {
    return Row(
      children: [
        Text(
          count,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 15)),
      ],
    );
  }

  /// Bio: bei mehr als [_bioCollapseAt] Zeichen wird sie standardmäßig
  /// abgeschnitten und über "mehr" / "weniger" auf-/zugeklappt.
  Widget _buildBio(String bio) {
    const baseStyle = TextStyle(color: Colors.white, fontSize: 14, height: 1.4);
    if (bio.length <= _bioCollapseAt) {
      return Text(bio, style: baseStyle);
    }
    final collapsed = '${bio.substring(0, _bioCollapseAt).trimRight()}…';
    return GestureDetector(
      onTap: () => setState(() => _bioExpanded = !_bioExpanded),
      behavior: HitTestBehavior.opaque,
      child: Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: _bioExpanded ? bio : collapsed),
            TextSpan(
              text: _bioExpanded ? '  weniger' : '  mehr',
              style: TextStyle(
                color: AppAccentColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarSection() {
    final firstVehicle = _vehicles.isNotEmpty ? _vehicles.first : _profile;
    final brand =
        ((firstVehicle['brand'] ?? firstVehicle['car_brand']) as String?)
            ?.trim();
    final model =
        ((firstVehicle['model'] ?? firstVehicle['car_name']) as String?)
            ?.trim();
    final summary = [
      if (brand != null && brand.isNotEmpty) brand,
      if (model != null && model.isNotEmpty) model,
    ].join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _carCardExpanded = !_carCardExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.garage_rounded,
                  color: AppAccentColors.accent,
                  size: 18,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Meine Garage',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                  ),
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '· $summary',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                ],
                const Spacer(),
                Icon(
                  _carCardExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.white70,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: _carCardExpanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: VehicleGarageCarousel(
                    vehicles: _vehicles,
                    onAddVehicle: () async {
                      final changed = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EditProfilePage(),
                        ),
                      );
                      if (changed == true) _loadData();
                    },
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _buildProfileGroupCard(Map<String, dynamic> group) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final groupId = group['id'] as String;
    final title = (group['name'] as String?) ?? 'Gruppe';
    final isPublic = group['is_public'] == true;
    final isOwner = group['created_by'] == uid;
    final isActive = group['is_active'] == true;
    final members = (group['group_members'] as List?) ?? [];
    final count = members.length;
    final startTime = DateTime.tryParse(group['start_time'] as String? ?? '');
    final nameExpanded = _expandedGroupNames.contains(groupId);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GroupLobbyPage(groupId: groupId)),
        ).then((_) => _loadData());
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isOwner
                ? AppAccentColors.accent.withValues(alpha: 0.5)
                : isActive
                ? AppAccentColors.accent.withValues(alpha: 0.75)
                : AppAccentColors.accent.withValues(alpha: 0.3),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        if (nameExpanded) {
                          _expandedGroupNames.remove(groupId);
                        } else {
                          _expandedGroupNames.add(groupId);
                        }
                      });
                    },
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: nameExpanded ? 3 : 1,
                        overflow: nameExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                _groupBadge(
                  isPublic ? 'Öffentlich' : 'Privat',
                  isPublic ? Colors.greenAccent : Colors.orangeAccent,
                ),
                const SizedBox(width: 6),
                if (isActive) ...[
                  _groupBadge('Live', AppAccentColors.accent),
                  const SizedBox(width: 6),
                ],
                if (isOwner) _groupBadge('Owner', AppAccentColors.accent),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                  color: const Color(0xFF1C1F26),
                  onSelected: (v) async {
                    if (v == 'leave') await _leaveOrDeleteGroup(group);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'leave',
                      // Ob am Ende gelöscht wird (letzter Owner) entscheidet
                      // der Confirm-Dialog anhand der tatsächlichen Owner-Anzahl.
                      child: Text(
                        'Gruppe verlassen',
                        style: TextStyle(color: AppAccentColors.accent),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (startTime != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.event, color: Colors.white70, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '${startTime.day.toString().padLeft(2, '0')}.${startTime.month.toString().padLeft(2, '0')}. '
                    '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.local_fire_department,
                  color: AppAccentColors.accent,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  '$count Fahrer',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _leaveOrDeleteGroup(Map<String, dynamic> group) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final groupId = group['id'] as String;

    // Owner-Rolle über group_members prüfen (mehrere Owner möglich,
    // da ein Owner die Rolle weitergeben kann).
    final iAmOwner = await SocialService.isOwner(groupId);
    final otherOwners = iAmOwner
        ? await SocialService.countOtherOwners(groupId, uid)
        : 0;
    // Gruppe nur löschen, wenn ich Owner bin UND es keinen weiteren Owner gibt.
    final willDelete = iAmOwner && otherOwners == 0;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _LeaveGroupDialog(
        willDelete: willDelete,
        iAmOwner: iAmOwner,
        onConfirm: () async {
          if (willDelete) {
            await SocialService.deleteGroup(groupId);
          } else {
            await SocialService.leaveGroup(groupId);
          }
        },
      ),
    );
    if (confirmed != true) return;

    if (mounted) await _loadData();
  }
}

/// Bestätigungsdialog für „Gruppe verlassen". Letzter Admin sieht eine
/// destruktive Variante mit Warntext + roter Lösch-Aktion und Inline-Spinner
/// während das Backend läuft.
class _LeaveGroupDialog extends StatefulWidget {
  final bool willDelete;
  final bool iAmOwner;
  final Future<void> Function() onConfirm;

  const _LeaveGroupDialog({
    required this.willDelete,
    required this.iAmOwner,
    required this.onConfirm,
  });

  @override
  State<_LeaveGroupDialog> createState() => _LeaveGroupDialogState();
}

class _LeaveGroupDialogState extends State<_LeaveGroupDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _handleConfirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Aktion fehlgeschlagen: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final destructive = widget.willDelete;
    final title = destructive ? 'Gruppe löschen?' : 'Gruppe verlassen?';
    final body = destructive
        ? 'Achtung: Du bist der einzige Admin. Wenn du die Gruppe verlässt, '
              'wird sie vollständig gelöscht. Ernenne vorher einen neuen Admin, '
              'wenn die Gruppe bestehen bleiben soll.'
        : widget.iAmOwner
        ? 'Es gibt weitere Owner – die Gruppe bleibt bestehen, du '
              'verlierst nur deine Mitgliedschaft.'
        : 'Du verlässt diese Gruppe. Beitritt später wieder möglich, '
              'solange sie öffentlich ist.';
    final confirmLabel = destructive ? 'Gruppe löschen' : 'Verlassen';

    return AlertDialog(
      backgroundColor: const Color(0xFF1C1F26),
      title: Row(
        children: [
          if (destructive)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.warning_amber_rounded,
                color: AppAccentColors.accent,
                size: 22,
              ),
            ),
          Expanded(
            child: Text(title, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(body, style: const TextStyle(color: Colors.white70)),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: AppAccentColors.accent, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Abbrechen', style: TextStyle(color: Colors.grey)),
        ),
        if (destructive)
          ElevatedButton(
            onPressed: _busy ? null : _handleConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppAccentColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    confirmLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
          )
        else
          TextButton(
            onPressed: _busy ? null : _handleConfirm,
            child: _busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: AppAccentColors.accent,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    confirmLabel,
                    style: TextStyle(color: AppAccentColors.accent),
                  ),
          ),
      ],
    );
  }
}
