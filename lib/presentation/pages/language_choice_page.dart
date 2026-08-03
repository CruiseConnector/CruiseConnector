// Sprachwahl beim allerersten App-Start (2026-08-03, vucko).
//
// Erscheint genau EINMAL — danach merkt sich die App die Wahl. Ändern geht über
// Einstellungen → App-Einstellungen → Sprache.
//
// Vorbelegt ist die Geräte-Sprache: Wer sein Handy auf Englisch hat, sieht den
// Screen bereits auf Englisch und muss nur bestätigen.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/app_locale_provider.dart';
import 'package:cruise_connect/core/l10n_extension.dart';

const _background = Color(0xFF0D141E);
const _surface = Color(0xFF151E2A);
const _border = Color(0xFF344156);
const _textMuted = Color(0xFFB6BECC);
const _brandMarkAsset = 'assets/branding/cruiseconnect_icon_foreground.png';

class LanguageChoicePage extends StatelessWidget {
  const LanguageChoicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<AppLocaleProvider>();
    final accent = AppAccentColors.accent;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    height: 96,
                    width: 190,
                    decoration: BoxDecoration(
                      color: Color.lerp(_surface, accent, 0.10),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.26),
                      ),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 140,
                        height: 58,
                        child: Image.asset(
                          _brandMarkAsset,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  l10n.languageChoiceTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.languageChoiceSubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 30),

                for (final language in AppLanguage.values) ...[
                  _LanguageCard(
                    language: language,
                    isSelected: localeProvider.language == language,
                    isSystemSuggestion:
                        AppLocaleProvider.systemSuggestion() == language,
                    systemHint: l10n.languageSystemHint,
                    // Vorschau: Sprache sofort umstellen, aber NICHT als
                    // getroffene Wahl markieren — erst „Weiter" schliesst ab.
                    onTap: () => context.read<AppLocaleProvider>().setLanguage(
                      language,
                      markChosen: false,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                const SizedBox(height: 18),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => context
                        .read<AppLocaleProvider>()
                        .setLanguage(localeProvider.language),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      elevation: 5,
                      shadowColor: accent.withValues(alpha: 0.28),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      l10n.languageChoiceContinue,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.language,
    required this.isSelected,
    required this.isSystemSuggestion,
    required this.systemHint,
    required this.onTap,
  });

  final AppLanguage language;
  final bool isSelected;
  final bool isSystemSuggestion;
  final String systemHint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.15)
              : _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? accent : _border,
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    language.label,
                    style: TextStyle(
                      color: isSelected ? accent : Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (isSystemSuggestion) ...[
                    const SizedBox(height: 4),
                    Text(
                      systemHint,
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected ? accent : _border,
            ),
          ],
        ),
      ),
    );
  }
}
