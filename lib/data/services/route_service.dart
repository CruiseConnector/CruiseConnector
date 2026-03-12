import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

/// Service für die Routenberechnung via Supabase Edge Function.
class RouteService {
  const RouteService();

  static const String _edgeFunction = 'generate-cruise-route';

  // ─────────────────────────── Public API ────────────────────────────────────

  /// Berechnet eine Rundkurs-Route von der aktuellen Position.
  Future<RouteResult> generateRoundTrip({
    required geo.Position startPosition,
    required int targetDistanceKm,
    required String mode,
    required String planningType,
    Map<String, double>? targetLocation,
  }) async {
    final body = <String, dynamic>{
      'startLocation': {
        'latitude': startPosition.latitude,
        'longitude': startPosition.longitude,
      },
      'targetDistance': targetDistanceKm,
      'mode': mode,
      'route_type': 'ROUND_TRIP',
      'planning_type': planningType,
      if (targetLocation != null) 'targetLocation': targetLocation,
    };
    final result = await _invoke(body);
    // Snap Route-Start und Ende auf exakte GPS-Position (verhindert Kreis-Bug)
    return _snapRouteToStartPosition(result, startPosition);
  }

  /// Berechnet eine Route von A nach B (direkt oder scenic).
  Future<RouteResult> generatePointToPoint({
    required geo.Position startPosition,
    required double destinationLat,
    required double destinationLng,
    required String mode,
    bool scenic = false,
    int routeVariant = 0,
  }) async {
    final body = <String, dynamic>{
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
      if (scenic) ...{
        'targetDistance': 50 + (routeVariant * 10), // Unterschiedliche Ziel-Distanzen
        'randomSeed': routeVariant, // Für Backend: verschiedene Algorithmen/Parameter
      },
    };
    final result = await _invoke(body);
    // Snap Route-Start auf exakte GPS-Position (verhindert Kreis-Bug)
    return _snapRouteToStartPosition(result, startPosition);
  }

  // ──────────────────────────── Internal ─────────────────────────────────────

  Future<RouteResult> _invoke(Map<String, dynamic> body) async {
    final response = await Supabase.instance.client.functions.invoke(
      _edgeFunction,
      body: body,
    );

    final data = response.data;
    if (data == null || data['error'] != null) {
      throw Exception(data?['error'] ?? 'Unbekannter Fehler bei der Berechnung.');
    }

    final geometry = Map<String, dynamic>.from(data['route']['geometry'] as Map);
    final coordinates = extractCoordinates(geometry);
    final maneuvers = extractManeuvers(data, coordinates);

    final distanceRaw = (data['route']['distance'] as num?)?.toDouble();
    final durationRaw = (data['route']['duration'] as num?)?.toDouble();
    final distanceKmRaw = (data['meta']?['distance_km'] as num?)?.toDouble();

    return RouteResult(
      geoJson: json.encode(geometry),
      geometry: geometry,
      coordinates: coordinates,
      maneuvers: maneuvers.where((m) => m.icon != Icons.u_turn_left).toList(),
      distanceMeters: distanceRaw,
      durationSeconds: durationRaw,
      distanceKm: distanceKmRaw,
    );
  }

  // ─────────────────────── Coordinate Helpers ────────────────────────────────

  /// Extrahiert Koordinaten-Liste aus einem GeoJSON-Geometry-Objekt.
  List<List<double>> extractCoordinates(Map<String, dynamic> geometry) {
    final raw = (geometry['coordinates'] as List?) ?? const [];
    return raw
        .whereType<List>()
        .where((c) => c.length >= 2)
        .map(
          (c) => [
            (c[0] as num).toDouble(),
            (c[1] as num).toDouble(),
          ],
        )
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

        // Depart und Arrive-Steps überspringen
        final type = (maneuver['type'] as String?) ?? '';
        if (type == 'arrive' || type == 'depart') continue;

        // Prüfe Distanz zum vorherigen Maneuver (vermeide Kreise am Start)
        final distance = (step['distance'] as num?)?.toDouble() ?? 0;
        if (distance < 50) continue; // Überspringe zu kurze Segmente

        final location = maneuver['location'];
        if (location is! List || location.length < 2) continue;

        final longitude = (location[0] as num).toDouble();
        final latitude = (location[1] as num).toDouble();
        final modifier = (maneuver['modifier'] as String?) ?? '';
        final rawInstruction =
            (maneuver['instruction'] as String?) ??
            (step['name'] as String?) ??
            _announcementForModifier(modifier);

        final routeIndex = _findNearestIndex(latitude, longitude, routeCoordinates);

        maneuvers.add(
          RouteManeuver(
            latitude: latitude,
            longitude: longitude,
            routeIndex: routeIndex,
            icon: _iconForModifier(modifier),
            announcement: _announcementFromInstruction(rawInstruction, modifier, distance),
            instruction: _normalizeInstruction(rawInstruction, modifier),
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

  // ────────────────────── Icon / Text Helpers ────────────────────────────────

  IconData _iconForModifier(String modifier) {
    switch (modifier.toLowerCase()) {
      case 'left':
      case 'slight left':
      case 'sharp left':
        return Icons.turn_left;
      case 'right':
      case 'slight right':
      case 'sharp right':
        return Icons.turn_right;
      case 'uturn':
      case 'uturn left':
      case 'uturn right':
        return Icons.u_turn_left;
      default:
        return Icons.straight;
    }
  }

  /// Formatiert Distanz lesbar (z.B. 6385m → 6,4 km)
  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return 'In ${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
    } else {
      return 'In ${meters.toInt()} m';
    }
  }

  String _announcementForModifier(String modifier, {double? distance}) {
    final distText = distance != null ? _formatDistance(distance) : 'In 100 m';
    switch (modifier.toLowerCase()) {
      case 'left':
      case 'slight left':
      case 'sharp left':
        return '$distText links abbiegen';
      case 'right':
      case 'slight right':
      case 'sharp right':
        return '$distText rechts abbiegen';
      case 'uturn':
      case 'uturn left':
      case 'uturn right':
        return '$distText bitte wenden';
      default:
        return '$distText geradeaus weiterfahren';
    }
  }

  String _normalizeInstruction(String instruction, String modifier) {
    final trimmed = instruction.trim();
    return trimmed.isEmpty ? _announcementForModifier(modifier) : trimmed;
  }

  String _announcementFromInstruction(String instruction, String modifier, double distance) {
    return '${_formatDistance(distance)} ${_normalizeInstruction(instruction, modifier)}';
  }

  // ─────────────────────── Route Snapping ───────────────────────────────────

  /// Snappt den ersten (und letzten bei Rundkurs) Routenpunkt auf die exakte Startposition.
  /// Verhindert den Kreis-Bug am Routenanfang.
  RouteResult _snapRouteToStartPosition(RouteResult result, geo.Position startPosition) {
    if (result.coordinates.isEmpty) return result;
    
    final snappedCoordinates = List<List<double>>.from(result.coordinates);
    final startLng = startPosition.longitude;
    final startLat = startPosition.latitude;
    
    // Ersten Punkt auf exakte Position snap
    snappedCoordinates[0] = [startLng, startLat];
    
    // Bei Rundkurs: Letzten Punkt auch auf Startposition snap
    if (snappedCoordinates.length > 1) {
      final firstPoint = result.coordinates.first;
      final lastPoint = result.coordinates.last;
      final distanceBetween = geo.Geolocator.distanceBetween(
        firstPoint[1], firstPoint[0], lastPoint[1], lastPoint[0],
      );
      // Wenn Start und Ende nahe beieinander (Rundkurs), snap Ende auch
      if (distanceBetween < 500) {
        snappedCoordinates.last = [startLng, startLat];
      }
    }
    
    // Update geometry mit neuen Koordinaten
    final newGeometry = Map<String, dynamic>.from(result.geometry);
    newGeometry['coordinates'] = snappedCoordinates;
    
    return RouteResult(
      geoJson: json.encode(newGeometry),
      geometry: newGeometry,
      coordinates: snappedCoordinates,
      maneuvers: result.maneuvers,
      distanceMeters: result.distanceMeters,
      durationSeconds: result.durationSeconds,
      distanceKm: result.distanceKm,
    );
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

  return RouteWindowMatch(index: nearestIndex, distanceMeters: nearestDistance);
}
