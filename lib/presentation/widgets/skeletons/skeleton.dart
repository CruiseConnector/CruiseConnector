import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// 2026-06-24 (vucko Skeleton-Loading): Gemeinsame, dunkel-theme-konforme
/// Shimmer-Bausteine. Statt des hässlichen Kreis-Spinners zeigen die Seiten
/// während des Ladens ein animiertes Skelett ihrer echten Struktur.
///
/// Verwendung:
/// ```dart
/// SkeletonShimmer(
///   child: Column(children: [
///     SkeletonBox(width: 160, height: 22),
///     SkeletonCircle(size: 48),
///   ]),
/// )
/// ```
/// Alle Platzhalter im `child` sind weiß (opak) — der Shimmer-Gradient färbt sie
/// dunkelgrau ein und lässt einen Glanz darüberwandern.
class SkeletonShimmer extends StatelessWidget {
  const SkeletonShimmer({super.key, required this.child, this.enabled = true});

  final Widget child;

  /// Wenn false, wird nur das Kind ohne Animation gezeigt (z. B. für Tests).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Shimmer.fromColors(
      // Auf dem dunklen App-Hintergrund (#0B0E14) / Karten (#1C1F26) liegen die
      // Platzhalter dezent darüber — sichtbar, aber nicht grell.
      baseColor: const Color(0xFF20242C),
      highlightColor: const Color(0xFF2E333D),
      period: const Duration(milliseconds: 1350),
      child: child,
    );
  }
}

/// Abgerundeter Platzhalter-Block (Texte, Karten, Buttons). Breite optional
/// (null = volle Breite des Parents).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
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

/// Kreisförmiger Platzhalter (Avatare, runde Icons/Ringe).
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }
}
