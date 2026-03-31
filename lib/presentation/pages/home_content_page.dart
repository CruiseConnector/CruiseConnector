import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/route_elevation_service.dart';
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

class _HomeContentPageState extends State<HomeContentPage>
    with SingleTickerProviderStateMixin {
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
  final Map<String, _HeroRouteInsights> _heroInsightsByRouteId = {};
  final Set<String> _heroInsightsLoading = <String>{};
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _loadStats();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
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

      if (topRoute != null) {
        unawaited(_ensureHeroRouteInsights(topRoute));
      }
    } catch (e) {
      debugPrint('[Home] Daten laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ensureHeroRouteInsights(SavedRoute route) async {
    if (_heroInsightsByRouteId.containsKey(route.id) ||
        _heroInsightsLoading.contains(route.id)) {
      return;
    }

    final coordinates = _extractCoordinates(route.geometry);
    if (coordinates.length < 2) return;

    if (mounted) {
      setState(() {
        _heroInsightsLoading.add(route.id);
      });
    } else {
      _heroInsightsLoading.add(route.id);
    }

    try {
      final curves = await GamificationService.countCurvesAsync(coordinates);
      final xp = GamificationService.calculateRouteXp(
        distanceKm: route.distanceKm,
        curves: curves,
        style: route.style,
      );
      final elevationSummary = await const RouteElevationService().getSummary(
        routeKey: route.id,
        coordinates: coordinates,
      );

      if (!mounted) return;
      setState(() {
        _heroInsightsByRouteId[route.id] = _HeroRouteInsights(
          curves: curves,
          xp: xp,
          elevation: elevationSummary,
        );
        _heroInsightsLoading.remove(route.id);
      });
    } catch (e) {
      debugPrint('[Home] Hero-Insights fehlgeschlagen: $e');
      if (!mounted) return;
      setState(() {
        _heroInsightsLoading.remove(route.id);
      });
    }
  }

  List<List<double>> _extractCoordinates(Map<String, dynamic> geometry) {
    final extracted = <List<double>>[];
    try {
      final coords = geometry['coordinates'];
      if (coords is List) {
        for (final point in coords) {
          if (point is List && point.length >= 2) {
            extracted.add([
              (point[0] as num).toDouble(),
              (point[1] as num).toDouble(),
            ]);
          }
        }
      }
    } catch (_) {
      return const [];
    }
    return extracted;
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
            _buildSuggestedRouteSection(),
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

  Widget _buildSuggestedRouteSection() {
    if (_weeklyTopRoute != null) {
      final cardWidth = math.max(MediaQuery.of(context).size.width - 40, 680);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: SizedBox(
          width: cardWidth.toDouble(),
          child: _buildSuggestedRouteCard(_weeklyTopRoute!),
        ),
      );
    }

    if (_loading) {
      final cardWidth = math.max(MediaQuery.of(context).size.width - 40, 680);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: SizedBox(
          width: cardWidth.toDouble(),
          child: _buildSuggestedRouteSkeleton(),
        ),
      );
    }

    return _buildEmptyRecommendation();
  }

  Widget _buildSuggestedRouteCard(SavedRoute route) {
    final coordinates = _extractCoordinates(route.geometry);
    final heroInsights = _heroInsightsByRouteId[route.id];
    final isLoadingInsights = _heroInsightsLoading.contains(route.id);
    final ratingValue = route.rating?.toDouble();
    final title = (route.name?.trim().isNotEmpty ?? false)
        ? route.name!.trim()
        : '${route.styleEmoji} ${route.style}';
    final climbMeters = heroInsights?.elevation?.ascentMeters;
    final routeTypeLabel = route.isRoundTrip ? 'Rundkurs' : 'A nach B';

    return Container(
      height: 234,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: const Color(0xFFFF3B30)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                child: Row(
                  children: [
                    Expanded(
                      flex: 7,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'VORGESCHLAGENE ROUTE',
                            style: TextStyle(
                              color: Color(0xFFFF3B30),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${route.formattedDistance} • ${route.formattedDuration}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.76),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildSuggestedMetric(
                                icon: Icons.route_rounded,
                                label: route.formattedDistance,
                              ),
                              _buildSuggestedMetric(
                                icon: Icons.schedule_rounded,
                                label: route.formattedDuration,
                              ),
                              _buildSuggestedMetric(
                                icon: Icons.turn_slight_right_rounded,
                                label: heroInsights != null
                                    ? '${heroInsights.curves} Kurven'
                                    : isLoadingInsights
                                    ? 'Kurven ...'
                                    : 'Kurven --',
                              ),
                              _buildSuggestedMetric(
                                icon: Icons.bolt_rounded,
                                label: heroInsights != null
                                    ? '${heroInsights.xp} XP'
                                    : isLoadingInsights
                                    ? 'XP ...'
                                    : 'XP --',
                              ),
                              if (ratingValue != null && ratingValue > 0)
                                _buildSuggestedMetric(
                                  icon: Icons.star_rounded,
                                  label: ratingValue.toStringAsFixed(1),
                                  tint: const Color(0xFFFFE2A8),
                                ),
                              _buildSuggestedMetric(
                                icon: route.isRoundTrip
                                    ? Icons.loop_rounded
                                    : Icons.alt_route_rounded,
                                label: routeTypeLabel,
                              ),
                              if (climbMeters != null)
                                _buildSuggestedMetric(
                                  icon: Icons.north_rounded,
                                  label: '↑ $climbMeters m',
                                  tint: const Color(0xFFDCFCE7),
                                )
                              else if (isLoadingInsights)
                                _buildSuggestedMetric(
                                  icon: Icons.north_rounded,
                                  label: '↑ ...',
                                ),
                            ],
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              _buildStyleChip(route),
                              const SizedBox(width: 10),
                              _buildSaveChip(route),
                              const Spacer(),
                              GestureDetector(
                                onTap: () {
                                  CruiseModePage.pendingRoute.value = route;
                                  widget.onTabChange?.call(2);
                                },
                                child: Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF3B30),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.directions_car_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Route fahren',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    _buildSuggestedRoutePreview(route, coordinates),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestedMetric({
    required IconData icon,
    required String label,
    Color tint = const Color(0xFFEFEFEF),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tint),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: tint,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestedRoutePreview(
    SavedRoute route,
    List<List<double>> coordinates,
  ) {
    return SizedBox(
      width: 188,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF10131A),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: coordinates.length >= 2
                      ? CustomPaint(
                          painter: _RoutePolylinePainter(
                            coordinates: coordinates,
                          ),
                        )
                      : Center(
                          child: Text(
                            route.styleEmoji,
                            style: const TextStyle(fontSize: 38),
                          ),
                        ),
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    route.styleEmoji,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.map_outlined,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaveChip(SavedRoute route) {
    return GestureDetector(
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _isRouteSaved
              ? const Color(0xFFFFE2A8).withValues(alpha: 0.16)
              : Colors.black.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isRouteSaved
                ? const Color(0xFFFFE2A8).withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Icon(
          _isRouteSaved
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          color: _isRouteSaved ? const Color(0xFFFFE2A8) : Colors.white,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildStyleChip(SavedRoute route) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        '${route.styleEmoji} ${route.style}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildEmptyRecommendation() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: const Border(
          left: BorderSide(color: Color(0xFFFF3B30), width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Vorgeschlagene Route',
                      style: TextStyle(
                        color: Color(0xFFFF3B30),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Starte deine erste Route',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sobald eine Empfehlung verfügbar ist, erscheint sie hier als kompakte Hero-Route.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.route_rounded,
                            color: Color(0xFFFF3B30),
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Keine Route vorhanden',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: const Color(0xFF10131A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: const Icon(
                  Icons.explore_outlined,
                  color: Color(0xFFFF3B30),
                  size: 42,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestedRouteSkeleton() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: const Border(
          left: BorderSide(color: Color(0xFFFF3B30), width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _shimmerBar(width: 146, height: 10),
                    const SizedBox(height: 12),
                    _shimmerBar(width: 240, height: 22),
                    const SizedBox(height: 8),
                    _shimmerBar(width: 190, height: 22),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _shimmerPill(width: 76),
                        _shimmerPill(width: 82),
                        _shimmerPill(width: 86),
                        _shimmerPill(width: 72),
                        _shimmerPill(width: 78),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _shimmerBar(width: double.infinity, height: 40)),
                        const SizedBox(width: 10),
                        _shimmerBar(width: 128, height: 40),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              _shimmerRoutePreview(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shimmerBar({
    required double width,
    required double height,
    double radius = 12,
  }) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        final phase = _shimmerController.value;
        return Container(
          width: width.isFinite ? width : double.infinity,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + phase * 2, -0.2),
              end: Alignment(1.0 + phase * 2, 0.2),
              colors: const [
                Color(0xFF22262F),
                Color(0xFF323844),
                Color(0xFF22262F),
              ],
              stops: const [0.2, 0.5, 0.8],
            ),
          ),
        );
      },
    );
  }

  Widget _shimmerPill({required double width}) {
    return _shimmerBar(width: width, height: 28, radius: 999);
  }

  Widget _shimmerRoutePreview() {
    return SizedBox(
      width: 132,
      child: Container(
        height: 176,
        decoration: BoxDecoration(
          color: const Color(0xFF10131A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            _shimmerBar(width: double.infinity, height: 12, radius: 999),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF151922),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: AnimatedBuilder(
                  animation: _shimmerController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _RoutePolylinePainter(
                        coordinates: const [
                          [0.12, 0.78],
                          [0.26, 0.52],
                          [0.42, 0.60],
                          [0.58, 0.30],
                          [0.76, 0.44],
                          [0.88, 0.18],
                        ],
                      ),
                    );
                  },
                ),
              ),
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

class _HeroRouteInsights {
  const _HeroRouteInsights({
    required this.curves,
    required this.xp,
    required this.elevation,
  });

  final int curves;
  final int xp;
  final RouteElevationSummary? elevation;
}

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
