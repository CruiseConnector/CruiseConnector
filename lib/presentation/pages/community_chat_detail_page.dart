import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/widgets/mentions.dart';
import 'package:cruise_connect/presentation/widgets/social/route_attachment_card.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

enum _CommunityChatPostFilter { all, groupRides, sharedRoutes }

const _communityChatTopicMentions = {
  'gruppe',
  'gruppen',
  'gruppenfahrt',
  'gruppenfahrten',
  'gruppenfahert',
  'geteilteroute',
};

class CommunityChatDetailPage extends StatefulWidget {
  const CommunityChatDetailPage({super.key, required this.communityId});

  final String communityId;

  @override
  State<CommunityChatDetailPage> createState() =>
      _CommunityChatDetailPageState();
}

class _CommunityChatDetailPageState extends State<CommunityChatDetailPage> {
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  Map<String, dynamic>? _community;
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _members = [];
  final Map<String, GlobalKey> _messageKeys = {};
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _membersChannel;
  bool _loading = true;
  bool _sending = false;
  int _localMessageSeq = 0;
  Map<String, dynamic>? _replyToMessage;
  SavedRoute? _attachedRoute;
  Timer? _reloadDebounce;
  _CommunityChatPostFilter _postFilter = _CommunityChatPostFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeMessages();
    _subscribeMembers();
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _messagesChannel?.unsubscribe();
    _membersChannel?.unsubscribe();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool scrollToBottom = true}) async {
    try {
      final community = await CommunityChatService.fetchCommunity(
        widget.communityId,
      );
      final messages = await CommunityChatService.fetchMessages(
        widget.communityId,
      );
      final members = await CommunityChatService.fetchMembers(
        widget.communityId,
      );
      if (!mounted) return;
      setState(() {
        _community = community;
        _messages = messages;
        _members = members;
        _loading = false;
      });
      if (scrollToBottom) _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(e, fallback: 'Community konnte nicht geladen werden.');
    }
  }

  void _subscribeMessages() {
    _messagesChannel = CommunityChatService.subscribeMessages(
      widget.communityId,
      () {
        _reloadDebounce?.cancel();
        _reloadDebounce = Timer(const Duration(milliseconds: 160), () {
          if (mounted) _load();
        });
      },
    );
  }

  void _subscribeMembers() {
    _membersChannel = CommunityChatService.subscribeMembers(
      widget.communityId,
      () {
        _reloadDebounce?.cancel();
        _reloadDebounce = Timer(const Duration(milliseconds: 160), () {
          if (mounted) _load(scrollToBottom: false);
        });
      },
    );
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _messageCtrl.text.trim();
    final attachedRoute = _attachedRoute;
    if (text.isEmpty && attachedRoute == null) return;

    final replyTo = _replyToMessage;
    final routeAttachment = attachedRoute == null
        ? null
        : _routeAttachmentFor(attachedRoute);
    if (routeAttachment != null) {
      final alreadyPosted =
          await CommunityChatService.hasOwnRoutePostForCommunity(
            communityId: widget.communityId,
            routeId: routeAttachment['route_id'].toString(),
          );
      if (alreadyPosted) {
        _showError(
          const CommunityChatServiceException(
            CommunityChatService.duplicateRoutePostMessage,
          ),
          fallback: CommunityChatService.duplicateRoutePostMessage,
        );
        return;
      }
    }
    final replyToId = replyTo?['id']?.toString();
    final persistedReplyToId =
        replyToId == null || replyToId.startsWith('local-') ? null : replyToId;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final body = text.isEmpty ? 'Route geteilt' : text;
    final localId =
        'local-${DateTime.now().microsecondsSinceEpoch}-${_localMessageSeq++}';
    final optimistic = <String, dynamic>{
      'id': localId,
      'community_id': widget.communityId,
      'user_id': uid,
      'body': body,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'deleted_at': null,
      if (persistedReplyToId != null) 'reply_to_message_id': persistedReplyToId,
      if (routeAttachment != null) 'route_attachment': routeAttachment,
      'profiles': _profileForUser(uid),
      '_pending': true,
    };

    setState(() {
      _sending = true;
      _messages = [..._messages, optimistic];
      _messageCtrl.clear();
      _replyToMessage = null;
      _attachedRoute = null;
    });
    _scrollToBottom();
    try {
      await CommunityChatService.sendMessage(
        widget.communityId,
        body,
        replyToMessageId: persistedReplyToId,
        routeAttachment: routeAttachment,
      );
      unawaited(_load());
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages = _messages
              .where((message) => message['id'] != localId)
              .toList();
          _replyToMessage = replyTo;
          _attachedRoute = attachedRoute;
          _messageCtrl.text = text;
        });
      }
      _showError(e, fallback: 'Nachricht konnte nicht gesendet werden.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Map<String, dynamic> _profileForUser(String userId) {
    for (final member in _members) {
      if (member['user_id'] == userId) {
        final raw = member['profiles'];
        if (raw is Map) return Map<String, dynamic>.from(raw);
      }
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user?.id == userId) {
      final meta = user?.userMetadata ?? const <String, dynamic>{};
      return {
        'id': userId,
        'username': meta['username'] ?? meta['name'] ?? user?.email,
        'email': user?.email,
        'avatar_url': meta['avatar_url'],
      };
    }
    return {'id': userId};
  }

  Map<String, dynamic> _routeAttachmentFor(SavedRoute route) {
    return {
      'route_id': route.id,
      'title': route.name ?? route.style,
      'style': route.style,
      'distance_km': route.distanceKm,
      if (route.durationSeconds != null)
        'duration_seconds': route.durationSeconds,
      if (route.sourceRouteId != null) 'source_route_id': route.sourceRouteId,
    };
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

  String _friendlyError(Object error, String fallback) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    final isBackendNoise =
        lower.contains('postgrest') ||
        lower.contains('supabase') ||
        lower.contains('row-level') ||
        lower.contains('rls') ||
        lower.contains('policy') ||
        lower.contains('permission') ||
        lower.contains('schema cache') ||
        lower.contains('violates') ||
        lower.contains('duplicate key');
    if (raw.trim().isEmpty || isBackendNoise) return fallback;
    return raw.length > 110 ? fallback : raw;
  }

  void _showError(
    Object error, {
    String fallback = 'Aktion gerade nicht möglich.',
  }) {
    _showToast(_friendlyError(error, fallback), error: true);
  }

  void _showToast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: error
            ? const Color(0xFF301B20)
            : const Color(0xFF171B24),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1250),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Future<void> _copyInviteCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    _showToast('Code kopiert.');
  }

  void _showMembersSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CommunityMembersSheet(
        communityId: widget.communityId,
        initialMembers: _members,
        ownerOnlyMessages: _community?['owner_only_messages'] == true,
        onChanged: () => _load(scrollToBottom: false),
      ),
    );
  }

  String? get _myRole {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return null;
    for (final member in _members) {
      if (member['user_id'] == uid) return member['role']?.toString();
    }
    return null;
  }

  bool get _amAdmin => _myRole == 'owner';
  bool get _canPinMessages => CommunityChatService.canModerate(_myRole);
  bool get _canWrite {
    if (_community?['owner_only_messages'] != true) return true;
    return CommunityChatService.canModerate(_myRole);
  }

  Map<String, dynamic>? _messageById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final message in _messages) {
      if (message['id']?.toString() == id) return message;
    }
    return null;
  }

  Map<String, dynamic>? _routeAttachmentFrom(Map<String, dynamic> message) {
    final raw = message['route_attachment'];
    if (raw is! Map) return null;
    final attachment = Map<String, dynamic>.from(raw);
    final routeId = attachment['route_id']?.toString();
    if (routeId == null || routeId.isEmpty) return null;
    return attachment;
  }

  Future<void> _copyMessage(Map<String, dynamic> message) async {
    final body = message['body']?.toString() ?? '';
    final route = _routeAttachmentFrom(message);
    final value = route == null
        ? body
        : [
            if (body.isNotEmpty) body,
            'Route: ${route['title'] ?? route['route_id']}',
          ].join('\n');
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    _showToast('Nachricht kopiert.');
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    final id = message['id']?.toString();
    if (id == null || id.isEmpty) return;
    if (id.startsWith('local-')) {
      setState(() {
        _messages = _messages.where((entry) => entry['id'] != id).toList();
      });
      return;
    }
    final previous = List<Map<String, dynamic>>.from(_messages);
    setState(() {
      _messages = _messages.where((entry) => entry['id'] != id).toList();
    });
    try {
      await CommunityChatService.deleteMessage(id);
      unawaited(_load(scrollToBottom: false));
    } catch (e) {
      if (mounted) setState(() => _messages = previous);
      _showError(e, fallback: 'Nachricht konnte nicht gelöscht werden.');
    }
  }

  Future<void> _setMessagePinned(
    Map<String, dynamic> message, {
    required bool pinned,
  }) async {
    final id = message['id']?.toString();
    if (id == null || id.isEmpty || id.startsWith('local-')) return;
    final previous = List<Map<String, dynamic>>.from(_messages);
    setState(() {
      _messages = _messages.map((entry) {
        if (entry['id']?.toString() != id) return entry;
        return {
          ...entry,
          'pinned_at': pinned ? DateTime.now().toUtc().toIso8601String() : null,
          'pinned_by': pinned
              ? Supabase.instance.client.auth.currentUser?.id
              : null,
        };
      }).toList();
    });
    try {
      await CommunityChatService.setMessagePinned(
        messageId: id,
        pinned: pinned,
      );
      unawaited(_load(scrollToBottom: false));
      _showToast(pinned ? 'Post angepinnt.' : 'Pin entfernt.');
    } catch (e) {
      if (mounted) setState(() => _messages = previous);
      _showError(e, fallback: 'Pin konnte nicht gespeichert werden.');
    }
  }

  void _showMessageActions(Map<String, dynamic> message) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final isMine = message['user_id'] == uid;
    final canDelete = isMine || CommunityChatService.canModerate(_myRole);
    final isPinned = message['pinned_at'] != null;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                _MessageActionTile(
                  icon: Icons.reply_rounded,
                  label: 'Antworten',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    setState(() => _replyToMessage = message);
                  },
                ),
                _MessageActionTile(
                  icon: Icons.copy_rounded,
                  label: 'Kopieren',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_copyMessage(message));
                  },
                ),
                if (_canPinMessages)
                  _MessageActionTile(
                    icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    label: isPinned ? 'Pin entfernen' : 'Anpinnen',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_setMessagePinned(message, pinned: !isPinned));
                    },
                  ),
                if (canDelete)
                  _MessageActionTile(
                    icon: Icons.delete_outline_rounded,
                    label: 'Löschen',
                    destructive: true,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_deleteMessage(message));
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRoutePicker() async {
    final route = await showModalBottomSheet<SavedRoute>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.68,
            child: FutureBuilder<List<SavedRoute>>(
              future: SavedRoutesService.getSavedRouteLibrary(),
              builder: (context, snapshot) {
                final routes = snapshot.data ?? const <SavedRoute>[];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 14),
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: Text(
                        'Route anhängen',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      Expanded(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppAccentColors.accent,
                          ),
                        ),
                      )
                    else if (routes.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Noch keine gespeicherten Routen.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                          itemCount: routes.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final route = routes[index];
                            return InkWell(
                              onTap: () => Navigator.pop(sheetContext, route),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F121A),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.07),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.route_rounded,
                                      color: AppAccentColors.accent,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${route.styleEmoji} ${route.name ?? route.style}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${route.formattedDistance} · ${route.formattedDuration}',
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
    if (route == null || !mounted) return;
    setState(() => _attachedRoute = route);
  }

  void _scrollToMessage(String? messageId) {
    if (messageId == null || messageId.isEmpty) return;
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.30,
      );
      return;
    }
    final visibleMessages = _visibleMessages();
    final index = visibleMessages.indexWhere(
      (message) => message['id']?.toString() == messageId,
    );
    if (index < 0 || !_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      (index * 86.0).clamp(0.0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _confirmLeaveCommunity() async {
    final isAdmin = _amAdmin;
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151821),
        title: const Text(
          'Community verlassen?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          isAdmin
              ? 'Wenn du gehst, wird automatisch das Mitglied Admin, das als naechstes beigetreten ist.'
              : 'Du verlaesst diese Community und kannst danach nicht mehr mitschreiben.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Verlassen',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (shouldLeave != true) return;

    try {
      await CommunityChatService.leaveCommunity(widget.communityId);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _showError(e, fallback: 'Community konnte nicht verlassen werden.');
    }
  }

  Future<void> _confirmDeleteCommunity() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151821),
        title: const Text(
          'Community loeschen?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Diese Community, alle Mitglieder und Nachrichten werden dauerhaft geloescht.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Loeschen',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;

    try {
      await CommunityChatService.deleteCommunity(widget.communityId);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _showError(e, fallback: 'Community konnte nicht gelöscht werden.');
    }
  }

  Future<void> _toggleOwnerOnlyMessages() async {
    final community = _community;
    if (community == null) return;
    final current = community['owner_only_messages'] == true;
    final next = !current;
    setState(() {
      _community = {...community, 'owner_only_messages': next};
    });
    try {
      await CommunityChatService.setOwnerOnlyMessages(
        communityId: widget.communityId,
        enabled: next,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _community = {...community, 'owner_only_messages': current};
        });
      }
      _showError(e, fallback: 'Einstellung konnte nicht gespeichert werden.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final community = _community;
    final title = community?['name']?.toString() ?? 'Community';
    final ownerOnlyMessages = community?['owner_only_messages'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        foregroundColor: Colors.white,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Mitglieder',
            onPressed: _showMembersSheet,
            icon: const Icon(Icons.people_outline, color: Colors.white),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: Colors.white),
            color: const Color(0xFF1C1F26),
            onSelected: (value) {
              if (value == 'leave') {
                _confirmLeaveCommunity();
              } else if (value == 'delete') {
                _confirmDeleteCommunity();
              } else if (value == 'owner_only') {
                _toggleOwnerOnlyMessages();
              }
            },
            itemBuilder: (_) => [
              if (_amAdmin)
                PopupMenuItem(
                  value: 'owner_only',
                  child: Row(
                    children: [
                      Icon(
                        ownerOnlyMessages
                            ? Icons.chat_bubble_outline
                            : Icons.admin_panel_settings_outlined,
                        color: Colors.white70,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ownerOnlyMessages
                              ? 'Alle schreiben lassen'
                              : 'Nur Owner schreibt',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_amAdmin) const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.redAccent, size: 18),
                    SizedBox(width: 10),
                    Text(
                      'Verlassen',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
              if (_amAdmin) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Community loeschen',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: AppAccentColors.accent),
            )
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: Column(
                children: [
                  if (community != null) _buildCommunityHeader(community),
                  _buildPostFilters(),
                  Expanded(child: _buildMessages()),
                  _buildComposer(),
                ],
              ),
            ),
    );
  }

  Widget _buildCommunityHeader(Map<String, dynamic> community) {
    final isPublic = community['is_public'] == true;
    final memberCount = CommunityChatService.memberCount(community);
    final inviteCode = community['invite_code']?.toString();
    final canInvite = CommunityChatService.canInvite(community);
    final ownerOnlyMessages = community['owner_only_messages'] == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111620),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildMetaPill(
                  icon: isPublic ? Icons.public : Icons.lock_outline,
                  label: isPublic ? 'Öffentlich' : 'Privat',
                  color: isPublic ? Colors.greenAccent : Colors.orangeAccent,
                ),
                const SizedBox(width: 8),
                _buildMetaPill(
                  icon: Icons.people_outline,
                  trailingIcon: ownerOnlyMessages
                      ? Icons.admin_panel_settings_outlined
                      : null,
                  label: '$memberCount Mitglieder',
                  color: Colors.white70,
                  trailingColor: ownerOnlyMessages ? Colors.orangeAccent : null,
                  onTap: _showMembersSheet,
                ),
              ],
            ),
          ),
          if (!isPublic &&
              canInvite &&
              inviteCode != null &&
              inviteCode.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => _copyInviteCode(inviteCode),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppAccentColors.accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppAccentColors.accent.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.key, color: AppAccentColors.accent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        inviteCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const Icon(Icons.copy, color: Colors.white70, size: 17),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaPill({
    required IconData icon,
    required String label,
    required Color color,
    IconData? trailingIcon,
    Color? trailingColor,
    VoidCallback? onTap,
  }) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 6),
            Icon(trailingIcon, color: trailingColor ?? color, size: 13),
          ],
        ],
      ),
    );
    if (onTap == null) return pill;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: pill,
    );
  }

  Widget _buildPostFilters() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _buildPostFilterChip(
              filter: _CommunityChatPostFilter.all,
              icon: Icons.auto_awesome_motion_outlined,
              label: 'Alles',
            ),
            const SizedBox(width: 8),
            _buildPostFilterChip(
              filter: _CommunityChatPostFilter.groupRides,
              icon: Icons.groups_2_outlined,
              label: '@Gruppenfahrten',
            ),
            const SizedBox(width: 8),
            _buildPostFilterChip(
              filter: _CommunityChatPostFilter.sharedRoutes,
              icon: Icons.route_outlined,
              label: 'Geteilte Routen',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostFilterChip({
    required _CommunityChatPostFilter filter,
    required IconData icon,
    required String label,
  }) {
    final selected = _postFilter == filter;
    return InkWell(
      onTap: () => setState(() => _postFilter = filter),
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppAccentColors.accent.withValues(alpha: 0.18)
              : const Color(0xFF151821),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppAccentColors.accent
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: selected ? AppAccentColors.accent : Colors.white60,
              size: 17,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _visibleMessages() {
    final filtered = switch (_postFilter) {
      _CommunityChatPostFilter.all => _messages.toList(),
      _CommunityChatPostFilter.groupRides =>
        _messages.where(_messageMatchesGroupRide).toList(),
      _CommunityChatPostFilter.sharedRoutes =>
        _messages
            .where((message) => _routeAttachmentFrom(message) != null)
            .toList(),
    };
    filtered.sort((a, b) {
      final aPinned = a['pinned_at'] != null;
      final bPinned = b['pinned_at'] != null;
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      if (aPinned && bPinned) {
        final ap =
            DateTime.tryParse(a['pinned_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bp =
            DateTime.tryParse(b['pinned_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bp.compareTo(ap);
      }
      return _messageDate(a).compareTo(_messageDate(b));
    });
    return filtered;
  }

  DateTime _messageDate(Map<String, dynamic> message) {
    return DateTime.tryParse(message['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool _messageMatchesGroupRide(Map<String, dynamic> message) {
    final body = (message['body'] ?? '').toString().toLowerCase();
    return RegExp(
          r'@(gruppe|gruppen|gruppenfahrt|gruppenfahrten|gruppenfahert)\b',
          caseSensitive: false,
        ).hasMatch(body) ||
        body.contains('gruppenfahrt') ||
        body.contains('gruppen fahr');
  }

  int _replyCountFor(String? messageId) {
    if (messageId == null || messageId.isEmpty) return 0;
    return _messages
        .where(
          (message) => message['reply_to_message_id']?.toString() == messageId,
        )
        .length;
  }

  String _postTopicLabel(Map<String, dynamic> message) {
    if (_routeAttachmentFrom(message) != null) return 'r/GeteilteRouten';
    if (_messageMatchesGroupRide(message)) return 'r/Gruppenfahrten';
    final raw = (_community?['name'] ?? 'Community').toString().trim();
    final compact = raw.replaceAll(RegExp(r'\s+'), '');
    return 'r/${compact.isEmpty ? 'Community' : compact}';
  }

  Widget _buildMessages() {
    final visibleMessages = _visibleMessages();
    if (visibleMessages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.article_outlined, color: Colors.grey[700], size: 44),
              const SizedBox(height: 12),
              Text(
                _postFilter == _CommunityChatPostFilter.all
                    ? 'Noch keine Posts'
                    : 'Keine passenden Posts',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _postFilter == _CommunityChatPostFilter.groupRides
                    ? 'Nutze Tags wie @Gruppenfahrt oder @Gruppenfahrten.'
                    : _postFilter == _CommunityChatPostFilter.sharedRoutes
                    ? 'Hänge eine gespeicherte Route an deinen Post.'
                    : 'Schreib den ersten Post in diese Community.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
      itemCount: visibleMessages.length,
      itemBuilder: (context, index) {
        final message = visibleMessages[index];
        final id = message['id']?.toString();
        final key = id == null
            ? null
            : _messageKeys.putIfAbsent(id, GlobalKey.new);
        return KeyedSubtree(key: key, child: _buildCommunityPostCard(message));
      },
    );
  }

  Widget _buildCommunityPostCard(Map<String, dynamic> message) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final isMine = message['user_id'] == uid;
    final rawProfile = message['profiles'];
    final profile = rawProfile is Map
        ? Map<String, dynamic>.from(rawProfile)
        : <String, dynamic>{};
    final name = CommunityChatService.displayName(
      profile,
      fallbackUserId: message['user_id'] as String?,
    );
    final body = message['body']?.toString() ?? '';
    final time = _formatMessageTime(message['created_at'] as String?);
    final isPending = message['_pending'] == true;
    final replyToId = message['reply_to_message_id']?.toString();
    final repliedMessage = _messageById(replyToId);
    final routeAttachment = _routeAttachmentFrom(message);
    final messageId = message['id']?.toString();
    final replies = _replyCountFor(messageId);
    final isPinned = message['pinned_at'] != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => _showMessageActions(message),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF151821),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isPinned
                  ? AppAccentColors.accent.withValues(alpha: 0.46)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isPinned) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppAccentColors.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.push_pin,
                          color: AppAccentColors.accent,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Angepinnt',
                          style: TextStyle(
                            color: AppAccentColors.accent,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 9),
                ],
                Row(
                  children: [
                    UserAvatar.fromProfile(
                      profile,
                      fallbackName: name,
                      radius: 14,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_postTopicLabel(message)} · $name · $time',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isMine)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppAccentColors.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          isPending ? 'sendet...' : 'Du',
                          style: TextStyle(
                            color: AppAccentColors.accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Aktionen',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _showMessageActions(message),
                      icon: const Icon(
                        Icons.more_horiz,
                        color: Colors.white54,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                if (replyToId != null && replyToId.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _scrollToMessage(replyToId),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0E14),
                        borderRadius: BorderRadius.circular(9),
                        border: Border(
                          left: BorderSide(
                            color: AppAccentColors.accent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        repliedMessage?['body']?.toString() ??
                            'Antwort anzeigen',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 11.5,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.38,
                        fontWeight: FontWeight.w700,
                      ),
                      children: buildMentionSpans(
                        context: context,
                        text: body,
                        baseStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.38,
                          fontWeight: FontWeight.w700,
                        ),
                        plainMentions: _communityChatTopicMentions,
                      ),
                    ),
                  ),
                ],
                if (routeAttachment != null) ...[
                  const SizedBox(height: 12),
                  RouteAttachmentCard(
                    routeId: routeAttachment['route_id'].toString(),
                    compact: true,
                    showRideButton: true,
                    fallbackTitle: routeAttachment['title']?.toString(),
                    fallbackStyle: routeAttachment['style']?.toString(),
                    fallbackDistanceKm: (routeAttachment['distance_km'] as num?)
                        ?.toDouble(),
                    fallbackDurationSeconds:
                        (routeAttachment['duration_seconds'] as num?)
                            ?.toDouble(),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _PostAction(
                      icon: Icons.mode_comment_outlined,
                      label: replies == 1 ? '1 Antwort' : '$replies Antworten',
                      onTap: () => setState(() => _replyToMessage = message),
                    ),
                    _PostAction(
                      icon: Icons.reply_rounded,
                      label: 'Antworten',
                      onTap: () => setState(() => _replyToMessage = message),
                    ),
                    _PostAction(
                      icon: Icons.copy_rounded,
                      label: 'Kopieren',
                      onTap: () => unawaited(_copyMessage(message)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _insertComposerTag(String tag) {
    final text = _messageCtrl.text;
    final needsSpace = text.isNotEmpty && !RegExp(r'\s$').hasMatch(text);
    final next = '$text${needsSpace ? ' ' : ''}$tag ';
    if (next.length > AppInputLimits.communityMessageMaxLength) return;
    _messageCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  Widget _buildComposerTag(String tag) {
    return ActionChip(
      onPressed: () => _insertComposerTag(tag),
      avatar: Icon(
        Icons.alternate_email_rounded,
        color: AppAccentColors.accent,
        size: 15,
      ),
      label: Text(tag),
      labelStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
      backgroundColor: const Color(0xFF0B0E14),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildComposer() {
    final canWrite = _canWrite;
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyToMessage != null) ...[
              _ComposerPreview(
                icon: Icons.reply_rounded,
                title: 'Antwort auf Post',
                text: _replyToMessage?['body']?.toString() ?? 'Post',
                onClear: () => setState(() => _replyToMessage = null),
              ),
              const SizedBox(height: 8),
            ],
            if (_attachedRoute != null) ...[
              _ComposerPreview(
                icon: Icons.route_rounded,
                title: 'Route am Post',
                text:
                    '${_attachedRoute!.styleEmoji} ${_attachedRoute!.name ?? _attachedRoute!.style}',
                onClear: () => setState(() => _attachedRoute = null),
              ),
              const SizedBox(height: 8),
            ],
            if (!canWrite)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0E14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.admin_panel_settings_outlined,
                      color: AppAccentColors.accent.withValues(alpha: 0.78),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Nur Admins können hier posten.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildComposerTag('@Gruppenfahrt'),
                      const SizedBox(width: 8),
                      _buildComposerTag('@Gruppenfahrten'),
                      const SizedBox(width: 8),
                      _buildComposerTag('@Gruppen'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton(
                      tooltip: 'Route anhängen',
                      onPressed: _showRoutePicker,
                      icon: Icon(
                        Icons.add_link_rounded,
                        color: AppAccentColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _messageCtrl,
                      maxLength: AppInputLimits.communityMessageMaxLength,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Post schreiben',
                        hintStyle: const TextStyle(color: Colors.grey),
                        counterText: '',
                        filled: true,
                        fillColor: const Color(0xFF0B0E14),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
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
                          : const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 18,
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatMessageTime(String? raw) {
    final dt = DateTime.tryParse(raw ?? '')?.toLocal();
    if (dt == null) return '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _PostAction extends StatelessWidget {
  const _PostAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.grey, size: 18),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerPreview extends StatelessWidget {
  const _ComposerPreview({
    required this.icon,
    required this.title,
    required this.text,
    required this.onClear,
  });

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppAccentColors.accent, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _MessageActionTile extends StatelessWidget {
  const _MessageActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.redAccent : Colors.white;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class CommunityMembersSheet extends StatefulWidget {
  const CommunityMembersSheet({
    required this.communityId,
    required this.initialMembers,
    required this.ownerOnlyMessages,
    required this.onChanged,
    super.key,
  });

  final String communityId;
  final List<Map<String, dynamic>> initialMembers;
  final bool ownerOnlyMessages;
  final Future<void> Function() onChanged;

  @override
  State<CommunityMembersSheet> createState() => _CommunityMembersSheetState();
}

class _CommunityMembersSheetState extends State<CommunityMembersSheet> {
  List<Map<String, dynamic>> _members = [];
  bool _loading = false;
  String? _busyUserId;

  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  String? get _myRole {
    final uid = _myId;
    if (uid == null) return null;
    for (final member in _members) {
      if (member['user_id'] == uid) return member['role']?.toString();
    }
    return null;
  }

  bool get _amAdmin => _myRole == 'owner';
  bool get _amModerator => _myRole == 'moderator';

  @override
  void initState() {
    super.initState();
    _members = widget.initialMembers;
    if (_members.isEmpty) _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _loading = true);
    try {
      final members = await CommunityChatService.fetchMembers(
        widget.communityId,
      );
      if (!mounted) return;
      setState(() {
        _members = members;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(e);
    }
  }

  Future<void> _setRole(String userId, String role) async {
    setState(() => _busyUserId = userId);
    try {
      await CommunityChatService.setMemberRole(
        communityId: widget.communityId,
        userId: userId,
        role: role,
      );
      await _loadMembers();
      await widget.onChanged();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  Future<void> _removeMember(String userId) async {
    setState(() => _busyUserId = userId);
    try {
      await CommunityChatService.removeMember(
        communityId: widget.communityId,
        userId: userId,
      );
      await _loadMembers();
      await widget.onChanged();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  String _friendlyError(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    final isBackendNoise =
        lower.contains('postgrest') ||
        lower.contains('supabase') ||
        lower.contains('row-level') ||
        lower.contains('rls') ||
        lower.contains('policy') ||
        lower.contains('permission') ||
        lower.contains('schema cache') ||
        lower.contains('violates');
    if (raw.trim().isEmpty || isBackendNoise || raw.length > 110) {
      return 'Aktion gerade nicht möglich.';
    }
    return raw;
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _friendlyError(error),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: const Color(0xFF301B20),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1350),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.72;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Mitglieder',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _roleChip(_myRole, compact: true),
                ],
              ),
            ),
            if (widget.ownerOnlyMessages)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.orangeAccent.withValues(alpha: 0.22),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.admin_panel_settings_outlined,
                        color: Colors.orangeAccent,
                        size: 17,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Nur Admins können in diesem Chat schreiben.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: AppAccentColors.accent,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                      itemBuilder: (context, index) =>
                          _buildMemberTile(_members[index]),
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                      itemCount: _members.length,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member) {
    final profile = _profile(member);
    final userId = member['user_id']?.toString() ?? '';
    final role = member['role']?.toString();
    final isMe = userId == _myId;
    final name = CommunityChatService.displayName(
      profile,
      fallbackUserId: userId,
    );
    final busy = _busyUserId == userId;
    final actions = _actionsFor(member);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      leading: UserAvatar.fromProfile(profile, fallbackName: name, radius: 22),
      title: Row(
        children: [
          Expanded(
            child: Text(
              isMe ? '$name · Du' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: _roleChip(role),
      ),
      trailing: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : actions.isEmpty
          ? null
          : PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, color: Colors.white70),
              color: const Color(0xFF1C1F26),
              onSelected: (value) {
                if (value == 'remove') {
                  _removeMember(userId);
                } else {
                  _setRole(userId, value);
                }
              },
              itemBuilder: (_) => actions,
            ),
    );
  }

  List<PopupMenuEntry<String>> _actionsFor(Map<String, dynamic> member) {
    final userId = member['user_id']?.toString();
    final role = member['role']?.toString();
    final isMe = userId == _myId;
    final entries = <PopupMenuEntry<String>>[];

    if (_amAdmin) {
      if (role != 'owner') {
        entries.add(
          _roleMenuItem('owner', Icons.admin_panel_settings, 'Admin'),
        );
      }
      if (role != 'moderator') {
        entries.add(_roleMenuItem('moderator', Icons.shield, 'Moderator'));
      }
      if (role != 'member') {
        entries.add(_roleMenuItem('member', Icons.person, 'User'));
      }
      if (!isMe) {
        entries.add(const PopupMenuDivider());
        entries.add(_removeMenuItem());
      }
      return entries;
    }

    if (_amModerator && !isMe && role == 'member') {
      entries.add(_removeMenuItem());
    }
    return entries;
  }

  PopupMenuItem<String> _roleMenuItem(
    String value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: AppAccentColors.accent, size: 18),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  PopupMenuItem<String> _removeMenuItem() {
    return const PopupMenuItem(
      value: 'remove',
      child: Row(
        children: [
          Icon(Icons.person_remove_outlined, color: Colors.redAccent, size: 18),
          SizedBox(width: 10),
          Text('Entfernen', style: TextStyle(color: Colors.redAccent)),
        ],
      ),
    );
  }

  Widget _roleChip(String? role, {bool compact = false}) {
    final color = _roleColor(role);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 8,
        vertical: compact ? 5 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_roleIcon(role), color: color, size: compact ? 14 : 12),
          const SizedBox(width: 5),
          Text(
            CommunityChatService.roleLabel(role),
            style: TextStyle(
              color: color,
              fontSize: compact ? 12 : 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'owner':
        return Colors.redAccent;
      case 'moderator':
        return Colors.lightBlueAccent;
      default:
        return Colors.white70;
    }
  }

  IconData _roleIcon(String? role) {
    switch (role) {
      case 'owner':
        return Icons.admin_panel_settings;
      case 'moderator':
        return Icons.shield;
      default:
        return Icons.person;
    }
  }

  Map<String, dynamic>? _profile(Map<String, dynamic> member) {
    final profile = member['profiles'];
    if (profile is Map) return Map<String, dynamic>.from(profile);
    return null;
  }
}
