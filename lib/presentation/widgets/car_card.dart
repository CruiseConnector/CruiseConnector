import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';

class CarCard extends StatelessWidget {
  const CarCard({super.key, required this.profile, this.onTap});

  final Map<String, dynamic> profile;
  final VoidCallback? onTap;

  static Color get accent => AppAccentColors.accent;
  static const Color surface = Color(0xFF1C1F26);
  static const Color pageBg = Color(0xFF0B0E14);
  static const double baseHeight = 540;
  static const double _footerHeight = 32;
  static const Map<String, String> _countryDisplayCodes = <String, String>{
    'AT': 'AT-AUT',
    'DE': 'DE-GER',
    'GB': 'GB-UK',
    'JP': 'JP-JPN',
    'KR': 'KR-KOR',
    'US': 'US-USA',
    'IT': 'IT-ITA',
    'FR': 'FR-FRA',
    'CH': 'CH-SUI',
    'SE': 'SE-SWE',
    'ES': 'ES-ESP',
    'CZ': 'CZ-CZE',
    'RO': 'RO-ROU',
    'CN': 'CN-CHN',
    'IN': 'IN-IND',
    'NL': 'NL-NED',
    'RU': 'RU-RUS',
  };

  static double preferredHeightFor(
    Map<String, dynamic> profile, {
    double width = 320,
  }) {
    final description = _str(profile['description']);
    final tuningDetails = _str(profile['tuning_details']);
    final stats = _statsFor(profile);
    final imageHeight = width / (16 / 9);
    final gridWidth = (width - 24).clamp(1, width);
    final statColumns = gridWidth < 280 ? 1 : 2;
    final statRows = stats.isEmpty ? 0 : (stats.length / statColumns).ceil();
    final statsHeight = stats.isEmpty
        ? 0
        : 24 + (statRows * 66) + ((statRows - 1) * 10);

    final textWidth = (width - 48).clamp(160, width);
    var textSectionsHeight = 0.0;
    if (description != null) {
      final descriptionPainter = TextPainter(
        text: TextSpan(
          text: description,
          style: const TextStyle(
            fontSize: 12,
            height: 1.25,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: textWidth.toDouble());
      textSectionsHeight += 12 + 26 + descriptionPainter.height;
    }
    if (tuningDetails != null) {
      final tuningPainter = TextPainter(
        text: TextSpan(
          text: tuningDetails,
          style: const TextStyle(
            fontSize: 12,
            height: 1.25,
            fontWeight: FontWeight.w700,
          ),
        ),
        maxLines: 3,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: textWidth.toDouble());
      textSectionsHeight += 10 + 42 + tuningPainter.height;
    }

    final computedHeight =
        imageHeight + statsHeight + textSectionsHeight + _footerHeight + 24;
    return computedHeight.clamp(baseHeight, 860).toDouble();
  }

  static bool isEmpty(Map<String, dynamic> profile) {
    return _str(_field(profile, 'brand', 'car_brand')) == null &&
        _str(_field(profile, 'model', 'car_name')) == null &&
        _str(profile['tuning_details']) == null &&
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
    final tuningDetails = _str(profile['tuning_details']);
    final imageUrl = _str(_field(profile, 'image_url', 'car_image_url'));
    final countryCode =
        (_str(_field(profile, 'country_code', 'car_country_code')) ?? 'AT')
            .toUpperCase();
    final countryLabel = _countryDisplayCodes[countryCode] ?? countryCode;
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
                  child: _CountryChip(countryCode: countryLabel),
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
              padding: EdgeInsets.fromLTRB(
                12,
                stats.isEmpty ? 12 : 0,
                12,
                tuningDetails == null ? 12 : 8,
              ),
              child: _DescriptionBox(description: description),
            ),
          if (tuningDetails != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                description == null && stats.isEmpty ? 12 : 0,
                12,
                12,
              ),
              child: _TuningBox(details: tuningDetails),
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
      if (horsepower != null)
        _VehicleStat(Icons.bolt_rounded, 'Leistung', '$horsepower PS'),
      if (topSpeed != null)
        _VehicleStat(
          Icons.keyboard_double_arrow_up_rounded,
          'Top Speed',
          '$topSpeed km/h',
        ),
      if (zeroToHundred != null)
        _VehicleStat(
          Icons.timer_outlined,
          '0-100',
          '${_formatDecimalSeconds(zeroToHundred)} s',
        ),
      if (displacement != null)
        _VehicleStat(
          Icons.blur_circular_rounded,
          'Hubraum',
          '${_formatThousands(displacement)} ccm',
        )
      else if (engineSize != null)
        _VehicleStat(
          Icons.blur_circular_rounded,
          'Hubraum',
          '${engineSize.toStringAsFixed(1).replaceAll('.', ',')} L',
        ),
      if (cylinders != null)
        _VehicleStat(Icons.adjust_rounded, 'Zylinder', '$cylinders'),
      if (mileage != null)
        _VehicleStat(
          Icons.speed_outlined,
          'Kilometer',
          '${_formatThousands(mileage)} km',
        ),
      if (year != null)
        _VehicleStat(Icons.calendar_today_outlined, 'Baujahr', '$year'),
      if (drivetrain != null)
        _VehicleStat(Icons.settings_suggest_outlined, 'Antrieb', drivetrain),
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
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TuningBox extends StatelessWidget {
  const _TuningBox({required this.details});

  final String details;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: CarCard.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CarCard.accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, color: CarCard.accent, size: 14),
              const SizedBox(width: 6),
              Text(
                'Tuning / Umbauten',
                style: TextStyle(
                  color: CarCard.accent,
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            details,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.84),
              fontSize: 12,
              height: 1.25,
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
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
          fontSize: 11,
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
  _VehicleStat(this.icon, this.label, this.value);

  final IconData icon;
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
        final columns = constraints.maxWidth < 280 ? 1 : 2;
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
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final _VehicleStat stat;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Container(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: CarCard.accent.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(stat.icon, color: CarCard.accent, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    stat.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 10.5,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  stat.value,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
