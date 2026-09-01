/// Erkennt Kehrtwenden in einer Streckengeometrie.
///
/// 2026-09-01 (Vucko: „die routen die jetzt im routenpool gespeichert sind und
/// genehmigt werden von der app keine wendepunkte mitten auf den strassen
/// erlauben"):
///
/// Diese Datei ist eine ZEICHENGENAUE Portierung von `kehrtwendenZaehler` und
/// `ueberlappRaster` aus `supabase/functions/generate-cruise-route-v2/
/// index.ts`. Der Server rechnet die Kennzahl fuer frisch erzeugte Routen; die
/// App braucht sie fuer alles, was NICHT frisch vom Server kommt — Pool-Zeilen
/// ohne Kennzahl, wiederholte Fahrten, geteilte Strecken.
///
/// Die beiden Fassungen MUESSEN gleich rechnen, sonst faellt eine Strecke je
/// nach Weg mal durch und mal nicht. Der Test
/// `test/route/kehrtwenden_portierung_test.dart` liest beide Dateien und
/// schlaegt fehl, sobald eine Konstante auseinanderlaeuft.
///
/// Koordinaten sind ueberall `[longitude, latitude]` (Mapbox-Format).
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Schrittweite des Rasters, auf das die Strecke umgelegt wird.
const double kehrtwendeRasterM = 25;

/// Wie nah sich Hin- und Rueckrichtung kommen muessen, damit es dieselbe
/// Strasse ist.
const double kehrtwendeNaeheM = 40;

/// Kuerzer als das ist es eine enge Kehre (Serpentine), keine Wende.
const double kehrtwendeMinWegM = 150;

/// Laenger als das ist es eine Ueberlappung, keine Wende.
const double kehrtwendeMaxWegM = 6000;

/// Wie gegenlaeufig zwei Richtungen sein muessen. -0.5 entspricht mehr als
/// 120 Grad.
const double kehrtwendeGegenlaeufigCos = -0.5;

/// Kantenlaenge der Suchzellen. Muss groesser als [kehrtwendeNaeheM] sein,
/// sonst uebersieht die Nachbarschaftssuche Treffer.
const double kehrtwendeZelleM = 120;

/// Wie stark zwei benachbarte Treffer auseinanderliegen duerfen und trotzdem
/// als EINE Wende gelten.
const int kehrtwendeBuendelToleranz = 12;

/// Wie viel Strecke vor dem Stich und nach der Rueckkehr liegen muss, damit
/// die Wende als „mittendrin" gilt.
///
/// Darunter ist sie die Lage von Start oder Ziel und damit unvermeidbar: eine
/// Sackgasse vor der Haustuer kann keine Route wegplanen.
const double kehrtwendeRandM = 300;

/// Obergrenze der Rasterpunkte. Schuetzt vor einer Endlosschleife bei
/// kaputten Geometrien.
const int ueberlappMaxPunkte = 20000;

/// Wie weit vor und hinter dem Scheitel der Kurs gemessen wird, um zu pruefen,
/// ob dort wirklich gedreht wird.
const double kehrtwendeDrehFensterM = 100;

/// Ab wie viel Grad Kursaenderung am Scheitel es eine echte Wende ist.
///
/// 2026-09-01 nachgemessen: Ohne diese Pruefung meldete die Zaehlung an 40
/// echten Pool-Strecken 66 Wenden — an 21 davon dreht die Strecke am Scheitel
/// gar nicht (teils nur 22 Grad). Das sind lange Stellen, an denen die Route
/// nur in der Naehe ihrer selbst zurueckläuft, ohne dass jemand wenden muss.
/// Ein Tor auf der ungepruefeten Zahl haette also jede dritte Strecke aus
/// einem Grund abgelehnt, den es nicht gibt.
///
/// 140 Grad und nicht 180: An einer echten Wende liegt die Gegenfahrbahn ein
/// paar Meter versetzt, und die Rasterung glaettet die Spitze etwas ab.
const double kehrtwendeDrehGrad = 140;

/// Eine einzelne gefundene Wende.
///
/// Die Meterangaben beziehen sich auf die Strecke ab Start, gemessen im
/// Raster — nicht auf den Index der Rohkoordinaten.
class KehrtwendenStelle {
  const KehrtwendenStelle({
    required this.beginnM,
    required this.rueckkehrM,
    required this.mittendrin,
  });

  /// Wo der Stich beginnt (Meter ab Start).
  final double beginnM;

  /// Wo die Strecke wieder an diesem Punkt vorbeikommt.
  final double rueckkehrM;

  /// Ob vor UND nach der Wende noch echte Strecke liegt.
  final bool mittendrin;

  /// Die Laenge des Stichs.
  double get laengeM => rueckkehrM - beginnM;

  /// Die Spitze der Wende, also wo tatsaechlich gedreht wird.
  double get scheitelM => beginnM + laengeM / 2;
}

/// Das Ergebnis der Zaehlung.
class KehrtwendenBefund {
  const KehrtwendenBefund({
    required this.anzahl,
    required this.anzahlMitte,
    required this.maxLaengeM,
    this.stellen = const <KehrtwendenStelle>[],
  });

  /// Alle Wenden, auch die am Rand.
  final int anzahl;

  /// Nur die Wenden MITTENDRIN — die vermeidbaren.
  final int anzahlMitte;

  /// Die laengste Stichstrecke in Metern.
  final int maxLaengeM;

  /// Jede einzelne Wende mit ihrer Lage. Fuer Diagnose und Nachweis: ohne sie
  /// laesst sich nicht pruefen, ob an der gemeldeten Stelle wirklich gedreht
  /// wird.
  final List<KehrtwendenStelle> stellen;

  static const KehrtwendenBefund keine = KehrtwendenBefund(
    anzahl: 0,
    anzahlMitte: 0,
    maxLaengeM: 0,
  );

  /// Ob diese Strecke den Nutzer mitten auf der Strasse wenden liesse.
  bool get hatWendeMittendrin => anzahlMitte > 0;
}

/// Legt die Strecke auf ein gleichmaessiges Meterraster um.
///
/// Ohne diesen Schritt haengt jede Aussage ueber „wie weit auseinander" an der
/// Dichte der Stuetzpunkte: GraphHopper setzt in einer Kurve zwanzig Punkte
/// und auf der Geraden zwei.
({Float64List xs, Float64List ys, int n}) ueberlappRaster(
  List<List<double>> coords,
  double schrittM,
) {
  if (coords.isEmpty) {
    return (xs: Float64List(0), ys: Float64List(0), n: 0);
  }
  final lat0 = coords[0][1];
  final lng0 = coords[0][0];
  final mProLng = 111320 * math.cos(lat0 * math.pi / 180);
  const mProLat = 110540.0;

  final px = <double>[];
  final py = <double>[];
  var vx = 0.0;
  var vy = 0.0;
  px.add(0);
  py.add(0);
  var rest = schrittM;

  for (var i = 1; i < coords.length; i++) {
    final punkt = coords[i];
    if (punkt.length < 2) continue;
    final nx = (punkt[0] - lng0) * mProLng;
    final ny = (punkt[1] - lat0) * mProLat;
    var dx = nx - vx;
    var dy = ny - vy;
    var len = math.sqrt(dx * dx + dy * dy);
    // `len > 0` ist Pflicht: GraphHopper liefert gelegentlich zwei identische
    // Stuetzpunkte hintereinander. Ohne die Bedingung teilt die naechste Zeile
    // durch null und die ganze Kennzahl wird NaN.
    while (len > 0 && len >= rest && px.length < ueberlappMaxPunkte) {
      vx += (dx / len) * rest;
      vy += (dy / len) * rest;
      px.add(vx);
      py.add(vy);
      dx = nx - vx;
      dy = ny - vy;
      len = math.sqrt(dx * dx + dy * dy);
      rest = schrittM;
    }
    rest -= len;
    vx = nx;
    vy = ny;
  }
  return (
    xs: Float64List.fromList(px),
    ys: Float64List.fromList(py),
    n: px.length,
  );
}

/// Der Kurs zwischen zwei Rasterpunkten, in Grad.
double _kurs(double dx, double dy) => math.atan2(dx, dy) * 180 / math.pi;

/// Der kleinere Winkel zwischen zwei Kursen, 0 bis 180.
double _kursDifferenz(double a, double b) {
  var d = (a - b).abs() % 360;
  if (d > 180) d = 360 - d;
  return d;
}

/// Dreht die Strecke am Rasterpunkt [scheitel] wirklich um?
///
/// Ohne diese Pruefung meldet die Partnersuche auch Stellen, an denen die
/// Route nur nah an sich selbst vorbeilaeuft — parallel, ohne dass jemand
/// anhalten und wenden muesste.
bool _drehtDortWirklich(
  Float64List xs,
  Float64List ys,
  int n,
  int scheitel,
) {
  final fenster = (kehrtwendeDrehFensterM / kehrtwendeRasterM).round();
  final davor = scheitel - fenster;
  final danach = scheitel + fenster;
  if (davor < 0 || danach >= n) return false;
  final kursDavor = _kurs(xs[scheitel] - xs[davor], ys[scheitel] - ys[davor]);
  final kursDanach = _kurs(xs[danach] - xs[scheitel], ys[danach] - ys[scheitel]);
  return _kursDifferenz(kursDavor, kursDanach) >= kehrtwendeDrehGrad;
}

/// Zaehlt die Kehrtwenden einer Strecke.
///
/// Eine Kehrtwende ist eine Stelle, an der die Strecke auf DERSELBEN Strasse
/// zurueckkommt, aus der sie hergekommen ist. Erkannt wird sie daran, dass
/// zwei Rasterpunkte raeumlich nah beieinanderliegen, in der Reihenfolge aber
/// weit auseinander, und ihre Fahrtrichtungen gegenlaeufig sind.
KehrtwendenBefund kehrtwendenZaehler(List<List<double>> coords) {
  if (coords.length < 2) return KehrtwendenBefund.keine;

  final raster = ueberlappRaster(coords, kehrtwendeRasterM);
  final xs = raster.xs;
  final ys = raster.ys;
  final n = raster.n;

  final minSchritte = (kehrtwendeMinWegM / kehrtwendeRasterM).round();
  final maxSchritte = (kehrtwendeMaxWegM / kehrtwendeRasterM).round();
  if (n <= minSchritte + 2) return KehrtwendenBefund.keine;

  // Fahrtrichtung je Rasterpunkt als Einheitsvektor (Nachbar davor/danach).
  final rx = Float64List(n);
  final ry = Float64List(n);
  for (var i = 0; i < n; i++) {
    final a = i > 0 ? i - 1 : 0;
    final b = i < n - 1 ? i + 1 : n - 1;
    var dx = xs[b] - xs[a];
    var dy = ys[b] - ys[a];
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > 0) {
      dx /= len;
      dy /= len;
    }
    rx[i] = dx;
    ry[i] = dy;
  }

  const zelle = kehrtwendeZelleM;
  final gitter = <int, List<int>>{};
  int schluessel(int cx, int cy) => cx * 1000003 + cy;
  for (var i = 0; i < n; i++) {
    final k = schluessel(
      (xs[i] / zelle).floor(),
      (ys[i] / zelle).floor(),
    );
    gitter.putIfAbsent(k, () => <int>[]).add(i);
  }

  const naeheQuadrat = kehrtwendeNaeheM * kehrtwendeNaeheM;
  // Fuer jeden Punkt i der FRUEHESTE gegenlaeufige Partner j > i im Fenster.
  // Der fruehste, damit die Wende an ihrer Spitze gemessen wird und nicht an
  // einem spaeteren Zufallstreffer.
  final partner = Int32List(n);
  for (var i = 0; i < n; i++) {
    partner[i] = -1;
  }
  for (var i = 0; i < n; i++) {
    final cx = (xs[i] / zelle).floor();
    final cy = (ys[i] / zelle).floor();
    var bester = -1;
    for (var ox = -1; ox <= 1; ox++) {
      for (var oy = -1; oy <= 1; oy++) {
        final eimer = gitter[schluessel(cx + ox, cy + oy)];
        if (eimer == null) continue;
        for (final j in eimer) {
          final abstandSchritte = j - i;
          if (abstandSchritte <= minSchritte) continue; // zu nah = enge Kehre
          if (abstandSchritte > maxSchritte) continue; // zu weit = Ueberlappung
          final dx = xs[j] - xs[i];
          final dy = ys[j] - ys[i];
          if (dx * dx + dy * dy > naeheQuadrat) continue;
          if (rx[i] * rx[j] + ry[i] * ry[j] > kehrtwendeGegenlaeufigCos) {
            continue;
          }
          if (bester < 0 || j < bester) bester = j;
        }
      }
    }
    partner[i] = bester;
  }

  var anzahl = 0;
  var anzahlMitte = 0;
  final gesamtM = n * kehrtwendeRasterM;
  var i = 0;
  var maxLaengeM = 0.0;
  final stellen = <KehrtwendenStelle>[];
  while (i < n) {
    if (partner[i] < 0) {
      i++;
      continue;
    }
    final start = i;
    final rueckkehr = partner[i];
    while (i + 1 < n &&
        partner[i + 1] >= 0 &&
        (partner[i + 1] - partner[i]).abs() <= kehrtwendeBuendelToleranz) {
      i++;
    }
    anzahl++;
    final laengeM = (partner[start] - start) * kehrtwendeRasterM;
    if (laengeM > maxLaengeM) maxLaengeM = laengeM;

    // Liegt die Wende am Rand der Strecke oder mittendrin?
    //
    // Nicht am Scheitel gemessen, sondern daran, WIE VIEL STRECKE davor und
    // danach noch kommt. Eine 400-Meter-Sackgasse am Ziel hat ihren Scheitel
    // 400 Meter vor dem Ende — eine Scheitelmessung wuerde sie faelschlich als
    // „mittendrin" zaehlen und aus „musste wenden" ein „keine Route" machen.
    //
    // Kommt vor dem Stich oder nach der Rueckkehr fast nichts mehr, ist die
    // Wende die Lage von Start oder Ziel und damit unvermeidbar. Liegt vor UND
    // nach ihr echte Strecke, ist sie ein Routenfehler — genau der Fall, den
    // Vucko gefahren ist.
    final vorDemStichM = start * kehrtwendeRasterM;
    final nachDerRueckkehrM = gesamtM - partner[start] * kehrtwendeRasterM;
    // Mittendrin heisst: vor UND nach der Wende liegt echte Strecke, UND an
    // ihrem Scheitel dreht die Route auch wirklich um. Die zweite Bedingung
    // ist kein Beiwerk — ohne sie ist jede dritte Meldung falsch.
    final scheitel = ((start + partner[start]) / 2).round();
    final mittendrin = vorDemStichM > kehrtwendeRandM &&
        nachDerRueckkehrM > kehrtwendeRandM &&
        _drehtDortWirklich(xs, ys, n, scheitel);
    if (mittendrin) anzahlMitte++;
    stellen.add(
      KehrtwendenStelle(
        beginnM: vorDemStichM,
        rueckkehrM: partner[start] * kehrtwendeRasterM,
        mittendrin: mittendrin,
      ),
    );

    // Bis zum Rueckkehrpunkt springen: sonst zaehlt der Rueckweg denselben
    // Stich ein zweites Mal.
    i = math.max(i + 1, rueckkehr);
  }

  return KehrtwendenBefund(
    anzahl: anzahl,
    anzahlMitte: anzahlMitte,
    maxLaengeM: maxLaengeM.round(),
    stellen: List<KehrtwendenStelle>.unmodifiable(stellen),
  );
}
