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

/// Eine Listen-Zeile: runder Avatar + 1–2 Textzeilen (+ optionaler Trailing-
/// Button). Baustein für Mitglieder-/Chat-/Benachrichtigungs-/Nutzer-Listen.
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({
    super.key,
    this.avatarSize = 48,
    this.lines = 2,
    this.hasTrailing = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  final double avatarSize;
  final int lines;
  final bool hasTrailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          SkeletonCircle(size: avatarSize),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SkeletonBox(width: 150, height: 13),
                if (lines > 1) ...[
                  const SizedBox(height: 8),
                  const SkeletonBox(width: 92, height: 11),
                ],
              ],
            ),
          ),
          if (hasTrailing) ...[
            const SizedBox(width: 12),
            const SkeletonBox(width: 66, height: 30, radius: 15),
          ],
        ],
      ),
    );
  }
}

/// Komplette Listen-Lade-Ansicht: N [SkeletonListTile] unter einem Shimmer.
/// Direkt als `body:` einer Seite verwendbar (kein Scrollen — reiner Platzhalter).
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.count = 6,
    this.avatarSize = 48,
    this.lines = 2,
    this.hasTrailing = false,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  final int count;
  final double avatarSize;
  final int lines;
  final bool hasTrailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            count,
            (_) => SkeletonListTile(
              avatarSize: avatarSize,
              lines: lines,
              hasTrailing: hasTrailing,
            ),
          ),
        ),
      ),
    );
  }
}

/// Chat-Skeleton: wechselnde Nachrichten-Blasen (links mit Avatar, rechts
/// eigene). Für Community-/Gruppen-Chat-Ladezustand — nie ein Kreis-Spinner.
class SkeletonChat extends StatelessWidget {
  const SkeletonChat({super.key, this.count = 8});

  final int count;

  @override
  Widget build(BuildContext context) {
    const widths = <double>[200, 130, 240, 96, 170, 150, 210, 120];
    const heights = <double>[40, 34, 56, 34, 40, 48, 40, 34];
    return SkeletonShimmer(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        itemBuilder: (context, i) {
          final mine = i.isOdd;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              mainAxisAlignment:
                  mine ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!mine) ...[
                  const SkeletonCircle(size: 32),
                  const SizedBox(width: 8),
                ],
                SkeletonBox(
                  width: widths[i % widths.length],
                  height: heights[i % heights.length],
                  radius: 16,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
