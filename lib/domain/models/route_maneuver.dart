import 'package:flutter/material.dart';

/// Typ des Manövers für spezielle Darstellungen (z.B. Kreisverkehr).
enum ManeuverType { normal, roundabout }

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
    this.roundaboutTurnAngleRad,
  });

  final double latitude;
  final double longitude;
  final int routeIndex;
  final IconData icon;
  final String announcement;
  final String instruction;
  final ManeuverType maneuverType;
  final int?
  roundaboutExitNumber; // Welche Ausfahrt im Kreisverkehr (1, 2, 3...)

  /// Echter Ausfahrts-Winkel aus GraphHopper `turn_angle` (Radiant).
  /// 0 = geradeaus durch den Kreisverkehr, positiv = rechts raus,
  /// negativ = links raus (Rechtsverkehr/CCW). null beim Mapbox-Pfad →
  /// Painter fällt auf die synthetische Gleichverteilung zurück.
  final double? roundaboutTurnAngleRad;

  bool get isArrival => icon == Icons.flag;

  /// 2026-06-13 (vucko J3): Kopie mit überschriebenen Feldern. Wird beim
  /// Start-Snap genutzt, damit beim Neuberechnen des routeIndex KEIN Feld mehr
  /// still verloren geht (genau so verschwand der Kreisverkehr-Typ → Banner
  /// zeigte das alte Material-Icon statt des Painters).
  RouteManeuver copyWith({
    double? latitude,
    double? longitude,
    int? routeIndex,
    IconData? icon,
    String? announcement,
    String? instruction,
    ManeuverType? maneuverType,
    int? roundaboutExitNumber,
    double? roundaboutTurnAngleRad,
  }) {
    return RouteManeuver(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      routeIndex: routeIndex ?? this.routeIndex,
      icon: icon ?? this.icon,
      announcement: announcement ?? this.announcement,
      instruction: instruction ?? this.instruction,
      maneuverType: maneuverType ?? this.maneuverType,
      roundaboutExitNumber: roundaboutExitNumber ?? this.roundaboutExitNumber,
      roundaboutTurnAngleRad:
          roundaboutTurnAngleRad ?? this.roundaboutTurnAngleRad,
    );
  }
}

/// Ergebnis einer Nearest-Route-Point Fenstersuche.
class RouteWindowMatch {
  const RouteWindowMatch({
    required this.index,
    required this.distanceMeters,
    this.segmentIndex,
    this.segmentFraction,
  });

  final int index;
  final double distanceMeters;
  final int? segmentIndex;
  final double? segmentFraction;
}
