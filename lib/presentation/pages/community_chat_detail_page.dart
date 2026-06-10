import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

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
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _membersChannel;
  bool _loading = true;
  bool _sending = false;
  Timer? _reloadDebounce;

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
      _showError(e.toString());
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
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await CommunityChatService.sendMessage(widget.communityId, text);
      _messageCtrl.clear();
      await _load();
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _copyInviteCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Invite-Code kopiert.')));
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
      _showError(e.toString());
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
      _showError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final community = _community;
    final title = community?['name']?.toString() ?? 'Community';

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
              }
            },
            itemBuilder: (_) => [
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
          : Column(
              children: [
                if (community != null) _buildCommunityHeader(community),
                Expanded(child: _buildMessages()),
                _buildComposer(),
              ],
            ),
    );
  }

  Widget _buildCommunityHeader(Map<String, dynamic> community) {
    final isPublic = community['is_public'] == true;
    final memberCount = CommunityChatService.memberCount(community);
    final inviteCode = community['invite_code']?.toString();
    final canInvite = CommunityChatService.canInvite(community);

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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildMetaPill(
                icon: isPublic ? Icons.public : Icons.lock_outline,
                label: isPublic ? 'Öffentlich' : 'Privat',
                color: isPublic ? Colors.greenAccent : Colors.orangeAccent,
              ),
              _buildMetaPill(
                icon: Icons.people_outline,
                label: '$memberCount Mitglieder',
                color: Colors.white70,
                onTap: _showMembersSheet,
              ),
            ],
          ),
          if (canInvite && inviteCode != null && inviteCode.isNotEmpty) ...[
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
    VoidCallback? onTap,
  }) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
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
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return pill;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: pill,
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
              Icon(
                Icons.chat_bubble_outline,
                color: Colors.grey[700],
                size: 44,
              ),
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
                'Schreib die erste Nachricht in diese Community.',
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
      itemBuilder: (context, index) {
        return _buildMessageBubble(_messages[index]);
      },
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            UserAvatar.fromProfile(profile, fallbackName: name, radius: 16),
            const SizedBox(width: 8),
          ],
          Flexible(
            flex: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
                    time,
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
                maxLength: AppInputLimits.communityMessageMaxLength,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Nachricht schreiben',
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
                    : const Icon(Icons.send, color: Colors.white, size: 18),
              ),
            ),
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

class CommunityMembersSheet extends StatefulWidget {
  const CommunityMembersSheet({
    required this.communityId,
    required this.initialMembers,
    required this.onChanged,
    super.key,
  });

  final String communityId;
  final List<Map<String, dynamic>> initialMembers;
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
      _showError(e.toString());
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
      _showError(e.toString());
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
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
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
