import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/services/cruise_group_service.dart';
import '../../data/services/social_service.dart';
import '../../domain/models/cruise_group.dart';
import '../../domain/models/group_member.dart';
import 'cruise_mode_page.dart';

/// Lobby vor dem gemeinsamen Start: zeigt Mitglieder, Rollen, Startbutton
/// für Owner — andere sehen "Warten auf Host...".
/// Wenn der Owner `is_active` auf true setzt, wechseln alle automatisch in
/// den [CruiseModePage]-Navigationsmodus.
class GroupLobbyPage extends StatefulWidget {
  const GroupLobbyPage({super.key, required this.groupId});
  final String groupId;

  @override
  State<GroupLobbyPage> createState() => _GroupLobbyPageState();
}

class _GroupLobbyPageState extends State<GroupLobbyPage> {
  CruiseGroup? _group;
  bool _loading = true;
  bool _starting = false;

  List<Map<String, dynamic>> _pendingRequests = [];
  /// Mitglieder, die ich blockiert habe oder die mich blockiert haben —
  /// werden in der Mitglieder-Liste ausgegraut dargestellt.
  Set<String> _blockedIds = {};

  RealtimeChannel? _groupCh;
  RealtimeChannel? _membersCh;

  String get _myId => Supabase.instance.client.auth.currentUser!.id;

  bool get _amOwner =>
      _group?.members.any(
        (m) => m.userId == _myId && m.role == MemberRole.owner,
      ) ??
      false;

  MemberRole get _myRole =>
      _group?.members
          .firstWhere(
            (m) => m.userId == _myId,
            orElse: () => GroupMember(
              id: '',
              groupId: widget.groupId,
              userId: _myId,
              role: MemberRole.passenger,
              createdAt: DateTime.now(),
            ),
          )
          .role ??
      MemberRole.passenger;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _groupCh?.unsubscribe();
    _membersCh?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        CruiseGroupService.fetch(widget.groupId),
        SocialService.getBlockedAndBlockerIds(),
      ]);
      final g = results[0] as CruiseGroup?;
      final blocked = results[1] as Set<String>;
      if (!mounted) return;
      setState(() {
        _group = g;
        _blockedIds = blocked;
        _loading = false;
      });
      if (g != null && g.isActive) _enterNavigation();
      // Pending-Requests nur laden, wenn ich Owner bin (RLS sorgt für Rest).
      if (g != null && g.isOwner(_myId)) {
        final pending = await SocialService.listPendingJoinRequests(
          widget.groupId,
        );
        if (!mounted) return;
        setState(() => _pendingRequests = pending);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  void _subscribe() {
    _groupCh = CruiseGroupService.subscribeGroup(widget.groupId, (row) {
      if (row['is_active'] == true) _enterNavigation();
      _load();
    });
    _membersCh = CruiseGroupService.subscribeMembers(
      widget.groupId,
      (_) => _load(),
    );
  }

  void _enterNavigation() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CruiseModePage(groupId: widget.groupId),
      ),
    );
  }

  Future<void> _startRoute() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await CruiseGroupService.activate(widget.groupId);
      // Eigener Realtime-Handler bringt uns in die Navigation.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Start fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _changeMyRole(MemberRole role) async {
    try {
      await CruiseGroupService.updateMemberRole(
        groupId: widget.groupId,
        userId: _myId,
        role: role,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<void> _promoteToOwner(GroupMember m) async {
    if (!_amOwner) return;
    await CruiseGroupService.updateMemberRole(
      groupId: widget.groupId,
      userId: m.userId,
      role: MemberRole.owner,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _group?.name ?? 'Lobby',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _group == null
          ? const Center(
              child: Text(
                'Gruppe nicht gefunden',
                style: TextStyle(color: Colors.white),
              ),
            )
          : _buildBody(),
      bottomNavigationBar: _loading || _group == null ? null : _buildBottom(),
    );
  }

  Widget _buildBody() {
    final g = _group!;
    final km = ((g.routeData?['distance_meters'] ?? 0) as num) / 1000;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (g.description != null && g.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    g.description!,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              Row(
                children: [
                  const Icon(
                    Icons.straighten,
                    color: Color(0xFFFF3B30),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${km.toStringAsFixed(1)} km',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(width: 20),
                  Icon(
                    g.isPublic ? Icons.public : Icons.lock,
                    color: const Color(0xFFFF3B30),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    g.isPublic ? 'Öffentlich' : 'Privat',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_shouldShowInviteCode()) ...[
          const SizedBox(height: 16),
          _buildInviteCodeCard(),
        ],
        if (_amOwner && _pendingRequests.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildPendingRequestsCard(),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Mitglieder (${g.members.length}/${g.maxPeople})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.person_add, color: Color(0xFFFF3B30)),
              onPressed: () => _showInviteDialog(), // Phase 3b — Friend-Picker
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...g.members.map(_buildMemberTile),
        const SizedBox(height: 24),
        const Text(
          'Meine Rolle',
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
        const SizedBox(height: 8),
        _buildRoleSelector(),
      ],
    );
  }

  /// Öffentliche Gruppen: Code für alle Mitglieder sichtbar.
  /// Private Gruppen: Code nur für Owner sichtbar.
  bool _shouldShowInviteCode() {
    final g = _group;
    if (g == null || g.inviteCode == null || g.inviteCode!.isEmpty) {
      return false;
    }
    if (g.isPublic) return true;
    return _amOwner;
  }

  Widget _buildInviteCodeCard() {
    final code = _group!.inviteCode!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFF3B30).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.qr_code_2, color: Color(0xFFFF3B30), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gruppen-Code',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Code kopieren',
            icon: const Icon(Icons.copy, color: Color(0xFFFF3B30)),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('$code kopiert')));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPendingRequestsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.how_to_reg, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Text(
                'Offene Beitritts-Anfragen (${_pendingRequests.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._pendingRequests.map(_buildPendingRequestTile),
        ],
      ),
    );
  }

  Widget _buildPendingRequestTile(Map<String, dynamic> req) {
    final profile = req['profiles'] as Map<String, dynamic>?;
    final username =
        profile?['username'] ??
        profile?['email']?.toString().split('@').first ??
        'User';
    final message = (req['message'] as String?)?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFFFF3B30),
            child: Text(
              username.toString().substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username.toString(),
                  style: const TextStyle(color: Colors.white),
                ),
                if (message != null && message.isNotEmpty)
                  Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Annehmen',
            icon: const Icon(Icons.check, color: Colors.green),
            onPressed: () => _respondRequest(req['id'] as String, accept: true),
          ),
          IconButton(
            tooltip: 'Ablehnen',
            icon: const Icon(Icons.close, color: Colors.redAccent),
            onPressed: () =>
                _respondRequest(req['id'] as String, accept: false),
          ),
        ],
      ),
    );
  }

  Future<void> _respondRequest(String requestId, {required bool accept}) async {
    try {
      if (accept) {
        await SocialService.acceptJoinRequest(requestId);
      } else {
        await SocialService.rejectJoinRequest(requestId);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      return;
    }
    if (!mounted) return;
    setState(() {
      _pendingRequests.removeWhere((r) => r['id'] == requestId);
    });
    await _load();
  }

  Widget _buildMemberTile(GroupMember m) {
    final isMe = m.userId == _myId;
    final isBlocked = _blockedIds.contains(m.userId);
    final roleLabel = m.role == MemberRole.owner
        ? 'Owner'
        : m.role == MemberRole.driver
        ? 'Fahrer'
        : 'Mitfahrer';
    final roleColor = m.role == MemberRole.owner
        ? const Color(0xFFFF3B30)
        : Colors.grey;
    return Opacity(
      // Blockierte User werden ausgegraut, damit klar ist, dass weder
      // sie meinen Content sehen noch ich ihren — sie bleiben aber sichtbar
      // damit die Mitglieder-Liste vollständig bleibt (Group-Logik).
      opacity: isBlocked ? 0.45 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(12),
          border: isBlocked
              ? Border.all(color: Colors.white.withValues(alpha: 0.05))
              : null,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF0B0E14),
              backgroundImage: m.avatarUrl != null
                  ? NetworkImage(m.avatarUrl!)
                  : null,
              child: m.avatarUrl == null
                  ? Text(
                      (m.displayName ?? '?').characters.first.toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${m.displayName ?? 'User'}${isMe ? ' (Du)' : ''}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  if (isBlocked)
                    const Text(
                      'Blockiert',
                      style: TextStyle(
                        color: Color(0xFFFF3B30),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            Text(roleLabel, style: TextStyle(color: roleColor)),
            if (_amOwner && !isMe && m.role != MemberRole.owner && !isBlocked)
              IconButton(
                tooltip: 'Zum Owner befördern',
                icon: const Icon(Icons.star_border, color: Colors.grey),
                onPressed: () => _promoteToOwner(m),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSelector() {
    if (_myRole == MemberRole.owner) {
      return const Text(
        'Du bist Owner',
        style: TextStyle(color: Color(0xFFFF3B30)),
      );
    }
    return Row(
      children: [
        _roleChip('Fahrer', MemberRole.driver),
        const SizedBox(width: 12),
        _roleChip('Mitfahrer', MemberRole.passenger),
      ],
    );
  }

  Widget _roleChip(String label, MemberRole role) {
    final selected = _myRole == role;
    return GestureDetector(
      onTap: () => _changeMyRole(role),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF3B30) : const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildBottom() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: _amOwner && !_starting ? _startRoute : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              disabledBackgroundColor: const Color(0xFF1C1F26),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _starting
                ? const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  )
                : Text(
                    _amOwner ? 'Route starten' : 'Warten auf Host...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _showInviteDialog() async {
    final myUid = _myId;
    final friends = await SocialService.getFollowingList(myUid);
    final mutualIds = await SocialService.getMutualFollowIds(myUid);
    if (!mounted) return;

    final alreadyIn = _group?.members.map((m) => m.userId).toSet() ?? {};
    // Nur Kontakte (gegenseitiges Folgen) dürfen eingeladen werden.
    final invitable = friends.where((f) {
      final p = f['profiles'] as Map<String, dynamic>?;
      final id = p?['id'] as String?;
      return id != null && !alreadyIn.contains(id) && mutualIds.contains(id);
    }).toList();

    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];
    final invited = <String>{};

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1F26),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> doInvite(String userId) async {
            final messenger = ScaffoldMessenger.of(ctx);
            try {
              await SocialService.inviteToGroup(widget.groupId, userId);
              setSheet(() => invited.add(userId));
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(content: Text('Einladung fehlgeschlagen: $e')),
              );
            }
          }

          Widget tileFor(Map<String, dynamic> profile) {
            final id = profile['id'] as String;
            final username =
                (profile['username'] ?? profile['email'] ?? 'User') as String;
            final isMember = alreadyIn.contains(id);
            final didInvite = invited.contains(id);
            final isMutual = mutualIds.contains(id);
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF0B0E14),
                child: Text(
                  username.characters.first.toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(
                username,
                style: const TextStyle(color: Colors.white),
              ),
              trailing: isMember
                  ? const Text(
                      'Dabei',
                      style: TextStyle(color: Colors.greenAccent),
                    )
                  : didInvite
                  ? const Text(
                      'Eingeladen',
                      style: TextStyle(color: Colors.grey),
                    )
                  : !isMutual
                  ? const Text(
                      'Kein Kontakt',
                      style: TextStyle(color: Colors.grey),
                    )
                  : TextButton(
                      onPressed: () => doInvite(id),
                      child: const Text(
                        'Einladen',
                        style: TextStyle(color: Color(0xFFFF3B30)),
                      ),
                    ),
            );
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Freunde einladen',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: searchCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'User suchen…',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        filled: true,
                        fillColor: const Color(0xFF0B0E14),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.grey,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (q) async {
                        if (q.trim().isEmpty) {
                          setSheet(() => searchResults = []);
                          return;
                        }
                        final res = await SocialService.searchUsers(q);
                        setSheet(
                          () => searchResults = res
                              .where((u) => u['id'] != myUid)
                              .toList(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: searchResults.isNotEmpty
                        ? ListView(
                            children: searchResults.map(tileFor).toList(),
                          )
                        : invitable.isEmpty
                        ? const Center(
                            child: Text(
                              'Du folgst noch niemandem.\nNutze die Suche.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView(
                            children: invitable.map((f) {
                              final p = f['profiles'] as Map<String, dynamic>;
                              return tileFor(p);
                            }).toList(),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
