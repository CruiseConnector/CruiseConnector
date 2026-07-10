import 'dart:ui' as ui;

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/safety_notice_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<bool> showNotificationPermissionNoticeSheet(
  BuildContext context, {
  bool force = false,
}) async {
  if (!force &&
      await SafetyNoticeService.hasSeenNotificationPermissionNotice()) {
    return SafetyNoticeService.hasAcceptedNotificationPermissionNotice();
  }
  if (!context.mounted) return false;

  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // Apple 5.1.1(iv): Kein Ausweg vor der System-Permission-Anfrage — der
    // Nutzer muss nach dieser Erklärung immer bei der echten Anfrage landen.
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.70),
    builder: (_) => const NotificationPermissionNoticeSheet(),
  );
  return accepted ?? false;
}

class NotificationPermissionNoticeSheet extends StatefulWidget {
  const NotificationPermissionNoticeSheet({super.key});

  @override
  State<NotificationPermissionNoticeSheet> createState() =>
      _NotificationPermissionNoticeSheetState();
}

class _NotificationPermissionNoticeSheetState
    extends State<NotificationPermissionNoticeSheet> {
  bool _busy = false;

  Future<void> _close(bool accepted) async {
    if (_busy) return;
    setState(() => _busy = true);
    await SafetyNoticeService.markNotificationPermissionNotice(
      accepted: accepted,
    );
    if (!mounted) return;
    Navigator.of(context).pop(accepted);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final media = MediaQuery.of(context);
    final clampedMedia = media.copyWith(
      textScaler: media.textScaler.clamp(maxScaleFactor: 1.08),
    );
    final height = (media.size.height * 0.58).clamp(420.0, 560.0).toDouble();

    return MediaQuery(
      data: clampedMedia,
      child: Align(
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
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 38,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.20),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Expanded(
                              child: SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      CupertinoIcons.bell_fill,
                                      color: accent,
                                      size: 34,
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Mitteilungen erlauben',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 25,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Wir schicken dir nur wichtige Hinweise wie Gruppen-Updates, neue Follower, Antworten und Routen-Erinnerungen.',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.72,
                                        ),
                                        fontSize: 14.2,
                                        height: 1.34,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    _HintRow(
                                      accent: accent,
                                      icon: CupertinoIcons.person_2_fill,
                                      text:
                                          'Gruppenfahrten und Einladungen kommen rechtzeitig an.',
                                    ),
                                    _HintRow(
                                      accent: accent,
                                      icon: CupertinoIcons.chat_bubble_2_fill,
                                      text:
                                          'Antworten, Likes und neue Kontakte landen nicht unbemerkt.',
                                    ),
                                    _HintRow(
                                      accent: accent,
                                      icon: CupertinoIcons.slider_horizontal_3,
                                      text:
                                          'Du kannst Mitteilungen später in den Einstellungen ändern.',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton(
                                onPressed: _busy ? null : () => _close(true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: _busy
                                    ? const CupertinoActivityIndicator(
                                        color: Colors.white,
                                      )
                                    : const Text(
                                        'Weiter',
                                        style: TextStyle(
                                          color: Colors.white,
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
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  const _HintRow({
    required this.accent,
    required this.icon,
    required this.text,
  });

  final Color accent;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.74),
                fontSize: 13.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
