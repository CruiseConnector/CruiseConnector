/// Eine gespeicherte Route aus der Supabase `routes` Tabelle.
class SavedRoute {
  const SavedRoute({
    required this.id,
    required this.createdAt,
    required this.style,
    required this.distanceKm,
    required this.geometry,
    this.name,
    this.durationSeconds,
    this.routeType,
    this.rating,
  });

  final String id;
  final DateTime createdAt;
  final String style;
  final double distanceKm;
  final Map<String, dynamic> geometry;
  final String? name;
  final double? durationSeconds;
  final String? routeType;
  final int? rating;

  factory SavedRoute.fromJson(Map<String, dynamic> json) {
    return SavedRoute(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      style: (json['style'] as String?) ?? 'Standard',
      distanceKm: (json['distance_actual'] as num?)?.toDouble() ?? 0.0,
      geometry: json['geometry'] is Map
          ? Map<String, dynamic>.from(json['geometry'] as Map)
          : const {},
      name: json['name'] as String?,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
      routeType: (json['route_type'] as String?) ?? 'ROUND_TRIP',
      rating: (json['rating'] as num?)?.toInt(),
    );
  }

  bool get isRoundTrip => routeType == 'ROUND_TRIP';

  /// Serialisiert die Route für den lokalen Cache (shared_preferences).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'style': style,
      'distance_actual': distanceKm,
      'geometry': geometry,
      'name': name,
      'duration_seconds': durationSeconds,
      'route_type': routeType,
      'rating': rating,
    };
  }

  /// Formatierte Distanz (z.B. "12,4 km").
  String get formattedDistance =>
      '${distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km';

  /// Formatierte Fahrtzeit (z.B. "1h 23m").
  String get formattedDuration {
    if (durationSeconds == null) return '--';
    final minutes = (durationSeconds! / 60).round();
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  /// Icon-Name für den Fahrstil.
  String get styleEmoji {
    switch (style) {
      case 'Kurvenjagd':
        return '🏔️';
      case 'Sport Mode':
        return '🏎️';
      case 'Abendrunde':
        return '🌙';
      case 'Entdecker':
        return '🧭';
      default:
        return '🛣️';
    }
  }
}
