import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cruise_connect/data/services/auth_service.dart';

/// Zentraler Auth-State für die gesamte App.
/// Wird in main.dart als ChangeNotifierProvider eingebunden.
class AuthProvider extends ChangeNotifier {
  User? _currentUser;
  StreamSubscription<AuthState>? _authSub;

  AuthProvider() {
    _currentUser = AuthService.currentUser;
    // Auf Auth-Änderungen (Login / Logout) reagieren
    _authSub = AuthService.authStateChanges.listen((state) {
      _currentUser = state.session?.user;
      notifyListeners();
    });
  }

  /// Aktuell eingeloggter User — null = nicht eingeloggt.
  User? get currentUser => _currentUser;

  /// true = User ist eingeloggt.
  bool get isLoggedIn => _currentUser != null;

  /// Username aus den User-Metadaten.
  String get username =>
      _currentUser?.userMetadata?['username'] as String? ??
      _currentUser?.email?.split('@').first ??
      'Unbekannt';

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
