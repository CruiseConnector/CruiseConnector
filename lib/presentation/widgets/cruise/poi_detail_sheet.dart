import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/route_poi_service.dart';
import 'package:cruise_connect/data/services/opening_hours_parser.dart';

/// 2026-05-24 (vucko): Aesthetisches POI-Detail-Sheet.
///
/// Header mit großem Icon-Badge in Typ-Farbe, Status-Badge (Offen / Schließt
/// in X Min / Geschlossen), Distanz-Chip, ausklappbare Wochentag-Tabelle.
class PoiDetailSheet extends StatelessWidget {
  final RoutePoi poi;
  // 2026-05-28 (vucko): Callback für „Tankstelle in Route einbauen".
  // null = Button wird nicht gezeigt (z.B. keine aktive Route).
  final VoidCallback? onAddToRoute;
  // Wenn POI bereits Teil der Route ist: Button wird zu „Entfernen".
  final bool isAlreadyOnRoute;

  const PoiDetailSheet({
    super.key,
    required this.poi,
    this.onAddToRoute,
    this.isAlreadyOnRoute = false,
  });

  static Future<void> show(
    BuildContext context,
    RoutePoi poi, {
    VoidCallback? onAddToRoute,
    bool isAlreadyOnRoute = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => PoiDetailSheet(
        poi: poi,
        onAddToRoute: onAddToRoute,
        isAlreadyOnRoute: isAlreadyOnRoute,
      ),
    );
  }

  Color _accentForType() {
    return switch (poi.type) {
      PoiType.fuel => const Color(0xFFEF4444),
      PoiType.restaurant => const Color(0xFFFB923C),
      PoiType.cafe => const Color(0xFFA78BFA),
      PoiType.fastFood => const Color(0xFFFBBF24),
      PoiType.pub => const Color(0xFF22C55E),
      PoiType.motorcycleRepair => const Color(0xFF2DD4BF),
      PoiType.parking => const Color(0xFF60A5FA),
      PoiType.toilets => const Color(0xFF9CA3AF),
    };
  }

  IconData _iconForType() {
    return switch (poi.type) {
      PoiType.fuel => Icons.local_gas_station_rounded,
      PoiType.restaurant => Icons.restaurant_rounded,
      PoiType.cafe => Icons.local_cafe_rounded,
      PoiType.fastFood => Icons.fastfood_rounded,
      PoiType.pub => Icons.sports_bar_rounded,
      PoiType.motorcycleRepair => Icons.build_rounded,
      PoiType.parking => Icons.local_parking_rounded,
      PoiType.toilets => Icons.wc_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentForType();
    final hours = OpeningHoursParser.parse(poi.openingHours);
    final weekList = hours.parseFailed
        ? const <({String day, String hours, bool isToday})>[]
        : OpeningHoursParser.renderWeekList(hours);
    final (statusColor, statusBg, statusLabel) = _statusVisuals(hours);
    final distanceText = poi.distanceFromRouteMeters < 1000
        ? '${poi.distanceFromRouteMeters.round()} m abseits der Route'
        : '${(poi.distanceFromRouteMeters / 1000).toStringAsFixed(1)} km abseits der Route';

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.14),
                  const Color(0xFF11141B),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.5],
              ),
              border: Border(
                top: BorderSide(
                  color: accent.withValues(alpha: 0.45),
                  width: 1.2,
                ),
              ),
            ),
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag-Handle
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  // Header: Icon-Badge + Name + Type
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accent.withValues(alpha: 0.95),
                              accent.withValues(alpha: 0.62),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.45),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          _iconForType(),
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              poi.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                                height: 1.05,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              poi.brand != null && poi.brand!.isNotEmpty &&
                                      poi.brand != poi.displayName
                                  ? '${poi.type.label} · ${poi.brand}'
                                  : poi.type.label,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Status-Badge + Distanz nebeneinander
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusChip(
                        label: statusLabel,
                        color: statusColor,
                        bgColor: statusBg,
                        icon: _statusIcon(hours.status),
                      ),
                      _InfoChip(
                        label: distanceText,
                        color: AppAccentColors.accent,
                        icon: Icons.alt_route_rounded,
                      ),
                    ],
                  ),
                  // Opening-Hours-Details
                  if (weekList.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    const _SectionHeader(label: 'Öffnungszeiten'),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < weekList.length; i++)
                            _WeekRow(
                              day: weekList[i].day,
                              hours: weekList[i].hours,
                              isToday: weekList[i].isToday,
                              isLast: i == weekList.length - 1,
                            ),
                        ],
                      ),
                    ),
                  ] else if (hours.parseFailed && poi.openingHours != null) ...[
                    const SizedBox(height: 22),
                    const _SectionHeader(label: 'Öffnungszeiten'),
                    const SizedBox(height: 8),
                    Text(
                      poi.openingHours!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ] else if (poi.openingHours == null) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.4)),
                        const SizedBox(width: 6),
                        Text(
                          'Keine Öffnungszeiten hinterlegt',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],
                  // 2026-05-28 (vucko): „Zur Route hinzufügen" Button
                  if (onAddToRoute != null) ...[
                    const SizedBox(height: 22),
                    _AddToRouteButton(
                      accent: accent,
                      isAlreadyOnRoute: isAlreadyOnRoute,
                      poiTypeLabel: poi.type.label,
                      onTap: () {
                        Navigator.of(context).pop();
                        onAddToRoute!();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  (Color, Color, String) _statusVisuals(OpeningHoursInfo info) {
    switch (info.status) {
      case OpenStatus.open24_7:
        return (const Color(0xFF34D399), const Color(0x2034D399), 'Rund um die Uhr');
      case OpenStatus.open:
        return (const Color(0xFF34D399), const Color(0x2034D399), info.todayLabel);
      case OpenStatus.closingSoon:
        return (const Color(0xFFFB923C), const Color(0x33FB923C), info.todayLabel);
      case OpenStatus.closedNow:
        return (const Color(0xFF94A3B8), const Color(0x2094A3B8), info.todayLabel);
      case OpenStatus.closedToday:
        return (const Color(0xFFF87171), const Color(0x20F87171), 'Heute geschlossen');
      case OpenStatus.unknown:
        return (const Color(0xFF94A3B8), const Color(0x2094A3B8), 'Keine Angabe');
    }
  }

  IconData _statusIcon(OpenStatus s) {
    return switch (s) {
      OpenStatus.open24_7 => Icons.lock_open_rounded,
      OpenStatus.open => Icons.check_circle_rounded,
      OpenStatus.closingSoon => Icons.access_time_filled_rounded,
      OpenStatus.closedNow => Icons.lock_clock,
      OpenStatus.closedToday => Icons.do_not_disturb_on_rounded,
      OpenStatus.unknown => Icons.help_outline_rounded,
    };
  }
}

/// 2026-05-28 (vucko): "Zur Route hinzufügen" Button für POI-Sheet.
/// Triggert eine Re-Routing mit dem POI als Pflicht-Wegpunkt.
class _AddToRouteButton extends StatelessWidget {
  final Color accent;
  final bool isAlreadyOnRoute;
  final String poiTypeLabel;
  final VoidCallback onTap;

  const _AddToRouteButton({
    required this.accent,
    required this.isAlreadyOnRoute,
    required this.poiTypeLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isAlreadyOnRoute
        ? const Color(0xFFF87171)
        : accent;
    final label = isAlreadyOnRoute
        ? 'Aus Route entfernen'
        : 'Route über diese${_genderArticleSuffix()} ${poiTypeLabel.toLowerCase()}';
    final icon = isAlreadyOnRoute
        ? Icons.remove_circle_outline_rounded
        : Icons.add_road_rounded;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.95),
                color.withValues(alpha: 0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Tankstelle / Werkstatt = feminin → "diese"
  // Café / Restaurant / Imbiss = neutrum → "dieses"
  // Pub / Parkplatz = maskulin → "diesen"
  // Default: feminin ("diese"), passt für Tankstelle (häufigster Fall).
  String _genderArticleSuffix() {
    final lower = poiTypeLabel.toLowerCase();
    if (lower == 'restaurant' || lower == 'café' || lower == 'imbiss' || lower == 'wc') {
      return 's';
    }
    if (lower == 'pub' || lower == 'parkplatz') {
      return 'n';
    }
    return '';
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color bgColor;
  final IconData icon;

  const _StatusChip({
    required this.label,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _InfoChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.32), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.55),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  final String day;
  final String hours;
  final bool isToday;
  final bool isLast;

  const _WeekRow({
    required this.day,
    required this.hours,
    required this.isToday,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final isClosed = hours == 'Geschlossen';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              day,
              style: TextStyle(
                color: isToday
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.62),
                fontSize: 13,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              hours,
              style: TextStyle(
                color: isToday
                    ? Colors.white
                    : isClosed
                        ? Colors.white.withValues(alpha: 0.35)
                        : Colors.white.withValues(alpha: 0.72),
                fontSize: 13,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
