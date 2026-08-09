import 'package:flutter/material.dart';

/// Was der Fahrer tun will, wenn er von der Gruppenroute abgekommen ist.
enum GroupDivergenceChoice {
  /// Zurück auf die Gruppenroute — dorthin, wo ich sie verlassen habe.
  backToRoute,

  /// Die aktuelle Route der Gruppe von hier aus neu übernehmen.
  adoptGroupRoute,

  /// Eigene Route — ich fahre selbst weiter, die Gruppe wartet nicht auf mich.
  ownRoute,
}

/// Karte, die erscheint, wenn ein Gruppen-Mitfahrer von der Route abgekommen
/// ist und NICHT selbst neu berechnen darf (der Vorderste führt).
///
/// 2026-08-09 (vucko, Gruppenfahrt am 08.08.): „wir haben nicht gewusst wohin
/// fahren, dann mussten wir die Route leider abbrechen, was sehr frustrierend
/// war." Genau diese Sackgasse schließt diese Karte: Wer abkommt, bekommt drei
/// klare Wege statt einer stillen „Neuberechnung", die nie endet.
///
/// BEWUSST KEIN MODALER DIALOG. Während der Fahrt darf nichts die Karte
/// zudecken oder eine Antwort erzwingen — ein Dialog mitten im Verkehr ist
/// gefährlich. Die Karte liegt über den unteren Bedienelementen, lässt sich
/// wegwischen und blockiert nichts.
class GroupDivergenceCard extends StatelessWidget {
  const GroupDivergenceCard({
    super.key,
    required this.gapMeters,
    required this.onChoice,
    required this.onDismiss,
    this.busy = false,
  });

  /// Luftlinie zur Gruppenroute — macht die Lage greifbar („380 m entfernt").
  final double gapMeters;
  final ValueChanged<GroupDivergenceChoice> onChoice;
  final VoidCallback onDismiss;

  /// Während eine Wahl verarbeitet wird: Knöpfe sperren, damit ein zweiter
  /// Tipper nicht zwei Routenwechsel gleichzeitig auslöst.
  final bool busy;

  static const _hintergrund = Color(0xFF161A22);
  static const _rand = Color(0xFF2B3242);
  static const _akzent = Color(0xFFFF4D24);

  String get _abstandText {
    if (!gapMeters.isFinite || gapMeters <= 0) return '';
    if (gapMeters >= 1000) {
      return '${(gapMeters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km '
          'von der Gruppenroute entfernt';
    }
    return '${gapMeters.round()} m von der Gruppenroute entfernt';
  }

  @override
  Widget build(BuildContext context) {
    final abstand = _abstandText;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: _hintergrund,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _rand),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.alt_route, color: _akzent, size: 20),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'Du bist von der Gruppe abgekommen',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: busy ? null : onDismiss,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  tooltip: 'Ausblenden',
                ),
              ],
            ),
            if (abstand.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                abstand,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _knopf(
              text: 'Zurück zur Gruppenroute',
              unter: 'Führt dich dorthin zurück, wo du sie verlassen hast',
              icon: Icons.u_turn_left,
              hervorgehoben: true,
              wahl: GroupDivergenceChoice.backToRoute,
            ),
            const SizedBox(height: 8),
            _knopf(
              text: 'Gruppenroute von hier übernehmen',
              unter: 'Plant die Route der Gruppe ab deinem Standort neu',
              icon: Icons.groups,
              hervorgehoben: false,
              wahl: GroupDivergenceChoice.adoptGroupRoute,
            ),
            const SizedBox(height: 8),
            _knopf(
              text: 'Eigene Route fahren',
              unter: 'Du fährst selbstständig weiter zum Ziel',
              icon: Icons.navigation_outlined,
              hervorgehoben: false,
              wahl: GroupDivergenceChoice.ownRoute,
            ),
          ],
        ),
      ),
    );
  }

  Widget _knopf({
    required String text,
    required String unter,
    required IconData icon,
    required bool hervorgehoben,
    required GroupDivergenceChoice wahl,
  }) {
    final farbe = hervorgehoben ? _akzent : const Color(0xFF1E2431);
    return Opacity(
      opacity: busy ? 0.5 : 1.0,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: busy ? null : () => onChoice(wahl),
        child: Container(
          decoration: BoxDecoration(
            color: farbe,
            borderRadius: BorderRadius.circular(13),
            border: hervorgehoben ? null : Border.all(color: _rand),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 19, color: Colors.white),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      unter,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.66),
                        fontSize: 11.5,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
