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
///   2. Wo stehe ich ueberall? -> Ein Raster mit allen siebzehn Familien und
///      ihrem Stufenpfad. Gefuellter Punkt = geschafft, Umriss = offen.
///   3. Was ist als Naechstes dran? -> Die drei Ziele, denen man am naechsten
///      ist, mit Balken und Restweg.
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
app.Badge? badgeZielBadge(
  app.BadgeFamilie familie,
  Set<String> erreichteIds,
) {
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
  return 'noch $gerundet ${badgeEinheit(fortschritt.einheit, gerundet)}';
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
          _FamilienRaster(
            erreichteIds: erreichteIds,
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

/// Alle siebzehn Familien auf einen Blick, jede mit ihrem Stufenpfad.
class _FamilienRaster extends StatelessWidget {
  const _FamilienRaster({required this.erreichteIds, this.onBadgeTippen});

  final Set<String> erreichteIds;
  final void Function(app.Badge badge)? onBadgeTippen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spalten = constraints.maxWidth >= 620
            ? 5
            : constraints.maxWidth >= 430
            ? 4
            : 3;
        const luecke = 7.0;
        final breite =
            (constraints.maxWidth - (spalten - 1) * luecke) / spalten;
        return Wrap(
          spacing: luecke,
          runSpacing: luecke,
          children: [
            for (final familie in app.badgeFamilien)
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
                '${ziel.familie.titel} · ${ziel.fortschritt.zahlen}',
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
