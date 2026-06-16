import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
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
    this.reroutingDuration,
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

  /// Wie lange der aktuelle Reroute schon sichtbar ist. Nach einigen Sekunden
  /// wechselt der Untertext von "warte" zu einem sicheren Weiterfahr-Hinweis,
  /// damit die UI nicht wie eingefroren wirkt.
  final Duration? reroutingDuration;

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
            RoundaboutSymbol(maneuver: maneuver, size: 50)
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
    final isTakingLong =
        reroutingDuration != null &&
        reroutingDuration! >= const Duration(seconds: 6);
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
                  isTakingLong
                      ? 'Suche läuft weiter — Route bleibt sichtbar'
                      : 'Route wird angepasst — bitte weiterfahren',
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

/// 2026-06-16 (vucko O9): Eigenständiges Kreisverkehr-Symbol (für das Banner,
/// CarPlay/Android-Auto und Golden-Tests gleichermaßen). Rendert die echte
/// Topologie aus dem Manöver (entry/exit/arms) bzw. den Fallback.
class RoundaboutSymbol extends StatelessWidget {
  const RoundaboutSymbol({
    super.key,
    required this.maneuver,
    this.size = 50,
  });

  final RouteManeuver maneuver;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RoundaboutPainter(
          exitNumber: maneuver.roundaboutExitNumber ?? 1,
          turnAngleRad: maneuver.roundaboutTurnAngleRad,
          entryBearing: maneuver.roundaboutEntryBearing,
          exitBearing: maneuver.roundaboutExitBearing,
          armBearings: maneuver.roundaboutArmBearings,
        ),
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
  _RoundaboutPainter({
    required this.exitNumber,
    this.turnAngleRad,
    this.entryBearing,
    this.exitBearing,
    this.armBearings,
  });

  final int exitNumber;

  /// GraphHopper `turn_angle` (Radiant) — Fallback für den Ausfahrtswinkel.
  final double? turnAngleRad;

  /// Kompass-Winkel (0..360°) der Einfahrt (Richtung zur Herkunft) bzw. der
  /// genommenen Ausfahrt — aus der gefahrenen Geometrie.
  final double? entryBearing;
  final double? exitBearing;

  /// 2026-06-16 (vucko O9): ALLE Arme des Kreisels (Kompass-Winkel, aus OSM).
  /// Vorhanden ⇒ echte Topologie (3-/4-/5-/6-armig, asymmetrisch) wie Apple/
  /// Google. null/leer ⇒ Fallback auf Einfahrt + genommene Ausfahrt.
  final List<double>? armBearings;

  /// Kompass-Bearing → Screen-Winkel (y-down), so dass die EINFAHRT unten (π/2)
  /// liegt. Rechtskurve→rechts, geradeaus→oben, Linkskurve→links (verifiziert).
  double _screen(double bearing) =>
      (bearing - (entryBearing ?? 0) + 90.0) * math.pi / 180.0;

  int _nearestArm(List<double> arms, double bearing) {
    var best = 0;
    var bestD = 999.0;
    for (var i = 0; i < arms.length; i++) {
      var d = (arms[i] - bearing).abs() % 360.0;
      if (d > 180) d = 360 - d;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 2026-06-16 (vucko O9, User-Figma-Referenz): Das Symbol zeigt den
    // Kreisverkehr so, wie er WIRKLICH aussieht — Hub + Ring + ALLE Arme an
    // ihren echten Winkeln (aus OSM), die Einfahrt nach unten gedreht, die
    // genommene Ausfahrt + Fahrlinie in Akzentfarbe hervorgehoben. Liegen keine
    // OSM-Arme vor, fällt es auf Einfahrt + genommene Ausfahrt (Geometrie/
    // turn_angle) zurück — nie eine erfundene Topologie. Canvas y-down.
    final w = size.width;
    final center = Offset(w / 2, w / 2);
    final ringR = w * 0.30;
    final hubR = w * 0.115;
    final stubOut = w * 0.155;
    final accent = AppAccentColors.accent;
    final ringRect = Rect.fromCircle(center: center, radius: ringR);
    const entryScreen = math.pi / 2; // unten

    Offset on(double a, double r) =>
        Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));

    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.045;
    final armPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05
      ..strokeCap = StrokeCap.round;
    final accentStroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.072
      ..strokeCap = StrokeCap.round;
    final armFill = Paint()
      ..color = Colors.white.withValues(alpha: 0.34)
      ..style = PaintingStyle.fill;
    final accentFill = Paint()
      ..color = accent
      ..style = PaintingStyle.fill;

    // Hub + Ring.
    canvas.drawCircle(
      center,
      hubR,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.16)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(center, ringR, ringPaint);

    void exitStub(double screenAngle, {required bool highlight}) {
      final p = highlight ? accentStroke : armPaint;
      final outer = on(screenAngle, ringR + stubOut);
      canvas.drawLine(on(screenAngle, ringR), outer, p);
      final head = highlight ? w * 0.135 : w * 0.085;
      final spread = highlight ? 0.5 : 0.6;
      final aL = Offset(
        outer.dx - head * math.cos(screenAngle - spread),
        outer.dy - head * math.sin(screenAngle - spread),
      );
      final aR = Offset(
        outer.dx - head * math.cos(screenAngle + spread),
        outer.dy - head * math.sin(screenAngle + spread),
      );
      canvas.drawPath(
        Path()
          ..moveTo(outer.dx, outer.dy)
          ..lineTo(aL.dx, aL.dy)
          ..lineTo(aR.dx, aR.dy)
          ..close(),
        highlight ? accentFill : armFill,
      );
    }

    void driveArc(double takenScreen) {
      var sweep = takenScreen - entryScreen;
      while (sweep > 0) {
        sweep -= 2 * math.pi;
      }
      while (sweep <= -2 * math.pi) {
        sweep += 2 * math.pi;
      }
      if (sweep.abs() > 0.04) {
        canvas.drawArc(ringRect, entryScreen, sweep, false, accentStroke);
      }
    }

    // Einfahrt-Stummel (unten) — Teil der Fahrlinie, daher in Akzentfarbe von
    // außen bis an den Ring (wie Apple/Google: durchgehender Pfad rein → Bogen →
    // raus). Ohne Pfeilspitze (Pfeil sitzt nur an der genommenen Ausfahrt).
    canvas.drawLine(
      on(entryScreen, ringR + stubOut),
      on(entryScreen, ringR),
      accentStroke,
    );

    final arms = armBearings;
    // Genommene Ausfahrt als Screen-Winkel: echte exitBearing bevorzugt, sonst
    // turn_angle.
    double? takenScreen;
    if (entryBearing != null && exitBearing != null) {
      takenScreen = _screen(exitBearing!);
    } else if (turnAngleRad != null) {
      takenScreen = roundaboutExitAngleFromTurnAngle(turnAngleRad!);
    }

    // ── ECHTE TOPOLOGIE (OSM-Arme vorhanden) ──────────────────────────────
    if (arms != null && arms.length >= 2 && entryBearing != null) {
      final entryIdx = _nearestArm(arms, entryBearing!);
      final takenIdx = exitBearing != null
          ? _nearestArm(arms, exitBearing!)
          : -1;
      for (var i = 0; i < arms.length; i++) {
        if (i == entryIdx) continue; // Einfahrt schon gezeichnet
        if (i == takenIdx) continue; // Ausfahrt unten als Highlight
        exitStub(_screen(arms[i]), highlight: false);
      }
      final ts = takenIdx >= 0 ? _screen(arms[takenIdx]) : takenScreen;
      if (ts != null) {
        driveArc(ts);
        exitStub(ts, highlight: true);
      }
      return;
    }

    // ── FALLBACK (keine OSM-Arme): Einfahrt + genommene Ausfahrt ───────────
    if (takenScreen != null) {
      // Ausfahrten, an denen man vorbeifährt (Näherung über exit_number).
      var sweep = takenScreen - entryScreen;
      while (sweep > 0) {
        sweep -= 2 * math.pi;
      }
      while (sweep <= -2 * math.pi) {
        sweep += 2 * math.pi;
      }
      final passed = exitNumber.clamp(1, 12) - 1;
      for (var i = 1; i <= passed; i++) {
        exitStub(entryScreen + sweep * (i / exitNumber), highlight: false);
      }
      driveArc(takenScreen);
      exitStub(takenScreen, highlight: true);
    } else {
      final tp = TextPainter(
        text: TextSpan(
          text: exitNumber.clamp(1, 9).toString(),
          style: TextStyle(
            color: accent,
            fontSize: w * 0.30,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_RoundaboutPainter o) =>
      o.exitNumber != exitNumber ||
      o.turnAngleRad != turnAngleRad ||
      o.entryBearing != entryBearing ||
      o.exitBearing != exitBearing ||
      !listEquals(o.armBearings, armBearings);
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

/// Übersetzt den GraphHopper `turn_angle` in den Screen-Winkel der Painter-
/// Konvention (y-down: 0 = rechts/Osten, π/2 = unten = Einfahrt, −π/2 = oben).
/// GH liefert die Durchfahrt im Kreisverkehr: positive Werte = clockwise,
/// negative Werte = counter-clockwise. DACH/Rechtsverkehr ist counter-clockwise,
/// also ist eine rechte/fruehe Ausfahrt negativ. Einfahrt unten, geradeaus oben:
/// Austritt = oben - turn_angle.
@visibleForTesting
double roundaboutExitAngleFromTurnAngle(double turnAngleRad) {
  var angle = -math.pi / 2 - turnAngleRad;
  while (angle <= -math.pi) {
    angle += 2 * math.pi;
  }
  while (angle > math.pi) {
    angle -= 2 * math.pi;
  }
  return angle;
}
