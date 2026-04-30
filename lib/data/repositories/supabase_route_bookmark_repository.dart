import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/domain/repositories/route_bookmark_repository.dart';

class SupabaseRouteBookmarkRepository implements RouteBookmarkRepository {
  SupabaseRouteBookmarkRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<void> saveRoute(String userId, String routeId) async {
    await _client.from('route_bookmarks').upsert({
      'user_id': userId,
      'route_id': routeId,
    }, onConflict: 'user_id,route_id');
  }

  @override
  Future<void> unsaveRoute(String userId, String routeId) async {
    await _client
        .from('route_bookmarks')
        .delete()
        .eq('user_id', userId)
        .eq('route_id', routeId);
  }

  @override
  Future<bool> checkIfRouteIsSaved(String userId, String routeId) async {
    final row = await _client
        .from('route_bookmarks')
        .select('id')
        .eq('user_id', userId)
        .eq('route_id', routeId)
        .maybeSingle();
    return row != null;
  }

  @override
  Future<List<SavedRoute>> getSavedRoutes(String userId) async {
    final rows = await _client
        .from('route_bookmarks')
        .select('route_id, created_at, routes(*)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((row) => row as Map<String, dynamic>)
        .map((row) => row['routes'])
        .whereType<Map>()
        .map((route) => SavedRoute.fromJson(Map<String, dynamic>.from(route)))
        .toList();
  }
}
