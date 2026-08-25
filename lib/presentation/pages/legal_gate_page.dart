import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/legal_acceptance_service.dart';
import 'package:cruise_connect/presentation/pages/legal_acceptance_page.dart';

class LegalGatePage extends StatefulWidget {
  const LegalGatePage({
    super.key,
    required this.child,
    this.source = 'app_onboarding',
    this.onExit,
  });

  final Widget child;
  final String source;

  /// Ausweg, wenn das Tor nicht durchschritten werden kann. Ohne Angabe:
  /// abmelden und zurueck zum Start. Nur Tests reichen hier etwas herein.
  final Future<void> Function(BuildContext context)? onExit;

  @override
  State<LegalGatePage> createState() => _LegalGatePageState();
}

class _LegalGatePageState extends State<LegalGatePage> {
  late Future<bool> _acceptedFuture;

  @override
  void initState() {
    super.initState();
    _acceptedFuture = _loadAcceptanceState();
  }

  Future<bool> _loadAcceptanceState() {
    // 2026-07-10 (vucko „AGB-Fenster kam zweimal"): Der Check läuft jetzt
    // zentral + prozessweit dedupliziert im Service. Mehrere gleichzeitig
    // entstehende Gates (AuthPage-StreamBuilder + pushAndRemoveUntil aus
    // login/welcome/main) teilen sich EIN Ergebnis, statt sich gegenseitig
    // das Pre-Auth-Pending wegzuräumen und das Fenster erneut zu zeigen.
    // DB-Fehler landen im Fehler-Screen mit Retry statt im Doppel-Fenster.
    return LegalAcceptanceService.ensureAcceptedOrPending(
      source: widget.source,
    );
  }

  void _markAccepted() {
    setState(() {
      _acceptedFuture = Future<bool>.value(true);
    });
  }

  void _retry() {
    setState(() {
      _acceptedFuture = _loadAcceptanceState();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _acceptedFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: const Color(0xFF0B0E14),
            body: Center(
              child: CircularProgressIndicator(color: AppAccentColors.accent),
            ),
          );
        }

        if (snapshot.hasError) {
          return LegalGateErrorScreen(onRetry: _retry, onExit: widget.onExit);
        }

        if (snapshot.data == true) {
          return widget.child;
        }

        return LegalAcceptancePage(
          source: widget.source,
          persistAcceptance: true,
          canGoBack: false,
          onAccepted: _markAccepted,
          onExit: widget.onExit,
        );
      },
    );
  }
}

/// 2026-07-21 (Vorfall „Rechtliches konnte nicht geprueft werden"): Dieser
/// Bildschirm laeuft VOR jedem Login/Onboarding. Damals fehlte die
/// `legal_acceptances`-Migration in der Prod-Datenbank — die Pruefung warf,
/// und der einzige Knopf war „Erneut versuchen". Erneut versuchen half nicht,
/// weil der Fehler nicht am Geraet lag: alle Nutzer standen fest. Deshalb hat
/// dieser Bildschirm ab 2026-08-24 ZWEI Knoepfe.
///
/// Oeffentlich, damit der Regressionstest ihn ohne Supabase pumpen kann.
class LegalGateErrorScreen extends StatelessWidget {
  const LegalGateErrorScreen({super.key, required this.onRetry, this.onExit});

  final VoidCallback onRetry;
  final Future<void> Function(BuildContext context)? onExit;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFFFB4B4),
                  size: 42,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Rechtliches konnte nicht geprüft werden.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Bitte prüfe die Verbindung oder ob die Migration für die Rechtstexte in Supabase schon eingespielt ist.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFB6BECC), height: 1.35),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Erneut versuchen'),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => (onExit ?? abmeldenUndZumStart)(context),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFB6BECC),
                  ),
                  child: const Text('Abmelden und zurück zum Start'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
