import 'dart:async';

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/group_chat_service.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

/// 2026-06-25 (vucko): Gruppen-Chat als einbettbares Panel (Lobby-Tab „Chat").
/// Mitglieder tauschen sich vor/nach der Fahrt aus. Realtime + Optimistic-Send,
/// gespiegelt vom Community-Chat. Eigene Nachrichten per Lang-Druck löschbar.
class GroupChatPanel extends StatefulWidget {
  const GroupChatPanel({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupChatPanel> createState() => _GroupChatPanelState();
}

class _GroupChatPanelState extends State<GroupChatPanel> {
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _channel;
  Timer? _reloadDebounce;
  bool _loading = true;
  bool _sending = false;
  int _localSeq = 0;

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _channel?.unsubscribe();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool scrollToBottom = true}) async {
    try {
      final messages = await GroupChatService.fetchMessages(widget.groupId);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
      });
      if (scrollToBottom) _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _subscribe() {
    _channel = GroupChatService.subscribeMessages(widget.groupId, () {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 160), () {
        if (mounted) _load();
      });
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;
    final uid = _uid;
    if (uid == null) return;

    final localId =
        'local-${DateTime.now().microsecondsSinceEpoch}-${_localSeq++}';
    final optimistic = <String, dynamic>{
      'id': localId,
      'group_id': widget.groupId,
      'user_id': uid,
      'body': text,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'deleted_at': null,
      'profiles': _myProfile(uid),
      '_pending': true,
    };

    setState(() {
      _sending = true;
      _messages = [..._messages, optimistic];
      _messageCtrl.clear();
    });
    _scrollToBottom();
    try {
      await GroupChatService.sendMessage(widget.groupId, text);
      unawaited(_load());
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages = _messages.where((m) => m['id'] != localId).toList();
          _messageCtrl.text = text;
        });
        _toast('Nachricht konnte nicht gesendet werden.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
    if (id == null || id.isEmpty) return;
    if (id.startsWith('local-')) {
      setState(() => _messages = _messages.where((m) => m['id'] != id).toList());
      return;
    }
    final previous = List<Map<String, dynamic>>.from(_messages);
    setState(() => _messages = _messages.where((m) => m['id'] != id).toList());
    try {
      await GroupChatService.deleteMessage(id);
      unawaited(_load(scrollToBottom: false));
    } catch (_) {
      if (mounted) setState(() => _messages = previous);
      _toast('Nachricht konnte nicht gelöscht werden.');
    }
  }

  void _confirmDelete(Map<String, dynamic> message) {
    if (message['user_id'] != _uid) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ListTile(
          onTap: () {
            Navigator.pop(sheetContext);
            unawaited(_deleteMessage(message));
          },
          leading: const Icon(Icons.delete_outline_rounded,
              color: Colors.redAccent),
          title: const Text(
            'Nachricht löschen',
            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color(0xFF301B20),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: AppAccentColors.accent),
      );
    }
    return Column(
      children: [
        Expanded(child: _buildMessages()),
        _buildComposer(),
      ],
    );
  }

  Widget _buildMessages() {
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline, color: Colors.grey[700], size: 44),
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
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _buildBubble(_messages[index]),
    );
  }

  Widget _buildBubble(Map<String, dynamic> message) {
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
    final isPending = message['_pending'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: isMine ? () => _confirmDelete(message) : null,
        child: Row(
          mainAxisAlignment:
              isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine) ...[
              UserAvatar.fromProfile(profile, fallbackName: name, radius: 16),
              const SizedBox(width: 8),
            ],
            Flexible(
              flex: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: isMine
                      ? AppAccentColors.accent
                      : const Color(0xFF1C1F26),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(14),
                    topRight: const Radius.circular(14),
                    bottomLeft: Radius.circular(isMine ? 14 : 4),
                    bottomRight: Radius.circular(isMine ? 4 : 14),
                  ),
                  border: isMine
                      ? null
                      : Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMine)
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppAccentColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (!isMine) const SizedBox(height: 3),
                    Text(
                      body,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isPending ? '$time · sendet...' : time,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isMine) const SizedBox(width: 48),
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
                onPressed: _sending ? null : _send,
                style: IconButton.styleFrom(
                  backgroundColor: AppAccentColors.accent,
                  disabledBackgroundColor: Colors.grey[800],
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, color: Colors.white, size: 18),
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
