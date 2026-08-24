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
/// Drei Zustände:
///  * Aufgaben offen  → Checkliste mit Fortschritt.
///  * Bonus läuft     → „2× XP"-Countdown, tickt im Minutentakt.
///  * Bonus vorbei    → die Karte verschwindet ersatzlos.
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
    _tick?.cancel();
    super.dispose();
  }

  /// Alle Aufgaben frisch erledigt: Badge verleihen (Animation) und den
  /// Eintrag dauerhaft ins Profil schreiben.
  Future<void> _beiPaketVerdient() async {
    if (!StarterAufgabenService.instance.paketFrischVerdient.value) return;
    StarterAufgabenService.instance.paketFrischVerdient.value = false;

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
        if (!bisher.contains(app.Badge.starterBadgeId)) {
          await db
              .from('profiles')
              .update({
                'badges': [...bisher, app.Badge.starterBadgeId],
              })
              .eq('id', userId);
        }
      }
    } catch (e) {
      debugPrint('[Starter] Badge-Eintrag fehlgeschlagen: $e');
    }
    unawaited(GamificationService.calculateAndSync());

    if (!mounted) return;
    final badge = app.Badge.getById(app.Badge.starterBadgeId);
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

        // Bonus vorbei und Paket vergeben: nichts mehr anzeigen.
        if (dienst.paketVergeben && !dienst.doppelXpAktiv) {
          return const SizedBox.shrink();
        }

        final accent = AppAccentColors.accent;
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: dienst.doppelXpAktiv
              ? _bonusInhalt(accent, dienst)
              : _aufgabenInhalt(accent, dienst),
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
            // 2026-08-24 (Aufgabe 4.5): Der Zaehler zeigt die SCHWELLE, nicht
            // die Listenlaenge. Vorher stand „3/8", und acht war zugleich die
            // Zahl der Zeilen — jetzt sind es elf Zeilen, von denen acht
            // genuegen. „3/8" ueber elf Zeilen waere ohne den Satz darunter
            // nicht zu verstehen.
            Text(
              '${dienst.erledigtAnzahl.clamp(0, StarterAufgabenService.aufgabenFuerBoost)}'
              '/${StarterAufgabenService.aufgabenFuerBoost}',
              style: TextStyle(
                color: accent,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Erledige ${StarterAufgabenService.aufgabenFuerBoost} dieser '
          '${StarterAufgabenService.aufgaben.length} Schritte und du bekommst '
          'das Startklar-Abzeichen plus eine Woche doppelte XP.',
          style: const TextStyle(color: Colors.white54, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        for (final aufgabe in StarterAufgabenService.aufgaben)
          _aufgabenZeile(context, accent, dienst, aufgabe),
      ],
    );
  }

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
