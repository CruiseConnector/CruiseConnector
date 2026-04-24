import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/saved_routes_cache_service.dart';

/// Wrapper um Supabase Auth — Login, Registrierung, Abmelden.
class AuthService {
  static SupabaseClient get _db => Supabase.instance.client;

  /// Der aktuell eingeloggte User (null = nicht eingeloggt).
  static User? get currentUser => _db.auth.currentUser;

  /// Stream für Auth-State-Änderungen (Login / Logout).
  static Stream<AuthState> get authStateChanges => _db.auth.onAuthStateChange;

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

    await _db.auth.signUp(
      email: email,
      password: password,
      data: {'username': derivedName},
    );
  }

  // ─── Abmelden ─────────────────────────────────────────────────────────────

  static Future<void> signOut() async {
    await SavedRoutesCacheService.clearAll();
    await _db.auth.signOut();
  }

  // ─── Hilfsmethoden ────────────────────────────────────────────────────────

  /// Lädt den Benutzernamen aus der `profiles` Tabelle.
  /// Gibt null zurück wenn kein User eingeloggt oder DB-Fehler.
  static Future<String?> getUsername() async {
    final userId = currentUser?.id;
    if (userId == null) return null;

    try {
      final data = await _db
          .from('profiles')
          .select('username')
          .eq('id', userId)
          .maybeSingle();

      return data?['username'] as String?;
    } catch (e) {
      return null;
    }
  }
}
