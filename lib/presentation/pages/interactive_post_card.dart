import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/core/deep_links.dart';
import 'package:cruise_connect/presentation/pages/post_detail_page.dart';

class InteractivePostCard extends StatefulWidget {
  final String postId;
  final String name;
  final String handle;
  final String time;
  final String content;
  final String initialLikeCount;
  final String initialRepostCount;
  final String initialCommentCount;

  const InteractivePostCard({
    super.key,
    required this.postId,
    required this.name,
    required this.handle,
    required this.time,
    required this.content,
    this.initialLikeCount = '0',
    this.initialRepostCount = '0',
    this.initialCommentCount = '0',
  });

  @override
  State<InteractivePostCard> createState() => _InteractivePostCardState();
}

class _InteractivePostCardState extends State<InteractivePostCard> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<CommunityProvider>();
    provider.registerPost({
      'id': widget.postId,
      'likes_count': int.tryParse(widget.initialLikeCount) ?? 0,
      'reposts_count': int.tryParse(widget.initialRepostCount) ?? 0,
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      provider.ensureLikedChecked(widget.postId);
      provider.ensureRepostedChecked(widget.postId);
    });
  }

  void _toggleLike() =>
      context.read<CommunityProvider>().toggleLike(widget.postId);
  void _toggleRepost() =>
      context.read<CommunityProvider>().toggleRepost(widget.postId);
  void _sharePost() {
    final link = CruiseDeepLinks.postUri(widget.postId).toString();
    Share.share(
      'Post von ${widget.handle} auf CruiseConnect: $link',
      subject: 'CruiseConnect Post',
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CommunityProvider>();
    final isLiked = provider.isLiked(widget.postId);
    final isReposted = provider.isReposted(widget.postId);
    final likeCount = provider.likeCount(widget.postId);
    final repostCount = provider.repostCount(widget.postId);
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
          // Header
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppAccentColors.accent,
                child: Text(
                  widget.name.isNotEmpty ? widget.name[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          widget.handle,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          '·',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          widget.time,
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
              const Icon(Icons.more_horiz, color: Colors.grey, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          // Content
          Text(
            widget.content,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          // Action Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Comment Button - Navigates to Detail
              _buildActionButton(
                icon: Icons.chat_bubble_outline,
                color: Colors.grey,
                count: widget.initialCommentCount,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PostDetailPage(
                        postId: widget.postId,
                        name: widget.name,
                        handle: widget.handle,
                        content: widget.content,
                        time: widget.time,
                      ),
                    ),
                  );
                },
              ),
              // Repost Button
              _buildActionButton(
                icon: isReposted ? Icons.repeat_on : Icons.repeat,
                color: isReposted ? const Color(0xFF00C853) : Colors.grey,
                count: repostCount.toString(),
                onTap: _toggleRepost,
              ),
              // Like Button
              _buildActionButton(
                icon: isLiked ? Icons.favorite : Icons.favorite_border,
                color: isLiked ? AppAccentColors.accent : Colors.grey,
                count: likeCount.toString(),
                onTap: _toggleLike,
              ),
              // Share Button
              _buildActionButton(
                icon: Icons.share_outlined,
                color: Colors.grey,
                count: '',
                onTap: _sharePost,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String count,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            if (count.isNotEmpty && count != '0') ...[
              const SizedBox(width: 6),
              Text(count, style: TextStyle(color: color, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}
