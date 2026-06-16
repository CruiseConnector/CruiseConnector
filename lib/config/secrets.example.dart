/// TEMPLATE-DATEI – Echte Keys HIER NICHT eintragen!
///
/// So verwendest du diese Datei:
///   1. Kopiere diese Datei: secrets.example.dart → secrets.dart
///   2. Trage deine echten API-Keys in secrets.dart ein
///   3. secrets.dart ist gitignored und wird nie committed
///
/// Wo findest du die Keys?
///   - Supabase URL:    Supabase Dashboard → Project Settings → API → URL
///   - Supabase Anon:   Supabase Dashboard → Project Settings → API → anon key
class AppSecrets {
  AppSecrets._();

  // Supabase – Projekt-URL
  static const String supabaseUrl = 'https://DEIN_PROJEKT_ID.supabase.co';

  // Supabase – Anon Key (anon-Rolle, kein Admin-Zugriff)
  static const String supabaseAnonKey = 'DEIN_SUPABASE_ANON_KEY';
  // Google OAuth - Public Client IDs, keine Secrets.
  // Web Client ID: Google Cloud Console -> APIs & Services -> Credentials.
  static const String googleWebClientId =
      'DEIN_GOOGLE_WEB_CLIENT_ID.apps.googleusercontent.com';

  // iOS Client ID: Google Cloud Console -> OAuth Client ID -> iOS.
  // Android braucht hier normalerweise keinen eigenen Wert.
  static const String googleIosClientId =
      'DEIN_GOOGLE_IOS_CLIENT_ID.apps.googleusercontent.com';
}
