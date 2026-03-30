import 'package:flutter/material.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PostDetailPage extends StatefulWidget {
  final String postId;
  final String name;
  final String handle;
  final String content;
  final String time;

  const PostDetailPage({
    super.key,
    required this.postId,
    required this.name,
    required this.handle,
    required this.content,
    required this.time,
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
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Original Post
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.grey[800],
                        child: Text(
                          widget.name.isNotEmpty
                              ? widget.name[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            widget.handle,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${widget.time} · CruiseConnect',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 10),
                  Text(
                    'Kommentare (${_comments.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_loading)
                    const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF3B30),
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
                      final commentUserId = comment['user_id'] as String?;
                      final username = SocialService.publicDisplayName(
                        profile,
                        fallbackUserId: commentUserId,
                      );
                      final isOwn = commentUserId == currentUserId;

                      return _buildComment(
                        username,
                        comment['content'] ?? '',
                        commentId: comment['id'],
                        isOwn: isOwn,
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
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
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
                          : const Color(0xFFFF3B30),
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.grey[800],
            child: Text(
              user.isNotEmpty ? user[0].toUpperCase() : 'U',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
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
