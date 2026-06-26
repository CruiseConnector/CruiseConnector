import 'dart:async';

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/group_chat_store.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/group_chat_service.dart';
import 'package:cruise_connect/presentation/widgets/skeletons/skeleton.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

/// 2026-06-25 (vucko): Gruppen-Chat als einbettbares Panel (Lobby → „Chat").
///
/// Die GANZE Sende-/Zustands-Logik liegt im [GroupChatStore] (Singleton), nicht
/// hier — so überlebt eine Nachricht das Verlassen des Chats (Outbox mit Retry)
/// und der Entwurf geht nicht verloren. Das Panel ist nur die Ansicht: es hört
/// auf den Store + auf Realtime und rendert. Eigene Nachrichten per Lang-Druck
/// löschen; fehlgeschlagene per Tipp erneut senden.
class GroupChatPanel extends StatefulWidget {
  const GroupChatPanel({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupChatPanel> createState() => _GroupChatPanelState();
}

class _GroupChatPanelState extends State<GroupChatPanel> {
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _store = GroupChatStore.instance;

  RealtimeChannel? _channel;
  Timer? _reloadDebounce;
  bool _loading = true;
  int _lastCount = 0;

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;
  String get _gid => widget.groupId;

  @override
  void initState() {
    super.initState();
    // Entwurf wiederherstellen — nichts geht verloren, wenn man kurz rausgeht.
    _messageCtrl.text = _store.draftFor(_gid);
    _loading = !_store.hasGroupData(_gid);
    _store.addListener(_onStore);
    _subscribe();
    _initialLoad();
  }

  @override
  void dispose() {
    // Entwurf sichern (Senden hat ihn ggf. schon geleert).
    _store.setDraft(_gid, _messageCtrl.text);
    _store.removeListener(_onStore);
    _reloadDebounce?.cancel();
    _channel?.unsubscribe();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _initialLoad() async {
    await _store.reload(_gid);
    if (!mounted) return;
    setState(() => _loading = false);
    _scrollToBottom(jump: true);
  }

  void _onStore() {
    if (!mounted) return;
    final count = _store.messagesFor(_gid).length;
    final grew = count > _lastCount;
    _lastCount = count;
    setState(() {});
    if (grew) _scrollToBottom();
  }

  void _subscribe() {
    _channel = GroupChatService.subscribeMessages(_gid, () {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 140), () {
        _store.reload(_gid);
      });
    });
  }

  void _send() {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;
    final uid = _uid;
    if (uid == null) return;
    _store.send(_gid, text, _myProfile(uid));
    _messageCtrl.clear();
    _store.setDraft(_gid, '');
    _scrollToBottom();
  }

  Map<String, dynamic> _myProfile(String uid) {
    final user = Supabase.instance.client.auth.currentUser;
    final meta = user?.userMetadata ?? const <String, dynamic>{};
    return {
      'id': uid,
      'username': meta['username'] ?? meta['name'] ?? user?.email,
      'email': user?.email,
      'avatar_url': meta['avatar_url'],
    };
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    final id = message['id']?.toString();
    if (id == null) return;
    final status = message['_status'];
    if (status == 'sending' || status == 'failed') {
      _store.discard(_gid, message);
      return;
    }
    _store.removeLocally(_gid, id);
    try {
      await GroupChatService.deleteMessage(id);
    } catch (_) {
      _store.reload(_gid);
    }
  }

  void _messageActions(Map<String, dynamic> message) {
    if (message['user_id'] != _uid) return;
    final failed = message['_status'] == 'failed';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 8),
            if (failed)
              ListTile(
                onTap: () {
                  Navigator.pop(sheetContext);
                  _store.retry(_gid, message);
                },
                leading: Icon(Icons.refresh_rounded,
                    color: AppAccentColors.accent),
                title: Text(
                  'Erneut senden',
                  style: TextStyle(
                    color: AppAccentColors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ListTile(
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteMessage(message);
              },
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              title: const Text(
                'Löschen',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final target = _scrollCtrl.position.maxScrollExtent;
      if (jump) {
        _scrollCtrl.jumpTo(target);
      } else {
        _scrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = _store.messagesFor(_gid);
    if (_loading && messages.isEmpty) {
      return const SkeletonChat();
    }
    return Column(
      children: [
        Expanded(child: _buildMessages(messages)),
        _buildComposer(),
      ],
    );
  }

  Widget _buildMessages(List<Map<String, dynamic>> messages) {
    if (messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.forum_outlined, color: Colors.grey[700], size: 46),
              const SizedBox(height: 12),
              const Text(
                'Noch keine Nachrichten',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Schreib der Gruppe — Treffpunkt, Tempo, alles klären.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final prev = index > 0 ? messages[index - 1] : null;
        // Aufeinanderfolgende Nachrichten desselben Absenders gruppieren:
        // Avatar/Name nur beim ERSTEN einer Serie, dazwischen enger.
        final sameSenderAsPrev = prev != null &&
            prev['user_id'] == message['user_id'] &&
            !_breaksGroup(prev, message);
        return _buildBubble(message, groupedWithPrev: sameSenderAsPrev);
      },
    );
  }

  // > 5 Min Abstand bricht die Gruppierung (frischer Block).
  bool _breaksGroup(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ta = DateTime.tryParse(a['created_at']?.toString() ?? '');
    final tb = DateTime.tryParse(b['created_at']?.toString() ?? '');
    if (ta == null || tb == null) return false;
    return tb.difference(ta).inMinutes.abs() > 5;
  }

  Widget _buildBubble(
    Map<String, dynamic> message, {
    required bool groupedWithPrev,
  }) {
    final isMine = message['user_id'] == _uid;
    final rawProfile = message['profiles'];
    final profile = rawProfile is Map
        ? Map<String, dynamic>.from(rawProfile)
        : <String, dynamic>{};
    final name = GroupChatService.displayName(
      profile,
      fallbackUserId: message['user_id'] as String?,
    );
    final body = message['body']?.toString() ?? '';
    final time = _formatTime(message['created_at'] as String?);
    final status = message['_status'];
    final sending = status == 'sending';
    final failed = status == 'failed';

    return Padding(
      padding: EdgeInsets.only(top: groupedWithPrev ? 2 : 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: isMine ? () => _messageActions(message) : null,
        onTap: failed ? () => _store.retry(_gid, message) : null,
        child: Row(
          mainAxisAlignment:
              isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine)
              SizedBox(
                width: 32,
                child: groupedWithPrev
                    ? null
                    : UserAvatar.fromProfile(
                        profile,
                        fallbackName: name,
                        radius: 16,
                      ),
              ),
            if (!isMine) const SizedBox(width: 8),
            Flexible(
              flex: 8,
              child: Opacity(
                opacity: sending ? 0.72 : 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    gradient: isMine && !failed
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppAccentColors.accent,
                              Color.lerp(AppAccentColors.accent,
                                  Colors.black, 0.18)!,
                            ],
                          )
                        : null,
                    color: failed
                        ? const Color(0xFF3A1D22)
                        : isMine
                        ? null
                        : const Color(0xFF1C1F26),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(isMine || groupedWithPrev ? 16 : 5),
                      topRight: Radius.circular(!isMine || groupedWithPrev ? 16 : 5),
                      bottomLeft: const Radius.circular(16),
                      bottomRight: const Radius.circular(16),
                    ),
                    border: failed
                        ? Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.55),
                          )
                        : isMine
                        ? null
                        : Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isMine && !groupedWithPrev)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppAccentColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      Text(
                        body,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          height: 1.34,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            time,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.60),
                              fontSize: 10.5,
                            ),
                          ),
                          if (sending) ...[
                            const SizedBox(width: 5),
                            SizedBox(
                              width: 9,
                              height: 9,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.4,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ] else if (failed) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Colors.redAccent,
                              size: 12,
                            ),
                            const SizedBox(width: 3),
                            const Text(
                              'Tippen für erneut',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ] else if (isMine) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.done_all_rounded,
                              color: Colors.white.withValues(alpha: 0.60),
                              size: 12,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (isMine) const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF111620),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _messageCtrl,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.send,
                onChanged: (v) => _store.setDraft(_gid, v),
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Nachricht an die Gruppe',
                  hintStyle: const TextStyle(color: Colors.grey),
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFF0B0E14),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton.filled(
                onPressed: _send,
                style: IconButton.styleFrom(
                  backgroundColor: AppAccentColors.accent,
                ),
                icon: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? raw) {
    final dt = DateTime.tryParse(raw ?? '')?.toLocal();
    if (dt == null) return '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
