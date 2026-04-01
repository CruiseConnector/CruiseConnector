import 'package:cruise_connect/data/services/route_quality_validator.dart';

class SeenRouteEntry {
  const SeenRouteEntry({
    required this.fingerprint,
    required this.sampledCoordinates,
  });

  final String fingerprint;
  final List<List<double>> sampledCoordinates;
}

class SeenRouteRegistry {
  SeenRouteRegistry._();

  static final Map<String, List<SeenRouteEntry>> _entries = {};
  static const int _maxEntriesPerScenario = 4;

  static List<SeenRouteEntry> entriesFor(String scenarioKey) =>
      List.unmodifiable(_entries[scenarioKey] ?? const []);

  static bool hasExactFingerprint(String scenarioKey, String fingerprint) {
    return (_entries[scenarioKey] ?? const []).any(
      (entry) => entry.fingerprint == fingerprint,
    );
  }

  static bool hasSimilarRoute(
    String scenarioKey,
    List<List<double>> sampledCoordinates, {
    required double thresholdPercent,
    required double proximityMeters,
  }) {
    final previous = (_entries[scenarioKey] ?? const [])
        .map((entry) => entry.sampledCoordinates);
    return RouteQualityValidator.isRouteTooSimilarToPrevious(
      sampledCoordinates,
      previous,
      thresholdPercent: thresholdPercent,
      proximityMeters: proximityMeters,
    );
  }

  static void remember(
    String scenarioKey, {
    required String fingerprint,
    required List<List<double>> sampledCoordinates,
  }) {
    final list = [...(_entries[scenarioKey] ?? const <SeenRouteEntry>[])];
    if (list.any((entry) => entry.fingerprint == fingerprint)) {
      return;
    }
    list.add(
      SeenRouteEntry(
        fingerprint: fingerprint,
        sampledCoordinates: sampledCoordinates,
      ),
    );
    if (list.length > _maxEntriesPerScenario) {
      list.removeRange(0, list.length - _maxEntriesPerScenario);
    }
    _entries[scenarioKey] = list;
  }

  static void clearScenario(String scenarioKey) {
    _entries.remove(scenarioKey);
  }

  static void clearAll() {
    _entries.clear();
  }
}
