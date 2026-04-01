import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart' as geo;

/// GPS-Smoother für iOS/Android mit Kalman-Filter und Heading-Fusion.
///
/// Äquivalent zum WebPositionSmoother, aber optimiert für native Plattformen:
/// - Kalman-Filter für Position-Smoothing
/// - Heading-Berechnung aus Bewegungsverlauf (Fallback wenn GPS-Heading ungültig)
/// - Geschwindigkeitsabhängige Heading-Priorität (GPS vs Bewegung)
/// - Bearing-Interpolation für flüssige Rotation
/// - iOS-optimierte Parameter
class NativePositionSmoother {
  NativePositionSmoother({
    this.minMovementMeters = 1.5,
    this.maxJumpMeters = 500.0,
    this.minHeadingDistanceMeters = 3.0,
    this.headingSmoothingFactor = 0.45,
    this.processNoise = 1.8,
    this.stationaryNoiseMeters = 4.0,
    this.headingNoiseThresholdDegrees = 12.0,
    this.lowSpeedThresholdMs = 2.5,
    this.highSpeedThresholdMs = 8.0,
  });

  /// Minimale Distanz für Rebuild-Trigger.
  final double minMovementMeters;

  /// Maximale akzeptierte Distanz (darüber: Reset/Teleport).
  final double maxJumpMeters;

  /// Minimale Distanz für Heading-Berechnung aus Bewegung.
  final double minHeadingDistanceMeters;

  /// Smoothing-Faktor für Heading (0–1, höher = reaktiver).
  final double headingSmoothingFactor;

  /// Prozessrauschen für Kalman-Filter.
  final double processNoise;

  /// Unterhalb dieser Distanz gilt Update als Standrauschen.
  final double stationaryNoiseMeters;

  /// Unterhalb dieser Winkelabweichung wird Heading extra geglättet.
  final double headingNoiseThresholdDegrees;

  /// Unter dieser Geschwindigkeit (m/s) wird Bewegungs-Heading priorisiert.
  final double lowSpeedThresholdMs;

  /// Über dieser Geschwindigkeit (m/s) wird GPS-Heading priorisiert.
  final double highSpeedThresholdMs;

  // ── Kalman State ──────────────────────────────────────────────────────────
  double? _lat;
  double? _lng;
  double _vLat = 0.0;
  double _vLng = 0.0;
  double _pLat = 8.0;
  double _pLng = 8.0;
  double _pvLat = 8.0;
  double _pvLng = 8.0;
  DateTime? _lastTimestamp;
  double? _lastRawLat;
  double? _lastRawLng;

  // ── Heading State ─────────────────────────────────────────────────────────
  double _smoothedHeading = 0.0;
  double _movementHeading = 0.0;
  // ignore: unused_field - Reserviert für zukünftige Diagnostik
  double _lastGpsHeading = 0.0;
  bool _hasValidHeading = false;
  bool _hasValidMovementHeading = false;
  double? _lastHeadingLat;
  double? _lastHeadingLng;
  // ignore: unused_field - Reserviert für Heading-Timeout-Erkennung
  DateTime? _lastHeadingTime;

  // ── Speed State ───────────────────────────────────────────────────────────
  double _currentSpeed = 0.0;
  double _smoothedSpeed = 0.0;

  // ── Output ────────────────────────────────────────────────────────────────
  geo.Position? _lastOutput;

  /// Aktuell geglättete Position.
  geo.Position? get current => _lastOutput;

  /// Geglättetes Heading in Grad (0–360, Nord=0).
  double get heading => _smoothedHeading;

  /// Ob ein valides Heading vorliegt.
  bool get hasValidHeading => _hasValidHeading;

  /// Aktuelle geglättete Latitude.
  double get lat => _lat ?? 0.0;

  /// Aktuelle geglättete Longitude.
  double get lng => _lng ?? 0.0;

  /// Aktuelle Geschwindigkeit (m/s).
  double get speed => _smoothedSpeed;

  /// Velocity in lat/s für Prediction.
  double get velocityLat => _vLat;

  /// Velocity in lng/s für Prediction.
  double get velocityLng => _vLng;

  /// Verarbeitet eine neue GPS-Position.
  /// Gibt die geglättete Position zurück, oder null wenn kein Rebuild nötig.
  geo.Position? update(geo.Position raw) {
    if (kIsWeb) return raw; // Auf Web nicht verwenden

    final now = raw.timestamp;

    // Speed aktualisieren
    _updateSpeed(raw);

    // Heading aus GPS + Bewegung fusionieren
    _updateHeading(raw);

    // Erster Wert: State initialisieren
    if (_lat == null || _lastTimestamp == null) {
      _lat = raw.latitude;
      _lng = raw.longitude;
      _vLat = 0.0;
      _vLng = 0.0;
      _lastTimestamp = now;
      _lastRawLat = raw.latitude;
      _lastRawLng = raw.longitude;
      _lastOutput = _buildPosition(raw, _lat!, _lng!);
      return _lastOutput;
    }

    // Delta-Time berechnen
    final dt = now.difference(_lastTimestamp!).inMilliseconds / 1000.0;
    if (dt <= 0) return null;
    _lastTimestamp = now;

    final rawStepMeters = _lastRawLat != null && _lastRawLng != null
        ? geo.Geolocator.distanceBetween(
            _lastRawLat!,
            _lastRawLng!,
            raw.latitude,
            raw.longitude,
          )
        : double.infinity;

    // Teleport-Check
    final jumpDist = geo.Geolocator.distanceBetween(
      _lat!,
      _lng!,
      raw.latitude,
      raw.longitude,
    );
    if (jumpDist > maxJumpMeters || rawStepMeters > maxJumpMeters) {
      _resetState(raw);
      _lastOutput = _buildPosition(raw, _lat!, _lng!);
      return _lastOutput;
    }

    // Standrauschen unterdrücken
    if (rawStepMeters < stationaryNoiseMeters &&
        (raw.speed.isNaN || raw.speed < 1.0)) {
      _lastRawLat = raw.latitude;
      _lastRawLng = raw.longitude;
      // Bei Stillstand trotzdem Heading-Update erlauben (für Kompass-Rotation)
      if (_hasValidHeading) {
        _lastOutput = _buildPosition(raw, _lat!, _lng!);
        return _lastOutput;
      }
      return null;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // KALMAN PREDICT
    // ═══════════════════════════════════════════════════════════════════════
    final predictedLat = _lat! + _vLat * dt;
    final predictedLng = _lng! + _vLng * dt;

    final q = processNoise * dt * dt;
    _pLat += q + _pvLat * dt * dt;
    _pLng += q + _pvLng * dt * dt;
    _pvLat += q * 0.4;
    _pvLng += q * 0.4;

    // ═══════════════════════════════════════════════════════════════════════
    // KALMAN UPDATE
    // ═══════════════════════════════════════════════════════════════════════
    final accuracyDeg = (raw.accuracy.isFinite && raw.accuracy > 0)
        ? raw.accuracy / 111_000.0
        : 0.00008;
    final rLat = accuracyDeg * accuracyDeg;
    final rLng = rLat;

    final kLat = _pLat / (_pLat + rLat);
    final kLng = _pLng / (_pLng + rLng);

    _lat = predictedLat + kLat * (raw.latitude - predictedLat);
    _lng = predictedLng + kLng * (raw.longitude - predictedLng);

    // Velocity aus Innovation ableiten
    if (dt > 0.05) {
      final kvLat = _pvLat / (_pvLat + rLat * 1.5);
      final kvLng = _pvLng / (_pvLng + rLng * 1.5);
      final innovLat = raw.latitude - predictedLat;
      final innovLng = raw.longitude - predictedLng;
      _vLat = _vLat + kvLat * (innovLat / dt - _vLat) * 0.6;
      _vLng = _vLng + kvLng * (innovLng / dt - _vLng) * 0.6;
      _pvLat *= (1 - kvLat);
      _pvLng *= (1 - kvLng);
    }

    _pLat *= (1 - kLat);
    _pLng *= (1 - kLng);

    // ═══════════════════════════════════════════════════════════════════════
    // Output: Rebuild nur wenn sichtbare Bewegung
    // ═══════════════════════════════════════════════════════════════════════
    final prev = _lastOutput;
    if (prev != null) {
      final movedMeters = geo.Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        _lat!,
        _lng!,
      );
      // Bei schneller Bewegung häufiger updaten
      final effectiveMinMovement = _smoothedSpeed > highSpeedThresholdMs
          ? minMovementMeters * 0.5
          : minMovementMeters;
      if (movedMeters < effectiveMinMovement && !_hasValidHeading) {
        _lastRawLat = raw.latitude;
        _lastRawLng = raw.longitude;
        return null;
      }
    }

    _lastRawLat = raw.latitude;
    _lastRawLng = raw.longitude;
    _lastOutput = _buildPosition(raw, _lat!, _lng!);
    return _lastOutput;
  }

  /// Vorhersage für smooth Animation zwischen GPS-Updates.
  ({double lat, double lng, double heading}) predict(DateTime now) {
    if (_lat == null || _lastTimestamp == null) {
      return (lat: 0.0, lng: 0.0, heading: _smoothedHeading);
    }
    final dt = now.difference(_lastTimestamp!).inMilliseconds / 1000.0;
    final clampedDt = dt.clamp(0.0, 1.5);
    return (
      lat: _lat! + _vLat * clampedDt,
      lng: _lng! + _vLng * clampedDt,
      heading: _smoothedHeading,
    );
  }

  /// Setzt den Smoother zurück.
  void reset() {
    _lat = null;
    _lng = null;
    _vLat = 0.0;
    _vLng = 0.0;
    _pLat = 8.0;
    _pLng = 8.0;
    _pvLat = 8.0;
    _pvLng = 8.0;
    _lastTimestamp = null;
    _lastRawLat = null;
    _lastRawLng = null;
    _smoothedHeading = 0.0;
    _movementHeading = 0.0;
    _lastGpsHeading = 0.0;
    _hasValidHeading = false;
    _hasValidMovementHeading = false;
    _lastHeadingLat = null;
    _lastHeadingLng = null;
    _lastHeadingTime = null;
    _currentSpeed = 0.0;
    _smoothedSpeed = 0.0;
    _lastOutput = null;
  }

  // ── Heading-Fusion ───────────────────────────────────────────────────────

  void _updateHeading(geo.Position raw) {
    final gpsHeading = raw.heading;
    final hasGpsHeading = gpsHeading.isFinite &&
        gpsHeading >= 0 &&
        gpsHeading <= 360 &&
        raw.headingAccuracy.isFinite &&
        raw.headingAccuracy < 45; // Nur präzise GPS-Headings akzeptieren

    // GPS-Heading speichern wenn valide
    if (hasGpsHeading) {
      _lastGpsHeading = gpsHeading;
    }

    // Bewegungs-Heading berechnen
    _updateMovementHeading(raw);

    // ═══════════════════════════════════════════════════════════════════════
    // HEADING FUSION: Geschwindigkeitsabhängige Priorisierung
    // ═══════════════════════════════════════════════════════════════════════
    double targetHeading;
    double blendFactor;

    if (_smoothedSpeed < lowSpeedThresholdMs) {
      // Niedrige Geschwindigkeit / Stillstand:
      // → Bewegungs-Heading priorisieren (reagiert auf Drehung)
      // → GPS-Heading als Fallback
      if (_hasValidMovementHeading) {
        targetHeading = _movementHeading;
        blendFactor = 0.55; // Reaktiver bei niedriger Geschwindigkeit
      } else if (hasGpsHeading) {
        targetHeading = gpsHeading;
        blendFactor = 0.35;
      } else {
        return; // Kein gültiges Heading
      }
    } else if (_smoothedSpeed > highSpeedThresholdMs) {
      // Hohe Geschwindigkeit:
      // → GPS-Heading priorisieren (genauer bei Bewegung)
      if (hasGpsHeading) {
        targetHeading = gpsHeading;
        blendFactor = 0.50;
      } else if (_hasValidMovementHeading) {
        targetHeading = _movementHeading;
        blendFactor = 0.40;
      } else {
        return;
      }
    } else {
      // Mittlere Geschwindigkeit: Blend beide
      final speedFactor = (_smoothedSpeed - lowSpeedThresholdMs) /
          (highSpeedThresholdMs - lowSpeedThresholdMs);

      if (hasGpsHeading && _hasValidMovementHeading) {
        // Gewichteter Durchschnitt
        targetHeading = _lerpAngle(_movementHeading, gpsHeading, speedFactor);
        blendFactor = 0.45;
      } else if (hasGpsHeading) {
        targetHeading = gpsHeading;
        blendFactor = 0.40 + speedFactor * 0.15;
      } else if (_hasValidMovementHeading) {
        targetHeading = _movementHeading;
        blendFactor = 0.50 - speedFactor * 0.15;
      } else {
        return;
      }
    }

    // Heading-Noise filtern
    if (_hasValidHeading) {
      final headingDelta = _angleDelta(_smoothedHeading, targetHeading);
      // Sehr kleine Änderungen stärker glätten
      final effectiveBlend = headingDelta <= headingNoiseThresholdDegrees
          ? blendFactor * 0.6
          : blendFactor;
      _smoothedHeading = _lerpAngle(_smoothedHeading, targetHeading, effectiveBlend);
    } else {
      _smoothedHeading = targetHeading;
    }

    _hasValidHeading = true;
    _lastHeadingTime = DateTime.now();
  }

  void _updateMovementHeading(geo.Position raw) {
    final prevLat = _lastHeadingLat;
    final prevLng = _lastHeadingLng;

    if (prevLat == null || prevLng == null) {
      _lastHeadingLat = raw.latitude;
      _lastHeadingLng = raw.longitude;
      return;
    }

    final distance = geo.Geolocator.distanceBetween(
      prevLat,
      prevLng,
      raw.latitude,
      raw.longitude,
    );

    if (distance >= minHeadingDistanceMeters) {
      final computed = _calculateBearing(
        prevLat,
        prevLng,
        raw.latitude,
        raw.longitude,
      );

      if (_hasValidMovementHeading) {
        final headingDelta = _angleDelta(_movementHeading, computed);
        final blend = headingDelta <= headingNoiseThresholdDegrees
            ? headingSmoothingFactor * 0.55
            : headingSmoothingFactor;
        _movementHeading = _lerpAngle(_movementHeading, computed, blend);
      } else {
        _movementHeading = computed;
      }
      _hasValidMovementHeading = true;

      _lastHeadingLat = raw.latitude;
      _lastHeadingLng = raw.longitude;
    }
  }

  void _updateSpeed(geo.Position raw) {
    if (raw.speed.isFinite && raw.speed >= 0) {
      _currentSpeed = raw.speed;
      // Exponential smoothing für Speed
      _smoothedSpeed = _smoothedSpeed * 0.7 + _currentSpeed * 0.3;
    }
  }

  void _resetState(geo.Position raw) {
    _lat = raw.latitude;
    _lng = raw.longitude;
    _vLat = 0.0;
    _vLng = 0.0;
    _pLat = 8.0;
    _pLng = 8.0;
    _pvLat = 8.0;
    _pvLng = 8.0;
    _lastRawLat = raw.latitude;
    _lastRawLng = raw.longitude;
    _lastHeadingLat = raw.latitude;
    _lastHeadingLng = raw.longitude;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

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

  double _angleDelta(double from, double to) {
    final diff = (to - from).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
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
      speed: _smoothedSpeed,
      speedAccuracy: raw.speedAccuracy,
      floor: raw.floor,
      isMocked: raw.isMocked,
    );
  }
}
