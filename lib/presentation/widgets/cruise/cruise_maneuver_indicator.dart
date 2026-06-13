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
    this.isRerouting = false,
  });

  final RouteManeuver maneuver;

  /// Distanz entlang der Route zum nächsten Manöver (in Metern).
  final double? distanceToManeuverMeters;

  /// Optionales führendes Element (z. B. Zurück-Button), das INNERHALB der
  /// Banner-Karte sitzt und per Trennlinie vom Manöver abgesetzt wird — so wirkt
  /// oben alles als EINE Einheit statt zwei lose Pillen.
  final Widget? leading;

  /// 2026-06-13 (vucko Google/Apple-Bar-Review G1): Klar off-route / Reroute in
  /// flight → das Banner zeigt einen neutralen „Neuberechnung"-Status (wie
  /// Google „Rerouting…") statt der veralteten, irreführenden Abbiege-Anweisung.
  final bool isRerouting;

  @override
  Widget build(BuildContext context) {
    if (isRerouting) {
      return _buildReroutingBanner(context);
    }
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
                  turnAngleRad: maneuver.roundaboutTurnAngleRad,
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

  /// 2026-06-13 (vucko G1): „Neuberechnung"-Status — neutrale Karte mit
  /// rotierendem Refresh-Icon, exakt wie Google „Rerouting…". Verhindert, dass
  /// eine veraltete Abbiege-Anweisung den Fahrer in die Irre führt.
  Widget _buildReroutingBanner(BuildContext context) {
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
          SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppAccentColors.accent,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Neuberechnung',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Route wird angepasst — bitte weiterfahren',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 14,
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
/// - Ist [turnAngleRad] gesetzt (GraphHopper `turn_angle`), wird der ECHTE
///   Austritts-Winkel gezeichnet statt der synthetischen Gleichverteilung —
///   siehe [roundaboutExitAngleFromTurnAngle].
class _RoundaboutPainter extends CustomPainter {
  _RoundaboutPainter({required this.exitNumber, this.turnAngleRad});

  final int exitNumber;

  /// Echter GH-Austritts-Winkel (Radiant, 0 = geradeaus, + = rechts, − = links).
  /// null → Fallback auf Gleichverteilung (Mapbox-Pfad).
  final double? turnAngleRad;

  @override
  void paint(Canvas canvas, Size size) {
    // 2026-06-13 (vucko: Kreisverkehr UNMISSVERSTÄNDLICH Rechtsverkehr, wie
    // Google): saubere Darstellung statt verwaschenem Doppel-Arc.
    //  - Ring (weiß).
    //  - Einfahrt von UNTEN (deine Straße rein), Accent.
    //  - Dein Fahrweg im Ring GEGEN den Uhrzeigersinn (Rechtsverkehr!) vom
    //    Einfahrtspunkt zur markierten Ausfahrt, Accent + dicker.
    //  - Ausfahrten: aktive Accent + Pfeil, inaktive dünn grau.
    // Canvas y-down: Winkel 0 = rechts, π/2 = unten (Einfahrt), −π/2 = oben.
    final center = Offset(size.width / 2, size.height / 2);
    final ringRadius = size.width * 0.30;
    final exitRadius = size.width * 0.46;
    final accent = AppAccentColors.accent;
    final ringRect = Rect.fromCircle(center: center, radius: ringRadius);

    // 1. Ring (weiß, dezent).
    canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // 2026-06-13 (vucko): Kreisverkehre bis 8 Ausfahrten symbolisch abbilden
    // (war auf 6 gedeckelt → „7. Ausfahrt" wurde fälschlich als 6. gezeigt).
    // Gezeichnet werden so viele Ausfahrt-Stubs wie die Ziel-Ausfahrt-Nummer
    // (min 4), gleichmäßig verteilt; die GENOMMENE Ausfahrt sitzt am ECHTEN
    // GraphHopper-Winkel (turn_angle), falls vorhanden.
    final totalExits = math.max(4, exitNumber.clamp(1, 8).toInt());
    final realTurnAngle = turnAngleRad;
    final activeExitAngle = realTurnAngle != null
        ? roundaboutExitAngleFromTurnAngle(realTurnAngle)
        : roundaboutExitAngleForRightHandTraffic(
            exitNumber,
            totalExits: totalExits,
          );

    // 2. Inaktive Ausfahrt-Stubs (dünn grau) — zuerst, damit der aktive Pfeil
    //    obenauf liegt.
    const entryAngle = math.pi / 2; // unten = Einfahrt
    for (var i = 1; i <= totalExits; i++) {
      if (i == exitNumber) continue;
      final angle =
          roundaboutExitAngleForRightHandTraffic(i, totalExits: totalExits);
      // Stubs die dem aktiven Winkel zu nahe sind auslassen (kein Hervorlugen).
      var delta = (angle - activeExitAngle) % (2 * math.pi);
      if (delta > math.pi) delta -= 2 * math.pi;
      if (delta < -math.pi) delta += 2 * math.pi;
      if (delta.abs() < 0.5) continue;
      // 2026-06-13 (vucko): Deko-Stub NICHT auf die Einfahrt (unten) zeichnen —
      // bei vielen Ausfahrten (≥4) fällt sonst eine synthetische Ausfahrt mit
      // der Einfahrt zusammen und sieht falsch aus.
      var entryDelta = (angle - entryAngle) % (2 * math.pi);
      if (entryDelta > math.pi) entryDelta -= 2 * math.pi;
      if (entryDelta < -math.pi) entryDelta += 2 * math.pi;
      if (entryDelta.abs() < 0.4) continue;
      canvas.drawLine(
        Offset(center.dx + ringRadius * math.cos(angle),
            center.dy + ringRadius * math.sin(angle)),
        Offset(center.dx + exitRadius * 0.92 * math.cos(angle),
            center.dy + exitRadius * 0.92 * math.sin(angle)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
    }

    // 3. Einfahrt von unten (deine Straße in den Kreis), Accent.
    canvas.drawLine(
      Offset(center.dx, center.dy + exitRadius),
      Offset(center.dx, center.dy + ringRadius),
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );

    // 4. Dein Fahrweg im Ring: vom Einfahrtspunkt (unten, π/2) GEGEN den
    //    Uhrzeigersinn (negativer Sweep = CCW visuell = Rechtsverkehr) zur
    //    aktiven Ausfahrt.
    var activeSweep = activeExitAngle - math.pi / 2;
    while (activeSweep > 0) {
      activeSweep -= 2 * math.pi;
    }
    while (activeSweep <= -2 * math.pi) {
      activeSweep += 2 * math.pi;
    }
    if (activeSweep < 0) {
      canvas.drawArc(
        ringRect,
        math.pi / 2,
        activeSweep,
        false,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // 5. Aktive Ausfahrt: Stub vom Ring nach außen + klare Pfeilspitze.
    final exitOuter = Offset(center.dx + exitRadius * math.cos(activeExitAngle),
        center.dy + exitRadius * math.sin(activeExitAngle));
    final exitInner = Offset(
        center.dx + ringRadius * math.cos(activeExitAngle),
        center.dy + ringRadius * math.sin(activeExitAngle));
    canvas.drawLine(
      exitInner,
      exitOuter,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
    const arrowSize = 6.5;
    final aLeft = Offset(
      exitOuter.dx - arrowSize * math.cos(activeExitAngle - 0.5),
      exitOuter.dy - arrowSize * math.sin(activeExitAngle - 0.5),
    );
    final aRight = Offset(
      exitOuter.dx - arrowSize * math.cos(activeExitAngle + 0.5),
      exitOuter.dy - arrowSize * math.sin(activeExitAngle + 0.5),
    );
    canvas.drawPath(
      Path()
        ..moveTo(exitOuter.dx, exitOuter.dy)
        ..lineTo(aLeft.dx, aLeft.dy)
        ..lineTo(aRight.dx, aRight.dy)
        ..close(),
      Paint()
        ..color = accent
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_RoundaboutPainter oldDelegate) =>
      oldDelegate.exitNumber != exitNumber ||
      oldDelegate.turnAngleRad != turnAngleRad;
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

/// Übersetzt den GraphHopper `turn_angle` (0 = geradeaus durch den
/// Kreisverkehr, + = rechts raus, − = links raus) in den Screen-Winkel der
/// Painter-Konvention (y-down: 0 = rechts/Osten, π/2 = unten = Einfahrt,
/// −π/2 = oben = geradeaus). Einfahrt unten ⇒ Austritt = oben + turn_angle
/// (im Uhrzeigersinn positiv): −π/2 + turnAngleRad, normalisiert auf (−π, π].
@visibleForTesting
double roundaboutExitAngleFromTurnAngle(double turnAngleRad) {
  var angle = -math.pi / 2 + turnAngleRad;
  while (angle <= -math.pi) {
    angle += 2 * math.pi;
  }
  while (angle > math.pi) {
    angle -= 2 * math.pi;
  }
  return angle;
}
