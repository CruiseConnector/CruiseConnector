import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 2026-08-16 (vucko Testfahrt, Aufgabe 6): „Auf der Startseite ein Widget
/// mit der Rangliste — Top 3, die eigene Position, wöchentlich und monatlich."
///
/// Datenquelle ist die RPC `get_rangliste(p_zeitraum, p_limit)`
/// (SECURITY DEFINER, Migration 20260816040000): Kilometer-Summe je Fahrer im
/// laufenden Zeitraum (Wiener Zeit), Top-N plus die eigene Zeile mit Rang.
enum RanglisteZeitraum { woche, monat }

extension RanglisteZeitraumX on RanglisteZeitraum {
  String get rpcWert => this == RanglisteZeitraum.monat ? 'monat' : 'woche';
  String get label => this == RanglisteZeitraum.monat ? 'Monat' : 'Woche';
}

class RanglisteEintrag {
  const RanglisteEintrag({
    required this.rang,
    required this.userId,
    required this.username,
    required this.distanceKm,
    required this.xp,
    required this.sessionCount,
    required this.istIch,
    this.avatarUrl,
  });

  final int rang;
  final String userId;
  final String username;
  final String? avatarUrl;
  final double distanceKm;
  final int xp;
  final int sessionCount;
  final bool istIch;

  static RanglisteEintrag? fromRow(Map<String, dynamic> r) {
    final userId = r['user_id']?.toString();
    if (userId == null) return null;
    return RanglisteEintrag(
      rang: (r['rang'] as num?)?.toInt() ?? 0,
      userId: userId,
      username: (r['username'] as String?)?.trim().isNotEmpty == true
          ? (r['username'] as String).trim()
          : 'Fahrer',
      avatarUrl: r['avatar_url'] as String?,
      distanceKm: (r['distance_km'] as num?)?.toDouble() ?? 0,
      xp: (r['xp'] as num?)?.toInt() ?? 0,
      sessionCount: (r['session_count'] as num?)?.toInt() ?? 0,
      istIch: r['is_me'] == true,
    );
  }
}

class Rangliste {
  const Rangliste({required this.zeitraum, required this.top, this.ich});

  final RanglisteZeitraum zeitraum;

  /// Die besten N (aufsteigend nach Rang).
  final List<RanglisteEintrag> top;

  /// Die eigene Zeile — auch dann, wenn sie in [top] enthalten ist; null,
  /// wenn im Zeitraum noch nichts gefahren wurde.
  final RanglisteEintrag? ich;

  bool get ichInTop => ich != null && top.any((e) => e.userId == ich!.userId);

  /// Reine Sortierung/Trennung — testbar ohne Netz.
  static Rangliste ausZeilen(
    RanglisteZeitraum zeitraum,
    List<Map<String, dynamic>> rows, {
    int limit = 3,
  }) {
    final eintraege = rows
        .map(RanglisteEintrag.fromRow)
        .whereType<RanglisteEintrag>()
        .toList()
      ..sort((a, b) => a.rang.compareTo(b.rang));
    RanglisteEintrag? ich;
    for (final e in eintraege) {
      if (e.istIch) ich = e;
    }
    final top = eintraege.where((e) => e.rang <= limit).toList();
    return Rangliste(zeitraum: zeitraum, top: top, ich: ich);
  }
}

class RanglisteService {
  RanglisteService._();
  static final RanglisteService instance = RanglisteService._();

  static const Duration _cacheDauer = Duration(minutes: 3);
  final Map<RanglisteZeitraum, (DateTime, Rangliste)> _cache = {};

  Future<Rangliste?> lade(
    RanglisteZeitraum zeitraum, {
    int limit = 3,
    bool frisch = false,
  }) async {
    final c = _cache[zeitraum];
    if (!frisch && c != null && DateTime.now().difference(c.$1) < _cacheDauer) {
      return c.$2;
    }
    try {
      final data = await Supabase.instance.client.rpc(
        'get_rangliste',
        params: {'p_zeitraum': zeitraum.rpcWert, 'p_limit': limit},
      );
      final rows = (data as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      final r = Rangliste.ausZeilen(zeitraum, rows, limit: limit);
      _cache[zeitraum] = (DateTime.now(), r);
      return r;
    } catch (e) {
      debugPrint('[Rangliste] laden fehlgeschlagen: $e');
      return c?.$2;
    }
  }

  void leeren() => _cache.clear();
}
