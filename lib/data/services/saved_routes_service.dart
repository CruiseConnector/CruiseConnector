import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/route_quality_validator.dart';
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

  static bool areEquivalentRoutes(SavedRoute first, SavedRoute second) {
    if (first.id == second.id) return true;

    final firstFingerprint = _normalizedRouteFingerprint(first);
    final secondFingerprint = _normalizedRouteFingerprint(second);
    if (firstFingerprint != null &&
        secondFingerprint != null &&
        firstFingerprint == secondFingerprint) {
      return true;
    }

    final firstSource = first.sourceRouteId?.trim();
    final secondSource = second.sourceRouteId?.trim();
    final firstIds = <String>{
      first.id,
      if (firstSource != null && firstSource.isNotEmpty) firstSource,
    };
    final secondIds = <String>{
      second.id,
      if (secondSource != null && secondSource.isNotEmpty) secondSource,
    };

    if (firstIds.intersection(secondIds).isNotEmpty) return true;
    return first.routeSignature == second.routeSignature;
  }

  static String? _normalizedRouteFingerprint(SavedRoute route) {
    final explicit = route.routeFingerprint?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final metaFingerprint =
        route.routeMeta['route_fingerprint']?.toString().trim() ??
        route.routeMeta['fingerprint']?.toString().trim();
    if (metaFingerprint != null && metaFingerprint.isNotEmpty) {
      return metaFingerprint;
    }
    return null;
  }

  static bool hasEquivalentSavedRoute(
    SavedRoute route,
    Iterable<SavedRoute> savedRoutes,
  ) {
    for (final savedRoute in savedRoutes) {
      if (areEquivalentRoutes(route, savedRoute)) return true;
    }
    return false;
  }

  static List<SavedRoute> dedupeEquivalentRoutes(Iterable<SavedRoute> routes) {
    final unique = <SavedRoute>[];
    for (final route in routes) {
      if (!hasEquivalentSavedRoute(route, unique)) {
        unique.add(route);
      }
    }
    return unique;
  }

  @visibleForTesting
  static List<SavedRoute> savedRouteCopiesFromUserRoutes(
    Iterable<SavedRoute> routes,
  ) {
    return dedupeEquivalentRoutes(routes);
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
        final first =
            geometry['type'] == 'MultiLineString' &&
                coordinates.first is List &&
                (coordinates.first as List).isNotEmpty
            ? (coordinates.first as List).first
            : coordinates[0];
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
    int? xpDistance,
    int? xpCurveBonus,
    int? xpStyleBonus,
    int? xpBase,
    double? xpMultiplier,
    int? xpStreakDays,
    int? xpAwarded,
    bool completedAtEnd = false,
    String? groupId,
    String? photoUrl,
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
      if (photoUrl != null && photoUrl.trim().isNotEmpty)
        'photo_url': photoUrl.trim(),
      'driven_km': effectiveDrivenKm,
      'route_source':
          result.edgeMeta['route_source']?.toString() ??
          result.edgeMeta['source']?.toString(),
      'route_fingerprint':
          result.edgeMeta['route_fingerprint']?.toString() ??
          RouteQualityValidator.buildRouteFingerprint(
            _sampleCoordinatesForFingerprint(result.coordinates),
            distanceKm: result.distanceKm,
            precision: 4,
          ),
      'quality_tier': result.edgeMeta['quality_tier']?.toString(),
      'route_meta': result.edgeMeta,
      'completed_at_end': completedAtEnd,
      if (groupId != null && groupId.trim().isNotEmpty)
        'group_id': groupId.trim(),
      if (xpDistance != null) 'xp_distance': xpDistance,
      if (xpCurveBonus != null) 'xp_curve_bonus': xpCurveBonus,
      if (xpStyleBonus != null) 'xp_style_bonus': xpStyleBonus,
      if (xpBase != null) 'xp_base': xpBase,
      if (xpMultiplier != null) 'xp_multiplier': xpMultiplier,
      if (xpStreakDays != null) 'xp_streak_days': xpStreakDays,
      if (xpAwarded != null) 'xp_awarded': xpAwarded,
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
      } else if (e.code == 'PGRST204' &&
          e.message.contains('completed_at_end')) {
        debugPrint(
          '[SavedRoutes] completed_at_end-Spalte fehlt, speichere ohne Completion-Flag',
        );
        row.remove('completed_at_end');
        await _db.from('routes').insert(row);
        invalidateWeeklyTopRouteCache();
      } else if (e.code == 'PGRST204' && e.message.contains('group_id')) {
        debugPrint(
          '[SavedRoutes] group_id-Spalte fehlt, speichere ohne Gruppenbezug',
        );
        row.remove('group_id');
        await _db.from('routes').insert(row);
        invalidateWeeklyTopRouteCache();
      } else if (e.code == 'PGRST204') {
        debugPrint(
          '[SavedRoutes] Route-Meta-Spalten fehlen, speichere ohne Meta: ${e.message}',
        );
        row
          ..remove('route_source')
          ..remove('route_fingerprint')
          ..remove('quality_tier')
          ..remove('route_meta')
          ..remove('completed_at_end')
          ..remove('group_id')
          ..remove('xp_distance')
          ..remove('xp_curve_bonus')
          ..remove('xp_style_bonus')
          ..remove('xp_base')
          ..remove('xp_multiplier')
          ..remove('xp_streak_days')
          ..remove('xp_awarded');
        await _db.from('routes').insert(row);
        invalidateWeeklyTopRouteCache();
      } else {
        rethrow;
      }
    }
  }

  static List<List<double>> _sampleCoordinatesForFingerprint(
    List<List<double>> coordinates,
  ) {
    if (coordinates.length <= 32) {
      return coordinates.map((point) => [point[0], point[1]]).toList();
    }
    final step = (coordinates.length / 32).ceil();
    final sampled = <List<double>>[];
    for (var i = 0; i < coordinates.length; i += step) {
      sampled.add([coordinates[i][0], coordinates[i][1]]);
    }
    sampled.add([coordinates.last[0], coordinates.last[1]]);
    return sampled;
  }

  /// Speichert eine bestehende Route (z.B. empfohlene Route) für den aktuellen User.
  static Future<void> saveExistingRoute(SavedRoute route) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;

    final savedRoutes = await getSavedRouteLibrary();
    if (hasEquivalentSavedRoute(route, savedRoutes)) {
      debugPrint(
        '[SavedRoutes] Route bereits gespeichert: id=${route.id}, '
        'fingerprint=${route.routeFingerprint ?? route.routeSignature}',
      );
      return;
    }

    final row = _buildExistingRouteInsert(userId: userId, route: route);

    try {
      await _db.from('routes').insert(row);
      invalidateWeeklyTopRouteCache();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204') {
        debugPrint(
          '[SavedRoutes] Route-Meta-Spalten fehlen, speichere Empfehlung ohne Meta: ${e.message}',
        );
        row
          ..remove('source_route_id')
          ..remove('route_source')
          ..remove('route_fingerprint')
          ..remove('quality_tier')
          ..remove('route_meta');
        await _db.from('routes').insert(row);
        invalidateWeeklyTopRouteCache();
      } else if (e.code == '23505') {
        // Unique constraint: diese Route ist für den User bereits gespeichert.
        debugPrint(
          '[SavedRoutes] Duplicate Save durch DB verhindert: id=${route.id}',
        );
        return;
      } else {
        rethrow;
      }
    }
  }

  @visibleForTesting
  static Map<String, dynamic> buildExistingRouteInsertForTest({
    required String userId,
    required SavedRoute route,
  }) {
    return _buildExistingRouteInsert(userId: userId, route: route);
  }

  static Map<String, dynamic> _buildExistingRouteInsert({
    required String userId,
    required SavedRoute route,
  }) {
    final rawSourceRouteId = (route.sourceRouteId?.trim().isNotEmpty == true)
        ? route.sourceRouteId!.trim()
        : route.id;
    final sourceRouteId =
        _shouldPersistSourceRouteId(
          route: route,
          rawSourceRouteId: rawSourceRouteId,
        )
        ? rawSourceRouteId
        : null;
    final routeFingerprint = (route.routeFingerprint?.trim().isNotEmpty == true)
        ? route.routeFingerprint!.trim()
        : route.routeSignature;
    final routeMeta = Map<String, dynamic>.from(route.routeMeta)
      ..['saved_route_source'] = 'existing_route_copy'
      ..['source_route_id'] = rawSourceRouteId
      ..['source_route_fingerprint'] = routeFingerprint;

    return <String, dynamic>{
      'user_id': userId,
      'name': route.name ?? '${route.styleEmoji} ${route.style}',
      'style': route.style,
      'route_type': route.routeType ?? 'ROUND_TRIP',
      'distance_target': (route.distanceTargetKm ?? route.distanceKm).round(),
      'distance_actual': route.distanceKm,
      'duration_seconds': route.durationSeconds?.round(),
      'geometry': route.geometry,
      if (sourceRouteId != null) 'source_route_id': sourceRouteId,
      'route_source': route.routeSource ?? 'saved_route_copy',
      'route_fingerprint': routeFingerprint,
      'quality_tier': route.qualityTier,
      'route_meta': routeMeta,
      if (route.rating != null && route.rating! > 0) 'rating': route.rating,
    };
  }

  static bool _shouldPersistSourceRouteId({
    required SavedRoute route,
    required String rawSourceRouteId,
  }) {
    if (!_isUuid(rawSourceRouteId)) return false;

    final routeSource = route.routeSource?.trim().toLowerCase();
    if (routeSource == 'route_pool' ||
        routeSource == 'route_pool_candidate' ||
        routeSource == 'candidate_reserve') {
      return false;
    }

    final externalSourceIds = <String>{
      route.routeMeta['pool_route_id']?.toString().trim() ?? '',
      route.routeMeta['route_pool_id']?.toString().trim() ?? '',
      route.routeMeta['candidate_route_id']?.toString().trim() ?? '',
      route.routeMeta['route_pool_candidate_id']?.toString().trim() ?? '',
    }..removeWhere((value) => value.isEmpty);

    return !externalSourceIds.contains(rawSourceRouteId);
  }

  static bool _isUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  static bool _isMissingColumnError(Object error) {
    if (error is! PostgrestException) return false;
    final message = error.message.toLowerCase();
    return error.code == '42703' ||
        error.code == 'PGRST204' ||
        message.contains('column') && message.contains('does not exist') ||
        message.contains('could not find') && message.contains('column');
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

  // ─── Gespeicherte Bibliothek ─────────────────────────────────────────────

  /// Gibt eigene gespeicherte Routen-Kopien zurück.
  /// Gefahrene Routen bleiben sichtbar; XP/Analytics kommen aus Drive-Sessions.
  static Future<List<SavedRoute>> getSavedRouteCopies() async {
    final routes = await getUserRoutes();
    return savedRouteCopiesFromUserRoutes(routes);
  }

  static Future<List<SavedRoute>> getBookmarkedRoutes() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return const [];

    try {
      final rows = await _db
          .from('route_bookmarks')
          .select('route_id, created_at, routes(*)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return dedupeEquivalentRoutes(
        (rows as List)
            .map((row) => row as Map<String, dynamic>)
            .map((row) => row['routes'])
            .whereType<Map>()
            .map(
              (route) => SavedRoute.fromJson(Map<String, dynamic>.from(route)),
            ),
      );
    } catch (e) {
      debugPrint('[SavedRoutes] getBookmarkedRoutes Fehler: $e');
      return const [];
    }
  }

  static Future<List<SavedRoute>> getSavedRouteLibrary() async {
    final results = await Future.wait([
      getSavedRouteCopies(),
      getBookmarkedRoutes(),
    ]);
    return dedupeEquivalentRoutes([...results[0], ...results[1]]);
  }

  static Future<bool> isRouteSaved(SavedRoute route) async {
    return hasEquivalentSavedRoute(route, await getSavedRouteLibrary());
  }

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
  /// Benennt eine eigene gespeicherte Route um.
  ///
  /// Posts und Bookmarks referenzieren dieselbe `routes.id`, deshalb ist der
  /// neue Name danach überall sichtbar, wo diese Route geladen wird.
  static Future<void> renameRoute(String id, String name) async {
    final userId = _db.auth.currentUser?.id;
    final cleaned = name.trim();
    if (userId == null || cleaned.isEmpty) return;
    if (cleaned.length > AppInputLimits.routeNameMaxLength) {
      throw ArgumentError('Routenname ist zu lang.');
    }

    try {
      await _db
          .from('routes')
          .update({'name': cleaned})
          .eq('id', id)
          .eq('user_id', userId);
      invalidateWeeklyTopRouteCache();
    } catch (e) {
      debugPrint('[SavedRoutes] renameRoute Fehler: $e');
      rethrow;
    }
  }

  /// Setzt/entfernt (null) das Foto einer eigenen gespeicherten Route.
  /// Returnt true bei Erfolg (mind. eine Zeile geändert).
  static Future<bool> updateRoutePhoto(String id, String? photoUrl) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      final rows = await _db
          .from('routes')
          .update({'photo_url': photoUrl})
          .eq('id', id)
          .eq('user_id', userId)
          .select('id');
      return rows.isNotEmpty;
    } catch (e) {
      debugPrint('[SavedRoutes] updateRoutePhoto Fehler: $e');
      return false;
    }
  }

  static Future<void> unsaveRouteEverywhere(SavedRoute route) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;

    final sourceRouteId = route.sourceRouteId?.trim();
    final routeIds = <String>{
      route.id,
      if (sourceRouteId != null && sourceRouteId.isNotEmpty) sourceRouteId,
    };

    try {
      await _db
          .from('route_bookmarks')
          .delete()
          .eq('user_id', userId)
          .inFilter('route_id', routeIds.toList());
    } catch (e) {
      debugPrint('[SavedRoutes] Bookmark entfernen fehlgeschlagen: $e');
    }

    try {
      final ownRoutes = await getUserRoutes();
      final savedCopies = ownRoutes
          .where((candidate) => areEquivalentRoutes(route, candidate))
          .map((candidate) => candidate.id)
          .toSet();
      routeIds.addAll(savedCopies);

      await _deleteRoutePublicationsForUser(userId: userId, routeIds: routeIds);

      if (savedCopies.isNotEmpty) {
        await _db
            .from('routes')
            .delete()
            .eq('user_id', userId)
            .inFilter('id', savedCopies.toList());
        invalidateWeeklyTopRouteCache();
      }
    } catch (e) {
      debugPrint(
        '[SavedRoutes] Gespeicherte Kopie entfernen fehlgeschlagen: $e',
      );
      rethrow;
    }
  }

  static Future<void> deleteRoute(String id) async {
    final userId = _db.auth.currentUser?.id;
    final routeId = id.trim();
    if (routeId.isEmpty) return;

    final routeIds = <String>{routeId};
    if (userId != null) {
      try {
        final row = await _db
            .from('routes')
            .select('source_route_id')
            .eq('id', routeId)
            .eq('user_id', userId)
            .maybeSingle();
        final sourceRouteId = row?['source_route_id']?.toString().trim();
        if (sourceRouteId != null && sourceRouteId.isNotEmpty) {
          routeIds.add(sourceRouteId);
        }
      } on PostgrestException catch (e) {
        if (!_isMissingColumnError(e)) rethrow;
      }

      await _deleteRoutePublicationsForUser(userId: userId, routeIds: routeIds);
    }

    try {
      final query = _db.from('routes').delete().eq('id', routeId);
      if (userId != null) {
        await query.eq('user_id', userId);
      } else {
        await query;
      }
      invalidateWeeklyTopRouteCache();
    } catch (e) {
      debugPrint('[SavedRoutes] deleteRoute Fehler: $e');
      rethrow; // UI soll informiert werden, dass Löschen fehlschlug
    }
  }

  static Future<void> _deleteRoutePublicationsForUser({
    required String userId,
    required Iterable<String> routeIds,
  }) async {
    final ids = routeIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    try {
      await _db
          .from('posts')
          .delete()
          .eq('user_id', userId)
          .inFilter('shared_route_id', ids);
    } on PostgrestException catch (e) {
      if (_isMissingColumnError(e)) {
        debugPrint('[SavedRoutes] shared_route_id fehlt, Posts übersprungen.');
      } else {
        rethrow;
      }
    }

    final deletedAt = DateTime.now().toUtc().toIso8601String();
    for (final routeId in ids) {
      await _softDeleteCommunityRouteMessages(
        userId: userId,
        routeJsonKey: 'route_id',
        routeId: routeId,
        deletedAt: deletedAt,
      );
      await _softDeleteCommunityRouteMessages(
        userId: userId,
        routeJsonKey: 'source_route_id',
        routeId: routeId,
        deletedAt: deletedAt,
      );
    }
  }

  static Future<void> _softDeleteCommunityRouteMessages({
    required String userId,
    required String routeJsonKey,
    required String routeId,
    required String deletedAt,
  }) async {
    try {
      await _db
          .from('community_messages')
          .update({'deleted_at': deletedAt, 'updated_at': deletedAt})
          .eq('user_id', userId)
          .isFilter('deleted_at', null)
          .filter('route_attachment->>$routeJsonKey', 'eq', routeId);
    } on PostgrestException catch (e) {
      if (_isMissingColumnError(e)) {
        debugPrint(
          '[SavedRoutes] route_attachment fehlt, Chat-Routen übersprungen.',
        );
      } else {
        rethrow;
      }
    }
  }
}
