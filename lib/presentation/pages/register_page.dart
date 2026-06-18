import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/auth_service.dart';
import 'package:cruise_connect/presentation/pages/home_page.dart';
import 'package:cruise_connect/presentation/pages/login_page.dart';
import 'package:cruise_connect/presentation/widgets/auth_social_buttons.dart';

const _authBackground = Color(0xFF0D141E);
const _authSurface = Color(0xFF151E2A);
const _authField = Color(0xFF1A2432);
const _authBorder = Color(0xFF344156);
const _authTextMuted = Color(0xFFB6BECC);
const _brandMarkAsset = 'assets/branding/cruiseconnect_icon_foreground.png';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _obscure = true;
  bool _obscureConf = true;
  String? _errorMsg;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _continueWithGoogle() async {
    await _runSocialLogin(
      setLoading: (value) => setState(() => _googleLoading = value),
      action: AuthService.signInWithGoogle,
    );
  }

  Future<void> _continueWithApple() async {
    await _runSocialLogin(
      setLoading: (value) => setState(() => _appleLoading = value),
      action: AuthService.signInWithApple,
    );
  }

  Future<void> _runSocialLogin({
    required ValueChanged<bool> setLoading,
    required Future<void> Function() action,
  }) async {
    setLoading(true);
    setState(() => _errorMsg = null);
    try {
      await action();
      if (!mounted) return;
      if (AuthService.currentUser != null) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Anmeldung geoeffnet. Kehre danach zur App zurueck.'),
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMsg = _translateError(e.message));
    } catch (e) {
      debugPrint('[Register] Social Login Fehler: $e');
      if (mounted) {
        setState(
          () => _errorMsg = 'Anmeldung fehlgeschlagen. Bitte erneut versuchen.',
        );
      }
    } finally {
      if (mounted) setLoading(false);
    }
  }

  Future<void> _signUp() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (username.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _errorMsg = 'Bitte alle Felder ausfüllen.');
      return;
    }
    if (!AppInputLimits.isValidUsername(username)) {
      setState(
        () => _errorMsg =
            'Benutzername: 3-${AppInputLimits.usernameMaxLength} Zeichen, nur Buchstaben, Zahlen und _.',
      );
      return;
    }
    if (password != confirm) {
      setState(() => _errorMsg = 'Passwörter stimmen nicht überein.');
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMsg = 'Passwort muss mindestens 6 Zeichen haben.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      await AuthService.signUp(
        email: email,
        password: password,
        username: username,
      );
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: _authSurface,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: AppAccentColors.accent.withValues(alpha: 0.28),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                Icons.mark_email_unread_outlined,
                color: AppAccentColors.accent,
              ),
              const SizedBox(width: 10),
              const Text(
                'E-Mail bestätigen',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
          content: Text(
            'Wir haben eine Bestätigungs-E-Mail an $email gesendet.\n\nBitte öffne die E-Mail und klicke auf den Link, um dein Konto zu aktivieren.',
            style: const TextStyle(color: _authTextMuted),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                try {
                  await AuthService.resendVerificationEmail(email);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Bestaetigungs-E-Mail an $email erneut gesendet.',
                      ),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'E-Mail konnte nicht erneut gesendet werden.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Erneut senden'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Zur Anmeldung',
                style: TextStyle(
                  color: AppAccentColors.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    } on AuthException catch (e) {
      setState(() => _errorMsg = _translateError(e.message));
    } catch (e) {
      debugPrint('[Register] Unerwarteter Fehler: $e');
      setState(
        () =>
            _errorMsg = 'Registrierung fehlgeschlagen. Bitte erneut versuchen.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _translateError(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('already registered') || m.contains('user already exists')) {
      return 'Diese E-Mail ist bereits registriert.';
    }
    if (m.contains('password should be')) {
      return 'Passwort zu schwach. Mindestens 6 Zeichen.';
    }
    if (m.contains('invalid email')) {
      return 'Ungültige E-Mail-Adresse.';
    }
    if (m.contains('abgebrochen') || m.contains('cancel')) {
      return 'Anmeldung abgebrochen.';
    }
    if (m.contains('google login ist noch nicht konfiguriert')) {
      return 'Google Login ist noch nicht fertig konfiguriert.';
    }
    if (m.contains('apple') && m.contains('nicht verfuegbar')) {
      return 'Apple Anmeldung ist auf diesem Geraet nicht verfuegbar.';
    }
    if (m.contains('provider') || m.contains('oauth')) {
      return 'Social Login ist noch nicht vollstaendig konfiguriert.';
    }
    return 'Registrierung fehlgeschlagen. Bitte erneut versuchen.';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final brand = AppAccentColors.accent;
    final headerH = size.height * 0.28;

    return Scaffold(
      backgroundColor: _authBackground,
      body: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(brand, const Color(0xFF202A3A), 0.24)!,
                  Color.lerp(brand, _authBackground, 0.58)!,
                  _authBackground,
                ],
                stops: const [0, 0.52, 1],
              ),
            ),
            child: const SizedBox.expand(),
          ),

          Positioned(
            top: headerH,
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: _authSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
              ),
            ),
          ),

          SingleChildScrollView(
            child: Column(
              children: [
                // ── Header ────────────────────────────────────────────────
                SizedBox(
                  height: headerH,
                  width: double.infinity,
                  child: Padding(
                    padding: EdgeInsets.only(top: padding.top),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.arrow_back_ios,
                                  color: Colors.white,
                                ),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const Spacer(),
                              const Text(
                                'Cruise Connector',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              const SizedBox(width: 50),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          height: 90,
                          width: 90,
                          decoration: BoxDecoration(
                            color: Color.lerp(_authField, brand, 0.10),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: brand.withValues(alpha: 0.26),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: brand.withValues(alpha: 0.20),
                                blurRadius: 22,
                                spreadRadius: -8,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 17,
                              vertical: 24,
                            ),
                            child: Image.asset(
                              _brandMarkAsset,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Formular ─────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: _authSurface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(40),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 36),
                      const Center(
                        child: Text(
                          'Konto erstellen',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Center(
                        child: Text(
                          'Werde Teil der Cruise Connector Community',
                          style: TextStyle(fontSize: 14, color: _authTextMuted),
                        ),
                      ),
                      const SizedBox(height: 24),

                      AuthSocialButtons(
                        googleLoading: _googleLoading,
                        appleLoading: _appleLoading,
                        enabled:
                            !_isLoading && !_googleLoading && !_appleLoading,
                        onGoogle: _continueWithGoogle,
                        onApple: _continueWithApple,
                      ),
                      const SizedBox(height: 22),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            const Expanded(child: Divider(color: _authBorder)),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'oder mit E-Mail',
                                style: TextStyle(
                                  color: _authTextMuted.withValues(alpha: 0.72),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider(color: _authBorder)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      _label('Benutzername'),
                      _inputField(
                        controller: _usernameController,
                        icon: Icons.person_outline,
                        hint: 'DeinFahrername',
                        maxLength: AppInputLimits.usernameMaxLength,
                        inputFormatters: AppInputLimits.usernameFormatters,
                      ),
                      const SizedBox(height: 16),

                      _label('E-Mail Adresse'),
                      _inputField(
                        controller: _emailController,
                        icon: Icons.email_outlined,
                        hint: 'deine@email.de',
                        keyboardType: TextInputType.emailAddress,
                        maxLength: AppInputLimits.emailMaxLength,
                      ),
                      const SizedBox(height: 16),

                      _label('Passwort'),
                      _inputField(
                        controller: _passwordController,
                        icon: Icons.lock_outline,
                        hint: 'Mindestens 6 Zeichen',
                        obscure: _obscure,
                        maxLength: AppInputLimits.passwordMaxLength,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                            color: brand.withValues(alpha: 0.76),
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      const SizedBox(height: 16),

                      _label('Passwort bestätigen'),
                      _inputField(
                        controller: _confirmController,
                        icon: Icons.lock_outline,
                        hint: 'Passwort wiederholen',
                        obscure: _obscureConf,
                        maxLength: AppInputLimits.passwordMaxLength,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConf
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: brand.withValues(alpha: 0.76),
                          ),
                          onPressed: () =>
                              setState(() => _obscureConf = !_obscureConf),
                        ),
                      ),

                      if (_errorMsg != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF331316),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(
                                  0xFFFF6B6B,
                                ).withValues(alpha: 0.42),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Color(0xFFFF6B6B),
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
                        ),

                      const SizedBox(height: 28),

                      SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _signUp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brand,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _authBorder,
                            disabledForegroundColor: Colors.white54,
                            elevation: 5,
                            shadowColor: brand.withValues(alpha: 0.28),
                            shape: const StadiumBorder(),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Registrieren',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 22),

                      Center(
                        child: GestureDetector(
                          onTap: () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginPage(),
                            ),
                          ),
                          child: RichText(
                            text: TextSpan(
                              text: 'Bereits ein Konto? ',
                              style: const TextStyle(
                                color: _authTextMuted,
                                fontSize: 14,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Jetzt anmelden',
                                  style: TextStyle(
                                    color: brand,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 50),
                    ],
                  ),
                ),
              ],
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

  Widget _inputField({
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final accent = AppAccentColors.accent;
    return Container(
      decoration: BoxDecoration(
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
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        maxLength: maxLength,
        inputFormatters: inputFormatters,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        cursorColor: accent,
        decoration: InputDecoration(
          counterText: '',
          prefixIcon: Icon(
            icon,
            color: accent.withValues(alpha: 0.92),
            size: 20,
          ),
          suffixIcon: suffixIcon,
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
            borderSide: BorderSide(
              color: accent.withValues(alpha: 0.92),
              width: 1.6,
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: _authBorder),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}
