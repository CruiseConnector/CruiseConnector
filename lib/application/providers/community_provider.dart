import 'package:flutter/foundation.dart';
import 'package:cruise_connect/data/services/social_service.dart';

/// Zentraler State für Community-Posts, Likes und Reposts.
/// Durch den zentralen State sind Likes überall in der App synchron —
/// kein manuelles Reload nötig.
class CommunityProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _feedPosts = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Like-State zentral gespeichert: postId → isLiked
  final Map<String, bool> _likedPosts = {};
  // Like-Anzahl zentral: postId → count
  final Map<String, int> _likeCounts = {};

  List<Map<String, dynamic>> get feedPosts => List.unmodifiable(_feedPosts);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Prüft ob ein Post geliked ist.
  bool isLiked(String postId) => _likedPosts[postId] ?? false;

  /// Gibt die Like-Anzahl für einen Post zurück.
  int likeCount(String postId) => _likeCounts[postId] ?? 0;

  /// Lädt den Feed neu.
  Future<void> loadFeed() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final posts = await SocialService.getFeedPosts();
      _feedPosts = posts;
      // Like-State aus den Posts initialisieren
      for (final post in posts) {
        final id = post['id'] as String?;
        if (id != null) {
          _likedPosts[id] = post['is_liked_by_me'] as bool? ?? false;
          _likeCounts[id] = (post['likes_count'] as num?)?.toInt() ?? 0;
        }
      }
    } catch (e) {
      _errorMessage = 'Feed konnte nicht geladen werden.';
      debugPrint('[CommunityProvider] loadFeed Fehler: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Toggled den Like-State eines Posts (optimistic update).
  Future<void> toggleLike(String postId) async {
    final wasLiked = _likedPosts[postId] ?? false;
    final oldCount = _likeCounts[postId] ?? 0;

    // Optimistic Update: UI sofort aktualisieren
    _likedPosts[postId] = !wasLiked;
    _likeCounts[postId] = wasLiked ? oldCount - 1 : oldCount + 1;
    notifyListeners();

    // Dann erst an Server schicken (SocialService.toggleLike kümmert sich
    // selbst darum ob es liked oder unliked)
    try {
      await SocialService.toggleLike(postId);
    } catch (e) {
      // Bei Fehler: Rollback
      _likedPosts[postId] = wasLiked;
      _likeCounts[postId] = oldCount;
      debugPrint('[CommunityProvider] toggleLike Fehler: $e');
      notifyListeners();
    }
  }

  /// Entfernt einen Post aus dem lokalen State (nach Löschen).
  void removePost(String postId) {
    _feedPosts.removeWhere((p) => p['id'] == postId);
    notifyListeners();
  }
}
