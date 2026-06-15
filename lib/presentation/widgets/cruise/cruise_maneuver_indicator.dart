import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';

import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/presentation/widgets/cruise/nav_distance_format.dart';

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
    // 2026-06-13 (vucko J2): Google-Style Stufen (690/680/670), keine krummen
    // Zahlen. Kurz vorm Manöver „Jetzt" statt „0 m".
    final distanceText = formatNavDistance(
      distanceToManeuverMeters,
      nowLabelUnderTen: true,
    );

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

  // Winkel-Naehe-Test (zyklisch).
  static bool _angClose(double a, double b, double tol) {
    var d = (a - b) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    if (d < -math.pi) d += 2 * math.pi;
    return d.abs() < tol;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 2026-06-15 (vucko M2, Geraete-Video: „Symbol komplett falsch/verbuggt"):
    // Komplett-Rebuild. EINE Winkelquelle treibt das ganze Glyph — der ECHTE
    // Geometrie-Austrittswinkel (turn_angle = aus der gefahrenen Route, rechts
    // positiv). Vorher kollidierten synthetisch gleichverteilte Stubs mit dem
    // realen Pfeil (zwei Winkelraeume) → „verbuggt". Jetzt:
    //   • Ring.
    //   • Einfahrt von UNTEN (deine Strasse rein), Accent.
    //   • Fahrbogen im Ring vom Einfahrtspunkt GEGEN den Uhrzeigersinn
    //     (Rechtsverkehr) bis zum Austritt, Accent.
    //   • EIN fetter Pfeil exakt am echten Austrittswinkel.
    //   • dezente Deko-Stubs, die Einfahrt UND aktiven Pfeil garantiert nie
    //     ueberlappen (rein dekorativ, kein Anspruch auf reale Position).
    // Canvas y-down: Winkel 0 = rechts, π/2 = unten (Einfahrt), −π/2 = oben.
    final center = Offset(size.width / 2, size.height / 2);
    final ringRadius = size.width * 0.28;
    final exitLen = size.width * 0.20;
    final accent = AppAccentColors.accent;
    final ringRect = Rect.fromCircle(center: center, radius: ringRadius);
    const entryAngle = math.pi / 2; // unten = Einfahrt

    Offset onRing(double a, double r) =>
        Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));

    // Austrittswinkel: ECHTE Geometrie bevorzugt (immer korrekte Richtung),
    // sonst die Rechtsverkehr-Gleichverteilung (Mapbox-Fallback, turn_angle null).
    final realTurnAngle = turnAngleRad;
    final exitAngle = realTurnAngle != null
        ? roundaboutExitAngleFromTurnAngle(realTurnAngle)
        : roundaboutExitAngleForRightHandTraffic(
            exitNumber,
            totalExits: math.max(4, exitNumber.clamp(1, 8).toInt()),
          );

    // 1) Dezente Deko-Stubs (gleichmaessig, aber Einfahrt + aktiver Pfeil
    //    ausgespart → nie Kollision). Anzahl skaliert grob mit der Ausfahrt-Nr.
    final deco = math.max(4, exitNumber.clamp(1, 7).toInt() + 1);
    final decoPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < deco; i++) {
      final a = -math.pi / 2 + i * (2 * math.pi / deco);
      if (_angClose(a, entryAngle, 0.5)) continue;
      if (_angClose(a, exitAngle, 0.5)) continue;
      canvas.drawLine(
        onRing(a, ringRadius),
        onRing(a, ringRadius + exitLen * 0.7),
        decoPaint,
      );
    }

    // 2) Ring.
    canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    final accentStroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    // 3) Einfahrt von unten.
    canvas.drawLine(
      onRing(entryAngle, ringRadius + exitLen),
      onRing(entryAngle, ringRadius),
      accentStroke,
    );

    // 4) Fahrbogen Einfahrt → Austritt, GEGEN den Uhrzeigersinn (negativer
    //    Sweep in y-down = visuell CCW = Rechtsverkehr).
    var sweep = exitAngle - entryAngle;
    while (sweep > 0) {
      sweep -= 2 * math.pi;
    }
    while (sweep <= -2 * math.pi) {
      sweep += 2 * math.pi;
    }
    canvas.drawArc(ringRect, entryAngle, sweep, false, accentStroke);

    // 5) EIN fetter Austritts-Pfeil am echten Winkel.
    final outer = onRing(exitAngle, ringRadius + exitLen);
    canvas.drawLine(onRing(exitAngle, ringRadius), outer, accentStroke);
    const head = 6.5;
    final aLeft = Offset(
      outer.dx - head * math.cos(exitAngle - 0.5),
      outer.dy - head * math.sin(exitAngle - 0.5),
    );
    final aRight = Offset(
      outer.dx - head * math.cos(exitAngle + 0.5),
      outer.dy - head * math.sin(exitAngle + 0.5),
    );
    canvas.drawPath(
      Path()
        ..moveTo(outer.dx, outer.dy)
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
