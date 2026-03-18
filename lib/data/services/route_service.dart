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
      'language': 'de',
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
      'language': 'de',
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
    debugPrint('[RouteService] Invoking Edge Function with: ${body['planning_type']}, mode: ${body['mode']}');

    dynamic data;
    try {
      final response = await Supabase.instance.client.functions.invoke(
        _edgeFunction,
        body: body,
      );
      data = response.data;
      debugPrint('[RouteService] Response received: ${data?.runtimeType}');
    } catch (e) {
      debugPrint('[RouteService] Edge Function call failed: $e');
      throw Exception('Verbindungsfehler: $e');
    }

    if (data == null) {
      throw Exception('Keine Antwort von der Route-Berechnung erhalten.');
    }

    // Wenn data ein String ist (JSON), parsen
    if (data is String) {
      try {
        data = json.decode(data);
      } catch (e) {
        throw Exception('Ungültige Antwort: $data');
      }
    }

    if (data is! Map) {
      throw Exception('Unerwartetes Antwortformat: ${data.runtimeType}');
    }

    if (data['error'] != null) {
      throw Exception(data['error'].toString());
    }

    if (data['route'] == null) {
      throw Exception('Keine Route in der Antwort gefunden.');
    }

    final route = data['route'] as Map;
    if (route['geometry'] == null) {
      throw Exception('Route enthält keine Geometrie-Daten.');
    }

    final geometry = Map<String, dynamic>.from(route['geometry'] as Map);
    final coordinates = extractCoordinates(geometry);

    if (coordinates.length < 2) {
      throw Exception('Route hat zu wenig Koordinaten (${coordinates.length}).');
    }

    final maneuvers = extractManeuvers(data, coordinates);

    final distanceRaw = (route['distance'] as num?)?.toDouble();
    final durationRaw = (route['duration'] as num?)?.toDouble();
    final distanceKmRaw = (data['meta']?['distance_km'] as num?)?.toDouble();

    debugPrint('[RouteService] Route OK: ${coordinates.length} Punkte, ${distanceKmRaw?.toStringAsFixed(1)} km');

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
        if (distance < 100) continue; // Überspringe zu kurze Segmente (erhöht von 50 auf 100m)

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

        // Kreisverkehr erkennen
        final isRoundabout = type == 'roundabout' ||
            type == 'rotary' ||
            type == 'roundabout turn';
        final exitNumber = isRoundabout
            ? (maneuver['exit'] as num?)?.toInt()
            : null;

        maneuvers.add(
          RouteManeuver(
            latitude: latitude,
            longitude: longitude,
            routeIndex: routeIndex,
            icon: isRoundabout ? Icons.roundabout_left : _iconForManeuver(type, modifier),
            announcement: _announcementFromInstruction(rawInstruction, modifier, distance),
            instruction: isRoundabout
                ? _roundaboutInstruction(exitNumber, rawInstruction, modifier)
                : _normalizeInstruction(rawInstruction, modifier),
            maneuverType: isRoundabout ? ManeuverType.roundabout : ManeuverType.normal,
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

  // ────────────────────── Icon / Text Helpers ────────────────────────────────

  IconData _iconForManeuver(String type, String modifier) {
    // Typen die immer "geradeaus" sind, egal welcher modifier
    const straightTypes = {'new name', 'continue', 'merge', 'on ramp', 'notification'};
    if (straightTypes.contains(type)) {
      // Bei merge/ramp trotzdem Richtung anzeigen wenn stark
      if (type == 'merge' || type == 'on ramp') {
        if (modifier.contains('left')) return Icons.turn_slight_left;
        if (modifier.contains('right')) return Icons.turn_slight_right;
      }
      return Icons.straight;
    }

    switch (modifier.toLowerCase()) {
      case 'left':
        return Icons.turn_left;
      case 'slight left':
        return Icons.turn_slight_left;
      case 'sharp left':
        return Icons.turn_left;
      case 'right':
        return Icons.turn_right;
      case 'slight right':
        return Icons.turn_slight_right;
      case 'sharp right':
        return Icons.turn_right;
      case 'uturn':
      case 'uturn left':
      case 'uturn right':
        return Icons.u_turn_left;
      case 'straight':
        return Icons.straight;
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

  String _roundaboutInstruction(int? exitNumber, String rawInstruction, String modifier) {
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
      case 1: return '1.';
      case 2: return '2.';
      case 3: return '3.';
      case 4: return '4.';
      case 5: return '5.';
      default: return '$exit.';
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
    if (trimmed.isEmpty) return _announcementForModifier(modifier);
    return _translateToGerman(trimmed);
  }

  /// Übersetzt englische Navigationsanweisungen ins Deutsche (sequenziell, kein early return)
  String _translateToGerman(String instruction) {
    var r = instruction;

    // Kreisverkehr (vor generischen "enter"/"exit" erkennen)
    r = r.replaceAll(RegExp(r'\benter (?:the )?(?:roundabout|traffic circle|rotary)\b', caseSensitive: false), 'In den Kreisverkehr einfahren');
    r = r.replaceAll(RegExp(r'\bexit (?:the )?(?:roundabout|traffic circle|rotary)\b', caseSensitive: false), 'Kreisverkehr verlassen');

    // Abbiegungen
    r = r.replaceAll(RegExp(r'\bturn (?:slightly |sharp )?left\b', caseSensitive: false), 'Links abbiegen');
    r = r.replaceAll(RegExp(r'\bturn (?:slightly |sharp )?right\b', caseSensitive: false), 'Rechts abbiegen');
    r = r.replaceAll(RegExp(r'\buturn\b', caseSensitive: false), 'Wenden');

    // Halten
    r = r.replaceAll(RegExp(r'\bbear left\b', caseSensitive: false), 'Links halten');
    r = r.replaceAll(RegExp(r'\bbear right\b', caseSensitive: false), 'Rechts halten');
    r = r.replaceAll(RegExp(r'\bkeep left\b', caseSensitive: false), 'Links halten');
    r = r.replaceAll(RegExp(r'\bkeep right\b', caseSensitive: false), 'Rechts halten');
    r = r.replaceAll(RegExp(r'\bkeep (?:straight|going)\b', caseSensitive: false), 'Geradeaus weiterfahren');

    // Geradeaus / Starten
    r = r.replaceAll(RegExp(r'\bhead (?:north|south|east|west|northwest|northeast|southwest|southeast)\b', caseSensitive: false), 'Geradeaus fahren');
    r = r.replaceAll(RegExp(r'\bcontinue\b', caseSensitive: false), 'Weiterfahren');

    // Ausfahrten
    r = r.replaceAll(RegExp(r'\btake the \w+ (?:exit|ramp)\b', caseSensitive: false), 'Ausfahrt nehmen');
    r = r.replaceAll(RegExp(r'\btake (?:the )?exit\b', caseSensitive: false), 'Ausfahrt nehmen');

    // Auffahren / Abfahren
    r = r.replaceAll(RegExp(r'\bmerge (?:onto|into)\b', caseSensitive: false), 'Auffahren auf');
    r = r.replaceAll(RegExp(r'\bexit (?:onto|to)\b', caseSensitive: false), 'Abfahrt auf');

    // Ziel
    r = r.replaceAll(RegExp(r'\b(?:you have arrived|arrive at|destination)\b', caseSensitive: false), 'Ziel erreicht');

    // Englische Verbindungswörter — zuletzt, nach allen längeren Mustern
    r = r.replaceAll(RegExp(r'\bonto\b', caseSensitive: false), 'auf');
    r = r.replaceAll(RegExp(r'\btoward\b', caseSensitive: false), 'Richtung');
    r = r.replaceAll(RegExp(r'\bvia\b', caseSensitive: false), 'über');

    return r;
  }

  String _announcementFromInstruction(String instruction, String modifier, double distance) {
    return '${_formatDistance(distance)} ${_normalizeInstruction(instruction, modifier)}';
  }

  // ─────────────────────── Route Snapping ───────────────────────────────────

  /// Snappt Start (und Rundkurs-Ende) auf die exakte GPS-Position und
  /// entfernt die Anfangs-Schleife die Mapbox manchmal erzeugt.
  RouteResult _snapRouteToStartPosition(RouteResult result, geo.Position startPosition) {
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
      final d = geo.Geolocator.distanceBetween(startLat, startLng, coords[i][1], coords[i][0]);
      if (d > maxDist) {
        maxDist = d;
        maxDistIdx = i;
      }
    }

    var trimTo = 0;
    if (maxDist > 100.0) {
      // Route hat sich ≥100 m entfernt — prüfe ob sie danach zurückkommt
      for (var i = maxDistIdx; i < searchEnd; i++) {
        final d = geo.Geolocator.distanceBetween(startLat, startLng, coords[i][1], coords[i][0]);
        if (d < 80.0) trimTo = i; // Rückkehr zum Startbereich
      }
    } else {
      // Fallback: alter Algorithmus für sehr kurze Ausreißer (<100 m)
      for (var i = 1; i < searchEnd; i++) {
        final d = geo.Geolocator.distanceBetween(startLat, startLng, coords[i][1], coords[i][0]);
        if (d < 35.0) trimTo = i;
      }
    }
    if (trimTo > 0) coords = coords.sublist(trimTo);
    if (coords.isEmpty) return result;

    // ── Startpunkt auf exakte GPS-Position setzen ─────────────────────────────
    coords[0] = [startLng, startLat];

    // ── Rundkurs: letzten Punkt auch auf Start setzen ─────────────────────────
    if (coords.length > 1) {
      final last = coords.last;
      final d = geo.Geolocator.distanceBetween(startLat, startLng, last[1], last[0]);
      if (d < 500) coords.last = [startLng, startLat];
    }

    // ── Selbstschneidende Schleifen aus der Route entfernen ───────────────────
    coords = _removeRouteLoops(coords);

    // ── Maneuver-Indices komplett neu berechnen (nach allen Koordinaten-Änderungen) ─
    // Statt Offset-Korrektur: lat/lng-Position des Maneuvers in neuen Koordinaten suchen.
    final finalManeuvers = result.maneuvers
        .map((m) => RouteManeuver(
              latitude: m.latitude,
              longitude: m.longitude,
              routeIndex: _findNearestIndex(m.latitude, m.longitude, coords),
              icon: m.icon,
              announcement: m.announcement,
              instruction: m.instruction,
            ))
        .toList();

    final newGeometry = Map<String, dynamic>.from(result.geometry);
    newGeometry['coordinates'] = coords;

    return RouteResult(
      geoJson: json.encode(newGeometry),
      geometry: newGeometry,
      coordinates: coords,
      maneuvers: finalManeuvers,
      distanceMeters: result.distanceMeters,
      durationSeconds: result.durationSeconds,
      distanceKm: result.distanceKm,
    );
  }

  /// Entfernt Schleifen (Loops) aus einer Route.
  ///
  /// Erkennt eine Schleife anhand von drei Kriterien:
  ///   1. Direktabstand zwischen Punkt j und i < 80 m  (fängt auch breitere Haken)
  ///   2. Weglänge j→i ist > 3,5× der Direktdistanz   (echter Umweg, kein normaler Bogen)
  ///   3. Weglänge j→i < 1500 m                        (lokale Schleife, kein legitimer Umweg)
  ///
  /// Kumulierte Distanzen werden vorab berechnet → O(n) pro Durchlauf.
  List<List<double>> _removeRouteLoops(List<List<double>> coords) {
    if (coords.length < 10) return coords;

    // Kumulierte Streckenlängen vorberechnen
    final cum = <double>[0.0];
    for (var i = 1; i < coords.length; i++) {
      cum.add(cum.last +
          geo.Geolocator.distanceBetween(
            coords[i - 1][1], coords[i - 1][0],
            coords[i][1],     coords[i][0],
          ));
    }

    // Letzten 15 % nicht scannen — Rundkurs endet legitim nah am Start
    final safeEnd = (coords.length * 0.85).round().clamp(10, coords.length);

    for (var i = 10; i < safeEnd; i++) {
      final lookBack = math.max(0, i - 400); // 400 Punkte Rückblick (vorher 150)
      for (var j = lookBack; j < i - 5; j++) {
        final directDist = geo.Geolocator.distanceBetween(
          coords[i][1], coords[i][0],
          coords[j][1], coords[j][0],
        );
        if (directDist > 80.0) continue;          // zu weit weg, kein Loop

        final pathLen = cum[i] - cum[j];
        if (pathLen < directDist * 3.5) continue; // normaler Bogen, kein Umweg
        if (pathLen > 1500) continue;             // zu lang = legitimer Umweg

        // Schleife gefunden → Kurzschluss: coords[j] direkt mit coords[i] verbinden
        final shortened = [
          ...coords.sublist(0, j + 1),
          ...coords.sublist(i),
        ];
        return _removeRouteLoops(shortened); // rekursiv weitere Schleifen entfernen
      }
    }
    return coords;
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
