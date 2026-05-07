import 'package:shared_preferences/shared_preferences.dart';

class RoutingOnboardingService {
  RoutingOnboardingService._();

  static const String acceptedKey = 'routing_onboarding_v1_accepted';

  static Future<bool> hasAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(acceptedKey) ?? false;
  }

  static Future<void> markAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(acceptedKey, true);
  }
}
