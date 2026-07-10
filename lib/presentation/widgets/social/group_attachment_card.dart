import 'package:flutter/material.dart';

import 'package:cruise_connect/data/services/cruise_group_service.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/domain/models/cruise_group.dart';
import 'package:cruise_connect/domain/models/group_member.dart';
import 'package:cruise_connect/presentation/pages/group_lobby_page.dart';

/// 2026-07-03 (vucko Gruppen-Share): Einheitliche Darstellung einer geteilten
/// Gruppe in Posts und Composer — 1:1 gespiegelt von [RouteAttachmentCard], aber
/// klar als GRUPPE differenziert (Gruppen-Icon, „GRUPPE"-Pill, Öffentlich/Privat,
/// Beitreten- statt Fahren-Aktion). Beitreten respektiert die bestehende
/// can_join_group-Logik (Live-Session/Privat/blockiert).
class GroupAttachmentCard extends StatefulWidget {
  const GroupAttachmentCard({
    super.key,
    required this.groupId,
    this.compact = false,
    this.showJoinButton = true,
  });

  final String groupId;
  final bool compact;
  final bool showJoinButton;

  @override
  State<GroupAttachmentCard> createState() => _GroupAttachmentCardState();
}

class _GroupAttachmentCardState extends State<GroupAttachmentCard> {
  CruiseGroup? _group;
  String? _ownerName;
  bool _loading = true;
  bool _busy = false;

  // Beitritts-Status.
  bool _isMember = false;
  bool _hasPendingRequest = false;

  @override
  void initState() {
    super.initState();
    _loadGroup();
  }

  @override
  void didUpdateWidget(covariant GroupAttachmentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId) {
      _group = null;
      _ownerName = null;
      _loading = true;
      _busy = false;
      _isMember = false;
      _hasPendingRequest = false;
      _loadGroup();
    }
  }

  Future<void> _loadGroup() async {
    try {
      final group = await CruiseGroupService.fetch(widget.groupId);
      // Beitritts-Status nur laden, wenn die Karte auch einen Button zeigt.
      var isMember = false;
      var hasPending = false;
      if (group != null && widget.showJoinButton) {
        final results = await Future.wait([
          SocialService.isMember(widget.groupId),
          SocialService.hasPendingJoinRequest(widget.groupId),
        ]);
        isMember = results[0];
        hasPending = results[1];
      }
      if (!mounted) return;
      setState(() {
        _group = group;
        _ownerName = group == null ? null : _resolveOwnerName(group);
        _isMember = isMember;
        _hasPendingRequest = hasPending;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String? _resolveOwnerName(CruiseGroup group) {
    for (final GroupMember m in group.members) {
      if (m.userId == group.ownerId) {
        final name = m.displayName?.trim();
        if (name != null && name.isNotEmpty) return name;
      }
    }
    return null;
  }

  /// Verknüpfte Route (falls die Gruppe eine Route trägt) — Distanz in km.
  double _routeKm(CruiseGroup group) {
    final data = group.activeRouteData;
    final meters = (data?['distance_meters'] as num?)?.toDouble() ?? 0;
    return meters / 1000;
  }

  Future<void> _primaryAction() async {
    final group = _group;
    if (_busy || group == null) return;

    // Mitglied → Lobby öffnen.
    if (_isMember) {
      _openLobby();
      return;
    }

    // Anfrage bereits offen → nichts tun (Button ist ohnehin passiv).
    if (_hasPendingRequest) return;

    setState(() => _busy = true);
    try {
      if (group.isPublic) {
        await SocialService.joinGroup(widget.groupId);
        if (!mounted) return;
        setState(() {
          _isMember = true;
          _busy = false;
        });
        _showSnack('Gruppe beigetreten.');
        _openLobby();
      } else {
        await SocialService.requestJoinGroup(widget.groupId);
        if (!mounted) return;
        setState(() {
          _hasPendingRequest = true;
          _busy = false;
        });
        _showSnack('Beitritts-Anfrage gesendet.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final message = e is SocialServiceException
          ? e.message
          : 'Beitritt nicht möglich.';
      _showSnack(message, error: true);
    }
  }

  void _openLobby() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupLobbyPage(groupId: widget.groupId),
      ),
    );
  }

  void _showSnack(String message, {bool error = false}) {
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

  @override
  Widget build(BuildContext context) {
    final group = _group;
    final isCompact = widget.compact;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 12 : 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1C1F26),
            Color.lerp(const Color(0xFF1C1F26), _groupAccent, 0.12)!,
          ],
        ),
        borderRadius: BorderRadius.circular(isCompact ? 14 : 16),
        border: Border.all(color: _groupAccent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: _groupAccent.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: _loading
          ? _buildLoading(isCompact)
          : group == null
          ? _buildFallback(isCompact)
          : _buildGroup(group, isCompact),
    );
  }

  // Blaugrüner Gruppen-Akzent (differenziert von den Routen-Trust-Badges).
  static const Color _groupAccent = Color(0xFF7DD3FC);

  Widget _buildLoading(bool isCompact) {
    return Row(
      children: [
        _GroupIconBox(compact: isCompact, muted: false),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Gruppe wird geladen...',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: isCompact ? 12 : 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFallback(bool isCompact) {
    return Row(
      children: [
        _GroupIconBox(compact: isCompact, muted: true),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Gruppe nicht mehr verfügbar',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: isCompact ? 12 : 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGroup(CruiseGroup group, bool isCompact) {
    final memberCount = group.members.length;
    final km = _routeKm(group);
    return Row(
      children: [
        _GroupIconBox(compact: isCompact, muted: false),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openLobby,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _GroupPill(compact: isCompact),
                    const SizedBox(width: 6),
                    _GroupVisibilityLabel(
                      isPublic: group.isPublic,
                      compact: isCompact,
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  group.name.isEmpty ? 'Gruppe' : group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isCompact ? 13 : 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _subtitle(memberCount, km),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: isCompact ? 11 : 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.showJoinButton) ...[
          const SizedBox(width: 8),
          _GroupPrimaryAction(
            compact: isCompact,
            loading: _busy,
            state: _buttonState(group),
            onTap: _primaryAction,
          ),
        ],
      ],
    );
  }

  String _subtitle(int memberCount, double km) {
    final memberLabel = '$memberCount ${memberCount == 1 ? 'Mitglied' : 'Mitglieder'}';
    final owner = _ownerName;
    final parts = <String>[
      memberLabel,
      if (owner != null && owner.isNotEmpty) '@$owner',
      if (km > 0) '${km.toStringAsFixed(1).replaceAll('.', ',')} km',
    ];
    return parts.join(' · ');
  }

  _GroupButtonState _buttonState(CruiseGroup group) {
    if (_isMember) return _GroupButtonState.open;
    if (_hasPendingRequest) return _GroupButtonState.requested;
    // 2026-07-03 (vucko Gruppen-Share): Live-Session ist für Nicht-Mitglieder
    // nicht joinbar (can_join_group blockt) → Button „Session läuft".
    if (group.isActive) return _GroupButtonState.live;
    return group.isPublic ? _GroupButtonState.join : _GroupButtonState.request;
  }
}

enum _GroupButtonState { open, join, request, requested, live }

class _GroupIconBox extends StatelessWidget {
  const _GroupIconBox({required this.compact, required this.muted});

  final bool compact;
  final bool muted;

  static const Color _accent = Color(0xFF7DD3FC);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 36 : 44,
      height: compact ? 36 : 44,
      decoration: BoxDecoration(
        color: muted
            ? Colors.white.withValues(alpha: 0.05)
            : _accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: muted
            ? null
            : Border.all(color: _accent.withValues(alpha: 0.30)),
      ),
      child: Icon(
        Icons.groups_rounded,
        color: muted ? Colors.white54 : _accent,
        size: compact ? 18 : 22,
      ),
    );
  }
}

class _GroupPill extends StatelessWidget {
  const _GroupPill({required this.compact});

  final bool compact;

  static const Color _accent = Color(0xFF7DD3FC);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _accent.withValues(alpha: 0.32)),
      ),
      child: Text(
        'GRUPPE',
        style: TextStyle(
          color: _accent,
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _GroupVisibilityLabel extends StatelessWidget {
  const _GroupVisibilityLabel({required this.isPublic, required this.compact});

  final bool isPublic;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isPublic ? Icons.public : Icons.lock_rounded,
          color: Colors.white.withValues(alpha: 0.55),
          size: compact ? 12 : 13,
        ),
        const SizedBox(width: 3),
        Text(
          isPublic ? 'Öffentlich' : 'Privat',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: compact ? 10 : 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _GroupPrimaryAction extends StatelessWidget {
  const _GroupPrimaryAction({
    required this.compact,
    required this.loading,
    required this.state,
    required this.onTap,
  });

  final bool compact;
  final bool loading;
  final _GroupButtonState state;
  final VoidCallback onTap;

  static const Color _accent = Color(0xFF7DD3FC);

  String get _label {
    switch (state) {
      case _GroupButtonState.open:
        return 'Öffnen';
      case _GroupButtonState.join:
        return 'Beitreten';
      case _GroupButtonState.request:
        return 'Anfragen';
      case _GroupButtonState.requested:
        return 'Angefragt';
      case _GroupButtonState.live:
        return 'Session läuft';
    }
  }

  bool get _disabled =>
      state == _GroupButtonState.requested || state == _GroupButtonState.live;

  @override
  Widget build(BuildContext context) {
    final disabled = _disabled;
    return GestureDetector(
      onTap: (loading || disabled) ? null : onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 16,
          vertical: compact ? 7 : 10,
        ),
        decoration: BoxDecoration(
          color: disabled
              ? Colors.white.withValues(alpha: 0.08)
              : _accent,
          borderRadius: BorderRadius.circular(12),
          border: disabled
              ? Border.all(color: Colors.white.withValues(alpha: 0.14))
              : null,
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                _label,
                style: TextStyle(
                  color: disabled
                      ? Colors.white.withValues(alpha: 0.65)
                      : const Color(0xFF0B0E14),
                  fontSize: compact ? 11 : 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
