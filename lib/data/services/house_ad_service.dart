import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Eine House-Ad-Kampagne (Eigen-/Direktvermarktung ohne Drittanbieter).
///
/// Quelle ist die Tabelle `house_ads` (nur aktive Kampagnen im Zeitfenster
/// sind per RLS lesbar). Bilder liegen auf dem eigenen CDN
/// (tiles.cruiseconnector.at) — kein AdMob, kein Tracking-SDK.
class HouseAd {
  const HouseAd({
    required this.id,
    required this.imageUrl,
    this.headline,
    this.body,
    this.ctaLabel,
    this.targetUrl,
    this.advertiser,
    this.weight = 1,
  });

  final String id;
  final String imageUrl;
  final String? headline;
  final String? body;
  final String? ctaLabel;
  final String? targetUrl;
  final String? advertiser;
  final int weight;

  static HouseAd fromMap(Map<String, dynamic> m) => HouseAd(
    id: m['id'] as String,
    imageUrl: m['image_url'] as String,
    headline: m['headline'] as String?,
    body: m['body'] as String?,
    ctaLabel: m['cta_label'] as String?,
    targetUrl: m['target_url'] as String?,
    advertiser: m['advertiser'] as String?,
    weight: (m['weight'] as num?)?.toInt() ?? 1,
  );
}

class HouseAdService {
  static SupabaseClient get _db => Supabase.instance.client;

  /// Aktive Kampagnen für ein Placement, gewichtete Zufalls-Reihenfolge
  /// (weight 2 erscheint doppelt so oft vorn wie weight 1).
  static Future<List<HouseAd>> getAds({
    String placement = 'discover_feed',
  }) async {
    try {
      final rows = await _db
          .from('house_ads')
          .select(
            'id, image_url, headline, body, cta_label, target_url, advertiser, weight',
          )
          .eq('placement', placement);
      final ads = (rows as List)
          .whereType<Map<String, dynamic>>()
          .map(HouseAd.fromMap)
          .toList();
      // Gewichtetes Mischen: jede Kampagne bekommt einen Zufallsscore,
      // skaliert mit ihrem Gewicht — einfach und ausreichend fair.
      final rand = math.Random();
      ads.sort(
        (a, b) => (rand.nextDouble() / math.max(b.weight, 1)).compareTo(
          rand.nextDouble() / math.max(a.weight, 1),
        ),
      );
      return ads;
    } catch (e) {
      // Werbung ist nie ein Fehlerfall — Feed funktioniert ohne weiter.
      debugPrint('[HouseAd] Laden fehlgeschlagen: $e');
      return const [];
    }
  }

  /// Impression/Klick zählen — fire and forget, blockiert nie die UI.
  static void track(String adId, String event) {
    _db
        .rpc(
          'house_ad_track',
          params: {'p_ad_id': adId, 'p_event': event},
        )
        .then((_) {}, onError: (Object e) {
          debugPrint('[HouseAd] track($event) fehlgeschlagen: $e');
        });
  }
}
