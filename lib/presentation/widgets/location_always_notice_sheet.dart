import 'dart:ui' as ui;

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/safety_notice_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;

Future<void> showLocationAlwaysNoticeSheet(
  BuildContext context, {
  bool force = false,
}) async {
  if (!force && await SafetyNoticeService.hasSeenLocationAlwaysNotice()) {
    return;
  }
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.70),
    builder: (_) => const LocationAlwaysNoticeSheet(),
  );
}

class LocationAlwaysNoticeSheet extends StatefulWidget {
  const LocationAlwaysNoticeSheet({super.key});

  @override
  State<LocationAlwaysNoticeSheet> createState() =>
      _LocationAlwaysNoticeSheetState();
}

class _LocationAlwaysNoticeSheetState extends State<LocationAlwaysNoticeSheet> {
  bool _busy = false;

  Future<void> _markAndClose() async {
    await SafetyNoticeService.markLocationAlwaysNoticeSeen();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _openSettings() async {
    if (_busy) return;
    setState(() => _busy = true);
    await SafetyNoticeService.markLocationAlwaysNoticeSeen();
    await geo.Geolocator.openAppSettings();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final media = MediaQuery.of(context);
    final height = (media.size.height * 0.58).clamp(430.0, 520.0).toDouble();

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
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Center(
                                    child: Container(
                                      width: 38,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.20,
                                        ),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Icon(
                                    CupertinoIcons.location_fill,
                                    color: accent,
                                    size: 34,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Standort immer erlauben',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 25,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Für aktive Navigation, Gruppenfahrten und sichere Re-Updates muss Cruise Connector deinen Standort auch weiter nutzen können, wenn du kurz die App wechselst oder der Bildschirm gesperrt ist.',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.72,
                                      ),
                                      fontSize: 14.2,
                                      height: 1.36,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _HintRow(
                                    accent: accent,
                                    icon: CupertinoIcons.lock_rotation,
                                    text:
                                        'Aktive Fahrt bleibt stabil im Hintergrund.',
                                  ),
                                  _HintRow(
                                    accent: accent,
                                    icon: CupertinoIcons.person_2_fill,
                                    text:
                                        'Gruppenmitglieder sehen weiter deinen echten Fortschritt.',
                                  ),
                                  _HintRow(
                                    accent: accent,
                                    icon: CupertinoIcons.gear,
                                    text:
                                        'Du kannst die Freigabe jederzeit in iOS/Android ändern.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: OutlinedButton(
                                    onPressed: _busy ? null : _markAndClose,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.18,
                                        ),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                    child: const Text(
                                      'Später',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: FilledButton(
                                    onPressed: _busy ? null : _openSettings,
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
                                            'Einstellungen',
                                            style: TextStyle(
                                              color: Colors.white,
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
