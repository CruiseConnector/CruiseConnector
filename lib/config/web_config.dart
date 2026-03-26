// Web-Konfiguration: Wird nur auf Flutter Web verwendet
import 'package:flutter/foundation.dart';

class WebConfig {
  /// true = App läuft im Browser
  static bool get isWeb => kIsWeb;

  /// Gibt einen web-kompatiblen Fallback zurück wenn ein Feature nicht
  /// auf Web verfügbar ist (z.B. native GPS via flutter_tts)
  static bool get hasNativeGps => !kIsWeb;
}
