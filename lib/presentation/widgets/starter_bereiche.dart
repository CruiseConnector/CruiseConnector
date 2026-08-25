import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Die Bausteine der Starter-Karte: Bereiche, Schubladen, Aufgabenkacheln und
/// der Belohnungsblock.
///
/// 2026-08-25 (vucko wörtlich): „mache es so das die leute es zuklappen
/// koennen und das ganze besser gegliedert ist unter fahren unter community
/// usw. und das auch noch ausklappen koennen sonnst ist es zu unuebersichtlich
/// das man auch sieht was man als belohnung bekommt unten [...] und auch noch
/// soll beim ausklappen eine coole kleine animation sein beim ersten mal [...]
/// und es soll besser eingerahmt sein pro aufgabe".
///
/// GEMESSEN, warum die flache Liste unübersichtlich war (Widget-Test bei 320
/// Punkten Breite, frisches Konto, 0 von 12 erledigt):
///
///   Karte gesamt                                   2165 pt
///   davon die zwölf Aufgabenzeilen                 1870 pt  (86 %)
///   die kürzeste Zeile („route")                    120 pt
///   die längste Zeile („hashtag")                   191 pt
///   der Erklärabsatz unter dem Balken               112 pt
///
/// Eine Zeile war also im Schnitt 156 Punkte hoch — für zwei kurze Sätze. Der
/// Grund: neben Symbol (30 pt) und „Zeigen"-Pille (64 pt) blieben dem Text
/// keine 220 Punkte, also brachen Titel UND Beschreibung auf drei bis fünf
/// Zeilen um. Zwölfmal hintereinander ergibt das drei Bildschirmlängen ohne
/// jede Struktur.
///
/// DREI HEBEL, in dieser Reihenfolge:
///   1. Nur EIN Bereich ist offen. Damit hängt die Höhe an der Größe eines
///      Bereichs (höchstens fünf Aufgaben), nicht mehr an der Liste.
///   2. Die Beschreibung steht nur beim NÄCHSTEN Schritt eines Bereichs. Die
///      übrigen offenen Aufgaben sind einzeilige Kacheln, erledigte sind
///      Haken-Zeilen ohne Rahmen.
///   3. Der Erklärabsatz ist weg. Was er sagte, steht jetzt als Belohnung
///      unten — konkret statt beschreibend.

/// Ein Bereich der Starter-Karte.
///
/// WARUM DIESE DREI: Vucko nennt „unter fahren unter community usw.". Die
/// zwölf Aufgaben zerfallen tatsächlich in genau drei Fragen, die ein Fahrer
/// unterscheidet:
///
///   Fahren       — alles, was mit einer Strecke zu tun hat: suchen, merken,
///                  speichern, fahren, Kilometer sammeln.
///   Community    — alles, wobei andere Leute zuschauen oder mitmachen.
///   Dein Profil  — alles, was nur dich betrifft: die Tour, dein Auto, deine
///                  Sammlung.
///
/// Die Reihenfolge ist keine Geschmacksfrage: Sie folgt dem, was die App IST.
/// Wer sie öffnet, will fahren. „Dein Profil" steht hinten, weil dort die
/// Aufgabe „Tutorial abschließen" liegt, die praktisch jeder schon vor der
/// ersten Anzeige dieser Karte erledigt hat — ein Bereich, der beim Öffnen
/// meistens komplett abgehakt ist, gehört nicht nach vorn.
class StarterBereich {
  const StarterBereich({
    required this.id,
    required this.titel,
    required this.untertitel,
    required this.symbol,
    required this.aufgabenIds,
  });

  final String id;
  final String titel;

  /// Eine Zeile darunter, damit die Schublade sich selbst erklärt — dasselbe
  /// Muster wie die Schubladen in `badge_uebersicht_panel.dart`.
  final String untertitel;
  final IconData symbol;
  final List<String> aufgabenIds;
}

const List<StarterBereich> starterBereiche = [
  StarterBereich(
    id: 'fahren',
    titel: 'Fahren',
    untertitel: 'Suchen, merken, losfahren',
    symbol: Icons.route_rounded,
    aufgabenIds: ['route', 'favorit', 'speichern', 'runde', 'km50'],
  ),
  StarterBereich(
    id: 'community',
    titel: 'Community',
    untertitel: 'Posts, Hashtags, Gruppen',
    symbol: Icons.groups_rounded,
    aufgabenIds: ['community', 'post', 'hashtag', 'gruppenfahrt'],
  ),
  StarterBereich(
    id: 'profil',
    titel: 'Dein Profil',
    untertitel: 'Tour, Garage, Abzeichen',
    symbol: Icons.account_circle_rounded,
    aufgabenIds: ['tutorial', 'garage', 'abzeichen'],
  ),
];

/// Ein Bereich mit den Aufgaben, die wirklich dazugehören.
class StarterBereichInhalt {
  const StarterBereichInhalt(this.bereich, this.aufgaben);

  final StarterBereich bereich;
  final List<StarterAufgabe> aufgaben;
}

/// Der Auffangbereich für Aufgaben, die kein Bereich kennt.
const StarterBereich starterBereichWeiteres = StarterBereich(
  id: 'weiteres',
  titel: 'Weiteres',
  untertitel: 'Was sonst noch offen ist',
  symbol: Icons.more_horiz_rounded,
  aufgabenIds: [],
);

/// Verteilt [StarterAufgabenService.aufgaben] auf die Bereiche.
///
/// DIE ZUORDNUNG DARF NICHTS VERSCHLUCKEN. `starter_aufgaben_service.dart`
/// gehört einer anderen Hand: wer dort eine dreizehnte Aufgabe einträgt, würde
/// sie sonst nie zu sehen bekommen, und die Karte verspräche eine Belohnung
/// für eine unsichtbare Bedingung. Alles, was in keiner Liste steht, landet
/// deshalb sichtbar in [starterBereichWeiteres]. Der Test
/// `starter_bereiche_test.dart` schlägt zusätzlich fehl, sobald das passiert.
List<StarterBereichInhalt> starterBereicheMitAufgaben() {
  final nachId = {
    for (final a in StarterAufgabenService.aufgaben) a.id: a,
  };
  final vergeben = <String>{};
  final ergebnis = <StarterBereichInhalt>[];

  for (final bereich in starterBereiche) {
    final aufgaben = <StarterAufgabe>[];
    for (final id in bereich.aufgabenIds) {
      final aufgabe = nachId[id];
      if (aufgabe == null) continue; // Aufgabe wurde entfernt: still weglassen.
      aufgaben.add(aufgabe);
      vergeben.add(id);
    }
    if (aufgaben.isNotEmpty) ergebnis.add(StarterBereichInhalt(bereich, aufgaben));
  }

  final rest = StarterAufgabenService.aufgaben
      .where((a) => !vergeben.contains(a.id))
      .toList();
  if (rest.isNotEmpty) {
    ergebnis.add(StarterBereichInhalt(starterBereichWeiteres, rest));
  }
  return ergebnis;
}

/// Was die Karte sich über Öffnungen merken muss.
///
/// ZWEI DINGE, beide dauerhaft:
///   * ob der Nutzer die ganze Karte zugeklappt hat — sonst müsste er das nach
///     jedem App-Start erneut tun, und „zuklappen können" wäre eine Geste
///     ohne Wirkung;
///   * welche Bereiche ihre Einblende-Animation schon hatten. „Beim ersten
///     Mal" heißt beim ersten Mal, nicht bei jedem Aufbau der Startseite.
///
/// JE BEREICH, NICHT JE KARTE. Der erste Bereich steht beim Öffnen der App
/// schon offen — läge das Gedächtnis auf der Karte, wäre die Animation genau
/// dort verbraucht, wo niemand etwas aufgeklappt hat, und die beiden anderen
/// Bereiche bekämen sie nie. So gehört sie zum Moment, in dem ein Bereich
/// zum ersten Mal seinen Inhalt zeigt.
class StarterKartenGedaechtnis {
  StarterKartenGedaechtnis._();

  static const kZugeklappt = 'starter_karte_zugeklappt_v1';
  static const kAnimiert = 'starter_bereiche_animiert_v1';

  static bool _geladen = false;
  static bool zugeklappt = false;
  static Set<String> animierteBereiche = <String>{};

  static bool get geladen => _geladen;

  static Future<void> laden() async {
    if (_geladen) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      zugeklappt = prefs.getBool(kZugeklappt) ?? false;
      animierteBereiche = (prefs.getStringList(kAnimiert) ?? const <String>[])
          .toSet();
    } catch (_) {
      // Ohne Gerätespeicher bleibt die Karte offen und animiert einmal.
    }
    _geladen = true;
  }

  static Future<void> setzeZugeklappt(bool wert) async {
    zugeklappt = wert;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kZugeklappt, wert);
    } catch (_) {
      // Der Zustand gilt dann nur für diese Sitzung.
    }
  }

  static Future<void> merkeAnimiert(String bereichId) async {
    if (!animierteBereiche.add(bereichId)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(kAnimiert, animierteBereiche.toList()..sort());
    } catch (_) {
      // Dann läuft sie beim nächsten Start noch einmal. Kein Schaden.
    }
  }

  static void resetForTests() {
    _geladen = false;
    zugeklappt = false;
    animierteBereiche = <String>{};
  }
}

/// Eine Schublade: Kopfzeile mit Stand, darunter die Aufgaben.
///
/// Die Bedienung ist zeichengleich mit `badge_uebersicht_panel.dart` und der
/// Abzeichen-Liste in `analytics_page.dart`: die ganze Kopfzeile ist die
/// Schaltfläche, rechts steht der Stand als Pille, daneben dreht sich ein
/// `AnimatedRotation`-Pfeil. Dieselbe Geste an drei Stellen ist mehr wert als
/// drei eigene Ideen.
class StarterBereichSchublade extends StatelessWidget {
  const StarterBereichSchublade({
    super.key,
    required this.inhalt,
    required this.accent,
    required this.offen,
    required this.erledigt,
    required this.aufTippen,
    required this.aufZeigen,
    required this.animieren,
    required this.aufAnimationGelaufen,
  });

  final StarterBereichInhalt inhalt;
  final Color accent;
  final bool offen;

  /// Ob eine Aufgabe erledigt ist. Kommt aus dem Dienst, nicht aus dem Widget.
  final bool Function(String aufgabeId) erledigt;

  final VoidCallback aufTippen;
  final void Function(StarterAufgabe aufgabe) aufZeigen;

  /// Erstes Öffnen: die Kacheln kommen gestaffelt herein.
  final bool animieren;
  final VoidCallback aufAnimationGelaufen;

  int get _erledigteAnzahl =>
      inhalt.aufgaben.where((a) => erledigt(a.id)).length;

  bool get _fertig => _erledigteAnzahl == inhalt.aufgaben.length;

  @override
  Widget build(BuildContext context) {
    final gesamt = inhalt.aufgaben.length;
    final fertig = _fertig;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: offen ? 0.045 : 0.025),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: offen
              ? accent.withValues(alpha: 0.30)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: offen,
            label:
                '${inhalt.bereich.titel}, $_erledigteAnzahl von $gesamt '
                'erledigt',
            child: InkWell(
              key: ValueKey('starter_bereich_${inhalt.bereich.id}'),
              onTap: aufTippen,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: fertig
                            ? accent.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        fertig ? Icons.check_rounded : inhalt.bereich.symbol,
                        size: 16,
                        color: fertig
                            ? accent
                            : Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            inhalt.bereich.titel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            inhalt.bereich.untertitel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.42),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    _StandPille(
                      erledigt: _erledigteAnzahl,
                      gesamt: gesamt,
                      accent: accent,
                      fertig: fertig,
                    ),
                    const SizedBox(width: 2),
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
          ),
          if (offen)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 9),
              child: _AufgabenStapel(
                key: ValueKey('starter_stapel_${inhalt.bereich.id}'),
                aufgaben: inhalt.aufgaben,
                accent: accent,
                erledigt: erledigt,
                aufZeigen: aufZeigen,
                animieren: animieren,
                aufAnimationGelaufen: aufAnimationGelaufen,
              ),
            ),
        ],
      ),
    );
  }
}

/// „2/5" als Pille. Erledigte Bereiche tragen den Akzent.
class _StandPille extends StatelessWidget {
  const _StandPille({
    required this.erledigt,
    required this.gesamt,
    required this.accent,
    required this.fertig,
  });

  final int erledigt;
  final int gesamt;
  final Color accent;
  final bool fertig;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: fertig
            ? accent.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '$erledigt/$gesamt',
        style: TextStyle(
          color: fertig ? accent : Colors.white.withValues(alpha: 0.72),
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// Die Aufgaben eines offenen Bereichs, beim ersten Mal gestaffelt.
///
/// DIE ANIMATION IST BEWUSST KLEIN. Vucko sagt „coole kleine animation" — das
/// Stichwort ist klein. Jede Kachel kommt 10 Punkte von unten herein und blendet
/// auf, mit 55 ms Versatz. Bei fünf Aufgaben ist alles nach 500 ms fertig; wer
/// tippt und sofort weiterlesen will, wird nicht aufgehalten, denn die Kacheln
/// sind vom ersten Moment an da und antippbar.
///
/// „Bewegung reduzieren" (iOS Bedienungshilfen, Android Animationen aus) hebt
/// sie ersatzlos auf — dasselbe Vorgehen wie in `xp_rechnung_animation.dart`:
/// der Regler springt auf den Endwert, der Inhalt bleibt derselbe.
class _AufgabenStapel extends StatefulWidget {
  const _AufgabenStapel({
    super.key,
    required this.aufgaben,
    required this.accent,
    required this.erledigt,
    required this.aufZeigen,
    required this.animieren,
    required this.aufAnimationGelaufen,
  });

  final List<StarterAufgabe> aufgaben;
  final Color accent;
  final bool Function(String aufgabeId) erledigt;
  final void Function(StarterAufgabe aufgabe) aufZeigen;
  final bool animieren;
  final VoidCallback aufAnimationGelaufen;

  @override
  State<_AufgabenStapel> createState() => _AufgabenStapelState();
}

class _AufgabenStapelState extends State<_AufgabenStapel>
    with SingleTickerProviderStateMixin {
  /// Startwert 1, also FERTIG.
  ///
  /// Das ist kein Detail: Der Vermerk „schon animiert" liegt im
  /// Geraetespeicher und ist beim ersten Bild noch nicht da. Stuende der
  /// Regler auf 0 und die Animation liefe nicht los, weil noch niemand weiss,
  /// ob sie darf, waeren die Kacheln unsichtbar. So sind sie immer sichtbar,
  /// und die Animation setzt den Regler notfalls zurueck auf 0.
  late final AnimationController _regler = AnimationController(
    vsync: this,
    value: 1,
    duration: Duration(milliseconds: 260 + 55 * widget.aufgaben.length),
  );
  bool _gelaufen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pruefeStart();
  }

  @override
  void didUpdateWidget(_AufgabenStapel alt) {
    super.didUpdateWidget(alt);
    // WICHTIG: Beim ersten Aufbau steht [widget.animieren] auf false, weil das
    // Gedaechtnis noch geladen wird. Es kippt eine Bildfolge spaeter auf true.
    // Ohne diesen Haken liefe die Animation auf einem frischen Geraet NIE —
    // ausgerechnet dort, wo sie hingehoert.
    _pruefeStart();
  }

  void _pruefeStart() {
    if (_gelaufen || !widget.animieren) return;
    // „Bewegung reduzieren" (iOS Bedienungshilfen, Android Animationen aus):
    // ersatzlos, und OHNE Vermerk. Wer die Einstellung spaeter abschaltet,
    // bekommt sie dann. Dasselbe Vorgehen wie in xp_rechnung_animation.dart.
    if (MediaQuery.disableAnimationsOf(context)) return;
    _gelaufen = true;
    // Erst merken, dann laufen lassen: so laeuft sie auch dann nur einmal,
    // wenn die Karte zwischendurch neu aufgebaut wird.
    widget.aufAnimationGelaufen();
    _regler.forward(from: 0);
  }

  @override
  void dispose() {
    _regler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Der nächste Schritt ist die erste offene Aufgabe des Bereichs. Nur sie
    // trägt ihre Beschreibung — siehe Kopf dieser Datei, Hebel 2.
    final naechste = widget.aufgaben
        .cast<StarterAufgabe?>()
        .firstWhere((a) => !widget.erledigt(a!.id), orElse: () => null);

    return AnimatedBuilder(
      animation: _regler,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < widget.aufgaben.length; i++) ...[
              if (i > 0) const SizedBox(height: 5),
              _gestaffelt(
                i,
                StarterAufgabenKachel(
                  aufgabe: widget.aufgaben[i],
                  accent: widget.accent,
                  erledigt: widget.erledigt(widget.aufgaben[i].id),
                  naechsterSchritt: identical(widget.aufgaben[i], naechste),
                  aufZeigen: () => widget.aufZeigen(widget.aufgaben[i]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _gestaffelt(int index, Widget kind) {
    if (_regler.value >= 1) return kind;
    final start = (index * 55) / _regler.duration!.inMilliseconds;
    final anteil = Curves.easeOutCubic.transform(
      ((_regler.value - start) / (1 - start)).clamp(0.0, 1.0),
    );
    return Opacity(
      opacity: anteil,
      child: Transform.translate(
        offset: Offset(0, 10 * (1 - anteil)),
        child: kind,
      ),
    );
  }
}

/// Eine Aufgabe als eigene Einheit.
///
/// „es soll besser eingerahmt sein pro aufgabe" — mit der Einschränkung aus
/// dem Auftrag, dass zwölf Rahmen nicht wie ein Gitter wirken dürfen. Deshalb
/// bekommt NICHT jede Aufgabe denselben Rahmen. Es gibt drei Stufen, und sie
/// tragen eine Information:
///
///   * der nächste Schritt  — Rahmen im Akzent, Beschreibung, „Zeigen"-Knopf;
///   * offen, aber später   — ruhiger Rahmen, nur der Titel, Pfeil rechts;
///   * erledigt             — kein Rahmen, Haken und durchgestrichener Titel.
///
/// Damit schrumpft die Zahl der Rahmen mit dem Fortschritt, statt zu bleiben.
/// Und der Blick landet dort, wo er hin soll: auf der einen Sache, die als
/// Nächstes dran ist.
class StarterAufgabenKachel extends StatelessWidget {
  const StarterAufgabenKachel({
    super.key,
    required this.aufgabe,
    required this.accent,
    required this.erledigt,
    required this.naechsterSchritt,
    required this.aufZeigen,
  });

  final StarterAufgabe aufgabe;
  final Color accent;
  final bool erledigt;
  final bool naechsterSchritt;
  final VoidCallback aufZeigen;

  @override
  Widget build(BuildContext context) {
    final kachelKey = ValueKey('starter_aufgabe_${aufgabe.id}');
    if (erledigt) {
      return Semantics(
        label: '${aufgabe.titel}, erledigt',
        child: Padding(
          key: kachelKey,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: accent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  aufgabe.titel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: Colors.white38,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: '${aufgabe.titel}, zeigen wie',
      child: InkWell(
        key: kachelKey,
        onTap: aufZeigen,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
          decoration: BoxDecoration(
            color: naechsterSchritt
                ? accent.withValues(alpha: 0.11)
                : Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: naechsterSchritt
                  ? accent.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: naechsterSchritt ? _naechster() : _spaeter(),
        ),
      ),
    );
  }

  /// Der Hero: Symbol, Titel, Beschreibung, „Zeigen".
  Widget _naechster() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.radio_button_unchecked, color: accent, size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                aufgabe.titel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                aufgabe.beschreibung,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'Zeigen',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  /// Offen, aber nicht als Nächstes: eine Zeile, Pfeil statt Pille.
  ///
  /// Der Pfeil ist derselbe Knopf wie „Zeigen" — die ganze Kachel führt hin
  /// ([InkWell] darüber). Er ist nur schmaler, damit dem Titel bei 320 Punkten
  /// Breite genug Platz bleibt und nichts umbricht.
  Widget _spaeter() {
    return Row(
      children: [
        Icon(
          Icons.radio_button_unchecked,
          color: Colors.white.withValues(alpha: 0.28),
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            aufgabe.titel,
            // Zwei Zeilen erlaubt: „Die ersten 50 Kilometer fahren" braucht bei
            // 320 Punkten fast die volle Breite. Lieber ein Umbruch als ein
            // abgeschnittener Titel — bei den ueblichen Schriften bleibt es
            // trotzdem einzeilig.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: accent.withValues(alpha: 0.75),
        ),
      ],
    );
  }
}

/// Wie viele XP das Starter-Paket bringt.
///
/// 2026-08-25 (vucko): „man soll sehen man bekommt ein badge 1000 XP + noch
/// einen 2 fach boost der 7 Tage lang aktiv ist". Die Gutschrift selbst baut
/// eine andere Hand im `GamificationService`; hier steht nur die Zahl, die
/// angezeigt wird.
const int starterBelohnungXp = 1000;

/// Der Name des Abzeichens, das am Ende der Liste steht.
///
/// 2026-08-25 (vucko): „das abzeichen nach dem onboarding soll startklar
/// heissen und nicht durchgespielt". Umbenannt wird `badge.dart` von anderer
/// Hand. Bis das steht, zeigt die Karte trotzdem den Namen, den Vucko genannt
/// hat: Der Katalogname wird übernommen, sobald er nicht mehr „Durchgespielt"
/// lautet. So steht hier nie ein Wort, das er nicht sehen will, und nach der
/// Umbenennung folgt die Karte wieder dem Katalog.
String starterBelohnungAbzeichen() {
  final name = app.Badge.getById(app.Badge.onboardingBadgeId)?.name;
  if (name == null || name.isEmpty || name == 'Durchgespielt') {
    return 'Startklar';
  }
  return name;
}

/// Was es am Ende gibt — der Grund, die Liste überhaupt anzufassen.
///
/// 2026-08-25 (vucko): „das man auch sieht was man als belohnung bekommt
/// unten". Er steht deshalb als Letztes in der Karte, unter den Bereichen.
///
/// Vorher stand an dieser Stelle ein Absatz von 112 Punkten Höhe, der die
/// Belohnung BESCHRIEB („Noch 8 Schritte bis zum Startklar-Abzeichen und einer
/// Woche doppelte XP. Wer alle 12 schafft, bekommt das Abzeichen ..."). Drei
/// Zeilen Fließtext, in denen zwei Schwellen und zwei Abzeichen vorkamen — der
/// Satz war der Grund, warum niemand wusste, wofür er hier tippt. Jetzt sind
/// es drei Pillen: Abzeichen, XP, Bonuswoche. Man sieht sie, statt sie zu
/// lesen.
class StarterBelohnungsBlock extends StatelessWidget {
  const StarterBelohnungsBlock({
    super.key,
    required this.accent,
    required this.offeneAufgaben,
  });

  final Color accent;
  final int offeneAufgaben;

  @override
  Widget build(BuildContext context) {
    final rest = offeneAufgaben == 1
        ? 'Noch 1 Schritt'
        : 'Noch $offeneAufgaben Schritte';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.redeem_rounded, color: accent, size: 17),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Deine Belohnung',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Flexible statt fest: sonst nimmt sich die Restzahl bei einer
              // hochgestellten Systemschrift die ganze Zeile und die
              // Ueberschrift schrumpft auf drei Buchstaben.
              Flexible(
                child: Text(
                  rest,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Das Abzeichen steht ALLEIN in seiner Zeile, und zwar aus zwei
          // Gruenden. Erstens ist es der Preis, den Vucko zuerst nennt.
          // Zweitens gemessen: „Abzeichen „Startklar"" braucht bei 320 Punkten
          // Breite 254 Punkte, verfuegbar sind 242 — als dritte Pille in einer
          // Reihe waere die Beschriftung abgeschnitten worden. Ueber die ganze
          // Breite passt sie mit Luft.
          _BelohnungsZeile(
            symbol: Icons.workspace_premium_rounded,
            text: 'Abzeichen ${starterBelohnungAbzeichen()}',
            accent: accent,
            hervorgehoben: true,
          ),
          const SizedBox(height: 6),
          // Die beiden anderen nebeneinander: zusammen 216 Punkte, sie passen
          // auch bei 320 in eine Zeile. Das Wrap faengt trotzdem ab, falls
          // jemand die Schriftgroesse hochstellt.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _BelohnungsPille(
                symbol: Icons.bolt_rounded,
                text: '$starterBelohnungXp XP',
                accent: accent,
              ),
              _BelohnungsPille(
                symbol: Icons.timelapse_rounded,
                text: '7 Tage doppelte XP',
                accent: accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BelohnungsPille extends StatelessWidget {
  const _BelohnungsPille({
    required this.symbol,
    required this.text,
    required this.accent,
  });

  final IconData symbol;
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(symbol, size: 13, color: accent),
          const SizedBox(width: 5),
          // Flexible, damit eine hochgestellte Systemschrift die Pille
          // schrumpfen laesst, statt die Zeile zu sprengen.
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Der Hauptpreis, ueber die ganze Breite.
class _BelohnungsZeile extends StatelessWidget {
  const _BelohnungsZeile({
    required this.symbol,
    required this.text,
    required this.accent,
    this.hervorgehoben = false,
  });

  final IconData symbol;
  final String text;
  final Color accent;
  final bool hervorgehoben;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent.withValues(alpha: hervorgehoben ? 0.65 : 0.35),
        ),
      ),
      // GEMESSEN bei 320 Punkten: „Abzeichen „Startklar"" braucht bei 11
      // Punkten Schrift 220 Punkte, hier stehen 233 zur Verfuegung. Mit 12
      // Punkten Schrift waren es 240 — die Beschriftung endete mit drei
      // Punkten. Der Test „keine Beschriftung wird abgeschnitten" haelt das
      // fest.
      child: Row(
        children: [
          Icon(symbol, size: 14, color: accent),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
