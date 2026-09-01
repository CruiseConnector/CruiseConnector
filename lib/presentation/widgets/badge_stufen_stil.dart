/// 2026-08-19 (vucko woertlich): „und baue die Badges weiter aus schau das sie
/// andere Farben andere Formen andere Symbole haben die Aufteilung gefaellt
/// mir sehr gut. das die niedrigste Stufe Bronze / Rot ist, die beste lila
/// oder blau ist und das man wirklich einen ueberblick hat"
///
/// WARUM GEZEICHNET UND NICHT ALS BILD: `lib/images/badges/` enthaelt bereits
/// 35 PNG mit zusammen 31 MB (kleinste 580 KB, groesste 1,44 MB). Zwanzig
/// weitere Dateien fuer Stufen-Rahmen haetten das Installationspaket um rund
/// 20 MB aufgeblaeht. Form, Farbe und Symbol entstehen deshalb im
/// [CustomPainter] und im vorhandenen Icon-Zeichensatz. Nebeneffekt: scharf
/// auf jeder Aufloesung, und ein neuer Farbton ist eine Zeile statt eines
/// Bildauftrags.
///
/// WARUM DREI MERKMALE STATT NUR FARBE: Wer Rot und Gruen schlecht trennt,
/// haette bei einer reinen Farbskala nichts. Jede Stufe traegt deshalb
/// zusaetzlich eine eigene Silhouette (Kreis, Sechseck, Zackenkranz) und ein
/// eigenes Symbol (Flamme, Blitz, Funken). Auch in Graustufen bleiben die
/// Stufen unterscheidbar.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Die Silhouette einer Stufe. Bewusst drei Formen, die sich schon als
/// Umriss unterscheiden: rund, kantig, gezackt.
enum BadgeStufenForm { kreis, sechseck, zacken }

/// Farbe, Form und Symbol einer Stufe an EINER Stelle.
class BadgeStufenStil {
  const BadgeStufenStil({
    required this.stufe,
    required this.name,
    required this.ziffer,
    required this.farbe,
    required this.farbeTief,
    required this.farbeHell,
    required this.symbol,
    required this.form,
  });

  /// 0 = stufenloser Meilenstein, 1 bis 3 = die Skala.
  final int stufe;

  /// „Bronze", „Tuerkis", „Violett" — steht in der Legende der Sammlung.
  final String name;

  /// Roemische Ziffer, leer bei stufenlosen Meilensteinen.
  final String ziffer;

  /// Leitfarbe. Traegt Rand, Symbol und Text auf dunklem Grund.
  final Color farbe;

  /// Dunkles Ende des Fuellverlaufs.
  final Color farbeTief;

  /// Helles Ende. Wird fuer Text genutzt, wo die Leitfarbe zu satt waere.
  final Color farbeHell;

  final IconData symbol;
  final BadgeStufenForm form;
}

/// Die Skala. Unten Bronze/Rot, oben Violett, das im Verlauf nach Blau
/// kippt — genau Vuckos Vorgabe „niedrigste Stufe Bronze / Rot, die beste
/// lila oder blau".
///
/// NACHGERECHNET, nicht nach Gefuehl gewaehlt. Grund ist der dunkle
/// App-Hintergrund #0B0E14:
///   Kontrast der Leitfarbe gegen den Grund: Bronze 5,1 : 1, Tuerkis 12,5 : 1,
///   Violett 7,7 : 1. Die hellen Varianten (Textfarben) liegen bei 9,3 / 15,8
///   / 12,1 : 1.
///   Graustufen-Abstand der Stufen untereinander: Bronze zu Tuerkis 2,46,
///   Tuerkis zu Violett 1,62, Bronze zu Violett 1,52. Damit trennen sich die
///   Stufen auch dann noch, wenn die Farbe wegfaellt.
/// Trotzdem traegt die Farbe die Unterscheidung NICHT allein: Form und Symbol
/// stehen gleichberechtigt daneben.
const BadgeStufenStil _stufe1 = BadgeStufenStil(
  stufe: 1,
  name: 'Bronze',
  ziffer: 'I',
  farbe: Color(0xFFE0562B),
  farbeTief: Color(0xFF601B05),
  farbeHell: Color(0xFFFF9A63),
  symbol: Icons.local_fire_department_rounded,
  form: BadgeStufenForm.kreis,
);

// 2026-09-01 (Vucko, neue Badge-Serie aus Figma): Die Leiter heisst jetzt
// Bronze, Silber, Gold. Vorher war sie Bronze, Tuerkis, Violett — so hatte er
// es am 19.08. gewuenscht („die niedrigste Stufe Bronze / Rot, die beste lila
// oder blau"). Mit der neuen Serie hat er sich anders entschieden, und die
// Embleme tragen die neue Leiter bereits: Bronzekreis, Silberwappen,
// Goldsechseck. Ein violetter Rahmen um ein goldenes Emblem waere ein
// sichtbarer Bruch.
//
// Violett bleibt der Serie erhalten, aber nur noch fuer die SONDERBADGES —
// die Aurorasterne. Genau so steht es auf dem Board: „Es gibt KEINE violetten
// Stufenbadges mehr."
const BadgeStufenStil _stufe2 = BadgeStufenStil(
  stufe: 2,
  name: 'Silber',
  ziffer: 'II',
  farbe: Color(0xFF9FB0C6),
  farbeTief: Color(0xFF3E4854),
  farbeHell: Color(0xFFEDF2F9),
  symbol: Icons.bolt_rounded,
  form: BadgeStufenForm.sechseck,
);

const BadgeStufenStil _stufe3 = BadgeStufenStil(
  stufe: 3,
  name: 'Gold',
  ziffer: 'III',
  farbe: Color(0xFFF5CB5C),
  farbeTief: Color(0xFF7A5408),
  farbeHell: Color(0xFFFFEDB4),
  symbol: Icons.auto_awesome_rounded,
  form: BadgeStufenForm.zacken,
);

/// Meilensteine ohne Rangfolge: badge_14 (Pokal), badge_31 und badge_32.
///
/// 2026-09-01: Diamantfuenfeck in Cyan, so wie die Embleme. Vorher teilten
/// sich Meilensteine und Sonderbadges EINEN neutralen Stil; die neue Serie
/// unterscheidet sie deutlich, also tut die App es jetzt auch.
const BadgeStufenStil _meilenstein = BadgeStufenStil(
  stufe: 0,
  name: 'Meilenstein',
  ziffer: '',
  farbe: Color(0xFF15AECF),
  farbeTief: Color(0xFF084D5E),
  farbeHell: Color(0xFF8AE3F6),
  symbol: Icons.flag_rounded,
  form: BadgeStufenForm.kreis,
);

/// Sonderbadges ohne Rangfolge: badge_15, badge_16, badge_28, badge_57,
/// badge_58. Aurorastern in Violett und Magenta.
const BadgeStufenStil _sonder = BadgeStufenStil(
  stufe: 0,
  name: 'Sonder',
  ziffer: '',
  farbe: Color(0xFFD264E8),
  farbeTief: Color(0xFF4A0B57),
  farbeHell: Color(0xFFF0B8FA),
  symbol: Icons.auto_awesome_motion_rounded,
  form: BadgeStufenForm.zacken,
);

/// Welche Badges Meilensteine sind. Alles andere ohne Stufe ist ein
/// Sonderbadge.
///
/// Bewusst eine Liste statt eines neuen Feldes am Modell: `profiles.badges`
/// ist append-only, und die Badge-Datei traegt ausdruecklich die Regel, dass
/// bestehende Eintraege nicht angefasst werden. Eine Liste hier aendert nur
/// die Darstellung.
const Set<String> badgeMeilensteinIds = {'badge_14', 'badge_31', 'badge_32'};

const BadgeStufenStil _stufeOhne = _meilenstein;

/// Die drei Stufen in aufsteigender Reihenfolge, fuer Legenden und Tests.
const List<BadgeStufenStil> badgeStufenSkala = [_stufe1, _stufe2, _stufe3];

/// Der Stil zu einer Stufe.
///
/// [badgeId] entscheidet bei Stufe 0 zwischen Meilenstein (Cyan) und
/// Sonderbadge (Violett und Magenta). Ohne Angabe bleibt es beim Meilenstein,
/// so wie vor dem 01.09. — kein Aufrufer bricht dadurch.
BadgeStufenStil badgeStufenStil(int stufe, {String? badgeId}) =>
    switch (stufe) {
      1 => _stufe1,
      2 => _stufe2,
      3 => _stufe3,
      _ =>
        badgeId != null && !badgeMeilensteinIds.contains(badgeId)
            ? _sonder
            : _stufeOhne,
    };

// ---------------------------------------------------------------------------
// Geometrie
// ---------------------------------------------------------------------------

Offset _entlang(Offset von, Offset zu, double strecke) {
  final richtung = zu - von;
  final laenge = richtung.distance;
  if (laenge == 0) return von;
  final anteil = math.min(strecke, laenge / 2) / laenge;
  return von + richtung * anteil;
}

/// Polygonzug mit weich gerundeten Ecken. Scharfe Spitzen wirken auf dem
/// Handy schnell wie Bildfehler; die Rundung haelt die Silhouette erkennbar.
Path _gerundetesPolygon(List<Offset> ecken, double eckenRadius) {
  final pfad = Path();
  for (var i = 0; i < ecken.length; i++) {
    final jetzt = ecken[i];
    final vorher = ecken[(i - 1 + ecken.length) % ecken.length];
    final naechste = ecken[(i + 1) % ecken.length];
    final anfang = _entlang(jetzt, vorher, eckenRadius);
    final ende = _entlang(jetzt, naechste, eckenRadius);
    if (i == 0) {
      pfad.moveTo(anfang.dx, anfang.dy);
    } else {
      pfad.lineTo(anfang.dx, anfang.dy);
    }
    pfad.quadraticBezierTo(jetzt.dx, jetzt.dy, ende.dx, ende.dy);
  }
  pfad.close();
  return pfad;
}

/// Der Umriss einer Stufe, eingepasst in [feld].
Path badgeStufenPfad(BadgeStufenForm form, Rect feld) {
  final mitte = feld.center;
  final radius = math.min(feld.width, feld.height) / 2;
  switch (form) {
    case BadgeStufenForm.kreis:
      return Path()..addOval(Rect.fromCircle(center: mitte, radius: radius));
    case BadgeStufenForm.sechseck:
      final ecken = <Offset>[
        for (var i = 0; i < 6; i++)
          mitte +
              Offset(
                math.cos(-math.pi / 2 + i * math.pi / 3) * radius,
                math.sin(-math.pi / 2 + i * math.pi / 3) * radius,
              ),
      ];
      return _gerundetesPolygon(ecken, radius * 0.20);
    case BadgeStufenForm.zacken:
      const spitzen = 12;
      final innen = radius * 0.80;
      final ecken = <Offset>[
        for (var i = 0; i < spitzen * 2; i++)
          () {
            final winkel = -math.pi / 2 + i * math.pi / spitzen;
            final r = i.isEven ? radius : innen;
            return mitte + Offset(math.cos(winkel) * r, math.sin(winkel) * r);
          }(),
      ];
      return _gerundetesPolygon(ecken, radius * 0.09);
  }
}

// ---------------------------------------------------------------------------
// Die Fuellung — die Stufe steckt auch INNEN drin
// ---------------------------------------------------------------------------

/// 2026-08-24 (vucko woertlich): „das schlechteste soll nicht nur im kreis die
/// andere farbe haben sondern auch innen drinnen".
///
/// Bis hierher trug praktisch nur der RAND die Stufe. Die Fuellung war ein
/// Hauch der Leitfarbe (Deckkraft 0,34 nach 0,55) und lief bei allen drei
/// Stufen auf fast denselben dunklen Grund hinaus — gemessen lagen Stufe I und
/// Stufe III innen nur 1,23 : 1 auseinander. Wer die Stufe erkennen wollte,
/// musste die Raender vergleichen. Jetzt traegt die Flaeche selbst die Stufe.
///
/// NACHGERECHNET, nicht nach Gefuehl gewaehlt — gegen den App-Grund #0B0E14
/// und gegen [BadgeStufenStil.farbeHell], die als Symbol MITTEN auf dieser
/// Fuellung sitzt:
///   Innenhelligkeit (relative Leuchtdichte) Stufe I 0,057 · II 0,157 ·
///   III 0,144. Die unterste Stufe — Vuckos „das schlechteste" — liegt damit
///   INNEN klar unter den beiden anderen: 1,93 : 1 gegen Tuerkis, 1,81 : 1
///   gegen Violett. Vorher waren es 1,54 : 1 und 1,23 : 1, letzteres unter
///   jeder Wahrnehmungsschwelle.
///   Tuerkis und Violett liegen in der Helligkeit nah beieinander (1,07 : 1),
///   trennen sich aber im Farbton deutlich (Kanalabstand 0,70 von 3,0) — dazu
///   kommen wie bisher eigene Form und eigenes Symbol.
///   Symbol auf der Fuellung: Stufe I 4,7 : 1, Stufe II 4,2 : 1,
///   Stufe III 3,4 : 1. Die helle Stufe ist die knappste und liegt damit immer
///   noch ueber den 3 : 1 fuer grafische Elemente.
///
/// WARUM DIE TIEFFARBE UND NICHT DIE LEITFARBE DIE FLAECHE TRAEGT: Fuellt man
/// mit der satten Leitfarbe, faellt das helle Symbol darin zusammen — Tuerkis
/// #4FE6D4 unter #A8F7EC ergaebe 1,3 : 1. Die Flaeche bleibt deshalb im tiefen
/// Ende der Stufe und wird nur nach oben hin aufgehellt.
///
/// UND NICHT ZU DUNKEL: Das untere Ende des Verlaufs behaelt mindestens
/// 1,4 : 1 gegen den App-Grund. Eine noch tiefere Bronze-Fuellung sah im
/// ersten Anlauf aus wie ein GESPERRTES Abzeichen (gemessen 1,15 : 1) — genau
/// die Verwechslung, die hier nicht entstehen darf.
///
/// GESPERRT bleibt bewusst hohl: ein Hauch Farbe auf dem dunklen Grund. Der
/// Abstand zwischen „gesperrt" und „niedrigste Stufe" wird durch diese
/// Aenderung GROESSER (Deckkraft 0,10 gegen voll gedeckt), nicht kleiner.
///
/// `test/presentation/badge_stufen_darstellung_test.dart` rechnet das nach.
///
/// Mischung der Fuellung je Stufe. Negativ = zu Schwarz hin, positiv = zur
/// Leitfarbe hin. `oben` ist der Anfang des Verlaufs (oben links), `unten`
/// sein Ende (unten rechts).
// 2026-09-01: Die Anteile waren auf die alte Leiter getunt (Tuerkis und
// Violett sind dunkler als Silber und Gold). Mit den neuen Leitfarben fiel das
// Symbol auf der hellen Goldfuellung zusammen und eine gesperrte Goldstufe
// wirkte gefuellt statt hohl. Die Werte sind so nachgezogen, dass ALLE
// Lesbarkeitspruefungen in badge_stufen_darstellung_test wieder halten —
// keine einzige davon wurde gelockert.
const Map<int, ({double oben, double unten})> _innenMischung = {
  0: (oben: -0.05, unten: -0.20),
  1: (oben: 0.15, unten: -0.20),
  2: (oben: 0.15, unten: -0.20),
  3: (oben: 0.20, unten: -0.20),
};

Color _innenMischen(BadgeStufenStil stil, double anteil) => anteil >= 0
    ? Color.lerp(stil.farbeTief, stil.farbe, anteil)!
    : Color.lerp(stil.farbeTief, const Color(0xFF000000), -anteil)!;

/// Die beiden Stufen des Fuell-Verlaufs, von oben links nach unten rechts.
List<Color> badgeStufenInnenFarben(
  BadgeStufenStil stil, {
  required bool freigeschaltet,
}) {
  if (!freigeschaltet) {
    return [
      stil.farbe.withValues(alpha: 0.10),
      stil.farbeTief.withValues(alpha: 0.16),
    ];
  }
  final mischung = _innenMischung[stil.stufe] ?? _innenMischung[0]!;
  return [
    _innenMischen(stil, mischung.oben),
    _innenMischen(stil, mischung.unten),
  ];
}

// ---------------------------------------------------------------------------
// Bausteine
// ---------------------------------------------------------------------------

/// Zeichnet den Stufen-Rahmen. Fuellung als Verlauf, Rand in der Leitfarbe.
///
/// Gesperrte Badges werden fahl dargestellt. Die FORM bleibt dabei voll
/// gezeichnet und der Rand behaelt genug Deckkraft, damit die Stufe auch im
/// gesperrten Zustand ablesbar ist. Genau das war Vuckos Vorbehalt.
class BadgeStufenRahmenPainter extends CustomPainter {
  const BadgeStufenRahmenPainter({
    required this.stil,
    required this.freigeschaltet,
  });

  final BadgeStufenStil stil;
  final bool freigeschaltet;

  @override
  void paint(Canvas canvas, Size size) {
    final feld = Offset.zero & size;
    final pfad = badgeStufenPfad(stil.form, feld.deflate(1.2));

    canvas.drawPath(
      pfad,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: badgeStufenInnenFarben(stil, freigeschaltet: freigeschaltet),
        ).createShader(feld),
    );

    canvas.drawPath(
      pfad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = freigeschaltet ? 2.0 : 1.4
        ..strokeJoin = StrokeJoin.round
        ..color = stil.farbe.withValues(alpha: freigeschaltet ? 0.95 : 0.42),
    );
  }

  @override
  bool shouldRepaint(BadgeStufenRahmenPainter alt) =>
      alt.stil.stufe != stil.stufe || alt.freigeschaltet != freigeschaltet;
}

/// Das Familien-Emblem (PNG) in der Form seiner Stufe.
class BadgeStufenEmblem extends StatelessWidget {
  const BadgeStufenEmblem({
    super.key,
    required this.stufe,
    required this.groesse,
    required this.freigeschaltet,
    required this.child,
    this.innenAnteil = 0.70,
  });

  final int stufe;
  final double groesse;
  final bool freigeschaltet;
  final Widget child;

  /// Wie viel der Kantenlaenge das Emblem im Inneren belegt.
  final double innenAnteil;

  @override
  Widget build(BuildContext context) {
    final stil = badgeStufenStil(stufe);
    return SizedBox(
      width: groesse,
      height: groesse,
      child: CustomPaint(
        painter: BadgeStufenRahmenPainter(
          stil: stil,
          freigeschaltet: freigeschaltet,
        ),
        child: Center(
          child: SizedBox(
            width: groesse * innenAnteil,
            height: groesse * innenAnteil,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Die kleine Stufen-Marke fuer die Ecke einer Kachel: Form, Symbol, Ziffer.
///
/// Drei Merkmale auf engstem Raum. Die Ziffer bleibt erhalten, weil sie die
/// Reihenfolge benennt, die Form und Symbol nur andeuten.
class BadgeStufenMarke extends StatelessWidget {
  const BadgeStufenMarke({
    super.key,
    required this.stufe,
    required this.freigeschaltet,
    this.groesse = 20,
  });

  final int stufe;
  final bool freigeschaltet;
  final double groesse;

  @override
  Widget build(BuildContext context) {
    final stil = badgeStufenStil(stufe);
    final deckkraft = freigeschaltet ? 1.0 : 0.5;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: groesse,
          height: groesse,
          child: CustomPaint(
            painter: BadgeStufenRahmenPainter(
              stil: stil,
              freigeschaltet: freigeschaltet,
            ),
            child: Center(
              child: Icon(
                stil.symbol,
                size: groesse * 0.52,
                color: stil.farbeHell.withValues(alpha: deckkraft),
              ),
            ),
          ),
        ),
        if (stil.ziffer.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            stil.ziffer,
            style: TextStyle(
              color: stil.farbeHell.withValues(alpha: deckkraft),
              fontSize: groesse * 0.55,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ],
    );
  }
}

/// Ein winziger Stufen-Punkt fuer die Uebersicht: gefuellt = erreicht,
/// nur Umriss = noch offen. Drei davon nebeneinander sind der Stufenpfad
/// einer Familie.
class BadgeStufenPunkt extends StatelessWidget {
  const BadgeStufenPunkt({
    super.key,
    required this.stufe,
    required this.erreicht,
    this.groesse = 14,
  });

  final int stufe;
  final bool erreicht;
  final double groesse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: groesse,
      height: groesse,
      child: CustomPaint(
        painter: BadgeStufenRahmenPainter(
          stil: badgeStufenStil(stufe),
          freigeschaltet: erreicht,
        ),
      ),
    );
  }
}

/// Der Stufenpfad einer Familie: drei Punkte in Bronze, Tuerkis, Violett.
class BadgeStufenPfadLeiste extends StatelessWidget {
  const BadgeStufenPfadLeiste({
    super.key,
    required this.erreichteStufen,
    this.punktGroesse = 14,
    this.abstand = 4,
  });

  /// Wie viele Stufen der Familie schon geschafft sind (0 bis 3).
  final int erreichteStufen;

  final double punktGroesse;
  final double abstand;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var s = 1; s <= 3; s++) ...[
          if (s > 1) SizedBox(width: abstand),
          BadgeStufenPunkt(
            stufe: s,
            erreicht: s <= erreichteStufen,
            groesse: punktGroesse,
          ),
        ],
      ],
    );
  }
}
