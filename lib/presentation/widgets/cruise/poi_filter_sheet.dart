import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/poi_settings_service.dart';
import 'package:cruise_connect/data/services/route_poi_service.dart';

/// 2026-05-28 (vucko Task #75): Floating POI-Filter Bottom-Sheet.
///
/// User-Wunsch: „Tankstellen/Cafés/etc. sollen als EIN Toggle auf dem
/// Bildschirm sein, aestetisch, alle Optionen gleichzeitig einstellbar".
///
/// UX:
/// - Floating-Action-Button öffnet das Sheet
/// - Grid 2 Spalten mit großen tappbaren Chips pro POI-Typ
/// - Chip zeigt Icon + Label + animierte Switch-Markierung
/// - Toggle „Alles" oben + „Nichts" rechts
/// - Schließt automatisch nach 1.5s ohne Interaktion (optional)
/// - Haptic-Feedback bei jedem Toggle
class PoiFilterSheet extends StatefulWidget {
  const PoiFilterSheet({
    super.key,
    this.meldungenAn,
    this.onMeldungenUmschalten,
  });

  /// 2026-09-02 (Vucko, Sprachnachricht): "die meldung bzw das man baustellen
  /// ein oder ausschalten soll kann weg oder in die poi liste rein".
  ///
  /// Der Schalter fuer fremde Meldungen hatte einen eigenen Knopf in der
  /// rechten Spalte und belegte damit einen der vier Plaetze. Er gehoert
  /// inhaltlich hierher: es geht um das, was auf der Karte zu sehen ist.
  ///
  /// Der Zustand bleibt in der Fahransicht und wird nur durchgereicht. Ihn
  /// hierher zu verschieben haette bedeutet, ihn aus einem Seitenzustand in
  /// einen Dienst umzubauen und elf Aufrufstellen mitzuziehen — viel
  /// Bewegung fuer einen Schalter.
  ///
  /// Ohne diese beiden Angaben zeigt das Blatt den Schalter gar nicht. So
  /// bleibt es an Stellen benutzbar, die den Schalter nicht kennen.
  final bool? meldungenAn;
  final VoidCallback? onMeldungenUmschalten;

  static Future<void> show(
    BuildContext context, {
    bool? meldungenAn,
    VoidCallback? onMeldungenUmschalten,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => PoiFilterSheet(
        meldungenAn: meldungenAn,
        onMeldungenUmschalten: onMeldungenUmschalten,
      ),
    );
  }

  @override
  State<PoiFilterSheet> createState() => _PoiFilterSheetState();
}

class _PoiFilterSheetState extends State<PoiFilterSheet> {
  /// Spiegel des durchgereichten Zustands. Ohne ihn bliebe der Schalter im
  /// offenen Blatt stehen, bis man es schliesst und neu oeffnet: die
  /// Fahransicht baut sich zwar neu auf, dieses Blatt liegt aber in einer
  /// eigenen Route darueber und bekommt davon nichts mit.
  bool? _meldungenAn;

  static const List<_PoiFilterItem> _items = [
    _PoiFilterItem(
      type: PoiType.fuel,
      label: 'Tankstellen',
      icon: Icons.local_gas_station_rounded,
      color: Color(0xFFEF4444),
    ),
    _PoiFilterItem(
      type: PoiType.restaurant,
      label: 'Restaurants',
      icon: Icons.restaurant_rounded,
      color: Color(0xFFFB923C),
    ),
    _PoiFilterItem(
      type: PoiType.cafe,
      label: 'Cafés',
      icon: Icons.local_cafe_rounded,
      color: Color(0xFFA78BFA),
    ),
    _PoiFilterItem(
      type: PoiType.fastFood,
      label: 'Imbisse',
      icon: Icons.fastfood_rounded,
      color: Color(0xFFFBBF24),
    ),
    _PoiFilterItem(
      type: PoiType.pub,
      label: 'Pubs',
      icon: Icons.sports_bar_rounded,
      color: Color(0xFF22C55E),
    ),
    _PoiFilterItem(
      type: PoiType.motorcycleRepair,
      label: 'Werkstätten',
      icon: Icons.build_rounded,
      color: Color(0xFF2DD4BF),
    ),
    _PoiFilterItem(
      type: PoiType.parking,
      label: 'Parkplätze',
      icon: Icons.local_parking_rounded,
      color: Color(0xFF60A5FA),
    ),
    _PoiFilterItem(
      type: PoiType.toilets,
      label: 'WC',
      icon: Icons.wc_rounded,
      color: Color(0xFF9CA3AF),
    ),
  ];

  bool _getEnabled(PoiType type) {
    final s = PoiSettingsService.instance;
    return switch (type) {
      PoiType.fuel => s.fuel,
      PoiType.restaurant => s.restaurant,
      PoiType.cafe => s.cafe,
      PoiType.fastFood => s.fastFood,
      PoiType.pub => s.pub,
      PoiType.motorcycleRepair => s.repair,
      PoiType.parking => s.parking,
      PoiType.toilets => s.toilets,
    };
  }

  Future<void> _setEnabled(PoiType type, bool v) async {
    final s = PoiSettingsService.instance;
    HapticFeedback.selectionClick();
    switch (type) {
      case PoiType.fuel:
        await s.setFuel(v);
      case PoiType.restaurant:
        await s.setRestaurant(v);
      case PoiType.cafe:
        await s.setCafe(v);
      case PoiType.fastFood:
        await s.setFastFood(v);
      case PoiType.pub:
        await s.setPub(v);
      case PoiType.motorcycleRepair:
        await s.setRepair(v);
      case PoiType.parking:
        await s.setParking(v);
      case PoiType.toilets:
        await s.setToilets(v);
    }
    if (mounted) setState(() {});
  }

  Future<void> _setAll(bool v) async {
    HapticFeedback.mediumImpact();
    for (final item in _items) {
      await _setEnabled(item.type, v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final enabledCount = _items.where((i) => _getEnabled(i.type)).length;
    final allEnabled = enabledCount == _items.length;
    final noneEnabled = enabledCount == 0;
    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.12),
                const Color(0xFF11141B),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.4],
            ),
            border: Border(
              top: BorderSide(
                color: accent.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                // Header
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: accent.withValues(alpha: 0.4),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.tune_rounded, color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'POIs auf der Karte',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            '$enabledCount von ${_items.length} aktiviert',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _MiniButton(
                      label: allEnabled ? 'Aus' : 'Alle',
                      icon: allEnabled
                          ? Icons.visibility_off_outlined
                          : Icons.done_all_rounded,
                      color: allEnabled
                          ? const Color(0xFFF87171)
                          : accent,
                      onTap: () => _setAll(!allEnabled),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // Grid
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  childAspectRatio: 2.4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  children: [
                    for (final item in _items)
                      _PoiFilterChip(
                        item: item,
                        enabled: _getEnabled(item.type),
                        onTap: () => _setEnabled(item.type, !_getEnabled(item.type)),
                      ),
                  ],
                ),
                // 2026-09-02: der Schalter fuer fremde Meldungen. Steht
                // bewusst UNTER dem Raster und optisch abgesetzt: es sind
                // nicht meine Punkte auf der Karte, sondern die Warnungen
                // anderer Fahrer.
                if (widget.meldungenAn != null &&
                    widget.onMeldungenUmschalten != null) ...[
                  const SizedBox(height: 18),
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  const SizedBox(height: 14),
                  _MeldungenZeile(
                    an: _meldungenAn ?? widget.meldungenAn!,
                    onUmschalten: () {
                      setState(
                        () => _meldungenAn =
                            !(_meldungenAn ?? widget.meldungenAn!),
                      );
                      widget.onMeldungenUmschalten!();
                    },
                  ),
                ],
                const SizedBox(height: 16),
                if (noneEnabled)
                  Center(
                    child: Text(
                      'Keine POIs ausgewählt, Map bleibt clean.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                else
                  Center(
                    child: Text(
                      'Tippe Punkte auf der Map an für Details.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Die Zeile fuer fremde Meldungen im POI-Blatt.
class _MeldungenZeile extends StatelessWidget {
  const _MeldungenZeile({required this.an, required this.onUmschalten});

  final bool an;
  final VoidCallback onUmschalten;

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF9500);
    return InkWell(
      onTap: onUmschalten,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: (an ? orange : Colors.white).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: Icon(
                an ? Icons.warning_amber_rounded : Icons.report_off_outlined,
                size: 20,
                color: an ? orange : Colors.white.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Meldungen anderer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    an
                        ? 'Baustellen und Unfälle werden angezeigt und angesagt.'
                        : 'Baustellen und Unfälle bleiben aus.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: an,
              onChanged: (_) => onUmschalten(),
              activeThumbColor: Colors.white,
              activeTrackColor: orange,
            ),
          ],
        ),
      ),
    );
  }
}

class _PoiFilterItem {
  final PoiType type;
  final String label;
  final IconData icon;
  final Color color;
  const _PoiFilterItem({
    required this.type,
    required this.label,
    required this.icon,
    required this.color,
  });
}

class _PoiFilterChip extends StatelessWidget {
  final _PoiFilterItem item;
  final bool enabled;
  final VoidCallback onTap;

  const _PoiFilterChip({
    required this.item,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: enabled
            ? LinearGradient(
                colors: [
                  item.color.withValues(alpha: 0.32),
                  item.color.withValues(alpha: 0.14),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: enabled ? null : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: enabled
              ? item.color.withValues(alpha: 0.65)
              : Colors.white.withValues(alpha: 0.08),
          width: 1.3,
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: item.color.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: enabled
                        ? item.color.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    item.icon,
                    color: enabled
                        ? item.color
                        : Colors.white.withValues(alpha: 0.35),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: enabled
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: enabled ? item.color : Colors.transparent,
                    border: Border.all(
                      color: enabled
                          ? item.color
                          : Colors.white.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: enabled
                      ? const Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: Colors.white,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _MiniButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
