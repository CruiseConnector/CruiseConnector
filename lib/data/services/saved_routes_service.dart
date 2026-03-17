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
      'distance_target': distKm,
      'distance_actual': drivenKm ?? distKm,
      'duration_seconds': result.durationSeconds,
      'geometry': result.geometry,
    };
    if (rating != null && rating > 0) row['rating'] = rating;
    if (drivenKm != null) row['driven_km'] = drivenKm;

    await _db.from('routes').insert(row);
  }

  // ─── Laden ────────────────────────────────────────────────────────────────

  /// Gibt alle gespeicherten Routen des eingeloggten Users zurück,
  /// neueste zuerst.
  static Future<List<SavedRoute>> getUserRoutes() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return const [];

    final data = await _db
        .from('routes')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => SavedRoute.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // ─── Beliebte Routen ────────────────────────────────────────────────────

  /// Gibt beliebte Routen anderer Nutzer zurück (ähnlicher Stil, gute Bewertung).
  /// Kann als Vorschlag für neue Nutzer verwendet werden.
  static Future<List<SavedRoute>> getPopularRoutes({
    String? style,
    int limit = 10,
  }) async {
    var query = _db
        .from('routes')
        .select()
        .gte('rating', 3)
        .order('rating', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);

    if (style != null) {
      query = _db
          .from('routes')
          .select()
          .eq('style', style)
          .gte('rating', 3)
          .order('rating', ascending: false)
          .limit(limit);
    }

    final data = await query;
    return (data as List)
        .map((row) => SavedRoute.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // ─── Löschen ─────────────────────────────────────────────────────────────

  /// Löscht eine Route anhand ihrer ID.
  static Future<void> deleteRoute(String id) async {
    await _db.from('routes').delete().eq('id', id);
  }
}
