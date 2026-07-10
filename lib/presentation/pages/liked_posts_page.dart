import 'package:flutter/material.dart';
import 'package:cruise_connect/presentation/widgets/skeletons/post_skeleton.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/post_detail_page.dart';
import 'package:cruise_connect/presentation/pages/user_profile_page.dart';
import 'package:cruise_connect/presentation/widgets/mentions.dart';
import 'package:cruise_connect/presentation/widgets/social/group_attachment_card.dart';
import 'package:cruise_connect/presentation/widgets/social/route_attachment_card.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

class LikedPostsPage extends StatefulWidget {
  const LikedPostsPage({super.key});

  @override
  State<LikedPostsPage> createState() => _LikedPostsPageState();
}

class _LikedPostsPageState extends State<LikedPostsPage> {
  List<Map<String, dynamic>> _likes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadLikes();
    });
  }

  Future<void> _loadLikes() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);
    try {
      final likes = await SocialService.getUserLikes(uid);
      if (!mounted) return;
      final provider = context.read<CommunityProvider>();
      final visibleLikes = <Map<String, dynamic>>[];
      for (final like in likes) {
        final post = like['posts'];
        if (post is! Map) continue;
        final postMap = Map<String, dynamic>.from(post);
        postMap['is_liked_by_me'] = true;
        like['posts'] = postMap;
        provider.registerPost(postMap);
        visibleLikes.add(like);
      }
      setState(() {
        _likes = visibleLikes;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[LikedPostsPage] Likes laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unlike(Map<String, dynamic> like) async {
    final post = like['posts'];
    if (post is! Map) return;
    final postId = post['id'] as String?;
    if (postId == null) return;

    final provider = context.read<CommunityProvider>();
    provider.registerPost(Map<String, dynamic>.from(post));
    await provider.toggleLike(postId);
    if (!mounted) return;

    if (!provider.isLiked(postId)) {
      setState(() {
        _likes = _likes.where((entry) {
          final entryPost = entry['posts'];
          return entryPost is! Map || entryPost['id'] != postId;
        }).toList();
      });
    }
  }

  void _openPost(Map<String, dynamic> post) {
    final author = post['profiles'] as Map<String, dynamic>?;
    final authorName = SocialService.publicDisplayName(
      author,
      fallbackUserId: post['user_id'] as String?,
    );
    final authorHandle = SocialService.publicHandle(
      author,
      fallbackUserId: post['user_id'] as String?,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailPage(
          postId: post['id'] as String,
          name: authorName,
          handle: authorHandle,
          content: (post['content'] ?? '').toString(),
          time: _formatTimeAgo(post['created_at']),
          sharedRouteId: post['shared_route_id'] as String?,
          sharedGroupId: post['shared_group_id'] as String?,
          avatarUrl: author?['avatar_url'] as String?,
        ),
      ),
    ).then((_) => _loadLikes());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          'Gefällt mir',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const PostSkeletonList(count: 4)
          : RefreshIndicator(
              color: AppAccentColors.accent,
              backgroundColor: const Color(0xFF1C1F26),
              onRefresh: _loadLikes,
              child: _likes.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(32),
                      children: [
                        const SizedBox(height: 120),
                        Icon(
                          Icons.favorite_border,
                          color: Colors.grey[700],
                          size: 56,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Noch keine Likes',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Posts, die dir gefallen, erscheinen hier.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _likes.length,
                      itemBuilder: (context, index) {
                        return _LikedPostCard(
                          like: _likes[index],
                          onTap: _openPost,
                          onUnlike: () => _unlike(_likes[index]),
                          timeAgo: _formatTimeAgo,
                        );
                      },
                    ),
            ),
    );
  }

  String _formatTimeAgo(dynamic createdAt) {
    if (createdAt == null) return '';
    final parsed = DateTime.tryParse(createdAt.toString());
    if (parsed == null) return '';
    final diff = DateTime.now().difference(parsed);
    if (diff.inMinutes < 1) return 'gerade eben';
    if (diff.inMinutes < 60) return '${diff.inMinutes} Min.';
    if (diff.inHours < 24) return '${diff.inHours} Std.';
    if (diff.inDays < 30) return '${diff.inDays} Tage';
    final months = (diff.inDays / 30).floor();
    if (months < 12) return '$months Mon.';
    return '${(months / 12).floor()} J.';
  }
}

class _LikedPostCard extends StatelessWidget {
  const _LikedPostCard({
    required this.like,
    required this.onTap,
    required this.onUnlike,
    required this.timeAgo,
  });

  final Map<String, dynamic> like;
  final void Function(Map<String, dynamic> post) onTap;
  final VoidCallback onUnlike;
  final String Function(dynamic value) timeAgo;

  @override
  Widget build(BuildContext context) {
    final post = like['posts'];
    if (post is! Map<String, dynamic>) return const SizedBox.shrink();

    final author = post['profiles'] as Map<String, dynamic>?;
    final authorName = SocialService.publicDisplayName(
      author,
      fallbackUserId: post['user_id'] as String?,
    );
    final authorHandle = SocialService.publicHandle(
      author,
      fallbackUserId: post['user_id'] as String?,
    );
    final authorId = author?['id'] as String?;
    final postId = post['id'] as String?;
    final provider = context.watch<CommunityProvider>();
    final likeCount = postId == null ? 0 : provider.likeCount(postId);
    final repostCount = postId == null ? 0 : provider.repostCount(postId);
    final commentsCount = (post['comments_count'] as num?)?.toInt() ?? 0;

    return InkWell(
      onTap: () => onTap(post),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.favorite, color: AppAccentColors.accent, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Gefällt dir · ${timeAgo(like['created_at'])}',
                  style: TextStyle(
                    color: AppAccentColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  child: UserAvatar.fromProfile(
                    author,
                    fallbackName: authorName,
                    radius: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
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
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: authorName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          ' $authorHandle · ${timeAgo(post['created_at'])}',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
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
                              if (value == 'unlike') onUnlike();
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'unlike',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.favorite,
                                      color: AppAccentColors.accent,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Like entfernen',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.35,
                          ),
                          children: buildMentionSpans(
                            context: context,
                            text: (post['content'] ?? '').toString(),
                            baseStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                      if (post['shared_route_id'] != null) ...[
                        const SizedBox(height: 10),
                        RouteAttachmentCard(
                          routeId: post['shared_route_id'] as String,
                          compact: true,
                        ),
                      ],
                      // 2026-07-03 (vucko Gruppen-Share): Gruppen-Karte analog.
                      if (post['shared_group_id'] != null) ...[
                        const SizedBox(height: 10),
                        GroupAttachmentCard(
                          groupId: post['shared_group_id'] as String,
                          compact: true,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _Metric(
                            icon: Icons.chat_bubble_outline,
                            value: commentsCount,
                          ),
                          const SizedBox(width: 22),
                          _Metric(
                            icon: Icons.repeat,
                            value: repostCount,
                            color: provider.isReposted(postId ?? '')
                                ? const Color(0xFF00C853)
                                : Colors.grey,
                          ),
                          const SizedBox(width: 22),
                          InkWell(
                            onTap: onUnlike,
                            borderRadius: BorderRadius.circular(18),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              child: _Metric(
                                icon: Icons.favorite,
                                value: likeCount,
                                color: AppAccentColors.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value, this.color});

  final IconData icon;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Colors.grey;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: effectiveColor),
        if (value > 0) ...[
          const SizedBox(width: 5),
          Text('$value', style: TextStyle(color: effectiveColor, fontSize: 12)),
        ],
      ],
    );
  }
}
