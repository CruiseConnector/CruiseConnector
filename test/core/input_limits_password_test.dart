// Regeln hinter dem Passwort-Reset (2026-08-02, vucko).
//
// Die Validierung liegt bewusst in AppInputLimits und nicht in der UI, damit
// Reset-Seite (ForgotPasswordPage) und Einstellungen (ChangePasswordPage)
// garantiert dieselbe Regel prüfen wie der Server (GoTrue: min. 6 Zeichen).
//
// Ausführen: flutter test test/core/input_limits_password_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/core/input_limits.dart';

void main() {
  group('isValidPassword', () {
    test('zu kurz wird abgelehnt', () {
      expect(AppInputLimits.isValidPassword(''), isFalse);
      expect(AppInputLimits.isValidPassword('12345'), isFalse);
    });

    test('genau die Mindestlaenge wird akzeptiert', () {
      final minimal = 'a' * AppInputLimits.passwordMinLength;
      expect(AppInputLimits.isValidPassword(minimal), isTrue);
    });

    test('Maximallaenge ist die Obergrenze', () {
      final max = 'a' * AppInputLimits.passwordMaxLength;
      final tooLong = 'a' * (AppInputLimits.passwordMaxLength + 1);
      expect(AppInputLimits.isValidPassword(max), isTrue);
      expect(AppInputLimits.isValidPassword(tooLong), isFalse);
    });

    test('Leerzeichen zaehlen mit und werden nicht wegtrimmt', () {
      // '  ab  ' hat 6 Zeichen — wuerde beim Trimmen faelschlich durchfallen,
      // obwohl GoTrue das Passwort so akzeptiert.
      expect(AppInputLimits.isValidPassword('  ab  '), isTrue);
    });
  });

  group('looksLikeEmail', () {
    test('gaengige Adressen werden akzeptiert', () {
      expect(AppInputLimits.looksLikeEmail('max@example.com'), isTrue);
      expect(AppInputLimits.looksLikeEmail('  max@example.com  '), isTrue);
      expect(AppInputLimits.looksLikeEmail('a.b+tag@sub.example.co.uk'), isTrue);
    });

    test('offensichtlicher Muell wird abgelehnt', () {
      expect(AppInputLimits.looksLikeEmail(''), isFalse);
      expect(AppInputLimits.looksLikeEmail('max'), isFalse);
      expect(AppInputLimits.looksLikeEmail('max@'), isFalse);
      expect(AppInputLimits.looksLikeEmail('max@example'), isFalse);
      expect(AppInputLimits.looksLikeEmail('max example@web.de'), isFalse);
      expect(AppInputLimits.looksLikeEmail('a@b@c.de'), isFalse);
    });

    test('ueberlange Adressen werden abgelehnt', () {
      final long = '${'a' * AppInputLimits.emailMaxLength}@example.com';
      expect(AppInputLimits.looksLikeEmail(long), isFalse);
    });
  });
}
