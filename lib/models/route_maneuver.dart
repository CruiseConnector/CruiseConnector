import 'package:flutter/material.dart';

/// A single navigation maneuver along a cruise route.
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

/// Result of a nearest-route-point window search.
class RouteWindowMatch {
  const RouteWindowMatch({required this.index, required this.distanceMeters});

  final int index;
  final double distanceMeters;
}
