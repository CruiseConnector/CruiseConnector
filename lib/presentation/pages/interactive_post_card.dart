import 'package:flutter/material.dart';
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
    this.initialLikeCount = "0",
    this.initialRepostCount = "0",
    this.initialCommentCount = "0",
  });

  @override
  State<InteractivePostCard> createState() => _InteractivePostCardState();
}

class _InteractivePostCardState extends State<InteractivePostCard> {
  bool _isLiked = false;
  bool _isReposted = false;
  late int _likeCount;
  late int _repostCount;

  @override
  void initState() {
    super.initState();
    _likeCount = int.tryParse(widget.initialLikeCount) ?? 0;
    _repostCount = int.tryParse(widget.initialRepostCount) ?? 0;
  }

  void _toggleLike() {
    setState(() {
      _isLiked = !_isLiked;
      if (_isLiked) {
        _likeCount++;
      } else {
        _likeCount--;
      }
    });
  }

  void _toggleRepost() {
    setState(() {
      _isReposted = !_isReposted;
      if (_isReposted) {
        _repostCount++;
      } else {
        _repostCount--;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
                backgroundColor: const Color(0xFFFF3B30),
                child: Text(widget.name.isNotEmpty ? widget.name[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    Row(
                      children: [
                        Text(widget.handle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        const SizedBox(width: 5),
                        const Text("·", style: TextStyle(color: Colors.grey, fontSize: 13)),
                        const SizedBox(width: 5),
                        Text(widget.time, style: const TextStyle(color: Colors.grey, fontSize: 13)),
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
            style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
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
              _buildActionButton(icon: _isReposted ? Icons.repeat_on : Icons.repeat, color: _isReposted ? const Color(0xFF00C853) : Colors.grey, count: _repostCount.toString(), onTap: _toggleRepost),
              // Like Button
              _buildActionButton(icon: _isLiked ? Icons.favorite : Icons.favorite_border, color: _isLiked ? const Color(0xFFFF3B30) : Colors.grey, count: _likeCount.toString(), onTap: _toggleLike),
              // Share Button
              _buildActionButton(icon: Icons.share_outlined, color: Colors.grey, count: "", onTap: () {}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required Color color, required String count, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            if (count.isNotEmpty && count != "0") ...[
              const SizedBox(width: 6),
              Text(count, style: TextStyle(color: color, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}