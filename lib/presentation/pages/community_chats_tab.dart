import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cruise_connect/presentation/widgets/skeletons/skeleton.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/deep_links.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/data/services/community_neuigkeit_service.dart';
import 'package:cruise_connect/presentation/pages/community_chat_detail_page.dart';
import 'package:cruise_connect/presentation/pages/community_einstieg.dart';
import 'package:cruise_connect/presentation/pages/community_settings_page.dart';
import 'package:cruise_connect/presentation/pages/community_teilen_blatt.dart';
import 'package:cruise_connect/presentation/widgets/community_avatar.dart';
import 'package:cruise_connect/presentation/widgets/community/community_filter_leiste.dart';
import 'package:cruise_connect/presentation/widgets/community/community_vorschau_blatt.dart';

class CommunityChatsTab extends StatefulWidget {
  const CommunityChatsTab({super.key});

  @override
  State<CommunityChatsTab> createState() => _CommunityChatsTabState();
}

class _CommunityChatsTabState extends State<CommunityChatsTab> {
  final _codeSearchController = TextEditingController();
  bool _loading = true;
  bool _codeSearchLoading = false;
  List<Map<String, dynamic>> _myCommunities = [];
  List<Map<String, dynamic>> _discoverCommunities = [];
  Map<String, dynamic>? _codeSearchResult;

  /// 2026-08-24 (Auftrag Vucko, Aufgabe 2): die Filterwahl. Sie überlebt den
  /// App-Neustart, deshalb liegt sie im Dienst und nicht in diesem State.
  final _filter = CommunityFilterEinstellungen.instance;

  /// Die Auswahlliste der Regionen. Leer, solange sie noch nicht da ist —
  /// dann steht im Blatt nur „Alle Regionen".
  List<CommunityRegion> _regionen = const <CommunityRegion>[];

  /// 2026-08-25 (Auftrag Vucko): das erkannte Land. Es beschneidet die
  /// AUSWAHLLISTE der Regionen an beiden Stellen, an denen es Regionen gibt —
  /// im Filter hier unten und im Blatt „Community erstellen".
  ///
  /// Es setzt BEWUSST keinen Filter. Würde das Land den Regionsfilter selbst
  /// setzen, verschwänden Communities, ohne dass jemand etwas angetippt hat.
  final _standortLand = CommunityStandortLand.instance;

  /// Der Suchtext, wie er zuletzt an die Datenbank gegangen ist.
  String _suchtext = '';

  /// Entprellt das Tippen im Suchfeld. Ohne das ginge bei „Vorarlberg" eine
  /// Abfrage je Buchstabe raus.
  Timer? _sucheTimer;

  static const Duration _sucheVerzoegerung = Duration(milliseconds: 350);

  @override
  void dispose() {
    _sucheTimer?.cancel();
    _filter.removeListener(_filterGeaendert);
    _standortLand.removeListener(_landGeaendert);
    _codeSearchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _filter.addListener(_filterGeaendert);
    _standortLand.addListener(_landGeaendert);
    _starten();
  }

  /// Erst die gemerkte Filterwahl, dann die Liste. In dieser Reihenfolge,
  /// sonst zeigt der erste Aufbau ungefiltert alles und schiebt eine
  /// Zehntelsekunde später um.
  Future<void> _starten() async {
    await _filter.laden();
    if (!mounted) return;
    unawaited(_regionenLaden());
    unawaited(_landErmitteln());
    await _load();
  }

  /// Das Land, in zwei Schritten.
  ///
  /// DIE REIHENFOLGE IST DER PUNKT: `laden()` holt das zuletzt erkannte Land
  /// aus den Einstellungen und ist sofort da. `aktualisieren()` fragt danach
  /// Standort und Profil und schiebt nach. Beides läuft NEBEN dem Laden der
  /// Liste — die Liste wartet nie auf eine Standortfreigabe, und bis das Land
  /// feststeht, stehen ALLE Regionen zur Wahl statt gar keiner.
  Future<void> _landErmitteln() async {
    await _standortLand.laden();
    if (!mounted) return;
    await _standortLand.aktualisieren();
  }

  /// Das erkannte Land hat sich geändert: nur neu zeichnen.
  ///
  /// KEIN Neuladen der Listen. Das Land beschneidet die Auswahlliste, es
  /// filtert keine Community weg — eine Abfrage dafür wäre eine Abfrage für
  /// nichts.
  void _landGeaendert() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _regionenLaden() async {
    final regionen = await CommunityChatService.regionenLaden();
    if (!mounted || regionen.isEmpty) return;
    setState(() => _regionen = regionen);
  }

  /// Der Filter hat sich geändert: sofort neu laden. Die Wahl selbst ist im
  /// selben Augenblick schon sichtbar, weil der Dienst ein ChangeNotifier ist.
  void _filterGeaendert() {
    if (!mounted) return;
    setState(() {});
    unawaited(_load());
  }

  /// Lädt beide Listen.
  ///
  /// FAHRZEUGART UND REGION GEHEN NUR IN DIE ÖFFENTLICHE LISTE. Vucko:
  /// „einen filter haben bei oeffentliche communitys". Würden sie auch für
  /// „Meine Communities" gelten, verschwänden dem Nutzer seine eigenen
  /// Communities, sobald er nach Motorrad filtert — das wäre kein Filter,
  /// das wäre ein Verlust.
  ///
  /// Die SUCHE gilt für beide: wer einen Namen tippt, sucht die Community und
  /// nicht die Liste, in der sie zufällig steht.
  ///
  /// Die Sortierwahl gilt ebenfalls nur für die öffentliche Liste. „Meine
  /// Communities" steht fest auf „Aktiv" — das ist die Reihenfolge, die jeder
  /// Messenger benutzt, und Angepinntes steht ohnehin darüber.
  Future<void> _load() async {
    try {
      final results = await Future.wait([
        CommunityChatService.communitiesLaden(
          bereich: CommunityListe.meine,
          suche: _suchtext,
        ),
        CommunityChatService.communitiesLaden(
          bereich: CommunityListe.entdecken,
          fahrzeugart: _filter.fahrzeugart,
          regionCode: _filter.regionCode,
          suche: _suchtext,
          sortierung: _filter.sortierung,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _myCommunities = results[0];
        _discoverCommunities = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Communities konnten nicht geladen werden.');
    }
  }

  Future<void> _openCommunity(String communityId) async {
    // 2026-08-24 (Aufgabe 1.1, Ebene 3). Vucko: „Wenn man in der Community
    // draufdrückt, dann halt das nochmal benachrichtigungsmäßig — wie, in
    // welcher Community das jetzt genau war."
    //
    // Der Punkt geht genau HIER aus, beim wirklichen Öffnen, nicht schon
    // beim Öffnen des Chats-Reiters. Das ist das Verhalten, das jeder aus
    // WhatsApp kennt.
    unawaited(
      CommunityNeuigkeitService.instance.alsGesehenMarkieren(
        CommunityBereich.community,
        communityId: communityId,
      ),
    );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityChatDetailPage(communityId: communityId),
      ),
    );
    if (mounted) _load();
  }

  /// 2026-08-24 (Auftrag Vucko, dringend): „wenn man auf eine community
  /// klickt, dass man direkt beitritt ohne beitrettbutton -> fixxen".
  ///
  /// Hier stand vorher `_joinCommunity`, und es hing am `onTap` der KOMPLETTEN
  /// Kachel. Ein Tipp auf Bild, Name oder Beschreibung einer fremden Community
  /// machte einen sofort zum Mitglied, ohne Rueckfrage und ohne dass man
  /// gesehen haette, worum es geht.
  ///
  /// Jetzt faellt die Entscheidung in genau einer Funktion,
  /// [communityKachelZiel]: Mitglied fuehrt in den Chat, alle anderen in die
  /// Vorschau. Ein Beitritt kann von hier aus gar nicht mehr ausgeloest
  /// werden, dafuer gibt es nur noch den Knopf im Vorschau-Blatt.
  Future<void> _kachelGetippt(
    Map<String, dynamic> community, {
    required bool istMitglied,
    String? inviteCode,
  }) async {
    switch (communityKachelZiel(istMitglied: istMitglied)) {
      case CommunityKachelZiel.chat:
        final id = community['id']?.toString();
        if (id != null && id.isNotEmpty) await _openCommunity(id);
      case CommunityKachelZiel.vorschau:
        await _zeigeCommunityVorschau(community, inviteCode: inviteCode);
    }
  }

  /// Zeigt die Vorschau und raeumt danach auf.
  ///
  /// Nach einem erfolgreichen Beitritt wird ZUERST die Liste neu geladen und
  /// erst dann der Chat geoeffnet: die Community wandert von „Öffentliche
  /// Communities" zu „Meine Communities" und die Mitgliederzahl steigt um
  /// eins. Kommt der Nutzer aus dem Chat zurueck, stimmt die Liste damit
  /// schon, statt erst beim naechsten Herunterziehen.
  Future<void> _zeigeCommunityVorschau(
    Map<String, dynamic> community, {
    String? inviteCode,
  }) async {
    final ergebnis = await CommunityVorschauBlatt.zeigen(
      context,
      community: community,
      istMitglied: CommunityChatService.isCurrentUserMember(community),
      onBeitreten: () => _beitrittAusfuehren(community, inviteCode: inviteCode),
    );
    if (!mounted || ergebnis == null) return;
    await _load();
    if (!mounted || !ergebnis.oeffnetChat) return;
    final id = ergebnis.communityId.isNotEmpty
        ? ergebnis.communityId
        : (community['id']?.toString() ?? '');
    if (id.isNotEmpty) await _openCommunity(id);
  }

  /// Der einzige Weg in eine Mitgliedschaft, der aus dieser Seite heraus noch
  /// existiert. Wird ausschliesslich vom Knopf im Vorschau-Blatt gerufen.
  ///
  /// Zwei Wege, ein Ergebnis:
  /// - ohne Einladungscode (Entdecken-Liste): direkter Eintrag, geht nur bei
  ///   oeffentlichen Communities. Eine private Community landet gar nicht
  ///   erst in dieser Liste, und faellt sie doch einmal hinein, antwortet die
  ///   Datenbank mit 42501 und der Dienst mit dem passenden Satz.
  /// - mit Einladungscode: die RPC entscheidet, und bei einer privaten
  ///   Community wird daraus eine Beitrittsanfrage beim Admin (Entscheidung
  ///   Vucko vom 23.08.), kein Beitritt.
  /// 2026-08-31: Der Rumpf ist nach [communityBeitrittAusfuehren] in
  /// community_einstieg.dart gewandert, unveraendert. Grund: Seit heute fuehrt
  /// ein zweiter Weg in dieselbe Vorschau, naemlich ein geteilter Link von
  /// aussen. Zwei Abschriften derselben Entscheidung waeren im ersten Monat
  /// auseinandergelaufen, und es ist genau die Entscheidung, die ein
  /// Mitglied erzeugt.
  Future<CommunityBeitrittsErgebnis> _beitrittAusfuehren(
    Map<String, dynamic> community, {
    String? inviteCode,
  }) {
    return communityBeitrittAusfuehren(
      communityId: community['id']?.toString() ?? '',
      inviteCode: inviteCode,
    );
  }

  /// 2026-08-31 (Auftrag Vucko „Communities teilen"): Hier stand
  /// `normalizeInviteCode`. Seit heute kursieren geteilte LINKS, und ein
  /// eingefuegter Link kam an dieser Stelle als `null` an, das Feld tat
  /// einfach nichts. [CommunityChatService.einladungscodeAusEingabe] nimmt
  /// beides, den blossen Code und den ganzen Link. Begruendung steht dort.
  Future<void> _lookupCommunityCode(String raw) async {
    final normalized = CommunityChatService.einladungscodeAusEingabe(raw);
    if (normalized == null) {
      setState(() {
        _codeSearchResult = null;
        _codeSearchLoading = false;
      });
      return;
    }
    setState(() => _codeSearchLoading = true);
    final result = await CommunityChatService.findCommunityByCode(normalized);
    if (!mounted || _codeSearchController.text.trim() != raw.trim()) return;
    setState(() {
      _codeSearchResult = result;
      _codeSearchLoading = false;
    });
  }

  /// 2026-08-24 (Auftrag Vucko, Aufgabe 2): Das Feld kann jetzt ZWEIERLEI.
  ///
  /// Gemessen vorher: `onChanged` rief nur [_lookupCommunityCode], und
  /// [CommunityChatService.normalizeInviteCode] liefert für alles, was nicht
  /// wie `CCC-XXXXXX` aussieht, `null`. Wer „Opel" tippte, löste also
  /// buchstäblich nichts aus — das Feld sah aus wie eine Suche und war keine.
  ///
  /// Jetzt geht der Text ZUSÄTZLICH als `p_suche` an
  /// `get_communities_gefiltert` (Name und Beschreibung, groß-/klein egal).
  /// Der Code-Weg bleibt unangetastet daneben stehen.
  ///
  /// Entprellt, weil sonst je Buchstabe zwei Abfragen rausgingen.
  void _sucheGeaendert(String roh) {
    _lookupCommunityCode(roh);
    _sucheTimer?.cancel();
    _sucheTimer = Timer(_sucheVerzoegerung, () {
      final text = roh.trim();
      if (!mounted || text == _suchtext) return;
      _suchtext = text;
      unawaited(_load());
    });
  }

  /// 2026-08-24 (Auftrag Vucko, Aufgabe 1): „man soll auch community anpinnen
  /// koennen".
  ///
  /// WARUM DER EINTRAG IM DREI-PUNKTE-MENÜ und nicht langer Druck oder
  /// Wischen: Dieses Menü ([_buildCommunityMenu]) ist in dieser App die
  /// Stelle, an der Kachel-Aktionen stehen — Mitglieder, Einstellungen,
  /// Verlassen, Löschen. Ein langer Druck ist im Community-Chat schon
  /// besetzt (Emoji-Reaktionen), und eine Wischgeste gibt es in der ganzen
  /// App an keiner einzigen Liste. Eine neue Geste einzuführen hiesse, sie
  /// erklären zu müssen; ein siebter Menüeintrag erklärt sich selbst.
  ///
  /// RÜCKMELDUNG (Optimistic-UI-Grundsatz dieses Projekts): Die Kachel
  /// bekommt die Nadel und springt SOFORT nach oben, bevor der Server
  /// geantwortet hat. Geht es schief, rutscht sie zurück und es steht da,
  /// warum. Die 10er-Grenze der Datenbank ist genau so ein Fall.
  /// 2026-08-31 (Auftrag Vucko „Communities teilen"): Teilen aus der Liste.
  ///
  /// Der Link braucht den Einladungscode, und der kommt aus der RPC
  /// `get_community_invite_code`, die nur Mitgliedern antwortet. In der Liste
  /// steht er nicht: `_communitySelect` hat die Spalte am 23.08. bewusst
  /// verloren, weil sie sonst fuer jeden lesbar waere. Also wird er hier
  /// einzeln geholt, und zwar erst beim Tippen und nicht fuer jede Kachel auf
  /// Vorrat.
  Future<void> _teilen(Map<String, dynamic> community) async {
    final id = community['id']?.toString();
    if (id == null || id.isEmpty) return;
    final code = await CommunityChatService.inviteCodeFor(id);
    if (!mounted) return;
    if (code == null || code.isEmpty) {
      _showMessage('Der Link ist gerade nicht abrufbar.');
      return;
    }
    await CommunityTeilenBlatt.zeigenUndAusfuehren(
      context,
      community: community,
      einladungsCode: code,
    );
  }

  Future<void> _pinUmschalten(Map<String, dynamic> community) async {
    final id = community['id']?.toString();
    if (id == null || id.isEmpty) return;

    final warAngepinnt = CommunityChatService.istAngepinnt(community);
    final alterPlatz = CommunityChatService.pinPosition(community);

    setState(() {
      CommunityChatService.setzePinInZeile(
        community,
        angepinnt: !warAngepinnt,
        // Ans Ende der Pins — genau das macht `community_pin_setzen` auch.
        position: _naechsterPinPlatz(),
      );
      CommunityChatService.sortiereMitPinsZuerst(_myCommunities);
      CommunityChatService.sortiereMitPinsZuerst(_discoverCommunities);
    });
    _showMessage(
      warAngepinnt ? 'Nicht mehr angepinnt.' : 'Oben angepinnt.',
    );

    try {
      final platz = await CommunityChatService.pinSetzen(
        communityId: id,
        angepinnt: !warAngepinnt,
      );
      if (!mounted) return;
      setState(() {
        CommunityChatService.setzePinInZeile(
          community,
          angepinnt: !warAngepinnt,
          position: platz,
        );
        CommunityChatService.sortiereMitPinsZuerst(_myCommunities);
        CommunityChatService.sortiereMitPinsZuerst(_discoverCommunities);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        CommunityChatService.setzePinInZeile(
          community,
          angepinnt: warAngepinnt,
          position: alterPlatz,
        );
        CommunityChatService.sortiereMitPinsZuerst(_myCommunities);
        CommunityChatService.sortiereMitPinsZuerst(_discoverCommunities);
      });
      _showError(e);
    }
  }

  /// Der nächste freie Platz, nur für die sofortige Anzeige. Die Wahrheit
  /// vergibt die Datenbank.
  int _naechsterPinPlatz() {
    var hoechster = 0;
    for (final liste in [_myCommunities, _discoverCommunities]) {
      for (final zeile in liste) {
        final platz = CommunityChatService.pinPosition(zeile);
        if (platz != null && platz > hoechster) hoechster = platz;
      }
    }
    return hoechster + 1;
  }

  /// 2026-08-23 (Entscheidung Vucko, bindend): Ein alter, schon geteilter
  /// Link fuehrt in eine inzwischen private Community NICHT mehr direkt
  /// hinein, sondern loest eine Beitrittsanfrage beim Admin aus.
  ///
  /// Vorher stand hier ein blindes „Code rein, Chat auf". Wuerde das so
  /// bleiben, liefe der Nutzer bei einer privaten Community in eine leere,
  /// nicht lesbare Seite, weil er gar kein Mitglied ist. Deshalb entscheidet
  /// jetzt der Status aus [CommunityJoinResult], ob geoeffnet oder nur
  /// gemeldet wird.
  Future<void> _joinCommunityWithCode(String rawCode) async {
    // 2026-08-31 (Auftrag Vucko „Communities teilen"): Ein eingefuegter LINK
    // nimmt hier NICHT den direkten Weg in die Mitgliedschaft, sondern den
    // ueber die Vorschau. Vucko woertlich: „dass man wieder den Vorschau
    // Bildschirm hat mit kurzer Beschreibung und dem Titel und dass man auf
    // beitreten klicken kann oder nicht."
    //
    // Der blosse Code bleibt bewusst unveraendert beim direkten Weg: Wer
    // einen Code abtippt, hat ihn von jemandem bekommen und weiss, wo er
    // hinwill. Wer einen Link einfuegt, hat ihn irgendwo im Netz gesehen.
    final ausLink = CruiseDeepLinks.communityCodeAus(
      Uri.tryParse(rawCode.trim()) ?? Uri(),
    );
    if (ausLink != null) {
      final code = CommunityChatService.normalizeInviteCode(ausLink);
      if (code != null) {
        _codeSearchController.clear();
        setState(() => _codeSearchResult = null);
        await CommunityEinstieg.oeffnen(code, context: context);
        if (mounted) await _load();
        return;
      }
    }

    try {
      final result = await CommunityChatService.joinCommunityByCode(rawCode);
      if (!mounted) return;
      _codeSearchController.clear();
      setState(() => _codeSearchResult = null);
      _showMessage(result.userMessage);
      if (result.opensCommunity && result.communityId.isNotEmpty) {
        await _openCommunity(result.communityId);
      }
    } catch (e) {
      _showError(e);
    }
  }

  /// Oeffnet die Einstellungs-Seite aus der Uebersicht heraus. Nach einer
  /// Aenderung wird die Liste neu geladen, damit Bild, Name und die
  /// Sichtbarkeits-Plakette sofort stimmen.
  Future<void> _openSettings(Map<String, dynamic> community) async {
    final communityId = community['id']?.toString();
    if (communityId == null) return;
    final result = await Navigator.push<CommunitySettingsResult>(
      context,
      MaterialPageRoute(
        builder: (_) => CommunitySettingsPage(
          communityId: communityId,
          initialCommunity: community,
        ),
      ),
    );
    if (!mounted) return;
    if (result == CommunitySettingsResult.changed ||
        result == CommunitySettingsResult.deleted) {
      await _load();
    }
  }

  void _showMembers(Map<String, dynamic> community) {
    final communityId = community['id']?.toString();
    if (communityId == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CommunityMembersSheet(
        communityId: communityId,
        initialMembers: const [],
        ownerOnlyMessages: community['owner_only_messages'] == true,
        onChanged: _load,
      ),
    );
  }

  Future<void> _confirmLeaveCommunity(Map<String, dynamic> community) async {
    final communityId = community['id']?.toString();
    if (communityId == null) return;

    final isAdmin = CommunityChatService.currentUserRole(community) == 'owner';
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
      await CommunityChatService.leaveCommunity(communityId);
      if (mounted) _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _confirmDeleteCommunity(Map<String, dynamic> community) async {
    final communityId = community['id']?.toString();
    if (communityId == null) return;

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
      await CommunityChatService.deleteCommunity(communityId);
      if (mounted) _load();
    } catch (e) {
      _showError(e);
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

  /// 2026-08-23: neutrale Rueckmeldung (nicht rot). Der Beitritt per Code
  /// kann seit heute fuenf verschiedene Ausgaenge haben, drei davon sind kein
  /// Fehler, sondern eine Beitrittsanfrage.
  void _showMessage(String message) {
    if (!mounted) return;
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
        backgroundColor: const Color(0xFF1C1F26),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2400),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showError(Object message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message is String ? message : _friendlyError(message),
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
    if (_loading) {
      return const SkeletonList(count: 7);
    }

    return RefreshIndicator(
      color: AppAccentColors.accent,
      backgroundColor: const Color(0xFF151821),
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
        children: [
          _buildActionRow(),
          const SizedBox(height: 12),
          _buildInlineCodeSearch(),
          const SizedBox(height: 18),
          _buildSectionHeader('Meine Communities', _myCommunities.length),
          const SizedBox(height: 10),
          if (_myCommunities.isEmpty)
            // 2026-08-24: Die Suche gilt auch für diese Liste. Ohne die
            // Fallunterscheidung stünde hier „Noch keine Community", während
            // der Nutzer nur einen Namen getippt hat, den keine seiner
            // Communities trägt — die falscheste Auskunft, die diese Kachel
            // geben kann.
            _buildEmptyState(
              icon: _suchtext.isEmpty ? Icons.forum_outlined : Icons.search_off,
              title: _suchtext.isEmpty
                  ? 'Noch keine Community'
                  : 'Keine deiner Communities heißt so',
              text: _suchtext.isEmpty
                  ? 'Erstelle eine Community oder tritt mit einem Code bei.'
                  : 'Lösch die Suche, dann siehst du wieder alle.',
            )
          else
            ..._myCommunities.map(
              (community) => _buildCommunityCard(
                community,
                joined: true,
                onTap: () => _kachelGetippt(community, istMitglied: true),
              ),
            ),
          const SizedBox(height: 22),
          _buildSectionHeader(
            'Öffentliche Communities',
            _discoverCommunities.length,
          ),
          const SizedBox(height: 10),
          // 2026-08-24 (Auftrag Vucko, Aufgabe 2): der Filter. Er steht UNTER
          // der Überschrift „Öffentliche Communities" und nicht oben bei der
          // Suche — dort würde er aussehen, als gälte er auch für „Meine
          // Communities", und genau das tut er nicht.
          CommunityFilterLeiste(
            einstellungen: _filter,
            regionen: _regionen,
            landCode: _standortLand.landCode,
            landQuelle: _standortLand.quelle,
            onFahrzeugart: _filter.setzeFahrzeugart,
            onRegion: _filter.setzeRegion,
            onSortierung: _filter.setzeSortierung,
            onZuruecksetzen: _filter.zuruecksetzen,
          ),
          const SizedBox(height: 12),
          if (_discoverCommunities.isEmpty)
            _buildEntdeckenLeer()
          else
            ..._discoverCommunities.map(
              (community) => _buildCommunityCard(
                community,
                joined: false,
                onTap: () => _kachelGetippt(community, istMitglied: false),
              ),
            ),
        ],
      ),
    );
  }

  /// 2026-08-24 (Auftrag Vucko, Aufgabe 2, wörtlich): „sorg dafuer, dass ein
  /// leeres Ergebnis erklaert wird […] statt einfach leer zu sein, und dass
  /// man mit einem Tipp wieder alles sieht."
  ///
  /// Das ist hier kein Randfall, sondern der wahrscheinlichste Ausgang:
  /// gemessen am 24.08.2026 gibt es SECHS Communities. Ein Filter auf
  /// „Motorrad" in „Tirol" trifft mit hoher Wahrscheinlichkeit keine einzige.
  Widget _buildEntdeckenLeer() {
    final erklaerung = communityFilterLeerText(
      filtertEtwasWeg: _filter.filtertEtwasWeg,
      sucheAktiv: _suchtext.isNotEmpty,
    );
    if (erklaerung == null) {
      // Wirklich nichts da — kein Filter, keine Suche.
      return _buildEmptyState(
        icon: Icons.travel_explore,
        title: 'Nichts Neues gefunden',
        text: 'Öffentliche Communities tauchen hier im Entdecken auf.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEmptyState(
          icon: Icons.filter_alt_off_outlined,
          title: erklaerung,
          text: _filter.filtertEtwasWeg
              ? 'Nimm den Filter raus, dann siehst du wieder alle.'
              : 'Lösch die Suche, dann siehst du wieder alle.',
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _alleWiederAnzeigen,
            icon: Icon(
              Icons.refresh,
              color: AppAccentColors.accent,
              size: 17,
            ),
            label: const Text('Alle Communities anzeigen'),
            style: TextButton.styleFrom(
              foregroundColor: AppAccentColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
        ),
      ],
    );
  }

  /// Ein Tipp, und alles ist wieder da: Filter zurück auf „Alle", Suchfeld
  /// leer. Beides zusammen, weil der Nutzer nicht raten soll, welches von
  /// beidem gerade zugeschlagen hat.
  Future<void> _alleWiederAnzeigen() async {
    // VORHER merken: nach dem Zuruecksetzen ist `filtertEtwasWeg` immer
    // false, und die Frage waere nicht mehr zu beantworten. Ohne das laedt
    // die Seite zweimal — einmal ueber den Melder des Filters, einmal von
    // hier.
    final filterWarAktiv = _filter.filtertEtwasWeg;
    _sucheTimer?.cancel();
    _codeSearchController.clear();
    setState(() {
      _suchtext = '';
      _codeSearchResult = null;
    });
    await _filter.zuruecksetzen();
    // zuruecksetzen() meldet nur, wenn wirklich ein Filter gesetzt war — und
    // erst dieser Melder laedt neu. War nur die Suche im Weg, muss das
    // Neuladen von hier kommen.
    if (!filterWarAktiv) await _load();
  }

  Widget _buildInlineCodeSearch() {
    final result = _codeSearchResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: TextField(
            controller: _codeSearchController,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Community suchen, nach Name oder Code',
              hintStyle: const TextStyle(color: Colors.grey),
              counterText: '',
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: _codeSearchLoading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.login, color: Colors.white70),
                      onPressed: _codeSearchController.text.trim().isEmpty
                          ? null
                          : () {
                              _joinCommunityWithCode(
                                _codeSearchController.text,
                              );
                            },
                    ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onChanged: _sucheGeaendert,
            onSubmitted: (value) {
              _joinCommunityWithCode(value);
            },
          ),
        ),
        if (result != null) ...[
          const SizedBox(height: 10),
          _buildCommunityCard(
            result,
            joined: false,
            // 2026-08-24: auch der Treffer der Code-Suche fuehrt jetzt in die
            // Vorschau statt direkt in den Beitritt. Ein Code kann von
            // jemand anderem in die Zwischenablage geraten sein, und bei
            // einer privaten Community loest der Knopf ohnehin nur eine
            // Anfrage aus. Der Nutzer soll vorher sehen, wo er landet.
            onTap: () => _kachelGetippt(
              result,
              istMitglied: false,
              inviteCode:
                  result['invite_code']?.toString() ??
                  _codeSearchController.text,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _showCreateCommunitySheet,
            icon: const Icon(Icons.add, color: Colors.white, size: 18),
            label: const Text('Erstellen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppAccentColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _showJoinCodeSheet,
            icon: const Icon(Icons.key, color: Colors.white, size: 18),
            label: const Text('Code'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF151821),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: const TextStyle(color: Colors.grey, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityCard(
    Map<String, dynamic> community, {
    required bool joined,
    required VoidCallback onTap,
  }) {
    final owner = CommunityChatService.ownerProfile(community);
    final ownerName = CommunityChatService.displayName(
      owner,
      fallbackUserId: community['owner_id'] as String?,
    );
    final memberCount = CommunityChatService.memberCount(community);
    final isPublic = community['is_public'] == true;
    final description = (community['description'] as String?)?.trim();
    final role = CommunityChatService.currentUserRole(community);
    final istNeu = CommunityChatService.istVorKurzemErstellt(community);
    final angepinnt = CommunityChatService.istAngepinnt(community);
    // 2026-08-24 (Aufgabe 2/3): Fahrzeugart und Region an der Kachel.
    // „Alle" bekommt bewusst KEIN Etikett — es ist der Standardwert der
    // Spalte, es steht also an JEDER der sechs Bestands-Communities, und ein
    // Etikett, das überall klebt, unterscheidet nichts.
    final fahrzeugartText = CommunityChatService.fahrzeugartVon(
      community,
    ).kachelText;
    final regionText = CommunityChatService.regionName(community);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 2026-08-23 (Auftrag Vucko „Profilbilder fuer Communities"):
                // dritte Anzeigestelle. Diese Kachel wird an drei Orten
                // gerendert (Meine Communities, Entdecken, Treffer der
                // Code-Suche), deshalb reicht hier eine Aenderung fuer alle
                // drei. Ohne Bild bleibt genau der bisherige Platzhalter.
                // 2026-08-24 (Aufgabe 1.1, Ebene 3): Der Punkt sitzt am Bild,
                // wie in jedem Messenger. Nur bei Communities, in denen man
                // Mitglied ist — bei einer fremden Community aus der
                // Entdecken-Liste gibt es keinen Lesestand und damit auch
                // nichts „Neues fuer dich".
                if (joined)
                  _mitHinweispunkt(
                    community['id']?.toString(),
                    CommunityAvatar.fromCommunity(community, size: 42),
                  )
                else
                  CommunityAvatar.fromCommunity(community, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        community['name']?.toString() ?? 'Community',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // 2026-08-24 (Aufgabe 1.2, Vucko: „wenn eine Community
                      // jünger als sieben Tage ist, dass da drunter dann
                      // ‚neu' steht oder halt ‚vor kurzem erstellt'").
                      // Vuckos Entscheidung, bindend: der Text lautet
                      // „Vor kurzem erstellt".
                      //
                      // Der Platz UNTER dem Namen ist genau diese Zeile,
                      // deshalb steht das Etikett neben @ownerName statt in
                      // einer eigenen Zeile: eine zusätzliche Zeile würde
                      // jede Kachel höher machen, auch die 4 von 6, die das
                      // Etikett heute gar nicht tragen.
                      //
                      // Diese Kachel rendert ALLE DREI Anzeigestellen
                      // (Meine Communities, Öffentliche Communities, Treffer
                      // der Code-Suche), eine Änderung deckt also alle ab.
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '@$ownerName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (istNeu) ...[
                            const SizedBox(width: 6),
                            _buildNeuLabel(),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // 2026-08-24 (Aufgabe 1): die Nadel. Sie ist die Rückmeldung
                // auf den Menüeintrag und sitzt links neben der
                // Sichtbarkeits-Plakette, also dort, wo das Auge nach dem
                // Namen ohnehin hinwandert.
                if (angepinnt) ...[
                  Icon(
                    Icons.push_pin,
                    size: 15,
                    color: AppAccentColors.accent,
                  ),
                  const SizedBox(width: 6),
                ],
                _buildVisibilityPill(isPublic),
                if (joined) ...[
                  const SizedBox(width: 4),
                  _buildCommunityMenu(community, role),
                ],
              ],
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
            if (fahrzeugartText != null || regionText != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (fahrzeugartText != null)
                    _buildMerkmal(
                      CommunityChatService.fahrzeugartVon(community) ==
                              CommunityFahrzeugart.motorrad
                          ? Icons.two_wheeler
                          : Icons.directions_car_filled,
                      fahrzeugartText,
                    ),
                  if (regionText != null)
                    _buildMerkmal(Icons.place_outlined, regionText),
                ],
              ),
            ],
            const SizedBox(height: 13),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _showMembers(community),
                  icon: Icon(
                    Icons.people_outline,
                    color: Colors.grey[500],
                    size: 16,
                  ),
                  label: Text('$memberCount Mitglieder'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey,
                    textStyle: const TextStyle(fontSize: 12),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const Spacer(),
                // 2026-08-24: Der Knopf hiess bei einer fremden Community
                // „Beitreten" und trat auch sofort bei. Jetzt heisst er
                // „Ansehen" und fuehrt in dieselbe Vorschau wie ein Tipp auf
                // die Kachel. Der Knopf „Beitreten" existiert weiterhin, aber
                // nur noch EINMAL und nur dort, wo man vorher gesehen hat,
                // um welche Community es geht: unten im Vorschau-Blatt.
                TextButton.icon(
                  onPressed: onTap,
                  icon: Icon(
                    joined
                        ? Icons.chat_bubble_outline
                        : Icons.visibility_outlined,
                    color: AppAccentColors.accent,
                    size: 16,
                  ),
                  label: Text(joined ? 'Chat' : 'Ansehen'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppAccentColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 2026-08-24 (Aufgabe 1.1, Ebene 3): legt den Hinweispunkt auf das
  /// Community-Bild.
  ///
  /// Die Zahl steht bewusst NICHT im Punkt. Vucko hat einen Punkt bestellt
  /// („so ein kleiner Punkt … wie in den ganzen Apps halt eine
  /// Benachrichtigung aussieht"), keine Zählerei. Die Anzahl liefert die RPC
  /// zwar mit, aber sie in einen 10-dp-Kreis zu quetschen macht die Kachel
  /// unruhig, ohne dass jemand etwas davon hat.
  Widget _mitHinweispunkt(String? communityId, Widget kind) {
    if (communityId == null) return kind;
    return ValueListenableBuilder<CommunityHinweisStand>(
      valueListenable: CommunityNeuigkeitService.instance.stand,
      builder: (context, stand, bild) {
        if (!stand.fuerCommunity(communityId).neu) return bild!;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            bild!,
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppAccentColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF1C1F26), width: 2),
                ),
              ),
            ),
          ],
        );
      },
      child: kind,
    );
  }

  /// 2026-08-24 (Aufgabe 1.2): das Etikett selbst.
  ///
  /// Bewusst NICHT in der Akzentfarbe: der Akzent gehört in dieser Kachel
  /// dem Knopf „Chat"/„Beitreten". Ein zweites akzentfarbenes Element daneben
  /// würde mit ihm konkurrieren. Das Etikett sagt nur „diese Community
  /// existiert erst seit Kurzem" und ist bewusst ruhig.
  Widget _buildNeuLabel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: const Text(
        'Vor kurzem erstellt',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// Ein ruhiges Etikett für Fahrzeugart und Region. Bewusst dieselbe
  /// Zurückhaltung wie [_buildNeuLabel]: der Akzent gehört in dieser Kachel
  /// dem Knopf „Chat"/„Ansehen" und der Nadel.
  Widget _buildMerkmal(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey[500]),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityMenu(Map<String, dynamic> community, String? role) {
    final isAdmin = role == 'owner';
    final angepinnt = CommunityChatService.istAngepinnt(community);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz, color: Colors.white70),
      color: const Color(0xFF1C1F26),
      onSelected: (value) {
        if (value == 'pin') {
          _pinUmschalten(community);
        } else if (value == 'teilen') {
          _teilen(community);
        } else if (value == 'members') {
          _showMembers(community);
        } else if (value == 'leave') {
          _confirmLeaveCommunity(community);
        } else if (value == 'delete') {
          _confirmDeleteCommunity(community);
        } else if (value == 'settings') {
          _openSettings(community);
        }
      },
      itemBuilder: (_) => [
        // 2026-08-24 (Auftrag Vucko, Aufgabe 1): „man soll auch communitys
        // anpinnen koennen". Der Eintrag steht GANZ OBEN, weil er der
        // einzige im Menue ist, den man oefter als einmal benutzt.
        PopupMenuItem(
          value: 'pin',
          child: Row(
            children: [
              Icon(
                angepinnt
                    ? Icons.push_pin_outlined
                    : Icons.push_pin,
                color: angepinnt ? Colors.white70 : AppAccentColors.accent,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                angepinnt ? 'Nicht mehr anpinnen' : 'Anpinnen',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        // 2026-08-31 (Auftrag Vucko „Communities teilen"): direkt unter
        // Anpinnen. Die Liste ist die Stelle, an der man an seine eigenen
        // Communities denkt; den Weg ueber Chat oeffnen und dann das Menue
        // dort wuerde kaum jemand gehen.
        const PopupMenuItem(
          value: 'teilen',
          child: Row(
            children: [
              Icon(Icons.ios_share, color: Colors.white70, size: 18),
              SizedBox(width: 10),
              Text('Teilen', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // 2026-08-23 (Auftrag Vucko): zweiter Zugang zu den Einstellungen.
        // Vorher gab es hier nur Mitglieder, Verlassen und Loeschen, und
        // Schreibmodus und Sichtbarkeit lagen versteckt im Menue INNERHALB
        // des Chats. Genau deshalb hat Vucko sie nicht gefunden.
        if (isAdmin)
          const PopupMenuItem(
            value: 'settings',
            child: Row(
              children: [
                Icon(Icons.settings_outlined, color: Colors.white70, size: 18),
                SizedBox(width: 10),
                Text('Einstellungen', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'members',
          child: Row(
            children: [
              Icon(Icons.people_outline, color: Colors.white70, size: 18),
              SizedBox(width: 10),
              Text('Mitglieder', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'leave',
          child: Row(
            children: [
              Icon(Icons.logout, color: Colors.redAccent, size: 18),
              SizedBox(width: 10),
              Text('Verlassen', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
        if (isAdmin) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
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
    );
  }

  Widget _buildVisibilityPill(bool isPublic) {
    final color = isPublic ? Colors.greenAccent : Colors.orangeAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        isPublic ? 'Öffentlich' : 'Privat',
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showCreateCommunitySheet() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var isPublic = false;
    var ownerOnlyMessages = false;
    var saving = false;
    // 2026-08-24 (Auftrag Vucko, Aufgabe 3): „obs fuer autofahrer
    // motorradfahrer in welcher region".
    //
    // VORGABEN, begründet: „Für alle" und „Keine Angabe". Beides ist genau
    // das, was die Datenbank ohnehin setzt (`fahrzeugart` default `both`,
    // `region_code` NULL), und beides heisst „fällt aus keinem Filter
    // heraus". Ein Pflichtfeld wäre hier eine Hürde vor dem eigentlichen
    // Zweck — und eine erzwungene Wahl liefert falsche Angaben, weil jemand
    // irgendetwas antippt, um weiterzukommen. Ändern kann der Admin es
    // später in den Einstellungen.
    var fahrzeugart = CommunityFahrzeugart.alle;
    String? regionCode;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> create() async {
              if (saving) return;
              setSheetState(() => saving = true);
              try {
                final id = await CommunityChatService.createCommunity(
                  name: nameCtrl.text,
                  description: descCtrl.text,
                  isPublic: isPublic,
                  ownerOnlyMessages: ownerOnlyMessages,
                  fahrzeugart: fahrzeugart,
                  regionCode: regionCode,
                );
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                if (!mounted) return;
                await _openCommunity(id);
              } catch (e) {
                _showError(e);
              } finally {
                if (sheetContext.mounted) {
                  setSheetState(() => saving = false);
                }
              }
            }

            // 2026-08-24: scrollbar. Das Blatt hat mit Fahrzeugart und Region
            // zwei Blöcke mehr; auf einem kleinen Gerät mit offener Tastatur
            // liefe es sonst über.
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                18,
                18,
                18,
                MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Community erstellen',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSheetTextField(
                    controller: nameCtrl,
                    label: 'Name',
                    maxLength: AppInputLimits.communityNameMaxLength,
                  ),
                  const SizedBox(height: 10),
                  _buildSheetTextField(
                    controller: descCtrl,
                    label: 'Beschreibung',
                    maxLength: AppInputLimits.communityDescriptionMaxLength,
                    minLines: 2,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _buildVisibilityOption(
                          selected: isPublic,
                          icon: Icons.public,
                          title: 'Öffentlich',
                          onTap: () => setSheetState(() => isPublic = true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildVisibilityOption(
                          selected: !isPublic,
                          icon: Icons.lock_outline,
                          title: 'Privat',
                          onTap: () => setSheetState(() => isPublic = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildFeldUeberschrift('Für wen ist die Community?'),
                  const SizedBox(height: 8),
                  CommunityFahrzeugartChips(
                    gewaehlt: fahrzeugart,
                    alleBeschriftung: 'Für alle',
                    onWahl: (wahl) => setSheetState(() => fahrzeugart = wahl),
                  ),
                  const SizedBox(height: 16),
                  _buildFeldUeberschrift('Region (freiwillig)'),
                  const SizedBox(height: 8),
                  _buildRegionZeile(
                    regionCode: regionCode,
                    onWahl: (code) => setSheetState(() => regionCode = code),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => setSheetState(
                      () => ownerOnlyMessages = !ownerOnlyMessages,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F121A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: ownerOnlyMessages
                              ? AppAccentColors.accent
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            ownerOnlyMessages
                                ? Icons.admin_panel_settings
                                : Icons.chat_bubble_outline,
                            color: ownerOnlyMessages
                                ? AppAccentColors.accent
                                : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Nur Owner darf schreiben',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: ownerOnlyMessages,
                            activeThumbColor: AppAccentColors.accent,
                            activeTrackColor: AppAccentColors.accent.withValues(
                              alpha: 0.35,
                            ),
                            onChanged: (value) =>
                                setSheetState(() => ownerOnlyMessages = value),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: saving ? null : create,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppAccentColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Erstellen',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      nameCtrl.dispose();
      descCtrl.dispose();
    });
  }

  void _showJoinCodeSheet() {
    final codeCtrl = TextEditingController();
    var saving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> join() async {
              if (saving) return;
              setSheetState(() => saving = true);
              try {
                final result = await CommunityChatService.joinCommunityByCode(
                  codeCtrl.text,
                );
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                if (!mounted) return;
                _showMessage(result.userMessage);
                if (result.opensCommunity && result.communityId.isNotEmpty) {
                  await _openCommunity(result.communityId);
                }
              } catch (e) {
                _showError(e);
              } finally {
                if (sheetContext.mounted) {
                  setSheetState(() => saving = false);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                18,
                18,
                MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mit Code beitreten',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSheetTextField(
                    controller: codeCtrl,
                    label: 'CCC-ABC123',
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : join,
                      icon: saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.login, color: Colors.white),
                      label: const Text('Beitreten'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppAccentColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(codeCtrl.dispose);
  }

  Widget _buildSheetTextField({
    required TextEditingController controller,
    required String label,
    int? maxLength,
    int minLines = 1,
    int maxLines = 1,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
  }) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      minLines: minLines,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        counterStyle: const TextStyle(color: Colors.grey),
        labelStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF0F121A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppAccentColors.accent),
        ),
      ),
    );
  }

  /// Eine kleine Überschrift über einem Wahlblock im Erstellen-Blatt.
  Widget _buildFeldUeberschrift(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.grey,
        fontSize: 11.5,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.4,
      ),
    );
  }

  /// Die Regionszeile im Erstellen-Blatt.
  ///
  /// „Keine Angabe" ist die Vorgabe und steht ausdrücklich als Text da, damit
  /// niemand denkt, er hätte etwas vergessen. Der Satz darunter sagt, was das
  /// bedeutet — sonst ist „keine Region" eine Leerstelle statt einer
  /// Entscheidung.
  Widget _buildRegionZeile({
    required String? regionCode,
    required ValueChanged<String?> onWahl,
  }) {
    String text = 'Keine Angabe (überregional)';
    for (final region in _regionen) {
      if (region.code == regionCode) text = region.name;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final wahl = await CommunityRegionBlatt.zeigen(
              context,
              regionen: _regionen,
              aktuell: regionCode,
              titel: 'Region der Community',
              alleBeschriftung: 'Keine Angabe (überregional)',
              // 2026-08-25: dieselbe Beschneidung wie im Filter. Wer in
              // Deutschland eine Community anlegt, soll nicht erst durch neun
              // österreichische Bundesländer und 26 Kantone scrollen.
              landCode: _standortLand.landCode,
              landQuelle: _standortLand.quelle,
            );
            if (wahl != null) onWahl(wahl.code);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFF0F121A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: regionCode == null
                    ? Colors.white.withValues(alpha: 0.08)
                    : AppAccentColors.accent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: regionCode == null
                      ? Colors.grey
                      : AppAccentColors.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: regionCode == null ? Colors.grey : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Icon(Icons.expand_more, color: Colors.grey, size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ohne Angabe erscheint deine Community in jedem Regionsfilter.',
          style: TextStyle(color: Colors.grey, fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _buildVisibilityOption({
    required bool selected,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppAccentColors.accent.withValues(alpha: 0.18)
              : const Color(0xFF0F121A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppAccentColors.accent
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? AppAccentColors.accent : Colors.grey,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
