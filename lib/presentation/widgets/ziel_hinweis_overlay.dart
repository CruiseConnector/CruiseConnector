import 'dart:async';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/tutorial_ziel_registry.dart';
import 'package:flutter/material.dart';

/// 2026-08-16 (vucko Testfahrt, Aufgabe 5): „Wenn die Leute bei den
/// Willkommensaufgaben auf eine Aufgabe klicken, sollen sie direkt hingeleitet
/// werden, und es wird ihnen gehighlightet, was sie machen müssen — man zeigt
/// ihnen: so geht das. Und bei der Cruise-Mode-Seite soll das Overlay Schritt
/// für Schritt erklären, welcher Modus was ist."
///
/// Das ist die eine gemeinsame Mechanik dafür: eine Folge von
/// [HinweisSchritt]en. Jeder Schritt zeigt einen Spotlight-Ring um ein ECHTES
/// Widget (gemessen über [TutorialZielRegistry], nicht geraten), scrollt es
/// vorher in den Blick und stellt eine Sprechblase mit Titel + Satz daneben.
/// „Weiter" führt zum nächsten Schritt, der letzte Knopf schließt. Antippen
/// des dunklen Bereichs schließt ebenfalls (nichts hält den Nutzer fest).
class HinweisSchritt {
  const HinweisSchritt({
    required this.titel,
    required this.text,
    this.ziel,
    this.vorbereitung,
    this.aufblasen = 8,
    this.symbol,
  });

  final String titel;
  final String text;

  /// Registry-Schlüssel des Ziels; null = nur Sprechblase in der Mitte.
  final String? ziel;

  /// Läuft VOR dem Anzeigen (z. B. Modus umschalten, Panel aufklappen).
  final Future<void> Function()? vorbereitung;
  final double aufblasen;

  /// Optionales Symbol links in der Sprechblase (z. B. Stern für „merken").
  final IconData? symbol;
}

/// Zeigt eine Hinweis-Führung über dem aktuellen Bildschirm.
Future<void> showZielHinweise(
  BuildContext context, {
  required List<HinweisSchritt> schritte,
  String letzterKnopf = 'Verstanden',
}) async {
  if (schritte.isEmpty || !context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return ZielHinweisOverlay(schritte: schritte, letzterKnopf: letzterKnopf);
    },
  );
}

class ZielHinweisOverlay extends StatefulWidget {
  const ZielHinweisOverlay({
    super.key,
    required this.schritte,
    this.letzterKnopf = 'Verstanden',
    this.messenBis = const Duration(milliseconds: 2500),
  });

  final List<HinweisSchritt> schritte;
  final String letzterKnopf;

  /// Wie lange auf das Ziel-Widget gewartet wird (Tab-Wechsel, Aufklappen).
  final Duration messenBis;

  @override
  State<ZielHinweisOverlay> createState() => _ZielHinweisOverlayState();
}

class _ZielHinweisOverlayState extends State<ZielHinweisOverlay> {
  int _index = 0;
  Rect? _rect;
  bool _bereit = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_zeige(0));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _zeige(int i) async {
    _poll?.cancel();
    setState(() {
      _index = i;
      _rect = null;
      _bereit = false;
    });
    final schritt = widget.schritte[i];
    try {
      await schritt.vorbereitung?.call();
    } catch (e) {
      debugPrint('[Hinweis] Vorbereitung fehlgeschlagen: $e');
    }
    if (!mounted) return;
    if (schritt.ziel == null) {
      setState(() => _bereit = true);
      return;
    }
    // Ziel in den Blick scrollen (falls es in einer Liste liegt), dann messen.
    final ctx = TutorialZielRegistry.key(schritt.ziel!).currentContext;
    if (ctx != null && ctx.mounted) {
      try {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.45,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {}
    }
    const takt = Duration(milliseconds: 120);
    var gewartet = Duration.zero;
    void messen() {
      if (!mounted) return;
      final r = TutorialZielRegistry.rect(schritt.ziel!, aufblasen: schritt.aufblasen);
      if (r != null) {
        _poll?.cancel();
        setState(() {
          _rect = r;
          _bereit = true;
        });
        return;
      }
      if (gewartet >= widget.messenBis) {
        _poll?.cancel();
        setState(() => _bereit = true); // ohne Spotlight, nur Text
      }
    }

    messen();
    if (!_bereit) {
      _poll = Timer.periodic(takt, (_) {
        gewartet += takt;
        messen();
      });
    }
  }

  void _weiter() {
    if (_index + 1 >= widget.schritte.length) {
      Navigator.of(context).maybePop();
      return;
    }
    unawaited(_zeige(_index + 1));
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final schritt = widget.schritte[_index];
    final size = MediaQuery.sizeOf(context);
    final letzter = _index + 1 >= widget.schritte.length;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: CustomPaint(
                painter: _HinweisSpotlightPainter(rect: _rect, accent: accent),
              ),
            ),
          ),
          if (_bereit)
            _sprechblase(context, schritt, accent, size, letzter),
        ],
      ),
    );
  }

  Widget _sprechblase(
    BuildContext context,
    HinweisSchritt schritt,
    Color accent,
    Size size,
    bool letzter,
  ) {
    final rect = _rect;
    // Über oder unter dem Ziel — je nachdem, wo mehr Platz ist.
    final unten = rect == null || rect.center.dy < size.height * 0.5;
    final blase = Container(
      key: const ValueKey('hinweis_blase'),
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (schritt.symbol != null) ...[
                Icon(schritt.symbol, color: accent, size: 20),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  schritt.titel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (widget.schritte.length > 1)
                Text(
                  '${_index + 1}/${widget.schritte.length}',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            schritt.text,
            style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (!letzter)
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text(
                    'Überspringen',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              const Spacer(),
              ElevatedButton(
                key: const ValueKey('hinweis_weiter'),
                onPressed: _weiter,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  elevation: 0,
                ),
                child: Text(
                  letzter ? widget.letzterKnopf : 'Weiter',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (rect == null) {
      return Positioned.fill(
        child: SafeArea(child: Center(child: blase)),
      );
    }
    final pad = MediaQuery.paddingOf(context);
    return unten
        ? Positioned(
            top: (rect.bottom + 14).clamp(pad.top + 8, size.height - 200),
            left: 0,
            right: 0,
            child: blase,
          )
        : Positioned(
            bottom: (size.height - rect.top + 14).clamp(pad.bottom + 8, size.height - 120),
            left: 0,
            right: 0,
            child: blase,
          );
  }
}

class _HinweisSpotlightPainter extends CustomPainter {
  const _HinweisSpotlightPainter({required this.rect, required this.accent});

  final Rect? rect;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.68);
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, dim);
    final r = rect;
    if (r != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(20)),
        Paint()..blendMode = BlendMode.clear,
      );
    }
    canvas.restore();
    if (r == null) return;
    final outer = RRect.fromRectAndRadius(r.inflate(3), const Radius.circular(23));
    canvas
      ..drawRRect(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = accent.withValues(alpha: 0.85),
      )
      ..drawRRect(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 11
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
          ..color = accent.withValues(alpha: 0.30),
      );
  }

  @override
  bool shouldRepaint(covariant _HinweisSpotlightPainter old) =>
      old.rect != rect || old.accent != accent;
}
