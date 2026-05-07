import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/user_profile_page.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CommunityCarouselCard extends StatefulWidget {
  final VoidCallback? onOpenCommunity;

  const CommunityCarouselCard({super.key, this.onOpenCommunity});

  @override
  State<CommunityCarouselCard> createState() => _CommunityCarouselCardState();
}

class _CommunityCarouselCardState extends State<CommunityCarouselCard> {
  static const int _visibleSuggestionLimit = 5;
  static const int _suggestionFetchLimit = 10;
  static const int _visibleGroupLimit = 3;
  static const int _groupFetchLimit = 8;

  final PageController _pageController = PageController();
  final Set<String> _busyUsers = {};
  final Set<String> _busyGroups = {};
  final Set<String> _joinedGroups = {};
  final Set<String> _dismissedUsers = {};

  int _page = 0;
  bool _loading = true;
  bool _replenishingUsers = false;
  bool _replenishingGroups = false;
  List<Map<String, dynamic>> _suggestedUsers = [];
  List<Map<String, dynamic>> _publicGroups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        SocialService.getSuggestedUsers(limit: _suggestionFetchLimit),
        SocialService.getDiscoverGroups(),
      ]);
      if (!mounted) return;
      final suggestions = results[0]
          .where((user) => !_dismissedUsers.contains(user['id']))
          .take(_visibleSuggestionLimit)
          .toList();
      setState(() {
        _suggestedUsers = suggestions;
        _publicGroups = results[1].take(_visibleGroupLimit).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[CommunityCarouselCard] Laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _replenishSuggestedUsers() async {
    if (_replenishingUsers ||
        _suggestedUsers.length >= _visibleSuggestionLimit) {
      return;
    }
    _replenishingUsers = true;
    try {
      final latest = await SocialService.getSuggestedUsers(
        limit: _suggestionFetchLimit,
      );
      if (!mounted) return;
      setState(() {
        final visibleIds = _suggestedUsers
            .map((user) => user['id'] as String?)
            .whereType<String>()
            .toSet();
        for (final user in latest) {
          final id = user['id'] as String?;
          if (id == null ||
              visibleIds.contains(id) ||
              _dismissedUsers.contains(id)) {
            continue;
          }
          _suggestedUsers.add(user);
          visibleIds.add(id);
          if (_suggestedUsers.length >= _visibleSuggestionLimit) break;
        }
      });
    } catch (e) {
      debugPrint('[CommunityCarouselCard] User nachladen fehlgeschlagen: $e');
    } finally {
      _replenishingUsers = false;
    }
  }

  Future<void> _replenishPublicGroups() async {
    if (_replenishingGroups || _publicGroups.length >= _visibleGroupLimit) {
      return;
    }
    _replenishingGroups = true;
    try {
      final latest = await SocialService.getDiscoverGroups();
      if (!mounted) return;
      setState(() {
        final visibleIds = _publicGroups
            .map((group) => group['id'] as String?)
            .whereType<String>()
            .toSet();
        for (final group in latest.take(_groupFetchLimit)) {
          final id = group['id'] as String?;
          if (id == null ||
              visibleIds.contains(id) ||
              _joinedGroups.contains(id)) {
            continue;
          }
          _publicGroups.add(group);
          visibleIds.add(id);
          if (_publicGroups.length >= _visibleGroupLimit) break;
        }
      });
    } catch (e) {
      debugPrint(
        '[CommunityCarouselCard] Gruppen nachladen fehlgeschlagen: $e',
      );
    } finally {
      _replenishingGroups = false;
    }
  }

  Future<void> _followUser(String userId) async {
    if (_busyUsers.contains(userId)) return;
    Map<String, dynamic>? user;
    for (final entry in _suggestedUsers) {
      if (entry['id'] == userId) {
        user = entry;
        break;
      }
    }
    setState(() => _busyUsers.add(userId));
    try {
      await context.read<CommunityProvider>().followUser(
        userId,
        targetIsPrivate: user?['is_private'] == true,
      );
      if (!mounted) return;
      setState(() {
        _dismissedUsers.add(userId);
        _suggestedUsers.removeWhere((user) => user['id'] == userId);
      });
      await _replenishSuggestedUsers();
    } finally {
      if (mounted) setState(() => _busyUsers.remove(userId));
    }
  }

  Future<void> _dismissUser(String userId) async {
    if (userId.isEmpty) return;
    setState(() {
      _dismissedUsers.add(userId);
      _suggestedUsers.removeWhere((user) => user['id'] == userId);
    });
    await _replenishSuggestedUsers();
  }

  Future<void> _joinGroup(String groupId) async {
    if (_busyGroups.contains(groupId) || _joinedGroups.contains(groupId)) {
      return;
    }
    setState(() => _busyGroups.add(groupId));
    try {
      await SocialService.joinGroup(groupId);
      if (!mounted) return;
      setState(() {
        _busyGroups.remove(groupId);
        _joinedGroups.add(groupId);
      });
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      setState(() {
        _publicGroups.removeWhere((group) => group['id'] == groupId);
        _joinedGroups.remove(groupId);
      });
      await _replenishPublicGroups();
    } catch (e) {
      debugPrint('[CommunityCarouselCard] Beitreten fehlgeschlagen: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Beitreten gerade nicht möglich.'),
          backgroundColor: Color(0xFF1C1F26),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyGroups.remove(groupId));
    }
  }

  void _openUser(Map<String, dynamic> user) {
    final id = user['id'] as String?;
    if (id == null) return;
    final name = SocialService.publicDisplayName(user, fallbackUserId: id);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfilePage(userId: id, initialUsername: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.groups_2_outlined,
                color: AppAccentColors.accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Community',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              GestureDetector(
                onTap: widget.onOpenCommunity,
                behavior: HitTestBehavior.opaque,
                child: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white54,
                  size: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _loading
                ? const _CommunityLoadingSlide()
                : PageView(
                    controller: _pageController,
                    onPageChanged: (value) => setState(() => _page = value),
                    children: [
                      SuggestedContactsSlide(
                        users: _suggestedUsers,
                        busyUserIds: _busyUsers,
                        onOpenUser: _openUser,
                        onFollow: _followUser,
                        onDismiss: _dismissUser,
                        onOpenCommunity: widget.onOpenCommunity,
                      ),
                      PublicGroupsSlide(
                        groups: _publicGroups,
                        busyGroupIds: _busyGroups,
                        joinedGroupIds: _joinedGroups,
                        onJoin: _joinGroup,
                        onOpenCommunity: widget.onOpenCommunity,
                      ),
                      EventsComingSoonSlide(
                        onOpenCommunity: widget.onOpenCommunity,
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          Center(child: _CommunityDots(activeIndex: _page, count: 3)),
        ],
      ),
    );
  }
}

class SuggestedContactsSlide extends StatelessWidget {
  final List<Map<String, dynamic>> users;
  final Set<String> busyUserIds;
  final ValueChanged<Map<String, dynamic>> onOpenUser;
  final ValueChanged<String> onFollow;
  final ValueChanged<String> onDismiss;
  final VoidCallback? onOpenCommunity;

  const SuggestedContactsSlide({
    super.key,
    required this.users,
    required this.busyUserIds,
    required this.onOpenUser,
    required this.onFollow,
    required this.onDismiss,
    this.onOpenCommunity,
  });

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return _EmptySlide(
        icon: Icons.person_add_alt_1_outlined,
        title: 'Neue Kontakte',
        text: 'Gerade keine neuen Vorschläge. Schau später wieder rein.',
        actionLabel: 'Entdecken',
        onAction: onOpenCommunity,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vorschläge',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Color(0xFFA0AEC0),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Scrollbar(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              itemCount: users.length > 5 ? 5 : users.length,
              separatorBuilder: (_, _) => const SizedBox(height: 7),
              itemBuilder: (context, index) {
                final user = users[index];
                final id = user['id'] as String? ?? '';
                final name = SocialService.publicDisplayName(
                  user,
                  fallbackUserId: id,
                );
                final handle = SocialService.publicHandle(
                  user,
                  fallbackUserId: id,
                );
                final busy = busyUserIds.contains(id);

                return _ContactRow(
                  name: name,
                  handle: handle,
                  avatarUrl: user['avatar_url'] as String?,
                  busy: busy,
                  onTap: () => onOpenUser(user),
                  onFollow: id.isEmpty ? null : () => onFollow(id),
                  onDismiss: id.isEmpty ? null : () => onDismiss(id),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class PublicGroupsSlide extends StatelessWidget {
  final List<Map<String, dynamic>> groups;
  final Set<String> busyGroupIds;
  final Set<String> joinedGroupIds;
  final ValueChanged<String> onJoin;
  final VoidCallback? onOpenCommunity;

  const PublicGroupsSlide({
    super.key,
    required this.groups,
    required this.busyGroupIds,
    required this.joinedGroupIds,
    required this.onJoin,
    this.onOpenCommunity,
  });

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return _EmptySlide(
        icon: Icons.groups_outlined,
        title: 'Öffentliche Gruppen',
        text: 'Aktuell ist keine offene Gruppe verfügbar.',
        actionLabel: 'Community',
        onAction: onOpenCommunity,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Öffentliche Gruppen',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Color(0xFFA0AEC0),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(height: 7),
            itemBuilder: (context, index) {
              final group = groups[index];
              final id = group['id'] as String? ?? '';
              final members = (group['group_members'] as List?)?.length ?? 0;
              final joined = joinedGroupIds.contains(id);
              final busy = busyGroupIds.contains(id);

              return _GroupPreviewRow(
                name: group['name']?.toString() ?? 'Gruppe',
                memberCount: members,
                joined: joined,
                busy: busy,
                onJoin: id.isEmpty ? null : () => onJoin(id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class EventsComingSoonSlide extends StatelessWidget {
  final VoidCallback? onOpenCommunity;

  const EventsComingSoonSlide({super.key, this.onOpenCommunity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppAccentColors.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Coming Soon',
                  style: TextStyle(
                    color: AppAccentColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.event_outlined, color: Colors.white38, size: 22),
            ],
          ),
          const Spacer(),
          const Text(
            'Events',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Hier kannst du in Zukunft deine Events planen.',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFFA0AEC0),
              fontSize: 11,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final String name;
  final String handle;
  final String? avatarUrl;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onFollow;
  final VoidCallback? onDismiss;

  const _ContactRow({
    required this.name,
    required this.handle,
    required this.avatarUrl,
    required this.busy,
    required this.onTap,
    required this.onFollow,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              UserAvatar(
                name: name,
                avatarUrl: avatarUrl,
                radius: 15,
                onTap: onTap,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFA0AEC0),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _DismissButton(onTap: onDismiss),
            ],
          ),
          const SizedBox(height: 7),
          Align(
            alignment: Alignment.centerLeft,
            child: _MiniActionButton(
              label: 'Folgen',
              icon: Icons.person_add_alt_1,
              busy: busy,
              onTap: onFollow,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupPreviewRow extends StatelessWidget {
  final String name;
  final int memberCount;
  final bool joined;
  final bool busy;
  final VoidCallback? onJoin;

  const _GroupPreviewRow({
    required this.name,
    required this.memberCount,
    required this.joined,
    required this.busy,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppAccentColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.groups_2_outlined,
            color: AppAccentColors.accent,
            size: 19,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Row(
                children: [
                  const Icon(
                    Icons.people_alt_outlined,
                    color: Color(0xFFA0AEC0),
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$memberCount Mitglieder',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFA0AEC0),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _MiniActionButton(
          label: joined ? 'Drin' : 'Beitreten',
          icon: joined ? Icons.check : Icons.login,
          busy: busy,
          onTap: joined ? null : onJoin,
        ),
      ],
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onTap;

  const _MiniActionButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 108),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: enabled
                ? AppAccentColors.accent
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                child: busy
                    ? const SizedBox(
                        key: ValueKey('busy'),
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        icon,
                        key: ValueKey(icon),
                        color: Colors.white,
                        size: 13,
                      ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DismissButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _DismissButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: const Icon(Icons.close, color: Color(0xFFA0AEC0), size: 14),
      ),
    );
  }
}

class _EmptySlide extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final String actionLabel;
  final VoidCallback? onAction;

  const _EmptySlide({
    required this.icon,
    required this.title,
    required this.text,
    required this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppAccentColors.accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFA0AEC0),
              fontSize: 10,
              height: 1.25,
            ),
          ),
          const Spacer(),
          if (onAction != null)
            Align(
              alignment: Alignment.centerLeft,
              child: _MiniActionButton(
                label: actionLabel,
                icon: Icons.arrow_forward,
                busy: false,
                onTap: onAction,
              ),
            ),
        ],
      ),
    );
  }
}

class _CommunityLoadingSlide extends StatelessWidget {
  const _CommunityLoadingSlide();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (index) => Expanded(
          child: Container(
            margin: EdgeInsets.only(bottom: index == 2 ? 0 : 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}

class _CommunityDots extends StatelessWidget {
  final int activeIndex;
  final int count;

  const _CommunityDots({required this.activeIndex, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (index) {
        final active = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 16 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active
                ? AppAccentColors.accent
                : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}
