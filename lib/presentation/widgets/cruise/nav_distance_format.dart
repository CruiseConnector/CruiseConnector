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
  // Saubere 10-m-Stufen: 670, 680, 690 … nie 671, 683, 522.
  final rounded = ((m / 10).round() * 10).clamp(0, 990).toInt();
  return '$rounded m';
}
