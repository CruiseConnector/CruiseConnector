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
  final List<String> _weeklyLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  // Streak
  int _streakDays = 0;

  // Monats-/Jahresvergleich
  double _thisMonthKm = 0;
  double _lastMonthKm = 0;
  int _thisMonthRoutes = 0;
  // Wochendaten (neu)
  double _weeklyTotalKm = 0;
  double _weeklyTotalXp = 0;
  int _weeklyRouteCount = 0;
  double _weeklyTotalTime = 0; // Sekunden
  double _lastWeekTotalKm = 0;
  double _lastWeekTotalXp = 0;
  double _lastWeekTotalTime = 0; // Sekunden

  // Monatsdaten (neu)
  double _thisMonthXp = 0;
  double _lastMonthXp = 0;
  double _thisMonthTime = 0; // Sekunden
  double _lastMonthTime = 0; // Sekunden

  // Monatliche Chart-Daten (12 Monate)
  List<double> _monthlyChartData = List.filled(12, 0);
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted && !_tabController.indexIsChanging) {
        setState(() {});
      }
    });
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

      double thisMonthKm = 0, lastMonthKm = 0;
      int thisMonthRoutes = 0;

      // Neue Tracking-Variablen
      double weeklyTotalTime = 0, lastWeekTotalTime = 0;
      double lastWeekKm = 0, lastWeekXp = 0;
      int weekRouteCount = 0;
      double thisMonthXp = 0, lastMonthXp = 0;
      double thisMonthTime = 0, lastMonthTime = 0;
      final lastWeekStart = weekStart.subtract(const Duration(days: 7));

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

        final routeDuration = r.durationSeconds ?? 0.0;
        final estCurves = (r.distanceKm / 5).round();
        final routeXp = GamificationService.calculateRouteXp(
          distanceKm: r.distanceKm,
          curves: estCurves,
          style: r.style,
        );

        // Wöchentliche Daten
        if (!routeDay.isBefore(weekStart)) {
          final dayIndex = createdAt.weekday - 1;
          if (dayIndex >= 0 && dayIndex < 7) {
            weeklyKm[dayIndex] += r.distanceKm;
            weeklyXp[dayIndex] += routeXp;
          }
          weekRouteCount++;
          weeklyTotalTime += routeDuration;
        } else if (!routeDay.isBefore(lastWeekStart) &&
            routeDay.isBefore(weekStart)) {
          lastWeekKm += r.distanceKm;
          lastWeekXp += routeXp;
          lastWeekTotalTime += routeDuration;
        }

        // Monatsdaten
        if (!createdAt.isBefore(thisMonthStart)) {
          thisMonthKm += r.distanceKm;
          thisMonthRoutes++;
          thisMonthXp += routeXp;
          thisMonthTime += routeDuration;
        } else if (!createdAt.isBefore(lastMonthStart) &&
            createdAt.isBefore(thisMonthStart)) {
          lastMonthKm += r.distanceKm;
          lastMonthXp += routeXp;
          lastMonthTime += routeDuration;
        }

        // Monatliche Aufschlüsselung (dieses Jahr, für Chart)
        if (!createdAt.isBefore(thisYearStart)) {
          final monthIndex = createdAt.month - 1;
          monthlyKm[monthIndex] += r.distanceKm;
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
      final weeklyBarSource = weeklyKm.any((km) => km > 0)
          ? weeklyKm
          : weeklyXp;
      final maxWeeklyValue = weeklyBarSource.reduce((a, b) => a > b ? a : b);
      final normalizedWeekly = weeklyBarSource
          .map(
            (value) => maxWeeklyValue > 0
                ? (value / maxWeeklyValue).clamp(0.0, 1.0)
                : 0.0,
          )
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
          _streakDays = streak;
          _thisMonthKm = thisMonthKm;
          _lastMonthKm = lastMonthKm;
          _thisMonthRoutes = thisMonthRoutes;
          _monthlyChartData = normalizedMonthly;
          _weeklyTotalKm = weeklyKm.fold(0.0, (a, b) => a + b);
          _weeklyTotalXp = weeklyXp.fold(0.0, (a, b) => a + b);
          _weeklyRouteCount = weekRouteCount;
          _weeklyTotalTime = weeklyTotalTime;
          _lastWeekTotalKm = lastWeekKm;
          _lastWeekTotalXp = lastWeekXp;
          _lastWeekTotalTime = lastWeekTotalTime;
          _thisMonthXp = thisMonthXp;
          _lastMonthXp = lastMonthXp;
          _thisMonthTime = thisMonthTime;
          _lastMonthTime = lastMonthTime;
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
        _buildSelectedTabContent(),
      ],
    );
  }

  Widget _buildSelectedTabContent() {
    switch (_tabController.index) {
      case 0:
        return _buildOverviewTab();
      case 1:
        return _buildMonthlyTab();
      case 2:
        return _buildRoutesTab();
      case 3:
      default:
        return _buildBadgesTab();
    }
  }

  Widget _buildOverviewTab() {
    final now = DateTime.now();
    final kmDelta = _weeklyTotalKm - _lastWeekTotalKm;
    final xpDelta = _weeklyTotalXp - _lastWeekTotalXp;
    final timeDelta = _weeklyTotalTime - _lastWeekTotalTime;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Diese Woche',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'vs. letzte',
                style: TextStyle(
                  color: Color(0xFF8A94A6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // KPI Cards
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  value: _weeklyTotalKm < 10
                      ? '${_weeklyTotalKm.toStringAsFixed(1)} km'
                      : '${_weeklyTotalKm.toStringAsFixed(0)} km',
                  label: 'Distanz',
                  delta: _formatKpiDelta(kmDelta, suffix: ''),
                  deltaPositive: kmDelta >= 0,
                  deltaZero: kmDelta == 0,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildKpiCard(
                  value: _formatDurationShort(_weeklyTotalTime),
                  label: 'Fahrzeit',
                  delta: _formatTimeDelta(timeDelta),
                  deltaPositive: timeDelta >= 0,
                  deltaZero: timeDelta == 0,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildKpiCard(
                  value: _weeklyTotalXp.toStringAsFixed(0),
                  label: 'XP',
                  delta: _formatKpiDelta(xpDelta, suffix: ''),
                  deltaPositive: xpDelta >= 0,
                  deltaZero: xpDelta == 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Mini bar chart + route count
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 60,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(7, (i) {
                      final isToday = i == now.weekday - 1;
                      final barValue = _weeklyChartData[i].clamp(0.0, 1.0);
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor:
                                        barValue > 0 ? barValue : 0.06,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: isToday
                                            ? const LinearGradient(
                                                colors: [
                                                  Color(0xFFFF3B30),
                                                  Color(0xFFFF6B35),
                                                ],
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                              )
                                            : null,
                                        color: isToday
                                            ? null
                                            : const Color(0xFF2A2F3A),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _weeklyLabels[i],
                                style: TextStyle(
                                  color: isToday
                                      ? Colors.white
                                      : const Color(0xFF8A94A6),
                                  fontSize: 9,
                                  fontWeight: isToday
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                '$_weeklyRouteCount Fahrten',
                style: const TextStyle(
                  color: Color(0xFF8A94A6),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Streak line
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: _streakDays > 0
                        ? (_streakDays / 7).clamp(0.0, 1.0)
                        : 0.0,
                    backgroundColor: const Color(0xFF2A2F3A),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFFF3B30),
                    ),
                    minHeight: 3,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _streakDays > 0
                    ? '\u{1F525} $_streakDays Tage Streak'
                    : 'Kein Streak',
                style: TextStyle(
                  color: _streakDays > 0
                      ? Colors.white
                      : const Color(0xFF8A94A6),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Monats-/Jahresübersicht Tab ──────────────────────────────────────

  Widget _buildMonthlyTab() {
    const monthLabels = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    final now = DateTime.now();
    final kmDelta = _thisMonthKm - _lastMonthKm;
    final xpDelta = _thisMonthXp - _lastMonthXp;
    final timeDelta = _thisMonthTime - _lastMonthTime;
    final avgKmPerRoute = _thisMonthRoutes > 0
        ? _thisMonthKm / _thisMonthRoutes
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dieser Monat',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'vs. letzter',
                style: TextStyle(
                  color: Color(0xFF8A94A6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // KPI Cards
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  value: _thisMonthKm < 10
                      ? '${_thisMonthKm.toStringAsFixed(1)} km'
                      : '${_thisMonthKm.toStringAsFixed(0)} km',
                  label: 'Distanz',
                  delta: _formatKpiDelta(kmDelta, suffix: ''),
                  deltaPositive: kmDelta >= 0,
                  deltaZero: kmDelta == 0,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildKpiCard(
                  value: _formatDurationShort(_thisMonthTime),
                  label: 'Fahrzeit',
                  delta: _formatTimeDelta(timeDelta),
                  deltaPositive: timeDelta >= 0,
                  deltaZero: timeDelta == 0,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildKpiCard(
                  value: _thisMonthXp >= 1000
                      ? '${(_thisMonthXp / 1000).toStringAsFixed(1)}k'
                      : _thisMonthXp.toStringAsFixed(0),
                  label: 'XP',
                  delta: _formatKpiDelta(xpDelta, suffix: ''),
                  deltaPositive: xpDelta >= 0,
                  deltaZero: xpDelta == 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Summary line
          Row(
            children: [
              Text(
                '$_thisMonthRoutes Fahrten',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Text(
                '  \u00b7  ',
                style: TextStyle(color: Color(0xFF8A94A6), fontSize: 13),
              ),
              Text(
                '\u00d8 ${avgKmPerRoute.toStringAsFixed(1)} km/Fahrt',
                style: const TextStyle(
                  color: Color(0xFF8A94A6),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Yearly mini chart (12 bars)
          SizedBox(
            height: 50,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(12, (i) {
                final isCurrentMonth = i == now.month - 1;
                final barValue = _monthlyChartData[i].clamp(0.0, 1.0);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: barValue > 0 ? barValue : 0.06,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: isCurrentMonth
                                      ? const LinearGradient(
                                          colors: [
                                            Color(0xFFFF3B30),
                                            Color(0xFFFF6B35),
                                          ],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        )
                                      : null,
                                  color: isCurrentMonth
                                      ? null
                                      : const Color(0xFF2A2F3A),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          monthLabels[i],
                          style: TextStyle(
                            color: isCurrentMonth
                                ? Colors.white
                                : const Color(0xFF8A94A6),
                            fontSize: 8,
                            fontWeight: isCurrentMonth
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── KPI Card (shared by Week + Month) ──────────────────────────────

  Widget _buildKpiCard({
    required String value,
    required String label,
    required String delta,
    required bool deltaPositive,
    required bool deltaZero,
  }) {
    final deltaColor = deltaZero
        ? const Color(0xFF8A94A6)
        : deltaPositive
            ? const Color(0xFF4ADE80)
            : const Color(0xFFFF6B6B);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF252A33),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8A94A6),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            delta,
            style: TextStyle(
              color: deltaColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Format helpers ─────────────────────────────────────────────────

  String _formatDurationShort(double seconds) {
    final totalMinutes = (seconds / 60).round();
    if (totalMinutes < 60) return '${totalMinutes}m';
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  String _formatKpiDelta(double delta, {String suffix = ''}) {
    if (delta == 0) return '\u00b10$suffix';
    final prefix = delta > 0 ? '+' : '';
    return '$prefix${delta.toStringAsFixed(delta.abs() >= 10 ? 0 : 1)}$suffix';
  }

  String _formatTimeDelta(double deltaSeconds) {
    if (deltaSeconds == 0) return '\u00b10:00';
    final prefix = deltaSeconds > 0 ? '+' : '-';
    final abs = deltaSeconds.abs();
    final totalMinutes = (abs / 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '$prefix$h:${m.toString().padLeft(2, '0')}';
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required Color accentColor,
    required Widget child,
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
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    border: Border.all(color: accentColor, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFFA0AEC0),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildRoutesTab() {
    if (_allRoutes.isEmpty) {
      return _buildSectionCard(
        title: 'Routen',
        subtitle: 'Noch keine Routen gefahren.',
        accentColor: const Color(0xFFFF3B30),
        child: const Text(
          'Sobald du Routen fährst, erscheinen sie hier in einer kompakten Übersicht.',
          style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
        ),
      );
    }

    return _buildSectionCard(
      title: 'Routen',
      subtitle: 'Die letzten gefahrenen Routen als kompakte Liste.',
      accentColor: const Color(0xFFFF3B30),
      child: Column(
        children: [
          for (var i = 0; i < _allRoutes.take(10).length; i++) ...[
            _buildRouteSummaryRow(_allRoutes[i]),
            if (i < _allRoutes.take(10).length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildBadgesTab() {
    return _buildSectionCard(
      title: 'Badge Sammlung',
      subtitle:
          '${_earnedBadges.length}/${app.Badge.all.length} freigeschaltet.',
      accentColor: const Color(0xFFFFD700),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 700
                  ? 4
                  : constraints.maxWidth >= 500
                  ? 3
                  : 2;
              final cardWidth =
                  (constraints.maxWidth - (crossAxisCount - 1) * 8) /
                  crossAxisCount;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final badge in app.Badge.all)
                    SizedBox(width: cardWidth, child: _buildBadgeTile(badge)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRouteSummaryRow(SavedRoute route) {
    final estimatedCurves = (route.distanceKm / 5).round();
    final routeXp = GamificationService.calculateRouteXp(
      distanceKm: route.distanceKm,
      curves: estimatedCurves,
      style: route.style,
    );

    return Container(
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
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          if (route.rating != null)
            Row(
              children: [
                const Icon(Icons.star, color: Color(0xFFFFD700), size: 14),
                const SizedBox(width: 2),
                Text(
                  '${route.rating}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBadgeTile(app.Badge badge) {
    final earned = _earnedBadges.any((b) => b.id == badge.id);
    return Container(
      decoration: BoxDecoration(
        color: earned ? const Color(0xFF2A2F3A) : const Color(0xFF14171C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: earned
              ? const Color(0xFFFF3B30).withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              badge.emoji,
              style: TextStyle(
                fontSize: 24,
                color: earned ? null : Colors.white.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              badge.name,
              style: TextStyle(
                color: earned
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.2),
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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

}
