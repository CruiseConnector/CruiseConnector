import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Kontogebundene Schluessel fuer die SharedPreferences.
///
/// 2026-08-24 (Aufgabe 4.6, Nebenfund 1). Vucko: „die Anpassung darf nicht
/// verloren gehen."
///
/// GEMESSEN: `home_dashboard_layout_v1`, `home_snapshot_v1`,
/// `home_badge_hunt_id_v1` und `app_tutorial_v2_completed` trugen KEINE
/// Nutzerkennung. Auf einem Handy mit zwei Konten erbte das zweite Konto die
/// Kachel-Anordnung, den Startseiten-Schnappschuss (Name, Avatar, XP,
/// Kilometer des ersten Kontos) und den Tutorial-Status des ersten. Das
/// zweite Konto sah beim allerersten Start fremde Zahlen und bekam gar kein
/// Onboarding.
///
/// JETZT: Jeder dieser Werte liegt unter `basis::<userId>`. Der alte,
/// kontolose Wert wird EINMAL uebernommen, damit heute niemandem seine
/// Anordnung verlorengeht — aber nur von genau EINEM Konto. Welches es war,
/// steht in der Uebernahme-Marke; jedes weitere Konto startet sauber mit den
/// Standardwerten.
///
/// ENTSCHEIDUNG (Vucko schlaeft, keine Rueckfrage moeglich): Der alte Wert
/// wird NICHT geloescht. Er kostet ein paar Byte, und wenn ein Nutzer auf
/// eine aeltere App-Version zurueckfaellt, findet die ihre Anordnung noch
/// vor. Die Uebernahme-Marke verhindert trotzdem, dass ein zweites Konto ihn
/// jemals sieht.
class NutzerPrefsSchluessel {
  NutzerPrefsSchluessel._();

  /// Ersetzbar, damit Tests ohne Supabase auskommen.
  @visibleForTesting
  static String? Function()? nutzerIdFuerTests;

  /// Die Kennung des angemeldeten Kontos, oder `null`. Wirft nie: ist
  /// Supabase noch nicht hochgefahren (Tests, sehr frueher App-Start), gilt
  /// „kein Konto" und es bleibt beim alten, kontolosen Schluessel.
  static String? aktuelleNutzerId() {
    final test = nutzerIdFuerTests;
    if (test != null) return test();
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Der kontogebundene Schluessel zu [basis].
  static String fuer(String basis, {String? nutzerId}) {
    final id = nutzerId ?? aktuelleNutzerId();
    if (id == null || id.isEmpty) return basis;
    return '$basis::$id';
  }

  /// Merkt sich, welches Konto den alten kontolosen Wert bekommen hat.
  static String uebernahmeMarke(String basis) => '${basis}__uebernommen_von';

  /// Holt den alten kontolosen Wert genau einmal ins Konto.
  ///
  /// Passiert nichts, wenn: kein Konto angemeldet ist, das Konto schon einen
  /// eigenen Wert hat, es gar keinen alten Wert gibt, oder der alte Wert
  /// bereits einem ANDEREN Konto zugeschlagen wurde.
  static Future<void> uebernimmAltbestand(
    SharedPreferences prefs,
    String basis, {
    String? nutzerId,
  }) async {
    final id = nutzerId ?? aktuelleNutzerId();
    if (id == null || id.isEmpty) return;
    final ziel = fuer(basis, nutzerId: id);
    if (ziel == basis) return;
    if (prefs.containsKey(ziel)) return;
    if (!prefs.containsKey(basis)) return;

    final marke = uebernahmeMarke(basis);
    final besitzer = prefs.getString(marke);
    if (besitzer != null && besitzer != id) return;

    final wert = prefs.get(basis);
    if (wert is String) {
      await prefs.setString(ziel, wert);
    } else if (wert is bool) {
      await prefs.setBool(ziel, wert);
    } else if (wert is int) {
      await prefs.setInt(ziel, wert);
    } else if (wert is double) {
      await prefs.setDouble(ziel, wert);
    } else if (wert is List<String>) {
      await prefs.setStringList(ziel, wert);
    } else {
      return;
    }
    await prefs.setString(marke, id);
  }

  /// Kurzform: Altbestand uebernehmen und den fertigen Schluessel liefern.
  static Future<String> vorbereitet(
    SharedPreferences prefs,
    String basis, {
    String? nutzerId,
  }) async {
    await uebernimmAltbestand(prefs, basis, nutzerId: nutzerId);
    return fuer(basis, nutzerId: nutzerId);
  }
}
