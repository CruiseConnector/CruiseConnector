import 'package:flutter/material.dart';

const _googleMarkAsset = 'lib/images/google_mark.png';

class AuthSocialButtons extends StatelessWidget {
  const AuthSocialButtons({
    super.key,
    required this.onGoogle,
    required this.onApple,
    this.googleLoading = false,
    this.appleLoading = false,
    this.enabled = true,
    this.surfaceColor = const Color(0xFF1A2432),
    this.borderColor = const Color(0xFF344156),
  });

  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final bool googleLoading;
  final bool appleLoading;
  final bool enabled;
  final Color surfaceColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _AuthSocialButton(
          label: 'Mit Google fortfahren',
          loading: googleLoading,
          enabled: enabled && !googleLoading && !appleLoading,
          onTap: onGoogle,
          surfaceColor: surfaceColor,
          borderColor: borderColor,
          child: Image.asset(
            _googleMarkAsset,
            width: 34,
            height: 34,
            filterQuality: FilterQuality.high,
          ),
        ),
        const SizedBox(width: 20),
        _AuthSocialButton(
          label: 'Mit Apple fortfahren',
          loading: appleLoading,
          enabled: enabled && !googleLoading && !appleLoading,
          onTap: onApple,
          surfaceColor: surfaceColor,
          borderColor: borderColor,
          child: Icon(
            Icons.apple,
            size: 36,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}

class _AuthSocialButton extends StatelessWidget {
  const _AuthSocialButton({
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onTap,
    required this.child,
    required this.surfaceColor,
    required this.borderColor,
  });

  final String label;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;
  final Color surfaceColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      child: SizedBox(
        height: 64,
        width: 64,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(17),
            child: Ink(
              decoration: BoxDecoration(
                color: Color.lerp(surfaceColor, Colors.white, 0.02),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: borderColor),
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
              child: Center(
                child: loading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: accent,
                          strokeWidth: 2.4,
                        ),
                      )
                    : child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
