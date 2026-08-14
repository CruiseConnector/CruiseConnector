import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 2026-08-14 (vucko Tutorial-Badge): Liefert den Beitrittszeitpunkt des
/// eingeloggten Nutzers (profiles.created_at) für das „Gründungszeit"-Badge
/// („Dabei seit August 2026"). Einmal geladen, dann im Speicher gecacht —
/// das Datum ändert sich nie, also reicht ein Query pro App-Lauf.
class MembershipSinceService {
  MembershipSinceService._();

  static DateTime? _cached;
  static String? _cachedForUserId;

  static Future<DateTime?> load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;
    if (_cached != null && _cachedForUserId == userId) return _cached;

    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('created_at')
          .eq('id', userId)
          .maybeSingle();
      final raw = row?['created_at'] as String?;
      if (raw != null) {
        final parsed = DateTime.tryParse(raw);
        if (parsed != null) {
          _cached = parsed.toLocal();
          _cachedForUserId = userId;
        }
      }
    } catch (e) {
      debugPrint('[MembershipSince] created_at laden fehlgeschlagen: $e');
    }
    return _cached;
  }

  @visibleForTesting
  static void resetCache() {
    _cached = null;
    _cachedForUserId = null;
  }
}
