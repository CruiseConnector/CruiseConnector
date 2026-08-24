import 'package:flutter/material.dart';
import 'package:cruise_connect/presentation/widgets/skeletons/skeleton.dart';
import 'package:flutter/services.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/hashtag_beitraege_page.dart';
import 'package:cruise_connect/presentation/pages/user_profile_page.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

/// Regex zum Parsen von `@username`-Tokens.
final RegExp mentionPattern = RegExp(r'@([A-Za-z0-9_]+)');

/// 2026-08-24 — Aufgabe 1.3 aus dem Auftrag vom 23.08.
///
/// Vucko, Aufnahme 3: „wenn man Hashtags hätte […] dass man unter Hashtags
/// Sachen suchen kann" und „für zukünftige Gewinnspiele wäre das auch ganz
/// cool, dass man da Sachen auslosen kann".
///
/// DIESES MUSTER MUSS ZEICHENGLEICH MIT DER DATENBANK SEIN. Dort steht in
/// Migration 20260824102000 (Trigger `post_hashtags_pflegen`):
///
///     '#([[:alpha:]_][[:alnum:]_]{1,49})'
///
/// Also: erstes Zeichen ein Unicode-BUCHSTABE oder ein Unterstrich, danach
/// Buchstaben, Ziffern und Unterstriche, insgesamt 2 bis 50 Zeichen ohne die
/// Raute. `#2026` ist damit KEIN Hashtag (das hält Preisangaben und
/// Hausnummern draussen), `#cruise2026` schon.
///
/// Läuft die Anzeige hier auseinander, macht die App etwas anklickbar, das
/// die Suche nie findet — oder umgekehrt. Bei einer Verlosung heißt das:
/// Teilnehmer verlieren.
///
/// In Dart heißt „Unicode-Buchstabe" `\p{L}` mit `unicode: true`. Genau
/// deshalb ist ein reines `[A-Za-z]` hier falsch: Deutsche Umlaute sind ein
/// echter Fall, `#kurvenkönig` muss anklickbar sein.
final RegExp hashtagPattern = RegExp(
  r'#([\p{L}_][\p{L}\p{N}_]{1,49})',
  unicode: true,
);

/// Zieht alle erwähnten Usernames (lowercase, ohne `@`) aus einem Text.
Set<String> extractMentionUsernames(String text) {
  return mentionPattern
      .allMatches(text)
      .map((m) => m.group(1)!.toLowerCase())
      .toSet();
}

/// 2026-08-24 (Aufgabe 1.3): alle Hashtags eines Textes, klein geschrieben
/// und ohne die Raute.
///
/// Das ist genau das, was der Trigger in der Datenbank ablegt
/// (`lower(m[1])`). Der Client SCHREIBT die Hashtags NICHT — das macht
/// ausschliesslich der Trigger. Das ist Absicht: sonst trägt sich jemand per
/// manipuliertem Aufruf in ein Gewinnspiel ein, ohne den Hashtag je
/// geschrieben zu haben (dieselbe Lehre wie beim Meldungs-Missbrauchsschutz
/// vom 26.07.). Diese Funktion ist nur für Anzeige und Vorschau da.
Set<String> extractHashtags(String text) {
  return hashtagPattern
      .allMatches(text)
      .map((m) => m.group(1)!.toLowerCase())
      .toSet();
}

/// Baut [TextSpan]s mit klickbaren `@username`-Mentions in App-Rot.
/// Tap navigiert zum Profil; nicht auflösbare Mentions bleiben als Plain-Text.
List<InlineSpan> buildMentionSpans({
  required BuildContext context,
  required String text,
  required TextStyle baseStyle,
  TextStyle? mentionStyle,
  Set<String> plainMentions = const {},
}) {
  final spans = <InlineSpan>[];
  final effectiveMentionStyle =
      mentionStyle ??
      baseStyle.copyWith(
        color: AppAccentColors.accent,
        fontWeight: FontWeight.w600,
      );

  // 2026-08-24 (Aufgabe 1.3): ZWEITES MUSTER IN DERSELBEN SCHLEIFE.
  //
  // Beide Trefferlisten werden zusammengeworfen und nach Startposition
  // sortiert, damit die Reihenfolge im Text erhalten bleibt. Überschneiden
  // können sich die beiden nicht — `@` ist in keinem Hashtag-Zeichensatz und
  // `#` in keinem Erwähnungs-Zeichensatz. Die Prüfung auf Überlappung steht
  // trotzdem da: sie kostet nichts und fängt ab, falls jemand später ein
  // Muster erweitert.
  //
  // Damit erben alle SECHS Anzeigestellen die anklickbaren Hashtags, ohne
  // dass eine davon angefasst werden muss (Feed, Entdecken, Beitrags-Detail,
  // zwei Profil-Seiten, gemerkte Beiträge, Community-Chat).
  final treffer = <RegExpMatch>[
    ...mentionPattern.allMatches(text).cast<RegExpMatch>(),
    ...hashtagPattern.allMatches(text).cast<RegExpMatch>(),
  ]..sort((a, b) => a.start.compareTo(b.start));

  int cursor = 0;
  for (final match in treffer) {
    if (match.start < cursor) continue; // Überlappung, schon verarbeitet
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    final wort = match.group(1)!;
    final istHashtag = text[match.start] == '#';

    if (istHashtag) {
      // 2026-08-24 (Auftrag Vucko vom 24.08.: „wenn ihn schon 17 Leute
      // benutzt haben, dann soll das moeglichst da noch drunter stehen"):
      // HIER steht die Zahl BEWUSST NICHT.
      //
      // Ein Hashtag im Fliesstext ist ein Wort in einem Satz. „Heute #bmw
      // (17) gefahren" macht den Satz kaputt, und in einem Beitrag mit drei
      // Hashtags stuenden drei Zahlen, die niemand vergleicht. Instagram und
      // TikTok, Vuckos Vorbilder, zeigen die Zahl auch erst auf der
      // Hashtag-Seite — dort, wo man sich fuer den Hashtag entschieden hat.
      // Der Weg dorthin ist ein Tipp weit.
      spans.add(
        _MentionSpan.build(
          label: '#$wort',
          style: effectiveMentionStyle,
          onTap: () => HashtagBeitraegePage.oeffnen(context, wort),
        ),
      );
    } else if (plainMentions.contains(wort.toLowerCase())) {
      spans.add(
        TextSpan(
          text: '@$wort',
          style: effectiveMentionStyle.copyWith(fontWeight: FontWeight.w800),
        ),
      );
    } else {
      spans.add(
        _MentionSpan.build(
          label: '@$wort',
          style: effectiveMentionStyle,
          onTap: () => _openProfileByUsername(context, wort),
        ),
      );
    }
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return spans;
}

class _MentionSpan {
  static InlineSpan build({
    required String label,
    required TextStyle style,
    required VoidCallback onTap,
  }) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Text(label, style: style),
      ),
    );
  }
}

Future<void> _openProfileByUsername(
  BuildContext context,
  String username,
) async {
  final userId = await SocialService.findUserIdByUsername(username);
  if (!context.mounted) return;
  if (userId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('@$username nicht gefunden'),
        backgroundColor: const Color(0xFF1C1F26),
      ),
    );
    return;
  }
  if (await SocialService.isBlockedEither(userId)) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profil ist nicht verfügbar'),
        backgroundColor: Color(0xFF1C1F26),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          UserProfilePage(userId: userId, initialUsername: username),
    ),
  );
}

/// Container, der ein eigenes [TextField] mit Inline-Mention-Vorschlägen
/// kombiniert. Vorschläge erscheinen oberhalb des Eingabefelds; nur Follower
/// des aktuellen Users werden vorgeschlagen (Anti-Spam).
class MentionTextField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration decoration;
  final TextStyle? style;
  final int maxLines;
  final int? minLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;

  const MentionTextField({
    super.key,
    required this.controller,
    this.decoration = const InputDecoration(),
    this.style,
    this.maxLines = 1,
    this.minLines,
    this.textInputAction,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.maxLength,
    this.inputFormatters,
  });

  @override
  State<MentionTextField> createState() => _MentionTextFieldState();
}

class _MentionTextFieldState extends State<MentionTextField> {
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = false;
  String? _activePrefix; // null = kein @ aktiv, '' = direkt nach @
  int _activeStart = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _clearSuggestions();
      return;
    }
    final text = widget.controller.text;
    final cursor = selection.baseOffset.clamp(0, text.length);

    // Suche das letzte `@` vor dem Cursor in einem zusammenhängenden Token.
    int at = -1;
    for (int i = cursor - 1; i >= 0; i--) {
      final ch = text[i];
      if (ch == '@') {
        at = i;
        break;
      }
      // Token-Abbruch bei Whitespace/Newline.
      if (RegExp(r'\s').hasMatch(ch)) break;
    }
    if (at == -1) {
      _clearSuggestions();
      return;
    }
    // `@` muss am Wort-Anfang stehen (Zeilenstart oder nach Whitespace).
    final before = at == 0 ? '' : text[at - 1];
    if (before.isNotEmpty && !RegExp(r'\s').hasMatch(before)) {
      _clearSuggestions();
      return;
    }
    final prefix = text.substring(at + 1, cursor);
    if (!RegExp(r'^[A-Za-z0-9_]*$').hasMatch(prefix)) {
      _clearSuggestions();
      return;
    }
    _activePrefix = prefix;
    _activeStart = at;
    _fetchSuggestions(prefix);
  }

  void _clearSuggestions() {
    if (_activePrefix == null && _suggestions.isEmpty) return;
    setState(() {
      _activePrefix = null;
      _activeStart = -1;
      _suggestions = [];
      _loading = false;
    });
  }

  Future<void> _fetchSuggestions(String prefix) async {
    setState(() => _loading = true);
    final list = await SocialService.getMyFollowerProfiles(prefix: prefix);
    if (!mounted) return;
    // Nur übernehmen, wenn der Prefix noch aktuell ist (Race-Schutz).
    if (_activePrefix != prefix) return;
    setState(() {
      _suggestions = list;
      _loading = false;
    });
  }

  void _insertMention(String username) {
    final text = widget.controller.text;
    if (_activeStart < 0) return;
    final cursor = widget.controller.selection.baseOffset.clamp(0, text.length);
    final before = text.substring(0, _activeStart);
    final after = text.substring(cursor);
    final inserted = '@$username ';
    final newText = '$before$inserted$after';
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: before.length + inserted.length,
      ),
    );
    _clearSuggestions();
  }

  @override
  Widget build(BuildContext context) {
    final showSuggestions =
        _activePrefix != null && (_loading || _suggestions.isNotEmpty);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSuggestions)
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1F26),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: _loading && _suggestions.isEmpty
                ? const SkeletonList(
                    count: 3,
                    avatarSize: 32,
                    lines: 1,
                    padding: EdgeInsets.symmetric(vertical: 4),
                  )
                : _suggestions.isEmpty
                ? const SizedBox(
                    height: 44,
                    child: Center(
                      child: Text(
                        'Keine passenden Follower',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, i) {
                      final p = _suggestions[i];
                      final username = p['username'] as String? ?? '';
                      final email = p['email'] as String? ?? '';
                      final avatar = p['avatar_url'] as String?;
                      return InkWell(
                        onTap: () => _insertMention(username),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              UserAvatar(
                                name: username.isNotEmpty ? username : '?',
                                avatarUrl: avatar,
                                radius: 14,
                                backgroundColor: AppAccentColors.accent,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '@$username',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (email.isNotEmpty)
                                      Text(
                                        email,
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 11,
                                        ),
                                        overflow: TextOverflow.ellipsis,
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
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          decoration: widget.decoration,
          style: widget.style,
          maxLines: widget.maxLines,
          minLines: widget.minLines,
          maxLength: widget.maxLength,
          inputFormatters: widget.inputFormatters,
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onSubmitted,
        ),
      ],
    );
  }
}
