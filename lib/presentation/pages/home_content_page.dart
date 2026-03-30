import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
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
    if (widget.refreshKey != old.refreshKey && widget.refreshKey > 0) {
      _loadStats();
    }
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
  SavedRoute? _weeklyTopRoute;
  bool _isRouteSaved = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final result = await GamificationService.calculateAndSync();
      final routes = await SavedRoutesService.getUserRoutes();
      final rideRoutes = routes
          .where((route) => route.isDrivenSession)
          .toList();

      // Wöchentliche Daten berechnen
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(
        Duration(days: todayStart.weekday - 1),
      );
      final weeklyKm = List<double>.filled(7, 0);
      for (final r in rideRoutes) {
        final localCreatedAt = r.createdAt.toLocal();
        final routeDay = DateTime(
          localCreatedAt.year,
          localCreatedAt.month,
          localCreatedAt.day,
        );
        if (!routeDay.isBefore(weekStart)) {
          final dayIndex = routeDay.weekday - 1;
          if (dayIndex >= 0 && dayIndex < 7) {
            weeklyKm[dayIndex] += r.actualDistanceKm;
          }
        }
      }
      final maxKm = weeklyKm.fold<double>(0, (a, b) => a > b ? a : b);
      final normalized = weeklyKm
          .map((km) => maxKm > 0 ? (km / maxKm).clamp(0.0, 1.0) : 0.0)
          .toList();

      // Streak berechnen (Tage in Folge gefahren)
      int streak = 0;
      if (rideRoutes.isNotEmpty) {
        final today = DateTime(now.year, now.month, now.day);
        final driveDays = <DateTime>{};
        for (final r in rideRoutes) {
          final localCreatedAt = r.createdAt.toLocal();
          driveDays.add(
            DateTime(
              localCreatedAt.year,
              localCreatedAt.month,
              localCreatedAt.day,
            ),
          );
        }
        var checkDay = today;
        if (!driveDays.contains(checkDay)) {
          checkDay = checkDay.subtract(const Duration(days: 1));
        }
        while (driveDays.contains(checkDay)) {
          streak++;
          checkDay = checkDay.subtract(const Duration(days: 1));
        }
      }

      // Wöchentliche Top-Route laden
      SavedRoute? topRoute;
      bool routeSaved = false;
      try {
        // Standort ermitteln
        double userLat = 50.1109; // Fallback: Frankfurt
        double userLng = 8.6821;
        try {
          final permission = await geo.Geolocator.checkPermission();
          final hasPermission =
              permission == geo.LocationPermission.always ||
              permission == geo.LocationPermission.whileInUse;
          if (!hasPermission) {
            await geo.Geolocator.requestPermission();
          }
          final pos = await geo.Geolocator.getCurrentPosition(
            locationSettings: const geo.LocationSettings(
              accuracy: geo.LocationAccuracy.low,
              timeLimit: Duration(seconds: 5),
            ),
          );
          userLat = pos.latitude;
          userLng = pos.longitude;
        } catch (e) {
          debugPrint('[Home] Standort nicht verfügbar, nutze Fallback: $e');
        }

        topRoute = await SavedRoutesService.getWeeklyTopRoute(
          userLat: userLat,
          userLng: userLng,
        );

        // Prüfen ob Route bereits gespeichert
        if (topRoute != null) {
          routeSaved = SavedRoutesService.hasEquivalentSavedRoute(
            topRoute,
            routes,
          );
        }
      } catch (e) {
        debugPrint('[Home] Top-Route laden fehlgeschlagen: $e');
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
          _weeklyTopRoute = topRoute;
          _isRouteSaved = routeSaved;
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
    final String userName =
        (user?.userMetadata?['username'] as String?) ??
        user?.email?.split('@')[0] ??
        'User';

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
                border: Border.all(
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fortschritt',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _loading
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFFF3B30),
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _statRow('⚡', '$totalXp XP gesamt'),
                            const SizedBox(height: 6),
                            _statRow(
                              '🏎️',
                              '${totalDistanceKm.toStringAsFixed(0)} Km gefahren',
                            ),
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
            const SizedBox(height: 16),

            // Top-Strecke dieser Woche
            if (_weeklyTopRoute != null)
              _buildHeroRouteCard(_weeklyTopRoute!)
            else if (!_loading)
              _buildEmptyRecommendation()
            else
              const SizedBox(
                height: 200,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFF3B30),
                    ),
                  ),
                ),
              ),
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
                        border: Border.all(
                          color: const Color(
                            0xFFFFFFFF,
                          ).withValues(alpha: 0.06),
                          width: 1,
                        ),
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
                          _buildCommunityItem(
                            '$totalRoutes Fahrten absolviert',
                            '🔥',
                          ),
                          const SizedBox(height: 4),
                          _buildCommunityItem(
                            'Level $userLevel - $levelName',
                            '📍',
                          ),
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
                                    colors: [
                                      Color(0xFFFF5252),
                                      Color(0xFFD32F2F),
                                    ],
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
                        border: Border.all(
                          color: const Color(
                            0xFFFFFFFF,
                          ).withValues(alpha: 0.06),
                          width: 1,
                        ),
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
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
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

  // ── Hero Route Card (wöchentliche Top-Strecke) ──────────────────────────

  Widget _buildHeroRouteCard(SavedRoute route) {
    // Gradient-Farben basierend auf Stil
    final gradientColors = switch (route.style) {
      'Kurvenjagd' => [const Color(0xFF1B5E20), const Color(0xFF388E3C)],
      'Sport Mode' => [const Color(0xFFB71C1C), const Color(0xFFD32F2F)],
      'Abendrunde' => [const Color(0xFF1A237E), const Color(0xFF3949AB)],
      'Entdecker' => [const Color(0xFFE65100), const Color(0xFFFB8C00)],
      _ => [const Color(0xFFB71C1C), const Color(0xFFE65100)],
    };

    // Koordinaten aus Geometrie extrahieren
    List<List<double>> coordinates = [];
    try {
      final coords = route.geometry['coordinates'];
      if (coords is List) {
        for (final c in coords) {
          if (c is List && c.length >= 2) {
            coordinates.add([
              (c[0] as num).toDouble(),
              (c[1] as num).toDouble(),
            ]);
          }
        }
      }
    } catch (_) {}

    final ratingValue = route.rating?.toDouble() ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header mit Gold-Akzent
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('🏆', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Top-Strecke dieser Woche',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Route Visual mit Polyline
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradientColors,
                  ),
                ),
                child: coordinates.length >= 2
                    ? CustomPaint(
                        painter: _RoutePolylinePainter(
                          coordinates: coordinates,
                        ),
                        size: const Size(double.infinity, 180),
                      )
                    : Center(
                        child: Text(
                          route.styleEmoji,
                          style: const TextStyle(fontSize: 64),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Route Name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              route.name ?? '${route.styleEmoji} ${route.style}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),

          // Rating + Subtitle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                // Sterne
                ...List.generate(5, (i) {
                  return Icon(
                    i < ratingValue.floor()
                        ? Icons.star
                        : (i < ratingValue
                              ? Icons.star_half
                              : Icons.star_border),
                    color: const Color(0xFFFFD700),
                    size: 18,
                  );
                }),
                const SizedBox(width: 8),
                Text(
                  ratingValue > 0 ? ratingValue.toStringAsFixed(1) : '--',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  '·',
                  style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 14),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Top bewertet diese Woche',
                    style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Metric Pills
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _buildMetricPill(route.formattedDistance, 'Distanz'),
                const SizedBox(width: 10),
                _buildMetricPill(route.formattedDuration, 'Dauer'),
                const SizedBox(width: 10),
                _buildMetricPill(
                  route.isRoundTrip ? 'Rundkurs' : 'A nach B',
                  'Typ',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                // Route fahren Button
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      CruiseModePage.pendingRoute.value = route;
                      widget.onTabChange?.call(2);
                    },
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.directions_car,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Route fahren',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Speichern Button
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      if (_isRouteSaved) return;
                      try {
                        await SavedRoutesService.saveExistingRoute(route);
                        if (mounted) {
                          setState(() => _isRouteSaved = true);
                        }
                      } catch (e) {
                        debugPrint('[Home] Route speichern fehlgeschlagen: $e');
                      }
                    },
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _isRouteSaved
                              ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                              : const Color(0xFFFFFFFF).withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isRouteSaved
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            color: _isRouteSaved
                                ? const Color(0xFFFFD700)
                                : const Color(0xFFA0AEC0),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isRouteSaved ? 'Gespeichert' : 'Speichern',
                            style: TextStyle(
                              color: _isRouteSaved
                                  ? const Color(0xFFFFD700)
                                  : const Color(0xFFA0AEC0),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricPill(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0E14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyRecommendation() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.explore_outlined,
              color: Color(0xFFFFD700),
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Noch keine Top-Strecke in deiner Nähe diese Woche',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Starte eine Fahrt und bewerte sie, um Empfehlungen zu erhalten',
            style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
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
                  hasStreak
                      ? '$_streakDays Tage Streak'
                      : 'Kein aktiver Streak',
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
                  style: const TextStyle(
                    color: Color(0xFFA0AEC0),
                    fontSize: 12,
                  ),
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
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildCommunityItem(String text, String emoji) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 11),
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

// ── CustomPainter für Route-Polyline auf dem Gradient-Hintergrund ──────────

class _RoutePolylinePainter extends CustomPainter {
  final List<List<double>> coordinates;

  _RoutePolylinePainter({required this.coordinates});

  @override
  void paint(Canvas canvas, Size size) {
    if (coordinates.length < 2) return;

    // Bounding Box berechnen
    double minLon = double.infinity, maxLon = -double.infinity;
    double minLat = double.infinity, maxLat = -double.infinity;
    for (final c in coordinates) {
      if (c[0] < minLon) minLon = c[0];
      if (c[0] > maxLon) maxLon = c[0];
      if (c[1] < minLat) minLat = c[1];
      if (c[1] > maxLat) maxLat = c[1];
    }

    final lonRange = maxLon - minLon;
    final latRange = maxLat - minLat;
    if (lonRange == 0 && latRange == 0) return;

    // Padding
    const padding = 24.0;
    final drawWidth = size.width - padding * 2;
    final drawHeight = size.height - padding * 2;

    // Skalierung mit Aspect Ratio beibehalten
    final scaleX = lonRange > 0 ? drawWidth / lonRange : 1.0;
    final scaleY = latRange > 0 ? drawHeight / latRange : 1.0;
    final scale = math.min(scaleX, scaleY);

    final offsetX = padding + (drawWidth - lonRange * scale) / 2;
    final offsetY = padding + (drawHeight - latRange * scale) / 2;

    // Punkte normalisieren
    final points = coordinates.map((c) {
      final x = offsetX + (c[0] - minLon) * scale;
      // Y invertieren (Lat steigt nach oben, Canvas nach unten)
      final y = offsetY + (maxLat - c[1]) * scale;
      return Offset(x, y);
    }).toList();

    // Glow-Effekt zeichnen
    final glowPaint = Paint()
      ..color = const Color(0xFFFF5252).withValues(alpha: 0.3)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, glowPaint);

    // Haupt-Linie zeichnen
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, linePaint);

    // Start-Punkt
    final startDotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(points.first, 5, startDotPaint);

    // End-Punkt
    final endDotPaint = Paint()..color = const Color(0xFFFFD700);
    canvas.drawCircle(points.last, 5, endDotPaint);
  }

  @override
  bool shouldRepaint(covariant _RoutePolylinePainter oldDelegate) {
    return oldDelegate.coordinates != coordinates;
  }
}
