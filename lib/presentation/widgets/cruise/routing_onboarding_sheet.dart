import 'dart:ui' as ui;

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/routing_onboarding_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<void> showRoutingOnboardingSheet(
  BuildContext context, {
  bool force = false,
}) async {
  if (RoutingOnboardingService.isOpen) return;
  if (!force && await RoutingOnboardingService.hasAccepted()) return;
  if (!context.mounted) return;

  RoutingOnboardingService.acquireLock();
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: force,
      enableDrag: force,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.74),
      builder: (_) => RoutingOnboardingSheet(showCloseButton: force),
    );
  } finally {
    RoutingOnboardingService.releaseLock();
  }
}

class RoutingOnboardingSheet extends StatefulWidget {
  const RoutingOnboardingSheet({super.key, this.showCloseButton = false});

  final bool showCloseButton;

  @override
  State<RoutingOnboardingSheet> createState() => _RoutingOnboardingSheetState();
}

class _RoutingOnboardingSheetState extends State<RoutingOnboardingSheet> {
  late final PageController _pageController;
  late final List<bool> _checked;
  int _page = 0;
  bool _saving = false;

  static const List<_RoutingSlide> _slides = [
    _RoutingSlide(
      icon: CupertinoIcons.shield_lefthalf_fill,
      title: 'Du entscheidest',
      body:
          'Cruise Connector schlägt Routen vor. Du prüfst immer selbst, ob Straße, Manöver und Situation sicher und erlaubt sind.',
      facts: [
        _SlideFact(CupertinoIcons.car_detailed, 'Route = Vorschlag'),
        _SlideFact(CupertinoIcons.eye, 'Straße zuerst'),
        _SlideFact(
          CupertinoIcons.person_crop_circle_badge_checkmark,
          'Fahrer verantwortlich',
        ),
      ],
      checkbox:
          'Ich entscheide als Fahrer selbst und folge keiner Route blind.',
    ),
    _RoutingSlide(
      icon: CupertinoIcons.map,
      title: 'So plant die App',
      body:
          'Rundkurs, A nach B und Wegpunkte helfen dir beim Planen. Länge, Stil und Autobahn-Schalter sind Wünsche, keine Garantie.',
      facts: [
        _SlideFact(CupertinoIcons.arrow_2_circlepath, 'Rundkurs'),
        _SlideFact(CupertinoIcons.location_north_line, 'A nach B'),
        _SlideFact(CupertinoIcons.pin, 'Wegpunkte'),
      ],
      checkbox:
          'Ich weiß, dass Kartendaten und Routenberechnung abweichen können.',
    ),
    _RoutingSlide(
      icon: CupertinoIcons.exclamationmark_triangle,
      title: 'Regeln gehen vor',
      body:
          'Schilder, Sperren, Fahrverbote, Privatwege, Tempolimits und Anweisungen vor Ort haben immer Vorrang.',
      facts: [
        _SlideFact(CupertinoIcons.nosign, 'Sperren beachten'),
        _SlideFact(CupertinoIcons.speedometer, 'Limits einhalten'),
        _SlideFact(CupertinoIcons.lock_shield, 'Privatwege meiden'),
      ],
      checkbox: 'Ich halte mich an die lokalen Verkehrsregeln und Anweisungen.',
    ),
    _RoutingSlide(
      icon: CupertinoIcons.hand_raised_fill,
      title: 'Nicht bedienen',
      body:
          'Plane vor der Fahrt. Während der Fahrt bleibt das Handy in einer Halterung. Für Änderungen hältst du sicher an.',
      facts: [
        _SlideFact(CupertinoIcons.device_phone_portrait, 'Halterung nutzen'),
        _SlideFact(CupertinoIcons.speaker_2, 'Ansagen nutzen'),
        _SlideFact(CupertinoIcons.pause_circle, 'Zum Bedienen anhalten'),
      ],
      checkbox: 'Ich bediene das Gerät nicht während der Fahrt.',
    ),
    _RoutingSlide(
      icon: CupertinoIcons.doc_text_fill,
      title: 'Haftung & Nutzung',
      body:
          'Die App ersetzt keine Verkehrsregeln, Ortskenntnis oder Sorgfalt. Haftung ist nur im gesetzlich zulässigen Rahmen ausgeschlossen.',
      facts: [
        _SlideFact(CupertinoIcons.checkmark_seal, 'Unverbindlich'),
        _SlideFact(CupertinoIcons.location_slash, 'Daten können falsch sein'),
        _SlideFact(CupertinoIcons.person_crop_circle, 'Deine Verantwortung'),
      ],
      checkbox: 'Ich habe die Sicherheits- und Nutzungshinweise verstanden.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _checked = List<bool>.filled(_slides.length, false);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (!_checked[_page] || _saving) return;
    if (_page < _slides.length - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    setState(() => _saving = true);
    await RoutingOnboardingService.markAccepted();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _back() {
    if (_page == 0 || _saving) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final media = MediaQuery.of(context);
    final sheetHeight = (media.size.height * 0.84)
        .clamp(560.0, 720.0)
        .toDouble();
    final canContinue = _checked[_page] && !_saving;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SizedBox(
          height: sheetHeight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              0,
              12,
              media.padding.bottom == 0 ? 12 : 0,
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xF2161921),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                    border: Border.all(color: accent.withValues(alpha: 0.34)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.40),
                        blurRadius: 34,
                        offset: const Offset(0, -10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _SheetHeader(
                        accent: accent,
                        showCloseButton: widget.showCloseButton,
                        page: _page,
                        total: _slides.length,
                      ),
                      Expanded(
                        child: PageView.builder(
                          controller: _pageController,
                          physics: const NeverScrollableScrollPhysics(),
                          onPageChanged: (index) =>
                              setState(() => _page = index),
                          itemCount: _slides.length,
                          itemBuilder: (context, index) {
                            return _SlidePage(
                              slide: _slides[index],
                              accent: accent,
                              checked: _checked[index],
                              onChanged: (value) {
                                setState(() => _checked[index] = value);
                              },
                            );
                          },
                        ),
                      ),
                      _SheetFooter(
                        accent: accent,
                        page: _page,
                        total: _slides.length,
                        canContinue: canContinue,
                        saving: _saving,
                        onBack: _back,
                        onNext: _next,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.accent,
    required this.showCloseButton,
    required this.page,
    required this.total,
  });

  final Color accent;
  final bool showCloseButton;
  final int page;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = (page + 1) / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 10),
      child: Column(
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.17),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accent.withValues(alpha: 0.38)),
                ),
                child: Icon(
                  CupertinoIcons.car_detailed,
                  color: accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sicher fahren',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Kurz bestätigen. Jeder Schritt zählt.',
                      style: TextStyle(
                        color: Color(0xBFFFFFFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (showCloseButton)
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.10),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${page + 1} von $total',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.50),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlidePage extends StatelessWidget {
  const _SlidePage({
    required this.slide,
    required this.accent,
    required this.checked,
    required this.onChanged,
  });

  final _RoutingSlide slide;
  final Color accent;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: 0.24),
                    const Color(0xFF151A24),
                    const Color(0xFF0D121A),
                  ],
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.36),
                        ),
                      ),
                      child: Icon(slide.icon, color: accent, size: 30),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      slide.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      slide.body,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.76),
                        fontSize: 15.5,
                        height: 1.34,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final fact in slide.facts)
                          _FactPill(fact: fact, accent: accent),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _RequiredCheck(
            text: slide.checkbox,
            accent: accent,
            checked: checked,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _FactPill extends StatelessWidget {
  const _FactPill({required this.fact, required this.accent});

  final _SlideFact fact;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(fact.icon, color: accent, size: 17),
          const SizedBox(width: 8),
          Text(
            fact.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequiredCheck extends StatelessWidget {
  const _RequiredCheck({
    required this.text,
    required this.accent,
    required this.checked,
    required this.onChanged,
  });

  final String text;
  final Color accent;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onChanged(!checked),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: checked
                  ? accent.withValues(alpha: 0.70)
                  : Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: checked ? accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: checked
                        ? accent
                        : Colors.white.withValues(alpha: 0.38),
                    width: 1.4,
                  ),
                ),
                child: checked
                    ? const Icon(
                        CupertinoIcons.checkmark,
                        color: Colors.white,
                        size: 17,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.84),
                    fontSize: 13.2,
                    height: 1.28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetFooter extends StatelessWidget {
  const _SheetFooter({
    required this.accent,
    required this.page,
    required this.total,
    required this.canContinue,
    required this.saving,
    required this.onBack,
    required this.onNext,
  });

  final Color accent;
  final int page;
  final int total;
  final bool canContinue;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final isLast = page == total - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xF2161921),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: IconButton(
                onPressed: page == 0 ? null : onBack,
                icon: Icon(
                  CupertinoIcons.chevron_left,
                  color: page == 0
                      ? Colors.white.withValues(alpha: 0.20)
                      : Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: canContinue ? onNext : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    disabledBackgroundColor: Colors.white.withValues(
                      alpha: 0.10,
                    ),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white.withValues(
                      alpha: 0.34,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    elevation: 0,
                  ),
                  child: saving
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : Text(
                          canContinue
                              ? (isLast ? 'Akzeptieren' : 'Weiter')
                              : 'Häkchen setzen',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutingSlide {
  const _RoutingSlide({
    required this.icon,
    required this.title,
    required this.body,
    required this.facts,
    required this.checkbox,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<_SlideFact> facts;
  final String checkbox;
}

class _SlideFact {
  const _SlideFact(this.icon, this.label);

  final IconData icon;
  final String label;
}
