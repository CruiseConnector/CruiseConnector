import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/presentation/widgets/cruise/nav_distance_format.dart';

/// Zeigt verbleibende Zeit und Streckendistanz am unteren Rand der Karte.
class CruiseNavigationInfoPanel extends StatelessWidget {
  const CruiseNavigationInfoPanel({
    super.key,
    required this.durationSeconds,
    required this.distanceMeters,
  });

  final double? durationSeconds;
  final double? distanceMeters;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2028).withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Verbleibende Zeit
            Expanded(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppAccentColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.schedule_rounded,
                      color: AppAccentColors.accent,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _formatDuration(durationSeconds),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          _formatEta(durationSeconds),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 32,
              color: Colors.white.withValues(alpha: 0.08),
            ),
            const SizedBox(width: 12),
            // Verbleibende Strecke
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            _formatDistanceKm(distanceMeters),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          'verbleibend',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.straighten_rounded,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(double? durationSeconds) {
    if (durationSeconds == null || durationSeconds <= 0) return '…';
    final totalMinutes = (durationSeconds / 60).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) return '$minutes Min.';
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  static String _formatEta(double? durationSeconds) {
    if (durationSeconds == null || durationSeconds <= 0) return 'Ankunft: …';
    final now = DateTime.now();
    final eta = now.add(Duration(seconds: durationSeconds.round()));
    return 'Ankunft: ${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
  }

  static String _formatDistanceKm(double? rawDistance) {
    if (rawDistance == null || rawDistance <= 0) return '… km';
    // 2026-06-13 (vucko J2): Gleiche Google-Style-Stufung wie das Manöver-Banner
    // (rawDistance ist immer in Metern).
    return formatNavDistance(rawDistance);
  }
}
