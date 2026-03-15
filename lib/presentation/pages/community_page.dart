import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/create_post_page.dart';
import 'package:cruise_connect/presentation/pages/create_group_page.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _loading = true;
  List<Map<String, dynamic>> _feedPosts = [];
  List<Map<String, dynamic>> _myGroups = [];
  List<Map<String, dynamic>> _discoverPosts = [];
  List<Map<String, dynamic>> _discoverGroups = [];
  List<Map<String, dynamic>> _searchResults = [];
  int _unreadNotifications = 0;
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        SocialService.getFeedPosts(),
        SocialService.getMyGroups(),
        SocialService.getDiscoverPosts(),
        SocialService.getDiscoverGroups(),
        SocialService.getUnreadCount(),
      ]);

      if (mounted) {
        setState(() {
          _feedPosts = results[0] as List<Map<String, dynamic>>;
          _myGroups = results[1] as List<Map<String, dynamic>>;
          _discoverPosts = results[2] as List<Map<String, dynamic>>;
          _discoverGroups = results[3] as List<Map<String, dynamic>>;
          _unreadNotifications = results[4] as int;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    final results = await SocialService.searchUsers(query);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        title: const Text("Community", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => _showSearchDialog(),
          ),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.white),
                onPressed: () => _showNotifications(),
              ),
              if (_unreadNotifications > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Color(0xFFFF3B30), shape: BoxShape.circle),
                    child: Text('$_unreadNotifications', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFF3B30),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: "Feed"),
            Tab(text: "Aktive Gruppen"),
            Tab(text: "Entdecken"),
          ],
        ),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFF3B30),
        child: Icon(_tabController.index == 1 ? Icons.group_add : Icons.add, color: Colors.white),
        onPressed: () async {
          if (_tabController.index == 0 || _tabController.index == 2) {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePostPage()));
          } else {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupPage()));
          }
          _loadData();
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFeedTab(),
                _buildGroupsTab(),
                _buildDiscoverTab(),
              ],
            ),
    );
  }

  // ── Feed Tab ──────────────────────────────────────────────────────────

  Widget _buildFeedTab() {
    if (_feedPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, color: Colors.grey[700], size: 48),
            const SizedBox(height: 12),
            const Text('Dein Feed ist leer', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Folge anderen Nutzern um ihre Posts zu sehen', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _tabController.animateTo(2),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF3B30)),
              child: const Text('Entdecken', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFFFF3B30),
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: _feedPosts.length,
        separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
        itemBuilder: (context, index) => _buildPostItem(_feedPosts[index]),
      ),
    );
  }

  // ── Groups Tab ────────────────────────────────────────────────────────

  Widget _buildGroupsTab() {
    if (_myGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_outlined, color: Colors.grey[700], size: 48),
            const SizedBox(height: 12),
            const Text('Keine aktiven Gruppen', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Erstelle oder trete einer Gruppe bei', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFFFF3B30),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _myGroups.length,
        itemBuilder: (context, index) {
          final group = _myGroups[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildGroupCard(group, true),
          );
        },
      ),
    );
  }

  // ── Discover Tab ──────────────────────────────────────────────────────

  Widget _buildDiscoverTab() {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFFFF3B30),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          if (_discoverGroups.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text("Gruppen entdecken", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _discoverGroups.length,
                itemBuilder: (context, index) {
                  final group = _discoverGroups[index];
                  return Container(
                    width: 200,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1F26),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(group['name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        if (group['route_name'] != null)
                          Text(group['route_name'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        GestureDetector(
                          onTap: () async {
                            await SocialService.joinGroup(group['id']);
                            _loadData();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3B30),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text("Beitreten", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text("Vorschläge für dich", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ),
          if (_discoverPosts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Noch keine Posts in der Community', style: TextStyle(color: Colors.grey))),
            )
          else
            ...List.generate(_discoverPosts.length, (index) {
              final post = _discoverPosts[index];
              final isOwnPost = post['user_id'] == currentUserId;
              return Column(
                children: [
                  _buildPostItem(post, showFollow: !isOwnPost),
                  if (index < _discoverPosts.length - 1) const Divider(color: Colors.white10, height: 1),
                ],
              );
            }),
        ],
      ),
    );
  }

  // ── Post Item ─────────────────────────────────────────────────────────

  Widget _buildPostItem(Map<String, dynamic> post, {bool showFollow = false}) {
    final profile = post['profiles'] as Map<String, dynamic>?;
    final name = profile?['username'] ?? profile?['email']?.split('@')[0] ?? 'User';
    final handle = '@${profile?['email']?.split('@')[0] ?? 'user'}';
    final time = _formatTimeAgo(post['created_at']);
    final content = post['content'] ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFFF3B30),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(width: 5),
                    Flexible(child: Text(handle, style: const TextStyle(color: Colors.grey, fontSize: 14), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 5),
                    Text("· $time", style: const TextStyle(color: Colors.grey, fontSize: 14)),
                    if (showFollow) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () async {
                          await SocialService.followUser(post['user_id']);
                          _loadData();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Du folgst jetzt $name'), backgroundColor: const Color(0xFF1C1F26)),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFFF3B30)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text("Folgen", style: TextStyle(color: Color(0xFFFF3B30), fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(content, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildInteraction(Icons.chat_bubble_outline, '${post['comments_count'] ?? 0}'),
                    _buildInteraction(Icons.repeat, '${post['reposts_count'] ?? 0}'),
                    _PostLikeButton(postId: post['id'], initialCount: post['likes_count'] ?? 0),
                    _buildInteraction(Icons.share_outlined, ''),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteraction(IconData icon, String count) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey, size: 18),
        if (count.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(count, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ],
    );
  }

  // ── Group Card ────────────────────────────────────────────────────────

  Widget _buildGroupCard(Map<String, dynamic> group, bool isJoined) {
    final memberCount = (group['group_members'] as List?)?.length ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: isJoined ? Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(group['name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                if (isJoined)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text("Dabei", style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  )
                else
                  GestureDetector(
                    onTap: () async {
                      await SocialService.joinGroup(group['id']);
                      _loadData();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFFF3B30), borderRadius: BorderRadius.circular(12)),
                      child: const Text("Beitreten", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            if (group['route_name'] != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.terrain, color: Colors.white70, size: 14),
                const SizedBox(width: 6),
                Text(group['route_name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 14)),
              ]),
            ],
            if (group['stats'] != null) ...[
              const SizedBox(height: 4),
              Text(group['stats'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.local_fire_department, color: Colors.orange, size: 14),
              const SizedBox(width: 6),
              Text("$memberCount Fahrer", style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
            if (group['time_location'] != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.flag, color: Colors.white70, size: 14),
                const SizedBox(width: 6),
                Text(group['time_location'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  // ── Search Dialog ─────────────────────────────────────────────────────

  void _showSearchDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0E14),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40, height: 4,
                        decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Benutzername suchen...',
                          hintStyle: const TextStyle(color: Colors.grey),
                          prefixIcon: const Icon(Icons.search, color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF1C1F26),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        onChanged: (query) async {
                          await _searchUsers(query);
                          setModalState(() {});
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _searchResults.isEmpty
                          ? Center(
                              child: Text(
                                _searchController.text.isEmpty ? 'Suche nach Benutzernamen' : 'Keine Ergebnisse',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: _searchResults.length,
                              itemBuilder: (context, index) {
                                final user = _searchResults[index];
                                final username = user['username'] ?? user['email']?.split('@')[0] ?? 'User';
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFFFF3B30),
                                    child: Text(username[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                                  title: Text(username, style: const TextStyle(color: Colors.white)),
                                  subtitle: Text('@${user['email']?.split('@')[0] ?? ''}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                  trailing: _FollowButton(userId: user['id'], onChanged: () => _loadData()),
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
    ).then((_) => _searchController.clear());
  }

  // ── Notifications ─────────────────────────────────────────────────────

  void _showNotifications() async {
    await SocialService.markAllRead();
    setState(() => _unreadNotifications = 0);

    if (!mounted) return;

    final notifications = await SocialService.getNotifications();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B0E14),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Align(alignment: Alignment.centerLeft, child: Text("Benachrichtigungen", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
            ),
            if (notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Keine Benachrichtigungen', style: TextStyle(color: Colors.grey)),
              )
            else
              ...notifications.take(10).map((n) {
                final from = n['profiles'] as Map<String, dynamic>?;
                final fromName = from?['username'] ?? from?['email']?.split('@')[0] ?? 'User';
                final type = n['type'];
                String message;
                IconData icon;
                switch (type) {
                  case 'follow':
                    message = '$fromName folgt dir jetzt';
                    icon = Icons.person_add;
                    break;
                  case 'like':
                    message = '$fromName hat deinen Post geliked';
                    icon = Icons.favorite;
                    break;
                  default:
                    message = '$fromName hat interagiert';
                    icon = Icons.notifications;
                }
                return ListTile(
                  leading: Icon(icon, color: const Color(0xFFFF3B30)),
                  title: Text(message, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(_formatTimeAgo(n['created_at']), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                );
              }),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}

// ── Follow Button Widget ──────────────────────────────────────────────

class _FollowButton extends StatefulWidget {
  final String userId;
  final VoidCallback onChanged;
  const _FollowButton({required this.userId, required this.onChanged});

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  bool _following = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkFollow();
  }

  Future<void> _checkFollow() async {
    final result = await SocialService.isFollowing(widget.userId);
    if (mounted) setState(() { _following = result; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF3B30)));
    if (widget.userId == Supabase.instance.client.auth.currentUser?.id) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () async {
        if (_following) {
          await SocialService.unfollowUser(widget.userId);
        } else {
          await SocialService.followUser(widget.userId);
        }
        setState(() => _following = !_following);
        widget.onChanged();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _following ? Colors.transparent : const Color(0xFFFF3B30),
          borderRadius: BorderRadius.circular(20),
          border: _following ? Border.all(color: Colors.grey) : null,
        ),
        child: Text(
          _following ? "Folgst du" : "Folgen",
          style: TextStyle(color: _following ? Colors.grey : Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ── Post Like Button ──────────────────────────────────────────────────

class _PostLikeButton extends StatefulWidget {
  final String postId;
  final int initialCount;
  const _PostLikeButton({required this.postId, required this.initialCount});

  @override
  State<_PostLikeButton> createState() => _PostLikeButtonState();
}

class _PostLikeButtonState extends State<_PostLikeButton> {
  late int _count;
  bool _liked = false;

  @override
  void initState() {
    super.initState();
    _count = widget.initialCount;
    _checkLiked();
  }

  Future<void> _checkLiked() async {
    final liked = await SocialService.hasLiked(widget.postId);
    if (mounted) setState(() => _liked = liked);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final nowLiked = await SocialService.toggleLike(widget.postId);
        setState(() {
          _liked = nowLiked;
          _count += nowLiked ? 1 : -1;
        });
      },
      child: Row(
        children: [
          Icon(_liked ? Icons.favorite : Icons.favorite_border, color: _liked ? const Color(0xFFFF3B30) : Colors.grey, size: 18),
          const SizedBox(width: 4),
          Text('$_count', style: TextStyle(color: _liked ? const Color(0xFFFF3B30) : Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}
