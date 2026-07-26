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
  // 2026-06-13 (vucko Kamera-Abbiege-Ruckeln, Geräte-Video): geglättete
  // Winkelgeschwindigkeit (Grad/s) der Drehung. Damit kann predict() das
  // Heading zwischen den ~1Hz-GPS-Fixes pro Frame EXTRAPOLIEREN (Dead
  // Reckoning wie Position) — sonst sprang das Kamera-Ziel-Heading 1×/s und
  // die Drehung kam in Bursts (Ruckeln beim Abbiegen, auf Geraden unsichtbar).
  double _headingRateDegPerSec = 0.0;
  double _movementHeading = 0.0;
  // 2026-07-22 (vucko Re-Lock-Kamera): letztes VALIDES rohes GPS-Heading
  // (Gate: isFinite, 0-360, headingAccuracy<45) + Zeitstempel. Dient beim
  // Zentrieren als zuverlässiger Fallback, wenn keine Routen-Tangente da ist.
  double _lastGpsHeading = 0.0;
  DateTime? _lastGpsHeadingAt;
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

  /// 2026-07-22 (vucko Re-Lock-Kamera): letztes zuverlässiges rohes GPS-Heading
  /// (nur gesetzt, wenn das strenge Validitäts-Gate in [_updateHeading] galt).
  double get lastReliableGpsHeading => _lastGpsHeading;

  /// Ob [lastReliableGpsHeading] frisch genug ist, um beim Zentrieren als
  /// Fallback zu dienen (älter als 5s = Fahrsituation kann sich geändert haben).
  bool get hasRecentReliableGpsHeading {
    final at = _lastGpsHeadingAt;
    return at != null &&
        DateTime.now().difference(at) < const Duration(seconds: 5);
  }

  /// 2026-07-22 (vucko Re-Lock-Kamera, „300-400m verkehrt herum"): Setzt den
  /// kompletten Heading-Zustand HART auf [headingDeg]. Nötig beim Zentrieren/
  /// Navigations-Start: der EMA-Zustand (_smoothedHeading/_movementHeading)
  /// konnte während Stand-/Langsamfahrt-Phasen aus GPS-Jitter bis zu ~180°
  /// falsch geprägt sein und heilte sich danach nur über mehrere reale Fixe
  /// hinweg (= genau die beobachteten 300-400m Fahrstrecke). Position/Velocity
  /// und die Bewegungs-Anker (_lastHeadingLat/Lng) bleiben bewusst unberührt —
  /// nur die RICHTUNG wird auf den extern bestimmten, korrekten Wert gestellt.
  void snapHeading(double headingDeg) {
    if (!headingDeg.isFinite) return;
    var h = headingDeg % 360.0;
    if (h < 0) h += 360.0;
    _smoothedHeading = h;
    _movementHeading = h;
    _headingRateDegPerSec = 0.0;
    _hasValidHeading = true;
    _hasValidMovementHeading = true;
    _lastHeadingTime = DateTime.now();
  }

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
    // 2026-06-13 (vucko Kamera-Abbiege-Ruckeln): Heading pro Frame
    // EXTRAPOLIEREN (Dead Reckoning wie Position). Das Drehfeld wandert damit
    // kontinuierlich statt 1×/Fix zu springen → die Kamera-Rotation gleitet
    // beim Abbiegen. Extrapolations-dt eigener, kürzerer Clamp (1,0s): bei
    // langen GPS-Lücken nicht über die Kurve hinausdrehen.
    final headingDt = dt.clamp(0.0, 1.0);
    final predictedHeading =
        (_smoothedHeading + _headingRateDegPerSec * headingDt) % 360.0;
    return (
      lat: _lat! + _vLat * clampedDt,
      lng: _lng! + _vLng * clampedDt,
      heading: predictedHeading < 0 ? predictedHeading + 360.0 : predictedHeading,
    );
  }

  /// 2026-07-03 (vucko Async-nach-Resume): Setzt die Prediction-Baseline auf
  /// JETZT und stoppt die Dead-Reckoning-Extrapolation, OHNE Position/Heading zu
  /// verwerfen. Nötig beim App-Resume: der vsync-Ticker ruht im Hintergrund
  /// (Render friert ein), während der GPS-Stream weiterläuft und `_lastTimestamp`
  /// fortschreibt. Ohne Rebase spuckt `predict()` beim ersten Frame nach dem
  /// Resume die volle 1,5-s-Extrapolation aus → Puck/Linie springen. Nach
  /// `rebaseToNow()` liefert `predict(now)` exakt die letzte gute Position
  /// (clampedDt≈0, v=0); der nächste reale Fix übernimmt nahtlos.
  void rebaseToNow() {
    if (_lat == null) return;
    _lastTimestamp = DateTime.now();
    _vLat = 0.0;
    _vLng = 0.0;
    _headingRateDegPerSec = 0.0;
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
    _headingRateDegPerSec = 0.0;
    _movementHeading = 0.0;
    _lastGpsHeading = 0.0;
    _lastGpsHeadingAt = null;
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
    final hasGpsHeading =
        gpsHeading.isFinite &&
        gpsHeading >= 0 &&
        gpsHeading <= 360 &&
        raw.headingAccuracy.isFinite &&
        raw.headingAccuracy < 45; // Nur präzise GPS-Headings akzeptieren

    // GPS-Heading speichern wenn valide
    if (hasGpsHeading) {
      _lastGpsHeading = gpsHeading;
      _lastGpsHeadingAt = DateTime.now();
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
      final speedFactor =
          (_smoothedSpeed - lowSpeedThresholdMs) /
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

    // 2026-06-11 (vucko 1Hz-GPS-Fix): Die Blendfaktoren (0.35-0.55) wirken PRO
    // UPDATE und waren auf den 20-Hz-Fahrsimulator kalibriert (Konvergenz in
    // ~0,4s). Echtes GPS liefert ~1 Fix/s — gleiche Faktoren ergaben dort eine
    // ~2s-Zeitkonstante: in zuegigen Kurven hing Kamera-/Puck-Heading 20-30
    // Grad nach ("saegende" Drehung). Zeitnormierung: alphaEff so wählen,
    // dass die KONVERGENZ PRO ZEIT der 20-Hz-Kalibrierung entspricht
    // (alphaEff = 1-(1-alpha)^(dt/50ms)), gekappt bei 0.85, damit bei langen
    // Fix-Luecken der rohe GPS-Jitter nicht 1:1 durchschlaegt.
    final lastHeadingAt = _lastHeadingTime;
    if (lastHeadingAt != null) {
      final dtMs = DateTime.now().difference(lastHeadingAt).inMilliseconds;
      if (dtMs > 75) {
        final exponent = dtMs / 50.0;
        blendFactor = math.min(
          0.85,
          1.0 - math.pow(1.0 - blendFactor, exponent).toDouble(),
        );
      }
    }

    // Heading-Noise filtern
    if (_hasValidHeading) {
      final headingDelta = _angleDelta(_smoothedHeading, targetHeading);
      // Sehr kleine Änderungen stärker glätten
      final effectiveBlend = headingDelta <= headingNoiseThresholdDegrees
          ? blendFactor * 0.6
          : blendFactor;
      final previousHeading = _smoothedHeading;
      _smoothedHeading = _lerpAngle(
        _smoothedHeading,
        targetHeading,
        effectiveBlend,
      );
      // 2026-06-13 (vucko Kamera-Abbiege-Ruckeln): Winkelgeschwindigkeit aus
      // der tatsächlichen Heading-Änderung pro Zeit schätzen (signiert,
      // kürzester Weg), stark geglättet (1Hz-GPS ist rausch-anfällig) und auf
      // ±90°/s gedeckelt. predict() extrapoliert damit pro Frame.
      final lastAt = _lastHeadingTime;
      if (lastAt != null) {
        final dtSec = DateTime.now().difference(lastAt).inMilliseconds / 1000.0;
        if (dtSec > 0.04 && dtSec < 2.0) {
          final signedDelta = _signedAngleDelta(previousHeading, _smoothedHeading);
          final instRate = (signedDelta / dtSec).clamp(-90.0, 90.0);
          // EMA: ruhige, kontinuierliche Rate statt zappelnder Momentanwerte.
          _headingRateDegPerSec =
              _headingRateDegPerSec * 0.6 + instRate * 0.4;
        }
      } else {
        _headingRateDegPerSec = 0.0;
      }
    } else {
      _smoothedHeading = targetHeading;
      _headingRateDegPerSec = 0.0;
    }

    _hasValidHeading = true;
    _lastHeadingTime = DateTime.now();
  }

  /// Signierter Winkel-Unterschied (kürzester Weg) von [from] nach [to],
  /// Bereich (-180, 180]. Positiv = im Uhrzeigersinn.
  double _signedAngleDelta(double from, double to) {
    var d = (to - from) % 360.0;
    if (d > 180.0) d -= 360.0;
    if (d < -180.0) d += 360.0;
    return d;
  }

  void _updateMovementHeading(geo.Position raw) {
    final prevLat = _lastHeadingLat;
    final prevLng = _lastHeadingLng;

    if (prevLat == null || prevLng == null) {
      _lastHeadingLat = raw.latitude;
      _lastHeadingLng = raw.longitude;
      return;
    }

    // 2026-07-22 (vucko Re-Lock-Kamera): Bei ECHTEM Stillstand (OS meldet
    // ~0 m/s) sind Positions-Deltas reines GPS-Rauschen — eine daraus
    // berechnete „Bewegungsrichtung" ist Zufall (bis ~180° falsch) und hat
    // den EMA-Zustand an Ampeln/im Stand korrumpiert. Kein Update, Anker
    // bleibt stehen; sobald echte Bewegung einsetzt (speed >= 0.5), rechnet
    // der nächste Fix mit korrekter Richtung weiter.
    if (raw.speed.isFinite && raw.speed >= 0 && raw.speed < 0.5) {
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
      if (_lastTimestamp == null) {
        _smoothedSpeed = _currentSpeed;
        return;
      }
      // 2026-06-11 (vucko Real-GPS-Fix): Der alte Alpha-Wert 0.3 lief PRO
      // Update. Im 20-Hz-Simulator konvergierte Speed dadurch in <0.5s; echtes
      // iOS-GPS liefert oft nur 1 Hz, also hing _smoothedSpeed mehrere Sekunden
      // hinterher. Diese Speed begrenzt den Route-Render-Lock-Forward-Catchup,
      // wodurch Puck/Linie sichtbar hinter dem echten Fahrfortschritt bleiben
      // konnten. Alpha jetzt zeitnormiert auf die 50ms-Sim-Kalibrierung.
      final dtMs = raw.timestamp.difference(_lastTimestamp!).inMilliseconds;
      var alpha = 0.3;
      if (dtMs > 75) {
        alpha = math.min(
          0.9,
          1.0 - math.pow(1.0 - alpha, dtMs / 50.0).toDouble(),
        );
      }
      _smoothedSpeed += (_currentSpeed - _smoothedSpeed) * alpha;
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
    final x =
        math.cos(lat1R) * math.sin(lat2R) -
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
