import 'dart:math' as math;
import 'package:geolocator/geolocator.dart' as geo;

/// Fortgeschrittener GPS-Smoother für Web-Plattformen.
///
/// Nutzt einen vereinfachten Kalman-artigen Filter mit Velocity-Prediction:
/// 1. Position wird anhand der letzten Geschwindigkeit vorhergesagt (Prediction)
/// 2. GPS-Messung wird mit Accuracy gewichtet eingerechnet (Correction)
/// 3. Heading wird aus Bewegungsrichtung berechnet (Browser liefert kein brauchbares)
/// 4. Zwischen GPS-Updates wird die Position per Timer interpoliert
class WebPositionSmoother {
  WebPositionSmoother({
    this.minMovementMeters = 1.5,
    this.maxJumpMeters = 500.0,
    this.minHeadingDistanceMeters = 3.0,
    this.headingSmoothingFactor = 0.3,
    this.processNoise = 2.0,
  });

  /// Minimale Distanz für Rebuild-Trigger (in Metern).
  final double minMovementMeters;

  /// Maximale akzeptierte Distanz zwischen Updates (darüber: Reset/Teleport).
  final double maxJumpMeters;

  /// Minimale Distanz für Heading-Berechnung (unter diesem Wert: GPS-Jitter).
  final double minHeadingDistanceMeters;

  /// Smoothing-Faktor für Heading (0–1, höher = reaktiver).
  final double headingSmoothingFactor;

  /// Prozessrauschen für den Kalman-Filter (höher = vertraut GPS mehr).
  final double processNoise;

  // ── Kalman State ──────────────────────────────────────────────────────────
  double? _lat;
  double? _lng;
  double _vLat = 0.0; // Geschwindigkeit in Breitengrad/Sekunde
  double _vLng = 0.0; // Geschwindigkeit in Längengrad/Sekunde
  double _pLat = 10.0; // Unsicherheit Position Lat
  double _pLng = 10.0; // Unsicherheit Position Lng
  double _pvLat = 10.0; // Unsicherheit Velocity Lat
  double _pvLng = 10.0; // Unsicherheit Velocity Lng
  DateTime? _lastTimestamp;

  // ── Heading State ─────────────────────────────────────────────────────────
  double _smoothedHeading = 0.0;
  bool _hasValidHeading = false;
  double? _lastHeadingLat;
  double? _lastHeadingLng;

  // ── Output ────────────────────────────────────────────────────────────────
  geo.Position? _lastOutput;

  /// Aktuell geglättete Position (null vor erstem Update).
  geo.Position? get current => _lastOutput;

  /// Geglättetes Heading in Grad (0–360, Nord=0).
  double get heading => _smoothedHeading;

  /// Ob bereits ein valides Heading berechnet wurde.
  bool get hasValidHeading => _hasValidHeading;

  /// Aktuelle geglättete Latitude (für Animation).
  double get lat => _lat ?? 0.0;

  /// Aktuelle geglättete Longitude (für Animation).
  double get lng => _lng ?? 0.0;

  /// Aktuelle Velocity in lat/s (für Prediction bei Animation).
  double get velocityLat => _vLat;

  /// Aktuelle Velocity in lng/s (für Prediction bei Animation).
  double get velocityLng => _vLng;

  /// Verarbeitet eine neue rohe GPS-Position.
  /// Gibt die geglättete Position zurück, oder `null` wenn kein Rebuild nötig.
  geo.Position? update(geo.Position raw) {
    final now = raw.timestamp;

    // ── Heading aus Positionsverlauf berechnen ──────────────────────────────
    _updateHeading(raw);

    // ── Erster Wert: State initialisieren ───────────────────────────────────
    if (_lat == null || _lastTimestamp == null) {
      _lat = raw.latitude;
      _lng = raw.longitude;
      _vLat = 0.0;
      _vLng = 0.0;
      _lastTimestamp = now;
      _lastOutput = _buildPosition(raw, _lat!, _lng!);
      return _lastOutput;
    }

    // ── Delta-Time berechnen ────────────────────────────────────────────────
    final dt = now.difference(_lastTimestamp!).inMilliseconds / 1000.0;
    if (dt <= 0) return null; // Doppeltes Event ignorieren
    _lastTimestamp = now;

    // ── Teleport-Check ──────────────────────────────────────────────────────
    final jumpDist = geo.Geolocator.distanceBetween(
      _lat!, _lng!, raw.latitude, raw.longitude,
    );
    if (jumpDist > maxJumpMeters) {
      _lat = raw.latitude;
      _lng = raw.longitude;
      _vLat = 0.0;
      _vLng = 0.0;
      _pLat = 10.0;
      _pLng = 10.0;
      _pvLat = 10.0;
      _pvLng = 10.0;
      _lastOutput = _buildPosition(raw, _lat!, _lng!);
      return _lastOutput;
    }

    // ════════════════════════════════════════════════════════════════════════
    // KALMAN PREDICT: Position anhand Velocity vorhersagen
    // ════════════════════════════════════════════════════════════════════════
    final predictedLat = _lat! + _vLat * dt;
    final predictedLng = _lng! + _vLng * dt;

    // Unsicherheit wächst mit der Zeit (Prozessrauschen)
    final q = processNoise * dt * dt;
    _pLat += q + _pvLat * dt * dt;
    _pLng += q + _pvLng * dt * dt;
    _pvLat += q * 0.5;
    _pvLng += q * 0.5;

    // ════════════════════════════════════════════════════════════════════════
    // KALMAN UPDATE: GPS-Messung einrechnen (gewichtet nach Accuracy)
    // ════════════════════════════════════════════════════════════════════════
    // Messrauschen: accuracy in Meter → in Grad umrechnen (grobe Näherung)
    final accuracyDeg = (raw.accuracy.isFinite && raw.accuracy > 0)
        ? raw.accuracy / 111_000.0 // ~111km pro Grad
        : 0.0001; // Fallback ~11m
    final rLat = accuracyDeg * accuracyDeg;
    final rLng = rLat;

    // Kalman Gain: wie viel vertrauen wir der Messung?
    final kLat = _pLat / (_pLat + rLat);
    final kLng = _pLng / (_pLng + rLng);

    // Position korrigieren
    _lat = predictedLat + kLat * (raw.latitude - predictedLat);
    _lng = predictedLng + kLng * (raw.longitude - predictedLng);

    // Velocity aus Innovation ableiten (wie stark weicht GPS von Prediction ab)
    if (dt > 0.05) {
      final kvLat = _pvLat / (_pvLat + rLat * 2);
      final kvLng = _pvLng / (_pvLng + rLng * 2);
      final innovLat = raw.latitude - predictedLat;
      final innovLng = raw.longitude - predictedLng;
      _vLat = _vLat + kvLat * (innovLat / dt - _vLat) * 0.5;
      _vLng = _vLng + kvLng * (innovLng / dt - _vLng) * 0.5;
      _pvLat *= (1 - kvLat);
      _pvLng *= (1 - kvLng);
    }

    // Unsicherheit nach Update reduzieren
    _pLat *= (1 - kLat);
    _pLng *= (1 - kLng);

    // ════════════════════════════════════════════════════════════════════════
    // Output: Rebuild nur wenn sichtbare Bewegung
    // ════════════════════════════════════════════════════════════════════════
    final prev = _lastOutput;
    if (prev != null) {
      final movedMeters = geo.Geolocator.distanceBetween(
        prev.latitude, prev.longitude, _lat!, _lng!,
      );
      if (movedMeters < minMovementMeters) {
        return null; // Zu wenig Bewegung → kein visuelles Update
      }
    }

    _lastOutput = _buildPosition(raw, _lat!, _lng!);
    return _lastOutput;
  }

  /// Gibt eine vorhergesagte Position für den Zeitpunkt `now` zurück,
  /// basierend auf dem letzten Kalman-State + Velocity.
  /// Für smooth Animation zwischen GPS-Updates.
  ({double lat, double lng, double heading}) predict(DateTime now) {
    if (_lat == null || _lastTimestamp == null) {
      return (lat: 0.0, lng: 0.0, heading: _smoothedHeading);
    }
    final dt = now.difference(_lastTimestamp!).inMilliseconds / 1000.0;
    // Prediction maximal 2 Sekunden voraus (danach zu ungenau)
    final clampedDt = dt.clamp(0.0, 2.0);
    return (
      lat: _lat! + _vLat * clampedDt,
      lng: _lng! + _vLng * clampedDt,
      heading: _smoothedHeading,
    );
  }

  /// Setzt den Smoother zurück (z.B. bei Navigation-Start).
  void reset() {
    _lat = null;
    _lng = null;
    _vLat = 0.0;
    _vLng = 0.0;
    _pLat = 10.0;
    _pLng = 10.0;
    _pvLat = 10.0;
    _pvLng = 10.0;
    _lastTimestamp = null;
    _smoothedHeading = 0.0;
    _hasValidHeading = false;
    _lastHeadingLat = null;
    _lastHeadingLng = null;
    _lastOutput = null;
  }

  // ── Heading-Berechnung ───────────────────────────────────────────────────

  void _updateHeading(geo.Position raw) {
    final prevLat = _lastHeadingLat;
    final prevLng = _lastHeadingLng;

    if (prevLat == null || prevLng == null) {
      _lastHeadingLat = raw.latitude;
      _lastHeadingLng = raw.longitude;
      // Browser-Heading als Fallback nutzen (falls brauchbar)
      final bh = raw.heading;
      if (bh.isFinite && bh > 0 && bh < 360) {
        _smoothedHeading = bh;
        _hasValidHeading = true;
      }
      return;
    }

    final distance = geo.Geolocator.distanceBetween(
      prevLat, prevLng, raw.latitude, raw.longitude,
    );

    if (distance >= minHeadingDistanceMeters) {
      final computed = _calculateBearing(
        prevLat, prevLng, raw.latitude, raw.longitude,
      );

      if (_hasValidHeading) {
        _smoothedHeading = _lerpAngle(
          _smoothedHeading, computed, headingSmoothingFactor,
        );
      } else {
        _smoothedHeading = computed;
        _hasValidHeading = true;
      }

      _lastHeadingLat = raw.latitude;
      _lastHeadingLng = raw.longitude;
    }
  }

  double _calculateBearing(double lat1, double lng1, double lat2, double lng2) {
    final lat1R = lat1 * math.pi / 180;
    final lat2R = lat2 * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2R);
    final x = math.cos(lat1R) * math.sin(lat2R) -
        math.sin(lat1R) * math.cos(lat2R) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  double _lerpAngle(double from, double to, double t) {
    var diff = (to - from) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return (from + diff * t) % 360;
  }

  geo.Position _buildPosition(geo.Position raw, double lat, double lng) {
    return geo.Position(
      latitude: lat,
      longitude: lng,
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
  }
}
