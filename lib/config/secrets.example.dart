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
}
