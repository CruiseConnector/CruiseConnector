// Passwort ändern — Einstellungen → Konto & Privatsphäre.
//
// 2026-08-02 (vucko): Vorher war der Menüpunkt ein toter Button (ListTile ohne
// onTap). Zwei Fälle:
//   * Konto MIT E-Mail-Identität → aktuelles Passwort prüfen, dann neues setzen.
//   * Reines Google-/Apple-Konto  → es gibt kein altes Passwort, also wird eins
//     *gesetzt*. Danach ist zusätzlich der E-Mail-Login möglich.
// Wer sein altes Passwort nicht mehr weiß, geht über den Reset-Code-Weg
// (ForgotPasswordPage) — dieselbe Mechanik wie auf der Login-Seite.

import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/auth_service.dart';
import 'package:cruise_connect/presentation/pages/forgot_password_page.dart';

const _bg = Color(0xFF0B0E14);
const _card = Color(0xFF141A24);
const _border = Color(0xFF283345);
const _muted = Color(0xFFB6BECC);
const _errorColor = Color(0xFFFF6B6B);

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _repeatCtrl = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  bool _obscure = true;
  bool _hasPassword = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _repeatCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadIdentity() async {
    try {
      final hasEmail = await AuthService.hasEmailIdentity();
      if (!mounted) return;
      setState(() {
        _hasPassword = hasEmail;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[ChangePassword] Identitäten laden fehlgeschlagen: $e');
      // Im Zweifel den strengeren Weg gehen (altes Passwort abfragen).
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final current = _currentCtrl.text;
    final next = _newCtrl.text;

    if (_hasPassword && current.isEmpty) {
      setState(() => _errorMsg = 'Bitte gib dein aktuelles Passwort ein.');
      return;
    }
    if (!AppInputLimits.isValidPassword(next)) {
      setState(
        () => _errorMsg =
            'Passwort muss mindestens ${AppInputLimits.passwordMinLength} Zeichen haben.',
      );
      return;
    }
    if (next != _repeatCtrl.text) {
      setState(() => _errorMsg = 'Passwörter stimmen nicht überein.');
      return;
    }
    if (_hasPassword && current == next) {
      setState(() => _errorMsg = 'Das neue Passwort ist dein bisheriges.');
      return;
    }

    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      if (_hasPassword) {
        final ok = await AuthService.verifyCurrentPassword(current);
        if (!ok) {
          if (mounted) {
            setState(() => _errorMsg = 'Aktuelles Passwort ist falsch.');
          }
          return;
        }
      }
      await AuthService.updatePassword(next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _hasPassword
                ? 'Passwort geändert.'
                : 'Passwort gesetzt. Du kannst dich jetzt auch mit E-Mail anmelden.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[ChangePassword] Speichern fehlgeschlagen: $e');
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

  Future<void> _openReset() async {
    final email = AuthService.currentUser?.email;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordPage(
          initialEmail: email,
          // Adresse ist bekannt → Code direkt anfordern, kein zweites Tippen.
          autoSend: email != null && email.isNotEmpty,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
        title: Text(
          _hasPassword ? 'Passwort ändern' : 'Passwort festlegen',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: accent))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hasPassword
                          ? 'Zur Sicherheit brauchen wir einmal dein aktuelles Passwort.'
                          : 'Dein Konto läuft bisher über Google oder Apple. Leg ein '
                                'Passwort fest, um dich zusätzlich mit E-Mail anmelden zu können.',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 14.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_hasPassword) ...[
                      _label('Aktuelles Passwort'),
                      _field(
                        controller: _currentCtrl,
                        hint: '••••••••',
                        obscure: _obscure,
                        autofillHints: const [AutofillHints.password],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : _openReset,
                          style: TextButton.styleFrom(
                            foregroundColor: accent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Passwort vergessen?',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    _label('Neues Passwort'),
                    _field(
                      controller: _newCtrl,
                      hint: '••••••••',
                      obscure: _obscure,
                      autofillHints: const [AutofillHints.newPassword],
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: accent.withValues(alpha: 0.76),
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    const SizedBox(height: 16),

                    _label('Neues Passwort bestätigen'),
                    _field(
                      controller: _repeatCtrl,
                      hint: 'Passwort wiederholen',
                      obscure: _obscure,
                      autofillHints: const [AutofillHints.newPassword],
                      onSubmitted: (_) => _busy ? null : _save(),
                    ),

                    if (_errorMsg != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF331316),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _errorColor.withValues(alpha: 0.42),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: _errorColor,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMsg!,
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

                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _border,
                          disabledForegroundColor: Colors.white54,
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
                                _hasPassword
                                    ? 'Passwort ändern'
                                    : 'Passwort festlegen',
                                style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
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

  Widget _field({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    Widget? suffixIcon,
    List<String>? autofillHints,
    ValueChanged<String>? onSubmitted,
  }) {
    final accent = AppAccentColors.accent;
    return TextField(
      controller: controller,
      obscureText: obscure,
      maxLength: AppInputLimits.passwordMaxLength,
      autofillHints: autofillHints,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      cursorColor: accent,
      onChanged: (_) {
        if (_errorMsg != null) setState(() => _errorMsg = null);
      },
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF8993A3)),
        filled: true,
        fillColor: _card,
        prefixIcon: Icon(
          Icons.lock_outline,
          color: accent.withValues(alpha: 0.92),
          size: 20,
        ),
        suffixIcon: suffixIcon,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: accent.withValues(alpha: 0.92),
            width: 1.6,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
    );
  }
}
