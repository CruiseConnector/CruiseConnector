/// 2026-08-19 (vucko woertlich): „… und das man wirklich einen ueberblick hat"
///
/// Vorher stand ueber der Sammlung nur ein Zaehler „23/54 freigeschaltet" und
/// darunter siebzehn Bloecke, die man einzeln durchscrollen musste. Wo jemand
/// steht, liess sich nur durch Scrollen zusammensuchen; was als Naechstes
/// dran ist, ueberhaupt nicht.
///
/// Diese Uebersicht beantwortet drei Fragen ohne Scrollen:
///   1. Was bedeuten die Stufen? -> Legende mit Form, Farbe, Symbol und wie
///      viele Badges der jeweiligen Stufe schon offen sind.
///   2. Wo stehe ich ueberall? -> Drei Schubladen („In Arbeit", „Geschafft",
///      „Noch nicht begonnen"), in denen die Familien mit ihrem Stufenpfad
///      liegen. Gefuellter Punkt = geschafft, Umriss = offen.
///   3. Was ist als Naechstes dran? -> Die drei Ziele, denen man am naechsten
///      ist, mit Balken und Restweg.
///
/// 2026-08-24 (vucko woertlich): „die stufen badges sollen noch besser
/// angezeigt werden man scrollt da endlos". Punkt 2 war bis dahin EIN Wrap
/// ueber alle siebzehn Familien am Stueck. Seit dieser Fassung liegen sie in
/// aufklappbaren Schubladen — Begruendung bei [badgeFamilienGruppen].
///
/// Erst darunter kommen die Familien-Bloecke mit den Kacheln, die Vucko
/// ausdruecklich behalten wollte.
library;

import 'package:flutter/material.dart';

import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/presentation/widgets/badge_stufen_stil.dart';

/// Ein Ziel, dem der Nutzer gerade am naechsten ist.
class BadgeNaechstesZiel {
  const BadgeNaechstesZiel({
    required this.familie,
    required this.badge,
    required this.fortschritt,
  });

  final app.BadgeFamilie familie;
  final app.Badge badge;
  final app.BadgeFortschritt fortschritt;
}

/// Das Badge, auf das der Balken einer Familie tatsaechlich zeigt.
///
/// WICHTIG: `Badge.naechsteStufe` geht die Familie in Stufen-Reihenfolge
/// durch, `badgeFamilienFortschritt` nimmt die kleinste noch offene SCHWELLE.
/// Bei „Kilometer" faellt das auseinander: nach 500 km ist die kleinste
/// offene Schwelle 1.000 km (Meilenstein badge_31), die naechste Stufe aber
/// 2.500 km. Stuenden Name und Balken aus verschiedenen Quellen, zeigte die
/// Uebersicht „2.500 km" ueber einem Balken, der gegen 1.000 rechnet. Diese
/// Funktion benutzt deshalb dieselbe Regel wie der Fortschritt.
app.Badge? badgeZielBadge(app.BadgeFamilie familie, Set<String> erreichteIds) {
  app.BadgeStufe? naechste;
  for (final stufe in familie.alleStufen) {
    if (erreichteIds.contains(stufe.id)) continue;
    if (naechste == null || stufe.schwelle < naechste.schwelle) {
      naechste = stufe;
    }
  }
  if (naechste == null) return null;
  return app.Badge.getById(naechste.id);
}

/// Die naechsten Ziele, sortiert nach Naehe. Reine Rechenfunktion, damit der
/// Test sie ohne Widget-Baum pruefen kann.
List<BadgeNaechstesZiel> badgeNaechsteZiele({
  required Set<String> erreichteIds,
  required Map<app.BadgeMetrik, double> metriken,
  int anzahl = 3,
}) {
  final ziele = <BadgeNaechstesZiel>[];
  for (final familie in app.badgeFamilien) {
    final fortschritt = app.badgeFamilienFortschritt(
      familie: familie.schluessel,
      erreichteBadgeIds: erreichteIds,
      metriken: metriken,
    );
    if (fortschritt == null) continue;
    final badge = badgeZielBadge(familie, erreichteIds);
    if (badge == null) continue;
    ziele.add(
      BadgeNaechstesZiel(
        familie: familie,
        badge: badge,
        fortschritt: fortschritt,
      ),
    );
  }
  // Am naechsten zuerst. Bei Gleichstand entscheidet der kleinere Restweg,
  // sonst waere die Reihenfolge zwischen zwei 0-Prozent-Zielen zufaellig.
  ziele.sort((a, b) {
    final v = b.fortschritt.anteil.compareTo(a.fortschritt.anteil);
    if (v != 0) return v;
    final ra = a.fortschritt.ziel - a.fortschritt.aktuell;
    final rb = b.fortschritt.ziel - b.fortschritt.aktuell;
    return ra.compareTo(rb);
  });
  return ziele.take(anzahl).toList();
}

/// „noch 226 km" statt „274 von 500 km" — beim Restweg zaehlt, was fehlt.
///
/// 2026-08-19 (nach dem Blick auf den Simulator): Bei genau einem fehlenden
/// Schritt stand hier „noch 1 Fahrten". Die Einheiten in badge.dart sind alle
/// im Plural gefuehrt, weil sie sonst meistens falsch waeren — fuer den
/// Sonderfall 1 braucht es die Einzahl.
String badgeRestweg(app.BadgeFortschritt fortschritt) {
  final rest = (fortschritt.ziel - fortschritt.aktuell).clamp(
    0.0,
    double.infinity,
  );
  final gerundet = rest.ceil();
  return 'noch ${badgeZahl(gerundet)} '
      '${badgeEinheit(fortschritt.einheit, gerundet)}';
}

/// Tausenderpunkt, damit vierstellige Zahlen lesbar bleiben. Eine Quelle
/// fuer alle Fortschritts- und Challenge-Anzeigen, siehe badge.dart.
String badgeZahl(int wert) => app.zahlMitTausenderpunkt(wert.toDouble());

/// „Ziel 2.500 km" — das naechste Etappenziel beim Namen genannt.
///
/// 2026-08-26 (vucko, Aufgabe 8, woertlich): „Je nachdem, wie viele Kilometer
/// noch fehlen, sagen wir 120 km bis zur 2000-km-Marke, oder wie viele
/// Gruppenfahrten noch fehlen, sollte genau das als naechstes Etappenziel
/// angezeigt werden." Und praezisierend: „ist fuer das Onboarding gemeint und
/// zukuenftige Challenges, wo das gleiche Format haben werden."
///
/// Vorher stand in derselben Zeile „1007.5 von 2500 km" — die eigene Zahl mit
/// Nachkommastelle, das Ziel ohne Trennung, und daneben schon „noch 1493 km".
/// Zwei Sichten auf dieselbe Sache, keine davon nannte die Marke.
String badgeEtappenziel(app.BadgeFortschritt fortschritt) {
  final ziel = fortschritt.ziel.ceil();
  return 'Ziel ${badgeZahl(ziel)} '
      '${badgeEinheit(fortschritt.einheit, ziel)}';
}

// ---------------------------------------------------------------------------
// Gruppierung — gegen das endlose Scrollen
// ---------------------------------------------------------------------------

/// 2026-08-24 (vucko woertlich): „die stufen badges sollen noch besser
/// angezeigt werden man scrollt da endlos".
///
/// Vorher stand hier EIN Wrap ueber alle siebzehn Familien am Stueck, und der
/// Katalog waechst weiter. Jetzt liegen die Familien in drei Schubladen.
///
/// WARUM NACH ZUSTAND UND NICHT NACH THEMA: Eine Einteilung nach Bereichen
/// („Fahren", „Sozial", …) braucht eine Tabelle Familienschluessel → Bereich.
/// Jede neue Familie, die jemand in `badge.dart` ergaenzt, faellt dann
/// entweder in einen Resterampen-Topf oder verschwindet, bis jemand die
/// Tabelle nachzieht. Der Zustand dagegen ergibt sich aus den Daten selbst:
/// eine neue Familie landet automatisch in „Noch nicht begonnen" und wandert
/// von allein weiter. Ausserdem beantwortet der Zustand genau die drei Fragen,
/// die jemand vor dieser Seite hat:
///   „Was ist als Naechstes dran?" → In Arbeit
///   „Was habe ich schon?"        → Geschafft
///   „Was gibt es ueberhaupt?"    → Noch nicht begonnen
///
/// ES VERSCHWINDET NICHTS: Jede Familie liegt in genau einer Gruppe, jede
/// Gruppe laesst sich aufklappen. Der Test prueft, dass die Vereinigung der
/// Gruppen wieder der volle Katalog ist — auch wenn er waechst.
class BadgeFamilienGruppe {
  const BadgeFamilienGruppe({
    required this.titel,
    required this.erklaerung,
    required this.familien,
  });

  /// „In Arbeit", „Geschafft", „Noch nicht begonnen".
  final String titel;

  /// Eine Zeile darunter, damit die Schublade sich selbst erklaert.
  final String erklaerung;

  final List<app.BadgeFamilie> familien;
}

/// Titel der Schublade, die beim Oeffnen der Seite offen steht.
const String badgeGruppeInArbeit = 'In Arbeit';
const String badgeGruppeGeschafft = 'Geschafft';
const String badgeGruppeOffen = 'Noch nicht begonnen';

/// Ist in dieser Familie wirklich NICHTS mehr offen?
///
/// Bewusst „jedes Abzeichen", nicht „Stufe III erreicht": eine Familie kann
/// neben den drei Stufen Meilensteine tragen (bei „Kilometer" etwa die 1.000).
/// Waere Stufe III das Mass, laege die Familie unter „Geschafft" und tauchte
/// gleichzeitig unten unter „Als Naechstes" wieder als Ziel auf.
bool badgeFamilieFertig(app.BadgeFamilie familie, Set<String> erreichteIds) =>
    familie.alleStufen.every((s) => erreichteIds.contains(s.id));

/// Teilt den Katalog in die drei Schubladen. Leere Schubladen entfallen.
///
/// Innerhalb von „In Arbeit" steht das Naechstliegende oben — dafuer werden,
/// wenn die Kennzahlen schon geladen sind, dieselben Fortschritte benutzt wie
/// im Abschnitt „Als Naechstes". Ohne Kennzahlen bleibt die Katalogreihenfolge.
List<BadgeFamilienGruppe> badgeFamilienGruppen({
  required Set<String> erreichteIds,
  Map<app.BadgeMetrik, double>? metriken,
}) {
  final inArbeit = <app.BadgeFamilie>[];
  final geschafft = <app.BadgeFamilie>[];
  final offen = <app.BadgeFamilie>[];

  for (final familie in app.badgeFamilien) {
    if (badgeFamilieFertig(familie, erreichteIds)) {
      geschafft.add(familie);
    } else if (familie.alleStufen.any((s) => erreichteIds.contains(s.id))) {
      inArbeit.add(familie);
    } else {
      offen.add(familie);
    }
  }

  if (metriken != null) {
    double naehe(app.BadgeFamilie f) =>
        app
            .badgeFamilienFortschritt(
              familie: f.schluessel,
              erreichteBadgeIds: erreichteIds,
              metriken: metriken,
            )
            ?.anteil ??
        0.0;
    final gewicht = {for (final f in inArbeit) f.schluessel: naehe(f)};
    inArbeit.sort(
      (a, b) => gewicht[b.schluessel]!.compareTo(gewicht[a.schluessel]!),
    );
  }

  return [
    if (inArbeit.isNotEmpty)
      BadgeFamilienGruppe(
        titel: badgeGruppeInArbeit,
        erklaerung: 'Angefangen, noch nicht durch',
        familien: inArbeit,
      ),
    if (geschafft.isNotEmpty)
      BadgeFamilienGruppe(
        titel: badgeGruppeGeschafft,
        erklaerung: 'Nichts mehr offen',
        familien: geschafft,
      ),
    if (offen.isNotEmpty)
      BadgeFamilienGruppe(
        titel: badgeGruppeOffen,
        erklaerung: 'Hier ist noch alles zu holen',
        familien: offen,
      ),
  ];
}

/// Kurzer Name fuer die enge Kachel im Raster.
///
/// 2026-08-19 (nach dem Blick auf den Simulator): Bei drei Spalten ist eine
/// Kachel rund 90 Punkte breit. Laengere Woerter brechen dort MITTEN im Wort
/// um, im Simulator stand "Abgeschlosse ne Fahrten" und "Gruppenfahrte n".
/// Die vollen Namen bleiben ueberall sonst erhalten, nur hier wird gekuerzt.
String badgeKurzTitel(String titel) {
  const kurz = <String, String>{
    'Abgeschlossene Fahrten': 'Fahrten',
    'Gruppenfahrten': 'Gruppe fahren',
    'Gegründete Gruppen': 'Gruppe gründen',
    'Gespeicherte Routen': 'Gespeichert',
    'Geteilte Routen': 'Geteilt',
    'Stunden am Steuer': 'Stunden',
    'Nachts unterwegs': 'Nachts',
    'Früh unterwegs': 'Früh',
    'Von A nach B': 'A nach B',
  };
  return kurz[titel] ?? titel;
}

/// Einzahl oder Mehrzahl der Einheit. Unveraenderliche Einheiten (km, Std,
/// Level) stehen bewusst nicht in der Tabelle.
String badgeEinheit(String einheit, int anzahl) {
  if (anzahl != 1) return einheit;
  const einzahl = <String, String>{
    'Fahrten': 'Fahrt',
    'Gruppen': 'Gruppe',
    'Gruppenfahrten': 'Gruppenfahrt',
    'Routen': 'Route',
    'Rundkurse': 'Rundkurs',
    'Stile': 'Stil',
    'Tage': 'Tag',
  };
  return einzahl[einheit] ?? einheit;
}

// ---------------------------------------------------------------------------
// Das Raster — EIN Gesetz fuer die ganze Abzeichen-Seite
// ---------------------------------------------------------------------------

/// 2026-08-25 (vucko woertlich): „das man die badges besser darstellen kann
/// nicht untereinander sondern schon nebeneinander".
///
/// GEMESSEN, warum sie untereinander standen: Der Katalog rechnete seine
/// Kachelbreite aus der AUSSENbreite der Liste (390 Punkte ergaben zwei
/// Kacheln zu 191), gezeichnet wurden die Kacheln aber INNERHALB der
/// Schublade, die nach Rand und Innenabstand nur noch 370 Punkte breit ist.
/// 191 + 8 + 191 = 390 passt nicht in 370 — also brach das `Wrap` nach JEDER
/// Kachel um. Auf dem Telefon stand damit genau eine Kachel je Reihe, obwohl
/// zwei gemeint waren. Gemessen bei 390 Punkten: Kacheln je Reihe
/// [1, 1, 1, 1, 1], voll aufgeklappt 11.532 Punkte.
///
/// Damit das nicht wieder passiert, steht die Rasterregel ab jetzt an EINER
/// Stelle und wird von beiden Rastern der Seite benutzt: von den
/// Familien-Zellen im Uebersichts-Panel und von den Kacheln im Katalog. Wer
/// sie aufruft, uebergibt die WIRKLICH verfuegbare Breite — nicht die des
/// umgebenden Kastens.
///
/// Nebeneffekt und eigentlicher Grund fuer „schoener": beide Raster der Seite
/// haben jetzt dieselbe Spaltenzahl, dieselbe Luecke und damit dieselbe
/// Rasterkante. Vorher hatte das Panel 7 Punkte Luecke und die Schwellen
/// 430/620, der Katalog 8 Punkte und die Schwellen 500/700 — zwei Raster
/// uebereinander, die sich um zwei Spalten unterschieden.
const double badgeRasterLuecke = 8.0;

/// Wie viele Kacheln nebeneinander passen.
///
/// GERECHNET, nicht geschaetzt — mit [badgeRasterLuecke] von 8 Punkten:
///   320 Punkte Geraet -> Katalog 300 nutzbar -> 3 Spalten zu 94,7
///                     -> Panel   276 nutzbar -> 3 Spalten zu 86,7
///   390 Punkte Geraet -> Katalog 370 nutzbar -> 3 Spalten zu 118,0
///   Tablet ab 440     -> 4 Spalten, ab 600 -> 5
///
/// Die Schwelle fuer die dritte Spalte liegt bei 260 und nicht hoeher, weil
/// das schmalste Geraet, das noch bedient wird (320 Punkte), im
/// Uebersichts-Panel nur 276 Punkte nutzbare Breite uebrig laesst. Eine
/// Schwelle von 300 haette dort auf zwei Spalten zurueckgeschaltet — also
/// genau das Gegenteil dessen, was Vucko wollte. Unter 260 Punkten (kein
/// heutiges Geraet) bleiben zwei Spalten, damit eine Kachel nicht unter
/// 80 Punkte faellt.
int badgeRasterSpalten(double verfuegbar) => verfuegbar >= 600
    ? 5
    : verfuegbar >= 440
    ? 4
    : verfuegbar >= 260
    ? 3
    : 2;

/// Die Breite einer Kachel bei [verfuegbar] Punkten nutzbarer Breite.
double badgeRasterKachelBreite(double verfuegbar) {
  final spalten = badgeRasterSpalten(verfuegbar);
  return (verfuegbar - (spalten - 1) * badgeRasterLuecke) / spalten;
}

/// Die Masse EINER Katalog-Kachel, aus ihrer Breite abgeleitet.
///
/// WARUM ABGELEITET UND NICHT FEST: Die Kachel war bisher immer 138 Punkte
/// hoch, egal ob sie 191 oder 95 Punkte breit war. Bei drei Spalten auf einem
/// schmalen Telefon steht darin ein 52 Punkte grosses Emblem in einer 95
/// Punkte breiten Kachel — das Emblem fuellt die Kachel fast randlos und der
/// Name darunter wird zur Restflaeche. Emblem, Innenabstand und Schriftgrad
/// folgen deshalb der Breite. Alle Kacheln der Seite bekommen DIESELBE
/// Breite, also auch dieselbe Hoehe: das Raster bleibt eine saubere Kante.
class BadgeKachelMasse {
  const BadgeKachelMasse({
    required this.breite,
    required this.emblem,
    required this.polster,
    required this.namenGroesse,
    required this.namenHoehe,
    required this.hoehe,
  });

  final double breite;

  /// Kantenlaenge des gezeichneten Stufen-Emblems.
  final double emblem;

  /// Seitlicher Innenabstand.
  final double polster;

  final double namenGroesse;

  /// Feste Hoehe des Namensfeldes (zwei Zeilen), damit die Unterzeilen aller
  /// Kacheln einer Reihe auf derselben Linie liegen.
  final double namenHoehe;

  final double hoehe;
}

/// Randstaerke einer Kachel. Steht hier, weil sie in die Hoehe eingeht: ein
/// `Container` mit `Border` legt den Rand als zusaetzlichen Innenabstand um
/// sein Kind. Wer den vergisst, baut einen Inhalt, der um genau zwei Punkte
/// zu hoch ist — und Flutter meldet einen Ueberlauf.
const double badgeKachelRand = 1.0;

/// Feste Anteile der Kachel, die nicht mit der Breite wachsen: Rand oben und
/// unten, Innenabstand oben (8) und unten (9), Kopfzeile (14), Luft darunter
/// (6), Luft unter dem Emblem (8), Luft ueber der Unterzeile (3) und die
/// Unterzeile selbst (13).
const double _kachelFestAnteil =
    2 * badgeKachelRand + 8 + 14 + 6 + 8 + 3 + 13 + 9;

BadgeKachelMasse badgeKachelMasse(double breite) {
  final emblem = (breite * 0.44).clamp(38.0, 56.0);
  final namenGroesse = breite >= 130
      ? 11.0
      : breite >= 108
      ? 10.5
      : 9.5;
  final namenHoehe = (namenGroesse * 1.12 * 2).ceilToDouble();
  return BadgeKachelMasse(
    breite: breite,
    emblem: emblem,
    polster: breite < 108 ? 6.0 : 10.0,
    namenGroesse: namenGroesse,
    namenHoehe: namenHoehe,
    hoehe: emblem + namenHoehe + _kachelFestAnteil,
  );
}

class BadgeUebersichtPanel extends StatelessWidget {
  const BadgeUebersichtPanel({
    super.key,
    required this.erreichteIds,
    required this.metriken,
    this.onBadgeTippen,
  });

  final Set<String> erreichteIds;

  /// null = die Kennzahlen sind noch nicht geladen. Dann entfaellt der Teil
  /// „Als Naechstes", der Rest steht trotzdem.
  final Map<app.BadgeMetrik, double>? metriken;

  final void Function(app.Badge badge)? onBadgeTippen;

  @override
  Widget build(BuildContext context) {
    final werte = metriken;
    final ziele = werte == null
        ? const <BadgeNaechstesZiel>[]
        : badgeNaechsteZiele(erreichteIds: erreichteIds, metriken: werte);

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14).withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ueberschrift('Die drei Stufen'),
          const SizedBox(height: 9),
          _Legende(erreichteIds: erreichteIds),
          const SizedBox(height: 15),
          _trenner(),
          const SizedBox(height: 13),
          _ueberschrift('Wo du stehst'),
          const SizedBox(height: 9),
          _FamilienSchubladen(
            erreichteIds: erreichteIds,
            metriken: werte,
            onBadgeTippen: onBadgeTippen,
          ),
          if (ziele.isNotEmpty) ...[
            const SizedBox(height: 15),
            _trenner(),
            const SizedBox(height: 13),
            _ueberschrift('Als Nächstes'),
            const SizedBox(height: 9),
            for (var i = 0; i < ziele.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _ZielZeile(ziel: ziele[i], onBadgeTippen: onBadgeTippen),
            ],
          ],
        ],
      ),
    );
  }

  static Widget _ueberschrift(String text) => Text(
    text,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 12.5,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.3,
    ),
  );

  static Widget _trenner() =>
      Container(height: 1, color: Colors.white.withValues(alpha: 0.06));
}

/// Die Skala erklaert sich selbst: Form, Farbe, Symbol und der eigene Stand.
class _Legende extends StatelessWidget {
  const _Legende({required this.erreichteIds});

  final Set<String> erreichteIds;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final stil in badgeStufenSkala) ...[
          if (stil.stufe > 1) const SizedBox(width: 8),
          Expanded(
            child: _LegendenZelle(stil: stil, erreichteIds: erreichteIds),
          ),
        ],
      ],
    );
  }
}

class _LegendenZelle extends StatelessWidget {
  const _LegendenZelle({required this.stil, required this.erreichteIds});

  final BadgeStufenStil stil;
  final Set<String> erreichteIds;

  @override
  Widget build(BuildContext context) {
    final derStufe = app.Badge.all.where((b) => b.stufe == stil.stufe).toList();
    final offen = derStufe.where((b) => erreichteIds.contains(b.id)).length;
    final hatWelche = offen > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: stil.farbe.withValues(alpha: hatWelche ? 0.10 : 0.04),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: stil.farbe.withValues(alpha: hatWelche ? 0.42 : 0.16),
        ),
      ),
      child: Column(
        children: [
          BadgeStufenMarke(
            stufe: stil.stufe,
            freigeschaltet: hatWelche,
            groesse: 22,
          ),
          const SizedBox(height: 7),
          Text(
            stil.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: stil.farbeHell.withValues(alpha: hatWelche ? 1 : 0.55),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$offen von ${derStufe.length}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Die drei Schubladen mit ihren Familien.
///
/// STANDARD: „In Arbeit" ist offen, der Rest zugeklappt. Damit ist die Hoehe
/// dieses Abschnitts an die Zahl der ANGEFANGENEN Familien gebunden, nicht an
/// die Groesse des Katalogs — genau der Punkt, der Vucko gestoert hat. Hat
/// jemand noch nichts angefangen, bleibt alles zu: zwei Kopfzeilen statt
/// siebzehn Kacheln, und der Abschnitt „Als Naechstes" darunter sagt ohnehin
/// schon, wo es losgeht.
///
/// Eigenhaendig auf- oder zugeklappte Schubladen merkt sich [_umgeschaltet].
/// Die Vorgabe wird deshalb bei JEDEM Aufbau neu berechnet und nicht in
/// `initState` eingefroren: die Kennzahlen und die erreichten Abzeichen kommen
/// nachgeladen: waere die Vorgabe eingefroren, stuende beim ersten Aufbau noch
/// „nichts angefangen" und die falsche Schublade waere offen.
class _FamilienSchubladen extends StatefulWidget {
  const _FamilienSchubladen({
    required this.erreichteIds,
    required this.metriken,
    this.onBadgeTippen,
  });

  final Set<String> erreichteIds;
  final Map<app.BadgeMetrik, double>? metriken;
  final void Function(app.Badge badge)? onBadgeTippen;

  @override
  State<_FamilienSchubladen> createState() => _FamilienSchubladenState();
}

class _FamilienSchubladenState extends State<_FamilienSchubladen> {
  final Map<String, bool> _umgeschaltet = {};

  @override
  Widget build(BuildContext context) {
    final gruppen = badgeFamilienGruppen(
      erreichteIds: widget.erreichteIds,
      metriken: widget.metriken,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < gruppen.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _Schublade(
            gruppe: gruppen[i],
            offen:
                _umgeschaltet[gruppen[i].titel] ??
                gruppen[i].titel == badgeGruppeInArbeit,
            aufTippen: () => setState(() {
              final titel = gruppen[i].titel;
              _umgeschaltet[titel] =
                  !(_umgeschaltet[titel] ?? titel == badgeGruppeInArbeit);
            }),
            erreichteIds: widget.erreichteIds,
            onBadgeTippen: widget.onBadgeTippen,
          ),
        ],
      ],
    );
  }
}

/// Eine Schublade: Kopfzeile mit Stand, darunter das Raster ihrer Familien.
class _Schublade extends StatelessWidget {
  const _Schublade({
    required this.gruppe,
    required this.offen,
    required this.aufTippen,
    required this.erreichteIds,
    this.onBadgeTippen,
  });

  final BadgeFamilienGruppe gruppe;
  final bool offen;
  final VoidCallback aufTippen;
  final Set<String> erreichteIds;
  final void Function(app.Badge badge)? onBadgeTippen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: offen ? 0.03 : 0.02),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: aufTippen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          gruppe.titel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          gruppe.erklaerung,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.42),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${gruppe.familien.length}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: offen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 19,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (offen)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 9),
              child: _FamilienRaster(
                familien: gruppe.familien,
                erreichteIds: erreichteIds,
                onBadgeTippen: onBadgeTippen,
              ),
            ),
        ],
      ),
    );
  }
}

/// Die Familien einer Schublade, jede mit ihrem Stufenpfad.
class _FamilienRaster extends StatelessWidget {
  const _FamilienRaster({
    required this.familien,
    required this.erreichteIds,
    this.onBadgeTippen,
  });

  final List<app.BadgeFamilie> familien;
  final Set<String> erreichteIds;
  final void Function(app.Badge badge)? onBadgeTippen;

  @override
  Widget build(BuildContext context) {
    // Dieselbe Rasterregel wie im Katalog darunter — [badgeRasterSpalten].
    // Der LayoutBuilder sitzt INNERHALB des Innenabstands der Schublade, die
    // Breite ist hier also schon die wirklich nutzbare.
    return LayoutBuilder(
      builder: (context, constraints) {
        final breite = badgeRasterKachelBreite(constraints.maxWidth);
        return Wrap(
          spacing: badgeRasterLuecke,
          runSpacing: badgeRasterLuecke,
          children: [
            for (final familie in familien)
              SizedBox(
                width: breite,
                child: _FamilienZelle(
                  familie: familie,
                  erreichteIds: erreichteIds,
                  onBadgeTippen: onBadgeTippen,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FamilienZelle extends StatelessWidget {
  const _FamilienZelle({
    required this.familie,
    required this.erreichteIds,
    this.onBadgeTippen,
  });

  final app.BadgeFamilie familie;
  final Set<String> erreichteIds;
  final void Function(app.Badge badge)? onBadgeTippen;

  @override
  Widget build(BuildContext context) {
    final erreicht = app.Badge.hoechsteErreichteStufe(
      familie.schluessel,
      erreichteIds,
    );
    // Stufenlose Familien (aktuell nur „Fahrstile") haben keinen Pfad. Sie
    // bekommen einen Meilenstein-Punkt, damit die Zelle nicht leer wirkt.
    final gestuft = familie.istGestuft;
    final fertig = gestuft
        ? erreicht >= 3
        : familie.alleStufen.every((s) => erreichteIds.contains(s.id));
    final ziel =
        badgeZielBadge(familie, erreichteIds) ??
        app.Badge.getById(familie.alleStufen.last.id);
    final stilOben = badgeStufenStil(gestuft ? (fertig ? 3 : erreicht) : 0);

    final zelle = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
      decoration: BoxDecoration(
        color: fertig
            ? stilOben.farbe.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: fertig
              ? stilOben.farbe.withValues(alpha: 0.40)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (gestuft)
            BadgeStufenPfadLeiste(erreichteStufen: erreicht, punktGroesse: 13)
          else
            BadgeStufenPunkt(stufe: 0, erreicht: fertig, groesse: 13),
          const SizedBox(height: 6),
          SizedBox(
            height: 26,
            child: Text(
              badgeKurzTitel(familie.titel),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: erreicht > 0 ? 0.9 : 0.5),
                fontSize: 9.5,
                height: 1.12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    if (ziel == null || onBadgeTippen == null) return zelle;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onBadgeTippen!(ziel),
      child: zelle,
    );
  }
}

/// Eine Zeile „Als Naechstes": Stufe, Ziel, Balken, Restweg.
class _ZielZeile extends StatelessWidget {
  const _ZielZeile({required this.ziel, this.onBadgeTippen});

  final BadgeNaechstesZiel ziel;
  final void Function(app.Badge badge)? onBadgeTippen;

  @override
  Widget build(BuildContext context) {
    final stil = badgeStufenStil(ziel.badge.stufe);
    final zeile = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        BadgeStufenMarke(
          stufe: ziel.badge.stufe,
          freigeschaltet: false,
          groesse: 22,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ziel.badge.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    badgeRestweg(ziel.fortschritt),
                    style: TextStyle(
                      color: stil.farbeHell,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: ziel.fortschritt.anteil,
                  minHeight: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.07),
                  color: stil.farbe,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${ziel.familie.titel} · ${badgeEtappenziel(ziel.fortschritt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.42),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (onBadgeTippen == null) return zeile;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onBadgeTippen!(ziel.badge),
      child: zeile,
    );
  }
}
