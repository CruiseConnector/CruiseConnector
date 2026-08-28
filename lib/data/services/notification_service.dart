import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cruise_connect/data/services/notification_settings_service.dart';

/// Zentrale Notification-Verwaltung mit Realtime-Subscription.
///
/// Architektur:
///   1. fetch() lädt initiale Liste via Supabase REST + JOIN auf profiles
///   2. subscribeRealtime() öffnet Channel auf notifications-Tabelle,
///      filtert auf user_id=currentUser, dispatcht onNew callback
///   3. ChangeNotifier-Pattern: UI hört via Provider/AnimatedBuilder
///
/// Kein OS-Push (APN/FCM) — In-App-Toast + Badge sind MVP.
/// Falls Toast gewünscht: onNew-Callback im UI-Layer hooken.
class NotificationService extends ChangeNotifier {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  SupabaseClient get _supabase => Supabase.instance.client;

  final List<AppNotification> _items = [];
  RealtimeChannel? _channel;
  bool _initialLoaded = false;

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((n) => !n.read).length;
  bool get isLoaded => _initialLoaded;

  /// Optional Callback wenn neue Notification während Session reinkommt.
  /// UI hookt hier für TopToast.
  ValueChanged<AppNotification>? onNew;

  Future<void> loadInitial() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final rows = await _supabase
          .from('notifications')
          .select(
              'id, created_at, user_id, from_user_id, type, read, reference_id, '
              'payload, aggregate_count, aggregate_until, '
              'from_profile:profiles!from_user_id(username, avatar_url)')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      _items
        ..clear()
        ..addAll(rows.map<AppNotification>(AppNotification.fromMap));
      _initialLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[NotificationService] loadInitial failed: $e');
    }
  }

  Future<void> startRealtime() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await stopRealtime();
    _channel = _supabase
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: _handleRealtimeInsert,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: _handleRealtimeUpdate,
        );
    _channel?.subscribe();
  }

  Future<void> stopRealtime() async {
    if (_channel != null) {
      await _supabase.removeChannel(_channel!);
      _channel = null;
    }
  }

  void _handleRealtimeInsert(PostgresChangePayload payload) {
    try {
      final notif = AppNotification.fromMap(payload.newRecord);
      _items.insert(0, notif);
      notifyListeners();
      // 2026-05-23 (vucko): User-Settings filtern — Toast nur wenn
      // dieser Typ aktiviert ist. Eintrag bleibt in der Inbox.
      if (NotificationSettingsService.instance.isTypeEnabled(notif.type)) {
        onNew?.call(notif);
      }
    } catch (e) {
      debugPrint('[NotificationService] realtime insert parse failed: $e');
    }
  }

  void _handleRealtimeUpdate(PostgresChangePayload payload) {
    try {
      final rec = payload.newRecord;
      final id = rec['id'] as String?;
      if (id == null) return;
      final idx = _items.indexWhere((n) => n.id == id);
      if (idx < 0) return;
      // 2026-07-10 (vucko Avatar-Fix): Das Realtime-WAL-Payload ist single-table
      // und enthält NICHT das in loadInitial gejointe from_profile
      // (username/avatar_url). Würde man das Item komplett aus fromMap(newRecord)
      // neu bauen, wäre fromAvatarUrl=null → der Avatar fällt beim „Alle gelesen"
      // /Öffnen bis zum App-Neustart auf das Platzhalter-Symbol zurück. Deshalb
      // NUR die tatsächlich geänderten Felder (read/aggregate) auf das bestehende
      // Item mergen und Avatar + Name behalten.
      final merged = _items[idx].copyWith(
        read: rec['read'] as bool?,
        aggregateCount: (rec['aggregate_count'] as num?)?.toInt(),
        aggregateUntil: rec['aggregate_until'] == null
            ? null
            : DateTime.tryParse(rec['aggregate_until'] as String),
      );
      _items[idx] = merged;
      notifyListeners();
      // Aggregierte Likes triggern auch ein UI-Refresh
      if (merged.aggregateCount > 1) {
        onNew?.call(merged);
      }
    } catch (e) {
      debugPrint('[NotificationService] realtime update parse failed: $e');
    }
  }

  Future<void> markAsRead(String id) async {
    final idx = _items.indexWhere((n) => n.id == id);
    if (idx < 0) return;
    _items[idx] = _items[idx].copyWith(read: true);
    notifyListeners();
    try {
      await _supabase.from('notifications').update({'read': true}).eq('id', id);
    } catch (e) {
      debugPrint('[NotificationService] markAsRead failed: $e');
    }
  }

  Future<void> markAllAsRead() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final hadUnread = _items.any((n) => !n.read);
    if (!hadUnread) return;
    for (var i = 0; i < _items.length; i++) {
      if (!_items[i].read) _items[i] = _items[i].copyWith(read: true);
    }
    notifyListeners();
    try {
      await _supabase
          .from('notifications')
          .update({'read': true})
          .eq('user_id', userId)
          .eq('read', false);
    } catch (e) {
      debugPrint('[NotificationService] markAllAsRead failed: $e');
    }
  }

  Future<void> delete(String id) async {
    _items.removeWhere((n) => n.id == id);
    notifyListeners();
    try {
      await _supabase.from('notifications').delete().eq('id', id);
    } catch (e) {
      debugPrint('[NotificationService] delete failed: $e');
    }
  }
}

/// Value-Object für eine Notification inkl. JOIN auf from-Profile.
class AppNotification {
  final String id;
  final DateTime createdAt;
  final String userId;
  final String fromUserId;
  final String type;
  final bool read;
  final String? referenceId;
  final Map<String, dynamic> payload;
  final int aggregateCount;
  final DateTime? aggregateUntil;
  final String? fromUsername;
  final String? fromAvatarUrl;

  AppNotification({
    required this.id,
    required this.createdAt,
    required this.userId,
    required this.fromUserId,
    required this.type,
    required this.read,
    required this.referenceId,
    required this.payload,
    required this.aggregateCount,
    required this.aggregateUntil,
    required this.fromUsername,
    required this.fromAvatarUrl,
  });

  AppNotification copyWith({
    bool? read,
    int? aggregateCount,
    DateTime? aggregateUntil,
  }) =>
      AppNotification(
        id: id,
        createdAt: createdAt,
        userId: userId,
        fromUserId: fromUserId,
        type: type,
        read: read ?? this.read,
        referenceId: referenceId,
        payload: payload,
        aggregateCount: aggregateCount ?? this.aggregateCount,
        aggregateUntil: aggregateUntil ?? this.aggregateUntil,
        fromUsername: fromUsername,
        fromAvatarUrl: fromAvatarUrl,
      );

  factory AppNotification.fromMap(Map<String, dynamic> m) {
    final fromProfile = m['from_profile'] as Map<String, dynamic>?;
    return AppNotification(
      id: m['id'] as String,
      createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
          DateTime.now(),
      userId: m['user_id'] as String,
      fromUserId: m['from_user_id'] as String? ?? '',
      type: m['type'] as String,
      read: (m['read'] as bool?) ?? false,
      referenceId: m['reference_id'] as String?,
      payload: (m['payload'] as Map<String, dynamic>?) ?? const {},
      aggregateCount: ((m['aggregate_count'] ?? 1) as num).toInt(),
      aggregateUntil: m['aggregate_until'] == null
          ? null
          : DateTime.tryParse(m['aggregate_until'] as String),
      fromUsername: fromProfile?['username'] as String?,
      fromAvatarUrl: fromProfile?['avatar_url'] as String?,
    );
  }

  /// Liefert (title, body) für UI je nach type.
  ///
  /// 2026-05-24 (vucko): Variantenpool pro Type für Push-Notification-
  /// Vielfalt. Pro Notification deterministisch (gleicher Index für
  /// gleiche notification.id) — User sieht nicht zweimal denselben Text
  /// und alle Notifications haben einen frischen Anstrich.
  (String title, String body) renderTexts() {
    // 2026-06-25 (vucko): Immer den @Namen des Auslösers zeigen — z.B.
    // „@vucko hat deinen Post geliked". Nur wenn wirklich kein Username da ist,
    // Fallback auf „Jemand".
    final name = (fromUsername != null && fromUsername!.trim().isNotEmpty)
        ? '@${fromUsername!.trim()}'
        : 'Jemand';
    // Deterministischer Index pro Notification — gleiche ID → gleicher Text.
    final variantIdx = id.hashCode.abs();
    String pick(List<String> options) =>
        options[variantIdx % options.length];

    switch (type) {
      case 'follow':
        // 2026-07-10 (vucko): immer der echte @Name, nie „Cruiser"/„Jemand".
        return (
          pick(const [
            'Neuer Follower',
            'Du hast einen Follower',
          ]),
          pick([
            '$name folgt dir jetzt',
            '$name ist jetzt einer deiner Follower',
          ]),
        );
      case 'like':
        if (aggregateCount > 1) {
          return (
            '$aggregateCount neue Likes',
            pick([
              '$name und ${aggregateCount - 1} weitere haben deinen Post geliked',
              '$name + ${aggregateCount - 1} feiern deinen Post',
            ]),
          );
        }
        return (
          pick(const ['Neuer Like', 'Post gefällt']),
          pick([
            '$name gefällt dein Post',
            '$name hat dir ein Herz gegeben',
            '$name feiert deinen Beitrag',
          ]),
        );
      case 'comment':
        return (
          pick(const ['Neuer Kommentar', 'Frisch kommentiert']),
          pick([
            '$name hat kommentiert',
            '$name antwortet auf deinen Post',
            '$name mischt sich ein',
          ]),
        );
      case 'friend_request':
        return (
          pick(const [
            'Freundschaftsanfrage',
            'Anfrage zum Mitcruisen',
            'Neuer Kontakt',
          ]),
          pick([
            '$name möchte mit dir cruisen',
            '$name sucht jemanden zum Cruisen',
            '$name will mit dir Touren teilen',
          ]),
        );
      case 'group_invite':
        final group = payload['group_name'] as String? ?? 'einer Gruppe';
        return (
          pick(const [
            'Einladung zur Gruppe',
            'Du wurdest eingeladen',
            'Eine Crew sucht dich',
          ]),
          pick([
            '$name lädt dich zu $group ein',
            '$name will dich bei $group dabei haben',
            'Komm zu $group, eingeladen von $name',
          ]),
        );
      case 'group_ride_started':
        return (
          pick(const [
            'Die Gruppe fährt los',
            'Crew rollt los',
            'Die Tour läuft',
          ]),
          pick([
            '$name fährt jetzt los',
            '$name hat die Tour gestartet, schließ dich an',
            'Spring auf: $name ist unterwegs',
          ]),
        );
      case 'group_public_created':
        return (
          pick(const ['Neue Gruppe', 'Frische Crew', 'Neue öffentliche Tour']),
          pick([
            '$name hat eine öffentliche Gruppe erstellt',
            '$name eröffnet eine neue Crew',
          ]),
        );
      case 'group_joined':
        return (
          pick(const [
            'Neues Gruppenmitglied',
            'Crew wächst',
            'Neuer Cruiser dabei',
          ]),
          pick([
            '$name ist beigetreten',
            '$name fährt jetzt mit',
            '$name ist Teil der Crew',
          ]),
        );
      case 'repost':
        return (
          pick(const ['Repost', 'Geteilt!', 'Dein Post verbreitet sich']),
          pick([
            '$name hat deinen Post geteilt',
            '$name pusht deinen Beitrag weiter',
          ]),
        );
      case 'weather_recommendation':
        return _weatherTexts();
      // 2026-08-28 (Fehler 6): Beitraege von Gefolgten. Die Vorschau kommt
      // aus dem Trigger-Payload (erste 80 Zeichen des Beitrags).
      case 'feed_post':
        final vorschau = (payload['preview'] as String? ?? '').trim();
        return (
          '$name hat etwas gepostet',
          vorschau.isNotEmpty ? vorschau : 'Schau dir den neuen Beitrag an',
        );
      // 2026-08-28 (Fehler 6): Community-Chat, gebuendelt je Community.
      case 'community_message':
        final cname = payload['community_name'] as String? ?? 'Community';
        final vorschau = (payload['preview'] as String? ?? '').trim();
        if (aggregateCount > 1) {
          return (
            cname,
            '$aggregateCount neue Nachrichten, zuletzt: $vorschau',
          );
        }
        return (cname, '$name: $vorschau');
      case 'trip_reminder':
        return (
          pick(const [
            'Trip wartet',
            'Deine Tour läuft noch',
            'Weiterfahren?',
          ]),
          pick([
            'Dein gestarteter Trip wartet auf Fortsetzung',
            'Letzter Stopp erreicht, bereit für den nächsten?',
            'Deine Tour mit Stopps pausiert, knack sie heute',
          ]),
        );
      default:
        return ('Benachrichtigung', name);
    }
  }

  /// 2026-08-24 (vucko, Auftrag „Nachmittags-Meldung"): Der Wortlaut kommt
  /// jetzt aus WetterPushTexte — derselben Tabelle, aus der auch die Edge
  /// Function send-push den Push rendert. Vorher stand auf dem
  /// Sperrbildschirm jeden Tag „Bestes Cruise-Wetter", und wer antippte,
  /// las in der App etwas voellig anderes.
  ///
  /// Die alte Fassung waehlte zusaetzlich nach DateTime.now().hour aus.
  /// Das musste auseinanderlaufen: der Push entsteht am Nachmittag, die
  /// App rendert erst, wenn jemand die Liste oeffnet. Massgeblich ist
  /// deshalb createdAt.
  (String, String) _weatherTexts() {
    final rohwert = payload['temperature_c'];
    return WetterPushTexte.fuer(
      userId: userId,
      erstelltAm: createdAt,
      temperaturC: rohwert is num ? rohwert : null,
    );
  }
}

/// 2026-08-24 (vucko, Auftrag „Nachmittags-Meldung"): Der Wortlaut der
/// taeglichen Wetter-Meldung.
///
/// Warum eine eigene Tabelle statt Text direkt im Rendering:
/// Der Push-Titel stand bis heute fest in supabase/functions/send-push
/// („Bestes Cruise-Wetter", jeden Tag derselbe), waehrend die App darunter
/// einen anderen Text zeigte. Wer die Meldung antippte, las etwas anderes
/// als auf dem Sperrbildschirm. Beide Seiten rendern deshalb jetzt aus
/// DIESER Tabelle; send-push haelt eine zeichengleiche Kopie, und
/// test/services/wetter_push_texte_test.dart schlaegt fehl, sobald die
/// beiden auseinanderlaufen.
///
/// Hausregeln fuer jeden neuen Text (der Test bewacht sie):
///   * KEIN Bindestrich und kein Gedankenstrich. Auch nicht in
///     Zusammensetzungen — „Feierabendrunde", nicht „Feierabend-Runde".
///   * Echte Umlaute und echtes ss/ß, keine ae/oe/ue-Ersatzschreibung.
///   * Titel hoechstens 30 Zeichen (Android schneidet den Titel der
///     eingeklappten Meldung dort ab), Text hoechstens 85 Zeichen
///     (zwei Zeilen auf dem iPhone-Sperrbildschirm).
///   * Der Kern steht VORNE: die Temperatur im Titel oder in den ersten
///     45 Zeichen des Textes.
///   * Kein Apostroph — Dart und TypeScript halten die Tabelle in
///     einfachen Anfuehrungszeichen, und der Abgleichtest liest sie so.
///
/// Auswahl: (Tagesnummer + Streuwert der user_id) % Poolgroesse. Damit
/// wechselt der Text jeden Tag garantiert (zwei aufeinanderfolgende Tage
/// koennen nie denselben Index treffen), zwei Nutzer bekommen am selben
/// Tag nicht zwingend dasselbe, und Push und App treffen trotzdem exakt
/// denselben Eintrag, weil beide nur created_at und user_id brauchen.
class WetterPushTexte {
  WetterPushTexte._();

  /// 13 bis 26 Grad — der Normalfall, deshalb 32 Varianten: ein
  /// voller Monat ohne Wiederholung.
  static const List<List<String>> mild = <List<String>>[
    ['Bestes Wetter für Kurven', '{temp}° und die Landstraße ist leer. Hol dir eine Route'],
    ['Der Nachmittag gehört dir', '{temp}° draußen. Such dir eine kurvige Runde und fahr los'],
    ['Feierabendrunde?', '{temp}°, eine Stunde Kurven und du bist rechtzeitig zurück'],
    ['Perfekte Fahrtemperatur', '{temp}° sind genau richtig. Motor an und ab in die Berge'],
    ['Jetzt lohnt sich der Weg', '{temp}° draußen. Wir bauen dir eine Strecke voller Kurven'],
    ['Kurvenwetter', '{temp}° und kaum Wind. Deine Runde wartet in der App'],
    ['Zeit für frische Luft', '{temp}°, Fenster runter und raus auf die Landstraße'],
    ['Deine Strecke steht bereit', '{temp}° draußen. Sag uns wie weit, wir bauen die Kurven'],
    ['Nachmittag mit {temp}°', 'Die Straßen sind frei. Zwei Klicks und deine Runde steht'],
    ['{temp}° und die Straße ruft', 'Zwei Stunden Kurven, dann bist du zurück. Route in der App'],
    ['Guter Tag zum Cruisen', '{temp}° draußen. Wähle deine Länge, den Rest machen wir'],
    ['Raus aus dem Alltag', '{temp}°, eine kurze Runde reicht schon zum Abschalten'],
    ['Die Berge sind nah', '{temp}° draußen. Deine Passstraße ist zwei Klicks entfernt'],
    ['Kurven statt Couch', '{temp}°, hol dir eine Route und leg einfach los'],
    ['Der Sprit ist es wert', '{temp}° draußen. Eine Runde durch die Hügel und der Tag zählt'],
    ['Sonnenuntergang mitnehmen', '{temp}° jetzt. In zwei Stunden steht die Sonne genau richtig'],
    ['Straßen frei bei {temp}°', 'Such dir eine Runde in der App und fahr sie noch heute'],
    ['Heute lohnt der Umweg', '{temp}° draußen. Die kurvige Strecke dauert kaum länger'],
    ['Zeit für eine Ausfahrt', '{temp}°, eine Runde durchs Grüne und der Tag ist gerettet'],
    ['Der Asphalt ist warm', '{temp}° draußen. Beste Bedingungen für eine ruhige Runde'],
    ['Noch ist es hell', '{temp}° draußen. Für eine Runde reicht das Licht locker'],
    ['Deine Kurven für heute', '{temp}°, sag uns die Länge und wir legen die Strecke'],
    ['Cruisen bei {temp}°', 'Allein losfahren oder dich einer Gruppe anschließen'],
    ['Wetterfenster offen', '{temp}° draußen. Die nächsten Stunden gehören der Straße'],
    ['Kurze Runde gefällig?', '{temp}°, dreißig Kilometer und du bist wieder daheim'],
    ['Heute nicht die Autobahn', '{temp}° draußen. Die kurvige Strecke kostet kaum mehr Zeit'],
    ['Beste Zeit am Tag', '{temp}° und am späten Nachmittag ist am wenigsten los'],
    ['Kurvenjagd am Nachmittag', '{temp}° draußen. Wir bauen dir die kurvigste Runde der Gegend'],
    ['Fahr eine Runde für dich', '{temp}°, ohne Ziel, nur wegen der Strecke'],
    ['Handy weg, Lenkrad her', '{temp}° draußen. Zwei Stunden nur du und die Straße'],
    ['Der Tag hat noch Luft', '{temp}°, eine Runde geht sich vor dem Abendessen aus'],
    ['Passstraßen bei {temp}°', 'Hol dir die Route in die App und fahr sie heute noch'],
  ];

  /// Ab 27 Grad. Hitze verlangt einen anderen Rat (Hoehe, Schatten,
  /// spaeter Abend) als ein milder Tag.
  static const List<List<String>> warm = <List<String>>[
    ['Warme {temp}° draußen', 'Fahr in die Höhe, oben ist es angenehmer. Route in der App'],
    ['Hitze mag Höhe', '{temp}° im Tal. Such dir eine Bergstrecke, oben ist es kühler'],
    ['Abends wird es angenehm', '{temp}° jetzt. Plane deine Runde für die Zeit nach sechs'],
    ['{temp}° und freie Bahn', 'Schattige Waldstraßen findest du in der App'],
    ['Sommerabend nutzen', '{temp}° draußen. Die schönste Zeit für eine Runde kommt erst'],
    ['Cabrio oder Helm?', '{temp}° draußen. Beides geht heute, such dir die Strecke aus'],
    ['Heiß, aber fahrbar', '{temp}° im Schatten. Nimm Wasser mit und fahr eine ruhige Runde'],
    ['{temp}° am Nachmittag', 'Der See ist nicht weit. Wir bauen dir die kurvige Anfahrt'],
    ['Ab in die Berge', '{temp}° unten, oben deutlich frischer. Deine Route wartet hier'],
    ['Warme Straßen, guter Grip', '{temp}° draußen. Beste Bedingungen für eine entspannte Runde'],
    ['Sonne satt bei {temp}°', 'Such dir eine Runde durch den Wald und bleib im Schatten'],
    ['Der Tag ist noch lang', '{temp}° draußen. Bis zum Sonnenuntergang gehen zwei Stunden'],
    ['Trinken nicht vergessen', '{temp}° draußen. Dann steht der Ausfahrt nichts im Weg'],
    ['{temp}° und Fernsicht', 'Perfekt für eine Passstraße mit Aussicht. Route in der App'],
    ['Sommerrunde planen', '{temp}° jetzt. Wähle die Länge, wir suchen die Schattenseiten'],
    ['Raus, solange es hell ist', '{temp}° draußen. Eine kurze Runde geht immer'],
  ];

  /// Unter 13 Grad. daily-weather-push meldet sich erst ab etwa 5 Grad,
  /// darunter gilt das Wetter als „marginal" und es geht nichts raus.
  static const List<List<String>> kuehl = <List<String>>[
    ['{temp}° und klare Sicht', 'Jacke an, Straßen sind frei. Deine Runde wartet in der App'],
    ['Kühl, aber fahrbar', '{temp}° draußen. Mit der richtigen Jacke ein guter Tag zum Fahren'],
    ['Frische Luft, freie Straßen', '{temp}° draußen. Um diese Zeit ist kaum jemand unterwegs'],
    ['Kurven ohne Sommerverkehr', '{temp}°, jetzt gehören die Bergstraßen dir allein'],
    ['Jetzt oder morgen früh', 'Warm anziehen, {temp}° und eine kurze Runde lohnen sich'],
    ['Die Sicht ist heute weit', '{temp}° draußen. Bei kühler Luft siehst du bis zum Horizont'],
    ['Kurze Runde reicht', '{temp}° draußen. Vierzig Kilometer und du bist wieder im Warmen'],
    ['Sitzheizung und Kurven', '{temp}° draußen. Genau dafür wurde sie eingebaut'],
    ['Vorsicht in den Kurven', '{temp}° draußen. Kalter Asphalt braucht etwas mehr Gefühl'],
    ['{temp}° und trotzdem Zeit', 'Für eine kurze Ausfahrt reicht der Nachmittag locker'],
    ['Leere Straßen im Herbst', '{temp}° draußen. Die schönen Strecken hast du fast für dich'],
    ['Der Motor will warm werden', '{temp}° draußen. Fahr eine Runde, bevor es dunkel wird'],
    ['Noch zwei Stunden hell', '{temp}° draußen. Das reicht für eine Runde über Land'],
    ['Handschuhe und Kurven', '{temp}° draußen. Route holen und die Kurven mitnehmen'],
    ['Kein Regen gemeldet', '{temp}° draußen. Das Fenster für eine Runde steht offen'],
    ['Fahren geht immer', '{temp}° draußen. Kurz raus, dann schmeckt der Kaffee besser'],
  ];

  /// Ohne Temperatur in der Nutzlast. Diese Texte duerfen keinen
  /// Platzhalter enthalten, sonst stuende „{temp}°" auf dem Bildschirm.
  static const List<List<String>> ohneWert = <List<String>>[
    ['Zeit für eine Runde', 'Die Bedingungen passen heute. Such dir eine kurvige Strecke'],
    ['Der Nachmittag ist frei', 'Gutes Wetter, freie Straßen. Deine Route wartet in der App'],
    ['Kurven warten auf dich', 'Sag uns wie weit du willst, wir bauen die Strecke'],
    ['Feierabend, Motor an', 'Eine Stunde Kurven und du bist rechtzeitig zurück'],
    ['Heute passt es', 'Wetter gut, Straßen frei. Fahr eine Runde für dich'],
    ['Ab nach draußen', 'Eine kurze Runde reicht schon zum Abschalten'],
    ['Route steht bereit', 'Zwei Klicks in der App und du fährst los'],
    ['Kurven statt Sofa', 'Wähle deine Länge, den Rest übernehmen wir'],
    ['Ruhige Zeit auf der Straße', 'Am späten Nachmittag ist am wenigsten los'],
    ['Fahr die schöne Strecke', 'Die kurvige Route dauert kaum länger als die Autobahn'],
    ['Noch reicht das Licht', 'Für eine Runde über Land ist genug Tag übrig'],
    ['Der Tag ist nicht vorbei', 'Eine Runde geht sich vor dem Abendessen aus'],
  ];

  /// Kleiner, sprachneutraler Streuwert. Bewusst NICHT String.hashCode:
  /// der ist in Dart und in Deno verschieden, und beide Seiten muessen
  /// denselben Eintrag treffen. Faktor und Modul sind klein genug, dass
  /// auch die 53 Bit von JavaScript exakt rechnen.
  static int streuwert(String text) {
    var h = 0;
    for (final c in text.codeUnits) {
      h = (h * 31 + c) % 1000003;
    }
    return h;
  }

  /// Tage seit dem 1.1.1970 in UTC. Die Meldung entsteht am Nachmittag
  /// (11 bis 19 Uhr UTC), da liegt keine Tagesgrenze in der Naehe.
  static int tagesnummer(DateTime zeitpunkt) =>
      zeitpunkt.toUtc().millisecondsSinceEpoch ~/ 86400000;

  /// Die Bandgrenzen stehen zeichengleich in send-push/index.ts.
  static List<List<String>> poolFuer(num? temperaturC) {
    if (temperaturC == null) return ohneWert;
    if (temperaturC >= 27) return warm;
    if (temperaturC < 13) return kuehl;
    return mild;
  }

  /// Minusgrade werden ausgeschrieben. „minus 3°" statt „-3°" — ein
  /// Minuszeichen ist auf dem Bildschirm ein Strich, und Striche sind
  /// in diesen Texten nicht erlaubt.
  static String temperaturText(num temperaturC) {
    final gerundet = temperaturC.round();
    return gerundet < 0 ? 'minus ${-gerundet}' : '$gerundet';
  }

  /// Liefert (Titel, Text) fuer genau diese Meldung.
  static (String, String) fuer({
    required String userId,
    required DateTime erstelltAm,
    required num? temperaturC,
  }) {
    final pool = poolFuer(temperaturC);
    final index = (tagesnummer(erstelltAm) + streuwert(userId)) % pool.length;
    final paar = pool[index];
    if (temperaturC == null) return (paar[0], paar[1]);
    final grad = temperaturText(temperaturC);
    return (
      paar[0].replaceAll('{temp}', grad),
      paar[1].replaceAll('{temp}', grad),
    );
  }
}
