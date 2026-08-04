// Sprachwahl Deutsch / English (2026-08-03, vucko).
//
// Aufgebaut wie AppAccentProvider (ChangeNotifier + shared_preferences) — das
// ist das etablierte Muster für App-Einstellungen in diesem Projekt.

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  german('de', 'Deutsch'),
  english('en', 'English');

  const AppLanguage(this.code, this.label);

  /// Sprachcode für Locale, GraphHopper (`locale`) und `profiles.language`.
  final String code;

  /// Anzeigename — bewusst IMMER in der jeweiligen Sprache selbst, damit man
  /// seine Sprache auch findet, wenn die App gerade in der anderen läuft.
  final String label;

  static AppLanguage? fromCode(String? code) {
    if (code == null) return null;
    final normalized = code.trim().toLowerCase();
    for (final language in AppLanguage.values) {
      if (language.code == normalized) return language;
    }
    return null;
  }
}

class AppLocaleProvider extends ChangeNotifier {
  static const _languageKey = 'app_language';
  static const _languageChosenKey = 'app_language_chosen';

  AppLanguage _language = AppLanguage.german;
  bool _hasChosen = false;
  bool _loaded = false;

  AppLanguage get language => _language;
  Locale get locale => Locale(_language.code);

  /// Ob der Nutzer die Sprache schon einmal bewusst gewählt hat. Solange das
  /// false ist, zeigt der Start die Sprachwahl.
  bool get hasChosen => _hasChosen;

  /// Ob [load] durchgelaufen ist — verhindert, dass der Start-Gate die
  /// Sprachwahl aufblitzen lässt, bevor die gespeicherte Wahl gelesen wurde.
  bool get isLoaded => _loaded;

  /// Sprache des Geräts, wenn wir sie unterstützen — sonst Deutsch.
  /// Dient als Vorbelegung im Sprachwahl-Screen.
  static AppLanguage systemSuggestion() {
    final systemCode = PlatformDispatcher.instance.locale.languageCode;
    return AppLanguage.fromCode(systemCode) ?? AppLanguage.german;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = AppLanguage.fromCode(prefs.getString(_languageKey));
    _hasChosen = prefs.getBool(_languageChosenKey) ?? false;
    // Ohne gespeicherte Wahl läuft die App in der Geräte-Sprache, bis der
    // Nutzer im Sprachwahl-Screen bestätigt — der Screen zeigt dann also
    // bereits die Sprache, die er vermutlich will.
    _language = stored ?? systemSuggestion();
    _loaded = true;
    notifyListeners();
  }

  /// Sprache setzen. [markChosen] false = nur vorübergehend (Vorschau im
  /// Sprachwahl-Screen), true = bewusste Wahl des Nutzers.
  Future<void> setLanguage(
    AppLanguage language, {
    bool markChosen = true,
  }) async {
    final changed = _language != language || (markChosen && !_hasChosen);
    if (!changed) return;

    _language = language;
    if (markChosen) _hasChosen = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, language.code);
    if (markChosen) await prefs.setBool(_languageChosenKey, true);
  }
}
