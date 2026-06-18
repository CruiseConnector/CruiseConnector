import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/saved_routes_cache_service.dart';

/// Wrapper um Supabase Auth: Login, Registrierung, Social Login und Abmelden.
class AuthService {
  static SupabaseClient get _db => Supabase.instance.client;

  static const String authCallbackUrl = 'cruiseconnect://auth/callback';

  static Future<void>? _googleInitFuture;

  /// Der aktuell eingeloggte User (null = nicht eingeloggt).
  static User? get currentUser => _db.auth.currentUser;

  /// Stream fuer Auth-State-Aenderungen (Login / Logout).
  static Stream<AuthState> get authStateChanges => _db.auth.onAuthStateChange;

  /// E-Mail + Passwort Login.
  /// Wirft eine [AuthException] oder [Exception] bei Fehler.
  static Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _db.auth.signInWithPassword(email: email, password: password);
    await ensureCurrentUserProfile();
  }

  /// Neuen Account anlegen. Supabase sendet dabei die Verification-Mail.
  static Future<void> signUp({
    required String email,
    required String password,
    String? username,
  }) async {
    final rawName = username?.trim().isNotEmpty == true
        ? username!.trim()
        : AppInputLimits.normalizeUsernameFallback(email.split('@').first);
    if (!AppInputLimits.isValidUsername(rawName)) {
      throw ArgumentError(
        'Username muss 3-${AppInputLimits.usernameMaxLength} Zeichen haben '
        'und darf nur Buchstaben, Zahlen und _ enthalten.',
      );
    }

    final response = await _db.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: authCallbackUrl,
      data: {'username': rawName},
    );
    if (response.session != null) {
      await ensureCurrentUserProfile();
    }
  }

  /// Sendet die Signup-Bestaetigung erneut.
  static Future<void> resendVerificationEmail(String email) async {
    await _db.auth.resend(
      email: email.trim(),
      type: OtpType.signup,
      emailRedirectTo: authCallbackUrl,
    );
  }

  /// Native Google-Anmeldung auf Android/iOS. Auf Web/Desktop faellt es auf
  /// Supabase OAuth mit Redirect zurueck.
  static Future<void> signInWithGoogle() async {
    final webClientId = AppConstants.googleWebClientId.trim();
    final iosClientId = AppConstants.googleIosClientId.trim();
    final onMobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final onIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (onMobile && webClientId.isEmpty) {
      throw const AuthException(
        'Google Login ist noch nicht konfiguriert (Web Client ID fehlt).',
      );
    }
    if (onIos && iosClientId.isEmpty) {
      throw const AuthException(
        'Google Login ist noch nicht konfiguriert (iOS Client ID fehlt).',
      );
    }
    final canUseNative =
        onMobile && GoogleSignIn.instance.supportsAuthenticate();

    if (!canUseNative) {
      await _startOAuthSignIn(OAuthProvider.google, scopes: 'email profile');
      return;
    }

    await _ensureGoogleInitialized();

    try {
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final authorization = await googleUser.authorizationClient
          .authorizationForScopes(const <String>['email', 'profile']);
      final idToken = googleAuth.idToken;
      final accessToken = authorization?.accessToken;

      if (idToken == null) {
        throw const AuthException('Google hat kein ID Token geliefert.');
      }

      await _db.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      await ensureCurrentUserProfile();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw const AuthException('Google Anmeldung abgebrochen.');
      }
      throw AuthException(e.description ?? 'Google Anmeldung fehlgeschlagen.');
    }
  }

  /// Native Apple-Anmeldung auf iOS/macOS. Andere Plattformen nutzen Supabase
  /// OAuth und kommen ueber den Auth-Deep-Link zurueck in die App.
  static Future<void> signInWithApple() async {
    final isApplePlatform =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    if (!isApplePlatform) {
      await _startOAuthSignIn(OAuthProvider.apple, scopes: 'email name');
      return;
    }

    final isAvailable = await SignInWithApple.isAvailable();
    if (!isAvailable) {
      throw const AuthException(
        'Apple Anmeldung ist auf diesem Geraet nicht verfuegbar.',
      );
    }

    final rawNonce = _db.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AuthException('Apple hat kein ID Token geliefert.');
      }

      await _db.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      await _saveAppleDisplayName(credential);
      await ensureCurrentUserProfile();
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AuthException('Apple Anmeldung abgebrochen.');
      }
      throw AuthException(e.message);
    } on SignInWithAppleException catch (e) {
      throw AuthException(e.toString());
    }
  }

  // ── Konto-Verknüpfung (mehrere Anmeldeoptionen pro Account) ───────────────
  // 2026-06-16 (vucko): Ein Account, mehrere Login-Wege. Supabase verknüpft
  // Identitäten per linkIdentityWithIdToken (nativer idToken-Flow). Voraussetzung
  // im Supabase-Dashboard: „Manual linking" muss aktiviert sein, sonst kommt ein
  // klarer Fehler zurück (wird in der UI angezeigt). Apple läuft nativ sofort;
  // Google braucht zusätzlich die iOS-Client-ID (sonst sauberer Hinweis).

  /// Alle mit dem aktuellen Account verknüpften Identitäten (email/google/apple).
  static Future<List<UserIdentity>> linkedIdentities() async {
    try {
      return await _db.auth.getUserIdentities();
    } catch (_) {
      return _db.auth.currentUser?.identities ?? const <UserIdentity>[];
    }
  }

  /// Ob ein bestimmter Provider bereits verknüpft ist.
  static bool hasProvider(List<UserIdentity> identities, String provider) =>
      identities.any((i) => i.provider == provider);

  /// Apple mit dem aktuellen Account verknüpfen (nativ, iOS/macOS).
  static Future<void> linkApple() async {
    final isApplePlatform =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (!isApplePlatform || !await SignInWithApple.isAvailable()) {
      throw const AuthException(
        'Apple-Verbinden ist auf diesem Gerät nicht verfügbar.',
      );
    }
    final rawNonce = _db.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AuthException('Apple hat kein ID Token geliefert.');
      }
      await _db.auth.linkIdentityWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      await _saveAppleDisplayName(credential);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AuthException('Apple-Verbinden abgebrochen.');
      }
      throw AuthException(e.message);
    }
  }

  /// Google mit dem aktuellen Account verknüpfen (nativ, braucht iOS-Client-ID).
  static Future<void> linkGoogle() async {
    final webClientId = AppConstants.googleWebClientId.trim();
    final iosClientId = AppConstants.googleIosClientId.trim();
    final onIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    if (webClientId.isEmpty || (onIos && iosClientId.isEmpty)) {
      throw const AuthException(
        'Google-Verbinden ist noch nicht konfiguriert (iOS-Client-ID fehlt).',
      );
    }
    await _ensureGoogleInitialized();
    try {
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final authorization = await googleUser.authorizationClient
          .authorizationForScopes(const <String>['email', 'profile']);
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw const AuthException('Google hat kein ID Token geliefert.');
      }
      await _db.auth.linkIdentityWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization?.accessToken,
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw const AuthException('Google-Verbinden abgebrochen.');
      }
      throw AuthException(e.description ?? 'Google-Verbinden fehlgeschlagen.');
    }
  }

  /// Eine verknüpfte Identität wieder entfernen (nie die letzte — Supabase
  /// verweigert das Trennen der einzigen verbleibenden Identität).
  static Future<void> unlinkProvider(UserIdentity identity) async {
    await _db.auth.unlinkIdentity(identity);
  }

  static Future<void> signOut() async {
    await SavedRoutesCacheService.clearAll();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Google kann ungeinitialisiert sein; Supabase-Logout bleibt fuehrend.
    }
    await _db.auth.signOut();
  }

  /// Deletes the signed-in user's full account via a restricted Supabase RPC.
  static Future<void> deleteCurrentAccount() async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException('Kein User ist eingeloggt.');
    }

    try {
      await _db
          .rpc('delete_current_user')
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException(
              'Account deletion timed out while contacting Supabase.',
            ),
          );
    } on PostgrestException catch (e, stack) {
      debugPrint(
        '[AuthService] delete_current_user failed: '
        'message=${e.message}, code=${e.code}, details=${e.details}, '
        'hint=${e.hint}\n$stack',
      );
      rethrow;
    } catch (e, stack) {
      debugPrint('[AuthService] delete_current_user failed: $e\n$stack');
      rethrow;
    }
    await SavedRoutesCacheService.clearAll();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Google can be uninitialized or not linked to this session.
    }
    try {
      await _db.auth.signOut();
    } catch (_) {
      // The auth user is already gone; local session cleanup is best effort.
    }
  }

  /// Legt nach Social Login ein Profil an, falls der DB-Trigger wegen alter
  /// Daten oder Provider-Metadaten keines erzeugt hat.
  static Future<void> ensureCurrentUserProfile() async {
    final user = currentUser;
    if (user == null) return;

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final rawUsername =
        _stringMeta(metadata, 'username') ??
        _stringMeta(metadata, 'preferred_username') ??
        _stringMeta(metadata, 'name') ??
        user.email?.split('@').first ??
        'cruiser';
    final username = _safeUsername(rawUsername, fallbackId: user.id);

    try {
      await _db
          .from('profiles')
          .upsert(
            {'id': user.id, 'email': user.email, 'username': username},
            onConflict: 'id',
            ignoreDuplicates: true,
          );
    } catch (e) {
      debugPrint('[AuthService] Profil konnte nicht sichergestellt werden: $e');
    }
  }

  /// Laedt den Benutzernamen aus der `profiles` Tabelle.
  /// Gibt null zurueck wenn kein User eingeloggt oder DB-Fehler.
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

  static Future<void> _ensureGoogleInitialized() {
    final webClientId = AppConstants.googleWebClientId.trim();
    final iosClientId = AppConstants.googleIosClientId.trim();
    final clientId =
        defaultTargetPlatform == TargetPlatform.iOS && iosClientId.isNotEmpty
        ? iosClientId
        : null;

    return _googleInitFuture ??= GoogleSignIn.instance.initialize(
      clientId: clientId,
      serverClientId: webClientId,
    );
  }

  static Future<void> _startOAuthSignIn(
    OAuthProvider provider, {
    String? scopes,
  }) async {
    final launched = await _db.auth.signInWithOAuth(
      provider,
      redirectTo: kIsWeb ? null : authCallbackUrl,
      scopes: scopes,
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
    if (!launched) {
      throw const AuthException(
        'Anmeldung konnte nicht geoeffnet werden. Bitte erneut versuchen.',
      );
    }
  }

  static Future<void> _saveAppleDisplayName(
    AuthorizationCredentialAppleID credential,
  ) async {
    final givenName = credential.givenName?.trim();
    final familyName = credential.familyName?.trim();
    final fullName = [
      if (givenName != null && givenName.isNotEmpty) givenName,
      if (familyName != null && familyName.isNotEmpty) familyName,
    ].join(' ').trim();

    if (fullName.isEmpty) return;

    await _db.auth.updateUser(
      UserAttributes(
        data: {
          'full_name': fullName,
          'name': fullName,
          if (givenName != null && givenName.isNotEmpty)
            'given_name': givenName,
          if (familyName != null && familyName.isNotEmpty)
            'family_name': familyName,
        },
      ),
    );
  }

  static String? _stringMeta(Map<String, dynamic> metadata, String key) {
    final value = metadata[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  static String _safeUsername(String raw, {required String fallbackId}) {
    var normalized = raw
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (normalized.length > AppInputLimits.usernameMaxLength) {
      normalized = normalized.substring(0, AppInputLimits.usernameMaxLength);
    }
    if (AppInputLimits.isValidUsername(normalized)) {
      return normalized;
    }
    final suffix = fallbackId.replaceAll('-', '');
    return 'cruiser_${suffix.substring(0, 8)}';
  }
}
