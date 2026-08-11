import 'package:cruise_connect/data/services/app_version_gate_service.dart';
import 'package:cruise_connect/presentation/pages/update_required_page.dart';
import 'package:flutter/material.dart';

/// Prüft beim Start, ob die installierte Version noch erlaubt ist, und
/// blockiert sonst den Zugang zur ganzen App.
///
/// 2026-08-10 (vucko): „bevor sie in die App reingehen koennen." Deshalb sitzt
/// dieses Gate ganz aussen — vor Splash, Sprachwahl und Anmeldung.
///
/// Waehrend der Pruefung (Bruchteil einer Sekunde bis max. 5 s bei schlechtem
/// Netz) wird der Launch-Hintergrund gezeigt, damit nichts aufblitzt — der
/// eigentliche Splash liegt ohnehin darueber. Faellt die Pruefung durch, laesst
/// der Dienst den Nutzer bewusst REIN (fail-open).
class ForceUpdateGate extends StatefulWidget {
  const ForceUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends State<ForceUpdateGate> {
  Future<AppVersionGateResult>? _pruefung;

  @override
  void initState() {
    super.initState();
    _pruefung = AppVersionGateService.pruefe();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppVersionGateResult>(
      future: _pruefung,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          // Launch-Hintergrundfarbe, damit kein weisser Blitz entsteht.
          return const ColoredBox(
            color: Color(0xFF0D141E),
            child: SizedBox.expand(),
          );
        }
        final ergebnis = snap.data;
        if (ergebnis != null && ergebnis.blockiert) {
          return UpdateRequiredPage(
            storeUrl: ergebnis.storeUrl,
            nachricht: ergebnis.nachricht,
          );
        }
        return widget.child;
      },
    );
  }
}
