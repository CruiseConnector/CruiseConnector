import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Blockierender Update-Screen. Kein Weg vorbei — genau das ist der Sinn.
///
/// 2026-08-10 (vucko): „bevor sie in die App reingehen koennen." Deshalb kein
/// „Spaeter"-Knopf, und der Zurueck-Wisch ist gesperrt (PopScope).
class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({super.key, this.storeUrl, this.nachricht});

  final String? storeUrl;
  final String? nachricht;

  Future<void> _oeffneStore(BuildContext context) async {
    // Der richtige Store-Link kommt aus der Datenbank (je Plattform gepflegt).
    // Fallback nur fuer den seltenen Null-Fall: die echte Play-Store-Adresse
    // (Android ist die einzige Plattform, die dieses Gate aktuell erzwingt).
    final url = storeUrl ??
        'https://play.google.com/store/apps/details?id=com.vucko.cruiserconnect';
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Store konnte nicht geoeffnet werden.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Store konnte nicht geoeffnet werden.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D141E),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.system_update_alt_rounded,
                      color: accent,
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Neue Version verfuegbar',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    nachricht ??
                        'Um Cruise Connector weiter zu nutzen, aktualisiere bitte '
                            'auf die neueste Version. Es dauert nur einen Moment.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => _oeffneStore(context),
                      child: const Text(
                        'Jetzt aktualisieren',
                        style: TextStyle(
                          fontSize: 16,
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
      ),
    );
  }
}
