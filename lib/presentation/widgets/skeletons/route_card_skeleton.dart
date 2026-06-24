import 'package:flutter/material.dart';

import 'skeleton.dart';

/// Skeleton-Loader für eine Routen-Karte (dunkles Theme).
/// Wird angezeigt während gespeicherte oder vorgeschlagene Routen laden.
class RouteCardSkeleton extends StatelessWidget {
  const RouteCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header (Name + Stil-Pille)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SkeletonBox(width: 150, height: 16),
                SkeletonBox(width: 70, height: 24, radius: 12),
              ],
            ),
            SizedBox(height: 12),
            // Statistiken (Distanz, Dauer)
            Row(
              children: [
                SkeletonBox(width: 80, height: 12),
                SizedBox(width: 16),
                SkeletonBox(width: 80, height: 12),
              ],
            ),
            SizedBox(height: 12),
            // Karten-Vorschau
            SkeletonBox(width: double.infinity, height: 80, radius: 10),
            SizedBox(height: 12),
            // Button-Zeile
            Row(
              children: [
                SkeletonBox(width: 110, height: 36, radius: 18),
                SizedBox(width: 10),
                SkeletonBox(width: 110, height: 36, radius: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Zeigt mehrere RouteCardSkeletons für den Lade-State.
class RouteCardSkeletonList extends StatelessWidget {
  final int count;
  const RouteCardSkeletonList({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: count,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemBuilder: (_, _) => const RouteCardSkeleton(),
    );
  }
}
