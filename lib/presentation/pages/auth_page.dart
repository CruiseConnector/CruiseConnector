import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/presentation/pages/home_page.dart';
import 'package:cruise_connect/presentation/pages/welcome_page.dart';

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
          return const Scaffold(
            backgroundColor: Color(0xFF0B0E14),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFFF3B30)),
            ),
          );
        }

        final session = snapshot.data?.session
            ?? Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return const HomePage();
        }
        return const WelcomePage();
      },
    );
  }
}
