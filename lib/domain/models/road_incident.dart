import 'package:flutter/material.dart';

/// 2026-07-24 (vucko "+-Button"): Typ einer Crowd-Verkehrsmeldung.
enum RoadIncidentType {
  unfall,
  baustelle,
  stau;

  /// Lebensdauer pro Typ (Waze/Google-Recherche, konservativ): Unfälle sind
  /// meist in 1-2h geräumt, Baustellen bleiben tagelang, Stau löst sich am
  /// schnellsten auf.
  Duration get ttl => switch (this) {
    RoadIncidentType.unfall => const Duration(hours: 2),
    RoadIncidentType.baustelle => const Duration(hours: 24),
    RoadIncidentType.stau => const Duration(minutes: 45),
  };

  String get label => switch (this) {
    RoadIncidentType.unfall => 'Unfall',
    RoadIncidentType.baustelle => 'Baustelle',
    RoadIncidentType.stau => 'Stau',
  };

  IconData get icon => switch (this) {
    RoadIncidentType.unfall => Icons.car_crash_rounded,
    RoadIncidentType.baustelle => Icons.construction_rounded,
    RoadIncidentType.stau => Icons.traffic_rounded,
  };

  Color get color => switch (this) {
    RoadIncidentType.unfall => const Color(0xFFEF4444),
    RoadIncidentType.baustelle => const Color(0xFFFF9500),
    RoadIncidentType.stau => const Color(0xFFFBBF24),
  };

  static RoadIncidentType fromDb(String value) => switch (value) {
    'unfall' => RoadIncidentType.unfall,
    'baustelle' => RoadIncidentType.baustelle,
    _ => RoadIncidentType.stau,
  };
}

/// Spiegelt eine Zeile aus `road_incidents` (siehe Migration
/// 20260724120000_road_incidents.sql). Strukturell an [ConstructionReport]
/// angelehnt — bewusst eigenes Model, weil Lebenszyklus (TTL + Votes) und
/// Typen abweichen.
class RoadIncident {
  final String id;
  final RoadIncidentType type;
  final double latitude;
  final double longitude;
  final String? reportedBy;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int confirmedCount;
  final int dismissedCount;
  final bool active;
  final double? jamEndLat;
  final double? jamEndLng;

  const RoadIncident({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    required this.expiresAt,
    required this.confirmedCount,
    required this.dismissedCount,
    required this.active,
    this.reportedBy,
    this.jamEndLat,
    this.jamEndLng,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  factory RoadIncident.fromJson(Map<String, dynamic> json) {
    return RoadIncident(
      id: json['id'] as String,
      type: RoadIncidentType.fromDb(json['type'] as String),
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      reportedBy: json['reported_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
      confirmedCount: (json['confirmed_count'] as num?)?.toInt() ?? 1,
      dismissedCount: (json['dismissed_count'] as num?)?.toInt() ?? 0,
      active: json['active'] as bool? ?? true,
      jamEndLat: (json['jam_end_lat'] as num?)?.toDouble(),
      jamEndLng: (json['jam_end_lng'] as num?)?.toDouble(),
    );
  }
}
