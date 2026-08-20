import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cruise_connect/domain/models/road_incident.dart';

/// 2026-07-24 (vucko "+-Button"): Melde-Sheet — Waze-Prinzip: EIN Tap auf
/// einen der drei großen Buttons meldet sofort an der aktuellen Position,
/// kein zweiter Bestätigungsschritt (minimale Ablenkung während der Fahrt).
/// Gibt den gewählten Typ zurück (null = abgebrochen); das eigentliche
/// Melden macht der Aufrufer (der kennt die aktuelle Position).
class IncidentReportSheet extends StatelessWidget {
  const IncidentReportSheet({super.key});

  static const Color _bgDark = Color(0xFF11141B);

  static Future<RoadIncidentType?> show(BuildContext context) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet<RoadIncidentType>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (_) => const IncidentReportSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _bgDark,
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.14),
                width: 1.2,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const Text(
                  'Was ist los?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Wird an deiner aktuellen Position gemeldet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    for (final type in RoadIncidentType.values) ...[
                      if (type != RoadIncidentType.values.first)
                        const SizedBox(width: 12),
                      Expanded(child: _TypeButton(type: type)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 2026-08-20 (Vucko, Aufgabe 4: der Stau soll „halt irgendwie automatisch
/// erfasst" werden): Wenn die Stau-Erkennung aus dem Fahrprofil sicher ist,
/// fragt die App EINMAL nach, statt ungefragt zu melden.
///
/// WARUM FRAGEN UND NICHT AUTOMATISCH MELDEN. In 104 Tagen gab es genau EINE
/// Ueberlappung zweier Fahrer am selben Ort. Eine falsche automatische Meldung
/// wuerde also von niemandem korrigiert, sie stuende einfach da, und sie
/// kostet den Melder serverseitig Vertrauen. Der Fahrer dagegen steht in genau
/// diesem Moment und kann in einer Sekunde entscheiden. Ein Tippen ist
/// unvergleichlich weniger Aufwand als der Weg ueber den Melde-Knopf, damit
/// ist Vuckos Wunsch erfuellt, ohne die Karte zu vermuellen.
///
/// Antwortet niemand, passiert nichts. Kein Timeout meldet still im
/// Hintergrund — das waere das automatische Melden durch die Hintertuer.
class StauFrageSheet extends StatefulWidget {
  const StauFrageSheet({super.key, required this.grund});

  /// Kurze Begruendung aus der Erkennung, zum Beispiel „Anfahren und Stehen im
  /// Abstand von 40 m". Der Fahrer soll sehen, warum gefragt wird.
  final String grund;

  static const Color _bgDark = Color(0xFF11141B);

  /// true = Fahrer bestaetigt den Stau, false/null = nicht melden.
  static Future<bool?> show(BuildContext context, {required String grund}) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (_) => StauFrageSheet(grund: grund),
    );
  }

  @override
  State<StauFrageSheet> createState() => _StauFrageSheetState();
}

class _StauFrageSheetState extends State<StauFrageSheet> {
  Timer? _autoDismiss;

  /// Zwoelf Sekunden. Laenger als das „Noch da?"-Blatt (acht Sekunden), weil
  /// hier nicht auf eine Warnung reagiert wird, sondern eine Frage beantwortet
  /// — und weil der Fahrer im Stau ohnehin steht.
  static const Duration _autoDismissDauer = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _autoDismiss = Timer(_autoDismissDauer, () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const type = RoadIncidentType.stau;
    final accent = type.color;
    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.18),
                StauFrageSheet._bgDark,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.45],
            ),
            border: Border(top: BorderSide(color: accent, width: 1.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.18),
                        border: Border.all(color: accent, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Icon(type.icon, color: accent, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Steht der Verkehr?',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.grund,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _AntwortButton(
                        label: 'Ja, Stau',
                        icon: Icons.traffic_rounded,
                        color: accent,
                        primary: true,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).pop(true);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AntwortButton(
                        label: 'Nein',
                        icon: Icons.close_rounded,
                        color: Colors.white,
                        primary: false,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).pop(false);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Ohne Antwort wird nichts gemeldet',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 11,
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
}

class _AntwortButton extends StatelessWidget {
  const _AntwortButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: color.withValues(alpha: primary ? 0.92 : 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.withValues(alpha: primary ? 0.0 : 0.4),
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: primary ? Colors.black : color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: primary ? Colors.black : color,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  final RoadIncidentType type;
  const _TypeButton({required this.type});

  @override
  Widget build(BuildContext context) {
    final color = type.color;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).pop(type);
        },
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 1.4),
          ),
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.18),
                  border: Border.all(color: color, width: 2),
                ),
                alignment: Alignment.center,
                child: Icon(type.icon, color: color, size: 28),
              ),
              const SizedBox(height: 10),
              Text(
                type.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
