import 'package:geolocator/geolocator.dart' as geo;

/// Glättet GPS-Positionen auf Web-Plattformen mittels exponentieller Gewichtung.
///
/// Browser-Geolocation liefert oft sprunghaftere Werte als native GPS-Chips.
/// Dieser Smoother interpoliert Position und Heading, sodass die Darstellung
/// auf der Karte flüssig wie bei Apple Maps wirkt.
class WebPositionSmoother {
  WebPositionSmoother({
    this.positionAlpha = 0.35,
    this.headingAlpha = 0.25,
    this.minMovementMeters = 2.0,
    this.maxJumpMeters = 500.0,
  });

  /// Gewichtungsfaktor für neue Position (0–1). Höher = reaktiver, niedriger = glatter.
  final double positionAlpha;

  /// Gewichtungsfaktor für neues Heading (0–1).
  final double headingAlpha;

  /// Minimale Distanz in Metern, ab der ein Update als "echte Bewegung" gilt.
  final double minMovementMeters;

  /// Maximale Distanz, bei der ein Sprung akzeptiert wird (darüber: Reset).
  final double maxJumpMeters;

  geo.Position? _smoothedPosition;
  double _smoothedHeading = 0.0;

  /// Gibt die aktuell geglättete Position zurück (oder null vor dem ersten Update).
  geo.Position? get current => _smoothedPosition;

  /// Gibt das geglättete Heading zurück.
  double get heading => _smoothedHeading;

  /// Verarbeitet eine neue rohe GPS-Position und gibt die geglättete zurück.
  /// Gibt `null` zurück, wenn das Update zu klein ist und kein Rebuild nötig.
  geo.Position? update(geo.Position raw) {
    final prev = _smoothedPosition;

    // Erster Wert: direkt übernehmen
    if (prev == null) {
      _smoothedPosition = raw;
      _smoothedHeading = _validHeading(raw.heading);
      return raw;
    }

    final distance = geo.Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      raw.latitude,
      raw.longitude,
    );

    // Sprung zu groß (Teleport/GPS-Reset) → Position direkt übernehmen
    if (distance > maxJumpMeters) {
      _smoothedPosition = raw;
      _smoothedHeading = _validHeading(raw.heading);
      return raw;
    }

    // Heading glätten (zirkulär, damit 359°→1° korrekt interpoliert)
    final rawHeading = _validHeading(raw.heading);
    _smoothedHeading = _lerpAngle(_smoothedHeading, rawHeading, headingAlpha);

    // Position glätten
    final smoothLat = prev.latitude + (raw.latitude - prev.latitude) * positionAlpha;
    final smoothLng = prev.longitude + (raw.longitude - prev.longitude) * positionAlpha;

    final smoothed = geo.Position(
      latitude: smoothLat,
      longitude: smoothLng,
      timestamp: raw.timestamp,
      accuracy: raw.accuracy,
      altitude: raw.altitude,
      altitudeAccuracy: raw.altitudeAccuracy,
      heading: _smoothedHeading,
      headingAccuracy: raw.headingAccuracy,
      speed: raw.speed,
      speedAccuracy: raw.speedAccuracy,
      floor: raw.floor,
      isMocked: raw.isMocked,
    );
    _smoothedPosition = smoothed;

    // Unter Mindest-Bewegung: kein visuelles Update nötig
    final movedMeters = geo.Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      smoothLat,
      smoothLng,
    );
    if (movedMeters < minMovementMeters) {
      return null; // Signal: kein Rebuild nötig
    }

    return smoothed;
  }

  /// Setzt den Smoother zurück (z.B. bei Navigation-Start).
  void reset() {
    _smoothedPosition = null;
    _smoothedHeading = 0.0;
  }

  // ── Hilfsfunktionen ──────────────────────────────────────────────────────

  double _validHeading(double heading) {
    if (!heading.isFinite || heading < 0 || heading > 360) return _smoothedHeading;
    return heading;
  }

  /// Zirkuläre lineare Interpolation für Winkel (0–360°).
  double _lerpAngle(double from, double to, double t) {
    var diff = (to - from) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return (from + diff * t) % 360;
  }
}
