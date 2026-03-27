import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/widgets/social/route_attachment_card.dart';

/// Profil-Seite eines anderen Users (oder des eigenen).
class UserProfilePage extends StatefulWidget {
  final String userId;
  const UserProfilePage({super.key, required this.userId});

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
  bool _isFollowing = false;
  bool _isOwnProfile = false;
  bool _isPrivate = false;

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
      final results = await Future.wait([
        SocialService.getProfileStats(widget.userId),
        SocialService.getUserPosts(widget.userId),
        SocialService.getUserReposts(widget.userId),
        if (!_isOwnProfile) SocialService.isFollowing(widget.userId),
      ]);
      if (mounted) {
        setState(() {
          _stats = results[0] as Map<String, dynamic>;
          _isPrivate = _stats['is_private'] == true;
          _posts = results[1] as List<Map<String, dynamic>>;
          _reposts = results[2] as List<Map<String, dynamic>>;
          if (!_isOwnProfile) _isFollowing = results[3] as bool;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[UserProfile] Daten laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _stats['username'] ?? 'User';
    final level = _stats['level'] ?? 1;
    final totalKm = (_stats['total_km'] as num?)?.toDouble() ?? 0;
    final totalRoutes = _stats['total_routes'] ?? 0;
    final followers = _stats['follower_count'] ?? 0;
    final following = _stats['following_count'] ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '@${name.toString().toLowerCase()}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF3B30)),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFFFF3B30),
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: const Color(0xFFFF3B30),
                            child: Text(
                              name.toString().isNotEmpty
                                  ? name.toString()[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            name.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Level $level',
                            style: const TextStyle(
                              color: Color(0xFFFF3B30),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Stats Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildStat('$totalRoutes', 'Fahrten'),
                              _buildStat(
                                '${totalKm.toStringAsFixed(0)} km',
                                'Gefahren',
                              ),
                              // Follower/Following-Liste nur anklickbar wenn man folgt oder eigenes Profil
                              GestureDetector(
                                onTap: (_isFollowing || _isOwnProfile)
                                    ? () => _showFollowList('followers')
                                    : null,
                                child: _buildStat('$followers', 'Follower'),
                              ),
                              GestureDetector(
                                onTap: (_isFollowing || _isOwnProfile)
                                    ? () => _showFollowList('following')
                                    : null,
                                child: _buildStat('$following', 'Folgt'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Follow Button
                          if (!_isOwnProfile)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final wasFollowing = _isFollowing;
                                  setState(() {
                                    _isFollowing = !wasFollowing;
                                    // Optimistisch Follower-Count aktualisieren
                                    final currentCount =
                                        (_stats['follower_count'] as int?) ?? 0;
                                    _stats['follower_count'] = wasFollowing
                                        ? currentCount - 1
                                        : currentCount + 1;
                                  });
                                  try {
                                    if (wasFollowing) {
                                      await SocialService.unfollowUser(
                                        widget.userId,
                                      );
                                    } else {
                                      await SocialService.followUser(
                                        widget.userId,
                                      );
                                    }
                                  } catch (e) {
                                    debugPrint(
                                      '[UserProfile] Follow/Unfollow fehlgeschlagen: $e',
                                    );
                                    if (mounted) {
                                      setState(() {
                                        _isFollowing = wasFollowing;
                                        final currentCount =
                                            (_stats['follower_count']
                                                as int?) ??
                                            0;
                                        _stats['follower_count'] = wasFollowing
                                            ? currentCount + 1
                                            : currentCount - 1;
                                      });
                                    }
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isFollowing
                                      ? Colors.transparent
                                      : const Color(0xFFFF3B30),
                                  side: _isFollowing
                                      ? const BorderSide(color: Colors.grey)
                                      : null,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  _isFollowing ? 'Folgst du' : 'Folgen',
                                  style: TextStyle(
                                    color: _isFollowing
                                        ? Colors.grey
                                        : Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Tab Bar
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TabBarDelegate(
                      TabBar(
                        controller: _tabController,
                        indicator: const UnderlineTabIndicator(
                          borderSide: BorderSide(
                            color: Color(0xFFFF3B30),
                            width: 2,
                          ),
                        ),
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.grey,
                        tabs: [
                          Tab(text: 'Posts (${_posts.length})'),
                          Tab(text: 'Reposts (${_reposts.length})'),
                        ],
                      ),
                    ),
                  ),
                ],
                body: TabBarView(
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

  Widget _buildStat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildPostItem(Map<String, dynamic> post) {
    final content = post['content'] ?? '';
    final time = _formatTimeAgo(post['created_at']);
    final likes = post['likes_count'] ?? 0;
    final comments = post['comments_count'] ?? 0;
    final reposts = post['reposts_count'] ?? 0;
    final sharedRouteId = post['shared_route_id'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            content,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.3,
            ),
          ),
          if (sharedRouteId != null) ...[
            const SizedBox(height: 10),
            RouteAttachmentCard(routeId: sharedRouteId, compact: true),
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
    );
  }

  Widget _buildRepostItem(Map<String, dynamic> repost) {
    final post = repost['posts'] as Map<String, dynamic>?;
    if (post == null) return const SizedBox.shrink();

    final content = post['content'] ?? '';
    final time = _formatTimeAgo(repost['created_at']);
    final author = post['profiles'] as Map<String, dynamic>?;
    final authorName = author?['username'] ?? 'User';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.repeat, size: 14, color: Color(0xFF34C759)),
              const SizedBox(width: 6),
              Text(
                'Repost von @$authorName',
                style: const TextStyle(color: Color(0xFF34C759), fontSize: 12),
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
                Text(
                  content,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
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
              'Folge diesem Konto um die Posts und Reposts zu sehen.',
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
                      const Expanded(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFFF3B30),
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
                            final username =
                                profile?['username'] ??
                                profile?['email']?.split('@')[0] ??
                                'User';
                            final userId = profile?['id'] as String?;

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFFF3B30),
                                child: Text(
                                  username.toString().isNotEmpty
                                      ? username.toString()[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                username.toString(),
                                style: const TextStyle(color: Colors.white),
                              ),
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
