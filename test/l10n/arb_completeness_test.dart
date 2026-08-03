// Vollständigkeit der Übersetzungen (2026-08-03, vucko Sprachumschaltung).
//
// Bei ~2.000 Strings kann niemand im Kopf behalten, welcher Schlüssel schon
// übersetzt ist. Dieser Test ist die Absicherung: Er schlägt fehl, sobald ein
// deutscher Schlüssel kein englisches Gegenstück hat (oder umgekehrt).
//
// Ausführen: flutter test test/l10n/arb_completeness_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Liest die echten Übersetzungsschlüssel einer ARB-Datei.
/// `@@locale` ist Metadatum, `@key`-Einträge sind Beschreibungen für Übersetzer.
Map<String, String> _readArb(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('ARB-Datei fehlt: $path');
  }
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final entries = <String, String>{};
  for (final entry in decoded.entries) {
    if (entry.key.startsWith('@')) continue;
    entries[entry.key] = entry.value.toString();
  }
  return entries;
}

void main() {
  late Map<String, String> german;
  late Map<String, String> english;

  setUpAll(() {
    german = _readArb('lib/l10n/app_de.arb');
    english = _readArb('lib/l10n/app_en.arb');
  });

  test('jeder deutsche Schluessel hat eine englische Uebersetzung', () {
    final missing = german.keys.where((key) => !english.containsKey(key)).toList()
      ..sort();
    expect(
      missing,
      isEmpty,
      reason:
          'Diese Schluessel fehlen in app_en.arb:\n${missing.join('\n')}',
    );
  });

  test('keine verwaisten englischen Schluessel', () {
    final orphans = english.keys.where((key) => !german.containsKey(key)).toList()
      ..sort();
    expect(
      orphans,
      isEmpty,
      reason:
          'Diese Schluessel stehen nur in app_en.arb (in app_de.arb geloescht?):\n'
          '${orphans.join('\n')}',
    );
  });

  test('keine leeren Uebersetzungen', () {
    final emptyGerman = german.entries
        .where((e) => e.value.trim().isEmpty)
        .map((e) => e.key)
        .toList();
    final emptyEnglish = english.entries
        .where((e) => e.value.trim().isEmpty)
        .map((e) => e.key)
        .toList();
    expect(emptyGerman, isEmpty, reason: 'Leer in app_de.arb');
    expect(emptyEnglish, isEmpty, reason: 'Leer in app_en.arb');
  });

  test('englische Texte sind nicht bloss vom Deutschen kopiert', () {
    // Ein paar Woerter sind in beiden Sprachen identisch (Namen, „Deutsch",
    // „English", „OK"). Verdaechtig sind laengere Saetze, die Wort fuer Wort
    // gleich geblieben sind — das ist meist eine vergessene Uebersetzung.
    final suspicious = <String>[];
    for (final entry in german.entries) {
      final englishValue = english[entry.key];
      if (englishValue == null) continue;
      final isLongSentence = entry.value.trim().split(RegExp(r'\s+')).length >= 4;
      if (isLongSentence && englishValue.trim() == entry.value.trim()) {
        suspicious.add(entry.key);
      }
    }
    expect(
      suspicious,
      isEmpty,
      reason:
          'Diese laengeren Texte sind in beiden Sprachen identisch — '
          'vermutlich nicht uebersetzt:\n${suspicious.join('\n')}',
    );
  });

  test('untranslated.json ist leer (gen-l10n meldet keine Luecken)', () {
    final file = File('untranslated.json');
    if (!file.existsSync()) {
      // Datei entsteht erst beim Build — kein Grund fehlzuschlagen.
      return;
    }
    final content = file.readAsStringSync().trim();
    if (content.isEmpty) return;
    final decoded = jsonDecode(content) as Map<String, dynamic>;
    expect(
      decoded,
      isEmpty,
      reason: 'gen-l10n meldet fehlende Uebersetzungen:\n$content',
    );
  });
}
