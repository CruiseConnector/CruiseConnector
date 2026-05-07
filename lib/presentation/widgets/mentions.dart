import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/user_profile_page.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

/// Regex zum Parsen von `@username`-Tokens. Akzeptiert ASCII-Buchstaben,
/// Ziffern, Unterstriche und Punkte (häufig in Usernames).
final RegExp mentionPattern = RegExp(r'@([A-Za-z0-9_\.]+)');

/// Zieht alle erwähnten Usernames (lowercase, ohne `@`) aus einem Text.
Set<String> extractMentionUsernames(String text) {
  return mentionPattern
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
}) {
  final spans = <InlineSpan>[];
  final effectiveMentionStyle =
      mentionStyle ??
      baseStyle.copyWith(
        color: AppAccentColors.accent,
        fontWeight: FontWeight.w600,
      );

  int cursor = 0;
  for (final match in mentionPattern.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    final username = match.group(1)!;
    spans.add(
      _MentionSpan.build(
        label: '@$username',
        style: effectiveMentionStyle,
        onTap: () => _openProfileByUsername(context, username),
      ),
    );
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
        content: Text('Profil ist nicht verfuegbar'),
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
    if (!RegExp(r'^[A-Za-z0-9_\.]*$').hasMatch(prefix)) {
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
                ? SizedBox(
                    height: 44,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppAccentColors.accent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Follower laden…',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
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
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onSubmitted,
        ),
      ],
    );
  }
}
