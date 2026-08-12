import 'package:flutter/material.dart';

/// Gibt Speicher frei, sobald die App in den Hintergrund geht.
///
/// 2026-08-12 (vucko): „wenn ich die App wechsle auf eine andere App, die App
/// komplett aufeinmal crashed vom App-Verlauf."
///
/// WAS AM GERÄT GEMESSEN WURDE. `adb shell dumpsys activity exit-info` auf
/// seinem Samsung: fünfmal `reason=3 (LOW_MEMORY)` und fünfmal „OTHER KILLS BY
/// SYSTEM". Die App wird nicht von einem eigenen Fehler zerrissen, sondern von
/// Android aufgeräumt, weil sie im Hintergrund zu viel hält. Danach ist der
/// Prozess tot — und die Fahrt kam als unbestätigte Vorschau zurück.
///
/// WARUM ES DIESE KLASSE BRAUCHT. Der erste Anlauf hängte die Entlastung an
/// `didChangeAppLifecycleState` der Fahransicht. Die Messung danach zeigte:
/// Es passierte nichts, der Verbrauch stieg im Hintergrund sogar von 319 auf
/// 365 MB. Der Grund steht in `home_page.dart`: Der Cruise-Tab wird BEWUSST
/// erst beim ersten Besuch gebaut (die MapLibre-Ansicht darf nicht unsichtbar
/// entstehen, sonst stürzt sie nativ ab). Wer auf der Startseite ist, hat die
/// Fahransicht also gar nicht im Baum — und der Behandler lief nie.
///
/// Deshalb hängt die Wache jetzt am Binding selbst, nicht an einer Seite. Sie
/// wird einmal beim App-Start angemeldet und greift überall.
///
/// WAS FREIGEGEBEN WIRD. Nur der Bildspeicher: Feed-Bilder, Profilbilder,
/// Karten-Symbole. Die lädt die App beim Zurückkommen einfach neu — ein
/// kurzes Nachladen ist der weit kleinere Preis als ein abgeschossener Prozess
/// mitten in der Fahrt. Fahrtdaten, Route und GPS-Strom werden NICHT angefasst.
class AppSpeicherWache with WidgetsBindingObserver {
  AppSpeicherWache._();

  static final AppSpeicherWache instance = AppSpeicherWache._();

  bool _angemeldet = false;

  /// Obergrenze fuer den Bildspeicher.
  ///
  /// Flutter erlaubt standardmaessig 100 MB. Bei einer App, die Android
  /// nachweislich wegen Speichermangel abschiesst, ist das zu grosszuegig:
  /// Feed-Bilder und Profilbilder duerfen den Ausschlag nicht geben. 48 MB
  /// reichen fuer fluessiges Scrollen; was darueber hinaus faellt, wird beim
  /// Zurueckscrollen neu dekodiert — kaum spuerbar.
  static const int _bildspeicherGrenzeBytes = 48 * 1024 * 1024;

  /// Einmal beim App-Start aufrufen.
  void starten() {
    if (_angemeldet) return;
    _angemeldet = true;
    WidgetsBinding.instance.addObserver(this);
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        _bildspeicherGrenzeBytes;
    debugPrint(
      '[Speicher] Wache aktiv, Bildspeicher gedeckelt auf '
      '${_bildspeicherGrenzeBytes ~/ (1024 * 1024)} MB',
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _gibBildspeicherFrei('Hintergrund');
    }
  }

  /// Androids letzte Warnung, bevor der Prozess abgeschossen wird.
  ///
  /// Dafür gab es bisher überhaupt keinen Behandler — die Warnung verpuffte,
  /// und kurz darauf war die App weg.
  @override
  void didHaveMemoryPressure() {
    _gibBildspeicherFrei('Speicherdruck');
  }

  void _gibBildspeicherFrei(String anlass) {
    try {
      final cache = PaintingBinding.instance.imageCache;
      final vorher = cache.currentSizeBytes;
      cache
        ..clear()
        ..clearLiveImages();
      debugPrint(
        '[Speicher] $anlass: Bildspeicher freigegeben '
        '(${(vorher / 1024 / 1024).toStringAsFixed(1)} MB)',
      );
    } catch (e) {
      debugPrint('[Speicher] Freigeben fehlgeschlagen: $e');
    }
  }
}
