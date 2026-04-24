import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service für soziale Features: Posts, Follows, Gruppen, Notifications.
class SocialService {
  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _userId => _db.auth.currentUser?.id;

  /// Erkennt `@username`-Tokens in freiem Text. Zentrale Quelle, damit
  /// Service und UI dasselbe Pattern verwenden.
  static final RegExp _mentionPattern =
      RegExp(r'@([A-Za-z0-9_\.]+)');

  static Set<String> _extractMentions(String text) =>
      _mentionPattern
          .allMatches(text)
          .map((m) => m.group(1)!.toLowerCase())
          .toSet();

  // ── Posts ──────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getFeedPosts() async {
    final uid = _userId;
    if (uid == null) return [];

    try {
      final following = await getFollowingIds(uid);
      if (following.isEmpty) return [];

      // Mutual = Subset von following, die mir zurück folgen.
      // Nur dann darf ich `visibility='followers'`-Posts (= "Nur Follower")
      // sehen — sonst leakt Privates an einseitige Follower.
      final back = await _db
          .from('follows')
          .select('follower_id')
          .eq('following_id', uid)
          .eq('status', 'accepted')
          .inFilter('follower_id', following.toList());
      final mutual = (back as List)
          .map((r) => (r as Map)['follower_id'] as String)
          .toSet();

      const select =
          '*, profiles(id, username, email, avatar_url), shared_route_id';

      // Zwei disjunkte Queries (nach visibility) parallel — Filter auf
      // Query-Ebene verhindert, dass private Posts überhaupt ans Frontend
      // kommen, falls Mutual fehlt.
      final results = await Future.wait([
        _db
            .from('posts')
            .select(select)
            .inFilter('user_id', following.toList())
            .eq('visibility', 'public')
            .order('created_at', ascending: false)
            .limit(80),
        if (mutual.isNotEmpty)
          _db
              .from('posts')
              .select(select)
              .inFilter('user_id', mutual.toList())
              .eq('visibility', 'followers')
              .order('created_at', ascending: false)
              .limit(80),
      ]);

      final merged = <String, Map<String, dynamic>>{};
      for (final batch in results) {
        for (final row in batch as List) {
          final post = Map<String, dynamic>.from(row as Map);
          final id = post['id'] as String?;
          if (id != null) merged[id] = post;
        }
      }

      final list = merged.values.toList()
        ..sort((a, b) {
          final ad = DateTime.tryParse(a['created_at'] as String? ?? '');
          final bd = DateTime.tryParse(b['created_at'] as String? ?? '');
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return bd.compareTo(ad);
        });

      final capped = list.take(80).toList();
      debugPrint(
          '[Feed] uid=$uid following=${following.length} mutual=${mutual.length} → posts=${capped.length}');
      return capped;
    } catch (e) {
      debugPrint('[SocialService] getFeedPosts Fehler: $e');
      return [];
    }
  }

  /// IDs, denen der User folgt (status accepted).
  static Future<Set<String>> getFollowingIds(String uid) async {
    final rows = await _db
        .from('follows')
        .select('following_id')
        .eq('follower_id', uid)
        .eq('status', 'accepted');
    return (rows as List)
        .map((r) => (r as Map)['following_id'] as String)
        .toSet();
  }

  /// IDs mit gegenseitiger Folge (Kontakte).
  static Future<Set<String>> getMutualFollowIds(String uid) async {
    final following = await getFollowingIds(uid);
    if (following.isEmpty) return {};
    final back = await _db
        .from('follows')
        .select('follower_id')
        .eq('following_id', uid)
        .eq('status', 'accepted')
        .inFilter('follower_id', following.toList());
    return (back as List)
        .map((r) => (r as Map)['follower_id'] as String)
        .toSet();
  }

  static Future<bool> isMutualFollow(String otherUserId) async {
    final uid = _userId;
    if (uid == null) return false;
    final rows = await _db
        .from('follows')
        .select('follower_id, following_id')
        .or('and(follower_id.eq.$uid,following_id.eq.$otherUserId),and(follower_id.eq.$otherUserId,following_id.eq.$uid)')
        .eq('status', 'accepted');
    return (rows as List).length >= 2;
  }

  static Future<List<Map<String, dynamic>>> getUserPosts(String userId) async {
    try {
      final posts = await _db
          .from('posts')
          .select('*, profiles(id, username, email, avatar_url)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(posts);
    } catch (e) {
      debugPrint('[SocialService] getUserPosts Fehler: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getDiscoverPosts() async {
    try {
      final uid = _userId;
      final following = uid == null ? <String>{} : await getFollowingIds(uid);

      // Entdecken = öffentliche Posts von Usern, denen der aktuelle User
      // NICHT folgt (und nicht vom User selbst). Private Accounts sowieso raus.
      final posts = await _db
          .from('posts')
          .select('*, profiles(id, username, email, is_private), shared_route_id')
          .eq('visibility', 'public')
          .order('created_at', ascending: false)
          .limit(80);

      final filtered = (posts as List).where((p) {
        final authorId = p['user_id'] as String?;
        if (authorId == null) return false;
        if (authorId == uid) return false;
        if (following.contains(authorId)) return false;
        final profile = p['profiles'] as Map<String, dynamic>?;
        return profile?['is_private'] != true;
      }).toList();

      return List<Map<String, dynamic>>.from(filtered.take(30));
    } catch (e) {
      debugPrint('[SocialService] getDiscoverPosts Fehler: $e');
      return [];
    }
  }

  /// Legt einen Post an und gibt die neue Post-ID zurück (oder null bei
  /// fehlendem User / Fehler). Aufrufer kann die ID nutzen, um direkt
  /// Mention-Notifications zu verschicken.
  static Future<String?> createPost(
    String content, {
    String visibility = 'public',
    String? sharedRouteId,
  }) async {
    final uid = _userId;
    if (uid == null) return null;

    final row = <String, dynamic>{
      'user_id': uid,
      'content': content,
      'visibility': visibility,
    };
    if (sharedRouteId != null) row['shared_route_id'] = sharedRouteId;

    final result = await _db.from('posts').insert(row).select('id').single();
    final postId = (result as Map?)?['id'] as String?;

    // Mentions im Content auflösen — Anti-Spam: nur eigene Follower werden
    // tatsächlich benachrichtigt.
    if (postId != null) {
      final mentions = _extractMentions(content);
      if (mentions.isNotEmpty) {
        await sendMentionNotifications(
            postId: postId, usernames: mentions);
      }
    }
    return postId;
  }

  static Future<void> deletePost(String postId) async {
    await _db.from('posts').delete().eq('id', postId);
  }

  static Future<Map<String, dynamic>?> getPostById(String postId) async {
    try {
      final result = await _db
          .from('posts')
          .select('*, profiles(id, username, email, avatar_url), shared_route_id')
          .eq('id', postId)
          .maybeSingle();
      return result;
    } catch (e) {
      debugPrint('[SocialService] getPostById Fehler: $e');
      return null;
    }
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
        final post = await _db.from('posts').select('user_id').eq('id', postId).maybeSingle();
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
    final uid = _userId;
    final results = await _db
        .from('comments')
        .select('*, profiles!comments_user_id_profiles_fkey(id, username, email, avatar_url)')
        .eq('post_id', postId)
        .order('created_at', ascending: true);

    final list = List<Map<String, dynamic>>.from(results);
    if (uid == null || list.isEmpty) return list;

    // Welche Kommentare hat dieser User geliket?
    final ids = list.map((c) => c['id'] as String).toList();
    final likes = await _db
        .from('comment_likes')
        .select('comment_id')
        .eq('user_id', uid)
        .inFilter('comment_id', ids);
    final likedIds = {
      for (final row in likes as List) row['comment_id'] as String,
    };
    for (final c in list) {
      c['is_liked'] = likedIds.contains(c['id']);
    }
    return list;
  }

  static Future<void> addComment(
    String postId,
    String content, {
    String? parentCommentId,
  }) async {
    final uid = _userId;
    if (uid == null || content.trim().isEmpty) return;

    final row = <String, dynamic>{
      'post_id': postId,
      'user_id': uid,
      'content': content.trim(),
    };
    if (parentCommentId != null) {
      row['parent_comment_id'] = parentCommentId;
    }
    await _db.from('comments').insert(row);
    await _db.rpc('increment_comments', params: {'post_id_param': postId});

    // Notifications: Reply → an Parent-Autor; Top-Level → an Post-Autor.
    try {
      if (parentCommentId != null) {
        final parent = await _db
            .from('comments')
            .select('user_id')
            .eq('id', parentCommentId)
            .maybeSingle();
        final parentAuthor = parent?['user_id'] as String?;
        if (parentAuthor != null && parentAuthor != uid) {
          await _db.from('notifications').insert({
            'user_id': parentAuthor,
            'from_user_id': uid,
            'type': 'comment_reply',
            'reference_id': postId,
          });
        }
      } else {
        final post = await _db.from('posts').select('user_id').eq('id', postId).maybeSingle();
        final postAuthor = post?['user_id'] as String?;
        if (postAuthor != null && postAuthor != uid) {
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

    // Mention-Notifications für `@username`-Tokens im Kommentar.
    final mentions = _extractMentions(content.trim());
    if (mentions.isNotEmpty) {
      await sendMentionNotifications(postId: postId, usernames: mentions);
    }
  }

  static Future<void> deleteComment(String commentId, String postId) async {
    await _db.from('comments').delete().eq('id', commentId);
    await _db.rpc('decrement_comments', params: {'post_id_param': postId});
  }

  /// Liked einen Kommentar oder entfernt den Like (Toggle).
  /// Gibt den neuen Zustand zurück (true = jetzt geliked).
  static Future<bool> toggleCommentLike(String commentId) async {
    final uid = _userId;
    if (uid == null) return false;

    final existing = await _db
        .from('comment_likes')
        .select('id')
        .eq('comment_id', commentId)
        .eq('user_id', uid)
        .maybeSingle();

    if (existing != null) {
      await _db.from('comment_likes').delete().eq('id', existing['id']);
      await _db.rpc('decrement_comment_likes',
          params: {'comment_id_param': commentId});
      return false;
    }

    await _db.from('comment_likes').insert({
      'comment_id': commentId,
      'user_id': uid,
    });
    await _db.rpc('increment_comment_likes',
        params: {'comment_id_param': commentId});

    // Notification an Kommentar-Autor
    try {
      final comment = await _db
          .from('comments')
          .select('user_id, post_id')
          .eq('id', commentId)
          .maybeSingle();
      final commentAuthor = comment?['user_id'] as String?;
      if (commentAuthor != null && commentAuthor != uid) {
        await _db.from('notifications').insert({
          'user_id': commentAuthor,
          'from_user_id': uid,
          'type': 'comment_like',
          'reference_id': comment?['post_id'],
        });
      }
    } catch (e) {
      debugPrint('[Social] Comment-Like-Notification fehlgeschlagen: $e');
    }
    return true;
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
        final post = await _db.from('posts').select('user_id').eq('id', postId).maybeSingle();
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
  static Future<List<Map<String, dynamic>>> getUserReposts(String userId) async {
    final reposts = await _db
        .from('reposts')
        .select('*, posts(*, profiles(id, username, email, avatar_url))')
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

  /// Löst einen Username (Case-insensitive) zu einer User-ID auf.
  /// Gibt null zurück, falls kein Profil mit diesem Username existiert.
  static Future<String?> findUserIdByUsername(String username) async {
    final cleaned = username.trim();
    if (cleaned.isEmpty) return null;
    try {
      final row = await _db
          .from('profiles')
          .select('id')
          .ilike('username', cleaned)
          .maybeSingle();
      return (row as Map?)?['id'] as String?;
    } catch (e) {
      debugPrint('[SocialService] findUserIdByUsername Fehler: $e');
      return null;
    }
  }

  /// Profile meiner Follower — gefiltert nach Username-Prefix.
  /// Quelle für den Mention-Picker (Anti-Spam: man darf nur eigene Follower
  /// erwähnen).
  static Future<List<Map<String, dynamic>>> getMyFollowerProfiles({
    String prefix = '',
    int limit = 8,
  }) async {
    final uid = _userId;
    if (uid == null) return [];

    final rows = await _db
        .from('follows')
        .select(
            'follower_id, profiles!follows_follower_id_profiles_fkey(id, username, email, avatar_url)')
        .eq('following_id', uid)
        .eq('status', 'accepted');

    final profiles = <Map<String, dynamic>>[];
    final p = prefix.trim().toLowerCase();
    for (final row in rows as List) {
      final profile = (row as Map)['profiles'] as Map<String, dynamic>?;
      if (profile == null) continue;
      final username = (profile['username'] as String? ?? '').toLowerCase();
      if (username.isEmpty) continue;
      if (p.isNotEmpty && !username.startsWith(p)) continue;
      profiles.add(Map<String, dynamic>.from(profile));
      if (profiles.length >= limit) break;
    }
    return profiles;
  }

  /// Schickt für jeden gementionten User (`@username`) eine Notification.
  /// Anti-Spam: Es werden NUR Mentions akzeptiert, die zu eigenen Followern
  /// gehören; Self-Mentions werden ignoriert.
  /// Gibt die tatsächlich benachrichtigten User-IDs zurück.
  static Future<List<String>> sendMentionNotifications({
    required String postId,
    required Iterable<String> usernames,
  }) async {
    final uid = _userId;
    if (uid == null) return [];
    final cleaned = usernames
        .map((u) => u.trim().toLowerCase())
        .where((u) => u.isNotEmpty)
        .toSet();
    if (cleaned.isEmpty) return [];

    // Auflösen Username → user_id, beschränkt auf eigene Follower.
    final rows = await _db
        .from('follows')
        .select(
            'follower_id, profiles!follows_follower_id_profiles_fkey(id, username)')
        .eq('following_id', uid)
        .eq('status', 'accepted');

    final notified = <String>[];
    for (final row in rows as List) {
      final profile = (row as Map)['profiles'] as Map<String, dynamic>?;
      final username = (profile?['username'] as String? ?? '').toLowerCase();
      final targetId = profile?['id'] as String?;
      if (targetId == null || targetId == uid) continue;
      if (!cleaned.contains(username)) continue;
      try {
        await _db.from('notifications').insert({
          'user_id': targetId,
          'from_user_id': uid,
          'type': 'mention',
          'reference_id': postId,
        });
        notified.add(targetId);
      } catch (e) {
        debugPrint('[Social] Mention-Notification fehlgeschlagen: $e');
      }
    }
    return notified;
  }

  /// Liste der Follower (Personen, die diesem User folgen)
  static Future<List<Map<String, dynamic>>> getFollowers(String userId) async {
    final result = await _db
        .from('follows')
        .select('follower_id, profiles!follows_follower_id_profiles_fkey(id, username, email, avatar_url)')
        .eq('following_id', userId)
        .eq('status', 'accepted');
    return List<Map<String, dynamic>>.from(result);
  }

  /// Liste der Personen, denen dieser User folgt
  static Future<List<Map<String, dynamic>>> getFollowingList(String userId) async {
    final result = await _db
        .from('follows')
        .select('following_id, profiles!follows_following_id_profiles_fkey(id, username, email, avatar_url)')
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
        .select('id, username, email, avatar_url')
        .or('username.ilike.%$sanitized%,email.ilike.%$sanitized%')
        .limit(20);

    return List<Map<String, dynamic>>.from(results);
  }

  /// Nutzer-Vorschläge: Freunde-von-Freunden, fallback neueste Nutzer.
  /// Wird vom Entdecken-Tab genutzt wenn man (noch) niemandem folgt.
  static Future<List<Map<String, dynamic>>> getSuggestedUsers({
    int limit = 10,
  }) async {
    final uid = _userId;
    if (uid == null) return [];

    // IDs denen ich folge (sowie ich selbst) ausschließen
    final following = await _db
        .from('follows')
        .select('following_id')
        .eq('follower_id', uid)
        .eq('status', 'accepted');
    final excluded = <String>{
      uid,
      ...(following as List).map((r) => r['following_id'] as String),
    };

    // 1) Freunde-von-Freunden
    if (excluded.length > 1) {
      final myFollowingIds = excluded.where((id) => id != uid).toList();
      final fof = await _db
          .from('follows')
          .select('following_id, profiles!follows_following_id_profiles_fkey(id, username, email, avatar_url)')
          .inFilter('follower_id', myFollowingIds)
          .eq('status', 'accepted')
          .limit(50);

      final suggestions = <String, Map<String, dynamic>>{};
      for (final row in fof as List) {
        final p = (row as Map)['profiles'] as Map<String, dynamic>?;
        final id = p?['id'] as String?;
        if (p == null || id == null || excluded.contains(id)) continue;
        suggestions.putIfAbsent(id, () => p);
        if (suggestions.length >= limit) break;
      }
      if (suggestions.isNotEmpty) return suggestions.values.toList();
    }

    // 2) Fallback: neueste Profile (nicht-private)
    final recent = await _db
        .from('profiles')
        .select('id, username, email, avatar_url')
        .eq('is_private', false)
        .order('created_at', ascending: false)
        .limit(limit + excluded.length);
    return (recent as List)
        .whereType<Map<String, dynamic>>()
        .where((p) => !excluded.contains(p['id']))
        .take(limit)
        .toList();
  }

  // ── Groups ────────────────────────────────────────────────────────────

  /// Gruppen, in denen ich Mitglied/Owner bin.
  /// Nur öffentliche Gruppen — private werden in der Profil-Ansicht gezeigt.
  /// Sortiert chronologisch nach `start_time` (nächstes Event zuerst).
  static Future<List<Map<String, dynamic>>> getMyGroups({
    bool publicOnly = true,
  }) async {
    final uid = _userId;
    if (uid == null) return [];

    final memberships = await _db
        .from('group_members')
        .select('group_id')
        .eq('user_id', uid);

    final groupIds = <String>{
      ...(memberships as List).map((m) => m['group_id'] as String),
    };

    // Owner-Gruppen zusätzlich einsammeln — falls der Owner-Trigger
    // (set_owner_on_group_insert) mal nicht gegriffen hat.
    final ownGroups = await _db
        .from('groups')
        .select('id')
        .eq('created_by', uid);
    groupIds.addAll((ownGroups as List).map((g) => g['id'] as String));

    if (groupIds.isEmpty) return [];

    var q = _db
        .from('groups')
        .select('*, group_members(user_id)')
        .inFilter('id', groupIds.toList());
    if (publicOnly) q = q.eq('is_public', true);

    final groups = await q;
    final list = List<Map<String, dynamic>>.from(groups);
    _sortByStartTime(list);
    return list;
  }

  /// Alle Gruppen (public + private), in denen der User Mitglied oder Owner ist.
  /// Für die Profil-Ansicht.
  static Future<List<Map<String, dynamic>>> getMyAllGroups() async {
    return getMyGroups(publicOnly: false);
  }

  /// Private Gruppen des Users — für die Profil-Ansicht.
  static Future<List<Map<String, dynamic>>> getMyPrivateGroups() async {
    final uid = _userId;
    if (uid == null) return [];

    final memberships = await _db
        .from('group_members')
        .select('group_id')
        .eq('user_id', uid);
    final groupIds = <String>{
      ...(memberships as List).map((m) => m['group_id'] as String),
    };
    final ownGroups = await _db
        .from('groups')
        .select('id')
        .eq('created_by', uid);
    groupIds.addAll((ownGroups as List).map((g) => g['id'] as String));
    if (groupIds.isEmpty) return [];

    final groups = await _db
        .from('groups')
        .select('*, group_members(user_id)')
        .inFilter('id', groupIds.toList())
        .eq('is_public', false);
    final list = List<Map<String, dynamic>>.from(groups);
    _sortByStartTime(list);
    return list;
  }

  /// Öffentliche Gruppen, in denen der User weder Mitglied noch Owner ist.
  /// Sortiert nach `start_time` (nächstes Event zuerst).
  static Future<List<Map<String, dynamic>>> getDiscoverGroups() async {
    final uid = _userId;

    final groups = await _db
        .from('groups')
        .select('*, group_members(user_id), profiles:created_by(id, username, email)')
        .eq('is_public', true)
        .eq('is_active', false)
        .limit(80);

    final list = List<Map<String, dynamic>>.from(groups);
    if (uid == null) {
      _sortByStartTime(list);
      return list.take(40).toList();
    }

    // Ausfiltern: Gruppen in denen ich Mitglied ODER Owner bin.
    final filtered = list.where((g) {
      if (g['created_by'] == uid) return false;
      final members = (g['group_members'] as List?) ?? const [];
      return !members.any((m) => (m as Map)['user_id'] == uid);
    }).toList();

    _sortByStartTime(filtered);
    return filtered.take(40).toList();
  }

  /// Entfernt Gruppen, deren Route gestartet wurde und deren 24h-Fenster
  /// abgelaufen ist (Backup, falls pg_cron-Cleanup noch nicht gelaufen ist).
  static void _filterExpired(List<Map<String, dynamic>> list) {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    list.removeWhere((g) {
      final activated = DateTime.tryParse(g['activated_at'] as String? ?? '');
      return activated != null && activated.isBefore(cutoff);
    });
  }

  static void _sortByStartTime(List<Map<String, dynamic>> list) {
    _filterExpired(list);
    list.sort((a, b) {
      final aDt = DateTime.tryParse(a['start_time'] as String? ?? '');
      final bDt = DateTime.tryParse(b['start_time'] as String? ?? '');
      if (aDt == null && bDt == null) return 0;
      if (aDt == null) return 1;
      if (bDt == null) return -1;
      return aDt.compareTo(bDt);
    });
  }

  /// Nur der Owner darf löschen (RLS erzwingt das zusätzlich).
  static Future<void> deleteGroup(String groupId) async {
    await _db.from('groups').delete().eq('id', groupId);
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

  /// Prüft, ob der aktuelle User in der Gruppe die Rolle 'owner' hat.
  static Future<bool> isOwner(String groupId) async {
    final uid = _userId;
    if (uid == null) return false;
    final row = await _db
        .from('group_members')
        .select('role')
        .eq('group_id', groupId)
        .eq('user_id', uid)
        .maybeSingle();
    return (row as Map?)?['role'] == 'owner';
  }

  /// Zählt Owner der Gruppe, ohne den angegebenen User.
  /// Wird genutzt, um beim Verlassen zu entscheiden, ob die Gruppe
  /// gelöscht werden muss (nur wenn kein weiterer Owner übrig bleibt).
  static Future<int> countOtherOwners(String groupId, String excludeUid) async {
    final rows = await _db
        .from('group_members')
        .select('user_id')
        .eq('group_id', groupId)
        .eq('role', 'owner')
        .neq('user_id', excludeUid);
    return (rows as List).length;
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

  // ── Group Invite-Codes & Join-Requests ────────────────────────────────

  /// Normalisiert Codes wie 'cc7k9m2x' oder 'cc 7k9m2x' zu 'CC-7K9M2X'.
  static String? _normalizeInviteCode(String raw) {
    final cleaned = raw.trim().toUpperCase().replaceAll(RegExp(r'[\s\-_]'), '');
    if (cleaned.length < 3 || !cleaned.startsWith('CC')) return null;
    final body = cleaned.substring(2);
    if (body.length != 6) return null;
    if (!RegExp(r'^[A-Z2-9]{6}$').hasMatch(body)) return null;
    return 'CC-$body';
  }

  /// Sucht Gruppe per Invite-Code. Gibt null zurück, wenn Format/Code ungültig.
  static Future<Map<String, dynamic>?> findGroupByCode(String rawCode) async {
    final code = _normalizeInviteCode(rawCode);
    if (code == null) return null;
    try {
      final row = await _db
          .from('groups')
          .select('*, profiles:created_by(id, username, email)')
          .eq('invite_code', code)
          .maybeSingle();
      return row;
    } catch (e) {
      debugPrint('[SocialService] findGroupByCode Fehler: $e');
      return null;
    }
  }

  /// Join-Request für eine (private) Gruppe anlegen.
  /// Für öffentliche Gruppen sollte direkt joinGroup() genutzt werden.
  static Future<void> requestJoinGroup(String groupId, {String? message}) async {
    final uid = _userId;
    if (uid == null) return;
    await _db.from('group_join_requests').upsert({
      'group_id': groupId,
      'user_id': uid,
      'status': 'pending',
      'message': message,
    }, onConflict: 'group_id,user_id');
  }

  /// Prüft, ob der aktuelle User einen offenen (pending) Request hat.
  static Future<bool> hasPendingJoinRequest(String groupId) async {
    final uid = _userId;
    if (uid == null) return false;
    final row = await _db
        .from('group_join_requests')
        .select('status')
        .eq('group_id', groupId)
        .eq('user_id', uid)
        .eq('status', 'pending')
        .maybeSingle();
    return row != null;
  }

  /// Zieht einen offenen Join-Request zurück.
  static Future<void> cancelJoinRequest(String groupId) async {
    final uid = _userId;
    if (uid == null) return;
    await _db
        .from('group_join_requests')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', uid);
  }

  /// Listet alle offenen Join-Requests der Gruppe (Owner-Sicht).
  static Future<List<Map<String, dynamic>>> listPendingJoinRequests(
      String groupId) async {
    try {
      final rows = await _db
          .from('group_join_requests')
          .select('id, message, created_at, user_id, '
              'profiles:user_id(id, username, email, avatar_url)')
          .eq('group_id', groupId)
          .eq('status', 'pending')
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('[SocialService] listPendingJoinRequests Fehler: $e');
      return [];
    }
  }

  /// Owner akzeptiert einen Join-Request (atomar via RPC).
  static Future<void> acceptJoinRequest(String requestId) async {
    await _db.rpc('accept_group_join_request', params: {'req_id': requestId});
  }

  /// Owner lehnt einen Join-Request ab.
  static Future<void> rejectJoinRequest(String requestId) async {
    await _db.rpc('reject_group_join_request', params: {'req_id': requestId});
  }

  // ── Notifications ─────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getNotifications() async {
    final uid = _userId;
    if (uid == null) return [];

    final results = await _db
        .from('notifications')
        .select('*, profiles!notifications_from_user_id_profiles_fkey(id, username, email, avatar_url)')
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
          .select('id, username, email, created_at, level, total_km, total_routes, badges, bio, avatar_url')
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
      'email': profile?['email'],
      'avatar_url': profile?['avatar_url'],
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
