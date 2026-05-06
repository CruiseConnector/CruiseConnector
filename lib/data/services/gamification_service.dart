import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/domain/models/badge.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/domain/models/user_level.dart';

/// Ergebnis der Gamification-Berechnung.
class GamificationResult {
  const GamificationResult({
    required this.level,
    required this.earnedBadgeIds,
    required this.newBadgeIds,
    required this.totalRoutes,
    required this.totalDistanceKm,
    required this.totalHours,
    required this.totalXp,
  });

  final UserLevel level;
  final List<String> earnedBadgeIds;
  final List<String> newBadgeIds;
  final int totalRoutes;
  final double totalDistanceKm;
  final double totalHours;
  final int totalXp;

  List<Badge> get earnedBadges =>
      earnedBadgeIds.map(Badge.getById).whereType<Badge>().toList();

  List<Badge> get newBadges =>
      newBadgeIds.map(Badge.getById).whereType<Badge>().toList();
}

class RouteXpBreakdown {
  const RouteXpBreakdown({
    required this.distanceXp,
    required this.curveXp,
    required this.styleBonus,
    required this.baseXp,
    required this.streakDays,
    required this.multiplier,
    required this.totalXp,
  });

  final int distanceXp;
  final int curveXp;
  final int styleBonus;
  final int baseXp;
  final int streakDays;
  final double multiplier;
  final int totalXp;

  String get multiplierLabel => 'x${multiplier.toStringAsFixed(2)}';
}

/// Service für XP-, Level- und Badge-System mit Supabase-Backend.
class GamificationService {
  static SupabaseClient get _db => Supabase.instance.client;

  static const int xpPerDrivenKm = 10;
  static const int xpPerCurve = 2;
  static const int maxCurveXp = 80;
  static const double streakStep = 0.05;
  static const double maxStreakMultiplier = 1.30;
  static const double xpCreditStep = 0.20;
  static const Map<String, String> _legacyBadgeIds = {'route_1': 'badge_02'};

  @visibleForTesting
  static List<String> normalizeBadgeIds(Iterable<dynamic> badgeIds) {
    final activeBadgeIds = Badge.all.map((badge) => badge.id).toSet();
    final normalized = <String>{};

    for (final raw in badgeIds) {
      final id = raw?.toString().trim();
      if (id == null || id.isEmpty) continue;
      final mappedId = _legacyBadgeIds[id] ?? id;
      if (activeBadgeIds.contains(mappedId)) {
        normalized.add(mappedId);
      }
    }

    return [
      for (final badge in Badge.all)
        if (normalized.contains(badge.id)) badge.id,
    ];
  }

  @visibleForTesting
  static List<String> mergeBadgeIds(
    Iterable<dynamic> previousBadgeIds,
    Iterable<dynamic> currentBadgeIds,
  ) {
    return normalizeBadgeIds([...previousBadgeIds, ...currentBadgeIds]);
  }

  @visibleForTesting
  static List<String> newlyQualifiedBadgeIds(
    Iterable<dynamic> previousBadgeIds,
    Iterable<dynamic> currentBadgeIds,
  ) {
    final previousBadgeSet = normalizeBadgeIds(previousBadgeIds).toSet();
    return normalizeBadgeIds(
      currentBadgeIds,
    ).where((badgeId) => !previousBadgeSet.contains(badgeId)).toList();
  }

  /// Berechnet XP für eine einzelne Route.
  /// 10 XP/km + 5 XP/Kurve + Stil-Bonus.
  static int calculateRouteXp({
    required double distanceKm,
    required int curves,
    required String style,
    int streakDays = 1,
  }) {
    return calculateRouteXpBreakdown(
      distanceKm: distanceKm,
      curves: curves,
      style: style,
      streakDays: streakDays,
    ).totalXp;
  }

  static RouteXpBreakdown calculateRouteXpBreakdown({
    required double distanceKm,
    required int curves,
    required String style,
    int streakDays = 1,
  }) {
    final distanceXp = (math.max(0, distanceKm) * xpPerDrivenKm).round();
    final curveXp = math.min(math.max(0, curves) * xpPerCurve, maxCurveXp);
    int styleBonus = 0;
    switch (style) {
      case 'Kurvenjagd':
        styleBonus = 15;
        break;
      case 'Entdecker':
        styleBonus = 12;
        break;
      case 'Sport Mode':
        styleBonus = 10;
        break;
      case 'Abendrunde':
        styleBonus = 8;
        break;
    }
    final baseXp = distanceXp + curveXp + styleBonus;
    final safeStreakDays = math.max(1, streakDays);
    final multiplier = streakMultiplierForDays(safeStreakDays);
    return RouteXpBreakdown(
      distanceXp: distanceXp,
      curveXp: curveXp,
      styleBonus: styleBonus,
      baseXp: baseXp,
      streakDays: safeStreakDays,
      multiplier: multiplier,
      totalXp: (baseXp * multiplier).round(),
    );
  }

  static double completionCreditProgressStep(
    double progressRatio, {
    bool completed = false,
  }) {
    if (completed) return 1.0;
    final safeProgress = progressRatio.clamp(0.0, 1.0);
    final steps = ((safeProgress + 1e-9) / xpCreditStep).floor();
    final maxSteps = (1 / xpCreditStep).round();
    final boundedSteps = steps.clamp(0, maxSteps);
    return boundedSteps / maxSteps;
  }

  static double creditedDistanceKmForProgress({
    required double plannedDistanceKm,
    required double progressRatio,
    bool completed = false,
  }) {
    if (plannedDistanceKm <= 0) return 0;
    final creditProgress = completionCreditProgressStep(
      progressRatio,
      completed: completed,
    );
    return plannedDistanceKm * creditProgress;
  }

  static double streakMultiplierForDays(int streakDays) {
    final safeDays = math.max(1, streakDays);
    final bonus = math.min(
      (safeDays - 1) * streakStep,
      maxStreakMultiplier - 1,
    );
    return double.parse((1 + bonus).toStringAsFixed(2));
  }

  static int calculateDrivingStreakDays(
    Iterable<SavedRoute> routes, {
    DateTime? now,
  }) {
    final today = _dateOnly((now ?? DateTime.now()).toLocal());
    final driveDays = _driveDays(routes);
    if (driveDays.isEmpty) return 0;

    var checkDay = today;
    if (!driveDays.contains(checkDay)) {
      checkDay = checkDay.subtract(const Duration(days: 1));
    }

    var streak = 0;
    while (driveDays.contains(checkDay)) {
      streak++;
      checkDay = checkDay.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static int calculateStreakDaysForRide(
    Iterable<SavedRoute> existingRoutes, {
    DateTime? rideDate,
  }) {
    final rideDay = _dateOnly((rideDate ?? DateTime.now()).toLocal());
    final driveDays = _driveDays(existingRoutes)..add(rideDay);

    var streak = 0;
    var checkDay = rideDay;
    while (driveDays.contains(checkDay)) {
      streak++;
      checkDay = checkDay.subtract(const Duration(days: 1));
    }
    return math.max(1, streak);
  }

  static Future<int> getStreakDaysForNextRide({DateTime? rideDate}) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return 1;

    try {
      final data = await _db
          .from('routes')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      final routes = (data as List)
          .map((row) => SavedRoute.fromJson(row as Map<String, dynamic>))
          .toList();
      return calculateStreakDaysForRide(routes, rideDate: rideDate);
    } catch (e) {
      debugPrint('[Gamification] Streak-Abfrage fehlgeschlagen: $e');
      return 1;
    }
  }

  static Set<DateTime> _driveDays(Iterable<SavedRoute> routes) {
    return routes
        .where((route) => route.isDrivenSession)
        .map((route) => _dateOnly(route.createdAt.toLocal()))
        .toSet();
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Zählt echte Kurven anhand von Richtungswechseln > 30° in Koordinaten.
  static int countCurves(List<List<double>> coords) {
    if (coords.length < 3) return 0;
    int curves = 0;
    const step = 20;
    for (var i = step; i < coords.length - step; i += step) {
      final prev = coords[i - step];
      final curr = coords[i];
      final next = coords[math.min(i + step, coords.length - 1)];
      final bearing1 = math.atan2(curr[0] - prev[0], curr[1] - prev[1]);
      final bearing2 = math.atan2(next[0] - curr[0], next[1] - curr[1]);
      var angle = (bearing2 - bearing1).abs();
      if (angle > math.pi) angle = 2 * math.pi - angle;
      if (angle * 180 / math.pi > 30) curves++;
    }
    return curves;
  }

  /// Async-Version: Zählt Kurven in einem separaten Isolate (Main-Thread bleibt frei).
  static Future<int> countCurvesAsync(List<List<double>> coords) {
    if (coords.length < 100) return Future.value(countCurves(coords));
    return compute(_countCurvesIsolate, coords);
  }

  static int _countCurvesIsolate(List<List<double>> coords) =>
      countCurves(coords);

  /// Berechnet Level und Badges basierend auf allen Routen des Users.
  /// Speichert den Fortschritt in der `profiles`-Tabelle.
  static Future<GamificationResult> calculateAndSync() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      return GamificationResult(
        level: UserLevel.fromXp(0),
        earnedBadgeIds: const [],
        newBadgeIds: const [],
        totalRoutes: 0,
        totalDistanceKm: 0,
        totalHours: 0,
        totalXp: 0,
      );
    }

    // 1. Alle Routen laden
    List<SavedRoute> routes;
    try {
      final data = await _db
          .from('routes')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      routes = (data as List)
          .map((row) => SavedRoute.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Gamification] Routen-Abfrage fehlgeschlagen: $e');
      return GamificationResult(
        level: UserLevel.fromXp(0),
        earnedBadgeIds: const [],
        newBadgeIds: const [],
        totalRoutes: 0,
        totalDistanceKm: 0,
        totalHours: 0,
        totalXp: 0,
      );
    }

    final rideRoutes = routes.where((route) => route.isDrivenSession).toList();
    final xpEligibleRoutes = rideRoutes
        .where((route) => route.qualifiesForXpCredit)
        .toList();
    final completedRoutes = rideRoutes
        .where((route) => route.isFullyCompleted)
        .toList();
    final completedGroupRoutes = completedRoutes
        .where((route) => route.groupId?.trim().isNotEmpty == true)
        .toList();

    // 2. Statistiken berechnen
    double totalKm = 0;
    double totalSecs = 0;
    int totalXp = 0;

    for (final r in rideRoutes) {
      totalKm += r.actualDistanceKm;
      totalSecs += r.durationSeconds ?? 0;
    }

    final sortedXpRoutes = xpEligibleRoutes.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final r in sortedXpRoutes) {
      if (r.xpAwarded != null) {
        totalXp += r.xpAwarded!;
      } else {
        final creditedDistanceKm = r.xpCreditedDistanceKm;
        final estimatedCurves = (creditedDistanceKm / 5).round();
        totalXp += calculateRouteXp(
          distanceKm: creditedDistanceKm,
          curves: estimatedCurves,
          style: r.style,
        );
      }
    }

    // 3. Level aus XP berechnen
    final level = UserLevel.fromXp(totalXp.toDouble());

    final extraCounts = await Future.wait<int>([
      _countCreatedGroups(userId),
      _countRoutePosts(userId),
      _countSavedRouteReferences(userId, routes),
    ]);
    final createdGroupCount = extraCounts[0];
    final routePostCount = extraCounts[1];
    final savedRouteReferenceCount = extraCounts[2];

    // 4. Badges prüfen
    final currentlyQualifiedBadges = <String>[];

    // Level-Badges
    if (level.level >= 10) currentlyQualifiedBadges.add('badge_01');
    if (level.level >= 25) currentlyQualifiedBadges.add('badge_03');
    if (level.level >= 50) currentlyQualifiedBadges.add('badge_08');
    if (level.level >= UserLevel.maxLevel) {
      currentlyQualifiedBadges.add('badge_14');
    }

    // Routen- und Gruppen-Badges
    if (completedRoutes.isNotEmpty) currentlyQualifiedBadges.add('badge_02');
    if (completedGroupRoutes.length >= 5) {
      currentlyQualifiedBadges.add('badge_04');
    }
    if (routePostCount >= 1) currentlyQualifiedBadges.add('badge_05');
    if (createdGroupCount >= 1) currentlyQualifiedBadges.add('badge_07');
    if (savedRouteReferenceCount >= 5) {
      currentlyQualifiedBadges.add('badge_09');
    }

    // Distanz-Badges
    if (totalKm >= 500) currentlyQualifiedBadges.add('badge_06');
    if (totalKm >= 2500) currentlyQualifiedBadges.add('badge_10');
    if (totalKm >= 10000) currentlyQualifiedBadges.add('badge_13');

    // 5. Bisherige Badges laden und neue bestimmen
    List<String> previousBadges = [];
    try {
      final profile = await _db
          .from('profiles')
          .select('badges')
          .eq('id', userId)
          .maybeSingle();

      final rawBadges = profile?['badges'];
      if (rawBadges is Iterable) {
        previousBadges = normalizeBadgeIds(rawBadges);
      }
    } catch (e) {
      debugPrint('[Gamification] Badges-Abfrage fehlgeschlagen: $e');
    }

    final qualifiedBadges = normalizeBadgeIds(currentlyQualifiedBadges);
    final unlockedBadges = mergeBadgeIds(previousBadges, qualifiedBadges);
    final newBadges = newlyQualifiedBadgeIds(previousBadges, qualifiedBadges);

    // 6. Fortschritt im Backend speichern
    try {
      await _db
          .from('profiles')
          .update({
            'level': level.level,
            'total_km': totalKm,
            'total_xp': totalXp,
            'total_routes': completedRoutes.length,
            'badges': unlockedBadges,
          })
          .eq('id', userId);
    } catch (e) {
      debugPrint('[Gamification] Profil-Update fehlgeschlagen: $e');
    }

    return GamificationResult(
      level: level,
      earnedBadgeIds: unlockedBadges,
      newBadgeIds: newBadges,
      totalRoutes: completedRoutes.length,
      totalDistanceKm: totalKm,
      totalHours: totalSecs / 3600,
      totalXp: totalXp,
    );
  }

  static Future<int> _countCreatedGroups(String userId) async {
    try {
      final rows = await _db
          .from('groups')
          .select('id')
          .eq('created_by', userId)
          .limit(2);
      return (rows as List).length;
    } catch (e) {
      debugPrint('[Gamification] Gruppen-Zaehler fehlgeschlagen: $e');
      return 0;
    }
  }

  static Future<int> _countRoutePosts(String userId) async {
    try {
      final rows = await _db
          .from('posts')
          .select('shared_route_id')
          .eq('user_id', userId);
      return (rows as List)
          .whereType<Map>()
          .where((row) => row['shared_route_id'] != null)
          .length;
    } catch (e) {
      debugPrint('[Gamification] Routenpost-Zaehler fehlgeschlagen: $e');
      return 0;
    }
  }

  static Future<int> _countSavedRouteReferences(
    String userId,
    List<SavedRoute> routes,
  ) async {
    final routeIds = <String>{
      for (final route in routes)
        if (route.sourceRouteId?.trim().isNotEmpty == true)
          route.sourceRouteId!.trim(),
    };

    try {
      final rows = await _db
          .from('route_bookmarks')
          .select('route_id')
          .eq('user_id', userId);
      for (final row in (rows as List).whereType<Map>()) {
        final routeId = row['route_id'] as String?;
        if (routeId != null && routeId.trim().isNotEmpty) {
          routeIds.add(routeId.trim());
        }
      }
    } catch (e) {
      debugPrint('[Gamification] Routen-Speicher-Zaehler fehlgeschlagen: $e');
    }

    return routeIds.length;
  }
}
