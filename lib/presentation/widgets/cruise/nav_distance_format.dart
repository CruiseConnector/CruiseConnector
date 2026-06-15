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
