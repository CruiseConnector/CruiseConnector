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

  // ── Community-Deeplink ────────────────────────────────────────────────

  /// 2026-08-31 (Auftrag Vucko, Sprachnachricht: „dass man die community auch
  /// auf anderen Seiten verlinken kann wie Instagram Snapchat und so weiter
  /// mit deinem Link").
  ///
  /// Der Link traegt den EINLADUNGSCODE, nicht die Kennung der Community.
  /// Drei Gruende, alle am 31.08.2026 an der Datenbank nachgesehen:
  ///
  ///  1. Eine PRIVATE Community ist ueber ihre Kennung fuer Aussenstehende
  ///     gar nicht lesbar. Die Zeilenregel
  ///     `communities_visible_public_or_member` gibt nur oeffentliche Zeilen
  ///     und die eigenen frei. Ein Link mit Kennung landete dort auf einer
  ///     leeren Vorschau — also genau in dem Fehlerbild, das der Gruppen-Link
  ///     am 23.08. hatte.
  ///  2. `find_community_by_code` ist SECURITY DEFINER und darf sogar von
  ///     `anon` ausgefuehrt werden. Damit kann die App die Vorschau zeigen,
  ///     ohne dass der Betrachter Mitglied ist, und spaeter die Landeseite im
  ///     Netz dieselbe Vorschau bauen.
  ///  3. `join_community_with_code_v2` setzt Vuckos bindende Entscheidung vom
  ///     23.08. um: oeffentlich heisst sofort drin, privat heisst Anfrage beim
  ///     Admin. Ein Beitritt ueber die blosse Kennung kennt diesen
  ///     Unterschied nicht.
  ///
  /// Warum ein Pfad und keine Abfrage: `https://cruiseconnector.at/?x=y`
  /// antwortet heute mit 302 auf `/home` und wirft die Abfrage dabei weg
  /// (gemessen am 31.08.2026). Ein Pfad ueberlebt das.
  ///
  /// ACHTUNG, noch nicht fertig: Solange
  /// `/.well-known/apple-app-site-association` und
  /// `/.well-known/assetlinks.json` fehlen (beide gaben am 31.08.2026 eine
  /// 404), oeffnet dieser Link NICHT die App, sondern den Browser. Das ist
  /// Arbeit am Webserver, nicht in der App.
  static Uri communityUri(String einladungsCode) {
    return Uri.https(host, '/c/${einladungsCode.trim()}');
  }

  static String communityUrl(String einladungsCode) =>
      communityUri(einladungsCode).toString();

  /// Zieht den Einladungscode aus einem Link.
  ///
  /// Akzeptiert bewusst mehr Formen, als [communityUri] baut: geteilte Links
  /// leben lange, und ein Link, den irgendjemand von Hand getippt hat, soll
  /// genauso ankommen. Erlaubt sind `/c/<code>`, `/community/<code>`,
  /// `?community=<code>`, `?cm=<code>` und `cruiseconnect://community/<code>`.
  ///
  /// `?code=` ist ABSICHTLICH nicht dabei: `_isAuthDeepLink` in main.dart
  /// erkennt einen Anmeldelink genau an diesem Namen. Ein Community-Link mit
  /// `?code=` waere dort abgefangen worden, bevor er hier ankommt.
  ///
  /// Geprueft wird hier NICHT, ob der Code gueltig ist. Das macht
  /// `CommunityChatService.normalizeInviteCode`; diese Schicht kennt die
  /// Datenschicht nicht.
  static String? communityCodeAus(Uri uri) {
    final ausAbfrage =
        uri.queryParameters['community'] ?? uri.queryParameters['cm'];
    if (ausAbfrage != null && ausAbfrage.trim().isNotEmpty) {
      return ausAbfrage.trim();
    }

    final segmente = uri.pathSegments;
    if (segmente.length >= 2 &&
        (segmente[0] == 'c' || segmente[0] == 'community')) {
      final wert = segmente[1].trim();
      if (wert.isNotEmpty) return wert;
    }

    if (uri.scheme == 'cruiseconnect' &&
        (uri.host == 'community' || uri.host == 'c') &&
        segmente.isNotEmpty) {
      final wert = segmente.first.trim();
      if (wert.isNotEmpty) return wert;
    }

    return null;
  }

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

/// 2026-08-31 (Auftrag Vucko: „wenn man die App noch nicht hat, dass man in
/// den App Store [...] und dass wenn man die App hat, dass man direkt zur App
/// weitergeleitet wird und dann in den Vorschau screen").
///
/// Dieselbe Falle wie bei den Gruppen am 23.08., nur eine Ebene weiter: Der
/// Community-Link ist DAFUER da, Leute zu holen, die die App gerade erst
/// installiert haben. Genau die sind beim ersten Antippen nicht angemeldet.
/// Ohne Gedaechtnis waere der Link nach dem allerersten Start verbrannt, und
/// bei einer PRIVATEN Community fuehrt kein zweiter Weg hinein: sie taucht in
/// der Entdecken-Liste nie auf (`getDiscoverCommunities` filtert auf
/// oeffentlich).
///
/// Bewusst eine EIGENE Ablage neben [OffenerEinladungsLink] und nicht
/// dieselbe: Sonst wuerde ein Gruppen-Link einen gemerkten Community-Link
/// ueberschreiben, ohne dass es irgendwo auffaellt.
class OffenerCommunityLink {
  OffenerCommunityLink._();

  static const _schluesselCode = 'offener_community_link_code';
  static const _schluesselZeit = 'offener_community_link_zeit';

  /// Gleiche Frist wie beim Gruppen-Link. Ein Link, den jemand vor Wochen
  /// angetippt hat, darf nicht unvermittelt eine fremde Community aufblenden.
  static const gueltigkeit = Duration(days: 7);

  static Future<void> merkeCode(String einladungsCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_schluesselCode, einladungsCode);
    await prefs.setString(
      _schluesselZeit,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  /// Liest den gemerkten Code UND loescht ihn im selben Zug, damit er nur
  /// einmal wirkt. Abgelaufene Codes werden verworfen.
  static Future<String?> holeUndLoescheCode({DateTime? jetzt}) async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_schluesselCode);
    final zeitRoh = prefs.getString(_schluesselZeit);
    if (code == null || code.isEmpty) return null;

    await prefs.remove(_schluesselCode);
    await prefs.remove(_schluesselZeit);

    final zeit = DateTime.tryParse(zeitRoh ?? '');
    if (zeit != null) {
      final vergangen = (jetzt ?? DateTime.now().toUtc()).difference(zeit);
      if (vergangen > gueltigkeit) return null;
    }
    return code;
  }

  static Future<void> verwerfen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_schluesselCode);
    await prefs.remove(_schluesselZeit);
  }
}
