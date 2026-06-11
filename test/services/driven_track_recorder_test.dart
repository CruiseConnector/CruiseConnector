import 'package:cruise_connect/data/services/driven_track_recorder.dart';
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DrivenTrackRecorder', () {
    test('sammelt echte GPS-Samples und berechnet Distanz daraus', () {
      final recorder = DrivenTrackRecorder();
      final start = DateTime.utc(2026, 5, 9, 10);

      expect(
        recorder.addSample(
          latitude: 47.5000,
          longitude: 9.7000,
          timestamp: start,
          accuracyMeters: 5,
        ),
        DrivenTrackSampleResult.accepted,
      );
      expect(
        recorder.addSample(
          latitude: 47.5005,
          longitude: 9.7005,
          timestamp: start.add(const Duration(seconds: 5)),
          accuracyMeters: 5,
        ),
        DrivenTrackSampleResult.accepted,
      );

      final snapshot = recorder.snapshot();
      expect(snapshot.drawableSegments, hasLength(1));
      expect(snapshot.coordinates, hasLength(2));
      expect(snapshot.distanceMeters, greaterThan(60));
      expect(snapshot.geometry['type'], 'LineString');
    });

    test('ignoriert ungenaue Punkte und Kleinstbewegungen', () {
      final recorder = DrivenTrackRecorder();
      final start = DateTime.utc(2026, 5, 9, 10);

      recorder.addSample(
        latitude: 47.5000,
        longitude: 9.7000,
        timestamp: start,
        accuracyMeters: 5,
      );

      expect(
        recorder.addSample(
          latitude: 47.50001,
          longitude: 9.70001,
          timestamp: start.add(const Duration(seconds: 1)),
          accuracyMeters: 5,
        ),
        DrivenTrackSampleResult.ignored,
      );
      expect(
        recorder.addSample(
          latitude: 47.5010,
          longitude: 9.7010,
          timestamp: start.add(const Duration(seconds: 2)),
          accuracyMeters: 120,
        ),
        DrivenTrackSampleResult.ignored,
      );

      final snapshot = recorder.snapshot();
      expect(snapshot.coordinates, isEmpty);
      expect(snapshot.distanceMeters, 0);
    });

    test('trennt grosse GPS-Luecken ohne Luftlinie', () {
      final recorder = DrivenTrackRecorder(maxContinuousSegmentMeters: 250);
      final start = DateTime.utc(2026, 5, 9, 10);

      recorder
        ..addSample(
          latitude: 47.5000,
          longitude: 9.7000,
          timestamp: start,
          accuracyMeters: 5,
        )
        ..addSample(
          latitude: 47.5005,
          longitude: 9.7005,
          timestamp: start.add(const Duration(seconds: 5)),
          accuracyMeters: 5,
        );
      final beforeGapDistance = recorder.distanceMeters;

      expect(
        recorder.addSample(
          latitude: 47.5400,
          longitude: 9.7400,
          timestamp: start.add(const Duration(minutes: 2)),
          accuracyMeters: 5,
        ),
        DrivenTrackSampleResult.newSegment,
      );
      recorder.addSample(
        latitude: 47.5405,
        longitude: 9.7405,
        timestamp: start.add(const Duration(minutes: 2, seconds: 5)),
        accuracyMeters: 5,
      );

      final snapshot = recorder.snapshot();
      expect(snapshot.drawableSegments, hasLength(2));
      expect(snapshot.geometry['type'], 'MultiLineString');
      expect(snapshot.gapCount, 1);
      expect(snapshot.maxSegmentMeters, lessThan(100));
      expect(snapshot.distanceMeters, lessThan(beforeGapDistance + 100));
    });

    test('Completion-Result nutzt GPS-Track statt geplanter Route', () {
      final recorder = DrivenTrackRecorder();
      final start = DateTime.utc(2026, 5, 9, 10);
      recorder
        ..addSample(
          latitude: 47.5000,
          longitude: 9.7000,
          timestamp: start,
          accuracyMeters: 5,
        )
        ..addSample(
          latitude: 47.5010,
          longitude: 9.7010,
          timestamp: start.add(const Duration(seconds: 10)),
          accuracyMeters: 5,
        );

      const planned = RouteResult(
        geoJson: '{"type":"LineString","coordinates":[[13,48],[13.1,48.1]]}',
        geometry: {
          'type': 'LineString',
          'coordinates': [
            [13.0, 48.0],
            [13.1, 48.1],
          ],
        },
        coordinates: [
          [13.0, 48.0],
          [13.1, 48.1],
        ],
        maneuvers: [],
        distanceMeters: 15000,
        edgeMeta: {'route_fingerprint': 'planned-fp'},
      );

      final result = recorder.snapshot().toRouteResult(
        source: planned,
        durationSeconds: 120,
      );

      expect(result, isNotNull);
      expect(result!.coordinates.first, [9.7, 47.5]);
      expect(result.coordinates, isNot(contains([13.0, 48.0])));
      expect(result.geometry['type'], 'LineString');
      expect(result.edgeMeta['final_geometry_source'], 'gps_track');
      expect(result.edgeMeta['planned_route_fingerprint'], 'planned-fp');
      expect(result.edgeMeta.containsKey('route_fingerprint'), isFalse);
    });
  });
}
