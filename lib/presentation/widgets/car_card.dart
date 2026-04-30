import 'package:flutter/material.dart';

/// Auto-Profil-Karte im Ferrari-F8-Spider-Verkaufsanzeigen-Stil.
/// Schwarzer Hintergrund, gelb-rot Akzente, große Bild-Sektion oben,
/// klare Stammdaten-Tabelle unten mit Trenn-Linien.
///
/// Akzeptiert ein `profile`-Map mit den `car_*`-Feldern (siehe DB-Migration
/// `db_migrations/2026_04_27_profile_banner_and_car.sql`).
class CarCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  final VoidCallback? onTap;

  /// CruiseConnect-Markenrot — wird als Akzentfarbe verwendet.
  static const Color accent = Color(0xFFFF3B30);

  const CarCard({
    super.key,
    required this.profile,
    this.onTap,
  });

  /// True, wenn keinerlei Auto-Daten gesetzt sind.
  static bool isEmpty(Map<String, dynamic> profile) {
    return _str(profile['car_brand']) == null &&
        _str(profile['car_name']) == null &&
        profile['car_top_speed'] == null &&
        profile['car_engine_size'] == null &&
        profile['car_displacement'] == null &&
        profile['car_cylinders'] == null &&
        profile['car_horsepower'] == null &&
        profile['car_year'] == null &&
        _str(profile['car_first_reg']) == null &&
        profile['car_mileage'] == null &&
        _str(profile['car_image_url']) == null;
  }

  static String? _str(dynamic v) {
    final s = (v as String?)?.trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  @override
  Widget build(BuildContext context) {
    final brand = _str(profile['car_brand'])?.toUpperCase();
    final name = _str(profile['car_name']);
    final imageUrl = _str(profile['car_image_url']);
    final topSpeed = (profile['car_top_speed'] as num?)?.toInt();
    final engineSize = (profile['car_engine_size'] as num?)?.toDouble();
    final displacement = (profile['car_displacement'] as num?)?.toInt();
    final cylinders = (profile['car_cylinders'] as num?)?.toInt();
    final horsepower = (profile['car_horsepower'] as num?)?.toInt();
    final year = (profile['car_year'] as num?)?.toInt();
    final firstReg = _str(profile['car_first_reg']);
    final mileage = (profile['car_mileage'] as num?)?.toInt();

    final stats = <_Stat>[
      if (firstReg != null || year != null)
        _Stat('ERSTZULASSUNG', firstReg ?? '$year'),
      if (mileage != null) _Stat('KILOMETERSTAND', '${_formatThousands(mileage)} km'),
      if (horsepower != null) _Stat('LEISTUNG', '$horsepower PS'),
      if (topSpeed != null) _Stat('TOP SPEED', '$topSpeed km/h'),
      if (cylinders != null) _Stat('ZYLINDER', '$cylinders'),
      if (displacement != null)
        _Stat('HUBRAUM', '${_formatThousands(displacement)} cm³')
      else if (engineSize != null)
        _Stat('HUBRAUM',
            '${engineSize.toStringAsFixed(1).replaceAll('.', ',')} L'),
    ];

    final card = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.7), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.15),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ─── Header: Marke + Modell ─────────────────────────────────────
          Container(
            color: const Color(0xFF1A1A1F),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        brand ?? 'MEINE MARKE',
                        style: TextStyle(
                          color: brand != null ? Colors.white : Colors.white38,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.5,
                          height: 1.0,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      if (name != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Marken-Badge — kleiner Auto-Icon-Wappen
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accent, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.directions_car_filled,
                    color: accent,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),

          // ─── Bild ───────────────────────────────────────────────────────
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Container(
              color: Colors.black,
              child: imageUrl != null
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, _, _) => _placeholder(),
                    )
                  : _placeholder(),
            ),
          ),

          // ─── Stat-Tabelle mit Trenn-Linien ──────────────────────────────
          if (stats.isNotEmpty)
            Container(
              color: const Color(0xFF0F0F12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < stats.length; i++) ...[
                    _StatRow(stat: stats[i]),
                    if (i < stats.length - 1)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );

    if (onTap == null) return card;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }

  static String _formatThousands(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Widget _placeholder() {
    return const Center(
      child: Icon(Icons.directions_car_outlined,
          color: Colors.white24, size: 72),
    );
  }
}

class _Stat {
  final String label;
  final String value;
  const _Stat(this.label, this.value);
}

class _StatRow extends StatelessWidget {
  final _Stat stat;
  const _StatRow({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              stat.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          Text(
            stat.value,
            style: const TextStyle(
              color: CarCard.accent,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
