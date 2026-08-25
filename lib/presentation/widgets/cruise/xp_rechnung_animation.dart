import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';

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
///
/// 2026-08-24 (Aufgabe 4.4, vucko woertlich): „wenn man eine coole Animation
/// hat dann nach der Fahrt, dass halt irgendwie angezeigt werden kann, dass man
/// durch den Boost die sieben Tage einen doppelten Boost hat und halt auf dem
/// aufbauen kann."
///
/// Drei Dinge muss sie klarmachen. Zwei davon fehlten:
///   1. dass man doppelte XP hat        — sagte sie schon (die Pille „×2,30"
///                                         und der Grundtext daneben),
///   2. dass es SIEBEN TAGE laeuft      — sagte sie NICHT,
///   3. dass man darauf AUFBAUEN kann   — sagte sie NICHT.
/// Dafuer gibt es jetzt eine vierte Stufe: die Bonus-Leiste unter dem
/// Ergebnis, mit Restlaufzeit, Sieben-Tage-Balken und dem Wert von morgen.
///
/// AN DEN ZAHLEN DER FAHRT AENDERT SICH NICHTS. [basisXp], [multiplikator] und
/// [gesamtXp] werden weiterhin nirgends nachgerechnet. Der Wert von morgen ist
/// keine zweite Rechnung derselben Fahrt, sondern derselbe Multiplikator plus
/// den EINEN Tageszuwachs aus `GamificationService.proStreakTag` — die Zahl
/// steht also weiterhin nur an einer Stelle.
class XpRechnungAnimation extends StatefulWidget {
  const XpRechnungAnimation({
    super.key,
    required this.basisXp,
    required this.multiplikator,
    required this.gesamtXp,
    required this.streakTage,
    required this.doppelXpAktiv,
    this.bonusRestlaufzeit,
    this.multiplikatorMorgen,
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

  /// 2026-08-24 (Aufgabe 4.4): Wie lange die Bonuswoche noch laeuft.
  ///
  /// `null` heisst „nicht durchgereicht" — dann fragt das Widget den
  /// Starter-Dienst selbst. Der Weg von der Fahrt bis hierher fuehrt ueber
  /// `cruise_mode_page.dart` und `cruise_completion_dialog.dart`, und beide
  /// gehoeren einem anderen Arbeitsbereich. Der Rueckfall haelt die Anzeige
  /// trotzdem vollstaendig; die Vorlage dafuer ist der Countdown auf der
  /// Startseite (`starter_paket_karte.dart`, `_countdownText`).
  final Duration? bonusRestlaufzeit;

  /// Der Multiplikator, den dieselbe Fahrt MORGEN haette. `null` = selbst
  /// ableiten: [multiplikator] plus ein Tageszuwachs. Genau das meint Vuckos
  /// „auf dem aufbauen".
  final double? multiplikatorMorgen;

  /// Ab hier lohnt sich die Rechnung. Knapp unter 1,0 wegen Fliesskomma.
  static const double _multiplikatorSchwelle = 1.005;

  bool get zeigtRechnung => multiplikator >= _multiplikatorSchwelle;

  /// Die Bonus-Leiste erscheint nur, wenn die Woche wirklich laeuft.
  bool get zeigtBonusLeiste => doppelXpAktiv && zeigtRechnung;

  Duration? get restlaufzeit {
    final durchgereicht = bonusRestlaufzeit;
    if (durchgereicht != null) return durchgereicht;
    final ausDemDienst = StarterAufgabenService.instance.bonusVerbleibend;
    return ausDemDienst > Duration.zero ? ausDemDienst : null;
  }

  double get morgen =>
      multiplikatorMorgen ?? (multiplikator + GamificationService.proStreakTag);

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
        // Die vierte Stufe (Bonus-Leiste) braucht Luft. Ohne sie bleibt es
        // bei den gewohnten 1500 ms.
        milliseconds: widget.zeigtRechnung
            ? (widget.zeigtBonusLeiste ? 1900 : 1500)
            : 520,
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
    // Mit Bonus-Leiste laeuft der Regler 1900 ms statt 1500 — die drei ersten
    // Stufen sollen dabei GENAU SO SCHNELL bleiben wie vorher, sonst wirkt die
    // vertraute Rechnung ploetzlich zaeh. Deshalb werden ihre Anteile auf die
    // laengere Gesamtdauer umgerechnet (1500/1900 = 0,789).
    final skala = widget.zeigtBonusLeiste ? 1500 / 1900 : 1.0;
    final basisAnteil = _phase(0.0, 0.34 * skala, Curves.easeOutCubic);
    final pillAnteil = _phase(0.30 * skala, 0.56 * skala, Curves.easeOutBack);
    final ergebnisAnteil = _phase(0.50 * skala, 1.0 * skala, Curves.easeOutCubic);

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
        if (widget.zeigtBonusLeiste) _bauBonusLeiste(),
      ],
    );
  }

  /// 2026-08-24 (Aufgabe 4.4): Die vierte Stufe. Sie sagt die beiden Dinge,
  /// die bis heute fehlten: SIEBEN TAGE und AUFBAUEN.
  ///
  /// Vucko will es ausdruecklich „cool", deshalb baut sie sich nach dem
  /// Ergebnis auf: erst schiebt sich die Leiste herein, dann faehrt der
  /// Sieben-Tage-Balken auf seinen Stand, zuletzt kippt der Wert von morgen
  /// dazu. Bei „Bewegung reduzieren" steht alles sofort da — der Regler steht
  /// dann auf 1,0 und jede Stufe ist fertig.
  Widget _bauBonusLeiste() {
    final einzug = _phase(0.66, 0.82, Curves.easeOutCubic).clamp(0.0, 1.0);
    final balken = _phase(0.74, 0.94, Curves.easeOutCubic).clamp(0.0, 1.0);
    // easeOutBack schiesst bewusst ueber 1 hinaus (das gibt den kleinen
    // Ueberschwinger). Fuer die Deckkraft muss der Wert trotzdem im Bereich
    // bleiben, sonst wirft Opacity eine Zusicherung.
    final morgenSchwung = _phase(0.86, 1.0, Curves.easeOutBack);
    final morgenAnteil = morgenSchwung.clamp(0.0, 1.0);

    final rest = widget.restlaufzeit;
    final anteilVerbraucht = bonusFortschritt(rest);

    return Opacity(
      opacity: einzug,
      child: Transform.translate(
        offset: Offset(0, 12 * (1 - einzug)),
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
          decoration: BoxDecoration(
            color: AppAccentColors.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: AppAccentColors.accent.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🎁', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      bonusLaufzeitText(rest),
                      style: TextStyle(
                        color: AppAccentColors.accent,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              // Der Sieben-Tage-Balken. Er ist der eigentliche Beleg fuer
              // „das laeuft sieben Tage": man sieht, wie viel davon weg ist.
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: anteilVerbraucht * balken,
                  minHeight: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppAccentColors.accent,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Opacity(
                opacity: morgenAnteil,
                child: Transform.translate(
                  offset: Offset(0, 8 * (1 - morgenSchwung)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📈', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          aufbauText(
                            morgen: widget.morgen,
                            restlaufzeit: rest,
                          ),
                          style: const TextStyle(
                            color: Color(0xFFD6DBE4),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
    return '${multiplikatorText(basis)} für doppelte XP '
        '+ ${multiplikatorText(streakAnteil)} für $tageText';
  }
  if (doppelXpAktiv) return 'Doppelte XP diese Woche';
  return '$tageText · ${multiplikatorText(streakAnteil)} extra';
}

/// 2026-08-24 (Aufgabe 4.4): „dass es SIEBEN TAGE laeuft."
///
/// Bewusst wird die Sieben IMMER genannt, auch wenn die Restlaufzeit gerade
/// nicht durchgereicht wurde (dann kennt der Nutzer wenigstens die Laufzeit).
/// Formuliert wie der Countdown auf der Startseite, nur ohne Abkuerzungen und
/// ohne Gedankenstrich.
String bonusLaufzeitText(Duration? rest) {
  if (rest == null || rest <= Duration.zero) {
    return 'Doppelte XP · sieben Tage lang';
  }
  final tage = rest.inDays;
  final stunden = rest.inHours % 24;
  final minuten = rest.inMinutes % 60;
  String menge;
  if (tage > 0) {
    menge = '$tage ${tage == 1 ? 'Tag' : 'Tage'} '
        '$stunden ${stunden == 1 ? 'Stunde' : 'Stunden'}';
  } else if (stunden > 0) {
    menge = '$stunden ${stunden == 1 ? 'Stunde' : 'Stunden'} '
        '$minuten ${minuten == 1 ? 'Minute' : 'Minuten'}';
  } else {
    menge = '$minuten ${minuten == 1 ? 'Minute' : 'Minuten'}';
  }
  return 'Doppelte XP · noch $menge von sieben Tagen';
}

/// Wie viel der sieben Tage schon verbraucht sind, 0 bis 1. Ohne bekannte
/// Restlaufzeit 0 — dann steht der Balken leer und behauptet nichts.
double bonusFortschritt(Duration? rest) {
  if (rest == null || rest <= Duration.zero) return 0;
  final gesamt = StarterAufgabenService.bonusDauer.inMinutes;
  if (gesamt <= 0) return 0;
  final verbraucht = (gesamt - rest.inMinutes) / gesamt;
  return verbraucht.clamp(0.0, 1.0);
}

/// 2026-08-24 (Aufgabe 4.4): „und halt auf dem aufbauen kann."
///
/// [morgen] ist [XpRechnungAnimation.multiplikator] plus EIN Tageszuwachs. Es
/// ist keine zweite Rechnung dieser Fahrt: die gebuchten Zahlen bleiben
/// unangetastet, hier steht nur, was der naechste Tag am Stueck brächte.
///
/// Am LETZTEN Tag der Woche waere „morgen ×2,40" gelogen: dann faellt die
/// Basis von 2,0 auf 1,0 zurueck. In dem Fall nennt der Text keine Zahl.
String aufbauText({required double morgen, Duration? restlaufzeit}) {
  final letzterTag =
      restlaufzeit != null && restlaufzeit <= const Duration(days: 1);
  if (letzterTag) {
    return 'Letzter Tag der Bonuswoche. Deine Serie läuft danach weiter und '
        'zählt jeden Tag ${multiplikatorText(GamificationService.proStreakTag)} '
        'dazu.';
  }
  return 'Darauf kannst du aufbauen: Fährst du morgen wieder, sind es schon '
      '×${multiplikatorText(morgen)}. Jeder Tag am Stück legt '
      '${multiplikatorText(GamificationService.proStreakTag)} drauf.';
}
