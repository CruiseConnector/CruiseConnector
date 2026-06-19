import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/domain/models/user_level.dart';

Future<void> showXpLevelProgressPopup({
  required BuildContext context,
  required int previousTotalXp,
  required int newTotalXp,
  int? xpEarned,
}) {
  if (newTotalXp <= previousTotalXp) return Future<void>.value();

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'XP Fortschritt',
    barrierColor: Colors.black.withValues(alpha: 0.52),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _XpLevelProgressPopup(
        previousTotalXp: previousTotalXp,
        newTotalXp: newTotalXp,
        xpEarned: xpEarned ?? (newTotalXp - previousTotalXp),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class _XpLevelSegment {
  const _XpLevelSegment({
    required this.level,
    required this.fromXp,
    required this.toXp,
    required this.reachedLevel,
  });

  final int level;
  final int fromXp;
  final int toXp;
  final int? reachedLevel;
}

class _XpLevelProgressPopup extends StatefulWidget {
  const _XpLevelProgressPopup({
    required this.previousTotalXp,
    required this.newTotalXp,
    required this.xpEarned,
  });

  final int previousTotalXp;
  final int newTotalXp;
  final int xpEarned;

  @override
  State<_XpLevelProgressPopup> createState() => _XpLevelProgressPopupState();
}

class _XpLevelProgressPopupState extends State<_XpLevelProgressPopup>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _barController;
  late final AnimationController _burstController;
  late final List<_XpLevelSegment> _segments;
  int _segmentIndex = 0;
  int? _announcedLevel;

  _XpLevelSegment get _segment => _segments[_segmentIndex];

  @override
  void initState() {
    super.initState();
    _segments = _buildSegments(widget.previousTotalXp, widget.newTotalXp);
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
      reverseDuration: const Duration(milliseconds: 260),
    );
    _barController = AnimationController(vsync: this);
    _burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    _play();
  }

  List<_XpLevelSegment> _buildSegments(int fromXp, int toXp) {
    final segments = <_XpLevelSegment>[];
    var cursorXp = fromXp;
    var level = UserLevel.fromXp(cursorXp.toDouble()).level;

    while (level < UserLevel.maxLevel) {
      final nextLevelXp = UserLevel.xpForLevel(level + 1).round();
      if (toXp < nextLevelXp) break;
      segments.add(
        _XpLevelSegment(
          level: level,
          fromXp: cursorXp,
          toXp: nextLevelXp,
          reachedLevel: level + 1,
        ),
      );
      cursorXp = nextLevelXp;
      level += 1;
    }

    if (segments.isEmpty || cursorXp < toXp) {
      segments.add(
        _XpLevelSegment(
          level: UserLevel.fromXp(cursorXp.toDouble()).level,
          fromXp: cursorXp,
          toXp: toXp,
          reachedLevel: null,
        ),
      );
    }

    return segments;
  }

  Future<void> _play() async {
    await _entryController.forward();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    HapticFeedback.selectionClick();

    for (var index = 0; index < _segments.length; index++) {
      if (!mounted) return;
      setState(() {
        _segmentIndex = index;
        _announcedLevel = null;
      });
      _barController.value = 0;
      _barController.duration = _durationFor(_segments[index]);

      try {
        await _barController.forward(from: 0);
      } on TickerCanceled {
        return;
      }

      final reachedLevel = _segments[index].reachedLevel;
      if (reachedLevel != null) {
        if (!mounted) return;
        setState(() => _announcedLevel = reachedLevel);
        HapticFeedback.heavyImpact();
        try {
          await _burstController.forward(from: 0);
        } on TickerCanceled {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 170));
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    await _entryController.reverse();
    if (mounted) Navigator.of(context).maybePop();
  }

  Duration _durationFor(_XpLevelSegment segment) {
    final delta = math.max(40, segment.toXp - segment.fromXp);
    final ms = (760 + math.min(820, delta * 1.65)).round();
    return Duration(milliseconds: ms);
  }

  @override
  void dispose() {
    _entryController.dispose();
    _barController.dispose();
    _burstController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final merged = Listenable.merge([
      _entryController,
      _barController,
      _burstController,
    ]);

    return Material(
      type: MaterialType.transparency,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: AnimatedBuilder(
          animation: merged,
          builder: (context, child) {
            final entry = Curves.easeOutBack.transform(_entryController.value);
            final exitOpacity = _entryController.value.clamp(0.0, 1.0);
            final burst = _burstController.value;
            final shake = _announcedLevel == null
                ? 0.0
                : math.sin(burst * math.pi * 12) * (1 - burst) * 8;

            return Opacity(
              opacity: exitOpacity,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: const Color(0xFF05070B).withValues(alpha: 0.48),
                    ),
                  ),
                  ..._buildParticles(context, burst),
                  Center(
                    child: Transform.translate(
                      offset: Offset(shake, ui.lerpDouble(70, 0, entry)!),
                      child: Transform.scale(
                        scale: ui.lerpDouble(0.91, 1.0, entry)!,
                        child: _buildCard(context),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildParticles(BuildContext context, double burst) {
    final size = MediaQuery.sizeOf(context);
    final center = Offset(size.width / 2, size.height / 2);
    final active = _announcedLevel != null;
    final opacity = active
        ? (1 - ((burst - 0.45).clamp(0.0, 0.55) / 0.55))
              .clamp(0.0, 1.0)
              .toDouble()
        : 0.16;

    return List<Widget>.generate(18, (index) {
      final angle = (math.pi * 2 / 18) * index + 0.18;
      final baseDistance = active ? 92 + 160 * burst : 118 + index * 3;
      final drift = math.sin((_barController.value + index) * math.pi) * 10;
      final x = center.dx + math.cos(angle) * (baseDistance + drift);
      final y = center.dy + math.sin(angle) * (baseDistance + drift * 0.4);
      final particleSize = active ? 8 + 10 * (1 - burst) : 4.0;

      return Positioned(
        left: x - particleSize / 2,
        top: y - particleSize / 2,
        child: Opacity(
          opacity: opacity,
          child: Transform.rotate(
            angle: angle + burst,
            child: Container(
              width: particleSize,
              height: particleSize,
              decoration: BoxDecoration(
                color: index.isEven
                    ? AppAccentColors.accent
                    : const Color(0xFFFFD166),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildCard(BuildContext context) {
    final progress = Curves.easeInOutCubic.transform(_barController.value);
    final fromLevel = UserLevel.fromXp(_segment.fromXp.toDouble());
    final shownLevel = _announcedLevel ?? _segment.level;
    final shownUserLevel = UserLevel.fromXp(
      UserLevel.xpForLevel(shownLevel).toDouble(),
    );
    final currentXp = ui
        .lerpDouble(
          _segment.fromXp.toDouble(),
          _segment.toXp.toDouble(),
          progress,
        )!
        .round();
    final fromProgress = _progressFor(_segment.fromXp, _segment.level);
    final toProgress = _segment.reachedLevel == null
        ? _progressFor(_segment.toXp, _segment.level)
        : 1.0;
    final barProgress = ui
        .lerpDouble(fromProgress, toProgress, progress)!
        .clamp(0.0, 1.0)
        .toDouble();
    final isLevelBurst = _announcedLevel != null;
    final burstScale = isLevelBurst
        ? 1 + math.sin(_burstController.value * math.pi) * 0.08
        : 1.0;
    final nextLevel = _segment.level >= UserLevel.maxLevel
        ? _segment.level
        : _segment.level + 1;

    return Container(
      width: math.min(MediaQuery.sizeOf(context).width - 34, 420),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF111821).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppAccentColors.accent.withValues(alpha: 0.36),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: AppAccentColors.accent.withValues(alpha: 0.22),
            blurRadius: 42,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.36),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppAccentColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppAccentColors.accent.withValues(alpha: 0.28),
              ),
            ),
            child: Text(
              '+${_formatXp(widget.xpEarned)} XP',
              style: TextStyle(
                color: AppAccentColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Transform.scale(
            scale: burstScale,
            child: Text(
              isLevelBurst
                  ? 'Level $shownLevel erreicht'
                  : 'Level ${fromLevel.level}',
              textAlign: TextAlign.center,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isLevelBurst
                ? 'Du bist jetzt ${shownUserLevel.name}'
                : fromLevel.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFC8CFDC),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 22),
          _buildProgressBar(barProgress),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                _formatXp(currentXp),
                style: const TextStyle(
                  color: Color(0xFFAEB8C8),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                _segment.reachedLevel == null
                    ? 'Level $nextLevel'
                    : 'Level ${_segment.reachedLevel}',
                style: const TextStyle(
                  color: Color(0xFFAEB8C8),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(double progress) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          Container(
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppAccentColors.accent, const Color(0xFFFFD166)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppAccentColors.accent.withValues(alpha: 0.54),
                    blurRadius: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _progressFor(int totalXp, int level) {
    if (level >= UserLevel.maxLevel) return 1;
    final start = UserLevel.xpForLevel(level);
    final next = UserLevel.xpForLevel(level + 1);
    final span = next - start;
    if (span <= 0) return 1;
    return ((totalXp - start) / span).clamp(0.0, 1.0).toDouble();
  }

  String _formatXp(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final remaining = text.length - i;
      buffer.write(text[i]);
      if (remaining > 1 && remaining % 3 == 1) buffer.write('.');
    }
    return buffer.toString();
  }
}
