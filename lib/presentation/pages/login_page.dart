import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/auth_service.dart';
import 'package:cruise_connect/presentation/pages/home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscure   = true;
  String? _errorMsg;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email    = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMsg = 'Bitte E-Mail und Passwort eingeben.');
      return;
    }

    setState(() { _isLoading = true; _errorMsg = null; });

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
      setState(() => _errorMsg = 'Login fehlgeschlagen. Bitte erneut versuchen.');
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
    return 'Login fehlgeschlagen: $msg';
  }

  @override
  Widget build(BuildContext context) {
    final size    = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    const brand   = Color(0xFFEF4F4F);
    final headerH = size.height * 0.35;

    return Scaffold(
      backgroundColor: brand,
      body: Stack(
        children: [
          const ColoredBox(color: brand, child: SizedBox.expand()),

          // Weißer unterer Bereich
          Positioned(
            top: headerH, bottom: 0, left: 0, right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
              ),
            ),
          ),

          // Inhalt
          SingleChildScrollView(
            child: Column(
              children: [
                // ── Roter Header ─────────────────────────────────────────────
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
                                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const Spacer(),
                              const Text(
                                'CruiseConnect',
                                style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                              const Spacer(),
                              const SizedBox(width: 50),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        Container(
                          height: 120, width: 200,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 8))],
                          ),
                          child: const Icon(Icons.directions_car, size: 60, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Weißes Formular ──────────────────────────────────────────
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 40),
                      const Center(
                        child: Text(
                          'Willkommen zurück',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black87),
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Center(
                        child: Text('Melde dich an, um fortzufahren', style: TextStyle(fontSize: 15, color: Colors.grey)),
                      ),
                      const SizedBox(height: 30),

                      _label('E-Mail Adresse'),
                      _inputField(
                        controller: _emailController,
                        icon: Icons.email_outlined,
                        hint: 'deine@email.de',
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 18),

                      _label('Passwort'),
                      _inputField(
                        controller: _passwordController,
                        icon: Icons.lock_outline,
                        hint: '••••••••',
                        obscure: _obscure,
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),

                      // Fehlermeldung
                      if (_errorMsg != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 28),

                      // Anmelden Button
                      SizedBox(
                        width: double.infinity, height: 58,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _signIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brand,
                            foregroundColor: Colors.white,
                            elevation: 5,
                            shadowColor: brand.withValues(alpha: 0.4),
                            shape: const StadiumBorder(),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text('Anmelden', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        ),
                      ),

                      const SizedBox(height: 25),

                      Center(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: RichText(
                            text: const TextSpan(
                              text: 'Noch kein Konto? ',
                              style: TextStyle(color: Colors.grey, fontSize: 14),
                              children: [
                                TextSpan(
                                  text: 'Jetzt registrieren',
                                  style: TextStyle(color: brand, fontWeight: FontWeight.bold),
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
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 14)),
  );

  Widget _inputField({
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15)),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.grey[500], size: 20),
          suffixIcon: suffixIcon,
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey[400]),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }
}
