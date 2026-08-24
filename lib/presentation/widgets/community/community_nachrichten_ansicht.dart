import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/presentation/widgets/mentions.dart';
import 'package:cruise_connect/presentation/widgets/social/route_attachment_card.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

/// Erwaehnungen, die im Community-Chat als reiner Text stehen bleiben (keine
/// Personen, sondern Themen). Beide Darstellungen benutzen dieselbe Liste.
const communityChatThemenErwaehnungen = {
  'gruppe',
  'gruppen',
  'gruppenfahrt',
  'gruppenfahrten',
  'gruppenfahert',
  'geteilteroute',
};

/// Der Satz, der an der Stelle einer fuer alle geloeschten Nachricht steht.
///
/// 2026-08-24 (Auftrag Vucko): „Zeig an, dass eine Nachricht geloescht wurde,
/// statt sie spurlos verschwinden zu lassen." Der TEXT der Nachricht ist dabei
/// nicht auf dem Geraet — er wird gar nicht erst geholt (siehe
/// `CommunityChatService.fetchMessages`).
const String communityGeloeschtText = 'Diese Nachricht wurde gelöscht.';

/// Eine graue Zeile mitten im Chat: wer kam, wer ging.
///
/// Vucko: „man soll sehen wer dazu gekommen ist und wer aus der community
/// gegangen ist danach". Damit das den Chat nicht dominiert, fasst
/// [CommunityChatTimeline] aufeinanderfolgende Ereignisse zusammen und diese
/// Zeile zeigt hoechstens drei Namen. Ein Tipp klappt die vollstaendige Liste
/// auf — das ist die Antwort auf „was, wenn an einem Tag zehn Leute
/// beitreten": eine Zeile, nicht zehn.
class CommunitySystemZeile extends StatefulWidget {
  const CommunitySystemZeile({super.key, required this.eintraege});

  final List<Map<String, dynamic>> eintraege;

  @override
  State<CommunitySystemZeile> createState() => _CommunitySystemZeileState();
}

class _CommunitySystemZeileState extends State<CommunitySystemZeile> {
  bool _offen = false;

  String _name(Map<String, dynamic> eintrag) {
    final profil = eintrag['profiles'];
    return CommunityChatService.displayName(
      profil is Map ? Map<String, dynamic>.from(profil) : null,
      fallbackUserId: eintrag['user_id']?.toString(),
    );
  }

  String _zeit(Object? roh) {
    final dt = DateTime.tryParse(roh?.toString() ?? '')?.toLocal();
    if (dt == null) return '';
    final t = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$t.$m. $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final art = widget.eintraege.first['art']?.toString();
    final icon = switch (art) {
      'austritt' => Icons.logout_rounded,
      'entfernt' => Icons.person_remove_alt_1_outlined,
      _ => Icons.person_add_alt_1_outlined,
    };
    final aufklappbar = widget.eintraege.length > 1;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: aufklappbar ? () => setState(() => _offen = !_offen) : null,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 13, color: Colors.white38),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        CommunityChatTimeline.verlaufText(widget.eintraege),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ),
                    if (aufklappbar) ...[
                      const SizedBox(width: 6),
                      Icon(
                        _offen
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 15,
                        color: Colors.white38,
                      ),
                    ],
                  ],
                ),
                if (_offen) ...[
                  const SizedBox(height: 6),
                  for (final eintrag in widget.eintraege)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${_name(eintrag)} · ${_zeit(eintrag['am'])}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Die Messenger-Ansicht: Sprechblasen links und rechts, eng, chronologisch.
///
/// 2026-08-24 (Auftrag Vucko): „ob man den standart chat oder einen
/// Nachrichten Chat bevorzugt".
///
/// SIE ZEIGT DIESELBEN INHALTE wie die Beitragsansicht: Antworten (als Zitat
/// ueber der Blase), Routen-Anhaenge, Reaktionen, angeheftete Nachrichten (als
/// Band ueber der Liste, wie man es aus Messengern kennt) und die Systemzeilen
/// mit den Zu- und Abgaengen.
///
/// WAS SIE BEWUSST NICHT ZEIGT: die Themenzeile „r/Gruppenfahrten" ueber jedem
/// Beitrag. In einer Sprechblase waere sie eine Zeile Text ueber zwei Woertern
/// Inhalt. Dasselbe Thema laesst sich weiterhin ueber die Filterleiste ueber
/// dem Chat auswaehlen, die in beiden Darstellungen dieselbe ist.
class CommunityNachrichtenAnsicht extends StatelessWidget {
  const CommunityNachrichtenAnsicht({
    super.key,
    required this.zeilen,
    required this.scrollController,
    required this.messageKeys,
    required this.eigeneUserId,
    required this.onAktionen,
    required this.onAntworten,
    required this.onZuNachricht,
    required this.reaktionenBauer,
    required this.zitatTextFuer,
    required this.antwortenZahlFuer,
  });

  final List<ChatZeile> zeilen;
  final ScrollController scrollController;
  final Map<String, GlobalKey> messageKeys;
  final String? eigeneUserId;
  final void Function(Map<String, dynamic> nachricht) onAktionen;
  final void Function(Map<String, dynamic> nachricht) onAntworten;
  final void Function(String? nachrichtId) onZuNachricht;
  final Widget Function(Map<String, dynamic> nachricht) reaktionenBauer;
  final String Function(String? nachrichtId) zitatTextFuer;
  final int Function(String? nachrichtId) antwortenZahlFuer;

  static const List<String> _monate = [
    'Jan.',
    'Feb.',
    'März',
    'Apr.',
    'Mai',
    'Juni',
    'Juli',
    'Aug.',
    'Sep.',
    'Okt.',
    'Nov.',
    'Dez.',
  ];

  String _uhrzeit(Object? roh) {
    final dt = DateTime.tryParse(roh?.toString() ?? '')?.toLocal();
    if (dt == null) return '';
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  DateTime? _tag(ChatZeile zeile) {
    final lokal = zeile.zeit.toLocal();
    return DateTime(lokal.year, lokal.month, lokal.day);
  }

  String _tagesTitel(DateTime tag) {
    final heute = DateTime.now();
    final heuteTag = DateTime(heute.year, heute.month, heute.day);
    final unterschied = heuteTag.difference(tag).inDays;
    if (unterschied == 0) return 'Heute';
    if (unterschied == 1) return 'Gestern';
    return '${tag.day}. ${_monate[tag.month - 1]} ${tag.year}';
  }

  @override
  Widget build(BuildContext context) {
    final angepinnte = zeilen
        .where((z) => z.art != ChatZeileArt.verlauf && z.angepinnt)
        .toList();

    return Column(
      children: [
        if (angepinnte.isNotEmpty) _pinBand(angepinnte),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
            itemCount: zeilen.length,
            itemBuilder: (context, index) {
              final zeile = zeilen[index];
              final vorher = index == 0 ? null : zeilen[index - 1];
              final neuerTag =
                  vorher == null || _tag(vorher) != _tag(zeile);

              final inhalt = switch (zeile.art) {
                ChatZeileArt.verlauf => CommunitySystemZeile(
                  eintraege: zeile.verlauf,
                ),
                _ => _blase(
                  context,
                  zeile,
                  zeigeKopf: neuerTag || !_selbeQuelle(vorher, zeile),
                ),
              };

              final id = zeile.id;
              final key = id == null
                  ? null
                  : messageKeys.putIfAbsent(id, GlobalKey.new);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (neuerTag) _tagesTrenner(_tag(zeile)!),
                  KeyedSubtree(key: key, child: inhalt),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Zwei aufeinanderfolgende Blasen derselben Person werden enger gesetzt und
  /// bekommen nur einmal Name und Bild — genau wie in jedem Messenger.
  bool _selbeQuelle(ChatZeile? vorher, ChatZeile jetzt) {
    if (vorher == null || vorher.art == ChatZeileArt.verlauf) return false;
    return vorher.nachricht?['user_id'] == jetzt.nachricht?['user_id'];
  }

  Widget _tagesTrenner(DateTime tag) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _tagesTitel(tag),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  /// Das Band mit der angehefteten Nachricht ueber der Liste.
  ///
  /// In der Beitragsansicht stehen angeheftete Beitraege ganz oben in der
  /// Liste. In einem Messenger waere das falsch: dort ist die Reihenfolge die
  /// Zeit, und eine Nachricht von gestern zwischen zwei von heute wirkt wie
  /// ein Fehler. Deshalb hier das Band — ein Tipp springt zur Nachricht an
  /// ihrer echten Stelle.
  Widget _pinBand(List<ChatZeile> angepinnte) {
    final neueste = angepinnte.last;
    final nachricht = neueste.nachricht ?? const <String, dynamic>{};
    final text = nachricht['_geloescht'] == true
        ? communityGeloeschtText
        : (nachricht['body']?.toString() ?? '');
    return Material(
      color: const Color(0xFF141924),
      child: InkWell(
        onTap: () => onZuNachricht(nachricht['id']?.toString()),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              left: BorderSide(color: AppAccentColors.accent, width: 3),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.push_pin, size: 14, color: AppAccentColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      angepinnte.length == 1
                          ? 'Angepinnt'
                          : 'Angepinnt (${angepinnte.length})',
                      style: TextStyle(
                        color: AppAccentColors.accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      text.isEmpty ? 'Beitrag ansehen' : text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
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

  Widget _blase(
    BuildContext context,
    ChatZeile zeile, {
    required bool zeigeKopf,
  }) {
    final nachricht = zeile.nachricht ?? const <String, dynamic>{};
    final istGeloescht = zeile.art == ChatZeileArt.geloescht;
    final istEigene = nachricht['user_id'] == eigeneUserId;
    final rohProfil = nachricht['profiles'];
    final profil = rohProfil is Map
        ? Map<String, dynamic>.from(rohProfil)
        : <String, dynamic>{};
    final name = CommunityChatService.displayName(
      profil,
      fallbackUserId: nachricht['user_id']?.toString(),
    );
    final body = nachricht['body']?.toString() ?? '';
    final istUnterwegs = nachricht['_pending'] == true;
    final bearbeitet = nachricht['bearbeitet_am'] != null;
    final antwortAuf = nachricht['reply_to_message_id']?.toString();
    final rohAnhang = nachricht['route_attachment'];
    final anhang = rohAnhang is Map
        ? Map<String, dynamic>.from(rohAnhang)
        : null;
    final nachrichtId = nachricht['id']?.toString();
    final antworten = antwortenZahlFuer(nachrichtId);

    final blase = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 7),
      decoration: BoxDecoration(
        color: istGeloescht
            ? Colors.white.withValues(alpha: 0.04)
            : istEigene
            ? AppAccentColors.accent.withValues(alpha: 0.20)
            : const Color(0xFF1C1F26),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(istEigene ? 16 : 5),
          bottomRight: Radius.circular(istEigene ? 5 : 16),
        ),
        border: Border.all(
          color: zeile.angepinnt
              ? AppAccentColors.accent.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (zeigeKopf && !istEigene)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                name,
                style: TextStyle(
                  color: AppAccentColors.accent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          if (antwortAuf != null && antwortAuf.isNotEmpty && !istGeloescht) ...[
            InkWell(
              onTap: () => onZuNachricht(antwortAuf),
              borderRadius: BorderRadius.circular(7),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(7),
                  border: Border(
                    left: BorderSide(
                      color: AppAccentColors.accent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Text(
                  zitatTextFuer(antwortAuf),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
          if (istGeloescht)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.block_rounded,
                  size: 13,
                  color: Colors.white38,
                ),
                const SizedBox(width: 6),
                Text(
                  communityGeloeschtText,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            )
          else if (body.isNotEmpty)
            Text.rich(
              TextSpan(
                children: buildMentionSpans(
                  context: context,
                  text: body,
                  baseStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    height: 1.32,
                    fontWeight: FontWeight.w600,
                  ),
                  plainMentions: communityChatThemenErwaehnungen,
                ),
              ),
            ),
          if (anhang != null && anhang['route_id'] != null) ...[
            const SizedBox(height: 8),
            RouteAttachmentCard(
              routeId: anhang['route_id'].toString(),
              compact: true,
              showRideButton: true,
              fallbackTitle: anhang['title']?.toString(),
              fallbackStyle: anhang['style']?.toString(),
              fallbackDistanceKm: (anhang['distance_km'] as num?)?.toDouble(),
              fallbackDurationSeconds: (anhang['duration_seconds'] as num?)
                  ?.toDouble(),
            ),
          ],
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (antworten > 0 && !istGeloescht) ...[
                GestureDetector(
                  onTap: () => onAntworten(nachricht),
                  child: Text(
                    antworten == 1 ? '1 Antwort' : '$antworten Antworten',
                    style: TextStyle(
                      color: AppAccentColors.accent.withValues(alpha: 0.85),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (zeile.angepinnt) ...[
                Icon(Icons.push_pin, size: 11, color: AppAccentColors.accent),
                const SizedBox(width: 5),
              ],
              if (bearbeitet && !istGeloescht) ...[
                const Text(
                  'bearbeitet',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                istUnterwegs
                    ? 'sendet...'
                    : _uhrzeit(nachricht['created_at']),
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (!istGeloescht) reaktionenBauer(nachricht),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: zeigeKopf ? 8 : 2),
      child: Row(
        mainAxisAlignment: istEigene
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!istEigene)
            SizedBox(
              width: 30,
              child: zeigeKopf
                  ? UserAvatar.fromProfile(
                      profil,
                      fallbackName: name,
                      radius: 12,
                    )
                  : null,
            ),
          if (!istEigene) const SizedBox(width: 6),
          Flexible(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () => onAktionen(nachricht),
              onTap: istGeloescht ? () => onAktionen(nachricht) : null,
              child: blase,
            ),
          ),
        ],
      ),
    );
  }
}
