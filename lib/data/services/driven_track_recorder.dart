import 'dart:convert';
import 'dart:math' as math;

import 'package:cruise_connect/domain/models/route_result.dart';

enum DrivenTrackSampleResult { accepted, ignored, newSegment }

class DrivenTrackRecorder {
  DrivenTrackRecorder({
    this.minDistanceMeters = 4.0,
    this.maxAccuracyMeters = 80.0,
    this.maxContinuousSegmentMeters = 300.0,
    this.maxGapDuration = const Duration(seconds: 20),
    this.maxReasonableSpeedMetersPerSecond = 70.0,
  });

  final double minDistanceMeters;
  final double maxAccuracyMeters;
  final double maxContinuousSegmentMeters;
  final Duration maxGapDuration;
  final double maxReasonableSpeedMetersPerSecond;

  final List<List<_DrivenTrackSample>> _segments = [];
  _DrivenTrackSample? _lastAccepted;
  double _distanceMeters = 0.0;

  double get distanceMeters => _distanceMeters;

  void reset() {
    _segments.clear();
    _lastAccepted = null;
    _distanceMeters = 0.0;
  }

  DrivenTrackSampleResult addSample({
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    double? accuracyMeters,
    double? speedMetersPerSecond,
  }) {
    if (!_isValidCoordinate(latitude, longitude)) {
      return DrivenTrackSampleResult.ignored;
    }
    if (accuracyMeters != null &&
        accuracyMeters.isFinite &&
        accuracyMeters > maxAccuracyMeters) {
      return DrivenTrackSampleResult.ignored;
    }

    final sample = _DrivenTrackSample(
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
    );
    final previous = _lastAccepted;
    if (previous == null) {
      _startNewSegment(sample);
      return DrivenTrackSampleResult.accepted;
    }

    final elapsed = sample.timestamp.difference(previous.timestamp);
    if (elapsed.isNegative) return DrivenTrackSampleResult.ignored;

    final segmentMeters = _distanceMetersBetween(previous, sample);
    if (segmentMeters < minDistanceMeters) {
      return DrivenTrackSampleResult.ignored;
    }

    final elapsedSeconds = elapsed.inMilliseconds / 1000.0;
    final impliedSpeed = elapsedSeconds > 0
        ? segmentMeters / elapsedSeconds
        : double.infinity;
    final reportedSpeed =
        speedMetersPerSecond != null &&
            speedMetersPerSecond.isFinite &&
            speedMetersPerSecond >= 0
        ? speedMetersPerSecond
        : null;
    final impossibleSpeed =
        impliedSpeed > maxReasonableSpeedMetersPerSecond ||
        (reportedSpeed != null &&
            reportedSpeed > maxReasonableSpeedMetersPerSecond * 1.25);
    final hasGap =
        elapsed > maxGapDuration ||
        segmentMeters > maxContinuousSegmentMeters ||
        impossibleSpeed;

    if (hasGap) {
      _startNewSegment(sample);
      return DrivenTrackSampleResult.newSegment;
    }

    _segments.last.add(sample);
    _lastAccepted = sample;
    _distanceMeters += segmentMeters;
    return DrivenTrackSampleResult.accepted;
  }

  DrivenTrackSnapshot snapshot() {
    final drawableSegments = _segments
        .where((segment) => segment.length >= 2)
        .map(
          (segment) => segment
              .map((sample) => [sample.longitude, sample.latitude])
              .toList(growable: false),
        )
        .toList(growable: false);
    return DrivenTrackSnapshot(
      segments: drawableSegments,
      distanceMeters: _distanceMeters,
      acceptedSegmentCount: _segments.length,
      maxSegmentMeters: _maxSegmentMeters(drawableSegments),
    );
  }

  void _startNewSegment(_DrivenTrackSample sample) {
    _segments.add([sample]);
    _lastAccepted = sample;
  }

  bool _isValidCoordinate(double latitude, double longitude) {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  double _maxSegmentMeters(List<List<List<double>>> segments) {
    var maxSegment = 0.0;
    for (final segment in segments) {
      for (var i = 1; i < segment.length; i += 1) {
        maxSegment = math.max(
          maxSegment,
          _haversineMeters(
            segment[i - 1][1],
            segment[i - 1][0],
            segment[i][1],
            segment[i][0],
          ),
        );
      }
    }
    return maxSegment;
  }

  double _distanceMetersBetween(
    _DrivenTrackSample previous,
    _DrivenTrackSample current,
  ) {
    return _haversineMeters(
      previous.latitude,
      previous.longitude,
      current.latitude,
      current.longitude,
    );
  }
}

class DrivenTrackSnapshot {
  const DrivenTrackSnapshot({
    required this.segments,
    required this.distanceMeters,
    required this.acceptedSegmentCount,
    required this.maxSegmentMeters,
  });

  final List<List<List<double>>> segments;
  final double distanceMeters;
  final int acceptedSegmentCount;
  final double maxSegmentMeters;

  List<List<List<double>>> get drawableSegments => segments;

  List<List<double>> get coordinates => segments
      .expand((segment) => segment)
      .map((point) => [point[0], point[1]])
      .toList(growable: false);

  int get gapCount => math.max(0, acceptedSegmentCount - 1);

  bool get hasDrawableTrack => coordinates.length >= 2 && distanceMeters > 0;

  Map<String, dynamic> get geometry {
    if (segments.length == 1) {
      return {'type': 'LineString', 'coordinates': segments.first};
    }
    if (segments.length > 1) {
      return {'type': 'MultiLineString', 'coordinates': segments};
    }
    return const {'type': 'LineString', 'coordinates': <List<double>>[]};
  }

  /// Baut aus dem reinen GPS-Track eine [RouteResult] — OHNE geplante Route.
  ///
  /// 2026-08-03 (vucko Route-Aufzeichnen): Gegenstück zu [toRouteResult]. Beim
  /// Selbst-Aufzeichnen gibt es keine Quell-Route, aus der Manöver, Tempolimits
  /// oder Meta übernommen werden könnten — die Strecke IST das Ergebnis.
  /// Liefert `null`, solange kein zeichenbarer Track existiert (z. B. Fahrt
  /// sofort wieder beendet), damit der Aufrufer gar nicht erst speichert.
  RouteResult? toStandaloneRouteResult({required double? durationSeconds}) {
    if (!hasDrawableTrack) return null;

    final trackGeometry = geometry;
    return RouteResult(
      geoJson: jsonEncode(trackGeometry),
      geometry: trackGeometry,
      coordinates: coordinates,
      maneuvers: const [],
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      distanceKm: distanceMeters / 1000.0,
      edgeMeta: <String, dynamic>{
        'route_source': 'recorded_track',
        'source': 'recorded_track',
        'geometry_source': 'gps_track',
        'final_geometry_source': 'gps_track',
        'driven_track': true,
        'recorded_track': true,
        'driven_track_segments': segments.length,
        'driven_track_gap_count': gapCount,
        'driven_track_coordinate_count': coordinates.length,
        'max_display_segment_m': maxSegmentMeters,
        'distance_meters': distanceMeters,
        'distance_km': distanceMeters / 1000.0,
      },
    );
  }

  RouteResult? toRouteResult({
    required RouteResult source,
    required double? durationSeconds,
  }) {
    if (!hasDrawableTrack) return null;

    final trackCoordinates = coordinates;
    final trackGeometry = geometry;
    final meta = Map<String, dynamic>.from(source.edgeMeta);
    final plannedFingerprint = meta['route_fingerprint'];
    if (plannedFingerprint != null) {
      meta['planned_route_fingerprint'] = plannedFingerprint.toString();
      meta.remove('route_fingerprint');
    }
    meta
      ..['route_source'] = 'driven_track'
      ..['source'] = 'driven_track'
      ..['geometry_source'] = 'gps_track'
      ..['final_geometry_source'] = 'gps_track'
      ..['driven_track'] = true
      ..['driven_track_segments'] = segments.length
      ..['driven_track_gap_count'] = gapCount
      ..['driven_track_coordinate_count'] = trackCoordinates.length
      ..['max_display_segment_m'] = maxSegmentMeters
      ..['distance_meters'] = distanceMeters
      ..['distance_km'] = distanceMeters / 1000.0;

    return RouteResult(
      geoJson: jsonEncode(trackGeometry),
      geometry: trackGeometry,
      coordinates: trackCoordinates,
      maneuvers: source.maneuvers,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      distanceKm: distanceMeters / 1000.0,
      speedLimits: source.speedLimits,
      edgeMeta: meta,
    );
  }
}

class _DrivenTrackSample {
  const _DrivenTrackSample({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;
}

double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusMeters = 6371000.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degToRad(lat1)) *
          math.cos(_degToRad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _degToRad(double value) => value * math.pi / 180.0;
