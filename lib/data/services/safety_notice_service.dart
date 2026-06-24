import 'package:shared_preferences/shared_preferences.dart';

/// Kleine First-run-Hinweise, die getrennt vom Routing-Onboarding gepflegt
/// werden. Jeder Hinweis bleibt in Settings erneut abrufbar, soll aber nur
/// einmal automatisch erscheinen.
class SafetyNoticeService {
  SafetyNoticeService._();

  static const String groupSafetyAcceptedKey =
      'group_safety_notice_v1_accepted';
  static const String locationAlwaysSeenKey = 'location_always_notice_v1_seen';
  static const String notificationNoticeSeenKey =
      'notification_permission_notice_v1_seen';
  static const String notificationNoticeAcceptedKey =
      'notification_permission_notice_v1_accepted';

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

  static Future<bool> hasSeenNotificationPermissionNotice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(notificationNoticeSeenKey) ?? false;
  }

  static Future<bool> hasAcceptedNotificationPermissionNotice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(notificationNoticeAcceptedKey) ?? false;
  }

  static Future<void> markNotificationPermissionNotice({
    required bool accepted,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(notificationNoticeSeenKey, true);
    await prefs.setBool(notificationNoticeAcceptedKey, accepted);
  }
}
