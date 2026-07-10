import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/auth_service.dart';
import 'package:cruise_connect/data/services/legal_acceptance_service.dart';
import 'package:cruise_connect/presentation/pages/legal_acceptance_page.dart';
import 'package:cruise_connect/presentation/pages/legal_gate_page.dart';
import 'package:cruise_connect/presentation/pages/onboarding/onboarding_wizard_page.dart';
import 'package:cruise_connect/presentation/pages/onboarding/post_auth_gate.dart';
import 'package:cruise_connect/presentation/widgets/auth_social_buttons.dart';

const _authBackground = Color(0xFF0D141E);
const _authSurface = Color(0xFF151E2A);
const _authField = Color(0xFF1A2432);
const _authBorder = Color(0xFF344156);
const _authTextMuted = Color(0xFFB6BECC);
const _brandMarkAsset = 'assets/branding/cruiseconnect_icon_foreground.png';
const _brandLogoBoxWidth = 204.0;
const _brandLogoBoxHeight = 102.0;
const _brandLogoWidth = 150.0;
const _brandLogoHeight = 62.0;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _obscure = true;
  bool _emailNeedsVerification = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMsg = 'Bitte E-Mail und Passwort eingeben.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = null;
      _emailNeedsVerification = false;
    });

    try {
      await AuthService.signIn(email: email, password: password);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LegalGatePage(child: PostAuthGate()),
        ),
        (route) => false,
      );
    } on AuthException catch (e) {
      final needsVerification = e.message.toLowerCase().contains(
        'email not confirmed',
      );
      setState(() {
        _errorMsg = _translateError(e.message);
        _emailNeedsVerification = needsVerification;
      });
    } catch (e) {
      debugPrint('[Login] Unerwarteter Fehler: $e');
      setState(
        () => _errorMsg = 'Login fehlgeschlagen. Bitte erneut versuchen.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
    // 2026-07-10 (vucko): Bereits bestätigte Rechtstexte (Pre-Auth-Pending,
    // z. B. vom abgebrochenen ersten Versuch oder aus dem Wizard) nicht
    // ERNEUT abfragen — sonst kommt das AGB-Fenster zweimal.
    var accepted = await LegalAcceptanceService.pendingPreAuthAcceptance();
    if (!mounted) return;
    accepted ??= await LegalAcceptancePage.requestPreAuth(
      context,
      source: 'app_onboarding',
    );
    if (!mounted || accepted == null) return;

    setLoading(true);
    setState(() {
      _errorMsg = null;
      _emailNeedsVerification = false;
    });
    try {
      await action();
      if (!mounted) return;
      if (AuthService.currentUser != null) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const LegalGatePage(child: PostAuthGate()),
          ),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Anmeldung geöffnet. Kehre danach zur App zurück.'),
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMsg = _translateError(e.message));
    } catch (e) {
      debugPrint('[Login] Social Login Fehler: $e');
      if (mounted) {
        setState(
          () => _errorMsg = 'Anmeldung fehlgeschlagen. Bitte erneut versuchen.',
        );
      }
    } finally {
      if (mounted) setLoading(false);
    }
  }

  Future<void> _resendVerificationEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMsg = 'Bitte E-Mail eintragen.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AuthService.resendVerificationEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bestätigungs-E-Mail an $email erneut gesendet.'),
        ),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMsg = _translateError(e.message));
    } catch (e) {
      debugPrint('[Login] Verification resend Fehler: $e');
      if (mounted) {
        setState(
          () => _errorMsg =
              'E-Mail konnte nicht erneut gesendet werden. Bitte kurz warten.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _translateError(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) {
      return 'E-Mail oder Passwort falsch.';
    }
    if (m.contains('email not confirmed')) {
      return 'Bitte bestätige zuerst deine E-Mail.';
    }
    if (m.contains('abgebrochen') || m.contains('cancel')) {
      return 'Anmeldung abgebrochen.';
    }
    if (m.contains('google login ist noch nicht konfiguriert')) {
      return 'Google Login ist noch nicht fertig konfiguriert.';
    }
    if (m.contains('apple') && m.contains('nicht verfügbar')) {
      return 'Apple Anmeldung ist auf diesem Gerät nicht verfügbar.';
    }
    if (m.contains('too many requests')) {
      return 'Zu viele Versuche. Bitte kurz warten.';
    }
    return 'Login fehlgeschlagen. Bitte erneut versuchen.';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final brand = AppAccentColors.accent;
    final headerH = size.height * 0.35;

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

          // Inhalt
          SingleChildScrollView(
            child: Column(
              children: [
                // ── Auth Header ──────────────────────────────────────────────
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
                          height: _brandLogoBoxHeight,
                          width: _brandLogoBoxWidth,
                          decoration: BoxDecoration(
                            color: Color.lerp(_authField, brand, 0.10),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: brand.withValues(alpha: 0.26),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: brand.withValues(alpha: 0.20),
                                blurRadius: 26,
                                spreadRadius: -8,
                                offset: const Offset(0, 8),
                              ),
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.06),
                                blurRadius: 16,
                                spreadRadius: -12,
                                offset: const Offset(0, -6),
                              ),
                            ],
                          ),
                          child: Center(
                            child: SizedBox(
                              width: _brandLogoWidth,
                              height: _brandLogoHeight,
                              child: Image.asset(
                                _brandMarkAsset,
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

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
                      const SizedBox(height: 40),
                      const Center(
                        child: Text(
                          'Willkommen zurück',
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
                          'Melde dich an, um fortzufahren',
                          style: TextStyle(fontSize: 15, color: _authTextMuted),
                        ),
                      ),
                      const SizedBox(height: 30),

                      _label('E-Mail Adresse'),
                      _inputField(
                        controller: _emailController,
                        icon: Icons.email_outlined,
                        hint: 'deine@email.de',
                        keyboardType: TextInputType.emailAddress,
                        maxLength: AppInputLimits.emailMaxLength,
                      ),
                      const SizedBox(height: 18),

                      _label('Passwort'),
                      _inputField(
                        controller: _passwordController,
                        icon: Icons.lock_outline,
                        hint: '••••••••',
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

                      // Fehlermeldung
                      if (_errorMsg != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
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

                      if (_emailNeedsVerification)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _isLoading
                                ? null
                                : _resendVerificationEmail,
                            icon: const Icon(Icons.mark_email_unread_outlined),
                            label: const Text('E-Mail erneut senden'),
                            style: TextButton.styleFrom(foregroundColor: brand),
                          ),
                        ),

                      const SizedBox(height: 28),

                      // Anmelden Button
                      SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _signIn,
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
                                  'Anmelden',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 25),

                      // Registrierung temporär deaktiviert (Testphase)
                      // Center(
                      //   child: GestureDetector(
                      //     onTap: () => Navigator.pop(context),
                      //     child: RichText(
                      //       text: const TextSpan(
                      //         text: 'Noch kein Konto? ',
                      //         style: TextStyle(color: Colors.grey, fontSize: 14),
                      //         children: [
                      //           TextSpan(
                      //             text: 'Jetzt registrieren',
                      //             style: TextStyle(color: brand, fontWeight: FontWeight.bold),
                      //           ),
                      //         ],
                      //       ),
                      //     ),
                      //   ),
                      // ),
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
                                'oder',
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
                      const SizedBox(height: 18),
                      AuthSocialButtons(
                        googleLoading: _googleLoading,
                        appleLoading: _appleLoading,
                        enabled:
                            !_isLoading && !_googleLoading && !_appleLoading,
                        onGoogle: _continueWithGoogle,
                        onApple: _continueWithApple,
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: GestureDetector(
                          onTap: () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const OnboardingWizardPage(
                                startWithAccountCreation: true,
                              ),
                            ),
                          ),
                          child: RichText(
                            text: TextSpan(
                              text: 'Noch kein Konto? ',
                              style: const TextStyle(
                                color: _authTextMuted,
                                fontSize: 14,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Jetzt registrieren',
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
