import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class RouteElevationSummary {
  const RouteElevationSummary({
    required this.totalClimbMeters,
    required this.totalDescentMeters,
    required this.elevations,
    this.isEstimated = false,
  });

  final double totalClimbMeters;
  final double totalDescentMeters;
  final List<double> elevations;
  final bool isEstimated;

  int get ascentMeters => totalClimbMeters.round();
  int get descentMeters => totalDescentMeters.round();
}

class RouteElevationService {
  const RouteElevationService({http.Client? client}) : _client = client;

  static final Map<String, RouteElevationSummary?> _memoryCache =
      <String, RouteElevationSummary?>{};

  final http.Client? _client;

  static Future<RouteElevationSummary?> summarizeRoute(
    List<List<double>> coordinates,
  ) {
    return const RouteElevationService().fetchSummary(coordinates);
  }

  static RouteElevationSummary? estimateSummaryFromCoordinates(
    List<List<double>> coordinates,
  ) {
    final sampledCoordinates = sampleCoordinates(coordinates, maxPoints: 24);
    if (sampledCoordinates.length < 2) return null;
    final elevations = estimateElevations(sampledCoordinates, sampleCount: 48);
    return summarizeElevations(elevations, isEstimated: true);
  }

  Future<RouteElevationSummary?> getSummary({
    required String routeKey,
    required List<List<double>> coordinates,
  }) async {
    if (_memoryCache.containsKey(routeKey)) {
      return _memoryCache[routeKey];
    }

    final summary = await fetchSummary(coordinates);
    _memoryCache[routeKey] = summary;
    return summary;
  }

  Future<RouteElevationSummary?> fetchSummary(
    List<List<double>> coordinates,
  ) async {
    final sampledCoordinates = sampleCoordinates(coordinates);
    if (sampledCoordinates.length < 2) return null;

    final latitudes = sampledCoordinates
        .map((point) => point[1].toStringAsFixed(5))
        .join(',');
    final longitudes = sampledCoordinates
        .map((point) => point[0].toStringAsFixed(5))
        .join(',');

    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/elevation'
      '?latitude=$latitudes&longitude=$longitudes',
    );

    try {
      final response = _client != null
          ? await _client.get(uri)
          : await http.get(uri);
      if (response.statusCode != 200) {
        debugPrint(
          '[RouteElevation] HTTP ${response.statusCode} beim Laden von $uri',
        );
        return estimateSummaryFromCoordinates(sampledCoordinates);
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final rawElevations = data['elevation'] as List?;
      if (rawElevations == null || rawElevations.length < 2) {
        return estimateSummaryFromCoordinates(sampledCoordinates);
      }

      final elevations = rawElevations
          .whereType<num>()
          .map((value) => value.toDouble())
          .toList();
      return summarizeElevations(elevations);
    } catch (e) {
      debugPrint('[RouteElevation] Fehler beim Laden der Hoehenmeter: $e');
      return estimateSummaryFromCoordinates(sampledCoordinates);
    }
  }

  static List<List<double>> sampleCoordinates(
    List<List<double>> coordinates, {
    int maxPoints = 24,
  }) {
    final validCoordinates = coordinates
        .where((point) => point.length >= 2)
        .map((point) => [point[0], point[1]])
        .toList();
    if (validCoordinates.length <= maxPoints) {
      return validCoordinates;
    }

    final sampled = <List<double>>[];
    for (var i = 0; i < maxPoints; i++) {
      final ratio = maxPoints == 1 ? 0.0 : i / (maxPoints - 1);
      final index = ((validCoordinates.length - 1) * ratio).round();
      sampled.add(validCoordinates[index]);
    }
    return sampled;
  }

  static RouteElevationSummary? summarizeElevations(
    List<double> elevations, {
    double noiseThresholdMeters = 4.0,
    bool isEstimated = false,
  }) {
    if (elevations.length < 2) return null;

    var totalClimb = 0.0;
    var totalDescent = 0.0;

    for (var i = 1; i < elevations.length; i++) {
      final diff = elevations[i] - elevations[i - 1];
      if (diff >= noiseThresholdMeters) {
        totalClimb += diff;
      } else if (diff <= -noiseThresholdMeters) {
        totalDescent += -diff;
      }
    }

    return RouteElevationSummary(
      totalClimbMeters: totalClimb,
      totalDescentMeters: totalDescent,
      elevations: List<double>.unmodifiable(elevations),
      isEstimated: isEstimated,
    );
  }

  static List<double> estimateElevations(
    List<List<double>> coordinates, {
    int sampleCount = 48,
  }) {
    if (coordinates.length < 2) return const [];

    final sampledCoordinates = sampleCoordinates(
      coordinates,
      maxPoints: sampleCount.clamp(8, 64),
    );
    if (sampledCoordinates.length < 2) return const [];

    return sampledCoordinates
        .map((point) {
          final lng = point[0];
          final lat = point[1];
          final baseTerrain =
              math.sin(lat * 13.7) * 85 +
              math.cos(lng * 11.4) * 70 +
              math.sin((lng + lat) * 7.1) * 45;
          return 420 + baseTerrain;
        })
        .toList(growable: false);
  }
}
