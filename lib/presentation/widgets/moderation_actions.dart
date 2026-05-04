import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:provider/provider.dart';

import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/data/services/social_service.dart';

/// Sammelt alle UI-Helfer rund um Melden und Blockieren — wird sowohl von
/// Post-3-Punkte-Menüs als auch vom User-Profil-Menü genutzt, damit die
/// UX überall identisch ist (gleiche Reasons, gleiche Confirmations).
class ModerationActions {
  ModerationActions._();

  /// BottomSheet mit Reasons, optional Freitext-Detail. Submitted via
  /// `submit_content_report` RPC.
  static Future<void> showReportSheet(
    BuildContext context, {
    String? postId,
    String? commentId,
    String? userId,
    String? targetLabel,
  }) async {
    final detailsController = TextEditingController();
    String? selected;
    bool submitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[600],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      targetLabel != null
                          ? '$targetLabel melden'
                          : 'Inhalt melden',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Wähle einen Grund. Unsere Moderation prüft die Meldung.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                  ...SocialService.reportReasons.entries.map(
                    (e) => RadioListTile<String>(
                      value: e.key,
                      groupValue: selected,
                      onChanged: submitting
                          ? null
                          : (v) => setSheetState(() => selected = v),
                      title: Text(
                        e.value,
                        style: const TextStyle(color: Colors.white),
                      ),
                      activeColor: AppAccentColors.accent,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: detailsController,
                    maxLines: 3,
                    maxLength: 280,
                    enabled: !submitting,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Optional: weitere Details…',
                      hintStyle: TextStyle(
                        color: Colors.grey.withValues(alpha: 0.6),
                      ),
                      counterStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF0B0E14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (selected == null || submitting)
                          ? null
                          : () async {
                              setSheetState(() => submitting = true);
                              try {
                                await SocialService.submitReport(
                                  reason: selected!,
                                  postId: postId,
                                  commentId: commentId,
                                  reportedUserId: userId,
                                  details: detailsController.text.trim().isEmpty
                                      ? null
                                      : detailsController.text.trim(),
                                );
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Meldung gesendet. Danke für deinen Hinweis.',
                                      ),
                                      backgroundColor: Color(0xFF1C1F26),
                                    ),
                                  );
                                }
                              } catch (e) {
                                setSheetState(() => submitting = false);
                                if (sheetContext.mounted) {
                                  ScaffoldMessenger.of(
                                    sheetContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Senden fehlgeschlagen: $e',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppAccentColors.accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Meldung senden',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Bestätigungs-Dialog vor dem Blockieren. Folgt nach `Ja` direkt mit
  /// dem Provider-Call (optimistic), zeigt SnackBar bei Erfolg/Fehler.
  static Future<bool> confirmAndBlock(
    BuildContext context, {
    required String userId,
    required String username,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: Text(
          '@$username blockieren?',
          style: const TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Ihr seht euch gegenseitig keine Posts mehr und folgt euch nicht '
          'mehr. Du kannst die Blockierung jederzeit unter "Blockierte Nutzer" '
          'aufheben.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Abbrechen',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Blockieren',
              style: TextStyle(
                color: AppAccentColors.accent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    if (!context.mounted) return false;
    try {
      await context.read<CommunityProvider>().blockUser(userId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('@$username blockiert'),
            backgroundColor: const Color(0xFF1C1F26),
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Blockieren fehlgeschlagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }
}
