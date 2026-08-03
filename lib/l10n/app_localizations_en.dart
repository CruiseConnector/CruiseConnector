// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get languageChoiceTitle => 'Choose your language';

  @override
  String get languageChoiceSubtitle =>
      'Which language would you like to use Cruise Connector in? You can change this any time in the settings.';

  @override
  String get languageChoiceContinue => 'Continue';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageSystemHint => 'Suggested based on your device language';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSubtitle => 'App language';

  @override
  String get welcomeTitle => 'Welcome back!';

  @override
  String get welcomeCreateAccount => 'Create account';

  @override
  String get welcomeOrContinueWith => 'or continue with';

  @override
  String get loginTitle => 'Welcome back';

  @override
  String get loginSubtitle => 'Sign in to continue';

  @override
  String get loginNoAccountPrefix => 'No account yet? ';

  @override
  String get loginRegisterNow => 'Sign up now';

  @override
  String get loginResendVerification => 'Resend email';

  @override
  String loginVerificationResent(String email) {
    return 'Confirmation email sent to $email again.';
  }

  @override
  String get loginResendFailed =>
      'The email could not be sent again. Please wait a moment.';

  @override
  String get loginErrorMissingFields => 'Please enter your email and password.';

  @override
  String get loginErrorEmailMissing => 'Please enter your email address.';

  @override
  String get loginErrorInvalidCredentials => 'Wrong email or password.';

  @override
  String get loginErrorEmailNotConfirmed =>
      'Please confirm your email address first.';

  @override
  String get loginErrorFailed => 'Sign-in failed. Please try again.';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authEmailLabel => 'Email address';

  @override
  String get authEmailHint => 'you@email.com';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authPasswordHint => '••••••••';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authSocialOpened =>
      'Sign-in opened. Come back to the app afterwards.';

  @override
  String get authErrorSignInFailed => 'Sign-in failed. Please try again.';

  @override
  String get authErrorCancelled => 'Sign-in cancelled.';

  @override
  String get authErrorGoogleNotConfigured =>
      'Google sign-in is not fully configured yet.';

  @override
  String get authErrorAppleUnavailable =>
      'Apple sign-in is not available on this device.';

  @override
  String get authErrorTooManyAttempts =>
      'Too many attempts. Please wait a moment.';

  @override
  String get authCurrentPassword => 'Current password';

  @override
  String get authNewPassword => 'New password';

  @override
  String get authNewPasswordConfirm => 'Confirm new password';

  @override
  String get authPasswordRepeatHint => 'Repeat password';

  @override
  String get authPasswordsDoNotMatch => 'Passwords do not match.';

  @override
  String authPasswordTooShort(int min) {
    return 'Password must be at least $min characters.';
  }

  @override
  String authPasswordTooWeak(int min) {
    return 'Password too weak. At least $min characters.';
  }

  @override
  String get authPasswordSaveFailed =>
      'The password could not be saved. Please try again.';

  @override
  String get changePasswordTitle => 'Change password';

  @override
  String get changePasswordSetTitle => 'Set password';

  @override
  String get changePasswordHintCurrent =>
      'For your security we need your current password once.';

  @override
  String get changePasswordHintSocial =>
      'Your account currently uses Google or Apple. Set a password so you can also sign in with your email address.';

  @override
  String get changePasswordErrorCurrentMissing =>
      'Please enter your current password.';

  @override
  String get changePasswordErrorCurrentWrong => 'Current password is wrong.';

  @override
  String get changePasswordErrorSameAsOld =>
      'That is already your current password.';

  @override
  String get changePasswordChanged => 'Password changed.';

  @override
  String get changePasswordSet =>
      'Password set. You can now also sign in with your email address.';

  @override
  String get resetPasswordTitle => 'Reset password';

  @override
  String get resetPasswordEnterEmail =>
      'Enter your email address. We\'ll send you a 6-digit code to set a new password.';

  @override
  String get resetPasswordCodeStepTitle => 'Enter code';

  @override
  String resetPasswordCodeStepSubtitle(String email) {
    return 'If an account exists for $email, we\'ve sent you a 6-digit code.';
  }

  @override
  String resetPasswordNewStepSubtitle(int min) {
    return 'Choose a new password — at least $min characters.';
  }

  @override
  String get resetPasswordDoneTitle => 'Password changed';

  @override
  String get resetPasswordDoneSubtitle =>
      'Your new password is active and you are signed in. Use it the next time you log in.';

  @override
  String get resetPasswordSendCode => 'Send code';

  @override
  String get resetPasswordCodeLabel => '6-digit code';

  @override
  String get resetPasswordSpamHint => 'No email? Check your spam folder too.';

  @override
  String get resetPasswordResend => 'Send code again';

  @override
  String resetPasswordResendIn(int seconds) {
    return 'Send code again ($seconds s)';
  }

  @override
  String get resetPasswordChangeEmail => 'Change email address';

  @override
  String get resetPasswordSave => 'Save password';

  @override
  String get resetPasswordToApp => 'Continue to the app';

  @override
  String get resetPasswordErrorInvalidEmail =>
      'Please enter a valid email address.';

  @override
  String get resetPasswordErrorSendFailed =>
      'The code could not be sent. Please try again.';

  @override
  String get resetPasswordCodeSent => 'New code sent. Check your inbox.';

  @override
  String get resetPasswordErrorResendFailed =>
      'Could not send a new code. Please wait a moment.';

  @override
  String get resetPasswordErrorCodeMissing => 'Please enter the 6-digit code.';

  @override
  String get resetPasswordErrorCodeInvalid => 'Code invalid or expired.';

  @override
  String get resetPasswordErrorVerifyFailed =>
      'Verification failed. Please try again.';

  @override
  String get resetPasswordErrorRateLimited =>
      'Too many emails in a short time. Please wait a few minutes.';

  @override
  String get resetPasswordErrorCodeExpired =>
      'The code has expired. Request a new one.';

  @override
  String get resetPasswordErrorCodeWrong =>
      'That code doesn\'t match. Please check the digits.';

  @override
  String get resetPasswordErrorSamePassword =>
      'That is your previous password. Please choose a new one.';

  @override
  String get resetPasswordErrorSessionExpired =>
      'Session expired. Please request a new code.';

  @override
  String get resetPasswordErrorGeneric =>
      'That didn\'t work. Please try again.';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonOr => 'or';

  @override
  String get commonSave => 'Save';

  @override
  String get commonBack => 'Back';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonRetry => 'Try again';

  @override
  String get commonClose => 'Close';
}
