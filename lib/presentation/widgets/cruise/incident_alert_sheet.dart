import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/road_incident_service.dart';
import 'package:cruise_connect/domain/models/road_incident.dart';

/// 2026-07-24 (vucko "+-Button"): "Noch da?"-Sheet beim Annähern an eine
/// Crowd-Meldung — exakt das bewährte [ConstructionAlertSheet]-UX-Muster
/// (30% Höhe, zwei große Buttons, 8s Auto-Dismiss ohne Vote, Haptik),
/// nur mit Typ-abhängiger Farbe/Icon/Titel und dem road_incidents-Vote-RPC.
class IncidentAlertSheet extends StatefulWidget {
  final RoadIncident incident;

  const IncidentAlertSheet({super.key, required this.incident});

  static const Color _bgDark = Color(0xFF11141B);

  static Future<void> show(BuildContext context, RoadIncident incident) async {
    HapticFeedback.mediumImpact();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (_) => IncidentAlertSheet(incident: incident),
    );
  }

  @override
  State<IncidentAlertSheet> createState() => _IncidentAlertSheetState();
}

class _IncidentAlertSheetState extends State<IncidentAlertSheet>
    with SingleTickerProviderStateMixin {
  Timer? _autoDismissTimer;
  Timer? _progressTicker;
  late final AnimationController _pulseController;
  double _autoDismissProgress = 1.0;
  bool _voting = false;

  static const Duration _autoDismissDuration = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _autoDismissTimer = Timer(_autoDismissDuration, _dismissWithoutVote);
    _progressTicker = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _autoDismissProgress =
            1.0 - (timer.tick * 60.0) / _autoDismissDuration.inMilliseconds;
        if (_autoDismissProgress <= 0) {
          _autoDismissProgress = 0;
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _progressTicker?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _dismissWithoutVote() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  /// 2026-07-29 (vucko „ich konnte den gemeldeten Unfall beim naechsten Mal
  /// nicht mehr bereinigen"): Auf die EIGENE Meldung nimmt der Server keine
  /// Stimme an (er wirft „eigene Meldung"). Das Sheet zeigte trotzdem nur
  /// „Noch da / Schon weg" — der Melder konnte seine eigene Meldung also
  /// niemals wegraeumen, der Tipp lief jedes Mal ins Leere.
  /// Fuer die eigene Meldung gibt es deshalb das Zuruecknehmen.
  bool get _istEigeneMeldung {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    return uid != null && widget.incident.reportedBy == uid;
  }

  Future<void> _zuruecknehmen() async {
    if (_voting) return;
    setState(() => _voting = true);
    HapticFeedback.lightImpact();
    final ok = await RoadIncidentService.instance.retract(widget.incident.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Meldung zurueckgenommen.' : 'Konnte gerade nicht gespeichert werden.',
        ),
        backgroundColor: Colors.grey.shade800,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _vote(bool stillThere) async {
    if (_voting) return;
    setState(() => _voting = true);
    HapticFeedback.lightImpact();
    final ok = await RoadIncidentService.instance.vote(
      incidentId: widget.incident.id,
      stillThere: stillThere,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    // 2026-07-25 (Review-Fund): schlug der Vote fehl (offline/Server), sah das
    // vorher exakt wie ein Erfolg aus. Ehrliche Rückmeldung wie im
    // Baustellen-Sheet.
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Konnte gerade nicht gespeichert werden.'),
          backgroundColor: Colors.grey.shade800,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final incident = widget.incident;
    final accent = incident.type.color;

    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.18),
                IncidentAlertSheet._bgDark,
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: _autoDismissProgress,
                    minHeight: 2,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      accent.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final scale = 0.9 + _pulseController.value * 0.18;
                        return Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withValues(alpha: 0.18),
                            border: Border.all(color: accent, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(
                                  alpha: 0.35 * _pulseController.value,
                                ),
                                blurRadius: 22,
                                spreadRadius: 4 * _pulseController.value,
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Transform.scale(
                            scale: scale,
                            child: Icon(
                              incident.type.icon,
                              color: accent,
                              size: 28,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${incident.type.label} voraus',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Von der Community gemeldet, ist das noch da?',
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    _StatChip(
                      icon: Icons.thumb_up_outlined,
                      label: '${incident.confirmedCount}',
                      color: Colors.greenAccent.shade400,
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      icon: Icons.thumb_down_outlined,
                      label: '${incident.dismissedCount}',
                      color: Colors.redAccent,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_istEigeneMeldung)
                  // Eigene Meldung: abstimmen geht nicht, zuruecknehmen schon.
                  SizedBox(
                    width: double.infinity,
                    child: _VoteButton(
                      label: 'Meldung zurücknehmen',
                      icon: Icons.undo_rounded,
                      color: Colors.greenAccent.shade400,
                      primary: true,
                      loading: _voting,
                      onTap: _zuruecknehmen,
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: _VoteButton(
                          label: 'Noch da',
                          icon: Icons.warning_amber_rounded,
                          color: accent,
                          primary: true,
                          loading: _voting,
                          onTap: () => _vote(true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _VoteButton(
                          label: 'Schon weg',
                          icon: Icons.check_circle_outline_rounded,
                          color: Colors.greenAccent.shade400,
                          primary: false,
                          loading: _voting,
                          onTap: () => _vote(false),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _istEigeneMeldung
                        ? 'Deine Meldung — verschwindet automatisch'
                        : 'Verschwindet automatisch',
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

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoteButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool primary;
  final bool loading;
  final VoidCallback onTap;
  const _VoteButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.primary,
    required this.loading,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: primary
                ? LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.95),
                      color.withValues(alpha: 0.68),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: primary ? null : color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.withValues(alpha: primary ? 0.0 : 0.45),
              width: 1.2,
            ),
            boxShadow: primary
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: loading
              ? SizedBox(
                  height: 22,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          primary ? Colors.white : color,
                        ),
                      ),
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: primary ? Colors.white : color, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: primary ? Colors.white : color,
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
