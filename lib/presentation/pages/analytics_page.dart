import 'package:flutter/material.dart';

import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key, this.refreshNotifier});

  /// Wird von HomePage inkrementiert, um einen Reload auszulösen.
  final ValueNotifier<int>? refreshNotifier;

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  bool _isLoading = true;
  int _totalRoutes = 0;
  double _totalDistanceKm = 0;
  double _totalHours = 0;
  List<app.Badge> _earnedBadges = [];
  List<SavedRoute> _recentRoutes = [];

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier?.addListener(_loadStats);
    _loadStats();
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_loadStats);
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final gamResult = await GamificationService.calculateAndSync();
      final routes = await SavedRoutesService.getUserRoutes();

      if (mounted) {
        setState(() {
          _totalRoutes = gamResult.totalRoutes;
          _totalDistanceKm = gamResult.totalDistanceKm;
          _totalHours = gamResult.totalHours;
          _earnedBadges = gamResult.earnedBadges;
          _recentRoutes = routes.take(7).toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Analytics",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(color: Color(0xFFFF3B30), strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.grey),
                    onPressed: _loadStats,
                  ),
              ],
            ),
            const SizedBox(height: 24),
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildAnalyticsCard("Fahrten", '$_totalRoutes', Icons.directions_car, const Color(0xFF00E5FF)),
                _buildAnalyticsCard(
                  "Distanz",
                  _totalDistanceKm < 1
                      ? '0 km'
                      : '${_totalDistanceKm.toStringAsFixed(0)} km',
                  Icons.map,
                  const Color(0xFF00FF66),
                ),
                _buildAnalyticsCard(
                  "Zeit",
                  _totalHours < 1
                      ? '${(_totalHours * 60).toStringAsFixed(0)} min'
                      : '${_totalHours.toStringAsFixed(1)} h',
                  Icons.timer,
                  const Color(0xFFFF9900),
                ),
                _buildAnalyticsCard("Badges", '${_earnedBadges.length}', Icons.emoji_events, const Color(0xFFB026FF)),
              ],
            ),
            const SizedBox(height: 24),

            // Badge Collection
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F26),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Badge Sammlung",
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_earnedBadges.length}/${app.Badge.all.length}',
                        style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_earnedBadges.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Fahre Routen um Badges zu verdienen!',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: app.Badge.all.map((badge) {
                        final earned = _earnedBadges.any((b) => b.id == badge.id);
                        return Tooltip(
                          message: '${badge.name}\n${badge.description}',
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  badge.emoji,
                                  style: TextStyle(
                                    fontSize: 22,
                                    color: earned ? null : Colors.white.withValues(alpha: 0.2),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  badge.name,
                                  style: TextStyle(
                                    color: earned ? Colors.white : Colors.white.withValues(alpha: 0.2),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F26),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha:0.05), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha:0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Letzte Routen",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  if (_recentRoutes.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Noch keine Routen gefahren',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ),
                    )
                  else
                    ..._recentRoutes.map((r) => _buildRouteRow(r)),
                ],
              ),
            ),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteRow(SavedRoute route) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.route, color: Color(0xFFFF3B30), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              route.name ?? 'Route',
              style: const TextStyle(color: Colors.white, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${route.formattedDistance} · ${route.formattedDuration}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsCard(String title, String value, IconData icon, Color neonColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha:0.05), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: neonColor.withValues(alpha:0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: neonColor, size: 28),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
