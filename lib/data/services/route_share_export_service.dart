import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:cruise_connect/domain/models/saved_route.dart';

class RouteShareExportService {
  static Future<Uint8List> buildTransparentRoutePng({
    required SavedRoute route,
    required Color accent,
    double pixelRatio = 2,
  }) async {
    final coordinates = _extractCoordinates(route);
    if (coordinates.length < 2) {
      throw StateError('Route hat keine exportierbare Geometrie.');
    }

    const logicalSize = Size(720, 720);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(
        0,
        0,
        logicalSize.width * pixelRatio,
        logicalSize.height * pixelRatio,
      ),
    );
    canvas.scale(pixelRatio, pixelRatio);

    final routeBounds = Rect.fromLTWH(56, 52, logicalSize.width - 112, 390);
    _drawRoute(canvas, coordinates, routeBounds, accent);
    _drawInfoPanel(canvas, route, accent, logicalSize);

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (logicalSize.width * pixelRatio).round(),
      (logicalSize.height * pixelRatio).round(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Route konnte nicht als PNG gerendert werden.');
    }
    return byteData.buffer.asUint8List();
  }

  static List<Offset> _extractCoordinates(SavedRoute route) {
    final raw = route.geometry['coordinates'];
    if (raw is! List) return const [];
    final points = <Offset>[];
    for (final item in raw) {
      if (item is List && item.length >= 2) {
        final lng = item[0];
        final lat = item[1];
        if (lng is num && lat is num) {
          points.add(Offset(lng.toDouble(), lat.toDouble()));
        }
      }
    }
    return points;
  }

  static void _drawRoute(
    Canvas canvas,
    List<Offset> coordinates,
    Rect bounds,
    Color accent,
  ) {
    var minLng = coordinates.first.dx;
    var maxLng = coordinates.first.dx;
    var minLat = coordinates.first.dy;
    var maxLat = coordinates.first.dy;
    for (final point in coordinates) {
      minLng = math.min(minLng, point.dx);
      maxLng = math.max(maxLng, point.dx);
      minLat = math.min(minLat, point.dy);
      maxLat = math.max(maxLat, point.dy);
    }

    final lngSpan = math.max(maxLng - minLng, 0.0001);
    final latSpan = math.max(maxLat - minLat, 0.0001);
    final scale = math.min(bounds.width / lngSpan, bounds.height / latSpan);
    final routeWidth = lngSpan * scale;
    final routeHeight = latSpan * scale;
    final dx = bounds.left + (bounds.width - routeWidth) / 2;
    final dy = bounds.top + (bounds.height - routeHeight) / 2;

    Offset project(Offset point) {
      return Offset(
        dx + (point.dx - minLng) * scale,
        dy + (maxLat - point.dy) * scale,
      );
    }

    final path = Path()
      ..moveTo(project(coordinates.first).dx, project(coordinates.first).dy);
    for (final point in coordinates.skip(1)) {
      final projected = project(point);
      path.lineTo(projected.dx, projected.dy);
    }

    final halo = Paint()
      ..color = Colors.black.withValues(alpha: 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final glow = Paint()
      ..color = accent.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    final line = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, halo);
    canvas.drawPath(path, glow);
    canvas.drawPath(path, line);

    final start = project(coordinates.first);
    final finish = project(coordinates.last);
    final dotStroke = Paint()..color = Colors.white;
    final dotFill = Paint()..color = accent;
    canvas.drawCircle(start, 11, dotStroke);
    canvas.drawCircle(start, 6.5, dotFill);
    canvas.drawCircle(finish, 11, dotStroke);
    canvas.drawCircle(finish, 6.5, Paint()..color = const Color(0xFFFFD166));
  }

  static void _drawInfoPanel(
    Canvas canvas,
    SavedRoute route,
    Color accent,
    Size size,
  ) {
    final panelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(46, 456, size.width - 92, 196),
      const Radius.circular(34),
    );
    canvas.drawRRect(
      panelRect,
      Paint()..color = const Color(0xFF12161F).withValues(alpha: 0.86),
    );
    canvas.drawRRect(
      panelRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.12),
    );

    _drawText(
      canvas,
      route.name?.trim().isNotEmpty == true
          ? route.name!.trim()
          : '${route.displayStyleLabel} Route',
      const Offset(82, 492),
      maxWidth: 500,
      fontSize: 28,
      fontWeight: FontWeight.w800,
      color: Colors.white,
      maxLines: 1,
    );
    _drawText(
      canvas,
      'CruiseConnect',
      const Offset(82, 618),
      maxWidth: 220,
      fontSize: 17,
      fontWeight: FontWeight.w800,
      color: Colors.white.withValues(alpha: 0.78),
    );

    final chips = <_ExportChip>[
      _ExportChip(route.formattedDistance),
      _ExportChip(route.displayStyleLabel),
      _ExportChip(route.ratingShareLabel ?? 'Keine Bewertung'),
      if (route.qualityBadgeLabel != null)
        _ExportChip(route.qualityBadgeLabel!),
    ];

    var chipOffset = const Offset(82, 548);
    for (final chip in chips.take(4)) {
      final width = _chipWidth(chip.label);
      if (chipOffset.dx + width > size.width - 74) {
        chipOffset = Offset(82, chipOffset.dy + 36);
      }
      _drawChip(canvas, chip, chipOffset, width, accent);
      chipOffset = Offset(chipOffset.dx + width + 10, chipOffset.dy);
    }
  }

  static void _drawChip(
    Canvas canvas,
    _ExportChip chip,
    Offset offset,
    double width,
    Color accent,
  ) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(offset.dx, offset.dy, width, 28),
      const Radius.circular(999),
    );
    canvas.drawRRect(rect, Paint()..color = accent.withValues(alpha: 0.18));
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: 0.34),
    );
    _drawText(
      canvas,
      chip.label,
      Offset(offset.dx + 13, offset.dy + 5),
      maxWidth: width - 26,
      fontSize: 13,
      fontWeight: FontWeight.w800,
      color: Colors.white.withValues(alpha: 0.92),
      maxLines: 1,
    );
  }

  static double _chipWidth(String label) {
    return math.min(178, math.max(76, label.length * 8.2 + 28));
  }

  static void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    required double maxWidth,
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    int? maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1.08,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }
}

class _ExportChip {
  const _ExportChip(this.label);

  final String label;
}
