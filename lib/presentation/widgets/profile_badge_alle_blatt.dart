import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/presentation/widgets/badge_stufen_stil.dart';
import 'package:cruise_connect/presentation/widgets/profile_badge_showcase.dart';

/// Alle Abzeichen einer Person auf einen Blick.
///
/// 2026-09-01 (Vucko: „ganz wichtig moechte ich das die badges bei einem
/// Profil besser angezeigt werden"):
///
/// Auf dem Titelbild liegen hoechstens FUENF Aufkleber. Auf dem eigenen Profil
/// kam man ueber den Auswertungs-Reiter an den Rest — auf einem FREMDEN Profil
/// gar nicht. Wer zwoelf Abzeichen hat, zeigte davon fuenf und der Rest war
/// unsichtbar.
///
/// Dieses Blatt zeigt alle, nach Stufe geordnet, und jedes ist antippbar.
Future<void> zeigeAlleAbzeichen(
  BuildContext context, {
  required Map<String, dynamic> profile,
  required String name,
}) {
  final ids = ProfileBadgeShowcase.badgeIdsFromProfile(profile);
  final abzeichen = <app.Badge>[
    for (final id in ids)
      if (app.Badge.getById(id) != null) app.Badge.getById(id)!,
  ]..sort((a, b) => a.id.compareTo(b.id));
  final seitWann = ProfileBadgeShowcase.memberSinceFromProfile(profile);

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF11151D),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (blattKontext) {
      final accent = AppAccentColors.accent;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                abzeichen.length == 1
                    ? 'Ein Abzeichen von $name'
                    : '${abzeichen.length} Abzeichen von $name',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              if (abzeichen.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Hier stehen die Abzeichen, sobald welche dazukommen.',
                    style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 14),
                  ),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 16,
                      children: [
                        for (final b in abzeichen)
                          _AbzeichenKachel(
                            abzeichen: b,
                            accent: accent,
                            onTap: () => ProfileBadgeShowcase.showBadgeDetails(
                              blattKontext,
                              b,
                              memberSince: seitWann,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _AbzeichenKachel extends StatelessWidget {
  const _AbzeichenKachel({
    required this.abzeichen,
    required this.accent,
    required this.onTap,
  });

  final app.Badge abzeichen;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BadgeStufenEmblem(
                stufe: abzeichen.stufe,
                groesse: 54,
                freigeschaltet: true,
                child: abzeichen.assetPath == null
                    ? Icon(Icons.emoji_events_rounded, color: accent, size: 26)
                    : Image.asset(
                        abzeichen.assetPath!,
                        width: 34,
                        height: 34,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.emoji_events_rounded,
                          color: accent,
                          size: 26,
                        ),
                      ),
              ),
              const SizedBox(height: 6),
              Text(
                abzeichen.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 11,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
