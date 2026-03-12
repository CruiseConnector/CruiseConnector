import 'package:flutter/material.dart';

/// Eine einzelne Navigationsanweisung entlang einer Cruise-Route.
class RouteManeuver {
  const RouteManeuver({
    required this.latitude,
    required this.longitude,
    required this.routeIndex,
    required this.icon,
    required this.announcement,
    required this.instruction,
  });

  final double latitude;
  final double longitude;
  final int routeIndex;
  final IconData icon;
  final String announcement;
  final String instruction;
}

/// Ergebnis einer Nearest-Route-Point Fenstersuche.
class RouteWindowMatch {
  const RouteWindowMatch({required this.index, required this.distanceMeters});

  final int index;
  final double distanceMeters;
}
