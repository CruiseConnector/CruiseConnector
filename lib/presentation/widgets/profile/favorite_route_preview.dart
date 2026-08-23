import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:cruise_connect/domain/models/saved_route.dart';

/// Zeichnet den Streckenverlauf einer Route als Miniatur.
///
/// 2026-08-19 (Top-3-Lieblingsrouten): Bewusst ein [CustomPainter] und keine
/// eingebettete Karte. Auf einem Profil koennen drei Vorschauen gleichzeitig
/// stehen; drei MapLibre-Platform-Views waeren drei GPU-Surfaces fuer ein
/// Bild, das sich nie bewegt. Die Geometrie liegt mit der Route ohnehin schon
/// im Speicher.
class FavoriteRoutePreview extends StatelessWidget {
  const FavoriteRoutePreview({
    super.key,
    required this.route,
    required this.accent,
  });

  final SavedRoute route;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final photoUrl = route.photoUrl?.trim();
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF141821), Color(0xFF0C0E14)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Eigenes Foto der Route schlaegt die Skizze — es ist das
          // persoenlichere Bild und genau das, was ein Highlight sein soll.
          if (photoUrl != null && photoUrl.isNotEmpty)
            Image.network(
              photoUrl,
              fit: BoxFit.cover,
              // Ladefehler duerfen die Kachel nicht sprengen: dann eben die
              // Linienskizze, die immer funktioniert.
              errorBuilder: (_, _, _) => _sketch(),
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : _sketch(),
            )
          else
            _sketch(),
          // Verlauf nach unten, damit die Beschriftung darueber lesbar bleibt.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xCC0B0E14)],
                stops: [0.45, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sketch() {
    return CustomPaint(
      painter: _RouteSketchPainter(
        coordinates: route.flatCoordinates,
        accent: accent,
        isRoundTrip: route.isRoundTrip,
      ),
    );
  }
}

class _RouteSketchPainter extends CustomPainter {
  _RouteSketchPainter({
    required this.coordinates,
    required this.accent,
    required this.isRoundTrip,
  });

  /// Flache `[lng, lat]`-Liste (Mapbox-Reihenfolge, wie ueberall in der App).
  final List<List<double>> coordinates;
  final Color accent;
  final bool isRoundTrip;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final points = _project(size);
    if (points.length < 2) {
      _paintPlaceholder(canvas, size);
      return;
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    // Dunkles Casing unter der Linie — derselbe Aufbau wie auf der Karte,
    // damit die Strecke auch auf hellen Fotos ablesbar bleibt.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF05070B).withValues(alpha: 0.85),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = accent,
    );

    // Start-/Zielpunkt. Beim Rundkurs faellt beides zusammen — dann nur EIN
    // Punkt, sonst saehe es nach einem Fehler aus.
    _paintDot(canvas, points.first, accent);
    if (!isRoundTrip) _paintDot(canvas, points.last, Colors.white);
  }

  /// Projiziert die Geometrie flaechenfuellend in [size].
  ///
  /// Der Breitengrad wird mit `cos(lat)` gestaucht, sonst wirken Strecken in
  /// noerdlichen Breiten in Ost-West-Richtung gedehnt. Beide Achsen teilen
  /// sich denselben Massstab, damit die Form der Strecke erhalten bleibt.
  List<Offset> _project(Size size) {
    if (coordinates.length < 2) return const [];

    var minLng = double.infinity, maxLng = double.negativeInfinity;
    var minLat = double.infinity, maxLat = double.negativeInfinity;
    for (final point in coordinates) {
      minLng = math.min(minLng, point[0]);
      maxLng = math.max(maxLng, point[0]);
      minLat = math.min(minLat, point[1]);
      maxLat = math.max(maxLat, point[1]);
    }
    if (!minLng.isFinite || !minLat.isFinite) return const [];

    final centerLatRad = ((minLat + maxLat) / 2) * math.pi / 180.0;
    final lngScale = math.cos(centerLatRad).abs().clamp(0.05, 1.0);

    // Nie durch 0 teilen: eine punktfoermige Strecke landet sonst im NaN.
    final spanX = math.max((maxLng - minLng) * lngScale, 1e-9);
    final spanY = math.max(maxLat - minLat, 1e-9);

    const padding = 14.0;
    final usableWidth = math.max(size.width - padding * 2, 1.0);
    final usableHeight = math.max(size.height - padding * 2, 1.0);
    final scale = math.min(usableWidth / spanX, usableHeight / spanY);

    final offsetX = (size.width - spanX * scale) / 2;
    final offsetY = (size.height - spanY * scale) / 2;

    return [
      for (final point in _thinned())
        Offset(
          offsetX + (point[0] - minLng) * lngScale * scale,
          // Bildschirm-Y waechst nach unten, Breitengrad nach oben.
          offsetY + (maxLat - point[1]) * scale,
        ),
    ];
  }

  /// Duennt sehr lange Tracks gleichmaessig aus. Eine 90-km-Fahrt bringt
  /// mehrere tausend Punkte mit; auf ~160 logischen Pixeln ist alles ueber
  /// ~400 Stuetzpunkten unsichtbar, kostet aber jeden Frame Zeit.
  List<List<double>> _thinned() {
    const maxPoints = 400;
    if (coordinates.length <= maxPoints) return coordinates;
    final step = (coordinates.length / maxPoints).ceil();
    final result = <List<double>>[];
    for (var i = 0; i < coordinates.length; i += step) {
      result.add(coordinates[i]);
    }
    // Der letzte Punkt muss dabei sein, sonst endet die Linie im Nichts.
    if (result.last != coordinates.last) result.add(coordinates.last);
    return result;
  }

  void _paintDot(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(
      center,
      4.6,
      Paint()..color = const Color(0xFF05070B).withValues(alpha: 0.9),
    );
    canvas.drawCircle(center, 3.0, Paint()..color = color);
  }

  /// Fallback fuer Routen ohne brauchbare Geometrie (alte Zeilen, in denen
  /// `geometry` leer ist). Lieber ein ruhiges Symbol als eine leere Flaeche.
  void _paintPlaceholder(Canvas canvas, Size size) {
    const icon = Icons.route_rounded;
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: math.min(size.width, size.height) * 0.34,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: accent.withValues(alpha: 0.35),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _RouteSketchPainter oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.isRoundTrip != isRoundTrip ||
        !identical(oldDelegate.coordinates, coordinates);
  }
}
