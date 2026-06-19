import 'package:shared_preferences/shared_preferences.dart';

/// Kleine First-run-Hinweise, die getrennt vom Routing-Onboarding gepflegt
/// werden. Jeder Hinweis bleibt in Settings erneut abrufbar, soll aber nur
/// einmal automatisch erscheinen.
class SafetyNoticeService {
  SafetyNoticeService._();

  static const String groupSafetyAcceptedKey =
      'group_safety_notice_v1_accepted';
  static const String locationAlwaysSeenKey = 'location_always_notice_v1_seen';

  static Future<bool> hasAcceptedGroupSafety() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(groupSafetyAcceptedKey) ?? false;
  }

  static Future<void> markGroupSafetyAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(groupSafetyAcceptedKey, true);
  }

  static Future<bool> hasSeenLocationAlwaysNotice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(locationAlwaysSeenKey) ?? false;
  }

  static Future<void> markLocationAlwaysNoticeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(locationAlwaysSeenKey, true);
  }
}
