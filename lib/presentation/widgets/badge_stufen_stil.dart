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
  farbeTief: Color(0xFF7E2409),
  farbeHell: Color(0xFFFF9A63),
  symbol: Icons.local_fire_department_rounded,
  form: BadgeStufenForm.kreis,
);

const BadgeStufenStil _stufe2 = BadgeStufenStil(
  stufe: 2,
  name: 'Türkis',
  ziffer: 'II',
  farbe: Color(0xFF4FE6D4),
  farbeTief: Color(0xFF0A6E7C),
  farbeHell: Color(0xFFA8F7EC),
  symbol: Icons.bolt_rounded,
  form: BadgeStufenForm.sechseck,
);

const BadgeStufenStil _stufe3 = BadgeStufenStil(
  stufe: 3,
  name: 'Violett',
  ziffer: 'III',
  farbe: Color(0xFFAE93FF),
  farbeTief: Color(0xFF3B3FA8),
  farbeHell: Color(0xFFD6C4FF),
  symbol: Icons.auto_awesome_rounded,
  form: BadgeStufenForm.zacken,
);

/// Meilensteine ohne Rangfolge (Gruendungszeit, Startklar, 1.000 km …).
/// Bewusst neutral, damit sie die Skala nicht verwaessern.
const BadgeStufenStil _stufeOhne = BadgeStufenStil(
  stufe: 0,
  name: 'Meilenstein',
  ziffer: '',
  farbe: Color(0xFF9AA7BD),
  farbeTief: Color(0xFF2A3242),
  farbeHell: Color(0xFFC8D2E2),
  symbol: Icons.flag_rounded,
  form: BadgeStufenForm.kreis,
);

/// Die drei Stufen in aufsteigender Reihenfolge, fuer Legenden und Tests.
const List<BadgeStufenStil> badgeStufenSkala = [_stufe1, _stufe2, _stufe3];

BadgeStufenStil badgeStufenStil(int stufe) => switch (stufe) {
  1 => _stufe1,
  2 => _stufe2,
  3 => _stufe3,
  _ => _stufeOhne,
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
          colors: [
            stil.farbe.withValues(alpha: freigeschaltet ? 0.34 : 0.10),
            stil.farbeTief.withValues(alpha: freigeschaltet ? 0.55 : 0.16),
          ],
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
