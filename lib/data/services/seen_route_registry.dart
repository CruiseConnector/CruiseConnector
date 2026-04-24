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
  static const int _maxEntriesPerScenario = 8;

  static List<SeenRouteEntry> entriesFor(String scenarioKey) =>
      List.unmodifiable(_entries[scenarioKey] ?? const []);

  static List<SeenRouteEntry> entriesForAny(Iterable<String> scenarioKeys) {
    final combined = <SeenRouteEntry>[];
    final seenFingerprints = <String>{};
    for (final scenarioKey in scenarioKeys) {
      for (final entry in _entries[scenarioKey] ?? const <SeenRouteEntry>[]) {
        if (seenFingerprints.add(entry.fingerprint)) {
          combined.add(entry);
        }
      }
    }
    return List.unmodifiable(combined);
  }

  static bool hasExactFingerprint(String scenarioKey, String fingerprint) {
    return (_entries[scenarioKey] ?? const []).any(
      (entry) => entry.fingerprint == fingerprint,
    );
  }

  static bool hasExactFingerprintInAny(
    Iterable<String> scenarioKeys,
    String fingerprint,
  ) {
    for (final scenarioKey in scenarioKeys) {
      if (hasExactFingerprint(scenarioKey, fingerprint)) {
        return true;
      }
    }
    return false;
  }

  static bool hasSimilarRoute(
    String scenarioKey,
    List<List<double>> sampledCoordinates, {
    required double thresholdPercent,
    required double proximityMeters,
  }) {
    final previous = (_entries[scenarioKey] ?? const []).map(
      (entry) => entry.sampledCoordinates,
    );
    return RouteQualityValidator.isRouteTooSimilarToPrevious(
      sampledCoordinates,
      previous,
      thresholdPercent: thresholdPercent,
      proximityMeters: proximityMeters,
    );
  }

  static bool hasSimilarRouteInAny(
    Iterable<String> scenarioKeys,
    List<List<double>> sampledCoordinates, {
    required double thresholdPercent,
    required double proximityMeters,
  }) {
    for (final scenarioKey in scenarioKeys) {
      if (hasSimilarRoute(
        scenarioKey,
        sampledCoordinates,
        thresholdPercent: thresholdPercent,
        proximityMeters: proximityMeters,
      )) {
        return true;
      }
    }
    return false;
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

  static void rememberAll(
    Iterable<String> scenarioKeys, {
    required String fingerprint,
    required List<List<double>> sampledCoordinates,
  }) {
    for (final scenarioKey in scenarioKeys) {
      remember(
        scenarioKey,
        fingerprint: fingerprint,
        sampledCoordinates: sampledCoordinates,
      );
    }
  }

  static void clearScenario(String scenarioKey) {
    _entries.remove(scenarioKey);
  }

  static void clearAll() {
    _entries.clear();
  }
}
