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

/// Service für XP-, Level- und Badge-System mit Supabase-Backend.
class GamificationService {
  static SupabaseClient get _db => Supabase.instance.client;

  /// Berechnet XP für eine einzelne Route.
  /// 10 XP/km + 5 XP/Kurve + Stil-Bonus.
  static int calculateRouteXp({
    required double distanceKm,
    required int curves,
    required String style,
  }) {
    final baseXp = (distanceKm * 10).round();
    final curveXp = curves * 5;
    int styleBonus = 0;
    switch (style) {
      case 'Kurvenjagd': styleBonus = 20; break;
      case 'Entdecker': styleBonus = 15; break;
      case 'Sport Mode': styleBonus = 10; break;
    }
    return baseXp + curveXp + styleBonus;
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

  static int _countCurvesIsolate(List<List<double>> coords) => countCurves(coords);

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
    final data = await _db
        .from('routes')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final routes = (data as List)
        .map((row) => SavedRoute.fromJson(row as Map<String, dynamic>))
        .toList();

    // 2. Statistiken berechnen
    double totalKm = 0;
    double totalSecs = 0;
    int totalXp = 0;
    int roundTrips = 0;
    final styleCounts = <String, int>{};
    bool hasLongRoute = false;

    for (final r in routes) {
      totalKm += r.distanceKm;
      totalSecs += r.durationSeconds ?? 0;
      if (r.isRoundTrip) roundTrips++;
      styleCounts[r.style] = (styleCounts[r.style] ?? 0) + 1;
      if (r.distanceKm >= 100) hasLongRoute = true;

      // XP pro Route: 10/km + pauschale für Kurven (geschätzt ~1 Kurve/5km)
      // Exakte Kurven können wir nicht mehr zählen (Geometrie nicht immer geladen),
      // daher schätzen wir basierend auf Distanz und Stil
      final estimatedCurves = (r.distanceKm / 5).round();
      totalXp += calculateRouteXp(
        distanceKm: r.distanceKm,
        curves: estimatedCurves,
        style: r.style,
      );
    }

    // 3. Level aus XP berechnen
    final level = UserLevel.fromXp(totalXp.toDouble());

    // 4. Badges prüfen
    final earned = <String>[];

    // Distanz-Badges
    if (totalKm >= 10) earned.add('dist_10');
    if (totalKm >= 50) earned.add('dist_50');
    if (totalKm >= 100) earned.add('dist_100');
    if (totalKm >= 500) earned.add('dist_500');
    if (totalKm >= 1000) earned.add('dist_1000');
    if (totalKm >= 5000) earned.add('dist_5000');

    // Routen-Badges
    if (routes.isNotEmpty) earned.add('route_1');
    if (routes.length >= 5) earned.add('route_5');
    if (routes.length >= 10) earned.add('route_10');
    if (routes.length >= 25) earned.add('route_25');
    if (routes.length >= 50) earned.add('route_50');

    // Stil-Badges
    if ((styleCounts['Kurvenjagd'] ?? 0) >= 5) earned.add('style_kurven');
    if ((styleCounts['Sport Mode'] ?? 0) >= 5) earned.add('style_sport');
    if ((styleCounts['Abendrunde'] ?? 0) >= 5) earned.add('style_abend');
    if ((styleCounts['Entdecker'] ?? 0) >= 5) earned.add('style_entdecker');

    // Spezial-Badges
    if (roundTrips >= 10) earned.add('special_roundtrip');
    if (hasLongRoute) earned.add('special_long');

    // 5. Bisherige Badges laden und neue bestimmen
    List<String> previousBadges = [];
    try {
      final profile = await _db
          .from('profiles')
          .select('badges')
          .eq('id', userId)
          .maybeSingle();

      if (profile != null && profile['badges'] != null) {
        previousBadges = List<String>.from(profile['badges'] as List);
      }
    } catch (_) {}

    final newBadges = earned.where((b) => !previousBadges.contains(b)).toList();

    // 6. Fortschritt im Backend speichern
    try {
      await _db.from('profiles').update({
        'level': level.level,
        'total_km': totalKm,
        'total_xp': totalXp,
        'total_routes': routes.length,
        'badges': earned,
      }).eq('id', userId);
    } catch (_) {
      // Spalten existieren vielleicht noch nicht — nicht kritisch
    }

    return GamificationResult(
      level: level,
      earnedBadgeIds: earned,
      newBadgeIds: newBadges,
      totalRoutes: routes.length,
      totalDistanceKm: totalKm,
      totalHours: totalSecs / 3600,
      totalXp: totalXp,
    );
  }
}
