import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent gespeicherte Notification-Präferenzen.
/// Lokales Filtering im Flutter — DB-Triggers feuern weiter, aber
/// die Toast/Realtime-Anzeige respektiert diese Settings.
///
/// Zukunft: bei OS-Push-Migration via Edge-Function diese Settings
/// auch server-side prüfen (z.B. via user_notification_prefs Tabelle).
class NotificationSettingsService extends ChangeNotifier {
  NotificationSettingsService._();
  static final NotificationSettingsService instance =
      NotificationSettingsService._();

  static const _keyFollows = 'notif_follows_v1';
  static const _keyLikes = 'notif_likes_v1';
  static const _keyComments = 'notif_comments_v1';
  static const _keyFriendRequests = 'notif_friend_requests_v1';
  static const _keyGroupInvites = 'notif_group_invites_v1';
  static const _keyDailyWeather = 'notif_daily_weather_v1';

  bool _loaded = false;
  bool _follows = true;
  bool _likes = true;
  bool _comments = true;
  bool _friendRequests = true;
  bool _groupInvites = true;
  bool _dailyWeather = true;

  bool get isLoaded => _loaded;
  bool get follows => _follows;
  bool get likes => _likes;
  bool get comments => _comments;
  bool get friendRequests => _friendRequests;
  bool get groupInvites => _groupInvites;
  bool get dailyWeather => _dailyWeather;

  bool isTypeEnabled(String type) {
    switch (type) {
      case 'follow':
        return _follows;
      case 'like':
        return _likes;
      case 'comment':
        return _comments;
      case 'friend_request':
        return _friendRequests;
      case 'group_invite':
      case 'group_joined':
      case 'group_public_created':
      case 'group_ride_started':
        return _groupInvites;
      case 'weather_recommendation':
        return _dailyWeather;
      default:
        return true;
    }
  }

  Future<void> load() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    _follows = p.getBool(_keyFollows) ?? true;
    _likes = p.getBool(_keyLikes) ?? true;
    _comments = p.getBool(_keyComments) ?? true;
    _friendRequests = p.getBool(_keyFriendRequests) ?? true;
    _groupInvites = p.getBool(_keyGroupInvites) ?? true;
    _dailyWeather = p.getBool(_keyDailyWeather) ?? true;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setFollows(bool v) => _set(_keyFollows, v, (n) => _follows = n);
  Future<void> setLikes(bool v) => _set(_keyLikes, v, (n) => _likes = n);
  Future<void> setComments(bool v) =>
      _set(_keyComments, v, (n) => _comments = n);
  Future<void> setFriendRequests(bool v) =>
      _set(_keyFriendRequests, v, (n) => _friendRequests = n);
  Future<void> setGroupInvites(bool v) =>
      _set(_keyGroupInvites, v, (n) => _groupInvites = n);
  Future<void> setDailyWeather(bool v) =>
      _set(_keyDailyWeather, v, (n) => _dailyWeather = n);

  Future<void> _set(String key, bool v, void Function(bool) apply) async {
    apply(v);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, v);
  }
}
