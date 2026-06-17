import 'dart:math' as math;

/// 2026-06-13 (vucko J2): Google-Maps-Style Distanz-Formatierung für die
/// Navigation. Der User will saubere Stufen statt „krummer" Zahlen wie 522 m:
///
/// - ≥ 10 km   → ganze Kilometer        („26 km")
/// - 1–10 km   → ein Dezimal            („2,1 km")
/// - < 1 km    → saubere 10-m-Stufen    („690 m", „680 m", „670 m")
/// - < 10 m    → „Jetzt"                 (Manöver praktisch erreicht)
///
/// Eine einzige Quelle, damit Manöver-Banner und Rest-Distanz-Karte exakt
/// gleich runden.
String formatNavDistance(double? meters, {bool nowLabelUnderTen = false}) {
  if (meters == null) return '--';
  final m = meters < 0 ? 0.0 : meters;

  if (m >= 10000.0) {
    return '${(m / 1000.0).round()} km';
  }
  if (m >= 1000.0) {
    return '${(m / 1000.0).toStringAsFixed(1).replaceAll('.', ',')} km';
  }
  if (nowLabelUnderTen && m < 10.0) {
    return 'Jetzt';
  }
  // 2026-06-15 (vucko M3): Kadenz wie Google. Unter 200 m IMMER feine 10-m-
  // Stufen (kurz vor dem Manöver zählt jeder Schritt); darüber gröber, damit
  // die Zahl bei Tempo nicht hektisch springt: 200–500 m → 20-m-Stufen,
  // 500–<1000 m → 50-m-Stufen. Nie krumm (670/680/690 statt 671/683).
  final step = m <= 200.0
      ? 10
      : m <= 500.0
          ? 20
          : 50;
  final rounded = ((m / step).round() * step).clamp(0, 990).toInt();
  return '$rounded m';
}

/// 2026-06-17 (vucko Schnellstraße-Freeze, Video): Gleitende Manöver-Distanz für
/// die Banner-ANZEIGE.
///
/// [base] = stabile Index-Distanz (`Σ` Segmentlängen vom aktuellen Routen-Index
/// bis zum Manöver). Die springt NUR, wenn der Puck einen Routen-Stützpunkt
/// überfährt — auf Schnellstraßen liegen die aber weit auseinander, also steht
/// [base] zwischen zwei Stützpunkten lange still (das eingefrorene „1,0 km").
///
/// [render] ist die KONTINUIERLICHE Render-Distanz am Puck (gleitet pro Frame),
/// [cum] die kumulierten Segmentlängen. Es gilt geometrisch:
///   base − (render − cum[index]) == cum[Manöver] − render
/// also exakt die echte, pro Frame gleitende Restdistanz zum Manöver.
///
/// FRÜHER kappte eine 80-m-Grenze diesen Vorlauf → auf Schnellstraßen (Vorlauf
/// schnell > 80 m) fiel die Anzeige auf den eingefrorenen Index-Wert zurück und
/// klebte z. B. bei „1,0 km", obwohl der Wagen längst weiterfuhr. Jetzt wird der
/// gesamte plausible Vorlauf abgezogen. Nur unplausible Render-Werte fallen auf
/// [base] zurück: render HINTER dem Index (`ahead <= 0`, stale) oder render WEIT
/// hinter das Manöver (`ahead > base + Puffer`, Render-Sprung/Teleport).
double smoothManeuverDistanceMeters({
  required double base,
  required List<double> cum,
  required double render,
  required int currentIndex,
}) {
  if (render < 0 || cum.isEmpty) return base;
  final cri = currentIndex < 0
      ? 0
      : (currentIndex > cum.length - 1 ? cum.length - 1 : currentIndex);
  final ahead = render - cum[cri];
  if (ahead <= 0 || ahead > base + 150.0) return base;
  final smooth = base - ahead;
  if (smooth < 0.0) return 0.0;
  return smooth > base ? base : smooth;
}

/// 2026-06-17 (vucko Geräte-Video: Manöver-Distanz friert ein / springt HOCH):
/// Hält die ANGEZEIGTE Manöver-Distanz innerhalb DESSELBEN Manövers monoton
/// fallend und gleitet weich zum Ziel. Damit verschwinden zwei Video-Befunde:
///   - Sprünge nach OBEN innerhalb eines Manövers („10 m → 40 m" am Routenende,
///     „50 m → 110 m") durch Route-Re-Anchor / Render-Lag → werden GEHALTEN.
///   - grobe Stufen mit Sekunden-Halten an Kreisverkehren/Schnellstraßen
///     („850 → 800 → 700") → werden weich heruntergeführt.
/// Bei einem ECHTEN neuen Manöver ([maneuverChanged]: Manöver überfahren oder
/// Reroute → neuer Routen-Index) wird auf den neuen (i.d.R. größeren) Wert
/// gesnappt — das ist korrekt, nicht der Bug. [dtMs] zeitnormiert die Glättung
/// auf die ~90 ms-Banner-Kadenz. Pur, damit unit-testbar.
double monotonicManeuverDistanceMeters({
  required double? prevShown,
  required double target,
  required bool maneuverChanged,
  int dtMs = 90,
  double perFrameEase = 0.35,
  double snapEpsilonMeters = 1.5,
}) {
  final t = target.isFinite && target > 0 ? target : 0.0;
  if (prevShown == null || maneuverChanged || !prevShown.isFinite) return t;
  final prev = prevShown;
  if (t >= prev) return prev; // würde nach OBEN springen → halten
  if (prev - t <= snapEpsilonMeters) return t; // praktisch erreicht → snappen
  final clampedDt = dtMs <= 0
      ? 90
      : dtMs > 1000
          ? 1000
          : dtMs;
  final ease = 1.0 - math.pow(1.0 - perFrameEase, clampedDt / 90.0).toDouble();
  final eased = prev + (t - prev) * ease;
  return eased < t ? t : eased; // nie unter das Ziel
}
