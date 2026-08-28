import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Opt-out-Präferenzen für Push-Benachrichtigungen.
///
/// Prinzip: Beim ersten „Erlauben" sind ALLE sinnvollen Typen an (Default true /
/// fehlender Schlüssel = aktiviert). Der Nutzer schaltet in den Einstellungen
/// nur ab, was ihm zu viel ist.
///
/// WICHTIG (2026-06-24): Diese Settings werden jetzt zusätzlich server-seitig in
/// `profiles.notification_preferences` (jsonb) gespiegelt, weil die Edge-Function
/// `send-push` sie VOR dem Versand prüft. SharedPreferences bleibt nur lokaler
/// Cache (schneller Erststart, offline). DB ist die Source-of-Truth; bei Login /
/// Auth-Wechsel wird vom Server nachgezogen → geräteübergreifend konsistent.
///
/// Schlüsselnamen sind IDENTISCH zu den jsonb-Keys + zur Kategorie-Logik in
/// send-push (categoryForType), damit Client und Server dieselbe Sprache sprechen.
class NotificationSettingsService extends ChangeNotifier {
  NotificationSettingsService._();
  static final NotificationSettingsService instance =
      NotificationSettingsService._();

  static const _keyFollows = 'follows';
  static const _keyLikes = 'likes';
  static const _keyReposts = 'reposts';
  static const _keyComments = 'comments';
  static const _keyFriendRequests = 'friend_requests';
  static const _keyGroupInvites = 'group_invites';
  static const _keyDailyWeather = 'daily_weather';
  // 2026-08-28 (Fehler 6): Beitraege von Gefolgten + Community-Chat.
  static const _keyFeedPosts = 'feed_posts';
  static const _keyCommunityChat = 'community_chat';

  /// Prefix für den lokalen SharedPreferences-Cache.
  static const _spPrefix = 'notif_pref_';

  bool _loaded = false;
  bool _authWired = false;

  // Alle Kategorien standardmäßig AN.
  final Map<String, bool> _prefs = <String, bool>{
    _keyFollows: true,
    _keyLikes: true,
    _keyReposts: true,
    _keyComments: true,
    _keyFriendRequests: true,
    _keyGroupInvites: true,
    _keyDailyWeather: true,
    _keyFeedPosts: true,
    _keyCommunityChat: true,
  };

  bool get isLoaded => _loaded;
  bool get follows => _prefs[_keyFollows]!;
  bool get likes => _prefs[_keyLikes]!;
  bool get reposts => _prefs[_keyReposts]!;
  bool get comments => _prefs[_keyComments]!;
  bool get friendRequests => _prefs[_keyFriendRequests]!;
  bool get groupInvites => _prefs[_keyGroupInvites]!;
  bool get dailyWeather => _prefs[_keyDailyWeather]!;
  bool get feedPosts => _prefs[_keyFeedPosts]!;
  bool get communityChat => _prefs[_keyCommunityChat]!;

  /// Notification-Typ -> Einstellungs-Kategorie. Spiegel von send-push.
  /// Unbekannter Typ (z. B. trip_reminder) = immer an.
  static String? _categoryForType(String type) {
    switch (type) {
      case 'follow':
        return _keyFollows;
      case 'like':
        return _keyLikes;
      case 'repost':
        return _keyReposts;
      case 'comment':
        return _keyComments;
      case 'friend_request':
        return _keyFriendRequests;
      case 'group_invite':
      case 'group_joined':
      case 'group_public_created':
      case 'group_ride_started':
        return _keyGroupInvites;
      case 'weather_recommendation':
        return _keyDailyWeather;
      case 'feed_post':
        return _keyFeedPosts;
      case 'community_message':
        return _keyCommunityChat;
      default:
        return null;
    }
  }

  /// Für das In-App-Filtering (Toast/Realtime). Unbekannt = an.
  bool isTypeEnabled(String type) {
    final key = _categoryForType(type);
    if (key == null) return true;
    return _prefs[key] ?? true;
  }

  Future<void> load() async {
    if (!_loaded) {
      // 1) Lokaler Cache — sofort verfügbar, offline-fest.
      final p = await SharedPreferences.getInstance();
      for (final key in _prefs.keys.toList()) {
        final v = p.getBool('$_spPrefix$key');
        if (v != null) _prefs[key] = v;
      }
      _loaded = true;
      notifyListeners();
    }
    _wireAuthListener();
    // 2) Server-Wahrheit nachladen (falls schon eingeloggt).
    unawaited(_syncFromServer());
  }

  /// Auth-Wechsel (Login, Session-Restore) -> Prefs vom Server ziehen, damit sie
  /// geräteübergreifend gelten. Idempotent.
  void _wireAuthListener() {
    if (_authWired) return;
    _authWired = true;
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      switch (data.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.userUpdated:
          unawaited(_syncFromServer());
          break;
        default:
          break;
      }
    });
  }

  /// Manuell vom Server aktualisieren (z. B. beim Öffnen der Einstellungen).
  Future<void> refreshFromServer() => _syncFromServer();

  Future<void> _syncFromServer() async {
    final supa = Supabase.instance.client;
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await supa
          .from('profiles')
          .select('notification_preferences')
          .eq('id', uid)
          .maybeSingle();
      final raw = row?['notification_preferences'];
      if (raw is Map) {
        final p = await SharedPreferences.getInstance();
        var changed = false;
        for (final key in _prefs.keys.toList()) {
          final v = raw[key];
          if (v is bool && v != _prefs[key]) {
            _prefs[key] = v;
            await p.setBool('$_spPrefix$key', v);
            changed = true;
          }
        }
        if (changed) notifyListeners();
      }
    } catch (e) {
      debugPrint('[NotifPrefs] server sync failed: $e');
    }
  }

  Future<void> setFollows(bool v) => _set(_keyFollows, v);
  Future<void> setLikes(bool v) => _set(_keyLikes, v);
  Future<void> setReposts(bool v) => _set(_keyReposts, v);
  Future<void> setComments(bool v) => _set(_keyComments, v);
  Future<void> setFriendRequests(bool v) => _set(_keyFriendRequests, v);
  Future<void> setGroupInvites(bool v) => _set(_keyGroupInvites, v);
  Future<void> setDailyWeather(bool v) => _set(_keyDailyWeather, v);
  Future<void> setFeedPosts(bool v) => _set(_keyFeedPosts, v);
  Future<void> setCommunityChat(bool v) => _set(_keyCommunityChat, v);

  Future<void> _set(String key, bool v) async {
    if (_prefs[key] == v) return;
    _prefs[key] = v;
    notifyListeners();
    // Lokal cachen (sofort).
    final p = await SharedPreferences.getInstance();
    await p.setBool('$_spPrefix$key', v);
    // + Server (damit send-push die Einstellung respektiert).
    await _pushToServer();
  }

  /// Die komplette Map nach profiles.notification_preferences schreiben.
  Future<void> _pushToServer() async {
    final supa = Supabase.instance.client;
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supa.from('profiles').update(
        {'notification_preferences': Map<String, bool>.from(_prefs)},
      ).eq('id', uid);
    } catch (e) {
      debugPrint('[NotifPrefs] server write failed: $e');
    }
  }
}
