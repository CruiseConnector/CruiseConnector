import 'package:cruise_connect/data/services/route_variant.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

class PreparedRouteEntry {
  const PreparedRouteEntry({
    required this.route,
    required this.variant,
    required this.preparedAt,
  });

  final RouteResult route;
  final RouteVariant variant;
  final DateTime preparedAt;
}

class PreparedRouteBuffer {
  PreparedRouteBuffer._();

  static final Map<String, PreparedRouteEntry> _entries = {};
  static const Duration _freshness = Duration(minutes: 5);

  static PreparedRouteEntry? take(String scenarioKey) {
    final entry = _entries.remove(scenarioKey);
    if (entry == null) return null;
    if (DateTime.now().difference(entry.preparedAt) > _freshness) {
      return null;
    }
    return entry;
  }

  static void store(String scenarioKey, PreparedRouteEntry entry) {
    _entries[scenarioKey] = entry;
  }

  static bool hasFreshEntry(String scenarioKey) {
    final entry = _entries[scenarioKey];
    if (entry == null) return false;
    return DateTime.now().difference(entry.preparedAt) <= _freshness;
  }

  static int get count => _entries.length;

  static void clearScenario(String scenarioKey) {
    _entries.remove(scenarioKey);
  }

  static void clearAll() {
    _entries.clear();
  }
}
