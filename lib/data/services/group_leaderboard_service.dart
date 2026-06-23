import 'package:supabase_flutter/supabase_flutter.dart';

/// Eine Zeile der Gruppen-Rangliste: aggregierte Fahrleistung EINES Mitglieds
/// über alle Fahrten dieser Gruppe. Quelle ist die deterministische
/// SECURITY-DEFINER-RPC `get_group_leaderboard` — der Server aggregiert + sortiert
/// (Distanz desc, dann Top-Speed desc, dann user_id) -> jeder Client sieht exakt
/// dasselbe Ergebnis.
class GroupLeaderboardEntry {
  const GroupLeaderboardEntry({
    required this.userId,
    required this.username,
    required this.avatarUrl,
    required this.totalDistanceKm,
    required this.maxTopSpeedKmh,
    required this.totalDurationSeconds,
    required this.sessionCount,
  });

  final String userId;
  final String? username;
  final String? avatarUrl;
  final double totalDistanceKm;
  final double maxTopSpeedKmh;
  final int totalDurationSeconds;
  final int sessionCount;

  factory GroupLeaderboardEntry.fromMap(Map<String, dynamic> row) {
    double asDouble(Object? v) =>
        v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0.0;
    int asInt(Object? v) =>
        v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    return GroupLeaderboardEntry(
      userId: row['user_id'].toString(),
      username: row['username'] as String?,
      avatarUrl: row['avatar_url'] as String?,
      totalDistanceKm: asDouble(row['total_distance_km']),
      maxTopSpeedKmh: asDouble(row['max_top_speed_kmh']),
      totalDurationSeconds: asInt(row['total_duration_seconds']),
      sessionCount: asInt(row['session_count']),
    );
  }
}

/// Liest die deterministische Gruppen-Rangliste. Wirft NICHT — bei jedem Fehler
/// (Netz/RLS/leer) gibt es eine leere Liste zurück, damit die Lobby nie in einer
/// Fehler-Sackgasse hängt (analog zum übrigen Gruppen-Code).
class GroupLeaderboardService {
  GroupLeaderboardService._();
  static final _db = Supabase.instance.client;

  static Future<List<GroupLeaderboardEntry>> fetch(String groupId) async {
    try {
      final data = await _db.rpc(
        'get_group_leaderboard',
        params: {'p_group_id': groupId},
      );
      if (data is! List) return const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(GroupLeaderboardEntry.fromMap)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
