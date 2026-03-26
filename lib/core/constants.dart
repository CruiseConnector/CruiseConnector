import 'package:cruise_connect/config/secrets.dart';

/// App-weite Konstanten.
///
/// API-Keys werden aus [AppSecrets] (lib/config/secrets.dart) gelesen.
/// Die secrets.dart ist gitignored – echte Keys landen nie in Git.
class AppConstants {
  AppConstants._();

  static String get mapboxPublicToken => AppSecrets.mapboxPublicToken;
  static String get supabaseUrl => AppSecrets.supabaseUrl;
  static String get supabaseAnonKey => AppSecrets.supabaseAnonKey;
}
