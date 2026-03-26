import 'package:flutter/material.dart';
import 'package:cruise_connect/data/services/social_service.dart';

class CreatePostPage extends StatefulWidget {
  final String? initialText;
  final String? sharedRouteId;
  const CreatePostPage({super.key, this.initialText, this.sharedRouteId});

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final _controller = TextEditingController();
  bool _posting = false;
  String _visibility = 'public'; // 'public' oder 'followers'

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null) {
      _controller.text = widget.initialText!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitPost() async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;

    setState(() => _posting = true);
    try {
      await SocialService.createPost(content, visibility: _visibility, sharedRouteId: widget.sharedRouteId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _posting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Erstellen des Posts'), backgroundColor: Color(0xFF1C1F26)),
        );
      }
    }
  }

  Widget _buildVisibilityChip(String value, IconData icon, String label) {
    final selected = _visibility == value;
    return GestureDetector(
      onTap: () => setState(() => _visibility = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF3B30) : const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFFFF3B30) : Colors.grey[700]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : Colors.grey),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              color: selected ? Colors.white : Colors.grey,
              fontSize: 14,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = _controller.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        elevation: 0,
        leadingWidth: 100,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen', style: TextStyle(color: Colors.white, fontSize: 16)),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 10, bottom: 10),
            child: ElevatedButton(
              onPressed: _posting || !hasContent ? null : _submitPost,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF3B30),
                disabledBackgroundColor: const Color(0xFFFF3B30).withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: _posting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Posten', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Sichtbarkeits-Toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                _buildVisibilityChip('public', Icons.public, 'Alle'),
                const SizedBox(width: 8),
                _buildVisibilityChip('followers', Icons.group, 'Follower'),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1C1F26), height: 1),
          // Post-Eingabe
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey[800],
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      maxLines: null,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: "Was gibt's Neues?",
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 18),
                        border: InputBorder.none,
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
}
