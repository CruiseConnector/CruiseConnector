import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/auth_service.dart';
import 'package:cruise_connect/presentation/pages/home_page.dart';

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
  bool _obscure = true;
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
    });

    try {
      await AuthService.signIn(email: email, password: password);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    } on AuthException catch (e) {
      setState(() => _errorMsg = _translateError(e.message));
    } catch (e) {
      debugPrint('[Login] Unerwarteter Fehler: $e');
      setState(
        () => _errorMsg = 'Login fehlgeschlagen. Bitte erneut versuchen.',
      );
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
