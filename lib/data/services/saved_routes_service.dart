import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';

/// CRUD für gespeicherte Routen in der Supabase `routes` Tabelle.
class SavedRoutesService {
  static SupabaseClient get _db => Supabase.instance.client;

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
  }) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;

    final routeType = isRoundTrip ? 'ROUND_TRIP' : 'POINT_TO_POINT';
    final name = (customName?.trim().isNotEmpty == true)
        ? customName!.trim()
        : '$style ${isRoundTrip ? 'Rundkurs' : 'Route'}';

    final distKm = result.distanceKm ??
        (result.distanceMeters != null ? result.distanceMeters! / 1000 : 0.0);

    final row = <String, dynamic>{
      'user_id': userId,
      'name': name,
      'style': style,
      'route_type': routeType,
      'distance_target': distKm.round(), // int-Spalte → runden
      'distance_actual': drivenKm ?? distKm,
      'duration_seconds': result.durationSeconds?.round(),
      'geometry': result.geometry,
    };
    if (rating != null && rating > 0) row['rating'] = rating;
    if (drivenKm != null) row['driven_km'] = drivenKm;

    try {
      await _db.from('routes').insert(row);
    } on PostgrestException catch (e) {
      // Fallback: Falls 'name' Spalte noch nicht existiert, ohne speichern
      if (e.code == 'PGRST204' && e.message.contains('name')) {
        debugPrint('[SavedRoutes] name-Spalte fehlt, speichere ohne name');
        row.remove('name');
        await _db.from('routes').insert(row);
      } else {
        rethrow;
      }
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
      return SavedRoute.fromJson(data as Map<String, dynamic>);
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
    } catch (e) {
      debugPrint('[SavedRoutes] deleteRoute Fehler: $e');
      rethrow; // UI soll informiert werden, dass Löschen fehlschlug
    }
  }
}
