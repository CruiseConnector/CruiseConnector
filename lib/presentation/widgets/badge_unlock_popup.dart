import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app;

Future<void> showBadgeUnlockPopup({
  required BuildContext context,
  required List<app.Badge> badges,
}) {
  if (badges.isEmpty) return Future<void>.value();

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Badge freigeschaltet',
    barrierColor: Colors.black.withValues(alpha: 0.48),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _BadgeUnlockPopup(badges: badges);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class _BadgeUnlockPopup extends StatefulWidget {
  const _BadgeUnlockPopup({required this.badges});

  final List<app.Badge> badges;

  @override
  State<_BadgeUnlockPopup> createState() => _BadgeUnlockPopupState();
}

class _BadgeUnlockPopupState extends State<_BadgeUnlockPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();
    _closeAfterAnimation();
  }

  Future<void> _closeAfterAnimation() async {
    await Future<void>.delayed(const Duration(milliseconds: 2380));
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = widget.badges.first;
    final extraCount = widget.badges.length - 1;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Material(
      type: MaterialType.transparency,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final value = _controller.value;
            final reveal = Curves.easeOutBack.transform(
              (value / 0.35).clamp(0.0, 1.0).toDouble(),
            );
            final drop = Curves.easeInOutCubic.transform(
              ((value - 0.58) / 0.34).clamp(0.0, 1.0).toDouble(),
            );
            final textOpacity = (1 - ((value - 0.50) / 0.18))
                .clamp(0.0, 1.0)
                .toDouble();

            return LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                final start = Offset(size.width / 2, size.height * 0.40);
                final target = Offset(
                  size.width * 0.70,
                  size.height - bottomPadding - 30,
                );
                final position = Offset.lerp(start, target, drop)!;
                final badgeSize = ui.lerpDouble(126, 38, drop)!;
                final badgeOpacity = (1 - (drop * 0.18))
                    .clamp(0.0, 1.0)
                    .toDouble();

                return Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: const Color(0xFF05070B).withValues(alpha: 0.35),
                      ),
                    ),
                    Positioned(
                      left: target.dx - 26,
                      top: target.dy - 26,
                      child: Opacity(
                        opacity: (0.28 + drop * 0.72)
                            .clamp(0.0, 1.0)
                            .toDouble(),
                        child: _ActivityTarget(pulse: value),
                      ),
                    ),
                    ..._buildBursts(start, reveal, drop),
                    Positioned(
                      left: 24,
                      right: 24,
                      top: math.max(58, size.height * 0.18),
                      child: Opacity(
                        opacity: textOpacity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Badge freigeschaltet',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              extraCount > 0
                                  ? '${badge.name} +$extraCount weitere'
                                  : badge.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFC8CFDC),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: position.dx - badgeSize / 2,
                      top: position.dy - badgeSize / 2,
                      child: Opacity(
                        opacity: badgeOpacity,
                        child: _GlowingBadge(
                          badge: badge,
                          size: badgeSize,
                          reveal: reveal,
                          drop: drop,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildBursts(Offset center, double reveal, double drop) {
    if (drop > 0) return const <Widget>[];
    const count = 10;
    return List<Widget>.generate(count, (index) {
      final angle = (math.pi * 2 / count) * index;
      final distance = 38 + 46 * reveal;
      final x = center.dx + math.cos(angle) * distance;
      final y = center.dy + math.sin(angle) * distance;
      return Positioned(
        left: x - 9,
        top: y - 9,
        child: Opacity(
          opacity: (1 - (reveal - 0.72).clamp(0.0, 0.28) / 0.28)
              .clamp(0.0, 1.0)
              .toDouble(),
          child: Transform.scale(
            scale: 0.65 + reveal * 0.6,
            child: Icon(
              Icons.auto_awesome_rounded,
              color: const Color(0xFFFFD76A).withValues(alpha: 0.9),
              size: 18,
            ),
          ),
        ),
      );
    });
  }
}

class _GlowingBadge extends StatelessWidget {
  const _GlowingBadge({
    required this.badge,
    required this.size,
    required this.reveal,
    required this.drop,
  });

  final app.Badge badge;
  final double size;
  final double reveal;
  final double drop;

  @override
  Widget build(BuildContext context) {
    final glow = 18 + 20 * math.sin(reveal * math.pi).abs();
    return Transform.scale(
      scale: (0.72 + reveal * 0.28) * (1 - drop * 0.04),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppAccentColors.accent.withValues(alpha: 0.54),
              blurRadius: glow,
              spreadRadius: 3,
            ),
            const BoxShadow(
              color: Color(0x55FFD76A),
              blurRadius: 26,
              spreadRadius: 2,
            ),
          ],
        ),
        child: badge.assetPath != null
            ? Image.asset(badge.assetPath!, fit: BoxFit.contain)
            : Center(
                child: Text(badge.emoji, style: TextStyle(fontSize: size / 2)),
              ),
      ),
    );
  }
}

class _ActivityTarget extends StatelessWidget {
  const _ActivityTarget({required this.pulse});

  final double pulse;

  @override
  Widget build(BuildContext context) {
    final scale = 1 + math.sin(pulse * math.pi * 4).abs() * 0.08;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppAccentColors.accent.withValues(alpha: 0.32),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(Icons.show_chart, color: AppAccentColors.accent, size: 30),
      ),
    );
  }
}
