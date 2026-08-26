import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/app_changelog.dart';
import 'package:cruise_connect/data/services/changelog_service.dart';
import 'package:cruise_connect/presentation/pages/feedback_page.dart';
import 'package:flutter/material.dart';

/// Zeigt nach einem Update, was sich geaendert hat.
///
/// 2026-08-09 (vucko): „Nach jedem Update soll ein Update-Log kommen ... und
/// eine Feedback-Funktion." Beides gehoert zusammen: Wer gerade liest, was neu
/// ist, ist der beste Moment fuer eine Rueckmeldung — deshalb fuehrt der
/// letzte Schritt ins Rueckmeldungs-Formular.
///
/// 2026-08-26 (vucko, Aufgabe 3): „Schau, dass das Popup, das bei allen neuen
/// Features hochkommt, viel angenehmer fuer den User aussieht — also wirklich
/// so, dass es jeden Schritt erklaert, aber dabei nicht alles in eine riesige
/// Meldung verpackt. Viel weniger Woerter, nur ganz, ganz kurze Erklaerungen.
/// Und oben soll ein Fortschrittsanzeiger stehen, zum Beispiel 1 von 3."
///
/// Vorher stand hier eine einzige scrollende Liste mit allen Punkten
/// untereinander — bei fuenf Neuerungen eine Textwand, die niemand liest.
/// Jetzt ein Schritt je Bildschirm, oben die Zaehlung und ein Balken, der
/// zeigt, wie weit man ist.
Future<void> showChangelogSheet(
  BuildContext context,
  ChangelogEintrag eintrag,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => _ChangelogSheet(eintrag: eintrag),
  );
}

class _ChangelogSheet extends StatefulWidget {
  const _ChangelogSheet({required this.eintrag});

  final ChangelogEintrag eintrag;

  @override
  State<_ChangelogSheet> createState() => _ChangelogSheetState();
}

class _ChangelogSheetState extends State<_ChangelogSheet> {
  int _schritt = 0;

  int get _anzahl => widget.eintrag.punkte.length;
  bool get _letzter => _schritt >= _anzahl - 1;

  void _weiter() {
    if (_letzter) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _schritt++);
  }

  void _zurueck() {
    if (_schritt == 0) return;
    setState(() => _schritt--);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final punkte = widget.eintrag.punkte;
    if (punkte.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // 2026-08-26: Kein starres Hoehenmass. Bei groesserer Schrift (der
      // Betreiber testet auf dem MacBook mit 110 Prozent) muss der Text
      // wachsen duerfen, ohne dass unten die Knoepfe abgeschnitten werden.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Version ${widget.eintrag.version}',
                          style: TextStyle(
                            color: accent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      // Der Fortschrittsanzeiger, den Vucko wollte.
                      Text(
                        '${_schritt + 1} von $_anzahl',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _Fortschrittsbalken(
                    anzahl: _anzahl,
                    aktiv: _schritt,
                    farbe: accent,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.eintrag.titel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    punkte[_schritt],
                    key: ValueKey<int>(_schritt),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (_schritt > 0) ...[
                        SizedBox(
                          width: 52,
                          height: 50,
                          child: OutlinedButton(
                            onPressed: _zurueck,
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              size: 20,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _weiter,
                            child: Text(
                              _letzter ? 'Alles klar' : 'Weiter',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Die Rueckmeldung erst am Ende anbieten: wer noch liest,
                  // soll nicht abgelenkt werden.
                  if (_letzter) ...[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const FeedbackPage(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.chat_bubble_outline,
                        size: 18,
                        color: Colors.white70,
                      ),
                      label: const Text(
                        'Etwas dazu sagen',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ein Balken je Schritt. Erledigte und der aktuelle leuchten, der Rest ist
/// gedimmt — man sieht auf einen Blick, wie viel noch kommt.
class _Fortschrittsbalken extends StatelessWidget {
  const _Fortschrittsbalken({
    required this.anzahl,
    required this.aktiv,
    required this.farbe,
  });

  final int anzahl;
  final int aktiv;
  final Color farbe;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < anzahl; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 4,
              decoration: BoxDecoration(
                color: i <= aktiv
                    ? farbe
                    : Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Fuer den Einstellungen-Eintrag: zeigt die Neuerungen der laufenden Version,
/// auch wenn sie schon gesehen wurden.
Future<void> showChangelogAusEinstellungen(BuildContext context) async {
  final eintrag = await ChangelogService.instance.aktuellerEintrag();
  if (!context.mounted) return;
  if (eintrag == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fuer diese Version gibt es keine Notizen.')),
    );
    return;
  }
  await showChangelogSheet(context, eintrag);
}
