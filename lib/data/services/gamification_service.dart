import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/domain/models/badge.dart';
import 'package:cruise_connect/domain/models/user_drive_session.dart';
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

class DriveSessionTotals {
  const DriveSessionTotals({
    required this.totalRoutes,
    required this.totalDistanceKm,
    required this.totalSeconds,
    required this.totalXp,
  });

  final int totalRoutes;
  final double totalDistanceKm;
  final double totalSeconds;
  final int totalXp;
}

/// Service für XP-, Level- und Badge-System mit Supabase-Backend.
class GamificationService {
  static SupabaseClient get _db => Supabase.instance.client;

  static const int xpPerDrivenKm = 10;
  static const double minRouteProgressForXp = 0.20;
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

  /// Berechnet XP für eine einzelne Fahrt.
  /// Quelle ist ausschließlich die tatsächlich gefahrene Distanz: 10 XP/km.
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
    final distanceXp = calculateDriveXp(distanceKm);
    final safeStreakDays = math.max(1, streakDays);
    return RouteXpBreakdown(
      distanceXp: distanceXp,
      curveXp: 0,
      styleBonus: 0,
      baseXp: distanceXp,
      streakDays: safeStreakDays,
      multiplier: 1.0,
      totalXp: distanceXp,
    );
  }

  static int calculateDriveXp(double distanceKm) {
    return (math.max(0, distanceKm) * xpPerDrivenKm).round();
  }

  static double completionCreditProgressStep(
    double progressRatio, {
    bool completed = false,
  }) {
    return progressRatio.clamp(0.0, 1.0).toDouble();
  }

  static double creditedDistanceKmForProgress({
    required double plannedDistanceKm,
    required double progressRatio,
    bool completed = false,
  }) {
    if (plannedDistanceKm <= 0) return 0;
    final progress = completionCreditProgressStep(
      progressRatio,
      completed: completed,
    );
    if (progress < minRouteProgressForXp) return 0;
    return plannedDistanceKm * progress;
  }

  static double streakMultiplierForDays(int streakDays) {
    return 1.0;
  }

  static int calculateDrivingStreakDays(
    Iterable<UserDriveSession> sessions, {
    DateTime? now,
  }) {
    final today = _dateOnly((now ?? DateTime.now()).toLocal());
    final driveDays = _driveDays(sessions);
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
    Iterable<UserDriveSession> existingSessions, {
    DateTime? rideDate,
  }) {
    final rideDay = _dateOnly((rideDate ?? DateTime.now()).toLocal());
    final driveDays = _driveDays(existingSessions)..add(rideDay);

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
          .from('user_drive_sessions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      final sessions = (data as List)
          .map((row) => UserDriveSession.fromJson(row as Map<String, dynamic>))
          .toList();
      return calculateStreakDaysForRide(sessions, rideDate: rideDate);
    } catch (e) {
      debugPrint('[Gamification] Streak-Abfrage fehlgeschlagen: $e');
      return 1;
    }
  }

  static Set<DateTime> _driveDays(Iterable<UserDriveSession> sessions) {
    return sessions
        .where((session) => session.distanceKm > 0)
        .map((session) => _dateOnly(session.createdAt.toLocal()))
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

  @visibleForTesting
  static DriveSessionTotals summarizeDriveSessions(
    Iterable<UserDriveSession> sessions,
  ) {
    double totalKm = 0;
    double totalSecs = 0;
    int totalXp = 0;
    int totalRoutes = 0;

    for (final session in sessions) {
      if (session.distanceKm <= 0 && session.xpAwarded <= 0) continue;
      totalRoutes++;
      totalKm += math.max(0, session.distanceKm);
      totalSecs += math.max(0, session.durationSeconds);
      totalXp += math.max(
        0,
        session.xpAwarded > 0
            ? session.xpAwarded
            : calculateDriveXp(session.distanceKm),
      );
    }

    return DriveSessionTotals(
      totalRoutes: totalRoutes,
      totalDistanceKm: totalKm,
      totalSeconds: totalSecs,
      totalXp: totalXp,
    );
  }

  @visibleForTesting
  static Map<String, dynamic> buildDriveSessionInsert({
    required String userId,
    required double distanceKm,
    required int durationSeconds,
    required bool completedAtEnd,
    String? routeId,
    String? routeStyle,
    String? routeType,
    String? routeFingerprint,
    String source = 'navigation',
  }) {
    final safeDistanceKm = math.max(0.0, distanceKm);
    return {
      'user_id': userId,
      if (routeId?.trim().isNotEmpty == true) 'route_id': routeId!.trim(),
      'distance_km': double.parse(safeDistanceKm.toStringAsFixed(3)),
      'duration_seconds': math.max(0, durationSeconds),
      'xp_awarded': calculateDriveXp(safeDistanceKm),
      'completed_at_end': completedAtEnd,
      if (routeStyle?.trim().isNotEmpty == true)
        'route_style': routeStyle!.trim(),
      if (routeType?.trim().isNotEmpty == true) 'route_type': routeType!.trim(),
      if (routeFingerprint?.trim().isNotEmpty == true)
        'route_fingerprint': routeFingerprint!.trim(),
      'source': source,
    };
  }

  static Future<UserDriveSession?> recordDriveSession({
    required double distanceKm,
    required int durationSeconds,
    required bool completedAtEnd,
    String? routeId,
    String? routeStyle,
    String? routeType,
    String? routeFingerprint,
    String source = 'navigation',
  }) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null || distanceKm <= 0) return null;

    final row = buildDriveSessionInsert(
      userId: userId,
      distanceKm: distanceKm,
      durationSeconds: durationSeconds,
      completedAtEnd: completedAtEnd,
      routeId: routeId,
      routeStyle: routeStyle,
      routeType: routeType,
      routeFingerprint: routeFingerprint,
      source: source,
    );

    try {
      final data = await _db
          .from('user_drive_sessions')
          .insert(row)
          .select()
          .single();
      return UserDriveSession.fromJson(data);
    } catch (e) {
      debugPrint(
        '[Gamification] Drive-Session konnte nicht gespeichert werden: $e',
      );
      rethrow;
    }
  }

  static Future<List<UserDriveSession>> getDriveSessions({int? limit}) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return const [];

    try {
      var query = _db
          .from('user_drive_sessions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      if (limit != null) {
        query = query.limit(limit);
      }
      final data = await query;
      return (data as List)
          .map((row) => UserDriveSession.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint(
        '[Gamification] Drive-Sessions konnten nicht geladen werden: $e',
      );
      return const [];
    }
  }

  /// Berechnet Level und Badges basierend auf immutable Drive-Sessions.
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

    // 1. Alle Drive-Sessions laden. Gespeicherte Routen sind nicht XP-Quelle.
    List<UserDriveSession> sessions;
    try {
      sessions = await getDriveSessions();
    } catch (e) {
      debugPrint('[Gamification] Drive-Session-Abfrage fehlgeschlagen: $e');
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

    // 2. Statistiken berechnen
    final totals = summarizeDriveSessions(sessions);
    final totalKm = totals.totalDistanceKm;
    final totalSecs = totals.totalSeconds;
    final totalXp = totals.totalXp;
    final totalRoutes = totals.totalRoutes;
    final completedSessions = sessions
        .where((session) => session.completedAtEnd)
        .toList();

    // 3. Level aus XP berechnen
    final level = UserLevel.fromXp(totalXp.toDouble());

    final extraCounts = await Future.wait<int>([
      _countCreatedGroups(userId),
      _countRoutePosts(userId),
      _countSavedRouteReferences(userId),
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
    if (completedSessions.isNotEmpty) currentlyQualifiedBadges.add('badge_02');
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
            'total_routes': totalRoutes,
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
      totalRoutes: totalRoutes,
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

  static Future<int> _countSavedRouteReferences(String userId) async {
    final routeIds = <String>{};

    try {
      final rows = await _db
          .from('routes')
          .select('id, source_route_id')
          .eq('user_id', userId);
      for (final row in (rows as List).whereType<Map>()) {
        final sourceRouteId = row['source_route_id'] as String?;
        final routeId = sourceRouteId?.trim().isNotEmpty == true
            ? sourceRouteId!.trim()
            : row['id'] as String?;
        if (routeId != null && routeId.trim().isNotEmpty) {
          routeIds.add(routeId.trim());
        }
      }
    } catch (e) {
      debugPrint(
        '[Gamification] Gespeicherte Routen-Zaehler fehlgeschlagen: $e',
      );
    }

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
