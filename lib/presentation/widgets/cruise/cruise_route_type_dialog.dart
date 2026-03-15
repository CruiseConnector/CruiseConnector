import 'package:flutter/material.dart';

import 'package:cruise_connect/domain/models/mapbox_suggestion.dart';

/// Bottom-Sheet zur Auswahl des Routentyps (Schnellste, Sport, Abwechslung).
void showRouteTypeDialog({
  required BuildContext context,
  required MapboxSuggestion suggestion,
  required String selectedStyle,
  required void Function(MapboxSuggestion suggestion, {required bool scenic, int routeVariant}) onRouteSelected,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1C1F26),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Routen auswählen',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Ziel: ${suggestion.placeName}',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
            maxLines: 2, overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 24),
          _RouteOption(
            icon: Icons.speed,
            color: const Color(0xFFFF3B30),
            title: 'Schnellste Route',
            subtitle: 'Direkter Weg zum Ziel',
            onTap: () {
              Navigator.pop(ctx);
              onRouteSelected(suggestion, scenic: false, routeVariant: 0);
            },
          ),
          const SizedBox(height: 12),
          _RouteOption(
            icon: Icons.route,
            color: Colors.orange,
            title: 'Coole Route (Sport)',
            subtitle: 'Mit $selectedStyle - anspruchsvoll',
            onTap: () {
              Navigator.pop(ctx);
              onRouteSelected(suggestion, scenic: true, routeVariant: 0);
            },
          ),
          const SizedBox(height: 12),
          _RouteOption(
            icon: Icons.landscape,
            color: Colors.green,
            title: 'Coole Route (Abwechslung)',
            subtitle: 'Alternative mit Kurven & Natur',
            onTap: () {
              Navigator.pop(ctx);
              onRouteSelected(suggestion, scenic: true, routeVariant: 1);
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('Abbrechen', style: TextStyle(color: Colors.grey, fontSize: 16)),
            ),
          ),
        ],
      ),
    ),
  );
}

class _RouteOption extends StatelessWidget {
  const _RouteOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0E14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
          ],
        ),
      ),
    );
  }
}
