/// 2026-05-28 (vucko Task #66): Baustellen-Report Model.
///
/// Spiegelt die Supabase-View `active_construction_reports`. Source kann
/// 'osm' (importiert aus OpenStreetMap highway=construction) oder 'crowd'
/// (User-Report während Fahrt) sein. Der Bayesian Score (0..1) gibt die
/// geschätzte Wahrscheinlichkeit zurück dass die Baustelle noch aktiv ist.
class ConstructionReport {
  final String id;
  final double latitude;
  final double longitude;
  final String? roadName;
  final String? roadRef;
  final String source; // 'osm' | 'crowd'
  final int? osmId;
  final String? osmType; // 'node' | 'way'
  final int confirmCount;
  final int dismissCount;
  final DateTime firstReportedAt;
  final DateTime? lastConfirmedAt;
  final double score; // Bayesian Beta-Score 0..1

  const ConstructionReport({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.source,
    required this.confirmCount,
    required this.dismissCount,
    required this.firstReportedAt,
    required this.score,
    this.roadName,
    this.roadRef,
    this.osmId,
    this.osmType,
    this.lastConfirmedAt,
  });

  bool get isCrowdReported => source == 'crowd';
  bool get isOsmImported => source == 'osm';

  /// Display-Label für Bottom-Sheet & Marker.
  String get displayLabel {
    if (roadName != null && roadName!.isNotEmpty) return roadName!;
    if (roadRef != null && roadRef!.isNotEmpty) return roadRef!;
    return 'Baustelle';
  }

  /// Trust-Indicator für UI: > 0.6 → hoch, 0.4-0.6 → mittel, < 0.4 → niedrig.
  ConstructionTrust get trust {
    if (score >= 0.65) return ConstructionTrust.high;
    if (score >= 0.4) return ConstructionTrust.medium;
    return ConstructionTrust.low;
  }

  factory ConstructionReport.fromJson(Map<String, dynamic> json) {
    return ConstructionReport(
      id: json['id'] as String,
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      roadName: json['road_name'] as String?,
      roadRef: json['road_ref'] as String?,
      source: json['source'] as String,
      osmId: (json['osm_id'] as num?)?.toInt(),
      osmType: json['osm_type'] as String?,
      confirmCount: (json['confirm_count'] as num?)?.toInt() ?? 0,
      dismissCount: (json['dismiss_count'] as num?)?.toInt() ?? 0,
      firstReportedAt:
          DateTime.parse(json['first_reported_at'] as String).toUtc(),
      lastConfirmedAt: json['last_confirmed_at'] != null
          ? DateTime.parse(json['last_confirmed_at'] as String).toUtc()
          : null,
      score: (json['score'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

enum ConstructionTrust { high, medium, low }
