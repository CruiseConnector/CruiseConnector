import 'package:floating/floating.dart';
import 'package:flutter/material.dart';

/// 2026-08-16 (vucko Testfahrt, Aufgabe 1: „Beim App-Wechsel muss ich die
/// Route manuell neu starten"): Umschalter zwischen Vollansicht und dem
/// Bild-im-Bild-Fenster (Android), der den Vollansicht-Baum GEMOUNTET laesst.
///
/// WAS SCHIEFGING: Der `PiPSwitcher` des floating-Pakets tauscht seine
/// Kinder per AnimatedSwitcher aus. Beim App-Verlassen (PiP an) wurde damit
/// der komplette Scaffold — Karte, Panels, Fahrtsteuerung — ABGERISSEN, beim
/// Zurueckkommen neu gebaut. Jeder lokale Widget-Zustand war weg: Die
/// Fahrtsteuerung stand wieder auf „Fahrt starten", obwohl GPS, Zaehler und
/// Route im Seiten-State weiterliefen. Fuer den Fahrer sah es aus wie eine
/// abgebrochene Fahrt.
///
/// JETZT: Beide Ansichten haengen dauerhaft im Baum. Im PiP-Fenster wird die
/// Vollansicht nur `Offstage` gestellt (kein Layout-Paint, Zustand bleibt,
/// Ticker laufen weiter — kein Await auf eine Animation kann so haengen), das
/// kleine Fenster liegt darueber. Zurueck in der App verschwindet das
/// PiP-Kind, die Vollansicht ist unveraendert da.
class PipBaumUmschalter extends StatelessWidget {
  const PipBaumUmschalter({
    super.key,
    required this.vollansicht,
    required this.pipAnsicht,
    this.statusStream,
  });

  final Widget vollansicht;

  /// Wird nur gebaut, waehrend PiP aktiv ist (Builder, damit die reduzierte
  /// Ansicht immer die aktuellen Werte zeigt).
  final WidgetBuilder pipAnsicht;

  /// Nur fuer Tests austauschbar (Standard: `Floating().pipStatusStream`).
  final Stream<PiPStatus>? statusStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PiPStatus>(
      stream: statusStream ?? Floating().pipStatusStream,
      initialData: PiPStatus.disabled,
      builder: (context, snapshot) {
        final imPip = snapshot.data == PiPStatus.enabled;
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(offstage: imPip, child: vollansicht),
            if (imPip) Positioned.fill(child: pipAnsicht(context)),
          ],
        );
      },
    );
  }
}
