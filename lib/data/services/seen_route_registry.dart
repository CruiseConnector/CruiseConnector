import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cruise_connect/data/services/route_quality_validator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SeenRouteEntry {
  const SeenRouteEntry({
    required this.fingerprint,
    required this.sampledCoordinates,
    this.dominantSector,
  });

  final String fingerprint;
  final List<List<double>> sampledCoordinates;
  final int? dominantSector;
}

class SeenRouteRegistry {
  SeenRouteRegistry._();

  static final Map<String, List<SeenRouteEntry>> _entries = {};
  static const int _maxEntriesPerScenario = 10;
  static const String _prefsKey = 'seen_route_registry_v2';
  static bool _loaded = false;
  static Future<void>? _loadFuture;
  static SharedPreferences? _prefs;

  static Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loadFuture ??= _loadFromPrefs();
  }

  static Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            final value = entry.value;
            if (value is! List) continue;
            final parsed = value
                .map(_entryFromJson)
                .whereType<SeenRouteEntry>()
                .toList(growable: false);
            if (parsed.isNotEmpty) {
              _entries[entry.key] = parsed.length > _maxEntriesPerScenario
                  ? parsed.sublist(parsed.length - _maxEntriesPerScenario)
                  : parsed;
            }
          }
        }
      } catch (_) {
        await prefs.remove(_prefsKey);
      }
    }
    _loaded = true;
  }

  static SeenRouteEntry? _entryFromJson(Object? value) {
    if (value is! Map) return null;
    final fingerprint = value['fingerprint'];
    final coords = value['sampledCoordinates'];
    if (fingerprint is! String || fingerprint.isEmpty || coords is! List) {
      return null;
    }
    final sampledCoordinates = coords
        .map((point) {
          if (point is! List || point.length < 2) return null;
          final lng = point[0];
          final lat = point[1];
          final parsedLng = lng is num
              ? lng.toDouble()
              : double.tryParse(lng?.toString() ?? '');
          final parsedLat = lat is num
              ? lat.toDouble()
              : double.tryParse(lat?.toString() ?? '');
          if (parsedLng == null || parsedLat == null) return null;
          return <double>[parsedLng, parsedLat];
        })
        .whereType<List<double>>()
        .toList(growable: false);
    if (sampledCoordinates.isEmpty) return null;
    return SeenRouteEntry(
      fingerprint: fingerprint,
      sampledCoordinates: sampledCoordinates,
      dominantSector:
          _parseSector(value['dominantSector']) ??
          dominantSectorForCoordinates(sampledCoordinates),
    );
  }

  static Future<void> _persistIfLoaded() async {
    if (!_loaded && _prefs == null) return;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    final payload = _entries.map(
      (scenarioKey, entries) => MapEntry(
        scenarioKey,
        entries
            .map(
              (entry) => <String, dynamic>{
                'fingerprint': entry.fingerprint,
                'sampledCoordinates': entry.sampledCoordinates,
                if (entry.dominantSector != null)
                  'dominantSector': entry.dominantSector,
              },
            )
            .toList(growable: false),
      ),
    );
    await prefs.setString(_prefsKey, json.encode(payload));
  }

  static Future<void> _clearPersisted() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.remove(_prefsKey);
  }

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

  static bool hasRecentDominantSectorInAny(
    Iterable<String> scenarioKeys,
    List<List<double>> sampledCoordinates, {
    int recentEntryLimit = 4,
  }) {
    final sector = dominantSectorForCoordinates(sampledCoordinates);
    if (sector == null) return false;
    for (final scenarioKey in scenarioKeys) {
      final entries = _entries[scenarioKey] ?? const <SeenRouteEntry>[];
      final recent = entries.length <= recentEntryLimit
          ? entries
          : entries.sublist(entries.length - recentEntryLimit);
      for (final entry in recent) {
        if (entry.dominantSector == sector) {
          return true;
        }
      }
    }
    return false;
  }

  static Set<int> recentDominantSectorsForAny(
    Iterable<String> scenarioKeys, {
    int recentEntryLimit = 4,
  }) {
    final sectors = <int>{};
    for (final scenarioKey in scenarioKeys) {
      final entries = _entries[scenarioKey] ?? const <SeenRouteEntry>[];
      final recent = entries.length <= recentEntryLimit
          ? entries
          : entries.sublist(entries.length - recentEntryLimit);
      for (final entry in recent) {
        final sector = entry.dominantSector;
        if (sector != null) sectors.add(sector);
      }
    }
    return sectors;
  }

  static void remember(
    String scenarioKey, {
    required String fingerprint,
    required List<List<double>> sampledCoordinates,
  }) {
    final list = [...(_entries[scenarioKey] ?? const <SeenRouteEntry>[])];
    list.removeWhere((entry) => entry.fingerprint == fingerprint);
    list.add(
      SeenRouteEntry(
        fingerprint: fingerprint,
        sampledCoordinates: sampledCoordinates,
        dominantSector: dominantSectorForCoordinates(sampledCoordinates),
      ),
    );
    if (list.length > _maxEntriesPerScenario) {
      list.removeRange(0, list.length - _maxEntriesPerScenario);
    }
    _entries[scenarioKey] = list;
    unawaited(_persistIfLoaded());
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
    unawaited(_persistIfLoaded());
  }

  static void clearAll() {
    _entries.clear();
    _loaded = false;
    _loadFuture = null;
    final hadPrefs = _prefs != null;
    _prefs = null;
    if (hadPrefs) {
      unawaited(_clearPersisted());
    }
  }

  static Future<void> flushForTests() => _persistIfLoaded();

  static void resetMemoryForTests() {
    _entries.clear();
    _loaded = false;
    _loadFuture = null;
    _prefs = null;
  }

  static int? dominantSectorForCoordinates(List<List<double>> coordinates) {
    if (coordinates.length < 2 || coordinates.first.length < 2) return null;
    final start = coordinates.first;
    var bestDistanceScore = 0.0;
    List<double>? farthest;
    for (final point in coordinates) {
      if (point.length < 2) continue;
      final dx = point[0] - start[0];
      final dy = point[1] - start[1];
      final score = dx * dx + dy * dy;
      if (score > bestDistanceScore) {
        bestDistanceScore = score;
        farthest = point;
      }
    }
    if (farthest == null || bestDistanceScore <= 0.00000001) return null;
    final bearing = _bearingDegrees(
      start[1],
      start[0],
      farthest[1],
      farthest[0],
    );
    return (bearing / 45.0).floor().clamp(0, 7).toInt();
  }

  static int? _parseSector(Object? value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed < 0 || parsed > 7) return null;
    return parsed;
  }

  static double _bearingDegrees(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final phi1 = lat1 * math.pi / 180.0;
    final phi2 = lat2 * math.pi / 180.0;
    final deltaLambda = (lng2 - lng1) * math.pi / 180.0;
    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x =
        math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);
    final degrees = math.atan2(y, x) * 180.0 / math.pi;
    return (degrees + 360.0) % 360.0;
  }
}
