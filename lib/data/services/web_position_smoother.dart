import 'dart:math' as math;
import 'package:geolocator/geolocator.dart' as geo;

/// Glättet GPS-Positionen auf Web-Plattformen mittels exponentieller Gewichtung
/// und berechnet Heading aus aufeinanderfolgenden Positionen.
///
/// Browser-Geolocation liefert oft kein brauchbares Heading (0 oder NaN).
/// Dieser Smoother berechnet die Fahrtrichtung selbst aus der Positionshistorie
/// und interpoliert Position + Heading für flüssige Darstellung.
class WebPositionSmoother {
  WebPositionSmoother({
    this.positionAlpha = 0.35,
    this.headingAlpha = 0.25,
    this.minMovementMeters = 2.0,
    this.maxJumpMeters = 500.0,
    this.minHeadingDistanceMeters = 3.0,
  });

  /// Gewichtungsfaktor für neue Position (0–1). Höher = reaktiver, niedriger = glatter.
  final double positionAlpha;

  /// Gewichtungsfaktor für neues Heading (0–1).
  final double headingAlpha;

  /// Minimale Distanz in Metern, ab der ein Update als "echte Bewegung" gilt.
  final double minMovementMeters;

  /// Maximale Distanz, bei der ein Sprung akzeptiert wird (darüber: Reset).
  final double maxJumpMeters;

  /// Minimale Distanz zwischen zwei Positionen, ab der ein neues Heading berechnet wird.
  /// Verhindert Heading-Flackern bei GPS-Jitter im Stillstand.
  final double minHeadingDistanceMeters;

  geo.Position? _smoothedPosition;
  double _smoothedHeading = 0.0;
  bool _hasValidHeading = false;

  // Letzte Position für Heading-Berechnung (ungeglättet, für korrekte Richtung)
  double? _lastRawLat;
  double? _lastRawLng;

  /// Gibt die aktuell geglättete Position zurück (oder null vor dem ersten Update).
  geo.Position? get current => _smoothedPosition;

  /// Gibt das geglättete Heading zurück.
  double get heading => _smoothedHeading;

  /// Ob bereits ein valides Heading berechnet wurde.
  bool get hasValidHeading => _hasValidHeading;

  /// Verarbeitet eine neue rohe GPS-Position und gibt die geglättete zurück.
  /// Gibt `null` zurück, wenn das Update zu klein ist und kein Rebuild nötig.
  geo.Position? update(geo.Position raw) {
    final prev = _smoothedPosition;

    // Heading aus Positions-Differenz berechnen (zuverlässiger als Browser-Heading)
    _updateComputedHeading(raw);

    // Erster Wert: direkt übernehmen
    if (prev == null) {
      _smoothedPosition = _withHeading(raw, _smoothedHeading);
      return _smoothedPosition;
    }

    final distance = geo.Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      raw.latitude,
      raw.longitude,
    );

    // Sprung zu groß (Teleport/GPS-Reset) → Position direkt übernehmen
    if (distance > maxJumpMeters) {
      _smoothedPosition = _withHeading(raw, _smoothedHeading);
      return _smoothedPosition;
    }

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
    _hasValidHeading = false;
    _lastRawLat = null;
    _lastRawLng = null;
  }

  // ── Heading-Berechnung ───────────────────────────────────────────────────

  /// Berechnet das Heading aus der Differenz zwischen aktueller und letzter Position.
  /// Nutzt die rohen (ungeglätteten) Koordinaten für korrekte Richtung.
  void _updateComputedHeading(geo.Position raw) {
    final prevLat = _lastRawLat;
    final prevLng = _lastRawLng;

    if (prevLat == null || prevLng == null) {
      _lastRawLat = raw.latitude;
      _lastRawLng = raw.longitude;
      // Beim ersten Punkt: Browser-Heading als Fallback nutzen (falls brauchbar)
      final browserHeading = raw.heading;
      if (browserHeading.isFinite && browserHeading > 0 && browserHeading < 360) {
        _smoothedHeading = browserHeading;
        _hasValidHeading = true;
      }
      return;
    }

    final distance = geo.Geolocator.distanceBetween(
      prevLat, prevLng, raw.latitude, raw.longitude,
    );

    // Nur Heading berechnen wenn genug Distanz zurückgelegt (sonst GPS-Jitter)
    if (distance >= minHeadingDistanceMeters) {
      final computedHeading = _calculateBearing(
        prevLat, prevLng, raw.latitude, raw.longitude,
      );

      if (_hasValidHeading) {
        // Bestehendes Heading smooth interpolieren
        _smoothedHeading = _lerpAngle(_smoothedHeading, computedHeading, headingAlpha);
      } else {
        // Erstes valides Heading: direkt übernehmen
        _smoothedHeading = computedHeading;
        _hasValidHeading = true;
      }

      _lastRawLat = raw.latitude;
      _lastRawLng = raw.longitude;
    }
  }

  /// Berechnet den Bearing (Richtung) von Punkt A nach Punkt B in Grad (0–360, Nord=0).
  double _calculateBearing(double lat1, double lng1, double lat2, double lng2) {
    final lat1Rad = lat1 * math.pi / 180;
    final lat2Rad = lat2 * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;

    final y = math.sin(dLng) * math.cos(lat2Rad);
    final x = math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLng);

    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360; // Normalisieren auf 0–360
  }

  /// Position mit überschriebenem Heading zurückgeben.
  geo.Position _withHeading(geo.Position p, double heading) {
    return geo.Position(
      latitude: p.latitude,
      longitude: p.longitude,
      timestamp: p.timestamp,
      accuracy: p.accuracy,
      altitude: p.altitude,
      altitudeAccuracy: p.altitudeAccuracy,
      heading: heading,
      headingAccuracy: p.headingAccuracy,
      speed: p.speed,
      speedAccuracy: p.speedAccuracy,
      floor: p.floor,
      isMocked: p.isMocked,
    );
  }

  /// Zirkuläre lineare Interpolation für Winkel (0–360°).
  double _lerpAngle(double from, double to, double t) {
    var diff = (to - from) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return (from + diff * t) % 360;
  }
}
