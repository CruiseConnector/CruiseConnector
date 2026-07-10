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
      final rec = payload.newRecord;
      final id = rec['id'] as String?;
      if (id == null) return;
      final idx = _items.indexWhere((n) => n.id == id);
      if (idx < 0) return;
      // 2026-07-10 (vucko Avatar-Fix): Das Realtime-WAL-Payload ist single-table
      // und enthält NICHT das in loadInitial gejointe from_profile
      // (username/avatar_url). Würde man das Item komplett aus fromMap(newRecord)
      // neu bauen, wäre fromAvatarUrl=null → der Avatar fällt beim „Alle gelesen"
      // /Öffnen bis zum App-Neustart auf das Platzhalter-Symbol zurück. Deshalb
      // NUR die tatsächlich geänderten Felder (read/aggregate) auf das bestehende
      // Item mergen und Avatar + Name behalten.
      final merged = _items[idx].copyWith(
        read: rec['read'] as bool?,
        aggregateCount: (rec['aggregate_count'] as num?)?.toInt(),
        aggregateUntil: rec['aggregate_until'] == null
            ? null
            : DateTime.tryParse(rec['aggregate_until'] as String),
      );
      _items[idx] = merged;
      notifyListeners();
      // Aggregierte Likes triggern auch ein UI-Refresh
      if (merged.aggregateCount > 1) {
        onNew?.call(merged);
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

  AppNotification copyWith({
    bool? read,
    int? aggregateCount,
    DateTime? aggregateUntil,
  }) =>
      AppNotification(
        id: id,
        createdAt: createdAt,
        userId: userId,
        fromUserId: fromUserId,
        type: type,
        read: read ?? this.read,
        referenceId: referenceId,
        payload: payload,
        aggregateCount: aggregateCount ?? this.aggregateCount,
        aggregateUntil: aggregateUntil ?? this.aggregateUntil,
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
  ///
  /// 2026-05-24 (vucko): Variantenpool pro Type für Push-Notification-
  /// Vielfalt. Pro Notification deterministisch (gleicher Index für
  /// gleiche notification.id) — User sieht nicht zweimal denselben Text
  /// und alle Notifications haben einen frischen Anstrich.
  (String title, String body) renderTexts() {
    // 2026-06-25 (vucko): Immer den @Namen des Auslösers zeigen — z.B.
    // „@vucko hat deinen Post geliked". Nur wenn wirklich kein Username da ist,
    // Fallback auf „Jemand".
    final name = (fromUsername != null && fromUsername!.trim().isNotEmpty)
        ? '@${fromUsername!.trim()}'
        : 'Jemand';
    // Deterministischer Index pro Notification — gleiche ID → gleicher Text.
    final variantIdx = id.hashCode.abs();
    String pick(List<String> options) =>
        options[variantIdx % options.length];

    switch (type) {
      case 'follow':
        return (
          pick(const [
            'Neuer Follower',
            'Du hast einen Follower',
            'Cruiser folgt dir',
          ]),
          pick([
            '$name folgt dir jetzt',
            '$name ist jetzt einer deiner Follower',
            '$name will deine Touren sehen',
          ]),
        );
      case 'like':
        if (aggregateCount > 1) {
          return (
            '$aggregateCount neue Likes',
            pick([
              '$name und ${aggregateCount - 1} weitere haben deinen Post geliked',
              '$name + ${aggregateCount - 1} feiern deinen Post',
            ]),
          );
        }
        return (
          pick(const ['Neuer Like', 'Jemand mag deinen Post', 'Post gefällt']),
          pick([
            '$name gefällt dein Post',
            '$name hat dir ein Herz gegeben',
            '$name feiert deinen Beitrag',
          ]),
        );
      case 'comment':
        return (
          pick(const ['Neuer Kommentar', 'Jemand antwortet dir', 'Comment-Drop']),
          pick([
            '$name hat kommentiert',
            '$name antwortet auf deinen Post',
            '$name mischt sich ein',
          ]),
        );
      case 'friend_request':
        return (
          pick(const [
            'Freundschaftsanfrage',
            'Cruise-Buddy-Anfrage',
            'Neuer Kontakt',
          ]),
          pick([
            '$name möchte mit dir cruisen',
            '$name will dein Cruise-Buddy werden',
            '$name will mit dir Touren teilen',
          ]),
        );
      case 'group_invite':
        final group = payload['group_name'] as String? ?? 'einer Gruppe';
        return (
          pick(const [
            'Gruppen-Einladung',
            'Du wurdest eingeladen',
            'Ride-Crew sucht dich',
          ]),
          pick([
            '$name lädt dich zu $group ein',
            '$name will dich bei $group dabei haben',
            'Komm zu $group — Einladung von $name',
          ]),
        );
      case 'group_ride_started':
        return (
          pick(const [
            'Gruppen-Ride gestartet',
            'Crew rollt los',
            'Die Tour läuft',
          ]),
          pick([
            '$name fährt jetzt los',
            '$name hat die Tour gestartet — schließ dich an',
            'Spring auf: $name ist unterwegs',
          ]),
        );
      case 'group_public_created':
        return (
          pick(const ['Neue Gruppe', 'Frische Ride-Crew', 'Neue öffentliche Tour']),
          pick([
            '$name hat eine öffentliche Gruppe erstellt',
            '$name eröffnet eine neue Crew',
          ]),
        );
      case 'group_joined':
        return (
          pick(const [
            'Neues Gruppenmitglied',
            'Crew wächst',
            'Neuer Cruiser dabei',
          ]),
          pick([
            '$name ist beigetreten',
            '$name fährt jetzt mit',
            '$name ist Teil der Crew',
          ]),
        );
      case 'repost':
        return (
          pick(const ['Repost', 'Geteilt!', 'Dein Post verbreitet sich']),
          pick([
            '$name hat deinen Post geteilt',
            '$name pusht deinen Beitrag weiter',
          ]),
        );
      case 'weather_recommendation':
        return _weatherTexts(variantIdx);
      case 'trip_reminder':
        return (
          pick(const [
            'Trip wartet',
            'Deine Tour läuft noch',
            'Weiterfahren?',
          ]),
          pick([
            'Dein gestarteter Trip wartet auf Fortsetzung',
            'Letzter Stopp erreicht — bereit für den nächsten?',
            'Deine Multi-Stop-Tour pausiert — knack sie heute',
          ]),
        );
      default:
        return ('Benachrichtigung', name);
    }
  }

  /// 2026-05-24 (vucko): Kontext-aware Wetter-Texte je nach Temp +
  /// Tageszeit. Damit der User bei 28° Sonne nicht denselben "Heute ist
  /// es ideal"-Text bekommt wie bei 12° Bewölkt.
  (String, String) _weatherTexts(int variantIdx) {
    final tempCRaw = payload['temperature_c'];
    final temp = tempCRaw is num ? tempCRaw.toDouble() : null;
    final cond = (payload['condition'] as String?)?.toLowerCase() ?? 'gut';
    final hour = DateTime.now().hour;
    final isMorning = hour >= 5 && hour < 11;
    final isEvening = hour >= 16 && hour < 21;

    String pick(List<String> opts) => opts[variantIdx % opts.length];

    // Hitze (28°+)
    if (temp != null && temp >= 28) {
      return (
        pick(const ['Bestes Cruise-Wetter', 'Sonniger Tag', 'Heiß wie Asphalt']),
        pick([
          '${temp.round()}° und $cond — perfekt für eine schattige Bergtour',
          '${temp.round()}° draußen — Helm auf und ab in die Kurven',
          'Idealer Tag für eine entspannte Runde — ${temp.round()}°',
        ]),
      );
    }
    // Mild (18-27°) — optimal
    if (temp != null && temp >= 18 && temp < 28) {
      if (isMorning) {
        return (
          pick(const ['Perfekter Morgen', 'Morgentour gefällig?', 'Bestes Wetter']),
          pick([
            '${temp.round()}° und $cond — frische Luft wartet auf dich',
            '${temp.round()}° — Zeit für eine Vormittagsrunde',
            'Idealer Morgen für eine Tour — ${temp.round()}° draußen',
          ]),
        );
      }
      if (isEvening) {
        return (
          pick(const ['Feierabend-Cruise?', 'Goldene Stunde', 'Sunset-Tour wartet']),
          pick([
            '${temp.round()}° — perfekt für eine Abendrunde',
            'Sonnenuntergangs-Tour bei ${temp.round()}° — wie wärs?',
            '${temp.round()}° und $cond — Zeit für einen entspannten Cruise',
          ]),
        );
      }
      return (
        pick(const [
          'Perfektes Cruise-Wetter',
          'Bestes Wetter draußen',
          'Zeit für eine Tour',
        ]),
        pick([
          '${temp.round()}° und $cond — bereit für eine Runde?',
          'Cruise-Bedingungen optimal: ${temp.round()}°',
          'Heute idealer Tag — ${temp.round()}° und $cond',
        ]),
      );
    }
    // Kühl aber fahrbar (8-17°)
    if (temp != null && temp >= 8 && temp < 18) {
      return (
        pick(const [
          'Frischer Cruise-Tag',
          'Layer-Wetter',
          'Frische Luft wartet',
        ]),
        pick([
          '${temp.round()}° — pack die Jacke und rauf aufs Bike',
          'Kühl aber fahrbar: ${temp.round()}° und $cond',
          'Mit Jacke perfekt: ${temp.round()}° draußen',
        ]),
      );
    }
    // Kalt (<8°) — Aufruf zur Vorsicht
    if (temp != null && temp < 8) {
      return (
        pick(const ['Kalt aber möglich', 'Winter-Cruise', 'Frostige Tour?']),
        pick([
          '${temp.round()}° — warm anziehen, dann rollts',
          'Kalt aber klar bei ${temp.round()}° — vorsichtig fahren',
        ]),
      );
    }
    // Default ohne temp
    return (
      pick(const [
        'Perfektes Wetter zum Cruisen',
        'Bestes Cruise-Wetter',
        'Zeit für eine Tour',
      ]),
      pick(const [
        'Heute ist es ideal für eine Tour',
        'Die Bedingungen sind perfekt',
        'Helm auf und los gehts',
      ]),
    );
  }
}
