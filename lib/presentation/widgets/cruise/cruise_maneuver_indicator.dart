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
    this.groupFollowerWaiting = false,
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

  /// 2026-06-23 (vucko 2-Geräte-Gruppen-Video, C1): Dieses Gerät ist ein NICHT-
  /// führender Gruppen-Follower mit frischem Leader voraus. Statt des
  /// alarmierenden „Neuberechnung" zeigt das Banner dann ruhig „Folge der
  /// Gruppe", während die geteilte Leader-Route adoptiert wird — kein Flackern,
  /// kein Fehlalarm „ich suche", obwohl der Fahrer nur dem Leader folgt.
  final bool groupFollowerWaiting;

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
                  // 2026-06-19 (vucko Kreisverkehr 100% wie Apple): 3 Zeilen
                  // statt 2 — lange Kreisel-Ansagen („Im Kreisverkehr die N.
                  // Ausfahrt nehmen auf <Straße>") wurden sonst genau am
                  // Straßennamen abgeschnitten („…Dornbirner Straße…"). Apple
                  // zeigt den Zielnamen voll; die Spalte ist mainAxisSize.min,
                  // kurze Manöver bleiben also einzeilig.
                  maxLines: 3,
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
                Text(
                  groupFollowerWaiting ? 'Folge der Gruppe' : 'Neuberechnung',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  groupFollowerWaiting
                      ? 'Neue Route der Gruppe kommt gleich'
                      : isTakingLong
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
    final d = _resolveRoundaboutDesign(maneuver);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RoundaboutPainter(
          entryDeg: 180, // Einfahrt immer unten (Heading-up wie Apple/Google)
          exitDeg: d.exitDeg,
          armsDeg: d.armsDeg,
          islandScale: maneuver.roundaboutIslandScale ?? 1.0,
          armLenF: 1.0,
          arrival: maneuver.roundaboutIsArrival,
          accent: AppAccentColors.accent,
        ),
      ),
    );
  }
}

/// 2026-06-16 (vucko O9): Aufgelöste Design-Parameter (in der DESIGN-Konvention
/// des Figma: 0=oben, 90=rechts, 180=unten, 270=links, im Uhrzeigersinn). Die
/// Einfahrt liegt IMMER bei 180 (unten, Heading-up).
class _RoundaboutDesign {
  const _RoundaboutDesign({required this.exitDeg, required this.armsDeg});
  final double exitDeg;
  final List<double> armsDeg;
}

double _wrap360(double d) => ((d % 360) + 360) % 360;

/// Wandelt die geografischen Manöver-Daten (Kompass-Bearings aus OSM/Geometrie)
/// in die Design-Konvention um — Einfahrt nach unten (180) gedreht, übrige Arme
/// relativ dazu. Hat das Manöver echte OSM-Arme, werden sie 1:1 (nur rotiert)
/// übernommen; sonst wird eine plausible Topologie aus Ausfahrtsnummer +
/// turn_angle synthetisiert, damit das Symbol nie leer/kaputt wirkt.
_RoundaboutDesign _resolveRoundaboutDesign(RouteManeuver m) {
  final eB = m.roundaboutEntryBearing;
  final xB = m.roundaboutExitBearing;
  final arms = m.roundaboutArmBearings;
  final exitNumber = (m.roundaboutExitNumber ?? 1).clamp(1, 12);

  // 2026-06-19 (vucko Kreisverkehr 100% wie Apple): Der Ausfahrts-PFEIL kommt
  // IMMER aus der ECHTEN Routen-Geometrie (Einfahrts-Arm vs. Ausfahrts-Arm bzw.
  // der gefahrene Drehwinkel) und zeigt damit exakt dorthin, wo die rote Route
  // den Kreisel verlässt — NIE aus der Ausfahrtsnummer und NIE aus GHs
  // `turn_angle` (Deep-Research hat letzteres zum Positionieren 0:3 widerlegt).
  // So kann der Pfeil dem sichtbaren Linienverlauf nie widersprechen.
  double? exitDeg;
  if (eB != null && xB != null) {
    exitDeg = _wrap360(xB - eB + 180);
  } else if (m.roundaboutTurnAngleRad != null &&
      m.roundaboutTurnAngleRad!.isFinite) {
    // geomTurnRad: rechts positiv. Einfahrt unten (180), Fahrt nach oben (0);
    // eine Rechtsdrehung θ → Ausfahrt im Design-Winkel θ (im Uhrzeigersinn ab
    // oben). Das deckt sich exakt mit (xB − eB + 180) der echten Arme.
    exitDeg = _wrap360(m.roundaboutTurnAngleRad! * 180 / math.pi);
  }

  // Arme in Design-Konvention.
  List<double> armsDeg;
  if (eB != null && arms != null && arms.length >= 2) {
    // Echte OSM-Topologie: jeden Arm rotieren, Einfahrt + genommene Ausfahrt
    // exakt rasten → der Pfeil deckt sich mit einem echten Arm.
    final mapped = arms.map((b) => _wrap360(b - eB + 180)).toList();
    _snapNearest(mapped, 180); // Einfahrt
    if (exitDeg != null) _snapNearest(mapped, exitDeg); // genommene Ausfahrt
    armsDeg = mapped;
  } else {
    // KEINE OSM-Arme: sauberen Kreisel zeichnen, OHNE den Ausfahrts-Pfeil zu
    // verfälschen. Früher rastete die Ausfahrt auf die nächste Himmelsrichtung —
    // das verbog den Pfeil sichtbar weg von der roten Linie (genau der
    // Screenshot-Fehler). Jetzt: Einfahrt unten (180) + ECHTE Ausfahrt am realen
    // Winkel + plausible Füllarme, damit es nach Kreisverkehr aussieht und der
    // Pfeil trotzdem exakt auf der gefahrenen Ausfahrt sitzt.
    final ex = exitDeg ?? _wrap360(180 - exitNumber * 90);
    exitDeg = ex;
    armsDeg = _syntheticRoundaboutArms(ex);
  }
  return _RoundaboutDesign(exitDeg: exitDeg ?? 0, armsDeg: armsDeg);
}

/// Plausible Armverteilung, wenn KEINE OSM-Topologie vorliegt: Einfahrt (unten,
/// 180) + die echte genommene Ausfahrt [exitDeg] + Füllarme an Himmelsrichtungen,
/// die ≥35° Abstand zu allen bestehenden Armen halten. So wirkt das Symbol wie
/// ein echter Kreisverkehr, ohne den Ausfahrts-Pfeil zu verschieben.
List<double> _syntheticRoundaboutArms(double exitDeg) {
  final arms = <double>[180.0, _wrap360(exitDeg)];
  bool farEnough(double cand) => arms.every((a) {
        var d = (a - cand).abs() % 360.0;
        if (d > 180) d = 360 - d;
        return d >= 35.0;
      });
  for (final cand in const [0.0, 90.0, 270.0, 45.0, 135.0, 225.0, 315.0]) {
    if (arms.length >= 4) break;
    if (farEnough(cand)) arms.add(_wrap360(cand));
  }
  arms.sort();
  return arms;
}


void _snapNearest(List<double> list, double target) {
  var best = -1;
  var bestD = 999.0;
  for (var i = 0; i < list.length; i++) {
    var d = (list[i] - target).abs() % 360.0;
    if (d > 180) d = 360 - d;
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  if (best >= 0) list[best] = _wrap360(target);
}

/// Zeichnet das Kreisverkehr-Symbol — eine 1:1-Portierung der Figma-Vorlage
/// `RoundaboutIcon` (Cruise-Connector-Design, Datei RoundaboutIcons.tsx).
///
/// Konvention (Figma): Kompass-Grad 0=oben, 90=rechts, 180=unten, 270=links,
/// im Uhrzeigersinn. Rechtsverkehr → Kreisel wird gegen den Uhrzeigersinn
/// durchfahren (1. Ausfahrt rechts) → `dir = -1`. Struktur (Ring/Insel/Arme/
/// Chevrons/Pfeile) exakt aus dem Design; Akzentfarbe = App-Akzent.
/// Deckt JEDE Form ab: beliebige Armzahl/-winkel, Mini & große Kreisel
/// ([islandScale]), lange Zufahrten ([armLenF]), Umkehren/U-Turn (Bogen >180°)
/// und Ankunft am Kreisel ([arrival] → Ziel-Pin statt Ausfahrt-Pfeil).
class _RoundaboutPainter extends CustomPainter {
  _RoundaboutPainter({
    required this.entryDeg,
    required this.exitDeg,
    required this.armsDeg,
    required this.islandScale,
    required this.armLenF,
    required this.arrival,
    required this.accent,
  });

  final double entryDeg;
  final double exitDeg;
  final List<double> armsDeg;
  final double islandScale;
  final double armLenF;
  final bool arrival;
  final Color accent;

  // Struktur-Farben exakt aus dem Figma-Token-Objekt `C`.
  static const Color _road = Color(0xFF3A3A42);
  static const Color _island = Color(0xFF101013);
  static const Color _islandEdge = Color(0xFF3A3A42);

  // Kompass-Grad → Punkt (0=oben). dir steckt in ringArc.
  Offset _polar(Offset c, double r, double deg) {
    final rad = (deg - 90) * math.pi / 180.0;
    return Offset(c.dx + r * math.cos(rad), c.dy + r * math.sin(rad));
  }

  // Pfeil-Polygon: Spitze bei p, zeigt in Richtung deg (Kompass-Grad).
  Path _arrowHead(Offset p, double deg, double s) {
    final rad = (deg - 90) * math.pi / 180.0;
    final cos = math.cos(rad), sin = math.sin(rad);
    final back = s, half = s * 0.62;
    final l = Offset(p.dx - back * cos + half * sin, p.dy - back * sin - half * cos);
    final r = Offset(p.dx - back * cos - half * sin, p.dy - back * sin + half * cos);
    return Path()
      ..moveTo(p.dx, p.dy)
      ..lineTo(l.dx, l.dy)
      ..lineTo(r.dx, r.dy)
      ..close();
  }

  // Bogen entlang des Kreises, gegen den Uhrzeigersinn (dir = -1). Sweep wird in
  // [0,360) berechnet → eine fast-volle Umrundung (U-Turn) wird korrekt als
  // langer Bogen (largeArc) gezeichnet.
  Path _ringArc(Offset c, double r, double startDeg, double endDeg) {
    final s = _polar(c, r, startDeg);
    final e = _polar(c, r, endDeg);
    final sweep = _wrap360(startDeg - endDeg); // dir = -1
    final large = sweep > 180;
    return Path()
      ..moveTo(s.dx, s.dy)
      ..arcToPoint(
        e,
        radius: Radius.circular(r),
        largeArc: large,
        clockwise: false,
      );
  }

  // 2026-06-21 (vucko Geräte-Video „Kreisverkehr sieht katastrophal aus"):
  // KOMPLETT vereinfacht auf das klare Apple-/Google-Schema. Vorher: grauer
  // Arm-Kranz + 6 Chevrons + Fadenkreuz-Mitte → bei 50px ein unleserlicher
  // „durchgestrichener Kreis". Jetzt nur noch: neutraler Ring + die GENOMMENE
  // Route in Akzent (Einfahrt unten → Bogen → großer Ausfahrt-Pfeil). Immer
  // sauber lesbar, unabhängig von der (oft unsicheren) Arm-Topologie.
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);

    final ringR = s * 0.255; // Mittellinie der Kreisbahn
    final ringW = s * 0.11; // Bandbreite der Kreisbahn
    final islandR = math.max(s * 0.055, s * 0.075 * islandScale);
    final stub = s * 0.205 * armLenF.clamp(0.8, 1.2); // Ein-/Ausfahrt-Länge
    final travelW = s * 0.105; // Strichbreite der genommenen Route
    final arrowS = s * 0.092; // Größe Ausfahrt-Pfeil

    // Dezenter Aktiv-Glow.
    canvas.drawCircle(
      c,
      ringR + ringW * 0.5 + s * 0.045,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = accent.withValues(alpha: 0.16)
        ..strokeWidth = s * 0.02,
    );

    // Neutrale Kreisbahn (die Straße des Kreisverkehrs).
    canvas.drawCircle(
      c,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = _road
        ..strokeWidth = ringW,
    );

    // ── Genommene Route in Akzent ──────────────────────────────────────────
    final route = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = travelW;

    // Einfahrt-Stummel von außen (unten) an die Kreisbahn.
    canvas.drawLine(
      _polar(c, ringR + stub, entryDeg),
      _polar(c, ringR, entryDeg),
      route,
    );
    // Bogen auf der Kreisbahn (DACH = gegen den Uhrzeigersinn).
    canvas.drawPath(_ringArc(c, ringR, entryDeg, exitDeg), route);
    // Ausfahrt-Stummel von der Kreisbahn nach außen.
    canvas.drawLine(
      _polar(c, ringR, exitDeg),
      _polar(c, ringR + stub, exitDeg),
      route,
    );

    // Mittelinsel über der Bahn.
    canvas.drawCircle(c, islandR, Paint()..color = _island);
    canvas.drawCircle(
      c,
      islandR,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = _islandEdge
        ..strokeWidth = s * 0.012,
    );

    // Ausfahrt — großer Pfeil (oder Ziel-Pin bei Ankunft am Kreisel).
    final exitTip = _polar(c, ringR + stub, exitDeg);
    if (arrival) {
      canvas.drawCircle(exitTip, s * 0.085, Paint()..color = accent);
      canvas.drawCircle(
        exitTip,
        s * 0.036,
        Paint()..color = const Color(0xFFF4F4F6),
      );
    } else {
      canvas.drawPath(
        _arrowHead(exitTip, exitDeg, arrowS),
        Paint()..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(_RoundaboutPainter o) =>
      o.entryDeg != entryDeg ||
      o.exitDeg != exitDeg ||
      o.islandScale != islandScale ||
      o.armLenF != armLenF ||
      o.arrival != arrival ||
      o.accent != accent ||
      !listEquals(o.armsDeg, armsDeg);
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
