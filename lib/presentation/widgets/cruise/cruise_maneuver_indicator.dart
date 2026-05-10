import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';

import 'package:cruise_connect/domain/models/route_maneuver.dart';

/// Zeigt die nächste Navigationsanweisung mit Distanz-Anzeige.
class CruiseManeuverIndicator extends StatelessWidget {
  const CruiseManeuverIndicator({
    super.key,
    required this.maneuver,
    this.distanceToManeuverMeters,
  });

  final RouteManeuver maneuver;

  /// Distanz entlang der Route zum nächsten Manöver (in Metern).
  final double? distanceToManeuverMeters;

  @override
  Widget build(BuildContext context) {
    final distanceText = distanceToManeuverMeters == null
        ? '--'
        : distanceToManeuverMeters! >= 1000.0
        ? '${(distanceToManeuverMeters! / 1000.0).toStringAsFixed(1).replaceAll('.', ',')} km'
        : '${distanceToManeuverMeters!.clamp(0, 999).round()} m';

    final isRoundabout = maneuver.maneuverType == ManeuverType.roundabout;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2028).withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (isRoundabout)
            SizedBox(
              width: 48,
              height: 48,
              child: CustomPaint(
                painter: _RoundaboutPainter(
                  exitNumber: maneuver.roundaboutExitNumber ?? 1,
                ),
              ),
            )
          else
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppAccentColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                maneuver.icon,
                color: AppAccentColors.accent,
                size: 28,
              ),
            ),
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
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
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

/// Zeichnet einen Kreisverkehr mit markierter Ausfahrt.
class _RoundaboutPainter extends CustomPainter {
  _RoundaboutPainter({required this.exitNumber});

  final int exitNumber;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.32;
    final arrowRadius = size.width * 0.45;

    // Kreisverkehr-Ring
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, radius, ringPaint);

    // DACH/Rechtsverkehr: Einfahrt von unten, Ausfahrten gegen den Uhrzeigersinn.
    // Exit 1 = rechts, Exit 2 = geradeaus, Exit 3 = links.
    final totalExits = math.max(4, exitNumber.clamp(1, 6).toInt());

    for (var i = 1; i <= totalExits; i++) {
      final angle = roundaboutExitAngleForRightHandTraffic(
        i,
        totalExits: totalExits,
      );
      final exitX = center.dx + arrowRadius * math.cos(angle);
      final exitY = center.dy + arrowRadius * math.sin(angle);
      final innerX = center.dx + radius * math.cos(angle);
      final innerY = center.dy + radius * math.sin(angle);

      final isActive = i == exitNumber;
      final exitPaint = Paint()
        ..color = isActive
            ? AppAccentColors.accent
            : Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isActive ? 3.5 : 2.0
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(innerX, innerY), Offset(exitX, exitY), exitPaint);

      // Pfeilspitze für aktive Ausfahrt
      if (isActive) {
        final arrowPaint = Paint()
          ..color = AppAccentColors.accent
          ..style = PaintingStyle.fill;
        const arrowSize = 5.0;
        final tip = Offset(exitX, exitY);
        final left = Offset(
          tip.dx - arrowSize * math.cos(angle - 0.5),
          tip.dy - arrowSize * math.sin(angle - 0.5),
        );
        final right = Offset(
          tip.dx - arrowSize * math.cos(angle + 0.5),
          tip.dy - arrowSize * math.sin(angle + 0.5),
        );
        canvas.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(left.dx, left.dy)
            ..lineTo(right.dx, right.dy)
            ..close(),
          arrowPaint,
        );
      }
    }

    // Einfahrt von unten
    final entryPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final entryStart = Offset(center.dx, center.dy + arrowRadius);
    final entryEnd = Offset(center.dx, center.dy + radius);
    canvas.drawLine(entryStart, entryEnd, entryPaint);
  }

  @override
  bool shouldRepaint(_RoundaboutPainter oldDelegate) =>
      oldDelegate.exitNumber != exitNumber;
}

@visibleForTesting
double roundaboutExitAngleForRightHandTraffic(
  int exitNumber, {
  int totalExits = 4,
}) {
  final safeTotal = math.max(1, totalExits);
  final safeExit = exitNumber.clamp(1, safeTotal).toInt();
  return -((safeExit - 1) * 2 * math.pi / safeTotal);
}
