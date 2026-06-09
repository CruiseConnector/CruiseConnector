@Tags(['network'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/geocoding_service.dart';

/// 2026-06-09 (vucko A→B-Latenz): Netz-Smoke-Test für die Autocomplete-Pipeline
/// nach dem Timeout/Parallel/Cache-Umbau. Opt-in (echtes Mapbox-Netz):
///   flutter test test/services/geocoding_smoke_test.dart
/// Prüft: (1) Happy-Path liefert Treffer SCHNELL (Timeouts brechen ihn nicht),
/// (2) der zweite identische Call kommt aus dem Cache (deutlich schneller),
/// (3) getCoordinatesFromAddress löst eine Adresse auf. NIE Token ausgeben.
void main() {
  const service = GeocodingService();

  test('searchSuggestions liefert Treffer schnell (Timeout bricht nicht)',
      () async {
    final sw = Stopwatch()..start();
    final results = await service.searchSuggestions('Dornbirn');
    sw.stop();
    // ignore: avoid_print
    print('[smoke] searchSuggestions: ${results.length} Treffer in '
        '${sw.elapsedMilliseconds}ms');
    expect(results, isNotEmpty);
    // Mit Timeout 4s + Parallel-Retrieve sollte das klar darunter liegen.
    expect(sw.elapsedMilliseconds, lessThan(8000));
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('zweiter identischer Call kommt SOFORT aus dem Cache', () async {
    await service.searchSuggestions('Bregenz Bahnhof');
    final sw = Stopwatch()..start();
    final cached = await service.searchSuggestions('Bregenz Bahnhof');
    sw.stop();
    // ignore: avoid_print
    print('[smoke] cache-hit: ${cached.length} Treffer in '
        '${sw.elapsedMilliseconds}ms');
    expect(cached, isNotEmpty);
    expect(sw.elapsedMilliseconds, lessThan(50),
        reason: 'Cache-Treffer muss synchron-schnell sein');
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('getCoordinatesFromAddress löst eine Adresse auf', () async {
    final coords = await service.getCoordinatesFromAddress('Dornbirn');
    expect(coords, isNotNull);
    expect(coords!['latitude'], isNotNull);
    expect(coords['longitude'], isNotNull);
    // Vorarlberg-Plausibilität (Dornbirn ~47.4, 9.7).
    expect(coords['latitude']! > 46 && coords['latitude']! < 48, isTrue);
  }, timeout: const Timeout(Duration(seconds: 20)));
}
