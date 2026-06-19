import 'dart:ui' as ui;

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/safety_notice_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<bool> showGroupSafetyNoticeSheet(
  BuildContext context, {
  bool force = false,
}) async {
  if (!force && await SafetyNoticeService.hasAcceptedGroupSafety()) {
    return true;
  }
  if (!context.mounted) return false;

  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: force,
    enableDrag: force,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => GroupSafetyNoticeSheet(showCloseButton: force),
  );
  return accepted ?? false;
}

class GroupSafetyNoticeSheet extends StatefulWidget {
  const GroupSafetyNoticeSheet({super.key, this.showCloseButton = false});

  final bool showCloseButton;

  @override
  State<GroupSafetyNoticeSheet> createState() => _GroupSafetyNoticeSheetState();
}

class _GroupSafetyNoticeSheetState extends State<GroupSafetyNoticeSheet> {
  late final PageController _controller;
  late final List<bool> _checked;
  int _page = 0;
  bool _saving = false;

  static const List<_GroupNoticeSlide> _slides = [
    _GroupNoticeSlide(
      icon: CupertinoIcons.person_2_fill,
      title: 'Keine Veranstaltung',
      body:
          'Eine Gruppe ist nur eine gemeinsame Route in der App. Sie ist keine offizielle Veranstaltung, kein Rennen und keine Straßensperrung.',
      checkbox: 'Ich erstelle keine Veranstaltung und bewerbe kein Rennen.',
    ),
    _GroupNoticeSlide(
      icon: CupertinoIcons.shield_fill,
      title: 'Jeder fährt selbst',
      body:
          'Alle Teilnehmer bleiben eigenverantwortlich. Abstand, Tempo, Verkehrsregeln und lokale Anweisungen gehen immer vor.',
      checkbox: 'Ich setze niemanden unter Druck und beachte die Regeln.',
    ),
    _GroupNoticeSlide(
      icon: CupertinoIcons.map_pin_ellipse,
      title: 'Route prüfen',
      body:
          'Wähle Treffpunkt, Uhrzeit und Route so, dass sie sicher erreichbar sind. Öffentliche Gruppen sollen klar und verantwortungsvoll beschrieben sein.',
      checkbox:
          'Ich prüfe Route, Startpunkt und Beschreibung vor dem Erstellen.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _checked = List<bool>.filled(_slides.length, false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (!_checked[_page] || _saving) return;
    if (_page < _slides.length - 1) {
      await _controller.nextPage(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    setState(() => _saving = true);
    await SafetyNoticeService.markGroupSafetyAccepted();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _back() {
    if (_page == 0 || _saving) return;
    _controller.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final media = MediaQuery.of(context);
    final height = (media.size.height * 0.74).clamp(500.0, 620.0).toDouble();
    final canContinue = _checked[_page] && !_saving;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              0,
              12,
              media.padding.bottom == 0 ? 12 : 0,
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xF2161921),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                    border: Border.all(color: accent.withValues(alpha: 0.32)),
                  ),
                  child: Column(
                    children: [
                      _Header(
                        accent: accent,
                        page: _page,
                        total: _slides.length,
                        showCloseButton: widget.showCloseButton,
                      ),
                      Expanded(
                        child: PageView.builder(
                          controller: _controller,
                          physics: const NeverScrollableScrollPhysics(),
                          onPageChanged: (index) =>
                              setState(() => _page = index),
                          itemCount: _slides.length,
                          itemBuilder: (context, index) => _Slide(
                            slide: _slides[index],
                            accent: accent,
                            checked: _checked[index],
                            onChanged: (value) =>
                                setState(() => _checked[index] = value),
                          ),
                        ),
                      ),
                      _Footer(
                        accent: accent,
                        canContinue: canContinue,
                        saving: _saving,
                        isFirst: _page == 0,
                        isLast: _page == _slides.length - 1,
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

class _Header extends StatelessWidget {
  const _Header({
    required this.accent,
    required this.page,
    required this.total,
    required this.showCloseButton,
  });

  final Color accent;
  final int page;
  final int total;
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
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
              Icon(CupertinoIcons.person_3_fill, color: accent, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Gruppenfahrt-Hinweise',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (showCloseButton)
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (page + 1) / total,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.10),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({
    required this.slide,
    required this.accent,
    required this.checked,
    required this.onChanged,
  });

  final _GroupNoticeSlide slide;
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
                color: Colors.white.withValues(alpha: 0.055),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(slide.icon, color: accent, size: 42),
                    const SizedBox(height: 20),
                    Text(
                      slide.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      slide.body,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.76),
                        fontSize: 15.5,
                        height: 1.36,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _CheckRow(
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

class _CheckRow extends StatelessWidget {
  const _CheckRow({
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
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => onChanged(!checked),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: checked
                ? accent.withValues(alpha: 0.70)
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Row(
          children: [
            Icon(
              checked
                  ? CupertinoIcons.checkmark_square_fill
                  : CupertinoIcons.square,
              color: checked ? accent : Colors.white.withValues(alpha: 0.45),
              size: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 13.2,
                  height: 1.28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.accent,
    required this.canContinue,
    required this.saving,
    required this.isFirst,
    required this.isLast,
    required this.onBack,
    required this.onNext,
  });

  final Color accent;
  final bool canContinue;
  final bool saving;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: IconButton(
                onPressed: isFirst ? null : onBack,
                icon: Icon(
                  CupertinoIcons.chevron_left,
                  color: isFirst
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  child: saving
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : Text(
                          canContinue
                              ? (isLast ? 'Akzeptieren' : 'Weiter')
                              : 'Häkchen setzen',
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
      ),
    );
  }
}

class _GroupNoticeSlide {
  const _GroupNoticeSlide({
    required this.icon,
    required this.title,
    required this.body,
    required this.checkbox,
  });

  final IconData icon;
  final String title;
  final String body;
  final String checkbox;
}
