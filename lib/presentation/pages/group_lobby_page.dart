import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/input_limits.dart';
import '../../data/services/cruise_group_service.dart';
import '../../data/services/group_leaderboard_service.dart';
import '../../data/services/social_service.dart';
import '../../domain/models/cruise_group.dart';
import '../../domain/models/group_member.dart';
import '../widgets/user_avatar.dart';
import 'cruise_mode_page.dart';
import 'user_profile_page.dart';

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
  bool _enteringNavigation = false;
  final Set<String> _busyRoleUpdates = {};

  // 2026-06-23 (vucko X3): Die Rangliste kommt aus user_drive_sessions, das wegen
  // RLS (own-rows-only) NICHT per Realtime an Mitfahrer geliefert wird. Damit
  // jeder in der Lobby zeitnah DASSELBE Ergebnis sieht, fragen wir die
  // deterministische RPC alle paar Sekunden frisch ab (nur solange die Lobby
  // offen ist). Zusätzlich Pull-to-Refresh + Reload bei Rückkehr aus der Fahrt.
  Timer? _leaderboardPoll;

  // 2026-06-21 (vucko Lobby-Netzfehler): Ein vorübergehender Netz-/DNS-Fehler
  // ("Failed host lookup") warf eine Exception, die wie "Gruppe nicht gefunden"
  // aussah und in einer Sackgasse OHNE Retry endete. Jetzt: jede Exception =
  // transienter Fehler → "Verbindung wird hergestellt …" + Auto-Retry mit
  // Backoff, bis es lädt. NUR ein echtes null-Ergebnis (Gruppe existiert
  // wirklich nicht) zeigt "Gruppe nicht gefunden".
  bool _hadNetworkError = false;
  bool _loadInFlight = false;
  int _retryAttempt = 0;
  Timer? _retryTimer;

  List<Map<String, dynamic>> _pendingRequests = [];

  /// 2026-06-23 (vucko X3): Deterministische Gruppen-Rangliste (wer ist am
  /// meisten gefahren / am schnellsten). Wird nach jeder Gruppen-Fahrt befüllt
  /// und in der Lobby gezeigt — leer = Karte ausgeblendet (Pre-Ride-Lobby clean).
  List<GroupLeaderboardEntry> _leaderboard = const [];

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

  bool get _amCreator => _group?.ownerId == _myId;

  bool get _hasOwnerPower => _amOwner || _amCreator;

  RideRole get _myRideRole =>
      _group?.members
          .firstWhere(
            (m) => m.userId == _myId,
            orElse: () => GroupMember(
              id: '',
              groupId: widget.groupId,
              userId: _myId,
              role: MemberRole.passenger,
              rideRole: RideRole.passenger,
              createdAt: DateTime.now(),
            ),
          )
          .rideRole ??
      RideRole.passenger;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
    _startLeaderboardPolling();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _leaderboardPoll?.cancel();
    _groupCh?.unsubscribe();
    _membersCh?.unsubscribe();
    super.dispose();
  }

  void _startLeaderboardPolling() {
    _leaderboardPoll?.cancel();
    _leaderboardPoll = Timer.periodic(
      const Duration(seconds: 12),
      (_) => _refreshLeaderboardQuietly(),
    );
  }

  /// Holt NUR die Rangliste neu (kein Voll-Reload, kein Flackern). setState nur
  /// bei echter Änderung — so erscheinen die Eckdaten der Kollegen wenige
  /// Sekunden nachdem sie ihre Fahrt beendet haben, ohne dass die ganze Lobby
  /// neu aufblitzt.
  Future<void> _refreshLeaderboardQuietly() async {
    if (!mounted || _group == null) return;
    final next = await GroupLeaderboardService.fetch(widget.groupId);
    if (!mounted || !_leaderboardChanged(next)) return;
    setState(() => _leaderboard = next);
  }

  bool _leaderboardChanged(List<GroupLeaderboardEntry> next) {
    if (next.length != _leaderboard.length) return true;
    for (var i = 0; i < next.length; i++) {
      final a = _leaderboard[i];
      final b = next[i];
      if (a.userId != b.userId ||
          a.totalDistanceKm != b.totalDistanceKm ||
          a.maxTopSpeedKmh != b.maxTopSpeedKmh) {
        return true;
      }
    }
    return false;
  }

  Future<void> _load() async {
    // Überlappende Loads vermeiden (Realtime + Retry + manuelle Calls).
    if (_loadInFlight) return;
    _loadInFlight = true;
    try {
      final results = await Future.wait([
        CruiseGroupService.fetch(widget.groupId),
        SocialService.getBlockedAndBlockerIds(),
        GroupLeaderboardService.fetch(widget.groupId),
      ]);
      final g = results[0] as CruiseGroup?;
      final blocked = results[1] as Set<String>;
      final leaderboard = results[2] as List<GroupLeaderboardEntry>;
      if (!mounted) return;
      // Erfolg (auch g == null = Gruppe existiert wirklich nicht): kein
      // Netzfehler mehr, laufenden Retry stoppen.
      _retryTimer?.cancel();
      _retryAttempt = 0;
      setState(() {
        _group = g;
        _blockedIds = blocked;
        _leaderboard = leaderboard;
        _loading = false;
        _hadNetworkError = false;
      });
      // Pending-Requests nur laden, wenn ich Owner bin (RLS sorgt für Rest).
      if (g != null && (g.isOwner(_myId) || g.ownerId == _myId)) {
        final pending = await SocialService.listPendingJoinRequests(
          widget.groupId,
        );
        if (!mounted) return;
        setState(() => _pendingRequests = pending);
      }
    } catch (e) {
      // JEDE Exception hier ist ein transienter Fehler (Netz/DNS/Timeout/RLS-
      // Hänger) — NIEMALS als "Gruppe nicht gefunden" rendern. Wir halten den
      // bereits geladenen Stand (falls vorhanden) und planen einen Auto-Retry.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hadNetworkError = true;
      });
      _scheduleReload();
    } finally {
      _loadInFlight = false;
    }
  }

  /// Plant einen automatischen Reload mit Backoff (1,5s → 3s → 6s, gedeckelt),
  /// damit die Lobby NIE in einer Netzfehler-Sackgasse hängenbleibt: Sobald die
  /// Verbindung zurück ist, lädt sie von selbst. Zusätzlich triggert auch der
  /// Realtime-Reconnect ein _load().
  void _scheduleReload() {
    if (!mounted) return;
    _retryTimer?.cancel();
    _retryAttempt = (_retryAttempt + 1).clamp(1, 4);
    final delayMs = (1500 * (1 << (_retryAttempt - 1))).clamp(1500, 6000);
    _retryTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      _load();
    });
  }

  void _subscribe() {
    _groupCh = CruiseGroupService.subscribeGroup(widget.groupId, (row) {
      if (row['is_active'] == true) {
        // 2026-06-20 (vucko Gruppen-Rejoin): Hat der Nutzer die Fahrt bewusst
        // verlassen, NICHT automatisch zurückziehen — sonst reisst ihn der
        // nächste Leader-Reroute (jede Route-Änderung pingt die Lobby) sofort
        // wieder in die Navigation. Er sieht stattdessen den „Zur laufenden
        // Route"-Button und steigt bewusst wieder ein.
        if (!CruiseModePage.suppressedAutoEnterGroupIds.contains(
          widget.groupId,
        )) {
          _enterNavigation();
        }
      } else {
        // Fahrt vorbei → Suppress aufheben, damit eine neue Fahrt wieder alle
        // automatisch reinholt.
        CruiseModePage.suppressedAutoEnterGroupIds.remove(widget.groupId);
      }
      _load();
    });
    _membersCh = CruiseGroupService.subscribeMembers(
      widget.groupId,
      (_) => _load(),
    );
  }

  void _enterNavigation() {
    if (!mounted || _enteringNavigation) return;
    _enteringNavigation = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => CruiseModePage(groupId: widget.groupId),
          ),
        )
        .whenComplete(() {
          if (mounted) {
            _enteringNavigation = false;
            // Zurück aus der Fahrt → Rangliste sofort aktualisieren (die eigene
            // beendete Fahrt + zwischenzeitliche Kollegen-Ergebnisse).
            _load();
          }
        });
  }

  /// 2026-06-20 (vucko Gruppen-Rejoin): Bewusster Wiedereinstieg in die laufende
  /// Fahrt. Hebt den Auto-Enter-Suppress auf und steigt ab der AKTUELLEN Position
  /// wieder ein (Access-Leg). XP zählt nur die ab hier wirklich gefahrene Strecke
  /// (Driven-Track wird beim Access-Leg resettet).
  void _rejoinNavigation() {
    CruiseModePage.suppressedAutoEnterGroupIds.remove(widget.groupId);
    _enterNavigation();
  }

  // 2026-06-20 (vucko Gruppen-Audit): Crash-sicherer Mitglieder-Name. Ein LEERER
  // (nicht null) displayName liess `''.characters.first` werfen → Lobby-Tile-Crash.
  // Null UND Leerstring werden jetzt sauber abgefangen.
  static String _memberInitial(String? name) {
    final n = (name ?? '').trim();
    return n.isEmpty ? '?' : n.characters.first.toUpperCase();
  }

  static String _memberName(String? name) {
    final n = (name ?? '').trim();
    return n.isEmpty ? 'User' : n;
  }

  Future<void> _startRoute() async {
    if (_starting) return;
    // Owner startet bewusst → evtl. alten Suppress-Flag aufheben.
    CruiseModePage.suppressedAutoEnterGroupIds.remove(widget.groupId);
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

  Future<void> _changeMyRideRole(RideRole role) async {
    final key = 'ride:$_myId';
    if (_busyRoleUpdates.contains(key) || _myRideRole == role) return;
    _busyRoleUpdates.add(key);
    final previous = _applyMemberLocally(_myId, rideRole: role);
    try {
      await CruiseGroupService.updateRideRole(
        groupId: widget.groupId,
        userId: _myId,
        rideRole: role,
      );
    } catch (e) {
      _restoreGroup(previous);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      _busyRoleUpdates.remove(key);
    }
  }

  Future<void> _promoteToOwner(GroupMember m) async {
    if (!_hasOwnerPower) return;
    await _changeMemberRoleOptimistically(m, MemberRole.owner);
  }

  Future<void> _demoteOwner(GroupMember m) async {
    if (!_amCreator || m.userId == _group?.ownerId) return;
    await _changeMemberRoleOptimistically(
      m,
      m.rideRole == RideRole.driver ? MemberRole.driver : MemberRole.passenger,
    );
  }

  Future<void> _changeMemberRideRole(GroupMember m, RideRole role) async {
    if (!_hasOwnerPower && m.userId != _myId) return;
    final key = 'ride:${m.userId}';
    if (_busyRoleUpdates.contains(key) || m.rideRole == role) return;
    _busyRoleUpdates.add(key);
    final previous = _applyMemberLocally(m.userId, rideRole: role);
    try {
      await CruiseGroupService.updateRideRole(
        groupId: widget.groupId,
        userId: m.userId,
        rideRole: role,
      );
    } catch (e) {
      _restoreGroup(previous);
      rethrow;
    } finally {
      _busyRoleUpdates.remove(key);
    }
  }

  Future<void> _changeMemberRoleOptimistically(
    GroupMember member,
    MemberRole role,
  ) async {
    final key = 'member:${member.userId}';
    if (_busyRoleUpdates.contains(key) || member.role == role) return;
    _busyRoleUpdates.add(key);
    final previous = _applyMemberLocally(member.userId, role: role);
    try {
      await CruiseGroupService.updateMemberRole(
        groupId: widget.groupId,
        userId: member.userId,
        role: role,
      );
    } catch (e) {
      _restoreGroup(previous);
      rethrow;
    } finally {
      _busyRoleUpdates.remove(key);
    }
  }

  CruiseGroup? _applyMemberLocally(
    String userId, {
    MemberRole? role,
    RideRole? rideRole,
  }) {
    final current = _group;
    if (current == null || !mounted) return null;
    final nextMembers = current.members.map((member) {
      if (member.userId != userId) return member;
      return _copyMember(
        member,
        role: role ?? member.role,
        rideRole: _effectiveRideRole(member, role: role, rideRole: rideRole),
      );
    }).toList();
    setState(() => _group = _copyGroup(current, members: nextMembers));
    return current;
  }

  RideRole _effectiveRideRole(
    GroupMember member, {
    MemberRole? role,
    RideRole? rideRole,
  }) {
    if (rideRole != null) return rideRole;
    if (role == MemberRole.driver) return RideRole.driver;
    if (role == MemberRole.passenger) return RideRole.passenger;
    return member.rideRole;
  }

  void _restoreGroup(CruiseGroup? previous) {
    if (!mounted || previous == null) return;
    setState(() => _group = previous);
  }

  GroupMember _copyMember(
    GroupMember member, {
    required MemberRole role,
    required RideRole rideRole,
  }) {
    return GroupMember(
      id: member.id,
      groupId: member.groupId,
      userId: member.userId,
      role: role,
      rideRole: rideRole,
      createdAt: member.createdAt,
      currentLat: member.currentLat,
      currentLng: member.currentLng,
      lastUpdatedAt: member.lastUpdatedAt,
      displayName: member.displayName,
      avatarUrl: member.avatarUrl,
    );
  }

  CruiseGroup _copyGroup(
    CruiseGroup group, {
    required List<GroupMember> members,
  }) {
    return CruiseGroup(
      id: group.id,
      name: group.name,
      ownerId: group.ownerId,
      isPublic: group.isPublic,
      isActive: group.isActive,
      maxPeople: group.maxPeople,
      createdAt: group.createdAt,
      description: group.description,
      startTime: group.startTime,
      activatedAt: group.activatedAt,
      routeData: group.routeData,
      startLocation: group.startLocation,
      inviteCode: group.inviteCode,
      members: members,
    );
  }

  Future<void> _removeMember(GroupMember m) async {
    if (!_hasOwnerPower || m.userId == _myId || m.userId == _group?.ownerId) {
      return;
    }
    await CruiseGroupService.removeMember(
      groupId: widget.groupId,
      userId: m.userId,
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
          : _group != null
          ? _buildBody()
          : _hadNetworkError
          ? _buildConnecting()
          : _buildNotFound(),
      bottomNavigationBar: _loading || _group == null ? null : _buildBottom(),
    );
  }

  /// Transienter Netzfehler: NICHT "Gruppe nicht gefunden", sondern ehrlicher
  /// Verbindungs-Status. Lädt automatisch (Backoff-Retry läuft im Hintergrund)
  /// und bietet zusätzlich einen manuellen Sofort-Versuch.
  Widget _buildConnecting() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            const Text(
              'Verbindung wird hergestellt …',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Die Gruppe lädt automatisch, sobald du wieder online bist.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                _retryTimer?.cancel();
                _retryAttempt = 0;
                setState(() => _loading = true);
                _load();
              },
              child: const Text('Jetzt erneut versuchen'),
            ),
          ],
        ),
      ),
    );
  }

  /// Echtes null-Ergebnis: die Gruppe existiert wirklich nicht (mehr).
  Widget _buildNotFound() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Gruppe nicht gefunden',
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Zurück'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final g = _group!;
    final km = ((g.routeData?['distance_meters'] ?? 0) as num) / 1000;
    return RefreshIndicator(
      onRefresh: _load,
      color: AppAccentColors.accent,
      backgroundColor: const Color(0xFF1C1F26),
      child: ListView(
        // AlwaysScrollable, damit Pull-to-Refresh auch bei kurzer Liste greift.
        physics: const AlwaysScrollableScrollPhysics(),
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
                  Icon(
                    Icons.straighten,
                    color: AppAccentColors.accent,
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
                    color: AppAccentColors.accent,
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
        if (_leaderboard.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildLeaderboardCard(),
        ],
        if (_shouldShowInviteCode()) ...[
          const SizedBox(height: 16),
          _buildInviteCodeCard(),
        ],
        if (_hasOwnerPower && _pendingRequests.isNotEmpty) ...[
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
              icon: Icon(Icons.person_add, color: AppAccentColors.accent),
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
      ),
    );
  }

  // ── Gruppen-Rangliste (X3) ──────────────────────────────────────────────────

  /// Deterministische Rangliste-Karte: aggregierte Fahrleistung je Mitglied
  /// (Server-sortiert nach Distanz -> Top-Speed -> user_id, daher sieht jeder
  /// exakt dasselbe). Top-3 bekommen Gold/Silber/Bronze. Schnellste/r wird mit
  /// einem Bolt-Akzent hervorgehoben, damit „wer ist am schnellsten" auf einen
  /// Blick sichtbar ist.
  Widget _buildLeaderboardCard() {
    final entries = _leaderboard;
    // Index des Schnellsten (für die Bolt-Hervorhebung) — stabil & deterministisch.
    var fastestIdx = 0;
    for (var i = 1; i < entries.length; i++) {
      if (entries[i].maxTopSpeedKmh > entries[fastestIdx].maxTopSpeedKmh) {
        fastestIdx = i;
      }
    }
    final hasAnySpeed = entries[fastestIdx].maxTopSpeedKmh > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events, color: AppAccentColors.accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Gruppen-Rangliste',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Padding(
            padding: EdgeInsets.only(left: 28),
            child: Text(
              'Eure gefahrene Strecke & Top-Speed',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < entries.length; i++)
            _buildLeaderboardRow(
              entries[i],
              rank: i + 1,
              isFastest: hasAnySpeed && i == fastestIdx,
            ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardRow(
    GroupLeaderboardEntry e, {
    required int rank,
    required bool isFastest,
  }) {
    final isMe = e.userId == _myId;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        // Eigene Zeile dezent hervorheben, ohne die Rangliste zu verzerren.
        color: isMe
            ? AppAccentColors.accent.withValues(alpha: 0.10)
            : const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(12),
        border: isMe
            ? Border.all(color: AppAccentColors.accent.withValues(alpha: 0.35))
            : null,
      ),
      child: Row(
        children: [
          _rankBadge(rank),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF1C1F26),
            foregroundImage: UserAvatar.avatarImageProvider(
              context,
              e.avatarUrl,
              radius: 16,
            ),
            child: Text(
              _memberInitial(e.username),
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_memberName(e.username)}${isMe ? ' (Du)' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isFastest)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.bolt,
                          color: Colors.lightBlueAccent,
                          size: 13,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'Schnellste/r',
                          style: TextStyle(
                            color: Colors.lightBlueAccent.shade100,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${e.totalDistanceKm.toStringAsFixed(1)} km',
                style: TextStyle(
                  color: AppAccentColors.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              if (e.maxTopSpeedKmh > 0)
                Text(
                  '${e.maxTopSpeedKmh.round()} km/h Top',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Rang-Plakette: Gold/Silber/Bronze für Top-3, sonst dezente Nummer.
  Widget _rankBadge(int rank) {
    const gold = Color(0xFFFFD24A);
    const silver = Color(0xFFC7CDD6);
    const bronze = Color(0xFFCD7F4B);
    final color = switch (rank) {
      1 => gold,
      2 => silver,
      3 => bronze,
      _ => Colors.white24,
    };
    final isPodium = rank <= 3;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isPodium ? color.withValues(alpha: 0.18) : Colors.transparent,
        border: Border.all(color: color, width: isPodium ? 1.5 : 1),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          color: isPodium ? color : Colors.white54,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
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
    return _hasOwnerPower;
  }

  Widget _buildInviteCodeCard() {
    final code = _group!.inviteCode!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppAccentColors.accent.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.qr_code_2, color: AppAccentColors.accent, size: 22),
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
            icon: Icon(Icons.copy, color: AppAccentColors.accent),
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
            backgroundColor: AppAccentColors.accent,
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
    final isCreator = m.userId == _group?.ownerId;
    final isOwner = isCreator || m.role == MemberRole.owner;
    final rideLabel = m.rideRole == RideRole.driver ? 'Fahrer' : 'Mitfahrer';
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
            GestureDetector(
              onTap: isBlocked
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserProfilePage(
                          userId: m.userId,
                          initialUsername: m.displayName,
                        ),
                      ),
                    ),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF0B0E14),
                foregroundImage: UserAvatar.avatarImageProvider(
                  context,
                  m.avatarUrl,
                  radius: 18,
                ),
                child: Text(
                  _memberInitial(m.displayName),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_memberName(m.displayName)}${isMe ? ' (Du)' : ''}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (isCreator)
                        _memberBadge('Ersteller', Colors.amberAccent),
                      if (isOwner)
                        _memberBadge('Owner', AppAccentColors.accent),
                      _memberBadge(
                        rideLabel,
                        m.rideRole == RideRole.driver
                            ? Colors.lightBlueAccent
                            : Colors.white54,
                      ),
                    ],
                  ),
                  if (isBlocked)
                    Text(
                      'Blockiert',
                      style: TextStyle(
                        color: AppAccentColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            if (!isBlocked && (_hasOwnerPower || isMe))
              _buildMemberMenu(m, isMe: isMe, isCreator: isCreator),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSelector() {
    return Row(
      children: [
        _roleChip('Fahrer', RideRole.driver),
        const SizedBox(width: 12),
        _roleChip('Mitfahrer', RideRole.passenger),
      ],
    );
  }

  Widget _buildMemberMenu(
    GroupMember m, {
    required bool isMe,
    required bool isCreator,
  }) {
    return IconButton(
      tooltip: 'Mitglied verwalten',
      icon: const Icon(Icons.more_horiz, color: Colors.grey),
      onPressed: () =>
          _showMemberActionsSheet(m, isMe: isMe, isCreator: isCreator),
    );
  }

  Future<void> _showMemberActionsSheet(
    GroupMember m, {
    required bool isMe,
    required bool isCreator,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1C1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  UserAvatar(
                    name: m.displayName ?? 'User',
                    avatarUrl: m.avatarUrl,
                    radius: 18,
                    backgroundColor: const Color(0xFF0B0E14),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      m.displayName ?? 'User',
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
            ),
            _memberActionTile(
              ctx,
              value: 'ride_role',
              icon: Icons.swap_horiz,
              label: isMe ? 'Meine Fahrrolle ändern' : 'Fahrrolle ändern',
            ),
            if (_hasOwnerPower && !isMe && m.role != MemberRole.owner)
              _memberActionTile(
                ctx,
                value: 'owner_add',
                icon: Icons.admin_panel_settings_outlined,
                label: 'Owner geben',
              ),
            if (_amCreator && !isMe && m.role == MemberRole.owner && !isCreator)
              _memberActionTile(
                ctx,
                value: 'owner_remove',
                icon: Icons.remove_moderator_outlined,
                label: 'Owner wegnehmen',
              ),
            if (_hasOwnerPower && !isMe && !isCreator)
              _memberActionTile(
                ctx,
                value: 'kick',
                icon: Icons.person_remove_outlined,
                label: 'Aus Gruppe entfernen',
                destructive: true,
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action != null) await _handleMemberAction(action, m);
  }

  Widget _memberActionTile(
    BuildContext context, {
    required String value,
    required IconData icon,
    required String label,
    bool destructive = false,
  }) {
    final color = destructive ? AppAccentColors.accent : Colors.white;
    return ListTile(
      minLeadingWidth: 24,
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: () => Navigator.pop(context, value),
    );
  }

  Widget _memberBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _handleMemberAction(String value, GroupMember m) async {
    try {
      switch (value) {
        case 'ride_role':
          await _showRideRoleSheet(m);
          break;
        case 'owner_add':
          await _promoteToOwner(m);
          break;
        case 'owner_remove':
          await _demoteOwner(m);
          break;
        case 'kick':
          await _removeMember(m);
          break;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Aktion fehlgeschlagen: $e')));
    }
  }

  Future<void> _showRideRoleSheet(GroupMember m) async {
    final selected = await showModalBottomSheet<RideRole>(
      context: context,
      backgroundColor: const Color(0xFF1C1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 8),
            _rideRoleOption(ctx, m.rideRole, RideRole.driver, 'Fahrer'),
            _rideRoleOption(ctx, m.rideRole, RideRole.passenger, 'Mitfahrer'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null) {
      await _changeMemberRideRole(m, selected);
    }
  }

  Widget _rideRoleOption(
    BuildContext ctx,
    RideRole current,
    RideRole value,
    String label,
  ) {
    final selected = current == value;
    return ListTile(
      onTap: () => Navigator.pop(ctx, value),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? AppAccentColors.accent : Colors.grey,
      ),
      title: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }

  Widget _roleChip(String label, RideRole role) {
    final selected = _myRideRole == role;
    return GestureDetector(
      onTap: () => _changeMyRideRole(role),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppAccentColors.accent : const Color(0xFF1C1F26),
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
    final isActive = _group?.isActive == true;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: isActive
                ? _rejoinNavigation
                : _hasOwnerPower && !_starting
                ? _startRoute
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppAccentColors.accent,
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
                    isActive
                        ? 'Zur laufenden Route'
                        : _hasOwnerPower
                        ? 'Route starten'
                        : 'Warten auf Owner...',
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
                      child: Text(
                        'Einladen',
                        style: TextStyle(color: AppAccentColors.accent),
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
                      maxLength: AppInputLimits.searchQueryMaxLength,
                      inputFormatters: AppInputLimits.lengthFormatters(
                        AppInputLimits.searchQueryMaxLength,
                      ),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        counterText: '',
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
