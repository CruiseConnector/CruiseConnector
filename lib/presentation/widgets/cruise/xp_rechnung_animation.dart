import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';

/// Die XP-Rechnung einer Fahrt, die sich vor den Augen aufbaut.
///
/// 2026-08-19 (vucko woertlich): „ich moechte das es bei der post route page
/// eine gute animation gibt wenn man den multiplikator bekommt oder eine
/// streak hat die zeit normale xp fuer die fahrt + die xp = und dann die basis
/// xp multipliziert"
///
/// Drei Stufen, in dieser Reihenfolge:
///   1. Die Basis-XP der Fahrt zaehlen hoch (10 XP je gefahrenem Kilometer).
///   2. Der Multiplikator schiebt sich dazu, mit dem Grund daneben
///      (Doppel-XP-Woche und/oder Streak-Tage).
///   3. Das Ergebnis zaehlt von der Basis auf den Endwert.
///
/// ZWEI HARTE REGELN, beide aus gemessenen Fehlern:
///
/// * Hier wird NICHTS nachgerechnet. [basisXp], [multiplikator] und
///   [gesamtXp] kommen unveraendert aus `RouteXpBreakdown`, also aus genau
///   der Rechnung, die auch gebucht wird. Am 19.08. war gebucht 204 und
///   angezeigt „+102", weil an zwei Stellen zwei Rechnungen standen.
/// * Der Endwert der Animation ist woertlich [gesamtXp]. Die Zwischenwerte
///   sind interpoliert, der letzte Frame ist es nicht.
///
/// Ohne Streak und ohne Bonuswoche ist der Multiplikator 1,00. Dann faellt
/// die Multiplikations-Zeile ganz weg und es bleibt eine ruhige Zeile mit der
/// Zahl — eine Rechnung „120 × 1,00 = 120" waere albern.
class XpRechnungAnimation extends StatefulWidget {
  const XpRechnungAnimation({
    super.key,
    required this.basisXp,
    required this.multiplikator,
    required this.gesamtXp,
    required this.streakTage,
    required this.doppelXpAktiv,
  });

  /// Basis-XP der Fahrt, vor dem Multiplikator (`RouteXpBreakdown.baseXp`).
  final int basisXp;

  /// `RouteXpBreakdown.multiplier` — Basis (1,0 oder 2,0) plus 0,1 je Tag.
  final double multiplikator;

  /// `RouteXpBreakdown.totalXp` — die Zahl, die aufs Konto geht.
  final int gesamtXp;

  /// Tage der laufenden Serie, die in den Multiplikator geflossen sind.
  final int streakTage;

  /// Laeuft die Doppel-XP-Woche aus dem Starter-Paket? Bestimmt nur den
  /// Begruendungstext; der Wert selbst steckt schon in [multiplikator].
  final bool doppelXpAktiv;

  /// Ab hier lohnt sich die Rechnung. Knapp unter 1,0 wegen Fliesskomma.
  static const double _multiplikatorSchwelle = 1.005;

  bool get zeigtRechnung => multiplikator >= _multiplikatorSchwelle;

  @override
  State<XpRechnungAnimation> createState() => _XpRechnungAnimationState();
}

class _XpRechnungAnimationState extends State<XpRechnungAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Wurde die Bewegungs-Einstellung des Systems schon ausgewertet? Sie steht
  /// erst in `didChangeDependencies` zur Verfuegung, nicht in `initState`.
  bool _gestartet = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: widget.zeigtRechnung ? 1500 : 520,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_gestartet) return;
    _gestartet = true;
    // „Bewegung reduzieren" im System (iOS: Bedienungshilfen, Android:
    // Animationen aus) heisst: Ergebnis sofort, ohne Aufbau. Die ZAHLEN
    // bleiben dieselben, nur der Weg dorthin faellt weg.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _phase(double von, double bis, Curve kurve) {
    final roh = ((_controller.value - von) / (bis - von)).clamp(0.0, 1.0);
    return kurve.transform(roh);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: AppAccentColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppAccentColors.accent.withValues(alpha: 0.25),
            ),
          ),
          child: widget.zeigtRechnung
              ? _bauRechnung()
              : _bauEinfacheZeile(),
        );
      },
    );
  }

  /// Ohne Streak und ohne Bonuswoche: nur die Zahl, ruhig hochgezaehlt.
  Widget _bauEinfacheZeile() {
    final anteil = _phase(0.0, 1.0, Curves.easeOutCubic);
    return Row(
      children: [
        const Text('⚡', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'XP für diese Fahrt',
            style: TextStyle(
              color: Color(0xFFD6DBE4),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          '${xpText((widget.gesamtXp * anteil).round())} XP',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _bauRechnung() {
    final basisAnteil = _phase(0.0, 0.34, Curves.easeOutCubic);
    final pillAnteil = _phase(0.30, 0.56, Curves.easeOutBack);
    final ergebnisAnteil = _phase(0.50, 1.0, Curves.easeOutCubic);

    final basisWert = (widget.basisXp * basisAnteil).round();
    // Der letzte Frame ist EXAKT gesamtXp: bei anteil == 1 bleibt
    // basisXp + (gesamtXp - basisXp) uebrig. Kein Runden am Ende.
    final ergebnisWert =
        widget.basisXp +
        ((widget.gesamtXp - widget.basisXp) * ergebnisAnteil).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Opacity(
          opacity: basisAnteil.clamp(0.0, 1.0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Fahrt · 10 XP je Kilometer',
                  style: TextStyle(
                    color: Color(0xFFD6DBE4),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${xpText(basisWert)} XP',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Opacity(
          opacity: pillAnteil.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - pillAnteil.clamp(0.0, 1.0))),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppAccentColors.accent.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '×${multiplikatorText(widget.multiplikator)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    grundText(
                      multiplikator: widget.multiplikator,
                      streakTage: widget.streakTage,
                      doppelXpAktiv: widget.doppelXpAktiv,
                    ),
                    style: const TextStyle(
                      color: Color(0xFFD6DBE4),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 1,
          color: Colors.white.withValues(alpha: 0.12),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('🔥', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 7),
            const Expanded(
              child: Text(
                'Gutgeschrieben',
                style: TextStyle(
                  color: Color(0xFFD6DBE4),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '= ${xpText(ergebnisWert)} XP',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Tausenderpunkte, deutsch. 1234 wird zu „1.234".
String xpText(int wert) {
  final ziffern = wert.abs().toString();
  final puffer = StringBuffer();
  for (var i = 0; i < ziffern.length; i++) {
    if (i > 0 && (ziffern.length - i) % 3 == 0) puffer.write('.');
    puffer.write(ziffern[i]);
  }
  return '${wert < 0 ? '-' : ''}$puffer';
}

/// „2,30" statt „2.30". Auch die XP-Kachel im Abschluss-Sheet nutzt das,
/// damit dort nicht „x2.30" mit Punkt steht.
String multiplikatorText(double multiplikator) =>
    multiplikator.toStringAsFixed(2).replaceAll('.', ',');

/// Warum ist der Multiplikator so hoch? Der Text nennt beide Anteile
/// getrennt, damit erkennbar bleibt, was die Bonuswoche beitraegt und was die
/// eigene Serie. Der Streak-Anteil wird NICHT neu berechnet, sondern aus dem
/// gelieferten Multiplikator und der Basis abgeleitet.
String grundText({
  required double multiplikator,
  required int streakTage,
  required bool doppelXpAktiv,
}) {
  final basis = doppelXpAktiv ? 2.0 : 1.0;
  final streakAnteil = (multiplikator - basis).clamp(0.0, double.infinity);
  final tageText = '$streakTage ${streakTage == 1 ? 'Tag' : 'Tage'} Streak';
  if (doppelXpAktiv && streakTage > 0) {
    return '${multiplikatorText(basis)} Doppel-XP-Woche '
        '+ ${multiplikatorText(streakAnteil)} für $tageText';
  }
  if (doppelXpAktiv) return 'Doppel-XP-Woche läuft';
  return '$tageText · ${multiplikatorText(streakAnteil)} extra';
}
