import 'package:flutter/material.dart';

/// Typ des Manövers für spezielle Darstellungen (z.B. Kreisverkehr).
enum ManeuverType {
  normal,
  roundabout,
}

/// Eine einzelne Navigationsanweisung entlang einer Cruise-Route.
class RouteManeuver {
  const RouteManeuver({
    required this.latitude,
    required this.longitude,
    required this.routeIndex,
    required this.icon,
    required this.announcement,
    required this.instruction,
    this.maneuverType = ManeuverType.normal,
    this.roundaboutExitNumber,
  });

  final double latitude;
  final double longitude;
  final int routeIndex;
  final IconData icon;
  final String announcement;
  final String instruction;
  final ManeuverType maneuverType;
  final int? roundaboutExitNumber; // Welche Ausfahrt im Kreisverkehr (1, 2, 3...)
}

/// Ergebnis einer Nearest-Route-Point Fenstersuche.
class RouteWindowMatch {
  const RouteWindowMatch({required this.index, required this.distanceMeters});

  final int index;
  final double distanceMeters;
}
