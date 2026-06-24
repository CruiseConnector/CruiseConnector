import 'package:flutter/material.dart';

import 'skeleton.dart';

/// Skeleton-Loader für einen Community-Post (dunkles Theme).
/// Wird angezeigt während die Posts vom Server geladen werden.
///
/// Verwendung:
/// ```dart
/// if (isLoading) const PostSkeletonList() else ActualFeed(...)
/// ```
class PostSkeleton extends StatelessWidget {
  const PostSkeleton({super.key});

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
            // Avatar + Name
            Row(
              children: [
                SkeletonCircle(size: 40),
                SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 130, height: 12),
                    SizedBox(height: 6),
                    SkeletonBox(width: 80, height: 10),
                  ],
                ),
              ],
            ),
            SizedBox(height: 14),
            // Text-Zeilen
            SkeletonBox(width: double.infinity, height: 12),
            SizedBox(height: 7),
            SkeletonBox(width: double.infinity, height: 12),
            SizedBox(height: 7),
            SkeletonBox(width: 200, height: 12),
            SizedBox(height: 14),
            // Aktions-Zeile (Like, Kommentar, Teilen)
            Row(
              children: [
                SkeletonBox(width: 64, height: 26, radius: 13),
                SizedBox(width: 12),
                SkeletonBox(width: 64, height: 26, radius: 13),
                SizedBox(width: 12),
                SkeletonBox(width: 64, height: 26, radius: 13),
              ],
            ),
          ],
        ),
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
      padding: const EdgeInsets.only(top: 6),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemBuilder: (_, _) => const PostSkeleton(),
    );
  }
}
