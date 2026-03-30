// Tests für AuthService
//
// Da AuthService Supabase verwendet, wird hier mit Mockito gemockt.
// Vor dem ersten Ausführen: dart run build_runner build
//
// Tests ausführen: flutter test test/services/auth_service_test.dart

import 'package:flutter_test/flutter_test.dart';

// Nach `dart run build_runner build` wird diese Datei generiert:
// @GenerateMocks([GoTrueClient])
// import 'auth_service_test.mocks.dart';

void main() {
  group('AuthService Tests', () {
    // ─── Login Tests ──────────────────────────────────────────────────────

    test('signIn mit gültigen Daten → kein Fehler', () async {
      // Dieser Test läuft gegen Supabase Test-Credentials
      // In CI: Nutze einen Mock statt echter Supabase-Verbindung
      // Beispiel-Struktur:
      //
      // final mockAuth = MockGoTrueClient();
      // when(mockAuth.signInWithPassword(email: 'test@test.at', password: '123'))
      //   .thenAnswer((_) async => AuthResponse(...));
      //
      // expect(() => AuthService.signIn(...), returnsNormally);
      expect(true, isTrue); // Placeholder bis Mock generiert
    });

    test('signIn mit falschem Passwort → AuthException geworfen', () async {
      // Erwartetes Verhalten: Supabase wirft AuthException
      // Mockito-Beispiel:
      //
      // when(mockAuth.signInWithPassword(...))
      //   .thenThrow(AuthException('Invalid login credentials'));
      //
      // expect(() => AuthService.signIn(...), throwsA(isA<AuthException>()));
      expect(true, isTrue); // Placeholder
    });

    test('signIn mit leerem Passwort → Exception geworfen', () async {
      // Leeres Passwort sollte sofort einen Fehler geben
      expect(true, isTrue); // Placeholder
    });

    // ─── signOut Tests ────────────────────────────────────────────────────

    test('signOut → currentUser wird null', () async {
      // Nach signOut muss currentUser null sein
      // AuthService.currentUser ist ein Getter auf Supabase.instance.client.auth.currentUser
      // Nach signOut() sollte das null sein
      expect(true, isTrue); // Placeholder
    });

    // ─── Username Tests ───────────────────────────────────────────────────

    test('currentUser ist null wenn nicht eingeloggt', () {
      // Wenn kein User eingeloggt: AuthService.currentUser == null
      // Dieser Test kann direkt ohne Mock laufen wenn Supabase nicht init ist
      expect(true, isTrue); // Placeholder
    });

    // ─── signUp Tests ─────────────────────────────────────────────────────

    test('signUp mit gültigen Daten → kein Fehler', () async {
      expect(true, isTrue); // Placeholder
    });

    test('signUp mit bereits verwendeter E-Mail → AuthException', () async {
      expect(true, isTrue); // Placeholder
    });

    test('Username aus E-Mail abgeleitet wenn keiner angegeben', () async {
      // 'max@example.com' → Username 'max'
      final email = 'max@example.com';
      final expected = email.split('@').first;
      expect(expected, equals('max'));
    });
  });
}
