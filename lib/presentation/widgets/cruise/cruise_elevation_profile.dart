import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;

/// Kompaktes Höhenprofil der Route, zeigt Steigungen/Gefälle visuell.
/// Berechnet Höhendaten aus Koordinaten (Mapbox liefert keine Elevation,
/// daher schätzen wir relativ anhand der GPS-Daten oder zeigen
/// das vom Isolate berechnete Profil).
class CruiseElevationProfile extends StatelessWidget {
  const CruiseElevationProfile({
    super.key,
    required this.elevations,
    this.currentProgress = 0.0,
    this.height = 48.0,
  });

  /// Höhenwerte entlang der Route (in Metern).
  final List<double> elevations;

  /// Fortschritt auf der Route (0.0 – 1.0).
  final double currentProgress;

  /// Höhe des Widgets.
  final double height;

  @override
  Widget build(BuildContext context) {
    if (elevations.length < 2) return const SizedBox.shrink();

    final minElev = elevations.reduce(math.min);
    final maxElev = elevations.reduce(math.max);
    final totalClimb = _totalClimb();
    final totalDescent = _totalDescent();

    return Container(
      height: height + 28,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2028).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          // Höhenstatistiken
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatChip(
                icon: Icons.arrow_upward_rounded,
                color: const Color(0xFF34C759),
                label: '+${totalClimb.round()} m',
              ),
              _StatChip(
                icon: Icons.terrain_rounded,
                color: Colors.white54,
                label: '${minElev.round()}–${maxElev.round()} m',
              ),
              _StatChip(
                icon: Icons.arrow_downward_rounded,
                color: const Color(0xFFFF6B6B),
                label: '-${totalDescent.round()} m',
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Profil-Chart
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _ElevationPainter(
                elevations: elevations,
                progress: currentProgress.clamp(0.0, 1.0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _totalClimb() {
    double climb = 0;
    for (var i = 1; i < elevations.length; i++) {
      final diff = elevations[i] - elevations[i - 1];
      if (diff > 0) climb += diff;
    }
    return climb;
  }

  double _totalDescent() {
    double descent = 0;
    for (var i = 1; i < elevations.length; i++) {
      final diff = elevations[i] - elevations[i - 1];
      if (diff < 0) descent += diff.abs();
    }
    return descent;
  }

  /// Berechnet ein synthetisches Höhenprofil aus Routenkoordinaten.
  /// Nutzt Haversine-Distanzen und simuliert Terrain anhand von
  /// Koordinatenmustern (Richtungswechsel = Hügel).
  static List<double> estimateFromCoordinates(
    List<List<double>> coords, {
    int sampleCount = 80,
  }) {
    if (coords.length < 2) return const [];

    // Strecke in gleichmäßige Segmente teilen
    final cumDist = <double>[0];
    for (var i = 1; i < coords.length; i++) {
      cumDist.add(cumDist.last +
          geo.Geolocator.distanceBetween(
            coords[i - 1][1], coords[i - 1][0],
            coords[i][1], coords[i][0],
          ));
    }
    final totalDist = cumDist.last;
    if (totalDist < 100) return const [];

    // Samples gleichmäßig über die Strecke verteilen
    final step = totalDist / (sampleCount - 1);
    final elevations = <double>[];

    // Basis-Höhe mit sanftem Rauschen simulieren
    // Wir nutzen Bearing-Änderungen als Proxy für Terrain-Variation
    final rng = math.Random(coords.first[0].hashCode ^ coords.first[1].hashCode);
    double altitude = 400 + rng.nextDouble() * 200; // Starthoehe ~400-600m
    double momentum = 0;

    var coordIdx = 0;
    for (var s = 0; s < sampleCount; s++) {
      final targetDist = s * step;

      // Finde das passende Koordinaten-Segment
      while (coordIdx < cumDist.length - 1 && cumDist[coordIdx + 1] < targetDist) {
        coordIdx++;
      }

      // Bearing-Change als Höhenänderungs-Proxy
      final lookAhead = math.min(coordIdx + 5, coords.length - 1);
      final lookBehind = math.max(coordIdx - 5, 0);
      double bearingChange = 0;
      if (lookAhead > lookBehind + 1) {
        final b1 = math.atan2(
          coords[coordIdx][0] - coords[lookBehind][0],
          coords[coordIdx][1] - coords[lookBehind][1],
        );
        final b2 = math.atan2(
          coords[lookAhead][0] - coords[coordIdx][0],
          coords[lookAhead][1] - coords[coordIdx][1],
        );
        bearingChange = (b2 - b1).abs();
        if (bearingChange > math.pi) bearingChange = 2 * math.pi - bearingChange;
      }

      // Höhenänderung: Kurven = tendenziell Hügel/Täler
      final terrainNoise = (rng.nextDouble() - 0.5) * 3;
      final curveInfluence = bearingChange * 15 * (rng.nextBool() ? 1 : -1);
      momentum = momentum * 0.85 + (terrainNoise + curveInfluence) * 0.15;
      altitude += momentum;
      altitude = altitude.clamp(200, 1200);

      elevations.add(altitude);
    }

    return elevations;
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _ElevationPainter extends CustomPainter {
  _ElevationPainter({required this.elevations, required this.progress});

  final List<double> elevations;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (elevations.length < 2) return;

    final minE = elevations.reduce(math.min);
    final maxE = elevations.reduce(math.max);
    final range = maxE - minE;
    if (range < 1) return;

    final w = size.width;
    final h = size.height;
    final stepX = w / (elevations.length - 1);

    // Pfad für das Profil erstellen
    final profilePath = Path();
    profilePath.moveTo(0, h - ((elevations[0] - minE) / range) * h);
    for (var i = 1; i < elevations.length; i++) {
      final x = i * stepX;
      final y = h - ((elevations[i] - minE) / range) * h;
      // Smooth Bezier statt harter Linien
      final prevX = (i - 1) * stepX;
      final prevY = h - ((elevations[i - 1] - minE) / range) * h;
      final cpX = (prevX + x) / 2;
      profilePath.cubicTo(cpX, prevY, cpX, y, x, y);
    }

    // Gefüllter Bereich unter dem Profil (gefahrener Teil = orange)
    final progressX = progress * w;

    // Hintergrund-Füllung (gesamte Route, dunkelgrau)
    final bgFillPath = Path.from(profilePath)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      bgFillPath,
      Paint()..color = Colors.white.withValues(alpha: 0.05),
    );

    // Gefahrener Abschnitt (orange gradient)
    if (progress > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, progressX, h));
      final drivenFillPath = Path.from(profilePath)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFFF5722).withValues(alpha: 0.35),
          const Color(0xFFFF5722).withValues(alpha: 0.05),
        ],
      );
      canvas.drawPath(
        drivenFillPath,
        Paint()..shader = gradient.createShader(Rect.fromLTWH(0, 0, w, h)),
      );
      canvas.restore();
    }

    // Profillinie
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..isAntiAlias = true;
    canvas.drawPath(profilePath, linePaint);

    // Gefahrener Teil der Linie (orange)
    if (progress > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, progressX, h));
      canvas.drawPath(
        profilePath,
        Paint()
          ..color = const Color(0xFFFF5722)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..isAntiAlias = true,
      );
      canvas.restore();
    }

    // Positions-Marker
    if (progress > 0 && progress < 1) {
      final idx = (progress * (elevations.length - 1)).round().clamp(0, elevations.length - 1);
      final markerY = h - ((elevations[idx] - minE) / range) * h;
      canvas.drawCircle(
        Offset(progressX, markerY),
        4,
        Paint()..color = const Color(0xFFFF5722),
      );
      canvas.drawCircle(
        Offset(progressX, markerY),
        2,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_ElevationPainter old) =>
      old.progress != progress || old.elevations != elevations;
}
