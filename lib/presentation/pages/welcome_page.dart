import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/presentation/pages/login_page.dart';
// import 'package:cruise_connect/presentation/pages/register_page.dart';

const _authBackground = Color(0xFF0D141E);
const _authSurface = Color(0xFF151E2A);
const _authCard = Color(0xFF1A2432);
const _authBorder = Color(0xFF344156);
const _authTextMuted = Color(0xFFB6BECC);
const _brandMarkAsset = 'assets/branding/cruiseconnect_icon_foreground.png';
const _googleMarkAsset = 'lib/images/google_mark.png';
const _brandLogoBoxWidth = 204.0;
const _brandLogoBoxHeight = 102.0;
const _brandLogoWidth = 150.0;
const _brandLogoHeight = 62.0;

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final brand = AppAccentColors.accent;

    // Feste Werte damit das Layout auf Web genauso aussieht wie auf Mobile.
    final double iconAreaHeight = (size.height * 0.35).clamp(300.0, 330.0);
    final double iconTopGap = (size.height * 0.08).clamp(60.0, 76.0);
    final double contentGap =
        (iconAreaHeight - padding.top - iconTopGap - _brandLogoBoxHeight + 48)
            .clamp(104.0, 142.0);

    return Scaffold(
      backgroundColor: _authBackground,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
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
            ),
          ),

          Positioned(
            top: iconAreaHeight,
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: _authSurface,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(40),
                  topRight: Radius.circular(40),
                ),
              ),
            ),
          ),

          // ── Inhalt ───────────────────────────────────────────────────────
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                // Auf Web: max 460px breit — wirkt wie Mobile
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      SizedBox(height: iconTopGap),

                      // Brand mark sits in the red hero area, not down in the form.
                      Container(
                        height: _brandLogoBoxHeight,
                        width: _brandLogoBoxWidth,
                        decoration: BoxDecoration(
                          color: Color.lerp(_authCard, brand, 0.10),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: brand.withValues(alpha: 0.34),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: brand.withValues(alpha: 0.22),
                              blurRadius: 28,
                              spreadRadius: -6,
                              offset: const Offset(0, 14),
                            ),
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.06),
                              blurRadius: 18,
                              spreadRadius: -12,
                              offset: const Offset(0, -8),
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

                      SizedBox(height: contentGap),

                      // ── Auth Sektion ──────────────────────────────────
                      const Text(
                        'Cruise Connector',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Willkommen zurück!',
                        style: TextStyle(
                          fontSize: 18,
                          color: _authTextMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Registrierung temporär deaktiviert (Testphase — Testnutzer werden manuell vergeben)
                      // _buildButton(
                      //   context,
                      //   text: 'Registrieren',
                      //   onTap: () => Navigator.push(
                      //     context,
                      //     MaterialPageRoute(builder: (_) => const RegisterPage()),
                      //   ),
                      // ),
                      // const SizedBox(height: 16),
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
                            const Expanded(child: Divider(color: _authBorder)),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'oder anmelden mit',
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
                      const SizedBox(height: 20),

                      // Social Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildSocialButton(
                            label: 'Google Anmeldung folgt',
                            child: Image.asset(
                              _googleMarkAsset,
                              width: 34,
                              height: 34,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                          const SizedBox(width: 20),
                          _buildSocialButton(
                            label: 'Apple Anmeldung folgt',
                            child: Icon(
                              Icons.apple,
                              size: 36,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
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

  Widget _buildButton(
    BuildContext context, {
    required String text,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 35),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppAccentColors.accent,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: AppAccentColors.accent.withValues(alpha: 0.28),
                blurRadius: 20,
                spreadRadius: -6,
                offset: const Offset(0, 10),
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

  Widget _buildSocialButton({required String label, required Widget child}) {
    return Semantics(
      label: label,
      button: true,
      enabled: false,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.76,
          child: Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(
              color: Color.lerp(_authCard, Colors.white, 0.02),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: _authBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 16,
                  spreadRadius: -8,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.05),
                  blurRadius: 12,
                  spreadRadius: -10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
