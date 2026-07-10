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
import 'package:cruise_connect/data/services/map_style_service.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/home_page.dart';
import 'package:cruise_connect/presentation/pages/legal_acceptance_page.dart';
import 'package:cruise_connect/presentation/pages/welcome_page.dart';
import 'package:cruise_connect/presentation/widgets/photo/ride_photo_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _bg = Color(0xFF0B0E14);
const Color _card = Color(0xFF171B26);
const Color _muted = Color(0xFF8A93A6);
const Color _ok = Color(0xFF2ECC71);
const Color _err = Color(0xFFE74C3C);

enum _UNameState { idle, checking, available, taken, reserved, invalid, error }

enum _Step {
  welcome,
  account,
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
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
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
      final res = await SocialService.isUsernameAvailable(v);
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

  bool get _canLeaveUsernamePage =>
      _uState == _UNameState.available || _committedUsername != null;

  Future<bool> _commitUsername() async {
    final v = _usernameCtrl.text.trim();
    if (_committedUsername == v) return true;
    setState(() => _busy = true);
    try {
      final res = await SocialService.setUsername(v);
      if (res.ok) {
        _committedUsername = v;
        return true;
      }
      _showError(
        UsernameChangeException(
          res.error ?? 'unknown',
          daysRemaining: res.daysRemaining,
        ).message,
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
    final legalAcceptance = await LegalAcceptancePage.requestPreAuth(
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
      );
      if (AuthService.currentUser == null) {
        // E-Mail-Bestätigung nötig (Autoconfirm aus): hier kann der Wizard nicht
        // live weiterschreiben → ehrlich hinweisen.
        setState(
          () => _accountErr =
              'Bitte bestätige deine E-Mail und melde dich anschließend an.',
        );
        return false;
      }
      _accountCreated = true;
      return true;
    } on AuthException catch (e) {
      setState(() => _accountErr = _translateAuthError(e.message));
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
    if (m.contains('already registered') || m.contains('already exists')) {
      return 'Diese E-Mail ist bereits registriert.';
    }
    if (m.contains('password should be')) {
      return 'Passwort zu schwach. Mindestens 6 Zeichen.';
    }
    if (m.contains('invalid email')) return 'Ungültige E-Mail-Adresse.';
    return 'Registrierung fehlgeschlagen. Bitte erneut versuchen.';
  }

  // ── Navigation ───────────────────────────────────────────────────────────
  Future<void> _next() async {
    switch (_current) {
      case _Step.account:
        if (!await _createAccount()) return;
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
          await SocialService.setDisplayName(name);
        } catch (_) {
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
      await AuthService.signOut();
    } catch (_) {}
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
          );
        } catch (_) {}
      }
      await SocialService.completeOnboarding(
        countryCode: _country == 'Andere' ? null : _country,
        region: _country,
        language: 'de',
      );
    } catch (_) {
      // Onboarding darf nie hängen bleiben — im Zweifel weiter zur App.
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
      await SocialService.uploadAvatar(bytes);
    } catch (_) {
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
            'Live-Standort, Gruppen-Navigation, gemeinsam fahren.',
          ),
          _welcomePoint(
            accent,
            Icons.emoji_events_rounded,
            'Sammle XP & teile Fahrten',
            'Streaks, Statistiken und Story-Sharing.',
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
          _fieldLabel('E-Mail Adresse'),
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

  Widget _usernameStep(Color accent) {
    return _stepShell(
      accent: accent,
      icon: Icons.tag_rounded,
      title: 'Wähl deinen @-Namen',
      subtitle:
          'Dein eindeutiger Handle, daran finden dich andere. 3 bis 20 Zeichen, '
          'Buchstaben, Zahlen und _.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _usernameCtrl,
            onChanged: _onUsernameChanged,
            autocorrect: false,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
              LengthLimitingTextInputFormatter(
                AppInputLimits.usernameMaxLength,
              ),
            ],
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
      _UNameState.taken => ('Schon vergeben, probier einen Vorschlag.', _err),
      _UNameState.reserved => ('Dieser Name ist reserviert.', _err),
      _UNameState.invalid => (
        '3 bis 20 Zeichen: Buchstaben, Zahlen, _ '
            '(kein __, nicht mit _ beginnen oder enden).',
        _muted,
      ),
      _UNameState.checking => ('Prüfe Verfügbarkeit…', _muted),
      _UNameState.error => ('Konnte gerade nicht prüfen.', _muted),
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
          'Dein Anzeigename ohne @. Den kannst du jederzeit ändern, der '
          '@-Name bleibt fest.',
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
        ],
      ),
    );
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
