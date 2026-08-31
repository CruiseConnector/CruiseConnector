import 'package:cruise_connect/domain/models/saved_route.dart';

class UserDriveSession {
  const UserDriveSession({
    required this.id,
    required this.userId,
    required this.distanceKm,
    required this.durationSeconds,
    required this.xpAwarded,
    required this.completedAtEnd,
    required this.createdAt,
    this.routeId,
    this.routeStyle,
    this.routeType,
    this.routeFingerprint,
    this.source,
    this.topSpeedKmh,
    this.groupId,
    this.trackGeometry,
    this.photoUrl,
  });

  final String id;
  final String userId;
  final String? routeId;
  final double distanceKm;
  final int durationSeconds;
  final int xpAwarded;
  final bool completedAtEnd;
  final String? routeStyle;
  final String? routeType;
  final String? routeFingerprint;
  final String? source;
  final DateTime createdAt;
  // 2026-06-25 (vucko): Top-Speed der Fahrt (DB-Spalte top_speed_kmh, seit X3).
  // Für die Fahrt-Detailansicht. Kann null sein (alte Fahrten ohne Messung).
  final double? topSpeedKmh;
  // 2026-06-25 (vucko Routen-Detail-Page): Gruppen-Fahrt? (group_id gesetzt) →
  // die Detailseite zeigt dann Rangliste + Teilnehmer.
  final String? groupId;
  // 2026-06-25 (vucko Routen-Detail-Page): der GEFAHRENE Track als Liste von
  // [lng, lat]-Punkten (Mapbox-Format) → akkurate Routen-Darstellung wie Strava.
  // Null = alte Fahrt ohne aufgezeichneten Track.
  final List<List<double>>? trackGeometry;
  // 2026-06-25 (vucko Routen-Detail-Page): optionales Foto der Fahrt (Storage-URL).
  final String? photoUrl;

  bool get isGroupRide => groupId != null;

  /// Diese gefahrene Fahrt als speicherbare Strecke.
  ///
  /// 2026-09-01 (Vucko: „routen die man gefahren ist im nachhinein noch
  /// speichern kann"): Bis heute gab es dafuer genau EIN Zeitfenster — das
  /// Abschluss-Blatt direkt nach der Fahrt. Wer dort „Verwerfen" tippte oder
  /// wessen App vorher starb, hatte keinen zweiten Weg.
  ///
  /// Die Geometrie ist die GEFAHRENE Spur, nicht die geplante Route. Deshalb
  /// traegt sie ausdruecklich `driven_track` als Quelle: eine spaeter daraus
  /// gebaute Fremdfahrt soll wissen, dass sie einer echten Aufzeichnung folgt
  /// und keinem Routenvorschlag.
  ///
  /// Der geplante Fingerprint wird bewusst NICHT uebernommen. Eine gefahrene
  /// Spur ist nicht die geplante Route; sie als solche auszugeben wuerde die
  /// Duplikatserkennung belasten. Die Verbindung zur Fahrt laeuft ueber
  /// `source_route_id`.
  SavedRoute? alsSpeicherbareStrecke({String? name}) {
    final spur = trackGeometry;
    if (spur == null || spur.length < 2) return null;
    return SavedRoute(
      id: id,
      createdAt: createdAt,
      style: routeStyle ?? 'Standard',
      distanceKm: distanceKm,
      geometry: <String, dynamic>{
        'type': 'LineString',
        'coordinates': spur,
      },
      userId: userId,
      name: name,
      durationSeconds: durationSeconds.toDouble(),
      routeType: routeType ?? 'ROUND_TRIP',
      drivenKm: distanceKm,
      sourceRouteId: id,
      groupId: groupId,
      routeSource: 'driven_track',
      completedAtEnd: completedAtEnd,
      photoUrl: photoUrl,
      topSpeedKmh: topSpeedKmh,
      routeMeta: <String, dynamic>{
        'saved_route_source': 'gefahrene_fahrt',
        'drive_session_id': id,
        'route_source': 'driven_track',
        'geometry_source': 'gps_track',
        'final_geometry_source': 'gps_track',
        if (routeFingerprint != null && routeFingerprint!.isNotEmpty)
          'planned_route_fingerprint': routeFingerprint,
      },
    );
  }

  static List<List<double>>? _parseTrack(dynamic raw) {
    if (raw is! List) return null;
    final pts = <List<double>>[];
    for (final item in raw) {
      if (item is List && item.length >= 2) {
        final a = item[0];
        final b = item[1];
        if (a is num && b is num) pts.add([a.toDouble(), b.toDouble()]);
      }
    }
    return pts.length >= 2 ? pts : null;
  }

  factory UserDriveSession.fromJson(Map<String, dynamic> json) {
    return UserDriveSession(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      routeId: json['route_id'] as String?,
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      durationSeconds: (json['duration_seconds'] as num?)?.round() ?? 0,
      xpAwarded: (json['xp_awarded'] as num?)?.round() ?? 0,
      completedAtEnd: json['completed_at_end'] == true,
      routeStyle: json['route_style'] as String?,
      routeType: json['route_type'] as String?,
      routeFingerprint: json['route_fingerprint'] as String?,
      source: json['source'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      topSpeedKmh: (json['top_speed_kmh'] as num?)?.toDouble(),
      groupId: json['group_id'] as String?,
      trackGeometry: _parseTrack(json['track_geometry']),
      photoUrl: json['photo_url'] as String?,
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'user_id': userId,
      if (routeId != null) 'route_id': routeId,
      'distance_km': distanceKm,
      'duration_seconds': durationSeconds,
      'xp_awarded': xpAwarded,
      'completed_at_end': completedAtEnd,
      if (routeStyle != null) 'route_style': routeStyle,
      if (routeType != null) 'route_type': routeType,
      if (routeFingerprint != null) 'route_fingerprint': routeFingerprint,
      if (source != null) 'source': source,
      if (groupId != null) 'group_id': groupId,
      if (trackGeometry != null) 'track_geometry': trackGeometry,
      if (photoUrl != null) 'photo_url': photoUrl,
    };
  }
}
