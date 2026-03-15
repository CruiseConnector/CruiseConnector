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
  });

  final UserLevel level;
  final List<String> earnedBadgeIds;
  final List<String> newBadgeIds; // Badges die gerade neu verdient wurden
  final int totalRoutes;
  final double totalDistanceKm;
  final double totalHours;

  List<Badge> get earnedBadges =>
      earnedBadgeIds.map(Badge.getById).whereType<Badge>().toList();

  List<Badge> get newBadges =>
      newBadgeIds.map(Badge.getById).whereType<Badge>().toList();
}

/// Service für Level- und Badge-System mit Supabase-Backend.
class GamificationService {
  static SupabaseClient get _db => Supabase.instance.client;

  /// Berechnet Level und Badges basierend auf den Routen des Users.
  /// Speichert/aktualisiert den Fortschritt in der `profiles`-Tabelle.
  static Future<GamificationResult> calculateAndSync() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      return GamificationResult(
        level: UserLevel.fromKm(0),
        earnedBadgeIds: const [],
        newBadgeIds: const [],
        totalRoutes: 0,
        totalDistanceKm: 0,
        totalHours: 0,
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
    int roundTrips = 0;
    final styleCounts = <String, int>{};
    bool hasLongRoute = false;

    for (final r in routes) {
      totalKm += r.distanceKm;
      totalSecs += r.durationSeconds ?? 0;
      if (r.isRoundTrip) roundTrips++;
      styleCounts[r.style] = (styleCounts[r.style] ?? 0) + 1;
      if (r.distanceKm >= 100) hasLongRoute = true;
    }

    // 3. Level berechnen
    final level = UserLevel.fromKm(totalKm);

    // 4. Verdiente Badges berechnen
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

    // 5. Bisherige Badges aus Profil laden und neue bestimmen
    List<String> previousBadges = [];
    try {
      final profile = await _db
          .from('profiles')
          .select('badges, level, total_km')
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
    );
  }
}
