import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/fahrt_knoepfe_service.dart';

/// 2026-09-02 (Vucko, Sprachnachricht):
///   "in den einstellungen kann man alle hinzufuegen falls man eins nicht
///    braucht oder eins anders haben moechte aber maximal das man 4 anzeigen
///    kann"
///
/// Die Auswahl der Knoepfe, die waehrend der Fahrt rechts stehen. Hoechstens
/// vier, in der Reihenfolge, in der sie dort erscheinen.
///
/// Warum ein Blatt und keine eigene Seite: die Auswahl ist eine kurze
/// Entscheidung mit sechs Zeilen. Eine ganze Seite dafuer waere ein Umweg.
Future<void> showFahrtKnoepfeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => const _FahrtKnoepfeSheet(),
  );
}

class _FahrtKnoepfeSheet extends StatefulWidget {
  const _FahrtKnoepfeSheet();

  @override
  State<_FahrtKnoepfeSheet> createState() => _FahrtKnoepfeSheetState();
}

class _FahrtKnoepfeSheetState extends State<_FahrtKnoepfeSheet> {
  /// Steht kurz, wenn jemand einen fuenften Knopf antippt. Kein Dialog: der
  /// Grund ist in einem Satz gesagt, und ein Dialog waere fuer eine
  /// Kleinigkeit zu viel.
  String? _hinweis;
  Timer? _hinweisUhr;

  @override
  void dispose() {
    _hinweisUhr?.cancel();
    super.dispose();
  }

  void _zeigeHinweis(String text) {
    setState(() => _hinweis = text);
    _hinweisUhr?.cancel();
    _hinweisUhr = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _hinweis = null);
    });
  }

  Future<void> _umschalten(FahrKnopf k) async {
    final dienst = FahrtKnoepfeService.instance;
    final warGewaehlt = dienst.istGewaehlt(k);
    final ging = await dienst.umschalten(k);
    if (!mounted) return;
    if (!ging) {
      HapticFeedback.heavyImpact();
      _zeigeHinweis(
        'Vier sind das Höchste. Nimm zuerst einen weg, dann geht der hier.',
      );
      return;
    }
    HapticFeedback.selectionClick();
    if (warGewaehlt && dienst.auswahl.isEmpty) {
      _zeigeHinweis(
        'Jetzt ist kein Knopf mehr gewählt. Während der Fahrt bleibt nur der '
        'Griff zum Ausklappen.',
      );
    } else {
      setState(() => _hinweis = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent.withValues(alpha: 0.12), const Color(0xFF11141B)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.4],
            ),
            border: Border(
              top: BorderSide(color: accent.withValues(alpha: 0.4), width: 1.2),
            ),
          ),
          child: AnimatedBuilder(
            animation: FahrtKnoepfeService.instance,
            builder: (context, _) => _inhalt(accent),
          ),
        ),
      ),
    );
  }

  Widget _inhalt(Color accent) {
    final dienst = FahrtKnoepfeService.instance;
    final gewaehlt = dienst.auswahl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.withValues(alpha: 0.4)),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.apps_rounded, color: accent, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Knöpfe während der Fahrt',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        '${gewaehlt.length} von ${FahrtKnoepfeService.hoechstens} gewählt',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    unawaited(FahrtKnoepfeService.instance.aufVoreinstellung());
                    setState(() => _hinweis = null);
                  },
                  child: Text(
                    'Standard',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Rechts neben der Karte ist wenig Platz. Wähle die vier, die du '
              'wirklich brauchst. Der Rest bleibt erreichbar: die Punkte auf '
              'der Karte und die Meldungen anderer liegen zusammen in einer '
              'Liste.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),

            for (final info in FahrtKnoepfeService.alle)
              _KnopfZeile(
                info: info,
                gewaehlt: dienst.istGewaehlt(info.knopf),
                platzNummer: gewaehlt.indexOf(info.knopf) + 1,
                gesperrt: !dienst.istGewaehlt(info.knopf) && dienst.istVoll,
                onTap: () => _umschalten(info.knopf),
              ),

            if (_hinweis != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: Color(0xFFFBBF24),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _hinweis!,
                        style: const TextStyle(
                          color: Color(0xFFFBBF24),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),
            Text(
              'Zwei der Knöpfe haben nur während einer laufenden Fahrt etwas '
              'zu tun. Vorher siehst du sie nicht, auch wenn sie gewählt sind.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KnopfZeile extends StatelessWidget {
  const _KnopfZeile({
    required this.info,
    required this.gewaehlt,
    required this.platzNummer,
    required this.gesperrt,
    required this.onTap,
  });

  final FahrKnopfInfo info;
  final bool gewaehlt;

  /// 1 bis 4, wenn gewaehlt. Zeigt, an welcher Stelle der Knopf steht.
  final int platzNummer;

  /// Nicht gewaehlt und kein Platz mehr frei. Die Zeile bleibt antippbar,
  /// damit man den Grund zu hoeren bekommt, statt ins Leere zu tippen.
  final bool gesperrt;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: gewaehlt
            ? accent.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: (gewaehlt ? accent : Colors.white).withValues(
                      alpha: gewaehlt ? 0.18 : 0.08,
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    info.symbol,
                    size: 19,
                    color: gewaehlt
                        ? accent
                        : Colors.white.withValues(alpha: gesperrt ? 0.3 : 0.55),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              info.name,
                              style: TextStyle(
                                color: gesperrt
                                    ? Colors.white.withValues(alpha: 0.45)
                                    : Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (info.brauchtRoute) ...[
                            const SizedBox(width: 7),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                'nur mit Route',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.beschreibung,
                        style: TextStyle(
                          color: Colors.white.withValues(
                            alpha: gesperrt ? 0.3 : 0.48,
                          ),
                          fontSize: 11.5,
                          height: 1.32,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (gewaehlt)
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$platzNummer',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  Icon(
                    gesperrt
                        ? Icons.lock_outline_rounded
                        : Icons.add_circle_outline_rounded,
                    size: 22,
                    color: Colors.white.withValues(alpha: gesperrt ? 0.25 : 0.4),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
