import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:cruise_connect/core/routen_kappung.dart';

/// Nachgezeichnete Strecke OHNE Karte (2026-08-28, Fehler 7 und 8).
///
/// Geteilte Routen zeigten bisher einen Kartenausschnitt mit Ortsnamen,
/// Doerfern und dem exakten Start- und Zielpunkt — meist die Haustuer des
/// Besitzers. Diese Skizze zeichnet NUR den Verlauf der Linie auf neutralem,
/// dunklem Grund, im Stil des Export-Composers (route_share_page):
/// Verlaufslinie mit rundem Abschluss, dezenter Start- und Zielpunkt OHNE
/// Beschriftung. Keine Basemap, keine Ortsnamen, kein Massstab.
///
/// Die Punkte werden vor dem Zeichnen standardmaessig um
/// [anzeigeKappungMeter] je Ende gekappt (kappeEndstuecke). Aufrufer, die
/// bereits gekappte Punkte uebergeben, setzen [kappungMeter] auf 0.
class RouteVerlaufSketch extends StatelessWidget {
  const RouteVerlaufSketch({
    super.key,
    required this.punkte,
    required this.accent,
    this.abschnitte,
    this.kappungMeter = anzeigeKappungMeter,
    this.hintergrund = const Color(0xFF10141B),
    this.borderRadius,
  });

  /// Flache [longitude, latitude]-Liste (Mapbox-Format), z. B. aus
  /// `SavedRoute.flattenGeometryCoordinates` — traegt auch MultiLineString.
  final List<List<double>> punkte;

  final Color accent;

  /// Die ECHTEN Abschnitte der Geometrie, falls bekannt.
  ///
  /// Ist das gesetzt, wird die Linie genau dort und nur dort unterbrochen —
  /// nichts wird am Abstand erraten. Ein MultiLineString traegt seine Luecken
  /// selbst; eine geplante Route hat gar keine, sie ist eine gerechnete Linie.
  final List<List<List<double>>>? abschnitte;

  /// Meter, die je Ende vor dem Zeichnen entfernt werden. 0 = Punkte sind
  /// schon gekappt (oder es ist die eigene Route).
  final double kappungMeter;

  final Color hintergrund;
  final BorderRadius? borderRadius;

  List<List<List<double>>>? _gekappteAbschnitte() {
    final roh = abschnitte?.where((t) => t.length >= 2).toList(growable: false);
    if (roh == null || roh.isEmpty) return null;
    if (kappungMeter <= 0) return roh;
    if (roh.length == 1) {
      final einzeln = kappeEndstuecke(roh.first, kappungMeter, kappungMeter);
      return einzeln.length >= 2 ? <List<List<double>>>[einzeln] : null;
    }
    final erste = kappeEndstuecke(roh.first, kappungMeter, 0);
    final letzte = kappeEndstuecke(roh.last, 0, kappungMeter);
    final ergebnis = <List<List<double>>>[
      if (erste.length >= 2) erste,
      ...roh.sublist(1, roh.length - 1),
      if (letzte.length >= 2) letzte,
    ];
    return ergebnis.isEmpty ? null : ergebnis;
  }

  @override
  Widget build(BuildContext context) {
    final gezeichnet = kappungMeter > 0
        ? kappeEndstuecke(punkte, kappungMeter, kappungMeter)
        : punkte;
    // Die Endstuecke werden gekappt, damit Start und Ziel nicht die Haustuer
    // des Besitzers verraten. Das muss auch fuer die Abschnitte gelten —
    // sonst zeichnete die Skizze ueber die Abschnitte genau die Enden, die
    // die Kappung eben entfernt hat. Gekappt wird nur vorn am ERSTEN und
    // hinten am LETZTEN Abschnitt; die Grenzen dazwischen sind Luecken, keine
    // Enden.
    final gezeichneteAbschnitte = _gekappteAbschnitte();
    // 2026-09-01 (Vucko: „das layout beim teilen ... nicht mit einem schwarzen
    // hintergrund sondern das es einfach viel ansprechender fuer die leute
    // aussieht"):
    //
    // Der Grund war ein flaches 0xFF10141B — DUNKLER als die Karte darum
    // herum (0xFF1C1F26). Dadurch wirkte das Feld wie ein Loch im Beitrag.
    // Die Karte darf trotzdem nicht zurueck: Start und Ziel liegen meist an
    // der Haustuer des Besitzers, ein Ausschnitt mit Ortsnamen verriete die
    // Adresse (Fehler 7 vom 28.08.).
    //
    // Also: derselbe Schutz, aber Tiefe statt Leere. Ein weicher Verlauf von
    // oben nach unten, leicht in Richtung Akzentfarbe getoent, plus ein
    // dezenter Schein hinter der Linie. Es verraet nichts und sieht nach
    // etwas aus.
    final oben = Color.lerp(hintergrund, accent, 0.10)!;
    final unten = Color.lerp(hintergrund, Colors.black, 0.35)!;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [oben, hintergrund, unten],
          stops: const [0, 0.55, 1],
        ),
        borderRadius: borderRadius ?? BorderRadius.circular(14),
      ),
      clipBehavior: borderRadius == BorderRadius.zero
          ? Clip.none
          : Clip.antiAlias,
      child: gezeichnet.length < 2
          ? const Center(
              child: Icon(Icons.route_rounded, color: Colors.white24, size: 28),
            )
          : CustomPaint(
              size: Size.infinite,
              painter: RouteVerlaufPainter(
                punkte: gezeichnet,
                accent: accent,
                abschnitte: gezeichneteAbschnitte,
              ),
            ),
    );
  }
}

/// Zeichnet die (bereits gekappte) Linie: Halo, Verlaufslinie von Akzent zu
/// einer helleren Stufe, runde Enden, dezente Punkte an Anfang und Ende —
/// bewusst ohne jede Beschriftung.
class RouteVerlaufPainter extends CustomPainter {
  RouteVerlaufPainter({
    required this.punkte,
    required this.accent,
    this.abschnitte,
  });

  final List<List<double>> punkte;
  final Color accent;
  final List<List<List<double>>>? abschnitte;

  @override
  void paint(Canvas canvas, Size size) {
    if (punkte.length < 2 || size.isEmpty) return;

    var minLng = punkte.first[0], maxLng = punkte.first[0];
    var minLat = punkte.first[1], maxLat = punkte.first[1];
    for (final p in punkte) {
      minLng = math.min(minLng, p[0]);
      maxLng = math.max(maxLng, p[0]);
      minLat = math.min(minLat, p[1]);
      maxLat = math.max(maxLat, p[1]);
    }
    // 2026-09-01: Der Rand war fest 16 px je Seite. In der schmalen
    // Feed-Fassung ist der Kasten nur 84 px hoch — 32 px Rand fressen dort
    // ueber ein Drittel der Hoehe, und die Strecke schrumpft auf ein
    // Gebilde von rund 52 px in einem 340 px breiten Band. Genau das sah
    // Vucko als „klein und nicht mittig". Der Rand richtet sich jetzt nach
    // der kleineren Seite.
    final pad = math.max(6.0, math.min(size.width, size.height) * 0.10);
    final lngSpan = math.max(maxLng - minLng, 0.0001);
    final latSpan = math.max(maxLat - minLat, 0.0001);
    // Laengengrade werden zum Pol hin schmaler — ohne Korrektur wirkt die
    // Strecke in Ost-West-Richtung gestaucht. cos(Breite) reicht fuer eine
    // Skizze vollkommen.
    final latMitte = (minLat + maxLat) / 2 * math.pi / 180.0;
    final lngFaktor = math.max(math.cos(latMitte).abs(), 0.05);
    final scale = math.min(
      (size.width - 2 * pad) / (lngSpan * lngFaktor),
      (size.height - 2 * pad) / latSpan,
    );
    final w = lngSpan * lngFaktor * scale, h = latSpan * scale;
    final ox = (size.width - w) / 2, oy = (size.height - h) / 2;
    Offset project(List<double> p) => Offset(
          ox + (p[0] - minLng) * lngFaktor * scale,
          oy + (maxLat - p[1]) * scale,
        );

    // 2026-09-01: Ein einziger durchgehender Pfad ueber die abgeflachte
    // Punktliste zog bei einer aufgezeichneten Fahrt mit GPS-Luecke
    // (MultiLineString) eine gerade Bruecke ueber die Luecke. Die blaeht die
    // Umgrenzung auf und draengt die echte Strecke in eine Ecke. Der
    // Export-Composer macht es laengst richtig und zeichnet je Segment.
    //
    // Am selben Tag nachgebessert: Hier stand danach eine Abstandsregel mit
    // 400 Metern, die die Segmentgrenzen erraten sollte, nachdem sie
    // weggeworfen worden waren. An echten Strecken gemessen zerriss sie 9 von
    // 73 geplanten Routen, groesster echter Schritt 3143 m — durchgehende
    // Schnellstrassen mit duenner Stuetzpunktfolge, wo gar keine Luecke ist.
    //
    // Jetzt wird nichts mehr geraten. Eine GEPLANTE Route ist eine gerechnete
    // Linie und hat definitionsgemaess keine Luecke; eine AUFZEICHNUNG mit
    // Luecke ist ein MultiLineString und traegt ihre Grenzen selbst. Wer die
    // Abschnitte kennt, reicht sie durch — alle anderen bekommen einen
    // durchgehenden Zug, so wie es fuer eine geplante Route richtig ist.
    final gefiltert = abschnitte
        ?.where((teil) => teil.length >= 2)
        .toList(growable: false);
    final teile = (gefiltert == null || gefiltert.isEmpty)
        ? <List<List<double>>>[punkte]
        : gefiltert;
    final path = Path();
    for (final teil in teile) {
      final anfang = project(teil.first);
      path.moveTo(anfang.dx, anfang.dy);
      for (var i = 1; i < teil.length; i++) {
        final pr = project(teil[i]);
        path.lineTo(pr.dx, pr.dy);
      }
    }
    // Anfang und Ende der GESAMTEN Skizze — fuer den Farbverlauf und die
    // beiden Endpunkte.
    final start = project(teile.first.first);
    final ende = project(teile.last.last);

    // Strichstaerke nach der Kastengroesse. In der schmalen Feed-Fassung war
    // eine 4 px dicke Linie auf einem grossen dunklen Feld schlicht duenn.
    final dickeBasis = math.min(size.width, size.height);
    final strich = (dickeBasis * 0.055).clamp(3.5, 7.0);

    // Statt eines schwarzen Schattens ein Schein in der Akzentfarbe. Er hebt
    // die Linie vom Grund ab, ohne sie stumpf zu machen.
    final schein = Paint()
      ..color = accent.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strich * 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, strich * 1.1);
    final halo = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strich * 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final hell = Color.lerp(accent, Colors.white, 0.45)!;
    final linie = Paint()
      ..shader = ui.Gradient.linear(start, ende, [accent, hell])
      ..style = PaintingStyle.stroke
      ..strokeWidth = strich
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, schein);
    canvas.drawPath(path, halo);
    canvas.drawPath(path, linie);

    // Dezente Endpunkte OHNE Beschriftung — sie markieren nur den Anfang und
    // das Ende der GEKAPPTEN Linie, nie die echte Adresse.
    final punktR = (strich * 1.25).clamp(4.0, 8.0);
    canvas.drawCircle(start, punktR, Paint()..color = Colors.white);
    canvas.drawCircle(start, punktR * 0.56, Paint()..color = accent);
    canvas.drawCircle(ende, punktR, Paint()..color = Colors.white);
    canvas.drawCircle(
      ende,
      punktR * 0.56,
      Paint()..color = const Color(0xFFFFD166),
    );
  }

  /// Grober Abstand zweier [lng, lat]-Punkte in Metern.
  ///
  /// Reicht vollkommen, um eine GPS-Luecke von einem normalen Streckenschritt
  /// zu unterscheiden; eine echte Haversine-Rechnung waere hier verschwendet.

  @override
  bool shouldRepaint(RouteVerlaufPainter old) =>
      old.punkte != punkte ||
      old.accent != accent ||
      old.abschnitte != abschnitte;
}
