import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/application/providers/route_bookmark_provider.dart';
import 'package:cruise_connect/application/providers/saved_routes_provider.dart';
import 'package:cruise_connect/core/deep_links.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/create_post_page.dart';
import 'package:cruise_connect/presentation/pages/create_group_page.dart';
import 'package:cruise_connect/presentation/pages/community_chats_tab.dart';
import 'package:cruise_connect/presentation/pages/group_lobby_page.dart';
import 'package:cruise_connect/presentation/pages/user_profile_page.dart';
import 'package:cruise_connect/presentation/widgets/mentions.dart';
import 'package:cruise_connect/presentation/widgets/social/route_attachment_card.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';
import 'package:cruise_connect/presentation/widgets/moderation_actions.dart';
import 'package:cruise_connect/presentation/widgets/badge_unlock_popup.dart';
import 'package:cruise_connect/presentation/utils/share_helper.dart';

class CommunityPage extends StatefulWidget {
  final int refreshKey;
  final int? tutorialTabIndex;
  const CommunityPage({super.key, this.refreshKey = 0, this.tutorialTabIndex});

  static final ValueNotifier<String?> pendingGroupFocus =
      ValueNotifier<String?>(null);

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage>
    with SingleTickerProviderStateMixin {
  @override
  void didUpdateWidget(CommunityPage old) {
    super.didUpdateWidget(old);
    if (widget.refreshKey != old.refreshKey && widget.refreshKey > 0) {
      _scheduleLoadData();
    }
    if (widget.tutorialTabIndex != null &&
        widget.tutorialTabIndex != old.tutorialTabIndex) {
      _animateToTutorialTab(widget.tutorialTabIndex!);
    }
  }

  late TabController _tabController;

  bool _loading = true;
  List<Map<String, dynamic>> _myGroups = [];
  List<Map<String, dynamic>> _discoverGroups = [];
  List<Map<String, dynamic>> _suggestedUsers = [];
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic>? _searchedGroup;
  int _unreadNotifications = 0;
  final _searchController = TextEditingController();
  // Group-Discover-Filter
  final _groupSearchController = TextEditingController();
  String _groupSearchQuery = '';
  double _groupRadiusKm = 100; // 0 = aus
  bool _groupRadiusEnabled = false;
  Position? _userPosition;
  RealtimeChannel? _postsChannel;
  RealtimeChannel? _groupsChannel;
  RealtimeChannel? _notificationsChannel;
  final Set<String> _expandedGroupNames = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    final tutorialIndex = widget.tutorialTabIndex;
    if (tutorialIndex != null && tutorialIndex >= 0 && tutorialIndex < 4) {
      _tabController.index = tutorialIndex;
    }
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    CommunityPage.pendingGroupFocus.addListener(_onPendingGroupFocus);
    _scheduleLoadData();
    _setupRealtime();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPendingGroupFocus());
  }

  void _onPendingGroupFocus() {
    final groupId = CommunityPage.pendingGroupFocus.value;
    if (groupId == null || !mounted) return;
    CommunityPage.pendingGroupFocus.value = null;
    if (_tabController.index != 1) {
      _tabController.animateTo(1);
    }
    _scheduleLoadData();
  }

  void _scheduleLoadData() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  void _animateToTutorialTab(int index) {
    if (index < 0 || index >= _tabController.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tabController.index == index) return;
      _tabController.animateTo(index);
    });
  }

  @override
  void dispose() {
    _postsChannel?.unsubscribe();
    _groupsChannel?.unsubscribe();
    _notificationsChannel?.unsubscribe();
    CommunityPage.pendingGroupFocus.removeListener(_onPendingGroupFocus);
    _tabController.dispose();
    _searchController.dispose();
    _groupSearchController.dispose();
    super.dispose();
  }

  Future<void> _ensureUserPosition() async {
    if (_userPosition != null) return;
    try {
      final ok = await Geolocator.checkPermission();
      if (ok == LocationPermission.denied) {
        final req = await Geolocator.requestPermission();
        if (req == LocationPermission.denied ||
            req == LocationPermission.deniedForever) {
          return;
        }
      }
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _userPosition = pos);
    } catch (e) {
      debugPrint('[Community] Position-Fehler: $e');
    }
  }

  double _distanceKm(double lat, double lng) {
    final p = _userPosition;
    if (p == null) return double.infinity;
    return Geolocator.distanceBetween(p.latitude, p.longitude, lat, lng) /
        1000.0;
  }

  List<Map<String, dynamic>> _applyGroupDiscoverFilters(
    List<Map<String, dynamic>> groups,
  ) {
    final query = _groupSearchQuery.trim().toLowerCase();
    return groups.where((g) {
      if (g['is_active'] == true) return false;
      // Textsuche: Gruppen-Name + Owner/Mitglieder-Username
      if (query.isNotEmpty) {
        final name = (g['name'] as String? ?? '').toLowerCase();
        final ownerProfile = g['profiles'] as Map<String, dynamic>?;
        final ownerName = (ownerProfile?['username'] ?? '')
            .toString()
            .toLowerCase();
        final matches = name.contains(query) || ownerName.contains(query);
        if (!matches) return false;
      }
      // Radius-Filter
      if (_groupRadiusEnabled && _userPosition != null) {
        final loc = g['start_location'] as Map<String, dynamic>?;
        final lat = (loc?['lat'] as num?)?.toDouble();
        final lng = (loc?['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) return false;
        if (_distanceKm(lat, lng) > _groupRadiusKm) return false;
      }
      return true;
    }).toList();
  }

  void _setupRealtime() {
    final db = Supabase.instance.client;

    // Echtzeit-Updates für Posts (neue Posts, Likes, Kommentare)
    _postsChannel = db
        .channel('public:posts')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'posts',
          callback: (payload) {
            debugPrint(
              '[Community] Realtime post update: ${payload.eventType}',
            );
            _loadData();
          },
        )
        .subscribe();

    // Echtzeit-Updates fuer Gruppen-Listen.
    _groupsChannel = db
        .channel('public:groups_overview')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'groups',
          callback: (_) => _loadData(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'group_members',
          callback: (_) => _loadData(),
        )
        .subscribe();

    // Echtzeit-Updates für Benachrichtigungen
    final uid = db.auth.currentUser?.id;
    if (uid != null) {
      _notificationsChannel = db
          .channel('public:notifications:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: uid,
            ),
            callback: (payload) {
              debugPrint('[Community] New notification');
              if (mounted) {
                setState(() => _unreadNotifications++);
              }
            },
          )
          .subscribe();
    }
  }

  Future<void> _loadData() async {
    try {
      final provider = context.read<CommunityProvider>();
      final results = await Future.wait([
        provider.loadAll(),
        SocialService.getMyGroups(),
        SocialService.getDiscoverGroups(),
        SocialService.getUnreadCount(),
        SocialService.getSuggestedUsers(),
      ]);

      if (mounted) {
        setState(() {
          _myGroups = results[1] as List<Map<String, dynamic>>;
          _discoverGroups = results[2] as List<Map<String, dynamic>>;
          _unreadNotifications = results[3] as int;
          _suggestedUsers = results[4] as List<Map<String, dynamic>>;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Community] Daten laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searchedGroup = null;
      });
      return;
    }

    final looksLikeCode = RegExp(
      r'^\s*cc[\s\-_]?[A-Z0-9]{0,6}',
      caseSensitive: false,
    ).hasMatch(query);

    final futures = <Future<dynamic>>[SocialService.searchUsers(query)];
    if (looksLikeCode) {
      futures.add(SocialService.findGroupByCode(query));
    }
    final results = await Future.wait(futures);

    if (!mounted) return;
    final users = results[0] as List<Map<String, dynamic>>;
    final provider = context.read<CommunityProvider>();
    provider.seedProfiles(users);
    for (final user in users) {
      provider.seedFollowStatus(
        user['id'] as String,
        user['follow_status'] as String?,
      );
    }
    setState(() {
      _searchResults = users;
      _searchedGroup = looksLikeCode
          ? results[1] as Map<String, dynamic>?
          : null;
    });
  }

  bool _looksLikeGroupCode(String query) {
    return RegExp(
      r'^\s*cc[\s\-_]?[A-Z0-9]{0,6}',
      caseSensitive: false,
    ).hasMatch(query);
  }

  Future<void> _handleGroupDiscoverSearchChanged(String value) async {
    setState(() => _groupSearchQuery = value);
    if (!_looksLikeGroupCode(value)) {
      setState(() => _searchedGroup = null);
      return;
    }
    final result = await SocialService.findGroupByCode(value);
    if (!mounted || _groupSearchController.text != value) return;
    setState(() => _searchedGroup = result);
  }

  String _formatGroupDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diffDays = target.difference(today).inDays;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    String prefix;
    if (diffDays == 0) {
      prefix = 'Heute';
    } else if (diffDays == 1) {
      prefix = 'Morgen';
    } else if (diffDays > 1 && diffDays < 7) {
      final wds = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
      prefix = wds[dt.weekday - 1];
    } else {
      final d = dt.day.toString().padLeft(2, '0');
      final m = dt.month.toString().padLeft(2, '0');
      prefix = '$d.$m.${dt.year}';
    }
    return '$prefix · $hh:$mm';
  }

  String _formatTimeAgo(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes} Min.';
    if (diff.inHours < 24) return '${diff.inHours} Std.';
    if (diff.inDays < 30) return '${diff.inDays} Tage';
    return '${(diff.inDays / 30).floor()} Mon.';
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<AppAccentProvider>().color;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        title: const Text(
          'Community',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => _showSearchDialog(),
          ),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.white),
                onPressed: () => _showNotifications(),
              ),
              if (_unreadNotifications > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$_unreadNotifications',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelPadding: EdgeInsets.zero,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: accent, width: 2.5),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: const Color(0xFF3A3A45),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13.5,
            height: 1.2,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            height: 1.2,
          ),
          tabs: [
            _buildTabLabel('Feed'),
            _buildTabLabel('Fahrten'),
            _buildTabLabel('Chats'),
            _buildTabLabel('Entdecken'),
          ],
        ),
        elevation: 0,
      ),
      floatingActionButton: _tabController.index == 2
          ? null
          : FloatingActionButton(
              heroTag: 'community_fab',
              backgroundColor: accent,
              child: Icon(
                _tabController.index == 1 ? Icons.group_add : Icons.add,
                color: Colors.white,
              ),
              onPressed: () async {
                if (_tabController.index == 1) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateGroupPage()),
                  );
                } else {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreatePostPage()),
                  );
                }

                _loadData();
              },
            ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: accent))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFeedTab(),
                _buildGroupsTab(),
                const CommunityChatsTab(),
                _buildDiscoverTab(),
              ],
            ),
    );
  }

  Widget _buildTabLabel(String label) {
    return Tab(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1, softWrap: false),
        ),
      ),
    );
  }

  // ── Feed Tab ──────────────────────────────────────────────────────────

  Widget _buildFeedTab() {
    final feedPosts = context.watch<CommunityProvider>().feedPosts;
    if (feedPosts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, color: Colors.grey[700], size: 48),
              const SizedBox(height: 12),
              const Text(
                'Dein Feed ist leer',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Folge anderen Nutzern oder lade Freunde ein, um Posts zu sehen.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _shareInviteLink(context),
                  icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
                  label: const Text(
                    'Freunde einladen',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppAccentColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _tabController.animateTo(2);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _showSearchDialog();
                    });
                  },
                  icon: const Icon(Icons.search, color: Colors.white),
                  label: const Text(
                    'Freunde suchen',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppAccentColors.accent),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppAccentColors.accent,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: feedPosts.length,
        separatorBuilder: (_, _) =>
            const Divider(color: Colors.white10, height: 1),
        itemBuilder: (context, index) => _buildPostItem(feedPosts[index]),
      ),
    );
  }

  // ── Groups Tab ────────────────────────────────────────────────────────

  Widget _buildGroupsTab() {
    final hasMine = _myGroups.isNotEmpty;
    final hasDiscover = _discoverGroups.isNotEmpty;

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppAccentColors.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF12151C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white54, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hier geht es um Gruppenfahrten mit Route und Startzeit.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          _buildSectionHeader('Beigetretene öffentliche Gruppenfahrten'),
          const SizedBox(height: 8),
          if (!hasMine)
            _buildEmptyHint(
              'Du bist noch in keiner öffentlichen Gruppenfahrt. Erstelle eine Fahrt oder tritt weiter unten einer bei.',
            )
          else
            for (final g in _myGroups)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupLobbyPage(groupId: g['id']),
                      ),
                    );
                    _loadData();
                  },
                  child: _buildGroupCard(g, true),
                ),
              ),

          const SizedBox(height: 24),

          _buildSectionHeader('Weitere Gruppenfahrten entdecken'),
          const SizedBox(height: 8),
          _buildGroupDiscoverFilters(),
          const SizedBox(height: 12),
          Builder(
            builder: (_) {
              final filtered = _applyGroupDiscoverFilters(_discoverGroups);
              final codeResult = _looksLikeGroupCode(_groupSearchQuery)
                  ? _searchedGroup
                  : null;
              if (codeResult != null) {
                return Column(
                  children: [
                    _buildInlineGroupCodeResult(codeResult),
                    const SizedBox(height: 12),
                    for (final g in filtered)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    GroupLobbyPage(groupId: g['id']),
                              ),
                            );
                            _loadData();
                          },
                          child: _buildGroupCard(g, false),
                        ),
                      ),
                  ],
                );
              }
              if (!hasDiscover) {
                return _buildEmptyHint(
                  'Gerade keine offenen Gruppen in Sicht.',
                );
              }
              if (filtered.isEmpty) {
                return _buildEmptyHint(
                  'Keine Treffer — probier andere Filter.',
                );
              }
              return Column(
                children: [
                  for (final g in filtered)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupLobbyPage(groupId: g['id']),
                            ),
                          );
                          _loadData();
                        },
                        child: _buildGroupCard(g, false),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGroupDiscoverFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text-Suche
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _groupSearchController,
            maxLength: AppInputLimits.searchQueryMaxLength,
            inputFormatters: AppInputLimits.lengthFormatters(
              AppInputLimits.searchQueryMaxLength,
            ),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(
              counterText: '',
              hintText: 'Suche nach Gruppe oder User...',
              hintStyle: TextStyle(color: Colors.grey),
              prefixIcon: Icon(Icons.search, color: Colors.grey, size: 20),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: _handleGroupDiscoverSearchChanged,
          ),
        ),
        const SizedBox(height: 12),
        // Radius-Filter
        Row(
          children: [
            Checkbox(
              value: _groupRadiusEnabled,
              activeColor: AppAccentColors.accent,
              onChanged: (v) async {
                setState(() => _groupRadiusEnabled = v ?? false);
                if (_groupRadiusEnabled) await _ensureUserPosition();
                if (mounted) setState(() {});
              },
            ),
            const Icon(Icons.my_location, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(
              _groupRadiusEnabled
                  ? 'Umkreis: ${_groupRadiusKm.toStringAsFixed(0)} km'
                  : 'Umkreis-Filter aus',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
        if (_groupRadiusEnabled)
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppAccentColors.accent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: AppAccentColors.accent,
              overlayColor: AppAccentColors.accent.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: _groupRadiusKm,
              min: 10,
              max: 100,
              divisions: 18,
              label: '${_groupRadiusKm.toStringAsFixed(0)} km',
              onChanged: (v) => setState(() => _groupRadiusKm = v),
            ),
          ),
        if (_groupRadiusEnabled && _userPosition == null)
          const Padding(
            padding: EdgeInsets.only(left: 8, top: 2),
            child: Text(
              'Standort wird geladen... (Berechtigung erforderlich)',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildEmptyHint(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12151C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.grey, fontSize: 13),
      ),
    );
  }

  // ── Discover Tab ──────────────────────────────────────────────────────

  Widget _buildDiscoverTab() {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final provider = context.watch<CommunityProvider>();
    final discoverPosts = provider.discoverPosts;
    final showUserSuggestions = provider.followingCount < 5;

    final children = <Widget>[];

    if (discoverPosts.isEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text(
              'Noch keine Posts in der Community',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    } else {
      // Positionierungs-Algo:
      // - Nie als erstes Item.
      // - Erstes Karussell nach 10–15 Posts (zufällig).
      // - Danach jeweils 10–15 Posts Abstand.
      // - Gruppen & User-Vorschläge abwechselnd (nie direkt nacheinander).
      final rand = math.Random(discoverPosts.length);
      int nextInsertAt = 10 + rand.nextInt(6); // 10..15
      bool nextIsGroups = rand.nextBool();
      // Bei einer Invite-Kachel pro Galerie-Zyklus zusätzlich ab und zu einblenden.
      bool inviteShown = false;

      for (var i = 0; i < discoverPosts.length; i++) {
        final post = discoverPosts[i];
        final isOwnPost = post['user_id'] == currentUserId;
        children.add(_buildPostItem(post, showFollow: !isOwnPost));
        if (i < discoverPosts.length - 1) {
          children.add(const Divider(color: Colors.white10, height: 1));
        }

        final after = i + 1;
        if (after >= nextInsertAt) {
          Widget inserted;
          if (nextIsGroups) {
            if (_discoverGroups.isNotEmpty) {
              inserted = _buildGroupsCarousel();
            } else {
              inserted = _buildCreateGroupTile();
            }
          } else {
            if (showUserSuggestions && _suggestedUsers.isNotEmpty) {
              // Gelegentlich Invite-Kachel statt User-Vorschlag (einmal pro Galerie).
              if (!inviteShown && rand.nextInt(3) == 0) {
                inserted = _buildInviteFriendsTile();
                inviteShown = true;
              } else {
                inserted = _buildUsersCarousel();
              }
            } else {
              inserted = _buildInviteFriendsTile();
              inviteShown = true;
            }
          }
          children.add(inserted);
          nextIsGroups = !nextIsGroups;
          nextInsertAt = after + 10 + rand.nextInt(6);
        }
      }
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppAccentColors.accent,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: children,
      ),
    );
  }

  Widget _buildCarouselSection({
    required String title,
    required double height,
    required int itemCount,
    required double itemWidth,
    required IndexedWidgetBuilder itemBuilder,
    String? subtitle,
  }) {
    final ctrl = PageController(
      viewportFraction: itemWidth / MediaQuery.of(context).size.width,
    );
    return Column(
      children: [
        const SizedBox(height: 10),
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.10)),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: const BoxDecoration(color: Color(0xFF11141B)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppAccentColors.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(29, 0, 16, 10),
                  child: Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )
              else
                const SizedBox(height: 6),
              SizedBox(
                height: height,
                child: PageView.builder(
                  controller: ctrl,
                  padEnds: false,
                  itemCount: itemCount,
                  itemBuilder: itemBuilder,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.10)),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildCreateGroupTile() {
    return Column(
      children: [
        const SizedBox(height: 10),
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.10)),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF12151C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppAccentColors.accent.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.group_add,
                    color: AppAccentColors.accent,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Keine aktiven Gruppen in der Nähe',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Starte selbst eine — andere können beitreten.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateGroupPage()),
                  );
                  _loadData();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppAccentColors.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Aktive Gruppe erstellen',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.10)),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildInviteFriendsTile() {
    return Column(
      children: [
        const SizedBox(height: 10),
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.10)),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF12151C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.person_add_alt_1,
                    color: AppAccentColors.accent,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Freunde einladen',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Noch mehr Fahrer? Lade deine Crew zu Cruise Connector ein.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _shareInviteLink(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppAccentColors.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Einladungslink teilen',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.10)),
        const SizedBox(height: 10),
      ],
    );
  }

  Future<void> _shareInviteLink(BuildContext context) async {
    const link = 'https://cruiseconnector.at/invite';
    await shareText(
      context,
      text:
          'Komm mit auf Cruise Connector — Routen planen, cruisen & sharen. $link',
      subject: 'Join Cruise Connector',
    );
  }

  Future<void> _sharePost(
    BuildContext context,
    Map<String, dynamic> post,
  ) async {
    final postId = post['id'];
    final profile = post['profiles'] as Map<String, dynamic>?;
    final name = SocialService.publicDisplayName(
      profile,
      fallbackUserId: post['user_id'] as String?,
    );
    final link = CruiseDeepLinks.postUri(postId.toString()).toString();
    await shareText(
      context,
      text: 'Post von @$name auf Cruise Connector: $link',
      subject: 'Cruise Connector Post',
    );
  }

  Widget _buildUsersCarousel() {
    final visibleCount = math.min(_suggestedUsers.length, 5);
    return _buildCarouselSection(
      title: 'Leute, denen du folgen könntest',
      height: 170,
      itemCount: visibleCount,
      itemWidth: 160,
      itemBuilder: (ctx, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: _buildSuggestedUserCard(_suggestedUsers[i]),
      ),
    );
  }

  Widget _buildGroupsCarousel() {
    return _buildCarouselSection(
      title: 'Gruppen entdecken',
      height: 140,
      itemCount: _discoverGroups.length,
      itemWidth: 220,
      itemBuilder: (ctx, i) {
        final group = _discoverGroups[i];
        final groupId = group['id'] as String;
        final nameExpanded = _expandedGroupNames.contains(groupId);
        final memberCount = (group['group_members'] as List?)?.length ?? 0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1F26),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() {
                      if (nameExpanded) {
                        _expandedGroupNames.remove(groupId);
                      } else {
                        _expandedGroupNames.add(groupId);
                      }
                    });
                  },
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    child: Text(
                      group['name'] ?? '',
                      maxLines: nameExpanded ? 3 : 1,
                      overflow: nameExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.people, color: AppAccentColors.accent, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '$memberCount',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () async {
                    await _joinVisibleGroup(group['id'] as String);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppAccentColors.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Beitreten',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Post Item ─────────────────────────────────────────────────────────

  Widget _buildSuggestedUserCard(Map<String, dynamic> user) {
    final id = user['id'] as String;
    final provider = context.watch<CommunityProvider>();
    final status = provider.followStatus(
      id,
      fallback: user['follow_status'] as String? ?? 'none',
    );
    final isConnected = status == 'accepted' || status == 'pending';
    final isPrivate = user['is_private'] == true;
    final name = SocialService.publicDisplayName(
      user,
      fallbackUserId: user['id'] as String?,
    );
    final avatar = user['avatar_url'] as String?;
    return Container(
      width: 140,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          UserAvatar(
            name: name,
            avatarUrl: avatar,
            radius: 24,
            backgroundColor: const Color(0xFF0B0E14),
            onTap: () => _openUserProfile(id, name),
          ),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          GestureDetector(
            onTap: () async {
              final next = await context.read<CommunityProvider>().followUser(
                id,
                targetIsPrivate: isPrivate,
              );
              if (!mounted) return;
              if (next == 'accepted') {
                setState(() {
                  _suggestedUsers.removeWhere((u) => u['id'] == id);
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isConnected
                    ? Colors.transparent
                    : AppAccentColors.accent,
                borderRadius: BorderRadius.circular(12),
                border: isConnected ? Border.all(color: Colors.grey) : null,
              ),
              child: Text(
                status == 'accepted'
                    ? 'Gefolgt'
                    : status == 'pending'
                    ? 'Angefragt'
                    : isPrivate
                    ? 'Anfragen'
                    : 'Folgen',
                style: TextStyle(
                  color: isConnected ? Colors.grey : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openUserProfile(String userId, [String? username]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            UserProfilePage(userId: userId, initialUsername: username),
      ),
    );
  }

  Widget _buildPostItem(Map<String, dynamic> post, {bool showFollow = false}) {
    final profile = post['profiles'] as Map<String, dynamic>?;
    final name = SocialService.publicDisplayName(
      profile,
      fallbackUserId: post['user_id'] as String?,
    );
    final handle = SocialService.publicHandle(
      profile,
      fallbackUserId: post['user_id'] as String?,
    );
    final time = _formatTimeAgo(post['created_at']);
    final content = post['content'] ?? '';
    final postUserId = post['user_id'] as String?;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwnPost = postUserId == currentUserId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar.fromProfile(
            profile,
            radius: 20,
            onTap: postUserId == null
                ? null
                : () => _openUserProfile(postUserId, name),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (postUserId != null) {
                          _openUserProfile(postUserId, name);
                        }
                      },
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        handle,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '· $time',
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    if (showFollow && !isOwnPost && postUserId != null) ...[
                      const SizedBox(width: 8),
                      _buildInlineFollowButton(postUserId, name),
                    ],
                    const Spacer(),
                    // 3-Punkte-Menü: Owner sieht "Löschen", andere sehen
                    // "Beitrag melden" + "Benutzer melden" + "Benutzer blockieren".
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_horiz,
                        color: Colors.grey,
                        size: 18,
                      ),
                      color: const Color(0xFF1C1F26),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onSelected: (value) =>
                          _handlePostMenu(value, post, isOwnPost: isOwnPost),
                      itemBuilder: (_) => [
                        if (isOwnPost)
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  color: AppAccentColors.accent,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Löschen',
                                  style: TextStyle(
                                    color: AppAccentColors.accent,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          PopupMenuItem(
                            value: 'report_post',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.flag_outlined,
                                  color: AppAccentColors.accent,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Beitrag melden',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'report_user',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.person_off_outlined,
                                  color: AppAccentColors.accent,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Benutzer melden',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'block',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.block,
                                  color: AppAccentColors.accent,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Benutzer blockieren',
                                  style: TextStyle(
                                    color: AppAccentColors.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.3,
                    ),
                    children: buildMentionSpans(
                      context: context,
                      text: content,
                      baseStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
                // Route-Chip: Wenn Post eine geteilte Route enthält
                if (post['shared_route_id'] != null) ...[
                  const SizedBox(height: 10),
                  RouteAttachmentCard(
                    routeId: post['shared_route_id'] as String,
                    compact: true,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Kommentar-Button
                    GestureDetector(
                      onTap: () => _showComments(post),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline,
                            color: Colors.grey,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${post['comments_count'] ?? 0}',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Repost-Button
                    _PostRepostButton(
                      postId: post['id'],
                      initialCount: post['reposts_count'] ?? 0,
                    ),
                    // Like-Button
                    _PostLikeButton(
                      postId: post['id'],
                      initialCount: post['likes_count'] ?? 0,
                    ),
                    if (post['shared_route_id'] != null)
                      _RouteBookmarkButton(
                        routeId: post['shared_route_id'] as String,
                      ),
                    // Share
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _sharePost(context, post),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Icon(
                            Icons.share_outlined,
                            color: Colors.grey,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Reaktion auf das 3-Punkte-Menü an einem Post:
  /// - `delete`        → eigenen Post löschen
  /// - `report_post`   → Beitrag-Meldung
  /// - `report_user`   → User-Meldung
  /// - `block`         → User blockieren (Confirm + Provider)
  Future<void> _handlePostMenu(
    String value,
    Map<String, dynamic> post, {
    required bool isOwnPost,
  }) async {
    final postId = post['id'] as String?;
    final postUserId = post['user_id'] as String?;
    final profile = post['profiles'] as Map<String, dynamic>?;
    final username = SocialService.publicDisplayName(
      profile,
      fallbackUserId: postUserId,
    );

    if (value == 'delete' && isOwnPost && postId != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C1F26),
          title: const Text(
            'Post löschen?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Dieser Post wird unwiderruflich gelöscht.',
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Abbrechen',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Löschen',
                style: TextStyle(color: AppAccentColors.accent),
              ),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await SocialService.deletePost(postId);
        _loadData();
      }
      return;
    }

    if (value == 'report_post' && postId != null) {
      await ModerationActions.showReportSheet(
        context,
        postId: postId,
        targetLabel: 'Beitrag',
      );
      return;
    }

    if (value == 'report_user' && postUserId != null) {
      await ModerationActions.showReportSheet(
        context,
        userId: postUserId,
        targetLabel: '@$username',
      );
      return;
    }

    if (value == 'block' && postUserId != null) {
      await ModerationActions.confirmAndBlock(
        context,
        userId: postUserId,
        username: username,
      );
      return;
    }
  }

  Widget _buildInlineFollowButton(String targetUserId, String name) {
    final provider = context.watch<CommunityProvider>();
    final isFollowing = provider.isFollowing(targetUserId);
    final color = isFollowing ? Colors.grey : AppAccentColors.accent;
    return GestureDetector(
      onTap: () async {
        if (isFollowing) {
          await provider.unfollowUser(targetUserId);
        } else {
          await provider.followUser(targetUserId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Du folgst jetzt $name'),
                backgroundColor: const Color(0xFF1C1F26),
              ),
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          isFollowing ? 'Gefolgt' : 'Folgen',
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _showComments(Map<String, dynamic> post) {
    final commentController = TextEditingController();
    String? replyToId;
    String? replyToName;
    List<Map<String, dynamic>> comments = [];
    bool loading = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0E14),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                Future<void> reload() async {
                  final fresh = await SocialService.getComments(post['id']);
                  if (sheetContext.mounted) {
                    setSheetState(() {
                      comments = fresh;
                      loading = false;
                    });
                  }
                }

                if (loading && comments.isEmpty) {
                  reload();
                }

                // Top-Level-Kommentare und Replies gruppieren.
                final topLevel = comments
                    .where((c) => c['parent_comment_id'] == null)
                    .toList();
                final replyMap = <String, List<Map<String, dynamic>>>{};
                for (final c in comments) {
                  final parent = c['parent_comment_id'] as String?;
                  if (parent != null) {
                    replyMap.putIfAbsent(parent, () => []).add(c);
                  }
                }

                // Flache Liste (DFS) mit Tiefe — max. 4 Ebenen Verschachtelung.
                const maxDepth = 4;
                final flat = <({Map<String, dynamic> c, int depth})>[];
                void walk(Map<String, dynamic> node, int depth) {
                  flat.add((c: node, depth: depth));
                  if (depth >= maxDepth) return;
                  final kids = replyMap[node['id']] ?? [];
                  for (final k in kids) {
                    walk(k, depth + 1);
                  }
                }

                for (final t in topLevel) {
                  walk(t, 0);
                }

                return Column(
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[600],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Kommentare',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: loading
                          ? Center(
                              child: CircularProgressIndicator(
                                color: AppAccentColors.accent,
                              ),
                            )
                          : topLevel.isEmpty
                          ? const Center(
                              child: Text(
                                'Noch keine Kommentare',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: flat.length,
                              itemBuilder: (context, index) {
                                final entry = flat[index];
                                final cm = entry.c;
                                final depth = entry.depth;
                                return _buildCommentTile(
                                  cm,
                                  depth: depth,
                                  canReply: depth < maxDepth,
                                  onLike: () async {
                                    await SocialService.toggleCommentLike(
                                      cm['id'],
                                    );
                                    await reload();
                                  },
                                  onReply: () {
                                    final cProfile =
                                        cm['profiles'] as Map<String, dynamic>?;
                                    final cName =
                                        SocialService.publicDisplayName(
                                          cProfile,
                                          fallbackUserId:
                                              cm['user_id'] as String?,
                                        );
                                    setSheetState(() {
                                      replyToId = cm['id'] as String;
                                      replyToName = cName;
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    if (replyToId != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        color: const Color(0xFF12151C),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Antwort an @$replyToName',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setSheetState(() {
                                replyToId = null;
                                replyToName = null;
                              }),
                              child: const Icon(
                                Icons.close,
                                color: Colors.grey,
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Kommentar-Eingabe
                    Container(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 8,
                        top: 8,
                        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1F26),
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: MentionTextField(
                              controller: commentController,
                              maxLength: AppInputLimits.commentMaxLength,
                              inputFormatters: AppInputLimits.lengthFormatters(
                                AppInputLimits.commentMaxLength,
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: replyToId != null
                                    ? 'Antwort schreiben...'
                                    : 'Kommentar schreiben — @ erwähnt Follower',
                                hintStyle: const TextStyle(color: Colors.grey),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.send,
                              color: AppAccentColors.accent,
                            ),
                            onPressed: () async {
                              final text = commentController.text.trim();
                              if (text.isEmpty) return;
                              await SocialService.addComment(
                                post['id'],
                                text,
                                parentCommentId: replyToId,
                              );
                              commentController.clear();
                              setSheetState(() {
                                replyToId = null;
                                replyToName = null;
                              });
                              await reload();
                              _loadData();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCommentTile(
    Map<String, dynamic> comment, {
    required int depth,
    required bool canReply,
    required VoidCallback onLike,
    required VoidCallback onReply,
  }) {
    final cProfile = comment['profiles'] as Map<String, dynamic>?;
    final cName = SocialService.publicDisplayName(
      cProfile,
      fallbackUserId: comment['user_id'] as String?,
    );
    final cTime = _formatTimeAgo(comment['created_at']);
    final liked = comment['is_liked'] == true;
    final likesCount = (comment['likes_count'] as int?) ?? 0;
    double indentStep = 20.0;
    final leftPad = 16.0 + depth * indentStep;
    return Container(
      padding: EdgeInsets.only(left: leftPad, right: 16, top: 8, bottom: 8),
      decoration: depth > 0
          ? BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 2,
                ),
              ),
            )
          : null,
      margin: depth > 0
          ? EdgeInsets.only(left: 16.0 + (depth - 1) * indentStep)
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (depth > 0) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 4),
              child: Icon(
                Icons.subdirectory_arrow_right,
                color: Colors.white.withValues(alpha: 0.35),
                size: 16,
              ),
            ),
          ],
          UserAvatar.fromProfile(
            cProfile,
            fallbackName: cName,
            radius: depth == 0 ? 16 : 13,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      cName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      cTime,
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Builder(
                  builder: (ctx) {
                    const baseStyle = TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    );
                    final text = (comment['content'] ?? '').toString();
                    return Text.rich(
                      TextSpan(
                        style: baseStyle,
                        children: buildMentionSpans(
                          context: ctx,
                          text: text,
                          baseStyle: baseStyle,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onLike,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 40,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                liked ? Icons.favorite : Icons.favorite_border,
                                color: liked
                                    ? AppAccentColors.accent
                                    : Colors.grey,
                                size: 14,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '$likesCount',
                                style: TextStyle(
                                  color: liked
                                      ? AppAccentColors.accent
                                      : Colors.grey,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (canReply)
                      GestureDetector(
                        onTap: onReply,
                        child: const Text(
                          'Antworten',
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Group Card ────────────────────────────────────────────────────────

  Widget _buildGroupCard(Map<String, dynamic> group, bool isJoined) {
    final groupId = group['id'] as String;
    final title = group['name']?.toString() ?? '';
    final nameExpanded = _expandedGroupNames.contains(groupId);
    final memberCount = (group['group_members'] as List?)?.length ?? 0;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwner = group['created_by'] == currentUserId;
    final isActive = group['is_active'] == true;
    final isPublic = group['is_public'] == true;
    final startTimeStr = group['start_time'] as String?;
    final startDt = startTimeStr != null
        ? DateTime.tryParse(startTimeStr)
        : null;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? AppAccentColors.accent.withValues(alpha: 0.75)
              : isJoined
              ? AppAccentColors.accent.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        if (nameExpanded) {
                          _expandedGroupNames.remove(groupId);
                        } else {
                          _expandedGroupNames.add(groupId);
                        }
                      });
                    },
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: nameExpanded ? 3 : 1,
                        overflow: nameExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppAccentColors.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Live',
                      style: TextStyle(
                        color: AppAccentColors.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                if (isOwner)
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_horiz,
                      color: Colors.grey,
                      size: 20,
                    ),
                    color: const Color(0xFF1C1F26),
                    padding: EdgeInsets.zero,
                    onSelected: (value) async {
                      if (value == 'delete') {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: const Color(0xFF1C1F26),
                            title: const Text(
                              'Gruppe löschen?',
                              style: TextStyle(color: Colors.white),
                            ),
                            content: const Text(
                              'Die Gruppe wird unwiderruflich gelöscht — auch für alle Mitglieder.',
                              style: TextStyle(color: Colors.grey),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text(
                                  'Abbrechen',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(
                                  'Löschen',
                                  style: TextStyle(
                                    color: AppAccentColors.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await SocialService.deleteGroup(group['id']);
                          _loadData();
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              color: AppAccentColors.accent,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Löschen',
                              style: TextStyle(color: AppAccentColors.accent),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else if (isJoined)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppAccentColors.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Dabei',
                      style: TextStyle(
                        color: AppAccentColors.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () async {
                      await _joinVisibleGroup(group['id'] as String);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppAccentColors.accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Beitreten',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildGroupChip(
                  isPublic ? 'Öffentlich' : 'Privat',
                  isPublic ? Colors.greenAccent : Colors.orangeAccent,
                  isPublic ? Icons.public_outlined : Icons.lock_outline_rounded,
                ),
                if (isOwner)
                  _buildGroupChip(
                    'Leader',
                    AppAccentColors.accent,
                    Icons.admin_panel_settings_outlined,
                  )
                else if (isJoined)
                  _buildGroupChip(
                    'Mitglied',
                    Colors.white70,
                    Icons.check_circle_outline,
                  ),
              ],
            ),
            if (startDt != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.event, color: AppAccentColors.accent, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    _formatGroupDate(startDt),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
            if (group['route_name'] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.terrain, color: Colors.white70, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    group['route_name'] ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ],
            if (group['stats'] != null) ...[
              const SizedBox(height: 4),
              Text(
                group['stats'] ?? '',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.local_fire_department,
                  color: AppAccentColors.accent,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  '$memberCount Fahrer',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            if (group['time_location'] != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.flag, color: Colors.white70, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    group['time_location'] ?? '',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGroupChip(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ── Search Dialog ─────────────────────────────────────────────────────

  void _showSearchDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0E14),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[600],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        maxLength: AppInputLimits.searchQueryMaxLength,
                        inputFormatters: AppInputLimits.lengthFormatters(
                          AppInputLimits.searchQueryMaxLength,
                        ),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'Benutzer oder Gruppen-Code (CC-XXXXXX)...',
                          hintStyle: const TextStyle(color: Colors.grey),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.grey,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF1C1F26),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (query) async {
                          await _searchUsers(query);
                          setModalState(() {});
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: (_searchResults.isEmpty && _searchedGroup == null)
                          ? Center(
                              child: Text(
                                _searchController.text.isEmpty
                                    ? 'Suche nach Benutzernamen oder Gruppen-Code'
                                    : 'Keine Ergebnisse',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView(
                              controller: scrollController,
                              children: [
                                if (_searchedGroup != null)
                                  _buildSearchGroupResult(_searchedGroup!),
                                ..._searchResults.map((user) {
                                  final username =
                                      SocialService.publicDisplayName(
                                        user,
                                        fallbackUserId: user['id'] as String?,
                                      );
                                  final handle = SocialService.publicHandle(
                                    user,
                                    fallbackUserId: user['id'] as String?,
                                  );
                                  return ListTile(
                                    onTap: () {
                                      Navigator.pop(context);
                                      _openUserProfile(user['id'], username);
                                    },
                                    leading: UserAvatar.fromProfile(
                                      user,
                                      fallbackName: username,
                                      radius: 20,
                                    ),
                                    title: Text(
                                      username,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    subtitle: Text(
                                      handle,
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 13,
                                      ),
                                    ),
                                    trailing: _FollowButton(
                                      userId: user['id'],
                                      initialStatus:
                                          user['follow_status'] as String?,
                                      isPrivate: user['is_private'] == true,
                                      onChanged: () => _loadData(),
                                    ),
                                  );
                                }),
                              ],
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    ).then((_) => _searchController.clear());
  }

  Widget _buildSearchGroupResult(Map<String, dynamic> group) {
    final isPublic = group['is_public'] == true;
    final creator = group['profiles'] as Map<String, dynamic>?;
    final creatorName = SocialService.publicDisplayName(
      creator,
      fallbackUserId: group['created_by'] as String?,
    );
    final code = group['invite_code'] as String? ?? '';
    final joinCode = group['_join_code'] as String? ?? code;
    final subtitle = isPublic ? '@$creatorName' : '$code · @$creatorName';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppAccentColors.accent.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.groups, color: AppAccentColors.accent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        group['name']?.toString() ?? 'Gruppe',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isPublic
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isPublic ? 'Öffentlich' : 'Privat',
                        style: TextStyle(
                          color: isPublic ? Colors.green : Colors.orange,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FutureBuilder<Map<String, bool>>(
            future: _groupActionState(group['id'] as String),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const SizedBox(
                  width: 90,
                  height: 36,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              }
              final state = snap.data!;
              final isMember = state['isMember'] == true;
              final hasPending = state['hasPending'] == true;

              if (isMember) {
                return ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            GroupLobbyPage(groupId: group['id'] as String),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppAccentColors.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Öffnen'),
                );
              }
              if (joinCode.isNotEmpty) {
                return ElevatedButton(
                  onPressed: () async {
                    final groupId = await _joinGroupByCode(joinCode);
                    if (groupId == null || !context.mounted) return;
                    Navigator.pop(context);
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupLobbyPage(groupId: groupId),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppAccentColors.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Beitreten'),
                );
              }
              if (isPublic) {
                return ElevatedButton(
                  onPressed: () async {
                    final joined = await _joinVisibleGroup(
                      group['id'] as String,
                    );
                    if (!joined || !context.mounted) return;
                    Navigator.pop(context);
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            GroupLobbyPage(groupId: group['id'] as String),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppAccentColors.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Beitreten'),
                );
              }
              if (hasPending) {
                return OutlinedButton(
                  onPressed: null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey,
                    side: const BorderSide(color: Colors.grey),
                  ),
                  child: const Text('Angefragt'),
                );
              }
              return OutlinedButton(
                onPressed: () async {
                  await SocialService.requestJoinGroup(group['id'] as String);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Beitritts-Anfrage gesendet')),
                  );
                  setState(() {});
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  side: const BorderSide(color: Colors.orange),
                ),
                child: const Text('Anfrage'),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInlineGroupCodeResult(Map<String, dynamic> group) {
    final isPublic = group['is_public'] == true;
    final creator = group['profiles'] as Map<String, dynamic>?;
    final creatorName = SocialService.publicDisplayName(
      creator,
      fallbackUserId: group['created_by'] as String?,
    );
    final code = group['invite_code'] as String? ?? '';
    final joinCode = group['_join_code'] as String? ?? code;
    final subtitle = isPublic ? '@$creatorName' : '$code · @$creatorName';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppAccentColors.accent.withValues(alpha: 0.42),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPublic ? Icons.groups_rounded : Icons.lock_rounded,
            color: AppAccentColors.accent,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group['name']?.toString() ?? 'Gruppe',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () async {
              final groupId = await _joinGroupByCode(joinCode);
              if (groupId == null || !mounted) return;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupLobbyPage(groupId: groupId),
                ),
              );
              if (mounted) _loadData();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppAccentColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Beitreten',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, bool>> _groupActionState(String groupId) async {
    final results = await Future.wait([
      SocialService.isMember(groupId),
      SocialService.hasPendingJoinRequest(groupId),
    ]);
    return {'isMember': results[0], 'hasPending': results[1]};
  }

  Future<bool> _joinVisibleGroup(String groupId) async {
    try {
      await SocialService.joinGroup(groupId);
      await _loadData();
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Beitreten nicht moeglich: $e'),
            backgroundColor: const Color(0xFF1C1F26),
          ),
        );
        await _loadData();
      }
      return false;
    }
  }

  // ── Notifications ─────────────────────────────────────────────────────

  Future<String?> _joinGroupByCode(String code) async {
    try {
      final groupId = await SocialService.joinGroupWithCode(code);
      await _loadData();
      return groupId;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Beitreten nicht moeglich: $e'),
            backgroundColor: const Color(0xFF1C1F26),
          ),
        );
        await _loadData();
      }
      return null;
    }
  }

  void _showNotifications() async {
    await SocialService.markAllRead();
    if (!mounted) return;
    setState(() => _unreadNotifications = 0);

    final notifications = await SocialService.getNotifications();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B0E14),
      // Sheet darf bis zu ~75% Screen-Höhe einnehmen, damit lange
      // Listen scrollbar sind statt zu overflowen.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final items = notifications.take(50).toList();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Benachrichtigungen',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Keine Benachrichtigungen',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final n = items[index];
                          final from = n['profiles'] as Map<String, dynamic>?;
                          final fromName = SocialService.publicDisplayName(
                            from,
                            fallbackUserId: n['from_user_id'] as String?,
                          );
                          final fromId = from?['id'] as String?;
                          final type = n['type'];
                          String message;
                          IconData icon;
                          switch (type) {
                            case 'follow':
                              message = '$fromName folgt dir jetzt';
                              icon = Icons.person_add;
                              break;
                            case 'follow_request':
                              message = '$fromName möchte dir folgen';
                              icon = Icons.person_add_alt_1;
                              break;
                            case 'follow_accepted':
                              message =
                                  '$fromName hat deine Anfrage angenommen';
                              icon = Icons.check_circle;
                              break;
                            case 'like':
                              message = '$fromName hat deinen Post geliked';
                              icon = Icons.favorite;
                              break;
                            case 'comment':
                              message = '$fromName hat deinen Post kommentiert';
                              icon = Icons.comment;
                              break;
                            case 'comment_reply':
                              message =
                                  '$fromName hat auf deinen Kommentar geantwortet';
                              icon = Icons.reply;
                              break;
                            case 'comment_like':
                              message =
                                  '$fromName hat deinen Kommentar geliked';
                              icon = Icons.favorite;
                              break;
                            case 'repost':
                              message = '$fromName hat deinen Post geteilt';
                              icon = Icons.repeat;
                              break;
                            case 'group_invite':
                              message =
                                  '$fromName hat dich in eine Gruppe eingeladen';
                              icon = Icons.group_add;
                              break;
                            case 'group_public_created':
                              message =
                                  '$fromName hat eine neue öffentliche Gruppe erstellt';
                              icon = Icons.groups_2;
                              break;
                            case 'group_joined':
                              message =
                                  '$fromName ist deiner Gruppe beigetreten';
                              icon = Icons.group;
                              break;
                            case 'group_ride_started':
                              message =
                                  '$fromName hat die Gruppenfahrt gestartet';
                              icon = Icons.navigation;
                              break;
                            case 'mention':
                              message = '$fromName hat dich erwähnt';
                              icon = Icons.alternate_email;
                              break;
                            default:
                              message = '$fromName hat interagiert';
                              icon = Icons.notifications;
                          }

                          return ListTile(
                            onTap: () {
                              Navigator.pop(sheetContext);
                              final referenceId = n['reference_id'] as String?;
                              final isGroupNotification =
                                  type == 'group_invite' ||
                                  type == 'group_public_created' ||
                                  type == 'group_joined' ||
                                  type == 'group_ride_started';
                              if (isGroupNotification && referenceId != null) {
                                Future.delayed(
                                  const Duration(milliseconds: 150),
                                  () {
                                    if (!mounted) return;
                                    Navigator.push(
                                      this.context,
                                      MaterialPageRoute(
                                        builder: (_) => GroupLobbyPage(
                                          groupId: referenceId,
                                        ),
                                      ),
                                    ).then((_) => _loadData());
                                  },
                                );
                              } else if (fromId != null) {
                                Future.delayed(
                                  const Duration(milliseconds: 150),
                                  () {
                                    if (mounted) {
                                      _openUserProfile(fromId, fromName);
                                    }
                                  },
                                );
                              }
                            },
                            leading: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                UserAvatar.fromProfile(
                                  from,
                                  fallbackName: fromName.toString(),
                                  radius: 18,
                                ),
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF0B0E14),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      icon,
                                      color: AppAccentColors.accent,
                                      size: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            title: Text(
                              message,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              _formatTimeAgo(n['created_at']),
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            trailing: _buildNotificationTrailing(
                              type: type as String?,
                              referenceId: n['reference_id'] as String?,
                              fromId: fromId,
                              sheetContext: sheetContext,
                              setSheetState: () {
                                // Mark as handled lokal: type→null verhindert dass die
                                // Buttons zweimal feuern. Reicht als optisches Feedback;
                                // beim nächsten _loadData ist der DB-State eh aktuell.
                                n['type'] = '_handled';
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget? _buildNotificationTrailing({
    required String? type,
    required String? referenceId,
    required String? fromId,
    required BuildContext sheetContext,
    required VoidCallback setSheetState,
  }) {
    if (type == 'group_invite' && referenceId != null) {
      return GestureDetector(
        onTap: () async {
          final joined = await _joinVisibleGroup(referenceId);
          if (!joined) return;
          if (!sheetContext.mounted) return;
          Navigator.pop(sheetContext);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Gruppe beigetreten!'),
                backgroundColor: Color(0xFF1C1F26),
              ),
            );
            _loadData();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppAccentColors.accent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Beitreten',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    if ((type == 'group_public_created' ||
            type == 'group_joined' ||
            type == 'group_ride_started') &&
        referenceId != null) {
      return GestureDetector(
        onTap: () {
          Navigator.pop(sheetContext);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupLobbyPage(groupId: referenceId),
            ),
          ).then((_) => _loadData());
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: AppAccentColors.accent),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Öffnen',
            style: TextStyle(
              color: AppAccentColors.accent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    if (type == 'follow_request' && fromId != null) {
      final provider = context.read<CommunityProvider>();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () async {
              try {
                setSheetState();
                await provider.acceptFollowRequest(fromId);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Anfrage angenommen'),
                    backgroundColor: Color(0xFF1C1F26),
                  ),
                );
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Anfrage konnte nicht angenommen werden'),
                    backgroundColor: Color(0xFF1C1F26),
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppAccentColors.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Annehmen',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () async {
              try {
                setSheetState();
                await provider.rejectFollowRequest(fromId);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Anfrage abgelehnt'),
                    backgroundColor: Color(0xFF1C1F26),
                  ),
                );
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Anfrage konnte nicht abgelehnt werden'),
                    backgroundColor: Color(0xFF1C1F26),
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Ablehnen',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return null;
  }
}

// ── Follow Button Widget ──────────────────────────────────────────────

class _FollowButton extends StatefulWidget {
  final String userId;
  final VoidCallback onChanged;
  final String? initialStatus;
  final bool isPrivate;
  const _FollowButton({
    required this.userId,
    required this.onChanged,
    this.initialStatus,
    this.isPrivate = false,
  });

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  String _status = 'none';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _seedInitialStatus();
    _checkFollowIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _FollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.initialStatus != widget.initialStatus) {
      _loading = true;
      _seedInitialStatus();
      _checkFollowIfNeeded();
    }
  }

  void _seedInitialStatus() {
    final initial = widget.initialStatus;
    if (initial == null) return;
    _status = initial;
    context.read<CommunityProvider>().seedFollowStatus(widget.userId, initial);
  }

  Future<void> _checkFollowIfNeeded() async {
    final provider = context.read<CommunityProvider>();
    if (provider.hasKnownFollowStatus(widget.userId)) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final result = await provider.ensureFollowStatus(widget.userId);
    if (mounted) {
      setState(() {
        _status = result;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CommunityProvider>();
    final status = provider.followStatus(widget.userId, fallback: _status);
    final stillResolving =
        _loading && !provider.hasKnownFollowStatus(widget.userId);
    if (stillResolving) {
      return SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppAccentColors.accent,
        ),
      );
    }
    if (widget.userId == Supabase.instance.client.auth.currentUser?.id) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () async {
        if (status == 'accepted' || status == 'pending') {
          setState(() => _status = 'none');
          await provider.unfollowUser(widget.userId);
          if (!mounted) return;
        } else {
          final next = await provider.followUser(
            widget.userId,
            targetIsPrivate: widget.isPrivate,
          );
          if (!mounted) return;
          setState(() => _status = next);
        }
        widget.onChanged();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: status == 'none' ? AppAccentColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: status == 'none' ? null : Border.all(color: Colors.grey),
        ),
        child: Text(
          status == 'accepted'
              ? 'Folge ich'
              : status == 'pending'
              ? 'Angefragt'
              : widget.isPrivate
              ? 'Anfragen'
              : 'Folgen',
          style: TextStyle(
            color: status == 'none' ? Colors.white : Colors.grey,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── Post Like Button ──────────────────────────────────────────────────

class _RouteBookmarkButton extends StatefulWidget {
  const _RouteBookmarkButton({required this.routeId});

  final String routeId;

  @override
  State<_RouteBookmarkButton> createState() => _RouteBookmarkButtonState();
}

class _RouteBookmarkButtonState extends State<_RouteBookmarkButton> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<RouteBookmarkProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) provider.ensureChecked(widget.routeId);
    });
  }

  @override
  void didUpdateWidget(covariant _RouteBookmarkButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeId != widget.routeId) {
      context.read<RouteBookmarkProvider>().ensureChecked(widget.routeId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouteBookmarkProvider>();
    final saved = provider.isSaved(widget.routeId);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final saved = await context.read<RouteBookmarkProvider>().toggle(
          widget.routeId,
        );
        if (!context.mounted || saved == null) return;
        await context.read<SavedRoutesProvider>().loadRoutes();
        if (!context.mounted || saved != true) return;
        final gamResult = await GamificationService.calculateAndSync();
        if (!context.mounted || gamResult.newBadges.isEmpty) return;
        await showBadgeUnlockPopup(
          context: context,
          badges: gamResult.newBadges,
        );
      },
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Icon(
            saved ? Icons.bookmark : Icons.bookmark_border,
            color: saved ? const Color(0xFFFFD166) : Colors.grey,
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _PostLikeButton extends StatefulWidget {
  final String postId;
  final int initialCount;
  const _PostLikeButton({required this.postId, required this.initialCount});

  @override
  State<_PostLikeButton> createState() => _PostLikeButtonState();
}

class _PostLikeButtonState extends State<_PostLikeButton> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<CommunityProvider>();
    provider.registerPost({
      'id': widget.postId,
      'likes_count': widget.initialCount,
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) provider.ensureLikedChecked(widget.postId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CommunityProvider>();
    final liked = provider.isLiked(widget.postId);
    final count = provider.likeCount(widget.postId);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.read<CommunityProvider>().toggleLike(widget.postId),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                color: liked ? AppAccentColors.accent : Colors.grey,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  color: liked ? AppAccentColors.accent : Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Post Repost Button ────────────────────────────────────────────────

class _PostRepostButton extends StatefulWidget {
  final String postId;
  final int initialCount;
  const _PostRepostButton({required this.postId, required this.initialCount});

  @override
  State<_PostRepostButton> createState() => _PostRepostButtonState();
}

class _PostRepostButtonState extends State<_PostRepostButton> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<CommunityProvider>();
    provider.registerPost({
      'id': widget.postId,
      'reposts_count': widget.initialCount,
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) provider.ensureRepostedChecked(widget.postId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CommunityProvider>();
    final reposted = provider.isReposted(widget.postId);
    final count = provider.repostCount(widget.postId);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          context.read<CommunityProvider>().toggleRepost(widget.postId),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.repeat,
                color: reposted ? const Color(0xFF34C759) : Colors.grey,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  color: reposted ? const Color(0xFF34C759) : Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
