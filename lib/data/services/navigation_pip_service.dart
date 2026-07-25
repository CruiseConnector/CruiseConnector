import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:floating/floating.dart';

/// 2026-07-25 (vucko „Mini-Bildschirm während man andere Apps benutzt"):
/// Android-Picture-in-Picture für die laufende Navigation.
///
/// Verhalten: Sobald eine Fahrt läuft, wird PiP „scharf gestellt"
/// ([OnLeavePiP]) — verlässt der Nutzer die App (Home-Geste/-Taste), schrumpft
/// die Navigation automatisch in ein kleines Systemfenster über anderen Apps,
/// wie bei Google Maps. Endet die Fahrt, wird das wieder abgeschaltet.
///
/// NUR ANDROID. iOS hat dafür bewusst KEIN Gegenstück: Apples PiP
/// (AVPictureInPictureController) ist für echte Video-Wiedergabe gebaut; es
/// für Karteninhalte zweckzuentfremden ist ein App-Review-Risiko für eine
/// bereits veröffentlichte App — auch Google Maps und Waze bieten das auf iOS
/// nicht an. Auf iOS übernimmt die bereits vorhandene Live Activity
/// (Sperrbildschirm + Dynamic Island) diese Aufgabe.
class NavigationPipService {
  NavigationPipService._();
  static final NavigationPipService instance = NavigationPipService._();

  final Floating _floating = Floating();
  bool _armed = false;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  /// true, sobald PiP scharf gestellt ist (nur für Debug/Anzeige).
  bool get isArmed => _armed;

  /// Fahrt startet → PiP für „App verlassen" scharf stellen.
  /// Best effort: schlägt das fehl (altes Gerät, PiP systemweit deaktiviert),
  /// fährt die Navigation ganz normal weiter.
  Future<void> arm() async {
    if (!_supported || _armed) return;
    try {
      if (!await _floating.isPipAvailable) return;
      // 16:9 quer — passt zum Manöver-Banner-Layout (Pfeil + Distanz + ETA)
      // und liegt sicher innerhalb der von Android erlaubten Seitenverhältnisse.
      await _floating.enable(const OnLeavePiP(aspectRatio: Rational.landscape()));
      _armed = true;
    } catch (e) {
      debugPrint('[NavigationPip] arm fehlgeschlagen: $e');
    }
  }

  /// Fahrt beendet/pausiert → kein automatisches PiP mehr.
  Future<void> disarm() async {
    if (!_supported || !_armed) return;
    _armed = false;
    try {
      await _floating.cancelOnLeavePiP();
    } catch (e) {
      debugPrint('[NavigationPip] disarm fehlgeschlagen: $e');
    }
  }
}
