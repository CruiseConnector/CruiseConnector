import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

/// WhatsApp-artiger Emoji-Picker als Bottom-Sheet für Chat-Reaktionen.
///
/// 2026-07-23 (vucko „wie bei WhatsApp, nicht in Tastaturform umtun"): Vorher
/// öffnete ein Dialog mit einem TextField — das brachte die normale
/// System-Tastatur, die der Nutzer jederzeit auf Buchstaben umschalten
/// konnte. Dieses Widget zeigt stattdessen NUR das Emoji-Raster von
/// emoji_picker_flutter (kein Text-Eingabefeld, kein Tastatur-Umschalter) —
/// exakt wie WhatsApps Reaktions-Picker. Wird von community_chat_detail_page
/// und group_chat_panel gleichermaßen genutzt.
Future<String?> showChatEmojiPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF151821),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 6),
            EmojiPicker(
              onEmojiSelected: (category, emoji) {
                Navigator.pop(sheetContext, emoji.emoji);
              },
              config: const Config(
                height: 320,
                emojiViewConfig: EmojiViewConfig(
                  backgroundColor: Color(0xFF151821),
                  columns: 8,
                  emojiSizeMax: 30,
                ),
                categoryViewConfig: CategoryViewConfig(
                  backgroundColor: Color(0xFF1C1F26),
                  indicatorColor: Color(0xFFFF4438),
                  iconColorSelected: Color(0xFFFF4438),
                  iconColor: Colors.white54,
                  dividerColor: Colors.transparent,
                ),
                bottomActionBarConfig: BottomActionBarConfig(
                  backgroundColor: Color(0xFF1C1F26),
                  buttonColor: Color(0xFF1C1F26),
                  buttonIconColor: Colors.white54,
                ),
                searchViewConfig: SearchViewConfig(
                  backgroundColor: Color(0xFF1C1F26),
                  buttonIconColor: Colors.white54,
                  hintText: 'Emoji suchen',
                  hintTextStyle: TextStyle(color: Colors.white38),
                  inputTextStyle: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
