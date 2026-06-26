import 'package:flutter/foundation.dart';

import 'package:cruise_connect/data/services/group_chat_service.dart';

/// 2026-06-25 (vucko): Robuster Gruppen-Chat-Speicher.
///
/// Warum ein Store statt Logik im Widget? Wenn der User den Chat verlässt,
/// während eine Nachricht noch sendet, darf weder die Nachricht noch der
/// Entwurf verloren gehen. Dieser Singleton lebt UNABHÄNGIG vom Widget:
/// - Outbox mit Retry → der DB-Insert läuft zu Ende, auch wenn das Panel
///   längst disposed ist; bei Fehler 4 Versuche, dann „fehlgeschlagen" +
///   Wiederholen-Option.
/// - Pending-Nachrichten + Entwürfe überleben Navigieren (statisch gehalten).
/// - Dedup per `client_tag`: die optimistische Nachricht wird sauber durch die
///   bestätigte Server-Zeile ersetzt (kein Doppel, kein Verlust).
class GroupChatStore extends ChangeNotifier {
  GroupChatStore._();
  static final GroupChatStore instance = GroupChatStore._();

  final Map<String, List<Map<String, dynamic>>> _server = {};
  final Map<String, List<Map<String, dynamic>>> _pending = {};
  final Map<String, String> _drafts = {};
  final Set<String> _reloading = {};
  int _seq = 0;

  String draftFor(String groupId) => _drafts[groupId] ?? '';
  void setDraft(String groupId, String text) {
    if (text.isEmpty) {
      _drafts.remove(groupId);
    } else {
      _drafts[groupId] = text;
    }
  }

  /// Server-Nachrichten + noch nicht bestätigte (sending/failed) — chronologisch.
  List<Map<String, dynamic>> messagesFor(String groupId) {
    final server = _server[groupId] ?? const [];
    final serverTags = <String>{
      for (final m in server)
        if (m['client_tag'] != null) m['client_tag'] as String,
    };
    final pending = (_pending[groupId] ?? const [])
        .where((m) => !serverTags.contains(m['client_tag']))
        .toList();
    return [...server, ...pending];
  }

  bool get hasServerData => _server.isNotEmpty;
  bool hasGroupData(String groupId) => _server.containsKey(groupId);

  Future<void> reload(String groupId) async {
    if (_reloading.contains(groupId)) return;
    _reloading.add(groupId);
    try {
      final rows = await GroupChatService.fetchMessages(groupId);
      _server[groupId] = rows;
      // Bestätigte Pending (client_tag jetzt im Server) entfernen.
      final tags = <String>{
        for (final m in rows)
          if (m['client_tag'] != null) m['client_tag'] as String,
      };
      _pending[groupId]?.removeWhere((m) => tags.contains(m['client_tag']));
      notifyListeners();
    } catch (_) {
      // Reload-Fehler ist unkritisch (Realtime/nächster Versuch holt es nach).
    } finally {
      _reloading.remove(groupId);
    }
  }

  /// Nachricht senden: sofort optimistisch anzeigen, dann Outbox mit Retry.
  void send(String groupId, String body, Map<String, dynamic> profile) {
    final text = body.trim();
    if (text.isEmpty) return;
    final tag = 'c-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
    final optimistic = <String, dynamic>{
      'id': tag,
      'client_tag': tag,
      'group_id': groupId,
      'user_id': profile['id'],
      'body': text,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'deleted_at': null,
      'profiles': profile,
      '_status': 'sending',
    };
    (_pending[groupId] ??= []).add(optimistic);
    notifyListeners();
    _run(groupId, optimistic);
  }

  Future<void> _run(String groupId, Map<String, dynamic> optimistic) async {
    final tag = optimistic['client_tag'] as String;
    final body = optimistic['body'] as String;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await GroupChatService.sendMessage(groupId, body, clientTag: tag);
        optimistic['_status'] = 'sent';
        notifyListeners();
        // Bestätigte Zeile nachladen → optimistische wird ersetzt (Dedup).
        await reload(groupId);
        return;
      } catch (_) {
        // Backoff: 0.5s, 1s, 1.5s …
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    optimistic['_status'] = 'failed';
    notifyListeners();
  }

  void retry(String groupId, Map<String, dynamic> message) {
    if (message['_status'] != 'failed') return;
    message['_status'] = 'sending';
    notifyListeners();
    _run(groupId, message);
  }

  void discard(String groupId, Map<String, dynamic> message) {
    _pending[groupId]?.removeWhere((m) => m['client_tag'] == message['client_tag']);
    notifyListeners();
  }

  /// Lokales Soft-Delete (eigene, bereits gesendete Nachricht aus der Liste
  /// nehmen — der DB-Delete passiert separat im Service).
  void removeLocally(String groupId, String messageId) {
    _server[groupId]?.removeWhere((m) => m['id'] == messageId);
    _pending[groupId]?.removeWhere((m) => m['id'] == messageId);
    notifyListeners();
  }

  /// Eigene, bereits gesendete Nachricht bearbeiten (optimistisch + DB).
  Future<void> editMessage(
    String groupId,
    String messageId,
    String newBody,
  ) async {
    final clean = newBody.trim();
    if (clean.isEmpty) return;
    final list = _server[groupId];
    if (list != null) {
      for (final m in list) {
        if (m['id'] == messageId) {
          m['body'] = clean;
          m['edited_at'] = DateTime.now().toUtc().toIso8601String();
          break;
        }
      }
      notifyListeners();
    }
    try {
      await GroupChatService.editMessage(messageId, clean);
    } catch (_) {
      // Bei Fehler holt der reload den echten Stand zurück.
    }
    await reload(groupId);
  }

  /// Emoji-Reaktion auf eine bereits gesendete Nachricht umschalten
  /// (optimistisch + DB). [myUid] ist die eigene User-ID.
  void toggleReaction(
    String groupId,
    String messageId,
    String emoji,
    String myUid,
  ) {
    final list = _server[groupId];
    Map<String, dynamic>? msg;
    if (list != null) {
      for (final m in list) {
        if (m['id'] == messageId) {
          msg = m;
          break;
        }
      }
    }
    if (msg == null) return;

    final reactions = <Map<String, dynamic>>[
      for (final r in (msg['group_message_reactions'] as List?) ?? const [])
        if (r is Map) Map<String, dynamic>.from(r),
    ];
    final mine = reactions.any(
      (r) => r['emoji'] == emoji && r['user_id'] == myUid,
    );

    // Optimistisch umschalten.
    if (mine) {
      reactions.removeWhere(
        (r) => r['emoji'] == emoji && r['user_id'] == myUid,
      );
    } else {
      reactions.add({'emoji': emoji, 'user_id': myUid});
    }
    msg['group_message_reactions'] = reactions;
    notifyListeners();

    // Server (Add/Remove), danach echten Stand nachziehen.
    final future = mine
        ? GroupChatService.removeReaction(messageId, emoji)
        : GroupChatService.addReaction(messageId, emoji);
    future.then((_) => reload(groupId)).catchError((_) => reload(groupId));
  }
}
