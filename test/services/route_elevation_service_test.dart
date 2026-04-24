import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/route_elevation_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('RouteElevationService', () {
    test('summarizeElevations berechnet Anstieg und Abstieg robust', () {
      final summary = RouteElevationService.summarizeElevations([
        500,
        512,
        509,
        533,
        521,
        548,
      ]);

      expect(summary, isNotNull);
      expect(summary!.ascentMeters, greaterThan(0));
      expect(summary.descentMeters, greaterThan(0));
      expect(summary.isEstimated, isFalse);
    });

    test('estimateSummaryFromCoordinates liefert Fallback-Hoehenmeter', () {
      final coordinates = List.generate(
        40,
        (index) => [11.55 + index * 0.003, 48.10 + index * 0.0015],
      );

      final summary = RouteElevationService.estimateSummaryFromCoordinates(
        coordinates,
      );

      expect(summary, isNotNull);
      expect(summary!.ascentMeters, greaterThanOrEqualTo(0));
      expect(summary.isEstimated, isTrue);
      expect(summary.elevations.length, greaterThan(4));
    });

    test(
      'fetchSummary faellt bei API-Fehler auf geschaetzte Hoehenmeter zurueck',
      () async {
        final client = MockClient(
          (_) async => http.Response('{"error":"unavailable"}', 503),
        );
        final service = RouteElevationService(client: client);
        final coordinates = List.generate(
          30,
          (index) => [11.60 + index * 0.002, 48.12 + index * 0.0012],
        );

        final summary = await service.fetchSummary(coordinates);

        expect(summary, isNotNull);
        expect(summary!.isEstimated, isTrue);
        expect(summary.ascentMeters, greaterThanOrEqualTo(0));
      },
    );
  });
}
