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
  }) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;

    final routeType = isRoundTrip ? 'ROUND_TRIP' : 'POINT_TO_POINT';
    final name = (customName?.trim().isNotEmpty == true)
        ? customName!.trim()
        : '$style ${isRoundTrip ? 'Rundkurs' : 'Route'}';

    final distKm = result.distanceKm ??
        (result.distanceMeters != null ? result.distanceMeters! / 1000 : 0.0);

    await _db.from('routes').insert({
      'user_id': userId,
      'name': name,
      'style': style,
      'route_type': routeType,
      'distance_actual': distKm,
      'duration_seconds': result.durationSeconds,
      'geometry': result.geometry,
    });
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

  // ─── Löschen ─────────────────────────────────────────────────────────────

  /// Löscht eine Route anhand ihrer ID.
  static Future<void> deleteRoute(String id) async {
    await _db.from('routes').delete().eq('id', id);
  }
}
