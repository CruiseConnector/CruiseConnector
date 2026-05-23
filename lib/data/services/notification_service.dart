import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cruise_connect/data/services/notification_settings_service.dart';

/// Zentrale Notification-Verwaltung mit Realtime-Subscription.
///
/// Architektur:
///   1. fetch() lädt initiale Liste via Supabase REST + JOIN auf profiles
///   2. subscribeRealtime() öffnet Channel auf notifications-Tabelle,
///      filtert auf user_id=currentUser, dispatcht onNew callback
///   3. ChangeNotifier-Pattern: UI hört via Provider/AnimatedBuilder
///
/// Kein OS-Push (APN/FCM) — In-App-Toast + Badge sind MVP.
/// Falls Toast gewünscht: onNew-Callback im UI-Layer hooken.
class NotificationService extends ChangeNotifier {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  SupabaseClient get _supabase => Supabase.instance.client;

  final List<AppNotification> _items = [];
  RealtimeChannel? _channel;
  bool _initialLoaded = false;

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((n) => !n.read).length;
  bool get isLoaded => _initialLoaded;

  /// Optional Callback wenn neue Notification während Session reinkommt.
  /// UI hookt hier für TopToast.
  ValueChanged<AppNotification>? onNew;

  Future<void> loadInitial() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final rows = await _supabase
          .from('notifications')
          .select(
              'id, created_at, user_id, from_user_id, type, read, reference_id, '
              'payload, aggregate_count, aggregate_until, '
              'from_profile:profiles!from_user_id(username, avatar_url)')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      _items
        ..clear()
        ..addAll(rows.map<AppNotification>(AppNotification.fromMap));
      _initialLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[NotificationService] loadInitial failed: $e');
    }
  }

  Future<void> startRealtime() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await stopRealtime();
    _channel = _supabase
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: _handleRealtimeInsert,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: _handleRealtimeUpdate,
        );
    _channel?.subscribe();
  }

  Future<void> stopRealtime() async {
    if (_channel != null) {
      await _supabase.removeChannel(_channel!);
      _channel = null;
    }
  }

  void _handleRealtimeInsert(PostgresChangePayload payload) {
    try {
      final notif = AppNotification.fromMap(payload.newRecord);
      _items.insert(0, notif);
      notifyListeners();
      // 2026-05-23 (vucko): User-Settings filtern — Toast nur wenn
      // dieser Typ aktiviert ist. Eintrag bleibt in der Inbox.
      if (NotificationSettingsService.instance.isTypeEnabled(notif.type)) {
        onNew?.call(notif);
      }
    } catch (e) {
      debugPrint('[NotificationService] realtime insert parse failed: $e');
    }
  }

  void _handleRealtimeUpdate(PostgresChangePayload payload) {
    try {
      final updated = AppNotification.fromMap(payload.newRecord);
      final idx = _items.indexWhere((n) => n.id == updated.id);
      if (idx >= 0) {
        _items[idx] = updated;
        notifyListeners();
        // Aggregierte Likes triggern auch ein UI-Refresh
        if (updated.aggregateCount > 1) {
          onNew?.call(updated);
        }
      }
    } catch (e) {
      debugPrint('[NotificationService] realtime update parse failed: $e');
    }
  }

  Future<void> markAsRead(String id) async {
    final idx = _items.indexWhere((n) => n.id == id);
    if (idx < 0) return;
    _items[idx] = _items[idx].copyWith(read: true);
    notifyListeners();
    try {
      await _supabase.from('notifications').update({'read': true}).eq('id', id);
    } catch (e) {
      debugPrint('[NotificationService] markAsRead failed: $e');
    }
  }

  Future<void> markAllAsRead() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final hadUnread = _items.any((n) => !n.read);
    if (!hadUnread) return;
    for (var i = 0; i < _items.length; i++) {
      if (!_items[i].read) _items[i] = _items[i].copyWith(read: true);
    }
    notifyListeners();
    try {
      await _supabase
          .from('notifications')
          .update({'read': true})
          .eq('user_id', userId)
          .eq('read', false);
    } catch (e) {
      debugPrint('[NotificationService] markAllAsRead failed: $e');
    }
  }

  Future<void> delete(String id) async {
    _items.removeWhere((n) => n.id == id);
    notifyListeners();
    try {
      await _supabase.from('notifications').delete().eq('id', id);
    } catch (e) {
      debugPrint('[NotificationService] delete failed: $e');
    }
  }
}

/// Value-Object für eine Notification inkl. JOIN auf from-Profile.
class AppNotification {
  final String id;
  final DateTime createdAt;
  final String userId;
  final String fromUserId;
  final String type;
  final bool read;
  final String? referenceId;
  final Map<String, dynamic> payload;
  final int aggregateCount;
  final DateTime? aggregateUntil;
  final String? fromUsername;
  final String? fromAvatarUrl;

  AppNotification({
    required this.id,
    required this.createdAt,
    required this.userId,
    required this.fromUserId,
    required this.type,
    required this.read,
    required this.referenceId,
    required this.payload,
    required this.aggregateCount,
    required this.aggregateUntil,
    required this.fromUsername,
    required this.fromAvatarUrl,
  });

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        createdAt: createdAt,
        userId: userId,
        fromUserId: fromUserId,
        type: type,
        read: read ?? this.read,
        referenceId: referenceId,
        payload: payload,
        aggregateCount: aggregateCount,
        aggregateUntil: aggregateUntil,
        fromUsername: fromUsername,
        fromAvatarUrl: fromAvatarUrl,
      );

  factory AppNotification.fromMap(Map<String, dynamic> m) {
    final fromProfile = m['from_profile'] as Map<String, dynamic>?;
    return AppNotification(
      id: m['id'] as String,
      createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
          DateTime.now(),
      userId: m['user_id'] as String,
      fromUserId: m['from_user_id'] as String? ?? '',
      type: m['type'] as String,
      read: (m['read'] as bool?) ?? false,
      referenceId: m['reference_id'] as String?,
      payload: (m['payload'] as Map<String, dynamic>?) ?? const {},
      aggregateCount: ((m['aggregate_count'] ?? 1) as num).toInt(),
      aggregateUntil: m['aggregate_until'] == null
          ? null
          : DateTime.tryParse(m['aggregate_until'] as String),
      fromUsername: fromProfile?['username'] as String?,
      fromAvatarUrl: fromProfile?['avatar_url'] as String?,
    );
  }

  /// Liefert (title, body) für UI je nach type.
  (String title, String body) renderTexts() {
    final name = fromUsername ?? 'Jemand';
    switch (type) {
      case 'follow':
        return ('Neuer Follower', '$name folgt dir jetzt');
      case 'like':
        if (aggregateCount > 1) {
          return (
            '$aggregateCount neue Likes',
            '$name und ${aggregateCount - 1} weitere haben deinen Post geliked'
          );
        }
        return ('Neuer Like', '$name gefällt dein Post');
      case 'comment':
        return ('Neuer Kommentar', '$name hat kommentiert');
      case 'friend_request':
        return ('Freundschaftsanfrage', '$name möchte mit dir cruisen');
      case 'group_invite':
        final group = payload['group_name'] as String? ?? 'einer Gruppe';
        return ('Gruppen-Einladung', '$name lädt dich zu $group ein');
      case 'group_ride_started':
        return ('Gruppen-Ride gestartet', '$name fährt jetzt los');
      case 'group_public_created':
        return ('Neue Gruppe', '$name hat eine öffentliche Gruppe erstellt');
      case 'group_joined':
        return ('Neues Gruppenmitglied', '$name ist beigetreten');
      case 'repost':
        return ('Repost', '$name hat deinen Post geteilt');
      case 'weather_recommendation':
        final tempC = payload['temperature_c'];
        final cond = payload['condition'] as String? ?? 'gut';
        return (
          'Perfektes Wetter zum Cruisen',
          tempC != null
              ? '${tempC.round()}° und $cond — Zeit für eine Runde?'
              : 'Heute ist es ideal für eine Tour'
        );
      case 'trip_reminder':
        return ('Trip wartet', 'Dein gestarteter Trip wartet auf Fortsetzung');
      default:
        return ('Benachrichtigung', name);
    }
  }
}
