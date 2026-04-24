import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/saved_routes_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SavedRoutesCacheService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('schreibt und liest Cache nur pro User-Key', () async {
      await SavedRoutesCacheService.writeForUser('user-a', '[{"id":"a"}]');
      await SavedRoutesCacheService.writeForUser('user-b', '[{"id":"b"}]');

      expect(
        await SavedRoutesCacheService.readForUser('user-a'),
        equals('[{"id":"a"}]'),
      );
      expect(
        await SavedRoutesCacheService.readForUser('user-b'),
        equals('[{"id":"b"}]'),
      );
    });

    test('entfernt Legacy-Key beim Lesen und Schreiben', () async {
      SharedPreferences.setMockInitialValues({
        SavedRoutesCacheService.legacyCacheKey: '[{"id":"legacy"}]',
      });

      expect(await SavedRoutesCacheService.readForUser('user-a'), isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(SavedRoutesCacheService.legacyCacheKey),
        isFalse,
      );
    });

    test('clearAll entfernt alle Saved-Route-Caches', () async {
      SharedPreferences.setMockInitialValues({
        SavedRoutesCacheService.legacyCacheKey: '[{"id":"legacy"}]',
        SavedRoutesCacheService.cacheKeyForUser('user-a'): '[{"id":"a"}]',
        SavedRoutesCacheService.cacheKeyForUser('user-b'): '[{"id":"b"}]',
        'other_key': 'keep',
      });

      await SavedRoutesCacheService.clearAll();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(SavedRoutesCacheService.legacyCacheKey),
        isFalse,
      );
      expect(
        prefs.containsKey(SavedRoutesCacheService.cacheKeyForUser('user-a')),
        isFalse,
      );
      expect(
        prefs.containsKey(SavedRoutesCacheService.cacheKeyForUser('user-b')),
        isFalse,
      );
      expect(prefs.getString('other_key'), equals('keep'));
    });
  });
}
