import 'package:flutter/material.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF151922).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Verbleibende Zeit',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDuration(durationSeconds),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 36, color: Colors.white12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Strecke',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDistanceKm(distanceMeters),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(double? durationSeconds) {
    if (durationSeconds == null || durationSeconds <= 0) return '--';
    final totalMinutes = (durationSeconds / 60).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) return '$minutes Min.';
    return '$hours Std. ${minutes.toString().padLeft(2, '0')} Min.';
  }

  static String _formatDistanceKm(double? rawDistance) {
    if (rawDistance == null || rawDistance <= 0) return '-- km';
    final km = rawDistance > 1000 ? rawDistance / 1000 : rawDistance;
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  }
}
