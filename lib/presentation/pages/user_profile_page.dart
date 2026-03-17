import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/social_service.dart';

/// Profil-Seite eines anderen Users (oder des eigenen).
class UserProfilePage extends StatefulWidget {
  final String userId;
  const UserProfilePage({super.key, required this.userId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  bool _loading = true;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _posts = [];
  bool _isFollowing = false;
  bool _isOwnProfile = false;

  @override
  void initState() {
    super.initState();
    _isOwnProfile = widget.userId == Supabase.instance.client.auth.currentUser?.id;
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        SocialService.getProfileStats(widget.userId),
        SocialService.getUserPosts(widget.userId),
        if (!_isOwnProfile) SocialService.isFollowing(widget.userId),
      ]);
      if (mounted) {
        setState(() {
          _stats = results[0] as Map<String, dynamic>;
          _posts = results[1] as List<Map<String, dynamic>>;
          if (!_isOwnProfile) _isFollowing = results[2] as bool;
          _loading = false;
        });
      }
    } catch (_) {
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
        title: Text('@${name.toString().toLowerCase()}', style: const TextStyle(color: Colors.white, fontSize: 16)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30)))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFFFF3B30),
              child: ListView(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: const Color(0xFFFF3B30),
                          child: Text(
                            name.toString().isNotEmpty ? name.toString()[0].toUpperCase() : 'U',
                            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(name.toString(), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Level $level', style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 16),
                        // Stats Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildStat('$totalRoutes', 'Fahrten'),
                            _buildStat('${totalKm.toStringAsFixed(0)} km', 'Gefahren'),
                            _buildStat('$followers', 'Follower'),
                            _buildStat('$following', 'Folgt'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Follow Button
                        if (!_isOwnProfile)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                if (_isFollowing) {
                                  await SocialService.unfollowUser(widget.userId);
                                } else {
                                  await SocialService.followUser(widget.userId);
                                }
                                setState(() => _isFollowing = !_isFollowing);
                                _load();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isFollowing ? Colors.transparent : const Color(0xFFFF3B30),
                                side: _isFollowing ? const BorderSide(color: Colors.grey) : null,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                elevation: 0,
                              ),
                              child: Text(
                                _isFollowing ? 'Folgst du' : 'Folgen',
                                style: TextStyle(
                                  color: _isFollowing ? Colors.grey : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Divider
                  Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                  // Posts
                  if (_posts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Noch keine Posts', style: TextStyle(color: Colors.grey))),
                    )
                  else
                    ..._posts.map((post) => _buildPostItem(post)),
                ],
              ),
            ),
    );
  }

  Widget _buildStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
      ],
    );
  }

  Widget _buildPostItem(Map<String, dynamic> post) {
    final content = post['content'] ?? '';
    final createdAt = post['created_at'];
    final diff = createdAt != null ? DateTime.now().difference(DateTime.parse(createdAt)) : null;
    String time = '';
    if (diff != null) {
      if (diff.inMinutes < 60) {
        time = '${diff.inMinutes} Min.';
      } else if (diff.inHours < 24) {
        time = '${diff.inHours} Std.';
      } else {
        time = '${diff.inDays} Tage';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(content, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3)),
          const SizedBox(height: 6),
          Text(time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.05)),
        ],
      ),
    );
  }
}
