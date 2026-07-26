import 'package:cruise_connect/core/emoji_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmojiGuard.isSingleEmoji', () {
    // Alle Test-Emoji werden bewusst ueber Codepoints (String.fromCharCodes)
    // gebaut statt als Literal eingefuegt - eindeutig nachvollziehbar, kein
    // Risiko durch unsichtbare/verwechselbare Zeichen im Testcode.
    String cp(List<int> codepoints) => String.fromCharCodes(codepoints);

    final thumbsUp = cp([0x1F44D]);
    final fire = cp([0x1F525]);
    final thumbsUpMediumSkinTone = cp([0x1F44D, 0x1F3FD]);
    final familyZwj = cp([0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467]);
    final flagAustria = cp([0x1F1E6, 0x1F1F9]);
    final heartWithVs16 = cp([0x2764, 0xFE0F]);

    test('einfaches Emoji ist gueltig', () {
      expect(EmojiGuard.isSingleEmoji(thumbsUp), isTrue);
      expect(EmojiGuard.isSingleEmoji(fire), isTrue);
    });

    test('Emoji mit Hautton-Modifier ist gueltig (ein Grapheme)', () {
      expect(EmojiGuard.isSingleEmoji(thumbsUpMediumSkinTone), isTrue);
    });

    test('ZWJ-Familien-Sequenz ist gueltig (ein Grapheme)', () {
      expect(EmojiGuard.isSingleEmoji(familyZwj), isTrue);
    });

    test('Flaggen-Sequenz (2 Regional Indicators) ist gueltig', () {
      expect(EmojiGuard.isSingleEmoji(flagAustria), isTrue);
    });

    test('Emoji mit Variation-Selector-16 ist gueltig', () {
      expect(EmojiGuard.isSingleEmoji(heartWithVs16), isTrue);
    });

    test('Whitespace um ein Emoji wird toleriert', () {
      expect(EmojiGuard.isSingleEmoji(' $fire '), isTrue);
    });

    test('leerer String ist ungueltig', () {
      expect(EmojiGuard.isSingleEmoji(''), isFalse);
      expect(EmojiGuard.isSingleEmoji('   '), isFalse);
    });

    test('einzelner Buchstabe ist ungueltig', () {
      expect(EmojiGuard.isSingleEmoji('A'), isFalse);
      expect(EmojiGuard.isSingleEmoji('a'), isFalse);
    });

    test('einzelne Ziffer ist ungueltig', () {
      expect(EmojiGuard.isSingleEmoji('5'), isFalse);
    });

    test('normaler Text ist ungueltig', () {
      expect(EmojiGuard.isSingleEmoji('Hallo'), isFalse);
      expect(EmojiGuard.isSingleEmoji('gg wp'), isFalse);
    });

    test('zwei separate Emoji hintereinander sind ungueltig (mehr als 1 Grapheme)', () {
      expect(EmojiGuard.isSingleEmoji('$thumbsUp$fire'), isFalse);
    });

    test('Emoji gefolgt von Text ist ungueltig', () {
      expect(EmojiGuard.isSingleEmoji('${fire}gg'), isFalse);
    });

    test('Satzzeichen ist ungueltig', () {
      expect(EmojiGuard.isSingleEmoji('!'), isFalse);
      expect(EmojiGuard.isSingleEmoji('?'), isFalse);
    });
  });
}
