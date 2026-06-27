import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppAccentOption {
  red('Rot', Color(0xFFFF4D24)),
  blue('Blau', Color(0xFF2F80ED)),
  green('Grün', Color(0xFF22C55E)),
  teal('Türkis', Color(0xFF14B8A6)),
  purple('Lila', Color(0xFFA855F7)),
  orange('Orange', Color(0xFFFF8A00));

  const AppAccentOption(this.label, this.color);

  final String label;
  final Color color;
}

class AppAccentColors {
  AppAccentColors._();

  static Color accent = AppAccentOption.red.color;

  static void apply(Color color) {
    accent = color;
  }

  static Color get accentSoft => accent.withValues(alpha: 0.15);
  static Color get accentMuted => accent.withValues(alpha: 0.3);
  static Color get accentStrong => Color.lerp(accent, Colors.black, 0.18)!;

  static LinearGradient get primaryGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color.lerp(accent, Colors.white, 0.08)!, accentStrong],
  );
}

class AppAccentProvider extends ChangeNotifier {
  static const _storageKey = 'app_accent_color';

  AppAccentOption _option = AppAccentOption.red;

  AppAccentProvider() {
    AppAccentColors.apply(_option.color);
  }

  AppAccentOption get option => _option;
  Color get color => _option.color;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedName = prefs.getString(_storageKey);
    AppAccentOption? storedOption;
    for (final option in AppAccentOption.values) {
      if (option.name == storedName) {
        storedOption = option;
        break;
      }
    }
    if (storedOption == null) return;

    _option = storedOption;
    AppAccentColors.apply(_option.color);
    notifyListeners();
  }

  Future<void> setOption(AppAccentOption option) async {
    if (_option == option) return;

    _option = option;
    AppAccentColors.apply(option.color);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, option.name);
  }
}
