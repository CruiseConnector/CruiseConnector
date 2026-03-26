import 'package:flutter/material.dart';
import 'package:cruise_connect/presentation/pages/login_page.dart';
import 'package:cruise_connect/presentation/pages/register_page.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  static const Color _brand = Color(0xFFEF4F4F);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // Feste Werte damit das Layout auf Web genauso aussieht wie auf Mobile
    // (kein komischer Card-Stil — Original-Design überall)
    final double iconAreaHeight = size.height.clamp(0, 700) * 0.32;
    final double iconBoxHeight  = iconAreaHeight * 0.55;
    final double iconBoxWidth   = (size.width * 0.65).clamp(0, 280);

    return Scaffold(
      backgroundColor: _brand,
      body: Stack(
        children: [
          // ── Roter Hintergrund ────────────────────────────────────────────
          const Positioned.fill(child: ColoredBox(color: _brand)),

          // ── Weißer Bereich (unten, abgerundet) ──────────────────────────
          Positioned(
            top: iconAreaHeight,
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(40),
                  topRight: Radius.circular(40),
                ),
              ),
            ),
          ),

          // ── Inhalt ───────────────────────────────────────────────────────
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                // Auf Web: max 460px breit — wirkt wie Mobile
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      SizedBox(height: iconAreaHeight * 0.08),

                      // Auto-Icon Box (roter Hintergrund, kein dunkles Quadrat)
                      Container(
                        height: iconBoxHeight,
                        width: iconBoxWidth,
                        decoration: BoxDecoration(
                          color: _brand,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.directions_car_rounded,
                          size: 80,
                          color: Colors.white,
                        ),
                      ),

                      // Platzhalter: drückt Text in den weißen Bereich
                      SizedBox(height: iconAreaHeight * 0.42),

                      // ── Weiße Sektion ─────────────────────────────────
                      const Text(
                        'CruiseConnect',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Willkommen zurück!',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 36),

                      _buildButton(
                        context,
                        text: 'Registrieren',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const RegisterPage()),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildButton(
                        context,
                        text: 'Anmelden',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Divider
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Row(
                          children: [
                            Expanded(child: Divider(color: Colors.grey[300])),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'oder anmelden mit',
                                style: TextStyle(color: Colors.grey[400], fontSize: 13),
                              ),
                            ),
                            Expanded(child: Divider(color: Colors.grey[300])),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Social Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildSocialButton('lib/images/google.jpg'),
                          const SizedBox(width: 20),
                          _buildSocialButton('lib/images/Apple.png'),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(BuildContext context, {required String text, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 35),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _brand,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: _brand.withValues(alpha: 0.4),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(30),
              child: Center(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialButton(String path) {
    return Container(
      padding: const EdgeInsets.all(12),
      height: 72,
      width: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Image.asset(path),
    );
  }
}
