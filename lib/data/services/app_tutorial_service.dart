import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTutorialService {
  AppTutorialService._();

  static const String completedKey = 'app_tutorial_v1_completed';
  static final ValueNotifier<int> replayRequests = ValueNotifier<int>(0);

  static Future<bool> hasCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(completedKey) ?? false;
  }

  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(completedKey, true);
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(completedKey);
  }

  static Future<void> requestReplay() async {
    await reset();
    replayRequests.value += 1;
  }
}
