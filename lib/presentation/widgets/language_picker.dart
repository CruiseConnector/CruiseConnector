// Sprachumschaltung aus den Einstellungen (2026-08-03, vucko).
//
// Gleiche Machart wie showAccentColorPicker — Bottom-Sheet, Auswahl wirkt
// sofort, Sheet schliesst danach. Der Wechsel greift ohne Neustart, weil die
// MaterialApp am AppLocaleProvider hängt.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/app_locale_provider.dart';
import 'package:cruise_connect/core/l10n_extension.dart';

Future<void> showLanguagePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1C1F26),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Consumer<AppLocaleProvider>(
            builder: (context, localeProvider, _) {
              final accent = AppAccentColors.accent;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.settingsLanguage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.settingsLanguageSubtitle,
                    style: const TextStyle(
                      color: Color(0xFFA0AEC0),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final language in AppLanguage.values)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        language.label,
                        style: TextStyle(
                          color: localeProvider.language == language
                              ? accent
                              : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Icon(
                        localeProvider.language == language
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: localeProvider.language == language
                            ? accent
                            : Colors.grey,
                      ),
                      onTap: () async {
                        await context.read<AppLocaleProvider>().setLanguage(
                          language,
                        );
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}
