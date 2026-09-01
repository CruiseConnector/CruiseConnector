import 'dart:async';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/app_tutorial_service.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';
import 'package:cruise_connect/data/services/tutorial_ziel_registry.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';
import 'package:cruise_connect/presentation/widgets/badge_unlock_popup.dart';
import 'package:cruise_connect/presentation/widgets/starter_bereiche.dart';
import 'package:cruise_connect/presentation/widgets/ziel_hinweis_overlay.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Die Starter-Paket-Karte auf dem Startbildschirm.
///
/// 2026-08-14 (vucko): Aufgaben nach dem Onboarding, Starter-Paket als
/// Belohnung, danach eine Woche Doppel-XP mit echtem Countdown.
///
/// 2026-08-25 (vucko): „es soll darstehen beim onboarding widget wie weit ich
/// schon bin und als oberstes widget bis ich es abgeschlossen habe [...] also
/// einfach alle funktionen einmal durchgetestet haben die es in der app gibt."
///
/// SICHTBARKEIT — hier lag der Fehler, den er gemeldet hat. Die Bedingung war
/// `paketVergeben && !doppelXpAktiv → verschwinden`. „Vergeben" heißt aber nur
/// ACHT von zwölf Aufgaben. GEMESSEN am 25.08. in der Produktivdatenbank:
/// Vuckos Profil hat zehn von zwölf Aufgaben erledigt und ein
/// `starter_bonus_ende` vom 22.08., also eine abgelaufene Bonuswoche. Beide
/// Teile der alten Bedingung waren damit wahr — die Karte war für ihn
/// unsichtbar, mit zwei offenen Aufgaben. Deshalb hat er sie nie gesehen.
///
/// AB JETZT verschwindet die Karte erst, wenn ALLE zwölf Aufgaben erledigt
/// sind (und keine Bonuswoche mehr läuft). Solange etwas offen ist, steht sie
/// oben und zeigt, wie weit man ist.
///
/// Zustände:
///  * Aufgaben offen              → Fortschritt + Gliederung + Belohnung.
///  * Bonus läuft, Rest offen     → „2× XP"-Countdown UND die Restliste.
///  * Bonus läuft, alles erledigt → nur der Countdown.
///  * Alles erledigt, kein Bonus  → die Karte verschwindet ersatzlos.
///
/// ─────────────────────────────────────────────────────────────────────────
/// 2026-08-25, zweiter Auftrag desselben Tages (vucko wörtlich): „mache es so
/// das die leute es zuklappen koennen und das ganze besser gegliedert ist
/// unter fahren unter community usw. [...] sonnst ist es zu unuebersichtlich
/// das man auch sieht was man als belohnung bekommt unten [...] und es soll
/// besser eingerahmt sein pro aufgabe".
///
/// GEMESSEN, bevor etwas geändert wurde (Widget-Test, 320 Punkte Breite,
/// frisches Konto, 0 von 12 erledigt):
///
///   Karte gesamt                       2165 pt
///   davon die zwölf Aufgabenzeilen     1870 pt   (86 %)
///   der Erklärabsatz unter dem Balken   112 pt
///   Karte bei 10 von 12                1552 pt
///
/// Also drei Bildschirmlängen Liste, ganz oben auf der Startseite. Nach dem
/// Umbau, im selben Aufbau gemessen:
///
///   Karte gesamt                        759 pt   (−65 %)
///   alle drei Bereiche aufgeklappt     1234 pt   (der schlimmste Fall,
///                                                immer noch 43 % unter alt)
///   ganz zugeklappt                     119 pt
///
/// (Die Zahlen sind mit der Testschrift gemessen, in der jedes Zeichen ein
/// Quadrat ist. Auf dem Gerät ist alles kleiner — der Vergleich stimmt, weil
/// beide Zustände gleich gemessen sind.)
///
/// DER AUFBAU, von oben nach unten:
///   1. Kopfzeile: Symbol, „Dein Starter-Paket", Stand „3/12", Pfeil. Die
///      ganze Zeile klappt die Karte zu und wieder auf, dauerhaft.
///   2. Fortschrittsbalken über die ganzen zwölf.
///   3. Drei Bereiche als Schubladen (`starter_bereiche.dart`), von denen
///      genau EINE offen ist: die erste mit einer offenen Aufgabe.
///   4. Der Belohnungsblock, ganz unten: Abzeichen, XP, Bonuswoche.
class StarterPaketKarte extends StatefulWidget {
  const StarterPaketKarte({super.key, this.onTabChange});

  /// 2026-08-16 (vucko Testfahrt T5): Aufgabe antippen → direkt hinfuehren
  /// (Tab wechseln) und dort zeigen, was zu tun ist („so geht das").
  final ValueChanged<int>? onTabChange;

  @override
  State<StarterPaketKarte> createState() => _StarterPaketKarteState();
}

class _StarterPaketKarteState extends State<StarterPaketKarte> {
  Timer? _tick;

  /// 2026-08-25: Die Verleihungen laufen NACHEINANDER.
  ///
  /// Seit badge_16 (acht) und badge_58 (zwoelf) an verschiedenen Schwellen
  /// haengen, koennen beide im selben Durchgang fallen — wer von sieben
  /// erledigten Aufgaben aus einen Sync macht, springt auf zwoelf. Beide
  /// Melder feuern dann synchron hintereinander, und ohne diese Kette
  /// staenden zwei Verleihungs-Dialoge uebereinander.
  Future<void> _verleihKette = Future<void>.value();

  @override
  void initState() {
    super.initState();
    unawaited(StarterAufgabenService.instance.load());
    // 2026-08-19 (vucko): Der Starter-Zustand lag ausschliesslich im
    // Geraetespeicher. Gemessen: ein Geraetewechsel loeschte die laufende
    // Bonuswoche, und derselbe Account konnte auf einem zweiten Geraet eine
    // ZWEITE Woche bekommen. Der Abgleich holt den Stand vom Profil, sobald
    // die Startseite steht — das ist der frueheste Zeitpunkt, an dem die
    // Karte ihn braucht. Ohne Anmeldung oder ohne Netz faellt er still aus.
    unawaited(StarterAufgabenService.instance.synchronisiereMitProfil());
    StarterAufgabenService.instance.paketFrischVerdient.addListener(
      _beiPaketVerdient,
    );
    StarterAufgabenService.instance.alleAufgabenFrischErledigt.addListener(
      _beiAllenAufgaben,
    );
    // Zugeklappt-Zustand und die schon gelaufenen Einblendungen holen. Bis das
    // da ist, steht die Karte offen und animiert NICHT — siehe _darfAnimieren.
    unawaited(
      StarterKartenGedaechtnis.laden().then((_) {
        if (mounted) setState(() {});
      }),
    );
    // Minutentakt reicht für einen Wochen-Countdown und kostet nichts.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    StarterAufgabenService.instance.paketFrischVerdient.removeListener(
      _beiPaketVerdient,
    );
    StarterAufgabenService.instance.alleAufgabenFrischErledigt.removeListener(
      _beiAllenAufgaben,
    );
    _tick?.cancel();
    super.dispose();
  }

  /// Die Boost-Schwelle (acht von zwölf) ist frisch gefallen: badge_16
  /// verleihen und die Doppel-XP-Woche feiern.
  Future<void> _beiPaketVerdient() async {
    if (!StarterAufgabenService.instance.paketFrischVerdient.value) return;
    StarterAufgabenService.instance.paketFrischVerdient.value = false;
    await _reiheEin(app.Badge.starterBadgeId);
  }

  /// 2026-08-25 (vucko): Die ZWÖLFTE Aufgabe ist frisch gefallen — „alle
  /// funktionen einmal durchgetestet". Dafür gibt es badge_58.
  ///
  /// Eigener Melder statt eines gemeinsamen: die beiden Abzeichen hängen seit
  /// dem 25.08. an verschiedenen Schwellen (acht gegen zwölf). Wer beide über
  /// denselben Melder laufen ließe, verschöbe zwangsläufig eines von beiden.
  Future<void> _beiAllenAufgaben() async {
    if (!StarterAufgabenService.instance.alleAufgabenFrischErledigt.value) {
      return;
    }
    StarterAufgabenService.instance.alleAufgabenFrischErledigt.value = false;
    await _reiheEin(app.Badge.onboardingBadgeId);
  }

  /// Haengt eine Verleihung hinten an die Kette.
  ///
  /// 2026-09-01 (A18, Vucko: "Manchmal haengt es nach der Badge-Animation"):
  /// Der Faenger ist der Punkt. Ohne ihn blieb die Kette nach dem ERSTEN
  /// Fehlschlag dauerhaft auf einem abgelehnten Future stehen — jede weitere
  /// Verleihung haengte sich daran an und lief nie. Ein einziger Netzhaenger
  /// beim Freischalten legte damit alle folgenden Abzeichen fuer den Rest der
  /// Sitzung still, und zwar lautlos.
  Future<void> _reiheEin(String badgeId) {
    _verleihKette = _verleihKette
        .then((_) => _verleiheAbzeichen(badgeId))
        .catchError((Object e) {
          debugPrint('[Starter] Verleihung von $badgeId fehlgeschlagen: $e');
        });
    return _verleihKette;
  }

  /// Badge dauerhaft ins Profil schreiben und die Verleihung zeigen.
  Future<void> _verleiheAbzeichen(String badgeId) async {
    // Ins Profil haengen — profiles.badges ist append-only, und der
    // Gamification-Sync bildet die VEREINIGUNG aus bisherigen und
    // berechneten Badges: Ein direkt angehaengtes Badge bleibt also stehen.
    try {
      final db = Supabase.instance.client;
      final userId = db.auth.currentUser?.id;
      if (userId != null) {
        final profil = await db
            .from('profiles')
            .select('badges')
            .eq('id', userId)
            .maybeSingle();
        final bisher = (profil?['badges'] is Iterable)
            ? List<String>.from(profil!['badges'] as Iterable)
            : <String>[];
        if (!bisher.contains(badgeId)) {
          await db
              .from('profiles')
              .update({
                'badges': [...bisher, badgeId],
              })
              .eq('id', userId);
        }
      }
    } catch (e) {
      debugPrint('[Starter] Badge-Eintrag fehlgeschlagen: $e');
    }
    unawaited(GamificationService.calculateAndSync());

    if (!mounted) return;
    final badge = app.Badge.getById(badgeId);
    if (badge != null) {
      await showBadgeUnlockPopup(context: context, badges: [badge]);
    }
  }

  String _countdownText(Duration rest) {
    final tage = rest.inDays;
    final stunden = rest.inHours % 24;
    final minuten = rest.inMinutes % 60;
    if (tage > 0) return '$tage T $stunden Std';
    if (stunden > 0) return '$stunden Std $minuten Min';
    return '$minuten Min';
  }

  /// Eigenhaendig auf- oder zugeklappte Bereiche.
  ///
  /// Wie in `badge_uebersicht_panel.dart`: die VORGABE wird bei jedem Aufbau
  /// neu berechnet und nicht in `initState` eingefroren. Der Aufgabenstand
  /// kommt nachgeladen (Geraetespeicher, dann Profil) — waere die Vorgabe
  /// eingefroren, stuende beim ersten Aufbau noch „nichts erledigt" und der
  /// falsche Bereich waere offen.
  final Map<String, bool> _umgeschaltet = {};

  /// Der Bereich, der ohne Zutun offen steht: der erste mit einer offenen
  /// Aufgabe.
  ///
  /// AUSLIEFERUNGSZUSTAND, und zwar mit Absicht genau EINER. Alles zu waere
  /// ratlos — man saehe drei Ueberschriften und keine einzige Aufgabe. Alles
  /// offen waere wieder die flache Liste, die Vucko gemeldet hat (gemessen:
  /// 2165 Punkte Hoehe). Ein offener Bereich zeigt, wo man steht, und die
  /// beiden anderen sagen mit ihrer Pille „2/4", dass da noch etwas kommt.
  String? _vorgabeOffen(List<StarterBereichInhalt> bereiche) {
    final dienst = StarterAufgabenService.instance;
    for (final b in bereiche) {
      if (b.aufgaben.any((a) => !dienst.erledigt(a.id))) return b.bereich.id;
    }
    return bereiche.isEmpty ? null : bereiche.first.bereich.id;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StarterAufgabenService.instance,
      builder: (context, _) {
        final dienst = StarterAufgabenService.instance;
        if (!dienst.isLoaded) return const SizedBox.shrink();

        // 2026-08-25: Erst wenn ALLE zwoelf erledigt sind und keine Bonuswoche
        // mehr laeuft, ist die Karte fertig. Hier stand `paketVergeben`, also
        // acht von zwoelf — siehe der Kommentar ueber der Klasse.
        if (dienst.alleAufgabenErledigt && !dienst.doppelXpAktiv) {
          return const SizedBox.shrink();
        }

        final accent = AppAccentColors.accent;
        final bonus = dienst.doppelXpAktiv;
        final restOffen = !dienst.alleAufgabenErledigt;
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (bonus) _bonusInhalt(accent, dienst),
              // Laeuft die Woche, sind aber noch Aufgaben offen, stehen BEIDE
              // untereinander: der Countdown oben, die Restliste darunter.
              // Vorher verdeckte der Countdown die Liste, und wer den Boost
              // hatte, sah nie wieder, was ihm noch fehlt.
              if (bonus && restOffen) ...[
                const SizedBox(height: 14),
                Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                const SizedBox(height: 14),
              ],
              if (restOffen) _aufgabenInhalt(accent, dienst),
            ],
          ),
        );
      },
    );
  }

  Widget _bonusInhalt(Color accent, StarterAufgabenService dienst) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: Text(
            '2×',
            style: TextStyle(
              color: accent,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Doppel-XP-Woche läuft',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                // 2026-08-19: Hier stand ein Gedankenstrich im sichtbaren
                // Text. Die Repo-Regel verbietet ihn in Nutzertexten.
                'Jede Fahrt zählt doppelt, noch '
                '${_countdownText(dienst.bonusVerbleibend)}.',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _aufgabenInhalt(Color accent, StarterAufgabenService dienst) {
    final bereiche = starterBereicheMitAufgaben();
    final vorgabe = _vorgabeOffen(bereiche);
    final offen = StarterKartenGedaechtnis.geladen
        ? !StarterKartenGedaechtnis.zugeklappt
        : true;
    final gesamt = StarterAufgabenService.aufgaben.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 2026-08-25 (vucko): „mache es so das die leute es zuklappen koennen".
        // Die ganze Kopfzeile ist der Schalter — dieselbe Geste wie bei den
        // Bereichen darunter und bei den Schubladen der Abzeichen-Sammlung.
        Semantics(
          button: true,
          expanded: offen,
          child: InkWell(
            key: const ValueKey('starter_karte_kopf'),
            onTap: _kartenSchalter,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.card_giftcard_rounded, color: accent, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Dein Starter-Paket',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 2026-08-25 (vucko): „es soll darstehen [...] wie weit ich
                  // schon bin". Der Zaehler zeigt die GANZE Liste, nicht die
                  // Boost-Schwelle: Wer bei 8/8 stand, sah „fertig", obwohl
                  // vier Funktionen der App noch nie benutzt waren.
                  Semantics(
                    label:
                        '${dienst.erledigtAnzahl} von $gesamt Aufgaben '
                        'erledigt',
                    child: Text(
                      '${dienst.erledigtAnzahl}/$gesamt',
                      style: TextStyle(
                        color: accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: offen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 21,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _fortschrittsBalken(accent, dienst),
        if (!offen) ...[
          const SizedBox(height: 9),
          // Zugeklappt bleibt der Grund stehen, warum es die Karte gibt.
          // Sonst waere die zugeklappte Karte ein Balken ohne Aussage.
          Row(
            children: [
              Icon(Icons.redeem_rounded, color: accent, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _restText(dienst),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (offen) ...[
          const SizedBox(height: 12),
          for (var i = 0; i < bereiche.length; i++) ...[
            if (i > 0) const SizedBox(height: 7),
            StarterBereichSchublade(
              inhalt: bereiche[i],
              accent: accent,
              offen:
                  _umgeschaltet[bereiche[i].bereich.id] ??
                  (bereiche[i].bereich.id == vorgabe),
              erledigt: dienst.erledigt,
              aufTippen: () => _bereichSchalter(bereiche[i].bereich.id, vorgabe),
              aufZeigen: (aufgabe) => _fuehreHin(context, aufgabe.id),
              animieren: _darfAnimieren(bereiche[i].bereich.id),
              aufAnimationGelaufen: () =>
                  unawaited(
                    StarterKartenGedaechtnis.merkeAnimiert(
                      bereiche[i].bereich.id,
                    ),
                  ),
            ),
          ],
          const SizedBox(height: 12),
          StarterBelohnungsBlock(
            accent: accent,
            offeneAufgaben: gesamt - dienst.erledigtAnzahl,
          ),
        ],
      ],
    );
  }

  String _restText(StarterAufgabenService dienst) {
    final offen =
        StarterAufgabenService.aufgaben.length - dienst.erledigtAnzahl;
    final schritte = offen == 1 ? '1 Schritt' : '$offen Schritte';
    return 'Noch $schritte bis zur Belohnung';
  }

  /// Die ganze Liste auf- oder zuklappen. Der Zustand bleibt ueber den
  /// App-Start hinweg stehen, sonst muesste man nach jedem Start neu zuklappen.
  void _kartenSchalter() {
    final neu = StarterKartenGedaechtnis.geladen
        ? !StarterKartenGedaechtnis.zugeklappt
        : true;
    unawaited(StarterKartenGedaechtnis.setzeZugeklappt(neu));
    setState(() {});
  }

  void _bereichSchalter(String id, String? vorgabe) {
    setState(() {
      _umgeschaltet[id] = !(_umgeschaltet[id] ?? (id == vorgabe));
    });
  }

  /// Die Einblende-Animation laeuft je Bereich genau einmal.
  ///
  /// Solange das Gedaechtnis noch nicht geladen ist, wird NICHT animiert:
  /// sonst liefe sie beim ersten Bild jedes App-Starts, und der gespeicherte
  /// Vermerk „schon gesehen" waere wertlos.
  bool _darfAnimieren(String bereichId) {
    if (!StarterKartenGedaechtnis.geladen) return false;
    return !StarterKartenGedaechtnis.animierteBereiche.contains(bereichId);
  }

  /// Der Fortschrittsbalken ueber der Gliederung.
  ///
  /// 2026-08-25: Die „Boost"-Marke bei acht von zwoelf ist weg. Sie war der
  /// Rest der zwei Schwellen, die Vucko verwechselt hat — und sie widerspraeche
  /// jetzt dem Belohnungsblock unten, der EIN Paket am Ende der Liste zeigt
  /// (Abzeichen, XP, Bonuswoche). Zwei Ziele auf einem Balken, dazu ein
  /// dritter Zaehler in der Kopfzeile: genau daraus entstand die
  /// Unuebersichtlichkeit. Der Balken zeigt seitdem eine Sache: wie weit von
  /// zwoelf.
  Widget _fortschrittsBalken(Color accent, StarterAufgabenService dienst) {
    final gesamt = StarterAufgabenService.aufgaben.length;
    final anteil = gesamt == 0
        ? 0.0
        : (dienst.erledigtAnzahl / gesamt).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final breite = constraints.maxWidth;
        return SizedBox(
          height: 7,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: breite * anteil,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent.withValues(alpha: 0.65), accent],
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Fuehrt direkt zur Stelle, an der die Aufgabe erledigt wird, und zeigt
  /// dort per Spotlight, was zu tun ist.
  Future<void> _fuehreHin(BuildContext context, String id) async {
    switch (id) {
      case 'tutorial':
        await AppTutorialService.requestReplay();
      case 'route':
      case 'favorit':
        CruiseModePage.hinweisWunsch.value = id;
        widget.onTabChange?.call(2);
      case 'community':
        widget.onTabChange?.call(1);
        await Future<void>.delayed(const Duration(milliseconds: 420));
        if (!context.mounted) return;
        await showZielHinweise(
          context,
          schritte: const [
            HinweisSchritt(
              ziel: TutorialZielRegistry.communityDiscover,
              titel: 'Community',
              text:
                  'Hier siehst du, wer unterwegs ist. Unter „Entdecken" findest '
                  'du Gruppen und Leute in deiner Nähe. Aufgabe erledigt.',
            ),
          ],
          letzterKnopf: 'Super',
        );
      case 'speichern':
        // Bleibt auf Home: die Empfehlungs-Karte hat den Speichern-Knopf.
        await showZielHinweise(
          context,
          schritte: const [
            HinweisSchritt(
              ziel: TutorialZielRegistry.homeRouteSpeichern,
              titel: 'Route speichern',
              text:
                  'Tippe hier auf der Empfehlungs-Karte, dann liegt die Strecke '
                  'in deiner Sammlung. Das geht auch nach jeder Fahrt und bei '
                  'jeder geteilten Route im Feed.',
              symbol: Icons.bookmark_add_rounded,
              aufblasen: 10,
            ),
          ],
          letzterKnopf: 'Los geht\'s',
        );
      // 2026-08-19 (vucko): „auch noch weitere sachen wie der erste post, die
      // erste Gruppenfahrt umfasst wo man abschliessen muss und die erste
      // runde gefahren". Auch die neuen drei Zeilen muessen hinfuehren, sonst
      // waere „Zeigen" bei drei von acht Aufgaben eine tote Schaltflaeche.
      case 'runde':
        // Fahren-Reiter: dort wird die Route gesucht und die Fahrt gestartet.
        CruiseModePage.hinweisWunsch.value = 'route';
        widget.onTabChange?.call(2);
      case 'post':
        widget.onTabChange?.call(1);
        await Future<void>.delayed(const Duration(milliseconds: 420));
        if (!context.mounted) return;
        await showZielHinweise(
          context,
          schritte: const [
            HinweisSchritt(
              ziel: TutorialZielRegistry.communityFeed,
              titel: 'Dein erster Post',
              text:
                  'Im Feed teilst du deine Fahrt. Nach jeder Fahrt kannst du '
                  'Foto und Strecke direkt posten.',
              symbol: Icons.add_photo_alternate_rounded,
            ),
          ],
          letzterKnopf: 'Verstanden',
        );
      // 2026-08-24 (Aufgabe 4, vucko): „benutze einen hashtag". Fuehrt an
      // dieselbe Stelle wie „post" — die Raute entsteht im Beitragstext, es
      // gibt keinen eigenen Ort dafuer.
      case 'hashtag':
        widget.onTabChange?.call(1);
        await Future<void>.delayed(const Duration(milliseconds: 420));
        if (!context.mounted) return;
        await showZielHinweise(
          context,
          schritte: const [
            HinweisSchritt(
              ziel: TutorialZielRegistry.communityFeed,
              titel: 'Hashtag setzen',
              text:
                  'Schreib in deinen Beitrag ein Wort mit Raute davor, zum '
                  'Beispiel #Kurvenjagd. Andere finden dich dann darüber — '
                  'und die Aufgabe ist erledigt.',
              symbol: Icons.tag_rounded,
            ),
          ],
          letzterKnopf: 'Verstanden',
        );
      // 2026-08-24 (vucko): „erste Gruppenfahrt erstellen". Der Hinweis sagte
      // bis heute das Gegenteil („zaehlt erst, wenn ihr die Fahrt gemeinsam
      // bis zum Ziel durchzieht") — und genau daran ist der Boost fuer alle
      // 183 Nutzer gescheitert: null Fahrten mit group_id in der ganzen
      // Geschichte der App.
      case 'gruppenfahrt':
        widget.onTabChange?.call(1);
        await Future<void>.delayed(const Duration(milliseconds: 420));
        if (!context.mounted) return;
        await showZielHinweise(
          context,
          schritte: const [
            HinweisSchritt(
              ziel: TutorialZielRegistry.communityRides,
              titel: 'Gruppenfahrt',
              text:
                  'Hier legst du eine Gruppe an. Sobald sie steht, ist die '
                  'Aufgabe erledigt. Wer mitfährt, entscheidet ihr danach.',
              symbol: Icons.groups_rounded,
            ),
          ],
          letzterKnopf: 'Verstanden',
        );
      // 2026-08-24 (vucko): „Auto in die Garage hinzufuegen".
      case 'garage':
        widget.onTabChange?.call(4);
        await Future<void>.delayed(const Duration(milliseconds: 420));
        if (!context.mounted) return;
        await showZielHinweise(
          context,
          schritte: const [
            HinweisSchritt(
              ziel: TutorialZielRegistry.profilGarage,
              titel: 'Deine Garage',
              text:
                  'Trag hier dein Auto ein: Marke, Modell, Leistung. Andere '
                  'sehen dann, womit du unterwegs bist.',
              symbol: Icons.directions_car_rounded,
            ),
          ],
          letzterKnopf: 'Los geht\'s',
        );
      // 2026-08-24 (vucko): „die ersten drei Badges sammeln".
      case 'abzeichen':
        widget.onTabChange?.call(3);
        await Future<void>.delayed(const Duration(milliseconds: 420));
        if (!context.mounted) return;
        await showZielHinweise(
          context,
          schritte: const [
            HinweisSchritt(
              ziel: TutorialZielRegistry.analyticsUebersicht,
              titel: 'Deine Abzeichen',
              text:
                  'Hier liegt deine Sammlung. Tippe ein gesperrtes Abzeichen '
                  'an, dann steht da, was dafür fehlt. '
                  '${StarterAufgabenService.abzeichenFuerAufgabe} Stück, dann '
                  'ist die Aufgabe erledigt.',
              symbol: Icons.workspace_premium_rounded,
            ),
          ],
          letzterKnopf: 'Verstanden',
        );
      // 2026-08-24 (vucko): „die ersten 50 Kilometer fahren".
      case 'km50':
        // Wie bei „runde": der Fahren-Reiter ist die Stelle, an der Strecke
        // entsteht. Nur der Text ist ein anderer.
        CruiseModePage.hinweisWunsch.value = 'route';
        widget.onTabChange?.call(2);
      default:
        break;
    }
  }
}
