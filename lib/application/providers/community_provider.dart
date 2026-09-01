import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cruise_connect/data/services/social_service.dart';

/// Zentraler State für Community-Posts, Likes, Reposts und Following.
/// Feed, Entdecken und Profil teilen sich diesen State — keine doppelten
/// Counter mehr, egal auf welcher Seite geliked/reposted wird.
///
/// Follow/Unfollow updaten den lokalen State optimistisch, sodass Posts
/// ohne App-Neustart aus dem Feed verschwinden bzw. im Entdecken-Tab
/// erscheinen, wenn der Account öffentlich ist.
class CommunityProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _feedPosts = [];
  List<Map<String, dynamic>> _discoverPosts = [];
  Set<String> _followingIds = {};
  final Map<String, String> _followStatuses = {};
  final Set<String> _knownFollowStatuses = {};
  final Map<String, Map<String, dynamic>> _profileCache = {};
  RealtimeChannel? _myFollowingChannel;
  RealtimeChannel? _myFollowersChannel;
  RealtimeChannel? _myProfileChannel;
  String? _realtimeUserId;

  /// IDs aller User, die ich blockiert habe ODER die mich blockiert haben —
  /// werden überall aus Listen herausgefiltert.
  Set<String> _blockedIds = {};
  bool _isLoading = false;
  String? _errorMessage;

  // Like-State: postId → isLiked / count
  final Map<String, bool> _likedPosts = {};
  final Map<String, int> _likeCounts = {};
  // Repost-State: postId → isReposted / count
  final Map<String, bool> _repostedPosts = {};
  final Map<String, int> _repostCounts = {};
  // Hält fest, ob für einen Post schon einmal is_liked/is_reposted vom Server
  // geprüft wurde (damit wir das nicht bei jedem Build neu triggern).
  final Set<String> _checkedLike = {};
  final Set<String> _checkedRepost = {};
  // In-flight Toggles, um Doppel-Taps zu ignorieren.
  final Set<String> _busyLike = {};
  final Set<String> _busyRepost = {};
  // In-flight Follows pro Ziel-User, gegen Doppel-Taps.
  final Set<String> _busyFollow = {};

  List<Map<String, dynamic>> get feedPosts => List.unmodifiable(_feedPosts);
  List<Map<String, dynamic>> get discoverPosts =>
      List.unmodifiable(_discoverPosts);
  Set<String> get followingIds => Set.unmodifiable(_followingIds);
  int get followingCount => _followingIds.length;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool isLiked(String postId) => _likedPosts[postId] ?? false;
  int likeCount(String postId) => _likeCounts[postId] ?? 0;
  bool isReposted(String postId) => _repostedPosts[postId] ?? false;
  int repostCount(String postId) => _repostCounts[postId] ?? 0;
  bool isFollowing(String userId) => followStatus(userId) == 'accepted';
  bool isPendingFollow(String userId) => followStatus(userId) == 'pending';
  bool hasKnownFollowStatus(String userId) =>
      _knownFollowStatuses.contains(userId) || _followingIds.contains(userId);

  String followStatus(String userId, {String fallback = 'none'}) {
    final status = _followStatuses[userId];
    if (status != null) return status;
    return _followingIds.contains(userId) ? 'accepted' : fallback;
  }

  Map<String, dynamic>? cachedProfile(String userId) {
    final cached = _profileCache[userId];
    return cached == null ? null : Map.unmodifiable(cached);
  }

  Map<String, dynamic> mergedProfile(String userId, Map<String, dynamic> base) {
    final cached = _profileCache[userId];
    if (cached == null) return Map<String, dynamic>.from(base);
    return {...base, ...cached};
  }

  void seedFollowStatus(String userId, String? status, {bool notify = false}) {
    if (_applyFollowStatus(userId, status ?? 'none') && notify) {
      notifyListeners();
    }
  }

  void seedProfiles(Iterable<Map<String, dynamic>> profiles) {
    var changed = false;
    for (final profile in profiles) {
      changed = _seedProfile(profile) || changed;
    }
    if (changed) notifyListeners();
  }

  void seedProfile(Map<String, dynamic>? profile, {bool notify = false}) {
    if (profile == null) return;
    if (_seedProfile(profile) && notify) notifyListeners();
  }

  void applyProfilePatch(
    String userId,
    Map<String, dynamic> patch, {
    bool notify = true,
  }) {
    if (userId.isEmpty || patch.isEmpty) return;
    final next = {...?_profileCache[userId], 'id': userId, ...patch};
    _profileCache[userId] = next;
    if (notify) notifyListeners();
  }

  Future<String> ensureFollowStatus(String userId) async {
    if (hasKnownFollowStatus(userId)) return followStatus(userId);
    try {
      final status = await SocialService.getFollowStatus(userId);
      seedFollowStatus(userId, status, notify: true);
      return status;
    } catch (e) {
      debugPrint('[CommunityProvider] ensureFollowStatus Fehler: $e');
      return 'none';
    }
  }

  bool _seedProfile(Map<String, dynamic> profile) {
    final id = profile['id'] as String?;
    if (id == null || id.isEmpty) return false;
    final next = {...?_profileCache[id], ...Map<String, dynamic>.from(profile)};
    final changed = _profileCache[id].toString() != next.toString();
    _profileCache[id] = next;
    return changed;
  }

  bool _applyFollowStatus(String userId, String status) {
    final normalized = switch (status) {
      'accepted' => 'accepted',
      'pending' => 'pending',
      _ => 'none',
    };
    final previous = followStatus(userId);
    _knownFollowStatuses.add(userId);
    _followStatuses[userId] = normalized;
    if (normalized == 'accepted') {
      _followingIds = {..._followingIds, userId};
    } else {
      _followingIds = {..._followingIds}..remove(userId);
    }
    return previous != normalized;
  }

  bool _applyFollowStatusWithFollowerCount(String userId, String status) {
    final previousAccepted = followStatus(userId) == 'accepted';
    final changed = _applyFollowStatus(userId, status);
    final nextAccepted = followStatus(userId) == 'accepted';
    if (previousAccepted != nextAccepted) {
      _bumpCachedProfileCount(
        userId,
        'follower_count',
        nextAccepted ? 1 : -1,
        notify: false,
      );
    }
    return changed;
  }

  void _bumpCachedProfileCount(
    String userId,
    String field,
    int delta, {
    bool notify = true,
  }) {
    if (delta == 0) return;
    final current = (_profileCache[userId]?[field] as num?)?.toInt();
    if (current == null) return;
    applyProfilePatch(userId, {
      field: (current + delta).clamp(0, 1 << 31),
    }, notify: notify);
  }

  void startRealtime() {
    final db = Supabase.instance.client;
    final uid = db.auth.currentUser?.id;
    if (uid == null) {
      stopRealtime();
      return;
    }
    if (_realtimeUserId == uid &&
        _myFollowingChannel != null &&
        _myFollowersChannel != null &&
        _myProfileChannel != null) {
      return;
    }

    stopRealtime();
    _realtimeUserId = uid;

    _myFollowingChannel = db
        .channel('cc:my_following:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'follows',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'follower_id',
            value: uid,
          ),
          callback: _handleMyFollowingChange,
        )
        .subscribe();

    _myFollowersChannel = db
        .channel('cc:my_followers:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'follows',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'following_id',
            value: uid,
          ),
          callback: _handleMyFollowerChange,
        )
        .subscribe();

    _myProfileChannel = db
        .channel('cc:my_profile:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: uid,
          ),
          callback: (payload) {
            if (payload.newRecord.isEmpty) return;
            seedProfile(payload.newRecord, notify: true);
          },
        )
        .subscribe();
  }

  void stopRealtime() {
    _myFollowingChannel?.unsubscribe();
    _myFollowersChannel?.unsubscribe();
    _myProfileChannel?.unsubscribe();
    _myFollowingChannel = null;
    _myFollowersChannel = null;
    _myProfileChannel = null;
    _realtimeUserId = null;
  }

  void _handleMyFollowingChange(PostgresChangePayload payload) {
    final row = payload.newRecord.isNotEmpty
        ? payload.newRecord
        : payload.oldRecord;
    final targetUserId = row['following_id'] as String?;
    if (targetUserId == null) return;

    final oldAccepted = payload.oldRecord['status'] == 'accepted';
    final nextStatus = payload.eventType == PostgresChangeEvent.delete
        ? 'none'
        : (row['status'] as String? ?? 'none');
    final changed = _applyFollowStatus(targetUserId, nextStatus);
    final newAccepted = nextStatus == 'accepted';
    if (oldAccepted != newAccepted && _realtimeUserId != null) {
      _bumpCachedProfileCount(
        _realtimeUserId!,
        'following_count',
        newAccepted ? 1 : -1,
      );
    }
    if (changed) {
      notifyListeners();
      if (newAccepted) {
        _refreshFeedSilently();
      } else {
        _refreshDiscoverSilently();
      }
    }
  }

  void _handleMyFollowerChange(PostgresChangePayload payload) {
    final uid = _realtimeUserId;
    if (uid == null) return;
    final oldAccepted = payload.oldRecord['status'] == 'accepted';
    final newAccepted =
        payload.eventType != PostgresChangeEvent.delete &&
        payload.newRecord['status'] == 'accepted';
    if (oldAccepted == newAccepted) return;
    _bumpCachedProfileCount(uid, 'follower_count', newAccepted ? 1 : -1);
    notifyListeners();
  }

  /// Ruft jede Seite (Feed, Entdecken, Profil) auf, bevor sie Posts rendert.
  /// Seedet den zentralen State mit Serverwerten, solange kein Toggle läuft.
  void registerPost(Map<String, dynamic> post) {
    final id = post['id'] as String?;
    if (id == null) return;
    final serverLikeCount = (post['likes_count'] as num?)?.toInt();
    if (serverLikeCount != null && !_busyLike.contains(id)) {
      _likeCounts[id] = serverLikeCount < 0 ? 0 : serverLikeCount;
    } else {
      _likeCounts.putIfAbsent(id, () => 0);
    }

    final serverRepostCount = (post['reposts_count'] as num?)?.toInt();
    if (serverRepostCount != null && !_busyRepost.contains(id)) {
      _repostCounts[id] = serverRepostCount < 0 ? 0 : serverRepostCount;
    } else {
      _repostCounts.putIfAbsent(id, () => 0);
    }

    final liked = post['is_liked_by_me'];
    if (liked is bool && !_busyLike.contains(id)) {
      _likedPosts[id] = liked;
      _checkedLike.add(id);
    }
    final reposted = post['is_reposted_by_me'];
    if (reposted is bool && !_busyRepost.contains(id)) {
      _repostedPosts[id] = reposted;
      _checkedRepost.add(id);
    }
  }

  /// Für Posts, bei denen der Server-Wert `is_liked_by_me` nicht mitgeliefert
  /// wurde — einmalig per Request nachladen.
  // 2026-09-01 (Serverlast): Diese beiden Methoden stellten je eine Anfrage
  // PRO KNOPF. Solange die Knoepfe nur im Feed sassen, fiel das nicht auf;
  // seit sie auch auf fremden Profilen und auf der Beitragsseite stehen,
  // loeste ein Profil mit zwanzig Beitraegen bis zu vierzig zusaetzliche
  // Rundreisen aus — alle im selben Moment, weil alle Knoepfe gleichzeitig
  // aufgebaut werden.
  //
  // Jetzt sammeln sie erst. Alles, was im selben Aufbau-Takt anfaellt, geht
  // als EINE Abfrage mit in-Filter raus. Aus vierzig Rundreisen werden zwei.
  final Set<String> _offeneLikePruefungen = {};
  final Set<String> _offeneRepostPruefungen = {};
  bool _likeSammlungGeplant = false;
  bool _repostSammlungGeplant = false;

  Future<void> ensureLikedChecked(String postId) async {
    if (_checkedLike.contains(postId)) return;
    _checkedLike.add(postId);
    _offeneLikePruefungen.add(postId);
    if (_likeSammlungGeplant) return;
    _likeSammlungGeplant = true;
    // Ein Takt warten, damit alle Knoepfe desselben Aufbaus mitkommen.
    scheduleMicrotask(() async {
      await Future<void>.delayed(Duration.zero);
      _likeSammlungGeplant = false;
      final stapel = _offeneLikePruefungen.toSet();
      _offeneLikePruefungen.clear();
      if (stapel.isEmpty) return;
      try {
        final geliked = await SocialService.likedAmong(stapel);
        for (final id in stapel) {
          _likedPosts[id] = geliked.contains(id);
        }
        notifyListeners();
      } catch (_) {
        // Nicht als geprueft merken, sonst bleibt der Knopf fuer den Rest der
        // Sitzung auf dem falschen Stand.
        _checkedLike.removeAll(stapel);
      }
    });
  }

  Future<void> ensureRepostedChecked(String postId) async {
    if (_checkedRepost.contains(postId)) return;
    _checkedRepost.add(postId);
    _offeneRepostPruefungen.add(postId);
    if (_repostSammlungGeplant) return;
    _repostSammlungGeplant = true;
    scheduleMicrotask(() async {
      await Future<void>.delayed(Duration.zero);
      _repostSammlungGeplant = false;
      final stapel = _offeneRepostPruefungen.toSet();
      _offeneRepostPruefungen.clear();
      if (stapel.isEmpty) return;
      try {
        final geteilt = await SocialService.repostedAmong(stapel);
        for (final id in stapel) {
          _repostedPosts[id] = geteilt.contains(id);
        }
        notifyListeners();
      } catch (_) {
        _checkedRepost.removeAll(stapel);
      }
    });
  }

  /// Lädt Feed, Discover und Following-IDs in einem Rutsch.
  /// Wird von community_page beim Öffnen / Pull-to-Refresh aufgerufen.
  Future<void> loadAll() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final results = await Future.wait([
        SocialService.getFeedPosts(),
        SocialService.getDiscoverPosts(),
        if (uid != null)
          SocialService.getFollowingIds(uid)
        else
          Future.value(<String>{}),
        SocialService.getBlockedAndBlockerIds(),
      ]);
      _feedPosts = results[0] as List<Map<String, dynamic>>;
      _discoverPosts = results[1] as List<Map<String, dynamic>>;
      final freshFollowingIds = results[2] as Set<String>;
      final previouslyAccepted = _followStatuses.entries
          .where((entry) => entry.value == 'accepted')
          .map((entry) => entry.key)
          .toSet();
      _followingIds = freshFollowingIds;
      for (final id in freshFollowingIds) {
        _followStatuses[id] = 'accepted';
        _knownFollowStatuses.add(id);
      }
      for (final id in previouslyAccepted.difference(freshFollowingIds)) {
        _followStatuses[id] = 'none';
        _knownFollowStatuses.add(id);
      }
      _blockedIds = results[3] as Set<String>;
      for (final post in _feedPosts) {
        registerPost(post);
        seedProfile(post['profiles'] as Map<String, dynamic>?);
      }
      for (final post in _discoverPosts) {
        registerPost(post);
        seedProfile(post['profiles'] as Map<String, dynamic>?);
      }
    } catch (e) {
      _errorMessage = 'Feed konnte nicht geladen werden.';
      debugPrint('[CommunityProvider] loadAll Fehler: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Veraltet: Behalten für Aufrufer, die nur den Feed wollten.
  /// Delegiert auf [loadAll], weil Feed/Discover/Following zusammenhängen.
  Future<void> loadFeed() => loadAll();

  /// Folgt einem User. Bei privaten Konten wird intern eine Pending-Anfrage
  /// erzeugt — der lokale `_followingIds`-State wird in dem Fall NICHT
  /// erweitert (weil noch nicht akzeptiert). Returns: 'accepted' | 'pending'
  /// | 'none'.
  Future<String> followUser(
    String targetUserId, {
    bool? targetIsPrivate,
  }) async {
    if (_blockedIds.contains(targetUserId)) return 'none';
    if (_busyFollow.contains(targetUserId)) return followStatus(targetUserId);
    _busyFollow.add(targetUserId);

    final currentStatus = followStatus(targetUserId);
    if (currentStatus == 'accepted' || currentStatus == 'pending') {
      _busyFollow.remove(targetUserId);
      return currentStatus;
    }

    final optimisticStatus =
        (targetIsPrivate ?? _profileCache[targetUserId]?['is_private'] == true)
        ? 'pending'
        : 'accepted';

    // Optimistisch: Button sofort umschalten und Discover ggf. entfernen.
    final removedFromDiscover = _discoverPosts
        .where((p) => p['user_id'] == targetUserId)
        .toList();
    _discoverPosts = _discoverPosts
        .where((p) => p['user_id'] != targetUserId)
        .toList();
    _applyFollowStatusWithFollowerCount(targetUserId, optimisticStatus);
    notifyListeners();

    try {
      final status = await SocialService.followUser(targetUserId);
      _applyFollowStatusWithFollowerCount(targetUserId, status);
      if (status == 'accepted') {
        notifyListeners();
        _refreshFeedSilently();
      } else if (status == 'pending') {
        // Bei Pending wieder in Discover zurück, weil noch nicht echtes Following.
        _discoverPosts = [..._discoverPosts, ...removedFromDiscover];
        notifyListeners();
      } else {
        _discoverPosts = [..._discoverPosts, ...removedFromDiscover];
        notifyListeners();
      }
      return status;
    } catch (e) {
      _discoverPosts = [..._discoverPosts, ...removedFromDiscover];
      _applyFollowStatusWithFollowerCount(targetUserId, currentStatus);
      debugPrint('[CommunityProvider] followUser Fehler: $e');
      notifyListeners();
      return 'none';
    } finally {
      _busyFollow.remove(targetUserId);
    }
  }

  /// Wird vom Notifications-Sheet / FollowRequests-Page aufgerufen, wenn
  /// der Inhaber eine Anfrage akzeptiert — der Anfragende wird als Follower
  /// (nicht in `_followingIds`, da andere Richtung). State-Effekt nur
  /// indirekt über Refresh.
  Future<void> acceptFollowRequest(String fromUserId) async {
    try {
      await SocialService.acceptFollowRequest(fromUserId);
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        _bumpCachedProfileCount(uid, 'follower_count', 1);
        notifyListeners();
      }
      // Falls ich dem User auch folge, könnte sich Mutual ändern —
      // einfacher Refresh des Feeds reicht.
      _refreshFeedSilently();
    } catch (e) {
      debugPrint('[CommunityProvider] acceptFollowRequest Fehler: $e');
      rethrow;
    }
  }

  Future<void> rejectFollowRequest(String fromUserId) async {
    try {
      await SocialService.rejectFollowRequest(fromUserId);
    } catch (e) {
      debugPrint('[CommunityProvider] rejectFollowRequest Fehler: $e');
      rethrow;
    }
  }

  // ── Blocking ───────────────────────────────────────────────────────────

  Set<String> get blockedIds => Set.unmodifiable(_blockedIds);
  bool isBlocked(String userId) => _blockedIds.contains(userId);

  /// Blockt einen User: serverseitig via RPC (löscht Follows in beide
  /// Richtungen automatisch); lokal werden Posts des Users sofort aus
  /// Feed + Discover entfernt, und der User aus `_followingIds` raus.
  Future<void> blockUser(String targetUserId) async {
    final wasFollowing = _followingIds.contains(targetUserId);
    final removedFromFeed = _feedPosts
        .where((p) => p['user_id'] == targetUserId)
        .toList();
    final removedFromDiscover = _discoverPosts
        .where((p) => p['user_id'] == targetUserId)
        .toList();

    _blockedIds = {..._blockedIds, targetUserId};
    _feedPosts = _feedPosts.where((p) => p['user_id'] != targetUserId).toList();
    _discoverPosts = _discoverPosts
        .where((p) => p['user_id'] != targetUserId)
        .toList();
    seedFollowStatus(targetUserId, 'none');
    notifyListeners();

    try {
      await SocialService.blockUser(targetUserId);
    } catch (e) {
      // Rollback bei Fehler.
      _blockedIds = {..._blockedIds}..remove(targetUserId);
      _feedPosts = [..._feedPosts, ...removedFromFeed];
      _discoverPosts = [..._discoverPosts, ...removedFromDiscover];
      if (wasFollowing) {
        seedFollowStatus(targetUserId, 'accepted');
      }
      debugPrint('[CommunityProvider] blockUser Fehler: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> unblockUser(String targetUserId) async {
    final wasBlocked = _blockedIds.contains(targetUserId);
    _blockedIds = {..._blockedIds}..remove(targetUserId);
    notifyListeners();

    try {
      await SocialService.unblockUser(targetUserId);
      // Discover neu laden — Posts des entblockten Users könnten wieder
      // sichtbar werden.
      _refreshDiscoverSilently();
    } catch (e) {
      if (wasBlocked) _blockedIds = {..._blockedIds, targetUserId};
      debugPrint('[CommunityProvider] unblockUser Fehler: $e');
      notifyListeners();
      rethrow;
    }
  }

  /// Entfolgt einem User und filtert dessen Posts sofort aus dem Feed.
  /// Im Hintergrund wird Discover neu geladen, damit die Posts dort
  /// auftauchen, falls das Profil öffentlich ist.
  Future<void> unfollowUser(String targetUserId) async {
    if (_busyFollow.contains(targetUserId)) return;
    _busyFollow.add(targetUserId);

    final previousStatus = followStatus(targetUserId);
    final wasFollowing = previousStatus == 'accepted';
    if (!wasFollowing) {
      seedFollowStatus(targetUserId, 'none', notify: true);
      try {
        await SocialService.unfollowUser(targetUserId);
        _refreshDiscoverSilently();
      } catch (e) {
        seedFollowStatus(targetUserId, previousStatus, notify: true);
        debugPrint('[CommunityProvider] pending unfollow Fehler: $e');
      } finally {
        _busyFollow.remove(targetUserId);
      }
      return;
    }

    final removedFromFeed = _feedPosts
        .where((p) => p['user_id'] == targetUserId)
        .toList();
    _feedPosts = _feedPosts.where((p) => p['user_id'] != targetUserId).toList();
    seedFollowStatus(targetUserId, 'none');
    notifyListeners();

    try {
      await SocialService.unfollowUser(targetUserId);
      _refreshDiscoverSilently();
    } catch (e) {
      seedFollowStatus(targetUserId, previousStatus);
      _feedPosts = [...removedFromFeed, ..._feedPosts];
      debugPrint('[CommunityProvider] unfollowUser Fehler: $e');
      notifyListeners();
    } finally {
      _busyFollow.remove(targetUserId);
    }
  }

  Future<void> _refreshFeedSilently() async {
    try {
      final fresh = await SocialService.getFeedPosts();
      _feedPosts = fresh;
      for (final post in fresh) {
        registerPost(post);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[CommunityProvider] _refreshFeedSilently: $e');
    }
  }

  Future<void> _refreshDiscoverSilently() async {
    try {
      final fresh = await SocialService.getDiscoverPosts();
      _discoverPosts = fresh;
      for (final post in fresh) {
        registerPost(post);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[CommunityProvider] _refreshDiscoverSilently: $e');
    }
  }

  Future<void> toggleLike(String postId) async {
    if (_busyLike.contains(postId)) return;
    _busyLike.add(postId);

    final wasLiked = _likedPosts[postId] ?? false;
    final oldCount = _likeCounts[postId] ?? 0;

    _likedPosts[postId] = !wasLiked;
    _likeCounts[postId] = wasLiked ? oldCount - 1 : oldCount + 1;
    if (_likeCounts[postId]! < 0) _likeCounts[postId] = 0;
    notifyListeners();

    try {
      final result = await SocialService.toggleLikeWithCount(postId);
      _likedPosts[postId] = result.isActive;
      _likeCounts[postId] = result.count < 0 ? 0 : result.count;
    } catch (e) {
      _likedPosts[postId] = wasLiked;
      _likeCounts[postId] = oldCount;
      debugPrint('[CommunityProvider] toggleLike Fehler: $e');
    } finally {
      _busyLike.remove(postId);
      notifyListeners();
    }
  }

  Future<void> toggleRepost(String postId) async {
    if (_busyRepost.contains(postId)) return;
    _busyRepost.add(postId);

    final wasReposted = _repostedPosts[postId] ?? false;
    final oldCount = _repostCounts[postId] ?? 0;

    _repostedPosts[postId] = !wasReposted;
    _repostCounts[postId] = wasReposted ? oldCount - 1 : oldCount + 1;
    if (_repostCounts[postId]! < 0) _repostCounts[postId] = 0;
    notifyListeners();

    try {
      final result = await SocialService.toggleRepostWithCount(postId);
      _repostedPosts[postId] = result.isActive;
      _repostCounts[postId] = result.count < 0 ? 0 : result.count;
    } catch (e) {
      _repostedPosts[postId] = wasReposted;
      _repostCounts[postId] = oldCount;
      debugPrint('[CommunityProvider] toggleRepost Fehler: $e');
    } finally {
      _busyRepost.remove(postId);
      notifyListeners();
    }
  }

  void removePost(String postId) {
    _feedPosts.removeWhere((p) => p['id'] == postId);
    _discoverPosts.removeWhere((p) => p['id'] == postId);
    _likedPosts.remove(postId);
    _likeCounts.remove(postId);
    _repostedPosts.remove(postId);
    _repostCounts.remove(postId);
    _checkedLike.remove(postId);
    _checkedRepost.remove(postId);
    notifyListeners();
  }

  @override
  void dispose() {
    stopRealtime();
    super.dispose();
  }
}
