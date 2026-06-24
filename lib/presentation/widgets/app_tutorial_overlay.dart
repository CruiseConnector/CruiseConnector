import 'dart:async';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/app_tutorial_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<void> showAppTutorialOverlay(
  BuildContext context, {
  required ValueChanged<int> onTabChange,
  ValueChanged<int>? onCommunitySectionChange,
}) async {
  if (await AppTutorialService.hasCompleted()) return;
  if (!context.mounted) return;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _AppTutorialOverlay(
        onTabChange: onTabChange,
        onCommunitySectionChange: onCommunitySectionChange,
      );
    },
  );
}

class _AppTutorialOverlay extends StatefulWidget {
  const _AppTutorialOverlay({
    required this.onTabChange,
    required this.onCommunitySectionChange,
  });

  final ValueChanged<int> onTabChange;
  final ValueChanged<int>? onCommunitySectionChange;

  @override
  State<_AppTutorialOverlay> createState() => _AppTutorialOverlayState();
}

class _AppTutorialOverlayState extends State<_AppTutorialOverlay> {
  int _index = 0;

  static const List<_TutorialStep> _steps = [
    _TutorialStep(
      tab: 0,
      icon: CupertinoIcons.square_grid_2x2_fill,
      title: 'Home selbst gestalten',
      body:
          'Auf der Home kannst du Widgets sortieren, Gruppen bilden und dir die Startseite so bauen, wie du sie wirklich nutzt.',
      cta: 'Home',
      target: _TutorialTarget.home,
    ),
    _TutorialStep(
      tab: 1,
      icon: CupertinoIcons.person_2_fill,
      title: 'Community',
      body:
          'Hier findest du Fahrer, Vorschläge und soziale Bereiche. Unten ist der Community-Tab hervorgehoben.',
      cta: 'Community',
      target: _TutorialTarget.communityNav,
      communitySection: 0,
    ),
    _TutorialStep(
      tab: 1,
      icon: CupertinoIcons.news_solid,
      title: 'Feed',
      body:
          'Im Feed siehst du Posts, Fahrten und Updates von Leuten, denen du folgst.',
      cta: 'Feed',
      target: _TutorialTarget.communityFeed,
      communitySection: 0,
    ),
    _TutorialStep(
      tab: 1,
      icon: CupertinoIcons.person_3_fill,
      title: 'Gruppen',
      body:
          'Gruppen sind für gemeinsame Routen da. Vor der ersten Gruppenfahrt kommt ein kurzer Sicherheits-Hinweis mit Haken.',
      cta: 'Fahrten',
      target: _TutorialTarget.communityRides,
      communitySection: 1,
    ),
    _TutorialStep(
      tab: 1,
      icon: CupertinoIcons.chat_bubble_2_fill,
      title: 'Chats',
      body:
          'In Chats erstellst du eine Crew-Community oder redest privat mit Freunden. Routen und Absprachen bleiben direkt bei der Gruppe.',
      cta: 'Chats',
      target: _TutorialTarget.communityChats,
      communitySection: 2,
    ),
    _TutorialStep(
      tab: 1,
      icon: CupertinoIcons.search,
      title: 'Entdecken',
      body:
          'Über Entdecken findest du neue Fahrer, Gruppen und Inhalte außerhalb deiner direkten Kontakte.',
      cta: 'Entdecken',
      target: _TutorialTarget.communityDiscover,
      communitySection: 3,
    ),
    _TutorialStep(
      tab: 2,
      icon: CupertinoIcons.car_detailed,
      title: 'Cruise Mode',
      body:
          'In der Mitte planst du Routen, stellst Distanz, Fahrstil und Startpunkt ein und startest die Navigation.',
      cta: 'Cruise',
      target: _TutorialTarget.cruise,
    ),
    _TutorialStep(
      tab: 3,
      icon: CupertinoIcons.chart_bar_alt_fill,
      title: 'Analytics',
      body:
          'Analytics zeigt Fortschritt, Ranglisten, Routen, Badges und deine Fahr-Statistiken.',
      cta: 'Analytics',
      target: _TutorialTarget.analytics,
    ),
    _TutorialStep(
      tab: 4,
      icon: CupertinoIcons.person_crop_circle_fill,
      title: 'Profil',
      body:
          'Auf deinem Profil präsentierst du Garage, Badges, Sticker und alles, was andere Fahrer über dich sehen sollen.',
      cta: 'Profil',
      target: _TutorialTarget.profile,
    ),
    _TutorialStep(
      tab: 4,
      icon: CupertinoIcons.checkmark_seal_fill,
      title: 'Tutorial abgeschlossen',
      body:
          'Hiermit hast du das Tutorial abgeschlossen. Viel Spaß! Wenn du später nochmal nachsehen willst, findest du es in den Einstellungen über Konto löschen.',
      cta: 'Fertig',
      target: _TutorialTarget.done,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTab());
  }

  Future<void> _syncTab() async {
    final step = _steps[_index];
    widget.onTabChange(step.tab);
    final communitySection = step.communitySection;
    if (communitySection != null) {
      widget.onCommunitySectionChange?.call(communitySection);
    }
    await Future<void>.delayed(const Duration(milliseconds: 240));
  }

  Future<void> _finish() async {
    await AppTutorialService.markCompleted();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _next() {
    if (_index >= _steps.length - 1) {
      unawaited(_finish());
      return;
    }
    setState(() => _index += 1);
    unawaited(_syncTab());
  }

  void _back() {
    if (_index == 0) return;
    setState(() => _index -= 1);
    unawaited(_syncTab());
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_index];
    final accent = AppAccentColors.accent;
    final media = MediaQuery.of(context);
    final clampedMedia = media.copyWith(
      textScaler: media.textScaler.clamp(maxScaleFactor: 1.08),
    );

    return MediaQuery(
      data: clampedMedia,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            _TutorialHighlight(target: step.target, accent: accent),
            SafeArea(
              child: Stack(
                children: [
                  Positioned(
                    left: 18,
                    top: 14,
                    child: _Pill(
                      text: '${_index + 1}/${_steps.length}',
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  Positioned(
                    right: 18,
                    top: 10,
                    child: TextButton(
                      onPressed: _finish,
                      child: const Text(
                        'Überspringen',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: media.padding.bottom + 112,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xF2161921),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.35),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.40),
                                blurRadius: 30,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(step.icon, color: accent),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              step.title,
                                              maxLines: 1,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 22,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            step.cta,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: accent,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  step.body,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.76),
                                    fontSize: 13.6,
                                    height: 1.34,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 54,
                                      height: 50,
                                      child: IconButton(
                                        onPressed: _index == 0 ? null : _back,
                                        icon: Icon(
                                          CupertinoIcons.chevron_left,
                                          color: _index == 0
                                              ? Colors.white.withValues(
                                                  alpha: 0.20,
                                                )
                                              : Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: SizedBox(
                                        height: 50,
                                        child: FilledButton(
                                          onPressed: _next,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: accent,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                          ),
                                          child: Text(
                                            _index == _steps.length - 1
                                                ? 'Fertig'
                                                : 'Weiter',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TutorialHighlight extends StatelessWidget {
  const _TutorialHighlight({required this.target, required this.accent});

  final _TutorialTarget target;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _TutorialSpotlightPainter(target: target, accent: accent),
        ),
      ),
    );
  }
}

class _TutorialSpotlightPainter extends CustomPainter {
  const _TutorialSpotlightPainter({required this.target, required this.accent});

  final _TutorialTarget target;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final spotlight = _spotlightFor(size);
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.70);

    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, dim);
    if (spotlight != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(spotlight, const Radius.circular(24)),
        Paint()..blendMode = BlendMode.clear,
      );
    }
    canvas.restore();

    if (spotlight == null) return;
    final outer = RRect.fromRectAndRadius(
      spotlight.inflate(3),
      const Radius.circular(27),
    );
    canvas
      ..drawRRect(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = accent.withValues(alpha: 0.78),
      )
      ..drawRRect(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 11
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
          ..color = accent.withValues(alpha: 0.28),
      );
  }

  Rect? _spotlightFor(Size size) {
    final width = size.width;
    final height = size.height;

    final bottomNavY = height - 48;
    Rect bottomNavTarget(double xFactor, {double targetWidth = 74}) {
      return Rect.fromCenter(
        center: Offset(width * xFactor, bottomNavY),
        width: targetWidth,
        height: 58,
      );
    }

    Rect communityTabTarget(double xFactor, double targetWidth) {
      return Rect.fromCenter(
        center: Offset(width * xFactor, 143),
        width: targetWidth,
        height: 46,
      );
    }

    return switch (target) {
      _TutorialTarget.home => bottomNavTarget(0.11),
      _TutorialTarget.communityNav => bottomNavTarget(0.29, targetWidth: 82),
      _TutorialTarget.communityFeed => communityTabTarget(0.125, 90),
      _TutorialTarget.communityRides => communityTabTarget(0.365, 104),
      _TutorialTarget.communityChats => communityTabTarget(0.625, 96),
      _TutorialTarget.communityDiscover => communityTabTarget(0.84, 108),
      _TutorialTarget.cruise => Rect.fromCenter(
        center: Offset(width * 0.50, height - 72),
        width: 104,
        height: 104,
      ),
      _TutorialTarget.analytics => bottomNavTarget(0.70, targetWidth: 82),
      _TutorialTarget.profile => bottomNavTarget(0.90),
      _TutorialTarget.done => null,
    };
  }

  @override
  bool shouldRepaint(covariant _TutorialSpotlightPainter oldDelegate) {
    return oldDelegate.target != target || oldDelegate.accent != accent;
  }
}

class _TutorialStep {
  const _TutorialStep({
    required this.tab,
    required this.icon,
    required this.title,
    required this.body,
    required this.cta,
    required this.target,
    this.communitySection,
  });

  final int tab;
  final IconData icon;
  final String title;
  final String body;
  final String cta;
  final _TutorialTarget target;
  final int? communitySection;
}

enum _TutorialTarget {
  home,
  communityNav,
  communityFeed,
  communityRides,
  communityChats,
  communityDiscover,
  cruise,
  analytics,
  profile,
  done,
}
