import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Skeleton-Loader für eine Routen-Karte.
/// Wird angezeigt während gespeicherte oder vorgeschlagene Routen laden.
class RouteCardSkeleton extends StatelessWidget {
  const RouteCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[800]!,
      highlightColor: Colors.grey[600]!,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Karten-Header (Name + Stil)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _box(width: 150, height: 16),
                  _box(width: 70, height: 24, radius: 12),
                ],
              ),
              const SizedBox(height: 10),
              // Statistiken (Distanz, Dauer)
              Row(
                children: [
                  _box(width: 80, height: 12),
                  const SizedBox(width: 16),
                  _box(width: 80, height: 12),
                ],
              ),
              const SizedBox(height: 12),
              // Karten-Vorschau Platzhalter
              _box(width: double.infinity, height: 80, radius: 8),
              const SizedBox(height: 12),
              // Button-Zeile
              Row(
                children: [
                  _box(width: 100, height: 36, radius: 18),
                  const SizedBox(width: 10),
                  _box(width: 100, height: 36, radius: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _box({
    required double width,
    required double height,
    double radius = 6,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
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
