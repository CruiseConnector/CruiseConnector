// Passwort vergessen — 3 Schritte in einer Seite.
//
// 2026-08-02 (vucko): E-Mail eingeben → 6-stelligen Code aus der Mail tippen →
// neues Passwort setzen → direkt angemeldet weiter in die App. Bewusst OHNE
// Magic-Link: der Code-Weg ist derselbe, den das Onboarding schon nutzt, und
// er überlebt Browser-Wechsel und Deep-Link-Races.
//
// Erreichbar von zwei Stellen:
//   * Login-Seite („Passwort vergessen?")
//   * Einstellungen → Passwort ändern → „Passwort vergessen?" (autoSend: true)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/auth_service.dart';
import 'package:cruise_connect/presentation/pages/legal_gate_page.dart';
import 'package:cruise_connect/presentation/pages/onboarding/post_auth_gate.dart';

const _authBackground = Color(0xFF0D141E);
const _authField = Color(0xFF1A2432);
const _authBorder = Color(0xFF344156);
const _authTextMuted = Color(0xFFB6BECC);
const _authError = Color(0xFFFF6B6B);

enum _ResetStep { email, code, password, done }

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({
    super.key,
    this.initialEmail,
    this.autoSend = false,
  });

  /// Vorbelegte Adresse (aus dem Login-Feld oder vom angemeldeten Konto).
  final String? initialEmail;

  /// Code sofort beim Öffnen anfordern und direkt im Code-Schritt starten.
  /// Wird aus den Einstellungen genutzt — die Adresse ist dort schon bekannt.
  final bool autoSend;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordRepeatCtrl = TextEditingController();

  _ResetStep _step = _ResetStep.email;
  bool _busy = false;
  bool _obscure = true;
  String? _errorMsg;
  String _sentToEmail = '';

  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = widget.initialEmail?.trim() ?? '';
    if (widget.autoSend && AppInputLimits.looksLikeEmail(_emailCtrl.text)) {
      // Adresse steht fest → Code direkt anfordern, Nutzer landet im Code-Feld.
      WidgetsBinding.instance.addPostFrameCallback((_) => _sendCode());
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordRepeatCtrl.dispose();
    super.dispose();
  }

  // ── Schritt 1: Code anfordern ─────────────────────────────────────────────
  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (!AppInputLimits.looksLikeEmail(email)) {
      setState(() => _errorMsg = 'Bitte gib eine gültige E-Mail-Adresse ein.');
      return;
    }

    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      await AuthService.sendPasswordResetCode(email);
      if (!mounted) return;
      setState(() {
        _sentToEmail = email;
        _step = _ResetStep.code;
        _codeCtrl.clear();
      });
      _startResendCooldown();
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMsg = _translateError(e));
    } catch (e) {
      debugPrint('[ForgotPassword] sendCode Fehler: $e');
      if (mounted) {
        setState(
          () => _errorMsg =
              'Der Code konnte nicht gesendet werden. Bitte erneut versuchen.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendCode() async {
    if (_resendIn > 0 || _busy) return;
    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      await AuthService.sendPasswordResetCode(_sentToEmail);
      _startResendCooldown();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Neuer Code gesendet. Schau in dein Postfach.'),
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMsg = _translateError(e));
      // Beim Versandlimit länger sperren, damit nicht weiter dagegen getippt wird.
      if (_isRateLimited(e)) _startResendCooldown(180);
    } catch (e) {
      debugPrint('[ForgotPassword] resend Fehler: $e');
      if (mounted) {
        setState(
          () => _errorMsg = 'Konnte keinen neuen Code senden. Bitte kurz warten.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Schritt 2: Code prüfen ────────────────────────────────────────────────
  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 6) {
      setState(() => _errorMsg = 'Bitte gib den 6-stelligen Code ein.');
      return;
    }

    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      await AuthService.verifyPasswordResetCode(
        email: _sentToEmail,
        token: code,
      );
      if (!mounted) return;
      if (AuthService.currentUser == null) {
        setState(() => _errorMsg = 'Code ungültig oder abgelaufen.');
        return;
      }
      setState(() => _step = _ResetStep.password);
      _resendTimer?.cancel();
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMsg = _translateError(e));
    } catch (e) {
      debugPrint('[ForgotPassword] verifyCode Fehler: $e');
      if (mounted) {
        setState(
          () => _errorMsg = 'Bestätigung fehlgeschlagen. Bitte erneut versuchen.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Schritt 3: neues Passwort setzen ──────────────────────────────────────
  Future<void> _savePassword() async {
    final password = _passwordCtrl.text;
    if (!AppInputLimits.isValidPassword(password)) {
      setState(
        () => _errorMsg =
            'Passwort muss mindestens ${AppInputLimits.passwordMinLength} Zeichen haben.',
      );
      return;
    }
    if (password != _passwordRepeatCtrl.text) {
      setState(() => _errorMsg = 'Passwörter stimmen nicht überein.');
      return;
    }

    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      await AuthService.updatePassword(password);
      if (!mounted) return;
      setState(() => _step = _ResetStep.done);
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMsg = _translateError(e));
    } catch (e) {
      debugPrint('[ForgotPassword] savePassword Fehler: $e');
      if (mounted) {
        setState(
          () => _errorMsg =
              'Passwort konnte nicht gespeichert werden. Bitte erneut versuchen.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish() {
    // Nach dem Reset besteht bereits eine gültige Session → direkt in die App,
    // kein erneutes Anmelden. Der Legal-Gate-Wrapper bleibt wie beim Login.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LegalGatePage(child: PostAuthGate()),
      ),
      (route) => false,
    );
  }

  // 60 s spiegeln Supabases „Minimum interval per user" (SMTP-Settings). Wäre
  // der App-Cooldown kürzer, liefe der Nutzer beim „Erneut senden" in ein 429
  // vom Server, obwohl der Button aktiv aussieht.
  void _startResendCooldown([int seconds = 60]) {
    _resendTimer?.cancel();
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

  bool _isRateLimited(AuthException e) {
    final m = e.message.toLowerCase();
    return e.statusCode == '429' ||
        m.contains('rate limit') ||
        m.contains('security purposes') ||
        m.contains('too many requests');
  }

  String _translateError(AuthException e) {
    final m = e.message.toLowerCase();
    if (_isRateLimited(e)) {
      return 'Zu viele E-Mails in kurzer Zeit. Bitte warte ein paar Minuten.';
    }
    if (m.contains('expired')) {
      return 'Der Code ist abgelaufen. Fordere einen neuen an.';
    }
    if (m.contains('invalid') || m.contains('incorrect')) {
      return 'Der Code stimmt nicht. Bitte prüfe die Ziffern.';
    }
    if (m.contains('password should be') || m.contains('weak')) {
      return 'Passwort zu schwach. Mindestens ${AppInputLimits.passwordMinLength} Zeichen.';
    }
    if (m.contains('same password') || m.contains('should be different')) {
      return 'Das ist dein bisheriges Passwort. Bitte wähle ein neues.';
    }
    if (m.contains('session') || m.contains('jwt')) {
      return 'Sitzung abgelaufen. Bitte fordere einen neuen Code an.';
    }
    return 'Das hat nicht geklappt. Bitte erneut versuchen.';
  }

  void _backToEmailStep() {
    _resendTimer?.cancel();
    setState(() {
      _step = _ResetStep.email;
      _resendIn = 0;
      _errorMsg = null;
      _codeCtrl.clear();
    });
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final brand = AppAccentColors.accent;

    return Scaffold(
      backgroundColor: _authBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _busy
              ? null
              : () {
                  // Im Code-Schritt führt Zurück erst zur Adresse (Tippfehler),
                  // sonst raus aus dem Reset.
                  if (_step == _ResetStep.code) {
                    _backToEmailStep();
                  } else {
                    Navigator.pop(context);
                  }
                },
        ),
        title: const Text(
          'Passwort zurücksetzen',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(brand),
              const SizedBox(height: 28),
              switch (_step) {
                _ResetStep.email => _emailStep(brand),
                _ResetStep.code => _codeStep(brand),
                _ResetStep.password => _passwordStep(brand),
                _ResetStep.done => _doneStep(brand),
              },
              if (_errorMsg != null) ...[
                const SizedBox(height: 14),
                _errorBox(_errorMsg!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(Color brand) {
    final (icon, title, subtitle) = switch (_step) {
      _ResetStep.email => (
        Icons.lock_reset_rounded,
        'Passwort vergessen?',
        'Gib deine E-Mail-Adresse ein. Wir schicken dir einen 6-stelligen '
            'Code, mit dem du ein neues Passwort setzt.',
      ),
      _ResetStep.code => (
        Icons.mark_email_read_rounded,
        'Code eingeben',
        'Falls ein Konto mit $_sentToEmail existiert, haben wir dir einen '
            '6-stelligen Code geschickt.',
      ),
      _ResetStep.password => (
        Icons.password_rounded,
        'Neues Passwort',
        'Wähl ein neues Passwort — mindestens '
            '${AppInputLimits.passwordMinLength} Zeichen.',
      ),
      _ResetStep.done => (
        Icons.check_circle_rounded,
        'Passwort geändert',
        'Dein neues Passwort ist aktiv und du bist angemeldet. '
            'Beim nächsten Login nutzt du das neue Passwort.',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Color.lerp(_authField, brand, 0.16),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: brand.withValues(alpha: 0.28)),
          ),
          child: Icon(icon, color: brand, size: 28),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(
            color: _authTextMuted,
            fontSize: 14.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _emailStep(Color brand) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('E-Mail Adresse'),
        _inputField(
          controller: _emailCtrl,
          icon: Icons.email_outlined,
          hint: 'deine@email.de',
          keyboardType: TextInputType.emailAddress,
          maxLength: AppInputLimits.emailMaxLength,
          autofillHints: const [AutofillHints.email],
          onSubmitted: (_) => _busy ? null : _sendCode(),
        ),
        const SizedBox(height: 26),
        _primaryButton('Code senden', _sendCode, brand),
      ],
    );
  }

  Widget _codeStep(Color brand) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('6-stelliger Code'),
        Container(
          decoration: _fieldBox(),
          child: TextField(
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
            cursorColor: brand,
            decoration: _fieldDeco(brand, hint: '••••••').copyWith(
              counterText: '',
            ),
            onChanged: (v) {
              if (_errorMsg != null) setState(() => _errorMsg = null);
              // Auto-Bestätigung bei 6 Ziffern — kein Extra-Tap (wie im Onboarding).
              if (v.trim().length == 6 && !_busy) _verifyCode();
            },
            onSubmitted: (_) => _busy ? null : _verifyCode(),
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: _authTextMuted, size: 16),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Keine Mail erhalten? Sieh auch im Spam-Ordner nach.',
                style: TextStyle(
                  color: _authTextMuted,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
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
                  color: _resendIn > 0 ? _authTextMuted : brand,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: _busy ? null : _backToEmailStep,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'E-Mail-Adresse ändern',
                style: TextStyle(
                  color: _authTextMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _primaryButton('Weiter', _verifyCode, brand),
      ],
    );
  }

  Widget _passwordStep(Color brand) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Neues Passwort'),
        _inputField(
          controller: _passwordCtrl,
          icon: Icons.lock_outline,
          hint: '••••••••',
          obscure: _obscure,
          maxLength: AppInputLimits.passwordMaxLength,
          autofocus: true,
          autofillHints: const [AutofillHints.newPassword],
          suffixIcon: IconButton(
            icon: Icon(
              _obscure ? Icons.visibility_off : Icons.visibility,
              color: brand.withValues(alpha: 0.76),
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        const SizedBox(height: 18),
        _label('Neues Passwort bestätigen'),
        _inputField(
          controller: _passwordRepeatCtrl,
          icon: Icons.lock_outline,
          hint: 'Passwort wiederholen',
          obscure: _obscure,
          maxLength: AppInputLimits.passwordMaxLength,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _busy ? null : _savePassword(),
        ),
        const SizedBox(height: 26),
        _primaryButton('Passwort speichern', _savePassword, brand),
      ],
    );
  }

  Widget _doneStep(Color brand) {
    return _primaryButton('Weiter zur App', _finish, brand);
  }

  Widget _primaryButton(String text, VoidCallback onPressed, Color brand) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _authBorder,
          disabledForegroundColor: Colors.white54,
          elevation: 5,
          shadowColor: brand.withValues(alpha: 0.28),
          shape: const StadiumBorder(),
        ),
        child: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                text,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF331316),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _authError.withValues(alpha: 0.42)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: _authError, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFFFB4B4), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6, left: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        color: Colors.white,
        fontSize: 14,
      ),
    ),
  );

  BoxDecoration _fieldBox() => BoxDecoration(
    color: _authField,
    borderRadius: BorderRadius.circular(15),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.16),
        blurRadius: 14,
        spreadRadius: -4,
        offset: const Offset(0, 8),
      ),
    ],
  );

  InputDecoration _fieldDeco(Color accent, {required String hint}) {
    return InputDecoration(
      counterText: '',
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF8993A3)),
      filled: true,
      fillColor: _authField,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: _authBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: accent.withValues(alpha: 0.92), width: 1.6),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: _authBorder),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    bool obscure = false,
    bool autofocus = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    int? maxLength,
    List<String>? autofillHints,
    ValueChanged<String>? onSubmitted,
  }) {
    final accent = AppAccentColors.accent;
    return Container(
      decoration: _fieldBox(),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        autofocus: autofocus,
        keyboardType: keyboardType,
        maxLength: maxLength,
        autofillHints: autofillHints,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        cursorColor: accent,
        onChanged: (_) {
          if (_errorMsg != null) setState(() => _errorMsg = null);
        },
        onSubmitted: onSubmitted,
        decoration: _fieldDeco(accent, hint: hint).copyWith(
          prefixIcon: Icon(icon, color: accent.withValues(alpha: 0.92), size: 20),
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }
}
