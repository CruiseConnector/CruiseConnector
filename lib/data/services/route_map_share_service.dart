import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 2026-06-25 (vucko Share-Rework): Erzeugt ein ECHTES Karten-Bild (PNG) mit der
/// Route darüber — für den Strava-artigen „Karte"-Share.
///
/// Warum nicht den eingebetteten MapLibre-View capturen? Platform-Views rendern
/// NICHT in den Flutter-Layer-Baum → RepaintBoundary→toImage liefert dort nur
/// Transparenz. Stattdessen werden hier die (dunklen, freien) Esri-Raster-Tiles
/// für die Routen-Bounding-Box geladen, auf einem Canvas zusammengesetzt und die
/// Routen-Polyline projiziert darübergezeichnet → ein normales Bild, das sich
/// problemlos teilen/überlagern lässt (wie Stravas Karten-Sticker).
class RouteMapShareService {
  RouteMapShareService._();

  static const _tileTemplate =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile';

  static double _mercX(double lng) => (lng + 180.0) / 360.0;
  static double _mercY(double lat) {
    final s = math.sin(lat * math.pi / 180.0).clamp(-0.9999, 0.9999);
    return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Baut das Karten-PNG für die Route ([lng,lat]-Punkte). Gibt null zurück,
  /// wenn zu wenig Punkte oder gar keine Tiles geladen werden konnten.
  static Future<Uint8List?> buildRouteMapPng({
    required List<List<double>> route,
    required Color accent,
    int targetPx = 900,
  }) async {
    if (route.length < 2) return null;
    var minLng = route.first[0], maxLng = route.first[0];
    var minLat = route.first[1], maxLat = route.first[1];
    for (final p in route) {
      minLng = math.min(minLng, p[0]);
      maxLng = math.max(maxLng, p[0]);
      minLat = math.min(minLat, p[1]);
      maxLat = math.max(maxLat, p[1]);
    }
    // 12 % Rand, plus Mindest-Padding für sehr kleine/punktförmige Routen.
    final padLng = (maxLng - minLng) * 0.12 + 0.0009;
    final padLat = (maxLat - minLat) * 0.12 + 0.0009;
    minLng -= padLng;
    maxLng += padLng;
    minLat -= padLat;
    maxLat += padLat;

    final mxMin = _mercX(minLng), mxMax = _mercX(maxLng);
    final myMin = _mercY(maxLat), myMax = _mercY(minLat); // y ist invertiert
    final spanX = (mxMax - mxMin).abs();
    final spanY = (myMax - myMin).abs();
    final maxSpan = math.max(math.max(spanX, spanY), 1e-7);

    // Zoom so wählen, dass die Box ~targetPx füllt; dann auf max. ~30 Tiles
    // begrenzen (Bandbreite/Zeit), Esri-Maxzoom ~16.
    var z = (math.log(targetPx / (maxSpan * 256)) / math.ln2).floor();
    z = z.clamp(3, 16);
    int countAt(int zz) {
      final n = 1 << zz;
      final x0 = (mxMin * n).floor(), x1 = (mxMax * n).floor();
      final y0 = (myMin * n).floor(), y1 = (myMax * n).floor();
      return (x1 - x0 + 1) * (y1 - y0 + 1);
    }

    while (z > 3 && countAt(z) > 30) {
      z--;
    }
    final n = 1 << z;
    final x0 = (mxMin * n).floor(), x1 = (mxMax * n).floor();
    final y0 = (myMin * n).floor(), y1 = (myMax * n).floor();
    final xCount = x1 - x0 + 1, yCount = y1 - y0 + 1;
    final w = xCount * 256, h = yCount * 256;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFF0D1117),
    );

    var anyTile = false;
    for (var tx = x0; tx <= x1; tx++) {
      for (var ty = y0; ty <= y1; ty++) {
        try {
          final resp = await http
              .get(Uri.parse('$_tileTemplate/$z/$ty/$tx'))
              .timeout(const Duration(seconds: 8));
          if (resp.statusCode != 200) continue;
          final img = await _decode(resp.bodyBytes);
          final dx = ((tx - x0) * 256).toDouble();
          final dy = ((ty - y0) * 256).toDouble();
          canvas.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            Rect.fromLTWH(dx, dy, 256, 256),
            Paint()..filterQuality = FilterQuality.medium,
          );
          img.dispose();
          anyTile = true;
        } catch (_) {}
      }
    }
    if (!anyTile) return null;

    Offset proj(List<double> p) => Offset(
          _mercX(p[0]) * n * 256 - x0 * 256,
          _mercY(p[1]) * n * 256 - y0 * 256,
        );

    final path = Path();
    final first = proj(route.first);
    path.moveTo(first.dx, first.dy);
    for (final p in route.skip(1)) {
      final o = proj(p);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    final s = proj(route.first), e = proj(route.last);
    canvas.drawCircle(s, 9, Paint()..color = Colors.white);
    canvas.drawCircle(s, 5, Paint()..color = accent);
    canvas.drawCircle(e, 9, Paint()..color = Colors.white);
    canvas.drawCircle(e, 5, Paint()..color = const Color(0xFFFFD166));

    final outImg = await recorder.endRecording().toImage(w, h);
    final bd = await outImg.toByteData(format: ui.ImageByteFormat.png);
    outImg.dispose();
    return bd?.buffer.asUint8List();
  }
}
