import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/auth_service.dart';
import 'package:cruise_connect/data/services/legal_acceptance_service.dart';
import 'package:cruise_connect/presentation/pages/legal_acceptance_page.dart';
import 'package:cruise_connect/presentation/pages/legal_gate_page.dart';
import 'package:cruise_connect/presentation/pages/login_page.dart';
import 'package:cruise_connect/presentation/pages/onboarding/post_auth_gate.dart';
import 'package:cruise_connect/presentation/pages/onboarding/onboarding_wizard_page.dart';
import 'package:cruise_connect/presentation/widgets/auth_social_buttons.dart';

const _authBackground = Color(0xFF0D141E);
const _authSurface = Color(0xFF151E2A);
const _authCard = Color(0xFF1A2432);
const _authBorder = Color(0xFF344156);
const _authTextMuted = Color(0xFFB6BECC);
const _brandMarkAsset = 'assets/branding/cruiseconnect_icon_foreground.png';
const _brandLogoBoxWidth = 204.0;
const _brandLogoBoxHeight = 102.0;
const _brandLogoWidth = 150.0;
const _brandLogoHeight = 62.0;

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool _googleLoading = false;
  bool _appleLoading = false;
  String? _errorMsg;

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
    setState(() => _errorMsg = null);
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
      if (mounted) setState(() => _errorMsg = _translateAuthError(e.message));
    } catch (e) {
      debugPrint('[Welcome] Social Login Fehler: $e');
      if (mounted) {
        setState(
          () => _errorMsg = 'Anmeldung fehlgeschlagen. Bitte erneut versuchen.',
        );
      }
    } finally {
      if (mounted) setLoading(false);
    }
  }

  String _translateAuthError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('abgebrochen') || lower.contains('cancel')) {
      return 'Anmeldung abgebrochen.';
    }
    if (lower.contains('google login ist noch nicht konfiguriert')) {
      return 'Google Login ist noch nicht fertig konfiguriert.';
    }
    if (lower.contains('apple') && lower.contains('nicht verfügbar')) {
      return 'Apple Anmeldung ist auf diesem Gerät nicht verfügbar.';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final brand = AppAccentColors.accent;

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
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      SizedBox(height: iconTopGap),
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
                      const Text(
                        'Cruise Connector',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
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
                      const SizedBox(height: 32),
                      _buildButton(
                        context,
                        text: 'Konto erstellen',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const OnboardingWizardPage(
                              startWithAccountCreation: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildButton(
                        context,
                        text: 'Anmelden',
                        filled: false,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        ),
                      ),
                      const SizedBox(height: 28),
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
                                'oder weiter mit',
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
                      AuthSocialButtons(
                        googleLoading: _googleLoading,
                        appleLoading: _appleLoading,
                        enabled: !_googleLoading && !_appleLoading,
                        onGoogle: _continueWithGoogle,
                        onApple: _continueWithApple,
                      ),
                      if (_errorMsg != null) ...[
                        const SizedBox(height: 18),
                        _buildErrorBox(_errorMsg!),
                      ],
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
    bool filled = true,
  }) {
    final brand = AppAccentColors.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 35),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: Material(
          color: filled ? brand : Colors.transparent,
          shape: StadiumBorder(
            side: BorderSide(
              color: filled ? Colors.transparent : _authBorder,
              width: 1.2,
            ),
          ),
          elevation: filled ? 5 : 0,
          shadowColor: brand.withValues(alpha: 0.28),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Center(
              child: Text(
                text,
                style: TextStyle(
                  color: filled ? Colors.white : _authTextMuted,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBox(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 35),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF331316),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFFF6B6B).withValues(alpha: 0.42),
          ),
        ),
        child: Text(
          message,
          style: const TextStyle(color: Color(0xFFFFB4B4), fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
