import 'dart:ui' as ui;

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/location_permission_helper.dart';
import 'package:cruise_connect/data/services/safety_notice_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;

Future<bool> showLocationAlwaysNoticeSheet(
  BuildContext context, {
  bool force = false,
}) async {
  if (!force && await SafetyNoticeService.hasSeenLocationAlwaysNotice()) {
    return true;
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
    builder: (_) => const LocationAlwaysNoticeSheet(),
  );
  return accepted ?? false;
}

class LocationAlwaysNoticeSheet extends StatefulWidget {
  const LocationAlwaysNoticeSheet({super.key});

  @override
  State<LocationAlwaysNoticeSheet> createState() =>
      _LocationAlwaysNoticeSheetState();
}

class _LocationAlwaysNoticeSheetState extends State<LocationAlwaysNoticeSheet> {
  bool _busy = false;
  // 2026-07-03 (vucko „Standort immer / direkt in Einstellungen"): Zweiter
  // Schritt — nach dem System-Dialog hat der Nutzer evtl. nur „Beim Verwenden"
  // erteilt. Dann zeigen wir hier einen klaren 1-Tap-Button, der DIREKT die
  // App-Standort-Einstellungen öffnet (wo „Immer erlauben" gesetzt wird),
  // statt ihn hart aus der App zu werfen.
  bool _needsSettingsStep = false;

  Future<void> _acceptPermission() async {
    if (_busy) return;
    setState(() => _busy = true);
    await SafetyNoticeService.markLocationAlwaysNoticeSeen();
    var result = geo.LocationPermission.denied;
    try {
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        // Fragt an + stuft (so weit per Dialog möglich) auf „Immer" hoch. Die
        // Einstellungen öffnen wir bewusst NICHT automatisch — dafür gibt es
        // den klaren Folge-Button, damit der Nutzer nicht überrascht rausfliegt.
        result = await LocationPermissionHelper.requestAlways(
          openSettingsIfNeeded: false,
        );
      }
    } catch (_) {
      // Best-effort: Wenn iOS/Android gerade nicht antwortet, bleibt die App ruhig.
    }
    if (!mounted) return;
    if (result == geo.LocationPermission.always) {
      Navigator.of(context).pop(true);
      return;
    }
    // „Immer" fehlt noch (nur Beim-Verwenden / abgelehnt) → Einstellungs-Schritt.
    setState(() {
      _busy = false;
      _needsSettingsStep = true;
    });
  }

  Future<void> _openSettings() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await LocationPermissionHelper.openSettings();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final media = MediaQuery.of(context);
    final clampedMedia = media.copyWith(
      textScaler: media.textScaler.clamp(maxScaleFactor: 1.08),
    );
    final height = (media.size.height * 0.76).clamp(520.0, 680.0).toDouble();

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
                                      _needsSettingsStep
                                          ? CupertinoIcons.gear_alt_fill
                                          : CupertinoIcons.location_fill,
                                      color: accent,
                                      size: 34,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _needsSettingsStep
                                          ? 'Standort in den Einstellungen'
                                          : 'Standort für die Navigation',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 25,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _needsSettingsStep
                                          ? 'Du hast den Standort nur „Beim Verwenden" freigegeben. Für Navigation im Hintergrund und Gruppenfahrten öffnen wir dich direkt in den Einstellungen. Tippe dort auf Standort und wähle „Immer".'
                                          : 'Für aktive Navigation, Gruppenfahrten und sichere Re-Updates muss Cruise Connector deinen Standort auch weiter nutzen können, wenn du kurz die App wechselst oder der Bildschirm gesperrt ist.',
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
                                    if (_needsSettingsStep) ...[
                                      _HintRow(
                                        accent: accent,
                                        icon: CupertinoIcons.location_fill,
                                        text:
                                            '„Standort" antippen → „Immer" wählen.',
                                      ),
                                      _HintRow(
                                        accent: accent,
                                        icon: CupertinoIcons.checkmark_seal_fill,
                                        text:
                                            'Genauen Standort aktiviert lassen.',
                                      ),
                                    ] else ...[
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
                                            'Du kannst die Freigabe jederzeit in den Einstellungen ändern.',
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton(
                                onPressed: _busy
                                    ? null
                                    : (_needsSettingsStep
                                          ? _openSettings
                                          : _acceptPermission),
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
                                    : Text(
                                        // Apple 5.1.1(iv): VOR der System-Anfrage
                                        // darf der Button den Nutzer NICHT zu einer
                                        // Auswahl drängen („Immer erlauben"). Neutral
                                        // „Weiter" → führt nur zur echten iOS-Anfrage.
                                        _needsSettingsStep
                                            ? 'In den Einstellungen öffnen'
                                            : 'Weiter',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                              ),
                            ),
                            // Nur im Einstellungs-Schritt (also NACH dem System-
                            // Dialog, Apple 5.1.1(iv)-konform): ein Ausweg, damit
                            // der Nutzer mit „Beim Verwenden" weiterfahren kann.
                            if (_needsSettingsStep) ...[
                              const SizedBox(height: 6),
                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => Navigator.of(context).pop(true),
                                  child: Text(
                                    'Später, mit „Beim Verwenden" fahren',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
