import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:cruise_connect/core/routen_kappung.dart';

/// Nachgezeichnete Strecke OHNE Karte (2026-08-28, Fehler 7 und 8).
///
/// Geteilte Routen zeigten bisher einen Kartenausschnitt mit Ortsnamen,
/// Doerfern und dem exakten Start- und Zielpunkt — meist die Haustuer des
/// Besitzers. Diese Skizze zeichnet NUR den Verlauf der Linie auf neutralem,
/// dunklem Grund, im Stil des Export-Composers (route_share_page):
/// Verlaufslinie mit rundem Abschluss, dezenter Start- und Zielpunkt OHNE
/// Beschriftung. Keine Basemap, keine Ortsnamen, kein Massstab.
///
/// Die Punkte werden vor dem Zeichnen standardmaessig um
/// [anzeigeKappungMeter] je Ende gekappt (kappeEndstuecke). Aufrufer, die
/// bereits gekappte Punkte uebergeben, setzen [kappungMeter] auf 0.
class RouteVerlaufSketch extends StatelessWidget {
  const RouteVerlaufSketch({
    super.key,
    required this.punkte,
    required this.accent,
    this.kappungMeter = anzeigeKappungMeter,
    this.hintergrund = const Color(0xFF10141B),
    this.borderRadius,
  });

  /// Flache [longitude, latitude]-Liste (Mapbox-Format), z. B. aus
  /// `SavedRoute.flattenGeometryCoordinates` — traegt auch MultiLineString.
  final List<List<double>> punkte;

  final Color accent;

  /// Meter, die je Ende vor dem Zeichnen entfernt werden. 0 = Punkte sind
  /// schon gekappt (oder es ist die eigene Route).
  final double kappungMeter;

  final Color hintergrund;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final gezeichnet = kappungMeter > 0
        ? kappeEndstuecke(punkte, kappungMeter, kappungMeter)
        : punkte;
    return Container(
      decoration: BoxDecoration(
        color: hintergrund,
        borderRadius: borderRadius ?? BorderRadius.circular(14),
      ),
      clipBehavior: borderRadius == BorderRadius.zero
          ? Clip.none
          : Clip.antiAlias,
      child: gezeichnet.length < 2
          ? const Center(
              child: Icon(Icons.route_rounded, color: Colors.white24, size: 28),
            )
          : CustomPaint(
              size: Size.infinite,
              painter: RouteVerlaufPainter(punkte: gezeichnet, accent: accent),
            ),
    );
  }
}

/// Zeichnet die (bereits gekappte) Linie: Halo, Verlaufslinie von Akzent zu
/// einer helleren Stufe, runde Enden, dezente Punkte an Anfang und Ende —
/// bewusst ohne jede Beschriftung.
class RouteVerlaufPainter extends CustomPainter {
  RouteVerlaufPainter({required this.punkte, required this.accent});

  final List<List<double>> punkte;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (punkte.length < 2 || size.isEmpty) return;

    var minLng = punkte.first[0], maxLng = punkte.first[0];
    var minLat = punkte.first[1], maxLat = punkte.first[1];
    for (final p in punkte) {
      minLng = math.min(minLng, p[0]);
      maxLng = math.max(maxLng, p[0]);
      minLat = math.min(minLat, p[1]);
      maxLat = math.max(maxLat, p[1]);
    }
    const pad = 16.0;
    final lngSpan = math.max(maxLng - minLng, 0.0001);
    final latSpan = math.max(maxLat - minLat, 0.0001);
    // Laengengrade werden zum Pol hin schmaler — ohne Korrektur wirkt die
    // Strecke in Ost-West-Richtung gestaucht. cos(Breite) reicht fuer eine
    // Skizze vollkommen.
    final latMitte = (minLat + maxLat) / 2 * math.pi / 180.0;
    final lngFaktor = math.max(math.cos(latMitte).abs(), 0.05);
    final scale = math.min(
      (size.width - 2 * pad) / (lngSpan * lngFaktor),
      (size.height - 2 * pad) / latSpan,
    );
    final w = lngSpan * lngFaktor * scale, h = latSpan * scale;
    final ox = (size.width - w) / 2, oy = (size.height - h) / 2;
    Offset project(List<double> p) => Offset(
          ox + (p[0] - minLng) * lngFaktor * scale,
          oy + (maxLat - p[1]) * scale,
        );

    final path = Path();
    final start = project(punkte.first);
    path.moveTo(start.dx, start.dy);
    for (final p in punkte.skip(1)) {
      final pr = project(p);
      path.lineTo(pr.dx, pr.dy);
    }
    final ende = project(punkte.last);

    final halo = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final hell = Color.lerp(accent, Colors.white, 0.45)!;
    final linie = Paint()
      ..shader = ui.Gradient.linear(start, ende, [accent, hell])
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, halo);
    canvas.drawPath(path, linie);

    // Dezente Endpunkte OHNE Beschriftung — sie markieren nur den Anfang und
    // das Ende der GEKAPPTEN Linie, nie die echte Adresse.
    canvas.drawCircle(start, 5, Paint()..color = Colors.white);
    canvas.drawCircle(start, 2.8, Paint()..color = accent);
    canvas.drawCircle(ende, 5, Paint()..color = Colors.white);
    canvas.drawCircle(ende, 2.8, Paint()..color = const Color(0xFFFFD166));
  }

  @override
  bool shouldRepaint(RouteVerlaufPainter old) =>
      old.punkte != punkte || old.accent != accent;
}
