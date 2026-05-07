import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/widgets/mentions.dart';
import 'package:cruise_connect/presentation/widgets/social/route_attachment_card.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PostDetailPage extends StatefulWidget {
  final String postId;
  final String name;
  final String handle;
  final String content;
  final String time;
  final String? sharedRouteId;
  final String? avatarUrl;

  const PostDetailPage({
    super.key,
    required this.postId,
    required this.name,
    required this.handle,
    required this.content,
    required this.time,
    this.sharedRouteId,
    this.avatarUrl,
  });

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final _commentController = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final comments = await SocialService.getComments(widget.postId);
      if (mounted) {
        setState(() {
          _comments = comments;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[PostDetail] Kommentare laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await SocialService.addComment(widget.postId, text);
      _commentController.clear();
      await _loadComments();
    } catch (e) {
      debugPrint('[PostDetail] Kommentar senden fehlgeschlagen: $e');
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Beitrag', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Original Post
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151922),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            UserAvatar(
                              name: widget.name,
                              avatarUrl: widget.avatarUrl,
                              radius: 21,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    widget.handle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              widget.time,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text.rich(
                          TextSpan(
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              height: 1.35,
                            ),
                            children: buildMentionSpans(
                              context: context,
                              text: widget.content,
                              baseStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                        if (widget.sharedRouteId != null) ...[
                          const SizedBox(height: 12),
                          RouteAttachmentCard(
                            routeId: widget.sharedRouteId!,
                            compact: true,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          'CruiseConnect',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.42),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'Kommentare',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppAccentColors.accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_comments.length}',
                          style: TextStyle(
                            color: AppAccentColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_loading)
                    Center(
                      child: CircularProgressIndicator(
                        color: AppAccentColors.accent,
                      ),
                    )
                  else if (_comments.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'Noch keine Kommentare',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ..._comments.map((comment) {
                      final profile =
                          comment['profiles'] as Map<String, dynamic>?;
                      final username = profile?['username'] ?? 'User';
                      final commentUserId = comment['user_id'] as String?;
                      final isOwn = commentUserId == currentUserId;

                      return _buildComment(
                        username,
                        comment['content'] ?? '',
                        commentId: comment['id'],
                        isOwn: isOwn,
                        profile: profile,
                      );
                    }),
                ],
              ),
            ),
          ),
          // Comment input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1C1F26),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      height: 45,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: TextField(
                        controller: _commentController,
                        maxLength: AppInputLimits.commentMaxLength,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          counterText: '',
                          hintText: 'Kommentar schreiben...',
                          hintStyle: TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendComment(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _sendComment,
                    child: CircleAvatar(
                      backgroundColor: _sending
                          ? Colors.grey
                          : AppAccentColors.accent,
                      radius: 22,
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComment(
    String user,
    String text, {
    String? commentId,
    bool isOwn = false,
    Map<String, dynamic>? profile,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar.fromProfile(profile, fallbackName: user, radius: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1F26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(text, style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
          if (isOwn && commentId != null)
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: Colors.grey[600],
                size: 18,
              ),
              onPressed: () async {
                await SocialService.deleteComment(commentId, widget.postId);
                _loadComments();
              },
            ),
        ],
      ),
    );
  }
}
