import 'package:shared_preferences/shared_preferences.dart';

class CruiseDeepLinks {
  CruiseDeepLinks._();

  static const host = 'cruiseconnector.at';
  static const baseUrl = 'https://$host';

  static Uri postUri(String postId) {
    return Uri.https(host, '/', {'post': postId});
  }

  // 2026-07-03 (vucko Gruppen-Share): Deeplink zum Beitreten/Öffnen einer Gruppe,
  // gespiegelt von postUri. Gleicher Host/Scheme wie Posts → keine
  // Manifest-Änderung nötig.
  static Uri groupUri(String groupId) {
    return Uri.https(host, '/', {'group': groupId});
  }

  /// 2026-06-25 (vucko): Generischer Share-Deeplink fürs externe Teilen einer
  /// Route. Im geteilten Text mitgeschickt → tippt der Empfänger ihn an, öffnet
  /// sich die App (Android App-Link ist im Manifest `autoVerify`); ohne App
  /// landet er auf der Website. (iOS Universal Link braucht zusätzlich die
  /// gehostete apple-app-site-association — reine Infra, kein App-Code.)
  static Uri shareUri({String ref = 'route-share'}) {
    return Uri.https(host, '/', {'ref': ref});
  }

  static String get shareUrl => shareUri().toString();

  // ── Gruppen-Deeplink lesen ────────────────────────────────────────────

  /// 2026-08-23 (vucko, Sprachnachricht: „ueber den Quicklink dann joinen
  /// will, dass ein Fehler kommt"): Gruppen-ID aus einem Link ziehen.
  /// Lag vorher als private Methode in main.dart und war damit nicht
  /// pruefbar. Akzeptiert `?group=<id>`, `?g=<id>`, `/group/<id>` und
  /// `cruiseconnect://group/<id>`.
  static String? gruppenIdAus(Uri uri) {
    final ausAbfrage =
        uri.queryParameters['group'] ?? uri.queryParameters['g'];
    if (ausAbfrage != null && ausAbfrage.trim().isNotEmpty) {
      return ausAbfrage.trim();
    }

    final segmente = uri.pathSegments;
    if (segmente.length >= 2 && segmente[0] == 'group') {
      return segmente[1];
    }

    if (uri.scheme == 'cruiseconnect' &&
        uri.host == 'group' &&
        segmente.isNotEmpty) {
      return segmente.first;
    }

    return null;
  }
}

/// 2026-08-23 (vucko, Sprachnachricht: „wenn er eine Gruppe erstellt hat und
/// er einen anderen einlaedt [...] dass ein Fehler kommt"):
///
/// Ein Einladungslink ist dafuer da, NEUE Leute zu holen. Genau die sind beim
/// Antippen nicht angemeldet. Bisher merkte sich die App nichts: in ganz
/// `lib/` gab es keinen gespeicherten Deep-Link, `main.dart` verwarf ihn mit
/// einem stummen `return;`. Der Link war damit verbrannt, der Eingeladene
/// musste die Gruppe von Hand suchen, und private Gruppen erscheinen in der
/// Entdecken-Liste nie (`getDiscoverGroups` filtert `is_public = true`).
///
/// Deshalb wird der Link hier auf der Platte gemerkt (ueberlebt auch einen
/// Kaltstart) und nach der Anmeldung genau EINMAL eingeloest.
class OffenerEinladungsLink {
  OffenerEinladungsLink._();

  static const _schluesselGruppe = 'offener_einladungslink_gruppe';
  static const _schluesselZeit = 'offener_einladungslink_zeit';

  /// Nach dieser Zeit gilt ein gemerkter Link als verfallen. Sonst wuerde die
  /// App Wochen spaeter unvermittelt eine fremde Gruppe aufblenden.
  static const gueltigkeit = Duration(days: 7);

  static Future<void> merkeGruppe(String gruppenId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_schluesselGruppe, gruppenId);
    await prefs.setString(
      _schluesselZeit,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  /// Liest den gemerkten Link UND loescht ihn im selben Zug, damit er nur
  /// einmal wirkt. Abgelaufene Links werden verworfen.
  static Future<String?> holeUndLoescheGruppe({DateTime? jetzt}) async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_schluesselGruppe);
    final zeitRoh = prefs.getString(_schluesselZeit);
    if (id == null || id.isEmpty) return null;

    await prefs.remove(_schluesselGruppe);
    await prefs.remove(_schluesselZeit);

    final zeit = DateTime.tryParse(zeitRoh ?? '');
    if (zeit != null) {
      final vergangen = (jetzt ?? DateTime.now().toUtc()).difference(zeit);
      if (vergangen > gueltigkeit) return null;
    }
    return id;
  }

  static Future<void> verwerfen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_schluesselGruppe);
    await prefs.remove(_schluesselZeit);
  }
}
