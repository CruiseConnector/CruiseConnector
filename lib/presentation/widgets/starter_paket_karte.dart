import 'dart:async';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/app_tutorial_service.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';
import 'package:cruise_connect/data/services/tutorial_ziel_registry.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';
import 'package:cruise_connect/presentation/widgets/badge_unlock_popup.dart';
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
///  * Aufgaben offen              → Fortschritt + Checkliste.
///  * Bonus läuft, Rest offen     → „2× XP"-Countdown UND die Restliste.
///  * Bonus läuft, alles erledigt → nur der Countdown.
///  * Alles erledigt, kein Bonus  → die Karte verschwindet ersatzlos.
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
  Future<void> _reiheEin(String badgeId) {
    _verleihKette = _verleihKette.then((_) => _verleiheAbzeichen(badgeId));
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
          padding: const EdgeInsets.all(18),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.card_giftcard_rounded, color: accent, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Dein Starter-Paket',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // 2026-08-25 (vucko): „es soll darstehen [...] wie weit ich schon
            // bin". Der Zaehler zeigt jetzt die GANZE Liste, nicht die
            // Boost-Schwelle.
            //
            // Vorher stand hier „x/8". Das war die Schwelle fuer die
            // Bonuswoche — und genau die Zahl hat die Verwechslung
            // mitgetragen, die den Auftrag ausgeloest hat: Wer bei 8/8 stand,
            // sah „fertig", obwohl vier Funktionen der App noch nie benutzt
            // waren. Die Schwelle verschwindet nicht, sie wandert eine Zeile
            // tiefer auf den Balken (die „Boost"-Marke). So stehen BEIDE
            // Zahlen da: zwoelf als Ziel, acht als Zwischenstand.
            Semantics(
              label:
                  '${dienst.erledigtAnzahl} von '
                  '${StarterAufgabenService.aufgaben.length} Aufgaben erledigt',
              child: Text(
                '${dienst.erledigtAnzahl}'
                '/${StarterAufgabenService.aufgaben.length}',
                style: TextStyle(
                  color: accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _fortschrittsBalken(accent, dienst),
        const SizedBox(height: 8),
        Text(
          _fortschrittsText(dienst),
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12.5,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        for (final aufgabe in StarterAufgabenService.aufgaben)
          _aufgabenZeile(context, accent, dienst, aufgabe),
      ],
    );
  }

  /// 2026-08-25 (vucko): „es soll darstehen beim onboarding widget wie weit
  /// ich schon bin."
  ///
  /// WARUM EIN BALKEN UND NICHT NUR EINE ZAHL: Es gibt hier ZWEI Schwellen,
  /// die verschiedene Dinge bedeuten — acht (Startklar-Abzeichen plus
  /// Doppel-XP-Woche) und zwoelf (alle Funktionen einmal benutzt, badge_58).
  /// Zwei Zahlen nebeneinander („8/12 und 10/12") liest niemand richtig. Der
  /// Balken zeigt beide ohne Erklaerung: die Fuellung ist der Stand von
  /// zwoelf, die Marke steht bei acht. Was rechts von der Marke liegt, ist der
  /// Weg nach dem Boost.
  Widget _fortschrittsBalken(Color accent, StarterAufgabenService dienst) {
    final gesamt = StarterAufgabenService.aufgaben.length;
    const schwelle = StarterAufgabenService.aufgabenFuerBoost;
    final anteil = gesamt == 0
        ? 0.0
        : (dienst.erledigtAnzahl / gesamt).clamp(0.0, 1.0);
    final markeAnteil = gesamt == 0 ? 0.0 : (schwelle / gesamt).clamp(0.0, 1.0);
    final erreicht = dienst.boostErreicht;

    return LayoutBuilder(
      builder: (context, constraints) {
        final breite = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 10,
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
                        color: accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  // Die Boost-Marke. Sie sitzt AUF dem Balken, damit sie auch
                  // im gefuellten Teil sichtbar bleibt.
                  Positioned(
                    left: (breite * markeAnteil - 1.5).clamp(0.0, breite - 3),
                    top: -1,
                    bottom: -1,
                    width: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1F26),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.55),
                          width: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 14,
              child: Stack(
                children: [
                  Positioned(
                    left: (breite * markeAnteil - 22).clamp(0.0, breite - 44),
                    top: 0,
                    width: 44,
                    child: Text(
                      erreicht ? 'Boost ✓' : 'Boost',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: erreicht
                            ? accent
                            : Colors.white.withValues(alpha: 0.45),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Der Satz unter dem Balken. Er sagt genau EINE Sache: was der naechste
  /// Schritt bringt. Vor dem Boost ist das die Bonuswoche, danach das
  /// Abzeichen fuer die vollstaendige Liste.
  String _fortschrittsText(StarterAufgabenService dienst) {
    final gesamt = StarterAufgabenService.aufgaben.length;
    final abzeichen =
        app.Badge.getById(app.Badge.onboardingBadgeId)?.name ?? 'Durchgespielt';
    if (!dienst.boostErreicht) {
      final bisBoost = StarterAufgabenService.aufgabenFuerBoost -
          dienst.erledigtAnzahl;
      return 'Noch ${_schritte(bisBoost)} bis zum Startklar-Abzeichen und '
          'einer Woche doppelte XP. Wer alle $gesamt schafft, bekommt das '
          'Abzeichen „$abzeichen".';
    }
    final offen = gesamt - dienst.erledigtAnzahl;
    return 'Boost geschafft. Noch ${_schritte(offen)}, dann hast du jede '
        'Funktion der App einmal benutzt und bekommst das Abzeichen '
        '„$abzeichen".';
  }

  static String _schritte(int anzahl) =>
      anzahl == 1 ? '1 Schritt' : '$anzahl Schritte';

  Widget _aufgabenZeile(
    BuildContext context,
    Color accent,
    StarterAufgabenService dienst,
    StarterAufgabe aufgabe,
  ) {
    final erledigt = dienst.erledigt(aufgabe.id);
    return Semantics(
      button: !erledigt,
      label: erledigt ? '${aufgabe.titel}, erledigt' : '${aufgabe.titel}, zeigen wie',
      child: InkWell(
        key: ValueKey('starter_aufgabe_${aufgabe.id}'),
        onTap: erledigt ? null : () => _fuehreHin(context, aufgabe.id),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Row(
            children: [
              Icon(
                erledigt
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                color: erledigt ? accent : Colors.white24,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      aufgabe.titel,
                      style: TextStyle(
                        color: erledigt ? Colors.white38 : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration: erledigt ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    Text(
                      aufgabe.beschreibung,
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (!erledigt) ...[
                const SizedBox(width: 6),
                // „So geht das": kleiner Hinweis, dass die Zeile hinfuehrt.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Zeigen',
                    style: TextStyle(
                      color: accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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
