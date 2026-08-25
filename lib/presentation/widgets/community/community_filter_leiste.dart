import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/community_chat_service.dart';

/// 2026-08-24 — Auftrag Vucko, woertlich: „und man soll auch communitys
/// anpinnen koennen und einen filter haben bei oeffentliche communitys wo man
/// einstellen kann auch bei der erstellung obs fuer autofahrer motorradfahrer
/// in welcher region und das man dann beim filter nach region nach auto
/// motorrad oder beides und sonstige sachen die noch sinn machen einstellen
/// kann teste das auch gruendlich".
///
/// Diese Datei haelt die BEDIENUNG des Filters: die Chip-Reihen, das
/// Regionsblatt und den einen Satz, der ein leeres Ergebnis erklaert. Die
/// Wahl selbst liegt in [CommunityFilterEinstellungen], gefiltert wird
/// serverseitig in `get_communities_gefiltert`.
///
/// WARUM CHIP-REIHEN UND KEIN AUSKLAPPMENUE: Es gibt genau zwei Vorbilder im
/// Haus, und beide sind Chip-Reihen — `_buildLeaderboardPeriodPicker` und
/// `_buildFahrzeugFilterPicker` in `analytics_page.dart`. Drei Zustaende, alle
/// drei gleichzeitig sichtbar, ein Fingertipp dazwischen. Ein Ausklappmenue
/// braucht zwei Tipps und verbirgt, welche Wahl es ueberhaupt gibt.
///
/// WARUM DIE REGION TROTZDEM EIN BLATT IST: es sind 54 Eintraege (9
/// Bundeslaender, 26 Kantone, 16 Bundeslaender, dazu drei Mal „ganzes Land").
/// Eine Chip-Reihe daraus waere eine Tapete. Das Blatt ist derselbe Griff wie
/// die Vorschau in `community_vorschau_blatt.dart`.
///
/// EHRLICHKEIT ZUR WIRKUNG, gemessen am 24.08.2026: es gibt SECHS Communities
/// und drei Laender. Der Filter wird auf absehbare Zeit fast nichts
/// wegfiltern — und wenn doch, dann gleich alles. Genau dafuer gibt es
/// [communityFilterLeerText] und den Knopf „Alles anzeigen": ein leerer
/// Bildschirm ohne Erklaerung waere hier der wahrscheinlichste Ausgang.

/// 2026-08-25 — Auftrag Vucko, woertlich: „es soll automatisch erkannt werden
/// in welchem land man ist und man soll aus dem Land nur die regionen haben
/// also wenn ich in deutschland bin will ich keine regionen von oesterreich
/// haben usw. es solls automatisch am standort erkennen bitte auf das acht
/// geben".
///
/// Das Blatt zeigt seither nur noch die Regionen des erkannten Landes. Die
/// Erkennung selbst liegt in [CommunityStandortLand]; hier steht nur, was man
/// davon SIEHT — die Zeile „Nach deinem Standort: Österreich" und der Knopf,
/// der die anderen Länder wieder hereinholt.
///
/// WARUM DIE ANDEREN LAENDER EINEN KNOPF BEKOMMEN UND NICHT VERSCHWINDEN:
/// Zwei Faelle, die es wirklich gibt. Der Vorarlberger im Urlaub in Italien
/// bekommt vom Standort weder AT noch DE noch CH — er faellt aufs Profil
/// zurueck, und wenn auch das leer ist, muss er trotzdem waehlen koennen. Und
/// wer in Lustenau wohnt, schaut sehr wohl nach St. Gallen. Ein hartes
/// Wegschneiden waere fuer beide eine Sackgasse.

/// Der Satz, der ein leeres Ergebnis erklaert — oder `null`, wenn gar nichts
/// weggefiltert wurde und die Liste wirklich leer ist.
///
/// Bewusst eine freie Funktion und kein Widget: das ist die Entscheidung, die
/// leicht falsch herum ist („Keine Treffer" obwohl kein Filter gesetzt war),
/// und so ist sie im Test ohne Oberflaeche fahrbar.
///
/// Die SORTIERUNG taucht hier absichtlich nicht auf: sie ordnet um, sie
/// blendet nichts aus. Ein leeres Ergebnis kann sie nie erklaeren.
String? communityFilterLeerText({
  required bool filtertEtwasWeg,
  required bool sucheAktiv,
}) {
  if (filtertEtwasWeg && sucheAktiv) {
    return 'Keine Community passt zu diesem Filter und deiner Suche.';
  }
  if (filtertEtwasWeg) {
    return 'Keine Community passt zu diesem Filter.';
  }
  if (sucheAktiv) {
    return 'Keine Community passt zu deiner Suche.';
  }
  return null;
}

/// Was das Regionsblatt zurueckgibt.
///
/// Eine eigene Huelle, weil `null` sonst zwei Dinge hiesse: „abgebrochen" und
/// „alle Regionen". Das ist genau der Unterschied zwischen „Filter bleibt wie
/// er war" und „Filter geht auf".
class CommunityRegionWahl {
  const CommunityRegionWahl(this.code);

  /// `null` = alle Regionen.
  final String? code;
}

/// Die Filterleiste ueber „Öffentliche Communities".
class CommunityFilterLeiste extends StatelessWidget {
  const CommunityFilterLeiste({
    super.key,
    required this.einstellungen,
    required this.regionen,
    this.landCode,
    this.landQuelle = CommunityLandQuelle.unbekannt,
    required this.onFahrzeugart,
    required this.onRegion,
    required this.onSortierung,
    required this.onZuruecksetzen,
  });

  final CommunityFilterEinstellungen einstellungen;
  final List<CommunityRegion> regionen;

  /// Das erkannte Land (`AT`/`CH`/`DE`) oder `null` = alle Regionen zeigen.
  final String? landCode;

  /// Woher [landCode] stammt — steht als eine Zeile im Blatt.
  final CommunityLandQuelle landQuelle;

  final ValueChanged<CommunityFahrzeugart> onFahrzeugart;
  final ValueChanged<String?> onRegion;
  final ValueChanged<CommunitySortierung> onSortierung;
  final VoidCallback onZuruecksetzen;

  String get _regionText {
    final code = einstellungen.regionCode;
    if (code == null || code.isEmpty) return 'Alle Regionen';
    for (final region in regionen) {
      if (region.code == code) return region.name;
    }
    // Die Liste ist noch nicht da (erster Start ohne Netz) — dann steht der
    // Code da statt eines leeren Knopfes. Besser eine kryptische Angabe als
    // die Behauptung, es sei kein Filter gesetzt.
    return code;
  }

  @override
  Widget build(BuildContext context) {
    final regionGesetzt =
        einstellungen.regionCode != null &&
        einstellungen.regionCode!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommunityFahrzeugartChips(
          gewaehlt: einstellungen.fahrzeugart,
          onWahl: onFahrzeugart,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _RegionKnopf(
                text: _regionText,
                gesetzt: regionGesetzt,
                onTap: () async {
                  final wahl = await CommunityRegionBlatt.zeigen(
                    context,
                    regionen: regionen,
                    aktuell: einstellungen.regionCode,
                    landCode: landCode,
                    landQuelle: landQuelle,
                  );
                  if (wahl != null) onRegion(wahl.code);
                },
              ),
            ),
            if (einstellungen.filtertEtwasWeg) ...[
              const SizedBox(width: 8),
              _ZuruecksetzenKnopf(onTap: onZuruecksetzen),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final art in CommunitySortierung.values) ...[
              if (art != CommunitySortierung.values.first)
                const SizedBox(width: 8),
              Expanded(
                child: _FilterChip(
                  beschriftung: art.beschriftung,
                  gewaehlt: einstellungen.sortierung == art,
                  onTap: () => onSortierung(art),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Die Chip-Reihe fuer die Fahrzeugart.
///
/// Steht an ZWEI Stellen: im Filter („wonach suche ich") und im Blatt
/// „Community erstellen" („fuer wen ist sie"). Deshalb ein eigenes Widget und
/// keine private Methode — sonst driften die beiden Reihen auseinander, so
/// wie es beim Markenfeld passiert ist.
///
/// [alleBeschriftung] ist der einzige Unterschied: im Filter heisst der dritte
/// Zustand „Alle" (= egal), beim Erstellen „Für alle" (= offen fuer beide).
class CommunityFahrzeugartChips extends StatelessWidget {
  const CommunityFahrzeugartChips({
    super.key,
    required this.gewaehlt,
    required this.onWahl,
    this.alleBeschriftung,
  });

  final CommunityFahrzeugart gewaehlt;
  final ValueChanged<CommunityFahrzeugart> onWahl;
  final String? alleBeschriftung;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final art in CommunityFahrzeugart.values) ...[
          if (art != CommunityFahrzeugart.values.first)
            const SizedBox(width: 8),
          Expanded(
            child: _FilterChip(
              beschriftung: art == CommunityFahrzeugart.alle
                  ? (alleBeschriftung ?? art.beschriftung)
                  : art.beschriftung,
              icon: switch (art) {
                CommunityFahrzeugart.auto => Icons.directions_car_filled,
                CommunityFahrzeugart.motorrad => Icons.two_wheeler,
                CommunityFahrzeugart.alle => Icons.groups_outlined,
              },
              gewaehlt: gewaehlt == art,
              onTap: () => onWahl(art),
            ),
          ),
        ],
      ],
    );
  }
}

/// Das Auswahlblatt fuer die Region.
class CommunityRegionBlatt extends StatelessWidget {
  const CommunityRegionBlatt({
    super.key,
    required this.regionen,
    required this.aktuell,
    required this.titel,
    this.landCode,
    this.landQuelle = CommunityLandQuelle.unbekannt,
  });

  final List<CommunityRegion> regionen;
  final String? aktuell;
  final String titel;

  /// Das erkannte Land. `null` = alle Regionen zeigen.
  final String? landCode;
  final CommunityLandQuelle landQuelle;

  /// Oeffnet das Blatt. `null` = abgebrochen, sonst die Wahl (deren `code`
  /// wiederum `null` sein darf: „alle Regionen").
  static Future<CommunityRegionWahl?> zeigen(
    BuildContext context, {
    required List<CommunityRegion> regionen,
    required String? aktuell,
    String titel = 'Region',
    String alleBeschriftung = 'Alle Regionen',
    String? landCode,
    CommunityLandQuelle landQuelle = CommunityLandQuelle.unbekannt,
  }) {
    return showModalBottomSheet<CommunityRegionWahl>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _RegionBlattInhalt(
        regionen: regionen,
        aktuell: aktuell,
        titel: titel,
        alleBeschriftung: alleBeschriftung,
        landCode: landCode,
        landQuelle: landQuelle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _RegionBlattInhalt(
      regionen: regionen,
      aktuell: aktuell,
      titel: titel,
      alleBeschriftung: 'Alle Regionen',
      landCode: landCode,
      landQuelle: landQuelle,
    );
  }
}

class _RegionBlattInhalt extends StatefulWidget {
  const _RegionBlattInhalt({
    required this.regionen,
    required this.aktuell,
    required this.titel,
    required this.alleBeschriftung,
    required this.landCode,
    required this.landQuelle,
  });

  final List<CommunityRegion> regionen;
  final String? aktuell;
  final String titel;
  final String alleBeschriftung;
  final String? landCode;
  final CommunityLandQuelle landQuelle;

  @override
  State<_RegionBlattInhalt> createState() => _RegionBlattInhaltState();
}

class _RegionBlattInhaltState extends State<_RegionBlattInhalt> {
  static const Map<String, String> _landNamen = {
    'AT': 'Österreich',
    'CH': 'Schweiz',
    'DE': 'Deutschland',
  };

  /// `true` = alle Laender, nicht nur das erkannte.
  ///
  /// Der Zustand lebt nur solange das Blatt offen ist. Er wird BEWUSST nicht
  /// gemerkt: die naechste Wahl trifft der Nutzer wahrscheinlich wieder dort,
  /// wo er ist. Wer dauerhaft alles will, setzt die Region einfach auf „alle".
  late bool _alleLaender;

  @override
  void initState() {
    super.initState();
    // Aufgeklappt starten, wenn es nichts zu beschneiden gibt — oder wenn die
    // bereits gewaehlte Region zu einem anderen Land gehoert. Eine gesetzte
    // Wahl, die man im Blatt nicht sieht, waere ein Filter ohne Griff.
    _alleLaender =
        widget.landCode == null ||
        CommunityStandortLand.istFremdeRegion(
          regionCode: widget.aktuell,
          landCode: widget.landCode,
          regionen: widget.regionen,
        );
  }

  @override
  Widget build(BuildContext context) {
    // Die sichtbare Liste. [CommunityStandortLand.regionenFuerLand] gibt von
    // sich aus ALLES zurueck, wenn zum Land nichts passt — eine leere Auswahl
    // waere die schlechteste aller Anzeigen.
    final gefiltert = CommunityStandortLand.regionenFuerLand(
      widget.regionen,
      widget.landCode,
    );
    final beschneidetWirklich = gefiltert.length < widget.regionen.length;
    final sichtbar = (_alleLaender || !beschneidetWirklich)
        ? widget.regionen
        : gefiltert;
    final herkunft = beschneidetWirklich
        ? CommunityStandortLand.herkunftText(widget.landCode, widget.landQuelle)
        : null;

    // Nach Land gruppiert, in der Reihenfolge, in der die Datenbank sortiert:
    // „ganzes Land" zuerst (sortierung 0), dann alphabetisch.
    final nachLand = <String, List<CommunityRegion>>{};
    for (final region in sichtbar) {
      nachLand
          .putIfAbsent(region.landCode, () => <CommunityRegion>[])
          .add(region);
    }
    final laender = nachLand.keys.toList()..sort();

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                16,
                18,
                herkunft == null ? 10 : 4,
              ),
              child: Text(
                widget.titel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (herkunft != null && !_alleLaender)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.my_location,
                      size: 13,
                      color: Color(0xFFA0AEC0),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        herkunft,
                        style: const TextStyle(
                          color: Color(0xFFA0AEC0),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                children: [
                  _eintrag(
                    context,
                    text: widget.alleBeschriftung,
                    gewaehlt: widget.aktuell == null || widget.aktuell!.isEmpty,
                    wahl: const CommunityRegionWahl(null),
                  ),
                  if (widget.regionen.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 18, 12, 0),
                      child: Text(
                        'Die Regionsliste ist gerade nicht erreichbar. '
                        'Zieh die Liste herunter, sobald du wieder Netz hast.',
                        style: TextStyle(color: Colors.grey, fontSize: 12.5),
                      ),
                    ),
                  for (final land in laender) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
                      child: Text(
                        _landNamen[land] ?? land,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    for (final region in nachLand[land]!)
                      _eintrag(
                        context,
                        text: region.name,
                        gewaehlt: widget.aktuell == region.code,
                        wahl: CommunityRegionWahl(region.code),
                      ),
                  ],
                  if (beschneidetWirklich) _landUmschalter(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Der Weg zu den anderen Laendern — und zurueck.
  ///
  /// Steht UNTEN, nicht oben: oben stuende er zwischen dem Nutzer und dem, was
  /// er in neun von zehn Faellen sucht. Unten findet ihn genau der, der weiter
  /// gescrollt hat, weil seine Region nicht dabei war.
  Widget _landUmschalter() {
    final landName = CommunityStandortLand.landName(widget.landCode);
    final text = _alleLaender
        ? 'Nur $landName zeigen'
        : 'Regionen aus allen Ländern zeigen';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _alleLaender = !_alleLaender),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              children: [
                Icon(
                  _alleLaender ? Icons.filter_alt_outlined : Icons.public,
                  size: 16,
                  color: AppAccentColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _eintrag(
    BuildContext context, {
    required String text,
    required bool gewaehlt,
    required CommunityRegionWahl wahl,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).pop(wahl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: gewaehlt ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: gewaehlt ? FontWeight.w900 : FontWeight.w500,
                  ),
                ),
              ),
              if (gewaehlt)
                Icon(Icons.check, color: AppAccentColors.accent, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegionKnopf extends StatelessWidget {
  const _RegionKnopf({
    required this.text,
    required this.gesetzt,
    required this.onTap,
  });

  final String text;
  final bool gesetzt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: gesetzt
              ? AppAccentColors.accent.withValues(alpha: 0.18)
              : const Color(0xFF0B0E14).withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: gesetzt
                ? AppAccentColors.accent.withValues(alpha: 0.50)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.place_outlined,
              size: 15,
              color: gesetzt ? Colors.white : const Color(0xFFA0AEC0),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: gesetzt ? Colors.white : const Color(0xFFA0AEC0),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Icon(
              Icons.expand_more,
              size: 16,
              color: gesetzt ? Colors.white : const Color(0xFFA0AEC0),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZuruecksetzenKnopf extends StatelessWidget {
  const _ZuruecksetzenKnopf({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0E14).withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_alt_off_outlined, size: 15, color: Colors.white70),
            SizedBox(width: 6),
            Text(
              'Alles anzeigen',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ein Chip, gebaut wie `_buildLeaderboardPeriodChip` in `analytics_page.dart`
/// — dieselbe Hoehe, dieselbe Rundung, dieselben zwei Farben.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.beschriftung,
    required this.gewaehlt,
    required this.onTap,
    this.icon,
  });

  final String beschriftung;
  final bool gewaehlt;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        height: 40,
        decoration: BoxDecoration(
          color: gewaehlt
              ? AppAccentColors.accent.withValues(alpha: 0.18)
              : const Color(0xFF0B0E14).withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: gewaehlt
                ? AppAccentColors.accent.withValues(alpha: 0.50)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: gewaehlt ? Colors.white : const Color(0xFFA0AEC0),
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                beschriftung,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: gewaehlt ? Colors.white : const Color(0xFFA0AEC0),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
