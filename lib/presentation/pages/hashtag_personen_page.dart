import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/user_profile_page.dart';
import 'package:cruise_connect/presentation/widgets/skeletons/skeleton.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

/// 2026-08-24 — Auftrag Vucko vom 24.08.
///
/// Vucko: „dass man sieht, wer alles so einen # benutzt hat. Also wenn ihn
/// schon 17 Leute benutzt haben, dann soll das moeglichst da noch drunter
/// stehen […] man soll drauf klicken koennen wie bei Instagram oder TikTok."
///
/// Das hier ist die Liste hinter der Zahl. Sie ist bewusst wie die Rangliste
/// in `analytics_page.dart` gebaut (Bild, Name, darunter der Handle, rechts
/// die Kennzahl, Antippen fuehrt aufs Profil) und nicht wie eine neue,
/// vierte Darstellung von Personen. Wer die Rangliste kennt, kennt diese
/// Liste.
///
/// ZWEI ZAHLEN, DIE MAN NICHT VERWECHSELN DARF: „5 Leute" sind fuenf
/// verschiedene Verfasser, „12 Beitraege" sind zwoelf Beitraege. Wer
/// zehnmal denselben Hashtag schreibt, ist EINE Person. Genau deshalb
/// stammt die Personenzahl nicht aus `hashtag_vorschlaege`, wo `anzahl`
/// Beitraege zaehlt.

/// „von 17 Leuten" — die antippbare Zeile unter der Beitragszahl.
///
/// „von 1 Leuten" waere der klassische Programmierfehler in Listen. Vucko
/// sagt „Leute", deshalb steht das in der Mehrzahl; in der Einzahl sagt
/// niemand „1 Leut", also „1 Person".
String hashtagVonLeutenText(int anzahl) {
  if (anzahl == 1) return 'von 1 Person';
  return 'von $anzahl Leuten';
}

/// „17 Leute haben #bmw benutzt" — die Ueberschrift ueber der Personenliste.
///
/// [mindestens] steht, solange noch nachgeladen werden kann. Eine Zahl, die
/// sich beim Weiterscrollen aendert, waere schlimmer als gar keine.
String hashtagLeuteSatz(int anzahl, String tag, {bool mindestens = false}) {
  if (mindestens) return 'Mindestens $anzahl Leute haben #$tag benutzt';
  if (anzahl == 1) return '1 Person hat #$tag benutzt';
  return '$anzahl Leute haben #$tag benutzt';
}

/// Wie viele Beitraege — Nutzertext, Einzahl und Mehrzahl getrennt.
String hashtagBeitraegeText(int anzahl) {
  if (anzahl <= 0) return 'Keine Beiträge';
  if (anzahl == 1) return '1 Beitrag';
  return '$anzahl Beiträge';
}

/// Ein Blatt mit allen Leuten, die einen Hashtag benutzt haben.
class HashtagPersonenPage extends StatefulWidget {
  const HashtagPersonenPage({
    super.key,
    required this.tag,
    this.lader,
    this.seitenGroesse = 50,
  });

  /// Ohne Raute. Der Einstieg [oeffnen] macht sie weg.
  final String tag;

  /// Nur fuer Tests und fuer den Notbehelf aus der Beitragsseite gedacht.
  /// Ohne Angabe fragt die Seite die Datenbank.
  ///
  /// `null` als Ergebnis heisst FEHLER, `[]` heisst NIEMAND — die Seite
  /// zeigt fuer beides einen anderen Text.
  final Future<List<Map<String, dynamic>>?> Function(
    String tag, {
    int limit,
    int offset,
  })?
  lader;

  /// Wie viele Zeilen pro Nachladeschritt.
  final int seitenGroesse;

  static Future<void> oeffnen(
    BuildContext context,
    String tag, {
    Future<List<Map<String, dynamic>>?> Function(
      String tag, {
      int limit,
      int offset,
    })?
    lader,
  }) {
    final sauber = SocialService.normalisiereHashtagEingabe(tag);
    if (sauber.isEmpty) return Future<void>.value();
    return Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => HashtagPersonenPage(tag: sauber, lader: lader),
      ),
    );
  }

  @override
  State<HashtagPersonenPage> createState() => _HashtagPersonenPageState();
}

class _HashtagPersonenPageState extends State<HashtagPersonenPage> {
  final ScrollController _scroll = ScrollController();

  bool _laedt = true;
  bool _laedtNach = false;
  bool _fehler = false;
  bool _hatMehr = true;
  List<Map<String, dynamic>> _personen = const [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_beimScrollen);
    _laden();
  }

  @override
  void dispose() {
    _scroll.removeListener(_beimScrollen);
    _scroll.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>?> _hole({
    required int limit,
    required int offset,
  }) {
    final lader = widget.lader ?? SocialService.hashtagPersonen;
    return lader(widget.tag, limit: limit, offset: offset);
  }

  Future<void> _laden() async {
    setState(() {
      _laedt = true;
      _fehler = false;
    });
    final treffer = await _hole(limit: widget.seitenGroesse, offset: 0);
    if (!mounted) return;
    setState(() {
      _laedt = false;
      _fehler = treffer == null;
      _personen = treffer ?? const [];
      _hatMehr = treffer != null && treffer.length >= widget.seitenGroesse;
    });
  }

  /// Nachladen beim Scrollen.
  ///
  /// Bei zehn Beitraegen in der ganzen Datenbank ist das heute totes Holz.
  /// Es steht trotzdem hier, weil ein beliebter Hashtag genau die Stelle
  /// ist, an der eine Liste ohne Nachladen abgeschnitten aussieht — und
  /// niemand meldet „mir fehlen Leute", die er nie gesehen hat.
  void _beimScrollen() {
    if (!_scroll.hasClients || _laedt || _laedtNach || !_hatMehr) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 400) return;
    _nachladen();
  }

  Future<void> _nachladen() async {
    if (_laedtNach || !_hatMehr) return;
    setState(() => _laedtNach = true);
    final weitere = await _hole(
      limit: widget.seitenGroesse,
      offset: _personen.length,
    );
    if (!mounted) return;
    setState(() {
      _laedtNach = false;
      if (weitere == null) {
        // Ein Fehler beim NACHladen wirft die schon sichtbare Liste nicht
        // weg. Er stoppt nur das Nachladen, sonst dreht sich der Kringel
        // ewig.
        _hatMehr = false;
        return;
      }
      final bekannt = _personen
          .map((p) => p['user_id']?.toString())
          .whereType<String>()
          .toSet();
      final neue = weitere.where((p) {
        final id = p['user_id']?.toString();
        return id != null && !bekannt.contains(id);
      }).toList();
      _personen = [..._personen, ...neue];
      _hatMehr = weitere.length >= widget.seitenGroesse && neue.isNotEmpty;
    });
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
      body: _inhalt(),
    );
  }

  Widget _inhalt() {
    if (_laedt) {
      return const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        child: SkeletonList(count: 6, avatarSize: 36, hasTrailing: true),
      );
    }
    if (_fehler) return _fehlerZustand();

    return RefreshIndicator(
      color: AppAccentColors.accent,
      backgroundColor: const Color(0xFF151821),
      onRefresh: _laden,
      child: _personen.isEmpty
          ? _leerZustand()
          : ListView.separated(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
              itemCount: _personen.length + (_laedtNach ? 2 : 1),
              separatorBuilder: (_, _) => const SizedBox(height: 9),
              itemBuilder: (context, i) {
                if (i == 0) return _kopfzeile();
                if (i - 1 >= _personen.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                return _zeile(_personen[i - 1]);
              },
            ),
    );
  }

  Widget _kopfzeile() {
    // Solange nachgeladen werden kann, ist die Zahl hier eine Untergrenze.
    // Deshalb steht dann „mindestens" davor statt einer Zahl, die gleich
    // wieder eine andere ist.
    final text = hashtagLeuteSatz(
      _personen.length,
      widget.tag,
      mindestens: _hatMehr,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 4),
      child: Text(
        text,
        style: const TextStyle(color: Colors.grey, fontSize: 12.5),
      ),
    );
  }

  Widget _zeile(Map<String, dynamic> person) {
    final userId = person['user_id']?.toString();
    final name = SocialService.publicDisplayName(
      person,
      fallbackUserId: userId,
    );
    final handle = SocialService.publicHandle(person, fallbackUserId: userId);
    final anzahl = (person['anzahl'] as num?)?.toInt() ?? 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: userId == null || userId.isEmpty
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      UserProfilePage(userId: userId, initialUsername: name),
                ),
              ),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              UserAvatar(
                name: name,
                avatarUrl: person['avatar_url']?.toString(),
                radius: 18,
                backgroundColor: AppAccentColors.accent,
              ),
              const SizedBox(width: 11),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      handle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFA0AEC0),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                hashtagBeitraegeText(anzahl),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _leerZustand() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
      children: [
        Icon(
          Icons.people_outline,
          size: 44,
          color: Colors.grey.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 14),
        Text(
          'Noch niemand hat #${widget.tag} benutzt.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey, fontSize: 13.5),
        ),
        const SizedBox(height: 6),
        const Text(
          'Sobald jemand ihn in einem öffentlichen Beitrag schreibt, steht '
          'er hier. Beiträge, die nur Follower sehen, zählen bewusst nicht '
          'mit.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

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
          'Die Liste konnte nicht geladen werden.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13.5),
        ),
        const SizedBox(height: 6),
        const Text(
          'Das heißt nicht, dass niemand ihn benutzt hat. Wir kommen gerade '
          'nur nicht an die Daten. Prüf die Verbindung.',
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
}
