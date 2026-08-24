import 'dart:async';
import 'dart:ui' as ui;

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/safety_notice_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Wie lange ein Zugriff auf den Geraetespeicher dauern darf. Danach machen wir
/// ohne ihn weiter — ein haengender Speicher darf niemanden im Blatt festhalten.
const Duration _speicherGrenze = Duration(seconds: 3);

/// Zeigt den Hinweis „Mitteilungen erlauben".
///
/// 2026-08-24 (Vorfall „App haengt", iPhone 15 Pro Max): Dieses Blatt hatte
/// dieselbe Bauart wie die Sackgasse im Standort-Hinweis — `isDismissible` und
/// `enableDrag` aus, kein X, und der EINZIGE Ausgang war ein Knopf, der an
/// `_busy` hing. `_busy` wurde gesetzt, bevor in den Geraetespeicher
/// geschrieben wurde, und erst nach dem Schreiben wieder frei. Antwortet der
/// Speicher-Kanal nicht (volle Platte, Plugin nicht da, Kanal blockiert),
/// bleibt der einzige Knopf fuer immer grau.
///
/// Seitdem gilt hier hart:
///  1. Erst schliessen, dann merken. Der Ausgang haengt an NICHTS.
///  2. Es gibt einen zweiten, ehrlichen Weg („Jetzt nicht") und zusaetzlich
///     Wischen/Tippen daneben.
///  3. Jeder Speicherzugriff hat eine Zeitgrenze.
Future<bool> showNotificationPermissionNoticeSheet(
  BuildContext context, {
  bool force = false,
}) async {
  if (!force && await _hinweisSchonGesehen()) {
    return _hinweisSchonAngenommen();
  }
  if (!context.mounted) return false;

  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // 2026-08-24: wieder wegtippbar/wegwischbar. Wegwischen heisst „jetzt
    // nicht" — wir fragen dann einfach keine Mitteilungen an.
    isDismissible: true,
    enableDrag: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.70),
    builder: (_) => const NotificationPermissionNoticeSheet(),
  );
  return accepted ?? false;
}

/// Speicher-Lesezugriffe mit Zeitgrenze. Antwortet der Speicher nicht, zeigen
/// wir den Hinweis lieber nochmal, als in einem `await` zu versanden.
Future<bool> _hinweisSchonGesehen() async {
  try {
    return await SafetyNoticeService.hasSeenNotificationPermissionNotice()
        .timeout(_speicherGrenze);
  } catch (fehler) {
    debugPrint('[Mitteilungs-Hinweis] Merker lesen fehlgeschlagen: $fehler');
    return false;
  }
}

Future<bool> _hinweisSchonAngenommen() async {
  try {
    return await SafetyNoticeService.hasAcceptedNotificationPermissionNotice()
        .timeout(_speicherGrenze);
  } catch (fehler) {
    debugPrint(
      '[Mitteilungs-Hinweis] Zustimmung lesen fehlgeschlagen: $fehler',
    );
    return false;
  }
}

/// Test-Naht: „gesehen/angenommen" merken.
typedef MitteilungsMerker = Future<void> Function({required bool accepted});

class NotificationPermissionNoticeSheet extends StatefulWidget {
  const NotificationPermissionNoticeSheet({super.key, this.hinweisMerken});

  /// Test-Naht: Standard ist `SafetyNoticeService.markNotificationPermissionNotice`.
  final MitteilungsMerker? hinweisMerken;

  @override
  State<NotificationPermissionNoticeSheet> createState() =>
      _NotificationPermissionNoticeSheetState();
}

class _NotificationPermissionNoticeSheetState
    extends State<NotificationPermissionNoticeSheet> {
  bool _beendet = false;

  /// Der Ausgang. Erst schliessen, dann merken — nie umgekehrt. Der
  /// Geraetespeicher ist ein Plattform-Kanal und darf den Nutzer nicht
  /// aufhalten; deshalb laeuft das Schreiben nebenher und mit Zeitgrenze.
  void _close(bool accepted) {
    if (_beendet || !mounted) return;
    _beendet = true;
    final merken =
        widget.hinweisMerken ??
        SafetyNoticeService.markNotificationPermissionNotice;
    unawaited(
      merken(accepted: accepted).timeout(_speicherGrenze).catchError((
        Object fehler,
      ) {
        debugPrint(
          '[Mitteilungs-Hinweis] Merker schreiben fehlgeschlagen: $fehler',
        );
      }),
    );
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
                                // NIE gesperrt: dieser Knopf braucht weder
                                // Netz noch Speicher noch das System.
                                onPressed: () => _close(true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: const Text(
                                  'Weiter',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                            // Zweiter, ehrlicher Ausgang: kein Zwang zur
                            // Zustimmung, und ebenfalls nie gesperrt.
                            const SizedBox(height: 6),
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: TextButton(
                                onPressed: () => _close(false),
                                child: Text(
                                  'Jetzt nicht',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w700,
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
