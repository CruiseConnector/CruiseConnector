import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/weather_service.dart';

/// 2026-05-24 (vucko): Kompakte Inline-Wetter-Darstellung für den
/// Route-Banner. Passt visuell zu den anderen Metric-Items (Distanz, Dauer
/// etc.) und nimmt nicht mehr Platz als nötig.
///
/// Layout: Icon (oben) — Temp (Mitte) — Riding-Condition-Label (unten).
/// Color-Coded: Riding-Condition-Label in grün/blau/gelb/rot.
class WeatherInline extends StatelessWidget {
  const WeatherInline({
    super.key,
    required this.latitude,
    required this.longitude,
    this.durationMinutes,
  });

  final double latitude;
  final double longitude;
  final int? durationMinutes;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WeatherSnapshot?>(
      future: WeatherService.instance.fetchForPosition(
        latitude: latitude,
        longitude: longitude,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return _placeholderColumn();
        }
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * 4),
              child: child,
            ),
          ),
          child: _buildContent(snapshot.data!),
        );
      },
    );
  }

  Widget _placeholderColumn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cloud_outlined,
          color: AppAccentColors.accent.withValues(alpha: 0.35),
          size: 20,
        ),
        const SizedBox(height: 4),
        Text(
          '--°',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Wetter',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildContent(WeatherSnapshot snap) {
    final icon = _weatherIcon(snap.weatherCode);
    final condColor = switch (snap.ridingCondition) {
      RidingCondition.excellent => const Color(0xFF34D399),
      RidingCondition.good => const Color(0xFF60A5FA),
      RidingCondition.marginal => const Color(0xFFFBBF24),
      RidingCondition.poor => const Color(0xFFF87171),
    };
    final condLabel = switch (snap.ridingCondition) {
      RidingCondition.excellent => 'Perfekt',
      RidingCondition.good => 'Gut',
      RidingCondition.marginal => 'Vorsicht',
      RidingCondition.poor => 'Schlecht',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: condColor, size: 20),
        const SizedBox(height: 4),
        Text(
          '${snap.temperatureC.round()}°',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          condLabel,
          style: TextStyle(
            color: condColor,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  IconData _weatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny;
    if (code <= 2) return Icons.wb_cloudy;
    if (code <= 49) return Icons.cloud;
    if (code <= 55) return Icons.grain;
    if (code <= 67) return Icons.beach_access;
    if (code <= 77) return Icons.ac_unit;
    if (code <= 82) return Icons.beach_access;
    if (code <= 86) return Icons.ac_unit;
    if (code <= 99) return Icons.flash_on;
    return Icons.cloud;
  }
}

/// 2026-05-24 (vucko): Dezente einzeilige Warnung wenn Regen oder Trend.
/// Nur sichtbar bei relevanten Wetter-Events — nimmt sonst keinen Platz.
class WeatherWarningStrip extends StatelessWidget {
  const WeatherWarningStrip({
    super.key,
    required this.latitude,
    required this.longitude,
    this.durationMinutes,
  });

  final double latitude;
  final double longitude;
  final int? durationMinutes;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WeatherSnapshot?>(
      future: WeatherService.instance.fetchForPosition(
        latitude: latitude,
        longitude: longitude,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final snap = snapshot.data!;
        final warning = _buildWarning(snap);
        if (warning == null) return const SizedBox.shrink();
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 280),
          builder: (context, value, child) =>
              Opacity(opacity: value, child: child),
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: warning.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: warning.color.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(warning.icon, color: warning.color, size: 13),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    warning.text,
                    style: TextStyle(
                      color: warning.color,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  _WeatherWarning? _buildWarning(WeatherSnapshot snap) {
    // Trend (only if duration >= 45 min)
    final dur = durationMinutes;
    if (dur != null && dur >= 45) {
      final arrivalIdx = (dur / 60).round().clamp(1, 5);
      if (arrivalIdx < snap.next6Hours.length) {
        final arrival = snap.next6Hours[arrivalIdx];
        final startCode = snap.weatherCode;
        final endCode = arrival.weatherCode;
        if (startCode <= 2 && endCode >= 51) {
          return const _WeatherWarning(
            icon: Icons.water_drop_rounded,
            color: Color(0xFF60A5FA),
            text: 'Wird unterwegs regnerisch',
          );
        }
        if (startCode >= 51 && endCode <= 2) {
          return const _WeatherWarning(
            icon: Icons.wb_sunny_rounded,
            color: Color(0xFF34D399),
            text: 'Klart unterwegs auf',
          );
        }
        if (endCode >= 95 || startCode >= 95) {
          return const _WeatherWarning(
            icon: Icons.thunderstorm_rounded,
            color: Color(0xFFF87171),
            text: 'Gewitter zieht auf',
          );
        }
      }
    }
    // Heavy rain in next 6h?
    final maxProb = snap.maxPrecipitationProbabilityNext6h;
    final rainHour = snap.firstHeavyRainHour;
    if (rainHour != null) {
      return _WeatherWarning(
        icon: Icons.water_drop_rounded,
        color: const Color(0xFF60A5FA),
        text: 'Regen in ${rainHour}h möglich · $maxProb%',
      );
    }
    if (maxProb >= 50) {
      return _WeatherWarning(
        icon: Icons.water_drop_rounded,
        color: const Color(0xFF60A5FA),
        text: 'Regenrisiko $maxProb% in den nächsten 6h',
      );
    }
    return null;
  }
}

class _WeatherWarning {
  final IconData icon;
  final Color color;
  final String text;
  const _WeatherWarning({
    required this.icon,
    required this.color,
    required this.text,
  });
}
