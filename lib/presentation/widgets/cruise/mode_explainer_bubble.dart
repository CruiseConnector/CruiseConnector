import 'package:flutter/material.dart';

/// 2026-05-24 (vucko): Mini-Erklärungs-Bubble für Modus-Buttons.
///
/// Zeigt beim Klick auf einen aktiven Modus eine kleine Tooltip-Card
/// mit Erklärung, schließt beim erneuten Klick. Mit Fade + Slide-Animation.
///
/// Verwendung: Wrap einen Modus-Button mit ExplainableModeButton.
class ModeExplainerBubble extends StatefulWidget {
  final String text;
  final Color accentColor;
  final bool isOpen;
  final VoidCallback onDismiss;

  const ModeExplainerBubble({
    super.key,
    required this.text,
    required this.accentColor,
    required this.isOpen,
    required this.onDismiss,
  });

  @override
  State<ModeExplainerBubble> createState() => _ModeExplainerBubbleState();
}

class _ModeExplainerBubbleState extends State<ModeExplainerBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    if (widget.isOpen) _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant ModeExplainerBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen != oldWidget.isOpen) {
      if (widget.isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        if (_controller.value == 0) return const SizedBox.shrink();
        return Opacity(
          opacity: _fade.value,
          child: SlideTransition(
            position: _slide,
            child: Transform.scale(
              scale: _scale.value,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismiss,
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.accentColor.withValues(alpha: 0.16),
                        const Color(0xFF1C1F26),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: widget.accentColor.withValues(alpha: 0.42),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.accentColor.withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_rounded,
                        color: widget.accentColor,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.close_rounded,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
