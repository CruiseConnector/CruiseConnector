import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/app_changelog.dart';
import 'package:cruise_connect/data/services/changelog_service.dart';
import 'package:cruise_connect/presentation/pages/feedback_page.dart';
import 'package:flutter/material.dart';

/// Zeigt nach einem Update, was sich geaendert hat.
///
/// 2026-08-09 (vucko): „Nach jedem Update soll ein Update-Log kommen ... und
/// eine Feedback-Funktion." Beides gehoert zusammen: Wer gerade liest, was neu
/// ist, ist der beste Moment fuer eine Rueckmeldung — deshalb fuehrt der zweite
/// Knopf direkt ins Rueckmeldungs-Formular.
Future<void> showChangelogSheet(
  BuildContext context,
  ChangelogEintrag eintrag,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => _ChangelogSheet(eintrag: eintrag),
  );
}

class _ChangelogSheet extends StatelessWidget {
  const _ChangelogSheet({required this.eintrag});

  final ChangelogEintrag eintrag;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, color: accent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Version ${eintrag.version}',
                      style: TextStyle(
                        color: accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  eintrag.titel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              itemCount: eintrag.punkte.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (_, i) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 7),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      eintrag.punkte[i],
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Alles klar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const FeedbackPage(),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.chat_bubble_outline,
                    size: 18,
                    color: Colors.white70,
                  ),
                  label: const Text(
                    'Etwas dazu sagen',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
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

/// Fuer den Einstellungen-Eintrag: zeigt die Neuerungen der laufenden Version,
/// auch wenn sie schon gesehen wurden.
Future<void> showChangelogAusEinstellungen(BuildContext context) async {
  final eintrag = await ChangelogService.instance.aktuellerEintrag();
  if (!context.mounted) return;
  if (eintrag == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fuer diese Version gibt es keine Notizen.')),
    );
    return;
  }
  await showChangelogSheet(context, eintrag);
}
