import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/core/emoji_guard.dart';
import 'package:cruise_connect/data/services/social_service.dart';

/// 2026-06-25 (vucko): Gruppen-Chat. Mitglieder einer Cruise-Gruppe können sich
/// austauschen (Treffpunkt, Tempo, „wo seid ihr?"). Gespiegelt vom bewährten
/// Community-Chat ([CommunityChatService]). Tabelle `group_messages` wird per
/// FK ON DELETE CASCADE automatisch mit der Gruppe gelöscht (24h nach
/// Fahrt-Ende, siehe Migration group_chat_and_24h_lifecycle).
class GroupChatService {
  GroupChatService._();

  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _userId => _db.auth.currentUser?.id;

  static const String _messageSelect =
      'id, group_id, user_id, body, created_at, deleted_at, edited_at, '
      'client_tag, profiles:user_id(id, username, avatar_url), '
      'group_message_reactions(emoji, user_id)';

  static const int _bodyMaxLength = 2000;

  static String displayName(
    Map<String, dynamic>? profile, {
    String? fallbackUserId,
  }) {
    return SocialService.publicDisplayName(
      profile,
      fallbackUserId: fallbackUserId,
    );
  }

  /// Lädt die letzten 150 sichtbaren Nachrichten (aufsteigend), inkl. Profil.
  static Future<List<Map<String, dynamic>>> fetchMessages(
    String groupId,
  ) async {
    final rows = await _db
        .from('group_messages')
        .select(_messageSelect)
        .eq('group_id', groupId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: true)
        .limit(150);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Schreibt eine Nachricht. [clientTag] erlaubt dem Sender, seine optimistische
  /// Nachricht eindeutig mit der bestätigten Server-Zeile zu matchen (kein
  /// Doppel/Verlust). Wirft bei Fehler — der Outbox-Retry im GroupChatStore
  /// fängt das ab (4 Versuche, dann „nicht gesendet"-Status).
  ///
  /// 2026-06-25 (vucko): BEWUSST nur INSERT, KEIN `.select(_messageSelect)`-
  /// Embed beim Senden. Der profiles-Embed hing früher hier am FK
  /// group_messages→profiles (der fehlte → JEDER Send schlug fehl). Jetzt ist
  /// der Sende-Pfad maximal schlank + schnell und hängt an gar keinem Embed; die
  /// volle Zeile (inkl. Profil) holt der Realtime-Reload (fetchMessages).
  static Future<void> sendMessage(
    String groupId,
    String body, {
    String? clientTag,
  }) async {
    final uid = _userId;
    if (uid == null) {
      throw Exception('Nicht angemeldet.');
    }
    final cleanBody = body.trim();
    if (cleanBody.isEmpty) return;
    final trimmed = cleanBody.length > _bodyMaxLength
        ? cleanBody.substring(0, _bodyMaxLength)
        : cleanBody;
    await _db.from('group_messages').insert({
      'group_id': groupId,
      'user_id': uid,
      'body': trimmed,
      if (clientTag != null) 'client_tag': clientTag,
    });
  }

  /// Soft-Delete der eigenen Nachricht.
  static Future<void> deleteMessage(String messageId) async {
    await _db
        .from('group_messages')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', messageId);
  }

  /// Eigene Nachricht bearbeiten (Body + edited_at). RLS lässt nur eigene zu.
  static Future<void> editMessage(String messageId, String newBody) async {
    final clean = newBody.trim();
    if (clean.isEmpty) return;
    final trimmed = clean.length > _bodyMaxLength
        ? clean.substring(0, _bodyMaxLength)
        : clean;
    await _db
        .from('group_messages')
        .update({
          'body': trimmed,
          'edited_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', messageId);
  }

  /// Emoji-Reaktion setzen (idempotent — doppeltes Setzen ist ein No-Op).
  static Future<void> addReaction(String messageId, String emoji) async {
    // 2026-07-23 (vucko "nur Emoji, kein Text bei Reaktionen"): Defense in
    // Depth auf Service-Ebene, siehe community_chat_service.dart.
    if (!EmojiGuard.isSingleEmoji(emoji)) return;
    final uid = _userId;
    if (uid == null) return;
    await _db.from('group_message_reactions').upsert(
      {'message_id': messageId, 'user_id': uid, 'emoji': emoji},
      onConflict: 'message_id,user_id,emoji',
      ignoreDuplicates: true,
    );
  }

  /// Eigene Emoji-Reaktion entfernen.
  static Future<void> removeReaction(String messageId, String emoji) async {
    final uid = _userId;
    if (uid == null) return;
    await _db
        .from('group_message_reactions')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', uid)
        .eq('emoji', emoji);
  }

  /// Realtime-Abo auf neue/geänderte Nachrichten dieser Gruppe.
  static RealtimeChannel subscribeMessages(
    String groupId,
    void Function() onChange, {
    void Function(RealtimeSubscribeStatus status, Object? error)? onStatus,
  }) {
    final channel = _db.channel('group_messages_$groupId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'group_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'group_id',
        value: groupId,
      ),
      callback: (_) => onChange(),
    );
    // Reaktionen haben kein group_id → kein Spalten-Filter möglich; die RLS
    // liefert per Realtime nur Reaktionen aus den eigenen Gruppen aus, also
    // unkritisch. Jede Reaktions-Änderung triggert einen Reload.
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'group_message_reactions',
      callback: (_) => onChange(),
    );
    channel.subscribe(onStatus);
    return channel;
  }
}
