import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/data/services/prepared_route_buffer.dart';
import 'package:cruise_connect/data/services/route_access_plan.dart';
import 'package:cruise_connect/data/services/route_cache_service.dart';
import 'package:cruise_connect/data/services/route_generation_coordinator.dart';
import 'package:cruise_connect/data/services/route_pool_service.dart';
import 'package:cruise_connect/data/services/route_quality_validator.dart';
import 'package:cruise_connect/data/services/route_scenario.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/data/services/route_style_config.dart';
import 'package:cruise_connect/data/services/route_variant.dart';
import 'package:cruise_connect/data/services/seen_route_registry.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

/// Top-level Funktion für Isolate-basiertes JSON-Parsing.
Map<String, dynamic> _jsonDecodeIsolate(String data) =>
    Map<String, dynamic>.from(json.decode(data) as Map);

// ──────────────────── Testable Edge-Function Abstraction ────────────────────

/// Abstraktion über den Supabase-Edge-Function-Aufruf — mockbar in Tests.
abstract class RouteEdgeInvoker {
  Future<dynamic> invoke(Map<String, dynamic> body);
}

/// Standard-Implementierung: leitet an Supabase weiter.
class SupabaseRouteInvoker implements RouteEdgeInvoker {
  const SupabaseRouteInvoker();

  String get debugEndpoint =>
      '${AppConstants.supabaseUrl}/functions/v1/${RouteService.edgeFunction}';

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    final response = await Supabase.instance.client.functions.invoke(
      RouteService.edgeFunction,
      body: body,
    );
    return response.data;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Service für die Routenberechnung via Supabase Edge Function.
class RouteService {
  RouteService({RouteEdgeInvoker? invoker, RoutePoolService? routePoolService})
    : _invoker = invoker ?? const SupabaseRouteInvoker(),
      _routePoolService = routePoolService ?? RoutePoolService();

  static const String edgeFunction = 'generate-cruise-route';
  static const String clientRoutingBuildId = String.fromEnvironment(
    'ROUTING_CLIENT_BUILD_ID',
    defaultValue: 'local-dev',
  );
  static const String clientRoutingBuildTime = String.fromEnvironment(
    'ROUTING_CLIENT_BUILD_TIME',
    defaultValue: 'local-dev',
  );
  static int _lastRandomSeed = 0;
  static const String _explorerBearingPrefsKey =
      'route_service_recent_explorer_bearings';
  static const String _lastSuccessfulRouteKey =
      'route_service_last_successful_route';
  static final Map<String, RouteResult> _recentSuccessfulRoutes = {};
  static final Map<String, RouteResult> _recentDisplayedRoutes = {};

  /// Flag: letzte Route kam aus dem Offline-Cache
  static bool lastRouteFromCache = false;
  static bool lastRouteSessionCacheHit = false;
  static bool lastRouteRecentFallbackUsed = false;
  static bool lastRoutePersistentCacheFallbackUsed = false;
  static bool lastRoutePreparedBufferHit = false;
  static bool lastRoutePreparedBufferUsed = false;
  static bool lastRouteDuplicateFallbackUsed = false;
  static bool lastRouteEmergencyFallbackUsed = false;
  static bool lastRoutePoolFallbackUsed = false;
  static bool lastRoutePoolDistanceRuleApplied = false;
  static bool lastRoutePoolRejectedTooFar = false;
  static bool lastRouteAccessLegUsed = false;
  static double? lastRouteAccessLegDistanceKm;
  static String lastRouteGenerationSource = 'mapbox';
  static String lastRouteSubscriptionTier = 'premium';
  static String? lastRouteRequestedStyle;
  static String? lastRoutePoolMatchId;
  static String? lastRoutePoolMatchTier;
  static double? lastRoutePoolStartDistanceKm;
  static bool lastRouteDeadEndSpikeDetected = false;
  static int lastRouteApiCallCount = 0;
  static int? lastRouteGenerationStartedAtMs;
  static String? lastRouteDebugFingerprint;
  static double? lastRouteSimilarityToPreviousPercent;
  static String? lastRouteDebugTrigger;
  static String? lastRouteCoverageStatus;
  static bool lastRouteSeedJobCreated = false;
  static bool lastRouteDuplicateSeedJobPrevented = false;
  static bool lastRoutePoolBootstrapPending = false;
  static String? lastRouteRegionDifficulty;
  static String? lastRouteHardRegionStatus;
  static String? lastRouteChosenCluster;
  static bool lastRouteCandidateInserted = false;
  static bool lastRouteVerifiedInserted = false;

  /// Letzte 3 Entdecker-Richtungen (in Grad) für Diversifizierung.
  // TODO: In SharedPreferences persistieren für Session-übergreifende Diversifizierung
  static final List<double> _recentExplorerBearings = [];
  static const RouteQualityValidator _qualityValidator =
      RouteQualityValidator();
  static const RouteAccessPlanner _accessPlanner = RouteAccessPlanner();
  static final Map<String, int> _scenarioVariantCounters = {};

  /// Session-Cache: verhindert doppelte API-Calls für identische Anfragen.
  /// Key = konkrete Variant-/Request-Signatur, Value = RouteResult.
  static final Map<String, RouteResult> _sessionCache = {};

  /// Globaler Request-Zähler als Fallback für Legacy-Aufrufer.
  static int _globalDiversityIndex = 0;

  /// WORKER_LIMIT Cooldown: Nach diesem Fehler keine neuen Requests für X ms.
  static DateTime? _workerLimitCooldownUntil;

  final RouteEdgeInvoker _invoker;
  final RoutePoolService _routePoolService;
  String? _activeScenarioKeyForDebug;
  bool _activeForceFreshVariantForDebug = false;
  String _activeTriggerForDebug = 'unknown';

  // ─────────────────────────── Public API ────────────────────────────────────

  static bool requiresDestination(String routeType) {
    return routeType == 'POINT_TO_POINT';
  }

  @visibleForTesting
  static bool disableBackgroundPreparation = false;

  @visibleForTesting
  static void resetForTests() {
    _sessionCache.clear();
    _recentSuccessfulRoutes.clear();
    _recentDisplayedRoutes.clear();
    _scenarioVariantCounters.clear();
    _globalDiversityIndex = 0;
    _workerLimitCooldownUntil = null;
    _resetRouteDebugState();
    RouteGenerationCoordinator.resetForTests();
    RouteCacheService.resetForTests();
    SeenRouteRegistry.clearAll();
    PreparedRouteBuffer.clearAll();
  }

  static void _resetRouteDebugState() {
    lastRouteFromCache = false;
    lastRouteSessionCacheHit = false;
    lastRouteRecentFallbackUsed = false;
    lastRoutePersistentCacheFallbackUsed = false;
    lastRoutePreparedBufferHit = false;
    lastRoutePreparedBufferUsed = false;
    lastRouteDuplicateFallbackUsed = false;
    lastRouteEmergencyFallbackUsed = false;
    lastRoutePoolFallbackUsed = false;
    lastRoutePoolDistanceRuleApplied = false;
    lastRoutePoolRejectedTooFar = false;
    lastRouteAccessLegUsed = false;
    lastRouteAccessLegDistanceKm = null;
    lastRouteGenerationSource = 'mapbox';
    lastRouteSubscriptionTier = 'premium';
    lastRouteRequestedStyle = null;
    lastRoutePoolMatchId = null;
    lastRoutePoolMatchTier = null;
    lastRoutePoolStartDistanceKm = null;
    lastRouteDeadEndSpikeDetected = false;
    lastRouteApiCallCount = 0;
    lastRouteGenerationStartedAtMs = null;
    lastRouteDebugFingerprint = null;
    lastRouteSimilarityToPreviousPercent = null;
    lastRouteDebugTrigger = null;
    lastRouteCoverageStatus = null;
    lastRouteSeedJobCreated = false;
    lastRouteDuplicateSeedJobPrevented = false;
    lastRoutePoolBootstrapPending = false;
    lastRouteRegionDifficulty = null;
    lastRouteHardRegionStatus = null;
    lastRouteChosenCluster = null;
    lastRouteCandidateInserted = false;
    lastRouteVerifiedInserted = false;
  }

  static void _debugRouteSearch(String message) {
    debugPrint('[RouteDebug] $message');
  }

  static String _normalizeSubscriptionTier(String value) {
    switch (value.trim().toLowerCase()) {
      case 'free':
        return 'free';
      case 'basic':
        return 'basic';
      case 'premium':
      default:
        return 'premium';
    }
  }

  /// TestFlight/Beta policy: during the closed test phase every beta user is
  /// treated as premium, but the switch remains explicit and removable.
  static const bool treatBetaUsersAsPremiumForTesting = bool.fromEnvironment(
    'CRUISECONNECT_TREAT_BETA_USERS_AS_PREMIUM',
    defaultValue: true,
  );

  static String resolveEffectiveSubscriptionTier({
    String requestedTier = 'free',
    bool isTesterOrBeta = false,
  }) {
    if (treatBetaUsersAsPremiumForTesting && isTesterOrBeta) {
      return 'premium';
    }
    return _normalizeSubscriptionTier(requestedTier);
  }

  static bool _isFreeTier(String value) =>
      _normalizeSubscriptionTier(value) == 'free';

  static bool _isBasicTier(String value) =>
      _normalizeSubscriptionTier(value) == 'basic';

  /// Berechnet eine Rundkurs-Route von der aktuellen Position.
  ///
  /// Sendet einen `direction_hint` (0-359°) an die Edge Function, der die
  /// Hauptrichtung der Route bestimmt. Jede Generierung bekommt einen anderen
  /// Winkel → echte Rundkurse in verschiedene Richtungen.
  ///
  /// Post-Validierung prüft: Overlap (<20%), U-Turns, Distanz (±15%),
  /// und stilspezifische Kriterien (Kurvenjagd: genug Kurven, Abendrunde: langsam).
  ///
  /// ── Performance-Gov ──
  /// Auf der Edge Function läuft ein Multi-Phasen-Suchlauf
  /// (strict → balanced → fallback). Wir geben dem Edge Budget für 7-9
  /// Mapbox-Calls (siehe `max_candidate_attempts`), damit alle drei Phasen
  /// in Tal-Geometrien (z.B. Dornbirn) wirklich mehrere Pläne pro Phase
  /// testen können. Vorher (3-6 Calls) sind wir in Dornbirn 3/3 in
  /// "Kein passender Rundkurs" gelaufen, weil der Fallback nur 1 Plan bekam.
  /// Time-Budget Edge: 19 s normal / 22 s constrained / 16 s high-cost.
  /// Client-Timeout: 26 s (_invoke) — muss DARÜBER liegen.
  /// Client-Schleife: max 2 Versuche pro User-Aktion.
  Future<RouteResult> generateRoundTrip({
    required geo.Position startPosition,
    required int targetDistanceKm,
    required String mode,
    required String planningType,
    Map<String, double>? targetLocation,
    int? variantIndex,
    bool avoidHighways = false,
    bool forceFreshVariant = false,
    String debugTrigger = 'unknown',
    String subscriptionTier = 'premium',
  }) async {
    final styleConfig = RouteStyleConfig.forMode(mode);
    final normalizedTargetKm = styleConfig.clampRoundTripDistanceKm(
      targetDistanceKm,
    );
    final scenario = RouteScenario(
      routeType: 'ROUND_TRIP',
      startLatitude: startPosition.latitude,
      startLongitude: startPosition.longitude,
      style: mode,
      planningType: planningType,
      targetDistanceKm: normalizedTargetKm.toDouble(),
      avoidHighways: avoidHighways,
    );
    _resetRouteDebugState();
    lastRouteGenerationStartedAtMs = DateTime.now().millisecondsSinceEpoch;
    lastRouteDebugTrigger = debugTrigger;
    lastRouteSubscriptionTier = _normalizeSubscriptionTier(subscriptionTier);
    lastRouteRequestedStyle = mode;
    _debugRouteSearch(
      '[ServiceStart] routeType=ROUND_TRIP selectedKm=$normalizedTargetKm '
      'selectedStyle=$mode avoidHighways=$avoidHighways '
      'forceFreshVariant=$forceFreshVariant trigger=$debugTrigger '
      'subscriptionTier=$lastRouteSubscriptionTier '
      'scenarioKey=${scenario.scenarioKey} noveltyKey=${scenario.noveltyKey}',
    );
    _activeScenarioKeyForDebug = scenario.scenarioKey;
    _activeForceFreshVariantForDebug = forceFreshVariant;
    _activeTriggerForDebug = debugTrigger;

    if (forceFreshVariant) {
      RouteGenerationCoordinator.suspendBackgroundPreparation();
      PreparedRouteBuffer.clearScenario(scenario.scenarioKey);
      _debugRouteSearch(
        '[Prepared] clearedForForceFresh=true scenarioKey=${scenario.scenarioKey}',
      );
    }

    final singleFlightKey = forceFreshVariant
        ? '${scenario.scenarioKey}|fresh|${DateTime.now().microsecondsSinceEpoch}'
        : scenario.scenarioKey;
    return RouteGenerationCoordinator.runSingleFlight(singleFlightKey, () async {
      if (_isFreeTier(lastRouteSubscriptionTier)) {
        final freePoolRoute = await _tryRoutePoolFallback(
          scenario: scenario,
          styleConfig: styleConfig,
          userLat: startPosition.latitude,
          userLng: startPosition.longitude,
          fallbackReason: 'free_pool_only',
        );
        if (freePoolRoute != null) {
          return freePoolRoute;
        }
        final coverage = await _ensureCoverageBootstrapStatus(
          scenario: scenario,
          userLat: startPosition.latitude,
          userLng: startPosition.longitude,
          subscriptionTier: lastRouteSubscriptionTier,
          createSeedJob: true,
        );
        if (coverage == null) {
          throw const RouteServiceException(
            type: RouteErrorType.noRoute,
            userMessage:
                'Keine passende Route gefunden. Bitte versuche es erneut.',
            debugMessage: 'No route and no pool coverage bucket available.',
          );
        }
        throw await _buildCoverageWarmupException(
          scenario: scenario,
          coverage: coverage,
          lastError: null,
        );
      }

      if (_isBasicTier(lastRouteSubscriptionTier)) {
        final basicPoolRoute = await _tryRoutePoolFallback(
          scenario: scenario,
          styleConfig: styleConfig,
          userLat: startPosition.latitude,
          userLng: startPosition.longitude,
          fallbackReason: 'pool_first_basic',
        );
        if (basicPoolRoute != null) {
          return basicPoolRoute;
        }
        await _ensureCoverageBootstrapStatus(
          scenario: scenario,
          userLat: startPosition.latitude,
          userLng: startPosition.longitude,
          subscriptionTier: lastRouteSubscriptionTier,
          createSeedJob: true,
        );
      }

      final prepared = forceFreshVariant
          ? null
          : _takePreparedRoute(scenario: scenario, styleConfig: styleConfig);
      if (prepared != null) {
        return prepared;
      }

      final hasSeenHistory = SeenRouteRegistry.entriesForAny(
        _seenHistoryKeysForScenario(scenario),
      ).isNotEmpty;
      final difficultScenario = _isDifficultRoundTripScenario(
        scenario,
        styleConfig,
      );
      // Client-Schleife: Erstsuche darf in schwierigen Szenarien mehr Seeds
      // testen. Sobald es aber bereits eine gute Route für dieselben Settings
      // gibt, reicht ein frischer Versuch; danach fällt die App schnell auf
      // die geprüfte Route zurück statt 30-45s in NO_ROUTE-Tails zu laufen.
      final maxAttempts = forceFreshVariant
          ? (difficultScenario ? 3 : 2)
          : difficultScenario
          ? (hasSeenHistory ? 1 : 3)
          : (hasSeenHistory ? 1 : 2);
      _RouteCandidate? bestCandidate;
      _RouteCandidate? spareCandidate;
      _RouteCandidate? bestDuplicateCandidate;
      RouteServiceException? lastError;

      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        if (_isInWorkerLimitCooldown()) break;
        final variant = await _nextRoundTripVariant(
          scenario,
          styleConfig: styleConfig,
          explicitIndex: attempt == 0 ? variantIndex : null,
        );
        _debugRouteSearch(
          '[Attempt] attempt=${attempt + 1}/$maxAttempts '
          'scenarioKey=${scenario.scenarioKey} '
          'routeVariantHint=${variant.variantHint} '
          'fingerprintHint=${variant.fingerprintHint} '
          'forceFreshVariant=$forceFreshVariant',
        );
        try {
          final candidate = await _requestRoundTripVariant(
            scenario: scenario,
            styleConfig: styleConfig,
            startPosition: startPosition,
            targetLocation: targetLocation,
            variant: variant,
            forceFreshVariant: forceFreshVariant,
            debugTrigger: debugTrigger,
            // Hint an Edge Function: gibt strict/balanced/fallback je 2-3
            // Pläne (siehe declaredMaxPerPhase und reservedForLaterPhases
            // in der Edge Function). Constrained Suchen (Autobahn vermeiden,
            // Kurvenjagd in engen Tälern) bekommen +1 Plan, weil sie pro
            // Versuch ggf. einen relax-retry brauchen.
            candidateBudget: _roundTripCandidateBudget(scenario, styleConfig),
          );
          if (candidate.accepted) {
            if (!candidate.novelEnough) {
              debugPrint(
                '[RouteService] RoundTrip candidate ${attempt + 1}/$maxAttempts ist brauchbar, aber zu ähnlich zur letzten Route.',
              );
              if (_isBetterCandidate(candidate, bestDuplicateCandidate)) {
                bestDuplicateCandidate = candidate;
              }
              continue;
            }
            if (_isBetterCandidate(candidate, bestCandidate)) {
              if (bestCandidate != null &&
                  _isBetterCandidate(bestCandidate, spareCandidate)) {
                spareCandidate = bestCandidate;
              }
              bestCandidate = candidate;
            } else if (_isBetterCandidate(candidate, spareCandidate)) {
              spareCandidate = candidate;
            }
          }
          if (candidate.accepted &&
              candidate.novelEnough &&
              (candidate.isIdeal ||
                  candidate.isGood ||
                  (candidate.tier == RouteQualityTier.acceptable &&
                      !difficultScenario))) {
            break;
          }
        } catch (e, stack) {
          final mapped = e is RouteServiceException
              ? e
              : _mapInvokeException(
                  error: e,
                  stack: stack,
                  routeType: scenario.routeType,
                );
          lastError = mapped;
          if (_isWorkerLimitError(mapped)) {
            _setWorkerLimitCooldown();
          }
          debugPrint(
            '[RouteService] RoundTrip candidate ${attempt + 1}/$maxAttempts fehlgeschlagen: ${mapped.debugMessage}',
          );
          if (_isFatalStructuredError(mapped)) {
            break;
          }
        }
      }

      if (bestCandidate?.accepted == true) {
        final acceptedMapboxCandidate = bestCandidate!;
        lastRouteGenerationSource = 'mapbox';
        final finalized = _finalizeAndRemember(
          scenario: scenario,
          route: acceptedMapboxCandidate.route,
          sampledCoordinates: acceptedMapboxCandidate.sampledCoordinates,
          fingerprint: acceptedMapboxCandidate.fingerprint,
        );
        await _maybeRecordRoutePoolCandidate(
          scenario: scenario,
          route: acceptedMapboxCandidate.route,
          fingerprint: acceptedMapboxCandidate.fingerprint,
          tier: acceptedMapboxCandidate.tier,
          qualityScore: acceptedMapboxCandidate.score,
          subscriptionTier: lastRouteSubscriptionTier,
        );
        if (spareCandidate != null && spareCandidate.novelEnough) {
          PreparedRouteBuffer.store(
            scenario.scenarioKey,
            PreparedRouteEntry(
              route: spareCandidate.route,
              variant: spareCandidate.variant,
              preparedAt: DateTime.now(),
            ),
          );
        } else if (!hasSeenHistory && !forceFreshVariant) {
          _schedulePreparedRoundTripRoute(
            scenario: scenario,
            styleConfig: styleConfig,
            startPosition: startPosition,
          );
        }
        return finalized;
      }

      final poolFallback = await _tryRoutePoolFallback(
        scenario: scenario,
        styleConfig: styleConfig,
        userLat: startPosition.latitude,
        userLng: startPosition.longitude,
        fallbackReason: lastError?.type.name ?? 'no_accepted_mapbox_route',
      );
      if (poolFallback != null) {
        return poolFallback;
      }

      // Availability beats diversity: if every fresh attempt only failed the
      // novelty gate, return the best clean duplicate instead of surfacing a
      // no-route error. The route still passed the same quality gates.
      final allowDuplicateEmergencyFallback = debugTrigger != 'settingsChanged';
      if (bestDuplicateCandidate?.accepted == true &&
          allowDuplicateEmergencyFallback) {
        final duplicate = bestDuplicateCandidate!;
        lastRouteDuplicateFallbackUsed = true;
        lastRouteEmergencyFallbackUsed = true;
        debugPrint(
          '[RouteService] RoundTrip: keine neue Variante gefunden, nutze beste brauchbare Wiederholung statt Fehler.',
        );
        _debugRouteSearch(
          '[Fallback] duplicateFallbackUsed=true recentFallbackUsed=false '
          'emergencyFallbackUsed=true trigger=$debugTrigger '
          'scenarioKey=${scenario.scenarioKey} routeVariantHint=${duplicate.variant.variantHint} '
          'fingerprintHint=${duplicate.variant.fingerprintHint}',
        );
        return _finalizeAndRemember(
          scenario: scenario,
          route: duplicate.route,
          sampledCoordinates: duplicate.sampledCoordinates,
          fingerprint: duplicate.fingerprint,
        );
      }
      if (bestDuplicateCandidate?.accepted == true) {
        _debugRouteSearch(
          '[Fallback] duplicateFallbackSkipped=true trigger=$debugTrigger '
          'scenarioKey=${scenario.scenarioKey} reason=settingsChangedRequiresFreshRoute',
        );
      }

      final recent = forceFreshVariant
          ? null
          : _recentSuccessfulRoutes[scenario.scenarioKey];
      if (scenario.isRoundTrip &&
          recent != null &&
          _shouldUseRecentFallbackRoute(
            recent,
            scenario: scenario,
            lastError: lastError,
            requireNovelty: !difficultScenario,
          )) {
        lastRouteFromCache = true;
        lastRouteRecentFallbackUsed = true;
        lastRouteEmergencyFallbackUsed = true;
        _debugRouteSearch(
          '[Fallback] recentFallbackUsed=true cacheHit=false '
          'emergencyFallbackUsed=true scenarioKey=${scenario.scenarioKey} '
          'forceFreshVariant=$forceFreshVariant trigger=$debugTrigger',
        );
        return _finalizeAndRememberRoute(
          scenario: scenario,
          route: recent,
          fromCache: true,
        );
      }

      final cached = forceFreshVariant
          ? null
          : await _loadCachedRoute(scenarioKey: scenario.scenarioKey);
      if (scenario.isRoundTrip &&
          cached != null &&
          _shouldUseCachedFallbackRoute(
            cached,
            scenario: scenario,
            lastError: lastError,
            requireNovelty: !difficultScenario,
          )) {
        lastRouteFromCache = true;
        lastRoutePersistentCacheFallbackUsed = true;
        lastRouteEmergencyFallbackUsed = true;
        _debugRouteSearch(
          '[Fallback] persistentCacheFallbackUsed=true recentFallbackUsed=false '
          'emergencyFallbackUsed=true scenarioKey=${scenario.scenarioKey} '
          'forceFreshVariant=$forceFreshVariant trigger=$debugTrigger',
        );
        return _finalizeAndRememberRoute(
          scenario: scenario,
          route: cached,
          fromCache: true,
        );
      }

      if (_canUseStructuredFallback(lastError)) {
        final fallback = await _tryRoundTripFallback(
          scenario: scenario,
          styleConfig: styleConfig,
          startPosition: startPosition,
          targetLocation: targetLocation,
        );
        if (fallback != null) {
          return fallback;
        }

        final rescueFallback = await _tryRoundTripRescueFallback(
          scenario: scenario,
          styleConfig: styleConfig,
          startPosition: startPosition,
          targetLocation: targetLocation,
        );
        if (rescueFallback != null) {
          return rescueFallback;
        }
      }

      if (recent != null &&
          _shouldUseRecentFallbackRoute(
            recent,
            scenario: scenario,
            lastError: lastError,
            requireNovelty: false,
          )) {
        lastRouteFromCache = true;
        lastRouteRecentFallbackUsed = true;
        lastRouteEmergencyFallbackUsed = true;
        _debugRouteSearch(
          '[Fallback] recentFallbackUsed=true afterStructuredFallback=true '
          'emergencyFallbackUsed=true scenarioKey=${scenario.scenarioKey} '
          'forceFreshVariant=$forceFreshVariant trigger=$debugTrigger',
        );
        return _finalizeAndRememberRoute(
          scenario: scenario,
          route: recent,
          fromCache: true,
        );
      }

      if (cached != null &&
          _shouldUseCachedFallbackRoute(
            cached,
            scenario: scenario,
            lastError: lastError,
            requireNovelty: false,
          )) {
        lastRouteFromCache = true;
        lastRoutePersistentCacheFallbackUsed = true;
        lastRouteEmergencyFallbackUsed = true;
        _debugRouteSearch(
          '[Fallback] persistentCacheFallbackUsed=true afterStructuredFallback=true '
          'recentFallbackUsed=false emergencyFallbackUsed=true '
          'scenarioKey=${scenario.scenarioKey} '
          'forceFreshVariant=$forceFreshVariant trigger=$debugTrigger',
        );
        return _finalizeAndRememberRoute(
          scenario: scenario,
          route: cached,
          fromCache: true,
        );
      }

      final warmupError = await _maybeBuildCoverageWarmupError(
        scenario: scenario,
        userLat: startPosition.latitude,
        userLng: startPosition.longitude,
        lastError: lastError,
      );
      if (warmupError != null) {
        throw warmupError;
      }

      throw lastError ??
          const RouteServiceException(
            type: RouteErrorType.quality,
            userMessage:
                'Kein passender Rundkurs gefunden. Bitte versuche es erneut.',
            debugMessage: 'RoundTrip generation failed without usable result.',
          );
    });
  }

  /// Berechnet eine Route von A nach B (direkt oder scenic).
  ///
  /// Sendet `offset_side` (-1 links, +1 rechts) an die Edge Function,
  /// der bei jeder Generierung invertiert wird → garantiert verschiedene Routen.
  /// Scenic-Varianten bekommen zusätzlich ±10% Jitter auf den Seed.
  Future<RouteResult> generatePointToPoint({
    required geo.Position startPosition,
    required double destinationLat,
    required double destinationLng,
    required String mode,
    bool scenic = false,
    int routeVariant = 0,
    bool avoidHighways = false,
    int diversitySeed = 0,
    bool forceFreshVariant = false,
    String subscriptionTier = 'premium',
  }) async {
    final styleConfig = RouteStyleConfig.forMode(mode);
    final normalizedVariant = routeVariant.clamp(0, 3);
    // Detour-Multiplier in Mitte der Fenster (siehe RouteStyleConfig).
    // Klein 1.32× landet in [1.15, 1.65], Mittel 1.65× in [1.40, 2.10],
    // Groß 2.10× in [1.75, 2.95]. So bleiben sie deutlich differenziert,
    // ohne dass Mapbox in Bergland (Dornbirn, Bregenzerwald) ständig das
    // Fenster verfehlt und auf "direkt" zurückfällt.
    final detourFactor = switch (normalizedVariant) {
      1 => 1.32,
      2 => 1.65,
      3 => 2.10,
      _ => scenic ? 1.15 : 1.0,
    };
    final detourMinimumExtraKm = switch (normalizedVariant) {
      1 => 4.0,
      2 => 10.0,
      3 => 20.0,
      _ => scenic ? 3.0 : 0.0,
    };
    final directDistanceKm = math.max(
      geo.Geolocator.distanceBetween(
            startPosition.latitude,
            startPosition.longitude,
            destinationLat,
            destinationLng,
          ) /
          1000.0,
      1.0,
    );
    final scenicTargetKm = switch (normalizedVariant) {
      1 => directDistanceKm * 1.32,
      2 => directDistanceKm * 1.65,
      3 => directDistanceKm * 2.10,
      _ => scenic ? directDistanceKm * 1.15 : directDistanceKm,
    };
    final initialTargetDistanceKm = math.max(
      scenicTargetKm,
      directDistanceKm + detourMinimumExtraKm,
    );
    final targetDistanceKm = styleConfig.clampPointToPointTargetKm(
      initialTargetDistanceKm,
      directDistanceKm: directDistanceKm,
      scenic: scenic,
      detourVariant: normalizedVariant,
    );
    final shouldDiversify = scenic || normalizedVariant > 0;
    final scenario = RouteScenario(
      routeType: 'POINT_TO_POINT',
      startLatitude: startPosition.latitude,
      startLongitude: startPosition.longitude,
      destinationLatitude: destinationLat,
      destinationLongitude: destinationLng,
      style: shouldDiversify ? mode : 'Standard',
      planningType: 'Zufall',
      targetDistanceKm: targetDistanceKm,
      detourLevel: normalizedVariant,
      avoidHighways: avoidHighways,
    );
    _resetRouteDebugState();
    lastRouteGenerationStartedAtMs = DateTime.now().millisecondsSinceEpoch;
    lastRouteDebugTrigger = 'unknown';
    lastRouteSubscriptionTier = _normalizeSubscriptionTier(subscriptionTier);
    lastRouteRequestedStyle = shouldDiversify ? mode : 'Standard';
    _activeScenarioKeyForDebug = scenario.scenarioKey;
    _activeForceFreshVariantForDebug = forceFreshVariant;
    _activeTriggerForDebug = 'unknown';

    if (forceFreshVariant) {
      RouteGenerationCoordinator.suspendBackgroundPreparation();
      PreparedRouteBuffer.clearScenario(scenario.scenarioKey);
    }

    final singleFlightKey = forceFreshVariant
        ? '${scenario.scenarioKey}|fresh|${DateTime.now().microsecondsSinceEpoch}'
        : scenario.scenarioKey;
    return RouteGenerationCoordinator.runSingleFlight(singleFlightKey, () async {
      if (_isFreeTier(lastRouteSubscriptionTier)) {
        final freePoolRoute = await _tryRoutePoolFallback(
          scenario: scenario,
          styleConfig: styleConfig,
          userLat: startPosition.latitude,
          userLng: startPosition.longitude,
          fallbackReason: 'free_pool_only',
          directDistanceKm: directDistanceKm,
        );
        if (freePoolRoute != null) {
          return freePoolRoute;
        }
        final coverage = await _ensureCoverageBootstrapStatus(
          scenario: scenario,
          userLat: startPosition.latitude,
          userLng: startPosition.longitude,
          subscriptionTier: lastRouteSubscriptionTier,
          createSeedJob: true,
        );
        if (coverage == null) {
          throw const RouteServiceException(
            type: RouteErrorType.noRoute,
            userMessage:
                'Keine passende Route gefunden. Bitte versuche es erneut.',
            debugMessage: 'No route and no pool coverage bucket available.',
          );
        }
        throw await _buildCoverageWarmupException(
          scenario: scenario,
          coverage: coverage,
          lastError: null,
        );
      }

      if (_isBasicTier(lastRouteSubscriptionTier)) {
        final basicPoolRoute = await _tryRoutePoolFallback(
          scenario: scenario,
          styleConfig: styleConfig,
          userLat: startPosition.latitude,
          userLng: startPosition.longitude,
          fallbackReason: 'pool_first_basic',
          directDistanceKm: directDistanceKm,
        );
        if (basicPoolRoute != null) {
          return basicPoolRoute;
        }
        await _ensureCoverageBootstrapStatus(
          scenario: scenario,
          userLat: startPosition.latitude,
          userLng: startPosition.longitude,
          subscriptionTier: lastRouteSubscriptionTier,
          createSeedJob: true,
        );
      }

      final prepared = forceFreshVariant
          ? null
          : _takePreparedRoute(
              scenario: scenario,
              styleConfig: styleConfig,
              directDistanceKm: directDistanceKm,
            );
      if (prepared != null) {
        return prepared;
      }

      final hasSeenHistory = SeenRouteRegistry.entriesForAny(
        _seenHistoryKeysForScenario(scenario),
      ).isNotEmpty;
      final shouldUseTwoLiveAttempts = shouldDiversify;
      // Client-Schleife: direkte A→B-Routen bekommen nur einen Live-Versuch,
      // Scenic-/Detour-Varianten behalten einen zweiten Versuch für echte
      // Diversifikation und transienten Provider-Pressure.
      final maxAttempts = shouldUseTwoLiveAttempts ? 2 : 1;
      _RouteCandidate? bestCandidate;
      _RouteCandidate? spareCandidate;
      RouteServiceException? lastError;

      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        if (_isInWorkerLimitCooldown()) break;
        final variant = _nextPointToPointVariant(
          scenario,
          normalizedVariant: normalizedVariant,
          diversitySeed: diversitySeed + attempt,
          shouldDiversify: shouldDiversify,
        );
        try {
          final candidate = await _requestPointToPointVariant(
            scenario: scenario,
            styleConfig: styleConfig,
            startPosition: startPosition,
            destinationLat: destinationLat,
            destinationLng: destinationLng,
            scenic: scenic,
            normalizedVariant: normalizedVariant,
            avoidHighways: avoidHighways,
            directDistanceKm: directDistanceKm,
            targetDistanceKm: targetDistanceKm,
            detourFactor: detourFactor,
            variant: variant,
            // 4-5 Pläne pro Versuch — A→B braucht Spielraum, damit
            // Klein/Mittel/Groß ihre Detour-Fenster wirklich treffen können.
            candidateBudget: normalizedVariant >= 2
                ? 5
                : (hasSeenHistory ? 3 : 4),
          );
          if (candidate.accepted) {
            if (_isBetterCandidate(candidate, bestCandidate)) {
              if (bestCandidate != null &&
                  _isBetterCandidate(bestCandidate, spareCandidate)) {
                spareCandidate = bestCandidate;
              }
              bestCandidate = candidate;
            } else if (_isBetterCandidate(candidate, spareCandidate)) {
              spareCandidate = candidate;
            }
          }
          if (candidate.accepted &&
              (candidate.isIdeal ||
                  candidate.isGood ||
                  (candidate.tier == RouteQualityTier.acceptable &&
                      !shouldUseTwoLiveAttempts))) {
            break;
          }
        } catch (e, stack) {
          final mapped = e is RouteServiceException
              ? e
              : _mapInvokeException(
                  error: e,
                  stack: stack,
                  routeType: scenario.routeType,
                );
          lastError = mapped;
          if (_isWorkerLimitError(mapped)) {
            _setWorkerLimitCooldown();
          }
          debugPrint(
            '[RouteService] A→B candidate ${attempt + 1}/$maxAttempts fehlgeschlagen: ${mapped.debugMessage}',
          );
          if (_isFatalStructuredError(mapped)) {
            break;
          }
        }
      }

      final acceptedCandidate = bestCandidate;
      if (acceptedCandidate != null && acceptedCandidate.accepted) {
        if (_needsStrongerPointToPointDetour(
          scenario: scenario,
          styleConfig: styleConfig,
          candidate: acceptedCandidate,
          directDistanceKm: directDistanceKm,
        )) {
          final scenicUpgrade = await _tryPointToPointFallback(
            scenario: scenario,
            startPosition: startPosition,
            destinationLat: destinationLat,
            destinationLng: destinationLng,
            avoidHighways: avoidHighways,
            directDistanceKm: directDistanceKm,
            allowDirectFallback: false,
          );
          if (scenicUpgrade != null) {
            return scenicUpgrade;
          }
        }
        lastRouteGenerationSource = 'mapbox';
        final finalized = _finalizeAndRemember(
          scenario: scenario,
          route: acceptedCandidate.route,
          sampledCoordinates: acceptedCandidate.sampledCoordinates,
          fingerprint: acceptedCandidate.fingerprint,
        );
        await _maybeRecordRoutePoolCandidate(
          scenario: scenario,
          route: acceptedCandidate.route,
          fingerprint: acceptedCandidate.fingerprint,
          tier: acceptedCandidate.tier,
          qualityScore: acceptedCandidate.score,
          subscriptionTier: lastRouteSubscriptionTier,
        );
        if (spareCandidate != null) {
          PreparedRouteBuffer.store(
            scenario.scenarioKey,
            PreparedRouteEntry(
              route: spareCandidate.route,
              variant: spareCandidate.variant,
              preparedAt: DateTime.now(),
            ),
          );
        } else if (shouldDiversify && !forceFreshVariant) {
          _schedulePreparedPointToPointRoute(
            scenario: scenario,
            styleConfig: styleConfig,
            startPosition: startPosition,
            destinationLat: destinationLat,
            destinationLng: destinationLng,
            avoidHighways: avoidHighways,
            directDistanceKm: directDistanceKm,
          );
        }
        return finalized;
      }

      final poolFallback = await _tryRoutePoolFallback(
        scenario: scenario,
        styleConfig: styleConfig,
        userLat: startPosition.latitude,
        userLng: startPosition.longitude,
        fallbackReason: lastError?.type.name ?? 'no_accepted_mapbox_route',
        directDistanceKm: directDistanceKm,
      );
      if (poolFallback != null) {
        return poolFallback;
      }

      if (_canUseStructuredFallback(lastError)) {
        final fallback = await _tryPointToPointFallback(
          scenario: scenario,
          startPosition: startPosition,
          destinationLat: destinationLat,
          destinationLng: destinationLng,
          avoidHighways: avoidHighways,
          directDistanceKm: directDistanceKm,
          allowDirectFallback: scenario.detourLevel <= 0,
        );
        if (fallback != null) {
          return fallback;
        }
      }

      final cached = forceFreshVariant
          ? null
          : await _loadRecentOrCachedRoute(scenarioKey: scenario.scenarioKey);
      if (cached != null &&
          _shouldUseCachedFallbackRoute(
            cached,
            scenario: scenario,
            lastError: lastError,
          )) {
        lastRouteFromCache = true;
        return _finalizeAndRememberRoute(
          scenario: scenario,
          route: cached,
          fromCache: true,
        );
      }

      final warmupError = await _maybeBuildCoverageWarmupError(
        scenario: scenario,
        userLat: startPosition.latitude,
        userLng: startPosition.longitude,
        lastError: lastError,
      );
      if (warmupError != null) {
        throw warmupError;
      }

      throw lastError ??
          const RouteServiceException(
            type: RouteErrorType.noRoute,
            userMessage:
                'Keine passende Route gefunden. Bitte versuche es erneut.',
            debugMessage: 'Point-to-point generation failed without result.',
          );
    });
  }

  /// Baut einen direkten Zugang zu einer bestehenden Route, ohne deren
  /// logischen Ursprung oder Endpunkt umzudefinieren.
  ///
  /// Das Ergebnis enthält:
  /// - [originalRoute]: die unveränderte geplante Route
  /// - [followOnRoute]: die Originalroute ab dem Join-Punkt
  /// - [sessionRoute]: die vom Join-Punkt weiterzufahrende Session-Route,
  ///   optional mit Return-Leg zurück zum aktuellen Session-Startpunkt
  /// - [activeRoute]: Access-Leg + Session-Route für die aktuelle Navigation
  Future<RouteAccessPlan> buildAccessRouteToExistingRoute({
    required geo.Position currentPosition,
    required RouteResult existingRoute,
    String mode = 'Standard',
    bool avoidHighways = false,
    int? preferredJoinIndex,
    bool returnToSessionOrigin = false,
    bool rebaseClosedLoop = false,
  }) async {
    if (existingRoute.coordinates.length < 2) {
      throw const RouteServiceException(
        type: RouteErrorType.validation,
        userMessage: 'Die bestehende Route ist unvollständig.',
        debugMessage: 'Cannot build access plan for route with <2 coordinates.',
      );
    }

    final joinPoint = _accessPlanner.chooseJoinPoint(
      currentPosition: currentPosition,
      existingRoute: existingRoute,
      preferredJoinIndex: preferredJoinIndex,
      rebaseClosedLoop: rebaseClosedLoop,
    );
    final accessKey = _accessSingleFlightKey(
      currentPosition: currentPosition,
      joinPoint: joinPoint,
      existingRoute: existingRoute,
    );

    return RouteGenerationCoordinator.runSingleFlight(accessKey, () async {
      final followOnRoute = _sliceRouteFromIndex(
        existingRoute,
        joinPoint.index,
        wrapClosedLoop: returnToSessionOrigin,
      );
      final logicalOrigin = _copyCoordinate(existingRoute.coordinates.first);
      final logicalEnd = _copyCoordinate(existingRoute.coordinates.last);
      final sessionOrigin = [
        currentPosition.longitude,
        currentPosition.latitude,
      ];
      final routeStartDistanceMeters = _distanceBetweenCoordinates(
        sessionOrigin,
        existingRoute.coordinates.first,
      );
      final routePassesNearUser =
          joinPoint.distanceFromCurrentMeters <=
          RouteAccessPlanner.nearbyPassJoinDistanceMeters;
      final routeRebasedToUser = rebaseClosedLoop && joinPoint.index > 0;
      final joinPointType = _classifyAccessJoinPointType(
        preferredJoinIndex: preferredJoinIndex,
        joinPoint: joinPoint,
        rebaseClosedLoop: rebaseClosedLoop,
        routePassesNearUser: routePassesNearUser,
      );
      final metaBase = _buildAccessRouteMeta(
        existingRoute: existingRoute,
        joinPoint: joinPoint,
        joinPointType: joinPointType,
        routeStartDistanceMeters: routeStartDistanceMeters,
        routePassesNearUser: routePassesNearUser,
        routeRebasedToUser: routeRebasedToUser,
      );
      final followOnRouteWithMeta = _routeWithEdgeMeta(followOnRoute, {
        ...metaBase,
        'return_leg_used': false,
      });

      if (joinPoint.distanceFromCurrentMeters <=
          RouteAccessPlanner.directJoinDistanceMeters) {
        final returnLeg = await _buildReturnLegIfNeeded(
          sessionOrigin: sessionOrigin,
          followOnRoute: followOnRoute,
          mode: mode,
          avoidHighways: avoidHighways,
          enabled: returnToSessionOrigin,
        );
        final sessionRoute = returnLeg == null
            ? followOnRouteWithMeta
            : _routeWithEdgeMeta(
                _mergeRouteSegments([followOnRoute, returnLeg]),
                {...metaBase, 'return_leg_used': true},
              );
        return RouteAccessPlan(
          originalRoute: existingRoute,
          activeRoute: sessionRoute,
          followOnRoute: followOnRouteWithMeta,
          sessionRoute: sessionRoute,
          joinPoint: joinPoint,
          returnLeg: returnLeg,
          logicalOrigin: logicalOrigin,
          logicalEnd: logicalEnd,
          sessionOrigin: sessionOrigin,
          sessionEnd: _copyCoordinate(sessionRoute.coordinates.last),
          joinPointType: joinPointType,
          routeStartDistanceMeters: routeStartDistanceMeters,
          routePassesNearUser: routePassesNearUser,
          routeRebasedToUser: routeRebasedToUser,
        );
      }

      final accessLeg = await _requestAccessLegToJoin(
        currentPosition: currentPosition,
        joinPoint: joinPoint,
        mode: mode,
        avoidHighways: avoidHighways,
      );
      final returnLeg = await _buildReturnLegIfNeeded(
        sessionOrigin: sessionOrigin,
        followOnRoute: followOnRoute,
        mode: mode,
        avoidHighways: avoidHighways,
        enabled: returnToSessionOrigin,
      );
      final sessionRoute = returnLeg == null
          ? followOnRouteWithMeta
          : _routeWithEdgeMeta(
              _mergeRouteSegments([followOnRoute, returnLeg]),
              {...metaBase, 'return_leg_used': true},
            );
      final accessLegDistanceKm =
          (accessLeg.distanceMeters ??
              _distanceAlongCoordinates(accessLeg.coordinates)) /
          1000.0;
      final activeRoute = _routeWithEdgeMeta(
        _mergeAccessAndFollowOnRoutes(
          accessLeg: accessLeg,
          followOnRoute: sessionRoute,
        ),
        {
          ...metaBase,
          'access_leg_used': true,
          'access_leg_distance_km': double.parse(
            accessLegDistanceKm.toStringAsFixed(2),
          ),
          'return_leg_used': returnLeg != null,
        },
      );

      return RouteAccessPlan(
        originalRoute: existingRoute,
        activeRoute: activeRoute,
        followOnRoute: followOnRouteWithMeta,
        sessionRoute: sessionRoute,
        accessLeg: accessLeg,
        returnLeg: returnLeg,
        joinPoint: joinPoint,
        logicalOrigin: logicalOrigin,
        logicalEnd: logicalEnd,
        sessionOrigin: sessionOrigin,
        sessionEnd: _copyCoordinate(activeRoute.coordinates.last),
        joinPointType: joinPointType,
        routeStartDistanceMeters: routeStartDistanceMeters,
        routePassesNearUser: routePassesNearUser,
        routeRebasedToUser: routeRebasedToUser,
      );
    });
  }

  String _classifyAccessJoinPointType({
    required int? preferredJoinIndex,
    required RouteJoinPoint joinPoint,
    required bool rebaseClosedLoop,
    required bool routePassesNearUser,
  }) {
    if (preferredJoinIndex != null) return 'preferred_join';
    if (joinPoint.index == 0) return 'route_start';
    if (rebaseClosedLoop && routePassesNearUser) return 'nearby_pass';
    if (rebaseClosedLoop) return 'rebased_loop_join';
    return 'forward_join';
  }

  Map<String, dynamic> _buildAccessRouteMeta({
    required RouteResult existingRoute,
    required RouteJoinPoint joinPoint,
    required String joinPointType,
    required double routeStartDistanceMeters,
    required bool routePassesNearUser,
    required bool routeRebasedToUser,
  }) {
    return {
      ...existingRoute.edgeMeta,
      'access_leg_used': false,
      'access_leg_distance_km': null,
      'join_point_type': joinPointType,
      'route_start_distance_km': double.parse(
        (routeStartDistanceMeters / 1000.0).toStringAsFixed(2),
      ),
      'route_passes_near_user': routePassesNearUser,
      'route_rebased_to_user': routeRebasedToUser,
      'access_join_index': joinPoint.index,
      'access_join_progress_ratio': double.parse(
        joinPoint.progressRatio.toStringAsFixed(3),
      ),
      'access_join_distance_km': double.parse(
        (joinPoint.distanceFromCurrentMeters / 1000.0).toStringAsFixed(2),
      ),
      'return_leg_used': false,
    };
  }

  /// Generiert sequentiell Rundkurse mit Early-Exit bei guter Qualität.
  /// KEINE parallelen Requests mehr → schont Server und verhindert WORKER_LIMIT.
  ///
  /// Strategie: Maximal [maxCandidates] Kandidaten nacheinander, Abbruch sobald
  /// ein "idealer" oder "acceptable" Kandidat gefunden wird.
  Future<List<RouteResult>> generateSequentialRoundTrips({
    required geo.Position startPosition,
    required int targetDistanceKm,
    required String mode,
    required String planningType,
    int maxCandidates = 3,
  }) async {
    final results = <RouteResult>[];
    for (var i = 0; i < maxCandidates; i++) {
      try {
        results.add(
          await generateRoundTrip(
            startPosition: startPosition,
            targetDistanceKm: targetDistanceKm,
            mode: mode,
            planningType: planningType,
          ),
        );
      } catch (_) {
        break;
      }
    }
    return results;
  }

  /// Generiert sequentiell A→B-Routen mit Early-Exit.
  /// KEINE parallelen Requests mehr.
  Future<List<RouteResult>> generateSequentialPointToPoints({
    required geo.Position startPosition,
    required double destinationLat,
    required double destinationLng,
    required String mode,
    bool scenic = false,
    int routeVariant = 0,
    bool avoidHighways = false,
    int maxCandidates = 2,
  }) async {
    final results = <RouteResult>[];
    for (var i = 0; i < maxCandidates; i++) {
      try {
        results.add(
          await generatePointToPoint(
            startPosition: startPosition,
            destinationLat: destinationLat,
            destinationLng: destinationLng,
            mode: mode,
            scenic: scenic,
            routeVariant: routeVariant,
            avoidHighways: avoidHighways,
            diversitySeed: i,
          ),
        );
      } catch (_) {
        break;
      }
    }
    return results;
  }

  // ─────────────────────── WORKER_LIMIT Handling ───────────────────────────

  static bool _isWorkerLimitError(dynamic error) {
    if (error is RouteServiceException) {
      return error.type == RouteErrorType.workerLimit ||
          error.debugMessage.contains('WORKER_LIMIT') ||
          error.debugMessage.contains('546') ||
          error.debugMessage.contains('compute resources');
    }
    return error.toString().contains('WORKER_LIMIT') ||
        error.toString().contains('546');
  }

  static void _setWorkerLimitCooldown() {
    _workerLimitCooldownUntil = DateTime.now().add(const Duration(seconds: 8));
    debugPrint(
      '[RouteService] ⚠️ WORKER_LIMIT erkannt — 8s Cooldown aktiviert',
    );
  }

  static bool _isInWorkerLimitCooldown() {
    if (_workerLimitCooldownUntil == null) return false;
    if (DateTime.now().isAfter(_workerLimitCooldownUntil!)) {
      _workerLimitCooldownUntil = null;
      return false;
    }
    return true;
  }

  // ─────────────────────── Diversität & Fingerprint ────────────────────────

  /// Inkrementiert den globalen Diversitäts-Index.
  /// Sollte bei jedem User-initiierten "Neu generieren" aufgerufen werden.
  static void incrementDiversityIndex() {
    _globalDiversityIndex = (_globalDiversityIndex + 1) % 360;
    debugPrint('[RouteService] 🎲 Diversitäts-Index: $_globalDiversityIndex');
  }

  /// Berechnet einen Fingerprint für eine Route (basierend auf Geometrie).
  static String _calculateRouteFingerprint(RouteResult route) {
    if (route.coordinates.isEmpty) return 'empty';
    // Sampling: 10 Punkte gleichmäßig verteilt
    final step = (route.coordinates.length / 10).ceil().clamp(1, 100);
    final samples = <String>[];
    for (var i = 0; i < route.coordinates.length; i += step) {
      final coord = route.coordinates[i];
      // Auf ~50m runden
      final lat = (coord[1] * 2000).round();
      final lng = (coord[0] * 2000).round();
      samples.add('$lat,$lng');
    }
    return samples.join('|');
  }

  /// Prüft ob eine Route bereits kürzlich angezeigt wurde.
  static bool isRouteRecentlySeen(String scenarioKey, RouteResult route) {
    final fingerprint = _calculateRouteFingerprint(route);
    return SeenRouteRegistry.hasExactFingerprint(scenarioKey, fingerprint);
  }

  /// Merkt sich eine Route als "gesehen" für ein Szenario.
  static void markRouteAsSeen(String scenarioKey, RouteResult route) {
    final fingerprint = _calculateRouteFingerprint(route);
    final sampledCoordinates = route.coordinates
        .where((point) => point.length >= 2)
        .map((point) => [point[0], point[1]])
        .toList();
    SeenRouteRegistry.remember(
      scenarioKey,
      fingerprint: fingerprint,
      sampledCoordinates: sampledCoordinates,
    );
  }

  static Iterable<String> _seenHistoryKeysForScenario(RouteScenario scenario) {
    if (!scenario.isRoundTrip) {
      return <String>{scenario.scenarioKey};
    }
    return <String>{scenario.scenarioKey, scenario.noveltyKey};
  }

  static String _recentDisplayedKeyForScenario(RouteScenario scenario) {
    return scenario.scenarioKey;
  }

  /// Löscht die "gesehen"-Historie für ein Szenario.
  static void clearSeenRoutes(String scenarioKey) {
    SeenRouteRegistry.clearScenario(scenarioKey);
  }

  /// Löscht alle "gesehen"-Historien.
  static void clearAllSeenRoutes() {
    SeenRouteRegistry.clearAll();
  }

  // ─────────────────────── LEGACY: Parallel-Methoden (deprecated) ──────────

  /// @deprecated Nutze [generateSequentialRoundTrips] stattdessen.
  /// Diese Methode wird nur noch für Abwärtskompatibilität behalten.
  @Deprecated(
    'Nutze generateSequentialRoundTrips() — parallele Requests verursachen WORKER_LIMIT',
  )
  Future<List<RouteResult>> generateMultipleRoundTrips({
    required geo.Position startPosition,
    required int targetDistanceKm,
    required String mode,
    required String planningType,
    int count = 5,
  }) {
    // Delegiere an sequentielle Variante
    return generateSequentialRoundTrips(
      startPosition: startPosition,
      targetDistanceKm: targetDistanceKm,
      mode: mode,
      planningType: planningType,
      maxCandidates: count.clamp(1, 3), // Max 3 statt 5
    );
  }

  /// @deprecated Nutze [generateSequentialPointToPoints] stattdessen.
  @Deprecated(
    'Nutze generateSequentialPointToPoints() — parallele Requests verursachen WORKER_LIMIT',
  )
  Future<List<RouteResult>> generateMultiplePointToPoints({
    required geo.Position startPosition,
    required double destinationLat,
    required double destinationLng,
    required String mode,
    bool scenic = false,
    int routeVariant = 0,
    bool avoidHighways = false,
    int count = 4,
  }) {
    // Delegiere an sequentielle Variante
    return generateSequentialPointToPoints(
      startPosition: startPosition,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      mode: mode,
      scenic: scenic,
      routeVariant: routeVariant,
      avoidHighways: avoidHighways,
      maxCandidates: count.clamp(1, 2), // Max 2 statt 4
    );
  }

  // ──────────────────────────── Internal ─────────────────────────────────────

  Map<String, dynamic> _buildRoundTripRequest({
    required geo.Position startPosition,
    required int targetDistanceKm,
    required String mode,
    required String planningType,
    required RouteStyleConfig styleConfig,
    required RouteVariant variant,
    Map<String, double>? targetLocation,
    double? directionHint,
    int candidateBudget = 3,
    bool avoidHighways = false,
  }) {
    return <String, dynamic>{
      'startLocation': {
        'latitude': startPosition.latitude,
        'longitude': startPosition.longitude,
      },
      'targetDistance': targetDistanceKm,
      'mode': mode,
      'route_type': 'ROUND_TRIP',
      'planning_type': planningType,
      'language': 'de',
      'randomSeed': variant.seed,
      'continue_straight': true, // Verhindert unnötige U-Turns
      'avoid_highways': avoidHighways,
      'route_variant_hint': variant.variantHint,
      'route_fingerprint_hint': variant.fingerprintHint,
      'max_candidate_attempts': candidateBudget,
      ...styleConfig.toRequestHints(),
      if (targetLocation != null) 'targetLocation': targetLocation,
      // Richtungshinweis für die Edge Function: bestimmt die Hauptrichtung
      // der Waypoint-Verteilung (0-359°). Wird als baseBearing verwendet.
      if (directionHint != null) 'direction_hint': directionHint.round() % 360,
    };
  }

  Map<String, dynamic> _buildPointToPointRequest({
    required geo.Position startPosition,
    required double destinationLat,
    required double destinationLng,
    required String mode,
    required bool scenic,
    required int normalizedVariant,
    required bool avoidHighways,
    required RouteStyleConfig styleConfig,
    required double targetDistanceKm,
    required double detourFactor,
    required RouteVariant variant,
    int? offsetSide,
    int candidateBudget = 5,
  }) {
    return <String, dynamic>{
      'startLocation': {
        'latitude': startPosition.latitude,
        'longitude': startPosition.longitude,
      },
      'destination_location': {
        'latitude': destinationLat,
        'longitude': destinationLng,
      },
      'route_type': 'POINT_TO_POINT',
      'planning_type': 'Zufall',
      'mode': scenic ? mode : 'Standard',
      'avoid_highways': avoidHighways,
      'language': 'de',
      'continue_straight': true,
      'randomSeed': variant.seed,
      'route_variant_hint': variant.variantHint,
      'route_fingerprint_hint': variant.fingerprintHint,
      'max_candidate_attempts': candidateBudget,
      if (scenic || normalizedVariant > 0) ...styleConfig.toRequestHints(),
      if (scenic || normalizedVariant > 0) ...{
        'targetDistance': double.parse(targetDistanceKm.toStringAsFixed(1)),
        'detour_level': normalizedVariant,
        'detour_factor': detourFactor,
      },
      // Seite für Waypoint-Offset: -1 = links, +1 = rechts der Direktlinie.
      // Edge Function nutzt dies als baseSide-Override für Diversifizierung.
      if ((offsetSide ?? variant.offsetSide) != null)
        'offset_side': offsetSide ?? variant.offsetSide,
    };
  }

  String _accessSingleFlightKey({
    required geo.Position currentPosition,
    required RouteJoinPoint joinPoint,
    required RouteResult existingRoute,
  }) {
    final roundedLat = (currentPosition.latitude * 1000).round();
    final roundedLng = (currentPosition.longitude * 1000).round();
    final joinLat = (joinPoint.coordinate[1] * 1000).round();
    final joinLng = (joinPoint.coordinate[0] * 1000).round();
    return 'access_${existingRoute.coordinates.length}_${joinPoint.index}'
        '_${roundedLat}_$roundedLng'
        '_${joinLat}_$joinLng';
  }

  Future<RouteResult> _requestAccessLegToJoin({
    required geo.Position currentPosition,
    required RouteJoinPoint joinPoint,
    required String mode,
    required bool avoidHighways,
  }) async {
    return _requestDirectLegToCoordinate(
      startPosition: currentPosition,
      destinationCoordinate: joinPoint.coordinate,
      mode: mode,
      avoidHighways: avoidHighways,
      variantIndex: joinPoint.index,
      variantHint: 'access',
      fingerprintHint: 'join_${joinPoint.index}',
      candidateBudget: 3,
    );
  }

  Future<RouteResult?> _buildReturnLegIfNeeded({
    required List<double> sessionOrigin,
    required RouteResult followOnRoute,
    required String mode,
    required bool avoidHighways,
    required bool enabled,
  }) async {
    if (!enabled || followOnRoute.coordinates.length < 2) return null;
    final endCoordinate = followOnRoute.coordinates.last;
    final distanceToSessionOrigin = _distanceBetweenCoordinates(
      endCoordinate,
      sessionOrigin,
    );
    if (distanceToSessionOrigin <= 90.0) return null;

    final startPosition = _positionFromCoordinate(endCoordinate);
    return _requestDirectLegToCoordinate(
      startPosition: startPosition,
      destinationCoordinate: sessionOrigin,
      mode: mode,
      avoidHighways: avoidHighways,
      variantIndex: followOnRoute.coordinates.length,
      variantHint: 'return',
      fingerprintHint:
          'return_${(sessionOrigin[1] * 10000).round()}_${(sessionOrigin[0] * 10000).round()}',
      candidateBudget: 3,
    );
  }

  Future<RouteResult> _requestDirectLegToCoordinate({
    required geo.Position startPosition,
    required List<double> destinationCoordinate,
    required String mode,
    required bool avoidHighways,
    required int variantIndex,
    required String variantHint,
    required String fingerprintHint,
    required int candidateBudget,
  }) async {
    final directDistanceKm = math.max(
      geo.Geolocator.distanceBetween(
            startPosition.latitude,
            startPosition.longitude,
            destinationCoordinate[1],
            destinationCoordinate[0],
          ) /
          1000.0,
      0.4,
    );
    final styleConfig = RouteStyleConfig.forMode(mode);
    final variant = RouteVariant(
      index: variantIndex,
      seed: _nextRandomSeed(),
      angleOffset: 0,
      radiusJitter: 0,
      offsetBearing: 0,
      fingerprintHint: fingerprintHint,
      variantHint: variantHint,
    );
    final request = _buildPointToPointRequest(
      startPosition: startPosition,
      destinationLat: destinationCoordinate[1],
      destinationLng: destinationCoordinate[0],
      mode: 'Standard',
      scenic: false,
      normalizedVariant: 0,
      avoidHighways: avoidHighways,
      styleConfig: styleConfig,
      targetDistanceKm: directDistanceKm,
      detourFactor: 1.0,
      variant: variant,
      // Access-/Return-Legs sind sicherheitskritisch — lieber wenige echte
      // Straßenpläne testen, als dem User ein Luftlinien-Fragment zu zeigen.
      candidateBudget: candidateBudget,
    );

    try {
      final route = await _invoke(request);
      final snapped = _snapRouteToStartPosition(route, startPosition);
      return _filteredRouteResult(snapped);
    } on RouteServiceException catch (e) {
      if (avoidHighways) {
        debugPrint(
          '[RouteService] Access-Leg fehlgeschlagen mit aktivem avoidHighways (${e.debugMessage}) — kein Relax auf Autobahn',
        );
      }
      rethrow;
    }
  }

  RouteResult _sliceRouteFromIndex(
    RouteResult route,
    int startIndex, {
    bool wrapClosedLoop = false,
  }) {
    final clampedStart = startIndex
        .clamp(0, math.max(0, route.coordinates.length - 2))
        .toInt();
    final shouldWrap =
        wrapClosedLoop &&
        clampedStart > 0 &&
        _isClosedLoopCoordinates(route.coordinates);
    final slicedCoordinates = shouldWrap
        ? <List<double>>[
            ...route.coordinates.sublist(clampedStart).map(_copyCoordinate),
            ...route.coordinates
                .sublist(
                  1,
                  math.min(clampedStart + 1, route.coordinates.length),
                )
                .map(_copyCoordinate),
          ]
        : route.coordinates
              .sublist(clampedStart)
              .map(_copyCoordinate)
              .toList(growable: false);
    final geometry = <String, dynamic>{
      'type': 'LineString',
      'coordinates': slicedCoordinates,
    };
    final sourceGeometryDistanceMeters = _distanceAlongCoordinates(
      route.coordinates,
    );
    final sourceDistanceMeters =
        route.distanceMeters ?? sourceGeometryDistanceMeters;
    final sourceDistanceScale = sourceGeometryDistanceMeters > 0
        ? sourceDistanceMeters / sourceGeometryDistanceMeters
        : 1.0;
    final distanceMeters =
        _distanceAlongCoordinates(slicedCoordinates) * sourceDistanceScale;
    final durationSeconds =
        route.durationSeconds != null && sourceDistanceMeters > 0
        ? route.durationSeconds! * (distanceMeters / sourceDistanceMeters)
        : route.durationSeconds;
    final maneuvers = shouldWrap
        ? const <RouteManeuver>[]
        : route.maneuvers
              .where((maneuver) => maneuver.routeIndex >= clampedStart)
              .map(
                (maneuver) => _copyManeuver(
                  maneuver,
                  routeIndex: math
                      .max(0, maneuver.routeIndex - clampedStart)
                      .toInt(),
                ),
              )
              .toList(growable: false);
    final speedLimits = shouldWrap
        ? const <SpeedLimitSegment>[]
        : route.speedLimits
              .where((segment) => segment.endIndex >= clampedStart)
              .map((segment) {
                final start = math
                    .max(0, segment.startIndex - clampedStart)
                    .toInt();
                final end = math
                    .max(start, segment.endIndex - clampedStart)
                    .toInt();
                return SpeedLimitSegment(
                  startIndex: start,
                  endIndex: end,
                  speedKmh: segment.speedKmh,
                );
              })
              .toList(growable: false);

    return _filteredRouteResult(
      RouteResult(
        geoJson: json.encode(geometry),
        geometry: geometry,
        coordinates: slicedCoordinates,
        maneuvers: maneuvers,
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
        distanceKm: distanceMeters / 1000.0,
        speedLimits: speedLimits,
      ),
    );
  }

  RouteResult _mergeAccessAndFollowOnRoutes({
    required RouteResult accessLeg,
    required RouteResult followOnRoute,
  }) {
    return _mergeRouteSegments([accessLeg, followOnRoute]);
  }

  RouteResult _mergeRouteSegments(List<RouteResult> segments) {
    final nonEmptySegments = segments
        .where((segment) => segment.coordinates.length >= 2)
        .toList(growable: false);
    if (nonEmptySegments.isEmpty) {
      throw const RouteServiceException(
        type: RouteErrorType.validation,
        userMessage: 'Die zusammengesetzte Route ist unvollständig.',
        debugMessage: 'Cannot merge empty route segments.',
      );
    }

    final combinedCoordinates = <List<double>>[];
    final combinedManeuvers = <RouteManeuver>[];
    final combinedSpeedLimits = <SpeedLimitSegment>[];
    var routeIndexOffset = 0;
    var distanceMeters = 0.0;
    var durationSeconds = 0.0;

    for (final segment in nonEmptySegments) {
      final coordinates = segment.coordinates
          .map(_copyCoordinate)
          .toList(growable: true);
      if (combinedCoordinates.isNotEmpty &&
          coordinates.isNotEmpty &&
          _distanceBetweenCoordinates(
                combinedCoordinates.last,
                coordinates.first,
              ) <=
              30.0) {
        coordinates.removeAt(0);
      }

      combinedCoordinates.addAll(coordinates);
      combinedManeuvers.addAll(
        segment.maneuvers.map(
          (maneuver) => _copyManeuver(
            maneuver,
            routeIndex: maneuver.routeIndex + routeIndexOffset,
          ),
        ),
      );
      combinedSpeedLimits.addAll(
        segment.speedLimits.map(
          (speedLimit) => SpeedLimitSegment(
            startIndex: speedLimit.startIndex + routeIndexOffset,
            endIndex: speedLimit.endIndex + routeIndexOffset,
            speedKmh: speedLimit.speedKmh,
          ),
        ),
      );
      distanceMeters +=
          segment.distanceMeters ??
          _distanceAlongCoordinates(segment.coordinates);
      durationSeconds += segment.durationSeconds ?? 0.0;
      routeIndexOffset = math.max(0, combinedCoordinates.length - 1);
    }

    final geometry = <String, dynamic>{
      'type': 'LineString',
      'coordinates': combinedCoordinates,
    };

    return _filteredRouteResult(
      RouteResult(
        geoJson: json.encode(geometry),
        geometry: geometry,
        coordinates: combinedCoordinates,
        maneuvers: combinedManeuvers,
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds > 0 ? durationSeconds : null,
        distanceKm: distanceMeters / 1000.0,
        speedLimits: combinedSpeedLimits,
      ),
    );
  }

  geo.Position _positionFromCoordinate(List<double> coordinate) {
    return geo.Position(
      latitude: coordinate[1],
      longitude: coordinate[0],
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 5,
      speed: 0,
      speedAccuracy: 1,
    );
  }

  bool _isClosedLoopCoordinates(List<List<double>> coordinates) {
    if (coordinates.length < 3) return false;
    return _distanceBetweenCoordinates(coordinates.first, coordinates.last) <=
        90.0;
  }

  RouteResult _filteredRouteResult(RouteResult result) {
    return RouteResult(
      geoJson: result.geoJson,
      geometry: result.geometry,
      coordinates: result.coordinates
          .map(_copyCoordinate)
          .toList(growable: false),
      maneuvers: filterManeuvers(result.maneuvers),
      distanceMeters: result.distanceMeters,
      durationSeconds: result.durationSeconds,
      distanceKm: result.distanceKm,
      speedLimits: result.speedLimits,
      edgeMeta: result.edgeMeta,
    );
  }

  RouteResult _routeWithEdgeMeta(
    RouteResult result,
    Map<String, dynamic> edgeMeta,
  ) {
    return RouteResult(
      geoJson: result.geoJson,
      geometry: result.geometry,
      coordinates: result.coordinates
          .map(_copyCoordinate)
          .toList(growable: false),
      maneuvers: filterManeuvers(result.maneuvers),
      distanceMeters: result.distanceMeters,
      durationSeconds: result.durationSeconds,
      distanceKm: result.distanceKm,
      speedLimits: result.speedLimits,
      edgeMeta: edgeMeta,
    );
  }

  RouteManeuver _copyManeuver(
    RouteManeuver maneuver, {
    required int routeIndex,
  }) {
    return RouteManeuver(
      latitude: maneuver.latitude,
      longitude: maneuver.longitude,
      routeIndex: routeIndex,
      icon: maneuver.icon,
      announcement: maneuver.announcement,
      instruction: maneuver.instruction,
      maneuverType: maneuver.maneuverType,
      roundaboutExitNumber: maneuver.roundaboutExitNumber,
    );
  }

  List<double> _copyCoordinate(List<double> coordinate) {
    return [coordinate[0], coordinate[1]];
  }

  double _distanceAlongCoordinates(List<List<double>> coordinates) {
    if (coordinates.length < 2) return 0.0;
    var total = 0.0;
    for (var index = 1; index < coordinates.length; index++) {
      total += _distanceBetweenCoordinates(
        coordinates[index - 1],
        coordinates[index],
      );
    }
    return total;
  }

  double _distanceBetweenCoordinates(List<double> first, List<double> second) {
    return geo.Geolocator.distanceBetween(
      first[1],
      first[0],
      second[1],
      second[0],
    );
  }

  Future<RouteResult> _invoke(Map<String, dynamic> body) async {
    final requestUrl =
        _debugEndpointForInvoker(_invoker) ??
        '${AppConstants.supabaseUrl}/functions/v1/$edgeFunction';
    final routeType = body['route_type']?.toString() ?? 'ROUND_TRIP';
    final mode = body['mode'];
    final planningType = body['planning_type'];
    body['client_scenario_key'] ??=
        _activeScenarioKeyForDebug ?? scenarioKey(body);
    body['client_force_fresh_variant'] ??= _activeForceFreshVariantForDebug;
    body['client_trigger'] ??= _activeTriggerForDebug;
    final clientScenarioKey =
        body['client_scenario_key']?.toString() ?? scenarioKey(body);
    final routeVariantHint =
        body['route_variant_hint'] ?? body['variant_hint'] ?? '';
    final fingerprintHint =
        body['route_fingerprint_hint'] ?? body['fingerprint_hint'] ?? '';
    final clientForceFreshVariant = body['client_force_fresh_variant'] == true;
    final clientTrigger = body['client_trigger']?.toString() ?? 'unknown';
    final hasDestination = requiresDestination(routeType)
        ? body['destination_location'] != null
        : false;
    final hasTargetDistance = body['targetDistance'] != null;
    debugPrint(
      '[RouteService] Request → url=$requestUrl, routeType=$routeType, planning=$planningType, mode=$mode, hasDestination=$hasDestination, hasTargetDistance=$hasTargetDistance, avoidHighways=${body['avoid_highways'] == true}',
    );

    debugPrint(
      '[RouteService] Invoking Edge Function with: ${body['planning_type']}, mode: ${body['mode']}',
    );

    // Session-Cache prüfen
    final cacheKey = _cacheKey(body);
    final cached = _sessionCache[cacheKey];
    if (cached != null) {
      lastRouteSessionCacheHit = true;
      _debugRouteSearch(
        '[Request] cacheHit=true recentFallbackUsed=$lastRouteRecentFallbackUsed '
        'scenarioKey=$clientScenarioKey routeVariantHint=$routeVariantHint '
        'fingerprintHint=$fingerprintHint forceFreshVariant=$clientForceFreshVariant '
        'trigger=$clientTrigger apiCallCount=$lastRouteApiCallCount',
      );
      debugPrint('[RouteService] 📦 Cache-Hit — kein neuer API-Call nötig');
      return cached;
    }

    // Request-ID für Monitoring
    final requestTimestamp = DateTime.now().millisecondsSinceEpoch;
    body['request_id'] = 'cruiseconnect_$requestTimestamp';
    lastRouteApiCallCount += 1;
    _debugRouteSearch(
      '[Build] clientRoutingBuildId=$clientRoutingBuildId '
      'clientRoutingBuildTime=$clientRoutingBuildTime endpoint=$requestUrl '
      'requestTimestamp=$requestTimestamp requestId=${body['request_id']}',
    );
    _debugRouteSearch(
      '[RequestBody] ${jsonEncode(_debugRequestSnapshot(body))}',
    );
    _debugRouteSearch(
      '[Request] cacheHit=false recentFallbackUsed=$lastRouteRecentFallbackUsed '
      'scenarioKey=$clientScenarioKey routeVariantHint=$routeVariantHint '
      'fingerprintHint=$fingerprintHint forceFreshVariant=$clientForceFreshVariant '
      'trigger=$clientTrigger apiCallCount=$lastRouteApiCallCount '
      'requestId=${body['request_id']}',
    );
    debugPrint('[RouteService] 🗺️ Mapbox Request #$requestTimestamp gesendet');
    final stopwatch = Stopwatch()..start();

    dynamic data;
    int? statusCode;
    RouteServiceException? lastMappedError;
    // Exponential Backoff: nur bei HTTP 429/5xx, max 2 Retries.
    // Timeout muss das Edge-Time-Budget (16-22 s) plus Serialisierungs-Reserve
    // abdecken, sonst killt der Client bei tough cases (Dornbirn-Tal etc.)
    // die Generierung mitten im Lauf. Edge-Floor: 16 s, Worst Case: 22 s.
    const maxRetries = 2;
    final retryRng = math.Random();
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final rawResponse = await _invoker
            .invoke(body)
            .timeout(const Duration(seconds: 26));
        if (rawResponse is FunctionResponse) {
          statusCode = rawResponse.status;
          data = rawResponse.data;
        } else {
          statusCode = null;
          data = rawResponse;
        }

        debugPrint(
          '[RouteService] Response received: status=${statusCode ?? 200}, type=${data?.runtimeType}',
        );
        break;
      } catch (e, stack) {
        final mapped = _mapInvokeException(
          error: e,
          stack: stack,
          statusCode: e is FunctionException ? e.status : statusCode,
          routeType: routeType,
        );
        lastMappedError = mapped;
        debugPrint(
          '[RouteService] Edge Function Fehler (Versuch $attempt/$maxRetries): ${mapped.debugMessage}',
        );
        if (!_isRetryable(mapped) || attempt == maxRetries) {
          throw mapped;
        }
        // Shorter Backoff + Jitter. Die strukturierten Fallbacks sitzen
        // darüber und übernehmen den langen Tail, daher lieber zügig
        // zum nächsten Versuch wechseln.
        final baseDelayMs = math.pow(2, attempt - 1).toInt() * 400;
        final jitterMs = retryRng.nextInt(220);
        final delay = Duration(milliseconds: baseDelayMs + jitterMs);
        debugPrint(
          '[RouteService] Warte ${delay.inMilliseconds}ms vor Retry...',
        );
        await Future.delayed(delay);
      }
    }

    if (lastMappedError != null && data == null) {
      throw lastMappedError;
    }

    if (data == null) {
      throw RouteServiceException(
        type: RouteErrorType.emptyResponse,
        userMessage:
            'Der Routing-Dienst hat keine Daten geliefert. Bitte versuche es erneut.',
        debugMessage: 'Empty response body from routing function.',
        statusCode: statusCode,
      );
    }

    // Wenn data ein String ist (JSON), parsen — im Isolate für große Antworten
    if (data is String) {
      try {
        data = data.length > 5000
            ? await compute<String, Map<String, dynamic>>(
                _jsonDecodeIsolate,
                data,
              )
            : json.decode(data);
      } catch (e, stack) {
        debugPrint(
          '[RouteService] JSON parsing failed: error=$e, raw=${data.toString().substring(0, math.min(600, data.length))}',
        );
        throw RouteServiceException(
          type: RouteErrorType.parsing,
          userMessage:
              'Die Antwort des Routing-Dienstes konnte nicht verarbeitet werden.',
          debugMessage: 'Invalid JSON response: $e',
          statusCode: statusCode,
          stackTrace: stack,
        );
      }
    }

    if (data is! Map) {
      throw RouteServiceException(
        type: RouteErrorType.parsing,
        userMessage:
            'Der Routing-Dienst hat ein ungültiges Antwortformat gesendet.',
        debugMessage: 'Unexpected response type: ${data.runtimeType}',
        statusCode: statusCode,
      );
    }

    if (data['error'] != null) {
      final errorMessage = data['error'].toString();
      if (data['meta'] is Map) {
        final edgeMeta = Map<String, dynamic>.from(data['meta'] as Map);
        _debugRouteSearch(
          '[EdgeMeta] scenarioKey=$clientScenarioKey '
          'routing_build_id=${edgeMeta['routing_build_id']} '
          'avoid_highways_requested=${edgeMeta['avoid_highways_requested']} '
          'effective_excludes=${edgeMeta['effective_excludes']} '
          'requestId=${body['request_id']} error=${data['code']}',
        );
      }
      throw _mapServiceError(
        errorMessage: errorMessage,
        statusCode: statusCode,
        details: data,
        routeType: routeType,
      );
    }

    if (data['route'] == null) {
      final userMessage = routeType == 'ROUND_TRIP'
          ? 'Kein passender Rundkurs gefunden. Bitte ändere Stil, Länge oder Standort.'
          : 'Keine passende Route gefunden. Bitte ändere Stil, Umweg oder Start/Ziel.';
      throw RouteServiceException(
        type: RouteErrorType.noRoute,
        userMessage: userMessage,
        debugMessage: 'Response has no "route" field.',
        statusCode: statusCode,
      );
    }

    final route = data['route'] as Map;
    if (route['geometry'] == null) {
      throw RouteServiceException(
        type: RouteErrorType.parsing,
        userMessage: 'Die Route ist unvollständig (keine Geometriedaten).',
        debugMessage: 'Route payload has no geometry.',
        statusCode: statusCode,
      );
    }

    final geometry = Map<String, dynamic>.from(route['geometry'] as Map);
    final coordinates = extractCoordinates(geometry);

    if (coordinates.length < 10) {
      debugPrint(
        '[RouteService] WARNUNG: Route hat nur ${coordinates.length} Koordinaten — möglicherweise keine Straßengeometrie!',
      );
      if (coordinates.length < 2) {
        throw RouteServiceException(
          type: RouteErrorType.noRoute,
          userMessage:
              'Keine nutzbare Route gefunden. Bitte versuche andere Einstellungen.',
          debugMessage:
              'Route geometry has too few points (${coordinates.length}).',
          statusCode: statusCode,
        );
      }
    }

    final maneuvers = extractManeuvers(data, coordinates);
    final speedLimits = _extractSpeedLimits(data, coordinates);

    final distanceRaw = (route['distance'] as num?)?.toDouble();
    final durationRaw = (route['duration'] as num?)?.toDouble();
    // IMMER die echte Mapbox-Distanz nutzen (in Metern → km), NICHT meta.distance_km
    // meta.distance_km war früher geclampt und zeigte falsche Werte
    final distanceKmActual = distanceRaw != null ? distanceRaw / 1000.0 : null;

    debugPrint(
      '[RouteService] Route OK: ${coordinates.length} Punkte, ${distanceKmActual?.toStringAsFixed(1)} km (Mapbox: ${distanceRaw?.toStringAsFixed(0)} m)',
    );

    final edgeMeta = data['meta'] is Map
        ? Map<String, dynamic>.from(data['meta'] as Map)
        : <String, dynamic>{};
    stopwatch.stop();
    edgeMeta['edge_request_duration_ms'] = stopwatch.elapsedMilliseconds;
    edgeMeta['request_id'] ??= body['request_id'];
    debugPrint(
      '[RouteService] ✅ Route erhalten nach ${stopwatch.elapsedMilliseconds}ms',
    );

    if (routeType == 'ROUND_TRIP') {
      debugPrint(
        '[RouteService] RoundTrip Edge-Meta: avoid_highways_requested='
        '${edgeMeta['avoid_highways_requested']}, '
        'effective_excludes=${edgeMeta['effective_excludes']}',
      );
      _debugRouteSearch(
        '[EdgeMeta] scenarioKey=$clientScenarioKey '
        'routing_build_id=${edgeMeta['routing_build_id']} '
        'avoid_highways_requested=${edgeMeta['avoid_highways_requested']} '
        'effective_excludes=${edgeMeta['effective_excludes']} '
        'requestId=${body['request_id']}',
      );
    } else if (routeType == 'POINT_TO_POINT') {
      debugPrint(
        '[RouteService] A→B Edge-Meta: avoid_highways_requested='
        '${edgeMeta['avoid_highways_requested']}, '
        'detour_level=${edgeMeta['detour_level']}, '
        'effective_excludes=${edgeMeta['effective_excludes']}',
      );
    }

    final routeResult = RouteResult(
      geoJson: json.encode(geometry),
      geometry: geometry,
      coordinates: coordinates,
      maneuvers: maneuvers,
      distanceMeters: distanceRaw,
      durationSeconds: durationRaw,
      distanceKm: distanceKmActual,
      speedLimits: speedLimits,
      edgeMeta: edgeMeta,
    );
    _sessionCache[cacheKey] = routeResult;
    return routeResult;
  }

  static String? _debugEndpointForInvoker(RouteEdgeInvoker invoker) {
    if (invoker is SupabaseRouteInvoker) return invoker.debugEndpoint;
    try {
      final endpoint = (invoker as dynamic).debugEndpoint;
      return endpoint is String && endpoint.isNotEmpty ? endpoint : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _debugRequestSnapshot(Map<String, dynamic> body) {
    final start = body['startLocation'] as Map?;
    final destination = body['destination_location'] as Map?;
    return <String, dynamic>{
      'request_id': body['request_id'],
      'client_scenario_key': body['client_scenario_key'],
      'client_force_fresh_variant': body['client_force_fresh_variant'],
      'client_trigger': body['client_trigger'],
      'route_type': body['route_type'],
      'planning_type': body['planning_type'],
      'mode': body['mode'],
      'targetDistance': body['targetDistance'],
      'avoid_highways': body['avoid_highways'],
      'startLocation': start == null
          ? null
          : <String, dynamic>{
              'latitude': _roundDebugCoord(start['latitude']),
              'longitude': _roundDebugCoord(start['longitude']),
            },
      'destination_location': destination == null
          ? null
          : <String, dynamic>{
              'latitude': _roundDebugCoord(destination['latitude']),
              'longitude': _roundDebugCoord(destination['longitude']),
            },
      'direction_hint': body['direction_hint'],
      'route_variant_hint': body['route_variant_hint'],
      'route_fingerprint_hint': body['route_fingerprint_hint'],
      'max_candidate_attempts': body['max_candidate_attempts'],
      'style_profile': body['style_profile'],
      'waypoint_shape_factor': body['waypoint_shape_factor'],
      'radius_multiplier': body['radius_multiplier'],
      'zigzag_waypoints': body['zigzag_waypoints'],
    };
  }

  static double? _roundDebugCoord(Object? value) {
    final number = value is num ? value.toDouble() : null;
    if (number == null || !number.isFinite) return null;
    return (number * 100000).roundToDouble() / 100000;
  }

  static bool _isRetryable(RouteServiceException error) {
    // Nur HTTP 429 (Rate Limit) und 5xx (Server) → exponential backoff.
    // Timeout/Netzwerk-Fehler werden NICHT retried — Caller macht Fallback.
    return error.type == RouteErrorType.rateLimit ||
        error.type == RouteErrorType.server ||
        error.type == RouteErrorType.workerLimit;
  }

  static bool _isFatalStructuredError(RouteServiceException error) {
    return error.type == RouteErrorType.auth ||
        error.type == RouteErrorType.validation ||
        error.type == RouteErrorType.parsing;
  }

  static bool _isStructuredFallbackError(RouteServiceException error) {
    if (_isFatalStructuredError(error)) return false;

    return error.type == RouteErrorType.noRoute ||
        error.type == RouteErrorType.quality ||
        error.type == RouteErrorType.emptyResponse ||
        error.type == RouteErrorType.unknown;
  }

  static bool _canUseStructuredFallback(RouteServiceException? error) {
    if (error == null) return true;
    return _isStructuredFallbackError(error);
  }

  static bool _isDifficultRoundTripScenario(
    RouteScenario scenario,
    RouteStyleConfig styleConfig,
  ) {
    final targetKm = scenario.targetDistanceKm ?? 0.0;
    return scenario.avoidHighways ||
        targetKm >= 100 ||
        (styleConfig.profileKey == 'kurvenjagd' && targetKm <= 60) ||
        styleConfig.profileKey == 'entdecker';
  }

  static int _roundTripCandidateBudget(
    RouteScenario scenario,
    RouteStyleConfig styleConfig,
  ) {
    final targetKm = scenario.targetDistanceKm ?? 0.0;
    final highCostCurve =
        styleConfig.profileKey == 'kurvenjagd' && targetKm >= 120;
    final constrained =
        scenario.avoidHighways ||
        (styleConfig.profileKey == 'kurvenjagd' && targetKm <= 60);

    if (highCostCurve) return 9;
    if (constrained || targetKm >= 100) return 8;
    return 7;
  }

  static int _preparedRoundTripCandidateBudget(
    RouteScenario scenario,
    RouteStyleConfig styleConfig,
  ) {
    final liveBudget = _roundTripCandidateBudget(scenario, styleConfig);
    return (liveBudget - 3).clamp(3, 5).toInt();
  }

  static int _roundTripFallbackCandidateBudget(
    RouteScenario scenario,
    RouteStyleConfig styleConfig,
  ) {
    final liveBudget = _roundTripCandidateBudget(scenario, styleConfig);
    return (liveBudget - 2).clamp(4, 6).toInt();
  }

  static int _rescueRoundTripWaypointLimit(RouteScenario scenario) {
    final targetKm = scenario.targetDistanceKm ?? 0.0;
    if (scenario.avoidHighways || targetKm >= 90) return 4;
    return 3;
  }

  static int _pointToPointFallbackWaypointLimit(
    RouteScenario scenario, {
    required bool avoidHighways,
  }) {
    if (avoidHighways && scenario.detourLevel >= 2) return 3;
    if (scenario.detourLevel >= 3) return 2;
    return 1;
  }

  /// Erzeugt einen Cache-Key aus den user-facing Request-Parametern.
  /// Position wird auf ~200m gerundet → gleicher Standort = Cache-Hit.
  /// WICHTIG: Enthält jetzt auch randomSeed und direction_hint für Diversität.
  static String _cacheKey(Map<String, dynamic> body) {
    final start = body['startLocation'] as Map?;
    final lat = (start?['latitude'] as num?)?.toDouble() ?? 0;
    final lng = (start?['longitude'] as num?)?.toDouble() ?? 0;
    final rLat = (lat * 500).round(); // ~200m Präzision
    final rLng = (lng * 500).round();
    final dest = body['destination_location'] as Map?;
    final dKey = dest != null
        ? '_${((dest['latitude'] as num).toDouble() * 500).round()}'
              '_${((dest['longitude'] as num).toDouble() * 500).round()}'
        : '';
    // Diversitäts-Parameter für unterschiedliche Routen bei gleichen Einstellungen
    final seed = body['randomSeed'] ?? 0;
    final dirHint = ((body['direction_hint'] as num?)?.toDouble() ?? 0).round();
    final offsetSide = body['offset_side'] ?? 0;
    final variantHint =
        body['route_variant_hint'] ?? body['variant_hint'] ?? '';
    final fingerprintHint =
        body['route_fingerprint_hint'] ?? body['fingerprint_hint'] ?? '';
    final avoidHighways = body['avoid_highways'] == true ? 1 : 0;
    final detourLevel = body['detour_level'] ?? 0;
    return '${body['route_type']}_${body['mode']}_${body['planning_type']}_${body['targetDistance']}_${rLat}_$rLng$dKey'
        '_h${avoidHighways}_v${detourLevel}_s${seed}_d${dirHint}_o$offsetSide'
        '_vh$variantHint'
        '_fh$fingerprintHint';
  }

  /// Erzeugt einen Szenario-Key OHNE Diversitäts-Parameter.
  /// Wird für Single-Flight und "gesehene Routen" verwendet.
  static String scenarioKey(Map<String, dynamic> body) {
    final start = body['startLocation'] as Map?;
    final lat = (start?['latitude'] as num?)?.toDouble() ?? 0;
    final lng = (start?['longitude'] as num?)?.toDouble() ?? 0;
    final rLat = (lat * 500).round();
    final rLng = (lng * 500).round();
    final dest = body['destination_location'] as Map?;
    final dKey = dest != null
        ? '_${((dest['latitude'] as num).toDouble() * 500).round()}'
              '_${((dest['longitude'] as num).toDouble() * 500).round()}'
        : '';
    final avoidHighways = body['avoid_highways'] == true ? 1 : 0;
    final detourLevel = body['detour_level'] ?? 0;
    return '${body['route_type']}_${body['mode']}_${body['planning_type']}_${body['targetDistance']}_${rLat}_$rLng$dKey'
        '_h$avoidHighways'
        '_d$detourLevel';
  }

  Future<double> _initialRoundTripDirectionHint({
    required math.Random rng,
    required String mode,
    int? variantIndex,
  }) async {
    if (mode == 'Entdecker') {
      return _pickExplorerDirection(rng);
    }
    if (variantIndex != null) {
      return (((variantIndex % 8) * 45.0) + (rng.nextDouble() - 0.5) * 28.0) %
          360;
    }
    return rng.nextDouble() * 360;
  }

  double _jitteredDetourFactor({
    required double base,
    required bool scenic,
    required int normalizedVariant,
    required int randomSeed,
  }) {
    if (!scenic && normalizedVariant <= 0) return base;
    final seeded = ((math.sin(randomSeed * 0.0137) + 1.0) / 2.0).clamp(
      0.0,
      1.0,
    );
    final jitterRange = normalizedVariant >= 3
        ? 0.08
        : normalizedVariant == 2
        ? 0.07
        : 0.06;
    final jitter = (seeded - 0.5) * 2 * jitterRange;
    return math.max(1.0, base * (1.0 + jitter));
  }

  int _nextScenarioVariantIndex(String scenarioKey, {int? explicitIndex}) {
    if (explicitIndex != null) {
      _scenarioVariantCounters[scenarioKey] = explicitIndex + 1;
      return explicitIndex;
    }
    final next = _scenarioVariantCounters[scenarioKey] ?? 0;
    _scenarioVariantCounters[scenarioKey] = next + 1;
    return next;
  }

  Future<RouteVariant> _nextRoundTripVariant(
    RouteScenario scenario, {
    required RouteStyleConfig styleConfig,
    int? explicitIndex,
  }) async {
    final index = _nextScenarioVariantIndex(
      scenario.scenarioKey,
      explicitIndex: explicitIndex,
    );
    final seed = _nextRandomSeed() + index * 37;
    final rng = math.Random(seed);
    final baseDirection = await _initialRoundTripDirectionHint(
      rng: rng,
      mode: scenario.style,
      variantIndex: index,
    );
    final radiusJitter = 1.0 + ((rng.nextDouble() - 0.5) * 0.24);
    final angleOffset =
        (baseDirection + index * 47.0 + (index % 5) * 23.0) % 360;
    return RouteVariant(
      index: index,
      seed: seed,
      angleOffset: angleOffset,
      radiusJitter: radiusJitter,
      offsetBearing: angleOffset,
      fingerprintHint:
          '${scenario.scenarioKey}|rt|$index|${angleOffset.round()}|${(radiusJitter * 100).round()}',
      variantHint:
          'rt-${styleConfig.profileKey}-h${scenario.avoidHighways ? 1 : 0}'
          '-k${(scenario.targetDistanceKm ?? 0).round()}-$index'
          '-${(angleOffset / 45).round()}',
      styleBias: styleConfig.profileKey,
    );
  }

  RouteVariant _nextPointToPointVariant(
    RouteScenario scenario, {
    required int normalizedVariant,
    required int diversitySeed,
    required bool shouldDiversify,
  }) {
    final index =
        _nextScenarioVariantIndex(scenario.scenarioKey) + diversitySeed;
    final seed = _nextRandomSeed() + index * 53;
    final rng = math.Random(seed);
    final offsetBearingBase = switch (normalizedVariant) {
      1 => 34.0,
      2 => 60.0,
      3 => 88.0,
      _ => 14.0,
    };
    final bearingSpread = 18.0 + normalizedVariant * 5.0;
    final offsetBearing =
        offsetBearingBase + ((rng.nextDouble() - 0.5) * bearingSpread);
    final radiusJitter = switch (normalizedVariant) {
      1 => 1.06 + rng.nextDouble() * 0.10,
      2 => 1.14 + rng.nextDouble() * 0.14,
      3 => 1.22 + rng.nextDouble() * 0.18,
      _ => 0.98 + rng.nextDouble() * 0.05,
    };
    final offsetSide = shouldDiversify ? (index.isEven ? 1 : -1) : null;
    return RouteVariant(
      index: index,
      seed: seed,
      angleOffset: offsetBearing,
      radiusJitter: radiusJitter,
      offsetSide: offsetSide,
      offsetBearing: offsetBearing,
      fingerprintHint:
          '${scenario.scenarioKey}|ab|$index|${offsetSide ?? 0}|${offsetBearing.round()}|${(radiusJitter * 100).round()}',
      variantHint:
          'ab-${scenario.detourLevel}-${offsetSide ?? 0}-${offsetBearing.round()}',
      styleBias: scenario.style,
    );
  }

  Future<_RouteCandidate> _requestRoundTripVariant({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required geo.Position startPosition,
    required RouteVariant variant,
    required int candidateBudget,
    bool forceFreshVariant = false,
    String debugTrigger = 'unknown',
    Map<String, double>? targetLocation,
  }) async {
    final adjustedTargetKm = styleConfig.clampRoundTripDistanceKm(
      variant.index == 0
          ? (scenario.targetDistanceKm ?? 50.0).round()
          : ((scenario.targetDistanceKm ?? 50.0) * variant.radiusJitter)
                .round(),
    );
    final body = _buildRoundTripRequest(
      startPosition: startPosition,
      targetDistanceKm: adjustedTargetKm,
      mode: scenario.style,
      planningType: scenario.planningType,
      styleConfig: styleConfig,
      variant: variant,
      targetLocation: targetLocation,
      directionHint: variant.angleOffset,
      candidateBudget: candidateBudget,
      avoidHighways: scenario.avoidHighways,
    );
    body['client_scenario_key'] = scenario.scenarioKey;
    body['client_force_fresh_variant'] = forceFreshVariant;
    body['client_trigger'] = debugTrigger;
    final result = await _invoke(body);
    final snapped = _snapRouteToStartPosition(result, startPosition);
    return _evaluateCandidate(
      scenario: scenario,
      styleConfig: styleConfig,
      route: snapped,
      variant: variant,
    );
  }

  Future<_RouteCandidate> _requestPointToPointVariant({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required geo.Position startPosition,
    required double destinationLat,
    required double destinationLng,
    required bool scenic,
    required int normalizedVariant,
    required bool avoidHighways,
    required double directDistanceKm,
    required double targetDistanceKm,
    required double detourFactor,
    required RouteVariant variant,
    required int candidateBudget,
  }) async {
    final jitteredTargetKm = styleConfig.clampPointToPointTargetKm(
      targetDistanceKm * variant.radiusJitter,
      directDistanceKm: directDistanceKm,
      scenic: scenic,
      detourVariant: normalizedVariant,
    );
    final jitteredDetourFactor = _jitteredDetourFactor(
      base: detourFactor,
      scenic: scenic,
      normalizedVariant: normalizedVariant,
      randomSeed: variant.seed,
    );
    final body = _buildPointToPointRequest(
      startPosition: startPosition,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      mode: scenario.style,
      scenic: scenic,
      normalizedVariant: normalizedVariant,
      avoidHighways: avoidHighways,
      styleConfig: styleConfig,
      targetDistanceKm: jitteredTargetKm,
      detourFactor: jitteredDetourFactor,
      variant: variant,
      offsetSide: variant.offsetSide,
      candidateBudget: candidateBudget,
    );
    final result = await _invoke(body);
    final snapped = _snapRouteToStartPosition(result, startPosition);
    return _evaluateCandidate(
      scenario: scenario,
      styleConfig: styleConfig,
      route: snapped,
      variant: variant,
      directDistanceKm: directDistanceKm,
    );
  }

  _RouteCandidate _evaluateCandidate({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required RouteResult route,
    required RouteVariant variant,
    double? directDistanceKm,
    bool relaxedRoundTrip = false,
  }) {
    final actualDistanceKm = route.distanceKm ?? 0.0;
    final qualityTargetDistanceKm =
        scenario.isPointToPoint && scenario.detourLevel <= 0
        ? 0.0
        : scenario.targetDistanceKm ?? 0.0;
    final sampledCoordinates = _sampleRouteForSimilarity(route.coordinates);
    final fingerprint = RouteQualityValidator.buildRouteFingerprint(
      sampledCoordinates,
      distanceKm: route.distanceKm,
      precision: 4,
    );
    final quality = _qualityValidator.validateQuality(
      coordinates: route.coordinates,
      isRoundTrip: scenario.isRoundTrip,
      targetDistanceKm: qualityTargetDistanceKm,
      actualDistanceKm: actualDistanceKm,
    );
    final deadEndSpikes = RouteQualityValidator.detectDeadEndSpikes(
      route.coordinates,
    );
    final deadEndSpikeDetected = deadEndSpikes.isNotEmpty;
    if (deadEndSpikeDetected) {
      lastRouteDeadEndSpikeDetected = true;
    }
    final styleFitScore = styleConfig.scoreStyleFit(
      coordinates: route.coordinates,
      distanceKm: actualDistanceKm,
      durationSeconds: route.durationSeconds,
    );
    final styleMetrics = styleConfig.calculateStyleMetrics(
      coordinates: route.coordinates,
      distanceKm: actualDistanceKm,
      durationSeconds: route.durationSeconds,
    );
    final styleFitReasons = styleConfig.styleFitReasons(styleMetrics);
    final classification = _qualityValidator.classifyGeneratedRoute(
      quality: quality,
      isRoundTrip: scenario.isRoundTrip,
      coordinateCount: route.coordinates.length,
      actualDistanceKm: actualDistanceKm,
      targetDistanceKm: qualityTargetDistanceKm,
      styleProfileKey: styleConfig.profileKey,
      styleFitScore: styleFitScore,
    );
    final edgeTier = _edgeQualityTierFor(route);
    final styleOk = styleConfig.validateStyleQuality(
      coordinates: route.coordinates,
      distanceKm: actualDistanceKm,
      durationSeconds: route.durationSeconds,
    );
    final similarityThreshold = _similarityThresholdForScenario(scenario);
    final similarityProximityMeters = _similarityProximityMetersForScenario(
      scenario,
    );
    final recentSimilarityThreshold = _lastShownSimilarityThresholdForScenario(
      scenario,
    );
    final recentSimilarityProximityMeters =
        _lastShownSimilarityProximityMetersForScenario(scenario);
    final recentRoute = scenario.isRoundTrip
        ? (_recentDisplayedRoutes[_recentDisplayedKeyForScenario(scenario)] ??
              _recentSuccessfulRoutes[scenario.scenarioKey])
        : null;
    final recentRouteSamples = recentRoute == null
        ? null
        : _sampleRouteForSimilarity(recentRoute.coordinates);
    final recentRouteTooSimilar =
        recentRouteSamples != null &&
        RouteQualityValidator.isRouteTooSimilarToPrevious(
          sampledCoordinates,
          [recentRouteSamples],
          thresholdPercent: recentSimilarityThreshold,
          proximityMeters: recentSimilarityProximityMeters,
        );
    final tooSimilar =
        SeenRouteRegistry.hasExactFingerprintInAny(
          _seenHistoryKeysForScenario(scenario),
          fingerprint,
        ) ||
        SeenRouteRegistry.hasSimilarRouteInAny(
          _seenHistoryKeysForScenario(scenario),
          sampledCoordinates,
          thresholdPercent: similarityThreshold,
          proximityMeters: similarityProximityMeters,
        ) ||
        recentRouteTooSimilar;
    final noveltyRequired = scenario.isRoundTrip || scenario.detourLevel > 0;
    final novelEnough = !noveltyRequired || !tooSimilar;
    final minPoints = _minimumPointsForScenario(
      scenario,
      actualDistanceKm: actualDistanceKm,
    );
    final hasEnoughPoints = route.coordinates.length >= minPoints;
    final pointToPointMinDistance =
        !scenario.isPointToPoint || scenario.detourLevel <= 0
        ? 0.0
        : styleConfig.minimumPointToPointDistanceKm(
            directDistanceKm: directDistanceKm ?? 0.0,
            scenic: true,
            detourVariant: scenario.detourLevel,
          );
    final pointToPointMaxDistance =
        !scenario.isPointToPoint || scenario.detourLevel <= 0
        ? double.infinity
        : styleConfig.maximumPointToPointDistanceKm(
            targetKm: scenario.targetDistanceKm ?? actualDistanceKm,
            directDistanceKm: directDistanceKm ?? 0.0,
            scenic: true,
            detourVariant: scenario.detourLevel,
          );
    final detourDistanceOk =
        !scenario.isPointToPoint || scenario.detourLevel <= 0
        ? true
        : actualDistanceKm >= pointToPointMinDistance &&
              actualDistanceKm <= pointToPointMaxDistance;
    final detourRenderableOk = _pointToPointDetourRenderable(
      scenario: scenario,
      styleConfig: styleConfig,
      actualDistanceKm: actualDistanceKm,
      directDistanceKm: directDistanceKm ?? 0.0,
      minDistanceKm: pointToPointMinDistance,
      maxDistanceKm: pointToPointMaxDistance,
    );
    final successFirstDistanceOk = scenario.isRoundTrip
        ? (() {
            final targetKm = scenario.targetDistanceKm ?? actualDistanceKm;
            if (targetKm <= 0) return true;
            final minFactor = scenario.avoidHighways
                ? (targetKm <= 55
                      ? 0.66
                      : targetKm <= 85
                      ? 0.67
                      : targetKm <= 115
                      ? 0.68
                      : 0.69)
                : (targetKm <= 55
                      ? 0.70
                      : targetKm <= 85
                      ? 0.71
                      : targetKm <= 115
                      ? 0.72
                      : 0.73);
            final maxFactor = scenario.avoidHighways
                ? (targetKm <= 55
                      ? 1.48
                      : targetKm <= 85
                      ? 1.46
                      : targetKm <= 115
                      ? 1.44
                      : 1.42)
                : (targetKm <= 55
                      ? 1.44
                      : targetKm <= 85
                      ? 1.42
                      : targetKm <= 115
                      ? 1.40
                      : 1.38);
            return actualDistanceKm >= targetKm * minFactor &&
                actualDistanceKm <= targetKm * maxFactor;
          })()
        : (() {
            final directKm = directDistanceKm ?? 0.0;
            if (directKm <= 0) return true;
            if (scenario.detourLevel > 0) {
              final maxKm = math.max(
                pointToPointMaxDistance * 1.08,
                directKm * 1.45,
              );
              return actualDistanceKm >= directKm * 0.96 &&
                  actualDistanceKm <= maxKm;
            }
            return actualDistanceKm >= directKm * 0.92 &&
                actualDistanceKm <= math.max(directKm * 1.35, directKm + 6.0);
          })();
    final renderableDistanceOk =
        scenario.isPointToPoint && scenario.detourLevel > 0
        ? detourRenderableOk
        : successFirstDistanceOk;
    final scenicFallbackRenderable =
        scenario.isPointToPoint &&
        scenario.detourLevel > 0 &&
        detourRenderableOk &&
        (directDistanceKm ?? 0.0) > 0.0 &&
        actualDistanceKm >= (directDistanceKm ?? 0.0) * 1.08 &&
        actualDistanceKm <= pointToPointMaxDistance * 1.03 &&
        quality.uturnPositions.isEmpty &&
        quality.overlapPercent <= 12.0 &&
        quality.shapePenalty <= 20.0 &&
        route.coordinates.length >= 24;
    final roundTripStructureOk =
        !scenario.isRoundTrip ||
        _roundTripStructureRenderable(
          quality: quality,
          profileKey: styleConfig.profileKey,
        );
    final rescueRoundTripAcceptable =
        relaxedRoundTrip &&
        scenario.isRoundTrip &&
        successFirstDistanceOk &&
        quality.uturnPositions.length <=
            (styleConfig.profileKey == 'sport' ? 2 : 0) &&
        quality.returnPathPercent <=
            RouteQualityValidator.maxReturnPathPercent + 8.0 &&
        _roundTripStructureRenderable(
          quality: quality,
          profileKey: styleConfig.profileKey,
          relaxed: true,
        );
    final serverApprovedGoodTier =
        edgeTier == RouteQualityTier.ideal || edgeTier == RouteQualityTier.good;
    final serverApprovedRoundTripUturnLimit = !scenario.isRoundTrip
        ? 0
        : styleConfig.profileKey == 'kurvenjagd'
        ? 2
        : serverApprovedGoodTier
        ? 2
        : 0;
    final serverApprovedRepeatedStartLimit = !scenario.isRoundTrip
        ? 72.0
        : styleConfig.profileKey == 'sport' && serverApprovedGoodTier
        ? 58.0
        : 44.0;
    // Kraken-Schutz: spurArmPercent-Obergrenzen für serverApproved-Pfad
    // deutlich gesenkt (war 70/40), damit offene Stern-Formen nicht mehr
    // via Edge-Approval durchrutschen.
    final serverApprovedSpurLimit =
        scenario.isRoundTrip &&
            styleConfig.profileKey == 'sport' &&
            serverApprovedGoodTier &&
            quality.spurArmCount <= 1 &&
            quality.centerRecrossPercent <= 16.0 &&
            quality.foldedAreaPenalty <= 64.0 &&
            quality.repeatedStartAreaPercent <= 44.0
        ? 38.0
        : (scenario.isRoundTrip &&
              styleConfig.profileKey == 'sport' &&
              serverApprovedGoodTier &&
              quality.overlapPercent <= 22.0 &&
              quality.repeatedStartAreaPercent <= 15.0)
        ? 52.0
        : (scenario.isRoundTrip ? 32.0 : 55.0);
    final serverApprovedAcceptable =
        edgeTier != null &&
        edgeTier != RouteQualityTier.rejected &&
        !deadEndSpikeDetected &&
        hasEnoughPoints &&
        renderableDistanceOk &&
        (scenario.isRoundTrip
            ? quality.uturnPositions.length <= serverApprovedRoundTripUturnLimit
            : quality.uturnPositions.isEmpty) &&
        (!scenario.isRoundTrip || roundTripStructureOk) &&
        quality.overlapPercent <= (scenario.isRoundTrip ? 24.0 : 26.0) &&
        quality.shapePenalty <= (scenario.isRoundTrip ? 60.0 : 58.0) &&
        quality.foldedAreaPenalty <=
            (scenario.isRoundTrip
                ? (styleConfig.profileKey == 'sport' ? 84.0 : 72.0)
                : 94.0) &&
        quality.spurArmPercent <= serverApprovedSpurLimit &&
        quality.repeatedStartAreaPercent <=
            (scenario.isRoundTrip
                ? (styleConfig.profileKey == 'sport' ? 42.0 : 34.0)
                : serverApprovedRepeatedStartLimit) &&
        quality.microZigzagPercent <= (scenario.isRoundTrip ? 62.0 : 66.0) &&
        (!scenario.isRoundTrip || quality.centerRecrossPercent <= 28.0) &&
        (!scenario.isRoundTrip || quality.centerReentryCount <= 1);
    final sportRescueLoopShape =
        _roundTripStructureRenderable(
          quality: quality,
          profileKey: styleConfig.profileKey,
          relaxed: true,
        ) ||
        (quality.isLoopClosed &&
            quality.overlapPercent <= 14.0 &&
            quality.shapePenalty <= 48.0 &&
            quality.foldedAreaPenalty <= 58.0 &&
            quality.spurArmCount <= 1 &&
            quality.spurArmPercent <= 34.0 &&
            quality.repeatedStartAreaPercent <= 44.0 &&
            quality.centerRecrossPercent <= 18.0 &&
            quality.centerReentryCount <= 1 &&
            quality.microZigzagPercent <= 32.0 &&
            quality.middleCoverageRatio >= 0.28 &&
            quality.dominantLoopScore >= 70.0);
    final serverApprovedSportRescue =
        scenario.isRoundTrip &&
        styleConfig.profileKey == 'sport' &&
        edgeTier == RouteQualityTier.acceptable &&
        !deadEndSpikeDetected &&
        hasEnoughPoints &&
        successFirstDistanceOk &&
        quality.uturnPositions.length <= 1 &&
        sportRescueLoopShape;
    final qualityAcceptable = scenario.isRoundTrip
        ? classification.isAcceptable ||
              rescueRoundTripAcceptable ||
              serverApprovedAcceptable ||
              serverApprovedSportRescue
        : detourRenderableOk &&
              (quality.passed ||
                  classification.isAcceptable ||
                  scenicFallbackRenderable ||
                  serverApprovedAcceptable);
    final softRenderable =
        hasEnoughPoints && qualityAcceptable && !deadEndSpikeDetected;
    final styleSoftOk =
        styleOk ||
        (scenario.isRoundTrip &&
            roundTripStructureOk &&
            styleFitScore >= styleConfig.minStyleFitScore - 8.0 &&
            quality.shapePenalty <= 60.0 &&
            quality.foldedAreaPenalty <= 80.0 &&
            quality.repeatedStartAreaPercent <= 34.0 &&
            quality.spurArmPercent <= 26.0 &&
            quality.microZigzagPercent <= 42.0) ||
        (relaxedRoundTrip &&
            scenario.isRoundTrip &&
            styleFitScore >= styleConfig.minStyleFitScore - 16.0 &&
            quality.shapePenalty <= 66.0 &&
            quality.foldedAreaPenalty <= 88.0 &&
            quality.repeatedStartAreaPercent <= 40.0 &&
            quality.spurArmPercent <= 32.0 &&
            quality.microZigzagPercent <= 48.0);
    final hasSoftDetourPenalty =
        scenario.isPointToPoint &&
        scenario.detourLevel > 0 &&
        !detourDistanceOk &&
        detourRenderableOk;
    final hasSoftStylePenalty = !styleSoftOk;
    final hasSoftSimilarityPenalty = tooSimilar;
    final baseTier = _preferredTier(classification.tier, edgeTier);
    final effectiveTier = !softRenderable
        ? RouteQualityTier.rejected
        : (hasSoftDetourPenalty ||
              hasSoftStylePenalty ||
              hasSoftSimilarityPenalty)
        ? RouteQualityTier.acceptable
        : baseTier;
    final accepted = softRenderable;
    final score =
        classification.score +
        (effectiveTier == RouteQualityTier.acceptable &&
                classification.tier != RouteQualityTier.acceptable
            ? 12.0
            : 0.0) +
        (styleOk ? 0.0 : 18.0) +
        (styleSoftOk ? 0.0 : 30.0) +
        (deadEndSpikeDetected ? 90.0 : 0.0) +
        (tooSimilar ? 45.0 : 0.0) +
        (detourDistanceOk ? 0.0 : 135.0) +
        (hasEnoughPoints ? 0.0 : 24.0) -
        styleFitScore * 0.18;

    debugPrint(
      '[RouteService] Candidate ${scenario.routeType} ${variant.variantHint}: '
      'accepted=$accepted, score=${score.toStringAsFixed(1)}, '
      'distance=${actualDistanceKm.toStringAsFixed(1)}km, '
      'overlap=${quality.overlapPercent.toStringAsFixed(1)}%, '
      'shape=${quality.shapePenalty.toStringAsFixed(1)}, '
      'tier=${classification.tier.name}, '
      'styleFit=${styleFitScore.toStringAsFixed(1)}, '
      'curveDensity=${styleMetrics.curveDensityPer50Km.toStringAsFixed(1)}/50km, '
      'smooth=${styleMetrics.smoothnessScore.toStringAsFixed(1)}, '
      'zigzag=${styleMetrics.microZigzagPercent.toStringAsFixed(1)}, '
      'sharp=${styleMetrics.sharpCurveDensityPer50Km.toStringAsFixed(1)}/50km, '
      'styleReasons=${styleFitReasons.join('|')}, '
      'styleOk=$styleOk/$styleSoftOk, '
      'uturns=${quality.uturnPositions.length}, '
      'deadEndSpikes=${deadEndSpikes.length}, '
      'tooSimilar=$tooSimilar, novelEnough=$novelEnough, '
      'edgeTier=${edgeTier?.name ?? 'none'}, '
      'detourOk=$detourDistanceOk, '
      'distanceWindow=${pointToPointMinDistance.toStringAsFixed(1)}-${pointToPointMaxDistance.isFinite ? pointToPointMaxDistance.toStringAsFixed(1) : 'inf'}',
    );

    return _RouteCandidate(
      route: route,
      variant: variant,
      fingerprint: fingerprint,
      sampledCoordinates: sampledCoordinates,
      score: score,
      accepted: accepted,
      hardRejected: !softRenderable,
      tier: effectiveTier,
      isIdeal: effectiveTier == RouteQualityTier.ideal,
      isGood:
          effectiveTier == RouteQualityTier.ideal ||
          effectiveTier == RouteQualityTier.good,
      styleFitScore: styleFitScore,
      tooSimilar: tooSimilar,
      novelEnough: novelEnough,
    );
  }

  int _minimumPointsForScenario(
    RouteScenario scenario, {
    required double actualDistanceKm,
  }) {
    if (scenario.isRoundTrip) {
      final target = scenario.targetDistanceKm ?? actualDistanceKm;
      if (target >= 120) return 28;
      if (target >= 75) return 24;
      if (target >= 35) return 20;
      return actualDistanceKm >= 15 ? 18 : 14;
    }
    if (scenario.detourLevel <= 0) {
      if (actualDistanceKm >= 20) return 18;
      if (actualDistanceKm >= 10) return 12;
      return 8;
    }
    return actualDistanceKm >= 10 ? 30 : 0;
  }

  bool _roundTripStructureRenderable({
    required RouteQualityResult quality,
    required String profileKey,
    bool relaxed = false,
  }) {
    final isSport = profileKey == 'sport';
    final overlapLimit = relaxed
        ? (isSport ? 32.0 : 28.0)
        : (isSport ? 28.0 : 24.0);
    final shapeLimit = relaxed
        ? (isSport ? 64.0 : 56.0)
        : (isSport ? 58.0 : 50.0);
    final foldedLimit = relaxed
        ? (isSport ? 88.0 : 78.0)
        : (isSport ? 82.0 : 72.0);
    final spurLimit = relaxed
        ? (isSport ? 32.0 : 28.0)
        : (isSport ? 28.0 : 24.0);
    final repeatedStartLimit = relaxed
        ? (isSport ? 46.0 : 36.0)
        : (isSport ? 40.0 : 32.0);
    final centerRecrossLimit = relaxed
        ? (isSport ? 36.0 : 30.0)
        : (isSport ? 32.0 : 26.0);
    final microZigzagLimit = relaxed
        ? (isSport ? 44.0 : 36.0)
        : (isSport ? 40.0 : 32.0);
    final middleCoverageLimit = relaxed
        ? (isSport ? 0.26 : 0.30)
        : (isSport ? 0.28 : 0.32);
    final tolerableHighSpanLoop =
        quality.spurArmPercent <= (relaxed ? 66.0 : 62.0) &&
        quality.centerRecrossPercent <= (relaxed ? 18.0 : 16.0) &&
        quality.repeatedStartAreaPercent <= (relaxed ? 14.0 : 12.0) &&
        quality.foldedAreaPenalty <= (relaxed ? 24.0 : 18.0) &&
        quality.middleCoverageRatio >= (relaxed ? 0.58 : 0.62) &&
        quality.dominantLoopScore >= (relaxed ? 80.0 : 84.0);
    final presentableFoldedLoop =
        quality.spurArmCount <= 1 &&
        quality.spurArmPercent <= (relaxed ? 40.0 : 36.0) &&
        quality.overlapPercent <= (relaxed ? 26.0 : 22.0) &&
        quality.shapePenalty <= (relaxed ? 62.0 : 58.0) &&
        quality.foldedAreaPenalty <= (relaxed ? 92.0 : 88.0) &&
        quality.repeatedStartAreaPercent <= (relaxed ? 16.0 : 12.0) &&
        quality.centerRecrossPercent <= (relaxed ? 18.0 : 14.0) &&
        quality.centerReentryCount <= 1 &&
        quality.microZigzagPercent <= (relaxed ? 36.0 : 30.0) &&
        quality.middleCoverageRatio >= (relaxed ? 0.18 : 0.20) &&
        quality.dominantLoopScore >= (relaxed ? 54.0 : 58.0);
    return quality.isLoopClosed &&
        quality.overlapPercent <= overlapLimit &&
        quality.shapePenalty <= shapeLimit &&
        ((quality.foldedAreaPenalty <= foldedLimit &&
                (quality.spurArmPercent <= spurLimit ||
                    tolerableHighSpanLoop) &&
                quality.repeatedStartAreaPercent <= repeatedStartLimit &&
                quality.centerRecrossPercent <= centerRecrossLimit &&
                quality.centerReentryCount <= 1 &&
                quality.microZigzagPercent <= microZigzagLimit &&
                quality.middleCoverageRatio >= middleCoverageLimit) ||
            presentableFoldedLoop);
  }

  bool _pointToPointDetourRenderable({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required double actualDistanceKm,
    required double directDistanceKm,
    required double minDistanceKm,
    required double maxDistanceKm,
  }) {
    if (!scenario.isPointToPoint || scenario.detourLevel <= 0) return true;
    if (actualDistanceKm >= minDistanceKm &&
        actualDistanceKm <= maxDistanceKm) {
      return true;
    }
    final rescueSlackKm = switch (scenario.detourLevel) {
      1 => 1.0,
      2 => 1.6,
      3 => 2.6,
      _ => 0.0,
    };
    final rescueMinFactor = switch (scenario.detourLevel) {
      1 => 1.10,
      2 => 1.28,
      3 => 1.55,
      _ => 1.0,
    };
    final rescueMinKm = math.max(
      directDistanceKm * rescueMinFactor,
      minDistanceKm - rescueSlackKm,
    );
    final rescueMaxKm = math.max(
      maxDistanceKm,
      styleConfig.maximumPointToPointDistanceKm(
            targetKm: scenario.targetDistanceKm ?? actualDistanceKm,
            directDistanceKm: directDistanceKm,
            scenic: true,
            detourVariant: scenario.detourLevel,
          ) *
          1.04,
    );
    return actualDistanceKm >= rescueMinKm && actualDistanceKm <= rescueMaxKm;
  }

  bool _isBetterCandidate(_RouteCandidate candidate, _RouteCandidate? current) {
    if (!candidate.accepted) return false;
    if (current == null || !current.accepted) return true;

    if (candidate.novelEnough != current.novelEnough) {
      return candidate.novelEnough;
    }

    final candidateRank = _tierRank(candidate.tier);
    final currentRank = _tierRank(current.tier);
    if (candidateRank != currentRank) {
      return candidateRank < currentRank;
    }

    if ((candidate.score - current.score).abs() > 0.01) {
      return candidate.score < current.score;
    }

    return (candidate.route.distanceKm ?? 0.0) >
        (current.route.distanceKm ?? 0.0);
  }

  int _tierRank(RouteQualityTier tier) {
    return switch (tier) {
      RouteQualityTier.ideal => 0,
      RouteQualityTier.good => 1,
      RouteQualityTier.acceptable => 2,
      RouteQualityTier.rejected => 3,
    };
  }

  RouteQualityTier _preferredTier(
    RouteQualityTier localTier,
    RouteQualityTier? edgeTier,
  ) {
    if (edgeTier == null) return localTier;
    return _tierRank(edgeTier) < _tierRank(localTier) ? edgeTier : localTier;
  }

  RouteQualityTier? _edgeQualityTierFor(RouteResult route) {
    final rawTier = route.edgeMeta['quality_tier']?.toString().trim();
    return switch (rawTier) {
      'ideal' => RouteQualityTier.ideal,
      'good' => RouteQualityTier.good,
      'acceptable' => RouteQualityTier.acceptable,
      'rejected' => RouteQualityTier.rejected,
      _ => null,
    };
  }

  double _similarityThresholdForScenario(RouteScenario scenario) {
    if (scenario.isRoundTrip) {
      // Deutlich strenger als vorher (72 %). Kurvenjagd besonders scharf,
      // weil enge Tal-Loops mit gleichen Seeds sonst schnell wieder fast
      // identische Routen ergeben. Der Duplikat-Schutz triggert bereits ab
      // dieser Schwelle das Verwerfen und forciert einen neuen Seed/Winkel.
      final style = scenario.style.toLowerCase();
      if (style.contains('kurvenjagd') || style.contains('kurvenreich')) {
        return 56.0;
      }
      return 61.0;
    }
    if (scenario.detourLevel <= 0) {
      return scenario.avoidHighways ? 92.0 : 96.0;
    }
    // A→B-Umwege: strenger als zuvor — parallele „Fast-Duplikate“ zwischen
    // Klein/Mittel/Groß sollen eher verworfen und neu gesucht werden.
    if (scenario.detourLevel == 1) return 70.0;
    if (scenario.detourLevel == 2) return 68.0;
    return 66.0;
  }

  double _lastShownSimilarityThresholdForScenario(RouteScenario scenario) {
    if (!scenario.isRoundTrip) {
      return _similarityThresholdForScenario(scenario);
    }
    final style = scenario.style.toLowerCase();
    if (style.contains('kurvenjagd') || style.contains('kurvenreich')) {
      return 52.0;
    }
    return 56.0;
  }

  double _similarityProximityMetersForScenario(RouteScenario scenario) {
    if (scenario.isRoundTrip) {
      // Weitere Proximity → zwei Routen gelten schon dann als „in Deckung“,
      // wenn sie geometrisch grob übereinander liegen, auch wenn sie auf
      // parallelen Straßen verlaufen. Dadurch werden Fast-Duplikate
      // zuverlässiger erkannt.
      return 170.0;
    }
    if (!scenario.isRoundTrip && scenario.detourLevel > 0) {
      return 135.0;
    }
    return 160.0;
  }

  double _lastShownSimilarityProximityMetersForScenario(
    RouteScenario scenario,
  ) {
    if (!scenario.isRoundTrip) {
      return _similarityProximityMetersForScenario(scenario);
    }
    return 200.0;
  }

  bool _isNovelRouteForScenario(RouteScenario scenario, RouteResult route) {
    if (!scenario.isRoundTrip && scenario.detourLevel <= 0) return true;

    final sampledCoordinates = _sampleRouteForSimilarity(route.coordinates);
    final fingerprint = RouteQualityValidator.buildRouteFingerprint(
      sampledCoordinates,
      distanceKm: route.distanceKm,
      precision: 4,
    );
    final similarityThreshold = _similarityThresholdForScenario(scenario);
    final similarityProximityMeters = _similarityProximityMetersForScenario(
      scenario,
    );
    final recentRoute =
        _recentDisplayedRoutes[_recentDisplayedKeyForScenario(scenario)] ??
        _recentSuccessfulRoutes[scenario.scenarioKey];
    if (recentRoute != null) {
      final recentSamples = _sampleRouteForSimilarity(recentRoute.coordinates);
      if (RouteQualityValidator.isRouteTooSimilarToPrevious(
            sampledCoordinates,
            [recentSamples],
            thresholdPercent: _lastShownSimilarityThresholdForScenario(
              scenario,
            ),
            proximityMeters: _lastShownSimilarityProximityMetersForScenario(
              scenario,
            ),
          ) ||
          RouteQualityValidator.buildRouteFingerprint(
                recentSamples,
                distanceKm: recentRoute.distanceKm,
                precision: 4,
              ) ==
              fingerprint) {
        return false;
      }
    }

    if (SeenRouteRegistry.entriesForAny(
      _seenHistoryKeysForScenario(scenario),
    ).isEmpty) {
      return true;
    }

    return !SeenRouteRegistry.hasExactFingerprintInAny(
          _seenHistoryKeysForScenario(scenario),
          fingerprint,
        ) &&
        !SeenRouteRegistry.hasSimilarRouteInAny(
          _seenHistoryKeysForScenario(scenario),
          sampledCoordinates,
          thresholdPercent: similarityThreshold,
          proximityMeters: similarityProximityMeters,
        );
  }

  List<List<double>> _sampleRouteForSimilarity(
    List<List<double>> coordinates, {
    int maxSamples = 80,
  }) {
    if (coordinates.length <= maxSamples) {
      return coordinates
          .where((point) => point.length >= 2)
          .map((point) => [point[0], point[1]])
          .toList();
    }
    final sampled = <List<double>>[];
    for (var i = 0; i < maxSamples; i++) {
      final ratio = maxSamples == 1 ? 0.0 : i / (maxSamples - 1);
      final index = ((coordinates.length - 1) * ratio).round();
      final point = coordinates[index];
      if (point.length < 2) continue;
      sampled.add([point[0], point[1]]);
    }
    return sampled;
  }

  RouteResult? _takePreparedRoute({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    double? directDistanceKm,
  }) {
    final entry = PreparedRouteBuffer.take(scenario.scenarioKey);
    if (entry == null) {
      _debugRouteSearch(
        '[Prepared] preparedHit=false scenarioKey=${scenario.scenarioKey}',
      );
      return null;
    }
    _debugRouteSearch(
      '[Prepared] preparedHit=true scenarioKey=${scenario.scenarioKey} '
      'routeVariantHint=${entry.variant.variantHint} '
      'fingerprintHint=${entry.variant.fingerprintHint}',
    );
    lastRoutePreparedBufferHit = true;
    final candidate = _evaluateCandidate(
      scenario: scenario,
      styleConfig: styleConfig,
      route: entry.route,
      variant: entry.variant,
      directDistanceKm: directDistanceKm,
    );
    if (!candidate.accepted || !candidate.novelEnough) {
      _debugRouteSearch(
        '[Prepared] rejected scenarioKey=${scenario.scenarioKey} '
        'accepted=${candidate.accepted} novelEnough=${candidate.novelEnough}',
      );
      return null;
    }
    lastRoutePreparedBufferUsed = true;
    lastRouteGenerationSource = 'prepared_buffer';
    _debugRouteSearch(
      '[Prepared] accepted scenarioKey=${scenario.scenarioKey}',
    );
    return _finalizeAndRemember(
      scenario: scenario,
      route: candidate.route,
      sampledCoordinates: candidate.sampledCoordinates,
      fingerprint: candidate.fingerprint,
    );
  }

  void _schedulePreparedRoundTripRoute({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required geo.Position startPosition,
  }) {
    if (disableBackgroundPreparation ||
        RouteCacheService.shouldPausePreparation) {
      return;
    }
    if (PreparedRouteBuffer.hasFreshEntry(scenario.scenarioKey)) return;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 1500), () async {
        if (RouteCacheService.shouldPausePreparation) return;
        if (!RouteGenerationCoordinator.canPrepare(scenario.scenarioKey)) {
          return;
        }
        await RouteGenerationCoordinator.prepareInBackground(
          scenario.scenarioKey,
          () async {
            if (_isInWorkerLimitCooldown() ||
                PreparedRouteBuffer.hasFreshEntry(scenario.scenarioKey)) {
              return;
            }
            try {
              final variant = await _nextRoundTripVariant(
                scenario,
                styleConfig: styleConfig,
              );
              final candidate = await _requestRoundTripVariant(
                scenario: scenario,
                styleConfig: styleConfig,
                startPosition: startPosition,
                variant: variant,
                candidateBudget: _preparedRoundTripCandidateBudget(
                  scenario,
                  styleConfig,
                ),
              );
              if (!candidate.accepted || !candidate.novelEnough) return;
              PreparedRouteBuffer.store(
                scenario.scenarioKey,
                PreparedRouteEntry(
                  route: candidate.route,
                  variant: candidate.variant,
                  preparedAt: DateTime.now(),
                ),
              );
            } catch (e) {
              debugPrint('[RouteService] Prepared round-trip skipped: $e');
            }
          },
        );
      }),
    );
  }

  void _schedulePreparedPointToPointRoute({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required geo.Position startPosition,
    required double destinationLat,
    required double destinationLng,
    required bool avoidHighways,
    required double directDistanceKm,
  }) {
    if (disableBackgroundPreparation ||
        RouteCacheService.shouldPausePreparation) {
      return;
    }
    if (PreparedRouteBuffer.hasFreshEntry(scenario.scenarioKey)) return;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 1500), () async {
        if (RouteCacheService.shouldPausePreparation) return;
        if (!RouteGenerationCoordinator.canPrepare(scenario.scenarioKey)) {
          return;
        }
        await RouteGenerationCoordinator.prepareInBackground(
          scenario.scenarioKey,
          () async {
            if (_isInWorkerLimitCooldown() ||
                PreparedRouteBuffer.hasFreshEntry(scenario.scenarioKey)) {
              return;
            }
            try {
              final variant = _nextPointToPointVariant(
                scenario,
                normalizedVariant: scenario.detourLevel,
                diversitySeed: 211,
                shouldDiversify: true,
              );
              final targetDistanceKm =
                  scenario.targetDistanceKm ?? directDistanceKm;
              final detourFactor = switch (scenario.detourLevel) {
                1 => 1.32,
                2 => 1.65,
                3 => 2.10,
                _ => 1.15,
              };
              final candidate = await _requestPointToPointVariant(
                scenario: scenario,
                styleConfig: styleConfig,
                startPosition: startPosition,
                destinationLat: destinationLat,
                destinationLng: destinationLng,
                scenic: scenario.detourLevel > 0,
                normalizedVariant: scenario.detourLevel,
                avoidHighways: avoidHighways,
                directDistanceKm: directDistanceKm,
                targetDistanceKm: targetDistanceKm,
                detourFactor: detourFactor,
                variant: variant,
                candidateBudget: scenario.detourLevel >= 2 ? 3 : 2,
              );
              if (!candidate.accepted || !candidate.novelEnough) return;
              PreparedRouteBuffer.store(
                scenario.scenarioKey,
                PreparedRouteEntry(
                  route: candidate.route,
                  variant: candidate.variant,
                  preparedAt: DateTime.now(),
                ),
              );
            } catch (e) {
              debugPrint('[RouteService] Prepared A→B skipped: $e');
            }
          },
        );
      }),
    );
  }

  RouteResult _finalizeAndRemember({
    required RouteScenario scenario,
    required RouteResult route,
    required List<List<double>> sampledCoordinates,
    required String fingerprint,
    bool fromCache = false,
  }) {
    final previousDisplayed =
        _recentDisplayedRoutes[_recentDisplayedKeyForScenario(scenario)] ??
        _recentSuccessfulRoutes[scenario.scenarioKey];
    double? similarityToPrevious;
    if (previousDisplayed != null) {
      similarityToPrevious =
          RouteQualityValidator.calculateRouteSimilarityPercent(
            sampledCoordinates,
            _sampleRouteForSimilarity(previousDisplayed.coordinates),
            proximityMeters: _lastShownSimilarityProximityMetersForScenario(
              scenario,
            ),
          );
    }
    if (fromCache && lastRouteGenerationSource == 'mapbox') {
      lastRouteGenerationSource = 'cache';
    }
    lastRouteFromCache = fromCache;
    lastRouteDebugFingerprint = fingerprint;
    lastRouteSimilarityToPreviousPercent = similarityToPrevious;
    final finalized = _finalizeRoute(route, scenarioKey: scenario.scenarioKey);
    _recentSuccessfulRoutes[scenario.scenarioKey] = finalized;
    _recentDisplayedRoutes[_recentDisplayedKeyForScenario(scenario)] =
        finalized;
    SeenRouteRegistry.rememberAll(
      _seenHistoryKeysForScenario(scenario),
      fingerprint: fingerprint,
      sampledCoordinates: sampledCoordinates,
    );
    _debugRouteSearch(
      '[Result] scenarioKey=${scenario.scenarioKey} '
      'routeFingerprint=$fingerprint '
      'similarityToLastRoute=${similarityToPrevious == null ? 'none' : '${similarityToPrevious.toStringAsFixed(1)}%'} '
      'cacheHit=$lastRouteSessionCacheHit '
      'apiCallCount=$lastRouteApiCallCount '
      'recentFallbackUsed=$lastRouteRecentFallbackUsed '
      'persistentCacheFallbackUsed=$lastRoutePersistentCacheFallbackUsed '
      'preparedBufferHit=$lastRoutePreparedBufferHit '
      'preparedBufferUsed=$lastRoutePreparedBufferUsed '
      'duplicateFallbackUsed=$lastRouteDuplicateFallbackUsed '
      'poolFallbackUsed=$lastRoutePoolFallbackUsed '
      'routeGenerationSource=$lastRouteGenerationSource '
      'poolMatchId=$lastRoutePoolMatchId '
      'poolMatchTier=$lastRoutePoolMatchTier '
      'poolStartDistanceKm=${lastRoutePoolStartDistanceKm?.toStringAsFixed(1)} '
      'emergencyFallbackUsed=$lastRouteEmergencyFallbackUsed '
      'fallbackUsed=${lastRouteRecentFallbackUsed || lastRoutePersistentCacheFallbackUsed || lastRouteDuplicateFallbackUsed || lastRoutePoolFallbackUsed} '
      'trigger=${lastRouteDebugTrigger ?? 'unknown'} '
      'fromCache=$fromCache',
    );
    return finalized;
  }

  RouteResult _finalizeAndRememberRoute({
    required RouteScenario scenario,
    required RouteResult route,
    bool fromCache = false,
  }) {
    final sampledCoordinates = _sampleRouteForSimilarity(route.coordinates);
    final fingerprint = RouteQualityValidator.buildRouteFingerprint(
      sampledCoordinates,
      distanceKm: route.distanceKm,
      precision: 4,
    );
    return _finalizeAndRemember(
      scenario: scenario,
      route: route,
      sampledCoordinates: sampledCoordinates,
      fingerprint: fingerprint,
      fromCache: fromCache,
    );
  }

  Future<RouteResult?> _tryRoutePoolFallback({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required double userLat,
    required double userLng,
    required String fallbackReason,
    double? directDistanceKm,
  }) async {
    final bucket = _distanceBucketForPool(scenario.targetDistanceKm);
    if (bucket == null) {
      _debugRouteSearch(
        '[PoolFallback] skipped=true reason=unsupported_distance '
        'targetKm=${scenario.targetDistanceKm}',
      );
      return null;
    }

    lastRoutePoolDistanceRuleApplied = scenario.isRoundTrip;
    lastRoutePoolRejectedTooFar = false;
    lastRouteAccessLegUsed = false;
    lastRouteAccessLegDistanceKm = null;

    final matches = await _routePoolService.findCandidateRoutesNear(
      userLat: userLat,
      userLng: userLng,
      distanceBucket: bucket,
      style: scenario.style,
      avoidHighways: scenario.avoidHighways,
      routeType: scenario.routeType,
    );
    if (matches.isEmpty) {
      _debugRouteSearch(
        '[PoolFallback] poolHit=false reason=pool_density_missing '
        'scenarioKey=${scenario.scenarioKey} bucket=$bucket',
      );
      return null;
    }

    for (final match in matches) {
      final actualPoolStartDistanceKm = RoutePoolService.haversineDistanceKm(
        userLat,
        userLng,
        match.route.startLat,
        match.route.startLng,
      );
      if (scenario.isRoundTrip &&
          actualPoolStartDistanceKm >
              RoutePoolService.roundTripHardStartMaxKm) {
        lastRoutePoolRejectedTooFar = true;
        _debugRouteSearch(
          '[PoolFallback] poolHit=true poolUsed=false reason=too_far '
          'poolMatchId=${match.route.id} '
          'poolStartDistanceKm=${actualPoolStartDistanceKm.toStringAsFixed(1)} '
          'poolDistanceRuleApplied=true',
        );
        continue;
      }

      final route = _routePoolEntryToRouteResult(
        match,
        scenario: scenario,
        styleConfig: styleConfig,
        fallbackReason: fallbackReason,
      );
      if (route == null) {
        _debugRouteSearch(
          '[PoolFallback] poolHit=true poolUsed=false reason=invalid_geometry '
          'poolMatchId=${match.route.id}',
        );
        continue;
      }

      lastRouteAccessLegUsed = false;
      lastRouteAccessLegDistanceKm = null;
      var candidateRoute = route;
      if (scenario.isRoundTrip && actualPoolStartDistanceKm > 0.06) {
        final rebasedRoute = await _buildRoundTripPoolAccessRoute(
          scenario: scenario,
          styleConfig: styleConfig,
          fallbackReason: fallbackReason,
          userLat: userLat,
          userLng: userLng,
          match: match,
          poolRoute: route,
        );
        if (rebasedRoute == null) {
          _debugRouteSearch(
            '[PoolFallback] poolHit=true poolUsed=false reason=access_leg_unusable '
            'poolMatchId=${match.route.id} '
            'poolStartDistanceKm=${match.startDistanceKm.toStringAsFixed(1)}',
          );
          continue;
        }
        candidateRoute = rebasedRoute;
      }

      final candidate = _evaluateCandidate(
        scenario: scenario,
        styleConfig: styleConfig,
        route: candidateRoute,
        variant: _poolRouteVariant(scenario, match),
        relaxedRoundTrip: true,
        directDistanceKm: directDistanceKm,
      );
      if (!candidate.accepted || candidate.hardRejected) {
        _debugRouteSearch(
          '[PoolFallback] poolHit=true poolUsed=false reason=quality_rejected '
          'poolMatchId=${match.route.id} tier=${candidate.tier.name}',
        );
        continue;
      }
      if (!candidate.novelEnough) {
        _debugRouteSearch(
          '[PoolFallback] poolHit=true poolUsed=false reason=too_similar '
          'poolMatchId=${match.route.id}',
        );
        continue;
      }

      lastRoutePoolFallbackUsed = true;
      lastRouteEmergencyFallbackUsed = true;
      lastRouteGenerationSource = 'pool';
      lastRoutePoolMatchId = match.route.id;
      lastRoutePoolMatchTier = match.radiusScope;
      lastRoutePoolStartDistanceKm = actualPoolStartDistanceKm;
      _debugRouteSearch(
        '[PoolFallback] poolHit=true poolUsed=true '
        'poolMatchId=${match.route.id} poolMatchTier=${match.radiusScope} '
        'poolStartDistanceKm=${actualPoolStartDistanceKm.toStringAsFixed(1)} '
        'poolCandidateCount=${matches.length} fallbackReason=$fallbackReason',
      );

      return _finalizeAndRemember(
        scenario: scenario,
        route: candidate.route,
        sampledCoordinates: candidate.sampledCoordinates,
        fingerprint: candidate.fingerprint,
      );
    }

    _debugRouteSearch(
      '[PoolFallback] poolHit=true poolUsed=false reason=no_usable_candidate '
      'scenarioKey=${scenario.scenarioKey} bucket=$bucket '
      'poolCandidateCount=${matches.length}',
    );
    return null;
  }

  Future<RoutePoolCoverageCheck?> _ensureCoverageBootstrapStatus({
    required RouteScenario scenario,
    required double userLat,
    required double userLng,
    required String subscriptionTier,
    required bool createSeedJob,
  }) async {
    final bucket = _distanceBucketForPool(scenario.targetDistanceKm);
    if (bucket == null) return null;
    try {
      final coverage = await _routePoolService.ensureCoverageForRequest(
        userLat: userLat,
        userLng: userLng,
        distanceBucket: bucket,
        style: scenario.style,
        avoidHighways: scenario.avoidHighways,
        routeType: scenario.routeType,
        subscriptionTier: subscriptionTier,
        createSeedJob: createSeedJob,
      );
      lastRouteCoverageStatus = coverage.coverageStatus;
      lastRouteSeedJobCreated = coverage.seedJobCreated;
      lastRouteDuplicateSeedJobPrevented = coverage.duplicateJobPrevented;
      lastRoutePoolBootstrapPending = coverage.bootstrapPending;
      lastRouteRegionDifficulty = coverage.regionDifficulty;
      lastRouteHardRegionStatus = coverage.hardRegionStatus;
      lastRouteChosenCluster = coverage.assignment?.region.cityCluster;
      return coverage;
    } catch (_) {
      // Coverage/bootstrap metadata must never replace the original routing
      // error when the backing Supabase store is unavailable in unit tests or
      // degraded environments.
      return null;
    }
  }

  Future<RouteServiceException> _buildCoverageWarmupException({
    required RouteScenario scenario,
    required RoutePoolCoverageCheck coverage,
    required RouteServiceException? lastError,
  }) async {
    final cluster = coverage.assignment?.region.cityCluster;
    final warmupMessage = _coverageStatusUserMessage(
      coverage: coverage,
      cluster: cluster,
    );
    final meta = <String, dynamic>{
      ...coverage.toMeta(),
      'route_source': 'pool',
      'source': 'pool',
      'fallback_reason': lastError?.type.name ?? 'region_warming_up',
    };
    return RouteServiceException(
      type: RouteErrorType.noRoute,
      userMessage: warmupMessage,
      debugMessage:
          'Pool coverage warming up for ${scenario.routeType}/${scenario.style}/${scenario.targetDistanceKm}km status=${coverage.coverageStatus}',
      edgeMeta: meta,
      statusCode: lastError?.statusCode,
      stackTrace: lastError?.stackTrace,
    );
  }

  String _coverageStatusUserMessage({
    required RoutePoolCoverageCheck coverage,
    required String? cluster,
  }) {
    final clusterText = cluster ?? 'deiner Umgebung';
    switch (coverage.coverageStatus) {
      case 'hard_region_curated_needed':
        return 'In $clusterText gibt es noch keine lokal verifizierten Routen. Diese Region braucht kuratierte Strecken. Wir sammeln passende Fahrten.';
      case 'hard_region_thin':
        return 'In $clusterText gibt es erst wenige lokal verifizierte Routen. Wir erweitern den Pool noch.';
      case 'bootstrap_limited':
        return 'In $clusterText sind die automatischen Aufbauversuche aktuell begrenzt. Bitte versuche es spaeter erneut.';
      case 'cooldown':
        return 'In $clusterText bauen wir gerade erste Routen auf. Bitte versuche es in einigen Minuten erneut.';
      case 'warming_up':
      case 'empty':
      default:
        return cluster == null
            ? 'In deiner Umgebung wurde noch keine Route berechnet. Wir erstellen gerade erste Routen. Das dauert einige Minuten.'
            : 'In deiner Umgebung wurde noch keine Route fuer $cluster berechnet. Wir erstellen gerade erste Routen. Das dauert einige Minuten.';
    }
  }

  Future<RouteServiceException?> _maybeBuildCoverageWarmupError({
    required RouteScenario scenario,
    required double userLat,
    required double userLng,
    required RouteServiceException? lastError,
    RoutePoolCoverageCheck? coverage,
  }) async {
    final normalizedTier = lastRouteSubscriptionTier;
    if (!_isFreeTier(normalizedTier) &&
        !_isBasicTier(normalizedTier) &&
        normalizedTier != 'premium') {
      return null;
    }

    coverage ??= await _ensureCoverageBootstrapStatus(
      scenario: scenario,
      userLat: userLat,
      userLng: userLng,
      subscriptionTier: normalizedTier,
      createSeedJob: true,
    );
    if (coverage == null) return null;

    if (_isFreeTier(normalizedTier)) {
      return _buildCoverageWarmupException(
        scenario: scenario,
        coverage: coverage,
        lastError: lastError,
      );
    }

    if (coverage.shouldSurfaceWarmup &&
        (lastError == null ||
            lastError.type == RouteErrorType.noRoute ||
            lastError.type == RouteErrorType.quality ||
            lastError.type == RouteErrorType.network ||
            lastError.type == RouteErrorType.server ||
            lastError.type == RouteErrorType.rateLimit ||
            lastError.type == RouteErrorType.workerLimit ||
            lastError.type == RouteErrorType.emptyResponse ||
            lastError.type == RouteErrorType.unknown)) {
      return _buildCoverageWarmupException(
        scenario: scenario,
        coverage: coverage,
        lastError: lastError,
      );
    }
    return null;
  }

  Future<void> _maybeRecordRoutePoolCandidate({
    required RouteScenario scenario,
    required RouteResult route,
    required String fingerprint,
    required RouteQualityTier tier,
    required double qualityScore,
    required String subscriptionTier,
  }) async {
    final normalizedTier = _normalizeSubscriptionTier(subscriptionTier);
    if (_isFreeTier(normalizedTier)) return;
    if (lastRouteGenerationSource != 'mapbox') return;
    final bucket = _distanceBucketForPool(scenario.targetDistanceKm);
    if (bucket == null) return;

    final source = normalizedTier == 'basic' ? 'basic_live' : 'premium_live';
    final score = switch (tier) {
      RouteQualityTier.ideal => 95.0,
      RouteQualityTier.good => 85.0,
      RouteQualityTier.acceptable => 72.0,
      RouteQualityTier.rejected => 40.0,
    };
    final routePayload = <String, dynamic>{
      ...route.edgeMeta,
      'candidate_fingerprint': fingerprint,
      'candidate_subscription_tier': normalizedTier,
    };
    final geometry = route.geometry.isNotEmpty
        ? route.geometry
        : <String, dynamic>{
            'type': 'LineString',
            'coordinates': route.coordinates,
          };
    try {
      final candidateSaveResult = await _routePoolService.recordCandidateRoute(
        userLat: scenario.startLatitude,
        userLng: scenario.startLongitude,
        distanceBucket: bucket,
        style: scenario.style,
        avoidHighways: scenario.avoidHighways,
        routeType: scenario.routeType,
        candidateSource: source,
        routeFingerprint: fingerprint,
        geometry: geometry,
        routePayload: routePayload,
        qualityScore: math.min(100.0, math.max(score, qualityScore)),
        shapeScore: (route.edgeMeta['shape_score'] as num?)?.toDouble() ?? 0.0,
        distanceKm: route.distanceKm,
        hasHighway: (route.edgeMeta['has_highway'] as bool?) ?? false,
      );
      lastRouteCandidateInserted = candidateSaveResult.saved;
      lastRouteVerifiedInserted = false;
    } catch (_) {
      // Candidate staging must never block route delivery.
    }
  }

  Future<RouteResult?> _buildRoundTripPoolAccessRoute({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required String fallbackReason,
    required double userLat,
    required double userLng,
    required RoutePoolMatch match,
    required RouteResult poolRoute,
  }) async {
    final poolRouteDeadEndSpikes = RouteQualityValidator.detectDeadEndSpikes(
      poolRoute.coordinates,
    );
    if (poolRouteDeadEndSpikes.isNotEmpty) {
      lastRouteDeadEndSpikeDetected = true;
      _debugRouteSearch(
        '[PoolFallback] poolHit=true poolUsed=false reason=dead_end_spike '
        'poolMatchId=${match.route.id} '
        'deadEndSpikeCount=${poolRouteDeadEndSpikes.length}',
      );
      return null;
    }

    final currentPosition = _positionFromCoordinate([userLng, userLat]);
    final sessionOrigin = [userLng, userLat];
    final joinPoints = _accessPlanner.suggestJoinPoints(
      currentPosition: currentPosition,
      existingRoute: poolRoute,
      maxCandidates: 3,
      rebaseClosedLoop: true,
    );
    _ScoredPoolAccessRoute? bestRoute;
    final targetDistanceKm =
        scenario.targetDistanceKm ??
        poolRoute.distanceKm ??
        ((poolRoute.distanceMeters ?? 0.0) / 1000.0);

    for (final joinPoint in joinPoints) {
      try {
        final rotatedLoop = _sliceRouteFromIndex(
          poolRoute,
          joinPoint.index,
          wrapClosedLoop: true,
        );
        if (rotatedLoop.coordinates.length < 4) continue;

        final accessLeg = joinPoint.distanceFromCurrentMeters <= 60.0
            ? null
            : await _requestAccessLegToJoin(
                currentPosition: currentPosition,
                joinPoint: joinPoint,
                mode: scenario.style,
                avoidHighways: scenario.avoidHighways,
              );
        final accessDistanceKm =
            accessLeg?.distanceKm ??
            ((accessLeg?.distanceMeters ?? 0.0) / 1000.0);
        final exitIndices = _suggestRoundTripPoolExitIndices(
          route: rotatedLoop,
          targetDistanceKm: targetDistanceKm,
          accessLegDistanceKm: accessDistanceKm,
          sessionOrigin: sessionOrigin,
          maxCandidates: 2,
        );

        for (final exitIndex in exitIndices) {
          final loopSegment = _sliceRouteRange(rotatedLoop, 0, exitIndex);
          if (loopSegment.coordinates.length < 4) continue;
          final returnLeg = await _buildReturnLegIfNeeded(
            sessionOrigin: sessionOrigin,
            followOnRoute: loopSegment,
            mode: scenario.style,
            avoidHighways: scenario.avoidHighways,
            enabled: true,
          );
          final sessionRoute = returnLeg == null
              ? loopSegment
              : _mergeRouteSegments([loopSegment, returnLeg]);
          final activeRoute = accessLeg == null
              ? sessionRoute
              : _mergeAccessAndFollowOnRoutes(
                  accessLeg: accessLeg,
                  followOnRoute: sessionRoute,
                );
          final accessLegDistanceKm =
              accessDistanceKm +
              (returnLeg?.distanceKm ??
                  ((returnLeg?.distanceMeters ?? 0.0) / 1000.0));
          final accessLegSimilarityPercent =
              accessLeg != null && returnLeg != null
              ? RouteQualityValidator.calculateRouteSimilarityPercent(
                  accessLeg.coordinates,
                  returnLeg.coordinates,
                  sampleCount: 24,
                  proximityMeters: 65.0,
                )
              : 0.0;
          final roundedAccessLegDistanceKm = accessLegDistanceKm > 0
              ? double.parse(accessLegDistanceKm.toStringAsFixed(2))
              : null;
          final activeDistanceKm =
              activeRoute.distanceKm ??
              ((activeRoute.distanceMeters ?? 0.0) / 1000.0);
          final loopSegmentDistanceKm =
              loopSegment.distanceKm ??
              ((loopSegment.distanceMeters ?? 0.0) / 1000.0);
          final accessPlanScore = _scoreRoundTripPoolAccessPlan(
            targetDistanceKm: targetDistanceKm,
            activeDistanceKm: activeDistanceKm,
            accessLegDistanceKm: accessLegDistanceKm,
            accessLegSimilarityPercent: accessLegSimilarityPercent,
            joinProgress: joinPoint.progressRatio,
            joinScore: joinPoint.score,
            loopCompletionRatio:
                loopSegmentDistanceKm <= 0 || (poolRoute.distanceKm ?? 0) <= 0
                ? 1.0
                : (loopSegmentDistanceKm /
                          (poolRoute.distanceKm ?? loopSegmentDistanceKm))
                      .clamp(0.0, 1.0),
          );
          final routedPlan = _routeWithEdgeMeta(activeRoute, {
            ...poolRoute.edgeMeta,
            'fallbackUsed': true,
            'fallback_reason': fallbackReason,
            'pool_match_id': match.route.id,
            'pool_match_tier': match.radiusScope,
            'pool_start_distance_km': match.startDistanceKm,
            'pool_allowed_radius_km': match.allowedRadiusKm,
            'pool_distance_rule_applied': true,
            'pool_rejected_too_far': false,
            'access_leg_used': accessLeg != null || returnLeg != null,
            'access_leg_distance_km': roundedAccessLegDistanceKm,
            'access_leg_similarity_percent': double.parse(
              accessLegSimilarityPercent.toStringAsFixed(1),
            ),
            'access_plan_score': double.parse(
              accessPlanScore.toStringAsFixed(2),
            ),
            'access_join_index': joinPoint.index,
            'access_join_progress_ratio': joinPoint.progressRatio,
            'access_exit_index': exitIndex,
            'pool_loop_distance_km': double.parse(
              loopSegmentDistanceKm.toStringAsFixed(2),
            ),
            'pool_loop_completion_ratio': double.parse(
              ((loopSegmentDistanceKm <= 0 || (poolRoute.distanceKm ?? 0) <= 0
                          ? 1.0
                          : (loopSegmentDistanceKm /
                                (poolRoute.distanceKm ??
                                    loopSegmentDistanceKm)))
                      .clamp(0.0, 1.0))
                  .toStringAsFixed(3),
            ),
            'route_source': 'pool',
            'source': 'pool',
          });
          if (!_isPreliminarilyUsablePoolAccessRoute(
            scenario: scenario,
            styleConfig: styleConfig,
            route: routedPlan,
          )) {
            _debugRouteSearch(
              '[PoolFallback] poolHit=true poolUsed=false reason=access_leg_preview_rejected '
              'poolMatchId=${match.route.id} joinIndex=${joinPoint.index} '
              'exitIndex=$exitIndex',
            );
            continue;
          }
          if (bestRoute == null || accessPlanScore < bestRoute.score) {
            bestRoute = _ScoredPoolAccessRoute(
              route: routedPlan,
              score: accessPlanScore,
              accessLegUsed: accessLeg != null || returnLeg != null,
              accessLegDistanceKm: roundedAccessLegDistanceKm,
            );
          }
        }
      } catch (error) {
        _debugRouteSearch(
          '[PoolFallback] poolHit=true poolUsed=false reason=access_leg_error '
          'poolMatchId=${match.route.id} joinIndex=${joinPoint.index} '
          'message=$error',
        );
      }
    }

    if (bestRoute == null) return null;
    lastRouteAccessLegUsed = bestRoute.accessLegUsed;
    lastRouteAccessLegDistanceKm = bestRoute.accessLegDistanceKm;
    return bestRoute.route;
  }

  double _scoreRoundTripPoolAccessPlan({
    required double targetDistanceKm,
    required double activeDistanceKm,
    required double accessLegDistanceKm,
    required double accessLegSimilarityPercent,
    required double joinProgress,
    required double joinScore,
    required double loopCompletionRatio,
  }) {
    final earlyPenalty = joinProgress < 0.05
        ? (0.05 - joinProgress) * 22.0
        : 0.0;
    final latePenalty = joinProgress > 0.88
        ? (joinProgress - 0.88) * 18.0
        : 0.0;
    final distanceFitPenalty = targetDistanceKm > 0
        ? (activeDistanceKm - targetDistanceKm).abs() * 5.5
        : 0.0;
    final joinScorePenalty = joinScore / 1000.0;
    final incompleteLoopPenalty = loopCompletionRatio < 0.58
        ? (0.58 - loopCompletionRatio) * 70.0
        : 0.0;
    return distanceFitPenalty +
        accessLegDistanceKm * 6.5 +
        accessLegSimilarityPercent * 0.35 +
        incompleteLoopPenalty +
        earlyPenalty +
        latePenalty +
        joinScorePenalty;
  }

  List<int> _suggestRoundTripPoolExitIndices({
    required RouteResult route,
    required double targetDistanceKm,
    required double accessLegDistanceKm,
    required List<double> sessionOrigin,
    int maxCandidates = 2,
  }) {
    if (route.coordinates.length < 4) {
      return const [1];
    }

    final cumulativeDistances = _buildCoordinateCumulativeDistances(
      route.coordinates,
    );
    final sourceGeometryDistanceMeters = cumulativeDistances.last;
    final sourceDistanceMeters =
        route.distanceMeters ?? sourceGeometryDistanceMeters;
    final distanceScale = sourceGeometryDistanceMeters > 0
        ? sourceDistanceMeters / sourceGeometryDistanceMeters
        : 1.0;
    final totalDistanceKm = route.distanceKm ?? (sourceDistanceMeters / 1000.0);
    final deadEndSpikes = RouteQualityValidator.detectDeadEndSpikes(
      route.coordinates,
    );
    final minIndex = math.max(2, route.coordinates.length ~/ 6);
    final maxIndex = math.max(minIndex, route.coordinates.length - 3);
    final step = math.max(1, route.coordinates.length ~/ 32);
    final desiredLoopDistanceKm = targetDistanceKm > 0
        ? math.max(
            targetDistanceKm * 0.42,
            targetDistanceKm - (accessLegDistanceKm * 2.15) - 1.5,
          )
        : math.max(6.0, totalDistanceKm * 0.72);
    final clampedTargetLoopDistanceKm = desiredLoopDistanceKm.clamp(
      totalDistanceKm * 0.35,
      totalDistanceKm * 0.88,
    );
    final candidateIndices = <int>[];
    final targetBandsKm = <double>[
      clampedTargetLoopDistanceKm,
      math.max(totalDistanceKm * 0.35, clampedTargetLoopDistanceKm - 3.0),
      math.min(totalDistanceKm * 0.88, clampedTargetLoopDistanceKm + 3.0),
    ];

    for (final targetBandKm in targetBandsKm) {
      int? bestIndex;
      double? bestDelta;
      double? bestSessionDistanceKm;
      for (var index = minIndex; index <= maxIndex; index += step) {
        if (deadEndSpikes.any((spike) => spike.containsIndex(index))) continue;
        final loopDistanceKm =
            (cumulativeDistances[index] * distanceScale) / 1000.0;
        final completionRatio = totalDistanceKm > 0
            ? (loopDistanceKm / totalDistanceKm).clamp(0.0, 1.0)
            : 1.0;
        if (completionRatio < 0.35 || completionRatio > 0.92) continue;

        final delta = (loopDistanceKm - targetBandKm).abs();
        final exitCoordinate = route.coordinates[index];
        final sessionDistanceKm =
            _distanceBetweenCoordinates(exitCoordinate, sessionOrigin) / 1000.0;
        final currentBestDelta = bestDelta ?? double.infinity;
        final currentBestSessionDistanceKm =
            bestSessionDistanceKm ?? double.infinity;
        final isBetter =
            bestIndex == null ||
            delta < currentBestDelta - 0.25 ||
            ((delta - currentBestDelta).abs() <= 0.25 &&
                sessionDistanceKm < currentBestSessionDistanceKm);
        if (isBetter) {
          bestIndex = index;
          bestDelta = delta;
          bestSessionDistanceKm = sessionDistanceKm;
        }
      }
      if (bestIndex != null) {
        candidateIndices.add(bestIndex);
      }
    }

    int? nearestToSessionIndex;
    double? nearestToSessionDistanceKm;
    for (var index = minIndex; index <= maxIndex; index += step) {
      if (deadEndSpikes.any((spike) => spike.containsIndex(index))) continue;
      final loopDistanceKm =
          (cumulativeDistances[index] * distanceScale) / 1000.0;
      final completionRatio = totalDistanceKm > 0
          ? (loopDistanceKm / totalDistanceKm).clamp(0.0, 1.0)
          : 1.0;
      if (completionRatio < 0.35 || completionRatio > 0.92) continue;
      final sessionDistanceKm =
          _distanceBetweenCoordinates(route.coordinates[index], sessionOrigin) /
          1000.0;
      if (nearestToSessionIndex == null ||
          sessionDistanceKm < nearestToSessionDistanceKm!) {
        nearestToSessionIndex = index;
        nearestToSessionDistanceKm = sessionDistanceKm;
      }
    }
    if (nearestToSessionIndex != null) {
      candidateIndices.add(nearestToSessionIndex);
    }

    final chosen = <int>[];
    final minSeparation = math.max(8, route.coordinates.length ~/ 12);
    for (final candidate in candidateIndices) {
      if (chosen.any((value) => (value - candidate).abs() < minSeparation)) {
        continue;
      }
      chosen.add(candidate);
      if (chosen.length >= maxCandidates) break;
    }

    if (chosen.isEmpty) {
      chosen.add(math.max(2, route.coordinates.length - 3));
    }
    return chosen;
  }

  List<double> _buildCoordinateCumulativeDistances(
    List<List<double>> coordinates,
  ) {
    final cumulative = List<double>.filled(coordinates.length, 0.0);
    for (var index = 1; index < coordinates.length; index++) {
      cumulative[index] =
          cumulative[index - 1] +
          _distanceBetweenCoordinates(
            coordinates[index - 1],
            coordinates[index],
          );
    }
    return cumulative;
  }

  RouteResult _sliceRouteRange(
    RouteResult route,
    int startIndex,
    int endIndex,
  ) {
    final safeStart = startIndex
        .clamp(0, math.max(0, route.coordinates.length - 2))
        .toInt();
    final safeEnd = endIndex
        .clamp(
          safeStart + 1,
          math.max(safeStart + 1, route.coordinates.length - 1),
        )
        .toInt();
    final slicedCoordinates = route.coordinates
        .sublist(safeStart, safeEnd + 1)
        .map(_copyCoordinate)
        .toList(growable: false);
    final geometry = <String, dynamic>{
      'type': 'LineString',
      'coordinates': slicedCoordinates,
    };
    final sourceGeometryDistanceMeters = _distanceAlongCoordinates(
      route.coordinates,
    );
    final sourceDistanceMeters =
        route.distanceMeters ?? sourceGeometryDistanceMeters;
    final sourceDistanceScale = sourceGeometryDistanceMeters > 0
        ? sourceDistanceMeters / sourceGeometryDistanceMeters
        : 1.0;
    final distanceMeters =
        _distanceAlongCoordinates(slicedCoordinates) * sourceDistanceScale;
    final durationSeconds =
        route.durationSeconds != null && sourceDistanceMeters > 0
        ? route.durationSeconds! * (distanceMeters / sourceDistanceMeters)
        : route.durationSeconds;

    return _filteredRouteResult(
      RouteResult(
        geoJson: json.encode(geometry),
        geometry: geometry,
        coordinates: slicedCoordinates,
        maneuvers: const <RouteManeuver>[],
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
        distanceKm: distanceMeters / 1000.0,
        speedLimits: const <SpeedLimitSegment>[],
      ),
    );
  }

  bool _isPreliminarilyUsablePoolAccessRoute({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required RouteResult route,
  }) {
    final actualDistanceKm =
        route.distanceKm ??
        (route.distanceMeters != null ? route.distanceMeters! / 1000.0 : 0.0);
    final targetDistanceKm = scenario.targetDistanceKm ?? actualDistanceKm;
    final quality = _qualityValidator.validateQuality(
      coordinates: route.coordinates,
      isRoundTrip: scenario.isRoundTrip,
      targetDistanceKm: targetDistanceKm,
      actualDistanceKm: actualDistanceKm,
    );
    final styleFitScore = styleConfig.scoreStyleFit(
      coordinates: route.coordinates,
      distanceKm: actualDistanceKm,
      durationSeconds: route.durationSeconds,
    );
    final classification = _qualityValidator.classifyGeneratedRoute(
      quality: quality,
      isRoundTrip: scenario.isRoundTrip,
      coordinateCount: route.coordinates.length,
      actualDistanceKm: actualDistanceKm,
      targetDistanceKm: targetDistanceKm,
      styleProfileKey: styleConfig.profileKey,
      styleFitScore: styleFitScore,
    );
    final deadEndSpikes = RouteQualityValidator.detectDeadEndSpikes(
      route.coordinates,
    );
    if (deadEndSpikes.isNotEmpty) {
      lastRouteDeadEndSpikeDetected = true;
      return false;
    }
    return !classification.isRejected;
  }

  static int? _distanceBucketForPool(double? targetDistanceKm) {
    if (targetDistanceKm == null || !targetDistanceKm.isFinite) return null;
    if (targetDistanceKm <= 62.5) return 50;
    if (targetDistanceKm <= 87.5) return 75;
    if (targetDistanceKm <= 112.5) return 100;
    return null;
  }

  RouteResult? _routePoolEntryToRouteResult(
    RoutePoolMatch match, {
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required String fallbackReason,
  }) {
    final geometry = Map<String, dynamic>.from(match.route.geometry);
    if (geometry['type'] != 'LineString') return null;
    final coordinates = extractCoordinates(geometry);
    if (coordinates.length < 2) return null;
    final styleMetrics = styleConfig.calculateStyleMetrics(
      coordinates: coordinates,
      distanceKm: match.route.distanceKm,
      durationSeconds: match.route.durationSeconds,
    );
    final styleFitScore = styleConfig.scoreStyleFit(
      coordinates: coordinates,
      distanceKm: match.route.distanceKm,
      durationSeconds: match.route.durationSeconds,
    );
    final meta = <String, dynamic>{
      ...match.route.routePayload,
      'route_source': 'pool',
      'source': 'pool',
      'fallbackUsed': true,
      'fallback_reason': fallbackReason,
      'pool_match_id': match.route.id,
      'pool_match_tier': match.radiusScope,
      'pool_start_distance_km': match.startDistanceKm,
      'pool_allowed_radius_km': match.allowedRadiusKm,
      'quality_tier': 'good',
      'quality_reason': 'verified_route_pool',
      'selected_style': scenario.style,
      'style_fit_score': double.parse(styleFitScore.toStringAsFixed(1)),
      'style_fit_reasons': styleConfig.styleFitReasons(styleMetrics),
      'style_metrics': styleMetrics.toJson(),
      'curve_density_per_km': styleMetrics.toJson()['curve_density_per_km'],
      'smoothness_score': styleMetrics.smoothnessScore,
      'zigzag_score': styleMetrics.microZigzagPercent,
      'sharp_turn_count': styleMetrics.sharpCurveDensityPer50Km,
      'avoid_highways_requested': scenario.avoidHighways,
      'has_highway': match.route.hasHighway,
      'avoids_highway': match.route.avoidsHighway,
      'distance_bucket': match.route.distanceBucket,
      'mode': scenario.style,
      'orchestration': {
        'source': 'route_pool',
        'pool_hit': true,
        'pool_used': true,
        'pool_match_id': match.route.id,
        'pool_radius_scope': match.radiusScope,
        'mapbox_attempt_count': lastRouteApiCallCount,
        'fallback_reason': fallbackReason,
      },
    };
    return RouteResult(
      geoJson: json.encode(geometry),
      geometry: geometry,
      coordinates: coordinates,
      maneuvers: const [],
      distanceMeters: match.route.distanceKm * 1000.0,
      durationSeconds: match.route.durationSeconds,
      distanceKm: match.route.distanceKm,
      speedLimits: const [],
      edgeMeta: meta,
    );
  }

  RouteVariant _poolRouteVariant(RouteScenario scenario, RoutePoolMatch match) {
    final bucket = match.route.distanceBucket;
    return RouteVariant(
      index: 0,
      seed: 0,
      angleOffset: 0,
      radiusJitter: 1,
      offsetBearing: 0,
      fingerprintHint: '${scenario.scenarioKey}|pool|${match.route.id}',
      variantHint: 'pool-${match.route.id}-$bucket',
      styleBias: scenario.style,
    );
  }

  Future<RouteResult?> _tryRoundTripFallback({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required geo.Position startPosition,
    Map<String, double>? targetLocation,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final variant = await _nextRoundTripVariant(
          scenario,
          styleConfig: styleConfig,
        );
        final body = _buildRoundTripRequest(
          startPosition: startPosition,
          targetDistanceKm: (scenario.targetDistanceKm ?? 50.0).round(),
          mode: scenario.style,
          planningType: scenario.planningType,
          styleConfig: styleConfig,
          variant: variant,
          targetLocation: targetLocation,
          directionHint: variant.angleOffset,
          candidateBudget: _roundTripFallbackCandidateBudget(
            scenario,
            styleConfig,
          ),
          avoidHighways: scenario.avoidHighways,
        );
        body['simplify_waypoints'] = true;
        body['max_waypoints'] = 3;
        final result = await _invoke(body);
        final snapped = _snapRouteToStartPosition(result, startPosition);
        final candidate = _evaluateCandidate(
          scenario: scenario,
          styleConfig: styleConfig,
          route: snapped,
          variant: variant,
        );
        if (!candidate.accepted) {
          // Nicht nach dem ersten Reject abbrechen: zweiter Seed kann noch
          // eine brauchbare Fallback-Route liefern.
          continue;
        }
        final fallbackStyleFloor = styleConfig.profileKey == 'sport'
            ? styleConfig.minStyleFitScore - 8.0
            : styleConfig.minStyleFitScore;
        if (scenario.isRoundTrip &&
            candidate.styleFitScore < fallbackStyleFloor) {
          debugPrint(
            '[RouteService] Rundkurs-Fallback stilistisch verworfen: '
            'styleFit=${candidate.styleFitScore.toStringAsFixed(1)} '
            '< ${fallbackStyleFloor.toStringAsFixed(1)}',
          );
          continue;
        }
        if (!candidate.novelEnough) {
          debugPrint(
            '[RouteService] Rundkurs-Fallback Duplicate verworfen, retry=${attempt + 1}',
          );
          continue;
        }
        return _finalizeAndRemember(
          scenario: scenario,
          route: candidate.route,
          sampledCoordinates: candidate.sampledCoordinates,
          fingerprint: candidate.fingerprint,
        );
      } catch (e) {
        debugPrint(
          '[RouteService] Rundkurs-Fallback Versuch ${attempt + 1}/2 fehlgeschlagen: $e',
        );
        continue;
      }
    }
    return null;
  }

  Future<RouteResult?> _tryRoundTripRescueFallback({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required geo.Position startPosition,
    Map<String, double>? targetLocation,
  }) async {
    if (_isInWorkerLimitCooldown()) return null;

    if (!(scenario.avoidHighways && styleConfig.profileKey != 'sport')) {
      final sameStyle = await _requestRoundTripRescueVariant(
        scenario: scenario,
        requestStyleConfig: styleConfig,
        startPosition: startPosition,
        mode: scenario.style,
        planningType: scenario.planningType,
        targetLocation: targetLocation,
        avoidHighways: scenario.avoidHighways,
        candidateBudget: _roundTripFallbackCandidateBudget(
          scenario,
          styleConfig,
        ),
        targetFactor: 0.96,
        label: 'same-style',
      );
      if (sameStyle != null) return sameStyle;
    }

    if (!scenario.avoidHighways &&
        styleConfig.profileKey == 'sport' &&
        (scenario.targetDistanceKm ?? 0.0) >= 70.0) {
      final spreadStyle = RouteStyleConfig.forMode('Entdecker');
      final sportSpread = await _requestRoundTripRescueVariant(
        scenario: scenario,
        requestStyleConfig: spreadStyle,
        evaluationStyleConfig: styleConfig,
        startPosition: startPosition,
        mode: scenario.style,
        planningType: scenario.planningType,
        targetLocation: targetLocation,
        avoidHighways: scenario.avoidHighways,
        candidateBudget: _roundTripFallbackCandidateBudget(
          scenario,
          spreadStyle,
        ),
        targetFactor: 1.0,
        label: 'sport-spread',
      );
      if (sportSpread != null) return sportSpread;
    }

    // Letzter kontrollierter Rescue-Schritt: Wenn ein harter Stilfilter
    // normale Rundkurse blockiert, versuchen wir eine einfache Sport-Loop-
    // Variante. Der UI-Modus bleibt unverändert, und der Autobahn-Toggle wird
    // strikt beibehalten.
    if (scenario.avoidHighways || styleConfig.profileKey != 'sport') {
      final sportStyle = RouteStyleConfig.forMode('Sport Mode');
      return _requestRoundTripRescueVariant(
        scenario: scenario,
        requestStyleConfig: sportStyle,
        startPosition: startPosition,
        mode: scenario.style,
        requestMode: 'Sport Mode',
        planningType: scenario.planningType,
        targetLocation: targetLocation,
        avoidHighways: scenario.avoidHighways,
        candidateBudget: _roundTripFallbackCandidateBudget(
          scenario,
          sportStyle,
        ),
        targetFactor: 0.94,
        label: 'sport-relaxed',
      );
    }

    return null;
  }

  Future<RouteResult?> _requestRoundTripRescueVariant({
    required RouteScenario scenario,
    required RouteStyleConfig requestStyleConfig,
    RouteStyleConfig? evaluationStyleConfig,
    required geo.Position startPosition,
    required String mode,
    String? requestMode,
    required String planningType,
    required bool avoidHighways,
    required int candidateBudget,
    required double targetFactor,
    required String label,
    Map<String, double>? targetLocation,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final variant = await _nextRoundTripVariant(
          scenario,
          styleConfig: requestStyleConfig,
        );
        final rawTarget = math.max(
          25.0,
          (scenario.targetDistanceKm ?? 50.0) * targetFactor,
        );
        final targetKm = requestStyleConfig
            .clampRoundTripDistanceKm(rawTarget.round())
            .round();
        final body = _buildRoundTripRequest(
          startPosition: startPosition,
          targetDistanceKm: targetKm,
          mode: requestMode ?? mode,
          planningType: planningType,
          styleConfig: requestStyleConfig,
          variant: variant,
          targetLocation: targetLocation,
          directionHint: (variant.angleOffset + 37.0) % 360.0,
          candidateBudget: candidateBudget,
          avoidHighways: avoidHighways,
        );
        body['simplify_waypoints'] = true;
        body['max_waypoints'] = _rescueRoundTripWaypointLimit(scenario);
        body['rescue_round_trip'] = true;
        body['route_variant_hint'] = '${variant.variantHint}-rescue-$label';

        debugPrint(
          '[RouteService] Rundkurs-Rescue $label: '
          'mode=${requestMode ?? mode}, uiMode=$mode, '
          'target=${targetKm}km, avoidHighways=$avoidHighways, '
          'budget=$candidateBudget, retry=${attempt + 1}',
        );

        final result = await _invoke(body);
        final snapped = _snapRouteToStartPosition(result, startPosition);
        final candidate = _evaluateCandidate(
          scenario: scenario,
          styleConfig: evaluationStyleConfig ?? requestStyleConfig,
          route: snapped,
          variant: variant,
          relaxedRoundTrip: true,
        );
        if (!candidate.accepted) {
          debugPrint(
            '[RouteService] Rundkurs-Rescue $label verworfen: '
            'score=${candidate.score.toStringAsFixed(1)}, '
            'styleFit=${candidate.styleFitScore.toStringAsFixed(1)}',
          );
          // Früher Abbruch erzeugte unnötige NO_ROUTE-Fälle.
          continue;
        }
        final rescueStyleFloor =
            (evaluationStyleConfig ?? requestStyleConfig).minStyleFitScore -
            (label == 'sport-relaxed' ? 18.0 : 6.0);
        if (scenario.isRoundTrip &&
            candidate.styleFitScore < rescueStyleFloor) {
          debugPrint(
            '[RouteService] Rundkurs-Rescue $label stilistisch verworfen: '
            'styleFit=${candidate.styleFitScore.toStringAsFixed(1)} '
            '< ${rescueStyleFloor.toStringAsFixed(1)}',
          );
          continue;
        }
        if (!candidate.novelEnough) {
          debugPrint(
            '[RouteService] Rundkurs-Rescue $label Duplicate verworfen, retry=${attempt + 1}',
          );
          continue;
        }
        debugPrint('[RouteService] Rundkurs-Rescue $label akzeptiert.');
        return _finalizeAndRemember(
          scenario: scenario,
          route: candidate.route,
          sampledCoordinates: candidate.sampledCoordinates,
          fingerprint: candidate.fingerprint,
        );
      } catch (e) {
        debugPrint(
          '[RouteService] Rundkurs-Rescue $label Versuch ${attempt + 1}/2 fehlgeschlagen: $e',
        );
        continue;
      }
    }
    return null;
  }

  Future<RouteResult?> _tryPointToPointFallback({
    required RouteScenario scenario,
    required geo.Position startPosition,
    required double destinationLat,
    required double destinationLng,
    required bool avoidHighways,
    required double directDistanceKm,
    bool allowDirectFallback = true,
  }) async {
    try {
      if (scenario.detourLevel > 0) {
        final scenicVariant = _nextPointToPointVariant(
          scenario,
          normalizedVariant: scenario.detourLevel,
          diversitySeed: 97,
          shouldDiversify: true,
        );
        final scenicMode = scenario.style == 'Standard'
            ? 'Sport Mode'
            : scenario.style;
        final scenicStyleConfig = RouteStyleConfig.forMode(scenicMode);
        final scenicDetourFactor = switch (scenario.detourLevel) {
          1 => 1.32,
          2 => 1.65,
          3 => 2.10,
          _ => 1.15,
        };
        final scenicBody = _buildPointToPointRequest(
          startPosition: startPosition,
          destinationLat: destinationLat,
          destinationLng: destinationLng,
          mode: scenicMode,
          scenic: true,
          normalizedVariant: scenario.detourLevel,
          avoidHighways: avoidHighways,
          styleConfig: scenicStyleConfig,
          targetDistanceKm: scenario.targetDistanceKm ?? directDistanceKm,
          detourFactor: scenicDetourFactor,
          variant: scenicVariant,
          candidateBudget: 2,
        );
        scenicBody['simplify_waypoints'] = true;
        scenicBody['max_waypoints'] = _pointToPointFallbackWaypointLimit(
          scenario,
          avoidHighways: avoidHighways,
        );
        final scenicResult = await _invoke(scenicBody);
        final scenicSnapped = _snapRouteToStartPosition(
          scenicResult,
          startPosition,
        );
        final scenicCandidate = _evaluateCandidate(
          scenario: scenario,
          styleConfig: scenicStyleConfig,
          route: scenicSnapped,
          variant: scenicVariant,
          directDistanceKm: directDistanceKm,
        );
        if (scenicCandidate.accepted && scenicCandidate.novelEnough) {
          return _finalizeAndRemember(
            scenario: scenario,
            route: scenicCandidate.route,
            sampledCoordinates: scenicCandidate.sampledCoordinates,
            fingerprint: scenicCandidate.fingerprint,
          );
        }
        debugPrint(
          '[RouteService] Vereinfachter Scenic-Fallback verworfen: ${scenicCandidate.route.distanceKm?.toStringAsFixed(1)}km',
        );
        if (!allowDirectFallback) return null;
      }

      if (!allowDirectFallback) return null;

      final variant = _nextPointToPointVariant(
        scenario,
        normalizedVariant: 0,
        diversitySeed: 0,
        shouldDiversify: false,
      );
      final body = _buildPointToPointRequest(
        startPosition: startPosition,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
        mode: 'Standard',
        scenic: false,
        normalizedVariant: 0,
        avoidHighways: avoidHighways,
        styleConfig: RouteStyleConfig.forMode('Sport Mode'),
        targetDistanceKm: directDistanceKm,
        detourFactor: 1.0,
        variant: variant,
        candidateBudget: 2,
      );
      body['simplify_waypoints'] = true;
      body['max_waypoints'] = 0;
      final result = await _invoke(body);
      final snapped = _snapRouteToStartPosition(result, startPosition);
      final directCandidate = _evaluateCandidate(
        scenario: scenario,
        styleConfig: RouteStyleConfig.forMode('Sport Mode'),
        route: snapped,
        variant: variant,
        directDistanceKm: directDistanceKm,
      );
      if (!directCandidate.accepted || !directCandidate.novelEnough) {
        return null;
      }
      return _finalizeAndRemember(
        scenario: scenario,
        route: directCandidate.route,
        sampledCoordinates: directCandidate.sampledCoordinates,
        fingerprint: directCandidate.fingerprint,
      );
    } catch (e) {
      debugPrint('[RouteService] A→B-Fallback fehlgeschlagen: $e');
      return null;
    }
  }

  bool _needsStrongerPointToPointDetour({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required _RouteCandidate candidate,
    required double directDistanceKm,
  }) {
    if (!scenario.isPointToPoint || scenario.detourLevel <= 0) return false;

    final actualDistanceKm = candidate.route.distanceKm ?? 0.0;
    final minimumRenderableKm = styleConfig.minimumPointToPointDistanceKm(
      directDistanceKm: directDistanceKm,
      scenic: true,
      detourVariant: scenario.detourLevel,
    );
    final preferredSlackKm = switch (scenario.detourLevel) {
      1 => 0.0,
      2 => 1.5,
      3 => 3.0,
      _ => 0.0,
    };
    return actualDistanceKm < minimumRenderableKm + preferredSlackKm;
  }

  static RouteServiceException _mapInvokeException({
    required Object error,
    required StackTrace stack,
    int? statusCode,
    required String routeType,
  }) {
    if (error is RouteServiceException) return error;

    if (error is FunctionException) {
      final detailsMessage = error.details?.toString() ?? '';
      return _mapServiceError(
        errorMessage: detailsMessage,
        statusCode: error.status,
        details: error.details,
        stackTrace: stack,
        reasonPhrase: error.reasonPhrase,
        routeType: routeType,
      );
    }

    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (error is TimeoutException ||
        lower.contains('timeout') ||
        lower.contains('netzwerk') ||
        lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('network')) {
      return RouteServiceException(
        type: RouteErrorType.network,
        userMessage:
            'Keine Verbindung zum Routing-Dienst. Bitte Internetverbindung prüfen.',
        debugMessage: raw,
        statusCode: statusCode,
        stackTrace: stack,
      );
    }

    return RouteServiceException(
      type: RouteErrorType.unknown,
      userMessage: 'Routenberechnung fehlgeschlagen. Bitte erneut versuchen.',
      debugMessage: raw,
      statusCode: statusCode,
      stackTrace: stack,
    );
  }

  static RouteServiceException _mapServiceError({
    required String errorMessage,
    int? statusCode,
    Object? details,
    StackTrace? stackTrace,
    String? reasonPhrase,
    String routeType = 'ROUND_TRIP',
  }) {
    final lower = errorMessage.toLowerCase();
    final detailsMap = details is Map
        ? Map<String, dynamic>.from(details)
        : null;
    final errorCode = detailsMap?['code']?.toString().toUpperCase();
    final retryAfterSec = (detailsMap?['retry_after_sec'] as num?)?.toInt();
    final edgeMeta = detailsMap?['meta'] is Map
        ? Map<String, dynamic>.from(detailsMap!['meta'] as Map)
        : const <String, dynamic>{};

    if (statusCode == 401 || statusCode == 403 || lower.contains('jwt')) {
      return RouteServiceException(
        type: RouteErrorType.auth,
        userMessage:
            'Routing-Anfrage wurde abgelehnt. Bitte erneut anmelden und nochmals versuchen.',
        debugMessage:
            'Auth error (status=$statusCode, reason=$reasonPhrase): $errorMessage, details=$details',
        statusCode: statusCode,
        stackTrace: stackTrace,
      );
    }

    if (statusCode == 429 ||
        errorCode == 'RATE_LIMIT' ||
        lower.contains('rate limit') ||
        lower.contains('too many')) {
      return RouteServiceException(
        type: RouteErrorType.rateLimit,
        userMessage:
            'Zu viele Routing-Anfragen in kurzer Zeit. Bitte kurz warten und erneut versuchen.',
        debugMessage:
            'Rate limit (status=$statusCode, reason=$reasonPhrase): $errorMessage, details=$details',
        statusCode: statusCode,
        stackTrace: stackTrace,
      );
    }

    if (errorCode == 'WORKER_LIMIT' ||
        lower.contains('worker limit') ||
        lower.contains('resource limit') ||
        lower.contains('cpu time limit')) {
      return RouteServiceException(
        type: RouteErrorType.workerLimit,
        userMessage:
            'Der Routing-Dienst ist gerade stark ausgelastet. Bitte ${retryAfterSec ?? 2} Sekunden warten und erneut versuchen.',
        debugMessage:
            'Worker limit (status=$statusCode, reason=$reasonPhrase): $errorMessage, details=$details',
        statusCode: statusCode,
        stackTrace: stackTrace,
      );
    }

    if (errorCode == 'TIMEOUT' ||
        lower.contains('timeout') ||
        lower.contains('timed out')) {
      return RouteServiceException(
        type: RouteErrorType.server,
        userMessage:
            'Die Routenberechnung hat zu lange gedauert. Bitte erneut versuchen.',
        debugMessage:
            'Timeout (status=$statusCode, reason=$reasonPhrase): $errorMessage, details=$details',
        statusCode: statusCode,
        stackTrace: stackTrace,
      );
    }

    if (statusCode != null && statusCode >= 500) {
      return RouteServiceException(
        type: RouteErrorType.server,
        userMessage:
            'Temporärer Serverfehler beim Routing. Bitte in wenigen Sekunden erneut versuchen.',
        debugMessage:
            'Server error (status=$statusCode, reason=$reasonPhrase): $errorMessage, details=$details',
        statusCode: statusCode,
        stackTrace: stackTrace,
      );
    }

    if (lower.contains('no route found') ||
        lower.contains('keine route gefunden') ||
        lower.contains('no route') ||
        lower.contains('keine passende route')) {
      final userMessage = routeType == 'ROUND_TRIP'
          ? 'Kein passender Rundkurs gefunden. Bitte ändere Stil, Länge oder Standort.'
          : 'Keine passende Route gefunden. Bitte ändere Start/Ziel oder die Routeneinstellungen.';
      return RouteServiceException(
        type: RouteErrorType.noRoute,
        userMessage: userMessage,
        debugMessage:
            'No-route error (status=$statusCode, reason=$reasonPhrase): $errorMessage, details=$details',
        statusCode: statusCode,
        stackTrace: stackTrace,
        edgeMeta: edgeMeta,
      );
    }

    if (lower.contains('invalid') ||
        lower.contains('missing') ||
        lower.contains('ungültig') ||
        lower.contains('out of bounds') ||
        lower.contains('destination') ||
        lower.contains('startlocation')) {
      final userMessage = routeType == 'ROUND_TRIP'
          ? 'Rundkurs-Parameter sind ungültig. Bitte Länge, Stil oder Standort prüfen.'
          : 'Start, Ziel oder Routenparameter sind ungültig. Bitte Eingaben prüfen.';
      return RouteServiceException(
        type: RouteErrorType.validation,
        userMessage: userMessage,
        debugMessage:
            'Validation error (status=$statusCode, reason=$reasonPhrase): $errorMessage, details=$details',
        statusCode: statusCode,
        stackTrace: stackTrace,
      );
    }

    if (lower.contains('qualität') || lower.contains('quality')) {
      return RouteServiceException(
        type: RouteErrorType.quality,
        userMessage:
            'Für diese Einstellungen konnte keine stabile Route erzeugt werden. Bitte leicht anpassen und erneut versuchen.',
        debugMessage:
            'Quality error (status=$statusCode, reason=$reasonPhrase): $errorMessage, details=$details',
        statusCode: statusCode,
        stackTrace: stackTrace,
      );
    }

    return RouteServiceException(
      type: RouteErrorType.unknown,
      userMessage: 'Routenberechnung fehlgeschlagen. Bitte erneut versuchen.',
      debugMessage:
          'Unmapped routing error (status=$statusCode, reason=$reasonPhrase): $errorMessage, details=$details',
      statusCode: statusCode,
      stackTrace: stackTrace,
    );
  }

  static int _nextRandomSeed() {
    final candidate = DateTime.now().microsecondsSinceEpoch % 2147483647;
    if (candidate <= _lastRandomSeed) {
      _lastRandomSeed += 1;
    } else {
      _lastRandomSeed = candidate;
    }
    return _lastRandomSeed;
  }

  bool _shouldUseCachedFallbackRoute(
    RouteResult cached, {
    required RouteScenario scenario,
    RouteServiceException? lastError,
    bool requireNovelty = true,
  }) {
    final actualDistanceKm =
        cached.distanceKm ??
        ((cached.distanceMeters ?? 0.0) > 0
            ? (cached.distanceMeters! / 1000.0)
            : 0.0);
    if (actualDistanceKm <= 0 || cached.coordinates.length < 8) return false;

    final targetDistanceKm = scenario.isRoundTrip
        ? (scenario.targetDistanceKm ?? actualDistanceKm)
        : 0.0;
    final quality = _qualityValidator.validateQuality(
      coordinates: cached.coordinates,
      isRoundTrip: scenario.isRoundTrip,
      targetDistanceKm: targetDistanceKm,
      actualDistanceKm: actualDistanceKm,
    );
    if (requireNovelty && !_isNovelRouteForScenario(scenario, cached)) {
      return false;
    }
    final classification = _qualityValidator.classifyGeneratedRoute(
      quality: quality,
      isRoundTrip: scenario.isRoundTrip,
      coordinateCount: cached.coordinates.length,
      actualDistanceKm: actualDistanceKm,
      targetDistanceKm: targetDistanceKm,
    );
    if (classification.isRejected) return false;
    if (classification.isGood) return true;

    final transientProviderFailure =
        lastError == null ||
        lastError.type == RouteErrorType.noRoute ||
        lastError.type == RouteErrorType.quality ||
        lastError.type == RouteErrorType.network ||
        lastError.type == RouteErrorType.server ||
        lastError.type == RouteErrorType.rateLimit ||
        lastError.type == RouteErrorType.workerLimit ||
        lastError.type == RouteErrorType.emptyResponse ||
        lastError.type == RouteErrorType.unknown;

    if (scenario.isRoundTrip) {
      final strictAcceptable =
          quality.isLoopClosed &&
          quality.distanceInTolerance &&
          quality.uturnPositions.isEmpty &&
          quality.overlapPercent <= 22.0 &&
          quality.shapePenalty <= 42.0 &&
          quality.spurArmPercent <= 18.0 &&
          quality.centerReentryCount <= 1 &&
          quality.repeatedStartAreaPercent <= 18.0 &&
          quality.microZigzagPercent <= 18.0;
      if (strictAcceptable) return true;

      return transientProviderFailure &&
          quality.isLoopClosed &&
          quality.uturnPositions.length <= 1 &&
          quality.overlapPercent <= 30.0 &&
          quality.shapePenalty <= 54.0 &&
          quality.spurArmPercent <= 24.0 &&
          quality.centerReentryCount <= 1 &&
          quality.repeatedStartAreaPercent <= 26.0 &&
          quality.microZigzagPercent <= 26.0;
    }

    final strictAcceptable =
        quality.uturnPositions.isEmpty &&
        quality.overlapPercent <= 14.0 &&
        quality.shapePenalty <= 30.0 &&
        quality.microZigzagPercent <= 18.0;
    if (strictAcceptable) return true;

    return transientProviderFailure &&
        quality.uturnPositions.isEmpty &&
        quality.overlapPercent <= 20.0 &&
        quality.shapePenalty <= 36.0 &&
        quality.microZigzagPercent <= 24.0;
  }

  bool _shouldUseRecentFallbackRoute(
    RouteResult recent, {
    required RouteScenario scenario,
    RouteServiceException? lastError,
    bool requireNovelty = true,
  }) {
    final actualDistanceKm =
        recent.distanceKm ??
        ((recent.distanceMeters ?? 0.0) > 0
            ? (recent.distanceMeters! / 1000.0)
            : 0.0);
    if (actualDistanceKm <= 0 || recent.coordinates.length < 8) return false;
    if (lastError?.type == RouteErrorType.validation) return false;

    final targetDistanceKm = scenario.isRoundTrip
        ? (scenario.targetDistanceKm ?? actualDistanceKm)
        : 0.0;
    final quality = _qualityValidator.validateQuality(
      coordinates: recent.coordinates,
      isRoundTrip: scenario.isRoundTrip,
      targetDistanceKm: targetDistanceKm,
      actualDistanceKm: actualDistanceKm,
    );
    if (requireNovelty && !_isNovelRouteForScenario(scenario, recent)) {
      return false;
    }
    final classification = _qualityValidator.classifyGeneratedRoute(
      quality: quality,
      isRoundTrip: scenario.isRoundTrip,
      coordinateCount: recent.coordinates.length,
      actualDistanceKm: actualDistanceKm,
      targetDistanceKm: targetDistanceKm,
    );
    if (classification.isRejected) return false;

    final recoverableSearchFailure =
        lastError == null ||
        lastError.type == RouteErrorType.noRoute ||
        lastError.type == RouteErrorType.quality ||
        lastError.type == RouteErrorType.network ||
        lastError.type == RouteErrorType.server ||
        lastError.type == RouteErrorType.rateLimit ||
        lastError.type == RouteErrorType.workerLimit ||
        lastError.type == RouteErrorType.emptyResponse ||
        lastError.type == RouteErrorType.unknown;
    if (!recoverableSearchFailure) return false;

    if (scenario.isRoundTrip) {
      return quality.isLoopClosed &&
          quality.uturnPositions.length <= 1 &&
          quality.overlapPercent <= 24.0 &&
          quality.shapePenalty <= 60.0 &&
          quality.centerReentryCount <= 1 &&
          quality.repeatedStartAreaPercent <= 40.0;
    }

    return quality.uturnPositions.isEmpty &&
        quality.overlapPercent <= 22.0 &&
        quality.shapePenalty <= 38.0;
  }

  // ─────────────────────── Persistent Route Cache ────────────────────────────

  /// Speichert eine erfolgreiche Route im SharedPreferences für Offline-Fallback.
  Future<void> _cacheSuccessfulRoute(
    RouteResult route, {
    String? scenarioKey,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'geoJson': route.geoJson,
        'geometry': route.geometry,
        'coordinates': route.coordinates,
        'distanceMeters': route.distanceMeters,
        'durationSeconds': route.durationSeconds,
        'distanceKm': route.distanceKm,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      final cacheKey = scenarioKey == null
          ? _lastSuccessfulRouteKey
          : '$_lastSuccessfulRouteKey|$scenarioKey';
      await prefs.setString(cacheKey, json.encode(cacheData));
      debugPrint('[RouteService] ✓ Route im Offline-Cache gespeichert');
    } catch (e) {
      debugPrint('[RouteService] Cache-Speicherung fehlgeschlagen: $e');
    }
  }

  /// Lädt die letzte erfolgreiche Route aus SharedPreferences.
  /// Gibt null zurück wenn keine gecachte Route existiert oder sie >24h alt ist.
  Future<RouteResult?> _loadCachedRoute({String? scenarioKey}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scopedKey = scenarioKey == null
          ? _lastSuccessfulRouteKey
          : '$_lastSuccessfulRouteKey|$scenarioKey';
      final cached = scenarioKey == null
          ? prefs.getString(_lastSuccessfulRouteKey)
          : prefs.getString(scopedKey);
      if (cached == null) return null;

      final data = json.decode(cached) as Map<String, dynamic>;
      final timestamp = data['timestamp'] as int?;
      if (timestamp != null) {
        final age = DateTime.now().millisecondsSinceEpoch - timestamp;
        if (age > 24 * 60 * 60 * 1000) {
          debugPrint(
            '[RouteService] Gecachte Route ist >24h alt, wird ignoriert',
          );
          return null;
        }
      }

      final coordinates =
          (data['coordinates'] as List?)
              ?.map(
                (c) => (c as List).map((v) => (v as num).toDouble()).toList(),
              )
              .toList() ??
          [];

      if (coordinates.length < 2) return null;

      debugPrint(
        '[RouteService] 📦 Gecachte Route geladen (${coordinates.length} Punkte)',
      );
      return RouteResult(
        geoJson: data['geoJson'] as String? ?? '',
        geometry: Map<String, dynamic>.from(data['geometry'] as Map? ?? {}),
        coordinates: coordinates,
        maneuvers: const [], // Manöver nicht gecacht, werden neu berechnet
        distanceMeters: (data['distanceMeters'] as num?)?.toDouble(),
        durationSeconds: (data['durationSeconds'] as num?)?.toDouble(),
        distanceKm: (data['distanceKm'] as num?)?.toDouble(),
        speedLimits: const [],
      );
    } catch (e) {
      debugPrint('[RouteService] Cache-Laden fehlgeschlagen: $e');
      return null;
    }
  }

  Future<RouteResult?> _loadRecentOrCachedRoute({String? scenarioKey}) async {
    if (scenarioKey != null) {
      final recent = _recentSuccessfulRoutes[scenarioKey];
      if (recent != null) {
        debugPrint(
          '[RouteService] ♻️ Letzte erfolgreiche Route aus Memory-Cache geladen',
        );
        return recent;
      }
    }
    return _loadCachedRoute(scenarioKey: scenarioKey);
  }

  // ─────────────────────── Coordinate Helpers ────────────────────────────────

  /// Extrahiert Koordinaten-Liste aus einem GeoJSON-Geometry-Objekt.
  List<List<double>> extractCoordinates(Map<String, dynamic> geometry) {
    final raw = (geometry['coordinates'] as List?) ?? const [];
    return raw
        .whereType<List>()
        .where((c) => c.length >= 2)
        .map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
        .toList();
  }

  // ────────────────────── Maneuver Extraction ────────────────────────────────

  /// Extrahiert alle Navigationsanweisungen aus der API-Antwort.
  List<RouteManeuver> extractManeuvers(
    dynamic responseData,
    List<List<double>> routeCoordinates,
  ) {
    final route = responseData is Map ? responseData['route'] : null;
    final legs = route is Map ? route['legs'] as List? : null;
    if (legs == null || legs.isEmpty || routeCoordinates.length < 2) {
      return const [];
    }

    final maneuvers = <RouteManeuver>[];

    for (final leg in legs) {
      if (leg is! Map) continue;
      final steps = leg['steps'] as List?;
      if (steps == null) continue;

      for (final step in steps) {
        if (step is! Map) continue;
        final maneuver = step['maneuver'];
        if (maneuver is! Map) continue;

        final type = (maneuver['type'] as String?) ?? '';
        // Depart überspringen (Start braucht kein Manöver)
        if (type == 'depart') continue;

        final distance = (step['distance'] as num?)?.toDouble() ?? 0;
        // Nur "arrive" mit kurzer Distanz behalten, sonst zu kurze Steps
        // ignorieren (vermeidet doppelte Manöver am Start)
        if (distance < 15 && type != 'arrive') continue;

        final location = maneuver['location'];
        if (location is! List || location.length < 2) continue;

        final longitude = (location[0] as num).toDouble();
        final latitude = (location[1] as num).toDouble();
        final modifier = (maneuver['modifier'] as String?) ?? '';
        final rawInstruction =
            (maneuver['instruction'] as String?) ??
            (step['name'] as String?) ??
            _announcementForModifier(modifier);

        final routeIndex = _findNearestIndex(
          latitude,
          longitude,
          routeCoordinates,
        );

        // Kreisverkehr erkennen
        final isRoundabout =
            type == 'roundabout' ||
            type == 'rotary' ||
            type == 'roundabout turn';
        final exitNumber = isRoundabout
            ? (maneuver['exit'] as num?)?.toInt()
            : null;

        // Instruction bestimmen
        String instruction;
        if (isRoundabout) {
          instruction = _roundaboutInstruction(
            exitNumber,
            rawInstruction,
            modifier,
          );
        } else if (type == 'arrive') {
          instruction = 'Ziel erreicht.';
        } else if (type == 'end of road') {
          // Straßenende: klare Abbiegeanweisung
          final street = (step['name'] as String?) ?? '';
          final dirText = modifier.contains('left') ? 'Links' : 'Rechts';
          instruction = street.isNotEmpty
              ? '$dirText auf $street abbiegen.'
              : '$dirText abbiegen.';
        } else if (type == 'new name' || type == 'continue') {
          // Nur als echte Anweisung behalten wenn tatsächlich Richtungswechsel
          final mod = modifier.toLowerCase();
          if (mod == 'straight' || mod.isEmpty) {
            instruction = _normalizeInstruction(rawInstruction, modifier);
          } else {
            // Echte Richtungsänderung bei Straßennamenwechsel
            final street = (step['name'] as String?) ?? '';
            final dirText = directionText(mod);
            instruction = street.isNotEmpty
                ? '$dirText auf $street abbiegen.'
                : '$dirText abbiegen.';
          }
        } else {
          instruction = _normalizeInstruction(rawInstruction, modifier);
        }

        maneuvers.add(
          RouteManeuver(
            latitude: latitude,
            longitude: longitude,
            routeIndex: routeIndex,
            icon: isRoundabout
                ? Icons.roundabout_right
                : iconForManeuver(type, modifier),
            announcement: _announcementFromInstruction(
              rawInstruction,
              modifier,
              distance,
              type: type,
            ),
            instruction: instruction,
            maneuverType: isRoundabout
                ? ManeuverType.roundabout
                : ManeuverType.normal,
            roundaboutExitNumber: exitNumber,
          ),
        );
      }
    }

    maneuvers.sort((a, b) => a.routeIndex.compareTo(b.routeIndex));
    return maneuvers;
  }

  int _findNearestIndex(
    double latitude,
    double longitude,
    List<List<double>> coordinates,
  ) {
    var nearestIndex = 0;
    var nearestDistance = double.infinity;

    for (var i = 0; i < coordinates.length; i++) {
      final c = coordinates[i];
      if (c.length < 2) continue;
      final d = geo.Geolocator.distanceBetween(latitude, longitude, c[1], c[0]);
      if (d < nearestDistance) {
        nearestDistance = d;
        nearestIndex = i;
      }
    }
    return nearestIndex;
  }

  /// Filtert problematische Manöver aus der Liste:
  /// - U-Turns (beide Richtungen) — Mapbox generiert diese bei Rundkursen fälschlicherweise
  /// - Zwischenziel-"Arrive" — nur das letzte "Ziel erreicht" behalten
  /// - Kurze "continue/new name"-Manöver die eigentlich geradeaus sind
  // ignore: library_private_types_in_public_api
  List<RouteManeuver> filterManeuvers(List<RouteManeuver> maneuvers) {
    if (maneuvers.isEmpty) return maneuvers;

    // Finde den letzten Arrive-Index (= echtes Ziel)
    int lastArriveIndex = -1;
    for (var i = maneuvers.length - 1; i >= 0; i--) {
      if (maneuvers[i].icon == Icons.flag) {
        lastArriveIndex = i;
        break;
      }
    }

    final filtered = <RouteManeuver>[];
    for (var i = 0; i < maneuvers.length; i++) {
      final m = maneuvers[i];

      // U-Turns komplett entfernen (beide Richtungen)
      if (m.icon == Icons.u_turn_left || m.icon == Icons.u_turn_right) continue;

      // Zwischenziel-Arrives entfernen (nur das LETZTE behalten)
      if (m.icon == Icons.flag && i != lastArriveIndex) continue;

      // "Geradeaus" Manöver entfernen die keinen echten Richtungswechsel darstellen
      // (z.B. Straßennamenwechsel ohne Abbiegen)
      if (m.icon == Icons.straight && m.instruction.contains('Weiterfahren')) {
        continue;
      }

      filtered.add(m);
    }

    return filtered;
  }

  /// Finalisiert eine Route: filtert problematische Manöver (U-Turns, Zwischen-Arrives).
  /// Wird am Ende von generateRoundTrip/generatePointToPoint aufgerufen.
  /// Speichert die Route auch im Offline-Cache für Stufe-4-Fallback.
  RouteResult _finalizeRoute(RouteResult result, {String? scenarioKey}) {
    final filtered = _filteredRouteResult(result);
    final finalized = _withOrchestrationMeta(filtered);
    // Asynchron cachen ohne auf Ergebnis zu warten
    _cacheSuccessfulRoute(finalized, scenarioKey: scenarioKey);
    return finalized;
  }

  RouteResult _withOrchestrationMeta(RouteResult result) {
    final meta = Map<String, dynamic>.from(result.edgeMeta);
    final startedAtMs = lastRouteGenerationStartedAtMs;
    final generationDurationMs = startedAtMs == null
        ? null
        : math.max(0, DateTime.now().millisecondsSinceEpoch - startedAtMs);
    meta['route_source'] = lastRouteGenerationSource;
    meta['source'] = lastRouteGenerationSource;
    meta['quality_tier'] ??= 'acceptable';
    meta['quality_reason'] ??= meta['quality_reason'] ?? 'client_accepted';
    final selectedStyle =
        lastRouteRequestedStyle ?? meta['mode']?.toString() ?? 'Sport Mode';
    final styleConfig = RouteStyleConfig.forMode(selectedStyle);
    final styleDistanceKm =
        result.distanceKm ??
        (result.distanceMeters != null ? result.distanceMeters! / 1000.0 : 0.0);
    if (styleDistanceKm > 0 && result.coordinates.length >= 6) {
      final styleMetrics = styleConfig.calculateStyleMetrics(
        coordinates: result.coordinates,
        distanceKm: styleDistanceKm,
        durationSeconds: result.durationSeconds,
      );
      final styleFitScore = styleConfig.scoreStyleFit(
        coordinates: result.coordinates,
        distanceKm: styleDistanceKm,
        durationSeconds: result.durationSeconds,
      );
      meta['selected_style'] = selectedStyle;
      meta['style_fit_score'] = double.parse(styleFitScore.toStringAsFixed(1));
      meta['style_fit_reasons'] = styleConfig.styleFitReasons(styleMetrics);
      meta['style_metrics'] = styleMetrics.toJson();
      meta['curve_density_per_km'] = styleMetrics
          .toJson()['curve_density_per_km'];
      meta['smoothness_score'] = styleMetrics.smoothnessScore;
      meta['zigzag_score'] = styleMetrics.microZigzagPercent;
      meta['sharp_turn_count'] = styleMetrics.sharpCurveDensityPer50Km;
    }
    if (generationDurationMs != null) {
      meta['generation_duration_ms'] = generationDurationMs;
    }
    meta['fallbackUsed'] =
        lastRouteRecentFallbackUsed ||
        lastRoutePersistentCacheFallbackUsed ||
        lastRouteDuplicateFallbackUsed ||
        lastRoutePoolFallbackUsed;
    meta['pool_distance_rule_applied'] = lastRoutePoolDistanceRuleApplied;
    meta['pool_rejected_too_far'] = lastRoutePoolRejectedTooFar;
    meta['access_leg_used'] = lastRouteAccessLegUsed;
    meta['access_leg_distance_km'] = lastRouteAccessLegDistanceKm;
    meta['dead_end_spike_detected'] = RouteQualityValidator.detectDeadEndSpikes(
      result.coordinates,
    ).isNotEmpty;
    meta['mapboxCallCount'] = lastRouteApiCallCount;
    meta['mapbox_call_count'] = lastRouteApiCallCount;
    meta['liveGenerationCostUnits'] = lastRouteApiCallCount;
    meta['subscriptionTier'] = lastRouteSubscriptionTier;
    meta['route_fingerprint'] = lastRouteDebugFingerprint;
    meta['similarity_to_previous_percent'] =
        lastRouteSimilarityToPreviousPercent;
    meta['pool_route_id'] = lastRoutePoolMatchId;
    meta['coverage_status'] = lastRouteCoverageStatus;
    meta['seed_job_created'] = lastRouteSeedJobCreated;
    meta['duplicate_job_prevented'] = lastRouteDuplicateSeedJobPrevented;
    meta['pool_bootstrap_pending'] = lastRoutePoolBootstrapPending;
    meta['region_difficulty'] = lastRouteRegionDifficulty;
    meta['hard_region_status'] = lastRouteHardRegionStatus;
    meta['chosen_cluster'] = lastRouteChosenCluster;
    meta['candidate_inserted'] = lastRouteCandidateInserted;
    meta['verified_inserted'] = lastRouteVerifiedInserted;
    final existingOrchestration = meta['orchestration'] is Map
        ? Map<String, dynamic>.from(meta['orchestration'] as Map)
        : <String, dynamic>{};
    meta['orchestration'] = {
      ...existingOrchestration,
      'source': lastRouteGenerationSource,
      'generation_duration_ms': generationDurationMs,
      'quality_tier': meta['quality_tier'],
      'selected_style': meta['selected_style'],
      'style_fit_score': meta['style_fit_score'],
      'style_fit_reasons': meta['style_fit_reasons'],
      'style_metrics': meta['style_metrics'],
      'prepared_buffer_hit': lastRoutePreparedBufferHit,
      'prepared_buffer_used': lastRoutePreparedBufferUsed,
      'session_cache_hit': lastRouteSessionCacheHit,
      'pool_hit': lastRoutePoolFallbackUsed,
      'pool_used': lastRoutePoolFallbackUsed,
      'pool_match_id': lastRoutePoolMatchId,
      'pool_route_id': lastRoutePoolMatchId,
      'pool_radius_scope': lastRoutePoolMatchTier,
      'pool_start_distance_km': lastRoutePoolStartDistanceKm,
      'pool_distance_rule_applied': lastRoutePoolDistanceRuleApplied,
      'pool_rejected_too_far': lastRoutePoolRejectedTooFar,
      'access_leg_used': lastRouteAccessLegUsed,
      'access_leg_distance_km': lastRouteAccessLegDistanceKm,
      'dead_end_spike_detected': meta['dead_end_spike_detected'],
      'mapbox_attempt_count': lastRouteApiCallCount,
      'mapbox_call_count': lastRouteApiCallCount,
      'route_fingerprint': lastRouteDebugFingerprint,
      'similarity_to_previous_percent': lastRouteSimilarityToPreviousPercent,
      'subscription_tier': lastRouteSubscriptionTier,
      'coverage_status': lastRouteCoverageStatus,
      'seed_job_created': lastRouteSeedJobCreated,
      'duplicate_job_prevented': lastRouteDuplicateSeedJobPrevented,
      'pool_bootstrap_pending': lastRoutePoolBootstrapPending,
      'region_difficulty': lastRouteRegionDifficulty,
      'hard_region_status': lastRouteHardRegionStatus,
      'chosen_cluster': lastRouteChosenCluster,
      'candidate_inserted': lastRouteCandidateInserted,
      'verified_inserted': lastRouteVerifiedInserted,
      'fallback_reason': lastRoutePoolFallbackUsed ? 'mapbox_failed' : null,
    };
    return RouteResult(
      geoJson: result.geoJson,
      geometry: result.geometry,
      coordinates: result.coordinates,
      maneuvers: result.maneuvers,
      distanceMeters: result.distanceMeters,
      durationSeconds: result.durationSeconds,
      distanceKm: result.distanceKm,
      speedLimits: result.speedLimits,
      edgeMeta: meta,
    );
  }

  /// Wählt eine Entdecker-Richtung die sich von den letzten 3 unterscheidet.
  /// Persistiert die letzten Richtungen in SharedPreferences.
  static Future<double> _pickExplorerDirection(math.Random rng) async {
    final prefs = await SharedPreferences.getInstance();
    if (_recentExplorerBearings.isEmpty) {
      final stored = prefs.getStringList(_explorerBearingPrefsKey) ?? const [];
      for (final value in stored) {
        final parsed = double.tryParse(value);
        if (parsed != null && parsed.isFinite) {
          _recentExplorerBearings.add(parsed);
        }
      }
    }

    const maxAttempts = 20;
    const minAngleDiff = 60.0;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final candidate = rng.nextDouble() * 360;
      var tooClose = false;
      for (final prev in _recentExplorerBearings) {
        var delta = (candidate - prev).abs() % 360;
        if (delta > 180) delta = 360 - delta;
        if (delta < minAngleDiff) {
          tooClose = true;
          break;
        }
      }
      if (!tooClose) {
        await _storeExplorerDirection(prefs, candidate);
        return candidate;
      }
    }

    final fallback = rng.nextDouble() * 360;
    await _storeExplorerDirection(prefs, fallback);
    return fallback;
  }

  static Future<void> _storeExplorerDirection(
    SharedPreferences prefs,
    double direction,
  ) async {
    _recentExplorerBearings.add(direction);
    while (_recentExplorerBearings.length > 3) {
      _recentExplorerBearings.removeAt(0);
    }
    await prefs.setStringList(
      _explorerBearingPrefsKey,
      _recentExplorerBearings
          .map((value) => value.toStringAsFixed(1))
          .toList(growable: false),
    );
  }

  // ────────────────────── Icon / Text Helpers ────────────────────────────────

  IconData iconForManeuver(String type, String modifier) {
    final mod = modifier.toLowerCase().trim();
    final typ = type.toLowerCase().trim();

    // Kreisverkehr → eigenes Symbol
    if (typ == 'roundabout' || typ == 'rotary') {
      return Icons.roundabout_right;
    }

    // Ankunft / Ziel erreicht
    if (typ == 'arrive') return Icons.flag;
    if (typ == 'depart') return Icons.navigation;

    // Autobahn/Rampen
    if (typ == 'on ramp' || typ == 'off ramp') {
      if (mod.contains('left')) return Icons.ramp_left;
      if (mod.contains('right')) return Icons.ramp_right;
      return Icons.ramp_right;
    }

    // Zusammenführung (Merge)
    if (typ == 'merge') {
      if (mod.contains('left')) return Icons.merge;
      if (mod.contains('right')) return Icons.merge;
      return Icons.merge;
    }

    // Gabelung (Fork)
    if (typ == 'fork') {
      if (mod.contains('left')) return Icons.fork_left;
      if (mod.contains('right')) return Icons.fork_right;
      return Icons.fork_right;
    }

    // Straßenende — MUSS abbiegen (wie eine Kreuzung)
    if (typ == 'end of road') {
      if (mod.contains('left')) return Icons.turn_left;
      if (mod.contains('right')) return Icons.turn_right;
      return Icons.turn_left;
    }

    // Geradeaus-Typen (Straßennamenwechsel, Weiterfahrt)
    // Bei echten Richtungsänderungen trotzdem das richtige Abbiegesymbol zeigen
    if (typ == 'new name' || typ == 'continue' || typ == 'notification') {
      if (mod == 'sharp left') return Icons.turn_sharp_left;
      if (mod == 'sharp right') return Icons.turn_sharp_right;
      if (mod == 'left') return Icons.turn_left;
      if (mod == 'right') return Icons.turn_right;
      if (mod == 'slight left') return Icons.turn_slight_left;
      if (mod == 'slight right') return Icons.turn_slight_right;
      return Icons.straight;
    }

    // Richtungs-Modifier (Standard-Abbiegemanöver)
    switch (mod) {
      case 'left':
        return Icons.turn_left;
      case 'slight left':
        return Icons.turn_slight_left;
      case 'sharp left':
        return Icons.turn_sharp_left;
      case 'right':
        return Icons.turn_right;
      case 'slight right':
        return Icons.turn_slight_right;
      case 'sharp right':
        return Icons.turn_sharp_right;
      case 'uturn':
      case 'uturn left':
        return Icons.u_turn_left;
      case 'uturn right':
        return Icons.u_turn_right;
      case 'straight':
        return Icons.straight;
      default:
        return Icons.straight;
    }
  }

  /// Formatiert Distanz lesbar (z.B. 6385m → 6,4 km)
  String formatDistance(double meters) {
    if (meters >= 1000) {
      return 'In ${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
    } else {
      return 'In ${meters.toInt()} m';
    }
  }

  /// Gibt den deutschen Richtungstext für einen Modifier zurück.
  String directionText(String modifier) {
    switch (modifier.toLowerCase().trim()) {
      case 'left':
        return 'Links';
      case 'slight left':
        return 'Leicht links';
      case 'sharp left':
        return 'Scharf links';
      case 'right':
        return 'Rechts';
      case 'slight right':
        return 'Leicht rechts';
      case 'sharp right':
        return 'Scharf rechts';
      default:
        return 'Weiter';
    }
  }

  String _roundaboutInstruction(
    int? exitNumber,
    String rawInstruction,
    String modifier,
  ) {
    if (exitNumber != null && exitNumber > 0) {
      final ordinal = _exitOrdinal(exitNumber);
      return 'Im Kreisverkehr $ordinal Ausfahrt nehmen';
    }
    final normalized = _normalizeInstruction(rawInstruction, modifier);
    if (normalized.toLowerCase().contains('kreisverkehr')) return normalized;
    return 'Im Kreisverkehr weiterfahren';
  }

  String _exitOrdinal(int exit) {
    switch (exit) {
      case 1:
        return '1.';
      case 2:
        return '2.';
      case 3:
        return '3.';
      case 4:
        return '4.';
      case 5:
        return '5.';
      default:
        return '$exit.';
    }
  }

  String _announcementForModifier(
    String modifier, {
    double? distance,
    String type = '',
  }) {
    final distText = distance != null ? formatDistance(distance) : 'In 100 m';
    final mod = modifier.toLowerCase();
    final typ = type.toLowerCase();

    // Straßenende
    if (typ == 'end of road') {
      if (mod.contains('left')) {
        return '$distText links abbiegen (Straßenende).';
      }
      return '$distText rechts abbiegen (Straßenende).';
    }
    // Autobahnausfahrt
    if (typ == 'off ramp') {
      if (mod.contains('left')) return '$distText Ausfahrt links nehmen';
      return '$distText Ausfahrt rechts nehmen';
    }
    // Autobahnauffahrt
    if (typ == 'on ramp') {
      if (mod.contains('left')) return '$distText Auffahrt links nehmen';
      return '$distText Auffahrt rechts nehmen';
    }
    // Gabelung
    if (typ == 'fork') {
      if (mod.contains('left')) return '$distText links halten';
      return '$distText rechts halten';
    }
    // Zusammenführung
    if (typ == 'merge') {
      return '$distText einfädeln';
    }
    // Ankunft
    if (typ == 'arrive') {
      return 'Ziel erreicht.';
    }

    switch (mod) {
      case 'left':
        return '$distText nach Links abbiegen.';
      case 'slight left':
        return '$distText leicht links abbiegen.';
      case 'sharp left':
        return '$distText scharf links abbiegen.';
      case 'right':
        return '$distText nach Rechts abbiegen.';
      case 'slight right':
        return '$distText leicht rechts abbiegen.';
      case 'sharp right':
        return '$distText scharf rechts abbiegen.';
      case 'uturn':
      case 'uturn left':
      case 'uturn right':
        return '$distText bitte wenden.';
      default:
        return '$distText geradeaus weiterfahren.';
    }
  }

  String _normalizeInstruction(String instruction, String modifier) {
    final trimmed = instruction.trim();
    if (trimmed.isEmpty) return _announcementForModifier(modifier);
    return _translateToGerman(trimmed);
  }

  /// Übersetzt englische Navigationsanweisungen ins Deutsche (sequenziell, kein early return)
  String _translateToGerman(String instruction) {
    var r = instruction;

    // Kreisverkehr (vor generischen "enter"/"exit" erkennen)
    r = r.replaceAll(
      RegExp(
        r'\benter (?:the )?(?:roundabout|traffic circle|rotary)\b',
        caseSensitive: false,
      ),
      'In den Kreisverkehr einfahren',
    );
    r = r.replaceAll(
      RegExp(
        r'\bexit (?:the )?(?:roundabout|traffic circle|rotary)\b',
        caseSensitive: false,
      ),
      'Kreisverkehr verlassen',
    );

    // Abbiegungen — Reihenfolge wichtig: spezifischere Muster zuerst
    r = r.replaceAll(
      RegExp(r'\bturn sharp left\b', caseSensitive: false),
      'Scharf links abbiegen',
    );
    r = r.replaceAll(
      RegExp(r'\bturn sharp right\b', caseSensitive: false),
      'Scharf rechts abbiegen',
    );
    r = r.replaceAll(
      RegExp(r'\bturn slight(?:ly)? left\b', caseSensitive: false),
      'Leicht links abbiegen',
    );
    r = r.replaceAll(
      RegExp(r'\bturn slight(?:ly)? right\b', caseSensitive: false),
      'Leicht rechts abbiegen',
    );
    r = r.replaceAll(
      RegExp(r'\bturn left\b', caseSensitive: false),
      'Links abbiegen',
    );
    r = r.replaceAll(
      RegExp(r'\bturn right\b', caseSensitive: false),
      'Rechts abbiegen',
    );
    r = r.replaceAll(RegExp(r'\buturn\b', caseSensitive: false), 'Wenden');

    // Halten
    r = r.replaceAll(
      RegExp(r'\bbear left\b', caseSensitive: false),
      'Links halten',
    );
    r = r.replaceAll(
      RegExp(r'\bbear right\b', caseSensitive: false),
      'Rechts halten',
    );
    r = r.replaceAll(
      RegExp(r'\bkeep left\b', caseSensitive: false),
      'Links halten',
    );
    r = r.replaceAll(
      RegExp(r'\bkeep right\b', caseSensitive: false),
      'Rechts halten',
    );
    r = r.replaceAll(
      RegExp(r'\bkeep (?:straight|going)\b', caseSensitive: false),
      'Geradeaus weiterfahren',
    );

    // Geradeaus / Starten
    r = r.replaceAll(
      RegExp(
        r'\bhead (?:north|south|east|west|northwest|northeast|southwest|southeast)\b',
        caseSensitive: false,
      ),
      'Geradeaus fahren',
    );
    r = r.replaceAll(
      RegExp(r'\bcontinue\b', caseSensitive: false),
      'Weiterfahren',
    );

    // Ausfahrten
    r = r.replaceAll(
      RegExp(r'\btake the \w+ (?:exit|ramp)\b', caseSensitive: false),
      'Ausfahrt nehmen',
    );
    r = r.replaceAll(
      RegExp(r'\btake (?:the )?exit\b', caseSensitive: false),
      'Ausfahrt nehmen',
    );

    // Auffahren / Abfahren
    r = r.replaceAll(
      RegExp(r'\bmerge (?:onto|into)\b', caseSensitive: false),
      'Auffahren auf',
    );
    r = r.replaceAll(
      RegExp(r'\bexit (?:onto|to)\b', caseSensitive: false),
      'Abfahrt auf',
    );

    // Ziel
    r = r.replaceAll(
      RegExp(
        r'\b(?:you have arrived|arrive at|destination)\b',
        caseSensitive: false,
      ),
      'Ziel erreicht',
    );

    // Englische Verbindungswörter — zuletzt, nach allen längeren Mustern
    r = r.replaceAll(RegExp(r'\bonto\b', caseSensitive: false), 'auf');
    r = r.replaceAll(RegExp(r'\btoward\b', caseSensitive: false), 'Richtung');
    r = r.replaceAll(RegExp(r'\bvia\b', caseSensitive: false), 'über');

    return r;
  }

  /// Extrahiert Tempolimits aus den Mapbox-Route-Legs/Steps.
  /// Mapbox liefert `maxspeed` pro Annotation oder `speed_limit` pro Step.
  List<SpeedLimitSegment> _extractSpeedLimits(
    Map<dynamic, dynamic> data,
    List<List<double>> coordinates,
  ) {
    final segments = <SpeedLimitSegment>[];
    try {
      final route = data['route'] as Map?;
      final legs = route?['legs'] as List?;
      if (legs == null) return segments;

      int coordIndex = 0;
      for (final leg in legs) {
        if (leg is! Map) continue;
        // Annotations-basiert (genauer)
        final annotation = leg['annotation'] as Map?;
        final maxspeeds = annotation?['maxspeed'] as List?;
        if (maxspeeds != null && maxspeeds.isNotEmpty) {
          for (var i = 0; i < maxspeeds.length; i++) {
            final ms = maxspeeds[i];
            if (ms is Map && ms['speed'] != null) {
              final speed = (ms['speed'] as num).toInt();
              final unit = ms['unit'] as String? ?? 'km/h';
              final speedKmh = unit == 'mph'
                  ? (speed * 1.60934).round()
                  : speed;
              segments.add(
                SpeedLimitSegment(
                  startIndex: coordIndex + i,
                  endIndex: coordIndex + i + 1,
                  speedKmh: speedKmh,
                ),
              );
            }
          }
        }
        // Steps-basiert als Fallback
        final steps = leg['steps'] as List?;
        if (steps != null && maxspeeds == null) {
          for (final step in steps) {
            if (step is! Map) continue;
            final speedLimit = step['speed_limit'] as num?;
            final stepGeometry = step['geometry'] as Map?;
            final stepCoords = stepGeometry?['coordinates'] as List?;
            final stepLen = stepCoords?.length ?? 1;
            if (speedLimit != null && speedLimit > 0) {
              segments.add(
                SpeedLimitSegment(
                  startIndex: coordIndex,
                  endIndex: coordIndex + stepLen,
                  speedKmh: speedLimit.toInt(),
                ),
              );
            }
            coordIndex += stepLen > 1 ? stepLen - 1 : 1;
          }
        }
      }
    } catch (e) {
      debugPrint('[RouteService] Speed-Limit-Extraktion fehlgeschlagen: $e');
    }
    return segments;
  }

  String _announcementFromInstruction(
    String instruction,
    String modifier,
    double distance, {
    String type = '',
  }) {
    // Für spezielle Typen (Rampe, Arrive, Fork etc.) den typbasierten Text nutzen
    if (type.isNotEmpty && type != 'turn') {
      final typeBased = _announcementForModifier(
        modifier,
        distance: distance,
        type: type,
      );
      if (!typeBased.contains('geradeaus')) return typeBased;
    }
    return '${formatDistance(distance)} ${_normalizeInstruction(instruction, modifier)}';
  }

  // ─────────────────────── Route Snapping ───────────────────────────────────

  /// Snappt Start (und Rundkurs-Ende) auf die exakte GPS-Position und
  /// entfernt die Anfangs-Schleife die Mapbox manchmal erzeugt.
  RouteResult _snapRouteToStartPosition(
    RouteResult result,
    geo.Position startPosition,
  ) {
    if (result.coordinates.isEmpty) return result;

    final startLng = startPosition.longitude;
    final startLat = startPosition.latitude;
    var coords = List<List<double>>.from(result.coordinates);

    // ── Anfangs-Haken/Schleife entfernen ─────────────────────────────────────
    // Mapbox erzeugt manchmal einen Haken: Route geht kurz weg, dreht um,
    // kommt zurück zum Startbereich und fährt dann in die richtige Richtung.
    // Erkennung: Nach einem Abstand von ≥100 m sinkt die Distanz wieder auf <80 m.
    // Wir trimmen bis zum letzten solchen Rückkehr-Punkt.
    final searchEnd = (coords.length * 0.20).round().clamp(5, 200);

    // Größten Abstand vom Start in der Suchzone finden
    var maxDist = 0.0;
    var maxDistIdx = 0;
    for (var i = 0; i < searchEnd; i++) {
      final d = geo.Geolocator.distanceBetween(
        startLat,
        startLng,
        coords[i][1],
        coords[i][0],
      );
      if (d > maxDist) {
        maxDist = d;
        maxDistIdx = i;
      }
    }

    var trimTo = 0;
    if (maxDist > 100.0) {
      // Route hat sich ≥100 m entfernt — prüfe ob sie danach zurückkommt
      for (var i = maxDistIdx; i < searchEnd; i++) {
        final d = geo.Geolocator.distanceBetween(
          startLat,
          startLng,
          coords[i][1],
          coords[i][0],
        );
        if (d < 80.0) trimTo = i; // Rückkehr zum Startbereich
      }
    } else {
      // Fallback: alter Algorithmus für sehr kurze Ausreißer (<100 m)
      for (var i = 1; i < searchEnd; i++) {
        final d = geo.Geolocator.distanceBetween(
          startLat,
          startLng,
          coords[i][1],
          coords[i][0],
        );
        if (d < 35.0) trimTo = i;
      }
    }
    if (trimTo > 0) {
      final trimmedCoords = coords.sublist(trimTo);
      final originalDistanceMeters =
          result.distanceMeters ?? _measurePathDistanceMeters(coords);
      final trimmedDistanceMeters = _measurePathDistanceMeters(trimmedCoords);
      final trimmedRatio = originalDistanceMeters > 0
          ? trimmedDistanceMeters / originalDistanceMeters
          : 1.0;
      final removedPointRatio = trimTo / coords.length;
      if (trimmedRatio >= 0.72 || removedPointRatio <= 0.08) {
        coords = trimmedCoords;
      } else {
        debugPrint(
          '[RouteService] Start-Hook-Trim übersprungen: würde ${(trimmedRatio * 100).toStringAsFixed(0)}% Distanz übrig lassen '
          'bei ${(removedPointRatio * 100).toStringAsFixed(0)}% entfernten Punkten',
        );
      }
    }
    if (coords.isEmpty) return result;

    // ── Startpunkt: Mapbox-Snap auf Straße beibehalten ────────────────────────
    // Wir setzen den Start NICHT auf die exakte GPS-Position, da diese
    // in einem Gebäude/Parkplatz liegen kann. Mapbox hat den Start bereits
    // auf die nächste Straße gesnappt — das behalten wir bei.
    // Nur bei sehr kurzer Distanz (<30m) auf GPS-Position überschreiben.
    final distToFirstPoint = geo.Geolocator.distanceBetween(
      startLat,
      startLng,
      coords[0][1],
      coords[0][0],
    );
    if (distToFirstPoint < 30) {
      coords[0] = [startLng, startLat];
    }

    // ── Rundkurs: letzten Punkt nur setzen wenn nah genug an der Straße ───────
    if (coords.length > 1) {
      final last = coords.last;
      final d = geo.Geolocator.distanceBetween(
        startLat,
        startLng,
        last[1],
        last[0],
      );
      // Nur auf GPS-Position setzen wenn <30m (= User steht auf der Straße)
      if (d < 30) coords.last = [startLng, startLat];
    }

    final coordsBeforeLoopFix = List<List<double>>.from(coords);

    // ── Selbstschneidende Schleifen aus der Route entfernen ───────────────────
    // Sicherheitscheck: Loop-Entfernung darf maximal 30% der Punkte entfernen.
    // Mehr = Route wird zerstört (besonders in Stadtgebieten mit vielen Kreuzungen).
    final coordsBefore = coords.length;
    final coordsAfterLoops = _removeRouteLoops(coords);
    final removedPercent = 1.0 - (coordsAfterLoops.length / coordsBefore);
    if (removedPercent <= 0.30) {
      coords = coordsAfterLoops;
      debugPrint(
        '[RouteService] Loop-Fix: ${coordsBefore - coords.length} Punkte entfernt (${(removedPercent * 100).toStringAsFixed(0)}%)',
      );
    } else {
      debugPrint(
        '[RouteService] Loop-Fix ÜBERSPRUNGEN: würde ${(removedPercent * 100).toStringAsFixed(0)}% der Route entfernen (${coordsBefore - coordsAfterLoops.length} von $coordsBefore Punkten)',
      );
    }

    // ── Distanz & Dauer aus den BEREINIGTEN Koordinaten neu berechnen ─────
    // Nach Snapping + Loop-Removal können die Koordinaten deutlich kürzer sein
    // als die originale Mapbox-Distanz. Ohne Neuberechnung zeigt die App z.B.
    // 40 km an obwohl die bereinigte Route nur 6 km lang ist.
    double actualDistanceMeters = _measurePathDistanceMeters(coords);

    // Sicherheitscheck: Wenn die Loop-Bereinigung zu viel Distanz wegnimmt,
    // behalten wir den vor der Loop-Bereinigung gesnappten Zustand.
    final origDist = result.distanceMeters ?? actualDistanceMeters;
    final distRatio = origDist > 0 ? actualDistanceMeters / origDist : 1.0;
    final hasTrustedQualityMeta = result.edgeMeta['quality_tier'] != null;
    final shouldPreserveProviderDistance =
        !hasTrustedQualityMeta &&
        result.distanceMeters != null &&
        result.distanceMeters! > 0 &&
        actualDistanceMeters / result.distanceMeters! < 0.55;

    final double finalDistanceMeters;
    final double? finalDuration;
    if (shouldPreserveProviderDistance) {
      debugPrint(
        '[RouteService] Snap/Loop-Fix Legacy-Fallback: behalte Provider-Distanz ${(result.distanceMeters! / 1000).toStringAsFixed(1)} km '
        'statt ${(actualDistanceMeters / 1000).toStringAsFixed(1)} km ohne Quality-Meta',
      );
      finalDistanceMeters = result.distanceMeters!.toDouble();
      finalDuration = result.durationSeconds;
    } else if (distRatio < 0.78 && origDist > 10000) {
      coords = coordsBeforeLoopFix;
      actualDistanceMeters = _measurePathDistanceMeters(coords);
      debugPrint(
        '[RouteService] Snap/Loop-Fix WARNUNG: Distanz fiel auf ${(distRatio * 100).toStringAsFixed(0)}% — verwerfe Loop-Bereinigung und behalte gesnappten Vorzustand (${(actualDistanceMeters / 1000).toStringAsFixed(1)} km)',
      );
      finalDistanceMeters = actualDistanceMeters;
      finalDuration = result.durationSeconds;
    } else {
      finalDistanceMeters = actualDistanceMeters;
      final adjustedDuration = (result.durationSeconds ?? 0) * distRatio;
      finalDuration = adjustedDuration > 0
          ? adjustedDuration
          : result.durationSeconds;
      debugPrint(
        '[RouteService] Snap/Loop-Fix: ${origDist.round()}m → ${actualDistanceMeters.round()}m '
        '(${(actualDistanceMeters / 1000).toStringAsFixed(1)} km, ratio: ${distRatio.toStringAsFixed(2)})',
      );
    }

    // ── Maneuver-Indices komplett neu berechnen (nach allen Koordinaten-Änderungen) ─
    // Statt Offset-Korrektur: lat/lng-Position des Maneuvers in neuen Koordinaten suchen.
    final finalManeuvers = result.maneuvers
        .map(
          (m) => RouteManeuver(
            latitude: m.latitude,
            longitude: m.longitude,
            routeIndex: _findNearestIndex(m.latitude, m.longitude, coords),
            icon: m.icon,
            announcement: m.announcement,
            instruction: m.instruction,
          ),
        )
        .toList();

    final newGeometry = Map<String, dynamic>.from(result.geometry);
    newGeometry['coordinates'] = coords;

    return RouteResult(
      geoJson: json.encode(newGeometry),
      geometry: newGeometry,
      coordinates: coords,
      maneuvers: finalManeuvers,
      distanceMeters: finalDistanceMeters,
      durationSeconds: finalDuration,
      distanceKm: finalDistanceMeters / 1000.0,
      speedLimits: result.speedLimits,
      edgeMeta: result.edgeMeta,
    );
  }

  double _measurePathDistanceMeters(List<List<double>> coords) {
    var distanceMeters = 0.0;
    for (var i = 0; i < coords.length - 1; i++) {
      distanceMeters += geo.Geolocator.distanceBetween(
        coords[i][1],
        coords[i][0],
        coords[i + 1][1],
        coords[i + 1][0],
      );
    }
    return distanceMeters;
  }

  /// Entfernt Schleifen (Loops) aus einer Route.
  ///
  /// Erkennt eine Schleife wenn:
  ///   1. Direktabstand zwischen Punkt j und i < 60 m
  ///   2. Weglänge j→i ist > 4× der Direktdistanz (echter Umweg)
  ///   3. Weglänge j→i < 1200 m (lokale Schleife, kein legitimer Umweg)
  ///
  /// WICHTIG: Entfernt nur den Loop-Abschnitt (j+1 bis i-1).
  /// Punkt j und i liegen beide auf der originalen Straßengeometrie,
  /// daher entsteht KEINE Luftlinie/Abkürzung durch Gelände.
  List<List<double>> _removeRouteLoops(List<List<double>> coords) {
    if (coords.length < 10) return coords;

    final cum = <double>[0.0];
    for (var i = 1; i < coords.length; i++) {
      cum.add(
        cum.last +
            geo.Geolocator.distanceBetween(
              coords[i - 1][1],
              coords[i - 1][0],
              coords[i][1],
              coords[i][0],
            ),
      );
    }

    // Letzten 15 % nicht scannen — Rundkurs endet legitim nah am Start
    final safeEnd = (coords.length * 0.85).round().clamp(10, coords.length);

    for (var i = 10; i < safeEnd; i++) {
      final lookBack = math.max(0, i - 300);
      for (var j = lookBack; j < i - 8; j++) {
        final directDist = geo.Geolocator.distanceBetween(
          coords[i][1],
          coords[i][0],
          coords[j][1],
          coords[j][0],
        );
        if (directDist > 60.0) continue;

        final pathLen = cum[i] - cum[j];
        if (pathLen < directDist * 4.0) continue;
        if (pathLen > 1200) continue;

        // Loop gefunden: Punkte j+1 bis i-1 sind der Umweg.
        // Wir verbinden j direkt mit i — beide liegen auf der Originalstraße.
        final shortened = [...coords.sublist(0, j + 1), ...coords.sublist(i)];
        debugPrint(
          '[RouteService] Loop entfernt: ${i - j} Punkte, ${pathLen.toStringAsFixed(0)}m Umweg',
        );
        return _removeRouteLoops(shortened);
      }
    }
    return coords;
  }
}

class _RouteCandidate {
  const _RouteCandidate({
    required this.route,
    required this.variant,
    required this.fingerprint,
    required this.sampledCoordinates,
    required this.score,
    required this.accepted,
    required this.hardRejected,
    required this.tier,
    required this.isIdeal,
    required this.isGood,
    required this.styleFitScore,
    required this.tooSimilar,
    required this.novelEnough,
  });

  final RouteResult route;
  final RouteVariant variant;
  final String fingerprint;
  final List<List<double>> sampledCoordinates;
  final double score;
  final bool accepted;
  final bool hardRejected;
  final RouteQualityTier tier;
  final bool isIdeal;
  final bool isGood;
  final double styleFitScore;
  final bool tooSimilar;
  final bool novelEnough;
}

class _ScoredPoolAccessRoute {
  const _ScoredPoolAccessRoute({
    required this.route,
    required this.score,
    required this.accessLegUsed,
    required this.accessLegDistanceKm,
  });

  final RouteResult route;
  final double score;
  final bool accessLegUsed;
  final double? accessLegDistanceKm;
}

enum RouteErrorType {
  network,
  auth,
  validation,
  rateLimit,
  workerLimit,
  server,
  noRoute,
  emptyResponse,
  parsing,
  quality,
  unknown,
}

class RouteServiceException implements Exception {
  const RouteServiceException({
    required this.type,
    required this.userMessage,
    required this.debugMessage,
    this.statusCode,
    this.stackTrace,
    this.edgeMeta = const {},
  });

  final RouteErrorType type;
  final String userMessage;
  final String debugMessage;
  final int? statusCode;
  final StackTrace? stackTrace;
  final Map<String, dynamic> edgeMeta;

  @override
  String toString() {
    return 'RouteServiceException(type=$type, status=$statusCode, debug=$debugMessage)';
  }
}

// ─────────────────────── Navigation Helpers ────────────────────────────────
// Reine Berechnungsfunktionen ohne Klassen-Overhead.

/// Berechnet den Lagerwinkel (Bearing) zwischen zwei Koordinaten in Grad.
double calculateBearing(
  double startLat,
  double startLon,
  double endLat,
  double endLon,
) {
  final startLatRad = startLat * math.pi / 180;
  final endLatRad = endLat * math.pi / 180;
  final dLonRad = (endLon - startLon) * math.pi / 180;
  final y = math.sin(dLonRad) * math.cos(endLatRad);
  final x =
      math.cos(startLatRad) * math.sin(endLatRad) -
      math.sin(startLatRad) * math.cos(endLatRad) * math.cos(dLonRad);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Sucht den nächsten Routenpunkt im Suchfenster ab dem aktuellen Index.
RouteWindowMatch findNearestInWindow({
  required geo.Position position,
  required List<List<double>> coordinates,
  required int currentIndex,
  int windowSize = 20,
  double maxJumpMeters = 45.0,
}) {
  if (coordinates.isEmpty) {
    return const RouteWindowMatch(index: 0, distanceMeters: double.infinity);
  }

  final start = currentIndex.clamp(0, coordinates.length - 1);
  final end = math.min(start + windowSize, coordinates.length - 1);

  var nearestIndex = start;
  var nearestDistance = double.infinity;

  for (var i = start; i <= end; i++) {
    final c = coordinates[i];
    if (c.length < 2) continue;
    final d = geo.Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      c[1],
      c[0],
    );
    if (d < nearestDistance) {
      nearestDistance = d;
      nearestIndex = i;
    }
  }

  // Wenn das Match weit weg von der Route liegt, den Index nicht nach vorne
  // springen lassen. Distanz bleibt erhalten für Off-Route-Erkennung.
  if (nearestDistance > maxJumpMeters) {
    return RouteWindowMatch(index: start, distanceMeters: nearestDistance);
  }

  return RouteWindowMatch(index: nearestIndex, distanceMeters: nearestDistance);
}
