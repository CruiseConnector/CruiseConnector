import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/post_detail_page.dart';
import 'package:cruise_connect/presentation/widgets/mentions.dart';
import 'package:cruise_connect/presentation/widgets/route_chip.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';
import 'package:cruise_connect/presentation/widgets/moderation_actions.dart';
import 'package:cruise_connect/presentation/widgets/vehicle_garage_carousel.dart';

/// Profil-Seite eines anderen Users (oder des eigenen).
///
/// Wird der Username schon vom Aufrufer bekannt (z.B. aus einem Mention-Tap
/// oder einem Repost-Header), kann er als [initialUsername] übergeben werden.
/// Die AppBar zeigt ihn dann sofort, statt den Default-Fallback "@user"
/// einzublenden, bis das Profil aus der DB geladen ist.
class UserProfilePage extends StatefulWidget {
  final String userId;
  final String? initialUsername;
  const UserProfilePage({
    super.key,
    required this.userId,
    this.initialUsername,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _reposts = [];
  List<Map<String, dynamic>> _vehicles = [];
  bool _isFollowing = false;
  bool _isOwnProfile = false;
  bool _isPrivate = false;
  bool _carCardExpanded = false;
  bool _bioExpanded = false;
  bool _blockedProfile = false;
  static const int _bioCollapseAt = 20;

  /// Status meiner Follow-Beziehung zu diesem Profil:
  /// `'accepted'` (folge), `'pending'` (Anfrage gesendet), `'none'`.
  String _followStatus = 'none';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _isOwnProfile =
        widget.userId == Supabase.instance.client.auth.currentUser?.id;
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (mounted) {
        setState(() {
          _loading = true;
          _blockedProfile = false;
        });
      }
      if (!_isOwnProfile &&
          await SocialService.isBlockedEither(widget.userId)) {
        if (!mounted) return;
        setState(() {
          _stats = {};
          _posts = [];
          _reposts = [];
          _vehicles = [];
          _followStatus = 'none';
          _isFollowing = false;
          _isPrivate = false;
          _blockedProfile = true;
          _loading = false;
        });
        return;
      }

      if (!_isOwnProfile) {
        final preview = await SocialService.getProfilePreview(widget.userId);
        final status = await SocialService.getFollowStatus(widget.userId);
        final private = preview?['is_private'] == true;
        if (private && status != 'accepted') {
          if (!mounted) return;
          setState(() {
            _stats = {
              'username': preview?['username'],
              'avatar_url': preview?['avatar_url'],
              'is_private': true,
            };
            _posts = [];
            _reposts = [];
            _vehicles = [];
            _followStatus = status;
            _isFollowing = false;
            _isPrivate = true;
            _loading = false;
          });
          return;
        }
      }

      final results = await Future.wait([
        SocialService.getProfileStats(widget.userId),
        SocialService.getUserPosts(widget.userId),
        SocialService.getUserReposts(widget.userId),
        SocialService.getUserVehicles(widget.userId),
        if (!_isOwnProfile) SocialService.getFollowStatus(widget.userId),
      ]);
      if (mounted) {
        setState(() {
          _stats = results[0] as Map<String, dynamic>;
          _isPrivate = _stats['is_private'] == true;
          _posts = results[1] as List<Map<String, dynamic>>;
          _reposts = results[2] as List<Map<String, dynamic>>;
          _vehicles = results[3] as List<Map<String, dynamic>>;
          if (!_isOwnProfile) {
            _followStatus = results[4] as String;
            _isFollowing = _followStatus == 'accepted';
          }
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[UserProfile] Daten laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
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

    // Stats > vom Aufrufer mitgegebener Username > leer.
    // Vermeidet "@user"-Default während des Loadings, wenn der Caller den
    // tatsächlichen Username schon kennt (z.B. aus einem Mention-Tap).
    final loadedName = _stats['username'] as String?;
    final displayName = loadedName ?? widget.initialUsername ?? '';
    final level = _stats['level'] ?? 1;
    final totalKm = (_stats['total_km'] as num?)?.toDouble() ?? 0;
    final totalRoutes = _stats['total_routes'] ?? 0;
    final followers = _stats['follower_count'] ?? 0;
    final following = _stats['following_count'] ?? 0;
    final headerName = displayName.isEmpty ? 'User' : displayName;
    final privateLocked = _isPrivate && !_isFollowing && !_isOwnProfile;
    final bannerUrl = (_stats['banner_url'] as String?)?.trim();
    final handle = SocialService.publicHandle(
      _stats,
      fallbackUserId: widget.userId,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          headerName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        elevation: 0,
        actions: [
          // 3-Punkte-Menü nur auf fremden Profilen — Melden + Blockieren.
          if (!_isOwnProfile)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              color: const Color(0xFF1C1F26),
              onSelected: (value) => _handleProfileMenu(value, displayName),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        color: AppAccentColors.accent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Benutzer melden',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(
                        Icons.block,
                        color: AppAccentColors.accent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Blockieren',
                        style: TextStyle(color: AppAccentColors.accent),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: accent))
          : _blockedProfile
          ? _buildBlockedProfileBody()
          : RefreshIndicator(
              onRefresh: _load,
              color: accent,
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  SliverToBoxAdapter(
                    child: _buildTwitterProfileHeader(
                      bannerUrl: privateLocked ? null : bannerUrl,
                      avatarUrl: _stats['avatar_url'] as String?,
                      name: headerName,
                      handle: handle,
                      level: level,
                      totalRoutes: totalRoutes,
                      totalKm: totalKm,
                      followers: followers,
                      following: following,
                      privateLocked: privateLocked,
                    ),
                  ),
                  if (!privateLocked)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _TabBarDelegate(
                        TabBar(
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
                            fontSize: 12.5,
                          ),
                          tabs: [
                            Tab(text: 'Posts (${_posts.length})'),
                            Tab(text: 'Reposts (${_reposts.length})'),
                          ],
                        ),
                      ),
                    ),
                ],
                body: privateLocked
                    ? _buildPrivateMessage()
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          // Posts Tab
                          (_isPrivate && !_isFollowing && !_isOwnProfile)
                              ? _buildPrivateMessage()
                              : _posts.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Noch keine Posts',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _posts.length,
                                  padding: EdgeInsets.zero,
                                  itemBuilder: (context, index) =>
                                      _buildPostItem(_posts[index]),
                                ),
                          // Reposts Tab
                          (_isPrivate && !_isFollowing && !_isOwnProfile)
                              ? _buildPrivateMessage()
                              : _reposts.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Noch keine Reposts',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _reposts.length,
                                  padding: EdgeInsets.zero,
                                  itemBuilder: (context, index) =>
                                      _buildRepostItem(_reposts[index]),
                                ),
                        ],
                      ),
              ),
            ),
    );
  }

  Widget _buildFollowButton({bool compact = false}) {
    final isAccepted = _followStatus == 'accepted';
    final isPending = _followStatus == 'pending';
    final label = isAccepted
        ? 'Folgst du'
        : isPending
        ? 'Angefragt'
        : 'Folgen';
    final displayLabel = label;
    final isFilled = !isAccepted && !isPending;
    return ElevatedButton(
      onPressed: () async {
        final previousStatus = _followStatus;
        final previousIsFollowing = _isFollowing;
        final previousFollowers = (_stats['follower_count'] as int?) ?? 0;
        final provider = context.read<CommunityProvider>();

        try {
          if (isAccepted || isPending) {
            // Unfollow oder Pending-Anfrage zurückziehen — beide löschen
            // den follows-Eintrag.
            setState(() {
              _followStatus = 'none';
              _isFollowing = false;
              if (isAccepted) {
                _stats['follower_count'] = previousFollowers - 1;
              }
            });
            await provider.unfollowUser(widget.userId);
          } else {
            setState(() {
              // Optimistisch: bei privatem Konto pending, sonst accepted.
              _followStatus = _isPrivate ? 'pending' : 'accepted';
              _isFollowing = !_isPrivate;
              if (!_isPrivate) {
                _stats['follower_count'] = previousFollowers + 1;
              }
            });
            final status = await provider.followUser(widget.userId);
            // Server hat Source-of-Truth — Status angleichen.
            if (mounted) {
              setState(() {
                _followStatus = status;
                _isFollowing = status == 'accepted';
                if (status != 'accepted') {
                  _stats['follower_count'] = previousFollowers;
                }
              });
              if (status == 'pending') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Anfrage gesendet'),
                    backgroundColor: Color(0xFF1C1F26),
                  ),
                );
              }
            }
          }
        } catch (e) {
          debugPrint('[UserProfile] Follow/Unfollow fehlgeschlagen: $e');
          if (mounted) {
            setState(() {
              _followStatus = previousStatus;
              _isFollowing = previousIsFollowing;
              _stats['follower_count'] = previousFollowers;
            });
          }
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isFilled ? Colors.white : Colors.transparent,
        side: isFilled ? null : const BorderSide(color: Colors.grey),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 999 : 12),
        ),
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
            : const EdgeInsets.symmetric(vertical: 12),
        minimumSize: compact ? const Size(0, 32) : null,
        tapTargetSize: compact
            ? MaterialTapTargetSize.shrinkWrap
            : MaterialTapTargetSize.padded,
        elevation: 0,
      ),
      child: Text(
        displayLabel,
        style: TextStyle(
          color: isFilled ? Colors.black : Colors.grey,
          fontWeight: FontWeight.bold,
          fontSize: compact ? 12 : 15,
        ),
      ),
    );
  }

  Widget _buildTwitterProfileHeader({
    required String? bannerUrl,
    required String? avatarUrl,
    required String name,
    required String handle,
    required int level,
    required int totalRoutes,
    required double totalKm,
    required int followers,
    required int following,
    required bool privateLocked,
  }) {
    final bio = (_stats['bio'] as String?)?.trim();
    final bioTitle = (_stats['bio_title'] as String?)?.trim();
    final link = (_stats['link'] as String?)?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            _buildProfileBanner(bannerUrl),
            Positioned(
              left: 16,
              bottom: -50,
              child: _buildProfileAvatar(name: name, avatarUrl: avatarUrl),
            ),
            if (!_isOwnProfile)
              Positioned(
                right: 16,
                bottom: -42,
                child: _buildFollowButton(compact: true),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 58, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                handle,
                style: const TextStyle(color: Colors.grey, fontSize: 15),
              ),
              const SizedBox(height: 10),
              Text(
                'Level $level',
                style: TextStyle(
                  color: AppAccentColors.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!privateLocked && bio != null && bio.isNotEmpty) ...[
                const SizedBox(height: 12),
                if (bioTitle != null && bioTitle.isNotEmpty) ...[
                  Text(
                    bioTitle,
                    style: TextStyle(
                      color: AppAccentColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                ],
                _buildBio(bio),
              ],
              if (!privateLocked && link != null && link.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildProfileLink(link),
              ],
              if (!privateLocked) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _buildInlineStat('$totalRoutes', 'Fahrten'),
                    _buildInlineStat(
                      '${totalKm.toStringAsFixed(0)} km',
                      'Gefahren',
                    ),
                    _buildInlineStat(
                      '$following',
                      'Folgt',
                      onTap: (_isFollowing || _isOwnProfile)
                          ? () => _showFollowList('following')
                          : null,
                    ),
                    _buildInlineStat(
                      '$followers',
                      'Follower',
                      onTap: (_isFollowing || _isOwnProfile)
                          ? () => _showFollowList('followers')
                          : null,
                    ),
                  ],
                ),
              ],
              if (!privateLocked && _vehicles.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildCarSection(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileBanner(String? bannerUrl) {
    return SizedBox(
      height: 178,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF242834), Color(0xFF10131B)],
          ),
          image: bannerUrl != null && bannerUrl.isNotEmpty
              ? DecorationImage(
                  image: NetworkImage(bannerUrl),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: bannerUrl != null && bannerUrl.isNotEmpty
            ? const SizedBox.shrink()
            : Center(
                child: Icon(
                  Icons.camera_alt_outlined,
                  size: 74,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
      ),
    );
  }

  Widget _buildProfileAvatar({
    required String name,
    required String? avatarUrl,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: Color(0xFF0B0E14),
        shape: BoxShape.circle,
      ),
      child: UserAvatar(name: name, avatarUrl: avatarUrl, radius: 50),
    );
  }

  Widget _buildProfileLink(String link) {
    return InkWell(
      onTap: () => _openExternalLink(link),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link, size: 14, color: AppAccentColors.accent),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              link,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppAccentColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineStat(String value, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: ' $label',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _buildCarSection() {
    final firstVehicle = _vehicles.isNotEmpty ? _vehicles.first : _stats;
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
                  'Garage',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
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
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: _carCardExpanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: VehicleGarageCarousel(vehicles: _vehicles),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _buildBio(String bio) {
    const baseStyle = TextStyle(color: Colors.white, fontSize: 14, height: 1.4);
    if (bio.length <= _bioCollapseAt) {
      return Text(bio, style: baseStyle);
    }
    final collapsed = '${bio.substring(0, _bioCollapseAt).trimRight()}...';
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

  Widget _buildPostItem(Map<String, dynamic> post) {
    final content = post['content'] ?? '';
    final time = _formatTimeAgo(post['created_at']);
    final likes = post['likes_count'] ?? 0;
    final comments = post['comments_count'] ?? 0;
    final reposts = post['reposts_count'] ?? 0;
    final profile = post['profiles'] as Map<String, dynamic>?;
    final authorName = SocialService.publicDisplayName(
      profile ?? _stats,
      fallbackUserId: post['user_id'] as String?,
    );
    final authorHandle = SocialService.publicHandle(
      profile ?? _stats,
      fallbackUserId: post['user_id'] as String?,
    );

    return InkWell(
      onTap: () => _openPostDetail(
        postId: post['id'] as String,
        name: authorName,
        handle: authorHandle,
        content: content.toString(),
        time: time,
        sharedRouteId: post['shared_route_id'] as String?,
        avatarUrl:
            profile?['avatar_url'] as String? ??
            _stats['avatar_url'] as String?,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.3,
                ),
                children: buildMentionSpans(
                  context: context,
                  text: content.toString(),
                  baseStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.3,
                  ),
                ),
              ),
            ),
            if (post['shared_route_id'] != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: RouteChip(routeId: post['shared_route_id'] as String),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.favorite_border,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 4),
                Text(
                  '$likes',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.comment_outlined,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 4),
                Text(
                  '$comments',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.repeat,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 4),
                Text(
                  '$reposts',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Text(
                  time,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.05)),
          ],
        ),
      ),
    );
  }

  Widget _buildRepostItem(Map<String, dynamic> repost) {
    final post = repost['posts'] as Map<String, dynamic>?;
    if (post == null) return const SizedBox.shrink();

    final content = post['content'] ?? '';
    final time = _formatTimeAgo(repost['created_at']);
    final author = post['profiles'] as Map<String, dynamic>?;
    final authorName = SocialService.publicDisplayName(
      author,
      fallbackUserId: post['user_id'] as String?,
    );
    final authorId = author?['id'] as String?;
    final authorHandle = SocialService.publicHandle(
      author,
      fallbackUserId: post['user_id'] as String?,
    );

    return InkWell(
      onTap: () => _openPostDetail(
        postId: post['id'] as String,
        name: authorName,
        handle: authorHandle,
        content: content.toString(),
        time: _formatTimeAgo(post['created_at']),
        sharedRouteId: post['shared_route_id'] as String?,
        avatarUrl: author?['avatar_url'] as String?,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.repeat, size: 14, color: Color(0xFF34C759)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: authorId == null
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserProfilePage(
                              userId: authorId,
                              initialUsername: authorName,
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
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.3,
                      ),
                      children: buildMentionSpans(
                        context: context,
                        text: content.toString(),
                        baseStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                  if (post['shared_route_id'] != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: RouteChip(
                        routeId: post['shared_route_id'] as String,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    time,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.05)),
          ],
        ),
      ),
    );
  }

  /// 3-Punkte-Menü im AppBar (nur bei fremden Profilen): Melden / Blockieren.
  /// Nach erfolgreichem Block geht's zurück zur vorherigen Seite, weil das
  /// Profil dann ohnehin verschwunden ist (Posts gefiltert, Follow weg).
  Future<void> _handleProfileMenu(String value, String displayName) async {
    final username = displayName.isEmpty ? 'User' : displayName.toLowerCase();
    if (value == 'report') {
      await ModerationActions.showReportSheet(
        context,
        userId: widget.userId,
        targetLabel: '@$username',
      );
      return;
    }
    if (value == 'block') {
      final blocked = await ModerationActions.confirmAndBlock(
        context,
        userId: widget.userId,
        username: username,
      );
      if (blocked && mounted) Navigator.pop(context);
    }
  }

  void _openPostDetail({
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

  Widget _buildPrivateMessage() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, color: Colors.grey, size: 48),
            SizedBox(height: 16),
            Text(
              'Dieses Konto ist privat',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Sende eine Anfrage und warte, bis sie angenommen wird, um Posts und Reposts zu sehen.',
              style: TextStyle(color: Colors.grey, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedProfileBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 42,
              backgroundColor: const Color(0xFF1C1F26),
              child: Icon(Icons.block, color: AppAccentColors.accent, size: 34),
            ),
            const SizedBox(height: 18),
            const Text(
              'Dieser Nutzer hat Sie blockiert',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Profilinhalte, Garage und Statistiken sind nicht sichtbar.',
              style: TextStyle(color: Colors.grey, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showFollowList(String type) {
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
                  ? SocialService.getFollowers(widget.userId)
                  : SocialService.getFollowingList(widget.userId),
              builder: (context, snapshot) {
                final title = type == 'followers' ? 'Follower' : 'Folgt';
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
                                : 'Folgt noch niemandem',
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
                            final profile =
                                item['profiles'] as Map<String, dynamic>?;
                            final username = SocialService.publicDisplayName(
                              profile,
                              fallbackUserId: profile?['id'] as String?,
                            );
                            final userId = profile?['id'] as String?;

                            return ListTile(
                              leading: UserAvatar.fromProfile(
                                profile,
                                fallbackName: username.toString(),
                                radius: 20,
                              ),
                              title: Text(
                                username.toString(),
                                style: const TextStyle(color: Colors.white),
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                if (userId != null) {
                                  final usernameStr = username.toString();
                                  Future.delayed(
                                    const Duration(milliseconds: 150),
                                    () {
                                      if (!context.mounted) return;
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => UserProfilePage(
                                            userId: userId,
                                            initialUsername: usernameStr,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                }
                              },
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

  String _formatTimeAgo(dynamic createdAt) {
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(DateTime.parse(createdAt));
    if (diff.inMinutes < 60) return '${diff.inMinutes} Min.';
    if (diff.inHours < 24) return '${diff.inHours} Std.';
    return '${diff.inDays} Tage';
  }
}

/// Delegate für den pinned TabBar im NestedScrollView.
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: const Color(0xFF0B0E14), child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}
