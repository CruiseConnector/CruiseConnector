import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';

/// CRUD für gespeicherte Routen in der Supabase `routes` Tabelle.
class SavedRoutesService {
  static SupabaseClient get _db => Supabase.instance.client;

  // Cache für wöchentliche Top-Route (1 Stunde gültig)
  static SavedRoute? _cachedWeeklyTopRoute;
  static DateTime? _weeklyTopRouteCacheTime;
  static String? _weeklyTopRouteCacheKey;

  // ─── Wöchentliche Top-Route ──────────────────────────────────────────────

  /// Haversine-Distanz zwischen zwei Koordinaten in Kilometern.
  static double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371.0; // Erdradius in km
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  static double _toRadians(double deg) => deg * (math.pi / 180);

  /// Gibt die beste bewertete Route dieser Woche in der Nähe des Users zurück.
  /// Sucht zuerst im 50km-Radius, dann 100km, dann ohne Distanzfilter.
  /// Ergebnis wird 1 Stunde gecacht.
  static Future<SavedRoute?> getWeeklyTopRoute({
    required double userLat,
    required double userLng,
  }) async {
    final cacheKey = _buildWeeklyTopCacheKey(
      userLat: userLat,
      userLng: userLng,
    );
    // Cache prüfen (1 Stunde)
    if (_cachedWeeklyTopRoute != null &&
        _weeklyTopRouteCacheTime != null &&
        _weeklyTopRouteCacheKey == cacheKey) {
      final age = DateTime.now().difference(_weeklyTopRouteCacheTime!);
      if (age.inMinutes < 60) return _cachedWeeklyTopRoute;
    }

    try {
      // Wochenstart berechnen (Montag 00:00)
      final now = DateTime.now();
      final weekStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));

      // Alle Routen mit Rating >= 3 aus dieser Woche laden
      final data = await _db
          .from('routes')
          .select()
          .gte('rating', 3)
          .gte('created_at', weekStart.toIso8601String())
          .order('rating', ascending: false)
          .order('created_at', ascending: false);

      final weeklyRoutes = (data as List)
          .map((row) => SavedRoute.fromJson(row as Map<String, dynamic>))
          .where((route) => route.isRecommendationEligible)
          .toList();

      // Beste Route im 50km-Radius finden
      SavedRoute? best = _findBestInRadius(weeklyRoutes, userLat, userLng, 50);

      // Fallback: 100km-Radius
      best ??= _findBestInRadius(weeklyRoutes, userLat, userLng, 100);

      // Fallback: beste Route der Woche ohne Distanzfilter
      if (best == null && weeklyRoutes.isNotEmpty) {
        best = weeklyRoutes.first;
      }

      // Letzter Fallback: insgesamt beste bewertete Route (kein Wochenfilter)
      if (best == null) {
        final allData = await _db
            .from('routes')
            .select()
            .gte('rating', 3)
            .order('rating', ascending: false)
            .limit(1);

        final allRoutes = (allData as List)
            .map((row) => SavedRoute.fromJson(row as Map<String, dynamic>))
            .toList();
        if (allRoutes.isNotEmpty) best = allRoutes.first;
      }

      // Ergebnis cachen
      _cachedWeeklyTopRoute = best;
      _weeklyTopRouteCacheTime = DateTime.now();
      _weeklyTopRouteCacheKey = cacheKey;

      return best;
    } catch (e) {
      debugPrint('[SavedRoutes] getWeeklyTopRoute Fehler: $e');
      return null;
    }
  }

  static String _buildWeeklyTopCacheKey({
    required double userLat,
    required double userLng,
  }) {
    final now = DateTime.now();
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final latBucket = userLat.toStringAsFixed(1);
    final lngBucket = userLng.toStringAsFixed(1);
    return '${weekStart.toIso8601String()}|$latBucket|$lngBucket';
  }

  static void invalidateWeeklyTopRouteCache() {
    _cachedWeeklyTopRoute = null;
    _weeklyTopRouteCacheTime = null;
    _weeklyTopRouteCacheKey = null;
  }

  static bool hasEquivalentSavedRoute(
    SavedRoute route,
    Iterable<SavedRoute> savedRoutes,
  ) {
    final routeSignature = route.routeSignature;
    for (final savedRoute in savedRoutes) {
      if (savedRoute.id == route.id) return true;
      if (savedRoute.sourceRouteId == route.id) return true;
      if (savedRoute.routeSignature == routeSignature) return true;
    }
    return false;
  }

  /// Findet die beste bewertete Route innerhalb eines Radius (in km).
  static SavedRoute? _findBestInRadius(
    List<SavedRoute> routes,
    double userLat,
    double userLng,
    double radiusKm,
  ) {
    for (final route in routes) {
      final coords = _getFirstCoordinate(route);
      if (coords == null) continue;
      // coords ist [longitude, latitude] (Mapbox-Format)
      final distance = _haversineDistance(
        userLat,
        userLng,
        coords[1],
        coords[0],
      );
      if (distance <= radiusKm) return route;
    }
    return null;
  }

  /// Extrahiert die erste Koordinate aus der Route-Geometrie.
  /// Gibt [longitude, latitude] zurück oder null.
  static List<double>? _getFirstCoordinate(SavedRoute route) {
    try {
      final geometry = route.geometry;
      final coordinates = geometry['coordinates'];
      if (coordinates is List && coordinates.isNotEmpty) {
        final first = coordinates[0];
        if (first is List && first.length >= 2) {
          return [(first[0] as num).toDouble(), (first[1] as num).toDouble()];
        }
      }
    } catch (_) {}
    return null;
  }

  // ─── Speichern ────────────────────────────────────────────────────────────

  /// Speichert eine Route für den eingeloggten User.
  /// Tut nichts, wenn kein User eingeloggt ist.
  static Future<void> saveRoute({
    required RouteResult result,
    required String style,
    required bool isRoundTrip,
    String? customName,
    int? rating,
    double? drivenKm,
    double? plannedDistanceKm,
  }) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;

    final routeType = isRoundTrip ? 'ROUND_TRIP' : 'POINT_TO_POINT';
    final name = (customName?.trim().isNotEmpty == true)
        ? customName!.trim()
        : '$style ${isRoundTrip ? 'Rundkurs' : 'Route'}';

    final actualDistanceKm =
        result.distanceKm ??
        (result.distanceMeters != null ? result.distanceMeters! / 1000 : 0.0);
    final effectiveDrivenKm = drivenKm ?? actualDistanceKm;
    final effectivePlannedKm = plannedDistanceKm ?? actualDistanceKm;

    final row = <String, dynamic>{
      'user_id': userId,
      'name': name,
      'style': style,
      'route_type': routeType,
      'distance_target': effectivePlannedKm.round(),
      'distance_actual': actualDistanceKm,
      'duration_seconds': result.durationSeconds?.round(),
      'geometry': result.geometry,
      'driven_km': effectiveDrivenKm,
    };
    if (rating != null && rating > 0) row['rating'] = rating;

    try {
      await _db.from('routes').insert(row);
      invalidateWeeklyTopRouteCache();
    } on PostgrestException catch (e) {
      // Fallback: Falls 'name' Spalte noch nicht existiert, ohne speichern
      if (e.code == 'PGRST204' && e.message.contains('name')) {
        debugPrint('[SavedRoutes] name-Spalte fehlt, speichere ohne name');
        row.remove('name');
        await _db.from('routes').insert(row);
        invalidateWeeklyTopRouteCache();
      } else {
        rethrow;
      }
    }
  }

  /// Speichert eine bestehende Route (z.B. empfohlene Route) für den aktuellen User.
  static Future<void> saveExistingRoute(SavedRoute route) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;

    final row = <String, dynamic>{
      'user_id': userId,
      'name': route.name ?? '${route.styleEmoji} ${route.style}',
      'style': route.style,
      'route_type': route.routeType ?? 'ROUND_TRIP',
      'distance_target': (route.distanceTargetKm ?? route.distanceKm).round(),
      'distance_actual': route.distanceKm,
      'duration_seconds': route.durationSeconds?.round(),
      'geometry': route.geometry,
      'source_route_id': route.id,
    };

    try {
      await _db.from('routes').insert(row);
      invalidateWeeklyTopRouteCache();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204' && e.message.contains('source_route_id')) {
        debugPrint(
          '[SavedRoutes] source_route_id-Spalte fehlt, speichere Empfehlung ohne Herkunfts-ID',
        );
        row.remove('source_route_id');
        await _db.from('routes').insert(row);
        invalidateWeeklyTopRouteCache();
      } else {
        rethrow;
      }
    }
  }

  /// Prüft ob eine Route (anhand ID) dem aktuellen User gehört / gespeichert ist.
  static Future<bool> isRouteSavedByUser(String routeId) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final data = await _db
          .from('routes')
          .select('id')
          .eq('id', routeId)
          .eq('user_id', userId)
          .maybeSingle();
      return data != null;
    } catch (e) {
      debugPrint('[SavedRoutes] isRouteSavedByUser Fehler: $e');
      return false;
    }
  }

  // ─── Laden ────────────────────────────────────────────────────────────────

  /// Gibt alle gespeicherten Routen des eingeloggten Users zurück,
  /// neueste zuerst. Gibt leere Liste bei Fehler zurück.
  static Future<List<SavedRoute>> getUserRoutes() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return const [];

    try {
      final data = await _db
          .from('routes')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (data as List)
          .map((row) => SavedRoute.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[SavedRoutes] getUserRoutes Fehler: $e');
      return const [];
    }
  }

  // ─── Beliebte Routen ────────────────────────────────────────────────────

  /// Gibt beliebte Routen anderer Nutzer zurück (ähnlicher Stil, gute Bewertung).
  /// Kann als Vorschlag für neue Nutzer verwendet werden.
  static Future<List<SavedRoute>> getPopularRoutes({
    String? style,
    int limit = 10,
  }) async {
    try {
      // Basisquery einmal aufbauen, dann optional nach Stil filtern (DRY)
      var query = _db.from('routes').select().gte('rating', 3);
      if (style != null) {
        query = query.eq('style', style);
      }
      final data = await query
          .order('rating', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);

      return (data as List)
          .map((row) => SavedRoute.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[SavedRoutes] getPopularRoutes Fehler: $e');
      return const [];
    }
  }

  // ─── Einzelne Route laden ─────────────────────────────────────────────────

  /// Lädt eine einzelne Route anhand ihrer ID.
  static Future<SavedRoute?> getRouteById(String id) async {
    try {
      final data = await _db.from('routes').select().eq('id', id).maybeSingle();
      if (data == null) return null;
      return SavedRoute.fromJson(data);
    } catch (e) {
      debugPrint('[SavedRoutes] getRouteById Fehler: $e');
      return null;
    }
  }

  // ─── Löschen ─────────────────────────────────────────────────────────────

  /// Löscht eine Route anhand ihrer ID.
  static Future<void> deleteRoute(String id) async {
    try {
      await _db.from('routes').delete().eq('id', id);
      invalidateWeeklyTopRouteCache();
    } catch (e) {
      debugPrint('[SavedRoutes] deleteRoute Fehler: $e');
      rethrow; // UI soll informiert werden, dass Löschen fehlschlug
    }
  }
}
