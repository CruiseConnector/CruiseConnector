// Selbst aufgezeichnete Strecke → RouteResult (2026-08-03, vucko).
//
// Gegenstück zu driven_track_recorder_test.dart: dort wird der Track gegen eine
// GEPLANTE Route gelegt (toRouteResult), hier steht er für sich allein
// (toStandaloneRouteResult) — das ist der Fall „Route selbst aufzeichnen", wo es
// gar keine geplante Route gibt.
//
// Ausführen: flutter test test/services/driven_track_recorder_standalone_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/driven_track_recorder.dart';

/// Fährt eine gerade Strecke nach Norden, ein Sample pro Sekunde.
DrivenTrackRecorder _recordStraightLine({int samples = 5}) {
  final recorder = DrivenTrackRecorder();
  final start = DateTime.utc(2026, 8, 3, 10);
  for (var i = 0; i < samples; i += 1) {
    recorder.addSample(
      latitude: 47.5000 + i * 0.0005,
      longitude: 9.7000,
      timestamp: start.add(Duration(seconds: i)),
      accuracyMeters: 5,
    );
  }
  return recorder;
}

void main() {
  group('toStandaloneRouteResult', () {
    test('baut aus einem durchgehenden Track eine LineString-Route', () {
      final snapshot = _recordStraightLine().snapshot();

      final result = snapshot.toStandaloneRouteResult(durationSeconds: 240);

      expect(result, isNotNull);
      expect(result!.geometry['type'], 'LineString');
      expect(result.coordinates, hasLength(5));
      expect(result.durationSeconds, 240);
      // Distanz kommt aus dem Track selbst, nicht aus einer Planung.
      expect(result.distanceMeters, snapshot.distanceMeters);
      expect(result.distanceKm, closeTo(snapshot.distanceMeters / 1000, 1e-9));
      // Aufgezeichnet heisst: keine Manöver und keine Tempolimits.
      expect(result.maneuvers, isEmpty);
      expect(result.speedLimits, isEmpty);
      // geoJson muss zur geometry passen (wird so gespeichert und gerendert).
      expect(jsonDecode(result.geoJson), result.geometry);
    });

    test('markiert die Herkunft in edgeMeta', () {
      final snapshot = _recordStraightLine().snapshot();

      final meta = snapshot.toStandaloneRouteResult(durationSeconds: 60)!.edgeMeta;

      expect(meta['route_source'], 'recorded_track');
      expect(meta['recorded_track'], isTrue);
      expect(meta['geometry_source'], 'gps_track');
      expect(meta['driven_track_coordinate_count'], 5);
      expect(meta['driven_track_gap_count'], 0);
      // Kein route_fingerprint einer geplanten Route — es gab keine.
      expect(meta.containsKey('route_fingerprint'), isFalse);
    });

    test('wird bei einer Lücke im Track zu MultiLineString', () {
      final recorder = DrivenTrackRecorder();
      final start = DateTime.utc(2026, 8, 3, 10);
      // Erstes Segment.
      recorder.addSample(
        latitude: 47.5000,
        longitude: 9.7000,
        timestamp: start,
        accuracyMeters: 5,
      );
      recorder.addSample(
        latitude: 47.5005,
        longitude: 9.7000,
        timestamp: start.add(const Duration(seconds: 5)),
        accuracyMeters: 5,
      );
      // Signalabriss: weit weg und lange her → neues Segment.
      recorder.addSample(
        latitude: 47.6000,
        longitude: 9.8000,
        timestamp: start.add(const Duration(minutes: 10)),
        accuracyMeters: 5,
      );
      recorder.addSample(
        latitude: 47.6005,
        longitude: 9.8000,
        timestamp: start.add(const Duration(minutes: 10, seconds: 5)),
        accuracyMeters: 5,
      );

      final result = recorder.snapshot().toStandaloneRouteResult(
        durationSeconds: 900,
      );

      expect(result, isNotNull);
      expect(result!.geometry['type'], 'MultiLineString');
      expect(result.edgeMeta['driven_track_gap_count'], 1);
    });

    test('liefert null, wenn nichts Zeichenbares aufgezeichnet wurde', () {
      // Sofort wieder beendet: ein einzelner Punkt ergibt keine Strecke.
      final recorder = DrivenTrackRecorder();
      recorder.addSample(
        latitude: 47.5,
        longitude: 9.7,
        timestamp: DateTime.utc(2026, 8, 3, 10),
        accuracyMeters: 5,
      );

      expect(
        recorder.snapshot().toStandaloneRouteResult(durationSeconds: 5),
        isNull,
      );
      expect(
        DrivenTrackRecorder().snapshot().toStandaloneRouteResult(
          durationSeconds: null,
        ),
        isNull,
      );
    });
  });
}
