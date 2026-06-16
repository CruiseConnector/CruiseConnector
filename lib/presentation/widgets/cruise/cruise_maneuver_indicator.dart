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

  /// Echter GH-Austritts-Winkel (Radiant, 0 = geradeaus, - = rechts, + = links
  /// in DACH/Rechtsverkehr, weil die Kreisfahrt dort gegen den Uhrzeigersinn ist).
  /// null → Fallback auf Gleichverteilung (Mapbox-Pfad).
  final double? turnAngleRad;

  @override
  void paint(Canvas canvas, Size size) {
    // 2026-06-16 (vucko O5, Geräte-Video „Symbol oft falsch/unklar, Pfeil springt
    // links/rechts"): Die Ausfahrts-NUMMER ist die stabile Wahrheit (direkt aus
    // GraphHopper exit_number) — sie wird jetzt GROSS in die Mitte gezeichnet, so
    // liest der Fahrer „1/2/3…" sofort, ohne den kleinen Pfeilwinkel deuten zu
    // müssen (Apple-/Google-Stil). Der Richtungspfeil wird NUR gezeichnet, wenn
    // der ECHTE Geometrie-Winkel (turn_angle) vorliegt; der synthetische
    // Gleichverteilungs-Fallback (sprang je Frame zwischen links/rechts und stellte
    // die Ausfahrt falsch dar) ist ENTFERNT. So ist das Symbol bei JEDEM Kreisel
    // eindeutig UND stabil. Canvas y-down: 0 = rechts, π/2 = unten (Einfahrt),
    // −π/2 = oben.
    final w = size.width;
    final center = Offset(w / 2, w / 2);
    final ringR = w * 0.34; // Fahrbahn-Ring
    final hubR = w * 0.13; // Kreisinsel
    final stubOut = w * 0.13; // Überstand der Ausfahrt-Stummel
    final accent = AppAccentColors.accent;
    final ringRect = Rect.fromCircle(center: center, radius: ringR);
    const entryAngle = math.pi / 2; // unten = Einfahrt

    Offset onRing(double a, double r) =>
        Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));

    final faint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final accentStroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    // Kreisinsel (Hub) + Fahrbahn-Ring.
    canvas.drawCircle(
      center,
      hubR,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.13)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(center, ringR, faint);
    // Einfahrt von unten (immer).
    canvas.drawLine(
      onRing(entryAngle, ringR + stubOut),
      onRing(entryAngle, ringR),
      faint,
    );

    final realTurnAngle = turnAngleRad;
    if (realTurnAngle != null) {
      final exitAngle = roundaboutExitAngleFromTurnAngle(realTurnAngle);
      // CCW-Sweep (Rechtsverkehr) von Einfahrt zur Ausfahrt — negativ in y-down.
      var sweep = exitAngle - entryAngle;
      while (sweep > 0) {
        sweep -= 2 * math.pi;
      }
      while (sweep <= -2 * math.pi) {
        sweep += 2 * math.pi;
      }
      // Ausfahrten, an denen man VORBEIfährt (Anzahl = exit_number − 1), als
      // dezente Stummel gleichverteilt im gefahrenen Bogen → zahl-genau je
      // Kreisverkehr (mehr Ausfahrten vorher ⇒ mehr Stummel).
      final passed = exitNumber.clamp(1, 12) - 1;
      for (var i = 1; i <= passed; i++) {
        final a = entryAngle + sweep * (i / exitNumber);
        canvas.drawLine(onRing(a, ringR), onRing(a, ringR + stubOut), faint);
      }
      // Hervorgehobene Fahrlinie auf dem Ring (Einfahrt → eigene Ausfahrt).
      canvas.drawArc(ringRect, entryAngle, sweep, false, accentStroke);
      // Ausfahrts-Pfeil nach außen am ECHTEN Winkel.
      final outer = onRing(exitAngle, ringR + stubOut + 1);
      canvas.drawLine(onRing(exitAngle, ringR), outer, accentStroke);
      const head = 5.5;
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
    } else {
      // Kein echter Winkel → keine erfundene Ausfahrt; Nummer als Sicherheit.
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
