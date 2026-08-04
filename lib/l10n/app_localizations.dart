import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// Überschrift des Sprachwahl-Screens beim ersten App-Start
  ///
  /// In de, this message translates to:
  /// **'Sprache wählen'**
  String get languageChoiceTitle;

  /// No description provided for @languageChoiceSubtitle.
  ///
  /// In de, this message translates to:
  /// **'In welcher Sprache möchtest du Cruise Connector nutzen? Du kannst das jederzeit in den Einstellungen ändern.'**
  String get languageChoiceSubtitle;

  /// No description provided for @languageChoiceContinue.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get languageChoiceContinue;

  /// No description provided for @languageGerman.
  ///
  /// In de, this message translates to:
  /// **'Deutsch'**
  String get languageGerman;

  /// No description provided for @languageEnglish.
  ///
  /// In de, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageSystemHint.
  ///
  /// In de, this message translates to:
  /// **'Vorgeschlagen nach deiner Geräte-Sprache'**
  String get languageSystemHint;

  /// Menüpunkt in den App-Einstellungen
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Sprache der App'**
  String get settingsLanguageSubtitle;

  /// No description provided for @welcomeTitle.
  ///
  /// In de, this message translates to:
  /// **'Willkommen zurück!'**
  String get welcomeTitle;

  /// No description provided for @welcomeCreateAccount.
  ///
  /// In de, this message translates to:
  /// **'Konto erstellen'**
  String get welcomeCreateAccount;

  /// No description provided for @welcomeOrContinueWith.
  ///
  /// In de, this message translates to:
  /// **'oder weiter mit'**
  String get welcomeOrContinueWith;

  /// No description provided for @loginTitle.
  ///
  /// In de, this message translates to:
  /// **'Willkommen zurück'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Melde dich an, um fortzufahren'**
  String get loginSubtitle;

  /// No description provided for @loginNoAccountPrefix.
  ///
  /// In de, this message translates to:
  /// **'Noch kein Konto? '**
  String get loginNoAccountPrefix;

  /// No description provided for @loginRegisterNow.
  ///
  /// In de, this message translates to:
  /// **'Jetzt registrieren'**
  String get loginRegisterNow;

  /// No description provided for @loginResendVerification.
  ///
  /// In de, this message translates to:
  /// **'E-Mail erneut senden'**
  String get loginResendVerification;

  /// No description provided for @loginVerificationResent.
  ///
  /// In de, this message translates to:
  /// **'Bestätigungs-E-Mail an {email} erneut gesendet.'**
  String loginVerificationResent(String email);

  /// No description provided for @loginResendFailed.
  ///
  /// In de, this message translates to:
  /// **'E-Mail konnte nicht erneut gesendet werden. Bitte kurz warten.'**
  String get loginResendFailed;

  /// No description provided for @loginErrorMissingFields.
  ///
  /// In de, this message translates to:
  /// **'Bitte E-Mail und Passwort eingeben.'**
  String get loginErrorMissingFields;

  /// No description provided for @loginErrorEmailMissing.
  ///
  /// In de, this message translates to:
  /// **'Bitte E-Mail eintragen.'**
  String get loginErrorEmailMissing;

  /// No description provided for @loginErrorInvalidCredentials.
  ///
  /// In de, this message translates to:
  /// **'E-Mail oder Passwort falsch.'**
  String get loginErrorInvalidCredentials;

  /// No description provided for @loginErrorEmailNotConfirmed.
  ///
  /// In de, this message translates to:
  /// **'Bitte bestätige zuerst deine E-Mail.'**
  String get loginErrorEmailNotConfirmed;

  /// No description provided for @loginErrorFailed.
  ///
  /// In de, this message translates to:
  /// **'Login fehlgeschlagen. Bitte erneut versuchen.'**
  String get loginErrorFailed;

  /// No description provided for @authSignIn.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get authSignIn;

  /// No description provided for @authEmailLabel.
  ///
  /// In de, this message translates to:
  /// **'E-Mail Adresse'**
  String get authEmailLabel;

  /// No description provided for @authEmailHint.
  ///
  /// In de, this message translates to:
  /// **'deine@email.de'**
  String get authEmailHint;

  /// No description provided for @authPasswordLabel.
  ///
  /// In de, this message translates to:
  /// **'Passwort'**
  String get authPasswordLabel;

  /// No description provided for @authPasswordHint.
  ///
  /// In de, this message translates to:
  /// **'••••••••'**
  String get authPasswordHint;

  /// No description provided for @authForgotPassword.
  ///
  /// In de, this message translates to:
  /// **'Passwort vergessen?'**
  String get authForgotPassword;

  /// No description provided for @authSocialOpened.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung geöffnet. Kehre danach zur App zurück.'**
  String get authSocialOpened;

  /// No description provided for @authErrorSignInFailed.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung fehlgeschlagen. Bitte erneut versuchen.'**
  String get authErrorSignInFailed;

  /// No description provided for @authErrorCancelled.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung abgebrochen.'**
  String get authErrorCancelled;

  /// No description provided for @authErrorGoogleNotConfigured.
  ///
  /// In de, this message translates to:
  /// **'Google Login ist noch nicht fertig konfiguriert.'**
  String get authErrorGoogleNotConfigured;

  /// No description provided for @authErrorAppleUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Apple Anmeldung ist auf diesem Gerät nicht verfügbar.'**
  String get authErrorAppleUnavailable;

  /// No description provided for @authErrorTooManyAttempts.
  ///
  /// In de, this message translates to:
  /// **'Zu viele Versuche. Bitte kurz warten.'**
  String get authErrorTooManyAttempts;

  /// No description provided for @authCurrentPassword.
  ///
  /// In de, this message translates to:
  /// **'Aktuelles Passwort'**
  String get authCurrentPassword;

  /// No description provided for @authNewPassword.
  ///
  /// In de, this message translates to:
  /// **'Neues Passwort'**
  String get authNewPassword;

  /// No description provided for @authNewPasswordConfirm.
  ///
  /// In de, this message translates to:
  /// **'Neues Passwort bestätigen'**
  String get authNewPasswordConfirm;

  /// No description provided for @authPasswordRepeatHint.
  ///
  /// In de, this message translates to:
  /// **'Passwort wiederholen'**
  String get authPasswordRepeatHint;

  /// No description provided for @authPasswordsDoNotMatch.
  ///
  /// In de, this message translates to:
  /// **'Passwörter stimmen nicht überein.'**
  String get authPasswordsDoNotMatch;

  /// No description provided for @authPasswordTooShort.
  ///
  /// In de, this message translates to:
  /// **'Passwort muss mindestens {min} Zeichen haben.'**
  String authPasswordTooShort(int min);

  /// No description provided for @authPasswordTooWeak.
  ///
  /// In de, this message translates to:
  /// **'Passwort zu schwach. Mindestens {min} Zeichen.'**
  String authPasswordTooWeak(int min);

  /// No description provided for @authPasswordSaveFailed.
  ///
  /// In de, this message translates to:
  /// **'Passwort konnte nicht gespeichert werden. Bitte erneut versuchen.'**
  String get authPasswordSaveFailed;

  /// No description provided for @changePasswordTitle.
  ///
  /// In de, this message translates to:
  /// **'Passwort ändern'**
  String get changePasswordTitle;

  /// No description provided for @changePasswordSetTitle.
  ///
  /// In de, this message translates to:
  /// **'Passwort festlegen'**
  String get changePasswordSetTitle;

  /// No description provided for @changePasswordHintCurrent.
  ///
  /// In de, this message translates to:
  /// **'Zur Sicherheit brauchen wir einmal dein aktuelles Passwort.'**
  String get changePasswordHintCurrent;

  /// No description provided for @changePasswordHintSocial.
  ///
  /// In de, this message translates to:
  /// **'Dein Konto läuft bisher über Google oder Apple. Leg ein Passwort fest, um dich zusätzlich mit E-Mail anmelden zu können.'**
  String get changePasswordHintSocial;

  /// No description provided for @changePasswordErrorCurrentMissing.
  ///
  /// In de, this message translates to:
  /// **'Bitte gib dein aktuelles Passwort ein.'**
  String get changePasswordErrorCurrentMissing;

  /// No description provided for @changePasswordErrorCurrentWrong.
  ///
  /// In de, this message translates to:
  /// **'Aktuelles Passwort ist falsch.'**
  String get changePasswordErrorCurrentWrong;

  /// No description provided for @changePasswordErrorSameAsOld.
  ///
  /// In de, this message translates to:
  /// **'Das neue Passwort ist dein bisheriges.'**
  String get changePasswordErrorSameAsOld;

  /// No description provided for @changePasswordChanged.
  ///
  /// In de, this message translates to:
  /// **'Passwort geändert.'**
  String get changePasswordChanged;

  /// No description provided for @changePasswordSet.
  ///
  /// In de, this message translates to:
  /// **'Passwort gesetzt. Du kannst dich jetzt auch mit E-Mail anmelden.'**
  String get changePasswordSet;

  /// No description provided for @resetPasswordTitle.
  ///
  /// In de, this message translates to:
  /// **'Passwort zurücksetzen'**
  String get resetPasswordTitle;

  /// No description provided for @resetPasswordEnterEmail.
  ///
  /// In de, this message translates to:
  /// **'Gib deine E-Mail-Adresse ein. Wir schicken dir einen 6-stelligen Code, mit dem du ein neues Passwort setzt.'**
  String get resetPasswordEnterEmail;

  /// No description provided for @resetPasswordCodeStepTitle.
  ///
  /// In de, this message translates to:
  /// **'Code eingeben'**
  String get resetPasswordCodeStepTitle;

  /// No description provided for @resetPasswordCodeStepSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Falls ein Konto mit {email} existiert, haben wir dir einen 6-stelligen Code geschickt.'**
  String resetPasswordCodeStepSubtitle(String email);

  /// No description provided for @resetPasswordNewStepSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Wähl ein neues Passwort — mindestens {min} Zeichen.'**
  String resetPasswordNewStepSubtitle(int min);

  /// No description provided for @resetPasswordDoneTitle.
  ///
  /// In de, this message translates to:
  /// **'Passwort geändert'**
  String get resetPasswordDoneTitle;

  /// No description provided for @resetPasswordDoneSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Dein neues Passwort ist aktiv und du bist angemeldet. Beim nächsten Login nutzt du das neue Passwort.'**
  String get resetPasswordDoneSubtitle;

  /// No description provided for @resetPasswordSendCode.
  ///
  /// In de, this message translates to:
  /// **'Code senden'**
  String get resetPasswordSendCode;

  /// No description provided for @resetPasswordCodeLabel.
  ///
  /// In de, this message translates to:
  /// **'6-stelliger Code'**
  String get resetPasswordCodeLabel;

  /// No description provided for @resetPasswordSpamHint.
  ///
  /// In de, this message translates to:
  /// **'Keine Mail erhalten? Sieh auch im Spam-Ordner nach.'**
  String get resetPasswordSpamHint;

  /// No description provided for @resetPasswordResend.
  ///
  /// In de, this message translates to:
  /// **'Code erneut senden'**
  String get resetPasswordResend;

  /// No description provided for @resetPasswordResendIn.
  ///
  /// In de, this message translates to:
  /// **'Code erneut senden ({seconds} s)'**
  String resetPasswordResendIn(int seconds);

  /// No description provided for @resetPasswordChangeEmail.
  ///
  /// In de, this message translates to:
  /// **'E-Mail-Adresse ändern'**
  String get resetPasswordChangeEmail;

  /// No description provided for @resetPasswordSave.
  ///
  /// In de, this message translates to:
  /// **'Passwort speichern'**
  String get resetPasswordSave;

  /// No description provided for @resetPasswordToApp.
  ///
  /// In de, this message translates to:
  /// **'Weiter zur App'**
  String get resetPasswordToApp;

  /// No description provided for @resetPasswordErrorInvalidEmail.
  ///
  /// In de, this message translates to:
  /// **'Bitte gib eine gültige E-Mail-Adresse ein.'**
  String get resetPasswordErrorInvalidEmail;

  /// No description provided for @resetPasswordErrorSendFailed.
  ///
  /// In de, this message translates to:
  /// **'Der Code konnte nicht gesendet werden. Bitte erneut versuchen.'**
  String get resetPasswordErrorSendFailed;

  /// No description provided for @resetPasswordCodeSent.
  ///
  /// In de, this message translates to:
  /// **'Neuer Code gesendet. Schau in dein Postfach.'**
  String get resetPasswordCodeSent;

  /// No description provided for @resetPasswordErrorResendFailed.
  ///
  /// In de, this message translates to:
  /// **'Konnte keinen neuen Code senden. Bitte kurz warten.'**
  String get resetPasswordErrorResendFailed;

  /// No description provided for @resetPasswordErrorCodeMissing.
  ///
  /// In de, this message translates to:
  /// **'Bitte gib den 6-stelligen Code ein.'**
  String get resetPasswordErrorCodeMissing;

  /// No description provided for @resetPasswordErrorCodeInvalid.
  ///
  /// In de, this message translates to:
  /// **'Code ungültig oder abgelaufen.'**
  String get resetPasswordErrorCodeInvalid;

  /// No description provided for @resetPasswordErrorVerifyFailed.
  ///
  /// In de, this message translates to:
  /// **'Bestätigung fehlgeschlagen. Bitte erneut versuchen.'**
  String get resetPasswordErrorVerifyFailed;

  /// No description provided for @resetPasswordErrorRateLimited.
  ///
  /// In de, this message translates to:
  /// **'Zu viele E-Mails in kurzer Zeit. Bitte warte ein paar Minuten.'**
  String get resetPasswordErrorRateLimited;

  /// No description provided for @resetPasswordErrorCodeExpired.
  ///
  /// In de, this message translates to:
  /// **'Der Code ist abgelaufen. Fordere einen neuen an.'**
  String get resetPasswordErrorCodeExpired;

  /// No description provided for @resetPasswordErrorCodeWrong.
  ///
  /// In de, this message translates to:
  /// **'Der Code stimmt nicht. Bitte prüfe die Ziffern.'**
  String get resetPasswordErrorCodeWrong;

  /// No description provided for @resetPasswordErrorSamePassword.
  ///
  /// In de, this message translates to:
  /// **'Das ist dein bisheriges Passwort. Bitte wähle ein neues.'**
  String get resetPasswordErrorSamePassword;

  /// No description provided for @resetPasswordErrorSessionExpired.
  ///
  /// In de, this message translates to:
  /// **'Sitzung abgelaufen. Bitte fordere einen neuen Code an.'**
  String get resetPasswordErrorSessionExpired;

  /// No description provided for @resetPasswordErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Das hat nicht geklappt. Bitte erneut versuchen.'**
  String get resetPasswordErrorGeneric;

  /// No description provided for @commonCancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get commonCancel;

  /// No description provided for @commonOr.
  ///
  /// In de, this message translates to:
  /// **'oder'**
  String get commonOr;

  /// No description provided for @commonSave.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get commonSave;

  /// No description provided for @commonBack.
  ///
  /// In de, this message translates to:
  /// **'Zurück'**
  String get commonBack;

  /// No description provided for @commonContinue.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get commonContinue;

  /// No description provided for @commonRetry.
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get commonRetry;

  /// No description provided for @commonClose.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get commonClose;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
