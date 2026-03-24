import 'package:flutter/material.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/domain/models/user_level.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> with SingleTickerProviderStateMixin {
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
  final List<String> _weeklyLabels = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
      final maxKm = weeklyKm.reduce((a, b) => a > b ? a : b);
      final normalizedWeekly = weeklyKm
          .map((km) => maxKm > 0 ? (km / maxKm).clamp(0.0, 1.0) : 0.0)
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
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30)))
            : RefreshIndicator(
                onRefresh: _loadData,
                color: const Color(0xFFFF3B30),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 20),
                        _buildLevelCard(),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Analytics", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
            SizedBox(height: 4),
            Text("Deine Fahr-Statistiken", style: TextStyle(fontSize: 14, color: Color(0xFFA0AEC0))),
          ],
        ),
        IconButton(icon: const Icon(Icons.refresh, color: Colors.grey), onPressed: _loadData),
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
                  gradient: const LinearGradient(colors: [Color(0xFFFF5252), Color(0xFFD32F2F)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text('${_level.level}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_level.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('$_totalXp XP gesamt', style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 12)),
                  ],
                ),
              ),
              Text(
                '${(_level.progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _level.progress,
              backgroundColor: Colors.grey[800],
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF3B30)),
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
              const Text('Letzte Fahrten', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Text('${recentRoutes.length} von $_totalRoutes', style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          for (final route in recentRoutes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(child: Text(route.styleEmoji, style: const TextStyle(fontSize: 16))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(route.name ?? route.style, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(
                          '${route.formattedDistance} · ${route.formattedDuration}',
                          style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatDateShort(route.createdAt),
                    style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 11),
                  ),
                  if (route.rating != null) ...[
                    const SizedBox(width: 8),
                    Row(children: [
                      const Icon(Icons.star, color: Color(0xFFFFD700), size: 14),
                      Text('${route.rating}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ]),
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
        _buildAnalyticsCard("Fahrten", '$_totalRoutes', Icons.directions_car, const Color(0xFFFF3B30)),
        _buildAnalyticsCard("Distanz", _totalDistanceKm < 1 ? '0 km' : '${_totalDistanceKm.toStringAsFixed(0)} km', Icons.map, const Color(0xFF00E5FF)),
        _buildAnalyticsCard("Fahrzeit", _totalHours < 1 ? '${(_totalHours * 60).toStringAsFixed(0)} min' : '${_totalHours.toStringAsFixed(1)} h', Icons.timer, const Color(0xFFFFD700)),
        _buildAnalyticsCard("XP", '$_totalXp', Icons.bolt, const Color(0xFFB026FF)),
      ],
    );
  }

  Widget _buildTabSection() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(color: const Color(0xFF1C1F26), borderRadius: BorderRadius.circular(16)),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(color: const Color(0xFFFF3B30), borderRadius: BorderRadius.circular(12)),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFFA0AEC0),
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            tabs: const [
              Tab(icon: Icon(Icons.insights, size: 18), text: "Woche"),
              Tab(icon: Icon(Icons.route, size: 18), text: "Routen"),
              Tab(icon: Icon(Icons.emoji_events, size: 18), text: "Badges"),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 420,
          child: TabBarView(
            controller: _tabController,
            children: [_buildOverviewTab(), _buildRoutesTab(), _buildBadgesTab()],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTab() {
    final totalWeekKm = _weeklyRawKm.fold<double>(0, (a, b) => a + b);
    final weekRoutes = _allRoutes.where((r) {
      final weekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
      return r.createdAt.isAfter(weekStart);
    }).length;

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
          const Text("Fahraktivität diese Woche", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) => _buildChartBar(_weeklyLabels[i], _weeklyChartData[i], i == DateTime.now().weekday - 1)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem("Routen", '$weekRoutes', Icons.route),
              _buildSummaryItem("Km", totalWeekKm.toStringAsFixed(0), Icons.straighten),
              _buildSummaryItem("Badges", '${_earnedBadges.length}/${app.Badge.all.length}', Icons.emoji_events),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(children: [
      Icon(icon, color: const Color(0xFFFF3B30), size: 18),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      Text(label, style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 11)),
    ]);
  }

  Widget _buildRoutesTab() {
    if (_allRoutes.isEmpty) {
      return Container(
        decoration: BoxDecoration(color: const Color(0xFF1C1F26), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
        child: const Center(child: Text('Noch keine Routen gefahren', style: TextStyle(color: Colors.grey))),
      );
    }

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1C1F26), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _allRoutes.length.clamp(0, 15),
        itemBuilder: (context, index) {
          final route = _allRoutes[index];
          // XP für diese Route berechnen
          final estimatedCurves = (route.distanceKm / 5).round();
          final routeXp = GamificationService.calculateRouteXp(
            distanceKm: route.distanceKm,
            curves: estimatedCurves,
            style: route.style,
          );

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF0B0E14), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: const Color(0xFFFF3B30).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text(route.styleEmoji, style: const TextStyle(fontSize: 16))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(route.name ?? route.style, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text('${route.formattedDistance} · ${route.formattedDuration} · $routeXp XP', style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ])),
              if (route.rating != null)
                Row(children: [
                  const Icon(Icons.star, color: Color(0xFFFFD700), size: 14),
                  const SizedBox(width: 2),
                  Text('${route.rating}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ]),
            ]),
          );
        },
      ),
    );
  }

  Widget _buildBadgesTab() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1C1F26), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Badge Sammlung", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          Text('${_earnedBadges.length}/${app.Badge.all.length}', style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 13)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: app.Badge.all.isEmpty ? 0 : _earnedBadges.length / app.Badge.all.length,
            backgroundColor: Colors.grey[800],
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF3B30)),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.8),
            itemCount: app.Badge.all.length,
            itemBuilder: (context, index) {
              final badge = app.Badge.all[index];
              final earned = _earnedBadges.any((b) => b.id == badge.id);
              return Container(
                decoration: BoxDecoration(
                  color: earned ? const Color(0xFF2A2F3A) : const Color(0xFF14171C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: earned ? const Color(0xFFFF3B30).withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.05)),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(badge.emoji, style: TextStyle(fontSize: 24, color: earned ? null : Colors.white.withValues(alpha: 0.15))),
                  const SizedBox(height: 4),
                  Text(badge.name, style: TextStyle(color: earned ? Colors.white : Colors.white.withValues(alpha: 0.2), fontSize: 8, fontWeight: FontWeight.w500), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildAnalyticsCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1C1F26), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 24),
        ),
        const Spacer(),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 13, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildChartBar(String label, double value, bool isHighlighted) {
    return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      Container(
        width: 10, height: 140,
        decoration: BoxDecoration(color: const Color(0xFF2D3748), borderRadius: BorderRadius.circular(6)),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 10, height: 140 * value.clamp(0.0, 1.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isHighlighted ? [const Color(0xFFFF3B30), const Color(0xFFFF6B5B)] : [const Color(0xFF525252), const Color(0xFF3D3D3D)],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: TextStyle(color: isHighlighted ? const Color(0xFFFF3B30) : const Color(0xFFA0AEC0), fontSize: 10, fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal)),
    ]);
  }
}
