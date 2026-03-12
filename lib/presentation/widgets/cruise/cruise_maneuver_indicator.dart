import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;

import 'package:cruise_connect/domain/models/route_maneuver.dart';

/// Zeigt die nächste Navigationsanweisung mit Distanz-Anzeige.
class CruiseManeuverIndicator extends StatelessWidget {
  const CruiseManeuverIndicator({
    super.key,
    required this.maneuver,
    this.userPosition,
  });

  final RouteManeuver maneuver;
  final geo.Position? userPosition;

  @override
  Widget build(BuildContext context) {
    final distanceMeters = userPosition == null
        ? null
        : geo.Geolocator.distanceBetween(
            userPosition!.latitude,
            userPosition!.longitude,
            maneuver.latitude,
            maneuver.longitude,
          );

    final distanceText = distanceMeters == null
        ? '--'
        : distanceMeters >= 1000.0
        ? '${(distanceMeters / 1000.0).toStringAsFixed(1).replaceAll('.', ',')} km'
        : '${distanceMeters.clamp(0, 999).round()} m';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF2D3138).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(maneuver.icon, color: Colors.white, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  distanceText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  maneuver.instruction,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
