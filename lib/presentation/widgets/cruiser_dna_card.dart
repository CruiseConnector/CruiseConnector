import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// "Kurven-DNA" — persönliches Fahrerprofil im Profile-Tab.
/// Aggregiert Daten aus drive_sessions + route_ratings zu einem
/// identitäts-bildenden Tag-Cloud-Style-Widget.
///
/// 2026-05-24 (vucko Task #40):
/// Quelle: drive_sessions (Distanz, Stil, Curves), route_ratings (Tags),
/// GamificationService (Streak, Level, Total-XP).
class CruiserDnaCard extends StatefulWidget {
  const CruiserDnaCard({super.key});

  @override
  State<CruiserDnaCard> createState() => _CruiserDnaCardState();
}

class _CruiserDnaCardState extends State<CruiserDnaCard> {
  _DnaStats? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stats = await _DnaStats.fetch();
    if (mounted) {
      setState(() {
        _stats = stats;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    if (_loading) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
        ),
      );
    }
    final s = _stats;
    if (s == null || s.totalRoutes == 0) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            const Text('🧬', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Deine Kurven-DNA erscheint nach der ersten Fahrt',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.70),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.22),
            const Color(0xFF131821),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.14),
            blurRadius: 18,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🧬', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              const Text(
                'Deine Kurven-DNA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  s.riderType,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DnaChip(emoji: '🛣️', label: '${s.totalDistanceKm.round()} km'),
              _DnaChip(
                  emoji: '⏱️',
                  label: '${s.totalHours.toStringAsFixed(1)} h'),
              _DnaChip(emoji: '🌀', label: '${s.totalRoutes} Touren'),
              if (s.topStyle != null)
                _DnaChip(emoji: '⭐', label: 'Stil: ${s.topStyle}'),
              if (s.topRegion != null)
                _DnaChip(emoji: '📍', label: s.topRegion!),
              if (s.curvesPer50Km > 0)
                _DnaChip(
                    emoji: '↪️',
                    label:
                        '${s.curvesPer50Km.toStringAsFixed(1)} Kurven/50km'),
              _DnaChip(emoji: '⚡', label: 'Lvl ${s.level}'),
              if (s.streakDays >= 2)
                _DnaChip(emoji: '🔥', label: '${s.streakDays}-Tage-Streak'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DnaChip extends StatelessWidget {
  const _DnaChip({required this.emoji, required this.label});
  final String emoji;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DnaStats {
  final int totalRoutes;
  final double totalDistanceKm;
  final double totalHours;
  final int totalXp;
  final int level;
  final int streakDays;
  final String? topStyle;
  final String? topRegion;
  final double curvesPer50Km;

  String get riderType {
    if (curvesPer50Km >= 55) return 'KURVEN-JÄGER';
    if (curvesPer50Km >= 35) return 'SPORT-TYP';
    if (curvesPer50Km >= 20) return 'CRUISER';
    return 'EXPLORER';
  }

  _DnaStats({
    required this.totalRoutes,
    required this.totalDistanceKm,
    required this.totalHours,
    required this.totalXp,
    required this.level,
    required this.streakDays,
    required this.topStyle,
    required this.topRegion,
    required this.curvesPer50Km,
  });

  static Future<_DnaStats?> fetch() async {
    try {
      final db = Supabase.instance.client;
      final userId = db.auth.currentUser?.id;
      if (userId == null) return null;
      // Gesamt + Streak via GamificationService
      final gam = await GamificationService.calculateAndSync();
      // Top-Style + Top-Region + Kurven aus drive_sessions
      final sessions = await db
          .from('drive_sessions')
          .select('style, region, curve_count, distance_km')
          .eq('user_id', userId)
          .limit(500);
      final styleCounts = <String, int>{};
      final regionCounts = <String, int>{};
      var totalCurves = 0;
      var sumDistance = 0.0;
      for (final s in sessions) {
        final st = s['style'] as String?;
        if (st != null && st.isNotEmpty) {
          styleCounts[st] = (styleCounts[st] ?? 0) + 1;
        }
        final reg = s['region'] as String?;
        if (reg != null && reg.isNotEmpty) {
          regionCounts[reg] = (regionCounts[reg] ?? 0) + 1;
        }
        totalCurves += ((s['curve_count'] ?? 0) as num).toInt();
        sumDistance += ((s['distance_km'] ?? 0) as num).toDouble();
      }
      String? topOf(Map<String, int> m) {
        if (m.isEmpty) return null;
        final sorted = m.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return sorted.first.key;
      }
      final cur50 = sumDistance > 0
          ? (totalCurves / sumDistance) * 50.0
          : 0.0;
      // Streak via drive_sessions (consecutive Tagen)
      final streakRows = await db
          .from('drive_sessions')
          .select('created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(60);
      var streak = 0;
      final today = DateTime.now();
      final seenDays = <String>{};
      for (final row in streakRows) {
        final ts =
            DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal();
        if (ts == null) continue;
        final key = '${ts.year}-${ts.month}-${ts.day}';
        seenDays.add(key);
      }
      for (var d = 0; d < 60; d++) {
        final dayTs = today.subtract(Duration(days: d));
        final key = '${dayTs.year}-${dayTs.month}-${dayTs.day}';
        if (seenDays.contains(key)) {
          streak++;
        } else if (d > 0) {
          break;
        }
      }
      return _DnaStats(
        totalRoutes: gam.totalRoutes,
        totalDistanceKm: gam.totalDistanceKm,
        totalHours: gam.totalHours,
        totalXp: gam.totalXp,
        level: gam.level.level,
        streakDays: streak,
        topStyle: topOf(styleCounts),
        topRegion: topOf(regionCounts),
        curvesPer50Km: cur50,
      );
    } catch (e) {
      return null;
    }
  }
}
