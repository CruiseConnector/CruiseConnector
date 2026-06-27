// 2026-06-27 (vucko) — Entscheidet nach erfolgreicher Anmeldung, ob der
// Onboarding-Wizard kommt (neuer Account: profiles.onboarding_completed=false)
// oder direkt die App (HomePage). Bestehende User (Login) sind als onboarded
// markiert => sofort HomePage. EIN zentraler Entscheidungspunkt für alle
// Auth-Einstiege (Registrierung, Login, Google/Apple, Session-Restore).

import 'package:cruise_connect/data/services/map_style_service.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/home_page.dart';
import 'package:cruise_connect/presentation/pages/onboarding/onboarding_wizard_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class PostAuthGate extends StatefulWidget {
  const PostAuthGate({super.key});

  @override
  State<PostAuthGate> createState() => _PostAuthGateState();
}

class _PostAuthGateState extends State<PostAuthGate> {
  late final Future<bool> _needs = SocialService.needsOnboarding();

  @override
  void initState() {
    super.initState();
    // Offline-Karte nach Login/Registrierung/Session-Restore automatisch laden,
    // falls noch nicht vorhanden (nur WLAN, idempotent, im Hintergrund). Startet
    // früher als der Home-Prewarm, damit die Karte direkt nach dem Anmelden lädt.
    if (!kIsWeb) {
      MapStyleService.instance.ensureAutoDownloadScheduled(reason: 'post_auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _needs,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Color(0xFF0B0E14),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6A2C)),
            ),
          );
        }
        // Bei Fehler/false => App (defensiv: Onboarding nie erzwingen, wenn
        // unklar; der Wizard ist nur für eindeutig neue Accounts).
        return snap.data == true
            ? const OnboardingWizardPage()
            : const HomePage();
      },
    );
  }
}
