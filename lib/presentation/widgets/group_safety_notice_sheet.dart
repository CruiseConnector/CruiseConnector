import 'dart:ui' as ui;

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/app_tutorial_service.dart';
import 'package:cruise_connect/data/services/safety_notice_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<bool> showGroupSafetyNoticeSheet(
  BuildContext context, {
  bool force = false,
}) async {
  if (!force && !await AppTutorialService.hasCompleted()) {
    return false;
  }
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
  final ScrollController _controller = ScrollController();
  bool _readToBottom = false;
  bool _accepted = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 2026-07-03 (vucko): Defensive Absicherung. Normal hat der Hinweis echten
    // Overflow (~570 px) → der Nutzer scrollt bis unten und der Gate gibt frei.
    // ABER falls der Inhalt mal komplett in die (auf 720 geklemmte) Sheet-Hoehe
    // passt (z. B. sehr kleine System-Schriftgröße), wäre maxScrollExtent 0,
    // es feuerte nie ein Scroll-Event und der „bis unten scrollen"-Gate liesse
    // sich nie erfüllen → harter Deadlock bei der Gruppenerstellung. Deshalb:
    // wenn es nach dem ersten Layout nichts zu scrollen gibt, sofort freigeben.
    WidgetsBinding.instance.addPostFrameCallback((_) => _markReadIfNoScroll());
  }

  void _markReadIfNoScroll() {
    if (!mounted || _readToBottom) return;
    if (!_controller.hasClients) {
      // Scroll-View haengt beim ersten Frame evtl. noch nicht → 1× nachfassen.
      WidgetsBinding.instance.addPostFrameCallback((_) => _markReadIfNoScroll());
      return;
    }
    if (_controller.position.maxScrollExtent <= 0) {
      setState(() => _readToBottom = true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (!_readToBottom || !_accepted || _saving) return;
    setState(() => _saving = true);
    await SafetyNoticeService.markGroupSafetyAccepted();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  bool _handleScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (!_readToBottom && metrics.pixels >= metrics.maxScrollExtent - 24) {
      setState(() => _readToBottom = true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final media = MediaQuery.of(context);
    final height = (media.size.height * 0.82).clamp(560.0, 720.0).toDouble();
    final canAccept = _readToBottom && _accepted && !_saving;

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
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                      child: Column(
                        children: [
                          _Header(
                            accent: accent,
                            showCloseButton: widget.showCloseButton,
                          ),
                          Expanded(
                            child: NotificationListener<ScrollNotification>(
                              onNotification: _handleScroll,
                              child: SingleChildScrollView(
                                controller: _controller,
                                physics: const BouncingScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 12),
                                    _NoticeCard(
                                      icon: CupertinoIcons.person_2_fill,
                                      title: 'Keine Veranstaltung',
                                      text:
                                          'Eine Gruppe ist nur eine gemeinsame Route in der App. Sie ist keine offizielle Veranstaltung, kein Rennen und keine Straßensperrung.',
                                      accent: accent,
                                    ),
                                    _NoticeCard(
                                      icon: CupertinoIcons.shield_fill,
                                      title: 'Jeder fährt selbst',
                                      text:
                                          'Alle Teilnehmer bleiben eigenverantwortlich. Abstand, Tempo, Verkehrsregeln und lokale Anweisungen gehen immer vor.',
                                      accent: accent,
                                    ),
                                    _NoticeCard(
                                      icon: CupertinoIcons.map_pin_ellipse,
                                      title: 'Route prüfen',
                                      text:
                                          'Wähle Treffpunkt, Uhrzeit und Route so, dass sie sicher erreichbar sind. Öffentliche Gruppen sollen klar und verantwortungsvoll beschrieben sein.',
                                      accent: accent,
                                    ),
                                    _NoticeCard(
                                      icon: CupertinoIcons
                                          .exclamationmark_triangle_fill,
                                      title: 'Keine riskanten Fahrten',
                                      text:
                                          'Plane keine gefährlichen Aktionen. Keine illegalen Manöver, kein Druck auf andere und keine Aufforderung zu Rennen.',
                                      accent: accent,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Scrolle bis zum Ende und setze den Haken. Danach erscheint dieser Hinweis nicht mehr automatisch.',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.56,
                                        ),
                                        fontSize: 12.5,
                                        height: 1.3,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          _CheckRow(
                            text:
                                'Ich habe die Hinweise gelesen und erstelle keine riskante oder illegale Gruppenfahrt.',
                            accent: accent,
                            checked: _accepted,
                            enabled: _readToBottom,
                            onChanged: (value) =>
                                setState(() => _accepted = value),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: FilledButton(
                              onPressed: canAccept ? _accept : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                disabledBackgroundColor: Colors.white
                                    .withValues(alpha: 0.10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(22),
                                ),
                              ),
                              child: _saving
                                  ? const CupertinoActivityIndicator(
                                      color: Colors.white,
                                    )
                                  : Text(
                                      !_readToBottom
                                          ? 'Erst bis unten scrollen'
                                          : !_accepted
                                          ? 'Häkchen setzen'
                                          : 'Verstanden',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
  const _Header({required this.accent, required this.showCloseButton});

  final Color accent;
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
    return Column(
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
                'Gruppenfahrt-Hinweis',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
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
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.74),
                    fontSize: 13.4,
                    height: 1.32,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
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
    required this.enabled,
    required this.onChanged,
  });

  final String text;
  final Color accent;
  final bool checked;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.48,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? () => onChanged(!checked) : null,
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
                    fontSize: 13.0,
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
