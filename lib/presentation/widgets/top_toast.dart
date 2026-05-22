import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';

/// Top-Toast — Bestätigungs-Banner der von oben einfliegt.
///
/// Ersatz für ScaffoldMessenger.showSnackBar (die landet unten und
/// wird vom Bottom-Nav verdeckt). Erscheint unter der Status-Bar,
/// hat klare Lesbarkeit, verschwindet automatisch nach `duration`.
///
/// Usage:
///   TopToast.show(context, message: 'Route gespeichert');
///   TopToast.show(context, message: '...', icon: Icons.error, isError: true);
class TopToast {
  static OverlayEntry? _current;

  static void show(
    BuildContext context, {
    required String message,
    IconData icon = Icons.check_circle,
    bool isError = false,
    Duration duration = const Duration(seconds: 2),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _current?.remove();
    _current = null;
    final accent = isError
        ? const Color(0xFFE53935)
        : AppAccentColors.accent;
    final entry = OverlayEntry(
      builder: (ctx) => _TopToastWidget(
        message: message,
        icon: icon,
        accent: accent,
        duration: duration,
        onDismiss: () {
          _current?.remove();
          _current = null;
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _TopToastWidget extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color accent;
  final Duration duration;
  final VoidCallback onDismiss;

  const _TopToastWidget({
    required this.message,
    required this.icon,
    required this.accent,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_TopToastWidget> createState() => _TopToastWidgetState();
}

class _TopToastWidgetState extends State<_TopToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _offset;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _offset = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(_ctrl);
    _ctrl.forward();
    Future.delayed(widget.duration, () async {
      if (!mounted) return;
      await _ctrl.reverse();
      if (!mounted) return;
      widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Positioned(
      top: media.padding.top + 10,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _offset,
        child: FadeTransition(
          opacity: _opacity,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1E28),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.accent.withValues(alpha: 0.45),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: widget.accent.withValues(alpha: 0.20),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(widget.icon, color: widget.accent, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
