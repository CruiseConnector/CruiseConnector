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
  bool isFollowing(String userId) => _followingIds.contains(userId);

  /// Ruft jede Seite (Feed, Entdecken, Profil) auf, bevor sie Posts rendert.
  /// Seedet den zentralen State, falls der Post noch nicht bekannt ist;
  /// überschreibt keine bereits vorhandenen Werte (optimistic wins).
  void registerPost(Map<String, dynamic> post) {
    final id = post['id'] as String?;
    if (id == null) return;
    _likeCounts.putIfAbsent(id, () => (post['likes_count'] as num?)?.toInt() ?? 0);
    _repostCounts.putIfAbsent(id, () => (post['reposts_count'] as num?)?.toInt() ?? 0);
    final liked = post['is_liked_by_me'];
    if (liked is bool) {
      _likedPosts.putIfAbsent(id, () => liked);
      _checkedLike.add(id);
    }
    final reposted = post['is_reposted_by_me'];
    if (reposted is bool) {
      _repostedPosts.putIfAbsent(id, () => reposted);
      _checkedRepost.add(id);
    }
  }

  /// Für Posts, bei denen der Server-Wert `is_liked_by_me` nicht mitgeliefert
  /// wurde — einmalig per Request nachladen.
  Future<void> ensureLikedChecked(String postId) async {
    if (_checkedLike.contains(postId)) return;
    _checkedLike.add(postId);
    try {
      final liked = await SocialService.hasLiked(postId);
      _likedPosts[postId] = liked;
      notifyListeners();
    } catch (_) {
      _checkedLike.remove(postId);
    }
  }

  Future<void> ensureRepostedChecked(String postId) async {
    if (_checkedRepost.contains(postId)) return;
    _checkedRepost.add(postId);
    try {
      final reposted = await SocialService.hasReposted(postId);
      _repostedPosts[postId] = reposted;
      notifyListeners();
    } catch (_) {
      _checkedRepost.remove(postId);
    }
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
      ]);
      _feedPosts = results[0] as List<Map<String, dynamic>>;
      _discoverPosts = results[1] as List<Map<String, dynamic>>;
      _followingIds = results[2] as Set<String>;
      for (final post in _feedPosts) {
        registerPost(post);
      }
      for (final post in _discoverPosts) {
        registerPost(post);
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

  /// Folgt einem User und entfernt dessen Posts sofort aus dem Discover-Tab,
  /// damit der Wechsel ohne Re-Fetch sichtbar ist. Im Hintergrund wird der
  /// Feed neu geladen, damit die noch unbekannten Posts des Users erscheinen.
  Future<void> followUser(String targetUserId) async {
    if (_busyFollow.contains(targetUserId)) return;
    _busyFollow.add(targetUserId);

    final wasFollowing = _followingIds.contains(targetUserId);
    if (wasFollowing) {
      _busyFollow.remove(targetUserId);
      return;
    }

    _followingIds = {..._followingIds, targetUserId};
    final removedFromDiscover = _discoverPosts
        .where((p) => p['user_id'] == targetUserId)
        .toList();
    _discoverPosts = _discoverPosts
        .where((p) => p['user_id'] != targetUserId)
        .toList();
    notifyListeners();

    try {
      await SocialService.followUser(targetUserId);
      // Hintergrund-Refetch, um neue Posts zu bekommen (ohne UI-Block).
      _refreshFeedSilently();
    } catch (e) {
      _followingIds = {..._followingIds}..remove(targetUserId);
      _discoverPosts = [..._discoverPosts, ...removedFromDiscover];
      debugPrint('[CommunityProvider] followUser Fehler: $e');
      notifyListeners();
    } finally {
      _busyFollow.remove(targetUserId);
    }
  }

  /// Entfolgt einem User und filtert dessen Posts sofort aus dem Feed.
  /// Im Hintergrund wird Discover neu geladen, damit die Posts dort
  /// auftauchen, falls das Profil öffentlich ist.
  Future<void> unfollowUser(String targetUserId) async {
    if (_busyFollow.contains(targetUserId)) return;
    _busyFollow.add(targetUserId);

    final wasFollowing = _followingIds.contains(targetUserId);
    if (!wasFollowing) {
      _busyFollow.remove(targetUserId);
      return;
    }

    final removedFromFeed = _feedPosts
        .where((p) => p['user_id'] == targetUserId)
        .toList();
    _feedPosts = _feedPosts
        .where((p) => p['user_id'] != targetUserId)
        .toList();
    _followingIds = {..._followingIds}..remove(targetUserId);
    notifyListeners();

    try {
      await SocialService.unfollowUser(targetUserId);
      _refreshDiscoverSilently();
    } catch (e) {
      _followingIds = {..._followingIds, targetUserId};
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
    notifyListeners();

    try {
      final nowLiked = await SocialService.toggleLike(postId);
      // Server ist Source of Truth: Zustand angleichen, Count aus Baseline
      // neu ableiten, damit -1 / +2 nicht möglich sind.
      _likedPosts[postId] = nowLiked;
      final baseline = wasLiked ? oldCount - 1 : oldCount;
      _likeCounts[postId] = baseline + (nowLiked ? 1 : 0);
      if (_likeCounts[postId]! < 0) _likeCounts[postId] = 0;
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
    notifyListeners();

    try {
      final nowReposted = await SocialService.toggleRepost(postId);
      _repostedPosts[postId] = nowReposted;
      final baseline = wasReposted ? oldCount - 1 : oldCount;
      _repostCounts[postId] = baseline + (nowReposted ? 1 : 0);
      if (_repostCounts[postId]! < 0) _repostCounts[postId] = 0;
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
}
