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
import 'package:cruise_connect/data/services/route_generation_coordinator.dart';
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
  RouteService({RouteEdgeInvoker? invoker})
    : _invoker = invoker ?? const SupabaseRouteInvoker();

  static const String edgeFunction = 'generate-cruise-route';
  static int _lastRandomSeed = 0;
  static const String _explorerBearingPrefsKey =
      'route_service_recent_explorer_bearings';
  static const String _lastSuccessfulRouteKey = 'route_service_last_successful_route';
  
  /// Flag: letzte Route kam aus dem Offline-Cache
  static bool lastRouteFromCache = false;

  /// Letzte 3 Entdecker-Richtungen (in Grad) für Diversifizierung.
  // TODO: In SharedPreferences persistieren für Session-übergreifende Diversifizierung
  static final List<double> _recentExplorerBearings = [];
  static const RouteQualityValidator _qualityValidator =
      RouteQualityValidator();
  static final Map<String, int> _scenarioVariantCounters = {};

  /// Session-Cache: verhindert doppelte API-Calls für identische Anfragen.
  /// Key = konkrete Variant-/Request-Signatur, Value = RouteResult.
  static final Map<String, RouteResult> _sessionCache = {};
  
  /// Globaler Request-Zähler als Fallback für Legacy-Aufrufer.
  static int _globalDiversityIndex = 0;
  
  /// WORKER_LIMIT Cooldown: Nach diesem Fehler keine neuen Requests für X ms.
  static DateTime? _workerLimitCooldownUntil;

  final RouteEdgeInvoker _invoker;

  // ─────────────────────────── Public API ────────────────────────────────────

  static bool requiresDestination(String routeType) {
    return routeType == 'POINT_TO_POINT';
  }

  @visibleForTesting
  static bool disableBackgroundPreparation = false;

  @visibleForTesting
  static void resetForTests() {
    _sessionCache.clear();
    _scenarioVariantCounters.clear();
    _globalDiversityIndex = 0;
    _workerLimitCooldownUntil = null;
    SeenRouteRegistry.clearAll();
    PreparedRouteBuffer.clearAll();
  }

  /// Berechnet eine Rundkurs-Route von der aktuellen Position.
  ///
  /// Sendet einen `direction_hint` (0-359°) an die Edge Function, der die
  /// Hauptrichtung der Route bestimmt. Jede Generierung bekommt einen anderen
  /// Winkel → echte Rundkurse in verschiedene Richtungen.
  ///
  /// Post-Validierung prüft: Overlap (<20%), U-Turns, Distanz (±15%),
  /// und stilspezifische Kriterien (Kurvenjagd: genug Kurven, Abendrunde: langsam).
  Future<RouteResult> generateRoundTrip({
    required geo.Position startPosition,
    required int targetDistanceKm,
    required String mode,
    required String planningType,
    Map<String, double>? targetLocation,
    int? variantIndex,
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
    );

    return RouteGenerationCoordinator.runSingleFlight(
      scenario.scenarioKey,
      () async {
        final prepared = _takePreparedRoute(
          scenario: scenario,
        );
        if (prepared != null) {
          return prepared;
        }

        final hasSeenHistory = SeenRouteRegistry.entriesFor(
          scenario.scenarioKey,
        ).isNotEmpty;
        final maxAttempts = hasSeenHistory
            ? math.min(3, math.max(2, styleConfig.retryAttempts))
            : 1;
        _RouteCandidate? bestCandidate;
        _RouteCandidate? spareCandidate;
        var bestScore = double.infinity;
        RouteServiceException? lastError;

        for (var attempt = 0; attempt < maxAttempts; attempt++) {
          if (_isInWorkerLimitCooldown()) break;
          final variant = await _nextRoundTripVariant(
            scenario,
            styleConfig: styleConfig,
            explicitIndex: attempt == 0 ? variantIndex : null,
          );
          try {
            final candidate = await _requestRoundTripVariant(
              scenario: scenario,
              styleConfig: styleConfig,
              startPosition: startPosition,
              targetLocation: targetLocation,
              variant: variant,
              candidateBudget: hasSeenHistory ? 4 : 5,
            );
            if (!candidate.hardRejected && candidate.score < bestScore) {
              if (bestCandidate != null && candidate.accepted) {
                spareCandidate ??= candidate;
              }
              bestCandidate = candidate;
              bestScore = candidate.score;
            } else if (candidate.accepted) {
              spareCandidate ??= candidate;
            }
            if (candidate.accepted) {
              final finalized = _finalizeAndRemember(
                scenario: scenario,
                route: candidate.route,
                sampledCoordinates: candidate.sampledCoordinates,
                fingerprint: candidate.fingerprint,
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
              } else if (!hasSeenHistory) {
                _schedulePreparedRoundTripRoute(
                  scenario: scenario,
                  styleConfig: styleConfig,
                  startPosition: startPosition,
                );
              }
              return finalized;
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
          }
        }

        if (bestCandidate != null) {
          return _finalizeAndRemember(
            scenario: scenario,
            route: bestCandidate.route,
            sampledCoordinates: bestCandidate.sampledCoordinates,
            fingerprint: bestCandidate.fingerprint,
          );
        }

        final fallback = await _tryRoundTripFallback(
          scenario: scenario,
          styleConfig: styleConfig,
          startPosition: startPosition,
          targetLocation: targetLocation,
        );
        if (fallback != null) {
          return fallback;
        }

        final cached = await _loadCachedRoute(
          scenarioKey: scenario.scenarioKey,
        );
        if (cached != null) {
          lastRouteFromCache = true;
          return cached;
        }

        throw lastError ??
            const RouteServiceException(
              type: RouteErrorType.quality,
              userMessage:
                  'Kein passender Rundkurs gefunden. Bitte versuche es erneut.',
              debugMessage:
                  'RoundTrip generation failed without usable result.',
            );
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
  }) async {
    final styleConfig = RouteStyleConfig.forMode(mode);
    final normalizedVariant = routeVariant.clamp(0, 3);
    final detourFactor = switch (normalizedVariant) {
      1 => 1.24,
      2 => 1.52,
      3 => 1.92,
      _ => scenic ? 1.15 : 1.0,
    };
    final detourMinimumExtraKm = switch (normalizedVariant) {
      1 => 5.0,
      2 => 12.0,
      3 => 24.0,
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
      1 => directDistanceKm * 1.24,
      2 => directDistanceKm * 1.50,
      3 => directDistanceKm * 1.88,
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

    return RouteGenerationCoordinator.runSingleFlight(
      scenario.scenarioKey,
      () async {
        final prepared = _takePreparedRoute(
          scenario: scenario,
        );
        if (prepared != null) {
          return prepared;
        }

        final hasSeenHistory = SeenRouteRegistry.entriesFor(
          scenario.scenarioKey,
        ).isNotEmpty;
        final maxAttempts = shouldDiversify
            ? 2
            : (hasSeenHistory ? 2 : 1);
        _RouteCandidate? bestCandidate;
        _RouteCandidate? spareCandidate;
        var bestScore = double.infinity;
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
              candidateBudget: hasSeenHistory ? 3 : 4,
            );
            if (!candidate.hardRejected && candidate.score < bestScore) {
              if (bestCandidate != null && candidate.accepted) {
                spareCandidate ??= candidate;
              }
              bestCandidate = candidate;
              bestScore = candidate.score;
            } else if (candidate.accepted) {
              spareCandidate ??= candidate;
            }
            if (candidate.accepted) {
              final finalized = _finalizeAndRemember(
                scenario: scenario,
                route: candidate.route,
                sampledCoordinates: candidate.sampledCoordinates,
                fingerprint: candidate.fingerprint,
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
              } else if (shouldDiversify) {
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
          }
        }

        if (bestCandidate != null) {
          return _finalizeAndRemember(
            scenario: scenario,
            route: bestCandidate.route,
            sampledCoordinates: bestCandidate.sampledCoordinates,
            fingerprint: bestCandidate.fingerprint,
          );
        }

        final fallback = await _tryPointToPointFallback(
          scenario: scenario,
          startPosition: startPosition,
          destinationLat: destinationLat,
          destinationLng: destinationLng,
          avoidHighways: avoidHighways,
          directDistanceKm: directDistanceKm,
        );
        if (fallback != null) {
          return fallback;
        }

        final cached = await _loadCachedRoute(
          scenarioKey: scenario.scenarioKey,
        );
        if (cached != null) {
          lastRouteFromCache = true;
          return cached;
        }

        throw lastError ??
            const RouteServiceException(
              type: RouteErrorType.noRoute,
              userMessage:
                  'Keine passende Route gefunden. Bitte versuche es erneut.',
              debugMessage: 'Point-to-point generation failed without result.',
            );
      },
    );
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
    debugPrint('[RouteService] ⚠️ WORKER_LIMIT erkannt — 8s Cooldown aktiviert');
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
  @Deprecated('Nutze generateSequentialRoundTrips() — parallele Requests verursachen WORKER_LIMIT')
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
  @Deprecated('Nutze generateSequentialPointToPoints() — parallele Requests verursachen WORKER_LIMIT')
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
    int candidateBudget = 6,
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
      ...styleConfig.toRequestHints(),
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

  Future<RouteResult> _invoke(Map<String, dynamic> body) async {
    final requestUrl = '${AppConstants.supabaseUrl}/functions/v1/$edgeFunction';
    final routeType = body['route_type']?.toString() ?? 'ROUND_TRIP';
    final mode = body['mode'];
    final planningType = body['planning_type'];
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
      debugPrint('[RouteService] 📦 Cache-Hit — kein neuer API-Call nötig');
      return cached;
    }

    // Request-ID für Monitoring
    final requestTimestamp = DateTime.now().millisecondsSinceEpoch;
    body['request_id'] = 'cruiseconnect_$requestTimestamp';
    debugPrint('[RouteService] 🗺️ Mapbox Request #$requestTimestamp gesendet');
    final stopwatch = Stopwatch()..start();

    dynamic data;
    int? statusCode;
    RouteServiceException? lastMappedError;
    // Exponential Backoff: nur bei HTTP 429/5xx
    const maxRetries = 3;
    final retryRng = math.Random();
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final rawResponse = await _invoker
            .invoke(body)
            .timeout(const Duration(seconds: 15));
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
        // Exponential Backoff + Jitter
        final baseDelayMs = math.pow(2, attempt - 1).toInt() * 1000;
        final jitterMs = retryRng.nextInt(450);
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

    stopwatch.stop();
    debugPrint(
      '[RouteService] ✅ Route erhalten nach ${stopwatch.elapsedMilliseconds}ms',
    );

    final routeResult = RouteResult(
      geoJson: json.encode(geometry),
      geometry: geometry,
      coordinates: coordinates,
      maneuvers: maneuvers,
      distanceMeters: distanceRaw,
      durationSeconds: durationRaw,
      distanceKm: distanceKmActual,
      speedLimits: speedLimits,
    );
    _sessionCache[cacheKey] = routeResult;
    return routeResult;
  }

  static bool _isRetryable(RouteServiceException error) {
    // Nur HTTP 429 (Rate Limit) und 5xx (Server) → exponential backoff.
    // Timeout/Netzwerk-Fehler werden NICHT retried — Caller macht Fallback.
    return error.type == RouteErrorType.rateLimit ||
        error.type == RouteErrorType.server ||
        error.type == RouteErrorType.workerLimit;
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
    final variantHint = body['route_variant_hint'] ?? body['variant_hint'] ?? '';
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
    final angleOffset = (baseDirection + (index * 43.0)) % 360;
    return RouteVariant(
      index: index,
      seed: seed,
      angleOffset: angleOffset,
      radiusJitter: radiusJitter,
      offsetBearing: angleOffset,
      fingerprintHint:
          '${scenario.scenarioKey}|rt|$index|${angleOffset.round()}|${(radiusJitter * 100).round()}',
      variantHint:
          'rt-${styleConfig.profileKey}-${index % 8}-${(angleOffset / 45).round()}',
      styleBias: styleConfig.profileKey,
    );
  }

  RouteVariant _nextPointToPointVariant(
    RouteScenario scenario, {
    required int normalizedVariant,
    required int diversitySeed,
    required bool shouldDiversify,
  }) {
    final index = _nextScenarioVariantIndex(scenario.scenarioKey) + diversitySeed;
    final seed = _nextRandomSeed() + index * 53;
    final rng = math.Random(seed);
    final offsetBearingBase = switch (normalizedVariant) {
      1 => 28.0,
      2 => 52.0,
      3 => 76.0,
      _ => 16.0,
    };
    final offsetBearing =
        offsetBearingBase + ((rng.nextDouble() - 0.5) * 18.0);
    final radiusJitter = switch (normalizedVariant) {
      1 => 1.04 + rng.nextDouble() * 0.08,
      2 => 1.10 + rng.nextDouble() * 0.12,
      3 => 1.18 + rng.nextDouble() * 0.16,
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
    );
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
  }) {
    final actualDistanceKm = route.distanceKm ?? 0.0;
    final sampledCoordinates = _sampleRouteForSimilarity(route.coordinates);
    final fingerprint = RouteQualityValidator.buildRouteFingerprint(
      sampledCoordinates,
      distanceKm: route.distanceKm,
      precision: 4,
    );
    final quality = _qualityValidator.validateQuality(
      coordinates: route.coordinates,
      isRoundTrip: scenario.isRoundTrip,
      targetDistanceKm: scenario.targetDistanceKm ?? 0.0,
      actualDistanceKm: actualDistanceKm,
    );
    final classification = _qualityValidator.classifyGeneratedRoute(
      quality: quality,
      isRoundTrip: scenario.isRoundTrip,
      coordinateCount: route.coordinates.length,
      actualDistanceKm: actualDistanceKm,
      targetDistanceKm: scenario.targetDistanceKm ?? 0.0,
    );
    final styleOk = styleConfig.validateStyleQuality(
      coordinates: route.coordinates,
      distanceKm: actualDistanceKm,
      durationSeconds: route.durationSeconds,
    );
    final similarityThreshold = _similarityThresholdForScenario(scenario);
    final tooSimilar =
        SeenRouteRegistry.hasExactFingerprint(scenario.scenarioKey, fingerprint) ||
        SeenRouteRegistry.hasSimilarRoute(
          scenario.scenarioKey,
          sampledCoordinates,
          thresholdPercent: similarityThreshold,
          proximityMeters: scenario.isRoundTrip ? 130.0 : 160.0,
        );
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
    final qualityAcceptable = scenario.isRoundTrip
        ? classification.isAcceptable
        : quality.passed || classification.isAcceptable;
    final softRenderable =
        hasEnoughPoints && detourDistanceOk && !tooSimilar && qualityAcceptable;
    final accepted = softRenderable && styleOk;
    final score =
        classification.score +
        (styleOk ? 0.0 : 18.0) +
        (tooSimilar ? 45.0 : 0.0) +
        (detourDistanceOk ? 0.0 : 35.0) +
        (hasEnoughPoints ? 0.0 : 24.0);

    debugPrint(
      '[RouteService] Candidate ${scenario.routeType} ${variant.variantHint}: '
      'accepted=$accepted, score=${score.toStringAsFixed(1)}, '
      'distance=${actualDistanceKm.toStringAsFixed(1)}km, '
      'overlap=${quality.overlapPercent.toStringAsFixed(1)}%, '
      'uturns=${quality.uturnPositions.length}, tooSimilar=$tooSimilar, '
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
    return actualDistanceKm >= 10 ? 30 : 0;
  }

  double _similarityThresholdForScenario(RouteScenario scenario) {
    if (scenario.isRoundTrip) return 78.0;
    if (scenario.detourLevel <= 0) {
      return scenario.avoidHighways ? 92.0 : 96.0;
    }
    if (scenario.detourLevel == 1) return 76.0;
    if (scenario.detourLevel == 2) return 74.0;
    return 72.0;
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
  }) {
    final entry = PreparedRouteBuffer.take(scenario.scenarioKey);
    if (entry == null) return null;
    final sampled = _sampleRouteForSimilarity(entry.route.coordinates);
    final fingerprint = RouteQualityValidator.buildRouteFingerprint(
      sampled,
      distanceKm: entry.route.distanceKm,
      precision: 4,
    );
    if (SeenRouteRegistry.hasExactFingerprint(scenario.scenarioKey, fingerprint)) {
      return null;
    }
    if (SeenRouteRegistry.hasSimilarRoute(
      scenario.scenarioKey,
      sampled,
      thresholdPercent: _similarityThresholdForScenario(scenario),
      proximityMeters: scenario.isRoundTrip ? 130.0 : 160.0,
    )) {
      return null;
    }
    return _finalizeAndRemember(
      scenario: scenario,
      route: entry.route,
      sampledCoordinates: sampled,
      fingerprint: fingerprint,
    );
  }

  void _schedulePreparedRoundTripRoute({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required geo.Position startPosition,
  }) {
    if (disableBackgroundPreparation) return;
    if (PreparedRouteBuffer.hasFreshEntry(scenario.scenarioKey)) return;
    unawaited(
      Future<void>.delayed(Duration.zero, () async {
        if (!RouteGenerationCoordinator.canPrepare(scenario.scenarioKey)) return;
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
                candidateBudget: 2,
              );
              if (!candidate.accepted) return;
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
    if (disableBackgroundPreparation) return;
    if (PreparedRouteBuffer.hasFreshEntry(scenario.scenarioKey)) return;
    unawaited(
      Future<void>.delayed(Duration.zero, () async {
        if (!RouteGenerationCoordinator.canPrepare(scenario.scenarioKey)) return;
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
              final targetDistanceKm = scenario.targetDistanceKm ?? directDistanceKm;
              final detourFactor = switch (scenario.detourLevel) {
                1 => 1.24,
                2 => 1.52,
                3 => 1.92,
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
                candidateBudget: 2,
              );
              if (!candidate.accepted) return;
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
  }) {
    final finalized = _finalizeRoute(route, scenarioKey: scenario.scenarioKey);
    SeenRouteRegistry.remember(
      scenario.scenarioKey,
      fingerprint: fingerprint,
      sampledCoordinates: sampledCoordinates,
    );
    lastRouteFromCache = false;
    return finalized;
  }

  Future<RouteResult?> _tryRoundTripFallback({
    required RouteScenario scenario,
    required RouteStyleConfig styleConfig,
    required geo.Position startPosition,
    Map<String, double>? targetLocation,
  }) async {
    try {
      final variant = await _nextRoundTripVariant(
        scenario,
        styleConfig: styleConfig,
      );
      final body = _buildRoundTripRequest(
        startPosition: startPosition,
        targetDistanceKm:
            (scenario.targetDistanceKm ?? 50.0).round(),
        mode: scenario.style,
        planningType: scenario.planningType,
        styleConfig: styleConfig,
        variant: variant,
        targetLocation: targetLocation,
        directionHint: variant.angleOffset,
        candidateBudget: 3,
      );
      body['simplify_waypoints'] = true;
      body['max_waypoints'] = 3;
      final result = await _invoke(body);
      final snapped = _snapRouteToStartPosition(result, startPosition);
      final sampled = _sampleRouteForSimilarity(snapped.coordinates);
      final fingerprint = RouteQualityValidator.buildRouteFingerprint(
        sampled,
        distanceKm: snapped.distanceKm,
        precision: 4,
      );
      return _finalizeAndRemember(
        scenario: scenario,
        route: snapped,
        sampledCoordinates: sampled,
        fingerprint: fingerprint,
      );
    } catch (e) {
      debugPrint('[RouteService] Rundkurs-Fallback fehlgeschlagen: $e');
      return null;
    }
  }

  Future<RouteResult?> _tryPointToPointFallback({
    required RouteScenario scenario,
    required geo.Position startPosition,
    required double destinationLat,
    required double destinationLng,
    required bool avoidHighways,
    required double directDistanceKm,
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
          1 => 1.24,
          2 => 1.55,
          3 => 1.92,
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
        scenicBody['max_waypoints'] = scenario.detourLevel >= 3 ? 2 : 1;
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
        if (!scenicCandidate.hardRejected) {
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
      }

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
      final sampled = _sampleRouteForSimilarity(snapped.coordinates);
      final fingerprint = RouteQualityValidator.buildRouteFingerprint(
        sampled,
        distanceKm: snapped.distanceKm,
        precision: 4,
      );
      return _finalizeAndRemember(
        scenario: scenario,
        route: snapped,
        sampledCoordinates: sampled,
        fingerprint: fingerprint,
      );
    } catch (e) {
      debugPrint('[RouteService] A→B-Fallback fehlgeschlagen: $e');
      return null;
    }
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
    final detailsMap = details is Map ? Map<String, dynamic>.from(details) : null;
    final errorCode = detailsMap?['code']?.toString().toUpperCase();
    final retryAfterSec =
        (detailsMap?['retry_after_sec'] as num?)?.toInt();

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
      final cached =
          prefs.getString(scopedKey) ?? prefs.getString(_lastSuccessfulRouteKey);
      if (cached == null) return null;
      
      final data = json.decode(cached) as Map<String, dynamic>;
      final timestamp = data['timestamp'] as int?;
      if (timestamp != null) {
        final age = DateTime.now().millisecondsSinceEpoch - timestamp;
        if (age > 24 * 60 * 60 * 1000) {
          debugPrint('[RouteService] Gecachte Route ist >24h alt, wird ignoriert');
          return null;
        }
      }
      
      final coordinates = (data['coordinates'] as List?)
          ?.map((c) => (c as List).map((v) => (v as num).toDouble()).toList())
          .toList() ?? [];
      
      if (coordinates.length < 2) return null;
      
      debugPrint('[RouteService] 📦 Gecachte Route geladen (${coordinates.length} Punkte)');
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
    final finalized = RouteResult(
      geoJson: result.geoJson,
      geometry: result.geometry,
      coordinates: result.coordinates,
      maneuvers: filterManeuvers(result.maneuvers),
      distanceMeters: result.distanceMeters,
      durationSeconds: result.durationSeconds,
      distanceKm: result.distanceKm,
      speedLimits: result.speedLimits,
    );
    // Asynchron cachen ohne auf Ergebnis zu warten
    _cacheSuccessfulRoute(finalized, scenarioKey: scenarioKey);
    return finalized;
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
    if (trimTo > 0) coords = coords.sublist(trimTo);
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

    // ── Distanz & Dauer aus den BEREINIGTEN Koordinaten neu berechnen ─────
    // Nach Snapping + Loop-Removal können die Koordinaten deutlich kürzer sein
    // als die originale Mapbox-Distanz. Ohne Neuberechnung zeigt die App z.B.
    // 40 km an obwohl die bereinigte Route nur 6 km lang ist.
    double actualDistanceMeters = 0.0;
    for (var i = 0; i < coords.length - 1; i++) {
      actualDistanceMeters += geo.Geolocator.distanceBetween(
        coords[i][1],
        coords[i][0],
        coords[i + 1][1],
        coords[i + 1][0],
      );
    }

    // Sicherheitscheck: Wenn die bereinigte Route weniger als 50% der Mapbox-Distanz
    // hat, wurde zu viel abgeschnitten — Originaldistanz/Dauer beibehalten.
    final origDist = result.distanceMeters ?? actualDistanceMeters;
    final distRatio = origDist > 0 ? actualDistanceMeters / origDist : 1.0;

    final double finalDistanceMeters;
    final double? finalDuration;
    if (distRatio < 0.50 && origDist > 10000) {
      // Zu viel gekürzt — Originaldistanz beibehalten
      debugPrint(
        '[RouteService] Snap/Loop-Fix WARNUNG: Distanz fiel auf ${(distRatio * 100).toStringAsFixed(0)}% — behalte Mapbox-Original (${(origDist / 1000).toStringAsFixed(1)} km)',
      );
      finalDistanceMeters = origDist;
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

    return RouteResult(
      geoJson: json.encode(newGeometry),
      geometry: newGeometry,
      coordinates: coords,
      maneuvers: finalManeuvers,
      distanceMeters: finalDistanceMeters,
      durationSeconds: finalDuration,
      distanceKm: finalDistanceMeters / 1000.0,
      speedLimits: result.speedLimits,
    );
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
  });

  final RouteResult route;
  final RouteVariant variant;
  final String fingerprint;
  final List<List<double>> sampledCoordinates;
  final double score;
  final bool accepted;
  final bool hardRejected;
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
  });

  final RouteErrorType type;
  final String userMessage;
  final String debugMessage;
  final int? statusCode;
  final StackTrace? stackTrace;

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
