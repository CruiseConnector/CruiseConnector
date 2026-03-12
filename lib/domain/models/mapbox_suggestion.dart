/// Mapbox Geocoding Vorschlag für Autocomplete
class MapboxSuggestion {
  const MapboxSuggestion({
    required this.placeName,
    required this.coordinates,
    this.context,
  });

  final String placeName;
  final List<double> coordinates; // [longitude, latitude]
  final String? context;

  double get longitude => coordinates[0];
  double get latitude => coordinates[1];
}

/// Wegpunkt-Typ für Haltestop vs normaler Wegpunkt
enum WaypointType {
  normal, // Einfache Durchfahrt
  stop, // Haltestop - Route pausiert
}

/// Ein Wegpunkt mit Typ für die Routenplanung
class RouteWaypoint {
  const RouteWaypoint({
    required this.latitude,
    required this.longitude,
    this.type = WaypointType.normal,
    this.name,
  });

  final double latitude;
  final double longitude;
  final WaypointType type;
  final String? name;

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'type': type == WaypointType.stop ? 'stop' : 'normal',
    if (name != null) 'name': name,
  };
}
