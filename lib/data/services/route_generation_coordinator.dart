class RouteGenerationCoordinator {
  RouteGenerationCoordinator._();

  static final Map<String, Future<dynamic>> _inFlightByScenario = {};
  static final Map<String, Future<void>> _backgroundPreparationByScenario = {};
  static DateTime? _backgroundPreparationSuspendedUntil;

  static Future<T> runSingleFlight<T>(
    String scenarioKey,
    Future<T> Function() producer,
  ) {
    final existing = _inFlightByScenario[scenarioKey];
    if (existing != null) {
      return existing as Future<T>;
    }

    final future = Future<T>(() async {
      try {
        return await producer();
      } finally {
        _inFlightByScenario.remove(scenarioKey);
      }
    });
    _inFlightByScenario[scenarioKey] = future;
    return future;
  }

  static bool canPrepare(String scenarioKey) {
    return !_isBackgroundPreparationSuspended() &&
        !_inFlightByScenario.containsKey(scenarioKey) &&
        !_backgroundPreparationByScenario.containsKey(scenarioKey);
  }

  static Future<void> prepareInBackground(
    String scenarioKey,
    Future<void> Function() producer,
  ) async {
    if (!canPrepare(scenarioKey)) return;
    final future = Future<void>(() async {
      try {
        await producer();
      } finally {
        _backgroundPreparationByScenario.remove(scenarioKey);
      }
    });
    _backgroundPreparationByScenario[scenarioKey] = future;
    await future;
  }

  static bool hasInFlight(String scenarioKey) {
    return _inFlightByScenario.containsKey(scenarioKey);
  }

  static void suspendBackgroundPreparation([
    Duration duration = const Duration(seconds: 2),
  ]) {
    final until = DateTime.now().add(duration);
    if (_backgroundPreparationSuspendedUntil == null ||
        until.isAfter(_backgroundPreparationSuspendedUntil!)) {
      _backgroundPreparationSuspendedUntil = until;
    }
  }

  static void resetForTests() {
    _inFlightByScenario.clear();
    _backgroundPreparationByScenario.clear();
    _backgroundPreparationSuspendedUntil = null;
  }

  static bool _isBackgroundPreparationSuspended() {
    final until = _backgroundPreparationSuspendedUntil;
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _backgroundPreparationSuspendedUntil = null;
      return false;
    }
    return true;
  }
}
