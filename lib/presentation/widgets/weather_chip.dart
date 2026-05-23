import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/weather_service.dart';

/// Kleines Wetter-Chip-Widget für den Route-Preview.
/// Lädt Wetter im FutureBuilder, animiert sanft beim Laden ein.
/// Bei Fail zeigt es einfach nichts (silent fail).
class WeatherChip extends StatelessWidget {
  const WeatherChip({
    super.key,
    required this.latitude,
    required this.longitude,
    this.onTap,
  });

  final double latitude;
  final double longitude;
  final VoidCallback? onTap;

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
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * 6),
              child: child,
            ),
          ),
          child: _WeatherCompact(
            snapshot: snapshot.data!,
            onTap: onTap,
          ),
        );
      },
    );
  }
}

class _WeatherCompact extends StatelessWidget {
  const _WeatherCompact({required this.snapshot, this.onTap});

  final WeatherSnapshot snapshot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final (iconCp, label, colorHint) =
        WeatherCodeIcon.describe(snapshot.weatherCode);
    final icon = IconData(iconCp, fontFamily: 'MaterialIcons');
    final condColor = switch (snapshot.ridingCondition) {
      RidingCondition.excellent => const Color(0xFF34D399), // grün
      RidingCondition.good => const Color(0xFF60A5FA),       // blau
      RidingCondition.marginal => const Color(0xFFFBBF24),   // gelb
      RidingCondition.poor => const Color(0xFFF87171),       // rot
    };
    final condLabel = switch (snapshot.ridingCondition) {
      RidingCondition.excellent => 'Perfekt',
      RidingCondition.good => 'Gut',
      RidingCondition.marginal => 'Vorsicht',
      RidingCondition.poor => 'Schlecht',
    };
    final maxRainProb = snapshot.maxPrecipitationProbabilityNext6h;
    final rainHour = snapshot.firstHeavyRainHour;
    final tintColor = colorHint == 0
        ? const Color(0xFFFFA94D)  // sonnig: orange tint
        : colorHint == 2
        ? const Color(0xFF60A5FA)  // regen: blau
        : colorHint == 3
        ? const Color(0xFFF87171)  // sturm: rot
        : const Color(0xFF94A3B8); // cloudy/foggy: grau

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tintColor.withValues(alpha: 0.18),
                  const Color(0xCC1A1E28),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: tintColor.withValues(alpha: 0.35),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: tintColor.withValues(alpha: 0.15),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Linke Seite: Icon + Temperatur
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tintColor.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${snapshot.temperatureC.round()}°',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: condColor.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            condLabel,
                            style: TextStyle(
                              color: condColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                // Regen-Warnung wenn relevant
                if (maxRainProb >= 40 || rainHour != null) ...[
                  Container(
                    margin: const EdgeInsets.only(left: 10),
                    width: 1,
                    height: 26,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                  const SizedBox(width: 10),
                  _RainWarning(
                    probability: maxRainProb,
                    accent: accent,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RainWarning extends StatefulWidget {
  const _RainWarning({required this.probability, required this.accent});

  final int probability;
  final Color accent;

  @override
  State<_RainWarning> createState() => _RainWarningState();
}

class _RainWarningState extends State<_RainWarning>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) => Opacity(
                opacity: 0.6 + 0.4 * _pulse.value,
                child: const Icon(
                  Icons.water_drop_rounded,
                  color: Color(0xFF60A5FA),
                  size: 14,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${widget.probability}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          'Regen ≤ 6h',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.60),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
