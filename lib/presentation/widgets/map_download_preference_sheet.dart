import 'dart:ui' as ui;

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/map_style_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<MapAutoDownloadPolicy?> showMapDownloadPreferenceSheet(
  BuildContext context, {
  bool force = false,
}) async {
  if (!force && await MapStyleService.instance.hasSeenAutoDownloadPrompt()) {
    return MapStyleService.instance.autoDownloadPolicy;
  }
  if (!context.mounted) return null;

  final selected = await showModalBottomSheet<MapAutoDownloadPolicy>(
    context: context,
    isScrollControlled: true,
    isDismissible: force,
    enableDrag: force,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => const MapDownloadPreferenceSheet(),
  );
  return selected;
}

class MapDownloadPreferenceSheet extends StatefulWidget {
  const MapDownloadPreferenceSheet({super.key});

  @override
  State<MapDownloadPreferenceSheet> createState() =>
      _MapDownloadPreferenceSheetState();
}

class _MapDownloadPreferenceSheetState
    extends State<MapDownloadPreferenceSheet> {
  MapAutoDownloadPolicy _policy = MapAutoDownloadPolicy.wifiOnly;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _policy = MapStyleService.instance.autoDownloadPolicy;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await MapStyleService.instance.setAutoDownloadPolicy(_policy);
    await MapStyleService.instance.markAutoDownloadPromptSeen();
    // 2026-08-28 (Fehler 11): "Keine Offlinekarte" heisst genau das — es
    // wird kein Download angestossen. Nur eine zustimmende Wahl startet ihn.
    if (_policy != MapAutoDownloadPolicy.aus) {
      MapStyleService.instance.ensureAutoDownloadScheduled(
        reason: _policy == MapAutoDownloadPolicy.wifiOnly
            ? 'map_preference_wifi'
            : 'map_preference_mobile_allowed',
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(_policy);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final media = MediaQuery.of(context);
    // 2026-08-28 (Fehler 11): etwas hoeher, seit die dritte Karte und der
    // laengere Erklaertext dazukamen; die Kartenliste scrollt zur Not.
    final height = (media.size.height * 0.72).clamp(520.0, 640.0).toDouble();

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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
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
                            const SizedBox(height: 18),
                            Icon(
                              CupertinoIcons.map_fill,
                              color: accent,
                              size: 34,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Offlinekarte laden',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              // 2026-08-28 (Fehler 11): Das Blatt kommt jetzt
                              // beim ersten App-Start und muss ALLES sagen:
                              // was geladen wird, wie gross es ist, dass nur
                              // der deutschsprachige Raum gemeint ist, und
                              // dass ohne Zustimmung nichts passiert.
                              'Cruise Connector kann die Straßenkarte für Österreich, Deutschland und die Schweiz einmalig aufs Handy laden. Damit bleibt die Karte auch ohne Empfang gestochen scharf. Die Datei ist mehrere GB groß. Ohne deine Zustimmung wird nichts heruntergeladen, und du kannst deine Wahl in den Einstellungen jederzeit ändern.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.70),
                                fontSize: 14,
                                height: 1.34,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                _PolicyCard(
                                  selected:
                                      _policy == MapAutoDownloadPolicy.wifiOnly,
                                  accent: accent,
                                  icon: CupertinoIcons.wifi,
                                  title: 'Nur im WLAN',
                                  body:
                                      'Empfohlen. Lädt automatisch, sobald WLAN verfügbar ist.',
                                  onTap: () => setState(
                                    () => _policy =
                                        MapAutoDownloadPolicy.wifiOnly,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _PolicyCard(
                                  selected:
                                      _policy ==
                                      MapAutoDownloadPolicy.wifiAndMobile,
                                  accent: accent,
                                  icon: CupertinoIcons
                                      .antenna_radiowaves_left_right,
                                  title: 'WLAN & mobile Daten',
                                  body:
                                      'Startet auch über Mobilfunk. Kann viel Datenvolumen verbrauchen.',
                                  onTap: () => setState(
                                    () => _policy =
                                        MapAutoDownloadPolicy.wifiAndMobile,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                // 2026-08-28 (Fehler 11): die echte Wahl,
                                // NEIN zu sagen. Ohne sie war das Blatt nur
                                // die Frage, WIE geladen wird, nicht OB.
                                _PolicyCard(
                                  selected:
                                      _policy == MapAutoDownloadPolicy.aus,
                                  accent: accent,
                                  icon: CupertinoIcons.xmark_circle,
                                  title: 'Keine Offlinekarte',
                                  body:
                                      'Nichts wird heruntergeladen. Die Karte lädt wie gewohnt über das Internet.',
                                  onTap: () => setState(
                                    () =>
                                        _policy = MapAutoDownloadPolicy.aus,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                          child: SizedBox(
                            height: 54,
                            child: FilledButton(
                              onPressed: _saving ? null : _save,
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(22),
                                ),
                              ),
                              child: _saving
                                  ? const CupertinoActivityIndicator(
                                      color: Colors.white,
                                    )
                                  : const Text(
                                      'Speichern',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
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
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({
    required this.selected,
    required this.accent,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final bool selected;
  final Color accent;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.72)
                  : Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? accent : Colors.white70, size: 27),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.64),
                        fontSize: 12.4,
                        height: 1.28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                color: selected ? accent : Colors.white.withValues(alpha: 0.34),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
