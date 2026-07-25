import 'package:characters/characters.dart';

/// 2026-07-23 (vucko "nur Emoji, kein Text bei Reaktionen"): reine
/// String-Laenge/Runes-Zaehlung wuerde ZWJ-Sequenzen (Familie etc.),
/// Hautton-Modifier und Flaggen faelschlich als mehrere Zeichen zaehlen -
/// characters segmentiert nach den offiziellen Unicode-Grapheme-Cluster-
/// Regeln (UAX #29), die genau diese Sequenzen bereits korrekt als EIN
/// Zeichen erkennen. Deshalb reicht es, (a) zu pruefen dass GENAU ein
/// Grapheme-Cluster vorliegt und (b) dass dessen ERSTER Codepoint ein
/// Emoji-Basis-Zeichen ist (Extended_Pictographic) oder ein
/// Flaggen-Baustein (Regional_Indicator) - der Rest der Sequenz (ZWJ,
/// Hautton-Modifier, zweiter Flaggen-Buchstabe) wurde von characters ja
/// bereits als zusammengehoerig erkannt.
class EmojiGuard {
  EmojiGuard._();

  // Der `valid_regexps`-Linter kennt "Extended_Pictographic" (noch) nicht in
  // seiner eigenen Whitelist und meldet hier faelschlich einen Fehler - das
  // Property existiert und funktioniert (siehe test/core/emoji_guard_test.dart,
  // alle Faelle inkl. ZWJ/Hautton/Flagge sind gruen), nur der STATISCHE
  // Linter kennt es nicht.
  static final RegExp _emojiStartPattern = RegExp(
    // ignore: valid_regexps
    r'^(?:\p{Extended_Pictographic}|\p{Regional_Indicator})$',
    unicode: true,
  );

  /// true nur wenn [value] aus GENAU einem Emoji-Zeichen besteht (kein Text,
  /// keine Buchstaben/Ziffern, keine Mehrfach-Emoji-Strings).
  static bool isSingleEmoji(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    final chars = trimmed.characters;
    if (chars.length != 1) return false;
    final grapheme = chars.first;
    if (grapheme.isEmpty) return false;
    final firstCodepoint = String.fromCharCode(grapheme.runes.first);
    return _emojiStartPattern.hasMatch(firstCodepoint);
  }
}
