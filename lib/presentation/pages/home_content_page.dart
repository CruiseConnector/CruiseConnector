import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';

class HomeContentPage extends StatefulWidget {
  final Function(int)? onTabChange;
  final int refreshKey;
  const HomeContentPage({super.key, this.onTabChange, this.refreshKey = 0});

  @override
  State<HomeContentPage> createState() => _HomeContentPageState();
}

class _HomeContentPageState extends State<HomeContentPage> {
  @override
  void didUpdateWidget(HomeContentPage old) {
    super.didUpdateWidget(old);
    if (widget.refreshKey != old.refreshKey && widget.refreshKey > 0) _loadStats();
  }

  int userLevel = 1;
  double levelProgress = 0;
  String levelName = 'Street Rookie';
  int xpToNextLevel = 100;
  int totalXp = 0;
  int totalRoutes = 0;
  double totalDistanceKm = 0;
  int badgeCount = 0;
  bool _loading = true;
  List<double> _weeklyChartData = List.filled(7, 0);
  int _followerCount = 0;
  int _streakDays = 0;
  List<SavedRoute> _recommendedRoutes = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final result = await GamificationService.calculateAndSync();
      final routes = await SavedRoutesService.getUserRoutes();

      // Wöchentliche Daten berechnen
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weeklyKm = List<double>.filled(7, 0);
      for (final r in routes) {
        if (r.createdAt.isAfter(weekStart)) {
          final dayIndex = r.createdAt.weekday - 1;
          if (dayIndex >= 0 && dayIndex < 7) {
            weeklyKm[dayIndex] += r.distanceKm;
          }
        }
      }
      final maxKm = weeklyKm.fold<double>(0, (a, b) => a > b ? a : b);
      final normalized = weeklyKm
          .map((km) => maxKm > 0 ? (km / maxKm).clamp(0.0, 1.0) : 0.0)
          .toList();

      // Streak berechnen (Tage in Folge gefahren)
      int streak = 0;
      if (routes.isNotEmpty) {
        final today = DateTime(now.year, now.month, now.day);
        // Alle Fahrtage sammeln
        final driveDays = <DateTime>{};
        for (final r in routes) {
          driveDays.add(DateTime(r.createdAt.year, r.createdAt.month, r.createdAt.day));
        }
        // Von heute rückwärts zählen
        var checkDay = today;
        // Wenn heute noch nicht gefahren, starte ab gestern
        if (!driveDays.contains(checkDay)) {
          checkDay = checkDay.subtract(const Duration(days: 1));
        }
        while (driveDays.contains(checkDay)) {
          streak++;
          checkDay = checkDay.subtract(const Duration(days: 1));
        }
      }

      // Empfohlene Routen laden (beliebte Routen anderer Nutzer)
      List<SavedRoute> recommended = [];
      try {
        recommended = await SavedRoutesService.getPopularRoutes(limit: 5);
      } catch (e) {
        debugPrint('[Home] Empfohlene Routen fehlgeschlagen: $e');
      }

      // Community stats
      final uid = Supabase.instance.client.auth.currentUser?.id;
      int followers = 0;
      if (uid != null) {
        try {
          followers = await SocialService.getFollowerCount(uid);
        } catch (e) {
          debugPrint('[Home] Follower-Count fehlgeschlagen: $e');
        }
      }

      if (mounted) {
        setState(() {
          userLevel = result.level.level;
          levelProgress = result.level.progress;
          levelName = result.level.name;
          xpToNextLevel = result.level.xpToNextLevel;
          totalXp = result.totalXp;
          totalRoutes = result.totalRoutes;
          totalDistanceKm = result.totalDistanceKm;
          badgeCount = result.earnedBadgeIds.length;
          _weeklyChartData = normalized;
          _followerCount = followers;
          _streakDays = streak;
          _recommendedRoutes = recommended;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Home] Daten laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final String userName = (user?.userMetadata?['username'] as String?)
        ?? user?.email?.split('@')[0]
        ?? 'User';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Willkommen zurück',
                        style: TextStyle(
                          color: Color(0xFFA0AEC0),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '$userName!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      backgroundColor: Color(0xFFFF3B30),
                      child: Icon(Icons.person, color: Colors.white, size: 32),
                    ),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.blue[700],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          '$userLevel',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Fortschritt Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1F26),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFFFFFFF).withValues(alpha: 0.06), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fortschritt',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _loading
                    ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF3B30))))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _statRow('⚡', '$totalXp XP gesamt'),
                          const SizedBox(height: 6),
                          _statRow('🏎️', '${totalDistanceKm.toStringAsFixed(0)} Km gefahren'),
                          const SizedBox(height: 6),
                          _statRow('🛣️', '$totalRoutes Strecken'),
                          const SizedBox(height: 6),
                          _statRow('🏅', '$badgeCount Badges'),
                        ],
                      ),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              'Level $userLevel - $levelName',
                              style: const TextStyle(
                                color: Color(0xFFA0AEC0),
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(levelProgress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 8,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: levelProgress,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Noch $xpToNextLevel XP bis Level ${userLevel + 1}',
                    style: const TextStyle(
                      color: Color(0xFFA0AEC0),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Empfohlene Routen Section (echte Daten aus DB)
            const Text(
              'Heute für dich',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            if (_recommendedRoutes.isEmpty && !_loading)
              _buildEmptyRecommendation()
            else if (_recommendedRoutes.isNotEmpty)
              Column(
                children: _recommendedRoutes
                    .map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildRecommendedRouteCard(r),
                        ))
                    .toList(),
              )
            else
              const SizedBox(height: 160, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF3B30))))),
            const SizedBox(height: 16),

            // Community + Chart Section
            SizedBox(
              height: 200,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1F26),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFFFFFFF).withValues(alpha: 0.06), width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Community',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildCommunityItem('$_followerCount Follower', '👥'),
                          const SizedBox(height: 4),
                          _buildCommunityItem('$totalRoutes Fahrten absolviert', '🔥'),
                          const SizedBox(height: 4),
                          _buildCommunityItem('Level $userLevel - $levelName', '📍'),
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            child: GestureDetector(
                              onTap: () {
                                  widget.onTabChange?.call(1);
                              },
                              child: Container(
                                height: 35.0,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(30.0),
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  'Beitreten',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1F26),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFFFFFFF).withValues(alpha: 0.06), width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Letzte 7 Tage',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: Row(
                              children: [
                                const RotatedBox(
                                  quarterTurns: 3,
                                  child: Text(
                                    'Kilometer',
                                    style: TextStyle(
                                      color: Color(0xFFA0AEC0),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      _buildChartBar('Mo', _weeklyChartData[0]),
                                      _buildChartBar('Di', _weeklyChartData[1]),
                                      _buildChartBar('Mi', _weeklyChartData[2]),
                                      _buildChartBar('Do', _weeklyChartData[3]),
                                      _buildChartBar('Fr', _weeklyChartData[4]),
                                      _buildChartBar('Sa', _weeklyChartData[5]),
                                      _buildChartBar('So', _weeklyChartData[6]),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Streak Widget
            _buildStreakWidget(),
          ],
        ),
      ),
    );
  }

  // ── Empfohlene Route Card (echte Daten) ──────────────────────────────────

  Widget _buildRecommendedRouteCard(SavedRoute route) {
    // Farbschema basierend auf Stil
    final colors = switch (route.style) {
      'Kurvenjagd' => [const Color(0xFF1B5E20), const Color(0xFF388E3C)],
      'Sport Mode' => [const Color(0xFFB71C1C), const Color(0xFFD32F2F)],
      'Abendrunde' => [const Color(0xFF1A237E), const Color(0xFF3949AB)],
      'Entdecker'  => [const Color(0xFFE65100), const Color(0xFFFB8C00)],
      _            => [const Color(0xFF37474F), const Color(0xFF546E7A)],
    };

    return GestureDetector(
      onTap: () {
        CruiseModePage.pendingRoute.value = route;
        widget.onTabChange?.call(2);
      },
      child: Container(
        width: double.infinity,   // volle Breite wie Fortschritt-Widget
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    route.name ?? '${route.styleEmoji} ${route.style}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${route.formattedDistance} · ${route.formattedDuration}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (route.rating != null) ...[
                        const Icon(Icons.star, color: Colors.amber, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${route.rating}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Icon(
                        route.isRoundTrip ? Icons.loop : Icons.arrow_forward,
                        color: Colors.white54,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        route.isRoundTrip ? 'Rundkurs' : 'A nach B',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  route.styleEmoji,
                  style: const TextStyle(fontSize: 28),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyRecommendation() {
    return GestureDetector(
      onTap: () => widget.onTabChange?.call(2),
      child: Container(
        height: 160,
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFFFFF).withValues(alpha: 0.06)),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore, color: Color(0xFFFF3B30), size: 32),
            SizedBox(height: 10),
            Text(
              'Starte deine erste Fahrt!',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text(
              'Empfohlene Routen erscheinen hier',
              style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ── Streak Widget ────────────────────────────────────────────────────────

  Widget _buildStreakWidget() {
    final hasStreak = _streakDays > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasStreak
              ? const Color(0xFFFF3B30).withValues(alpha: 0.3)
              : const Color(0xFFFFFFFF).withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: hasStreak
                  ? const Color(0xFFFF3B30).withValues(alpha: 0.15)
                  : const Color(0xFF2D3748),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                hasStreak ? '🔥' : '❄️',
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasStreak ? '$_streakDays Tage Streak' : 'Kein aktiver Streak',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasStreak
                      ? 'Weiter so! Fahre heute um den Streak zu halten.'
                      : 'Starte eine Fahrt und beginne deinen Streak!',
                  style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 12),
                ),
              ],
            ),
          ),
          if (hasStreak)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_streakDays}d',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Helper Widgets ───────────────────────────────────────────────────────

  Widget _statRow(String emoji, String text) {
    return Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          text,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }

  Widget _buildCommunityItem(String text, String emoji) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFFA0AEC0),
              fontSize: 11,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildChartBar(String day, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              width: 8,
              decoration: BoxDecoration(
                color: const Color(0xFF2D3748),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: value,
                  child: Container(
                    width: 8,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            day,
            style: const TextStyle(
              color: Color(0xFFA0AEC0),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
