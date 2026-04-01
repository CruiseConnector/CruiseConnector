class RouteGenerationCoordinator {
  RouteGenerationCoordinator._();

  static final Map<String, Future<dynamic>> _inFlightByScenario = {};
  static final Set<String> _backgroundPreparation = {};

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
    return !_inFlightByScenario.containsKey(scenarioKey) &&
        !_backgroundPreparation.contains(scenarioKey);
  }

  static Future<void> prepareInBackground(
    String scenarioKey,
    Future<void> Function() producer,
  ) async {
    if (!canPrepare(scenarioKey)) return;
    _backgroundPreparation.add(scenarioKey);
    try {
      await producer();
    } finally {
      _backgroundPreparation.remove(scenarioKey);
    }
  }

  static bool hasInFlight(String scenarioKey) {
    return _inFlightByScenario.containsKey(scenarioKey);
  }
}
