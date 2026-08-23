import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/domain/models/saved_route.dart';

/// Die bis zu drei Lieblingsrouten, die ein Nutzer an sein Profil pinnt.
///
/// 2026-08-19 (Top-3-Lieblingsrouten): Tabelle `profile_featured_routes`
/// (Migration `20260819140000_profil_lieblingsrouten.sql`). Die Spalte
/// `position` (1..3) ist die Reihenfolge im Profil und wird hier IMMER
/// lueckenlos ab 1 neu vergeben — die UI arbeitet mit einer Liste, nicht mit
/// einzelnen Plaetzen, und eine Luecke waere fuer sie nicht darstellbar.
class FavoriteRoutesService {
  static SupabaseClient get _db => Supabase.instance.client;

  /// Mehr als drei Highlights sind bewusst nicht vorgesehen: Der Sinn des
  /// Features ist die Auswahl, nicht die Liste. Die DB haelt dieselbe Grenze
  /// per `check (position between 1 and 3)`.
  static const int maxFavorites = 3;

  /// Laedt die Lieblingsrouten eines Profils in Anzeige-Reihenfolge.
  ///
  /// Der Join zieht die Route gleich mit — ein Roundtrip statt vier. Zeilen
  /// ohne lesbare Route werden uebersprungen: bei privaten Profilen oder
  /// zwischenzeitlich entfernten Routen liefert PostgREST den Join als
  /// `null`, und eine halbe Kachel ist schlechter als keine.
  static Future<List<SavedRoute>> getFavorites(String userId) async {
    if (userId.trim().isEmpty) return const [];
    try {
      final rows = await _db
          .from('profile_featured_routes')
          .select('position, routes(*)')
          .eq('user_id', userId)
          .order('position', ascending: true);

      return (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map((row) => row['routes'])
          .whereType<Map>()
          .map((route) => SavedRoute.fromJson(Map<String, dynamic>.from(route)))
          .toList(growable: false);
    } catch (e) {
      debugPrint('[FavoriteRoutes] getFavorites Fehler: $e');
      return const [];
    }
  }

  /// Lieblingsrouten des eingeloggten Nutzers.
  static Future<List<SavedRoute>> getOwnFavorites() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return const [];
    return getFavorites(userId);
  }

  /// Ersetzt die Auswahl komplett durch [routeIds] (max. [maxFavorites]).
  ///
  /// Bewusst „loeschen und neu schreiben" statt eines Diffs: Die Reihenfolge
  /// ist Teil des Primaerschluessels `(user_id, position)`. Ein Diff muesste
  /// beim Umsortieren Zwischenzustaende schreiben, die den Schluessel
  /// verletzen (zwei Routen kurzzeitig auf Platz 1). Bei maximal drei Zeilen
  /// ist der Neuschrieb sowieso billiger als die Sonderfaelle.
  ///
  /// Liefert `true`, wenn der Stand danach dem Wunsch entspricht.
  static Future<bool> setFavorites(List<String> routeIds) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return false;

    // Duplikate raus (`unique (user_id, route_id)`), Reihenfolge behalten.
    final unique = <String>[];
    for (final id in routeIds) {
      final cleaned = id.trim();
      if (cleaned.isEmpty || unique.contains(cleaned)) continue;
      unique.add(cleaned);
      if (unique.length >= maxFavorites) break;
    }

    try {
      await _db.from('profile_featured_routes').delete().eq('user_id', userId);
      if (unique.isEmpty) return true;

      await _db.from('profile_featured_routes').insert([
        for (var i = 0; i < unique.length; i++)
          {'user_id': userId, 'route_id': unique[i], 'position': i + 1},
      ]);
      return true;
    } catch (e) {
      debugPrint('[FavoriteRoutes] setFavorites Fehler: $e');
      return false;
    }
  }

  /// Pinnt [routeId] hinten an. Ist die Route schon angepinnt oder sind
  /// bereits [maxFavorites] Plaetze belegt, passiert nichts (`false`).
  static Future<bool> pin(String routeId) async {
    final current = await getOwnFavorites();
    final ids = current.map((route) => route.id).toList();
    if (ids.contains(routeId) || ids.length >= maxFavorites) return false;
    return setFavorites([...ids, routeId]);
  }

  /// Entfernt [routeId] aus den Highlights und schliesst die Luecke.
  static Future<bool> unpin(String routeId) async {
    final current = await getOwnFavorites();
    final ids = current
        .map((route) => route.id)
        .where((id) => id != routeId)
        .toList();
    if (ids.length == current.length) return true; // war nicht angepinnt
    return setFavorites(ids);
  }

  /// Ist [routeId] beim eingeloggten Nutzer angepinnt?
  static Future<bool> isPinned(String routeId) async {
    final favorites = await getOwnFavorites();
    return favorites.any((route) => route.id == routeId);
  }
}
