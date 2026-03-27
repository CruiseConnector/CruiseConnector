import 'package:flutter/material.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/domain/models/user_level.dart';

class AnalyticsPage extends StatefulWidget {
  final int refreshKey;
  const AnalyticsPage({super.key, this.refreshKey = 0});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage>
    with SingleTickerProviderStateMixin {
  @override
  void didUpdateWidget(AnalyticsPage old) {
    super.didUpdateWidget(old);
    if (widget.refreshKey != old.refreshKey && widget.refreshKey > 0) {
      _loadData();
    }
  }

  late TabController _tabController;
  bool _loading = true;

  int _totalRoutes = 0;
  double _totalDistanceKm = 0;
  double _totalHours = 0;
  int _totalXp = 0;
  UserLevel _level = UserLevel.fromXp(0);
  List<app.Badge> _earnedBadges = [];
  List<SavedRoute> _allRoutes = [];

  List<double> _weeklyChartData = List.filled(7, 0);
  List<double> _weeklyRawKm = List.filled(7, 0);
  List<double> _weeklyRawXp = List.filled(7, 0);
  final List<String> _weeklyLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  // Streak
  int _streakDays = 0;

  // Monats-/Jahresvergleich
  double _thisMonthKm = 0;
  double _lastMonthKm = 0;
  int _thisMonthRoutes = 0;
  int _lastMonthRoutes = 0;
  double _thisYearKm = 0;
  double _lastYearKm = 0;
  int _thisYearRoutes = 0;
  int _lastYearRoutes = 0;

  // Monatliche Chart-Daten (12 Monate)
  List<double> _monthlyChartData = List.filled(12, 0);
  List<double> _monthlyRawKm = List.filled(12, 0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final gamResult = await GamificationService.calculateAndSync();
      final routes = await SavedRoutesService.getUserRoutes();

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(
        Duration(days: todayStart.weekday - 1),
      );
      final weeklyKm = List<double>.filled(7, 0);
      final weeklyXp = List<double>.filled(7, 0);

      // Monats-/Jahresberechnung
      final thisMonthStart = DateTime(now.year, now.month);
      final lastMonthStart = DateTime(now.year, now.month - 1);
      final thisYearStart = DateTime(now.year);
      final lastYearStart = DateTime(now.year - 1);
      final lastYearEnd = DateTime(now.year);

      double thisMonthKm = 0, lastMonthKm = 0;
      int thisMonthRoutes = 0, lastMonthRoutes = 0;
      double thisYearKm = 0, lastYearKm = 0;
      int thisYearRoutes = 0, lastYearRoutes = 0;

      // Monatliche km (dieses Jahr)
      final monthlyKm = List<double>.filled(12, 0);

      // Streak-Berechnung
      final driveDays = <DateTime>{};

      for (final r in routes) {
        final createdAt = r.createdAt.toLocal();
        final routeDay = DateTime(
          createdAt.year,
          createdAt.month,
          createdAt.day,
        );

        // Wöchentliche Daten
        if (!routeDay.isBefore(weekStart)) {
          final dayIndex = createdAt.weekday - 1;
          if (dayIndex >= 0 && dayIndex < 7) {
            weeklyKm[dayIndex] += r.distanceKm;
            final estCurves = (r.distanceKm / 5).round();
            weeklyXp[dayIndex] += GamificationService.calculateRouteXp(
              distanceKm: r.distanceKm,
              curves: estCurves,
              style: r.style,
            );
          }
        }

        // Monatsdaten
        if (!createdAt.isBefore(thisMonthStart)) {
          thisMonthKm += r.distanceKm;
          thisMonthRoutes++;
        } else if (!createdAt.isBefore(lastMonthStart) &&
            createdAt.isBefore(thisMonthStart)) {
          lastMonthKm += r.distanceKm;
          lastMonthRoutes++;
        }

        // Jahresdaten
        if (!createdAt.isBefore(thisYearStart)) {
          thisYearKm += r.distanceKm;
          thisYearRoutes++;
          // Monatliche Aufschlüsselung
          final monthIndex = createdAt.month - 1;
          monthlyKm[monthIndex] += r.distanceKm;
        } else if (!createdAt.isBefore(lastYearStart) &&
            createdAt.isBefore(lastYearEnd)) {
          lastYearKm += r.distanceKm;
          lastYearRoutes++;
        }

        // Streaktage
        driveDays.add(routeDay);
      }

      // Streak zählen
      int streak = 0;
      final today = DateTime(now.year, now.month, now.day);
      var checkDay = today;
      if (!driveDays.contains(checkDay)) {
        checkDay = checkDay.subtract(const Duration(days: 1));
      }
      while (driveDays.contains(checkDay)) {
        streak++;
        checkDay = checkDay.subtract(const Duration(days: 1));
      }

      // Normalisierung
      final maxXp = weeklyXp.reduce((a, b) => a > b ? a : b);
      final normalizedWeekly = weeklyXp
          .map((xp) => maxXp > 0 ? (xp / maxXp).clamp(0.0, 1.0) : 0.0)
          .toList();

      final maxMonthlyKm = monthlyKm.reduce((a, b) => a > b ? a : b);
      final normalizedMonthly = monthlyKm
          .map(
            (km) =>
                maxMonthlyKm > 0 ? (km / maxMonthlyKm).clamp(0.0, 1.0) : 0.0,
          )
          .toList();

      if (mounted) {
        setState(() {
          _totalRoutes = gamResult.totalRoutes;
          _totalDistanceKm = gamResult.totalDistanceKm;
          _totalHours = gamResult.totalHours;
          _totalXp = gamResult.totalXp;
          _level = gamResult.level;
          _earnedBadges = gamResult.earnedBadges;
          _allRoutes = routes;
          _weeklyChartData = normalizedWeekly;
          _weeklyRawKm = weeklyKm;
          _weeklyRawXp = weeklyXp;
          _streakDays = streak;
          _thisMonthKm = thisMonthKm;
          _lastMonthKm = lastMonthKm;
          _thisMonthRoutes = thisMonthRoutes;
          _lastMonthRoutes = lastMonthRoutes;
          _thisYearKm = thisYearKm;
          _lastYearKm = lastYearKm;
          _thisYearRoutes = thisYearRoutes;
          _lastYearRoutes = lastYearRoutes;
          _monthlyChartData = normalizedMonthly;
          _monthlyRawKm = monthlyKm;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Analytics] Daten laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF3B30)),
              )
            : RefreshIndicator(
                onRefresh: _loadData,
                color: const Color(0xFFFF3B30),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 10.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 20),
                        _buildLevelCard(),
                        const SizedBox(height: 12),
                        _buildStreakCard(),
                        const SizedBox(height: 16),
                        _buildStatsGrid(),
                        const SizedBox(height: 24),
                        if (_allRoutes.isNotEmpty) ...[
                          _buildRecentRoutesSection(),
                          const SizedBox(height: 24),
                        ],
                        _buildTabSection(),
                        const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Analytics',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Deine Fahr-Statistiken',
          style: TextStyle(fontSize: 14, color: Color(0xFFA0AEC0)),
        ),
      ],
    );
  }

  Widget _buildLevelCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '${_level.level}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _level.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '$_totalXp XP gesamt',
                      style: const TextStyle(
                        color: Color(0xFFA0AEC0),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(_level.progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _level.progress,
              backgroundColor: Colors.grey[800],
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFFF3B30),
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Noch ${_level.xpToNextLevel} XP bis Level ${_level.level + 1}',
            style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ── Streak Card ────────────────────────────────────────────────────────

  Widget _buildStreakCard() {
    final hasStreak = _streakDays > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasStreak
              ? const Color(0xFFFF3B30).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: hasStreak
                  ? const Color(0xFFFF3B30).withValues(alpha: 0.15)
                  : const Color(0xFF2D3748),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                hasStreak ? '🔥' : '❄️',
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasStreak
                      ? '$_streakDays Tage Streak'
                      : 'Kein aktiver Streak',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  hasStreak
                      ? 'Fahre heute um den Streak zu halten!'
                      : 'Starte eine Fahrt für deinen Streak',
                  style: const TextStyle(
                    color: Color(0xFFA0AEC0),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (hasStreak)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentRoutesSection() {
    final recentRoutes = _allRoutes.take(5).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Letzte Fahrten',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${recentRoutes.length} von $_totalRoutes',
                style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final route in recentRoutes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        route.styleEmoji,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          route.name ?? route.style,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${route.formattedDistance} · ${route.formattedDuration}',
                          style: const TextStyle(
                            color: Color(0xFFA0AEC0),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatDateShort(route.createdAt),
                    style: const TextStyle(
                      color: Color(0xFFA0AEC0),
                      fontSize: 11,
                    ),
                  ),
                  if (route.rating != null) ...[
                    const SizedBox(width: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.star,
                          color: Color(0xFFFFD700),
                          size: 14,
                        ),
                        Text(
                          '${route.rating}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatDateShort(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes} Min.';
    if (diff.inHours < 24) return '${diff.inHours} Std.';
    if (diff.inDays < 7) return '${diff.inDays} Tage';
    return '${date.day}.${date.month}.';
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildAnalyticsCard(
          'Fahrten',
          '$_totalRoutes',
          Icons.directions_car,
          const Color(0xFFFF3B30),
        ),
        _buildAnalyticsCard(
          'Distanz',
          _totalDistanceKm < 1
              ? '0 km'
              : '${_totalDistanceKm.toStringAsFixed(0)} km',
          Icons.map,
          const Color(0xFF00E5FF),
        ),
        _buildAnalyticsCard(
          'Fahrzeit',
          _totalHours < 1
              ? '${(_totalHours * 60).toStringAsFixed(0)} min'
              : '${_totalHours.toStringAsFixed(1)} h',
          Icons.timer,
          const Color(0xFFFFD700),
        ),
        _buildAnalyticsCard(
          'XP',
          '$_totalXp',
          Icons.bolt,
          const Color(0xFFB026FF),
        ),
      ],
    );
  }

  Widget _buildTabSection() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: const Color(0xFFFF3B30),
              borderRadius: BorderRadius.circular(12),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFFA0AEC0),
            labelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
            isScrollable: false,
            tabs: const [
              Tab(icon: Icon(Icons.insights, size: 16), text: 'Woche'),
              Tab(icon: Icon(Icons.calendar_month, size: 16), text: 'Monat'),
              Tab(icon: Icon(Icons.route, size: 16), text: 'Routen'),
              Tab(icon: Icon(Icons.emoji_events, size: 16), text: 'Badges'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(),
              _buildMonthlyTab(),
              _buildRoutesTab(),
              _buildBadgesTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTab() {
    final totalWeekKm = _weeklyRawKm.fold<double>(0, (a, b) => a + b);
    final totalWeekXp = _weeklyRawXp.fold<double>(0, (a, b) => a + b);
    final weekRoutes = _allRoutes.where((r) {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(
        Duration(days: todayStart.weekday - 1),
      );
      final routeDay = DateTime(
        r.createdAt.toLocal().year,
        r.createdAt.toLocal().month,
        r.createdAt.toLocal().day,
      );
      return !routeDay.isBefore(weekStart);
    }).length;

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1F26),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fahraktivität diese Woche',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Dein Wochenverlauf mit echten Tageswerten statt nur Balken.',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 170,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(
                      7,
                      (i) => _buildChartBar(
                        _weeklyLabels[i],
                        _weeklyChartData[i],
                        i == DateTime.now().weekday - 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildMiniMetricCard('Routen', '$weekRoutes', Icons.route),
                    _buildMiniMetricCard(
                      'Kilometer',
                      '${totalWeekKm.toStringAsFixed(0)} km',
                      Icons.straighten,
                    ),
                    _buildMiniMetricCard(
                      'XP',
                      totalWeekXp.toStringAsFixed(0),
                      Icons.bolt,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1F26),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tagesübersicht',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < 7; i++) ...[
                  _buildPeriodBreakdownRow(
                    label: _weeklyLabels[i],
                    value: '${_weeklyRawKm[i].toStringAsFixed(0)} km',
                    secondary: '${_weeklyRawXp[i].toStringAsFixed(0)} XP',
                    isHighlighted: i == DateTime.now().weekday - 1,
                  ),
                  if (i < 6) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Monats-/Jahresübersicht Tab ──────────────────────────────────────

  Widget _buildMonthlyTab() {
    final monthNames = [
      'Jan',
      'Feb',
      'Mär',
      'Apr',
      'Mai',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Okt',
      'Nov',
      'Dez',
    ];
    final now = DateTime.now();
    final currentMonthName = monthNames[now.month - 1];
    final lastMonthName = monthNames[(now.month - 2) % 12];

    final avgKmThisMonth = _thisMonthRoutes > 0
        ? _thisMonthKm / _thisMonthRoutes
        : 0.0;
    final avgKmLastMonth = _lastMonthRoutes > 0
        ? _lastMonthKm / _lastMonthRoutes
        : 0.0;

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildComparisonPanel(
            title: '$currentMonthName vs. $lastMonthName',
            icon: Icons.calendar_today,
            accentColor: const Color(0xFFFF3B30),
            tiles: [
              _buildStatTile(
                'Kilometer',
                '${_thisMonthKm.toStringAsFixed(0)} km',
                _lastMonthKm > 0
                    ? _thisMonthKm / _lastMonthKm - 1
                    : (_thisMonthKm > 0 ? 1.0 : 0.0),
              ),
              _buildStatTile(
                'Fahrten',
                '$_thisMonthRoutes',
                _lastMonthRoutes > 0
                    ? _thisMonthRoutes / _lastMonthRoutes - 1
                    : (_thisMonthRoutes > 0 ? 1.0 : 0.0),
              ),
              _buildStatTile(
                'Ø km/Fahrt',
                '${avgKmThisMonth.toStringAsFixed(1)} km',
                avgKmLastMonth > 0
                    ? avgKmThisMonth / avgKmLastMonth - 1
                    : (avgKmThisMonth > 0 ? 1.0 : 0.0),
              ),
            ],
          ),
          const SizedBox(height: 12),

          _buildComparisonPanel(
            title: '${now.year} vs. ${now.year - 1}',
            icon: Icons.date_range,
            accentColor: const Color(0xFF00E5FF),
            tiles: [
              _buildStatTile(
                'Kilometer',
                '${_thisYearKm.toStringAsFixed(0)} km',
                _lastYearKm > 0
                    ? _thisYearKm / _lastYearKm - 1
                    : (_thisYearKm > 0 ? 1.0 : 0.0),
              ),
              _buildStatTile(
                'Fahrten',
                '$_thisYearRoutes',
                _lastYearRoutes > 0
                    ? _thisYearRoutes / _lastYearRoutes - 1
                    : (_thisYearRoutes > 0 ? 1.0 : 0.0),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Monatliches Balkendiagramm ──
          Container(
            padding: const EdgeInsets.all(20),
            height: 220,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1F26),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Km pro Monat (${now.year})',
                  style: const TextStyle(
                    color: Color(0xFFA0AEC0),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(12, (i) {
                      final isCurrentMonth = i == now.month - 1;
                      return _buildChartBar(
                        monthNames[i],
                        _monthlyChartData[i],
                        isCurrentMonth,
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1F26),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Monat für Monat',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < 12; i++) ...[
                  _buildPeriodBreakdownRow(
                    label: monthNames[i],
                    value: '${_monthlyRawKm[i].toStringAsFixed(0)} km',
                    secondary: i == now.month - 1
                        ? 'Aktueller Monat'
                        : 'Monat ${i + 1}',
                    isHighlighted: i == now.month - 1,
                  ),
                  if (i < 11) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonPanel({
    required String title,
    required IconData icon,
    required Color accentColor,
    required List<Widget> tiles,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = tiles.length >= 3
                  ? (constraints.maxWidth - 20) / 3
                  : (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: tiles
                    .map((tile) => SizedBox(width: tileWidth, child: tile))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile(String label, String value, double changeRatio) {
    final pct = (changeRatio * 100).toStringAsFixed(0);
    final isPositive = changeRatio >= 0;
    final hasData = changeRatio != 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFA0AEC0),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 6),
          if (hasData)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color:
                    (isPositive
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEF4444))
                        .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPositive ? Icons.trending_up : Icons.trending_down,
                    color: isPositive
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444),
                    size: 12,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${isPositive ? '+' : ''}$pct%',
                    style: TextStyle(
                      color: isPositive
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFEF4444),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          else
            Text('—', style: TextStyle(color: Colors.grey[700], fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildMiniMetricCard(String label, String value, IconData icon) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFFFF3B30), size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFA0AEC0),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodBreakdownRow({
    required String label,
    required String value,
    required String secondary,
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isHighlighted
            ? const Color(0xFFFF3B30).withValues(alpha: 0.08)
            : const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHighlighted
              ? const Color(0xFFFF3B30).withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.04),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ),
          Text(
            secondary,
            style: TextStyle(color: Colors.grey[500], fontSize: 11),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutesTab() {
    if (_allRoutes.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: const Center(
          child: Text(
            'Noch keine Routen gefahren',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _allRoutes.length.clamp(0, 15),
        itemBuilder: (context, index) {
          final route = _allRoutes[index];
          final estimatedCurves = (route.distanceKm / 5).round();
          final routeXp = GamificationService.calculateRouteXp(
            distanceKm: route.distanceKm,
            curves: estimatedCurves,
            style: route.style,
          );

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0E14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B30).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      route.styleEmoji,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        route.name ?? route.style,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${route.formattedDistance} · ${route.formattedDuration} · $routeXp XP',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (route.rating != null)
                  Row(
                    children: [
                      const Icon(
                        Icons.star,
                        color: Color(0xFFFFD700),
                        size: 14,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${route.rating}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBadgesTab() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Badge Sammlung',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${_earnedBadges.length}/${app.Badge.all.length}',
                style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: app.Badge.all.isEmpty
                  ? 0
                  : _earnedBadges.length / app.Badge.all.length,
              backgroundColor: Colors.grey[800],
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFFF3B30),
              ),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.8,
              ),
              itemCount: app.Badge.all.length,
              itemBuilder: (context, index) {
                final badge = app.Badge.all[index];
                final earned = _earnedBadges.any((b) => b.id == badge.id);
                return Container(
                  decoration: BoxDecoration(
                    color: earned
                        ? const Color(0xFF2A2F3A)
                        : const Color(0xFF14171C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: earned
                          ? const Color(0xFFFF3B30).withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        badge.emoji,
                        style: TextStyle(
                          fontSize: 24,
                          color: earned
                              ? null
                              : Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        badge.name,
                        style: TextStyle(
                          color: earned
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.2),
                          fontSize: 8,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFA0AEC0),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartBar(String label, double value, bool isHighlighted) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                width: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D3748),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: value.clamp(0.0, 1.0),
                    child: Container(
                      width: 10,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isHighlighted
                              ? [
                                  const Color(0xFFFF3B30),
                                  const Color(0xFFFF6B5B),
                                ]
                              : [
                                  const Color(0xFF525252),
                                  const Color(0xFF3D3D3D),
                                ],
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
              label,
              style: TextStyle(
                color: isHighlighted
                    ? const Color(0xFFFF3B30)
                    : const Color(0xFFA0AEC0),
                fontSize: 9,
                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
