import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/membership_since_service.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

class BadgeSpotPlacement {
  const BadgeSpotPlacement(this.offset, this.scale, this.angle);

  final Offset offset;
  final double scale;
  final double angle;
}

class ProfileBadgeSticker {
  const ProfileBadgeSticker({
    required this.id,
    required this.spot,
    required this.x,
    required this.y,
    required this.scale,
  });

  final String id;
  final int spot;
  final double x;
  final double y;
  final double scale;

  ProfileBadgeSticker copyWith({
    String? id,
    int? spot,
    double? x,
    double? y,
    double? scale,
  }) {
    final nextSpot = (spot ?? this.spot)
        .clamp(0, ProfileBadgeShowcase.spotCount - 1)
        .toInt();
    final placement = placementForSpot(nextSpot);
    return ProfileBadgeSticker(
      id: id ?? this.id,
      spot: nextSpot,
      x: x ?? placement.offset.dx,
      y: y ?? placement.offset.dy,
      scale: scale ?? placement.scale,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'spot': spot,
      'x': double.parse(x.toStringAsFixed(3)),
      'y': double.parse(y.toStringAsFixed(3)),
      'scale': double.parse(scale.toStringAsFixed(2)),
    };
  }

  static ProfileBadgeSticker defaultForSlot(String id, int slot) {
    return defaultForSpot(id, ProfileBadgeShowcase.defaultSpotForSlot(slot));
  }

  static ProfileBadgeSticker defaultForSpot(String id, int spot) {
    final safeSpot = spot.clamp(0, ProfileBadgeShowcase.spotCount - 1).toInt();
    final placement = placementForSpot(safeSpot);
    return ProfileBadgeSticker(
      id: id,
      spot: safeSpot,
      x: placement.offset.dx,
      y: placement.offset.dy,
      scale: placement.scale,
    );
  }

  static BadgeSpotPlacement placementForSpot(int spot) {
    return ProfileBadgeShowcase.placements[spot
        .clamp(0, ProfileBadgeShowcase.placements.length - 1)
        .toInt()];
  }
}

class ProfileBadgeShowcase extends StatelessWidget {
  const ProfileBadgeShowcase({super.key, required this.profile, this.baseSize});

  static const int slotCount = 5;
  static const int spotCount = 10;
  static const List<int> _defaultActiveSpots = [0, 1, 2, 6, 8];
  static const List<BadgeSpotPlacement> placements = [
    BadgeSpotPlacement(Offset(0.36, 0.14), 0.72, -0.08),
    BadgeSpotPlacement(Offset(0.50, 0.10), 0.70, 0.06),
    BadgeSpotPlacement(Offset(0.64, 0.15), 0.72, -0.05),
    BadgeSpotPlacement(Offset(0.80, 0.13), 0.70, 0.07),
    BadgeSpotPlacement(Offset(0.93, 0.22), 0.66, -0.06),
    BadgeSpotPlacement(Offset(0.36, 0.36), 0.66, 0.05),
    BadgeSpotPlacement(Offset(0.48, 0.50), 0.64, -0.04),
    BadgeSpotPlacement(Offset(0.92, 0.42), 0.64, 0.05),
    BadgeSpotPlacement(Offset(0.76, 0.78), 0.66, 0.06),
    BadgeSpotPlacement(Offset(0.93, 0.78), 0.64, -0.08),
  ];

  static int defaultSpotForSlot(int slot) {
    return _defaultActiveSpots[slot.clamp(0, _defaultActiveSpots.length - 1)];
  }

  final Map<String, dynamic> profile;
  final double? baseSize;

  static List<String> badgeIdsFromProfile(Map<String, dynamic> profile) {
    final raw = profile['badges'];
    if (raw is! Iterable) return const [];
    final validIds = app.Badge.all.map((badge) => badge.id).toSet();
    return [
      for (final value in raw)
        if (validIds.contains(value?.toString())) value.toString(),
    ];
  }

  static List<ProfileBadgeSticker?> stickerSlotsFromProfile(
    Map<String, dynamic> profile,
  ) {
    final raw = profile['badge_showcase'];
    if (raw is! Iterable) {
      return List<ProfileBadgeSticker?>.filled(slotCount, null);
    }
    final earned = badgeIdsFromProfile(profile).toSet();
    final used = <String>{};
    final usedSpots = <int>{};
    final slots = <ProfileBadgeSticker?>[];
    var slot = 0;

    for (final value in raw) {
      final parsed = _parseSticker(value, slot, earned, used, usedSpots);
      slots.add(parsed);
      slot += 1;
      if (slots.length >= slotCount) break;
    }
    while (slots.length < slotCount) {
      slots.add(null);
    }
    return slots;
  }

  static List<Map<String, dynamic>> storageFromSlots(
    List<ProfileBadgeSticker?> slots,
  ) {
    final used = <String>{};
    final usedSpots = <int>{};
    final entries = <Map<String, dynamic>>[];
    for (final sticker in slots.take(slotCount)) {
      if (sticker == null ||
          sticker.id.isEmpty ||
          !used.add(sticker.id) ||
          !usedSpots.add(sticker.spot)) {
        entries.add(const {});
      } else {
        entries.add(sticker.toJson());
      }
    }
    while (entries.length < slotCount) {
      entries.add(const {});
    }
    return entries;
  }

  static ProfileBadgeSticker? _parseSticker(
    Object? raw,
    int slot,
    Set<String> earned,
    Set<String> used,
    Set<int> usedSpots,
  ) {
    String id = '';
    double? x;
    double? y;
    int? spot;

    if (raw is Map) {
      id = raw['id']?.toString().trim() ?? '';
      x = _readDouble(raw['x']);
      y = _readDouble(raw['y']);
      spot = _readInt(raw['spot']);
    } else if (raw != null) {
      id = raw.toString().trim();
    }

    if (id.isEmpty || !earned.contains(id) || !used.add(id)) return null;
    final resolvedSpot = _resolveSpot(spot, x, y, slot, usedSpots);
    usedSpots.add(resolvedSpot);
    return ProfileBadgeSticker.defaultForSpot(id, resolvedSpot);
  }

  static double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.'));
    return null;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static int _resolveSpot(
    int? explicitSpot,
    double? legacyX,
    double? legacyY,
    int slot,
    Set<int> usedSpots,
  ) {
    final candidates = <int>[];
    if (explicitSpot != null && explicitSpot >= 0 && explicitSpot < spotCount) {
      candidates.add(explicitSpot);
    }
    if (legacyX != null && legacyY != null) {
      final nearest = _nearestSpot(Offset(legacyX, legacyY));
      candidates.add(nearest);
    }
    candidates.add(defaultSpotForSlot(slot));
    candidates.addAll(List<int>.generate(spotCount, (index) => index));
    return candidates.firstWhere((spot) => !usedSpots.contains(spot));
  }

  /// created_at aus einem Profil-Map ziehen (getProfileStats liefert es mit) —
  /// so zeigt das Badge-Detail beim FREMDEN Profil dessen Beitrittsdatum.
  static DateTime? memberSinceFromProfile(Map<String, dynamic> profile) {
    final raw = profile['created_at'];
    if (raw is String) return DateTime.tryParse(raw)?.toLocal();
    return null;
  }

  static int _nearestSpot(Offset point) {
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < placements.length; i++) {
      final distance = (placements[i].offset - point).distanceSquared;
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// 2026-08-14 (vucko Tutorial-Badge): Beim Mitgliedschafts-Badge wird der
  /// Datums-Platzhalter in der Beschreibung dynamisch ersetzt. [memberSince]
  /// kommt idealerweise aus dem angezeigten Profil (created_at); fehlt es,
  /// wird das eigene Beitrittsdatum nachgeladen (Fallback: heutiges Datum in
  /// [app.Badge.resolveDescription]).
  static Future<void> showBadgeDetails(
    BuildContext context,
    app.Badge badge, {
    DateTime? memberSince,
    // 2026-08-15 (vucko): Bei gesperrten Badges Bedingung + Fortschritt
    // zeigen („274 von 1000 km"). null = freigeschaltet oder nicht messbar.
    app.BadgeFortschritt? fortschritt,
    bool freigeschaltet = true,
  }) async {
    var since = memberSince;
    if (badge.id == app.Badge.membershipBadgeId && since == null) {
      since = await MembershipSinceService.load();
      if (!context.mounted) return;
    }
    final description = app.Badge.resolveDescription(badge, memberSince: since);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF151A23),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Opacity(
                    opacity: freigeschaltet ? 1 : 0.38,
                    child: _BadgeStickerShell(
                      size: 104,
                      selected: freigeschaltet,
                      child: _BadgeImage(badge: badge, size: 82),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    badge.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  // 2026-08-18 (Aufgabe 4.2): Bei mehrstufigen Badges zeigt
                  // eine Leiste, an welcher Stelle der Familie man steht.
                  if (badge.stufe > 0) ...[
                    const SizedBox(height: 10),
                    _StufenLeiste(badge: badge),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFA7B0C1),
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!freigeschaltet && fortschritt != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      fortschritt.anleitung,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: fortschritt.anteil,
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        color: AppAccentColors.accent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      fortschritt.zahlen,
                      style: TextStyle(
                        color: AppAccentColors.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ] else if (!freigeschaltet) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Noch gesperrt',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppAccentColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: AppAccentColors.accent.withValues(alpha: 0.36),
                      ),
                    ),
                    child: Text(
                      badge.category.toUpperCase(),
                      style: TextStyle(
                        color: AppAccentColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  // 2026-08-14 (vucko): "ein Overlay, wo wenn man unten auf
                  // Schliessen drueckt, sich das schliesst" - bisher ging das
                  // Blatt nur per Wischen zu, ohne sichtbaren Ausweg.
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppAccentColors.accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text(
                        'Schließen',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final stickers = stickerSlotsFromProfile(profile).nonNulls.toList();
    if (stickers.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (width <= 0 || height <= 0) return const SizedBox.shrink();
        final calculatedBase = baseSize ?? (width * 0.15).clamp(42.0, 64.0);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < stickers.length; i++)
              _PositionedBadgeSticker(
                sticker: stickers[i],
                width: width,
                height: height,
                baseSize: calculatedBase,
                selected: false,
                onTap: () {
                  final badge = app.Badge.getById(stickers[i].id);
                  if (badge != null) {
                    showBadgeDetails(
                      context,
                      badge,
                      memberSince: memberSinceFromProfile(profile),
                    );
                  }
                },
              ),
          ],
        );
      },
    );
  }
}

class ProfileBadgeStickerEditor extends StatefulWidget {
  const ProfileBadgeStickerEditor({
    super.key,
    required this.profile,
    required this.displayName,
    required this.avatarUrl,
    required this.bannerUrl,
    required this.onChanged,
  });

  final Map<String, dynamic> profile;
  final String displayName;
  final String? avatarUrl;
  final String? bannerUrl;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  State<ProfileBadgeStickerEditor> createState() =>
      _ProfileBadgeStickerEditorState();
}

class _ProfileBadgeStickerEditorState extends State<ProfileBadgeStickerEditor> {
  late List<ProfileBadgeSticker?> _slots;
  int _selectedSlot = 0;

  @override
  void initState() {
    super.initState();
    _slots = ProfileBadgeShowcase.stickerSlotsFromProfile(widget.profile);
    _selectedSlot = _preferredSelectedSlot();
  }

  @override
  void didUpdateWidget(covariant ProfileBadgeStickerEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile['badge_showcase'] !=
            widget.profile['badge_showcase'] ||
        oldWidget.profile['badges'] != widget.profile['badges']) {
      _slots = ProfileBadgeShowcase.stickerSlotsFromProfile(widget.profile);
      _selectedSlot = _selectedSlot.clamp(0, _slots.length - 1).toInt();
      if (_slots[_selectedSlot] == null) {
        _selectedSlot = _preferredSelectedSlot();
      }
    }
  }

  int _preferredSelectedSlot() {
    final firstEmpty = _slots.indexWhere((sticker) => sticker == null);
    if (firstEmpty >= 0) return firstEmpty;
    final firstFilled = _slots.indexWhere((sticker) => sticker != null);
    return firstFilled < 0 ? 0 : firstFilled;
  }

  void _emit() {
    widget.onChanged(ProfileBadgeShowcase.storageFromSlots(_slots));
  }

  void _updateSlot(int slot, ProfileBadgeSticker? sticker) {
    if (slot < 0 || slot >= ProfileBadgeShowcase.slotCount) return;
    setState(() {
      _slots[slot] = sticker;
      _selectedSlot = slot;
    });
    _emit();
  }

  int _firstFreeSpot() {
    final usedSpots = {
      for (final sticker in _slots.whereType<ProfileBadgeSticker>())
        sticker.spot,
    };
    for (var i = 0; i < ProfileBadgeShowcase.spotCount; i++) {
      if (!usedSpots.contains(i)) return i;
    }
    return 0;
  }

  int _firstEmptySlot() {
    final index = _slots.indexWhere((sticker) => sticker == null);
    return index < 0 ? -1 : index;
  }

  void _selectSpotForCurrentSlot(int spot) {
    final sticker = _slots[_selectedSlot];
    if (sticker == null) return;
    final occupiedByOther = _slots.indexWhere(
      (candidate) => candidate != null && candidate.spot == spot,
    );
    if (occupiedByOther >= 0 && occupiedByOther != _selectedSlot) return;
    _updateSlot(_selectedSlot, sticker.copyWith(spot: spot));
  }

  Future<void> _addBadgeAtSpot(int spot) async {
    final emptySlot = _firstEmptySlot();
    if (emptySlot < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximal 5 Badge-Sticker möglich.'),
          backgroundColor: Color(0xFF1C1F26),
        ),
      );
      return;
    }
    setState(() => _selectedSlot = emptySlot);
    await _openBadgePicker(emptySlot, preferredSpot: spot);
  }

  Future<void> _handlePreviewSpotTap(int spot) async {
    final selected = _slots[_selectedSlot];
    if (selected == null) {
      await _addBadgeAtSpot(spot);
      return;
    }
    _selectSpotForCurrentSlot(spot);
  }

  Future<void> _openBadgePicker(int slotIndex, {int? preferredSpot}) async {
    final earnedIds = ProfileBadgeShowcase.badgeIdsFromProfile(widget.profile);
    final current = _slots[slotIndex];
    final usedInOtherSlots = {
      for (var i = 0; i < _slots.length; i++)
        if (i != slotIndex && _slots[i] != null) _slots[i]!.id,
    };
    final picked = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF151A23),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              12,
              18,
              18 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  preferredSpot == null
                      ? 'Badge wählen'
                      : 'Platz ${preferredSpot + 1} belegen',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                if (earnedIds.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 18),
                    child: Text(
                      'Noch keine Badges freigeschaltet.',
                      style: TextStyle(color: Color(0xFFA0AEC0)),
                    ),
                  )
                else
                  SizedBox(
                    height: MediaQuery.sizeOf(sheetContext).height * 0.50,
                    child: GridView.count(
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.92,
                      children: [
                        _BadgePickerTile.clear(
                          selected: current == null,
                          onTap: () => Navigator.pop(sheetContext, ''),
                        ),
                        for (final id in earnedIds)
                          _BadgePickerTile(
                            badge: app.Badge.getById(id),
                            selected: current?.id == id,
                            disabled: usedInOtherSlots.contains(id),
                            onTap: () => Navigator.pop(sheetContext, id),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null) return;
    if (picked.isEmpty) {
      _updateSlot(slotIndex, null);
      return;
    }
    final existing = current;
    final next = existing == null
        ? ProfileBadgeSticker.defaultForSpot(
            picked,
            preferredSpot ?? _firstFreeSpot(),
          )
        : existing.copyWith(id: picked);
    _updateSlot(slotIndex, next);
  }

  @override
  Widget build(BuildContext context) {
    final earned = ProfileBadgeShowcase.badgeIdsFromProfile(widget.profile);
    final filled = _slots.whereType<ProfileBadgeSticker>().length;
    final remaining = ProfileBadgeShowcase.slotCount - filled;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF171B23),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppAccentColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.workspace_premium_rounded,
                  color: AppAccentColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Badge-Sticker',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$remaining frei',
                style: const TextStyle(
                  color: Color(0xFFA7B0C1),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ProfileStickerPreview(
            slots: _slots,
            selectedSlot: _selectedSlot,
            displayName: widget.displayName,
            avatarUrl: widget.avatarUrl,
            bannerUrl: widget.bannerUrl,
            onSelectSlot: (slot) => setState(() => _selectedSlot = slot),
            onSelectSpot: _handlePreviewSpotTap,
          ),
          if (earned.isEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Freigeschaltete Badges erscheinen hier.',
              style: TextStyle(
                color: Color(0xFFA7B0C1),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            const Text(
              'Tippe einen freien Punkt in der Profil-Vorschau. Tippe ein Badge an, um es zu verschieben oder zu entfernen.',
              style: TextStyle(
                color: Color(0xFFA7B0C1),
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.swipe_rounded,
                    color: AppAccentColors.accent,
                    size: 16,
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'Badges unten seitlich wischen',
                    style: TextStyle(
                      color: Color(0xFFA7B0C1),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _PlacedBadgeStrip(
              slots: _slots,
              selectedSlot: _selectedSlot,
              onSelect: (slot) => setState(() => _selectedSlot = slot),
              onPick: () async {
                final empty = _firstEmptySlot();
                if (empty >= 0) {
                  setState(() => _selectedSlot = empty);
                  await _openBadgePicker(
                    empty,
                    preferredSpot: _firstFreeSpot(),
                  );
                }
              },
              onRemove: (slot) => _updateSlot(slot, null),
              onInfo: (slot) {
                final sticker = _slots[slot];
                final badge = sticker == null
                    ? null
                    : app.Badge.getById(sticker.id);
                if (badge != null) {
                  ProfileBadgeShowcase.showBadgeDetails(
                    context,
                    badge,
                    memberSince: ProfileBadgeShowcase.memberSinceFromProfile(
                      widget.profile,
                    ),
                  );
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileStickerPreview extends StatelessWidget {
  const _ProfileStickerPreview({
    required this.slots,
    required this.selectedSlot,
    required this.displayName,
    required this.avatarUrl,
    required this.bannerUrl,
    required this.onSelectSlot,
    required this.onSelectSpot,
  });

  final List<ProfileBadgeSticker?> slots;
  final int selectedSlot;
  final String displayName;
  final String? avatarUrl;
  final String? bannerUrl;
  final ValueChanged<int> onSelectSlot;
  final ValueChanged<int> onSelectSpot;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.10,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final baseSize = (width * 0.14).clamp(34.0, 46.0);
          final filled = slots.whereType<ProfileBadgeSticker>().length;
          final remaining = ProfileBadgeShowcase.slotCount - filled;
          final occupiedBySpot = <int, int>{
            for (var i = 0; i < slots.length; i++)
              if (slots[i] != null) slots[i]!.spot: i,
          };

          return ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF080B10),
                      image: bannerUrl != null && bannerUrl!.isNotEmpty
                          ? DecorationImage(
                              image: UserAvatar.resizedNetworkImageProvider(
                                context,
                                bannerUrl,
                                width: width,
                                height: height,
                                maxCacheSize: 2200,
                              )!,
                              fit: BoxFit.cover,
                              colorFilter: ColorFilter.mode(
                                Colors.black.withValues(alpha: 0.22),
                                BlendMode.darken,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: height * 0.36,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.30),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          const Color(0xFF0B0E14).withValues(alpha: 0.88),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 14,
                  right: 14,
                  child: Icon(
                    Icons.menu_rounded,
                    color: Colors.white.withValues(alpha: 0.64),
                    size: 28,
                  ),
                ),
                Positioned(
                  right: 16,
                  top: height * 0.44,
                  child: Container(
                    width: width * 0.42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.34),
                      ),
                      color: Colors.black.withValues(alpha: 0.10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Profil bearbeiten',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  top: height * 0.33,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0xFF080B10),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: UserAvatar(
                            name: displayName,
                            avatarUrl: avatarUrl,
                            radius: 34,
                          ),
                        ),
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: AppAccentColors.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF080B10),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.photo_camera_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 18,
                  top: height * 0.59,
                  right: width * 0.34,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName.trim().isEmpty
                            ? 'Dein Profil'
                            : displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        width: width * 0.42,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: width * 0.64,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF171B23).withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(left: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppAccentColors.accent.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$remaining von 5 frei',
                          style: TextStyle(
                            color: AppAccentColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                for (
                  var spot = 0;
                  spot < ProfileBadgeShowcase.spotCount;
                  spot++
                )
                  if (!occupiedBySpot.containsKey(spot))
                    _SpotMarker(
                      placement: ProfileBadgeShowcase.placements[spot],
                      width: width,
                      height: height,
                      size: baseSize * 0.54,
                      label: '${spot + 1}',
                      onTap: () => onSelectSpot(spot),
                    ),
                for (var i = 0; i < slots.length; i++)
                  if (slots[i] != null)
                    _PositionedBadgeSticker(
                      sticker: slots[i]!,
                      width: width,
                      height: height,
                      baseSize: baseSize,
                      selected: i == selectedSlot,
                      onTap: () => onSelectSlot(i),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SpotMarker extends StatelessWidget {
  const _SpotMarker({
    required this.placement,
    required this.width,
    required this.height,
    required this.size,
    required this.label,
    required this.onTap,
  });

  final BadgeSpotPlacement placement;
  final double width;
  final double height;
  final double size;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final left = (placement.offset.dx * width - size / 2).clamp(
      0.0,
      width - size,
    );
    final top = (placement.offset.dy * height - size / 2).clamp(
      0.0,
      height - size,
    );

    return Positioned(
      left: left,
      top: top,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF101722).withValues(alpha: 0.52),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.50),
                fontSize: (size * 0.34).clamp(10.0, 14.0),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PositionedBadgeSticker extends StatelessWidget {
  const _PositionedBadgeSticker({
    required this.sticker,
    required this.width,
    required this.height,
    required this.baseSize,
    required this.selected,
    required this.onTap,
  });

  final ProfileBadgeSticker sticker;
  final double width;
  final double height;
  final double baseSize;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badge = app.Badge.getById(sticker.id);
    if (badge == null) return const SizedBox.shrink();
    final size = baseSize * sticker.scale;
    final placement = ProfileBadgeSticker.placementForSpot(sticker.spot);
    final angle = placement.angle;
    final left = (sticker.x * width - size / 2).clamp(0.0, width - size);
    final top = (sticker.y * height - size / 2).clamp(0.0, height - size);

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Transform.rotate(
          angle: angle,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            scale: selected ? 1.06 : 1,
            child: _BadgeStickerShell(
              size: size,
              selected: selected,
              child: _BadgeImage(badge: badge, size: size * 0.76),
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgeStickerShell extends StatelessWidget {
  const _BadgeStickerShell({
    required this.size,
    required this.selected,
    required this.child,
  });

  final double size;
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.09),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF101722).withValues(alpha: 0.94),
        border: Border.all(
          color: selected
              ? AppAccentColors.accent.withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: 0.72),
          width: selected ? 2.4 : 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: AppAccentColors.accent.withValues(
              alpha: selected ? 0.34 : 0.18,
            ),
            blurRadius: selected ? 22 : 14,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PlacedBadgeStrip extends StatelessWidget {
  const _PlacedBadgeStrip({
    required this.slots,
    required this.selectedSlot,
    required this.onSelect,
    required this.onPick,
    required this.onRemove,
    required this.onInfo,
  });

  final List<ProfileBadgeSticker?> slots;
  final int selectedSlot;
  final ValueChanged<int> onSelect;
  final VoidCallback onPick;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onInfo;

  @override
  Widget build(BuildContext context) {
    final filled = slots.whereType<ProfileBadgeSticker>().length;
    final hasFreeSlot = filled < ProfileBadgeShowcase.slotCount;

    return SizedBox(
      height: 112,
      child: Stack(
        children: [
          Scrollbar(
            radius: const Radius.circular(99),
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 10, right: 26),
              children: [
                for (var i = 0; i < slots.length; i++)
                  if (slots[i] != null) ...[
                    _PlacedBadgeChip(
                      slot: i,
                      sticker: slots[i]!,
                      selected: i == selectedSlot,
                      onSelect: () => onSelect(i),
                      onRemove: () => onRemove(i),
                      onInfo: () => onInfo(i),
                    ),
                    const SizedBox(width: 8),
                  ],
                if (hasFreeSlot) _AddBadgeChip(onTap: onPick),
              ],
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 12,
            child: IgnorePointer(
              child: Container(
                width: 30,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xFF171B23).withValues(alpha: 0.0),
                      const Color(0xFF171B23),
                    ],
                  ),
                ),
                alignment: Alignment.centerRight,
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.52),
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlacedBadgeChip extends StatelessWidget {
  const _PlacedBadgeChip({
    required this.slot,
    required this.sticker,
    required this.selected,
    required this.onSelect,
    required this.onRemove,
    required this.onInfo,
  });

  final int slot;
  final ProfileBadgeSticker sticker;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onRemove;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final badge = app.Badge.getById(sticker.id);
    if (badge == null) return const SizedBox.shrink();

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        width: 138,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? AppAccentColors.accent.withValues(alpha: 0.13)
              : const Color(0xFF0E121A).withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppAccentColors.accent.withValues(alpha: 0.46)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _BadgeStickerShell(
                  size: 38,
                  selected: selected,
                  child: _BadgeImage(badge: badge, size: 29),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: onInfo,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFFA7B0C1),
                      size: 18,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      color: Color(0xFFA7B0C1),
                      size: 19,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Platz ${sticker.spot + 1}',
              style: const TextStyle(
                color: Color(0xFFA7B0C1),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              badge.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddBadgeChip extends StatelessWidget {
  const _AddBadgeChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        width: 132,
        height: 94,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0E121A).withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppAccentColors.accent.withValues(alpha: 0.16),
              ),
              child: Icon(
                Icons.add_rounded,
                color: AppAccentColors.accent,
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Badge platzieren',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgePickerTile extends StatelessWidget {
  const _BadgePickerTile({
    required this.badge,
    required this.selected,
    required this.onTap,
    this.disabled = false,
  }) : clear = false;

  const _BadgePickerTile.clear({required this.selected, required this.onTap})
    : badge = null,
      clear = true,
      disabled = false;

  final app.Badge? badge;
  final bool selected;
  final VoidCallback onTap;
  final bool clear;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: disabled ? null : onTap,
      child: Ink(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: disabled
              ? const Color(0xFF0B0E14).withValues(alpha: 0.28)
              : selected
              ? AppAccentColors.accent.withValues(alpha: 0.16)
              : const Color(0xFF0B0E14).withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: disabled
                ? Colors.white.withValues(alpha: 0.04)
                : selected
                ? AppAccentColors.accent.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Opacity(
          opacity: disabled ? 0.46 : 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (clear)
                Icon(
                  Icons.remove_circle_outline_rounded,
                  color: Colors.white.withValues(alpha: 0.72),
                  size: 30,
                )
              else if (badge != null)
                _BadgeImage(badge: badge!, size: 42),
              const SizedBox(height: 8),
              Text(
                disabled
                    ? 'Schon platziert'
                    : clear
                    ? 'Leer'
                    : badge?.name ?? 'Badge',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeImage extends StatelessWidget {
  const _BadgeImage({required this.badge, required this.size});

  final app.Badge badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (badge.assetPath != null) {
      return Image.asset(
        badge.assetPath!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
      );
    }
    return Text(badge.emoji, style: TextStyle(fontSize: size * 0.7));
  }
}

/// 2026-08-18 (Aufgabe 4.2, vucko Sprachnachricht 09 vom 16.08.):
/// „Mehrstufige Badges, das heisst, Kurvenkoenig gibt es drei Stufen."
/// Die Leiste zeigt I, II, III und hebt die Stufe hervor, die man gerade
/// betrachtet. Farben: Bronze, Silber, Gold.
class _StufenLeiste extends StatelessWidget {
  const _StufenLeiste({required this.badge});

  final app.Badge badge;

  static Color _farbe(int stufe) => switch (stufe) {
    1 => const Color(0xFFCD7F32),
    2 => const Color(0xFFC7CEDB),
    _ => const Color(0xFFFFD166),
  };

  @override
  Widget build(BuildContext context) {
    final familie = badge.familie;
    if (familie == null || badge.stufe == 0) return const SizedBox.shrink();
    final stufen = app.Badge.familienBadges(
      familie,
    ).where((b) => b.stufe > 0).toList();
    if (stufen.length < 2) return const SizedBox.shrink();
    final titel = app.badgeFamilieVon(familie)?.titel;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final stufe in stufen) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 30,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: stufe.id == badge.id
                      ? _farbe(stufe.stufe).withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: stufe.id == badge.id
                        ? _farbe(stufe.stufe).withValues(alpha: 0.7)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Text(
                  app.Badge.stufenZeichen[stufe.stufe],
                  style: TextStyle(
                    color: stufe.id == badge.id
                        ? _farbe(stufe.stufe)
                        : Colors.white.withValues(alpha: 0.3),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          titel == null
              ? 'Stufe ${badge.stufe} von ${stufen.length}'
              : 'Stufe ${badge.stufe} von ${stufen.length} \u00b7 $titel',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
