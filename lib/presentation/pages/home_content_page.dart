import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/application/providers/route_bookmark_provider.dart';
import 'package:cruise_connect/application/providers/saved_routes_provider.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/home_route_recommendation_service.dart';
import 'package:cruise_connect/data/services/route_elevation_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/domain/models/user_level.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';
import 'package:cruise_connect/presentation/widgets/badge_unlock_popup.dart';
import 'package:cruise_connect/presentation/widgets/community_carousel_card.dart';
import 'package:cruise_connect/presentation/widgets/top_toast.dart';
import 'package:cruise_connect/data/services/notification_service.dart';
import 'package:cruise_connect/data/services/trip_service.dart';
import 'package:cruise_connect/presentation/pages/notifications_page.dart';
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
  TripSummary? _activeTrip; // 2026-05-24 (vucko Task #53): Resume-Card
  HomeRouteRecommendation? _todayRecommendation;
  bool _isRouteSaved = false;
  // 2026-06-09 (vucko Audit T3-B): Re-Entry-Guard gegen Doppel-Tap auf Speichern
  // → sonst nebenläufige saveExistingRoute-Calls = doppelte DB-Inserts.
  bool _isSavingRoute = false;
  bool _isClosingTrip = false;
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
    // 2026-05-28 (vucko Task #68): Cached Home-Snapshot ASYNC laden damit
    // beim App-Start Level + Wochen-Chart + Lite-Recommendation sofort
    // sichtbar sind statt Skeleton — der Refresh läuft im Hintergrund.
    unawaited(_hydrateFromHomeSnapshot());
    _loadStats();
  }

  /// 2026-05-28 (vucko Task #68): Schneller initial-Render aus dem letzten
  /// gespeicherten Home-Snapshot — User sieht Level, XP-Bar, Wochen-Chart
  /// und eine Lite-Version der Empfehlung sofort beim App-Start. Sobald der
  /// Hintergrund-Refresh (_loadStats) durch ist, wird animiert auf die
  /// frischen Werte umgestellt.
  Future<void> _hydrateFromHomeSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('home_snapshot_v1');
      if (raw == null || !mounted) return;
      final map = jsonDecode(raw);
      if (map is! Map) return;
      setState(() {
        userLevel = (map['userLevel'] as num?)?.toInt() ?? userLevel;
        levelProgress =
            (map['levelProgress'] as num?)?.toDouble() ?? levelProgress;
        levelName = (map['levelName'] as String?) ?? levelName;
        xpToNextLevel =
            (map['xpToNextLevel'] as num?)?.toInt() ?? xpToNextLevel;
        totalXp = (map['totalXp'] as num?)?.toInt() ?? totalXp;
        totalRoutes = (map['totalRoutes'] as num?)?.toInt() ?? totalRoutes;
        totalDistanceKm =
            (map['totalDistanceKm'] as num?)?.toDouble() ?? totalDistanceKm;
        badgeCount = (map['badgeCount'] as num?)?.toInt() ?? badgeCount;
        _streakDays = (map['streakDays'] as num?)?.toInt() ?? _streakDays;
        final weekly = map['weeklyKm'];
        if (weekly is List && weekly.length == 7) {
          _weeklyKmData = weekly
              .map((e) => (e as num?)?.toDouble() ?? 0.0)
              .toList(growable: false);
          final maxKm = _weeklyKmData.fold<double>(0, (a, b) => a > b ? a : b);
          _weeklyChartData = _weeklyKmData
              .map((km) => maxKm > 0 ? (km / maxKm).clamp(0.0, 1.0) : 0.0)
              .toList(growable: false);
        }
        _profileUsername =
            map['profileUsername'] as String? ?? _profileUsername;
        _avatarUrl = map['avatarUrl'] as String? ?? _avatarUrl;
        // 2026-05-28 (vucko Task #72): Cached Recommendation hydraten
        // damit die "Heute für dich"-Card beim 2.+ App-Start direkt sichtbar
        // ist (statt "Starte deine erste Route" Empty-State).
        final recoRaw = map['recommendation'];
        if (recoRaw is Map) {
          try {
            _todayRecommendation = HomeRouteRecommendation.fromJson(
              Map<String, dynamic>.from(recoRaw),
            );
          } catch (e) {
            debugPrint('[Home] Cached recommendation parse failed: $e');
          }
        }
        // Loading-Flag bleibt true — Card wird sofort gerendert mit cached
        // Daten, im Hintergrund läuft der echte Refresh weiter.
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Home] Snapshot-Hydration fehlgeschlagen: $e');
    }
  }

  Future<void> _persistHomeSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final reco = _todayRecommendation;
      await prefs.setString(
        'home_snapshot_v1',
        jsonEncode(<String, dynamic>{
          'userLevel': userLevel,
          'levelProgress': levelProgress,
          'levelName': levelName,
          'xpToNextLevel': xpToNextLevel,
          'totalXp': totalXp,
          'totalRoutes': totalRoutes,
          'totalDistanceKm': totalDistanceKm,
          'badgeCount': badgeCount,
          'streakDays': _streakDays,
          'weeklyKm': _weeklyKmData,
          'profileUsername': _profileUsername,
          'avatarUrl': _avatarUrl,
          // 2026-05-28 (vucko Task #72): Recommendation mit serialisieren
          // damit beim 2.+ App-Start sofort die Card sichtbar ist.
          if (reco != null) 'recommendation': reco.toJson(),
        }),
      );
    } catch (e) {
      debugPrint('[Home] Snapshot persistieren fehlgeschlagen: $e');
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  /// 2026-05-22 (vucko): Schneller GPS-Resolve für Home-Recommendation.
  /// Strategie: lastKnownPosition zuerst (instant), parallel currentPosition
  /// mit 3s timeout. Wenn lastKnown da ist → sofort zurück. Sonst warte
  /// auf current. Fallback Frankfurt nach 3s total.
  Future<({double lat, double lng})> _resolveUserPosition() async {
    try {
      final permission = await geo.Geolocator.checkPermission();
      if (permission != geo.LocationPermission.always &&
          permission != geo.LocationPermission.whileInUse) {
        await geo.Geolocator.requestPermission();
      }
    } catch (_) {}
    // lastKnownPosition ist instant (gecached) — meistens genau genug
    try {
      final last = await geo.Geolocator.getLastKnownPosition().timeout(
        const Duration(seconds: 1),
      );
      if (last != null) return (lat: last.latitude, lng: last.longitude);
    } catch (_) {}
    // Sonst: kurzes currentPosition mit medium accuracy + 3s timeout
    try {
      final pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.medium,
          timeLimit: Duration(seconds: 3),
        ),
      );
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {}
    // Fallback Vorarlberg-Bodensee (besser als Frankfurt für DACH-User)
    return (lat: 47.5031, lng: 9.7471);
  }

  Future<void> _loadStats() async {
    try {
      // 2026-05-22 (vucko): PARALLEL loading — vorher seriell:
      // gamification → drive → profile → weekly → GPS(10s!) → recommendation → saved
      // Jetzt: alle unabhängigen calls gleichzeitig, GPS startet sofort.
      final userId = Supabase.instance.client.auth.currentUser?.id;

      final gamificationFuture = GamificationService.calculateAndSync();
      final driveSessionsFuture = GamificationService.getDriveSessions();
      final profileFuture = userId != null
          ? Supabase.instance.client
                .from('profiles')
                .select('id, username, avatar_url')
                .eq('id', userId)
                .maybeSingle()
                .then<Map<String, dynamic>?>((v) => v)
                .catchError((_) => null)
          : Future<Map<String, dynamic>?>.value(null);
      final userPosFuture = _resolveUserPosition();
      final savedRoutesFuture = SavedRoutesService.getSavedRouteLibrary()
          .catchError((_) => <SavedRoute>[]);

      final result = await gamificationFuture;
      final driveSessions = await driveSessionsFuture;
      final profile = await profileFuture;
      final userPos = await userPosFuture;
      final savedRoutes = await savedRoutesFuture;
      // Wöchentliche Daten berechnen
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(
        Duration(days: todayStart.weekday - 1),
      );
      final weeklyKm = List<double>.filled(7, 0);
      for (final session in driveSessions) {
        final localCreatedAt = session.createdAt.toLocal();
        final routeDay = DateTime(
          localCreatedAt.year,
          localCreatedAt.month,
          localCreatedAt.day,
        );
        if (!routeDay.isBefore(weekStart)) {
          final dayIndex = routeDay.weekday - 1;
          if (dayIndex >= 0 && dayIndex < 7) {
            weeklyKm[dayIndex] += session.distanceKm;
          }
        }
      }
      final maxKm = weeklyKm.fold<double>(0, (a, b) => a > b ? a : b);
      final normalized = weeklyKm
          .map((km) => maxKm > 0 ? (km / maxKm).clamp(0.0, 1.0) : 0.0)
          .toList();

      final streak = GamificationService.calculateDrivingStreakDays(
        driveSessions,
      );

      // Recommendation aus dem verified Routenpool — GPS schon parallel oben gelaufen.
      HomeRouteRecommendation? recommendation;
      bool routeSaved = false;
      try {
        recommendation = await HomeRouteRecommendationService.getTodayRoute(
          userLat: userPos.lat,
          userLng: userPos.lng,
        );
        if (recommendation != null) {
          routeSaved = SavedRoutesService.hasEquivalentSavedRoute(
            recommendation.route,
            savedRoutes,
          );
        }
      } catch (e) {
        debugPrint('[Home] Routepool-Empfehlung laden fehlgeschlagen: $e');
      }

      // 2026-05-24 (vucko Task #53): Aktive/pausierte Trip checken für Resume-Card
      // 2026-06-10 (vucko Trip-Resume): AUCH Solo-Trips (User-Wunsch geändert:
      // Trips sollen zwischenspeicherbar sein und von egal wo fortsetzbar).
      TripSummary? activeTrip;
      try {
        activeTrip = await TripService.instance
            .activeOrPausedTripForCurrentUser(groupOnly: false);
      } catch (e) {
        debugPrint('[Home] Trip-Status laden fehlgeschlagen: $e');
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
          _activeTrip = activeTrip;
          _todayRecommendation = recommendation;
          _isRouteSaved = routeSaved;
          _loading = false;
        });
      }

      if (recommendation != null) {
        unawaited(_ensureHeroRouteInsights(recommendation.route));
      }
      if (mounted && profile != null) {
        context.read<CommunityProvider>().seedProfile(profile);
      }
      // 2026-05-28 (vucko Task #68): Persistiere Home-Snapshot damit der
      // nächste App-Start sofort die Card mit cached Werten rendert statt
      // Skeleton.
      unawaited(_persistHomeSnapshot());
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
        // 2026-06-15 (vucko): Streak-Bonus in der Empfehlungs-XP mitzeigen.
        streakDays: _streakDays,
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

    return RefreshIndicator(
      color: accent,
      backgroundColor: const Color(0xFF1A1E28),
      onRefresh: () async {
        // Re-fetch alle Home-Daten parallel
        await Future.wait([
          GamificationService.calculateAndSync(),
          context.read<SavedRoutesProvider>().loadRoutes().catchError((_) {}),
          context.read<RouteBookmarkProvider>().loadSavedRoutes().catchError(
            (_) {},
          ),
        ]);
        if (mounted) setState(() {});
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
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
                          // 2026-06-09 (vucko Audit T3-C): maxLines:1 — ohne das war
                          // ellipsis in der unbeschränkten Column wirkungslos (Overflow
                          // bei langen Namen auf schmalen Screens).
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // 2026-05-23 (vucko): Bell-Icon mit Unread-Badge links
                  // vom Avatar — führt zur Notifications-Inbox.
                  Consumer<NotificationService>(
                    builder: (context, notifSvc, _) {
                      final count = notifSvc.unreadCount;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8, right: 6),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Material(
                              color: Colors.transparent,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const NotificationsPage(),
                                  ),
                                ),
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.notifications_none_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                            if (count > 0)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 18,
                                    minHeight: 18,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFF0B0E14),
                                      width: 2,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    count > 99 ? '99+' : '$count',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
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

              // 2026-05-24 (vucko Task #42): Hero-Streak-Banner (nur sichtbar
              // wenn 2+ Tage). Prominent, animiert, sofort sichtbar im
              // Above-the-fold-Bereich für Daily-Retention.
              if (_streakDays >= 2) ...[
                _buildHeroStreakBanner(),
                const SizedBox(height: 14),
              ],

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
                                // 2026-06-08 (vucko Homescreen-Redesign): 2×2-Raster
                                // aus Icon-Kacheln statt Emoji-Liste → sofortiger
                                // Überblick, crisp Material-Icons statt Emojis.
                                Row(
                                  children: [
                                    Expanded(
                                      child: _statTile(
                                        Icons.bolt,
                                        _formatThousands(totalXp),
                                        'XP GESAMT',
                                        isAccent: true,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _statTile(
                                        Icons.speed,
                                        totalDistanceKm.toStringAsFixed(0),
                                        'KM GEFAHREN',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _statTile(
                                        Icons.route,
                                        '$totalRoutes',
                                        'STRECKEN',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _statTile(
                                        Icons.workspace_premium,
                                        '$badgeCount',
                                        'BADGES',
                                      ),
                                    ),
                                  ],
                                ),
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
                          // 2026-06-08 (vucko Homescreen-Redesign): akzent-getönte
                          // Spur (statt flachem Grau) → der Balken wirkt integriert;
                          // Mindest-Nub, damit kleiner Fortschritt sichtbar bleibt.
                          Container(
                            height: 8,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: levelProgress.clamp(0.02, 1.0),
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
              // 2026-06-15 (vucko): unteres Streak-Widget entfernt — es war eine
              // Dublette zum Hero-Streak-Banner ganz oben. Nur das obere Banner
              // (mit echtem Multiplikator) bleibt.
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestedRouteSection() {
    final recommendation = _todayRecommendation;
    final trip = _activeTrip;

    // 2026-05-24 (vucko): Beides vorhanden → swipeable Carousel mit Trip zuerst.
    // Nur Trip → nur Trip-Card. Nur Recommendation → nur diese.
    if (trip != null && recommendation != null) {
      return _buildHomeCarousel(
        cards: [
          _buildTripResumeCarouselCard(trip),
          // Heute-für-dich-Card auf gleiche Carousel-Höhe wrappen damit
          // PageView nichts streckt. Original-Card hat intrinsisch < 180px.
          SizedBox(
            height: _carouselCardHeight,
            child: _buildSuggestedRouteCard(recommendation),
          ),
        ],
      );
    }
    if (trip != null) {
      return _buildTripResumeCarouselCard(trip);
    }
    if (recommendation != null) {
      return _buildSuggestedRouteCard(recommendation);
    }
    if (_loading) {
      return _buildSuggestedRouteSkeleton();
    }
    return _buildEmptyRecommendation();
  }

  // 2026-05-24 (vucko): Carousel-State für Trip+Heute-Slides.
  int _carouselIndex = 0;
  late final PageController _carouselController = PageController();

  /// Carousel-Höhe synchron zur Heute-für-dich-Card.
  /// "Heute für dich" braucht mit Mini-Map, nachgeladenen Hero-Insights,
  /// zwei Metric-Zeilen und 44px-CTA genug Luft, sonst overflowt sie im
  /// Trip+Route-Carousel auf schmalen iPhones.
  static const double _carouselCardHeight = 228;

  Widget _buildHomeCarousel({required List<Widget> cards}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _carouselCardHeight,
          child: PageView.builder(
            controller: _carouselController,
            itemCount: cards.length,
            onPageChanged: (i) {
              if (mounted) setState(() => _carouselIndex = i);
            },
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: cards[i],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Pagination dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(cards.length, (i) {
            final active = i == _carouselIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 6,
              width: active ? 20 : 6,
              decoration: BoxDecoration(
                color: active
                    ? AppAccentColors.accent
                    : Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }

  /// Trip-Resume-Card im Carousel — komplett app-konforme dunkle Optik.
  /// 2026-05-24 (vucko v2): kein Gradient, kein helles Tinten, exakt das
  /// gleiche Card-Schema wie "Heute für dich". Status nur als kleiner
  /// gefärbter Pin.
  Widget _buildTripResumeCarouselCard(TripSummary trip) {
    final isPaused = trip.isPaused;
    final statusColor = isPaused
        ? const Color(0xFFFFB347)
        : AppAccentColors.accent;
    final statusLabel = isPaused ? 'Tour pausiert' : 'Tour aktiv';
    final statusSubtitle = _tripStatusSubtitle(trip);
    final title = trip.title.isEmpty ? 'Multi-Stop Tour' : trip.title;
    // Distanz nur zeigen wenn > 0 (sonst irreführend "0 km")
    final km = trip.totalDistanceKm;
    final metricsLine = km > 0
        ? '${trip.stopCount} Stopps • ${km.toStringAsFixed(0)} km • ${trip.defaultStyle}'
        : '${trip.stopCount} Stopps • ${trip.defaultStyle}';
    final canCancelTrip = _canCancelTrip(trip);
    return SizedBox(
      height: _carouselCardHeight,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header-Zeile (exakt analog "Heute für dich")
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.45),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    statusLabel.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.66),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.35,
                    ),
                  ),
                  if (statusSubtitle.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '· $statusSubtitle',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.42),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.25,
                  height: 1.05,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),
              Text(
                metricsLine,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.64),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              // CTA wie der Drive-Chip in der Heute-Card (orange filled)
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openTrip(trip),
                      child: SizedBox(
                        height: 40,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppAccentColors.accent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppAccentColors.accent.withValues(
                                  alpha: 0.32,
                                ),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 19,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isPaused ? 'Tour fortsetzen' : 'Tour öffnen',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (canCancelTrip) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Tour abbrechen',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _isClosingTrip
                            ? null
                            : () => _confirmCancelTrip(trip),
                        child: Container(
                          width: 44,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: _isClosingTrip
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  Icons.close_rounded,
                                  color: Colors.white.withValues(alpha: 0.76),
                                  size: 20,
                                ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openTrip(TripSummary trip) {
    // 2026-06-10 (vucko Resume-Crash-Fix): erst null, dann id — ein
    // ValueNotifier feuert bei GLEICHEM Wert nicht. Blieb der Intent von
    // einem fehlgeschlagenen Versuch stehen (wird seit heute erst nach
    // Erfolg konsumiert), wäre der zweite Tap sonst ein totes Event.
    CruiseModePage.pendingTripResume.value = null;
    CruiseModePage.pendingTripResume.value = trip.id;
    widget.onTabChange?.call(2);
  }

  bool _canCancelTrip(TripSummary trip) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    return userId != null && trip.ownerId == userId;
  }

  Future<void> _confirmCancelTrip(TripSummary trip) async {
    if (_isClosingTrip) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text(
          'Tour abbrechen?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Die Tour wird aus dem Fortsetzen-Bereich entfernt. Deine gefahrenen Strecken bleiben unverändert.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Zurück',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Abbrechen',
              style: TextStyle(
                color: AppAccentColors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final previousTrip = _activeTrip;
    setState(() {
      _isClosingTrip = true;
      _activeTrip = null;
    });

    try {
      await TripService.instance.cancelTrip(trip.id);
      if (!mounted) return;
      TopToast.show(
        context,
        message: 'Tour abgebrochen',
        icon: Icons.close_rounded,
      );
      unawaited(_loadStats());
    } catch (e) {
      debugPrint('[Home] Trip abbrechen fehlgeschlagen: $e');
      if (!mounted) return;
      setState(() => _activeTrip = previousTrip);
      TopToast.show(
        context,
        message: 'Tour konnte nicht abgebrochen werden',
        icon: Icons.error_outline,
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isClosingTrip = false);
    }
  }

  String _tripStatusSubtitle(TripSummary trip) {
    // 2026-05-24 (vucko Fix): negative Diff (clock skew / zukünftiger
    // started_at) als "gerade gestartet" zeigen — niemals "-X Min".
    String formatAgo(DateTime when, String prefix) {
      final mins = DateTime.now().difference(when).inMinutes;
      if (mins <= 0) return '$prefix gerade eben';
      if (mins < 60) return '$prefix seit $mins Min';
      final h = mins ~/ 60;
      if (h < 24) return '$prefix seit ${h}h';
      return '$prefix seit ${h ~/ 24}d';
    }

    if (trip.isPaused && trip.pausedAt != null) {
      return formatAgo(trip.pausedAt!, 'pausiert');
    }
    if (trip.isActive && trip.startedAt != null) {
      return formatAgo(trip.startedAt!, 'läuft');
    }
    return '';
  }

  Widget _buildSuggestedRouteCard(HomeRouteRecommendation recommendation) {
    final route = recommendation.route;
    final coordinates = _extractCoordinates(route.geometry);
    final heroInsights = _heroInsightsByRouteId[route.id];
    final ratingValue = recommendation.averageRating;
    final title = recommendation.displayName;
    final routeTypeLabel = route.isRoundTrip ? 'Rundkurs' : 'A nach B';
    final durationLabel = route.formattedDuration;
    final distanceLabel = route.formattedDistance;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 430;
        final isCarouselConstrained =
            constraints.hasBoundedHeight &&
            constraints.maxHeight <= _carouselCardHeight + 1;
        // 2026-06-08 (vucko Route-Widget): quadratische Mini-Map, ~Höhe der
        // dichten Titel-/Stat-Spalte links.
        final previewSize = isCompact
            ? (isCarouselConstrained ? 88.0 : 96.0)
            : (isCarouselConstrained ? 96.0 : 104.0);

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          // 2026-06-08 (vucko Route-Widget): dichteres, premium Layout. Tight-
          // Cluster (Eyebrow→Titel→Untertitel→Stat-Strip mit 2–11px) + EIN
          // bewusster 14px-Bruch vor der CTA. Stat-Chips → randlose Inline-Icon-
          // Metriken, Stil wandert in den Untertitel → kein Stil-Chip mehr.
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              isCarouselConstrained ? 12 : 13,
              14,
              isCarouselConstrained ? 12 : 14,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: AppAccentColors.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'HEUTE FÜR DICH',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.96),
                              fontSize: isCompact ? 17.5 : 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.25,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$routeTypeLabel · ${route.displayStyleLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              height: 1.1,
                            ),
                          ),
                          SizedBox(height: isCarouselConstrained ? 9 : 11),
                          Wrap(
                            spacing: 13,
                            runSpacing: 7,
                            children: [
                              _inlineMetric(
                                Icons.straighten_rounded,
                                distanceLabel,
                              ),
                              if (heroInsights != null)
                                _inlineMetric(
                                  Icons.moving_rounded,
                                  '${heroInsights.curves} Kurven',
                                ),
                              if (durationLabel.isNotEmpty &&
                                  durationLabel != '--')
                                _inlineMetric(
                                  Icons.schedule_rounded,
                                  durationLabel,
                                ),
                              if (ratingValue != null &&
                                  recommendation.ratingCount > 0)
                                _inlineMetric(
                                  Icons.star_rounded,
                                  ratingValue.toStringAsFixed(1),
                                  iconColor: AppAccentColors.accent,
                                  valueColor: AppAccentColors.accent,
                                ),
                              if (heroInsights != null)
                                _inlineMetric(
                                  Icons.bolt_rounded,
                                  '${heroInsights.xp} XP',
                                  iconColor: Colors.white.withValues(
                                    alpha: 0.45,
                                  ),
                                  valueColor: Colors.white.withValues(
                                    alpha: 0.5,
                                  ),
                                  valueSize: 12.5,
                                  valueWeight: FontWeight.w500,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildSuggestedRoutePreview(
                      route,
                      coordinates,
                      size: previewSize,
                    ),
                  ],
                ),
                SizedBox(height: isCarouselConstrained ? 12 : 14),
                Row(
                  children: [
                    Expanded(
                      child: _buildDriveCta(
                        onTap: () {
                          CruiseModePage.pendingRoute.value = route;
                          widget.onTabChange?.call(2);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildSaveChip(route),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 2026-06-08 (vucko Route-Widget): randlose Inline-Metrik (Icon = Label, Wert
  // daneben). Dichter + ruhiger als Pills; Icon trägt die Bedeutung.
  Widget _inlineMetric(
    IconData icon,
    String value, {
    Color? iconColor,
    Color? valueColor,
    double valueSize = 13.5,
    FontWeight valueWeight = FontWeight.w600,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: iconColor ?? Colors.white.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white.withValues(alpha: 0.88),
            fontSize: valueSize,
            fontWeight: valueWeight,
            height: 1.0,
          ),
        ),
      ],
    );
  }

  // Primäre CTA — füllt per Expanded die Restbreite, h44 für ein klares Tap-Ziel.
  Widget _buildDriveCta({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppAccentColors.accent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: [
            BoxShadow(
              color: AppAccentColors.accent.withValues(alpha: 0.34),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.directions_car_filled_rounded,
              color: Colors.white,
              size: 19,
            ),
            SizedBox(width: 7),
            Text(
              'Fahren',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestedRoutePreview(
    SavedRoute route,
    List<List<double>> coordinates, {
    required double size,
  }) {
    // 2026-06-08 (vucko Route-Widget): Mini-Map mit straßen-artigem Hintergrund
    // (Land → Blöcke → an der Routenachse ausgerichtetes Straßennetz → Route mit
    // Glow/Casing/Linie/Punkten). KEINE Overlay-Icons mehr (Stil-Badge + Map-Icon
    // entfernt) — das Kästchen zeigt nur Karte + Route.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        // 2026-06-08 (vucko Route-Widget): ganz leicht sichtbarer Rahmen.
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppAccentColors.accent.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: CustomPaint(
          painter: _RouteMiniMapPainter(
            coordinates: coordinates,
            seed: route.id.hashCode,
            accent: AppAccentColors.accent,
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
          _shimmerBar(width: capped(112), height: 12),
          const SizedBox(height: 8),
          _shimmerBar(width: capped(220), height: 24),
          const SizedBox(height: 8),
          _shimmerBar(width: capped(230), height: 14),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _shimmerPill(width: capped(118)),
              _shimmerPill(width: capped(98)),
              _shimmerPill(width: capped(74)),
            ],
          ),
          const SizedBox(height: 10),
          _shimmerBar(width: capped(190), height: 34, radius: 12),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 420;
        final previewSize = isCompact ? 92.0 : 116.0;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF2A313C),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppAccentColors.accent.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              constraints: const BoxConstraints(minHeight: 150),
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
        // 2026-06-09 (vucko Audit T3-B): Doppel-Tap-Schutz — verhindert nebenläufige
        // save/unsave-Calls (doppelte DB-Inserts / Toggle-Race).
        if (_isSavingRoute) return;
        _isSavingRoute = true;
        // 2026-05-22 (vucko): Optimistic UI — setState SOFORT, dann async work.
        // Vorher: 5 sequenzielle awaits (save → reload → checkSaved → provider
        // reload → calculateAndSync) blockten UI 2-3s. Jetzt: User sieht
        // sofort den Haken, alles andere passiert im Hintergrund.
        final wasSaved = _isRouteSaved;
        try {
          if (wasSaved) {
            setState(() => _isRouteSaved = false); // optimistic
            unawaited(SavedRoutesService.unsaveRouteEverywhere(route));
            if (!mounted) return;
            unawaited(context.read<RouteBookmarkProvider>().loadSavedRoutes());
            unawaited(context.read<SavedRoutesProvider>().loadRoutes());
            return;
          }

          // optimistic: setState true sofort
          setState(() => _isRouteSaved = true);
          TopToast.show(
            context,
            message: 'Route gespeichert',
            icon: Icons.bookmark_added_rounded,
          );
          // Async work im Hintergrund
          await SavedRoutesService.saveExistingRoute(route);
          if (!mounted) return;
          unawaited(context.read<RouteBookmarkProvider>().loadSavedRoutes());
          unawaited(context.read<SavedRoutesProvider>().loadRoutes());
          // Gamification + Badge-Popup async (kein UI-Block)
          unawaited(() async {
            final gamResult = await GamificationService.calculateAndSync();
            if (!mounted) return;
            if (gamResult.newBadges.isNotEmpty) {
              await showBadgeUnlockPopup(
                context: context,
                badges: gamResult.newBadges,
              );
            }
          }());
        } catch (e) {
          debugPrint('[Home] Route speichern fehlgeschlagen: $e');
          if (!mounted) {
            _isSavingRoute = false;
            return;
          }
          // Rollback optimistic state
          setState(() => _isRouteSaved = wasSaved);
          TopToast.show(
            context,
            message: 'Route konnte nicht gespeichert werden',
            icon: Icons.error_outline,
            isError: true,
          );
        } finally {
          _isSavingRoute = false;
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        // 2026-06-08 (vucko Route-Widget): gleiche Höhe wie der Fahren-Button (44).
        width: 48,
        height: 44,
        decoration: BoxDecoration(
          color: _isRouteSaved
              ? const Color(0xFFFFE2A8).withValues(alpha: 0.16)
              : Colors.black.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(13),
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
          size: 17,
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
                    accent: AppAccentColors.accent,
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

  // ── Hero-Streak-Banner (prominent, above-the-fold) ──────────────────────

  Widget _buildHeroStreakBanner() {
    final accent = AppAccentColors.accent;
    final mul = GamificationService.streakMultiplierForDays(_streakDays);
    final mulNext = GamificationService.streakMultiplierForDays(
      _streakDays + 1,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.94, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: GestureDetector(
        onTap: () => widget.onTabChange?.call(3),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFFF6B35).withValues(alpha: 0.85),
                accent.withValues(alpha: 0.78),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF6B35).withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.30),
                  ),
                ),
                child: const Text('🔥', style: TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_streakDays Tage Streak',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Heute fahren: ${mulNext.toStringAsFixed(2)}× XP',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.40),
                  ),
                ),
                child: Text(
                  '${mul.toStringAsFixed(2)}×',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helper Widgets ───────────────────────────────────────────────────────

  // 2026-06-08 (vucko Homescreen-Redesign): eine Stat-Kachel — Icon in dezentem
  // Squircle-Chip, große Zahl, kleines Uppercase-Label. Eine Kachel akzentuiert
  // (XP), der Rest neutral-grau → ein Fokus, kein Emoji-Wirrwarr.
  Widget _statTile(
    IconData icon,
    String value,
    String label, {
    bool isAccent = false,
  }) {
    final tint = isAccent ? AppAccentColors.accent : const Color(0xFF9AA4B2);
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: isAccent ? 0.16 : 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: tint, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFF0F0F0),
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0x80FFFFFF),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Tausender-Trennung (deutsch: 1.535).
  String _formatThousands(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return (n < 0 ? '-' : '') + buf.toString();
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

// 2026-06-08 (vucko Homescreen-Redesign): echte GPS-Route als premium Mini-Skizze.
// Aufbau hintereinander (Mapbox-Nav-Look): weicher Glow → Casing in BG-Farbe (hebt
// die Linie sauber vom Glow ab) → Akzent-Linie → Start/Ziel-Punkte mit Ring.
// Rundkurs (Start≈Ziel) zeigt EINEN Punkt statt zwei überlappender.
class _RoutePolylinePainter extends CustomPainter {
  final List<List<double>> coordinates;
  final Color accent;

  _RoutePolylinePainter({required this.coordinates, required this.accent});

  static const Color _bg = Color(0xFF171C24);

  @override
  void paint(Canvas canvas, Size size) {
    if (coordinates.length < 2) return;

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

    const padding = 12.0;
    final drawWidth = size.width - padding * 2;
    final drawHeight = size.height - padding * 2;
    final scaleX = lonRange > 0 ? drawWidth / lonRange : 1.0;
    final scaleY = latRange > 0 ? drawHeight / latRange : 1.0;
    final scale = math.min(scaleX, scaleY);
    final offsetX = padding + (drawWidth - lonRange * scale) / 2;
    final offsetY = padding + (drawHeight - latRange * scale) / 2;

    final points = coordinates.map((c) {
      final x = offsetX + (c[0] - minLon) * scale;
      final y = offsetY + (maxLat - c[1]) * scale;
      return Offset(x, y);
    }).toList();

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    // 1. Glow (weicher Akzent-Schein)
    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: 0.26)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5),
    );
    // 2. Casing (BG-Farbe) — hebt die Linie sauber vom Glow ab.
    canvas.drawPath(
      path,
      Paint()
        ..color = _bg
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    // 3. Hauptlinie (Akzent)
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    // 4. Start/Ziel-Punkte
    final diag = math.sqrt(lonRange * lonRange + latRange * latRange);
    final startEndGeo = math.sqrt(
      math.pow(coordinates.first[0] - coordinates.last[0], 2) +
          math.pow(coordinates.first[1] - coordinates.last[1], 2),
    );
    final isLoop = diag > 0 && startEndGeo / diag < 0.08;

    void dot(Offset p, Color fill) {
      canvas.drawCircle(p, 3.6, Paint()..color = _bg);
      canvas.drawCircle(p, 2.4, Paint()..color = fill);
    }

    if (isLoop) {
      dot(points.first, accent);
    } else {
      dot(points.first, const Color(0xFF34D399)); // grün = Start
      dot(points.last, accent); // Akzent = Ziel
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePolylinePainter oldDelegate) =>
      oldDelegate.coordinates != coordinates || oldDelegate.accent != accent;
}

// 2026-06-08 (vucko Route-Widget): Offline-Mini-Map als Hintergrund der Empfehlung.
// Recherchiert (Komoot/Strava-Thumbnail-Look): gedämpfter Karten-Basemap (Land +
// Häuserblöcke + an der Routen-Hauptachse ausgerichtetes Straßennetz) in einem
// engen Grau-Wertband, darüber die Route als einziges saturiertes Element. Alles
// deterministisch aus der Route-ID geseedet (kein Flackern), keine Tiles/kein
// Live-GL-Map → performant im Scroll-Feed.
class _RouteMiniMapPainter extends CustomPainter {
  final List<List<double>> coordinates; // leer → generische Skizze
  final int seed;
  final Color accent;

  _RouteMiniMapPainter({
    required this.coordinates,
    required this.seed,
    required this.accent,
  });

  static const Color _land = Color(0xFF0E0F12);

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed & 0x7fffffff);

    // 1. Land-Basis mit dezentem Vertikal-Verlauf (Tiefe statt flach).
    final baseRect = Offset.zero & size;
    canvas.drawRect(
      baseRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF14171E), Color(0xFF0C0D11)],
        ).createShader(baseRect),
    );

    // Route-Punkte (echt oder generisch) — geben die Haupt-Ausrichtung des
    // Straßennetzes vor (first→Mitte ist auch bei Rundkursen stabil).
    final pts = coordinates.length >= 2
        ? _projectRoute(size)
        : _genericRoute(size, rnd);
    final mid = pts[pts.length ~/ 2];
    final theta = math.atan2(mid.dy - pts.first.dy, mid.dx - pts.first.dx);
    final perp = theta + math.pi / 2;
    final diag = size.width + size.height;

    // 2. Baufelder: leicht in Netz-Richtung gedrehte Blöcke (wie echte Häuserzeilen
    // zwischen den Straßen), nicht achsen-parallel → wirkt organischer.
    final blockPaint = Paint()
      ..color = const Color(0xFF2B313C).withValues(alpha: 0.55);
    for (var i = 0; i < 16; i++) {
      final bw = 6.0 + rnd.nextDouble() * 13;
      final bh = 6.0 + rnd.nextDouble() * 13;
      canvas.save();
      canvas.translate(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
      );
      canvas.rotate(theta + (rnd.nextDouble() - 0.5) * 0.3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: bw, height: bh),
          const Radius.circular(1.5),
        ),
        blockPaint,
      );
      canvas.restore();
    }

    // 3. Organisches Straßennetz: sanft mäandernde Linien (keine starren Geraden),
    //    grob an theta/perp ausgerichtet mit Winkel-Jitter → wirkt wie echte Straßen.
    void windingRoad(
      double sx,
      double sy,
      double angle,
      double length,
      int steps,
      double width,
      Color color,
    ) {
      final path = Path()..moveTo(sx, sy);
      var px = sx, py = sy, a = angle;
      final seg = length / steps;
      for (var i = 0; i < steps; i++) {
        a += (rnd.nextDouble() - 0.5) * 0.34;
        px += math.cos(a) * seg;
        py += math.sin(a) * seg;
        path.lineTo(px, py);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    for (var i = 0; i < 8; i++) {
      final a = (i.isEven ? theta : perp) + (rnd.nextDouble() - 0.5) * 0.6;
      windingRoad(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
        a,
        size.width * (0.45 + rnd.nextDouble() * 0.5),
        4,
        0.8,
        const Color(0xFF3C4350),
      );
    }
    for (var i = 0; i < 3; i++) {
      final a = (i.isEven ? theta : perp) + (rnd.nextDouble() - 0.5) * 0.4;
      final cx = (0.25 + rnd.nextDouble() * 0.5) * size.width;
      final cy = (0.25 + rnd.nextDouble() * 0.5) * size.height;
      windingRoad(
        cx - math.cos(a) * diag * 0.45,
        cy - math.sin(a) * diag * 0.45,
        a,
        diag * 0.9,
        6,
        1.4,
        const Color(0xFF4A5161),
      );
    }
    for (var i = 0; i < 2; i++) {
      final a = (i == 0 ? theta : perp) + (rnd.nextDouble() - 0.5) * 0.22;
      final cx = (0.3 + rnd.nextDouble() * 0.4) * size.width;
      final cy = (0.3 + rnd.nextDouble() * 0.4) * size.height;
      windingRoad(
        cx - math.cos(a) * diag * 0.6,
        cy - math.sin(a) * diag * 0.6,
        a,
        diag * 1.25,
        7,
        2.3,
        const Color(0xFF595F71),
      );
    }

    // 4. Route: Glow → Casing → Linie → Punkte.
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: 0.22)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..strokeWidth = 4.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final isLoop =
        coordinates.length >= 2 && (pts.first - pts.last).distance < 6.0;
    void dot(Offset p, Color fill) {
      canvas.drawCircle(p, 3.4, Paint()..color = _land);
      canvas.drawCircle(p, 2.4, Paint()..color = fill);
    }

    if (isLoop) {
      dot(pts.first, accent);
    } else {
      dot(pts.first, const Color(0xFF34D399));
      dot(pts.last, accent);
    }
  }

  List<Offset> _projectRoute(Size size) {
    double minLon = double.infinity, maxLon = -double.infinity;
    double minLat = double.infinity, maxLat = -double.infinity;
    for (final c in coordinates) {
      if (c[0] < minLon) minLon = c[0];
      if (c[0] > maxLon) maxLon = c[0];
      if (c[1] < minLat) minLat = c[1];
      if (c[1] > maxLat) maxLat = c[1];
    }
    final lonRange = (maxLon - minLon).abs();
    final latRange = (maxLat - minLat).abs();
    const padding = 11.0;
    final dw = size.width - padding * 2;
    final dh = size.height - padding * 2;
    final scale = math.min(
      lonRange > 0 ? dw / lonRange : 1.0,
      latRange > 0 ? dh / latRange : 1.0,
    );
    final ox = padding + (dw - lonRange * scale) / 2;
    final oy = padding + (dh - latRange * scale) / 2;
    return coordinates
        .map(
          (c) => Offset(
            ox + (c[0] - minLon) * scale,
            oy + (maxLat - c[1]) * scale,
          ),
        )
        .toList();
  }

  List<Offset> _genericRoute(Size size, math.Random rnd) {
    const padding = 14.0;
    final w = size.width - padding * 2;
    final h = size.height - padding * 2;
    const n = 5;
    return List.generate(n, (i) {
      final t = i / (n - 1);
      return Offset(
        padding + t * w,
        padding + (0.2 + rnd.nextDouble() * 0.6) * h,
      );
    });
  }

  @override
  bool shouldRepaint(covariant _RouteMiniMapPainter old) =>
      old.seed != seed ||
      old.coordinates != coordinates ||
      old.accent != accent;
}
