import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Skeleton-Loader für einen Community-Post.
/// Wird angezeigt während die Posts vom Server geladen werden.
///
/// Verwendung:
/// ```dart
/// if (isLoading) PostSkeleton() else ActualPostCard(...)
/// ```
class PostSkeleton extends StatelessWidget {
  const PostSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[800]!,
      highlightColor: Colors.grey[600]!,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar + Name Zeile
              Row(
                children: [
                  const CircleAvatar(radius: 20, backgroundColor: Colors.white),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _box(width: 120, height: 12),
                      const SizedBox(height: 4),
                      _box(width: 80, height: 10),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Text-Zeilen
              _box(width: double.infinity, height: 12),
              const SizedBox(height: 6),
              _box(width: double.infinity, height: 12),
              const SizedBox(height: 6),
              _box(width: 200, height: 12),
              const SizedBox(height: 12),
              // Aktions-Zeile (Like, Kommentar, Teilen)
              Row(
                children: [
                  _box(width: 60, height: 28),
                  const SizedBox(width: 12),
                  _box(width: 60, height: 28),
                  const SizedBox(width: 12),
                  _box(width: 60, height: 28),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Hilfs-Widget für einen grauen Platzhalter-Block.
  Widget _box({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

/// Zeigt mehrere PostSkeletons für den Lade-State.
class PostSkeletonList extends StatelessWidget {
  final int count;
  const PostSkeletonList({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: count,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemBuilder: (_, __) => const PostSkeleton(),
    );
  }
}
