import 'dart:async';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import '../../data/services/community_neuigkeit_service.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/user_profile_page.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum CommunityDashboardSection { carousel, contacts, groups, events }

class CommunityCarouselCard extends StatefulWidget {
  final VoidCallback? onOpenCommunity;
  final CommunityDashboardSection section;
  final bool compact;
  final bool framed;
  final bool showHeader;

  const CommunityCarouselCard({
    super.key,
    this.onOpenCommunity,
    this.section = CommunityDashboardSection.carousel,
    this.compact = false,
    this.framed = true,
    this.showHeader = true,
  });

  @override
  State<CommunityCarouselCard> createState() => _CommunityCarouselCardState();
}

class _CommunityCarouselCardState extends State<CommunityCarouselCard> {
  static const int _visibleSuggestionLimit = 5;
  static const int _suggestionFetchLimit = 10;
  static const int _visibleGroupLimit = 3;
  static const int _groupFetchLimit = 8;
  static const Duration _cacheTtl = Duration(minutes: 2);
  static List<Map<String, dynamic>>? _cachedSuggestedUsers;
  static List<Map<String, dynamic>>? _cachedPublicGroups;
  static DateTime? _cacheUpdatedAt;
  static final Set<String> _sessionDismissedUsers = {};
  static final Set<String> _sessionJoinedGroups = {};

  final PageController _pageController = PageController();
  final Set<String> _busyUsers = {};
  final Set<String> _busyGroups = {};
  late final Set<String> _joinedGroups = Set<String>.of(_sessionJoinedGroups);
  late final Set<String> _dismissedUsers = Set<String>.of(
    _sessionDismissedUsers,
  );

  int _page = 0;
  bool _loading = true;
  bool _replenishingUsers = false;
  bool _replenishingGroups = false;
  List<Map<String, dynamic>> _suggestedUsers = [];
  List<Map<String, dynamic>> _publicGroups = [];

  @override
  void initState() {
    super.initState();
    if (!_needsRemoteData) {
      _loading = false;
      return;
    }
    final hydrated = _applyCachedCommunityData();
    _loading = !hydrated;
    unawaited(_load(showLoading: !hydrated));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _needsSuggestions =>
      widget.section == CommunityDashboardSection.carousel ||
      widget.section == CommunityDashboardSection.contacts;

  bool get _needsGroups =>
      widget.section == CommunityDashboardSection.carousel ||
      widget.section == CommunityDashboardSection.groups;

  bool get _needsRemoteData => _needsSuggestions || _needsGroups;

  bool get _hasFreshNeededCache {
    final updatedAt = _cacheUpdatedAt;
    if (updatedAt == null || DateTime.now().difference(updatedAt) > _cacheTtl) {
      return false;
    }
    if (_needsSuggestions && _cachedSuggestedUsers == null) return false;
    if (_needsGroups && _cachedPublicGroups == null) return false;
    return true;
  }

  bool _applyCachedCommunityData({bool notify = false}) {
    if (_needsSuggestions && _cachedSuggestedUsers == null) return false;
    if (_needsGroups && _cachedPublicGroups == null) return false;

    void apply() {
      if (_needsSuggestions) {
        _suggestedUsers = (_cachedSuggestedUsers ?? const [])
            .where((user) {
              final id = user['id'] as String?;
              return id == null || !_dismissedUsers.contains(id);
            })
            .take(_visibleSuggestionLimit)
            .toList();
      }
      if (_needsGroups) {
        _publicGroups = (_cachedPublicGroups ?? const [])
            .where((group) {
              final id = group['id'] as String?;
              return id == null || !_joinedGroups.contains(id);
            })
            .take(_visibleGroupLimit)
            .toList();
      }
      _loading = false;
    }

    if (notify && mounted) {
      setState(apply);
    } else {
      apply();
    }
    return true;
  }

  Future<void> _load({bool force = false, bool showLoading = true}) async {
    if (!_needsRemoteData) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (!force && _hasFreshNeededCache) {
      _applyCachedCommunityData(notify: mounted);
      return;
    }

    if (showLoading && mounted) {
      setState(() => _loading = true);
    }

    try {
      final results = await Future.wait<List<Map<String, dynamic>>>([
        _needsSuggestions
            ? SocialService.getSuggestedUsers(limit: _suggestionFetchLimit)
            : Future<List<Map<String, dynamic>>>.value(
                _cachedSuggestedUsers ?? const [],
              ),
        _needsGroups
            ? SocialService.getDiscoverGroups()
            : Future<List<Map<String, dynamic>>>.value(
                _cachedPublicGroups ?? const [],
              ),
      ]);
      if (!mounted) return;
      if (_needsSuggestions) {
        _cachedSuggestedUsers = results[0];
      }
      if (_needsGroups) {
        _cachedPublicGroups = results[1].take(_groupFetchLimit).toList();
      }
      _cacheUpdatedAt = DateTime.now();
      final suggestions = results[0]
          .where((user) => !_dismissedUsers.contains(user['id']))
          .take(_visibleSuggestionLimit)
          .toList();
      setState(() {
        _suggestedUsers = suggestions;
        _publicGroups = results[1]
            .where((group) => !_joinedGroups.contains(group['id']))
            .take(_visibleGroupLimit)
            .toList();
        _loading = false;
      });
      // 2026-08-11 (vucko): Der Hinweispunkt am Community-Symbol lebt von
      // genau diesen Zahlen — sie sind ohnehin schon geladen, also kostet der
      // Punkt keine einzige zusaetzliche Abfrage.
      // Jede Kachel meldet NUR, was sie selbst geladen hat. Fuer die andere
      // Haelfte steht oben der Cache des Nachbarn — beim Kaltstart ist der
      // leer, und eine gemeldete 0 wuerde den korrekten Wert der anderen
      // Kachel ueberschreiben und den Hinweispunkt ausknipsen.
      unawaited(
        CommunityNeuigkeitService.instance.melde(
          gruppen: _needsGroups ? results[1].length : null,
          vorschlaege: _needsSuggestions ? results[0].length : null,
        ),
      );
    } catch (e) {
      debugPrint('[CommunityCarouselCard] Laden fehlgeschlagen: $e');
      if (!mounted) return;
      if (!_applyCachedCommunityData(notify: mounted) && mounted) {
        setState(() => _loading = false);
      }
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
      _cachedSuggestedUsers = latest;
      _cacheUpdatedAt = DateTime.now();
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
      _cachedPublicGroups = latest.take(_groupFetchLimit).toList();
      _cacheUpdatedAt = DateTime.now();
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
    int removedIndex = 0;
    for (var i = 0; i < _suggestedUsers.length; i++) {
      if (_suggestedUsers[i]['id'] == userId) {
        user = _suggestedUsers[i];
        removedIndex = i;
        break;
      }
    }
    // 2026-07-10 (vucko Instant-Follow): OPTIMISTIC — Karte SOFORT bestätigen
    // und entfernen, BEVOR der Server antwortet (Grundsatz: Frontend reagiert
    // instant, Backend darf 2-3s brauchen). Vorher hing die Karte 2-3s mit
    // Spinner am await. Bei Fehler wird die Karte zurückgeholt.
    setState(() {
      _sessionDismissedUsers.add(userId);
      _dismissedUsers.add(userId);
      _suggestedUsers.removeWhere((u) => u['id'] == userId);
    });
    _cachedSuggestedUsers?.removeWhere((u) => u['id'] == userId);
    unawaited(_replenishSuggestedUsers());
    try {
      await context.read<CommunityProvider>().followUser(
        userId,
        targetIsPrivate: user?['is_private'] == true,
      );
    } catch (e) {
      debugPrint('[CommunityCarouselCard] Follow fehlgeschlagen: $e');
      if (!mounted) return;
      // Rollback: Karte wieder anbieten + dezenter Hinweis.
      setState(() {
        _sessionDismissedUsers.remove(userId);
        _dismissedUsers.remove(userId);
        if (user != null && !_suggestedUsers.any((u) => u['id'] == userId)) {
          _suggestedUsers.insert(
            removedIndex.clamp(0, _suggestedUsers.length),
            user,
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Folgen fehlgeschlagen, bitte erneut versuchen.'),
        ),
      );
    }
  }

  Future<void> _dismissUser(String userId) async {
    if (userId.isEmpty) return;
    setState(() {
      _sessionDismissedUsers.add(userId);
      _dismissedUsers.add(userId);
      _suggestedUsers.removeWhere((user) => user['id'] == userId);
    });
    _cachedSuggestedUsers?.removeWhere((user) => user['id'] == userId);
    // Auch dauerhaft merken (14 Tage), nicht nur fuer diese Sitzung.
    //
    // 2026-08-11: Hier fehlte das. Wer jemanden auf der Home-Kachel wegklickte,
    // sah ihn nach dem naechsten App-Start wieder — und im Entdecken-Tab
    // sofort erneut, weil dessen serverseitiger Filter nur die gespeicherte
    // Liste kennt. Weggeklickt muss weggeklickt bleiben, egal wo man tippt.
    unawaited(SocialService.dismissSuggestedUser(userId));
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
        _sessionJoinedGroups.add(groupId);
        _joinedGroups.add(groupId);
      });
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      setState(() {
        _publicGroups.removeWhere((group) => group['id'] == groupId);
        _joinedGroups.remove(groupId);
      });
      _cachedPublicGroups?.removeWhere((group) => group['id'] == groupId);
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

  String get _title {
    switch (widget.section) {
      case CommunityDashboardSection.carousel:
        return 'Community';
      case CommunityDashboardSection.contacts:
        return 'Kontakte';
      case CommunityDashboardSection.groups:
        return 'Gruppen';
      case CommunityDashboardSection.events:
        return 'Events';
    }
  }

  IconData get _icon {
    switch (widget.section) {
      case CommunityDashboardSection.carousel:
        return Icons.groups_2_outlined;
      case CommunityDashboardSection.contacts:
        return Icons.person_add_alt_1_outlined;
      case CommunityDashboardSection.groups:
        return Icons.groups_outlined;
      case CommunityDashboardSection.events:
        return Icons.event_outlined;
    }
  }

  List<Widget> _communitySlides() => [
    SuggestedContactsSlide(
      users: _suggestedUsers,
      busyUserIds: _busyUsers,
      onOpenUser: _openUser,
      onFollow: _followUser,
      onDismiss: _dismissUser,
      onOpenCommunity: widget.onOpenCommunity,
      compact: widget.compact,
    ),
    PublicGroupsSlide(
      groups: _publicGroups,
      busyGroupIds: _busyGroups,
      joinedGroupIds: _joinedGroups,
      onJoin: _joinGroup,
      onOpenCommunity: widget.onOpenCommunity,
      compact: widget.compact,
    ),
    EventsComingSoonSlide(
      onOpenCommunity: widget.onOpenCommunity,
      compact: widget.compact,
    ),
  ];

  Widget _sectionSlide() {
    switch (widget.section) {
      case CommunityDashboardSection.carousel:
        return PageView(
          controller: _pageController,
          onPageChanged: (value) => setState(() => _page = value),
          children: _communitySlides(),
        );
      case CommunityDashboardSection.contacts:
        return SuggestedContactsSlide(
          users: _suggestedUsers,
          busyUserIds: _busyUsers,
          onOpenUser: _openUser,
          onFollow: _followUser,
          onDismiss: _dismissUser,
          onOpenCommunity: widget.onOpenCommunity,
          compact: widget.compact,
        );
      case CommunityDashboardSection.groups:
        return PublicGroupsSlide(
          groups: _publicGroups,
          busyGroupIds: _busyGroups,
          joinedGroupIds: _joinedGroups,
          onJoin: _joinGroup,
          onOpenCommunity: widget.onOpenCommunity,
          compact: widget.compact,
        );
      case CommunityDashboardSection.events:
        return EventsComingSoonSlide(
          onOpenCommunity: widget.onOpenCommunity,
          compact: widget.compact,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCarousel = widget.section == CommunityDashboardSection.carousel;
    final padding = widget.framed
        ? EdgeInsets.all(widget.compact ? 10 : 12)
        : EdgeInsets.zero;
    return Container(
      padding: padding,
      decoration: widget.framed
          ? BoxDecoration(
              color: const Color(0xFF1C1F26),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showHeader) ...[
            // 2026-08-12 (vucko): „schau, dass die Quicklinks zuverlaessiger
            // sind, die sind noch nicht gut genug. Dass es leichter ist, wenn
            // man draufdrueckt, weitergeleitet wird, und man mehr Flaeche zum
            // Druecken hat — aber nicht zu viel, dass man ausversehen
            // draufdrueckt."
            //
            // Vorher hing der Sprung in die Community an einem NACKTEN
            // Pfeilsymbol mit 14 Punkten Kantenlaenge. Das ist weniger als ein
            // Drittel der empfohlenen 48 Punkte — man musste zielen, und
            // daneben passierte einfach nichts.
            //
            // Jetzt ist die ganze KOPFZEILE der Bereich: Symbol, Titel und
            // Pfeil zusammen, mindestens 44 Punkte hoch. Das trifft man
            // beilaeufig.
            //
            // Bewusst NICHT die ganze Kachel: Darunter liegen Profilbilder,
            // Folgen-Knoepfe und das Wegklicken. Waere alles ein einziger
            // Bereich, wuerde jeder Fehlgriff auf einen Knopf stattdessen die
            // Community oeffnen — genau das „ausversehen draufdruecken", das er
            // ausschliesst.
            Semantics(
              button: true,
              label: '$_title öffnen',
              child: GestureDetector(
                onTap: widget.onOpenCommunity,
                behavior: HitTestBehavior.opaque,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: [
                      Icon(_icon, color: AppAccentColors.accent, size: 17),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            height: 1.06,
                          ),
                        ),
                      ),
                      // Etwas groesser und heller: Der Pfeil ist jetzt der
                      // sichtbare Hinweis „hier geht es weiter", nicht mehr
                      // das Ziel selbst.
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white70,
                        size: 15,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: widget.compact ? 4 : 6),
          ],
          Expanded(
            child: _loading ? const _CommunityLoadingSlide() : _sectionSlide(),
          ),
          if (isCarousel) ...[
            const SizedBox(height: 8),
            Center(child: _CommunityDots(activeIndex: _page, count: 3)),
          ],
        ],
      ),
    );
  }
}

class SuggestedContactsSlide extends StatelessWidget {
  static const int _compactContactLimit = 3;

  final List<Map<String, dynamic>> users;
  final Set<String> busyUserIds;
  final ValueChanged<Map<String, dynamic>> onOpenUser;
  final ValueChanged<String> onFollow;
  final ValueChanged<String> onDismiss;
  final VoidCallback? onOpenCommunity;
  final bool compact;

  const SuggestedContactsSlide({
    super.key,
    required this.users,
    required this.busyUserIds,
    required this.onOpenUser,
    required this.onFollow,
    required this.onDismiss,
    this.onOpenCommunity,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      if (compact) {
        return _CompactEmptySlide(
          icon: Icons.person_add_alt_1_outlined,
          title: 'Keine Vorschläge',
          text: 'Später wieder prüfen.',
          actionLabel: 'Entdecken',
          onAction: onOpenCommunity,
        );
      }
      return _EmptySlide(
        icon: Icons.person_add_alt_1_outlined,
        title: 'Neue Kontakte',
        text: 'Gerade keine neuen Vorschläge. Schau später wieder rein.',
        actionLabel: 'Entdecken',
        onAction: onOpenCommunity,
      );
    }

    if (compact) {
      final visibleUsers = users.take(_compactContactLimit).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vorschläge',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFFA0AEC0),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                physics: const BouncingScrollPhysics(),
                itemCount: visibleUsers.length,
                separatorBuilder: (_, _) => Divider(
                  height: 5,
                  thickness: 1,
                  color: Colors.white.withValues(alpha: 0.045),
                ),
                itemBuilder: (context, index) {
                  final user = visibleUsers[index];
                  final id = user['id'] as String? ?? '';
                  final name = SocialService.publicDisplayName(
                    user,
                    fallbackUserId: id,
                  );
                  final handle = SocialService.publicHandle(
                    user,
                    fallbackUserId: id,
                  );
                  return _ContactRow(
                    name: name,
                    handle: handle,
                    grund:
                        SocialService.mutualFollowersLine(user) ?? 'Neu dabei',
                    avatarUrl: user['avatar_url'] as String?,
                    busy: busyUserIds.contains(id),
                    onTap: () => onOpenUser(user),
                    onFollow: id.isEmpty ? null : () => onFollow(id),
                    onDismiss: id.isEmpty ? null : () => onDismiss(id),
                    compact: true,
                  );
                },
              ),
            ),
          ),
        ],
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
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: compact ? 6 : 8),
        Expanded(
          child: Scrollbar(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              itemCount: users.length > 5 ? 5 : users.length,
              separatorBuilder: (_, _) => SizedBox(height: compact ? 6 : 7),
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
                  grund: SocialService.mutualFollowersLine(user) ?? 'Neu dabei',
                  avatarUrl: user['avatar_url'] as String?,
                  busy: busy,
                  onTap: () => onOpenUser(user),
                  onFollow: id.isEmpty ? null : () => onFollow(id),
                  onDismiss: id.isEmpty ? null : () => onDismiss(id),
                  compact: compact,
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
  static const int _compactGroupLimit = 3;

  final List<Map<String, dynamic>> groups;
  final Set<String> busyGroupIds;
  final Set<String> joinedGroupIds;
  final ValueChanged<String> onJoin;
  final VoidCallback? onOpenCommunity;
  final bool compact;

  const PublicGroupsSlide({
    super.key,
    required this.groups,
    required this.busyGroupIds,
    required this.joinedGroupIds,
    required this.onJoin,
    this.onOpenCommunity,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      if (compact) {
        return _CompactEmptySlide(
          icon: Icons.groups_outlined,
          title: 'Keine Gruppen',
          text: 'Neue Gruppen findest du in der Community.',
          actionLabel: 'Finden',
          onAction: onOpenCommunity,
        );
      }
      return _EmptySlide(
        icon: Icons.groups_outlined,
        title: 'Öffentliche Gruppen',
        text: 'Aktuell ist keine offene Gruppe verfügbar.',
        actionLabel: 'Community',
        onAction: onOpenCommunity,
      );
    }

    if (compact) {
      final visibleGroups = groups.take(_compactGroupLimit).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Gruppen',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFFA0AEC0),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                physics: const BouncingScrollPhysics(),
                itemCount: visibleGroups.length,
                separatorBuilder: (_, _) => Divider(
                  height: 5,
                  thickness: 1,
                  color: Colors.white.withValues(alpha: 0.045),
                ),
                itemBuilder: (context, index) {
                  final group = visibleGroups[index];
                  final id = group['id'] as String? ?? '';
                  final members =
                      (group['group_members'] as List?)?.length ?? 0;
                  final joined = joinedGroupIds.contains(id);
                  final busy = busyGroupIds.contains(id);

                  return _GroupPreviewRow(
                    name: group['name']?.toString() ?? 'Gruppe',
                    memberCount: members,
                    joined: joined,
                    busy: busy,
                    onJoin: id.isEmpty ? null : () => onJoin(id),
                    compact: true,
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          compact ? 'Gruppen' : 'Öffentliche Gruppen',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFA0AEC0),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: compact ? 6 : 8),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            physics: compact
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: groups.length,
            separatorBuilder: (_, _) => SizedBox(height: compact ? 6 : 7),
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
                compact: compact,
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
  final bool compact;

  const EventsComingSoonSlide({
    super.key,
    this.onOpenCommunity,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const _CompactEmptySlide(
        icon: Icons.event_outlined,
        title: 'Events',
        text: 'Event-Planung folgt bald.',
      );
    }
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

  /// Warum wird diese Person vorgeschlagen?
  ///
  /// 2026-08-11 (vucko „ich moechte auch noch, dass das gekennzeichnet wird"):
  /// Bisher stand unter dem Namen nur der @-Name — die Karte sagte also nie,
  /// WARUM jemand auftaucht. SocialService.mutualFollowersLine baute den Satz
  /// („@a und @b folgen diesem Account") schon lange, wurde aber NIRGENDS
  /// aufgerufen. Fehlen gemeinsame Bekannte, steht dort „Neu dabei" statt
  /// einer leeren Zeile.
  final String? grund;
  final String? avatarUrl;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onFollow;
  final VoidCallback? onDismiss;
  final bool compact;

  const _ContactRow({
    required this.name,
    required this.handle,
    this.grund,
    required this.avatarUrl,
    required this.busy,
    required this.onTap,
    required this.onFollow,
    required this.onDismiss,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 28,
          child: Row(
            children: [
              UserAvatar(
                name: name,
                avatarUrl: avatarUrl,
                radius: 11,
                onTap: onTap,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    Text(
                      grund ?? handle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFA0AEC0),
                        fontSize: 8.4,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 3),
              _MiniActionButton(
                label: 'Folgen',
                icon: Icons.person_add_alt_1,
                busy: busy,
                onTap: onFollow,
                compact: true,
              ),
              const SizedBox(width: 4),
              _DismissButton(onTap: onDismiss, compact: true),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(compact ? 7 : 8),
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
                radius: compact ? 14 : 15,
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
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 11.5 : 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFFA0AEC0),
                          fontSize: compact ? 9.5 : 10,
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
          SizedBox(height: compact ? 6 : 7),
          Align(
            alignment: Alignment.centerLeft,
            child: _MiniActionButton(
              label: 'Folgen',
              icon: Icons.person_add_alt_1,
              busy: busy,
              onTap: onFollow,
              compact: compact,
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
  final bool compact;

  const _GroupPreviewRow({
    required this.name,
    required this.memberCount,
    required this.joined,
    required this.busy,
    required this.onJoin,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return SizedBox(
        height: 28,
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: AppAccentColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.groups_2_outlined,
                color: AppAccentColors.accent,
                size: 14,
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                    ),
                  ),
                  Text(
                    '$memberCount Mitglieder',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFA0AEC0),
                      fontSize: 8.4,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _MiniActionButton(
              label: joined ? 'Drin' : 'Beitreten',
              icon: joined ? Icons.check : Icons.login,
              busy: busy,
              onTap: joined ? null : onJoin,
              compact: true,
            ),
          ],
        ),
      );
    }

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
                maxLines: 2,
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
                    maxLines: 2,
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
          compact: false,
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
  final bool compact;

  const _MiniActionButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 72 : 108),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: compact ? 22 : 28,
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 9),
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
                        size: compact ? 10.5 : 13,
                      ),
              ),
              SizedBox(width: compact ? 3 : 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 9.5 : 11,
                    fontWeight: FontWeight.w700,
                    height: 1,
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
  final bool compact;

  const _DismissButton({required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: compact ? 21 : 26,
        height: compact ? 21 : 26,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Icon(
          Icons.close,
          color: const Color(0xFFA0AEC0),
          size: compact ? 12 : 14,
        ),
      ),
    );
  }
}

class _CompactEmptySlide extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CompactEmptySlide({
    required this.icon,
    required this.title,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppAccentColors.accent, size: 19),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Expanded(
            child: Text(
              text,
              maxLines: label == null ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFA0AEC0),
                fontSize: 10.5,
                height: 1.18,
              ),
            ),
          ),
          if (label != null && onAction != null) ...[
            const SizedBox(height: 7),
            _MiniActionButton(
              label: label,
              icon: Icons.arrow_forward,
              busy: false,
              onTap: onAction,
              compact: true,
            ),
          ],
        ],
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
                  maxLines: 2,
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
