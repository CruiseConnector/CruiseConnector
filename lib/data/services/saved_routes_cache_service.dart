import 'package:shared_preferences/shared_preferences.dart';

class SavedRoutesCacheService {
  SavedRoutesCacheService._();

  static const String legacyCacheKey = 'saved_routes_cache';
  static const String _cacheKeyPrefix = 'saved_routes_cache_v2:';

  static String cacheKeyForUser(String userId) => '$_cacheKeyPrefix$userId';

  static Future<String?> readForUser(String? userId) async {
    if (userId == null || userId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(legacyCacheKey);
    return prefs.getString(cacheKeyForUser(userId));
  }

  static Future<void> writeForUser(String? userId, String jsonPayload) async {
    if (userId == null || userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(legacyCacheKey);
    await prefs.setString(cacheKeyForUser(userId), jsonPayload);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keysToRemove = prefs.getKeys().where(
      (key) => key == legacyCacheKey || key.startsWith(_cacheKeyPrefix),
    );
    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
  }
}
