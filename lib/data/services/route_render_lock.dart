import 'dart:math' as math;

import 'package:geolocator/geolocator.dart' as geo;

bool shouldHoldRouteRenderLock({
  required DateTime now,
  required DateTime? lastAcceptedAt,
  required DateTime? offRouteSince,
  required bool routeConfirmed,
  required bool overviewActive,
  required bool hasLock,
  Duration holdDuration = const Duration(milliseconds: 1500),
}) {
  if (!routeConfirmed || overviewActive || !hasLock) return false;
  if (lastAcceptedAt == null) return false;
  if (now.difference(lastAcceptedAt) > holdDuration) return false;

  if (offRouteSince != null && now.difference(offRouteSince) > holdDuration) {
    return false;
  }
  return true;
}

/// Projected on-route render position for the navigation puck/camera/route trim.
class RouteRenderLockProjection {
  const RouteRenderLockProjection({
    required this.distanceM,
    required this.segmentIndex,
    required this.lateralMeters,
    required this.point,
  });

  /// Monotonic distance along the route in meters.
  final double distanceM;

  /// Segment containing [point].
  final int segmentIndex;

  /// Perpendicular distance from input GPS/smoother point to the route.
  final double lateralMeters;

  /// Projected route point as [longitude, latitude].
  final List<double> point;
}

class _RouteSearchWindow {
  const _RouteSearchWindow(this.from, this.to);

  final int from;
  final int to;
}

class _ProjectionSearchResult {
  const _ProjectionSearchResult({
    required this.segment,
    required this.distanceM,
    required this.lateralMeters,
  });

  final int segment;
  final double distanceM;
  final double lateralMeters;
}

/// Stateful on-route projector used while navigation is active.
///
/// The lock intentionally advances monotonically and searches by route meters,
/// not by segment count. GraphHopper point density varies a lot between dense
/// turns and long rural segments; a segment-count window can visibly freeze the
/// puck/line sync on real 1 Hz GPS.
class RouteRenderLock {
  RouteRenderLock({
    this.lateralMaxMeters = 35.0,
    this.lateralReleaseMeters = 60.0,
    this.behindWindowMeters = 90.0,
    this.minAheadWindowMeters = 220.0,
    this.maxAheadWindowMeters = 760.0,
  });

  final double lateralMaxMeters;

  /// 2026-06-12 (vucko Geraete-Video Autobahn): Hysterese. GPS driftet auf
  /// Autobahnen 15-30m lateral (+ Parallelfahrbahn) — ein einzelnes hartes
  /// Gate liess den Lock dort staendig abreissen: der Puck sprang sichtbar
  /// zwischen "auf der Linie" und "frei daneben". Akquise bleibt streng
  /// ([lateralMaxMeters]); ein BESTEHENDER Lock haelt bis zu diesem Wert.
  final double lateralReleaseMeters;
  final double behindWindowMeters;
  final double minAheadWindowMeters;
  final double maxAheadWindowMeters;

  /// Max. Render-Geschwindigkeit im Schnell-Aufhol-Modus (m/s). Deckelt das
  /// exponentielle Aufholen, damit ein grosser validierter Re-Anchor pro
  /// 60fps-Frame nur ~7m fliegt (animiert) statt in einem Frame zu
  /// teleportieren.
  static const double _catchUpMaxMps = 450.0;

  List<List<double>>? _coordinates;
  List<double>? _cumulativeDistances;
  String _routeSignature = '';
  int _segmentIndex = 0;
  double _distanceM = -1.0;
  // 2026-06-12 (vucko Geraete-Video Stop-and-Go): Glide-Distanz. Das
  // Projektions-ZIEL springt am echten 1Hz-GPS pro Fix (Kalman-Retarget) —
  // direkt gerendert ergibt das "rast kurz, steht dann" im Sekundentakt.
  // Google-Architektur: die RENDER-Distanz gleitet pro Frame mit
  // kontinuierlicher Geschwindigkeit aufs Ziel zu; Aufholfehler wird ueber
  // ~1,2s abgebaut, leichtes Vorauslaufen (max ~0,5s Fahrweg) statt
  // Stehenbleiben am Ziel, nie rueckwaerts.
  double _renderDistM = -1.0;
  bool _catchingUp = false;
  DateTime? _lastProjectionAt;
  // 2026-06-13 (vucko Verfahren-"kracht"): Beginn der anhaltenden Heading-
  // Divergenz (GPS-Kurs vs. Routen-Tangente). Beim echten Falsch-Abbiegen
  // waechst die Lateral-Distanz nur mit ~10-20 m/s — bis zum 60m-Release-
  // Gate klebte der Puck ~4s sichtbar falsch auf der Route. Divergiert der
  // Kurs klar (>65 Grad) UND ist der Fahrer schon >22m daneben, wird der
  // Lock nach 0,9s freigegeben (Kreisverkehr-sicher: dort bleibt die
  // Lateral-Distanz klein).
  DateTime? _headingDivergenceSince;

  List<double>? get cumulativeDistances => _cumulativeDistances;
  int get segmentIndex => _segmentIndex;

  /// Distanz, an der GERENDERT wird (Puck, Kamera, Linien-Schnitt) — die
  /// geglättete Glide-Distanz, nicht das rohe Projektions-Ziel.
  double get distanceM => _renderDistM;

  bool ensureRoute(List<List<double>> coordinates) {
    final signature = _routeSignatureFor(coordinates);
    if (identical(_coordinates, coordinates) && _routeSignature == signature) {
      return false;
    }
    _coordinates = coordinates;
    _routeSignature = signature;
    resetLock();
    if (coordinates.length < 2) {
      _cumulativeDistances = null;
      return true;
    }

    final cumulative = List<double>.filled(coordinates.length, 0.0);
    for (var i = 1; i < coordinates.length; i++) {
      cumulative[i] =
          cumulative[i - 1] +
          geo.Geolocator.distanceBetween(
            coordinates[i - 1][1],
            coordinates[i - 1][0],
            coordinates[i][1],
            coordinates[i][0],
          );
    }
    _cumulativeDistances = cumulative;
    return true;
  }

  String _routeSignatureFor(List<List<double>> coordinates) {
    final length = coordinates.length;
    if (length == 0) return '0';
    if (length == 1) return '1:${_pointSignature(coordinates.first)}';

    final sampleIndexes = <int>{
      0,
      length ~/ 4,
      length ~/ 2,
      (length * 3) ~/ 4,
      length - 1,
    };
    return [
      length,
      for (final index in sampleIndexes) _pointSignature(coordinates[index]),
    ].join('|');
  }

  String _pointSignature(List<double> point) {
    if (point.length < 2) return 'invalid';
    return '${point[0].toStringAsFixed(7)},${point[1].toStringAsFixed(7)}';
  }

  void resetLock() {
    _segmentIndex = 0;
    _distanceM = -1.0;
    _renderDistM = -1.0;
    _catchingUp = false;
    _lastProjectionAt = null;
    _headingDivergenceSince = null;
  }

  /// 2026-06-14 (vucko Re-Dock-Trim, Geraete-Screenshot „Strecke vor UND hinter
  /// mir"): Ankert den Lock nach einem Wieder-Andocken auf die re-gesnappte
  /// Routen-Distanz [distanceM]. Der Lock ist sonst MONOTON und friert bei
  /// Off-Route ein (project() liefert null, kein Rueckwaerts) — der Linien-
  /// Schnitt (= [distanceM] / _renderDistM) blieb damit hinter dem echten Puck
  /// kleben, der abgefahrene Teil blieb rot. Der globale Re-Snap im
  /// Aufrufer rueckt zwar _currentRouteIndex vor, fasste den Lock aber NIE an.
  ///
  /// Setzt das Projektions-ZIEL auf d; die sichtbare Render-Distanz gleitet im
  /// project()-Glide zuegig nach (Schnitt UND Puck teilen _renderDistM → sie
  /// bleiben zusammen, kein Gap). War der Lock zuvor freigegeben
  /// (_renderDistM < 0, z. B. Heading-Divergenz-Release), wird hart gesetzt —
  /// dann gibt es keine Zwischen-Distanz zum Hingleiten.
  void reanchorToDistance(double distanceM) {
    final cum = _cumulativeDistances;
    if (cum == null || cum.isEmpty) return;
    final d = distanceM.clamp(0.0, cum.last).toDouble();
    _distanceM = d;
    _segmentIndex = _segmentIndexForDistance(d);
    if (_renderDistM < 0) {
      _renderDistM = d;
      _catchingUp = false;
    } else {
      // Aufhol-Modus: der Glide zieht _renderDistM in ~0,5s auf d, statt
      // sekundenlang hinterherzukriechen (eigene Hysterese in project()).
      _catchingUp = true;
    }
    _headingDivergenceSince = null;
  }

  /// 2026-06-23 (vucko 2-Geräte-Video „Nav-Freeze bei GPS-Verlust"): Schiebt die
  /// Render-Distanz während einer GPS-Lücke MONOTON vorwärts (Dead-Reckoning
  /// entlang der Route), damit Puck + Linie weitergleiten statt einzufrieren.
  /// Nur vorwärts, auf das Routenende geclampt; zieht [_distanceM] mit, damit ein
  /// späterer project() nicht zurückspringt. Greift NUR während eines bestätigten
  /// GPS-Stalls (der Aufrufer gated streng) — der Normalpfad ist unberührt.
  void glideRenderForward(double targetDistanceM) {
    final cum = _cumulativeDistances;
    if (cum == null || cum.isEmpty || _renderDistM < 0) return;
    final maxD = cum.last;
    final d = targetDistanceM.clamp(_renderDistM, maxD).toDouble();
    if (d <= _renderDistM) return;
    _renderDistM = d;
    if (d > _distanceM) _distanceM = d;
    _segmentIndex = _segmentIndexForDistance(d);
    _catchingUp = false;
  }

  RouteRenderLockProjection? project({
    required List<List<double>> coordinates,
    required double latitude,
    required double longitude,
    required bool routeConfirmed,
    required int currentRouteIndex,
    required double speedMps,
    DateTime? timestamp,
    double? headingDeg,
  }) {
    if (coordinates.length < 2 || !routeConfirmed) return null;
    ensureRoute(coordinates);
    final cumulative = _cumulativeDistances;
    if (cumulative == null) return null;

    final cosLat = math.cos(latitude * math.pi / 180.0);
    final hasLock = _distanceM >= 0.0;
    final previousDistanceM = _distanceM;
    final previousSegmentIndex = _segmentIndex;
    var searchDistanceM = _distanceM;
    var searchSegmentIndex = _segmentIndex;
    if (hasLock && currentRouteIndex > _segmentIndex) {
      final idx = currentRouteIndex.clamp(0, cumulative.length - 1).toInt();
      final idxDist = cumulative[idx];
      if (idxDist > searchDistanceM + maxAheadWindowMeters) {
        searchSegmentIndex = math.min(idx, coordinates.length - 2);
        searchDistanceM = idxDist;
      }
    } else if (!hasLock) {
      // 2026-06-23 (vucko 2-Geräte-Video „komischer Start: Lasso/Dogleg"): Die
      // ERST-Akquise suchte über die GANZE Route (_windowFor mit centerDistanceM<0).
      // Auf einem selbstüberlappenden Rundkurs liegt der Puck am Start nah an
      // Start UND Rückweg-Leg — die Voll-Suche rastete dann aufs FERNE Rückweg-
      // Segment ein, das 3km-Fenster begann dort → sichtbarer Lasso-/Dogleg-Spike
      // am Puck, der erst der Reroute heilte. Erst-Akquise stattdessen um
      // currentRouteIndex bounden (= wo der Fahrer real auf der Route ist; beim
      // Fahrtstart 0, nach Reroute-Commit der Re-Anchor-Index). Greift NUR vor dem
      // ersten Lock; ein bestehender Lock ist monoton und davon unberührt.
      final hintIdx = currentRouteIndex.clamp(0, coordinates.length - 2).toInt();
      searchSegmentIndex = hintIdx;
      searchDistanceM = cumulative[hintIdx];
    }

    final primaryWindow = _windowFor(
      coordinates: coordinates,
      cumulative: cumulative,
      centerDistanceM: searchDistanceM,
      centerSegmentIndex: searchSegmentIndex,
      speedMps: speedMps,
    );
    var best = _searchBestProjection(
      coordinates: coordinates,
      cumulative: cumulative,
      latitude: latitude,
      longitude: longitude,
      cosLat: cosLat,
      from: primaryWindow.from,
      to: primaryWindow.to,
    );
    final usedReanchorWindow =
        hasLock && searchSegmentIndex != previousSegmentIndex;
    if (usedReanchorWindow) {
      final farFailed =
          best.segment < 0 || best.lateralMeters > lateralMaxMeters;
      final fallbackWindow = _windowFor(
        coordinates: coordinates,
        cumulative: cumulative,
        centerDistanceM: previousDistanceM,
        centerSegmentIndex: previousSegmentIndex,
        speedMps: speedMps,
      );
      final nearBest = _searchBestProjection(
        coordinates: coordinates,
        cumulative: cumulative,
        latitude: latitude,
        longitude: longitude,
        cosLat: cosLat,
        from: fallbackWindow.from,
        to: fallbackWindow.to,
      );
      // 2026-06-16 (vucko Standort-Sprung 200-300m): Der Index-Re-Anchor schob das
      // Such-Zentrum weit voraus. Liegt das GPS in Wahrheit weiter NAH bei der
      // bisherigen Position (selbstüberlappender Rundkurs / Parallelspur — das GPS
      // passt geometrisch auf BEIDE Legs), darf der Puck NICHT auf das ferne Leg
      // springen und dann 200-300 m vorne „warten". Wir nehmen das NAHE Ergebnis,
      // wenn es akzeptabel ist UND deutlich weniger weit voraus liegt — oder wenn
      // das ferne ganz versagt. Bei einem ECHTEN GPS-Sprung (Tunnelausfahrt)
      // versagt das nahe Fenster (GPS ist wirklich weit weg) → das ferne bleibt.
      final nearAcceptable =
          nearBest.segment >= 0 &&
          nearBest.lateralMeters <= lateralReleaseMeters;
      if (nearAcceptable &&
          (farFailed || nearBest.distanceM < best.distanceM - 30.0)) {
        best = nearBest;
      }
    }

    var bestDistanceM = best.distanceM;
    var bestSegment = best.segment;
    final lateralMeters = best.lateralMeters;
    // Hysterese: Akquise streng, Halten grosszuegig (Autobahn-GPS-Drift).
    final lateralGate = hasLock ? lateralReleaseMeters : lateralMaxMeters;
    if (bestSegment < 0 || lateralMeters > lateralGate) {
      return null;
    }

    // Heading-Divergenz-Release (siehe Feld-Kommentar): klarer Gegen-Kurs +
    // bereits deutlich neben der Linie -> Lock nach 0,9s loslassen, damit der
    // Puck beim Verfahren ehrlich der echten Position folgt statt bis 60m
    // lateral "festzukleben" und dann zu springen.
    if (hasLock &&
        headingDeg != null &&
        headingDeg.isFinite &&
        headingDeg >= 0.0 &&
        speedMps.isFinite &&
        speedMps > 3.0 &&
        lateralMeters > 22.0 &&
        timestamp != null) {
      final segBearing = _segmentBearingDeg(bestSegment);
      var diff = (headingDeg - segBearing).abs() % 360.0;
      if (diff > 180.0) diff = 360.0 - diff;
      if (diff > 65.0) {
        _headingDivergenceSince ??= timestamp;
        // 2026-06-13 (vucko Google/Apple-Bar-Review F6-1): 900→700ms. Mit der
        // lateralen Wachstumsdynamik ergab 0,9s ~1,2s Gesamt-Klebezeit;
        // Google/Apple fühlen sich <1s an. 0,7s + 22m-Gate hält den
        // Kreisverkehr-Schutz (dort bleibt lateral klein) und kommt auf
        // ~0,9s Gesamt — spürbar näher am Gold-Standard.
        if (timestamp.difference(_headingDivergenceSince!) >
            const Duration(milliseconds: 700)) {
          resetLock();
          return null;
        }
      } else {
        _headingDivergenceSince = null;
      }
    } else {
      _headingDivergenceSince = null;
    }

    if (hasLock && bestDistanceM < previousDistanceM) {
      bestDistanceM = previousDistanceM;
      bestSegment = previousSegmentIndex;
    }
    final speed = speedMps.isFinite ? speedMps.clamp(0.0, 60.0) : 0.0;
    // Anti-Teleport fuer das Projektions-ZIEL. Der externe Matcher
    // (currentRouteIndex) ist nur noch eine enge Plausibilitaetsstuetze, kein
    // Freifahrtschein bis zum naechsten Vertex. Auf langen GraphHopper-Segmenten
    // kann currentRouteIndex+1 naemlich 100-300 m voraus liegen; genau dort zog
    // der sichtbare Puck im Geraetevideo kurz nach vorne und wartete dann.
    // Darum wird jeder Vorwaertssprung mit bekanntem Frame-Timing zeitbasiert
    // gedeckelt. Explizite Re-Dock-Korrekturen nutzen reanchorToDistance() und
    // bleiben weiterhin als schneller, animierter Catch-up moeglich.
    // 2026-06-12: frueher "+2.0m PRO AUFRUF" — bei 60fps entsprach das
    // 120 m/s Drift-Budget, bei 1Hz nur 2 m/s: frameraten-abhaengig und
    // damit gleichzeitig zu lasch (Frames) und zu streng (Fixe).
    if (hasLock && timestamp != null && _lastProjectionAt != null) {
      final clampDtSeconds = math
          .max(
            0.0,
            timestamp.difference(_lastProjectionAt!).inMilliseconds / 1000.0,
          )
          .clamp(0.0, 2.0)
          .toDouble();
      final corroboratedIdx = currentRouteIndex
          .clamp(0, cumulative.length - 1)
          .toInt();
      final currentIdxDist = cumulative[corroboratedIdx];
      final indexSlackM = math.max(14.0, speed * 0.45);
      final indexCeiling = currentIdxDist + indexSlackM;
      final maxForwardDistance =
          previousDistanceM + (speed * 2.2 + 3.0) * clampDtSeconds;
      final ceiling = math.max(indexCeiling, maxForwardDistance);
      if (bestDistanceM > ceiling) {
        bestDistanceM = ceiling;
        bestSegment = _segmentIndexForDistance(bestDistanceM);
      }
    }

    _segmentIndex = bestSegment;
    _distanceM = bestDistanceM;

    // Glide: Render-Distanz pro Frame mit kontinuierlicher Geschwindigkeit
    // Richtung Ziel bewegen. v = Fahrgeschwindigkeit + Aufholterm (Fehler
    // ueber ~1,2s abbauen), gedeckelt auf das 1,6-fache (+8 m/s Reserve fuer
    // Stand-Anfahrt). Leichtes Vorauslaufen bis ~0,5s Fahrweg ist erlaubt
    // (kein sichtbarer Stopp am Ziel zwischen zwei Fixes), rueckwaerts nie.
    var dtSeconds = 1.0 / 60.0;
    var rawGapSeconds = dtSeconds;
    var hasFrameTiming = false;
    if (timestamp != null && _lastProjectionAt != null) {
      hasFrameTiming = true;
      rawGapSeconds =
          timestamp.difference(_lastProjectionAt!).inMilliseconds / 1000.0;
      dtSeconds = rawGapSeconds.clamp(0.0, 0.5).toDouble();
    }
    if (_renderDistM < 0) {
      _renderDistM = bestDistanceM;
    } else {
      final err = bestDistanceM - _renderDistM;
      // Frame-Kette = die Projektion laeuft kontinuierlich (Timing bekannt,
      // Abstand <=0,3s, also Kamera-Frames). Nur OHNE Frame-Kette war kein
      // Gleiten sichtbar — dann ist Direkt-Aufschliessen unsichtbar/richtig.
      final hasFrameChain = hasFrameTiming && rawGapSeconds <= 0.3;
      if (rawGapSeconds > 1.0 || (err.abs() > 80.0 && !hasFrameChain)) {
        // Echte Projektions-Luecke (>1s ohne Frames, z.B. App-Resume/GPS-
        // Aussetzer) oder grosser Sprung ohne Frame-Kette: direkt
        // aufschliessen — es gab keine Zwischenframes.
        _renderDistM = bestDistanceM;
        _catchingUp = false;
      } else if (_catchingUp || err > speed * 1.5 + 10.0) {
        // Re-Anchor-/Match-KORREKTUR (kein physischer Fahrweg): zuegig
        // exponentiell aufschliessen (~0,5s sichtbar), nicht sekundenlang
        // hinterhergleiten. Eigene Hysterese: einmal im Aufhol-Modus, bleibe
        // bis der Fehler wirklich klein ist (sonst bremst der sanfte Zweig
        // das Aufholen auf halber Strecke aus).
        _catchingUp = err > 5.0;
        if (_catchingUp) {
          final blend = 1.0 - math.exp(-dtSeconds / 0.12);
          // Rate-Deckel: auch ein validierter Riesen-Re-Anchor (z.B. 800m)
          // fliegt pro Frame nur begrenzt (~7m bei 60fps) — sichtbar
          // animiert statt Ein-Frame-Teleport. Typische Korrekturen
          // (<=80m) schliessen weiterhin in ~0,5s.
          _renderDistM += math.min(err * blend, _catchUpMaxMps * dtSeconds);
        } else {
          _renderDistM = bestDistanceM;
        }
      } else {
        final v = (speed + err / 1.2).clamp(0.0, speed * 1.6 + 8.0);
        final advanced = _renderDistM + v * dtSeconds;
        final ceiling = math.max(bestDistanceM + speed * 0.5, _renderDistM);
        _renderDistM = math.min(advanced, ceiling);
      }
    }

    if (timestamp != null &&
        (_lastProjectionAt == null ||
            !timestamp.isBefore(_lastProjectionAt!))) {
      _lastProjectionAt = timestamp;
    }
    final renderSegment = _segmentIndexForDistance(_renderDistM);
    final point = pointAtDistance(_renderDistM);
    if (point == null) return null;

    return RouteRenderLockProjection(
      distanceM: _renderDistM,
      segmentIndex: renderSegment,
      lateralMeters: lateralMeters,
      point: point,
    );
  }

  _RouteSearchWindow _windowFor({
    required List<List<double>> coordinates,
    required List<double> cumulative,
    required double centerDistanceM,
    required int centerSegmentIndex,
    required double speedMps,
  }) {
    if (centerDistanceM < 0.0) {
      return _RouteSearchWindow(0, coordinates.length - 1);
    }

    final speed = speedMps.isFinite ? speedMps.clamp(0.0, 60.0) : 0.0;
    final aheadWindow = (100.0 + speed * 12.0)
        .clamp(minAheadWindowMeters, maxAheadWindowMeters)
        .toDouble();
    final behindDist = centerDistanceM - behindWindowMeters;
    final aheadDist = centerDistanceM + aheadWindow;

    var from = centerSegmentIndex.clamp(0, coordinates.length - 2).toInt();
    while (from > 0 && cumulative[from] > behindDist) {
      from--;
    }

    var to = centerSegmentIndex.clamp(0, coordinates.length - 2).toInt();
    while (to < coordinates.length - 1 && cumulative[to] < aheadDist) {
      to++;
    }
    to = math.max(from + 1, math.min(to, coordinates.length - 1));
    return _RouteSearchWindow(from, to);
  }

  _ProjectionSearchResult _searchBestProjection({
    required List<List<double>> coordinates,
    required List<double> cumulative,
    required double latitude,
    required double longitude,
    required double cosLat,
    required int from,
    required int to,
  }) {
    var bestLateral2 = double.infinity;
    var bestDistanceM = -1.0;
    var bestSegment = -1;
    for (var i = from; i < to; i++) {
      final ax = (coordinates[i][0] - longitude) * 111320.0 * cosLat;
      final ay = (coordinates[i][1] - latitude) * 110540.0;
      final bx = (coordinates[i + 1][0] - longitude) * 111320.0 * cosLat;
      final by = (coordinates[i + 1][1] - latitude) * 110540.0;
      final dx = bx - ax;
      final dy = by - ay;
      final len2 = dx * dx + dy * dy;
      var t = 0.0;
      if (len2 > 1e-9) {
        t = (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
      }
      final px = ax + dx * t;
      final py = ay + dy * t;
      final lateral2 = px * px + py * py;
      if (lateral2 < bestLateral2) {
        bestLateral2 = lateral2;
        bestSegment = i;
        bestDistanceM = cumulative[i] + math.sqrt(len2) * t;
      }
    }

    return _ProjectionSearchResult(
      segment: bestSegment,
      distanceM: bestDistanceM,
      lateralMeters: math.sqrt(bestLateral2),
    );
  }

  /// Kurs (Grad, 0=Nord) des Routen-Segments [segIdx] -> [segIdx+1].
  double _segmentBearingDeg(int segIdx) {
    final coords = _coordinates;
    if (coords == null || coords.length < 2) return 0.0;
    final i = segIdx.clamp(0, coords.length - 2);
    final a = coords[i];
    final b = coords[i + 1];
    final lat1 = a[1] * math.pi / 180.0;
    final lat2 = b[1] * math.pi / 180.0;
    final dLng = (b[0] - a[0]) * math.pi / 180.0;
    final y = math.sin(dLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
  }

  int _segmentIndexForDistance(double distanceM) {
    final cumulative = _cumulativeDistances;
    final coordinates = _coordinates;
    if (cumulative == null || coordinates == null || coordinates.length < 2) {
      return _segmentIndex;
    }
    if (distanceM <= 0.0) return 0;
    if (distanceM >= cumulative.last) return coordinates.length - 2;

    var i = _segmentIndex.clamp(0, coordinates.length - 2);
    if (cumulative[i] > distanceM) i = 0;
    while (i < coordinates.length - 2 && cumulative[i + 1] < distanceM) {
      i++;
    }
    return i;
  }

  List<double>? pointAtDistance(double distanceM) {
    final coordinates = _coordinates;
    final cumulative = _cumulativeDistances;
    if (coordinates == null ||
        coordinates.length < 2 ||
        cumulative == null ||
        cumulative.length != coordinates.length) {
      return null;
    }
    if (distanceM <= 0.0) {
      return [coordinates.first[0], coordinates.first[1]];
    }
    if (distanceM >= cumulative.last) {
      return [coordinates.last[0], coordinates.last[1]];
    }

    var i = _segmentIndex.clamp(0, coordinates.length - 2);
    if (cumulative[i] > distanceM) i = 0;
    while (i < coordinates.length - 2 && cumulative[i + 1] < distanceM) {
      i++;
    }

    final segmentLen = cumulative[i + 1] - cumulative[i];
    final f = segmentLen > 0.0
        ? ((distanceM - cumulative[i]) / segmentLen).clamp(0.0, 1.0)
        : 0.0;
    return [
      coordinates[i][0] + (coordinates[i + 1][0] - coordinates[i][0]) * f,
      coordinates[i][1] + (coordinates[i + 1][1] - coordinates[i][1]) * f,
    ];
  }
}
