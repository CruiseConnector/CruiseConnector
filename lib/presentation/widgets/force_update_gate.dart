import 'dart:async';

import 'package:cruise_connect/data/services/app_version_gate_service.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';
import 'package:cruise_connect/presentation/pages/update_required_page.dart';
import 'package:flutter/material.dart';

/// Legt die Update-Sperre als DECKEL über die gesamte App.
///
/// 2026-08-10 (vucko): „bevor sie in die App reingehen koennen."
/// 2026-08-12 (vucko, geschärft): „wenn die app eine alte version hat, man
/// benachrichtigt wird und die app neuinstallieren MUSS um reinzukommen."
///
/// WARUM DECKEL UND NICHT ERSATZ. Die erste Fassung hing als `home:` im
/// Navigator und ERSETZTE die App durch die Sperrseite. Zwei Löcher dabei:
///
///   * Alles, was per `push` oder `pushAndRemoveUntil` auf den Navigator
///     kommt, legt sich ÜBER eine Route — also auch über die Sperrseite. Ein
///     Gruppen-Deeplink oder der Rücksprung nach der Anmeldung hätte die
///     Sperre schlicht überdeckt.
///   * Eine später erkannte Sperre (Schwelle wird hochgesetzt, während die App
///     läuft) hätte gar nicht mehr gegriffen — geprüft wurde nur einmal beim
///     Start.
///
/// Als Deckel im `builder` liegt die Seite über dem gesamten Navigator: Jeder
/// `push` landet DARUNTER und ist unsichtbar. Gleichzeitig bleibt der Navigator
/// gemountet — das ist wichtig, weil `rootNavigatorKey.currentState` sonst
/// `null` wäre und Gruppen- sowie Beitrags-Deeplinks für Leute mit aktueller
/// Version still verschluckt würden.
///
/// WÄHREND DER PRÜFUNG wird der Launch-Hintergrund über die App gelegt, nicht
/// anstelle. Auch das ist Absicht: nichts blitzt auf, und der Navigator lebt.
///
/// NEUPRÜFUNG bei Rückkehr in den Vordergrund, aber NIEMALS während einer
/// laufenden Fahrt. Jemandem mitten auf der Autobahn die Navigation gegen eine
/// Update-Wand zu tauschen wäre der schlimmere Fehler.
class ForceUpdateGate extends StatefulWidget {
  const ForceUpdateGate({super.key, required this.child});

  final Widget child;

  /// Frühestens nach dieser Zeit wird erneut beim Server nachgefragt.
  static const Duration erneutFruehestensNach = Duration(minutes: 15);

  @override
  State<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends State<ForceUpdateGate>
    with WidgetsBindingObserver {
  bool _erstePruefungLaeuft = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pruefe(erste: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _pruefe({bool erste = false}) async {
    await AppVersionGateService.pruefe();
    if (!mounted) return;
    if (erste) setState(() => _erstePruefungLaeuft = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Nicht während der Fahrt — siehe Klassenkommentar.
    if (CruiseModePage.isFullscreen.value) return;
    final zuletzt = AppVersionGateService.letzteErfolgreichePruefung;
    if (zuletzt != null &&
        DateTime.now().difference(zuletzt) <
            ForceUpdateGate.erneutFruehestensNach) {
      return;
    }
    unawaited(_pruefe());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppVersionGateResult>(
      valueListenable: AppVersionGateService.zustand,
      builder: (context, ergebnis, _) {
        return Stack(
          children: [
            // Bleibt IMMER im Baum, damit der Navigator gemountet ist.
            widget.child,
            if (ergebnis.blockiert)
              UpdateRequiredPage(
                storeUrl: ergebnis.storeUrl,
                nachricht: ergebnis.nachricht,
                installierterBuild: ergebnis.installierterBuild,
                benoetigterBuild: ergebnis.benoetigterBuild,
                onErneutPruefen: _pruefe,
              )
            else if (_erstePruefungLaeuft)
              // Launch-Hintergrundfarbe, damit nichts aufblitzt.
              const ColoredBox(
                color: Color(0xFF0D141E),
                child: SizedBox.expand(),
              ),
          ],
        );
      },
    );
  }
}
