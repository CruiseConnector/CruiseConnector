import 'dart:io';

import 'package:cruise_connect/data/services/route_share_export_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('externer Route-Export bleibt PNG-Flow ohne Community-Post', () {
    final source = File(
      'lib/data/services/route_share_export_service.dart',
    ).readAsStringSync();

    expect(source, contains('ui.PictureRecorder'));
    expect(source, contains('ui.ImageByteFormat.png'));
    expect(source, isNot(contains('XFile')));
    expect(source, isNot(contains('CreatePostPage')));
    expect(source, isNot(contains('SocialService')));
    expect(source, isNot(contains('CommunityProvider')));
  });

  test('Route-Export rendert MultiLineString ohne Luecken-Luftlinie', () async {
    final route = SavedRoute(
      id: 'route-driven',
      createdAt: DateTime.utc(2026, 5, 9),
      style: 'Sport Mode',
      distanceKm: 12.4,
      geometry: const {
        'type': 'MultiLineString',
        'coordinates': [
          [
            [9.7471, 47.5162],
            [9.7500, 47.5200],
          ],
          [
            [9.8100, 47.5500],
            [9.8200, 47.5600],
          ],
        ],
      },
    );

    final png = await RouteShareExportService.buildTransparentRoutePng(
      route: route,
      accent: Colors.red,
      pixelRatio: 1,
    );

    expect(png, isNotEmpty);
  });
}
