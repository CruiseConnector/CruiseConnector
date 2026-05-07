import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/application/providers/route_bookmark_provider.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/route_elevation_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/domain/models/user_level.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';
import 'package:cruise_connect/presentation/widgets/badge_unlock_popup.dart';
import 'package:cruise_connect/presentation/widgets/community_carousel_card.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

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
  String? _profileUserId;
  String? _avatarUrl;
  String? _profileUsername;
  bool _loading = true;
  List<double> _weeklyChartData = List.filled(7, 0);
  List<double> _weeklyKmData = List.filled(7, 0);
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
      Map<String, dynamic>? profile;
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        try {
          profile = await Supabase.instance.client
              .from('profiles')
              .select('id, username, avatar_url')
              .eq('id', userId)
              .maybeSingle();
        } catch (e) {
          debugPrint('[Home] Profil-Abfrage fehlgeschlagen: $e');
        }
      }
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

      final streak = GamificationService.calculateDrivingStreakDays(rideRoutes);

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
          final savedRoutes = await SavedRoutesService.getSavedRouteLibrary();
          routeSaved = SavedRoutesService.hasEquivalentSavedRoute(
            topRoute,
            savedRoutes,
          );
        }
      } catch (e) {
        debugPrint('[Home] Top-Route laden fehlgeschlagen: $e');
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
          _profileUserId = userId;
          _profileUsername = (profile?['username'] as String?)?.trim();
          _avatarUrl = profile?['avatar_url'] as String?;
          _weeklyChartData = normalized;
          _weeklyKmData = weeklyKm;
          _streakDays = streak;
          _weeklyTopRoute = topRoute;
          _isRouteSaved = routeSaved;
          _loading = false;
        });
      }

      if (topRoute != null) {
        unawaited(_ensureHeroRouteInsights(topRoute));
      }
      if (mounted && profile != null) {
        context.read<CommunityProvider>().seedProfile(profile);
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
      return [];
    }
    return extracted;
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<AppAccentProvider>().color;
    final community = context.watch<CommunityProvider>();
    final user = Supabase.instance.client.auth.currentUser;
    final profileBelongsToUser = _profileUserId == user?.id;
    final cachedProfile = user?.id == null
        ? null
        : community.cachedProfile(user!.id);
    final profileUsername =
        (cachedProfile?['username'] as String?) ??
        (profileBelongsToUser ? _profileUsername : null);
    final avatarUrl =
        (cachedProfile?['avatar_url'] as String?) ??
        (profileBelongsToUser ? _avatarUrl : null);
    final String userName = (profileUsername?.isNotEmpty ?? false)
        ? profileUsername!
        : (user?.userMetadata?['username'] as String?) ??
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
                    Padding(
                      padding: const EdgeInsets.only(top: 4, right: 2),
                      child: UserAvatar(
                        name: userName,
                        avatarUrl: avatarUrl,
                        radius: 28,
                        backgroundColor: accent,
                        onTap: () => widget.onTabChange?.call(4),
                      ),
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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onTabChange?.call(3),
              child: Container(
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
                    const Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Fortschritt',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFFA0AEC0),
                          size: 22,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _loading
                        ? Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: accent,
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
                                gradient: LinearGradient(
                                  colors: [
                                    accent,
                                    AppAccentColors.accentStrong,
                                  ],
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
                      userLevel >= UserLevel.maxLevel
                          ? 'Maximallevel erreicht'
                          : 'Noch $xpToNextLevel XP bis Level ${userLevel + 1}',
                      style: const TextStyle(
                        color: Color(0xFFA0AEC0),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Top-Strecke dieser Woche
            _buildSuggestedRouteSection(),
            const SizedBox(height: 16),

            // Community + Chart Section
            SizedBox(
              height: 244,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: CommunityCarouselCard(
                      onOpenCommunity: () => widget.onTabChange?.call(1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _buildWeeklyActivityCard()),
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
      return _buildSuggestedRouteCard(_weeklyTopRoute!);
    }

    if (_loading) {
      return _buildSuggestedRouteSkeleton();
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
    final curvesLabel = heroInsights != null
        ? '${heroInsights.curves} Kurven'
        : isLoadingInsights
        ? 'Kurven ...'
        : 'Kurven --';
    final durationLabel = route.formattedDuration;
    final distanceLabel = route.formattedDistance;
    final tertiaryLabel = heroInsights != null
        ? '${heroInsights.xp} XP'
        : climbMeters != null
        ? '↑ $climbMeters m'
        : routeTypeLabel;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 680;
        final previewSize = isCompact ? 148.0 : 232.0;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF2A313C),
            borderRadius: BorderRadius.circular(34),
            boxShadow: [
              BoxShadow(
                color: AppAccentColors.accent.withValues(alpha: 0.12),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      right: 16,
                      top: 4,
                      bottom: 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Heute für dich',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '${route.styleEmoji} – $title',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isCompact ? 21 : 25,
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '$distanceLabel • $curvesLabel • $durationLabel',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: isCompact ? 14 : 17,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (ratingValue != null && ratingValue > 0)
                          _buildSuggestedInfoRow(
                            icon: Icons.star_rounded,
                            label:
                                '${ratingValue.toStringAsFixed(1)} Bewertung',
                            tint: const Color(0xFFFFD76A),
                          ),
                        const SizedBox(height: 14),
                        _buildSuggestedInfoRow(
                          icon: Icons.local_fire_department_rounded,
                          label: tertiaryLabel,
                          tint: AppAccentColors.accent,
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _buildStyleChip(route),
                            _buildSaveChip(route),
                            GestureDetector(
                              onTap: () {
                                CruiseModePage.pendingRoute.value = route;
                                widget.onTabChange?.call(2);
                              },
                              child: Container(
                                height: 42,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: AppAccentColors.accent,
                                  borderRadius: BorderRadius.circular(16),
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
                                      'Fahren',
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
                ),
                _buildSuggestedRoutePreview(
                  route,
                  coordinates,
                  size: previewSize,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuggestedInfoRow({
    required IconData icon,
    required String label,
    required Color tint,
  }) {
    return Row(
      children: [
        Icon(icon, size: 22, color: tint),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestedRoutePreview(
    SavedRoute route,
    List<List<double>> coordinates, {
    required double size,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(AppAccentColors.accent, Colors.white, 0.10)!,
              AppAccentColors.accentStrong,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppAccentColors.accent.withValues(alpha: 0.28),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF171C24),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.06),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: coordinates.length >= 2
                        ? CustomPaint(
                            painter: _RoutePolylinePainter(
                              coordinates: coordinates,
                            ),
                          )
                        : Center(
                            child: Text(
                              route.styleEmoji,
                              style: const TextStyle(fontSize: 46),
                            ),
                          ),
                  ),
                ),
                Positioned(
                  left: 14,
                  top: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      route.styleEmoji,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
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
      ),
    );
  }

  Widget _buildEmptyRecommendation() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF2A313C),
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: AppAccentColors.accent.withValues(alpha: 0.1),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Heute für dich',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Starte deine erste Route',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sobald eine Empfehlung verfügbar ist, erscheint sie hier als kompakte Featured-Route.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 132,
              height: 132,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(AppAccentColors.accent, Colors.white, 0.10)!,
                      AppAccentColors.accentStrong,
                    ],
                  ),
                ),
                child: Container(
                  margin: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171C24),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    Icons.explore_outlined,
                    color: AppAccentColors.accent,
                    size: 40,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestedRouteSkeleton() {
    Widget shimmerCopy(double maxWidth) {
      double capped(double width) => math.min(width, maxWidth);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _shimmerBar(width: capped(150), height: 18),
          const SizedBox(height: 20),
          _shimmerBar(width: capped(250), height: 28),
          const SizedBox(height: 12),
          _shimmerBar(width: capped(260), height: 18),
          const SizedBox(height: 28),
          _shimmerBar(width: capped(220), height: 18),
          const SizedBox(height: 14),
          _shimmerBar(width: capped(180), height: 18),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _shimmerPill(width: capped(92)),
              _shimmerPill(width: capped(42)),
              _shimmerPill(width: capped(90)),
            ],
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 420;
        final previewSize = isCompact ? 132.0 : 188.0;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF2A313C),
            borderRadius: BorderRadius.circular(34),
            boxShadow: [
              BoxShadow(
                color: AppAccentColors.accent.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Container(
              constraints: const BoxConstraints(minHeight: 208),
              child: Row(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, copyConstraints) {
                        return shimmerCopy(copyConstraints.maxWidth);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  _shimmerRoutePreview(size: previewSize),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSaveChip(SavedRoute route) {
    return GestureDetector(
      onTap: () async {
        try {
          if (_isRouteSaved) {
            await SavedRoutesService.unsaveRouteEverywhere(route);
            if (!mounted) return;
            unawaited(context.read<RouteBookmarkProvider>().loadSavedRoutes());
            setState(() => _isRouteSaved = false);
            return;
          }

          await SavedRoutesService.saveExistingRoute(route);
          if (!mounted) return;
          unawaited(context.read<RouteBookmarkProvider>().loadSavedRoutes());
          final gamResult = await GamificationService.calculateAndSync();
          if (!mounted) return;
          if (gamResult.newBadges.isNotEmpty) {
            await showBadgeUnlockPopup(
              context: context,
              badges: gamResult.newBadges,
            );
          }
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

  Widget _shimmerRoutePreview({double size = 188}) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(AppAccentColors.accent, Colors.white, 0.10)!,
              AppAccentColors.accentStrong,
            ],
          ),
        ),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF171C24),
            borderRadius: BorderRadius.circular(24),
          ),
          child: AnimatedBuilder(
            animation: _shimmerController,
            builder: (context, child) {
              return Padding(
                padding: const EdgeInsets.all(18),
                child: CustomPaint(
                  painter: _RoutePolylinePainter(
                    coordinates: [
                      [0.12, 0.78],
                      [0.26, 0.52],
                      [0.42, 0.60],
                      [0.58, 0.30],
                      [0.76, 0.44],
                      [0.88, 0.18],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Streak Widget ────────────────────────────────────────────────────────

  Widget _buildStreakWidget() {
    final hasStreak = _streakDays > 0;
    final nextStreakDays = hasStreak ? _streakDays + 1 : 1;
    final nextMultiplier = GamificationService.streakMultiplierForDays(
      nextStreakDays,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasStreak
              ? AppAccentColors.accent.withValues(alpha: 0.3)
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
                  ? AppAccentColors.accent.withValues(alpha: 0.15)
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
                      ? 'Fahre heute für ${nextMultiplier.toStringAsFixed(2)}x XP.'
                      : 'Starte eine Fahrt und beginne deinen XP-Streak.',
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
                gradient: AppAccentColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${nextMultiplier.toStringAsFixed(2)}x',
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

  Widget _buildWeeklyActivityCard() {
    const days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final totalKm = _weeklyKmData.fold<double>(0, (sum, km) => sum + km);
    final activeDays = _weeklyKmData.where((km) => km > 0.05).length;

    return Container(
      padding: const EdgeInsets.all(12),
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
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Letzte 7 Tage',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppAccentColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _formatCompactKm(totalKm),
                  style: TextStyle(
                    color: AppAccentColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            activeDays == 0
                ? 'Noch keine Fahrten'
                : '$activeDays aktive ${activeDays == 1 ? 'Tag' : 'Tage'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 11),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(days.length, (index) {
                return Expanded(
                  child: _buildWeeklyBar(
                    day: days[index],
                    value: _weeklyChartData[index],
                    km: _weeklyKmData[index],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyBar({
    required String day,
    required double value,
    required double km,
  }) {
    final hasKm = km > 0.05;
    final fill = hasKm ? math.max(value, 0.12) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Container(
                    width: 12,
                    height: constraints.maxHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D3748),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        width: 12,
                        height: constraints.maxHeight * fill,
                        decoration: BoxDecoration(
                          gradient: hasKm
                              ? AppAccentColors.primaryGradient
                              : null,
                          color: hasKm ? null : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            day,
            maxLines: 1,
            style: TextStyle(
              color: hasKm ? Colors.white : const Color(0xFFA0AEC0),
              fontSize: 10,
              fontWeight: hasKm ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatCompactKm(double km) {
    if (km <= 0.05) return '0 km';
    if (km >= 100) return '${km.round()} km';
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  }
}

// ── CustomPainter für Route-Polyline auf dem Gradient-Hintergrund ──────────

class _HeroRouteInsights {
  _HeroRouteInsights({
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
      ..color = AppAccentColors.accent.withValues(alpha: 0.3)
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
