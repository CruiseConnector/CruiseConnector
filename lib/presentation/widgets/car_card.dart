import 'package:flutter/material.dart';

class CarCard extends StatelessWidget {
  const CarCard({super.key, required this.profile, this.onTap});

  final Map<String, dynamic> profile;
  final VoidCallback? onTap;

  static const Color accent = Color(0xFFFF3B30);
  static const Color surface = Color(0xFF1C1F26);
  static const Color pageBg = Color(0xFF0B0E14);
  static const double baseHeight = 470;
  static const double _footerHeight = 32;

  static double preferredHeightFor(
    Map<String, dynamic> profile, {
    double width = 320,
  }) {
    final description = _str(profile['description']);
    final stats = _statsFor(profile);
    final imageHeight = width / (16 / 9);
    final gridWidth = (width - 24).clamp(1, width);
    final statColumns = gridWidth < 250 ? 1 : 2;
    final statRows = stats.isEmpty ? 0 : (stats.length / statColumns).ceil();
    final statsHeight = stats.isEmpty
        ? 0
        : 24 + (statRows * 40) + ((statRows - 1) * 8);

    if (description == null) {
      return (imageHeight + statsHeight + _footerHeight + 10).clamp(
        baseHeight,
        760,
      );
    }

    final textWidth = (width - 48).clamp(160, width);
    final descriptionPainter = TextPainter(
      text: TextSpan(
        text: description,
        style: const TextStyle(
          fontSize: 10.2,
          height: 1.18,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: textWidth.toDouble());
    final descriptionHeight = 12 + 20 + descriptionPainter.height;

    final computedHeight =
        imageHeight + statsHeight + descriptionHeight + _footerHeight + 24;
    return computedHeight < baseHeight ? baseHeight : computedHeight;
  }

  static bool isEmpty(Map<String, dynamic> profile) {
    return _str(_field(profile, 'brand', 'car_brand')) == null &&
        _str(_field(profile, 'model', 'car_name')) == null &&
        _field(profile, 'top_speed', 'car_top_speed') == null &&
        profile['zero_to_hundred_seconds'] == null &&
        _str(profile['drivetrain']) == null &&
        _field(profile, 'engine_size', 'car_engine_size') == null &&
        _field(profile, 'displacement', 'car_displacement') == null &&
        _field(profile, 'cylinders', 'car_cylinders') == null &&
        _field(profile, 'horsepower', 'car_horsepower') == null &&
        _field(profile, 'year', 'car_year') == null &&
        _field(profile, 'mileage', 'car_mileage') == null &&
        _str(_field(profile, 'image_url', 'car_image_url')) == null;
  }

  static dynamic _field(
    Map<String, dynamic> data,
    String garageKey,
    String legacyKey,
  ) {
    return data[garageKey] ?? data[legacyKey];
  }

  static String? _str(dynamic value) {
    final text = (value as String?)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    final brand = _str(_field(profile, 'brand', 'car_brand'));
    final model = _str(_field(profile, 'model', 'car_name'));
    final description = _str(profile['description']);
    final imageUrl = _str(_field(profile, 'image_url', 'car_image_url'));
    final countryCode =
        (_str(_field(profile, 'country_code', 'car_country_code')) ?? 'AT')
            .toUpperCase();
    final type = (_str(profile['vehicle_type']) ?? 'car').toLowerCase();
    final isBike = type == 'motorcycle';

    final title = [
      if (brand != null) brand,
      if (model != null) model,
    ].join(' ').trim();

    final stats = _statsFor(profile);

    final child = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    errorBuilder: (_, _, _) =>
                        _VehicleImagePlaceholder(isBike: isBike),
                  )
                else
                  _VehicleImagePlaceholder(isBike: isBike),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.78),
                      ],
                    ),
                  ),
                ),
                Positioned(left: 14, top: 14, child: _TypeChip(isBike: isBike)),
                Positioned(
                  right: 14,
                  top: 14,
                  child: _CountryChip(countryCode: countryCode),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty
                            ? (isBike ? 'Mein Motorrad' : 'Mein Auto')
                            : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        isBike ? 'Motorradprofil' : 'Fahrzeugprofil',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
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
              padding: const EdgeInsets.all(12),
              child: _StatsGrid(stats: stats),
            ),
          if (description != null)
            Padding(
              padding: EdgeInsets.fromLTRB(12, stats.isEmpty ? 12 : 0, 12, 12),
              child: _DescriptionBox(description: description),
            ),
          const Spacer(),
          const _CardFooter(),
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

  static List<_VehicleStat> _statsFor(Map<String, dynamic> profile) {
    final drivetrain = _str(profile['drivetrain']);
    final topSpeed = (_field(profile, 'top_speed', 'car_top_speed') as num?)
        ?.toInt();
    final engineSize =
        (_field(profile, 'engine_size', 'car_engine_size') as num?)?.toDouble();
    final displacement =
        (_field(profile, 'displacement', 'car_displacement') as num?)?.toInt();
    final cylinders = (_field(profile, 'cylinders', 'car_cylinders') as num?)
        ?.toInt();
    final horsepower = (_field(profile, 'horsepower', 'car_horsepower') as num?)
        ?.toInt();
    final year = (_field(profile, 'year', 'car_year') as num?)?.toInt();
    final mileage = (_field(profile, 'mileage', 'car_mileage') as num?)
        ?.toInt();
    final zeroToHundred = (profile['zero_to_hundred_seconds'] as num?)
        ?.toDouble();

    return [
      if (horsepower != null) _VehicleStat('Leistung', '$horsepower PS'),
      if (topSpeed != null) _VehicleStat('Top Speed', '$topSpeed km/h'),
      if (zeroToHundred != null)
        _VehicleStat('0-100', '${_formatDecimalSeconds(zeroToHundred)} s'),
      if (displacement != null)
        _VehicleStat('Hubraum', '${_formatThousands(displacement)} ccm')
      else if (engineSize != null)
        _VehicleStat(
          'Hubraum',
          '${engineSize.toStringAsFixed(1).replaceAll('.', ',')} L',
        ),
      if (cylinders != null) _VehicleStat('Zylinder', '$cylinders'),
      if (mileage != null)
        _VehicleStat('Kilometer', '${_formatThousands(mileage)} km'),
      if (year != null) _VehicleStat('Baujahr', '$year'),
      if (drivetrain != null) _VehicleStat('Antrieb', drivetrain),
    ];
  }

  static String _formatDecimalSeconds(double value) {
    final fixed = value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
    return fixed.replaceAll('.', ',');
  }
}

class _DescriptionBox extends StatelessWidget {
  const _DescriptionBox({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CarCard.accent.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 10.2,
              height: 1.18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardFooter extends StatelessWidget {
  const _CardFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Text(
        'www.cruiseconnector.at',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.78),
          fontSize: 12,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.isBike});

  final bool isBike;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isBike ? Icons.two_wheeler_rounded : Icons.directions_car_filled,
            color: CarCard.accent,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            isBike ? 'Motorrad' : 'Auto',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountryChip extends StatelessWidget {
  const _CountryChip({required this.countryCode});

  final String countryCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        countryCode,
        style: const TextStyle(
          color: Color(0xFF111318),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _VehicleImagePlaceholder extends StatelessWidget {
  const _VehicleImagePlaceholder({required this.isBike});

  final bool isBike;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CarCard.pageBg,
      child: Center(
        child: Icon(
          isBike ? Icons.two_wheeler_rounded : Icons.directions_car_outlined,
          color: Colors.white.withValues(alpha: 0.18),
          size: 72,
        ),
      ),
    );
  }
}

class _VehicleStat {
  const _VehicleStat(this.label, this.value);

  final String label;
  final String value;
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final List<_VehicleStat> stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 250 ? 1 : 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final stat in stats)
              SizedBox(
                width: columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 8) / 2,
                child: _StatTile(stat: stat),
              ),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final _VehicleStat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CarCard.accent.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              stat.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.52),
                fontSize: 10,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              stat.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
