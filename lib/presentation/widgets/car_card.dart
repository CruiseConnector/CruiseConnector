import 'package:flutter/material.dart';

class CarCard extends StatelessWidget {
  const CarCard({super.key, required this.profile, this.onTap});

  final Map<String, dynamic> profile;
  final VoidCallback? onTap;

  static const Color accent = Color(0xFFFF3B30);
  static const Color surface = Color(0xFF171A22);

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

  static String? _str(dynamic value) {
    final text = (value as String?)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    final brand = _str(profile['car_brand']);
    final model = _str(profile['car_name']);
    final imageUrl = _str(profile['car_image_url']);
    final topSpeed = (profile['car_top_speed'] as num?)?.toInt();
    final engineSize = (profile['car_engine_size'] as num?)?.toDouble();
    final displacement = (profile['car_displacement'] as num?)?.toInt();
    final cylinders = (profile['car_cylinders'] as num?)?.toInt();
    final horsepower = (profile['car_horsepower'] as num?)?.toInt();
    final year = (profile['car_year'] as num?)?.toInt();
    final firstReg = _str(profile['car_first_reg']);
    final mileage = (profile['car_mileage'] as num?)?.toInt();

    final stats = <_CarStat>[
      if (horsepower != null)
        _CarStat(Icons.bolt, 'Leistung', '$horsepower PS'),
      if (topSpeed != null)
        _CarStat(Icons.speed, 'Top Speed', '$topSpeed km/h'),
      if (mileage != null)
        _CarStat(
          Icons.timeline,
          'Kilometer',
          '${_formatThousands(mileage)} km',
        ),
      if (firstReg != null || year != null)
        _CarStat(Icons.event, 'Erstzulassung', firstReg ?? '$year'),
      if (cylinders != null) _CarStat(Icons.settings, 'Zylinder', '$cylinders'),
      if (displacement != null)
        _CarStat(
          Icons.local_gas_station,
          'Hubraum',
          '${_formatThousands(displacement)} ccm',
        )
      else if (engineSize != null)
        _CarStat(
          Icons.local_gas_station,
          'Hubraum',
          '${engineSize.toStringAsFixed(1).replaceAll('.', ',')} L',
        ),
    ];

    final child = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl != null)
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _CarImagePlaceholder(),
                  )
                else
                  const _CarImagePlaceholder(),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              brand ?? 'Mein Auto',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                              ),
                            ),
                            if (model != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                model,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.76),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.directions_car_filled,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (stats.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth < 330 ? 1 : 2;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final stat in stats)
                        SizedBox(
                          width: columns == 1
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 10) / 2,
                          child: _StatTile(stat: stat),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: child,
    );
  }

  static String _formatThousands(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write('.');
      buffer.write(text[i]);
    }
    return buffer.toString();
  }
}

class _CarImagePlaceholder extends StatelessWidget {
  const _CarImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF10131A),
      child: Center(
        child: Icon(
          Icons.directions_car_outlined,
          color: Colors.white.withValues(alpha: 0.18),
          size: 64,
        ),
      ),
    );
  }
}

class _CarStat {
  const _CarStat(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final _CarStat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
      ),
      child: Row(
        children: [
          Icon(stat.icon, color: CarCard.accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stat.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
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
