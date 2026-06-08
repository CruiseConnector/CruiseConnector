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
    this.leading,
  });

  final RouteManeuver maneuver;

  /// Distanz entlang der Route zum nächsten Manöver (in Metern).
  final double? distanceToManeuverMeters;

  /// Optionales führendes Element (z. B. Zurück-Button), das INNERHALB der
  /// Banner-Karte sitzt und per Trennlinie vom Manöver abgesetzt wird — so wirkt
  /// oben alles als EINE Einheit statt zwei lose Pillen.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final distanceText = distanceToManeuverMeters == null
        ? '--'
        : distanceToManeuverMeters! >= 1000.0
        ? '${(distanceToManeuverMeters! / 1000.0).toStringAsFixed(1).replaceAll('.', ',')} km'
        : '${distanceToManeuverMeters!.clamp(0, 999).round()} m';

    final isRoundabout = maneuver.maneuverType == ManeuverType.roundabout;

    return Container(
      padding: EdgeInsets.fromLTRB(leading != null ? 6 : 16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2028).withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(22),
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
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 6),
            Container(
              width: 1,
              height: 44,
              color: Colors.white.withValues(alpha: 0.10),
            ),
            const SizedBox(width: 14),
          ],
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
                boxShadow: [
                  BoxShadow(
                    color: AppAccentColors.accent.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
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
///
/// Layout (DACH/Rechtsverkehr):
/// - Einfahrt unten (π/2 in Bildschirm-Koordinaten, y-down).
/// - Im Kreis fährt man CCW visuell (= negative sweep in Flutter).
/// - Exit 1 = rechts (0 rad), Exit 2 = geradeaus, Exit 3 = links —
///   gegeben durch [roundaboutExitAngleForRightHandTraffic].
class _RoundaboutPainter extends CustomPainter {
  _RoundaboutPainter({required this.exitNumber});

  final int exitNumber;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringRadius = size.width * 0.32;
    final exitRadius = size.width * 0.45;
    final accent = AppAccentColors.accent;
    final ringRect = Rect.fromCircle(center: center, radius: ringRadius);

    // 1. Ring (statisch, weiß).
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, ringRadius, ringPaint);

    // 2. Drehrichtungs-Arc: zeigt CCW über fast den ganzen Ring, kleine Lücke
    //    nahe Einfahrt damit die Einfahrt "rein-mündet".
    const directionStart = math.pi / 2 + 0.3;
    const directionSweep = -4.5;
    final directionArcPaint = Paint()
      ..color = accent.withValues(alpha: 0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      ringRect,
      directionStart,
      directionSweep,
      false,
      directionArcPaint,
    );

    // 3. Aktiver Fahrweg: vom Einfahrtspunkt (π/2) CCW zur aktiven Ausfahrt.
    //    Wird ÜBER den Drehrichtungs-Arc gezeichnet, voller Accent.
    final totalExits = math.max(4, exitNumber.clamp(1, 6).toInt());
    final activeExitAngle = roundaboutExitAngleForRightHandTraffic(
      exitNumber,
      totalExits: totalExits,
    );
    var activeSweep = activeExitAngle - math.pi / 2;
    while (activeSweep > 0) {
      activeSweep -= 2 * math.pi;
    }
    while (activeSweep <= -2 * math.pi) {
      activeSweep += 2 * math.pi;
    }
    if (activeSweep < 0) {
      final activePathPaint = Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        ringRect,
        math.pi / 2,
        activeSweep,
        false,
        activePathPaint,
      );
    }

    // 4. Ausfahrt-Stubs: inaktive dünn-weiß, aktive accent + Pfeilspitze.
    for (var i = 1; i <= totalExits; i++) {
      final angle = roundaboutExitAngleForRightHandTraffic(
        i,
        totalExits: totalExits,
      );
      final exitOffset = Offset(
        center.dx + exitRadius * math.cos(angle),
        center.dy + exitRadius * math.sin(angle),
      );
      final innerOffset = Offset(
        center.dx + ringRadius * math.cos(angle),
        center.dy + ringRadius * math.sin(angle),
      );
      final isActive = i == exitNumber;
      final stubPaint = Paint()
        ..color = isActive
            ? accent
            : Colors.white.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isActive ? 3.5 : 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(innerOffset, exitOffset, stubPaint);

      if (isActive) {
        final arrowPaint = Paint()
          ..color = accent
          ..style = PaintingStyle.fill;
        const arrowSize = 5.0;
        final left = Offset(
          exitOffset.dx - arrowSize * math.cos(angle - 0.5),
          exitOffset.dy - arrowSize * math.sin(angle - 0.5),
        );
        final right = Offset(
          exitOffset.dx - arrowSize * math.cos(angle + 0.5),
          exitOffset.dy - arrowSize * math.sin(angle + 0.5),
        );
        canvas.drawPath(
          Path()
            ..moveTo(exitOffset.dx, exitOffset.dy)
            ..lineTo(left.dx, left.dy)
            ..lineTo(right.dx, right.dy)
            ..close(),
          arrowPaint,
        );
      }
    }

    // 5. Drehrichtungs-Pfeil am Ende des Direction-Arcs (CCW-Tangente).
    const directionEnd = directionStart + directionSweep;
    final dirEndOffset = Offset(
      center.dx + ringRadius * math.cos(directionEnd),
      center.dy + ringRadius * math.sin(directionEnd),
    );
    // CCW-Tangente an θ: (sin θ, -cos θ) — Bewegungsrichtung bei abnehmendem θ.
    final tangentDx = math.sin(directionEnd);
    final tangentDy = -math.cos(directionEnd);
    const dirArrowSize = 4.5;
    final dirTip = Offset(
      dirEndOffset.dx + tangentDx * dirArrowSize * 0.7,
      dirEndOffset.dy + tangentDy * dirArrowSize * 0.7,
    );
    // Senkrecht zur Tangente für die Basis.
    final perpDx = -tangentDy;
    final perpDy = tangentDx;
    final dirBaseLeft = Offset(
      dirEndOffset.dx + perpDx * dirArrowSize * 0.55 -
          tangentDx * dirArrowSize * 0.25,
      dirEndOffset.dy + perpDy * dirArrowSize * 0.55 -
          tangentDy * dirArrowSize * 0.25,
    );
    final dirBaseRight = Offset(
      dirEndOffset.dx - perpDx * dirArrowSize * 0.55 -
          tangentDx * dirArrowSize * 0.25,
      dirEndOffset.dy - perpDy * dirArrowSize * 0.55 -
          tangentDy * dirArrowSize * 0.25,
    );
    final dirArrowPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.fill;
    canvas.drawPath(
      Path()
        ..moveTo(dirTip.dx, dirTip.dy)
        ..lineTo(dirBaseLeft.dx, dirBaseLeft.dy)
        ..lineTo(dirBaseRight.dx, dirBaseRight.dy)
        ..close(),
      dirArrowPaint,
    );

    // 6. Einfahrt von unten mit leichtem Rechts-Bogen vor dem Ring.
    final entryPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final entryStart = Offset(center.dx, center.dy + exitRadius);
    final entryEnd = Offset(center.dx, center.dy + ringRadius);
    final entryControl = Offset(
      center.dx + 3.0,
      (entryStart.dy + entryEnd.dy) / 2,
    );
    canvas.drawPath(
      Path()
        ..moveTo(entryStart.dx, entryStart.dy)
        ..quadraticBezierTo(
          entryControl.dx,
          entryControl.dy,
          entryEnd.dx,
          entryEnd.dy,
        ),
      entryPaint,
    );
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
