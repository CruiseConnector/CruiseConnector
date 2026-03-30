import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service für soziale Features: Posts, Follows, Gruppen, Notifications.
class SocialService {
  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _userId => _db.auth.currentUser?.id;

  static String publicDisplayName(
    Map<String, dynamic>? profile, {
    String? fallbackUserId,
  }) {
    final username = (profile?['username'] as String?)?.trim();
    if (username != null && username.isNotEmpty) return username;
    final shortId = _shortUserId(fallbackUserId);
    return shortId == null ? 'User' : 'Cruiser $shortId';
  }

  static String publicHandle(
    Map<String, dynamic>? profile, {
    String? fallbackUserId,
  }) {
    final username = (profile?['username'] as String?)?.trim();
    if (username != null && username.isNotEmpty) {
      final slug = username
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      return '@${slug.isEmpty ? 'user' : slug}';
    }
    final shortId = _shortUserId(fallbackUserId);
    return shortId == null ? '@user' : '@user_$shortId';
  }

  static String? _shortUserId(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    final sanitized = userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (sanitized.isEmpty) return null;
    return sanitized
        .substring(0, sanitized.length >= 6 ? 6 : sanitized.length)
        .toLowerCase();
  }

  // ── Posts ──────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getFeedPosts() async {
    final uid = _userId;
    if (uid == null) return [];

    try {
      // IDs der Leute denen man folgt
      final followingIds = await _db
          .from('follows')
          .select('following_id')
          .eq('follower_id', uid)
          .eq('status', 'accepted');

      final ids = (followingIds as List)
          .map((f) => f['following_id'] as String)
          .toList();
      // Eigene ID hinzufügen damit eigene Posts auch im Feed erscheinen
      ids.add(uid);

      final posts = await _db
          .from('posts')
          .select('*, profiles(id, username), shared_route_id')
          .inFilter('user_id', ids)
          .order('created_at', ascending: false)
          .limit(50);

      return List<Map<String, dynamic>>.from(posts);
    } catch (e) {
      debugPrint('[SocialService] getFeedPosts Fehler: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getUserPosts(String userId) async {
    try {
      final viewerId = _userId;
      final canSeeFollowersPosts =
          viewerId == userId || (viewerId != null && await isFollowing(userId));

      var query = _db
          .from('posts')
          .select('*, profiles(id, username), shared_route_id')
          .eq('user_id', userId);

      if (viewerId != userId) {
        query = canSeeFollowersPosts
            ? query.inFilter('visibility', ['public', 'followers'])
            : query.eq('visibility', 'public');
      }

      final posts = await query.order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(posts);
    } catch (e) {
      debugPrint('[SocialService] getUserPosts Fehler: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getDiscoverPosts() async {
    try {
      final uid = _userId;
      // Entdecken zeigt öffentliche Posts plus die eigenen Posts des Nutzers,
      // damit Profil- und Community-Ansicht konsistent bleiben.
      final posts = await _db
          .from('posts')
          .select('*, profiles(id, username, is_private), shared_route_id')
          .order('created_at', ascending: false)
          .limit(80);

      // Private Accounts und follower-only Posts clientseitig filtern.
      final filtered = (posts as List).where((p) {
        final profile = p['profiles'] as Map<String, dynamic>?;
        final isOwnPost = uid != null && p['user_id'] == uid;
        final visibility = (p['visibility'] as String?) ?? 'public';
        if (!isOwnPost && visibility != 'public') return false;
        if (!isOwnPost && profile?['is_private'] == true) return false;
        return true;
      }).toList();

      return List<Map<String, dynamic>>.from(filtered.take(30));
    } catch (e) {
      debugPrint('[SocialService] getDiscoverPosts Fehler: $e');
      return [];
    }
  }

  static Future<void> createPost(
    String content, {
    String visibility = 'public',
    String? sharedRouteId,
  }) async {
    final uid = _userId;
    if (uid == null) return;

    final row = <String, dynamic>{
      'user_id': uid,
      'content': content,
      'visibility': visibility,
    };
    if (sharedRouteId != null) row['shared_route_id'] = sharedRouteId;

    await _db.from('posts').insert(row);
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

      // Notification an Post-Autor
      try {
        final post = await _db
            .from('posts')
            .select('user_id')
            .eq('id', postId)
            .maybeSingle();
        if (post != null) {
          final postAuthor = post['user_id'] as String;
          if (postAuthor != uid) {
            await _db.from('notifications').insert({
              'user_id': postAuthor,
              'from_user_id': uid,
              'type': 'like',
              'reference_id': postId,
            });
          }
        }
      } catch (e) {
        debugPrint('[Social] Like-Notification fehlgeschlagen: $e');
      }
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

  // ── Comments ─────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getComments(String postId) async {
    final results = await _db
        .from('comments')
        .select('*, profiles!comments_user_id_profiles_fkey(id, username)')
        .eq('post_id', postId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(results);
  }

  static Future<void> addComment(String postId, String content) async {
    final uid = _userId;
    if (uid == null || content.trim().isEmpty) return;

    await _db.from('comments').insert({
      'post_id': postId,
      'user_id': uid,
      'content': content.trim(),
    });
    await _db.rpc('increment_comments', params: {'post_id_param': postId});

    // Notification an Post-Autor
    try {
      final post = await _db
          .from('posts')
          .select('user_id')
          .eq('id', postId)
          .maybeSingle();
      if (post != null) {
        final postAuthor = post['user_id'] as String;
        if (postAuthor != uid) {
          await _db.from('notifications').insert({
            'user_id': postAuthor,
            'from_user_id': uid,
            'type': 'comment',
            'reference_id': postId,
          });
        }
      }
    } catch (e) {
      debugPrint('[Social] Comment-Notification fehlgeschlagen: $e');
    }
  }

  static Future<void> deleteComment(String commentId, String postId) async {
    await _db.from('comments').delete().eq('id', commentId);
    await _db.rpc('decrement_comments', params: {'post_id_param': postId});
  }

  // ── Reposts ─────────────────────────────────────────────────────────

  static Future<bool> toggleRepost(String postId) async {
    final uid = _userId;
    if (uid == null) return false;

    final existing = await _db
        .from('reposts')
        .select('id')
        .eq('post_id', postId)
        .eq('user_id', uid)
        .maybeSingle();

    if (existing != null) {
      await _db.from('reposts').delete().eq('id', existing['id']);
      await _db.rpc('decrement_reposts', params: {'post_id_param': postId});
      return false;
    } else {
      await _db.from('reposts').insert({'post_id': postId, 'user_id': uid});
      await _db.rpc('increment_reposts', params: {'post_id_param': postId});

      // Notification an Post-Autor
      try {
        final post = await _db
            .from('posts')
            .select('user_id')
            .eq('id', postId)
            .maybeSingle();
        if (post != null) {
          final postAuthor = post['user_id'] as String;
          if (postAuthor != uid) {
            await _db.from('notifications').insert({
              'user_id': postAuthor,
              'from_user_id': uid,
              'type': 'repost',
              'reference_id': postId,
            });
          }
        }
      } catch (e) {
        debugPrint('[Social] Repost-Notification fehlgeschlagen: $e');
      }
      return true;
    }
  }

  static Future<bool> hasReposted(String postId) async {
    final uid = _userId;
    if (uid == null) return false;

    final existing = await _db
        .from('reposts')
        .select('id')
        .eq('post_id', postId)
        .eq('user_id', uid)
        .maybeSingle();

    return existing != null;
  }

  /// Alle Reposts eines Users (für Profil-Seite)
  static Future<List<Map<String, dynamic>>> getUserReposts(
    String userId,
  ) async {
    final reposts = await _db
        .from('reposts')
        .select('*, posts(*, profiles(id, username))')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(reposts);
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
    } catch (e) {
      debugPrint('[Social] Follow-Notification fehlgeschlagen: $e');
    }
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

  /// Liste der Follower (Personen, die diesem User folgen)
  static Future<List<Map<String, dynamic>>> getFollowers(String userId) async {
    final result = await _db
        .from('follows')
        .select(
          'follower_id, profiles!follows_follower_id_profiles_fkey(id, username)',
        )
        .eq('following_id', userId)
        .eq('status', 'accepted');
    return List<Map<String, dynamic>>.from(result);
  }

  /// Liste der Personen, denen dieser User folgt
  static Future<List<Map<String, dynamic>>> getFollowingList(
    String userId,
  ) async {
    final result = await _db
        .from('follows')
        .select(
          'following_id, profiles!follows_following_id_profiles_fkey(id, username)',
        )
        .eq('follower_id', userId)
        .eq('status', 'accepted');
    return List<Map<String, dynamic>>.from(result);
  }

  // ── User Search ───────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final sanitized = query.trim().replaceAll(RegExp(r'[%_\\,\.\(\)]'), '');
    if (sanitized.isEmpty) return [];

    final results = await _db
        .from('profiles')
        .select('id, username')
        .ilike('username', '%$sanitized%')
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

    final groupIds = (memberships as List)
        .map((m) => m['group_id'] as String)
        .toList();
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

    final result = await _db
        .from('groups')
        .insert({
          'created_by': uid,
          'name': name,
          'route_name': routeName,
          'stats': stats,
          'time_location': timeLocation,
          'description': description,
        })
        .select('id')
        .single();

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
        .select(
          '*, profiles!notifications_from_user_id_profiles_fkey(id, username)',
        )
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

  // ── Profile ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final profile = await _db
          .from('profiles')
          .select(
            'id, username, created_at, level, total_km, total_routes, badges, bio, avatar_url, is_private',
          )
          .eq('id', userId)
          .maybeSingle();
      return profile;
    } catch (e) {
      debugPrint('[Social] Profil-Abfrage fehlgeschlagen: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> getProfileStats(String userId) async {
    final followers = await getFollowerCount(userId);
    final following = await getFollowingCount(userId);

    final profile = await getUserProfile(userId);

    return {
      'follower_count': followers,
      'following_count': following,
      'username': profile?['username'],
      'created_at': profile?['created_at'],
      'level': profile?['level'] ?? 1,
      'total_km': profile?['total_km'] ?? 0,
      'total_routes': profile?['total_routes'] ?? 0,
      'badges': profile?['badges'] ?? [],
      'is_private': profile?['is_private'] ?? false,
    };
  }

  // ── Group Invites ───────────────────────────────────────────────────

  static Future<void> inviteToGroup(String groupId, String targetUserId) async {
    final uid = _userId;
    if (uid == null) return;

    await _db.from('notifications').insert({
      'user_id': targetUserId,
      'from_user_id': uid,
      'type': 'group_invite',
      'reference_id': groupId,
    });
  }
}
