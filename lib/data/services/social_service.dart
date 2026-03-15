import 'package:supabase_flutter/supabase_flutter.dart';

/// Service für soziale Features: Posts, Follows, Gruppen, Notifications.
class SocialService {
  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _userId => _db.auth.currentUser?.id;

  // ── Posts ──────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getFeedPosts() async {
    final uid = _userId;
    if (uid == null) return [];

    // Posts von Usern denen man folgt
    final followingIds = await _db
        .from('follows')
        .select('following_id')
        .eq('follower_id', uid)
        .eq('status', 'accepted');

    final ids = (followingIds as List).map((f) => f['following_id'] as String).toList();
    if (ids.isEmpty) return [];

    final posts = await _db
        .from('posts')
        .select('*, profiles!posts_user_id_fkey(username, email, avatar_url)')
        .inFilter('user_id', ids)
        .order('created_at', ascending: false)
        .limit(50);

    return List<Map<String, dynamic>>.from(posts);
  }

  static Future<List<Map<String, dynamic>>> getUserPosts(String userId) async {
    final posts = await _db
        .from('posts')
        .select('*, profiles!posts_user_id_fkey(username, email, avatar_url)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(posts);
  }

  static Future<List<Map<String, dynamic>>> getDiscoverPosts() async {
    // Neueste öffentliche Posts von allen
    final posts = await _db
        .from('posts')
        .select('*, profiles!posts_user_id_fkey(username, email, avatar_url)')
        .order('created_at', ascending: false)
        .limit(30);

    return List<Map<String, dynamic>>.from(posts);
  }

  static Future<void> createPost(String content) async {
    final uid = _userId;
    if (uid == null) return;

    await _db.from('posts').insert({
      'user_id': uid,
      'content': content,
    });
  }

  static Future<void> deletePost(String postId) async {
    await _db.from('posts').delete().eq('id', postId);
  }

  // ── Likes ─────────────────────────────────────────────────────────────

  static Future<bool> toggleLike(String postId) async {
    final uid = _userId;
    if (uid == null) return false;

    final existing = await _db
        .from('post_likes')
        .select('id')
        .eq('post_id', postId)
        .eq('user_id', uid)
        .maybeSingle();

    if (existing != null) {
      await _db.from('post_likes').delete().eq('id', existing['id']);
      await _db.rpc('decrement_likes', params: {'post_id_param': postId});
      return false;
    } else {
      await _db.from('post_likes').insert({'post_id': postId, 'user_id': uid});
      await _db.rpc('increment_likes', params: {'post_id_param': postId});
      return true;
    }
  }

  static Future<bool> hasLiked(String postId) async {
    final uid = _userId;
    if (uid == null) return false;

    final existing = await _db
        .from('post_likes')
        .select('id')
        .eq('post_id', postId)
        .eq('user_id', uid)
        .maybeSingle();

    return existing != null;
  }

  // ── Follows ───────────────────────────────────────────────────────────

  static Future<void> followUser(String targetUserId) async {
    final uid = _userId;
    if (uid == null || uid == targetUserId) return;

    await _db.from('follows').upsert({
      'follower_id': uid,
      'following_id': targetUserId,
      'status': 'accepted',
    });

    // Notification erstellen
    try {
      await _db.from('notifications').insert({
        'user_id': targetUserId,
        'from_user_id': uid,
        'type': 'follow',
      });
    } catch (_) {}
  }

  static Future<void> unfollowUser(String targetUserId) async {
    final uid = _userId;
    if (uid == null) return;

    await _db
        .from('follows')
        .delete()
        .eq('follower_id', uid)
        .eq('following_id', targetUserId);
  }

  static Future<bool> isFollowing(String targetUserId) async {
    final uid = _userId;
    if (uid == null) return false;

    final result = await _db
        .from('follows')
        .select('id')
        .eq('follower_id', uid)
        .eq('following_id', targetUserId)
        .eq('status', 'accepted')
        .maybeSingle();

    return result != null;
  }

  static Future<int> getFollowerCount(String userId) async {
    final result = await _db
        .from('follows')
        .select('id')
        .eq('following_id', userId)
        .eq('status', 'accepted');
    return (result as List).length;
  }

  static Future<int> getFollowingCount(String userId) async {
    final result = await _db
        .from('follows')
        .select('id')
        .eq('follower_id', userId)
        .eq('status', 'accepted');
    return (result as List).length;
  }

  // ── User Search ───────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];

    final results = await _db
        .from('profiles')
        .select('id, username, email, avatar_url, bio')
        .or('username.ilike.%$query%,email.ilike.%$query%')
        .limit(20);

    return List<Map<String, dynamic>>.from(results);
  }

  // ── Groups ────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getMyGroups() async {
    final uid = _userId;
    if (uid == null) return [];

    final memberships = await _db
        .from('group_members')
        .select('group_id')
        .eq('user_id', uid);

    final groupIds = (memberships as List).map((m) => m['group_id'] as String).toList();
    if (groupIds.isEmpty) return [];

    final groups = await _db
        .from('groups')
        .select('*, group_members(count)')
        .inFilter('id', groupIds)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(groups);
  }

  static Future<List<Map<String, dynamic>>> getDiscoverGroups() async {
    final groups = await _db
        .from('groups')
        .select('*, group_members(count)')
        .order('created_at', ascending: false)
        .limit(20);

    return List<Map<String, dynamic>>.from(groups);
  }

  static Future<void> createGroup({
    required String name,
    String? routeName,
    String? stats,
    String? timeLocation,
    String? description,
  }) async {
    final uid = _userId;
    if (uid == null) return;

    final result = await _db.from('groups').insert({
      'created_by': uid,
      'name': name,
      'route_name': routeName,
      'stats': stats,
      'time_location': timeLocation,
      'description': description,
    }).select('id').single();

    // Creator automatisch als Mitglied
    await _db.from('group_members').insert({
      'group_id': result['id'],
      'user_id': uid,
    });
  }

  static Future<void> joinGroup(String groupId) async {
    final uid = _userId;
    if (uid == null) return;

    await _db.from('group_members').upsert({
      'group_id': groupId,
      'user_id': uid,
    });
  }

  static Future<void> leaveGroup(String groupId) async {
    final uid = _userId;
    if (uid == null) return;

    await _db
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', uid);
  }

  static Future<bool> isMember(String groupId) async {
    final uid = _userId;
    if (uid == null) return false;

    final result = await _db
        .from('group_members')
        .select('id')
        .eq('group_id', groupId)
        .eq('user_id', uid)
        .maybeSingle();

    return result != null;
  }

  // ── Notifications ─────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getNotifications() async {
    final uid = _userId;
    if (uid == null) return [];

    final results = await _db
        .from('notifications')
        .select('*, profiles!notifications_from_user_id_fkey(username, email, avatar_url)')
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(50);

    return List<Map<String, dynamic>>.from(results);
  }

  static Future<int> getUnreadCount() async {
    final uid = _userId;
    if (uid == null) return 0;

    final results = await _db
        .from('notifications')
        .select('id')
        .eq('user_id', uid)
        .eq('read', false);

    return (results as List).length;
  }

  static Future<void> markAllRead() async {
    final uid = _userId;
    if (uid == null) return;

    await _db
        .from('notifications')
        .update({'read': true})
        .eq('user_id', uid)
        .eq('read', false);
  }

  // ── Profile Stats ─────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getProfileStats(String userId) async {
    final followers = await getFollowerCount(userId);
    final following = await getFollowingCount(userId);

    final profile = await _db
        .from('profiles')
        .select('username, email, avatar_url, bio, created_at')
        .eq('id', userId)
        .maybeSingle();

    return {
      'follower_count': followers,
      'following_count': following,
      'username': profile?['username'],
      'email': profile?['email'],
      'avatar_url': profile?['avatar_url'],
      'bio': profile?['bio'],
      'created_at': profile?['created_at'],
    };
  }
}
