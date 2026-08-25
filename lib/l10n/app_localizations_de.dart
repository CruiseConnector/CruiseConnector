// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get languageChoiceTitle => 'Sprache wählen';

  @override
  String get languageChoiceSubtitle =>
      'In welcher Sprache möchtest du Cruise Connector nutzen? Du kannst das jederzeit in den Einstellungen ändern.';

  @override
  String get languageChoiceContinue => 'Weiter';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageSystemHint =>
      'Vorgeschlagen nach der Sprache deines Geräts';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsLanguageSubtitle => 'Sprache der App';

  @override
  String get welcomeTitle => 'Willkommen zurück!';

  @override
  String get welcomeCreateAccount => 'Konto erstellen';

  @override
  String get welcomeOrContinueWith => 'oder weiter mit';

  @override
  String get loginTitle => 'Willkommen zurück';

  @override
  String get loginSubtitle => 'Melde dich an, um fortzufahren';

  @override
  String get loginNoAccountPrefix => 'Noch kein Konto? ';

  @override
  String get loginRegisterNow => 'Jetzt registrieren';

  @override
  String get loginResendVerification => 'E-Mail erneut senden';

  @override
  String loginVerificationResent(String email) {
    return 'Bestätigungsmail an $email erneut gesendet.';
  }

  @override
  String get loginResendFailed =>
      'E-Mail konnte nicht erneut gesendet werden. Bitte kurz warten.';

  @override
  String get loginErrorMissingFields => 'Bitte E-Mail und Passwort eingeben.';

  @override
  String get loginErrorEmailMissing => 'Bitte E-Mail eintragen.';

  @override
  String get loginErrorInvalidCredentials => 'E-Mail oder Passwort falsch.';

  @override
  String get loginErrorEmailNotConfirmed =>
      'Bitte bestätige zuerst deine E-Mail.';

  @override
  String get loginErrorFailed =>
      'Login fehlgeschlagen. Bitte erneut versuchen.';

  @override
  String get authSignIn => 'Anmelden';

  @override
  String get authEmailLabel => 'E-Mail-Adresse';

  @override
  String get authEmailHint => 'deine@email.de';

  @override
  String get authPasswordLabel => 'Passwort';

  @override
  String get authPasswordHint => '••••••••';

  @override
  String get authForgotPassword => 'Passwort vergessen?';

  @override
  String get authSocialOpened =>
      'Anmeldung geöffnet. Kehre danach zur App zurück.';

  @override
  String get authErrorSignInFailed =>
      'Anmeldung fehlgeschlagen. Bitte erneut versuchen.';

  @override
  String get authErrorCancelled => 'Anmeldung abgebrochen.';

  @override
  String get authErrorGoogleNotConfigured =>
      'Google Login ist noch nicht fertig konfiguriert.';

  @override
  String get authErrorAppleUnavailable =>
      'Apple Anmeldung ist auf diesem Gerät nicht verfügbar.';

  @override
  String get authErrorTooManyAttempts =>
      'Zu viele Versuche. Bitte kurz warten.';

  @override
  String get authCurrentPassword => 'Aktuelles Passwort';

  @override
  String get authNewPassword => 'Neues Passwort';

  @override
  String get authNewPasswordConfirm => 'Neues Passwort bestätigen';

  @override
  String get authPasswordRepeatHint => 'Passwort wiederholen';

  @override
  String get authPasswordsDoNotMatch => 'Passwörter stimmen nicht überein.';

  @override
  String authPasswordTooShort(int min) {
    return 'Passwort muss mindestens $min Zeichen haben.';
  }

  @override
  String authPasswordTooWeak(int min) {
    return 'Passwort zu schwach. Mindestens $min Zeichen.';
  }

  @override
  String get authPasswordSaveFailed =>
      'Passwort konnte nicht gespeichert werden. Bitte erneut versuchen.';

  @override
  String get changePasswordTitle => 'Passwort ändern';

  @override
  String get changePasswordSetTitle => 'Passwort festlegen';

  @override
  String get changePasswordHintCurrent =>
      'Zur Sicherheit brauchen wir einmal dein aktuelles Passwort.';

  @override
  String get changePasswordHintSocial =>
      'Dein Konto läuft bisher über Google oder Apple. Leg ein Passwort fest, um dich zusätzlich mit E-Mail anmelden zu können.';

  @override
  String get changePasswordErrorCurrentMissing =>
      'Bitte gib dein aktuelles Passwort ein.';

  @override
  String get changePasswordErrorCurrentWrong =>
      'Aktuelles Passwort ist falsch.';

  @override
  String get changePasswordErrorSameAsOld =>
      'Das neue Passwort ist dein bisheriges.';

  @override
  String get changePasswordChanged => 'Passwort geändert.';

  @override
  String get changePasswordSet =>
      'Passwort gesetzt. Du kannst dich jetzt auch mit E-Mail anmelden.';

  @override
  String get resetPasswordTitle => 'Passwort zurücksetzen';

  @override
  String get resetPasswordEnterEmail =>
      'Gib deine E-Mail-Adresse ein. Wir schicken dir einen sechsstelligen Code, mit dem du ein neues Passwort setzt.';

  @override
  String get resetPasswordCodeStepTitle => 'Code eingeben';

  @override
  String resetPasswordCodeStepSubtitle(String email) {
    return 'Falls ein Konto mit $email existiert, haben wir dir einen sechsstelligen Code geschickt.';
  }

  @override
  String resetPasswordNewStepSubtitle(int min) {
    return 'Wähl ein neues Passwort mit mindestens $min Zeichen.';
  }

  @override
  String get resetPasswordDoneTitle => 'Passwort geändert';

  @override
  String get resetPasswordDoneSubtitle =>
      'Dein neues Passwort ist aktiv und du bist angemeldet. Beim nächsten Login nutzt du das neue Passwort.';

  @override
  String get resetPasswordSendCode => 'Code senden';

  @override
  String get resetPasswordCodeLabel => 'sechsstelliger Code';

  @override
  String get resetPasswordSpamHint =>
      'Keine Mail erhalten? Sieh auch im Spamordner nach.';

  @override
  String get resetPasswordResend => 'Code erneut senden';

  @override
  String resetPasswordResendIn(int seconds) {
    return 'Code erneut senden ($seconds s)';
  }

  @override
  String get resetPasswordChangeEmail => 'E-Mail-Adresse ändern';

  @override
  String get resetPasswordSave => 'Passwort speichern';

  @override
  String get resetPasswordToApp => 'Weiter zur App';

  @override
  String get resetPasswordErrorInvalidEmail =>
      'Bitte gib eine gültige E-Mail-Adresse ein.';

  @override
  String get resetPasswordErrorSendFailed =>
      'Der Code konnte nicht gesendet werden. Bitte erneut versuchen.';

  @override
  String get resetPasswordCodeSent =>
      'Neuer Code gesendet. Schau in dein Postfach.';

  @override
  String get resetPasswordErrorResendFailed =>
      'Konnte keinen neuen Code senden. Bitte kurz warten.';

  @override
  String get resetPasswordErrorCodeMissing =>
      'Bitte gib den sechsstelligen Code ein.';

  @override
  String get resetPasswordErrorCodeInvalid => 'Code ungültig oder abgelaufen.';

  @override
  String get resetPasswordErrorVerifyFailed =>
      'Bestätigung fehlgeschlagen. Bitte erneut versuchen.';

  @override
  String get resetPasswordErrorRateLimited =>
      'Zu viele E-Mails in kurzer Zeit. Bitte warte ein paar Minuten.';

  @override
  String get resetPasswordErrorCodeExpired =>
      'Der Code ist abgelaufen. Fordere einen neuen an.';

  @override
  String get resetPasswordErrorCodeWrong =>
      'Der Code stimmt nicht. Bitte prüfe die Ziffern.';

  @override
  String get resetPasswordErrorSamePassword =>
      'Das ist dein bisheriges Passwort. Bitte wähle ein neues.';

  @override
  String get resetPasswordErrorSessionExpired =>
      'Sitzung abgelaufen. Bitte fordere einen neuen Code an.';

  @override
  String get resetPasswordErrorGeneric =>
      'Das hat nicht geklappt. Bitte erneut versuchen.';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonOr => 'oder';

  @override
  String get commonSave => 'Speichern';

  @override
  String get commonBack => 'Zurück';

  @override
  String get commonContinue => 'Weiter';

  @override
  String get commonRetry => 'Erneut versuchen';

  @override
  String get commonClose => 'Schließen';
}
