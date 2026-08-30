// 2026-06-27 (vucko) — Onboarding-Wizard. Das vollständige „Konto erstellen"-
// Erlebnis: mehrseitig, animiert, eine Sache pro Seite. Beginnt mit einem
// Willkommens-Screen („Los geht's"), legt dann das Konto an (E-Mail+Passwort)
// und sammelt danach Schritt für Schritt das Profil. Am Ende ist man im Account.
//
// Zwei Einstiege:
//  • Registrierung („Konto erstellen", noch keine Session) → startWithAccount=true,
//    Schritt „Account" legt das Konto an, danach schreibt jede Seite live ins Profil.
//  • Social-Login (Google/Apple, bereits eingeloggt) → PostAuthGate ruft den
//    Wizard ohne Account-Schritt auf; Profil-Daten werden direkt gespeichert.
//
// Gegated über profiles.onboarding_completed (siehe PostAuthGate). Erscheint NUR
// bei Account-Erstellung, nicht beim normalen Login bestehender User.

import 'dart:async';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/auth_service.dart';
import 'package:cruise_connect/data/services/legal_acceptance_service.dart';
import 'package:cruise_connect/data/services/map_style_service.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/data/services/vehicle_api_service.dart';
import 'package:cruise_connect/presentation/pages/home_page.dart';
import 'package:cruise_connect/presentation/pages/legal_acceptance_page.dart';
import 'package:cruise_connect/presentation/pages/welcome_page.dart';
import 'package:cruise_connect/presentation/widgets/photo/ride_photo_picker.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _bg = Color(0xFF0B0E14);
const Color _card = Color(0xFF171B26);
const Color _muted = Color(0xFF8A93A6);
const Color _ok = Color(0xFF2ECC71);
const Color _err = Color(0xFFE74C3C);

// 2026-08-24 (vucko, nach dem Vorfall „Nutzer sitzt fest"): Jeder Aufruf, auf
// den dieser Assistent mit `_busy = true` wartet, sperrt den GANZEN Bildschirm
// — Weiter, Überspringen und Zurück sind dann tot, und `PopScope(canPop:
// false)` verhindert zusätzlich die Zurück-Geste. Ein `finally` hilft dabei
// nur gegen Fehler, NICHT gegen einen Aufruf, der nie zurückkommt: dann läuft
// das `finally` nie. Deshalb hat jeder dieser Aufrufe eine Zeitgrenze. Läuft
// sie ab, greift das `finally`, der Bildschirm wird wieder bedienbar und der
// Nutzer bekommt eine Meldung statt eines gesperrten Knopfes.
const Duration _netzZeitgrenze = Duration(seconds: 20);

/// Abmelden darf kürzer warten — es soll nur schnell zur Startseite zurück.
const Duration _abmeldeZeitgrenze = Duration(seconds: 8);

enum _UNameState { idle, checking, available, taken, reserved, invalid, error }

enum _Step {
  welcome,
  account,
  verifyEmail,
  username,
  displayName,
  region,
  photo,
  garage,
  finish,
}

class OnboardingWizardPage extends StatefulWidget {
  const OnboardingWizardPage({
    super.key,
    this.startWithAccountCreation = false,
    this.initialDisplayName,
    this.initialUsername,
  });

  /// true = Einstieg über „Konto erstellen" (noch keine Session) → der Wizard
  /// legt das Konto selbst an. false = bereits eingeloggt (Social-Login).
  final bool startWithAccountCreation;

  /// Vorbelegung aus OAuth (Google/Apple liefern oft einen Namen).
  final String? initialDisplayName;
  final String? initialUsername;

  @override
  State<OnboardingWizardPage> createState() => _OnboardingWizardPageState();
}

class _OnboardingWizardPageState extends State<OnboardingWizardPage> {
  int _page = 0;
  bool _forward = true;
  bool _busy = false;
  bool _accountCreated = false;

  // Account-Schritt
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePw = true;
  bool _obscureConf = true;
  String? _accountErr;

  // E-Mail-Bestätigung per 6-stelligem Code (In-App, kein Neu-Login)
  final _codeCtrl = TextEditingController();
  bool _emailConfirmPending = false;
  String _pendingEmail = '';
  LegalAcceptanceSnapshot? _pendingLegal;
  String? _codeErr;
  Timer? _resendTimer;
  int _resendIn = 0;

  // Profil-Schritte
  final _usernameCtrl = TextEditingController();
  final _displayCtrl = TextEditingController();
  final _carBrandCtrl = TextEditingController();
  final _carNameCtrl = TextEditingController();
  String? _country;
  Uint8List? _avatarBytes;

  // @-Name Live-Check
  Timer? _debounce;
  _UNameState _uState = _UNameState.idle;
  List<String> _suggestions = const [];
  String? _committedUsername;

  late final bool _needsAccount;
  late final List<_Step> _steps;

  static const _countries = <(String, String)>[
    ('AT', 'Österreich'),
    ('DE', 'Deutschland'),
    ('CH', 'Schweiz'),
    ('IT', 'Italien'),
    ('FR', 'Frankreich'),
    ('LI', 'Liechtenstein'),
    ('Andere', 'Anderes Land'),
  ];

  @override
  void initState() {
    super.initState();
    _needsAccount =
        widget.startWithAccountCreation && AuthService.currentUser == null;
    _steps = <_Step>[
      _Step.welcome,
      if (_needsAccount) _Step.account,
      if (_needsAccount) _Step.verifyEmail,
      _Step.username,
      _Step.displayName,
      _Step.region,
      _Step.photo,
      _Step.garage,
      _Step.finish,
    ];

    final dn = widget.initialDisplayName?.trim();
    if (dn != null && dn.isNotEmpty) _displayCtrl.text = dn;
    final un = widget.initialUsername?.trim();
    if (un != null && un.isNotEmpty) {
      _usernameCtrl.text = un;
      _onUsernameChanged(un);
    } else {
      // 2026-08-28 (Fehler 3, Nutzer Justin): Wer das Onboarding abgebrochen
      // hatte, kam ueber das Tor OHNE Vorbelegung zurueck — leeres Feld,
      // obwohl sein Name laengst im Profil steht. Er tippte ihn neu, und die
      // 30-Tage-Sperre schlug zu (serverseitig seit heute mit Gleichheits-
      // Kurzschluss repariert). Die Vorbelegung macht den Wiedereinstieg
      // selbsterklaerend: Name steht da, Weiter druecken, fertig.
      unawaited(_ladeBestehendesProfilVor());
    }
  }

  Future<void> _ladeBestehendesProfilVor() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      // Zeitgrenze wie ueberall am Post-Auth-Tor: ein haengender Server darf
      // das Onboarding nicht blockieren (Waechtertest post_auth_tor_kein_haenger).
      final profil = await SocialService.getUserProfile(
        uid,
      ).timeout(const Duration(seconds: 6));
      if (!mounted || profil == null) return;
      final un = (profil['username'] as String?)?.trim();
      if (un != null && un.isNotEmpty && _usernameCtrl.text.trim().isEmpty) {
        _usernameCtrl.text = un;
        _onUsernameChanged(un);
      }
      final dn = (profil['display_name'] as String?)?.trim();
      if (dn != null && dn.isNotEmpty && _displayCtrl.text.trim().isEmpty) {
        _displayCtrl.text = dn;
      }
    } catch (_) {
      // Vorbelegung ist Komfort. Scheitert sie, tippt man wie bisher.
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _resendTimer?.cancel();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    _codeCtrl.dispose();
    _usernameCtrl.dispose();
    _displayCtrl.dispose();
    _carBrandCtrl.dispose();
    _carNameCtrl.dispose();
    super.dispose();
  }

  _Step get _current => _steps[_page];
  bool get _isLast => _page == _steps.length - 1;
  bool get _isOptional => _current == _Step.photo || _current == _Step.garage;

  // ── @-Name Verfügbarkeit (debounced, server-seitig) ──────────────────────
  void _onUsernameChanged(String raw) {
    _debounce?.cancel();
    _committedUsername = null;
    final v = raw.trim();
    if (v.isEmpty) {
      setState(() {
        _uState = _UNameState.idle;
        _suggestions = const [];
      });
      return;
    }
    if (!AppInputLimits.isValidUsername(v)) {
      setState(() {
        _uState = _UNameState.invalid;
        _suggestions = const [];
      });
      return;
    }
    setState(() => _uState = _UNameState.checking);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      // Ohne Zeitgrenze bleibt `_uState` bei einem hängenden Aufruf für
      // immer auf `checking` — und weil „Weiter" auf der @-Name-Seite an
      // `_canLeaveUsernamePage` hängt, käme der Nutzer nie weiter. Bei
      // Ablauf derselbe Zustand wie bei einem Fehler: „Konnte gerade nicht
      // prüfen." Jeder weitere Tastendruck startet die Prüfung neu.
      final res = await SocialService.isUsernameAvailable(v).timeout(
        const Duration(seconds: 10),
        onTimeout: () => (available: false, reason: 'error'),
      );
      if (!mounted || _usernameCtrl.text.trim() != v) return;
      setState(() {
        switch (res.reason) {
          case 'ok':
            _uState = _UNameState.available;
            _suggestions = const [];
          case 'taken':
            _uState = _UNameState.taken;
            _suggestions = _genSuggestions(v);
          case 'reserved':
            _uState = _UNameState.reserved;
            _suggestions = _genSuggestions(v);
          case 'invalid_format':
            _uState = _UNameState.invalid;
            _suggestions = const [];
          default:
            _uState = _UNameState.error;
            _suggestions = const [];
        }
      });
    });
  }

  List<String> _genSuggestions(String base) {
    final b = base.length > 16 ? base.substring(0, 16) : base;
    final out = <String>['${b}1', '${b}_at', 'der_$b', '${b}22'];
    return out
        .where(AppInputLimits.isValidUsername)
        .take(3)
        .toList(growable: false);
  }

  /// 2026-08-31 (Nutzer zsago888 kam nicht durch die Registrierung, Screenshot
  /// „Konnte gerade nicht prüfen", mehrere Namen erfolglos probiert):
  ///
  /// Diese Bedingung verlangte [_UNameState.available] — und sperrte den
  /// Nutzer damit AUS, sobald die Vorabprüfung den Server nicht erreichte.
  /// In den Serverprotokollen des 30.08. stehen 531 Zeitüberschreitungen und
  /// 465 Überlastungen; genau in so einem Moment ist er hängengeblieben, mit
  /// einem gültigen und freien Namen.
  ///
  /// Die Vorabprüfung ist reiner Komfort. Verbindlich entscheidet
  /// [_commitUsername] beim Tippen auf „Weiter": `set_username` prüft
  /// serverseitig gegen denselben eindeutigen Schlüssel und meldet „taken"
  /// oder „reserved" zurück, die der Assistent anzeigt. Ein nicht erreichbarer
  /// Vorab-Dienst darf deshalb nie der Grund sein, warum jemand kein Konto
  /// bekommt.
  ///
  /// Bekannte Absagen (belegt, reserviert, ungültiges Format) sperren
  /// unverändert — die sind ja beantwortet.
  bool get _canLeaveUsernamePage =>
      _committedUsername != null ||
      _uState == _UNameState.available ||
      _uState == _UNameState.error;

  Future<bool> _commitUsername() async {
    final v = _usernameCtrl.text.trim();
    if (_committedUsername == v) return true;
    setState(() => _busy = true);
    try {
      final res = await SocialService.setUsername(v).timeout(_netzZeitgrenze);
      if (res.ok) {
        _committedUsername = v;
        return true;
      }
      final grund = UsernameChangeException(
        res.error ?? 'unknown',
        daysRemaining: res.daysRemaining,
      ).message;
      _showError(
        res.error == 'taken'
            ? '$grund${AppInputLimits.usernameFoldingHint(v)}'
            : grund,
      );
      if (res.error == 'taken' || res.error == 'reserved') {
        setState(() {
          _uState = res.error == 'taken'
              ? _UNameState.taken
              : _UNameState.reserved;
          _suggestions = _genSuggestions(v);
        });
      }
      return false;
    } on TimeoutException {
      _showError(
        'Dein Nutzername konnte gerade nicht gespeichert werden. Prüfe deine '
        'Verbindung und tippe nochmal auf „Weiter".',
      );
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Konto anlegen (Account-Schritt) ──────────────────────────────────────
  Future<bool> _createAccount() async {
    final email = _emailCtrl.text.trim();
    final pw = _pwCtrl.text;
    final confirm = _confirmCtrl.text;
    if (email.isEmpty || pw.isEmpty) {
      setState(() => _accountErr = 'Bitte E-Mail und Passwort eingeben.');
      return false;
    }
    if (pw.length < 6) {
      setState(() => _accountErr = 'Passwort muss mindestens 6 Zeichen haben.');
      return false;
    }
    if (pw != confirm) {
      setState(() => _accountErr = 'Passwörter stimmen nicht überein.');
      return false;
    }
    // 2026-07-10 (vucko): Schon bestätigte Rechtstexte (Pre-Auth-Pending, z. B.
    // vom vorherigen Versuch „E-Mail bereits registriert") nicht ERNEUT
    // abfragen — sonst kommt das AGB-Fenster zweimal.
    var legalAcceptance =
        await LegalAcceptanceService.pendingPreAuthAcceptance();
    if (!mounted) return false;
    legalAcceptance ??= await LegalAcceptancePage.requestPreAuth(
      context,
      source: 'app_onboarding',
    );
    if (!mounted || legalAcceptance == null) {
      setState(
        () => _accountErr =
            'Bitte AGB und Datenschutzerklärung bestätigen, um dein Konto zu erstellen.',
      );
      return false;
    }

    setState(() {
      _busy = true;
      _accountErr = null;
    });
    try {
      await AuthService.signUp(
        email: email,
        password: pw,
        legalAcceptance: legalAcceptance,
      ).timeout(_netzZeitgrenze);
      if (AuthService.currentUser == null) {
        // E-Mail-Bestätigung nötig (Autoconfirm aus): NICHT hängen bleiben und
        // NICHT zum Neu-Login zwingen. Stattdessen in den In-App-Code-Schritt
        // wechseln — der Nutzer tippt den 6-stelligen Code aus der Mail ein und
        // ist danach SOFORT angemeldet und macht direkt im Onboarding weiter.
        _pendingEmail = email;
        _pendingLegal = legalAcceptance;
        _emailConfirmPending = true;
        _codeCtrl.clear();
        _codeErr = null;
        _startResendCooldown();
        return true;
      }
      // Session sofort da (Bestätigung deaktiviert) → kein Code-Schritt nötig.
      _emailConfirmPending = false;
      _accountCreated = true;
      return true;
    } on AuthException catch (e) {
      setState(() => _accountErr = _translateAuthError(e.message));
      return false;
    } on TimeoutException {
      setState(
        () => _accountErr =
            'Der Server antwortet gerade nicht. Prüfe deine Verbindung und '
            'versuche es erneut.',
      );
      return false;
    } catch (e) {
      debugPrint('[Onboarding] signUp Fehler: $e');
      setState(
        () => _accountErr =
            'Registrierung fehlgeschlagen. Bitte erneut versuchen.',
      );
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _translateAuthError(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('bereits registriert')) return msg;
    if (m.contains('already registered') || m.contains('already exists')) {
      return 'Diese E-Mail ist bereits registriert. Melde dich stattdessen an.';
    }
    if (m.contains('rate limit') || m.contains('security purposes')) {
      return 'Zu viele Versuche in kurzer Zeit. Bitte warte ein paar Minuten.';
    }
    if (m.contains('password should be')) {
      return 'Passwort zu schwach. Mindestens 6 Zeichen.';
    }
    if (m.contains('invalid email')) return 'Ungültige E-Mail-Adresse.';
    return 'Registrierung fehlgeschlagen. Bitte erneut versuchen.';
  }

  // ── Navigation ───────────────────────────────────────────────────────────
  Future<void> _next() async {
    // Vorschlaege schon beim Verlassen der Region-Seite anstossen — dann ist
    // die Liste da, wenn der Abschluss-Schritt erscheint, und niemand sieht
    // einen Ladekringel. Bewusst NICHT abgewartet: Das Weiterblaettern darf
    // nie an einer Netzabfrage haengen.
    if (_current == _Step.region) {
      _mitfahrerVorschlaege ??= SocialService.getSuggestedUsers(limit: 8);
    }
    switch (_current) {
      case _Step.account:
        if (!await _createAccount()) return;
        if (!_emailConfirmPending) {
          // Bestätigung deaktiviert → Code-Schritt überspringen, direkt zum @-Namen.
          _goToStep(_Step.username);
          return;
        }
      case _Step.verifyEmail:
        if (!await _verifyCode()) return;
      case _Step.username:
        if (!_canLeaveUsernamePage) return;
        if (!await _commitUsername()) return;
      case _Step.displayName:
        final name = _displayCtrl.text.trim();
        if (name.isEmpty) {
          _showError('Bitte gib einen Anzeigenamen ein.');
          return;
        }
        setState(() => _busy = true);
        try {
          await SocialService.setDisplayName(name).timeout(_netzZeitgrenze);
        } catch (_) {
          // Anzeigename ist nachträglich im Profil änderbar — hier zählt
          // nur, dass der Assistent weiterläuft statt zu hängen.
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      case _Step.region:
        if (_country == null) {
          _showError('Bitte wähle deine Region.');
          return;
        }
      default:
        break;
    }
    if (_isLast) {
      await _finish();
      return;
    }
    _goTo(_page + 1, forward: true);
  }

  void _goTo(int p, {required bool forward}) {
    setState(() {
      _forward = forward;
      _page = p;
    });
  }

  void _goToStep(_Step s) {
    final idx = _steps.indexOf(s);
    if (idx >= 0) _goTo(idx, forward: true);
  }

  // ── E-Mail-Code bestätigen (In-App, sofort angemeldet) ───────────────────
  Future<bool> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 6) {
      setState(() => _codeErr = 'Bitte gib den sechsstelligen Code ein.');
      return false;
    }
    setState(() {
      _busy = true;
      _codeErr = null;
    });
    try {
      await AuthService.verifyEmailCode(
        email: _pendingEmail,
        token: code,
        legalAcceptance: _pendingLegal,
      ).timeout(_netzZeitgrenze);
      if (AuthService.currentUser == null) {
        setState(() => _codeErr = 'Code ungültig oder abgelaufen.');
        return false;
      }
      // Konto ist jetzt bestätigt UND angemeldet → ab hier kein Zurück mehr.
      _accountCreated = true;
      _emailConfirmPending = false;
      _cancelResendTimer();
      return true;
    } on AuthException catch (e) {
      setState(() => _codeErr = _translateOtpError(e.message));
      return false;
    } on TimeoutException {
      setState(
        () => _codeErr =
            'Der Server antwortet gerade nicht. Prüfe deine Verbindung und '
            'tippe nochmal auf „Weiter".',
      );
      return false;
    } catch (e) {
      debugPrint('[Onboarding] verifyCode Fehler: $e');
      setState(
        () => _codeErr = 'Bestätigung fehlgeschlagen. Bitte erneut versuchen.',
      );
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _translateOtpError(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('expired')) {
      return 'Der Code ist abgelaufen. Fordere einen neuen an.';
    }
    if (m.contains('invalid') || m.contains('incorrect')) {
      return 'Der Code stimmt nicht. Bitte prüfe die Ziffern.';
    }
    return 'Bestätigung fehlgeschlagen. Bitte erneut versuchen.';
  }

  // 2026-08-02 (vucko): 60 s statt 45 s — Supabase erlaubt laut SMTP-Setting
  // („Minimum interval per user") nur alle 60 s eine Mail an denselben Nutzer.
  // Mit 45 s sah der Button aktiv aus und lief in ein 429.
  void _startResendCooldown([int seconds = 60]) {
    _cancelResendTimer();
    setState(() => _resendIn = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendIn = _resendIn <= 0 ? 0 : _resendIn - 1);
      if (_resendIn <= 0) t.cancel();
    });
  }

  void _cancelResendTimer() {
    _resendTimer?.cancel();
    _resendTimer = null;
  }

  Future<void> _resendCode() async {
    if (_resendIn > 0 || _busy || _pendingEmail.isEmpty) return;
    setState(() => _busy = true);
    try {
      await AuthService.resendVerificationEmail(
        _pendingEmail,
      ).timeout(_netzZeitgrenze);
      _startResendCooldown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Neuer Code gesendet. Schau in dein Postfach.'),
          ),
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      final m = e.message.toLowerCase();
      final rateLimited =
          e.statusCode == '429' ||
          m.contains('rate limit') ||
          m.contains('security purposes');
      if (rateLimited) {
        // E-Mail-Versandlimit erreicht → ehrlich sagen + längeren Cooldown,
        // damit nicht weiter dagegen getippt wird.
        _showError(
          'Zu viele E-Mails in kurzer Zeit. Bitte warte ein paar Minuten und '
          'versuche es dann erneut.',
        );
        _startResendCooldown(180);
      } else {
        _showError('Konnte keinen neuen Code senden. Bitte kurz warten.');
      }
    } catch (_) {
      if (mounted) {
        _showError(
          'Konnte gerade keinen neuen Code senden. Bitte kurz warten.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Erste Seite, hinter die man nicht zurück kann. Nach Konto-Erstellung ist das
  // die @-Name-Seite (Welcome/Account werden nicht erneut betreten).
  int get _floorPage => _accountCreated ? _steps.indexOf(_Step.username) : 0;

  void _handleBack() {
    if (_busy) return;
    if (_page > _floorPage) {
      _goTo(_page - 1, forward: false);
    } else {
      _handleExit();
    }
  }

  Future<void> _handleExit() async {
    // Noch kein Konto angelegt (reine Registrierung) → ohne Nachfrage zurück.
    if (AuthService.currentUser == null) {
      _toWelcome();
      return;
    }
    final confirmed = await _confirmCancel();
    if (confirmed == true) await _cancelOnboarding();
  }

  Future<bool?> _confirmCancel() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Onboarding abbrechen?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Bist du dir sicher, dass du das Onboarding abbrechen willst? Du wirst '
          'abgemeldet und kannst es später jederzeit neu starten.',
          style: TextStyle(color: _muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Weiter einrichten',
              style: TextStyle(color: _muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Abbrechen',
              style: TextStyle(
                color: AppAccentColors.accent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelOnboarding() async {
    setState(() => _busy = true);
    try {
      // Der Weg zurück zur Startseite darf NICHT am Abmelden hängen: läuft
      // die Zeitgrenze ab, geht es trotzdem raus. Eine noch offene lokale
      // Session wird beim nächsten Start ohnehin neu geprüft.
      await AuthService.signOut().timeout(_abmeldeZeitgrenze);
    } catch (e) {
      debugPrint('[Onboarding] Abmelden fehlgeschlagen/hängt: $e');
    }
    if (mounted) setState(() => _busy = false);
    _toWelcome();
  }

  void _toWelcome() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomePage()),
      (r) => false,
    );
  }

  Future<void> _skip() async {
    if (_isLast) {
      await _finish();
    } else {
      _goTo(_page + 1, forward: true);
    }
  }

  /// Vorschlaege fuer den Abschluss-Schritt.
  ///
  /// 2026-08-11 (vucko): „vorallem moechte ich, dass die Leute eher sehen,
  /// dass es auch das Gruppenfeature oder das Community-Feature gibt."
  /// BEWUSST KEIN eigener Schritt: Die Fortschrittsbalken oben kommen aus
  /// _steps.length — ein zusaetzlicher Balken liesse das Onboarding laenger
  /// wirken und erhoeht das Abbruchrisiko. Stattdessen haengt die Liste am
  /// ohnehin vorhandenen letzten Schritt, wo der Knopf schon „App starten"
  /// heisst. Wer nicht folgen will, tippt einfach weiter — nichts blockiert.
  Future<List<Map<String, dynamic>>>? _mitfahrerVorschlaege;
  final Set<String> _gefolgt = <String>{};
  final Set<String> _folgenLaeuft = <String>{};

  Future<void> _finish() async {
    setState(() => _busy = true);
    try {
      final brand = _carBrandCtrl.text.trim();
      final model = _carNameCtrl.text.trim();
      if (brand.isNotEmpty || model.isNotEmpty) {
        try {
          await SocialService.updateCarProfile(
            brand: brand.isEmpty ? null : brand,
            name: model.isEmpty ? null : model,
          ).timeout(_netzZeitgrenze);
        } catch (_) {}
      }
      await SocialService.completeOnboarding(
        countryCode: _country == 'Andere' ? null : _country,
        region: _country,
        language: 'de',
      ).timeout(_netzZeitgrenze);
    } catch (e) {
      // Onboarding darf nie hängen bleiben — im Zweifel weiter zur App.
      // 2026-08-24 (vucko): Das galt bisher nur für Fehler. Ohne Zeitgrenze
      // blieb `_busy` bei einem hängenden Aufruf für immer true — und weil
      // `_finish` als einzige Stelle kein `finally` hat, wären Weiter,
      // Überspringen UND Zurück dauerhaft tot gewesen. Schlägt das
      // Abschliessen fehl, bleibt `onboarding_completed` false: das Post-Auth-
      // Tor holt den Assistenten beim nächsten Start nach.
      debugPrint('[Onboarding] Abschluss nicht gespeichert: $e');
    }
    // Offline-Karte direkt nach abgeschlossener Registrierung automatisch laden
    // (falls noch nicht vorhanden, nur WLAN, im Hintergrund).
    if (!kIsWeb) {
      MapStyleService.instance.ensureAutoDownloadScheduled(
        reason: 'post_registration',
      );
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (r) => false,
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFFB3261E)),
    );
  }

  Future<void> _pickPhoto() async {
    final bytes = await pickAndCropRidePhoto(context, lockedAspect: 1);
    if (bytes == null || !mounted) return;
    setState(() {
      _avatarBytes = bytes;
      _busy = true;
    });
    try {
      // uploadAvatar ist in social_service.dart durchgehend begrenzt
      // (Upload 3 x 25 s, danach das Setzen von avatar_url 25 s) und kann
      // deshalb nicht endlos hängen. Zusätzlich hier eine harte Obergrenze,
      // damit der Bildschirm garantiert wieder bedienbar wird.
      await SocialService.uploadAvatar(
        bytes,
      ).timeout(const Duration(minutes: 2));
    } catch (e) {
      debugPrint('[Onboarding] Profilbild nicht hochgeladen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            // Kühler Tiefen-Verlauf als Basis
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF151A24),
                      Color(0xFF0B0E14),
                      Color(0xFF07090F),
                    ],
                    stops: [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            // Akzent-Glow oben links + unten rechts (Tiefe + Marke)
            Positioned(top: -150, left: -90, child: _glow(accent, 320, 0.22)),
            Positioned(
              bottom: -180,
              right: -110,
              child: _glow(accent, 340, 0.13),
            ),
            SafeArea(
              child: Column(
                children: [
                  _topBar(accent),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 360),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) {
                        final dx = _forward ? 0.12 : -0.12;
                        return FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: Offset(dx, 0),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey<int>(_page),
                        child: _buildStep(_current, accent),
                      ),
                    ),
                  ),
                  _bottomBar(accent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glow(Color c, double size, double opacity) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            c.withValues(alpha: opacity),
            c.withValues(alpha: 0),
          ],
        ),
      ),
    ),
  );

  Widget _topBar(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: _muted,
                size: 18,
              ),
              onPressed: _busy ? null : _handleBack,
            ),
          ),
          Expanded(
            child: Row(
              children: List.generate(_steps.length, (i) {
                final active = i <= _page;
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    height: 4,
                    margin: EdgeInsets.only(
                      right: i == _steps.length - 1 ? 0 : 6,
                    ),
                    decoration: BoxDecoration(
                      color: active ? accent : _card,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _bottomBar(Color accent) {
    final nextEnabled =
        !_busy && (_current != _Step.username || _canLeaveUsernamePage);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(
        children: [
          if (_isOptional)
            TextButton(
              onPressed: _busy ? null : _skip,
              child: const Text(
                'Überspringen',
                style: TextStyle(color: _muted, fontSize: 15),
              ),
            ),
          const Spacer(),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: nextEnabled ? _next : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                disabledBackgroundColor: accent.withValues(alpha: 0.35),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: _current == _Step.welcome ? 40 : 30,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 4,
                shadowColor: accent.withValues(alpha: 0.4),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _primaryLabel(_current),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 20),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _primaryLabel(_Step s) {
    switch (s) {
      case _Step.welcome:
        return 'Los geht\'s';
      case _Step.account:
        return 'Konto erstellen';
      case _Step.verifyEmail:
        return 'Bestätigen';
      case _Step.finish:
        return 'App starten';
      default:
        return 'Weiter';
    }
  }

  Widget _buildStep(_Step s, Color accent) {
    switch (s) {
      case _Step.welcome:
        return _welcomeStep(accent);
      case _Step.account:
        return _accountStep(accent);
      case _Step.verifyEmail:
        return _verifyEmailStep(accent);
      case _Step.username:
        return _usernameStep(accent);
      case _Step.displayName:
        return _displayStep(accent);
      case _Step.region:
        return _regionStep(accent);
      case _Step.photo:
        return _photoStep(accent);
      case _Step.garage:
        return _garageStep(accent);
      case _Step.finish:
        return _finishStep(accent);
    }
  }

  // ── Schritte ──────────────────────────────────────────────────────────────
  Widget _welcomeStep(Color accent) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutBack,
              builder: (_, t, child) => Transform.scale(
                scale: 0.7 + 0.3 * t.clamp(0.0, 1.0),
                child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
              ),
              child: Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.3),
                      blurRadius: 36,
                      spreadRadius: -8,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(25),
                  child: Image.asset(
                    'assets/branding/cruiseconnect_icon_foreground.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Willkommen bei\nCruise Connector',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'In wenigen Schritten ist dein Profil bereit und du kannst sofort losfahren.',
            style: TextStyle(color: _muted, fontSize: 16, height: 1.45),
          ),
          const SizedBox(height: 28),
          _welcomePoint(
            accent,
            Icons.route_rounded,
            'Entdecke die schönsten Routen',
            'Kurvenreich, scenic, auf dich zugeschnitten.',
          ),
          _welcomePoint(
            accent,
            Icons.groups_rounded,
            'Cruise mit Freunden',
            'Standort live sehen, gemeinsam navigieren, zusammen fahren.',
          ),
          _welcomePoint(
            accent,
            Icons.emoji_events_rounded,
            'Sammle XP & teile Fahrten',
            'Streaks, Statistiken und Fahrten als Story teilen.',
          ),
        ],
      ),
    );
  }

  Widget _welcomePoint(Color accent, IconData icon, String title, String sub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountStep(Color accent) {
    return _stepShell(
      accent: accent,
      icon: Icons.alternate_email_rounded,
      title: 'Erstelle dein Konto',
      subtitle:
          'E-Mail und Passwort, damit wir dein Profil und deine Fahrten sichern.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('E-Mail-Adresse'),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            inputFormatters: [
              LengthLimitingTextInputFormatter(AppInputLimits.emailMaxLength),
            ],
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: _fieldDeco(
              accent,
              hint: 'deine@email.de',
              prefixIcon: Icon(Icons.email_outlined, color: accent, size: 20),
            ),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Passwort'),
          TextField(
            controller: _pwCtrl,
            obscureText: _obscurePw,
            inputFormatters: [
              LengthLimitingTextInputFormatter(
                AppInputLimits.passwordMaxLength,
              ),
            ],
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: _fieldDeco(
              accent,
              hint: 'Mindestens 6 Zeichen',
              prefixIcon: Icon(Icons.lock_outline, color: accent, size: 20),
              suffix: IconButton(
                icon: Icon(
                  _obscurePw ? Icons.visibility_off : Icons.visibility,
                  color: _muted,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePw = !_obscurePw),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Passwort bestätigen'),
          TextField(
            controller: _confirmCtrl,
            obscureText: _obscureConf,
            inputFormatters: [
              LengthLimitingTextInputFormatter(
                AppInputLimits.passwordMaxLength,
              ),
            ],
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: _fieldDeco(
              accent,
              hint: 'Passwort wiederholen',
              prefixIcon: Icon(Icons.lock_outline, color: accent, size: 20),
              suffix: IconButton(
                icon: Icon(
                  _obscureConf ? Icons.visibility_off : Icons.visibility,
                  color: _muted,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureConf = !_obscureConf),
              ),
            ),
          ),
          if (_accountErr != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF331316),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _err.withValues(alpha: 0.42)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: _err, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _accountErr!,
                      style: const TextStyle(
                        color: Color(0xFFFFB4B4),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _verifyEmailStep(Color accent) {
    return _stepShell(
      accent: accent,
      icon: Icons.mark_email_read_rounded,
      title: 'Bestätige deine E-Mail',
      subtitle:
          'Wir haben dir einen sechsstelligen Code an $_pendingEmail geschickt. '
          'Gib ihn hier ein, du bleibst angemeldet und machst direkt weiter.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('Sechsstelliger Code'),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            textAlign: TextAlign.center,
            maxLength: 6,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: 14,
            ),
            decoration: _fieldDeco(
              accent,
              hint: '••••••',
            ).copyWith(counterText: ''),
            onChanged: (v) {
              if (_codeErr != null) setState(() => _codeErr = null);
              // Auto-Bestätigung, sobald 6 Ziffern da sind — kein Extra-Tap.
              if (v.trim().length == 6 && !_busy) _next();
            },
            onSubmitted: (_) {
              if (!_busy) _next();
            },
          ),
          const SizedBox(height: 12),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: _muted, size: 16),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Keine Mail erhalten? Sieh auch im Spamordner nach.',
                  style: TextStyle(color: _muted, fontSize: 12.5, height: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(
                onPressed: (_resendIn > 0 || _busy) ? null : _resendCode,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _resendIn > 0
                      ? 'Code erneut senden ($_resendIn s)'
                      : 'Code erneut senden',
                  style: TextStyle(
                    color: _resendIn > 0 ? _muted : accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const Spacer(),
              // Tippfehler in der Adresse? Direkt zurück zum Account-Schritt.
              TextButton(
                onPressed: _busy ? null : _handleBack,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'E-Mail-Adresse ändern',
                  style: TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (_codeErr != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF331316),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _err.withValues(alpha: 0.42)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: _err, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _codeErr!,
                      style: const TextStyle(
                        color: Color(0xFFFFB4B4),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _usernameStep(Color accent) {
    return _stepShell(
      accent: accent,
      icon: Icons.tag_rounded,
      title: 'Wähl deinen Nutzernamen',
      subtitle:
          'Er ist einmalig, daran finden dich andere. 3 bis 20 Zeichen, '
          'Buchstaben (auch ä ö ü ß), Zahlen und Unterstrich.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _usernameCtrl,
            onChanged: _onUsernameChanged,
            autocorrect: false,
            // 2026-08-25: Eigene Filterliste raus. Sie liess Umlaute beim
            // TIPPEN verschwinden — der Nutzer drückt „ü" und es passiert
            // nichts, er hält seine Tastatur für kaputt. Ab jetzt dieselbe
            // Liste wie im Profil-Bearbeiten, damit nicht wieder eine der
            // beiden Stellen vergessen wird.
            inputFormatters: AppInputLimits.usernameFormatters,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            decoration: _fieldDeco(
              accent,
              hint: 'deinname',
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 14, right: 2),
                child: Text('@', style: TextStyle(color: accent, fontSize: 20)),
              ),
              prefixTight: true,
              suffix: _uStatusIcon(),
            ),
          ),
          const SizedBox(height: 10),
          _uStatusLine(),
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Vorschläge:',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _suggestions
                  .map(
                    (s) => GestureDetector(
                      onTap: () {
                        _usernameCtrl.text = s;
                        _usernameCtrl.selection = TextSelection.collapsed(
                          offset: s.length,
                        );
                        _onUsernameChanged(s);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          '@$s',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget? _uStatusIcon() {
    switch (_uState) {
      case _UNameState.checking:
        return const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _muted),
          ),
        );
      case _UNameState.available:
        return const Icon(Icons.check_circle, color: _ok);
      case _UNameState.taken:
      case _UNameState.reserved:
      case _UNameState.invalid:
        return const Icon(Icons.cancel, color: _err);
      default:
        return null;
    }
  }

  Widget _uStatusLine() {
    final (String text, Color color) = switch (_uState) {
      _UNameState.available => (
        '@${_usernameCtrl.text.trim()} ist frei 🎉',
        _ok,
      ),
      // 2026-08-25: „Schon vergeben" allein verwirrt, seit Umlaute erlaubt
      // sind. Wer „müller" tippt und „mueller" nie gesehen hat, versteht
      // sonst nicht, womit sein Name kollidiert.
      // 2026-08-28 (Fehler 3, Wunsch des Betreibers): Wer hier landet, ist
      // oft der INHABER des Namens mit einem zweiten Anlauf zur
      // Registrierung. Die Meldung sagt ihm jetzt den richtigen Weg.
      // 2026-08-31 (Vucko: „wenn der Nutzername schon vergeben ist, dann soll
      // eine gute Meldung unter dem Textfeld sein"): Die Absage steht jetzt
      // im ERSTEN Satz und ist auf einen Blick lesbar. Der Hinweis fuer den
      // Inhaber kommt danach, er hilft nur einem Teil der Leute. Vorschlaege
      // stehen ohnehin direkt darunter.
      _UNameState.taken => (
        'Der Name ist schon vergeben. Nimm einen der Vorschläge, oder melde '
            'dich an, falls das dein Konto ist.'
            '${AppInputLimits.usernameFoldingHint(_usernameCtrl.text)}',
        _err,
      ),
      _UNameState.reserved => (
        'Der Name ist reserviert und kann nicht vergeben werden. Nimm einen '
            'der Vorschläge.',
        _err,
      ),
      _UNameState.invalid => (
        '3 bis 20 Zeichen: Buchstaben (auch ä ö ü ß), Zahlen, _ '
            '(kein __, nicht mit _ beginnen oder enden).',
        _muted,
      ),
      _UNameState.checking => ('Prüfe Verfügbarkeit…', _muted),
      // 2026-08-31: Der alte Text liess offen, wie es weitergeht — und weil
      // „Weiter" gesperrt war, sass der Nutzer fest. Jetzt sagt er, was zu
      // tun ist, und der Knopf funktioniert.
      _UNameState.error => (
        'Wir konnten den Namen gerade nicht prüfen. Tippe auf Weiter, wir '
            'versuchen es dann.',
        _muted,
      ),
      _UNameState.idle => ('', _muted),
    };
    if (text.isEmpty) return const SizedBox(height: 4);
    return Text(text, style: TextStyle(color: color, fontSize: 13.5));
  }

  Widget _displayStep(Color accent) {
    return _stepShell(
      accent: accent,
      icon: Icons.badge_rounded,
      title: 'Wie sollen dich\nandere sehen?',
      subtitle:
          'Dein Anzeigename ohne @. Den kannst du jederzeit ändern, dein '
          'Nutzername bleibt fest.',
      child: TextField(
        controller: _displayCtrl,
        textCapitalization: TextCapitalization.words,
        inputFormatters: [LengthLimitingTextInputFormatter(40)],
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        decoration: _fieldDeco(accent, hint: 'Max Mustermann'),
      ),
    );
  }

  Widget _regionStep(Color accent) {
    return _stepShell(
      accent: accent,
      icon: Icons.public_rounded,
      title: 'Wo cruisst du?',
      subtitle: 'Hilft uns, dir die besten Routen in deiner Nähe zu zeigen.',
      child: Column(
        children: _countries.map((c) {
          final selected = _country == c.$1;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => setState(() => _country = c.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: selected ? accent.withValues(alpha: 0.14) : _card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? accent : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      c.$2,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (selected)
                      Icon(Icons.check_circle, color: accent, size: 22),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _photoStep(Color accent) {
    return _stepShell(
      accent: accent,
      icon: Icons.add_a_photo_rounded,
      title: 'Zeig dich',
      subtitle: 'Ein Profilbild macht dein Profil persönlich. (Optional)',
      child: Center(
        child: GestureDetector(
          onTap: _busy ? null : _pickPhoto,
          child: Column(
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: _card,
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                  image: _avatarBytes != null
                      ? DecorationImage(
                          image: MemoryImage(_avatarBytes!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _avatarBytes == null
                    ? const Icon(
                        Icons.add_a_photo_outlined,
                        color: _muted,
                        size: 40,
                      )
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                _avatarBytes == null ? 'Foto auswählen' : 'Foto ändern',
                style: TextStyle(color: accent, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _garageStep(Color accent) {
    return _stepShell(
      accent: accent,
      icon: Icons.garage_rounded,
      title: 'Was fährst du?',
      subtitle: 'Füg dein erstes Fahrzeug zur Garage hinzu. (Optional)',
      child: Column(
        children: [
          TextField(
            controller: _carBrandCtrl,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(40)],
            style: const TextStyle(color: Colors.white, fontSize: 17),
            decoration: _fieldDeco(accent, hint: 'Marke (z.B. BMW)'),
          ),
          _markenVorschlaege(accent),
          const SizedBox(height: 12),
          TextField(
            controller: _carNameCtrl,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(40)],
            style: const TextStyle(color: Colors.white, fontSize: 17),
            decoration: _fieldDeco(accent, hint: 'Modell (z.B. M3)'),
          ),
        ],
      ),
    );
  }

  /// 2026-08-24 (Aufgabe 2.1): Vorschläge unter dem Marken-Feld.
  ///
  /// Vucko wörtlich: „B-M-W ganz in Caps geschrieben und groß geschrieben
  /// soll das Gleiche sein wie B groß, M klein und W klein [...] Wichtig
  /// ist, dass das [wortident] ist."
  ///
  /// Warum das hier hingehört und nicht nur in die Garage: dieses Feld war
  /// bis heute ein blankes Textfeld ohne jeden Vorschlag. In der
  /// Bearbeiten-Seite gibt es seit jeher eine Vorschlagsliste, hier nicht.
  /// Gemessen am 24.08. in der Produktivdatenbank: 128 Profile mit Marke,
  /// 48 verschiedene Schreibweisen. Neue Schreibweisen entstehen hier
  /// schneller, als eine Migration sie aufräumen kann. Der Trigger auf
  /// `profiles.car_brand` fängt die bekannten Fälle ab, aber ein Tippfehler
  /// bleibt ein Tippfehler.
  ///
  /// BEWUSST ohne Netz: die gepflegte Liste aus VehicleApiService liegt im
  /// Code. Das Onboarding darf an keiner Stelle auf eine Antwort warten.
  Widget _markenVorschlaege(Color accent) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _carBrandCtrl,
      builder: (context, wert, _) {
        final getippt = wert.text.trim().toLowerCase();
        // Die sechs häufigsten Marken der Nutzerschaft, gemessen am
        // 24.08. über get_brand_overview: BMW 30 Personen, Volkswagen 16,
        // Audi 14, Beta 8, Mercedes-Benz 7, Skoda 6.
        const haeufig = [
          'BMW',
          'Volkswagen',
          'Audi',
          'Beta',
          'Mercedes-Benz',
          'Skoda',
        ];
        final List<String> vorschlaege;
        if (getippt.length < 2) {
          vorschlaege = haeufig;
        } else {
          vorschlaege = [
            for (final make in VehicleApiService.kuratierteMarken)
              if (make.name.toLowerCase().startsWith(getippt)) make.name,
          ].take(6).toList();
        }
        // Genau getroffen: dann ist der Vorschlag nur noch Lärm.
        if (vorschlaege.length == 1 &&
            vorschlaege.first.toLowerCase() == getippt) {
          return const SizedBox(height: 8);
        }
        if (vorschlaege.isEmpty) return const SizedBox(height: 8);
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: vorschlaege.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final marke = vorschlaege[i];
                return GestureDetector(
                  onTap: () {
                    _carBrandCtrl.value = TextEditingValue(
                      text: marke,
                      selection: TextSelection.collapsed(offset: marke.length),
                    );
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: accent.withValues(alpha: 0.30)),
                    ),
                    child: Text(
                      marke,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _finishStep(Color accent) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (_, t, child) =>
                Transform.scale(scale: t.clamp(0.0, 1.2), child: child),
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 40,
                    spreadRadius: -6,
                  ),
                ],
              ),
              child: Icon(Icons.check_rounded, color: accent, size: 68),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Alles bereit!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Dein Profil steht. Finde Freunde in der Community, plane deine '
            'erste Route und ab auf die Straße.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 16, height: 1.45),
          ),
          _mitfahrerListe(accent),
        ],
      ),
    );
  }

  /// „Finde Mitfahrer" — Vorschlaege direkt zum Folgen.
  ///
  /// Zeigt sich NUR, wenn es wirklich jemanden gibt. Kein Ladekringel, kein
  /// Leertext: Bei einer jungen App ist die Liste oft leer, und ein leerer
  /// Kasten im Abschluss-Schritt waere schlechter als gar keiner.
  Widget _mitfahrerListe(Color accent) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _mitfahrerVorschlaege,
      builder: (context, snap) {
        final leute = snap.data ?? const <Map<String, dynamic>>[];
        if (snap.connectionState != ConnectionState.done || leute.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 30),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Fahrer in deiner Nähe',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Folge ein paar Leuten. Dann ist die Community von Anfang an '
                'lebendig.',
                style: TextStyle(color: _muted, fontSize: 13, height: 1.35),
              ),
            ),
            const SizedBox(height: 14),
            for (final person in leute.take(5)) _mitfahrerZeile(person, accent),
          ],
        );
      },
    );
  }

  Widget _mitfahrerZeile(Map<String, dynamic> person, Color accent) {
    final id = (person['id'] as String?) ?? '';
    final handle = SocialService.publicHandle(person, fallbackUserId: id);
    final grund = SocialService.mutualFollowersLine(person) ?? 'Neu dabei';
    final schonGefolgt = _gefolgt.contains(id);
    final laeuft = _folgenLaeuft.contains(id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          UserAvatar(
            name: handle,
            avatarUrl: person['avatar_url'] as String?,
            radius: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  handle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  grund,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: schonGefolgt
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.check_rounded,
                      color: Color(0xFF2ECC71),
                      size: 20,
                    ),
                  )
                : OutlinedButton(
                    onPressed: (laeuft || id.isEmpty)
                        ? null
                        : () => _folgeMitfahrer(id),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      side: BorderSide(color: accent.withValues(alpha: 0.6)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Folgen',
                      style: TextStyle(
                        color: accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Folgen ist bewusst „optimistisch": Der Haken erscheint sofort. Schlaegt es
  /// fehl, wird er still zurueckgenommen — im Onboarding jemandem eine
  /// Fehlermeldung vorzusetzen, waere der falsche Moment.
  Future<void> _folgeMitfahrer(String id) async {
    setState(() => _folgenLaeuft.add(id));
    try {
      await SocialService.followUser(id).timeout(_netzZeitgrenze);
      if (!mounted) return;
      setState(() {
        _gefolgt.add(id);
        _folgenLaeuft.remove(id);
      });
    } catch (e) {
      debugPrint('[Onboarding] Folgen fehlgeschlagen: $e');
      if (!mounted) return;
      setState(() => _folgenLaeuft.remove(id));
    }
  }

  // ── Bausteine ──────────────────────────────────────────────────────────────
  Widget _stepShell({
    required Color accent,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: accent, size: 26),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: _muted, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 26),
          child,
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6, left: 2),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  InputDecoration _fieldDeco(
    Color accent, {
    required String hint,
    Widget? prefixIcon,
    Widget? suffix,
    bool prefixTight = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF555E70)),
      filled: true,
      fillColor: _card,
      prefixIcon: prefixIcon,
      prefixIconConstraints: prefixTight
          ? const BoxConstraints(minWidth: 0, minHeight: 0)
          : null,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
    );
  }
}
