import 'package:flutter/material.dart';
import 'package:cruise_connect/presentation/widgets/skeletons/skeleton.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/presentation/pages/community_chat_detail_page.dart';

class CommunityChatsTab extends StatefulWidget {
  const CommunityChatsTab({super.key});

  @override
  State<CommunityChatsTab> createState() => _CommunityChatsTabState();
}

class _CommunityChatsTabState extends State<CommunityChatsTab> {
  final _codeSearchController = TextEditingController();
  bool _loading = true;
  bool _codeSearchLoading = false;
  List<Map<String, dynamic>> _myCommunities = [];
  List<Map<String, dynamic>> _discoverCommunities = [];
  Map<String, dynamic>? _codeSearchResult;

  @override
  void dispose() {
    _codeSearchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        CommunityChatService.getMyCommunities(),
        CommunityChatService.getDiscoverCommunities(),
      ]);
      if (!mounted) return;
      setState(() {
        _myCommunities = results[0];
        _discoverCommunities = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Communities konnten nicht geladen werden.');
    }
  }

  Future<void> _openCommunity(String communityId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityChatDetailPage(communityId: communityId),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _joinCommunity(Map<String, dynamic> community) async {
    try {
      final id = community['id'] as String;
      await CommunityChatService.joinCommunity(id);
      if (!mounted) return;
      await _openCommunity(id);
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _lookupCommunityCode(String raw) async {
    final normalized = CommunityChatService.normalizeInviteCode(raw);
    if (normalized == null) {
      setState(() {
        _codeSearchResult = null;
        _codeSearchLoading = false;
      });
      return;
    }
    setState(() => _codeSearchLoading = true);
    final result = await CommunityChatService.findCommunityByCode(normalized);
    if (!mounted || _codeSearchController.text.trim() != raw.trim()) return;
    setState(() {
      _codeSearchResult = result;
      _codeSearchLoading = false;
    });
  }

  Future<void> _joinCommunityWithCode(String rawCode) async {
    try {
      final id = await CommunityChatService.joinCommunityWithCode(rawCode);
      if (!mounted) return;
      _codeSearchController.clear();
      setState(() => _codeSearchResult = null);
      await _openCommunity(id);
    } catch (e) {
      _showError(e);
    }
  }

  void _showMembers(Map<String, dynamic> community) {
    final communityId = community['id']?.toString();
    if (communityId == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CommunityMembersSheet(
        communityId: communityId,
        initialMembers: const [],
        ownerOnlyMessages: community['owner_only_messages'] == true,
        onChanged: _load,
      ),
    );
  }

  Future<void> _confirmLeaveCommunity(Map<String, dynamic> community) async {
    final communityId = community['id']?.toString();
    if (communityId == null) return;

    final isAdmin = CommunityChatService.currentUserRole(community) == 'owner';
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
      await CommunityChatService.leaveCommunity(communityId);
      if (mounted) _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _confirmDeleteCommunity(Map<String, dynamic> community) async {
    final communityId = community['id']?.toString();
    if (communityId == null) return;

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
      await CommunityChatService.deleteCommunity(communityId);
      if (mounted) _load();
    } catch (e) {
      _showError(e);
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

  void _showError(Object message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message is String ? message : _friendlyError(message),
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
    if (_loading) {
      return const SkeletonList(count: 7);
    }

    return RefreshIndicator(
      color: AppAccentColors.accent,
      backgroundColor: const Color(0xFF151821),
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
        children: [
          _buildActionRow(),
          const SizedBox(height: 12),
          _buildInlineCodeSearch(),
          const SizedBox(height: 18),
          _buildSectionHeader('Meine Communities', _myCommunities.length),
          const SizedBox(height: 10),
          if (_myCommunities.isEmpty)
            _buildEmptyState(
              icon: Icons.forum_outlined,
              title: 'Noch keine Community',
              text: 'Erstelle eine Community oder tritt mit einem Code bei.',
            )
          else
            ..._myCommunities.map(
              (community) => _buildCommunityCard(
                community,
                joined: true,
                onTap: () => _openCommunity(community['id'] as String),
              ),
            ),
          const SizedBox(height: 22),
          _buildSectionHeader(
            'Öffentliche Communities',
            _discoverCommunities.length,
          ),
          const SizedBox(height: 10),
          if (_discoverCommunities.isEmpty)
            _buildEmptyState(
              icon: Icons.travel_explore,
              title: 'Nichts Neues gefunden',
              text: 'Öffentliche Communities tauchen hier im Entdecken auf.',
            )
          else
            ..._discoverCommunities.map(
              (community) => _buildCommunityCard(
                community,
                joined: false,
                onTap: () => _joinCommunity(community),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInlineCodeSearch() {
    final result = _codeSearchResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: TextField(
            controller: _codeSearchController,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Community-Code suchen (CCC-XXXXXX)',
              hintStyle: const TextStyle(color: Colors.grey),
              counterText: '',
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: _codeSearchLoading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.login, color: Colors.white70),
                      onPressed: _codeSearchController.text.trim().isEmpty
                          ? null
                          : () {
                              _joinCommunityWithCode(
                                _codeSearchController.text,
                              );
                            },
                    ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onChanged: (value) => _lookupCommunityCode(value),
            onSubmitted: (value) {
              _joinCommunityWithCode(value);
            },
          ),
        ),
        if (result != null) ...[
          const SizedBox(height: 10),
          _buildCommunityCard(
            result,
            joined: false,
            onTap: () => _joinCommunityWithCode(
              result['invite_code']?.toString() ?? _codeSearchController.text,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _showCreateCommunitySheet,
            icon: const Icon(Icons.add, color: Colors.white, size: 18),
            label: const Text('Erstellen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppAccentColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _showJoinCodeSheet,
            icon: const Icon(Icons.key, color: Colors.white, size: 18),
            label: const Text('Code'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF151821),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: const TextStyle(color: Colors.grey, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityCard(
    Map<String, dynamic> community, {
    required bool joined,
    required VoidCallback onTap,
  }) {
    final owner = CommunityChatService.ownerProfile(community);
    final ownerName = CommunityChatService.displayName(
      owner,
      fallbackUserId: community['owner_id'] as String?,
    );
    final memberCount = CommunityChatService.memberCount(community);
    final isPublic = community['is_public'] == true;
    final description = (community['description'] as String?)?.trim();
    final role = CommunityChatService.currentUserRole(community);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppAccentColors.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPublic ? Icons.forum_outlined : Icons.lock_outline,
                    color: AppAccentColors.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        community['name']?.toString() ?? 'Community',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '@$ownerName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildVisibilityPill(isPublic),
                if (joined) ...[
                  const SizedBox(width: 4),
                  _buildCommunityMenu(community, role),
                ],
              ],
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 13),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _showMembers(community),
                  icon: Icon(
                    Icons.people_outline,
                    color: Colors.grey[500],
                    size: 16,
                  ),
                  label: Text('$memberCount Mitglieder'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey,
                    textStyle: const TextStyle(fontSize: 12),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onTap,
                  icon: Icon(
                    joined ? Icons.chat_bubble_outline : Icons.login,
                    color: AppAccentColors.accent,
                    size: 16,
                  ),
                  label: Text(joined ? 'Chat' : 'Beitreten'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppAccentColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommunityMenu(Map<String, dynamic> community, String? role) {
    final isAdmin = role == 'owner';
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz, color: Colors.white70),
      color: const Color(0xFF1C1F26),
      onSelected: (value) {
        if (value == 'members') {
          _showMembers(community);
        } else if (value == 'leave') {
          _confirmLeaveCommunity(community);
        } else if (value == 'delete') {
          _confirmDeleteCommunity(community);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'members',
          child: Row(
            children: [
              Icon(Icons.people_outline, color: Colors.white70, size: 18),
              SizedBox(width: 10),
              Text('Mitglieder', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'leave',
          child: Row(
            children: [
              Icon(Icons.logout, color: Colors.redAccent, size: 18),
              SizedBox(width: 10),
              Text('Verlassen', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
        if (isAdmin) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
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
    );
  }

  Widget _buildVisibilityPill(bool isPublic) {
    final color = isPublic ? Colors.greenAccent : Colors.orangeAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        isPublic ? 'Öffentlich' : 'Privat',
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showCreateCommunitySheet() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var isPublic = false;
    var ownerOnlyMessages = false;
    var saving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> create() async {
              if (saving) return;
              setSheetState(() => saving = true);
              try {
                final id = await CommunityChatService.createCommunity(
                  name: nameCtrl.text,
                  description: descCtrl.text,
                  isPublic: isPublic,
                  ownerOnlyMessages: ownerOnlyMessages,
                );
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                if (!mounted) return;
                await _openCommunity(id);
              } catch (e) {
                _showError(e);
              } finally {
                if (sheetContext.mounted) {
                  setSheetState(() => saving = false);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                18,
                18,
                MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Community erstellen',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSheetTextField(
                    controller: nameCtrl,
                    label: 'Name',
                    maxLength: AppInputLimits.communityNameMaxLength,
                  ),
                  const SizedBox(height: 10),
                  _buildSheetTextField(
                    controller: descCtrl,
                    label: 'Beschreibung',
                    maxLength: AppInputLimits.communityDescriptionMaxLength,
                    minLines: 2,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _buildVisibilityOption(
                          selected: isPublic,
                          icon: Icons.public,
                          title: 'Öffentlich',
                          onTap: () => setSheetState(() => isPublic = true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildVisibilityOption(
                          selected: !isPublic,
                          icon: Icons.lock_outline,
                          title: 'Privat',
                          onTap: () => setSheetState(() => isPublic = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => setSheetState(
                      () => ownerOnlyMessages = !ownerOnlyMessages,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F121A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: ownerOnlyMessages
                              ? AppAccentColors.accent
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            ownerOnlyMessages
                                ? Icons.admin_panel_settings
                                : Icons.chat_bubble_outline,
                            color: ownerOnlyMessages
                                ? AppAccentColors.accent
                                : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Nur Owner darf schreiben',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: ownerOnlyMessages,
                            activeThumbColor: AppAccentColors.accent,
                            activeTrackColor: AppAccentColors.accent.withValues(
                              alpha: 0.35,
                            ),
                            onChanged: (value) =>
                                setSheetState(() => ownerOnlyMessages = value),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: saving ? null : create,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppAccentColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Erstellen',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      nameCtrl.dispose();
      descCtrl.dispose();
    });
  }

  void _showJoinCodeSheet() {
    final codeCtrl = TextEditingController();
    var saving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> join() async {
              if (saving) return;
              setSheetState(() => saving = true);
              try {
                final id = await CommunityChatService.joinCommunityWithCode(
                  codeCtrl.text,
                );
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                if (!mounted) return;
                await _openCommunity(id);
              } catch (e) {
                _showError(e);
              } finally {
                if (sheetContext.mounted) {
                  setSheetState(() => saving = false);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                18,
                18,
                MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mit Code beitreten',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSheetTextField(
                    controller: codeCtrl,
                    label: 'CCC-ABC123',
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : join,
                      icon: saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.login, color: Colors.white),
                      label: const Text('Beitreten'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppAccentColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(codeCtrl.dispose);
  }

  Widget _buildSheetTextField({
    required TextEditingController controller,
    required String label,
    int? maxLength,
    int minLines = 1,
    int maxLines = 1,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
  }) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      minLines: minLines,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        counterStyle: const TextStyle(color: Colors.grey),
        labelStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF0F121A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppAccentColors.accent),
        ),
      ),
    );
  }

  Widget _buildVisibilityOption({
    required bool selected,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppAccentColors.accent.withValues(alpha: 0.18)
              : const Color(0xFF0F121A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppAccentColors.accent
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? AppAccentColors.accent : Colors.grey,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
