import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;

/// 2026-07-03 (vucko „Standort immer / direkt in Einstellungen"): Bündelt die
/// komplette Standort-Freigabe-Logik an EINER Stelle, damit alle Aufrufer
/// (Vorab-Sheet, Navigations-Start, Gruppen-Hintergrund) sich gleich verhalten.
///
/// Zielverhalten (vom Nutzer gewünscht): Wenn der Standort aktiviert werden
/// muss, kann man gleich „Immer erlauben" wählen — und wenn das Betriebssystem
/// „Immer" NICHT per Dialog vergibt, wird man DIREKT in die App-Einstellungen
/// weitergeleitet, wo „Immer/Always" mit einem Tap gesetzt werden kann.
///
/// Plattform-Realität (warum der Umweg über die Einstellungen nötig ist):
///  - iOS fragt IMMER zuerst „Beim Verwenden" ab. „Immer erlauben" kommt erst
///    bei einer zweiten Anfrage als Hochstufungs-Dialog — und wenn iOS ihn nicht
///    (mehr) zeigt, geht „Immer" nur noch über die Einstellungen.
///  - Android 11+ vergibt Hintergrund-Standort („Immer zulassen") grundsätzlich
///    NICHT per Laufzeit-Dialog, sondern NUR über die App-Einstellungen.
class LocationPermissionHelper {
  const LocationPermissionHelper._();

  /// Darf die App den Standort mindestens im Vordergrund nutzen?
  static bool isUsable(geo.LocationPermission permission) {
    return permission == geo.LocationPermission.always ||
        permission == geo.LocationPermission.whileInUse;
  }

  /// Fragt die Freigabe an und stuft, so weit das OS es per Dialog erlaubt, bis
  /// „Immer erlauben" hoch. Ist „Immer" per Dialog nicht (mehr) erreichbar und
  /// [openSettingsIfNeeded] gesetzt, wird DIREKT die App-Einstellungsseite
  /// geöffnet. Gibt die final ermittelte Freigabe zurück.
  static Future<geo.LocationPermission> requestAlways({
    bool openSettingsIfNeeded = true,
  }) async {
    if (kIsWeb) return geo.LocationPermission.whileInUse;

    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.always) return permission;

    if (permission == geo.LocationPermission.denied) {
      // Erster System-Dialog (iOS: „Beim Verwenden"; Android: Standort-Dialog,
      // je nach Version ggf. schon mit „Immer zulassen").
      permission = await geo.Geolocator.requestPermission();
    }

    // Dauerhaft blockiert → nur noch die Einstellungen helfen.
    if (permission == geo.LocationPermission.deniedForever) {
      if (openSettingsIfNeeded) {
        await geo.Geolocator.openAppSettings();
      }
      return permission;
    }

    if (permission == geo.LocationPermission.whileInUse) {
      // Vordergrund ist da → auf „Immer" hochstufen. iOS zeigt dafür (falls
      // noch nicht abgelehnt) den Hochstufungs-Dialog; Android 11+ liefert
      // sofort denselben Stand zurück → in beiden Fällen danach direkt in die
      // Einstellungen, falls „Immer" noch fehlt.
      final upgraded = await geo.Geolocator.requestPermission();
      if (upgraded == geo.LocationPermission.always) return upgraded;
      if (openSettingsIfNeeded) {
        await geo.Geolocator.openAppSettings();
      }
      return upgraded;
    }

    return permission;
  }

  /// Öffnet direkt die App-Standort-Einstellungen (iOS + Android).
  static Future<bool> openSettings() => geo.Geolocator.openAppSettings();
}
