import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/core/input_limits.dart';

class SocialServiceException implements Exception {
  const SocialServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 2026-08-23 (vucko): Wie steht es um meinen Zugang zu einer Gruppe?
///
/// Vier Ausgaenge statt des alten ja/nein, weil „ich sehe die Gruppe nicht"
/// und „die Gruppe gibt es nicht mehr" zwei verschiedene Dinge sind. Genau
/// diese Verwechslung hat den eingeladenen Fahrer am 21.08. dreimal in die
/// Meldung „Diese Gruppe ist nicht mehr verfuegbar." laufen lassen.
enum GruppenZugang {
  /// Ich bin Gastgeber oder schon Mitglied. Direkt in die Lobby.
  mitglied,

  /// Ich darf beitreten, bin aber noch nicht drin. Einladung zeigen.
  einladung,

  /// Geloescht, beendet, oder die Fahrt laeuft bereits ohne mich.
  nichtVerfuegbar,

  /// Wir wissen es nicht (Netz/Server). Ehrlich sagen und Wiederholen anbieten.
  netzfehler,

  /// Kein Konto angemeldet. Link merken, nach der Anmeldung nachholen.
  nichtAngemeldet,
}

/// Ergebnis von [SocialService.pruefeGruppenZugang] samt dem, was wir von der
/// Gruppe lesen durften (kann leer sein, wenn die Lesepolitik sie versteckt).
class GruppenZugangsBescheid {
  const GruppenZugangsBescheid(this.zugang, {this.gruppe, this.gruppenName});

  final GruppenZugang zugang;
  final Map<String, dynamic>? gruppe;
  final String? gruppenName;

  String? get gastgeberName {
    final profil = gruppe?['profiles'] as Map<String, dynamic>?;
    final name = (profil?['username'] as String?)?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  int get mitgliederAnzahl =>
      ((gruppe?['group_members'] as List?) ?? const []).length;

  bool get istOeffentlich => gruppe?['is_public'] == true;
}

/// Strukturiertes Ergebnis des server-seitigen `set_username`-RPC.
class UsernameSetResult {
  const UsernameSetResult({
    required this.ok,
    this.username,
    this.error,
    this.daysRemaining,
  });

  final bool ok;
  final String? username;

  /// null bei Erfolg; sonst {invalid_format, reserved, taken, too_soon,
  /// not_authenticated, unknown}.
  final String? error;
  final int? daysRemaining;
}

/// Geworfen, wenn der @-Name nicht geändert werden konnte. [reason] ist der
/// RPC-Fehlercode; [daysRemaining] ist bei `too_soon` die Restzeit in Tagen.
class UsernameChangeException implements Exception {
  const UsernameChangeException(this.reason, {this.daysRemaining});

  final String reason;
  final int? daysRemaining;

  String get message {
    switch (reason) {
      case 'taken':
        return 'Dieser Name ist bereits vergeben.';
      case 'reserved':
        return 'Dieser Name ist reserviert.';
      case 'invalid_format':
        return 'Der Name braucht 3 bis 20 Zeichen, nur Buchstaben, Zahlen '
            'und _ (kein __, und nicht mit _ beginnen oder enden).';
      case 'too_soon':
        final d = daysRemaining ?? 30;
        return 'Du kannst deinen Namen erst in $d '
            '${d == 1 ? 'Tag' : 'Tagen'} wieder ändern.';
      case 'not_authenticated':
        return 'Bitte melde dich an.';
      default:
        return 'Der Name konnte nicht geändert werden.';
    }
  }

  @override
  String toString() => message;
}

class DuplicateSharedRoutePostException implements Exception {
  const DuplicateSharedRoutePostException();

  String get message => SocialService.duplicateSharedRoutePostMessage;

  @override
  String toString() => message;
}

// 2026-07-03 (vucko Gruppen-Share): Dubletten-Schutz gespiegelt vom Routen-Share
// — eine Gruppe soll pro User nur einmal im Feed landen (Unique-Index
// posts_user_shared_group_unique_idx).
class DuplicateSharedGroupPostException implements Exception {
  const DuplicateSharedGroupPostException();

  String get message => SocialService.duplicateSharedGroupPostMessage;

  @override
  String toString() => message;
}

/// 2026-08-24 — Auftrag Vucko: „wenn ihn schon 17 Leute benutzt haben, dann
/// soll das moeglichst da noch drunter stehen".
///
/// Die zwei Zahlen ueber einem Hashtag. Sie sind BEWUSST getrennt von der
/// geladenen Trefferliste: die Liste ist gedeckelt (die Seite holt 200
/// Beitraege), die Kopfzahlen sind es nicht. Wer bei 300 Beitraegen die
/// Laenge der Liste anzeigt, luegt.
class HashtagKennzahlen {
  const HashtagKennzahlen({required this.beitraege, required this.personen});

  /// Anzahl oeffentlicher, sichtbarer Beitraege mit diesem Hashtag.
  final int beitraege;

  /// Anzahl VERSCHIEDENER Verfasser. Das ist die Zahl, die Vucko meint.
  final int personen;
}

/// 2026-08-24 (Vucko: „bei der community page hat cozy mal was gepostet aber
/// ich sehe es nicht in meinem feed obwohl ich ihm folge.")
///
/// Wer sieht welchen Beitrag? Die Antwort steht ab jetzt AN EINER STELLE,
/// weil sie vorher in jeder Abfrage neu und jedes Mal anders erfunden wurde.
///
/// Die Sichtbarkeitsstufe heisst in der App schlicht „Follower"
/// (create_post_page.dart). Wer sie waehlt, meint SEINE FOLLOWER — nicht die
/// Teilmenge davon, der er selbst auch folgt. Der Feed holte solche Beitraege
/// aber nur von Leuten, die ZURUECKFOLGEN („mutual"). Gemessen am 24.08.:
/// Vucko folgt cozy, cozy folgt nicht zurueck — cozys zwei Beitraege vom
/// 21.08. blieben deshalb unsichtbar. Kein Datenfehler, ein Regelfehler.
///
/// Der alte Kommentar an dieser Stelle begruendete die Mutual-Bedingung mit
/// „sonst leakt Privates an einseitige Follower". Das ist verkehrt herum
/// gedacht: ein einseitiger Follower ist genau das Publikum, fuer das
/// „Follower" gemacht ist. Wer nur gegenseitige Kontakte erreichen will,
/// braucht dafuer eine EIGENE, so beschriftete Stufe — nicht eine stille
/// Verschaerfung dieser hier.
///
/// Wer das zurueckdreht, aendert bitte zuerst die Beschriftung in
/// `create_post_page.dart`. Solange dort „Follower" steht, gilt diese Regel.
class FeedSichtbarkeit {
  /// Stufen, die ich von jemandem sehen darf, DEM ICH FOLGE.
  static const List<String> stufenVonGefolgten = <String>[
    'public',
    'followers',
  ];

  /// Stufen, die ich von jemandem sehen darf, dem ich NICHT folge.
  /// (Im Feed steht ohnehin niemand, dem ich nicht folge — die Liste gilt
  /// fuer fremde Profile und „Entdecken".)
  static const List<String> stufenVonFremden = <String>['public'];

  static List<String> stufenFuerVerfasser({required bool folgeIchIhm}) =>
      folgeIchIhm ? stufenVonGefolgten : stufenVonFremden;

  /// Gehoert der Beitrag in den Feed von [betrachterId]?
  ///
  /// Doppelter Boden: die Abfragen filtern bereits serverseitig, diese
  /// Pruefung laeuft trotzdem noch einmal ueber das Ergebnis. Sie ist die
  /// Stelle, die der Test festnagelt.
  static bool imFeedSichtbar({
    required String betrachterId,
    required String verfasserId,
    required String? sichtbarkeit,
    required Set<String> folgeIch,
    Set<String> blockiert = const <String>{},
    bool istAusgeblendet = false,
  }) {
    if (istAusgeblendet) return false;
    if (blockiert.contains(verfasserId)) return false;
    // Eigene Beitraege sieht man immer, egal auf welche Stufe gestellt.
    if (verfasserId == betrachterId) return true;
    if (!folgeIch.contains(verfasserId)) return false;
    return stufenVonGefolgten.contains(sichtbarkeit ?? 'public');
  }

  /// Gehoert der Beitrag auf das Profil, das [betrachterId] gerade ansieht?
  ///
  /// Dieselbe Regel wie im Feed, nur ohne die Bedingung „steht im Feed":
  /// oeffentliche Beitraege sieht hier auch, wer nicht folgt.
  static bool aufProfilSichtbar({
    required String? betrachterId,
    required String verfasserId,
    required String? sichtbarkeit,
    required bool folgeIchIhm,
    bool istAusgeblendet = false,
  }) {
    if (betrachterId != null && betrachterId == verfasserId) return true;
    if (istAusgeblendet) return false;
    return stufenFuerVerfasser(
      folgeIchIhm: folgeIchIhm,
    ).contains(sichtbarkeit ?? 'public');
  }
}

/// Service für soziale Features: Posts, Follows, Gruppen, Notifications.
class SocialService {
  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _userId => _db.auth.currentUser?.id;

  /// 2026-08-23 (Auftrag Vucko): Bucket für Community-Bilder. Angelegt in
  /// der Migration 20260823123000, öffentlich lesbar, 5 MiB, jpeg/png/webp.
  /// Der Ordner darin ist die Community-Kennung, nicht die Nutzer-Kennung.
  static const String communityImagesBucket = 'community_images';

  static const String duplicateSharedRoutePostMessage =
      'Du hast diese Strecke bereits gepostet. Lösche zuerst den alten Post, '
      'danach kannst du die Strecke erneut posten.';

  // 2026-07-03 (vucko Gruppen-Share): Text gespiegelt vom Routen-Share.
  static const String duplicateSharedGroupPostMessage =
      'Du hast diese Gruppe bereits geteilt. Lösche zuerst den alten Post, '
      'danach kannst du die Gruppe erneut teilen.';

  static const String _profileSelect =
      'id, username, created_at, level, total_km, total_routes, '
      'badges, badge_showcase, bio_title, bio, avatar_url, banner_url, link, is_private, '
      'username_changed_at, '
      'car_brand, car_name, car_country_code, car_top_speed, car_engine_size, '
      'car_displacement, car_cylinders, car_horsepower, car_year, '
      'car_first_reg, car_mileage, car_image_url';

  static const String _legacyProfileSelect =
      'id, username, created_at, level, total_km, total_routes, '
      'badges, bio, avatar_url, banner_url, link, is_private, '
      'username_changed_at, '
      'car_brand, car_name, car_top_speed, car_engine_size, '
      'car_displacement, car_cylinders, car_horsepower, car_year, '
      'car_first_reg, car_mileage, car_image_url';

  static String publicDisplayName(
    Map<String, dynamic>? profile, {
    String? fallbackUserId,
  }) {
    final username = (profile?['username'] as String?)?.trim();
    if (username != null && username.isNotEmpty) return username;
    final shortId = _shortUserId(fallbackUserId);
    return shortId == null ? 'User' : 'Cruiser $shortId';
  }

  static String publicHandle(
    Map<String, dynamic>? profile, {
    String? fallbackUserId,
  }) {
    final username = (profile?['username'] as String?)?.trim();
    if (username != null && username.isNotEmpty) {
      // 2026-08-25 (Auftrag Vucko: Umlaute im Benutzernamen): Der Schnitt
      // haelt Umlaute drin. Vorher machte `[^a-z0-9]` aus „müller" ein
      // „m_ller" — der Name waere ueberall dort verstuemmelt worden, wo ein
      // Handle steht (Feed, Profil, Glocke, Community-Karte). Angezeigt wird,
      // was der Nutzer getippt hat; der Schnitt greift nur noch bei
      // Altbestaenden, die gar kein gueltiger Benutzername sind („Max Power").
      final slug = username
          .toLowerCase()
          .replaceAll(RegExp('[^a-z0-9äöüß]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      return '@${slug.isEmpty ? 'user' : slug}';
    }
    final shortId = _shortUserId(fallbackUserId);
    return shortId == null ? '@user' : '@user_$shortId';
  }

  static String? _shortUserId(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    final sanitized = userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (sanitized.isEmpty) return null;
    return sanitized
        .substring(0, sanitized.length >= 6 ? 6 : sanitized.length)
        .toLowerCase();
  }

  // ── Benutzernamen und Erwaehnungen ───────────────────────────────────
  //
  // 2026-08-25 — Auftrag Vucko: „schau auch noch das man beim benutzernamen
  // aeoeue verwenden kann das ist bis jetzt nicht gegangen".
  //
  // Die Umlaute zuzulassen ist ein Zweizeiler. Das eigentliche Problem sitzt
  // eine Ebene tiefer: sobald „müller" moeglich ist, ist er von „mueller" in
  // einer Liste kaum zu unterscheiden — und wer eine Nachricht von „@müller"
  // bekommt, haelt sie fuer die von „@mueller". Deshalb steht hier neben dem
  // Zeichensatz auch die FALTUNG, mit der verglichen wird.

  /// Zeichensatz eines Benutzernamens — und damit auch der einer Erwaehnung.
  ///
  /// Neu dazu gekommen sind AUSSCHLIESSLICH die deutschen Umlaute und das
  /// scharfe S. Bewusst NICHT `\p{L}` wie beim Hashtag: das kyrillische „а"
  /// sieht aus wie das lateinische „a", damit liesse sich jeder Name exakt
  /// nachbauen. Genau deshalb lassen Instagram und X nur ASCII zu. Bei einem
  /// Hashtag ist das egal — der gehoert niemandem. Bei einem Namen nicht.
  static const String usernameCharClass = 'A-Za-z0-9_ÄÖÜäöüß';

  /// Erkennt `@username`-Tokens in freiem Text. EINZIGE Quelle — die Anzeige
  /// in `mentions.dart` benutzt genau dieses Objekt, keine Kopie.
  ///
  /// Frueher stand hier zusaetzlich ein Punkt: `@([A-Za-z0-9_\.]+)`. Der war
  /// nie begruendet (er kam mit dem Muster im selben Commit ohne ein Wort
  /// dazu) und er ist nicht erfuellbar: `profiles_username_format` laesst in
  /// der Datenbank nur `[A-Za-z0-9_]` zu, ein Punkt kann in keinem
  /// Benutzernamen stehen. Schaden hat er trotzdem angerichtet — „Danke
  /// @vucko." am Satzende ergab hier das Token „vucko.", das zu keinem
  /// Profil passt. Die Anzeige verlinkte „@vucko" (ihr Muster kannte den
  /// Punkt nicht), die Benachrichtigung ging ins Leere. Ein Fehler, den
  /// niemand sieht: der Erwaehnte erfaehrt einfach nichts.
  ///
  /// Satzzeichen gehoeren nicht zum Namen und stehen deshalb in keiner der
  /// Klassen: „@müller." „@müller," „@müller?" enden alle am Namen.
  static final RegExp usernameMentionPattern = RegExp(
    '@([$usernameCharClass]+)',
  );

  /// Ein vollstaendiger Benutzername, ohne `@`.
  static final RegExp usernameFullPattern = RegExp('^[$usernameCharClass]+\$');

  /// Was schon getippt ist, waehrend die Vorschlagsliste laeuft (darf leer
  /// sein). Damit die Vorschlaege beim ersten Umlaut nicht abreissen.
  static final RegExp usernamePrefixPattern = RegExp(
    '^[$usernameCharClass]*\$',
  );

  /// Die Vergleichsform eines Benutzernamens: klein geschrieben, ae/oe/ue/ss
  /// ausgeschrieben, Akzente entfernt.
  ///
  /// ZEICHENGLEICH MIT `public.hashtag_schluessel(text)` aus Migration
  /// 20260824102000. Das ist Absicht: fuer genau dieses Problem — „#Kurven-
  /// koenig" und „#kurvenkönig" sind derselbe Hashtag — gibt es die Faltung
  /// im Haus schon. Ein zweites, leicht anderes Verfahren waere die Sorte
  /// Fehler, die uns die Laender-Klassifikation gekostet hat.
  ///
  /// Gefaltet wird NUR zum Vergleichen. Angezeigt wird immer die
  /// Schreibweise, die der Nutzer getippt hat.
  static String usernameKey(String name) {
    // Reihenfolge wie in der Migration: erst lower, dann die ausgeschriebenen
    // Ersetzungen, dann die Akzent-Tabelle.
    var wert = name.trim().toLowerCase();
    const ersetzungen = <String, String>{
      'ä': 'ae',
      'ö': 'oe',
      'ü': 'ue',
      'ß': 'ss',
      'æ': 'ae',
      'ø': 'oe',
      'å': 'aa',
      'œ': 'oe',
    };
    ersetzungen.forEach((von, nach) => wert = wert.replaceAll(von, nach));
    const akzente = 'áàâãāăçćčéèêëēėęíìîïīıñńóòôõōšśúùûūýÿžźż';
    const ersatz = 'aaaaaaccceeeeeeeiiiiiinnooooossuuuuyyzzz';
    final gefaltet = StringBuffer();
    for (final zeichen in wert.split('')) {
      final stelle = akzente.indexOf(zeichen);
      gefaltet.write(stelle < 0 ? zeichen : ersatz[stelle]);
    }
    return gefaltet.toString();
  }

  /// Alle Schreibweisen, die auf denselben Schluessel fallen: „mueller" und
  /// „müller", „strasse" und „straße".
  ///
  /// Gebraucht wird das beim NACHSCHLAGEN. Der Client kann die Datenbank
  /// nicht falten lassen — `hashtag_schluessel` ist fuer `authenticated`
  /// bewusst gesperrt, und eine Schluesselspalte am Benutzernamen gibt es
  /// noch nicht. Also fragt er nach allen Schreibweisen und prueft die
  /// Antwort selbst gegen [usernameKey]. Jede erzeugte Variante hat
  /// konstruktionsbedingt denselben Schluessel — es kann also nie der
  /// falsche Mensch herauskommen.
  static List<String> usernameSpellings(String name, {int max = 16}) {
    final start = name.trim();
    if (start.isEmpty) return const <String>[];
    const paare = <String, String>{
      'ä': 'ae',
      'ö': 'oe',
      'ü': 'ue',
      'ß': 'ss',
    };
    final gefunden = <String>{start};
    final offen = <String>[start];
    while (offen.isNotEmpty && gefunden.length < max) {
      final wort = offen.removeAt(0);
      final klein = wort.toLowerCase();
      for (final paar in paare.entries) {
        for (final richtung in <List<String>>[
          <String>[paar.key, paar.value],
          <String>[paar.value, paar.key],
        ]) {
          final von = richtung[0];
          final nach = richtung[1];
          var stelle = klein.indexOf(von);
          while (stelle >= 0 && gefunden.length < max) {
            final kandidat = wort.replaceRange(
              stelle,
              stelle + von.length,
              nach,
            );
            if (gefunden.add(kandidat)) offen.add(kandidat);
            stelle = klein.indexOf(von, stelle + 1);
          }
        }
      }
    }
    return gefunden.toList();
  }

  static Set<String> _extractMentions(String text) => usernameMentionPattern
      .allMatches(text)
      .map((m) => m.group(1)!)
      .where((name) => name.isNotEmpty)
      .toSet();

  static Future<void> _hydratePostReactionState(
    List<Map<String, dynamic>> posts,
  ) async {
    final uid = _userId;
    final ids = posts
        .map((post) => post['id'])
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    try {
      final results = await Future.wait([
        _db
            .from('post_likes')
            .select('post_id, user_id')
            .inFilter('post_id', ids),
        _db.from('reposts').select('post_id, user_id').inFilter('post_id', ids),
      ]);

      final likeCounts = <String, int>{};
      final repostCounts = <String, int>{};
      final likedByMe = <String>{};
      final repostedByMe = <String>{};

      for (final row in results[0] as List) {
        final map = row as Map;
        final postId = map['post_id'] as String?;
        if (postId == null) continue;
        likeCounts[postId] = (likeCounts[postId] ?? 0) + 1;
        if (uid != null && map['user_id'] == uid) likedByMe.add(postId);
      }

      for (final row in results[1] as List) {
        final map = row as Map;
        final postId = map['post_id'] as String?;
        if (postId == null) continue;
        repostCounts[postId] = (repostCounts[postId] ?? 0) + 1;
        if (uid != null && map['user_id'] == uid) repostedByMe.add(postId);
      }

      for (final post in posts) {
        final postId = post['id'] as String?;
        if (postId == null) continue;
        post['likes_count'] = likeCounts[postId] ?? 0;
        post['reposts_count'] = repostCounts[postId] ?? 0;
        post['is_liked_by_me'] = likedByMe.contains(postId);
        post['is_reposted_by_me'] = repostedByMe.contains(postId);
      }
    } catch (e) {
      debugPrint(
        '[SocialService] Reaction-State konnte nicht geladen werden: $e',
      );
    }
  }

  static ({bool isActive, int count}) _reactionToggleResult(dynamic raw) {
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final isActive =
        map['is_active'] == true || map['is_active']?.toString() == 'true';
    final count = (map['count'] as num?)?.toInt() ?? 0;
    return (isActive: isActive, count: count);
  }

  static bool isDuplicateSharedRoutePostError(Object error) {
    if (error is DuplicateSharedRoutePostException) return true;
    if (error is PostgrestException) {
      final text = '${error.message} ${error.details ?? ''}'.toLowerCase();
      return error.code == '23505' &&
          (text.contains('posts_user_shared_route_unique_idx') ||
              text.contains('shared_route_id'));
    }
    return false;
  }

  // 2026-07-03 (vucko Gruppen-Share): gespiegelt vom Routen-Share — fängt den
  // Unique-Index posts_user_shared_group_unique_idx ab.
  static bool isDuplicateSharedGroupPostError(Object error) {
    if (error is DuplicateSharedGroupPostException) return true;
    if (error is PostgrestException) {
      final text = '${error.message} ${error.details ?? ''}'.toLowerCase();
      return error.code == '23505' &&
          (text.contains('posts_user_shared_group_unique_idx') ||
              text.contains('shared_group_id'));
    }
    return false;
  }

  static bool isDuplicateGroupMemberError(Object error) {
    if (error is! PostgrestException) return false;
    final text = '${error.message} ${error.details ?? ''}'.toLowerCase();
    return error.code == '23505' &&
        (text.contains('group_members_group_id_user_id_key') ||
            text.contains('group_id, user_id') ||
            text.contains('group_members'));
  }

  static Future<int> _countPostReactions(String table, String postId) async {
    final rows = await _db.from(table).select('id').eq('post_id', postId);
    return (rows as List).length;
  }

  static Future<void> _sendPostReactionNotification({
    required String postId,
    required String type,
  }) async {
    // 2026-07-10 (vucko Doppel-Fix): Likes NICHT client-seitig einfügen — der
    // DB-Trigger notify_on_like() ist die EINZIGE Quelle (inkl. Aggregation
    // „X neue Likes"). Sonst entstehen zwei Like-Benachrichtigungen pro Like.
    if (type == 'like') return;
    final uid = _userId;
    if (uid == null) return;

    try {
      final post = await _db
          .from('posts')
          .select('user_id')
          .eq('id', postId)
          .maybeSingle();
      final postAuthor = post?['user_id'] as String?;
      if (postAuthor == null || postAuthor == uid) return;

      await _db.from('notifications').insert({
        'user_id': postAuthor,
        'from_user_id': uid,
        'type': type,
        'reference_id': postId,
      });
    } catch (e) {
      debugPrint('[Social] $type-Notification fehlgeschlagen: $e');
    }
  }

  // ── Posts ──────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getFeedPosts() async {
    final uid = _userId;
    if (uid == null) return [];

    try {
      final following = await getFollowingIds(uid);

      // Blockierte User in beide Richtungen ausfiltern.
      final blocked = await getBlockedAndBlockerIds();
      final allowedFollowing = following
          .where((id) => !blocked.contains(id))
          .toList();

      // 2026-08-07 (vucko): „man sieht seine eigenen posts nicht im feed."
      // Der Feed wurde ausschliesslich aus Accounts gespeist, denen man
      // folgt — die eigene ID landete nie in dieser Liste, weil sich niemand
      // selbst folgt. Schlimmer noch: wer niemandem folgte, brach hier
      // vorher komplett ab (`return []`) und sah nicht einmal die eigenen
      // Beitraege. Beide Abbrueche sind deshalb weg; eigene Beitraege holt
      // jetzt eine dritte, eigene Abfrage.

      // 2026-08-24 (vucko „cozy hat gepostet, ich sehe es nicht"): Hier stand
      // eine zweite Abfrage, die aus `allowedFollowing` die Menge „mutual"
      // schnitt — nur wer ZURUECKFOLGT, dessen „Nur Follower"-Beitraege
      // kamen in den Feed. Gemessen: Vucko folgt cozy, cozy folgt nicht
      // zurueck, cozys zwei Beitraege vom 21.08. fehlten deshalb.
      //
      // Die Bedingung ist ersatzlos weg. Wer „Follower" waehlt, meint seine
      // Follower — die Begruendung steht ausfuehrlich bei
      // [FeedSichtbarkeit]. Die Menge „mutual" wird weiterhin gebraucht,
      // aber woanders (`getMutualFollowIds`, Gruppen-Einladungen in
      // group_lobby_page.dart) — dort ist „gegenseitig" auch gemeint.

      // 2026-07-03 (vucko Gruppen-Share): shared_group_id analog zu shared_route_id
      // mitgeladen (kommt über `*` ohnehin mit, hier explizit fürs Muster).
      const select =
          '*, profiles(id, username, avatar_url), shared_route_id, shared_group_id';

      // Der Filter bleibt bewusst auf Query-Ebene, obwohl die Leseregel der
      // Datenbank dasselbe durchsetzt: doppelt haelt besser, und der Client
      // soll nichts anfragen, was er ohnehin nicht bekommen darf. Ein leeres
      // inFilter erzeugt `user_id=in.()` und laesst PostgREST stolpern,
      // deshalb die Abfrage nur bei nicht-leerer Liste. Der is_hidden-Filter
      // ist tolerant: alte Zeilen ohne Default sind null = nicht hidden.
      final results = await Future.wait([
        if (allowedFollowing.isNotEmpty)
          _db
              .from('posts')
              .select(select)
              .inFilter('user_id', allowedFollowing)
              .inFilter('visibility', FeedSichtbarkeit.stufenVonGefolgten)
              .neq('is_hidden', true)
              .order('created_at', ascending: false)
              .limit(80),
        // Die eigenen Beitraege, unabhaengig von der Sichtbarkeit: wer einen
        // Beitrag nur fuer Follower schreibt, will ihn selbst trotzdem sehen.
        // Ausgeblendete (moderierte) Beitraege bleiben aussen vor, damit der
        // Feed hier nichts zeigt, was fuer andere unsichtbar ist.
        _db
            .from('posts')
            .select(select)
            .eq('user_id', uid)
            .neq('is_hidden', true)
            .order('created_at', ascending: false)
            .limit(80),
      ]);

      final folgeIch = allowedFollowing.toSet();
      final merged = <String, Map<String, dynamic>>{};
      for (final batch in results) {
        for (final row in batch as List) {
          final post = Map<String, dynamic>.from(row as Map);
          final id = post['id'] as String?;
          final verfasser = post['user_id'] as String?;
          if (id == null || verfasser == null) continue;
          // Zweiter Boden hinter Query-Filter und Leseregel der Datenbank.
          if (!FeedSichtbarkeit.imFeedSichtbar(
            betrachterId: uid,
            verfasserId: verfasser,
            sichtbarkeit: post['visibility'] as String?,
            folgeIch: folgeIch,
            blockiert: blocked,
            istAusgeblendet: post['is_hidden'] == true,
          )) {
            continue;
          }
          merged[id] = post;
        }
      }

      final list = merged.values.toList()
        ..sort((a, b) {
          final ad = DateTime.tryParse(a['created_at'] as String? ?? '');
          final bd = DateTime.tryParse(b['created_at'] as String? ?? '');
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return bd.compareTo(ad);
        });

      final capped = list.take(80).toList();
      await _hydratePostReactionState(capped);
      final eigene = capped.where((p) => p['user_id'] == uid).length;
      debugPrint(
        '[Feed] uid=$uid following=${following.length} '
        '(erlaubt: ${allowedFollowing.length}) '
        '→ posts=${capped.length} (davon eigene: $eigene)',
      );
      return capped;
    } catch (e) {
      debugPrint('[SocialService] getFeedPosts Fehler: $e');
      return [];
    }
  }

  /// IDs, denen der User folgt (status accepted).
  static Future<Set<String>> getFollowingIds(String uid) async {
    final rows = await _db
        .from('follows')
        .select('following_id')
        .eq('follower_id', uid)
        .eq('status', 'accepted');
    return (rows as List)
        .map((r) => (r as Map)['following_id'] as String)
        .toSet();
  }

  /// IDs mit gegenseitiger Folge (Kontakte).
  ///
  /// 2026-08-24 (vucko): Diese Menge ist NICHT das Publikum der
  /// Sichtbarkeitsstufe „Nur Follower" — dafuer zaehlt allein
  /// [getFollowingIds] in der Gegenrichtung. Gebraucht wird „gegenseitig"
  /// nur dort, wo es auch draufsteht: Gruppen-Einladungen in
  /// `group_lobby_page.dart`. Wer sie wieder in eine Beitrags-Abfrage
  /// einbaut, macht den Fehler vom 24.08. noch einmal — Begruendung bei
  /// [FeedSichtbarkeit].
  static Future<Set<String>> getMutualFollowIds(String uid) async {
    final following = await getFollowingIds(uid);
    if (following.isEmpty) return {};
    final back = await _db
        .from('follows')
        .select('follower_id')
        .eq('following_id', uid)
        .eq('status', 'accepted')
        .inFilter('follower_id', following.toList());
    return (back as List)
        .map((r) => (r as Map)['follower_id'] as String)
        .toSet();
  }

  static Future<bool> isMutualFollow(String otherUserId) async {
    final uid = _userId;
    if (uid == null) return false;
    final rows = await _db
        .from('follows')
        .select('follower_id, following_id')
        .or(
          'and(follower_id.eq.$uid,following_id.eq.$otherUserId),and(follower_id.eq.$otherUserId,following_id.eq.$uid)',
        )
        .eq('status', 'accepted');
    return (rows as List).length >= 2;
  }

  /// Beitraege eines Profils.
  ///
  /// 2026-08-24 (vucko): dieselbe Regel wie im Feed — hier war bis heute
  /// GAR KEINE. Die Abfrage gab jeden Beitrag des Profils heraus, auch die
  /// auf „Nur Follower" gestellten und die moderierten (`is_hidden`). Das
  /// ist die Gegenrichtung desselben Denkfehlers: im Feed war „Follower" zu
  /// eng ausgelegt, auf dem fremden Profil gar nicht. Beide Stellen fragen
  /// jetzt [FeedSichtbarkeit].
  ///
  /// Auf dem EIGENEN Profil bleibt alles sichtbar, auch Ausgeblendetes —
  /// wer moderiert wurde, soll sehen, was mit seinem Beitrag passiert ist.
  static Future<List<Map<String, dynamic>>> getUserPosts(String userId) async {
    try {
      final uid = _userId;
      final istEigenesProfil = uid != null && uid == userId;
      final folgeIchIhm =
          istEigenesProfil || (await getFollowStatus(userId)) == 'accepted';

      var query = _db
          .from('posts')
          .select('*, profiles(id, username, avatar_url)')
          .eq('user_id', userId);
      if (!istEigenesProfil) {
        // Doppelt haelt besser: serverseitig gefiltert UND unten noch einmal
        // geprueft. Der Client fragt nicht nach, was er nicht sehen darf.
        query = query
            .inFilter(
              'visibility',
              FeedSichtbarkeit.stufenFuerVerfasser(folgeIchIhm: folgeIchIhm),
            )
            .neq('is_hidden', true);
      }
      final posts = await query.order('created_at', ascending: false);

      final list = (posts as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .where(
            (p) => FeedSichtbarkeit.aufProfilSichtbar(
              betrachterId: uid,
              verfasserId: userId,
              sichtbarkeit: p['visibility'] as String?,
              folgeIchIhm: folgeIchIhm,
              istAusgeblendet: p['is_hidden'] == true,
            ),
          )
          .toList();
      await _hydratePostReactionState(list);
      return list;
    } catch (e) {
      debugPrint('[SocialService] getUserPosts Fehler: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getDiscoverPosts() async {
    try {
      final uid = _userId;
      final following = uid == null ? <String>{} : await getFollowingIds(uid);
      final blocked = await getBlockedAndBlockerIds();

      // Entdecken = öffentliche Posts von Usern, denen der aktuelle User
      // NICHT folgt (und nicht vom User selbst). Private Accounts und
      // blockierte User in beide Richtungen sind raus.
      final posts = await _db
          .from('posts')
          .select(
            '*, profiles(id, username, avatar_url, is_private), shared_route_id, shared_group_id',
          )
          .eq('visibility', 'public')
          .neq('is_hidden', true)
          .order('created_at', ascending: false)
          .limit(80);

      final filtered = (posts as List).where((p) {
        final authorId = p['user_id'] as String?;
        if (authorId == null) return false;
        if (authorId == uid) return false;
        if (following.contains(authorId)) return false;
        if (blocked.contains(authorId)) return false;
        final profile = p['profiles'] as Map<String, dynamic>?;
        return profile?['is_private'] != true;
      }).toList();

      final list = List<Map<String, dynamic>>.from(filtered.take(30));
      await _hydratePostReactionState(list);
      return list;
    } catch (e) {
      debugPrint('[SocialService] getDiscoverPosts Fehler: $e');
      return [];
    }
  }

  /// Legt einen Post an und gibt die neue Post-ID zurück (oder null bei
  /// fehlendem User / Fehler). Aufrufer kann die ID nutzen, um direkt
  /// Mention-Notifications zu verschicken.
  static Future<String?> createPost(
    String content, {
    String visibility = 'public',
    String? sharedRouteId,
    String? sharedGroupId,
  }) async {
    final uid = _userId;
    if (uid == null) return null;
    final cleanedContent = content.trim();
    if (cleanedContent.isEmpty) return null;
    if (cleanedContent.length > AppInputLimits.postContentMaxLength) {
      throw const SocialServiceException('Post ist zu lang.');
    }
    final cleanedSharedRouteId = sharedRouteId?.trim();
    final cleanedSharedGroupId = sharedGroupId?.trim();

    if (cleanedSharedRouteId != null && cleanedSharedRouteId.isNotEmpty) {
      final alreadyPosted = await hasOwnPostForSharedRoute(
        cleanedSharedRouteId,
      );
      if (alreadyPosted) throw const DuplicateSharedRoutePostException();
    }

    // 2026-07-03 (vucko Gruppen-Share): Dubletten-Check gespiegelt vom Routen-Share.
    if (cleanedSharedGroupId != null && cleanedSharedGroupId.isNotEmpty) {
      final alreadyPosted = await hasOwnPostForSharedGroup(
        cleanedSharedGroupId,
      );
      if (alreadyPosted) throw const DuplicateSharedGroupPostException();
    }

    final row = <String, dynamic>{
      'user_id': uid,
      'content': cleanedContent,
      'visibility': visibility,
    };
    if (cleanedSharedRouteId != null && cleanedSharedRouteId.isNotEmpty) {
      row['shared_route_id'] = cleanedSharedRouteId;
    }
    if (cleanedSharedGroupId != null && cleanedSharedGroupId.isNotEmpty) {
      row['shared_group_id'] = cleanedSharedGroupId;
    }

    late final dynamic result;
    try {
      result = await _db.from('posts').insert(row).select('id').single();
    } on PostgrestException catch (e) {
      if (isDuplicateSharedRoutePostError(e)) {
        throw const DuplicateSharedRoutePostException();
      }
      if (isDuplicateSharedGroupPostError(e)) {
        throw const DuplicateSharedGroupPostException();
      }
      rethrow;
    }
    final postId = (result as Map?)?['id'] as String?;

    // Mentions im Content auflösen — Anti-Spam: nur eigene Follower werden
    // tatsächlich benachrichtigt.
    if (postId != null) {
      final mentions = _extractMentions(cleanedContent);
      if (mentions.isNotEmpty) {
        await sendMentionNotifications(postId: postId, usernames: mentions);
      }
    }
    return postId;
  }

  static Future<bool> hasOwnPostForSharedRoute(String routeId) async {
    final uid = _userId;
    final cleanedRouteId = routeId.trim();
    if (uid == null || cleanedRouteId.isEmpty) return false;

    final row = await _db
        .from('posts')
        .select('id')
        .eq('user_id', uid)
        .eq('shared_route_id', cleanedRouteId)
        .maybeSingle();
    return row != null;
  }

  // 2026-07-03 (vucko Gruppen-Share): gespiegelt vom Routen-Share — hat der User
  // diese Gruppe schon gepostet?
  static Future<bool> hasOwnPostForSharedGroup(String groupId) async {
    final uid = _userId;
    final cleanedGroupId = groupId.trim();
    if (uid == null || cleanedGroupId.isEmpty) return false;

    final row = await _db
        .from('posts')
        .select('id')
        .eq('user_id', uid)
        .eq('shared_group_id', cleanedGroupId)
        .maybeSingle();
    return row != null;
  }

  static Future<void> deletePost(String postId) async {
    await _db.from('posts').delete().eq('id', postId);
  }

  /// Ein einzelner Beitrag, geoeffnet ueber die Glocke oder einen Deeplink.
  ///
  /// 2026-08-24 (vucko): Der dritte Umweg an derselben Wurzel. Wer eine
  /// Beitrags-Kennung hatte — aus einer Kommentar-Benachrichtigung, aus einem
  /// geteilten Link — bekam den Beitrag hier ungefiltert, auch den auf „Nur
  /// Follower" gestellten. Aufrufer sind `notification_router.dart` und der
  /// Deeplink in `main.dart`. Es gilt dieselbe Regel wie auf dem Profil:
  /// eigene Beitraege immer, „Nur Follower" nur fuer Follower.
  static Future<Map<String, dynamic>?> getPostById(String postId) async {
    try {
      final result = await _db
          .from('posts')
          .select(
            '*, profiles(id, username, avatar_url), shared_route_id, shared_group_id',
          )
          .eq('id', postId)
          .maybeSingle();
      if (result == null) return null;
      final post = Map<String, dynamic>.from(result);

      final uid = _userId;
      final verfasser = post['user_id'] as String?;
      if (verfasser != null) {
        final folgeIchIhm =
            uid != null &&
            (uid == verfasser ||
                (await getFollowStatus(verfasser)) == 'accepted');
        if (!FeedSichtbarkeit.aufProfilSichtbar(
          betrachterId: uid,
          verfasserId: verfasser,
          sichtbarkeit: post['visibility'] as String?,
          folgeIchIhm: folgeIchIhm,
          istAusgeblendet: post['is_hidden'] == true,
        )) {
          return null;
        }
      }

      await _hydratePostReactionState([post]);
      return post;
    } catch (e) {
      debugPrint('[SocialService] getPostById Fehler: $e');
      return null;
    }
  }

  /// 2026-08-23 (vucko, Sprachnachricht: „dass wenn er eine Gruppe erstellt hat
  /// und er einen anderen einlaedt und er ueber die Glocke bzw. ueber den
  /// Quicklink dann joinen will, dass ein Fehler kommt"):
  ///
  /// Hier stand bis heute `groupExists`. Die Funktion hat eine LEERE Antwort
  /// von PostgREST als „Gruppe geloescht" gedeutet. Das ist falsch: Bei einem
  /// RLS-Ausschluss liefert PostgREST HTTP 200 mit leerer Liste, es gibt keinen
  /// Fehlercode. Leer heisst also „du darfst nicht lesen", nicht „gibt es
  /// nicht". Gemessen am echten Vorfall: Gruppe ac29cf1f-e50f-4b2e-81d3-
  /// d99885e7e084 („latenight session", privat, 21.08. 21:38). Der Eingeladene
  /// 645065af-3999-4e66-90cd-c4718c0b8ddf tippte um 21:42:49, 21:42:57 und
  /// 21:44:13 auf die Glocke, jedes Mal
  /// `GET /rest/v1/groups?select=id&id=eq.ac29cf1f...` mit HTTP 200 und
  /// content_length 2 (leere Liste), danach nie ein Lobby-Aufruf. Er ist bis
  /// heute nicht in `group_members`. Einladungen 2, eingeloest 0.
  /// Zusaetzlich verschluckte das `catch (_) { return false; }` jeden
  /// Netzfehler und machte daraus ebenfalls „nicht mehr verfuegbar".
  ///
  /// Ersatz ist diese Pruefung mit vier ehrlichen Ausgaengen. Der zweite
  /// Zeuge ist die Datenbankfunktion `can_join_group` (SECURITY DEFINER, an
  /// `authenticated` freigegeben): sie kennt die Einladung ausdruecklich und
  /// sieht die Gruppe auch dann, wenn die Lesepolitik sie versteckt.
  static Future<GruppenZugangsBescheid> pruefeGruppenZugang(
    String groupId,
  ) async {
    final uid = _userId;
    if (uid == null) {
      return const GruppenZugangsBescheid(GruppenZugang.nichtAngemeldet);
    }

    Map<String, dynamic>? zeile;
    try {
      final row = await _db
          .from('groups')
          .select(
            'id, name, created_by, is_public, is_active, closed_at, '
            'start_time, max_people, group_members(user_id), '
            'profiles:created_by(id, username, avatar_url)',
          )
          .eq('id', groupId)
          .maybeSingle();
      if (row != null) zeile = Map<String, dynamic>.from(row);
    } catch (e) {
      // Netz-/Serverfehler: Wir wissen es NICHT. Frueher wurde daraus
      // „Diese Gruppe ist nicht mehr verfuegbar." — eine Luege.
      debugPrint('[SocialService] pruefeGruppenZugang Lesefehler: $e');
      return const GruppenZugangsBescheid(GruppenZugang.netzfehler);
    }

    final mitgliederIds = ((zeile?['group_members'] as List?) ?? const [])
        .map((m) => (m as Map)['user_id']?.toString())
        .whereType<String>()
        .toList();

    // Bin ich schon drin? Dann brauchen wir den zweiten Zeugen nicht.
    if (zeile != null &&
        (zeile['created_by'] == uid || mitgliederIds.contains(uid))) {
      return GruppenZugangsBescheid(
        GruppenZugang.mitglied,
        gruppe: zeile,
        gruppenName: (zeile['name'] as String?)?.trim(),
      );
    }

    bool darfBeitreten;
    try {
      final antwort = await _db.rpc(
        'can_join_group',
        params: {'p_group_id': groupId, 'p_user_id': uid},
      );
      darfBeitreten = antwort == true;
    } catch (e) {
      debugPrint('[SocialService] can_join_group Fehler: $e');
      return const GruppenZugangsBescheid(GruppenZugang.netzfehler);
    }

    return GruppenZugangsBescheid(
      entscheideGruppenZugang(
        angemeldet: true,
        zeileLesbar: zeile != null,
        binMitglied: false,
        darfBeitreten: darfBeitreten,
      ),
      gruppe: zeile,
      gruppenName: (zeile?['name'] as String?)?.trim(),
    );
  }

  /// Die Entscheidungsregel ohne Datenbank, damit sie pruefbar ist.
  ///
  /// Wichtig: `zeileLesbar == false` ist KEIN Beweis fuer „geloescht".
  /// Erst wenn auch `can_join_group` nein sagt, ist die Gruppe fuer diesen
  /// Nutzer wirklich zu Ende (geloescht, beendet, oder die Fahrt laeuft schon).
  @visibleForTesting
  static GruppenZugang entscheideGruppenZugang({
    required bool angemeldet,
    required bool zeileLesbar,
    required bool binMitglied,
    required bool darfBeitreten,
  }) {
    if (!angemeldet) return GruppenZugang.nichtAngemeldet;
    if (binMitglied) return GruppenZugang.mitglied;
    if (darfBeitreten) return GruppenZugang.einladung;
    return GruppenZugang.nichtVerfuegbar;
  }

  // ── Likes ─────────────────────────────────────────────────────────────

  /// Hat die Datenbank das Liken/Reposten abgelehnt, weil der Beitrag fuer
  /// mich gar nicht sichtbar ist?
  ///
  /// 2026-08-24 (vucko): Seit die Leseregel „Nur Follower" serverseitig
  /// durchsetzt (Migration 20260824170000), koennen `toggle_post_like` und
  /// `toggle_post_repost` mit `beitrag_nicht_sichtbar` (42501) ablehnen.
  /// Der Rueckfallweg darunter ist fuer den Fall gedacht, dass die RPC FEHLT
  /// — er darf eine ABLEHNUNG nicht als „RPC kaputt" missverstehen und es
  /// dann direkt ueber die Tabelle noch einmal versuchen. Das scheitert
  /// zweitens an der Regel und wirft dem Nutzer eine rohe
  /// Datenbank-Ausnahme ins Gesicht.
  @visibleForTesting
  static bool istAblehnungWegenSichtbarkeit(Object error) {
    if (error is! PostgrestException) return false;
    if (error.code == '42501') return true;
    final text = '${error.message} ${error.details ?? ''}'.toLowerCase();
    return text.contains('beitrag_nicht_sichtbar');
  }

  static Future<bool> toggleLike(String postId) async {
    final result = await toggleLikeWithCount(postId);
    return result.isActive;
  }

  static Future<({bool isActive, int count})> toggleLikeWithCount(
    String postId,
  ) async {
    final uid = _userId;
    if (uid == null) return (isActive: false, count: 0);

    try {
      final raw = await _db.rpc(
        'toggle_post_like',
        params: {'post_id_param': postId},
      );
      final result = _reactionToggleResult(raw);
      if (result.isActive) {
        await _sendPostReactionNotification(postId: postId, type: 'like');
      }
      return result;
    } catch (e) {
      if (istAblehnungWegenSichtbarkeit(e)) {
        // Kein Rueckfall: die Datenbank hat NEIN gesagt, nicht geschwiegen.
        debugPrint('[SocialService] Like abgelehnt (Beitrag nicht sichtbar)');
        return (
          isActive: false,
          count: await _countPostReactions('post_likes', postId),
        );
      }
      debugPrint('[SocialService] toggle_post_like RPC fallback: $e');
    }

    final existing = await _db
        .from('post_likes')
        .select('id')
        .eq('post_id', postId)
        .eq('user_id', uid)
        .maybeSingle();

    if (existing != null) {
      await _db.from('post_likes').delete().eq('id', existing['id']);
      try {
        await _db.rpc('decrement_likes', params: {'post_id_param': postId});
      } catch (e) {
        debugPrint('[SocialService] decrement_likes ignoriert: $e');
      }
      final count = await _countPostReactions('post_likes', postId);
      return (isActive: false, count: count);
    }

    await _db.from('post_likes').insert({'post_id': postId, 'user_id': uid});
    try {
      await _db.rpc('increment_likes', params: {'post_id_param': postId});
    } catch (e) {
      debugPrint('[SocialService] increment_likes ignoriert: $e');
    }
    await _sendPostReactionNotification(postId: postId, type: 'like');
    final count = await _countPostReactions('post_likes', postId);
    return (isActive: true, count: count);
  }

  static Future<bool> hasLiked(String postId) async {
    final uid = _userId;
    if (uid == null) return false;

    final existing = await _db
        .from('post_likes')
        .select('id')
        .eq('post_id', postId)
        .eq('user_id', uid)
        .maybeSingle();

    return existing != null;
  }

  /// Alle Posts, die ein User geliket hat (für "Gefällt mir" im Profil-Menü).
  ///
  /// 2026-08-24 (vucko): Derselbe Umweg wie beim Repost — die Liste traegt
  /// fremde Beitraege mit. Ein Like darf das Publikum nicht aendern, das sich
  /// der VERFASSER ausgesucht hat. Geprueft wird gegen den Verfasser des
  /// Beitrags, nicht gegen den, der geliket hat. Heute ruft nur
  /// `liked_posts_page.dart` mit der eigenen Kennung auf; die Funktion nimmt
  /// aber eine fremde entgegen, und dann waere die Luecke offen.
  static Future<List<Map<String, dynamic>>> getUserLikes(String userId) async {
    final likes = await _db
        .from('post_likes')
        .select('*, posts(*, profiles(id, username, avatar_url))')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final betrachter = _userId;
    final folgeIch = betrachter == null
        ? <String>{}
        : await getFollowingIds(betrachter);

    final list = List<Map<String, dynamic>>.from(likes).where((like) {
      final post = like['posts'];
      // Zeilen ohne mitgeladenen Beitrag (geloescht) bleiben erhalten wie
      // bisher — die Seite ueberspringt sie ohnehin.
      if (post is! Map) return true;
      final verfasser = post['user_id'] as String?;
      if (verfasser == null) return true;
      return FeedSichtbarkeit.aufProfilSichtbar(
        betrachterId: betrachter,
        verfasserId: verfasser,
        sichtbarkeit: post['visibility'] as String?,
        folgeIchIhm: folgeIch.contains(verfasser),
        istAusgeblendet: post['is_hidden'] == true,
      );
    }).toList();
    final nestedPosts = <String, Map<String, dynamic>>{};
    for (final like in list) {
      final post = like['posts'];
      if (post is! Map) continue;
      final postMap = Map<String, dynamic>.from(post);
      final postId = postMap['id'] as String?;
      if (postId != null) nestedPosts[postId] = postMap;
    }

    await _hydratePostReactionState(nestedPosts.values.toList());
    for (final like in list) {
      final post = like['posts'];
      if (post is! Map) continue;
      final postId = post['id'] as String?;
      final hydrated = postId == null ? null : nestedPosts[postId];
      if (hydrated != null) like['posts'] = hydrated;
    }

    return list;
  }

  // ── Comments ─────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getComments(String postId) async {
    final uid = _userId;
    final results = await _db
        .from('comments')
        .select(
          '*, profiles!comments_user_id_profiles_fkey(id, username, avatar_url)',
        )
        .eq('post_id', postId)
        .order('created_at', ascending: true);

    final list = List<Map<String, dynamic>>.from(results);
    if (uid == null || list.isEmpty) return list;

    // Welche Kommentare hat dieser User geliket?
    final ids = list.map((c) => c['id'] as String).toList();
    final likes = await _db
        .from('comment_likes')
        .select('comment_id')
        .eq('user_id', uid)
        .inFilter('comment_id', ids);
    final likedIds = {
      for (final row in likes as List) row['comment_id'] as String,
    };
    for (final c in list) {
      c['is_liked'] = likedIds.contains(c['id']);
    }
    return list;
  }

  static Future<void> addComment(
    String postId,
    String content, {
    String? parentCommentId,
  }) async {
    final uid = _userId;
    final cleanedContent = content.trim();
    if (uid == null || cleanedContent.isEmpty) return;
    if (cleanedContent.length > AppInputLimits.commentMaxLength) {
      throw const SocialServiceException('Kommentar ist zu lang.');
    }

    final row = <String, dynamic>{
      'post_id': postId,
      'user_id': uid,
      'content': cleanedContent,
    };
    if (parentCommentId != null) {
      row['parent_comment_id'] = parentCommentId;
    }
    await _db.from('comments').insert(row);
    await _db.rpc('increment_comments', params: {'post_id_param': postId});

    // Notifications: Reply → an Parent-Autor; Top-Level → an Post-Autor.
    try {
      if (parentCommentId != null) {
        final parent = await _db
            .from('comments')
            .select('user_id')
            .eq('id', parentCommentId)
            .maybeSingle();
        final parentAuthor = parent?['user_id'] as String?;
        if (parentAuthor != null && parentAuthor != uid) {
          await _db.from('notifications').insert({
            'user_id': parentAuthor,
            'from_user_id': uid,
            'type': 'comment_reply',
            'reference_id': postId,
          });
        }
      } else {
        final post = await _db
            .from('posts')
            .select('user_id')
            .eq('id', postId)
            .maybeSingle();
        final postAuthor = post?['user_id'] as String?;
        if (postAuthor != null && postAuthor != uid) {
          await _db.from('notifications').insert({
            'user_id': postAuthor,
            'from_user_id': uid,
            'type': 'comment',
            'reference_id': postId,
          });
        }
      }
    } catch (e) {
      debugPrint('[Social] Comment-Notification fehlgeschlagen: $e');
    }

    // Mention-Notifications für `@username`-Tokens im Kommentar.
    final mentions = _extractMentions(content.trim());
    if (mentions.isNotEmpty) {
      await sendMentionNotifications(postId: postId, usernames: mentions);
    }
  }

  static Future<void> deleteComment(String commentId, String postId) async {
    await _db.from('comments').delete().eq('id', commentId);
    await _db.rpc('decrement_comments', params: {'post_id_param': postId});
  }

  /// Liked einen Kommentar oder entfernt den Like (Toggle).
  /// Gibt den neuen Zustand zurück (true = jetzt geliked).
  static Future<bool> toggleCommentLike(String commentId) async {
    final uid = _userId;
    if (uid == null) return false;

    final existing = await _db
        .from('comment_likes')
        .select('id')
        .eq('comment_id', commentId)
        .eq('user_id', uid)
        .maybeSingle();

    if (existing != null) {
      await _db.from('comment_likes').delete().eq('id', existing['id']);
      await _db.rpc(
        'decrement_comment_likes',
        params: {'comment_id_param': commentId},
      );
      return false;
    }

    await _db.from('comment_likes').insert({
      'comment_id': commentId,
      'user_id': uid,
    });
    await _db.rpc(
      'increment_comment_likes',
      params: {'comment_id_param': commentId},
    );

    // Notification an Kommentar-Autor
    try {
      final comment = await _db
          .from('comments')
          .select('user_id, post_id')
          .eq('id', commentId)
          .maybeSingle();
      final commentAuthor = comment?['user_id'] as String?;
      if (commentAuthor != null && commentAuthor != uid) {
        await _db.from('notifications').insert({
          'user_id': commentAuthor,
          'from_user_id': uid,
          'type': 'comment_like',
          'reference_id': comment?['post_id'],
        });
      }
    } catch (e) {
      debugPrint('[Social] Comment-Like-Notification fehlgeschlagen: $e');
    }
    return true;
  }

  // ── Reposts ─────────────────────────────────────────────────────────

  static Future<bool> toggleRepost(String postId) async {
    final result = await toggleRepostWithCount(postId);
    return result.isActive;
  }

  static Future<({bool isActive, int count})> toggleRepostWithCount(
    String postId,
  ) async {
    final uid = _userId;
    if (uid == null) return (isActive: false, count: 0);

    try {
      final raw = await _db.rpc(
        'toggle_post_repost',
        params: {'post_id_param': postId},
      );
      final result = _reactionToggleResult(raw);
      if (result.isActive) {
        await _sendPostReactionNotification(postId: postId, type: 'repost');
      }
      return result;
    } catch (e) {
      if (istAblehnungWegenSichtbarkeit(e)) {
        debugPrint('[SocialService] Repost abgelehnt (Beitrag nicht sichtbar)');
        return (
          isActive: false,
          count: await _countPostReactions('reposts', postId),
        );
      }
      debugPrint('[SocialService] toggle_post_repost RPC fallback: $e');
    }

    final existing = await _db
        .from('reposts')
        .select('id')
        .eq('post_id', postId)
        .eq('user_id', uid)
        .maybeSingle();

    if (existing != null) {
      await _db.from('reposts').delete().eq('id', existing['id']);
      try {
        await _db.rpc('decrement_reposts', params: {'post_id_param': postId});
      } catch (e) {
        debugPrint('[SocialService] decrement_reposts ignoriert: $e');
      }
      final count = await _countPostReactions('reposts', postId);
      return (isActive: false, count: count);
    }

    await _db.from('reposts').insert({'post_id': postId, 'user_id': uid});
    try {
      await _db.rpc('increment_reposts', params: {'post_id_param': postId});
    } catch (e) {
      debugPrint('[SocialService] increment_reposts ignoriert: $e');
    }
    await _sendPostReactionNotification(postId: postId, type: 'repost');
    final count = await _countPostReactions('reposts', postId);
    return (isActive: true, count: count);
  }

  static Future<bool> hasReposted(String postId) async {
    final uid = _userId;
    if (uid == null) return false;

    final existing = await _db
        .from('reposts')
        .select('id')
        .eq('post_id', postId)
        .eq('user_id', uid)
        .maybeSingle();

    return existing != null;
  }

  /// Alle Reposts eines Users (für Profil-Seite)
  /// 2026-08-24 (vucko): Ein Repost traegt den fremden Beitrag mit. Wer ihn
  /// weiterreicht, darf damit nicht das Publikum aendern, das sich der
  /// VERFASSER ausgesucht hat — ein auf „Nur Follower" gestellter Beitrag
  /// blieb ueber den Umweg Repost sonst fuer jeden lesbar. Geprueft wird
  /// gegen den Verfasser des Originals, nicht gegen den, der repostet hat.
  static Future<List<Map<String, dynamic>>> getUserReposts(
    String userId,
  ) async {
    final reposts = await _db
        .from('reposts')
        .select('*, posts(*, profiles(id, username, avatar_url))')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final betrachter = _userId;
    final folgeIch = betrachter == null
        ? <String>{}
        : await getFollowingIds(betrachter);

    final list = List<Map<String, dynamic>>.from(reposts).where((repost) {
      final post = repost['posts'];
      if (post is! Map) return false;
      final verfasser = post['user_id'] as String?;
      if (verfasser == null) return false;
      return FeedSichtbarkeit.aufProfilSichtbar(
        betrachterId: betrachter,
        verfasserId: verfasser,
        sichtbarkeit: post['visibility'] as String?,
        folgeIchIhm: folgeIch.contains(verfasser),
        istAusgeblendet: post['is_hidden'] == true,
      );
    }).toList();
    final nestedPosts = <String, Map<String, dynamic>>{};
    for (final repost in list) {
      final post = repost['posts'];
      if (post is! Map) continue;
      final postMap = Map<String, dynamic>.from(post);
      final postId = postMap['id'] as String?;
      if (postId != null) nestedPosts[postId] = postMap;
    }

    await _hydratePostReactionState(nestedPosts.values.toList());
    for (final repost in list) {
      final post = repost['posts'];
      if (post is! Map) continue;
      final postId = post['id'] as String?;
      final hydrated = postId == null ? null : nestedPosts[postId];
      if (hydrated != null) repost['posts'] = hydrated;
    }

    return list;
  }

  // ── Follows ───────────────────────────────────────────────────────────

  /// Folgt einem User. Bei privaten Konten wird stattdessen ein
  /// Pending-Request angelegt — der Inhaber muss erst akzeptieren, bevor
  /// die Beziehung als `accepted` gilt.
  /// Returns: 'accepted' | 'pending' | 'none' (none = self/no-op).
  static Future<String> followUser(String targetUserId) async {
    final uid = _userId;
    if (uid == null || uid == targetUserId) return 'none';
    if (await isBlockedEither(targetUserId)) return 'none';

    final existingStatus = await getFollowStatus(targetUserId);
    if (existingStatus == 'accepted' || existingStatus == 'pending') {
      return existingStatus;
    }

    // Prüfen, ob Ziel privat ist.
    final profile = await _db
        .from('profiles')
        .select('is_private')
        .eq('id', targetUserId)
        .maybeSingle();
    final isPrivate = (profile as Map?)?['is_private'] == true;
    final status = isPrivate ? 'pending' : 'accepted';

    try {
      await _db.from('follows').insert({
        'follower_id': uid,
        'following_id': targetUserId,
        'status': status,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return getFollowStatus(targetUserId);
      rethrow;
    }

    // 2026-07-10 (vucko Doppel-Benachrichtigung-Fix): KEIN Client-Insert mehr.
    // Der DB-Trigger notify_on_follow() ist die EINZIGE Quelle für die
    // Follow-Benachrichtigung (statusbewusst: 'friend_request' bei pending,
    // sonst 'follow'). Der frühere Client-Insert hier erzeugte pro Follow eine
    // ZWEITE notifications-Zeile → doppelte Benachrichtigung/Push.
    return status;
  }

  static Future<void> unfollowUser(String targetUserId) async {
    final uid = _userId;
    if (uid == null) return;

    await _db
        .from('follows')
        .delete()
        .eq('follower_id', uid)
        .eq('following_id', targetUserId);
  }

  /// Entfernt einen Follower von meinem Profil.
  static Future<void> removeFollower(String followerId) async {
    final uid = _userId;
    if (uid == null) return;

    await _db
        .from('follows')
        .delete()
        .eq('follower_id', followerId)
        .eq('following_id', uid);
  }

  /// Gibt den Status der Follow-Beziehung zurück:
  /// `'accepted'` | `'pending'` | `'none'`.
  static Future<String> getFollowStatus(String targetUserId) async {
    final uid = _userId;
    if (uid == null) return 'none';
    final row = await _db
        .from('follows')
        .select('status')
        .eq('follower_id', uid)
        .eq('following_id', targetUserId)
        .maybeSingle();
    final status = (row as Map?)?['status'] as String?;
    return status ?? 'none';
  }

  static Future<bool> isBlockedEither(String targetUserId) async {
    return await getBlockRelationship(targetUserId) != 'none';
  }

  /// Richtung der Block-Beziehung zum aktuellen User.
  /// Werte: `none`, `blocked_by_me`, `blocked_me`, `mutual`.
  static Future<String> getBlockRelationship(String targetUserId) async {
    final uid = _userId;
    if (uid == null || uid == targetUserId) return 'none';
    try {
      final result = await _db.rpc(
        'block_relationship',
        params: {'other': targetUserId},
      );
      return result as String? ?? 'none';
    } catch (e) {
      debugPrint('[Social] getBlockRelationship Fehler: $e');
      return 'none';
    }
  }

  static Future<bool> isFollowing(String targetUserId) async {
    final uid = _userId;
    if (uid == null) return false;

    final result = await _db
        .from('follows')
        .select('id')
        .eq('follower_id', uid)
        .eq('following_id', targetUserId)
        .eq('status', 'accepted')
        .maybeSingle();

    return result != null;
  }

  /// Akzeptiert eine Follow-Anfrage (Update `pending` → `accepted`).
  /// Notification an den Anfragenden, dass die Beziehung jetzt steht.
  static Future<void> acceptFollowRequest(String fromUserId) async {
    final uid = _userId;
    if (uid == null) return;
    final rows = await _db
        .from('follows')
        .update({'status': 'accepted'})
        .eq('follower_id', fromUserId)
        .eq('following_id', uid)
        .eq('status', 'pending')
        .select('id');
    if ((rows as List).isEmpty) {
      throw StateError('Die Anfrage konnte nicht angenommen werden.');
    }
    try {
      await _db.from('notifications').insert({
        'user_id': fromUserId,
        'from_user_id': uid,
        'type': 'follow_accepted',
      });
    } catch (e) {
      debugPrint('[Social] follow_accepted-Notification fehlgeschlagen: $e');
    }
  }

  /// Lehnt eine Follow-Anfrage ab — Row wird gelöscht, kein Eintrag in
  /// notifications, damit der Anfragende es nicht direkt mitbekommt.
  static Future<void> rejectFollowRequest(String fromUserId) async {
    final uid = _userId;
    if (uid == null) return;
    final rows = await _db
        .from('follows')
        .delete()
        .eq('follower_id', fromUserId)
        .eq('following_id', uid)
        .eq('status', 'pending')
        .select('id');
    if ((rows as List).isEmpty) {
      throw StateError('Die Anfrage konnte nicht abgelehnt werden.');
    }
  }

  /// Anzahl meiner offenen Follow-Anfragen — für Badge im Burger-Menü.
  static Future<int> getPendingFollowRequestCount() async {
    final uid = _userId;
    if (uid == null) return 0;
    final rows = await _db
        .from('follows')
        .select('follower_id')
        .eq('following_id', uid)
        .eq('status', 'pending');
    return (rows as List).length;
  }

  /// Liste meiner offenen Follow-Anfragen mit Profil-Infos.
  /// Sortiert: neueste zuerst (über follows.created_at, falls vorhanden).
  static Future<List<Map<String, dynamic>>> getPendingFollowRequests() async {
    final uid = _userId;
    if (uid == null) return [];
    final rows = await _db
        .from('follows')
        .select(
          'follower_id, created_at, '
          'profiles!follows_follower_id_profiles_fkey(id, username, avatar_url)',
        )
        .eq('following_id', uid)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<int> getFollowerCount(String userId) async {
    final result = await _db
        .from('follows')
        .select('id')
        .eq('following_id', userId)
        .eq('status', 'accepted');
    return (result as List).length;
  }

  static Future<int> getFollowingCount(String userId) async {
    final result = await _db
        .from('follows')
        .select('id')
        .eq('follower_id', userId)
        .eq('status', 'accepted');
    return (result as List).length;
  }

  /// Loest einen Benutzernamen zu einer User-ID auf.
  ///
  /// 2026-08-25 (Umlaute im Benutzernamen): Verglichen wird ueber
  /// [usernameKey], nicht mehr nur ueber Gross- und Kleinschreibung.
  /// „@Mueller" trifft damit den Nutzer „müller" und umgekehrt.
  ///
  /// Das ist eine Entscheidung fuer GROSSZUEGIGKEIT beim Erwaehnen, und sie
  /// ist gefahrlos, weil die Eindeutigkeit auf derselben Faltung steht: es
  /// kann „mueller" und „müller" nicht gleichzeitig geben. Wer erwaehnt,
  /// kann also gar nicht den Falschen treffen. Er kann den Richtigen nur
  /// verfehlen, wenn wir zu streng sind — und genau das merkt niemand.
  ///
  /// Warum nicht mehr blank `ilike`: `_` ist in LIKE ein Platzhalter fuer ein
  /// beliebiges Zeichen, „@a_b" hat damit auch „axb" gefunden. Die Antwort
  /// wird deshalb gegen den Schluessel nachgeprueft, statt ihr zu glauben.
  static Future<String?> findUserIdByUsername(String username) async {
    final cleaned = username.trim();
    if (cleaned.isEmpty) return null;
    // Nur echte Namenszeichen gehen in den Filter. Das haelt neben Unsinn
    // auch Komma und Punkt aus der or-Bedingung heraus, die beide dort eine
    // Bedeutung haetten.
    if (!usernameFullPattern.hasMatch(cleaned)) return null;
    final schluessel = usernameKey(cleaned);
    try {
      final filter = usernameSpellings(
        cleaned,
      ).map((wort) => 'username.ilike.$wort').join(',');
      final rows = await _db
          .from('profiles')
          .select('id, username')
          .or(filter)
          .limit(16);
      for (final row in rows as List) {
        final treffer = row as Map;
        if (usernameKey(treffer['username'] as String? ?? '') != schluessel) {
          continue;
        }
        return treffer['id'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('[SocialService] findUserIdByUsername Fehler: $e');
      return null;
    }
  }

  /// Profile meiner Follower — gefiltert nach Username-Prefix.
  /// Quelle für den Mention-Picker (Anti-Spam: man darf nur eigene Follower
  /// erwähnen).
  static Future<List<Map<String, dynamic>>> getMyFollowerProfiles({
    String prefix = '',
    int limit = 8,
  }) async {
    final uid = _userId;
    if (uid == null) return [];

    final rows = await _db
        .from('follows')
        .select(
          'follower_id, profiles!follows_follower_id_profiles_fkey(id, username, avatar_url)',
        )
        .eq('following_id', uid)
        .eq('status', 'accepted');

    final profiles = <Map<String, dynamic>>[];
    // 2026-08-25 (Umlaute im Benutzernamen): Verglichen wird ueber die
    // Faltung. Wer „@mue" tippt, bekommt „müller" vorgeschlagen — sonst
    // reisst die Liste genau bei dem Namen ab, den man gerade sucht.
    final p = usernameKey(prefix);
    final blocked = await getBlockedAndBlockerIds();
    for (final row in rows as List) {
      final profile = (row as Map)['profiles'] as Map<String, dynamic>?;
      if (profile == null) continue;
      final targetId = profile['id'] as String?;
      if (targetId == null || blocked.contains(targetId)) continue;
      final username = usernameKey(profile['username'] as String? ?? '');
      if (username.isEmpty) continue;
      if (p.isNotEmpty && !username.startsWith(p)) continue;
      profiles.add(Map<String, dynamic>.from(profile));
      if (profiles.length >= limit) break;
    }
    return profiles;
  }

  /// Schickt für jeden gementionten User (`@username`) eine Notification.
  /// Anti-Spam: Es werden NUR Mentions akzeptiert, die zu eigenen Followern
  /// gehören; Self-Mentions werden ignoriert.
  /// Gibt die tatsächlich benachrichtigten User-IDs zurück.
  static Future<List<String>> sendMentionNotifications({
    required String postId,
    required Iterable<String> usernames,
  }) async {
    final uid = _userId;
    if (uid == null) return [];
    // 2026-08-25 (Umlaute im Benutzernamen): Beide Seiten werden gefaltet.
    // Ohne das bekaeme „müller" nichts, wenn jemand „@mueller" geschrieben
    // hat — und niemand wuerde es merken.
    final cleaned = usernames
        .map(usernameKey)
        .where((u) => u.isNotEmpty)
        .toSet();
    if (cleaned.isEmpty) return [];
    final blocked = await getBlockedAndBlockerIds();

    // Auflösen Username → user_id, beschränkt auf eigene Follower.
    final rows = await _db
        .from('follows')
        .select(
          'follower_id, profiles!follows_follower_id_profiles_fkey(id, username)',
        )
        .eq('following_id', uid)
        .eq('status', 'accepted');

    final notified = <String>[];
    for (final row in rows as List) {
      final profile = (row as Map)['profiles'] as Map<String, dynamic>?;
      final username = usernameKey(profile?['username'] as String? ?? '');
      final targetId = profile?['id'] as String?;
      if (targetId == null || targetId == uid) continue;
      if (blocked.contains(targetId)) continue;
      if (!cleaned.contains(username)) continue;
      try {
        await _db.from('notifications').insert({
          'user_id': targetId,
          'from_user_id': uid,
          'type': 'mention',
          'reference_id': postId,
        });
        notified.add(targetId);
      } catch (e) {
        debugPrint('[Social] Mention-Notification fehlgeschlagen: $e');
      }
    }
    return notified;
  }

  /// Liste der Follower (Personen, die diesem User folgen)
  static Future<List<Map<String, dynamic>>> getFollowers(String userId) async {
    final result = await _db
        .from('follows')
        .select(
          'follower_id, profiles!follows_follower_id_profiles_fkey(id, username, avatar_url)',
        )
        .eq('following_id', userId)
        .eq('status', 'accepted');
    return List<Map<String, dynamic>>.from(result);
  }

  /// Liste der Personen, denen dieser User folgt
  static Future<List<Map<String, dynamic>>> getFollowingList(
    String userId,
  ) async {
    final result = await _db
        .from('follows')
        .select(
          'following_id, profiles!follows_following_id_profiles_fkey(id, username, avatar_url)',
        )
        .eq('follower_id', userId)
        .eq('status', 'accepted');
    return List<Map<String, dynamic>>.from(result);
  }

  // ── Hashtags ──────────────────────────────────────────────────────────

  /// 2026-08-24 — Aufgabe 1.3. Vucko, Aufnahme 3: „dass man unter Hashtags
  /// Sachen suchen kann" und „für zukünftige Gewinnspiele wäre das auch ganz
  /// cool, dass man da Sachen auslosen kann".
  ///
  /// Weil daraus AUSGELOST werden soll, muss die Liste VOLLSTÄNDIG sein. Sie
  /// kommt deshalb aus `post_hashtags` (Migration 20260824102000) und NICHT
  /// aus einer Textsuche: `content ilike '%tour%'` fände auch „tourenfahrt"
  /// und „kontour". Wer aus so einer Liste auslost, verlost an Leute, die nie
  /// teilgenommen haben.
  ///
  /// Groß- und Kleinschreibung sowie die Umlaut-Schreibweise spielen keine
  /// Rolle: `#Tourenfahrt`, `#tourenfahrt`, `#kurvenkönig` und
  /// `#kurvenkoenig` landen in derselben Liste. Die Faltung macht die
  /// Datenbank (`hashtag_schluessel`), bewusst NICHT der Client — sonst
  /// laufen beide irgendwann auseinander und ein Gewinnspiel verliert
  /// Teilnehmer.
  ///
  /// Zwei bewusste Einschränkungen der RPC, die Vucko kennen muss: nur
  /// `visibility = 'public'`, und keine ausgeblendeten Beiträge oder
  /// gesperrten Konten.
  ///
  /// [tag] darf mit oder ohne Raute kommen.
  /// 2026-08-24 (Auftrag Vucko vom 24.08.): dieselbe Abfrage, aber mit
  /// unterscheidbarem Ausgang. `null` heisst FEHLER, `[]` heisst KEIN
  /// TREFFER.
  ///
  /// Vorher lieferten beide Faelle `[]` und die Seite schrieb „Noch kein
  /// oeffentlicher Beitrag mit diesem Hashtag" — auch bei abgeschaltetem
  /// Netz. Das ist die schlimmste Sorte Text: er klingt nach einer Auskunft
  /// und ist eine Vermutung.
  static Future<List<Map<String, dynamic>>?> hashtagBeitraegeErgebnis(
    String tag, {
    int limit = 50,
    int offset = 0,
  }) async {
    final sauber = normalisiereHashtagEingabe(tag);
    if (sauber.isEmpty) return const [];
    try {
      final rows = await _db.rpc(
        'hashtag_beitraege',
        params: {'p_tag': sauber, 'p_limit': limit, 'p_offset': offset},
      );
      if (rows is List) {
        return rows
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
      }
      return const [];
    } catch (e) {
      debugPrint('[SocialService] hashtag_beitraege Fehler: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> hashtagBeitraege(
    String tag, {
    int limit = 50,
    int offset = 0,
  }) async {
    final treffer = await hashtagBeitraegeErgebnis(
      tag,
      limit: limit,
      offset: offset,
    );
    return treffer ?? const [];
  }

  /// 2026-08-24 (Aufgabe 1.3): Vorschläge beim Tippen und beliebte Hashtags.
  ///
  /// Ohne [praefix] die häufigsten Hashtags im Zeitfenster, mit [praefix] die
  /// Vervollständigung. Gezählt wird über den gefalteten Schlüssel, angezeigt
  /// die zuletzt tatsächlich getippte Schreibweise.
  static Future<List<Map<String, dynamic>>> hashtagVorschlaege({
    String? praefix,
    int tage = 30,
    int limit = 10,
  }) async {
    try {
      final rows = await _db.rpc(
        'hashtag_vorschlaege',
        params: {
          'p_praefix': praefix == null || praefix.trim().isEmpty
              ? null
              : normalisiereHashtagEingabe(praefix),
          'p_tage': tage,
          'p_limit': limit,
        },
      );
      if (rows is List) {
        return rows
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
      }
    } catch (e) {
      debugPrint('[SocialService] hashtag_vorschlaege Fehler: $e');
    }
    return [];
  }

  // ── Wer benutzt diesen Hashtag? ───────────────────────────────────────
  //
  // 2026-08-24 — Vucko am 24.08.: „Aber da moechte ich das auch noch mit den
  // Hashtags so haben, dass wenn man einen #Bmw, #BayerischeMotorenWerke oder
  // sonstige, dass man sieht, wer alles so einen # benutzt hat. Also wenn ihn
  // schon 17 Leute benutzt haben, dann soll das moeglichst da noch drunter
  // stehen […] man soll drauf klicken koennen wie bei Instagram oder TikTok."
  //
  // WARUM NICHT `hashtag_vorschlaege` benutzt wird: die Spalte `anzahl` dort
  // zaehlt BEITRAEGE. Wer denselben Hashtag zehnmal schreibt, stuende dort
  // als „10". Vucko will aber „1 Person". Beide Zahlen sind richtig, sie
  // beantworten nur verschiedene Fragen — deshalb eigene Abfragen.
  //
  // #Bmw und #BayerischeMotorenWerke sind und bleiben ZWEI Hashtags. Die
  // Marken-Vereinheitlichung vom 24.08. gilt fuer das Fahrzeug-Markenfeld,
  // nicht hier. Gefaltet werden nur Gross-/Kleinschreibung und Umlaute, und
  // das macht die Datenbank (`hashtag_schluessel`).
  //
  // DIE NAMEN DER ABFRAGEN STEHEN HIER UND NUR HIER, und sie muessen zu
  // Migration 20260824120000_hashtag_personen_und_kennzahlen.sql passen:
  //
  //   hashtag_personen(p_tag, p_limit, p_offset)
  //     -> user_id, username, avatar_url, beitraege, zuletzt
  //   hashtag_kennzahlen(p_tag)
  //     -> tag, tag_schluessel, beitraege_anzahl, personen_anzahl,
  //        personen_sichtbar
  //
  // `personen_sichtbar` wird hier bewusst NICHT angezeigt. Die Zahl unter dem
  // Hashtag ist laut Migration die objektive (`personen_anzahl`, ohne
  // Blockfilter), damit nicht jeder eine andere Zahl sieht und man an einer
  // sinkenden Zahl ablesen koennte, dass einen jemand blockiert hat. Die
  // Liste selbst ist gefiltert; sie kann also in Einzelfaellen eine Zeile
  // weniger haben als die Zahl verspricht. Am 24.08. stehen 0 Zeilen in
  // `user_blocks`, der Fall existiert heute nicht.
  //
  // Ein Test vergleicht diese Namen mit der Migrationsdatei
  // (test/community/hashtag_leute_test.dart) und wird rot, wenn sie
  // auseinanderlaufen. Dieselbe Fehlerklasse wie bei der
  // Laender-Klassifikation.
  static const String rpcHashtagPersonen = 'hashtag_personen';
  static const String rpcHashtagKennzahlen = 'hashtag_kennzahlen';

  /// Die Leute, die einen Hashtag benutzt haben — die haeufigsten zuerst.
  ///
  /// `null` heisst FEHLER (kein Netz, Abfrage fehlt noch), `[]` heisst
  /// NIEMAND. Die Oberflaeche muss beides verschieden anzeigen: „keiner" ist
  /// eine Auskunft, „ich weiss es gerade nicht" ist keine.
  static Future<List<Map<String, dynamic>>?> hashtagPersonen(
    String tag, {
    int limit = 50,
    int offset = 0,
  }) async {
    final sauber = normalisiereHashtagEingabe(tag);
    if (sauber.isEmpty) return const [];
    try {
      final rows = await _db.rpc(
        rpcHashtagPersonen,
        params: {'p_tag': sauber, 'p_limit': limit, 'p_offset': offset},
      );
      if (rows is List) {
        return rows.whereType<Map>().map(hashtagPersonZeile).toList();
      }
      return const [];
    } catch (e) {
      debugPrint('[SocialService] $rpcHashtagPersonen Fehler: $e');
      return null;
    }
  }

  /// Die zwei Kopfzahlen ueber einem Hashtag. `null` heisst wieder FEHLER.
  ///
  /// Sie kommen bewusst NICHT aus der Laenge der geladenen Trefferliste: die
  /// ist gedeckelt. Wer bei 300 Beitraegen „200 Beitraege" anzeigt, luegt.
  static Future<HashtagKennzahlen?> hashtagKennzahlen(String tag) async {
    final sauber = normalisiereHashtagEingabe(tag);
    if (sauber.isEmpty) {
      return const HashtagKennzahlen(beitraege: 0, personen: 0);
    }
    try {
      final antwort = await _db.rpc(
        rpcHashtagKennzahlen,
        params: {'p_tag': sauber},
      );
      Map<dynamic, dynamic>? roh;
      if (antwort is List) {
        for (final zeile in antwort) {
          if (zeile is Map) {
            roh = zeile;
            break;
          }
        }
      } else if (antwort is Map) {
        roh = antwort;
      }
      if (roh == null) {
        return const HashtagKennzahlen(beitraege: 0, personen: 0);
      }
      return hashtagKennzahlenAusZeile(roh);
    } catch (e) {
      debugPrint('[SocialService] $rpcHashtagKennzahlen Fehler: $e');
      return null;
    }
  }

  /// Liest die Kopfzahlen aus einer Antwortzeile.
  ///
  /// Getrennt und oeffentlich, damit ein Test die Umsetzung pruefen kann,
  /// ohne eine Datenbank zu brauchen.
  static HashtagKennzahlen hashtagKennzahlenAusZeile(
    Map<dynamic, dynamic> roh,
  ) {
    final m = Map<String, dynamic>.from(roh);
    return HashtagKennzahlen(
      beitraege: _zahlAus(m, const [
        'beitraege_anzahl',
        'beitraege',
        'anzahl_beitraege',
        'anzahl',
      ]),
      personen: _zahlAus(m, const [
        'personen_anzahl',
        'personen',
        'anzahl_personen',
      ]),
    );
  }

  /// Bringt eine Zeile der Personen-Abfrage in die EINE Form, die die
  /// Oberflaeche kennt: `user_id`, `username`, `avatar_url`, `anzahl`.
  ///
  /// Die Spalte mit der Haeufigkeit kann je nach Bauart `anzahl`,
  /// `beitraege` oder `anzahl_beitraege` heissen. Hier faellt das zusammen.
  /// Sonst stuende bei einer abweichenden Benennung ueberall „0 Beitraege" —
  /// ein stiller Fehler, den kein Nutzer meldet, weil die Liste ja da ist.
  static Map<String, dynamic> hashtagPersonZeile(Map<dynamic, dynamic> roh) {
    final m = Map<String, dynamic>.from(roh);
    return <String, dynamic>{
      ...m,
      'user_id': m['user_id']?.toString(),
      'username': m['username']?.toString(),
      'avatar_url': m['avatar_url']?.toString(),
      'anzahl': _zahlAus(m, const ['beitraege', 'anzahl', 'anzahl_beitraege']),
    };
  }

  static int _zahlAus(Map<String, dynamic> zeile, List<String> schluessel) {
    for (final name in schluessel) {
      final wert = zeile[name];
      if (wert is num) return wert.toInt();
      if (wert is String) {
        final zahl = int.tryParse(wert.trim());
        if (zahl != null) return zahl;
      }
    }
    return 0;
  }

  /// Notbehelf: rechnet die Personen aus einer schon geladenen Trefferliste.
  ///
  /// Solange die Abfrage aus der Migration nicht da ist — oder der Aufruf
  /// scheitert — rechnet die App mit den Beitraegen, die sie ohnehin geladen
  /// hat. Das stimmt EXAKT, solange alle Beitraege geladen wurden (die Seite
  /// holt 200, in der Datenbank stehen am 24.08. zehn), und wird zu klein,
  /// sobald es mehr sind. Genau deshalb ist es der zweite Weg und nicht der
  /// erste.
  ///
  /// Sortiert wie die Abfrage: haeufigste zuerst, bei Gleichstand nach Name.
  /// Die zweite Stufe ist wichtig, damit die Liste bei lauter Einsern nicht
  /// bei jedem Laden anders aussieht.
  static List<Map<String, dynamic>> personenAusBeitraegen(
    List<Map<String, dynamic>> beitraege,
  ) {
    final nachPerson = <String, Map<String, dynamic>>{};
    for (final beitrag in beitraege) {
      final userId = beitrag['user_id']?.toString();
      if (userId == null || userId.isEmpty) continue;
      final vorhanden = nachPerson[userId];
      if (vorhanden == null) {
        nachPerson[userId] = <String, dynamic>{
          'user_id': userId,
          'username': beitrag['username']?.toString(),
          'avatar_url': beitrag['avatar_url']?.toString(),
          'anzahl': 1,
        };
      } else {
        vorhanden['anzahl'] = (vorhanden['anzahl'] as int) + 1;
        // Aeltere Beitraege koennen ein leeres Profil haben; die erste
        // brauchbare Angabe gewinnt.
        vorhanden['username'] ??= beitrag['username']?.toString();
        vorhanden['avatar_url'] ??= beitrag['avatar_url']?.toString();
      }
    }
    final liste = nachPerson.values.toList();
    liste.sort((a, b) {
      final nachAnzahl = (b['anzahl'] as int).compareTo(a['anzahl'] as int);
      if (nachAnzahl != 0) return nachAnzahl;
      final nameA = (a['username']?.toString() ?? '').toLowerCase();
      final nameB = (b['username']?.toString() ?? '').toLowerCase();
      final nachName = nameA.compareTo(nameB);
      if (nachName != 0) return nachName;
      return (a['user_id'] as String).compareTo(b['user_id'] as String);
    });
    return liste;
  }

  /// Schneidet führende Rauten und Leerzeichen weg.
  ///
  /// Die RPCs tun dasselbe noch einmal (`btrim(regexp_replace(…, '^#+', ''))`),
  /// hier steht es nur, damit die Oberfläche schon vor dem Abschicken weiß,
  /// ob überhaupt etwas übrig bleibt. Gefaltet wird hier NICHT — das ist
  /// Sache der Datenbank.
  static String normalisiereHashtagEingabe(String eingabe) {
    return eingabe.trim().replaceFirst(RegExp(r'^#+'), '').trim();
  }

  // ── User Search ───────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final sanitized = query.trim().replaceAll(RegExp(r'[%_\\,\.\(\)]'), '');
    if (sanitized.isEmpty) return [];

    final blocked = await getBlockedAndBlockerIds();
    // 2026-08-25 (Umlaute im Benutzernamen): Gesucht wird nach allen
    // Schreibweisen. Sonst findet, wer „mueller" tippt, den Nutzer „müller"
    // nicht — und damit auch nicht die Person, die er gleich erwaehnen will.
    // Die Sonderzeichen sind eine Zeile darueber schon herausgeschnitten,
    // die Bedingung kann also nicht aufbrechen.
    final bedingung = usernameSpellings(
      sanitized,
    ).map((wort) => 'username.ilike.%$wort%').join(',');
    final results = await _db
        .from('profiles')
        .select('id, username, avatar_url, is_private')
        .or(bedingung)
        .limit(20);

    final profiles = List<Map<String, dynamic>>.from(
      (results as List).where((row) {
        final id = (row as Map)['id'] as String?;
        return id != null && !blocked.contains(id);
      }),
    );

    final uid = _userId;
    if (uid == null || profiles.isEmpty) return profiles;

    final ids = profiles.map((profile) => profile['id']).whereType<String>();
    final followRows = await _db
        .from('follows')
        .select('following_id, status')
        .eq('follower_id', uid)
        .inFilter('following_id', ids.toList());
    final byUser = {
      for (final row in followRows as List)
        (row as Map)['following_id'] as String: row['status'] as String?,
    };
    for (final profile in profiles) {
      final id = profile['id'] as String?;
      profile['follow_status'] = id == null ? 'none' : byUser[id] ?? 'none';
    }
    return profiles;
  }

  /// Nutzer-Vorschläge: Freunde-von-Freunden, fallback neueste Nutzer.
  /// Wird vom Entdecken-Tab genutzt wenn man (noch) niemandem folgt.
  // ── Weggeklickte Vorschläge („X" auf der Karte) ──────────────────────────
  // Lokal persistiert (SharedPreferences). Format je Eintrag: 'id|epochMs'.
  //
  // 2026-08-11 (vucko „wenn man sie wegklickt, sollen wie bei Instagram neue
  // dazukommen — wir sind schon 93 Personen und es kann nicht sein, dass mir
  // eine Person vorgeschlagen wird"): Vorher war Wegklicken ENDGUELTIG. Bei
  // ~93 Nutzern erschoepft sich der Pool damit in Tagen — am Ende blieb genau
  // eine Person uebrig, jeden Tag dieselbe. Weggeklickte tauchen jetzt nach
  // [_dismissVerfall] wieder auf; Instagram macht es genauso. Alte Eintraege
  // ohne Zeitstempel gelten ab dem ersten Lesen als „gerade weggeklickt".
  static const String _dismissedSuggestionsKey = 'suggested_users_dismissed_v1';
  static const int _dismissedSuggestionsCap = 300;
  static const Duration _dismissVerfall = Duration(days: 14);

  static Future<Set<String>> getDismissedSuggestionIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final roh = prefs.getStringList(_dismissedSuggestionsKey) ?? const [];
      final jetzt = DateTime.now().millisecondsSinceEpoch;
      final frisch = <String>[];
      final ids = <String>{};
      var migriert = false;
      for (final eintrag in roh) {
        final trenner = eintrag.lastIndexOf('|');
        if (trenner < 0) {
          // Alt-Format ohne Zeitstempel: ab jetzt zaehlt die Uhr.
          frisch.add('$eintrag|$jetzt');
          ids.add(eintrag);
          migriert = true;
          continue;
        }
        final id = eintrag.substring(0, trenner);
        final wann = int.tryParse(eintrag.substring(trenner + 1)) ?? jetzt;
        if (jetzt - wann > _dismissVerfall.inMilliseconds) {
          // Verfallen: nicht mehr ausschliessen, Eintrag entfernen.
          migriert = true;
          continue;
        }
        frisch.add(eintrag);
        ids.add(id);
      }
      if (migriert) {
        await prefs.setStringList(_dismissedSuggestionsKey, frisch);
      }
      return ids;
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> dismissSuggestedUser(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_dismissedSuggestionsKey) ?? <String>[];
      list
        ..removeWhere((e) => e == userId || e.startsWith('$userId|'))
        ..add('$userId|${DateTime.now().millisecondsSinceEpoch}');
      final trimmed = list.length > _dismissedSuggestionsCap
          ? list.sublist(list.length - _dismissedSuggestionsCap)
          : list;
      await prefs.setStringList(_dismissedSuggestionsKey, trimmed);
    } catch (_) {
      // Best effort — ein verlorenes Dismissal ist kein Fehlerfall.
    }
  }

  static Future<List<Map<String, dynamic>>> getSuggestedUsers({
    int limit = 10,
  }) async {
    final uid = _userId;
    if (uid == null) return [];

    // IDs denen ich folge oder bei denen eine Anfrage offen ist ausschließen.
    // Blockierte/Blockierende ebenfalls (wie im Discover-Feed).
    final following = await _db
        .from('follows')
        .select('following_id, status')
        .eq('follower_id', uid);
    final blocked = await getBlockedAndBlockerIds();
    final acceptedFollowing = (following as List)
        .where((r) => (r as Map)['status'] == 'accepted')
        .map((r) => r['following_id'] as String)
        .toSet();
    final dismissed = await getDismissedSuggestionIds();
    final excluded = <String>{
      uid,
      ...blocked,
      ...dismissed,
      ...following.map((r) => (r as Map)['following_id'] as String),
    };

    // Reihenfolge bleibt stabil: erst Freunde-von-Freunden, dann Auffueller.
    final ergebnis = <String, Map<String, dynamic>>{};

    // 1) Freunde-von-Freunden. Die Zwischenperson (follower_id) ist genau der
    //    GEMEINSAME Follower — jemand, dem ich folge und der auch dem
    //    Vorschlag folgt. Damit bauen wir „@a, @b … folgen diesem Account".
    if (excluded.length > 1) {
      final myFollowingIds = acceptedFollowing.toList();
      final fof = await _db
          .from('follows')
          .select(
            'follower_id, profiles!follows_following_id_profiles_fkey(id, username, avatar_url, is_private)',
          )
          .inFilter('follower_id', myFollowingIds)
          .eq('status', 'accepted')
          .limit(200);

      final suggestions = <String, Map<String, dynamic>>{};
      // Vorschlags-ID -> Liste der gemeinsamen-Follower-IDs (meine Freunde).
      final mutualIds = <String, List<String>>{};
      for (final row in fof as List) {
        final p = (row as Map)['profiles'] as Map<String, dynamic>?;
        final id = p?['id'] as String?;
        final followerId = row['follower_id'] as String?;
        if (p == null || id == null || excluded.contains(id)) continue;
        suggestions.putIfAbsent(id, () => Map<String, dynamic>.from(p));
        if (followerId != null) {
          (mutualIds[id] ??= <String>[]).add(followerId);
        }
      }
      if (suggestions.isNotEmpty) {
        // Zufällige Auswahl aus dem GANZEN FoF-Pool statt immer derselben
        // ersten N — so rotieren die Vorschläge bei jedem Neuladen.
        final pool = suggestions.keys.toList()..shuffle();
        final taken = pool.take(limit).toList();
        // Usernames aller benötigten gemeinsamen Follower in EINER Query holen.
        final neededFollowerIds = <String>{};
        for (final sid in taken) {
          neededFollowerIds.addAll(mutualIds[sid] ?? const []);
        }
        final nameById = <String, String>{};
        if (neededFollowerIds.isNotEmpty) {
          final profs = await _db
              .from('profiles')
              .select('id, username')
              .inFilter('id', neededFollowerIds.toList());
          for (final r in profs as List) {
            final m = r as Map;
            final rid = m['id'] as String?;
            final uname = (m['username'] as String?)?.trim();
            if (rid != null && uname != null && uname.isNotEmpty) {
              nameById[rid] = uname;
            }
          }
        }
        for (final sid in taken) {
          final names = (mutualIds[sid] ?? const [])
              .map((fid) => nameById[fid])
              .whereType<String>()
              .toList();
          suggestions[sid]!['mutual_names'] = names;
          suggestions[sid]!['mutual_count'] = names.length;
        }
        // 2026-08-11 (vucko „mir wird den ganzen Tag nur EINE Person
        // angezeigt"): Genau hier lag es. Vorher kehrte der Freunde-von-
        // Freunden-Pfad an dieser Stelle ZURUECK — auch mit nur einem
        // einzigen Treffer. Bei einem duennen Netz (93 Nutzer) war das der
        // Normalfall: eine Person, jeden Tag dieselbe, und der Fallback mit
        // allen uebrigen Profilen lief nie. Jetzt wird gesammelt und unten
        // aufgefuellt, bis das Limit voll ist.
        for (final sid in taken) {
          ergebnis[sid] = suggestions[sid]!;
        }
      }
    }
    if (ergebnis.length >= limit) {
      return ergebnis.values.take(limit).toList();
    }

    // 2) Auffuellen: neueste Profile, LANDSLEUTE ZUERST (vucko: „mehr Profile
    // in der Umgebung"). WICHTIG: kein `.eq('is_private', false)` —
    // das warf auch alle Profile mit is_private=NULL (Alt-Accounts vor der
    // Spalte) raus und ließ die Vorschläge komplett leer. Private Profile
    // dürfen wie bei Instagram vorgeschlagen werden — „Folgen" wird für sie
    // automatisch zur Anfrage (followUser handhabt das über den Status).
    final recent = await _db
        .from('profiles')
        .select('id, username, avatar_url, is_private, country_code')
        .order('created_at', ascending: false)
        .limit(limit * 3 + excluded.length);

    // Eigenes Land fuer die „Umgebung"-Sortierung — ein winziger Lookup.
    String? meinLand;
    try {
      final ich = await _db
          .from('profiles')
          .select('country_code')
          .eq('id', uid)
          .maybeSingle();
      meinLand = ich?['country_code'] as String?;
    } catch (_) {
      meinLand = null;
    }

    final pool =
        (recent as List)
            .whereType<Map<String, dynamic>>()
            .where((p) => !excluded.contains(p['id']))
            .where((p) => !ergebnis.containsKey(p['id']))
            .toList()
          ..shuffle();
    // Landsleute nach vorne — stabile Sortierung erhaelt die Zufallsreihenfolge
    // innerhalb beider Gruppen.
    if (meinLand != null && meinLand.isNotEmpty) {
      final gleiche = pool.where((p) => p['country_code'] == meinLand);
      final andere = pool.where((p) => p['country_code'] != meinLand);
      pool
        ..clear()
        ..addAll(gleiche)
        ..addAll(andere);
    }
    for (final p in pool) {
      if (ergebnis.length >= limit) break;
      ergebnis[p['id'] as String] = p;
    }
    return ergebnis.values.take(limit).toList();
  }

  /// Baut die „gemeinsame Follower"-Zeile für Vorschlags-Karten (Instagram-
  /// Style) aus den mutual_names/mutual_count-Feldern von [getSuggestedUsers].
  /// Beispiele: „@a folgt diesem Account", „@a und @b folgen diesem Account",
  /// „@a, @b und weitere Personen folgen diesem Account". Null wenn keine.
  static String? mutualFollowersLine(Map<String, dynamic> user) {
    final names =
        (user['mutual_names'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final count = (user['mutual_count'] as int?) ?? names.length;
    if (count <= 0 || names.isEmpty) return null;
    final a = '@${names[0]}';
    if (count == 1) return '$a folgt diesem Account';
    final b = names.length > 1 ? '@${names[1]}' : a;
    if (count == 2) return '$a und $b folgen diesem Account';
    return '$a, $b und weitere Personen folgen diesem Account';
  }

  // ── Groups ────────────────────────────────────────────────────────────

  /// Gruppen, in denen ich Mitglied/Owner bin.
  /// Nur öffentliche Gruppen — private werden in der Profil-Ansicht gezeigt.
  /// Sortiert chronologisch nach `start_time` (nächstes Event zuerst).
  static Future<List<Map<String, dynamic>>> getMyGroups({
    bool publicOnly = true,
    bool includeClosed = false,
  }) async {
    final uid = _userId;
    if (uid == null) return [];

    final memberships = await _db
        .from('group_members')
        .select('group_id')
        .eq('user_id', uid);

    final groupIds = <String>{
      ...(memberships as List).map((m) => m['group_id'] as String),
    };
    if (groupIds.isEmpty) return [];

    var q = _db
        .from('groups')
        .select('*, group_members(user_id)')
        .inFilter('id', groupIds.toList());
    if (publicOnly) q = q.eq('is_public', true);

    final groups = await q;
    final list = List<Map<String, dynamic>>.from(groups);
    // 2026-06-25 (vucko): Abgeschlossene Gruppen (closed_at gesetzt) gehören
    // NUR in die Profil-Ansicht (mit „Abgeschlossen"-Banner) — nicht in die
    // Community-/Discover-Listen. Profil ruft mit includeClosed:true auf.
    if (!includeClosed) {
      list.removeWhere((g) => g['closed_at'] != null);
    }
    _sortByStartTime(list);
    return list;
  }

  /// Alle Gruppen (public + private), in denen der User Mitglied oder Owner ist.
  /// Für die Profil-Ansicht.
  static Future<List<Map<String, dynamic>>> getMyAllGroups() async {
    return getMyGroups(publicOnly: false, includeClosed: true);
  }

  /// Private Gruppen des Users — für die Profil-Ansicht.
  static Future<List<Map<String, dynamic>>> getMyPrivateGroups() async {
    final uid = _userId;
    if (uid == null) return [];

    final memberships = await _db
        .from('group_members')
        .select('group_id')
        .eq('user_id', uid);
    final groupIds = <String>{
      ...(memberships as List).map((m) => m['group_id'] as String),
    };
    if (groupIds.isEmpty) return [];

    final groups = await _db
        .from('groups')
        .select('*, group_members(user_id)')
        .inFilter('id', groupIds.toList())
        .eq('is_public', false);
    final list = List<Map<String, dynamic>>.from(groups);
    _sortByStartTime(list);
    return list;
  }

  /// Merker auf jeder Zeile: „die Entfernung hat der Server entschieden".
  ///
  /// 2026-08-24 (Aufgabe 3.1): Solange dieser Schlüssel gesetzt ist, darf die
  /// Oberfläche NICHT noch einmal nach Entfernung filtern. Sie würde sonst
  /// genau die Gruppen wegwerfen, die der Server bewusst drin gelassen hat:
  /// Gruppen ohne brauchbaren Startpunkt (`entfernung_m == null`).
  static const String umkreisServerseitigKey = 'umkreis_serverseitig';

  /// Öffentliche Gruppen, in denen der User weder Mitglied noch Owner ist.
  ///
  /// 2026-08-24 — Aufgabe 3.1. Vucko, Aufnahme 4 [00:24]: „wenn man jetzt in
  /// Süddeutschland wäre, dass Leute in Norddeutschland angezeigt werden und
  /// sonst nicht."
  ///
  /// GEMESSENER FEHLER, den das behebt: die alte Fassung holte `.limit(80)`
  /// und schnitt auf `.take(40)` ab — beides ENTFERNUNGSBLIND. Der
  /// Umkreisfilter lief erst danach in der Oberfläche. In der Gegenprobe der
  /// Migration 20260824103000 (100 fiktive Gruppen, 95 davon in
  /// Norddeutschland und frisch, 5 im Umkreis von 50 km um Bregenz und älter)
  /// ergab das:
  ///     limit(80) zuerst, dann 50-km-Filter  ->  0 Treffer
  ///     50-km-Filter zuerst                  ->  5 Treffer
  /// Der Nutzer las „keine Gruppen in deiner Nähe", während fünf in
  /// Reichweite standen. Genau Vuckos Norddeutschland-Beispiel.
  ///
  /// Deshalb entscheidet jetzt die RPC `gruppen_in_der_naehe`: sie filtert
  /// und sortiert nach Entfernung, BEVOR abgeschnitten wird. Das kann nur der
  /// Server, weil nur er alle Zeilen sieht.
  ///
  /// [radiusMeter] ist in METERN (die RPC heißt `p_radius_m`), der Regler in
  /// der Oberfläche zeigt Kilometer. `null` heißt „alle": kein Filter, aber
  /// weiter nach Entfernung sortiert, damit der Schnitt bei [limit] die
  /// nächstgelegenen behält statt irgendwelche.
  ///
  /// Ohne [lat]/[lng] wird nichts ausgeblendet. Wir blenden nichts aus, was
  /// wir nicht beurteilen können.
  static Future<List<Map<String, dynamic>>> getDiscoverGroups({
    double? lat,
    double? lng,
    double? radiusMeter,
    int limit = 40,
  }) async {
    final uid = _userId;
    if (uid == null) return [];

    try {
      final rows = await _db.rpc(
        'gruppen_in_der_naehe',
        params: {
          'p_lat': lat,
          'p_lng': lng,
          'p_radius_m': radiusMeter,
          'p_limit': limit,
        },
      );
      if (rows is List) {
        return rows
            .whereType<Map>()
            .map((row) => _entdeckenGruppeAusRpc(row))
            .toList();
      }
    } on PostgrestException catch (e) {
      // Eine Datenbank ohne die neue RPC darf die Entdecken-Liste nicht
      // leeren. Dann zählt der alte Weg — entfernungsblind, aber sichtbar.
      final fehlt =
          e.code == 'PGRST202' ||
          e.message.toLowerCase().contains('could not find the function') ||
          e.message.toLowerCase().contains('does not exist');
      if (!fehlt) {
        debugPrint('[SocialService] gruppen_in_der_naehe Fehler: ${e.message}');
      }
    } catch (e) {
      debugPrint('[SocialService] gruppen_in_der_naehe unerwartet: $e');
    }

    return _getDiscoverGroupsAlterWeg(uid: uid, limit: limit);
  }

  /// Baut die flache RPC-Zeile auf die Form zurück, die die Kachel-Widgets
  /// seit jeher lesen.
  ///
  /// 2026-08-24: Die RPC liefert `mitglieder_anzahl`, `gastgeber_username`
  /// und `gastgeber_avatar_url` — flach. Die Kacheln lesen dagegen
  /// `group_members` (nur die LÄNGE, siehe community_page.dart:1473 und
  /// :2567 sowie community_carousel_card.dart:806 und :851) und
  /// `profiles`. Diese Widgets gehören anderen Dateien; sie hier zu ändern
  /// wäre eine Baustelle mehr, ohne dass jemand etwas davon hätte.
  ///
  /// `group_members` wird deshalb als Liste der richtigen LÄNGE mit leeren
  /// Einträgen nachgebaut. Bewusst OHNE erfundene `user_id`: eine Liste, die
  /// so tut, als kenne sie die Mitglieder, wäre eine Lüge, und irgendwann
  /// liest jemand sie aus.
  static Map<String, dynamic> _entdeckenGruppeAusRpc(Map row) {
    final gruppe = Map<String, dynamic>.from(row);
    final anzahl = (gruppe['mitglieder_anzahl'] as num?)?.toInt() ?? 0;
    gruppe['group_members'] = List<Map<String, dynamic>>.generate(
      anzahl < 0 ? 0 : anzahl,
      (_) => <String, dynamic>{},
    );
    gruppe['profiles'] = <String, dynamic>{
      'id': gruppe['created_by'],
      'username': gruppe['gastgeber_username'],
      'avatar_url': gruppe['gastgeber_avatar_url'],
    };
    gruppe[umkreisServerseitigKey] = true;
    return gruppe;
  }

  /// Nur für Tests: der Rückbau ohne Datenbank prüfbar.
  @visibleForTesting
  static Map<String, dynamic> entdeckenGruppeAusRpcFuerTest(Map row) =>
      _entdeckenGruppeAusRpc(row);

  /// Entfernungstext für eine Kachel der Entdecken-Liste.
  ///
  /// 2026-08-24 (Aufgabe 3.1, ausdrückliche Vorgabe): `entfernung_m` darf
  /// null sein — die Gruppe hat keinen Startpunkt, oder der Nutzer hat keine
  /// Position freigegeben. Dann steht dort „Entfernung unbekannt", NIEMALS
  /// „0 km". Eine Null wäre die Behauptung, die Gruppe starte genau hier.
  ///
  /// Liefert null, wenn die Zeile gar nicht vom Server kommt (alter Weg) —
  /// dann zeigt die Kachel wie bisher keine Entfernung an, statt eine
  /// erfundene.
  static String? entfernungText(Map<String, dynamic> gruppe) {
    if (gruppe[umkreisServerseitigKey] != true) return null;
    final meter = (gruppe['entfernung_m'] as num?)?.toDouble();
    if (meter == null || meter.isNaN || meter.isNegative) {
      return 'Entfernung unbekannt';
    }
    if (meter < 950) {
      // Unter einem Kilometer auf 100 m gerundet, sonst stünde dort „0 km".
      final hundert = (meter / 100).round() * 100;
      if (hundert <= 0) return 'unter 100 m entfernt';
      return '$hundert m entfernt';
    }
    final km = meter / 1000.0;
    if (km < 10) return '${km.toStringAsFixed(1)} km entfernt';
    return '${km.round()} km entfernt';
  }

  /// Der Weg vor dem 24.08.2026. Bleibt als Rückfallebene bestehen, falls die
  /// RPC auf einer Datenbank fehlt (alter Stand, Wiederherstellung).
  /// ENTFERNUNGSBLIND — deshalb setzt er [umkreisServerseitigKey] NICHT, und
  /// die Oberfläche filtert dann wie früher selbst nach.
  static Future<List<Map<String, dynamic>>> _getDiscoverGroupsAlterWeg({
    required String uid,
    required int limit,
  }) async {
    final blocked = await getBlockedAndBlockerIds();

    // 2026-08-11 (vucko, Home-Kacheln): Bewusst KEIN select('*') mehr.
    // Das zog fuer bis zu 80 Gruppen die vollen Routengeometrien
    // (route_data, current_route_data) mit — mehrere hundert Kilobyte, die
    // hier niemand liest. Die Fahrtroute kommt ausschliesslich ueber
    // CruiseGroupService.fetch, wenn man einer Gruppe wirklich beitritt.
    // Neu dabei: avatar_url des Gastgebers, damit die Kacheln ein Gesicht
    // zeigen koennen — das kostet nichts extra.
    final groups = await _db
        .from('groups')
        .select(
          'id, name, created_by, is_active, is_public, closed_at, start_time, '
          'start_location, route_name, stats, time_location, max_people, '
          'invite_code, created_at, '
          'group_members(user_id), '
          'profiles:created_by(id, username, avatar_url)',
        )
        .eq('is_public', true)
        .eq('is_active', false)
        .isFilter('closed_at', null) // 2026-06-25 (vucko): abgeschlossene raus
        .limit(80);

    final list = List<Map<String, dynamic>>.from(groups);
    list.removeWhere((g) => blocked.contains(g['created_by']));

    // Ausfiltern: Gruppen in denen ich Mitglied ODER Owner bin.
    final filtered = list.where((g) {
      if (g['is_active'] == true) return false;
      if (g['created_by'] == uid) return false;
      final members = (g['group_members'] as List?) ?? const [];
      return !members.any((m) => (m as Map)['user_id'] == uid);
    }).toList();

    _sortByStartTime(filtered);
    return filtered.take(limit < 1 ? 1 : limit).toList();
  }

  /// Entfernt Gruppen, deren Route gestartet wurde und deren 24h-Fenster
  /// abgelaufen ist (Backup, falls pg_cron-Cleanup noch nicht gelaufen ist).
  static void _filterExpired(List<Map<String, dynamic>> list) {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    list.removeWhere((g) {
      final activated = DateTime.tryParse(g['activated_at'] as String? ?? '');
      return activated != null && activated.isBefore(cutoff);
    });
  }

  /// Sortiert Gruppen fuer die Entdecken-Liste in drei Eimern.
  ///
  /// 2026-08-11 (vucko „man soll nicht zwingend eine Uhrzeit einstellen
  /// muessen"): Seit die Startzeit optional ist, gibt es Gruppen ohne Zeit.
  /// Die alte Sortierung schob sie ans ENDE — und weil die Liste bei
  /// `.limit(80)` / `.take(40)` abschneidet, waeren spontane Gruppen faktisch
  /// unsichtbar gewesen. Das haette das Feature still totgelegt.
  ///
  /// Reihenfolge jetzt:
  ///   0  terminiert und noch bevorstehend  (naechster Termin zuerst)
  ///   1  spontan, ohne Zeit                (neueste zuerst)
  ///   2  Termin bereits vorbei             (zuletzt)
  /// Nur fuer Tests: die Sortierregel ohne Datenbank pruefbar machen.
  @visibleForTesting
  static void sortiereFuerTest(List<Map<String, dynamic>> list) =>
      _sortByStartTime(list);

  static void _sortByStartTime(List<Map<String, dynamic>> list) {
    _filterExpired(list);
    final jetzt = DateTime.now();

    DateTime? startzeit(Map<String, dynamic> g) =>
        DateTime.tryParse(g['start_time'] as String? ?? '');

    int eimer(Map<String, dynamic> g) {
      final dt = startzeit(g);
      if (dt == null) return 1;
      return dt.isBefore(jetzt) ? 2 : 0;
    }

    /// Fuer spontane Gruppen zaehlt das Anlagedatum.
    DateTime schluessel(Map<String, dynamic> g) =>
        startzeit(g) ??
        DateTime.tryParse(g['created_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);

    list.sort((a, b) {
      final ea = eimer(a);
      final eb = eimer(b);
      if (ea != eb) return ea.compareTo(eb);
      // Bevorstehende: frueheste zuerst. Spontane und vergangene: neueste
      // zuerst — was gerade entstand, ist am ehesten noch relevant.
      return ea == 0
          ? schluessel(a).compareTo(schluessel(b))
          : schluessel(b).compareTo(schluessel(a));
    });
  }

  /// Nur der Owner darf löschen (RLS erzwingt das zusätzlich).
  static Future<void> deleteGroup(String groupId) async {
    await _db.from('groups').delete().eq('id', groupId);
  }

  static Future<void> createGroup({
    required String name,
    String? routeName,
    String? stats,
    String? timeLocation,
    String? description,
  }) async {
    final uid = _userId;
    if (uid == null) return;
    final cleanName = name.trim();
    final cleanDescription = description?.trim();
    if (cleanName.isEmpty ||
        cleanName.length > AppInputLimits.groupNameMaxLength) {
      throw const SocialServiceException('Gruppenname ist ungültig.');
    }
    if ((cleanDescription?.length ?? 0) >
        AppInputLimits.groupDescriptionMaxLength) {
      throw const SocialServiceException('Gruppenbeschreibung ist zu lang.');
    }
    if ((routeName?.trim().length ?? 0) >
            AppInputLimits.groupRouteNameMaxLength ||
        (stats?.trim().length ?? 0) > AppInputLimits.groupStatsMaxLength ||
        (timeLocation?.trim().length ?? 0) >
            AppInputLimits.groupTimeLocationMaxLength) {
      throw const SocialServiceException('Gruppendetails sind zu lang.');
    }

    await _db
        .from('groups')
        .insert({
          'created_by': uid,
          'name': cleanName,
          'route_name': routeName?.trim(),
          'stats': stats?.trim(),
          'time_location': timeLocation?.trim(),
          'description': cleanDescription?.isEmpty == true
              ? null
              : cleanDescription,
        })
        .select('id')
        .single();
  }

  static Future<void> joinGroup(String groupId) async {
    final uid = _userId;
    if (uid == null) return;

    final group = await _db
        .from('groups')
        .select('created_by, is_active, group_members(user_id)')
        .eq('id', groupId)
        .maybeSingle();
    final creatorId = (group as Map?)?['created_by'] as String?;
    final isActive = (group as Map?)?['is_active'] == true;
    final members = ((group as Map?)?['group_members'] as List?) ?? const [];
    final isAlreadyMember = members.any((m) => (m as Map)['user_id'] == uid);
    final blocked = await getBlockedAndBlockerIds();
    if (creatorId != null && blocked.contains(creatorId)) {
      throw const SocialServiceException('Diese Gruppe ist nicht verfügbar.');
    }
    if (isActive && !isAlreadyMember) {
      throw const SocialServiceException(
        'Die Session läuft bereits oder wurde schon beendet.',
      );
    }

    try {
      // 2026-08-09 (vucko): ride_role nur beim ERSTEN Beitritt setzen. Vorher
      // hat jeder erneute Beitritt (z. B. nach einem Netzabbruch) die in der
      // Lobby gewaehlte Rolle stillschweigend auf „Fahrer" zurueckgesetzt —
      // die Mitfahrerin stand danach wieder als eigenes Auto auf der Karte.
      await _db.from('group_members').upsert({
        'group_id': groupId,
        'user_id': uid,
        if (!isAlreadyMember) 'ride_role': 'driver',
      }, onConflict: 'group_id,user_id');
    } on PostgrestException catch (e) {
      if (isDuplicateGroupMemberError(e)) {
        return;
      }
      if (e.code == '42501') {
        throw const SocialServiceException(
          'Die Session läuft bereits oder wurde schon beendet.',
        );
      }
      throw SocialServiceException(e.message);
    }
    if (!isAlreadyMember) {
      await _notifyGroupOwners(groupId, type: 'group_joined', fromUserId: uid);
    }
  }

  static Future<void> leaveGroup(String groupId) async {
    final uid = _userId;
    if (uid == null) return;

    await _db
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', uid);
    // 2026-06-10 (vucko Gruppen-Trip-Regel): Verlässt das LETZTE Mitglied die
    // Gruppe, endet der Gruppen-Trip (zweite Ende-Bedingung neben
    // Zielerreichung). Best-effort — darf das Verlassen nie blockieren.
    try {
      final remaining = await _db
          .from('group_members')
          .select('user_id')
          .eq('group_id', groupId)
          .limit(1);
      if ((remaining as List).isEmpty) {
        await _db
            .from('trips')
            .update({
              'status': 'completed',
              'finished_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('group_id', groupId)
            .inFilter('status', ['active', 'paused']);
      }
    } catch (_) {}
  }

  static Future<void> removeGroupMember(String groupId, String userId) async {
    await _db
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', userId);
  }

  /// Prüft, ob der aktuelle User in der Gruppe die Rolle 'owner' hat.
  static Future<bool> isOwner(String groupId) async {
    final uid = _userId;
    if (uid == null) return false;
    final row = await _db
        .from('group_members')
        .select('role')
        .eq('group_id', groupId)
        .eq('user_id', uid)
        .maybeSingle();
    return (row as Map?)?['role'] == 'owner';
  }

  /// Zählt Owner der Gruppe, ohne den angegebenen User.
  /// Wird genutzt, um beim Verlassen zu entscheiden, ob die Gruppe
  /// gelöscht werden muss (nur wenn kein weiterer Owner übrig bleibt).
  static Future<int> countOtherOwners(String groupId, String excludeUid) async {
    final rows = await _db
        .from('group_members')
        .select('user_id')
        .eq('group_id', groupId)
        .eq('role', 'owner')
        .neq('user_id', excludeUid);
    return (rows as List).length;
  }

  static Future<bool> isMember(String groupId) async {
    final uid = _userId;
    if (uid == null) return false;

    final result = await _db
        .from('group_members')
        .select('id')
        .eq('group_id', groupId)
        .eq('user_id', uid)
        .maybeSingle();

    return result != null;
  }

  // ── Group Invite-Codes & Join-Requests ────────────────────────────────

  /// Normalisiert Codes wie 'cc7k9m2x' oder 'cc 7k9m2x' zu 'CC-7K9M2X'.
  static String? _normalizeInviteCode(String raw) {
    final cleaned = raw.trim().toUpperCase().replaceAll(RegExp(r'[\s\-_]'), '');
    if (cleaned.length < 3 || !cleaned.startsWith('CC')) return null;
    final body = cleaned.substring(2);
    if (body.length != 6) return null;
    if (!RegExp(r'^[A-Z2-9]{6}$').hasMatch(body)) return null;
    return 'CC-$body';
  }

  /// Sucht Gruppe per Invite-Code. Gibt null zurück, wenn Format/Code ungültig.
  static Future<Map<String, dynamic>?> findGroupByCode(String rawCode) async {
    final code = _normalizeInviteCode(rawCode);
    if (code == null) return null;
    try {
      final rpcRow = await _db.rpc(
        'find_group_by_code',
        params: {'p_code': code},
      );
      if (rpcRow is Map) {
        final map = Map<String, dynamic>.from(rpcRow);
        final creatorId = map['created_by'] as String?;
        final blocked = await getBlockedAndBlockerIds();
        if (creatorId != null && blocked.contains(creatorId)) return null;
        map['_join_code'] = code;
        return map;
      }
    } catch (e) {
      debugPrint('[SocialService] find_group_by_code RPC fallback: $e');
    }

    try {
      final row = await _db
          .from('groups')
          .select(
            '*, group_members(user_id), profiles:created_by(id, username)',
          )
          .eq('invite_code', code)
          .maybeSingle();
      if (row == null) return null;
      final map = Map<String, dynamic>.from(row as Map);
      final creatorId = map['created_by'] as String?;
      final blocked = await getBlockedAndBlockerIds();
      if (creatorId != null && blocked.contains(creatorId)) return null;
      map['_join_code'] = code;
      return map;
    } catch (e) {
      debugPrint('[SocialService] findGroupByCode Fehler: $e');
      return null;
    }
  }

  static Future<String> joinGroupWithCode(String rawCode) async {
    final code = _normalizeInviteCode(rawCode);
    if (code == null) {
      throw const SocialServiceException('Code ungültig.');
    }

    try {
      final result = await _db.rpc(
        'join_group_with_code',
        params: {'p_code': code},
      );
      final groupId = result as String;
      // 2026-08-09 (vucko): Frueher wurde hier ride_role='driver' nachgetragen.
      // Das war doppelt gemoppelt (die Spalte hat den Default 'driver', die RPC
      // legt die Zeile also ohnehin als Fahrer an) und hat beim erneuten
      // Beitritt die in der Lobby gewaehlte „Mitfahrer"-Rolle ueberschrieben.
      return groupId;
    } on PostgrestException catch (e) {
      throw SocialServiceException(e.message);
    }
  }

  /// Join-Request für eine (private) Gruppe anlegen.
  /// Für öffentliche Gruppen sollte direkt joinGroup() genutzt werden.
  static Future<void> requestJoinGroup(
    String groupId, {
    String? message,
  }) async {
    final uid = _userId;
    if (uid == null) return;
    final group = await _db
        .from('groups')
        .select('is_active')
        .eq('id', groupId)
        .maybeSingle();
    if ((group as Map?)?['is_active'] == true) {
      throw Exception('Diese Fahrt läuft bereits.');
    }
    await _db.from('group_join_requests').upsert({
      'group_id': groupId,
      'user_id': uid,
      'status': 'pending',
      'message': message,
    }, onConflict: 'group_id,user_id');
  }

  /// Prüft, ob der aktuelle User einen offenen (pending) Request hat.
  static Future<bool> hasPendingJoinRequest(String groupId) async {
    final uid = _userId;
    if (uid == null) return false;
    final row = await _db
        .from('group_join_requests')
        .select('status')
        .eq('group_id', groupId)
        .eq('user_id', uid)
        .eq('status', 'pending')
        .maybeSingle();
    return row != null;
  }

  /// Zieht einen offenen Join-Request zurück.
  static Future<void> cancelJoinRequest(String groupId) async {
    final uid = _userId;
    if (uid == null) return;
    await _db
        .from('group_join_requests')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', uid);
  }

  /// Listet alle offenen Join-Requests der Gruppe (Owner-Sicht).
  static Future<List<Map<String, dynamic>>> listPendingJoinRequests(
    String groupId,
  ) async {
    try {
      final rows = await _db
          .from('group_join_requests')
          .select(
            'id, message, created_at, user_id, '
            'profiles:user_id(id, username, avatar_url)',
          )
          .eq('group_id', groupId)
          .eq('status', 'pending')
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('[SocialService] listPendingJoinRequests Fehler: $e');
      return [];
    }
  }

  /// Owner akzeptiert einen Join-Request (atomar via RPC).
  static Future<void> acceptJoinRequest(String requestId) async {
    await _db.rpc('accept_group_join_request', params: {'req_id': requestId});
  }

  /// Owner lehnt einen Join-Request ab.
  static Future<void> rejectJoinRequest(String requestId) async {
    await _db.rpc('reject_group_join_request', params: {'req_id': requestId});
  }

  // ── Notifications ─────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getNotifications() async {
    final uid = _userId;
    if (uid == null) return [];
    final blocked = await getBlockedAndBlockerIds();

    final results = await _db
        .from('notifications')
        .select(
          '*, profiles!notifications_from_user_id_profiles_fkey(id, username, avatar_url)',
        )
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(50);

    return List<Map<String, dynamic>>.from(results as List).where((row) {
      final fromId = row['from_user_id'] as String?;
      return fromId == null || !blocked.contains(fromId);
    }).toList();
  }

  static Future<int> getUnreadCount() async {
    final uid = _userId;
    if (uid == null) return 0;
    final blocked = await getBlockedAndBlockerIds();

    final results = await _db
        .from('notifications')
        .select('id, from_user_id')
        .eq('user_id', uid)
        .eq('read', false);

    return (results as List).where((row) {
      final fromId = (row as Map)['from_user_id'] as String?;
      return fromId == null || !blocked.contains(fromId);
    }).length;
  }

  static Future<void> markAllRead() async {
    final uid = _userId;
    if (uid == null) return;

    await _db
        .from('notifications')
        .update({'read': true})
        .eq('user_id', uid)
        .eq('read', false);
  }

  // ── Profile ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final profile = await _db
          .from('profiles')
          .select(_profileSelect)
          .eq('id', userId)
          .maybeSingle();
      return profile;
    } on PostgrestException catch (e) {
      if ((e.code == 'PGRST204' || e.code == '42703') &&
          (e.message.contains('car_country_code') ||
              e.message.contains('bio_title') ||
              e.message.contains('badge_showcase'))) {
        final profile = await _db
            .from('profiles')
            .select(_legacyProfileSelect)
            .eq('id', userId)
            .maybeSingle();
        debugPrint(
          '[Social] car_country_code-Spalte fehlt, Legacy-Profil geladen. Migration ausführen!',
        );
        return profile;
      }
      debugPrint('[Social] Profil-Abfrage fehlgeschlagen: $e');
      return null;
    } catch (e) {
      debugPrint('[Social] Profil-Abfrage fehlgeschlagen: $e');
      return null;
    }
  }

  /// Mindestabstand zwischen zwei Username-Änderungen.
  static const Duration usernameChangeCooldown = Duration(days: 30);

  /// Prüft serverseitig, ob der eingeloggte User den Username gerade ändern
  /// darf. Ist das `username_changed_at`-Feld weniger als 30 Tage her,
  /// ist `canChange == false` und `nextChange` zeigt das Datum.
  static Future<({bool canChange, DateTime? nextChange})>
  canChangeUsername() async {
    final uid = _userId;
    if (uid == null) return (canChange: false, nextChange: null);
    try {
      // 2026-06-27 (vucko): Server-RPC statt client-seitiger Rechnung mit
      // DateTime.now() — der 30-Tage-Lock basiert auf Server-Zeit `now()` und
      // ist damit NICHT per Handy-Datum manipulierbar.
      final raw = await _db.rpc<dynamic>('username_change_status');
      final m = (raw as Map?)?.cast<String, dynamic>() ?? const {};
      final nextStr = m['next_change_at'] as String?;
      final next = nextStr != null ? DateTime.tryParse(nextStr) : null;
      return (canChange: m['can_change'] == true, nextChange: next);
    } catch (e) {
      debugPrint('[Social] canChangeUsername Fehler: $e');
      // Bei Fehler defensiv sperren — der Server (Trigger) schützt ohnehin.
      return (canChange: false, nextChange: null);
    }
  }

  /// Aktualisiert die freien Profil-Felder. Username-Änderungen werden hier
  /// NICHT durchgeführt — dafür [updateUsername] verwenden (mit Cooldown-Check).
  ///
  /// Robustheit: einzelne fehlende Spalten (z.B. `link` ohne Migration)
  /// brechen den Update nicht ab; betroffene Spalten werden weggelassen
  /// und die Operation einmal retried.
  static Future<void> updateProfile({
    String? bioTitle,
    String? bio,
    String? link,
    bool? isPrivate,
  }) async {
    final uid = _userId;
    if (uid == null) return;
    final patch = <String, dynamic>{};
    if (bioTitle != null) {
      final cleaned = bioTitle.trim();
      if (cleaned.length > AppInputLimits.bioTitleMaxLength) {
        throw const SocialServiceException('Die Überschrift deiner Bio ist zu lang.');
      }
      patch['bio_title'] = cleaned.isEmpty ? null : cleaned;
    }
    if (bio != null) {
      final cleaned = bio.trim();
      if (cleaned.length > AppInputLimits.bioMaxLength) {
        throw const SocialServiceException('Bio ist zu lang.');
      }
      patch['bio'] = cleaned;
    }
    if (link != null) {
      final cleaned = link.trim();
      if (cleaned.length > AppInputLimits.linkMaxLength) {
        throw const SocialServiceException('Link ist zu lang.');
      }
      patch['link'] = cleaned;
    }
    if (isPrivate != null) patch['is_private'] = isPrivate;
    if (patch.isEmpty) return;
    try {
      await _db.from('profiles').update(patch).eq('id', uid);
    } on PostgrestException catch (e) {
      // PGRST204: Column not found in schema cache — Migration noch nicht da?
      if ((e.code == 'PGRST204' || e.code == '42703') &&
          (e.message.contains('link') || e.message.contains('bio_title'))) {
        if (e.message.contains('bio_title')) patch.remove('bio_title');
        patch.remove('link');
        if (patch.isEmpty) return;
        await _db.from('profiles').update(patch).eq('id', uid);
        debugPrint(
          '[Social] updateProfile: link-Spalte fehlt, übersprungen. Migration ausführen!',
        );
      } else {
        rethrow;
      }
    }
  }

  static Future<void> updateBadgeShowcase(List<Object?> badgeEntries) async {
    final uid = _userId;
    if (uid == null) return;
    final used = <String>{};
    final usedSpots = <int>{};
    final cleaned = <Object>[];
    for (var i = 0; i < badgeEntries.take(5).length; i++) {
      final raw = badgeEntries[i];
      final id = raw is Map
          ? raw['id']?.toString().trim() ?? ''
          : raw?.toString().trim() ?? '';
      if (id.isEmpty || !used.add(id)) {
        cleaned.add(<String, dynamic>{});
      } else {
        var spot = _badgeShowcaseSpot(raw is Map ? raw['spot'] : null, i);
        if (!usedSpots.add(spot)) {
          spot = _firstFreeBadgeShowcaseSpot(usedSpots);
          usedSpots.add(spot);
        }
        cleaned.add({
          'id': id,
          'spot': spot,
          'x': _badgeShowcaseSpotX(spot),
          'y': _badgeShowcaseSpotY(spot),
          'scale': _badgeShowcaseSpotScale(spot),
        });
      }
    }
    while (cleaned.length < 5) {
      cleaned.add(<String, dynamic>{});
    }
    await _db
        .from('profiles')
        .update({'badge_showcase': cleaned})
        .eq('id', uid);
  }

  static int _badgeShowcaseSpot(Object? value, int slot) {
    final parsed = value is int
        ? value
        : value is num
        ? value.round()
        : value is String
        ? int.tryParse(value)
        : null;
    if (parsed != null && parsed >= 0 && parsed < 10) return parsed;
    return switch (slot) {
      0 => 0,
      1 => 1,
      2 => 2,
      3 => 6,
      _ => 8,
    };
  }

  static int _firstFreeBadgeShowcaseSpot(Set<int> usedSpots) {
    for (var spot = 0; spot < 10; spot++) {
      if (!usedSpots.contains(spot)) return spot;
    }
    return 0;
  }

  static double _badgeShowcaseSpotX(int spot) {
    return switch (spot) {
      0 => 0.36,
      1 => 0.50,
      2 => 0.64,
      3 => 0.80,
      4 => 0.93,
      5 => 0.36,
      6 => 0.48,
      7 => 0.92,
      8 => 0.76,
      _ => 0.93,
    };
  }

  static double _badgeShowcaseSpotY(int spot) {
    return switch (spot) {
      0 => 0.14,
      1 => 0.10,
      2 => 0.15,
      3 => 0.13,
      4 => 0.22,
      5 => 0.36,
      6 => 0.50,
      7 => 0.42,
      8 => 0.78,
      _ => 0.78,
    };
  }

  static double _badgeShowcaseSpotScale(int spot) {
    return switch (spot) {
      0 => 0.72,
      1 => 0.70,
      2 => 0.72,
      3 => 0.70,
      4 => 0.66,
      5 => 0.66,
      6 => 0.64,
      7 => 0.64,
      8 => 0.66,
      _ => 0.64,
    };
  }

  /// Username ändern. Wirft `StateError`, wenn der Cooldown noch läuft.
  /// Setzt `username_changed_at = now()`, damit der Cooldown beginnt.
  /// Ändert den @-Namen über den server-seitigen, manipulationssicheren RPC
  /// `set_username` (Format + globale Eindeutigkeit + 30-Tage-Lock, alles mit
  /// Server-Zeit `now()` — nicht per Handy-Datum umgehbar; ein Guard-Trigger
  /// blockt direkte UPDATEs). Wirft [UsernameChangeException] mit klarem Grund.
  static Future<void> updateUsername(String newUsername) async {
    final res = await setUsername(newUsername);
    if (res.ok) return;
    throw UsernameChangeException(
      res.error ?? 'unknown',
      daysRemaining: res.daysRemaining,
    );
  }

  /// Roher RPC-Aufruf `set_username` → strukturiertes Ergebnis (für Onboarding +
  /// Profil-Bearbeitung). ok=true => übernommen; sonst error in
  /// {invalid_format, reserved, taken, too_soon, not_authenticated}.
  static Future<UsernameSetResult> setUsername(String newUsername) async {
    final cleaned = newUsername.trim();
    final raw = await _db.rpc<dynamic>(
      'set_username',
      params: {'p_username': cleaned},
    );
    final m = (raw as Map?)?.cast<String, dynamic>() ?? const {};
    return UsernameSetResult(
      ok: m['ok'] == true,
      username: m['username'] as String?,
      error: m['error'] as String?,
      daysRemaining: (m['days_remaining'] as num?)?.toInt(),
    );
  }

  /// Live-Verfügbarkeits-Check über `username_available` (Format + Reserved +
  /// globale Eindeutigkeit, eigener Name ausgenommen). reason in
  /// {ok, invalid_format, reserved, taken}.
  static Future<({bool available, String reason})> isUsernameAvailable(
    String candidate,
  ) async {
    try {
      final raw = await _db.rpc<dynamic>(
        'username_available',
        params: {'p_username': candidate.trim()},
      );
      final m = (raw as Map?)?.cast<String, dynamic>() ?? const {};
      return (
        available: m['available'] == true,
        reason: (m['reason'] as String?) ?? 'unknown',
      );
    } catch (e) {
      debugPrint('[Social] isUsernameAvailable Fehler: $e');
      return (available: false, reason: 'error');
    }
  }

  /// Anzeigename (ohne @) — frei + beliebig oft änderbar.
  static Future<void> setDisplayName(String name) async {
    final uid = _userId;
    if (uid == null) return;
    final cleaned = name.trim();
    if (cleaned.length > AppInputLimits.usernameMaxLength * 2) {
      throw const SocialServiceException('Anzeigename ist zu lang.');
    }
    await _db
        .from('profiles')
        .update({'display_name': cleaned.isEmpty ? null : cleaned})
        .eq('id', uid);
  }

  /// Lädt ein Profilbild (Bytes, bereits zugeschnitten) hoch und setzt
  /// `avatar_url`. Gibt die Public-URL zurück (oder null bei Fehler).
  static Future<String?> uploadAvatar(Uint8List bytes) async {
    final uid = _userId;
    if (uid == null) return null;
    final url = await uploadUserAsset(
      bucket: 'avatars',
      bytes: bytes,
      fileName: 'avatar.jpg',
      contentType: 'image/jpeg',
    );
    if (url == null) return null;
    // 2026-08-24 (vucko): Der Upload selbst ist seit #179 begrenzt (25 s, drei
    // Versuche) — das Nachtragen der URL ins Profil war es nicht. Genau daran
    // wartet der Onboarding-Schritt „Profilbild" mit gesperrten Knoepfen.
    try {
      await _db
          .from('profiles')
          .update({'avatar_url': url})
          .eq('id', uid)
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      debugPrint('[Social] uploadAvatar: avatar_url nicht gesetzt: $e');
      return null;
    }
    return url;
  }

  /// Schreibt Onboarding-Stammdaten (Region/Land/Sprache) + markiert das
  /// Onboarding als abgeschlossen. Username/Anzeigename laufen über ihre
  /// eigenen Methoden.
  static Future<void> completeOnboarding({
    String? countryCode,
    String? region,
    String? language,
  }) async {
    final uid = _userId;
    if (uid == null) return;
    final patch = <String, dynamic>{'onboarding_completed': true};
    if (countryCode != null && countryCode.trim().isNotEmpty) {
      patch['country_code'] = countryCode.trim().toUpperCase();
    }
    if (region != null && region.trim().isNotEmpty) {
      patch['region'] = region.trim();
    }
    if (language != null && language.trim().isNotEmpty) {
      patch['app_language'] = language.trim();
    }
    await _db.from('profiles').update(patch).eq('id', uid);
  }

  /// True, wenn der eingeloggte User das Onboarding noch durchlaufen muss.
  ///
  /// 2026-08-24 (vucko): Zeitgrenze, weil an dieser einen Abfrage das
  /// Post-Auth-Tor haengt — der Bildschirm, den JEDER Nutzer nach JEDER
  /// Anmeldung sieht. Ohne Grenze drehte sich dort bei schlechtem Netz ein
  /// Ladekreis ohne Ende, und es gab keinen Weg zurueck.
  ///
  /// Ein Haenger wird BEWUSST nicht wie ein Fehler behandelt: Fehler haben
  /// eine Antwort und fallen defensiv auf false (= App, kein erzwungenes
  /// Onboarding). Eine abgelaufene Zeitgrenze heisst „wir wissen nichts" —
  /// die `TimeoutException` geht deshalb an den Aufrufer durch, damit der dem
  /// Nutzer die Wahl lassen kann, statt ihn still am Onboarding vorbeizulotsen.
  static Future<bool> needsOnboarding({
    Duration zeitgrenze = const Duration(seconds: 12),
  }) async {
    final uid = _userId;
    if (uid == null) return false;
    try {
      final row = await _db
          .from('profiles')
          .select('onboarding_completed')
          .eq('id', uid)
          .maybeSingle()
          .timeout(zeitgrenze);
      return (row as Map?)?['onboarding_completed'] != true;
    } on TimeoutException {
      debugPrint('[Social] needsOnboarding Zeitgrenze ($zeitgrenze) erreicht');
      rethrow;
    } catch (e) {
      debugPrint('[Social] needsOnboarding Fehler: $e');
      return false;
    }
  }

  /// Speichert das Auto-Profil (Stammdaten) auf den eingeloggten User.
  /// Felder mit `null` werden NICHT überschrieben.
  static Future<void> updateCarProfile({
    String? brand,
    String? name,
    int? topSpeed,
    double? engineSize,
    int? displacement,
    int? cylinders,
    int? horsepower,
    int? year,
    String? firstReg,
    int? mileage,
    String? countryCode,
    String? imageUrl,
  }) async {
    final uid = _userId;
    if (uid == null) return;
    final patch = <String, dynamic>{};
    if (brand != null) {
      patch['car_brand'] = brand.trim().isEmpty ? null : brand.trim();
    }
    if (name != null) {
      patch['car_name'] = name.trim().isEmpty ? null : name.trim();
    }
    if (topSpeed != null) patch['car_top_speed'] = topSpeed;
    if (engineSize != null) patch['car_engine_size'] = engineSize;
    if (displacement != null) patch['car_displacement'] = displacement;
    if (cylinders != null) patch['car_cylinders'] = cylinders;
    if (horsepower != null) patch['car_horsepower'] = horsepower;
    if (year != null) patch['car_year'] = year;
    if (firstReg != null) {
      patch['car_first_reg'] = firstReg.trim().isEmpty ? null : firstReg.trim();
    }
    if (mileage != null) patch['car_mileage'] = mileage;
    if (countryCode != null) {
      final cleaned = countryCode.trim().toUpperCase();
      patch['car_country_code'] = cleaned.isEmpty ? null : cleaned;
    }
    if (imageUrl != null) patch['car_image_url'] = imageUrl;
    if (patch.isEmpty) return;
    try {
      await _db.from('profiles').update(patch).eq('id', uid);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204' && e.message.contains('car_country_code')) {
        patch.remove('car_country_code');
        if (patch.isEmpty) return;
        await _db.from('profiles').update(patch).eq('id', uid);
        debugPrint(
          '[Social] updateCarProfile: car_country_code-Spalte fehlt, übersprungen. Migration ausführen!',
        );
        return;
      }
      rethrow;
    }
  }

  static Map<String, dynamic>? legacyVehicleFromProfile(
    Map<String, dynamic>? profile,
  ) {
    if (profile == null) return null;
    final vehicle = <String, dynamic>{
      'vehicle_type': 'car',
      'brand': profile['car_brand'],
      'model': profile['car_name'],
      'description': null,
      'tuning_details': null,
      'drivetrain': null,
      'country_code': profile['car_country_code'],
      'top_speed': profile['car_top_speed'],
      'engine_size': profile['car_engine_size'],
      'displacement': profile['car_displacement'],
      'cylinders': profile['car_cylinders'],
      'horsepower': profile['car_horsepower'],
      'year': profile['car_year'],
      'first_reg': profile['car_first_reg'],
      'mileage': profile['car_mileage'],
      'image_url': profile['car_image_url'],
      'sort_order': 0,
      'is_primary': true,
    };
    final hasData = vehicle.entries.any((entry) {
      if (entry.key == 'vehicle_type' ||
          entry.key == 'sort_order' ||
          entry.key == 'is_primary') {
        return false;
      }
      final value = entry.value;
      if (value is String) return value.trim().isNotEmpty;
      return value != null;
    });
    return hasData ? vehicle : null;
  }

  static Future<List<Map<String, dynamic>>> getUserVehicles(
    String userId,
  ) async {
    try {
      final rows = await _db
          .from('profile_vehicles')
          .select()
          .eq('user_id', userId)
          .order('sort_order', ascending: true)
          .order('created_at', ascending: true);
      final vehicles = List<Map<String, dynamic>>.from(rows as List);
      if (vehicles.isNotEmpty) return vehicles;

      final profile = await getUserProfile(userId);
      final legacy = legacyVehicleFromProfile(profile);
      return legacy == null ? [] : [legacy];
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' ||
          e.code == 'PGRST204' ||
          e.message.contains('profile_vehicles')) {
        final profile = await getUserProfile(userId);
        final legacy = legacyVehicleFromProfile(profile);
        debugPrint(
          '[Social] profile_vehicles fehlt, nutze Legacy-Fahrzeug. Migration ausführen!',
        );
        return legacy == null ? [] : [legacy];
      }
      rethrow;
    } catch (e) {
      debugPrint('[Social] Fahrzeuge laden fehlgeschlagen: $e');
      return [];
    }
  }

  static Future<void> saveUserVehicles(
    List<Map<String, dynamic>> vehicles,
  ) async {
    final uid = _userId;
    if (uid == null) return;

    final cleaned = <Map<String, dynamic>>[];
    for (var i = 0; i < vehicles.length; i++) {
      final vehicle = _cleanVehicleForDb(vehicles[i], uid, i);
      if (_vehicleHasData(vehicle)) cleaned.add(vehicle);
    }

    final primary = cleaned.isEmpty ? null : cleaned.first;
    await updateCarProfile(
      brand: primary?['brand'] as String?,
      name: primary?['model'] as String?,
      countryCode: primary?['country_code'] as String?,
      topSpeed: (primary?['top_speed'] as num?)?.toInt(),
      engineSize: (primary?['engine_size'] as num?)?.toDouble(),
      displacement: (primary?['displacement'] as num?)?.toInt(),
      cylinders: (primary?['cylinders'] as num?)?.toInt(),
      horsepower: (primary?['horsepower'] as num?)?.toInt(),
      year: (primary?['year'] as num?)?.toInt(),
      firstReg: primary?['first_reg'] as String?,
      mileage: (primary?['mileage'] as num?)?.toInt(),
      imageUrl: primary?['image_url'] as String?,
    );

    try {
      await _db.from('profile_vehicles').delete().eq('user_id', uid);
      if (cleaned.isNotEmpty) {
        await _db.from('profile_vehicles').insert(cleaned);
      }
    } on PostgrestException catch (e) {
      if ((e.code == 'PGRST204' || e.code == '42703') &&
          (e.message.contains('drivetrain') ||
              e.message.contains('zero_to_hundred_seconds') ||
              e.message.contains('tuning_details'))) {
        final compatible = cleaned
            .map(
              (vehicle) => Map<String, dynamic>.from(vehicle)
                ..remove('drivetrain')
                ..remove('zero_to_hundred_seconds')
                ..remove('tuning_details'),
            )
            .toList();
        await _db.from('profile_vehicles').delete().eq('user_id', uid);
        if (compatible.isNotEmpty) {
          await _db.from('profile_vehicles').insert(compatible);
        }
        debugPrint(
          '[Social] saveUserVehicles: optionale Fahrzeug-Spalten fehlen, kompatibel gespeichert. Migration ausführen!',
        );
        return;
      }
      if (e.code == 'PGRST205' ||
          e.code == 'PGRST204' ||
          e.message.contains('profile_vehicles')) {
        debugPrint(
          '[Social] saveUserVehicles: profile_vehicles fehlt, nur Legacy-Fahrzeug gespeichert.',
        );
        return;
      }
      rethrow;
    }
  }

  static Map<String, dynamic> _cleanVehicleForDb(
    Map<String, dynamic> raw,
    String uid,
    int index,
  ) {
    String? cleanText(dynamic value, {int? maxLength}) {
      final text = (value as String?)?.trim();
      if (text == null || text.isEmpty) return null;
      if (maxLength != null && text.length > maxLength) {
        return text.substring(0, maxLength);
      }
      return text;
    }

    String? cleanDescription(dynamic value) {
      final text = cleanText(value);
      if (text == null) return null;
      return text.length <= AppInputLimits.vehicleDescriptionMaxLength
          ? text
          : text.substring(0, AppInputLimits.vehicleDescriptionMaxLength);
    }

    double? cleanZeroToHundred(dynamic value) {
      final seconds = (value as num?)?.toDouble();
      if (seconds == null) return null;
      return seconds.clamp(0, 99.9).toDouble();
    }

    final type = cleanText(raw['vehicle_type']) == 'motorcycle'
        ? 'motorcycle'
        : 'car';
    return {
      'user_id': uid,
      'vehicle_type': type,
      'brand': cleanText(
        raw['brand'],
        maxLength: AppInputLimits.shortTextMaxLength,
      ),
      'model': cleanText(
        raw['model'],
        maxLength: AppInputLimits.shortTextMaxLength,
      ),
      'description': cleanDescription(raw['description']),
      'tuning_details': cleanDescription(raw['tuning_details']),
      'drivetrain': cleanText(raw['drivetrain'], maxLength: 12),
      'country_code': cleanText(raw['country_code'])?.toUpperCase(),
      'top_speed': (raw['top_speed'] as num?)?.toInt(),
      'zero_to_hundred_seconds': cleanZeroToHundred(
        raw['zero_to_hundred_seconds'],
      ),
      'engine_size': (raw['engine_size'] as num?)?.toDouble(),
      'displacement': (raw['displacement'] as num?)?.toInt(),
      'cylinders': (raw['cylinders'] as num?)?.toInt(),
      'horsepower': (raw['horsepower'] as num?)?.toInt(),
      'year': (raw['year'] as num?)?.toInt(),
      'first_reg': cleanText(raw['first_reg']),
      'mileage': (raw['mileage'] as num?)?.toInt(),
      'image_url': cleanText(raw['image_url']),
      'sort_order': index,
      'is_primary': index == 0,
    };
  }

  static bool _vehicleHasData(Map<String, dynamic> vehicle) {
    const ignored = {'user_id', 'vehicle_type', 'sort_order', 'is_primary'};
    return vehicle.entries.any((entry) {
      if (ignored.contains(entry.key)) return false;
      final value = entry.value;
      if (value is String) return value.trim().isNotEmpty;
      return value != null;
    });
  }

  /// Lädt ein Bild in einen beliebigen Storage-Bucket des aktuellen Users.
  /// Pfad wird `<uid>/<filename>.<ext>` (RLS-freundlich, weil
  /// `auth.uid()::text = (storage.foldername(name))[1]`).
  /// Returns: Public-URL mit Cache-Buster.
  static Future<String?> uploadUserAsset({
    required String bucket,
    required Uint8List bytes,
    required String fileName,
    String? contentType,
  }) async {
    final uid = _userId;
    if (uid == null) return null;
    final path = '$uid/$fileName';
    // 2026-06-25 (vucko #179): Upload gegen transiente Netzfehler härten — bis
    // zu 3 Versuche mit Timeout + kurzem Backoff. Vorher reichte EIN Fehlschlag
    // und das Foto „verschwand" still (Fahrt wurde ohne Bild gespeichert). Gibt
    // bei endgültigem Scheitern null zurück (statt zu werfen), damit der Aufrufer
    // sauber „fehlgeschlagen" melden kann statt in einen generischen Catch zu laufen.
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await _db.storage
            .from(bucket)
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(upsert: true, contentType: contentType),
            )
            .timeout(const Duration(seconds: 25));
        final publicUrl = _db.storage.from(bucket).getPublicUrl(path);
        return '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      } catch (e) {
        lastError = e;
        debugPrint(
          '[Social] Upload-Versuch $attempt/3 fehlgeschlagen ($path): $e',
        );
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
      }
    }
    debugPrint('[Social] Upload endgültig fehlgeschlagen ($path): $lastError');
    return null;
  }

  /// 2026-08-23 (Auftrag Vucko, Sprachnachricht): „...dass man für Communities
  /// wirklich auch Profilbilder reintun kann..."
  ///
  /// Zwillingsfunktion zu [uploadUserAsset], bewusst DANEBEN statt darin:
  /// [uploadUserAsset] wird an fünf Stellen benutzt (Avatar, Banner,
  /// Fahrzeug-Foto, Fahrt-Foto, Feedback-Bild) und legt den Pfad hart auf
  /// `<uid>/...`, weil alle bestehenden Storage-Regeln
  /// `auth.uid()::text = (storage.foldername(name))[1]` verlangen.
  ///
  /// Für Communities geht das nicht: `is_community_admin` prüft die ROLLE in
  /// `community_members`, nicht `communities.owner_id`. Gemessen am
  /// 23.08.2026 hat „Has.Crew" ZWEI Zeilen mit `role = 'owner'`. Läge das Bild
  /// unter `<uid>/`, könnte Admin B das Bild von Admin A nie ersetzen. Der
  /// Ordner ist deshalb die COMMUNITY-Kennung, passend zu den Regeln
  /// `community_images_hochladen_admin` und `..._ersetzen_admin`.
  ///
  /// Härtung identisch zum Vorbild: bis zu 3 Versuche, 25 s Timeout,
  /// wachsender Backoff, Cache-Buster an der Public-URL. Gibt bei
  /// endgültigem Scheitern null zurück, damit der Aufrufer eine ehrliche
  /// deutsche Meldung zeigen kann statt einer rohen Ausnahme.
  static Future<String?> uploadCommunityAsset({
    required String communityId,
    required Uint8List bytes,
    required String fileName,
    String? contentType,
  }) async {
    final cleanId = communityId.trim();
    if (cleanId.isEmpty) return null;
    final path = '$cleanId/$fileName';

    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await _db.storage
            .from(communityImagesBucket)
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(upsert: true, contentType: contentType),
            )
            .timeout(const Duration(seconds: 25));
        final publicUrl = _db.storage
            .from(communityImagesBucket)
            .getPublicUrl(path);
        return '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      } catch (e) {
        lastError = e;
        debugPrint(
          '[Social] Community-Upload-Versuch $attempt/3 fehlgeschlagen ($path): $e',
        );
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
      }
    }
    debugPrint(
      '[Social] Community-Upload endgültig fehlgeschlagen ($path): $lastError',
    );
    return null;
  }

  /// Entfernt ein Community-Bild wieder aus dem Bucket. Best-effort wie
  /// [deleteUserAsset]: wirft nie, damit ein Storage-Fehler das Speichern der
  /// Zeile nicht blockiert.
  static Future<bool> deleteCommunityAsset({required String publicUrl}) async {
    final path = storagePathFromPublicUrl(communityImagesBucket, publicUrl);
    if (path == null) return false;
    try {
      await _db.storage.from(communityImagesBucket).remove([path]);
      return true;
    } catch (e) {
      debugPrint(
        '[Social] Community-Storage-Cleanup fehlgeschlagen ($path): $e',
      );
      return false;
    }
  }

  /// Extrahiert den Storage-Pfad (`<uid>/<datei>`) aus einer Public-URL eines
  /// Buckets (Cache-Buster `?t=` wird abgeschnitten). Für Vergleich + Löschen.
  static String? storagePathFromPublicUrl(String bucket, String publicUrl) {
    final marker = '/object/public/$bucket/';
    final idx = publicUrl.indexOf(marker);
    if (idx < 0) return null;
    var path = publicUrl.substring(idx + marker.length);
    final q = path.indexOf('?');
    if (q >= 0) path = path.substring(0, q);
    path = Uri.decodeComponent(path);
    return path.isEmpty ? null : path;
  }

  /// Löscht eine zuvor via [uploadUserAsset] hochgeladene Datei wieder aus dem
  /// Bucket — anhand ihrer Public-URL. So bleibt KEIN verwaister Storage-Müll
  /// zurück, wenn der User ein Foto entfernt oder durch ein neues ersetzt.
  /// RLS erlaubt das Löschen eigener Dateien (`<uid>/...`). Best-effort: wirft
  /// nie, ein Fehlschlag darf den UI-Flow nicht blockieren.
  static Future<bool> deleteUserAsset({
    required String bucket,
    required String publicUrl,
  }) async {
    final path = storagePathFromPublicUrl(bucket, publicUrl);
    if (path == null) return false;
    try {
      await _db.storage.from(bucket).remove([path]);
      return true;
    } catch (e) {
      debugPrint('[Social] Storage-Cleanup fehlgeschlagen ($path): $e');
      return false;
    }
  }

  /// Persistiert die Public-URL mit Cache-Buster im jeweiligen
  /// Profil-Feld — für Avatar oder Banner.
  static Future<void> updateProfileImageUrl({
    required String column,
    required String publicUrl,
  }) async {
    final uid = _userId;
    if (uid == null) return;
    await _db.from('profiles').update({column: publicUrl}).eq('id', uid);
  }

  static Future<Map<String, dynamic>> getProfileStats(String userId) async {
    final followers = await getFollowerCount(userId);
    final following = await getFollowingCount(userId);

    final profile = await getUserProfile(userId);

    return {
      'id': userId,
      'follower_count': followers,
      'following_count': following,
      'username': profile?['username'],
      'avatar_url': profile?['avatar_url'],
      'banner_url': profile?['banner_url'],
      'bio_title': profile?['bio_title'],
      'bio': profile?['bio'],
      'link': profile?['link'],
      'created_at': profile?['created_at'],
      'level': profile?['level'] ?? 1,
      'total_km': profile?['total_km'] ?? 0,
      'total_routes': profile?['total_routes'] ?? 0,
      'badges': profile?['badges'] ?? [],
      'badge_showcase': profile?['badge_showcase'] ?? [],
      'is_private': profile?['is_private'] ?? false,
      'car_brand': profile?['car_brand'],
      'car_name': profile?['car_name'],
      'car_country_code': profile?['car_country_code'],
      'car_top_speed': profile?['car_top_speed'],
      'car_engine_size': profile?['car_engine_size'],
      'car_displacement': profile?['car_displacement'],
      'car_cylinders': profile?['car_cylinders'],
      'car_horsepower': profile?['car_horsepower'],
      'car_year': profile?['car_year'],
      'car_first_reg': profile?['car_first_reg'],
      'car_mileage': profile?['car_mileage'],
      'car_image_url': profile?['car_image_url'],
    };
  }

  // ── Group Invites ───────────────────────────────────────────────────

  /// 2026-08-23 (vucko, Sprachnachricht: „wenn er eine Gruppe erstellt hat und
  /// er einen anderen einlaedt"): Die Einladung laeuft jetzt ueber die RPC
  /// `invite_to_group` statt ueber einen direkten Insert in `notifications`.
  ///
  /// Zwei Gruende, beide gemessen:
  /// 1. Der Gruppenname fehlte. Gelesen wird `payload['group_name']`
  ///    (notification_service.dart:327-329 und
  ///    supabase/functions/send-push/index.ts:178-184), geschrieben hat ihn
  ///    nie jemand. Beide Einladungen aus dem Vorfall vom 21.08. haben
  ///    payload = {}. In der Glocke stand deshalb immer „laedt dich zu einer
  ///    Gruppe ein". Die RPC traegt den Namen ein.
  /// 2. Niemand hat geprueft, WER einlaedt. Die INSERT-Policy auf
  ///    `notifications` verlangt nur `from_user_id = auth.uid()`. Seit die
  ///    Lese-Policy auf `groups` einen Zweig fuer Eingeladene hat, haette sich
  ///    damit jeder selbst Lesezugang zu einer fremden privaten Gruppe
  ///    verschaffen koennen. Die RPC verlangt jetzt, dass der Einladende
  ///    selbst Gastgeber oder Mitglied ist.
  ///
  /// Fuer die Bedienung aendert sich nichts: Der Einladen-Knopf in der Lobby
  /// steht ohnehin nur Mitgliedern offen (`_amMember && !g.isActive`).
  static Future<void> inviteToGroup(String groupId, String targetUserId) async {
    final uid = _userId;
    if (uid == null) return;

    try {
      await _db.rpc(
        'invite_to_group',
        params: {'p_group_id': groupId, 'p_user_id': targetUserId},
      );
    } on PostgrestException catch (e) {
      // Die RPC bringt fertige deutsche Saetze mit („Nur der Gastgeber darf
      // zu dieser Gruppe einladen.", „Die Fahrt läuft bereits ...").
      throw SocialServiceException(e.message);
    }
  }

  static Future<Map<String, dynamic>?> getProfilePreview(String userId) async {
    try {
      final profile = await _db
          .from('profiles')
          .select('id, username, avatar_url, is_private')
          .eq('id', userId)
          .maybeSingle();
      return profile;
    } catch (e) {
      debugPrint('[Social] Profil-Preview fehlgeschlagen: $e');
      return null;
    }
  }

  static Future<void> _notifyGroupOwners(
    String groupId, {
    required String type,
    required String fromUserId,
  }) async {
    try {
      final owners = await _db
          .from('group_members')
          .select('user_id')
          .eq('group_id', groupId)
          .eq('role', 'owner');
      final targets = (owners as List)
          .map((r) => (r as Map)['user_id'] as String?)
          .whereType<String>()
          .where((id) => id != fromUserId)
          .toSet();
      if (targets.isEmpty) return;
      await _db.from('notifications').insert([
        for (final target in targets)
          {
            'user_id': target,
            'from_user_id': fromUserId,
            'type': type,
            'reference_id': groupId,
          },
      ]);
    } catch (e) {
      debugPrint('[Social] Group-Owner-Notification fehlgeschlagen: $e');
    }
  }

  // ── Blocking & Reporting ─────────────────────────────────────────────────

  /// Erlaubte Reason-Codes für Reports (müssen mit DB-Check übereinstimmen).
  static const reportReasons = <String, String>{
    'spam': 'Spam oder Werbung',
    'harassment': 'Belästigung / Mobbing',
    'hate_speech': 'Hassrede',
    'sexual_content': 'Sexueller Inhalt',
    'violence': 'Gewalt',
    'self_harm': 'Selbstverletzung',
    'illegal': 'Illegaler Inhalt',
    'other': 'Sonstiges',
  };

  /// IDs aller User, die ich blockiert habe ODER die mich blockiert haben.
  /// Wird vom Feed/Discover als Filter genutzt — beide Richtungen sollen
  /// füreinander unsichtbar sein.
  static Future<Set<String>> getBlockedAndBlockerIds() async {
    final uid = _userId;
    if (uid == null) return {};
    try {
      final rows = await _db.rpc('blocked_user_ids');
      return {
        for (final row in rows as List)
          if ((row as Map)['user_id'] case final String id) id,
      };
    } catch (e) {
      debugPrint('[Social] getBlockedAndBlockerIds: $e');
      return {};
    }
  }

  /// IDs, die ich aktiv blockiert habe (für Block-Liste im Profil).
  static Future<List<Map<String, dynamic>>> getBlockedUsers() async {
    final uid = _userId;
    if (uid == null) return [];
    try {
      final rows = await _db
          .from('user_blocks')
          .select(
            'blocked_id, created_at, profiles!user_blocks_blocked_id_fkey(id, username, avatar_url)',
          )
          .eq('blocker_id', uid)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('[Social] getBlockedUsers: $e');
      return [];
    }
  }

  static Future<bool> isBlocking(String targetUserId) async {
    final uid = _userId;
    if (uid == null) return false;
    final row = await _db
        .from('user_blocks')
        .select('blocker_id')
        .eq('blocker_id', uid)
        .eq('blocked_id', targetUserId)
        .maybeSingle();
    return row != null;
  }

  /// Blockt einen User über die SECURITY-DEFINER RPC `block_user`. Diese
  /// entfernt zusätzlich beidseitige Follow-Beziehungen.
  static Future<void> blockUser(String targetUserId) async {
    await _db.rpc('block_user', params: {'target': targetUserId});
  }

  static Future<void> unblockUser(String targetUserId) async {
    await _db.rpc('unblock_user', params: {'target': targetUserId});
  }

  /// Sendet einen Report. Mindestens eines von [postId], [commentId] oder
  /// [reportedUserId] muss gesetzt sein. Server-side check via RPC.
  static Future<void> submitReport({
    required String reason,
    String? reportedUserId,
    String? postId,
    String? commentId,
    String? details,
  }) async {
    await _db.rpc(
      'submit_content_report',
      params: {
        'p_reason': reason,
        'p_reported_user_id': reportedUserId,
        'p_post_id': postId,
        'p_comment_id': commentId,
        'p_details': details,
      },
    );
  }
}
