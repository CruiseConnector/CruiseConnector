import 'package:flutter/services.dart';

class AppInputLimits {
  AppInputLimits._();

  static const int usernameMinLength = 3;
  static const int usernameMaxLength = 20;
  static const int postContentMaxLength = 1000;
  static const int commentMaxLength = 1000;
  static const int groupNameMaxLength = 25;
  static const int groupDescriptionMaxLength = 300;
  static const int communityNameMaxLength = 40;
  static const int communityDescriptionMaxLength = 300;
  static const int communityMessageMaxLength = 2000;
  static const int groupRouteNameMaxLength = 80;
  static const int groupStatsMaxLength = 120;
  static const int groupTimeLocationMaxLength = 160;
  static const int bioTitleMaxLength = 40;
  static const int bioMaxLength = 500;
  static const int linkMaxLength = 200;
  static const int routeNameMaxLength = 60;
  static const int shortTextMaxLength = 32;
  static const int addressMaxLength = 160;
  static const int searchQueryMaxLength = 64;
  static const int emailMaxLength = 254;
  static const int passwordMaxLength = 128;
  static const int reportDetailsMaxLength = 280;
  static const int vehicleDescriptionMaxLength = 500;
  static const int vehicleTuningMaxLength = 500;

  static final RegExp usernameRegExp = RegExp(r'^[A-Za-z0-9_]{3,20}$');

  static final List<TextInputFormatter> usernameFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
    LengthLimitingTextInputFormatter(usernameMaxLength),
  ];

  static List<TextInputFormatter> lengthFormatters(int maxLength) {
    return [LengthLimitingTextInputFormatter(maxLength)];
  }

  static bool isValidUsername(String value) {
    return usernameRegExp.hasMatch(value.trim());
  }

  static String normalizeUsernameFallback(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final fallback = normalized.isEmpty
        ? 'Cruiser'
        : normalized.length < usernameMinLength
        ? 'Cruiser_$normalized'
        : normalized;
    return fallback.length <= usernameMaxLength
        ? fallback
        : fallback.substring(0, usernameMaxLength);
  }
}
