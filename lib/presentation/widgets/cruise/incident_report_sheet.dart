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
