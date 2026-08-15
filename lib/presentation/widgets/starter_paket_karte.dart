import 'dart:async';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/presentation/widgets/badge_unlock_popup.dart';
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
  const StarterPaketKarte({super.key});

  @override
  State<StarterPaketKarte> createState() => _StarterPaketKarteState();
}

class _StarterPaketKarteState extends State<StarterPaketKarte> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    unawaited(StarterAufgabenService.instance.load());
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
                'Jede Fahrt zählt doppelt — noch '
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
            Text(
              '${dienst.erledigtAnzahl}/${StarterAufgabenService.aufgaben.length}',
              style: TextStyle(
                color: accent,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Erledige diese Schritte und du bekommst das Startklar-Abzeichen '
          'plus eine Woche doppelte XP.',
          style: TextStyle(color: Colors.white54, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        for (final aufgabe in StarterAufgabenService.aufgaben)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Icon(
                  dienst.erledigt(aufgabe.id)
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  color: dienst.erledigt(aufgabe.id)
                      ? accent
                      : Colors.white24,
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
                          color: dienst.erledigt(aufgabe.id)
                              ? Colors.white38
                              : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          decoration: dienst.erledigt(aufgabe.id)
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      Text(
                        aufgabe.beschreibung,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
