import 'package:supabase_flutter/supabase_flutter.dart';

/// Wrapper um Supabase Auth — Login, Registrierung, Abmelden.
class AuthService {
  static SupabaseClient get _db => Supabase.instance.client;

  /// Der aktuell eingeloggte User (null = nicht eingeloggt).
  static User? get currentUser => _db.auth.currentUser;

  /// Stream für Auth-State-Änderungen (Login / Logout).
  static Stream<AuthState> get authStateChanges =>
      _db.auth.onAuthStateChange;

  // ─── Login ────────────────────────────────────────────────────────────────

  /// E-Mail + Passwort Login.
  /// Wirft eine [AuthException] oder [Exception] bei Fehler.
  static Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _db.auth.signInWithPassword(email: email, password: password);
  }

  // ─── Registrierung ────────────────────────────────────────────────────────

  /// Neuen Account anlegen. Legt automatisch ein Profil in `profiles` an.
  static Future<void> signUp({
    required String email,
    required String password,
    String? username,
  }) async {
    final derivedName = username?.trim().isNotEmpty == true
        ? username!.trim()
        : email.split('@').first;

    final response = await _db.auth.signUp(
      email: email,
      password: password,
      data: {'username': derivedName},
    );

    // Profil anlegen (Trigger macht das zwar auch, aber als Fallback):
    if (response.user != null) {
      await _db.from('profiles').upsert({
        'id': response.user!.id,
        'email': email,
        'username': derivedName,
      });
    }
  }

  // ─── Abmelden ─────────────────────────────────────────────────────────────

  static Future<void> signOut() async {
    await _db.auth.signOut();
  }

  // ─── Hilfsmethoden ────────────────────────────────────────────────────────

  /// Lädt den Benutzernamen aus der `profiles` Tabelle.
  static Future<String?> getUsername() async {
    final userId = currentUser?.id;
    if (userId == null) return null;

    final data = await _db
        .from('profiles')
        .select('username')
        .eq('id', userId)
        .maybeSingle();

    return data?['username'] as String?;
  }
}
