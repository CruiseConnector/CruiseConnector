import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show compute, kDebugMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
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
    return response;
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
  static bool lastRoutePoolExactBucketMissing = false;
  static bool lastRouteAlternativeDistanceOffered = false;
  static int lastRoutePoolCandidateCount = 0;
  static int lastRoutePoolSeenCandidateCount = 0;
  static bool lastRouteDuplicateSkipped = false;
  static String? lastRouteSourceDecision;
  static String? lastRouteLiveAttemptReason;
  static String? lastRoutePoolUsedReason;
  static List<String> lastRoutePreviousFingerprints = const [];
  static int? lastRouteRequestedDistanceBucket;
  static int? lastRouteReturnedDistanceBucket;
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
  static bool lastRouteCandidateSaveFailed = false;
  static bool lastRouteCandidateDuplicateFingerprint = false;
  static String? lastRouteCandidateDuplicateSource;
  static bool lastRouteCandidateCoverageRefreshFailed = false;
  static String? lastRouteCandidateSaveErrorType;
  static String? lastRouteCandidateSaveErrorCode;
  static String? lastRouteCandidateSaveErrorReason;
  static String? lastRouteCandidateSaveSkippedReason;
  static bool lastRouteTemporaryCandidate = false;
  static bool lastRouteHardRegionExplorationUsed = false;
  static bool lastRouteMovingStartDetected = false;
  static String? lastRouteStartSnapStrategy;
  static bool? lastRouteStartOnMotorway;
  static double? lastRouteAvoidManeuverRadiusUsed;

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
  Map<String, dynamic>? _lastRoundTripSearchSessionMeta;

  Map<String, dynamic>? get lastRoundTripSearchSessionMeta =>
      _lastRoundTripSearchSessionMeta == null
      ? null
      : Map<String, dynamic>.from(_lastRoundTripSearchSessionMeta!);
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
    lastRoutePoolExactBucketMissing = false;
    lastRouteAlternativeDistanceOffered = false;
    lastRoutePoolCandidateCount = 0;
    lastRoutePoolSeenCandidateCount = 0;
    lastRouteDuplicateSkipped = false;
    lastRouteSourceDecision = null;
    lastRouteLiveAttemptReason = null;
    lastRoutePoolUsedReason = null;
    lastRoutePreviousFingerprints = const [];
    lastRouteRequestedDistanceBucket = null;
    lastRouteReturnedDistanceBucket = null;
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
    lastRouteCandidateSaveFailed = false;
    lastRouteCandidateDuplicateFingerprint = false;
    lastRouteCandidateDuplicateSource = null;
    lastRouteCandidateCoverageRefreshFailed = false;
    lastRouteCandidateSaveErrorType = null;
    lastRouteCandidateSaveErrorCode = null;
    lastRouteCandidateSaveErrorReason = null;
    lastRouteCandidateSaveSkippedReason = null;
    lastRouteTemporaryCandidate = false;
    lastRouteHardRegionExplorationUsed = false;
    lastRouteMovingStartDetected = false;
    lastRouteStartSnapStrategy = null;
    lastRouteStartOnMotorway = null;
    lastRouteAvoidManeuverRadiusUsed = null;
  }

  static void _debugRouteSearch(String message) {
    if (!kDebugMode) return;
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
    List<Map<String, double>>? userWaypoints,
    int? variantIndex,
    bool avoidHighways = false,
    bool forceFreshVariant = false,
    String? waypointOrigin,
    int? waypointSeedAttempt,
    String debugTrigger = 'unknown',
    String subscriptionTier = 'premium',
  }) async {
    final styleConfig = RouteStyleConfig.forMode(mode);
    final isWaypointRequiredRoundTrip = planningType == 'Wegpunkte';
    final effectivePlanningType = planningType;
    final normalizedUserWaypoints = _normalizeUserWaypoints(userWaypoints);
    final normalizedTargetKm = styleConfig.clampRoundTripDistanceKm(
      targetDistanceKm,
    );
    final waypointValidationError = isWaypointRequiredRoundTrip
        ? _validateRequiredWaypoints(
            startPosition: startPosition,
            waypoints: normalizedUserWaypoints,
            targetDistanceKm: normalizedTargetKm,
          )
        : null;
    if (waypointValidationError != null) {
      throw waypointValidationError;
    }
    final waypointSignature = isWaypointRequiredRoundTrip
        ? _buildWaypointSignature(normalizedUserWaypoints)
        : null;
    final scenario = RouteScenario(
      routeType: 'ROUND_TRIP',
      startLatitude: startPosition.latitude,
      startLongitude: startPosition.longitude,
      style: mode,
      planningType: effectivePlanningType,
      targetDistanceKm: normalizedTargetKm.toDouble(),
      avoidHighways: avoidHighways,
      waypointSignature: waypointSignature,
      closeLoop: isWaypointRequiredRoundTrip,
    );
    var poolHealingFirstPolicy = isWaypointRequiredRoundTrip
        ? false
        : _usePoolHealingFirstForRoundTrip(scenario);
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
      'userWaypointCount=${normalizedUserWaypoints.length} '
      'waypointSignature=${waypointSignature ?? 'none'} '
      'poolHealingFirst=$poolHealingFirstPolicy '
      'scenarioKey=${scenario.scenarioKey} noveltyKey=${scenario.noveltyKey}',
    );
    _activeScenarioKeyForDebug = scenario.scenarioKey;
    _activeForceFreshVariantForDebug = forceFreshVariant;
    _activeTriggerForDebug = debugTrigger;
    lastRouteSourceDecision = poolHealingFirstPolicy
        ? 'hybrid_short_no_highway'
        : 'live_first';
    lastRouteLiveAttemptReason = forceFreshVariant
        ? 'search_again_force_fresh'
        : 'initial_search';
    await SeenRouteRegistry.ensureLoaded();
    final allowDuplicateFallbackForThisSearch =
        forceFreshVariant && debugTrigger != 'settingsChanged';

    if (forceFreshVariant) {
      RouteGenerationCoordinator.suspendBackgroundPreparation();
      PreparedRouteBuffer.clearScenario(scenario.scenarioKey);
      _debugRouteSearch(
        '[Prepared] clearedForForceFresh=true scenarioKey=${scenario.scenarioKey}',
      );
    }

    // Stabiler Suffix statt Timestamp: rapid Double-Click auf "Erneut suchen"
    // dedupliziert auf einen einzigen Single-Flight statt parallele Edge-Calls
    // zu erzeugen — verhindert Mapbox-5xx-Flood unter Last.
    final singleFlightKey = forceFreshVariant
        ? '${scenario.scenarioKey}|sa'
        : scenario.scenarioKey;
    return RouteGenerationCoordinator.runSingleFlight(singleFlightKey, () async {
      if (isWaypointRequiredRoundTrip) {
        return _generateRequiredWaypointRoundTrip(
          scenario: scenario,
          styleConfig: styleConfig,
          startPosition: startPosition,
          targetLocation: targetLocation,
          userWaypoints: normalizedUserWaypoints,
          variantIndex: variantIndex,
          forceFreshVariant: forceFreshVariant,
          waypointOrigin: waypointOrigin,
          waypointSeedAttempt: waypointSeedAttempt,
          debugTrigger: debugTrigger,
        );
      }

      RoutePoolCoverageCheck? poolHealingCoverage;
      var onDemandLiveFill = false;

      if (_isFreeTier(lastRouteSubscriptionTier)) {
        lastRouteSourceDecision = 'pool_only_free';
        final freePoolRoute = await _tryRoutePoolFallback(
          scenario: scenario,
          styleConfig: styleConfig,
          userLat: startPosition.latitude,
          userLng: startPosition.longitude,
          fallbackReason: 'free_pool_only',
          allowDuplicateFallback: allowDuplicateFallbackForThisSearch,
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
        lastRouteSourceDecision = 'pool_first_basic';
        final basicPoolRoute = await _tryRoutePoolFallback(
          scenario: scenario,
          styleConfig: styleConfig,
          userLat: startPosition.latitude,
          userLng: startPosition.longitude,
          fallbackReason: 'pool_first_basic',
          allowDuplicateFallback: allowDuplicateFallbackForThisSearch,
        );
        if (basicPoolRoute != null) {
          return basicPoolRoute;
        }
        poolHealingCoverage = await _ensureCoverageBootstrapStatus(
          scenario: scenario,
          userLat: startPosition.latitude,
          userLng: startPosition.longitude,
          subscriptionTier: lastRouteSubscriptionTier,
          createSeedJob: true,
        );
        if (poolHealingCoverage == null) {
          poolHealingFirstPolicy = false;
        }
        if (poolHealingFirstPolicy &&
            poolHealingCoverage != null &&
            _shouldStopLiveForPoolHealingCoverage(poolHealingCoverage)) {
          if (_shouldAllowHardRegionLiveExploration(
            poolHealingCoverage,
            lastRouteSubscriptionTier,
          )) {
            poolHealingFirstPolicy = false;
            onDemandLiveFill = true;
            lastRouteHardRegionExplorationUsed = true;
            lastRouteSourceDecision = forceFreshVariant
                ? 'search_again_hard_region_live_exploration'
                : 'hard_region_live_exploration';
            lastRouteLiveAttemptReason = forceFreshVariant
                ? 'search_again_force_fresh'
                : 'hard_region_live_exploration';
          } else {
            throw await _buildCoverageWarmupException(
              scenario: scenario,
              coverage: poolHealingCoverage,
              lastError: null,
            );
          }
        }
        if (poolHealingFirstPolicy &&
            poolHealingCoverage != null &&
            _shouldUseOnDemandLiveFill(poolHealingCoverage)) {
          poolHealingFirstPolicy = false;
          onDemandLiveFill = true;
          lastRouteSourceDecision = forceFreshVariant
              ? 'search_again_on_demand_live_fill'
              : 'on_demand_live_fill';
          lastRouteLiveAttemptReason = forceFreshVariant
              ? 'search_again_force_fresh'
              : 'thin_pool_on_demand_live_fill';
        }
      }

      if (poolHealingFirstPolicy &&
          !_isFreeTier(lastRouteSubscriptionTier) &&
          !_isBasicTier(lastRouteSubscriptionTier)) {
        poolHealingCoverage = await _ensureCoverageBootstrapStatus(
          scenario: scenario,
          userLat: startPosition.latitude,
          userLng: startPosition.longitude,
          subscriptionTier: lastRouteSubscriptionTier,
          createSeedJob: true,
        );
        if (poolHealingCoverage == null) {
          poolHealingFirstPolicy = false;
        }
        if (poolHealingCoverage != null &&
            _shouldStopLiveForPoolHealingCoverage(poolHealingCoverage)) {
          lastRouteSourceDecision = 'coverage_block_pool_then_live';
          lastRouteLiveAttemptReason = 'coverage_status_requires_live_check';
          if (_shouldAllowHardRegionLiveExploration(
            poolHealingCoverage,
            lastRouteSubscriptionTier,
          )) {
            lastRouteHardRegionExplorationUsed = true;
            lastRouteSourceDecision = forceFreshVariant
                ? 'search_again_hard_region_live_exploration'
                : 'hard_region_live_exploration';
            lastRouteLiveAttemptReason = forceFreshVariant
                ? 'search_again_force_fresh'
                : 'hard_region_live_exploration';
          }
          final poolBlockedRoute = await _tryRoutePoolFallback(
            scenario: scenario,
            styleConfig: styleConfig,
            userLat: startPosition.latitude,
            userLng: startPosition.longitude,
            fallbackReason: 'live_blocked_by_coverage_status',
            allowDuplicateFallback: allowDuplicateFallbackForThisSearch,
          );
          if (poolBlockedRoute != null) {
            return poolBlockedRoute;
          }
          // Premium/Test: Coverage darf Warmup nicht vor den Live-Versuch
          // ziehen. Erst wenn Live und Pool scheitern, wird unten ein
          // Warmup/Healing-Status gebaut.
          poolHealingFirstPolicy = false;
          onDemandLiveFill = true;
        }
        if (poolHealingCoverage != null &&
            _shouldUseOnDemandLiveFill(poolHealingCoverage)) {
          poolHealingFirstPolicy = false;
          onDemandLiveFill = true;
          lastRouteSourceDecision = forceFreshVariant
              ? 'search_again_on_demand_live_fill'
              : 'on_demand_live_fill';
          lastRouteLiveAttemptReason = forceFreshVariant
              ? 'search_again_force_fresh'
              : 'thin_pool_on_demand_live_fill';
        }
        if (!forceFreshVariant && poolHealingCoverage?.poolHealthy == true) {
          lastRouteSourceDecision = 'healthy_pool_first';
          final healthyPoolRoute = await _tryRoutePoolFallback(
            scenario: scenario,
            styleConfig: styleConfig,
            userLat: startPosition.latitude,
            userLng: startPosition.longitude,
            fallbackReason: 'healthy_pool_first',
          );
          if (healthyPoolRoute != null) {
            return healthyPoolRoute;
          }
        }
        if (!onDemandLiveFill) {
          lastRouteSourceDecision = forceFreshVariant
              ? 'search_again_live_first'
              : 'live_first_pool_thin_or_unavailable';
          lastRouteLiveAttemptReason = forceFreshVariant
              ? 'search_again_force_fresh'
              : 'pool_not_healthy_enough';
        }
      }

      // Search Again überspringt den Pool-Probe-Schritt vorne weg: der User
      // hat explizit Variation angefordert, der Pool-Fallback hinter den
      // Live-Versuchen (siehe _tryRoutePoolFallback weiter unten) bleibt als
      // Sicherheitsnetz. Live darf 30-45s laufen, Pool kommt nur wenn live
      // wirklich nichts liefert.
      if (forceFreshVariant) {
        lastRouteSourceDecision = onDemandLiveFill
            ? lastRouteSourceDecision
            : 'search_again_live_first';
        lastRouteLiveAttemptReason = onDemandLiveFill
            ? lastRouteLiveAttemptReason
            : 'search_again_force_fresh';
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
      final liveBatchCount = _roundTripLiveBatchCount(scenario, styleConfig);
      // Client-Schleife: Erstsuche darf in schwierigen Szenarien mehr Seeds
      // testen. Sobald es aber bereits eine gute Route für dieselben Settings
      // gibt, reicht ein frischer Versuch; danach fällt die App schnell auf
      // die geprüfte Route zurück statt 30-45s in NO_ROUTE-Tails zu laufen.
      // Search Again bekommt einen Versuch mehr als die Erstsuche
      // (capped bei 5), damit der User explizit eine Variante erzwingen kann
      // ohne dass die Schleife einfach in den Pool/NO_ROUTE-Tail fällt.
      final regularMaxAttempts = poolHealingFirstPolicy
          ? 1
          : difficultScenario
          ? (hasSeenHistory ? 1 : 3)
          : (hasSeenHistory ? 1 : 2);
      final maxAttempts = forceFreshVariant
          ? math.min(regularMaxAttempts + 1, 5)
          : regularMaxAttempts;
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
          forceFreshVariant: forceFreshVariant,
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
            userWaypoints: normalizedUserWaypoints,
            variant: variant,
            forceFreshVariant: forceFreshVariant,
            debugTrigger: debugTrigger,
            // Hint an Edge Function: gibt strict/balanced/fallback je 2-3
            // Pläne (siehe declaredMaxPerPhase und reservedForLaterPhases
            // in der Edge Function). Constrained Suchen (Autobahn vermeiden,
            // Kurvenjagd in engen Tälern) bekommen +1 Plan, weil sie pro
            // Versuch ggf. einen relax-retry brauchen.
            candidateBudget: poolHealingFirstPolicy
                ? _poolHealingFirstCandidateBudget(scenario)
                : _roundTripCandidateBudget(scenario, styleConfig),
            roundTripBatchIndex: liveBatchCount <= 1
                ? 0
                : attempt % liveBatchCount,
            roundTripBatchCount: liveBatchCount,
          );
          if (candidate.accepted) {
            if (!candidate.novelEnough) {
              lastRouteDuplicateSkipped = true;
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
          if (_isSearchInProgressError(mapped)) {
            break;
          }
          if (_edgeLiveFillExhausted(mapped)) {
            break;
          }
          if (_isFatalStructuredError(mapped)) {
            break;
          }
        }
      }

      if (bestCandidate?.accepted == true) {
        final acceptedMapboxCandidate = bestCandidate!;
        lastRouteGenerationSource = 'mapbox';
        await _maybeRecordRoutePoolCandidate(
          scenario: scenario,
          route: acceptedMapboxCandidate.route,
          fingerprint: acceptedMapboxCandidate.fingerprint,
          tier: acceptedMapboxCandidate.tier,
          qualityScore: acceptedMapboxCandidate.score,
          subscriptionTier: lastRouteSubscriptionTier,
        );
        final finalized = _finalizeAndRemember(
          scenario: scenario,
          route: acceptedMapboxCandidate.route,
          sampledCoordinates: acceptedMapboxCandidate.sampledCoordinates,
          fingerprint: acceptedMapboxCandidate.fingerprint,
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

      if (lastError != null && _isFatalStructuredError(lastError)) {
        throw lastError;
      }

      final poolFallback = await _tryRoutePoolFallback(
        scenario: scenario,
        styleConfig: styleConfig,
        userLat: startPosition.latitude,
        userLng: startPosition.longitude,
        fallbackReason: lastError?.type.name ?? 'no_accepted_mapbox_route',
        allowDuplicateFallback: allowDuplicateFallbackForThisSearch,
      );
      if (poolFallback != null) {
        return poolFallback;
      }

      final highwayAllowedNoHighwayFallback =
          await _tryHighwayAllowedNoHighwayRoundTripFallback(
            scenario: scenario,
            styleConfig: styleConfig,
            startPosition: startPosition,
            targetLocation: targetLocation,
            userWaypoints: normalizedUserWaypoints,
            forceFreshVariant: forceFreshVariant,
            debugTrigger: debugTrigger,
          );
      if (highwayAllowedNoHighwayFallback != null) {
        return highwayAllowedNoHighwayFallback;
      }

      // Availability beats diversity: if every fresh attempt only failed the
      // novelty gate, return the best clean duplicate instead of surfacing a
      // no-route error. The route still passed the same quality gates.
      final allowDuplicateEmergencyFallback =
          allowDuplicateFallbackForThisSearch;
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

      final recentDuplicate = allowDuplicateFallbackForThisSearch
          ? (_recentDisplayedRoutes[_recentDisplayedKeyForScenario(scenario)] ??
                _recentSuccessfulRoutes[scenario.scenarioKey])
          : null;
      if (scenario.isRoundTrip &&
          recentDuplicate != null &&
          _shouldUseRecentFallbackRoute(
            recentDuplicate,
            scenario: scenario,
            lastError: lastError,
            requireNovelty: false,
          )) {
        lastRouteFromCache = true;
        lastRouteRecentFallbackUsed = true;
        lastRouteDuplicateFallbackUsed = true;
        lastRouteEmergencyFallbackUsed = true;
        lastRouteGenerationSource = 'cache';
        _debugRouteSearch(
          '[Fallback] duplicateFallbackUsed=true recentFallbackUsed=true '
          'emergencyFallbackUsed=true scenarioKey=${scenario.scenarioKey} '
          'forceFreshVariant=$forceFreshVariant trigger=$debugTrigger',
        );
        return _finalizeAndRememberRoute(
          scenario: scenario,
          route: recentDuplicate,
          fromCache: true,
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

      final skipExtraRoundTripFallback = _skipExtraLiveFallbackForRoundTrip(
        scenario,
        styleConfig,
      );
      final edgeLiveFillExhausted = _edgeLiveFillExhausted(lastError);
      if (!poolHealingFirstPolicy &&
          !onDemandLiveFill &&
          _canUseStructuredFallback(lastError) &&
          !skipExtraRoundTripFallback &&
          !edgeLiveFillExhausted) {
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
      } else if (skipExtraRoundTripFallback) {
        _debugRouteSearch(
          '[Fallback] extraLiveFallbackSkipped=true '
          'reason=long_no_highway_curvy scenarioKey=${scenario.scenarioKey}',
        );
      } else if (edgeLiveFillExhausted) {
        _debugRouteSearch(
          '[Fallback] extraLiveFallbackSkipped=true '
          'reason=edge_live_fill_exhausted '
          'scenarioKey=${scenario.scenarioKey}',
        );
      } else if (onDemandLiveFill) {
        _debugRouteSearch(
          '[Fallback] extraLiveFallbackSkipped=true '
          'reason=on_demand_live_fill_exhausted '
          'scenarioKey=${scenario.scenarioKey}',
        );
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

      if (_isSearchInProgressError(lastError)) {
        throw lastError!;
      }

      final warmupError = await _maybeBuildCoverageWarmupError(
        scenario: scenario,
        userLat: startPosition.latitude,
        userLng: startPosition.longitude,
        lastError: lastError,
        coverage: poolHealingCoverage,
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

  Future<RouteResult?> pollRoundTripSearchSession(
    String searchSessionId,
  ) async {
    final id = searchSessionId.trim();
    if (id.isEmpty) return null;
    final body = <String, dynamic>{
      'action': 'get_search_session',
      'search_session_id': id,
      'route_type': 'ROUND_TRIP',
      'planning_type': 'Zufall',
      'client_trigger': 'searchSessionPoll',
      'client_scenario_key': 'search_session:$id',
    };
    try {
      debugPrint(
        '[RouteService][SearchSessionPoll] id=$id '
        'clientRoutingBuildId=$clientRoutingBuildId '
        'clientRoutingBuildTime=$clientRoutingBuildTime',
      );
      final result = await _invoke(body);
      result.edgeMeta['search_session_id'] ??= id;
      result.edgeMeta['route_source'] ??= 'search_session';
      _lastRoundTripSearchSessionMeta = Map<String, dynamic>.from(
        result.edgeMeta,
      );
      debugPrint(
        '[RouteService][SearchSessionPoll] id=$id status=found '
        'source=${result.edgeMeta['route_source'] ?? result.edgeMeta['source']} '
        'final_geometry_source=${result.edgeMeta['final_geometry_source'] ?? result.edgeMeta['geometry_source']} '
        'coordinate_count=${result.coordinates.length}',
      );
      return result;
    } on RouteServiceException catch (error) {
      _lastRoundTripSearchSessionMeta = Map<String, dynamic>.from(
        error.edgeMeta,
      );
      final code =
          error.edgeMeta['response_code']?.toString() ??
          error.edgeMeta['code']?.toString();
      final status = error.edgeMeta['search_session_status']?.toString();
      debugPrint(
        '[RouteService][SearchSessionPoll] id=$id route_pending=true '
        'code=$code status=$status '
        'attempts=${error.edgeMeta['attempts_count']} '
        'worker_last_seen_at=${error.edgeMeta['worker_last_seen_at']} '
        'message=${error.userMessage}',
      );
      if (_isSearchInProgressError(error)) return null;
      rethrow;
    }
  }

  Future<bool> kickRoundTripSearchSession(
    String searchSessionId, {
    String reason = 'client_poll_stale',
  }) async {
    final id = searchSessionId.trim();
    if (id.isEmpty) return false;
    final body = <String, dynamic>{
      'action': 'kick_search_session',
      'search_session_id': id,
      'route_type': 'ROUND_TRIP',
      'planning_type': 'Zufall',
      'client_trigger': reason,
      'client_scenario_key': 'search_session_kick:$id',
      'await_worker_response': reason == 'client_poll_stale',
    };
    try {
      final raw = await _invoker
          .invoke(body)
          .timeout(const Duration(seconds: 8));
      dynamic data = raw is FunctionResponse ? raw.data : raw;
      if (data is String) {
        data = json.decode(data);
      }
      if (data is Map) {
        final scheduled = data['worker_invocation_scheduled'] == true;
        final ok = data['worker_invocation_ok'] != false;
        debugPrint(
          '[RouteService] Search session kick id=$id scheduled=$scheduled ok=$ok',
        );
        return scheduled && ok;
      }
      return false;
    } catch (error) {
      debugPrint('[RouteService] Search session kick failed id=$id: $error');
      return false;
    }
  }

  Future<RouteResult> _generateRequiredWaypointRoundTrip({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required geo.Position startPosition,
    required List<Map<String, double>> userWaypoints,
    int? variantIndex,
    bool forceFreshVariant = false,
    String? waypointOrigin,
    int? waypointSeedAttempt,
    String debugTrigger = 'unknown',
    Map<String, double>? targetLocation,
  }) async {
    lastRouteSourceDecision = forceFreshVariant
        ? 'waypoint_required_stops_search_again'
        : 'waypoint_required_stops';
    lastRouteLiveAttemptReason = 'required_waypoint_route';

    final normalizedWaypointOrigin = waypointOrigin == 'auto_seed'
        ? 'auto_seed'
        : 'manual';
    final isAutoSeed = normalizedWaypointOrigin == 'auto_seed';
    final maxAttempts = isAutoSeed
        ? (forceFreshVariant ? 4 : 3)
        : (forceFreshVariant ? 3 : 2);
    final candidateBudget = isAutoSeed ? 30 : 18;
    _RouteCandidate? bestCandidate;
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
        '[WaypointRequired] attempt=${attempt + 1}/$maxAttempts '
        'scenarioKey=${scenario.scenarioKey} routeVariantHint=${variant.variantHint} '
        'fingerprintHint=${variant.fingerprintHint} forceFreshVariant=$forceFreshVariant '
        'waypointOrigin=$normalizedWaypointOrigin',
      );
      try {
        final candidate = await _requestRoundTripVariant(
          scenario: scenario,
          styleConfig: styleConfig,
          startPosition: startPosition,
          targetLocation: targetLocation,
          userWaypoints: userWaypoints,
          originalPlanningType: 'Wegpunkte',
          variant: variant,
          forceFreshVariant: forceFreshVariant,
          debugTrigger: debugTrigger,
          candidateBudget: candidateBudget,
          waypointOrigin: normalizedWaypointOrigin,
          waypointSeedAttempt: waypointSeedAttempt,
        );
        if (!candidate.accepted) {
          continue;
        }
        if (!candidate.novelEnough) {
          lastRouteDuplicateSkipped = true;
          if (_isBetterCandidate(candidate, bestDuplicateCandidate)) {
            bestDuplicateCandidate = candidate;
          }
          continue;
        }
        if (_isBetterCandidate(candidate, bestCandidate)) {
          bestCandidate = candidate;
        }
        if (candidate.isIdeal || candidate.isGood) break;
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
          '[RouteService] Required-waypoint candidate ${attempt + 1}/$maxAttempts fehlgeschlagen: ${mapped.debugMessage}',
        );
        if (_isFatalStructuredError(mapped)) {
          break;
        }
      }
    }

    final accepted = bestCandidate ?? bestDuplicateCandidate;
    if (accepted?.accepted == true) {
      if (identical(accepted, bestDuplicateCandidate) &&
          bestCandidate == null) {
        lastRouteDuplicateFallbackUsed = true;
      }
      lastRouteGenerationSource = 'mapbox';
      return _finalizeAndRemember(
        scenario: scenario,
        route: accepted!.route,
        sampledCoordinates: accepted.sampledCoordinates,
        fingerprint: accepted.fingerprint,
      );
    }

    throw lastError ??
        const RouteServiceException(
          type: RouteErrorType.quality,
          userMessage:
              'Diese Wegpunkte lassen sich nicht zu einer sauberen Route verbinden. Verschiebe einen Punkt oder entferne ihn.',
          debugMessage:
              'Required waypoint roundtrip failed without accepted candidate.',
          edgeMeta: {
            'response_code': 'waypoint_quality_too_low',
            'planning_type': 'Wegpunkte',
            'waypoint_mode': 'required_stops',
          },
        );
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
    bool navigationReroute = false,
    int? candidateBudgetOverride,
    int? maxSearchMsOverride,
    double? currentHeadingDegrees,
    double? currentSpeedMetersPerSecond,
    double? locationAccuracyMeters,
  }) async {
    final startToDestinationMeters = geo.Geolocator.distanceBetween(
      startPosition.latitude,
      startPosition.longitude,
      destinationLat,
      destinationLng,
    );
    if (startToDestinationMeters < 250) {
      throw const RouteServiceException(
        type: RouteErrorType.validation,
        userMessage: 'Start und Ziel liegen zu nah beieinander.',
        debugMessage:
            'POINT_TO_POINT rejected because start and destination are too close.',
      );
    }
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

    // Stabiler Suffix statt Timestamp: rapid Double-Click auf "Erneut suchen"
    // dedupliziert auf einen einzigen Single-Flight statt parallele Edge-Calls
    // zu erzeugen — verhindert Mapbox-5xx-Flood unter Last.
    final singleFlightKey = forceFreshVariant
        ? '${scenario.scenarioKey}|sa'
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
      final shouldUseTwoLiveAttempts = shouldDiversify && !navigationReroute;
      // Client-Schleife: direkte A→B-Routen bekommen nur einen Live-Versuch,
      // Scenic-/Detour-Varianten behalten einen zweiten Versuch für echte
      // Diversifikation und transienten Provider-Pressure.
      final maxAttempts = shouldUseTwoLiveAttempts ? 2 : 1;
      final previousFingerprints = SeenRouteRegistry.entriesForAny(
        _seenHistoryKeysForScenario(scenario),
      ).map((entry) => entry.fingerprint).toList(growable: false);
      _RouteCandidate? bestCandidate;
      _RouteCandidate? spareCandidate;
      _RouteCandidate? duplicateFallbackCandidate;
      _RouteCandidate? bestRejectedCandidate;
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
            // Scenic A→B darf 15-25s suchen; mehrere Korridor-Familien
            // sind nötig, damit Klein/Mittel/Groß unterscheidbar bleiben.
            candidateBudget:
                candidateBudgetOverride ??
                (normalizedVariant >= 2 ? 9 : (hasSeenHistory ? 5 : 6)),
            previousFingerprints: previousFingerprints,
            navigationReroute: navigationReroute,
            maxSearchMsOverride: maxSearchMsOverride,
            currentHeadingDegrees: currentHeadingDegrees,
            currentSpeedMetersPerSecond: currentSpeedMetersPerSecond,
            locationAccuracyMeters: locationAccuracyMeters,
          );
          if (candidate.accepted && !candidate.novelEnough) {
            lastRouteDuplicateSkipped = true;
            if (_isBetterCandidate(candidate, duplicateFallbackCandidate)) {
              duplicateFallbackCandidate = candidate;
            }
          } else if (candidate.accepted) {
            if (_isBetterCandidate(candidate, bestCandidate)) {
              if (bestCandidate != null &&
                  _isBetterCandidate(bestCandidate, spareCandidate)) {
                spareCandidate = bestCandidate;
              }
              bestCandidate = candidate;
            } else if (_isBetterCandidate(candidate, spareCandidate)) {
              spareCandidate = candidate;
            }
          } else if (bestRejectedCandidate == null ||
              candidate.score < bestRejectedCandidate.score) {
            bestRejectedCandidate = candidate;
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

      final acceptedCandidate = bestCandidate ?? duplicateFallbackCandidate;
      if (acceptedCandidate != null && acceptedCandidate.accepted) {
        if (bestCandidate == null && duplicateFallbackCandidate != null) {
          lastRouteDuplicateFallbackUsed = true;
        }
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
        } else if (shouldDiversify &&
            !forceFreshVariant &&
            !navigationReroute) {
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

      if (bestRejectedCandidate != null && lastError == null) {
        lastError = _buildPointToPointQualityTooLowException(
          scenario: scenario,
          candidate: bestRejectedCandidate,
        );
      }

      if (!navigationReroute) {
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
    return <String>{
      scenario.scenarioKey,
      scenario.noveltyKey,
      scenario.broadNoveltyKey,
    };
  }

  static List<String> _recentFingerprintsForScenario(RouteScenario scenario) =>
      SeenRouteRegistry.entriesForAny(
        _seenHistoryKeysForScenario(scenario),
      ).map((entry) => entry.fingerprint).take(10).toList(growable: false);

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

  static List<Map<String, double>> _normalizeUserWaypoints(
    List<Map<String, double>>? userWaypoints,
  ) {
    if (userWaypoints == null) return const [];
    return userWaypoints
        .map((point) {
          final latitude = point['latitude'];
          final longitude = point['longitude'];
          if (latitude == null ||
              longitude == null ||
              !latitude.isFinite ||
              !longitude.isFinite ||
              latitude < -90 ||
              latitude > 90 ||
              longitude < -180 ||
              longitude > 180) {
            return null;
          }
          return <String, double>{'latitude': latitude, 'longitude': longitude};
        })
        .whereType<Map<String, double>>()
        .toList(growable: false);
  }

  static String _buildWaypointSignature(
    List<Map<String, double>> userWaypoints,
  ) {
    if (userWaypoints.isEmpty) return 'none';
    return userWaypoints
        .map((point) {
          final lat = point['latitude'] ?? 0.0;
          final lng = point['longitude'] ?? 0.0;
          return '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
        })
        .join(';');
  }

  static RouteServiceException? _validateRequiredWaypoints({
    required geo.Position startPosition,
    required List<Map<String, double>> waypoints,
    required int targetDistanceKm,
  }) {
    RouteServiceException failure(
      String code,
      String userMessage,
      String debugMessage, {
      Map<String, dynamic> meta = const {},
    }) {
      return RouteServiceException(
        type: RouteErrorType.validation,
        userMessage: userMessage,
        debugMessage: debugMessage,
        edgeMeta: <String, dynamic>{
          'response_code': code,
          'code': code,
          'planning_type': 'Wegpunkte',
          'waypoint_mode': 'required_stops',
          'waypoint_route_mode': 'required_stops',
          'required_waypoint_count': waypoints.length,
          'max_waypoints': 3,
          ...meta,
        },
      );
    }

    if (waypoints.isEmpty) {
      return failure(
        'too_few_waypoints',
        'Setze mindestens einen Stopp für diese Rundkurs-Planung.',
        'Waypoint required-stops mode requires at least one waypoint.',
      );
    }
    if (waypoints.length > 3) {
      return failure(
        'too_many_waypoints',
        'Bitte nutze maximal 3 Stopps.',
        'Waypoint required-stops mode supports at most 3 waypoints.',
      );
    }

    const minPointDistanceKm = 0.20;
    final maxWaypointDistanceKm = math.max(
      12.0,
      math.min(220.0, targetDistanceKm * 0.75),
    );
    for (var i = 0; i < waypoints.length; i += 1) {
      final point = waypoints[i];
      final lat = point['latitude']!;
      final lng = point['longitude']!;
      final fromStartKm =
          geo.Geolocator.distanceBetween(
            startPosition.latitude,
            startPosition.longitude,
            lat,
            lng,
          ) /
          1000.0;
      if (fromStartKm < minPointDistanceKm) {
        return failure(
          'waypoint_duplicate_or_too_close',
          'Ein Stopp liegt zu nah am Start. Verschiebe ihn ein Stück weiter.',
          'Required waypoint $i is ${fromStartKm.toStringAsFixed(2)}km from start.',
          meta: {'failed_waypoint_index': i},
        );
      }
      if (fromStartKm > maxWaypointDistanceKm) {
        return failure(
          'waypoint_too_far',
          'Ein Stopp liegt zu weit weg für diesen Rundkurs.',
          'Required waypoint $i is ${fromStartKm.toStringAsFixed(1)}km from start.',
          meta: {
            'failed_waypoint_index': i,
            'max_waypoint_distance_km': maxWaypointDistanceKm,
          },
        );
      }
      for (var j = 0; j < i; j += 1) {
        final other = waypoints[j];
        final pairKm =
            geo.Geolocator.distanceBetween(
              lat,
              lng,
              other['latitude']!,
              other['longitude']!,
            ) /
            1000.0;
        if (pairKm < minPointDistanceKm) {
          return failure(
            'waypoint_duplicate_or_too_close',
            'Zwei Stopps liegen zu nah beieinander. Verschiebe oder lösche einen Punkt.',
            'Required waypoints $j and $i are ${pairKm.toStringAsFixed(2)}km apart.',
            meta: {'failed_waypoint_index': i, 'duplicate_waypoint_index': j},
          );
        }
      }
    }
    return null;
  }

  static bool _isMovingStart(geo.Position position) {
    return position.speed.isFinite && position.speed >= 2.5;
  }

  static double? _usableHeading(geo.Position position) {
    final heading = position.heading;
    if (!heading.isFinite || heading < 0) return null;
    final accuracy = position.headingAccuracy;
    if (accuracy.isFinite && accuracy > 45) return null;
    return heading % 360;
  }

  static double? _safeFiniteDouble(double value) =>
      value.isFinite ? value : null;

  static double _movingStartRadiusMeters(geo.Position position) {
    final accuracy = position.accuracy.isFinite ? position.accuracy : 25.0;
    return math.max(20.0, math.min(120.0, accuracy * 2.5));
  }

  static double _avoidManeuverRadiusMeters(
    geo.Position position, {
    required bool avoidHighways,
  }) {
    final speed = position.speed.isFinite ? position.speed : 0.0;
    final speedScaled = math.max(80.0, speed * 12.0);
    final base = avoidHighways ? 180.0 : 120.0;
    return math.max(base, math.min(500.0, speedScaled));
  }

  Map<String, dynamic> _buildRoundTripRequest({
    required geo.Position startPosition,
    required int targetDistanceKm,
    required String mode,
    required String planningType,
    required RouteStyleConfig styleConfig,
    required RouteVariant variant,
    Map<String, double>? targetLocation,
    List<Map<String, double>> userWaypoints = const [],
    double? directionHint,
    int candidateBudget = 3,
    int roundTripBatchIndex = 0,
    int roundTripBatchCount = 1,
    bool avoidHighways = false,
    List<String> previousFingerprints = const [],
    String? originalPlanningType,
    String? waypointOrigin,
    int? waypointSeedAttempt,
  }) {
    final isRequiredWaypointRoundTrip =
        originalPlanningType == 'Wegpunkte' && userWaypoints.isNotEmpty;
    final normalizedWaypointOrigin = waypointOrigin == 'auto_seed'
        ? 'auto_seed'
        : 'manual';
    final isAutoSeedWaypoint = normalizedWaypointOrigin == 'auto_seed';
    final movingStart =
        !isRequiredWaypointRoundTrip && _isMovingStart(startPosition);
    final usableHeading = movingStart ? _usableHeading(startPosition) : null;
    final startRadiusMeters = movingStart
        ? _movingStartRadiusMeters(startPosition)
        : null;
    final avoidManeuverRadiusMeters = movingStart
        ? _avoidManeuverRadiusMeters(
            startPosition,
            avoidHighways: avoidHighways,
          )
        : null;
    if (!isRequiredWaypointRoundTrip) {
      lastRouteMovingStartDetected = movingStart;
      lastRouteStartSnapStrategy = movingStart
          ? (usableHeading == null
                ? 'moving_radius_snap'
                : 'moving_bearing_radius_snap')
          : 'default_roundtrip_snap';
      lastRouteStartOnMotorway = null;
      lastRouteAvoidManeuverRadiusUsed = avoidManeuverRadiusMeters;
    }
    return <String, dynamic>{
      'startLocation': {
        'latitude': startPosition.latitude,
        'longitude': startPosition.longitude,
      },
      'targetDistance': targetDistanceKm,
      'mode': mode,
      'route_type': 'ROUND_TRIP',
      'planning_type': planningType,
      if (isRequiredWaypointRoundTrip) ...{
        'waypoint_mode': 'required_stops',
        'required_waypoints': userWaypoints,
        'waypoint_origin': normalizedWaypointOrigin,
        'auto_seed_waypoints': isAutoSeedWaypoint,
        if (waypointSeedAttempt != null)
          'waypoint_seed_attempt': waypointSeedAttempt,
        'waypoint_order': 'auto_optimize',
        'close_loop': true,
        'max_search_ms': isAutoSeedWaypoint ? 42000 : 33000,
        'required_waypoint_count': userWaypoints.length,
      },
      'language': 'de',
      'randomSeed': variant.seed,
      'continue_straight': true, // Verhindert unnötige U-Turns
      'avoid_highways': avoidHighways,
      'route_variant_hint': variant.variantHint,
      'route_fingerprint_hint': variant.fingerprintHint,
      if (previousFingerprints.isNotEmpty)
        'previous_route_fingerprints': previousFingerprints.take(10).toList(),
      'max_candidate_attempts': candidateBudget,
      if (roundTripBatchCount > 1) ...{
        'roundtrip_batch_index': roundTripBatchIndex.clamp(
          0,
          roundTripBatchCount - 1,
        ),
        'roundtrip_batch_count': roundTripBatchCount,
      },
      ...styleConfig.toRequestHints(),
      if (targetLocation != null) 'targetLocation': targetLocation,
      // Richtungshinweis für die Edge Function: bestimmt die Hauptrichtung
      // der Waypoint-Verteilung (0-359°). Wird als baseBearing verwendet.
      if (!isRequiredWaypointRoundTrip && directionHint != null)
        'direction_hint': directionHint.round() % 360,
      if (movingStart) ...{
        'moving_start': true,
        'current_speed_mps': startPosition.speed,
        if (usableHeading != null) 'current_heading': usableHeading,
        if (_safeFiniteDouble(startPosition.accuracy) != null)
          'location_accuracy_m': startPosition.accuracy,
        if (_safeFiniteDouble(startPosition.headingAccuracy) != null)
          'heading_accuracy_deg': startPosition.headingAccuracy,
        if (_safeFiniteDouble(startPosition.speedAccuracy) != null)
          'speed_accuracy_mps': startPosition.speedAccuracy,
        if (startRadiusMeters != null) 'start_radius_m': startRadiusMeters,
        if (usableHeading != null) 'start_bearing_tolerance_deg': 45.0,
        if (avoidManeuverRadiusMeters != null)
          'avoid_maneuver_radius_m': avoidManeuverRadiusMeters,
      },
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
    List<String> previousFingerprints = const [],
    bool navigationReroute = false,
    int? maxSearchMsOverride,
    double? currentHeadingDegrees,
    double? currentSpeedMetersPerSecond,
    double? locationAccuracyMeters,
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
      if (navigationReroute) 'reroute_request': true,
      if (navigationReroute) 'moving_start': true,
      if (maxSearchMsOverride != null) 'max_search_ms': maxSearchMsOverride,
      if (currentHeadingDegrees != null)
        'current_heading': currentHeadingDegrees,
      if (currentSpeedMetersPerSecond != null)
        'current_speed_mps': currentSpeedMetersPerSecond,
      if (locationAccuracyMeters != null)
        'location_accuracy_m': locationAccuracyMeters,
      if (navigationReroute) 'start_radius_m': 65,
      if (navigationReroute) 'start_bearing_tolerance_deg': 70,
      if (navigationReroute) 'avoid_maneuver_radius_m': 80,
      if (previousFingerprints.isNotEmpty)
        'previous_route_fingerprints': previousFingerprints.take(8).toList(),
      if (maxSearchMsOverride == null && (scenic || normalizedVariant > 0))
        'max_search_ms': 25000,
      if (scenic || normalizedVariant > 0) ...styleConfig.toRequestHints(),
      if (scenic || normalizedVariant > 0) ...{
        'targetDistance': targetDistanceKm,
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
      maneuvers: filterManeuvers(
        result.maneuvers,
        routeCoordinateCount: result.coordinates.length,
      ),
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
      maneuvers: filterManeuvers(
        result.maneuvers,
        routeCoordinateCount: result.coordinates.length,
      ),
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

  double _maxSegmentMeters(List<List<double>> coordinates) {
    if (coordinates.length < 2) return 0.0;
    var maxSegment = 0.0;
    for (var index = 1; index < coordinates.length; index++) {
      maxSegment = math.max(
        maxSegment,
        _distanceBetweenCoordinates(coordinates[index - 1], coordinates[index]),
      );
    }
    return maxSegment;
  }

  double _averageSegmentMeters(List<List<double>> coordinates) {
    if (coordinates.length < 2) return 0.0;
    return _distanceAlongCoordinates(coordinates) / (coordinates.length - 1);
  }

  int _minimumRoadGeometryCoordinateCount(double distanceKm) {
    if (distanceKm <= 0) return 10;
    if (distanceKm <= 60) return 70;
    if (distanceKm <= 85) return 105;
    if (distanceKm <= 115) return 145;
    return 180;
  }

  String? _roundTripDisplayGeometryIssue({
    required List<List<double>> coordinates,
    required double? distanceKm,
    required Map<String, dynamic> edgeMeta,
  }) {
    if (coordinates.length < 2) {
      return 'too_few_coordinates';
    }
    final effectiveDistanceKm =
        distanceKm ?? (_distanceAlongCoordinates(coordinates) / 1000.0);
    if (effectiveDistanceKm >= 20) {
      final source =
          (edgeMeta['geometry_source'] ??
                  edgeMeta['final_geometry_source'] ??
                  '')
              .toString()
              .toLowerCase();
      final overview = (edgeMeta['final_overview'] ?? edgeMeta['overview'])
          ?.toString()
          .toLowerCase();
      if (source.contains('candidate_plan') ||
          source.contains('shaping_points') ||
          source.contains('waypoint_plan')) {
        return 'display_geometry_uses_candidate_points';
      }
      if (source.contains('pre_hydration') && overview != 'full') {
        return 'pre_hydration_geometry_not_full';
      }

      final minimumCount = _minimumRoadGeometryCoordinateCount(
        effectiveDistanceKm,
      );
      if (coordinates.length < minimumCount) {
        return 'coordinate_count_too_low';
      }
      final maxSegment = _maxSegmentMeters(coordinates);
      final maxAllowedSegment = effectiveDistanceKm >= 90 ? 2500.0 : 2000.0;
      if (maxSegment > maxAllowedSegment) {
        return 'segment_too_long';
      }
      if (_averageSegmentMeters(coordinates) > 900.0) {
        return 'average_segment_too_long';
      }
    }
    return null;
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
    final cached = clientForceFreshVariant ? null : _sessionCache[cacheKey];
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
    // Timeout muss das Edge-Time-Budget plus Serialisierungs-Reserve abdecken,
    // sonst killt der Client bei tough cases die Generierung mitten im Lauf.
    final requestedMaxSearchMs = body['max_search_ms'];
    final requestTimeoutSeconds = requestedMaxSearchMs is num
        ? math.max(26, math.min(40, (requestedMaxSearchMs / 1000).ceil() + 6))
        : 26;
    const maxRetries = 2;
    final retryRng = math.Random();
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final rawResponse = await _invoker
            .invoke(body)
            .timeout(Duration(seconds: requestTimeoutSeconds));
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
          requestBody: body,
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

    if (routeType == 'ROUND_TRIP') {
      final responseMeta = data['meta'] is Map
          ? Map<String, dynamic>.from(data['meta'] as Map)
          : const <String, dynamic>{};
      final routeMap = data['route'] is Map ? data['route'] as Map : null;
      final geometryMap = routeMap?['geometry'] is Map
          ? routeMap!['geometry'] as Map
          : null;
      final rawCoordinates = geometryMap?['coordinates'];
      final responseCoordinateCount = rawCoordinates is List
          ? rawCoordinates.length
          : responseMeta['final_coordinate_count'] ??
                responseMeta['coordinate_count'];
      if (kDebugMode) {
        debugPrint(
          '[RouteDebug][RoundTripResponse] '
          'clientRoutingBuildId=$clientRoutingBuildId '
          'requestId=${body['request_id']} '
          'status=${statusCode ?? 200} '
          'code=${data['code'] ?? responseMeta['response_code']} '
          'search_session_id=${responseMeta['search_session_id']} '
          'search_session_status=${responseMeta['search_session_status']} '
          'on_demand_worker_triggered=${responseMeta['on_demand_worker_triggered']} '
          'route_present=${data['route'] != null} '
          'source=${responseMeta['route_source'] ?? responseMeta['source']} '
          'final_geometry_source=${responseMeta['final_geometry_source'] ?? responseMeta['geometry_source']} '
          'coordinate_count=$responseCoordinateCount',
        );
      }
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
        requestBody: body,
      );
    }

    if (data['route'] == null && data['code'] != null) {
      throw _mapServiceError(
        errorMessage:
            data['message']?.toString() ??
            data['error']?.toString() ??
            data['code'].toString(),
        statusCode: statusCode,
        details: data,
        routeType: routeType,
        requestBody: body,
      );
    }

    if (data['route'] == null) {
      final edgeMeta = <String, dynamic>{
        ..._requestRoutingContextMeta(body),
        if (data['meta'] is Map)
          ...Map<String, dynamic>.from(data['meta'] as Map),
      };
      final userMessage = routeType == 'ROUND_TRIP'
          ? _roundTripNoRouteUserMessage(edgeMeta)
          : 'Keine passende Route gefunden. Bitte ändere Stil, Umweg oder Start/Ziel.';
      throw RouteServiceException(
        type: RouteErrorType.noRoute,
        userMessage: userMessage,
        debugMessage: 'Response has no "route" field.',
        statusCode: statusCode,
        edgeMeta: edgeMeta,
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
    final distanceRaw = (route['distance'] as num?)?.toDouble();
    final durationRaw = (route['duration'] as num?)?.toDouble();
    // IMMER die echte Mapbox-Distanz nutzen (in Metern -> km), NICHT meta.distance_km
    // meta.distance_km war frueher geclampt und zeigte falsche Werte
    final distanceKmActual = distanceRaw != null ? distanceRaw / 1000.0 : null;

    final edgeMeta = data['meta'] is Map
        ? Map<String, dynamic>.from(data['meta'] as Map)
        : <String, dynamic>{};
    if (violatesNoHighwayPolicy(
      avoidHighways: body['avoid_highways'] == true,
      edgeMeta: edgeMeta,
    )) {
      edgeMeta['motorway_violation'] = true;
      throw RouteServiceException(
        type: RouteErrorType.noRoute,
        userMessage:
            'Keine passende Route ohne Autobahn gefunden. Bitte fahre weiter und versuche es erneut.',
        debugMessage:
            'No-highway request rejected because Edge meta violates motorway policy.',
        statusCode: statusCode,
        edgeMeta: edgeMeta,
      );
    }
    final displayGeometryIssue = routeType == 'ROUND_TRIP'
        ? _roundTripDisplayGeometryIssue(
            coordinates: coordinates,
            distanceKm: distanceKmActual,
            edgeMeta: edgeMeta,
          )
        : null;
    if (displayGeometryIssue != null) {
      edgeMeta['response_code'] = 'route_display_geometry_invalid';
      edgeMeta['display_geometry_reject_reason'] = displayGeometryIssue;
      edgeMeta['coordinate_count'] = coordinates.length;
      edgeMeta['max_segment_m'] = _maxSegmentMeters(coordinates);
      edgeMeta['average_segment_m'] = _averageSegmentMeters(coordinates);
      throw RouteServiceException(
        type: RouteErrorType.noRoute,
        userMessage:
            'Wir konnten gerade keine sauber auf Straßen verlaufende Route finden. Wir prüfen weitere Vorschläge im Hintergrund.',
        debugMessage:
            'Round-trip display geometry rejected: $displayGeometryIssue.',
        statusCode: statusCode,
        edgeMeta: edgeMeta,
      );
    }

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

    debugPrint(
      '[RouteService] Route OK: ${coordinates.length} Punkte, ${distanceKmActual?.toStringAsFixed(1)} km (Mapbox: ${distanceRaw?.toStringAsFixed(0)} m)',
    );

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
        'delivered_detour_level=${edgeMeta['delivered_detour_level']}, '
        'detour_downgraded=${edgeMeta['detour_downgraded']}, '
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
    final waypointSignature = _requestWaypointSignature(body);
    final waypointCount = _requestWaypointCount(body);
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
      'user_waypoint_count': waypointCount,
      'user_waypoint_signature': waypointSignature,
      'waypoint_mode': body['waypoint_mode'],
      'waypoint_order': body['waypoint_order'],
      'waypoint_origin': body['waypoint_origin'],
      'auto_seed_waypoints': body['auto_seed_waypoints'],
      'waypoint_seed_attempt': body['waypoint_seed_attempt'],
      'required_waypoint_count': body['required_waypoint_count'],
      'original_planning_type': body['original_planning_type'],
      'effective_planning_type': body['effective_planning_type'],
      'generation_mode': body['generation_mode'],
      'preference_area_count': body['preference_area_count'],
      'preference_applied': body['preference_applied'],
      'close_loop': body['close_loop'],
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

  static double? _requestDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static Map<String, dynamic> _requestRoutingContextMeta(
    Map<String, dynamic>? body,
  ) {
    if (body == null) return const <String, dynamic>{};

    final routeType = body['route_type']?.toString();
    final isRoundTrip = routeType == 'ROUND_TRIP';
    final targetDistanceKm = _requestDouble(body['targetDistance']);
    final distanceBucket = isRoundTrip
        ? _distanceBucketForPool(targetDistanceKm)
        : null;
    final rawMode = body['mode']?.toString();
    final styleKey = rawMode == null
        ? null
        : RouteStyleConfig.forMode(rawMode).profileKey;

    return <String, dynamic>{
      if (routeType != null) 'requested_route_type': routeType,
      if (rawMode != null) 'requested_style': rawMode,
      if (styleKey != null) 'requested_style_key': styleKey,
      if (distanceBucket != null) 'requested_distance_bucket': distanceBucket,
      if (body.containsKey('avoid_highways'))
        'avoid_highways': body['avoid_highways'] == true,
      if (body['client_scenario_key'] != null)
        'client_scenario_key': body['client_scenario_key'],
      if (body['waypoint_origin'] != null)
        'waypoint_origin': body['waypoint_origin'],
      if (body['auto_seed_waypoints'] != null)
        'auto_seed_waypoints': body['auto_seed_waypoints'],
      if (isRoundTrip) 'exact_cell_required': true,
    };
  }

  static int _requestWaypointCount(Map<String, dynamic> body) {
    final waypoints =
        body['required_waypoints'] ??
        body['preference_areas'] ??
        body['user_waypoints'] ??
        body['manual_waypoints'];
    return waypoints is List ? waypoints.length : 0;
  }

  static String _requestWaypointSignature(Map<String, dynamic> body) {
    final waypoints =
        body['required_waypoints'] ??
        body['preference_areas'] ??
        body['user_waypoints'] ??
        body['manual_waypoints'];
    if (waypoints is! List || waypoints.isEmpty) return 'none';
    return waypoints
        .map((entry) {
          if (entry is! Map) return 'invalid';
          final lat = _roundDebugCoord(entry['latitude']) ?? 0.0;
          final lng = _roundDebugCoord(entry['longitude']) ?? 0.0;
          return '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
        })
        .join(';');
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

  static bool _edgeLiveFillExhausted(RouteServiceException? error) {
    if (error == null || error.type != RouteErrorType.noRoute) return false;
    final meta = error.edgeMeta;
    final attempted = meta['live_fill_attempted'] == true;
    final exhausted = meta['live_fill_exhausted'] == true;
    final attempts =
        (meta['live_fill_attempt_count'] as num?)?.toInt() ??
        ((meta['search_summary'] is Map)
            ? ((meta['search_summary'] as Map)['candidate_attempts'] as num?)
                      ?.toInt() ??
                  0
            : 0);
    return attempted && exhausted && attempts >= 5;
  }

  static bool _isSearchInProgressError(RouteServiceException? error) {
    if (error == null || error.type != RouteErrorType.noRoute) return false;
    final code =
        error.edgeMeta['response_code']?.toString() ??
        error.edgeMeta['code']?.toString();
    if (code == 'search_session_no_route') return false;
    final status = error.edgeMeta['search_session_status']?.toString();
    return code == 'search_in_progress' ||
        error.edgeMeta['search_in_progress'] == true ||
        status == 'queued' ||
        status == 'running' ||
        status == 'hydrating';
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

  static bool _usePoolHealingFirstForRoundTrip(RouteScenario scenario) {
    return scenario.isRoundTrip &&
        scenario.planningType == 'Zufall' &&
        scenario.avoidHighways &&
        _distanceBucketForPool(scenario.targetDistanceKm) == 50;
  }

  static bool _shouldStopLiveForPoolHealingCoverage(
    RoutePoolCoverageCheck coverage,
  ) {
    if (coverage.poolHealthy) return false;
    if (!coverage.bootstrapEnabled) return true;
    if (coverage.regionDifficulty == 'hard') return true;
    if (coverage.coverageStatus == 'hard_region_curated_needed' ||
        coverage.coverageStatus == 'bootstrap_limited' ||
        coverage.coverageStatus == 'cooldown') {
      return true;
    }
    final healingStatus = coverage.healingStatus;
    return healingStatus == 'healing_failed_cooldown' ||
        healingStatus == 'healing_paused_budget' ||
        healingStatus == 'hard_region_curated_needed';
  }

  static bool _shouldAllowHardRegionLiveExploration(
    RoutePoolCoverageCheck coverage,
    String subscriptionTier,
  ) {
    if (_isFreeTier(subscriptionTier) || coverage.poolHealthy) return false;
    return !coverage.bootstrapEnabled ||
        coverage.regionDifficulty == 'hard' ||
        coverage.hardRegionStatus == 'curated_needed' ||
        coverage.curatedSeedPreferred ||
        coverage.coverageStatus == 'hard_region_curated_needed' ||
        coverage.coverageStatus == 'bootstrap_limited';
  }

  static bool _shouldUseOnDemandLiveFill(RoutePoolCoverageCheck coverage) {
    return !coverage.poolHealthy &&
        !_shouldStopLiveForPoolHealingCoverage(coverage);
  }

  static int _poolHealingFirstCandidateBudget(RouteScenario scenario) {
    final bucket = _distanceBucketForPool(scenario.targetDistanceKm);
    return bucket == 50 ? 3 : 4;
  }

  static int _roundTripCandidateBudget(
    RouteScenario scenario,
    RouteStyleConfig styleConfig,
  ) {
    final targetKm = scenario.targetDistanceKm ?? 0.0;
    final highCostCurve =
        styleConfig.profileKey == 'kurvenjagd' && targetKm >= 120;
    if (scenario.avoidHighways) {
      final baseBudget = targetKm <= 60
          ? styleConfig.profileKey == 'sport'
                ? 15
                : 12
          : targetKm <= 85
          ? 12
          : 14;
      return styleConfig.profileKey == 'kurvenjagd'
          ? math.min(16, baseBudget + 2)
          : baseBudget;
    }
    final constrained =
        styleConfig.profileKey == 'kurvenjagd' && targetKm <= 60;

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

  static int _roundTripLiveBatchCount(
    RouteScenario scenario,
    RouteStyleConfig styleConfig,
  ) {
    if (!scenario.isRoundTrip || scenario.planningType != 'Zufall') return 1;
    final targetKm = scenario.targetDistanceKm ?? 0.0;
    final lakeBorderShortLoop =
        targetKm <= 60.0 &&
        scenario.startLatitude >= 47.43 &&
        scenario.startLatitude <= 47.58 &&
        scenario.startLongitude >= 9.58 &&
        scenario.startLongitude <= 9.86;
    if (lakeBorderShortLoop) return 3;
    if (targetKm >= 70.0) return 3;
    if (scenario.avoidHighways && targetKm >= 60.0) return 3;
    if (styleConfig.profileKey == 'entdecker' ||
        styleConfig.profileKey == 'abendrunde') {
      return 3;
    }
    return 1;
  }

  static bool _skipExtraLiveFallbackForRoundTrip(
    RouteScenario scenario,
    RouteStyleConfig styleConfig,
  ) {
    final bucket = _distanceBucketForPool(scenario.targetDistanceKm);
    return scenario.isRoundTrip &&
        scenario.avoidHighways &&
        styleConfig.profileKey == 'kurvenjagd' &&
        (bucket ?? 0) >= 75;
  }

  static int _rescueRoundTripWaypointLimit(RouteScenario scenario) {
    final targetKm = scenario.targetDistanceKm ?? 0.0;
    if (scenario.avoidHighways || targetKm >= 90) return 4;
    return 3;
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
    final waypointSignature = _requestWaypointSignature(body);
    final closeLoop = body['close_loop'] == true ? 1 : 0;
    return '${body['route_type']}_${body['mode']}_${body['planning_type']}_${body['targetDistance']}_${rLat}_$rLng$dKey'
        '_h${avoidHighways}_v${detourLevel}_s${seed}_d${dirHint}_o$offsetSide'
        '_vh$variantHint'
        '_fh$fingerprintHint'
        '_wp$waypointSignature'
        '_loop$closeLoop';
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
    final waypointSignature = _requestWaypointSignature(body);
    final closeLoop = body['close_loop'] == true ? 1 : 0;
    return '${body['route_type']}_${body['mode']}_${body['planning_type']}_${body['targetDistance']}_${rLat}_$rLng$dKey'
        '_h$avoidHighways'
        '_d$detourLevel'
        '_wp$waypointSignature'
        '_loop$closeLoop';
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
    bool forceFreshVariant = false,
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
    // Search Again mit Seen-Historie: 90° Pre-Shift damit der erste
    // ausprobierte Sektor garantiert deutlich von der zuletzt gefahrenen
    // Richtung abweicht. Die anschließende _avoidRecentRoundTripSector-
    // Iteration kann immer noch in einen anderen Sektor zurückspringen,
    // wenn der vorgeschlagene blockiert ist.
    final hasSeenForSearchAgain = forceFreshVariant &&
        SeenRouteRegistry.entriesForAny(
          _seenHistoryKeysForScenario(scenario),
        ).isNotEmpty;
    final searchAgainShiftDegrees = hasSeenForSearchAgain ? 90.0 : 0.0;
    final rawAngleOffset =
        (baseDirection + searchAgainShiftDegrees + index * 47.0 +
                (index % 5) * 23.0) %
            360;
    final angleOffset = _avoidRecentRoundTripSector(rawAngleOffset, scenario);
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

  static double _avoidRecentRoundTripSector(
    double angleDegrees,
    RouteScenario scenario,
  ) {
    if (!scenario.isRoundTrip) return angleDegrees % 360.0;
    final recentSectors = SeenRouteRegistry.recentDominantSectorsForAny(
      _seenHistoryKeysForScenario(scenario),
    );
    if (recentSectors.isEmpty || recentSectors.length >= 8) {
      return angleDegrees % 360.0;
    }
    for (var step = 0; step < 8; step += 1) {
      final candidate = (angleDegrees + step * 45.0) % 360.0;
      final sector = (candidate / 45.0).floor().clamp(0, 7).toInt();
      if (!recentSectors.contains(sector)) {
        return candidate;
      }
    }
    return angleDegrees % 360.0;
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
    int roundTripBatchIndex = 0,
    int roundTripBatchCount = 1,
    bool? requestAvoidHighways,
    bool forceFreshVariant = false,
    String debugTrigger = 'unknown',
    Map<String, double>? targetLocation,
    List<Map<String, double>> userWaypoints = const [],
    String? originalPlanningType,
    String? waypointOrigin,
    int? waypointSeedAttempt,
  }) async {
    final adjustedTargetKm = styleConfig.clampRoundTripDistanceKm(
      variant.index == 0
          ? (scenario.targetDistanceKm ?? 50.0).round()
          : ((scenario.targetDistanceKm ?? 50.0) * variant.radiusJitter)
                .round(),
    );
    final previousFingerprints = _recentFingerprintsForScenario(scenario);
    final body = _buildRoundTripRequest(
      startPosition: startPosition,
      targetDistanceKm: adjustedTargetKm,
      mode: scenario.style,
      planningType: scenario.planningType,
      styleConfig: styleConfig,
      variant: variant,
      targetLocation: targetLocation,
      userWaypoints: userWaypoints,
      directionHint: variant.angleOffset,
      candidateBudget: candidateBudget,
      roundTripBatchIndex: roundTripBatchIndex,
      roundTripBatchCount: roundTripBatchCount,
      avoidHighways: requestAvoidHighways ?? scenario.avoidHighways,
      previousFingerprints: previousFingerprints,
      originalPlanningType: originalPlanningType,
      waypointOrigin: waypointOrigin,
      waypointSeedAttempt: waypointSeedAttempt,
    );
    body['client_scenario_key'] = scenario.scenarioKey;
    body['client_force_fresh_variant'] = forceFreshVariant;
    body['client_trigger'] = debugTrigger;
    final result = await _invoke(body);
    final snapped = _snapRouteToStartPosition(result, startPosition);
    if (originalPlanningType == 'Wegpunkte') {
      snapped.edgeMeta['waypoint_mode'] ??= 'required_stops';
      snapped.edgeMeta['waypoint_route_mode'] ??= 'required_stops';
      snapped.edgeMeta['required_waypoint_count'] ??= userWaypoints.length;
      snapped.edgeMeta['waypoint_origin'] ??= waypointOrigin ?? 'manual';
      snapped.edgeMeta['auto_seed_waypoints'] ??= waypointOrigin == 'auto_seed';
      snapped.edgeMeta['route_source'] ??= 'mapbox';
    }
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
    List<String> previousFingerprints = const [],
    bool navigationReroute = false,
    int? maxSearchMsOverride,
    double? currentHeadingDegrees,
    double? currentSpeedMetersPerSecond,
    double? locationAccuracyMeters,
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
      previousFingerprints: previousFingerprints,
      navigationReroute: navigationReroute,
      maxSearchMsOverride: maxSearchMsOverride,
      currentHeadingDegrees: currentHeadingDegrees,
      currentSpeedMetersPerSecond: currentSpeedMetersPerSecond,
      locationAccuracyMeters: locationAccuracyMeters,
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

  int _effectivePointToPointDetourLevel(
    RouteScenario scenario,
    RouteResult route,
  ) {
    if (!scenario.isPointToPoint) return scenario.detourLevel;
    final rawDelivered = route.edgeMeta['delivered_detour_level'];
    final delivered = rawDelivered is num
        ? rawDelivered.toInt()
        : int.tryParse(rawDelivered?.toString() ?? '');
    if (delivered == null) return scenario.detourLevel;
    return delivered.clamp(0, scenario.detourLevel).toInt();
  }

  double? _edgeMetaDouble(RouteResult route, String key) {
    final raw = route.edgeMeta[key];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '');
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
    final isRequiredWaypointRoundTrip =
        scenario.isRoundTrip && scenario.planningType == 'Wegpunkte';
    final pointToPointEvaluationDetourLevel = _effectivePointToPointDetourLevel(
      scenario,
      route,
    );
    final qualityTargetDistanceKm =
        scenario.isPointToPoint && pointToPointEvaluationDetourLevel <= 0
        ? 0.0
        : scenario.isRoundTrip && scenario.planningType == 'Wegpunkte'
        ? actualDistanceKm
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
    final destinationReached = _pointToPointDestinationReached(scenario, route);
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
    final routeDominantSector = scenario.isRoundTrip
        ? SeenRouteRegistry.dominantSectorForCoordinates(sampledCoordinates)
        : null;
    final recentRouteSameSector =
        scenario.isRoundTrip &&
        routeDominantSector != null &&
        recentRouteSamples != null &&
        SeenRouteRegistry.dominantSectorForCoordinates(recentRouteSamples) ==
            routeDominantSector;
    final seenRouteSameSector =
        scenario.isRoundTrip &&
        SeenRouteRegistry.hasRecentDominantSectorInAny(
          _seenHistoryKeysForScenario(scenario),
          sampledCoordinates,
        );
    final exactOrShapeSimilar =
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
    final sameSectorRepeated = recentRouteSameSector || seenRouteSameSector;
    final tooSimilar = exactOrShapeSimilar;
    final noveltyRequired = scenario.isRoundTrip || scenario.detourLevel > 0;
    final novelEnough = !noveltyRequired || !tooSimilar;
    final borderIntrusionRejected = _rejectRoundTripBorderIntrusion(
      scenario: scenario,
      coordinates: route.coordinates,
    );
    final minPoints = _minimumPointsForScenario(
      scenario,
      actualDistanceKm: actualDistanceKm,
    );
    final hasEnoughPoints = route.coordinates.length >= minPoints;
    final pointToPointMinDistance =
        !scenario.isPointToPoint || pointToPointEvaluationDetourLevel <= 0
        ? 0.0
        : _edgeMetaDouble(route, 'detour_min_distance_km') ??
              styleConfig.minimumPointToPointDistanceKm(
                directDistanceKm: directDistanceKm ?? 0.0,
                scenic: true,
                detourVariant: pointToPointEvaluationDetourLevel,
              );
    final pointToPointMaxDistance =
        !scenario.isPointToPoint || pointToPointEvaluationDetourLevel <= 0
        ? double.infinity
        : _edgeMetaDouble(route, 'detour_max_distance_km') ??
              styleConfig.maximumPointToPointDistanceKm(
                targetKm: scenario.targetDistanceKm ?? actualDistanceKm,
                directDistanceKm: directDistanceKm ?? 0.0,
                scenic: true,
                detourVariant: pointToPointEvaluationDetourLevel,
              );
    final detourDistanceOk =
        !scenario.isPointToPoint || pointToPointEvaluationDetourLevel <= 0
        ? true
        : actualDistanceKm >= pointToPointMinDistance &&
              actualDistanceKm <= pointToPointMaxDistance;
    final detourRenderableOk = _pointToPointDetourRenderable(
      scenario: scenario,
      styleConfig: styleConfig,
      actualDistanceKm: actualDistanceKm,
      directDistanceKm: directDistanceKm ?? 0.0,
      detourLevel: pointToPointEvaluationDetourLevel,
      minDistanceKm: pointToPointMinDistance,
      maxDistanceKm: pointToPointMaxDistance,
    );
    final successFirstDistanceOk = isRequiredWaypointRoundTrip
        ? true
        : scenario.isRoundTrip
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
            if (pointToPointEvaluationDetourLevel > 0) {
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
        scenario.isPointToPoint && pointToPointEvaluationDetourLevel > 0
        ? detourRenderableOk
        : successFirstDistanceOk;
    final scenicFallbackRenderable =
        scenario.isPointToPoint &&
        pointToPointEvaluationDetourLevel > 0 &&
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
        : destinationReached &&
              detourRenderableOk &&
              (quality.passed ||
                  classification.isAcceptable ||
                  scenicFallbackRenderable ||
                  serverApprovedAcceptable);
    final isPoolFallbackRoute =
        scenario.isRoundTrip && variant.variantHint.startsWith('pool-');
    final poolShapeQualityOk =
        !isPoolFallbackRoute || (quality.passed && renderableDistanceOk);
    final longSportRoundTripShapeOk =
        !scenario.isRoundTrip ||
        !scenario.avoidHighways ||
        styleConfig.profileKey != 'sport' ||
        (scenario.targetDistanceKm ?? actualDistanceKm) < 90.0 ||
        _longSportRoundTripShapeRenderable(quality: quality);
    final softRenderable =
        hasEnoughPoints &&
        qualityAcceptable &&
        poolShapeQualityOk &&
        longSportRoundTripShapeOk &&
        !deadEndSpikeDetected &&
        !borderIntrusionRejected;
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
        pointToPointEvaluationDetourLevel > 0 &&
        !detourDistanceOk &&
        detourRenderableOk;
    final hasSoftStylePenalty = !styleSoftOk;
    final sectorRepeatPenalty = !tooSimilar && sameSectorRepeated ? 22.0 : 0.0;
    final hasSoftSimilarityPenalty = tooSimilar || sectorRepeatPenalty > 0.0;
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
        (borderIntrusionRejected ? 220.0 : 0.0) +
        (tooSimilar ? 45.0 : 0.0) +
        sectorRepeatPenalty +
        (detourDistanceOk ? 0.0 : 135.0) +
        (destinationReached ? 0.0 : 500.0) +
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
      'poolShapeOk=$poolShapeQualityOk, '
      'borderIntrusionRejected=$borderIntrusionRejected, '
      'dominantSector=${routeDominantSector ?? '-'}, '
      'sameSectorRecent=$recentRouteSameSector/$seenRouteSameSector, '
      'tooSimilar=$tooSimilar, novelEnough=$novelEnough, '
      'edgeTier=${edgeTier?.name ?? 'none'}, '
      'detourOk=$detourDistanceOk, deliveredDetour=$pointToPointEvaluationDetourLevel, '
      'destinationReached=$destinationReached, '
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

  bool _rejectRoundTripBorderIntrusion({
    required RouteScenario scenario,
    required List<List<double>> coordinates,
  }) {
    if (!scenario.isRoundTrip || coordinates.length < 8) return false;
    if (!_isVorarlbergRhineValleyStart(scenario)) return false;

    var foreignCorridorPoints = 0;
    for (final point in coordinates) {
      if (point.length < 2) continue;
      final lng = point[0];
      final lat = point[1];
      final likelySwissRhineValley =
          lat >= 47.05 &&
          lat <= 47.58 &&
          (lng < 9.53 || (lat >= 47.30 && lat <= 47.52 && lng < 9.61));
      if (likelySwissRhineValley) {
        foreignCorridorPoints += 1;
      }
    }
    return foreignCorridorPoints >= math.max(4, coordinates.length * 0.03);
  }

  bool _isVorarlbergRhineValleyStart(RouteScenario scenario) {
    return scenario.startLatitude >= 47.18 &&
        scenario.startLatitude <= 47.46 &&
        scenario.startLongitude >= 9.55 &&
        scenario.startLongitude <= 9.80;
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

  bool _longSportRoundTripShapeRenderable({
    required RouteQualityResult quality,
  }) {
    if (!quality.isLoopClosed || quality.uturnPositions.length > 1) {
      return false;
    }
    final hasSpurLoop =
        quality.spurArmPercent >= 36.0 &&
        (quality.middleCoverageRatio < 0.38 ||
            quality.repeatedStartAreaPercent >= 20.0 ||
            quality.centerRecrossPercent >= 24.0 ||
            quality.radialPeakCount >= 3);
    final hasOutAndBackLoop =
        quality.returnPathPercent >= 24.0 &&
        (quality.middleCoverageRatio < 0.42 ||
            quality.spurArmPercent >= 26.0 ||
            quality.foldedAreaPenalty >= 82.0);
    final hasFoldedStub =
        quality.foldedAreaPenalty >= 90.0 &&
        (quality.spurArmPercent >= 28.0 ||
            quality.centerRecrossPercent >= 24.0 ||
            quality.middleCoverageRatio < 0.34);
    if (hasSpurLoop || hasOutAndBackLoop || hasFoldedStub) {
      return false;
    }
    return quality.spurArmPercent <= 40.0 &&
        quality.centerRecrossPercent <= 30.0 &&
        quality.repeatedStartAreaPercent <= 34.0 &&
        quality.middleCoverageRatio >= 0.30 &&
        quality.dominantLoopScore >= 58.0;
  }

  bool _pointToPointDetourRenderable({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required double actualDistanceKm,
    required double directDistanceKm,
    required int detourLevel,
    required double minDistanceKm,
    required double maxDistanceKm,
  }) {
    if (!scenario.isPointToPoint || detourLevel <= 0) return true;
    if (actualDistanceKm >= minDistanceKm &&
        actualDistanceKm <= maxDistanceKm) {
      return true;
    }
    final rescueSlackKm = switch (detourLevel) {
      1 => 1.0,
      2 => 1.6,
      3 => 2.6,
      _ => 0.0,
    };
    final rescueMinFactor = switch (detourLevel) {
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
            detourVariant: detourLevel,
          ) *
          1.04,
    );
    return actualDistanceKm >= rescueMinKm && actualDistanceKm <= rescueMaxKm;
  }

  bool _pointToPointDestinationReached(
    RouteScenario scenario,
    RouteResult route,
  ) {
    if (!scenario.isPointToPoint) return true;
    if (scenario.destinationLatitude == null ||
        scenario.destinationLongitude == null ||
        route.coordinates.isEmpty) {
      return false;
    }
    final end = route.coordinates.last;
    if (end.length < 2) return false;
    final distanceMeters = geo.Geolocator.distanceBetween(
      end[1],
      end[0],
      scenario.destinationLatitude!,
      scenario.destinationLongitude!,
    );
    return distanceMeters <= 750.0;
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
                candidateBudget: scenario.detourLevel >= 2 ? 6 : 4,
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
    lastRoutePreviousFingerprints = _recentFingerprintsForScenario(scenario);
    final finalized = _finalizeRoute(route, scenarioKey: scenario.scenarioKey);
    final dominantSector = scenario.isRoundTrip
        ? SeenRouteRegistry.dominantSectorForCoordinates(sampledCoordinates)
        : null;
    if (dominantSector != null) {
      finalized.edgeMeta['dominant_direction_sector'] = dominantSector;
    }
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
    bool allowDuplicateFallback = false,
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
    lastRoutePoolExactBucketMissing = false;
    lastRouteAlternativeDistanceOffered = false;
    lastRouteRequestedDistanceBucket = bucket;
    lastRouteReturnedDistanceBucket = null;
    lastRouteAccessLegUsed = false;
    lastRouteAccessLegDistanceKm = null;

    var matches = await _routePoolService.findCandidateRoutesNear(
      userLat: userLat,
      userLng: userLng,
      distanceBucket: bucket,
      style: scenario.style,
      avoidHighways: scenario.avoidHighways,
      routeType: scenario.routeType,
    );
    final shouldProbeCandidateReserve = _shouldProbeCandidateReserve(
      scenario: scenario,
      matches: matches,
      fallbackReason: fallbackReason,
    );
    if (shouldProbeCandidateReserve) {
      final forceCandidateReserve = _shouldForceCandidateReserve(
        matches: matches,
        fallbackReason: fallbackReason,
      );
      final reserveMatches = await _routePoolService
          .findCandidateReserveRoutesNear(
            userLat: userLat,
            userLng: userLng,
            distanceBucket: bucket,
            style: scenario.style,
            avoidHighways: scenario.avoidHighways,
            routeType: scenario.routeType,
            forceAllow: forceCandidateReserve,
          );
      if (reserveMatches.isNotEmpty) {
        final seenRouteIds = matches.map((match) => match.route.id).toSet();
        matches = <RoutePoolMatch>[
          ...matches,
          ...reserveMatches.where((match) => seenRouteIds.add(match.route.id)),
        ];
      }
    }
    matches = _rankPoolFallbackMatchesForScenario(
      scenario: scenario,
      matches: matches,
      fallbackReason: fallbackReason,
    );
    lastRoutePoolCandidateCount = matches.length;
    if (matches.isEmpty) {
      lastRoutePoolExactBucketMissing = true;
      _debugRouteSearch(
        '[PoolFallback] poolHit=false reason=pool_density_missing '
        'scenarioKey=${scenario.scenarioKey} bucket=$bucket',
      );
      return null;
    }
    final hasExactBucketMatch = matches.any(
      (match) => match.route.distanceBucket == bucket,
    );
    if (!hasExactBucketMatch) {
      lastRoutePoolExactBucketMissing = true;
    }

    _RouteCandidate? bestSeenCandidate;
    RoutePoolMatch? bestSeenMatch;
    double? bestSeenStartDistanceKm;

    for (final match in matches) {
      if (scenario.isRoundTrip && match.route.distanceBucket != bucket) {
        lastRouteAlternativeDistanceOffered = true;
        lastRouteReturnedDistanceBucket = match.route.distanceBucket;
        _debugRouteSearch(
          '[PoolFallback] poolHit=true poolUsed=false reason=bucket_mismatch '
          'requestedBucket=$bucket returnedBucket=${match.route.distanceBucket} '
          'alternative_distance_offered=true poolMatchId=${match.route.id}',
        );
        continue;
      }
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
        lastRouteDuplicateSkipped = true;
        lastRoutePoolSeenCandidateCount += 1;
        _debugRouteSearch(
          '[PoolFallback] poolHit=true poolUsed=false reason=too_similar '
          'poolMatchId=${match.route.id}',
        );
        if (_isBetterCandidate(candidate, bestSeenCandidate)) {
          bestSeenCandidate = candidate;
          bestSeenMatch = match;
          bestSeenStartDistanceKm = actualPoolStartDistanceKm;
        }
        continue;
      }

      final usingCandidateReserve = _poolMatchUsesCandidateReserve(match);
      lastRoutePoolFallbackUsed = true;
      lastRouteEmergencyFallbackUsed = true;
      lastRouteGenerationSource = usingCandidateReserve
          ? 'candidate_reserve'
          : 'pool';
      if (usingCandidateReserve) {
        lastRouteTemporaryCandidate = true;
      }
      lastRoutePoolMatchId = match.route.id;
      lastRoutePoolMatchTier = match.radiusScope;
      lastRoutePoolStartDistanceKm = actualPoolStartDistanceKm;
      lastRoutePoolUsedReason = usingCandidateReserve
          ? 'candidate_reserve:$fallbackReason'
          : fallbackReason;
      _debugRouteSearch(
        '[PoolFallback] poolHit=true poolUsed=true '
        'poolMatchId=${match.route.id} poolMatchTier=${match.radiusScope} '
        'poolStartDistanceKm=${actualPoolStartDistanceKm.toStringAsFixed(1)} '
        'poolCandidateCount=${matches.length} '
        'poolSeenCandidateCount=$lastRoutePoolSeenCandidateCount '
        'candidateReserve=$usingCandidateReserve '
        'fallbackReason=$fallbackReason',
      );

      return _finalizeAndRemember(
        scenario: scenario,
        route: candidate.route,
        sampledCoordinates: candidate.sampledCoordinates,
        fingerprint: candidate.fingerprint,
      );
    }

    if (allowDuplicateFallback &&
        bestSeenCandidate != null &&
        bestSeenMatch != null) {
      final match = bestSeenMatch;
      final candidate = bestSeenCandidate;
      final usingCandidateReserve = _poolMatchUsesCandidateReserve(match);
      lastRouteDuplicateFallbackUsed = true;
      lastRoutePoolFallbackUsed = true;
      lastRouteEmergencyFallbackUsed = true;
      lastRouteGenerationSource = usingCandidateReserve
          ? 'candidate_reserve'
          : 'pool';
      if (usingCandidateReserve) {
        lastRouteTemporaryCandidate = true;
      }
      lastRoutePoolMatchId = match.route.id;
      lastRoutePoolMatchTier = match.radiusScope;
      lastRoutePoolStartDistanceKm = bestSeenStartDistanceKm;
      lastRoutePoolUsedReason = usingCandidateReserve
          ? 'duplicate_candidate_reserve_fallback:$fallbackReason'
          : 'duplicate_pool_fallback:$fallbackReason';
      _debugRouteSearch(
        '[PoolFallback] poolHit=true poolUsed=true duplicateFallbackUsed=true '
        'poolMatchId=${match.route.id} poolMatchTier=${match.radiusScope} '
        'poolStartDistanceKm=${bestSeenStartDistanceKm?.toStringAsFixed(1)} '
        'poolCandidateCount=${matches.length} '
        'poolSeenCandidateCount=$lastRoutePoolSeenCandidateCount '
        'candidateReserve=$usingCandidateReserve '
        'fallbackReason=$fallbackReason',
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
      'poolCandidateCount=${matches.length} '
      'poolSeenCandidateCount=$lastRoutePoolSeenCandidateCount',
    );
    return null;
  }

  bool _shouldProbeCandidateReserve({
    required RouteScenario scenario,
    required List<RoutePoolMatch> matches,
    required String fallbackReason,
  }) {
    if (!scenario.isRoundTrip) return false;
    if (matches.isEmpty || matches.length < 3) return true;
    final reason = fallbackReason.toLowerCase();
    if (reason.contains('search_again') ||
        reason.contains('no_route') ||
        reason.contains('no_accepted') ||
        reason.contains('border') ||
        reason.contains('candidate_queue') ||
        reason.contains('quality') ||
        reason.contains('similar') ||
        reason.contains('coverage') ||
        reason.contains('thin') ||
        reason.contains('warming')) {
      return true;
    }
    // No-highway roundtrips are the most constrained cells. A nearby verified
    // neighbor must not hide a local candidate reserve that already matches the
    // exact requested policy.
    return scenario.avoidHighways;
  }

  bool _shouldForceCandidateReserve({
    required List<RoutePoolMatch> matches,
    required String fallbackReason,
  }) {
    if (matches.isEmpty) return true;
    final reason = fallbackReason.toLowerCase();
    return reason.contains('search_again') ||
        reason.contains('no_route') ||
        reason.contains('no_accepted') ||
        reason.contains('border') ||
        reason.contains('candidate_queue') ||
        reason.contains('quality') ||
        reason.contains('similar');
  }

  List<RoutePoolMatch> _rankPoolFallbackMatchesForScenario({
    required RouteScenario scenario,
    required List<RoutePoolMatch> matches,
    required String fallbackReason,
  }) {
    if (!scenario.isRoundTrip || matches.length < 2) return matches;
    final historyKeys = _seenHistoryKeysForScenario(scenario);
    final recentSectors = SeenRouteRegistry.recentDominantSectorsForAny(
      historyKeys,
    );
    final reason = fallbackReason.toLowerCase();
    final forceDiversity =
        recentSectors.isNotEmpty ||
        reason.contains('search_again') ||
        reason.contains('settings') ||
        reason.contains('no_route') ||
        reason.contains('no_accepted') ||
        reason.contains('quality');
    final verifiedMatchCount = matches
        .where((match) => !_poolMatchUsesCandidateReserve(match))
        .length;
    final ranked = [...matches];
    ranked.sort((a, b) {
      final rankA = _poolFallbackNoveltyRank(
        scenario: scenario,
        match: a,
        historyKeys: historyKeys,
        recentSectors: recentSectors,
        forceDiversity: forceDiversity,
        verifiedMatchCount: verifiedMatchCount,
      );
      final rankB = _poolFallbackNoveltyRank(
        scenario: scenario,
        match: b,
        historyKeys: historyKeys,
        recentSectors: recentSectors,
        forceDiversity: forceDiversity,
        verifiedMatchCount: verifiedMatchCount,
      );
      if ((rankA - rankB).abs() > 0.001) {
        return rankA.compareTo(rankB);
      }
      return a.startDistanceKm.compareTo(b.startDistanceKm);
    });
    return ranked;
  }

  double _poolFallbackNoveltyRank({
    required RouteScenario scenario,
    required RoutePoolMatch match,
    required Iterable<String> historyKeys,
    required Set<int> recentSectors,
    required bool forceDiversity,
    required int verifiedMatchCount,
  }) {
    var rank = match.startDistanceKm.clamp(0.0, 999.0).toDouble();
    if (match.route.distanceBucket !=
        _distanceBucketForPool(scenario.targetDistanceKm)) {
      rank += 90.0;
    }

    final candidateReserve = _poolMatchUsesCandidateReserve(match);
    if (candidateReserve) {
      rank += forceDiversity || verifiedMatchCount <= 0 ? -14.0 : 8.0;
    } else if (!match.route.verified) {
      rank += 20.0;
    }

    final coordinates = extractCoordinates(match.route.geometry);
    if (coordinates.length >= 2) {
      final sampled = _sampleRouteForSimilarity(coordinates);
      final fingerprint = RouteQualityValidator.buildRouteFingerprint(
        sampled,
        distanceKm: match.route.distanceKm,
        precision: 4,
      );
      if (SeenRouteRegistry.hasExactFingerprintInAny(
        historyKeys,
        fingerprint,
      )) {
        rank += 500.0;
      } else if (SeenRouteRegistry.hasSimilarRouteInAny(
        historyKeys,
        sampled,
        thresholdPercent: _similarityThresholdForScenario(scenario),
        proximityMeters: _similarityProximityMetersForScenario(scenario),
      )) {
        rank += forceDiversity ? 180.0 : 70.0;
      }

      final sector = SeenRouteRegistry.dominantSectorForCoordinates(sampled);
      if (sector != null && recentSectors.contains(sector)) {
        rank += forceDiversity ? 80.0 : 24.0;
      }
    }

    rank -= match.route.qualityScore.clamp(0.0, 100.0).toDouble() * 0.02;
    return rank;
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
    } catch (error) {
      // Coverage/bootstrap metadata must never replace the original routing
      // error when the backing Supabase store is unavailable in unit tests or
      // degraded environments.
      debugPrint(
        '[RouteService] Coverage bootstrap failed: ${error.runtimeType}: $error',
      );
      return null;
    }
  }

  Future<RouteServiceException> _buildCoverageWarmupException({
    required RouteScenario scenario,
    required RoutePoolCoverageCheck coverage,
    required RouteServiceException? lastError,
  }) async {
    final cluster = coverage.assignment?.region.cityCluster;
    final qualityTooLow =
        lastError?.edgeMeta['route_quality_too_low'] == true ||
        lastError?.edgeMeta['code'] == 'route_quality_too_low';
    final bucket = _distanceBucketForPool(scenario.targetDistanceKm);
    final realBudgetPaused = _coverageIndicatesRealBudgetPause(
      coverage,
      lastError,
    );
    final warmupMessage = qualityTooLow
        ? 'Wir suchen noch nach einer besseren Route. Für diese Strecke und Einstellung gibt es gerade noch keine stabile Variante. Bitte warte kurz oder versuche es erneut.'
        : _coverageStatusUserMessage(
            coverage: coverage,
            cluster: cluster,
            requestedStyle: scenario.style,
            requestedDistanceBucket: bucket,
            realBudgetPaused: realBudgetPaused,
          );
    final responseCode = qualityTooLow
        ? 'route_quality_too_low'
        : realBudgetPaused
        ? 'route_budget_paused'
        : 'pool_bootstrap_pending';
    final poolBootstrapPending =
        qualityTooLow || coverage.seedJobCreated || coverage.bootstrapPending;
    final healingStatus = coverage.healingStatus;
    final nextAction = qualityTooLow
        ? 'retry_or_bootstrap'
        : _coverageNextAction(
            healingStatus,
            realBudgetPaused: realBudgetPaused,
          );
    final meta = <String, dynamic>{
      ...coverage.toMeta(),
      if (lastError != null) ...lastError.edgeMeta,
      'route_source': 'pool',
      'source': 'pool',
      'fallback_reason': lastError?.type.name ?? 'region_warming_up',
      'code': responseCode,
      'response_code': responseCode,
      'pool_bootstrap_pending': poolBootstrapPending,
      'route_quality_too_low': qualityTooLow,
      'route_budget_paused': realBudgetPaused,
      'budget_paused': realBudgetPaused,
      'requested_distance_bucket': bucket,
      'requested_style': scenario.style,
      'avoid_highways': scenario.avoidHighways,
      'pool_exact_bucket_missing': lastRoutePoolExactBucketMissing,
      'alternative_distance_offered': lastRouteAlternativeDistanceOffered,
      'returned_distance_bucket': lastRouteReturnedDistanceBucket,
      'user_message_required': true,
      'seed_job_queued':
          coverage.seedJobCreated ||
          coverage.seedJobStatus == 'queued' ||
          coverage.seedJobStatus == 'running',
      'retry_recommended': true,
      'retry_available':
          healingStatus != 'healing_paused_budget' || !realBudgetPaused,
      'estimated_wait_minutes': coverage.estimatedWaitMinutes,
      'next_action': nextAction,
      'real_budget_limited': realBudgetPaused,
      'no_candidate_found': !qualityTooLow && !realBudgetPaused,
      'background_learning_queued':
          coverage.seedJobCreated ||
          coverage.seedJobStatus == 'queued' ||
          coverage.seedJobStatus == 'running',
      'live_attempted': lastRouteApiCallCount > 0,
      'live_attempt_count': lastRouteApiCallCount,
      'live_blocked_reason': lastRouteApiCallCount == 0
          ? (lastRouteLiveAttemptReason ?? coverage.coverageStatus)
          : null,
      'live_attempt_reason': lastRouteApiCallCount > 0
          ? (lastRouteLiveAttemptReason ?? 'route_generation')
          : 'pool_healing_status',
      'live_fill_attempted': lastRouteApiCallCount > 0,
      'live_fill_attempt_count': lastRouteApiCallCount,
      'live_fill_success': false,
      'pool_checked': true,
      'source_decision': lastRouteSourceDecision,
      'mapbox_call_count': lastRouteApiCallCount,
      'live_attempt_result': lastError == null
          ? 'not_attempted'
          : lastError.edgeMeta['response_code'] ??
                lastError.edgeMeta['code'] ??
                lastError.type.name,
      'final_no_route_reason': lastError == null
          ? coverage.coverageStatus
          : lastError.edgeMeta['response_code'] ??
                lastError.edgeMeta['code'] ??
                lastError.type.name,
      'healing_job_created': coverage.seedJobCreated,
      'pool_verified_count': coverage.currentVerifiedCount,
      'pool_candidate_count': coverage.currentCandidateCount,
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

  RouteServiceException _buildPointToPointQualityTooLowException({
    required RouteScenario scenario,
    required _RouteCandidate candidate,
  }) {
    return RouteServiceException(
      type: RouteErrorType.quality,
      userMessage:
          'Wir suchen noch nach einer besseren Route. Für diese Strecke und Einstellung gibt es gerade noch keine stabile Variante.',
      debugMessage:
          'POINT_TO_POINT candidates were returned by Mapbox but rejected by quality gates. '
          'bestTier=${candidate.tier.name}, distance=${candidate.route.distanceKm?.toStringAsFixed(1)}km',
      edgeMeta: <String, dynamic>{
        'code': 'route_quality_too_low',
        'response_code': 'route_quality_too_low',
        'route_quality_too_low': true,
        'retry_available': true,
        'retry_search_started': true,
        'retry_attempted': scenario.detourLevel > 0,
        'retry_reason': 'quality_gates_rejected_candidates',
        'rejected_reason_summary': 'quality_gates_rejected_candidates',
        'best_candidate_quality_tier': candidate.tier.name,
        'next_action': 'retry_or_bootstrap',
        'requested_detour_level': scenario.detourLevel,
        'delivered_detour_level':
            candidate.route.edgeMeta['delivered_detour_level'],
        'detour_downgraded': candidate.route.edgeMeta['detour_downgraded'],
        'detour_fallback_stage':
            candidate.route.edgeMeta['detour_fallback_stage'],
      },
    );
  }

  String _coverageStatusUserMessage({
    required RoutePoolCoverageCheck coverage,
    required String? cluster,
    String? requestedStyle,
    int? requestedDistanceBucket,
    bool realBudgetPaused = false,
  }) {
    final clusterText = cluster ?? 'deiner Umgebung';
    final healingStatus = coverage.healingStatus;
    if (healingStatus == 'healing_running') {
      return 'Wir erstellen gerade neue Vorschläge für diese Einstellung. Bitte versuche es gleich erneut.';
    }
    if (healingStatus == 'healing_queued') {
      return 'Neue Vorschläge für diese Einstellung sind eingeplant. Wir starten den Aufbau automatisch.';
    }
    if (healingStatus == 'healing_failed_cooldown') {
      return 'Für diese Einstellung war gerade keine gute Route möglich. Wir versuchen es später automatisch erneut.';
    }
    if (healingStatus == 'healing_paused_budget' && realBudgetPaused) {
      return 'Heute wurden viele Routenvorschläge berechnet. Wir begrenzen neue Suchen kurzzeitig.';
    }
    if (healingStatus == 'healing_paused_budget') {
      return 'Neue Vorschläge für diese Einstellung sind eingeplant. Wir starten den Aufbau automatisch.';
    }
    final longCurvy =
        (requestedStyle ?? '').toLowerCase().contains('kurven') &&
        (requestedDistanceBucket ?? 0) >= 75;
    if (longCurvy) {
      return 'Kurvenjagd ist hier gerade schwer verfügbar. Wir bauen neue Vorschläge für diese Länge auf.';
    }
    switch (coverage.coverageStatus) {
      case 'hard_region_curated_needed':
        return 'In $clusterText ist diese Einstellung noch schwierig. Wir suchen passende Strecken und sammeln sichere Vorschläge.';
      case 'hard_region_thin':
        return 'In $clusterText gibt es erst wenige gute Varianten. Wir suchen weiter nach passenden Vorschlägen.';
      case 'bootstrap_limited':
        return 'In $clusterText sind die automatischen Aufbauversuche aktuell begrenzt. Bitte versuche es spaeter erneut.';
      case 'cooldown':
        return 'In $clusterText bauen wir gerade erste Routen auf. Bitte versuche es in einigen Minuten erneut.';
      case 'thin':
      case 'warming_up':
      case 'empty':
      default:
        return 'Fuer diese Laenge und diesen Stil gibt es in deiner Umgebung noch zu wenige gute Varianten. Wir erstellen gerade neue Vorschlaege. Bitte versuche es in ein paar Minuten erneut.';
    }
  }

  static bool _coverageIndicatesRealBudgetPause(
    RoutePoolCoverageCheck coverage,
    RouteServiceException? lastError,
  ) {
    if (lastError?.type == RouteErrorType.rateLimit ||
        lastError?.statusCode == 429) {
      return true;
    }
    if (_edgeMetaIndicatesRealBudgetPause(lastError?.edgeMeta ?? const {})) {
      return true;
    }
    // Seed-job budget states are internal worker bookkeeping. During test and
    // premium flows they must not surface as provider/global budget limits.
    return false;
  }

  static bool _edgeMetaIndicatesRealBudgetPause(Map<String, dynamic> edgeMeta) {
    if (edgeMeta['real_budget_limited'] == true ||
        edgeMeta['provider_rate_limited'] == true ||
        edgeMeta['mapbox_429'] == true ||
        edgeMeta['global_cap_reached'] == true ||
        edgeMeta['budget_limited_global'] == true) {
      return true;
    }
    final status = edgeMeta['status'] is num
        ? (edgeMeta['status'] as num).toInt()
        : int.tryParse(edgeMeta['status']?.toString() ?? '');
    final httpStatus = edgeMeta['http_status'] is num
        ? (edgeMeta['http_status'] as num).toInt()
        : int.tryParse(edgeMeta['http_status']?.toString() ?? '');
    if (status == 429 || httpStatus == 429) return true;
    for (final key in const [
      'code',
      'response_code',
      'final_no_route_reason',
      'live_attempt_result',
      'seed_job_error',
      'last_failure_reason',
    ]) {
      if (_isRealBudgetLimitCode(edgeMeta[key]?.toString())) return true;
    }
    return false;
  }

  static bool _isRealBudgetLimitCode(String? value) {
    final lower = value?.trim().toLowerCase();
    if (lower == null || lower.isEmpty) return false;
    return lower == 'provider_rate_limited' ||
        lower == 'mapbox_rate_limited' ||
        lower == 'mapbox_http_429' ||
        lower == 'http_429' ||
        lower == 'rate_limited' ||
        lower == 'too_many_requests' ||
        lower == 'budget_limited_global' ||
        lower == 'global_cap_reached' ||
        lower == 'global_safety_cap_reached' ||
        lower == 'supabase_function_limit' ||
        lower == 'function_resource_limit';
  }

  static String _coverageNextAction(
    String healingStatus, {
    bool realBudgetPaused = true,
  }) {
    return switch (healingStatus) {
      'healing_running' => 'wait_for_healing',
      'healing_queued' => 'queued_for_healing',
      'healing_failed_cooldown' => 'wait_for_cooldown',
      'healing_paused_budget' =>
        realBudgetPaused ? 'wait_for_budget' : 'queued_for_healing',
      'hard_region_curated_needed' => 'change_settings_or_curated',
      _ => 'bootstrap',
    };
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
    final temporaryCandidate =
        tier == RouteQualityTier.acceptable ||
        route.edgeMeta['safe_fallback_used'] == true ||
        route.edgeMeta['temporary_candidate'] == true;
    lastRouteTemporaryCandidate = temporaryCandidate;
    final routePayload = <String, dynamic>{
      ...route.edgeMeta,
      'candidate_fingerprint': fingerprint,
      'candidate_subscription_tier': normalizedTier,
      'temporary_candidate': temporaryCandidate,
      'safe_acceptable_candidate': temporaryCandidate,
      'candidate_policy': temporaryCandidate
          ? 'safe_acceptable_candidate'
          : 'quality_candidate',
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
      lastRouteCandidateDuplicateFingerprint = candidateSaveResult.duplicate;
      lastRouteCandidateDuplicateSource = candidateSaveResult.duplicateSource;
      lastRouteCandidateCoverageRefreshFailed =
          candidateSaveResult.coverageRefreshFailed;
      lastRouteCandidateSaveErrorType = candidateSaveResult.saveErrorType;
      lastRouteCandidateSaveErrorCode = candidateSaveResult.saveErrorCode;
      lastRouteCandidateSaveErrorReason = _sanitizeCandidateSaveError(
        candidateSaveResult.saveErrorReason,
      );
      lastRouteCandidateSaveSkippedReason = candidateSaveResult.skippedReason;
      lastRouteCandidateSaveFailed =
          candidateSaveResult.saveErrorType != null ||
          candidateSaveResult.saveErrorCode != null ||
          candidateSaveResult.saveErrorReason != null;
      lastRouteVerifiedInserted = false;
    } catch (error) {
      // Candidate staging must never block route delivery.
      lastRouteCandidateInserted = false;
      lastRouteCandidateSaveFailed = true;
      lastRouteCandidateDuplicateFingerprint = false;
      lastRouteCandidateDuplicateSource = null;
      lastRouteCandidateCoverageRefreshFailed = false;
      lastRouteCandidateSaveErrorType = error.runtimeType.toString();
      lastRouteCandidateSaveErrorCode = error is PostgrestException
          ? error.code
          : null;
      lastRouteCandidateSaveErrorReason = _sanitizeCandidateSaveError(
        error is PostgrestException ? error.message : error.toString(),
      );
      lastRouteCandidateSaveSkippedReason = null;
    }
  }

  static String? _sanitizeCandidateSaveError(String? error) {
    if (error == null) return null;
    final compact = error
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'(pk\.eyJ)[A-Za-z0-9_\-.]+'), r'$1[redacted]')
        .trim();
    if (compact.isEmpty) return null;
    return compact.length <= 180 ? compact : '${compact.substring(0, 180)}...';
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
    final candidateReserve = _poolMatchUsesCandidateReserve(match);
    final routeSource = candidateReserve ? 'candidate_reserve' : 'pool';
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
      'route_source': routeSource,
      'source': routeSource,
      'fallbackUsed': true,
      'fallback_reason': fallbackReason,
      'pool_match_id': match.route.id,
      'pool_match_tier': match.radiusScope,
      'pool_start_distance_km': match.startDistanceKm,
      'pool_allowed_radius_km': match.allowedRadiusKm,
      'quality_tier': candidateReserve ? 'acceptable' : 'good',
      'quality_reason': candidateReserve
          ? 'candidate_reserve_route'
          : 'verified_route_pool',
      'candidate_reserve_used': candidateReserve,
      'candidate_pool_id': candidateReserve ? match.route.id : null,
      'final_geometry_source': candidateReserve
          ? 'road_snapped_full'
          : (match.route.routePayload['final_geometry_source'] ??
                match.route.routePayload['geometry_source'] ??
                'route_pool'),
      'road_snapped_geometry': true,
      'final_coordinate_count': coordinates.length,
      'max_display_segment_m': _maxSegmentMeters(coordinates),
      'selected_style': scenario.style,
      'style_fit_score': double.parse(styleFitScore.toStringAsFixed(1)),
      'style_fit_reasons': styleConfig.styleFitReasons(styleMetrics),
      'style_metrics': styleMetrics.toJson(),
      'curve_density_per_km': styleMetrics.toJson()['curve_density_per_km'],
      'smoothness_score': styleMetrics.smoothnessScore,
      'zigzag_score': styleMetrics.microZigzagPercent,
      'sharp_turn_count': styleMetrics.sharpCurveDensityPer50Km,
      'avoid_highways_requested': scenario.avoidHighways,
      'highway_allowed': !scenario.avoidHighways,
      'motorway_policy': scenario.avoidHighways
          ? 'exclude_motorway'
          : 'allowed_not_required',
      'has_highway': match.route.hasHighway,
      'avoids_highway': match.route.avoidsHighway,
      'actual_has_highway': match.route.hasHighway,
      'actual_avoids_highway': match.route.avoidsHighway,
      'cross_cell_highway_fallback':
          !scenario.avoidHighways && match.route.avoidsHighway,
      'requested_distance_bucket': _distanceBucketForPool(
        scenario.targetDistanceKm,
      ),
      'returned_distance_bucket': match.route.distanceBucket,
      'pool_exact_bucket_missing': false,
      'alternative_distance_offered': false,
      'distance_bucket': match.route.distanceBucket,
      'mode': scenario.style,
      'orchestration': {
        'source': routeSource,
        'pool_hit': true,
        'pool_used': true,
        'candidate_reserve_used': candidateReserve,
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
    final candidateReserve = _poolMatchUsesCandidateReserve(match);
    return RouteVariant(
      index: 0,
      seed: 0,
      angleOffset: 0,
      radiusJitter: 1,
      offsetBearing: 0,
      fingerprintHint: '${scenario.scenarioKey}|pool|${match.route.id}',
      variantHint: candidateReserve
          ? 'candidate-reserve-${match.route.id}-$bucket'
          : 'pool-${match.route.id}-$bucket',
      styleBias: scenario.style,
    );
  }

  static bool _poolMatchUsesCandidateReserve(RoutePoolMatch match) {
    return match.route.source == 'candidate_reserve' ||
        match.route.routePayload['candidate_reserve'] == true;
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

  Future<RouteResult?> _tryHighwayAllowedNoHighwayRoundTripFallback({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required geo.Position startPosition,
    required bool forceFreshVariant,
    required String debugTrigger,
    Map<String, double>? targetLocation,
    List<Map<String, double>> userWaypoints = const [],
  }) async {
    if (scenario.avoidHighways || !scenario.isRoundTrip) return null;
    if (_isInWorkerLimitCooldown()) return null;

    final noHighwayScenario = RouteScenario(
      routeType: scenario.routeType,
      startLatitude: scenario.startLatitude,
      startLongitude: scenario.startLongitude,
      destinationLatitude: scenario.destinationLatitude,
      destinationLongitude: scenario.destinationLongitude,
      style: scenario.style,
      planningType: scenario.planningType,
      targetDistanceKm: scenario.targetDistanceKm,
      detourLevel: scenario.detourLevel,
      avoidHighways: true,
      waypointSignature: scenario.waypointSignature,
      closeLoop: scenario.closeLoop,
    );
    final noHighwayBudget = math.max(
      _roundTripCandidateBudget(noHighwayScenario, styleConfig),
      _roundTripCandidateBudget(scenario, styleConfig),
    );
    final noHighwayBatchCount = _roundTripLiveBatchCount(
      noHighwayScenario,
      styleConfig,
    );

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final variant = await _nextRoundTripVariant(
          noHighwayScenario,
          styleConfig: styleConfig,
          explicitIndex: attempt,
        );
        _debugRouteSearch(
          '[Fallback] highwayAllowedNoHighwayLive=true '
          'attempt=${attempt + 1}/2 scenarioKey=${scenario.scenarioKey} '
          'requestScenarioKey=${noHighwayScenario.scenarioKey} '
          'routeVariantHint=${variant.variantHint}',
        );
        final candidate = await _requestRoundTripVariant(
          scenario: noHighwayScenario,
          styleConfig: styleConfig,
          startPosition: startPosition,
          targetLocation: targetLocation,
          userWaypoints: userWaypoints,
          variant: variant,
          forceFreshVariant: forceFreshVariant,
          debugTrigger: debugTrigger,
          candidateBudget: noHighwayBudget,
          roundTripBatchIndex: noHighwayBatchCount <= 1
              ? 0
              : attempt % noHighwayBatchCount,
          roundTripBatchCount: noHighwayBatchCount,
          requestAvoidHighways: true,
        );
        if (!candidate.accepted || !candidate.novelEnough) {
          continue;
        }

        candidate.route.edgeMeta['avoid_highways_requested'] = false;
        candidate.route.edgeMeta['avoid_highways'] = false;
        candidate.route.edgeMeta['highway_allowed'] = true;
        candidate.route.edgeMeta['motorway_policy'] = 'allowed_not_required';
        candidate.route.edgeMeta['highway_allowed_fallback_used'] = true;
        candidate.route.edgeMeta['selected_no_highway_compatible'] = true;
        candidate.route.edgeMeta['cross_cell_highway_fallback'] = true;
        candidate.route.edgeMeta['actual_avoids_highway'] = true;
        candidate.route.edgeMeta['actual_has_highway'] = false;
        candidate.route.edgeMeta['mapbox_request_avoid_highways'] = true;
        candidate.route.edgeMeta['mapbox_request_motorway_excluded'] = true;

        lastRouteGenerationSource = 'mapbox';
        lastRouteEmergencyFallbackUsed = true;
        lastRouteSourceDecision = 'highway_allowed_no_highway_live_fallback';
        lastRouteLiveAttemptReason = 'allowed_not_required_no_highway_retry';

        await _maybeRecordRoutePoolCandidate(
          scenario: scenario,
          route: candidate.route,
          fingerprint: candidate.fingerprint,
          tier: candidate.tier,
          qualityScore: candidate.score,
          subscriptionTier: lastRouteSubscriptionTier,
        );
        return _finalizeAndRemember(
          scenario: scenario,
          route: candidate.route,
          sampledCoordinates: candidate.sampledCoordinates,
          fingerprint: candidate.fingerprint,
        );
      } catch (e) {
        debugPrint(
          '[RouteService] Highway-Allowed No-Highway-Fallback Versuch '
          '${attempt + 1}/2 fehlgeschlagen: $e',
        );
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
    if (_skipExtraLiveFallbackForRoundTrip(scenario, styleConfig)) {
      _debugRouteSearch(
        '[Rescue] skipStyleDowngrade=true reason=long_no_highway_curvy '
        'scenarioKey=${scenario.scenarioKey} '
        'bucket=${_distanceBucketForPool(scenario.targetDistanceKm)}',
      );
      return null;
    }

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
        final fallbackLevels = scenario.detourLevel >= 3
            ? <int>[2, 1]
            : scenario.detourLevel == 2
            ? <int>[2, 2, 1]
            : <int>[1];
        for (
          var fallbackIndex = 0;
          fallbackIndex < fallbackLevels.length;
          fallbackIndex++
        ) {
          final fallbackDetourLevel = fallbackLevels[fallbackIndex];
          final scenicVariant = _nextPointToPointVariant(
            scenario,
            normalizedVariant: fallbackDetourLevel,
            diversitySeed: 97 + fallbackIndex * 11,
            shouldDiversify: true,
          );
          final scenicMode = scenario.style == 'Standard'
              ? 'Sport Mode'
              : scenario.style;
          final scenicStyleConfig = RouteStyleConfig.forMode(scenicMode);
          final scenicDetourFactor = switch (fallbackDetourLevel) {
            1 => 1.32,
            2 => 1.65,
            3 => 2.10,
            _ => 1.15,
          };
          final scenicMinimumExtraKm = switch (fallbackDetourLevel) {
            1 => 3.0,
            2 => 7.0,
            3 => 14.0,
            _ => 2.0,
          };
          final scenicTargetKm = scenicStyleConfig.clampPointToPointTargetKm(
            math.max(
              directDistanceKm * scenicDetourFactor,
              directDistanceKm + scenicMinimumExtraKm,
            ),
            directDistanceKm: directDistanceKm,
            scenic: true,
            detourVariant: fallbackDetourLevel,
          );
          final scenicBody = _buildPointToPointRequest(
            startPosition: startPosition,
            destinationLat: destinationLat,
            destinationLng: destinationLng,
            mode: scenicMode,
            scenic: true,
            normalizedVariant: fallbackDetourLevel,
            avoidHighways: avoidHighways,
            styleConfig: scenicStyleConfig,
            targetDistanceKm: scenicTargetKm,
            detourFactor: scenicDetourFactor,
            variant: scenicVariant,
            offsetSide: scenario.detourLevel == 2 && fallbackDetourLevel == 2
                ? -1
                : scenicVariant.offsetSide,
            candidateBudget: 2,
          );
          scenicBody['simplify_waypoints'] = true;
          scenicBody['max_waypoints'] = fallbackDetourLevel >= 2
              ? (avoidHighways ? 2 : 2)
              : 1;
          final scenicResult = await _invoke(scenicBody);
          final scenicSnapped = _snapRouteToStartPosition(
            scenicResult,
            startPosition,
          );
          final edgeDeliveredLevel =
              (scenicSnapped.edgeMeta['delivered_detour_level'] as num?)
                  ?.toInt() ??
              fallbackDetourLevel;
          scenicSnapped.edgeMeta['requested_detour_level'] =
              scenario.detourLevel;
          scenicSnapped.edgeMeta['delivered_detour_level'] = edgeDeliveredLevel;
          scenicSnapped.edgeMeta['detour_downgraded'] =
              edgeDeliveredLevel < scenario.detourLevel;
          scenicSnapped.edgeMeta['detour_fallback_stage'] =
              edgeDeliveredLevel < scenario.detourLevel
              ? 'client_downgraded_to_$edgeDeliveredLevel'
              : 'client_scenic_fallback';
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
            '[RouteService] Vereinfachter Scenic-Fallback level=$fallbackDetourLevel verworfen: ${scenicCandidate.route.distanceKm?.toStringAsFixed(1)}km',
          );
        }
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
    final deliveredDetourLevel = _effectivePointToPointDetourLevel(
      scenario,
      candidate.route,
    );
    if (deliveredDetourLevel < scenario.detourLevel) return false;

    final actualDistanceKm = candidate.route.distanceKm ?? 0.0;
    final minimumRenderableKm = styleConfig.minimumPointToPointDistanceKm(
      directDistanceKm: directDistanceKm,
      scenic: true,
      detourVariant: deliveredDetourLevel,
    );
    final preferredSlackKm = switch (deliveredDetourLevel) {
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
    Map<String, dynamic>? requestBody,
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
        requestBody: requestBody,
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
    Map<String, dynamic>? requestBody,
  }) {
    final lower = errorMessage.toLowerCase();
    final detailsMap = details is Map
        ? Map<String, dynamic>.from(details)
        : null;
    final errorCode = detailsMap?['code']?.toString().toUpperCase();
    final retryAfterSec = (detailsMap?['retry_after_sec'] as num?)?.toInt();
    final edgeMeta = <String, dynamic>{
      ..._requestRoutingContextMeta(requestBody),
      if (detailsMap?['meta'] is Map)
        ...Map<String, dynamic>.from(detailsMap!['meta'] as Map),
    };

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
        errorCode == 'WORKER_RESOURCE_LIMIT' ||
        lower.contains('worker limit') ||
        lower.contains('resource limit') ||
        lower.contains('compute resources') ||
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

    final responseCode =
        edgeMeta['response_code']?.toString() ?? edgeMeta['code']?.toString();
    if (responseCode == 'search_in_progress' ||
        detailsMap?['code']?.toString() == 'search_in_progress' ||
        edgeMeta['search_in_progress'] == true) {
      return RouteServiceException(
        type: RouteErrorType.noRoute,
        userMessage:
            'Wir berechnen eine bessere Route. Das kann bei dieser Einstellung 1-2 Minuten dauern.',
        debugMessage:
            'Persistent round-trip search in progress (status=$statusCode): $errorMessage, details=$details',
        statusCode: statusCode,
        stackTrace: stackTrace,
        edgeMeta: edgeMeta,
      );
    }
    if (responseCode == 'search_session_no_route') {
      return RouteServiceException(
        type: RouteErrorType.noRoute,
        userMessage:
            'Wir haben mehrere Varianten geprüft, aber gerade keine sichere Route gefunden. Wir versuchen es im Hintergrund weiter.',
        debugMessage:
            'Persistent round-trip search exhausted (status=$statusCode): $errorMessage, details=$details',
        statusCode: statusCode,
        stackTrace: stackTrace,
        edgeMeta: edgeMeta,
      );
    }
    if (lower.contains('too_few_waypoints') ||
        lower.contains('too_many_waypoints') ||
        lower.contains('waypoint_duplicate_or_too_close') ||
        lower.contains('waypoint_too_far') ||
        lower.contains('waypoint_layout_unstable') ||
        lower.contains('waypoint_route_not_possible') ||
        lower.contains('waypoint_not_reached') ||
        responseCode == 'too_few_waypoints' ||
        responseCode == 'too_many_waypoints' ||
        responseCode == 'waypoint_duplicate_or_too_close' ||
        responseCode == 'waypoint_too_far' ||
        responseCode == 'waypoint_layout_unstable' ||
        responseCode == 'waypoint_route_not_possible' ||
        responseCode == 'waypoint_not_reached') {
      return RouteServiceException(
        type: RouteErrorType.validation,
        userMessage:
            'Diese Wegpunkte lassen sich nicht zu einer sauberen Route verbinden. Verschiebe einen Punkt oder entferne ihn.',
        debugMessage:
            'Waypoint validation error (status=$statusCode, reason=$reasonPhrase): $errorMessage, details=$details',
        statusCode: statusCode,
        stackTrace: stackTrace,
        edgeMeta: edgeMeta,
      );
    }

    if (lower.contains('waypoint_quality_too_low') ||
        responseCode == 'waypoint_quality_too_low') {
      return RouteServiceException(
        type: RouteErrorType.quality,
        userMessage:
            'Diese Wegpunkte lassen sich nicht zu einer sauberen Route verbinden. Verschiebe einen Punkt oder entferne ihn.',
        debugMessage:
            'Waypoint quality error (status=$statusCode, reason=$reasonPhrase): $errorMessage, details=$details',
        statusCode: statusCode,
        stackTrace: stackTrace,
        edgeMeta: edgeMeta,
      );
    }

    if (lower.contains('no route found') ||
        lower.contains('keine route gefunden') ||
        lower.contains('no route') ||
        lower.contains('keine passende route')) {
      final userMessage = routeType == 'ROUND_TRIP'
          ? _roundTripNoRouteUserMessage(edgeMeta)
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
        edgeMeta: edgeMeta,
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
        edgeMeta: edgeMeta,
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

  static String _roundTripNoRouteUserMessage(Map<String, dynamic> edgeMeta) {
    final style = (edgeMeta['requested_style'] ?? edgeMeta['selected_style'])
        ?.toString()
        .toLowerCase();
    final bucketValue = edgeMeta['requested_distance_bucket'];
    final bucket = bucketValue is num
        ? bucketValue.toInt()
        : int.tryParse(bucketValue?.toString() ?? '');
    final coverageStatus = edgeMeta['coverage_status']?.toString();
    final healingStatus = edgeMeta['healing_status']?.toString();
    final realBudgetPaused = _edgeMetaIndicatesRealBudgetPause(edgeMeta);
    if (edgeMeta['search_in_progress'] == true ||
        edgeMeta['response_code']?.toString() == 'search_in_progress') {
      return 'Wir berechnen eine bessere Route. Das kann bei dieser Einstellung 1-2 Minuten dauern.';
    }
    if (edgeMeta['response_code']?.toString() == 'search_session_no_route') {
      return 'Wir haben mehrere Varianten geprüft, aber gerade keine sichere Route gefunden. Wir versuchen es im Hintergrund weiter.';
    }
    if (healingStatus == 'healing_running') {
      return 'Wir erstellen gerade neue Vorschläge für diese Einstellung. Bitte versuche es gleich erneut.';
    }
    if (healingStatus == 'healing_failed_cooldown') {
      return 'Für diese Einstellung war gerade keine gute Route möglich. Wir versuchen es später automatisch erneut.';
    }
    if (healingStatus == 'healing_paused_budget' && realBudgetPaused) {
      return 'Heute wurden viele Routenvorschläge berechnet. Wir begrenzen neue Suchen kurzzeitig.';
    }
    if (healingStatus == 'healing_paused_budget') {
      return 'Neue Vorschläge für diese Einstellung sind eingeplant. Wir starten den Aufbau automatisch.';
    }
    if (healingStatus == 'hard_region_curated_needed') {
      return 'Diese Kombination ist in deiner Umgebung schwierig. Versuche eine andere Länge oder einen anderen Stil.';
    }
    final bootstrapPending =
        edgeMeta['pool_bootstrap_pending'] == true ||
        edgeMeta['seed_job_created'] == true ||
        coverageStatus == 'empty' ||
        coverageStatus == 'thin' ||
        coverageStatus == 'warming_up';
    if (bootstrapPending) {
      return 'Für diese Länge und diesen Stil gibt es hier gerade noch keine stabile Route. Wir suchen weiter nach passenden Varianten.';
    }
    if (style != null && style.contains('kurven')) {
      return 'Kurvenjagd ist hier gerade schwer verfügbar. Wir suchen weiter nach einer passenden kurvigen Route.';
    }
    if (bucket != null && bucket >= 75) {
      return 'Für diese Länge gibt es hier gerade keine stabile Rundroute. Bitte später erneut versuchen oder eine kürzere Länge wählen.';
    }
    return 'Kein passender Rundkurs gefunden. Bitte ändere Stil, Länge oder Standort.';
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
  List<RouteManeuver> filterManeuvers(
    List<RouteManeuver> maneuvers, {
    int? routeCoordinateCount,
  }) {
    if (maneuvers.isEmpty) return maneuvers;

    // Finde den letzten Arrive-Index (= echtes Ziel)
    int lastArriveIndex = -1;
    final minFinalArriveRouteIndex = routeCoordinateCount == null
        ? null
        : math.max(0, routeCoordinateCount - 4);
    for (var i = maneuvers.length - 1; i >= 0; i--) {
      final maneuver = maneuvers[i];
      if (maneuver.icon == Icons.flag &&
          (minFinalArriveRouteIndex == null ||
              maneuver.routeIndex >= minFinalArriveRouteIndex)) {
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
    meta['pool_exact_bucket_missing'] = lastRoutePoolExactBucketMissing;
    meta['alternative_distance_offered'] = lastRouteAlternativeDistanceOffered;
    meta['requested_distance_bucket'] = lastRouteRequestedDistanceBucket;
    meta['returned_distance_bucket'] = lastRouteReturnedDistanceBucket;
    meta['access_leg_used'] = lastRouteAccessLegUsed;
    meta['access_leg_distance_km'] = lastRouteAccessLegDistanceKm;
    meta['dead_end_spike_detected'] = RouteQualityValidator.detectDeadEndSpikes(
      result.coordinates,
    ).isNotEmpty;
    meta['mapboxCallCount'] = lastRouteApiCallCount;
    meta['mapbox_call_count'] = lastRouteApiCallCount;
    meta['liveGenerationCostUnits'] = lastRouteApiCallCount;
    final avoidHighwaysRequested =
        meta['avoid_highways_requested'] == true ||
        meta['avoid_highways'] == true;
    meta['highway_allowed'] = !avoidHighwaysRequested;
    meta['motorway_policy'] = avoidHighwaysRequested
        ? 'exclude_motorway'
        : 'allowed_not_required';
    meta['actual_has_highway'] ??= meta['has_highway'];
    meta['actual_avoids_highway'] ??= meta['avoids_highway'];
    meta['cross_cell_highway_fallback'] ??=
        !avoidHighwaysRequested && meta['avoids_highway'] == true;
    meta['source_decision'] = lastRouteSourceDecision;
    meta['live_attempted'] = lastRouteApiCallCount > 0;
    meta['live_attempt_reason'] = lastRouteApiCallCount > 0
        ? (lastRouteLiveAttemptReason ?? 'route_generation')
        : (lastRouteGenerationSource == 'pool' ? 'pool_first' : 'not_needed');
    meta['live_attempt_result'] = lastRouteApiCallCount > 0
        ? (lastRouteGenerationSource == 'mapbox' ? 'success' : 'not_selected')
        : 'not_attempted';
    meta['live_fill_attempted'] = lastRouteApiCallCount > 0;
    meta['live_fill_attempt_count'] = lastRouteApiCallCount;
    meta['live_fill_success'] = lastRouteGenerationSource == 'mapbox';
    meta['pool_candidate_count'] = lastRoutePoolCandidateCount;
    meta['pool_seen_candidate_count'] = lastRoutePoolSeenCandidateCount;
    meta['pool_used_reason'] = lastRoutePoolUsedReason;
    meta['duplicate_skipped'] = lastRouteDuplicateSkipped;
    meta['duplicateFallbackUsed'] = lastRouteDuplicateFallbackUsed;
    meta['duplicate_fallback_used'] = lastRouteDuplicateFallbackUsed;
    meta['previous_route_fingerprints'] = lastRoutePreviousFingerprints;
    meta['last_10_route_fingerprints'] = lastRoutePreviousFingerprints
        .take(10)
        .toList(growable: false);
    meta['last_5_route_fingerprints'] = lastRoutePreviousFingerprints
        .take(5)
        .toList(growable: false);
    meta['last10_excluded_count'] = lastRoutePreviousFingerprints.length;
    meta['last5_excluded_count'] = lastRoutePreviousFingerprints.length;
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
    meta['candidate_saved'] = lastRouteCandidateInserted;
    meta['candidate_save_failed'] = lastRouteCandidateSaveFailed;
    meta['candidate_duplicate_fingerprint'] =
        lastRouteCandidateDuplicateFingerprint;
    meta['candidate_duplicate_source'] = lastRouteCandidateDuplicateSource;
    meta['candidate_coverage_refresh_failed'] =
        lastRouteCandidateCoverageRefreshFailed;
    meta['candidate_save_error_type'] = lastRouteCandidateSaveErrorType;
    meta['candidate_save_error_code'] = lastRouteCandidateSaveErrorCode;
    meta['candidate_save_error_reason'] = lastRouteCandidateSaveErrorReason;
    meta['candidate_save_skipped_reason'] = lastRouteCandidateSaveSkippedReason;
    meta['temporary_candidate'] = lastRouteTemporaryCandidate;
    meta['safe_acceptable_candidate'] = lastRouteTemporaryCandidate;
    meta['verified_inserted'] = lastRouteVerifiedInserted;
    meta['hard_region_exploration_used'] = lastRouteHardRegionExplorationUsed;
    meta['moving_start_detected'] = lastRouteMovingStartDetected;
    meta['start_snap_strategy'] = lastRouteStartSnapStrategy;
    meta['start_on_motorway'] = lastRouteStartOnMotorway;
    meta['avoid_maneuver_radius_used'] = lastRouteAvoidManeuverRadiusUsed;
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
      'pool_exact_bucket_missing': lastRoutePoolExactBucketMissing,
      'alternative_distance_offered': lastRouteAlternativeDistanceOffered,
      'requested_distance_bucket': lastRouteRequestedDistanceBucket,
      'returned_distance_bucket': lastRouteReturnedDistanceBucket,
      'access_leg_used': lastRouteAccessLegUsed,
      'access_leg_distance_km': lastRouteAccessLegDistanceKm,
      'dead_end_spike_detected': meta['dead_end_spike_detected'],
      'mapbox_attempt_count': lastRouteApiCallCount,
      'mapbox_call_count': lastRouteApiCallCount,
      'live_attempted': meta['live_attempted'],
      'live_attempt_reason': meta['live_attempt_reason'],
      'live_attempt_result': meta['live_attempt_result'],
      'live_fill_attempted': meta['live_fill_attempted'],
      'live_fill_attempt_count': meta['live_fill_attempt_count'],
      'live_fill_success': meta['live_fill_success'],
      'source_decision': meta['source_decision'],
      'route_fingerprint': lastRouteDebugFingerprint,
      'previous_fingerprints': lastRoutePreviousFingerprints,
      'last_10_route_fingerprints': meta['last_10_route_fingerprints'],
      'last_5_route_fingerprints': meta['last_5_route_fingerprints'],
      'last10_excluded_count': meta['last10_excluded_count'],
      'last5_excluded_count': meta['last5_excluded_count'],
      'similarity_to_previous_percent': lastRouteSimilarityToPreviousPercent,
      'duplicate_skipped': lastRouteDuplicateSkipped,
      'duplicate_fallback_used': lastRouteDuplicateFallbackUsed,
      'pool_candidate_count': lastRoutePoolCandidateCount,
      'pool_seen_candidate_count': lastRoutePoolSeenCandidateCount,
      'pool_used_reason': lastRoutePoolUsedReason,
      'subscription_tier': lastRouteSubscriptionTier,
      'coverage_status': lastRouteCoverageStatus,
      'seed_job_created': lastRouteSeedJobCreated,
      'duplicate_job_prevented': lastRouteDuplicateSeedJobPrevented,
      'pool_bootstrap_pending': lastRoutePoolBootstrapPending,
      'region_difficulty': lastRouteRegionDifficulty,
      'hard_region_status': lastRouteHardRegionStatus,
      'chosen_cluster': lastRouteChosenCluster,
      'candidate_inserted': lastRouteCandidateInserted,
      'candidate_saved': lastRouteCandidateInserted,
      'candidate_save_failed': lastRouteCandidateSaveFailed,
      'candidate_duplicate_fingerprint': lastRouteCandidateDuplicateFingerprint,
      'candidate_duplicate_source': lastRouteCandidateDuplicateSource,
      'candidate_coverage_refresh_failed':
          lastRouteCandidateCoverageRefreshFailed,
      'candidate_save_error_type': lastRouteCandidateSaveErrorType,
      'candidate_save_error_code': lastRouteCandidateSaveErrorCode,
      'candidate_save_error_reason': lastRouteCandidateSaveErrorReason,
      'candidate_save_skipped_reason': lastRouteCandidateSaveSkippedReason,
      'temporary_candidate': lastRouteTemporaryCandidate,
      'safe_acceptable_candidate': lastRouteTemporaryCandidate,
      'verified_inserted': lastRouteVerifiedInserted,
      'hard_region_exploration_used': lastRouteHardRegionExplorationUsed,
      'moving_start_detected': lastRouteMovingStartDetected,
      'start_snap_strategy': lastRouteStartSnapStrategy,
      'start_on_motorway': lastRouteStartOnMotorway,
      'avoid_maneuver_radius_used': lastRouteAvoidManeuverRadiusUsed,
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
    if (typ == 'roundabout' || typ == 'rotary' || typ == 'roundabout turn') {
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

  final start = currentIndex.clamp(0, coordinates.length - 1).toInt();
  final end = math.min(start + windowSize, coordinates.length - 1);

  var nearestIndex = start;
  var nearestDistance = double.infinity;
  int? nearestSegmentIndex;
  double? nearestSegmentFraction;

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

  for (var i = start; i < end; i++) {
    final from = coordinates[i];
    final to = coordinates[i + 1];
    if (from.length < 2 || to.length < 2) continue;

    final projection = _projectPositionOnRouteSegment(
      position: position,
      from: from,
      to: to,
    );
    if (projection.distanceMeters < nearestDistance) {
      nearestDistance = projection.distanceMeters;
      nearestSegmentIndex = i;
      nearestSegmentFraction = projection.fraction;
      nearestIndex = projection.fraction >= 0.5 ? i + 1 : i;
    }
  }

  // Wenn das Match weit weg von der Route liegt, den Index nicht nach vorne
  // springen lassen. Distanz bleibt erhalten für Off-Route-Erkennung.
  if (nearestDistance > maxJumpMeters) {
    return RouteWindowMatch(
      index: start,
      distanceMeters: nearestDistance,
      segmentIndex: nearestSegmentIndex,
      segmentFraction: nearestSegmentFraction,
    );
  }

  return RouteWindowMatch(
    index: nearestIndex,
    distanceMeters: nearestDistance,
    segmentIndex: nearestSegmentIndex,
    segmentFraction: nearestSegmentFraction,
  );
}

class _RouteSegmentProjection {
  const _RouteSegmentProjection({
    required this.distanceMeters,
    required this.fraction,
  });

  final double distanceMeters;
  final double fraction;
}

_RouteSegmentProjection _projectPositionOnRouteSegment({
  required geo.Position position,
  required List<double> from,
  required List<double> to,
}) {
  const metersPerDegreeLat = 111320.0;
  final metersPerDegreeLng =
      metersPerDegreeLat * math.cos(position.latitude * math.pi / 180.0);

  final ax = (from[0] - position.longitude) * metersPerDegreeLng;
  final ay = (from[1] - position.latitude) * metersPerDegreeLat;
  final bx = (to[0] - position.longitude) * metersPerDegreeLng;
  final by = (to[1] - position.latitude) * metersPerDegreeLat;

  final dx = bx - ax;
  final dy = by - ay;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) {
    return _RouteSegmentProjection(
      distanceMeters: math.sqrt(ax * ax + ay * ay),
      fraction: 0.0,
    );
  }

  final fraction = ((-ax * dx - ay * dy) / lengthSquared)
      .clamp(0.0, 1.0)
      .toDouble();
  final closestX = ax + dx * fraction;
  final closestY = ay + dy * fraction;
  return _RouteSegmentProjection(
    distanceMeters: math.sqrt(closestX * closestX + closestY * closestY),
    fraction: fraction,
  );
}
