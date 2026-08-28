import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cruise_connect/presentation/widgets/skeletons/skeleton.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/emoji_guard.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/pages/community_settings_page.dart';
import 'package:cruise_connect/presentation/widgets/chat_emoji_picker.dart';
import 'package:cruise_connect/presentation/widgets/community/community_eckdaten_blatt.dart';
import 'package:cruise_connect/presentation/widgets/community/community_nachrichten_ansicht.dart';
import 'package:cruise_connect/presentation/widgets/community_avatar.dart';
import 'package:cruise_connect/presentation/widgets/mentions.dart';
import 'package:cruise_connect/presentation/widgets/social/route_attachment_card.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

enum _CommunityChatPostFilter { all, groupRides, sharedRoutes }

// 2026-08-24: Die Liste steht jetzt in community_nachrichten_ansicht.dart,
// damit beide Darstellungen dieselbe benutzen.
const _communityChatTopicMentions = communityChatThemenErwaehnungen;

// 2026-07-22 (vucko Emoji-Reaktionen): identische Auswahl wie im Gruppen-Chat
// (group_chat_panel.dart), damit sich beide Chat-Arten gleich anfühlen.
const _communityQuickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

class CommunityChatDetailPage extends StatefulWidget {
  const CommunityChatDetailPage({super.key, required this.communityId});

  final String communityId;

  @override
  State<CommunityChatDetailPage> createState() =>
      _CommunityChatDetailPageState();
}

class _CommunityChatDetailPageState extends State<CommunityChatDetailPage> {
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  Map<String, dynamic>? _community;
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _members = [];
  final Map<String, GlobalKey> _messageKeys = {};

  /// Marke an der Liste selbst. Der Anker beim Umschalten der Darstellung muss
  /// gegen die Oberkante der LISTE gemessen werden, nicht gegen die des
  /// Bildschirms — darueber sitzen Leiste, Kopfzeile und Filterzeile.
  final GlobalKey _listenKey = GlobalKey();
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _membersChannel;
  RealtimeChannel? _communityChannel;
  String? _inviteCode;
  int _openJoinRequests = 0;
  bool _loading = true;
  bool _sending = false;
  int _localMessageSeq = 0;
  Map<String, dynamic>? _replyToMessage;
  SavedRoute? _attachedRoute;
  Timer? _reloadDebounce;
  _CommunityChatPostFilter _postFilter = _CommunityChatPostFilter.all;

  /// 2026-08-24 (Auftrag Vucko „chat art optimieren"): die gewaehlte
  /// Darstellung. Voreinstellung ist die Beitragsansicht — sie war bis heute
  /// die einzige, niemand soll sich nach einem Update neu zurechtfinden
  /// muessen.
  ChatDarstellung _darstellung = ChatDarstellung.standard;

  /// 2026-08-28 (Fehler 6): Stummschalten je Community. null = noch nicht
  /// geladen; die Glocke erscheint erst mit bekanntem Zustand, sonst wuerde
  /// sie beim Laden kurz falsch stehen.
  bool? _stumm;

  /// True, sobald in dieser Sitzung selbst umgeschaltet wurde. Danach darf
  /// eine spaet eintreffende Antwort vom Konto die Wahl nicht mehr umwerfen.
  bool _wahlGetroffen = false;

  /// Wer kam und wer ging (`community_mitglieder_verlauf`).
  List<Map<String, dynamic>> _verlauf = [];

  /// Kennungen der Nachrichten, die ICH „nur fuer mich" geloescht habe.
  Set<String> _ausgeblendet = {};
  RealtimeChannel? _verlaufChannel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeMessages();
    _subscribeMembers();
    _subscribeCommunity();
    _subscribeVerlauf();
    unawaited(_ladeDarstellung());
    // Fehler 6: eigenen Stumm-Status holen (eine winzige Einzelzeilen-Abfrage,
    // bewusst nicht im _load-Buendel — die Glocke darf spaeter erscheinen).
    unawaited(
      CommunityChatService.fetchStumm(widget.communityId).then((wert) {
        if (mounted && wert != null) setState(() => _stumm = wert);
      }),
    );
    // Die Serveruhr EINMAL messen. Sie entscheidet ueber nichts (das tut die
    // Datenbank), aber ohne sie kann die Seite nicht ehrlich anzeigen, wie
    // lange noch bearbeitet werden darf.
    unawaited(
      Serverzeit.abgleichen().then((ok) {
        if (ok && mounted) setState(() {});
      }),
    );
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _messagesChannel?.unsubscribe();
    _membersChannel?.unsubscribe();
    _communityChannel?.unsubscribe();
    _verlaufChannel?.unsubscribe();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool scrollToBottom = true}) async {
    try {
      final community = await CommunityChatService.fetchCommunity(
        widget.communityId,
      );
      final messages = await CommunityChatService.fetchMessages(
        widget.communityId,
      );
      final members = await CommunityChatService.fetchMembers(
        widget.communityId,
      );
      // 2026-08-24: beide Abfragen sind winzig und unabhaengig voneinander;
      // nacheinander waeren es zwei Umlaeufe mehr beim Oeffnen.
      final zusatz = await Future.wait([
        CommunityChatService.fetchVerlauf(widget.communityId),
        CommunityChatService.fetchAusgeblendeteIds(widget.communityId),
      ]);
      if (!mounted) return;
      setState(() {
        _community = community;
        _messages = messages;
        _members = members;
        _verlauf = zusatz[0] as List<Map<String, dynamic>>;
        _ausgeblendet = zusatz[1] as Set<String>;
        _loading = false;
      });
      if (scrollToBottom) _scrollToBottom();
      unawaited(_loadInviteCode());
      unawaited(_loadOpenJoinRequests());
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(e, fallback: 'Community konnte nicht geladen werden.');
    }
  }

  /// 2026-08-23 (Auftrag Vucko): Der Code stand bis heute in der
  /// Community-Zeile und war damit für JEDEN angemeldeten Nutzer JEDER
  /// öffentlichen Community lesbar. Die Migration 20260823123000 hat das
  /// Leserecht auf die Spalte entzogen; er kommt jetzt über eine RPC, die nur
  /// Mitgliedern antwortet.
  Future<void> _loadInviteCode() async {
    final code = await CommunityChatService.inviteCodeFor(widget.communityId);
    if (!mounted) return;
    setState(() => _inviteCode = code);
  }

  /// 2026-08-23 (Auftrag Vucko): „sonst versanden die Anfragen."
  ///
  /// Seit heute loest ein alter, schon geteilter Link in eine inzwischen
  /// private Community eine Beitrittsanfrage aus statt eines Beitritts. Eine
  /// Anfrage schreibt aber KEINE Benachrichtigung (nachgesehen in
  /// join_community_with_code_v2, sie legt nur die Zeile an). Ohne diesen
  /// Hinweis muesste der Admin von sich aus die Einstellungen oeffnen und
  /// nachschauen. Deshalb steht die Zahl dort, wo er ohnehin ist: im Kopf des
  /// Chats. Nur fuer Admins, also genau eine zusaetzliche Abfrage fuer die
  /// wenigen, die sie beantworten koennen.
  Future<void> _loadOpenJoinRequests() async {
    if (!_amAdmin) {
      if (mounted && _openJoinRequests != 0) {
        setState(() => _openJoinRequests = 0);
      }
      return;
    }
    final requests = await CommunityChatService.fetchJoinRequests(
      widget.communityId,
    );
    if (!mounted) return;
    setState(() => _openJoinRequests = requests.length);
  }

  void _subscribeMessages() {
    _messagesChannel = CommunityChatService.subscribeMessages(
      widget.communityId,
      () {
        _reloadDebounce?.cancel();
        _reloadDebounce = Timer(const Duration(milliseconds: 160), () {
          if (mounted) _load();
        });
      },
    );
  }

  /// 2026-08-23 (Auftrag Vucko): „Wer den Chat offen hat, merkt vom
  /// Umschalten nichts." Gemessen: es gab nur Kanäle auf `community_messages`
  /// und `community_members`. Schaltete der Admin den Schreibmodus um, tippte
  /// ein Mitglied noch minutenlang weiter und lief erst beim Senden auf einen
  /// Fehler. Jetzt kommt die Änderung sofort an, das Eingabefeld sperrt sich
  /// von selbst und der Hinweis darüber wechselt.
  void _subscribeCommunity() {
    _communityChannel = CommunityChatService.subscribeCommunity(
      widget.communityId,
      () {
        if (mounted) _load(scrollToBottom: false);
      },
    );
  }

  void _subscribeMembers() {
    _membersChannel = CommunityChatService.subscribeMembers(
      widget.communityId,
      () {
        _reloadDebounce?.cancel();
        _reloadDebounce = Timer(const Duration(milliseconds: 160), () {
          if (mounted) _load(scrollToBottom: false);
        });
      },
    );
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _messageCtrl.text.trim();
    final attachedRoute = _attachedRoute;
    if (text.isEmpty && attachedRoute == null) return;

    final replyTo = _replyToMessage;
    final routeAttachment = attachedRoute == null
        ? null
        : _routeAttachmentFor(attachedRoute);
    if (routeAttachment != null) {
      final alreadyPosted =
          await CommunityChatService.hasOwnRoutePostForCommunity(
            communityId: widget.communityId,
            routeId: routeAttachment['route_id'].toString(),
          );
      if (alreadyPosted) {
        _showError(
          const CommunityChatServiceException(
            CommunityChatService.duplicateRoutePostMessage,
          ),
          fallback: CommunityChatService.duplicateRoutePostMessage,
        );
        return;
      }
    }
    final replyToId = replyTo?['id']?.toString();
    final persistedReplyToId =
        replyToId == null || replyToId.startsWith('local-') ? null : replyToId;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final body = text.isEmpty ? 'Route geteilt' : text;
    final localId =
        'local-${DateTime.now().microsecondsSinceEpoch}-${_localMessageSeq++}';
    final optimistic = <String, dynamic>{
      'id': localId,
      'community_id': widget.communityId,
      'user_id': uid,
      'body': body,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'deleted_at': null,
      if (persistedReplyToId != null) 'reply_to_message_id': persistedReplyToId,
      if (routeAttachment != null) 'route_attachment': routeAttachment,
      'profiles': _profileForUser(uid),
      '_pending': true,
    };

    setState(() {
      _sending = true;
      _messages = [..._messages, optimistic];
      _messageCtrl.clear();
      _replyToMessage = null;
      _attachedRoute = null;
    });
    _scrollToBottom();
    try {
      await CommunityChatService.sendMessage(
        widget.communityId,
        body,
        replyToMessageId: persistedReplyToId,
        routeAttachment: routeAttachment,
      );
      unawaited(_load());
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages = _messages
              .where((message) => message['id'] != localId)
              .toList();
          _replyToMessage = replyTo;
          _attachedRoute = attachedRoute;
          _messageCtrl.text = text;
        });
      }
      _showError(e, fallback: 'Nachricht konnte nicht gesendet werden.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Map<String, dynamic> _profileForUser(String userId) {
    for (final member in _members) {
      if (member['user_id'] == userId) {
        final raw = member['profiles'];
        if (raw is Map) return Map<String, dynamic>.from(raw);
      }
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user?.id == userId) {
      final meta = user?.userMetadata ?? const <String, dynamic>{};
      return {
        'id': userId,
        'username': meta['username'] ?? meta['name'] ?? user?.email,
        'email': user?.email,
        'avatar_url': meta['avatar_url'],
      };
    }
    return {'id': userId};
  }

  Map<String, dynamic> _routeAttachmentFor(SavedRoute route) {
    return {
      'route_id': route.id,
      'title': route.name ?? route.style,
      'style': route.style,
      'distance_km': route.distanceKm,
      if (route.durationSeconds != null)
        'duration_seconds': route.durationSeconds,
      if (route.sourceRouteId != null) 'source_route_id': route.sourceRouteId,
    };
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _friendlyError(Object error, String fallback) {
    // 2026-08-23 (Auftrag Vucko): Der echte Grund wurde bisher verschluckt.
    // Diese Funktion filtert „policy" und „row-level" bewusst als Rauschen
    // weg, weil das für JEDE Regelverletzung auf JEDER Tabelle steht. Genau
    // diesen Text schickt Postgres aber auch, wenn der Admin das Schreiben
    // gesperrt hat. Ein BENANNTER Fehler aus dem Dienst (Code gesetzt, wie
    // CC001 beim Premium-Gate) geht deshalb ungefiltert durch.
    if (error is CommunityChatServiceException && error.code != null) {
      return error.message;
    }
    final raw = error.toString();
    final lower = raw.toLowerCase();
    final isBackendNoise =
        lower.contains('postgrest') ||
        lower.contains('supabase') ||
        lower.contains('row-level') ||
        lower.contains('rls') ||
        lower.contains('policy') ||
        lower.contains('permission') ||
        lower.contains('schema cache') ||
        lower.contains('violates') ||
        lower.contains('duplicate key');
    if (raw.trim().isEmpty || isBackendNoise) return fallback;
    return raw.length > 110 ? fallback : raw;
  }

  void _showError(
    Object error, {
    String fallback = 'Aktion gerade nicht möglich.',
  }) {
    _showToast(_friendlyError(error, fallback), error: true);
  }

  void _showToast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: error
            ? const Color(0xFF301B20)
            : const Color(0xFF171B24),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1250),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Future<void> _copyInviteCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    _showToast('Code kopiert.');
  }

  void _showMembersSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CommunityMembersSheet(
        communityId: widget.communityId,
        initialMembers: _members,
        ownerOnlyMessages: _community?['owner_only_messages'] == true,
        onChanged: () => _load(scrollToBottom: false),
      ),
    );
  }

  String? get _myRole {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return null;
    for (final member in _members) {
      if (member['user_id'] == uid) return member['role']?.toString();
    }
    return null;
  }

  bool get _amAdmin => _myRole == 'owner';
  bool get _canPinMessages => CommunityChatService.canModerate(_myRole);
  bool get _canWrite {
    if (_community?['owner_only_messages'] != true) return true;
    return CommunityChatService.canModerate(_myRole);
  }

  Map<String, dynamic>? _messageById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final message in _messages) {
      if (message['id']?.toString() == id) return message;
    }
    return null;
  }

  Map<String, dynamic>? _routeAttachmentFrom(Map<String, dynamic> message) {
    final raw = message['route_attachment'];
    if (raw is! Map) return null;
    final attachment = Map<String, dynamic>.from(raw);
    final routeId = attachment['route_id']?.toString();
    if (routeId == null || routeId.isEmpty) return null;
    return attachment;
  }

  Future<void> _copyMessage(Map<String, dynamic> message) async {
    final body = message['body']?.toString() ?? '';
    final route = _routeAttachmentFrom(message);
    final value = route == null
        ? body
        : [
            if (body.isNotEmpty) body,
            'Route: ${route['title'] ?? route['route_id']}',
          ].join('\n');
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    _showToast('Nachricht kopiert.');
  }

  Future<void> _setMessagePinned(
    Map<String, dynamic> message, {
    required bool pinned,
  }) async {
    final id = message['id']?.toString();
    if (id == null || id.isEmpty || id.startsWith('local-')) return;
    final previous = List<Map<String, dynamic>>.from(_messages);
    setState(() {
      _messages = _messages.map((entry) {
        if (entry['id']?.toString() != id) return entry;
        return {
          ...entry,
          'pinned_at': pinned ? DateTime.now().toUtc().toIso8601String() : null,
          'pinned_by': pinned
              ? Supabase.instance.client.auth.currentUser?.id
              : null,
        };
      }).toList();
    });
    try {
      await CommunityChatService.setMessagePinned(
        messageId: id,
        pinned: pinned,
      );
      unawaited(_load(scrollToBottom: false));
      _showToast(pinned ? 'Post angepinnt.' : 'Pin entfernt.');
    } catch (e) {
      if (mounted) setState(() => _messages = previous);
      _showError(e, fallback: 'Pin konnte nicht gespeichert werden.');
    }
  }

  /// Emoji-Reaktion umschalten (langer Druck auf eine Nachricht) — optimistisch
  /// + DB, gespiegelt vom Gruppen-Chat-Vorbild (GroupChatStore.toggleReaction).
  void _toggleReaction(String messageId, String emoji) {
    // 2026-07-23 (vucko "nur Emoji, kein Text bei Reaktionen"): Lock gegen
    // Text/Mehrfach-Emoji-Strings — betrifft in der Praxis nur einen
    // hypothetischen künftigen Aufrufer, da die Quick-Emojis und der Picker
    // schon jetzt nur echte Einzel-Emoji liefern.
    if (!EmojiGuard.isSingleEmoji(emoji)) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final index = _messages.indexWhere(
      (m) => m['id']?.toString() == messageId,
    );
    if (index == -1) return;

    final reactions = <Map<String, dynamic>>[
      for (final r
          in (_messages[index]['community_message_reactions'] as List?) ??
              const [])
        if (r is Map) Map<String, dynamic>.from(r),
    ];
    final mine = reactions.any(
      (r) => r['emoji'] == emoji && r['user_id'] == uid,
    );

    setState(() {
      final updated = <Map<String, dynamic>>[...reactions];
      if (mine) {
        updated.removeWhere(
          (r) => r['emoji'] == emoji && r['user_id'] == uid,
        );
      } else {
        updated.add({'emoji': emoji, 'user_id': uid});
      }
      _messages = [
        for (final m in _messages)
          if (m['id']?.toString() == messageId)
            {...m, 'community_message_reactions': updated}
          else
            m,
      ];
    });

    final future = mine
        ? CommunityChatService.removeReaction(messageId, emoji)
        : CommunityChatService.addReaction(messageId, emoji);
    future
        .then((_) => _load(scrollToBottom: false))
        .catchError((_) => _load(scrollToBottom: false));
  }

  /// 2026-07-23 (vucko „wie bei WhatsApp"): echter Emoji-Picker (Raster, kein
  /// Text-Keyboard) statt der 6 Schnell-Emojis — gespiegelt von
  /// group_chat_panel.dart._openCustomEmojiPicker.
  Future<void> _openCustomEmojiPicker(String messageId) async {
    // Bottom-Sheet-Schließ-Animation erst abwarten — ein zweites Sheet im
    // selben Tick wie Navigator.pop(sheetContext) kollidiert sonst mit der
    // laufenden Pop-Transition und erscheint gar nicht.
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    final emoji = await showChatEmojiPicker(context);
    if (emoji == null || emoji.isEmpty) return;
    _toggleReaction(messageId, emoji);
  }

  void _showMessageActions(Map<String, dynamic> message) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final isMine = message['user_id'] == uid;
    final istGeloescht = message['_geloescht'] == true;
    final isPinned = message['pinned_at'] != null;
    final messageId = message['id']?.toString();
    final istLokal = messageId == null || messageId.startsWith('local-');
    final istUnterwegs = message['_pending'] == true;
    // Für alle löschen darf, wer die Nachricht geschrieben hat, und die
    // Moderation. Unverändert gegenüber heute — eine stille Verschärfung
    // gehört nicht in diesen Auftrag.
    // `istLokal` heisst: die Nachricht ist noch gar nicht in der Datenbank.
    // „Fuer alle loeschen" waere dafuer das falsche Wort — es gibt niemanden,
    // bei dem sie steht. Sie wird verworfen.
    final darfFuerAlleLoeschen =
        !istGeloescht &&
        !istLokal &&
        (isMine || CommunityChatService.canModerate(_myRole));

    // 2026-08-24 (Auftrag Vucko): Die Frist wird gegen die SERVERZEIT
    // gerechnet. Ist sie unbekannt, bleibt der Eintrag stehen und der Server
    // lehnt gegebenenfalls mit einer ehrlichen Meldung ab — siehe
    // CommunityChatService.darfBearbeiten.
    final verbleibend = _verbleibendeFrist(message);
    final darfBearbeiten =
        !istLokal &&
        CommunityChatService.darfBearbeiten(
          istEigene: isMine,
          istGeloescht: istGeloescht,
          istUnterwegs: istUnterwegs,
          verbleibend: verbleibend,
        );

    // Reagieren nur auf echte Server-Nachrichten (keine optimistische
    // "sendet..."-Zeile mit lokaler ID, kein Grabstein).
    final canReact = !istUnterwegs && !istLokal && !istGeloescht;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                if (canReact)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final emoji in _communityQuickEmojis)
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _toggleReaction(messageId, emoji);
                            },
                            child: Container(
                              width: 46,
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1F26),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                        // 2026-07-23 (vucko): eigenes Emoji über die normale
                        // System-Emoji-Tastatur wählen (nicht auf die 6
                        // Schnell-Emojis beschränkt).
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(sheetContext);
                            unawaited(_openCustomEmojiPicker(messageId));
                          },
                          child: Container(
                            width: 46,
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1F26),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.06),
                              ),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.white70,
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (canReact)
                  Divider(color: Colors.white.withValues(alpha: 0.06), height: 18),
                if (!istGeloescht)
                  _MessageActionTile(
                    icon: Icons.reply_rounded,
                    label: 'Antworten',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      setState(() => _replyToMessage = message);
                    },
                  ),
                if (darfBearbeiten)
                  _MessageActionTile(
                    icon: Icons.edit_outlined,
                    label: 'Bearbeiten',
                    // Der Hinweis ist die Anzeige der Frist. Steht dort nichts,
                    // ist die Serverzeit noch nicht gemessen — dann wird auch
                    // nichts behauptet.
                    hinweis: verbleibend == null
                        ? null
                        : CommunityChatService.fristText(verbleibend),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_bearbeiteNachricht(message));
                    },
                  ),
                if (!istGeloescht)
                  _MessageActionTile(
                    icon: Icons.copy_rounded,
                    label: 'Kopieren',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_copyMessage(message));
                    },
                  ),
                if (_canPinMessages && !istGeloescht)
                  _MessageActionTile(
                    icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    label: isPinned ? 'Pin entfernen' : 'Anpinnen',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_setMessagePinned(message, pinned: !isPinned));
                    },
                  ),
                // 2026-08-24 (Auftrag Vucko „wie bei WhatsApp"): zwei
                // Möglichkeiten, und die Wörter müssen den Unterschied selbst
                // erklären. „Löschen" allein sagte nicht, wen es trifft.
                if (!istLokal)
                  _MessageActionTile(
                    icon: Icons.visibility_off_outlined,
                    label: 'Nur für mich löschen',
                    hinweis: 'Die anderen sehen sie weiter.',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_loescheNurFuerMich(message));
                    },
                  ),
                if (darfFuerAlleLoeschen)
                  _MessageActionTile(
                    icon: Icons.delete_outline_rounded,
                    label: 'Für alle löschen',
                    hinweis: 'Verschwindet bei allen Mitgliedern.',
                    destructive: true,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_loescheFuerAlle(message));
                    },
                  ),
                if (istLokal)
                  _MessageActionTile(
                    icon: Icons.close_rounded,
                    label: 'Entwurf verwerfen',
                    destructive: true,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_loescheFuerAlle(message));
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRoutePicker() async {
    final route = await showModalBottomSheet<SavedRoute>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.68,
            child: FutureBuilder<List<SavedRoute>>(
              future: SavedRoutesService.getSavedRouteLibrary(),
              builder: (context, snapshot) {
                final routes = snapshot.data ?? const <SavedRoute>[];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 14),
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: Text(
                        'Route anhängen',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      Expanded(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppAccentColors.accent,
                          ),
                        ),
                      )
                    else if (routes.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Noch keine gespeicherten Routen.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                          itemCount: routes.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final route = routes[index];
                            return InkWell(
                              onTap: () => Navigator.pop(sheetContext, route),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F121A),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.07),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.route_rounded,
                                      color: AppAccentColors.accent,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${route.styleEmoji} ${route.name ?? route.style}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${route.formattedDistance} · ${route.formattedDuration}',
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
    if (route == null || !mounted) return;
    setState(() => _attachedRoute = route);
  }

  void _scrollToMessage(String? messageId) {
    if (messageId == null || messageId.isEmpty) return;
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.30,
      );
      return;
    }
    final zeilen = _zeilen();
    final index = zeilen.indexWhere((zeile) => zeile.id == messageId);
    if (index < 0 || !_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      (index * 86.0).clamp(0.0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// 2026-08-28 (Fehler 6): Glocke umschalten. Optimistisch — die Anzeige
  /// kippt sofort, der Server zieht nach; scheitert er, kippt sie zurueck
  /// und sagt es ehrlich.
  Future<void> _toggleStumm() async {
    final vorher = _stumm;
    if (vorher == null) return;
    final neu = !vorher;
    HapticFeedback.selectionClick();
    setState(() => _stumm = neu);
    final ok = await CommunityChatService.setStumm(widget.communityId, neu);
    if (!mounted) return;
    if (!ok) {
      setState(() => _stumm = vorher);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Konnte gerade nicht gespeichert werden.'),
          backgroundColor: Color(0xFF333333),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          neu
              ? 'Community stummgeschaltet. Du bekommst keine Benachrichtigungen mehr aus diesem Chat.'
              : 'Benachrichtigungen fuer diese Community sind wieder an.',
        ),
        backgroundColor: const Color(0xFF333333),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmLeaveCommunity() async {
    final isAdmin = _amAdmin;
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151821),
        title: const Text(
          'Community verlassen?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          isAdmin
              ? 'Wenn du gehst, wird automatisch das Mitglied Admin, das als nächstes beigetreten ist.'
              : 'Du verlässt diese Community und kannst danach nicht mehr mitschreiben.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Verlassen',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (shouldLeave != true) return;

    try {
      await CommunityChatService.leaveCommunity(widget.communityId);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _showError(e, fallback: 'Community konnte nicht verlassen werden.');
    }
  }

  Future<void> _confirmDeleteCommunity() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151821),
        title: const Text(
          'Community löschen?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Diese Community, alle Mitglieder und Nachrichten werden dauerhaft gelöscht.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Löschen',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;

    try {
      await CommunityChatService.deleteCommunity(widget.communityId);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _showError(e, fallback: 'Community konnte nicht gelöscht werden.');
    }
  }

  /// 2026-08-23 (Auftrag Vucko, Sprachnachricht): Schreibmodus und
  /// Sichtbarkeit lagen als zwei Eintraege in DIESEM Drei-Punkte-Menue und
  /// wurden nicht gefunden. Sie stehen jetzt zusammen mit Bild, Name,
  /// Beschreibung, Einladungscode, Mitgliedern und Loeschen auf einer eigenen
  /// Einstellungs-Seite, die es auch aus dem Karten-Menue der Uebersicht gibt.
  /// Das Umschalten der Sichtbarkeit hat dort ausserdem eine Rueckfrage; hier
  /// lief es ohne, ein Fehltipp machte eine private Community sofort
  /// oeffentlich.
  Future<void> _openSettings() async {
    final community = _community;
    final result = await Navigator.push<CommunitySettingsResult>(
      context,
      MaterialPageRoute(
        builder: (_) => CommunitySettingsPage(
          communityId: widget.communityId,
          initialCommunity: community,
        ),
      ),
    );
    if (!mounted) return;
    if (result == CommunitySettingsResult.deleted) {
      Navigator.pop(context);
      return;
    }
    if (result == CommunitySettingsResult.changed) {
      await _load(scrollToBottom: false);
    } else {
      // Auch ohne gemeldete Aenderung koennen Anfragen beantwortet worden
      // sein, wenn der Admin die Seite nur angeschaut hat.
      unawaited(_loadOpenJoinRequests());
    }
  }

  /// 2026-08-24 (Auftrag Vucko): „wenn man in der community oben klickt auf
  /// den namen wenn man drinnen ist, soll man auch als normaler user in der
  /// gruppe die eckdaten wie mitglieder usw sehen koennen aber man soll nichts
  /// aendern koennen das soll gelocked sein".
  ///
  /// GEMESSEN vorher: der Name war an beiden Stellen oben ein blosser `Row`
  /// ohne `onTap`. Ein Mitglied kam an die Eckdaten seiner eigenen Community
  /// nicht heran — die Einstellungen sind Admin-Sache, die Vorschau von unten
  /// ist fuer Nichtmitglieder.
  ///
  /// Beide Stellen (AppBar-Titel und Kopfzeile darunter) rufen DIESE Methode,
  /// damit sie nicht auseinanderlaufen. Wohin es geht, entscheidet
  /// [communityKopfzeileZiel] — der Admin landet mit demselben einen
  /// Fingertipp direkt in den Einstellungen und nicht erst in einer
  /// Nur-Lesen-Ansicht.
  Future<void> _oeffneEckdaten() async {
    final community = _community;
    if (community == null) return;
    switch (communityKopfzeileZiel(rolle: _myRole)) {
      case CommunityKopfzeileZiel.einstellungen:
        await _openSettings();
      case CommunityKopfzeileZiel.eckdaten:
        await CommunityEckdatenBlatt.zeigen(
          context,
          community: community,
          rolle: _myRole,
          onMitgliederAnzeigen: _showMembersSheet,
        );
    }
  }

  /// Der Admin sieht am Zahnrad, dass sein Tipp in die Einstellungen fuehrt;
  /// alle anderen am „i", dass es Angaben zum Nachlesen gibt. Ohne dieses
  /// Zeichen bleibt eine antippbare Kopfzeile unentdeckt.
  bool get _kopfzeileFuehrtInEinstellungen =>
      communityKopfzeileZiel(rolle: _myRole) ==
      CommunityKopfzeileZiel.einstellungen;

  IconData get _kopfzeileSymbol => _kopfzeileFuehrtInEinstellungen
      ? Icons.settings_outlined
      : Icons.info_outline;

  String get _kopfzeileHinweis => _kopfzeileFuehrtInEinstellungen
      ? 'Einstellungen der Community'
      : 'Eckdaten dieser Community';

  @override
  Widget build(BuildContext context) {
    final community = _community;
    final title = community?['name']?.toString() ?? 'Community';

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        // 2026-08-23 (Auftrag Vucko „Profilbilder fuer Communities"): erste
        // von genau drei Anzeigestellen. Die anderen beiden sind die Kopfzeile
        // unter der Leiste und die Kachel in der Uebersicht.
        title: Tooltip(
          message: _kopfzeileHinweis,
          child: InkWell(
            onTap: community == null ? null : _oeffneEckdaten,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                children: [
                  CommunityAvatar.fromCommunity(
                    community,
                    size: 30,
                    borderRadius: 9,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(_kopfzeileSymbol, size: 15, color: Colors.white54),
                ],
              ),
            ),
          ),
        ),
        actions: [
          // 2026-08-28 (Fehler 6): Stummschalten je Community — die Glocke
          // direkt am Chat, ein Tipp. Serverseitig gespeichert, damit auch
          // der Push-Fanout sie respektiert. Erscheint erst, wenn der
          // Zustand geladen ist.
          if (_stumm != null)
            IconButton(
              tooltip: _stumm!
                  ? 'Stumm. Tippen, um Benachrichtigungen wieder zu bekommen'
                  : 'Benachrichtigungen an. Tippen zum Stummschalten',
              onPressed: _toggleStumm,
              icon: Icon(
                _stumm!
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_outlined,
                color: _stumm! ? Colors.white38 : Colors.white,
              ),
            ),
          // 2026-08-24 (Auftrag Vucko „chat art optimieren"): Der Wechsel
          // gehoert dorthin, wo der Chat ist, und nicht in ein
          // Einstellungsmenue drei Ebenen tiefer. Ein Tipp, sofort sichtbar.
          IconButton(
            tooltip: _darstellung == ChatDarstellung.standard
                ? 'Ansicht wechseln: Nachrichten'
                : 'Ansicht wechseln: Beiträge',
            onPressed: _wechsleDarstellung,
            icon: Icon(
              _darstellung == ChatDarstellung.standard
                  ? Icons.chat_bubble_outline_rounded
                  : Icons.view_agenda_outlined,
              color: Colors.white,
            ),
          ),
          IconButton(
            tooltip: 'Mitglieder',
            onPressed: _showMembersSheet,
            icon: const Icon(Icons.people_outline, color: Colors.white),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: Colors.white),
            color: const Color(0xFF1C1F26),
            onSelected: (value) {
              if (value == 'leave') {
                _confirmLeaveCommunity();
              } else if (value == 'delete') {
                _confirmDeleteCommunity();
              } else if (value == 'settings') {
                _openSettings();
              }
            },
            itemBuilder: (_) => [
              if (_amAdmin)
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(
                        Icons.settings_outlined,
                        color: Colors.white70,
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Einstellungen der Community',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_amAdmin) const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.redAccent, size: 18),
                    SizedBox(width: 10),
                    Text(
                      'Verlassen',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
              if (_amAdmin) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Community löschen',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      body: _loading
          ? const SkeletonChat()
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: Column(
                children: [
                  if (community != null) _buildCommunityHeader(community),
                  _buildPostFilters(),
                  Expanded(key: _listenKey, child: _buildMessages()),
                  _buildComposer(),
                ],
              ),
            ),
    );
  }

  Widget _buildCommunityHeader(Map<String, dynamic> community) {
    final isPublic = community['is_public'] == true;
    final memberCount = CommunityChatService.memberCount(community);
    // 2026-08-23: kommt nicht mehr aus der Zeile, sondern aus der RPC
    // `get_community_invite_code`, die nur Mitgliedern antwortet.
    final inviteCode = _inviteCode;
    final canInvite = CommunityChatService.canInvite(community);
    final ownerOnlyMessages = community['owner_only_messages'] == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111620),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 2026-08-24: zweite antippbare Stelle. „Oben auf den Namen" kann
          // beides meinen — die Leiste oder die Kopfzeile direkt darunter.
          // Beide fuehren ueber `_oeffneEckdaten` zum selben Ziel.
          InkWell(
            onTap: _oeffneEckdaten,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                // 2026-08-23: zweite Anzeigestelle des Community-Bildes.
                CommunityAvatar.fromCommunity(
                  community,
                  size: 44,
                  borderRadius: 13,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    community['name']?.toString() ?? 'Community',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(_kopfzeileSymbol, size: 17, color: Colors.white38),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildMetaPill(
                  icon: isPublic ? Icons.public : Icons.lock_outline,
                  label: isPublic ? 'Öffentlich' : 'Privat',
                  color: isPublic ? Colors.greenAccent : Colors.orangeAccent,
                ),
                const SizedBox(width: 8),
                _buildMetaPill(
                  icon: Icons.people_outline,
                  trailingIcon: ownerOnlyMessages
                      ? Icons.admin_panel_settings_outlined
                      : null,
                  label: '$memberCount Mitglieder',
                  color: Colors.white70,
                  trailingColor: ownerOnlyMessages ? Colors.orangeAccent : null,
                  onTap: _showMembersSheet,
                ),
                // 2026-08-24 (Aufgabe 10b). Vucko: „ein badge in der community
                // wo man sieht wann es gegruendet wurde."
                //
                // Es steht bewusst HIER, in der Kopfzeile der Community
                // selbst, und nicht in der Liste — das Etikett „Vor kurzem
                // erstellt" aus Aufgabe 1.2 sitzt in der Liste und sagt
                // etwas anderes (jünger als 7 Tage). Dieses hier zeigt IMMER
                // das Datum, egal wie alt die Community ist.
                //
                // Nicht anklickbar mit Absicht: Es ist eine Angabe, kein
                // Einstieg. Alles, was hier tippbar ist (Mitglieder,
                // Beitrittsanfragen), führt woandershin.
                if (CommunityChatService.gruendungsdatumText(community)
                    case final gruendung?) ...[
                  const SizedBox(width: 8),
                  _buildMetaPill(
                    icon: Icons.workspace_premium_outlined,
                    label: gruendung,
                    color: Colors.amberAccent,
                  ),
                ],
                if (_amAdmin && _openJoinRequests > 0) ...[
                  const SizedBox(width: 8),
                  _buildMetaPill(
                    icon: Icons.person_add_alt_1,
                    label: _openJoinRequests == 1
                        ? '1 Beitrittsanfrage'
                        : '$_openJoinRequests Beitrittsanfragen',
                    color: Colors.orangeAccent,
                    onTap: _openSettings,
                  ),
                ],
              ],
            ),
          ),
          if (!isPublic &&
              canInvite &&
              inviteCode != null &&
              inviteCode.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => _copyInviteCode(inviteCode),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppAccentColors.accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppAccentColors.accent.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.key, color: AppAccentColors.accent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        inviteCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const Icon(Icons.copy, color: Colors.white70, size: 17),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaPill({
    required IconData icon,
    required String label,
    required Color color,
    IconData? trailingIcon,
    Color? trailingColor,
    VoidCallback? onTap,
  }) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 6),
            Icon(trailingIcon, color: trailingColor ?? color, size: 13),
          ],
        ],
      ),
    );
    if (onTap == null) return pill;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: pill,
    );
  }

  Widget _buildPostFilters() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _buildPostFilterChip(
              filter: _CommunityChatPostFilter.all,
              icon: Icons.auto_awesome_motion_outlined,
              label: 'Alles',
            ),
            const SizedBox(width: 8),
            _buildPostFilterChip(
              filter: _CommunityChatPostFilter.groupRides,
              icon: Icons.groups_2_outlined,
              label: '@Gruppenfahrten',
            ),
            const SizedBox(width: 8),
            _buildPostFilterChip(
              filter: _CommunityChatPostFilter.sharedRoutes,
              icon: Icons.route_outlined,
              label: 'Geteilte Routen',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostFilterChip({
    required _CommunityChatPostFilter filter,
    required IconData icon,
    required String label,
  }) {
    final selected = _postFilter == filter;
    return InkWell(
      onTap: () => setState(() => _postFilter = filter),
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppAccentColors.accent.withValues(alpha: 0.18)
              : const Color(0xFF151821),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppAccentColors.accent
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: selected ? AppAccentColors.accent : Colors.white60,
              size: 17,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Die Nachrichten nach dem gewaehlten Themenfilter. Die Reihenfolge macht
  /// seit dem 24.08. [CommunityChatTimeline] — sie haengt an der Darstellung
  /// (Beitragsansicht: Angepinntes zuerst; Nachrichten-Ansicht: streng
  /// chronologisch) und muss deshalb an einer Stelle liegen, die beide kennt.
  List<Map<String, dynamic>> _visibleMessages() {
    return switch (_postFilter) {
      _CommunityChatPostFilter.all => _messages.toList(),
      _CommunityChatPostFilter.groupRides =>
        _messages.where(_messageMatchesGroupRide).toList(),
      _CommunityChatPostFilter.sharedRoutes =>
        _messages
            .where((message) => _routeAttachmentFrom(message) != null)
            .toList(),
    };
  }

  bool _messageMatchesGroupRide(Map<String, dynamic> message) {
    final body = (message['body'] ?? '').toString().toLowerCase();
    return RegExp(
          r'@(gruppe|gruppen|gruppenfahrt|gruppenfahrten|gruppenfahert)\b',
          caseSensitive: false,
        ).hasMatch(body) ||
        body.contains('gruppenfahrt') ||
        body.contains('gruppen fahr');
  }

  int _replyCountFor(String? messageId) {
    if (messageId == null || messageId.isEmpty) return 0;
    // 2026-08-24: Eine geloeschte oder von mir ausgeblendete Antwort zaehlt
    // nicht mit — sonst stuende „3 Antworten" ueber zwei sichtbaren.
    return _messages
        .where(
          (message) =>
              message['reply_to_message_id']?.toString() == messageId &&
              message['_geloescht'] != true &&
              !_ausgeblendet.contains(message['id']?.toString()),
        )
        .length;
  }

  String _postTopicLabel(Map<String, dynamic> message) {
    if (_routeAttachmentFrom(message) != null) return 'r/GeteilteRouten';
    if (_messageMatchesGroupRide(message)) return 'r/Gruppenfahrten';
    final raw = (_community?['name'] ?? 'Community').toString().trim();
    final compact = raw.replaceAll(RegExp(r'\s+'), '');
    return 'r/${compact.isEmpty ? 'Community' : compact}';
  }

  Widget _buildMessages() {
    final zeilen = _zeilen();
    if (zeilen.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.article_outlined, color: Colors.grey[700], size: 44),
              const SizedBox(height: 12),
              Text(
                _postFilter == _CommunityChatPostFilter.all
                    ? 'Noch keine Posts'
                    : 'Keine passenden Posts',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _postFilter == _CommunityChatPostFilter.groupRides
                    ? 'Nutze Tags wie @Gruppenfahrt oder @Gruppenfahrten.'
                    : _postFilter == _CommunityChatPostFilter.sharedRoutes
                    ? 'Hänge eine gespeicherte Route an deinen Post.'
                    : 'Schreib den ersten Post in diese Community.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (_darstellung == ChatDarstellung.nachrichten) {
      return CommunityNachrichtenAnsicht(
        zeilen: zeilen,
        scrollController: _scrollCtrl,
        messageKeys: _messageKeys,
        eigeneUserId: Supabase.instance.client.auth.currentUser?.id,
        onAktionen: _showMessageActions,
        onAntworten: (nachricht) =>
            setState(() => _replyToMessage = nachricht),
        onZuNachricht: _scrollToMessage,
        reaktionenBauer: _buildReactions,
        zitatTextFuer: _zitatText,
        antwortenZahlFuer: _replyCountFor,
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
      itemCount: zeilen.length,
      itemBuilder: (context, index) {
        final zeile = zeilen[index];
        final id = zeile.id;
        final key = id == null
            ? null
            : _messageKeys.putIfAbsent(id, GlobalKey.new);
        final inhalt = switch (zeile.art) {
          ChatZeileArt.verlauf => CommunitySystemZeile(
            eintraege: zeile.verlauf,
          ),
          ChatZeileArt.geloescht => _buildGeloeschtKarte(zeile.nachricht!),
          ChatZeileArt.nachricht => _buildCommunityPostCard(zeile.nachricht!),
        };
        return KeyedSubtree(key: key, child: inhalt);
      },
    );
  }

  Widget _buildCommunityPostCard(Map<String, dynamic> message) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final isMine = message['user_id'] == uid;
    final rawProfile = message['profiles'];
    final profile = rawProfile is Map
        ? Map<String, dynamic>.from(rawProfile)
        : <String, dynamic>{};
    final name = CommunityChatService.displayName(
      profile,
      fallbackUserId: message['user_id'] as String?,
    );
    final body = message['body']?.toString() ?? '';
    final time = _formatMessageTime(message['created_at'] as String?);
    final isPending = message['_pending'] == true;
    final replyToId = message['reply_to_message_id']?.toString();
    final routeAttachment = _routeAttachmentFrom(message);
    final messageId = message['id']?.toString();
    final replies = _replyCountFor(messageId);
    final isPinned = message['pinned_at'] != null;
    // 2026-08-24 (Auftrag Vucko): „Eine bearbeitete Nachricht muss als
    // bearbeitet erkennbar sein." `bearbeitet_am` setzt ausschliesslich der
    // Trigger in der Datenbank; ein mitgeschickter Wert wird dort verworfen.
    final istBearbeitet = message['bearbeitet_am'] != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => _showMessageActions(message),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF151821),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isPinned
                  ? AppAccentColors.accent.withValues(alpha: 0.46)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isPinned) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppAccentColors.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.push_pin,
                          color: AppAccentColors.accent,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Angepinnt',
                          style: TextStyle(
                            color: AppAccentColors.accent,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 9),
                ],
                Row(
                  children: [
                    UserAvatar.fromProfile(
                      profile,
                      fallbackName: name,
                      radius: 14,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_postTopicLabel(message)} · $name · $time'
                        '${istBearbeitet ? ' · bearbeitet' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isMine)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppAccentColors.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          isPending ? 'sendet...' : 'Du',
                          style: TextStyle(
                            color: AppAccentColors.accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Aktionen',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _showMessageActions(message),
                      icon: const Icon(
                        Icons.more_horiz,
                        color: Colors.white54,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                if (replyToId != null && replyToId.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _scrollToMessage(replyToId),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0E14),
                        borderRadius: BorderRadius.circular(9),
                        border: Border(
                          left: BorderSide(
                            color: AppAccentColors.accent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        _zitatText(replyToId),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 11.5,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.38,
                        fontWeight: FontWeight.w700,
                      ),
                      children: buildMentionSpans(
                        context: context,
                        text: body,
                        baseStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.38,
                          fontWeight: FontWeight.w700,
                        ),
                        plainMentions: _communityChatTopicMentions,
                      ),
                    ),
                  ),
                ],
                if (routeAttachment != null) ...[
                  const SizedBox(height: 12),
                  RouteAttachmentCard(
                    routeId: routeAttachment['route_id'].toString(),
                    compact: true,
                    showRideButton: true,
                    fallbackTitle: routeAttachment['title']?.toString(),
                    fallbackStyle: routeAttachment['style']?.toString(),
                    fallbackDistanceKm: (routeAttachment['distance_km'] as num?)
                        ?.toDouble(),
                    fallbackDurationSeconds:
                        (routeAttachment['duration_seconds'] as num?)
                            ?.toDouble(),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _PostAction(
                      icon: Icons.mode_comment_outlined,
                      label: replies == 1 ? '1 Antwort' : '$replies Antworten',
                      onTap: () => setState(() => _replyToMessage = message),
                    ),
                    _PostAction(
                      icon: Icons.reply_rounded,
                      label: 'Antworten',
                      onTap: () => setState(() => _replyToMessage = message),
                    ),
                    _PostAction(
                      icon: Icons.copy_rounded,
                      label: 'Kopieren',
                      onTap: () => unawaited(_copyMessage(message)),
                    ),
                  ],
                ),
                _buildReactions(message),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Reaktions-Pillen unter dem Post (Emoji + Anzahl, eigene hervorgehoben).
  /// Gespiegelt von group_chat_panel.dart._buildReactions/_reactionPill.
  Widget _buildReactions(Map<String, dynamic> message) {
    final raw = message['community_message_reactions'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();
    final uid = Supabase.instance.client.auth.currentUser?.id;

    final counts = <String, int>{};
    final mineEmojis = <String>{};
    for (final r in raw) {
      if (r is! Map) continue;
      final emoji = r['emoji']?.toString();
      if (emoji == null || emoji.isEmpty) continue;
      counts[emoji] = (counts[emoji] ?? 0) + 1;
      if (r['user_id'] == uid) mineEmojis.add(emoji);
    }
    if (counts.isEmpty) return const SizedBox.shrink();

    final id = message['id']?.toString();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final entry in counts.entries)
            _reactionPill(
              entry.key,
              entry.value,
              mine: mineEmojis.contains(entry.key),
              messageId: id,
            ),
        ],
      ),
    );
  }

  Widget _reactionPill(
    String emoji,
    int count, {
    required bool mine,
    required String? messageId,
  }) {
    return GestureDetector(
      onTap: messageId == null ? null : () => _toggleReaction(messageId, emoji),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: mine
              ? AppAccentColors.accent.withValues(alpha: 0.22)
              : const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: mine
                ? AppAccentColors.accent.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            if (count > 1) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  color: mine ? Colors.white : Colors.white70,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _insertComposerTag(String tag) {
    final text = _messageCtrl.text;
    final needsSpace = text.isNotEmpty && !RegExp(r'\s$').hasMatch(text);
    final next = '$text${needsSpace ? ' ' : ''}$tag ';
    if (next.length > AppInputLimits.communityMessageMaxLength) return;
    _messageCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  Widget _buildComposerTag(String tag) {
    return ActionChip(
      onPressed: () => _insertComposerTag(tag),
      avatar: Icon(
        Icons.alternate_email_rounded,
        color: AppAccentColors.accent,
        size: 15,
      ),
      label: Text(tag),
      labelStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
      backgroundColor: const Color(0xFF0B0E14),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildComposer() {
    final canWrite = _canWrite;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF111620),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyToMessage != null) ...[
              _ComposerPreview(
                icon: Icons.reply_rounded,
                title: 'Antwort auf Post',
                text: _replyToMessage?['body']?.toString() ?? 'Post',
                onClear: () => setState(() => _replyToMessage = null),
              ),
              const SizedBox(height: 8),
            ],
            if (_attachedRoute != null) ...[
              _ComposerPreview(
                icon: Icons.route_rounded,
                title: 'Route am Post',
                text:
                    '${_attachedRoute!.styleEmoji} ${_attachedRoute!.name ?? _attachedRoute!.style}',
                onClear: () => setState(() => _attachedRoute = null),
              ),
              const SizedBox(height: 8),
            ],
            if (!canWrite)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0E14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.admin_panel_settings_outlined,
                      color: AppAccentColors.accent.withValues(alpha: 0.78),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      // 2026-08-23 (Auftrag Vucko): Der alte Satz „Nur Admins
                      // koennen hier posten." war ungenau. Gemessen an der
                      // Regel `members_write_community_messages`: im
                      // nur-Admin-Modus duerfen owner UND moderator schreiben.
                      // Und nach Vuckos Entscheidung vom 23.08.2026 sind nur
                      // BEITRAEGE gesperrt, das Reagieren bleibt allen offen
                      // (Regel `cmr_insert` verlangt nur Mitgliedschaft).
                      child: Text(
                        'Nur Admins und Moderatoren posten hier. Reagieren geht für alle.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildComposerTag('@Gruppenfahrt'),
                      const SizedBox(width: 8),
                      _buildComposerTag('@Gruppenfahrten'),
                      const SizedBox(width: 8),
                      _buildComposerTag('@Gruppen'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton(
                      tooltip: 'Route anhängen',
                      onPressed: _showRoutePicker,
                      icon: Icon(
                        Icons.add_link_rounded,
                        color: AppAccentColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _messageCtrl,
                      maxLength: AppInputLimits.communityMessageMaxLength,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Post schreiben',
                        hintStyle: const TextStyle(color: Colors.grey),
                        counterText: '',
                        filled: true,
                        fillColor: const Color(0xFF0B0E14),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton.filled(
                      onPressed: _sending ? null : _send,
                      style: IconButton.styleFrom(
                        backgroundColor: AppAccentColors.accent,
                        disabledBackgroundColor: Colors.grey[800],
                      ),
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 18,
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }


  // --------------------------------------------------------------------------
  // 2026-08-24 (Auftrag Vucko): Chat-Art, Bearbeiten, Löschen, Verlauf
  // --------------------------------------------------------------------------

  /// Liest die bevorzugte Darstellung — erst vom Gerät (sofort), dann vom
  /// Konto (Wahrheit). Hat der Nutzer in der Zwischenzeit selbst umgeschaltet,
  /// gewinnt seine Wahl: eine langsame Antwort darf einen Tipp nicht
  /// zurückdrehen.
  Future<void> _ladeDarstellung() async {
    final vomGeraet = await CommunityChatService.chatDarstellungVomGeraet();
    if (mounted && vomGeraet != null && !_wahlGetroffen) {
      setState(() => _darstellung = vomGeraet);
    }
    final vomKonto = await CommunityChatService.chatDarstellungVomKonto();
    if (!mounted || vomKonto == null || _wahlGetroffen) return;
    setState(() => _darstellung = vomKonto);
  }

  void _subscribeVerlauf() {
    _verlaufChannel = CommunityChatService.subscribeVerlauf(
      widget.communityId,
      () {
        _reloadDebounce?.cancel();
        _reloadDebounce = Timer(const Duration(milliseconds: 160), () {
          if (mounted) _load(scrollToBottom: false);
        });
      },
    );
  }

  /// Wechselt zwischen Beitragsansicht und Nachrichten-Ansicht.
  ///
  /// „Es soll zuverlaessig sein" (Vucko) heißt hier drei Dinge:
  ///  * Es wird NICHTS nachgeladen. Beide Ansichten zeichnen dieselbe Liste
  ///    aus dem Zustand dieser Seite.
  ///  * Es springt nicht. Die Zeile, die gerade oben im Bild steht, wird
  ///    gemerkt und nach dem Umschalten wieder angesteuert — die Höhen der
  ///    beiden Darstellungen sind verschieden, ein einfaches Beibehalten der
  ///    Rollposition landete irgendwo.
  ///  * Die Wahl überlebt den Neustart: sie geht sofort ans Gerät und ans
  ///    Konto (`profiles.chat_darstellung`).
  void _wechsleDarstellung() {
    final anker = _ankerZeile();
    final neu = _darstellung == ChatDarstellung.standard
        ? ChatDarstellung.nachrichten
        : ChatDarstellung.standard;
    setState(() {
      _darstellung = neu;
      _wahlGetroffen = true;
    });
    unawaited(CommunityChatService.merkeChatDarstellung(neu));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (anker != null) {
        _scrollToMessage(anker);
      } else {
        _scrollToBottom();
      }
    });
    _showToast('Ansicht: ${neu.titel}');
  }

  /// Die oberste Zeile, die gerade im Bild steht. Sie ist der Anker beim
  /// Umschalten der Darstellung.
  String? _ankerZeile() {
    if (!_scrollCtrl.hasClients) return null;
    final listenBox = _listenKey.currentContext?.findRenderObject();
    final listenOberkante = listenBox is RenderBox && listenBox.hasSize
        ? listenBox.localToGlobal(Offset.zero).dy
        : 0.0;
    String? bester;
    var besteEntfernung = double.infinity;
    for (final zeile in _zeilen()) {
      final id = zeile.id;
      if (id == null) continue;
      final ctx = _messageKeys[id]?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final oben = box.localToGlobal(Offset.zero).dy - listenOberkante;
      if (oben < -4) continue;
      if (oben < besteEntfernung) {
        besteEntfernung = oben;
        bester = id;
      }
    }
    return bester;
  }

  /// Die Zeitleiste: Nachrichten, Grabsteine und die Zu- und Abgänge.
  ///
  /// Die Zu- und Abgänge erscheinen nur unter „Alles". Unter einem Themen-
  /// filter („@Gruppenfahrten") wären sie Beiwerk, das nicht zum Filter passt.
  List<ChatZeile> _zeilen() {
    return CommunityChatTimeline.baue(
      nachrichten: _visibleMessages(),
      verlauf: _postFilter == _CommunityChatPostFilter.all
          ? _verlauf
          : const [],
      ausgeblendet: _ausgeblendet,
      angepinntZuerst: _darstellung == ChatDarstellung.standard,
    );
  }

  /// Der Text, der im Antwort-Zitat steht.
  ///
  /// Vorher stand hier `repliedMessage?['body'] ?? 'Antwort anzeigen'`. Seit
  /// eine gelöschte Nachricht als Grabstein in der Liste bleibt, hätte das
  /// eine leere Zeile ergeben.
  String _zitatText(String? messageId) {
    final message = _messageById(messageId);
    if (message == null) return 'Antwort anzeigen';
    if (message['_geloescht'] == true) return communityGeloeschtText;
    final body = message['body']?.toString() ?? '';
    if (body.isNotEmpty) return body;
    return _routeAttachmentFrom(message) != null
        ? 'Route geteilt'
        : 'Antwort anzeigen';
  }

  /// Wie lange die Nachricht noch bearbeitet werden darf — gerechnet gegen die
  /// SERVERZEIT. `null` heißt „unbekannt", nicht „abgelaufen".
  Duration? _verbleibendeFrist(Map<String, dynamic> message) {
    return CommunityChatService.verbleibendeBearbeitungszeit(
      erstelltAm: DateTime.tryParse(message['created_at']?.toString() ?? ''),
      serverJetzt: Serverzeit.jetzt,
    );
  }

  /// Bearbeiten. Der Server setzt die Frist durch, dieser Dialog zeigt sie.
  ///
  /// Der Zähler läuft mit: schlägt es null, schließt sich der Dialog von
  /// selbst. Das ist ehrlicher, als den Nutzer noch zu Ende tippen zu lassen
  /// und ihn dann in eine Ablehnung laufen zu lassen.
  Future<void> _bearbeiteNachricht(Map<String, dynamic> message) async {
    final id = message['id']?.toString();
    if (id == null || id.isEmpty || id.startsWith('local-')) return;
    final alterText = message['body']?.toString() ?? '';
    final ctrl = TextEditingController(text: alterText);
    // Der Zaehler laeuft, solange der Dialog offen ist. Er wird unten wieder
    // abgestellt — ein Timer.periodic, den niemand abstellt, laeuft bis zum
    // Ende der App weiter.
    Timer? ticker;

    final neuerText = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setzeDialog) {
            ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
              if (!builderContext.mounted) return;
              final rest = _verbleibendeFrist(message);
              if (rest != null && rest <= Duration.zero) {
                Navigator.pop(dialogContext);
                return;
              }
              setzeDialog(() {});
            });
            final rest = _verbleibendeFrist(message);
            return AlertDialog(
              backgroundColor: const Color(0xFF151821),
              title: const Text(
                'Nachricht bearbeiten',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 6,
                    maxLength: AppInputLimits.communityMessageMaxLength,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: const Color(0xFF0B0E14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: Colors.white38,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          rest == null
                              // Ohne gemessene Serverzeit wird KEINE Frist
                              // behauptet. Ein „noch 6 Stunden", das auf der
                              // Geraeteuhr beruht, waere geraten.
                              ? 'Bearbeiten geht 6 Stunden lang. Die genaue '
                                    'Restzeit kommt vom Server.'
                              : CommunityChatService.fristText(rest),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'Abbrechen',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, ctrl.text),
                  child: Text(
                    'Speichern',
                    style: TextStyle(
                      color: AppAccentColors.accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    ticker?.cancel();
    ctrl.dispose();
    if (!mounted) return;
    final sauber = neuerText?.trim();
    if (sauber == null || sauber.isEmpty || sauber == alterText.trim()) return;

    final vorher = List<Map<String, dynamic>>.from(_messages);
    setState(() {
      _messages = [
        for (final eintrag in _messages)
          if (eintrag['id']?.toString() == id)
            {
              ...eintrag,
              'body': sauber,
              'bearbeitet_am': DateTime.now().toUtc().toIso8601String(),
            }
          else
            eintrag,
      ];
    });
    try {
      await CommunityChatService.editMessage(messageId: id, body: sauber);
      unawaited(_load(scrollToBottom: false));
      if (mounted) _showToast('Nachricht bearbeitet.');
    } catch (e) {
      if (mounted) setState(() => _messages = vorher);
      _showError(e, fallback: 'Nachricht konnte nicht bearbeitet werden.');
    }
  }

  /// Für alle löschen. MIT Rückfrage: das trifft jeden anderen und lässt sich
  /// nicht zurückholen.
  Future<void> _loescheFuerAlle(Map<String, dynamic> message) async {
    final id = message['id']?.toString();
    if (id == null || id.isEmpty) return;
    if (id.startsWith('local-')) {
      setState(() {
        _messages = _messages.where((entry) => entry['id'] != id).toList();
      });
      return;
    }

    final sicher = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151821),
        title: const Text(
          'Für alle löschen?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Die Nachricht verschwindet bei allen Mitgliedern. An ihrer Stelle '
          'steht „Diese Nachricht wurde gelöscht." Das lässt sich nicht '
          'rückgängig machen.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Abbrechen',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Für alle löschen',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
    if (sicher != true || !mounted) return;

    final vorher = List<Map<String, dynamic>>.from(_messages);
    setState(() {
      _messages = [
        for (final eintrag in _messages)
          if (eintrag['id']?.toString() == id)
            {
              ...eintrag,
              'body': '',
              'route_attachment': null,
              'community_message_reactions': const <Map<String, dynamic>>[],
              '_geloescht': true,
              'deleted_at': DateTime.now().toUtc().toIso8601String(),
            }
          else
            eintrag,
      ];
    });
    try {
      await CommunityChatService.deleteMessage(id, fuerAlle: true);
      unawaited(_load(scrollToBottom: false));
    } catch (e) {
      if (mounted) setState(() => _messages = vorher);
      _showError(e, fallback: 'Nachricht konnte nicht gelöscht werden.');
    }
  }

  /// Nur für mich löschen. OHNE Rückfrage — aber mit „Rückgängig".
  ///
  /// Die Abwägung: eine Rückfrage schützt vor einem Fehlgriff, der hier nur
  /// die eigene Ansicht trifft und niemandem sonst etwas wegnimmt. Ein
  /// „Rückgängig" im Hinweis ist die bessere Antwort auf denselben Fehlgriff:
  /// es kostet keinen zusätzlichen Tipp im Normalfall und macht den Fehler
  /// wirklich rückgängig, statt ihn nur zu bestätigen. Bei „für alle" geht das
  /// nicht — deshalb steht dort die Rückfrage.
  Future<void> _loescheNurFuerMich(Map<String, dynamic> message) async {
    final id = message['id']?.toString();
    if (id == null || id.isEmpty) return;
    if (id.startsWith('local-')) {
      setState(() {
        _messages = _messages.where((entry) => entry['id'] != id).toList();
      });
      return;
    }

    setState(() => _ausgeblendet = {..._ausgeblendet, id});
    try {
      await CommunityChatService.deleteMessage(id, fuerAlle: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Nur bei dir entfernt.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          backgroundColor: const Color(0xFF171B24),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          action: SnackBarAction(
            label: 'Rückgängig',
            textColor: AppAccentColors.accent,
            onPressed: () => unawaited(_zeigeWiederAn(id)),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _ausgeblendet = {..._ausgeblendet}..remove(id);
        });
      }
      _showError(e, fallback: 'Nachricht konnte nicht entfernt werden.');
    }
  }

  Future<void> _zeigeWiederAn(String messageId) async {
    setState(() {
      _ausgeblendet = {..._ausgeblendet}..remove(messageId);
    });
    try {
      await CommunityChatService.zeigeNachrichtWiederAn(messageId);
    } catch (e) {
      if (mounted) {
        setState(() => _ausgeblendet = {..._ausgeblendet, messageId});
      }
      _showError(e, fallback: 'Konnte nicht zurückgeholt werden.');
    }
  }

  /// Der Grabstein in der Beitragsansicht.
  Widget _buildGeloeschtKarte(Map<String, dynamic> message) {
    final rawProfile = message['profiles'];
    final profile = rawProfile is Map
        ? Map<String, dynamic>.from(rawProfile)
        : <String, dynamic>{};
    final name = CommunityChatService.displayName(
      profile,
      fallbackUserId: message['user_id'] as String?,
    );
    final time = _formatMessageTime(message['created_at'] as String?);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => _showMessageActions(message),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            children: [
              const Icon(Icons.block_rounded, size: 15, color: Colors.white38),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$name · $time',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      communityGeloeschtText,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMessageTime(String? raw) {
    final dt = DateTime.tryParse(raw ?? '')?.toLocal();
    if (dt == null) return '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _PostAction extends StatelessWidget {
  const _PostAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.grey, size: 18),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerPreview extends StatelessWidget {
  const _ComposerPreview({
    required this.icon,
    required this.title,
    required this.text,
    required this.onClear,
  });

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppAccentColors.accent, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _MessageActionTile extends StatelessWidget {
  const _MessageActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.hinweis,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  /// 2026-08-24: die zweite Zeile unter dem Eintrag — die verbleibende
  /// Bearbeitungszeit oder der Satz, der sagt, WEN das Loeschen trifft.
  final String? hinweis;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.redAccent : Colors.white;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
      subtitle: hinweis == null
          ? null
          : Text(
              hinweis!,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

class CommunityMembersSheet extends StatefulWidget {
  const CommunityMembersSheet({
    required this.communityId,
    required this.initialMembers,
    required this.ownerOnlyMessages,
    required this.onChanged,
    super.key,
  });

  final String communityId;
  final List<Map<String, dynamic>> initialMembers;
  final bool ownerOnlyMessages;
  final Future<void> Function() onChanged;

  @override
  State<CommunityMembersSheet> createState() => _CommunityMembersSheetState();
}

class _CommunityMembersSheetState extends State<CommunityMembersSheet> {
  List<Map<String, dynamic>> _members = [];
  bool _loading = false;
  String? _busyUserId;

  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  String? get _myRole {
    final uid = _myId;
    if (uid == null) return null;
    for (final member in _members) {
      if (member['user_id'] == uid) return member['role']?.toString();
    }
    return null;
  }

  bool get _amAdmin => _myRole == 'owner';
  bool get _amModerator => _myRole == 'moderator';

  @override
  void initState() {
    super.initState();
    _members = widget.initialMembers;
    if (_members.isEmpty) _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _loading = true);
    try {
      final members = await CommunityChatService.fetchMembers(
        widget.communityId,
      );
      if (!mounted) return;
      setState(() {
        _members = members;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(e);
    }
  }

  Future<void> _setRole(String userId, String role) async {
    setState(() => _busyUserId = userId);
    try {
      await CommunityChatService.setMemberRole(
        communityId: widget.communityId,
        userId: userId,
        role: role,
      );
      await _loadMembers();
      await widget.onChanged();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  Future<void> _removeMember(String userId) async {
    setState(() => _busyUserId = userId);
    try {
      await CommunityChatService.removeMember(
        communityId: widget.communityId,
        userId: userId,
      );
      await _loadMembers();
      await widget.onChanged();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  String _friendlyError(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    final isBackendNoise =
        lower.contains('postgrest') ||
        lower.contains('supabase') ||
        lower.contains('row-level') ||
        lower.contains('rls') ||
        lower.contains('policy') ||
        lower.contains('permission') ||
        lower.contains('schema cache') ||
        lower.contains('violates');
    if (raw.trim().isEmpty || isBackendNoise || raw.length > 110) {
      return 'Aktion gerade nicht möglich.';
    }
    return raw;
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _friendlyError(error),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: const Color(0xFF301B20),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1350),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.72;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Mitglieder',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _roleChip(_myRole, compact: true),
                ],
              ),
            ),
            if (widget.ownerOnlyMessages)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.orangeAccent.withValues(alpha: 0.22),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.admin_panel_settings_outlined,
                        color: Colors.orangeAccent,
                        size: 17,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Nur Admins können in diesem Chat schreiben.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: AppAccentColors.accent,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                      itemBuilder: (context, index) =>
                          _buildMemberTile(_members[index]),
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                      itemCount: _members.length,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member) {
    final profile = _profile(member);
    final userId = member['user_id']?.toString() ?? '';
    final role = member['role']?.toString();
    final isMe = userId == _myId;
    final name = CommunityChatService.displayName(
      profile,
      fallbackUserId: userId,
    );
    final busy = _busyUserId == userId;
    final actions = _actionsFor(member);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      leading: UserAvatar.fromProfile(profile, fallbackName: name, radius: 22),
      title: Row(
        children: [
          Expanded(
            child: Text(
              isMe ? '$name · Du' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: _roleChip(role),
      ),
      trailing: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : actions.isEmpty
          ? null
          : PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, color: Colors.white70),
              color: const Color(0xFF1C1F26),
              onSelected: (value) {
                if (value == 'remove') {
                  _removeMember(userId);
                } else {
                  _setRole(userId, value);
                }
              },
              itemBuilder: (_) => actions,
            ),
    );
  }

  List<PopupMenuEntry<String>> _actionsFor(Map<String, dynamic> member) {
    final userId = member['user_id']?.toString();
    final role = member['role']?.toString();
    final isMe = userId == _myId;
    final entries = <PopupMenuEntry<String>>[];

    if (_amAdmin) {
      if (role != 'owner') {
        entries.add(
          _roleMenuItem('owner', Icons.admin_panel_settings, 'Admin'),
        );
      }
      if (role != 'moderator') {
        entries.add(_roleMenuItem('moderator', Icons.shield, 'Moderator'));
      }
      if (role != 'member') {
        entries.add(_roleMenuItem('member', Icons.person, 'User'));
      }
      if (!isMe) {
        entries.add(const PopupMenuDivider());
        entries.add(_removeMenuItem());
      }
      return entries;
    }

    if (_amModerator && !isMe && role == 'member') {
      entries.add(_removeMenuItem());
    }
    return entries;
  }

  PopupMenuItem<String> _roleMenuItem(
    String value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: AppAccentColors.accent, size: 18),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  PopupMenuItem<String> _removeMenuItem() {
    return const PopupMenuItem(
      value: 'remove',
      child: Row(
        children: [
          Icon(Icons.person_remove_outlined, color: Colors.redAccent, size: 18),
          SizedBox(width: 10),
          Text('Entfernen', style: TextStyle(color: Colors.redAccent)),
        ],
      ),
    );
  }

  Widget _roleChip(String? role, {bool compact = false}) {
    final color = _roleColor(role);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 8,
        vertical: compact ? 5 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_roleIcon(role), color: color, size: compact ? 14 : 12),
          const SizedBox(width: 5),
          Text(
            CommunityChatService.roleLabel(role),
            style: TextStyle(
              color: color,
              fontSize: compact ? 12 : 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'owner':
        return Colors.redAccent;
      case 'moderator':
        return Colors.lightBlueAccent;
      default:
        return Colors.white70;
    }
  }

  IconData _roleIcon(String? role) {
    switch (role) {
      case 'owner':
        return Icons.admin_panel_settings;
      case 'moderator':
        return Icons.shield;
      default:
        return Icons.person;
    }
  }

  Map<String, dynamic>? _profile(Map<String, dynamic> member) {
    final profile = member['profiles'];
    if (profile is Map) return Map<String, dynamic>.from(profile);
    return null;
  }
}
