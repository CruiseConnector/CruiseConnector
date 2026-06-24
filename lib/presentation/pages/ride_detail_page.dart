import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/domain/models/user_drive_session.dart';
import 'package:cruise_connect/presentation/pages/route_share_page.dart';

/// Strava-artige Detailansicht einer abgeschlossenen Fahrt.
///
/// 2026-06-25 (vucko): Aufrufbar aus der Analytics-„Letzte Fahrten"-Liste —
/// vorher waren die Zeilen tot. Zeigt die Eckdaten groß + ästhetisch (Distanz,
/// Dauer, Top-Speed, Ø-Tempo, XP) mit Status + Datum. (Foto + Karten-Vorschau +
/// Nachträglich-Speichern folgen in weiteren Schritten.)
class RideDetailPage extends StatelessWidget {
  const RideDetailPage({super.key, required this.session});

  final UserDriveSession session;

  static const _months = [
    'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
    'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
  ];

  String get _styleLabel =>
      (session.routeStyle?.trim().isNotEmpty == true)
          ? session.routeStyle!.trim()
          : 'Cruise';

  String _formatDistance(double km) =>
      km >= 100 ? '${km.toStringAsFixed(0)} km' : '${km.toStringAsFixed(1)} km';

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    final s = seconds % 60;
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  String _formatDate(DateTime dt) {
    final l = dt.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '${l.day}. ${_months[l.month - 1]} ${l.year} · $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final topSpeed = session.topSpeedKmh;
    final avgKmh = session.durationSeconds > 0
        ? session.distanceKm / (session.durationSeconds / 3600.0)
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Fahrt',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
            tooltip: 'Teilen',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RouteSharePage(
                  data: RouteShareData(
                    title: _styleLabel,
                    subtitle: _formatDate(session.createdAt),
                    segments: const [],
                    distanceLabel: _formatDistance(session.distanceKm),
                    durationLabel: _formatDuration(session.durationSeconds),
                    topSpeedLabel:
                        session.topSpeedKmh != null && session.topSpeedKmh! > 0
                            ? '${session.topSpeedKmh!.toStringAsFixed(0)} km/h'
                            : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildHero(accent),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  'Distanz',
                  _formatDistance(session.distanceKm),
                  Icons.map_rounded,
                  accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statTile(
                  'Dauer',
                  _formatDuration(session.durationSeconds),
                  Icons.timer_rounded,
                  accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  'Top-Speed',
                  topSpeed != null && topSpeed > 0
                      ? '${topSpeed.toStringAsFixed(0)} km/h'
                      : '—',
                  Icons.speed_rounded,
                  accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statTile(
                  'Ø Tempo',
                  avgKmh != null && avgKmh > 0
                      ? '${avgKmh.toStringAsFixed(0)} km/h'
                      : '—',
                  Icons.trending_up_rounded,
                  accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _statTile(
            'Verdiente XP',
            '${session.xpAwarded} XP',
            Icons.bolt_rounded,
            accent,
          ),
        ],
      ),
    );
  }

  Widget _buildHero(Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(accent, Colors.black, 0.12)!,
            Color.lerp(accent, Colors.black, 0.46)!,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  session.completedAtEnd
                      ? Icons.flag_rounded
                      : Icons.route_rounded,
                  color: Colors.white,
                  size: 15,
                ),
                const SizedBox(width: 5),
                Text(
                  session.completedAtEnd ? 'Abgeschlossen' : 'Aufgezeichnet',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _styleLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatDate(session.createdAt),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFA0AEC0),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
