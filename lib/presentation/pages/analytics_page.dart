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
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(
      Duration(days: todayStart.weekday - 1),
    );
    final lastWeekStart = weekStart.subtract(const Duration(days: 7));
    final totalWeekKm = _weeklyRawKm.fold<double>(0, (a, b) => a + b);
    final totalWeekXp = _weeklyRawXp.fold<double>(0, (a, b) => a + b);
    final weekRoutes = _allRoutes.where((r) {
      final routeDay = DateTime(
        r.createdAt.toLocal().year,
        r.createdAt.toLocal().month,
        r.createdAt.toLocal().day,
      );
      return !routeDay.isBefore(weekStart);
    }).length;
    final activeDays = _weeklyRawKm.where((km) => km > 0).length;
    final avgKmPerRoute = weekRoutes > 0 ? totalWeekKm / weekRoutes : 0.0;

    double lastWeekKm = 0;
    double lastWeekXp = 0;
    var lastWeekRoutes = 0;
    for (final route in _allRoutes) {
      final routeDay = DateTime(
        route.createdAt.toLocal().year,
        route.createdAt.toLocal().month,
        route.createdAt.toLocal().day,
      );
      if (!routeDay.isBefore(lastWeekStart) && routeDay.isBefore(weekStart)) {
        lastWeekKm += route.distanceKm;
        lastWeekRoutes++;
        final estimatedCurves = (route.distanceKm / 5).round();
        lastWeekXp += GamificationService.calculateRouteXp(
          distanceKm: route.distanceKm,
          curves: estimatedCurves,
          style: route.style,
        );
      }
    }

    final weekKmDelta = totalWeekKm - lastWeekKm;
    final weekXpDelta = totalWeekXp - lastWeekXp;

    return Column(
      children: [
        _buildSectionCard(
          title: 'Fahraktivität diese Woche',
          subtitle: 'Kilometer pro Tag, kompakt mit Vorwochenvergleich.',
          accentColor: const Color(0xFFFF3B30),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final expanded = constraints.maxWidth >= 430;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _buildMiniMetricCard(
                        'Kilometer',
                        '${totalWeekKm.toStringAsFixed(0)} km',
                        Icons.straighten,
                        expanded: expanded,
                      ),
                      _buildMiniMetricCard(
                        'Fahrten',
                        '$weekRoutes',
                        Icons.route,
                        expanded: expanded,
                      ),
                      _buildMiniMetricCard(
                        'Fahrttage',
                        '$activeDays / 7',
                        Icons.calendar_today,
                        expanded: expanded,
                      ),
                      _buildMiniMetricCard(
                        'Ø km/Fahrt',
                        '${avgKmPerRoute.toStringAsFixed(1)} km',
                        Icons.speed,
                        expanded: expanded,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final pillWidth = constraints.maxWidth >= 560 ? 220.0 : 160.0;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _buildTrendPill(
                        width: pillWidth,
                        label: 'Vorwoche',
                        value:
                            '${lastWeekKm.toStringAsFixed(0)} km · $lastWeekRoutes Fahrten',
                        caption:
                            '${lastWeekXp.toStringAsFixed(0)} XP im gleichen Zeitraum',
                        accentColor: const Color(0xFF00E5FF),
                      ),
                      _buildTrendPill(
                        width: pillWidth,
                        label: 'Trend',
                        value: _formatSignedDistance(weekKmDelta),
                        caption:
                            '${_formatSignedNumber(weekXpDelta, suffix: ' XP')} vs. letzte Woche',
                        accentColor: weekKmDelta >= 0
                            ? const Color(0xFFFF3B30)
                            : const Color(0xFFA0AEC0),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 168,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(
                    7,
                    (i) => _buildChartBar(
                      _weeklyLabels[i],
                      _weeklyChartData[i],
                      i == now.weekday - 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Balken zeigen Kilometer pro Tag. XP stehen unten je Wochentag.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'Tagesübersicht',
          subtitle: 'Montag bis Sonntag mit Distanz und XP auf einen Blick.',
          accentColor: const Color(0xFF00E5FF),
          child: Column(
            children: [
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
    final lastMonthIndex = now.month == 1 ? 11 : now.month - 2;
    final lastMonthName = monthNames[lastMonthIndex];
    final lastMonthYear = now.month == 1 ? now.year - 1 : now.year;

    final avgKmThisMonth = _thisMonthRoutes > 0
        ? _thisMonthKm / _thisMonthRoutes
        : 0.0;
    final avgKmLastMonth = _lastMonthRoutes > 0
        ? _lastMonthKm / _lastMonthRoutes
        : 0.0;
    final monthDeltaKm = _thisMonthKm - _lastMonthKm;
    final oldYearAvg = _lastYearRoutes > 0
        ? _lastYearKm / _lastYearRoutes
        : 0.0;
    final currentYearAvg = _thisYearRoutes > 0
        ? _thisYearKm / _thisYearRoutes
        : 0.0;
    final yearDeltaKm = _thisYearKm - _lastYearKm;

    return Column(
      children: [
        _buildSectionCard(
          title: 'Monatsvergleich',
          subtitle: 'Vergangener Monat zuerst, aktueller Monat danach.',
          accentColor: const Color(0xFFFF3B30),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 560;
              return _buildComparisonLayout(
                leftTitle: '$lastMonthName $lastMonthYear',
                leftAccent: const Color(0xFF637082),
                leftMetrics: [
                  _buildComparisonMetric(
                    'Kilometer',
                    '${_lastMonthKm.toStringAsFixed(0)} km',
                  ),
                  _buildComparisonMetric('Fahrten', '$_lastMonthRoutes'),
                  _buildComparisonMetric(
                    'Ø km/Fahrt',
                    '${avgKmLastMonth.toStringAsFixed(1)} km',
                  ),
                ],
                rightTitle: '$currentMonthName ${now.year}',
                rightAccent: const Color(0xFFFF3B30),
                rightMetrics: [
                  _buildComparisonMetric(
                    'Kilometer',
                    '${_thisMonthKm.toStringAsFixed(0)} km',
                  ),
                  _buildComparisonMetric('Fahrten', '$_thisMonthRoutes'),
                  _buildComparisonMetric(
                    'Ø km/Fahrt',
                    '${avgKmThisMonth.toStringAsFixed(1)} km',
                  ),
                  _buildComparisonMetric(
                    'Delta',
                    _formatSignedDistance(monthDeltaKm),
                  ),
                ],
                stacked: stacked,
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'Jahresvergleich',
          subtitle: 'Vergangenes Jahr zuerst, aktuelles Jahr danach.',
          accentColor: const Color(0xFF00E5FF),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 560;
              return _buildComparisonLayout(
                leftTitle: '${now.year - 1}',
                leftAccent: const Color(0xFF637082),
                leftMetrics: [
                  _buildComparisonMetric(
                    'Kilometer',
                    '${_lastYearKm.toStringAsFixed(0)} km',
                  ),
                  _buildComparisonMetric('Fahrten', '$_lastYearRoutes'),
                  _buildComparisonMetric(
                    'Ø km/Fahrt',
                    '${oldYearAvg.toStringAsFixed(1)} km',
                  ),
                ],
                rightTitle: '${now.year}',
                rightAccent: const Color(0xFF00E5FF),
                rightMetrics: [
                  _buildComparisonMetric(
                    'Kilometer',
                    '${_thisYearKm.toStringAsFixed(0)} km',
                  ),
                  _buildComparisonMetric('Fahrten', '$_thisYearRoutes'),
                  _buildComparisonMetric(
                    'Ø km/Fahrt',
                    '${currentYearAvg.toStringAsFixed(1)} km',
                  ),
                  _buildComparisonMetric(
                    'Delta',
                    _formatSignedDistance(yearDeltaKm),
                  ),
                ],
                stacked: stacked,
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'Km pro Monat (${now.year})',
          subtitle: 'Monatliche Verteilung für das aktuelle Jahr.',
          accentColor: const Color(0xFFFFD700),
          child: Column(
            children: [
              SizedBox(
                height: 176,
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
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < 12; i++)
                    _buildMiniMonthCard(
                      monthNames[i],
                      '${_monthlyRawKm[i].toStringAsFixed(0)} km',
                      i == now.month - 1,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonLayout({
    required String leftTitle,
    required Color leftAccent,
    required List<Widget> leftMetrics,
    required String rightTitle,
    required Color rightAccent,
    required List<Widget> rightMetrics,
    required bool stacked,
  }) {
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildComparisonSide(
            title: leftTitle,
            accentColor: leftAccent,
            metrics: leftMetrics,
          ),
          const SizedBox(height: 12),
          _buildComparisonSide(
            title: rightTitle,
            accentColor: rightAccent,
            metrics: rightMetrics,
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildComparisonSide(
            title: leftTitle,
            accentColor: leftAccent,
            metrics: leftMetrics,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildComparisonSide(
            title: rightTitle,
            accentColor: rightAccent,
            metrics: rightMetrics,
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonSide({
    required String title,
    required Color accentColor,
    required List<Widget> metrics,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < metrics.length; i++) ...[
            metrics[i],
            if (i < metrics.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildComparisonMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF141922),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFA0AEC0),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
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

  Widget _buildMiniMetricCard(
    String label,
    String value,
    IconData icon, {
    bool expanded = true,
  }) {
    return Container(
      width: expanded ? 150 : 110,
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

  Widget _buildTrendPill({
    required double width,
    required String label,
    required String value,
    required String caption,
    required Color accentColor,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: accentColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMonthCard(String label, String value, bool isHighlighted) {
    return Container(
      width: 88,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: isHighlighted
            ? const Color(0xFFFFD700).withValues(alpha: 0.1)
            : const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHighlighted
              ? const Color(0xFFFFD700).withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.04),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isHighlighted ? const Color(0xFFFFD700) : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
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

  String _formatSignedDistance(double value) {
    final prefix = value >= 0 ? '+' : '-';
    return '$prefix${value.abs().toStringAsFixed(0)} km';
  }

  String _formatSignedNumber(double value, {String suffix = ''}) {
    final prefix = value >= 0 ? '+' : '-';
    return '$prefix${value.abs().toStringAsFixed(0)}$suffix';
  }
}
