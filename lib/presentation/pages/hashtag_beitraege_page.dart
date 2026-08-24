import 'dart:math';

import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/hashtag_personen_page.dart';
import 'package:cruise_connect/presentation/pages/post_detail_page.dart';
import 'package:cruise_connect/presentation/pages/user_profile_page.dart';
import 'package:cruise_connect/presentation/widgets/mentions.dart';
import 'package:cruise_connect/presentation/widgets/skeletons/post_skeleton.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

/// 2026-08-24 — Aufgabe 1.3 aus dem Auftrag vom 23.08.
///
/// Vucko, Aufnahme 3: „dass man unter Hashtags Sachen suchen kann" und „für
/// zukünftige Gewinnspiele wäre das auch ganz cool, dass man da Sachen
/// auslosen kann".
///
/// ENTSCHEIDUNG (Vucko schläft, deshalb begründet und hier festgehalten):
/// Diese Seite ist eine EIGENE Datei und nicht die Ergebnisliste innerhalb
/// von `community_page.dart`.
///
/// Der Auftrag schlug vor, die Treffer mit `_buildPostItem` aus
/// `community_page.dart` zu rendern. Das geht nicht, ohne dieselbe Liste
/// zweimal zu bauen: `_buildPostItem` ist eine private Methode von
/// `_CommunityPageState` und hängt an dessen Provider und Navigation. Ein
/// Hashtag ist aber an SECHS Anzeigestellen anklickbar (Feed, Entdecken,
/// Beitrags-Detail, zwei Profil-Seiten, gemerkte Beiträge, Community-Chat) —
/// die meisten davon liegen ausserhalb der Community-Seite. Ein Tipp dort
/// müsste sonst erst die Community-Seite aufbauen.
///
/// Deshalb: EINE Liste, von überall erreichbar. Die Karte ist bewusst
/// derselbe Aufbau wie im Feed (Bild, Name, Handle, Zeit, Text mit
/// anklickbaren Erwähnungen und Hashtags) und führt beim Antippen in
/// dieselbe [PostDetailPage] wie der Feed. Was hier fehlt, sind Herz und
/// Kommentarzähler — die liegen im Detail, und in einer Trefferliste zu einem
/// Hashtag will man zuerst sehen, WER teilgenommen hat.
///
/// Nachzuholen, siehe „offen": Nachladen beim Scrollen. Heute holt die Seite
/// bis zu 200 Beiträge auf einmal; bei 10 Beiträgen in der ganzen Datenbank
/// (gemessen am 24.08.) ist das mit Abstand ausreichend.
class HashtagBeitraegePage extends StatefulWidget {
  const HashtagBeitraegePage({
    super.key,
    required this.tag,
    this.beitraegeLader,
    this.kennzahlenLader,
    this.personenLader,
  });

  /// Mit oder ohne Raute, beides ist erlaubt.
  final String tag;

  /// 2026-08-24: die drei Abfragen sind austauschbar, damit ein Widget-Test
  /// die Seite mit erfundenen Daten pruefen kann. In der Datenbank stehen am
  /// 24.08. NULL Beitraege mit einer Raute — ohne diese Naht waere die
  /// Personenzahl an echten Daten nicht pruefbar, und ungeprueft geht sie
  /// genau dann kaputt, wenn Vucko sie zum ersten Mal braucht.
  ///
  /// `null` als Ergebnis heisst FEHLER, `[]` heisst KEIN TREFFER.
  final Future<List<Map<String, dynamic>>?> Function(
    String tag, {
    int limit,
    int offset,
  })?
  beitraegeLader;

  final Future<HashtagKennzahlen?> Function(String tag)? kennzahlenLader;

  final Future<List<Map<String, dynamic>>?> Function(
    String tag, {
    int limit,
    int offset,
  })?
  personenLader;

  /// Öffnet die Seite. Einziger Einstieg, damit die Normalisierung an genau
  /// einer Stelle passiert.
  static Future<void> oeffnen(BuildContext context, String tag) {
    final sauber = SocialService.normalisiereHashtagEingabe(tag);
    if (sauber.isEmpty) return Future<void>.value();
    return Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => HashtagBeitraegePage(tag: sauber),
      ),
    );
  }

  @override
  State<HashtagBeitraegePage> createState() => _HashtagBeitraegePageState();
}

class _HashtagBeitraegePageState extends State<HashtagBeitraegePage> {
  bool _laedt = true;
  bool _fehler = false;
  List<Map<String, dynamic>> _beitraege = const [];

  /// 2026-08-24 (Auftrag Vucko vom 24.08.: „wenn ihn schon 17 Leute benutzt
  /// haben, dann soll das moeglichst da noch drunter stehen"). `null`
  /// heisst: die Kopfzahlen kamen nicht an, gerechnet wird aus der Liste.
  HashtagKennzahlen? _kennzahlen;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() => _fehler = false);
    // Beide Abfragen gleichzeitig. Nacheinander waeren es zwei Wartezeiten
    // fuer eine Seite, die aus einer Zeile Text und einer Liste besteht.
    final ergebnisse = await Future.wait<Object?>([
      (widget.beitraegeLader ?? SocialService.hashtagBeitraegeErgebnis)(
        widget.tag,
        limit: 200,
      ),
      (widget.kennzahlenLader ?? SocialService.hashtagKennzahlen)(widget.tag),
    ]);
    if (!mounted) return;
    final treffer = ergebnisse[0] as List<Map<String, dynamic>>?;
    setState(() {
      _laedt = false;
      _fehler = treffer == null;
      _beitraege = treffer ?? const [];
      _kennzahlen = ergebnisse[1] as HashtagKennzahlen?;
    });
  }

  /// Die zwei Zahlen ueber der Liste.
  ///
  /// Aus der Datenbank, aber NIE kleiner als das, was nachweislich auf dem
  /// Bildschirm steht. Beides kann zu klein sein: die Liste ist bei 200
  /// gedeckelt, und die Kopfzahl-Abfrage koennte fehlen oder ihre Spalten
  /// anders nennen. Das Groessere von beidem ist in jedem dieser Faelle die
  /// richtige Antwort — und vor allem kann nie „5 Beitraege" ueber sieben
  /// sichtbaren Karten stehen.
  HashtagKennzahlen get _zahlen {
    final ausDerListe = HashtagKennzahlen(
      beitraege: _beitraege.length,
      personen: SocialService.personenAusBeitraegen(_beitraege).length,
    );
    final ausDerDatenbank = _kennzahlen;
    if (ausDerDatenbank == null) return ausDerListe;
    return HashtagKennzahlen(
      beitraege: max(ausDerDatenbank.beitraege, ausDerListe.beitraege),
      personen: max(ausDerDatenbank.personen, ausDerListe.personen),
    );
  }

  /// Lader fuer das Personen-Blatt, mit Notbehelf.
  ///
  /// Erst die Abfrage. Kommt sie nicht (Migration noch nicht da, kein Netz),
  /// werden die Personen aus den Beitraegen gerechnet, die diese Seite
  /// ohnehin schon geladen hat. Dann steht dort eine Liste statt einer
  /// Fehlermeldung — und sie stimmt, solange nicht mehr als 200 Beitraege
  /// zu dem Hashtag existieren.
  Future<List<Map<String, dynamic>>?> _personen(
    String tag, {
    int limit = 50,
    int offset = 0,
  }) async {
    final lader = widget.personenLader ?? SocialService.hashtagPersonen;
    final ausDerDatenbank = await lader(tag, limit: limit, offset: offset);
    if (ausDerDatenbank != null) return ausDerDatenbank;
    if (_fehler) return null; // Wir haben auch keine Beitraege: ehrlich sein.
    final alle = SocialService.personenAusBeitraegen(_beitraege);
    if (offset >= alle.length) return const [];
    return alle.sublist(offset, min(offset + limit, alle.length));
  }

  String _zeit(Object? roh) {
    final wert = DateTime.tryParse(roh?.toString() ?? '');
    if (wert == null) return '';
    final abstand = DateTime.now().difference(wert.toLocal());
    if (abstand.inMinutes < 1) return 'gerade eben';
    if (abstand.inMinutes < 60) return 'vor ${abstand.inMinutes} Min.';
    if (abstand.inHours < 24) return 'vor ${abstand.inHours} Std.';
    if (abstand.inDays < 7) return 'vor ${abstand.inDays} Tagen';
    final tag = wert.toLocal();
    final tt = tag.day.toString().padLeft(2, '0');
    final mm = tag.month.toString().padLeft(2, '0');
    return '$tt.$mm.${tag.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '#${widget.tag}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _fehler
          ? _fehlerZustand()
          : _laedt
          ? const SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              child: PostSkeletonList(count: 4),
            )
          : RefreshIndicator(
              color: AppAccentColors.accent,
              backgroundColor: const Color(0xFF151821),
              onRefresh: _laden,
              child: _beitraege.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                      children: [
                        Icon(
                          Icons.tag,
                          size: 44,
                          color: Colors.grey.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Noch kein öffentlicher Beitrag mit diesem Hashtag.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 13.5),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Schreib den ersten. Beiträge, die nur Follower '
                          'sehen, tauchen hier bewusst nicht auf.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
                      itemCount: _beitraege.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        if (i == 0) return _kopfzeile();
                        return _karte(_beitraege[i - 1]);
                      },
                    ),
            ),
    );
  }

  /// 2026-08-24 — Auftrag Vucko vom 24.08.: „wenn ihn schon 17 Leute benutzt
  /// haben, dann soll das moeglichst da noch drunter stehen […] man soll
  /// drauf klicken koennen wie bei Instagram oder TikTok."
  ///
  /// Hier stand vorher nur „X Beiträge" in Grau. Jetzt steht die Beitragszahl
  /// gross und ruhig unter dem Hashtag, so wie Instagram und TikTok es
  /// machen, und darunter die Personenzahl als antippbare Zeile.
  ///
  /// BEWUSST KEIN KNOPF: ein Knopf mit Rahmen und Flaeche wuerde in dieser
  /// Kopfzeile schreien und waere in der ganzen App der einzige seiner Art.
  /// Eine farbige Zeile mit Pfeil ist das, was hier ueberall sonst „das
  /// oeffnet etwas" bedeutet.
  Widget _kopfzeile() {
    final zahlen = _zahlen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hashtagBeitraegeText(zahlen.beitraege),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (zahlen.personen > 0)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => HashtagPersonenPage.oeffnen(
                context,
                widget.tag,
                lader: _personen,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hashtagVonLeutenText(zahlen.personen),
                      style: TextStyle(
                        color: AppAccentColors.accent,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppAccentColors.accent,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Kein Netz oder Abfrage kaputt. Bewusst ein ANDERER Text als „noch kein
  /// Beitrag": vorher stand hier auch bei abgeschaltetem Netz, es gebe keinen
  /// Beitrag mit diesem Hashtag. Das klingt nach Auskunft und ist eine
  /// Vermutung — bei einer Verlosung waere es eine falsche.
  Widget _fehlerZustand() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
      children: [
        Icon(
          Icons.wifi_off_rounded,
          size: 44,
          color: Colors.grey.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 14),
        const Text(
          'Die Beiträge konnten nicht geladen werden.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13.5),
        ),
        const SizedBox(height: 6),
        const Text(
          'Das heißt nicht, dass es keine gibt. Prüf die Verbindung und '
          'versuch es nochmal.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _laden,
            style: TextButton.styleFrom(
              foregroundColor: AppAccentColors.accent,
            ),
            child: const Text('Erneut versuchen'),
          ),
        ),
      ],
    );
  }

  Widget _karte(Map<String, dynamic> beitrag) {
    final userId = beitrag['user_id']?.toString();
    final name = SocialService.publicDisplayName(
      beitrag,
      fallbackUserId: userId,
    );
    final handle = SocialService.publicHandle(beitrag, fallbackUserId: userId);
    final inhalt = beitrag['content']?.toString() ?? '';
    final zeit = _zeit(beitrag['created_at']);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PostDetailPage(
            postId: beitrag['post_id']?.toString() ?? '',
            name: name,
            handle: handle,
            content: inhalt,
            time: zeit,
            avatarUrl: beitrag['avatar_url']?.toString(),
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: userId == null
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => UserProfilePage(
                              userId: userId,
                              initialUsername: name,
                            ),
                          ),
                        ),
                  child: UserAvatar(
                    name: name,
                    avatarUrl: beitrag['avatar_url']?.toString(),
                    radius: 18,
                    backgroundColor: AppAccentColors.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        zeit.isEmpty ? handle : '$handle · $zeit',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (inhalt.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  children: buildMentionSpans(
                    context: context,
                    text: inhalt,
                    baseStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
