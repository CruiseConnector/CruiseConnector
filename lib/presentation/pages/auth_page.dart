import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/presentation/pages/legal_gate_page.dart';
import 'package:cruise_connect/presentation/pages/onboarding/post_auth_gate.dart';
import 'package:cruise_connect/presentation/pages/welcome_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Entscheidet anhand des Supabase-Auth-Streams ob Login- oder Home-Screen
/// angezeigt wird.
class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Während des ersten Ladens kurz warten
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: const Color(0xFF0B0E14),
            body: Center(
              child: CircularProgressIndicator(color: AppAccentColors.accent),
            ),
          );
        }

        final session =
            snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return const LegalGatePage(child: PostAuthGate());
        }
        return const WelcomePage();
      },
    );
  }
}
